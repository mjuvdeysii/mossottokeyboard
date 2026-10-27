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
    public var wordPenalty = 22.0
    public var userBonus = 4.0
    /// 中英混输: English words for the typed letters, ranked against the Chinese readings by frequency.
    public var english: EnglishLexicon?
    public var englishEnabled = true
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
    public var abbreviationPenalty = 2.6
    public var prefixPenalty = 0.4

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
                        let extra = st.node.ids.isEmpty ? prefixPenalty : prefixPenalty + completionPenalty
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
                let cost = abbreviationPenalty + (t0.group ? 1.0 : 0)
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
        // 小鹤双拼, plain: with an odd number of keys the last one is simply not finished yet. The candidates are those
        // of the complete pairs typed so far; the dangling key waits (no guessing the next syllable from it).
        if scheme == .xiaohe, taps.count >= 3, taps.count % 2 == 1, !taps.contains(where: { $0.key == "'" }) {
            boundaries = []
            let r = decodeLetters(Array(taps.dropLast()))
            let raw = String(taps.map { $0.key })
            var cands = r.candidates.filter { $0.tapCount > 0 && $0.score > -.infinity && !$0.isEnglish }
            // English words cover every key typed (ios → iOS): first when they lead the full reading, else second
            if englishEnabled, english != nil {
                let full = decodeLetters(taps).candidates
                for (k, c) in full.enumerated() where c.isEnglish && !cands.contains(where: { $0.text == c.text }) {
                    cands.insert(c, at: min(k == 0 ? 0 : 1, cands.count))
                }
            }
            cands.append(Candidate(text: raw, tapCount: taps.count, syllables: [], corrected: false, score: -.infinity))
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
        var spanAt = [[UInt16: [Span]]](repeating: [:], count: n)
        var has = [[Bool]](repeating: [Bool](repeating: false, count: lexicon.syllables.count), count: n + 1)
        for i in 0..<n { for s in spansFrom[i] { spanAt[i][s.id, default: []].append(s); has[i][Int(s.id)] = true } }

        // Edge buckets keyed by (start, end)
        var buckets: [Int: [Edge]] = [:]
        // 九宫格 input is far more ambiguous per key: keep more words per span
        let wide = taps.contains { $0.group } ? (scheme == .xiaohe ? 4 : 1) : 1
        func cap(_ e: Edge) -> Int { (e.start == 0 ? (e.cuts.count == 1 ? 120 : 40) : 12) * wide }
        func insert(_ e: Edge) {
            let key = e.start * 1024 + e.end
            var list = buckets[key] ?? []
            let c = cap(e)
            if list.count < c {
                list.append(e)
            } else if let minIdx = list.indices.min(by: { list[$0].score < list[$1].score }), list[minIdx].score < e.score {
                list[minIdx] = e
            } else { return }
            buckets[key] = list
        }

        // Match a syllable sequence (word) from a first span onwards; calls `found` for every complete chain.
        func chains(_ syl: (Int) -> UInt16, count L: Int, first: Span,
                    found: (_ end: Int, _ spatial: Double, _ corrected: Bool, _ cuts: [Int], _ kinds: [UInt8]) -> Void) {
            var stack: [(k: Int, pos: Int, sp: Double, corr: Bool, cuts: [Int], kinds: [UInt8])] =
                [(1, first.end, first.spatial, first.corrected, [first.end], [first.kind])]
            while let top = stack.popLast() {
                if top.k == L {
                    // a word made only of abbreviations must be at least two syllables; one-syllable abbreviations are noise
                    if !(L == 1 && top.kinds[0] == 2) { found(top.pos, top.sp, top.corr, top.cuts, top.kinds) }
                    continue
                }
                guard top.pos < n, let next = spanAt[top.pos][syl(top.k)] else { continue }
                for s in next {
                    if top.kinds.last == 1 { continue }       // a half-typed syllable can only be the last one
                    stack.append((top.k + 1, s.end, top.sp + s.spatial, top.corr || s.corrected, top.cuts + [s.end], top.kinds + [s.kind]))
                }
            }
        }

        // Only start words where a chain of syllables from the beginning can arrive, and from where one can
        // still reach the end (or stop early for a shorter candidate from position 0) — this skips the inside of
        // spelled-out syllables in 全拼 (the "hon" of "zhong").
        var reach = [Bool](repeating: false, count: n + 1)
        reach[0] = true
        for i in 0..<n where reach[i] { for sp in spansFrom[i] { reach[sp.end] = true } }

        for i in 0..<n where reach[i] {
            for first in spansFrom[i] {
                // Fast path for the common cases; the full chain walk only when the second syllable can follow.
                let firstEnd = first.end
                func scan(_ idx: Int) {
                    let e = lexicon.entry(idx)
                    let L = e.sylCount
                    if first.kind == 2 && L == 1 { return }
                    if first.kind == 1 && L > 1 { return }
                    let base = Double(e.score) / 100 - wordPenalty
                    if L == 1 {
                        insert(Edge(start: i, end: firstEnd, score: base + first.spatial, corrected: first.corrected, entry: idx,
                                    userText: nil, ids: [], cuts: [firstEnd], kinds: [first.kind]))
                        return
                    }
                    guard firstEnd < n, has[firstEnd][Int(lexicon.syllable(e, 1))] else { return }
                    chains({ self.lexicon.syllable(e, $0) }, count: L, first: first) { end, sp, corr, cuts, kinds in
                        insert(Edge(start: i, end: end, score: base + sp, corrected: corr, entry: idx, userText: nil,
                                    ids: [], cuts: cuts, kinds: kinds))
                    }
                }
                // a half-typed syllable can only be a one-syllable word: walk just the single characters
                if first.kind == 1 {
                    for idx in lexicon.singles(first.id) { scan(idx) }
                } else {
                    for idx in lexicon.range(firstSyllable: first.id) { scan(idx) }
                }
                if let user {
                    for u in user.candidates(first: first.id) {
                        let L = u.ids.count
                        if first.kind == 2 && L == 1 { continue }
                        if first.kind == 1 && L > 1 { continue }
                        let base = log(Double(u.count) + 1) * 2 + userBonus - 8
                        chains({ u.ids[$0] }, count: L, first: first) { end, sp, corr, cuts, kinds in
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
        for (_, list) in buckets {
            for e in list {
                ending[e.end].append(edges.count)
                edges.append(e)
            }
        }

        // K-best Viterbi over the word lattice (once unrestricted, once literal-only)
        struct Path { var score: Double; var edges: [Int]; var corrected: Bool }
        func bestPaths(literalOnly: Bool) -> [Path] {
            var paths = [[Path]](repeating: [], count: n + 1)
            paths[0] = [Path(score: 0, edges: [], corrected: false)]
            for j in 1...n {
                var cands: [Path] = []
                for ei in ending[j] {
                    let e = edges[ei]
                    if literalOnly && e.corrected { continue }
                    for p in paths[e.start] {
                        cands.append(Path(score: p.score + e.score, edges: p.edges + [ei], corrected: p.corrected || e.corrected))
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
            fullCands.append(([edges[ei]], edges[ei].corrected, edges[ei].score))
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

    public func spelling(of id: UInt16) -> String {
        let s = lexicon.syllables[Int(id)]
        return scheme == .xiaohe ? (XiaoheScheme.code(for: s) ?? "") : s
    }
}

public extension Decoder {
    /// Correction strength presets exposed in settings.
    enum Strength: Int, CaseIterable { case conservative = 0, standard = 1, aggressive = 2 }

    func apply(strength: Strength) {
        switch strength {
        case .conservative: correctionPenalty = 2.5
        case .standard: correctionPenalty = 1.5
        case .aggressive: correctionPenalty = 0.8
        }
    }

    /// The key sequence a candidate stands for (used to learn the personal touch offset).
    func keys(for candidate: Candidate) -> [Character] { candidate.intendedKeys }
}
