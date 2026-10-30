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
            Shot(name: "letters_english", page: .letters, state: "english", borders: true, panel: nil),
            Shot(name: "en_autocorrect", page: .letters, state: "en_typing", borders: true, panel: nil),
            Shot(name: "longpress_comma", page: .letters, state: "idle", borders: true, panel: "longpress"),
            Shot(name: "press_g", page: .letters, state: "composing", borders: true, panel: "press:g"),
            Shot(name: "press_q", page: .letters, state: "composing", borders: true, panel: "press:q"),
            Shot(name: "cursor_drag", page: .letters, state: "idle", borders: true, panel: "cursor"),
            Shot(name: "forced_light", page: .letters, state: "composing", borders: true, panel: "forced"),
            Shot(name: "forget_word", page: .letters, state: "composing", borders: true, panel: "forget"),
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
                root.addSubview(tint)

                let bar = CandidateBarView(frame: CGRect(x: inset, y: 0, width: width, height: barH))
                root.addSubview(bar)
                bar.mosto.setNight(night)
                bar.showsMosto = !Theme.plain
                let kb = KeyboardView(spatial: SpatialModel.standard(width: Double(width)))
                kb.frame = CGRect(x: inset, y: barH, width: width, height: 4 * pitch)
                kb.overrideUserInterfaceStyle = night ? .dark : .light
                root.addSubview(kb)
                kb.configure(LayoutContext(page: shot.page, chinese: !shot.name.hasPrefix("en_"), showGlobe: shot.globe, returnLabel: nil,
                                           returnIsAccent: false, shifted: shot.state == "shift", capsLock: false,
                                           keyBorders: shot.borders, pinyinGrid: shot.name.hasPrefix("t9") || shot.name.hasSuffix("_t9"),
                                           xiaoheGuide: shot.name.hasSuffix("guide")))
                var composing = candidates(["你好", "尼好", "泥好", "拟好", "你", "尼", "泥", "拟", "逆", "腻", "nihc"], correctedFirst: true)
                composing[0].fixes = [Fix(typed: "hap", meant: "hao")]
                switch shot.state {
                case "composing": bar.update(preedit: "ni hao", candidates: composing)
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
                } else if shot.panel == "settings" || shot.panel == "settings_full" {
                    let panel = SettingsPanelView(frame: root.bounds)
                    root.addSubview(panel)
                    kb.isHidden = true; bar.isHidden = true   // as in the keyboard: the panel replaces them
                    panel.setNight(night)
                    panel.setLearned("词库 1866491 条 · 已学习 0 个词")
                    panel.setNote("词库与学习记录只存在本机，键盘全程离线工作。")
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
        // The keyboard's memory with the engine loaded and working, measured in this process the same way iOS
        // counts it against a keyboard's limit (the engine's files come from the keyboard extension in the app).
        if let ext = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MossOttoKeyboardExt.appex"),
           let kb = Bundle(url: ext) ?? Bundle.main.builtInPlugInsURL.flatMap({ u in
               (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil))?.first.flatMap(Bundle.init(url:)) }) {
            let before = memoryFootprintMB()
            let host = EngineHost()
            host.load(lexiconPath: kb.path(forResource: "lexicon", ofType: "bin"), englishPath: kb.path(forResource: "english", ofType: "bin"),
                      grammarPath: kb.path(forResource: "grammar", ofType: "gram"), userDictURL: nil)
            var worst = 0.0
            let letters = Array("abcdefghijklmnopqrstuvwxyz")
            var rng = SystemRandomNumberGenerator()
            for i in 0..<400 {
                let n = 2 + i % 24
                let taps = (0..<n).map { _ in Tap.exact(letters[Int(rng.next() % 26)]) }
                let t0 = CACurrentMediaTime()
                _ = host.decodeNow(taps)
                worst = max(worst, (CACurrentMediaTime() - t0) * 1000)
            }
            print(String(format: "FOOTPRINT before %.1f MB, after engine + 400 decodes %.1f MB, slowest decode %.1f ms", before, memoryFootprintMB(), worst))
        } else {
            print("FOOTPRINT keyboard extension not found in \(Bundle.main.builtInPlugInsURL?.path ?? "-")")
        }
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
}
