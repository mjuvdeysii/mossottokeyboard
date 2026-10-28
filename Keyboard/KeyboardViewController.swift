import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    /// The text field being typed into: the system's proxy, or a stand-in field when the keyboard is driven by the
    /// in-app test bench (App/KeyboardTests.swift), which runs this same controller against a simulated field.
    var hostOverride: UITextDocumentProxy?
    private var host: UITextDocumentProxy { hostOverride ?? super.textDocumentProxy }
    /// Where the lexicon and the other engine files are (the keyboard's own bundle; the test bench points it at the
    /// keyboard extension inside the app) and whether learned words are kept on disk (not in tests).
    static var resourceBundle: Bundle = .main
    static var keepsLearnedWords = true
    // Engine: decoding and learned words on their own thread (EngineHost); the main thread only draws and types
    private let engine = EngineHost()
    private var scheme: PinyinScheme = .xiaohe
    private let spatial = SpatialModel.standard()

    // Views. Everything sits in `root`, whose light (日光 / 夜灯) is forced; the controller's own view keeps the
    // system's, so 自动 can always read the real light / dark mode.
    private let root = UIView()
    private let tintView = AmbientLightView()
    private let candidateBar = CandidateBarView()
    private lazy var keyboard = KeyboardView(spatial: spatial)
    private let grid = CandidateGridView()
    private let settingsPanel = SettingsPanelView()
    /// Made on first use and dropped again on a memory warning while hidden.
    private var emojiPanelIfLoaded: EmojiPanelView?
    private var emojiPanel: EmojiPanelView {
        if let p = emojiPanelIfLoaded { return p }
        let p = makeEmojiPanel()
        emojiPanelIfLoaded = p
        return p
    }
    private let syllablePicker = SyllablePickerView()
    private var syllableChoices: (start: Int, choices: [(text: String, keys: [Character])]) = (0, [])
    private var heightConstraint: NSLayoutConstraint?

    // State
    private var chinese = true
    private var page: KeyboardPage = .letters
    private var shifted = false
    private var capsLock = false
    private var lastShiftTap: Date = .distantPast
    private var taps: [Tap] = []
    /// The candidates last received from the engine, and for which state of `taps` (see `generation`).
    private var result: Decoder.Result?
    private var resultGeneration = -1
    /// Bumped whenever `taps` changes: a decode that comes back for an older generation is dropped.
    private var generation = 0
    /// The current keys are read as typed, without correction (right after an undone correction).
    private var literalGeneration = false
    private var committedParts: [(text: String, ids: [UInt16])] = []
    private var lastInsertedSpace = false
    /// The last auto-corrected commit made with the space bar, undone by an immediate delete (as on Gboard).
    private var undoable: (text: String, taps: [Tap], syllables: [UInt16])?
    private var lastDocumentID: UUID?
    /// The text around the cursor as the last key left it: a change notice that finds something else means the user
    /// moved the cursor or the field changed under us, and what a delete would undo is no longer just before it.
    private var afterLastKey = ""
    /// The language last chosen for ordinary text (address, e-mail and search fields switch to English on their own).
    private var preferredChinese = true
    private var isNight = false
    /// Pinyin currently written into the host field as marked text.
    private var hasMarkedText = false
    /// The marked text last written, and how many times the host was seen to include it in the text before the
    /// cursor (see reconcileWithHost).
    private var markedString = ""
    private var hostEchoesMarked = 0
    private var lastEchoed = ""
    private var markedHistory: [String] = []

    // English mode: the word being typed (its taps and the characters inserted), its suggestions and the
    // autocorrection space would apply; the last applied correction, which a delete right after takes back.
    private var english: EnglishDecoder?
    private var enTaps: [Tap] = []
    private var enTyped = ""
    private var enSuggestions: [String] = []
    private var enCorrection: String?
    private var enUndo: (typed: String, taps: [Tap], corrected: String)?
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let tick = UISelectionFeedbackGenerator()

    private var isLandscape: Bool { view.bounds.width > view.bounds.height && view.bounds.height > 0 }
    private var barHeight: CGFloat { isLandscape ? Metrics.toolbarHeightLandscape : Metrics.toolbarHeight }

    // MARK: - Test bench

    /// What the test bench checks after every action.
    struct TestState { let keys: String; let composing: Bool; let marked: String?; let candidates: [String]; let english: Bool; let page: KeyboardPage }
    var testState: TestState {
        TestState(keys: String(taps.map { $0.key }), composing: !taps.isEmpty, marked: hasMarkedText ? markedString : nil,
                  candidates: (result?.candidates ?? []).map { $0.text }, english: !chinese, page: page)
    }
    /// Block until the engine has loaded (the bench drives keys straight after creating the controller).
    func waitForEngineForTests() -> Bool {
        for _ in 0..<600 {
            if engine.decodeNow([Tap.exact("a")]) != nil { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }
    var syllableChoiceCount: Int { syllableChoices.choices.count }
    /// The candidates shown are for the keys typed now (no decode still under way for them).
    var candidateBarForTests: CandidateBarView { candidateBar }
    var testSettled: Bool { taps.isEmpty || resultGeneration == generation }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Clear, so the system's Liquid Glass (or the classic keyboard backdrop in older apps) shows through;
        // 日光 / 夜灯 only tint it.
        view.backgroundColor = .clear
        root.backgroundColor = Theme.touchable   // never fully clear: iOS drops touches on transparent points
        view.addSubview(root)
        tintView.isUserInteractionEnabled = false
        root.addSubview(tintView)
        loadEngine()

        keyboard.inputController = self
        keyboard.onAction = { [weak self] action, tap in self?.handle(action, tap: tap) }
        keyboard.canMoveCursor = { [weak self] in self?.taps.isEmpty ?? false }
        keyboard.stripIsEmpty = { [weak self] in
            guard let self else { return true }
            return self.taps.isEmpty && self.enSuggestions.isEmpty
        }
        keyboard.reservedTop = { [weak self] in
            // while keys are being composed the strip belongs to the candidates: Mosto takes no touches from q / w
            guard let self, !self.candidateBar.isHidden, self.taps.isEmpty else { return nil }
            let m = self.candidateBar.mosto
            guard !m.isHidden, m.alpha > 0.5 else { return nil }
            return self.candidateBar.convert(m.frame.insetBy(dx: -6, dy: 0), to: self.keyboard)
        }
        keyboard.onCursorMove = { [weak self] d in
            guard let self, self.taps.isEmpty else { return }
            // the cursor leaves the word just typed: nothing to undo or autocorrect there any more
            self.undoable = nil
            self.enUndo = nil
            self.endEnglishWord()
            // one visible character per step: an emoji or other surrogate pair is two UTF-16 units
            let proxy = self.host
            let ch = d < 0 ? proxy.documentContextBeforeInput?.last : proxy.documentContextAfterInput?.first
            // some apps share no context: then step one unit and let the system clamp at the ends
            proxy.adjustTextPosition(byCharacterOffset: d * (ch?.utf16.count ?? 1))
            if ch != nil, self.hapticsOn, self.hasFullAccess { self.tick.selectionChanged() }
        }
        keyboard.onKeyDown = { [weak self] action in self?.playFeedback(action) }

        candidateBar.onSelect = { [weak self] i in self?.candidateTapped(i) }
        syllablePicker.isHidden = true
        keyboard.addSubview(syllablePicker)
        keyboard.overlay = syllablePicker
        syllablePicker.onPick = { [weak self] i in self?.pickSyllable(i) }
        candidateBar.onExpand = { [weak self] in self?.showGrid(true) }
        candidateBar.onLongPress = { [weak self] i in self?.offerForget(i) }
        candidateBar.onSettings = { [weak self] in self?.showSettings(true) }
        candidateBar.onMostoTap = { [weak self] in
            guard let self else { return }
            self.playFeedback(.emoji)
            if !self.taps.isEmpty { self.commitAll() }   // as the emoji key does: nothing typed is left half-marked
            self.showEmoji(true, kaomoji: true)
        }
        candidateBar.onMostoDoubleTap = { [weak self] in
            // 日光 ⇄ 夜灯, from whatever light is showing now (自动 included); the settings page shows the choice
            guard let self else { return }
            self.playFeedback(.emoji)
            KeyboardSettings.shared.appearance = self.isNight ? 1 : 2
            self.applyAppearance()
        }
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
            self?.engine.resetLearning()
            self?.spatial.offsetX = 0
            self?.spatial.offsetY = 0
            self?.spatial.keyOffsets = [:]
            KeyboardSettings.shared.touchOffset = (0, 0)
            KeyboardSettings.shared.keyOffsets = [:]
            self?.settingsPanel.setLearned("已清空。")
        }

        for v in [candidateBar, keyboard, grid, settingsPanel] as [UIView] { root.addSubview(v) }
        grid.isHidden = true
        settingsPanel.isHidden = true
        applySettings()
        let off = KeyboardSettings.shared.touchOffset
        spatial.offsetX = off.0
        spatial.offsetY = off.1
        spatial.keyOffsetsList = KeyboardSettings.shared.keyOffsets
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
        lastDocumentID = host.documentIdentifier
        hostEchoesMarked = 0
        lastEchoed = ""
        forgetLastWord()
        afterLastKey = contextSnapshot()
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
        LaunchGuard.succeeded()   // put away normally: not a launch that failed
        peakFootprint = max(peakFootprint, memoryFootprintMB())
        if !taps.isEmpty {
            // put away mid-word: the letters stay in the field. Where the host already kept them itself (it
            // finalised the marked text as the field lost focus) they are only unmarked, never written twice.
            // (the marked text is the letters, or the 九宫格 pinyin — exactly what a commit would write)
            if hasMarkedText, !markedString.isEmpty, (host.documentContextBeforeInput ?? "").hasSuffix(markedString) {
                host.unmarkText()
                hasMarkedText = false
                clearComposition()
            } else {
                commitRaw()
            }
        }
        engine.save()
        KeyboardSettings.shared.touchOffset = (spatial.offsetX, spatial.offsetY)
        KeyboardSettings.shared.keyOffsets = spatial.keyOffsetsList
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
        if !syllablePicker.isHidden, let f = keyboard.keypadSideColumn() { syllablePicker.frame = f }
        root.frame = b
        tintView.frame = b
        // landscape on a phone with rounded corners / the Dynamic Island: keys and candidates stay inside the safe
        // area (as on the system keyboard), the glass and tint still run edge to edge
        let insetL = view.safeAreaInsets.left, insetR = view.safeAreaInsets.right
        let w = b.width - insetL - insetR
        candidateBar.frame = CGRect(x: insetL, y: 0, width: w, height: barHeight)
        // the keys reach up into the strip — 8 pt always, a little more right after a key (see KeyboardView.hitTest) —
        // never so far that a quick candidate pick lands on a key (the strip is shorter in landscape)
        let reach: CGFloat = min(14, barHeight * 0.3)
        keyboard.frame = CGRect(x: insetL, y: barHeight - reach, width: w, height: b.height - barHeight + reach)
        keyboard.topReach = reach
        grid.frame = CGRect(x: insetL, y: barHeight, width: w, height: b.height - barHeight)
        let safe = CGRect(x: insetL, y: 0, width: w, height: b.height)
        settingsPanel.frame = safe
        if emojiShown { emojiPanel.frame = safe }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        reconcileWithHost()
        leaveWordIfMoved()
        let id = host.documentIdentifier
        if id != lastDocumentID {
            // what was learned about the last field's echo of marked text says nothing about this one
            hostEchoesMarked = 0
            lastEchoed = ""
            if taps.isEmpty { forgetLastWord() }
            // Another field (or a host that reports a new identifier whenever its text changes — this arrives
            // late, after the next keys may already be typed): never throw those keys away; adapt the layout only
            // when nothing is being composed and the field is actually of another kind.
            lastDocumentID = id
            if taps.isEmpty {
                // a field of another kind gets its page and language; any field gets its shift and light
                if fieldTraits() != lastFieldTraits { adaptToField() } else if !chinese { updateAutoShift(); reconfigure() }
                applyAppearance()
            }
            return
        }
        if !chinese { updateAutoShift(); reconfigure() }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        reconcileWithHost()
        leaveWordIfMoved()
    }

    private func contextSnapshot() -> String {
        (host.documentContextBeforeInput ?? "") + "\u{1}" + (host.documentContextAfterInput ?? "")
    }

    /// The cursor is no longer where the last key left it (tapped elsewhere, text replaced, another field): the
    /// word just typed is behind us — no undoing its correction, no suggestions for it, no ". " from its space.
    private func leaveWordIfMoved() {
        guard taps.isEmpty, contextSnapshot() != afterLastKey else { return }
        forgetLastWord()
    }

    private func forgetLastWord() {
        undoable = nil
        enUndo = nil
        lastInsertedSpace = false
        endEnglishWord()
    }

    /// The host took the letters being composed out of our hands — the user tapped elsewhere in the text, sent the
    /// message, or the field was cleared: the field committed (or dropped) the marked text itself. The composition
    /// then ends here without touching the field again, or the next key would write the letters a second time.
    /// Only checked in hosts seen to include the marked text in the text before the cursor (confirmed twice), so a
    /// host that does not is never mistaken for one that moved on.
    private func reconcileWithHost() {
        guard !taps.isEmpty, hasMarkedText, markedString.count >= 2,
              let before = host.documentContextBeforeInput else { return }
        if before.hasSuffix(markedString) {
            // the host shows our marked text in its context: confirmed once per distinct composition string
            if markedString != lastEchoed { lastEchoed = markedString; hostEchoesMarked += 1 }
            return
        }
        // a late notice about an earlier state of this composition (fast typing) is not the host moving on
        // and only once the host has caught up with the latest marked text (it echoed the current string): callbacks
        // arrive in order, so a context without it after that is newer, never a stale one from before a commit
        guard hostEchoesMarked >= 2, lastEchoed == markedString,
              !markedHistory.contains(where: { before.hasSuffix($0) }) else { return }
        markedHistory.removeAll()
        hasMarkedText = false
        taps.removeAll()
        generation += 1
        result = nil
        committedParts.removeAll()
        syllablePicker.isHidden = true
        keyboard.setSideColumnHidden(false)
        candidateBar.update(preedit: "", candidates: [])
        showGrid(false)
        reconfigure()
    }

    /// What `adaptToField` looks at: a new identifier with the same traits is the same kind of field.
    private func fieldTraits() -> [Int] {
        let p = host
        return [p.keyboardType?.rawValue ?? -1, p.returnKeyType?.rawValue ?? -1, p.autocapitalizationType?.rawValue ?? -1]
    }
    private var lastFieldTraits: [Int] = []

    // MARK: - Engine

    /// The lexicon, learned words and English list are memory-mapped files, opened on the engine's thread: the
    /// keyboard appears at once, and keys typed in the first moments simply wait in the engine's queue.
    private func loadEngine() {
        let safe = LaunchGuard.begin()
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let b = Self.resourceBundle
        let ep = b.path(forResource: "english", ofType: "bin")
        engine.load(lexiconPath: b.path(forResource: "lexicon", ofType: "bin"), englishPath: ep,
                    grammarPath: b.path(forResource: "grammar", ofType: "gram"),
                    userDictURL: Self.keepsLearnedWords ? dir?.appendingPathComponent("userdict.json") : nil, safe: safe)
        // English mode reads the same file (read-only, safe to share between threads)
        if !safe, let ep, let en = try? EnglishLexicon(path: ep) { english = EnglishDecoder(lexicon: en) }
        safeMode = safe
        // up and running for a few seconds: this launch counts as a good one
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { LaunchGuard.succeeded() }
    }
    private var safeMode = false
    private var commitsSinceSave = 0

    /// iOS is short of memory: everything the keyboard can rebuild goes (the emoji page when it is not showing, the
    /// decoder's last result), and the learned words are written out, so the keyboard is not the process iOS ends.
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        if !emojiShown, let p = emojiPanelIfLoaded {
            p.removeFromSuperview()
            emojiPanelIfLoaded = nil
        }
        engine.trim()
        memoryWarnings += 1
    }
    private var memoryWarnings = 0
    private var peakFootprint = 0.0

    // MARK: - 日光 / 夜灯

    /// The system's own light: dark mode, or a host that asks for a dark keyboard (Spotlight, some search bars).
    /// Read from the controller's view, which is never overridden (only `root` is).
    private var systemIsDark: Bool {
        // the glass iOS draws follows the keyboard's own traits; a host's keyboardAppearance does not change it on
        // iOS 26 (a field asking for a dark keyboard still shows pale glass), so it is not read here
        view.traitCollection.userInterfaceStyle == .dark
    }

    /// The glass under the keyboard is always the system's (light or dark, as the system or the host asks), and it
    /// runs beyond the keyboard's view, so nothing can recolour it without leaving a box inside a grey frame. So the
    /// light is split: everything that sits on the glass — the candidate strip, the emoji page, settings — follows the
    /// glass and stays readable on it; the keys (and Mosto) follow the light chosen: 自动 the glass's, 日光 / 夜灯
    /// their own. Night on a light system is violet vinyl keys on pale glass; day on a dark one, cream keys on dark.
    private func applyAppearance() {
        let sysDark = systemIsDark
        let mode = KeyboardSettings.shared.appearance
        let night = mode == 1 ? false : mode == 2 ? true : sysDark
        // a host that asks for a dark keyboard while the system is light gets dark glass: follow it
        let glass: UIUserInterfaceStyle = .unspecified   // the strip, emoji page and settings follow the glass itself
        let keys: UIUserInterfaceStyle = mode == 0 ? .unspecified : (night ? .dark : .light)
        let changed = night != isNight || root.overrideUserInterfaceStyle != glass || keyboard.overrideUserInterfaceStyle != keys
        if changed, root.window != nil {
            // a short crossfade instead of a flash when the light changes under the keyboard
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.18
            root.layer.add(fade, forKey: "light")
        }
        isNight = night
        root.overrideUserInterfaceStyle = glass
        keyboard.overrideUserInterfaceStyle = keys
        tintView.night = night
        tintView.forcedNight = false
        tintView.forcedDay = false
        candidateBar.mosto.setNight(night)
        candidateBar.showsMosto = true    // by day and at night: only his light follows the keyboard's
        settingsPanel.setNight(night)
    }

    func applySettings() {
        let s = KeyboardSettings.shared
        let newScheme = PinyinScheme(rawValue: s.scheme) ?? .xiaohe
        if newScheme != scheme, !taps.isEmpty { commitRaw() }     // keys typed under the other scheme mean something else
        scheme = newScheme
        engine.configure(scheme: newScheme, correction: s.autocorrect, english: s.english)
        hapticsOn = s.feedback
        soundOn = s.keySound
        if !settingsPanel.isHidden {
            let n = engine.counts()
            settingsPanel.setLearned("词库 \(n.lexicon) 条 · 已学习 \(n.learned) 个词")
        }
        let d = keyboard.stats
        let mem = memoryFootprintMB()
        peakFootprint = max(peakFootprint, mem)
        settingsPanel.setDiagnostics("本次按键 \(d.began) 次：输入 \(d.emitted)，系统取消后保留 \(d.cancelKept)，丢弃 \(d.dropped)；"
            + String(format: "按键响应（主线程）平均 %.1f ms、最长 %.0f ms；候选出现 平均 %.1f ms、最长 %.0f ms；",
                     handleCount > 0 ? handleTotal / Double(handleCount) : 0, handleMax,
                     candCount > 0 ? candTotal / Double(candCount) : 0, candMax)
            + String(format: "内存 %.0f MB（本次最高 %.0f MB）", mem, peakFootprint)
            + (memoryWarnings > 0 ? "，内存警告 \(memoryWarnings) 次" : "")
            + (safeMode ? "；上次启动未完成，本次以精简模式运行（无语言模型与中英混输），下次自动恢复" : ""))
        settingsPanel.setNote((hasFullAccess ? "" : "按键震动与按键音需在 设置 › 通用 › 键盘 › 键盘 › Mosto键盘 中开启“允许完全访问”。")
            + "键盘不联网，词库与学习记录只存在本机。")
        reconfigure()
        applyAppearance()
        if !taps.isEmpty { refresh() }
    }

    /// Haptics and sound, read once per settings change rather than from the defaults on every key.
    private var hapticsOn = true
    private var soundOn = true
    /// Click sounds are started off the main thread: AudioServicesPlaySystemSound can block for a few milliseconds
    /// (most of all on the first sound after the keyboard appears), and the key press must not wait for it.
    private static let soundQueue = DispatchQueue(label: "mosto.keysound", qos: .userInteractive)

    /// The system keyboard's three click sounds: letters and symbols, delete, and the other function keys.
    private func playFeedback(_ action: KeyAction) {
        guard hasFullAccess else { return }
        if hapticsOn { haptic.impactOccurred(); haptic.prepare() }
        guard soundOn else { return }
        let sound: SystemSoundID
        switch action {
        case .char, .space, .t9: sound = 1104
        case .delete, .deleteWord: sound = 1155
        default: sound = 1156
        }
        Self.soundQueue.async { AudioServicesPlaySystemSound(sound) }
    }

    // MARK: - Field adaptation

    private func adaptToField() {
        lastFieldTraits = fieldTraits()
        let proxy = host
        switch proxy.keyboardType ?? .default {
        case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad:
            page = .numpad   // digits-only fields (phone, code, amount) get the 九宫格 number pad
        case .numbersAndPunctuation:
            page = .numbers   // digits and punctuation: the full 123 page
        case .emailAddress, .URL, .webSearch:
            page = .letters
            if taps.isEmpty { chinese = false }
        default:
            page = .letters
            // back in ordinary text: the language the user last chose there (an address bar switched to English)
            if taps.isEmpty { chinese = preferredChinese }
        }
        if !chinese { updateAutoShift() }
        reconfigure()
    }

    /// nil = default return key, drawn as the ↵ icon like Gboard.
    private func returnLabel() -> (String?, Bool) {
        let type = host.returnKeyType ?? .default
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
        candidateBar.typing = !taps.isEmpty
        let (label, accent) = returnLabel()
        let ctx = LayoutContext(page: page, chinese: chinese, showGlobe: needsInputModeSwitchKey,
                                         returnLabel: label, returnIsAccent: accent,
                                         shifted: shifted, capsLock: capsLock,
                                         keyBorders: true,
                                         numberGrid: KeyboardSettings.shared.numberPad,   // 123: the 九宫格 pad or the full page
                                         pinyinGrid: KeyboardSettings.shared.pinyinGrid, composing: !taps.isEmpty)
        // most keystrokes change nothing on the keys: skip the work entirely (it ran twice per keystroke before)
        if ctx == lastContext { return }
        lastContext = ctx
        keyboard.configure(ctx)
    }

    // MARK: - Key handling

    private var handleTotal = 0.0, handleMax = 0.0, handleCount = 0
    /// From a key to its candidates appearing (decoded on the engine's thread).
    private var candTotal = 0.0, candMax = 0.0, candCount = 0

    func handle(_ action: KeyAction, tap: Tap?) {
        let t0 = CACurrentMediaTime()
        defer {
            afterLastKey = contextSnapshot()
            let ms = (CACurrentMediaTime() - t0) * 1000
            handleTotal += ms; handleCount += 1; handleMax = max(handleMax, ms)
            if handleCount % 40 == 0 { peakFootprint = max(peakFootprint, memoryFootprintMB()) }   // a few µs
        }
        candidateBar.dismissForget()
        let undo = undoable
        undoable = nil
        if action == .delete, let undo, undoCorrection(undo) { return }
        let enUndoNow = enUndo
        enUndo = nil
        if action == .delete, let u = enUndoNow, undoEnglishCorrection(u) { return }
        // English word state ends with anything that is not part of typing a word
        switch action {
        case .char, .space, .delete, .shift: break
        default: endEnglishWord()
        }
        // any key ends the suggestions, as on Gboard
        switch action {
        case .char(let s):
            if let tap, page == .letters { letter(s, tap: tap) } else { symbol(s) }
        case .space:
            space()
        case .delete:
            delete()
        case .ret:
            if !taps.isEmpty { commitRaw() } else { host.insertText("\n") }
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
            switch host.keyboardType ?? .default {
            case .emailAddress, .URL, .webSearch: break
            default: preferredChinese = chinese
            }
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
            guard d != "'" || !taps.isEmpty else { return }
            if taps.isEmpty { engine.setContext(host.documentContextBeforeInput ?? "") }
            lastInsertedSpace = false
            taps.append(Tap.t9(d))
            refresh()
        case .clearInput:
            if !taps.isEmpty { clearComposition() }
        case .deleteWord:
            deleteWord()
        case .emoji:
            if !taps.isEmpty { commitAll() }
            showEmoji(true)
        }
    }

    private func letter(_ s: String, tap: Tap) {
        lastInsertedSpace = false
        if chinese && !(shifted || capsLock) {
            // a new composition: the words are read in the context of the text before the cursor
            if taps.isEmpty { engine.setContext(host.documentContextBeforeInput ?? "") }
            taps.append(tap)
            refresh()
            return
        }
        // English, or Shift held in Chinese mode: direct letter.
        if !taps.isEmpty { commitAll() }
        let typed = (shifted || capsLock) ? s.uppercased() : s
        host.insertText(typed)
        if !chinese, english != nil {
            enTaps.append(tap)
            enTyped += typed
            updateEnglishSuggestions()
        }
        if shifted && !capsLock {
            shifted = false
            reconfigure()
        }
    }

    private func symbol(_ s: String) {
        if !taps.isEmpty { commitAll() }
        // English: a sentence or clause mark ends the word, applying its autocorrection first (as space does)
        if !chinese, !enTaps.isEmpty {
            if [".", ",", "!", "?", ";", ":"].contains(s) { applyEnglishAutocorrection() }
            endEnglishWord()
        }
        // Right after a digit, as the system Chinese keyboard: 。 is a decimal point and ： a time separator
        // (3.14, 12:30), never 3。14 or 12：30.
        var out = s
        if chinese, s == "。" || s == "：", let prev = host.documentContextBeforeInput?.last,
           prev.isASCII, prev.isNumber {
            out = s == "。" ? "." : ":"
        }
        host.insertText(out)
        lastInsertedSpace = false
        if !chinese && [".", "!", "?"].contains(s) { updateAutoShift(); reconfigure() }
    }

    private func space() {
        if !chinese, !enTaps.isEmpty {
            applyEnglishAutocorrection()
            endEnglishWord()
        }
        if !taps.isEmpty {
            if let c = currentResult()?.candidates.first, c.corrected, c.tapCount == taps.count, committedParts.isEmpty {
                let saved = taps
                select(0)
                if taps.isEmpty { undoable = (c.text, saved, c.syllables) }
                return
            }
            commitAll()
            return
        }
        let proxy = host
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
        host.deleteBackward()
        if !enTaps.isEmpty {
            enTaps.removeLast()
            if !enTyped.isEmpty { enTyped.removeLast() }
            if enTaps.isEmpty { endEnglishWord() } else { updateEnglishSuggestions() }
        }
        if !chinese { updateAutoShift(); reconfigure() }
    }

    // MARK: - English autocorrect

    /// The suggestions for the word being typed, shown in the strip: the autocorrection first (underlined, it is
    /// what space will type), then the word exactly as typed, then the other readings — written in the word's case.
    private func updateEnglishSuggestions() {
        guard let english, !enTaps.isEmpty else { endEnglishWord(); return }
        let list = english.suggestions(enTaps)
        let fix = KeyboardSettings.shared.autocorrect ? english.autocorrection(enTaps, suggestions: list) : nil
        enCorrection = fix.map { EnglishDecoder.cased($0.text, like: enTyped) }
        var texts: [String] = []
        if let c = enCorrection { texts.append(c) }
        texts.append(enTyped)
        for s in list where !s.text.isEmpty {
            let t = EnglishDecoder.cased(s.text, like: enTyped)
            if !texts.contains(t) { texts.append(t) }
        }
        enSuggestions = Array(texts.prefix(8))
        candidateBar.update(preedit: "", candidates: englishCandidates())
    }

    private func englishCandidates() -> [Candidate] {
        enSuggestions.enumerated().map { i, t in
            Candidate(text: t, tapCount: 0, syllables: [], corrected: i == 0 && enCorrection != nil, score: 0)
        }
    }

    /// Replace the word being typed (still in the field just before the cursor) with `text`.
    private func replaceEnglishWord(with text: String) {
        let before = host.documentContextBeforeInput ?? ""
        guard !enTyped.isEmpty, before.hasSuffix(enTyped) else { return }
        for _ in enTyped { host.deleteBackward() }
        host.insertText(text)
    }

    /// Space or a punctuation mark: put in the autocorrection, remembering it so a delete right after undoes it.
    private func applyEnglishAutocorrection() {
        guard let c = enCorrection, c != enTyped else { return }
        let before = host.documentContextBeforeInput ?? ""
        guard before.hasSuffix(enTyped) else { return }
        let saved = (typed: enTyped, taps: enTaps, corrected: c)
        replaceEnglishWord(with: c)
        enUndo = saved
    }

    /// Delete right after an autocorrection (and the space or mark that applied it): the typed word comes back.
    private func undoEnglishCorrection(_ u: (typed: String, taps: [Tap], corrected: String)) -> Bool {
        let before = host.documentContextBeforeInput ?? ""
        guard !before.isEmpty, before.dropLast().hasSuffix(u.corrected) else { return false }
        host.deleteBackward()                       // the space / mark
        for _ in u.corrected { host.deleteBackward() }
        host.insertText(u.typed)
        enTaps = u.taps
        enTyped = u.typed
        enCorrection = nil
        // shown again, but this word is now left as typed
        updateEnglishSuggestions()
        enCorrection = nil
        lastInsertedSpace = false
        return true
    }

    private func endEnglishWord() {
        guard !enTaps.isEmpty || !enSuggestions.isEmpty else { return }
        enTaps = []
        enTyped = ""
        enSuggestions = []
        enCorrection = nil
        if taps.isEmpty { candidateBar.update(preedit: "", candidates: []) }
    }

    /// Held delete: the whole composition, else back over one word — two Chinese characters, or a Latin word with
    /// the spaces before it, or a run of punctuation.
    private func deleteWord() {
        lastInsertedSpace = false
        if !taps.isEmpty { clearComposition(); return }
        endEnglishWord()
        let before = host.documentContextBeforeInput ?? ""
        guard let last = before.last else { host.deleteBackward(); return }
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
        for _ in 0..<max(count, 1) { host.deleteBackward() }
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
        let proxy = host
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

    /// The keys changed: their letters go into the field at once (marked text, underlined); the engine decodes in the
    /// background and the candidates are shown when they arrive — unless more keys came in meanwhile.
    private func refresh(literal: Bool = false) {
        generation += 1
        literalGeneration = literal
        let gen = generation
        let asked = CACurrentMediaTime()
        if !taps.contains(where: { $0.group }) { setMarked(String(taps.map { $0.key })) }
        else if !engine.isLoaded {
            // 九宫格 before any pinyin has been read (engine still loading, or it failed): the digits, so a key
            // press is never invisible; the pinyin replaces them as soon as it is known
            setMarked(String(taps.map { $0.key }))
        }
        reconfigure()
        engine.decode(taps, literal: literal, generation: gen) { [weak self] out in
            guard let self, gen == self.generation, let out else { return }
            let ms = (CACurrentMediaTime() - asked) * 1000
            self.candTotal += ms; self.candCount += 1; self.candMax = max(self.candMax, ms)
            self.show(out, generation: gen)
        }
    }

    private func setMarked(_ marked: String) {
        host.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0))
        hasMarkedText = true
        markedString = marked
        markedHistory.append(marked)
        if markedHistory.count > 12 { markedHistory.removeFirst() }
    }

    private func show(_ out: EngineHost.Output, generation gen: Int) {
        guard !taps.isEmpty else { return }
        let r = out.result
        result = r
        resultGeneration = gen
        // 九宫格 keys have no single letter: the field shows the pinyin read from them
        if taps.contains(where: { $0.group }) {
            let py = r.preedit.replacingOccurrences(of: " ", with: "")
            if !hasMarkedText || py != markedString { setMarked(py) }
        }
        candidateBar.update(preedit: r.preedit, candidates: r.candidates)
        if !grid.isHidden { grid.show(r.candidates) }
        updateSyllablePicker(out.choices)
    }

    /// The candidates for exactly the keys typed now (a commit needs them): the last ones received when they are
    /// current, else decoded at once — this waits only for a decode already under way.
    private func currentResult() -> Decoder.Result? {
        if resultGeneration == generation, let r = result { return r }
        guard !taps.isEmpty, let out = engine.decodeNow(taps, literal: literalGeneration, generation: generation) else { return result }
        show(out, generation: generation)
        return out.result
    }

    /// `shown`: the candidate the user saw and tapped; if the keys changed since it was shown, the same word is
    /// looked up in the current candidates (an index into a list that has changed would pick something else).
    private func select(_ index: Int, shown: Candidate? = nil) {
        guard let r = currentResult() else { return }
        var i = index
        if let shown, i >= r.candidates.count || r.candidates[i].text != shown.text || r.candidates[i].tapCount != shown.tapCount {
            guard let j = r.candidates.firstIndex(where: { $0.text == shown.text && $0.tapCount == shown.tapCount }) else { return }
            i = j
        }
        guard i < r.candidates.count else { return }
        let c = r.candidates[i]
        guard c.tapCount > 0, c.tapCount <= taps.count else { return }
        insertCommitted(c.text)
        // Learn: the word itself and where this user's finger actually lands.
        if !c.syllables.isEmpty {
            engine.learn(syllables: c.syllables, text: c.text)
            committedParts.append((c.text, c.syllables))
            for (tap, key) in zip(taps.prefix(c.tapCount), c.intendedKeys) { spatial.observe(tap: tap, intended: key) }
            // the touch habits are written out every so often too (iOS may end the keyboard without notice)
            commitsSinceSave += 1
            if commitsSinceSave >= 30 {
                commitsSinceSave = 0
                KeyboardSettings.shared.touchOffset = (spatial.offsetX, spatial.offsetY)
                KeyboardSettings.shared.keyOffsets = spatial.keyOffsetsList
            }
        }
        taps.removeFirst(min(c.tapCount, taps.count))
        if !taps.isEmpty { engine.setContext(committedParts.map { $0.text }.joined().isEmpty ? c.text : committedParts.map { $0.text }.joined()) }
        if taps.isEmpty {
            engine.learn(parts: committedParts)
            clearComposition()
        } else {
            refresh()
        }
    }

    /// Delete right after an auto-corrected commit: take the word back out, put the typed keys back into the
    /// composition and show them uncorrected, so the next space types what was actually pressed.
    private func undoCorrection(_ u: (text: String, taps: [Tap], syllables: [UInt16])) -> Bool {
        guard taps.isEmpty, (host.documentContextBeforeInput ?? "").hasSuffix(u.text) else { return false }
        for _ in u.text { host.deleteBackward() }
        if !u.syllables.isEmpty { engine.unlearn(syllables: u.syllables, text: u.text) }
        taps = u.taps
        refresh(literal: true)
        return true
    }

    /// Long press on a candidate this user taught the keyboard: offer to remove it from what was learned.
    /// Words from the built-in lexicon cannot be removed, so nothing is offered for them.
    private func offerForget(_ i: Int) {
        guard let r = result, i < r.candidates.count else { return }
        let c = r.candidates[i]
        guard !c.syllables.isEmpty, engine.knows(syllables: c.syllables, text: c.text) else { return }
        candidateBar.offerForget(c.text) { [weak self] in
            self?.engine.forget(syllables: c.syllables, text: c.text)
            if self?.taps.isEmpty == false { self?.refresh() }
        }
    }

    private func commitAll() {
        var guardCount = 0
        while !taps.isEmpty && guardCount < 32 {
            guardCount += 1
            if let c = currentResult()?.candidates.first, c.tapCount > 0, !c.syllables.isEmpty || c.isEnglish {
                select(0)
            } else {
                commitRaw()
            }
        }
        if !taps.isEmpty { commitRaw() }   // a very long run: whatever is left goes in as typed, never lost
    }

    /// 九宫格: show the syllable column while keypad keys are being composed (it covers ， 。 ？ meanwhile).
    private func updateSyllablePicker(_ choices: (start: Int, choices: [(text: String, keys: [Character])])) {
        guard taps.contains(where: { $0.group }), let frame = keyboard.keypadSideColumn() else {
            syllablePicker.isHidden = true
            keyboard.setSideColumnHidden(false)
            return
        }
        syllableChoices = choices
        guard !syllableChoices.choices.isEmpty else { syllablePicker.isHidden = true; keyboard.setSideColumnHidden(false); return }
        keyboard.setSideColumnHidden(true)
        syllablePicker.frame = frame
        syllablePicker.show(syllableChoices.choices.map { $0.text })
        syllablePicker.isHidden = false
        keyboard.bringSubviewToFront(syllablePicker)
    }

    /// The keypad keys of the chosen syllable become its exact letters; the rest decodes around them.
    func pickSyllable(_ i: Int) {
        let (start, choices) = syllableChoices
        guard i < choices.count, start + choices[i].keys.count <= taps.count else { return }
        playFeedback(.t9("2"))
        taps.replaceSubrange(start..<(start + choices[i].keys.count), with: choices[i].keys.map { Tap.exact($0) })
        refresh()
    }

    /// Insert committed text; it replaces the marked pinyin when there is one.
    private func insertCommitted(_ text: String) {
        host.insertText(text)
        hasMarkedText = false
        markedString = ""
    }

    private func commitRaw() {
        // 九宫格 keys are digits: what "the letters" means there is the pinyin read from them
        // (with no engine — it failed to load — the keys themselves, so nothing typed is ever lost)
        let raw = taps.contains(where: { $0.group })
            ? (currentResult()?.preedit ?? String(taps.map { $0.key })).replacingOccurrences(of: " ", with: "")
            : String(taps.map { $0.key })
        insertCommitted(raw)
        clearComposition()
    }

    private func clearComposition() {
        markedHistory.removeAll()
        if hasMarkedText {
            host.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            host.unmarkText()
            hasMarkedText = false
        }
        taps.removeAll()
        generation += 1          // a decode still under way for these keys is dropped when it comes back
        syllablePicker.isHidden = true
        keyboard.setSideColumnHidden(false)
        result = nil
        committedParts.removeAll()
        candidateBar.update(preedit: "", candidates: [])
        showGrid(false)
        reconfigure()
    }

    // MARK: - Candidates

    func candidateTapped(_ i: Int) {
        if taps.isEmpty, !enTaps.isEmpty, i < enSuggestions.count {
            // an English suggestion replaces the word being typed, followed by a space
            replaceEnglishWord(with: enSuggestions[i])
            host.insertText(" ")
            lastInsertedSpace = true
            endEnglishWord()
            updateAutoShift(); reconfigure()
            return
        }
        // the word the user saw: the strip shows `result`
        select(i, shown: result.flatMap { i < $0.candidates.count ? $0.candidates[i] : nil })
    }

    // MARK: - Panels

    private func showGrid(_ on: Bool) {
        if on {
            // English mode lists its own suggestions (the same ones as the strip, in the same order)
            if taps.isEmpty, !enSuggestions.isEmpty { grid.show(englishCandidates()) }
            else if let r = result { grid.show(r.candidates) }
        }
        grid.isHidden = !on
        // panels sit on the same system glass as the keys (no opaque sheet stacked on it): hide what is underneath
        keyboard.isHidden = on || !settingsPanel.isHidden || emojiShown
    }

    private func showSettings(_ on: Bool) {
        settingsPanel.isHidden = !on        // first: applySettings fills in the counts only for a visible panel
        if on { showEmoji(false); settingsPanel.load(); applySettings() }
        candidateBar.isHidden = on
        keyboard.isHidden = on || !grid.isHidden
    }

    // MARK: - 表情

    private var emojiShown = false

    /// Built on first use (the emoji list is read then), on the same glass as the keys.
    private func makeEmojiPanel() -> EmojiPanelView {
        let p = EmojiPanelView()
        p.isHidden = true
        root.addSubview(p)
        p.onEmoji = { [weak self] e in
            guard let self else { return }
            self.playFeedback(.char(e))
            self.host.insertText(e)
            self.lastInsertedSpace = false
        }
        p.onDelete = { [weak self] in
            guard let self else { return }
            self.playFeedback(.delete)
            self.host.deleteBackward()
        }
        p.onBack = { [weak self] in self?.playFeedback(.page(.letters)); self?.showEmoji(false) }
        p.onSettings = { [weak self] in self?.showSettings(true) }
        return p
    }

    /// The emoji page covers the keys and the candidate strip, as the system emoji keyboard does.
    private func showEmoji(_ on: Bool, kaomoji: Bool = false) {
        guard on != emojiShown else { return }
        emojiShown = on
        if on {
            showGrid(false)
            endEnglishWord()
            emojiPanel.setChinese(chinese)
            emojiPanel.frame = CGRect(x: view.safeAreaInsets.left, y: 0, width: view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right, height: view.bounds.height)
            emojiPanel.load(kaomoji: kaomoji)
            root.bringSubviewToFront(emojiPanel)
        } else if !chinese {
            updateAutoShift()
            reconfigure()
        }
        if on { emojiPanel.isHidden = false } else { emojiPanelIfLoaded?.isHidden = true }
        candidateBar.isHidden = on || !settingsPanel.isHidden
        keyboard.isHidden = on || !grid.isHidden || !settingsPanel.isHidden
    }
}
