import UIKit

/// The scrolling row of the candidate strip: the strip reads its touches (tap, slide, hold — StripGesture) and the
/// system's scrolling gives the swipe its inertia and bounce.
final class CandidateStrip: UIScrollView {
    weak var owner: CandidateBarView?
    /// Whether the row was still gliding when the finger came down — read before any recogniser stops it, so that
    /// touch only stops the glide and never types the candidate under it.
    private(set) var glidingAtDown = false
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if event?.type == .touches { glidingAtDown = isDecelerating }
        return super.hitTest(point, with: event)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let t = touches.first, let o = owner else { return }
        o.stripTouch(.began, at: t.location(in: o), time: CACurrentMediaTime())
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let t = touches.first, let o = owner else { return }
        o.stripTouch(.moved, at: t.location(in: o), time: CACurrentMediaTime())
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let t = touches.first, let o = owner else { return }
        o.stripTouch(.ended, at: t.location(in: o), time: CACurrentMediaTime())
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard let t = touches.first, let o = owner else { return }
        o.stripTouch(.cancelled, at: t.location(in: o), time: CACurrentMediaTime())
    }
}

/// Top strip, as on the system keyboard: every candidate in one row that scrolls sideways (the first screen full,
/// the last one cut at the edge where more follow), and a chevron that opens the full grid. Idle it stays empty —
/// only Mosto sits at its left. The pinyin is written into the text field as marked text; with that turned off it
/// shows above the candidates.
final class CandidateBarView: UIView, UIScrollViewDelegate {
    var onSelect: ((Int) -> Void)?
    var onExpand: (() -> Void)?
    var onSettings: (() -> Void)?
    /// Mosto: a tap opens his 颜文字, a double tap switches 日光 / 夜灯.
    var onMostoTap: (() -> Void)?
    var onMostoDoubleTap: (() -> Void)?
    /// Long press on a candidate (to offer removing a learned word).
    var onLongPress: ((Int) -> Void)?
    /// Tap on the leading raw-key preview pill: commits the literal typed letters immediately.
    var onPreeditTap: (() -> Void)?

    private let preeditDock = UIView()
    private let preeditClip = UIView()
    private let preedit = UILabel()
    private let preeditFade = CAGradientLayer()
    private let preeditCaret = CALayer()
    /// After a corrected word went in: "↩ nihap" at the start of the strip puts the keys back as typed (the same
    /// as pressing delete right away). After a swipe that cleared the composition: the keys it cleared.
    private let undoChip = UIButton(type: .system)
    var onUndo: (() -> Void)?
    private var undoText: String?
    private var longPressTimer: Timer?
    private var forgetTimer: Timer?
    var idleAccessibilityViews: [UIView] = []
    /// The candidates, in a row that scrolls; inside a box whose mask fades the edges where more candidates are.
    private let stripBox = UIView()
    private let strip = CandidateStrip()
    private let fade = CAGradientLayer()
    private let expandButton = UIButton(type: .system)
    let mosto = MostoView()
    private var labels: [UILabel] = []
    private var pool: [UILabel] = []
    private var dividerPool: [CALayer] = []
    /// Zero-width 2pt focus glow bar beneath slot 0 when autocorrect engaged (replaces noisy jr->ke text).
    private let correctionBar = CALayer()
    private let clearFilament = CALayer()
    private var clearSwipeProgress: CGFloat = 0
    private var clearSwipeArmed = false
    /// What each pooled label shows now (so a label is only redrawn when it changes).
    private var poolKeys: [String] = []
    private var activeFixes: [Fix] = []
    private var activePinpoint = CorrectionPinpoint(slipped: [], missingAnchors: [])
    private var isPrediction = false
    private var isMathResult = false
    var gridExpanded = false { didSet { if gridExpanded != oldValue { setNeedsLayout(); layoutIfNeeded() } } }
    private var candidates: [Candidate] = []
    /// Candidates laid out so far (the row is laid out a screen or two ahead of what is shown), their widths, and
    /// measured widths by text and caption, kept through a composition.
    private(set) var visibleCount = 0
    private var widths: [CGFloat] = []
    private var widthCache: [String: CGFloat] = [:]
    private var gesture = StripGesture()
    /// The test bench drives touches with its own clock: the hold is checked against it, no timer runs.
    private var benchTouches = false
    /// Mosto in the idle corner, by day and at night alike (only his light changes with the keyboard's).
    var showsMosto = false { didSet { if showsMosto != oldValue { update(preedit: preeditRaw, candidates: candidates, prediction: isPrediction) } } }
    private var mostoWanted = false
    private var mostoTimer: Timer?
    private var lastExpandSym: String = ""
    private var lastExpandExpanded = false
    private static var expandImages: [String: UIImage] = [:]
    /// Raw typed-key pill at the start of the candidate row (when not writing inline marked text).
    var showsPreedit = false { didSet { setNeedsLayout() } }
    /// Xiaohe 2-key rhythm kerning in the raw-letter pill (adds subtle 2.5pt gap every 2 keys & accents odd trailing key).
    var xiaoheRhythm = false { didSet { if xiaoheRhythm != oldValue { applyPreeditText(preeditRaw) } } }
    private var preeditRaw = ""

    static var font: UIFont { Theme.font(19, .regular) }
    static var firstFont: UIFont { Theme.font(19, .medium) }
    static var fixFont: UIFont { Theme.font(10.5, .semibold) }
    /// Below this height (landscape) a caption sits beside its candidate, not under it.
    static let twoLineHeight: CGFloat = 44

    /// Under an auto-corrected first choice, what was corrected: the keys as typed → the spelling read (hap → hao),
    /// at most two syllables, else how many; English: the word as typed, struck through.
    static func caption(for c: Candidate) -> NSAttributedString? {
        guard c.corrected else { return nil }
        let out = NSMutableAttributedString()
        let typedAttrs: [NSAttributedString.Key: Any] = [.font: fixFont, .foregroundColor: Theme.captionTyped]
        let meantAttrs: [NSAttributedString.Key: Any] = [.font: fixFont, .foregroundColor: Theme.captionMeant]
        // more than two in a long sentence: the one nearest the cursor (the last), and how many more
        let shown = c.fixes.count > 2 ? [c.fixes[c.fixes.count - 1]] : c.fixes
        for (k, f) in shown.enumerated() {
            if k > 0 { out.append(NSAttributedString(string: "  ", attributes: typedAttrs)) }
            out.append(NSAttributedString(string: f.typed, attributes: typedAttrs))
            out.append(NSAttributedString(string: "→", attributes: typedAttrs))
            out.append(NSAttributedString(string: f.meant, attributes: meantAttrs))
        }
        if c.fixes.count > 2 { out.append(NSAttributedString(string: " 等 \(c.fixes.count) 处", attributes: typedAttrs)) }
        return out.length > 0 ? out : NSAttributedString(string: "已纠错", attributes: meantAttrs)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear   // root provides single uniform hit-test backing
        preeditDock.backgroundColor = Theme.preeditPillBg
        preeditDock.layer.borderWidth = 0.5
        preeditDock.layer.borderColor = Theme.preeditPillBorder.resolvedColor(with: traitCollection).cgColor
        preeditDock.layer.cornerCurve = .continuous
        preeditDock.clipsToBounds = true
        preeditDock.isHidden = true
        preeditDock.isAccessibilityElement = true
        preeditDock.accessibilityTraits = .button
        preeditDock.accessibilityHint = "轻点直接上屏原字母"
        let preeditTap = UITapGestureRecognizer(target: self, action: #selector(preeditTapped))
        preeditTap.delaysTouchesBegan = false
        preeditTap.delaysTouchesEnded = false
        preeditDock.addGestureRecognizer(preeditTap)
        preeditClip.isUserInteractionEnabled = false
        preeditClip.clipsToBounds = true
        preeditDock.addSubview(preeditClip)
        preedit.font = Theme.font(11.5, .medium)
        preedit.textColor = Theme.secondaryText
        preedit.textAlignment = .left
        preedit.lineBreakMode = .byClipping
        preedit.isUserInteractionEnabled = false
        preeditClip.addSubview(preedit)
        preeditFade.startPoint = CGPoint(x: 0, y: 0.5)
        preeditFade.endPoint = CGPoint(x: 1, y: 0.5)
        preeditFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        preeditCaret.cornerRadius = 0.75
        preeditCaret.backgroundColor = Theme.correctedMark.resolvedColor(with: traitCollection).withAlphaComponent(0.78).cgColor
        preeditDock.layer.addSublayer(preeditCaret)
        addSubview(preeditDock)
        // the row scrolls with the system's own inertia and bounce; no scroll bar; a finger that lands highlights
        // at once, and the scrolling takes the touch over (no selection) once it starts
        strip.owner = self
        strip.delegate = self
        strip.showsHorizontalScrollIndicator = false
        strip.showsVerticalScrollIndicator = false
        strip.alwaysBounceHorizontal = false; strip.bounces = false
        strip.alwaysBounceVertical = false
        strip.decelerationRate = .normal
        strip.delaysContentTouches = false
        strip.canCancelContentTouches = false; strip.panGestureRecognizer.cancelsTouchesInView = false; strip.panGestureRecognizer.delaysTouchesBegan = false; strip.panGestureRecognizer.delaysTouchesEnded = false
        strip.scrollsToTop = false
        strip.disableAllEdgeEffects()
        strip.backgroundColor = .clear
        strip.panGestureRecognizer.addTarget(self, action: #selector(stripPanned(_:)))
        correctionBar.cornerRadius = 1
        correctionBar.zPosition = 10
        correctionBar.isHidden = true
        strip.layer.addSublayer(correctionBar)
        stripBox.backgroundColor = .clear
        stripBox.addSubview(strip)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        addSubview(stripBox)
        bringSubviewToFront(preeditDock)
        clearFilament.cornerRadius = 1
        clearFilament.zPosition = 20
        clearFilament.isHidden = true
        layer.addSublayer(clearFilament)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        expandButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: cfg), for: .normal)
        expandButton.tintColor = Theme.secondaryText
        addSubview(expandButton)
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        var uc = UIButton.Configuration.filled()
        uc.cornerStyle = .capsule
        uc.baseBackgroundColor = Theme.correctedTint
        uc.baseForegroundColor = Theme.correctedMark
        uc.image = UIImage(systemName: "arrow.uturn.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        uc.imagePadding = 4
        uc.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 11)
        undoChip.configuration = uc
        undoChip.isHidden = true
        undoChip.addAction(UIAction { [weak self] _ in self?.onUndo?() }, for: .touchUpInside)
        addSubview(undoChip)
        // Mosto sits in the idle corner; a tap opens settings (also reachable from the ⚙︎ key)
        addSubview(mosto)
        let double = UITapGestureRecognizer(target: self, action: #selector(mostoDoubleTapped))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: self, action: #selector(mostoTapped))
        single.require(toFail: double)
        mosto.addGestureRecognizer(double)
        mosto.addGestureRecognizer(single)
        mosto.onActivate = { [weak self] in self?.onMostoTap?() }
        mosto.onToggleLight = { [weak self] in self?.onMostoDoubleTap?() }
        update(preedit: "", candidates: [])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func preeditTapped() {
        preeditDock.alpha = 0.55
        UIView.animate(withDuration: 0.14) { self.preeditDock.alpha = 1 }
        onPreeditTap?()
    }

    @objc private func expandTapped() { if gridExpanded || !candidates.isEmpty { onExpand?() } else { onSettings?() } }

    /// Exact character indices in the raw typed preedit string highlighted by active autocorrection `fixes`.
    struct CorrectionPinpoint: Equatable {
        let slipped: Set<Int>
        let missingAnchors: Set<Int>
        var isEmpty: Bool { slipped.isEmpty && missingAnchors.isEmpty }
    }

    /// Maps decoder `Fix` syllables back onto the live raw keystroke string so slipped, extra, or omitted keys
    /// light up in place inside `preeditDock` and `StudioTextPaper`.
    static func correctionPinpoint(in raw: String, fixes: [Fix]) -> CorrectionPinpoint {
        guard !raw.isEmpty, !fixes.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return CorrectionPinpoint(slipped: [], missingAnchors: [])
        }
        let rawChars = Array(raw)
        var cursor = 0
        var slipped: Set<Int> = []
        var missingAnchors: Set<Int> = []

        for (fixIdx, fix) in fixes.enumerated() {
            let typed = Array(fix.typed)
            let meant = Array(fix.meant)
            guard !typed.isEmpty, !meant.isEmpty, typed != meant, cursor < rawChars.count else { continue }
            var matchStart: Int?
            if let exact = fix.offset, exact >= cursor, exact + typed.count <= rawChars.count,
               Array(rawChars[exact..<(exact + typed.count)]) == typed {
                matchStart = exact
            } else if typed.count == 1 {
                let matches = (cursor..<rawChars.count).filter { rawChars[$0] == typed[0] }
                if matches.count == 1 {
                    matchStart = matches[0]
                } else if fixIdx == fixes.count - 1, let last = matches.last, last == rawChars.count - 1 {
                    matchStart = last
                }
            } else if typed.count <= rawChars.count - cursor {
                let limit = rawChars.count - typed.count
                for s in cursor...limit {
                    var ok = true
                    for k in 0..<typed.count where rawChars[s + k] != typed[k] {
                        ok = false; break
                    }
                    guard ok else { continue }
                    // Avoid mistaking an earlier complete syllable (e.g. "tia" inside "jintian") for an omitted syllable.
                    if meant.count > typed.count, s + meant.count <= rawChars.count,
                       Array(rawChars[s..<(s + meant.count)]) == meant {
                        continue
                    }
                    matchStart = s
                    break
                }
            }
            guard let start = matchStart else { continue }
            let n = typed.count, m = meant.count
            var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
            for i in 0...n { dp[i][0] = i }
            for j in 0...m { dp[0][j] = j }
            for i in 1...n {
                for j in 1...m {
                    let sub = dp[i - 1][j - 1] + (typed[i - 1] == meant[j - 1] ? 0 : 1)
                    dp[i][j] = min(sub, dp[i - 1][j] + 1, dp[i][j - 1] + 1)
                }
            }
            var i = n, j = m
            var hadOmission = false
            var hadTapEdit = false
            while i > 0 || j > 0 {
                if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + (typed[i - 1] == meant[j - 1] ? 0 : 1) {
                    if typed[i - 1] != meant[j - 1] {
                        slipped.insert(start + i - 1)
                        hadTapEdit = true
                    }
                    i -= 1; j -= 1
                } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                    slipped.insert(start + i - 1)
                    hadTapEdit = true
                    i -= 1
                } else {
                    hadOmission = true
                    j -= 1
                }
            }
            if hadOmission && !hadTapEdit {
                missingAnchors.insert(start + n - 1)
            }
            cursor = start + n
        }
        return CorrectionPinpoint(slipped: slipped, missingAnchors: missingAnchors)
    }

    private func updatePreeditChrome() {
        let resolvedMark = Theme.correctedMark.resolvedColor(with: traitCollection)
        if !activePinpoint.isEmpty {
            preeditDock.layer.borderColor = resolvedMark.withAlphaComponent(0.42).cgColor
            preeditCaret.backgroundColor = resolvedMark.withAlphaComponent(0.95).cgColor
        } else {
            preeditDock.layer.borderColor = Theme.preeditPillBorder.resolvedColor(with: traitCollection).cgColor
            preeditCaret.backgroundColor = resolvedMark.withAlphaComponent(0.78).cgColor
        }
    }

    /// Formats the raw-key live dock: exact keys typed, 2-key breathing kerning in Xiaohe mode, and live
    /// autocorrection pinpoint highlights on slipped/omitted characters.
    private func applyPreeditText(_ text: String, fixes: [Fix] = []) {
        preeditRaw = text
        activeFixes = fixes
        let pinpoint = Self.correctionPinpoint(in: text, fixes: fixes)
        activePinpoint = pinpoint
        preeditDock.accessibilityLabel = text.isEmpty ? nil : "输入原字母 \(text)"
        if !pinpoint.isEmpty, !fixes.isEmpty {
            preeditDock.accessibilityValue = "已自动纠正：" + fixes.map { "\($0.typed) 改为 \($0.meant)" }.joined(separator: "，")
        } else {
            preeditDock.accessibilityValue = nil
        }
        updatePreeditChrome()
        guard !text.isEmpty else {
            preedit.attributedText = nil
            preedit.text = ""
            return
        }
        let font = Theme.font(11.5, .medium)
        let boldFont = Theme.font(11.5, .semibold)
        let baseColor = Theme.secondaryText.resolvedColor(with: traitCollection)
        let markColor = Theme.correctedMark.resolvedColor(with: traitCollection)
        let asciiLetters = text.allSatisfy { $0.isASCII && $0.isLetter }
        guard (xiaoheRhythm && asciiLetters) || !pinpoint.isEmpty else {
            preedit.attributedText = nil
            preedit.font = font
            preedit.textColor = baseColor
            preedit.text = text
            return
        }
        let attr = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: baseColor])
        let len = attr.length
        if xiaoheRhythm && asciiLetters && len >= 3 {
            var i = 1
            while i < len - 1 {
                attr.addAttribute(.kern, value: 2.5, range: NSRange(location: i, length: 1))
                i += 2
            }
        }
        // Highlight an odd trailing key (mid-syllable in 2-key Xiaohe) so key parity is legible at a glance.
        if xiaoheRhythm && asciiLetters && len % 2 == 1 && !pinpoint.slipped.contains(len - 1) && !pinpoint.missingAnchors.contains(len - 1) {
            attr.addAttribute(.foregroundColor, value: markColor, range: NSRange(location: len - 1, length: 1))
        }
        for idx in pinpoint.slipped where idx >= 0 && idx < len {
            attr.addAttributes([
                .foregroundColor: markColor,
                .font: boldFont,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: markColor,
            ], range: NSRange(location: idx, length: 1))
        }
        for idx in pinpoint.missingAnchors where idx >= 0 && idx < len {
            attr.addAttributes([
                .foregroundColor: markColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: markColor,
            ], range: NSRange(location: idx, length: 1))
        }
        preedit.attributedText = attr
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            preeditDock.backgroundColor = Theme.preeditPillBg
            applyPreeditText(preeditRaw, fixes: activeFixes)
            let divColor = Theme.candidateDivider.resolvedColor(with: traitCollection).cgColor
            for d in dividerPool { d.backgroundColor = divColor }
            correctionBar.backgroundColor = Theme.correctedMark.resolvedColor(with: traitCollection).cgColor
            layoutClearFilament()
            poolKeys = poolKeys.map { _ in "" }
            setNeedsLayout()
        }
    }

    /// The style changed (Mosto / 简洁): the colours set once at creation follow.
    func themeChanged() {
        expandButton.tintColor = Theme.secondaryText
        preedit.textColor = Theme.secondaryText
        preedit.font = Theme.font(11.5, .medium)
        preeditDock.backgroundColor = Theme.preeditPillBg
        applyPreeditText(preeditRaw, fixes: activeFixes)
        correctionBar.backgroundColor = Theme.correctedMark.resolvedColor(with: traitCollection).cgColor
        layoutClearFilament()
        var uc = undoChip.configuration
        uc?.baseBackgroundColor = Theme.correctedTint
        uc?.baseForegroundColor = Theme.correctedMark
        undoChip.configuration = uc
        let t = undoText, spoken = undoChip.accessibilityLabel
        undoText = nil; setUndo(t, spoken: spoken)
        widthCache = [:]
        poolKeys = poolKeys.map { _ in "" }
        setNeedsLayout()
    }

    /// 只读测试钩子：第 0 个候选当前的 caption 文本（联想态应为「联想」，候选态为纠错说明或 nil）。
    var firstCaptionForTests: String? { captionFor(0)?.string }
    /// 只读测试钩子：当前是否处于联想态。
    var predictionMarkForTests: Bool { isPrediction }
    var undoTextForTests: String? { undoText }
    func undoTapForTests() { onUndo?() }
    var correctionBarShownForTests: Bool { !correctionBar.isHidden }
    var preeditShownForTests: Bool { !preeditDock.isHidden }
    var preeditAttributedForTests: NSAttributedString? { preedit.attributedText }
    var preeditPinpointForTests: CorrectionPinpoint { activePinpoint }
    var preeditDockFrameForTests: CGRect { preeditDock.frame }
    var preeditOverflowFadeForTests: Bool { preeditClip.layer.mask === preeditFade }
    var widthCacheCountForTests: Int { widthCache.count }

    /// Offer (or withdraw, with nil) putting back keys: the ones a correction replaced, or the ones a swipe cleared.
    /// `spoken`: what VoiceOver says for it (by default, that it takes back a correction).
    func setUndo(_ typed: String?, spoken: String? = nil) {
        guard typed != undoText else { return }
        undoText = typed
        if let typed {
            var c = undoChip.configuration
            c?.attributedTitle = AttributedString(typed, attributes: AttributeContainer([.font: Theme.font(14, .semibold)]))
            undoChip.configuration = c
            undoChip.accessibilityLabel = spoken ?? "撤回纠错，恢复为 \(typed)"
            // the chip belongs to the strip's left corner: Mosto stays away while it is there
            setMosto(false)
        } else {
            setMosto(candidates.isEmpty && !typing && showsMosto)
        }
        undoChip.isHidden = typed == nil
        setNeedsLayout()
    }

    /// Continuous delete-left swipe or held-delete clutch progress (`0...1`) drives the strip's bottom warm-amber filament synchronously.
    func setClearProgress(_ progress: CGFloat, armed: Bool, dimContent: Bool = true) {
        let p = armed ? 1.0 : min(1, max(0, progress))
        clearSwipeProgress = p
        clearSwipeArmed = armed
        let a: CGFloat = dimContent ? (armed ? 0.35 : (p > 0.01 ? (1.0 - p * 0.40) : 1.0)) : 1.0
        stripBox.alpha = a
        expandButton.alpha = a
        preeditDock.alpha = a
        layoutClearFilament()
    }

    /// A swipe left off delete is armed: the candidates fade to show they are about to go (no animation: it follows
    /// the finger).
    func setClearPreview(_ on: Bool) {
        setClearProgress(on ? 1 : 0, armed: on)
    }

    private func layoutClearFilament() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if clearSwipeProgress <= 0.005 || bounds.width <= 20 {
            clearFilament.isHidden = true
            CATransaction.commit()
            return
        }
        clearFilament.isHidden = false
        let span = max(0, bounds.width - 20)
        let w = span * clearSwipeProgress
        let h: CGFloat = clearSwipeArmed ? 2.5 : 2.0
        clearFilament.frame = CGRect(x: bounds.width - 10 - w, y: bounds.height - h, width: w, height: h)
        let baseColor = Theme.plain ? Theme.correctedMark : Theme.dyn(Theme.gold, Theme.goldGlow)
        clearFilament.backgroundColor = baseColor.resolvedColor(with: traitCollection)
            .withAlphaComponent(clearSwipeArmed ? 1.0 : (0.55 + 0.45 * clearSwipeProgress)).cgColor
        CATransaction.commit()
    }

    var clearPreviewForTests: Bool { stripBox.alpha < 1 }
    var clearFilamentProgressForTests: CGFloat { clearSwipeProgress }

    // MARK: VoiceOver: each laid-out candidate is a button (the strip draws plain labels and reads raw touches)

    private final class CandidateElement: UIAccessibilityElement {
        var activate: (() -> Void)?
        override func accessibilityActivate() -> Bool { activate?(); return true }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = super.hitTest(point, with: event), hit !== self { return hit }
        if showsPreedit && !preeditDock.isHidden && !preeditRaw.isEmpty && preeditDock.frame.width > 0 {
            let expanded = CGRect(x: preeditDock.frame.minX, y: 0, width: preeditDock.frame.width, height: bounds.height)
            if expanded.contains(point) { return preeditDock }
        }
        return super.hitTest(point, with: event)
    }

    override var accessibilityElements: [Any]? {
        get {
            var out: [Any] = []
            let visibleIdle = idleAccessibilityViews.filter { !$0.isHidden }
            if !visibleIdle.isEmpty {
                out.append(contentsOf: visibleIdle)
            } else if !mosto.isHidden {
                out.append(mosto)
            }
            if !undoChip.isHidden { out.append(undoChip) }
            if showsPreedit && !preeditDock.isHidden && !preeditRaw.isEmpty { out.append(preeditDock) }
            for (i, l) in labels.enumerated() where !l.isHidden {
                let e = CandidateElement(accessibilityContainer: self)
                e.accessibilityLabel = i < candidates.count ? candidates[i].text : l.text
                if i < candidates.count, !isPrediction, let cap = Self.caption(for: candidates[i]) {
                    e.accessibilityValue = cap.string == "已纠错" ? "已纠错"
                        : "已纠错：" + candidates[i].fixes.map { "\($0.typed) 改为 \($0.meant)" }.joined(separator: "，")
                } else if isMathResult {
                    e.accessibilityValue = "心算结果"
                    e.accessibilityHint = "轻点插入"
                } else if isPrediction {
                    e.accessibilityValue = "联想，键盘猜的下一个词"
                    e.accessibilityHint = "轻点插入"
                }
                e.accessibilityTraits = .button
                if i == 0, !isPrediction { e.accessibilityHint = "首选，空格上屏" }
                e.accessibilityFrameInContainerSpace = strip.convert(l.frame, to: self)
                e.activate = { [weak self] in self?.onSelect?(i) }
                out.append(e)
            }
            if !expandButton.isHidden {
                expandButton.accessibilityLabel = (candidates.isEmpty && !gridExpanded) ? "键盘设置" : (gridExpanded ? "收起候选" : "全部候选")
                out.append(expandButton)
            }
            return out
        }
        set { }
    }

    /// VoiceOver's three-finger swipe: a screen of candidates at a time.
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let page = strip.bounds.width
        guard page > 0, !stripBox.isHidden else { return false }
        let maxX = max(0, strip.contentSize.width - page)
        var x = strip.contentOffset.x
        switch direction {
        case .right, .next: x = min(maxX, x + page)
        case .left, .previous: x = max(0, x - page)
        default: return false
        }
        guard x != strip.contentOffset.x else { return false }
        strip.setContentOffset(CGPoint(x: x, y: 0), animated: false)
        UIAccessibility.post(notification: .pageScrolled, argument: nil)
        return true
    }

    @objc private func mostoTapped() { onMostoTap?() }
    @objc private func mostoDoubleTapped() { mosto.hop(); onMostoDoubleTap?() }

    /// Immediately show typed keys in the leading single-row live keystroke dock (0 ms, 0 XPC).
    func setPreedit(_ text: String) {
        let changed = preeditRaw != text || !activeFixes.isEmpty
        if changed { applyPreeditText(text, fixes: []) }
        let show = showsPreedit && !isPrediction && !text.isEmpty
        if preeditDock.isHidden != !show || changed {
            preeditDock.isHidden = !show
            setNeedsLayout()
        }
    }

    /// `prediction`: the row shows next-word suggestions (联想) rather than candidates for typed keys.
    func update(preedit text: String, candidates: [Candidate], prediction: Bool = false, mathResult: Bool = false) {
        let firstFixes = (!prediction && !mathResult && candidates.first?.corrected == true) ? candidates[0].fixes : []
        if preeditRaw != text || activeFixes != firstFixes {
            applyPreeditText(text, fixes: firstFixes)
        }
        // another list (a new key, a commit): the row starts from the beginning again; the same list (the same keys
        // decoded once more) leaves it where the finger put it
        let changed = prediction != isPrediction || mathResult != isMathResult || candidates.count != self.candidates.count
            || !zip(candidates, self.candidates).allSatisfy { $0.text == $1.text }
        self.candidates = candidates
        isPrediction = prediction
        isMathResult = mathResult
        // widths are measured again from the cache (captions can change with the same words)
        widths = []
        if widthCache.count > 1500 { widthCache.removeAll(keepingCapacity: true) }
        if changed, strip.contentOffset != .zero {
            inUpdate = true
            strip.setContentOffset(.zero, animated: false)
            inUpdate = false
        }
        let busy = !candidates.isEmpty
        setMosto(!busy && !typing && showsMosto && undoText == nil)
        preeditDock.isHidden = text.isEmpty || prediction || !showsPreedit
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Mosto steps aside the moment typing starts (the strip is for candidates) and comes back only when the
    /// keyboard has been idle a moment, fading in rather than popping up — never flickering between words.
    /// Keys are being composed (the candidates may not have arrived yet): Mosto stays out of the way.
    var typing = false {
        didSet { if typing != oldValue { setMosto(!typing && candidates.isEmpty && showsMosto && undoText == nil); setNeedsLayout() } }
    }

    /// Mosto is (about to be) shown or put away — his night light follows him.
    var onMostoShown: ((Bool) -> Void)?

    /// Stop every timer owned by the candidate strip and Mosto when the keyboard is dismissed.
    func pauseTimers() {
        mostoTimer?.invalidate(); mostoTimer = nil
        longPressTimer?.invalidate(); longPressTimer = nil
        forgetTimer?.invalidate(); forgetTimer = nil
        mosto.pauseTimers()
    }

    private func setMosto(_ on: Bool) {
        // put away even when he was never asked for (a new strip starts with him hidden, 简洁 never shows him)
        if !on, !mostoWanted { mosto.isHidden = true; return }
        guard on != mostoWanted else { return }
        mostoWanted = on
        if !on { onMostoShown?(false) }
        mostoTimer?.invalidate(); mostoTimer = nil
        guard on else { mosto.layer.removeAllAnimations(); mosto.isHidden = true; return }
        mosto.isHidden = false
        mosto.transform = .identity
        if window == nil || UIAccessibility.isReduceMotionEnabled {
            mosto.alpha = 1
            onMostoShown?(true)
            return
        }
        mosto.alpha = 0
        onMostoShown?(true)
        UIView.animate(withDuration: 0.14, delay: 0, options: [.allowUserInteraction]) {
            self.mosto.alpha = 1
        }
        mostoTimer = Timer.scheduledTimer(withTimeInterval: 0.26, repeats: false) { [weak self] _ in
            guard let self, self.mostoWanted else { return }
            self.mosto.greet()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        // Inset neatly inside the 28pt idle Mosto capsule (zero overflow or clipping mismatch).
        let pillH = min(28, max(24, h - 12))
        let mSize = min(24, pillH - 4)
        mosto.frame = CGRect(x: 14, y: floor((h - mSize) / 2), width: mSize, height: mSize)
        let expandW: CGFloat = 36
        expandButton.frame = CGRect(x: bounds.width - expandW, y: 0, width: expandW, height: h)
        // Start at 10pt so the first element cleanly clears iOS 26/27 Liquid Glass top-left corner radius.
        var lead: CGFloat = 10
        if !undoChip.isHidden {
            let sz = undoChip.sizeThatFits(CGSize(width: 200, height: h))
            undoChip.frame = CGRect(x: 10, y: (h - sz.height) / 2, width: sz.width, height: sz.height)
            lead = undoChip.frame.maxX + 6
            preeditDock.frame = .zero
        } else if showsPreedit && !preeditDock.isHidden, !preeditRaw.isEmpty {
            let textW: CGFloat
            if let attr = preedit.attributedText, attr.length > 0 {
                textW = ceil(attr.size().width)
            } else {
                textW = ceil((preeditRaw as NSString).size(withAttributes: [.font: preedit.font ?? Theme.font(11.5, .medium)]).width)
            }
            let pillH = min(26, max(20, h - 14))
            let pillW: CGFloat
            if gridExpanded {
                pillW = max(60, bounds.width - expandW - 18)
            } else {
                let maxPillW = min(110, floor(bounds.width * 0.28))
                pillW = min(max(30, textW + 18), maxPillW)
            }
            preeditDock.layer.cornerRadius = pillH / 2
            preeditDock.frame = CGRect(x: 10, y: (h - pillH) / 2, width: pillW, height: pillH)
            lead = preeditDock.frame.maxX + 6

            let caretW: CGFloat = 1.5, caretGap: CGFloat = 2.0, padH: CGFloat = 7
            let maxInner = max(8, pillW - padH * 2 - caretW - caretGap)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if textW > maxInner {
                preeditClip.frame = CGRect(x: padH, y: 0, width: maxInner, height: pillH)
                preedit.frame = CGRect(x: maxInner - textW, y: 0, width: textW, height: pillH)
                preeditFade.frame = preeditClip.bounds
                preeditFade.locations = [0, NSNumber(value: Double(min(0.30, 12 / maxInner))), 1]
                if preeditClip.layer.mask !== preeditFade { preeditClip.layer.mask = preeditFade }
                preeditCaret.frame = CGRect(x: preeditClip.frame.maxX + caretGap, y: (pillH - 12) / 2, width: caretW, height: 12)
            } else {
                if preeditClip.layer.mask != nil { preeditClip.layer.mask = nil }
                let startX = gridExpanded ? (padH + 3) : floor((pillW - (textW + caretGap + caretW)) / 2)
                preeditClip.frame = CGRect(x: startX, y: 0, width: textW, height: pillH)
                preedit.frame = CGRect(x: 0, y: 0, width: textW, height: pillH)
                preeditCaret.frame = CGRect(x: startX + textW + caretGap, y: (pillH - 12) / 2, width: caretW, height: 12)
            }
            updatePreeditChrome()
            CATransaction.commit()
        } else {
            preeditDock.frame = .zero
        }
        // Keep stripBox and CandidateStrip spanning the FULL bar height (0..h) so taps on the upper third never miss.
        let box = CGRect(x: lead, y: 0, width: max(0, bounds.width - expandW - lead), height: h)
        if stripBox.frame != box { stripBox.frame = box }
        let inner = CGRect(origin: .zero, size: box.size)
        if strip.frame != inner { strip.frame = inner }
        // nothing to show: the strip takes no touches (or when grid is open and dock expands full-width above it)
        let hideStripForGridDock = gridExpanded && showsPreedit && !preeditDock.isHidden && !preeditRaw.isEmpty
        stripBox.isHidden = (candidates.isEmpty && !typing) || hideStripForGridDock
        layoutCandidates()
        layoutClearFilament()
    }

    /// Keep the candidate strip pure and high-density while composing (zero jr->ke / 原键 clutter).
    /// Only prediction mode keeps the subtle "联想" marker on slot 0 (or "心算" for trailing arithmetic).
    private func captionFor(_ i: Int) -> NSAttributedString? {
        if isMathResult {
            return i == 0 ? NSAttributedString(string: "心算", attributes: [.font: Self.fixFont, .foregroundColor: Theme.correctedMark]) : nil
        }
        if isPrediction {
            return i == 0 ? NSAttributedString(string: "联想", attributes: [.font: Self.fixFont, .foregroundColor: Theme.secondaryText]) : nil
        }
        return nil
    }

    /// The candidate's text as the label draws it: with its caption under it (portrait), or beside it on the same
    /// baseline, 4 pt after it (landscape, where the strip has no room for two lines).
    private func labelText(_ c: Candidate, caption cap: NSAttributedString, inline: Bool) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let capm = NSMutableAttributedString(attributedString: cap)
        if inline {
            let t = NSMutableAttributedString(string: c.text, attributes: [.font: Self.font, .foregroundColor: Theme.candidateText, .paragraphStyle: para])
            if t.length > 0 { t.addAttribute(.kern, value: 4, range: NSRange(location: t.length - 1, length: 1)) }
            capm.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: capm.length))
            t.append(capm)
            return t
        }
        para.lineSpacing = -1
        let t = NSMutableAttributedString(string: c.text + "\n", attributes: [.font: Self.font, .foregroundColor: Theme.candidateText, .paragraphStyle: para])
        capm.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: capm.length))
        t.append(capm)
        return t
    }

    /// Width of candidate `i` (cached by text, slot-0 weight, and caption): compact 14pt padding for 4-6 visible candidates.
    private func measure(_ i: Int, inline: Bool) -> CGFloat {
        let c = candidates[i]
        let cap = captionFor(i)
        let isFirst = i == 0 && !isPrediction
        let key = (isFirst ? "F" : "R") + (inline ? "1" : "0") + "\u{1}" + c.text + "\u{1}" + (cap?.string ?? "")
        if let w = widthCache[key] { return w }
        let f = isFirst ? Self.firstFont : Self.font
        let textW = (c.text as NSString).size(withAttributes: [.font: f]).width
        let w: CGFloat
        if let cap {
            w = inline ? max(38, ceil(textW + 4 + cap.size().width) + 16) : max(38, ceil(max(textW, cap.size().width)) + 16)
        } else {
            w = max(38, ceil(textW) + (isFirst ? 16 : 14))
        }
        widthCache[key] = w
        return w
    }

    /// Lay the row out from its start to two screens past what is shown (the rest only as the finger gets there:
    /// a single syllable can have hundreds of candidates). Labels & dividers are pooled and reused.
    private func layoutCandidates() {
        let viewW = strip.bounds.width
        let rowH = strip.bounds.height
        let topY: CGFloat = 4
        let labelH: CGFloat = max(18, rowH - 8)
        let inline = bounds.height < Self.twoLineHeight
        let need = strip.contentOffset.x + max(viewW, 1) * 2
        let pressed = gesture.highlighted
        let divColor = Theme.candidateDivider.resolvedColor(with: traitCollection).cgColor
        let divH: CGFloat = min(15, max(10, labelH * 0.45))
        let divY: CGFloat = (rowH - divH) / 2
        var x: CGFloat = 0
        var n = 0
        var showCorrectionBar = false
        var correctionFrame = CGRect.zero
        CATransaction.begin(); CATransaction.setDisableActions(true)
        while n < candidates.count && (x < need || n == 0) {
            let w: CGFloat
            if n < widths.count { w = widths[n] } else { w = measure(n, inline: inline); widths.append(w) }
            if pool.count <= n {
                let l = UILabel()
                l.font = Self.font
                l.textAlignment = .center
                l.lineBreakMode = .byTruncatingTail
                l.layer.cornerRadius = 9
                l.layer.cornerCurve = .continuous
                l.clipsToBounds = true
                strip.addSubview(l)
                pool.append(l)
                poolKeys.append("")
            }
            let l = pool[n]
            l.isHidden = false
            let frame = CGRect(x: x, y: topY, width: w, height: labelH)
            if l.frame != frame { l.frame = frame }
            let c = candidates[n]
            let cap = captionFor(n)
            let isFirst = n == 0 && !isPrediction
            let key = (isFirst ? "F" : "R") + (inline ? "1" : "0") + "\u{1}" + c.text + "\u{1}" + (cap?.string ?? "")
            if poolKeys[n] != key {
                poolKeys[n] = key
                l.textColor = Theme.candidateText
                l.font = isFirst ? Self.firstFont : Self.font
                if let cap {
                    l.numberOfLines = inline ? 1 : 2
                    l.attributedText = labelText(c, caption: cap, inline: inline)
                } else {
                    l.numberOfLines = 1
                    l.attributedText = nil
                    l.text = c.text
                }
            }
            // Clean, restrained focus highlight on slot 0 (spacebar target); zero text noise.
            let firstBg = (c.corrected || (isMathResult && n == 0)) ? Theme.correctedTint : Theme.firstCandidateTint
            l.backgroundColor = n == pressed ? Theme.functionKey : ((isFirst || (isMathResult && n == 0)) ? firstBg : .clear)
            if isFirst && c.corrected {
                let barW: CGFloat = min(14, max(8, w - 16))
                showCorrectionBar = true
                correctionFrame = CGRect(x: x + (w - barW) / 2, y: topY + labelH - 3, width: barW, height: 2)
            }
            if n > 0 {
                let di = n - 1
                if dividerPool.count <= di {
                    let d = CALayer()
                    d.backgroundColor = divColor
                    strip.layer.addSublayer(d)
                    dividerPool.append(d)
                }
                let d = dividerPool[di]
                let hideDiv = (n == 1 && !isPrediction) || n == pressed || (n - 1) == pressed
                d.isHidden = hideDiv
                if !hideDiv {
                    d.backgroundColor = divColor
                    d.frame = CGRect(x: x - 0.25, y: divY, width: 0.5, height: divH)
                }
            }
            x += w
            n += 1
        }
        let usedDivs = max(0, n - 1)
        if dividerPool.count > usedDivs {
            for d in dividerPool.dropFirst(usedDivs) where !d.isHidden { d.isHidden = true }
        }
        correctionBar.isHidden = !showCorrectionBar
        if showCorrectionBar {
            correctionBar.backgroundColor = Theme.correctedMark.resolvedColor(with: traitCollection).cgColor
            correctionBar.frame = correctionFrame
        }
        CATransaction.commit()
        if visibleCount != n || labels.count != n {
            for l in pool.dropFirst(n) where !l.isHidden { l.isHidden = true }
            labels = Array(pool.prefix(n))
        }
        visibleCount = n
        // the rest is still to be laid out: the row is as long as they would make it on average; exact once laid out
        let total = n == candidates.count || n == 0 ? x : x + CGFloat(candidates.count - n) * (x / CGFloat(n))
        let size = CGSize(width: total, height: rowH)
        if strip.contentSize != size { strip.contentSize = size }
        // ⌄: there are candidates past the edge (the full grid shows them all)
        let idleGear = candidates.isEmpty && !typing && undoText == nil && !gridExpanded && window != nil
        let sym = idleGear ? "slider.horizontal.3" : (gridExpanded ? "chevron.up" : "chevron.down")
        let symKey = "\(sym)_\(idleGear ? 1 : 0)_\(gridExpanded ? 1 : 0)"
        if symKey != lastExpandSym {
            lastExpandSym = symKey
            let img = Self.expandImages[symKey] ?? {
                let cfg = UIImage.SymbolConfiguration(pointSize: idleGear ? 15 : 16, weight: gridExpanded ? .semibold : .regular)
                let rendered = UIImage(systemName: sym, withConfiguration: cfg)
                if let rendered { Self.expandImages[symKey] = rendered }
                return rendered
            }()
            expandButton.setImage(img, for: .normal)
        }
        if gridExpanded != lastExpandExpanded {
            lastExpandExpanded = gridExpanded
            expandButton.tintColor = gridExpanded ? Theme.candidateText : Theme.secondaryText
            expandButton.backgroundColor = gridExpanded ? Theme.functionKey.withAlphaComponent(0.45) : .clear
            expandButton.layer.cornerRadius = 14
        }
        expandButton.isHidden = !((total > viewW + 0.5 && !isPrediction) || gridExpanded || idleGear)
        updateFade()
    }

    /// 12 pt fades at the edges where the row goes on (the right edge while more follow, the left once scrolled):
    /// the candidates thin out into the strip's own background — no colour, no shadow.
    private func updateFade() {
        let w = stripBox.bounds.width
        let x = strip.contentOffset.x
        let left = x > 0.5
        let right = x + w < strip.contentSize.width - 0.5
        guard w > 24, left || right, !stripBox.isHidden else {
            if stripBox.layer.mask != nil { stripBox.layer.mask = nil }
            return
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fade.frame = stripBox.bounds
        let e = Double(12 / w)
        fade.locations = [0, NSNumber(value: left ? e : 0), NSNumber(value: right ? 1 - e : 1), 1]
        if stripBox.layer.mask !== fade { stripBox.layer.mask = fade }
        CATransaction.commit()
    }

    // MARK: Scrolling

    private var inUpdate = false

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !inUpdate else { return }
        // less than a screen laid out ahead of what is shown: lay out the next
        let laidEnd = widths.prefix(visibleCount).reduce(0, +)
        if visibleCount < candidates.count, laidEnd - (scrollView.contentOffset.x + scrollView.bounds.width) < scrollView.bounds.width {
            layoutCandidates()
        } else {
            updateFade()
        }
    }

    @objc private func stripPanned(_ g: UIPanGestureRecognizer) {
        if abs(g.translation(in: strip).x) > 22 { stripScrollBegan() }
    }

    /// The strip began to scroll under the finger: no tap, no hold.
    private func stripScrollBegan() {
        if gesture.scrollBegan() {
            longPressTimer?.invalidate()
            setNeedsLayout()
        }
    }

    // MARK: Touches (tap, slide, hold: StripGesture)

    /// The candidate under a point of this view (an index into the full list), where the row shows it.
    private func candidateIndex(at p: CGPoint) -> Int? {
        let q = convert(p, to: strip)
        let leftSlop: CGFloat = (showsPreedit && !preeditDock.isHidden) ? 4 : 12
        guard q.y >= -16, q.x >= strip.bounds.minX - leftSlop, q.x < strip.bounds.maxX else { return nil }
        if let exact = labels.firstIndex(where: { ($0.frame.minX - 6) <= q.x && q.x < ($0.frame.maxX + 6) }) {
            return exact
        }
        if !labels.isEmpty {
            if q.x <= labels[0].frame.maxX + 10 { return 0 }
            // Fallback to nearest visible candidate within 12 pt gap so taps on inter-item spacing never miss.
            var best: (idx: Int, dist: CGFloat)?
            for (i, l) in labels.enumerated() where !l.isHidden {
                let d = q.x < l.frame.minX ? (l.frame.minX - q.x) : (q.x > l.frame.maxX ? (q.x - l.frame.maxX) : 0)
                if d <= 12, best == nil || d < best!.dist { best = (i, d) }
            }
            if let best { return best.idx }
        }
        return typing && labels.isEmpty && p.x < 120 ? 0 : nil
    }

    func stripTouch(_ phase: TouchSample.Phase, at p: CGPoint, time: CFTimeInterval) {
        switch phase {
        case .began:
            let idx = candidateIndex(at: p)
            let text = idx.flatMap { $0 < candidates.count ? candidates[$0].text : "" }
            // a finger that lands while the row is still gliding only stops it
            let gliding = benchGliding || ((strip.glidingAtDown || strip.isDecelerating) && strip.contentOffset.x > 24 && abs(strip.panGestureRecognizer.velocity(in: strip).x) > 120)
            gesture.begin(index: idx, text: text, at: p, time: time, stoppingScroll: gliding, canHold: !isPrediction)
            longPressTimer?.invalidate()
            if idx != nil, !isPrediction, !gliding, !benchTouches {
                // in the common run-loop modes: it fires while the scroll view tracks the finger too
                let t = Timer(timeInterval: StripGesture.holdTime, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.holdDue(at: self.gesture.began + StripGesture.holdTime)
                }
                RunLoop.main.add(t, forMode: .common)
                longPressTimer = t
            }
            setNeedsLayout()
        case .moved:
            if hypot(p.x - gesture.start.x, p.y - gesture.start.y) > 22, gesture.move(to: p) {
                longPressTimer?.invalidate()
                setNeedsLayout()
            }
        case .ended:
            longPressTimer?.invalidate()
            let idx = candidateIndex(at: p)
            let wasDown = gesture.down, wasSlid = gesture.slid, wasHeld = gesture.held
            var chosen = gesture.end(index: gesture.index, currentText: gesture.text).map { idx ?? $0 }
            // If candidates finished laying out between .began and .ended (ultra-fast tap right after typing),
            // commit the candidate now under the finger instead of dropping the tap.
            if chosen == nil, !benchTouches, wasDown, !wasSlid, !wasHeld, let endIdx = idx, endIdx < candidates.count {
                chosen = endIdx
            }
            setNeedsLayout()
            if let chosen { onSelect?(chosen) }
        case .cancelled:
            longPressTimer?.invalidate()
            if !benchTouches, !gesture.slid, !gesture.held, time - gesture.began < 0.35, let c = gesture.end(index: gesture.index, currentText: gesture.text).map({ candidateIndex(at: p) ?? $0 }) { onSelect?(c) } else { gesture.cancel() }
            setNeedsLayout()
        }
    }

    private func holdDue(at t: CFTimeInterval) {
        guard let i = gesture.hold(at: t) else { return }
        setNeedsLayout()
        onLongPress?(i)
    }

    // MARK: Test bench

    /// The bench's "the row is still gliding" (it cannot fling a real scroll view).
    private var benchGliding = false

    /// Recorded touches in this view's coordinates, through the same tap / slide / hold judgement as real ones; the
    /// hold is checked against the samples' clock. `gliding`: the row was still moving as the finger landed.
    func touchForTests(_ samples: [TouchSample], gliding: Bool = false) {
        benchTouches = true
        benchGliding = gliding
        defer { benchGliding = false }
        for s in samples {
            if gesture.down { holdDue(at: s.time) }
            stripTouch(s.phase, at: s.point, time: s.time)
            layoutIfNeeded()
        }
    }

    /// A tap (finger down and up again within 0.1 s, not moving) at a point of this view.
    func tapForTests(at p: CGPoint, time: CFTimeInterval) {
        touchForTests([TouchSample(id: 0, phase: .began, point: p, time: time),
                       TouchSample(id: 0, phase: .ended, point: p, time: time + 0.1)])
    }

    /// The row scrolls by a finger moving `dx` (negative: to the left, showing later candidates), through the same
    /// entry the system's scrolling uses.
    func stripPanForTests(dx: CGFloat) {
        stripScrollBegan()
        let maxX = max(0, strip.contentSize.width - strip.bounds.width)
        strip.setContentOffset(CGPoint(x: min(maxX, max(0, strip.contentOffset.x - dx)), y: 0), animated: false)
        layoutIfNeeded()
    }

    /// Snapshot support: the row scrolled to `x`.
    func scrollStrip(to x: CGFloat) {
        layoutIfNeeded()
        for _ in 0..<8 {
            let maxX = max(0, strip.contentSize.width - strip.bounds.width)
            strip.setContentOffset(CGPoint(x: min(maxX, max(0, x)), y: 0), animated: false)
            layoutIfNeeded()
            if strip.contentOffset.x >= min(x, maxX) - 0.5 { break }
        }
    }

    var stripOffsetForTests: CGFloat { strip.contentOffset.x }
    /// The scrolling row's viewport, in this view's coordinates.
    var stripFrameForTests: CGRect { stripBox.frame }
    var stripContentWidthForTests: CGFloat { strip.contentSize.width }
    var stripWidthForTests: CGFloat { strip.bounds.width }
    var laidOutForTests: Int { visibleCount }
    var laidOutWidthForTests: CGFloat { widths.prefix(visibleCount).reduce(0, +) }
    var lastLaidTextForTests: String? { visibleCount > 0 ? labels[visibleCount - 1].text ?? labels[visibleCount - 1].attributedText?.string : nil }
    var expandShownForTests: Bool { !expandButton.isHidden }
    /// Where candidate `i` is drawn, in this view's coordinates (nil: not laid out yet).
    func candidateFrameForTests(_ i: Int) -> CGRect? {
        guard i < visibleCount else { return nil }
        return strip.convert(labels[i].frame, to: self)
    }
    /// Lay out a candidate list and return how long it took (ms).
    func timedUpdateForTests(_ list: [Candidate]) -> Double {
        let t0 = CACurrentMediaTime()
        update(preedit: "", candidates: list)
        return (CACurrentMediaTime() - t0) * 1000
    }

    // MARK: - Remove a learned word

    private var forgetButton: UIButton?

    /// A one-tap confirmation over the candidate row: "删除已学词语「…」". Any other touch dismisses it.
    func offerForget(_ text: String, confirm: @escaping () -> Void) {
        dismissForget()
        var cfg = UIButton.Configuration.filled()
        cfg.title = "删除已学词语「\(text)」"
        cfg.baseBackgroundColor = .systemRed
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        let b = UIButton(configuration: cfg, primaryAction: UIAction { [weak self] _ in confirm(); self?.dismissForget() })
        b.sizeToFit()
        b.frame.origin = CGPoint(x: 10, y: (bounds.height - b.bounds.height) / 2)
        addSubview(b)
        forgetButton = b
        forgetTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self, weak b] _ in
            if let b, self?.forgetButton === b { self?.dismissForget() }
        }
    }

    func dismissForget() {
        forgetTimer?.invalidate()
        forgetTimer = nil
        forgetButton?.removeFromSuperview()
        forgetButton = nil
    }
}

/// Full candidate list as a wrapping grid (vertical scroll only).
final class CandidateGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelect: ((Int) -> Void)?
    var onClose: (() -> Void)?
    var onDelete: (() -> Void)?
    var onFilterToggle: (() -> Void)?
    var onLongPress: ((Int) -> Void)?

    private var allCandidates: [Candidate] = []
    private var displayedIndices: [Int] = []
    private var singleCharOnly = false
    private let collection: UICollectionView
    private let dockBar = UIView()
    private let dockHairline = CALayer()
    private let closeButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let singleCharButton = UIButton(type: .system)
    private var deleteTimer: Timer?

    private func updateFilterButtonStyle() {
        let active = singleCharOnly
        singleCharButton.titleLabel?.font = Theme.font(14, .semibold)
        singleCharButton.backgroundColor = active ? Theme.accentKey : Theme.functionKey
        singleCharButton.setTitleColor(active ? Theme.accentText : Theme.functionText, for: .normal)
        singleCharButton.layer.cornerRadius = Metrics.cornerRadius
        singleCharButton.layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
        singleCharButton.layer.shadowColor = (active ? Theme.accentLip : Theme.functionLip).resolvedColor(with: traitCollection).cgColor
        singleCharButton.accessibilityTraits = active ? [.button, .selected] : .button
    }

    private func rebuildDisplayed() {
        if singleCharOnly {
            displayedIndices = allCandidates.indices.filter { allCandidates[$0].text.count == 1 }
        } else {
            displayedIndices = Array(allCandidates.indices)
        }
        let hasSingle = allCandidates.contains(where: { $0.text.count == 1 })
        let hasMulti = allCandidates.contains(where: { $0.text.count > 1 })
        singleCharButton.isHidden = !(hasSingle && hasMulti)
    }

    func themeChanged() {
        dockHairline.backgroundColor = Theme.separator.resolvedColor(with: traitCollection).cgColor
        for b in [closeButton, deleteButton] {
            b.tintColor = Theme.functionText
            b.backgroundColor = Theme.functionKey
            b.layer.cornerRadius = Metrics.cornerRadius
            b.layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
            b.layer.shadowColor = Theme.functionLip.resolvedColor(with: traitCollection).cgColor
        }
        updateFilterButtonStyle()
        collection.reloadData()
        setNeedsLayout()
    }
    final class Cell: UICollectionViewCell {
        let label = UILabel()
        var baseBackground: UIColor = .clear
        var baseBorderColor: UIColor = .clear
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = CandidateBarView.font
            label.textAlignment = .center
            label.textColor = Theme.candidateText
            contentView.addSubview(label)
            contentView.backgroundColor = .clear
            contentView.layer.cornerRadius = 10
            contentView.layer.cornerCurve = .continuous
            contentView.layer.borderWidth = 0.5
            contentView.layer.borderColor = UIColor.clear.cgColor
            isAccessibilityElement = true
            accessibilityTraits = .button
        }
        required init?(coder: NSCoder) { fatalError() }
        override var accessibilityLabel: String? { get { label.text } set { } }
        override func traitCollectionDidChange(_ previous: UITraitCollection?) {
            super.traitCollectionDidChange(previous)
            contentView.layer.borderColor = baseBorderColor.resolvedColor(with: traitCollection).cgColor
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = contentView.bounds.insetBy(dx: 4, dy: 0)
        }
        override var isHighlighted: Bool {
            didSet { contentView.backgroundColor = isHighlighted ? Theme.functionKey : baseBackground }
        }
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = Theme.touchable   // on the system glass, like the keys (never fully clear: see Theme.touchable)
        collection.backgroundColor = .clear
        collection.clipsToBounds = true
        collection.disableAllEdgeEffects()
        collection.alwaysBounceHorizontal = false
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(Cell.self, forCellWithReuseIdentifier: "c")
        addSubview(collection)
        dockHairline.backgroundColor = Theme.separator.resolvedColor(with: traitCollection).cgColor
        dockBar.backgroundColor = .clear
        dockBar.layer.addSublayer(dockHairline)
        addSubview(dockBar)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        closeButton.setImage(UIImage(systemName: "chevron.up", withConfiguration: cfg), for: .normal)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
        singleCharButton.setTitle("单字", for: .normal)
        for b in [closeButton, deleteButton, singleCharButton] {
            b.tintColor = Theme.functionText
            b.backgroundColor = Theme.functionKey
            b.layer.cornerRadius = Metrics.cornerRadius
            b.layer.cornerCurve = .continuous
            // Match keycap milled lip without offscreen rasterization (explicit shadowPath set in layoutSubviews).
            b.layer.shadowOpacity = 1
            b.layer.shadowRadius = 0
            b.layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
            b.layer.shadowColor = Theme.functionLip.resolvedColor(with: traitCollection).cgColor
            addSubview(b)
        }
        updateFilterButtonStyle()
        singleCharButton.isHidden = true
        closeButton.accessibilityLabel = "收起候选"
        deleteButton.accessibilityLabel = "删除"
        singleCharButton.accessibilityLabel = "只看单字"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        for ev: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            deleteButton.addTarget(self, action: #selector(deleteUp), for: ev)
        }
        singleCharButton.addTarget(self, action: #selector(toggleSingleChar), for: .touchUpInside)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = StripGesture.holdTime
        collection.addGestureRecognizer(lp)
    }

    override var isHidden: Bool { didSet { if isHidden { deleteUp() } } }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { deleteUp() }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        dockHairline.backgroundColor = Theme.separator.resolvedColor(with: traitCollection).cgColor
        for b in [closeButton, deleteButton] { b.layer.shadowColor = Theme.functionLip.resolvedColor(with: traitCollection).cgColor }
        updateFilterButtonStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func closeTapped() { onClose?() }
    @objc private func deleteDown() {
        onDelete?()
        deleteTimer?.invalidate()
        let t = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            let r = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in self?.onDelete?() }
            RunLoop.main.add(r, forMode: .common)
            self?.deleteTimer = r
        }
        RunLoop.main.add(t, forMode: .common)
        deleteTimer = t
    }
    @objc private func deleteUp() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }
    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let p = g.location(in: collection)
        guard let ip = collection.indexPathForItem(at: p), ip.item < displayedIndices.count else { return }
        onLongPress?(displayedIndices[ip.item])
    }
    @objc private func toggleSingleChar() {
        singleCharOnly.toggle()
        rebuildDisplayed()
        updateFilterButtonStyle()
        onFilterToggle?()
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    func show(_ candidates: [Candidate], preserveFilter: Bool = false) {
        allCandidates = candidates
        if !preserveFilter || !candidates.contains(where: { $0.text.count == 1 }) {
            singleCharOnly = false
        }
        rebuildDisplayed()
        updateFilterButtonStyle()
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 56; closeButton.isHidden = true; closeButton.frame = .zero
        let dockH: CGFloat = 52
        collection.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - dockH))
        collection.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)
        dockBar.frame = CGRect(x: 0, y: bounds.height - dockH, width: bounds.width, height: dockH)
        dockHairline.frame = CGRect(x: 10, y: 0, width: max(0, bounds.width - 20), height: 1 / UIScreen.main.scale)
        let bh: CGFloat = 40
        let by = bounds.height - bh - 6
        singleCharButton.frame = CGRect(x: 8, y: by, width: 64, height: bh)
        singleCharButton.layer.shadowPath = UIBezierPath(roundedRect: singleCharButton.bounds, cornerRadius: Metrics.cornerRadius).cgPath
        bringSubviewToFront(singleCharButton)
        deleteButton.frame = CGRect(x: bounds.width - side + 4, y: by, width: side - 10, height: bh)
        deleteButton.layer.shadowPath = UIBezierPath(roundedRect: deleteButton.bounds, cornerRadius: Metrics.cornerRadius).cgPath
        bringSubviewToFront(deleteButton)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { displayedIndices.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "c", for: indexPath) as! Cell
        let realIndex = displayedIndices[indexPath.item]
        let c = allCandidates[realIndex]
        let isFirst = realIndex == 0
        let bg: UIColor = isFirst ? (c.corrected ? Theme.correctedTint : Theme.firstCandidateTint) : .clear
        let border: UIColor = isFirst ? Theme.preeditPillBorder : .clear
        cell.label.text = c.text
        cell.label.font = isFirst ? CandidateBarView.firstFont : CandidateBarView.font
        cell.label.textColor = isFirst && c.corrected ? Theme.correctedMark : Theme.candidateText
        cell.baseBackground = bg
        cell.baseBorderColor = border
        cell.contentView.backgroundColor = bg
        cell.contentView.layer.borderColor = border.resolvedColor(with: traitCollection).cgColor
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout l: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let maxW = collectionView.bounds.width - 16
        let realIndex = displayedIndices[indexPath.item]
        let f = realIndex == 0 ? CandidateBarView.firstFont : CandidateBarView.font
        let w = ceil((allCandidates[realIndex].text as NSString).size(withAttributes: [.font: f]).width) + 18
        return CGSize(width: min(maxW, max(42, w)), height: 40)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(displayedIndices[indexPath.item])
    }

    var displayedCountForTests: Int { displayedIndices.count }
    var singleCharButtonHiddenForTests: Bool { singleCharButton.isHidden }
    func toggleSingleCharForTests() { toggleSingleChar() }
    func selectDisplayedForTests(_ i: Int) { if i < displayedIndices.count { onSelect?(displayedIndices[i]) } }
    func longPressDisplayedForTests(_ i: Int) { if i < displayedIndices.count { onLongPress?(displayedIndices[i]) } }
    func deleteTapForTests() { onDelete?() }
}

/// R50/R52 single-layer OTTOSSOM physical toggle tile with a 4.5pt hardware micro-LED and grounded shadowPath.
private final class HardwareTileButton: UIControl {
    private let eyebrowLabel = UILabel()
    private let valueLabel = UILabel()
    private let ledDot = CALayer()
    private var activeTint: Bool = false
    private var locked: Bool = false
    private var lastShadowSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
        layer.shadowOpacity = 1

        eyebrowLabel.font = Theme.font(10.5, .medium)
        eyebrowLabel.isUserInteractionEnabled = false
        addSubview(eyebrowLabel)

        valueLabel.font = Theme.font(14.5, .semibold)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.72
        valueLabel.isUserInteractionEnabled = false
        addSubview(valueLabel)

        ledDot.cornerRadius = 2.25
        layer.addSublayer(ledDot)

        isAccessibilityElement = true
        accessibilityTraits = .button
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(eyebrow: String, value: String, active: Bool, locked: Bool = false) {
        eyebrowLabel.text = eyebrow
        valueLabel.text = value
        self.activeTint = active
        self.locked = locked
        accessibilityLabel = "\(eyebrow)：\(value)"
        refreshAppearance()
    }

    func refreshAppearance() {
        let t = traitCollection
        let pressed = isHighlighted && !locked
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = (pressed ? Theme.keyPressed : Theme.key).resolvedColor(with: t).cgColor
        layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        layer.shadowColor = Theme.keyLip.resolvedColor(with: t).cgColor
        layer.shadowOpacity = pressed ? 0 : 1
        let ledColor: UIColor = locked
            ? Theme.statusLedMuted.withAlphaComponent(0.35)
            : (activeTint ? Theme.statusLedActive : Theme.statusLedMuted)
        ledDot.backgroundColor = ledColor.resolvedColor(with: t).cgColor
        CATransaction.commit()
        eyebrowLabel.textColor = Theme.secondaryText
        eyebrowLabel.font = Theme.font(10.5, .medium)
        valueLabel.textColor = locked ? Theme.secondaryText : Theme.keyText
        valueLabel.font = Theme.font(14.5, .semibold)
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { refreshAppearance() } }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refreshAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }
        if b.size != lastShadowSize {
            lastShadowSize = b.size
            layer.shadowPath = UIBezierPath(roundedRect: b, cornerRadius: Metrics.cornerRadius).cgPath
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ledDot.frame = CGRect(x: b.width - 13, y: 8.5, width: 4.5, height: 4.5)
        CATransaction.commit()
        let compact = b.height < 52
        let padX: CGFloat = 10
        let topPad: CGFloat = compact ? 6 : 9
        eyebrowLabel.frame = CGRect(x: padX, y: topPad, width: max(0, b.width - padX - 18), height: 14)
        valueLabel.frame = CGRect(x: padX, y: eyebrowLabel.frame.maxY + (compact ? 1 : 3), width: max(0, b.width - padX * 2), height: max(18, b.height - eyebrowLabel.frame.maxY - 8))
    }
}

/// OTTOSSOM zero-scroll hardware control deck (2x3 tactile tiles + contextual Xiaohe guide pill) with a clean
/// secondary drawer (`更多偏好`) for low-frequency toggles, learned lexicon stats & diagnostics.
final class SettingsPanelView: UIView {
    var onClose: (() -> Void)?
    var onChange: (() -> Void)?
    var onResetLearning: (() -> Void)?

    private let header = UIView()
    private let headerHairline = CALayer()
    private let statusLabel = UILabel()
    private let titleLabel = UILabel()
    private let mostoImage = UIImageView()
    private let doneButton = UIButton(type: .system)

    // Primary zero-scroll deck
    private let deckContainer = UIView()
    private let schemeTile = HardwareTileButton()
    private let layoutTile = HardwareTileButton()
    private let lightTile = HardwareTileButton()
    private let hapticTile = HardwareTileButton()
    private let soundTile = HardwareTileButton()
    private let correctTile = HardwareTileButton()
    private var hardwareTiles: [HardwareTileButton] { [schemeTile, layoutTile, lightTile, hapticTile, soundTile, correctTile] }

    private let accessBanner = UILabel()
    private let utilityRow = UIView()
    private let guidePill = UIButton(type: .custom)
    private let guideLed = CALayer()
    private let offlineStatusLabel = UILabel()
    private let moreButton = UIButton(type: .system)

    // Secondary low-frequency preferences drawer
    private let moreScroll = UIScrollView()
    private let backDeckButton = UIButton(type: .system)
    private let stack = UIStackView()

    private let numberControl = UISegmentedControl(items: ["完整页", "九宫格"])
    private let englishSwitch = UISwitch()
    private let appearance = UISegmentedControl(items: ["自动", "日光", "夜灯"])
    private let styleControl = UISegmentedControl(items: ["Mosto", "简洁"])
    private let learnedLabel = UILabel()
    private let diagLabel = UILabel()
    private let note = UILabel()
    private var groups: [UIView] = []
    private var feedbackAvailable = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.touchable
        tintColor = Theme.selection
        for sw in [englishSwitch] { sw.onTintColor = Theme.selection }
        numberControl.translatesAutoresizingMaskIntoConstraints = false
        numberControl.widthAnchor.constraint(equalToConstant: 156).isActive = true
        for i in 0..<numberControl.numberOfSegments { numberControl.setWidth(78, forSegmentAt: i) }
        for sc in [numberControl, appearance, styleControl] {
            sc.selectedSegmentTintColor = Theme.selection
            sc.setTitleTextAttributes([.foregroundColor: Theme.selectionText, .font: Theme.font(13.5, .semibold)], for: .selected)
            sc.setTitleTextAttributes([.foregroundColor: Theme.keyText, .font: Theme.font(13.5, .medium)], for: .normal)
            sc.setContentHuggingPriority(.required, for: .horizontal)
        }

        // Header: Mosto + OTTOSSOM Control Deck title + status + Done pill
        mostoImage.contentMode = .scaleAspectFit
        mostoImage.image = UIImage(named: "mosto_day", in: Bundle(for: SettingsPanelView.self), with: nil)
        titleLabel.text = "Mosto 控制台"
        titleLabel.font = Theme.font(16, .bold)
        titleLabel.textColor = Theme.keyText
        titleLabel.tag = Self.tagPrimary
        statusLabel.font = Theme.font(11.5, .medium)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.tag = Self.tagSecondary
        let titles = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        titles.axis = .vertical
        titles.spacing = 1

        doneButton.setTitle("完成", for: .normal)
        doneButton.titleLabel?.font = Theme.font(14, .bold)
        doneButton.layer.cornerRadius = 14
        doneButton.layer.cornerCurve = .continuous
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        doneButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        doneButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let h = UIStackView(arrangedSubviews: [mostoImage, titles, UIView(), doneButton])
        h.alignment = .center
        h.spacing = 8
        mostoImage.widthAnchor.constraint(equalToConstant: 28).isActive = true
        mostoImage.heightAnchor.constraint(equalToConstant: 28).isActive = true
        header.addSubview(h)
        h.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            h.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            h.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        headerHairline.backgroundColor = Theme.separator.resolvedColor(with: traitCollection).cgColor
        header.layer.addSublayer(headerHairline)
        addSubview(header)

        // Primary 2x3 Hardware Tile Deck
        addSubview(deckContainer)
        schemeTile.addTarget(self, action: #selector(toggleScheme), for: .touchUpInside)
        layoutTile.addTarget(self, action: #selector(toggleLayout), for: .touchUpInside)
        lightTile.addTarget(self, action: #selector(cycleLight), for: .touchUpInside)
        hapticTile.addTarget(self, action: #selector(toggleHaptic), for: .touchUpInside)
        soundTile.addTarget(self, action: #selector(toggleSound), for: .touchUpInside)
        correctTile.addTarget(self, action: #selector(toggleAutocorrect), for: .touchUpInside)
        for t in hardwareTiles { deckContainer.addSubview(t) }

        accessBanner.text = "震动与声效需在 系统设置 › 通用 › 键盘 开启「允许完全访问」"
        accessBanner.font = Theme.font(11.5, .medium)
        accessBanner.textColor = Theme.correctedMark
        accessBanner.textAlignment = .center
        accessBanner.numberOfLines = 1
        accessBanner.adjustsFontSizeToFitWidth = true
        accessBanner.minimumScaleFactor = 0.78
        accessBanner.isHidden = true
        deckContainer.addSubview(accessBanner)

        deckContainer.addSubview(utilityRow)
        guidePill.setTitle("   小鹤键位提示", for: .normal)
        guidePill.titleLabel?.font = Theme.font(12, .semibold)
        guidePill.layer.cornerRadius = 15
        guidePill.layer.cornerCurve = .continuous
        guidePill.layer.borderWidth = 0.5
        guideLed.cornerRadius = 2.25
        guidePill.layer.addSublayer(guideLed)
        guidePill.addTarget(self, action: #selector(toggleGuide), for: .touchUpInside)
        utilityRow.addSubview(guidePill)

        offlineStatusLabel.text = "纯本机离线词库 · 零联网"
        offlineStatusLabel.font = Theme.font(11.5, .medium)
        offlineStatusLabel.textColor = Theme.secondaryText
        utilityRow.addSubview(offlineStatusLabel)

        moreButton.setTitle("更多偏好 · 清空 ›", for: .normal)
        moreButton.titleLabel?.font = Theme.font(12, .semibold)
        moreButton.layer.cornerRadius = 15
        moreButton.layer.cornerCurve = .continuous
        moreButton.addTarget(self, action: #selector(openMore), for: .touchUpInside)
        utilityRow.addSubview(moreButton)

        // Secondary Drawer (`moreScroll`)
        moreScroll.isHidden = true
        moreScroll.alwaysBounceHorizontal = false
        moreScroll.showsHorizontalScrollIndicator = false
        moreScroll.disableAllEdgeEffects()
        addSubview(moreScroll)

        stack.axis = .vertical
        stack.spacing = 6
        moreScroll.addSubview(stack)

        backDeckButton.setTitle("‹ 返回控制台", for: .normal)
        backDeckButton.titleLabel?.font = Theme.font(13.5, .semibold)
        backDeckButton.contentHorizontalAlignment = .leading
        backDeckButton.addTarget(self, action: #selector(closeMore), for: .touchUpInside)
        stack.addArrangedSubview(inset(backDeckButton))
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)

        section("输入细节", rows: [
            row("中英混输", englishSwitch),
            row("123 数字键", numberControl),
        ], footer: "九宫格下小鹤双拼与全拼均可使用；打 ok、ios 直接出 OK、iOS。")

        section("外观微调", rows: [
            row("风格", styleControl),
            row("光线", appearance),
        ], footer: "Mosto 配备软胶单层键帽；简洁复刻系统 Liquid Glass。")

        learnedLabel.font = .systemFont(ofSize: 14)
        learnedLabel.textColor = Theme.secondaryText
        learnedLabel.tag = Self.tagSecondary
        learnedLabel.numberOfLines = 0
        resetButton.setTitle("清空已学习的词语与触点习惯", for: .normal)
        resetButton.setTitleColor(.systemRed, for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 14.5)
        resetButton.contentHorizontalAlignment = .leading
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        section("本机学习词库", rows: [learnedLabel, resetButton], footer: nil)

        diagLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        diagLabel.textColor = Theme.secondaryText
        diagLabel.tag = Self.tagSecondary
        diagLabel.numberOfLines = 0
        if Self.isTestFlight {
            section("测试诊断", rows: [diagLabel], footer: nil)
        }

        note.numberOfLines = 0
        note.font = .systemFont(ofSize: 12)
        note.textColor = Theme.secondaryText
        note.tag = Self.tagSecondary
        stack.addArrangedSubview(inset(note))

        numberControl.addTarget(self, action: #selector(numberChanged), for: .valueChanged)
        for c in [appearance, styleControl] { c.addTarget(self, action: #selector(drawerChanged), for: .valueChanged) }
        englishSwitch.addTarget(self, action: #selector(drawerChanged), for: .valueChanged)

        styleChrome()
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func styleChrome() {
        let t = traitCollection
        tintColor = Theme.selection
        headerHairline.backgroundColor = Theme.separator.resolvedColor(with: t).cgColor
        mostoImage.isHidden = Theme.plain
        doneButton.backgroundColor = Theme.plain ? Theme.selection : Theme.accentKey
        doneButton.setTitleColor(Theme.plain ? Theme.selectionText : Theme.accentText, for: .normal)
        moreButton.backgroundColor = Theme.functionKey
        moreButton.setTitleColor(Theme.functionText, for: .normal)
        backDeckButton.setTitleColor(Theme.selection, for: .normal)
        accessBanner.textColor = Theme.correctedMark
        for sc in [numberControl, appearance, styleControl] {
            sc.selectedSegmentTintColor = Theme.selection
            sc.setTitleTextAttributes([.foregroundColor: Theme.selectionText, .font: Theme.font(13.5, .semibold)], for: .selected)
            sc.setTitleTextAttributes([.foregroundColor: Theme.keyText, .font: Theme.font(13.5, .medium)], for: .normal)
        }
        englishSwitch.onTintColor = Theme.selection
        for tile in hardwareTiles { tile.refreshAppearance() }
        refreshGuidePill()
    }

    private func refreshGuidePill() {
        let s = KeyboardSettings.shared
        let on = s.xiaoheGuide
        let t = traitCollection
        guidePill.isHidden = s.scheme != 0
        offlineStatusLabel.isHidden = !guidePill.isHidden
        guidePill.backgroundColor = (on ? Theme.key : Theme.functionKey)
        guidePill.setTitleColor(on ? Theme.keyText : Theme.functionText, for: .normal)
        guidePill.layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideLed.backgroundColor = (on ? Theme.statusLedActive : Theme.statusLedMuted).resolvedColor(with: t).cgColor
        CATransaction.commit()
    }

    private func inset(_ v: UIView) -> UIView {
        let wrap = UIView()
        wrap.addSubview(v)
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            v.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -16),
            v.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 2),
            v.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -2),
        ])
        return wrap
    }

    private func section(_ title: String, rows: [UIView], footer: String?) {
        let cap = UILabel()
        cap.text = title
        cap.font = .systemFont(ofSize: 12.5)
        cap.textColor = Theme.secondaryText
        cap.tag = Self.tagSecondary
        let capWrap = inset(cap)
        stack.addArrangedSubview(capWrap)
        stack.setCustomSpacing(4, after: capWrap)

        let group = UIView()
        group.backgroundColor = Theme.settingsGroup
        group.tag = Self.tagGroup
        group.layer.cornerRadius = 12
        group.layer.cornerCurve = .continuous
        let inner = UIStackView()
        inner.axis = .vertical
        for (i, r) in rows.enumerated() {
            if i > 0 {
                let line = UIView()
                line.backgroundColor = Theme.separator
                line.tag = Self.tagLine
                line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
                inner.addArrangedSubview(line)
            }
            let cell = UIView()
            cell.addSubview(r)
            r.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                r.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
                r.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                r.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
                r.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -6),
                cell.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            ])
            inner.addArrangedSubview(cell)
        }
        group.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            inner.topAnchor.constraint(equalTo: group.topAnchor),
            inner.bottomAnchor.constraint(equalTo: group.bottomAnchor),
        ])
        let wrap = UIView()
        wrap.addSubview(group)
        group.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            group.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            group.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            group.topAnchor.constraint(equalTo: wrap.topAnchor),
            group.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        stack.addArrangedSubview(wrap)
        groups.append(group)
        if let footer {
            let f = UILabel()
            f.text = footer
            f.numberOfLines = 0
            f.font = .systemFont(ofSize: 11.5)
            f.textColor = Theme.secondaryText
            f.tag = Self.tagSecondary
            stack.setCustomSpacing(4, after: wrap)
            let fw = inset(f)
            stack.addArrangedSubview(fw)
            stack.setCustomSpacing(12, after: fw)
        } else {
            stack.setCustomSpacing(12, after: wrap)
        }
    }

    private func row(_ text: String, _ control: UIView) -> UIView {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 15.5)
        l.textColor = Theme.keyText
        l.tag = Self.tagPrimary
        l.numberOfLines = 0
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        let s = UIStackView(arrangedSubviews: [l, UIView(), control])
        s.alignment = .center
        s.spacing = 10
        return s
    }

    static let isTestFlight: Bool = {
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { return true }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private static let tagPrimary = 9_701, tagSecondary = 9_702, tagGroup = 9_703, tagLine = 9_704

    func themeChanged() {
        styleChrome()
        func walk(_ v: UIView) {
            switch v.tag {
            case Self.tagPrimary: (v as? UILabel)?.textColor = Theme.keyText
            case Self.tagSecondary: (v as? UILabel)?.textColor = Theme.secondaryText
            case Self.tagGroup: v.backgroundColor = Theme.settingsGroup
            case Self.tagLine: v.backgroundColor = Theme.separator
            default: break
            }
            v.subviews.forEach(walk)
        }
        walk(self)
        load()
    }

    func setNight(_ night: Bool) {
        mostoImage.image = UIImage(named: night ? "mosto_night" : "mosto_day", in: Bundle(for: SettingsPanelView.self), with: nil)
        updateStatus(night: night)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        styleChrome()
    }

    private func updateStatus(night: Bool? = nil) {
        let s = KeyboardSettings.shared
        let nightName = s.style == 1 ? "夜光" : "夜灯"
        let light = night.map { $0 ? nightName : "日光" } ?? (["自动", "日光", nightName][s.appearance])
        statusLabel.text = "\(s.style == 1 ? "简洁" : "Mosto") · \(light) · \(s.scheme == 0 ? "小鹤双拼" : "全拼") · \(s.pinyinGrid ? "九宫格" : "全键盘")"
    }

    func load() {
        let s = KeyboardSettings.shared
        updateStatus()

        schemeTile.configure(eyebrow: "输入方案", value: s.scheme == 0 ? "小鹤双拼" : "全拼", active: s.scheme == 0)
        layoutTile.configure(eyebrow: "键盘布局", value: s.pinyinGrid ? "九宫格" : "全键盘", active: s.pinyinGrid)
        let lightTitle: String
        if s.style == 1 {
            lightTitle = "简洁模式"
        } else {
            lightTitle = ["跟随系统", "暖瓷日光", "深曜夜灯"][s.appearance]
        }
        lightTile.configure(eyebrow: "台灯光效", value: lightTitle, active: s.style == 0)

        let prof = HapticProfile(rawValue: s.hapticProfile) ?? .crisp
        hapticTile.configure(
            eyebrow: "按键震动",
            value: feedbackAvailable ? (s.feedback ? prof.deckValue : "已关闭") : "需完全访问",
            active: feedbackAvailable && s.feedback,
            locked: !feedbackAvailable
        )
        soundTile.configure(
            eyebrow: "按键声效",
            value: feedbackAvailable ? (s.keySound ? "原声开启" : "已静音") : "需完全访问",
            active: feedbackAvailable && s.keySound,
            locked: !feedbackAvailable
        )
        correctTile.configure(eyebrow: "触点纠错", value: s.autocorrect ? "智能开启" : "已关闭", active: s.autocorrect)

        numberControl.selectedSegmentIndex = s.numberPad ? 1 : 0
        englishSwitch.isOn = s.english
        appearance.selectedSegmentIndex = s.appearance
        styleControl.selectedSegmentIndex = s.style
        refreshGuidePill()
        setNeedsLayout()
    }

    func setNote(_ text: String) { note.text = text }

    func setFeedbackAvailable(_ ok: Bool) {
        feedbackAvailable = ok
        accessBanner.isHidden = ok
        hapticTile.isEnabled = ok
        soundTile.isEnabled = ok
        load()
    }

    func setLearned(_ text: String) { learnedLabel.text = text }
    func setDiagnostics(_ text: String) { diagLabel.text = text }

    /// Snapshot & compatibility helper: keeps the primary zero-scroll Hardware Deck focused.
    func demoScrollToFeedback() {
        moreScroll.isHidden = true
        deckContainer.isHidden = false
        setNeedsLayout()
    }

    var diagnosticsText: String { diagLabel.text ?? "" }

    // MARK: - Actions & Test Hooks

    private let resetButton = UIButton(type: .system)
    private var resetConfirming = false

    private var canProvideHaptic: Bool { feedbackAvailable && KeyboardSettings.shared.feedback }

    private func notifyTileChange() {
        if canProvideHaptic { UISelectionFeedbackGenerator().selectionChanged() }
        load()
        onChange?()
    }

    @objc private func toggleScheme() {
        let s = KeyboardSettings.shared
        s.scheme = s.scheme == 0 ? 1 : 0
        notifyTileChange()
    }

    @objc private func toggleLayout() {
        let s = KeyboardSettings.shared
        s.pinyinGrid.toggle()
        notifyTileChange()
    }

    @objc private func cycleLight() {
        let s = KeyboardSettings.shared
        if s.style == 1 {
            s.style = 0; s.appearance = 0
        } else if s.appearance == 0 {
            s.appearance = 1
        } else if s.appearance == 1 {
            s.appearance = 2
        } else {
            s.style = 1; s.appearance = 0
        }
        notifyTileChange()
    }

    @objc private func toggleHaptic() {
        guard feedbackAvailable else { return }
        let s = KeyboardSettings.shared
        if !s.feedback {
            s.feedback = true
            s.hapticProfile = 0
        } else if s.hapticProfile < 2 {
            s.hapticProfile += 1
        } else {
            s.feedback = false
            s.hapticProfile = 0
        }
        if s.feedback {
            let prof = HapticProfile(rawValue: s.hapticProfile) ?? .crisp
            let t = SystemFeedbackPlayer.tunedImpact(for: prof, firm: false)
            UIImpactFeedbackGenerator(style: t.style).impactOccurred(intensity: t.intensity)
        }
        load()
        onChange?()
    }

    @objc private func toggleSound() {
        guard feedbackAvailable else { return }
        KeyboardSettings.shared.keySound.toggle()
        notifyTileChange()
    }

    @objc private func toggleAutocorrect() {
        KeyboardSettings.shared.autocorrect.toggle()
        notifyTileChange()
    }

    @objc private func toggleGuide() {
        KeyboardSettings.shared.xiaoheGuide.toggle()
        notifyTileChange()
    }

    @objc private func openMore() {
        if canProvideHaptic { UISelectionFeedbackGenerator().selectionChanged() }
        deckContainer.isHidden = true
        moreScroll.isHidden = false
        moreScroll.setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    @objc private func closeMore() {
        if canProvideHaptic { UISelectionFeedbackGenerator().selectionChanged() }
        moreScroll.isHidden = true
        deckContainer.isHidden = false
        setNeedsLayout()
    }

    @objc private func drawerChanged() {
        if canProvideHaptic { UISelectionFeedbackGenerator().selectionChanged() }
        let s = KeyboardSettings.shared
        s.english = englishSwitch.isOn
        s.appearance = appearance.selectedSegmentIndex
        s.style = styleControl.selectedSegmentIndex
        load()
        onChange?()
    }

    @objc private func numberChanged() {
        if canProvideHaptic { UISelectionFeedbackGenerator().selectionChanged() }
        KeyboardSettings.shared.numberPad = numberControl.selectedSegmentIndex == 1
        onChange?()
    }

    @objc private func closeTapped() {
        if canProvideHaptic { UISelectionFeedbackGenerator().selectionChanged() }
        resetConfirming = false
        resetButton.setTitle("清空已学习的词语与触点习惯", for: .normal)
        moreScroll.isHidden = true
        deckContainer.isHidden = false
        onClose?()
    }

    @objc private func resetTapped() {
        if !resetConfirming {
            resetConfirming = true
            if canProvideHaptic { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            resetButton.setTitle("确认清空？再点一次立即清空", for: .normal)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self, self.resetConfirming else { return }
                self.resetConfirming = false
                self.resetButton.setTitle("清空已学习的词语与触点习惯", for: .normal)
            }
        } else {
            resetConfirming = false
            if canProvideHaptic { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            resetButton.setTitle("清空已学习的词语与触点习惯", for: .normal)
            onResetLearning?()
        }
    }

    var hardwareTileCountForTests: Int { hardwareTiles.count }
    var showingMoreForTests: Bool { !moreScroll.isHidden }
    func toggleMoreForTests() { if moreScroll.isHidden { openMore() } else { closeMore() } }
    func tapSchemeTileForTests() { toggleScheme() }
    func tapHapticTileForTests() { toggleHaptic() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        guard w > 60, h > 60 else { return }
        let headH: CGFloat = h < 205 ? 36 : 42
        header.frame = CGRect(x: 0, y: 0, width: w, height: headH)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headerHairline.frame = CGRect(x: 12, y: headH - 0.5, width: max(0, w - 24), height: 1 / UIScreen.main.scale)
        CATransaction.commit()

        let bodyFrame = CGRect(x: 0, y: headH, width: w, height: max(0, h - headH))
        deckContainer.frame = bodyFrame
        moreScroll.frame = bodyFrame

        // Layout 2x3 Hardware Tile Matrix inside `deckContainer` (0 scroll in portrait & landscape)
        let padX: CGFloat = 10
        let gapX: CGFloat = 8
        let gapY: CGFloat = h < 205 ? 6 : 8
        let bannerH: CGFloat = accessBanner.isHidden ? 0 : 18
        let utilH: CGFloat = 30
        let padTop: CGFloat = h < 205 ? 6 : 10
        let padBot: CGFloat = h < 205 ? 6 : 10
        let availH = bodyFrame.height - padTop - padBot - utilH - bannerH - gapY * (accessBanner.isHidden ? 2 : 3)
        let rowH = max(42, floor(availH / 2))
        let colW = max(40, (w - padX * 2 - gapX * 2) / 3)
        let row1 = [schemeTile, layoutTile, lightTile]
        let row2 = [hapticTile, soundTile, correctTile]
        for (i, tile) in row1.enumerated() {
            tile.frame = CGRect(x: padX + CGFloat(i) * (colW + gapX), y: padTop, width: colW, height: rowH)
        }
        let y2 = padTop + rowH + gapY
        for (i, tile) in row2.enumerated() {
            tile.frame = CGRect(x: padX + CGFloat(i) * (colW + gapX), y: y2, width: colW, height: rowH)
        }
        var nextY = y2 + rowH + gapY
        if !accessBanner.isHidden {
            accessBanner.frame = CGRect(x: padX, y: nextY, width: w - padX * 2, height: bannerH)
            nextY += bannerH + gapY
        }
        utilityRow.frame = CGRect(x: padX, y: min(nextY, bodyFrame.height - utilH - 4), width: w - padX * 2, height: utilH)
        let moreW = min(136, max(108, (utilityRow.bounds.width) * 0.42))
        moreButton.frame = CGRect(x: utilityRow.bounds.width - moreW, y: 0, width: moreW, height: utilH)
        let guideW = min(142, max(96, utilityRow.bounds.width - moreW - 10))
        guidePill.frame = CGRect(x: 0, y: 0, width: guideW, height: utilH)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideLed.frame = CGRect(x: 10, y: (utilH - 4.5) / 2, width: 4.5, height: 4.5)
        CATransaction.commit()
        offlineStatusLabel.frame = CGRect(x: 2, y: 0, width: utilityRow.bounds.width - moreW - 8, height: utilH)

        // Layout secondary `moreScroll`
        let size = stack.systemLayoutSizeFitting(
            CGSize(width: w, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        stack.frame = CGRect(x: 0, y: 6, width: w, height: size.height)
        moreScroll.contentSize = CGSize(width: w, height: size.height + 16)
    }
}

extension Notification.Name {
    static let mostoSettingsDidChange = Notification.Name("app.mossling.keyboard.settingsDidChange")
}

final class KeyboardSettings {
    static let appGroupID = "group.app.mossling.keyboard"
    static let shared = KeyboardSettings()
    private let d: UserDefaults

    /// Every choice is stored the moment it is made and only ever changed by the user: an update never resets it
    /// (the keyboard's defaults live in its own container, which iOS keeps across updates).
    /// When the local App Group container is available, settings are migrated once from standard defaults so the
    /// companion app and keyboard share preferences strictly on-device.
    /// A first install starts in 全拼. Earlier versions started in 小鹤双拼 without storing it: a keyboard that has
    /// been used before (it stored touch habits or any setting) keeps 小鹤双拼, written down now so it stays.
    private init() {
        let standard = UserDefaults.standard
        if let group = UserDefaults(suiteName: Self.appGroupID) {
            if !group.bool(forKey: "migratedToAppGroup") {
                let keys = ["scheme", "autocorrect", "xiaoheGuide", "english", "pinyinGrid", "numberPad", "style", "appearance", "feedback", "hapticProfile", "keySound", "keyOffsets", "offsetX", "offsetY"]
                for k in keys where group.object(forKey: k) == nil {
                    if let v = standard.object(forKey: k) { group.set(v, forKey: k) }
                }
                group.set(true, forKey: "migratedToAppGroup")
            }
            d = group
        } else {
            d = standard
        }
        if d.object(forKey: "scheme") == nil {
            let usedBefore = ["offsetX", "keyOffsets", "appearance", "autocorrect", "english", "pinyinGrid", "feedback", "keySound"]
                .contains { d.object(forKey: $0) != nil }
            d.set(usedBefore ? 0 : 1, forKey: "scheme")
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .mostoSettingsDidChange, object: nil)
    }

    /// 0 小鹤双拼, 1 全拼 (PinyinScheme raw value). First install: 全拼 (see init).
    var scheme: Int {
        get { d.object(forKey: "scheme") as? Int ?? 1 }
        set { d.set(newValue, forKey: "scheme"); notify() }
    }
    var autocorrect: Bool {
        get { d.object(forKey: "autocorrect") as? Bool ?? true }
        set { d.set(newValue, forKey: "autocorrect"); notify() }
    }
    /// 小鹤键位提示 (learning mode): letter keys show the initials and finals they stand for.
    var xiaoheGuide: Bool {
        get { d.object(forKey: "xiaoheGuide") as? Bool ?? false }
        set { d.set(newValue, forKey: "xiaoheGuide"); notify() }
    }
    /// 中英混输: English words offered among the Chinese candidates.
    var english: Bool {
        get { d.object(forKey: "english") as? Bool ?? true }
        set { d.set(newValue, forKey: "english"); notify() }
    }
    /// Chinese typed on the 九宫格 pinyin keypad (on) or the full keyboard (off).
    var pinyinGrid: Bool {
        get { d.object(forKey: "pinyinGrid") as? Bool ?? false }
        set { d.set(newValue, forKey: "pinyinGrid"); notify() }
    }
    /// 123 opens the 九宫格 number pad (on) or the full numbers-and-symbols page (off). Until chosen in settings it
    /// follows the Chinese layout: typing on the 九宫格 means numbers on the keypad too.
    var numberPad: Bool {
        get { d.object(forKey: "numberPad") as? Bool ?? pinyinGrid }
        set { d.set(newValue, forKey: "numberPad"); notify() }
    }
    /// 0 自动 (follows the system's light / dark mode), 1 日光, 2 夜灯. (The old 3 "晚上" reads as 自动.)
    /// 0 Mosto, 1 简洁 (无主题).
    var style: Int {
        get { d.object(forKey: "style") as? Int ?? 0 }
        set { d.set(newValue, forKey: "style"); notify() }
    }
    var appearance: Int {
        get { min(d.object(forKey: "appearance") as? Int ?? 0, 3) % 3 }
        set { d.set(newValue, forKey: "appearance"); notify() }
    }
    /// Haptic tap on key down (the key kept its old name: it used to switch sound and haptics together).
    var feedback: Bool {
        get { d.object(forKey: "feedback") as? Bool ?? true }
        set { d.set(newValue, forKey: "feedback"); notify() }
    }
    /// 0 轻脆 (default), 1 机械, 2 静谧.
    var hapticProfile: Int {
        get { max(0, min(2, d.object(forKey: "hapticProfile") as? Int ?? 0)) }
        set { d.set(max(0, min(2, newValue)), forKey: "hapticProfile"); notify() }
    }
    /// The system keyboard's click sounds on key down (follow the ring / silent switch). Until set on its own it
    /// follows the old combined switch.
    var keySound: Bool {
        get { d.object(forKey: "keySound") as? Bool ?? feedback }
        set { d.set(newValue, forKey: "keySound"); notify() }
    }
    /// Learned per-key touch offsets (SpatialModel.keyOffsetsList).
    var keyOffsets: [String: [Double]] {
        get { d.dictionary(forKey: "keyOffsets") as? [String: [Double]] ?? [:] }
        set { d.set(newValue, forKey: "keyOffsets") }
    }
    var touchOffset: (Double, Double) {
        get { (d.double(forKey: "offsetX"), d.double(forKey: "offsetY")) }
        set { d.set(newValue.0, forKey: "offsetX"); d.set(newValue.1, forKey: "offsetY") }
    }
}

/// 九宫格 拼音选择: while composing on the keypad, the left column lists the syllables the next keys can spell
/// (longest first, then the most common). Tapping one fixes those keys to its letters. Scrolls vertically only.
final class SyllablePickerView: UIView {
    var onPick: ((Int) -> Void)?
    private let scroll = UIScrollView()
    private var buttons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.functionTop
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.5
        layer.borderColor = Theme.functionLip.resolvedColor(with: traitCollection).cgColor
        clipsToBounds = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        scroll.disableAllEdgeEffects()
        addSubview(scroll)
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        layer.borderColor = Theme.functionLip.resolvedColor(with: traitCollection).cgColor
    }

    /// Buttons are kept and relabelled (this runs on every keypad key), never rebuilt.
    func show(_ choices: [String]) {
        while buttons.count < choices.count {
            let b = UIButton(type: .system)
            b.titleLabel?.font = Theme.font(17, .semibold)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.6
            b.tintColor = Theme.keyText
            b.setTitleColor(Theme.keyText, for: .normal)
            b.tag = buttons.count
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            scroll.addSubview(b)
            buttons.append(b)
        }
        for (i, b) in buttons.enumerated() {
            let on = i < choices.count
            b.isHidden = !on
            if on {
                UIView.performWithoutAnimation {
                    b.setTitle(choices[i], for: .normal)
                    b.layoutIfNeeded()
                }
                b.accessibilityLabel = "拼音 \(choices[i])"
            }
        }
        shown = choices.count
        scroll.setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }
    private var shown = 0

    @objc private func tapped(_ b: UIButton) { onPick?(b.tag) }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let h: CGFloat = 40
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: 2, y: CGFloat(i) * h, width: bounds.width - 4, height: h)
        }
        scroll.contentSize = CGSize(width: bounds.width, height: CGFloat(shown) * h)
    }
}
