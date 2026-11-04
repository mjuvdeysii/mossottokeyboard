import Foundation

/// Learned words/phrases. Stored by pinyin (not syllable id) so it survives lexicon rebuilds.
public final class UserDictionary {
    struct Item: Codable {
        var p: [String]   // pinyin syllables
        var t: String     // text
        var c: Int        // commit count
        var u: Double     // last used (unix time)
    }

    private var items: [String: Item] = [:]
    /// Per first syllable: the learned items, with the lexicon's own score for the same word (nil for words the
    /// lexicon does not have — the user's own phrases).
    private var byFirst: [UInt16: [(ids: [UInt16], key: String, lex: Int16?)]] = [:]   // lex: see lexScores
    private let lexicon: Lexicon
    private let url: URL?
    private var dirty = false
    public var maxItems = 20000

    public init(lexicon: Lexicon, url: URL?) {
        self.lexicon = lexicon
        self.url = url
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
        rebuildIndex()
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

    public var count: Int { items.count }

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

    /// A sentence committed in several picks: remember how its pieces go together — the whole of it when it is short
    /// enough (≤ 8 syllables), else each neighbouring pair of pieces — so it comes out in one go next time.
    public func learn(parts: [(text: String, ids: [UInt16])]) {
        guard parts.count > 1 else { return }
        let all = parts.flatMap { $0.ids }
        if all.count <= 8 {
            learn(syllables: all, text: parts.map { $0.text }.joined())
            return
        }
        for (a, b) in zip(parts, parts.dropFirst()) where a.ids.count + b.ids.count <= 8 {
            learn(syllables: a.ids + b.ids, text: a.text + b.text)
        }
    }

    /// 联想 from what this user has written before: learned phrases that begin with the end of `context` (你好 →
    /// 世界, after 你好世界 was typed), the rest of each — most used, then most recent, first.
    public func continuations(after context: [Character], limit: Int = 3) -> [String] {
        var found: [String: (c: Int, u: Double)] = [:]
        for it in items.values {
            let t = Array(it.t)
            guard t.count >= 3 else { continue }
            for k in stride(from: min(t.count - 1, context.count), through: 2, by: -1) where context.suffix(k).elementsEqual(t.prefix(k)) {
                let rest = String(t[k...].prefix(4))
                let old = found[rest]
                if old == nil || old!.c < it.c || (old!.c == it.c && old!.u < it.u) { found[rest] = (it.c, it.u) }
                break
            }
        }
        return found.sorted { $0.value.c != $1.value.c ? $0.value.c > $1.value.c : $0.value.u > $1.value.u }
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
        dirty = true
        save()
    }

    private func prune() {
        let sorted = items.sorted { ($0.value.c, $0.value.u) > ($1.value.c, $1.value.u) }
        items = Dictionary(uniqueKeysWithValues: sorted.prefix(maxItems * 3 / 4).map { ($0.key, $0.value) })
        rebuildIndex()
    }

    public func save() {
        guard dirty, let url else { return }
        dirty = false
        learnedSinceSave = 0
        let list = Array(items.values)
        if let data = try? JSONEncoder().encode(list) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
