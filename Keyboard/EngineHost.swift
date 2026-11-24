import Foundation
import Darwin
import CoreText

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
    private let bgQueue = DispatchQueue(label: "mosto.bg", qos: .utility)
    // engine-queue state
    private var lexicon: Lexicon?
    private var decoder: Decoder?
    private var userDict: UserDictionary?
    private var readingsReady = false
    private var renderableGlyphCache: [UInt32: Bool] = [:]
    private static let glyphCheckFont: CTFont =
        CTFontCreateUIFontForLanguage(.system, 17, "zh-Hans" as CFString)
        ?? CTFontCreateWithName("PingFangSC-Regular" as CFString, 17, nil)
    private static var cachedEnglish: EnglishLexicon?
    private static var cachedEmojiHints: [String: [String]]?
    private static var cachedReadings: [Character: [UInt16]]?
    private static var cachedLexicon: Lexicon?
    private static var cachedGrammar: Grammar?
    private static var cachedSentence: Grammar?
    private static let isExtension = Bundle.main.bundlePath.hasSuffix(".appex")
    /// 表情联想: words → emoji (Unicode CLDR's Chinese annotations; Tools/build_emoji_hints.py)
    private var emojiHintsPath: String?
    private var emojiHintsLoaded = false
    private var emojiHints: [String: [String]] = [:]
    private static let kaomojiHints: [String: String] = [
        "开心": "ヾ(≧▽≦*)o", "高兴": "(≧∇≦)/", "哈哈": "(＾▽＾)", "哈哈哈": "ヾ(≧▽≦*)o",
        "笑死": "(≧∇≦)/", "嘿嘿": "(●'◡'●)", "晚安": "(∪｡∪)｡｡｡zzz", "困": "(￣o￣) . z Z",
        "好困": "(∪｡∪)｡｡｡zzz", "睡觉": "( ˘ω˘ ) ｽﾔｧ…", "早安": "( ´ ▽ ` )ﾉ", "辛苦了": "( ´▽｀)つ旦",
        "抱抱": "(づ￣ ³￣)づ", "贴贴": "(づ｡◕‿‿◕｡)づ", "爱你": "(´,,•ω•,,)♡", "喜欢": "(´∀`)♡",
        "比心": "(｡•ㅅ•｡)♡", "害羞": "(⁄ ⁄•⁄ω⁄•⁄ ⁄)", "卖萌": "(・ω・)", "猫猫": "(=^･ω･^=)",
        "狗狗": "U•ェ•*U", "委屈": "(｡•́︿•̀｡)", "难过": "QAQ", "破防": "(;´༎ຶД༎ຶ`)",
        "哭": "( T_T )", "呜呜": "(´;ω;`)", "生气": "(╬▔皿▔)╯", "掀桌": "(╯°□°)╯︵ ┻━┻",
        "震惊": "Σ(っ °Д °;)っ", "吃瓜": "(⊙ˍ⊙)", "无语": "(￣_,￣ )", "无奈": "╮(╯▽╰)╭",
        "摊手": "╮(￣▽￣)╭", "社恐": "(*/ω＼*)", "救命": "Σ(°△°|||)", "加油": "(๑•̀ㅂ•́)و✧",
        "冲": "(ง •̀_•́)ง", "好的": "(｡•̀ᴗ-)✧", "收到": "(｡･∀･)ﾉﾞ", "点赞": "(*￣▽￣)d",
        "厉害": "( •̀ ω •́ )✧", "比耶": "v(￣︶￣)y", "期待": "(☆▽☆)", "谢谢": "(´▽`ʃ♡ƪ)",
        "干杯": "( ^_^)／□☆□＼(^_^ )", "拜拜": "( ´ ▽ ` )ﾉ~~", "再见": "( ^_^)/~~",
        "摸鱼": "_(:3」∠)_", "躺平": "(:3[▓▓]", "好累": "_(:3」∠)_", "恶魔": "ψ(｀∇´)ψ",
        "魔头": "ψ(｀∇´)ψ", "小魔王": "Ψ(￣∀￣)Ψ", "可爱": "(｡･ω･｡)ﾉ♡", "女儿": "(づ｡◕‿‿◕｡)づ",
        "宝宝": "ヾ(≧▽≦*)o", "生日快乐": "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧"
    ]
    private static let sortedKaomojiHints: [(key: String, value: String)] = kaomojiHints.sorted { $0.key.count > $1.key.count }

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

    private func isRenderableCandidateText(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v < 0x20000 || scalar.properties.isEmoji { continue }
            if let cached = renderableGlyphCache[v] {
                if !cached { return false }
                continue
            }
            let s = String(scalar)
            let utf16 = Array(s.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
            let fallback = CTFontCreateForString(Self.glyphCheckFont, s as CFString, CFRange(location: 0, length: utf16.count))
            let psName = CTFontCopyPostScriptName(fallback) as String
            let ok = !psName.contains("LastResort")
                && CTFontGetGlyphsForCharacters(fallback, utf16, &glyphs, utf16.count)
                && !glyphs.isEmpty && glyphs[0] != 0
            if renderableGlyphCache.count > 512 { renderableGlyphCache.removeAll(keepingCapacity: true) }
            renderableGlyphCache[v] = ok
            if !ok { return false }
        }
        return true
    }

    private func ensureEmojiHints() {
        guard !emojiHintsLoaded else { return }
        emojiHintsLoaded = true
        if let cached = Self.cachedEmojiHints {
            emojiHints = cached
            return
        }
        // Keep well below the 60 MB keyboard extension Jetsam ceiling.
        guard let hp = emojiHintsPath, (!Self.isExtension || memoryFootprintMB() < 42) else { return }
        autoreleasepool {
            guard let text = try? String(contentsOfFile: hp, encoding: .utf8) else { return }
            var t: [String: [String]] = [:]; t.reserveCapacity(1200)
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "\t")
                if parts.count == 2 { t[String(parts[0])] = parts[1].split(separator: " ").map(String.init) }
            }
            Self.cachedEmojiHints = t
            emojiHints = t
        }
    }

    /// Background preload of compact single-char readings and emoji hints so live decode/predict never stalls on disk or lexicon scan.
    private func preloadAuxTables(lex: Lexicon, emojiPath: String?) {
        let needReadings = Self.cachedReadings == nil
        let needEmoji = Self.cachedEmojiHints == nil && emojiPath != nil
        guard needReadings || needEmoji else { return }
        bgQueue.async { [weak self] in
            guard let self else { return }
            var builtReadings: [Character: [UInt16]]?
            if needReadings && (!Self.isExtension || memoryFootprintMB() < 46) {
                builtReadings = Self.compactReadings(for: lex)
            }
            var builtHints: [String: [String]]?
            if needEmoji, let hp = emojiPath, (!Self.isExtension || memoryFootprintMB() < 42) {
                autoreleasepool {
                    if let text = try? String(contentsOfFile: hp, encoding: .utf8) {
                        var t: [String: [String]] = [:]; t.reserveCapacity(1200)
                        for line in text.split(separator: "\n") {
                            let parts = line.split(separator: "\t")
                            if parts.count == 2 { t[String(parts[0])] = parts[1].split(separator: " ").map(String.init) }
                        }
                        builtHints = t
                    }
                }
            }
            self.queue.async {
                if let r = builtReadings {
                    Self.cachedReadings = r
                    self.decoder?.setReadings(r)
                    self.readingsReady = true
                }
                if let h = builtHints {
                    Self.cachedEmojiHints = h
                    self.emojiHints = h
                    self.emojiHintsLoaded = true
                }
            }
        }
    }

    /// Two-stage load in .appex: open lexicon.bin (~2 ms) and mark ready immediately so the first keystroke decodes
    /// with zero stall, while secondary mmaps and auxiliary tables stream in on `bgQueue`.
    func load(lexiconPath: String?, englishPath: String?, grammarPath: String?, sentencePath: String? = nil, userDictURL: URL?,
              safe: Bool = false, emojiHintsPath: String? = nil, onEnglishLoaded: ((EnglishLexicon) -> Void)? = nil) {
        let t0 = CFAbsoluteTimeGetCurrent()
        queue.async {
            self.emojiHintsPath = safe ? nil : emojiHintsPath
            self.emojiHintsLoaded = false
            guard let path = lexiconPath, let lex = Self.cachedLexicon ?? (try? Lexicon(path: path)) else { return }
            Self.cachedLexicon = lex
            self.lexicon = lex
            let ud = UserDictionary(lexicon: lex, url: userDictURL)
            self.userDict = ud
            let d = Decoder(lexicon: lex, user: ud)
            self.readingsReady = safe
            if safe {
                d.setReadings(["\0": []])
            } else if let cr = Self.cachedReadings {
                d.setReadings(cr)
                self.readingsReady = true
            }
            var enLex: EnglishLexicon? = safe ? nil : Self.cachedEnglish
            if let enLex { d.english = enLex }
            let cachedGram = safe ? nil : Self.cachedGrammar
            let cachedSent = safe ? nil : Self.cachedSentence
            if let cachedSent {
                d.predictionGrammar = cachedGram ?? cachedSent
                d.grammar = cachedSent
            } else if let cachedGram {
                d.grammar = cachedGram
            }
            if !safe, let eh = Self.cachedEmojiHints {
                self.emojiHints = eh
                self.emojiHintsLoaded = true
            }
            if !Self.isExtension {
                if !safe, enLex == nil, let ep = englishPath {
                    enLex = try? EnglishLexicon(path: ep)
                    Self.cachedEnglish = enLex
                    d.english = enLex
                }
                var gram = cachedGram
                if !safe, gram == nil, let gp = grammarPath {
                    gram = try? Grammar(path: gp)
                    Self.cachedGrammar = gram
                    if d.grammar == nil { d.grammar = gram } else if cachedSent != nil { d.predictionGrammar = gram }
                }
                if !safe, cachedSent == nil, let sp = sentencePath, let sentence = try? Grammar(path: sp) {
                    Self.cachedSentence = sentence
                    d.predictionGrammar = gram ?? d.grammar
                    d.grammar = sentence
                }
                if !safe { self.ensureEmojiHints() }
            }
            self.decoder = d
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            self.lock.lock()
            self.sharedEnglish = enLex
            self.sharedLexiconCount = lex.entryCount
            self.sharedLearnedCount = ud.count
            self.sharedLoadMs = elapsedMs
            self.loaded = true
            self.lock.unlock()
            if let enLex { DispatchQueue.main.async { onEnglishLoaded?(enLex) } }
            if Self.isExtension && !safe {
                let needEn = enLex == nil ? englishPath : nil
                let needGr = cachedGram == nil ? grammarPath : nil
                let needSe = cachedSent == nil ? sentencePath : nil
                if needEn != nil || needGr != nil || needSe != nil {
                    self.bgQueue.async { [weak self = self] in
                        guard let self else { return }
                        if let ep = needEn, let en = try? EnglishLexicon(path: ep) {
                            self.queue.async {
                                Self.cachedEnglish = en
                                self.decoder?.english = en
                                self.lock.lock(); self.sharedEnglish = en; self.lock.unlock()
                            }
                            DispatchQueue.main.async { onEnglishLoaded?(en) }
                        }
                        var gram = cachedGram
                        if let gp = needGr, let g = try? Grammar(path: gp) {
                            gram = g
                            self.queue.async {
                                Self.cachedGrammar = g
                                if self.decoder?.grammar == nil { self.decoder?.grammar = g }
                                else { self.decoder?.predictionGrammar = g }
                            }
                        }
                        if let sp = needSe, let s = try? Grammar(path: sp) {
                            let pGram = gram
                            self.queue.async {
                                Self.cachedSentence = s
                                self.decoder?.predictionGrammar = pGram ?? self.decoder?.grammar
                                self.decoder?.grammar = s
                            }
                        }
                        self.preloadAuxTables(lex: lex, emojiPath: emojiHintsPath)
                    }
                } else {
                    self.preloadAuxTables(lex: lex, emojiPath: emojiHintsPath)
                }
            }
            if !safe {
                self.queue.asyncAfter(deadline: .now() + 0.05) { [weak self = self] in
                    guard let self else { return }
                    self.lock.lock(); let idle = self.latest == 0; self.lock.unlock()
                    if idle { autoreleasepool { _ = d.decode([Tap.exact("w"), Tap.exact("o")]) } }
                }
            }
        }
    }

    /// Memory warning: write the learned words out now and release static caches if needed.
    func trim() {
        queue.async {
            self.userDict?.save()
            Self.cachedReadings = nil
            Self.cachedEmojiHints = nil
            self.emojiHints = [:]
            self.emojiHintsLoaded = false
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

    private func run(_ taps: [Tap], literal: Bool, hasCommittedParts: Bool) -> Output? {
        guard let d = decoder else { return nil }
        let was = d.correctionEnabled
        if literal { d.correctionEnabled = false }
        var r = d.decode(taps)
        d.correctionEnabled = was
        if !r.candidates.isEmpty, r.candidates[0].corrected { r.candidates[0].fixes = d.fixes(for: r.candidates[0], taps: taps) }
        if r.candidates.count > 1, !r.candidates[0].corrected, r.candidates[1].corrected {
            r.candidates[1].fixes = d.fixes(for: r.candidates[1], taps: taps)
        }
        if let first = r.candidates.first, first.tapCount == taps.count, first.text.count >= 2 {
            if !Self.isExtension && !emojiHintsLoaded { ensureEmojiHints() }
            let dyn = Self.dynamicDateCandidate(for: first.text)
            let at = min(dyn != nil ? 1 : 2, r.candidates.count)
            var items = Array((emojiHints[first.text] ?? []).prefix(1))
            if let kao = Self.kaomojiHints[first.text] { items.append(kao) }
            if let dyn { items.insert(dyn, at: 0) }
            let extra = items.prefix(2).filter { e in !r.candidates.contains { $0.text == e } }.map { Candidate(text: $0, tapCount: taps.count, syllables: [], corrected: false, score: first.score - 50) }
            if !extra.isEmpty { r.candidates.insert(contentsOf: extra, at: at) }
        }
        // Single-char interleaving, deduplication, and CoreText non-BMP tofu filtering off the main thread.
        let sc: (Candidate) -> Bool = { $0.text.count == 1 && !$0.syllables.isEmpty && !$0.isEnglish }
        if hasCommittedParts {
            let topFull = r.candidates.prefix(1).filter { $0.tapCount == taps.count && !sc($0) }
            let rest = r.candidates.dropFirst(topFull.count)
            r.candidates = Array(topFull) + rest.filter(sc) + rest.filter { !sc($0) }
        } else if taps.count == 2, r.candidates.count > 2 {
            let t = r.candidates.dropFirst(2)
            r.candidates = Array(r.candidates.prefix(2)) + t.filter(sc) + t.filter { !sc($0) }
        } else if taps.count == 4, r.candidates.count > 3 {
            let t = r.candidates.dropFirst(3); let s = t.filter(sc)
            r.candidates = Array(r.candidates.prefix(3)) + Array(s.prefix(2)) + t.filter { !sc($0) } + Array(s.dropFirst(2))
        } else if taps.count >= 5, r.candidates.count > 3 {
            let t = r.candidates.dropFirst(2); let m = t.filter { !sc($0) }; let s = t.filter(sc)
            r.candidates = Array(r.candidates.prefix(2)) + Array(m.prefix(2)) + Array(s.prefix(2)) + Array(m.dropFirst(2)) + Array(s.dropFirst(2))
        }
        var seen = Set<String>()
        r.candidates = r.candidates.filter { seen.insert($0.text).inserted }
        let renderable = r.candidates.filter { isRenderableCandidateText($0.text) }
        if !renderable.isEmpty { r.candidates = renderable }

        var choices: (start: Int, choices: [(text: String, keys: [Character])]) = (0, [])
        if taps.contains(where: { $0.group }) { choices = d.t9SyllableChoices(taps) }
        return Output(result: r, choices: choices)
    }

    /// Offline relative date/time candidates: 日期, 时间/现在, 星期, 今天..大后天, 昨天/前天, 本/上/下个月, 上/本/下周一..日.
    private static func dynamicDateCandidate(for word: String, now: Date = Date()) -> String? {
        let cal = Calendar.current
        let wds = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        func md(_ d: Date, weekday: Bool) -> String {
            let m = cal.component(.month, from: d)
            let day = cal.component(.day, from: d)
            if weekday {
                let wd = cal.component(.weekday, from: d)
                let label = (wd >= 1 && wd <= 7) ? " " + wds[wd - 1] : ""
                return "\(m)月\(day)日\(label)"
            }
            return "\(m)月\(day)日"
        }
        switch word {
        case "日期":
            let y = cal.component(.year, from: now), m = cal.component(.month, from: now), d = cal.component(.day, from: now)
            return String(format: "%04d-%02d-%02d", y, m, d)
        case "时间", "现在":
            let h = cal.component(.hour, from: now), m = cal.component(.minute, from: now)
            return String(format: "%02d:%02d", h, m)
        case "星期":
            let wd = cal.component(.weekday, from: now)
            return (wd >= 1 && wd <= 7) ? wds[wd - 1] : nil
        case "今天":
            return md(now, weekday: true)
        case "明天":
            return cal.date(byAdding: .day, value: 1, to: now).map { md($0, weekday: true) }
        case "后天":
            return cal.date(byAdding: .day, value: 2, to: now).map { md($0, weekday: true) }
        case "大后天":
            return cal.date(byAdding: .day, value: 3, to: now).map { md($0, weekday: true) }
        case "昨天":
            return cal.date(byAdding: .day, value: -1, to: now).map { md($0, weekday: true) }
        case "前天":
            return cal.date(byAdding: .day, value: -2, to: now).map { md($0, weekday: true) }
        case "今年":
            return "\(cal.component(.year, from: now))年"
        case "明年":
            return "\(cal.component(.year, from: now) + 1)年"
        case "去年":
            return "\(cal.component(.year, from: now) - 1)年"
        case "本月", "这个月":
            return "\(cal.component(.month, from: now))月"
        case "上个月":
            return cal.date(byAdding: .month, value: -1, to: now).map { "\(cal.component(.month, from: $0))月" }
        case "下个月":
            return cal.date(byAdding: .month, value: 1, to: now).map { "\(cal.component(.month, from: $0))月" }
        default:
            break
        }
        let nextPrefix = word.hasPrefix("下周") || word.hasPrefix("下星期")
        let thisPrefix = word.hasPrefix("本周") || word.hasPrefix("这周")
        let prevPrefix = word.hasPrefix("上周") || word.hasPrefix("上星期")
        guard nextPrefix || thisPrefix || prevPrefix, let last = word.last else { return nil }
        let targetMonBased: Int
        switch last {
        case "一": targetMonBased = 1
        case "二": targetMonBased = 2
        case "三": targetMonBased = 3
        case "四": targetMonBased = 4
        case "五": targetMonBased = 5
        case "六": targetMonBased = 6
        case "日", "天": targetMonBased = 7
        default: return nil
        }
        // Convert Calendar weekday (1=Sun..7=Sat) to Monday-based (1=Mon..7=Sun).
        let todayWD = cal.component(.weekday, from: now)
        let todayMonBased = todayWD == 1 ? 7 : todayWD - 1
        let weekShift = nextPrefix ? 7 : (prevPrefix ? -7 : 0)
        let delta = weekShift + (targetMonBased - todayMonBased)
        return cal.date(byAdding: .day, value: delta, to: now).map { md($0, weekday: false) }
    }

    /// Decode in the background; `done` runs on the main thread (nil until the engine has loaded). A request that a
    /// newer one has replaced before its turn comes is skipped (fast typing queues one decode per key; only the
    /// latest is ever shown), so the queue never builds a backlog.
    func decode(_ taps: [Tap], literal: Bool = false, hasCommittedParts: Bool = false, generation: Int, done: @escaping (Output?) -> Void) {
        lock.lock(); latest = max(latest, generation); predictTicket += 1; lock.unlock()
        queue.async {
            self.lock.lock(); let superseded = generation < self.latest; self.lock.unlock()
            if superseded { return }
            let out = self.run(taps, literal: literal, hasCommittedParts: hasCommittedParts)
            self.lock.lock()
            self.lastOut = (generation, literal, out)
            self.lock.unlock()
            DispatchQueue.main.async { done(out) }
        }
    }
    private let lock = NSLock()
    private var latest = 0
    private var predictTicket = 0
    private var loaded = false
    private var sharedEnglish: EnglishLexicon?
    private var sharedLexiconCount = 0
    private var sharedLearnedCount = 0
    private var sharedLoadMs: Double = 0
    /// The engine has loaded (the lexicon at least).
    var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return loaded }
    var loadMs: Double { lock.lock(); defer { lock.unlock() }; return sharedLoadMs }
    var englishLexicon: EnglishLexicon? { lock.lock(); defer { lock.unlock() }; return sharedEnglish }
    // protected by `lock`: the last background decode, so a commit that needs it right away does not wait or re-decode
    private var lastOut: (generation: Int, literal: Bool, out: Output?)?

    /// Decode now, waiting for whatever is queued before it (used by the simulator test bench and snapshot renderer).
    /// With `generation`, the background decode already queued for that generation is used when it has run.
    func decodeNow(_ taps: [Tap], literal: Bool = false, hasCommittedParts: Bool = false, generation: Int? = nil) -> Output? {
        if let g = generation {
            lock.lock()
            let cached = lastOut
            lock.unlock()
            if let last = cached, last.generation == g, last.literal == literal, last.out != nil {
                return last.out
            }
        }
        return queue.sync {
            if let g = generation {
                self.lock.lock(); let cached = self.lastOut; self.lock.unlock()
                if let last = cached, last.generation == g, last.literal == literal, last.out != nil {
                    return last.out
                }
            }
            return run(taps, literal: literal, hasCommittedParts: hasCommittedParts)
        }
    }

    /// Non-blocking bounded decode for live keyboard commits: hits lock-protected cache in microseconds when ready,
    /// never waits on cold start, and never stalls past `timeout`.
    func decodeWithTimeout(_ taps: [Tap], literal: Bool = false, hasCommittedParts: Bool = false, generation: Int? = nil, timeout: TimeInterval = 0.025) -> Output? {
        lock.lock()
        let ready = loaded
        let cached = lastOut
        lock.unlock()
        guard ready else { return nil }
        if let g = generation, let last = cached, last.generation == g, last.literal == literal, let out = last.out {
            return out
        }
        let sem = DispatchSemaphore(value: 0)
        var result: Output?
        queue.async {
            if let g = generation {
                self.lock.lock(); let latestCached = self.lastOut; self.lock.unlock()
                if let last = latestCached, last.generation == g, last.literal == literal, let out = last.out {
                    result = out
                    sem.signal()
                    return
                }
            }
            result = self.run(taps, literal: literal, hasCommittedParts: hasCommittedParts)
            sem.signal()
        }
        return sem.wait(timeout: .now() + timeout) == .success ? result : nil
    }

    /// 联想: what may come next after the text before the cursor; preemptible by live typing (`predictTicket`).
    func predict(after context: String, done: @escaping ([String]) -> Void) {
        let ctx = Array(context.suffix(8))   // the model reads three; the user's own phrases may match more
        lock.lock(); predictTicket += 1; let ticket = predictTicket; lock.unlock()
        queue.async {
            self.lock.lock(); let stale = ticket != self.predictTicket; self.lock.unlock()
            if stale { return }
            if !self.readingsReady, let lex = self.lexicon, let d = self.decoder {
                if Self.isExtension { return }
                self.readingsReady = true
                if !Self.isExtension || memoryFootprintMB() < 46 {
                    d.setReadings(Self.compactReadings(for: lex))
                } else {
                    d.setReadings(["\0": []])
                }
            }
            let raw = self.decoder?.predictions(after: ctx) ?? []; var singles = 0; var p = raw.filter { if $0.count == 1 { singles += 1; return singles <= 2 }; return true }; let tail = String(ctx); if !p.isEmpty { for (k, kao) in Self.sortedKaomojiHints where tail.hasSuffix(k) { if !Self.isExtension && !self.emojiHintsLoaded { self.ensureEmojiHints() }; if let em = self.emojiHints[k]?.first, !p.contains(em) { p.insert(em, at: min(2, p.count)) }; if !p.contains(kao) { p.insert(kao, at: min(3, p.count)) }; break } }; p = Array(p.prefix(5))
            DispatchQueue.main.async { done(p) }
        }
    }

    // MARK: learned words

    private func syncLearnedCount() {
        let c = userDict?.count ?? 0
        lock.lock(); sharedLearnedCount = c; lock.unlock()
    }

    func learn(syllables: [UInt16], text: String) { queue.async { self.userDict?.learn(syllables: syllables, text: text); self.syncLearnedCount() } }
    func learn(parts: [(text: String, ids: [UInt16])]) { queue.async { self.userDict?.learn(parts: parts); self.syncLearnedCount() } }
    func unlearn(syllables: [UInt16], text: String) { queue.async { self.userDict?.unlearn(syllables: syllables, text: text); self.syncLearnedCount() } }
    func forget(syllables: [UInt16], text: String) {
        queue.async { self.userDict?.forget(syllables: syllables, text: text); self.userDict?.save(); self.syncLearnedCount() }
    }
    func resetLearning() { queue.async { self.userDict?.reset(); self.syncLearnedCount() } }
    func save() { queue.async { self.userDict?.save() } }
    func knows(syllables: [UInt16], text: String) -> Bool {
        guard isLoaded else { return false }
        return queue.sync { userDict?.contains(syllables: syllables, text: text) ?? false }
    }
    func knows(syllables: [UInt16], text: String, done: @escaping (Bool) -> Void) {
        queue.async {
            let found = self.userDict?.contains(syllables: syllables, text: text) ?? false
            DispatchQueue.main.async { done(found) }
        }
    }
    /// Entries in the lexicon and words learned, for the settings page (lock-protected, never blocks main thread).
    func counts() -> (lexicon: Int, learned: Int) {
        lock.lock(); defer { lock.unlock() }
        return (sharedLexiconCount, sharedLearnedCount)
    }
}
