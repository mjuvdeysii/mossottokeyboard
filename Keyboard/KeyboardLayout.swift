import UIKit

/// numbers / symbols: Gboard's full-width 123 and #+= pages; numpad: the 九宫格 number pad.
enum KeyboardPage { case letters, numbers, symbols, numpad }

enum KeyAction: Equatable {
    case char(String)
    case shift
    case delete
    case space
    case ret
    case globe
    case settings
    case page(KeyboardPage)
    case toggleLanguage
    /// A 九宫格 pinyin key: its digit 2–9, or ' for 分词.
    case t9(Character)
    /// 重输: drop what is being composed.
    case clearInput
    /// Held delete, after a while: a word at a time (two Chinese characters, or a Latin word with its space).
    case deleteWord
    /// 表情: the emoji page. Held, it opens the keyboard settings instead (as Gboard's emoji key).
    case emoji
}

extension KeyAction {
    /// 只有真正写/删字、改语言或换页面的动作才该让联想条消失。
    /// .shift / .globe / 空 composition 下的 .page 与 .settings 不改变文本，
    /// 不该让一条刚出现的联想凭空空掉（Krug：别让我想；Norman：状态变化要可归因）。
    var endsSuggestions: Bool {
        switch self {
        case .char, .delete, .space, .ret, .t9, .clearInput, .deleteWord, .emoji, .toggleLanguage, .page, .settings:
            return true
        case .shift, .globe:
            return false
        }
    }
}

enum KeyStyle: Equatable { case normal, function, accent }

struct KeySpec: Equatable {
    var action: KeyAction
    var label: String
    var symbol: String? = nil        // SF Symbol name
    var width: CGFloat = 1           // in letter-key units (1 = screen width / 10); 0 = flexible
    var alt: String? = nil           // long-press alternate
    var style: KeyStyle = .normal
    var isLetter: Bool = false
    var hint: String? = nil          // small corner label (top-row digits, like Gboard)
    /// 小鹤键位提示: the initial (zh / ch / sh) and finals this letter stands for, drawn under the letter
    var guideInitial: String? = nil
    var guideFinals: [String] = []
    var guideChordHint: XiaoheScheme.ChordHint? = nil
    var moreAlts: [String] = []      // further long-press choices after `alt`, shown as a row
    /// Contextual smart action shown directly on the spacebar (e.g. `跳出 》` or `= 383`).
    var isSmartSpace: Bool = false
}

struct LayoutContext: Equatable {
    var page: KeyboardPage
    var chinese: Bool
    var showGlobe: Bool
    /// nil = default return key (drawn as the ↵ icon); otherwise the host's action title.
    var returnLabel: String?
    var returnIsAccent: Bool
    var shifted: Bool
    var capsLock: Bool
    var keyBorders: Bool
    /// 123 opens the 九宫格 number pad (on) or Gboard's full 123 page (off).
    var numberGrid: Bool = true
    /// Chinese letters on the 九宫格 pinyin keypad instead of the full keyboard.
    var pinyinGrid: Bool = false
    /// Something is being composed (重输 and 分词 apply).
    var composing: Bool = false
    /// 小鹤键位提示: the letter keys show the initials and finals of 小鹤双拼 (learning mode)
    var xiaoheGuide: Bool = false
    /// Pending odd-beat first key when `xiaoheGuide` is active, illuminating only valid final keys.
    var xiaohePendingInitial: Character? = nil
    /// Contextual spacebar label override (`跳出 》` for smart CJK pairs or `= 383` for trailing math).
    var spaceOverride: String? = nil
}

/// Geometry aligned with Gboard iOS & native Apple Chinese keyboard (42 pt bar + 4×54 pt = 258 pt portrait,
/// 38 pt bar + 4×40 pt = 198 pt landscape). Locked to a single calibrated height so host containers never bounce.
/// Bottom rows: letters 1.25 | 1.125 | 1.125 | space 4 | 1 | 1.5; symbol pages 1.25 | 1.125 | 1.125 | 4 | 2.5.
/// Symbol third rows: 1.5 | 6 × 7/6 | 1.5. Every page fits on screen, nothing scrolls.
enum Metrics {
    /// The system keyboard's candidate / prediction strip (no separate pinyin line: the pinyin goes into the field).
    static let toolbarHeight: CGFloat = 42
    static let rowPitch: CGFloat = 54
    static let rowPitchLandscape: CGFloat = 40
    static let toolbarHeightLandscape: CGFloat = 38
    static let gapX: CGFloat = 5.5
    static let gapY: CGFloat = 11
    /// Outer horizontal breathing inset so edge keys (q/p, 123/return) sit cleanly inside iOS 26/27 rounded Liquid Glass.
    static let sideInset: CGFloat = 4.5
    static let sideInsetLandscape: CGFloat = 4.0
    /// Precision 1.0 pt bottom contact grounding across both styles.
    static var lip: CGFloat { 1.0 }
    /// Apple continuous squircle cap corners.
    static var cornerRadius: CGFloat { Theme.plain ? 8.5 : 9.5 }
    static let letterFont: CGFloat = 24
    static let symbolFont: CGFloat = 24
    static let functionFont: CGFloat = 15.5
    static let hintFont: CGFloat = 11
    static let iconSize: CGFloat = 20.5

    static func toolbarHeight(landscape: Bool) -> CGFloat {
        landscape ? toolbarHeightLandscape : toolbarHeight
    }

    static func totalHeight(landscape: Bool) -> CGFloat {
        landscape ? (toolbarHeightLandscape + 4 * rowPitchLandscape) : (toolbarHeight + 4 * rowPitch)
    }

    static func maxAdaptiveHeight(landscape: Bool) -> CGFloat {
        landscape ? 224 : 308
    }

    /// Optical letter font size anchored at baseline 40 pt cap height -> 24 pt, scaled in 0.5 pt steps.
    static func letterFontSize(forCapHeight capHeight: CGFloat) -> CGFloat {
        let raw = letterFont + (capHeight - 40) * 0.25
        let clamped = min(26.5, max(20.5, raw))
        return (clamped * 2).rounded() / 2
    }
}

enum Layouts {
    static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    static let topRowDigits = Array("1234567890").map(String.init)
    static let sixth: CGFloat = 7.0 / 6.0

    static func rows(_ ctx: LayoutContext) -> [[KeySpec]] {
        switch ctx.page {
        case .letters: return ctx.pinyinGrid && ctx.chinese ? pinyinPad(ctx) : letters(ctx)
        case .numbers: return numbers(ctx)
        case .symbols: return symbols(ctx)
        case .numpad: return numpad(ctx)
        }
    }

    /// The emoji key: 表情 on a tap, the keyboard settings on a long press (as on Gboard).
    static let emojiKey = KeySpec(action: .emoji, label: "", symbol: "face.smiling", width: 1, style: .function)

    /// Second and third keys of every bottom row: 表情 (or the system globe when the device needs it) and the 中/英
    /// switch, where the iOS and Gboard keyboards have them.
    /// On a device that needs the globe (Home button), the globe comes first and 表情 stays beside it: emoji and the
    /// settings (long press) are never lost to the system key.
    private static func middleKeys(_ ctx: LayoutContext) -> [KeySpec] {
        let globe = KeySpec(action: .globe, label: "", symbol: "globe", width: 1, style: .function)
        let lang = KeySpec(action: .toggleLanguage, label: ctx.chinese ? "中" : "英", width: 1, style: .function)
        return ctx.showGlobe ? [globe, emojiKey, lang] : [emojiKey, lang]
    }

    /// As on the system keyboard: 换行 / return, the host's action (搜索, 发送…) in blue, 确认 while composing.
    private static func returnKey(_ ctx: LayoutContext, width: CGFloat, wide: Bool) -> KeySpec {
        // always Mosto's crown gold: the one key every message ends on
        if let l = ctx.returnLabel {
            return KeySpec(action: .ret, label: l, width: width, style: .accent)
        }
        return KeySpec(action: .ret, label: ctx.chinese ? "换行" : "return", width: width, style: .accent)
    }

    private static func spaceKey(_ ctx: LayoutContext) -> KeySpec {
        if let label = ctx.spaceOverride {
            return KeySpec(action: .space, label: label, width: 0, isSmartSpace: true)
        }
        return KeySpec(action: .space, label: ctx.chinese ? "空格" : "space", width: 0)
    }

    private static func letters(_ ctx: LayoutContext) -> [[KeySpec]] {
        var rows: [[KeySpec]] = []
        for (r, row) in letterRows.enumerated() {
            var specs: [KeySpec] = []
            for c in row {
                let upper = ctx.shifted || ctx.capsLock
                let label = upper ? String(c).uppercased() : String(c)
                // letters are plain: no corner digits, no long-press symbols (digits and symbols live on 123 / #+=)
                var spec = KeySpec(action: .char(String(c)), label: label, isLetter: true)
                if ctx.xiaoheGuide, ctx.chinese, let g = XiaoheScheme.keyGuide[c] {
                    spec.guideInitial = g.initial
                    spec.guideFinals = g.finals
                    spec.guideChordHint = XiaoheScheme.chordHint(forKey: c, after: ctx.xiaohePendingInitial)
                }
                specs.append(spec)
            }
            if r == 2 {
                let shiftSymbol = ctx.capsLock ? "capslock.fill" : (ctx.shifted ? "shift.fill" : "shift")
                // engaged shift reads as a white cap with a solid arrow, as on the iOS keyboard
                let engaged = ctx.shifted || ctx.capsLock
                specs.insert(KeySpec(action: .shift, label: "", symbol: shiftSymbol, width: 1.5, style: engaged ? .normal : .function), at: 0)
                specs.append(KeySpec(action: .delete, label: "", symbol: "delete.left", width: 1.5, style: .function))
            }
            rows.append(specs)
        }
        var bottom: [KeySpec] = [KeySpec(action: .page(ctx.numberGrid ? .numpad : .numbers), label: "123", width: 1.25, style: .function)]
        bottom += middleKeys(ctx)
        bottom.append(spaceKey(ctx))
        bottom.append(ctx.chinese
            ? KeySpec(action: .char("，"), label: "，", width: 1, alt: "。", style: .function, hint: "。", moreAlts: ["？", "！", "、", "…", "《", "（"])
            : KeySpec(action: .char("."), label: ".", width: 1, alt: ",", style: .function, hint: ",", moreAlts: ["?", "!", "'", "\"", "-"]))
        bottom.append(returnKey(ctx, width: ctx.showGlobe ? 1.75 : 2, wide: false))
        rows.append(bottom)
        return rows
    }

    private static func charRow(_ s: [String], width: CGFloat = 1, alts: [String: String] = [:], hints: [String: String] = [:]) -> [KeySpec] {
        s.map { KeySpec(action: .char($0), label: $0, width: width, alt: alts[$0], hint: hints[$0] ?? alts[$0]) }
    }

    private static func bottomRow(_ ctx: LayoutContext) -> [KeySpec] {
        var bottom: [KeySpec] = [KeySpec(action: .page(.letters), label: ctx.chinese ? "拼音" : "ABC", width: 1.25, style: .function)]
        bottom += middleKeys(ctx)
        bottom.append(spaceKey(ctx))
        bottom.append(returnKey(ctx, width: 2.5, wide: true))
        return bottom
    }

    private static func numbers(_ ctx: LayoutContext) -> [[KeySpec]] {
        let row1 = charRow(topRowDigits)
        let row2 = ctx.chinese
            ? charRow(["-", "/", "：", "；", "（", "）", "¥", "@", "“", "”"], alts: ["-": "—", "/": "、", "：": ":", "；": ";", "（": "【", "）": "】", "¥": "$", "@": "#", "“": "「", "”": "」"])
            : charRow(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
        var row3: [KeySpec] = [KeySpec(action: .page(.symbols), label: "#+=", width: 1.5, style: .function)]
        row3 += ctx.chinese
            ? charRow(["。", "，", "、", "？", "！", "."], width: sixth, alts: ["。": "…", "，": "；", "、": "·", "？": "?", "！": "!", ".": "…"])
            : charRow([".", ",", "?", "!", "'", "%"], width: sixth)
        row3.append(KeySpec(action: .delete, label: "", symbol: "delete.left", width: 1.5, style: .function))
        return [row1, row2, row3, bottomRow(ctx)]
    }

    /// 九宫格 pinyin keypad, as on the system keyboard: the phone keypad (1 分词, 2 ABC … 9 WXYZ) in the middle,
    /// ， 。 ？ on the left, delete / 重输 / return on the right; 123, settings, 符号, space and 中/英 below.
    /// Each key stands for all its letters; the decoder sorts out which were meant (小鹤双拼 and 全拼 alike).
    private static func pinyinPad(_ ctx: LayoutContext) -> [[KeySpec]] {
        let side: CGFloat = 1.6, mid: CGFloat = 6.8 / 3
        func k(_ d: Character, _ label: String) -> KeySpec { KeySpec(action: .t9(d), label: label, width: mid) }
        func p(_ s: String, _ alt: String?, more: [String] = []) -> KeySpec {
            KeySpec(action: .char(s), label: s, width: side, alt: alt, style: .function, hint: alt, moreAlts: more)
        }
        let row1 = [p("，", "、", more: ["：", "；", "（", "《", "“"]), k("'", "分词"), k("2", "ABC"), k("3", "DEF"),
                    KeySpec(action: .delete, label: "", symbol: "delete.left", width: side, style: .function)]
        let row2 = [p("。", "…", more: ["·", "—", "）", "》", "”"]), k("4", "GHI"), k("5", "JKL"), k("6", "MNO"),
                    KeySpec(action: .clearInput, label: "重输", width: side, style: .function)]
        let row3 = [p("？", "！", more: ["～", "【", "】", "「", "」"]), k("7", "PQRS"), k("8", "TUV"), k("9", "WXYZ"), returnKey(ctx, width: side, wide: true)]
        let gear: [KeySpec] = ctx.showGlobe
            ? [KeySpec(action: .globe, label: "", symbol: "globe", width: 1, style: .function), emojiKey]
            : [emojiKey]
        let row4 = [KeySpec(action: .page(ctx.numberGrid ? .numpad : .numbers), label: "123", width: side, style: .function)]
                    + gear
                    + [KeySpec(action: .page(.symbols), label: "符号", width: mid - 1 + 0.27, style: .function),
                       spaceKey(ctx),
                       KeySpec(action: .toggleLanguage, label: "中", width: side, style: .function)]
        return [row1, row2, row3, row4]
    }

    /// 九宫格 number pad: a phone keypad in the middle (1–9, 0 below 8), common number punctuation on the left,
    /// delete / space / return on the right. 符号 opens the full 123 page; 返回 goes back to the letters.
    /// Half-width "." and ":" in both languages, as numbers, decimals and times are written.
    private static func numpad(_ ctx: LayoutContext) -> [[KeySpec]] {
        let side: CGFloat = 2, digit: CGFloat = 2
        func d(_ s: String) -> KeySpec { KeySpec(action: .char(s), label: s, width: digit) }
        func p(_ s: String, _ alt: String? = nil) -> KeySpec { KeySpec(action: .char(s), label: s, width: side, alt: alt, style: .function, hint: alt) }
        let row1 = [p("+", "="), d("1"), d("2"), d("3"),
                    KeySpec(action: .delete, label: "", symbol: "delete.left", width: side, style: .function)]
        let row2 = [p("-", "_"), d("4"), d("5"), d("6"),
                    KeySpec(action: .space, label: ctx.chinese ? "空格" : "space", width: side)]
        let row3 = [p("/", "*"), d("7"), d("8"), d("9"), returnKey(ctx, width: side, wide: true)]
        // the way back keeps its full width (and the same name as on every other page); with the globe key the two
        // punctuation keys give it the room
        let back = KeySpec(action: .page(.letters), label: ctx.chinese ? "拼音" : "ABC", width: ctx.showGlobe ? 1.5 : side, style: .function)
        var row4: [KeySpec] = ctx.showGlobe ? [back, KeySpec(action: .globe, label: "", symbol: "globe", width: 1.2, style: .function)] : [back]
        let dotW: CGFloat = ctx.showGlobe ? 1.3 : side
        let colonW: CGFloat = side
        row4 += [KeySpec(action: .char("."), label: ".", width: dotW, alt: ",", style: .function, hint: ","), d("0"),
                 KeySpec(action: .char(":"), label: ":", width: colonW, alt: "%", style: .function, hint: "%"),
                 KeySpec(action: .page(.numbers), label: ctx.chinese ? "符号" : "#+=", width: side, style: .function)]
        return [row1, row2, row3, row4]
    }

    private static func symbols(_ ctx: LayoutContext) -> [[KeySpec]] {
        let row1 = ctx.chinese
            ? charRow(["【", "】", "｛", "｝", "#", "%", "^", "*", "+", "="], alts: ["【": "「", "】": "」", "｛": "『", "｝": "』"])
            : charRow(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
        let row2 = ctx.chinese
            ? charRow(["_", "—", "\\", "|", "～", "《", "》", "$", "&", "·"], alts: ["《": "〈", "》": "〉", "～": "°", "$": "€", "·": "•"])
            : charRow(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"], alts: ["~": "°"])
        var row3: [KeySpec] = [KeySpec(action: .page(.numbers), label: "123", width: 1.5, style: .function)]
        row3 += ctx.chinese
            ? charRow(["…", "，", "^_^", "？", "！", "'"], width: sixth, alts: ["…": "——", "^_^": "ψ(｀∇´)ψ", "'": "’"], hints: ["…": "—", "^_^": "ψ"])
            : charRow([".", ",", "?", "!", "'", "`"], width: sixth)
        row3.append(KeySpec(action: .delete, label: "", symbol: "delete.left", width: 1.5, style: .function))
        return [row1, row2, row3, bottomRow(ctx)]
    }
}

/// Mosto 潮玩: the keyboard is made of the same stuff as Mosto — matte soft vinyl in his colours. Every key is a
/// little toy cap: a face over a darker lip (it sinks when pressed), rounded type, a matte-gold action key like his
/// crown, his bat wings on the space bar. Two lights, as in Moss & Otto: 日光 (cream and lavender vinyl on a lavender
/// tint) and 夜灯 (violet vinyl under the gold glow of his tail). They map onto the light / dark trait, so every
/// colour below resolves by itself; the keyboard forces the trait when the user picks 日光 or 夜灯.
/// The keyboard's own background is a tint over the system's Liquid Glass (an opaque one shows up as a band).
enum Theme {
    static func dyn(_ day: UIColor, _ night: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? night : day }
    }
    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }
    /// Mosto's colours (Tools/ip/mosto3d.py, palette lilac).
    static let violet = hex(0x633EBF), deepViolet = hex(0x2B1961), cream = hex(0xFFE4A8), gold = hex(0xD69A34)
    static let goldGlow = hex(0xFFC45A)

    /// 简洁 (无主题): plain keys in the system's greys, no Mosto, the system type — 日光 and 夜光.
    static var plain = false

    private struct FontKey: Hashable { let plain: Bool; let size10: Int; let weight: CGFloat }
    private static var fontCache: [FontKey: UIFont] = [:]

    /// The toy's type: SF Rounded (Chinese falls back to the system face); the system face when plain. Cached per (style, size, weight).
    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .medium) -> UIFont {
        let key = FontKey(plain: plain, size10: Int((size * 10).rounded()), weight: weight.rawValue)
        if let cached = fontCache[key] { return cached }
        let f = UIFont.systemFont(ofSize: size, weight: weight)
        let resolved: UIFont
        if plain {
            resolved = f
        } else if let d = f.fontDescriptor.withDesign(.rounded) {
            resolved = UIFont(descriptor: d, size: size)
        } else {
            resolved = f
        }
        fontCache[key] = resolved
        return resolved
    }

    static let glassTint = UIColor.clear
    static let forcedNightTint = UIColor.clear
    static let forcedDayTint = UIColor.clear
    /// Uniform touch-hit backing on root (invisible 1.2% grey prevents iOS extension gap drops without dark banding).
    static let touchable = UIColor(white: 0.5, alpha: 0.012)
    /// Opaque panels over the keys (candidate grid, settings).
    static var panel: UIColor { plain ? plain_panel : mosto_panel }
    private static let mosto_panel: UIColor = dyn(hex(0xF0EDF6), hex(0x191625))
    private static let plain_panel: UIColor = dyn(hex(0xF2F2F7), hex(0x1C1C1E))
    /// Settings: grouped background, rounded groups, hairline separators.
    static var settingsGroup: UIColor { plain ? plain_settingsGroup : mosto_settingsGroup }
    private static let mosto_settingsGroup: UIColor = dyn(UIColor(white: 1, alpha: 0.88), hex(0x2E2942, 0.72))
    private static let plain_settingsGroup: UIColor = dyn(UIColor(white: 1, alpha: 0.9), UIColor(white: 1, alpha: 0.08))
    static var separator: UIColor { plain ? plain_separator : mosto_separator }

    // Monolith matte vinyl caps (Day: ceramic ivory + cool lavender stone + brushed gold; Night: obsidian charcoal-violet).
    private static let mosto_separator: UIColor = dyn(hex(0x22193D, 0.12), UIColor(white: 1, alpha: 0.12))
    private static let plain_separator: UIColor = dyn(UIColor(white: 0, alpha: 0.12), UIColor(white: 1, alpha: 0.12))
    static var key: UIColor { plain ? plain_key : mosto_key }
    private static let mosto_key: UIColor = dyn(hex(0xFCFBF8), hex(0x2D283E))
    private static let plain_key: UIColor = dyn(hex(0xFFFFFF), hex(0x3D3E43))
    static var keyTop: UIColor { plain ? plain_keyTop : mosto_keyTop }
    private static let mosto_keyTop = mosto_key
    private static let plain_keyTop: UIColor = plain_key
    static var keyLip: UIColor { plain ? plain_keyLip : mosto_keyLip }
    private static let mosto_keyLip: UIColor = dyn(hex(0xD3CCE2), hex(0x161321))
    private static let plain_keyLip: UIColor = dyn(hex(0xBEC3CE), hex(0x16171A))
    static var keyPressed: UIColor { plain ? plain_keyPressed : mosto_keyPressed }
    private static let mosto_keyPressed: UIColor = dyn(hex(0xE9E3F5), hex(0x413A59))
    private static let plain_keyPressed: UIColor = dyn(hex(0xE5E7EE), hex(0x565860))
    static var functionKey: UIColor { plain ? plain_functionKey : mosto_functionKey }
    private static let mosto_functionKey: UIColor = dyn(hex(0xE6E1F0), hex(0x1F1C2C))
    private static let plain_functionKey: UIColor = dyn(hex(0xD2D6E0), hex(0x28292E))
    static var functionTop: UIColor { plain ? plain_functionTop : mosto_functionTop }
    private static let mosto_functionTop = mosto_functionKey
    private static let plain_functionTop: UIColor = plain_functionKey
    static var functionLip: UIColor { plain ? plain_functionLip : mosto_functionLip }
    private static let mosto_functionLip: UIColor = dyn(hex(0xBFB5D6), hex(0x12101B))
    private static let plain_functionLip: UIColor = dyn(hex(0xB0B6C4), hex(0x121316))
    static var functionPressed: UIColor { plain ? plain_functionPressed : mosto_functionPressed }
    private static let mosto_functionPressed: UIColor = dyn(hex(0xD5CCE8), hex(0x342F49))
    private static let plain_functionPressed: UIColor = dyn(hex(0xFFFFFF), hex(0x43444B))
    static var accentKey: UIColor { plain ? plain_accentKey : mosto_accentKey }
    private static let mosto_accentKey: UIColor = dyn(hex(0xDFA940), hex(0xD8A13B))
    private static let plain_accentKey: UIColor = dyn(hex(0x007AFF), hex(0x0A84FF))
    static var accentTop: UIColor { plain ? plain_accentTop : mosto_accentTop }
    private static let mosto_accentTop = mosto_accentKey
    private static let plain_accentTop: UIColor = plain_accentKey
    static var accentPressed: UIColor { plain ? plain_accentPressed : mosto_accentPressed }
    private static let mosto_accentPressed: UIColor = dyn(hex(0xC9922C), hex(0xBE8828))
    private static let plain_accentPressed: UIColor = dyn(hex(0x0062CC), hex(0x0070E0))
    static var accentLip: UIColor { plain ? plain_accentLip : mosto_accentLip }
    private static let mosto_accentLip: UIColor = dyn(hex(0xB37E20), hex(0x8C6115))
    private static let plain_accentLip: UIColor = dyn(hex(0x005EC4), hex(0x005BBF))
    static var accentText: UIColor { plain ? plain_accentText : mosto_accentText }
    private static let mosto_accentText: UIColor = hex(0x241748)
    private static let plain_accentText: UIColor = UIColor.white
    static var keyBorder: UIColor { plain ? plain_keyBorder : mosto_keyBorder }
    private static let mosto_keyBorder: UIColor = dyn(hex(0x22193D, 0.08), UIColor(white: 1, alpha: 0.09))
    private static let plain_keyBorder: UIColor = dyn(UIColor(white: 0, alpha: 0.08), UIColor(white: 1, alpha: 0.10))
    static var statusLedActive: UIColor { plain ? plain_statusLedActive : mosto_statusLedActive }
    private static let mosto_statusLedActive: UIColor = dyn(hex(0x6B47C8), hex(0xE8B752))
    private static let plain_statusLedActive: UIColor = dyn(hex(0x007AFF), hex(0x0A84FF))
    static var statusLedMuted: UIColor { dyn(UIColor(white: 0, alpha: 0.16), UIColor(white: 1, alpha: 0.22)) }
    static var spaceNotch: UIColor { plain ? plain_spaceNotch : mosto_spaceNotch }
    private static let mosto_spaceNotch: UIColor = dyn(hex(0x22193D, 0.22), hex(0xF3EDE2, 0.26))
    private static let plain_spaceNotch: UIColor = dyn(UIColor(white: 0, alpha: 0.16), UIColor(white: 1, alpha: 0.22))
    /// Softened ceramic key tones when 日光 keys sit over Dark system Liquid Glass (Spotlight / dark apps).
    static var forcedDayKey: UIColor { plain ? hex(0xEAECEF) : hex(0xF1EDF6) }
    static var forcedDayKeyPressed: UIColor { plain ? hex(0xD8DCE4) : hex(0xE1DAE9) }
    static var forcedDayKeyLip: UIColor { plain ? hex(0x8D93A0) : hex(0x988FB0) }
    static var forcedDayFunctionKey: UIColor { plain ? hex(0xC6CBD6) : hex(0xDDD7EB) }
    static var forcedDayFunctionPressed: UIColor { plain ? hex(0xDDE1EA) : hex(0xCCC4E0) }
    static var forcedDayFunctionLip: UIColor { plain ? hex(0x7C828F) : hex(0x8B81A6) }
    static var bubble: UIColor { plain ? plain_bubble : mosto_bubble }
    private static let mosto_bubble: UIColor = dyn(hex(0xFFFFFF), hex(0x3A3450))
    private static let plain_bubble: UIColor = dyn(hex(0xFFFFFF), hex(0x52535A))
    static var bubbleLip: UIColor { plain ? plain_bubbleLip : mosto_bubbleLip }
    private static let mosto_bubbleLip: UIColor = dyn(hex(0xCFC7E0), hex(0x524A6E))
    private static let plain_bubbleLip: UIColor = dyn(hex(0xC2C7D0), hex(0x232428))
    static var wing: UIColor { plain ? plain_wing : mosto_wing }
    private static let mosto_wing: UIColor = dyn(hex(0xAE99E8), hex(0x6E59C9))
    private static let plain_wing: UIColor = UIColor.clear
    static var keyText: UIColor { plain ? plain_keyText : mosto_keyText }
    private static let mosto_keyText: UIColor = dyn(hex(0x22193D), hex(0xF3EDE2))
    private static let plain_keyText: UIColor = dyn(hex(0x111216), hex(0xFFFFFF))
    static var functionText: UIColor { plain ? plain_functionText : mosto_functionText }
    private static let mosto_functionText: UIColor = dyn(hex(0x372B5C), hex(0xD4CCE8))
    private static let plain_functionText: UIColor = dyn(hex(0x1E2028), hex(0xF2F2F7))
    static var keyShadow: UIColor { plain ? plain_keyShadow : mosto_keyShadow }
    /// `a` moved `k` of the way towards `b` (opaque colours).
    private static let mosto_keyShadow = dyn(hex(0x2B1961, 0.09), UIColor(white: 0, alpha: 0.22))
    private static let plain_keyShadow: UIColor = dyn(UIColor(white: 0, alpha: 0.06), UIColor(white: 0, alpha: 0.28))
    static func mix(_ a: UIColor, _ b: UIColor, _ k: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k, alpha: a1 + (a2 - a1) * k)
    }
    static var candidateText: UIColor { keyText }
    static var secondaryText: UIColor { plain ? plain_secondaryText : mosto_secondaryText }
    /// 键位提示 finals on the letter caps: ≥ 4.5:1 on the cream face by day and the violet face at night
    private static let mosto_secondaryText: UIColor = dyn(hex(0x6A5C96), hex(0xB4A8DC))
    private static let plain_secondaryText: UIColor = dyn(hex(0x5F636E), hex(0xAEAEB2))
    static var preeditPillBg: UIColor { plain ? dyn(UIColor(white: 0, alpha: 0.07), UIColor(white: 1, alpha: 0.14)) : dyn(hex(0x633EBF, 0.10), UIColor(white: 1, alpha: 0.14)) }
    static var preeditPillBorder: UIColor { dyn(UIColor(white: 0, alpha: 0.06), UIColor(white: 1, alpha: 0.12)) }
    static var candidateDivider: UIColor { dyn(UIColor(white: 0, alpha: 0.11), UIColor(white: 1, alpha: 0.16)) }
    static var firstCandidateTint: UIColor { plain ? dyn(UIColor(white: 0, alpha: 0.05), UIColor(white: 1, alpha: 0.11)) : dyn(hex(0x633EBF, 0.09), hex(0xFFE4A8, 0.13)) }
    static var guideText: UIColor { plain ? plain_guideText : mosto_guideText }
    /// The correction mark, selected alternates: Mosto's violet by day, his gold at night.
    private static let mosto_guideText: UIColor = dyn(hex(0x5B4D8C), hex(0xDCD5F7))
    private static let plain_guideText: UIColor = dyn(hex(0x55555C), hex(0xD1D1D6))
    static var correctedMark: UIColor { plain ? plain_correctedMark : mosto_correctedMark }
    /// The correction caption under the first candidate (typed → meant), small type on the tinted pill: both halves
    /// at least 4.5 : 1 against the pill in every style and light.
    static var captionTyped: UIColor { plain ? dyn(hex(0x5A5A60), hex(0xB4B4BA)) : dyn(hex(0x55488A), hex(0xC8BEEA)) }
    static var captionMeant: UIColor { plain ? dyn(hex(0x0952B0), hex(0x7CC0FF)) : correctedMark }
    /// Behind the corrected first choice and the undo chip: a soft tint of the correction colour.
    private static let mosto_correctedMark: UIColor = dyn(hex(0x633EBF), hex(0xFFC45A))
    private static let plain_correctedMark: UIColor = dyn(hex(0x0A6CE0), hex(0x5EB0FF))
    static var correctedTint: UIColor { plain ? plain_correctedTint : mosto_correctedTint }
    private static let mosto_correctedTint: UIColor = dyn(hex(0x633EBF, 0.14), hex(0xFFC45A, 0.20))
    private static let plain_correctedTint: UIColor = dyn(hex(0x0A7CFF, 0.11), hex(0x0A84FF, 0.22))
    static var selection: UIColor { plain ? plain_selection : mosto_selection }
    private static let mosto_selection: UIColor = dyn(hex(0x633EBF), hex(0xE3B04F))
    private static let plain_selection: UIColor = dyn(hex(0x0A7CFF), hex(0x0A84FF))
    static var selectionText: UIColor { plain ? plain_selectionText : mosto_selectionText }
    private static let mosto_selectionText: UIColor = dyn(.white, hex(0x2B1961))
    private static let plain_selectionText: UIColor = UIColor.white
}

extension UIScrollView {
    /// Disables all four iOS 26+ Liquid Glass scroll-edge blur curtains so compact ribbons & panels stay razor-sharp.
    func disableAllEdgeEffects() {
        contentInsetAdjustmentBehavior = .never
        if #available(iOS 26.0, *) {
            topEdgeEffect.isHidden = true
            bottomEdgeEffect.isHidden = true
            leftEdgeEffect.isHidden = true
            rightEdgeEffect.isHidden = true
        }
    }
}
