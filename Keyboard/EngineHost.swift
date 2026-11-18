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
    private var readingsReady = false
    private static var cachedEnglish: EnglishLexicon?
    private static var cachedEmojiHints: [String: [String]]?
    private static var cachedReadings: [Character: [UInt16]]?
    private static var cachedLexicon: Lexicon?
    private static var cachedGrammar: Grammar?
    private static var cachedSentence: Grammar?
    /// 表情联想: words → emoji (Unicode CLDR's Chinese annotations; Tools/build_emoji_hints.py)
    private var emojiHints: [String: [String]] = [:]; private static let kaomojiHints: [String: String] = ["开心": "ヾ(≧▽≦*)o", "高兴": "(≧∇≦)/", "哈哈": "(＾▽＾)", "哈哈哈": "ヾ(≧▽≦*)o", "笑死": "(≧∇≦)/", "嘿嘿": "(●'◡'●)", "晚安": "(∪｡∪)｡｡｡zzz", "困": "(￣o￣) . z Z", "好困": "(∪｡∪)｡｡｡zzz", "睡觉": "( ˘ω˘ ) ｽﾔｧ…", "抱抱": "(づ￣ ³￣)づ", "爱你": "(´,,•ω•,,)♡", "喜欢": "(´∀`)♡", "比心": "(｡•ㅅ•｡)♡", "卖萌": "(・ω・)", "委屈": "(｡•́︿•̀｡)", "难过": "QAQ", "哭": "( T_T )", "呜呜": "(´;ω;`)", "生气": "(╬▔皿▔)╯", "掀桌": "(╯°□°)╯︵ ┻━┻", "震惊": "Σ(っ °Д °;)っ", "无奈": "╮(╯▽╰)╭", "摊手": "╮(￣▽￣)╭", "加油": "(๑•̀ㅂ•́)و✧", "冲": "(ง •̀_•́)ง", "好的": "(｡•̀ᴗ-)✧", "收到": "(｡･∀･)ﾉﾞ", "谢谢": "(´▽`ʃ♡ƪ)", "摸鱼": "_(:3」∠)_", "躺平": "(:3[▓▓]", "好累": "_(:3」∠)_", "恶魔": "ψ(｀∇´)ψ", "魔头": "ψ(｀∇´)ψ", "小魔王": "Ψ(￣∀￣)Ψ", "可爱": "(｡･ω･｡)ﾉ♡", "女儿": "(づ｡◕‿‿◕｡)づ", "宝宝": "ヾ(≧▽≦*)o"]

    private static func compactReadings(for lex: Lexicon) -> [Character: [UInt16]] {
        if let cached = cachedReadings { return cached }
        var t: [Character: [UInt16]] = [:]
        t.reserveCapacity(3600)
        autoreleasepool {
            for sid in 0..<lex.syllables.count {
                let range = lex.range(firstSyllable: UInt16(sid))
                var i = range.lowerBound; let end = range.upperBound
                while i < end {
                    let e = lex.entry(i)
                    if e.sylCount != 1 { break }
                    if e.score >= 800, let ch = lex.text(e).first, (t[ch]?.count ?? 0) < 4 { t[ch, default: []].append(UInt16(sid)) }
                    i += 1
                }
            }
        }
        if t.isEmpty { t["\0"] = [] }
        cachedReadings = t
        return t
    }

    /// Load the lexicon, the learned words and the English list (memory-mapped files: quick, and off the main thread).
    func load(lexiconPath: String?, englishPath: String?, grammarPath: String?, sentencePath: String? = nil, userDictURL: URL?,
              safe: Bool = false, emojiHintsPath: String? = nil, onEnglishLoaded: ((EnglishLexicon) -> Void)? = nil) {
        queue.async {
            if !safe, let hp = emojiHintsPath {
                if let cached = Self.cachedEmojiHints {
                    self.emojiHints = cached
                } else if let text = try? String(contentsOfFile: hp, encoding: .utf8) {
                    var t: [String: [String]] = [:]; t.reserveCapacity(1200)
                    for line in text.split(separator: "\n") {
                        let parts = line.split(separator: "\t")
                        if parts.count == 2 { t[String(parts[0])] = parts[1].split(separator: " ").map(String.init) }
                    }
                    Self.cachedEmojiHints = t; self.emojiHints = t
                }
            }
            guard let path = lexiconPath, let lex = Self.cachedLexicon ?? (try? Lexicon(path: path)) else { return }
            Self.cachedLexicon = lex
            self.lexicon = lex
            let ud = UserDictionary(lexicon: lex, url: userDictURL)
            self.userDict = ud
            let d = Decoder(lexicon: lex, user: ud)
            self.readingsReady = safe
            if safe { d.setReadings(["\0": []]) }
            var enLex: EnglishLexicon?
            if !safe, let ep = englishPath {
                enLex = Self.cachedEnglish ?? (try? EnglishLexicon(path: ep))
                Self.cachedEnglish = enLex
                d.english = enLex
            }
            if !safe, let gp = grammarPath {
                let g = Self.cachedGrammar ?? (try? Grammar(path: gp))
                Self.cachedGrammar = g
                d.grammar = g
            }
            if !safe, let sp = sentencePath {
                if let sentence = Self.cachedSentence ?? (try? Grammar(path: sp)) {
                    Self.cachedSentence = sentence
                    d.predictionGrammar = d.grammar
                    d.grammar = sentence
                }
            }
            self.decoder = d
            self.lock.lock(); self.sharedEnglish = enLex; self.loaded = true; self.lock.unlock()
            if let enLex { DispatchQueue.main.async { onEnglishLoaded?(enLex) } }
            if !safe {
                self.queue.async { autoreleasepool { _ = d.decode([Tap.exact("w"), Tap.exact("o")]) } }
            }
            }
    }

    /// Memory warning: write the learned words out now and release static caches if needed.
    func trim() { queue.async { self.userDict?.save(); Self.cachedReadings = nil } }

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
        // the keys as typed read first, a correction second (kw → ke): that one says what it would change
        if r.candidates.count > 1, !r.candidates[0].corrected, r.candidates[1].corrected {
            r.candidates[1].fixes = d.fixes(for: r.candidates[1], taps: taps)
        }
        // a word that has an emoji (哈哈 😂, 蛋糕 🎂): offered after the first few candidates, never before them
        if let first = r.candidates.first, first.tapCount == taps.count, first.text.count >= 2 {
            let isUtil = first.text == "日期" || first.text == "时间" || first.text == "星期"; let at = min(isUtil ? 1 : 2, r.candidates.count); var items = Array((emojiHints[first.text] ?? []).prefix(1))
            if let kao = Self.kaomojiHints[first.text] { items.append(kao) }; if first.text == "日期" { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; items.insert(f.string(from: Date()), at: 0) } else if first.text == "时间" { let f = DateFormatter(); f.dateFormat = "HH:mm"; items.insert(f.string(from: Date()), at: 0) } else if first.text == "星期" { let wd = Calendar.current.component(.weekday, from: Date()); let wds = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]; if wd >= 1 && wd <= 7 { items.insert(wds[wd - 1], at: 0) } }
            let extra = items.prefix(2).filter { e in !r.candidates.contains { $0.text == e } }.map { Candidate(text: $0, tapCount: taps.count, syllables: [], corrected: false, score: first.score - 50) }
            if !extra.isEmpty { r.candidates.insert(contentsOf: extra, at: at) }
            // inline emoji/kaomoji restrained to <=2 items at slot 2 (after top 2 words); date/time at slot 1
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
    private var sharedEnglish: EnglishLexicon?
    /// The engine has loaded (the lexicon at least).
    var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return loaded }
    var englishLexicon: EnglishLexicon? { lock.lock(); defer { lock.unlock() }; return sharedEnglish }
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
            if !self.readingsReady, let lex = self.lexicon, let d = self.decoder {
                self.readingsReady = true
                d.setReadings(Self.compactReadings(for: lex))
            }
            var raw = self.decoder?.predictions(after: ctx) ?? []; var singles = 0; var p = raw.filter { if $0.count == 1 { singles += 1; return singles <= 2 }; return true }; let tail = String(ctx); if !p.isEmpty { for (k, kao) in Self.kaomojiHints.sorted(by: { $0.key.count > $1.key.count }) where tail.hasSuffix(k) { if let em = self.emojiHints[k]?.first, !p.contains(em) { p.insert(em, at: min(2, p.count)) }; if !p.contains(kao) { p.insert(kao, at: min(3, p.count)) }; break } }; p = Array(p.prefix(5))
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
    func save() { queue.async { self.userDict?.save() } }
    func knows(syllables: [UInt16], text: String) -> Bool { queue.sync { userDict?.contains(syllables: syllables, text: text) ?? false } }
    /// Entries in the lexicon and words learned, for the settings page.
    func counts() -> (lexicon: Int, learned: Int) { queue.sync { (lexicon?.entryCount ?? 0, userDict?.count ?? 0) } }
}
