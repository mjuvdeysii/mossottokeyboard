import UIKit

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
            Shot(name: "letters_gboard_borderless", page: .letters, state: "composing", borders: false, panel: nil),
            Shot(name: "grid", page: .letters, state: "composing", borders: true, panel: "grid"),
            Shot(name: "settings", page: .letters, state: "idle", borders: true, panel: "settings"),
            Shot(name: "longpress_comma", page: .letters, state: "idle", borders: true, panel: "longpress"),
        ]
        for night in [false, true] {
            for shot in shots {
                let root = UIView(frame: CGRect(x: 0, y: 0, width: width, height: Metrics.toolbarHeight + 4 * Metrics.rowPitch))
                root.overrideUserInterfaceStyle = night ? .dark : .light
                root.backgroundColor = night ? UIColor(white: 0.13, alpha: 1) : UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)
                window.addSubview(root)
                let tint = UIView(frame: root.bounds)
                tint.backgroundColor = Theme.glassTint
                root.addSubview(tint)

                let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: width, height: Metrics.toolbarHeight))
                root.addSubview(bar)
                bar.mosto.setNight(night)
                let kb = KeyboardView(spatial: SpatialModel.standard(width: Double(width)))
                kb.frame = CGRect(x: 0, y: Metrics.toolbarHeight, width: width, height: 4 * Metrics.rowPitch)
                root.addSubview(kb)
                kb.configure(LayoutContext(page: shot.page, chinese: true, showGlobe: false, returnLabel: nil,
                                           returnIsAccent: false, shifted: shot.state == "shift", capsLock: false,
                                           keyBorders: shot.borders))
                let composing = candidates(["你好", "尼好", "泥好", "拟好", "你", "尼", "泥", "拟", "逆", "腻", "nihc"], correctedFirst: true)
                switch shot.state {
                case "composing": bar.update(preedit: "ni hao", candidates: composing)
                case "predict":
                    bar.update(preedit: "", candidates: ["吗", "啊", "呀", "坏", "毒", "漂亮"].map {
                        Candidate(text: $0, tapCount: 0, syllables: [], corrected: false, score: 0) }, prediction: true)
                default: bar.update(preedit: "", candidates: [])
                }
                if shot.panel == "grid" {
                    let grid = CandidateGridView(frame: kb.frame)
                    root.addSubview(grid)
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
                } else if shot.panel == "settings" {
                    let panel = SettingsPanelView(frame: root.bounds)
                    root.addSubview(panel)
                    panel.setNote("词库：546858 条；已学习：0 条。")
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
        print("SNAPSHOTS \(dir.path)")
        exit(0)
    }
}
