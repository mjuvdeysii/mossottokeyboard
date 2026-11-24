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
    private let clearArmedPill = UILabel()
    private let deletePreviewPill = UILabel()
    private var clearSwipeProgress: CGFloat = 0
    private var clearSwipeArmed = false
    private var clearSwipeDimContent = true
    private var deleteClutchText: String = ""
    private var deleteClutchCount: Int = 0
    private var cursorScrubActive = false
    private var cursorScrubDelta = 0
    private var cursorScrubEndStop = 0
    private var cursorScrubCrossedNewline = false
    /// What each pooled label shows now (so a label is only redrawn when it changes).
    private struct PoolSlotKey: Equatable {
        let text: String
        let caption: String
        let isFirst: Bool
        let inline: Bool
        let plain: Bool
        let dark: Bool
    }
    private struct PoolVisualKey: Equatable {
        let bgKind: UInt8   // 0=clear, 1=pressed, 2=firstRegular, 3=firstAccent
        let plain: Bool
        let dark: Bool
    }
    private struct WidthKey: Hashable {
        let text: String
        let caption: String
        let isFirst: Bool
        let inline: Bool
    }
    private struct FontMetricsTable {
        let cjk: CGFloat
        let middot: CGFloat
        let ascii: [CGFloat]
    }
    private var poolSlots: [PoolSlotKey?] = []
    private var poolVisuals: [PoolVisualKey?] = []
    private var lastDivPlain = false
    private var lastDivDark = false
    private var cachedDivColorCG: CGColor?
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
    private var widthCache: [WidthKey: CGFloat] = [:]
    private static var fontAttrCache: [Int: [NSAttributedString.Key: Any]] = [:]
    private static var widthTables: [Int: FontMetricsTable] = [:]
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
        clearArmedPill.text = "松手清空"
        clearArmedPill.font = Theme.font(11.5, .semibold)
        clearArmedPill.textAlignment = .center
        clearArmedPill.layer.cornerRadius = 11
        clearArmedPill.layer.cornerCurve = .continuous
        clearArmedPill.layer.borderWidth = 0.5
        clearArmedPill.clipsToBounds = true
        clearArmedPill.isUserInteractionEnabled = false
        clearArmedPill.isHidden = true
        addSubview(clearArmedPill)
        deletePreviewPill.font = Theme.font(11.5, .medium)
        deletePreviewPill.textAlignment = .center
        deletePreviewPill.lineBreakMode = .byTruncatingMiddle
        deletePreviewPill.layer.cornerRadius = 11
        deletePreviewPill.layer.cornerCurve = .continuous
        deletePreviewPill.layer.borderWidth = 0.5
        deletePreviewPill.clipsToBounds = true
        deletePreviewPill.isUserInteractionEnabled = false
        deletePreviewPill.isHidden = true
        addSubview(deletePreviewPill)
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
            if let cancelBtn = forgetCancelButton {
                var c = cancelBtn.configuration
                c?.baseBackgroundColor = Theme.functionKey
                c?.baseForegroundColor = Theme.functionText
                cancelBtn.configuration = c
            }
            layoutClearFilament()
            cachedDivColorCG = divColor
            lastDivDark = traitCollection.userInterfaceStyle == .dark
            poolSlots = poolSlots.map { _ in nil }
            poolVisuals = poolVisuals.map { _ in nil }
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
        if let cancelBtn = forgetCancelButton {
            var c = cancelBtn.configuration
            c?.baseBackgroundColor = Theme.functionKey
            c?.baseForegroundColor = Theme.functionText
            cancelBtn.configuration = c
        }
        layoutClearFilament()
        var uc = undoChip.configuration
        uc?.baseBackgroundColor = Theme.correctedTint
        uc?.baseForegroundColor = Theme.correctedMark
        undoChip.configuration = uc
        let t = undoText, spoken = undoChip.accessibilityLabel
        undoText = nil; setUndo(t, spoken: spoken)
        widthCache.removeAll(keepingCapacity: true)
        cachedDivColorCG = Theme.candidateDivider.resolvedColor(with: traitCollection).cgColor
        lastDivPlain = Theme.plain
        lastDivDark = traitCollection.userInterfaceStyle == .dark
        poolSlots = poolSlots.map { _ in nil }
        poolVisuals = poolVisuals.map { _ in nil }
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

    var isDeleteActionActive: Bool { clearSwipeProgress > 0.005 || clearSwipeArmed }
    var isDeleteClutchEngaged: Bool { clearSwipeArmed && !clearSwipeDimContent }
    var isCursorScrubActive: Bool { cursorScrubActive }
    var isTelemetryOverlayActive: Bool { isDeleteActionActive || cursorScrubActive }

    /// Continuous delete-left swipe or held-delete clutch progress (`0...1`) drives the strip's bottom warm-amber filament
    /// and right/left ceramic HUD pills synchronously.
    func setClearProgress(_ progress: CGFloat, armed: Bool, dimContent: Bool = true,
                          deletedText: String = "", deletedCount: Int = 0) {
        let p = armed ? 1.0 : min(1, max(0, progress))
        clearSwipeProgress = p
        clearSwipeArmed = armed
        clearSwipeDimContent = dimContent
        deleteClutchText = (armed && !dimContent) ? deletedText : ""
        deleteClutchCount = (armed && !dimContent) ? deletedCount : 0
        let a: CGFloat = dimContent ? (armed ? 0.35 : (p > 0.01 ? (1.0 - p * 0.40) : 1.0)) : 1.0
        stripBox.alpha = a
        expandButton.alpha = (armed || cursorScrubActive) ? 0 : a
        preeditDock.alpha = a
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// A swipe left off delete is armed: the candidates fade to show they are about to go (no animation: it follows
    /// the finger).
    func setClearPreview(_ on: Bool) {
        setClearProgress(on ? 1 : 0, armed: on)
    }

    /// Spacebar cursor trackpad telemetry drives the top bar ceramic HUD (left mode tag + right step/boundary readout
    /// plus bottom tracking rail) while hiding idle pills and expand affordances without layout jumps.
    func setCursorTelemetry(active: Bool, delta: Int, endStop: Int, crossedNewline: Bool) {
        let nextDelta = active ? delta : 0
        let nextStop = active ? endStop : 0
        let nextNewline = active ? crossedNewline : false
        if cursorScrubActive == active,
           cursorScrubDelta == nextDelta,
           cursorScrubEndStop == nextStop,
           cursorScrubCrossedNewline == nextNewline {
            return
        }
        cursorScrubActive = active
        cursorScrubDelta = nextDelta
        cursorScrubEndStop = nextStop
        cursorScrubCrossedNewline = nextNewline
        if !clearSwipeArmed && clearSwipeProgress <= 0.01 {
            expandButton.alpha = active ? 0 : 1
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func layoutClearFilament() {
        let clutchEngaged = clearSwipeArmed && !clearSwipeDimContent
        let showClearOrClutch = clearSwipeArmed && forgetOverlay == nil && bounds.width > 120
        let showCursorHud = !showClearOrClutch && cursorScrubActive && forgetOverlay == nil && bounds.width > 120
        let showCue = showClearOrClutch || showCursorHud
        clearArmedPill.isHidden = !showCue
        if showCue {
            let cueText: String
            let pillFont: UIFont
            let pillW: CGFloat
            if showClearOrClutch {
                if clutchEngaged {
                    cueText = deleteClutchCount > 0 ? "逐词删 · \(deleteClutchCount)字" : "逐词删"
                    pillFont = UIFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
                } else {
                    cueText = "松手清空"
                    pillFont = Theme.font(11.5, .semibold)
                }
                clearArmedPill.text = cueText
                clearArmedPill.font = pillFont
                let textW = ceil((cueText as NSString).size(withAttributes: [.font: pillFont]).width)
                pillW = clutchEngaged ? min(116, max(58, textW + 18)) : 66
            } else {
                if cursorScrubEndStop < 0 {
                    cueText = "已到文首"
                } else if cursorScrubEndStop > 0 {
                    cueText = "已到文末"
                } else if cursorScrubDelta < 0 {
                    cueText = "左移 \(-cursorScrubDelta) 字"
                } else if cursorScrubDelta > 0 {
                    cueText = "右移 \(cursorScrubDelta) 字"
                } else {
                    cueText = "滑移定位"
                }
                pillFont = UIFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
                clearArmedPill.text = cueText
                clearArmedPill.font = pillFont
                let textW = ceil((cueText as NSString).size(withAttributes: [.font: pillFont]).width)
                pillW = min(116, max(62, textW + 18))
            }
            let pillH = min(22, max(18, bounds.height - 16))
            clearArmedPill.frame = CGRect(
                x: bounds.width - 10 - pillW,
                y: floor((bounds.height - 2.5 - pillH) / 2),
                width: pillW,
                height: pillH
            )
            clearArmedPill.layer.cornerRadius = pillH / 2
            let useAmberHighlight = showClearOrClutch || cursorScrubEndStop != 0
            if Theme.plain {
                clearArmedPill.backgroundColor = useAmberHighlight
                    ? Theme.dyn(
                        UIColor(red: 0.94, green: 0.90, blue: 0.97, alpha: 1),
                        UIColor(red: 0.22, green: 0.18, blue: 0.28, alpha: 1)
                    )
                    : Theme.preeditPillBg
                clearArmedPill.textColor = useAmberHighlight ? Theme.correctedMark : Theme.keyText
                clearArmedPill.layer.borderColor = (useAmberHighlight ? Theme.correctedMark : Theme.preeditPillBorder)
                    .withAlphaComponent(useAmberHighlight ? 0.45 : 1.0)
                    .resolvedColor(with: traitCollection).cgColor
            } else if useAmberHighlight {
                let goldAccent = Theme.dyn(Theme.gold, Theme.goldGlow)
                clearArmedPill.backgroundColor = Theme.dyn(
                    UIColor(red: 0.96, green: 0.91, blue: 0.78, alpha: 1),
                    UIColor(red: 0.28, green: 0.22, blue: 0.13, alpha: 1)
                )
                clearArmedPill.textColor = Theme.dyn(
                    UIColor(red: 0.45, green: 0.28, blue: 0.04, alpha: 1),
                    Theme.goldGlow
                )
                clearArmedPill.layer.borderColor = goldAccent.withAlphaComponent(0.55).resolvedColor(with: traitCollection).cgColor
            } else {
                clearArmedPill.backgroundColor = Theme.dyn(
                    UIColor(red: 0.92, green: 0.95, blue: 0.91, alpha: 1),
                    UIColor(red: 0.16, green: 0.21, blue: 0.17, alpha: 1)
                )
                clearArmedPill.textColor = Theme.keyText
                clearArmedPill.layer.borderColor = Theme.statusLedActive.withAlphaComponent(0.55).resolvedColor(with: traitCollection).cgColor
            }
            bringSubviewToFront(clearArmedPill)
        }

        let maxPreviewW = showCue ? (clearArmedPill.frame.minX - 18) : 0
        let showPreview = showCue && (clutchEngaged || showCursorHud) && maxPreviewW >= 68
        deletePreviewPill.isHidden = !showPreview
        if showPreview {
            let previewFont = Theme.font(11.5, .medium)
            let previewString: String
            if showClearOrClutch {
                if !deleteClutchText.isEmpty {
                    let snippet = Self.abbreviated(deleteClutchText, to: 10)
                    previewString = maxPreviewW >= 172 ? "已删「\(snippet)」· 松手撤回" : "已删「\(snippet)」"
                } else {
                    previewString = "已进入逐词快删"
                }
            } else {
                if cursorScrubCrossedNewline {
                    previewString = maxPreviewW >= 120 ? "游标微调 · 换行" : "游标 · 换行"
                } else {
                    previewString = "游标微调"
                }
            }
            deletePreviewPill.text = previewString
            deletePreviewPill.font = previewFont
            let textW = ceil((previewString as NSString).size(withAttributes: [.font: previewFont]).width)
            let pillW = min(maxPreviewW, max(68, textW + 18))
            let pillH = min(22, max(18, bounds.height - 16))
            deletePreviewPill.frame = CGRect(
                x: 10,
                y: floor((bounds.height - 2.5 - pillH) / 2),
                width: pillW,
                height: pillH
            )
            deletePreviewPill.layer.cornerRadius = pillH / 2
            deletePreviewPill.backgroundColor = Theme.preeditPillBg
            deletePreviewPill.textColor = showCursorHud ? Theme.secondaryText : Theme.keyText
            deletePreviewPill.layer.borderColor = Theme.preeditPillBorder.resolvedColor(with: traitCollection).cgColor
            bringSubviewToFront(deletePreviewPill)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if clearSwipeProgress > 0.005, bounds.width > 20 {
            clearFilament.isHidden = false
            let span = max(0, bounds.width - 20)
            let w = span * clearSwipeProgress
            let h: CGFloat = clearSwipeArmed ? 2.5 : 2.0
            clearFilament.frame = CGRect(x: bounds.width - 10 - w, y: bounds.height - h, width: w, height: h)
            let baseColor = Theme.plain ? Theme.correctedMark : Theme.dyn(Theme.gold, Theme.goldGlow)
            clearFilament.backgroundColor = baseColor.resolvedColor(with: traitCollection)
                .withAlphaComponent(clearSwipeArmed ? 1.0 : (0.55 + 0.45 * clearSwipeProgress)).cgColor
        } else if showCursorHud, bounds.width > 40 {
            clearFilament.isHidden = false
            let span = max(0, bounds.width - 20)
            let indW = min(44, max(24, span * 0.14))
            let indX: CGFloat
            if cursorScrubEndStop < 0 {
                indX = 10
            } else if cursorScrubEndStop > 0 {
                indX = bounds.width - 10 - indW
            } else {
                let ratio = max(-1.0, min(1.0, CGFloat(cursorScrubDelta) / 14.0))
                indX = bounds.width / 2 + ratio * ((span - indW) / 2) - indW / 2
            }
            let h: CGFloat = 2.0
            clearFilament.frame = CGRect(x: indX, y: bounds.height - h, width: indW, height: h)
            let clamped = cursorScrubEndStop != 0
            let railColor: UIColor = clamped
                ? (Theme.plain ? Theme.correctedMark : Theme.dyn(Theme.gold, Theme.goldGlow))
                : Theme.statusLedActive
            clearFilament.backgroundColor = railColor.resolvedColor(with: traitCollection)
                .withAlphaComponent(clamped ? 0.95 : 0.85).cgColor
        } else {
            clearFilament.isHidden = true
        }
        CATransaction.commit()
    }

    private static func abbreviated(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        return String(s.prefix(limit / 2)) + "…" + String(s.suffix(limit - limit / 2 - 1))
    }

    var clearPreviewForTests: Bool { stripBox.alpha < 1 }
    var clearFilamentProgressForTests: CGFloat { clearSwipeProgress }
    var clearArmedCueShownForTests: Bool { clearSwipeArmed && clearSwipeDimContent && !clearArmedPill.isHidden }
    var deleteClutchCueShownForTests: Bool { clearSwipeArmed && !clearSwipeDimContent && !clearArmedPill.isHidden }
    var cursorTelemetryShownForTests: Bool { cursorScrubActive && !clearArmedPill.isHidden }
    var cursorTelemetryBoundaryForTests: Bool { cursorScrubActive && cursorScrubEndStop != 0 }
    var cursorTelemetryTextForTests: String? { (cursorScrubActive && !clearArmedPill.isHidden) ? clearArmedPill.text : nil }
    var clearArmedCueTextForTests: String? { clearArmedPill.isHidden ? nil : clearArmedPill.text }
    var clearArmedPillFrameForTests: CGRect { clearArmedPill.frame }
    var deletePreviewShownForTests: Bool { !deletePreviewPill.isHidden }
    var deletePreviewTextForTests: String? { deletePreviewPill.isHidden ? nil : deletePreviewPill.text }
    var deletePreviewPillFrameForTests: CGRect { deletePreviewPill.frame }
    var cursorModePillTextForTests: String? { (cursorScrubActive && !deletePreviewPill.isHidden) ? deletePreviewPill.text : nil }
    var stripVisibleForTests: Bool { !stripBox.isHidden }
    var clearArmedOpaqueForTests: Bool { (clearArmedPill.backgroundColor?.cgColor.alpha ?? 0) >= 0.99 }

    // MARK: VoiceOver: each laid-out candidate is a button (the strip draws plain labels and reads raw touches)

    private final class CandidateElement: UIAccessibilityElement {
        var activate: (() -> Void)?
        override func accessibilityActivate() -> Bool { activate?(); return true }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = super.hitTest(point, with: event), hit !== self { return hit }
        if !preeditDock.isHidden && !preeditRaw.isEmpty && preeditDock.frame.width > 0 {
            let expanded = CGRect(x: preeditDock.frame.minX, y: 0, width: preeditDock.frame.width, height: bounds.height)
            if expanded.contains(point) { return preeditDock }
        }
        return super.hitTest(point, with: event)
    }

    override var accessibilityElements: [Any]? {
        get {
            if forgetOverlay != nil {
                return [forgetConfirmButton, forgetCancelButton].compactMap { $0 }
            }
            if isDeleteClutchEngaged || cursorScrubActive {
                return [deletePreviewPill, clearArmedPill].filter { !$0.isHidden }
            }
            var out: [Any] = []
            let visibleIdle = idleAccessibilityViews.filter { !$0.isHidden }
            if !visibleIdle.isEmpty {
                out.append(contentsOf: visibleIdle)
            } else if !mosto.isHidden {
                out.append(mosto)
            }
            if !undoChip.isHidden { out.append(undoChip) }
            if !preeditDock.isHidden && !preeditRaw.isEmpty { out.append(preeditDock) }
            for (i, l) in labels.enumerated() where !l.isHidden {
                let e = CandidateElement(accessibilityContainer: self)
                e.accessibilityLabel = i < candidates.count ? candidates[i].text : l.text
                if i < candidates.count, !isPrediction, let cap = Self.caption(for: candidates[i]) {
                    e.accessibilityValue = cap.string == "已纠错" ? "已纠错"
                        : "已纠错：" + candidates[i].fixes.map { "\($0.typed) 改为 \($0.meant)" }.joined(separator: "，")
                } else if isMathResult {
                    e.accessibilityValue = "心算结果"
                    e.accessibilityHint = "轻点或按空格插入"
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

    private var preeditDockWanted: Bool {
        !preeditRaw.isEmpty && !isPrediction && (showsPreedit || gridExpanded)
    }

    /// Immediately show typed keys in the leading single-row live keystroke dock (0 ms, 0 XPC).
    func setPreedit(_ text: String) {
        let changed = preeditRaw != text || !activeFixes.isEmpty
        if changed { applyPreeditText(text, fixes: []) }
        let show = preeditDockWanted
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
        if !busy && forgetOverlay != nil { dismissForget() }
        setMosto(!busy && !typing && showsMosto && undoText == nil)
        preeditDock.isHidden = !preeditDockWanted
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
        if let overlay = forgetOverlay {
            overlay.frame = bounds
            stripBox.isHidden = true
            preeditDock.isHidden = true
            expandButton.isHidden = true
            undoChip.isHidden = true
            mosto.isHidden = true
            clearArmedPill.isHidden = true
            deletePreviewPill.isHidden = true
            let pillH = min(30, max(24, h - 10))
            let y = floor((h - pillH) / 2)
            if let cancelBtn = forgetCancelButton {
                let cFit = cancelBtn.sizeThatFits(CGSize(width: 100, height: pillH))
                let cancelW = min(68, max(52, ceil(cFit.width)))
                cancelBtn.frame = CGRect(x: max(10, bounds.width - 10 - cancelW), y: y, width: cancelW, height: pillH)
                if let confirmBtn = forgetConfirmButton {
                    let maxConfirmW = max(80, cancelBtn.frame.minX - 18)
                    let mFit = confirmBtn.sizeThatFits(CGSize(width: maxConfirmW, height: pillH))
                    let confirmW = min(maxConfirmW, ceil(mFit.width))
                    confirmBtn.frame = CGRect(x: 10, y: y, width: confirmW, height: pillH)
                }
            }
            bringSubviewToFront(overlay)
            layoutClearFilament()
            return
        }
        let hideChromeForHud = isDeleteClutchEngaged || cursorScrubActive
        undoChip.isHidden = undoText == nil || hideChromeForHud
        preeditDock.isHidden = !preeditDockWanted || !undoChip.isHidden || hideChromeForHud
        mosto.isHidden = !mostoWanted || hideChromeForHud
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
        } else if !preeditDock.isHidden, !preeditRaw.isEmpty {
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
        layoutClearFilament()
        let rightLimit = clearArmedPill.isHidden ? (bounds.width - expandW) : min(bounds.width - expandW, clearArmedPill.frame.minX - 6)
        // Keep stripBox and CandidateStrip spanning the FULL bar height (0..h) so taps on the upper third never miss.
        let box = CGRect(x: lead, y: 0, width: max(0, rightLimit - lead), height: h)
        if stripBox.frame != box { stripBox.frame = box }
        let inner = CGRect(origin: .zero, size: box.size)
        if strip.frame != inner { strip.frame = inner }
        // nothing to show: the strip takes no touches (or when grid is open and live preedit dock replaces duplicate row-1 strip)
        let hideStripForGridDock = gridExpanded && !preeditDock.isHidden && !preeditRaw.isEmpty
        stripBox.isHidden = (candidates.isEmpty && !typing) || hideStripForGridDock || hideChromeForHud
        layoutCandidates()
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

    private static func attrs(isFirst: Bool) -> [NSAttributedString.Key: Any] {
        let key = (Theme.plain ? 2 : 0) + (isFirst ? 1 : 0)
        if let cached = fontAttrCache[key] { return cached }
        let built: [NSAttributedString.Key: Any] = [.font: isFirst ? firstFont : font]
        fontAttrCache[key] = built
        return built
    }

    private static func fastTextWidth(_ text: String, isFirst: Bool, plain: Bool) -> CGFloat? {
        let tableKey = (plain ? 2 : 0) + (isFirst ? 1 : 0)
        let table: FontMetricsTable
        if let cached = widthTables[tableKey] {
            table = cached
        } else {
            let a = attrs(isFirst: isFirst)
            let cjk = ("汉" as NSString).size(withAttributes: a).width
            let mid = ("·" as NSString).size(withAttributes: a).width
            var ascii = [CGFloat](repeating: 0, count: 95)
            for code in 0x20...0x7E {
                let s = String(UnicodeScalar(code)!) as NSString
                ascii[code - 0x20] = s.size(withAttributes: a).width
            }
            table = FontMetricsTable(cjk: cjk, middot: mid, ascii: ascii)
            widthTables[tableKey] = table
        }
        var sum: CGFloat = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v >= 0x4E00 && v <= 0x9FFF {
                sum += table.cjk
            } else if v >= 0x20 && v <= 0x7E {
                sum += table.ascii[Int(v - 0x20)]
            } else if v == 0x00B7 {
                sum += table.middot
            } else {
                return nil
            }
        }
        return sum
    }

    /// Width of candidate `i` (cached by text, slot-0 weight, and caption): compact 14pt padding for 4-6 visible candidates.
    private func measure(_ i: Int, caption cap: NSAttributedString?, inline: Bool) -> CGFloat {
        let c = candidates[i]
        let isFirst = i == 0 && !isPrediction
        let capStr = cap?.string ?? ""
        let key = WidthKey(text: c.text, caption: capStr, isFirst: isFirst, inline: inline)
        if let w = widthCache[key] { return w }
        let textW = Self.fastTextWidth(c.text, isFirst: isFirst, plain: Theme.plain)
            ?? (c.text as NSString).size(withAttributes: Self.attrs(isFirst: isFirst)).width
        let w: CGFloat
        if let cap {
            let capW = cap.size().width
            w = inline ? max(38, ceil(textW + 4 + capW) + 16) : max(38, ceil(max(textW, capW)) + 16)
        } else {
            w = max(38, ceil(textW) + (isFirst ? 16 : 14))
        }
        widthCache[key] = w
        return w
    }

    /// Lay the row out from its start to 1.6 screens past what is shown (the rest only as the finger gets there:
    /// a single syllable can have hundreds of candidates). Labels & dividers are pooled and reused.
    private func layoutCandidates() {
        let viewW = strip.bounds.width
        let rowH = strip.bounds.height
        let topY: CGFloat = 4
        let labelH: CGFloat = max(18, rowH - 8)
        let inline = bounds.height < Self.twoLineHeight
        let need = strip.contentOffset.x + max(viewW, 1) * 1.6
        let pressed = gesture.highlighted
        let plain = Theme.plain
        let dark = traitCollection.userInterfaceStyle == .dark
        let refreshDivColor = cachedDivColorCG == nil || plain != lastDivPlain || dark != lastDivDark
        let divColor: CGColor
        if refreshDivColor {
            divColor = Theme.candidateDivider.resolvedColor(with: traitCollection).cgColor
            cachedDivColorCG = divColor
            lastDivPlain = plain
            lastDivDark = dark
        } else {
            divColor = cachedDivColorCG!
        }
        let divH: CGFloat = min(15, max(10, labelH * 0.45))
        let divY: CGFloat = (rowH - divH) / 2
        var x: CGFloat = 0
        var n = 0
        var showCorrectionBar = false
        var correctionFrame = CGRect.zero
        CATransaction.begin(); CATransaction.setDisableActions(true)
        while n < candidates.count && (x < need || n == 0) {
            let cap = captionFor(n)
            let w: CGFloat
            if n < widths.count { w = widths[n] } else { w = measure(n, caption: cap, inline: inline); widths.append(w) }
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
                poolSlots.append(nil)
                poolVisuals.append(nil)
            }
            let l = pool[n]
            if l.isHidden { l.isHidden = false }
            let frame = CGRect(x: x, y: topY, width: w, height: labelH)
            if l.frame != frame { l.frame = frame }
            let c = candidates[n]
            let isFirst = n == 0 && !isPrediction
            let slotKey = PoolSlotKey(text: c.text, caption: cap?.string ?? "", isFirst: isFirst, inline: inline, plain: plain, dark: dark)
            if poolSlots[n] != slotKey {
                poolSlots[n] = slotKey
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
            let isFirstAccent = isFirst && (c.corrected || isMathResult)
            let bgKind: UInt8 = n == pressed ? 1 : (isFirstAccent ? 3 : ((isFirst || (isMathResult && n == 0)) ? 2 : 0))
            let visKey = PoolVisualKey(bgKind: bgKind, plain: plain, dark: dark)
            if poolVisuals[n] != visKey {
                poolVisuals[n] = visKey
                switch bgKind {
                case 1: l.backgroundColor = Theme.functionKey
                case 3: l.backgroundColor = Theme.correctedTint
                case 2: l.backgroundColor = Theme.firstCandidateTint
                default: l.backgroundColor = .clear
                }
            }
            if isFirst && c.corrected {
                let barW: CGFloat = min(14, max(8, w - 16))
                showCorrectionBar = true
                correctionFrame = CGRect(x: x + (w - barW) / 2, y: topY + labelH - 3, width: barW, height: 2)
            }
            if n > 0 {
                let di = n - 1
                let d: CALayer
                var divCreated = false
                if dividerPool.count <= di {
                    let layer = CALayer()
                    layer.backgroundColor = divColor
                    strip.layer.addSublayer(layer)
                    dividerPool.append(layer)
                    d = layer
                    divCreated = true
                } else {
                    d = dividerPool[di]
                }
                let hideDiv = (n == 1 && !isPrediction) || n == pressed || (n - 1) == pressed
                if d.isHidden != hideDiv { d.isHidden = hideDiv }
                if !hideDiv {
                    if refreshDivColor && !divCreated { d.backgroundColor = divColor }
                    let dFrame = CGRect(x: x - 0.25, y: divY, width: 0.5, height: divH)
                    if d.frame != dFrame { d.frame = dFrame }
                }
            }
            x += w
            n += 1
        }
        let usedDivs = max(0, n - 1)
        if dividerPool.count > usedDivs {
            for d in dividerPool.dropFirst(usedDivs) where !d.isHidden { d.isHidden = true }
        }
        if correctionBar.isHidden != !showCorrectionBar { correctionBar.isHidden = !showCorrectionBar }
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
        let hideExpand = isDeleteClutchEngaged || cursorScrubActive || !((total > viewW + 0.5 && !isPrediction) || gridExpanded || idleGear)
        if expandButton.isHidden != hideExpand { expandButton.isHidden = hideExpand }
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

    private var forgetOverlay: UIView?
    private var forgetConfirmButton: UIButton?
    private var forgetCancelButton: UIButton?

    var forgetOverlayActiveForTests: Bool { forgetOverlay != nil }
    var forgetOverlayHidesStripForTests: Bool { forgetOverlay != nil && stripBox.isHidden && expandButton.isHidden }
    var forgetButtonsNonOverlappingForTests: Bool {
        guard let c = forgetConfirmButton, let x = forgetCancelButton else { return false }
        return !c.frame.intersects(x.frame) && c.frame.minX >= 8 && x.frame.maxX <= bounds.width - 8
    }
    func tapForgetCancelForTests() { dismissForget() }

    /// An exclusive staged confirmation replacing the strip momentarily: "删除「…」" + "取消".
    func offerForget(_ text: String, confirm: @escaping () -> Void) {
        dismissForget()
        let overlay = UIView(frame: bounds)
        overlay.backgroundColor = .clear

        var cfg = UIButton.Configuration.filled()
        cfg.title = "删除「\(text)」"
        cfg.titleLineBreakMode = .byTruncatingMiddle
        cfg.image = UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        cfg.imagePadding = 5
        cfg.baseBackgroundColor = Theme.dyn(
            UIColor(red: 0.84, green: 0.22, blue: 0.24, alpha: 1),
            UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
        )
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 13)
        let confirmBtn = UIButton(configuration: cfg, primaryAction: UIAction { [weak self] _ in
            confirm()
            self?.dismissForget()
        })
        confirmBtn.accessibilityLabel = "确认删除已学词语 \(text)"

        var cancelCfg = UIButton.Configuration.filled()
        cancelCfg.title = "取消"
        cancelCfg.baseBackgroundColor = Theme.functionKey
        cancelCfg.baseForegroundColor = Theme.functionText
        cancelCfg.cornerStyle = .capsule
        cancelCfg.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        let cancelBtn = UIButton(configuration: cancelCfg, primaryAction: UIAction { [weak self] _ in
            self?.dismissForget()
        })
        cancelBtn.accessibilityLabel = "取消删除"

        overlay.addSubview(confirmBtn)
        overlay.addSubview(cancelBtn)
        addSubview(overlay)
        forgetOverlay = overlay
        forgetConfirmButton = confirmBtn
        forgetCancelButton = cancelBtn
        setNeedsLayout()
        layoutIfNeeded()

        forgetTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self, weak overlay] _ in
            if let overlay, self?.forgetOverlay === overlay { self?.dismissForget() }
        }
    }

    func dismissForget() {
        forgetTimer?.invalidate()
        forgetTimer = nil
        forgetOverlay?.removeFromSuperview()
        forgetOverlay = nil
        forgetConfirmButton = nil
        forgetCancelButton = nil
        setNeedsLayout()
    }
}

/// Full candidate list as a wrapping grid (vertical scroll only) with a 3-mode scope rail (`全部 / 词组 / 单字`),
/// live count badge, and smooth bottom overflow fade into the thumb dock.
final class CandidateGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate {
    enum FilterMode: Int, CaseIterable {
        case all = 0
        case phrases = 1
        case singleChar = 2

        var title: String {
            switch self {
            case .all: return "全部"
            case .phrases: return "词组"
            case .singleChar: return "单字"
            }
        }
    }

    var onSelect: ((Int) -> Void)?
    var onClose: (() -> Void)?
    var onDelete: (() -> Void)?
    var onFilterToggle: (() -> Void)?
    var onLongPress: ((Int) -> Void)?

    private var allCandidates: [Candidate] = []
    private var displayedIndices: [Int] = []
    private var filterMode: FilterMode = .all
    private let collectionBox = UIView()
    private let collectionFade = CAGradientLayer()
    private let collection: UICollectionView
    private let dockBar = UIView()
    private let dockHairline = CALayer()
    private let closeButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let filterRail = UIView()
    private var filterButtons: [UIButton] = []
    private let countBadge = UILabel()
    private var deleteTimer: Timer?

    private func updateFilterRailStyle() {
        let t = traitCollection
        filterRail.backgroundColor = Theme.settingsGroup.resolvedColor(with: t)
        filterRail.layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        for (i, b) in filterButtons.enumerated() {
            let active = i == filterMode.rawValue
            b.backgroundColor = (active ? Theme.selection : .clear).resolvedColor(with: t)
            b.setTitleColor((active ? Theme.selectionText : Theme.keyText).resolvedColor(with: t), for: .normal)
            b.titleLabel?.font = Theme.font(12, active ? .bold : .semibold)
            b.accessibilityTraits = active ? [.button, .selected] : .button
        }
        countBadge.backgroundColor = Theme.settingsGroup.resolvedColor(with: t)
        countBadge.layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        countBadge.textColor = Theme.secondaryText.resolvedColor(with: t)
    }

    private func rebuildDisplayed() {
        switch filterMode {
        case .all:
            displayedIndices = Array(allCandidates.indices)
        case .phrases:
            displayedIndices = allCandidates.indices.filter { allCandidates[$0].text.count > 1 }
        case .singleChar:
            displayedIndices = allCandidates.indices.filter { allCandidates[$0].text.count == 1 }
        }
        let hasSingle = allCandidates.contains(where: { $0.text.count == 1 })
        let hasMulti = allCandidates.contains(where: { $0.text.count > 1 })
        filterRail.isHidden = !(hasSingle && hasMulti)

        let total = displayedIndices.count
        switch filterMode {
        case .all:
            countBadge.text = total > 0 ? "\(total)" : ""
        case .phrases:
            countBadge.text = "\(total) 词"
        case .singleChar:
            countBadge.text = "\(total) 字"
        }
        countBadge.isHidden = allCandidates.isEmpty
    }

    private func updateCollectionBottomFade() {
        let h = collectionBox.bounds.height
        let hasMoreBelow = collection.contentSize.height > h + 2
            && (collection.contentOffset.y + h < collection.contentSize.height - 2)
        guard h > 40, hasMoreBelow else {
            if collectionBox.layer.mask != nil { collectionBox.layer.mask = nil }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionFade.frame = collectionBox.bounds
        let frac = Double(min(0.14, 12.0 / h))
        collectionFade.locations = [0, NSNumber(value: 1.0 - frac), 1]
        if collectionBox.layer.mask !== collectionFade { collectionBox.layer.mask = collectionFade }
        CATransaction.commit()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === collection { updateCollectionBottomFade() }
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
        updateFilterRailStyle()
        collection.reloadData()
        setNeedsLayout()
    }
    final class Cell: UICollectionViewCell {
        let label = UILabel()
        let correctionBar = CALayer()
        var baseBackground: UIColor = .clear
        var baseBorderColor: UIColor = .clear
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = CandidateBarView.font
            label.textAlignment = .center
            label.textColor = Theme.candidateText
            contentView.addSubview(label)
            correctionBar.cornerRadius = 1
            correctionBar.isHidden = true
            contentView.layer.addSublayer(correctionBar)
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
            correctionBar.backgroundColor = Theme.correctedMark.resolvedColor(with: traitCollection).cgColor
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = contentView.bounds.insetBy(dx: 4, dy: 0)
            let barW = min(14, max(8, contentView.bounds.width - 18))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            correctionBar.frame = CGRect(x: (contentView.bounds.width - barW) / 2, y: contentView.bounds.height - 4, width: barW, height: 2)
            CATransaction.commit()
        }
        override var isHighlighted: Bool {
            didSet {
                contentView.backgroundColor = isHighlighted ? Theme.functionKey : baseBackground
                if !UIAccessibility.isReduceMotionEnabled {
                    contentView.transform = isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
                }
            }
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
        collectionFade.startPoint = CGPoint(x: 0.5, y: 0)
        collectionFade.endPoint = CGPoint(x: 0.5, y: 1)
        collectionFade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        collectionBox.backgroundColor = .clear
        collectionBox.clipsToBounds = true
        addSubview(collectionBox)

        collection.backgroundColor = .clear
        collection.clipsToBounds = true
        collection.disableAllEdgeEffects()
        collection.alwaysBounceHorizontal = false
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(Cell.self, forCellWithReuseIdentifier: "c")
        collectionBox.addSubview(collection)

        dockHairline.backgroundColor = Theme.separator.resolvedColor(with: traitCollection).cgColor
        dockBar.backgroundColor = .clear
        dockBar.layer.addSublayer(dockHairline)
        addSubview(dockBar)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        closeButton.setImage(UIImage(systemName: "chevron.up", withConfiguration: cfg), for: .normal)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
        for b in [closeButton, deleteButton] {
            b.tintColor = Theme.functionText
            b.backgroundColor = Theme.functionKey
            b.layer.cornerRadius = Metrics.cornerRadius
            b.layer.cornerCurve = .continuous
            // Match keycap milled lip without offscreen rasterization (explicit shadowPath set in layoutSubviews).
            b.layer.shadowOpacity = 1
            b.layer.shadowRadius = 0
            b.layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
            b.layer.shadowColor = Theme.functionLip.resolvedColor(with: traitCollection).cgColor
            dockBar.addSubview(b)
        }

        filterRail.layer.cornerRadius = 15
        filterRail.layer.cornerCurve = .continuous
        filterRail.layer.borderWidth = 0.5
        filterRail.clipsToBounds = true
        for mode in FilterMode.allCases {
            let b = UIButton(type: .custom)
            b.tag = mode.rawValue
            b.setTitle(mode.title, for: .normal)
            b.layer.cornerRadius = 12
            b.layer.cornerCurve = .continuous
            b.accessibilityLabel = "候选筛选：\(mode.title)"
            b.addTarget(self, action: #selector(filterButtonTapped(_:)), for: .touchUpInside)
            filterRail.addSubview(b)
            filterButtons.append(b)
        }
        filterRail.isHidden = true
        dockBar.addSubview(filterRail)

        countBadge.font = Theme.font(11.5, .semibold)
        countBadge.textAlignment = .center
        countBadge.layer.cornerRadius = 11
        countBadge.layer.cornerCurve = .continuous
        countBadge.layer.borderWidth = 0.5
        countBadge.clipsToBounds = true
        countBadge.isAccessibilityElement = false
        countBadge.isHidden = true
        dockBar.addSubview(countBadge)

        updateFilterRailStyle()
        closeButton.accessibilityLabel = "收起候选"
        deleteButton.accessibilityLabel = "删除"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        for ev: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            deleteButton.addTarget(self, action: #selector(deleteUp), for: ev)
        }
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
        updateFilterRailStyle()
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
    @objc private func filterButtonTapped(_ sender: UIButton) {
        setFilterMode(FilterMode(rawValue: sender.tag) ?? .all)
    }
    @objc private func toggleSingleChar() {
        setFilterMode(filterMode == .singleChar ? .all : .singleChar)
    }

    private func setFilterMode(_ next: FilterMode) {
        guard next != filterMode else { return }
        filterMode = next
        rebuildDisplayed()
        updateFilterRailStyle()
        setNeedsLayout()
        onFilterToggle?()
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
        collection.layoutIfNeeded()
        updateCollectionBottomFade()
    }

    func show(_ candidates: [Candidate], preserveFilter: Bool = false) {
        allCandidates = candidates
        if !preserveFilter {
            filterMode = .all
        } else {
            switch filterMode {
            case .all: break
            case .phrases:
                if !candidates.contains(where: { $0.text.count > 1 }) { filterMode = .all }
            case .singleChar:
                if !candidates.contains(where: { $0.text.count == 1 }) { filterMode = .all }
            }
        }
        rebuildDisplayed()
        updateFilterRailStyle()
        setNeedsLayout()
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
        layoutIfNeeded()
        updateCollectionBottomFade()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 54
        let dockH: CGFloat = 50
        collectionBox.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - dockH))
        collection.frame = collectionBox.bounds
        collection.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)
        dockBar.frame = CGRect(x: 0, y: bounds.height - dockH, width: bounds.width, height: dockH)
        dockHairline.frame = CGRect(x: 10, y: 0, width: max(0, bounds.width - 20), height: 1 / UIScreen.main.scale)

        let bh: CGFloat = 38
        let by = (dockH - bh) / 2
        deleteButton.frame = CGRect(x: bounds.width - side + 2, y: by, width: side - 10, height: bh)
        deleteButton.layer.shadowPath = UIBezierPath(roundedRect: deleteButton.bounds, cornerRadius: Metrics.cornerRadius).cgPath
        let closeW: CGFloat = 46
        closeButton.isHidden = false
        closeButton.frame = CGRect(x: deleteButton.frame.minX - 6 - closeW, y: by, width: closeW, height: bh)
        closeButton.layer.shadowPath = UIBezierPath(roundedRect: closeButton.bounds, cornerRadius: Metrics.cornerRadius).cgPath

        let rightLimit = closeButton.frame.minX - 6
        let badgeW: CGFloat = countBadge.isHidden ? 0 : min(48, max(30, ceil((countBadge.text as NSString? ?? "").size(withAttributes: [.font: countBadge.font as Any]).width) + 14))
        if filterRail.isHidden {
            filterRail.frame = .zero
            if !countBadge.isHidden {
                countBadge.frame = CGRect(x: 8, y: (dockH - 24) / 2, width: badgeW, height: 24)
            }
        } else {
            let railH: CGFloat = 32
            let railY = (dockH - railH) / 2
            let railMaxW = max(116, rightLimit - 8 - (badgeW > 0 ? badgeW + 6 : 0))
            let railW = min(156, railMaxW)
            filterRail.frame = CGRect(x: 8, y: railY, width: railW, height: railH)
            let pad: CGFloat = 2.5
            let gap: CGFloat = 2
            let segW = max(24, (railW - pad * 2 - gap * CGFloat(max(1, filterButtons.count - 1))) / CGFloat(max(1, filterButtons.count)))
            for (i, b) in filterButtons.enumerated() {
                b.frame = CGRect(x: pad + CGFloat(i) * (segW + gap), y: pad, width: segW, height: railH - pad * 2)
            }
            if !countBadge.isHidden {
                let badgeX = filterRail.frame.maxX + 6
                let availBadge = max(0, rightLimit - badgeX)
                countBadge.frame = availBadge >= 26
                    ? CGRect(x: badgeX, y: (dockH - 22) / 2, width: min(badgeW, availBadge), height: 22)
                    : .zero
                countBadge.isHidden = availBadge < 26
            }
        }
        collection.layoutIfNeeded()
        updateCollectionBottomFade()
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
        cell.correctionBar.backgroundColor = Theme.correctedMark.resolvedColor(with: traitCollection).cgColor
        cell.correctionBar.isHidden = !(isFirst && c.corrected)
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

    var collectionForTests: UICollectionView { collection }
    var displayedCountForTests: Int { displayedIndices.count }
    var singleCharButtonHiddenForTests: Bool { filterRail.isHidden }
    var closeButtonHiddenForTests: Bool { closeButton.isHidden }
    var filterModeForTests: Int { filterMode.rawValue }
    func selectFilterForTests(_ mode: Int) { setFilterMode(FilterMode(rawValue: mode) ?? .all) }
    var countBadgeTextForTests: String { countBadge.text ?? "" }
    var collectionBottomFadeActiveForTests: Bool { collectionBox.layer.mask === collectionFade }
    var dockControlsNonOverlappingForTests: Bool {
        let railOk = filterRail.isHidden || (!filterRail.frame.intersects(closeButton.frame) && !filterRail.frame.intersects(deleteButton.frame) && filterRail.frame.minX >= 0)
        let badgeOk = countBadge.isHidden || (!countBadge.frame.intersects(filterRail.frame) && !countBadge.frame.intersects(closeButton.frame))
        return railOk && badgeOk && !closeButton.frame.intersects(deleteButton.frame) && deleteButton.frame.maxX <= dockBar.bounds.width + 0.5
    }
    func tapCloseForTests() { closeTapped() }
    func toggleSingleCharForTests() { toggleSingleChar() }
    func selectDisplayedForTests(_ i: Int) { if i < displayedIndices.count { onSelect?(displayedIndices[i]) } }
    func longPressDisplayedForTests(_ i: Int) { if i < displayedIndices.count { onLongPress?(displayedIndices[i]) } }
    func deleteTapForTests() { onDelete?() }
}

/// R50/R69 single-layer OTTOSSOM physical toggle tile with micro-pictograph icon, 4.5pt hardware LED & grounded shadowPath.
private final class HardwareTileButton: UIControl {
    private let iconView = UIImageView()
    private let eyebrowLabel = UILabel()
    private let valueLabel = UILabel()
    private let ledDot = CALayer()
    private var activeTint: Bool = false
    private var locked: Bool = false
    private var lastShadowSize: CGSize = .zero
    private static var symbolCache: [String: UIImage] = [:]

    private static func cachedSymbol(_ name: String) -> UIImage? {
        if let img = symbolCache[name] { return img }
        let cfg = UIImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
        let img = UIImage(systemName: name, withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate)
        if let img { symbolCache[name] = img }
        return img
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
        layer.shadowOpacity = 1

        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)

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

    var hasSymbolForTests: Bool { iconView.image != nil }

    func configure(icon: String, eyebrow: String, value: String, active: Bool, locked: Bool = false, spoken: String? = nil) {
        iconView.image = Self.cachedSymbol(icon)
        eyebrowLabel.text = eyebrow
        valueLabel.text = value
        self.activeTint = active
        self.locked = locked
        accessibilityLabel = spoken ?? "\(eyebrow)：\(value)"
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
        let tint: UIColor = locked ? Theme.secondaryText.withAlphaComponent(0.6) : (activeTint ? Theme.selection : Theme.secondaryText)
        iconView.tintColor = tint.resolvedColor(with: t)
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
        ledDot.frame = CGRect(x: b.width - 12, y: 8.5, width: 4.5, height: 4.5)
        CATransaction.commit()
        let compact = b.height < 52
        let padX: CGFloat = 9.5
        let topPad: CGFloat = compact ? 5.5 : 8.5
        let iconSide: CGFloat = compact ? 13 : 14
        iconView.frame = CGRect(x: padX, y: topPad, width: iconSide, height: iconSide)
        let eyeX = padX + iconSide + 4
        eyebrowLabel.frame = CGRect(x: eyeX, y: topPad, width: max(0, b.width - eyeX - 18), height: iconSide)
        valueLabel.frame = CGRect(x: padX, y: eyebrowLabel.frame.maxY + (compact ? 1 : 3), width: max(0, b.width - padX * 2), height: max(18, b.height - eyebrowLabel.frame.maxY - (compact ? 5 : 8)))
    }
}

/// R69 Visual-First 1-tap 4-step elevation rail (`紧 / 标 / 舒 / 宽`) with ascending hardware height silhouettes.
private final class ElevationRailView: UIView {
    var selectedTier: KeyboardHeightPreset = .standard {
        didSet { if selectedTier != oldValue { refreshAppearance() } }
    }
    var embeddedInGroup = false {
        didSet { if embeddedInGroup != oldValue { refreshAppearance() } }
    }
    var onSelect: ((KeyboardHeightPreset) -> Void)?

    private var buttons: [UIButton] = []
    private var barLayers: [CALayer] = []
    private var markLabels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 15
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        clipsToBounds = true

        for preset in KeyboardHeightPreset.allCases {
            let btn = UIButton(type: .custom)
            btn.tag = preset.rawValue
            btn.layer.cornerRadius = 12
            btn.layer.cornerCurve = .continuous
            btn.accessibilityLabel = "键盘高度：\(preset.title)"
            btn.accessibilityTraits = .button
            btn.addTarget(self, action: #selector(tierTapped(_:)), for: .touchUpInside)

            let bar = CALayer()
            bar.cornerRadius = 1.1
            btn.layer.addSublayer(bar)

            let lbl = UILabel()
            lbl.text = preset.shortMark
            lbl.font = Theme.font(11.5, .semibold)
            lbl.textAlignment = .left
            lbl.isUserInteractionEnabled = false
            btn.addSubview(lbl)

            addSubview(btn)
            buttons.append(btn)
            barLayers.append(bar)
            markLabels.append(lbl)
        }
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tierTapped(_ sender: UIButton) {
        let tier = KeyboardHeightPreset.clamped(sender.tag)
        selectedTier = tier
        onSelect?(tier)
    }

    func selectForTests(_ tier: KeyboardHeightPreset) {
        guard tier.rawValue < buttons.count else { return }
        tierTapped(buttons[tier.rawValue])
    }

    func refreshAppearance() {
        let t = traitCollection
        backgroundColor = (embeddedInGroup ? Theme.touchable : Theme.settingsGroup).resolvedColor(with: t)
        layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, btn) in buttons.enumerated() {
            let active = i == selectedTier.rawValue
            let fill: UIColor = active ? Theme.selection : .clear
            btn.backgroundColor = fill.resolvedColor(with: t)
            btn.isSelected = active
            btn.accessibilityValue = active ? "已选" : nil
            let fg: UIColor = active ? Theme.selectionText : (i <= selectedTier.rawValue ? Theme.keyText : Theme.secondaryText)
            markLabels[i].textColor = fg.resolvedColor(with: t)
            markLabels[i].font = Theme.font(11.5, active ? .bold : .semibold)
            let barColor: UIColor = active ? Theme.selectionText : (i <= selectedTier.rawValue ? Theme.statusLedActive : Theme.statusLedMuted)
            barLayers[i].backgroundColor = barColor.resolvedColor(with: t).cgColor
        }
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refreshAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        guard w > 40, h > 16 else { return }
        let pad: CGFloat = 2.5
        let gap: CGFloat = 2
        let count = CGFloat(buttons.count)
        let segW = max(12, (w - pad * 2 - gap * (count - 1)) / count)
        let segH = max(12, h - pad * 2)
        let heights: [CGFloat] = [5, 7.5, 10, 12.5]
        let barW: CGFloat = 2.5
        let bottomY = (segH + 12.5) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, btn) in buttons.enumerated() {
            btn.frame = CGRect(x: pad + CGFloat(i) * (segW + gap), y: pad, width: segW, height: segH)
            let bh = heights[min(i, heights.count - 1)]
            let barX = max(3.5, floor((segW - 18) * 0.5))
            barLayers[i].frame = CGRect(x: barX, y: bottomY - bh, width: barW, height: bh)
            markLabels[i].frame = CGRect(x: barX + barW + 2.5, y: 0, width: max(12, segW - barX - barW - 3.5), height: segH)
        }
        CATransaction.commit()
    }
}

/// OTTOSSOM miniature ceramic telemetry badge inside the secondary preferences drawer.
private final class TelemetryChipView: UIView {
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        valueLabel.font = Theme.font(14.5, .bold)
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.72
        captionLabel.font = Theme.font(10.5, .medium)
        captionLabel.textAlignment = .center
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.75

        let v = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        v.axis = .vertical
        v.spacing = 1.5
        v.alignment = .fill
        addSubview(v)
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            v.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    var valueTextForTests: String { valueLabel.text ?? "" }

    func configure(value: String, caption: String) {
        valueLabel.text = value
        captionLabel.text = caption
        isAccessibilityElement = true
        accessibilityLabel = "\(caption)：\(value)"
    }

    func refreshAppearance() {
        let t = traitCollection
        backgroundColor = Theme.functionKey.resolvedColor(with: t)
        layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        valueLabel.textColor = Theme.keyText.resolvedColor(with: t)
        captionLabel.textColor = Theme.secondaryText.resolvedColor(with: t)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refreshAppearance()
    }
}

/// OTTOSSOM zero-scroll hardware control deck (2x3 tactile tiles + contextual Xiaohe guide pill) with a clean
/// visual telemetry secondary drawer (`更多 ›`) for low-frequency toggles, learned lexicon stats & diagnostics.
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
    private let heightRail = ElevationRailView()
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
    private let drawerHeightRail = ElevationRailView()
    private let lexiconChip = TelemetryChipView()
    private let learnedChip = TelemetryChipView()
    private let learnedLabel = UILabel()
    private let tapsChip = TelemetryChipView()
    private let memChip = TelemetryChipView()
    private let readyChip = TelemetryChipView()
    private let diagLabel = UILabel()
    private let notePill = UIView()
    private let noteIcon = UIImageView()
    private let note = UILabel()
    private var telemetryChips: [TelemetryChipView] { [lexiconChip, learnedChip, tapsChip, memChip, readyChip] }
    private let resetTrashIcon = UIImageView()
    private var rawDiagnostics = ""
    private var cachedLexiconDisplay = "--"
    private var cachedLearnedDisplay = "0 词"
    private var groups: [UIView] = []
    private var feedbackAvailable = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.touchable
        tintColor = Theme.selection
        englishSwitch.onTintColor = Theme.selection
        numberControl.translatesAutoresizingMaskIntoConstraints = false
        numberControl.widthAnchor.constraint(equalToConstant: 156).isActive = true
        for i in 0..<numberControl.numberOfSegments { numberControl.setWidth(78, forSegmentAt: i) }
        drawerHeightRail.embeddedInGroup = true
        drawerHeightRail.translatesAutoresizingMaskIntoConstraints = false
        drawerHeightRail.widthAnchor.constraint(equalToConstant: 200).isActive = true
        drawerHeightRail.heightAnchor.constraint(equalToConstant: 31).isActive = true
        for sc in [numberControl, appearance, styleControl] {
            sc.selectedSegmentTintColor = Theme.selection
            sc.setTitleTextAttributes([.foregroundColor: Theme.selectionText, .font: Theme.font(13, .semibold)], for: .selected)
            sc.setTitleTextAttributes([.foregroundColor: Theme.keyText, .font: Theme.font(13, .medium)], for: .normal)
            sc.setContentHuggingPriority(.required, for: .horizontal)
        }

        // Header: [backDeck capsule when in secondary drawer] / Mosto + title + Done pill
        backDeckButton.setImage(UIImage(systemName: "chevron.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10.5, weight: .bold)), for: .normal)
        backDeckButton.setTitle(" 概览", for: .normal)
        backDeckButton.titleLabel?.font = Theme.font(12, .semibold)
        backDeckButton.layer.cornerRadius = 14
        backDeckButton.layer.cornerCurve = .continuous
        backDeckButton.layer.borderWidth = 0.5
        backDeckButton.translatesAutoresizingMaskIntoConstraints = false
        backDeckButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        backDeckButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        backDeckButton.accessibilityLabel = "返回控制台概览"
        backDeckButton.isHidden = true
        backDeckButton.addTarget(self, action: #selector(closeMore), for: .touchUpInside)

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

        let h = UIStackView(arrangedSubviews: [backDeckButton, mostoImage, titles, UIView(), doneButton])
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

        accessBanner.text = "震动与声效需在系统设置开启「允许完全访问」"
        accessBanner.font = Theme.font(11.5, .medium)
        accessBanner.textColor = Theme.correctedMark
        accessBanner.textAlignment = .center
        accessBanner.numberOfLines = 1
        accessBanner.adjustsFontSizeToFitWidth = true
        accessBanner.minimumScaleFactor = 0.78
        accessBanner.isHidden = true
        deckContainer.addSubview(accessBanner)

        deckContainer.addSubview(utilityRow)
        guidePill.setTitle("   键位提示", for: .normal)
        guidePill.titleLabel?.font = Theme.font(11.5, .semibold)
        guidePill.titleLabel?.adjustsFontSizeToFitWidth = true
        guidePill.titleLabel?.minimumScaleFactor = 0.85
        guidePill.layer.cornerRadius = 15
        guidePill.layer.cornerCurve = .continuous
        guidePill.layer.borderWidth = 0.5
        guideLed.cornerRadius = 2.25
        guidePill.layer.addSublayer(guideLed)
        guidePill.addTarget(self, action: #selector(toggleGuide), for: .touchUpInside)
        utilityRow.addSubview(guidePill)

        offlineStatusLabel.text = "纯离线"
        offlineStatusLabel.font = Theme.font(11.5, .medium)
        offlineStatusLabel.textColor = Theme.secondaryText
        utilityRow.addSubview(offlineStatusLabel)

        let onElevationSelect: (KeyboardHeightPreset) -> Void = { [weak self] tier in
            self?.applyElevation(tier)
        }
        heightRail.onSelect = onElevationSelect
        drawerHeightRail.onSelect = onElevationSelect
        utilityRow.addSubview(heightRail)

        moreButton.setTitle("更多 ›", for: .normal)
        moreButton.titleLabel?.font = Theme.font(12, .semibold)
        moreButton.titleLabel?.adjustsFontSizeToFitWidth = true
        moreButton.titleLabel?.minimumScaleFactor = 0.85
        moreButton.layer.cornerRadius = 15
        moreButton.layer.cornerCurve = .continuous
        moreButton.addTarget(self, action: #selector(openMore), for: .touchUpInside)
        utilityRow.addSubview(moreButton)

        // Secondary OTTOSSOM Instrument Drawer (`moreScroll`)
        moreScroll.isHidden = true
        moreScroll.alwaysBounceHorizontal = false
        moreScroll.showsHorizontalScrollIndicator = false
        moreScroll.disableAllEdgeEffects()
        addSubview(moreScroll)

        stack.axis = .vertical
        stack.spacing = 6
        moreScroll.addSubview(stack)

        section("输入与按键", rows: [
            row("中英混输", icon: "globe", englishSwitch),
            row("123 数字键", icon: "number.square", numberControl),
        ], footer: nil)

        section("外观与比例", rows: [
            row("风格", icon: "paintpalette", styleControl),
            row("光线", icon: "sun.max", appearance),
            row("高度", icon: "arrow.up.and.down.square", drawerHeightRail),
        ], footer: nil)

        lexiconChip.configure(value: "--", caption: "内置词库")
        learnedChip.configure(value: "0 词", caption: "已学习")
        let lexRow = UIStackView(arrangedSubviews: [lexiconChip, learnedChip])
        lexRow.axis = .horizontal
        lexRow.distribution = .fillEqually
        lexRow.spacing = 8

        learnedLabel.font = Theme.font(12, .medium)
        learnedLabel.textColor = Theme.secondaryText
        learnedLabel.tag = Self.tagSecondary
        learnedLabel.numberOfLines = 0
        learnedLabel.isHidden = true

        let lexCol = UIStackView(arrangedSubviews: [lexRow, learnedLabel])
        lexCol.axis = .vertical
        lexCol.spacing = 6

        resetTrashIcon.contentMode = .scaleAspectFit
        resetTrashIcon.image = UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold))
        resetTrashIcon.translatesAutoresizingMaskIntoConstraints = false
        resetTrashIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        resetTrashIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        resetButton.setTitle("清空已学习的词语与触点习惯", for: .normal)
        resetButton.titleLabel?.font = Theme.font(14, .semibold)
        resetButton.titleLabel?.adjustsFontSizeToFitWidth = true
        resetButton.titleLabel?.minimumScaleFactor = 0.85
        resetButton.contentHorizontalAlignment = .leading
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        let resetRow = UIStackView(arrangedSubviews: [resetTrashIcon, resetButton])
        resetRow.alignment = .center
        resetRow.spacing = 7
        section("本机词库", rows: [lexCol, resetRow], footer: nil)

        tapsChip.configure(value: "--", caption: "本次按键")
        memChip.configure(value: "--", caption: "内存占用")
        readyChip.configure(value: "--", caption: "引擎就绪")
        let diagRow = UIStackView(arrangedSubviews: [tapsChip, memChip, readyChip])
        diagRow.axis = .horizontal
        diagRow.distribution = .fillEqually
        diagRow.spacing = 8

        diagLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        diagLabel.textColor = Theme.secondaryText
        diagLabel.tag = Self.tagSecondary
        diagLabel.numberOfLines = 0
        diagLabel.isHidden = true

        let diagCol = UIStackView(arrangedSubviews: [diagRow, diagLabel])
        diagCol.axis = .vertical
        diagCol.spacing = 6
        if Self.isTestFlight {
            section("实时遥测", rows: [diagCol], footer: nil)
        }

        notePill.backgroundColor = Theme.settingsGroup
        notePill.tag = Self.tagGroup
        notePill.layer.cornerRadius = 11
        notePill.layer.cornerCurve = .continuous
        noteIcon.contentMode = .scaleAspectFit
        noteIcon.image = UIImage(systemName: "lock.shield.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold))
        noteIcon.tintColor = Theme.secondaryText
        noteIcon.translatesAutoresizingMaskIntoConstraints = false
        noteIcon.widthAnchor.constraint(equalToConstant: 15).isActive = true
        noteIcon.heightAnchor.constraint(equalToConstant: 15).isActive = true

        note.numberOfLines = 0
        note.font = Theme.font(11.5, .medium)
        note.textColor = Theme.secondaryText
        note.tag = Self.tagSecondary
        note.text = "纯离线本机运算 · 零联网零跨进程共享"

        let noteStack = UIStackView(arrangedSubviews: [noteIcon, note])
        noteStack.alignment = .center
        noteStack.spacing = 7
        notePill.addSubview(noteStack)
        noteStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            noteStack.leadingAnchor.constraint(equalTo: notePill.leadingAnchor, constant: 12),
            noteStack.trailingAnchor.constraint(equalTo: notePill.trailingAnchor, constant: -12),
            noteStack.topAnchor.constraint(equalTo: notePill.topAnchor, constant: 8),
            noteStack.bottomAnchor.constraint(equalTo: notePill.bottomAnchor, constant: -8),
        ])
        let noteWrap = UIView()
        noteWrap.addSubview(notePill)
        notePill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            notePill.leadingAnchor.constraint(equalTo: noteWrap.leadingAnchor, constant: 12),
            notePill.trailingAnchor.constraint(equalTo: noteWrap.trailingAnchor, constant: -12),
            notePill.topAnchor.constraint(equalTo: noteWrap.topAnchor),
            notePill.bottomAnchor.constraint(equalTo: noteWrap.bottomAnchor),
        ])
        stack.addArrangedSubview(noteWrap)

        numberControl.addTarget(self, action: #selector(numberChanged), for: .valueChanged)
        for c in [appearance, styleControl] { c.addTarget(self, action: #selector(drawerChanged), for: .valueChanged) }
        englishSwitch.addTarget(self, action: #selector(drawerChanged), for: .valueChanged)

        styleChrome()
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func destructiveRedColor(for t: UITraitCollection) -> UIColor {
        t.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1)
            : UIColor(red: 0.80, green: 0.16, blue: 0.18, alpha: 1)
    }

    private func styleChrome() {
        let t = traitCollection
        tintColor = Theme.selection
        headerHairline.backgroundColor = Theme.separator.resolvedColor(with: t).cgColor
        let inMore = !moreScroll.isHidden
        mostoImage.isHidden = Theme.plain || inMore
        backDeckButton.isHidden = !inMore
        backDeckButton.backgroundColor = Theme.functionKey
        backDeckButton.setTitleColor(Theme.keyText, for: .normal)
        backDeckButton.tintColor = Theme.keyText
        backDeckButton.layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        doneButton.backgroundColor = Theme.plain ? Theme.selection : Theme.accentKey
        doneButton.setTitleColor(Theme.plain ? Theme.selectionText : Theme.accentText, for: .normal)
        moreButton.backgroundColor = Theme.functionKey
        moreButton.setTitleColor(Theme.functionText, for: .normal)
        accessBanner.textColor = Theme.correctedMark
        for sc in [numberControl, appearance, styleControl] {
            sc.selectedSegmentTintColor = Theme.selection
            sc.setTitleTextAttributes([.foregroundColor: Theme.selectionText, .font: Theme.font(13, .semibold)], for: .selected)
            sc.setTitleTextAttributes([.foregroundColor: Theme.keyText, .font: Theme.font(13, .medium)], for: .normal)
        }
        englishSwitch.onTintColor = Theme.selection
        let red = destructiveRedColor(for: t)
        resetButton.setTitleColor(red, for: .normal)
        resetTrashIcon.tintColor = red
        noteIcon.tintColor = (feedbackAvailable ? Theme.secondaryText : Theme.correctedMark).resolvedColor(with: t)
        for tile in hardwareTiles { tile.refreshAppearance() }
        for chip in telemetryChips { chip.refreshAppearance() }
        refreshGuidePill()
        refreshHeightRail()
    }

    var heightPresetForTests: KeyboardHeightPreset { KeyboardHeightPreset.clamped(KeyboardSettings.shared.keyboardHeight) }
    var drawerHeightPresetForTests: KeyboardHeightPreset { drawerHeightRail.selectedTier }
    var heightPillTitleForTests: String { "高度·\(heightPresetForTests.title)" }
    func tapHeightPillForTests() { cycleHeight() }
    func selectHeightForTests(_ preset: KeyboardHeightPreset) { heightRail.selectForTests(preset) }
    func selectDrawerHeightForTests(_ preset: KeyboardHeightPreset) { drawerHeightRail.selectForTests(preset) }
    var tileIconsLoadedForTests: Bool { hardwareTiles.allSatisfy(\.hasSymbolForTests) }
    var isResetConfirmingForTests: Bool { resetConfirming }
    var telemetrySummaryForTests: (lexicon: String, learned: String, mem: String, ready: String) {
        (lexiconChip.valueTextForTests, learnedChip.valueTextForTests, memChip.valueTextForTests, readyChip.valueTextForTests)
    }
    var preferredFullHeightForTests: CGFloat {
        let headH: CGFloat = (bounds.height > 60 && bounds.height < 205) ? 36 : 42
        let w = bounds.width > 60 ? bounds.width : 375
        let size = stack.systemLayoutSizeFitting(
            CGSize(width: w, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return headH + size.height + 22
    }

    private func refreshHeightRail() {
        let tier = KeyboardHeightPreset.clamped(KeyboardSettings.shared.keyboardHeight)
        heightRail.selectedTier = tier
        heightRail.refreshAppearance()
        drawerHeightRail.selectedTier = tier
        drawerHeightRail.refreshAppearance()
    }

    private func applyElevation(_ tier: KeyboardHeightPreset) {
        KeyboardSettings.shared.keyboardHeight = tier.rawValue
        if canProvideHaptic {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: tier.hapticIntensity)
        }
        load()
        onChange?()
    }

    @objc private func cycleHeight() {
        applyElevation(KeyboardHeightPreset.clamped(KeyboardSettings.shared.keyboardHeight).next)
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
        cap.font = .systemFont(ofSize: 12)
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
            stack.setCustomSpacing(10, after: fw)
        } else {
            stack.setCustomSpacing(10, after: wrap)
        }
    }

    private func row(_ text: String, icon: String, _ control: UIView) -> UIView {
        let iv = UIImageView(image: UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)))
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Theme.secondaryText
        iv.tag = Self.tagIcon
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 17).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 17).isActive = true

        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 14.5, weight: .medium)
        l.textColor = Theme.keyText
        l.tag = Self.tagPrimary
        l.numberOfLines = 1
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        let s = UIStackView(arrangedSubviews: [iv, l, UIView(), control])
        s.alignment = .center
        s.spacing = 7
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

    private static let tagPrimary = 9_701, tagSecondary = 9_702, tagGroup = 9_703, tagLine = 9_704, tagIcon = 9_705

    func themeChanged() {
        styleChrome()
        func walk(_ v: UIView) {
            switch v.tag {
            case Self.tagPrimary: (v as? UILabel)?.textColor = Theme.keyText
            case Self.tagSecondary: (v as? UILabel)?.textColor = Theme.secondaryText
            case Self.tagGroup: v.backgroundColor = Theme.settingsGroup
            case Self.tagLine: v.backgroundColor = Theme.separator
            case Self.tagIcon: (v as? UIImageView)?.tintColor = Theme.secondaryText
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
        let heightName = KeyboardHeightPreset.clamped(s.keyboardHeight).title
        statusLabel.text = "\(s.style == 1 ? "简洁" : light) · \(s.scheme == 0 ? "双拼" : "全拼") · \(s.pinyinGrid ? "九宫格" : "全键盘") · \(heightName)"
    }

    func load() {
        let s = KeyboardSettings.shared
        updateStatus()

        schemeTile.configure(
            icon: "character.textbox",
            eyebrow: "方案",
            value: s.scheme == 0 ? "双拼" : "全拼",
            active: s.scheme == 0,
            spoken: "输入方案：\(s.scheme == 0 ? "小鹤双拼" : "全拼")"
        )
        layoutTile.configure(
            icon: s.pinyinGrid ? "square.grid.3x3" : "keyboard",
            eyebrow: "布局",
            value: s.pinyinGrid ? "九宫格" : "全键盘",
            active: s.pinyinGrid,
            spoken: "键盘布局：\(s.pinyinGrid ? "九宫格" : "全键盘")"
        )
        let lightIcon: String
        let lightTitle: String
        if s.style == 1 {
            lightIcon = "sparkles"
            lightTitle = "简洁"
        } else {
            lightIcon = ["circle.lefthalf.filled", "sun.max.fill", "moon.stars.fill"][s.appearance]
            lightTitle = ["自动", "日光", "夜灯"][s.appearance]
        }
        lightTile.configure(
            icon: lightIcon,
            eyebrow: "光效",
            value: lightTitle,
            active: s.style == 0,
            spoken: "台灯光效：\(lightTitle)"
        )

        let prof = HapticProfile(rawValue: s.hapticProfile) ?? .crisp
        hapticTile.configure(
            icon: "iphone.radiowaves.left.and.right",
            eyebrow: "震动",
            value: feedbackAvailable ? (s.feedback ? prof.title : "关闭") : "需访问",
            active: feedbackAvailable && s.feedback,
            locked: !feedbackAvailable,
            spoken: "按键震动：\(feedbackAvailable ? (s.feedback ? prof.deckValue : "已关闭") : "需允许完全访问")"
        )
        soundTile.configure(
            icon: (feedbackAvailable && s.keySound) ? "speaker.wave.2.fill" : "speaker.slash",
            eyebrow: "声效",
            value: feedbackAvailable ? (s.keySound ? "原声" : "静音") : "需访问",
            active: feedbackAvailable && s.keySound,
            locked: !feedbackAvailable,
            spoken: "按键声效：\(feedbackAvailable ? (s.keySound ? "原声开启" : "已静音") : "需允许完全访问")"
        )
        correctTile.configure(
            icon: "wand.and.stars",
            eyebrow: "纠错",
            value: s.autocorrect ? "开启" : "关闭",
            active: s.autocorrect,
            spoken: "触点纠错：\(s.autocorrect ? "智能开启" : "已关闭")"
        )

        numberControl.selectedSegmentIndex = s.numberPad ? 1 : 0
        englishSwitch.isOn = s.english
        appearance.selectedSegmentIndex = s.appearance
        styleControl.selectedSegmentIndex = s.style
        refreshGuidePill()
        refreshHeightRail()
        setNeedsLayout()
    }

    func setNote(_ text: String) {
        let needsAccess = !feedbackAvailable || text.contains("允许完全访问")
        noteIcon.image = UIImage(
            systemName: needsAccess ? "exclamationmark.shield.fill" : "lock.shield.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
        )
        noteIcon.tintColor = (needsAccess ? Theme.correctedMark : Theme.secondaryText).resolvedColor(with: traitCollection)
        note.text = needsAccess
            ? "需在「设置 › Mosto键盘」开启完全访问以启用震动与声音 · 词库全程离线"
            : "纯离线本机运算 · 零联网零跨进程共享"
    }

    func setFeedbackAvailable(_ ok: Bool) {
        feedbackAvailable = ok
        accessBanner.isHidden = ok
        hapticTile.isEnabled = ok
        soundTile.isEnabled = ok
        setNote("")
        load()
    }

    private static func extractInt(after marker: String, in text: String) -> Int? {
        guard let r = text.range(of: marker) else { return nil }
        var rest = text[r.upperBound...]
        while let ch = rest.first, !ch.isNumber {
            if !ch.isWhitespace { break }
            rest.removeFirst()
        }
        let digits = rest.prefix(while: \.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    func setLearned(_ text: String) {
        learnedLabel.text = text
        if text.contains("已清空") {
            cachedLearnedDisplay = "已清空"
            learnedChip.configure(value: cachedLearnedDisplay, caption: "已学习")
            lexiconChip.configure(value: cachedLexiconDisplay, caption: "内置词库")
            learnedLabel.isHidden = true
            return
        }
        if let lex = Self.extractInt(after: "词库 ", in: text),
           let learned = Self.extractInt(after: "已学习 ", in: text) {
            cachedLexiconDisplay = lex >= 10_000 ? "\(lex / 10_000)万+" : "\(lex)"
            cachedLearnedDisplay = "\(learned) 词"
            lexiconChip.configure(value: cachedLexiconDisplay, caption: "内置词库")
            learnedChip.configure(value: cachedLearnedDisplay, caption: "已学习")
            learnedLabel.isHidden = true
        } else {
            learnedLabel.isHidden = text.isEmpty
        }
    }

    func setDiagnostics(_ text: String) {
        rawDiagnostics = text
        diagLabel.text = text
        let tapsVal = Self.extractInt(after: "本次按键 ", in: text).map { "\($0) 次" } ?? "--"
        let memVal = Self.extractInt(after: "内存 ", in: text).map { "\($0) MB" } ?? "--"
        let readyVal = Self.extractInt(after: "引擎就绪 ", in: text).map { "\($0) ms" } ?? "--"
        tapsChip.configure(value: tapsVal, caption: "本次按键")
        memChip.configure(value: memVal, caption: "内存占用")
        readyChip.configure(value: readyVal, caption: "引擎就绪")
        let alertOnly = text.contains("精简模式") || text.contains("内存警告")
        diagLabel.isHidden = !alertOnly
    }

    /// Snapshot & compatibility helper: keeps the primary zero-scroll Hardware Deck focused.
    func demoScrollToFeedback() {
        moreScroll.isHidden = true
        deckContainer.isHidden = false
        styleChrome()
        setNeedsLayout()
    }

    var diagnosticsText: String { rawDiagnostics }

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
        styleChrome()
        setNeedsLayout()
    }

    private func resetConfirmationPrompt() {
        resetConfirming = false
        resetButton.setTitle("清空已学习的词语与触点习惯", for: .normal)
    }

    @objc private func closeMore() {
        if canProvideHaptic { UISelectionFeedbackGenerator().selectionChanged() }
        resetConfirmationPrompt()
        moreScroll.isHidden = true
        deckContainer.isHidden = false
        styleChrome()
        setNeedsLayout()
    }

    @objc private func drawerChanged() {
        if canProvideHaptic { UISelectionFeedbackGenerator().selectionChanged() }
        let s = KeyboardSettings.shared
        s.english = englishSwitch.isOn
        if appearance.selectedSegmentIndex >= 0 {
            s.appearance = appearance.selectedSegmentIndex
        }
        if styleControl.selectedSegmentIndex >= 0 {
            s.style = styleControl.selectedSegmentIndex
        }
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
        resetConfirmationPrompt()
        moreScroll.isHidden = true
        deckContainer.isHidden = false
        styleChrome()
        onClose?()
    }

    @objc private func resetTapped() {
        if !resetConfirming {
            resetConfirming = true
            if canProvideHaptic { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            resetButton.setTitle("确认清空？再点一次立即清空", for: .normal)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self, self.resetConfirming else { return }
                self.resetConfirmationPrompt()
            }
        } else {
            resetConfirmationPrompt()
            if canProvideHaptic { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            onResetLearning?()
        }
    }

    var hardwareTileCountForTests: Int { hardwareTiles.count }
    var showingMoreForTests: Bool { !moreScroll.isHidden }
    var backDeckButtonInHeaderForTests: Bool { backDeckButton.isDescendant(of: header) && !backDeckButton.isHidden && mostoImage.isHidden }
    var drawerHeightEmbeddedForTests: Bool {
        drawerHeightRail.embeddedInGroup
            && drawerHeightRail.backgroundColor?.resolvedColor(with: traitCollection) != Theme.settingsGroup.resolvedColor(with: traitCollection)
    }
    func toggleMoreForTests() { if moreScroll.isHidden { openMore() } else { closeMore() } }
    func tapSchemeTileForTests() { toggleScheme() }
    func tapHapticTileForTests() { toggleHaptic() }
    var maxTileHeightForTests: CGFloat { hardwareTiles.map(\.frame.height).max() ?? 0 }
    var utilityRowNonOverlappingForTests: Bool {
        let guideOk = guidePill.isHidden || (!guidePill.frame.intersects(heightRail.frame) && guidePill.frame.maxX <= utilityRow.bounds.width + 0.5)
        let offlineOk = offlineStatusLabel.isHidden || (!offlineStatusLabel.frame.intersects(heightRail.frame) && offlineStatusLabel.frame.maxX <= utilityRow.bounds.width + 0.5)
        return guideOk && offlineOk
            && !heightRail.frame.intersects(moreButton.frame)
            && heightRail.frame.minX >= 0
            && moreButton.frame.maxX <= utilityRow.bounds.width + 0.5
    }
    var bannerNonOverlappingForTests: Bool {
        accessBanner.isHidden || (!accessBanner.frame.intersects(utilityRow.frame) && !accessBanner.frame.intersects(hapticTile.frame))
    }

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
        let compactH = h < 205
        let padX: CGFloat = 10
        let gapX: CGFloat = 8
        let gapY: CGFloat = compactH ? 4 : 8
        let bannerH: CGFloat = accessBanner.isHidden ? 0 : (compactH ? 16 : 18)
        let utilH: CGFloat = compactH ? 28 : 30
        let padTop: CGFloat = compactH ? 4 : 10
        let padBot: CGFloat = compactH ? 4 : 10
        let availH = bodyFrame.height - padTop - padBot - utilH - bannerH - gapY * (accessBanner.isHidden ? 2 : 3)
        let rowH = min(84, max(compactH ? 38 : 42, floor(availH / 2)))
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
        utilityRow.frame = CGRect(x: padX, y: min(nextY, max(nextY, bodyFrame.height - utilH - padBot)), width: w - padX * 2, height: utilH)
        let uw = utilityRow.bounds.width
        let gapUtil: CGFloat = 6
        let moreW = min(74, max(62, (uw * 0.18).rounded()))
        moreButton.frame = CGRect(x: uw - moreW, y: 0, width: moreW, height: utilH)
        let showGuide = !guidePill.isHidden
        let leftW: CGFloat = showGuide ? min(98, max(82, (uw * 0.24).rounded())) : min(56, max(44, (uw * 0.14).rounded()))
        let railMax = max(120, uw - leftW - moreW - gapUtil * 2)
        let railW = min(204, max(min(railMax, 148), floor((uw * 0.48).rounded())))
        let railX = uw - moreW - gapUtil - railW
        heightRail.frame = CGRect(x: railX, y: 0, width: railW, height: utilH)
        let actualLeftW = max(40, railX - gapUtil)
        guidePill.frame = CGRect(x: 0, y: 0, width: min(leftW, actualLeftW), height: utilH)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideLed.frame = CGRect(x: 9, y: (utilH - 4.5) / 2, width: 4.5, height: 4.5)
        CATransaction.commit()
        offlineStatusLabel.frame = CGRect(x: 2, y: 0, width: min(leftW, actualLeftW), height: utilH)

        // Layout secondary `moreScroll`
        let size = stack.systemLayoutSizeFitting(
            CGSize(width: w, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        stack.frame = CGRect(x: 0, y: 10, width: w, height: size.height)
        moreScroll.contentSize = CGSize(width: w, height: size.height + 20)
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
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) != nil,
           let group = UserDefaults(suiteName: Self.appGroupID) {
            if !group.bool(forKey: "migratedToAppGroup") {
                let keys = ["scheme", "autocorrect", "xiaoheGuide", "english", "pinyinGrid", "numberPad", "style", "appearance", "keyboardHeight", "feedback", "hapticProfile", "keySound", "keyOffsets", "offsetX", "offsetY"]
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

    var usesStandardDefaultsForTests: Bool { d === UserDefaults.standard }

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

    /// Keyboard elevation tier: 0 紧凑 / 1 标准 (default) / 2 舒展 / 3 宽大.
    var keyboardHeight: Int {
        get {
            guard let raw = (d.object(forKey: "keyboardHeight") as? NSNumber)?.intValue else {
                return KeyboardHeightPreset.standard.rawValue
            }
            return KeyboardHeightPreset.clamped(raw).rawValue
        }
        set {
            d.set(KeyboardHeightPreset.clamped(newValue).rawValue, forKey: "keyboardHeight")
            notify()
        }
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
/// (longest first, then the most common) inside an OTTOSSOM recessed ceramic tuner track. Tapping one fixes
/// those keys to its letters. Scrolls vertically only with a soft bottom overflow fade.
final class SyllablePickerView: UIView, UIScrollViewDelegate {
    var onPick: ((Int) -> Void)?
    private let scrollBox = UIView()
    private let scroll = UIScrollView()
    private let bottomFade = CAGradientLayer()
    private let activeBar = UIView()
    private var buttons: [UIButton] = []
    private var dividers: [CALayer] = []
    private var shown = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.functionKey
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.6
        layer.borderColor = Theme.keyBorder.resolvedColor(with: traitCollection).cgColor
        clipsToBounds = true

        scrollBox.backgroundColor = .clear
        addSubview(scrollBox)

        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        scroll.delegate = self
        scroll.disableAllEdgeEffects()
        scrollBox.addSubview(scroll)

        bottomFade.startPoint = CGPoint(x: 0.5, y: 0)
        bottomFade.endPoint = CGPoint(x: 0.5, y: 1)
        bottomFade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]

        activeBar.isUserInteractionEnabled = false
        activeBar.layer.cornerRadius = 1.25
        activeBar.layer.cornerCurve = .continuous
        activeBar.isHidden = true
        scroll.addSubview(activeBar)

        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            refreshAppearance()
        }
    }

    func themeChanged() {
        backgroundColor = Theme.functionKey
        refreshAppearance()
        setNeedsLayout()
    }

    private func refreshAppearance() {
        let t = traitCollection
        layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        activeBar.backgroundColor = Theme.selection
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let divCG = Theme.candidateDivider.resolvedColor(with: t).cgColor
        for d in dividers { d.backgroundColor = divCG }
        CATransaction.commit()
        for (i, b) in buttons.enumerated() {
            styleButton(b, active: i == 0)
        }
    }

    private func styleButton(_ b: UIButton, active: Bool) {
        b.titleLabel?.font = Theme.font(active ? 16.5 : 16, active ? .bold : .semibold)
        if active {
            b.backgroundColor = Theme.key
            b.layer.cornerRadius = 7
            b.layer.cornerCurve = .continuous
            let fg = Theme.plain ? Theme.selection : Theme.keyText
            b.tintColor = fg
            b.setTitleColor(fg, for: .normal)
            b.accessibilityTraits = [.button, .selected]
        } else {
            b.backgroundColor = .clear
            b.layer.cornerRadius = 6
            b.layer.cornerCurve = .continuous
            b.tintColor = Theme.keyText
            b.setTitleColor(Theme.keyText, for: .normal)
            b.accessibilityTraits = .button
        }
    }

    /// Buttons are kept and relabelled (this runs on every keypad key), never rebuilt.
    func show(_ choices: [String]) {
        while buttons.count < choices.count {
            let b = UIButton(type: .system)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.6
            b.tag = buttons.count
            styleButton(b, active: b.tag == 0)
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            scroll.addSubview(b)
            buttons.append(b)
        }
        for (i, b) in buttons.enumerated() {
            let on = i < choices.count
            b.isHidden = !on
            if on {
                styleButton(b, active: i == 0)
                UIView.performWithoutAnimation {
                    b.setTitle(choices[i], for: .normal)
                    b.layoutIfNeeded()
                }
                b.accessibilityLabel = "拼音 \(choices[i])"
            }
        }
        shown = choices.count
        refreshAppearance()
        scroll.setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateBottomFade()
    }

    private func updateBottomFade() {
        let h = scrollBox.bounds.height
        let hasMore = h > 32 && scroll.contentSize.height > h + 2 && (scroll.contentOffset.y + h < scroll.contentSize.height - 2)
        guard hasMore else {
            if scrollBox.layer.mask != nil { scrollBox.layer.mask = nil }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bottomFade.frame = scrollBox.bounds
        let frac = Double(min(0.20, 14.0 / h))
        bottomFade.locations = [0, NSNumber(value: 1.0 - frac), 1]
        if scrollBox.layer.mask !== bottomFade { scrollBox.layer.mask = bottomFade }
        CATransaction.commit()
    }

    var shownCountForTests: Int { shown }
    var activeBarVisibleForTests: Bool { !activeBar.isHidden && shown > 0 }
    var dividerCountForTests: Int { dividers.filter { !$0.isHidden }.count }

    @objc private func tapped(_ b: UIButton) { onPick?(b.tag) }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollBox.frame = bounds.insetBy(dx: 0, dy: 2)
        scroll.frame = scrollBox.bounds
        let rowH: CGFloat = bounds.height < 135 ? 32 : 38
        let insetX: CGFloat = 3.5
        let btnW = max(0, bounds.width - insetX * 2)
        let neededDivs = max(0, shown - 2)
        while dividers.count < neededDivs {
            let d = CALayer()
            d.backgroundColor = Theme.candidateDivider.resolvedColor(with: traitCollection).cgColor
            scroll.layer.addSublayer(d)
            dividers.append(d)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, b) in buttons.enumerated() {
            let y = 2 + CGFloat(i) * rowH
            b.frame = CGRect(x: insetX, y: y, width: btnW, height: rowH - 2)
        }
        if shown > 0, let first = buttons.first {
            activeBar.isHidden = false
            activeBar.backgroundColor = Theme.selection
            let barH: CGFloat = min(14, max(10, first.frame.height - 14))
            activeBar.frame = CGRect(x: first.frame.minX + 5, y: first.frame.midY - barH / 2, width: 2.5, height: barH)
            scroll.bringSubviewToFront(activeBar)
        } else {
            activeBar.isHidden = true
        }
        let divW = max(0, bounds.width - 16)
        for (di, d) in dividers.enumerated() {
            let visible = di < neededDivs && bounds.width > 20
            d.isHidden = !visible
            if visible {
                let slotIdx = di + 2
                d.frame = CGRect(x: 8, y: 1 + CGFloat(slotIdx) * rowH, width: divW, height: 0.5)
            }
        }
        CATransaction.commit()
        scroll.contentSize = CGSize(width: bounds.width, height: 4 + CGFloat(shown) * rowH)
        updateBottomFade()
    }
}
