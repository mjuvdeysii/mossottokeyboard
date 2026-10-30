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
        host.onChange = { [weak self] in self?.refresh() }
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
                    if self.step == passed { self.step = min(passed + 1, lessons.count) }
                    self.justPassed = false
                    self.firstDone = false
                    self.firstKeys = nil
                }
            }
        }
    }

    /// The keyboard to practise on (this app's own copy of the settings: the keyboard in other apps is unaffected).
    @Published var layout = 0 {   // 0 全拼, 1 小鹤双拼, 2 九宫格
        didSet { applyLayout() }
    }
    /// 小鹤键位提示 on the practice keyboard (the letters show their initial and finals).
    @Published var guide = true {
        didSet { applyLayout() }
    }
    func applyLayout() {
        let s = KeyboardSettings.shared
        s.scheme = layout == 1 ? 0 : 1
        s.pinyinGrid = layout == 2
        s.xiaoheGuide = guide
        keyboard?.applySettings()
    }

    func skip() {
        firstDone = false; firstKeys = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step = min(step + 1, lessons.count) }
    }
    func restart() { clear(); layout = 0; firstDone = false; firstKeys = nil; withAnimation { step = 0 } }
    func clear() { host.clear(); refresh() }

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
    /// Owned by the app (AppNavigation), so 「了解」 can send someone straight to a lesson.
    @ObservedObject var model: PlaygroundModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.step < lessons.count {
                        LessonCard(model: model, index: model.step)
                    } else {
                        DoneCard(model: model)
                    }
                    TextArea(model: model)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.never)
            // (the CI snapshot run starts its own keyboards: none here)
            Group { if SnapshotRenderer.requested { Color.clear } else { KeyboardHostView(model: model) } }
                .frame(height: 264)
                .background(Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.10, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1) }))
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
                Button("跳过") { model.skip() }.font(.subheadline)
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

private struct DoneCard: View {
    @ObservedObject var model: PlaygroundModel
    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: mostoImage("Mosto")).resizable().scaledToFit().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("都会了").font(.title3.weight(.bold))
                Text("随便打打试试。到“启用”里添加键盘，就能在所有 App 里用。").font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("练习用的键盘", selection: $model.layout) {
                    Text("全拼").tag(0)
                    Text("小鹤双拼").tag(1)
                    Text("九宫格").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)
                if model.layout == 1 {
                    // 小鹤 on the practice keyboard: the guide on the keys, and a few words to try
                    Toggle("键位提示", isOn: $model.guide).font(.subheadline).tint(mostoTint)
                    Text("试试：nihc 你好 · vsgo 中国 · ulpb 双拼 · keyi 可以").font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button("再来一遍") { model.restart() }.font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(UIColor.secondarySystemGroupedBackground)))
    }
}

/// What has been typed: the text, the keys being composed underlined (as a text field shows them), a cursor.
struct TextArea: View {
    @ObservedObject var model: PlaygroundModel
    @State private var blink = true
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            (Text(model.before) + Text(model.marked).underline() + Text(blink ? "|" : " ").foregroundColor(mostoTint))
                .font(.system(size: 20))
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    if model.before.isEmpty && model.marked.isEmpty {
                        Text(model.ready ? "在下面的键盘上打字" : "键盘准备中…").font(.system(size: 20)).foregroundStyle(.tertiary).padding(.leading, 10)
                    }
                }
            if !model.before.isEmpty || !model.marked.isEmpty {
                Button { model.clear() } label: { Label("清空", systemImage: "xmark.circle.fill").font(.caption.weight(.semibold)) }
                    .foregroundStyle(.secondary)
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
