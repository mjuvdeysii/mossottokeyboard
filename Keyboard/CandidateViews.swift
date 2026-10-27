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
    private var isPrediction = false
    private var candidates: [Candidate] = []
    private(set) var visibleCount = 0
    private var pressedIndex: Int?
    /// Mosto in the idle corner: at night only (by day it lives in settings).
    var showsMosto = false { didSet { update(preedit: preedit.text ?? "", candidates: candidates, prediction: isPrediction) } }
    /// Pinyin above the candidates (when it is not written into the text field).
    var showsPreedit = false { didSet { setNeedsLayout() } }

    static let font = UIFont.systemFont(ofSize: 20)

    override init(frame: CGRect) {
        super.init(frame: frame)
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
        mosto.isHidden = busy || !showsMosto
        preedit.isHidden = !busy || prediction || !showsPreedit
        setNeedsLayout()
        layoutIfNeeded()
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
            if i == 0 && !isPrediction && c.corrected {
                // an auto-corrected first choice is underlined (the only mark the system bar does not have)
                l.attributedText = NSAttributedString(string: c.text, attributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.correctedMark, .font: Self.font])
            } else {
                l.text = c.text
            }
            if i == pressedIndex { l.backgroundColor = Theme.functionKey; l.layer.cornerRadius = 8; l.clipsToBounds = true }
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
        backgroundColor = .clear   // on the system glass, like the keys (the keys are hidden while it shows)
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
    private let mostoImage = UIImageView()
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    private let schemeControl = UISegmentedControl(items: ["小鹤双拼", "全拼"])
    private let layoutControl = UISegmentedControl(items: ["全键盘", "九宫格"])
    private let englishSwitch = UISwitch()
    private let predictionSwitch = UISwitch()
    private let inlineControl = UISegmentedControl(items: ["首选", "拼音", "不显示"])
    private let correctionSwitch = UISwitch()
    private let strength = UISegmentedControl(items: ["保守", "标准", "积极"])
    private let numberControl = UISegmentedControl(items: ["九宫格", "全键盘"])
    private let bordersSwitch = UISwitch()
    private let feedbackSwitch = UISwitch()
    private let appearance = UISegmentedControl(items: ["自动", "日光", "夜灯"])
    private let learnedLabel = UILabel()
    private let note = UILabel()
    private var groups: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear   // the system glass shows through, so the panel is one layer with the keyboard

        // Header: Mosto (day or night), the name, 完成 — fixed above the scrolling list
        mostoImage.contentMode = .scaleAspectFit
        mostoImage.image = UIImage(named: "mosto_day", in: Bundle(for: SettingsPanelView.self), with: nil)
        let title = UILabel()
        title.text = "Mosto键盘"
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = Theme.keyText
        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        done.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let h = UIStackView(arrangedSubviews: [mostoImage, title, UIView(), done])
        h.alignment = .center
        h.spacing = 8
        mostoImage.widthAnchor.constraint(equalToConstant: 34).isActive = true
        mostoImage.heightAnchor.constraint(equalToConstant: 34).isActive = true
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
            row("联想", predictionSwitch),
            row("输入框中显示", inlineControl),
        ], footer: "中文键盘：九宫格时每个键代表它上面的几个字母，小鹤双拼与全拼都能用（全拼更准）；分词键用来切开音节。中英混输：打 ok、ios 直接出 OK、iOS。输入框中显示：打字时把首选结果（或拼音）先写进输入框，带下划线，候选栏不再被拼音挤占；选“不显示”则拼音显示在候选栏上方。")
        section("自动纠错", rows: [
            row("按触点位置纠错", correctionSwitch),
            row("强度", strength),
        ], footer: "首选带下划线 = 已纠错；上屏后立刻按删除可撤回这次纠错。")
        section("键盘", rows: [
            row("数字键盘", numberControl),
            row("显示键帽", bordersSwitch),
            row("按键震动与按键音", feedbackSwitch),
        ], footer: nil)
        section("外观", rows: [row("外观", appearance)], footer: "自动：跟随系统的浅色 / 深色模式。夜灯：深夜蓝底色，Mosto 待在候选栏左边，尾巴尖亮起金光。")

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

        note.numberOfLines = 0
        note.font = .systemFont(ofSize: 12)
        note.textColor = Theme.secondaryText
        stack.addArrangedSubview(inset(note))

        for c in [schemeControl, layoutControl, inlineControl, strength, numberControl, appearance] {
            c.addTarget(self, action: #selector(changed), for: .valueChanged)
            c.setContentHuggingPriority(.required, for: .horizontal)
        }
        for sw in [englishSwitch, predictionSwitch, correctionSwitch, bordersSwitch, feedbackSwitch] {
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
    }

    func load() {
        let s = KeyboardSettings.shared
        schemeControl.selectedSegmentIndex = s.scheme
        layoutControl.selectedSegmentIndex = s.pinyinGrid ? 1 : 0
        englishSwitch.isOn = s.english
        predictionSwitch.isOn = s.predictions
        inlineControl.selectedSegmentIndex = s.inlineMode
        correctionSwitch.isOn = s.autocorrect
        strength.selectedSegmentIndex = s.strength
        strength.isEnabled = s.autocorrect
        numberControl.selectedSegmentIndex = s.numberGrid ? 0 : 1
        bordersSwitch.isOn = s.keyBorders
        feedbackSwitch.isOn = s.feedback
        appearance.selectedSegmentIndex = s.appearance
    }

    func setNote(_ text: String) { note.text = text }
    func setLearned(_ text: String) { learnedLabel.text = text }

    @objc private func changed() {
        let s = KeyboardSettings.shared
        s.scheme = schemeControl.selectedSegmentIndex
        s.pinyinGrid = layoutControl.selectedSegmentIndex == 1
        s.english = englishSwitch.isOn
        s.predictions = predictionSwitch.isOn
        s.inlineMode = inlineControl.selectedSegmentIndex
        s.autocorrect = correctionSwitch.isOn
        s.strength = strength.selectedSegmentIndex
        s.numberGrid = numberControl.selectedSegmentIndex == 0
        s.keyBorders = bordersSwitch.isOn
        s.feedback = feedbackSwitch.isOn
        s.appearance = appearance.selectedSegmentIndex
        strength.isEnabled = s.autocorrect
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
    var strength: Int {
        get { d.object(forKey: "strength") as? Int ?? 1 }
        set { d.set(newValue, forKey: "strength") }
    }
    /// On = iOS 26 key caps (default); off = Gboard's borderless keys.
    var keyBorders: Bool {
        get { d.object(forKey: "keyCaps") as? Bool ?? true }
        set { d.set(newValue, forKey: "keyCaps") }
    }
    /// 中英混输: English words offered among the Chinese candidates.
    var english: Bool {
        get { d.object(forKey: "english") as? Bool ?? true }
        set { d.set(newValue, forKey: "english") }
    }
    /// What is written into the text field while composing (underlined marked text):
    /// 0 the first candidate (default), 1 the pinyin (as the system keyboard), 2 nothing (pinyin above the candidates).
    var inlineMode: Int {
        get { d.object(forKey: "inlineMode") as? Int ?? 0 }
        set { d.set(newValue, forKey: "inlineMode") }
    }
    /// Chinese typed on the 九宫格 pinyin keypad (on) or the full keyboard (off).
    var pinyinGrid: Bool {
        get { d.object(forKey: "pinyinGrid") as? Bool ?? false }
        set { d.set(newValue, forKey: "pinyinGrid") }
    }
    /// 123 opens the 九宫格 number pad (default) or the full 123 page.
    var numberGrid: Bool {
        get { d.object(forKey: "numberGrid") as? Bool ?? true }
        set { d.set(newValue, forKey: "numberGrid") }
    }
    var predictions: Bool {
        get { d.object(forKey: "predictions") as? Bool ?? true }
        set { d.set(newValue, forKey: "predictions") }
    }
    /// 0 自动 (follows the system's light / dark mode), 1 日光, 2 夜灯. (The old 3 "晚上" reads as 自动.)
    var appearance: Int {
        get { min(d.object(forKey: "appearance") as? Int ?? 0, 3) % 3 }
        set { d.set(newValue, forKey: "appearance") }
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
