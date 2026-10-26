import UIKit

enum KeyboardPage { case letters, numbers, symbols }

enum KeyAction: Equatable {
    case char(String)
    case shift
    case delete
    case space
    case ret
    case globe
    case page(KeyboardPage)
    case toggleLanguage
}

enum KeyStyle { case normal, function, accent }

struct KeySpec {
    var action: KeyAction
    var label: String
    var symbol: String? = nil        // SF Symbol name
    var width: CGFloat = 1           // in letter-key units; 0 = flexible
    var alt: String? = nil           // long-press alternate
    var style: KeyStyle = .normal
    var isLetter: Bool = false
}

struct LayoutContext {
    var page: KeyboardPage
    var chinese: Bool
    var showGlobe: Bool
    var returnLabel: String
    var returnIsAccent: Bool
    var shifted: Bool
    var capsLock: Bool
}

/// All pages fit on screen: 10 keys max per row, nothing hidden, no scrolling.
enum Layouts {
    static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    static let topRowDigits = Array("1234567890").map(String.init)
    static let longPressAlt: [Character: String] = [
        "a": "@", "s": "*", "d": "+", "f": "-", "g": "=", "h": "/", "j": "#", "k": "(", "l": ")",
        "z": "_", "x": "$", "c": "\"", "v": "'", "b": ":", "n": ";", "m": "!",
    ]

    static func rows(_ ctx: LayoutContext) -> [[KeySpec]] {
        switch ctx.page {
        case .letters: return letters(ctx)
        case .numbers: return numbers(ctx)
        case .symbols: return symbols(ctx)
        }
    }

    private static func letters(_ ctx: LayoutContext) -> [[KeySpec]] {
        var rows: [[KeySpec]] = []
        for (r, row) in letterRows.enumerated() {
            var specs: [KeySpec] = []
            for (i, c) in row.enumerated() {
                let upper = ctx.shifted || ctx.capsLock
                let label = upper ? String(c).uppercased() : String(c)
                let alt = r == 0 ? topRowDigits[i] : longPressAlt[c]
                specs.append(KeySpec(action: .char(String(c)), label: label, alt: alt, isLetter: true))
            }
            if r == 2 {
                let shiftSymbol = ctx.capsLock ? "capslock.fill" : (ctx.shifted ? "shift.fill" : "shift")
                specs.insert(KeySpec(action: .shift, label: "", symbol: shiftSymbol, width: 1.5, style: .function), at: 0)
                specs.append(KeySpec(action: .delete, label: "", symbol: "delete.left", width: 1.5, style: .function))
            }
            rows.append(specs)
        }
        var bottom: [KeySpec] = [KeySpec(action: .page(.numbers), label: "123", width: 1.25, style: .function)]
        if ctx.showGlobe { bottom.append(KeySpec(action: .globe, label: "", symbol: "globe", width: 1, style: .function)) }
        if ctx.chinese {
            bottom.append(KeySpec(action: .char("，"), label: "，", width: 1, alt: "？", style: .function))
            bottom.append(KeySpec(action: .space, label: "小鹤双拼", width: 0))
            bottom.append(KeySpec(action: .char("。"), label: "。", width: 1, alt: "！", style: .function))
        } else {
            bottom.append(KeySpec(action: .char(","), label: ",", width: 1, alt: "?", style: .function))
            bottom.append(KeySpec(action: .space, label: "space", width: 0))
            bottom.append(KeySpec(action: .char("."), label: ".", width: 1, alt: "!", style: .function))
        }
        bottom.append(KeySpec(action: .toggleLanguage, label: ctx.chinese ? "中" : "英", width: 1, style: .function))
        bottom.append(KeySpec(action: .ret, label: ctx.returnLabel, width: 1.75, style: ctx.returnIsAccent ? .accent : .function))
        rows.append(bottom)
        return rows
    }

    private static func charRow(_ s: [String]) -> [KeySpec] {
        s.map { KeySpec(action: .char($0), label: $0) }
    }

    private static func bottomRow(_ ctx: LayoutContext) -> [KeySpec] {
        var bottom: [KeySpec] = [KeySpec(action: .page(.letters), label: ctx.chinese ? "拼音" : "ABC", width: 1.25, style: .function)]
        if ctx.showGlobe { bottom.append(KeySpec(action: .globe, label: "", symbol: "globe", width: 1, style: .function)) }
        bottom.append(KeySpec(action: .space, label: ctx.chinese ? "空格" : "space", width: 0))
        bottom.append(KeySpec(action: .ret, label: ctx.returnLabel, width: 1.75, style: ctx.returnIsAccent ? .accent : .function))
        return bottom
    }

    private static func numbers(_ ctx: LayoutContext) -> [[KeySpec]] {
        let row1 = charRow(topRowDigits)
        let row2 = ctx.chinese
            ? charRow(["-", "/", "：", "；", "（", "）", "¥", "@", "“", "”"])
            : charRow(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
        var row3: [KeySpec] = [KeySpec(action: .page(.symbols), label: "#+=", width: 1.5, style: .function)]
        row3 += ctx.chinese
            ? charRow(["。", "，", "、", "？", "！", "…", "."])
            : charRow([".", ",", "?", "!", "'", "%", "*"])
        row3.append(KeySpec(action: .delete, label: "", symbol: "delete.left", width: 1.5, style: .function))
        return [row1, row2, row3, bottomRow(ctx)]
    }

    private static func symbols(_ ctx: LayoutContext) -> [[KeySpec]] {
        let row1 = ctx.chinese
            ? charRow(["【", "】", "{", "}", "#", "%", "^", "*", "+", "="])
            : charRow(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
        let row2 = ctx.chinese
            ? charRow(["_", "—", "\\", "|", "～", "《", "》", "&", "·", "€"])
            : charRow(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"])
        var row3: [KeySpec] = [KeySpec(action: .page(.numbers), label: "123", width: 1.5, style: .function)]
        row3 += ctx.chinese
            ? charRow(["「", "」", "‘", "’", "〈", "〉", "°"])
            : charRow([".", ",", "?", "!", "'", "`", "°"])
        row3.append(KeySpec(action: .delete, label: "", symbol: "delete.left", width: 1.5, style: .function))
        return [row1, row2, row3, bottomRow(ctx)]
    }
}

enum Theme {
    static func dyn(_ light: UIColor, _ dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
    static let background = dyn(UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1), UIColor(white: 0.17, alpha: 1))
    static let key = dyn(.white, UIColor(white: 0.42, alpha: 1))
    static let keyPressed = dyn(UIColor(white: 0.86, alpha: 1), UIColor(white: 0.30, alpha: 1))
    static let functionKey = dyn(UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1), UIColor(white: 0.27, alpha: 1))
    static let accentKey = UIColor.systemBlue
    static let keyText = dyn(.black, .white)
    static let keyShadow = dyn(UIColor(white: 0, alpha: 0.35), UIColor(white: 0, alpha: 0.6))
    static let candidateText = dyn(.black, .white)
    static let secondaryText = dyn(UIColor(white: 0.35, alpha: 1), UIColor(white: 0.7, alpha: 1))
    static let correctedMark = UIColor.systemBlue
}
