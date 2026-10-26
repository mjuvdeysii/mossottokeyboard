import Foundation

// Engine test harness (runs on macOS or Linux, no UIKit).
//   EngineCLI <lexicon.bin> type <letters>        show candidates for exact keys
//   EngineCLI <lexicon.bin> bench [sigma ...]     simulated-touch accuracy benchmark
//   EngineCLI <lexicon.bin> codes                 dump syllable -> code table

struct RNG {
    var s: UInt64
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double(s >> 11) / Double(1 << 53)
    }
    mutating func gauss() -> Double {
        let u = max(next(), 1e-12), v = next()
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: EngineCLI <lexicon.bin> type|bench|codes ..."); exit(1) }
let lex = try Lexicon(path: args[1])
let decoder = Decoder(lexicon: lex)
let model = SpatialModel.standard()
let env = ProcessInfo.processInfo.environment
if let v = env["PEN"].flatMap(Double.init) { decoder.correctionPenalty = v }
if let v = env["SIG"].flatMap(Double.init) { model.sigmaX = v; model.sigmaY = v * 0.9 }
if let v = env["WP"].flatMap(Double.init) { decoder.wordPenalty = v }

func codeLetters(_ ids: [UInt16]) -> String {
    ids.map { XiaoheScheme.code(for: lex.syllables[Int($0)])! }.joined()
}

func noisyTaps(_ letters: String, sigmaX: Double, sigmaY: Double, rng: inout RNG) -> [Tap] {
    letters.map { c in
        let (cx, cy) = model.center(of: c)!
        let x = cx + rng.gauss() * sigmaX * model.keyWidth
        let y = cy + rng.gauss() * sigmaY * model.keyHeight
        return model.tap(x: x, y: y)
    }
}

switch args[2] {
case "codes":
    for s in lex.syllables { print(s, XiaoheScheme.code(for: s) ?? "-") }

case "type":
    let letters = args.count > 3 ? args[3] : ""
    let t0 = Date()
    let r = decoder.decode(letters.map { Tap.exact($0) })
    let ms = Date().timeIntervalSince(t0) * 1000
    print("preedit: \(r.preedit)   (\(String(format: "%.1f", ms)) ms)")
    for c in r.candidates.prefix(15) {
        print(String(format: "%6.2f", c.score), c.text, "taps=\(c.tapCount)", c.corrected ? "[corrected]" : "")
    }

case "bench":
    // Test items: common 2–4 syllable words sampled from the lexicon + everyday sentences.
    var items: [(String, [UInt16])] = []
    var rng = RNG(s: 42)
    var pool: [(String, [UInt16])] = []
    for s in 0..<lex.syllables.count {
        for i in lex.range(firstSyllable: UInt16(s)) {
            let e = lex.entry(i)
            if (2...4).contains(e.sylCount) && e.score >= 900 { pool.append((lex.text(e), lex.syllableIDs(e))) }
        }
    }
    for _ in 0..<1500 { items.append(pool[Int(rng.next() * Double(pool.count))]) }
    let sentences = [
        ("我们明天去公园", "wo men ming tian qu gong yuan"),
        ("今天天气很好", "jin tian tian qi hen hao"),
        ("你吃饭了吗", "ni chi fan le ma"),
        ("这个问题怎么解决", "zhe ge wen ti zen me jie jue"),
        ("请把文件发给我", "qing ba wen jian fa gei wo"),
        ("我马上就到", "wo ma shang jiu dao"),
        ("谢谢你的帮助", "xie xie ni de bang zhu"),
        ("会议改到下午三点", "hui yi gai dao xia wu san dian"),
        ("这个价格有点贵", "zhe ge jia ge you dian gui"),
        ("我们需要重新设计", "wo men xu yao chong xin she ji"),
        ("客户已经收到退款", "ke hu yi jing shou dao tui kuan"),
        ("请尽快回复邮件", "qing jin kuai hui fu you jian"),
        ("周末一起去吃火锅", "zhou mo yi qi qu chi huo guo"),
        ("这款产品卖得很好", "zhe kuan chan pin mai de hen hao"),
        ("数据分析结果出来了", "shu ju fen xi jie guo chu lai le"),
        ("我觉得没问题", "wo jue de mei wen ti"),
        ("你现在在哪里", "ni xian zai zai na li"),
        ("晚上早点休息", "wan shang zao dian xiu xi"),
        ("输入法自动纠错", "shu ru fa zi dong jiu cuo"),
        ("小鹤双拼很好用", "xiao he shuang pin hen hao yong"),
        ("下周开始上线", "xia zhou kai shi shang xian"),
        ("图片已经更新了", "tu pian yi jing geng xin le"),
        ("麻烦帮我确认一下", "ma fan bang wo que ren yi xia"),
        ("物流信息显示已签收", "wu liu xin xi xian shi yi qian shou"),
        ("我们正在处理这个问题", "wo men zheng zai chu li zhe ge wen ti"),
    ]
    var sentItems: [(String, [UInt16])] = []
    for (t, py) in sentences {
        let ids = py.split(separator: " ").map { lex.id(of: String($0))! }
        sentItems.append((t, ids))
    }

    let sigmas: [Double] = args.count > 3 ? args[3...].compactMap(Double.init) : [0.20, 0.30, 0.40]
    for (name, set) in [("words", items), ("sentences", sentItems)] {
        // Reference: what perfect keystrokes give.
        decoder.correctionEnabled = false
        var refs: [String] = []
        var refIsTarget = 0
        let t0 = Date()
        for (t, ids) in set {
            let r = decoder.decode(codeLetters(ids).map { Tap.exact($0) })
            refs.append(r.candidates.first?.text ?? "")
            if refs.last == t { refIsTarget += 1 }
        }
        let avgMs = Date().timeIntervalSince(t0) * 1000 / Double(set.count)
        print("\n== \(name): n=\(set.count)  perfect-keys top1 == intended text: \(refIsTarget)  avg decode \(String(format: "%.2f", avgMs)) ms")
        for sg in sigmas {
            var rng2 = RNG(s: 7)
            var tapErr = 0, tapTotal = 0
            var offOK = 0, onOK = 0, onTop3 = 0, harmed = 0, cleanItems = 0, fixed = 0, noisyItems = 0
            for (k, (_, ids)) in set.enumerated() {
                let letters = codeLetters(ids)
                let taps = noisyTaps(letters, sigmaX: sg, sigmaY: sg * 0.9, rng: &rng2)
                let wrong = zip(taps, letters).filter { $0.0.key != $0.1 }.count
                tapErr += wrong; tapTotal += letters.count
                decoder.correctionEnabled = false
                let off = decoder.decode(taps).candidates.first?.text ?? ""
                decoder.correctionEnabled = true
                let onR = decoder.decode(taps).candidates
                let on = onR.first?.text ?? ""
                if off == refs[k] { offOK += 1 }
                if on == refs[k] { onOK += 1 }
                if onR.prefix(3).contains(where: { $0.text == refs[k] }) { onTop3 += 1 }
                if wrong == 0 { cleanItems += 1; if on != refs[k] { harmed += 1 } }
                else { noisyItems += 1; if on == refs[k] { fixed += 1 } }
            }
            let n = Double(set.count)
            print(String(format: "touch σ=%.2f key | key error rate %.1f%% | top1 correction OFF %.1f%%  ON %.1f%% | ON top3 %.1f%% | items with mistyped keys recovered %d/%d | clean items broken by correction %d/%d",
                         sg, 100 * Double(tapErr) / Double(tapTotal), 100 * Double(offOK) / n, 100 * Double(onOK) / n,
                         100 * Double(onTop3) / n, fixed, noisyItems, harmed, cleanItems))
        }
    }

default:
    print("unknown command")
}
