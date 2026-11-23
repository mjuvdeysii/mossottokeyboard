import UIKit
import CoreText

final class KeyView: UIView {
    private(set) var spec: KeySpec
    private(set) var borders = false
    private let label = UILabel()
    private var hintLabel: UILabel?
    private var hintLit = false
    /// 小鹤键位提示: lazily created only when guide is enabled.
    private var guideLabel: UILabel?
    private let icon = UIImageView()

    /// Mosto studio micro-craft: hardware status indicator on 中/英 and Shift, homing bar on Space.
    private var statusDot: CALayer?
    private var spaceNotch: CALayer?

    var pressed = false {
        didSet {
            if !pressed { setHintLit(false) }
            if pressed != oldValue { applyPressState() }
        }
    }
    private var hasApplied = false
    private(set) var applyRunsForTests = 0
    /// While the space bar drives the cursor the other caps go blank, as in the iOS trackpad mode.
    var blanked = false {
        didSet {
            guard blanked != oldValue else { return }
            UIView.animate(withDuration: 0.15) {
                let a: CGFloat = self.blanked ? 0 : 1
                self.label.alpha = a; self.hintLabel?.alpha = a; self.icon.alpha = a; self.guideLabel?.alpha = a
            }
            statusDot?.isHidden = blanked || Theme.plain || !(spec.action == .toggleLanguage || spec.action == .shift)
            spaceNotch?.isHidden = blanked || Theme.plain || spec.action != .space || bounds.width <= 120
        }
    }

    private var currentStyle: KeyStyle = .normal
    private var restBg: CGColor = UIColor.white.cgColor
    private var pressedBg: CGColor = UIColor.lightGray.cgColor
    private var restFg: UIColor = Theme.keyText
    private var pressedFg: UIColor = Theme.keyText
    private static var symbolCache: [String: UIImage] = [:]
    private static let opticalPunctuation: Set<String> = ["，", "。", "？", "！", "、", "；", "：", "（", "）", "「", "」", "【", "】", "《", "》"]
    private static let lowBaselinePunctuation: Set<String> = ["。", "，", "、", "．"]
    private static var opticalOffsetCache: [String: CGPoint] = [:]

    /// Measures true 2D glyph ink bounds vs typographic advance & ascent/descent so asymmetric fullwidth CJK
    /// punctuation optically centers both horizontally and vertically inside keycaps and previews.
    static func opticalOffset(for text: String, font: UIFont) -> CGPoint {
        guard text.count == 1, opticalPunctuation.contains(text) else { return .zero }
        let key = "\(text)|\(Int((font.pointSize * 10).rounded()))"
        if let cached = opticalOffsetCache[key] { return cached }
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let adv = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let img = CTLineGetImageBounds(line, nil)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if adv > 0, !img.isNull, img.width > 0 {
            dx = min(4.0, max(-4.0, adv * 0.5 - (img.minX + img.width * 0.5)))
        }
        if lowBaselinePunctuation.contains(text), !img.isNull, img.height > 0, ascent + descent > 0 {
            let typoMidY = (ascent - descent) * 0.5
            let inkMidY = img.minY + img.height * 0.5
            // CoreText is Y-up while UIKit is Y-down: moving a low mark upward needs a negative UIKit dy.
            dy = min(2.0, max(-5.5, inkMidY - typoMidY))
        }
        let pt = CGPoint(x: dx, y: dy)
        opticalOffsetCache[key] = pt
        return pt
    }

    static func opticalHorizontalOffset(for text: String, font: UIFont) -> CGFloat {
        opticalOffset(for: text, font: font).x
    }

    private static func cachedSymbol(_ name: String) -> UIImage? {
        let k = name + (Theme.plain ? "_p" : "_m")
        if let img = symbolCache[k] { return img }
        let cfg = UIImage.SymbolConfiguration(pointSize: Metrics.iconSize, weight: Theme.plain ? .regular : .semibold)
        guard let img = UIImage(systemName: name, withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate) else { return nil }
        symbolCache[k] = img
        return img
    }

    init(spec: KeySpec, borders: Bool) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1.0)
        layer.shadowOpacity = 1
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        icon.contentMode = .center
        addSubview(label)
        addSubview(icon)
        apply(spec, borders: borders, force: true)
    }

    /// Update label / icon / style without recreating the view (keeps touches alive).
    func apply(_ spec: KeySpec, borders: Bool, force: Bool = false) {
        if !force && hasApplied && borders == self.borders && spec == self.spec { return }
        hasApplied = true
        applyRunsForTests += 1
        self.spec = spec
        self.borders = borders
        hintLit = false
        label.text = spec.label
        if let hint = spec.hint {
            let h = hintLabel ?? {
                let l = UILabel()
                addSubview(l)
                hintLabel = l
                return l
            }()
            h.font = Theme.font(bounds.height > 0 && bounds.height < 34 ? 8.5 : 9.5, .semibold)
            h.textAlignment = .right
            h.adjustsFontSizeToFitWidth = true
            h.minimumScaleFactor = 0.65
            h.text = hint
            h.isHidden = false
        } else {
            hintLabel?.isHidden = true
        }
        let hasGuide = !spec.guideFinals.isEmpty || spec.guideInitial != nil
        if hasGuide && guideLabel == nil {
            let g = UILabel()
            g.numberOfLines = 0
            g.textAlignment = .center
            addSubview(g)
            guideLabel = g
        }
        guideLabel?.isHidden = !hasGuide
        switch spec.action {
        case .char where spec.isLetter: label.font = Theme.font(Metrics.letterFont, .regular)
        case .char where ["“", "”", "‘", "’"].contains(spec.label):
            label.font = UIFont(name: "PingFangSC-Medium", size: Metrics.symbolFont) ?? Theme.font(Metrics.symbolFont, .medium)
        case .char where spec.label.count >= 3:
            label.font = Theme.font(18.5, .medium)
        case .char: label.font = Theme.font(Metrics.symbolFont, .medium)
        case .t9(let d): label.font = Theme.font(d == "'" ? Metrics.functionFont : 20, .semibold)
        case .space: label.font = Theme.font(15, .regular)
        default: label.font = Theme.font(Metrics.functionFont, Theme.plain ? .medium : .semibold)
        }
        if let name = spec.symbol {
            // Keep face.smiling in its crisp outline variant in dark mode so it harmonizes with shift & delete.
            icon.overrideUserInterfaceStyle = (name == "face.smiling") ? .light : .unspecified
            icon.image = Self.cachedSymbol(name)
            icon.isHidden = false
        } else {
            icon.overrideUserInterfaceStyle = .unspecified
            icon.image = nil
            icon.isHidden = true
        }
        updateColors()
        setNeedsLayout()
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityLabel = Self.spokenName(spec)
        accessibilityHint = spec.alt.map { "上滑或长按输入 \($0)" }
    }

    /// What VoiceOver reads for a key (icons have no text of their own).
    private static func spokenName(_ spec: KeySpec) -> String {
        switch spec.action {
        case .char(let s): return s
        case .shift: return "上档"
        case .delete: return "删除"
        case .space: return "空格"
        case .ret: return spec.label.isEmpty ? "换行" : spec.label
        case .globe: return "下一个键盘"
        case .settings: return "键盘设置"
        case .emoji: return "表情，按住打开键盘设置"
        case .toggleLanguage: return spec.label == "中" ? "中文，轻点切换到英文" : "英文，轻点切换到中文"
        case .t9(let d): return d == "'" ? "分词" : "\(d)，\(spec.label)"
        case .deleteWord: return "删除词"
        case .clearInput: return "重输"
        case .page(let p):
            switch p {
            case .letters: return "字母"
            case .numbers: return "数字与符号"
            case .symbols: return "更多符号"
            case .numpad: return "数字键盘"
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyPressState() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.backgroundColor = pressed ? pressedBg : restBg
        layer.shadowOpacity = pressed ? 0 : 1
        CATransaction.commit()
        if currentStyle == .function {
            let fg = pressed ? pressedFg : restFg
            label.textColor = fg
            icon.tintColor = fg
        }
    }

    private func updateColors() {
        let t = traitCollection
        let rest: UIColor, down: UIColor, under: UIColor, fg: UIColor, downFg: UIColor
        currentStyle = spec.action == .shift && spec.style == .normal ? .normal : spec.style
        switch currentStyle {
        case .normal:
            rest = Theme.key; down = Theme.keyPressed; under = Theme.keyLip
            fg = Theme.keyText; downFg = Theme.keyText
        case .function:
            rest = Theme.functionKey; down = Theme.functionPressed; under = Theme.functionLip
            fg = Theme.functionText; downFg = Theme.keyText
        case .accent:
            rest = Theme.accentKey; down = Theme.accentPressed; under = Theme.accentLip
            fg = Theme.accentText; downFg = Theme.accentText
        }
        restBg = rest.resolvedColor(with: t).cgColor
        pressedBg = down.resolvedColor(with: t).cgColor
        restFg = fg.resolvedColor(with: t)
        pressedFg = downFg.resolvedColor(with: t)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.shadowColor = under.resolvedColor(with: t).cgColor
        layer.borderColor = Theme.keyBorder.resolvedColor(with: t).cgColor
        if let dot = statusDot {
            let active = (spec.action == .toggleLanguage && spec.label == "中") || (spec.action == .shift && spec.style == .normal)
            dot.backgroundColor = (active ? Theme.statusLedActive : Theme.statusLedMuted).resolvedColor(with: t).cgColor
            dot.isHidden = blanked || Theme.plain || !(spec.action == .toggleLanguage || spec.action == .shift)
        }
        if let notch = spaceNotch {
            notch.backgroundColor = Theme.spaceNotch.resolvedColor(with: t).cgColor
            notch.isHidden = blanked || Theme.plain || spec.action != .space || bounds.width <= 120
        }
        CATransaction.commit()
        if currentStyle != .function {
            label.textColor = spec.action == .space ? restFg.withAlphaComponent(0.76) : restFg
            icon.tintColor = restFg
        }
        if let h = hintLabel, !h.isHidden {
            let color = hintLit ? Theme.correctedMark : Theme.secondaryText.withAlphaComponent(0.78)
            h.textColor = color.resolvedColor(with: t)
        }
        if let g = guideLabel, !g.isHidden { g.attributedText = guideText() }
        applyPressState()
        if bounds.width > 0 && (bounds.size != lastCapSize || lastPlainMode != Theme.plain) { layoutCap() }
    }

    func setHintLit(_ lit: Bool) {
        guard lit != hintLit else { return }
        hintLit = lit
        guard let h = hintLabel, !h.isHidden else { return }
        let color = lit ? Theme.correctedMark : Theme.secondaryText.withAlphaComponent(0.78)
        h.textColor = color.resolvedColor(with: traitCollection)
    }

    var hintTextForTests: String? { (hintLabel?.isHidden == false) ? hintLabel?.text : nil }
    var hintLitForTests: Bool { hintLit }
    var labelFontSizeForTests: CGFloat { label.font.pointSize }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
    }

    /// The style changed (Mosto / 简洁): colours, type and the cap's shape follow.
    func themeChanged() {
        hasApplied = false
        lastCapSize = .zero
        apply(spec, borders: borders, force: true)
    }

    private var lastCapSize: CGSize = .zero
    private var lastPlainMode: Bool = false

    private func layoutCap() {
        let f = bounds
        guard f.width > 0, f.height > 0 else { return }
        let cr: CGFloat = Metrics.cornerRadius
        let sizeChanged = f.size != lastCapSize || lastPlainMode != Theme.plain
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if sizeChanged {
            lastCapSize = f.size
            lastPlainMode = Theme.plain
            layer.cornerRadius = cr
            layer.shadowPath = UIBezierPath(roundedRect: f, cornerRadius: cr).cgPath
        }
        let wantsDot = !Theme.plain && (spec.action == .toggleLanguage || spec.action == .shift)
        if wantsDot {
            let dot = statusDot ?? {
                let d = CALayer()
                d.cornerRadius = 2.25
                layer.addSublayer(d)
                statusDot = d
                return d
            }()
            dot.frame = CGRect(x: f.width - 9.5, y: 5.5, width: 4.5, height: 4.5)
            let active = (spec.action == .toggleLanguage && spec.label == "中") || (spec.action == .shift && spec.style == .normal)
            dot.backgroundColor = (active ? Theme.statusLedActive : Theme.statusLedMuted).resolvedColor(with: traitCollection).cgColor
            dot.isHidden = blanked
        } else {
            statusDot?.isHidden = true
        }
        let wantsNotch = spec.action == .space && !Theme.plain && f.width > 120
        if wantsNotch {
            let notch = spaceNotch ?? {
                let n = CALayer()
                n.cornerRadius = 1.25
                layer.addSublayer(n)
                spaceNotch = n
                return n
            }()
            notch.frame = CGRect(x: (f.width - 22) / 2, y: (f.height - 2.5) / 2, width: 22, height: 2.5)
            notch.backgroundColor = Theme.spaceNotch.resolvedColor(with: traitCollection).cgColor
            notch.isHidden = blanked
            label.isHidden = true
        } else {
            spaceNotch?.isHidden = true
            label.isHidden = false
        }
        CATransaction.commit()

        let hasHint = !(hintLabel?.isHidden ?? true)
        let o = cjkPunctuationOffset(label.text, fontSize: label.font.pointSize, font: label.font)
        let hintDrop: CGFloat = hasHint ? (spec.label.count >= 3 ? 4.0 : 1.5) : 0
        label.frame = f.insetBy(dx: 2, dy: 0).offsetBy(dx: o.x, dy: o.y + hintDrop)
        icon.frame = f
        // 键位提示: the letter moves up and smaller; the initial and finals sit under it (portrait only).
        let guided = !(spec.guideFinals.isEmpty && spec.guideInitial == nil) && f.height >= 34
        guideLabel?.isHidden = !guided
        if guided {
            let g = guideLabel ?? {
                let l = UILabel()
                l.numberOfLines = 0
                l.textAlignment = .center
                addSubview(l)
                guideLabel = l
                return l
            }()
            let top = f.height * 0.40
            label.font = Theme.font(min(Metrics.letterFont, top * 0.95), .regular)
            label.frame = CGRect(x: f.minX + 2, y: f.minY + 1, width: f.width - 4, height: top)
            g.attributedText = guideText(fitting: CGSize(width: f.width - 2, height: f.height - top - 2))
            g.frame = CGRect(x: f.minX + 1, y: f.minY + top, width: f.width - 2, height: f.height - top - 2)
        } else if spec.isLetter {
            let capH = f.height > 0 ? f.height : 40
            let lf = Theme.font(KeyboardHeightPreset.letterFontSize(forCapHeight: capH), .regular)
            if label.font !== lf { label.font = lf }
        }
        if let h = hintLabel, !h.isHidden {
            let compact = f.height < 34
            let ht = h.text ?? ""
            let tinyMark = ["。", "、", "·", ",", "'", "_"].contains(ht)
            h.font = Theme.font((compact ? 8.5 : 9.5) + (tinyMark ? 1.0 : 0), .semibold)
            let hw = min(16, max(11, f.width * 0.36))
            let hh: CGFloat = compact ? 11 : 13
            let hy: CGFloat = (compact ? 1.5 : 2.5) + (ht == "_" ? 1.5 : 0)
            h.frame = CGRect(x: f.width - hw - 3.5, y: hy, width: hw, height: hh)
        }
    }

    /// The guide's lines: the initial in the accent colour, then each final; the size shrinks until all lines fit.
    private func guideText(fitting box: CGSize? = nil) -> NSAttributedString {
        var lines: [(String, UIColor)] = []
        if let i = spec.guideInitial { lines.append((i, Theme.correctedMark)) }
        // under an initial (zh / ch / sh) the finals share one line, so the key never needs a third
        if spec.guideInitial != nil, spec.guideFinals.count > 1 {
            lines.append((spec.guideFinals.joined(separator: " "), Theme.guideText))
        } else {
            for f in spec.guideFinals { lines.append((f, Theme.guideText)) }
        }
        guard !lines.isEmpty else { return NSAttributedString() }
        var size: CGFloat = 10
        if let box {
            while size > 6.5 {
                let font = Theme.font(size, .semibold)
                let widest = lines.map { ($0.0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
                if widest <= box.width && font.lineHeight * CGFloat(lines.count) <= box.height { break }
                size -= 0.5
            }
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 0
        para.maximumLineHeight = Theme.font(size, .semibold).lineHeight
        let out = NSMutableAttributedString()
        for (k, (text, color)) in lines.enumerated() {
            out.append(NSAttributedString(string: (k > 0 ? "\n" : "") + text, attributes: [
                .font: Theme.font(size, .semibold), .foregroundColor: color, .paragraphStyle: para]))
        }
        return out
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCap()
    }
}

/// Key popup shown above a pressed character key.
/// Optical centring for full-width CJK punctuation using CoreText ink bounds, keeping asymmetric marks visually centered.
func cjkPunctuationOffset(_ text: String?, fontSize: CGFloat, font: UIFont? = nil) -> CGPoint {
    guard let t = text else { return .zero }
    let resolved = font ?? Theme.font(fontSize, .medium)
    let measured = KeyView.opticalOffset(for: t, font: resolved)
    if ["。", "，", "、", "．"].contains(t) {
        let dx = abs(measured.x) > 0.1 ? measured.x : fontSize * 0.22
        let dy = abs(measured.y) > 0.1 ? measured.y : -fontSize * 0.2
        return CGPoint(x: dx, y: dy)
    }
    if abs(measured.x) > 0.1 || abs(measured.y) > 0.1 { return measured }
    // Fallback for symmetric/bracket cases without non-zero CoreText bounds delta
    if ["（", "「", "『", "《", "〈", "【", "〔", "｛"].contains(t) { return CGPoint(x: -fontSize * 0.25, y: 0) }
    if ["）", "」", "』", "》", "〉", "】", "〕", "｝"].contains(t) { return CGPoint(x: fontSize * 0.25, y: 0) }
    return .zero
}

/// Clean, horn-free, neck-free floating key pill shown above a pressed key when slow-tapped, held, or flicked.
final class KeyPreview: UIView {
    let label = UILabel()
    private var lastRadiusBounds: CGRect = .zero
    private(set) var isFlicked = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 11
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.shadowRadius = 2.0
        layer.shadowOpacity = 0.10
        layer.shadowOffset = CGSize(width: 0, height: 1.5)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
        refreshStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refreshStyle() {
        let t = traitCollection
        backgroundColor = Theme.bubble
        layer.borderWidth = isFlicked ? 1.0 : 0.5
        layer.borderColor = (isFlicked ? Theme.correctedMark : Theme.bubbleLip).resolvedColor(with: t).cgColor
        layer.shadowColor = (Theme.plain ? UIColor.black : Theme.deepViolet).cgColor
        label.font = Theme.font(28, .medium)
        label.textColor = isFlicked ? Theme.correctedMark : Theme.keyText
    }

    func setFlicked(_ on: Bool) {
        guard isFlicked != on else { return }
        isFlicked = on
        refreshStyle()
    }

    /// `key`: the key's frame; `limit`: the horizontal room available (container bounds), both in container space.
    func place(over key: CGRect, within limit: CGRect, upwardLift: CGFloat = 0) {
        let capW = max(key.width + 16, 46)
        let availAbove = max(36, key.minY - limit.minY - 4)
        let capH = min(max(36, key.height * 1.04), availAbove)
        var capX = key.midX - capW / 2
        capX = min(max(limit.minX + 2, capX), limit.maxX - capW - 2)
        let top = max(limit.minY + 1, key.minY - capH - 4 - upwardLift)
        frame = CGRect(x: capX, y: top, width: capW, height: capH)
        refreshStyle()
        if bounds != lastRadiusBounds {
            lastRadiusBounds = bounds
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 11).cgPath
        }
        layoutPreviewLabel()
    }

    private func layoutPreviewLabel() {
        let o = cjkPunctuationOffset(label.text, fontSize: label.font.pointSize, font: label.font)
        label.frame = bounds.insetBy(dx: 3, dy: 0).offsetBy(dx: o.x, dy: o.y)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds != lastRadiusBounds {
            lastRadiusBounds = bounds
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 11).cgPath
        }
        layoutPreviewLabel()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refreshStyle()
    }
}

/// Long-press row of alternates (Gboard style): slide to choose, release to type the highlighted one.
final class AltPopup: UIView {
    private var labels: [UILabel] = []
    let cell: CGFloat
    var selected = 0 { didSet { if selected != oldValue { refresh() } } }

    /// `reversed`: near the right edge the row runs leftwards, so the first choice still sits over the key.
    let reversed: Bool

    init(options: [String], cell: CGFloat, height: CGFloat, reversed: Bool = false) {
        self.cell = cell
        self.reversed = reversed
        super.init(frame: CGRect(x: 0, y: 0, width: cell * CGFloat(options.count) + 8, height: height))
        isUserInteractionEnabled = false
        backgroundColor = Theme.bubble
        layer.cornerRadius = 11
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = Theme.bubbleLip.resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = (Theme.plain ? UIColor.black : Theme.deepViolet).cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2.5)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 11).cgPath
        for (i, o) in options.enumerated() {
            let slot = reversed ? options.count - 1 - i : i
            let shift = cjkPunctuationOffset(o, fontSize: 24)
            let l = UILabel(frame: CGRect(x: 4 + CGFloat(slot) * cell, y: 4, width: cell, height: height - 8))
            l.layer.sublayerTransform = CATransform3DMakeTranslation(shift.x, shift.y, 0)
            l.text = o
            l.textAlignment = .center
            l.font = Theme.font(24, .medium)
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.5
            l.layer.cornerRadius = 8
            l.layer.cornerCurve = .continuous
            l.clipsToBounds = true
            addSubview(l)
            labels.append(l)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        for (i, l) in labels.enumerated() {
            l.backgroundColor = i == selected ? Theme.selection : .clear
            l.textColor = i == selected ? Theme.selectionText : Theme.keyText
        }
    }

    func index(at x: CGFloat) -> Int {
        let slot = max(0, min(labels.count - 1, Int((x - frame.minX - 4) / cell)))
        return reversed ? labels.count - 1 - slot : slot
    }
}

/// Result of moving the host cursor by one step during spacebar trackpad drag.
enum CursorMoveOutcome: Equatable {
    case moved(crossedNewline: Bool)
    case hitStart, hitEnd
    case unavailable
}

/// Draws the keys and handles every touch itself (no UIButton per key), so a key
/// reacts on the first touch event, gaps between keys still hit the nearest key,
/// and fast two-thumb typing rolls over instead of dropping letters.
final class KeyboardView: UIView {
    var onAction: ((KeyAction, Tap?) -> Void)?
    /// The space bar drags the cursor one character (+1 right, −1 left). Returns whether it passed a visible
    /// character (and whether it crossed a newline or hit a confirmed start/end boundary).
    var onCursorBegin: (() -> Void)?
    var onCursorMove: ((Int) -> CursorMoveOutcome)?
    var onCursorEnd: (() -> Void)?
    /// Whether a drag on the space bar may move the cursor now (not while a pinyin is being composed).
    var canMoveCursor: (() -> Bool)?
    /// A finger lands on a key (where, for the haptic).
    var onKeyDown: ((KeyAction, CGPoint) -> Void)?
    /// Something felt that is not a key landing: other characters shown or changed, cursor mode, word deletes.
    var onFeedback: ((FeedbackEvent, CGPoint?) -> Void)?
    /// Whether something is being composed now (a swipe left off delete clears it only then).
    var isComposing: (() -> Bool)?
    /// A swipe left off delete is armed (true) or no longer (false): the strip shows what lifting would do.
    var onClearPreview: ((Bool) -> Void)?
    /// Continuous normalized delete-left swipe progress in 0...1 and armed state for the bar's warm filament.
    var onClearProgress: ((CGFloat, Bool) -> Void)?
    /// Continuous held-delete clutch ramp-up (`0...1`) before & during word-level deletion.
    var onDeleteClutchProgress: ((CGFloat, Bool) -> Void)?
    /// Called when a held-delete repeat gesture finishes on finger lift so any deleted words can offer undo.
    var onDeleteRepeatEnded: (() -> Void)?
    /// A swipe left off delete was let go while armed: clear the composition.
    var onClearSwipe: (() -> Void)?
    /// The test bench's stand-in for the version before the swipe existed (the same touches, no swipe to clear).
    var clearSwipeEnabled = true
    weak var inputController: UIInputViewController?

    let spatial: SpatialModel
    private(set) var context: LayoutContext?
    private var rows: [[KeySpec]] = []
    private var keyViews: [KeyView] = []
    /// The style changed: every key redraws in it.
    func themeChanged() {
        keyViews.forEach { $0.themeChanged() }
        previewPool.forEach { $0.refreshStyle() }
        for tr in tracked.values { tr.preview?.refreshStyle() }
        updateTrackpadRulerColors()
        setNeedsLayout()
    }
    private var hitRects: [CGRect] = []
    private var globeButton: UIButton?
    private var previewPool: [KeyPreview] = []
    private let trackpadRuler = CALayer()
    private let trackpadAxis = CALayer()
    private let trackpadTicks = CAShapeLayer()
    private let trackpadReticle = CALayer()
    private let trackpadPip = CALayer()
    private let trackpadBadge = UILabel()
    private var trackpadRulerOffset: CGFloat = 0
    private var trackpadEndStop = 0
    private var trackpadRawOverdrag: CGFloat = 0
    private var trackpadStepsDelta = 0
    private var trackpadJustCrossedNewline = false
    private var trackpadBadgeLastText = ""
    private var trackpadBadgeLastStop = 0
    private var lastTrackpadSize: CGSize = .zero
    var trackpadRulerVisibleForTests: Bool { !trackpadRuler.isHidden }
    var trackpadRulerOffsetForTests: CGFloat { trackpadRulerOffset }
    var trackpadEndStopForTests: Int { trackpadEndStop }
    var trackpadOverdragForTests: CGFloat { trackpadRubberBandOffset }
    var trackpadBadgeTextForTests: String? { trackpadBadge.isHidden ? nil : trackpadBadge.text }
    private var lastCharDownTime: CFTimeInterval = -1
    static let rapidPreviewThreshold: CFTimeInterval = 0.13
    var adaptivePreviewEnabled = true
    private(set) var lastPreviewShownForTests = false

    private final class Tracked {
        var keyIndex: Int
        var start: CGPoint
        var location: CGPoint
        var altShown = false
        var altOptions: [String] = []
        var altPopup: AltPopup?
        var altAnchorX: CGFloat = 0
        var longPressTimer: KeyTimer?
        var repeatTimer: KeyTimer?
        var dragAccum: CGFloat = 0
        var dragging = false
        /// The ticks of a cursor drag (rounds/R4.md): by the finger's distance, not by the characters.
        var rhythm = CursorRhythm()
        var lastMove: CFTimeInterval
        let began: CFTimeInterval
        var repeatCount = 0
        var deleteRepeating = false
        var preview: KeyPreview?
        /// Finished (emitted or abandoned): never finished again.
        var finished = false
        /// Typed the moment the finger landed (keys with no long-press choices): nothing more to type on release.
        var typedOnDown = false
        /// On delete, while something is being composed: the swipe left that clears it (rounds/R3.md).
        var clearSwipe: ClearSwipe?
        /// Upward flick off the Chinese comma key (，) emits a period (。) instantaneously without waiting for long-press.
        var flickedAlt: String?
        init(keyIndex: Int, start: CGPoint, time: CFTimeInterval) {
            self.keyIndex = keyIndex; self.start = start; self.location = start; self.began = time; self.lastMove = time
        }
    }
    /// A finger on the keys: a real touch, or one the test bench feeds.
    private enum TouchKey: Hashable { case touch(ObjectIdentifier), sample(Int) }
    private var tracked: [TouchKey: Tracked] = [:]
    private var touchOrder: [TouchKey] = []

    init(spatial: SpatialModel) {
        self.spatial = spatial
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        clipsToBounds = false
        backgroundColor = .clear   // root provides single uniform hit-test backing (avoids stacked translucent band)

        trackpadRuler.masksToBounds = true
        trackpadRuler.isHidden = true
        trackpadRuler.zPosition = 30
        trackpadTicks.fillColor = nil
        trackpadTicks.lineCap = .round
        trackpadReticle.cornerRadius = 1.0
        trackpadPip.cornerRadius = 2.5
        trackpadRuler.addSublayer(trackpadAxis)
        trackpadRuler.addSublayer(trackpadTicks)
        trackpadRuler.addSublayer(trackpadReticle)
        trackpadRuler.addSublayer(trackpadPip)
        layer.addSublayer(trackpadRuler)

        trackpadBadge.font = Theme.font(10.5, .semibold)
        trackpadBadge.textAlignment = .center
        trackpadBadge.layer.cornerRadius = 8.5
        trackpadBadge.layer.cornerCurve = .continuous
        trackpadBadge.layer.borderWidth = 0.5
        trackpadBadge.layer.zPosition = 31
        trackpadBadge.clipsToBounds = true
        trackpadBadge.isUserInteractionEnabled = false
        trackpadBadge.isAccessibilityElement = false
        trackpadBadge.isHidden = true
        addSubview(trackpadBadge)
        updateTrackpadRulerColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateTrackpadRulerColors()
    }

    private var trackpadRubberBandOffset: CGFloat {
        guard trackpadEndStop != 0 else { return 0 }
        let limit: CGFloat = 10
        let mag = abs(trackpadRawOverdrag)
        let damped = limit * (1 - exp(-mag / 22))
        return trackpadRawOverdrag >= 0 ? damped : -damped
    }

    private func updateTrackpadRulerColors() {
        let t = traitCollection
        let clamped = trackpadEndStop != 0
        let stopColor = Theme.plain ? Theme.selection : Theme.dyn(Theme.gold, Theme.goldGlow)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackpadAxis.backgroundColor = Theme.separator.resolvedColor(with: t).withAlphaComponent(0.55).cgColor
        trackpadTicks.strokeColor = Theme.secondaryText.resolvedColor(with: t).withAlphaComponent(0.38).cgColor
        trackpadReticle.backgroundColor = (clamped ? stopColor : Theme.correctedMark).resolvedColor(with: t).cgColor
        trackpadPip.backgroundColor = (clamped ? stopColor : Theme.statusLedActive).resolvedColor(with: t).cgColor
        trackpadBadge.backgroundColor = (clamped ? Theme.correctedTint : Theme.key.withAlphaComponent(0.92)).resolvedColor(with: t)
        trackpadBadge.textColor = (clamped ? stopColor : Theme.keyText).resolvedColor(with: t)
        trackpadBadge.layer.borderColor = (clamped ? stopColor.withAlphaComponent(0.45) : Theme.keyBorder).resolvedColor(with: t).cgColor
        CATransaction.commit()
    }

    private func layoutTrackpadRuler(rowH: CGFloat) {
        let trackH: CGFloat = 40
        let topAreaH = max(0, bounds.height - topReach - rowH)
        let rFrame = CGRect(x: 14, y: topReach + floor((topAreaH - trackH) / 2), width: max(0, bounds.width - 28), height: trackH)
        let baseY = floor(trackH * 0.56)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackpadRuler.frame = rFrame
        trackpadAxis.frame = CGRect(x: 0, y: baseY, width: rFrame.width, height: 0.5)
        let reticleW: CGFloat = trackpadEndStop != 0 ? 2.5 : 2
        trackpadReticle.frame = CGRect(x: floor(rFrame.width / 2 - reticleW / 2), y: baseY - 13, width: reticleW, height: 24)
        let pipShift = CGFloat(trackpadEndStop) * 3.5
        trackpadPip.frame = CGRect(x: floor(rFrame.width / 2 - 2.5 + pipShift), y: baseY - 20, width: 5, height: 5)
        if rFrame.size != lastTrackpadSize && rFrame.width > 20 {
            lastTrackpadSize = rFrame.size
            let path = UIBezierPath()
            let halfCount = Int(ceil((rFrame.width * 0.5 + 90) / 9.0))
            let midX = floor(rFrame.width * 0.5)
            for idx in -halfCount...halfCount {
                let x = midX + CGFloat(idx) * 9
                let major = idx % 5 == 0
                path.move(to: CGPoint(x: x, y: baseY - (major ? 9 : 4)))
                path.addLine(to: CGPoint(x: x, y: baseY + (major ? 7 : 4)))
            }
            trackpadTicks.path = path.cgPath
            trackpadTicks.lineWidth = 1.2
            trackpadTicks.frame = trackpadRuler.bounds
        }
        CATransaction.commit()
        layoutTrackpadBadge()
    }

    private func layoutTrackpadBadge() {
        guard !trackpadRuler.isHidden else {
            trackpadBadge.isHidden = true
            return
        }
        let text: String
        if trackpadEndStop < 0 {
            text = "文首"
        } else if trackpadEndStop > 0 {
            text = "文末"
        } else if trackpadStepsDelta < 0 {
            text = trackpadJustCrossedNewline ? "↵ ← \(-trackpadStepsDelta)" : "← \(-trackpadStepsDelta)"
        } else if trackpadStepsDelta > 0 {
            text = trackpadJustCrossedNewline ? "→ \(trackpadStepsDelta) ↵" : "→ \(trackpadStepsDelta)"
        } else {
            trackpadBadge.isHidden = true
            return
        }
        trackpadBadge.isHidden = false
        if text != trackpadBadgeLastText || trackpadBadge.bounds.height == 0 {
            trackpadBadgeLastText = text
            trackpadBadge.text = text
            let size = (text as NSString).size(withAttributes: [.font: trackpadBadge.font ?? Theme.font(10.5, .semibold)])
            let w = max(36, ceil(size.width) + 14)
            let h: CGFloat = 17
            let y = max(topReach + 4, trackpadRuler.frame.minY - h - 4)
            trackpadBadge.frame = CGRect(x: floor((bounds.width - w) / 2), y: y, width: w, height: h)
        }
        if trackpadEndStop != trackpadBadgeLastStop {
            trackpadBadgeLastStop = trackpadEndStop
            updateTrackpadRulerColors()
        }
    }

    private func advanceTrackpadRuler(dx: CGFloat) {
        if trackpadEndStop == 0 {
            trackpadRulerOffset = (trackpadRulerOffset + dx).truncatingRemainder(dividingBy: 45)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackpadTicks.transform = CATransform3DMakeTranslation(trackpadRulerOffset + trackpadRubberBandOffset, 0, 0)
        if trackpadEndStop != trackpadBadgeLastStop {
            let reticleW: CGFloat = trackpadEndStop != 0 ? 2.5 : 2
            let baseY = floor(trackpadRuler.bounds.height * 0.56)
            let midX = trackpadRuler.bounds.width / 2
            trackpadReticle.frame = CGRect(x: floor(midX - reticleW / 2), y: baseY - 13, width: reticleW, height: 24)
            let pipShift = CGFloat(trackpadEndStop) * 3.5
            trackpadPip.frame = CGRect(x: floor(midX - 2.5 + pipShift), y: baseY - 20, width: 5, height: 5)
        }
        CATransaction.commit()
        layoutTrackpadBadge()
    }

    /// Extra height at the top (overlapping the bottom of the candidate strip) that still belongs to the top
    /// row: a fast finger landing a little high types the key instead of hitting the strip and getting lost.
    var topReach: CGFloat = 0 { didSet { setNeedsLayout() } }

    /// Touch accounting for this session, shown in settings (诊断) to find where keystrokes go missing.
    struct Stats { var began = 0, emitted = 0, cancelKept = 0, dropped = 0 }
    private(set) var stats = Stats()

    func configure(_ ctx: LayoutContext) {
        let newRows = Layouts.rows(ctx)
        // a held key that rolls over is emitted while the keys it belongs to are still the ones laid out (emitting
        // it can lay the view out again; with the new rows and the old key views that read past the end)
        if !(newRows.count == rows.count && zip(newRows, rows).allSatisfy({ $0.count == $1.count })) { flushHeldKeys() }
        let sameShape = newRows.count == rows.count && zip(newRows, rows).allSatisfy { a, b in
            a.count == b.count && zip(a, b).allSatisfy { $0.width == $1.width && $0.action == $1.action }
        }
        context = ctx
        rows = newRows
        if sameShape && keyViews.count == newRows.reduce(0, { $0 + $1.count }) {
            // Labels only (shift state, return key title): update in place so in-flight touches survive.
            for (kv, spec) in zip(keyViews, newRows.flatMap { $0 }) { kv.apply(spec, borders: ctx.keyBorders) }
        } else {
            rebuild()
        }
    }

    private func rebuild() {
        // a key that changes the layout (123, 中/英, 符号) was released while another finger still held a key:
        // that keystroke counts — emit it before the keys are rebuilt, rather than dropping it
        flushHeldKeys()
        cancelAllTouches()
        keyViews.forEach { $0.removeFromSuperview() }
        globeButton?.removeFromSuperview()
        globeButton = nil
        let borders = context?.keyBorders ?? false
        keyViews = rows.flatMap { $0 }.map { KeyView(spec: $0, borders: borders) }
        keyViews.forEach { addSubview($0) }
        if let idx = keyViews.firstIndex(where: { $0.spec.action == .globe }), let ic = inputController {
            // The system input-mode menu needs a real UIControl wired to handleInputModeList.
            let b = UIButton(type: .custom)
            b.addTarget(ic, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
            b.tag = idx
            addSubview(b)
            globeButton = b
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !rows.isEmpty, bounds.width > 0, keyViews.count == rows.reduce(0, { $0 + $1.count }) else { return }
        let rowH = (bounds.height - topReach) / CGFloat(rows.count)
        let unit = bounds.width / 10
        let gapX = Metrics.gapX
        let gapY = min(12, max(8, (rowH * 0.20).rounded()))
        hitRects = []
        var i = 0
        var spatialKeys: [SpatialModel.Key] = []
        for (r, row) in rows.enumerated() {
            let fixed = row.reduce(CGFloat(0)) { $0 + $1.width }
            let flexCount = CGFloat(row.filter { $0.width == 0 }.count)
            let flexW = flexCount > 0 ? max(1, (10 - fixed) / flexCount) : 0
            let total = fixed + flexW * flexCount
            var x = (10 - total) / 2
            for (j, spec) in row.enumerated() {
                let w = spec.width == 0 ? flexW : spec.width
                let y = topReach + CGFloat(r) * rowH
                let frame = CGRect(x: x * unit + gapX / 2, y: y + gapY / 2, width: w * unit - gapX, height: rowH - gapY)
                keyViews[i].frame = frame
                var hit = CGRect(x: x * unit, y: y, width: w * unit, height: rowH)
                if r == 0 { hit = CGRect(x: hit.minX, y: 0, width: hit.width, height: rowH + topReach) }
                if j == 0 { hit = CGRect(x: 0, y: hit.minY, width: hit.maxX, height: hit.height) }
                if j == row.count - 1 { hit.size.width = bounds.width - hit.minX }
                hitRects.append(hit)
                if spec.isLetter, case .char(let s) = spec.action, let c = s.first {
                    spatialKeys.append(.init(char: c, cx: Double(frame.midX), cy: Double(frame.midY)))
                }
                if let g = globeButton, g.tag == i { g.frame = frame }
                x += w
                i += 1
            }
        }
        if spatialKeys.count == 26 {
            spatial.update(keys: spatialKeys, keyWidth: Double(unit), keyHeight: Double(rowH))
        }
        // the 九宫格 syllable column follows the keys it covers (rotation lays them out anew)
        if let o = overlay, !o.isHidden, let f = keypadSideColumn() { o.frame = f }
        layoutTrackpadRuler(rowH: rowH)
    }

    // MARK: - Hit testing

    private func keyIndex(at p: CGPoint) -> Int? {
        // keys hidden under the syllable column type nothing, however close the touch lands
        func usable(_ i: Int) -> Bool { i >= keyViews.count || !keyViews[i].isHidden }
        if let i = hitRects.indices.first(where: { hitRects[$0].contains(p) }) { return usable(i) ? i : nil }
        // Outside every row band (e.g. dragged off the edge): nearest key.
        var best: Int?
        var bestD = CGFloat.infinity
        for (i, r) in hitRects.enumerated() where usable(i) {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// A view laid over some keys that takes its own touches (the 九宫格 syllable column).
    var overlay: UIView?

    /// The 九宫格 keypad's left column (the punctuation keys of its first three rows), in this view's coordinates.
    func keypadSideColumn() -> CGRect? {
        guard context?.pinyinGrid == true, context?.chinese == true, context?.page == .letters, rows.count >= 3 else { return nil }
        var idx = 0, rect = CGRect.null
        for r in 0..<3 {
            if idx < keyViews.count { rect = rect.union(keyViews[idx].frame) }
            idx += rows[r].count
        }
        return rect.isNull ? nil : rect
    }

    /// Hide the keypad's ， 。 ？ while the syllable column covers them (so they never show through it).
    func setSideColumnHidden(_ hidden: Bool) {
        guard context?.pinyinGrid == true, rows.count >= 3 else { return }
        var idx = 0
        for r in 0..<3 {
            if idx < keyViews.count { keyViews[idx].isHidden = hidden }
            idx += rows[r].count
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let o = overlay, !o.isHidden, o.frame.contains(point) {
            return o.hitTest(convert(point, to: o), with: event)
        }
        if let g = globeButton, g.frame.contains(point) { return g }
        guard bounds.contains(point) else { return nil }
        // Mosto sits in the strip right above q: the band over the top row gives way to him where he stands, so a
        // tap or double tap on him never types a q
        if point.y < topReach, let r = reservedTop?(), r.contains(point) { return nil }
        // The band above the top row overlaps the bottom of the candidate strip. Its lower 8 pt always types; the
        // rest types while the user is typing (a key went down in the last 0.25 s — a fast finger landing high) or
        // when the strip has nothing to tap; otherwise the touch goes to the candidate under it.
        if point.y < topReach - 8, CACurrentMediaTime() - lastKeyDown > 0.25, !(stripIsEmpty?() ?? true) { return nil }
        return self
    }

    /// When the last key went down (see hitTest).
    private var lastKeyDown: CFTimeInterval = 0
    /// Whether the candidate strip above has nothing to tap.
    var stripIsEmpty: (() -> Bool)?
    /// Part of the band above the top row that belongs to the strip (Mosto, when he is there), in this view's space.
    var reservedTop: (() -> CGRect?)?

    // MARK: - Touches

    // UIKit's touches only read where and when; everything else is in began / moved / ended / cancelled below,
    // which the test bench drives with recorded samples (feedForTests) — the same code either way.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { began(.touch(ObjectIdentifier(t)), at: t.location(in: self), time: CACurrentMediaTime()) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { moved(.touch(ObjectIdentifier(t)), at: t.location(in: self), time: CACurrentMediaTime()) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // in the order the keys went down (a Set has none): two keys lifted together come out as typed
        let ordered = touches.sorted { a, b in
            (touchOrder.firstIndex(of: .touch(ObjectIdentifier(a))) ?? .max) < (touchOrder.firstIndex(of: .touch(ObjectIdentifier(b))) ?? .max)
        }
        for t in ordered { ended(.touch(ObjectIdentifier(t)), at: t.location(in: self), time: CACurrentMediaTime()) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { cancelled(.touch(ObjectIdentifier(t)), at: t.location(in: self), time: CACurrentMediaTime()) }
    }

    private func began(_ id: TouchKey, at p: CGPoint, time: CFTimeInterval) {
        // Roll-over: a new finger finalises any key still held down that types (characters, 九宫格 keys, a space
        // tap, return), so fast two-thumb typing keeps the order the keys went down in.
        flushHeldKeys()
        if hitRects.count != keyViews.count { layoutIfNeeded() }
        guard let idx = keyIndex(at: p), idx < keyViews.count else { return }

        let tr = Tracked(keyIndex: idx, start: p, time: time)
        stats.began += 1
        tracked[id] = tr
        touchOrder.append(id)
        let kv = keyViews[idx]
        kv.pressed = true
        lastKeyDown = time
        onKeyDown?(kv.spec.action, p)
        switch kv.spec.action {
        case .char(let s) where kv.spec.alt == nil:
            // Velocity-adaptive zero-ghost feedback: suppress occluding popup during rapid burst typing (<130ms).
            let rapid = adaptivePreviewEnabled && lastCharDownTime > 0 && (time - lastCharDownTime) < Self.rapidPreviewThreshold
            lastCharDownTime = time
            if !rapid {
                showPreview(tr, text: kv.spec.label)
                lastPreviewShownForTests = (tr.preview != nil && tr.preview?.isHidden == false)
            } else {
                lastPreviewShownForTests = false
            }
            tr.typedOnDown = true
            stats.emitted += 1
            if kv.spec.isLetter, let c = s.first {
                onAction?(.char(s), spatial.tap(x: Double(p.x), y: Double(p.y), hitKey: c))
            } else {
                onAction?(.char(s), nil)
            }
        case .t9:
            tr.typedOnDown = true
            stats.emitted += 1
            onAction?(kv.spec.action, nil)
        case .char:
            lastCharDownTime = time
            showPreview(tr, text: kv.spec.label)
            lastPreviewShownForTests = (tr.preview != nil && tr.preview?.isHidden == false)
            tr.longPressTimer = schedule(after: 0.38, from: time) { [weak self, weak tr] _ in
                guard let self, let tr else { return }
                self.showAlt(tr)
            }
        case .delete:
            // a swipe left from here clears the composition — only when there is one as the finger lands (read
            // before this press takes a key of it away)
            let composing = clearSwipeEnabled && (isComposing?() ?? false)
            onAction?(.delete, nil)
            if composing { tr.clearSwipe = ClearSwipe(start: p, keyLeft: kv.frame.minX, time: time) }
            // a second finger on a delete already held deletes once; one repeat at a time
            if tracked.values.contains(where: { $0 !== tr && $0.keyIndex == idx && !$0.finished }) { break }
            tr.repeatTimer = schedule(after: 0.42, from: time) { [weak self, weak tr] _ in
                guard let self, let tr else { return }
                self.startDeleteRepeat(tr)
            }
        case .shift:
            onAction?(.shift, nil)
        case .emoji:
            // held: the keyboard settings (and the tap that follows is not an emoji tap)
            tr.longPressTimer = schedule(after: 0.45, from: time) { [weak self, weak tr] _ in
                guard let self, let tr else { return }
                tr.altShown = true
                self.onAction?(.settings, nil)
            }
        default:
            break
        }
    }

    private func moved(_ id: TouchKey, at p: CGPoint, time: CFTimeInterval) {
        guard let tr = tracked[id], tr.keyIndex < keyViews.count else { return }
        let prev = tr.location
        tr.location = p
        let kv = keyViews[tr.keyIndex]
        switch kv.spec.action {
        case .space:
            // Drag on the space bar moves the cursor (Gboard / iOS trackpad): the caps go blank, one character
            // per ~9 pt when slow, finer steps when the finger moves fast, so a long jump needs no second swipe.
            let dx = p.x - prev.x
            let now = time
            let speed = abs(dx) / CGFloat(max(now - tr.lastMove, 1.0 / 120))
            tr.lastMove = now
            // a quick tap on space while typing fast may slide a little: only a clear drag (22 pt), or a shorter
            // one after holding for a moment, moves the cursor — otherwise it is a space
            let held = now - tr.began
            let threshold: CGFloat = held > 0.3 ? 12 : 22
            if !tr.dragging && abs(p.x - tr.start.x) > threshold && (canMoveCursor?() ?? true) {
                tr.dragging = true
                tr.dragAccum = 0
                tr.rhythm.begin(at: now)
                setCursorMode(true, except: tr.keyIndex)
                onCursorBegin?()
                onFeedback?(.cursorMode, p)
            }
            if tr.dragging {
                tr.dragAccum += dx
                let step: CGFloat = speed > 900 ? 3.5 : speed > 450 ? 5.5 : 9
                var steps = 0, passed = 0
                var hitBoundary = 0
                var crossedNewline = false
                while abs(tr.dragAccum) >= step {
                    let dir = tr.dragAccum > 0 ? 1 : -1
                    switch onCursorMove?(dir) ?? .unavailable {
                    case .moved(let nl):
                        passed += 1
                        trackpadStepsDelta += dir
                        if nl { crossedNewline = true }
                        hitBoundary = 0
                        trackpadEndStop = 0
                        trackpadRawOverdrag = 0
                    case .hitStart:
                        hitBoundary = -1
                    case .hitEnd:
                        hitBoundary = 1
                    case .unavailable:
                        trackpadStepsDelta += dir
                        hitBoundary = 0
                        trackpadEndStop = 0
                        trackpadRawOverdrag = 0
                    }
                    steps += dir
                    tr.dragAccum -= CGFloat(dir) * step
                }
                if passed > 0 {
                    trackpadJustCrossedNewline = crossedNewline
                }
                if hitBoundary != 0 {
                    let newlyClamped = trackpadEndStop != hitBoundary
                    trackpadEndStop = hitBoundary
                    trackpadJustCrossedNewline = false
                    if (hitBoundary < 0 && dx < 0) || (hitBoundary > 0 && dx > 0) {
                        trackpadRawOverdrag += dx
                    } else if hitBoundary > 0 && dx < 0 {
                        trackpadRawOverdrag = max(0, trackpadRawOverdrag + dx)
                    } else if hitBoundary < 0 && dx > 0 {
                        trackpadRawOverdrag = min(0, trackpadRawOverdrag + dx)
                    }
                    if newlyClamped { onFeedback?(.cursorBoundary, p) }
                } else if trackpadEndStop != 0 {
                    if trackpadEndStop > 0 {
                        trackpadRawOverdrag = max(0, trackpadRawOverdrag + dx)
                    } else {
                        trackpadRawOverdrag = min(0, trackpadRawOverdrag + dx)
                    }
                } else if crossedNewline {
                    onFeedback?(.cursorBoundary, p)
                }
                advanceTrackpadRuler(dx: dx)
                // felt by the finger's distance (every 27 pt, ≥ 100 ms apart), not once per character
                if tr.rhythm.feed(dx: dx, steps: steps, passed: passed, at: now) { onFeedback?(.cursorStep, p) }
            }
        case .delete:
            followClearSwipe(tr, to: p, at: time)
        case .char where tr.altShown:
            // the first choice stays selected until the finger actually slides
            if let popup = tr.altPopup, abs(p.x - tr.altAnchorX) > 6 {
                let i = popup.index(at: p.x)
                if i != popup.selected { popup.selected = i; onFeedback?(.altMoved, p) }
            }
        case .char where !tr.altShown && !tr.typedOnDown:
            if let alt = kv.spec.alt {
                let rise = tr.start.y - p.y
                let driftX = abs(p.x - tr.start.x)
                if rise >= 16 && driftX <= 32 {
                    kv.setHintLit(true)
                    if tr.flickedAlt == nil {
                        tr.flickedAlt = alt
                        tr.longPressTimer?.invalidate()
                        showPreview(tr, text: alt, flicked: true)
                        lastPreviewShownForTests = (tr.preview != nil && tr.preview?.isHidden == false)
                        onFeedback?(.altMoved, p)
                    }
                    break
                } else if tr.flickedAlt != nil && rise < 8 {
                    tr.flickedAlt = nil
                    kv.setHintLit(false)
                    onFeedback?(.altMoved, p)
                    if kv.spec.style == .normal || kv.spec.action == .char("，") || kv.spec.action == .char("。") {
                        showPreview(tr, text: kv.spec.label, flicked: false)
                    } else {
                        recyclePreview(tr.preview); tr.preview = nil
                    }
                    break
                } else if rise >= 6 && driftX <= 32 {
                    kv.setHintLit(true)
                    break
                } else if tr.flickedAlt == nil {
                    kv.setHintLit(false)
                    if rise > 6 && driftX <= 28 { break }
                }
            }
            // Slide to a neighbouring character key before release (keys typed on landing stay typed).
            if let idx = keyIndex(at: p), idx < keyViews.count, idx != tr.keyIndex, case .char = keyViews[idx].spec.action {
                kv.pressed = false
                tr.longPressTimer?.invalidate()
                tr.flickedAlt = nil
                tr.keyIndex = idx
                keyViews[idx].pressed = true
                recyclePreview(tr.preview); tr.preview = nil   // never the old key's pill over the new key
                showPreview(tr, text: keyViews[idx].spec.label)
                lastPreviewShownForTests = (tr.preview != nil && tr.preview?.isHidden == false)
                if keyViews[idx].spec.alt != nil {
                    tr.longPressTimer = schedule(after: 0.38, from: time) { [weak self, weak tr] _ in
                        guard let self, let tr else { return }
                        self.showAlt(tr)
                    }
                }
            }
        default:
            break
        }
    }

    /// The finger on delete moved: arm or disarm the swipe that clears. Armed, the strip fades and held delete will
    /// not start repeating (the press ends as a clear, or as the one delete it already was).
    private func followClearSwipe(_ tr: Tracked, to p: CGPoint, at time: CFTimeInterval) {
        guard var swipe = tr.clearSwipe else { return }
        let changed = swipe.move(to: p, at: time)
        tr.clearSwipe = swipe
        onClearProgress?(swipe.progress(at: p, time: time), swipe.armed)
        guard changed else { return }
        if swipe.armed { tr.repeatTimer?.invalidate(); tr.repeatTimer = nil }
        onFeedback?(.clearArmed, p)
        onClearPreview?(swipe.armed)
    }

    private func ended(_ id: TouchKey, at p: CGPoint, time: CFTimeInterval) {
        guard let tr = tracked[id] else { return }
        tr.location = p
        // where the finger came up decides a swipe on delete (armed there or not)
        if tr.keyIndex < keyViews.count, keyViews[tr.keyIndex].spec.action == .delete { followClearSwipe(tr, to: p, at: time) }
        finish(tr, emit: true)
        tracked[id] = nil
        touchOrder.removeAll { $0 == id }
    }

    /// Keys a new finger finalises, so fast typing keeps the order it was typed in: characters, 九宫格 keys, return,
    /// and a space that is a tap (not a cursor drag).
    private func rollsOver(_ tr: Tracked) -> Bool {
        guard tr.keyIndex < keyViews.count, !tr.altShown, !tr.finished else { return false }
        switch keyViews[tr.keyIndex].spec.action {
        case .char, .t9, .ret: return true
        case .space: return !tr.dragging
        default: return false
        }
    }

    /// Emit every held key that rolls over (in the order they went down).
    private func flushHeldKeys() {
        for id in touchOrder {
            if let tr = tracked[id], rollsOver(tr) {
                tracked[id] = nil
                finish(tr, emit: true)
            }
        }
        touchOrder.removeAll { tracked[$0] == nil }
    }

    private func cancelled(_ id: TouchKey, at p: CGPoint, time: CFTimeInterval) {
        // iOS cancels keyboard touches it suspects belong to a system gesture (screen edges, the bottom bar, a
        // fast stroke). A press on a character key or a tap on space that was cancelled is still a keystroke:
        // dropping it is what makes fast typing lose letters. Only a long-press menu or a cursor drag is abandoned
        // (and a swipe on delete: it never clears when cancelled).
        guard let tr = tracked[id] else { return }
        var keep = false
        if tr.keyIndex < keyViews.count {
            switch keyViews[tr.keyIndex].spec.action {
            case .char, .t9: keep = !tr.altShown
            case .space: keep = !tr.dragging
            default: keep = false
            }
        }
        let already = tr.typedOnDown
        finish(tr, emit: keep)
        if already { } else if keep { stats.cancelKept += 1 } else { stats.dropped += 1 }
        tracked[id] = nil
        touchOrder.removeAll { $0 == id }
    }

    // MARK: - Test bench: recorded touches

    /// The bench's clock: set once samples are fed; the keys' timers then fire as the samples' time passes them.
    private var benchClock: CFTimeInterval?
    private var benchTimers: [KeyTimer] = []
    /// Swipes on delete let go while armed (cleared), this session.
    private(set) var clearSwipes = 0

    /// A timer for a held key: a run-loop timer, or on the bench one that the fed samples' clock fires.
    private func schedule(after delay: CFTimeInterval, from time: CFTimeInterval, repeating: CFTimeInterval? = nil,
                          commonModes: Bool = false, _ action: @escaping (KeyTimer) -> Void) -> KeyTimer {
        guard benchClock != nil else {
            return KeyTimer.scheduled(after: delay, repeating: repeating, commonModes: commonModes, action)
        }
        let kt = KeyTimer(fireAt: time + delay, interval: repeating, action: action)
        benchTimers.append(kt)
        return kt
    }

    private func advanceBenchClock(to t: CFTimeInterval) {
        guard benchClock != nil else { return }
        while true {
            benchTimers.removeAll { !$0.isValid }
            guard let next = benchTimers.filter({ $0.fireAt <= t }).min(by: { $0.fireAt < $1.fireAt }) else { break }
            benchClock = next.fireAt
            next.fire()
        }
        benchClock = t
    }

    /// Feed recorded touches (in this view's coordinates): the same began / moved / ended / cancelled as real ones.
    func feedForTests(_ samples: [TouchSample]) {
        if benchClock == nil { benchClock = samples.first?.time ?? 0 }
        for s in samples {
            advanceBenchClock(to: s.time)
            switch s.phase {
            case .began: began(.sample(s.id), at: s.point, time: s.time)
            case .moved: moved(.sample(s.id), at: s.point, time: s.time)
            case .ended: ended(.sample(s.id), at: s.point, time: s.time)
            case .cancelled: cancelled(.sample(s.id), at: s.point, time: s.time)
            }
        }
    }

    /// Time passes on the bench with no finger moving (a key held still).
    func advanceForTests(to t: CFTimeInterval) { advanceBenchClock(to: t) }

    /// Where a key is (its cap, and the area that types it), for the bench to aim at.
    func keyRectsForTests(_ action: KeyAction) -> (cap: CGRect, hit: CGRect)? {
        layoutIfNeeded()
        guard let i = keyViews.firstIndex(where: { $0.spec.action == action }), i < hitRects.count else { return nil }
        return (keyViews[i].frame, hitRects[i])
    }

    override var isHidden: Bool { didSet { if isHidden && !oldValue { cancelAllTouches() } } }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelAllTouches() }
    }

    /// Put away (a panel over the keys, the keyboard dismissed): held keys let go, repeats stop, caps redrawn.
    func cancelAllTouches() {
        for (_, tr) in tracked where !tr.finished { finish(tr, emit: false); if !tr.typedOnDown { stats.dropped += 1 } }
        tracked.removeAll()
        touchOrder.removeAll()
    }

    private func setCursorMode(_ on: Bool, except index: Int) {
        for (i, kv) in keyViews.enumerated() where i != index { kv.blanked = on }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackpadRuler.isHidden = !on
        trackpadRulerOffset = 0
        trackpadEndStop = 0
        trackpadRawOverdrag = 0
        trackpadStepsDelta = 0
        trackpadJustCrossedNewline = false
        trackpadBadgeLastText = ""
        trackpadBadgeLastStop = 0
        trackpadBadge.isHidden = true
        trackpadTicks.transform = CATransform3DIdentity
        CATransaction.commit()
        if on {
            bringSubviewToFront(trackpadBadge)
            updateTrackpadRulerColors()
        }
    }

    private func finish(_ tr: Tracked, emit: Bool) {
        guard !tr.finished else { return }
        tr.finished = true
        if tr.dragging { setCursorMode(false, except: -1); onCursorEnd?() }
        tr.longPressTimer?.invalidate()
        tr.repeatTimer?.invalidate()
        recyclePreview(tr.preview)
        tr.preview = nil
        // a swipe on delete: lifted while armed, it clears; cancelled or put away, it never does
        let clears = emit && tr.clearSwipe?.armed == true
        if tr.clearSwipe != nil { onClearProgress?(0, false) }
        if tr.clearSwipe?.armed == true { onClearPreview?(false) }
        tr.clearSwipe = nil
        if tr.deleteRepeating {
            onDeleteClutchProgress?(0, false)
            if emit { onDeleteRepeatEnded?() }
        }
        tr.deleteRepeating = false
        let chosen = tr.altPopup?.selected ?? 0
        tr.altPopup?.removeFromSuperview()
        tr.altPopup = nil
        guard tr.keyIndex < keyViews.count else { return }
        let kv = keyViews[tr.keyIndex]
        // still held by another finger: it stays down
        if !tracked.values.contains(where: { $0 !== tr && $0.keyIndex == tr.keyIndex && !$0.finished }) { kv.pressed = false }
        guard emit, !tr.typedOnDown else { return }
        stats.emitted += 1
        if clears {
            clearSwipes += 1
            onFeedback?(.key(.clearInput), tr.location)
            onClearSwipe?()
            return
        }
        switch kv.spec.action {
        case .char(let s):
            if tr.altShown, chosen < tr.altOptions.count {
                onAction?(.char(tr.altOptions[chosen]), nil)
            } else if let flick = tr.flickedAlt {
                onAction?(.char(flick), nil)
            } else if kv.spec.isLetter, let c = s.first {
                let tap = spatial.tap(x: Double(tr.location.x), y: Double(tr.location.y), hitKey: c)
                onAction?(.char(s), tap)
            } else {
                onAction?(.char(s), nil)
            }
        case .space:
            if !tr.dragging { onAction?(.space, nil) }
        case .delete, .shift, .globe:
            break
        case .emoji:
            if !tr.altShown { onAction?(.emoji, nil) }
        default:
            onAction?(kv.spec.action, nil)
        }
    }

    /// As the system keyboard: a character every 70 ms, then after ~1.4 s a word at a time (slower ticks, so it
    /// stays controllable). Timers run in the common run-loop modes so they keep firing while a finger moves.
    private func startDeleteRepeat(_ tr: Tracked) {
        tr.repeatCount = 0
        tr.deleteRepeating = true
        // held delete has started: this press no longer swipes to clear
        if tr.clearSwipe != nil { onClearProgress?(0, false) }
        tr.clearSwipe = nil
        tr.repeatTimer = schedule(after: 0.07, from: benchClock ?? CACurrentMediaTime(), repeating: 0.07, commonModes: true) { [weak self, weak tr] timer in
            guard let self, let tr else { timer.invalidate(); return }
            tr.repeatCount += 1
            if tr.repeatCount < 20 {
                self.onAction?(.delete, nil)
                if tr.repeatCount >= 8 {
                    let clutch = CGFloat(tr.repeatCount - 7) / 13.0
                    self.onDeleteClutchProgress?(clutch, false)
                }
            } else {
                if tr.repeatCount == 20 {
                    self.onDeleteClutchProgress?(1.0, true)
                }
                if tr.repeatCount % 3 == 0 {
                    self.onAction?(.deleteWord, nil)
                    self.onFeedback?(.deleteWord, nil)
                }
            }
        }
    }

    /// Snapshot support: the space bar held and dragged — cursor mode, every other cap blank + Leica vernier ruler.
    func demoCursorMode() {
        guard let idx = keyViews.firstIndex(where: { $0.spec.action == .space }) else { return }
        UIView.performWithoutAnimation {
            keyViews[idx].pressed = true
            setCursorMode(true, except: idx)
            trackpadStepsDelta = 6
            advanceTrackpadRuler(dx: 14)
        }
    }

    /// Snapshot support: show the floating pill for a character key as if it were held.
    func demoPress(_ char: String) {
        guard let idx = keyViews.firstIndex(where: { $0.spec.action == .char(char) }) else { return }
        let tr = Tracked(keyIndex: idx, start: keyViews[idx].center, time: CACurrentMediaTime())
        keyViews[idx].pressed = true
        showPreview(tr, text: keyViews[idx].spec.label)
        lastPreviewShownForTests = (tr.preview != nil && tr.preview?.isHidden == false)
    }

    /// Snapshot support: a key drawn held down (delete, during a swipe that clears).
    func demoHold(_ action: KeyAction) {
        guard let idx = keyViews.firstIndex(where: { $0.spec.action == action }) else { return }
        UIView.performWithoutAnimation { keyViews[idx].pressed = true }
    }

    // MARK: - Popups

    private func acquirePreview() -> KeyPreview {
        if let reused = previewPool.popLast() {
            reused.isHidden = false
            return reused
        }
        let p = KeyPreview(frame: .zero)
        addSubview(p)
        return p
    }

    private func recyclePreview(_ p: KeyPreview?) {
        guard let p else { return }
        p.setFlicked(false)
        p.isHidden = true
        if !previewPool.contains(where: { $0 === p }) {
            if previewPool.count < 2 {
                previewPool.append(p)
            } else {
                p.removeFromSuperview()
            }
        }
    }

    private func showPreview(_ tr: Tracked, text: String, flicked: Bool = false) {
        guard tr.keyIndex < keyViews.count else { return }
        let kv = keyViews[tr.keyIndex]
        guard kv.spec.style == .normal || kv.spec.action == .char("，") || kv.spec.action == .char("。") || tr.flickedAlt != nil || tr.altShown || flicked else { return }
        let p = tr.preview ?? acquirePreview()
        p.setFlicked(flicked)
        p.label.text = text
        if p.superview == nil { addSubview(p) } else { bringSubviewToFront(p) }
        p.isHidden = false
        // the room above: up to the top of the keyboard's whole view (the strip included)
        let topY = superview.map { convert(CGPoint.zero, from: $0).y } ?? bounds.minY
        p.place(over: kv.frame, within: CGRect(x: bounds.minX, y: topY + 1, width: bounds.width, height: bounds.maxY - topY - 1), upwardLift: flicked ? 3 : 0)
        tr.preview = p
    }

    func keyHintTextForTests(_ action: KeyAction) -> String? {
        layoutIfNeeded()
        return keyViews.first(where: { $0.spec.action == action })?.hintTextForTests
    }

    func keyHintLitForTests(_ action: KeyAction) -> Bool {
        keyViews.first(where: { $0.spec.action == action })?.hintLitForTests ?? false
    }

    func keyLabelFontSizeForTests(_ action: KeyAction) -> CGFloat? {
        layoutIfNeeded()
        return keyViews.first(where: { $0.spec.action == action })?.labelFontSizeForTests
    }

    var activePreviewFlickedForTests: Bool {
        tracked.values.contains { $0.preview?.isHidden == false && $0.preview?.isFlicked == true }
    }

    private func showAlt(_ tr: Tracked) {
        guard tr.keyIndex < keyViews.count, !tr.finished else { return }   // a long-press timer after the keys changed
        let kv = keyViews[tr.keyIndex]
        guard let alt = kv.spec.alt else { return }
        tr.altShown = true
        tr.altOptions = [alt] + kv.spec.moreAlts
        if tr.altOptions.count == 1 {
            showPreview(tr, text: alt)
            tr.preview?.label.textColor = Theme.correctedMark
            lastPreviewShownForTests = (tr.preview != nil && tr.preview?.isHidden == false)
        } else {
            recyclePreview(tr.preview); tr.preview = nil
            let f = kv.frame
            let cell = max(f.width, 34)
            let rowWidth = cell * CGFloat(tr.altOptions.count) + 8
            // the first option sits over the key; the rest run right, or left when the key is near the right edge
            let reversed = f.midX - cell / 2 - 4 + rowWidth > bounds.width - 2
            let popup = AltPopup(options: tr.altOptions, cell: cell, height: f.height * 1.1, reversed: reversed)
            var x = reversed ? f.midX + cell / 2 + 4 - rowWidth : f.midX - cell / 2 - 4
            x = min(max(2, x), bounds.width - popup.frame.width - 2)
            popup.frame.origin = CGPoint(x: x, y: f.minY - popup.frame.height - 4)
            popup.selected = 0
            tr.altAnchorX = tr.location.x
            addSubview(popup)
            tr.altPopup = popup
        }
        // the finger already felt the key landing: the choices appearing are a tick, with no second click
        onFeedback?(.altShown, tr.location)
    }
}
