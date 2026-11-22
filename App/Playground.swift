import SwiftUI
import UIKit

// 上手: the real keyboard, running inside the app (the same controller and engine as the keyboard extension, typing
// into a text area of the app's own), with a short guided run through what it does — each step checks what was
// typed and moves on by itself. Nothing typed here leaves the app, and nothing is learned from it.

/// The keyboard extension's bundle: its lexicon and language model are what the playground decodes with.
private let keyboardExtensionBundle: Bundle? = {
    guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
    if let b = Bundle(url: plugins.appendingPathComponent("MossOttoKeyboardExt.appex")) { return b }
    return (try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil))?
        .lazy.compactMap(Bundle.init(url:)).first
}()

/// One step of the guided run: what to type, which key is the deliberate slip, and how to tell it worked.
struct Lesson {
    let title: String
    let line: String
    let keys: String
    var slip: Int? = nil          // index in `keys` of the key pressed on purpose wrong / the place a key is left out
    var missing: Character? = nil // the letter left out at `slip`
    let check: (String, KeyboardViewController.TestState) -> Bool
    /// A second step after `check` passes: it gets what `check` left the keyboard holding to put back (the keys a
    /// clear took away), and passes the lesson.
    var then: ((KeyboardViewController.TestState, String?) -> Bool)? = nil
}

let lessons: [Lesson] = [
    Lesson(title: "打出“你好”", line: "依次按下面的键，再按空格。", keys: "nihao␣",
           check: { t, _ in t.contains("你好") }),
    Lesson(title: "按错一个键", line: "最后的 e 故意按成旁边的 w：看候选下方的小字 rw→re，再按空格。", keys: "jintianhenrw␣", slip: 11,
           check: { t, _ in t.contains("今天很热") }),
    Lesson(title: "长句漏按一个键", line: "tian 少按一个 n，整句照样读对。", keys: "jintiantiaqihenhao␣", slip: 10, missing: "n",
           check: { t, _ in t.contains("今天天气很好") }),
    Lesson(title: "撤回纠错", line: "点候选栏最左边的 ↩：刚才按的字母原样回来。", keys: "↩",
           check: { _, s in s.composing && s.keys.contains("tiaqi") }),
    Lesson(title: "清空正在打的拼音", line: "从删除键往左一划，正在打的拼音一次清空；点 ↩ 找回。", keys: "⌫↩",
           check: { _, s in !s.composing && s.restorable != nil },
           then: { s, keys in s.composing && keys != nil && s.keys == keys }),
    Lesson(title: "中英混输", line: "英文词夹在句子里照打，不用切换。先按删除清掉刚才的字母，再打：", keys: "woyongiphonedazi␣",
           check: { t, _ in t.contains("iPhone打字") }),
    Lesson(title: "只打声母", line: "常用词只打每个字的声母。", keys: "bzd␣",
           check: { t, _ in t.contains("不知道") }),
]

/// 「了解」页演示卡（标题）→ 「上手」里可以直接去试的那一课（标题）。不在表里的卡（联想）没有「试一试」。
let demoLessons: [String: String] = [
    "按错了什么，改成了什么": "按错一个键",
    "长句多按、漏按一个键": "长句漏按一个键",
    "一键撤回": "长句漏按一个键",   // the undo lesson needs the sentence this one commits: start there
    "中英混输": "中英混输",
    "记住你的词": "只打声母",
]

/// The text area's state, and the guided run's progress.
@MainActor
final class PlaygroundModel: ObservableObject {
    @Published var before = ""      // committed text before the marked keys
    @Published var marked = ""      // the keys being composed (underlined, as the field shows them)
    @Published var step = 0         // index into `lessons`; lessons.count = free typing
    @Published var justPassed = false
    /// A lesson with two steps (清空, then 找回): the first is done; what it left to put back.
    @Published var firstDone = false
    private var firstKeys: String?
    /// Which pass the pending move-on belongs to (a later pass, jump or skip supersedes it).
    private var passCount = 0
    @Published var ready = false
    let host = ObservedTextHost()
    var keyboard: KeyboardViewController?

    init() {
        let s = KeyboardSettings.shared; layout = s.pinyinGrid ? 2 : (s.scheme == 0 ? 1 : 0); guide = s.xiaoheGuide; numberPad = s.numberPad; style = s.style; appearance = s.appearance; autocorrect = s.autocorrect; english = s.english; feedback = s.feedback; keySound = s.keySound; if UserDefaults.standard.bool(forKey: "onboardingDone") || KeyboardStatus.isAdded() { step = lessons.count; UserDefaults.standard.set(true, forKey: "onboardingDone") }; host.onChange = { [weak self] in self?.refresh() }
    }

    func refresh() {
        let all = host.string
        if let m = host.markedString, let r = all.range(of: m, options: .backwards) {
            before = String(all[..<r.lowerBound]); marked = m
        } else {
            before = all; marked = ""
        }
        guard step < lessons.count, !justPassed, let kb = keyboard else { return }
        let lesson = lessons[step], state = kb.testState
        if let then = lesson.then {
            if !firstDone {
                if lesson.check(all, state) { firstDone = true; firstKeys = state.restorable }
                return
            }
            // the keys to put back are gone (another key was pressed): the first step again
            if !then(state, firstKeys) {
                if state.restorable == nil && !lesson.check(all, state) && state.keys != firstKeys { firstDone = false; firstKeys = nil }
                return
            }
        } else if !lesson.check(all, state) {
            return
        }
        do {
            justPassed = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let passed = step
            passCount += 1
            let pass = passCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                // a jump, a skip or another pass in the meantime already moved on: then only the tick goes
                guard let self, self.justPassed, self.passCount == pass else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if self.step == passed { self.step = min(passed + 1, lessons.count); if self.step >= lessons.count { UserDefaults.standard.set(true, forKey: "onboardingDone") } }
                    self.justPassed = false
                    self.firstDone = false
                    self.firstKeys = nil
                }
            }
        }
    }

    /// 0 全拼, 1 小鹤双拼, 2 九宫格 (one three-way control: the three ways someone may want to type Chinese here).
    @Published var layout = 0 { didSet { applyLayout() } }
    @Published var style = 0 { didSet { applyLayout() } }
    @Published var appearance = 0 { didSet { applyLayout() } }
    @Published var autocorrect = true { didSet { applyLayout() } }
    @Published var english = true { didSet { applyLayout() } }
    @Published var feedback = true { didSet { applyLayout() } }
    @Published var keySound = true { didSet { applyLayout() } }
    @Published var numberPad = false { didSet { applyLayout() } }
    @Published var keyboardVisible = true
    /// 小鹤双拼's rhyme hints on the keys (off by default: a clean board for people who know the layout).
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

    func skip() {
        firstDone = false; firstKeys = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step = min(step + 1, lessons.count); if step >= lessons.count { UserDefaults.standard.set(true, forKey: "onboardingDone") } }
    }
        func skipAll() { firstDone = false; firstKeys = nil; UserDefaults.standard.set(true, forKey: "onboardingDone"); withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step = lessons.count } }; func restart() { clear(); firstDone = false; firstKeys = nil; withAnimation { step = 0 } }
    func clear() { host.clear(); refresh() }
    func resetDefaults() {
        layout = 0
        guide = false
        numberPad = false
        style = 0
        appearance = 0
        autocorrect = true
        english = true
        feedback = true
        keySound = true
    }
        
    /// Straight to one lesson (「了解」页的「试一试」): the keys being composed dropped, the field empty, the practice
    /// keyboard back on 全拼 (the lessons are written for it).
    func jump(to lesson: Int) {
        guard lessons.indices.contains(lesson) else { return }
        // dropped, not cleared: no ↩ offers the keys back in the new lesson
        keyboard?.discardComposition()
        host.clear()
        keyboard?.textDidChange(nil)   // the word before is gone with the text: no ↩, no suggestions for it
        if layout != 0 { layout = 0 }
        justPassed = false
        firstDone = false
        firstKeys = nil
        passCount += 1
        step = lesson
        refresh()
    }
}

/// The app's text area for the playground: FakeTextHost (the bench's model of a text field) that says when it changes.
final class ObservedTextHost: FakeTextHost {
    var onChange: (() -> Void)?
    override func insertText(_ s: String) { super.insertText(s); changed() }
    override func deleteBackward() { super.deleteBackward(); changed() }
    override func setMarkedText(_ s: String, selectedRange: NSRange) { super.setMarkedText(s, selectedRange: selectedRange); changed() }
    override func unmarkText() { super.unmarkText(); changed() }
    override func adjustTextPosition(byCharacterOffset offset: Int) { super.adjustTextPosition(byCharacterOffset: offset); changed() }
    private func changed() { DispatchQueue.main.async { [weak self] in self?.onChange?() } }
}

/// The keyboard controller, hosted in a SwiftUI view.
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
        // the guided steps are written for 全拼 on the full keyboard
        DispatchQueue.main.async { model.ready = true; model.applyLayout() }
        return box
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}

// MARK: - Screen

struct PlaygroundScreen: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.step < lessons.count {
                        LessonCard(model: model, index: model.step)
                        TextArea(model: model)
                    } else {
                        TextArea(model: model)
                        PracticeQuickDeck(model: model)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.never)

            if model.keyboardVisible {
                Divider()
                Group {
                    if SnapshotRenderer.requested {
                        Color.clear
                    } else {
                        KeyboardHostView(model: model)
                    }
                }
                .frame(height: 264)
                .background(Color(UIColor {
                    $0.userInterfaceStyle == .dark
                        ? UIColor(white: 0.10, alpha: 1)
                        : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
                }))
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

/// The current step: progress, what to do, the keys to press (the slip in colour), and a tick when it worked.
struct LessonCard: View {
    @ObservedObject var model: PlaygroundModel
    /// The step this card shows, fixed when it is made: while it animates out the model has already moved on
    /// (past the last step, too), so the card never reads the model's current step for its content.
    let index: Int
    var body: some View {
        let l = lessons[min(max(index, 0), lessons.count - 1)]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<lessons.count, id: \.self) { i in
                    Capsule().fill(i < index ? mostoTint : (i == index ? mostoTint.opacity(0.55) : Color(UIColor.tertiarySystemFill)))
                        .frame(width: i == index ? 22 : 8, height: 8)
                }
                Spacer()
                Button("下一步") { model.skip() }.font(.subheadline); Text("·").foregroundStyle(.tertiary); Button("跳过引导") { model.skipAll() }.font(.subheadline.weight(.semibold))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(l.title).font(.title3.weight(.bold))
                Spacer()
                if model.justPassed {
                    // Mosto pops up to cheer the step done
                    HStack(spacing: 4) {
                        Image(uiImage: mostoImage("Mosto")).resizable().scaledToFit().frame(width: 34, height: 34)
                        Text("好！").font(.subheadline.weight(.bold)).foregroundStyle(mostoTint)
                    }
                    .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                    .accessibilityLabel("成功")
                }
            }
            Text(l.line).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // the keys typed so far fill in, so the step shows where one is
            KeyChips(keys: l.keys, slip: l.slip, missing: l.missing, done: model.marked.count)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.justPassed)
        .id(index)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }
}

/// The keys of a step as small caps that wrap: the slip in the correction colour, a left-out key as a dashed gap.
private struct KeyChips: View {
    let keys: String
    let slip: Int?
    let missing: Character?
    var done = 0
    var body: some View {
        WrapLayout(spacing: 3, lineSpacing: 5) {
            ForEach(Array(keys.enumerated()), id: \.offset) { i, c in
                if i == slip, let m = missing {
                    // the key not pressed, then the one at this place
                    chip(String(m), style: .gap)
                    chip(String(c), style: .plain, typed: i < done)
                } else {
                    let function = c == "␣" || c == "↩" || c == "⌫"
                    chip(c == "␣" ? "空格" : (c == "⌫" ? "⌫ 往左划" : String(c)), style: i == slip ? .slip : (function ? .function : .plain),
                         typed: !function && i < done)
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: done)
    }
    enum Style { case plain, slip, gap, function }
    @ViewBuilder private func chip(_ t: String, style: Style, typed: Bool = false) -> some View {
        Text(t)
            .font(.system(size: 15, weight: style == .slip || typed ? .bold : .regular, design: .rounded))
            .strikethrough(style == .gap, color: .secondary)
            .foregroundStyle(style == .slip ? Color.white : (style == .gap ? Color.secondary : (typed ? mostoTint : Color.primary)))
            .scaleEffect(typed ? 1.06 : 1)
            .frame(minWidth: 24, minHeight: 30)
            .padding(.horizontal, t.count > 1 ? 8 : 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(style == .slip ? AnyShapeStyle(mostoTint) : (style == .function ? AnyShapeStyle(Color(uiColor: Theme.functionKey)) : AnyShapeStyle(Color(UIColor.tertiarySystemFill))))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(style == .gap ? Color.secondary : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
    }
}


private struct PracticeQuickDeck: View {
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(uiImage: mostoImage(model.appearance == 2 ? "MostoNight" : "Mosto"))
                        .resizable().scaledToFit().frame(width: 40, height: 40)
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(mostoTint.opacity(0.12)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自由试打模式").font(.subheadline.weight(.bold))
                        Text("随时切换方案体验纠错与长句；更多偏好在底部「设置」页调整。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("7 步闯关") {
                        UISelectionFeedbackGenerator().selectionChanged()
                        model.restart()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Picker("输入方案", selection: $model.layout) {
                    Text("全拼").tag(0)
                    Text("小鹤双拼").tag(1)
                    Text("九宫格").tag(2)
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))

            HStack(spacing: 10) {
                NavigationLink {
                    XiaoheGuideView()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "square.grid.3x3")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(mostoTint)
                        Text("小鹤键位图")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("声韵母口诀与查表")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TouchDriftHeatmapView()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "scope")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(mostoTint)
                        Text("落点热力图")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("拇指偏移学习模型")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
/// Interactive sandbox text area with quick test hints and a one-tap fold/unfold toggle for the bottom keyboard.
struct TextArea: View {
    @ObservedObject var model: PlaygroundModel
    @State private var blink = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.step >= lessons.count ? "实时试打沙盒" : "练习输入区", systemImage: "text.cursor")
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                if !model.before.isEmpty || !model.marked.isEmpty {
                    Button("清空") { model.clear() }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { model.keyboardVisible.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: model.keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                        Text(model.keyboardVisible ? "收起键盘" : "唤出键盘")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(mostoTint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(mostoTint.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            (Text(model.before) + Text(model.marked).underline() + Text(blink ? "|" : " ").foregroundColor(mostoTint))
                .font(.system(size: 20, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !model.keyboardVisible {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { model.keyboardVisible = true }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if model.before.isEmpty && model.marked.isEmpty {
                        Text(model.ready ? (model.layout == 1 ? "试试小鹤：nihc 你好 · wanan 晚安 · riqi 日期 · 长按 ，出《》" : "在这里直接试打：nihao 你好 · wanan 晚安 · riqi 日期 · 长按 ，出《》") : "正在准备键盘…")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 530_000_000)
                blink.toggle()
            }
        }
    }
}
