import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    // Engine
    private var lexicon: Lexicon?
    private var decoder: Decoder?
    private var userDict: UserDictionary?
    private var predictor: Predictor?
    private let spatial = SpatialModel.standard()

    // Views. Everything sits in `root`, whose light (日光 / 夜灯) is forced; the controller's own view keeps the
    // system's, so 自动 can always read the real light / dark mode.
    private let root = UIView()
    private let tintView = AmbientLightView()
    private let candidateBar = CandidateBarView()
    private lazy var keyboard = KeyboardView(spatial: spatial)
    private let grid = CandidateGridView()
    private let settingsPanel = SettingsPanelView()
    private var heightConstraint: NSLayoutConstraint?

    // State
    private var chinese = true
    private var page: KeyboardPage = .letters
    private var shifted = false
    private var capsLock = false
    private var lastShiftTap: Date = .distantPast
    private var taps: [Tap] = []
    private var result: Decoder.Result?
    private var committedParts: [(text: String, ids: [UInt16])] = []
    private var lastInsertedSpace = false
    /// The last auto-corrected commit made with the space bar, undone by an immediate delete (as on Gboard).
    private var undoable: (text: String, taps: [Tap], syllables: [UInt16])?
    private var lastDocumentID: UUID?
    private var predictions: [String] = []
    private var isNight = false
    /// Pinyin currently written into the host field as marked text.
    private var hasMarkedText = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let tick = UISelectionFeedbackGenerator()

    private var isLandscape: Bool { view.bounds.width > view.bounds.height && view.bounds.height > 0 }
    private var barHeight: CGFloat { isLandscape ? Metrics.toolbarHeightLandscape : Metrics.toolbarHeight }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Clear, so the system's Liquid Glass (or the classic keyboard backdrop in older apps) shows through;
        // 日光 / 夜灯 only tint it.
        view.backgroundColor = .clear
        root.backgroundColor = .clear
        view.addSubview(root)
        tintView.isUserInteractionEnabled = false
        root.addSubview(tintView)
        loadEngine()

        keyboard.inputController = self
        keyboard.onAction = { [weak self] action, tap in self?.handle(action, tap: tap) }
        keyboard.canMoveCursor = { [weak self] in self?.taps.isEmpty ?? false }
        keyboard.onCursorMove = { [weak self] d in
            guard let self, self.taps.isEmpty else { return }
            // one visible character per step: an emoji or other surrogate pair is two UTF-16 units
            let proxy = self.textDocumentProxy
            let ch = d < 0 ? proxy.documentContextBeforeInput?.last : proxy.documentContextAfterInput?.first
            // some apps share no context: then step one unit and let the system clamp at the ends
            proxy.adjustTextPosition(byCharacterOffset: d * (ch?.utf16.count ?? 1))
            if ch != nil, KeyboardSettings.shared.feedback, self.hasFullAccess { self.tick.selectionChanged() }
        }
        keyboard.onKeyDown = { [weak self] action in self?.playFeedback(action) }

        candidateBar.onSelect = { [weak self] i in self?.candidateTapped(i) }
        candidateBar.onExpand = { [weak self] in self?.showGrid(true) }
        candidateBar.onLongPress = { [weak self] i in self?.offerForget(i) }
        candidateBar.onSettings = { [weak self] in self?.showSettings(true) }
        grid.onSelect = { [weak self] i in self?.showGrid(false); self?.candidateTapped(i) }
        grid.onClose = { [weak self] in self?.showGrid(false) }
        grid.onDelete = { [weak self] in
            guard let self else { return }
            self.handle(.delete, tap: nil)
            if self.taps.isEmpty { self.showGrid(false) } else { self.grid.show(self.result?.candidates ?? []) }
        }
        settingsPanel.onClose = { [weak self] in self?.showSettings(false) }
        settingsPanel.onChange = { [weak self] in self?.applySettings() }
        settingsPanel.onResetLearning = { [weak self] in
            self?.userDict?.reset()
            self?.spatial.offsetX = 0
            self?.spatial.offsetY = 0
            KeyboardSettings.shared.touchOffset = (0, 0)
            self?.settingsPanel.setLearned("已清空。")
        }

        for v in [candidateBar, keyboard, grid, settingsPanel] as [UIView] { root.addSubview(v) }
        grid.isHidden = true
        settingsPanel.isHidden = true
        applySettings()
        let off = KeyboardSettings.shared.touchOffset
        spatial.offsetX = off.0
        spatial.offsetY = off.1
        reconfigure()
    }

    /// Ask iOS to let the keyboard have touches at the screen edges first (system edge gestures delay or cancel them).
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        releaseSystemGestureDelays()
    }

    /// iOS puts a system gesture gate (_UISystemGestureGateGestureRecognizer) on the keyboard's window that holds
    /// touches near the screen edges back until it decides they are not a system swipe — so q, a, shift, 123 and the
    /// space bar press late, and in fast typing those taps arrive out of order or are lost. Turning off its
    /// delaysTouchesBegan (on every recognizer above our view, each time the keyboard lands in a window) makes every
    /// key press immediately; the system gestures themselves still work.
    private func releaseSystemGestureDelays() {
        var v: UIView? = view
        while let cur = v {
            cur.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false; $0.delaysTouchesEnded = false }
            v = cur.superview
        }
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false; $0.delaysTouchesEnded = false }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if heightConstraint == nil {
            let c = view.heightAnchor.constraint(equalToConstant: preferredHeight())
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
        lastDocumentID = textDocumentProxy.documentIdentifier
        adaptToField()
        applyAppearance()
        haptic.prepare()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyAppearance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !taps.isEmpty { commitRaw() }
        userDict?.save()
        KeyboardSettings.shared.touchOffset = (spatial.offsetX, spatial.offsetY)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        heightConstraint?.constant = preferredHeight(landscape: size.width > size.height)
    }

    private func preferredHeight(landscape: Bool? = nil) -> CGFloat {
        let isLandscape = landscape ?? (UIScreen.main.bounds.width > UIScreen.main.bounds.height)
        return isLandscape ? Metrics.toolbarHeightLandscape + 4 * Metrics.rowPitchLandscape
                           : Metrics.toolbarHeight + 4 * Metrics.rowPitch
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        if view.window != nil { releaseSystemGestureDelays() }   // the window can change (rotation, app switch)
        root.frame = b
        tintView.frame = b
        candidateBar.frame = CGRect(x: 0, y: 0, width: b.width, height: barHeight)
        // the keys reach 10 pt up into the strip: taps that land a little high still type (see topReach)
        let reach: CGFloat = 10
        keyboard.frame = CGRect(x: 0, y: barHeight - reach, width: b.width, height: b.height - barHeight + reach)
        keyboard.topReach = reach
        grid.frame = CGRect(x: 0, y: barHeight, width: b.width, height: b.height - barHeight)
        settingsPanel.frame = b
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let id = textDocumentProxy.documentIdentifier
        if id != lastDocumentID {
            // Another field (or a host that reports a new identifier whenever its text changes — this arrives
            // late, after the next keys may already be typed): never throw those keys away; adapt the layout only
            // when nothing is being composed.
            lastDocumentID = id
            if taps.isEmpty { adaptToField(); applyAppearance() }
            return
        }
        if !chinese { updateAutoShift(); reconfigure() }
    }

    // MARK: - Engine

    private func loadEngine() {
        guard let path = Bundle.main.path(forResource: "lexicon", ofType: "bin"),
              let lex = try? Lexicon(path: path) else { return }
        lexicon = lex
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let ud = UserDictionary(lexicon: lex, url: dir?.appendingPathComponent("userdict.json"))
        userDict = ud
        decoder = Decoder(lexicon: lex, user: ud)
        if let pp = Bundle.main.path(forResource: "predictions", ofType: "bin") { predictor = try? Predictor(path: pp) }
        if let ep = Bundle.main.path(forResource: "english", ofType: "txt") { decoder?.english = try? EnglishLexicon(path: ep) }
    }

    // MARK: - 日光 / 夜灯

    /// The system's own light: dark mode, or a host that asks for a dark keyboard (Spotlight, some search bars).
    /// Read from the controller's view, which is never overridden (only `root` is).
    private var systemIsDark: Bool {
        view.traitCollection.userInterfaceStyle == .dark || textDocumentProxy.keyboardAppearance == .dark
    }

    private func applyAppearance() {
        let night: Bool
        switch KeyboardSettings.shared.appearance {
        case 1: night = false
        case 2: night = true
        default: night = systemIsDark
        }
        isNight = night
        root.overrideUserInterfaceStyle = night ? .dark : .light
        // a forced night over light glass needs a denser tint to read as night
        tintView.night = night
        tintView.forcedNight = night && !systemIsDark
        candidateBar.mosto.setNight(night)
        candidateBar.showsMosto = night
        settingsPanel.setNight(night)
    }

    private func applySettings() {
        let s = KeyboardSettings.shared
        let scheme = PinyinScheme(rawValue: s.scheme) ?? .xiaohe
        if decoder?.scheme != scheme {
            if !taps.isEmpty { commitRaw() }     // keys typed under the other scheme mean something else
            decoder?.scheme = scheme
        }
        decoder?.correctionEnabled = s.autocorrect
        decoder?.apply(strength: Decoder.Strength(rawValue: s.strength) ?? .standard)
        decoder?.englishEnabled = s.english
        candidateBar.showsPreedit = s.inlineMode == 2
        settingsPanel.setLearned("词库 \(lexicon?.entryCount ?? 0) 条 · 已学习 \(userDict?.count ?? 0) 个词")
        let d = keyboard.stats
        settingsPanel.setDiagnostics("本次按键 \(d.began) 次：输入 \(d.emitted)，系统取消后保留 \(d.cancelKept)，丢弃 \(d.dropped)；"
            + String(format: "每键处理 平均 %.1f ms、最长 %.0f ms", handleCount > 0 ? handleTotal / Double(handleCount) : 0, handleMax))
        settingsPanel.setNote((hasFullAccess ? "" : "震动与按键音需在 设置 › 通用 › 键盘 › 键盘 › Mosto键盘 中开启“允许完全访问”。")
            + "键盘不联网，词库与学习记录只存在本机。")
        reconfigure()
        applyAppearance()
        if !KeyboardSettings.shared.predictions { clearPredictions() }
        if !taps.isEmpty { refresh() }
    }

    /// The system keyboard's three click sounds: letters and symbols, delete, and the other function keys.
    private func playFeedback(_ action: KeyAction) {
        guard KeyboardSettings.shared.feedback, hasFullAccess else { return }
        haptic.impactOccurred()
        let sound: SystemSoundID
        switch action {
        case .char, .space, .t9: sound = 1104
        case .delete: sound = 1155
        default: sound = 1156
        }
        AudioServicesPlaySystemSound(sound)
        haptic.prepare()
    }

    // MARK: - Field adaptation

    private func adaptToField() {
        let proxy = textDocumentProxy
        switch proxy.keyboardType ?? .default {
        case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad:
            page = .numpad   // digits-only fields always get the 九宫格 pad
        case .numbersAndPunctuation:
            page = KeyboardSettings.shared.numberGrid ? .numpad : .numbers
        case .emailAddress, .URL, .webSearch:
            page = .letters
            if taps.isEmpty { chinese = false }
        default:
            page = .letters
        }
        if !chinese { updateAutoShift() }
        reconfigure()
    }

    /// nil = default return key, drawn as the ↵ icon like Gboard.
    private func returnLabel() -> (String?, Bool) {
        let type = textDocumentProxy.returnKeyType ?? .default
        let zh: [UIReturnKeyType: String] = [.go: "前往", .search: "搜索", .send: "发送", .done: "完成",
                                             .next: "下一项", .join: "加入", .route: "路线", .continue: "继续",
                                             .google: "搜索", .yahoo: "搜索", .emergencyCall: "紧急"]
        let en: [UIReturnKeyType: String] = [.go: "go", .search: "search", .send: "send", .done: "done",
                                             .next: "next", .join: "join", .route: "route", .continue: "continue",
                                             .google: "search", .yahoo: "search", .emergencyCall: "SOS"]
        if !taps.isEmpty { return (chinese ? "确认" : "return", false) }   // commits the letters, as the system keyboard
        if type == .default { return (nil, false) }
        return ((chinese ? zh[type] : en[type]), true)
    }

    private var lastContext: LayoutContext?

    private func reconfigure() {
        let (label, accent) = returnLabel()
        let ctx = LayoutContext(page: page, chinese: chinese, showGlobe: needsInputModeSwitchKey,
                                         returnLabel: label, returnIsAccent: accent,
                                         shifted: shifted, capsLock: capsLock,
                                         keyBorders: KeyboardSettings.shared.keyBorders,
                                         numberGrid: KeyboardSettings.shared.numberGrid,
                                         pinyinGrid: KeyboardSettings.shared.pinyinGrid, composing: !taps.isEmpty)
        // most keystrokes change nothing on the keys: skip the work entirely (it ran twice per keystroke before)
        if ctx == lastContext { return }
        lastContext = ctx
        keyboard.configure(ctx)
    }

    // MARK: - Key handling

    private var handleTotal = 0.0, handleMax = 0.0, handleCount = 0

    private func handle(_ action: KeyAction, tap: Tap?) {
        let t0 = CACurrentMediaTime()
        defer {
            let ms = (CACurrentMediaTime() - t0) * 1000
            handleTotal += ms; handleCount += 1; handleMax = max(handleMax, ms)
        }
        candidateBar.dismissForget()
        let undo = undoable
        undoable = nil
        if action == .delete, let undo, undoCorrection(undo) { return }
        // any key ends the suggestions, as on Gboard
        if !predictions.isEmpty, action != .settings, action != .globe { clearPredictions() }
        switch action {
        case .char(let s):
            if let tap, page == .letters { letter(s, tap: tap) } else { symbol(s) }
        case .space:
            space()
        case .delete:
            delete()
        case .ret:
            if !taps.isEmpty { commitRaw() } else { textDocumentProxy.insertText("\n") }
            lastInsertedSpace = false
            if !chinese { updateAutoShift() }
            reconfigure()
        case .shift:
            shiftTapped()
        case .page(let p):
            if p != .letters, !taps.isEmpty { commitAll() }
            page = p
            reconfigure()
        case .toggleLanguage:
            if !taps.isEmpty { commitRaw() }
            chinese.toggle()
            shifted = false
            capsLock = false
            if !chinese { updateAutoShift() }
            reconfigure()
        case .settings:
            if !taps.isEmpty { commitAll() }
            showSettings(true)
        case .globe:
            break
        case .t9(let d):
            // 九宫格: each key stands for its letters; 分词 only splits syllables inside a composition
            guard decoder != nil, d != "'" || !taps.isEmpty else { return }
            lastInsertedSpace = false
            taps.append(Tap.t9(d))
            refresh()
        case .clearInput:
            if !taps.isEmpty { clearComposition() }
        case .deleteWord:
            deleteWord()
        }
    }

    private func letter(_ s: String, tap: Tap) {
        lastInsertedSpace = false
        if chinese && !(shifted || capsLock) {
            guard decoder != nil else { textDocumentProxy.insertText(s); return }
            taps.append(tap)
            refresh()
            return
        }
        // English, or Shift held in Chinese mode: direct letter.
        if !taps.isEmpty { commitAll() }
        textDocumentProxy.insertText((shifted || capsLock) ? s.uppercased() : s)
        if shifted && !capsLock {
            shifted = false
            reconfigure()
        }
    }

    private func symbol(_ s: String) {
        if !taps.isEmpty { commitAll() }
        textDocumentProxy.insertText(s)
        lastInsertedSpace = false
        if !chinese && [".", "!", "?"].contains(s) { updateAutoShift(); reconfigure() }
    }

    private func space() {
        if !taps.isEmpty {
            if let c = result?.candidates.first, c.corrected, c.tapCount == taps.count, committedParts.isEmpty {
                let saved = taps
                select(0)
                if taps.isEmpty { undoable = (c.text, saved, c.syllables) }
                return
            }
            commitAll()
            return
        }
        let proxy = textDocumentProxy
        if !chinese, lastInsertedSpace, let before = proxy.documentContextBeforeInput,
           before.hasSuffix(" "), let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastInsertedSpace = false
            updateAutoShift()
            reconfigure()
            return
        }
        proxy.insertText(" ")
        lastInsertedSpace = true
        if !chinese { updateAutoShift(); reconfigure() }
    }

    private func delete() {
        lastInsertedSpace = false
        if !taps.isEmpty {
            taps.removeLast()
            if taps.isEmpty { clearComposition() } else { refresh() }
            return
        }
        textDocumentProxy.deleteBackward()
        if !chinese { updateAutoShift(); reconfigure() }
    }

    /// Held delete: the whole composition, else back over one word — two Chinese characters, or a Latin word with
    /// the spaces before it, or a run of punctuation.
    private func deleteWord() {
        lastInsertedSpace = false
        if !taps.isEmpty { clearComposition(); return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        guard let last = before.last else { textDocumentProxy.deleteBackward(); return }
        var count = 0
        var chars = Array(before)
        func isHan(_ c: Character) -> Bool { c.unicodeScalars.first.map { (0x3400...0x9FFF).contains($0.value) } ?? false }
        if isHan(last) {
            count = min(2, chars.count)
        } else {
            while let c = chars.last, c == " " { chars.removeLast(); count += 1 }
            let word: (Character) -> Bool = { $0.isLetter || $0.isNumber }
            if let c = chars.last, word(c), !isHan(c) {
                while let c = chars.last, word(c), !isHan(c) { chars.removeLast(); count += 1 }
            } else if !chars.isEmpty {
                chars.removeLast(); count += 1
            }
        }
        for _ in 0..<max(count, 1) { textDocumentProxy.deleteBackward() }
        if !chinese { updateAutoShift(); reconfigure() }
    }

    private func shiftTapped() {
        let now = Date()
        if capsLock {
            capsLock = false
            shifted = false
        } else if shifted && now.timeIntervalSince(lastShiftTap) < 0.35 {
            capsLock = true
        } else {
            shifted.toggle()
        }
        lastShiftTap = now
        reconfigure()
    }

    private func updateAutoShift() {
        guard !capsLock else { return }
        let proxy = textDocumentProxy
        let type = proxy.autocapitalizationType ?? .sentences
        guard type != .none else { shifted = false; return }
        let before = proxy.documentContextBeforeInput ?? ""
        if type == .allCharacters { shifted = true; return }
        if type == .words { shifted = before.isEmpty || before.last == " " || before.last == "\n"; return }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        shifted = before.isEmpty || trimmed.hasSuffix(".") && before.hasSuffix(" ")
            || trimmed.hasSuffix("!") && before.hasSuffix(" ") || trimmed.hasSuffix("?") && before.hasSuffix(" ")
            || before.hasSuffix("\n")
    }

    // MARK: - Composition

    private func refresh() {
        guard let decoder else { return }
        let r = decoder.decode(taps)
        result = r
        let mode = KeyboardSettings.shared.inlineMode
        if mode != 2 {
            // Written into the text field, underlined, until a candidate replaces it: the letters as typed
            // (九宫格 keys have no single letter, so their pinyin), or the pinyin.
            let marked = mode == 0 && !taps.contains(where: { $0.group }) ? String(taps.map { $0.key }) : r.preedit
            textDocumentProxy.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0))
            hasMarkedText = true
        } else if hasMarkedText {
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            textDocumentProxy.unmarkText()
            hasMarkedText = false
        }
        candidateBar.update(preedit: r.preedit, candidates: r.candidates)
        if !grid.isHidden { grid.show(r.candidates) }
        reconfigure()
    }

    private func select(_ index: Int) {
        guard let decoder, let r = result, index < r.candidates.count else { return }
        let c = r.candidates[index]
        guard c.tapCount > 0 else { return }
        insertCommitted(c.text)
        let committedText = c.text
        // Learn: the word itself and where this user's finger actually lands.
        if !c.syllables.isEmpty {
            userDict?.learn(syllables: c.syllables, text: c.text)
            committedParts.append((c.text, c.syllables))
            let keys = decoder.keys(for: c)
            for (tap, key) in zip(taps.prefix(c.tapCount), keys) { spatial.observe(tap: tap, intended: key) }
        }
        taps.removeFirst(min(c.tapCount, taps.count))
        if taps.isEmpty {
            if committedParts.count > 1 {
                let ids = committedParts.flatMap { $0.ids }
                if ids.count <= 8 { userDict?.learn(syllables: ids, text: committedParts.map { $0.text }.joined()) }
            }
            clearComposition()
            if !c.syllables.isEmpty { showPredictions(after: committedText) }
        } else {
            refresh()
        }
    }

    /// Delete right after an auto-corrected commit: take the word back out, put the typed keys back into the
    /// composition and show them uncorrected, so the next space types what was actually pressed.
    private func undoCorrection(_ u: (text: String, taps: [Tap], syllables: [UInt16])) -> Bool {
        guard taps.isEmpty, let decoder, (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(u.text) else { return false }
        for _ in u.text { textDocumentProxy.deleteBackward() }
        if !u.syllables.isEmpty { userDict?.unlearn(syllables: u.syllables, text: u.text) }
        predictions = []
        taps = u.taps
        let was = decoder.correctionEnabled
        decoder.correctionEnabled = false
        refresh()
        decoder.correctionEnabled = was
        return true
    }

    /// Long press on a candidate this user taught the keyboard: offer to remove it from what was learned.
    /// Words from the built-in lexicon cannot be removed, so nothing is offered for them.
    private func offerForget(_ i: Int) {
        guard let r = result, i < r.candidates.count, let userDict else { return }
        let c = r.candidates[i]
        guard !c.syllables.isEmpty, userDict.contains(syllables: c.syllables, text: c.text) else { return }
        candidateBar.offerForget(c.text) { [weak self] in
            self?.userDict?.forget(syllables: c.syllables, text: c.text)
            self?.userDict?.save()
            if self?.taps.isEmpty == false { self?.refresh() }
        }
    }

    private func commitAll() {
        var guardCount = 0
        while !taps.isEmpty && guardCount < 32 {
            guardCount += 1
            if result == nil { refresh() }
            if let c = result?.candidates.first, c.tapCount > 0, !c.syllables.isEmpty || c.isEnglish {
                select(0)
            } else {
                commitRaw()
            }
        }
    }

    /// Insert committed text; it replaces the marked pinyin when there is one.
    private func insertCommitted(_ text: String) {
        textDocumentProxy.insertText(text)
        hasMarkedText = false
    }

    private func commitRaw() {
        insertCommitted(String(taps.map { $0.key }))
        clearComposition()
    }

    private func clearComposition() {
        if hasMarkedText {
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            textDocumentProxy.unmarkText()
            hasMarkedText = false
        }
        taps.removeAll()
        result = nil
        committedParts.removeAll()
        candidateBar.update(preedit: "", candidates: [])
        showGrid(false)
        reconfigure()
    }

    // MARK: - Predictions (联想)

    private func candidateTapped(_ i: Int) {
        if taps.isEmpty, i < predictions.count {
            let text = predictions[i]
            textDocumentProxy.insertText(text)
            showPredictions(after: text)
        } else {
            select(i)
        }
    }

    private func showPredictions(after text: String) {
        guard KeyboardSettings.shared.predictions, chinese, let predictor else { return }
        predictions = predictor.predict(after: text)
        guard !predictions.isEmpty else { clearPredictions(); return }
        let cands = predictions.map { Candidate(text: $0, tapCount: 0, syllables: [], corrected: false, score: 0) }
        candidateBar.update(preedit: "", candidates: cands, prediction: true)
        result = Decoder.Result(candidates: cands, preedit: "")
    }

    private func clearPredictions() {
        guard !predictions.isEmpty else { return }
        predictions = []
        if taps.isEmpty {
            result = nil
            candidateBar.update(preedit: "", candidates: [])
            showGrid(false)
        }
    }

    // MARK: - Panels

    private func showGrid(_ on: Bool) {
        if on, let r = result { grid.show(r.candidates) }
        grid.isHidden = !on
        // panels sit on the same system glass as the keys (no opaque sheet stacked on it): hide what is underneath
        keyboard.isHidden = on || !settingsPanel.isHidden
    }

    private func showSettings(_ on: Bool) {
        if on { settingsPanel.load(); applySettings() }
        settingsPanel.isHidden = !on
        candidateBar.isHidden = on
        keyboard.isHidden = on || !grid.isHidden
    }
}
