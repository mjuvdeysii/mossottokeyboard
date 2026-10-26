import UIKit

final class KeyView: UIView {
    private(set) var spec: KeySpec
    private let label = UILabel()
    private let icon = UIImageView()

    var pressed = false { didSet { if pressed != oldValue { updateColors() } } }

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 1
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        icon.contentMode = .center
        addSubview(label)
        addSubview(icon)
        apply(spec)
    }

    /// Update label / icon / style without recreating the view (keeps touches alive).
    func apply(_ spec: KeySpec) {
        self.spec = spec
        label.text = spec.label
        switch spec.action {
        case .char where spec.isLetter: label.font = .systemFont(ofSize: 23, weight: .regular)
        case .char: label.font = .systemFont(ofSize: 21, weight: .regular)
        case .space: label.font = .systemFont(ofSize: 15, weight: .regular)
        default: label.font = .systemFont(ofSize: 16, weight: .regular)
        }
        if let name = spec.symbol {
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
            icon.isHidden = false
        } else {
            icon.image = nil
            icon.isHidden = true
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateColors() {
        let bg: UIColor
        switch spec.style {
        case .normal: bg = pressed ? Theme.keyPressed : Theme.key
        case .function: bg = pressed ? Theme.key : Theme.functionKey
        case .accent: bg = pressed ? Theme.functionKey : Theme.accentKey
        }
        backgroundColor = bg
        let fg: UIColor = spec.style == .accent && !pressed ? .white : Theme.keyText
        label.textColor = fg
        icon.tintColor = fg
        layer.shadowColor = Theme.keyShadow.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 0)
        icon.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 5).cgPath
    }
}

/// Key popup shown above a pressed character key.
final class KeyPreview: UIView {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = Theme.key
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 30)
        label.textColor = Theme.keyText
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}

/// Draws the keys and handles every touch itself (no UIButton per key), so a key
/// reacts on the first touch event, gaps between keys still hit the nearest key,
/// and fast two-thumb typing rolls over instead of dropping letters.
final class KeyboardView: UIView {
    var onAction: ((KeyAction, Tap?) -> Void)?
    var onCursorMove: ((Int) -> Void)?
    var onKeyDown: (() -> Void)?
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
        var longPressTimer: Timer?
        var repeatTimer: Timer?
        var dragAccum: CGFloat = 0
        var dragging = false
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

    func configure(_ ctx: LayoutContext) {
        let newRows = Layouts.rows(ctx)
        let sameShape = newRows.count == rows.count && zip(newRows, rows).allSatisfy { a, b in
            a.count == b.count && zip(a, b).allSatisfy { $0.width == $1.width && $0.action == $1.action }
        }
        context = ctx
        rows = newRows
        if sameShape && keyViews.count == newRows.reduce(0, { $0 + $1.count }) {
            // Labels only (shift state, return key title): update in place so in-flight touches survive.
            for (kv, spec) in zip(keyViews, newRows.flatMap { $0 }) { kv.apply(spec) }
        } else {
            rebuild()
        }
    }

    private func rebuild() {
        cancelAllTouches()
        keyViews.forEach { $0.removeFromSuperview() }
        globeButton?.removeFromSuperview()
        globeButton = nil
        keyViews = rows.flatMap { $0 }.map { KeyView(spec: $0) }
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
        let rowH = bounds.height / CGFloat(rows.count)
        let unit = bounds.width / 10
        let gapX: CGFloat = 6
        let gapY: CGFloat = min(12, rowH * 0.22)
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
                let y = CGFloat(r) * rowH
                let frame = CGRect(x: x * unit + gapX / 2, y: y + gapY / 2, width: w * unit - gapX, height: rowH - gapY)
                keyViews[i].frame = frame
                var hit = CGRect(x: x * unit, y: y, width: w * unit, height: rowH)
                if j == 0 { hit = CGRect(x: 0, y: y, width: hit.maxX, height: rowH) }
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
                if let tr = tracked[id], tr.keyIndex < keyViews.count,
                   case .char = keyViews[tr.keyIndex].spec.action, !tr.altShown {
                    finish(tr, emit: true)
                    tracked[id] = nil
                }
            }
            touchOrder.removeAll { tracked[$0] == nil }
            if hitRects.count != keyViews.count { layoutIfNeeded() }
            let p = t.location(in: self)
            guard let idx = keyIndex(at: p), idx < keyViews.count else { continue }

            let tr = Tracked(keyIndex: idx, start: p)
            let id = ObjectIdentifier(t)
            tracked[id] = tr
            touchOrder.append(id)
            let kv = keyViews[idx]
            kv.pressed = true
            onKeyDown?()
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
                // Drag on the space bar moves the cursor.
                let dx = p.x - prev.x
                if !tr.dragging && abs(p.x - tr.start.x) > 14 { tr.dragging = true }
                if tr.dragging {
                    tr.dragAccum += dx
                    let step: CGFloat = 9
                    while abs(tr.dragAccum) >= step {
                        let dir = tr.dragAccum > 0 ? 1 : -1
                        onCursorMove?(dir)
                        tr.dragAccum -= CGFloat(dir) * step
                    }
                }
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

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            guard let tr = tracked[id] else { continue }
            finish(tr, emit: false)
            tracked[id] = nil
            touchOrder.removeAll { $0 == id }
        }
    }

    private func cancelAllTouches() {
        for (_, tr) in tracked { finish(tr, emit: false) }
        tracked.removeAll()
        touchOrder.removeAll()
    }

    private func finish(_ tr: Tracked, emit: Bool) {
        tr.longPressTimer?.invalidate()
        tr.repeatTimer?.invalidate()
        tr.preview?.removeFromSuperview()
        tr.preview = nil
        guard tr.keyIndex < keyViews.count else { return }
        let kv = keyViews[tr.keyIndex]
        kv.pressed = false
        guard emit else { return }
        switch kv.spec.action {
        case .char(let s):
            if tr.altShown, let alt = kv.spec.alt {
                onAction?(.char(alt), nil)
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

    // MARK: - Popups

    private func showPreview(_ tr: Tracked, text: String) {
        let kv = keyViews[tr.keyIndex]
        guard kv.spec.style == .normal || kv.spec.action == .char("，") || kv.spec.action == .char("。") else { return }
        let f = kv.frame
        let w = max(f.width + 14, 46), h = f.height * 1.05
        var x = f.midX - w / 2
        x = min(max(2, x), bounds.width - w - 2)
        let frame = CGRect(x: x, y: f.minY - h - 4, width: w, height: h)
        let p = tr.preview ?? KeyPreview(frame: frame)
        p.frame = frame
        p.label.text = text
        p.label.textColor = Theme.keyText
        if p.superview == nil { addSubview(p) }
        tr.preview = p
    }

    private func showAlt(_ tr: Tracked) {
        let kv = keyViews[tr.keyIndex]
        guard let alt = kv.spec.alt else { return }
        tr.altShown = true
        showPreview(tr, text: alt)
        tr.preview?.label.textColor = Theme.correctedMark
        onKeyDown?()
    }
}
