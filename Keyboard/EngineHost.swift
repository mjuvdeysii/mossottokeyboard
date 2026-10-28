import Foundation

/// The input engine on its own thread. Everything that reads or changes the decoder or the learned words runs on one
/// serial queue, so the main thread — which draws the keys and talks to the text field — never waits for a decode:
/// a key press shows its letters at once and the candidates follow a moment later. A commit (space, a candidate)
/// that needs the candidates for exactly the keys typed waits only for the decode already under way.
final class EngineHost {
    struct Output {
        let result: Decoder.Result
        /// 九宫格 拼音选择: where the keypad keys start and the syllables they can spell (empty without keypad keys).
        let choices: (start: Int, choices: [(text: String, keys: [Character])])
    }

    private let queue = DispatchQueue(label: "mosto.engine", qos: .userInteractive)
    // engine-queue state
    private var lexicon: Lexicon?
    private var decoder: Decoder?
    private var userDict: UserDictionary?

    /// Load the lexicon, the learned words and the English list (memory-mapped files: quick, and off the main thread).
    func load(lexiconPath: String?, englishPath: String?, grammarPath: String?, userDictURL: URL?) {
        queue.async {
            guard let path = lexiconPath, let lex = try? Lexicon(path: path) else { return }
            self.lexicon = lex
            let ud = UserDictionary(lexicon: lex, url: userDictURL)
            self.userDict = ud
            let d = Decoder(lexicon: lex, user: ud)
            if let ep = englishPath { d.english = try? EnglishLexicon(path: ep) }
            if let gp = grammarPath { d.grammar = try? Grammar(path: gp) }
            self.decoder = d
        }
    }

    /// The text just before the cursor (the language model reads the first word in its context).
    func setContext(_ text: String) {
        let ctx = Array(text.suffix(3))
        queue.async { self.decoder?.leftContext = ctx }
    }

    /// Settings that change how keys are read (applied in order with the decodes).
    func configure(scheme: PinyinScheme, correction: Bool, english: Bool) {
        queue.async {
            self.decoder?.scheme = scheme
            self.decoder?.correctionEnabled = correction
            self.decoder?.englishEnabled = english
        }
    }

    private func run(_ taps: [Tap], literal: Bool) -> Output? {
        guard let d = decoder else { return nil }
        let was = d.correctionEnabled
        if literal { d.correctionEnabled = false }
        let r = d.decode(taps)
        d.correctionEnabled = was
        var choices: (start: Int, choices: [(text: String, keys: [Character])]) = (0, [])
        if taps.contains(where: { $0.group }) { choices = d.t9SyllableChoices(taps) }
        return Output(result: r, choices: choices)
    }

    /// Decode in the background; `done` runs on the main thread (nil until the engine has loaded). A request that a
    /// newer one has replaced before its turn comes is skipped (fast typing queues one decode per key; only the
    /// latest is ever shown), so the queue never builds a backlog.
    func decode(_ taps: [Tap], literal: Bool = false, generation: Int, done: @escaping (Output?) -> Void) {
        lock.lock(); latest = max(latest, generation); lock.unlock()
        queue.async {
            self.lock.lock(); let superseded = generation < self.latest; self.lock.unlock()
            if superseded { return }
            let out = self.run(taps, literal: literal)
            DispatchQueue.main.async { done(out) }
        }
    }
    private let lock = NSLock()
    private var latest = 0

    /// Decode now, waiting for whatever is queued before it (used only when a commit needs the exact candidates).
    func decodeNow(_ taps: [Tap], literal: Bool = false) -> Output? {
        queue.sync { run(taps, literal: literal) }
    }

    // MARK: learned words

    func learn(syllables: [UInt16], text: String) { queue.async { self.userDict?.learn(syllables: syllables, text: text) } }
    func learn(parts: [(text: String, ids: [UInt16])]) { queue.async { self.userDict?.learn(parts: parts) } }
    func unlearn(syllables: [UInt16], text: String) { queue.async { self.userDict?.unlearn(syllables: syllables, text: text) } }
    func forget(syllables: [UInt16], text: String) {
        queue.async { self.userDict?.forget(syllables: syllables, text: text); self.userDict?.save() }
    }
    func resetLearning() { queue.async { self.userDict?.reset() } }
    /// Written to disk; waits so the file is saved before the keyboard goes away.
    func save() { queue.sync { self.userDict?.save() } }
    func knows(syllables: [UInt16], text: String) -> Bool { queue.sync { userDict?.contains(syllables: syllables, text: text) ?? false } }
    /// Entries in the lexicon and words learned, for the settings page.
    func counts() -> (lexicon: Int, learned: Int) { queue.sync { (lexicon?.entryCount ?? 0, userDict?.count ?? 0) } }
}
