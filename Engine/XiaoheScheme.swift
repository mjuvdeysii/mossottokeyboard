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
}
