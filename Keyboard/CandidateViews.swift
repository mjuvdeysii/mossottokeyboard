import UIKit

/// Top strip, as on the system keyboard: as many candidates as fit (no horizontal scrolling) and a chevron that
/// opens the full grid. Idle it stays empty — only at night Mosto sits at its left, tail tip glowing.
/// The pinyin is written into the text field as marked text; with that turned off it shows above the candidates.
final class CandidateBarView: UIView {
    var onSelect: ((Int) -> Void)?
    var onExpand: (() -> Void)?
    var onSettings: (() -> Void)?
    /// Long press on a candidate (to offer removing a learned word).
    var onLongPress: ((Int) -> Void)?

    private let preedit = UILabel()
    private var longPressTimer: Timer?
    private var longPressed = false
    private let row = UIView()
    private let expandButton = UIButton(type: .system)
    let mosto = MostoView()
    private var labels: [UILabel] = []
    private var pool: [UILabel] = []
    private var isPrediction = false
    private var candidates: [Candidate] = []
    private(set) var visibleCount = 0
    private var pressedIndex: Int?
    /// Mosto in the idle corner, by day and at night alike (only his light changes with the keyboard's).
    var showsMosto = false { didSet { update(preedit: preedit.text ?? "", candidates: candidates, prediction: isPrediction) } }
    private var mostoWanted = false
    private var mostoTimer: Timer?
    /// Pinyin above the candidates (when it is not written into the text field).
    var showsPreedit = false { didSet { setNeedsLayout() } }

    static let font = UIFont.systemFont(ofSize: 20)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.touchable   // never fully clear: see Theme.touchable
        preedit.font = .systemFont(ofSize: 14)
        preedit.textColor = Theme.secondaryText
        addSubview(preedit)
        addSubview(row)
        row.isUserInteractionEnabled = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        expandButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: cfg), for: .normal)
        expandButton.tintColor = Theme.secondaryText
        addSubview(expandButton)
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        // Mosto sits in the idle corner; a tap opens settings (also reachable from the ⚙︎ key)
        addSubview(mosto)
        mosto.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(settingsTapped)))
        update(preedit: "", candidates: [])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func expandTapped() { onExpand?() }
    @objc private func settingsTapped() { onSettings?() }

    /// `prediction`: the row shows next-word suggestions (联想) rather than candidates for typed keys.
    func update(preedit text: String, candidates: [Candidate], prediction: Bool = false) {
        preedit.text = text
        self.candidates = candidates
        isPrediction = prediction
        let busy = !candidates.isEmpty
        setMosto(!busy && showsMosto)
        preedit.isHidden = !busy || prediction || !showsPreedit
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Mosto steps aside the moment typing starts (the strip is for candidates) and comes back only when the
    /// keyboard has been idle a moment, fading in rather than popping up — never flickering between words.
    private func setMosto(_ on: Bool) {
        guard on != mostoWanted else { return }
        mostoWanted = on
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
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let preH: CGFloat = showsPreedit ? min(20, h * 0.3) : 0
        preedit.frame = CGRect(x: 10, y: 2, width: bounds.width - 20, height: preH)
        let ms = min(h - 12, 46)
        mosto.frame = CGRect(x: 10, y: (h - ms) / 2 + 2, width: ms, height: ms)
        let rowY = preH
        let rowH = h - preH
        expandButton.frame = CGRect(x: bounds.width - 44, y: rowY, width: 44, height: rowH)
        row.frame = CGRect(x: 0, y: rowY, width: bounds.width - 44, height: rowH)

        // labels are pooled and reused (this runs on every keystroke): only text and frames change
        var x: CGFloat = 6
        visibleCount = 0
        for (i, c) in candidates.enumerated() {
            // at least a 44 pt target, as Apple's guidelines ask (single characters were ~40 pt)
            let w = max(44, ceil((c.text as NSString).size(withAttributes: [.font: Self.font]).width) + 22)
            if x + w > row.bounds.width && i > 0 { break }
            if pool.count <= i {
                let l = UILabel()
                l.font = Self.font
                l.textAlignment = .center
                l.lineBreakMode = .byTruncatingTail
                l.layer.cornerRadius = 8
                l.clipsToBounds = true
                row.addSubview(l)
                pool.append(l)
            }
            let l = pool[i]
            l.isHidden = false
            l.frame = CGRect(x: x, y: 0, width: min(w, row.bounds.width - x), height: rowH)
            l.textColor = Theme.candidateText
            if i == 0 && !isPrediction && c.corrected {
                // an auto-corrected first choice is underlined (the only mark the system bar does not have)
                l.attributedText = NSAttributedString(string: c.text, attributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.correctedMark,
                    .font: Self.font, .foregroundColor: Theme.candidateText])
            } else {
                l.attributedText = nil
                l.text = c.text
            }
            l.backgroundColor = i == pressedIndex ? Theme.functionKey : .clear
            x += w
            visibleCount += 1
        }
        for l in pool.dropFirst(visibleCount) { l.isHidden = true }
        labels = Array(pool.prefix(visibleCount))
        expandButton.isHidden = candidates.count <= visibleCount
    }

    private func candidateIndex(at p: CGPoint) -> Int? {
        let q = convert(p, to: row)
        guard q.y >= -8, q.x < row.bounds.width else { return nil }
        return labels.firstIndex { $0.frame.minX <= q.x && q.x < $0.frame.maxX }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        pressedIndex = candidateIndex(at: t.location(in: self))
        longPressed = false
        longPressTimer?.invalidate()
        if let idx = pressedIndex, !isPrediction {
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self, self.pressedIndex == idx else { return }
                self.longPressed = true
                self.pressedIndex = nil
                self.setNeedsLayout()
                self.onLongPress?(idx)
            }
        }
        setNeedsLayout()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.invalidate()
        guard let t = touches.first, !longPressed else { longPressed = false; return }
        let idx = candidateIndex(at: t.location(in: self))
        let was = pressedIndex
        pressedIndex = nil
        setNeedsLayout()
        if let idx, idx == was { onSelect?(idx) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.invalidate()
        pressedIndex = nil
        setNeedsLayout()
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
        }
        required init?(coder: NSCoder) { fatalError() }
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
            b.tintColor = Theme.keyText
            b.backgroundColor = Theme.functionKey
            b.layer.cornerRadius = 6
            addSubview(b)
        }
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
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
    private let englishSwitch = UISwitch()
    private let correctionSwitch = UISwitch()
    private let feedbackSwitch = UISwitch()
    private let soundSwitch = UISwitch()
    private let appearance = UISegmentedControl(items: ["自动", "日光", "夜灯"])
    private let learnedLabel = UILabel()
    private let diagLabel = UILabel()
    private let note = UILabel()
    private var groups: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.touchable   // the system glass shows through (never fully clear: see Theme.touchable)

        // Header: Mosto (day or night), the name, 完成 — fixed above the scrolling list
        mostoImage.contentMode = .scaleAspectFit
        mostoImage.image = UIImage(named: "mosto_day", in: Bundle(for: SettingsPanelView.self), with: nil)
        let title = UILabel()
        title.text = "Mosto键盘"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = Theme.keyText
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Theme.secondaryText
        let titles = UIStackView(arrangedSubviews: [title, statusLabel])
        titles.axis = .vertical
        titles.spacing = 1
        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
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
            row("中英混输", englishSwitch),
        ], footer: "中文键盘：九宫格时每个键代表它上面的几个字母，小鹤双拼与全拼都能用（全拼更准）；分词键用来切开音节。打字时按下的字母写进输入框，带下划线，选了候选才替换成汉字。中英混输：打 ok、ios 直接出 OK、iOS。")
        section("自动纠错", rows: [
            row("按触点位置纠错", correctionSwitch),
        ], footer: "首选带下划线 = 已纠错；上屏后立刻按删除可撤回这次纠错。英文模式同样按触点纠错：teh → the、dont → don't、im → I'm，空格时替换，删除可撤回。")
        section("键盘", rows: [
            row("按键震动", feedbackSwitch),
            row("按键音", soundSwitch),
        ], footer: "震动与按键音在按下的一瞬间发出（与系统键盘一样）；按键音跟随静音开关。")
        section("外观", rows: [row("光线", appearance)], footer: "自动：跟随系统的浅色 / 深色模式。Mosto 不打字时待在候选栏左边：日光下睁大眼睛、偶尔眨眼；夜灯下深夜蓝底色，尾巴尖亮起灯珠的金光。")

        learnedLabel.font = .systemFont(ofSize: 15)
        learnedLabel.textColor = Theme.secondaryText
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
        diagLabel.numberOfLines = 0
        section("诊断", rows: [diagLabel], footer: "打一段字后打开这里：“丢弃”是被系统取消、没能输入的按键；“按键响应”是每次按键在主线程上花的时间（字母按下即上屏），“候选出现”是按键到候选显示出来的时间（在后台线程解码）。")

        note.numberOfLines = 0
        note.font = .systemFont(ofSize: 12)
        note.textColor = Theme.secondaryText
        stack.addArrangedSubview(inset(note))

        for c in [schemeControl, layoutControl, appearance] {
            c.addTarget(self, action: #selector(changed), for: .valueChanged)
            c.setContentHuggingPriority(.required, for: .horizontal)
        }
        for sw in [englishSwitch, correctionSwitch, feedbackSwitch, soundSwitch] {
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
        let capWrap = inset(cap)
        stack.addArrangedSubview(capWrap)
        stack.setCustomSpacing(4, after: capWrap)

        let group = UIView()
        group.backgroundColor = Theme.settingsGroup
        group.layer.cornerRadius = 12
        group.layer.cornerCurve = .continuous
        let inner = UIStackView()
        inner.axis = .vertical
        for (i, r) in rows.enumerated() {
            if i > 0 {
                let line = UIView()
                line.backgroundColor = Theme.separator
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
        l.numberOfLines = 0
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        let s = UIStackView(arrangedSubviews: [l, UIView(), control])
        s.alignment = .center
        s.spacing = 10
        return s
    }

    /// Mosto in the header shows the light the keyboard is in.
    func setNight(_ night: Bool) {
        mostoImage.image = UIImage(named: night ? "mosto_night" : "mosto_day", in: Bundle(for: SettingsPanelView.self), with: nil)
        updateStatus(night: night)
    }

    /// The line under the name: the light, the scheme and the layout in use, at a glance.
    private func updateStatus(night: Bool? = nil) {
        let s = KeyboardSettings.shared
        let light = night.map { $0 ? "夜灯" : "日光" } ?? (["自动", "日光", "夜灯"][s.appearance])
        statusLabel.text = "\(light) · \(s.scheme == 0 ? "小鹤双拼" : "全拼") · \(s.pinyinGrid ? "九宫格" : "全键盘")"
    }

    func load() {
        let s = KeyboardSettings.shared
        updateStatus()
        schemeControl.selectedSegmentIndex = s.scheme
        layoutControl.selectedSegmentIndex = s.pinyinGrid ? 1 : 0
        englishSwitch.isOn = s.english
        correctionSwitch.isOn = s.autocorrect
        feedbackSwitch.isOn = s.feedback
        soundSwitch.isOn = s.keySound
        appearance.selectedSegmentIndex = s.appearance
    }

    func setNote(_ text: String) { note.text = text }
    func setLearned(_ text: String) { learnedLabel.text = text }
    func setDiagnostics(_ text: String) { diagLabel.text = text }

    @objc private func changed() {
        let s = KeyboardSettings.shared
        s.scheme = schemeControl.selectedSegmentIndex
        s.pinyinGrid = layoutControl.selectedSegmentIndex == 1
        s.english = englishSwitch.isOn
        s.autocorrect = correctionSwitch.isOn
        s.feedback = feedbackSwitch.isOn
        s.keySound = soundSwitch.isOn
        s.appearance = appearance.selectedSegmentIndex
        updateStatus()
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

    /// 0 小鹤双拼, 1 全拼 (PinyinScheme raw value)
    var scheme: Int {
        get { d.object(forKey: "scheme") as? Int ?? 0 }
        set { d.set(newValue, forKey: "scheme") }
    }
    var autocorrect: Bool {
        get { d.object(forKey: "autocorrect") as? Bool ?? true }
        set { d.set(newValue, forKey: "autocorrect") }
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
    /// 0 自动 (follows the system's light / dark mode), 1 日光, 2 夜灯. (The old 3 "晚上" reads as 自动.)
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
        backgroundColor = Theme.functionKey
        layer.cornerRadius = Metrics.cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        scroll.contentInsetAdjustmentBehavior = .never
        addSubview(scroll)
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Buttons are kept and relabelled (this runs on every keypad key), never rebuilt.
    func show(_ choices: [String]) {
        while buttons.count < choices.count {
            let b = UIButton(type: .system)
            b.titleLabel?.font = .systemFont(ofSize: 17)
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
