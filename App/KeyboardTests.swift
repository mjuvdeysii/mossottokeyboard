import UIKit

/// A text field for the test bench: the same calls the system's proxy takes, applied to a string with a cursor and
/// marked text the way UIKit text views do (marked text sits at the cursor and is part of the text before it;
/// inserting replaces it; unmarking keeps it). It also records what a real host would punish: deleting while
/// something is marked (hosts disagree about what that deletes).
final class FakeTextHost: NSObject, UITextDocumentProxy {
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
            type(vc, "jintianttianqihenhao"); settle(vc); vc.handle(.space, tap: nil)
            log(h.string.hasSuffix("今天天气很好"), "quanpin.one key too many: jintianttianqihenhao → 今天天气很好", "text=\(h.string)")
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

    // MARK: - Fuzz: random people, the composition rules after every key

    static func fuzz(_ window: UIWindow) {
        var rng = SystemRandomNumberGenerator()
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
