import UIKit

/// 表情与颜文字面板: Emoji categories + OTTOSSOM Mood-Tape Kaomoji deck + comfortable scrollable bottom dock.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onEmoji: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onBack: (() -> Void)?
    var onSettings: (() -> Void)?

    struct Category { let name: String; let symbol: String; var items: [String] }
    struct MoodGroup { let title: String; let items: [String] }

    private var sections: [Category] = []
    private let collection: UICollectionView
    private let moodHeader = UIView()
    private let moodMosto = UIImageView()
    private let moodScrollBox = UIView()
    private let moodFade = CAGradientLayer()
    private let moodScroll = UIScrollView()
    private let moodHairline = CALayer()
    private var moodButtons: [UIButton] = []
    private var displayedMoods: [(title: String, items: [String])] = []
    private var selectedMood = 0
    private var kaomojiMode = false
    private var moodPoseGeneration = 0
    private var currentMoodPoseName = "mosto_day"

    private let dockBar = UIView()
    private let dockHairline = CALayer()
    private let tabScrollBox = UIView()
    private let tabFade = CAGradientLayer()
    private let tabScroll = UIScrollView()
    private var tabButtons: [UIButton] = []
    private let backButton = UIButton(type: .custom)
    private let deleteButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private let gear = UIButton(type: .system)
    private var selected = -1
    private var pendingScrollToSelectedTab = false
    private var deleteTimer: Timer?
    var tabScrollOffsetXForTests: CGFloat { tabScroll.contentOffset.x }

    static let categoryNames: [(String, String)] = [
        ("笑脸与人物", "face.smiling"), ("动物与自然", "pawprint"), ("食物与饮料", "fork.knife"), ("活动", "soccerball"),
        ("旅行与地点", "car"), ("物品", "lightbulb"), ("符号", "heart"), ("旗帜", "flag"),
    ]

    static let kaomojiName = "Mosto 颜文字"

    /// Structured 10-mood Kaomoji tape (all 228 unique expressions, single source of truth).
    static let kaomojiMoodGroups: [MoodGroup] = [
        MoodGroup(title: "招牌", items: [
            "ψ(｀∇´)ψ", "(｀∀´)Ψ", "Ψ(￣∀￣)Ψ", "ψ(._. )>", "(¬‿¬)", "(￣y▽￣)╭",
            "(▼∀▼)", "ψ(￣▽￣)ψ", "(ΦωΦ)✧", "(✧∀✧)", "ψ(｀▽´)ψ",
        ]),
        MoodGroup(title: "开心", items: [
            "(＾▽＾)", "ヾ(≧▽≦*)o", "(≧∇≦)ﾉ", "(*^▽^*)", "(●'◡'●)", "ヽ(✿ﾟ▽ﾟ)ノ",
            "♪(^∇^*)", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "o(*￣▽￣*)ブ", "(￣▽￣)／", "ヾ(•ω•`)o", "(〃＾▽＾〃)",
            "(*^ω^*)", "(^▽^)", "o(^▽^)o", "(≧∀≦)ゞ", "ヾ(^▽^*)))", "ヽ(^o^)丿",
            "(*≧∀≦*)", "(^o^)/", "٩(ˊᗜˋ*)و", "(*￣︶￣)", "(￣∀￣)", "( ´ ▽ ` )",
            "(☆▽☆)", "(★ω★)", "(✧ω✧)", "ヽ(•̀ω•́ )ゝ", "(*ﾟ▽ﾟ*)", "(｡◕‿◕｡)",
        ]),
        MoodGroup(title: "萌宠", items: [
            "(・ω・)", "(｡･ω･｡)", "(=^･ω･^=)", "(=｀ω´=)", "(ฅ´ω`ฅ)", "ʕ•ᴥ•ʔ",
            "U•ェ•*U", "(▽◕ ᴥ ◕▽)", "(●—●)", "(=^･ｪ･^=)", "(=´∇｀=)", "(´･ω･`)",
            "(・∀・)", "(✿◡‿◡)", "(✿◠‿◠)", "(=・ω・=)", "(=^･^=)", "(ฅ'ω'ฅ)",
            "ʕ·ᴥ·ʔ", "(・(ｪ)・)", "(◕ᴥ◕)", "(ᵔᴥᵔ)", "( ´(00)ˋ )", "(*ΦωΦ*)",
            "(/ =ω=)/", "(｡･ω･｡)ﾉ", "( ・◇・)？", "(・ω< )",
        ]),
        MoodGroup(title: "贴贴", items: [
            "(*/ω＼*)", "(⁄ ⁄•⁄ω⁄•⁄ ⁄)", "(/▽＼)", "(´,,•ω•,,)♡", "(´∀`)♡", "(｡･ω･｡)ﾉ♡",
            "(♡˙︶˙♡)", "(｡•ㅅ•｡)♡", "(´▽`ʃ♡ƪ)", "(づ｡◕‿‿◕｡)づ", "(づ￣ ³￣)づ", "(っ´▽`)っ",
            "(つ´ω`)つ", "⊂(・▽・⊂)", "(*╯3╰)", "(っ˘ω˘ς )", "( ˘ ³˘)♥", "(´ε｀ )♡",
            "(灬º‿º灬)♡", "(〃∀〃)", "(*/▽＼*)", "(*ﾉωﾉ)", "(っ•̀ω•́)っ♡", "♡(ŐωŐ人)",
            "(づ◡﹏◡)づ", "(⊃｡•́‿•̀｡)⊃", "(つ≧▽≦)つ", "(*´∀`*)",
        ]),
        MoodGroup(title: "加油", items: [
            "(๑•̀ㅂ•́)و✧", "(｡•̀ᴗ-)✧", "(ง •_•)ง", "(ง •̀_•́)ง", "ᕦ(ò_óˇ)ᕤ", "٩( 'ω' )و",
            "( •̀ ω •́ )✧", "(｡･∀･)ﾉﾞ", "( ´ ▽ ` )ﾉ", "(^_−)☆", "( ￣▽￣)σ", "(╭☞•́⍛•̀)╭☞",
            "(￣︶￣)↗", "♪(´▽｀)", "(*•̀ᴗ•́*)و ̑̑", "v(￣︶￣)y", "(^o^)v", "( •̀∀•́ )",
            "(๑•̀ω•́)ノ", "(｀・ω・´)ゞ", "(￣^￣)ゞ", "( • ̀ω•́ )✧", "✧٩(ˊωˋ*)و✧", "(๑˃̵ᴗ˂̵)و",
        ]),
        MoodGroup(title: "摸鱼", items: [
            "¯\\_(ツ)_/¯", "╮(￣▽￣)╭", "╮(╯▽╰)╭", "(￣_,￣ )", "(¬_¬ )", "( →_→)",
            "(←_← )", "( ˙꒳˙ )", "(￣.￣)", "( ´_ゝ`)", "( -_-)旦~", "_(:з」∠)_",
            "_(:3」∠)_", "(:3[▓▓]", "(:3[＿＿]", "(¦3[▓▓]", "(=_=)", "(⌐■_■)",
            "(▀̿Ĺ̯▀̿ ̿)", "(~￣▽￣)~", "╰(￣ω￣ｏ)", "( ´･･)ﾉ(._.`)", "ヾ(´･ω･｀)ﾉ", "(눈_눈)",
            "(ー_ー)!!", "(￣ω￣;)", "(￣▽￣\")", "(´-ι_-｀)", "(¬､¬)", "(°_°)",
            "(:3_ヽ)_", "__(⌒(_´-ω-)_",
        ]),
        MoodGroup(title: "破防", items: [
            "(ಥ_ಥ)", "(T_T)", "QAQ", "QvQ", "(｡•́︿•̀｡)", "(´;ω;`)",
            "( >﹏<。)", "o(TヘTo)", "(；′⌒`)", "(｡•́ - •̀｡)", "(ノへ￣、)", "(´-ω-`)",
            "(；´д｀)ゞ", "orz", "OTZ", "(´；ω；`)", "(╥_╥)", "(っ- ‸ - ς)",
            "(ToT)", "(;´༎ຶД༎ຶ`)", "(ノДＴ)", "(´•̥ ̯ •̥`)", "o(╥﹏╥)o", "(p_q)",
        ]),
        MoodGroup(title: "吃瓜", items: [
            "(⊙ˍ⊙)", "Σ(っ °Д °;)っ", "∑(っ°Д°;)っ", "(⊙_⊙)？", "(⊙x⊙;)", "(°ー°〃)",
            "щ(゜Д゜щ)", "(x_x)", "(◔◡◔)", "┌( ಠ_ಠ)┘", "(・_・;)", "(°ロ°)!",
            "(?_?)", "(O_O;)", "Σ(°△°|||)", "(°Д°)", "(⊙o⊙)", "w(ﾟДﾟ)w",
            "(゜ロ゜)", "(´⊙ω⊙`)", "ε=ε=┌(;￣◇￣)┘",
        ]),
        MoodGroup(title: "掀桌", items: [
            "(╯°□°）╯︵ ┻━┻", "(╯‵□′)╯︵┻━┻", "┬─┬ノ( º _ ºノ)", "(╬▔皿▔)╯", "(╬ Ò﹏Ó)", "(＃°Д°)",
            "(｀⌒´メ)", "(๑`^´๑)", "( `д´)", "(`皿´#)", "(╬ಠ益ಠ)", "(ノಠ益ಠ)ノ彡┻━┻",
            "凸(｀0´)凸", "(҂ `з´ )",
        ]),
        MoodGroup(title: "晚安", items: [
            "(～﹃～)~zZ", "(∪｡∪)｡｡｡zzz", "(￣o￣) . z Z", "(-_-) zzz", "(￣﹃￣)", "( ˘ω˘ ) ｽﾔｧ…",
            "(๑´ㅂ`๑)", "(￣～￣) 嚼嚼", "( ^_^)／▼☆▼＼(^_^ )", "( ^_^)/~~", "( ´ ▽ ` )ﾉ~~", "( ˘ ³˘)ﾉ~~",
            "(*￣▽￣)d", "(っ˘ڡ˘ς)", "( ´▽｀)つ旦", "( ^_^)／□☆□＼(^_^ )",
        ]),
    ]

    static let kaomoji: [String] = kaomojiMoodGroups.flatMap(\.items)
    static var moodGroupCountForTests: Int { kaomojiMoodGroups.count }
    var activeMoodIndexForTests: Int { selectedMood }
    func selectMoodForTests(_ index: Int) { selectMood(index) }
    var displayedKaomojiCountForTests: Int { kaomojiMode ? (displayedMoods.indices.contains(selectedMood) ? displayedMoods[selectedMood].items.count : 0) : 0 }
    var moodMostoPoseNameForTests: String { currentMoodPoseName }
    var moodTitlesForTests: [String] { displayedMoods.map(\.title) }
    func tapMoodMostoForTests() { moodMostoTapped() }

    final class Cell: UICollectionViewCell {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 30)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            label.layer.cornerRadius = 9
            label.layer.cornerCurve = .continuous
            label.layer.borderWidth = 0.5
            label.layer.borderColor = UIColor.clear.cgColor
            label.clipsToBounds = true
            contentView.addSubview(label)
            contentView.layer.cornerRadius = 9
            contentView.layer.cornerCurve = .continuous
            isAccessibilityElement = true
            accessibilityTraits = .keyboardKey
        }
        required init?(coder: NSCoder) { fatalError() }
        override func traitCollectionDidChange(_ previous: UITraitCollection?) {
            super.traitCollectionDidChange(previous)
            if tag == 1 {
                label.layer.borderColor = Theme.keyBorder.resolvedColor(with: traitCollection).cgColor
                label.backgroundColor = Theme.key
                label.textColor = Theme.keyText
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = contentView.bounds.insetBy(dx: 3, dy: 3)
        }
        override var isHighlighted: Bool {
            didSet {
                contentView.backgroundColor = .clear
                if tag == 1 {
                    label.backgroundColor = isHighlighted ? Theme.keyPressed : Theme.key
                } else {
                    label.backgroundColor = isHighlighted ? Theme.functionKey : .clear
                }
            }
        }
    }

    final class Header: UICollectionReusableView {
        let label = UILabel()
        let mosto = UIImageView(image: UIImage(named: "mosto_day", in: Bundle(for: EmojiPanelView.self), with: nil))
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = Theme.font(13, .bold)
            label.textColor = Theme.secondaryText
            backgroundColor = Theme.touchable
            addSubview(label)
            mosto.contentMode = .scaleAspectFit
            mosto.isHidden = true
            addSubview(mosto)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            let m: CGFloat = mosto.isHidden ? 0 : 24
            mosto.frame = CGRect(x: 6, y: (bounds.height - 24) / 2, width: 24, height: 24)
            label.frame = bounds.insetBy(dx: 10, dy: 0).offsetBy(dx: m, dy: 0)
        }
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 4, left: 4, bottom: 6, right: 4)
        layout.sectionHeadersPinToVisibleBounds = true
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = Theme.touchable

        collection.backgroundColor = .clear
        collection.clipsToBounds = true
        collection.disableAllEdgeEffects()
        collection.alwaysBounceHorizontal = false
        collection.showsHorizontalScrollIndicator = false
        collection.delaysContentTouches = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(Cell.self, forCellWithReuseIdentifier: "e")
        collection.register(Header.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "h")
        addSubview(collection)

        // Top Kaomoji Mood Tape Ribbon (replaces static section header only in kaomojiMode)
        moodHeader.isHidden = true
        moodMosto.contentMode = .scaleAspectFit
        moodMosto.image = UIImage(named: "mosto_day", in: Bundle(for: EmojiPanelView.self), with: nil)
        moodMosto.isUserInteractionEnabled = true
        moodMosto.isAccessibilityElement = true
        moodMosto.accessibilityTraits = .button
        moodMosto.accessibilityLabel = "切换常用与招牌颜文字"
        moodMosto.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(moodMostoTapped)))
        moodHeader.addSubview(moodMosto)
        moodFade.startPoint = CGPoint(x: 0, y: 0.5)
        moodFade.endPoint = CGPoint(x: 1, y: 0.5)
        moodFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        moodScrollBox.backgroundColor = .clear
        moodScroll.showsHorizontalScrollIndicator = false
        moodScroll.alwaysBounceHorizontal = true
        moodScroll.delaysContentTouches = false
        moodScroll.disableAllEdgeEffects()
        moodScroll.delegate = self
        moodScrollBox.addSubview(moodScroll)
        moodHeader.addSubview(moodScrollBox)
        moodHairline.backgroundColor = Theme.separator.resolvedColor(with: traitCollection).cgColor
        moodHeader.layer.addSublayer(moodHairline)
        addSubview(moodHeader)

        // Bottom Comfortable Scrollable Dock
        dockHairline.backgroundColor = Theme.separator.resolvedColor(with: traitCollection).cgColor
        dockBar.backgroundColor = .clear
        dockBar.layer.addSublayer(dockHairline)
        addSubview(dockBar)

        tabFade.startPoint = CGPoint(x: 0, y: 0.5)
        tabFade.endPoint = CGPoint(x: 1, y: 0.5)
        tabFade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        tabScrollBox.backgroundColor = .clear
        tabScroll.showsHorizontalScrollIndicator = false
        tabScroll.alwaysBounceHorizontal = true
        tabScroll.delaysContentTouches = false
        tabScroll.disableAllEdgeEffects()
        tabScroll.delegate = self
        tabScrollBox.addSubview(tabScroll)
        dockBar.addSubview(tabScrollBox)

        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        backButton.setTitle("ABC", for: .normal)
        backButton.titleLabel?.font = Theme.font(16, .semibold)
        backButton.setTitleColor(Theme.keyText, for: .normal)
        backButton.setTitleColor(Theme.secondaryText, for: .highlighted)
        backButton.accessibilityLabel = "返回键盘"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
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
            b.layer.cornerRadius = Metrics.cornerRadius
            b.layer.cornerCurve = .continuous
            dockBar.addSubview(b)
        }
        returnButton.backgroundColor = Theme.accentKey
        returnButton.setTitleColor(Theme.accentText, for: .normal)
        applyLips()

        let tabCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        for (i, (name, symbol)) in ([("常用", "clock")] + Self.categoryNames).enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol, withConfiguration: tabCfg), for: .normal)
            b.tintColor = Theme.secondaryText
            b.tag = i
            b.accessibilityLabel = name
            b.layer.cornerRadius = 8
            b.layer.cornerCurve = .continuous
            b.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabScroll.addSubview(b)
            tabButtons.append(b)
        }

        let mosto = UIButton(type: .custom)
        if let face = UIImage(named: "mosto_day", in: Bundle(for: EmojiPanelView.self), with: nil) {
            mosto.setImage(Self.resizedFace(face), for: .normal)
        }
        mosto.tag = Self.categoryNames.count + 1
        mosto.accessibilityLabel = Self.kaomojiName
        mosto.layer.cornerRadius = 8
        mosto.layer.cornerCurve = .continuous
        mosto.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        tabScroll.addSubview(mosto)
        tabButtons.append(mosto)

        gear.setImage(UIImage(systemName: "gearshape", withConfiguration: tabCfg), for: .normal)
        gear.tintColor = Theme.secondaryText
        gear.accessibilityLabel = "设置"
        gear.layer.cornerRadius = 8
        gear.layer.cornerCurve = .continuous
        gear.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        tabScroll.addSubview(gear)

        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func resizedFace(_ face: UIImage) -> UIImage {
        let side: CGFloat = 24
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let scale = min(side / face.size.width, side / face.size.height)
            let w = face.size.width * scale, h = face.size.height * scale
            face.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
    }

    func themeChanged() {
        applyLips()
        moodMosto.isHidden = Theme.plain
        refreshMoodRibbonStyle()
        collection.reloadData()
        setNeedsLayout()
    }

    private func applyLips() {
        let t = traitCollection
        dockHairline.backgroundColor = Theme.separator.resolvedColor(with: t).cgColor
        moodHairline.backgroundColor = Theme.separator.resolvedColor(with: t).cgColor
        for (b, lip) in [(backButton, Theme.functionLip), (deleteButton, Theme.functionLip), (returnButton, Theme.accentLip)] {
            b.layer.shadowColor = lip.resolvedColor(with: t).cgColor
            b.layer.shadowOpacity = 1
            b.layer.shadowRadius = 0
            b.layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
            b.layer.cornerRadius = Metrics.cornerRadius
        }
        backButton.backgroundColor = kaomojiMode ? Theme.accentKey : Theme.functionKey
        backButton.setTitleColor(kaomojiMode ? Theme.accentText : Theme.keyText, for: .normal)
        backButton.layer.shadowColor = (kaomojiMode ? Theme.accentLip : Theme.functionLip).resolvedColor(with: t).cgColor
        if let kaomojiTab = tabButtons.last {
            if Theme.plain {
                let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                kaomojiTab.imageView?.overrideUserInterfaceStyle = .light
                kaomojiTab.setImage(UIImage(systemName: "face.smiling", withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate), for: .normal)
                let isSel = selected == tabButtons.count - 1
                kaomojiTab.tintColor = (isSel ? Theme.keyText : Theme.secondaryText).resolvedColor(with: t)
            } else {
                let night = KeyboardSettings.shared.appearance == 2 || (KeyboardSettings.shared.appearance == 0 && t.userInterfaceStyle == .dark)
                let imgName = night ? "mosto_night" : "mosto_day"
                if let face = UIImage(named: imgName, in: Bundle(for: EmojiPanelView.self), with: nil) {
                    kaomojiTab.imageView?.overrideUserInterfaceStyle = .unspecified
                    kaomojiTab.setImage(Self.resizedFace(face), for: .normal)
                }
                moodMosto.image = UIImage(named: imgName, in: Bundle(for: EmojiPanelView.self), with: nil)
            }
        }
        deleteButton.backgroundColor = Theme.functionKey
        deleteButton.tintColor = Theme.keyText
        gear.tintColor = Theme.secondaryText
        updateMoodMostoPose(animated: false)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyLips()
        refreshMoodRibbonStyle()
    }

    // MARK: - Data

    static var supportedEmojiVersion: Double {
        if #available(iOS 18.4, *) { return 17.0 }
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

    private static let recentKaomojiKey = "recentKaomoji"
    static func recentKaomoji() -> [String] {
        (UserDefaults.standard.array(forKey: recentKaomojiKey) as? [String]) ?? []
    }

    private func rebuildMoodData() {
        var groups: [(title: String, items: [String])] = []
        let recents = Array(Self.recentKaomoji().prefix(9))
        if !recents.isEmpty {
            groups.append(("常用", recents))
        }
        for g in Self.kaomojiMoodGroups {
            groups.append((g.title, g.items))
        }
        displayedMoods = groups
        moodButtons.forEach { $0.removeFromSuperview() }
        moodButtons = groups.enumerated().map { idx, g in
            let b = UIButton(type: .system)
            b.setTitle(g.title, for: .normal)
            b.titleLabel?.font = Theme.font(12.5, .semibold)
            b.tag = idx
            b.layer.cornerRadius = 12
            b.layer.cornerCurve = .continuous
            b.layer.borderWidth = 0.5
            b.addTarget(self, action: #selector(moodTapped(_:)), for: .touchUpInside)
            moodScroll.addSubview(b)
            return b
        }
        selectedMood = min(selectedMood, max(0, displayedMoods.count - 1))
        refreshMoodRibbonStyle()
    }

    private func refreshMoodRibbonStyle() {
        let t = traitCollection
        for (i, b) in moodButtons.enumerated() {
            let active = i == selectedMood
            b.backgroundColor = active ? Theme.selection : Theme.preeditPillBg
            b.setTitleColor(active ? Theme.selectionText : Theme.keyText, for: .normal)
            b.layer.borderColor = (active ? UIColor.clear : Theme.keyBorder).resolvedColor(with: t).cgColor
            b.accessibilityTraits = active ? [.button, .selected] : .button
        }
    }

    private func selectMood(_ index: Int) {
        guard displayedMoods.indices.contains(index) else { return }
        selectedMood = index
        refreshMoodRibbonStyle()
        updateMoodMostoPose(animated: true)
        layoutMoodPills()
        if index < moodButtons.count {
            moodScroll.scrollRectToVisible(moodButtons[index].frame.insetBy(dx: -16, dy: 0), animated: true)
        }
        if kaomojiMode {
            collection.reloadData()
            collection.setContentOffset(.zero, animated: false)
        }
    }

    @objc private func moodTapped(_ b: UIButton) {
        selectMood(b.tag)
    }

    @objc private func moodMostoTapped() {
        let hasRecent = displayedMoods.first?.title == "常用"
        let target: Int
        if hasRecent && selectedMood != 0 {
            target = 0
        } else {
            target = displayedMoods.firstIndex(where: { $0.title == "招牌" }) ?? 0
        }
        selectMood(target)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animate(withDuration: 0.10, animations: {
            self.moodMosto.transform = CGAffineTransform(scaleX: 1.16, y: 0.88).translatedBy(x: 0, y: -2)
        }) { _ in
            UIView.animate(withDuration: 0.16) {
                self.moodMosto.transform = .identity
            }
        }
    }

    private func updateMoodMostoPose(animated: Bool) {
        let t = traitCollection
        let night = KeyboardSettings.shared.appearance == 2 || (KeyboardSettings.shared.appearance == 0 && t.userInterfaceStyle == .dark)
        let title = displayedMoods.indices.contains(selectedMood) ? displayedMoods[selectedMood].title : "招牌"
        let basePose: String
        switch title {
        case "晚安":
            basePose = "mosto_night"
        case "摸鱼", "破防":
            basePose = "mosto_yawn"
        default:
            basePose = night ? "mosto_night" : "mosto_day"
        }
        moodPoseGeneration &+= 1
        let gen = moodPoseGeneration
        let bundle = Bundle(for: EmojiPanelView.self)
        if animated && !night && !UIAccessibility.isReduceMotionEnabled && ["开心", "萌宠", "贴贴", "加油"].contains(title) {
            currentMoodPoseName = "mosto_blink"
            moodMosto.image = UIImage(named: "mosto_blink", in: bundle, with: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.moodPoseGeneration == gen else { return }
                self.currentMoodPoseName = basePose
                self.moodMosto.image = UIImage(named: basePose, in: bundle, with: nil)
            }
        } else {
            currentMoodPoseName = basePose
            moodMosto.image = UIImage(named: basePose, in: bundle, with: nil)
        }
    }

    /// `kaomoji`: open directly on the 10-mood Kaomoji Tape Deck.
    func load(kaomoji: Bool = false) {
        let recent = Self.recents()
        let cats = Self.categories()
        sections = [Category(name: "常用", symbol: "clock", items: recent)] + cats
        rebuildMoodData()
        kaomojiMode = kaomoji
        selectedMood = 0
        refreshMoodRibbonStyle()
        updateMoodMostoPose(animated: false)
        selected = -1
        pendingScrollToSelectedTab = true
        returnButton.isHidden = true
        deleteButton.isHidden = false
        applyLips()
        moodHeader.isHidden = !kaomoji
        moodMosto.isHidden = Theme.plain
        collection.reloadData()
        setNeedsLayout()
        guard bounds.width > 100, bounds.height > 100 else {
            if kaomoji { setSelected(Self.categoryNames.count + 1, animated: false) }
            return
        }
        layoutIfNeeded()
        collection.layoutIfNeeded()
        if kaomoji {
            setSelected(Self.categoryNames.count + 1, animated: false)
            collection.setContentOffset(.zero, animated: false)
            return
        }
        scrollTo(recent.isEmpty ? 1 : 0, animated: false)
    }

    func setChinese(_ chinese: Bool) {
        backButton.setTitle(chinese ? "拼音" : "ABC", for: .normal)
        backButton.setNeedsLayout()
    }

    // MARK: - Layout

    private var cellSide: CGFloat {
        let w = collection.bounds.width - 8
        guard w > 100 else { return 40 }
        let across = max(8, Int(w / 46))
        return floor(w / CGFloat(across))
    }

    private func updateEdgeFade(box: UIView, scroll: UIScrollView, fade: CAGradientLayer) {
        let w = box.bounds.width
        let x = scroll.contentOffset.x
        let left = x > 0.5
        let right = x + w < scroll.contentSize.width - 0.5
        guard w > 28, left || right else {
            if box.layer.mask != nil { box.layer.mask = nil }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = box.bounds
        let e = Double(12 / w)
        fade.locations = [0, NSNumber(value: left ? e : 0), NSNumber(value: right ? 1 - e : 1), 1]
        if box.layer.mask !== fade { box.layer.mask = fade }
        CATransaction.commit()
    }

    private func layoutMoodPills() {
        var x: CGFloat = 2
        let h: CGFloat = 26
        let y: CGFloat = max(0, (moodScroll.bounds.height - h) / 2)
        for b in moodButtons {
            let title = b.title(for: .normal) ?? ""
            let tw = ceil((title as NSString).size(withAttributes: [.font: Theme.font(12.5, .semibold)]).width)
            let w = max(44, tw + 18)
            b.frame = CGRect(x: x, y: y, width: w, height: h)
            x += w + 6
        }
        moodScroll.contentSize = CGSize(width: x + 4, height: moodScroll.bounds.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        guard b.width > 100, b.height > 100 else { return }
        let barH: CGFloat = 48
        let topH: CGFloat = kaomojiMode ? 40 : 2

        if kaomojiMode {
            moodHeader.isHidden = false
            moodHeader.frame = CGRect(x: 0, y: 0, width: b.width, height: topH)
            let showMosto = !Theme.plain
            moodMosto.isHidden = !showMosto
            let lead: CGFloat = showMosto ? 40 : 12
            moodMosto.frame = CGRect(x: 12, y: (topH - 24) / 2, width: 24, height: 24)
            moodScrollBox.frame = CGRect(x: lead, y: 0, width: max(0, b.width - lead - 12), height: topH)
            moodScroll.frame = moodScrollBox.bounds
            layoutMoodPills()
            updateEdgeFade(box: moodScrollBox, scroll: moodScroll, fade: moodFade)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            moodHairline.frame = CGRect(x: 8, y: topH - 0.5, width: max(0, b.width - 16), height: 1 / UIScreen.main.scale)
            CATransaction.commit()
        } else {
            moodHeader.isHidden = true
        }

        collection.frame = CGRect(x: 0, y: topH, width: b.width, height: max(0, b.height - topH - barH))

        dockBar.frame = CGRect(x: 0, y: b.height - barH, width: b.width, height: barH)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dockHairline.frame = CGRect(x: 8, y: 0, width: max(0, b.width - 16), height: 1 / UIScreen.main.scale)
        CATransaction.commit()

        let side: CGFloat = 56
        let btnH: CGFloat = barH - 8
        let btnY: CGFloat = 4
        backButton.frame = CGRect(x: 6, y: btnY, width: side, height: btnH)
        deleteButton.frame = CGRect(x: b.width - side - 6, y: btnY, width: side, height: btnH)
        returnButton.frame = deleteButton.frame
        for btn in [backButton, deleteButton, returnButton] {
            btn.layer.shadowPath = UIBezierPath(roundedRect: btn.bounds, cornerRadius: Metrics.cornerRadius).cgPath
        }

        // Scrollable horizontal category pills between backButton and deleteButton (36x34pt touch targets, zero squish)
        let tabLeft = backButton.frame.maxX + 6
        let tabRight = deleteButton.frame.minX - 6
        tabScrollBox.frame = CGRect(x: tabLeft, y: 0, width: max(0, tabRight - tabLeft), height: barH)
        tabScroll.frame = tabScrollBox.bounds
        let dockItems = tabButtons + [gear]
        let itemW: CGFloat = 36
        let itemH: CGFloat = 34
        let itemGap: CGFloat = 4
        var tx: CGFloat = 2
        let ty = (barH - itemH) / 2
        for item in dockItems {
            item.frame = CGRect(x: tx, y: ty, width: itemW, height: itemH)
            tx += itemW + itemGap
        }
        let totalTabW = tx - itemGap + 2
        if totalTabW < tabScroll.bounds.width {
            let extra = (tabScroll.bounds.width - totalTabW) / 2
            for item in dockItems { item.frame.origin.x += extra }
        }
        tabScroll.contentSize = CGSize(width: max(tabScroll.bounds.width, totalTabW), height: barH)
        if pendingScrollToSelectedTab || (kaomojiMode && selected == tabButtons.count - 1) {
            ensureSelectedTabVisible(animated: false)
            pendingScrollToSelectedTab = false
        }
        updateEdgeFade(box: tabScrollBox, scroll: tabScroll, fade: tabFade)

        collection.collectionViewLayout.invalidateLayout()
        if !kaomojiMode { updateSelection() }
    }

    // MARK: - Collection

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        kaomojiMode ? 1 : sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if kaomojiMode {
            guard displayedMoods.indices.contains(selectedMood) else { return 0 }
            return displayedMoods[selectedMood].items.count
        }
        return sections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let c = collectionView.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! Cell
        let kao = kaomojiMode || isKaomoji(indexPath.section)
        let e: String
        if kaomojiMode {
            e = displayedMoods[selectedMood].items[indexPath.item]
        } else {
            e = sections[indexPath.section].items[indexPath.item]
        }
        c.label.text = e
        c.tag = kao ? 1 : 0
        c.label.backgroundColor = kao ? Theme.key : .clear
        c.label.layer.borderColor = kao ? Theme.keyBorder.resolvedColor(with: traitCollection).cgColor : UIColor.clear.cgColor
        c.label.font = kao ? .systemFont(ofSize: 14.5, weight: .medium) : .systemFont(ofSize: 30)
        c.label.minimumScaleFactor = kao ? 0.58 : 0.6
        c.label.textColor = Theme.keyText
        c.accessibilityLabel = e
        return c
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let h = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "h", for: indexPath) as! Header
        if kaomojiMode {
            h.label.text = nil
            h.mosto.isHidden = true
            return h
        }
        h.label.text = (isKaomoji(indexPath.section) && Theme.plain) ? "常用颜文字" : sections[indexPath.section].name
        let night = KeyboardSettings.shared.appearance == 2 || (KeyboardSettings.shared.appearance == 0 && traitCollection.userInterfaceStyle == .dark)
        h.mosto.image = UIImage(named: night ? "mosto_night" : "mosto_day", in: Bundle(for: EmojiPanelView.self), with: nil)
        h.mosto.isHidden = !isKaomoji(indexPath.section) || Theme.plain
        h.setNeedsLayout()
        return h
    }

    private func isKaomoji(_ section: Int) -> Bool {
        section < sections.count && sections[section].name == Self.kaomojiName
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if kaomojiMode || isKaomoji(indexPath.section) {
            return CGSize(width: max(60, floor((collectionView.bounds.width - 8) / 3)), height: 42)
        }
        return CGSize(width: cellSide, height: cellSide)
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        if kaomojiMode { return .zero }
        return sections[section].items.isEmpty ? .zero : CGSize(width: collectionView.bounds.width, height: 28)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let kao = kaomojiMode || isKaomoji(indexPath.section)
        let e: String
        if kaomojiMode {
            e = displayedMoods[selectedMood].items[indexPath.item]
        } else {
            e = sections[indexPath.section].items[indexPath.item]
        }
        if !kao {
            Self.remember(e)
        } else {
            var rk = Self.recentKaomoji().filter { $0 != e }
            rk.insert(e, at: 0)
            let capped = Array(rk.prefix(24))
            UserDefaults.standard.set(capped, forKey: Self.recentKaomojiKey)
            if kaomojiMode, displayedMoods.first?.title == "常用", selectedMood != 0 {
                displayedMoods[0].items = Array(capped.prefix(9))
            }
        }
        onEmoji?(e)
        collectionView.deselectItem(at: indexPath, animated: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === moodScroll {
            updateEdgeFade(box: moodScrollBox, scroll: moodScroll, fade: moodFade)
            return
        }
        if scrollView === tabScroll {
            updateEdgeFade(box: tabScrollBox, scroll: tabScroll, fade: tabFade)
            return
        }
        guard scrollView === collection, !kaomojiMode else { return }
        updateSelection()
    }

    // MARK: - Categories

    private func scrollTo(_ section: Int, animated: Bool) {
        guard section < sections.count, !sections[section].items.isEmpty else { return }
        if section == 0 {
            collection.setContentOffset(.zero, animated: animated)
        } else if section < collection.numberOfSections,
                  let attr = collection.layoutAttributesForSupplementaryElement(
                      ofKind: UICollectionView.elementKindSectionHeader,
                      at: IndexPath(item: 0, section: section)
                  ) {
            let maxY = max(0, collection.contentSize.height - collection.bounds.height)
            collection.setContentOffset(CGPoint(x: 0, y: min(attr.frame.minY, maxY)), animated: animated)
        }
        setSelected(section, animated: animated)
    }

    private func updateSelection() {
        let y = collection.contentOffset.y + 30
        var current = sections.firstIndex { !$0.items.isEmpty } ?? 1
        let known = min(sections.count, collection.numberOfSections)
        for s in 1..<max(1, known) where !sections[s].items.isEmpty {
            if let attr = collection.layoutAttributesForSupplementaryElement(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: s)
            ), attr.frame.minY <= y { current = s }
        }
        setSelected(current)
    }

    private func ensureSelectedTabVisible(animated: Bool) {
        guard selected >= 0, selected < tabButtons.count, tabScroll.bounds.width > 0, tabScroll.contentSize.width > 0 else { return }
        let target = tabButtons[selected].frame.insetBy(dx: -12, dy: 0)
        let maxX = max(0, tabScroll.contentSize.width - tabScroll.bounds.width)
        var offsetX = tabScroll.contentOffset.x
        if target.maxX > offsetX + tabScroll.bounds.width {
            offsetX = min(maxX, target.maxX - tabScroll.bounds.width)
        } else if target.minX < offsetX {
            offsetX = max(0, target.minX)
        }
        if abs(offsetX - tabScroll.contentOffset.x) > 0.5 {
            tabScroll.setContentOffset(CGPoint(x: offsetX, y: 0), animated: animated)
        }
        updateEdgeFade(box: tabScrollBox, scroll: tabScroll, fade: tabFade)
    }

    private func setSelected(_ s: Int, animated: Bool = true) {
        guard s != selected, s < sections.count else { return }
        selected = s
        for (i, b) in tabButtons.enumerated() {
            b.tintColor = (i == s ? Theme.keyText : Theme.secondaryText).resolvedColor(with: traitCollection)
            b.backgroundColor = i == s ? Theme.functionKey : .clear
            b.isEnabled = !sections[i].items.isEmpty
        }
        ensureSelectedTabVisible(animated: animated)
    }

    @objc private func tabTapped(_ b: UIButton) {
        let tapKaomoji = b.tag == Self.categoryNames.count + 1
        if tapKaomoji != kaomojiMode {
            kaomojiMode = tapKaomoji
            applyLips()
            collection.reloadData()
            setNeedsLayout()
            layoutIfNeeded()
        }
        if kaomojiMode {
            setSelected(b.tag)
            collection.setContentOffset(.zero, animated: false)
        } else {
            scrollTo(b.tag, animated: false)
        }
    }

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
