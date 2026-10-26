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

    /// Display form of a syllable (lv -> lü, lve -> lüe).
    public static func display(_ pinyin: String) -> String {
        if pinyin.hasPrefix("lv") || pinyin.hasPrefix("nv") {
            return pinyin.replacingOccurrences(of: "v", with: "ü")
        }
        return pinyin
    }
}
