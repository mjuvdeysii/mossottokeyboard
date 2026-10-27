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
    var moreAlts: [String] = []      // further long-press choices after `alt`, shown as a row
}

struct LayoutContext {
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
    /// iOS 26 caps are rounder than Gboard's space bar (6 pt); 8.5 pt is an estimate pending a native screenshot.
    static let cornerRadius: CGFloat = 8.5
    static let letterFont: CGFloat = 23
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

    /// Second and third keys of every bottom row: settings (or the system globe when the
    /// device needs it) and the 中/英 switch, in Gboard's settings / emoji positions.
    private static func middleKeys(_ ctx: LayoutContext) -> [KeySpec] {
        let first = ctx.showGlobe
            ? KeySpec(action: .globe, label: "", symbol: "globe", width: 1, style: .function)
            : KeySpec(action: .settings, label: "", symbol: "gearshape", width: 1, style: .function)
        return [first, KeySpec(action: .toggleLanguage, label: ctx.chinese ? "中" : "英", width: 1, style: .function)]
    }

    /// As on the system keyboard: 换行 / return, the host's action (搜索, 发送…) in blue, 确认 while composing.
    private static func returnKey(_ ctx: LayoutContext, width: CGFloat, wide: Bool) -> KeySpec {
        if let l = ctx.returnLabel {
            return KeySpec(action: .ret, label: l, width: width, style: ctx.returnIsAccent ? .accent : .function)
        }
        return KeySpec(action: .ret, label: ctx.chinese ? "换行" : "return", width: width, style: .function)
    }

    private static func letters(_ ctx: LayoutContext) -> [[KeySpec]] {
        var rows: [[KeySpec]] = []
        for (r, row) in letterRows.enumerated() {
            var specs: [KeySpec] = []
            for c in row {
                let upper = ctx.shifted || ctx.capsLock
                let label = upper ? String(c).uppercased() : String(c)
                // letters are plain: no corner digits, no long-press symbols (digits and symbols live on 123 / #+=)
                specs.append(KeySpec(action: .char(String(c)), label: label, isLetter: true))
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
        bottom.append(returnKey(ctx, width: 2, wide: false))
        rows.append(bottom)
        return rows
    }

    private static func charRow(_ s: [String], width: CGFloat = 1, alts: [String: String] = [:]) -> [KeySpec] {
        s.map { KeySpec(action: .char($0), label: $0, width: width, alt: alts[$0]) }
    }

    private static func bottomRow(_ ctx: LayoutContext) -> [KeySpec] {
        var bottom: [KeySpec] = [KeySpec(action: .page(.letters), label: ctx.chinese ? "中文" : "ABC", width: 1.25, style: .function)]
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
        let gear = ctx.showGlobe
            ? KeySpec(action: .globe, label: "", symbol: "globe", width: 1, style: .function)
            : KeySpec(action: .settings, label: "", symbol: "gearshape", width: 1, style: .function)
        let row4 = [KeySpec(action: .page(ctx.numberGrid ? .numpad : .numbers), label: "123", width: side, style: .function),
                    gear,
                    KeySpec(action: .page(.symbols), label: "符号", width: mid - 1 + 0.27, style: .function),
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
        var row4: [KeySpec] = ctx.showGlobe
            ? [KeySpec(action: .page(.letters), label: ctx.chinese ? "返回" : "ABC", width: 1, style: .function),
               KeySpec(action: .globe, label: "", symbol: "globe", width: 1, style: .function)]
            : [KeySpec(action: .page(.letters), label: ctx.chinese ? "返回" : "ABC", width: side, style: .function)]
        row4 += [p(".", ","), d("0"), p(":", "%"),
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

/// Two lights, as in Moss & Otto: 日光 (day) and 夜灯 (night lamp). They map onto the light / dark trait, so every
/// colour below resolves by itself; the keyboard forces the trait when the user picks 日光 or 夜灯.
/// The keyboard's own background is clear: on iOS 26 the system puts third-party keyboards on its Liquid Glass
/// (an opaque background shows up as a grey band), so the light only tints that glass.
enum Theme {
    static func dyn(_ day: UIColor, _ night: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? night : day }
    }
    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }
    /// Tint laid over the system glass: none by day (the system keyboard's own glass), the deep lamp-lit blue at night.
    static let glassTint = dyn(.clear, hex(0x1B2245, 0.62))
    /// Night forced while the system is light: the glass underneath is pale, so the tint must carry the night alone.
    static let forcedNightTint = hex(0x1B2245, 0.92)
    /// Opaque panels over the keys (candidate grid, settings).
    static let panel = dyn(hex(0xF2F2F7), hex(0x1B2245))   // opaque: keys must not show through a panel
    /// Settings, as iOS Settings draws them: grouped background, rounded white groups, hairline separators.
    static let settingsGroup = dyn(UIColor(white: 1, alpha: 0.85), UIColor(white: 1, alpha: 0.10))
    static let separator = dyn(UIColor(white: 0, alpha: 0.12), UIColor(white: 1, alpha: 0.12))
    // iOS 26 key caps: translucent, no hard shadow
    static let key = dyn(UIColor(white: 1, alpha: 0.93), UIColor(white: 1, alpha: 0.17))
    static let keyPressed = dyn(UIColor(white: 0.80, alpha: 0.95), UIColor(white: 1, alpha: 0.32))
    static let functionKey = dyn(UIColor(white: 0, alpha: 0.11), UIColor(white: 1, alpha: 0.09))
    static let keyHighlight = dyn(UIColor(white: 1, alpha: 0.75), UIColor(white: 1, alpha: 0.18))
    static let bubble = dyn(.white, hex(0x2C3766))
    /// The system keyboard's action blue (return key with 搜索 / 发送…, selected alternates, the correction mark).
    static let accentKey = UIColor.systemBlue
    static let accentText = UIColor.white
    static let keyText = dyn(hex(0x1C1D19), hex(0xF4EBDD))
    static let keyShadow = dyn(UIColor(white: 0, alpha: 0.16), UIColor(white: 0, alpha: 0))
    static let candidateText = keyText
    static let secondaryText = dyn(hex(0x5E5F66), hex(0xAEB4CC))
    static let correctedMark = accentKey
}
