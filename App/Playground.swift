import SwiftUI
import UIKit

/// The keyboard extension's bundle: its lexicon and language model are what the studio bench decodes with.
private let keyboardExtensionBundle: Bundle? = {
    guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
    if let b = Bundle(url: plugins.appendingPathComponent("MossOttoKeyboardExt.appex")) { return b }
    return (try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil))?
        .lazy.compactMap(Bundle.init(url:)).first
}()

/// Interactive showcase scenario shown in the Studio's 手感体验 bar (and verified by `KeyboardTests`).
struct Lesson {
    let title: String
    let line: String
    let keys: String
    var slip: Int? = nil
    var missing: Character? = nil
    let check: (String, KeyboardViewController.TestState) -> Bool
    var then: ((KeyboardViewController.TestState, String?) -> Bool)? = nil
}

let lessons: [Lesson] = [
    Lesson(title: "打出“你好”", line: "轻敲下面字母，按空格上屏。", keys: "nihao␣",
           check: { t, _ in t.contains("你好") }),
    Lesson(title: "按错一个键", line: "故意把 e 按成旁边的 w：留意首选微光提示，空格依然读对。", keys: "jintianhenrw␣", slip: 11,
           check: { t, _ in t.contains("今天很热") }),
    Lesson(title: "长句漏按一个键", line: "tian 少按一个 n，整句自动补全并连读。", keys: "jintiantiaqihenhao␣", slip: 10, missing: "n",
           check: { t, _ in t.contains("今天天气很好") }),
    Lesson(title: "撤回纠错", line: "点候选栏左侧 ↩，刚才输入的原始字母原样回来。", keys: "↩",
           check: { _, s in s.composing && s.keys.contains("tiaqi") }),
    Lesson(title: "清空正在打的拼音", line: "从删除键向左轻划清空拼音，再点 ↩ 恢复。", keys: "⌫↩",
           check: { _, s in !s.composing && s.restorable != nil },
           then: { s, keys in s.composing && keys != nil && s.keys == keys }),
    Lesson(title: "中英混输", line: "中英文夹杂直接打，无需手动切换语言。", keys: "woyongiphonedazi␣",
           check: { t, _ in t.contains("iPhone打字") }),
    Lesson(title: "只打声母", line: "常用词只敲声母一样准。", keys: "bzd␣",
           check: { t, _ in t.contains("不知道") }),
]

/// Atlas card / showcase jump map -> matching interactive demo title.
let demoLessons: [String: String] = [
    "按错了什么，改成了什么": "按错一个键",
    "长句多按、漏按一个键": "长句漏按一个键",
    "一键撤回": "长句漏按一个键",
    "中英混输": "中英混输",
    "记住你的词": "只打声母",
]

enum BenchMode: String, CaseIterable, Identifiable {
    case free = "自由试打"
    case demos = "手感体验"
    case speed = "节奏测速"

    var id: String { rawValue }
}

/// Unified Studio bench state: single text slip, single embedded keyboard, interactive demos, and 3-sentence speed test.
@MainActor
final class PlaygroundModel: ObservableObject {
    @Published var before = ""
    @Published var marked = ""
    @Published var step = lessons.count
    @Published var justPassed = false
    @Published var firstDone = false
    @Published var benchMode: BenchMode = .free
    @Published var passedTitles: Set<String> = []
    @Published var ready = false

    // Unified 3-sentence speed test state (zero duplicate PlaygroundModel or keyboard instances).
    static let speedTargets = [
        "今天天气真不错",
        "按偏了也能打对",
        "下周一准时开会",
    ]
    @Published var speedIndex = 0
    @Published var speedStart: Date? = nil
    @Published var speedFinishedSeconds: Double? = nil
    @Published var speedTotalChars = 0
    @AppStorage("mostoBestCPM") var bestCPM = 0

    private var firstKeys: String?
    private var passCount = 0
    let host = ObservedTextHost()
    var keyboard: KeyboardViewController?

    init() {
        let s = KeyboardSettings.shared
        layout = s.pinyinGrid ? 2 : (s.scheme == 0 ? 1 : 0)
        guide = s.xiaoheGuide
        numberPad = s.numberPad
        style = s.style
        appearance = s.appearance
        autocorrect = s.autocorrect
        english = s.english
        feedback = s.feedback
        keySound = s.keySound
        host.onChange = { [weak self] in self?.refresh() }
    }

    var lampMode: StudioLampMode {
        StudioLampMode.from(appearance: appearance, style: style)
    }

    func applyLampMode(_ mode: StudioLampMode) {
        switch mode {
        case .day:
            if style != 0 { style = 0 }
            if appearance != 1 { appearance = 1 }
        case .night:
            if style != 0 { style = 0 }
            if appearance != 2 { appearance = 2 }
        case .plain:
            if style != 1 { style = 1 }
            if appearance != 0 { appearance = 0 }
        }
    }

    var currentSpeedTarget: String {
        Self.speedTargets[min(speedIndex, Self.speedTargets.count - 1)]
    }

    var matchedSpeedPrefixCount: Int {
        let typed = Array(before)
        let target = Array(currentSpeedTarget)
        var n = 0
        while n < typed.count && n < target.count && typed[n] == target[n] { n += 1 }
        return n
    }

    var currentCPM: Int {
        guard let elapsed = speedFinishedSeconds ?? speedStart.map({ Date().timeIntervalSince($0) }),
              elapsed > 0.4 else { return 0 }
        let chars = speedFinishedSeconds != nil ? speedTotalChars : (speedTotalChars + matchedSpeedPrefixCount)
        return Int((Double(chars) / elapsed * 60.0).rounded())
    }

    func resetSpeedTest() {
        speedIndex = 0
        speedStart = nil
        speedFinishedSeconds = nil
        speedTotalChars = 0
        clear()
        keyboardVisible = true
    }

    func refresh() {
        let all = host.string
        if let m = host.markedString, let r = all.range(of: m, options: .backwards) {
            before = String(all[..<r.lowerBound]); marked = m
        } else {
            before = all; marked = ""
        }
        evaluateSpeedProgress()
        guard step < lessons.count, !justPassed, let kb = keyboard else { return }
        let lesson = lessons[step], state = kb.testState
        if let then = lesson.then {
            if !firstDone {
                if lesson.check(all, state) { firstDone = true; firstKeys = state.restorable }
                return
            }
            if !then(state, firstKeys) {
                if state.restorable == nil && !lesson.check(all, state) && state.keys != firstKeys {
                    firstDone = false; firstKeys = nil
                }
                return
            }
        } else if !lesson.check(all, state) {
            return
        }
        passedTitles.insert(lesson.title)
        justPassed = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let passed = step
        passCount += 1
        let pass = passCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, self.justPassed, self.passCount == pass else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if self.step == passed { self.step = min(passed + 1, lessons.count) }
                self.justPassed = false
                self.firstDone = false
                self.firstKeys = nil
            }
        }
    }

    private func evaluateSpeedProgress() {
        guard benchMode == .speed, speedFinishedSeconds == nil else { return }
        if speedStart == nil && (!before.isEmpty || !marked.isEmpty) {
            speedStart = Date()
        }
        let target = currentSpeedTarget
        if before.contains(target) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            speedTotalChars += target.count
            if speedIndex + 1 < Self.speedTargets.count {
                speedIndex += 1
                clear()
            } else {
                let sec = max(0.5, Date().timeIntervalSince(speedStart ?? Date()))
                speedFinishedSeconds = sec
                let finalCPM = Int((Double(speedTotalChars) / sec * 60.0).rounded())
                if finalCPM > bestCPM { bestCPM = finalCPM }
            }
        }
    }

    /// 0 全拼, 1 小鹤双拼, 2 九宫格
    @Published var layout = 0 { didSet { applyLayout() } }
    @Published var style = 0 { didSet { applyLayout() } }
    @Published var appearance = 0 { didSet { applyLayout() } }
    @Published var autocorrect = true { didSet { applyLayout() } }
    @Published var english = true { didSet { applyLayout() } }
    @Published var feedback = true { didSet { applyLayout() } }
    @Published var keySound = true { didSet { applyLayout() } }
    @Published var numberPad = false { didSet { applyLayout() } }
    @Published var keyboardVisible = true
    @Published var guide = false { didSet { applyLayout() } }

    func applyLayout() {
        let s = KeyboardSettings.shared
        let prevGrid = s.pinyinGrid
        s.scheme = layout == 1 ? 0 : 1
        s.pinyinGrid = layout == 2
        if s.pinyinGrid == prevGrid { s.numberPad = numberPad }
        s.xiaoheGuide = guide
        s.style = style
        s.appearance = appearance
        s.autocorrect = autocorrect
        s.english = english
        s.feedback = feedback
        s.keySound = keySound
        keyboard?.applySettings()
    }

    /// Refreshes settings from `KeyboardSettings.shared` after an external toggle (such as VolumeCheckSheet).
    func syncKeyboardSettings() {
        let s = KeyboardSettings.shared
        if keySound != s.keySound { keySound = s.keySound }
        if feedback != s.feedback { feedback = s.feedback }
        keyboard?.applySettings()
    }

    func clear() {
        host.clear()
        refresh()
    }

    /// Selects a specific interactive showcase demo on the unified typing bench.
    func jump(to lesson: Int) {
        guard lessons.indices.contains(lesson) else { return }
        keyboard?.discardComposition()
        host.clear()
        keyboard?.textDidChange(nil)
        if layout != 0 { layout = 0 }
        benchMode = .demos
        justPassed = false
        firstDone = false
        firstKeys = nil
        passCount += 1
        step = lesson
        keyboardVisible = true
        refresh()
    }
}

/// The app's text area host for the studio bench.
final class ObservedTextHost: FakeTextHost {
    var onChange: (() -> Void)?
    override func insertText(_ s: String) { super.insertText(s); changed() }
    override func deleteBackward() { super.deleteBackward(); changed() }
    override func setMarkedText(_ s: String, selectedRange: NSRange) { super.setMarkedText(s, selectedRange: selectedRange); changed() }
    override func unmarkText() { super.unmarkText(); changed() }
    override func adjustTextPosition(byCharacterOffset offset: Int) { super.adjustTextPosition(byCharacterOffset: offset); changed() }
    private func changed() { DispatchQueue.main.async { [weak self] in self?.onChange?() } }
}

/// The real R50 `KeyboardViewController`, hosted directly inside SwiftUI.
struct KeyboardHostView: UIViewControllerRepresentable {
    @ObservedObject var model: PlaygroundModel

    func makeUIViewController(context: Context) -> UIViewController {
        let box = UIViewController()
        box.view.backgroundColor = .clear
        if let b = keyboardExtensionBundle { KeyboardViewController.resourceBundle = b }
        KeyboardViewController.keepsLearnedWords = false
        let vc = KeyboardViewController()
        vc.hostOverride = model.host
        box.addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        box.view.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: box.view.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: box.view.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: box.view.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: box.view.bottomAnchor),
        ])
        vc.didMove(toParent: box)
        model.keyboard = vc
        DispatchQueue.main.async { model.ready = true; model.applyLayout() }
        return box
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}

/// Warm ceramic desk-paper text slip replacing old grey sandboxes.
struct StudioTextPaper: View {
    @ObservedObject var model: PlaygroundModel
    var onInsertPhrase: ((String) -> Void)? = nil
    @State private var blink = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("桌面试打纸", systemImage: "text.cursor")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MossOttoStyle.inkSecondary)
                Spacer()
                if !model.before.isEmpty || !model.marked.isEmpty {
                    Button("清空") { model.clear() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MossOttoStyle.inkSecondary)
                }
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { model.keyboardVisible.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                        Text(model.keyboardVisible ? "收起键盘" : "唤出键盘")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MossOttoStyle.violet)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(MossOttoStyle.violet.opacity(0.11)))
                }
                .buttonStyle(.plain)
            }

            (
                Text(model.before)
                    .foregroundColor(MossOttoStyle.inkPrimary)
                + Text(model.marked)
                    .underline()
                    .foregroundColor(MossOttoStyle.inkPrimary)
                + Text(blink ? "|" : " ")
                    .foregroundColor(MossOttoStyle.violet)
            )
            .font(.system(size: 19, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                if !model.keyboardVisible {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { model.keyboardVisible = true }
                }
            }
            .overlay(alignment: .topLeading) {
                if model.before.isEmpty && model.marked.isEmpty {
                    Text(placeholderText)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(MossOttoStyle.inkSecondary.opacity(0.65))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MossOttoStyle.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7)
        )
        .task {
            if SnapshotRenderer.requested { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 530_000_000)
                blink.toggle()
            }
        }
    }

    private var placeholderText: String {
        if !model.ready { return "正在准备桌面键盘…" }
        if model.layout == 1 { return "试试小鹤：nihc 你好 · wanan 晚安 · 上滑逗号直出。" }
        return "直接试打：nihao 你好 · 365+18= 心算 · 上滑逗号直出。"
    }
}

/// Compact calm inspiration / demo prompt card used inside `UnifiedTypingBench` when `benchMode == .demos`.
struct LessonCard: View {
    @ObservedObject var model: PlaygroundModel
    let index: Int

    var body: some View {
        let clamped = min(max(index, 0), lessons.count - 1)
        let l = lessons[clamped]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(l.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MossOttoStyle.inkPrimary)
                Spacer()
                if model.justPassed {
                    HStack(spacing: 4) {
                        Image(uiImage: mostoImage("Mosto"))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text("已触发")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MossOttoStyle.moss)
                    }
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            Text(l.line)
                .font(.caption)
                .foregroundStyle(MossOttoStyle.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            KeyChips(keys: l.keys, slip: l.slip, missing: l.missing, done: model.marked.count)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MossOttoStyle.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MossOttoStyle.hairline, lineWidth: 0.7)
        )
    }
}

/// Monochrome/amber R50 keystroke recipe chips (replaces old loud purple badges).
struct KeyChips: View {
    let keys: String
    let slip: Int?
    let missing: Character?
    var done = 0

    var body: some View {
        WrapLayout(spacing: 4, lineSpacing: 5) {
            ForEach(Array(keys.enumerated()), id: \.offset) { i, c in
                if i == slip, let m = missing {
                    chip(String(m), style: .gap)
                    chip(String(c), style: .plain, typed: i < done)
                } else {
                    let function = c == "␣" || c == "↩" || c == "⌫"
                    chip(
                        c == "␣" ? "空格" : (c == "⌫" ? "⌫ 左划" : String(c)),
                        style: i == slip ? .slip : (function ? .function : .plain),
                        typed: !function && i < done
                    )
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: done)
    }

    enum Style { case plain, slip, gap, function }

    @ViewBuilder
    private func chip(_ t: String, style: Style, typed: Bool = false) -> some View {
        Text(t)
            .font(.system(size: 13.5, weight: style == .slip || typed ? .bold : .medium, design: .rounded))
            .strikethrough(style == .gap, color: MossOttoStyle.inkSecondary)
            .foregroundStyle(
                style == .slip
                    ? Color.white
                    : (style == .gap ? MossOttoStyle.inkSecondary : (typed ? MossOttoStyle.violet : MossOttoStyle.inkPrimary))
            )
            .frame(minWidth: 22, minHeight: 26)
            .padding(.horizontal, t.count > 1 ? 8 : 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        style == .slip
                            ? MossOttoStyle.lampAmber
                            : (style == .function ? MossOttoStyle.surfaceMuted : MossOttoStyle.surface)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        style == .gap ? MossOttoStyle.inkSecondary.opacity(0.6) : MossOttoStyle.hairline,
                        style: style == .gap ? StrokeStyle(lineWidth: 1, dash: [3, 2]) : StrokeStyle(lineWidth: 0.7)
                    )
            )
    }
}
