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
    /// Opened from Mosto (颜文字): the delete key's place holds 返回, in the return key's crown gold, so a pick and a
    /// tap bring the keys straight back under the thumb.
    private let returnButton = UIButton(type: .system)
    private var selected = -1
    private var collectionFade: CAGradientLayer?
    private var deleteTimer: Timer?
    private let gear = UIButton(type: .system)

    /// 底栏的 7 个目的地（设计评审 2026-11-03）：11 格挤 294pt 时每格 26.7pt，点错会落到空分类。
    /// 旅行/物品/旗帜仍是列表分组，只是不占底栏。section 号 = sections 的下标（常用 0，分类 1…8，颜文字 10）。
    static let tabDestinations: [(section: Int, name: String, symbol: String)] = [
        (0, "常用", "clock"), (1, "笑脸与人物", "face.smiling"), (2, "动物与自然", "pawprint"),
        (3, "食物与饮料", "fork.knife"), (4, "活动", "soccerball"), (7, "符号", "heart"),
        (10, "Mosto 颜文字", ""),
    ]

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
        // 高兴 / 兴奋
        "ヽ(°〇°)ﾉ", "＼(^o^)／", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "(๑˃ᴗ˂)ﻭ", "٩(◕‿◕)۶", "(⌒▽⌒)☆",
        "(o˘◡˘o)", "ヽ(・∀・)ﾉ", "(*≧ω≦*)", "(灬º‿º灬)♡",
        // 难过 / 委屈
        "(´；ω；`)", "(｡╯︵╰｡)", "(っ˘̩╭╮˘̩)っ", "(ಥ﹏ಥ)", "(ᗒᗣᗕ)՞", "(இ﹏இ`｡)",
        // 生气 / 无语
        "(＃`Д´)", "(눈_눈)", "(￣ヘ￣)", "(￣ω￣;)", "(；一_一)", "(・_・;)",
        // 惊讶
        "(°ロ°) !", "(⊙_⊙)", "Σ(°△°|||)︴", "(ﾟдﾟ)", "(O_O;)", "(◎_◎;)",
        // 害羞 / 可爱
        "(⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)", "(*/▽＼*)", "(๑´ㅂ`๑)", "(灬ºωº灬)", "(灬´ω`灬)",
        // 加油 / 打气
        "(๑•̀ㅂ•́)ง", "٩(ˊᗜˋ*)و", "(ง •̀_•́)ง", "ᕙ(⇀‸↼‶)ᕗ",
        // 摸鱼 / 躺平
        "(－_－) zzZ", "(￣o￣) zzZ", "_(┐「ε:)_", "(¯﹃¯)", "(´-ω-`)",
        // 打招呼 / 告辞
        "(・ω・)ノ", "( ´ ▽ ` )ﾉ", "ヾ(•ω•`)o", "(￣▽￣)ノ", "(*・ω・)ﾉ",
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
        /// 颜文字格子：按字数定字号，让长短不一的颜文字在屏幕上**看起来一样大**（原来固定 17pt 再自动缩，
        /// 长的缩到 10pt、短的保持 17pt，于是有的偏大有的偏小）。
        var isKaomoji = false

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = contentView.bounds
            applyFont()
        }

        private func applyFont() {
            let side = min(contentView.bounds.width, contentView.bounds.height)
            guard side > 4 else { return }
            if isKaomoji {
                let n = max(3, label.text?.count ?? 6)
                // 一格约放得下 0.62×字号 个字符；按字数反推字号，再夹在 10–19 之间
                label.font = .systemFont(ofSize: max(10, min(19, side * 1.5 / CGFloat(n))))
            } else {
                label.font = .systemFont(ofSize: min(34, max(20, floor(side * 0.78))))
            }
        }
        override var isHighlighted: Bool {
            didSet { contentView.backgroundColor = isHighlighted ? Theme.functionKey : .clear }
        }
    }

    final class Header: UICollectionReusableView {
        let label = UILabel()
        /// Mosto himself beside the name of his own 颜文字.
        let mosto = UIImageView(image: UIImage(named: "mosto_day", in: Bundle(for: EmojiPanelView.self), with: nil))
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = Theme.font(12, .bold)
            label.textColor = Theme.secondaryText
            addSubview(label)
            mosto.contentMode = .scaleAspectFit
            mosto.isHidden = true
            addSubview(mosto)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            let m: CGFloat = mosto.isHidden ? 0 : 22
            mosto.frame = CGRect(x: 6, y: (bounds.height - 22) / 2, width: 22, height: 22)
            label.frame = bounds.insetBy(dx: 10, dy: 0).offsetBy(dx: m, dy: 0)
        }
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 18, right: 4)
        layout.sectionHeadersPinToVisibleBounds = false
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = Theme.touchable   // on the system glass (never fully clear: see Theme.touchable)
        collection.backgroundColor = .clear
        collection.contentInsetAdjustmentBehavior = .never
        collection.alwaysBounceHorizontal = false
        collection.showsHorizontalScrollIndicator = false
        collection.delaysContentTouches = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(Cell.self, forCellWithReuseIdentifier: "e")
        collection.register(Header.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "h")

        // 底部渐隐：静止时最后一行不会被「拼音」条硬切一刀（设计组 R8 第 7 条）
        // build 256 的事故：给列表加过一层渐变遮罩，颜色写反（透明→黑）导致整片列表不可见。
        // 渐隐只是装饰，不值得再冒一次「看不见」的风险——直接去掉，底部留白（18pt）已经在布局里。
        addSubview(collection)

        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        backButton.setTitle("ABC", for: .normal)
        backButton.titleLabel?.font = Theme.font(16, .semibold)
        backButton.setTitleColor(Theme.keyText, for: .normal)
        backButton.setTitleColor(Theme.secondaryText, for: .highlighted)
        backButton.accessibilityLabel = "返回键盘"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
        deleteButton.accessibilityLabel = "删除"
        // delete repeats while held, as the delete key does
        deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        returnButton.setTitle("返回", for: .normal)
        returnButton.titleLabel?.font = Theme.font(16, .bold)
        returnButton.accessibilityLabel = "返回键盘"
        returnButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        returnButton.isHidden = true
        for b in [backButton, deleteButton, returnButton] {
            b.tintColor = Theme.keyText
            b.setTitleColor(Theme.keyText, for: .normal)
            b.backgroundColor = Theme.functionKey
            b.layer.cornerRadius = 8
            b.layer.cornerCurve = .continuous
            addSubview(b)
        }
        returnButton.backgroundColor = Theme.accentKey
        returnButton.setTitleColor(Theme.accentText, for: .normal)
        applyLips()
        bar.axis = .horizontal
        bar.distribution = .fillEqually
        addSubview(bar)
        let tabCfg = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        // 7 个目的地，每格在 402pt 上约 43pt、375pt 上约 39pt（设计评审：原来 11 格只有 26.7pt）。
        for dest in Self.tabDestinations {
            let b = UIButton(type: .system)
            if !dest.symbol.isEmpty { b.setImage(UIImage(systemName: dest.symbol, withConfiguration: tabCfg), for: .normal) }
            b.tintColor = Theme.secondaryText
            b.tag = dest.section
            b.accessibilityLabel = dest.name
            b.layer.cornerRadius = 8
            b.layer.cornerCurve = .continuous
            b.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            bar.addArrangedSubview(b)
            tabButtons.append(b)
        }
        // 颜文字 tab 用「颜」字：彩色位图混在单色图标行里是异物（设计组 R8）；脸留在列表头当品牌
        if let kaomojiTab = tabButtons.last {
            kaomojiTab.setImage(nil, for: .normal)
            kaomojiTab.setTitle("颜", for: .normal)
            kaomojiTab.titleLabel?.font = Theme.font(17, .semibold)
            kaomojiTab.setTitleColor(Theme.secondaryText, for: .normal)
        }

        titleLabel.font = Theme.font(12, .bold)
        titleLabel.textColor = Theme.secondaryText
        // the category names are the headers in the list itself (as on the system emoji keyboard); a second, pinned
        // name above them showed the same words twice
        titleLabel.isHidden = true
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The bar's keys are vinyl caps like the keyboard's: a darker lip under each (a hard, unblurred shadow).
    private func applyLips() {
        for (b, lip) in [(backButton, Theme.functionLip), (deleteButton, Theme.functionLip), (returnButton, Theme.accentLip)] {
            b.layer.shadowColor = lip.resolvedColor(with: traitCollection).cgColor
            b.layer.shadowOpacity = 1
            b.layer.shadowRadius = 0
            b.layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
            b.layer.cornerRadius = Metrics.cornerRadius
        }
        backButton.backgroundColor = Theme.functionKey
        deleteButton.backgroundColor = Theme.functionKey
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyLips()
    }

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

    /// `kaomoji`: open on Mosto 颜文字 (a tap on Mosto) instead of 常用.
    func load(kaomoji: Bool = false) {
        let recent = Self.recents()
        sections = [Category(name: "常用", symbol: "clock", items: recent)] + Self.categories()
        selected = -1
        returnButton.isHidden = !kaomoji
        deleteButton.isHidden = kaomoji
        collection.reloadData()
        guard bounds.width > 100, bounds.height > 100 else { return }   // shown with a frame later: load() runs again
        layoutIfNeeded()
        collection.layoutIfNeeded()
        if kaomoji, let k = sections.firstIndex(where: { $0.name == Self.kaomojiName }) {
            scrollTo(k, animated: false)
            return
        }
        // open on 常用 when there is something in it, else on the faces
        scrollTo(recent.isEmpty ? 1 : 0, animated: false)
    }

    func setChinese(_ chinese: Bool) {
        backButton.setTitle(chinese ? "拼音" : "ABC", for: .normal)
        backButton.setNeedsLayout()
    }

    // MARK: - Layout

    private var cellSide: CGFloat {
        // 8 across in portrait (as the iOS emoji keyboard), more in landscape
        let w = collection.bounds.width - 8
        guard w > 100 else { return 40 }      // not laid out yet: never a zero or negative item size
        let across = max(8, Int(w / 42))
        return floor(w / CGFloat(across))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        guard b.width > 100, b.height > 100 else { return }   // before the panel has its real frame
        let barH: CGFloat = 36
        titleLabel.frame = CGRect(x: 12, y: 0, width: b.width - 24, height: 24)
        collection.frame = CGRect(x: 0, y: 2, width: b.width, height: b.height - 2 - barH - 4)
        let side: CGFloat = 48
        backButton.frame = CGRect(x: 4, y: b.height - barH - 2, width: side, height: barH - 4)
        deleteButton.frame = CGRect(x: b.width - side - 4, y: b.height - barH - 2, width: side, height: barH - 4)
        returnButton.frame = deleteButton.frame
        // narrow phones: the gear gives its room to the tabs (settings stay a long press on the 表情 key away)
        gear.isHidden = b.width - 2 * side - 12 < 230
        bar.frame = CGRect(x: side + 6, y: b.height - barH, width: b.width - 2 * side - 12, height: barH - 4)
        if let fade = collectionFade {
            fade.frame = collection.bounds
            let clearAt = max(0, 1 - 16 / max(collection.bounds.height, 1))   // 底部 16pt 渐隐
            fade.locations = [0, NSNumber(value: clearAt), 1]
        }
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
        c.isKaomoji = isKaomoji(indexPath.section)
        c.setNeedsLayout()
        c.label.textColor = Theme.keyText
        c.accessibilityLabel = e
        return c
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let h = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "h", for: indexPath) as! Header
        h.label.text = sections[indexPath.section].name
        h.mosto.isHidden = !isKaomoji(indexPath.section)
        h.setNeedsLayout()
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
        sections[section].items.isEmpty ? .zero : CGSize(width: collectionView.bounds.width, height: 20)
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
        for b in tabButtons {
            b.tintColor = b.tag == s ? Theme.keyText : Theme.secondaryText
            b.setTitleColor(b.tag == s ? Theme.keyText : Theme.secondaryText, for: .normal)
            // 选中不再用 1.46:1 的浅色填充（日光下几乎看不见）：图标加深 + 底下 2.5pt 短横线。
            b.backgroundColor = .clear
            b.viewWithTag(9011)?.removeFromSuperview()
            if b.tag == s {
                let line = UIView(frame: CGRect(x: (b.bounds.width - 18) / 2, y: b.bounds.height - 5, width: 18, height: 2.5))
                line.tag = 9011
                line.backgroundColor = Theme.keyText
                line.layer.cornerRadius = 1.25
                b.addSubview(line)
            }
            // 分类为空时按钮不可点（空分类点下去什么也不会发生，用户会以为键盘坏了）
            b.isEnabled = b.tag < sections.count && !sections[b.tag].items.isEmpty
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

    // hidden or taken off screen with the delete key still held (a second finger on 拼音): the repeat stops
    override var isHidden: Bool { didSet { if isHidden { deleteUp() } } }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { deleteUp() }
    }

    @objc private func deleteUp() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }
}
