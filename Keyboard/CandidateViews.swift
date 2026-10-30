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

    private let preedit = UILabel()
    /// After a corrected word went in: "↩ nihap" at the start of the strip puts the keys back as typed (the same
    /// as pressing delete right away). After a swipe that cleared the composition: the keys it cleared.
    private let undoChip = UIButton(type: .system)
    var onUndo: (() -> Void)?
    private var undoText: String?
    private var longPressTimer: Timer?
    /// The candidates, in a row that scrolls; inside a box whose mask fades the edges where more candidates are.
    private let stripBox = UIView()
    private let strip = CandidateStrip()
    private let fade = CAGradientLayer()
    private let expandButton = UIButton(type: .system)
    let mosto = MostoView()
    private var labels: [UILabel] = []
    private var pool: [UILabel] = []
    /// What each pooled label shows now (so a label is only redrawn when it changes).
    private var poolKeys: [String] = []
    private var isPrediction = false
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
    var showsMosto = false { didSet { update(preedit: preedit.text ?? "", candidates: candidates, prediction: isPrediction) } }
    private var mostoWanted = false
    private var mostoTimer: Timer?
    /// Pinyin above the candidates (when it is not written into the text field).
    var showsPreedit = false { didSet { setNeedsLayout() } }

    static var font: UIFont { Theme.font(20, .regular) }
    static var fixFont: UIFont { Theme.font(10.5, .semibold) }
    /// Below this height (landscape) a caption sits beside its candidate, not under it.
    static let twoLineHeight: CGFloat = 44

    /// Under an auto-corrected first choice, what was corrected: the keys as typed → the spelling read (hap → hao),
    /// at most two syllables, else how many; English: the word as typed, struck through. Under the literal reading
    /// that follows it, "原键" (the keys exactly as pressed).
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
        backgroundColor = Theme.touchable   // never fully clear: see Theme.touchable
        preedit.font = Theme.font(14, .medium)
        preedit.textColor = Theme.secondaryText
        addSubview(preedit)
        // the row scrolls with the system's own inertia and bounce; no scroll bar; a finger that lands highlights
        // at once, and the scrolling takes the touch over (no selection) once it starts
        strip.owner = self
        strip.delegate = self
        strip.showsHorizontalScrollIndicator = false
        strip.showsVerticalScrollIndicator = false
        strip.alwaysBounceHorizontal = true
        strip.alwaysBounceVertical = false
        strip.decelerationRate = .normal
        strip.delaysContentTouches = false
        strip.canCancelContentTouches = true
        strip.scrollsToTop = false
        strip.contentInsetAdjustmentBehavior = .never
        strip.backgroundColor = .clear
        strip.panGestureRecognizer.addTarget(self, action: #selector(stripPanned(_:)))
        stripBox.backgroundColor = .clear
        stripBox.addSubview(strip)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        addSubview(stripBox)
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
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

    @objc private func expandTapped() { onExpand?() }

    /// The style changed (Mosto / 简洁): the colours set once at creation follow.
    func themeChanged() {
        expandButton.tintColor = Theme.secondaryText
        preedit.textColor = Theme.secondaryText
        preedit.font = Theme.font(14, .medium)
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

    var undoTextForTests: String? { undoText }
    func undoTapForTests() { onUndo?() }

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

    /// A swipe left off delete is armed: the candidates fade to show they are about to go (no animation: it follows
    /// the finger).
    func setClearPreview(_ on: Bool) {
        let a: CGFloat = on ? 0.35 : 1
        stripBox.alpha = a
        expandButton.alpha = a
    }
    var clearPreviewForTests: Bool { stripBox.alpha < 1 }

    // MARK: VoiceOver: each laid-out candidate is a button (the strip draws plain labels and reads raw touches)

    private final class CandidateElement: UIAccessibilityElement {
        var activate: (() -> Void)?
        override func accessibilityActivate() -> Bool { activate?(); return true }
    }

    override var accessibilityElements: [Any]? {
        get {
            var out: [Any] = []
            if !mosto.isHidden { out.append(mosto) }
            if !undoChip.isHidden { out.append(undoChip) }
            for (i, l) in labels.enumerated() where !l.isHidden {
                let e = CandidateElement(accessibilityContainer: self)
                e.accessibilityLabel = i < candidates.count ? candidates[i].text : l.text
                if i < candidates.count, !isPrediction, let cap = Self.caption(for: candidates[i]) {
                    e.accessibilityValue = cap.string == "已纠错" ? "已纠错"
                        : "已纠错：" + candidates[i].fixes.map { "\($0.typed) 改为 \($0.meant)" }.joined(separator: "，")
                }
                e.accessibilityTraits = .button
                if i == 0, !isPrediction { e.accessibilityHint = "首选，空格上屏" }
                e.accessibilityFrameInContainerSpace = strip.convert(l.frame, to: self)
                e.activate = { [weak self] in self?.onSelect?(i) }
                out.append(e)
            }
            if !expandButton.isHidden {
                expandButton.accessibilityLabel = "全部候选"
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

    /// `prediction`: the row shows next-word suggestions (联想) rather than candidates for typed keys.
    func update(preedit text: String, candidates: [Candidate], prediction: Bool = false) {
        preedit.text = text
        // another list (a new key, a commit): the row starts from the beginning again; the same list (the same keys
        // decoded once more) leaves it where the finger put it
        let changed = prediction != isPrediction || candidates.count != self.candidates.count
            || !zip(candidates, self.candidates).allSatisfy { $0.text == $1.text }
        self.candidates = candidates
        isPrediction = prediction
        // widths are measured again from the cache (captions can change with the same words)
        widths = []
        if candidates.isEmpty || widthCache.count > 1500 { widthCache = [:] }
        if changed, strip.contentOffset != .zero {
            inUpdate = true
            strip.setContentOffset(.zero, animated: false)
            inUpdate = false
        }
        let busy = !candidates.isEmpty
        setMosto(!busy && !typing && showsMosto && undoText == nil)
        preedit.isHidden = !busy || prediction || !showsPreedit
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Mosto steps aside the moment typing starts (the strip is for candidates) and comes back only when the
    /// keyboard has been idle a moment, fading in rather than popping up — never flickering between words.
    /// Keys are being composed (the candidates may not have arrived yet): Mosto stays out of the way.
    var typing = false {
        didSet { if typing != oldValue { setMosto(!typing && candidates.isEmpty && showsMosto && undoText == nil) } }
    }

    /// Mosto is (about to be) shown or put away — his night light follows him.
    var onMostoShown: ((Bool) -> Void)?

    private func setMosto(_ on: Bool) {
        // put away even when he was never asked for (a new strip starts with him hidden, 简洁 never shows him)
        if !on, !mostoWanted { mosto.isHidden = true; return }
        guard on != mostoWanted else { return }
        mostoWanted = on
        onMostoShown?(on)
        mostoTimer?.invalidate(); mostoTimer = nil
        guard on else { mosto.layer.removeAllAnimations(); mosto.isHidden = true; return }
        // not on screen yet (the keyboard is being set up): simply there
        if window == nil { mosto.alpha = 1; mosto.transform = .identity; mosto.isHidden = false; return }
        let reduce = UIAccessibility.isReduceMotionEnabled
        mostoTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self, self.mostoWanted else { return }
            self.mosto.alpha = 0
            if !reduce { self.mosto.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }
            self.mosto.isHidden = false
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.mosto.alpha = 1
                self.mosto.transform = .identity
            } completion: { done in
                if done, self.mostoWanted { self.mosto.greet() }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let preH: CGFloat = showsPreedit ? min(20, h * 0.3) : 0
        preedit.frame = CGRect(x: 10, y: 2, width: bounds.width - 20, height: preH)
        // high in the strip, clear of the q key below (the keys' reach band gives way to him: see reservedTop)
        let ms = min(h - 8, 44)
        mosto.frame = CGRect(x: 8, y: 1, width: ms, height: ms)
        let rowY = preH
        let rowH = h - preH
        expandButton.frame = CGRect(x: bounds.width - 44, y: rowY, width: 44, height: rowH)
        // the row starts where the first candidate always started (after the chip, if there is one) and ends at ⌄
        var lead: CGFloat = 6
        if !undoChip.isHidden {
            let sz = undoChip.sizeThatFits(CGSize(width: 200, height: rowH))
            undoChip.frame = CGRect(x: 8, y: rowY + (rowH - sz.height) / 2, width: sz.width, height: sz.height)
            lead = undoChip.frame.maxX + 6
        }
        let box = CGRect(x: lead, y: rowY, width: max(0, bounds.width - 44 - lead), height: rowH)
        if stripBox.frame != box { stripBox.frame = box }
        let inner = CGRect(origin: .zero, size: box.size)
        if strip.frame != inner { strip.frame = inner }
        // nothing to show: the strip takes no touches (they fall to the strip's own view, as before it scrolled)
        stripBox.isHidden = candidates.isEmpty
        layoutCandidates()
    }

    /// The caption a candidate carries: what the first choice corrected, or "原键" on the literal reading after it.
    private func captionFor(_ i: Int) -> NSAttributedString? {
        guard !isPrediction, i < candidates.count, i <= 1 else { return nil }
        let c = candidates[i]
        if i == 0 { return Self.caption(for: c) }
        // the keys as typed first, a correction second: the second says what it changes (kw→ke)
        if !candidates[0].corrected, c.corrected, !c.isEnglish { return Self.caption(for: c) }
        guard candidates[0].corrected, !c.corrected, !c.isEnglish, c.tapCount == candidates[0].tapCount else { return nil }
        return NSAttributedString(string: "原键", attributes: [.font: Self.fixFont, .foregroundColor: Theme.secondaryText])
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

    /// Width of candidate `i` (cached by text and caption): at least a 44 pt target, as Apple's guidelines ask.
    private func measure(_ i: Int, inline: Bool) -> CGFloat {
        let c = candidates[i]
        let cap = captionFor(i)
        let key = (inline ? "1" : "0") + "\u{1}" + c.text + "\u{1}" + (cap?.string ?? "")
        if let w = widthCache[key] { return w }
        let textW = (c.text as NSString).size(withAttributes: [.font: Self.font]).width
        let w: CGFloat
        if let cap {
            w = inline ? max(44, ceil(textW + 4 + cap.size().width) + 22) : max(44, ceil(max(textW, cap.size().width)) + 22)
        } else {
            w = max(44, ceil(textW) + 22)
        }
        widthCache[key] = w
        return w
    }

    /// Lay the row out from its start to two screens past what is shown (the rest only as the finger gets there:
    /// a single syllable can have hundreds of candidates). Labels are pooled and reused: only text and frames change.
    private func layoutCandidates() {
        let viewW = strip.bounds.width
        let rowH = strip.bounds.height
        let inline = bounds.height < Self.twoLineHeight
        let need = strip.contentOffset.x + max(viewW, 1) * 2
        let pressed = gesture.highlighted
        var x: CGFloat = 0
        var n = 0
        while n < candidates.count && (x < need || n == 0) {
            let w: CGFloat
            if n < widths.count { w = widths[n] } else { w = measure(n, inline: inline); widths.append(w) }
            if pool.count <= n {
                let l = UILabel()
                l.font = Self.font
                l.textAlignment = .center
                l.lineBreakMode = .byTruncatingTail
                l.layer.cornerRadius = 8
                l.clipsToBounds = true
                strip.addSubview(l)
                pool.append(l)
                poolKeys.append("")
            }
            let l = pool[n]
            l.isHidden = false
            let frame = CGRect(x: x, y: 3, width: w, height: rowH - 6)
            if l.frame != frame { l.frame = frame }
            let c = candidates[n]
            let cap = captionFor(n)
            let key = (inline ? "1" : "0") + "\u{1}" + c.text + "\u{1}" + (cap?.string ?? "")
            if poolKeys[n] != key {
                poolKeys[n] = key
                l.textColor = Theme.candidateText
                if let cap {
                    // the word, and with it what the correction changed (or that this one is the keys as typed)
                    l.numberOfLines = inline ? 1 : 2
                    l.attributedText = labelText(c, caption: cap, inline: inline)
                } else {
                    l.numberOfLines = 1
                    l.attributedText = nil
                    l.text = c.text
                }
            }
            // the corrected first choice sits on a soft tint of the correction colour (what space will type)
            let fixed = n == 0 && !isPrediction && c.corrected
            l.backgroundColor = n == pressed ? Theme.functionKey : (fixed ? Theme.correctedTint : .clear)
            x += w
            n += 1
        }
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
        expandButton.isHidden = !(total > viewW + 0.5)
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
        if g.state == .began { stripScrollBegan() }
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
        guard q.y >= -8, q.x >= strip.bounds.minX, q.x < strip.bounds.maxX else { return nil }
        return labels.firstIndex { $0.frame.minX <= q.x && q.x < $0.frame.maxX }
    }

    func stripTouch(_ phase: TouchSample.Phase, at p: CGPoint, time: CFTimeInterval) {
        switch phase {
        case .began:
            let idx = candidateIndex(at: p)
            let text = idx.flatMap { $0 < candidates.count ? candidates[$0].text : nil }
            // a finger that lands while the row is still gliding only stops it
            let gliding = strip.glidingAtDown || strip.isDecelerating || benchGliding
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
            if gesture.move(to: p) {
                longPressTimer?.invalidate()
                setNeedsLayout()
            }
        case .ended:
            longPressTimer?.invalidate()
            let idx = candidateIndex(at: p)
            let current = idx.flatMap { $0 < candidates.count ? candidates[$0].text : nil }
            let chosen = gesture.end(index: idx, currentText: current)
            setNeedsLayout()
            if let chosen { onSelect?(chosen) }
        case .cancelled:
            longPressTimer?.invalidate()
            gesture.cancel()
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
        b.frame.origin = CGPoint(x: 10, y: (bounds.height - b.bounds.height) / 2 + 4)
        addSubview(b)
        forgetButton = b
        Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self, weak b] _ in
            if let b, self?.forgetButton === b { self?.dismissForget() }
        }
    }

    func dismissForget() {
        forgetButton?.removeFromSuperview()
        forgetButton = nil
    }
}

/// Full candidate list as a wrapping grid (vertical scroll only).
final class CandidateGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelect: ((Int) -> Void)?
    var onClose: (() -> Void)?
    var onDelete: (() -> Void)?

    private var candidates: [Candidate] = []
    private let collection: UICollectionView
    private let closeButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    final class Cell: UICollectionViewCell {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = CandidateBarView.font
            label.textAlignment = .center
            label.textColor = Theme.candidateText
            contentView.addSubview(label)
            // as the system keyboard's expanded candidates: plain text on the glass, a soft highlight when pressed
            contentView.backgroundColor = .clear
            contentView.layer.cornerRadius = 8
            contentView.layer.cornerCurve = .continuous
            isAccessibilityElement = true
            accessibilityTraits = .button
        }
        required init?(coder: NSCoder) { fatalError() }
        override var accessibilityLabel: String? { get { label.text } set { } }
        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = contentView.bounds.insetBy(dx: 4, dy: 0)
        }
        override var isHighlighted: Bool {
            didSet { contentView.backgroundColor = isHighlighted ? Theme.functionKey : .clear }
        }
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = Theme.touchable   // on the system glass, like the keys (never fully clear: see Theme.touchable)
        collection.backgroundColor = .clear
        collection.contentInsetAdjustmentBehavior = .never
        collection.alwaysBounceHorizontal = false
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(Cell.self, forCellWithReuseIdentifier: "c")
        addSubview(collection)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        closeButton.setImage(UIImage(systemName: "chevron.up", withConfiguration: cfg), for: .normal)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
        for b in [closeButton, deleteButton] {
            b.tintColor = Theme.functionText
            b.backgroundColor = Theme.functionKey
            b.layer.cornerRadius = Metrics.cornerRadius
            b.layer.cornerCurve = .continuous
            // the keyboard's vinyl cap: a darker lip under the face (a hard, unblurred shadow)
            b.layer.shadowOpacity = 1
            b.layer.shadowRadius = 0
            b.layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
            b.layer.shadowColor = Theme.functionLip.resolvedColor(with: traitCollection).cgColor
            addSubview(b)
        }
        closeButton.accessibilityLabel = "收起候选"
        deleteButton.accessibilityLabel = "删除"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        for b in [closeButton, deleteButton] { b.layer.shadowColor = Theme.functionLip.resolvedColor(with: traitCollection).cgColor }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func closeTapped() { onClose?() }
    @objc private func deleteTapped() { onDelete?() }

    func show(_ candidates: [Candidate]) {
        self.candidates = candidates
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 56
        collection.frame = CGRect(x: 0, y: 0, width: bounds.width - side, height: bounds.height)
        let bh = (bounds.height - 18) / 2
        closeButton.frame = CGRect(x: bounds.width - side + 4, y: 6, width: side - 10, height: bh)
        deleteButton.frame = CGRect(x: bounds.width - side + 4, y: 12 + bh, width: side - 10, height: bh)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { candidates.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "c", for: indexPath) as! Cell
        cell.label.text = candidates[indexPath.item].text
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout l: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let maxW = collectionView.bounds.width - 12
        let w = ceil((candidates[indexPath.item].text as NSString).size(withAttributes: [.font: CandidateBarView.font]).width) + 24
        return CGSize(width: min(maxW, max(48, w)), height: 44)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(indexPath.item)
    }
}

/// In-keyboard settings, laid out like iOS Settings: a fixed header (Mosto, title, 完成) over grouped, rounded
/// sections that scroll vertically. Every change applies at once (no App Group or full access needed).
final class SettingsPanelView: UIView {
    var onClose: (() -> Void)?
    var onChange: (() -> Void)?
    var onResetLearning: (() -> Void)?

    private let header = UIView()
    private let statusLabel = UILabel()
    private let mostoImage = UIImageView()
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    private let schemeControl = UISegmentedControl(items: ["小鹤双拼", "全拼"])
    private let layoutControl = UISegmentedControl(items: ["全键盘", "九宫格"])
    private let numberControl = UISegmentedControl(items: ["完整页", "九宫格"])
    private let englishSwitch = UISwitch()
    private let guideSwitch = UISwitch()
    private let correctionSwitch = UISwitch()
    private let feedbackSwitch = UISwitch()
    private let soundSwitch = UISwitch()
    private let appearance = UISegmentedControl(items: ["自动", "日光", "夜灯"])
    /// 风格: Mosto (the vinyl toy keys, Mosto in the strip) or 简洁 (no theme: plain keys in the system's greys).
    private let styleControl = UISegmentedControl(items: ["Mosto", "简洁"])
    private let learnedLabel = UILabel()
    private let diagLabel = UILabel()
    private let accessLabel = UILabel()
    private let note = UILabel()
    private var groups: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.touchable   // the system glass shows through (never fully clear: see Theme.touchable)
        // Mosto's colours on every control: violet by day, crown gold at night
        tintColor = Theme.selection
        for sw in [englishSwitch, guideSwitch, correctionSwitch, feedbackSwitch, soundSwitch] { sw.onTintColor = Theme.selection }
        // the three input choices share one width, so their left and right edges line up down the card
        for sc in [schemeControl, layoutControl, numberControl] {
            sc.translatesAutoresizingMaskIntoConstraints = false
            sc.widthAnchor.constraint(equalToConstant: 168).isActive = true
            for i in 0..<sc.numberOfSegments { sc.setWidth(84, forSegmentAt: i) }
        }
        for sc in [schemeControl, layoutControl, numberControl, appearance, styleControl] {
            sc.selectedSegmentTintColor = Theme.selection
            sc.setTitleTextAttributes([.foregroundColor: Theme.selectionText, .font: Theme.font(14, .semibold)], for: .selected)
            sc.setTitleTextAttributes([.foregroundColor: Theme.keyText, .font: Theme.font(14, .medium)], for: .normal)
        }

        // Header: Mosto (day or night), the name, 完成 — fixed above the scrolling list
        mostoImage.contentMode = .scaleAspectFit
        mostoImage.image = UIImage(named: "mosto_day", in: Bundle(for: SettingsPanelView.self), with: nil)
        let title = UILabel()
        title.text = "Mosto键盘"
        title.font = Theme.font(17, .bold)
        title.textColor = Theme.keyText
        title.tag = Self.tagPrimary
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.tag = Self.tagSecondary
        let titles = UIStackView(arrangedSubviews: [title, statusLabel])
        titles.axis = .vertical
        titles.spacing = 1
        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.titleLabel?.font = Theme.font(17, .bold)
        done.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let h = UIStackView(arrangedSubviews: [mostoImage, titles, UIView(), done])
        h.alignment = .center
        h.spacing = 8
        mostoImage.widthAnchor.constraint(equalToConstant: 40).isActive = true
        mostoImage.heightAnchor.constraint(equalToConstant: 40).isActive = true
        header.addSubview(h)
        h.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            h.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            h.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        addSubview(header)

        stack.axis = .vertical
        stack.spacing = 6
        scroll.addSubview(stack)
        scroll.alwaysBounceHorizontal = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never   // no safe-area inset: the list starts under the header
        addSubview(scroll)

        section("输入", rows: [
            row("输入方案", schemeControl),
            row("中文键盘", layoutControl),
            row("123 键", numberControl),
            row("中英混输", englishSwitch),
        ], footer: "中文键盘：九宫格每个键代表它上面的几个字母，两种方案都能用（全拼更准），“分词”切开音节。\n123 键：打开完整的数字符号页，或九宫格数字键盘；未设置时跟随中文键盘。\n中英混输：打 ok、ios 直接出 OK、iOS。\n所有设置会一直记住，更新版本不会重置。")
        section("小鹤双拼", rows: [
            row("键位提示", guideSwitch),
        ], footer: "学习用：小鹤双拼方案下，字母键上显示它代表的声母与韵母（zh、ch、sh 在 V、I、U）。记熟后可关掉。全拼方案下不显示。完整键位表与说明在 Mosto键盘 App 里。")
        section("自动纠错", rows: [
            row("按触点位置纠错", correctionSwitch),
        ], footer: "首选浅色底 = 已纠错，下方小字是改了哪里（hap→hao）；“原键”是按原样读的结果。上屏后点候选栏左侧 ↩ 或立刻按删除可撤回。英文模式同样按触点纠错：teh → the、dont → don't、im → I'm，空格时替换，删除可撤回。")
        section("键盘", rows: [
            row("按键震动", feedbackSwitch),
            row("按键音", soundSwitch),
            accessLabel,
        ], footer: "震动与按键音在按下的一瞬间发出（与系统键盘一样）；按键音跟随静音开关。")
        section("外观", rows: [row("风格", styleControl), row("光线", appearance)], footer: "风格：Mosto 是软胶按键与 Mosto 本人；简洁是没有主题的素净按键，白天清爽、夜里低亮。光线自动：跟随系统的浅色 / 深色模式。Mosto 不打字时待在候选栏左边：轻点他选颜文字，轻点两下切换日光 / 夜灯。日光下睁大眼睛、偶尔眨眼；夜灯下深紫底色，尾巴尖亮起金光。按键是他的软胶：空格上是他的翅膀，中 / 英 键戴着他的歪王冠，换行键是王冠的金色。")

        accessLabel.text = "按键震动与按键音需要允许完全访问：设置 › 通用 › 键盘 › 键盘 › Mosto键盘。"
        accessLabel.font = .systemFont(ofSize: 13)
        accessLabel.textColor = Theme.secondaryText
        accessLabel.tag = Self.tagSecondary
        accessLabel.numberOfLines = 0
        accessLabel.isHidden = true
        setFeedbackAvailable(true)
        learnedLabel.font = .systemFont(ofSize: 15)
        learnedLabel.textColor = Theme.secondaryText
        learnedLabel.tag = Self.tagSecondary
        learnedLabel.numberOfLines = 0
        let reset = UIButton(type: .system)
        reset.setTitle("清空已学习的词语与触点习惯", for: .normal)
        reset.setTitleColor(.systemRed, for: .normal)
        reset.titleLabel?.font = .systemFont(ofSize: 15)
        reset.contentHorizontalAlignment = .leading
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        section("学习", rows: [learnedLabel, reset], footer: nil)
        diagLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        diagLabel.textColor = Theme.secondaryText
        diagLabel.tag = Self.tagSecondary
        diagLabel.numberOfLines = 0
        // 诊断: for testers (TestFlight) only — nobody else needs to read key timings
        if Self.isTestFlight { section("诊断", rows: [diagLabel], footer: "打一段字后打开这里：“丢弃”是被系统取消、没能输入的按键；“按键响应”是每次按键在主线程上花的时间（字母按下即上屏），“候选出现”是按键到候选显示出来的时间（在后台线程解码）。") }

        note.numberOfLines = 0
        note.font = .systemFont(ofSize: 12)
        note.textColor = Theme.secondaryText
        note.tag = Self.tagSecondary
        stack.addArrangedSubview(inset(note))

        for c in [schemeControl, layoutControl, appearance, styleControl] {
            c.addTarget(self, action: #selector(changed), for: .valueChanged)
            c.setContentHuggingPriority(.required, for: .horizontal)
        }
        numberControl.addTarget(self, action: #selector(numberChanged), for: .valueChanged)
        numberControl.setContentHuggingPriority(.required, for: .horizontal)
        for sw in [englishSwitch, guideSwitch, correctionSwitch, feedbackSwitch, soundSwitch] {
            sw.addTarget(self, action: #selector(changed), for: .valueChanged)
        }
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

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

    /// One iOS-style group: a small grey caption, rounded rows separated by hairlines, an optional footnote.
    private func section(_ title: String, rows: [UIView], footer: String?) {
        let cap = UILabel()
        cap.text = title
        cap.font = .systemFont(ofSize: 13)
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
                r.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
                r.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -7),
                cell.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
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
            f.font = .systemFont(ofSize: 12)
            f.textColor = Theme.secondaryText
            f.tag = Self.tagSecondary
            stack.setCustomSpacing(4, after: wrap)
            let fw = inset(f)
            stack.addArrangedSubview(fw)
            stack.setCustomSpacing(14, after: fw)
        } else {
            stack.setCustomSpacing(14, after: wrap)
        }
    }

    private func row(_ text: String, _ control: UIView) -> UIView {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 16)
        l.textColor = Theme.keyText
        l.tag = Self.tagPrimary
        l.numberOfLines = 0
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        let s = UIStackView(arrangedSubviews: [l, UIView(), control])
        s.alignment = .center
        s.spacing = 10
        return s
    }

    /// Mosto in the header shows the light the keyboard is in.
    /// A TestFlight build (its receipt is the sandbox one).
    static let isTestFlight: Bool = {
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { return true }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private static let tagPrimary = 9_701, tagSecondary = 9_702, tagGroup = 9_703, tagLine = 9_704

    /// The style changed (Mosto / 简洁): every colour set at creation follows; no Mosto in 简洁.
    func themeChanged() {
        tintColor = Theme.selection
        for sw in [englishSwitch, guideSwitch, correctionSwitch, feedbackSwitch, soundSwitch] { sw.onTintColor = Theme.selection }
        for sc in [schemeControl, layoutControl, numberControl, appearance, styleControl] {
            sc.selectedSegmentTintColor = Theme.selection
            sc.setTitleTextAttributes([.foregroundColor: Theme.selectionText, .font: Theme.font(14, .semibold)], for: .selected)
            sc.setTitleTextAttributes([.foregroundColor: Theme.keyText, .font: Theme.font(14, .medium)], for: .normal)
        }
        mostoImage.isHidden = Theme.plain
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
        updateStatus()
    }

    func setNight(_ night: Bool) {
        mostoImage.image = UIImage(named: night ? "mosto_night" : "mosto_day", in: Bundle(for: SettingsPanelView.self), with: nil)
        updateStatus(night: night)
    }

    /// The line under the name: the light, the scheme and the layout in use, at a glance.
    private func updateStatus(night: Bool? = nil) {
        let s = KeyboardSettings.shared
        let nightName = s.style == 1 ? "夜光" : "夜灯"
        let light = night.map { $0 ? nightName : "日光" } ?? (["自动", "日光", nightName][s.appearance])
        statusLabel.text = "\(s.style == 1 ? "简洁" : "Mosto") · \(light) · \(s.scheme == 0 ? "小鹤双拼" : "全拼") · \(s.pinyinGrid ? "九宫格" : "全键盘")"
    }

    func load() {
        let s = KeyboardSettings.shared
        updateStatus()
        schemeControl.selectedSegmentIndex = s.scheme
        layoutControl.selectedSegmentIndex = s.pinyinGrid ? 1 : 0
        numberControl.selectedSegmentIndex = s.numberPad ? 1 : 0
        englishSwitch.isOn = s.english
        guideSwitch.isOn = s.xiaoheGuide
        correctionSwitch.isOn = s.autocorrect
        feedbackSwitch.isOn = s.feedback
        soundSwitch.isOn = s.keySound
        appearance.selectedSegmentIndex = s.appearance
        styleControl.selectedSegmentIndex = s.style
    }

    func setNote(_ text: String) { note.text = text }
    /// Without 允许完全访问 the system plays no haptics or click sounds for a keyboard: the two switches show it
    /// (greyed, the choice kept) and say what they need.
    func setFeedbackAvailable(_ ok: Bool) {
        feedbackSwitch.isEnabled = ok
        soundSwitch.isEnabled = ok
        accessLabel.isHidden = ok
        // the line it sits on, and the hairline above it, only while there is something to say
        if let cell = accessLabel.superview, let list = cell.superview as? UIStackView,
           let i = list.arrangedSubviews.firstIndex(of: cell) {
            cell.isHidden = ok
            if i > 0 { list.arrangedSubviews[i - 1].isHidden = ok }
        }
    }
    func setLearned(_ text: String) { learnedLabel.text = text }
    func setDiagnostics(_ text: String) { diagLabel.text = text }
    /// Snapshot support: the list scrolled so the 键盘 section (震动、按键音 and, without 允许完全访问, why) starts at
    /// the top, as far as the list goes.
    func demoScrollToFeedback() {
        layoutIfNeeded()
        stack.layoutIfNeeded()
        guard let group = groups.first(where: { feedbackSwitch.isDescendant(of: $0) }), let wrap = group.superview,
              let i = stack.arrangedSubviews.firstIndex(of: wrap) else { return }
        // from its caption (the line above the group)
        let top = i > 0 ? stack.arrangedSubviews[i - 1].frame.minY : wrap.frame.minY
        let y = stack.frame.minY + top - 6
        let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
        scroll.contentOffset = CGPoint(x: 0, y: min(max(0, y), maxY))
    }
    var diagnosticsText: String { diagLabel.text ?? "" }

    @objc private func changed() {
        let s = KeyboardSettings.shared
        s.scheme = schemeControl.selectedSegmentIndex
        s.pinyinGrid = layoutControl.selectedSegmentIndex == 1
        s.english = englishSwitch.isOn
        s.xiaoheGuide = guideSwitch.isOn
        s.autocorrect = correctionSwitch.isOn
        s.feedback = feedbackSwitch.isOn
        s.keySound = soundSwitch.isOn
        s.appearance = appearance.selectedSegmentIndex
        s.style = styleControl.selectedSegmentIndex
        // until chosen here, the number pad follows the Chinese layout (shown at once when that changes)
        numberControl.selectedSegmentIndex = s.numberPad ? 1 : 0
        updateStatus()
        onChange?()
    }

    @objc private func numberChanged() {
        KeyboardSettings.shared.numberPad = numberControl.selectedSegmentIndex == 1
        onChange?()
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func resetTapped() { onResetLearning?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 48)
        scroll.frame = CGRect(x: 0, y: 48, width: bounds.width, height: bounds.height - 48)
        let w = bounds.width
        let size = stack.systemLayoutSizeFitting(CGSize(width: w, height: 0),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: 0, y: 4, width: w, height: size.height)
        scroll.contentSize = CGSize(width: w, height: size.height + 16)
    }
}

final class KeyboardSettings {
    static let shared = KeyboardSettings()
    private let d = UserDefaults.standard

    /// Every choice is stored the moment it is made and only ever changed by the user: an update never resets it
    /// (the keyboard's defaults live in its own container, which iOS keeps across updates).
    /// A first install starts in 全拼. Earlier versions started in 小鹤双拼 without storing it: a keyboard that has
    /// been used before (it stored touch habits or any setting) keeps 小鹤双拼, written down now so it stays.
    private init() {
        if d.object(forKey: "scheme") == nil {
            let usedBefore = ["offsetX", "keyOffsets", "appearance", "autocorrect", "english", "pinyinGrid", "feedback", "keySound"]
                .contains { d.object(forKey: $0) != nil }
            d.set(usedBefore ? 0 : 1, forKey: "scheme")
        }
    }

    /// 0 小鹤双拼, 1 全拼 (PinyinScheme raw value). First install: 全拼 (see init).
    var scheme: Int {
        get { d.object(forKey: "scheme") as? Int ?? 1 }
        set { d.set(newValue, forKey: "scheme") }
    }
    var autocorrect: Bool {
        get { d.object(forKey: "autocorrect") as? Bool ?? true }
        set { d.set(newValue, forKey: "autocorrect") }
    }
    /// 小鹤键位提示 (learning mode): letter keys show the initials and finals they stand for.
    var xiaoheGuide: Bool {
        get { d.object(forKey: "xiaoheGuide") as? Bool ?? false }
        set { d.set(newValue, forKey: "xiaoheGuide") }
    }
    /// 中英混输: English words offered among the Chinese candidates.
    var english: Bool {
        get { d.object(forKey: "english") as? Bool ?? true }
        set { d.set(newValue, forKey: "english") }
    }
    /// Chinese typed on the 九宫格 pinyin keypad (on) or the full keyboard (off).
    var pinyinGrid: Bool {
        get { d.object(forKey: "pinyinGrid") as? Bool ?? false }
        set { d.set(newValue, forKey: "pinyinGrid") }
    }
    /// 123 opens the 九宫格 number pad (on) or the full numbers-and-symbols page (off). Until chosen in settings it
    /// follows the Chinese layout: typing on the 九宫格 means numbers on the keypad too.
    var numberPad: Bool {
        get { d.object(forKey: "numberPad") as? Bool ?? pinyinGrid }
        set { d.set(newValue, forKey: "numberPad") }
    }
    /// 0 自动 (follows the system's light / dark mode), 1 日光, 2 夜灯. (The old 3 "晚上" reads as 自动.)
    /// 0 Mosto, 1 简洁 (无主题).
    var style: Int {
        get { d.object(forKey: "style") as? Int ?? 0 }
        set { d.set(newValue, forKey: "style") }
    }
    var appearance: Int {
        get { min(d.object(forKey: "appearance") as? Int ?? 0, 3) % 3 }
        set { d.set(newValue, forKey: "appearance") }
    }
    /// Haptic tap on key down (the key kept its old name: it used to switch sound and haptics together).
    var feedback: Bool {
        get { d.object(forKey: "feedback") as? Bool ?? true }
        set { d.set(newValue, forKey: "feedback") }
    }
    /// The system keyboard's click sounds on key down (follow the ring / silent switch). Until set on its own it
    /// follows the old combined switch.
    var keySound: Bool {
        get { d.object(forKey: "keySound") as? Bool ?? feedback }
        set { d.set(newValue, forKey: "keySound") }
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
        scroll.contentInsetAdjustmentBehavior = .never
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
