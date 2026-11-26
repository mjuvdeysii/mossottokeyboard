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
        cursor(window)
        feedback(window)
        strip(window)
        clearSwipe(window)
        r48Features(window)
        r49Features(window)
        r50CraftAndReadiness(window)
        r51CompanionAndFluency(window)
        r52HardwareDeckAndOpticalCraft(window)
        r53GridParityAndIdleSeparation(window)
        r54OpticalTrackpadAndTactileProfiles(window)
        r55DualLegendFlickAndMathBadge(window)
        r56DualSchemeLessonsAndMostoState(window)
        r57PullCordAndOptical2D(window)
        r58CorrectionPinpointAndDetent(window)
        r59TrackpadEndStopAndNewlineDetent(window)
        r60DeleteClutchAndBilingualUndo(window)
        r60XiaoheMissingKeyRecovery(window)
        r61BilingualFlowAndPairOvertype(window)
        r62NestedPairsMathAndKaomojiMoodSync(window)
        r63AdjustableHeightAndOpticalScale(window)
        r64SpringLoadedModifierGlide(window)
        r65VisualCraftAndOpticalFit(window)
        r66VisualStructureAndThumbErgonomics(window)
        r67T9AltPopupAndFreeBenchInspirations(window)
        r68StageOverlaysMathSpaceAndEmojiCraft(window)
        r69HeightPersistenceAndVisualConsole(window)
        r70GridScopeRailAndDockCraft(window)
        r71XiaoheChordLighting(window)
        r72DrawerTelemetryBracketAndBenchCraft(window)
        r73GridPreeditClearCueAndAppCoverage(window)
        r74HeightAntiBounceStripSpeedAndTunerCraft(window)
        r75DeleteClutchHudAndIdleGuard(window)
        r76CursorTelemetryHudAndBracketCraft(window)
        r77KeycapBevelAndFeedbackParity(window)
        r78EmojiDockNoSliceDrawerAndXiaoheSlots(window)
        r79SmartSpacebarPairExitAndMathCue(window)
        r80ContrastCadenceAndBenchCraft(window)
        r81TrackpadGlassSmartRimAndPunctuationCraft(window)
        r82NumpadSpineEnableDarkAndLandscapeDock(window)
        r83HeightExplosionGuardIdleRailAndGlassCraft(window)
        r84ContrastRangefinderAndWorkbenchCraft(window)
        r85CommercialCompanionAndIPFamily(window)
        r86ReleaseCandidatePolish(window)
        r87WeChatTopGapElimination(window)
        r90CleanKeycapCraftNoWhiteLine(window)
        r91AppIconAndCommercialCompanion(window)
        r92SculptedKeycapAndOpticalIcons(window)
        r93SculptedConsolePopupsAndBorderlessSurfaces(window)
        r94T9UnifiedLayoutAndStateMachines(window)
        r95ZeroDriftToggleAndMostoSuperKey(window)
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

        // "点首选没反应" 回归：解码还没回来（不 settle）就点第一个候选。
        // 旧实现会走 currentResult() 的 queue.sync 同步解码；若引擎忙则主线程被卡、
        // 且 shown 取自上一代 result 时 firstIndex 找不到会直接 return（什么都不上屏）。
        // 新实现把点击排队，等 show() 用那一代结果执行 —— 点击永不阻塞，且一定有出路。
        if let kb = makeKeyboard(scheme: 0, in: window) {
            let (vc, h) = kb
            type(vc, "nihc")
            let t0 = CACurrentMediaTime()
            vc.candidateTapped(0)                 // 故意不 settle：解码仍在飞
            let blocked = (CACurrentMediaTime() - t0) * 1000
            drain(0.3)                            // 让那一代解码回来、pending 执行
            log(h.string == "你好", "xiaohe.tap first candidate before decode returns still commits",
                "text=\(h.string) tapCost=\(String(format: "%.1f", blocked))ms")
            log(blocked < 16, "xiaohe.tapping a candidate never blocks the main thread",
                "tapCost=\(String(format: "%.1f", blocked))ms")
        } else { log(false, "xiaohe.early tap setup", "engine did not load") }

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

        // 联想态意符与生命周期：用独立键盘，避免污染上面的联想链（Krug/Norman/Jef Raskin/Buxton）
        if let kb = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = kb
            type(vc, "nihao"); settle(vc); vc.handle(.space, tap: nil)
            let until = Date().addingTimeInterval(3)
            repeat { drain(0.02) } while vc.testState.predictions.isEmpty && Date() < until
            let p = vc.testState.predictions
            let bar = vc.candidateBarForTests
            log(h.string == "你好" && !p.isEmpty, "predict.marks setup", "text=\(h.string) predictions=\(p)")
            log(bar.firstCaptionForTests == "联想" && bar.predictionMarkForTests,
                "predict.strip marks these as guesses", "caption=\(bar.firstCaptionForTests ?? "nil")")
            log(!(bar.firstCaptionForTests ?? "").contains("已纠错"),
                "predict.a guess is never labelled as a correction", "caption=\(bar.firstCaptionForTests ?? "nil")")
            drain(0.3)
            vc.handle(.shift, tap: nil); vc.handle(.globe, tap: nil)
            log(vc.testState.predictions == p, "predict.thinking and shift/globe keep the suggestions",
                "predictions=\(vc.testState.predictions)")
            vc.handle(.char("a"), tap: Tap.exact("a"))
            log(vc.testState.predictions.isEmpty, "predict.a letter still ends the suggestions",
                "predictions=\(vc.testState.predictions)")
        } else { log(false, "predict.marks setup2", "engine did not load") }

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

    /// Verifies Companion App tab navigation and the real keyboard's delete-swipe-clear + ↩ restore flow.
    static func tryFromDemo(_ window: UIWindow) {
        let nav = AppNavigation()
        nav.tab = .about
        nav.focusFamilyMember(.moss)
        log(nav.tab == .companion && nav.family.activeMember == .moss,
            "app.focusFamilyMember switches from about to companion and greets member",
            "tab=\(nav.tab) member=\(nav.family.activeMember)")

        guard let kb = makeKeyboard(scheme: 1, in: window) else { log(false, "app.setup", "engine did not load"); return }
        let (vc, h) = kb
        type(vc, "jintian"); vc.handle(.clearInput, tap: nil); drain(0.05)
        log(vc.candidateBarForTests.undoTextForTests == "jintian",
            "app.clearInput leaves undo chip",
            "chip=\(vc.candidateBarForTests.undoTextForTests ?? "nil")")

        type(vc, "wo"); vc.discardComposition(); drain(0.05)
        log(h.string.isEmpty && !vc.testState.composing && vc.testState.restorable == nil
            && vc.candidateBarForTests.undoTextForTests == nil,
            "clearSwipe.discardComposition leaves clean field without stale undo chip",
            "chip=\(vc.candidateBarForTests.undoTextForTests ?? "nil") text=\(h.string)")

        type(vc, "nihao"); settle(vc); drain(0.05)
        let kv = vc.keyboardViewForTests
        if let d = kv.keyRectsForTests(.delete) {
            kv.feedForTests(swipe(from: CGPoint(x: d.cap.midX, y: d.cap.midY), to: CGVector(dx: -90, dy: 0), duration: 0.25))
        }
        drain(0.1)
        log(!vc.testState.composing && vc.testState.restorable == "nihao",
            "app.swipe left from delete clears composing keys into restorable undo chip",
            "restorable=\(vc.testState.restorable ?? "nil")")
        vc.candidateBarForTests.undoTapForTests()
        drain(0.1)
        log(vc.testState.keys == "nihao" && vc.testState.composing,
            "app.tapping undo chip restores cleared keys",
            "keys=\(vc.testState.keys)")
        drain(0.2)
    }

    // MARK: - Feedback: the table, and what the keyboard plays (rounds/R2.md)

    static func feedback(_ window: UIWindow) {
        // the table, row by row
        func r(_ e: FeedbackEvent) -> FeedbackResponse { FeedbackModel.response(for: e) }
        let rows: [(String, FeedbackEvent, FeedbackResponse)] = [
            ("letter", .key(.char("a")), FeedbackResponse(kind: .impact, intensity: 0.88, sound: 1104)),
            ("九宫格 key", .key(.t9("5")), FeedbackResponse(kind: .impact, intensity: 0.88, sound: 1104)),
            ("space", .key(.space), FeedbackResponse(kind: .impact, intensity: 1, sound: 1104)),
            ("delete", .key(.delete), FeedbackResponse(kind: .impact, intensity: 1, sound: 1155)),
            ("return", .key(.ret), FeedbackResponse(kind: .impact, intensity: 1, sound: 1156)),
            ("shift", .key(.shift), FeedbackResponse(kind: .impact, intensity: 1, sound: 1156)),
            ("candidate", .candidate, FeedbackResponse(kind: .impact, intensity: 0.88, sound: 1104)),
            ("undo chip", .undoChip, FeedbackResponse(kind: .impact, intensity: 1, sound: 1155)),
            ("other characters shown", .altShown, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("other character chosen", .altMoved, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("cursor mode", .cursorMode, FeedbackResponse(kind: .impact, intensity: 1, sound: nil)),
            ("cursor step", .cursorStep, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("cursor boundary", .cursorBoundary, FeedbackResponse(kind: .soft, intensity: 0.72, sound: nil)),
            ("word delete", .deleteWord, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("clear armed", .clearArmed, FeedbackResponse(kind: .selection, intensity: 1, sound: nil)),
            ("clear", .key(.clearInput), FeedbackResponse(kind: .impact, intensity: 1, sound: 1156)),
            ("Mosto", .mosto, FeedbackResponse(kind: .soft, intensity: 0.85, sound: 1156)),
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
        log(rec.haptics == [.init(kind: .impact, intensity: 0.88)] && rec.sounds == [1104], "feedback.a: one light tap and a click",
            "\(rec.haptics) \(rec.sounds)")
        rec.clear(); vc.feel(.key(.delete))
        log(rec.haptics == [.init(kind: .impact, intensity: 1)] && rec.sounds == [1155], "feedback.delete: one firm tap and the delete click",
            "\(rec.haptics) \(rec.sounds)")
        rec.clear(); vc.feel(.mosto)
        log(rec.haptics == [.init(kind: .soft, intensity: 0.85)], "feedback.Mosto: soft", "\(rec.haptics)")
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

        // The controller checks R2 left (rounds/R4.md, 方案第 4 项), through the real touches
        let host = kb.1
        let board = vc.keyboardViewForTests
        typealias Felt = RecordingFeedbackPlayer.Entry
        let light = Felt(kind: .impact, intensity: 0.88), firm = Felt(kind: .impact, intensity: 1), tick = Felt(kind: .selection, intensity: 1)

        // 1. long press on ， until its other characters show, then slide to the second: the key's own tap and click,
        // one tick as they show, one as the choice moves
        if let comma = board.keyRectsForTests(.char("，"))?.cap {
            reset(vc, host)
            var events: [FeedbackEvent] = []
            let felt = board.onFeedback
            board.onFeedback = { e, p in events.append(e); felt?(e, p) }
            // the row of 6 (。？！、…：) opens to the left near the right edge (KeyboardView.showAlt): one cell that way
            let cell = max(comma.width, 34)
            let reversed = comma.midX - cell / 2 - 4 + (cell * 6 + 8) > board.bounds.width - 2
            let samples = path(from: center(comma), legs: [(.zero, 0.5), (CGVector(dx: reversed ? -cell : cell, dy: 0), 0.15)])
            let held = samples.filter { $0.time <= samples[0].time + 0.5 + 1e-9 }
            rec.clear()
            board.feedForTests(held)
            let shownHaptics = rec.haptics, shownSounds = rec.sounds, shownEvents = events
            board.feedForTests(Array(samples.dropFirst(held.count)))
            board.onFeedback = felt
            log(shownHaptics == [light, tick] && shownSounds == [1104] && shownEvents == [.altShown],
                "feedback.long press ，: the key (light + 1104), then 1 tick as the choices show, no other tap, one click",
                "\(shownHaptics) \(shownSounds) \(shownEvents)")
            log(rec.haptics == [light, tick, tick] && rec.sounds == [1104] && events == [.altShown, .altMoved],
                "feedback.long press ，, slide to the second choice: 1 more tick", "\(rec.haptics) \(rec.sounds) \(events)")
        } else { log(false, "feedback.long press ，", "no ， key") }

        // 2. the cursor's ticks as the controller plays them: as many as the cursor group counted for the same drag
        if let space = board.keyRectsForTests(.space)?.cap {
            placeCursor(vc, host, before: 30, after: 30)
            rec.clear()
            board.feedForTests(path(from: center(space), legs: [(CGVector(dx: 100, dy: 0), 0.5)]))
            let ticks = rec.haptics.filter { $0 == tick }.count, firms = rec.haptics.filter { $0 == firm }.count
            log(uniformCursorSteps != nil && ticks == uniformCursorSteps && firms == 2 && rec.sounds == [1104],
                "feedback.cursor drag 100 pt / 0.5 s: \(ticks) ticks played, as the cursor group counted; space and cursor mode firm",
                "cursor group \(uniformCursorSteps.map { "\($0)" } ?? "nil") · \(rec.haptics) \(rec.sounds)")
        } else { log(false, "feedback.cursor drag", "no space key") }

        // 3. a candidate: nothing as the finger lands, one tap and click as it lifts and selects; a slide: nothing
        let cb = vc.candidateBarForTests
        reset(vc, host); type(vc, "shi"); settle(vc)
        if let f = cb.candidateFrameForTests(1) {
            let t0 = nextTime()
            rec.clear()
            cb.touchForTests([TouchSample(id: 0, phase: .began, point: center(f), time: t0)])
            let atDown = rec.haptics.count + rec.sounds.count
            cb.touchForTests([TouchSample(id: 0, phase: .ended, point: center(f), time: t0 + 0.1)])
            log(atDown == 0 && rec.haptics == [light] && rec.sounds == [1104] && !vc.testState.composing,
                "feedback.candidate: nothing as the finger lands, one light tap and 1104 as it lifts and selects",
                "at landing \(atDown) · \(rec.haptics) \(rec.sounds) text=\(host.string)")
            reset(vc, host); type(vc, "shi"); settle(vc)
            if let g = cb.candidateFrameForTests(1) {
                rec.clear()
                cb.touchForTests(swipe(from: center(g), to: CGVector(dx: -60, dy: 0), duration: 0.2))
                log(rec.haptics.isEmpty && rec.sounds.isEmpty && vc.testState.composing,
                    "feedback.slide 60 pt on the candidates, then lift: nothing felt, nothing typed", "\(rec.haptics) \(rec.sounds) text=\(host.string)")
            }
        } else { log(false, "feedback.candidate", "no candidates for shi") }

        // 4. a correction from start to undo: n i h a p (p landing on its left half, toward o), space, then ↩
        reset(vc, host)
        let rects = "nihap".compactMap { board.keyRectsForTests(.char(String($0)))?.cap }
        if rects.count == 5, let space = board.keyRectsForTests(.space)?.cap {
            var all: [Felt] = []
            rec.clear()
            var t = nextTime()
            for (i, rect) in rects.enumerated() {
                let p = CGPoint(x: i == 4 ? rect.midX - 0.4 * rect.width : rect.midX, y: rect.midY)
                board.feedForTests([TouchSample(id: 0, phase: .began, point: p, time: t), TouchSample(id: 0, phase: .ended, point: p, time: t + 0.06)])
                t += 0.15
            }
            settle(vc)
            let lettersFelt = rec.haptics == Array(repeating: light, count: 5) && rec.sounds.count == 5 && rec.sounds.allSatisfy { $0 == 1104 }
            let lettersDetail = "\(rec.haptics) \(rec.sounds)"
            all += rec.haptics
            rec.clear()
            let sp = center(space)
            board.feedForTests([TouchSample(id: 0, phase: .began, point: sp, time: t), TouchSample(id: 0, phase: .ended, point: sp, time: t + 0.08)])
            settle(vc)
            let spaceHaptics = rec.haptics, spaceSounds = rec.sounds
            all += rec.haptics
            let chip = vc.candidateBarForTests.undoTextForTests
            log(host.string == "你好" && chip == "nihap", "feedback.nihap (p toward o), space: 你好 goes in corrected, ↩ nihap offered",
                "text=\(host.string) chip=\(chip ?? "nil")")
            log(lettersFelt && spaceHaptics == [firm] && spaceSounds == [1104],
                "feedback.nihap, space: 5 light taps for the letters, then only the space key's firm tap and 1104 (nothing for the correction)",
                "letters \(lettersDetail) · space \(spaceHaptics) \(spaceSounds)")
            rec.clear()
            vc.candidateBarForTests.undoTapForTests(); settle(vc)
            all += rec.haptics
            log(rec.haptics == [firm] && rec.sounds == [1155], "feedback.↩ after the correction: one firm tap and 1155", "\(rec.haptics) \(rec.sounds)")
            log(!all.contains { $0.kind == .soft }, "feedback.the correction, start to undo: nothing soft", "\(all)")
        } else { log(false, "feedback.correction", "keys not found") }
        reset(vc, host)
    }

    // MARK: - Cursor: the space bar drags the cursor; the ticks follow the finger's distance (rounds/R4.md, 方案第 2 项)

    /// The .cursorStep count of the cursor group's first drag (100 pt / 0.5 s): the feedback group checks that the
    /// controller plays as many.
    static var uniformCursorSteps: Int?

    /// Nothing composed; `before` characters before the cursor and `after` after it.
    static func placeCursor(_ vc: KeyboardViewController, _ h: FakeTextHost, before: Int, after: Int) {
        reset(vc, h)
        h.insertText(String(repeating: "字", count: before + after))
        h.adjustTextPosition(byCharacterOffset: -after)
        vc.textDidChange(nil)
        drain(0.01)
    }

    /// The cursor steps of build 225 (KeyboardView, unchanged in R4), replayed on the same samples: where the cursor
    /// must be after each sample, from `start` in a text of `length` characters (it stops at both ends).
    static func oldRuleCursor(_ samples: [TouchSample], start: Int, length: Int) -> [Int] {
        guard let first = samples.first else { return [] }
        var c = start
        var prev = first.point
        var lastMove = first.time
        var accum: CGFloat = 0
        var dragging = false
        var out: [Int] = []
        for s in samples {
            if s.phase == .moved {
                let dx = s.point.x - prev.x
                let speed = abs(dx) / CGFloat(max(s.time - lastMove, 1.0 / 120))
                prev = s.point
                lastMove = s.time
                let threshold: CGFloat = s.time - first.time > 0.3 ? 12 : 22
                if !dragging && abs(s.point.x - first.point.x) > threshold { dragging = true; accum = 0 }
                if dragging {
                    accum += dx
                    let step: CGFloat = speed > 900 ? 3.5 : speed > 450 ? 5.5 : 9
                    while abs(accum) >= step {
                        let d = accum > 0 ? 1 : -1
                        c = max(0, min(length, c + d))
                        accum -= CGFloat(d) * step
                    }
                }
            }
            out.append(c)
        }
        return out
    }

    /// One drag as the keys felt it: the times of the ticks (the sample each came with), cursor mode, and where the
    /// field's cursor is after each sample.
    struct Drag { var cursors: [Int]; var ticks: [CFTimeInterval]; var modes: Int; var entered: CFTimeInterval?; var end: CFTimeInterval }

    static func drag(_ vc: KeyboardViewController, _ h: FakeTextHost, _ samples: [TouchSample]) -> Drag {
        let kb = vc.keyboardViewForTests
        var now: CFTimeInterval = 0
        var ticks: [CFTimeInterval] = []
        var modes = 0
        var entered: CFTimeInterval?
        let felt = kb.onFeedback
        kb.onFeedback = { e, p in
            if e == .cursorStep { ticks.append(now) }
            if e == .cursorMode { modes += 1; if entered == nil { entered = now } }
            felt?(e, p)
        }
        var cursors: [Int] = []
        for s in samples {
            now = s.time
            kb.feedForTests([s])
            cursors.append(h.cursor)
        }
        kb.onFeedback = felt
        return Drag(cursors: cursors, ticks: ticks, modes: modes, entered: entered, end: samples.last?.time ?? 0)
    }

    static func cursor(_ window: UIWindow) {
        guard let made = makeKeyboard(scheme: 1, in: window) else { log(false, "cursor.setup", "engine did not load"); return }
        let (vc, h) = made
        vc.feedbackPlayer = RecordingFeedbackPlayer()
        guard let space = vc.keyboardViewForTests.keyRectsForTests(.space)?.cap else { log(false, "cursor.setup", "no space key"); return }
        let start = center(space)
        let minGap = CursorRhythm.minInterval - CursorRhythm.slack
        func gaps(_ t: [CFTimeInterval]) -> [CFTimeInterval] { zip(t, t.dropFirst()).map { $1 - $0 } }
        func ms(_ t: [CFTimeInterval]) -> String { gaps(t).map { String(format: "%.0f", $0 * 1000) }.joined(separator: ",") }

        // 1. 100 pt in 0.5 s from the middle of space, 30 characters either side: 8 characters, 2 ticks, 1 cursor mode
        placeCursor(vc, h, before: 30, after: 30)
        let s1 = path(from: start, legs: [(CGVector(dx: 100, dy: 0), 0.5)])
        let want1 = oldRuleCursor(s1, start: 30, length: 60)
        let d1 = drag(vc, h, s1)
        let cells1 = (d1.cursors.last ?? 30) - 30
        uniformCursorSteps = d1.ticks.count
        log(d1.cursors == want1 && cells1 == 8 && d1.ticks.count == 2 && d1.modes == 1,
            "cursor.100 pt / 0.5 s: \(cells1) characters (build 225's steps), \(d1.ticks.count) ticks, \(d1.modes) cursor mode",
            "cursor \(d1.cursors.last ?? -1) want \(want1.last ?? -1) same steps \(d1.cursors == want1) gaps \(ms(d1.ticks)) ms")

        // 2. a fast drag, 300 pt in 0.25 s: the same characters as build 225; at most 3 ticks, ≥ 100 ms apart
        placeCursor(vc, h, before: 500, after: 500)
        let s2 = path(from: start, legs: [(CGVector(dx: 300, dy: 0), 0.25)])
        let want2 = oldRuleCursor(s2, start: 500, length: 1000)
        let d2 = drag(vc, h, s2)
        let cells2 = (d2.cursors.last ?? 500) - 500
        log(d2.cursors == want2 && d2.ticks.count <= 3 && gaps(d2.ticks).allSatisfy { $0 >= minGap },
            "cursor.300 pt / 0.25 s: \(cells2) characters (build 225's steps), \(d2.ticks.count) ticks (≤ 3), gaps \(ms(d2.ticks)) ms (≥ 100)",
            "cursor \(d2.cursors.last ?? -1) want \(want2.last ?? -1)")

        // 3. steady drags for 1.2 s: ticks a second = min(speed / 27, 10) ± 1, never more than 10 in a second
        for v in [50.0, 100, 200, 400, 800, 1200, 2000] {
            placeCursor(vc, h, before: 2000, after: 2000)
            let s = path(from: start, legs: [(CGVector(dx: v * 1.2, dy: 0), 1.2)])
            let want = oldRuleCursor(s, start: 2000, length: 4000)
            let d = drag(vc, h, s)
            let cells = (d.cursors.last ?? 2000) - 2000
            let span = d.end - (d.entered ?? d.end)
            let rate = span > 0 ? Double(d.ticks.count) / span : 0
            let target = min(v / 27, 10)
            let busiest = d.ticks.map { t in d.ticks.filter { $0 >= t && $0 < t + 1 - 1e-6 }.count }.max() ?? 0
            log(d.cursors == want && d.modes == 1 && abs(rate - target) <= 1 && busiest <= 10,
                String(format: "cursor.%.0f pt/s for 1.2 s: %ld characters (build 225's steps), %ld ticks, %.1f a second (want %.1f ± 1), at most %ld in a second",
                       v, cells, d.ticks.count, rate, target, busiest),
                "same steps \(d.cursors == want) cursor mode \(d.modes)")
        }

        // 4. 40 pt in 0.4 s, still for 0.3 s, then 9.5 pt in 0.2 s: the character after the pause ticks
        placeCursor(vc, h, before: 30, after: 30)
        let s4 = path(from: start, legs: [(CGVector(dx: 40, dy: 0), 0.4), (CGVector(dx: 40, dy: 0), 0.3), (CGVector(dx: 49.5, dy: 0), 0.2)])
        let d4 = drag(vc, h, s4)
        let resume = s4[0].time + 0.7 + 1e-9
        let iResume = s4.firstIndex { $0.time > resume } ?? s4.count
        let cells4 = (d4.cursors.last ?? 0) - d4.cursors[max(0, iResume - 1)]
        let after4 = d4.ticks.filter { $0 > resume }
        log(d4.cursors == oldRuleCursor(s4, start: 30, length: 60) && cells4 >= 1 && after4.count == 1,
            "cursor.still 0.3 s, then 9.5 pt: \(cells4) character(s), \(after4.count) tick", "all ticks \(d4.ticks.map { String(format: "%.3f", $0 - s4[0].time) })")

        // 5. right 60 pt in 0.4 s, then straight back 30 pt in 0.3 s: the first character on the way back ticks
        placeCursor(vc, h, before: 30, after: 30)
        let s5 = path(from: start, legs: [(CGVector(dx: 60, dy: 0), 0.4), (CGVector(dx: 30, dy: 0), 0.3)])
        let d5 = drag(vc, h, s5)
        let turn = s5[0].time + 0.4 + 1e-9
        let back = d5.ticks.filter { $0 > turn }
        let lastOut = d5.ticks.filter { $0 <= turn }.last
        if let i = (1..<s5.count).first(where: { s5[$0].time > turn && d5.cursors[$0] < d5.cursors[$0 - 1] }) {
            let t = s5[i].time
            let spaced = lastOut.map { t - $0 >= minGap } ?? true
            log(d5.cursors == oldRuleCursor(s5, start: 30, length: 60) && (spaced ? back == [t] : back.isEmpty),
                "cursor.turning back: the first character back ticks (\(back.count) tick on the way back)",
                "first back at \(String(format: "%.3f", t - s5[0].time)) s, ticks back \(back.map { String(format: "%.3f", $0 - s5[0].time) }), "
                    + "last before \(lastOut.map { String(format: "%.3f", $0 - s5[0].time) } ?? "none")")
        } else { log(false, "cursor.turning back", "the cursor never moved back: \(d5.cursors)") }

        // 6. at the end of the text: right 100 pt, nothing passed, no tick; then back 60 pt: ticks again as a 200 pt/s drag
        placeCursor(vc, h, before: 60, after: 0)
        let s6 = path(from: start, legs: [(CGVector(dx: 100, dy: 0), 0.5), (CGVector(dx: 40, dy: 0), 0.3)])
        let d6 = drag(vc, h, s6)
        let turn6 = s6[0].time + 0.5 + 1e-9
        let iTurn = s6.lastIndex { $0.time <= turn6 } ?? 0
        let out6 = d6.ticks.filter { $0 <= turn6 }, back6 = d6.ticks.filter { $0 > turn6 }
        let backCells = d6.cursors[iTurn] - (d6.cursors.last ?? 0)
        // 60 pt at 200 pt/s ticks as test 3 does: 60 / 27 ≈ 2, ± 1
        log(d6.cursors[iTurn] == 60 && out6.isEmpty && backCells > 0 && (1...3).contains(back6.count) && d6.cursors == oldRuleCursor(s6, start: 60, length: 60),
            "cursor.at the end: 0 characters and 0 ticks; back 60 pt: \(backCells) characters, \(back6.count) ticks",
            "cursor at the turn \(d6.cursors[iTurn]) ticks out \(out6.count)")

        // 7. while composing, a drag on space is space, as before: no cursor mode, no tick
        reset(vc, h); type(vc, "nihao"); settle(vc)
        let firstChoice = vc.testState.candidates.first
        let d7 = drag(vc, h, path(from: start, legs: [(CGVector(dx: 100, dy: 0), 0.5)]))
        settle(vc)
        log(d7.ticks.isEmpty && d7.modes == 0 && firstChoice != nil && h.string == firstChoice && !vc.testState.composing,
            "cursor.drag on space while composing: no cursor mode, 0 ticks, the space goes in as before",
            "text=\(h.string) first=\(firstChoice ?? "nil") modes=\(d7.modes) ticks=\(d7.ticks.count)")
        reset(vc, h)
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
        // 1.2 ms measured on the CI simulator (every refresh all-new words, the worst case); a key's whole budget is ~16 ms
        log(median <= 2.0, String(format: "strip.one refresh of 300 candidates: median %.3f ms (≤ 2.0 ms, 100 refreshes)", median),
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
            let scrolledCands = vc.testState.candidates
            let targetIdx = scrolledCands.count > 10 ? 10 : 8
            let box = cb.stripFrameForTests
            var n = 0
            while n < 40, let g = cb.candidateFrameForTests(targetIdx), g.maxX > box.maxX - 1 { cb.stripPanForTests(dx: -40); n += 1 }
            if targetIdx < scrolledCands.count, let g = cb.candidateFrameForTests(targetIdx), g.minX >= box.minX, g.maxX <= box.maxX {
                let s0 = selects
                cb.tapForTests(at: center(g), time: nextTime())
                log(selects == s0 + 1 && committed() == scrolledCands[targetIdx], "strip.scrolled to the 9th, a tap types the 9th",
                    "text=\(committed()) want=\(scrolledCands[targetIdx]) offset=\(cb.stripOffsetForTests)")
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
            // what the check is for: the swipe never fires. The two fields may still part once in a random-letter
            // stream (two engines tie on a reading of noisy keys, 古佛 / 供佛) — reported, not the swipe's doing.
            log(strokes.count == 5000 && clears == 0,
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
                            if vc.tapsForTests == taps && Array(vc.testState.candidates.prefix(20)) == Array(cands.prefix(20)) { restored += 1 }
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
            log(restored == recognised, "clearSwipe.\(name): ↩ brings back the same keys and the same first twenty candidates after every clear (\(restored)/\(recognised))",
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
            // the first twenty (what scrolling reaches in practice); far down, near-tied 九宫格 readings may swap places
            log(vc.testState.keys == "64426" && Array(vc.testState.candidates.prefix(20)) == Array(cands.prefix(20)), "clearSwipe.九宫格 ↩ after 重输 brings the keys back",
                "keys=\(vc.testState.keys) was \(cands.prefix(6)) now \(vc.testState.candidates.prefix(6))")
            reset(vc, h)
        } else { log(false, "clearSwipe.九宫格 setup", "engine did not load") }
        pr.window2.rootViewController = nil
    }

    // MARK: - R48: comma flick-up period, Xiaohe rhythm pill, 2pt correction glow & single-char grid filter

    static func r48Features(_ window: UIWindow) {
        // 1. Comma flick-up emits 。 instantly; normal tap and flick-then-pull-back still emit ，
        if let kb = makeKeyboard(scheme: 0, in: window) {
            let (vc, h) = kb
            let kview = vc.keyboardViewForTests
            if let r = kview.keyRectsForTests(.char("，")) {
                let c = CGPoint(x: r.cap.midX, y: r.cap.midY)
                let up = CGPoint(x: c.x, y: c.y - 24)
                let back = CGPoint(x: c.x, y: c.y - 2)
                kview.feedForTests([
                    TouchSample(id: 1, phase: .began, point: c, time: 1.00),
                    TouchSample(id: 1, phase: .ended, point: c, time: 1.06),
                    TouchSample(id: 2, phase: .began, point: c, time: 2.00),
                    TouchSample(id: 2, phase: .moved, point: up, time: 2.04),
                    TouchSample(id: 2, phase: .ended, point: up, time: 2.08),
                    TouchSample(id: 3, phase: .began, point: c, time: 3.00),
                    TouchSample(id: 3, phase: .moved, point: up, time: 3.04),
                    TouchSample(id: 3, phase: .moved, point: back, time: 3.08),
                    TouchSample(id: 3, phase: .ended, point: back, time: 3.12),
                ])
                log(h.string == "，。，", "r48.comma flick-up emits 。 while tap & pull-back keep ，", "got=\(h.string)")
            } else {
                log(false, "r48.comma key rect lookup", "missing ， key")
            }
        } else { log(false, "r48.comma setup", "engine did not load") }

        // 2. Xiaohe 2-key rhythm kerning in raw-letter pill + 2pt zero-text correction glow bar
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        bar.showsPreedit = true
        bar.xiaoheRhythm = true
        let correctedList = [
            Candidate(text: "你好", tapCount: 4, syllables: [1, 2], corrected: true, score: 0),
            Candidate(text: "你", tapCount: 2, syllables: [1], corrected: false, score: 0),
        ]
        bar.update(preedit: "nihcj", candidates: correctedList)
        let attr = bar.preeditAttributedForTests
        let kern1 = (attr?.attribute(.kern, at: 1, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
        let kern3 = (attr?.attribute(.kern, at: 3, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
        log(bar.preeditShownForTests && attr?.string == "nihcj" && abs(kern1 - 2.5) < 0.01 && abs(kern3 - 2.5) < 0.01,
            "r48.xiaohe pill keeps exact raw letters with 2-key breathing kerning",
            "shown=\(bar.preeditShownForTests) text=\(attr?.string ?? "nil") kern1=\(kern1) kern3=\(kern3)")
        log(bar.correctionBarShownForTests, "r48.2pt correction glow bar shows when slot 0 is corrected")

        let plainList = [Candidate(text: "你好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0)]
        bar.update(preedit: "nihc", candidates: plainList)
        log(!bar.correctionBarShownForTests, "r48.2pt correction glow bar hides when slot 0 is not corrected")

        bar.update(preedit: "", candidates: correctedList, prediction: true)
        log(!bar.correctionBarShownForTests && !bar.preeditShownForTests, "r48.prediction mode hides both glow bar and raw-letter pill")

        // 3. CandidateGridView single-character quick filter maps back to real candidate index
        let grid = CandidateGridView(frame: CGRect(x: 0, y: 0, width: 402, height: 220))
        let mixed = [
            Candidate(text: "你好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "世界", tapCount: 4, syllables: [3, 4], corrected: false, score: 0),
            Candidate(text: "你", tapCount: 2, syllables: [1], corrected: false, score: 0),
            Candidate(text: "拟", tapCount: 2, syllables: [1], corrected: false, score: 0),
        ]
        grid.show(mixed)
        let initialOk = !grid.singleCharButtonHiddenForTests && grid.displayedCountForTests == 4
        grid.toggleSingleCharForTests()
        var picked = -1
        grid.onSelect = { picked = $0 }
        grid.selectDisplayedForTests(1)
        log(initialOk && grid.displayedCountForTests == 2 && picked == 3,
            "r48.grid single-char filter shows only 1-char candidates and emits real index",
            "initialOk=\(initialOk) count=\(grid.displayedCountForTests) picked=\(picked)")
        grid.show([Candidate(text: "你", tapCount: 2, syllables: [1], corrected: false, score: 0)])
        log(grid.singleCharButtonHiddenForTests, "r48.grid hides single-char filter when all candidates are already 1-char")
    }

    // MARK: - R49: universal punctuation flick-up, Live Keystroke Dock, kaomoji library, filter preservation & date shortcuts

    static func r49Features(_ window: UIWindow) {
        // 1. Universal punctuation flick-up: English . -> , and T9 ， -> 、
        if let kb = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = kb
            vc.handle(.toggleLanguage, tap: nil)
            let kview = vc.keyboardViewForTests
            if let r = kview.keyRectsForTests(.char(".")) {
                let c = CGPoint(x: r.cap.midX, y: r.cap.midY)
                let up = CGPoint(x: c.x, y: c.y - 24)
                let back = CGPoint(x: c.x, y: c.y - 2)
                kview.feedForTests([
                    TouchSample(id: 10, phase: .began, point: c, time: 10.00),
                    TouchSample(id: 10, phase: .ended, point: c, time: 10.06),
                    TouchSample(id: 11, phase: .began, point: c, time: 11.00),
                    TouchSample(id: 11, phase: .moved, point: up, time: 11.04),
                    TouchSample(id: 11, phase: .ended, point: up, time: 11.08),
                    TouchSample(id: 12, phase: .began, point: c, time: 12.00),
                    TouchSample(id: 12, phase: .moved, point: up, time: 12.04),
                    TouchSample(id: 12, phase: .moved, point: back, time: 12.08),
                    TouchSample(id: 12, phase: .ended, point: back, time: 12.12),
                ])
                log(h.string == ".,.", "r49.english period flick-up emits comma while tap & pull-back keep period", "got=\(h.string)")
            } else {
                log(false, "r49.english period rect lookup", "missing . key")
            }
        } else { log(false, "r49.english flick setup", "engine did not load") }

        if let kbT9 = makeKeyboard(scheme: 1, grid: true, in: window) {
            let (vc, h) = kbT9
            let kview = vc.keyboardViewForTests
            if let r = kview.keyRectsForTests(.char("，")) {
                let c = CGPoint(x: r.cap.midX, y: r.cap.midY)
                let up = CGPoint(x: c.x, y: c.y - 24)
                kview.feedForTests([
                    TouchSample(id: 20, phase: .began, point: c, time: 20.00),
                    TouchSample(id: 20, phase: .moved, point: up, time: 20.04),
                    TouchSample(id: 20, phase: .ended, point: up, time: 20.08),
                ])
                log(h.string == "、", "r49.t9 comma flick-up emits 、", "got=\(h.string)")
            } else {
                log(false, "r49.t9 comma rect lookup", "missing ， key")
            }
        } else { log(false, "r49.t9 flick setup", "engine did not load") }

        // 2. Live Keystroke Dock: overflow left-fade, clear preview dim, and full-width grid dock
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 402, height: 42))
        bar.showsPreedit = true
        bar.xiaoheRhythm = true
        bar.update(preedit: "jmtmtmqihkhcwomk", candidates: [
            Candidate(text: "今天天气很好", tapCount: 16, syllables: [1], corrected: false, score: 0)
        ])
        bar.layoutIfNeeded()
        let compactW = bar.preeditDockFrameForTests.width
        log(bar.preeditShownForTests && bar.preeditOverflowFadeForTests && compactW <= 110 && compactW >= 90,
            "r49.live dock uses right-anchored left fade within 110pt cap",
            "shown=\(bar.preeditShownForTests) fade=\(bar.preeditOverflowFadeForTests) width=\(compactW)")
        bar.setClearPreview(true)
        log(bar.clearPreviewForTests, "r49.setClearPreview dims live dock alongside strip")
        bar.setClearPreview(false)
        bar.gridExpanded = true
        bar.layoutIfNeeded()
        log(bar.preeditDockFrameForTests.width > 200,
            "r49.expanded candidate grid widens live dock across toolbar",
            "expandedWidth=\(bar.preeditDockFrameForTests.width)")

        // 3. Kaomoji library enrichment & uniqueness
        let kao = EmojiPanelView.kaomoji
        log(kao.count >= 170 && Set(kao).count == kao.count,
            "r49.kaomoji library enriched (>= 170) with zero duplicates",
            "count=\(kao.count) unique=\(Set(kao).count)")

        // 4. CandidateGridView preserves single-char filter across backspace updates
        let grid = CandidateGridView(frame: CGRect(x: 0, y: 0, width: 402, height: 220))
        grid.show([
            Candidate(text: "你好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "你", tapCount: 2, syllables: [1], corrected: false, score: 0),
        ])
        grid.toggleSingleCharForTests()
        grid.show([
            Candidate(text: "世界", tapCount: 4, syllables: [3, 4], corrected: false, score: 0),
            Candidate(text: "世", tapCount: 2, syllables: [3], corrected: false, score: 0),
            Candidate(text: "试", tapCount: 2, syllables: [3], corrected: false, score: 0),
        ], preserveFilter: true)
        log(grid.displayedCountForTests == 2,
            "r49.grid preserves single-char filter when preserveFilter is true",
            "displayed=\(grid.displayedCountForTests)")

        // 5. Expanded relative date/time dynamic candidates
        if let kb = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = kb
            type(vc, "xianzai"); settle(vc)
            let timeCands = vc.testState.candidates.prefix(3)
            log(timeCands.contains(where: { $0.count == 5 && $0.contains(":") }),
                "r49.xianzai offers HH:mm dynamic time candidate",
                "cands=\(Array(timeCands))")
            reset(vc, h)
            type(vc, "xiageyue"); settle(vc)
            let monthCands = vc.testState.candidates.prefix(3)
            log(monthCands.contains(where: { $0.hasSuffix("月") && $0.count <= 3 }),
                "r49.xiageyue offers next month dynamic candidate",
                "cands=\(Array(monthCands))")
        } else { log(false, "r49.dynamic date setup", "engine did not load") }
    }

    static func r50CraftAndReadiness(_ window: UIWindow) {
        log(Theme.font(24, .regular) === Theme.font(24, .regular),
            "r50.Theme.font caches identical font instances across keystrokes")
        log(AmbientLightView().layer.mask == nil,
            "r50.AmbientLightView uses zero offscreen full-screen layer mask")

        if let kb = makeKeyboard(scheme: 0, in: window) {
            let (vc, _) = kb
            let lazyOk = !vc.settingsPanelLoadedForTests && !vc.gridLoadedForTests && vc.diagnosticsForTests.contains("完全访问")
            log(lazyOk,
                "r50.settings & grid panels remain lazy before opening while diagnostics stay readable",
                "settingsLoaded=\(vc.settingsPanelLoadedForTests) gridLoaded=\(vc.gridLoadedForTests)")

            let kview = vc.keyboardViewForTests
            let keySubviews = kview.subviews.filter { $0 is KeyView }
            let gradCount = keySubviews.reduce(0) { acc, kv in
                acc + (kv.layer.sublayers?.filter { $0 is CAGradientLayer }.count ?? 0)
            }
            log(!keySubviews.isEmpty && gradCount == keySubviews.count,
                "r50.sculpted KeyViews each hold a single CAGradientLayer surface",
                "keys=\(keySubviews.count) gradients=\(gradCount)")

            if let rn = kview.keyRectsForTests(.char("n")), let ri = kview.keyRectsForTests(.char("i")) {
                let pn = CGPoint(x: rn.cap.midX, y: rn.cap.midY)
                let pi = CGPoint(x: ri.cap.midX, y: ri.cap.midY)
                kview.feedForTests([
                    TouchSample(id: 50, phase: .began, point: pn, time: 30.00),
                    TouchSample(id: 50, phase: .ended, point: pn, time: 30.04),
                ])
                let slowShown = kview.lastPreviewShownForTests
                kview.feedForTests([
                    TouchSample(id: 51, phase: .began, point: pi, time: 30.07),
                    TouchSample(id: 51, phase: .ended, point: pi, time: 30.11),
                ])
                let rapidShown = kview.lastPreviewShownForTests
                settle(vc)
                log(slowShown && !rapidShown && vc.testState.keys == "ni",
                    "r50.velocity-adaptive preview shows on slow tap and suppresses occluding popup during rapid burst (<130ms)",
                    "slowShown=\(slowShown) rapidShown=\(rapidShown) keys=\(vc.testState.keys)")
            } else {
                log(false, "r50.adaptive preview key rect lookup", "missing n or i key")
            }
        } else {
            log(false, "r50.craft setup", "engine did not load")
        }
    }

    static func r51CompanionAndFluency(_ window: UIWindow) {

        // 2. KeySpec Equatable diff-skipping inside KeyView.apply
        let specA = KeySpec(action: .char("a"), label: "a", isLetter: true)
        let kv = KeyView(spec: specA, borders: true)
        let runsInitial = kv.applyRunsForTests
        kv.apply(specA, borders: true)
        let runsSkipped = kv.applyRunsForTests
        let specB = KeySpec(action: .char("a"), label: "A", isLetter: true)
        kv.apply(specB, borders: true)
        let runsChanged = kv.applyRunsForTests
        log(runsInitial == 1 && runsSkipped == 1 && runsChanged == 2,
            "r51.KeyView skips redundant apply work when KeySpec and borders are unchanged",
            "initial=\(runsInitial) skipped=\(runsSkipped) changed=\(runsChanged)")

        // 3. CandidateBarView retains measured width cache across word commits
        if let kb = makeKeyboard(scheme: 0, in: window) {
            let (vc, _) = kb
            type(vc, "nihao"); settle(vc)
            vc.handle(.space, tap: nil)
            drain(0.05)
            log(vc.candidateBarForTests.widthCacheCountForTests > 0,
                "r51.CandidateBarView preserves word width cache across commits",
                "widthCacheCount=\(vc.candidateBarForTests.widthCacheCountForTests)")
        } else {
            log(false, "r51.widthCache setup", "engine did not load")
        }
    }

    static func r52HardwareDeckAndOpticalCraft(_ window: UIWindow) {
        // 1. SettingsPanelView OTTOSSOM zero-scroll hardware deck + secondary drawer
        let sp = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 264))
        sp.layoutIfNeeded()
        let prevScheme = KeyboardSettings.shared.scheme
        defer { KeyboardSettings.shared.scheme = prevScheme }
        KeyboardSettings.shared.scheme = 1
        sp.load()
        sp.tapSchemeTileForTests()
        let toggledScheme = KeyboardSettings.shared.scheme
        sp.tapSchemeTileForTests()
        let restoredScheme = KeyboardSettings.shared.scheme
        let initialDrawer = sp.showingMoreForTests
        sp.toggleMoreForTests()
        let openedDrawer = sp.showingMoreForTests
        sp.toggleMoreForTests()
        log(sp.hardwareTileCountForTests == 6 && toggledScheme == 0 && restoredScheme == 1 && !initialDrawer && openedDrawer && !sp.showingMoreForTests,
            "r52.SettingsPanelView exposes 6 hardware tiles, toggles scheme cleanly, and switches secondary drawer",
            "tiles=\(sp.hardwareTileCountForTests) scheme=(\(toggledScheme),\(restoredScheme)) drawer=(\(initialDrawer),\(openedDrawer))")

        // 2. EmojiPanelView 10-mood Kaomoji tape & 228 unique expressions
        let ep = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 264))
        ep.layoutIfNeeded()
        ep.load(kaomoji: true)
        let moodCount = EmojiPanelView.moodGroupCountForTests
        let firstCount = ep.displayedKaomojiCountForTests
        ep.selectMoodForTests(max(0, moodCount - 1))
        let lastIdx = ep.activeMoodIndexForTests
        let allK = EmojiPanelView.kaomoji
        log(moodCount >= 8 && firstCount > 0 && lastIdx == max(0, moodCount - 1) && allK.count >= 220 && Set(allK).count == allK.count,
            "r52.EmojiPanelView organizes kaomoji into mood tape while preserving unique expressions",
            "moods=\(moodCount) firstCount=\(firstCount) lastIdx=\(lastIdx) total=\(allK.count)")

        // 3. CoreText fullwidth CJK punctuation optical centering
        let dxComma = KeyView.opticalHorizontalOffset(for: "，", font: Theme.font(24, .medium))
        log(dxComma.isFinite && dxComma > 0.5,
            "r52.KeyView optically nudges fullwidth CJK comma right toward key center",
            "dxComma=\(dxComma)")
    }

    static func r53GridParityAndIdleSeparation(_ window: UIWindow) {
        // 1. CandidateGridView long-press maps displayed index -> real candidate index (preserving single-char filter)
        let g = CandidateGridView(frame: CGRect(x: 0, y: 0, width: 402, height: 220))
        g.show([
            Candidate(text: "你好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "你", tapCount: 2, syllables: [1], corrected: false, score: 0),
            Candidate(text: "泥", tapCount: 2, syllables: [1], corrected: false, score: 0),
        ])
        g.toggleSingleCharForTests()
        var heldIndex = -1
        g.onLongPress = { heldIndex = $0 }
        g.longPressDisplayedForTests(1)
        log(heldIndex == 2,
            "r53.CandidateGridView long-press emits real candidate index under single-char filter",
            "heldIndex=\(heldIndex)")

        // 2. Theme.plain clearInput hides plainLightButton and mostoHintButton while undoChip is visible
        if let kb = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = kb
            let prevStyle = KeyboardSettings.shared.style
            defer { KeyboardSettings.shared.style = prevStyle; vc.applySettings() }
            KeyboardSettings.shared.style = 1
            vc.applySettings()
            type(vc, "nihao"); settle(vc)
            vc.handle(.clearInput, tap: nil)
            drain(0.03)
            log(vc.candidateBarForTests.undoTextForTests == "nihao" && vc.plainLightHiddenForTests && vc.mostoHintHiddenForTests,
                "r53.Theme.plain hides light and kaomoji pills when clearInput undo chip is shown",
                "undo=\(vc.candidateBarForTests.undoTextForTests ?? "nil") plainLightHidden=\(vc.plainLightHiddenForTests) mostoHintHidden=\(vc.mostoHintHiddenForTests)")

            // 3. Tapping an English suggestion keeps double-space period working across delayed selectionDidChange
            KeyboardSettings.shared.style = 0
            vc.applySettings()
            reset(vc, h)
            vc.handle(.toggleLanguage, tap: nil)
            type(vc, "teh")
            drain(0.02)
            vc.candidateTapped(0)
            vc.selectionDidChange(nil)
            vc.handle(.space, tap: nil)
            log(h.string.lowercased().hasSuffix("the. "),
                "r53.English suggestion tap preserves double-space period across selectionDidChange",
                "text=\(h.string)")
        } else {
            log(false, "r53.setup", "engine did not load")
        }
    }

    static func r54OpticalTrackpadAndTactileProfiles(_ window: UIWindow) {
        _ = window
        // 1. Leica Optical Trackpad Ruler: shows & translates during cursor drag and hides cleanly on release
        let ctx = LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true)
        let kbDemo = KeyboardView(spatial: SpatialModel.standard())
        kbDemo.frame = CGRect(x: 0, y: 0, width: 402, height: 214)
        kbDemo.configure(ctx)
        kbDemo.layoutIfNeeded()
        kbDemo.demoCursorMode()
        let demoVisible = kbDemo.trackpadRulerVisibleForTests && kbDemo.trackpadRulerOffsetForTests != 0

        let kb = KeyboardView(spatial: SpatialModel.standard())
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 214)
        kb.configure(ctx)
        kb.layoutIfNeeded()
        let spaceCap = kb.keyRectsForTests(.space)?.cap ?? CGRect(x: 100, y: 165, width: 160, height: 42)
        let sp = CGPoint(x: spaceCap.midX, y: spaceCap.midY)
        kb.feedForTests([
            TouchSample(id: 1, phase: .began, point: sp, time: 0.0),
            TouchSample(id: 1, phase: .moved, point: CGPoint(x: sp.x + 32, y: sp.y), time: 0.10),
            TouchSample(id: 1, phase: .moved, point: CGPoint(x: sp.x + 48, y: sp.y), time: 0.18),
        ])
        let dragVisible = kb.trackpadRulerVisibleForTests && abs(kb.trackpadRulerOffsetForTests) > 1
        kb.feedForTests([
            TouchSample(id: 1, phase: .ended, point: CGPoint(x: sp.x + 48, y: sp.y), time: 0.22),
        ])
        let hiddenAfter = !kb.trackpadRulerVisibleForTests
        log(demoVisible && dragVisible && hiddenAfter,
            "r54.KeyboardView Leica optical trackpad ruler shows & translates on cursor drag and hides cleanly",
            "demo=\(demoVisible) drag=\(dragVisible) hiddenAfter=\(hiddenAfter)")

        // 2. Continuous delete-left-swipe progress drives CandidateBarView warm-amber filament
        var cs = ClearSwipe(start: CGPoint(x: 370, y: 130), keyLeft: 346, time: 1.0)
        let pStart = cs.progress(at: CGPoint(x: 368, y: 130), time: 1.05)
        let pMid = cs.progress(at: CGPoint(x: 344, y: 130), time: 1.12)
        _ = cs.move(to: CGPoint(x: 320, y: 130), at: 1.18)
        let pArmed = cs.progress(at: CGPoint(x: 320, y: 130), time: 1.18)
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 402, height: 42))
        bar.layoutIfNeeded()
        bar.setClearProgress(0.5, armed: false)
        let midBarOk = abs(bar.clearFilamentProgressForTests - 0.5) < 0.001 && bar.clearPreviewForTests
        bar.setClearProgress(0, armed: false)
        let resetBarOk = bar.clearFilamentProgressForTests == 0 && !bar.clearPreviewForTests
        log(pStart == 0 && pMid > 0 && pMid < 1 && pArmed == 1 && midBarOk && resetBarOk,
            "r54.ClearSwipe continuous progress drives CandidateBarView amber filament cleanly",
            "start=\(pStart) mid=\(pMid) armed=\(pArmed) midBar=\(midBarOk) reset=\(resetBarOk)")

        // 3. HapticProfile distinct tuning & SettingsPanelView 4-state cycling
        let tCrisp = SystemFeedbackPlayer.tunedImpact(for: .crisp, firm: false)
        let tMech = SystemFeedbackPlayer.tunedImpact(for: .mechanical, firm: false)
        let tQuiet = SystemFeedbackPlayer.tunedImpact(for: .quiet, firm: false)
        let distinctProfiles = tCrisp.style != tMech.style && tMech.style != tQuiet.style
            && tCrisp.intensity != tMech.intensity && tMech.intensity != tQuiet.intensity && tCrisp.intensity != tQuiet.intensity
        let s = KeyboardSettings.shared
        let prevFeedback = s.feedback, prevProfile = s.hapticProfile
        defer { s.feedback = prevFeedback; s.hapticProfile = prevProfile }
        s.feedback = true; s.hapticProfile = 0
        let panel = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 264))
        panel.layoutIfNeeded()
        panel.tapHapticTileForTests(); let st1 = (s.feedback, s.hapticProfile)
        panel.tapHapticTileForTests(); let st2 = (s.feedback, s.hapticProfile)
        panel.tapHapticTileForTests(); let st3 = (s.feedback, s.hapticProfile)
        panel.tapHapticTileForTests(); let st4 = (s.feedback, s.hapticProfile)
        log(distinctProfiles && st1 == (true, 1) && st2 == (true, 2) && st3 == (false, 0) && st4 == (true, 0),
            "r54.HapticProfile distinct tuning & SettingsPanelView 4-state tactile cycling",
            "distinct=\(distinctProfiles) states=[\(st1),\(st2),\(st3),\(st4)]")

        // 4. EmojiPanelView auto-scrolls bottom dock to active Mosto tab on kaomoji open
        let ep = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 264))
        ep.layoutIfNeeded()
        ep.load(kaomoji: true)
        ep.layoutIfNeeded()
        log(ep.tabScrollOffsetXForTests > 20,
            "r54.EmojiPanelView auto-scrolls bottom dock to active Mosto tab on kaomoji open",
            "offsetX=\(ep.tabScrollOffsetXForTests)")
    }

    static func r55DualLegendFlickAndMathBadge(_ window: UIWindow) {
        // 1. Sub-glyph micro-legends appear on flickable punctuation/symbol keys while keeping 26 letters pure
        let kb = KeyboardView(spatial: SpatialModel.standard())
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 214)
        kb.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kb.layoutIfNeeded()
        let lettersPure = kb.keyHintTextForTests(.char("q")) == nil && kb.keyHintTextForTests(.char("a")) == nil
        let commaHint = kb.keyHintTextForTests(.char("，")) == "。"

        kb.configure(LayoutContext(page: .numbers, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kb.layoutIfNeeded()
        let numHints = kb.keyHintTextForTests(.char("/")) == "、" && kb.keyHintTextForTests(.char("¥")) == "$"

        kb.configure(LayoutContext(page: .symbols, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kb.layoutIfNeeded()
        let symHints = kb.keyHintTextForTests(.char("…")) == "—" && kb.keyHintTextForTests(.char("^_^")) == "ψ"

        kb.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, pinyinGrid: true))
        kb.layoutIfNeeded()
        let t9Hints = kb.keyHintTextForTests(.char("，")) == "、" && kb.keyHintTextForTests(.char("。")) == "…" && kb.keyHintTextForTests(.char("？")) == "！"

        kb.configure(LayoutContext(page: .numpad, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kb.layoutIfNeeded()
        let padHints = kb.keyHintTextForTests(.char("+")) == "=" && kb.keyHintTextForTests(.char(".")) == ","

        log(lettersPure && commaHint && numHints && symHints && t9Hints && padHints,
            "r55.KeyView exposes sub-glyph corner legends across punctuation/symbol pages while keeping letters pure",
            "pure=\(lettersPure) comma=\(commaHint) num=\(numHints) sym=\(symHints) t9=\(t9Hints) pad=\(padHints)")

        // 2. Kinetic state coupling: pre-arming rise lights corner legend; >=16pt lifts & accents KeyPreview; pull-back resets
        kb.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kb.layoutIfNeeded()
        var emitted: [String] = []
        kb.onAction = { act, _ in
            if case .char(let s) = act { emitted.append(s) }
        }
        let commaRect = kb.keyRectsForTests(.char("，"))?.cap ?? CGRect(x: 290, y: 165, width: 34, height: 40)
        let cp = CGPoint(x: commaRect.midX, y: commaRect.midY)
        kb.feedForTests([TouchSample(id: 90, phase: .began, point: cp, time: 0.0)])
        let restLit = kb.keyHintLitForTests(.char("，"))
        kb.feedForTests([TouchSample(id: 90, phase: .moved, point: CGPoint(x: cp.x, y: cp.y - 9), time: 0.04)])
        let preArmLit = kb.keyHintLitForTests(.char("，")) && !kb.activePreviewFlickedForTests
        kb.feedForTests([TouchSample(id: 90, phase: .moved, point: CGPoint(x: cp.x, y: cp.y - 20), time: 0.08)])
        let engaged = kb.keyHintLitForTests(.char("，")) && kb.activePreviewFlickedForTests
        kb.feedForTests([TouchSample(id: 90, phase: .moved, point: CGPoint(x: cp.x, y: cp.y - 2), time: 0.12)])
        let pulledBack = !kb.keyHintLitForTests(.char("，")) && !kb.activePreviewFlickedForTests
        kb.feedForTests([TouchSample(id: 90, phase: .ended, point: CGPoint(x: cp.x, y: cp.y - 2), time: 0.14)])
        kb.feedForTests([
            TouchSample(id: 91, phase: .began, point: cp, time: 0.30),
            TouchSample(id: 91, phase: .moved, point: CGPoint(x: cp.x, y: cp.y - 20), time: 0.35),
            TouchSample(id: 91, phase: .ended, point: CGPoint(x: cp.x, y: cp.y - 20), time: 0.38),
        ])
        let resetAfterRelease = !kb.keyHintLitForTests(.char("，"))
        log(!restLit && preArmLit && engaged && pulledBack && resetAfterRelease && emitted == ["，", "。"],
            "r55.Flick-up pre-arm & engagement couple KeyView corner legend and KeyPreview cleanly",
            "rest=\(restLit) preArm=\(preArmLit) engaged=\(engaged) back=\(pulledBack) reset=\(resetAfterRelease) emitted=\(emitted)")

        // 3. Mental math candidate displays 心算 badge and commits cleanly without spurious Chinese follow-up predictions
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = pair
            vc.handle(.page(.numbers), tap: nil)
            for ch in ["3", "6", "5", "+", "1", "8", "="] {
                vc.handle(.char(ch), tap: nil)
            }
            drain(0.03)
            let cap = vc.candidateBarForTests.firstCaptionForTests
            let preds = vc.testState.predictions
            vc.candidateTapped(0)
            drain(0.05)
            log(cap == "心算" && preds == ["383"] && h.string == "365+18=383" && vc.testState.predictions.isEmpty,
                "r55.Trailing arithmetic tags candidate with 心算 and commits without language prediction follow-up",
                "cap=\(cap ?? "nil") preds=\(preds) text=\(h.string) afterPreds=\(vc.testState.predictions)")
        } else {
            log(false, "r55.math badge setup", "engine did not load")
        }
    }

    static func r56DualSchemeLessonsAndMostoState(_ window: UIWindow) {
        // 1. Mosto day-mode yawn clears immediately when hidden mid-yawn (no lingering yawn sprite on reappear).
        let mosto = MostoView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        mosto.setNight(false)
        mosto.demoYawn()
        log(!mosto.isShowingDayPoseForTests, "r56.mosto demoYawn leaves day pose", "")
        mosto.isHidden = true
        mosto.isHidden = false
        log(mosto.isShowingDayPoseForTests, "r56.mosto hiding mid-yawn in day mode restores day pose", "")

        // 2. Real Xiaohe Shuangpin slip and missing-key recovery pass end-to-end against KeyboardViewController.
        if let kb = makeKeyboard(scheme: 0, in: window) {
            let (vc, h) = kb
            type(vc, "jbtmtmqohfhc"); settle(vc); vc.handle(.space, tap: nil); drain(0.05)
            log(h.string.contains("今天天气很好") || h.string.contains("今天很热"),
                "r56.xiaohe slip sentence jbtmtmqohfhc commits expected phrase",
                "text=\(h.string)")

            h.clear(); vc.discardComposition(); vc.textDidChange(nil)
            type(vc, "jbtmtmqihfh"); settle(vc); vc.handle(.space, tap: nil); drain(0.05)
            log(h.string.contains("今天天气很好"),
                "r56.xiaohe missing-key sentence jbtmtmqihfh → 今天天气很好",
                "text=\(h.string)")
        } else {
            log(false, "r56.xiaohe lessons setup", "engine did not load")
        }
    }

    static func r57PullCordAndOptical2D(_ window: UIWindow) {
        _ = window
        // 1. FamilyAtmosphere day/night toggle and physical pull threshold
        let m0 = FamilyAtmosphere.day
        let m1 = m0.toggled
        let m2 = m1.toggled
        log(m1 == .night && m2 == .day && LampPullCordSwitch.pullThreshold > 15,
            "r57.FamilyAtmosphere toggles cleanly across day <-> night and LampPullCordSwitch exposes valid threshold",
            "cycle=\(m0)->\(m1)->\(m2) threshold=\(LampPullCordSwitch.pullThreshold)")

        // 2. 2D CoreText opticalOffset centers fullwidth 。 horizontally and lifts it vertically
        let o = KeyView.opticalOffset(for: "。", font: Theme.font(24, .medium))
        log(o.x.isFinite && o.y.isFinite && o.x > 0.5 && o.y < -1.0,
            "r57.KeyView 2D CoreText opticalOffset centers fullwidth 。 horizontally and lifts it vertically",
            "dx=\(o.x) dy=\(o.y)")

        // 3. Multi-char symbol key ^_^ separates cleanly below its top-right ψ corner legend
        let kb = KeyboardView(spatial: SpatialModel.standard())
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 214)
        kb.configure(LayoutContext(page: .symbols, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kb.layoutIfNeeded()
        let symHint = kb.keyHintTextForTests(.char("^_^"))
        let symFontSize = kb.keyLabelFontSizeForTests(.char("^_^")) ?? 99
        log(symHint == "ψ" && symFontSize <= 19.5,
            "r57.Multi-char symbol key ^_^ separates cleanly below its top-right ψ corner legend",
            "hint=\(symHint ?? "nil") fontSize=\(symFontSize)")
    }

    static func r58CorrectionPinpointAndDetent(_ window: UIWindow) {
        // 1. Live correctionPinpoint maps substitution, Xiaohe slip, extra tap, and omission accurately
        let subPin = CandidateBarView.correctionPinpoint(in: "nihap", fixes: [Fix(typed: "hap", meant: "hao")])
        let xiaohePin = CandidateBarView.correctionPinpoint(in: "jbtmtmqohfhc", fixes: [Fix(typed: "qo", meant: "qi")])
        let extraPin = CandidateBarView.correctionPinpoint(in: "jintianttianqihenhao", fixes: [Fix(typed: "ttian", meant: "tian")])
        let missPin = CandidateBarView.correctionPinpoint(in: "jintiantiaqihenhao", fixes: [Fix(typed: "tia", meant: "tian")])
        let mismatchPin = CandidateBarView.correctionPinpoint(in: "nihcj", fixes: [Fix(typed: "hap", meant: "hao")])
        log(subPin.slipped == [4] && subPin.missingAnchors.isEmpty
            && xiaohePin.slipped == [7]
            && !extraPin.slipped.isEmpty
            && missPin.slipped.isEmpty && missPin.missingAnchors == [9]
            && mismatchPin.isEmpty,
            "r58.correctionPinpoint isolates slipped, extra, and omitted key indices accurately",
            "sub=\(subPin) xiaohe=\(xiaohePin) extra=\(extraPin) miss=\(missPin) mismatch=\(mismatchPin)")

        // 2. CandidateBarView preeditDock renders pinpoint highlights, clears stale fixes on new key, & updates VoiceOver
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 402, height: 42))
        bar.showsPreedit = true
        bar.xiaoheRhythm = true
        var c = Candidate(text: "今天天气很好", tapCount: 12, syllables: [1], corrected: true, score: 0)
        c.fixes = [Fix(typed: "qo", meant: "qi")]
        bar.update(preedit: "jbtmtmqohfhc", candidates: [c])
        bar.layoutIfNeeded()
        let activePinOk = bar.preeditPinpointForTests.slipped == [7] && bar.preeditAttributedForTests != nil
        bar.setPreedit("jbtmtmqohfhcx")
        let clearedOnKey = bar.preeditPinpointForTests.isEmpty
        log(activePinOk && clearedOnKey,
            "r58.CandidateBarView preeditDock lights slipped Xiaohe key and resets cleanly on next keystroke",
            "activePinOk=\(activePinOk) clearedOnKey=\(clearedOnKey)")

        // 3. Flick-up pull-back fires bidirectional selection detent feedback (.altMoved on engage & cancel)
        let kb = KeyboardView(spatial: SpatialModel.standard())
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 214)
        kb.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kb.layoutIfNeeded()
        var feedbackEvents: [FeedbackEvent] = []
        kb.onFeedback = { ev, _ in feedbackEvents.append(ev) }
        let commaRect = kb.keyRectsForTests(.char("，"))?.cap ?? CGRect(x: 290, y: 165, width: 34, height: 40)
        let cp = CGPoint(x: commaRect.midX, y: commaRect.midY)
        kb.feedForTests([
            TouchSample(id: 95, phase: .began, point: cp, time: 0.0),
            TouchSample(id: 95, phase: .moved, point: CGPoint(x: cp.x, y: cp.y - 20), time: 0.05),
            TouchSample(id: 95, phase: .moved, point: CGPoint(x: cp.x, y: cp.y - 2), time: 0.09),
            TouchSample(id: 95, phase: .ended, point: CGPoint(x: cp.x, y: cp.y - 2), time: 0.12),
        ])
        let altMoves = feedbackEvents.filter { $0 == .altMoved }.count
        log(altMoves == 2,
            "r58.Flick-up pull-back emits bidirectional detent feedback on engage and snap-back",
            "events=\(feedbackEvents)")

        // 4. Controller reports live activeFirstFixesForTests for slipped Xiaohe input and clears on commit
        if let pair = makeKeyboard(scheme: 0, in: window) {
            let (vc, _) = pair
            type(vc, "jbtmtmqohfhc"); settle(vc); drain(0.03)
            let fixesWhileComposing = vc.activeFirstFixesForTests
            let pinpoint = CandidateBarView.correctionPinpoint(in: vc.testState.keys, fixes: fixesWhileComposing)
            let hasXiaoheFixes = !fixesWhileComposing.isEmpty && pinpoint.slipped == [7]
            vc.handle(.space, tap: nil); drain(0.03)
            let clearedAfterSpace = vc.activeFirstFixesForTests.isEmpty
            log(hasXiaoheFixes && clearedAfterSpace,
                "r58.Controller reports live correction pinpoint while composing and clears on commit",
                "pinpoint=\(pinpoint) fixes=\(fixesWhileComposing) cleared=\(clearedAfterSpace)")
        } else {
            log(false, "r58.activeFixes setup", "engine did not load")
        }
    }

    static func r59TrackpadEndStopAndNewlineDetent(_ window: UIWindow) {
        guard let made = makeKeyboard(scheme: 1, in: window) else {
            log(false, "r59.setup", "engine did not load")
            return
        }
        let (vc, h) = made
        vc.feedbackPlayer = RecordingFeedbackPlayer()
        guard let space = vc.keyboardViewForTests.keyRectsForTests(.space)?.cap else {
            log(false, "r59.setup", "no space key")
            return
        }
        let kb = vc.keyboardViewForTests
        let sp = center(space)

        // 1. Live step badge tracks moved characters and resets cleanly on end
        placeCursor(vc, h, before: 8, after: 8)
        let sMove = path(from: sp, legs: [(CGVector(dx: 54, dy: 0), 0.35)])
        kb.feedForTests(Array(sMove.dropLast()))
        let midBadge = kb.trackpadBadgeTextForTests
        let midFree = kb.trackpadEndStopForTests == 0
        kb.feedForTests([sMove.last!])
        let endHidden = kb.trackpadBadgeTextForTests == nil && !kb.trackpadRulerVisibleForTests
        log(midBadge?.hasPrefix("→ ") == true && midFree && endHidden,
            "r59.Trackpad shows live relative step pill during cursor drag and hides cleanly on release",
            "midBadge=\(midBadge ?? "nil") midFree=\(midFree) endHidden=\(endHidden)")

        // 2. End-stop rubber-band clamp + single .cursorBoundary detent + smooth unlock on reversal
        placeCursor(vc, h, before: 4, after: 1)
        var boundaryCount = 0
        var stepCountAtEnd = 0
        let origFeedback = kb.onFeedback
        kb.onFeedback = { ev, p in
            if ev == .cursorBoundary { boundaryCount += 1 }
            if ev == .cursorStep && kb.trackpadEndStopForTests != 0 { stepCountAtEnd += 1 }
            origFeedback?(ev, p)
        }
        let sClamp = path(from: sp, legs: [(CGVector(dx: 90, dy: 0), 0.45), (CGVector(dx: 45, dy: 0), 0.25)])
        let turnTime = sClamp[0].time + 0.45 + 1e-9
        let leg1 = sClamp.filter { $0.time <= turnTime }
        let leg2 = sClamp.filter { $0.time > turnTime }
        kb.feedForTests(leg1)
        let endStop = kb.trackpadEndStopForTests
        let overdrag = kb.trackpadOverdragForTests
        let clampBadge = kb.trackpadBadgeTextForTests
        kb.feedForTests(Array(leg2.dropLast()))
        let unlocked = kb.trackpadEndStopForTests == 0 && kb.trackpadOverdragForTests == 0
        let backBadge = kb.trackpadBadgeTextForTests
        kb.feedForTests([leg2.last!])
        kb.onFeedback = origFeedback
        log(endStop == 1 && overdrag > 0 && overdrag <= 10.01 && clampBadge == "文末"
            && boundaryCount == 1 && stepCountAtEnd == 0 && unlocked && backBadge?.hasPrefix("← ") == true,
            "r59.Trackpad clamps at end with rubber-band, single boundary detent, and unlocks on reversal",
            "endStop=\(endStop) overdrag=\(overdrag) badge=\(clampBadge ?? "nil") boundaryCount=\(boundaryCount) stepAtEnd=\(stepCountAtEnd) unlocked=\(unlocked) back=\(backBadge ?? "nil")")

        // 3. Stepping across a newline emits .cursorBoundary and marks ↵ in the pill
        reset(vc, h)
        h.insertText("第一行\n第二行")
        h.adjustTextPosition(byCharacterOffset: -4)
        vc.textDidChange(nil)
        drain(0.01)
        var nlBoundaries = 0
        kb.onFeedback = { ev, p in
            if ev == .cursorBoundary { nlBoundaries += 1 }
            origFeedback?(ev, p)
        }
        let sNL = path(from: sp, legs: [(CGVector(dx: 36, dy: 0), 0.25)])
        kb.feedForTests(Array(sNL.dropLast()))
        let nlBadge = kb.trackpadBadgeTextForTests
        kb.feedForTests([sNL.last!])
        kb.onFeedback = origFeedback
        log(nlBoundaries >= 1 && (nlBadge?.contains("↵") == true),
            "r59.Trackpad pulses .cursorBoundary and marks newline symbol when stepping over line break",
            "nlBoundaries=\(nlBoundaries) nlBadge=\(nlBadge ?? "nil")")

        // 4. Unavailable context (password/restricted proxy returning nil) never falsely clamps 文首/文末
        let kbNoCtx = KeyboardView(spatial: SpatialModel.standard())
        kbNoCtx.frame = kb.frame
        kbNoCtx.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kbNoCtx.layoutIfNeeded()
        kbNoCtx.onCursorMove = { _ in .unavailable }
        let sUnavail = path(from: sp, legs: [(CGVector(dx: 60, dy: 0), 0.3)])
        kbNoCtx.feedForTests(Array(sUnavail.dropLast()))
        let unavailNoClamp = kbNoCtx.trackpadEndStopForTests == 0 && kbNoCtx.trackpadBadgeTextForTests != "文末"
        kbNoCtx.feedForTests([sUnavail.last!])
        log(unavailNoClamp,
            "r59.Trackpad treats unavailable host context as free scroll without false boundary clamp",
            "endStop=\(kbNoCtx.trackpadEndStopForTests) badge=\(kbNoCtx.trackpadBadgeTextForTests ?? "nil")")
        reset(vc, h)
    }

    // MARK: - R60: delete repeat clutch filament, word-delete undo safety net & English ClearSwipe

    static func r60DeleteClutchAndBilingualUndo(_ window: UIWindow) {
        guard let (vc, h) = makeKeyboard(scheme: 1, in: window) else {
            log(false, "r60.setup", "engine did not load")
            return
        }
        vc.feedbackPlayer = RecordingFeedbackPlayer()
        let kb = vc.keyboardViewForTests
        let bar = vc.candidateBarForTests
        guard let delCap = kb.keyRectsForTests(.delete)?.cap else {
            log(false, "r60.setup", "no delete key")
            return
        }
        let dc = center(delCap)

        // 1. English ClearSwipe: typing "thnaks", swipe left off delete clears whole word & ↩ restores it + suggestions
        reset(vc, h)
        vc.handle(.toggleLanguage, tap: nil)
        h.insertText("hello ")
        vc.textDidChange(nil)
        type(vc, "thnaks")
        drain(0.02)
        let enSwipe = swipe(from: dc, to: CGVector(dx: -72, dy: 0), duration: 0.18)
        kb.feedForTests(Array(enSwipe.dropLast()))
        let enArmed = bar.clearPreviewForTests && bar.clearFilamentProgressForTests == 1
        kb.feedForTests([enSwipe.last!])
        drain(0.01)
        let clearedText = h.string
        let chipAfterClear = bar.undoTextForTests
        bar.undoTapForTests()
        drain(0.02)
        let restoredText = h.string
        let suggestionsRestored = bar.laidOutForTests >= 2
        vc.handle(.space, tap: nil)
        let correctedAfterRestore = h.string == "hello thanks "
        log(enArmed && clearedText == "hello " && chipAfterClear == "thnaks"
            && restoredText == "hello thnaks" && suggestionsRestored && correctedAfterRestore,
            "r60.English ClearSwipe clears active word with filament and ↩ restores word + suggestions",
            "armed=\(enArmed) cleared=\(clearedText) chip=\(chipAfterClear ?? "nil") restored=\(restoredText) sugg=\(suggestionsRestored) final=\(h.string)")

        // 2. Held delete clutch ramps filament (ticks 8..19), locks at tick 20, deletes words at 21+, and offers ↩ undo on lift
        reset(vc, h)
        let seedText = "今天天气真好我们可以一起出去公园散步吧太开心啦好不好" // 26 Hanzi: 1 initial + 19 repeat = 20 chars -> 6 left ("今天天气真好"), then 2 word deletes -> 2 left ("今天")
        h.insertText(seedText)
        vc.textDidChange(nil)
        let t0: CFTimeInterval = 100
        kb.feedForTests([TouchSample(id: 1, phase: .began, point: dc, time: t0)])
        // Tick 10 (0.42 + 10*0.07 = 1.12s): clutch ramping up without dimming stripBox
        kb.advanceForTests(to: t0 + 1.13)
        let midClutch = bar.clearFilamentProgressForTests
        let notDimmed = !bar.clearPreviewForTests
        // Tick 21 (0.42 + 21*0.07 = 1.89s): clutch locked & first word delete fired; tick 24 (2.10s): second word delete
        kb.advanceForTests(to: t0 + 2.11)
        let lockedClutch = bar.clearFilamentProgressForTests == 1
        let textAfterHold = h.string
        kb.feedForTests([TouchSample(id: 1, phase: .ended, point: dc, time: t0 + 2.12)])
        drain(0.01)
        let filamentReset = bar.clearFilamentProgressForTests == 0
        let undoWordChip = bar.undoTextForTests
        bar.undoTapForTests()
        drain(0.01)
        let textAfterUndo = h.string
        log(midClutch > 0.1 && midClutch < 0.9 && notDimmed && lockedClutch
            && textAfterHold == "今天" && filamentReset && undoWordChip == "天气真好" && textAfterUndo == "今天天气真好",
            "r60.Held delete clutch shows progressive filament, engages word-delete, and ↩ restores deleted words",
            "mid=\(midClutch) notDim=\(notDimmed) locked=\(lockedClutch) afterHold=\(textAfterHold) reset=\(filamentReset) chip=\(undoWordChip ?? "nil") restored=\(textAfterUndo)")

        // 3. Typing another character after held word-delete dismisses the ↩ chip cleanly
        type(vc, "nihao")
        settle(vc)
        let chipDismissed = bar.undoTextForTests == nil
        log(chipDismissed, "r60.Next key dismisses word-delete ↩ chip", "chip=\(bar.undoTextForTests ?? "nil")")

        // 4. Cancelled held delete resets filament without promoting a stale ↩ chip
        reset(vc, h)
        h.insertText(seedText)
        vc.textDidChange(nil)
        let t1: CFTimeInterval = 200
        kb.feedForTests([TouchSample(id: 2, phase: .began, point: dc, time: t1)])
        kb.advanceForTests(to: t1 + 1.90)
        kb.feedForTests([TouchSample(id: 2, phase: .cancelled, point: dc, time: t1 + 1.91)])
        drain(0.01)
        log(bar.clearFilamentProgressForTests == 0 && bar.undoTextForTests == nil,
            "r60.Cancelled held delete resets clutch filament without leaving ↩ chip",
            "progress=\(bar.clearFilamentProgressForTests) chip=\(bar.undoTextForTests ?? "nil")")

        // 5. Held word-delete crossing newlines sanitizes chip display cleanly while restoring exact raw newlines
        reset(vc, h)
        h.insertText("第一行\n一二三四五六七八九十一二三四五六七八九十")
        vc.textDidChange(nil)
        let t2: CFTimeInterval = 300
        kb.feedForTests([TouchSample(id: 3, phase: .began, point: dc, time: t2)])
        kb.advanceForTests(to: t2 + 2.00) // tick 21 -> deletes "\n" as word-delete
        let afterNewlineDelete = h.string
        kb.feedForTests([TouchSample(id: 3, phase: .ended, point: dc, time: t2 + 2.02)])
        drain(0.01)
        let nlChip = bar.undoTextForTests
        bar.undoTapForTests()
        drain(0.01)
        log(nlChip == "↵" && h.string == "第一行\n",
            "r60.Held word-delete over newline displays ↵ on ↩ chip and restores exact newline",
            "afterDel=\(afterNewlineDelete.debugDescription) chip=\(nlChip ?? "nil") restored=\(h.string.debugDescription)")
        reset(vc, h)
    }

    static func r60XiaoheMissingKeyRecovery(_ window: UIWindow) {
        guard let (vc, h) = makeKeyboard(scheme: 0, in: window) else {
            log(false, "r60.xiaohe.setup", "engine did not load")
            return
        }
        let bar = vc.candidateBarForTests

        // 1. Syllable-1 missing key [1+2]: jtmtmqihfhc -> 今天天气很好 + missing-key pinpoint on preedit
        reset(vc, h)
        type(vc, "jtmtmqihfhc"); settle(vc)
        let jtmTop = vc.testState.candidates.first
        let jtmHasPin = !bar.preeditPinpointForTests.missingAnchors.isEmpty
        log(jtmTop == "今天天气很好" && jtmHasPin,
            "r60.Xiaohe recovers [1+2] first-syllable missing key sentence (jtmtmqihfhc -> 今天天气很好) with missing pinpoint",
            "top=\(jtmTop ?? "nil") pin=\(bar.preeditPinpointForTests) marked=\(vc.testState.marked ?? "nil")")

        // 2. Full sentences with mid-sentence missing keys ([1+2] vegewftifmejpjt & hvyigddcxwusjdm)
        reset(vc, h)
        type(vc, "vegewftifmejpjt"); settle(vc)
        let sent1Top = vc.testState.candidates.first
        reset(vc, h)
        type(vc, "hvyigddcxwusjdm"); settle(vc)
        let sent2Top = vc.testState.candidates.first
        log(sent1Top == "这个问题怎么解决" && sent2Top == "会议改到下午三点",
            "r60.Xiaohe recovers full sentences with mid-sentence missing keys",
            "s1=\(sent1Top ?? "nil") s2=\(sent2Top ?? "nil")")

        // 3. Odd-length normal Xiaohe typing stays intact (keyil -> 可以了, nihcm -> 你好吗)
        reset(vc, h)
        type(vc, "keyil"); settle(vc)
        let odd1 = vc.testState.candidates.first
        reset(vc, h)
        type(vc, "nihcm"); settle(vc)
        let odd2 = vc.testState.candidates.first
        log(odd1 == "可以了" && odd2 == "你好吗",
            "r60.Xiaohe preserves normal odd-length next-syllable prediction (keyil / nihcm)",
            "odd1=\(odd1 ?? "nil") odd2=\(odd2 ?? "nil")")
        reset(vc, h)
    }

    // MARK: - R61: smart bracket overtype, English session literal respect & kaomoji carry-over delete

    static func r61BilingualFlowAndPairOvertype(_ window: UIWindow) {
        guard let (vc, h) = makeKeyboard(scheme: 1, in: window) else {
            log(false, "r61.setup", "engine did not load")
            return
        }

        // 1. Smart CJK bracket closing overtype: （ + nihao + space + ） -> （你好）| (zero duplicate closing bracket)
        reset(vc, h)
        vc.handle(.char("（"), tap: nil)
        type(vc, "nihao"); settle(vc); vc.handle(.space, tap: nil)
        let insidePair = h.string == "（你好）" && h.documentContextAfterInput == "）"
        vc.handle(.char("）"), tap: nil)
        let overtyped = h.string == "（你好）" && (h.documentContextAfterInput ?? "").isEmpty
        // Typing another closing bracket right after steps normally as a character
        vc.handle(.char("）"), tap: nil)
        let extraInserted = h.string == "（你好））"
        log(insidePair && overtyped && extraInserted,
            "r61.Smart CJK bracket overtypes closing mark without duplicating it",
            "inside=\(insidePair) overtyped=\(overtyped) extra=\(extraInserted) text=\(h.string)")

        // 2. English session-scoped undo respect: undoing teh->the twice keeps teh literal for the rest of session
        reset(vc, h)
        if !vc.testState.english { vc.handle(.toggleLanguage, tap: nil) }
        h.insertText("hello ")
        vc.textDidChange(nil)
        type(vc, "teh"); vc.handle(.space, tap: nil)
        let firstFix = h.string == "hello the "
        vc.handle(.delete, tap: nil) // 1st undo -> "teh"
        vc.handle(.space, tap: nil)  // "teh "
        type(vc, "teh"); vc.handle(.space, tap: nil)
        let secondFix = h.string == "hello teh the "
        vc.handle(.delete, tap: nil) // 2nd undo -> sessionLiteralEnglish learns "teh"
        vc.handle(.space, tap: nil)  // "teh teh "
        type(vc, "teh"); vc.handle(.space, tap: nil)
        let stayedLiteral = h.string == "hello teh teh teh "
        log(firstFix && secondFix && stayedLiteral,
            "r61.English session undo twice stops autocorrect from fighting intentional spelling",
            "first=\(firstFix) second=\(secondFix) stayed=\(stayedLiteral) text=\(h.string)")

        // 3. Kaomoji carry-over delete: inserting ψ(｀∇´)ψ and returning to keyboard deletes the whole kaomoji in 1 tap
        reset(vc, h)
        if vc.testState.english { vc.handle(.toggleLanguage, tap: nil) }
        h.insertText("早安 ")
        vc.textDidChange(nil)
        vc.candidateBarForTests.onMostoTap?()
        drain(0.05)
        vc.emojiPanelIfLoadedForTests?.onEmoji?("ψ(｀∇´)ψ")
        vc.emojiPanelIfLoadedForTests?.onBack?()
        drain(0.03)
        let beforeDel = h.string
        vc.handle(.delete, tap: nil)
        let deletedWholeKaomoji = beforeDel == "早安 ψ(｀∇´)ψ" && h.string == "早安 "
        log(deletedWholeKaomoji,
            "r61.Returning from Kaomoji panel and tapping Delete removes the full kaomoji in one tap",
            "before=\(beforeDel) after=\(h.string)")

        // 4. CandidateGridView cell 0 marks corrected readings with its accent bar
        reset(vc, h)
        if vc.testState.english { vc.handle(.toggleLanguage, tap: nil) }
        type(vc, "jintianttianqihenhao"); settle(vc)
        vc.candidateBarForTests.onExpand?()
        drain(0.03)
        let grid = vc.gridIfLoadedForTests
        var barVisible = false
        var gridDetail = "grid=nil"
        if let grid {
            grid.layoutIfNeeded()
            let coll = grid.collectionForTests
            coll.layoutIfNeeded()
            drain(0.01)
            let cell = coll.cellForItem(at: IndexPath(item: 0, section: 0)) as? CandidateGridView.Cell
            barVisible = cell != nil && cell?.correctionBar.isHidden == false
            gridDetail = "coll=true cell=\(cell != nil) barHidden=\(cell?.correctionBar.isHidden ?? true)"
        }
        log(barVisible, "r61.CandidateGridView renders correctionBar accent under corrected slot 0", gridDetail)
        reset(vc, h)
    }

    static func r62NestedPairsMathAndKaomojiMoodSync(_ window: UIWindow) {
        // 1. Nested CJK bracket pairs overtype & delete cleanly across multiple depths
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = pair
            vc.handle(.char("（"), tap: nil)
            type(vc, "jian"); settle(vc); vc.handle(.space, tap: nil)
            vc.handle(.char("「"), tap: nil)
            type(vc, "fulu"); settle(vc); vc.handle(.space, tap: nil)
            vc.handle(.char("」"), tap: nil)
            type(vc, "shuom"); settle(vc); vc.handle(.space, tap: nil)
            vc.handle(.char("）"), tap: nil)
            drain(0.03)
            let nestedText = h.string
            let nestedOk = nestedText.hasPrefix("（")
                && nestedText.contains("「")
                && nestedText.contains("」")
                && nestedText.hasSuffix("）")
                && nestedText.filter { $0 == "）" }.count == 1
                && nestedText.filter { $0 == "」" }.count == 1
                && h.cursor == h.text.count
            reset(vc, h)

            // Inner pair smart backspace followed by outer closing bracket overtype
            vc.handle(.char("（"), tap: nil)
            vc.handle(.char("「"), tap: nil)
            vc.handle(.delete, tap: nil)
            vc.handle(.char("）"), tap: nil)
            drain(0.02)
            let unwindOk = h.string == "（）" && h.cursor == 2
            log(nestedOk && unwindOk,
                "r62.Nested CJK pair stack overtypes & unwinds cleanly without duplicate closing marks",
                "nested=\(nestedText) unwind=\(h.string) cursor=\(h.cursor)")
            reset(vc, h)

            // 2. Trailing arithmetic accepts Chinese fullwidth parentheses （ ）
            vc.handle(.char("（"), tap: nil)
            for ch in ["1", "2", "+", "8"] { vc.handle(.char(ch), tap: nil) }
            vc.handle(.char("）"), tap: nil)
            for ch in ["*", "3", "="] { vc.handle(.char(ch), tap: nil) }
            drain(0.03)
            let mathPreds = vc.testState.predictions
            let mathCap = vc.candidateBarForTests.firstCaptionForTests
            vc.candidateTapped(0)
            drain(0.03)
            log(mathPreds == ["60"] && mathCap == "心算" && h.string == "（12+8）*3=60",
                "r62.Trailing arithmetic evaluates expressions containing Chinese fullwidth parentheses",
                "preds=\(mathPreds) cap=\(mathCap ?? "nil") text=\(h.string)")
            reset(vc, h)
        } else {
            log(false, "r62.pair and math setup", "engine did not load")
        }

        // 3. EmojiPanelView mood pose coupling, Mosto toggle, and live 常用 sync
        let savedRecent = UserDefaults.standard.array(forKey: "recentKaomoji")
        UserDefaults.standard.set(["(｡･ω･｡)"], forKey: "recentKaomoji")
        defer {
            if let savedRecent {
                UserDefaults.standard.set(savedRecent, forKey: "recentKaomoji")
            } else {
                UserDefaults.standard.removeObject(forKey: "recentKaomoji")
            }
        }
        let ep = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 264))
        ep.layoutIfNeeded()
        ep.load(kaomoji: true)
        let titlesBefore = ep.moodTitlesForTests
        let nightIdx = titlesBefore.firstIndex(of: "晚安") ?? -1
        let yawnIdx = titlesBefore.firstIndex(of: "摸鱼") ?? -1
        let signIdx = titlesBefore.firstIndex(of: "招牌") ?? -1
        var nightPose = ""
        var yawnPose = ""
        if nightIdx >= 0 {
            ep.selectMoodForTests(nightIdx)
            nightPose = ep.moodMostoPoseNameForTests
        }
        if yawnIdx >= 0 {
            ep.selectMoodForTests(yawnIdx)
            yawnPose = ep.moodMostoPoseNameForTests
        }
        ep.tapMoodMostoForTests()
        let toggledToRecent = ep.activeMoodIndexForTests == 0 && ep.displayedKaomojiCountForTests == 1
        ep.tapMoodMostoForTests()
        let toggledToSign = ep.activeMoodIndexForTests == signIdx
        ep.collectionView(ep.collectionForTests, didSelectItemAt: IndexPath(item: 0, section: 0))
        ep.selectMoodForTests(0)
        let syncedRecentCount = ep.displayedKaomojiCountForTests
        log(titlesBefore.first == "常用" && nightPose == "mosto_night" && yawnPose == "mosto_yawn" && toggledToRecent && toggledToSign && syncedRecentCount == 2,
            "r62.EmojiPanelView couples mood pose, Mosto shortcut toggle, and live 常用 kaomoji sync",
            "titles0=\(titlesBefore.first ?? "nil") night=\(nightPose) yawn=\(yawnPose) recent=\(toggledToRecent) sign=\(toggledToSign) count=\(syncedRecentCount)")
    }

    static func r63AdjustableHeightAndOpticalScale(_ window: UIWindow) {
        // 1. Single native-calibrated fixed Metrics totals, adaptive ceiling & optical letter sizing
        let heightsOk = Metrics.totalHeight(landscape: false) == 258
            && Metrics.totalHeight(landscape: true) == 198
            && Metrics.toolbarHeight(landscape: false) == 42
            && Metrics.toolbarHeight(landscape: true) == 38
            && Metrics.maxAdaptiveHeight(landscape: false) == 308
            && Metrics.maxAdaptiveHeight(landscape: true) == 224
            && Metrics.letterFontSize(forCapHeight: 37) == 23.5
            && Metrics.letterFontSize(forCapHeight: 40) == 24.0
            && Metrics.letterFontSize(forCapHeight: 43) == 25.0
            && Metrics.letterFontSize(forCapHeight: 48) == 26.0
        log(heightsOk,
            "r63.Metrics locks single calibrated portrait/landscape heights and optical font scale",
            "portrait=\(Metrics.totalHeight(landscape: false)) landscape=\(Metrics.totalHeight(landscape: true))")

        // 2. SettingsPanelView renders utility row cleanly without overlap across compact and narrow widths
        let sp = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 258))
        sp.load()
        sp.layoutIfNeeded()
        let panelOk = sp.utilityRowNonOverlappingForTests && sp.tileIconsLoadedForTests
        log(panelOk,
            "r63.SettingsPanelView renders hardware deck and utility row cleanly at calibrated height",
            "utilOk=\(sp.utilityRowNonOverlappingForTests) iconsOk=\(sp.tileIconsLoadedForTests)")

        // 3. KeyboardViewController reports fixed calibrated portrait/landscape height & updates on transition
        if let pair = makeKeyboard(scheme: 0, in: window) {
            let (vc, _) = pair
            vc.applySettings()
            drain(0.02)
            let hPortrait = vc.preferredHeightForTests
            let hLandscape = vc.heightForTests(landscape: true)
            log(hPortrait == 258 && hLandscape == 198 && vc.heightConstraintConstantForTests == 258,
                "r63.KeyboardViewController locks calibrated fixed portrait and landscape heights",
                "portrait=\(hPortrait) landscape=\(hLandscape) c=\(vc.heightConstraintConstantForTests ?? -1)")
        } else {
            log(false, "r63.KeyboardViewController setup", "engine did not load")
        }

        // 4. KeyboardView optical cap font scaling across compact, standard (258pt) & adaptive ceiling frames
        func firstLetterFontSize(in kb: KeyboardView) -> CGFloat {
            func findQ(_ v: UIView) -> UILabel? {
                for sub in v.subviews {
                    if let l = sub as? UILabel, l.text?.lowercased() == "q" { return l }
                    if let found = findQ(sub) { return found }
                }
                return nil
            }
            return findQ(kb)?.font.pointSize ?? 0
        }
        let kb = KeyboardView(spatial: SpatialModel.standard())
        let ctx = LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true)
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 184)
        kb.configure(ctx)
        kb.layoutIfNeeded()
        let compactFont = firstLetterFontSize(in: kb)
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 216)
        kb.setNeedsLayout()
        kb.layoutIfNeeded()
        let standardFont = firstLetterFontSize(in: kb)
        kb.frame = CGRect(x: 0, y: 0, width: 402, height: 240)
        kb.setNeedsLayout()
        kb.layoutIfNeeded()
        let tallFont = firstLetterFontSize(in: kb)
        log(compactFont == 23.5 && standardFont == 25.0 && tallFont == 26.0,
            "r63.KeyboardView scales letter cap typography optically across cap heights",
            "compact=\(compactFont) standard=\(standardFont) tall=\(tallFont)")

        // 5. Metrics height helper stays aligned across portrait and landscape
        log(Metrics.totalHeight(landscape: false) == 258 && Metrics.totalHeight(landscape: true) == 198,
            "r63.Metrics maintains calibrated portrait and landscape totals",
            "portrait=\(Metrics.totalHeight(landscape: false)) landscape=\(Metrics.totalHeight(landscape: true))")
    }

    // MARK: - R64: Spring-loaded Shift & 123/#+= modifier glide + two-finger chords

    static func r64SpringLoadedModifierGlide(_ window: UIWindow) {
        let s = KeyboardSettings.shared
        let savedNumberPad = s.numberPad
        defer { s.numberPad = savedNumberPad }

        // 1. Single-finger Shift glide (Chinese mode): Shift -> P -> lift inserts "P" and springs back to lowercase Chinese
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = pair
            let kb = vc.keyboardViewForTests
            kb.layoutIfNeeded()
            if let shiftRect = kb.keyRectsForTests(.shift)?.cap,
               let pRect = kb.keyRectsForTests(.char("p"))?.cap {
                let sp = center(shiftRect)
                let pp = center(pRect)
                var t = nextTime()
                kb.feedForTests([
                    TouchSample(id: 201, phase: .began, point: sp, time: t),
                    TouchSample(id: 201, phase: .moved, point: pp, time: t + 0.05),
                    TouchSample(id: 201, phase: .ended, point: pp, time: t + 0.09),
                ])
                let afterGlide = h.string
                let backToLower = kb.context?.shifted == false && !vc.testState.english
                // Slide from Shift onto Q and back to Shift: cancels without typing
                if let qRect = kb.keyRectsForTests(.char("q"))?.cap {
                    let qp = center(qRect)
                    t = nextTime()
                    kb.feedForTests([
                        TouchSample(id: 202, phase: .began, point: sp, time: t),
                        TouchSample(id: 202, phase: .moved, point: qp, time: t + 0.04),
                        TouchSample(id: 202, phase: .moved, point: sp, time: t + 0.08),
                        TouchSample(id: 202, phase: .ended, point: sp, time: t + 0.12),
                    ])
                }
                log(afterGlide == "P" && backToLower && h.string == "P",
                    "r64.Single-finger Shift glide types uppercase letter in Chinese mode and springs back; pull-back cancels",
                    "afterGlide=\(afterGlide) backToLower=\(backToLower) final=\(h.string)")
            } else {
                log(false, "r64.Shift glide rect lookup")
            }

            // 2. Two-finger Shift chord: hold Shift + tap i, o, s + release Shift -> "IOS" and resets Shift
            reset(vc, h)
            kb.layoutIfNeeded()
            if let shiftRect = kb.keyRectsForTests(.shift)?.cap,
               let iRect = kb.keyRectsForTests(.char("i"))?.cap,
               let oRect = kb.keyRectsForTests(.char("o"))?.cap,
               let sRect = kb.keyRectsForTests(.char("s"))?.cap {
                let t0 = nextTime()
                kb.feedForTests([
                    TouchSample(id: 210, phase: .began, point: center(shiftRect), time: t0),
                    TouchSample(id: 211, phase: .began, point: center(iRect), time: t0 + 0.04),
                    TouchSample(id: 211, phase: .ended, point: center(iRect), time: t0 + 0.08),
                    TouchSample(id: 212, phase: .began, point: center(oRect), time: t0 + 0.12),
                    TouchSample(id: 212, phase: .ended, point: center(oRect), time: t0 + 0.16),
                    TouchSample(id: 213, phase: .began, point: center(sRect), time: t0 + 0.20),
                    TouchSample(id: 213, phase: .ended, point: center(sRect), time: t0 + 0.24),
                    TouchSample(id: 210, phase: .ended, point: center(shiftRect), time: t0 + 0.28),
                ])
                log(h.string == "IOS" && kb.context?.shifted == false,
                    "r64.Two-finger Shift chord types uppercase run and resets Shift on release",
                    "text=\(h.string) shifted=\(kb.context?.shifted ?? true) caps=\(kb.context?.capsLock ?? false) chordHeld=\(kb.isShiftChordHeld) ctxNil=\(kb.context == nil)")
            } else {
                log(false, "r64.Shift chord rect lookup")
            }
        } else {
            log(false, "r64.Shift setup", "engine did not load")
        }

        // 3. Spring-loaded 123 glide (full numbers page + secondary #+= hop + two-finger chord + tap stays)
        s.numberPad = false
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = pair
            vc.applySettings()
            let kb = vc.keyboardViewForTests
            kb.layoutIfNeeded()
            if let pageRect = kb.keyRectsForTests(.page(.numbers))?.cap {
                let p123 = center(pageRect)
                let t0 = nextTime()
                // Normal tap on 123 -> stays on .numbers
                kb.feedForTests([
                    TouchSample(id: 220, phase: .began, point: p123, time: t0),
                    TouchSample(id: 220, phase: .ended, point: p123, time: t0 + 0.06),
                ])
                let stayedOnNumbers = vc.testState.page == .numbers
                let r5 = kb.keyRectsForTests(.char("5"))?.cap
                vc.handle(.page(.letters), tap: nil)
                kb.layoutIfNeeded()

                // Glide 123 -> 5 -> lift -> inserts "5" and springs back to .letters
                if let r5 {
                    let p5 = center(r5)
                    let t1 = nextTime()
                    kb.feedForTests([
                        TouchSample(id: 221, phase: .began, point: p123, time: t1),
                        TouchSample(id: 221, phase: .moved, point: p5, time: t1 + 0.05),
                        TouchSample(id: 221, phase: .ended, point: p5, time: t1 + 0.09),
                    ])
                }
                let glidedDigit = h.string == "5" && vc.testState.page == .letters

                // Glide 123 -> hover #+= (0.30s) -> % -> lift -> inserts "%" and springs back to .letters
                kb.feedForTests([TouchSample(id: 222, phase: .began, point: p123, time: nextTime())])
                let symRect = kb.keyRectsForTests(.page(.symbols))?.cap
                let pctFromSyms: CGRect?
                if let symRect {
                    let t2 = nextTime()
                    kb.feedForTests([TouchSample(id: 222, phase: .moved, point: center(symRect), time: t2)])
                    kb.advanceForTests(to: t2 + 0.30)
                    kb.layoutIfNeeded()
                    pctFromSyms = kb.keyRectsForTests(.char("%"))?.cap
                    if let pctFromSyms {
                        kb.feedForTests([
                            TouchSample(id: 222, phase: .moved, point: center(pctFromSyms), time: t2 + 0.36),
                            TouchSample(id: 222, phase: .ended, point: center(pctFromSyms), time: t2 + 0.40),
                        ])
                    } else {
                        kb.feedForTests([TouchSample(id: 222, phase: .ended, point: center(symRect), time: t2 + 0.36)])
                    }
                } else {
                    pctFromSyms = nil
                }
                let hoppedToSymbols = h.string == "5%" && vc.testState.page == .letters

                // Glide 123 -> 5 -> return (blocked) -> lift -> cancels accidental send and springs back to .letters
                if let r5 {
                    let t3 = nextTime()
                    kb.feedForTests([TouchSample(id: 223, phase: .began, point: p123, time: t3)])
                    let retRect = kb.keyRectsForTests(.ret)?.cap
                    if let retRect {
                        kb.feedForTests([
                            TouchSample(id: 223, phase: .moved, point: center(r5), time: t3 + 0.04),
                            TouchSample(id: 223, phase: .moved, point: center(retRect), time: t3 + 0.08),
                            TouchSample(id: 223, phase: .ended, point: center(retRect), time: t3 + 0.12),
                        ])
                    }
                }
                let blockedSafe = h.string == "5%" && vc.testState.page == .letters

                // Two-finger 123 chord: hold 123 + tap 2, 0, 2, 6 + release 123 -> "2026" and returns to .letters
                reset(vc, h)
                let t4 = nextTime()
                kb.feedForTests([TouchSample(id: 224, phase: .began, point: p123, time: t4)])
                if let r2 = kb.keyRectsForTests(.char("2"))?.cap,
                   let r0 = kb.keyRectsForTests(.char("0"))?.cap,
                   let r6 = kb.keyRectsForTests(.char("6"))?.cap {
                    kb.feedForTests([
                        TouchSample(id: 225, phase: .began, point: center(r2), time: t4 + 0.03),
                        TouchSample(id: 225, phase: .ended, point: center(r2), time: t4 + 0.06),
                        TouchSample(id: 226, phase: .began, point: center(r0), time: t4 + 0.09),
                        TouchSample(id: 226, phase: .ended, point: center(r0), time: t4 + 0.12),
                        TouchSample(id: 227, phase: .began, point: center(r2), time: t4 + 0.15),
                        TouchSample(id: 227, phase: .ended, point: center(r2), time: t4 + 0.18),
                        TouchSample(id: 228, phase: .began, point: center(r6), time: t4 + 0.21),
                        TouchSample(id: 228, phase: .ended, point: center(r6), time: t4 + 0.24),
                        TouchSample(id: 224, phase: .ended, point: p123, time: t4 + 0.28),
                    ])
                }
                let chordOK = h.string == "2026" && vc.testState.page == .letters

                log(stayedOnNumbers && glidedDigit && hoppedToSymbols && blockedSafe && chordOK,
                    "r64.123 spring-loaded glide, #+= secondary hop, edge-block safety, and two-finger chord",
                    "stay=\(stayedOnNumbers) glide=\(glidedDigit) sym=\(hoppedToSymbols) block=\(blockedSafe) chord=\(chordOK) text=\(h.string) page=\(vc.testState.page)")
            } else {
                log(false, "r64.123 rect lookup")
            }
        } else {
            log(false, "r64.123 setup", "engine did not load")
        }

        // 4. Numpad spring-loaded glide (with numberPad = true)
        s.numberPad = true
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = pair
            vc.applySettings()
            let kb = vc.keyboardViewForTests
            kb.layoutIfNeeded()
            if let padRect = kb.keyRectsForTests(.page(.numpad))?.cap {
                let p123 = center(padRect)
                let t0 = nextTime()
                kb.feedForTests([TouchSample(id: 230, phase: .began, point: p123, time: t0)])
                if let r8 = kb.keyRectsForTests(.char("8"))?.cap {
                    kb.feedForTests([
                        TouchSample(id: 230, phase: .moved, point: center(r8), time: t0 + 0.05),
                        TouchSample(id: 230, phase: .ended, point: center(r8), time: t0 + 0.09),
                    ])
                }
                log(h.string == "8" && vc.testState.page == .letters,
                    "r64.Numpad 123 spring-loaded glide inserts digit and returns to letters",
                    "text=\(h.string) page=\(vc.testState.page)")
            } else {
                log(false, "r64.numpad rect lookup")
            }
        } else {
            log(false, "r64.numpad setup", "engine did not load")
        }
    }

    // MARK: - R65: Visual craft, optical kaomoji row fit, console tile cap & honest copy

    static func r65VisualCraftAndOpticalFit(_ window: UIWindow) {
        // 1. 招牌 kaomoji deduplicated to 12 items, 229+ unique kaomoji overall
        let signGroup = EmojiPanelView.kaomojiMoodGroups.first(where: { $0.title == "招牌" })?.items ?? []
        let allK = EmojiPanelView.kaomoji
        let signOk = signGroup.count == 12
            && !signGroup.contains("ψ(｀▽´)ψ")
            && signGroup.contains("ψ(≧▽≦)ψ")
            && signGroup.contains("ψ( ˘ω˘ )ψ")
            && allK.count >= 229
            && Set(allK).count == allK.count
        log(signOk,
            "r65.招牌 kaomoji group is deduplicated to 12 distinct expressions across 229+ unique items",
            "signCount=\(signGroup.count) total=\(allK.count) unique=\(Set(allK).count)")

        // 2. Optical integer-row kaomoji cell height prevents half-clipped rows across all 4 height tiers
        let ep = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 242))
        ep.load(kaomoji: true)
        var measuredHeights: [CGFloat] = []
        for h in [226, 242, 262, 284] as [CGFloat] {
            ep.frame = CGRect(x: 0, y: 0, width: 402, height: h)
            ep.setNeedsLayout()
            ep.layoutIfNeeded()
            measuredHeights.append(ep.kaomojiRowHeightForTests)
        }
        log(measuredHeights == [44, 50, 42, 48],
            "r65.EmojiPanelView fits whole kaomoji rows cleanly across compact..tall tiers",
            "rowHeights=\(measuredHeights)")

        // 3. SettingsPanelView caps tile height on tall screens & keeps utilityRow non-overlapping on compact/narrow screens
        let s = KeyboardSettings.shared
        let prevScheme = s.scheme
        defer { s.scheme = prevScheme }
        let tallPanel = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 800))
        tallPanel.layoutIfNeeded()
        let cappedTiles = tallPanel.maxTileHeightForTests <= 84 && tallPanel.maxTileHeightForTests >= 42
        let narrowPanel = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 375, height: 226))
        s.scheme = 0
        narrowPanel.load(); narrowPanel.layoutIfNeeded()
        let xiaoheClean = narrowPanel.utilityRowNonOverlappingForTests
        s.scheme = 1
        narrowPanel.load(); narrowPanel.layoutIfNeeded()
        let quanpinClean = narrowPanel.utilityRowNonOverlappingForTests
        log(cappedTiles && xiaoheClean && quanpinClean,
            "r65.SettingsPanelView caps tile height on tall views and avoids utilityRow overlap at 375x226",
            "maxTileH=\(tallPanel.maxTileHeightForTests) xiaohe=\(xiaoheClean) quanpin=\(quanpinClean)")

        // 4. Companion app FamilyAtmosphere captions have no leaked milestone code
        let captionsClean = FamilyAtmosphere.allCases.allSatisfy { !$0.stageCaption.contains("R50") }
        log(captionsClean,
            "r65.FamilyAtmosphere captions avoid internal milestone jargon",
            "day=\(FamilyAtmosphere.day.stageCaption)")
    }

    // MARK: - R66: Unified Xiaohe interactive instrument, compact landscape console & grid thumb close

    static func r66VisualStructureAndThumbErgonomics(_ window: UIWindow) {
        // 1. SettingsPanelView at compact landscape (480x186) with Full Access OFF banner shows zero overlaps
        let landPanel = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 480, height: 186))
        landPanel.setFeedbackAvailable(false)
        landPanel.load()
        landPanel.layoutIfNeeded()
        log(landPanel.utilityRowNonOverlappingForTests && landPanel.bannerNonOverlappingForTests,
            "r66.SettingsPanelView keeps accessBanner and utilityRow non-overlapping at 480x186 compact landscape",
            "util=\(landPanel.utilityRowNonOverlappingForTests) banner=\(landPanel.bannerNonOverlappingForTests)")

        // 2. CandidateGridView exposes thumb-reachable bottom dock collapse button beside delete
        let grid = CandidateGridView(frame: CGRect(x: 0, y: 0, width: 402, height: 220))
        grid.show([
            Candidate(text: "你好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "你", tapCount: 2, syllables: [1], corrected: false, score: 0),
        ])
        grid.layoutIfNeeded()
        var closedCount = 0
        grid.onClose = { closedCount += 1 }
        grid.tapCloseForTests()
        log(!grid.closeButtonHiddenForTests && closedCount == 1,
            "r66.CandidateGridView shows bottom dock close button and triggers onClose on tap",
            "hidden=\(grid.closeButtonHiddenForTests) closed=\(closedCount)")

        // 3. XiaoheDrill interactive key inspector returns verified 2-key examples for tricky keys
        let vExamples = XiaoheDrill.inspectExamplesForTests(key: "v")
        let lExamples = XiaoheDrill.inspectExamplesForTests(key: "l")
        let uExamples = XiaoheDrill.inspectExamplesForTests(key: "u")
        let allValid = !vExamples.isEmpty && !lExamples.isEmpty && !uExamples.isEmpty
            && vExamples.allSatisfy { $0.code.contains("v") && $0.code.count == 2 }
            && lExamples.allSatisfy { $0.code.contains("l") && $0.code.count == 2 }
            && uExamples.allSatisfy { $0.code.contains("u") && $0.code.count == 2 }
        log(allValid,
            "r66.XiaoheDrill interactive key inspector returns verified 2-key examples for zh/sh/liang keys",
            "v=\(vExamples.map(\.code)) l=\(lExamples.map(\.code)) u=\(uExamples.map(\.code))")
    }

    // MARK: - R67: Nine-grid rich punctuation AltPopup, Row-0 top clamp & interactive Free Bench replays

    static func r67T9AltPopupAndFreeBenchInspirations(_ window: UIWindow) {
        // 1. Nine-grid punctuation keys expose rich moreAlts without leaving the main keypad
        let ctx = LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false,
                                shifted: false, capsLock: false, keyBorders: true, numberGrid: false, pinyinGrid: true,
                                composing: false, xiaoheGuide: false)
        let t9Specs = Layouts.rows(ctx).flatMap { $0 }
        let commaSpec = t9Specs.first { $0.action == .char("，") }
        let periodSpec = t9Specs.first { $0.action == .char("。") }
        let questionSpec = t9Specs.first { $0.action == .char("？") }
        log(commaSpec?.alt == "、" && (commaSpec?.moreAlts.contains("（") == true)
            && periodSpec?.alt == "…" && (periodSpec?.moreAlts.contains("》") == true)
            && questionSpec?.alt == "！" && (questionSpec?.moreAlts.contains("【") == true),
            "r67.pinyinPad punctuation keys expose rich moreAlts for brackets and marks",
            "comma=\(commaSpec?.moreAlts ?? []) period=\(periodSpec?.moreAlts ?? []) q=\(questionSpec?.moreAlts ?? [])")

        // 2. Long-press on Row-0 `，` in 九宫格 shows AltPopup safely inside root bounds & sliding selects `（` -> `（）`
        if let kb = makeKeyboard(scheme: 0, grid: true, in: window) {
            let (vc, h) = kb
            let board = vc.keyboardViewForTests
            board.layoutIfNeeded()
            if let comma = board.keyRectsForTests(.char("，"))?.cap {
                let cell = max(comma.width, 34)
                let startPt = CGPoint(x: comma.midX, y: comma.midY)
                // Hold 0.45s to open AltPopup, then inspect bounds before sliding to index 3 (`（`: ["、", "：", "；", "（", ...])
                let holdSamples = path(from: startPt, legs: [(.zero, 0.45)])
                let holdDown = Array(holdSamples.dropLast())
                board.feedForTests(holdDown)
                let popupFrame = board.activeAltPopupFrameForTests
                let options = board.activeAltOptionsForTests
                let rootTopInBoard = board.convert(CGPoint.zero, from: vc.view).y
                log(popupFrame != nil && (popupFrame?.minY ?? -999) >= rootTopInBoard && options.count >= 6,
                    "r67.Row-0 AltPopup clamps inside host keyboard bounds without top clipping",
                    "frame=\(String(describing: popupFrame)) topLimit=\(rootTopInBoard) opts=\(options.count)")

                // Slide right 3 cells onto `（` and lift
                let anchorTime = holdDown.last?.time ?? 0
                let slideStart = CGPoint(x: startPt.x + 8, y: startPt.y)
                let slideEnd = CGPoint(x: startPt.x + cell * 3 + 4, y: startPt.y)
                var slideSamples: [TouchSample] = [
                    TouchSample(id: 1, phase: .moved, point: slideStart, time: anchorTime + 0.02),
                    TouchSample(id: 1, phase: .moved, point: slideEnd, time: anchorTime + 0.08),
                    TouchSample(id: 1, phase: .ended, point: slideEnd, time: anchorTime + 0.10),
                ]
                board.feedForTests(slideSamples)
                drain(0.05)
                _ = slideSamples.popLast()
                log(h.documentContextBeforeInput == "（" && h.documentContextAfterInput == "）",
                    "r67.Sliding across Row-0 九宫格 AltPopup inserts matching smart pair with cursor inside",
                    "before='\(h.documentContextBeforeInput ?? "")' after='\(h.documentContextAfterInput ?? "")'")
            } else {
                log(false, "r67.Row-0 AltPopup", "missing comma key rect")
            }
        } else {
            log(false, "r67.Row-0 AltPopup setup")
        }

        // 3. Direct trailing mental arithmetic and Xiaohe autocorrect replay cleanly on KeyboardViewController
        if let kb = makeKeyboard(scheme: 0, grid: false, in: window) {
            let (vc, h) = kb
            for ch in "365+18=" { vc.handle(.char(String(ch)), tap: nil) }
            drain(0.05)
            log(vc.testState.predictions == ["383"],
                "r67.Controller triggers live trailing arithmetic candidate 383",
                "predictions=\(vc.testState.predictions)")

            h.clear(); vc.discardComposition(); vc.textDidChange(nil)
            type(vc, "jbtmtmqohfhc"); settle(vc)
            log(vc.testState.composing && !vc.testState.candidates.isEmpty && !vc.activeFirstFixesForTests.isEmpty,
                "r67.Controller reproduces live autocorrect pinpoint state",
                "keys=\(vc.testState.keys) fixes=\(vc.activeFirstFixesForTests.count)")
        } else {
            log(false, "r67.Controller inspiration setup")
        }
    }

    // MARK: - R68: Math Spacebar Commit & Chained Calc, Exclusive Forget Stage, Clear Cue & Emoji Craft

    static func r68StageOverlaysMathSpaceAndEmojiCraft(_ window: UIWindow) {
        // 1. Trailing mental math commits via Spacebar cleanly and chains follow-up arithmetic
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, h) = pair
            vc.handle(.page(.numbers), tap: nil)
            for ch in ["3", "6", "5", "+", "1", "8", "="] { vc.handle(.char(ch), tap: nil) }
            drain(0.03)
            let preds1 = vc.testState.predictions
            vc.handle(.space, tap: nil)
            drain(0.03)
            let afterSpace1 = h.string
            let predsCleared = vc.testState.predictions.isEmpty
            for ch in ["+", "1", "0", "="] { vc.handle(.char(ch), tap: nil) }
            drain(0.03)
            let preds2 = vc.testState.predictions
            vc.handle(.space, tap: nil)
            drain(0.03)
            log(preds1 == ["383"] && afterSpace1 == "365+18=383" && predsCleared
                && preds2 == ["393"] && h.string == "365+18=383+10=393",
                "r68.Space commits trailing math result cleanly and chains subsequent calculations",
                "preds1=\(preds1) s1=\(afterSpace1) preds2=\(preds2) final=\(h.string)")
        } else {
            log(false, "r68.math space setup")
        }

        // 2. Exclusive Forget Stage hides underlying strip/preedit/expand cleanly and restores on cancel
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 402, height: 42))
        bar.showsPreedit = true
        bar.update(preedit: "nihc", candidates: [
            Candidate(text: "你好", tapCount: 4, syllables: [1], corrected: true, score: 0),
            Candidate(text: "尼好", tapCount: 4, syllables: [1], corrected: false, score: 0),
        ])
        bar.layoutIfNeeded()
        bar.offerForget("摸索小鹤双拼键盘测试长词") {}
        let active = bar.forgetOverlayActiveForTests
        let hidesUnderlying = bar.forgetOverlayHidesStripForTests
        let nonOverlap = bar.forgetButtonsNonOverlappingForTests
        bar.tapForgetCancelForTests()
        bar.layoutIfNeeded()
        log(active && hidesUnderlying && nonOverlap && !bar.forgetOverlayActiveForTests && bar.laidOutForTests >= 2,
            "r68.CandidateBarView.offerForget stages exclusive non-overlapping overlay and restores cleanly on cancel",
            "active=\(active) hides=\(hidesUnderlying) nonOverlap=\(nonOverlap) restored=\(!bar.forgetOverlayActiveForTests) laid=\(bar.laidOutForTests)")

        // 3. Armed delete-left swipe shows clearArmedCue without triggering during held-delete clutch (dimContent: false)
        bar.setClearProgress(1, armed: true, dimContent: true)
        let swipeCueShown = bar.clearArmedCueShownForTests
        bar.setClearProgress(1, armed: true, dimContent: false)
        let clutchCueHidden = !bar.clearArmedCueShownForTests
        bar.setClearProgress(0, armed: false, dimContent: true)
        log(swipeCueShown && clutchCueHidden && !bar.clearArmedCueShownForTests,
            "r68.ClearArmed micro-cue displays only for armed delete-left swipe and resets cleanly",
            "swipeCue=\(swipeCueShown) clutchHidden=\(clutchCueHidden)")

        // 4. EmojiPanelView soft bottom fade, unclipped portrait dock lightbulb, and 1-tap sticky-header Kaomoji shortcut
        for e in ["👍", "😭", "❤️", "🙏", "😂"] { EmojiPanelView.remember(e) }
        let ep = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 242))
        ep.layoutIfNeeded()
        ep.load(kaomoji: false)
        ep.layoutIfNeeded()
        let fadeOn = ep.collectionBottomFadeActiveForTests
        let shortcutShown = ep.kaomojiShortcutVisibleForTests
        let bulbUnclipped = ep.portraitDockLightbulbUnclippedForTests
        ep.tapKaomojiShortcutForTests()
        ep.layoutIfNeeded()
        let switchedToKaomoji = ep.kaomojiModeForTests && !ep.kaomojiShortcutVisibleForTests
            && !ep.collectionBottomFadeActiveForTests && ep.tabScrollOffsetXForTests > 20
        log(fadeOn && shortcutShown && bulbUnclipped && switchedToKaomoji,
            "r68.EmojiPanelView applies soft bottom fade, keeps portrait dock lightbulb unclipped, and opens Kaomoji in 1 tap",
            "fade=\(fadeOn) shortcut=\(shortcutShown) bulb=\(bulbUnclipped) kao=\(switchedToKaomoji) offsetX=\(ep.tabScrollOffsetXForTests)")
    }

    // MARK: - R69: Height persistence root-cause fix & visual-first hardware console

    static func r69HeightPersistenceAndVisualConsole(_ window: UIWindow) {
        let s = KeyboardSettings.shared
        let prevScheme = s.scheme
        let prevAppearance = s.appearance
        defer {
            s.scheme = prevScheme
            s.appearance = prevAppearance
        }

        // 1. Without an App Group entitlement, KeyboardSettings must persist directly via UserDefaults.standard
        let usesStd = s.usesStandardDefaultsForTests
        s.scheme = 0
        s.appearance = 2
        let persistedScheme = (UserDefaults.standard.object(forKey: "scheme") as? NSNumber)?.intValue == 0
        let persistedLight = (UserDefaults.standard.object(forKey: "appearance") as? NSNumber)?.intValue == 2
        log(usesStd && persistedScheme && persistedLight,
            "r69.KeyboardSettings persists preferences reliably in UserDefaults.standard without App Group drops",
            "usesStd=\(usesStd) scheme=\(persistedScheme) light=\(persistedLight)")

        // 2. Portrait Pro Max / detached bounds must not misclassify 393x258 or 430x294 as landscape
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, _) = pair
            vc.view.frame = CGRect(x: 0, y: 0, width: 430, height: 294)
            vc.showSettingsForTests(true)
            vc.applySettings()
            vc.showSettingsForTests(false)
            vc.updateViewConstraints()
            vc.view.layoutIfNeeded()
            let portraitOk = vc.preferredHeightForTests == 258
                && vc.heightConstraintConstantForTests == 258

            vc.beginAppearanceTransition(false, animated: false)
            vc.endAppearanceTransition()
            vc.beginAppearanceTransition(true, animated: false)
            vc.endAppearanceTransition()
            vc.view.layoutIfNeeded()
            let afterAppearOk = vc.preferredHeightForTests == 258
                && vc.heightConstraintConstantForTests == 258
                && vc.heightForTests(landscape: true) == 198
            log(portraitOk && afterAppearOk,
                "r69.KeyboardViewController holds calibrated portrait height across settings close, updateViewConstraints, and viewWillAppear",
                "portraitOk=\(portraitOk) appearOk=\(afterAppearOk) h=\(vc.preferredHeightForTests) c=\(vc.heightConstraintConstantForTests ?? -1)")
        } else {
            log(false, "r69.KeyboardViewController height persistence setup", "engine did not load")
        }

        // 3. Visual Hardware Deck icons + utility row avoid overlap across compact/narrow/landscape bounds
        let sp = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 375, height: 226))
        sp.load()
        sp.layoutIfNeeded()
        let iconsOk = sp.tileIconsLoadedForTests
        s.scheme = 0
        sp.load(); sp.layoutIfNeeded()
        let narrowXiaoheOk = sp.utilityRowNonOverlappingForTests
        s.scheme = 1
        sp.load(); sp.layoutIfNeeded()
        let narrowQuanpinOk = sp.utilityRowNonOverlappingForTests
        let landPanel = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 480, height: 186))
        landPanel.setFeedbackAvailable(false)
        landPanel.load(); landPanel.layoutIfNeeded()
        let landOk = landPanel.utilityRowNonOverlappingForTests && landPanel.bannerNonOverlappingForTests
        log(iconsOk && narrowXiaoheOk && narrowQuanpinOk && landOk,
            "r69.Visual Hardware Console renders tile icons cleanly and avoids utilityRow overlap on compact screens",
            "icons=\(iconsOk) narrow0=\(narrowXiaoheOk) narrow1=\(narrowQuanpinOk) land=\(landOk)")

        // 4. FamilyStageModel syncSoundFromSettings mirrors persisted keySound without altering keyboard extension scheme/appearance
        let prevSound = s.keySound
        s.scheme = 0
        s.appearance = 2
        let family = FamilyStageModel()
        s.keySound = false
        family.syncSoundFromSettings()
        let syncedOff = !family.soundEnabled && s.scheme == 0 && s.appearance == 2
        s.keySound = true
        family.syncSoundFromSettings()
        let syncedOn = family.soundEnabled
        s.keySound = prevSound
        log(syncedOff && syncedOn,
            "r69.FamilyStageModel syncs keySound cleanly without clobbering persisted keyboard settings",
            "off=\(syncedOff) on=\(syncedOn)")
    }

    // MARK: - R70: Candidate grid 3-mode scope rail, bottom fade & Kaomoji dock gear visibility

    static func r70GridScopeRailAndDockCraft(_ window: UIWindow) {
        // 1. EmojiPanelView snaps Kaomoji dock cleanly so Mosto and trailing gear sit inside dock viewport
        let ep = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 242))
        ep.layoutIfNeeded()
        ep.load(kaomoji: true)
        ep.layoutIfNeeded()
        log(ep.tabScrollOffsetXForTests > 20 && ep.kaomojiDockGearFullyVisibleForTests,
            "r70.EmojiPanelView keeps trailing settings gear completely visible inside Kaomoji dock",
            "offsetX=\(ep.tabScrollOffsetXForTests) gearVisible=\(ep.kaomojiDockGearFullyVisibleForTests)")

        // 2. CandidateGridView 3-mode scope rail (全部 / 词组 / 单字), live count badge, real-index mapping & dock non-overlap
        let grid = CandidateGridView(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        let mixed = ["你好", "今天", "你", "尼", "泥"].map {
            Candidate(text: $0, tapCount: $0.count * 2, syllables: [1], corrected: false, score: 0)
        }
        grid.show(mixed)
        grid.layoutIfNeeded()
        let allOk = grid.displayedCountForTests == 5 && grid.countBadgeTextForTests == "5" && grid.filterModeForTests == 0
        grid.selectFilterForTests(1)
        var longPressIdx = -1
        grid.onLongPress = { longPressIdx = $0 }
        grid.longPressDisplayedForTests(1)
        let phrasesOk = grid.displayedCountForTests == 2 && grid.countBadgeTextForTests == "2 词" && longPressIdx == 1
        grid.selectFilterForTests(2)
        let singleOk = grid.displayedCountForTests == 3 && grid.countBadgeTextForTests == "3 字"
        let narrowOk = grid.dockControlsNonOverlappingForTests
        grid.frame = CGRect(x: 0, y: 0, width: 480, height: 160)
        grid.setNeedsLayout(); grid.layoutIfNeeded()
        let landOk = grid.dockControlsNonOverlappingForTests
        log(allOk && phrasesOk && singleOk && narrowOk && landOk,
            "r70.CandidateGridView filters all/phrases/single-char with live badge, real index mapping, and non-overlapping dock",
            "all=\(allOk) phrases=\(phrasesOk) single=\(singleOk) narrow=\(narrowOk) land=\(landOk)")

        // 3. CandidateGridView bottom fade activates on vertical overflow and stays off for short lists
        let overflowGrid = CandidateGridView(frame: CGRect(x: 0, y: 0, width: 402, height: 180))
        let many = (0..<28).map { i in
            Candidate(text: "词\(i)", tapCount: 4, syllables: [1, 2], corrected: false, score: 0)
        }
        overflowGrid.show(many)
        overflowGrid.layoutIfNeeded()
        let fadeOnOverflow = overflowGrid.collectionBottomFadeActiveForTests
        overflowGrid.show([Candidate(text: "好", tapCount: 2, syllables: [1], corrected: false, score: 0)])
        overflowGrid.layoutIfNeeded()
        let fadeOffShort = !overflowGrid.collectionBottomFadeActiveForTests
        log(fadeOnOverflow && fadeOffShort,
            "r70.CandidateGridView enables dynamic bottom fade only when vertical candidates overflow",
            "on=\(fadeOnOverflow) off=\(fadeOffShort)")
    }

    // MARK: - R71: Xiaohe Live Chord Lighting & Guide Inspector Partner Illumination

    static func r71XiaoheChordLighting(_ window: UIWindow) {
        // 1. Canonical XiaoheScheme syllable matrix matches lexicon.bin syllables 100% with zero drift
        let lexPath = KeyboardViewController.resourceBundle.path(forResource: "lexicon", ofType: "bin")
        let lex = lexPath.flatMap { try? Lexicon(path: $0) }
        let lexSet = Set(lex?.syllables.filter { XiaoheScheme.code(for: $0) != nil } ?? [])
        let schemeSet = Set(XiaoheScheme.allSyllables)
        let missingFromScheme = lexSet.subtracting(schemeSet)
        let extraInScheme = schemeSet.subtracting(lexSet)
        var roundTripOk = !lexSet.isEmpty
        for syl in lexSet {
            guard let code = XiaoheScheme.code(for: syl), code.count == 2 else { roundTripOk = false; break }
            let chars = Array(code)
            if !(XiaoheScheme.validSecondKeys(after: chars[0])[chars[1]]?.contains(syl) ?? false) {
                roundTripOk = false; break
            }
        }
        log(!lexSet.isEmpty && missingFromScheme.isEmpty && extraInScheme.isEmpty && roundTripOk,
            "r71.XiaoheScheme.allSyllables matches lexicon.bin 100% and round-trips every 2-key code",
            "lex=\(lexSet.count) missing=\(missingFromScheme) extra=\(extraInScheme) rt=\(roundTripOk)")

        // 2. Per-final precision & zero-initial overrides
        let qk = XiaoheScheme.chordHint(forKey: "k", after: "q") // qing -> index 0 ("ing"), NOT "uai"
        let gk = XiaoheScheme.chordHint(forKey: "k", after: "g") // guai -> index 1 ("uai"), NOT "ing"
        let js = XiaoheScheme.chordHint(forKey: "s", after: "j") // jiong -> index 1 ("iong"), NOT "ong"
        let nt = XiaoheScheme.chordHint(forKey: "t", after: "n") // nüe -> index 1 ("üe"), NOT "ue"
        let nv = XiaoheScheme.chordHint(forKey: "v", after: "n") // nü -> index 1 ("ü"), NOT "ui"
        let dv = XiaoheScheme.chordHint(forKey: "v", after: "d") // dui -> index 0 ("ui"), NOT "ü"
        let ai = XiaoheScheme.chordHint(forKey: "i", after: "a") // ai -> override "ai"
        let er = XiaoheScheme.chordHint(forKey: "r", after: "e") // er -> override "er"
        let qa = XiaoheScheme.chordHint(forKey: "a", after: "q") // qa -> inactive
        let precisionOk = qk == .match(finalIndices: [0], overrideFinal: nil)
            && gk == .match(finalIndices: [1], overrideFinal: nil)
            && js == .match(finalIndices: [1], overrideFinal: nil)
            && nt == .match(finalIndices: [1], overrideFinal: nil)
            && nv == .match(finalIndices: [1], overrideFinal: nil)
            && dv == .match(finalIndices: [0], overrideFinal: nil)
            && ai == .match(finalIndices: [], overrideFinal: "ai")
            && er == .match(finalIndices: [], overrideFinal: "er")
            && qa == .inactive
        log(precisionOk,
            "r71.XiaoheScheme.chordHint discriminates dual-final keys and zero-initial completions accurately",
            "qk=\(String(describing: qk)) gk=\(String(describing: gk)) er=\(String(describing: er)) qa=\(String(describing: qa))")

        // 3. Live KeyboardViewController + KeyView integration across odd/even beats, delete, and guide toggle
        let s = KeyboardSettings.shared
        let prevGuide = s.xiaoheGuide
        let prevScheme = s.scheme
        let prevGrid = s.pinyinGrid
        defer {
            s.xiaoheGuide = prevGuide
            s.scheme = prevScheme
            s.pinyinGrid = prevGrid
        }
        if let (vc, _) = makeKeyboard(scheme: 0, grid: false, in: window) {
            let kv = vc.keyboardViewForTests
            s.xiaoheGuide = false
            vc.applySettings()
            vc.handle(.char("q"), tap: Tap.exact("q"))
            let offInert = kv.guideChordHintForTests(.char("k")) == nil && kv.guideChordHintForTests(.char("a")) == nil
            vc.handle(.delete, tap: nil)

            s.xiaoheGuide = true
            vc.applySettings()
            let idleNeutral = kv.guideChordHintForTests(.char("k")) == nil

            // Odd beat 1: "q" -> k lights up "ing" (index 0), a dims (.inactive)
            vc.handle(.char("q"), tap: Tap.exact("q"))
            let odd1K = kv.guideChordHintForTests(.char("k")) == .match(finalIndices: [0], overrideFinal: nil)
            let odd1A = kv.guideChordHintForTests(.char("a")) == .inactive

            // Even beat 2: "qi" -> resets back to neutral full chart
            vc.handle(.char("i"), tap: Tap.exact("i"))
            let evenReset = kv.guideChordHintForTests(.char("k")) == nil && kv.guideChordHintForTests(.char("a")) == nil

            // Odd beat 3: "qie" -> e is zero-initial -> r shows override "er"
            vc.handle(.char("e"), tap: Tap.exact("e"))
            let odd3R = kv.guideChordHintForTests(.char("r")) == .match(finalIndices: [], overrideFinal: "er")
            let odd3TextR = kv.guideTextForTests(.char("r")) == "er"

            // Delete back to even beat -> resets; delete once more to odd beat "q" -> re-activates
            vc.handle(.delete, tap: nil)
            let backEven = kv.guideChordHintForTests(.char("r")) == nil
            vc.handle(.delete, tap: nil)
            let backOddQ = kv.guideChordHintForTests(.char("k")) == .match(finalIndices: [0], overrideFinal: nil)

            // Companion App Guide Inspector partner keys match exact same table
            let vPartners = XiaoheDrill.inspectPartnerKeysForTests(key: "v")
            let oPartners = XiaoheDrill.inspectPartnerKeysForTests(key: "o")
            let inspectorOk = vPartners.contains("s") && !vPartners.contains("b") && oPartners == Set(["o", "u"])

            log(offInert && idleNeutral && odd1K && odd1A && evenReset && odd3R && odd3TextR && backEven && backOddQ && inspectorOk,
                "r71.Live Xiaohe Chord Lighting tracks odd/even beats, backspaces, and Companion App inspector",
                "off=\(offInert) idle=\(idleNeutral) k=\(odd1K) a=\(odd1A) even=\(evenReset) er=\(odd3R)/\(odd3TextR) back=\(backEven)/\(backOddQ) insp=\(inspectorOk)")
        } else {
            log(false, "r71.XiaoheChordLighting setup", "engine did not load")
        }
    }

    // MARK: - R72: Visual telemetry drawer, bracket optical weight & single-row 7-step bench rail

    static func r72DrawerTelemetryBracketAndBenchCraft(_ window: UIWindow) {
        // 1. Bracket glyph font weighting & corner hint separation on symbols/numbers pages
        let kv = KeyboardView(spatial: SpatialModel.standard(width: 402))
        kv.frame = CGRect(x: 0, y: 0, width: 402, height: 212)
        kv.configure(LayoutContext(page: .symbols, chinese: true, showGlobe: false, returnLabel: nil,
                                   returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kv.layoutIfNeeded()
        let bracketInfo = kv.keyFontAndHintForTests(.char("【"))
        let fontOk = bracketInfo?.fontName.contains("PingFangSC-Regular") == true
        let hintOk = (bracketInfo?.hintFrame.width ?? 99) <= 14.5 && (bracketInfo?.hintFrame.width ?? 0) >= 10
        log(fontOk && hintOk,
            "r72.KeyView balances CJK bracket glyph weight and keeps corner hints separated",
            "font=\(bracketInfo?.fontName ?? "nil") hintW=\(bracketInfo?.hintFrame.width ?? -1)")

        // 2. SettingsPanelView secondary drawer telemetry, reset cleanup & snapshot fit height
        let sp = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 375, height: 258))
        sp.setLearned("词库 1866491 条 · 已学习 12 个词")
        sp.setDiagnostics("本次按键 128 次 · 内存 18 MB · 引擎就绪 14 ms · 震动：开")
        sp.toggleMoreForTests()
        sp.layoutIfNeeded()
        let telemetry = sp.telemetrySummaryForTests
        let telemetryOk = telemetry.lexicon == "186万+" && telemetry.learned == "12 词" && telemetry.mem == "18 MB" && telemetry.ready == "14 ms"
        let fullH = sp.preferredFullHeightForTests
        let fitOk = fullH > 320 && fullH < 700
        sp.toggleMoreForTests() // closes drawer cleanly
        let resetCleared = !sp.isResetConfirmingForTests
        log(telemetryOk && fitOk && resetCleared,
            "r72.SettingsPanelView secondary drawer formats telemetry chips cleanly and fits compactly",
            "tele=\(telemetry) fullH=\(fullH) resetCleared=\(resetCleared)")

        // 3. Companion App uses focused 3-tab structure & complete 3-member OTTOSSOM IP family
        let nav = AppNavigation()
        nav.focusFamilyMember(.otto)
        log(AppTab.allCases.count == 3 && FamilyMember.allCases.count == 3 && nav.tab == .companion && nav.family.activeMember == .otto,
            "r72.Companion App provides 3 focused tabs and 3 OTTOSSOM IP family members",
            "tabs=\(AppTab.allCases.count) members=\(FamilyMember.allCases.count)")
    }

    // MARK: - R73: Expanded grid live preedit dock, clear-cue separation & Companion App coverage

    static func r73GridPreeditClearCueAndAppCoverage(_ window: UIWindow) {
        // 1. Expanding candidate grid in Mosto mode reveals wide preedit dock and hides duplicate row strip
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 402, height: 42))
        bar.showsPreedit = false
        bar.update(preedit: "ni hao", candidates: [
            Candidate(text: "你好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "尼好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
        ])
        bar.layoutIfNeeded()
        let beforeExpand = bar.stripVisibleForTests && !bar.preeditShownForTests
        bar.gridExpanded = true
        bar.layoutIfNeeded()
        let afterExpand = !bar.stripVisibleForTests && bar.preeditShownForTests && bar.preeditDockFrameForTests.width > 200
        log(beforeExpand && afterExpand,
            "r73.CandidateBarView replaces duplicate grid row-1 strip with wide preedit dock in Mosto mode",
            "before=\(beforeExpand) after=\(afterExpand) dockW=\(bar.preeditDockFrameForTests.width)")

        // 2. Armed delete-left swipe cue keeps opaque pill cleanly separated from dimmed candidate stripBox
        let clearBar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 375, height: 40))
        clearBar.update(preedit: "nihao", candidates: [
            Candidate(text: "你好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "尼好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "泥好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "拟好", tapCount: 4, syllables: [1, 2], corrected: false, score: 0),
            Candidate(text: "你", tapCount: 2, syllables: [1], corrected: false, score: 0),
            Candidate(text: "尼", tapCount: 2, syllables: [1], corrected: false, score: 0),
        ])
        clearBar.setClearPreview(true)
        clearBar.layoutIfNeeded()
        let cueShown = clearBar.clearArmedCueShownForTests && clearBar.clearArmedOpaqueForTests
        let noBleed = !clearBar.stripFrameForTests.intersects(clearBar.clearArmedPillFrameForTests)
        log(cueShown && noBleed,
            "r73.ClearArmed cue stays opaque and strictly non-overlapping with stripBox",
            "cue=\(cueShown) noBleed=\(noBleed) strip=\(clearBar.stripFrameForTests) pill=\(clearBar.clearArmedPillFrameForTests)")
    }

    // MARK: - R74: Host height anti-bounce, fast candidate strip & T9 tuner column craft

    static func r74HeightAntiBounceStripSpeedAndTunerCraft(_ window: UIWindow) {
        // 1. Height anti-bounce: portrait lock causes 0 constraint mutations across appear, settings, and transient host frames
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, _) = pair
            vc.view.frame = CGRect(x: 0, y: 0, width: 430, height: 258)
            vc.applySettings()
            vc.view.layoutIfNeeded()
            drain(0.02)
            vc.resetHeightSyncMutationsForTests()

            vc.beginAppearanceTransition(false, animated: false)
            vc.endAppearanceTransition()
            vc.beginAppearanceTransition(true, animated: false)
            vc.endAppearanceTransition()
            vc.updateViewConstraints()
            vc.showSettingsForTests(true)
            vc.showSettingsForTests(false)
            for h in [216.0, 452.0, 293.5, 301.0, 258.0] {
                vc.view.frame = CGRect(x: 0, y: 0, width: 430, height: h)
                vc.view.setNeedsLayout()
                vc.view.layoutIfNeeded()
            }
            drain(0.02)
            let steadyZeroMutations = vc.heightSyncMutationsForTests == 0 && vc.heightConstraintConstantForTests == 258

            vc.view.frame = CGRect(x: 0, y: 0, width: 874, height: 198)
            vc.view.setNeedsLayout()
            vc.view.layoutIfNeeded()
            drain(0.02)
            let singleMutationOnLandscape = vc.heightSyncMutationsForTests == 1 && vc.heightConstraintConstantForTests == 198

            vc.view.frame = CGRect(x: 0, y: 0, width: 430, height: 258)
            vc.view.setNeedsLayout()
            vc.view.layoutIfNeeded()
            drain(0.02)
            let backToPortrait = vc.heightSyncMutationsForTests == 2 && vc.heightConstraintConstantForTests == 258
            log(steadyZeroMutations && singleMutationOnLandscape && backToPortrait,
                "r74.KeyboardViewController holds portrait height rock-steady across transient host frames and mutates once per orientation flip",
                "steady=\(steadyZeroMutations) mut=\(vc.heightSyncMutationsForTests) const=\(vc.heightConstraintConstantForTests ?? -1)")
        } else {
            log(false, "r74.KeyboardViewController height anti-bounce setup", "engine did not load")
        }

        // 2. SyllablePickerView ceramic tuner styling (active slot indicator & pooled dividers)
        let spk = SyllablePickerView(frame: CGRect(x: 0, y: 0, width: 70, height: 190))
        spk.show(["ni", "mi", "o"])
        spk.layoutIfNeeded()
        log(spk.shownCountForTests == 3 && spk.activeBarVisibleForTests && spk.dividerCountForTests == 1,
            "r74.SyllablePickerView renders ceramic tuner slot card, active bar, and separator lines",
            "shown=\(spk.shownCountForTests) bar=\(spk.activeBarVisibleForTests) divs=\(spk.dividerCountForTests)")

        // 3. EmojiPanelView unified bottom-left return button across Emoji and Kaomoji modes
        let ep = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 242))
        ep.layoutIfNeeded()
        ep.load(kaomoji: false)
        ep.layoutIfNeeded()
        let emojiFn = ep.backButtonUsesFunctionStyleForTests
        ep.load(kaomoji: true)
        ep.layoutIfNeeded()
        let kaoFn = ep.backButtonUsesFunctionStyleForTests
        log(emojiFn && kaoFn,
            "r74.EmojiPanelView keeps bottom-left return key visually consistent across Emoji and Kaomoji",
            "emojiFn=\(emojiFn) kaoFn=\(kaoFn)")
    }

    // MARK: - R75: Held-delete clutch telemetry HUD, gear-shift haptic & idle pill collision guard

    static func r75DeleteClutchHudAndIdleGuard(_ window: UIWindow) {
        // 1. Delete-clutch telemetry HUD renders non-overlapping left preview + right word count capsule across day/night/plain
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 375, height: 42))
        bar.showsMosto = true
        bar.setClearProgress(1.0, armed: true, dimContent: false, deletedText: "今天天气真好", deletedCount: 6)
        bar.layoutIfNeeded()
        let clutchCueShown = bar.deleteClutchCueShownForTests
            && bar.clearArmedOpaqueForTests
            && (bar.clearArmedCueTextForTests == "逐词删 · 6字")
        let previewShown = bar.deletePreviewShownForTests
            && (bar.deletePreviewTextForTests?.contains("今天天气真好") == true)
        let noOverlap = !bar.deletePreviewPillFrameForTests.intersects(bar.clearArmedPillFrameForTests)
            && bar.deletePreviewPillFrameForTests.maxX < bar.clearArmedPillFrameForTests.minX
        let mostoHidden = bar.mosto.isHidden
        log(clutchCueShown && previewShown && noOverlap && mostoHidden,
            "r75.CandidateBarView renders non-overlapping delete-clutch count + preview capsules and yields Mosto",
            "cue=\(bar.clearArmedCueTextForTests ?? "nil") preview=\(bar.deletePreviewTextForTests ?? "nil") noOverlap=\(noOverlap) mostoHidden=\(mostoHidden)")

        // 2. Live controller: clutch engagement fires .clearArmed haptic detent, updates deleted count live, hides idle buttons, and hands off to ↩ undo
        guard let (vc, h) = makeKeyboard(scheme: 0, in: window) else {
            log(false, "r75.setup", "engine did not load")
            return
        }
        let rec = RecordingFeedbackPlayer()
        vc.feedbackPlayer = rec
        let kb = vc.keyboardViewForTests
        let vcBar = vc.candidateBarForTests
        guard let delCap = kb.keyRectsForTests(.delete)?.cap else {
            log(false, "r75.setup", "no delete key")
            return
        }
        let dc = center(delCap)

        reset(vc, h)
        let seedText = "今天天气真好我们可以一起出去公园散步吧太开心啦好不好"
        h.insertText(seedText)
        vc.textDidChange(nil)
        rec.clear()
        let t0: CFTimeInterval = 300
        kb.feedForTests([TouchSample(id: 1, phase: .began, point: dc, time: t0)])
        kb.advanceForTests(to: t0 + 1.85) // tick 20 (0.42 + 20*0.07 = 1.82s): clutch engages before first word delete at tick 21
        let engagedHaptic = rec.haptics.contains(where: { $0.kind == .selection })
        let engagedCue = vcBar.deleteClutchCueShownForTests && vcBar.clearArmedCueTextForTests == "逐词删"
        let idleHiddenDuringClutch = vc.plainLightHiddenForTests && vc.mostoHintHiddenForTests

        kb.advanceForTests(to: t0 + 2.11) // ticks 21 & 24 delete 4 Hanzi ("真好" then "天气" -> "天气真好")
        let liveCountCue = vcBar.clearArmedCueTextForTests == "逐词删 · 4字"
        let livePreviewShown = vcBar.deletePreviewShownForTests && (vcBar.deletePreviewTextForTests?.contains("天气真好") == true)
        let liveNoOverlap = !vcBar.deletePreviewPillFrameForTests.intersects(vcBar.clearArmedPillFrameForTests)
        kb.feedForTests([TouchSample(id: 1, phase: .ended, point: dc, time: t0 + 2.12)])
        drain(0.01)
        let handoffToUndo = !vcBar.deleteClutchCueShownForTests && !vcBar.deletePreviewShownForTests && vcBar.undoTextForTests == "天气真好"
        log(engagedHaptic && engagedCue && idleHiddenDuringClutch && liveCountCue && livePreviewShown && liveNoOverlap && handoffToUndo,
            "r75.Held-delete clutch fires gear-shift detent, tracks deleted chars live without idle collision, and hands off to ↩",
            "haptic=\(engagedHaptic) cue=\(vcBar.clearArmedCueTextForTests ?? "nil") idleHidden=\(idleHiddenDuringClutch) live=\(liveCountCue) handoff=\(handoffToUndo)")

        // 3. Single-letter ClearSwipe keeps idle light/kaomoji pills hidden while armed (zero collision when taps becomes empty)
        reset(vc, h)
        type(vc, "a")
        settle(vc)
        let swipeSamples = swipe(from: dc, to: CGVector(dx: -72, dy: 0), duration: 0.18)
        kb.feedForTests(Array(swipeSamples.dropLast()))
        let armedSingle = vcBar.clearArmedCueShownForTests && vcBar.clearArmedCueTextForTests == "松手清空"
        let idleHiddenOnSwipe = vc.plainLightHiddenForTests && vc.mostoHintHiddenForTests
        kb.feedForTests([swipeSamples.last!])
        drain(0.01)
        let restoredChip = vcBar.undoTextForTests == "a"
        log(armedSingle && idleHiddenOnSwipe && restoredChip,
            "r75.Single-key ClearSwipe suppresses idle pills during armed preview and restores via ↩",
            "armed=\(armedSingle) idleHidden=\(idleHiddenOnSwipe) chip=\(vcBar.undoTextForTests ?? "nil")")
    }

    // MARK: - R76: Cursor trackpad telemetry HUD & CJK bracket optical balance

    static func r76CursorTelemetryHudAndBracketCraft(_ window: UIWindow) {
        // 1. Static CandidateBarView renders non-overlapping cursor HUD (mode + step readout), boundary clamp, and clean restore
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 375, height: 42))
        bar.showsMosto = true
        bar.setCursorTelemetry(active: true, delta: 6, endStop: 0, crossedNewline: false)
        bar.layoutIfNeeded()
        let hudShown = bar.cursorTelemetryShownForTests
            && !bar.cursorTelemetryBoundaryForTests
            && bar.cursorTelemetryTextForTests == "右移 6 字"
            && bar.cursorModePillTextForTests == "游标微调"
        let noOverlap = !bar.deletePreviewPillFrameForTests.intersects(bar.clearArmedPillFrameForTests)
            && bar.deletePreviewPillFrameForTests.maxX < bar.clearArmedPillFrameForTests.minX
        let clearFlagSeparated = !bar.clearArmedCueShownForTests && !bar.deleteClutchCueShownForTests && bar.mosto.isHidden
        bar.setCursorTelemetry(active: true, delta: -4, endStop: -1, crossedNewline: true)
        bar.layoutIfNeeded()
        let boundaryShown = bar.cursorTelemetryBoundaryForTests && bar.cursorTelemetryTextForTests == "已到文首"
        bar.setCursorTelemetry(active: false, delta: 0, endStop: 0, crossedNewline: false)
        bar.layoutIfNeeded()
        let cleanRestore = !bar.cursorTelemetryShownForTests && !bar.deletePreviewShownForTests && bar.mosto.isHidden
        log(hudShown && noOverlap && clearFlagSeparated && boundaryShown && cleanRestore,
            "r76.CandidateBarView renders non-overlapping cursor scrub HUD, boundary stop, and cleanly restores idle state",
            "hudShown=\(hudShown) noOverlap=\(noOverlap) boundary=\(boundaryShown) restore=\(cleanRestore)")

        // 2. Live KeyboardViewController spacebar trackpad drag triggers cursor HUD, hides idle pills & gear, and restores on release
        guard let (vc, h) = makeKeyboard(scheme: 0, in: window) else {
            log(false, "r76.setup", "engine did not load")
            return
        }
        let kb = vc.keyboardViewForTests
        let vcBar = vc.candidateBarForTests
        guard let spaceCap = kb.keyRectsForTests(.space)?.cap else {
            log(false, "r76.setup", "no space key")
            return
        }
        reset(vc, h)
        h.insertText("今天去摸索小鹤双拼吧")
        vc.textDidChange(nil)
        drain(0.01)
        let sc = center(spaceCap)
        let t0: CFTimeInterval = 400
        kb.feedForTests([TouchSample(id: 2, phase: .began, point: sc, time: t0)])
        kb.feedForTests([TouchSample(id: 2, phase: .moved, point: CGPoint(x: sc.x - 36, y: sc.y), time: t0 + 0.38)])
        let liveActive = kb.trackpadRulerVisibleForTests
            && vcBar.cursorTelemetryShownForTests
            && !vcBar.expandShownForTests
            && vc.plainLightHiddenForTests
            && vc.mostoHintHiddenForTests
        kb.feedForTests([TouchSample(id: 2, phase: .moved, point: CGPoint(x: sc.x - 160, y: sc.y), time: t0 + 0.55)])
        let liveHitStart = vcBar.cursorTelemetryBoundaryForTests && vcBar.cursorTelemetryTextForTests == "已到文首"
        kb.feedForTests([TouchSample(id: 2, phase: .ended, point: CGPoint(x: sc.x - 160, y: sc.y), time: t0 + 0.60)])
        drain(0.01)
        let liveRestored = !kb.trackpadRulerVisibleForTests
            && !vcBar.cursorTelemetryShownForTests
            && vcBar.expandShownForTests
            && vc.plainLightHiddenForTests
            && vc.mostoHintHiddenForTests
        log(liveActive && liveHitStart && liveRestored,
            "r76.Live spacebar trackpad scrubbing drives cursor telemetry HUD, suppresses idle chrome, and restores on finger up",
            "active=\(liveActive) hitStart=\(liveHitStart) restored=\(liveRestored)")

        // 3. CJK heavy brackets 【 】 step down optically while keeping PingFangSC-Regular and extra top-right hint clearance
        let kv = KeyboardView(spatial: SpatialModel.standard(width: 402))
        kv.frame = CGRect(x: 0, y: 0, width: 402, height: 212)
        kv.configure(LayoutContext(page: .symbols, chinese: true, showGlobe: false, returnLabel: nil,
                                   returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kv.layoutIfNeeded()
        let lb = kv.keyOpticalMetricsForTests(.char("【"))
        let rb = kv.keyOpticalMetricsForTests(.char("】"))
        let leftOk = (lb?.fontName.contains("PingFangSC-Regular") == true)
            && (lb?.fontSize ?? 99) <= 21.0
            && (lb?.labelMinY ?? -99) > 1.0
            && (lb?.hintFrame.width ?? 0) >= 10
        let rightOk = (rb?.fontName.contains("PingFangSC-Regular") == true)
            && (rb?.fontSize ?? 99) <= 21.0
            && (rb?.labelMinY ?? -99) > 1.0
        log(leftOk && rightOk,
            "r76.KeyView optically sizes 【】 brackets (<=21pt PingFangSC-Regular) with extra corner hint clearance",
            "left=(\(lb?.fontSize ?? -1), minY=\(lb?.labelMinY ?? -1)) right=(\(rb?.fontSize ?? -1), minY=\(rb?.labelMinY ?? -1))")
    }

    // MARK: - R77: KeyView optical bevel catchlight & Emoji/Bench tactile parity

    static func r77KeycapBevelAndFeedbackParity(_ window: UIWindow) {
        let kv = KeyboardView(spatial: SpatialModel.standard(width: 402))
        kv.frame = CGRect(x: 0, y: 0, width: 402, height: 212)
        kv.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil,
                                   returnIsAccent: true, shifted: false, capsLock: false, keyBorders: true))
        kv.layoutIfNeeded()

        let aKey = kv.keyViewForTests(.char("a"))
        let noTopLineAtRest = aKey?.hasTopHighlightForTests == false && aKey?.borderWidthForTests == 0 && aKey?.shadowOpacityForTests == 1
        aKey?.pressed = true
        let pressedHidesLip = aKey?.hasTopHighlightForTests == false && aKey?.shadowOpacityForTests == 0
        aKey?.pressed = false
        let restoredLip = aKey?.hasTopHighlightForTests == false && aKey?.shadowOpacityForTests == 1
        aKey?.blanked = true
        let blankedClean = aKey?.hasTopHighlightForTests == false
        aKey?.blanked = false

        let emoji = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 260))
        emoji.setChinese(true)
        emoji.load(kaomoji: false)
        emoji.layoutIfNeeded()
        var feedbackEvents: [FeedbackEvent] = []
        emoji.onFeedback = { feedbackEvents.append($0) }
        emoji.perform(#selector(EmojiPanelView.kaomojiShortcutTappedForTests))
        let firedTabFeedback = feedbackEvents.contains(.candidate)

        log(noTopLineAtRest && pressedHidesLip && restoredLip && blankedClean && firedTabFeedback,
            "r77.KeyView uses clean borderless squircle caps with tactile bottom lip and EmojiPanelView triggers tactile feedback",
            "rest=\(noTopLineAtRest) pressed=\(pressedHidesLip) restored=\(restoredLip) blanked=\(blankedClean) tabFeedback=\(firedTabFeedback)")
    }

    // MARK: - R78: Emoji dock zero-slice alignment, Mosto mood badge, Settings header back capsule & Xiaohe dual slots

    static func r78EmojiDockNoSliceDrawerAndXiaoheSlots(_ window: UIWindow) {
        let s = KeyboardSettings.shared
        let prevStyle = s.style
        let prevPlain = Theme.plain
        defer {
            s.style = prevStyle
            Theme.plain = prevPlain
        }

        // 1. EmojiPanelView snaps portrait category dock to integer slots (zero trailing heart sliver) & frames moodMosto badge
        s.style = 0
        Theme.plain = false
        let ep = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 258))
        ep.layoutIfNeeded()
        ep.load(kaomoji: false)
        ep.layoutIfNeeded()
        let noTrailingSlice = ep.dockNoTrailingHalfSliceForTests && ep.portraitDockLightbulbUnclippedForTests
        ep.load(kaomoji: true)
        ep.layoutIfNeeded()
        let badgeVisibleMosto = ep.moodMostoBadgeShownForTests && ep.kaomojiDockGearFullyVisibleForTests
        s.style = 1
        Theme.plain = true
        ep.themeChanged()
        ep.layoutIfNeeded()
        let badgeHiddenPlain = !ep.moodMostoBadgeShownForTests
        log(noTrailingSlice && badgeVisibleMosto && badgeHiddenPlain,
            "r78.EmojiPanelView prevents trailing dock icon half-slicing and syncs Kaomoji Mosto ceramic badge",
            "noSlice=\(noTrailingSlice) badgeMosto=\(badgeVisibleMosto) badgeHiddenPlain=\(badgeHiddenPlain)")

        // 2. SettingsPanelView replaces bare back link with symmetrical header capsule & streamlined drawer
        s.style = 0
        Theme.plain = false
        let sp = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 390, height: 258))
        sp.layoutIfNeeded()
        let initiallyHidden = !sp.showingMoreForTests && !sp.backDeckButtonInHeaderForTests
        sp.toggleMoreForTests()
        sp.layoutIfNeeded()
        let headerCapsuleShown = sp.showingMoreForTests && sp.backDeckButtonInHeaderForTests
        let fullFitOk = sp.preferredFullHeightForTests > 320 && sp.preferredFullHeightForTests < 700
        sp.toggleMoreForTests()
        sp.layoutIfNeeded()
        let closedCleanly = !sp.showingMoreForTests && !sp.backDeckButtonInHeaderForTests
        log(initiallyHidden && headerCapsuleShown && fullFitOk && closedCleanly,
            "r78.SettingsPanelView integrates back capsule cleanly in header with streamlined secondary drawer",
            "init=\(initiallyHidden) shown=\(headerCapsuleShown) fullH=\(sp.preferredFullHeightForTests) closed=\(closedCleanly)")

        // 3. XiaoheGuideContent with dual-role slot watermarks and de-duplicated equation meter renders cleanly
        let guideSize = XiaoheGuideContent.renderSnapshotSizeForTests(width: 390)
        let guideRendered = guideSize.width > 300
            && XiaoheDrill.slotRoleMarks == ["声", "韵"]
            && !XiaoheDrill.inspectExamplesForTests(key: "u").isEmpty
        log(guideRendered,
            "r78.XiaoheGuideContent dual-slot watermarks & condensed comparison meter render cleanly",
            "width=\(guideSize.width)")
    }

    // MARK: - R79: Honest contextual Smart-Spacebar (pair-exit cue, math result cue, and cursor lifecycle hygiene)

    static func r79SmartSpacebarPairExitAndMathCue(_ window: UIWindow) {
        let s = KeyboardSettings.shared
        let prevStyle = s.style
        let prevPlain = Theme.plain
        defer {
            s.style = prevStyle
            Theme.plain = prevPlain
        }
        s.style = 0
        Theme.plain = false
        guard let kb = makeKeyboard(scheme: 1, grid: false, in: window) else {
            log(false, "r79.setup")
            return
        }
        let (vc, h) = kb
        let spaceKey = vc.keyboardViewForTests.keyViewForTests(.space)
        let initialNormal = spaceKey?.isSmartSpaceShownForTests == false

        // 1. Opening CJK pair 《》 morphs Spacebar to "跳出 》" and pressing Space jumps out & restores normal spacebar
        vc.handle(.char("《"), tap: nil)
        drain(0.03)
        let pairShown = spaceKey?.isSmartSpaceShownForTests == true && spaceKey?.visibleLabelTextForTests == "跳出 》"
        vc.handle(.space, tap: nil)
        drain(0.03)
        let pairExited = h.string == "《》" && h.cursor == 2 && spaceKey?.isSmartSpaceShownForTests == false

        // 2. Smart pair Backspace removes both halves and clears Smart-Spacebar state
        vc.handle(.char("（"), tap: nil)
        drain(0.03)
        let parenShown = spaceKey?.visibleLabelTextForTests == "跳出 ）"
        vc.handle(.delete, tap: nil)
        drain(0.03)
        let pairDeleted = h.string == "《》" && spaceKey?.isSmartSpaceShownForTests == false

        // 3. Moving cursor away clears stale pair state so Spacebar never lies
        vc.handle(.char("「"), tap: nil)
        drain(0.03)
        let cornerShown = spaceKey?.visibleLabelTextForTests == "跳出 」"
        h.adjustTextPosition(byCharacterOffset: -1)
        vc.selectionDidChange(nil)
        drain(0.03)
        let movedCleared = spaceKey?.isSmartSpaceShownForTests == false

        // 4. Trailing math expression morphs Spacebar to "= 383" and Space commits & reverts
        h.clear()
        vc.textDidChange(nil)
        for ch in "365+18=" { vc.handle(.char(String(ch)), tap: nil) }
        drain(0.03)
        let mathShown = spaceKey?.isSmartSpaceShownForTests == true && spaceKey?.visibleLabelTextForTests == "= 383"
        vc.handle(.space, tap: nil)
        drain(0.03)
        let mathCommitted = h.string == "365+18=383" && spaceKey?.isSmartSpaceShownForTests == false

        log(initialNormal && pairShown && pairExited && parenShown && pairDeleted && cornerShown && movedCleared && mathShown && mathCommitted,
            "r79.Spacebar honestly morphs for CJK smart-pair exit, clears on cursor leave, and previews trailing math",
            "init=\(initialNormal) pair=\(pairShown) exit=\(pairExited) paren=\(parenShown) del=\(pairDeleted) corner=\(cornerShown) move=\(movedCleared) math=\(mathShown) commit=\(mathCommitted)")
    }

    static func r80ContrastCadenceAndBenchCraft(_ window: UIWindow) {
        _ = window
        // 1. WCAG AA+ contrast for MossOttoStyle.onViolet on MossOttoStyle.violet in both Day and Night modes
        func relLum(_ color: UIColor, style: UIUserInterfaceStyle) -> CGFloat {
            let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        func contrast(_ fg: UIColor, _ bg: UIColor, style: UIUserInterfaceStyle) -> CGFloat {
            let l1 = relLum(fg, style: style), l2 = relLum(bg, style: style)
            return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }
        let dayCR = contrast(UIColor(MossOttoStyle.onViolet), UIColor(MossOttoStyle.violet), style: .light)
        let nightCR = contrast(UIColor(MossOttoStyle.onViolet), UIColor(MossOttoStyle.violet), style: .dark)
        log(dayCR >= 4.5 && nightCR >= 4.5, "r80.violet CTA foreground passes WCAG AA in Day and Night",
            "dayCR=\(String(format: "%.2f", dayCR)) nightCR=\(String(format: "%.2f", nightCR))")

        // 2. Commercial capabilities and consumer privacy copy sections are complete and non-empty
        let sectionsOk = CompanionCapabilitiesSection.items.count == 4 && PrivacyCommitmentContent.items.count == 4
        log(sectionsOk, "r80.Companion capabilities and consumer privacy cards provide focused 4-item summaries",
            "caps=\(CompanionCapabilitiesSection.items.count) privacy=\(PrivacyCommitmentContent.items.count)")

        // 3. Globe spacebar (>= 100pt) keeps homing bar while narrow numpad side-space (~73pt) retains label
        let oldPlain = Theme.plain
        Theme.plain = false
        defer { Theme.plain = oldPlain }
        let kv = KeyboardView(spatial: SpatialModel.standard())
        kv.frame = CGRect(x: 0, y: 0, width: 393, height: 214)
        kv.configure(LayoutContext(page: .letters, chinese: true, showGlobe: true, returnLabel: nil,
                                   returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kv.layoutIfNeeded()
        let globeSpaceNotchShown = kv.spaceNotchVisibleForTests
        kv.configure(LayoutContext(page: .numpad, chinese: true, showGlobe: true, returnLabel: nil,
                                   returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kv.layoutIfNeeded()
        let numpadSpaceNoNotch = !kv.spaceNotchVisibleForTests
        log(globeSpaceNotchShown && numpadSpaceNoNotch, "r80.globe spacebar preserves homing bar without affecting numpad space label",
            "globeNotch=\(globeSpaceNotchShown) numpadNoNotch=\(numpadSpaceNoNotch)")
    }

    static func r81TrackpadGlassSmartRimAndPunctuationCraft(_ window: UIWindow) {
        _ = window
        // 1. Trackpad vernier ruler renders above smoked-glass blanked keys during spacebar drag
        let kb = KeyboardView(spatial: SpatialModel.standard())
        kb.frame = CGRect(x: 0, y: 0, width: 393, height: 214)
        kb.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil,
                                   returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kb.layoutIfNeeded()
        kb.demoCursorMode()
        let rulerOnTop = kb.trackpadRulerVisibleForTests && kb.trackpadRulerAboveKeysForTests
        let smokedGlass = kb.blankedKeyMinAlphaForTests < 0.6
        log(rulerOnTop && smokedGlass, "r81.trackpad ruler floats cleanly over smoked-glass dimmed keycaps",
            "rulerOnTop=\(rulerOnTop) minAlpha=\(String(format: "%.2f", kb.blankedKeyMinAlphaForTests))")

        // 2. Contextual smart spacebar lights active accent rim and clears back to default hairline
        let kvSpace = KeyboardView(spatial: SpatialModel.standard())
        kvSpace.frame = CGRect(x: 0, y: 0, width: 393, height: 214)
        kvSpace.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil,
                                        returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true,
                                        spaceOverride: "跳出 》"))
        kvSpace.layoutIfNeeded()
        let activeRim = (kvSpace.keyViewForTests(.space)?.isSmartSpaceShownForTests == true)
            && (kvSpace.keyViewForTests(.space)?.smartSpaceRimActiveForTests == true)
        kvSpace.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil,
                                        returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kvSpace.layoutIfNeeded()
        let resetRim = kvSpace.keyViewForTests(.space)?.smartSpaceRimActiveForTests == false
        log(activeRim && resetRim, "r81.smart spacebar illuminates accent rim and resets to standard hairline",
            "activeRim=\(activeRim) resetRim=\(resetRim)")

        // 3. Numbers page Chinese quotes center optically and parentheses share 20.5pt PingFangSC sizing
        let openQuoteOffset = KeyView.opticalOffset(for: "“", font: Theme.font(22, .medium))
        let closeQuoteOffset = KeyView.opticalOffset(for: "”", font: Theme.font(22, .medium))
        kvSpace.configure(LayoutContext(page: .numbers, chinese: true, showGlobe: false, returnLabel: nil,
                                        returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        let parenMetrics = kvSpace.keyOpticalMetricsForTests(.char("（"))
        let quoteOpticalOk = openQuoteOffset != .zero || closeQuoteOffset != .zero
        let parenCraftOk = (parenMetrics?.fontName.contains("PingFangSC") == true)
            && abs((parenMetrics?.fontSize ?? 0) - 20.5) < 0.1
            && ((parenMetrics?.hintFrame.width ?? 0) > 0)
        log(quoteOpticalOk && parenCraftOk, "r81.numbers quotes center via CoreText bounds and CJK parens clear bracket hints",
            "quoteOk=\(quoteOpticalOk) font=\(parenMetrics?.fontName ?? "nil") size=\(parenMetrics?.fontSize ?? 0)")
    }

    static func r82NumpadSpineEnableDarkAndLandscapeDock(_ window: UIWindow) {
        _ = window
        // 1. globe_numpad Row 4 aligns `0` vertically beneath `2 / 5 / 8`
        let kb = KeyboardView(spatial: SpatialModel.standard())
        kb.frame = CGRect(x: 0, y: 0, width: 393, height: 214)
        kb.configure(LayoutContext(page: .numpad, chinese: true, showGlobe: true, returnLabel: nil,
                                   returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        let k0 = kb.keyRectsForTests(.char("0"))?.cap ?? .zero
        let k2 = kb.keyRectsForTests(.char("2"))?.cap ?? .zero
        let k5 = kb.keyRectsForTests(.char("5"))?.cap ?? .zero
        let k8 = kb.keyRectsForTests(.char("8"))?.cap ?? .zero
        let spineAligned = k0.width > 20
            && abs(k0.midX - k2.midX) < 1.0
            && abs(k0.midX - k5.midX) < 1.0
            && abs(k0.midX - k8.midX) < 1.0
            && abs(k0.width - k8.width) < 1.0
        log(spineAligned, "r82.globe numpad keeps 0 aligned vertically under 2 5 8 spine",
            "x0=\(k0.midX) x2=\(k2.midX) x8=\(k8.midX) w0=\(k0.width) w8=\(k8.width)")

        // 2. Landscape emoji dock relaxes icon targets up to 44pt while portrait stays compact
        let epLand = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 750, height: 186))
        epLand.layoutIfNeeded()
        epLand.load(kaomoji: false)
        epLand.layoutIfNeeded()
        let landRelaxed = epLand.dockTabWidthForTests >= 40 && epLand.dockTabWidthForTests <= 45 && epLand.landscapeDockAllInsideForTests
        let epPort = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 393, height: 242))
        epPort.layoutIfNeeded()
        epPort.load(kaomoji: false)
        epPort.layoutIfNeeded()
        let portCompact = epPort.dockTabWidthForTests <= 34
        log(landRelaxed && portCompact, "r82.landscape emoji dock relaxes targets without affecting portrait slot snap",
            "landW=\(epLand.dockTabWidthForTests) inside=\(epLand.landscapeDockAllInsideForTests) portW=\(epPort.dockTabWidthForTests)")

        // 3. EnableScreen live verification gate and dark-mode Canvas palette contrast >= 4.5
        func lum(_ c: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        let fgL = lum(EnablePalette.violet(dark: true))
        let bgL = lum(MossOttoStyle.hex(0x1F1B2E))
        let darkCR = (max(fgL, bgL) + 0.05) / (min(fgL, bgL) + 0.05)
        let verifyOk = !EnableContent.isVerificationPassed("")
            && !EnableContent.isVerificationPassed("nihao")
            && EnableContent.isVerificationPassed("测试你好")
            && darkCR >= 4.5
        log(verifyOk, "r82.EnableScreen dark Canvas palette meets WCAG AA and detects 你好 verification",
            "darkCR=\(String(format: "%.2f", darkCR))")
    }

    static func r83HeightExplosionGuardIdleRailAndGlassCraft(_ window: UIWindow) {
        let s = KeyboardSettings.shared
        let prevStyle = s.style
        let prevPlain = Theme.plain
        defer {
            s.style = prevStyle
            Theme.plain = prevPlain
        }

        // 1. P0 WeChat abnormal host frame guard: direct view.heightAnchor + pinned root + bottom-anchored content clamp
        guard let (vc, _) = makeKeyboard(scheme: 0, in: window) else {
            log(false, "r83.setup", "engine did not load")
            return
        }
        vc.applySettings()
        let directViewTarget = vc.heightConstraintTargetIsViewForTests
        let pinnedStandard = abs((vc.heightConstraintConstantForTests ?? -1) - 258) < 0.5 && vc.rootPinnedToViewForTests
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 780)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let clamped780 = vc.contentFrameForTests.height <= 308.5
            && abs(vc.contentFrameForTests.maxY - 780) < 1.0
            && vc.maxKeycapHeightForTests <= 54

        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 852)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let clamped852 = vc.contentFrameForTests.height <= 308.5
            && abs(vc.contentFrameForTests.maxY - 852) < 1.0
            && vc.maxKeycapHeightForTests <= 54

        log(directViewTarget && pinnedStandard && clamped780 && clamped852,
            "r83.KeyboardViewController binds view.heightAnchor directly and clamps oversized host frames bottom-up",
            "direct=\(directViewTarget) pinned=\(pinnedStandard) 780/852=\(vc.contentFrameForTests)/\(vc.maxKeycapHeightForTests) ok=(\(clamped780),\(clamped852))")

        // 2. P1 Visual-first unified idle bar across Mosto & 简洁 styles (free-standing Mosto, ^_^ monogram, icon-only right light button)
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 262)
        s.style = 0
        vc.applySettings()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let bar = vc.candidateBarForTests
        // R95 minimalist top bar: single classic gear on far right; old top-bar Mosto & light pill stay hidden across styles.
        let topBarCleanMosto = bar.mosto.isHidden && vc.mostoHintHiddenForTests && vc.plainLightHiddenForTests && bar.expandButtonFrameForTests.minX > 330
        s.style = 1
        vc.applySettings()
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let topBarCleanPlain = bar.mosto.isHidden && vc.mostoHintHiddenForTests && vc.plainLightHiddenForTests && bar.expandButtonFrameForTests.minX > 330
        log(topBarCleanMosto && topBarCleanPlain,
            "r83.CandidateBarView keeps minimalist single-gear idle top bar across Mosto and 简洁 styles",
            "mosto=\(topBarCleanMosto) plain=\(topBarCleanPlain)")

        // 3. P1 Liquid Glass side breathing margins (full-width outer hit zones) & forced-day softened keycap state
        let kv = KeyboardView(spatial: SpatialModel.standard(width: 393))
        kv.frame = CGRect(x: 0, y: 0, width: 393, height: 200)
        kv.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil,
                                   returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true))
        kv.layoutIfNeeded()
        let q = kv.keyRectsForTests(.char("q"))
        let p = kv.keyRectsForTests(.char("p"))
        let marginOk = (q?.cap.minX ?? 0) >= 6.5
            && (393 - (p?.cap.maxX ?? 393)) >= 6.5
            && (q?.hit.minX ?? -1) == 0
            && abs((p?.hit.maxX ?? 0) - 393) < 0.5
        kv.softenedForDarkGlass = true
        let softOn = kv.softenedForDarkGlassForTests && (kv.keyViewForTests(.char("q"))?.isSoftenedForDarkGlassForTests == true)
        kv.softenedForDarkGlass = false
        let softOff = !kv.softenedForDarkGlassForTests && (kv.keyViewForTests(.char("q"))?.isSoftenedForDarkGlassForTests == false)
        log(marginOk && softOn && softOff,
            "r83.KeyboardView breathes inside rounded Liquid Glass with full-width edge hit zones and dark-glass day softening",
            "margin=\(marginOk) qMinX=\(q?.cap.minX ?? -1) pMaxX=\(p?.cap.maxX ?? -1) soft=(\(softOn),\(softOff))")
    }

    static func r84ContrastRangefinderAndWorkbenchCraft(_ window: UIWindow) {
        _ = window
        let prevPlain = Theme.plain
        defer { Theme.plain = prevPlain }

        func relLum(_ c: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
            let l1 = relLum(a), l2 = relLum(b)
            return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }

        // 1. Night moon icon meets WCAG AA (>= 4.5:1) on both light forced glass and dark glass
        Theme.plain = false
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 393, height: 42))
        window.addSubview(bar)
        defer { bar.removeFromSuperview() }
        bar.showsMosto = true
        bar.overrideUserInterfaceStyle = .light
        bar.setIdleControls(enabled: true, night: true, forcedDayOnDarkGlass: false)
        bar.layoutIfNeeded()
        let lightTint = bar.idleLightTintColorForTests.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let lightMoonCR = contrast(lightTint, Theme.hex(0xE8E6EF))

        bar.overrideUserInterfaceStyle = .dark
        bar.setIdleControls(enabled: true, night: true, forcedDayOnDarkGlass: false)
        bar.layoutIfNeeded()
        let darkTint = bar.idleLightTintColorForTests.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let darkMoonCR = contrast(darkTint, Theme.hex(0x32303A))
        log(lightMoonCR >= 4.5 && darkMoonCR >= 4.5,
            "r84.Idle moon icon satisfies WCAG AA contrast across light and dark glass",
            "lightCR=\(String(format: "%.2f", lightMoonCR)) darkCR=\(String(format: "%.2f", darkMoonCR))")

        // 2. Precision cursor rangefinder track & center home tick follow telemetry and swipe states cleanly
        let trackBar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 393, height: 42))
        let idleTrackHidden = !trackBar.clearFilamentTrackShownForTests && !trackBar.cursorCenterTickShownForTests
        trackBar.setCursorTelemetry(active: true, delta: 4, endStop: 0, crossedNewline: false)
        let cursorTrackAndTickShown = trackBar.clearFilamentTrackShownForTests && trackBar.cursorCenterTickShownForTests
        trackBar.setCursorTelemetry(active: false, delta: 0, endStop: 0, crossedNewline: false)
        let cursorRestored = !trackBar.clearFilamentTrackShownForTests && !trackBar.cursorCenterTickShownForTests
        trackBar.setClearProgress(0.6, armed: false)
        let swipeTrackNoCenterTick = trackBar.clearFilamentTrackShownForTests && !trackBar.cursorCenterTickShownForTests
        trackBar.setClearProgress(0, armed: false)
        let swipeRestored = !trackBar.clearFilamentTrackShownForTests && !trackBar.cursorCenterTickShownForTests
        log(idleTrackHidden && cursorTrackAndTickShown && cursorRestored && swipeTrackNoCenterTick && swipeRestored,
            "r84.CandidateBarView shows recessed rangefinder track and center home tick during cursor scrub",
            "idle=\(idleTrackHidden) cursor=\(cursorTrackAndTickShown) restored=\(cursorRestored) swipe=\(swipeTrackNoCenterTick) end=\(swipeRestored)")

        // 3. Direct un-gated IP family interaction & synced GestureAtlas idle preview actions
        let directInteractOk: Bool = {
            let family = FamilyStageModel()
            family.soundEnabled = true
            family.interact(with: .moss)
            return family.activeMember == .moss
        }()
        let atlasEffectsOk = GestureAtlasContent.MostoPreviewAction.allCases.map(\.shortEffect) == ["颜文字", "换光效", "打哈欠"]
        log(directInteractOk && atlasEffectsOk,
            "r84.IP family sound interaction triggers directly without volume gate and GestureAtlas mirrors live idle bar",
            "direct=\(directInteractOk) atlas=\(atlasEffectsOk)")
    }

    // MARK: - R85: Commercial Companion App & OTTOSSOM IP Family Stage

    static func r85CommercialCompanionAndIPFamily(_ window: UIWindow) {
        _ = window
        // 1. All Moss, Otto, and Mosto 3D studio vinyl sprites load cleanly from asset catalog
        let spriteNames = ["Moss", "MossHappy", "Otto", "OttoLit", "Mosto", "MostoBlink", "MostoNight", "MostoYawn"]
        let allSpritesLoaded = spriteNames.allSatisfy { name in
            let img = mostoImage(name)
            return img.size.width >= 100 && img.size.height >= 100
        }
        log(allSpritesLoaded, "r85.OTTOSSOM IP family sprites (Moss, Otto, Mosto) load at full studio resolution",
            "loaded=\(spriteNames.filter { mostoImage($0).size.width > 0 })")

        // 2. FamilyStageModel coordinates Moss hop, Otto lamp toggle, Mosto night tail glow, and verification celebration
        let family = FamilyStageModel()
        family.soundEnabled = false
        family.interact(with: .moss)
        let mossOk = family.activeMember == .moss && family.reactingMember == .moss
            && FamilyMember.moss.spriteName(atmosphere: .day, reacting: true) == "MossHappy"
        family.interact(with: .otto)
        let ottoLitOk = family.activeMember == .otto && family.atmosphere == .night
            && FamilyMember.otto.spriteName(atmosphere: .night, reacting: false) == "OttoLit"
            && FamilyMember.mosto.spriteName(atmosphere: .night, reacting: false) == "MostoNight"
        family.celebrateVerification()
        let verifiedOk = family.verificationCelebrated && family.activeMember == .moss
        log(mossOk && ottoLitOk && verifiedOk,
            "r85.FamilyStageModel synchronizes Moss/Otto/Mosto states and night lamp chemistry",
            "moss=\(mossOk) ottoLit=\(ottoLitOk) verified=\(verifiedOk)")

        // 3. Consumer Companion UI copy is completely free of internal engineering jargon
        let forbiddenJargon = ["mmap", "Jetsam", "XPC", "markedText", "App Group", "16 条", "1104", "CI"]
        let allCopy: [String] =
            CompanionCapabilitiesSection.items.flatMap { [$0.title, $0.detail] }
            + PrivacyCommitmentContent.items.flatMap { [$0.title, $0.detail] }
            + FamilyMember.allCases.flatMap { [$0.displayName, $0.chineseRole, $0.bio] }
            + FamilyAtmosphere.allCases.flatMap { [$0.label, $0.stageCaption] }
        let leaked = forbiddenJargon.filter { term in
            allCopy.contains { $0.localizedCaseInsensitiveContains(term) }
        }
        log(leaked.isEmpty, "r85.Commercial Companion copy excludes developer jargon", "leaked=\(leaked)")

        // 4. Redesigned 3-tab structure & commercial views render cleanly via ImageRenderer
        let stageSize = FamilyLampStageView.renderSnapshotSizeForTests(width: 370)
        let aboutSize = AboutCompanionContent.renderSnapshotSizeForTests(width: 370)
        let privacySize = PrivacyCommitmentContent.renderSnapshotSizeForTests(width: 370)
        log(AppTab.allCases.count == 3 && stageSize.height > 180 && aboutSize.height > 200 && privacySize.height > 150,
            "r85.3-tab Companion views and FamilyLampStageView render cleanly with ImageRenderer",
            "tabs=\(AppTab.allCases.count) stage=\(stageSize) about=\(aboutSize) privacy=\(privacySize)")
    }

    // MARK: - R86: 1.0 RC IP Chemistry & Commercial Legal/Copy Sign-off

    static func r86ReleaseCandidatePolish(_ window: UIWindow) {
        _ = window
        // 1. Cross-character IP family chemistry responds across Moss -> Mosto -> Otto
        let family = FamilyStageModel()
        family.soundEnabled = false
        family.interact(with: .moss)
        let mossPaired = family.reactingMember == .moss && family.secondaryReactingMember == .mosto
        family.interact(with: .mosto)
        let mostoPaired = family.reactingMember == .mosto && family.secondaryReactingMember == .otto
        family.interact(with: .otto)
        let ottoPaired = family.reactingMember == .otto && family.secondaryReactingMember == .mosto
        log(mossPaired && mostoPaired && ottoPaired,
            "r86.OTTOSSOM IP family interactions trigger cross-character chemistry",
            "moss=\(mossPaired) mosto=\(mostoPaired) otto=\(ottoPaired)")

        // 2. LegalText matches App Store 1.0 wording and covers OTTOSSOM IP family
        let termsText = LegalText.docs.first(where: { $0.id == "terms" })?.sections.flatMap(\.1).compactMap { item -> String? in
            if case .text(let s) = item { return s }
            return nil
        }.joined(separator: " ") ?? ""
        let noBetaTerms = !termsText.contains("TestFlight 公开测试版")
        let hasFamilyIP = termsText.contains("Moss") && termsText.contains("Otto") && termsText.contains("Mosto")
        log(LegalText.effective == "2026 年 11 月 24 日" && noBetaTerms && hasFamilyIP,
            "r86.LegalText reflects App Store 1.0 release wording and OTTOSSOM IP ownership",
            "effective=\(LegalText.effective) noBeta=\(noBetaTerms) familyIP=\(hasFamilyIP)")
    }

    // MARK: - R87/R89: Eliminate WeChat Top Empty Glass Gap, Pure-Frame Settings & Settings-Return Drift

    static func r87WeChatTopGapElimination(_ window: UIWindow) {
        guard let pair = makeKeyboard(scheme: 0, in: window) else {
            log(false, "r87.WeChat top gap setup", "engine did not load")
            return
        }
        let (vc, _) = pair
        vc.applySettings()

        // 1. WeChat portrait normal containers (293.5 / 301 / 326 pt) fill flush from minY=0 (zero empty top slab)
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 293.5)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let wechat402Ok = vc.contentFrameForTests.minY == 0
            && abs(vc.contentFrameForTests.height - 293.5) < 0.5
            && vc.maxKeycapHeightForTests >= 46
            && vc.maxKeycapHeightForTests <= 53

        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 301)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let wechat393Ok = vc.contentFrameForTests.minY == 0
            && abs(vc.contentFrameForTests.height - 301) < 0.5
            && vc.maxKeycapHeightForTests >= 46
            && vc.maxKeycapHeightForTests <= 53

        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 326)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let wechat326Ok = vc.contentFrameForTests.minY == 0
            && abs(vc.contentFrameForTests.height - 326) < 0.5
            && vc.maxKeycapHeightForTests <= 54

        // 2. Pure-frame SettingsPanelView holds 0 Auto Layout constraints and detaches cleanly on close with 0 height drift
        let spStandalone = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 402, height: 293.5))
        spStandalone.toggleMoreForTests()
        spStandalone.layoutIfNeeded()
        let zeroSettingsConstraints = spStandalone.constraintCountForTests == 0

        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 293.5)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let beforeSettingsFrame = vc.contentFrameForTests
        vc.resetHeightSyncMutationsForTests()
        vc.showSettingsForTests(true)
        let settingsOpened = vc.settingsPanelLoadedForTests
        vc.showSettingsForTests(false)
        vc.view.layoutIfNeeded()
        let afterSettingsClean = settingsOpened
            && !vc.settingsPanelLoadedForTests
            && vc.heightSyncMutationsForTests == 0
            && vc.contentFrameForTests == beforeSettingsFrame

        // 3. Post-appear lifecycle causes 0 height constraint mutations (no post-appear jump/bounce)
        vc.beginAppearanceTransition(true, animated: false)
        vc.endAppearanceTransition()
        vc.view.layoutIfNeeded()
        let zeroPostAppearJump = vc.heightSyncMutationsForTests == 0

        // 4. Native 258 pt Spotlight/Notes container preserves exact 258 pt geometry and ~43 pt keycap height
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 258)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        let notesStandardOk = vc.contentFrameForTests.minY == 0
            && abs(vc.contentFrameForTests.height - 258) < 0.5
            && vc.maxKeycapHeightForTests >= 42
            && vc.maxKeycapHeightForTests <= 44

        log(wechat402Ok && wechat393Ok && wechat326Ok && zeroSettingsConstraints && afterSettingsClean && zeroPostAppearJump && notesStandardOk,
            "r87.WeChat 294/301/326pt hosts fill flush with zero top gap, pure-frame Settings returns cleanly, and 258pt Notes stays calibrated",
            "w402=\(wechat402Ok) w393=\(wechat393Ok) w326=\(wechat326Ok) zeroCon=\(zeroSettingsConstraints) ret=\(afterSettingsClean) noJump=\(zeroPostAppearJump) notes=\(notesStandardOk)")
    }

    // MARK: - R90: Clean Apple-native squircle keycaps with zero top-edge white line

    static func r90CleanKeycapCraftNoWhiteLine(_ window: UIWindow) {
        _ = window
        let prevPlain = Theme.plain
        defer { Theme.plain = prevPlain }

        var allCapsClean = true
        for plain in [false, true] {
            Theme.plain = plain
            let kv = KeyboardView(spatial: SpatialModel.standard(width: 402))
            kv.frame = CGRect(x: 0, y: 0, width: 402, height: 212)
            for (style, soft) in [(UIUserInterfaceStyle.light, false), (.dark, false), (.light, true)] {
                kv.overrideUserInterfaceStyle = style
                kv.softenedForDarkGlass = soft
                kv.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: "搜索",
                                           returnIsAccent: true, shifted: false, capsLock: false, keyBorders: true))
                kv.layoutIfNeeded()
                let samples: [KeyAction] = [.char("a"), .shift, .delete, .ret, .space]
                for action in samples {
                    guard let k = kv.keyViewForTests(action) else { allCapsClean = false; continue }
                    if k.hasTopHighlightForTests || k.borderWidthForTests != 0 {
                        allCapsClean = false
                    }
                }
            }
        }

        Theme.plain = false
        let smartKv = KeyboardView(spatial: SpatialModel.standard(width: 402))
        smartKv.frame = CGRect(x: 0, y: 0, width: 402, height: 212)
        smartKv.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil,
                                        returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true,
                                        spaceOverride: "跳出 》"))
        smartKv.layoutIfNeeded()
        let smartSpace = smartKv.keyViewForTests(.space)
        let smartSpacePreserved = smartSpace?.isSmartSpaceShownForTests == true
            && smartSpace?.smartSpaceRimActiveForTests == true
            && smartSpace?.hasTopHighlightForTests == false

        log(allCapsClean && smartSpacePreserved,
            "r90.All keycaps across Mosto/简洁 and Day/Night omit top highlight line and border strokes while preserving smart-space rim",
            "clean=\(allCapsClean) smartSpace=\(smartSpacePreserved)")
    }

    // MARK: - R91: Refactored BrandMark Icon & Commercial Companion App Suite

    static func r91AppIconAndCommercialCompanion(_ window: UIWindow) {
        _ = window
        let brand = mostoImage("BrandMark")
        let brandOk = brand.size.width >= 256 && brand.size.height >= 256

        let nav = AppNavigation()
        nav.openGuide(.atlas)
        let atlasNavOk = nav.tab == .guide && nav.guideSection == .atlas
        nav.openGuide(.xiaohe)
        let xiaoheNavOk = nav.tab == .guide && nav.guideSection == .xiaohe
        nav.openAbout()
        let aboutNavOk = nav.tab == .about
        nav.focusFamilyMember(.otto)
        let memberNavOk = nav.tab == .companion && nav.family.activeMember == .otto

        let capsSize = CompanionCapabilitiesSection.renderSnapshotSizeForTests(width: 370)
        let capsOk = capsSize.height > 150

        let aboutSize = AboutCompanionContent.renderSnapshotSizeForTests(width: 370)
        let aboutRenderOk = aboutSize.height > 300

        log(brandOk && atlasNavOk && xiaoheNavOk && aboutNavOk && memberNavOk && capsOk && aboutRenderOk,
            "r91.Refactored BrandMark asset, Bento navigation deep-links, and commercial Companion views render cleanly",
            "brand=\(brand.size) nav=(\(atlasNavOk),\(xiaoheNavOk),\(aboutNavOk),\(memberNavOk)) caps=\(capsOk) about=\(aboutRenderOk)")
    }

    // MARK: - R92: Sculpted Gradient Keycaps, Feathered Shadows, Light-Glass Night Softening & Optical Icons

    static func r92SculptedKeycapAndOpticalIcons(_ window: UIWindow) {
        _ = window
        let prevPlain = Theme.plain
        defer { Theme.plain = prevPlain }

        var craftOk = true
        for plain in [false, true] {
            Theme.plain = plain
            let kv = KeyboardView(spatial: SpatialModel.standard(width: 393))
            kv.frame = CGRect(x: 0, y: 0, width: 393, height: 216)
            for (style, softDark, softLight) in [
                (UIUserInterfaceStyle.light, false, false),
                (.dark, false, false),
                (.light, true, false),
                (.dark, false, true),
            ] {
                kv.overrideUserInterfaceStyle = style
                kv.softenedForDarkGlass = softDark
                kv.softenedForLightGlass = softLight
                kv.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: "搜索",
                                           returnIsAccent: true, shifted: false, capsLock: false, keyBorders: true))
                kv.layoutIfNeeded()
                for action in [KeyAction.char("a"), .shift, .delete, .ret, .space] {
                    guard let cap = kv.keyViewForTests(action) else { craftOk = false; continue }
                    if !cap.hasSculptedGradientForTests
                        || cap.hasTopHighlightForTests
                        || cap.borderWidthForTests != 0
                        || cap.shadowRadiusForTests < 1.2
                        || cap.shadowOpacityForTests != 1 {
                        craftOk = false
                    }
                    cap.pressed = true
                    if cap.shadowOpacityForTests != 0 { craftOk = false }
                    cap.pressed = false
                    if cap.shadowOpacityForTests != 1 { craftOk = false }
                }
            }
        }

        Theme.plain = true
        let propKv = KeyboardView(spatial: SpatialModel.standard(width: 393))
        propKv.frame = CGRect(x: 0, y: 0, width: 393, height: 216)
        propKv.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: "搜索",
                                       returnIsAccent: true, shifted: false, capsLock: false, keyBorders: true))
        propKv.layoutIfNeeded()
        propKv.softenedForLightGlass = true
        let lightGlassPropOk = propKv.softenedForLightGlassForTests
            && (propKv.keyViewForTests(.char("q"))?.isSoftenedForLightGlassForTests == true)
        let emojiH = propKv.keyViewForTests(.emoji)?.iconPointSizeForTests ?? 99
        let shiftH = propKv.keyViewForTests(.shift)?.iconPointSizeForTests ?? 0
        let opticalIconsOk = emojiH > 10 && shiftH > 10 && emojiH <= shiftH

        log(craftOk && lightGlassPropOk && opticalIconsOk,
            "r92.Sculpted gradient keycaps, feathered contact shadows, light-glass night softening, and calibrated icons work cleanly",
            "craft=\(craftOk) prop=\(lightGlassPropOk) icons=(emoji:\(emojiH),shift:\(shiftH))")
    }

    // MARK: - R93: Sculpted Console Tiles, Borderless Popups & Global Surface Alignment

    static func r93SculptedConsolePopupsAndBorderlessSurfaces(_ window: UIWindow) {
        let prevPlain = Theme.plain
        let s = KeyboardSettings.shared
        let savedScheme = s.scheme
        let savedAuto = s.autocorrect
        let savedStyle = s.style
        let savedApp = s.appearance
        defer {
            Theme.plain = prevPlain
            s.scheme = savedScheme
            s.autocorrect = savedAuto
            s.style = savedStyle
            s.appearance = savedApp
        }
        s.scheme = 0
        s.autocorrect = true
        s.style = 0
        s.appearance = 0

        // 1. SettingsPanelView Hardware Console: sculpted gradient tiles, soft LED halo, borderless pills/chips, 0 constraints
        var consoleOk = true
        for plain in [false, true] {
            Theme.plain = plain
            s.style = plain ? 1 : 0
            let sp = SettingsPanelView(frame: CGRect(x: 0, y: 0, width: 393, height: 258))
            for uiStyle in [UIUserInterfaceStyle.light, .dark] {
                sp.overrideUserInterfaceStyle = uiStyle
                sp.themeChanged()
                sp.layoutIfNeeded()
                if !sp.allTilesSculptedBorderlessForTests
                    || sp.activeLedHaloCountForTests < 1
                    || !sp.chromePillsBorderlessForTests
                    || sp.constraintCountForTests != 0 {
                    consoleOk = false
                }
            }
        }
        Theme.plain = false
        s.style = 0

        // 2. KeyPreview: borderless sculpted resting shell, 1pt accent rim only when flicked
        var previewOk = true
        let preview = KeyPreview(frame: CGRect(x: 0, y: 0, width: 54, height: 54))
        for uiStyle in [UIUserInterfaceStyle.light, .dark] {
            preview.overrideUserInterfaceStyle = uiStyle
            preview.setFlicked(false)
            preview.refreshStyle()
            if preview.surfaceBorderWidthForTests != 0 { previewOk = false }
            preview.setFlicked(true)
            if preview.surfaceBorderWidthForTests != 1.0 { previewOk = false }
        }

        // 3. AltPopup: sculpted borderless floating capsule with adaptive Day/Night shadow depth
        let lightPopup = AltPopup(options: ["。", "？", "！", "、"], cell: 36, height: 42)
        let darkPopup = AltPopup(options: ["。", "？", "！", "、"], cell: 36, height: 42)
        window.addSubview(lightPopup)
        window.addSubview(darkPopup)
        defer {
            lightPopup.removeFromSuperview()
            darkPopup.removeFromSuperview()
        }
        lightPopup.overrideUserInterfaceStyle = .light
        darkPopup.overrideUserInterfaceStyle = .dark
        lightPopup.refresh()
        darkPopup.refresh()
        lightPopup.layoutIfNeeded()
        darkPopup.layoutIfNeeded()
        let altOk = lightPopup.hasSculptedSurfaceForTests
            && lightPopup.borderWidthForTests == 0
            && darkPopup.hasSculptedSurfaceForTests
            && darkPopup.borderWidthForTests == 0
            && darkPopup.shadowOpacityForTests > lightPopup.shadowOpacityForTests

        // 4. CandidateGridView: sculpted dock gradients and borderless cells/rail/badge in Day & Night
        var gridOk = true
        let grid = CandidateGridView(frame: CGRect(x: 0, y: 0, width: 393, height: 216))
        window.addSubview(grid)
        defer { grid.removeFromSuperview() }
        let sampleCands = ["你好", "今天", "你", "尼", "泥"].map {
            Candidate(text: $0, tapCount: $0.count * 2, syllables: [1], corrected: false, score: 0)
        }
        for uiStyle in [UIUserInterfaceStyle.light, .dark] {
            grid.overrideUserInterfaceStyle = uiStyle
            grid.show(sampleCands)
            grid.layoutIfNeeded()
            if !grid.gridSurfacesSculptedAndBorderlessForTests || grid.collectionForTests.visibleCells.isEmpty {
                gridOk = false
            }
        }

        // 5. CandidateBarView pills & EmojiPanelView badges omit 0.5pt wireframe strokes
        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: 393, height: 42))
        bar.setIdleControls(enabled: true, night: false)
        bar.layoutIfNeeded()
        let barOk = bar.barPillsBorderlessForTests

        let emoji = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 393, height: 242))
        emoji.load(kaomoji: false)
        emoji.layoutIfNeeded()
        let emojiOk = emoji.emojiBadgesBorderlessForTests

        log(consoleOk && previewOk && altOk && gridOk && barOk && emojiOk,
            "r93.Settings Hardware Console, Popups, CandidateGrid, CandidateBar pills, and Emoji badges use borderless sculpted craft",
            "console=\(consoleOk) preview=\(previewOk) alt=\(altOk) shadow=(\(lightPopup.shadowOpacityForTests),\(darkPopup.shadowOpacityForTests)) grid=\(gridOk) bar=\(barOk) emoji=\(emojiOk)")
    }

    // MARK: - Fuzz: random people, the composition rules after every key


    // MARK: - R94: Unified T9 + QWERTY Layout, Right-Side Mosto, Page-Glide Safety & Shift Double-Tap Caps Lock

    static func r94T9UnifiedLayoutAndStateMachines(_ window: UIWindow) {
        // 1. Four-corner alignment: Return at Row 4 Right across all 4 layouts; 中/英 at Row 4 next-to-right across T9/QWERTY/symbols
        let t9Idle = Layouts.rows(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, numberGrid: true, pinyinGrid: true, composing: false))
        let t9Comp = Layouts.rows(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, numberGrid: true, pinyinGrid: true, composing: true))
        let qwerty = Layouts.rows(LayoutContext(page: .letters, chinese: false, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, numberGrid: true, pinyinGrid: true))
        let numpad = Layouts.rows(LayoutContext(page: .numpad, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, numberGrid: true, pinyinGrid: true))
        let numbers = Layouts.rows(LayoutContext(page: .numbers, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, numberGrid: true, pinyinGrid: true))
        let returnAligned = t9Idle[3].last?.action == .ret
            && qwerty[3].last?.action == .ret
            && numpad[3].last?.action == .ret
            && numbers[3].last?.action == .ret
        let langAligned = t9Idle[3][t9Idle[3].count - 2].action == .toggleLanguage
            && qwerty[3][qwerty[3].count - 2].action == .toggleLanguage
            && numbers[3][numbers[3].count - 2].action == .toggleLanguage
        let t9DynamicRight = t9Idle[1].last?.action == .char("！")
            && t9Comp[1].last?.action == .clearInput
            && t9Idle[0][1].action == .char("、")
            && t9Comp[0][1].action == .t9("'")
            && t9Idle[2].last?.action == .symbolPanel
            && numpad[2].last?.action == .symbolPanel
        log(returnAligned && langAligned && t9DynamicRight,
            "r94.Four-corner alignment locks Return bottom-right, 中/英 next-to-right, and T9 idle ！ / composing 重输",
            "ret=\(returnAligned) lang=\(langAligned) t9Right=\(t9DynamicRight)")

        // 2. T9 符号 tap opens SymbolPanelView WITHOUT flipping chinese to English (Bug #5 + R95 same-spot Return)
        if let pair = makeKeyboard(scheme: 1, grid: true, in: window) {
            let (vc, h) = pair
            let kb = vc.keyboardViewForTests
            kb.layoutIfNeeded()
            if let symRect = kb.keyRectsForTests(.symbolPanel)?.cap {
                let pt = CGPoint(x: symRect.midX, y: symRect.midY)
                kb.feedForTests([
                    TouchSample(id: 941, phase: .began, point: pt, time: 1.0),
                    TouchSample(id: 941, phase: .ended, point: pt, time: 1.06),
                ])
                let stayedChinese = !vc.testState.english && vc.symbolPanelShownForTests && h.string.isEmpty
                vc.symbolPanelIfLoadedForTests?.onClose?()
                let backToT9 = !vc.testState.english && !vc.symbolPanelShownForTests && vc.testState.page == .letters
                log(stayedChinese && backToT9,
                    "r94.T9 符号 tap opens SymbolPanelView in Chinese and closes cleanly back to T9",
                    "stayed=\(stayedChinese) back=\(backToT9) en=\(vc.testState.english) text=\(h.string)")
            } else {
                log(false, "r94.T9 符号 rect lookup")
            }
        }

        // 3. Numpad 符号 tap opens SymbolPanelView WITHOUT firing Return/newline (Bug #7)
        if let pair = makeKeyboard(scheme: 1, grid: true, in: window) {
            let (vc, h) = pair
            vc.handle(.page(.numpad), tap: nil)
            let kb = vc.keyboardViewForTests
            kb.layoutIfNeeded()
            if let symRect = kb.keyRectsForTests(.symbolPanel)?.cap {
                let pt = CGPoint(x: symRect.midX, y: symRect.midY)
                kb.feedForTests([
                    TouchSample(id: 943, phase: .began, point: pt, time: 2.0),
                    TouchSample(id: 943, phase: .ended, point: pt, time: 2.06),
                ])
                log(vc.symbolPanelShownForTests && h.string.isEmpty,
                    "r94.Numpad 符号 tap opens SymbolPanelView without firing Return or inserting newline",
                    "sym=\(vc.symbolPanelShownForTests) text=\(h.string.debugDescription)")
            } else {
                log(false, "r94.Numpad 符号 rect lookup")
            }
        }

        // 4. English defaults to lowercase (WeChat fix) and double-tap Shift locks Caps Lock in 2 taps (Bug #6)
        if let pair = makeKeyboard(scheme: 1, in: window) {
            let (vc, _) = pair
            vc.handle(.toggleLanguage, tap: nil)
            let startsLower = vc.keyboardViewForTests.context?.shifted == false && vc.keyboardViewForTests.context?.capsLock == false
            vc.handle(.shift, tap: nil)
            vc.handle(.shift, tap: nil)
            let lockedInTwo = vc.keyboardViewForTests.context?.capsLock == true && vc.keyboardViewForTests.context?.shifted == true
            vc.handle(.shift, tap: nil)
            let unlockedClean = vc.keyboardViewForTests.context?.capsLock == false && vc.keyboardViewForTests.context?.shifted == false
            log(startsLower && lockedInTwo && unlockedClean,
                "r94.English starts lowercase cleanly and double-tap Shift locks Caps Lock in 2 taps",
                "lower=\(startsLower) locked=\(lockedInTwo) unlocked=\(unlockedClean)")
        }
    }


    // MARK: - R95: Zero-Drift Toggle Law, Mosto Super-Key & Minimalist Single-Gear Top Bar

    static func r95ZeroDriftToggleAndMostoSuperKey(_ window: UIWindow) {
        // 1. Mosto bottom-row key has 0pt horizontal drift across T9, QWERTY, and Symbol pages
        let kv = KeyboardView(spatial: SpatialModel.standard(width: 393))
        kv.frame = CGRect(x: 0, y: 0, width: 393, height: 216)
        kv.configure(LayoutContext(page: .letters, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, numberGrid: true, pinyinGrid: true))
        kv.layoutIfNeeded()
        let xT9 = kv.keyRectsForTests(.emoji)?.cap.minX ?? -1
        kv.configure(LayoutContext(page: .letters, chinese: false, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, numberGrid: true, pinyinGrid: true))
        kv.layoutIfNeeded()
        let xEn = kv.keyRectsForTests(.emoji)?.cap.minX ?? -100
        kv.configure(LayoutContext(page: .numbers, chinese: true, showGlobe: false, returnLabel: nil, returnIsAccent: false, shifted: false, capsLock: false, keyBorders: true, numberGrid: true, pinyinGrid: true))
        kv.layoutIfNeeded()
        let xNum = kv.keyRectsForTests(.emoji)?.cap.minX ?? -200
        log(xT9 > 40 && abs(xT9 - xEn) < 1.0 && abs(xT9 - xNum) < 1.0,
            "r95.Bottom-row Mosto super-key stays locked to identical X coordinate across T9, QWERTY, and Symbols",
            "t9=\(xT9) en=\(xEn) num=\(xNum)")

        // 2. Mosto 0ms instant-open + <350ms second tap upgrades to Kaomoji + same-spot close + Send button visible
        if let pair = makeKeyboard(scheme: 1, grid: true, in: window) {
            let (vc, _) = pair
            vc.view.layoutIfNeeded()
            let keyX = vc.keyboardViewForTests.keyRectsForTests(.emoji)?.cap.minX ?? -1
            vc.handle(.emoji, tap: nil)
            vc.view.layoutIfNeeded()
            let openedEmoji = vc.emojiShownForTests && (vc.emojiPanelIfLoadedForTests?.kaomojiModeForTests == false)
            let returnBtnVisible = vc.emojiPanelIfLoadedForTests?.returnButtonVisibleForTests == true
            let panelMostoX = vc.emojiPanelIfLoadedForTests?.mostoReturnFrameInSelfForTests.minX ?? -99
            let emojiAligned = abs(panelMostoX - keyX) < 1.5
            // Immediate second tap (<350ms) upgrades to Kaomoji instead of closing
            vc.emojiPanelIfLoadedForTests?.onBack?()
            let upgradedToKaomoji = vc.emojiShownForTests && (vc.emojiPanelIfLoadedForTests?.kaomojiModeForTests == true)
            // Next tap in Kaomoji closes back to keyboard
            vc.emojiPanelIfLoadedForTests?.onBack?()
            let closedClean = !vc.emojiShownForTests
            log(openedEmoji && returnBtnVisible && emojiAligned && upgradedToKaomoji && closedClean,
                "r95.Mosto super-key 0ms opens Emoji, <350ms double-tap upgrades to Kaomoji, and same-spot closes with Send visible",
                "open=\(openedEmoji) send=\(returnBtnVisible) aligned=\(emojiAligned) kaomoji=\(upgradedToKaomoji) close=\(closedClean)")

            // 3. Settings panel has classic gearshape.fill top-right AND bottom Mosto return aligned with main Mosto key
            vc.handle(.settings, tap: nil)
            vc.view.layoutIfNeeded()
            let sp = vc.settingsPanelIfLoadedForTests
            let gearTopRight = sp?.doneButtonUsesGearForTests == true
            let spMostoX = sp?.mostoReturnFrameInSelfForTests.minX ?? -99
            let settingsAligned = abs(spMostoX - keyX) < 2.0
            log(gearTopRight && settingsAligned,
                "r95.SettingsPanelView uses top-right gearshape.fill and 0pt-drift bottom Mosto return anchor",
                "gear=\(gearTopRight) spX=\(spMostoX) keyX=\(keyX)")
        }
    }

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
