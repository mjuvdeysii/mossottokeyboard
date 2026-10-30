import UIKit

/// A text field for the test bench: the same calls the system's proxy takes, applied to a string with a cursor and
/// marked text the way UIKit text views do (marked text sits at the cursor and is part of the text before it;
/// inserting replaces it; unmarking keeps it). It also records what a real host would punish: deleting while
/// something is marked (hosts disagree about what that deletes).
class FakeTextHost: NSObject, UITextDocumentProxy {
    private(set) var text: [Character] = []
    private(set) var cursor = 0
    private(set) var marked: Range<Int>?
    private(set) var deletesWhileMarked = 0
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    let identifier = UUID()

    var string: String { String(text) }
    var markedString: String? { marked.map { String(text[$0]) } }

    var documentContextBeforeInput: String? { String(text[..<cursor]) }
    var documentContextAfterInput: String? { String(text[cursor...]) }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { identifier }
    var hasText: Bool { !text.isEmpty }

    func insertText(_ s: String) {
        if let m = marked {
            text.replaceSubrange(m, with: Array(s))
            cursor = m.lowerBound + s.count
            marked = nil
        } else {
            text.insert(contentsOf: Array(s), at: cursor)
            cursor += s.count
        }
    }
    func deleteBackward() {
        if let m = marked {
            deletesWhileMarked += 1
            text.removeSubrange(m); cursor = m.lowerBound; marked = nil
            return
        }
        guard cursor > 0 else { return }
        text.remove(at: cursor - 1); cursor -= 1
    }
    func adjustTextPosition(byCharacterOffset offset: Int) {
        marked = nil
        cursor = max(0, min(text.count, cursor + offset))
    }
    func setMarkedText(_ s: String, selectedRange: NSRange) {
        let start: Int
        if let m = marked { text.removeSubrange(m); start = m.lowerBound } else { start = cursor }
        text.insert(contentsOf: Array(s), at: start)
        cursor = start + s.count
        marked = s.isEmpty ? nil : start..<(start + s.count)
    }
    func unmarkText() { marked = nil }
    func clear() { text = []; cursor = 0; marked = nil }
}

/// CI: drives the real KeyboardViewController against FakeTextHost — fixed scenarios with expected text, then
/// thousands of random key sequences checked for the composition rules after every key. Writes
/// Documents/keyboard-tests.txt; a line starting with FAIL blocks the release.
@MainActor
enum KeyboardTests {
    static var report: [String] = []
    static var failures = 0

    static func log(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if !ok { failures += 1 }
        report.append((ok ? "PASS " : "FAIL ") + name + (ok ? "" : "  " + detail()))
    }

    static func makeKeyboard(scheme: Int, grid: Bool = false, english: Bool = true, in window: UIWindow) -> (KeyboardViewController, FakeTextHost)? {
        LaunchGuard.succeeded()   // each bench keyboard is a fresh launch; none of them failed
        let s = KeyboardSettings.shared
        s.scheme = scheme
        s.pinyinGrid = grid
        s.english = english
        s.autocorrect = true
        s.appearance = 0
        let vc = KeyboardViewController()
        let host = FakeTextHost()
        vc.hostOverride = host
        window.rootViewController = vc
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 264)
        vc.beginAppearanceTransition(true, animated: false)
        vc.endAppearanceTransition()
        vc.view.layoutIfNeeded()
        guard vc.waitForEngineForTests() else { return nil }
        vc.applySettings()
        return (vc, host)
    }

    static func drain(_ s: Double = 0.03) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    /// Until the candidates shown are for the keys typed (a decode can take 100 ms on a busy CI simulator).
    static func settle(_ vc: KeyboardViewController) {
        let until = Date().addingTimeInterval(3)
        repeat { drain(0.01) } while !vc.testSettled && Date() < until
        drain(0.01)
    }

    /// Type letters (exact taps), then the given action.
    static func type(_ vc: KeyboardViewController, _ letters: String) {
        for c in letters {
            if "23456789'".contains(c) && KeyboardSettings.shared.pinyinGrid { vc.handle(.t9(c), tap: nil) }
            else { vc.handle(.char(String(c)), tap: Tap.exact(c)) }
        }
    }

    static func run(in window: UIWindow, to file: URL) {
        let ext = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MossOttoKeyboardExt.appex")
        guard let kb = ext.flatMap(Bundle.init(url:)) else {
            log(false, "setup", "keyboard extension not found"); write(file); return
        }
        KeyboardViewController.resourceBundle = kb
        KeyboardViewController.keepsLearnedWords = false
        let saved = (KeyboardSettings.shared.scheme, KeyboardSettings.shared.pinyinGrid, KeyboardSettings.shared.english)
        scenarios(window)
        tryFromDemo(window)
        feedback(window)
        strip(window)
        clearSwipe(window)
        fuzz(window)
        KeyboardSettings.shared.scheme = saved.0; KeyboardSettings.shared.pinyinGrid = saved.1; KeyboardSettings.shared.english = saved.2
        report.insert(failures == 0 ? "ALL PASS (\(report.count) checks)" : "FAILURES \(failures)", at: 0)
        write(file)
    }

    static func write(_ file: URL) {
        try? report.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        print(report.prefix(80).joined(separator: "\n"))
    }

    // MARK: - Scenarios: what a person does, and the text that must result

    static func scenarios(_ window: UIWindow) {
        // 小鹤双拼
        if let kb = makeKeyboard(scheme: 0, in: window) {
            let (vc, h) = kb
            type(vc, "nihc"); drain()
            log(h.markedString == "nihc", "xiaohe.marked shows the keys", "marked=\(h.markedString ?? "nil")")
            vc.handle(.space, tap: nil)
            log(h.string == "你好" && h.marked == nil, "xiaohe.space commits 你好", "text=\(h.string)")
            type(vc, "keyil"); vc.handle(.space, tap: nil)
            log(h.string == "你好可以了", "xiaohe.odd keys: keyil → 可以了", "text=\(h.string)")
            type(vc, "nihc"); vc.handle(.delete, tap: nil); drain()
            log(h.markedString == "nih" && vc.testState.keys == "nih", "xiaohe.delete takes back one key", "marked=\(h.markedString ?? "nil")")
            vc.handle(.delete, tap: nil); vc.handle(.delete, tap: nil); vc.handle(.delete, tap: nil)
            log(h.string == "你好可以了" && h.marked == nil && !vc.testState.composing, "xiaohe.delete all keys leaves the text", "text=\(h.string)")
            vc.handle(.delete, tap: nil)
            log(h.string == "你好可以", "xiaohe.delete then deletes text", "text=\(h.string)")
            type(vc, "nihc"); vc.handle(.ret, tap: nil)
            log(h.string == "你好可以nihc" && h.marked == nil, "xiaohe.return commits the letters", "text=\(h.string)")
            type(vc, "nihc"); settle(vc)
            let c = vc.testState.candidates
            if c.count > 1 { vc.candidateTapped(1) }
            log(c.count > 1 && h.string == "你好可以nihc" + c[1], "xiaohe.tap the second candidate", "text=\(h.string) cands=\(c.prefix(3))")
            type(vc, "wo"); vc.handle(.toggleLanguage, tap: nil)
            log(h.string.hasSuffix("wo") && h.marked == nil && vc.testState.english, "xiaohe.中/英 mid-word commits the letters", "text=\(h.string)")
        } else { log(false, "xiaohe.setup", "engine did not load") }

        // 全拼 and English
        if let kb = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = kb
            type(vc, "nihao"); vc.handle(.space, tap: nil)
            log(h.string == "你好", "quanpin.nihao → 你好", "text=\(h.string)")
            type(vc, "nh"); vc.handle(.space, tap: nil)
            log(h.string == "你好你好", "quanpin.abbreviation nh → 你好", "text=\(h.string)")
            // 简洁 (无主题): switching the style redraws the keys and types the same
            KeyboardSettings.shared.style = 1; vc.applySettings()
            type(vc, "nihao"); settle(vc); vc.handle(.space, tap: nil)
            log(h.string.hasSuffix("你好") && Theme.plain, "style.简洁 types as before", "text=\(h.string)")
            KeyboardSettings.shared.style = 0; vc.applySettings()
            log(!Theme.plain, "style.back to Mosto", "")
            // 连续打字: a punctuation key commits the reading and follows it, the next words read on in context
            type(vc, "womenzoule"); settle(vc); vc.handle(.char("，"), tap: nil)
            log(h.string.hasSuffix("我们走了，") && h.marked == nil, "continuous.，commits the reading first", "text=\(h.string)")
            type(vc, "mingtianjian"); settle(vc); vc.handle(.char("。"), tap: nil)
            log(h.string.hasSuffix("明天见。"), "continuous.。 after the next words", "text=\(h.string)")
            type(vc, "jintianttianqihenhao"); settle(vc); vc.handle(.space, tap: nil)
            log(h.string.hasSuffix("今天天气很好"), "quanpin.one key too many: jintianttianqihenhao → 今天天气很好", "text=\(h.string)")
            log(vc.candidateBarForTests.undoTextForTests == "jintianttianqihenhao", "quanpin.undo chip offers the keys as typed",
                "chip=\(vc.candidateBarForTests.undoTextForTests ?? "nil")")
            let before = h.string
            vc.candidateBarForTests.undoTapForTests()
            settle(vc)
            log(!h.string.hasSuffix("今天天气很好") && vc.testState.keys == "jintianttianqihenhao", "quanpin.undo chip puts the keys back",
                "text=\(h.string) keys=\(vc.testState.keys)")
            vc.handle(.space, tap: nil)
            log(h.string.count > before.count - 6 && h.marked == nil && !vc.testState.composing,
                "quanpin.after undo, space commits the keys read without correction", "text=\(h.string)")
            type(vc, "woxiangqumaidonxi"); settle(vc); vc.handle(.space, tap: nil)
            log(h.string.hasSuffix("我想去买东西"), "quanpin.one key left out: woxiangqumaidonxi → 我想去买东西", "text=\(h.string)")
            type(vc, "woyongiphonedazi"); settle(vc); vc.handle(.space, tap: nil)
            log(h.string.hasSuffix("我用iPhone打字"), "mixed.woyongiphonedazi → 我用iPhone打字", "text=\(h.string)")
            vc.handle(.toggleLanguage, tap: nil)
            type(vc, "teh"); vc.handle(.space, tap: nil)
            log(h.string.hasSuffix("the "), "english.teh → the", "text=\(h.string)")
            vc.handle(.delete, tap: nil)
            log(h.string.hasSuffix("teh"), "english.delete undoes the correction", "text=\(h.string)")
            vc.handle(.space, tap: nil); vc.handle(.space, tap: nil)
            log(h.string.hasSuffix("teh. "), "english.double space types a full stop", "text=\(h.string)")
            vc.handle(.toggleLanguage, tap: nil)
            type(vc, "ok"); vc.handle(.space, tap: nil)
            log(h.string.hasSuffix("OK"), "mixed.ok → OK", "text=\(h.string)")
            vc.handle(.page(.numbers), tap: nil); vc.handle(.char("3"), tap: nil); vc.handle(.char("。"), tap: nil); vc.handle(.char("1"), tap: nil)
            log(h.string.hasSuffix("3.1"), "numbers.。 after a digit is a decimal point", "text=\(h.string)")
        } else { log(false, "quanpin.setup", "engine did not load") }

        // 联想: after a Chinese commit, next-word suggestions; tapping one types it and suggests again
        if let kb = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = kb
            type(vc, "nihao"); settle(vc); vc.handle(.space, tap: nil)
            let until = Date().addingTimeInterval(3)
            repeat { drain(0.02) } while vc.testState.predictions.isEmpty && Date() < until
            let p = vc.testState.predictions
            log(h.string == "你好" && !p.isEmpty, "predict.suggestions after 你好", "text=\(h.string) predictions=\(p)")
            if let first = p.first {
                vc.candidateTapped(0)
                log(h.string == "你好" + first && h.marked == nil, "predict.tap types the suggestion", "text=\(h.string)")
            }
            vc.handle(.space, tap: nil)   // (no-op guard: the suggestion row is gone after any key)
            type(vc, "dangao"); settle(vc)
            let hc = vc.testState.candidates
            if let i = hc.firstIndex(of: "🎂") {
                vc.candidateTapped(i)
                log(i >= 1 && h.string.hasSuffix("🎂") && !vc.testState.composing, "emoji.蛋糕 offers 🎂 after the words", "index=\(i) text=\(h.string)")
            } else { log(false, "emoji.蛋糕 offers 🎂 after the words", "candidates=\(hc.prefix(6))") }
            type(vc, "a")
            log(vc.testState.predictions.isEmpty && vc.testState.composing, "predict.a key ends the suggestions", "predictions=\(vc.testState.predictions)")
            vc.handle(.space, tap: nil)
        } else { log(false, "predict.setup", "engine did not load") }

        // The cursor moved away from the word just typed: a delete there is a delete, not an undo
        if let kb = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = kb
            vc.handle(.toggleLanguage, tap: nil)
            type(vc, "teh"); vc.handle(.space, tap: nil)
            type(vc, "teh"); vc.handle(.space, tap: nil)
            h.adjustTextPosition(byCharacterOffset: -4)
            vc.selectionDidChange(nil)
            vc.handle(.delete, tap: nil)
            log(h.string.lowercased() == "thethe ", "moved.delete after moving the cursor deletes one character", "text=\(h.string)")
            vc.handle(.toggleLanguage, tap: nil)
            h.adjustTextPosition(byCharacterOffset: 10)
            vc.selectionDidChange(nil)
            type(vc, "ni")
            vc.candidateBarForTests.onMostoTap?()
            log(h.marked == nil && !vc.testState.composing && !h.string.contains("ni"), "mosto.tap mid-word commits the word first", "text=\(h.string) marked=\(h.markedString ?? "nil")")
        } else { log(false, "moved.setup", "engine did not load") }

        // 九宫格
        if let kb = makeKeyboard(scheme: 1, grid: true, in: window) {
            let (vc, h) = kb
            type(vc, "64426"); settle(vc)
            log(vc.testState.composing && h.marked != nil, "t9.keys compose with the pinyin shown", "marked=\(h.markedString ?? "nil")")
            vc.handle(.space, tap: nil)
            log(h.string == "你好" && h.marked == nil, "t9.64426 → 你好", "text=\(h.string)")
            type(vc, "64426"); vc.handle(.clearInput, tap: nil)
            log(h.string == "你好" && h.marked == nil && !vc.testState.composing, "t9.重输 drops the keys", "text=\(h.string)")
        } else { log(false, "t9.setup", "engine did not load") }
    }

    // MARK: - The app: 「了解」页演示卡的「试一试」

    /// 试一试 on a demo card opens 上手 at that demo's lesson, with the field empty — also when something was being
    /// typed there (the real keyboard typing into the playground's own text area, as in the app).
    static func tryFromDemo(_ window: UIWindow) {
        let missing = demoLessons.filter { pair in !lessons.contains { $0.title == pair.value } }
        log(missing.isEmpty, "app.every 试一试 has its lesson", "missing=\(missing)")
        let nav = AppNavigation()
        let p = nav.playground
        nav.tab = .about
        guard let kb = makeKeyboard(scheme: 1, in: window) else { log(false, "app.setup", "engine did not load"); return }
        let vc = kb.0
        vc.hostOverride = p.host
        p.keyboard = vc
        type(vc, "nihao"); settle(vc); vc.handle(.space, tap: nil)
        type(vc, "jintian"); settle(vc)
        drain(0.05)
        log(!p.host.string.isEmpty && vc.testState.composing, "app.something typed on 上手 before 试一试", "text=\(p.host.string)")
        nav.tryDemo("长句多按、漏按一个键")
        drain(0.05)
        let title = p.step < lessons.count ? lessons[p.step].title : "(done)"
        log(nav.tab == .playground, "app.试一试 opens 上手", "tab=\(nav.tab)")
        log(title == "长句漏按一个键", "app.试一试 on 长句多按、漏按一个键 opens 长句漏按一个键", "lesson=\(title)")
        log(p.host.string.isEmpty && p.before.isEmpty && p.marked.isEmpty && !vc.testState.composing && !p.justPassed,
            "app.试一试 starts with an empty field", "text=\(p.host.string) before=\(p.before) marked=\(p.marked) keys=\(vc.testState.keys)")

        // 清空正在打的拼音 (rounds/R3.md): the lesson the 上手 page opens at (no 了解 card leads to it: the same jump
        // its 试一试 would make), done step by step — swipe off delete, then ↩
        let clearTitle = "清空正在打的拼音"
        let ci = lessons.firstIndex { $0.title == clearTitle }
        log(ci == lessons.firstIndex { $0.title == "撤回纠错" }.map { $0 + 1 }, "app.清空 lesson follows 撤回纠错", "index=\(String(describing: ci))")
        if let ci {
            type(vc, "jintian"); vc.handle(.clearInput, tap: nil); drain(0.05)
            log(vc.candidateBarForTests.undoTextForTests == "jintian", "app.a clear before the jump leaves its ↩", "chip=\(vc.candidateBarForTests.undoTextForTests ?? "nil")")
            type(vc, "wo"); drain(0.02)
            p.jump(to: ci)
            drain(0.05)
            log(p.step == ci && p.host.string.isEmpty && !vc.testState.composing && vc.testState.restorable == nil
                && vc.candidateBarForTests.undoTextForTests == nil,
                "clearSwipe.jump(to:) leaves no ↩ chip", "step=\(p.step) chip=\(vc.candidateBarForTests.undoTextForTests ?? "nil") text=\(p.host.string)")
            type(vc, "nihao"); settle(vc); drain(0.05)
            let kb = vc.keyboardViewForTests
            if let d = kb.keyRectsForTests(.delete) {
                kb.feedForTests(swipe(from: CGPoint(x: d.cap.midX, y: d.cap.midY), to: CGVector(dx: -90, dy: 0), duration: 0.25))
            }
            drain(0.1)
            log(p.firstDone && !p.justPassed && !vc.testState.composing && vc.testState.restorable == "nihao",
                "app.清空 lesson: the swipe is the first step", "firstDone=\(p.firstDone) restorable=\(vc.testState.restorable ?? "nil")")
            vc.candidateBarForTests.undoTapForTests()
            drain(0.1)
            log(p.justPassed && vc.testState.keys == "nihao", "app.清空 lesson: ↩ brings the keys back and passes",
                "justPassed=\(p.justPassed) keys=\(vc.testState.keys)")
            drain(1.3)
        }
        p.keyboard = nil
    }

    // MARK: - Feedback: the table, and what the keyboard plays (rounds/R2.md)

    static func feedback(_ window: UIWindow) {
        // the table, row by row
        func r(_ e: FeedbackEvent) -> FeedbackResponse { FeedbackModel.response(for: e) }
        let rows: [(String, FeedbackEvent, FeedbackResponse)] = [
            ("letter", .key(.char("a")), FeedbackResponse(kind: .impact, intensity: 0.6, sound: 1104)),
            ("九宫格 key", .key(.t9("5")), FeedbackResponse(kind: .impact, intensity: 0.6, sound: 1104)),
            ("space", .key(.space), FeedbackResponse(kind: .impact, intensity: 1, sound: 1104)),
            ("delete", .key(.delete), FeedbackResponse(kind: .impact, intensity: 1, sound: 1155)),
            ("return", .key(.ret), FeedbackResponse(kind: .impact, intensity: 1, sound: 1156)),
            ("shift", .key(.shift), FeedbackResponse(kind: .impact, intensity: 1, sound: 1156)),
            ("candidate", .candidate, FeedbackResponse(kind: .impact, intensity: 0.6, sound: 1104)),
            ("undo chip", .undoChip, FeedbackResponse(kind: .impact, intensity: 1, sound: 1155)),
            ("other characters shown", .altShown, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("other character chosen", .altMoved, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("cursor mode", .cursorMode, FeedbackResponse(kind: .impact, intensity: 1, sound: nil)),
            ("cursor step", .cursorStep, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("word delete", .deleteWord, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("clear armed", .clearArmed, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("clear", .key(.clearInput), FeedbackResponse(kind: .impact, intensity: 1, sound: 1156)),
            ("Mosto", .mosto, FeedbackResponse(kind: .soft, intensity: 0.7, sound: 1156)),
        ]
        for (name, e, want) in rows { log(r(e) == want, "feedback.table \(name)", "got \(r(e))") }

        guard let kb = makeKeyboard(scheme: 1, in: window) else { log(false, "feedback.setup", "engine did not load"); return }
        let vc = kb.0
        let rec = RecordingFeedbackPlayer()
        vc.feedbackPlayer = rec
        let s = KeyboardSettings.shared
        let (oldFeedback, oldSound) = (s.feedback, s.keySound)
        defer { s.feedback = oldFeedback; s.keySound = oldSound; vc.applySettings() }
        s.feedback = true; s.keySound = true; vc.applySettings()

        // in this app the keyboard plays whatever 允许完全访问 says (the 上手 page)
        log(vc.feedbackAllowed, "feedback.inside the app: allowed", "hasFullAccess=\(vc.hasFullAccess)")
        rec.clear(); vc.feel(.key(.char("a")))
        log(rec.haptics == [.init(kind: .impact, intensity: 0.6)] && rec.sounds == [1104], "feedback.a: one light tap and a click",
            "\(rec.haptics) \(rec.sounds)")
        rec.clear(); vc.feel(.key(.delete))
        log(rec.haptics == [.init(kind: .impact, intensity: 1)] && rec.sounds == [1155], "feedback.delete: one firm tap and the delete click",
            "\(rec.haptics) \(rec.sounds)")
        rec.clear(); vc.feel(.mosto)
        log(rec.haptics == [.init(kind: .soft, intensity: 0.7)], "feedback.Mosto: soft", "\(rec.haptics)")
        let keys: [KeyAction] = [.char("q"), .space, .ret, .shift, .delete, .t9("2"), .page(.numbers), .toggleLanguage, .emoji]
        rec.clear(); for k in keys { vc.feel(.key(k)) }
        log(!rec.haptics.contains { $0.kind == .soft }, "feedback.no key is soft", "\(rec.haptics)")

        // switches on their own
        s.feedback = false; s.keySound = true; vc.applySettings()
        rec.clear(); vc.feel(.key(.char("a")))
        log(rec.haptics.isEmpty && rec.sounds == [1104], "feedback.震动 off: only the click", "\(rec.haptics) \(rec.sounds)")
        s.feedback = true; s.keySound = false; vc.applySettings()
        rec.clear(); vc.feel(.key(.char("a")))
        log(rec.haptics.count == 1 && rec.sounds.isEmpty, "feedback.按键音 off: only the tap", "\(rec.haptics) \(rec.sounds)")
        s.keySound = true

        // without 允许完全访问 (in another app): nothing at all, and the diagnostics say why
        vc.fullAccessOverride = false
        vc.applySettings()
        rec.clear()
        for e: FeedbackEvent in [.key(.char("a")), .key(.delete), .candidate, .undoChip, .altShown, .cursorStep, .mosto] { vc.feel(e) }
        log(rec.haptics.isEmpty && rec.sounds.isEmpty, "feedback.without full access: nothing", "\(rec.haptics) \(rec.sounds)")
        log(vc.diagnosticsForTests.contains("完全访问 未开"), "feedback.diagnostics say 完全访问 未开", vc.diagnosticsForTests)
        vc.fullAccessOverride = nil
        vc.applySettings()
    }

    // MARK: - Recorded touches (rounds/R3.md, 方案第 3 项)

    static let fuzzSeed: UInt64 = 0x4D6F_7374_6F52_3301
    static let typingSeed: UInt64 = 0x4D6F_7374_6F52_3302

    /// The bench's clock for recorded touches: every sequence starts a second after the last one ended, so no timer
    /// of one (a long press, held delete) runs into the next.
    static var benchTime = CACurrentMediaTime()
    static func nextTime() -> CFTimeInterval { benchTime += 1; return benchTime }

    /// A finger from `p` along `legs` (each: where it is by the end, relative to `p`, and how long that takes), moved
    /// samples at 60 Hz, then lifted (or cancelled) where it ended.
    static func path(id: Int = 1, from p: CGPoint, legs: [(CGVector, Double)], at t0: CFTimeInterval? = nil,
                     end: TouchSample.Phase = .ended) -> [TouchSample] {
        var t = t0 ?? nextTime()
        var out = [TouchSample(id: id, phase: .began, point: p, time: t)]
        var from = CGVector.zero
        for (to, d) in legs {
            let steps = max(1, Int((d * 60).rounded(.up)))
            for k in 1...steps {
                let f = CGFloat(k) / CGFloat(steps)
                out.append(TouchSample(id: id, phase: .moved,
                                       point: CGPoint(x: p.x + from.dx + (to.dx - from.dx) * f, y: p.y + from.dy + (to.dy - from.dy) * f),
                                       time: t + d * Double(f)))
            }
            t += d
            from = to
        }
        out.append(TouchSample(id: id, phase: end, point: CGPoint(x: p.x + from.dx, y: p.y + from.dy), time: t))
        return out
    }

    /// One straight swipe.
    static func swipe(from p: CGPoint, to d: CGVector, duration: Double, end: TouchSample.Phase = .ended) -> [TouchSample] {
        path(from: p, legs: [(d, duration)], end: end)
    }

    static func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    /// Continuous typing on the real keys, from a fixed seed: letters 82 %, delete 8 %, space 10 %; each lands at
    /// the key's centre plus a σ = 6 pt scatter, is held 40–140 ms and drifts 0–12 pt in any direction meanwhile —
    /// delete 0–30 pt, half of the time to the left. The random source (SeededRandom) is the one the fuzz uses.
    static func typingSamples(_ kb: KeyboardView, keys: Int, rng: inout SeededRandom) -> [[TouchSample]] {
        let letters = Array("abcdefghijklmnopqrstuvwxyz").compactMap { kb.keyRectsForTests(.char(String($0)))?.cap }
        guard letters.count == 26, let space = kb.keyRectsForTests(.space)?.cap, let del = kb.keyRectsForTests(.delete)?.cap else { return [] }
        var out: [[TouchSample]] = []
        var t = nextTime()
        for k in 0..<keys {
            let r = rng.int(100)
            let cap = r < 82 ? letters[rng.int(26)] : r < 90 ? del : space
            let p = CGPoint(x: cap.midX + CGFloat(rng.gauss() * 6), y: cap.midY + CGFloat(rng.gauss() * 6))
            let hold = 0.04 + rng.unit() * 0.10
            let isDelete = cap == del
            let reach = CGFloat(rng.unit()) * (isDelete ? 30 : 12)
            let angle = isDelete && rng.int(2) == 0 ? Double.pi * (0.75 + rng.unit() * 0.5) : rng.unit() * 2 * Double.pi
            let drift = CGVector(dx: reach * CGFloat(cos(angle)), dy: reach * CGFloat(sin(angle)))
            out.append(path(id: k, from: p, legs: [(drift, hold)], at: t))
            t += hold + 0.03 + rng.unit() * 0.12
        }
        benchTime = t
        return out
    }

    /// The keyboard as built now (A) and the same keyboard without the swipe to clear (B, "the version before"),
    /// each typing into its own field; the same touches go to both.
    struct Pair { let a: KeyboardViewController; let ha: FakeTextHost; let b: KeyboardViewController; let hb: FakeTextHost; let window2: UIWindow }

    static func makePair(_ window: UIWindow, scheme: Int = 1, grid: Bool = false) -> Pair? {
        let w2: UIWindow = window.windowScene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: window.frame)
        w2.frame = window.frame
        guard let b = makeKeyboard(scheme: scheme, grid: grid, in: w2), let a = makeKeyboard(scheme: scheme, grid: grid, in: window) else { return nil }
        b.0.keyboardViewForTests.clearSwipeEnabled = false
        for vc in [a.0, b.0] { vc.feedbackPlayer = RecordingFeedbackPlayer() }
        return Pair(a: a.0, ha: a.1, b: b.0, hb: b.1, window2: w2)
    }

    static func reset(_ vc: KeyboardViewController, _ h: FakeTextHost) {
        vc.discardComposition()
        h.clear()
        vc.textDidChange(nil)
        drain(0.01)
    }

    /// Both keyboards: reset, `setup` typed (exact keys), then the same touches. Returns whether A ended as B did
    /// (the field and the keys being composed) and how many times A cleared.
    static func ab(_ pr: Pair, setup: String, commit: Bool = false, _ touches: (KeyboardView) -> [TouchSample]) -> (same: Bool, clears: Int, detail: String) {
        var clears = 0
        for (vc, h) in [(pr.a, pr.ha), (pr.b, pr.hb)] {
            reset(vc, h)
            type(vc, setup); settle(vc)
            if commit { vc.handle(.space, tap: nil); drain(0.02) }
            let kb = vc.keyboardViewForTests
            let before = kb.clearSwipes
            kb.feedForTests(touches(kb))
            settle(vc)
            if vc === pr.a { clears = kb.clearSwipes - before }
        }
        let same = pr.ha.string == pr.hb.string && pr.a.testState.keys == pr.b.testState.keys && pr.ha.markedString == pr.hb.markedString
        return (same, clears, "A text=\(pr.ha.string) keys=\(pr.a.testState.keys) · B text=\(pr.hb.string) keys=\(pr.b.testState.keys) · clears=\(clears)")
    }

    // MARK: - Candidate strip: scrolls sideways, never selects while sliding (rounds/R3.md, 方案第 1 项)

    static func strip(_ window: UIWindow) {
        // 1. 300 candidates: scrolled to the end, the last is the keys as typed; the row is exactly as long as its items
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 402, height: Metrics.toolbarHeight))
        window.addSubview(bar)
        defer { bar.removeFromSuperview() }
        func list(_ tag: Int) -> [Candidate] {
            // every word new in every list: nothing is measured before (the worst case for a refresh)
            (0..<299).map { i in Candidate(text: i % 7 == 0 ? "词语\(tag)·\(i)" : "字\(tag)·\(i)", tapCount: 3, syllables: [1], corrected: false, score: 0) }
                + [Candidate(text: "shi", tapCount: 3, syllables: [], corrected: false, score: 0)]
        }
        bar.update(preedit: "", candidates: list(0))
        let firstScreen = bar.laidOutForTests
        log(firstScreen < 300 && bar.expandShownForTests, "strip.300 candidates: only the first screens are laid out, ⌄ shown",
            "laid=\(firstScreen)")
        var guardSteps = 0, last = -1.0
        while Double(bar.stripOffsetForTests) != last && guardSteps < 600 {
            last = Double(bar.stripOffsetForTests)
            bar.stripPanForTests(dx: -bar.stripWidthForTests)
            guardSteps += 1
        }
        let frames = (0..<bar.laidOutForTests).compactMap { bar.candidateFrameForTests($0) }
        let sum = frames.reduce(0) { $0 + $1.width }
        log(bar.laidOutForTests == 300 && bar.lastLaidTextForTests == "shi" && abs(bar.stripContentWidthForTests - sum) <= 1,
            "strip.300 candidates: scrolled to the end, the last is the keys as typed, the row's length is the items' widths",
            "laid=\(bar.laidOutForTests) last=\(bar.lastLaidTextForTests ?? "nil") content=\(bar.stripContentWidthForTests) sum=\(sum)")
        // 2. one refresh of a 300-candidate list (all words new: nothing measured before), median of 100
        var times: [Double] = []
        for k in 0..<100 { times.append(bar.timedUpdateForTests(list(k + 1))) }
        times.sort()
        let median = times[50]
        log(median <= 1.0, String(format: "strip.one refresh of 300 candidates: median %.3f ms (≤ 1.0 ms, 100 refreshes)", median),
            String(format: "median %.3f ms, max %.3f ms", median, times.last ?? 0))
        log(bar.stripOffsetForTests == 0, "strip.another list starts from the beginning", "offset=\(bar.stripOffsetForTests)")
        bar.stripPanForTests(dx: -200)
        let held = bar.stripOffsetForTests
        bar.update(preedit: "", candidates: list(100))
        log(held > 0 && bar.stripOffsetForTests == held, "strip.the same list again leaves the row where it was", "before=\(held) after=\(bar.stripOffsetForTests)")

        // with the real keyboard: 全拼 shi has hundreds of candidates
        guard let kb = makeKeyboard(scheme: 1, in: window) else { log(false, "strip.setup", "engine did not load"); return }
        let (vc, h) = kb
        let cb = vc.candidateBarForTests
        var selects = 0, holds = 0
        let select = cb.onSelect, hold = cb.onLongPress
        cb.onSelect = { i in selects += 1; select?(i) }
        cb.onLongPress = { i in holds += 1; hold?(i) }
        defer { cb.onSelect = select; cb.onLongPress = hold }
        func compose() { reset(vc, h); type(vc, "shi"); settle(vc); drain(0.02) }
        func committed() -> String { h.marked.map { String(h.text[..<$0.lowerBound]) } ?? h.string }

        // 3. a swipe left starting on the first choice, 30 / 60 / 120 pt: nothing goes in — the finger alone (past
        // 10 pt it is a slide), and with the row scrolling under it
        for dx: CGFloat in [-30, -60, -120] {
            for scrolls in [false, true] {
                compose()
                guard let f = cb.candidateFrameForTests(0) else { log(false, "strip.setup", "no candidates for shi"); return }
                let s0 = selects
                let all = swipe(from: center(f), to: CGVector(dx: dx, dy: 0), duration: 0.2)
                if scrolls {
                    // the system's scrolling takes over once the finger has gone 12 pt
                    let early = all.prefix { abs($0.point.x - all[0].point.x) <= 12 }
                    cb.touchForTests(Array(early))
                    cb.stripPanForTests(dx: dx)
                    cb.touchForTests(Array(all.dropFirst(early.count)))
                } else {
                    cb.touchForTests(all)
                }
                log(selects == s0 && vc.testState.composing && vc.testState.keys == "shi" && committed().isEmpty,
                    "strip.swipe left \(Int(-dx)) pt from the first choice\(scrolls ? " (scrolling)" : ""): nothing typed",
                    "selects=\(selects - s0) text=\(h.string)")
            }
        }
        // 4. a slow slide (60 pt over 0.8 s) on a candidate: never a hold; a still finger for 0.6 s is one
        compose()
        if let f = cb.candidateFrameForTests(1) {
            let h0 = holds
            cb.touchForTests(swipe(from: center(f), to: CGVector(dx: -60, dy: 0), duration: 0.8))
            log(holds == h0, "strip.slow slide 60 pt over 0.8 s: no 删除已学词语", "holds=\(holds - h0)")
            compose()
            if let g = cb.candidateFrameForTests(1) {
                let h1 = holds, s1 = selects
                cb.touchForTests(path(from: center(g), legs: [(CGVector(dx: 2, dy: 1), 0.6)]))
                log(holds == h1 + 1 && selects == s1, "strip.(control) a finger held still 0.6 s is a hold", "holds=\(holds - h1) selects=\(selects - s1)")
            }
        }
        cb.dismissForget()
        // 5. a tap (≤ 8 pt, ≤ 0.3 s) types the word under the finger; scrolled to the 9th, a tap types the 9th
        compose()
        let cands = vc.testState.candidates
        if let f = cb.candidateFrameForTests(1), cands.count > 9 {
            cb.touchForTests(path(from: center(f), legs: [(CGVector(dx: -6, dy: 5), 0.25)]))
            log(committed() == cands[1], "strip.tap (6 pt drift, 0.25 s) types the word under the finger", "text=\(committed()) want=\(cands[1])")
            compose()
            let box = cb.stripFrameForTests
            var n = 0
            while n < 40, let g = cb.candidateFrameForTests(8), g.maxX > box.maxX - 1 { cb.stripPanForTests(dx: -40); n += 1 }
            if let g = cb.candidateFrameForTests(8), g.minX >= box.minX, g.maxX <= box.maxX {
                let s0 = selects
                cb.tapForTests(at: center(g), time: nextTime())
                log(selects == s0 + 1 && committed() == cands[8], "strip.scrolled to the 9th, a tap types the 9th",
                    "text=\(committed()) want=\(cands[8]) offset=\(cb.stripOffsetForTests)")
            } else { log(false, "strip.scrolled to the 9th, a tap types the 9th", "the 9th never came into view") }
        } else { log(false, "strip.tap types the word under the finger", "candidates=\(cands.prefix(10))") }
        // 6. a finger landing while the row still glides only stops it
        compose()
        if let f = cb.candidateFrameForTests(1) {
            let s0 = selects
            cb.touchForTests(path(from: center(f), legs: [(CGVector(dx: 1, dy: 0), 0.1)]), gliding: true)
            log(selects == s0 && committed().isEmpty, "strip.a tap while the row glides types nothing", "selects=\(selects - s0) text=\(h.string)")
        }
        // 7. scrolled, then another key: back to the start
        compose()
        cb.stripPanForTests(dx: -150)
        let scrolled = cb.stripOffsetForTests
        vc.handle(.char("i"), tap: Tap.exact("i")); settle(vc)
        log(scrolled > 0 && cb.stripOffsetForTests == 0, "strip.after scrolling, the next key starts the row from the beginning",
            "scrolled=\(scrolled) now=\(cb.stripOffsetForTests)")
        // 8. 先右划再左划 on the strip (120 pt each way): nothing typed, nothing cleared
        compose()
        if let f = cb.candidateFrameForTests(1) {
            let s0 = selects
            let all = path(from: center(f), legs: [(CGVector(dx: 120, dy: 0), 0.2), (CGVector(dx: 0, dy: 0), 0.2)])
            let early = all.prefix { abs($0.point.x - all[0].point.x) <= 12 }
            cb.touchForTests(Array(early))
            cb.stripPanForTests(dx: 120)
            cb.stripPanForTests(dx: -120)
            cb.touchForTests(Array(all.dropFirst(early.count)))
            log(selects == s0 && vc.testState.keys == "shi" && vc.testState.composing && committed().isEmpty && vc.keyboardViewForTests.clearSwipes == 0,
                "strip.right 120 pt then left 120 pt on the strip: nothing typed, nothing cleared", "selects=\(selects - s0) text=\(h.string) keys=\(vc.testState.keys)")
        }
        reset(vc, h)
    }

    // MARK: - Swipe left off delete: clears the composition, ↩ brings it back (rounds/R3.md, 方案第 2 项)

    static func clearSwipe(_ window: UIWindow) {
        let s = KeyboardSettings.shared
        let (oldFeedback, oldSound) = (s.feedback, s.keySound)
        s.feedback = true; s.keySound = true
        defer { s.feedback = oldFeedback; s.keySound = oldSound }
        guard let pr = makePair(window) else { log(false, "clearSwipe.setup", "engine did not load"); return }
        for vc in [pr.a, pr.b] { vc.applySettings() }
        let kbA = pr.a.keyboardViewForTests
        guard let del = kbA.keyRectsForTests(.delete) else { log(false, "clearSwipe.setup", "no delete key"); return }
        let dc = center(del.cap)

        // must not clear: each the same as the version without the swipe
        // 1. continuous typing, fixed seed, 5,000 keys
        do {
            var rng = SeededRandom(seed: typingSeed)
            let strokes = typingSamples(kbA, keys: 5000, rng: &rng)
            var clears = 0, mismatches = 0, firstMismatch = ""
            let base = kbA.clearSwipes
            for (vc, h) in [(pr.a, pr.ha), (pr.b, pr.hb)] { reset(vc, h) }
            // space and delete act on what was read so far: both keyboards wait for their reading first, so the two
            // fields differ only if the swipe made a difference (not by which decode happened to arrive in time)
            let letterCaps = Array("abcdefghijklmnopqrstuvwxyz").compactMap { kbA.keyRectsForTests(.char(String($0)))?.cap }
            for (k, stroke) in strokes.enumerated() {
                let onLetter = stroke.first.map { p in letterCaps.contains { $0.contains(p.point) } } ?? true
                if !onLetter { settle(pr.a); settle(pr.b) }
                pr.a.keyboardViewForTests.feedForTests(stroke)
                pr.b.keyboardViewForTests.feedForTests(stroke)
                if k % 25 == 24 { drain(0.002) }
                if k % 500 == 499 {
                    settle(pr.a); settle(pr.b)
                    if pr.ha.string != pr.hb.string || pr.a.testState.keys != pr.b.testState.keys {
                        mismatches += 1
                        if firstMismatch.isEmpty {
                            let ca = Array(pr.ha.string), cb = Array(pr.hb.string)
                            let at = (0..<min(ca.count, cb.count)).first { ca[$0] != cb[$0] } ?? min(ca.count, cb.count)
                            firstMismatch = "after \(k + 1) keys: lengths \(ca.count)/\(cb.count), first difference at \(at): A …\(String(ca[max(0, at - 6)..<min(ca.count, at + 6)])) / B …\(String(cb[max(0, at - 6)..<min(cb.count, at + 6)])); keys A \(pr.a.testState.keys) B \(pr.b.testState.keys)"
                        }
                    }
                }
            }
            clears = kbA.clearSwipes - base
            log(strokes.count == 5000 && clears == 0 && mismatches == 0,
                "clearSwipe.typing: 5000 keys (letters 82%, delete 8%, space 10%, seed \(String(typingSeed, radix: 16))): \(clears) clears, field as without the swipe",
                "keys=\(strokes.count) clears=\(clears) mismatches=\(mismatches) \(firstMismatch)")
        }
        // 2. delete dragged 30 pt left (not 12 pt past its edge): one key deleted
        var r = ab(pr, setup: "nihao") { _ in swipe(from: dc, to: CGVector(dx: -30, dy: 0), duration: 0.2) }
        log(r.same && r.clears == 0 && pr.a.testState.keys == "niha", "clearSwipe.delete dragged 30 pt left: one key deleted", r.detail)
        // 3. held 0.6 s (repeating), then 80 pt left: the repeat as before, no clear
        r = ab(pr, setup: "woxiangqumaidongxi") { _ in path(from: dc, legs: [(.zero, 0.6), (CGVector(dx: -80, dy: 0), 0.15)]) }
        log(r.same && r.clears == 0 && pr.a.testState.keys.count < 17, "clearSwipe.held 0.6 s then 80 pt left: held delete as before, no clear", r.detail)
        // 4. up and left (Δx −60, Δy −40)
        r = ab(pr, setup: "nihao") { _ in swipe(from: dc, to: CGVector(dx: -60, dy: -40), duration: 0.2) }
        log(r.same && r.clears == 0, "clearSwipe.up-left Δx −60 Δy −40: no clear", r.detail)
        // 5. nothing composed: 60 pt left deletes one character
        r = ab(pr, setup: "nihao", commit: true) { _ in swipe(from: dc, to: CGVector(dx: -60, dy: 0), duration: 0.2) }
        log(r.same && r.clears == 0 && pr.ha.string == "你", "clearSwipe.nothing composed: 60 pt left deletes one character", r.detail)
        // 6. 先右划再左划 on the keys: from m over to delete and back
        if let m = kbA.keyRectsForTests(.char("m"))?.cap {
            r = ab(pr, setup: "nihao") { _ in path(from: center(m), legs: [(CGVector(dx: dc.x - m.midX, dy: dc.y - m.midY), 0.2), (.zero, 0.2)]) }
            log(r.same && r.clears == 0, "clearSwipe.from m to delete and back: as before, no clear", r.detail)
        }
        // 7. 先右划再左划 on space while composing: space (the first choice goes in)
        if let sp = kbA.keyRectsForTests(.space)?.cap {
            r = ab(pr, setup: "nihao") { _ in path(from: center(sp), legs: [(CGVector(dx: 60, dy: 0), 0.15), (CGVector(dx: 0, dy: 0), 0.15)]) }
            log(r.same && r.clears == 0 && !pr.a.testState.composing, "clearSwipe.space right 60 then left 60: as before (commits), no clear", r.detail)
        }
        // 8. on the strip: see strip.right 120 pt then left 120 pt
        // 9. armed, then the system cancels the touch: one key deleted, no clear
        r = ab(pr, setup: "nihao") { _ in swipe(from: dc, to: CGVector(dx: -90, dy: 0), duration: 0.2, end: .cancelled) }
        log(r.same && r.clears == 0 && pr.a.testState.keys == "niha" && !pr.a.candidateBarForTests.clearPreviewForTests,
            "clearSwipe.armed then cancelled by the system: one key deleted, no clear", r.detail)
        // 10. armed, then back over the key: one key deleted, no clear, two ticks
        let recA = pr.a.feedbackPlayer as? RecordingFeedbackPlayer
        r = ab(pr, setup: "nihao") { kb in
            if kb === kbA { recA?.clear() }
            return path(from: dc, legs: [(CGVector(dx: -90, dy: 0), 0.15), (CGVector(dx: 0, dy: 0), 0.15)])
        }
        let ticks = recA?.haptics.filter { $0.kind == .selection }.count ?? -1
        log(r.same && r.clears == 0 && pr.a.testState.keys == "niha" && ticks == 2 && !pr.a.candidateBarForTests.clearPreviewForTests,
            "clearSwipe.armed then back over delete: one key deleted, no clear, 2 ticks", r.detail + " ticks=\(ticks)")
        // 11. long press on ， and slide along its choices
        if let comma = kbA.keyRectsForTests(.char("，"))?.cap {
            r = ab(pr, setup: "nihao") { _ in path(from: center(comma), legs: [(.zero, 0.5), (CGVector(dx: -40, dy: 0), 0.2), (CGVector(dx: 30, dy: 0), 0.2)]) }
            log(r.same && r.clears == 0, "clearSwipe.long press ， and slide: as before, no clear", r.detail)
        } else { log(false, "clearSwipe.long press ，", "no ， key") }
        // 12. two fingers: one holds delete still, the other slides left and right over the letters
        if let g = kbA.keyRectsForTests(.char("g"))?.cap {
            r = ab(pr, setup: "nihao") { _ in
                let t0 = nextTime()
                let one = path(id: 1, from: dc, legs: [(.zero, 0.4)], at: t0)
                let two = path(id: 2, from: center(g), legs: [(CGVector(dx: -40, dy: 0), 0.12), (CGVector(dx: 40, dy: 0), 0.12), (.zero, 0.06)], at: t0 + 0.05)
                return (one + two).enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map { $0.element }
            }
            log(r.same && r.clears == 0, "clearSwipe.one finger still on delete, another sliding on the letters: as before, no clear", r.detail)
        }

        // must clear: Δx × duration × Δy on the full keyboard (portrait), the full keyboard in landscape, and the 九宫格
        func grid(_ name: String, _ vc: KeyboardViewController, _ h: FakeTextHost, setup: String) {
            let kb = vc.keyboardViewForTests
            guard let d = kb.keyRectsForTests(.delete) else { log(false, "clearSwipe.\(name) setup", "no delete key"); return }
            let start = center(d.cap)
            var valid = 0, recognised = 0, outside = 0, falseClears = 0, restored = 0, misses: [String] = [], restoreDiff = ""
            reset(vc, h); type(vc, setup); settle(vc)
            let keys = vc.testState.keys, cands = vc.testState.candidates, taps = vc.tapsForTests
            for dx: CGFloat in [-48, -60, -90, -140] {
                for dur in [0.12, 0.25, 0.40] {
                    for dy: CGFloat in [0, 15, -15, 24, -24] {
                        if vc.testState.keys != keys { reset(vc, h); type(vc, setup); settle(vc) }
                        let committed = h.marked.map { String(h.text[..<$0.lowerBound]) } ?? h.string
                        let before = kb.clearSwipes
                        kb.feedForTests(swipe(from: start, to: CGVector(dx: dx, dy: dy), duration: dur))
                        settle(vc)
                        let cleared = kb.clearSwipes > before
                        // the definition: past 12 pt beyond the key's left edge (a wide landscape key can keep a
                        // short swipe from its centre inside that margin)
                        let inDefinition = start.x + dx <= d.cap.minX - ClearSwipe.beyond
                        if inDefinition {
                            valid += 1
                            if cleared && !vc.testState.composing && h.marked == nil && h.string == committed && vc.testState.restorable == keys {
                                recognised += 1
                            } else if misses.count < 4 { misses.append("Δx \(Int(dx)) \(dur) s Δy \(Int(dy))") }
                        } else {
                            outside += 1
                            if cleared { falseClears += 1 }
                        }
                        if cleared {
                            vc.candidateBarForTests.undoTapForTests()
                            settle(vc)
                            if vc.tapsForTests == taps && vc.testState.candidates == cands { restored += 1 }
                            else if restoreDiff.isEmpty {
                                let now = vc.testState.candidates
                                let at = (0..<min(cands.count, now.count)).first { cands[$0] != now[$0] } ?? min(cands.count, now.count)
                                restoreDiff = "taps same: \(vc.tapsForTests == taps) keys \(vc.testState.keys) | counts \(cands.count)/\(now.count), first difference at \(at): was \(Array(cands[min(at, cands.count)...].prefix(4))) now \(Array(now[min(at, now.count)...].prefix(4)))"
                            }
                        }
                    }
                }
            }
            log(valid > 0 && recognised == valid, "clearSwipe.\(name): \(recognised)/\(valid) swipes inside the definition clear",
                "missed \(misses.joined(separator: "; "))")
            if outside > 0 {
                log(falseClears == 0, "clearSwipe.\(name): \(outside) grid swipes end within 12 pt of the key's edge (outside the definition) and do not clear",
                    "cleared \(falseClears)")
            }
            log(restored == recognised, "clearSwipe.\(name): ↩ brings back the same keys and candidates after every clear (\(restored)/\(recognised))",
                "restored=\(restored) \(restoreDiff)")
            reset(vc, h)
        }
        grid("portrait", pr.a, pr.ha, setup: "nihao")

        // after a clear: delete deletes a character of the field and the chip goes; a letter starts anew
        reset(pr.a, pr.ha); type(pr.a, "nihao"); pr.a.handle(.space, tap: nil); type(pr.a, "jintian"); settle(pr.a)
        let rec = pr.a.feedbackPlayer as? RecordingFeedbackPlayer
        rec?.clear()
        kbA.feedForTests(swipe(from: dc, to: CGVector(dx: -90, dy: 0), duration: 0.25))
        settle(pr.a)
        typealias Felt = RecordingFeedbackPlayer.Entry
        let firm = Felt(kind: .impact, intensity: 1), tick = Felt(kind: .selection, intensity: 1)
        log((rec?.haptics ?? []) == [firm, tick, firm] && (rec?.sounds ?? []) == [1155, 1156],
            "feedback.swipe that clears: delete (firm + 1155), tick, clear (firm + 1156)", "\(rec?.haptics ?? []) \(rec?.sounds ?? [])")
        log(pr.ha.string == "你好" && pr.ha.marked == nil && pr.a.candidateBarForTests.undoTextForTests == "jintian"
            && !pr.a.candidateBarForTests.clearPreviewForTests,
            "clearSwipe.cleared: the field keeps 你好, the chip shows jintian", "text=\(pr.ha.string) chip=\(pr.a.candidateBarForTests.undoTextForTests ?? "nil")")
        rec?.clear()
        pr.a.candidateBarForTests.undoTapForTests(); settle(pr.a)
        log((rec?.haptics ?? []) == [firm] && (rec?.sounds ?? []) == [1155], "feedback.↩ after a clear: firm + 1155",
            "\(rec?.haptics ?? []) \(rec?.sounds ?? [])")
        kbA.feedForTests(swipe(from: dc, to: CGVector(dx: -90, dy: 0), duration: 0.25)); settle(pr.a)
        pr.a.handle(.delete, tap: nil)
        log(pr.ha.string == "你" && pr.a.candidateBarForTests.undoTextForTests == nil && pr.a.testState.restorable == nil,
            "clearSwipe.after a clear, delete deletes a character and the chip goes", "text=\(pr.ha.string) chip=\(pr.a.candidateBarForTests.undoTextForTests ?? "nil")")
        type(pr.a, "jintian"); settle(pr.a)
        kbA.feedForTests(swipe(from: dc, to: CGVector(dx: -90, dy: 0), duration: 0.25)); settle(pr.a)
        type(pr.a, "w"); settle(pr.a)
        log(pr.a.testState.keys == "w" && pr.a.candidateBarForTests.undoTextForTests == nil,
            "clearSwipe.after a clear, a letter starts a new composition and the chip goes", "keys=\(pr.a.testState.keys)")
        // a long composition: the chip shortens it in the middle; VoiceOver hears all of it
        reset(pr.a, pr.ha); type(pr.a, "woxiangqumaidongxi"); settle(pr.a)
        kbA.feedForTests(swipe(from: dc, to: CGVector(dx: -90, dy: 0), duration: 0.25)); settle(pr.a)
        log(pr.a.candidateBarForTests.undoTextForTests == "woxian…ongxi" && pr.a.testState.restorable == "woxiangqumaidongxi",
            "clearSwipe.a long composition: the chip reads woxian…ongxi", "chip=\(pr.a.candidateBarForTests.undoTextForTests ?? "nil")")
        reset(pr.a, pr.ha)

        // landscape: the same keyboard 874 pt wide
        pr.a.view.frame = CGRect(x: 0, y: 0, width: 874, height: Metrics.toolbarHeightLandscape + 4 * Metrics.rowPitchLandscape)
        pr.a.view.setNeedsLayout(); pr.a.view.layoutIfNeeded(); kbA.layoutIfNeeded()
        if kbA.bounds.width > 800 { grid("landscape", pr.a, pr.ha, setup: "nihao") }
        else { log(false, "clearSwipe.landscape setup", "the keys are \(kbA.bounds.width) pt wide (the window laid the keyboard out again)") }
        pr.a.view.frame = CGRect(x: 0, y: 0, width: 402, height: 264)
        pr.a.view.setNeedsLayout(); pr.a.view.layoutIfNeeded()

        // 九宫格: the swipe, and the 重输 key, both leave the chip
        if let t9 = makeKeyboard(scheme: 1, grid: true, in: window) {
            let (vc, h) = t9
            vc.feedbackPlayer = RecordingFeedbackPlayer()
            grid("九宫格", vc, h, setup: "64426")
            type(vc, "64426"); settle(vc)
            let cands = vc.testState.candidates
            vc.handle(.clearInput, tap: nil)
            let chip = vc.candidateBarForTests.undoTextForTests
            log(!vc.testState.composing && chip == "nihao", "clearSwipe.九宫格 重输 leaves the chip with the pinyin", "chip=\(chip ?? "nil")")
            vc.candidateBarForTests.undoTapForTests(); settle(vc)
            log(vc.testState.keys == "64426" && vc.testState.candidates == cands, "clearSwipe.九宫格 ↩ after 重输 brings the keys back",
                "keys=\(vc.testState.keys) was \(cands.prefix(6)) now \(vc.testState.candidates.prefix(6))")
            reset(vc, h)
        } else { log(false, "clearSwipe.九宫格 setup", "engine did not load") }
        pr.window2.rootViewController = nil
    }

    // MARK: - Fuzz: random people, the composition rules after every key

    static func fuzz(_ window: UIWindow) {
        var rng = SeededRandom(seed: fuzzSeed)
        func r(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var steps = 0, violations: [String] = []
        for round in 0..<6 {
            let grid = round % 3 == 2
            guard let kb = makeKeyboard(scheme: round % 2, grid: grid, in: window) else { log(false, "fuzz.setup"); return }
            let (vc, h) = kb
            var recent: [String] = []
            for _ in 0..<600 {
                steps += 1
                let k = r(100)
                let before = h.string
                let names = ["key", "space", "delete", "cand", "ret", "lang", "punct", "delword", "clear", "syl", "wait"]
                let kind = k < 55 ? 0 : k < 67 ? 1 : k < 79 ? 2 : k < 84 ? 3 : k < 87 ? 4 : k < 90 ? 5 : k < 92 ? 6 : k < 94 ? 7 : k < 96 ? 8 : k < 98 ? 9 : 10
                recent.append(names[kind]); if recent.count > 6 { recent.removeFirst() }
                switch k {
                case 0..<55:
                    // the 九宫格 shows only in Chinese; English always has the full keyboard
                    if grid && !vc.testState.english { vc.handle(.t9(Array("23456789'")[r(9)]), tap: nil) }
                    else { let c = letters[r(26)]; vc.handle(.char(String(c)), tap: Tap.exact(c)) }
                case 55..<67: vc.handle(.space, tap: nil)
                case 67..<79: vc.handle(.delete, tap: nil)
                case 79..<84: vc.candidateTapped(r(6))
                case 84..<87: vc.handle(.ret, tap: nil)
                case 87..<90: vc.handle(.toggleLanguage, tap: nil)
                case 90..<92: vc.handle(.page(.numbers), tap: nil); vc.handle(.char("，"), tap: nil); vc.handle(.page(.letters), tap: nil)
                case 92..<94: vc.handle(.deleteWord, tap: nil)
                case 94..<96: vc.handle(.clearInput, tap: nil)
                case 96..<98: if vc.syllableChoiceCount > 0 { vc.pickSyllable(r(vc.syllableChoiceCount)) }
                default: drain(0.05)
                }
                // 九宫格 keys have no letter of their own: the field shows the pinyin once the decode for them is
                // back (a few ms on a phone), so the grid's rules are checked after it has had that time
                if grid {
                    // a 九宫格 decode takes a few ms on a phone and far longer on a shared CI simulator
                    settle(vc)
                } else if r(4) == 0 { drain(0.005) }
                // the rules
                let st = vc.testState
                if !st.composing && h.marked != nil { violations.append("marked text left after the composition ended (\(h.markedString ?? ""))") }
                if st.composing && h.marked == nil && !st.keys.isEmpty { violations.append("composing \(st.keys) but nothing marked in the field (english \(st.english), \(st.candidates.count) candidates, page \(st.page), settled \(vc.testSettled), after \(recent.joined(separator: ",")))") }
                if st.composing && !grid && !st.english, let m = h.markedString, m != st.keys {
                    violations.append("field shows \(m) while the keys are \(st.keys)")
                }
                if h.deletesWhileMarked > 0 { violations.append("deleteBackward while text was marked"); break }
                if h.cursor < 0 || h.cursor > h.text.count { violations.append("cursor out of range") }
                _ = before
                if violations.count > 8 { break }
            }
            vc.handle(.space, tap: nil); drain(0.1)
        }
        log(violations.isEmpty, "fuzz.\(steps) random keys keep the field and the composition in step",
            Array(Set(violations)).prefix(6).joined(separator: " | "))
    }
}

/// A random sequence that is the same on every run (SplitMix64): the bench's typing and fuzz are reproducible.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    /// In [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// Standard normal (Box–Muller).
    mutating func gauss() -> Double {
        let u1 = max(unit(), 1e-12), u2 = unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}
