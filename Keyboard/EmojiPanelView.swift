import UIKit

/// 表情: the emoji page, as the iOS / Gboard emoji keyboards — every emoji in the Unicode order under the iOS
/// categories, with 常用 (recently used) first. It scrolls vertically only; the category bar along the bottom jumps
/// to a category and follows the scrolling. Emoji newer than this iOS can draw are left out.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onEmoji: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onBack: (() -> Void)?
    var onSettings: (() -> Void)?

    struct Category { let name: String; let symbol: String; var items: [String] }

    /// Section 0 is 常用; the rest are the file's categories.
    private var sections: [Category] = []
    private let collection: UICollectionView
    private let titleLabel = UILabel()
    private let bar = UIStackView()
    private var tabButtons: [UIButton] = []
    private let backButton = UIButton(type: .custom)   // custom: its title always draws (a .system title stayed blank)
    private let deleteButton = UIButton(type: .system)
    private var selected = -1
    private var deleteTimer: Timer?

    static let categoryNames: [(String, String)] = [
        ("笑脸与人物", "face.smiling"), ("动物与自然", "pawprint"), ("食物与饮料", "fork.knife"), ("活动", "soccerball"),
        ("旅行与地点", "car"), ("物品", "lightbulb"), ("符号", "heart"), ("旗帜", "flag"),
    ]

    /// Mosto 的颜文字: the last tab, under Mosto's own face — the little devil's ψ(｀∇´)ψ first, then the everyday ones.
    /// Text, so they go into any field; three to a row.
    static let kaomojiName = "Mosto 颜文字"
    static let kaomoji: [String] = [
        "ψ(｀∇´)ψ", "(｀∀´)Ψ", "Ψ(￣∀￣)Ψ", "ψ(._. )>", "(¬‿¬)", "(￣y▽￣)╭",
        "(＾▽＾)", "(๑•̀ㅂ•́)و✧", "(｡•̀ᴗ-)✧", "ヾ(≧▽≦*)o", "(*/ω＼*)", "(⁄ ⁄•⁄ω⁄•⁄ ⁄)",
        "(╯°□°）╯︵ ┻━┻", "┬─┬ノ( º _ ºノ)", "¯\\_(ツ)_/¯", "(ಥ_ಥ)", "(T_T)", "QAQ",
        "(・ω・)", "(｡･ω･｡)", "(=^･ω･^=)", "ʕ•ᴥ•ʔ", "(≧∇≦)ﾉ", "(●'◡'●)",
        "(✿◠‿◠)", "o(*￣▽￣*)ブ", "(っ´▽`)っ", "(づ｡◕‿‿◕｡)づ", "(ง •_•)ง", "ᕦ(ò_óˇ)ᕤ",
        "( •̀ ω •́ )✧", "(⊙ˍ⊙)", "Σ(っ °Д °;)っ", "(╬▔皿▔)╯", "(ノへ￣、)", "(´▽`ʃ♡ƪ)",
        "♪(´▽｀)", "(～﹃～)~zZ", "(￣︶￣)↗", "(^_−)☆", "(´･ω･`)", "_(:з」∠)_",
        "(～￣▽￣)～", "щ(ﾟДﾟщ)", "(×_×)", "(〃＾▽＾〃)", "(´∀｀)♡", "(๑•́ ₃ •̀๑)",
    ]

    final class Cell: UICollectionViewCell {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 30)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            contentView.addSubview(label)
            contentView.layer.cornerRadius = 8
            contentView.layer.cornerCurve = .continuous
            isAccessibilityElement = true
            accessibilityTraits = .keyboardKey
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = contentView.bounds
        }
        override var isHighlighted: Bool {
            didSet { contentView.backgroundColor = isHighlighted ? Theme.functionKey : .clear }
        }
    }

    final class Header: UICollectionReusableView {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = Theme.secondaryText
            addSubview(label)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = bounds.insetBy(dx: 10, dy: 0)
        }
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 6, right: 4)
        layout.sectionHeadersPinToVisibleBounds = false
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = .clear   // on the system glass, like the keys
        collection.backgroundColor = .clear
        collection.contentInsetAdjustmentBehavior = .never
        collection.alwaysBounceHorizontal = false
        collection.showsHorizontalScrollIndicator = false
        collection.delaysContentTouches = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(Cell.self, forCellWithReuseIdentifier: "e")
        collection.register(Header.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "h")
        addSubview(collection)

        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        backButton.setTitle("ABC", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 16)
        backButton.setTitleColor(Theme.keyText, for: .normal)
        backButton.setTitleColor(Theme.secondaryText, for: .highlighted)
        backButton.accessibilityLabel = "返回键盘"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
        // delete repeats while held, as the delete key does
        deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        for b in [backButton, deleteButton] {
            b.tintColor = Theme.keyText
            b.setTitleColor(Theme.keyText, for: .normal)
            b.backgroundColor = Theme.functionKey
            b.layer.cornerRadius = 8
            b.layer.cornerCurve = .continuous
            addSubview(b)
        }
        bar.axis = .horizontal
        bar.distribution = .fillEqually
        addSubview(bar)
        let tabCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        for (i, (name, symbol)) in ([("常用", "clock")] + Self.categoryNames).enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol, withConfiguration: tabCfg), for: .normal)
            b.tintColor = Theme.secondaryText
            b.tag = i
            b.accessibilityLabel = name
            b.layer.cornerRadius = 7
            b.layer.cornerCurve = .continuous
            b.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            bar.addArrangedSubview(b)
            tabButtons.append(b)
        }
        // the last tab: Mosto's face (his 颜文字)
        let mosto = UIButton(type: .custom)
        // drawn at the size of the other tab icons (a 24 pt face), so the button needs no insets
        if let face = UIImage(named: "mosto_day", in: Bundle(for: EmojiPanelView.self), with: nil) {
            let side: CGFloat = 24
            let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
                let scale = min(side / face.size.width, side / face.size.height)
                let w = face.size.width * scale, h = face.size.height * scale
                face.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            }
            mosto.setImage(small, for: .normal)
        }
        mosto.tag = Self.categoryNames.count + 1
        mosto.accessibilityLabel = Self.kaomojiName
        mosto.layer.cornerRadius = 7
        mosto.layer.cornerCurve = .continuous
        mosto.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        bar.addArrangedSubview(mosto)
        tabButtons.append(mosto)
        // settings stay one long press away from here too (the 表情 key's long press opens them as well)
        let gear = UIButton(type: .system)
        gear.setImage(UIImage(systemName: "gearshape", withConfiguration: tabCfg), for: .normal)
        gear.tintColor = Theme.secondaryText
        gear.accessibilityLabel = "设置"
        gear.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        bar.addArrangedSubview(gear)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = Theme.secondaryText
        addSubview(titleLabel)
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Data

    /// The emoji this iOS can draw: by the Emoji version each first appeared in (iOS 16.4 → 15.0, 17.4 → 15.1, 18.4 → 16.0).
    static var supportedEmojiVersion: Double {
        if #available(iOS 18.4, *) { return 16.0 }
        if #available(iOS 17.4, *) { return 15.1 }
        if #available(iOS 16.4, *) { return 15.0 }
        return 14.0
    }

    private static var cached: [Category]?
    static func categories() -> [Category] {
        if let c = cached { return c }
        var cats = categoryNames.map { Category(name: $0.0, symbol: $0.1, items: []) }
        let bundle = Bundle(for: EmojiPanelView.self)
        if let path = bundle.path(forResource: "emoji", ofType: "txt"),
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            let maxVersion = supportedEmojiVersion
            for line in text.split(separator: "\n") {
                let f = line.split(separator: "\t", maxSplits: 2)
                guard f.count == 3, let c = Int(f[0]), c < cats.count, let v = Double(f[1]), v <= maxVersion else { continue }
                cats[c].items.append(String(f[2]))
            }
        }
        cats.append(Category(name: kaomojiName, symbol: "", items: kaomoji))
        cached = cats
        return cats
    }

    private static let recentKey = "recentEmoji"
    static func recents() -> [String] {
        (UserDefaults.standard.array(forKey: recentKey) as? [String]) ?? []
    }
    static func remember(_ e: String) {
        var r = recents().filter { $0 != e }
        r.insert(e, at: 0)
        UserDefaults.standard.set(Array(r.prefix(32)), forKey: recentKey)
    }

    func load() {
        let recent = Self.recents()
        sections = [Category(name: "常用", symbol: "clock", items: recent)] + Self.categories()
        selected = -1
        collection.reloadData()
        guard bounds.width > 100, bounds.height > 100 else { return }   // shown with a frame later: load() runs again
        layoutIfNeeded()
        collection.layoutIfNeeded()
        // open on 常用 when there is something in it, else on the faces
        scrollTo(recent.isEmpty ? 1 : 0, animated: false)
    }

    func setChinese(_ chinese: Bool) {
        backButton.setTitle(chinese ? "中文" : "ABC", for: .normal)
        backButton.setNeedsLayout()
    }

    // MARK: - Layout

    private var cellSide: CGFloat {
        // 8 across in portrait (as the iOS emoji keyboard), more in landscape
        let w = collection.bounds.width - 8
        guard w > 100 else { return 40 }      // not laid out yet: never a zero or negative item size
        let across = max(8, Int(w / 46))
        return floor(w / CGFloat(across))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        guard b.width > 100, b.height > 100 else { return }   // before the panel has its real frame
        let barH: CGFloat = 40
        titleLabel.frame = CGRect(x: 12, y: 0, width: b.width - 24, height: 24)
        collection.frame = CGRect(x: 0, y: 24, width: b.width, height: b.height - 24 - barH - 4)
        let side: CGFloat = 56
        backButton.frame = CGRect(x: 4, y: b.height - barH, width: side, height: barH - 4)
        deleteButton.frame = CGRect(x: b.width - side - 4, y: b.height - barH, width: side, height: barH - 4)
        bar.frame = CGRect(x: side + 8, y: b.height - barH, width: b.width - 2 * side - 16, height: barH - 4)
        collection.collectionViewLayout.invalidateLayout()
        updateSelection()
    }

    // MARK: - Collection

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let c = collectionView.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! Cell
        let e = sections[indexPath.section].items[indexPath.item]
        c.label.text = e
        c.label.font = isKaomoji(indexPath.section) ? .systemFont(ofSize: 17) : .systemFont(ofSize: 30)
        c.label.textColor = Theme.keyText
        c.accessibilityLabel = e
        return c
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let h = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "h", for: indexPath) as! Header
        h.label.text = sections[indexPath.section].name
        return h
    }

    private func isKaomoji(_ section: Int) -> Bool { sections[section].name == Self.kaomojiName }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if isKaomoji(indexPath.section) {
            return CGSize(width: max(60, floor((collectionView.bounds.width - 8) / 3)), height: 44)
        }
        return CGSize(width: cellSide, height: cellSide)
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        // the first section's name is the panel title; later ones get a small header where they begin
        sections[section].items.isEmpty || section == 0 ? .zero : CGSize(width: collectionView.bounds.width, height: 24)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let e = sections[indexPath.section].items[indexPath.item]
        if !isKaomoji(indexPath.section) { Self.remember(e) }   // 常用 holds emoji (its cells are emoji-sized)
        onEmoji?(e)
        collectionView.deselectItem(at: indexPath, animated: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateSelection() }

    // MARK: - Categories

    private func scrollTo(_ section: Int, animated: Bool) {
        guard section < sections.count, !sections[section].items.isEmpty else { return }
        if section == 0 {
            collection.setContentOffset(.zero, animated: animated)
        } else if section < collection.numberOfSections, let attr = collection.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader,
                                                                                  at: IndexPath(item: 0, section: section)) {
            let maxY = max(0, collection.contentSize.height - collection.bounds.height)
            collection.setContentOffset(CGPoint(x: 0, y: min(attr.frame.minY, maxY)), animated: animated)
        }
        setSelected(section)
    }

    /// The category whose emoji fill the top of the view.
    private func updateSelection() {
        let y = collection.contentOffset.y + 30
        var current = sections.firstIndex { !$0.items.isEmpty } ?? 1
        // the collection may not have taken in the sections yet (a layout pass right after reloadData): only ask it
        // about sections it already has, or UIKit throws
        let known = min(sections.count, collection.numberOfSections)
        for s in 1..<max(1, known) where !sections[s].items.isEmpty {
            if let attr = collection.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader,
                                                                              at: IndexPath(item: 0, section: s)),
               attr.frame.minY <= y { current = s }
        }
        setSelected(current)
    }

    private func setSelected(_ s: Int) {
        guard s != selected, s < sections.count else { return }
        selected = s
        titleLabel.text = sections[s].name
        for (i, b) in tabButtons.enumerated() {
            b.tintColor = i == s ? Theme.keyText : Theme.secondaryText
            b.backgroundColor = i == s ? Theme.functionKey : .clear
            b.isEnabled = !sections[i].items.isEmpty
        }
    }

    @objc private func tabTapped(_ b: UIButton) { scrollTo(b.tag, animated: false) }
    @objc private func backTapped() { onBack?() }
    @objc private func settingsTapped() { onSettings?() }

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
}
