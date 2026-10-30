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

enum KeyStyle { case normal, function, accent }

struct KeySpec {
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
    var moreAlts: [String] = []      // further long-press choices after `alt`, shown as a row
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
}

/// Geometry measured from Gboard iOS 2.3 on a 402 pt wide iPhone (1206 px screenshots):
/// toolbar 65 pt, row pitch 53 pt, key gaps ~5.5 pt × 11 pt, space bar 42 pt tall with ~6 pt corners,
/// borderless keys, letter glyphs ~24 pt. (Gboard's top-row digit hints and letter long-press symbols are left out.)
/// Bottom rows: letters 1.25 | 1.125 | 1.125 | space 4 | 1 | 1.5; symbol pages 1.25 | 1.125 | 1.125 | 4 | 2.5.
/// Symbol third rows: 1.5 | 6 × 7/6 | 1.5. Every page fits on screen, nothing scrolls.
enum Metrics {
    /// The system keyboard's candidate / prediction strip (no separate pinyin line: the pinyin goes into the field).
    static let toolbarHeight: CGFloat = 48
    static let rowPitch: CGFloat = 54
    static let rowPitchLandscape: CGFloat = 40
    static let toolbarHeightLandscape: CGFloat = 38
    static let gapX: CGFloat = 6
    static let gapY: CGFloat = 12
    /// The darker lip under each cap (the face sinks onto it when pressed).
    static var lip: CGFloat { Theme.plain ? 1.5 : 3 }
    /// Soft vinyl caps: rounder than the system keyboard's.
    static var cornerRadius: CGFloat { Theme.plain ? 6 : 10 }
    static let letterFont: CGFloat = 24
    static let symbolFont: CGFloat = 24
    static let functionFont: CGFloat = 16
    static let hintFont: CGFloat = 11
    static let iconSize: CGFloat = 21
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
        bottom.append(KeySpec(action: .space, label: ctx.chinese ? "空格" : "space", width: 0))
        bottom.append(ctx.chinese
            ? KeySpec(action: .char("，"), label: "，", width: 1, alt: "。", style: .function, moreAlts: ["？", "！", "、", "…", "："])
            : KeySpec(action: .char("."), label: ".", width: 1, alt: ",", style: .function, moreAlts: ["?", "!", "'", ":"]))
        bottom.append(returnKey(ctx, width: ctx.showGlobe ? 1.75 : 2, wide: false))
        rows.append(bottom)
        return rows
    }

    private static func charRow(_ s: [String], width: CGFloat = 1, alts: [String: String] = [:]) -> [KeySpec] {
        s.map { KeySpec(action: .char($0), label: $0, width: width, alt: alts[$0]) }
    }

    private static func bottomRow(_ ctx: LayoutContext) -> [KeySpec] {
        var bottom: [KeySpec] = [KeySpec(action: .page(.letters), label: ctx.chinese ? "拼音" : "ABC", width: 1.25, style: .function)]
        bottom += middleKeys(ctx)
        bottom.append(KeySpec(action: .space, label: ctx.chinese ? "空格" : "space", width: 0))
        bottom.append(returnKey(ctx, width: 2.5, wide: true))
        return bottom
    }

    private static func numbers(_ ctx: LayoutContext) -> [[KeySpec]] {
        let row1 = charRow(topRowDigits)
        let row2 = ctx.chinese
            ? charRow(["-", "/", "：", "；", "（", "）", "¥", "@", "“", "”"], alts: ["“": "‘", "”": "’", "¥": "￥"])
            : charRow(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
        var row3: [KeySpec] = [KeySpec(action: .page(.symbols), label: "#+=", width: 1.5, style: .function)]
        row3 += ctx.chinese
            ? charRow(["。", "，", "、", "？", "！", "."], width: sixth, alts: ["。": "…"])
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
        func p(_ s: String, _ alt: String?) -> KeySpec { KeySpec(action: .char(s), label: s, width: side, alt: alt, style: .function) }
        let row1 = [p("，", "、"), k("'", "分词"), k("2", "ABC"), k("3", "DEF"),
                    KeySpec(action: .delete, label: "", symbol: "delete.left", width: side, style: .function)]
        let row2 = [p("。", "…"), k("4", "GHI"), k("5", "JKL"), k("6", "MNO"),
                    KeySpec(action: .clearInput, label: "重输", width: side, style: .function)]
        let row3 = [p("？", "！"), k("7", "PQRS"), k("8", "TUV"), k("9", "WXYZ"), returnKey(ctx, width: side, wide: true)]
        let gear: [KeySpec] = ctx.showGlobe
            ? [KeySpec(action: .globe, label: "", symbol: "globe", width: 1, style: .function), emojiKey]
            : [emojiKey]
        let row4 = [KeySpec(action: .page(ctx.numberGrid ? .numpad : .numbers), label: "123", width: side, style: .function)]
                    + gear
                    + [KeySpec(action: .page(.symbols), label: "符号", width: mid - 1 + 0.27, style: .function),
                       KeySpec(action: .space, label: "空格", width: 0),
                       KeySpec(action: .toggleLanguage, label: "中", width: side, style: .function)]
        return [row1, row2, row3, row4]
    }

    /// 九宫格 number pad: a phone keypad in the middle (1–9, 0 below 8), common number punctuation on the left,
    /// delete / space / return on the right. 符号 opens the full 123 page; 返回 goes back to the letters.
    /// Half-width "." and ":" in both languages, as numbers, decimals and times are written.
    private static func numpad(_ ctx: LayoutContext) -> [[KeySpec]] {
        let side: CGFloat = 2, digit: CGFloat = 2
        func d(_ s: String) -> KeySpec { KeySpec(action: .char(s), label: s, width: digit) }
        func p(_ s: String, _ alt: String? = nil) -> KeySpec { KeySpec(action: .char(s), label: s, width: side, alt: alt, style: .function) }
        let row1 = [p("+", "="), d("1"), d("2"), d("3"),
                    KeySpec(action: .delete, label: "", symbol: "delete.left", width: side, style: .function)]
        let row2 = [p("-", "_"), d("4"), d("5"), d("6"),
                    KeySpec(action: .space, label: ctx.chinese ? "空格" : "space", width: side)]
        let row3 = [p("/", "*"), d("7"), d("8"), d("9"), returnKey(ctx, width: side, wide: true)]
        // the way back keeps its full width (and the same name as on every other page); with the globe key the two
        // punctuation keys give it the room
        let back = KeySpec(action: .page(.letters), label: ctx.chinese ? "拼音" : "ABC", width: side, style: .function)
        var row4: [KeySpec] = ctx.showGlobe ? [back, KeySpec(action: .globe, label: "", symbol: "globe", width: 1.2, style: .function)] : [back]
        let punct: CGFloat = ctx.showGlobe ? 1.4 : side
        row4 += [KeySpec(action: .char("."), label: ".", width: punct, alt: ",", style: .function), d("0"),
                 KeySpec(action: .char(":"), label: ":", width: punct, alt: "%", style: .function),
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
            ? charRow(["…", "，", "^_^", "？", "！", "'"], width: sixth, alts: ["'": "’"])
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

    /// 简洁 (无主题): plain keys in the system's greys, no Mosto, no wings or crown, the system type — 日光 and 夜光.
    static var plain = false

    /// The toy's type: SF Rounded (Chinese falls back to the system face); the system face when plain.
    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .medium) -> UIFont {
        let f = UIFont.systemFont(ofSize: size, weight: weight)
        if plain { return f }
        guard let d = f.fontDescriptor.withDesign(.rounded) else { return f }
        return UIFont(descriptor: d, size: size)
    }

    /// No tint over the system glass: the system draws its glass beyond the keyboard's view (the margin above the
    /// strip, the globe row below), so any colour laid on it shows as a box inside a grey frame. The keys are the toy;
    /// the glass stays the system's, by day and at night alike.
    static let glassTint = UIColor.clear
    static let forcedNightTint = UIColor.clear
    static let forcedDayTint = UIColor.clear
    /// The keyboard's own surfaces: almost invisible (2 % grey over the system glass) but never fully transparent —
    /// inside a keyboard extension iOS does not deliver a touch that lands on a fully transparent point, even in a
    /// view that would take it. With clear backgrounds, fast taps landing in the gaps between keys, above the top row
    /// or in the empty strip were simply lost ("打空").
    static let touchable = UIColor(white: 0.5, alpha: 0.02)
    /// Opaque panels over the keys (candidate grid, settings).
    static var panel: UIColor { plain ? plain_panel : mosto_panel }   // opaque: keys must not show through a panel
    private static let mosto_panel: UIColor = dyn(hex(0xEEE8F8), hex(0x1D1442))
    private static let plain_panel: UIColor = dyn(hex(0xF2F2F7), hex(0x1C1C1E))
    /// Settings: grouped background, rounded groups, hairline separators.
    static var settingsGroup: UIColor { plain ? plain_settingsGroup : mosto_settingsGroup }
    private static let mosto_settingsGroup: UIColor = dyn(UIColor(white: 1, alpha: 0.85), hex(0x3A2C7A, 0.55))
    private static let plain_settingsGroup: UIColor = dyn(UIColor(white: 1, alpha: 0.9), UIColor(white: 1, alpha: 0.08))
    static var separator: UIColor { plain ? plain_separator : mosto_separator }

    // Vinyl caps: face (top → bottom) over a darker lip.
    private static let mosto_separator: UIColor = dyn(hex(0x2B1961, 0.12), UIColor(white: 1, alpha: 0.12))
    private static let plain_separator: UIColor = dyn(UIColor(white: 0, alpha: 0.12), UIColor(white: 1, alpha: 0.12))
    static var key: UIColor { plain ? plain_key : mosto_key }              // letter face
    private static let mosto_key: UIColor = dyn(hex(0xFBF8FF), hex(0x46378C))
    private static let plain_key: UIColor = dyn(hex(0xFFFFFF), hex(0x5A5A5E))
    static var keyTop: UIColor { plain ? plain_keyTop : mosto_keyTop }
    private static let mosto_keyTop: UIColor = dyn(hex(0xFFFFFF), hex(0x52429E))
    private static let plain_keyTop: UIColor = dyn(hex(0xFFFFFF), hex(0x606064))
    static var keyLip: UIColor { plain ? plain_keyLip : mosto_keyLip }
    private static let mosto_keyLip: UIColor = dyn(hex(0xCDBFEB), hex(0x1B1248))
    private static let plain_keyLip: UIColor = dyn(hex(0xB3B6BD), hex(0x2B2B2E))
    static var keyPressed: UIColor { plain ? plain_keyPressed : mosto_keyPressed }
    private static let mosto_keyPressed: UIColor = dyn(hex(0xEDE6FA), hex(0x5A4AAE))
    private static let plain_keyPressed: UIColor = dyn(hex(0xE4E5E9), hex(0x75757A))
    static var functionKey: UIColor { plain ? plain_functionKey : mosto_functionKey }      // function face (lavender / deep violet)
    private static let mosto_functionKey: UIColor = dyn(hex(0xC7B8F0), hex(0x2D2168))
    private static let plain_functionKey: UIColor = dyn(hex(0xADB2BC), hex(0x3A3A3D))
    static var functionTop: UIColor { plain ? plain_functionTop : mosto_functionTop }
    private static let mosto_functionTop: UIColor = dyn(hex(0xD3C6F6), hex(0x35286F))
    private static let plain_functionTop: UIColor = dyn(hex(0xB3B8C1), hex(0x3E3E41))
    static var functionLip: UIColor { plain ? plain_functionLip : mosto_functionLip }
    private static let mosto_functionLip: UIColor = dyn(hex(0x9682D6), hex(0x120B33))
    private static let plain_functionLip: UIColor = dyn(hex(0x8A8E96), hex(0x1E1E20))
    static var functionPressed: UIColor { plain ? plain_functionPressed : mosto_functionPressed }
    private static let mosto_functionPressed: UIColor = dyn(hex(0xFFFDF8), hex(0x46378C))
    private static let plain_functionPressed: UIColor = dyn(hex(0xFFFFFF), hex(0x5A5A5E))
    static var accentKey: UIColor { plain ? plain_accentKey : mosto_accentKey }         // the crown: matte gold
    private static let mosto_accentKey: UIColor = dyn(hex(0xE7B85A), hex(0xE3B04F))
    private static let plain_accentKey: UIColor = dyn(hex(0x0A7CFF), hex(0x0A84FF))
    static var accentTop: UIColor { plain ? plain_accentTop : mosto_accentTop }
    private static let mosto_accentTop: UIColor = dyn(hex(0xF0CA78), hex(0xEDC26C))
    private static let plain_accentTop: UIColor = dyn(hex(0x2B8EFF), hex(0x2A93FF))
    static var accentLip: UIColor { plain ? plain_accentLip : mosto_accentLip }
    private static let mosto_accentLip: UIColor = dyn(hex(0xA9741F), hex(0x7C5112))
    private static let plain_accentLip: UIColor = dyn(hex(0x0062CC), hex(0x0059B8))
    static var accentText: UIColor { plain ? plain_accentText : mosto_accentText }
    private static let mosto_accentText: UIColor = hex(0x2B1961)
    private static let plain_accentText: UIColor = UIColor.white
    static var keyHighlight: UIColor { plain ? plain_keyHighlight : mosto_keyHighlight }
    private static let mosto_keyHighlight: UIColor = dyn(UIColor(white: 1, alpha: 0.95), UIColor(white: 1, alpha: 0.16))
    private static let plain_keyHighlight: UIColor = dyn(UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0.10))
    static var bubble: UIColor { plain ? plain_bubble : mosto_bubble }
    private static let mosto_bubble: UIColor = dyn(hex(0xFFFDF8), hex(0x52429E))
    private static let plain_bubble: UIColor = dyn(hex(0xFFFFFF), hex(0x6A6A6E))
    static var bubbleLip: UIColor { plain ? plain_bubbleLip : mosto_bubbleLip }
    /// The wings on the space bar.
    private static let mosto_bubbleLip: UIColor = dyn(hex(0xCDBFEB), hex(0x1B1248))
    private static let plain_bubbleLip: UIColor = dyn(hex(0xB3B6BD), hex(0x2B2B2E))
    static var wing: UIColor { plain ? plain_wing : mosto_wing }
    private static let mosto_wing: UIColor = dyn(hex(0xB7A6E6), hex(0x2A1E66))
    private static let plain_wing: UIColor = UIColor.clear
    static var keyText: UIColor { plain ? plain_keyText : mosto_keyText }
    private static let mosto_keyText: UIColor = dyn(hex(0x2B1961), hex(0xFFF3DC))
    private static let plain_keyText: UIColor = dyn(hex(0x111114), hex(0xFFFFFF))
    static var functionText: UIColor { plain ? plain_functionText : mosto_functionText }
    /// The soft contact shadow under each cap.
    private static let mosto_functionText: UIColor = dyn(hex(0x2B1961), hex(0xD9CCFF))
    private static let plain_functionText: UIColor = dyn(hex(0x111114), hex(0xFFFFFF))
    static var keyShadow: UIColor { plain ? plain_keyShadow : mosto_keyShadow }
    /// `a` moved `k` of the way towards `b` (opaque colours).
    private static let mosto_keyShadow: UIColor = dyn(hex(0x2B1961, 0.14), UIColor(white: 0, alpha: 0.32))
    private static let plain_keyShadow: UIColor = dyn(UIColor(white: 0, alpha: 0.10), UIColor(white: 0, alpha: 0.35))
    static func mix(_ a: UIColor, _ b: UIColor, _ k: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k, alpha: a1 + (a2 - a1) * k)
    }
    static var candidateText: UIColor { keyText }
    static var secondaryText: UIColor { plain ? plain_secondaryText : mosto_secondaryText }
    /// 键位提示 finals on the letter caps: ≥ 4.5:1 on the cream face by day and the violet face at night
    private static let mosto_secondaryText: UIColor = dyn(hex(0x6A5C96), hex(0xB4A8DC))
    private static let plain_secondaryText: UIColor = dyn(hex(0x6C6C72), hex(0xA1A1A8))
    static var guideText: UIColor { plain ? plain_guideText : mosto_guideText }
    /// The correction mark, selected alternates: Mosto's violet by day, his gold at night.
    private static let mosto_guideText: UIColor = dyn(hex(0x5B4D8C), hex(0xDCD5F7))
    private static let plain_guideText: UIColor = dyn(hex(0x55555C), hex(0xD1D1D6))
    static var correctedMark: UIColor { plain ? plain_correctedMark : mosto_correctedMark }
    /// Behind the corrected first choice and the undo chip: a soft tint of the correction colour.
    private static let mosto_correctedMark: UIColor = dyn(hex(0x633EBF), hex(0xFFC45A))
    private static let plain_correctedMark: UIColor = dyn(hex(0x0A6CE0), hex(0x5EB0FF))
    static var correctedTint: UIColor { plain ? plain_correctedTint : mosto_correctedTint }
    private static let mosto_correctedTint: UIColor = dyn(hex(0x633EBF, 0.10), hex(0xFFC45A, 0.15))
    private static let plain_correctedTint: UIColor = dyn(hex(0x0A7CFF, 0.10), hex(0x0A84FF, 0.22))
    static var selection: UIColor { plain ? plain_selection : mosto_selection }
    private static let mosto_selection: UIColor = dyn(hex(0x633EBF), hex(0xE3B04F))
    private static let plain_selection: UIColor = dyn(hex(0x0A7CFF), hex(0x0A84FF))
    static var selectionText: UIColor { plain ? plain_selectionText : mosto_selectionText }
    private static let mosto_selectionText: UIColor = dyn(.white, hex(0x2B1961))
    private static let plain_selectionText: UIColor = UIColor.white
}
