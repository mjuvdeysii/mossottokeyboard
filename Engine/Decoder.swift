import Foundation

public struct Candidate: Equatable {
    public let text: String
    /// Number of taps this candidate consumes from the start of the input.
    public let tapCount: Int
    public let syllables: [UInt16]
    /// True when at least one key was auto-corrected to produce this candidate.
    public let corrected: Bool
    public let score: Double
}

/// Xiaohe shuangpin decoder with touch-position-aware auto-correction.
///
/// Every syllable position is expanded to the plausible 2-key codes given
/// the touch model; the lexicon then scores words over that lattice:
///   score = ln(freq) − wordPenalty + Σ spatial log-prob − correctionPenalty·(#corrected syllables)
/// so a key is only changed when the touch geometry *and* the language agree.
public final class Decoder {
    public let lexicon: Lexicon
    public var user: UserDictionary?

    public var correctionEnabled = true
    public var spatialWeight = 1.0
    public var correctionPenalty = 1.5
    public var wordPenalty = 22.0
    public var userBonus = 4.0
    public var maxSyllableAlternatives = 6
    public var pruneMargin = 7.0
    public var beam = 4

    public init(lexicon: Lexicon, user: UserDictionary? = nil) {
        self.lexicon = lexicon
        self.user = user
    }

    public struct Result {
        public var candidates: [Candidate]
        /// Pinyin of the first candidate, e.g. "ni hao d".
        public var preedit: String
    }

    struct SylCand { let id: UInt16; let spatial: Double; let corrected: Bool }

    struct Edge {
        let start: Int
        let len: Int
        let score: Double
        let corrected: Bool
        let entry: Int          // >= 0 lexicon entry, < 0 user item
        let userText: String?
        let ids: [UInt16]
    }

    // MARK: - Syllable lattice

    func syllableCandidates(_ taps: [Tap]) -> [[SylCand]] {
        var out: [[SylCand]] = []
        let full = taps.count / 2
        for p in 0..<full {
            let a = taps[2 * p], b = taps[2 * p + 1]
            let aa = correctionEnabled ? a.alternatives : [(a.key, 0.0)]
            let bb = correctionEnabled ? b.alternatives : [(b.key, 0.0)]
            var best: [UInt16: SylCand] = [:]
            for (ka, la) in aa {
                for (kb, lb) in bb {
                    guard let ids = lexicon.codeToSyllables[String([ka, kb])] else { continue }
                    let corrected = ka != a.key || kb != b.key
                    let s = spatialWeight * (la + lb) - (corrected ? correctionPenalty : 0)
                    for id in ids where (best[id]?.spatial ?? -.infinity) < s {
                        best[id] = SylCand(id: id, spatial: s, corrected: corrected)
                    }
                }
            }
            var list = best.values.sorted { $0.spatial > $1.spatial }
            if let top = list.first?.spatial { list = list.filter { $0.spatial >= top - pruneMargin } }
            out.append(Array(list.prefix(maxSyllableAlternatives)))
        }
        if taps.count % 2 == 1, let t = taps.last {
            let alts = correctionEnabled ? t.alternatives : [(t.key, 0.0)]
            var best: [UInt16: SylCand] = [:]
            for (k, l) in alts {
                let corrected = k != t.key
                let s = spatialWeight * l - (corrected ? correctionPenalty : 0)
                for id in lexicon.firstKeyToSyllables[k] ?? [] where (best[id]?.spatial ?? -.infinity) < s {
                    best[id] = SylCand(id: id, spatial: s, corrected: corrected)
                }
            }
            var list = best.values.sorted { $0.spatial > $1.spatial }
            if let top = list.first?.spatial { list = list.filter { $0.spatial >= top - pruneMargin } }
            out.append(list)
        }
        return out
    }

    // MARK: - Decode

    public func decode(_ taps: [Tap]) -> Result {
        guard !taps.isEmpty else { return Result(candidates: [], preedit: "") }
        let lattice = syllableCandidates(taps)
        let P = lattice.count
        let partial = taps.count % 2 == 1
        let sylCount = lexicon.syllables.count

        // membership: position -> syllable id -> index into lattice[pos]
        var member = [[Int16]](repeating: [Int16](repeating: -1, count: sylCount), count: P)
        for p in 0..<P { for (i, c) in lattice[p].enumerated() { member[p][Int(c.id)] = Int16(i) } }

        // Edge buckets keyed by (start, len)
        var buckets: [Int: [Edge]] = [:]
        func cap(_ start: Int, _ len: Int) -> Int { start == 0 ? (len == 1 ? 120 : 40) : 12 }
        func insert(_ e: Edge) {
            let key = e.start * 64 + e.len
            var list = buckets[key] ?? []
            let c = cap(e.start, e.len)
            if list.count < c {
                list.append(e)
            } else if let minIdx = list.indices.min(by: { list[$0].score < list[$1].score }), list[minIdx].score < e.score {
                list[minIdx] = e
            } else { return }
            buckets[key] = list
        }

        for i in 0..<P {
            for c in lattice[i] {
                for idx in lexicon.range(firstSyllable: c.id) {
                    let e = lexicon.entry(idx)
                    let L = e.sylCount
                    if i + L > P { continue }
                    var sp = c.spatial
                    var corr = c.corrected
                    var ok = true
                    var k = 1
                    while k < L {
                        let m = member[i + k][Int(lexicon.syllable(e, k))]
                        if m < 0 { ok = false; break }
                        let sc = lattice[i + k][Int(m)]
                        sp += sc.spatial
                        corr = corr || sc.corrected
                        k += 1
                    }
                    if !ok { continue }
                    let score = Double(e.score) / 100 - wordPenalty + sp
                    insert(Edge(start: i, len: L, score: score, corrected: corr, entry: idx, userText: nil, ids: []))
                }
                if let user {
                    for u in user.candidates(first: c.id) {
                        let L = u.ids.count
                        if i + L > P { continue }
                        var sp = c.spatial, corr = c.corrected, ok = true
                        for k in 1..<max(L, 1) where k < L {
                            let m = member[i + k][Int(u.ids[k])]
                            if m < 0 { ok = false; break }
                            sp += lattice[i + k][Int(m)].spatial
                            corr = corr || lattice[i + k][Int(m)].corrected
                        }
                        if !ok { continue }
                        let score = log(Double(u.count) + 1) * 2 + userBonus - 8 + sp
                        insert(Edge(start: i, len: L, score: score, corrected: corr, entry: -1, userText: u.text, ids: u.ids))
                    }
                }
            }
        }

        // Flatten edges and index by end position
        var edges: [Edge] = []
        var ending = [[Int]](repeating: [], count: P + 1)
        for (_, list) in buckets {
            for e in list {
                ending[e.start + e.len].append(edges.count)
                edges.append(e)
            }
        }

        // K-best Viterbi over the word lattice (once unrestricted, once literal-only)
        struct Path { var score: Double; var edges: [Int]; var corrected: Bool }
        func bestPaths(literalOnly: Bool) -> [Path] {
            var paths = [[Path]](repeating: [], count: P + 1)
            paths[0] = [Path(score: 0, edges: [], corrected: false)]
            for j in 1...P {
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
            return paths[P]
        }

        func text(_ e: Edge) -> String { e.userText ?? lexicon.text(lexicon.entry(e.entry)) }
        func ids(_ e: Edge) -> [UInt16] { e.entry >= 0 ? lexicon.syllableIDs(lexicon.entry(e.entry)) : e.ids }
        func consumed(start: Int, len: Int) -> Int { (start + len == P && partial) ? taps.count : 2 * (start + len) }

        var result: [Candidate] = []
        var seen = Set<String>()
        func add(_ c: Candidate) { if seen.insert(c.text).inserted { result.append(c) } }

        let full = bestPaths(literalOnly: false)
        var fullCands = full.map { p -> Candidate in
            Candidate(text: p.edges.map { text(edges[$0]) }.joined(),
                      tapCount: taps.count,
                      syllables: p.edges.flatMap { ids(edges[$0]) },
                      corrected: p.corrected, score: p.score)
        }
        for e in buckets[P] ?? [] where e.start == 0 {
            fullCands.append(Candidate(text: text(e), tapCount: taps.count, syllables: ids(e), corrected: e.corrected, score: e.score))
        }
        fullCands.sort { $0.score > $1.score }

        if let first = fullCands.first {
            add(first)
            // Gboard-style: when the top choice was auto-corrected, offer the literal reading next.
            if first.corrected, correctionEnabled, let lit = bestPaths(literalOnly: true).first {
                add(Candidate(text: lit.edges.map { text(edges[$0]) }.joined(), tapCount: taps.count,
                              syllables: lit.edges.flatMap { ids(edges[$0]) }, corrected: false, score: lit.score))
            }
        }
        for c in fullCands.dropFirst() { add(c) }

        if P > 1 {
            for L in stride(from: P - 1, through: 1, by: -1) {
                let list = (buckets[L] ?? []).sorted { $0.score > $1.score }
                for e in list {
                    add(Candidate(text: text(e), tapCount: consumed(start: 0, len: L), syllables: ids(e),
                                  corrected: e.corrected, score: e.score))
                }
            }
        }

        let raw = String(taps.map { $0.key })
        if result.isEmpty {
            result.append(Candidate(text: raw, tapCount: taps.count, syllables: [], corrected: false, score: -.infinity))
        }

        // Preedit: pinyin of the top candidate; dangling single tap shown as typed.
        var preedit = raw
        if let top = result.first, !top.syllables.isEmpty {
            var parts = top.syllables.map { XiaoheScheme.display(lexicon.syllables[Int($0)]) }
            if partial && top.tapCount == taps.count, !parts.isEmpty {
                parts[parts.count - 1] = String(taps.last!.key)
            }
            preedit = parts.joined(separator: " ")
        }
        return Result(candidates: result, preedit: preedit)
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
    func keys(for candidate: Candidate) -> [Character] {
        candidate.syllables.flatMap { Array(XiaoheScheme.code(for: lexicon.syllables[Int($0)]) ?? "") }
    }
}
