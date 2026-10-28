import Foundation

public struct Candidate: Equatable {
    public let text: String
    /// Number of taps this candidate consumes from the start of the input.
    public let tapCount: Int
    public let syllables: [UInt16]
    /// True when at least one key was auto-corrected to produce this candidate.
    public let corrected: Bool
    public let score: Double
    /// The keys this candidate stands for, one per consumed tap (empty when it used an abbreviation or a
    /// half-typed syllable). Used to learn the personal touch offset.
    public var intendedKeys: [Character] = []
    /// An English word offered in Chinese mode (中英混输); committed as written, never learned as pinyin.
    public var isEnglish = false
}

/// The two ways of spelling a syllable this keyboard accepts.
public enum PinyinScheme: Int, CaseIterable {
    /// 小鹤双拼: every syllable is exactly two keys.
    case xiaohe = 0
    /// 全拼: syllables spelled out (1–6 keys), with initials-only abbreviations (简拼) and a half-typed last syllable.
    case quanpin = 1
}

/// Pinyin decoder with touch-position-aware auto-correction, for 小鹤双拼 and 全拼.
///
/// The taps are first cut into syllable *spans* — every way a run of taps can spell a syllable, given the touch
/// model's plausible keys for each tap. Words from the lexicon are then matched over chains of spans and scored:
///   score = ln(freq) − wordPenalty + Σ spatial log-prob − correctionPenalty·(#corrected syllables) − abbreviation cost
/// so a key is only changed when the touch geometry *and* the language agree. For 小鹤 the spans are fixed two-tap
/// pairs; for 全拼 a syllable trie walks the taps and the same tap run may be cut several ways (xian / xi'an).
public final class Decoder {
    public let lexicon: Lexicon
    public var user: UserDictionary?
    public var scheme: PinyinScheme = .xiaohe

    public var correctionEnabled = true
    public var spatialWeight = 1.0
    public var correctionPenalty = 1.5
    public var wordPenalty = 26.0   // with the language model (each word also pays its non-collocation cost)
    /// What learning adds. A word the lexicon has gets its own frequency plus  userWeight·ln(1 + times picked),
    /// at most `userCap` (a single character at most a quarter of it) — so picking 得 once in 过得 lifts 得 a little
    /// without pushing 的 out of every other sentence. A phrase of the user's own (not in the lexicon) starts from
    /// `userPhraseScore`, an ordinary word's frequency.
    public var userWeight = 2.0
    public var userCap = 8.0
    /// A word of two or more syllables the user picked starts this much ahead (a picked word should come first next
    /// time; homophone words rarely collide the way single characters do).
    public var userWordBoost = 3.0
    public var userPhraseScore = 9.0
    /// 中英混输: English words for the typed letters, ranked against the Chinese readings by frequency.
    public var english: EnglishLexicon?
    public var englishEnabled = true
    /// Which words go together (Rime octagram language model): each word of a sentence is scored against the text
    /// before it — inside the sentence, and for its first word the text already in the field (`leftContext`).
    public var grammar: Grammar?
    public var grammarWeight = 1.0
    /// The language model weighs less on a word whose keys were corrected: it chooses between words the keys spell,
    /// it does not talk the keyboard into changing keys to make a likelier phrase.
    public var grammarCorrectedFactor = 0.5
    /// The text just before the cursor (a few characters), so the first word is also read in context.
    public var leftContext: [Character] = []
    /// Cost of reading the letters as English in Chinese mode (English is the less likely intent there).
    public var englishPenalty = 3.0
    /// Extra cost of a completion (the word is longer than what was typed).
    public var englishCompletionPenalty = 3.0
    /// Offer a longer word for a prefix (iph → iPhone). Off: a plain input method shows only what was typed.
    public var englishCompletions = false
    /// Words usually written with capitals in Chinese text (iOS, iPhone, OK…) are typed on purpose: a bonus.
    public var englishCasedBonus = 3.0
    public var maxSyllableAlternatives = 6
    public var pruneMargin = 7.0
    public var beam = 4
    /// 全拼: cost of a syllable typed as its initial only (简拼), and of a half-typed last syllable.
    public var abbreviationPenalty = 6.0
    public var prefixPenalty = 0.4
    /// 九宫格: extra cost of reading a keypad key as a whole syllable's initial (every key holds several initials,
    /// so abbreviations there are far more often a misreading than on the full keyboard).
    public var t9AbbreviationExtra = 3.4
    /// 九宫格: the least lexicon score (ln of its frequency) a word of two or more syllables needs to be offered.
    public var t9MinWordScore = -Double.infinity
    /// 九宫格: extra cost of reading the last keys as the start of a longer syllable (on the keypad a half-typed
    /// syllable matches far more spellings, so a reading that ends on whole syllables should usually win).
    public var t9PrefixExtra = 3.0
    /// How much of a word's own frequency the language model takes back when it scores the word in context.
    public var unigramDiscount = 0.5
    public var unigramCenter = 10.0
    /// The model's counts are read against how much it has seen after the context (P(word | context) rather than
    /// a joint count): a common context no longer lends its own frequency to whatever follows it.
    public var contextNormalisation = 0.6

    public init(lexicon: Lexicon, user: UserDictionary? = nil) {
        self.lexicon = lexicon
        self.user = user
    }

    public struct Result {
        public var candidates: [Candidate]
        /// Pinyin of the first candidate, e.g. "ni hao d".
        public var preedit: String
    }

    /// One way a run of taps [start, end) spells a syllable.
    struct Span {
        let end: Int
        let id: UInt16
        let spatial: Double       // includes correction / abbreviation / prefix costs
        let corrected: Bool
        let kind: UInt8           // 0 full spelling, 1 half-typed last syllable, 2 abbreviation (initial only)
    }

    struct Edge {
        let start: Int
        let end: Int
        let score: Double
        let corrected: Bool
        let entry: Int            // >= 0 lexicon entry, < 0 user item
        let userText: String?
        let ids: [UInt16]
        let cuts: [Int]           // end tap of each syllable
        let kinds: [UInt8]
    }

    // MARK: - Spans

    /// spans[i] = every syllable that can start at tap i.
    func spans(_ taps: [Tap]) -> [[Span]] {
        scheme == .xiaohe ? xiaoheSpans(taps) : quanpinSpans(taps)
    }

    private func alternatives(_ t: Tap) -> [(key: Character, logp: Double)] {
        t.group ? t.alternatives : correctionEnabled ? t.alternatives : [(t.key, 0.0)]
    }
    /// Whether reading tap `t` as key `k` is a correction (never for a 九宫格 key: all its letters are meant).
    @inline(__always) private func isCorrection(_ k: Character, _ t: Tap) -> Bool { !t.group && k != t.key }

    /// 全拼 syllable boundaries set with 分词 ('): no syllable may run across one (positions in the filtered taps).
    private var boundaries = Set<Int>()

    private func pruned(_ best: [UInt16: Span], limit: Int) -> [Span] {
        var list = best.values.sorted { $0.spatial > $1.spatial }
        if let top = list.first?.spatial { list = list.filter { $0.spatial >= top - pruneMargin } }
        return Array(list.prefix(limit))
    }

    private func xiaoheSpans(_ taps: [Tap]) -> [[Span]] {
        let n = taps.count
        var out = [[Span]](repeating: [], count: n)
        var i = 0
        while i + 1 < n {
            let a = taps[i], b = taps[i + 1]
            var best: [UInt16: Span] = [:]
            for (ka, la) in alternatives(a) {
                for (kb, lb) in alternatives(b) {
                    guard let ids = lexicon.codeToSyllables[String([ka, kb])] else { continue }
                    let corrected = isCorrection(ka, a) || isCorrection(kb, b)
                    let s = spatialWeight * (la + lb) - (corrected ? correctionPenalty : 0)
                    for id in ids where (best[id]?.spatial ?? -.infinity) < s {
                        best[id] = Span(end: i + 2, id: id, spatial: s, corrected: corrected, kind: 0)
                    }
                }
            }
            // 九宫格: every syllable on the two keys is equally likely here; the words decide, so keep them all
            out[i] = pruned(best, limit: a.group || b.group ? 96 : maxSyllableAlternatives)
            i += 2
        }
        if n % 2 == 1, let t = taps.last {
            // a dangling first key: any syllable whose code starts with it
            var best: [UInt16: Span] = [:]
            for (k, l) in alternatives(t) {
                let corrected = isCorrection(k, t)
                let s = spatialWeight * l - (corrected ? correctionPenalty : 0)
                for id in lexicon.firstKeyToSyllables[k] ?? [] where (best[id]?.spatial ?? -.infinity) < s {
                    best[id] = Span(end: n, id: id, spatial: s, corrected: corrected, kind: 1)
                }
            }
            out[n - 1] = pruned(best, limit: 400)
        }
        return out
    }

    // 全拼: a trie of syllable spellings
    private final class TrieNode {
        var children: [Character: TrieNode] = [:]
        var ids: [UInt16] = []          // syllables spelled exactly by this path
        var below: [UInt16] = []        // every syllable spelled through this node (for a half-typed syllable)
    }
    private lazy var trie: TrieNode = {
        let root = TrieNode()
        for (i, s) in lexicon.syllables.enumerated() {
            var node = root
            for c in s {
                let next = node.children[c] ?? TrieNode()
                node.children[c] = next
                node = next
                node.below.append(UInt16(i))
            }
            node.ids.append(UInt16(i))
        }
        return root
    }()
    private static let initials: Set<Character> = Set("bpmfdtnlgkhjqxrzcswy")
    private static let vowels: Set<Character> = Set("aeiouv")
    /// 全拼: extra cost of growing a fully spelled syllable into a longer one (xian → xiang).
    public var completionPenalty = 2.5
    /// On the full keyboard the keys spell exactly what was meant: when they already end on a whole syllable, a
    /// word that needs a longer one (药店买 for yaodianma) comes after every reading of the keys as typed.
    public var fullCompletionPenalty = 15.0

    private func quanpinSpans(_ taps: [Tap]) -> [[Span]] {
        let n = taps.count
        var out = [[Span]](repeating: [], count: n)
        for i in 0..<n {
            var best: [Int: Span] = [:]                       // key: end * 1024 + id
            func emit(_ s: Span) {
                let k = s.end * 1024 + Int(s.id)
                if (best[k]?.spatial ?? -.infinity) < s.spatial { best[k] = s }
            }
            // walk the trie with every plausible key per tap
            struct State { let node: TrieNode; let score: Double; let corrected: Bool }
            var states = [State(node: trie, score: 0, corrected: false)]
            var pos = i
            while pos < n && !states.isEmpty {
                var next: [State] = []
                let t = taps[pos]
                for st in states {
                    for (k, l) in alternatives(t) {
                        guard let child = st.node.children[k] else { continue }
                        next.append(State(node: child, score: st.score + spatialWeight * l, corrected: st.corrected || isCorrection(k, t)))
                    }
                }
                if let top = next.map({ $0.score }).max() { next = next.filter { $0.score >= top - pruneMargin } }
                if next.count > 24 { next = Array(next.sorted { $0.score > $1.score }.prefix(24)) }
                pos += 1
                for st in next {
                    let cost = st.score - (st.corrected ? correctionPenalty : 0)
                    for id in st.node.ids { emit(Span(end: pos, id: id, spatial: cost, corrected: st.corrected, kind: 0)) }
                    if pos == n {
                        // still typing the last syllable: anything it can grow into — but when the keys already spell
                        // a whole syllable (xian), that syllable comes first and the longer ones (xiang) after
                        let extra = st.node.ids.isEmpty ? prefixPenalty + (taps[i].group ? t9PrefixExtra : 0)
                            : prefixPenalty + (taps[i].group ? completionPenalty + t9PrefixExtra : fullCompletionPenalty)
                        for id in st.node.below where !st.node.ids.contains(id) {
                            emit(Span(end: pos, id: id, spatial: cost - extra, corrected: st.corrected, kind: 1))
                        }
                    }
                }
                states = next
                if boundaries.contains(pos) { break }   // 分词: the syllable must end here
            }
            // 简拼: an initial standing for a whole syllable (zh / ch / sh count as one initial); typed keys only, and
            // only when no vowel follows — "nh" is 你好, while in "ni" the n simply starts a spelled-out syllable
            // On a 九宫格 key every initial on it may be meant (and whether a vowel follows is unknown), at a little
            // more cost; keys typed on the full keyboard abbreviate only as typed.
            let t0 = taps[i]
            let heads0: [Character] = t0.group ? t0.alternatives.map { $0.key }.filter { Self.initials.contains($0) }
                                               : (Self.initials.contains(t0.key) ? [t0.key] : [])
            func vowel(_ j: Int) -> Bool { j < n && !taps[j].group && Self.vowels.contains(taps[j].key) }
            func hasH(_ j: Int) -> Bool { j < n && (taps[j].group ? taps[j].alternatives.contains { $0.key == "h" } : taps[j].key == "h") }
            for k0 in heads0 where i + 1 < n {
                var ends: [(end: Int, head: String)] = []
                if !vowel(i + 1) { ends.append((end: i + 1, head: String(k0))) }
                if "zcs".contains(k0), i + 2 < n, hasH(i + 1), !vowel(i + 2), !boundaries.contains(i + 1) {
                    ends.append((end: i + 2, head: String(k0) + "h"))
                }
                let cost = abbreviationPenalty + (t0.group ? t9AbbreviationExtra : 0)
                for (end, head) in ends {
                    for id in trie.children[k0]?.below ?? [] {
                        // a lone z / c / s also stands for zh / ch / sh, as people abbreviate both
                        guard lexicon.syllables[Int(id)].hasPrefix(head) else { continue }
                        emit(Span(end: end, id: id, spatial: -cost, corrected: false, kind: 2))
                    }
                }
            }
            out[i] = best.values.sorted { $0.spatial > $1.spatial }
        }
        return out
    }

    // MARK: - Decode

    public func decode(_ taps: [Tap]) -> Result {
        // 小鹤双拼, plain: with an odd number of keys the last one is the initial of the next syllable, not yet finished.
        // The candidates first carry the reading on through it — what was decoded so far plus the likeliest syllable
        // that key starts (可以 + l → 可以了, 你好 + m → 你好吗), so a long sentence keeps flowing and space commits all
        // of it — then the candidates of the complete pairs alone, then the keys as typed.
        if scheme == .xiaohe, taps.count >= 3, taps.count % 2 == 1, !taps.contains(where: { $0.key == "'" }) {
            boundaries = []
            let n = taps.count
            let r = decodeLetters(Array(taps.dropLast()))
            let raw = String(taps.map { $0.key })
            var cands = r.candidates.filter { $0.tapCount > 0 && $0.score > -.infinity && !$0.isEnglish }
            let full = decodeLetters(taps)
            var ahead: [Candidate] = []
            if !(taps.last!.group) {
                let whole = full.candidates.filter { $0.tapCount == n && !$0.isEnglish && $0.score > -.infinity }
                // keep what the complete pairs already read (the next key must not rewrite it), when it can be kept
                if let lead = cands.first, lead.tapCount == n - 1 {
                    ahead = Array(whole.filter { $0.text.hasPrefix(lead.text) && $0.text.count > lead.text.count }.prefix(2))
                }
                if ahead.isEmpty { ahead = Array(whole.prefix(1)) }
            }
            cands.removeAll { c in ahead.contains { $0.text == c.text } }
            cands.insert(contentsOf: ahead, at: 0)
            // English words cover every key typed (ios → iOS): first when they lead the full reading, else second
            if englishEnabled, english != nil {
                for (k, c) in full.candidates.enumerated() where c.isEnglish && !cands.contains(where: { $0.text == c.text }) {
                    cands.insert(c, at: min(k == 0 ? 0 : 1, cands.count))
                }
            }
            cands.append(Candidate(text: raw, tapCount: n, syllables: [], corrected: false, score: -.infinity))
            return Result(candidates: cands, preedit: r.preedit + " " + String(taps.last!.key))
        }
        // 分词 (') taps only set syllable boundaries: decode the letters, then count the separators back into each
        // candidate's tapCount so committing a candidate removes them too.
        guard taps.contains(where: { $0.key == "'" }) else { boundaries = []; return decodeLetters(taps) }
        var letters: [Tap] = []
        var orig = [0]                // orig[k]: original taps consumed once k letters are (with separators right after)
        boundaries = []
        for (i, t) in taps.enumerated() where t.key != "'" {
            if i > 0, taps[i - 1].key == "'", !letters.isEmpty { boundaries.insert(letters.count) }
            letters.append(t)
            var end = i + 1
            while end < taps.count, taps[end].key == "'" { end += 1 }
            orig.append(end)
        }
        guard !letters.isEmpty else { return Result(candidates: [], preedit: String(repeating: "'", count: taps.count)) }
        let r = decodeLetters(letters)
        boundaries = []
        let cands = r.candidates.map { c -> Candidate in
            var m = Candidate(text: c.text, tapCount: orig[min(c.tapCount, orig.count - 1)], syllables: c.syllables,
                              corrected: c.corrected, score: c.score)
            m.intendedKeys = c.intendedKeys
            m.isEnglish = c.isEnglish
            return m
        }
        return Result(candidates: cands, preedit: r.preedit)
    }

    private func decodeLetters(_ taps: [Tap]) -> Result {
        guard !taps.isEmpty else { return Result(candidates: [], preedit: "") }
        let n = taps.count
        let spansFrom = spans(taps)
        // index: start tap -> syllable id -> spans
        // groups[i]: the syllables that can start at tap i, each with its readings; slot[i * S + id] finds one
        // (a flat table rather than a dictionary per position: no hashing in the innermost loops)
        let S = lexicon.syllables.count
        var groups = [[(id: UInt16, spans: [Span])]](repeating: [], count: n)
        var slot = [Int32](repeating: -1, count: n * S)
        for i in 0..<n {
            for sp in spansFrom[i] {
                let k = i * S + Int(sp.id)
                if slot[k] < 0 { slot[k] = Int32(groups[i].count); groups[i].append((sp.id, [sp])) }
                else { groups[i][Int(slot[k])].spans.append(sp) }
            }
        }

        // Edge buckets keyed by (start, end), each keeping its best `cap` words. `floor` is the score a new word must
        // beat once a bucket is full, checked before an edge is even built (most candidate words never get in).
        // flat arrays indexed by (start, end): `accepts` runs for nearly every lexicon word looked at, so no hashing
        let stride_ = n + 1
        var bucketList = [[Edge]](repeating: [], count: stride_ * stride_)
        var floorArr = [Double](repeating: -.infinity, count: stride_ * stride_ * 2)
        // 九宫格 input is far more ambiguous per key: keep more words per span
        let wide = taps.contains { $0.group } ? (scheme == .xiaohe ? 4 : 1) : 1
        // 九宫格: every key is 3–4 letters, so a weak word (one the lexicon only lists, with no frequency of its own)
        // fits the keys far more often by accident than it is meant; there words need a little real weight
        let minWord = taps.contains { $0.group } ? t9MinWordScore : -Double.infinity
        @inline(__always) func cap(_ start: Int, _ syllables: Int) -> Int { (start == 0 ? (syllables == 1 ? 120 : 40) : 12) * wide }
        // a one-syllable word at the start may join a bucket while it holds fewer than 120; any other word, fewer than
        // its own cap — so each bucket has two bars, by the cap of the word asking
        @inline(__always) func fkey(_ start: Int, _ end: Int, _ syllables: Int) -> Int {
            (start * stride_ + end) * 2 + (start == 0 && syllables == 1 ? 1 : 0)
        }
        @inline(__always) func accepts(_ start: Int, _ end: Int, _ syllables: Int, _ score: Double) -> Bool {
            score > floorArr[fkey(start, end, syllables)]
        }
        func insert(_ e: Edge) {
            let key = e.start * stride_ + e.end
            var list = bucketList[key]
            bucketList[key] = []
            let c = cap(e.start, e.cuts.count)
            if list.count < c {
                list.append(e)
            } else {
                var minIdx = 0
                for j in 1..<list.count where list[j].score < list[minIdx].score { minIdx = j }
                if list[minIdx].score < e.score { list[minIdx] = e }
            }
            var low = -Double.infinity
            if list.count >= cap(e.start, 2) || list.count >= cap(e.start, 1) {
                low = .infinity
                for x in list where x.score < low { low = x.score }
            }
            if list.count >= cap(e.start, 2) { floorArr[fkey(e.start, e.end, 2)] = low }
            if list.count >= cap(e.start, 1) { floorArr[fkey(e.start, e.end, 1)] = low }
            bucketList[key] = list
        }

        // Match a syllable sequence (word) from a first span onwards; calls `found` for every complete chain.
        // Depth-first with one shared path (no arrays built per step); only a chain that may enter a bucket is copied.
        var cutBuf: [Int] = []
        var kindBuf: [UInt8] = []
        cutBuf.reserveCapacity(8); kindBuf.reserveCapacity(8)
        func chains(_ syl: (Int) -> UInt16, count L: Int, first: Span, base: Double,
                    found: (_ end: Int, _ spatial: Double, _ corrected: Bool, _ cuts: [Int], _ kinds: [UInt8]) -> Void) {
            cutBuf.removeAll(keepingCapacity: true); kindBuf.removeAll(keepingCapacity: true)
            cutBuf.append(first.end); kindBuf.append(first.kind)
            func walk(_ k: Int, _ pos: Int, _ sp: Double, _ corr: Bool) {
                if k == L {
                    // a word made only of abbreviations must be at least two syllables; one-syllable abbreviations are noise
                    if L == 1 && kindBuf[0] == 2 { return }
                    found(pos, sp, corr, cutBuf, kindBuf)
                    return
                }
                guard pos < n, kindBuf.last != 1 else { return }
                let si = slot[pos * S + Int(syl(k))]
                guard si >= 0 else { return }
                for s in groups[pos][Int(si)].spans {
                    cutBuf.append(s.end); kindBuf.append(s.kind)
                    walk(k + 1, s.end, sp + s.spatial, corr || s.corrected)
                    cutBuf.removeLast(); kindBuf.removeLast()
                }
            }
            walk(1, first.end, first.spatial, first.corrected)
        }

        // Only start words where a chain of syllables from the beginning can arrive, and from where one can
        // still reach the end (or stop early for a shorter candidate from position 0) — this skips the inside of
        // spelled-out syllables in 全拼 (the "hon" of "zhong").
        var reach = [Bool](repeating: false, count: n + 1)
        reach[0] = true
        for i in 0..<n where reach[i] { for sp in spansFrom[i] { reach[sp.end] = true } }

        for i in 0..<n where reach[i] {
            for first in spansFrom[i] {
                let firstEnd = first.end
                // Single characters (best first: stop at the first that no longer makes the cut). An abbreviation
                // is never a one-character word.
                if first.kind != 2 {
                    for idx in lexicon.singles(first.id) {
                        let base = Double(lexicon.entry(idx).score) / 100 - wordPenalty
                        guard accepts(i, firstEnd, 1, base + first.spatial) else { break }
                        insert(Edge(start: i, end: firstEnd, score: base + first.spatial, corrected: first.corrected, entry: idx,
                                    userText: nil, ids: [], cuts: [firstEnd], kinds: [first.kind]))
                    }
                }
                // Longer words only through the syllables that can start where this one ends (a half-typed syllable
                // is always the last, so it starts no longer word).
                for (sid, seconds) in first.kind != 1 && firstEnd < n ? groups[firstEnd] : [] {
                    let follow = lexicon.followers(first: first.id, second: sid)
                    // two-syllable words: each reading of the second syllable, the words best first
                    if !follow.pairs.isEmpty {
                        for s2 in seconds {
                            let sp = first.spatial + s2.spatial
                            let corr = first.corrected || s2.corrected
                            for idx in follow.pairs {
                                let score = Double(lexicon.entry(idx).score) / 100
                                if score < minWord { break }   // best first: the rest are weaker still
                                let base = score - wordPenalty
                                guard accepts(i, s2.end, 2, base + sp) else { break }
                                insert(Edge(start: i, end: s2.end, score: base + sp, corrected: corr, entry: idx, userText: nil,
                                            ids: [], cuts: [firstEnd, s2.end], kinds: [first.kind, s2.kind]))
                            }
                        }
                    }
                    // three syllables or more: walk the rest of the chain, from where a third syllable could start
                    if !follow.longer.isEmpty {
                        let thirds = seconds.compactMap { $0.kind == 1 || $0.end >= n ? nil : $0.end }
                        if thirds.isEmpty { continue }
                        for idx in follow.longer {
                            let e = lexicon.entry(idx)
                            if Double(e.score) / 100 < minWord { break }
                            let third = Int(lexicon.syllable(e, 2))
                            guard thirds.contains(where: { slot[$0 * S + third] >= 0 }) else { continue }
                            let base = Double(e.score) / 100 - wordPenalty
                            chains({ self.lexicon.syllable(e, $0) }, count: e.sylCount, first: first, base: base) { end, sp, corr, cuts, kinds in
                                guard accepts(i, end, cuts.count, base + sp) else { return }
                                insert(Edge(start: i, end: end, score: base + sp, corrected: corr, entry: idx, userText: nil,
                                            ids: [], cuts: cuts, kinds: kinds))
                            }
                        }
                    }
                }
                if let user {
                    for u in user.candidates(first: first.id) {
                        let L = u.ids.count
                        if first.kind == 2 && L == 1 { continue }
                        if first.kind == 1 && L > 1 { continue }
                        let gain = L == 1 ? min(userCap / 4, userWeight * log(1 + Double(u.count)))
                                          : min(userCap, userWordBoost + userWeight * log(1 + Double(u.count)))
                        let base = (u.lex.map { Double($0) / 100 } ?? userPhraseScore) - wordPenalty + gain
                        chains({ u.ids[$0] }, count: L, first: first, base: base) { end, sp, corr, cuts, kinds in
                            insert(Edge(start: i, end: end, score: base + sp, corrected: corr, entry: -1, userText: u.text,
                                        ids: u.ids, cuts: cuts, kinds: kinds))
                        }
                    }
                }
            }
        }

        // Flatten edges and index by end tap
        var edges: [Edge] = []
        var ending = [[Int]](repeating: [], count: n + 1)
        for list in bucketList {
            for e in list {
                ending[e.end].append(edges.count)
                edges.append(e)
            }
        }

        // K-best Viterbi over the word lattice (once unrestricted, once literal-only)
        struct Path { var score: Double; var edges: [Int]; var corrected: Bool }
        // the characters of each edge's word, decoded once (the language model reads them for every transition)
        var edgeChars = [[Character]?](repeating: nil, count: edges.count)
        func chars(_ ei: Int) -> [Character] {
            if let c = edgeChars[ei] { return c }
            let e = edges[ei]
            let c = Array(e.userText ?? lexicon.text(lexicon.entry(e.entry)))
            edgeChars[ei] = c
            return c
        }
        let keypad = taps.contains { $0.group }
        // per-context normalisation of the language model: on the full keyboard (九宫格 measured no better with it)
        grammar?.massWeight = keypad ? 0 : contextNormalisation
        /// The language-model score of word `ei` after the words of `prev` (or after the text in the field).
        func link(_ prev: [Int], _ ei: Int) -> Double {
            guard let grammar else { return 0 }
            var ctx: [Character] = []
            var k = prev.count - 1
            while ctx.count < 3 && k >= 0 { ctx.insert(contentsOf: chars(prev[k]), at: 0); k -= 1 }
            if ctx.count < 3 { ctx.insert(contentsOf: leftContext.suffix(3 - ctx.count), at: 0) }
            let q = grammar.query(context: Array(ctx.suffix(3)), word: chars(ei))
            // a corrected word keeps the same baseline but only part of the lift above it
            let base = grammar.nonCollocationPenalty
            var lift = grammarWeight * (edges[ei].corrected ? base + grammarCorrectedFactor * (q - base) : q)
            // The model's counts are joint (how often context + word occur), so they already carry how common the
            // word is; the lexicon's frequency added on top counts that twice and lets 在 outvote 再 after 可以.
            // Where the model has the pair, part of the word's own frequency is taken back out.
            if unigramDiscount > 0, !keypad, q > base, !edges[ei].corrected, edges[ei].entry >= 0 {
                lift -= unigramDiscount * (Double(lexicon.entry(edges[ei].entry).score) / 100 - unigramCenter)
            }
            return lift
        }
        func bestPaths(literalOnly: Bool) -> [Path] {
            var paths = [[Path]](repeating: [], count: n + 1)
            paths[0] = [Path(score: 0, edges: [], corrected: false)]
            for j in 1...n {
                var cands: [Path] = []
                for ei in ending[j] {
                    let e = edges[ei]
                    if literalOnly && e.corrected { continue }
                    for p in paths[e.start] {
                        cands.append(Path(score: p.score + e.score + link(p.edges, ei), edges: p.edges + [ei],
                                          corrected: p.corrected || e.corrected))
                    }
                }
                cands.sort { $0.score > $1.score }
                paths[j] = Array(cands.prefix(beam))
            }
            return paths[n]
        }

        func text(_ e: Edge) -> String { e.userText ?? lexicon.text(lexicon.entry(e.entry)) }
        func ids(_ e: Edge) -> [UInt16] { e.entry >= 0 ? lexicon.syllableIDs(lexicon.entry(e.entry)) : e.ids }
        func keys(_ es: [Edge]) -> [Character] {
            guard es.allSatisfy({ $0.kinds.allSatisfy { $0 == 0 } }) else { return [] }
            return es.flatMap { e in ids(e).flatMap { Array(spelling(of: $0)) } }
        }
        func candidate(_ es: [Edge], tapCount: Int, corrected: Bool, score: Double) -> Candidate {
            var c = Candidate(text: es.map(text).joined(), tapCount: tapCount, syllables: es.flatMap(ids),
                              corrected: corrected, score: score)
            c.intendedKeys = keys(es)
            return c
        }

        var result: [Candidate] = []
        var resultEdges: [[Edge]] = []
        var seen = Set<String>()
        func add(_ c: Candidate, _ es: [Edge]) {
            if seen.insert(c.text).inserted { result.append(c); resultEdges.append(es) }
        }

        let full = bestPaths(literalOnly: false)
        var fullCands = full.map { p in (p.edges.map { edges[$0] }, p.corrected, p.score) }
        for ei in ending[n] where edges[ei].start == 0 {
            fullCands.append(([edges[ei]], edges[ei].corrected, edges[ei].score + link([], ei)))
        }
        fullCands.sort { $0.2 > $1.2 }

        if let first = fullCands.first {
            add(candidate(first.0, tapCount: n, corrected: first.1, score: first.2), first.0)
            // Gboard-style: when the top choice was auto-corrected, offer the literal reading next.
            if first.1, correctionEnabled, let lit = bestPaths(literalOnly: true).first {
                let es = lit.edges.map { edges[$0] }
                add(candidate(es, tapCount: n, corrected: false, score: lit.score), es)
            }
        }
        for c in fullCands.dropFirst() { add(candidate(c.0, tapCount: n, corrected: c.1, score: c.2), c.0) }

        // 中英混输: the letters as an English word (exact, then the likeliest completion), placed by score among
        // the readings that cover all the input — so "ok" leads with OK, while "de" still leads with 的.
        if englishEnabled, let english, n >= 2 {
            let typed = String(taps.map { $0.key }).lowercased()
            var extra: [Candidate] = []
            // short plain words (so, me, an…) mostly collide with pinyin being typed: they need more evidence
            let short = n == 2 ? 3.0 : n == 3 ? 1.5 : 0
            func score(_ w: EnglishLexicon.Word) -> Double {
                w.display != w.key ? w.logp - englishPenalty + englishCasedBonus : w.logp - englishPenalty - short
            }
            // rare plain words (nih, hon…) are more likely pinyin being typed: only common ones, or ones written cased
            if let w = english.exact(typed), w.display != w.key || w.zipf >= 3.6 {
                var c = Candidate(text: w.display, tapCount: n, syllables: [], corrected: false, score: score(w))
                c.isEnglish = true
                extra.append(c)
            }
            if englishCompletions, n >= 3, let w = english.completion(typed) {
                var c = Candidate(text: w.display, tapCount: n, syllables: [], corrected: false,
                                  score: score(w) - englishCompletionPenalty)
                c.isEnglish = true
                extra.append(c)
            }
            for c in extra.sorted(by: { $0.score > $1.score }) where seen.insert(c.text).inserted {
                var pos = result.prefix(while: { $0.score >= c.score }).count
                // a short plain word never displaces a Chinese reading of the same keys (么 before "me")
                if n <= 3, !result.isEmpty, english.exact(typed)?.display == c.text, c.text == typed { pos = max(pos, 1) }
                result.insert(c, at: pos)
                resultEdges.insert([], at: pos)
            }
        }

        // Words covering a shorter prefix of the input, longest first
        if n > 1 {
            for end in stride(from: n - 1, through: 1, by: -1) {
                let list = ending[end].filter { edges[$0].start == 0 }.sorted { edges[$0].score > edges[$1].score }
                for ei in list {
                    let e = edges[ei]
                    add(candidate([e], tapCount: end, corrected: e.corrected, score: e.score), [e])
                }
            }
        }

        let raw = String(taps.map { $0.key })

        // Preedit: the top candidate's pinyin; abbreviations and a half-typed syllable shown as typed.
        var preedit = raw
        if let es = resultEdges.first, !es.isEmpty {
            var parts: [String] = []
            var cursor = 0
            for e in es {
                let sy = ids(e)
                for (k, cut) in e.cuts.enumerated() {
                    if e.kinds[k] == 0, k < sy.count {
                        parts.append(XiaoheScheme.display(lexicon.syllables[Int(sy[k])]))
                    } else {
                        parts.append(String(taps[cursor..<min(cut, n)].map { $0.key }))
                    }
                    cursor = cut
                }
            }
            if cursor < n { parts.append(String(taps[cursor...].map { $0.key })) }
            preedit = parts.joined(separator: " ")
        }
        // The letters as typed are always the last choice (Gboard offers the raw input too); for 九宫格 keys, whose
        // "letters" are digits, the pinyin read from them.
        let rawText = taps.contains(where: { $0.group }) ? preedit.replacingOccurrences(of: " ", with: "") : raw
        add(Candidate(text: rawText, tapCount: n, syllables: [], corrected: false, score: -.infinity), [])
        return Result(candidates: result, preedit: preedit)
    }

    /// The keys that spell a syllable in the current scheme.
    /// How common a syllable is: its most frequent single character's score (built on first use).
    private lazy var syllableWeight: [Int] = (0..<lexicon.syllables.count).map { sid in
        lexicon.singles(UInt16(sid)).map { Int(lexicon.entry($0).score) }.max() ?? Int(Int16.min)
    }

    /// 九宫格 拼音选择: the syllables the next keypad keys can spell (from the first keypad tap on), longest
    /// spelling first, then the most common — as the left column of a phone keypad IME offers. Choosing one turns
    /// those keys into its exact letters, so the rest of the input decodes around it.
    public func t9SyllableChoices(_ taps: [Tap], limit: Int = 30) -> (start: Int, choices: [(text: String, keys: [Character])]) {
        guard let start = taps.firstIndex(where: { $0.group }) else { return (0, []) }
        var digits: [Character] = []
        for t in taps[start...] { if t.group { digits.append(t.key) } else { break } }
        var found: [(text: String, keys: [Character], len: Int, w: Int)] = []
        for (i, syl) in lexicon.syllables.enumerated() {
            let keys = Array(spelling(of: UInt16(i)))
            guard !keys.isEmpty, keys.count <= digits.count else { continue }
            if zip(keys, digits).allSatisfy({ Tap.t9Digit($0.0) == $0.1 }) {
                found.append((XiaoheScheme.display(syl), keys, keys.count, syllableWeight[i]))
            }
        }
        found.sort { $0.len != $1.len ? $0.len > $1.len : $0.w > $1.w }
        var seen = Set<String>()
        let list = found.filter { seen.insert($0.text).inserted }.prefix(limit).map { (text: $0.text, keys: $0.keys) }
        return (start, Array(list))
    }

    // MARK: - 联想: what may come next after a commit

    /// Each character's readings (built once, on first use, from the lexicon's single characters).
    private var readingsOfChar: [Character: [UInt16]] = [:]
    /// Hand over a table built elsewhere (see `readingsTable`), so the decoder's thread never spends the time.
    public func setReadings(_ table: [Character: [UInt16]]) { if readingsOfChar.isEmpty { readingsOfChar = table } }
    private func readings(_ c: Character) -> [UInt16] {
        if readingsOfChar.isEmpty { readingsOfChar = Self.readingsTable(lexicon) }
        return readingsOfChar[c] ?? []
    }
    /// Every character's readings, from the lexicon's single characters (read-only: safe on any thread).
    public static func readingsTable(_ lexicon: Lexicon) -> [Character: [UInt16]] {
        var t: [Character: [UInt16]] = [:]
        for sid in 0..<lexicon.syllables.count {
            var i = lexicon.range(firstSyllable: UInt16(sid)).lowerBound
            let end = lexicon.range(firstSyllable: UInt16(sid)).upperBound
            while i < end {
                let e = lexicon.entry(i)
                if e.sylCount != 1 { break }   // a syllable's single characters come first in its run
                if let ch = lexicon.text(e).first { t[ch, default: []].append(UInt16(sid)) }
                i += 1
            }
        }
        return t
    }

    /// The lexicon's best score for a character on its own, in ln units.
    func charScore(_ c: Character) -> Double {
        var best = -Double.infinity
        for sid in readings(c).prefix(4) {
            for idx in lexicon.singles(sid) {
                let e = lexicon.entry(idx)
                if lexicon.text(e).first == c { best = max(best, Double(e.score) / 100); break }
            }
        }
        return best
    }
    public var predictionMinChar = 13.5

    /// The lexicon's best score for a two-character word, in ln units (nil: not a word it lists).
    func wordScore(_ a: Character, _ b: Character) -> Double? {
        var best: Int16?
        let text = String([a, b])
        for x in readings(a).prefix(4) { for y in readings(b).prefix(4) {
            if let v = lexicon.score(of: [x, y], text: text) { best = max(best ?? v, v) }
        } }
        return best.map { Double($0) / 100 }
    }

    /// Next-word suggestions for the text before the cursor: what the language model has seen right after it (the
    /// longest context it knows first) — one character, or a two-character word the lexicon lists — best first.
    /// predbench (word boundaries of the sentence sets): the next word among the first six about one time in five.
    public func predictions(after context: [Character], limit: Int = 8) -> [String] {
        guard let grammar, let last = context.last, Grammar.isHan(last) else { return [] }
        _ = grammar
        var scored: [(String, Double)] = []
        for (t, v) in grammar.continuations(after: context, limit: 40) {
            let chars = Array(t)
            if chars.count == 2, wordScore(chars[0], chars[1]) == nil { continue }   // fragments, not words
            // a lone character must be one people type on its own often (的 我 了, not 歹 of 好歹)
            if chars.count == 1, charScore(chars[0]) < predictionMinChar { continue }
            var score = v
            // the user just finished a word (你好); a character that would rather pull its last character into a
            // word of its own (好像) misreads it
            if context.count >= 2, let joined = wordScore(last, chars[0]), joined >= predictionSplitWord,
               wordScore(context[context.count - 2], last) != nil {
                score -= predictionSplitPenalty
            }
            scored.append((t, score))
        }
        // what this user wrote after the same words before comes first
        var out = user?.continuations(after: context) ?? []
        for (t, _) in scored.sorted(by: { $0.1 > $1.1 }) where !out.contains(t) { out.append(t) }
        return Array(out.prefix(limit))
    }
    public var predictionSplitWord = 11.0
    public var predictionSplitPenalty = 3.0

    public func spelling(of id: UInt16) -> String {
        let s = lexicon.syllables[Int(id)]
        return scheme == .xiaohe ? (XiaoheScheme.code(for: s) ?? "") : s
    }
}

public extension Decoder {
    /// The key sequence a candidate stands for (used to learn the personal touch offset).
    func keys(for candidate: Candidate) -> [Character] { candidate.intendedKeys }
}
