import UIKit
import SwiftUI

/// CI-only: launched with `-renderKeyboardSnapshots`, the container app renders the keyboard's real UIKit views
/// (the same KeyboardView / CandidateBarView / MostoView / panels the extension uses) to PNGs in
/// Documents/snapshots, then exits. The workflow copies them to the ci-logs branch for visual review.
/// The system's Liquid Glass cannot be captured outside a real keyboard session, so a flat stand-in colour
/// (the glass's typical resolved tone) sits under the 日光 / 夜灯 tint.
enum SnapshotRenderer {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-renderKeyboardSnapshots") }

    static let width: CGFloat = 402   // the device the Gboard measurements came from

    private static func candidates(_ texts: [String], correctedFirst: Bool = false) -> [Candidate] {
        texts.enumerated().map { i, t in
            Candidate(text: t, tapCount: i < 4 ? 4 : 2, syllables: [1], corrected: correctedFirst && i == 0, score: 0)
        }
    }

    @MainActor
    static func run(in scene: UIWindowScene) {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("snapshots")
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
        window.isHidden = false

        struct Shot { let name: String; let page: KeyboardPage; let state: String; let borders: Bool; let panel: String?; var globe = false; var land = false }
        let shots: [Shot] = [
            Shot(name: "letters_idle", page: .letters, state: "idle", borders: true, panel: nil),
            Shot(name: "letters_composing", page: .letters, state: "composing", borders: true, panel: nil),
            Shot(name: "letters_predict", page: .letters, state: "predict", borders: true, panel: nil),
            Shot(name: "letters_undo", page: .letters, state: "undo", borders: true, panel: nil),
            Shot(name: "plain_composing", page: .letters, state: "composing", borders: true, panel: nil),
            Shot(name: "plain_numbers", page: .numbers, state: "idle", borders: true, panel: nil),
            Shot(name: "letters_guide", page: .letters, state: "idle", borders: true, panel: nil),
            Shot(name: "letters_shift", page: .letters, state: "shift", borders: true, panel: nil),
            Shot(name: "numbers", page: .numbers, state: "idle", borders: true, panel: nil),
            Shot(name: "symbols", page: .symbols, state: "idle", borders: true, panel: nil),
            Shot(name: "numpad", page: .numpad, state: "idle", borders: true, panel: nil),
            Shot(name: "t9_idle", page: .letters, state: "idle", borders: true, panel: nil),
            Shot(name: "t9_composing", page: .letters, state: "composing", borders: true, panel: nil),
            Shot(name: "numpad_press_5", page: .numpad, state: "idle", borders: true, panel: "press:5"),
            Shot(name: "grid", page: .letters, state: "composing", borders: true, panel: "grid"),
            Shot(name: "settings", page: .letters, state: "idle", borders: true, panel: "settings"),
            Shot(name: "settings_full", page: .letters, state: "idle", borders: true, panel: "settings_full"),
            // rounds/R4.md: without 允许完全访问 — the two switches greyed, the line that says why
            Shot(name: "settings_noaccess", page: .letters, state: "idle", borders: true, panel: "settings_noaccess"),
            Shot(name: "letters_english", page: .letters, state: "english", borders: true, panel: nil),
            Shot(name: "en_autocorrect", page: .letters, state: "en_typing", borders: true, panel: nil),
            Shot(name: "longpress_comma", page: .letters, state: "idle", borders: true, panel: "longpress"),
            Shot(name: "press_g", page: .letters, state: "composing", borders: true, panel: "press:g"),
            Shot(name: "press_q", page: .letters, state: "composing", borders: true, panel: "press:q"),
            Shot(name: "cursor_drag", page: .letters, state: "idle", borders: true, panel: "cursor"),
            Shot(name: "forced_light", page: .letters, state: "composing", borders: true, panel: "forced"),
            Shot(name: "forget_word", page: .letters, state: "composing", borders: true, panel: "forget"),
            // rounds/R3.md: the strip scrolled to the middle of a long list (both edges fade); a swipe left off delete
            // armed (the candidates faded, delete held); after the clear, the ↩ chip with the keys it took
            Shot(name: "strip_scrolled", page: .letters, state: "composing", borders: true, panel: "scrolled"),
            Shot(name: "clear_armed", page: .letters, state: "composing", borders: true, panel: "clear_armed"),
            Shot(name: "cleared_undo", page: .letters, state: "cleared", borders: true, panel: nil),
            Shot(name: "press_comma_numbers", page: .numbers, state: "idle", borders: true, panel: "press:，"),
            Shot(name: "emoji", page: .letters, state: "idle", borders: true, panel: "emoji"),
            Shot(name: "mosto_yawn", page: .letters, state: "idle", borders: true, panel: "yawn"),
            Shot(name: "mosto_kaomoji", page: .letters, state: "idle", borders: true, panel: "kaomoji"),
            // Home-button devices: the globe joins the bottom row, 表情 stays
            Shot(name: "globe_letters", page: .letters, state: "composing", borders: true, panel: nil, globe: true),
            Shot(name: "globe_t9", page: .letters, state: "idle", borders: true, panel: nil, globe: true),
            Shot(name: "globe_numbers", page: .numbers, state: "idle", borders: true, panel: nil, globe: true),
            Shot(name: "globe_numpad", page: .numpad, state: "idle", borders: true, panel: nil, globe: true),
            // landscape (iPhone 17 Pro: 874 wide, keys inside the 62 pt safe areas)
            Shot(name: "land_letters", page: .letters, state: "composing", borders: true, panel: nil, land: true),
            Shot(name: "land_t9", page: .letters, state: "idle", borders: true, panel: nil, land: true),
            Shot(name: "land_numbers", page: .numbers, state: "idle", borders: true, panel: nil, land: true),
            Shot(name: "land_emoji", page: .letters, state: "idle", borders: true, panel: "emoji", land: true),
        ]
        // 表情 opens on 常用 when something was used: a few, as after some use
        for e in ["👍", "😭", "❤️", "🙏", "😂"] { EmojiPanelView.remember(e) }
        for night in [false, true] {
            for shot in shots {
                Theme.plain = shot.name.hasPrefix("plain")   // 简洁 (无主题)
                defer { Theme.plain = false }
                // settings_full: the whole settings list at once (a tall frame), to review every section
                let barH = shot.land ? Metrics.toolbarHeightLandscape : Metrics.toolbarHeight
                let pitch = shot.land ? Metrics.rowPitchLandscape : Metrics.rowPitch
                let fullWidth: CGFloat = shot.land ? 874 : width
                let inset: CGFloat = shot.land ? 62 : 0
                let width = fullWidth - 2 * inset
                let height = shot.panel == "settings_full" ? 820 : barH + 4 * pitch
                let root = UIView(frame: CGRect(x: 0, y: 0, width: fullWidth, height: height))
                // "forced": the light chosen in settings differs from the system glass underneath (日光 in a dark app,
                // 夜灯 in a light one): the keys take the chosen light, everything on the glass follows the glass
                let forced = shot.panel == "forced"
                let darkGlass = night != forced
                root.overrideUserInterfaceStyle = darkGlass ? .dark : .light
                root.backgroundColor = darkGlass ? UIColor(white: 0.13, alpha: 1) : UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)
                window.addSubview(root)
                let tint = AmbientLightView(frame: root.bounds)
                tint.night = night
                tint.forcedNight = forced && night
                tint.forcedDay = forced && !night
                tint.isHidden = Theme.plain          // 简洁 has no lamp glow, as in the keyboard
                root.addSubview(tint)

                // Mosto is set up before the strip is on screen: he is simply there, as when the keyboard opens
                // (on screen he would wait 0.6 s and fade in — after the picture is taken)
                let bar = CandidateBarView(frame: CGRect(x: inset, y: 0, width: width, height: barH))
                bar.mosto.setNight(night)
                bar.showsMosto = !Theme.plain
                root.addSubview(bar)
                let kb = KeyboardView(spatial: SpatialModel.standard(width: Double(width)))
                kb.frame = CGRect(x: inset, y: barH, width: width, height: 4 * pitch)
                kb.overrideUserInterfaceStyle = night ? .dark : .light
                root.addSubview(kb)
                kb.configure(LayoutContext(page: shot.page, chinese: !shot.name.hasPrefix("en_"), showGlobe: shot.globe, returnLabel: nil,
                                           returnIsAccent: false, shifted: shot.state == "shift", capsLock: false,
                                           keyBorders: shot.borders, pinyinGrid: shot.name.hasPrefix("t9") || shot.name.hasSuffix("_t9"),
                                           xiaoheGuide: shot.name.hasSuffix("guide")))
                // 九宫格 keys have no neighbours to slip onto: its first candidate carries no correction
                let t9Shot = shot.name.hasPrefix("t9") || shot.name.hasSuffix("_t9")
                var composing = candidates(["你好", "尼好", "泥好", "拟好", "你", "尼", "泥", "拟", "逆", "腻", "nihc"], correctedFirst: !t9Shot)
                if !t9Shot { composing[0].fixes = [Fix(typed: "hap", meant: "hao")] }
                switch shot.state {
                case "composing" where shot.panel == "scrolled":
                    bar.update(preedit: "ni hao", candidates: composing + candidates(["倪", "霓", "匿", "妮", "昵", "溺", "睨", "鲵", "旎", "怩"]))
                case "composing": bar.update(preedit: "ni hao", candidates: composing)
                case "cleared":
                    bar.setUndo("nihap", spoken: "撤回清空，恢复为 nihap")
                    bar.update(preedit: "", candidates: [])
                case "en_typing": bar.update(preedit: "", candidates: [
                    { var c = Candidate(text: "the", tapCount: 0, syllables: [], corrected: true, score: 0)
                      c.fixes = [Fix(typed: "teh", meant: "the")]; return c }(),
                    Candidate(text: "teh", tapCount: 0, syllables: [], corrected: false, score: 0),
                    Candidate(text: "tech", tapCount: 0, syllables: [], corrected: false, score: 0)])
                case "english": bar.update(preedit: "ios", candidates: candidates(["iOS", "戳死", "戳所", "戳三", "ios"], correctedFirst: false))
                case "undo":
                    bar.setUndo("jintiantiaqi")
                    bar.update(preedit: "", candidates: ["很好", "不错", "怎么样", "真好"].map {
                        Candidate(text: $0, tapCount: 0, syllables: [], corrected: false, score: 0) }, prediction: true)
                case "predict":
                    bar.update(preedit: "", candidates: ["我", "不", "在", "一起", "可以", "也", "要", "会"].map {
                        Candidate(text: $0, tapCount: 0, syllables: [], corrected: false, score: 0) }, prediction: true)
                default: bar.update(preedit: "", candidates: [])
                }
                if shot.name == "t9_composing" {
                    kb.layoutIfNeeded()
                    if let f = kb.keypadSideColumn() {
                        kb.setSideColumnHidden(true)
                        let picker = SyllablePickerView(frame: f)
                        kb.addSubview(picker)
                        picker.show(["ni", "mi", "o"])
                    }
                }
                if let panel = shot.panel, panel.hasPrefix("press:") {
                    kb.layoutIfNeeded()
                    kb.demoPress(String(panel.dropFirst(6)))
                } else if shot.panel == "forget" {
                    bar.offerForget("尼好") {}
                } else if shot.panel == "scrolled" {
                    bar.scrollStrip(to: width * 0.6)
                } else if shot.panel == "clear_armed" {
                    kb.layoutIfNeeded()
                    kb.demoHold(.delete)
                    bar.setClearPreview(true)
                } else if shot.panel == "cursor" {
                    kb.layoutIfNeeded()
                    kb.demoCursorMode()
                } else if shot.panel == "grid" {
                    let grid = CandidateGridView(frame: kb.frame)
                    root.addSubview(grid)
                    kb.isHidden = true
                    grid.show(composing + candidates(["倪", "霓", "匿", "妮", "昵", "溺", "睨", "鲵", "旎", "怩"]))
                } else if shot.panel == "longpress" {
                    // the row a long press on ， opens (slot 7.5–8.5 of the bottom row), "？" highlighted
                    let unit = width / 10
                    let key = CGRect(x: 7.5 * unit + Metrics.gapX / 2, y: 3 * Metrics.rowPitch + Metrics.gapY / 2,
                                     width: unit - Metrics.gapX, height: Metrics.rowPitch - Metrics.gapY)
                    let popup = AltPopup(options: ["。", "？", "！", "、", "…", "："], cell: max(key.width, 34), height: key.height * 1.1, reversed: true)
                    var x = key.midX + popup.cell / 2 + 4 - popup.frame.width
                    x = min(max(2, x), width - popup.frame.width - 2)
                    popup.frame.origin = CGPoint(x: x, y: key.minY - popup.frame.height - 4)
                    popup.selected = 1
                    kb.addSubview(popup)
                } else if shot.panel == "yawn" {
                    bar.showsMosto = !Theme.plain          // (by day too, to review the sprite on both glasses)
                    bar.mosto.demoYawn()
                } else if shot.panel == "emoji" || shot.panel == "kaomoji" {
                    let panel = EmojiPanelView(frame: root.bounds)
                    root.addSubview(panel)
                    kb.isHidden = true; bar.isHidden = true   // as in the keyboard: the emoji page covers both
                    panel.setChinese(true)
                    panel.layoutIfNeeded()
                    panel.load(kaomoji: shot.panel == "kaomoji")
                } else if shot.panel == "settings" || shot.panel == "settings_full" || shot.panel == "settings_noaccess" {
                    let panel = SettingsPanelView(frame: root.bounds)
                    root.addSubview(panel)
                    kb.isHidden = true; bar.isHidden = true   // as in the keyboard: the panel replaces them
                    panel.setNight(night)
                    panel.setLearned("词库 1866491 条 · 已学习 0 个词")
                    if shot.panel == "settings_noaccess" {
                        // as KeyboardViewController.applySettings shows it without 允许完全访问
                        panel.setFeedbackAvailable(false)
                        panel.setNote("按键震动与按键音需在 设置 › 通用 › 键盘 › 键盘 › Mosto键盘 中开启“允许完全访问”。"
                            + "词库与学习记录只存在本机，键盘全程离线工作。")
                        panel.demoScrollToFeedback()
                    } else {
                        panel.setNote("词库与学习记录只存在本机，键盘全程离线工作。")
                    }
                }
                root.setNeedsLayout(); root.layoutIfNeeded()
                kb.layoutIfNeeded(); bar.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat(); format.scale = 3
                let img = UIGraphicsImageRenderer(bounds: root.bounds, format: format).image { _ in
                    root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
                }
                let file = dir.appendingPathComponent("\(night ? "night" : "day")_\(shot.name).png")
                try? img.pngData()?.write(to: file)
                root.removeFromSuperview()
            }
        }
        // the companion app's home screen (the same SwiftUI view, rendered off-screen)
        for night in [false, true] {
            // the home page in three parts (one tall bitmap of all of it comes out black)
            func page<V: View>(_ v: V) -> some View {
                v.padding(.horizontal, 16)
                    .frame(width: width)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.systemGroupedBackground))
                    .tint(mostoTint)
                    .environment(\.colorScheme, night ? .dark : .light)
            }
            let lesson = PlaygroundModel()
            lesson.step = 2
            lesson.before = "你好今天很热"
            lesson.marked = "jintiantiaqi"
            let parts: [(String, AnyView)] = [
                ("0", AnyView(page(VStack(spacing: 14) {
                    LessonCard(model: lesson, index: 2)
                    TextArea(model: lesson)
                }))),
                ("1", AnyView(page(VStack(spacing: 30) {
                    MostoHero()
                    SetupCard()
                }))),
                ("2", AnyView(page(FeatureShowcase()))),
                ("3", AnyView(page(VStack(spacing: 30) {
                    MoreList(snapshot: true)
                    HomeFooter()
                }))),
            ]
            for (k, v) in parts {
                let r = ImageRenderer(content: v)
                r.scale = 2
                if let img = r.uiImage, let data = img.pngData() {
                    try? data.write(to: dir.appendingPathComponent("\(night ? "night" : "day")_app_home\(k).png"))
                } else { print("SNAPSHOT app_home\(k): no image") }
            }
            // the 小鹤双拼 page (explanation, learning cost, key chart)
            let guide = XiaoheGuideContent()
                .padding(.horizontal, 16)
                .frame(width: width)
                .padding(.vertical, 12)
                .background(Color(UIColor.systemGroupedBackground))
                .tint(mostoTint)
                .environment(\.colorScheme, night ? .dark : .light)
            let g = ImageRenderer(content: guide)
            var gshot: UIImage?
            for scale in [3.0, 2.0, 1.5, 1.0] where gshot == nil { g.scale = scale; gshot = g.uiImage }
            if let img = gshot {
                try? img.pngData()?.write(to: dir.appendingPathComponent("\(night ? "night" : "day")_app_xiaohe.png"))
            }
        }
        // FOOTPRINT: the engine's speed and memory as the user's phone has them (rounds/R5.md 3a). CI builds this step
        // with the Release compiler settings (-O, whole module, exclusivity unchecked), so the decodes run the engine
        // TestFlight ships; the line says "UNOPTIMIZED" if the build was not optimised.
        measureFootprint()
        // the keyboard's own behaviour: the real controller against a simulated text field (App/KeyboardTests.swift)
        // Run from a plain run-loop callout, not from inside this task: a task runs as a main-queue block, and while
        // one is running GCD delivers no other main-queue block — the keyboard's decode results would never arrive.
        let file = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard-tests.txt")
        let path = dir.path
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
            MainActor.assumeIsolated { KeyboardTests.run(in: window, to: file) }
            print("SNAPSHOTS \(path)")
            exit(0)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    // MARK: - FOOTPRINT (rounds/R5.md 3a)

    /// The gate's random-number generator (EngineCLI `RNG`): fixed seeds, so two runs decode the same inputs.
    private struct FootprintRNG {
        var s: UInt64
        mutating func bits() -> UInt64 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return s >> 11
        }
        mutating func next() -> Double { Double(bits()) / Double(UInt64(1) << 53) }
        mutating func gauss() -> Double {
            let u = max(next(), 1e-12), v = next()
            return sqrt(-2 * log(u)) * cos(2 * .pi * v)
        }
    }

    private static func percentiles(_ values: [Double]) -> (p50: Double, p99: Double, max: Double) {
        guard !values.isEmpty else { return (0, 0, 0) }
        let v = values.sorted()
        func at(_ q: Double) -> Double { v[min(v.count - 1, Int(Double(v.count) * q))] }
        return (at(0.5), at(0.99), v[v.count - 1])
    }

    /// A read-only shared mapping of one of the engine's files, to ask the kernel which of its pages are in memory
    /// (`mincore`) and, before the engine loads, to drop them (`msync` MS_INVALIDATE), so what is resident afterwards
    /// is what the engine paged in rather than what the build left in the file cache.
    private final class MappedFile {
        let size: Int
        private let base: UnsafeMutableRawPointer
        init?(_ path: String) {
            let fd = open(path, O_RDONLY)
            guard fd >= 0 else { return nil }
            defer { close(fd) }
            var st = stat()
            guard fstat(fd, &st) == 0, st.st_size > 0 else { return nil }
            let p = mmap(nil, Int(st.st_size), PROT_READ, MAP_SHARED, fd, 0)
            guard let p, p != MAP_FAILED else { return nil }
            size = Int(st.st_size)
            base = p
        }
        deinit { munmap(base, size) }
        /// Bytes of the file resident in memory.
        func residentBytes() -> Int {
            let page = Int(getpagesize())
            var vec = [CChar](repeating: 0, count: (size + page - 1) / page)
            guard mincore(base, size, &vec) == 0 else { return -1 }
            return vec.reduce(0) { $0 + ($1 & 1 != 0 ? 1 : 0) } * page
        }
        func evict() { _ = msync(base, size, MS_INVALIDATE) }
    }

    /// The gate's first 100 sentences (EngineCLI/sentences.tsv, then sentences2.tsv) as 小鹤 keys. The workflow copies
    /// them into Documents and also passes the repository path after `-footprintSentences`.
    private static func typingSentences() -> [[Character]] {
        var paths: [String] = []
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-footprintSentences"), i + 1 < args.count { paths.append(args[i + 1]) }
        paths.append(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("footprint-sentences.tsv").path)
        for path in paths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            var out: [[Character]] = []
            for line in text.split(separator: "\n") where out.count < 100 {
                let parts = line.split(separator: "\t")
                guard parts.count == 2 else { continue }
                let codes = parts[1].split(separator: " ").map { XiaoheScheme.code(for: String($0)) }
                guard !codes.isEmpty, !codes.contains(where: { $0 == nil }) else { continue }
                out.append(Array(codes.compactMap { $0 }.joined()))
            }
            if !out.isEmpty { return out }
        }
        return []
    }

    /// One line, `FOOTPRINT …`, that the workflow keeps in the CI log:
    /// - load + first decode: the first key after the keyboard opens (engine just loaded, its files paged in on demand);
    /// - random: 2,000 decodes of 2–25 random letters, exact keys, seeds 1–5 (the same inputs as the R5 replica);
    /// - typing: the gate's first 100 sentences typed with the gate's touch noise (σ 0.22 key), one decode per key as
    ///   the keyboard does while someone types (every prefix of the sentence);
    /// - memory: phys_footprint (what iOS counts against the keyboard's limit) before, with the engine loaded, after;
    /// - mapped resident: the engine's files' pages in memory after the decodes (clean file pages: not counted above).
    private static func measureFootprint() {
        guard let ext = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MossOttoKeyboardExt.appex"),
              let kb = Bundle(url: ext) ?? Bundle.main.builtInPlugInsURL.flatMap({ u in
                  (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil))?.first.flatMap(Bundle.init(url:)) })
        else {
            print("FOOTPRINT keyboard extension not found in \(Bundle.main.builtInPlugInsURL?.path ?? "-")")
            return
        }
        let lexiconPath = kb.path(forResource: "lexicon", ofType: "bin")
        let sentencePath = kb.path(forResource: "sentence", ofType: "gram")
        let grammarPath = kb.path(forResource: "grammar", ofType: "gram")
        let mapped: [(name: String, file: MappedFile?)] = [("lexicon", lexiconPath.flatMap(MappedFile.init)),
                                                           ("sentence", sentencePath.flatMap(MappedFile.init)),
                                                           ("grammar", grammarPath.flatMap(MappedFile.init))]
        for m in mapped { m.file?.evict() }
        let residentBefore = mapped.reduce(0) { $0 + max(0, $1.file?.residentBytes() ?? 0) }

        let before = memoryFootprintMB()
        let host = EngineHost()
        host.load(lexiconPath: lexiconPath, englishPath: kb.path(forResource: "english", ofType: "bin"),
                  grammarPath: grammarPath, sentencePath: sentencePath, userDictURL: nil)
        let c0 = CACurrentMediaTime()
        _ = host.decodeNow([Tap.exact("n")])
        let cold = (CACurrentMediaTime() - c0) * 1000
        let loaded = memoryFootprintMB()
        // the engine's own warm-up (queued by `load`) finishes before the timed decodes start
        for s in ["wo", "nihao", "women", "shi", "de", "jintian"] { _ = host.decodeNow(s.map { Tap.exact($0) }) }

        func timed(_ taps: [Tap]) -> Double {
            let t0 = CACurrentMediaTime()
            _ = host.decodeNow(taps)
            return (CACurrentMediaTime() - t0) * 1000
        }
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var random: [Double] = []
        random.reserveCapacity(2000)
        for seed in 1...5 {
            var rng = FootprintRNG(s: UInt64(seed))
            for i in 0..<400 {
                let n = 2 + i % 24
                random.append(timed((0..<n).map { _ in Tap.exact(letters[Int(rng.bits() % 26)]) }))
            }
        }
        let model = SpatialModel.standard()
        let sentences = typingSentences()
        var typing: [Double] = []
        var rng = FootprintRNG(s: 1)
        for keys in sentences {
            let taps: [Tap] = keys.map { c in
                guard let (cx, cy) = model.center(of: c) else { return Tap.exact(c) }
                return model.tap(x: cx + rng.gauss() * 0.22 * model.keyWidth, y: cy + rng.gauss() * 0.198 * model.keyHeight)
            }
            for k in 1...taps.count { typing.append(timed(Array(taps.prefix(k)))) }
        }
        let after = memoryFootprintMB()
        let resident = mapped.map { (name: $0.name, bytes: $0.file?.residentBytes() ?? -1) }
        let residentTotal = resident.reduce(0) { $0 + max(0, $1.bytes) }

        let r = percentiles(random), t = percentiles(typing)
        let mb = { (b: Int) -> String in b < 0 ? "n/a" : String(format: "%.1f", Double(b) / 1_048_576) }
        let build = _isDebugAssertConfiguration() ? "UNOPTIMIZED (-Onone)" : "optimized"
        print("FOOTPRINT \(build)"
              + String(format: " | load + first decode %.1f ms", cold)
              + String(format: " | random p50/p99/max %.2f/%.2f/%.2f ms (n=%d, seeds 1-5)", r.p50, r.p99, r.max, random.count)
              + String(format: " | typing p50/p99/max %.2f/%.2f/%.2f ms (n=%d, %d gate sentences, sigma 0.22)", t.p50, t.p99, t.max, typing.count, sentences.count)
              + String(format: " | memory before %.1f MB, engine loaded +%.1f MB, after decodes +%.1f MB", before, loaded - before, after - before)
              + " | mapped resident \(mb(residentTotal)) MB ("
              + resident.map { "\($0.name) \(mb($0.bytes))" }.joined(separator: ", ")
              + "; \(mb(residentBefore)) MB before load)")
    }
}
