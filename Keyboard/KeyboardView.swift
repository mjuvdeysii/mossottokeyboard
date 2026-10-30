import UIKit

final class KeyView: UIView {
    private(set) var spec: KeySpec
    private(set) var borders = false
    private let label = UILabel()
    private let hintLabel = UILabel()
    /// 小鹤键位提示: the initial and finals under the letter
    private let guideLabel = UILabel()
    private let icon = UIImageView()

    var pressed = false { didSet { if pressed != oldValue { updateColors() } } }
    private var hasApplied = false
    /// While the space bar drives the cursor the other caps go blank, as in the iOS trackpad mode.
    var blanked = false {
        didSet {
            guard blanked != oldValue else { return }
            UIView.animate(withDuration: 0.15) {
                let a: CGFloat = self.blanked ? 0 : 1
                self.label.alpha = a; self.hintLabel.alpha = a; self.icon.alpha = a; self.guideLabel.alpha = a
            }
            wings.isHidden = blanked || spec.action != .space
            crown.isHidden = blanked || spec.action != .toggleLanguage
        }
    }

    /// The vinyl cap: a darker lip, the face over it (top-lit), and on the space bar Mosto's two wings.
    private let lip = CALayer()
    private let face = CAGradientLayer()
    /// The light catching the cap's rounded top edge (soft vinyl, matte: a rim, not a gloss).
    private let rim = CAShapeLayer()
    private let wings = CAShapeLayer()
    private let crown = CAShapeLayer()

    init(spec: KeySpec, borders: Bool) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        lip.cornerRadius = Metrics.cornerRadius
        face.cornerRadius = Metrics.cornerRadius
        face.startPoint = CGPoint(x: 0.5, y: 0)
        face.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(lip)
        face.locations = [0, 0.5, 1]
        layer.addSublayer(face)
        rim.fillColor = nil
        rim.lineWidth = 1
        rim.lineCap = .round
        layer.addSublayer(rim)
        // contact shadow: the cap stands on the board, it is not printed on it
        lip.shadowOffset = CGSize(width: 0, height: 1)
        lip.shadowRadius = 1.5
        layer.addSublayer(wings)
        crown.path = Self.crownPath()
        crown.lineJoin = .round
        crown.lineWidth = 1
        layer.addSublayer(crown)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        hintLabel.font = .systemFont(ofSize: Metrics.hintFont, weight: .regular)
        hintLabel.textAlignment = .center
        icon.contentMode = .center
        addSubview(label)
        addSubview(hintLabel)
        guideLabel.numberOfLines = 0
        guideLabel.textAlignment = .center
        guideLabel.isHidden = true
        addSubview(guideLabel)
        addSubview(icon)
        apply(spec, borders: borders)
    }

    /// Update label / icon / style without recreating the view (keeps touches alive).
    func apply(_ spec: KeySpec, borders: Bool) {
        // nothing to redraw when the key is unchanged (this runs for every key on every keystroke)
        if hasApplied, borders == self.borders, spec.label == self.spec.label, spec.symbol == self.spec.symbol,
           spec.style == self.spec.style, spec.action == self.spec.action, spec.alt == self.spec.alt,
           spec.width == self.spec.width, spec.guideFinals == self.spec.guideFinals,
           spec.guideInitial == self.spec.guideInitial { return }
        hasApplied = true
        self.spec = spec
        self.borders = borders
        label.text = spec.label
        hintLabel.text = spec.hint
        hintLabel.isHidden = spec.hint == nil
        guideLabel.isHidden = spec.guideFinals.isEmpty && spec.guideInitial == nil
        switch spec.action {
        // the system keyboard's type: regular weight throughout
        case .char where spec.isLetter: label.font = Theme.font(Metrics.letterFont, .regular)
        case .char where ["“", "”", "‘", "’"].contains(spec.label):
            // the rounded face draws the curly quotes as two near-identical straight ticks: PingFang shows “ and ”
            label.font = UIFont(name: "PingFangSC-Medium", size: Metrics.symbolFont) ?? Theme.font(Metrics.symbolFont, .medium)
        case .char: label.font = Theme.font(Metrics.symbolFont, .medium)
        case .t9(let d): label.font = Theme.font(d == "'" ? Metrics.functionFont : 20, .semibold)
        default: label.font = Theme.font(Metrics.functionFont, .semibold)
        }
        if let name = spec.symbol {
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.iconSize, weight: .semibold))
            icon.isHidden = false
        } else {
            icon.image = nil
            icon.isHidden = true
        }
        updateColors()
        setNeedsLayout()
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityLabel = Self.spokenName(spec)
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

    private func updateColors() {
        let t = traitCollection
        let top: UIColor, bottom: UIColor, under: UIColor, fg: UIColor
        // an engaged shift reads as a letter cap (cream / violet vinyl) with a solid arrow
        let style: KeyStyle = spec.action == .shift && spec.style == .normal ? .normal : spec.style
        switch style {
        case .normal:
            top = pressed ? Theme.keyPressed : Theme.keyTop
            bottom = pressed ? Theme.keyPressed : Theme.key
            under = Theme.keyLip; fg = Theme.keyText
        case .function:
            top = pressed ? Theme.functionPressed : Theme.functionTop
            bottom = pressed ? Theme.functionPressed : Theme.functionKey
            under = Theme.functionLip; fg = pressed ? Theme.keyText : Theme.functionText
        case .accent:
            top = pressed ? Theme.accentKey : Theme.accentTop
            bottom = Theme.accentKey
            under = Theme.accentLip; fg = Theme.accentText
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // a little fall-off towards the lip gives the cap its volume
        let b = bottom.resolvedColor(with: t), u = under.resolvedColor(with: t)
        face.colors = [top.resolvedColor(with: t).cgColor, b.cgColor, Theme.mix(b, u, pressed ? 0.04 : 0.10).cgColor]
        lip.backgroundColor = u.cgColor
        lip.shadowColor = Theme.keyShadow.resolvedColor(with: t).cgColor
        lip.shadowOpacity = pressed ? 0 : 1
        rim.strokeColor = Theme.keyHighlight.resolvedColor(with: t).withAlphaComponent(
            Theme.keyHighlight.resolvedColor(with: t).cgColor.alpha * (pressed ? 0.35 : style == .accent ? 0.8 : 1)).cgColor
        wings.fillColor = Theme.wing.resolvedColor(with: t).cgColor
        crown.fillColor = Theme.accentKey.resolvedColor(with: t).cgColor
        crown.strokeColor = Theme.accentLip.resolvedColor(with: t).cgColor
        CATransaction.commit()
        backgroundColor = .clear
        label.textColor = fg
        hintLabel.textColor = Theme.secondaryText
        guideLabel.attributedText = guideText()
        icon.tintColor = fg
        if bounds.width > 0 { layoutCap() }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
    }

    /// The face rests on the lip; pressed, it sinks onto it (the lip all but disappears), as a soft toy key would.
    private var faceRect: CGRect {
        let l = min(Metrics.lip, bounds.height * 0.1)
        return pressed ? CGRect(x: 0, y: l - 0.5, width: bounds.width, height: bounds.height - l)
                       : CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - l)
    }

    /// The style changed (Mosto / 简洁): colours, type and the cap's shape follow.
    func themeChanged() {
        hasApplied = false
        apply(spec, borders: borders)
    }

    private func layoutCap() {
        let l = min(Metrics.lip, bounds.height * 0.1)
        let f = faceRect
        CATransaction.begin(); CATransaction.setDisableActions(true)
        lip.cornerRadius = Metrics.cornerRadius
        face.cornerRadius = Metrics.cornerRadius
        lip.frame = CGRect(x: 0, y: l, width: bounds.width, height: bounds.height - l)
        lip.shadowPath = UIBezierPath(roundedRect: lip.bounds, cornerRadius: Metrics.cornerRadius).cgPath
        face.frame = f
        rim.frame = f
        rim.path = Self.rimPath(in: f.size)
        if spec.action == .space, f.width > 120, !Theme.plain {
            wings.isHidden = blanked
            wings.frame = f
            wings.path = Self.wingsPath(in: f.size)
        } else {
            wings.isHidden = true
        }
        if spec.action == .toggleLanguage, !blanked, !Theme.plain {
            crown.isHidden = false
            crown.bounds = CGRect(x: 0, y: 0, width: 15, height: 9)
            crown.position = CGPoint(x: f.maxX - 9, y: f.minY + 1)
            crown.setAffineTransform(CGAffineTransform(rotationAngle: 0.30))
        } else {
            crown.isHidden = true
        }
        CATransaction.commit()
        let o = cjkPunctuationOffset(label.text, fontSize: label.font.pointSize)
        label.frame = f.insetBy(dx: 2, dy: 0).offsetBy(dx: o.x, dy: o.y)
        icon.frame = f
        // 键位提示: the letter moves up and smaller; the initial (gold) and finals sit under it, one per line —
        // only where the cap is tall enough to read them (portrait); in landscape the letter alone
        let guided = !(spec.guideFinals.isEmpty && spec.guideInitial == nil) && f.height >= 34
        guideLabel.isHidden = !guided
        if guided {
            let top = f.height * 0.40
            label.font = Theme.font(min(Metrics.letterFont, top * 0.95), .regular)
            label.frame = CGRect(x: f.minX + 2, y: f.minY + 1, width: f.width - 4, height: top)
            guideLabel.attributedText = guideText(fitting: CGSize(width: f.width - 2, height: f.height - top - 2))
            guideLabel.frame = CGRect(x: f.minX + 1, y: f.minY + top, width: f.width - 2, height: f.height - top - 2)
        } else if spec.isLetter {
            label.font = Theme.font(Metrics.letterFont, .regular)
        }
        // Digit hint in the cap's top-right corner.
        hintLabel.frame = CGRect(x: f.maxX - 16, y: f.minY + 2, width: 12, height: 13)
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

    /// The cap's top edge, inset half a point: the two upper corners and the line between them, ending where the
    /// sides turn straight.
    static func rimPath(in size: CGSize) -> CGPath {
        let r = min(Metrics.cornerRadius, size.height / 2, size.width / 2) - 0.5
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0.5, y: r + 0.5))
        p.addArc(withCenter: CGPoint(x: r + 0.5, y: r + 0.5), radius: r, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
        p.addLine(to: CGPoint(x: size.width - r - 0.5, y: 0.5))
        p.addArc(withCenter: CGPoint(x: size.width - r - 0.5, y: r + 0.5), radius: r, startAngle: 1.5 * .pi, endAngle: 0, clockwise: true)
        return p.cgPath
    }

    /// Mosto's two little bat wings at the ends of the space bar: a curved arm out to the tip, three scalloped
    /// fingers below, tips outwards.
    static func wingsPath(in size: CGSize) -> CGPath {
        let w: CGFloat = 24, h: CGFloat = 13, inset: CGFloat = 12
        let y = (size.height - h) / 2 + 1
        let p = UIBezierPath()
        func wing(_ x0: CGFloat, _ dir: CGFloat) {
            func pt(_ x: CGFloat, _ yy: CGFloat) -> CGPoint { CGPoint(x: x0 + dir * x, y: y + yy) }
            p.move(to: pt(0, 4))
            p.addQuadCurve(to: pt(w, 0), controlPoint: pt(w * 0.45, -2))            // the arm
            p.addQuadCurve(to: pt(w * 0.84, h * 0.80), controlPoint: pt(w * 0.98, h * 0.45))
            p.addQuadCurve(to: pt(w * 0.52, h), controlPoint: pt(w * 0.70, h * 0.48))  // scallop, finger
            p.addQuadCurve(to: pt(w * 0.22, h * 0.86), controlPoint: pt(w * 0.38, h * 0.50))
            p.addQuadCurve(to: pt(0, h * 0.66), controlPoint: pt(w * 0.08, h * 0.56))
            p.close()
        }
        wing(size.width - inset - w, 1)   // right wing, tip to the right
        wing(inset + w, -1)               // left wing, tip to the left
        return p.cgPath
    }

    /// Mosto's crown, worn askew on the 中 / 英 key: three points, matte gold, tilted, peeking over the top edge.
    static func crownPath() -> CGPath {
        let w: CGFloat = 15, h: CGFloat = 9
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0.5, y: 2.5))
        p.addLine(to: CGPoint(x: w * 0.27, y: h * 0.55))
        p.addLine(to: CGPoint(x: w * 0.5, y: 0))
        p.addLine(to: CGPoint(x: w * 0.73, y: h * 0.55))
        p.addLine(to: CGPoint(x: w - 0.5, y: 2.5))
        p.addLine(to: CGPoint(x: w, y: h))
        p.close()
        return p.cgPath
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCap()
    }
}

/// Key popup shown above a pressed character key.
/// Optical centring for full-width CJK punctuation: 。，、 sit in the lower-left of their em box, so on a key
/// they look dropped and off to the side. Returns the offset that moves the glyph to the visual centre.
func cjkPunctuationOffset(_ text: String?, fontSize: CGFloat) -> CGPoint {
    guard let t = text else { return .zero }
    if ["。", "，", "、", "．"].contains(t) { return CGPoint(x: fontSize * 0.22, y: -fontSize * 0.2) }
    // full-width brackets hug the inside edge of their em box: an opening one sits right, a closing one left
    if ["（", "「", "『", "《", "〈", "【", "〔", "｛"].contains(t) { return CGPoint(x: -fontSize * 0.25, y: 0) }
    if ["）", "」", "』", "》", "〉", "】", "〕", "｝"].contains(t) { return CGPoint(x: fontSize * 0.25, y: 0) }
    return .zero
}

/// The key-press balloon, shaped like the iOS keyboard's: a wider cap above the key that narrows through a
/// short neck into the key itself, so the pressed key appears to grow upwards rather than a box floating over it.
final class KeyPreview: UIView {
    let label = UILabel()
    private let shape = CAShapeLayer()
    /// Mosto's two cream horns on the balloon's top corners.
    private let horns = CAShapeLayer()
    private var capRect: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(horns)
        layer.addSublayer(shape)
        horns.fillColor = Theme.cream.cgColor
        horns.strokeColor = Theme.hex(0xC9A86A).cgColor
        horns.lineWidth = 0.8
        shape.shadowColor = Theme.deepViolet.cgColor
        shape.shadowOpacity = 0.30
        shape.shadowRadius = 3
        shape.shadowOffset = CGSize(width: 0, height: 2)
        shape.lineWidth = 1
        label.textAlignment = .center
        label.font = Theme.font(32, .medium)
        label.textColor = Theme.keyText
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `key`: the key's frame; `limit`: the horizontal room available (container bounds), both in container space.
    func place(over key: CGRect, within limit: CGRect) {
        // the top row has only the strip above it, and nothing can be drawn above the keyboard's own top edge: there
        // the balloon grows only as tall as the room allows (never shorter than the key) instead of being cut off
        let capW = max(key.width + 26, 52)
        var capH = key.height * 1.12, neck: CGFloat = 10
        let room = key.minY - limit.minY
        if neck + capH > room {
            neck = max(4, min(10, room - key.height * 0.95))
            capH = max(key.height * 0.9, room - neck)
        }
        var capX = key.midX - capW / 2
        capX = min(max(limit.minX + 1, capX), limit.maxX - capW - 1)
        let top = key.minY - neck - capH
        let minX = min(capX, key.minX), maxX = max(capX + capW, key.maxX)
        frame = CGRect(x: minX, y: top, width: maxX - minX, height: key.maxY - top)
        let cap = CGRect(x: capX - minX, y: 0, width: capW, height: capH)
        let k = CGRect(x: key.minX - minX, y: capH + neck, width: key.width, height: key.height)
        capRect = cap
        let r: CGFloat = 11, kr = Metrics.cornerRadius
        let p = UIBezierPath()
        p.move(to: CGPoint(x: cap.minX, y: cap.minY + r))
        p.addArc(withCenter: CGPoint(x: cap.minX + r, y: cap.minY + r), radius: r, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
        p.addLine(to: CGPoint(x: cap.maxX - r, y: cap.minY))
        p.addArc(withCenter: CGPoint(x: cap.maxX - r, y: cap.minY + r), radius: r, startAngle: 1.5 * .pi, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: cap.maxX, y: cap.maxY - 4))
        p.addCurve(to: CGPoint(x: k.maxX, y: k.minY + 2),
                   controlPoint1: CGPoint(x: cap.maxX, y: cap.maxY + neck * 0.55),
                   controlPoint2: CGPoint(x: k.maxX, y: k.minY - neck * 0.45))
        p.addLine(to: CGPoint(x: k.maxX, y: k.maxY - kr))
        p.addArc(withCenter: CGPoint(x: k.maxX - kr, y: k.maxY - kr), radius: kr, startAngle: 0, endAngle: 0.5 * .pi, clockwise: true)
        p.addLine(to: CGPoint(x: k.minX + kr, y: k.maxY))
        p.addArc(withCenter: CGPoint(x: k.minX + kr, y: k.maxY - kr), radius: kr, startAngle: 0.5 * .pi, endAngle: .pi, clockwise: true)
        p.addLine(to: CGPoint(x: k.minX, y: k.minY + 2))
        p.addCurve(to: CGPoint(x: cap.minX, y: cap.maxY - 4),
                   controlPoint1: CGPoint(x: k.minX, y: k.minY - neck * 0.45),
                   controlPoint2: CGPoint(x: cap.minX, y: cap.maxY + neck * 0.55))
        p.close()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = p.cgPath
        shape.shadowPath = p.cgPath
        shape.fillColor = Theme.bubble.resolvedColor(with: traitCollection).cgColor
        shape.strokeColor = Theme.bubbleLip.resolvedColor(with: traitCollection).cgColor
        horns.frame = bounds
        horns.path = Self.hornsPath(cap)
        horns.isHidden = top - 9 < limit.minY || Theme.plain   // no room above for his horns (none in 简洁)
        CATransaction.commit()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let o = cjkPunctuationOffset(label.text, fontSize: label.font.pointSize)
        label.frame = capRect.insetBy(dx: 3, dy: 0).offsetBy(dx: o.x, dy: o.y - 1)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        shape.fillColor = Theme.bubble.resolvedColor(with: traitCollection).cgColor
        shape.strokeColor = Theme.bubbleLip.resolvedColor(with: traitCollection).cgColor
    }

    /// Two small curled horns rising from the balloon's shoulders, out then up (as on Mosto's head); their bases
    /// tuck under the balloon.
    static func hornsPath(_ cap: CGRect) -> CGPath {
        let p = UIBezierPath()
        let base: CGFloat = 8, rise: CGFloat = 9
        for dir: CGFloat in [-1, 1] {
            let cx = dir < 0 ? cap.minX + 13 : cap.maxX - 13
            let b0 = CGPoint(x: cx - base / 2, y: cap.minY + 4), b1 = CGPoint(x: cx + base / 2, y: cap.minY + 4)
            let tip = CGPoint(x: cx + dir * 5, y: cap.minY - rise)
            let outer = dir < 0 ? b0 : b1, inner = dir < 0 ? b1 : b0
            p.move(to: inner)
            p.addQuadCurve(to: tip, controlPoint: CGPoint(x: inner.x + dir * 1, y: cap.minY - rise * 0.5))
            p.addQuadCurve(to: outer, controlPoint: CGPoint(x: outer.x + dir * 4, y: cap.minY - rise * 0.2))
            p.close()
        }
        return p.cgPath
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
        layer.cornerRadius = 10
        layer.shadowColor = Theme.deepViolet.cgColor
        layer.shadowOpacity = 0.30
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
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
            l.layer.cornerRadius = 7
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

/// Draws the keys and handles every touch itself (no UIButton per key), so a key
/// reacts on the first touch event, gaps between keys still hit the nearest key,
/// and fast two-thumb typing rolls over instead of dropping letters.
final class KeyboardView: UIView {
    var onAction: ((KeyAction, Tap?) -> Void)?
    var onCursorMove: ((Int) -> Void)?
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
    func themeChanged() { keyViews.forEach { $0.themeChanged() }; setNeedsLayout() }
    private var hitRects: [CGRect] = []
    private var globeButton: UIButton?

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
        var lastMove: CFTimeInterval
        let began: CFTimeInterval
        var repeatCount = 0
        var preview: KeyPreview?
        /// Finished (emitted or abandoned): never finished again.
        var finished = false
        /// Typed the moment the finger landed (keys with no long-press choices): nothing more to type on release.
        var typedOnDown = false
        /// On delete, while something is being composed: the swipe left that clears it (rounds/R3.md).
        var clearSwipe: ClearSwipe?
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
        backgroundColor = Theme.touchable   // never fully clear: see Theme.touchable
    }

    required init?(coder: NSCoder) { fatalError() }

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
        let gapY = min(Metrics.gapY, rowH * 0.22)
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
            // A key with nothing to choose on a long press types the moment the finger lands, as the fastest
            // input methods do: the time the finger rests on the glass is no longer added to every keystroke.
            // The balloon still shows while it is held.
            showPreview(tr, text: kv.spec.label)
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
            showPreview(tr, text: kv.spec.label)
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
                setCursorMode(true, except: tr.keyIndex)
                onFeedback?(.cursorMode, p)
            }
            if tr.dragging {
                tr.dragAccum += dx
                let step: CGFloat = speed > 900 ? 3.5 : speed > 450 ? 5.5 : 9
                while abs(tr.dragAccum) >= step {
                    let dir = tr.dragAccum > 0 ? 1 : -1
                    onCursorMove?(dir)
                    tr.dragAccum -= CGFloat(dir) * step
                }
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
            // Slide to a neighbouring character key before release (keys typed on landing stay typed).
            if let idx = keyIndex(at: p), idx < keyViews.count, idx != tr.keyIndex, case .char = keyViews[idx].spec.action {
                kv.pressed = false
                tr.longPressTimer?.invalidate()
                tr.keyIndex = idx
                keyViews[idx].pressed = true
                tr.preview?.removeFromSuperview(); tr.preview = nil   // never the old key's balloon over the new key
                showPreview(tr, text: keyViews[idx].spec.label)
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
    }

    private func finish(_ tr: Tracked, emit: Bool) {
        guard !tr.finished else { return }
        tr.finished = true
        if tr.dragging { setCursorMode(false, except: -1) }
        tr.longPressTimer?.invalidate()
        tr.repeatTimer?.invalidate()
        tr.preview?.removeFromSuperview()
        tr.preview = nil
        // a swipe on delete: lifted while armed, it clears; cancelled or put away, it never does
        let clears = emit && tr.clearSwipe?.armed == true
        if tr.clearSwipe?.armed == true { onClearPreview?(false) }
        tr.clearSwipe = nil
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
        // held delete has started: this press no longer swipes to clear
        tr.clearSwipe = nil
        tr.repeatTimer = schedule(after: 0.07, from: benchClock ?? CACurrentMediaTime(), repeating: 0.07, commonModes: true) { [weak self, weak tr] timer in
            guard let self, let tr else { timer.invalidate(); return }
            tr.repeatCount += 1
            if tr.repeatCount < 20 {
                self.onAction?(.delete, nil)
            } else if tr.repeatCount % 3 == 0 {
                self.onAction?(.deleteWord, nil)
                self.onFeedback?(.deleteWord, nil)
            }
        }
    }

    /// Snapshot support: the space bar held and dragged — cursor mode, every other cap blank.
    func demoCursorMode() {
        guard let idx = keyViews.firstIndex(where: { $0.spec.action == .space }) else { return }
        UIView.performWithoutAnimation {
            keyViews[idx].pressed = true
            setCursorMode(true, except: idx)
        }
    }

    /// Snapshot support: show the balloon for a character key as if it were held.
    func demoPress(_ char: String) {
        guard let idx = keyViews.firstIndex(where: { $0.spec.action == .char(char) }) else { return }
        let tr = Tracked(keyIndex: idx, start: keyViews[idx].center, time: CACurrentMediaTime())
        keyViews[idx].pressed = true
        showPreview(tr, text: keyViews[idx].spec.label)
    }

    /// Snapshot support: a key drawn held down (delete, during a swipe that clears).
    func demoHold(_ action: KeyAction) {
        guard let idx = keyViews.firstIndex(where: { $0.spec.action == action }) else { return }
        UIView.performWithoutAnimation { keyViews[idx].pressed = true }
    }

    // MARK: - Popups

    private func showPreview(_ tr: Tracked, text: String) {
        guard tr.keyIndex < keyViews.count else { return }
        let kv = keyViews[tr.keyIndex]
        guard kv.spec.style == .normal || kv.spec.action == .char("，") || kv.spec.action == .char("。") || tr.altShown else { return }
        let p = tr.preview ?? KeyPreview(frame: .zero)
        p.label.text = text
        p.label.textColor = Theme.keyText
        if p.superview == nil { addSubview(p) }
        // the room above: up to the top of the keyboard's whole view (the strip included)
        let topY = superview.map { convert(CGPoint.zero, from: $0).y } ?? bounds.minY
        p.place(over: kv.frame, within: CGRect(x: bounds.minX, y: topY + 1, width: bounds.width, height: bounds.maxY - topY - 1))
        tr.preview = p
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
        } else {
            tr.preview?.removeFromSuperview(); tr.preview = nil
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
