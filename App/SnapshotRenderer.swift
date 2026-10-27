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

        struct Shot { let name: String; let page: KeyboardPage; let state: String; let borders: Bool; let panel: String? }
        let shots: [Shot] = [
            Shot(name: "letters_idle", page: .letters, state: "idle", borders: true, panel: nil),
            Shot(name: "letters_composing", page: .letters, state: "composing", borders: true, panel: nil),
            Shot(name: "letters_predict", page: .letters, state: "predict", borders: true, panel: nil),
            Shot(name: "letters_shift", page: .letters, state: "shift", borders: true, panel: nil),
            Shot(name: "numbers", page: .numbers, state: "idle", borders: true, panel: nil),
            Shot(name: "symbols", page: .symbols, state: "idle", borders: true, panel: nil),
            Shot(name: "numpad", page: .numpad, state: "idle", borders: true, panel: nil),
            Shot(name: "t9_idle", page: .letters, state: "idle", borders: true, panel: nil),
            Shot(name: "t9_composing", page: .letters, state: "composing", borders: true, panel: nil),
            Shot(name: "numpad_press_5", page: .numpad, state: "idle", borders: true, panel: "press:5"),
            Shot(name: "letters_gboard_borderless", page: .letters, state: "composing", borders: false, panel: nil),
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
        ]
        for night in [false, true] {
            for shot in shots {
                // settings_full: the whole settings list at once (a tall frame), to review every section
                let height = shot.panel == "settings_full" ? 820 : Metrics.toolbarHeight + 4 * Metrics.rowPitch
                let root = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
                root.overrideUserInterfaceStyle = night ? .dark : .light
                // "forced": the light chosen in settings differs from the system glass underneath (日光 in a dark app,
                // 夜灯 in a light one) — the keyboard must still read as its own light, neither glaring nor covered
                let forced = shot.panel == "forced"
                let darkGlass = night != forced
                root.backgroundColor = darkGlass ? UIColor(white: 0.13, alpha: 1) : UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)
                window.addSubview(root)
                let tint = AmbientLightView(frame: root.bounds)
                tint.night = night
                tint.forcedNight = forced && night
                tint.forcedDay = forced && !night
                root.addSubview(tint)

                let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: width, height: Metrics.toolbarHeight))
                root.addSubview(bar)
                bar.mosto.setNight(night)
                bar.showsMosto = night
                let kb = KeyboardView(spatial: SpatialModel.standard(width: Double(width)))
                kb.frame = CGRect(x: 0, y: Metrics.toolbarHeight, width: width, height: 4 * Metrics.rowPitch)
                root.addSubview(kb)
                kb.configure(LayoutContext(page: shot.page, chinese: !shot.name.hasPrefix("en_"), showGlobe: false, returnLabel: nil,
                                           returnIsAccent: false, shifted: shot.state == "shift", capsLock: false,
                                           keyBorders: shot.borders, pinyinGrid: shot.name.hasPrefix("t9")))
                let composing = candidates(["你好", "尼好", "泥好", "拟好", "你", "尼", "泥", "拟", "逆", "腻", "nihc"], correctedFirst: true)
                switch shot.state {
                case "composing": bar.update(preedit: "ni hao", candidates: composing)
                case "en_typing": bar.update(preedit: "", candidates: [
                    Candidate(text: "the", tapCount: 0, syllables: [], corrected: true, score: 0),
                    Candidate(text: "teh", tapCount: 0, syllables: [], corrected: false, score: 0),
                    Candidate(text: "tech", tapCount: 0, syllables: [], corrected: false, score: 0)])
                case "english": bar.update(preedit: "ios", candidates: candidates(["iOS", "戳死", "戳所", "戳三", "ios"], correctedFirst: false))
                case "predict":
                    bar.update(preedit: "", candidates: ["吗", "啊", "呀", "坏", "毒", "漂亮"].map {
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
                } else if shot.panel == "settings" || shot.panel == "settings_full" {
                    let panel = SettingsPanelView(frame: root.bounds)
                    root.addSubview(panel)
                    kb.isHidden = true; bar.isHidden = true   // as in the keyboard: the panel replaces them
                    panel.setNight(night)
                    panel.setLearned("词库 546858 条 · 已学习 0 个词")
                    panel.setNote("键盘不联网，词库与学习记录只存在本机。")
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
            let content = HomeContent(text: .constant(""), snapshot: true)
                .frame(width: width)
                .padding(.vertical, 12)
                .background(Color(UIColor.systemGroupedBackground))
                .tint(mostoTint)
                .environment(\.colorScheme, night ? .dark : .light)
            let r = ImageRenderer(content: content)
            r.scale = 3
            if let img = r.uiImage {
                try? img.pngData()?.write(to: dir.appendingPathComponent("\(night ? "night" : "day")_app_home.png"))
            }
        }
        print("SNAPSHOTS \(dir.path)")
        exit(0)
    }
}
