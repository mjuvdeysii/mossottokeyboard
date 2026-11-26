import Foundation

/// Learned words/phrases. Stored by pinyin (not syllable id) so it survives lexicon rebuilds.
public final class UserDictionary {
    struct Item: Codable {
        var p: [String]   // pinyin syllables
        var t: String     // text
        var c: Int        // commit count
        var u: Double     // last used (unix time)
    }

    struct BigramItem: Codable {
        var a: String
        var b: String
        var c: Int
        var u: Double
    }

    private var items: [String: Item] = [:]
    /// Per first syllable: the learned items, with the lexicon's own score for the same word (nil for words the
    /// lexicon does not have — the user's own phrases).
    private var byFirst: [UInt16: [(ids: [UInt16], key: String, lex: Int16?)]] = [:]   // lex: see lexScores
    /// Local word-pair transition memory (`prev -> [next: (count, lastUsed)]`), stored in `userdict.json.bigrams`.
    private var bigrams: [String: [String: (c: Int, u: Double)]] = [:]
    private var byNext: [String: [(prev: [Character], c: Int, u: Double)]] = [:]
    private var bigramPrevEndChars: Set<Character> = []
    private var bigramNextStartChars: Set<Character> = []
    private var bigramCount = 0
    public var maxBigrams = 8000
    private var bigramsDirty = false
    private let lexicon: Lexicon
    private let url: URL?
    private let bigramURL: URL?
    private var dirty = false
    public var maxItems = 20000

    public init(lexicon: Lexicon, url: URL?) {
        self.lexicon = lexicon
        self.url = url
        self.bigramURL = url.map { $0.appendingPathExtension("bigrams") }
        if let url, let data = try? Data(contentsOf: url) {
            if let list = try? JSONDecoder().decode([Item].self, from: data) {
                for it in list { items[Self.key(it.p, it.t)] = it }
            } else {
                // unreadable (cut off, or written by something else): keep it aside rather than overwrite it later
                let aside = url.appendingPathExtension("corrupt")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: url, to: aside)
            }
        }
        if let bigramURL, let bdata = try? Data(contentsOf: bigramURL) {
            if let blist = try? JSONDecoder().decode([BigramItem].self, from: bdata) {
                for it in blist where !it.a.isEmpty && !it.b.isEmpty && it.c > 0 {
                    if bigrams[it.a]?[it.b] == nil { bigramCount += 1 }
                    bigrams[it.a, default: [:]][it.b] = (it.c, it.u)
                }
            } else {
                let aside = bigramURL.appendingPathExtension("corrupt")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: bigramURL, to: aside)
            }
        }
        rebuildIndex()
        rebuildBigramIndexes()
    }

    static func key(_ p: [String], _ t: String) -> String { p.joined(separator: " ") + "|" + t }

    private func rebuildIndex() {
        byFirst.removeAll(keepingCapacity: true)
        let idMap = Dictionary(uniqueKeysWithValues: lexicon.syllables.enumerated().map { ($1, UInt16($0)) })
        for (k, it) in items {
            let ids = it.p.compactMap { idMap[$0] }
            guard ids.count == it.p.count, let f = ids.first else { continue }
            byFirst[f, default: []].append((ids, k, nil))
        }
        lexScores.removeAll()
    }
    /// The lexicon's score of each learned item, looked up the first time the decoder asks (never all at once at
    /// launch or inside a keystroke). `Int16.min` marks "not in the lexicon".
    private var lexScores: [String: Int16] = [:]
    private func lexScore(_ key: String, _ ids: [UInt16], _ text: String) -> Int16? {
        if let v = lexScores[key] { return v == Int16.min ? nil : v }
        let v = lexicon.score(of: ids, text: text)
        lexScores[key] = v ?? Int16.min
        return v
    }

    private func rebuildBigramIndexes() {
        byNext.removeAll(keepingCapacity: true)
        bigramPrevEndChars.removeAll(keepingCapacity: true)
        bigramNextStartChars.removeAll(keepingCapacity: true)
        var total = 0
        for (a, nexts) in bigrams {
            let prevChars = Array(a)
            guard let prevLast = prevChars.last else { continue }
            for (b, val) in nexts {
                guard let nextFirst = b.first else { continue }
                bigramPrevEndChars.insert(prevLast)
                bigramNextStartChars.insert(nextFirst)
                byNext[b, default: []].append((prevChars, val.c, val.u))
                total += 1
            }
        }
        bigramCount = total
    }

    public var count: Int { items.count }
    public var bigramCountForTests: Int { bigramCount }

    func candidates(first: UInt16) -> [(ids: [UInt16], text: String, count: Int, lex: Int16?)] {
        guard let list = byFirst[first] else { return [] }
        return list.compactMap { e in items[e.key].map { (e.ids, $0.t, $0.c, lexScore(e.key, e.ids, $0.t)) } }
    }

    public func learn(syllables ids: [UInt16], text: String) {
        // one syllable per character: a reading with an English word in it (我用iPhone) is not a learnable word
        guard !ids.isEmpty, !text.isEmpty, ids.count <= 8, text.count == ids.count else { return }
        let p = ids.map { lexicon.syllables[Int($0)] }
        let k = Self.key(p, text)
        let now = Date().timeIntervalSince1970
        if var it = items[k] {
            it.c += 1
            it.u = now
            items[k] = it
        } else {
            items[k] = Item(p: p, t: text, c: 1, u: now)
            byFirst[ids[0], default: []].append((ids, k, nil))
        }
        if items.count > maxItems { prune() }
        dirty = true
        // written out every so often, not only when the keyboard is put away: iOS can end the keyboard's process
        // without notice, and what was learned since the last save would go with it
        learnedSinceSave += 1
        if learnedSinceSave >= 25 { save() }
    }
    private var learnedSinceSave = 0

    /// Record an adjacent Chinese word-pair transition (`prev -> next`) in `userdict.json.bigrams`.
    public func learnBigram(prev: String, next: String) {
        guard !prev.isEmpty, !next.isEmpty, prev.count <= 4, next.count <= 4,
              prev.allSatisfy(Grammar.isHan), next.allSatisfy(Grammar.isHan) else { return }
        let now = Date().timeIntervalSince1970
        var map = bigrams[prev] ?? [:]
        let isNew = map[next] == nil
        let nextCount = (map[next]?.c ?? 0) + 1
        map[next] = (nextCount, now)
        bigrams[prev] = map
        if isNew {
            bigramCount += 1
            if let pl = prev.last { bigramPrevEndChars.insert(pl) }
            if let nf = next.first { bigramNextStartChars.insert(nf) }
            byNext[next, default: []].append((Array(prev), nextCount, now))
        } else if var entries = byNext[next] {
            let prevChars = Array(prev)
            if let idx = entries.firstIndex(where: { $0.prev == prevChars }) {
                entries[idx] = (prevChars, nextCount, now)
                byNext[next] = entries
            }
        }
        if bigramCount > maxBigrams { pruneBigrams() }
        bigramsDirty = true
        learnedSinceSave += 1
        if learnedSinceSave >= 25 { save() }
    }

    /// Lattice transition boost for `word` following `context`, with O(1) character fast-reject when absent.
    func bigramBonus(after context: [Character], word: [Character], weight: Double, cap: Double) -> Double {
        guard !bigrams.isEmpty, weight > 0, cap > 0, word.count >= 1, word.count <= 4,
              let lastPrev = context.last, bigramPrevEndChars.contains(lastPrev),
              let firstWord = word.first, bigramNextStartChars.contains(firstWord),
              let list = byNext[String(word)] else { return 0 }
        var best = 0.0
        for entry in list where context.count >= entry.prev.count && context.suffix(entry.prev.count).elementsEqual(entry.prev) {
            let scale = (entry.prev.count == 1 || word.count == 1) ? 0.5 : 1.0
            let bonus = min(cap, weight * log(1.0 + Double(entry.c))) * scale
            if bonus > best { best = bonus }
        }
        return best
    }

    /// A sentence committed in several picks: remember how its pieces go together — the whole of it when it is short
    /// enough (≤ 8 syllables), else each neighbouring pair of pieces — so it comes out in one go next time.
    public func learn(parts: [(text: String, ids: [UInt16])]) {
        guard parts.count > 1 else { return }
        for (a, b) in zip(parts, parts.dropFirst()) {
            learnBigram(prev: a.text, next: b.text)
        }
        let all = parts.flatMap { $0.ids }
        if all.count <= 8 {
            learn(syllables: all, text: parts.map { $0.text }.joined())
            return
        }
        for (a, b) in zip(parts, parts.dropFirst()) where a.ids.count + b.ids.count <= 8 {
            learn(syllables: a.ids + b.ids, text: a.text + b.text)
        }
    }

    /// 联想 from what this user has written before: learned phrases + adjacent word-pair bigrams matching the end of
    /// `context`, preferring longer context matches, then commit count and recency.
    public func continuations(after context: [Character], limit: Int = 3) -> [String] {
        var found: [String: (len: Int, c: Int, u: Double)] = [:]
        for it in items.values {
            let t = Array(it.t)
            guard t.count >= 3 else { continue }
            for k in stride(from: min(t.count - 1, context.count), through: 2, by: -1) where context.suffix(k).elementsEqual(t.prefix(k)) {
                let rest = String(t[k...].prefix(4))
                let old = found[rest]
                let cand = (k, it.c, it.u)
                if old == nil || (cand.0, cand.1, cand.2) > (old!.len, old!.c, old!.u) { found[rest] = cand }
                break
            }
        }
        if !bigrams.isEmpty, !context.isEmpty {
            for k in stride(from: min(4, context.count), through: 1, by: -1) {
                let key = String(context.suffix(k))
                guard let nexts = bigrams[key] else { continue }
                for (nextWord, val) in nexts {
                    let old = found[nextWord]
                    let cand = (k, val.c, val.u)
                    if old == nil || (cand.0, cand.1, cand.2) > (old!.len, old!.c, old!.u) { found[nextWord] = cand }
                }
            }
        }
        return found.sorted { ($0.value.len, $0.value.c, $0.value.u) > ($1.value.len, $1.value.c, $1.value.u) }
            .prefix(limit).map { $0.key }
    }

    public func contains(syllables ids: [UInt16], text: String) -> Bool {
        items[Self.key(ids.map { lexicon.syllables[Int($0)] }, text)] != nil
    }

    /// Take back one commit (an undone auto-correction): the count drops by one, the entry goes at zero.
    public func unlearn(syllables ids: [UInt16], text: String) {
        let k = Self.key(ids.map { lexicon.syllables[Int($0)] }, text)
        guard var it = items[k] else { return }
        it.c -= 1
        if it.c <= 0 { remove(k, first: ids.first) } else { items[k] = it }
        dirty = true
    }

    public func forget(syllables ids: [UInt16], text: String) {
        let k = Self.key(ids.map { lexicon.syllables[Int($0)] }, text)
        if items[k] != nil { remove(k, first: ids.first); dirty = true }
    }

    /// One entry out, and out of its first syllable's list (no rebuild of the whole index inside a keystroke).
    private func remove(_ k: String, first: UInt16?) {
        items.removeValue(forKey: k)
        if let f = first { byFirst[f]?.removeAll { $0.key == k } }
    }

    public func reset() {
        items.removeAll()
        byFirst.removeAll()
        bigrams.removeAll()
        byNext.removeAll()
        bigramPrevEndChars.removeAll()
        bigramNextStartChars.removeAll()
        bigramCount = 0
        dirty = true
        bigramsDirty = true
        save()
    }

    private func prune() {
        let sorted = items.sorted { ($0.value.c, $0.value.u) > ($1.value.c, $1.value.u) }
        items = Dictionary(uniqueKeysWithValues: sorted.prefix(maxItems * 3 / 4).map { ($0.key, $0.value) })
        rebuildIndex()
    }

    private func pruneBigrams() {
        var flat: [(a: String, b: String, c: Int, u: Double)] = []
        flat.reserveCapacity(bigramCount)
        for (a, nexts) in bigrams {
            for (b, val) in nexts { flat.append((a, b, val.c, val.u)) }
        }
        flat.sort { ($0.c, $0.u) > ($1.c, $1.u) }
        var kept: [String: [String: (c: Int, u: Double)]] = [:]
        for item in flat.prefix(maxBigrams * 3 / 4) {
            kept[item.a, default: [:]][item.b] = (item.c, item.u)
        }
        bigrams = kept
        rebuildBigramIndexes()
    }

    public func save() {
        guard let url else { return }
        learnedSinceSave = 0
        if dirty {
            dirty = false
            let list = Array(items.values)
            if let data = try? JSONEncoder().encode(list) {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
        if bigramsDirty, let bigramURL {
            bigramsDirty = false
            if bigrams.isEmpty {
                try? FileManager.default.removeItem(at: bigramURL)
            } else {
                var blist: [BigramItem] = []
                blist.reserveCapacity(bigramCount)
                for (a, nexts) in bigrams {
                    for (b, val) in nexts { blist.append(BigramItem(a: a, b: b, c: val.c, u: val.u)) }
                }
                if let data = try? JSONEncoder().encode(blist) {
                    try? FileManager.default.createDirectory(at: bigramURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: bigramURL, options: .atomic)
                }
            }
        }
    }
}
