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

    private static func isPureBlack(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage, cg.width >= 4, cg.height >= 4 else { return true }
        let w = cg.width, h = cg.height
        var rgba = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &rgba,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        for (px, py) in [(w / 4, h / 4), (w / 2, h / 2), ((3 * w) / 4, (3 * h) / 4)] {
            ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            if let pixel = cg.cropping(to: CGRect(x: px, y: py, width: 1, height: 1)) {
                ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                if rgba[0] > 2 || rgba[1] > 2 || rgba[2] > 2 { return false }
            }
        }
        return true
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
            Shot(name: "plain_idle", page: .letters, state: "idle", borders: true, panel: nil),
            Shot(name: "forced_idle", page: .letters, state: "idle", borders: true, panel: "forced"),
            Shot(name: "plain_forced_idle", page: .letters, state: "idle", borders: true, panel: "forced"),
            Shot(name: "letters_composing", page: .letters, state: "composing", borders: true, panel: nil),
            Shot(name: "letters_predict", page: .letters, state: "predict", borders: true, panel: nil),
            Shot(name: "letters_undo", page: .letters, state: "undo", borders: true, panel: nil),
            Shot(name: "plain_composing", page: .letters, state: "composing", borders: true, panel: nil),
            Shot(name: "plain_appex_pill", page: .letters, state: "composing", borders: true, panel: nil),
            Shot(name: "plain_numbers", page: .numbers, state: "idle", borders: true, panel: nil),
            Shot(name: "letters_guide", page: .letters, state: "idle", borders: true, panel: nil),
            Shot(name: "letters_guide_chord", page: .letters, state: "chord", borders: true, panel: nil),
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
            Shot(name: "smart_space", page: .letters, state: "smart_space", borders: true, panel: nil),
            Shot(name: "forced_light", page: .letters, state: "composing", borders: true, panel: "forced"),
            Shot(name: "forget_word", page: .letters, state: "composing", borders: true, panel: "forget"),
            // rounds/R3.md: the strip scrolled to the middle of a long list (both edges fade); a swipe left off delete
            // armed (the candidates faded, delete held); after the clear, the ↩ chip with the keys it took
            Shot(name: "strip_scrolled", page: .letters, state: "composing", borders: true, panel: "scrolled"),
            Shot(name: "clear_armed", page: .letters, state: "composing", borders: true, panel: "clear_armed"),
            Shot(name: "delete_clutch", page: .letters, state: "idle", borders: true, panel: "delete_clutch"),
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
                tint.isHidden = Theme.plain
                root.addSubview(tint)

                // Mosto is set up before the strip is on screen: he is simply there, as when the keyboard opens
                // (on screen he would wait 0.6 s and fade in — after the picture is taken)
                let bar = CandidateBarView(frame: CGRect(x: inset, y: 0, width: width, height: barH))
                bar.mosto.setNight(night)
                bar.showsMosto = !Theme.plain
                let isT9 = shot.name.hasPrefix("t9") || shot.name.hasSuffix("_t9")
                let isEn = shot.name.hasPrefix("en_")
                bar.setIdleControls(enabled: true, night: night, forcedDayOnDarkGlass: forced && !night)
                if shot.name == "plain_appex_pill" || shot.name == "letters_guide_chord" {
                    bar.showsPreedit = true
                    bar.xiaoheRhythm = true
                }
                root.addSubview(bar)
                let kb = KeyboardView(spatial: SpatialModel.standard(width: Double(width)))
                kb.frame = CGRect(x: inset, y: barH, width: width, height: 4 * pitch)
                kb.overrideUserInterfaceStyle = night ? .dark : .light
                kb.softenedForDarkGlass = forced && !night
                kb.softenedForLightGlass = forced && night
                root.addSubview(kb)
                let isGuideShot = shot.name == "letters_guide" || shot.name == "letters_guide_chord"
                let chordInitial: Character? = shot.name == "letters_guide_chord" ? "q" : nil
                kb.configure(LayoutContext(page: shot.page, chinese: !isEn, showGlobe: shot.globe, returnLabel: nil,
                                           returnIsAccent: false, shifted: shot.state == "shift", capsLock: false,
                                           keyBorders: shot.borders, pinyinGrid: isT9,
                                           composing: shot.state == "composing",
                                           xiaoheGuide: isGuideShot,
                                           xiaohePendingInitial: chordInitial,
                                           spaceOverride: shot.state == "smart_space" ? "跳出 》" : nil,
                                           spaceSchemeLabel: isEn ? nil : (isGuideShot ? "小鹤" : "全拼")))
                // 九宫格 keys have no neighbours to slip onto: its first candidate carries no correction
                let t9Shot = isT9
                var composing = candidates(["你好", "尼好", "泥好", "拟好", "你", "尼", "泥", "拟", "逆", "腻", "nihc"], correctedFirst: !t9Shot)
                if !t9Shot { composing[0].fixes = [Fix(typed: "hap", meant: "hao")] }
                switch shot.state {
                case "composing" where shot.panel == "scrolled":
                    bar.update(preedit: "ni hao", candidates: composing + candidates(["倪", "霓", "匿", "妮", "昵", "溺", "睨", "鲵", "旎", "怩"]))
                case "composing": bar.update(preedit: shot.name == "plain_appex_pill" ? "nihcj" : "ni hao", candidates: composing)
                case "chord": bar.update(preedit: "q", candidates: candidates(["去", "起", "其", "前", "请", "钱", "群"], correctedFirst: false))
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
                } else if shot.panel == "delete_clutch" {
                    kb.layoutIfNeeded()
                    kb.demoHold(.delete)
                    bar.setClearProgress(1.0, armed: true, dimContent: false, deletedText: "今天天气真好", deletedCount: 6)
                } else if shot.panel == "cursor" {
                    kb.layoutIfNeeded()
                    kb.demoCursorMode()
                    bar.setCursorTelemetry(active: true, delta: 6, endStop: 0, crossedNewline: false)
                } else if shot.panel == "grid" {
                    let grid = CandidateGridView(frame: kb.frame)
                    root.addSubview(grid)
                    kb.isHidden = true
                    bar.gridExpanded = true
                    grid.show(composing + candidates(["倪", "霓", "匿", "妮", "昵", "溺", "睨", "鲵", "旎", "怩"]))
                } else if shot.panel == "longpress" {
                    // the row a long press on ， opens (slot 7.5–8.5 of the bottom row), "？" highlighted
                    let sideInset: CGFloat = shot.land ? Metrics.sideInsetLandscape : Metrics.sideInset
                    let unit = (width - sideInset * 2) / 10
                    let key = CGRect(x: sideInset + 7.5 * unit + Metrics.gapX / 2, y: 3 * Metrics.rowPitch + Metrics.gapY / 2,
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
                        if shot.panel == "settings_full" {
                            panel.setDiagnostics("本次按键 128 次 · 内存 18 MB · 引擎就绪 14 ms · 震动：开")
                            panel.toggleMoreForTests()
                            panel.layoutIfNeeded()
                            let fitH = min(760, max(440, ceil(panel.preferredFullHeightForTests)))
                            root.frame.size.height = fitH
                            tint.frame = root.bounds
                            panel.frame = root.bounds
                        }
                    }
                }
                root.setNeedsLayout(); root.layoutIfNeeded()
                kb.layoutIfNeeded(); bar.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat(); format.scale = 3
                var drew = false
                var img = UIGraphicsImageRenderer(bounds: root.bounds, format: format).image { _ in
                    drew = root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
                }
                if !drew || isPureBlack(img) {
                    img = UIGraphicsImageRenderer(bounds: root.bounds, format: format).image { ctx in
                        root.layer.render(in: ctx.cgContext)
                    }
                }
                let file = dir.appendingPathComponent("\(night ? "night" : "day")_\(shot.name).png")
                try? img.pngData()?.write(to: file)
                root.removeFromSuperview()
            }
        }
        // the companion app's live OTTOSSOM screens (rendered off-screen for CI verification)
        struct CompanionHomeSnapshotHost: View {
            @ObservedObject var family: FamilyStageModel
            @State private var verifyText = ""
            @FocusState private var typing: Bool
            var body: some View {
                VStack(spacing: 18) {
                    FamilyLampStageView(model: family)
                    CompanionEnableCard(added: true, verifyText: $verifyText, typing: $typing)
                }
            }
        }
        for night in [false, true] {
            func page<V: View>(_ v: V) -> some View {
                v.padding(.horizontal, 16)
                    .frame(width: width)
                    .padding(.vertical, 12)
                    .background(MossOttoStyle.canvas)
                    .tint(mostoTint)
                    .environment(\.colorScheme, night ? .dark : .light)
            }
            let family = FamilyStageModel()
            family.atmosphere = night ? .night : .day
            if night { family.activeMember = .otto }
            let parts: [(String, AnyView)] = [
                ("0", AnyView(page(CompanionHomeSnapshotHost(family: family)))),
                ("1", AnyView(page(CompanionCapabilitiesSection()))),
                ("3", AnyView(page(AboutCompanionContent(added: true)))),
                ("privacy", AnyView(page(PrivacyCommitmentContent()))),
                ("atlas", AnyView(page(GestureAtlasContent()))),
            ]
            for (k, v) in parts {
                let r = ImageRenderer(content: v)
                r.scale = 2
                let filename = k.count == 1 ? "\(night ? "night" : "day")_app_home\(k).png" : "\(night ? "night" : "day")_app_\(k).png"
                if let img = r.uiImage, let data = img.pngData() {
                    try? data.write(to: dir.appendingPathComponent(filename))
                } else { print("SNAPSHOT app_\(k): no image") }
            }
            // EnableScreen visual verification snapshot
            struct EnableSnapshotHost: View {
                @State private var text = ""
                @FocusState private var typing: Bool
                var body: some View { EnableContent(added: true, text: $text, typing: $typing) }
            }
            let enView = page(EnableSnapshotHost())
            let enRenderer = ImageRenderer(content: enView)
            enRenderer.scale = 2
            if let img = enRenderer.uiImage, let data = img.pngData() {
                try? data.write(to: dir.appendingPathComponent("\(night ? "night" : "day")_app_enable.png"))
            }
            // the 小鹤双拼 page (explanation, learning cost, R50 monolith key chart)
            let guide = XiaoheGuideContent()
                .padding(.horizontal, 16)
                .frame(width: width)
                .padding(.vertical, 12)
                .background(MossOttoStyle.canvas)
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
                      grammarPath: kb.path(forResource: "grammar", ofType: "gram"),
                      sentencePath: kb.path(forResource: "sentence", ofType: "gram"), userDictURL: nil)
            // the first key after the keyboard opens (engine just loaded, models paging in), then 400 more
            let c0 = CACurrentMediaTime()
            _ = host.decodeNow([Tap.exact("n")])
            let cold = (CACurrentMediaTime() - c0) * 1000
            let loaded = memoryFootprintMB()
            var times: [Double] = []
            let letters = Array("abcdefghijklmnopqrstuvwxyz")
            var rng = SystemRandomNumberGenerator()
            for i in 0..<400 {
                let n = 2 + i % 24
                let taps = (0..<n).map { _ in Tap.exact(letters[Int(rng.next() % 26)]) }
                let t0 = CACurrentMediaTime()
                _ = host.decodeNow(taps)
                times.append((CACurrentMediaTime() - t0) * 1000)
            }
            times.sort()
            let p99 = times[min(times.count - 1, Int(Double(times.count) * 0.99))]
            print(String(format: "FOOTPRINT load + first decode %.1f ms, warm p99 %.1f ms, max %.1f ms; memory before %.1f MB, engine loaded +%.1f MB, after 400 decodes +%.1f MB",
                         cold, p99, times.last ?? 0, before, loaded - before, memoryFootprintMB() - before))
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
