import Foundation
import Darwin

/// This process's memory as iOS counts it against the keyboard's limit (phys_footprint: dirty and compressed pages;
/// the memory-mapped lexicon, language model and English list are clean file pages and do not count), in MB.
func memoryFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

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
    /// 表情联想: words → emoji (Unicode CLDR's Chinese annotations; Tools/build_emoji_hints.py)
    private var emojiHints: [String: [String]] = [:]

    /// Load the lexicon, the learned words and the English list (memory-mapped files: quick, and off the main thread).
    /// `safe`: after launches that ended early (a crash, or iOS ending the keyboard while it was starting), the
    /// keyboard starts with the lexicon and learned words only — no language model, no English — so it stays up
    /// rather than iOS falling back to the system keyboard again.
    /// `sentencePath`: the sentence model (万象, a large modern corpus) that reads the keys; `grammarPath` then serves
    /// 联想 only. Without it, `grammarPath` does both.
    func load(lexiconPath: String?, englishPath: String?, grammarPath: String?, sentencePath: String? = nil, userDictURL: URL?,
              safe: Bool = false, emojiHintsPath: String? = nil) {
        queue.async {
            if !safe, let hp = emojiHintsPath, let text = try? String(contentsOfFile: hp, encoding: .utf8) {
                var t: [String: [String]] = [:]
                for line in text.split(separator: "\n") {
                    let parts = line.split(separator: "\t")
                    if parts.count == 2 { t[String(parts[0])] = parts[1].split(separator: " ").map(String.init) }
                }
                self.emojiHints = t
            }
            guard let path = lexiconPath, let lex = try? Lexicon(path: path) else { return }
            self.lexicon = lex
            let ud = UserDictionary(lexicon: lex, url: userDictURL)
            self.userDict = ud
            let d = Decoder(lexicon: lex, user: ud)
            if !safe, let ep = englishPath { d.english = try? EnglishLexicon(path: ep) }
            if !safe, let gp = grammarPath { d.grammar = try? Grammar(path: gp) }
            if !safe, let sp = sentencePath, let sentence = try? Grammar(path: sp) {
                d.predictionGrammar = d.grammar
                d.grammar = sentence
            }
            self.decoder = d
            self.lock.lock(); self.loaded = true; self.lock.unlock()
            // the character table 联想 uses: built beside the decoder's thread, never in front of a keystroke
            DispatchQueue.global(qos: .utility).async {
                let table = Decoder.readingsTable(lex)
                self.queue.async { d.setReadings(table) }
            }
        }
    }

    /// Memory warning: write the learned words out now (nothing is lost if iOS ends the keyboard next).
    func trim() { queue.async { self.userDict?.save() } }

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
        var r = d.decode(taps)
        d.correctionEnabled = was
        // what the first candidate corrected, for the strip to show (hap → hao)
        if !r.candidates.isEmpty, r.candidates[0].corrected { r.candidates[0].fixes = d.fixes(for: r.candidates[0], taps: taps) }
        // a word that has an emoji (哈哈 😂, 蛋糕 🎂): offered after the first few candidates, never before them
        if let first = r.candidates.first, first.tapCount == taps.count, let emoji = emojiHints[first.text] {
            let at = min(3, r.candidates.count)
            let extra = emoji.prefix(2).filter { e in !r.candidates.contains { $0.text == e } }.map {
                Candidate(text: $0, tapCount: taps.count, syllables: [], corrected: false, score: first.score - 50)
            }
            r.candidates.insert(contentsOf: extra, at: at)
        }
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
            self.lastOut = (generation, literal, out)
            DispatchQueue.main.async { done(out) }
        }
    }
    private let lock = NSLock()
    private var latest = 0
    private var loaded = false
    /// The engine has loaded (the lexicon at least).
    var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return loaded }
    // engine-queue state: the last background decode, so a commit that needs it right away does not decode again
    private var lastOut: (generation: Int, literal: Bool, out: Output?)?

    /// Decode now, waiting for whatever is queued before it (used only when a commit needs the exact candidates).
    /// With `generation`, the background decode already queued for that generation is used when it has run.
    func decodeNow(_ taps: [Tap], literal: Bool = false, generation: Int? = nil) -> Output? {
        queue.sync {
            if let g = generation, let last = lastOut, last.generation == g, last.literal == literal, last.out != nil {
                return last.out
            }
            return run(taps, literal: literal)
        }
    }

    /// 联想: what may come next after the text before the cursor; `done` on the main thread.
    func predict(after context: String, done: @escaping ([String]) -> Void) {
        let ctx = Array(context.suffix(8))   // the model reads three; the user's own phrases may match more
        queue.async {
            let p = self.decoder?.predictions(after: ctx) ?? []
            DispatchQueue.main.async { done(p) }
        }
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
