import UIKit

/// 表情与颜文字面板: Emoji categories + OTTOSSOM Mood-Tape Kaomoji deck + comfortable scrollable bottom dock.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onEmoji: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onBack: (() -> Void)?
    var onNumbers: (() -> Void)?
    var onReturn: (() -> Void)?
    var onSettings: (() -> Void)?
    var onFeedback: ((FeedbackEvent) -> Void)?
    /// Exact X origin & width of the main keyboard's bottom-row Mosto key for 0pt-drift toggle.
    var mostoAnchorX: CGFloat?
    var mostoAnchorWidth: CGFloat?

    struct Category { let name: String; let symbol: String; var items: [String] }
    struct MoodGroup { let title: String; let items: [String] }

    private var sections: [Category] = []
    private let collectionBox = UIView()
    private let collectionFade = CAGradientLayer()
    private let collection: UICollectionView
    private let kaomojiShortcutButton = UIButton(type: .custom)
    private let moodHeader = UIView()
    private let moodMostoBadge = UIView()
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
    private let mostoReturnButton = UIButton(type: .custom)
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

    /// Structured 10-mood Kaomoji tape (all 229 unique expressions, single source of truth).
    static let kaomojiMoodGroups: [MoodGroup] = [
        MoodGroup(title: "招牌", items: [
            "ψ(｀∇´)ψ", "(｀∀´)Ψ", "Ψ(￣∀￣)Ψ", "ψ(._. )>", "(¬‿¬)", "(￣y▽￣)╭",
            "(▼∀▼)", "ψ(￣▽￣)ψ", "(ΦωΦ)✧", "(✧∀✧)", "ψ(≧▽≦)ψ", "ψ( ˘ω˘ )ψ",
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
    var kaomojiRowHeightForTests: CGFloat { kaomojiRowHeight }
    var collectionBottomFadeActiveForTests: Bool { collectionBox.layer.mask === collectionFade }
    var kaomojiShortcutVisibleForTests: Bool { !kaomojiShortcutButton.isHidden }
    var kaomojiModeForTests: Bool { kaomojiMode }
    func tapKaomojiShortcutForTests() { kaomojiShortcutTapped() }
    var collectionForTests: UICollectionView { collection }
    var portraitDockLightbulbUnclippedForTests: Bool {
        tabButtons.count > 3 && tabButtons[3].frame.maxX <= tabScrollBox.bounds.width + 0.5
    }
    var kaomojiDockGearFullyVisibleForTests: Bool {
        guard let last = tabButtons.last else { return false }
        let f = tabScroll.convert(last.frame, to: tabScrollBox)
        return f.width > 0 && f.minX >= -0.5 && f.maxX <= tabScrollBox.bounds.width + 0.5
    }
    var dockNoTrailingHalfSliceForTests: Bool {
        let boxW = tabScrollBox.bounds.width
        guard boxW > 0 else { return false }
        let items = tabButtons
        if tabScroll.contentSize.width <= boxW + 0.5 { return true }
        return !items.contains {
            let f = tabScroll.convert($0.frame, to: tabScrollBox)
            return f.minX > boxW - 10 && f.minX < boxW - 0.5
        }
    }
    var moodMostoBadgeShownForTests: Bool { !moodMostoBadge.isHidden && moodMostoBadge.bounds.width >= 28 }
    var backButtonUsesFunctionStyleForTests: Bool { backButton.backgroundColor == Theme.functionKey }
    var dockTabWidthForTests: CGFloat { tabButtons.first?.frame.width ?? 0 }
    var landscapeDockAllInsideForTests: Bool { (tabButtons.last?.frame.maxX ?? 0) <= tabScrollBox.bounds.width + 0.5 }
    var mostoReturnFrameInSelfForTests: CGRect { dockBar.convert(mostoReturnButton.frame, to: self) }
    var returnButtonVisibleForTests: Bool { !returnButton.isHidden && returnButton.frame.width >= 48 }
    var emojiBadgesBorderlessForTests: Bool { kaomojiShortcutButton.layer.borderWidth == 0 && moodMostoBadge.layer.borderWidth == 0 }

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
            label.layer.borderWidth = 0
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
                label.backgroundColor = Theme.keyTop
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
                    label.backgroundColor = isHighlighted ? Theme.keyPressed : Theme.keyTop
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

        collectionBox.backgroundColor = .clear
        collectionFade.startPoint = CGPoint(x: 0.5, y: 0)
        collectionFade.endPoint = CGPoint(x: 0.5, y: 1)
        collectionFade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]

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
        collectionBox.addSubview(collection)
        addSubview(collectionBox)

        kaomojiShortcutButton.layer.borderWidth = 0
        kaomojiShortcutButton.accessibilityLabel = "打开 Mosto 颜文字"
        kaomojiShortcutButton.addTarget(self, action: #selector(kaomojiShortcutTapped), for: .touchUpInside)
        addSubview(kaomojiShortcutButton)

        // Top Kaomoji Mood Tape Ribbon (replaces static section header only in kaomojiMode)
        moodHeader.isHidden = true
        moodMostoBadge.layer.cornerRadius = 14
        moodMostoBadge.layer.cornerCurve = .continuous
        moodMostoBadge.layer.borderWidth = 0
        moodMostoBadge.isUserInteractionEnabled = false
        moodHeader.addSubview(moodMostoBadge)

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
        backButton.setTitle("123", for: .normal)
        backButton.titleLabel?.font = Theme.font(15.5, .semibold)
        backButton.setTitleColor(Theme.keyText, for: .normal)
        backButton.setTitleColor(Theme.secondaryText, for: .highlighted)
        backButton.accessibilityLabel = "数字键盘"
        backButton.addTarget(self, action: #selector(numbersTapped), for: .touchUpInside)

        mostoReturnButton.accessibilityLabel = "关闭表情返回键盘"
        mostoReturnButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        returnButton.setTitle("换行", for: .normal)
        returnButton.titleLabel?.font = Theme.font(15.5, .semibold)
        returnButton.accessibilityLabel = "发送或换行"
        returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        returnButton.isHidden = false

        for b in [backButton, mostoReturnButton, deleteButton, returnButton] {
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

        gear.isHidden = true

        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    func themeChanged() {
        applyLips()
        moodMosto.isHidden = Theme.plain
        moodMostoBadge.isHidden = Theme.plain
        refreshMoodRibbonStyle()
        collection.reloadData()
        setNeedsLayout()
    }

    private func applyLips() {
        let t = traitCollection
        dockHairline.backgroundColor = Theme.separator.resolvedColor(with: t).cgColor
        moodHairline.backgroundColor = Theme.separator.resolvedColor(with: t).cgColor
        moodMostoBadge.backgroundColor = Theme.preeditPillBg
        for (b, lip) in [(backButton, Theme.functionLip), (deleteButton, Theme.functionLip), (returnButton, Theme.accentLip)] {
            b.layer.shadowColor = lip.resolvedColor(with: t).cgColor
            b.layer.shadowOpacity = 1
            b.layer.shadowRadius = Metrics.shadowBlur
            b.layer.shadowOffset = CGSize(width: 0, height: Metrics.lip)
            b.layer.cornerRadius = Metrics.cornerRadius
        }
        backButton.backgroundColor = Theme.functionKey
        backButton.setTitleColor(Theme.keyText, for: .normal)
        mostoReturnButton.backgroundColor = Theme.selection.withAlphaComponent(0.18)
        if Theme.plain {
            let mCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            mostoReturnButton.setImage(UIImage(systemName: "face.smiling", withConfiguration: mCfg)?.withRenderingMode(.alwaysTemplate), for: .normal)
            mostoReturnButton.tintColor = Theme.selection
        } else {
            let night = KeyboardSettings.shared.appearance == 2 || (KeyboardSettings.shared.appearance == 0 && t.userInterfaceStyle == .dark)
            let imgName = night ? "mosto_night" : "mosto_day"
            if let face = UIImage(named: imgName, in: Bundle(for: EmojiPanelView.self), with: nil) {
                mostoReturnButton.setImage(Self.resizedFace(face, side: 28).withRenderingMode(.alwaysOriginal), for: .normal)
            }
        }
        returnButton.backgroundColor = Theme.accentKey
        returnButton.setTitleColor(Theme.accentText, for: .normal)
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
        updateKaomojiShortcutStyle()
        deleteButton.backgroundColor = Theme.functionKey
        deleteButton.tintColor = Theme.keyText
        gear.tintColor = Theme.secondaryText
        updateMoodMostoPose(animated: false)
    }

    private func updateKaomojiShortcutStyle() {
        let t = traitCollection
        let night = KeyboardSettings.shared.appearance == 2 || (KeyboardSettings.shared.appearance == 0 && t.userInterfaceStyle == .dark)
        var cfg = UIButton.Configuration.filled()
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = Theme.preeditPillBg
        cfg.baseForegroundColor = Theme.keyText
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 9)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = Theme.font(11.5, .semibold)
            return out
        }
        if Theme.plain {
            cfg.image = nil
            cfg.title = "颜文字 ›"
            cfg.imagePadding = 0
        } else {
            let imgName = night ? "mosto_night" : "mosto_day"
            if let face = UIImage(named: imgName, in: Bundle(for: EmojiPanelView.self), with: nil) {
                cfg.image = Self.resizedFace(face, side: 15).withRenderingMode(.alwaysOriginal)
                cfg.imagePadding = 4
            } else {
                cfg.image = nil
                cfg.imagePadding = 0
            }
            cfg.title = "颜文字"
        }
        kaomojiShortcutButton.configuration = cfg
        kaomojiShortcutButton.layer.cornerCurve = .continuous
    }

    private static func resizedFace(_ face: UIImage, side: CGFloat = 24) -> UIImage {
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let scale = min(side / face.size.width, side / face.size.height)
            let w = face.size.width * scale, h = face.size.height * scale
            face.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
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
            b.addTarget(self, action: #selector(moodTapped(_:)), for: .touchUpInside)
            moodScroll.addSubview(b)
            return b
        }
        selectedMood = min(selectedMood, max(0, displayedMoods.count - 1))
        refreshMoodRibbonStyle()
    }

    private func refreshMoodRibbonStyle() {
        for (i, b) in moodButtons.enumerated() {
            let active = i == selectedMood
            b.backgroundColor = active ? Theme.selection : Theme.preeditPillBg
            b.setTitleColor(active ? Theme.selectionText : Theme.keyText, for: .normal)
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
        onFeedback?(.candidate)
        selectMood(b.tag)
    }

    @objc private func moodMostoTapped() {
        onFeedback?(.mosto)
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
        returnButton.isHidden = false
        deleteButton.isHidden = false
        applyLips()
        moodHeader.isHidden = !kaomoji
        moodMosto.isHidden = Theme.plain
        moodMostoBadge.isHidden = Theme.plain
        collection.reloadData()
        setNeedsLayout()
        guard bounds.width > 100, bounds.height > 100 else {
            if kaomoji { setSelected(Self.categoryNames.count + 1, animated: false) }
            updateCollectionBottomFade()
            return
        }
        layoutIfNeeded()
        collection.layoutIfNeeded()
        if kaomoji {
            setSelected(Self.categoryNames.count + 1, animated: false)
            collection.setContentOffset(.zero, animated: false)
            updateCollectionBottomFade()
            return
        }
        scrollTo(recent.isEmpty ? 1 : 0, animated: false)
        updateCollectionBottomFade()
    }

    func setChinese(_ chinese: Bool) {
        backButton.setTitle("123", for: .normal)
        backButton.setNeedsLayout()
    }

    func setReturnLabel(_ title: String?, chinese: Bool) {
        let label = title ?? (chinese ? "换行" : "return")
        returnButton.setTitle(label, for: .normal)
        returnButton.accessibilityLabel = label
    }

    // MARK: - Layout

    private var cellSide: CGFloat {
        let w = collection.bounds.width - 8
        guard w > 100 else { return 40 }
        let compactLand = bounds.height < 210 && w > 500
        let across = compactLand ? max(12, Int(w / 40)) : max(8, Int(w / 46))
        return floor(w / CGFloat(across))
    }

    private func updateEdgeFade(box: UIView, scroll: UIScrollView, fade: CAGradientLayer, edge: CGFloat = 12) {
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
        let e = Double(min(0.24, edge / w))
        fade.locations = [0, NSNumber(value: left ? e : 0), NSNumber(value: right ? 1 - e : 1), 1]
        if box.layer.mask !== fade { box.layer.mask = fade }
        CATransaction.commit()
    }

    private func updateCollectionBottomFade() {
        let h = collectionBox.bounds.height
        let hasMoreBelow = !kaomojiMode
            && collection.contentSize.height > h + 2
            && (collection.contentOffset.y + h < collection.contentSize.height - 2)
        guard h > 40, hasMoreBelow else {
            if collectionBox.layer.mask != nil { collectionBox.layer.mask = nil }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionFade.frame = collectionBox.bounds
        let frac = Double(min(0.16, 15.0 / h))
        collectionFade.locations = [0, NSNumber(value: 1.0 - frac), 1]
        if collectionBox.layer.mask !== collectionFade { collectionBox.layer.mask = collectionFade }
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
            moodMostoBadge.isHidden = !showMosto
            moodMosto.isHidden = !showMosto
            let lead: CGFloat = showMosto ? 46 : 12
            moodMostoBadge.frame = CGRect(x: 10, y: (topH - 28) / 2, width: 30, height: 28)
            moodMosto.frame = CGRect(x: 15, y: (topH - 20) / 2, width: 20, height: 20)
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

        collectionBox.frame = CGRect(x: 0, y: topH, width: b.width, height: max(0, b.height - topH - barH))
        collection.frame = collectionBox.bounds
        if let flow = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            flow.sectionInset = UIEdgeInsets(top: 2, left: 4, bottom: b.height < 210 ? 2 : 4, right: 4)
        }
        kaomojiShortcutButton.isHidden = kaomojiMode
        if !kaomojiMode {
            let headerH: CGFloat = b.height < 210 ? 22 : 26
            let pillH: CGFloat = b.height < 210 ? 20 : 22
            let fitW = ceil(kaomojiShortcutButton.sizeThatFits(CGSize(width: 140, height: pillH)).width)
            let pillW = max(Theme.plain ? 62 : 76, fitW)
            kaomojiShortcutButton.frame = CGRect(
                x: max(8, b.width - pillW - 8),
                y: topH + floor((headerH - pillH) / 2),
                width: pillW,
                height: pillH
            )
            kaomojiShortcutButton.layer.cornerRadius = pillH / 2
            bringSubviewToFront(kaomojiShortcutButton)
        }

        dockBar.frame = CGRect(x: 0, y: b.height - barH, width: b.width, height: barH)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dockHairline.frame = CGRect(x: 8, y: 0, width: max(0, b.width - 16), height: 1 / UIScreen.main.scale)
        CATransaction.commit()

        let sideInset: CGFloat = b.width > 500 ? Metrics.sideInsetLandscape : Metrics.sideInset
        let contentW = max(1, b.width - sideInset * 2)
        let unit = contentW / 10
        let gapX = Metrics.gapX
        let btnH: CGFloat = barH - 8
        let btnY: CGFloat = 4
        let isLand = b.width > 500
        let leftW = isLand ? 54 : floor(1.4 * unit - gapX)
        let leftX = floor(sideInset + gapX / 2)
        backButton.frame = CGRect(x: leftX, y: btnY, width: max(40, leftW), height: btnH)

        let mrW = mostoAnchorWidth ?? (isLand ? 42 : max(32, floor(1.0 * unit - gapX)))
        let mrX = mostoAnchorX ?? (backButton.frame.maxX + gapX)
        mostoReturnButton.frame = CGRect(x: mrX, y: btnY, width: mrW, height: btnH)

        let retW = isLand ? 66 : max(52, floor(1.8 * unit - gapX))
        let retX = floor(b.width - sideInset - gapX / 2 - retW)
        returnButton.frame = CGRect(x: retX, y: btnY, width: retW, height: btnH)

        let delW: CGFloat = isLand ? 44 : max(36, floor(1.05 * unit - gapX))
        deleteButton.frame = CGRect(x: returnButton.frame.minX - gapX - delW, y: btnY, width: delW, height: btnH)

        for btn in [backButton, mostoReturnButton, deleteButton, returnButton] {
            let sr = CGRect(x: 0.75, y: 0.5, width: max(0, btn.bounds.width - 1.5), height: max(0, btn.bounds.height - 0.5))
            btn.layer.shadowPath = UIBezierPath(roundedRect: sr, cornerRadius: max(1, Metrics.cornerRadius - 0.5)).cgPath
        }

        // Scrollable horizontal category pills between mostoReturnButton and deleteButton.
        let tabLeft = mostoReturnButton.frame.maxX + 4
        let tabRight = deleteButton.frame.minX - 4
        tabScrollBox.frame = CGRect(x: tabLeft, y: 0, width: max(0, tabRight - tabLeft), height: barH)
        tabScroll.frame = tabScrollBox.bounds
        let dockItems = tabButtons
        let boxW = tabScrollBox.bounds.width
        let itemH: CGFloat = 34
        let ty = (barH - itemH) / 2
        let defaultSpan = CGFloat(dockItems.count) * 34 + CGFloat(max(0, dockItems.count - 1)) * 3 + 4
        let totalTabW: CGFloat
        if defaultSpan <= boxW {
            let count = CGFloat(max(1, dockItems.count))
            let gaps = CGFloat(max(0, dockItems.count - 1))
            let itemW = min(44, max(34, floor((boxW - gaps * 6 - 8) / count)))
            let itemGap = gaps > 0 ? min(8, max(3, floor((boxW - count * itemW - 8) / gaps))) : 0
            let contentW = count * itemW + gaps * itemGap
            let pad = max(0, (boxW - contentW) / 2)
            for (i, item) in dockItems.enumerated() {
                item.frame = CGRect(x: pad + CGFloat(i) * (itemW + itemGap), y: ty, width: itemW, height: itemH)
            }
            totalTabW = boxW
        } else {
            let startX: CGFloat = 2
            let nVisible = max(4, min(dockItems.count, Int(floor((boxW - startX) / 34))))
            let stride = (boxW - startX) / CGFloat(nVisible)
            let itemW = min(34, max(26, floor(stride - 4)))
            for (i, item) in dockItems.enumerated() {
                item.frame = CGRect(x: startX + CGFloat(i) * stride, y: ty, width: itemW, height: itemH)
            }
            totalTabW = startX + CGFloat(dockItems.count - 1) * stride + itemW + 6
        }
        tabScroll.contentSize = CGSize(width: max(tabScroll.bounds.width, totalTabW), height: barH)
        if pendingScrollToSelectedTab || (kaomojiMode && selected == tabButtons.count - 1) {
            ensureSelectedTabVisible(animated: false)
            pendingScrollToSelectedTab = false
        }
        updateEdgeFade(box: tabScrollBox, scroll: tabScroll, fade: tabFade, edge: 12)

        collection.collectionViewLayout.invalidateLayout()
        collection.layoutIfNeeded()
        if !kaomojiMode { updateSelection() }
        updateCollectionBottomFade()
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
        c.label.backgroundColor = kao ? Theme.keyTop : .clear
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

    /// Integer-row fit prevents half-clipped kaomoji pills along the bottom dock across all height tiers.
    private var kaomojiRowHeight: CGFloat {
        let h = collection.bounds.height - 4
        guard h > 80 else { return 44 }
        let rows: CGFloat = h >= 166 ? 4 : (h < 108 ? 2 : 3)
        return min(50, max(38, floor(h / rows)))
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if kaomojiMode || isKaomoji(indexPath.section) {
            return CGSize(width: max(60, floor((collectionView.bounds.width - 8) / 3)), height: kaomojiRowHeight)
        }
        return CGSize(width: cellSide, height: cellSide)
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        if kaomojiMode { return .zero }
        return sections[section].items.isEmpty ? .zero : CGSize(width: collectionView.bounds.width, height: bounds.height < 210 ? 22 : 26)
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
            updateEdgeFade(box: tabScrollBox, scroll: tabScroll, fade: tabFade, edge: 26)
            return
        }
        guard scrollView === collection, !kaomojiMode else { return }
        updateSelection()
        updateCollectionBottomFade()
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
        let maxX = max(0, tabScroll.contentSize.width - tabScroll.bounds.width)
        var offsetX = tabScroll.contentOffset.x
        if selected == tabButtons.count - 1 {
            // Snap cleanly to the trailing edge so Mosto and `gear` sit completely clear of edge fade.
            offsetX = maxX
        } else {
            let target = tabButtons[selected].frame.insetBy(dx: -12, dy: 0)
            if target.maxX > offsetX + tabScroll.bounds.width {
                offsetX = min(maxX, target.maxX - tabScroll.bounds.width)
            } else if target.minX < offsetX {
                offsetX = max(0, target.minX)
            }
        }
        if abs(offsetX - tabScroll.contentOffset.x) > 0.5 {
            tabScroll.setContentOffset(CGPoint(x: offsetX, y: 0), animated: animated)
        }
        updateEdgeFade(box: tabScrollBox, scroll: tabScroll, fade: tabFade, edge: 12)
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

    @objc private func kaomojiShortcutTapped() {
        guard let mostoTab = tabButtons.last else { return }
        tabTapped(mostoTab)
    }

    @objc func kaomojiShortcutTappedForTests() {
        kaomojiShortcutTapped()
    }

    @objc private func tabTapped(_ b: UIButton) {
        onFeedback?(.candidate)
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
        updateCollectionBottomFade()
    }

    @objc private func backTapped() { onBack?() }
    @objc private func numbersTapped() { onNumbers?() }
    @objc private func returnTapped() { onReturn?() }
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


// MARK: - R95: T9 / Numpad Classified Symbol Panel (0pt-drift Row 3 Right Return)

/// 九宫格/数字键盘专属分类符号面板：左列分类、中区网格、右列四行与九宫格严格对齐（⌫ / 空格 / 返回 / 发送）。
final class SymbolPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSymbol: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onSpace: (() -> Void)?
    var onReturn: (() -> Void)?
    var onClose: (() -> Void)?
    var onFeedback: ((FeedbackEvent) -> Void)?

    struct Category { let title: String; let items: [String] }
    static let categories: [Category] = [
        Category(title: "常用", items: ["，", "。", "？", "！", "、", "：", "；", "“", "（", "《", "【", "—", "…", "～", "·", "@", "#", "%", "¥", "$", "+", "-", "×", "÷"]),
        Category(title: "中文", items: ["，", "。", "、", "；", "：", "？", "！", "…", "—", "·", "～", "￥", "「", "『", "《", "（", "【", "“", "’", "°", "℃", "‰", "※", "§"]),
        Category(title: "英文", items: [".", ",", "?", "!", ":", ";", "'", "\"", "@", "#", "$", "%", "&", "*", "_", "-", "/", "\\", "|", "~", "`", "^", "<", ">"]),
        Category(title: "括号", items: ["（", "）", "【", "】", "《", "》", "「", "」", "『", "』", "“", "”", "(", ")", "[", "]", "{", "}", "<", ">", "〈", "〉", "〔", "〕"]),
        Category(title: "数学", items: ["+", "-", "×", "÷", "=", "≠", "≈", "±", "<", ">", "≤", "≥", "%", "‰", "°", "℃", "√", "∞", "π", "∑", "∠", "⊥", "∥", "△"]),
        Category(title: "序号", items: ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑴", "⑵", "⑶", "⑷", "⑸", "一", "二", "三", "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"]),
    ]

    private var selectedCategory = 0
    private var categoryButtons: [UIButton] = []
    private let categoryScroll = UIScrollView()
    private let collection: UICollectionView
    private let deleteButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private var deleteTimer: Timer?

    var closeButtonFrameForTests: CGRect { closeButton.frame }
    var returnButtonFrameForTests: CGRect { returnButton.frame }

    final class SymCell: UICollectionViewCell {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = Theme.font(20, .medium)
            label.textAlignment = .center
            label.textColor = Theme.keyText
            label.layer.cornerRadius = 8
            label.layer.cornerCurve = .continuous
            label.clipsToBounds = true
            contentView.addSubview(label)
            isAccessibilityElement = true
            accessibilityTraits = .keyboardKey
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = contentView.bounds.insetBy(dx: 3, dy: 3)
        }
        override var isHighlighted: Bool {
            didSet {
                label.backgroundColor = isHighlighted ? Theme.keyPressed : Theme.keyTop
            }
        }
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = Theme.touchable

        categoryScroll.showsVerticalScrollIndicator = false
        categoryScroll.showsHorizontalScrollIndicator = false
        categoryScroll.alwaysBounceHorizontal = false
        categoryScroll.disableAllEdgeEffects()
        addSubview(categoryScroll)

        for (i, cat) in Self.categories.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(cat.title, for: .normal)
            b.titleLabel?.font = Theme.font(14, .semibold)
            b.tag = i
            b.layer.cornerRadius = Metrics.cornerRadius
            b.layer.cornerCurve = .continuous
            b.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            categoryScroll.addSubview(b)
            categoryButtons.append(b)
        }

        collection.backgroundColor = .clear
        collection.showsVerticalScrollIndicator = false
        collection.alwaysBounceHorizontal = false
        collection.delaysContentTouches = false
        collection.disableAllEdgeEffects()
        collection.dataSource = self
        collection.delegate = self
        collection.register(SymCell.self, forCellWithReuseIdentifier: "s")
        addSubview(collection)

        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        deleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: cfg), for: .normal)
        deleteButton.accessibilityLabel = "删除"
        deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        spaceButton.setTitle("空格", for: .normal)
        spaceButton.titleLabel?.font = Theme.font(15, .medium)
        spaceButton.accessibilityLabel = "空格"
        spaceButton.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)

        closeButton.setTitle("返回", for: .normal)
        closeButton.titleLabel?.font = Theme.font(15.5, .semibold)
        closeButton.accessibilityLabel = "返回键盘"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        returnButton.setTitle("换行", for: .normal)
        returnButton.titleLabel?.font = Theme.font(15.5, .semibold)
        returnButton.accessibilityLabel = "发送或换行"
        returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)

        for b in [deleteButton, spaceButton, closeButton, returnButton] {
            b.layer.cornerRadius = Metrics.cornerRadius
            b.layer.cornerCurve = .continuous
            addSubview(b)
        }
        themeChanged()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setReturnLabel(_ title: String?, chinese: Bool) {
        let label = title ?? (chinese ? "换行" : "return")
        returnButton.setTitle(label, for: .normal)
        returnButton.accessibilityLabel = label
        spaceButton.setTitle(chinese ? "空格" : "space", for: .normal)
    }

    func themeChanged() {
        for (i, b) in categoryButtons.enumerated() {
            let active = i == selectedCategory
            b.backgroundColor = active ? Theme.selection : Theme.functionKey
            b.setTitleColor(active ? Theme.selectionText : Theme.keyText, for: .normal)
        }
        deleteButton.backgroundColor = Theme.functionKey
        deleteButton.tintColor = Theme.keyText
        spaceButton.backgroundColor = Theme.key
        spaceButton.setTitleColor(Theme.keyText, for: .normal)
        closeButton.backgroundColor = Theme.selection.withAlphaComponent(0.18)
        closeButton.setTitleColor(Theme.selection, for: .normal)
        returnButton.backgroundColor = Theme.accentKey
        returnButton.setTitleColor(Theme.accentText, for: .normal)
        collection.reloadData()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            themeChanged()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        guard b.width > 100, b.height > 80 else { return }
        let sideInset: CGFloat = b.width > 500 ? Metrics.sideInsetLandscape : Metrics.sideInset
        let contentW = max(1, b.width - sideInset * 2)
        let unit = contentW / 10
        let gapX = Metrics.gapX
        let rowH = b.height / 4
        let gapY: CGFloat = rowH <= 60 ? min(12, max(8, (rowH * 0.20).rounded())) : 12
        let capH = max(1, rowH - gapY)

        let leftW = floor(1.6 * unit - gapX)
        let leftX = floor(sideInset + gapX / 2)
        categoryScroll.frame = CGRect(x: leftX, y: floor(gapY / 2), width: leftW, height: max(1, b.height - gapY))
        let catBtnH: CGFloat = max(32, floor((b.height - gapY - 5 * 6) / 6))
        var cy: CGFloat = 0
        for btn in categoryButtons {
            btn.frame = CGRect(x: 0, y: cy, width: leftW, height: catBtnH)
            cy += catBtnH + 6
        }
        categoryScroll.contentSize = CGSize(width: leftW, height: max(categoryScroll.bounds.height, cy))

        let rightW = floor(1.6 * unit - gapX)
        let rightX = floor(b.width - sideInset - gapX / 2 - rightW)
        let rightButtons = [deleteButton, spaceButton, closeButton, returnButton]
        for (r, btn) in rightButtons.enumerated() {
            let y0 = floor(CGFloat(r) * rowH + gapY / 2)
            btn.frame = CGRect(x: rightX, y: y0, width: rightW, height: capH)
        }

        let gridX = leftX + leftW + gapX
        let gridW = max(40, rightX - gapX - gridX)
        collection.frame = CGRect(x: gridX, y: floor(gapY / 2), width: gridW, height: max(1, b.height - gapY))
        collection.collectionViewLayout.invalidateLayout()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Self.categories[selectedCategory].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "s", for: indexPath) as! SymCell
        let sym = Self.categories[selectedCategory].items[indexPath.item]
        cell.label.text = sym
        cell.label.textColor = Theme.keyText
        cell.label.backgroundColor = Theme.keyTop
        cell.accessibilityLabel = sym
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cols: CGFloat = 4
        let w = floor(collectionView.bounds.width / cols)
        let h = floor(collectionView.bounds.height / 4)
        return CGSize(width: max(30, w), height: max(34, h))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let sym = Self.categories[selectedCategory].items[indexPath.item]
        onFeedback?(.key(.char(sym)))
        onSymbol?(sym)
    }

    @objc private func categoryTapped(_ b: UIButton) {
        selectedCategory = b.tag
        onFeedback?(.candidate)
        themeChanged()
        collection.setContentOffset(.zero, animated: false)
    }

    @objc private func spaceTapped() { onSpace?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func returnTapped() { onReturn?() }

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
