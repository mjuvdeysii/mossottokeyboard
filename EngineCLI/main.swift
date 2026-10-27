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
// 中英混输: english.txt next to the lexicon (ENGLISH=0 turns it off)
let englishPath = (args[1] as NSString).deletingLastPathComponent + "/english.txt"
if ProcessInfo.processInfo.environment["ENGLISH"] != "0", let en = try? EnglishLexicon(path: englishPath) { decoder.english = en }
if let v = ProcessInfo.processInfo.environment["ENP"], let d = Double(v) { decoder.englishPenalty = d }
let model = SpatialModel.standard()
let env = ProcessInfo.processInfo.environment
if let v = env["PEN"].flatMap(Double.init) { decoder.correctionPenalty = v }
if let v = env["SIG"].flatMap(Double.init) { model.sigmaX = v; model.sigmaY = v * 0.9 }
if let v = env["WP"].flatMap(Double.init) { decoder.wordPenalty = v }
if env["SCHEME"] == "quanpin" { decoder.scheme = .quanpin }
if let v = env["ABBR"].flatMap(Double.init) { decoder.abbreviationPenalty = v }


func codeLetters(_ ids: [UInt16]) -> String {
    ids.map { decoder.spelling(of: $0) }.joined()
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
case "predict":
    let pr = try Predictor(path: args[1].replacingOccurrences(of: "lexicon.bin", with: "predictions.bin"))
    for w in args[3...] { print(w, "→", pr.predict(after: w)) }

case "codes":
    for s in lex.syllables { print(s, XiaoheScheme.code(for: s) ?? "-") }

case "type":
    let letters = args.count > 3 ? args[3] : ""
    let t0 = Date()
    let t9 = ProcessInfo.processInfo.environment["T9"] == "1"   // keys are 九宫格 digits (2–9, ' for 分词)
    let r = decoder.decode(letters.map { t9 ? Tap.t9($0) : Tap.exact($0) })
    let ms = Date().timeIntervalSince(t0) * 1000
    print("preedit: \(r.preedit)   (\(String(format: "%.1f", ms)) ms)")
    for c in r.candidates.prefix(15) {
        print(String(format: "%6.2f", c.score), c.text, "taps=\(c.tapCount)", c.corrected ? "[corrected]" : "")
    }

case "bench", "gate":
    var metrics: [String: Double] = [:]
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
    // Everyday sentences with pinyin (EngineCLI/sentences.tsv, generated with pypinyin and spot-checked).
    let tsv = (try? String(contentsOfFile: env["SENTENCES"] ?? "EngineCLI/sentences.tsv", encoding: .utf8)) ?? ""
    let sentences: [(String, String)] = tsv.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "\t")
        return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
    }
    var sentItems: [(String, [UInt16])] = []
    for (t, py) in sentences {
        let ids = py.split(separator: " ").map { lex.id(of: String($0))! }
        sentItems.append((t, ids))
    }

    let sigmas: [Double] = args[2] == "gate" ? [0.22] : (args.count > 3 ? args[3...].compactMap(Double.init) : [0.20, 0.30, 0.40])
    for (name, set) in [("words", items), ("sentences", sentItems)] {
        // Reference: what perfect keystrokes give.
        decoder.correctionEnabled = false
        var refs: [String] = []
        var refIsTarget = 0
        for (t, ids) in set {   // also the warm-up: pages the lexicon in and builds the lazy indexes
            let r = decoder.decode(codeLetters(ids).map { Tap.exact($0) })
            refs.append(r.candidates.first?.text ?? "")
            if refs.last == t { refIsTarget += 1 }
        }
        // Timing: the best of three warm passes, so a busy shared CI runner does not fail the gate on noise.
        let taps = set.map { codeLetters($0.1).map { Tap.exact($0) } }
        var avgMs = Double.infinity
        for _ in 0..<3 {
            let t0 = Date()
            for tp in taps { _ = decoder.decode(tp) }
            avgMs = min(avgMs, Date().timeIntervalSince(t0) * 1000 / Double(set.count))
        }
        print("\n== \(name): n=\(set.count)  perfect-keys top1 == intended text: \(refIsTarget)  avg decode \(String(format: "%.2f", avgMs)) ms")
        metrics["\(name).perfect"] = 100 * Double(refIsTarget) / Double(set.count)
        metrics["\(name).ms"] = avgMs
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
            if abs(sg - 0.22) < 1e-9 {
                metrics["\(name).on"] = 100 * Double(onOK) / n
                metrics["\(name).broken"] = 100 * Double(harmed) / Double(max(cleanItems, 1))
            }
            print(String(format: "touch σ=%.2f key | key error rate %.1f%% | top1 correction OFF %.1f%%  ON %.1f%% | ON top3 %.1f%% | items with mistyped keys recovered %d/%d | clean items broken by correction %d/%d",
                         sg, 100 * Double(tapErr) / Double(tapTotal), 100 * Double(offOK) / n, 100 * Double(onOK) / n,
                         100 * Double(onTop3) / n, fixed, noisyItems, harmed, cleanItems))
        }
    }

    // 九宫格: the same items typed on the number keys (each key stands for its 3–4 letters), perfect keys
    if ProcessInfo.processInfo.environment["T9"] != "0" {
        for (name, set) in [("words", items), ("sentences", sentItems)] {
            var top1 = 0, top3 = 0
            let t0 = Date()
            for (t, ids) in set {
                let taps = codeLetters(ids).map { Tap.t9(Tap.t9Digit($0)) }
                let c = decoder.decode(taps).candidates
                if c.first?.text == t { top1 += 1 }
                if c.prefix(3).contains(where: { $0.text == t }) { top3 += 1 }
            }
            let ms = Date().timeIntervalSince(t0) * 1000 / Double(set.count)
            metrics["t9.\(name).top1"] = 100 * Double(top1) / Double(set.count)
            metrics["t9.\(name).top3"] = 100 * Double(top3) / Double(set.count)
            metrics["t9.\(name).ms"] = ms
            print(String(format: "== 九宫格 %@: top1 %.1f%%  top3 %.1f%%  %.2f ms", name, metrics["t9.\(name).top1"]!, metrics["t9.\(name).top3"]!, ms))
        }
    }

    if args[2] == "gate" {
        // Regression gate for CI: the release does not go out if typing quality drops below these floors.
        // 小鹤双拼 and 全拼 each have their own floors (set a little under the measured values)
        let floors: [(String, Double, Bool)] = decoder.scheme == .xiaohe ? [
            ("words.on", 96.0, true),          // σ=0.22 touch noise, correction on, top-1 (%)
            ("words.broken", 1.0, false),      // clean words changed by correction (%) — at most
            ("sentences.perfect", 72.0, true), // perfect keys, top-1 equals the intended sentence (%)
            ("sentences.on", 86.0, true),
            ("words.ms", 3.0, false),          // average decode time (ms) — at most
            ("t9.words.top1", 48.0, true),     // 九宫格 (each key = its 3–4 letters), perfect keys
            ("t9.sentences.top3", 33.0, true),
            ("t9.sentences.ms", 40.0, false),
        ] : [
            ("words.on", 97.0, true),
            ("words.broken", 1.0, false),
            ("sentences.perfect", 72.0, true),
            ("sentences.on", 90.0, true),
            ("sentences.ms", 8.0, false),
            ("t9.words.top1", 65.0, true),
            ("t9.sentences.top1", 50.0, true),
            ("t9.sentences.ms", 250.0, false),
        ]
        print("scheme:", decoder.scheme == .xiaohe ? "小鹤双拼" : "全拼")
        var failed = false
        // 中英混输: English words people type in Chinese chat lead; Chinese syllables keep their Chinese first.
        if decoder.english != nil {
            decoder.correctionEnabled = true
            let mixed: [(String, String)] = [("ok", "OK"), ("ios", "iOS"), ("iphone", "iPhone"), ("github", "GitHub"),
                                             ("wifi", "Wi-Fi"), ("hello", "hello"),
                                             ("de", "的"), ("he", "和"), ("wo", "我"), ("me", "么")]
            var bad: [String] = []
            for (k, want) in mixed {
                let top = decoder.decode(k.map { Tap.exact($0) }).candidates.first?.text ?? ""
                // English wants must match exactly; for a Chinese want any Chinese reading first is fine (么/没)
                let chineseWanted = want.unicodeScalars.contains { $0.value > 0x2E80 }
                let good = chineseWanted ? top.unicodeScalars.contains { $0.value > 0x2E80 } : top == want
                if !good { bad.append("\(k)→\(top)") }
            }
            let ok = bad.isEmpty
            print(ok ? "PASS mixed.top1 \(mixed.count)/\(mixed.count)" : "FAIL mixed.top1 " + bad.joined(separator: " "))
            if !ok { failed = true }
        }
        for (k, v, atLeast) in floors {
            let m = metrics[k] ?? .nan
            let ok = atLeast ? m >= v : m <= v
            print(String(format: "%@ %@ %.2f (%@ %.2f)", ok ? "PASS" : "FAIL", k, m, atLeast ? "≥" : "≤", v))
            if !ok { failed = true }
        }
        if failed { exit(1) }
    }

default:
    print("unknown command")
}
