import UIKit

final class KeyView: UIView {
    private(set) var spec: KeySpec
    private(set) var borders = false
    private let label = UILabel()
    private let hintLabel = UILabel()
    private let icon = UIImageView()

    var pressed = false { didSet { if pressed != oldValue { updateColors() } } }
    private var hasApplied = false
    /// While the space bar drives the cursor the other caps go blank, as in the iOS trackpad mode.
    var blanked = false {
        didSet {
            guard blanked != oldValue else { return }
            UIView.animate(withDuration: 0.15) {
                let a: CGFloat = self.blanked ? 0 : 1
                self.label.alpha = a; self.hintLabel.alpha = a; self.icon.alpha = a
            }
        }
    }

    init(spec: KeySpec, borders: Bool) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = Metrics.cornerRadius
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        hintLabel.font = .systemFont(ofSize: Metrics.hintFont, weight: .regular)
        hintLabel.textAlignment = .center
        icon.contentMode = .center
        addSubview(label)
        addSubview(hintLabel)
        addSubview(icon)
        apply(spec, borders: borders)
    }

    /// Update label / icon / style without recreating the view (keeps touches alive).
    func apply(_ spec: KeySpec, borders: Bool) {
        // nothing to redraw when the key is unchanged (this runs for every key on every keystroke)
        if hasApplied, borders == self.borders, spec.label == self.spec.label, spec.symbol == self.spec.symbol,
           spec.style == self.spec.style, spec.action == self.spec.action, spec.alt == self.spec.alt,
           spec.width == self.spec.width { return }
        hasApplied = true
        self.spec = spec
        self.borders = borders
        label.text = spec.label
        hintLabel.text = spec.hint
        hintLabel.isHidden = spec.hint == nil
        switch spec.action {
        // the system keyboard's type: regular weight throughout
        case .char where spec.isLetter: label.font = .systemFont(ofSize: Metrics.letterFont, weight: .regular)
        case .char: label.font = .systemFont(ofSize: Metrics.symbolFont, weight: .regular)
        case .t9(let d): label.font = .systemFont(ofSize: d == "'" ? Metrics.functionFont : 20, weight: .regular)
        default: label.font = .systemFont(ofSize: Metrics.functionFont, weight: .regular)
        }
        if let name = spec.symbol {
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.iconSize, weight: .regular))
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
        case .toggleLanguage: return spec.label == "中" ? "中文，轻点切换到英文" : "英文，轻点切换到中文"
        case .t9(let d): return d == "'" ? "分词" : "\(d)，\(spec.label)"
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

    /// Gboard draws keys borderless: only the space bar (and an action-coloured return key)
    /// has a filled cap. With "按键边框" on, every key gets the classic iOS cap.
    private var hasCap: Bool { borders || spec.action == .space || spec.style == .accent }

    private func updateColors() {
        let bg: UIColor
        if hasCap {
            switch spec.style {
            case .normal: bg = pressed ? Theme.keyPressed : Theme.key
            case .function: bg = pressed ? Theme.key : Theme.functionKey
            case .accent: bg = pressed ? Theme.functionKey : Theme.accentKey
            }
        } else {
            // borderless: an engaged shift still shows as a lit key
            let engaged = spec.action == .shift && spec.style == .normal
            bg = pressed || engaged ? Theme.keyHighlight : .clear
        }
        backgroundColor = bg
        layer.shadowOpacity = hasCap && !pressed ? 1 : 0
        let fg: UIColor = spec.style == .accent && !pressed ? Theme.accentText : Theme.keyText
        label.textColor = fg
        hintLabel.textColor = Theme.secondaryText
        icon.tintColor = fg
        layer.shadowColor = Theme.keyShadow.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let o = cjkPunctuationOffset(label.text, fontSize: label.font.pointSize)
        label.frame = bounds.insetBy(dx: 2, dy: 0).offsetBy(dx: o.x, dy: o.y)
        icon.frame = bounds
        // Digit hint in the cap's top-right corner (Gboard's hint, kept inside the iOS key cap).
        hintLabel.frame = CGRect(x: bounds.width - 16, y: 2, width: 12, height: 13)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Metrics.cornerRadius).cgPath
    }
}

/// Key popup shown above a pressed character key.
/// Optical centring for full-width CJK punctuation: 。，、 sit in the lower-left of their em box, so on a key
/// they look dropped and off to the side. Returns the offset that moves the glyph to the visual centre.
func cjkPunctuationOffset(_ text: String?, fontSize: CGFloat) -> CGPoint {
    guard let t = text, ["。", "，", "、", "．"].contains(t) else { return .zero }
    return CGPoint(x: fontSize * 0.22, y: -fontSize * 0.2)
}

/// The key-press balloon, shaped like the iOS keyboard's: a wider cap above the key that narrows through a
/// short neck into the key itself, so the pressed key appears to grow upwards rather than a box floating over it.
final class KeyPreview: UIView {
    let label = UILabel()
    private let shape = CAShapeLayer()
    private var capRect: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(shape)
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.28
        shape.shadowRadius = 2.5
        shape.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 32, weight: .medium)
        label.textColor = Theme.keyText
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `key`: the key's frame; `limit`: the horizontal room available (container bounds), both in container space.
    func place(over key: CGRect, within limit: CGRect) {
        let capW = max(key.width + 26, 52), capH = key.height * 1.12, neck: CGFloat = 10
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
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        for (i, o) in options.enumerated() {
            let slot = reversed ? options.count - 1 - i : i
            let shift = cjkPunctuationOffset(o, fontSize: 24)
            let l = UILabel(frame: CGRect(x: 4 + CGFloat(slot) * cell, y: 4, width: cell, height: height - 8))
            l.layer.sublayerTransform = CATransform3DMakeTranslation(shift.x, shift.y, 0)
            l.text = o
            l.textAlignment = .center
            l.font = .systemFont(ofSize: 24, weight: .medium)
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
            l.backgroundColor = i == selected ? Theme.accentKey : .clear
            l.textColor = i == selected ? Theme.accentText : Theme.keyText
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
    var onKeyDown: ((KeyAction) -> Void)?
    weak var inputController: UIInputViewController?

    let spatial: SpatialModel
    private(set) var context: LayoutContext?
    private var rows: [[KeySpec]] = []
    private var keyViews: [KeyView] = []
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
        var longPressTimer: Timer?
        var repeatTimer: Timer?
        var dragAccum: CGFloat = 0
        var dragging = false
        var lastMove = CACurrentMediaTime()
        let began = CACurrentMediaTime()
        var repeatCount = 0
        var preview: KeyPreview?
        init(keyIndex: Int, start: CGPoint) { self.keyIndex = keyIndex; self.start = start; self.location = start }
    }
    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private var touchOrder: [ObjectIdentifier] = []

    init(spatial: SpatialModel) {
        self.spatial = spatial
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        clipsToBounds = false
        backgroundColor = .clear
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
        guard !rows.isEmpty, bounds.width > 0 else { return }
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
    }

    // MARK: - Hit testing

    private func keyIndex(at p: CGPoint) -> Int? {
        if let i = hitRects.firstIndex(where: { $0.contains(p) }) { return i }
        // Outside every row band (e.g. dragged off the edge): nearest key.
        var best: Int?
        var bestD = CGFloat.infinity
        for (i, r) in hitRects.enumerated() {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let g = globeButton, g.frame.contains(point) { return g }
        return bounds.contains(point) ? self : nil
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            // Roll-over: a new finger finalises any character key still held down.
            for id in touchOrder {
                if let tr = tracked[id], tr.keyIndex < keyViews.count, !tr.altShown,
                   Self.rollsOver(keyViews[tr.keyIndex].spec.action) {
                    finish(tr, emit: true)
                    tracked[id] = nil
                }
            }
            touchOrder.removeAll { tracked[$0] == nil }
            if hitRects.count != keyViews.count { layoutIfNeeded() }
            let p = t.location(in: self)
            guard let idx = keyIndex(at: p), idx < keyViews.count else { continue }

            let tr = Tracked(keyIndex: idx, start: p)
            stats.began += 1
            let id = ObjectIdentifier(t)
            tracked[id] = tr
            touchOrder.append(id)
            let kv = keyViews[idx]
            kv.pressed = true
            onKeyDown?(kv.spec.action)
            switch kv.spec.action {
            case .char:
                showPreview(tr, text: kv.spec.label)
                if kv.spec.alt != nil {
                    tr.longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self, weak tr] _ in
                        guard let self, let tr else { return }
                        self.showAlt(tr)
                    }
                }
            case .delete:
                onAction?(.delete, nil)
                tr.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self, weak tr] _ in
                    guard let self, let tr else { return }
                    self.startDeleteRepeat(tr)
                }
            case .shift:
                onAction?(.shift, nil)
            default:
                break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let tr = tracked[ObjectIdentifier(t)], tr.keyIndex < keyViews.count else { continue }
            let p = t.location(in: self)
            let prev = tr.location
            tr.location = p
            let kv = keyViews[tr.keyIndex]
            switch kv.spec.action {
            case .space:
                // Drag on the space bar moves the cursor (Gboard / iOS trackpad): the caps go blank, one character
                // per ~9 pt when slow, finer steps when the finger moves fast, so a long jump needs no second swipe.
                let dx = p.x - prev.x
                let now = CACurrentMediaTime()
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
            case .char where tr.altShown:
                // the first choice stays selected until the finger actually slides
                if let popup = tr.altPopup, abs(p.x - tr.altAnchorX) > 6 { popup.selected = popup.index(at: p.x) }
            case .char where !tr.altShown:
                // Slide to a neighbouring character key before release.
                if let idx = keyIndex(at: p), idx < keyViews.count, idx != tr.keyIndex, case .char = keyViews[idx].spec.action {
                    kv.pressed = false
                    tr.longPressTimer?.invalidate()
                    tr.keyIndex = idx
                    keyViews[idx].pressed = true
                    showPreview(tr, text: keyViews[idx].spec.label)
                    if keyViews[idx].spec.alt != nil {
                        tr.longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: false) { [weak self, weak tr] _ in
                            guard let self, let tr else { return }
                            self.showAlt(tr)
                        }
                    }
                }
            default:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            guard let tr = tracked[id] else { continue }
            tr.location = t.location(in: self)
            finish(tr, emit: true)
            tracked[id] = nil
            touchOrder.removeAll { $0 == id }
        }
    }

    /// Keys a new finger finalises (characters and 九宫格 keys), so fast typing keeps the order it was typed in.
    private static func rollsOver(_ a: KeyAction) -> Bool {
        switch a { case .char, .t9: return true; default: return false }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // iOS cancels keyboard touches it suspects belong to a system gesture (screen edges, the bottom bar, a
        // fast stroke). A press on a character key or a tap on space that was cancelled is still a keystroke:
        // dropping it is what makes fast typing lose letters. Only a long-press menu or a cursor drag is abandoned.
        for t in touches {
            let id = ObjectIdentifier(t)
            guard let tr = tracked[id] else { continue }
            var keep = false
            if tr.keyIndex < keyViews.count {
                switch keyViews[tr.keyIndex].spec.action {
                case .char, .t9: keep = !tr.altShown
                case .space: keep = !tr.dragging
                default: keep = false
                }
            }
            finish(tr, emit: keep)
            if keep { stats.cancelKept += 1 } else { stats.dropped += 1 }
            tracked[id] = nil
            touchOrder.removeAll { $0 == id }
        }
    }

    private func cancelAllTouches() {
        for (_, tr) in tracked { finish(tr, emit: false); stats.dropped += 1 }
        tracked.removeAll()
        touchOrder.removeAll()
    }

    private func setCursorMode(_ on: Bool, except index: Int) {
        for (i, kv) in keyViews.enumerated() where i != index { kv.blanked = on }
    }

    private func finish(_ tr: Tracked, emit: Bool) {
        if tr.dragging { setCursorMode(false, except: -1) }
        tr.longPressTimer?.invalidate()
        tr.repeatTimer?.invalidate()
        tr.preview?.removeFromSuperview()
        tr.preview = nil
        let chosen = tr.altPopup?.selected ?? 0
        tr.altPopup?.removeFromSuperview()
        tr.altPopup = nil
        guard tr.keyIndex < keyViews.count else { return }
        let kv = keyViews[tr.keyIndex]
        kv.pressed = false
        guard emit else { return }
        stats.emitted += 1
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
        default:
            onAction?(kv.spec.action, nil)
        }
    }

    private func startDeleteRepeat(_ tr: Tracked) {
        tr.repeatCount = 0
        tr.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self, weak tr] _ in
            guard let self, let tr else { return }
            tr.repeatCount += 1
            self.onAction?(.delete, nil)
            if tr.repeatCount >= 25 { self.onAction?(.delete, nil) }   // accelerate after ~2s
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
        let tr = Tracked(keyIndex: idx, start: keyViews[idx].center)
        keyViews[idx].pressed = true
        showPreview(tr, text: keyViews[idx].spec.label)
    }

    // MARK: - Popups

    private func showPreview(_ tr: Tracked, text: String) {
        let kv = keyViews[tr.keyIndex]
        guard kv.spec.style == .normal || kv.spec.action == .char("，") || kv.spec.action == .char("。") || tr.altShown else { return }
        let p = tr.preview ?? KeyPreview(frame: .zero)
        p.label.text = text
        p.label.textColor = Theme.keyText
        if p.superview == nil { addSubview(p) }
        p.place(over: kv.frame, within: bounds)
        tr.preview = p
    }

    private func showAlt(_ tr: Tracked) {
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
        onKeyDown?(kv.spec.action)
    }
}
