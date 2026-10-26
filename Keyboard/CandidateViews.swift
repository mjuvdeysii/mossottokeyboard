import UIKit

/// Top strip: pinyin preedit + as many candidates as fit (no horizontal scrolling);
/// the chevron opens the full candidate grid.
final class CandidateBarView: UIView {
    var onSelect: ((Int) -> Void)?
    var onExpand: (() -> Void)?
    var onSettings: (() -> Void)?

    private let preedit = UILabel()
    private let row = UIView()
    private let expandButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private var labels: [UILabel] = []
    private var candidates: [Candidate] = []
    private(set) var visibleCount = 0
    private var pressedIndex: Int?

    static let font = UIFont.systemFont(ofSize: 20)
    /// Settings live on the bottom row (Gboard's gear position); the toolbar shows a gear only
    /// when that slot is taken by the system globe key.
    var showSettingsWhenIdle = false { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        preedit.font = .systemFont(ofSize: 14)
        preedit.textColor = Theme.secondaryText
        addSubview(preedit)
        addSubview(row)
        row.isUserInteractionEnabled = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        expandButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: cfg), for: .normal)
        settingsButton.setImage(UIImage(systemName: "gearshape", withConfiguration: cfg), for: .normal)
        for b in [expandButton, settingsButton] {
            b.tintColor = Theme.secondaryText
            addSubview(b)
        }
        expandButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        update(preedit: "", candidates: [])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func expandTapped() { onExpand?() }
    @objc private func settingsTapped() { onSettings?() }

    func update(preedit text: String, candidates: [Candidate]) {
        preedit.text = text
        self.candidates = candidates
        let composing = !candidates.isEmpty
        settingsButton.isHidden = composing || !showSettingsWhenIdle
        preedit.isHidden = !composing
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let preH: CGFloat = min(20, h * 0.3)
        preedit.frame = CGRect(x: 10, y: 2, width: bounds.width - 20, height: preH)
        settingsButton.frame = CGRect(x: 4, y: 0, width: 44, height: h)
        let rowY = preH
        let rowH = h - preH
        expandButton.frame = CGRect(x: bounds.width - 44, y: rowY, width: 44, height: rowH)
        row.frame = CGRect(x: 0, y: rowY, width: bounds.width - 44, height: rowH)

        labels.forEach { $0.removeFromSuperview() }
        labels.removeAll()
        var x: CGFloat = 6
        visibleCount = 0
        for (i, c) in candidates.enumerated() {
            let w = ceil((c.text as NSString).size(withAttributes: [.font: Self.font]).width) + 22
            if x + w > row.bounds.width && i > 0 { break }
            let l = UILabel(frame: CGRect(x: x, y: 0, width: min(w, row.bounds.width - x), height: rowH))
            l.font = Self.font
            l.textAlignment = .center
            l.lineBreakMode = .byTruncatingTail
            l.textColor = Theme.candidateText
            if i == 0 {
                // Auto-corrected first choice is marked, like Gboard.
                let attrs: [NSAttributedString.Key: Any] = c.corrected
                    ? [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.correctedMark, .font: UIFont.systemFont(ofSize: 20, weight: .semibold)]
                    : [.font: UIFont.systemFont(ofSize: 20, weight: .semibold)]
                l.attributedText = NSAttributedString(string: c.text, attributes: attrs)
            } else {
                l.text = c.text
            }
            if i == pressedIndex { l.backgroundColor = Theme.functionKey; l.layer.cornerRadius = 6; l.clipsToBounds = true }
            row.addSubview(l)
            labels.append(l)
            x += w
            visibleCount += 1
        }
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
        setNeedsLayout()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let idx = candidateIndex(at: t.location(in: self))
        let was = pressedIndex
        pressedIndex = nil
        setNeedsLayout()
        if let idx, idx == was { onSelect?(idx) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressedIndex = nil
        setNeedsLayout()
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
            contentView.backgroundColor = Theme.key
            contentView.layer.cornerRadius = 6
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = contentView.bounds.insetBy(dx: 4, dy: 0)
        }
        override var isHighlighted: Bool {
            didSet { contentView.backgroundColor = isHighlighted ? Theme.keyPressed : Theme.key }
        }
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = Theme.background
        collection.backgroundColor = .clear
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

/// In-keyboard settings (no App Group / full access needed to change them).
final class SettingsPanelView: UIView {
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?
    var onResetLearning: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let correctionSwitch = UISwitch()
    private let strength = UISegmentedControl(items: ["保守", "标准", "积极"])
    private let feedbackSwitch = UISwitch()
    private let bordersSwitch = UISwitch()
    private let note = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        stack.axis = .vertical
        stack.spacing = 10
        scroll.addSubview(stack)
        scroll.alwaysBounceHorizontal = false
        addSubview(scroll)

        let title = UILabel()
        title.text = "键盘设置"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = Theme.keyText
        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        done.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [title, UIView(), done])
        stack.addArrangedSubview(header)

        stack.addArrangedSubview(row("自动纠错（按触点位置）", correctionSwitch))
        stack.addArrangedSubview(row("纠错强度", strength))
        stack.addArrangedSubview(row("按键震动与音效", feedbackSwitch))
        stack.addArrangedSubview(row("按键边框", bordersSwitch))

        let reset = UIButton(type: .system)
        reset.setTitle("清空已学习的词语与触点习惯", for: .normal)
        reset.setTitleColor(.systemRed, for: .normal)
        reset.contentHorizontalAlignment = .leading
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        stack.addArrangedSubview(reset)

        note.numberOfLines = 0
        note.font = .systemFont(ofSize: 12)
        note.textColor = Theme.secondaryText
        stack.addArrangedSubview(note)

        correctionSwitch.addTarget(self, action: #selector(changed), for: .valueChanged)
        strength.addTarget(self, action: #selector(changed), for: .valueChanged)
        feedbackSwitch.addTarget(self, action: #selector(changed), for: .valueChanged)
        bordersSwitch.addTarget(self, action: #selector(changed), for: .valueChanged)
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func row(_ text: String, _ control: UIView) -> UIView {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 15)
        l.textColor = Theme.keyText
        l.numberOfLines = 0
        let s = UIStackView(arrangedSubviews: [l, control])
        s.alignment = .center
        s.spacing = 12
        return s
    }

    func load() {
        let s = KeyboardSettings.shared
        correctionSwitch.isOn = s.autocorrect
        strength.selectedSegmentIndex = s.strength
        strength.isEnabled = s.autocorrect
        feedbackSwitch.isOn = s.feedback
        bordersSwitch.isOn = s.keyBorders
    }

    func setNote(_ text: String) { note.text = text }

    @objc private func changed() {
        let s = KeyboardSettings.shared
        s.autocorrect = correctionSwitch.isOn
        s.strength = strength.selectedSegmentIndex
        s.feedback = feedbackSwitch.isOn
        s.keyBorders = bordersSwitch.isOn
        strength.isEnabled = s.autocorrect
        onChange?()
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func resetTapped() { onResetLearning?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let w = bounds.width - 32
        let size = stack.systemLayoutSizeFitting(CGSize(width: w, height: 0),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: 16, y: 10, width: w, height: size.height)
        scroll.contentSize = CGSize(width: bounds.width, height: size.height + 20)
    }
}

final class KeyboardSettings {
    static let shared = KeyboardSettings()
    private let d = UserDefaults.standard

    var autocorrect: Bool {
        get { d.object(forKey: "autocorrect") as? Bool ?? true }
        set { d.set(newValue, forKey: "autocorrect") }
    }
    var strength: Int {
        get { d.object(forKey: "strength") as? Int ?? 1 }
        set { d.set(newValue, forKey: "strength") }
    }
    /// Off = Gboard's borderless keys; on = classic iOS key caps.
    var keyBorders: Bool {
        get { d.object(forKey: "keyBorders") as? Bool ?? false }
        set { d.set(newValue, forKey: "keyBorders") }
    }
    var feedback: Bool {
        get { d.object(forKey: "feedback") as? Bool ?? true }
        set { d.set(newValue, forKey: "feedback") }
    }
    var touchOffset: (Double, Double) {
        get { (d.double(forKey: "offsetX"), d.double(forKey: "offsetY")) }
        set { d.set(newValue.0, forKey: "offsetX"); d.set(newValue.1, forKey: "offsetY") }
    }
}
