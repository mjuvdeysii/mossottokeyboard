import Foundation

/// 小鹤双拼（纯双拼，无形码）：每个音节固定两键。
public enum XiaoheScheme {
    static let initialKey: [String: Character] = ["zh": "v", "ch": "i", "sh": "u"]

    static let finalKey: [String: Character] = [
        "iu": "q", "ei": "w", "e": "e", "uan": "r", "van": "r", "ue": "t", "ve": "t",
        "un": "y", "vn": "y", "u": "u", "i": "i", "o": "o", "uo": "o", "ie": "p",
        "a": "a", "ong": "s", "iong": "s", "ai": "d", "en": "f", "eng": "g",
        "ang": "h", "an": "j", "ing": "k", "uai": "k", "iang": "l", "uang": "l",
        "ou": "z", "ia": "x", "ua": "x", "ao": "c", "ui": "v", "v": "v", "in": "b",
        "iao": "n", "ian": "m",
    ]

    static let zeroInitial: Set<String> = ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "er", "o", "ou"]
    static let plainInitials: Set<Character> = Set("bpmfdtnlgkhjqxrzcsyw")

    /// Two-key code for a pinyin syllable (rime spelling: lv / lve / ju), or nil if not typeable.
    public static func code(for pinyin: String) -> String? {
        if zeroInitial.contains(pinyin) {
            let chars = Array(pinyin)
            switch chars.count {
            case 1: return String([chars[0], chars[0]])          // a -> aa
            case 2: return pinyin                                 // ai, an, ou ...
            default:                                              // ang -> ah, eng -> eg
                guard let f = finalKey[pinyin] else { return nil }
                return String([chars[0], f])
            }
        }
        for (ini, key) in initialKey where pinyin.hasPrefix(ini) {
            guard let f = finalKey[String(pinyin.dropFirst(2))] else { return nil }
            return String([key, f])
        }
        guard let first = pinyin.first, plainInitials.contains(first),
              let f = finalKey[String(pinyin.dropFirst())] else { return nil }
        return String([first, f])
    }

    /// What each key stands for, for the key chart and the keyboard's 键位提示: the initial it carries (zh / ch / sh
    /// only — every other initial is its own letter) and the finals, written as in school pinyin (ü). Kept beside
    /// `finalKey`; the engine gate checks that the two agree.
    public static let keyGuide: [Character: (initial: String?, finals: [String])] = [
        "q": (nil, ["iu"]), "w": (nil, ["ei"]), "e": (nil, ["e"]), "r": (nil, ["uan"]), "t": (nil, ["ue", "üe"]),
        "y": (nil, ["un"]), "u": ("sh", ["u"]), "i": ("ch", ["i"]), "o": (nil, ["uo", "o"]), "p": (nil, ["ie"]),
        "a": (nil, ["a"]), "s": (nil, ["ong", "iong"]), "d": (nil, ["ai"]), "f": (nil, ["en"]), "g": (nil, ["eng"]),
        "h": (nil, ["ang"]), "j": (nil, ["an"]), "k": (nil, ["ing", "uai"]), "l": (nil, ["iang", "uang"]),
        "z": (nil, ["ou"]), "x": (nil, ["ia", "ua"]), "c": (nil, ["ao"]), "v": ("zh", ["ui", "ü"]), "b": (nil, ["in"]),
        "n": (nil, ["iao"]), "m": (nil, ["ian"]),
    ]

    /// The guide and the code table say the same thing: every final's key lists it, every listed final is on its key.
    public static func guideAgrees() -> [String] {
        var bad: [String] = []
        func school(_ f: String) -> String { f == "v" ? "ü" : f == "ve" ? "üe" : f }
        for (f, k) in finalKey {
            let shown = keyGuide[k]?.finals ?? []
            // ü-forms written with u where the sound is unambiguous (juan, jun): van / vn share uan / un's key
            if !shown.contains(school(f)) && !(f == "van" && shown.contains("uan")) && !(f == "vn" && shown.contains("un")) {
                bad.append("\(f)→\(k)")
            }
        }
        for (k, g) in keyGuide {
            for f in g.finals {
                let code = f == "ü" ? "v" : f == "üe" ? "ve" : f
                if finalKey[code] != k { bad.append("\(k):\(f)") }
            }
            if let i = g.initial, initialKey[i] != k { bad.append("\(k):\(i)") }
        }
        return bad
    }

    /// Display form of a syllable (lv -> lü, lve -> lüe).
    public static func display(_ pinyin: String) -> String {
        if pinyin.hasPrefix("lv") || pinyin.hasPrefix("nv") {
            return pinyin.replacingOccurrences(of: "v", with: "ü")
        }
        return pinyin
    }

    /// Per-key state during the 2nd beat of a Xiaohe syllable (after the user has typed an initial/zero-initial key).
    public enum ChordHint: Equatable {
        /// This key can validly complete a Mandarin syllable; `finalIndices` highlights matching items in `keyGuide[key].finals`,
        /// while `overrideFinal` displays the exact resulting zero-initial final (e.g. "ai", "an", "ao", "ei", "en", "er", "ou").
        case match(finalIndices: Set<Int>, overrideFinal: String?)
        /// No standard syllable starts with the pending first key and ends on this key (softly dimmed, still tappable).
        case inactive
    }

    /// Canonical Mandarin pinyin syllables covered by the offline lexicon (414 entries).
    public static let allSyllables: [String] =
        ("a ai an ang ao ba bai ban bang bao bei ben beng bi bian biang biao bie bin bing bo bu "
         + "ca cai can cang cao ce cei cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo "
         + "da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo "
         + "e ei en eng er fa fan fang fei fen feng fiao fo fou fu "
         + "ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo "
         + "ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo "
         + "ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun "
         + "ka kai kan kang kao ke kei ken keng kong kou ku kua kuai kuan kuang kui kun kuo "
         + "la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve "
         + "ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu "
         + "na nai nan nang nao ne nei nen neng ni nian niang niao nie nin ning niu nong nou nu nuan nuo nv nve "
         + "o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu "
         + "qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun "
         + "ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo "
         + "sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo "
         + "ta tai tan tang tao te tei teng ti tian tiao tie ting tong tou tu tuan tui tun tuo "
         + "wa wai wan wang wei wen weng wo wu xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun "
         + "ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun "
         + "za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo")
        .split(separator: " ").map(String.init)

    /// Precomputed map: first Xiaohe key -> [second Xiaohe key: [syllables]].
    private static let secondKeysByFirst: [Character: [Character: [String]]] = {
        var map: [Character: [Character: [String]]] = [:]
        for syl in allSyllables {
            guard let code = code(for: syl), code.count == 2 else { continue }
            let chars = Array(code)
            map[chars[0], default: [:]][chars[1], default: []].append(syl)
        }
        return map
    }()

    /// All valid second-key continuations and their display pinyin forms after `firstKey`.
    public static func validSecondKeys(after firstKey: Character) -> [Character: [String]] {
        let lower = Character(String(firstKey).lowercased())
        return secondKeysByFirst[lower] ?? [:]
    }

    /// Strips the initial from a pinyin syllable and converts `v` to school-style `ü`.
    private static func finalForm(of pinyin: String) -> String {
        let stripped: String
        if pinyin.hasPrefix("zh") || pinyin.hasPrefix("ch") || pinyin.hasPrefix("sh") {
            stripped = String(pinyin.dropFirst(2))
        } else if zeroInitial.contains(pinyin) {
            stripped = pinyin
        } else {
            stripped = String(pinyin.dropFirst())
        }
        return stripped.replacingOccurrences(of: "v", with: "ü")
    }

    /// Computes exact per-final chord lighting for `key` given a pending `firstKey` (nil when idle or on even beats).
    public static func chordHint(forKey key: Character, after firstKey: Character?) -> ChordHint? {
        guard let firstKey else { return nil }
        let seconds = validSecondKeys(after: firstKey)
        guard !seconds.isEmpty else { return nil }
        let lower = Character(String(key).lowercased())
        guard let syllables = seconds[lower], !syllables.isEmpty else { return .inactive }
        let guideFinals = keyGuide[lower]?.finals ?? []
        var matched: Set<Int> = []
        for syl in syllables {
            let fin = finalForm(of: syl)
            for (idx, gf) in guideFinals.enumerated() where gf == fin {
                matched.insert(idx)
            }
        }
        if !matched.isEmpty {
            return .match(finalIndices: matched, overrideFinal: nil)
        }
        // Zero-initial 2-letter syllables (ai, an, ao, ei, en, er, ou) spell their final directly on the 2nd key.
        return .match(finalIndices: [], overrideFinal: syllables.first)
    }
}
