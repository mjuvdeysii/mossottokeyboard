import Foundation

/// English typing with touch-aware autocorrect and suggestions, in the manner of the iOS / Gboard English keyboards:
/// the taps of the current word are matched against a trie of ~39 000 words, letting each tap stand for any key the
/// touch model finds plausible, and allowing at most one slip (an extra tap, or a missed letter). Each reading is
/// scored  ln P(word) + Σ spatial log-prob − slip cost,  so a word is only changed when the touch geometry and the
/// language agree. The keyboard shows the best readings; on space it replaces the typed word with the best one only
/// when that is clearly better (and a delete right after puts the typed word back).
public final class EnglishDecoder {
    public struct Suggestion: Equatable {
        public let text: String
        public let score: Double
        /// A tap was read as another key, or a slip was repaired.
        public let corrected: Bool
        /// Longer than what was typed (a completion, offered but never applied automatically).
        public let completion: Bool
    }

    private final class Node {
        var children: [Character: Node] = [:]
        var word: Int = -1            // index into lexicon.words when a word ends here
        var best: Double = -.infinity // best word log-prob at or below this node (for pruning and completions)
        var bestWord: Int = -1
    }

    public let lexicon: EnglishLexicon
    private let root = Node()

    public var spatialWeight = 1.0
    public var correctionPenalty = 1.2
    public var slipPenalty = 5.0
    public var completionPenalty = 2.5
    public var beam = 48
    /// A typed word that is itself in the dictionary is replaced only when the correction is this much likelier.
    public var keepMargin = 6.0

    public init(lexicon: EnglishLexicon) {
        self.lexicon = lexicon
        for (i, w) in lexicon.words.enumerated() {
            var node = root
            for c in w.key {
                let next = node.children[c] ?? Node()
                node.children[c] = next
                node = next
            }
            node.word = i
        }
        func fill(_ n: Node) {
            if n.word >= 0 { n.best = lexicon.words[n.word].logp; n.bestWord = n.word }
            for c in n.children.values {
                fill(c)
                if c.best > n.best { n.best = c.best; n.bestWord = c.bestWord }
            }
        }
        fill(root)
    }

    private struct State { let node: Node; let score: Double; let corrected: Bool; let slips: Int }

    /// The best readings of the taps typed so far in the current word (lowercase letters), best first.
    /// Slips allowed: one extra tap, one missed letter, or two neighbouring letters typed the wrong way round.
    public func suggestions(_ taps: [Tap], limit: Int = 5) -> [Suggestion] {
        guard !taps.isEmpty, taps.count <= 24 else { return [] }
        var best: [Int: Suggestion] = [:]
        search(taps, startSlips: 0, extra: 0, into: &best)
        // swapped neighbours (teh → the, thnaks → thanks): the same search over the taps with one pair exchanged
        if taps.count >= 3 {
            for i in 0..<(taps.count - 1) where taps[i].key != taps[i + 1].key {
                var sw = taps
                sw.swapAt(i, i + 1)
                search(sw, startSlips: 1, extra: slipPenalty, into: &best)
            }
        }
        var list = Array(best.values.sorted { $0.score > $1.score }.prefix(limit))
        let typed = String(taps.map { $0.key }).lowercased()
        if let c = Self.contractions[typed], !list.contains(where: { $0.text == c }) {
            list.insert(Suggestion(text: c, score: list.first?.score ?? 0, corrected: true, completion: false), at: 0)
            list = Array(list.prefix(limit))
        }
        return list
    }

    private func search(_ taps: [Tap], startSlips: Int, extra: Double, into best: inout [Int: Suggestion]) {
        var states = [State(node: root, score: -extra, corrected: startSlips > 0, slips: startSlips)]
        for t in taps {
            var next: [State] = []
            next.reserveCapacity(states.count * 6)
            for st in states {
                for (k, l) in t.alternatives {
                    if let c = st.node.children[k] {
                        next.append(State(node: c, score: st.score + spatialWeight * l - (k != t.key ? correctionPenalty : 0),
                                          corrected: st.corrected || k != t.key, slips: st.slips))
                    }
                }
                guard st.slips == 0 else { continue }
                // an extra tap: skip it
                next.append(State(node: st.node, score: st.score - slipPenalty, corrected: true, slips: 1))
                // a missed letter: any letter here, then this tap as typed
                if let tk = t.alternatives.first?.key {
                    for (_, c) in st.node.children {
                        if let d = c.children[tk] {
                            next.append(State(node: d, score: st.score - slipPenalty, corrected: true, slips: 1))
                        }
                    }
                }
            }
            // keep the likeliest, judged with the best word still reachable (an admissible look-ahead)
            next.sort { $0.score + $0.node.best > $1.score + $1.node.best }
            states = Array(next.prefix(beam))
            if states.isEmpty { return }
        }
        func offer(_ i: Int, _ s: Double, _ corrected: Bool, _ completion: Bool) {
            let w = lexicon.words[i]
            if (best[i]?.score ?? -.infinity) < s {
                best[i] = Suggestion(text: w.display, score: s, corrected: corrected, completion: completion)
            }
        }
        for st in states {
            if st.node.word >= 0 { offer(st.node.word, st.score + lexicon.words[st.node.word].logp, st.corrected, false) }
            if st.node.bestWord >= 0, st.node.bestWord != st.node.word {
                offer(st.node.bestWord, st.score + st.node.best - completionPenalty, st.corrected, true)
            }
        }
    }

    /// A typed string counts as a real word only when it is reasonably common (the word list also holds frequent
    /// misspellings such as "teh" and "realy", which must not shield themselves from correction).
    public var realWordZipf = 3.3

    /// Apostrophes and the pronoun I, as the system keyboard puts them in: dont → don't, im → I'm, i → I.
    public static let contractions: [String: String] = [
        "i": "I", "im": "I'm", "ive": "I've", "ill": "I'll", "id": "I'd",
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "cant": "can't", "wont": "won't", "isnt": "isn't",
        "arent": "aren't", "wasnt": "wasn't", "werent": "weren't", "hasnt": "hasn't", "havent": "haven't",
        "hadnt": "hadn't", "couldnt": "couldn't", "wouldnt": "wouldn't", "shouldnt": "shouldn't", "mustnt": "mustn't",
        "youre": "you're", "youve": "you've", "youll": "you'll", "youd": "you'd", "theyre": "they're",
        "theyve": "they've", "theyll": "they'll", "thats": "that's", "whats": "what's", "wheres": "where's",
        "whos": "who's", "theres": "there's", "heres": "here's", "hes": "he's", "shes": "she's", "lets": "let's",
        "weve": "we've", "wasn": "wasn't", "aint": "ain't", "yall": "y'all",
    ]
    /// Contractions that are also ordinary words ("ill", "id", "lets", "hes"…): offered, never applied by space.
    private static let ambiguousContractions: Set<String> = ["ill", "id", "lets", "hes", "shes", "wasn", "well", "were"]

    /// What space should type for this word: the correction when it is clearly better than what was typed, else nil
    /// (keep the typed letters). Never a completion; never for single letters (except i → I).
    public func autocorrection(_ taps: [Tap], suggestions s: [Suggestion]? = nil) -> Suggestion? {
        let typed0 = String(taps.map { $0.key }).lowercased()
        if let c = Self.contractions[typed0], !Self.ambiguousContractions.contains(typed0) {
            return Suggestion(text: c, score: 0, corrected: true, completion: false)
        }
        guard taps.count >= 2 else { return nil }
        let list = s ?? suggestions(taps)
        let typed = String(taps.map { $0.key }).lowercased()
        guard let top = list.first(where: { !$0.completion }), top.text.lowercased() != typed else { return nil }
        if let tw = lexicon.exact(typed), tw.zipf >= realWordZipf || tw.display != tw.key {
            // the typed word exists: change it only on strong evidence (and never a short real word)
            guard typed.count >= 4 else { return nil }
            let typedScore = tw.logp
            return top.score - typedScore > keepMargin ? top : nil
        }
        return top.corrected ? top : nil
    }

    /// The suggestion written the way the word was typed: Capitalised, ALL CAPS, or as the dictionary writes it.
    public static func cased(_ word: String, like typed: String) -> String {
        guard let first = typed.first else { return word }
        if typed.count > 1, typed == typed.uppercased(), typed != typed.lowercased() { return word.uppercased() }
        if first.isUppercase, let w0 = word.first { return String(w0).uppercased() + word.dropFirst() }
        return word
    }
}
