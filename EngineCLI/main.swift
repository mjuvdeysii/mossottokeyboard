import Foundation

// Engine test harness (runs on macOS or Linux, no UIKit).
//   EngineCLI <lexicon.bin> type <letters>        show candidates for exact keys
//   EngineCLI <lexicon.bin> bench [sigma ...]     simulated-touch accuracy benchmark
//   EngineCLI <lexicon.bin> codes                 dump syllable -> code table
//   EngineCLI <lexicon.bin> slips <words|sentences|holdout> <quarter|edge|centre>   one key on a neighbour (R4), root causes
//   EngineCLI <lexicon.bin> rare                  uncommon words typed on purpose kept first (rare.kept)

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
// 中英混输: english.bin next to the lexicon (ENGLISH=0 turns it off)
let englishPath = (args[1] as NSString).deletingLastPathComponent + "/english.bin"
if ProcessInfo.processInfo.environment["ENGLISH"] != "0", let en = try? EnglishLexicon(path: englishPath) { decoder.english = en }
if let v = ProcessInfo.processInfo.environment["ENP"], let d = Double(v) { decoder.englishPenalty = d }
let model = SpatialModel.standard()
let env = ProcessInfo.processInfo.environment
if let v = env["PEN"].flatMap(Double.init) { decoder.correctionPenalty = v }
if let v = env["SIG"].flatMap(Double.init) { model.sigmaX = v; model.sigmaY = v * 0.9 }
if let v = env["WP"].flatMap(Double.init) { decoder.wordPenalty = v }
if env["SCHEME"] == "quanpin" { decoder.scheme = .quanpin }
if let v = env["ABBR"].flatMap(Double.init) { decoder.abbreviationPenalty = v }
if let v = env["T9ABBR"].flatMap(Double.init) { decoder.t9AbbreviationExtra = v }
if let v = env["BEAM"].flatMap(Int.init) { decoder.beam = v }
if let v = env["UGD"].flatMap(Double.init) { decoder.unigramDiscount = v }
if let v = env["UGC"].flatMap(Double.init) { decoder.unigramCenter = v }
if let v = env["CP"].flatMap(Double.init) { decoder.fullCompletionPenalty = v }
if env["MIX"] == "0" { decoder.mixedEnglish = false }
if let v = env["MIXP"].flatMap(Double.init) { decoder.mixedPenalty = v }
if let v = env["MIXC"].flatMap(Double.init) { decoder.mixedCasedBonus = v }
if let v = env["MIXR"].flatMap(Double.init) { decoder.mixedRarePenalty = v }
if let v = env["MIXY"].flatMap(Double.init) { decoder.mixedPinyinPenalty = v }
if let v = env["MIXZ"].flatMap(Double.init) { decoder.mixedMinZipf = v }
if let v = env["MISSP"].flatMap(Double.init) { decoder.missingPenalty = v }
if let v = env["MIXF"].flatMap(Double.init) { decoder.mixedForeignBonus = v }
if let v = env["ABM"].flatMap(Double.init) { decoder.midAbbreviationPenalty = v }
if let v = env["MIXS"].flatMap(Double.init) { decoder.mixedSlipPenalty = v }
if let v = env["AOP"].flatMap(Double.init) { decoder.abbreviationOverlapPenalty = v }
if let v = env["CORR"].flatMap(Double.init) { decoder.correctionPenalty = v }
if let v = env["SPW"].flatMap(Double.init) { decoder.spatialWeight = v }
if let v = env["SKM"].flatMap(Double.init) { decoder.slipMargin = v }
if env["SKIP"] == "0" { decoder.skipEnabled = false }
if let v = env["SKIPP"].flatMap(Double.init) { decoder.skipPenalty = v; decoder.xiaoheSkipPenalty = v }
if let v = env["SKIPD"].flatMap(Double.init) { decoder.skipDoublePenalty = v; decoder.xiaoheSkipDoublePenalty = v }
if let v = env["XSKIPP"].flatMap(Double.init) { decoder.xiaoheSkipPenalty = v }
if let v = env["T9PFX"].flatMap(Double.init) { decoder.t9PrefixExtra = v }
if let v = env["T9MIN"].flatMap(Double.init) { decoder.t9MinWordScore = v }
if let v = env["UW"].flatMap(Double.init) { decoder.userWeight = v }
// language model: grammar.gram next to the lexicon (GRAMMAR=path overrides, GRAMMAR=0 turns it off; GW weight)
if env["GRAMMAR"] != "0" {
    let gp = env["GRAMMAR"] ?? (args[1] as NSString).deletingLastPathComponent + "/grammar.gram"
    decoder.grammar = try? Grammar(path: gp)
    // the sentence model (万象) beside it reads the keys; grammar.gram then serves 联想 (SENTENCE=0 turns it off)
    let sp = env["SENTENCE"] ?? (args[1] as NSString).deletingLastPathComponent + "/sentence.gram"
    if sp != "0", let sentence = try? Grammar(path: sp) {
        decoder.predictionGrammar = decoder.grammar
        decoder.grammar = sentence
        print("sentence model:", sp)
    }
}
if let v = env["GW"].flatMap(Double.init) { decoder.grammarWeight = v }
if let v = env["MASSB"].flatMap(Int.init) { decoder.grammar?.massBudget = v }
if let v = env["MW"].flatMap(Double.init) { decoder.contextNormalisation = v }
if let v = env["MB"].flatMap(Int.init) { decoder.grammar?.massBudget = v }
if let v = env["MC"].flatMap(Double.init) { decoder.grammar?.massCenter = v }
if let v = env["GCF"].flatMap(Double.init) { decoder.grammarCorrectedFactor = v }
if let v = env["UC"].flatMap(Double.init) { decoder.userCap = v }
if let v = env["UP"].flatMap(Double.init) { decoder.userPhraseScore = v }
if let v = env["UB"].flatMap(Double.init) { decoder.userWordBoost = v }
if env["TAIL"] == "0" { decoder.tailSlipEnabled = false }
if let v = env["TSE"].flatMap(Double.init) { decoder.tailSlipExtra = v }
if env["DEDUPE"] == "0" { decoder.dedupeLastCharacter = false }
if let v = env["DDK"].flatMap(Int.init) { decoder.dedupeKeep = v }
// R4: the touch model's floor, corrected syllables in a class of their own, the corrected reading second
if let v = env["MINP"].flatMap(Double.init) { model.minProbability = v }
if let v = env["PM"].flatMap(Double.init) { decoder.pruneMargin = v }
if env["SPLIT"] == "0" { decoder.correctionClasses = false }
if let v = env["CMARGIN"].flatMap(Double.init) { decoder.correctionMargin = v }
if let v = env["CKEEP"].flatMap(Int.init) { decoder.correctionKeep = v }
if let v = env["CALT"].flatMap(Int.init) { decoder.correctionAlternatives = v }
if let v = env["AMARGIN"].flatMap(Double.init) { decoder.alternateMargin = v }


func codeLetters(_ ids: [UInt16]) -> String {
    ids.map { decoder.spelling(of: $0) }.joined()
}

/// A tap in the middle of key `c`, as a finger landing on the key's centre gives on the phone (the touch model's
/// neighbours included) — not `Tap.exact`, which carries the key alone.
func centreTap(_ c: Character) -> Tap {
    guard let (cx, cy) = model.center(of: c) else { return Tap.exact(c) }
    return model.tap(x: cx, y: cy, hitKey: c)
}

/// R1 现场错例 (EngineCLI/r1_typos.tsv): every key a tap on the centre of its key (r1.top1 / r1.top3), and the old
/// `Tap.exact` reading beside it for one round (r1.exact.*). The scheme is put back as it was.
func r1Typos(_ path: String, debug: Bool) -> (top1: Int, top3: Int, exact1: Int, exact3: Int, total: Int) {
    let keep = decoder.scheme, keepCorr = decoder.correctionEnabled
    defer { decoder.scheme = keep; decoder.correctionEnabled = keepCorr }
    decoder.correctionEnabled = true
    var t1 = 0, t3 = 0, e1 = 0, e3 = 0, total = 0
    guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return (0, 0, 0, 0, 0) }
    for line in raw.split(separator: "\n") where !line.hasPrefix("#") {
        let f = line.split(separator: "\t").map(String.init); guard f.count == 3 else { continue }
        decoder.scheme = f[0] == "xiaohe" ? .xiaohe : .quanpin
        let top = decoder.decode(f[1].map(centreTap)).candidates.prefix(3).map { $0.text }
        let ex = decoder.decode(f[1].map { Tap.exact($0) }).candidates.prefix(3).map { $0.text }
        total += 1
        if top.first == f[2] { t1 += 1 }; if top.contains(f[2]) { t3 += 1 }
        if ex.first == f[2] { e1 += 1 }; if ex.contains(f[2]) { e3 += 1 }
        if debug, env["TYPO_DEBUG"] == "1" || top.first != f[2] {
            print(top.first == f[2] ? "  ok" : (top.contains(f[2]) ? "  top3" : "  MISS"), f[1], "→", top.first ?? "-", "| want", f[2],
                  "| exact →", ex.first ?? "-")
        }
    }
    return (t1, t3, e1, e3, total)
}

func noisyTaps(_ letters: String, sigmaX: Double, sigmaY: Double, rng: inout RNG) -> [Tap] {
    letters.map { c in
        let (cx, cy) = model.center(of: c)!
        let x = cx + rng.gauss() * sigmaX * model.keyWidth
        let y = cy + rng.gauss() * sigmaY * model.keyHeight
        return model.tap(x: x, y: y)
    }
}

/// English: what space would type for these taps (the autocorrection, or the letters as typed).
func englishOutput(_ ed: EnglishDecoder, _ taps: [Tap]) -> String {
    let lit = String(taps.map { $0.key })
    return (ed.autocorrection(taps)?.text ?? lit).lowercased()
}

func englishBench(_ ed: EnglishDecoder) -> [String: Double] {
    var rng = RNG(s: 42)
    let pool = ed.lexicon.words.filter { $0.zipf >= 4.0 && (3...10).contains($0.key.count) && $0.display == $0.key }
    var words: [String] = []
    for _ in 0..<1500 { words.append(pool[Int(rng.next() * Double(pool.count))].key) }
    var kept = 0, on = 0, off = 0, top3 = 0, noisy = 0, fixed = 0
    let t0 = Date()
    for w in words {
        if englishOutput(ed, w.map { Tap.exact($0) }) == w { kept += 1 }
        let taps = noisyTaps(w, sigmaX: 0.22, sigmaY: 0.198, rng: &rng)
        let lit = String(taps.map { $0.key })
        if lit == w { off += 1 } else { noisy += 1 }
        let out = englishOutput(ed, taps)
        if out == w { on += 1; if lit != w { fixed += 1 } }
        if ed.suggestions(taps).prefix(3).contains(where: { $0.text.lowercased() == w }) { top3 += 1 }
    }
    let ms = Date().timeIntervalSince(t0) * 1000 / Double(words.count * 3)
    let n = Double(words.count)
    print(String(format: "== English: clean words kept %.1f%% | touch σ=0.22: as typed %.1f%%, with autocorrect %.1f%% (fixed %d/%d), suggestions top3 %.1f%% | %.2f ms",
                 100 * Double(kept) / n, 100 * Double(off) / n, 100 * Double(on) / n, fixed, noisy, 100 * Double(top3) / n, ms))
    return ["en.kept": 100 * Double(kept) / n, "en.on": 100 * Double(on) / n, "en.top3": 100 * Double(top3) / n, "en.ms": ms]
}

/// The gate's 1,500 common words (2–4 syllables, lexicon score ≥ 900, fixed seed).
func gateWords() -> [(String, [UInt16])] {
    var rng = RNG(s: 42)
    var pool: [(String, [UInt16])] = []
    for s in 0..<lex.syllables.count {
        for i in lex.range(firstSyllable: UInt16(s)) {
            let e = lex.entry(i)
            if (2...4).contains(e.sylCount) && e.score >= 900 { pool.append((lex.text(e), lex.syllableIDs(e))) }
        }
    }
    // the same words whatever order the lexicon file keeps them in
    pool.sort { $0.1 != $1.1 ? $0.1.lexicographicallyPrecedes($1.1) : $0.0 < $1.0 }
    var items: [(String, [UInt16])] = []
    for _ in 0..<1500 { items.append(pool[Int(rng.next() * Double(pool.count))]) }
    return items
}

/// Sentences with pinyin (text TAB syllables), from comma-separated files; lines with an unknown syllable are skipped.
func loadSentences(_ files: String) -> [(String, [UInt16])] {
    let tsv = files.split(separator: ",").compactMap { try? String(contentsOfFile: String($0), encoding: .utf8) }.joined(separator: "\n")
    return tsv.split(separator: "\n").compactMap { line in
        let p = line.split(separator: "\t"); guard p.count == 2 else { return nil }
        let ids = p[1].split(separator: " ").compactMap { lex.id(of: String($0)) }
        return ids.count == p[1].split(separator: " ").count ? (String(p[0]), ids) : nil
    }
}

// MARK: - R4 按偏一个键 (slips): every key of every item replaced by each of its neighbours, the rest on key centres

/// Neighbours on the standard keyboard: centre distance under 1.2 key widths / row pitches (left, right, diagonals).
func neighbours(_ c: Character) -> [Character] {
    guard let (cx, cy) = model.center(of: c) else { return [] }
    return model.keys.filter { k in
        let dx = (k.cx - cx) / model.keyWidth, dy = (k.cy - cy) / model.keyHeight
        return k.char != c && (dx * dx + dy * dy).squareRoot() < 1.2
    }.map { $0.char }
}
/// The touch draws for the key-edge depth (one sequence per run, in enumeration order).
var slipRNG = RNG(s: 11)
/// Where the finger lands when it was aimed at `intended` and hit `typed`:
///   quarter — on `typed`, a quarter key from its centre toward `intended` (the main measure);
///   centre  — on `typed`'s centre;
///   edge    — the gate's touch noise (σ 0.22 key) aimed at `intended`, the first draw that lands on `typed`.
func slipTap(intended: Character, typed: Character, depth: String) -> Tap {
    let (ix, iy) = model.center(of: intended)!, (tx, ty) = model.center(of: typed)!
    switch depth {
    case "centre": return model.tap(x: tx, y: ty, hitKey: typed)
    case "quarter": return model.tap(x: ix + 0.75 * (tx - ix), y: iy + 0.75 * (ty - iy), hitKey: typed)
    default:
        let sx = 0.22 * model.keyWidth, sy = 0.198 * model.keyHeight
        for _ in 0..<200000 {
            let x = ix + slipRNG.gauss() * sx, y = iy + slipRNG.gauss() * sy
            if model.nearestKey(x: x, y: y) == typed { return model.tap(x: x, y: y, hitKey: typed) }
        }
        return model.tap(x: tx, y: ty, hitKey: typed)
    }
}
/// The keys as typed read as something with no correction: 小鹤 every pair a syllable's code, 全拼 whole syllables.
func legalKeys(_ keys: [Character]) -> Bool {
    if decoder.scheme == .xiaohe {
        guard keys.count % 2 == 0 else { return false }
        var i = 0
        while i + 1 < keys.count { if lex.codeToSyllables[String([keys[i], keys[i + 1]])] == nil { return false }; i += 2 }
        return true
    }
    return decoder.pinyinSyllables(String(keys)) > 0
}
/// How common a syllable is (its most frequent single character); rare = the bottom fifth of syllables.
let syllableCommonness: [Int] = (0..<lex.syllables.count).map { s in lex.singles(UInt16(s)).map { Int(lex.entry($0).score) }.max() ?? Int(Int16.min) }
let rareSyllableCut = syllableCommonness.sorted()[syllableCommonness.count / 5]
func lexiconScore(_ c: Candidate) -> Int? {
    guard let s0 = c.syllables.first else { return nil }
    for i in lex.range(firstSyllable: s0) {
        let e = lex.entry(i)
        if Int(e.sylCount) == c.syllables.count, lex.text(e) == c.text, lex.syllableIDs(e) == c.syllables { return Int(e.score) }
    }
    return nil
}

struct SlipCount {
    var clean = 0, legal = 0, legal1 = 0, legal3 = 0, legalAny = 0, other = 0, other1 = 0, other3 = 0
    var common = 0, common1 = 0, common3 = 0, uncommon = 0, uncommon1 = 0, uncommon3 = 0
    var literalWin = 0, rareWin = 0
    var buckets: [String: Int] = [:], examples: [String: [String]] = [:]
    func pct(_ a: Int, _ b: Int) -> Double { 100 * Double(a) / Double(max(b, 1)) }
}

/// Enumerate the slips of `items` (only those the clean centre taps read right) at one touch depth. `split`: whether
/// the keys as typed are another common word (words only); `diagnose`: the root-cause buckets (re-decodes the misses).
func countSlips(_ items: [(String, [Character])], depth: String, split: Bool, diagnose: Bool) -> SlipCount {
    let keepHits = model.adaptiveHits, keepCorr = decoder.correctionEnabled
    model.adaptiveHits = false            // no learned offsets: the key under the finger is the key typed
    decoder.correctionEnabled = true
    slipRNG = RNG(s: 11)
    defer { model.adaptiveHits = keepHits; decoder.correctionEnabled = keepCorr }
    var r = SlipCount()
    let keepPen = decoder.correctionPenalty, keepGCF = decoder.grammarCorrectedFactor, keepBeam = decoder.beam
    for (text, keys) in items {
        guard decoder.decode(keys.map(centreTap)).candidates.first?.text == text else { continue }
        r.clean += 1
        for p in 0..<keys.count {
            for nb in neighbours(keys[p]) {
                var v = keys; v[p] = nb
                var taps = keys.map(centreTap)
                taps[p] = slipTap(intended: keys[p], typed: nb, depth: depth)
                let res = decoder.decode(taps), c = res.candidates
                let top1 = c.first?.text == text, top3 = c.prefix(3).contains { $0.text == text }
                guard legalKeys(v) else {
                    r.other += 1; if top1 { r.other1 += 1 }; if top3 { r.other3 += 1 }
                    if !top1, env["SLIP_DEBUG"] == "other" { print("   other", String(v), "→", c.first?.text ?? "-", c.first?.corrected == true ? "(corrected)" : "", "|", text, "|", res.preedit) }
                    continue
                }
                r.legal += 1
                if top1 { r.legal1 += 1 }; if top3 { r.legal3 += 1 }
                if !top1, env["SLIP_DEBUG"] == "legal" { print("   legal", String(v), "→", c.prefix(3).map { $0.text }.joined(separator: "/"), "|", text, "|", res.preedit) }
                if c.contains(where: { $0.text == text }) { r.legalAny += 1 }
                if split {
                    decoder.correctionEnabled = false
                    let lit = decoder.decode(v.map { Tap.exact($0) }).candidates.first
                    decoder.correctionEnabled = true
                    if let lit, let s = lexiconScore(lit), s >= 900 { r.common += 1; if top1 { r.common1 += 1 }; if top3 { r.common3 += 1 } }
                    else { r.uncommon += 1; if top1 { r.uncommon1 += 1 }; if top3 { r.uncommon3 += 1 } }
                }
                guard !top1, diagnose else { continue }
                if let w = c.first, !w.corrected {
                    r.literalWin += 1
                    if w.syllables.contains(where: { syllableCommonness[Int($0)] <= rareSyllableCut }) { r.rareWin += 1 }
                }
                // the root cause, the first that applies
                var b: String
                if !taps[p].alternatives.contains(where: { $0.key == keys[p] }) { b = "1 cut (minProbability)" }
                else if !c.contains(where: { $0.text == text }) {
                    let keepPM = decoder.pruneMargin, keepCM = decoder.correctionMargin
                    decoder.pruneMargin = 30; decoder.correctionMargin = 30
                    let wide = decoder.decode(taps).candidates
                    decoder.pruneMargin = keepPM; decoder.correctionMargin = keepCM
                    if wide.first?.text == text { b = "2 syllable pruned (top1 once kept)" }
                    else if wide.contains(where: { $0.text == text }) { b = "2b syllable pruned (listed once kept)" }
                    else {
                        decoder.beam = 16; let w2 = decoder.decode(taps).candidates; decoder.beam = keepBeam
                        b = w2.contains(where: { $0.text == text }) ? "5 beam" : "6 not reached"
                    }
                } else {
                    decoder.correctionPenalty = 0; decoder.grammarCorrectedFactor = 1
                    let fair = decoder.decode(taps).candidates.first?.text == text
                    decoder.correctionPenalty = keepPen; decoder.grammarCorrectedFactor = keepGCF
                    if fair {
                        decoder.correctionPenalty = 0
                        let a = decoder.decode(taps).candidates.first?.text == text
                        decoder.correctionPenalty = keepPen
                        b = a ? "3a correctionPenalty" : "3b grammarCorrectedFactor"
                    } else { b = "4 touch + prior (in list)" }
                }
                r.buckets[b, default: 0] += 1
                if r.examples[b, default: []].count < 4 { r.examples[b, default: []].append("\(String(v))→\(c.first?.text ?? "-")|\(text)") }
            }
        }
    }
    return r
}
func slipItems(_ set: String) -> [(String, [Character])] {
    switch set {
    case "words":
        var seen = Set<String>()
        return gateWords().filter { seen.insert($0.0).inserted }.map { ($0.0, Array(codeLetters($0.1))) }
    case "holdout": return loadSentences("EngineCLI/sentences3.tsv,EngineCLI/sentences4.tsv").map { ($0.0, Array(codeLetters($0.1))) }
    default: return loadSentences("EngineCLI/sentences.tsv,EngineCLI/sentences2.tsv").map { ($0.0, Array(codeLetters($0.1))) }
    }
}

/// rare.kept: uncommon words typed on purpose (2–3 syllables, lexicon score 600–899) that the keys read first with
/// correction off, centre taps — the share still first with correction on (fixed step over the pool).
func rareKept() -> (kept: Int, n: Int, examples: [String]) {
    let keepHits = model.adaptiveHits, keepCorr = decoder.correctionEnabled
    model.adaptiveHits = false
    defer { model.adaptiveHits = keepHits; decoder.correctionEnabled = keepCorr }
    var pool: [(String, [UInt16])] = []
    for s in 0..<lex.syllables.count { for i in lex.range(firstSyllable: UInt16(s)) {
        let e = lex.entry(i)
        if (2...3).contains(e.sylCount) && e.score >= 600 && e.score < 900 { pool.append((lex.text(e), lex.syllableIDs(e))) }
    } }
    pool.sort { $0.1 != $1.1 ? $0.1.lexicographicallyPrecedes($1.1) : $0.0 < $1.0 }
    let step = max(1, pool.count / 3000)
    var n = 0, kept = 0, ex: [String] = []
    for (k, (text, ids)) in pool.enumerated() where k % step == 0 {
        let taps = codeLetters(ids).map(centreTap)
        decoder.correctionEnabled = false
        guard decoder.decode(taps).candidates.first?.text == text else { continue }
        decoder.correctionEnabled = true
        n += 1
        let on = decoder.decode(taps).candidates.first?.text
        if on == text { kept += 1 } else if ex.count < 8 { ex.append("\(text)→\(on ?? "-")") }
    }
    return (kept, n, ex)
}

switch args[2] {
case "slips":   // EngineCLI <lexicon> slips <words|sentences|holdout> <quarter|edge|centre>: one key on a neighbour (R4)
    let set = args.count > 3 ? args[3] : "words", depth = args.count > 4 ? args[4] : "quarter"
    let t0 = Date()
    let r = countSlips(slipItems(set), depth: depth, split: set == "words", diagnose: env["BUCKETS"] != "0")
    print("slips \(set) \(depth) | \(decoder.scheme == .xiaohe ? "小鹤" : "全拼") | minProbability \(model.minProbability) | items read right on clean keys \(r.clean) | \(String(format: "%.0f s", Date().timeIntervalSince(t0)))")
    print(String(format: "legal slips (the keys still spell something): n=%d  top1 %.1f%%  top3 %.1f%%  listed %.1f%%", r.legal, r.pct(r.legal1, r.legal), r.pct(r.legal3, r.legal), r.pct(r.legalAny, r.legal)))
    print(String(format: "other slips (spell nothing):                  n=%d  top1 %.1f%%  top3 %.1f%%", r.other, r.pct(r.other1, r.other), r.pct(r.other3, r.other)))
    if set == "words" {
        print(String(format: "  legal, the keys as typed are another common word (score ≥ 900): n=%d  top1 %.1f%%  top3 %.1f%%", r.common, r.pct(r.common1, r.common), r.pct(r.common3, r.common)))
        print(String(format: "  legal, the keys as typed are no common word:                   n=%d  top1 %.1f%%  top3 %.1f%%", r.uncommon, r.pct(r.uncommon1, r.uncommon), r.pct(r.uncommon3, r.uncommon)))
    }
    print("misses won by an uncorrected reading: \(r.literalWin), of which with a rare syllable (bottom fifth): \(r.rareWin)")
    for (k, v) in r.buckets.sorted(by: { $0.key < $1.key }) { print("  bucket \(k): \(v)  e.g. \(r.examples[k]!.joined(separator: "  "))") }

case "rare":
    let r = rareKept()
    print(String(format: "rare.kept %.2f%% (%d of %d)  %@", 100 * Double(r.kept) / Double(max(r.n, 1)), r.kept, r.n, r.examples.joined(separator: " ")))

case "typos":   // EngineCLI <lexicon> typos <tsv>: scheme<TAB>keys<TAB>expected — r1.top1 / r1.top3 (a record, not a gate)
    let r = r1Typos(args[3], debug: true)
    print("r1.top1 \(r.top1)/\(r.total)  r1.top3 \(r.top3)/\(r.total)  r1.exact.top1 \(r.exact1)/\(r.total)  r1.exact.top3 \(r.exact3)/\(r.total)")

case "entype":
    guard let en = decoder.english else { print("no english.bin"); exit(1) }
    let ed = EnglishDecoder(lexicon: en)
    let taps = (args.count > 3 ? args[3] : "").map { Tap.exact($0) }
    print("autocorrect:", ed.autocorrection(taps)?.text ?? "-")
    for s in ed.suggestions(taps) { print(String(format: "%7.2f", s.score), s.text, s.corrected ? "[corrected]" : "", s.completion ? "[completion]" : "") }

case "gramcount":
    // stdin: one phrase per line → phrase \t ln(count) (empty when the language model never saw it)
    guard let g = decoder.grammar else { print("no grammar"); exit(1) }
    while let line = readLine() {
        let t = line.split(separator: "\t").first.map(String.init) ?? line
        if let v = g.logCount(Array(t)) { print("\(t)\t\(String(format: "%.3f", v))") } else { print("\(t)\t") }
    }

case "wordscore":
    while let line = readLine() { let c = Array(line); if c.count == 1 { print(line, decoder.charScore(c[0])) }; if c.count == 2 { print(line, decoder.wordScore(c[0], c[1]).map { String(format: "%.2f", $0) } ?? "-") } }

case "predbench":
    // 联想 quality: in every sentence, after each character, do the suggestions hold what comes next?
    // SEG: the sentences cut into words (space-separated): only word boundaries are scored there
    let files = (env["SEG"] ?? env["SENTENCES"] ?? "EngineCLI/sentences.tsv,EngineCLI/sentences2.tsv").split(separator: ",")
    let segmented = env["SEG"] != nil
    var points = 0, hit1 = 0, hit6 = 0, saved = 0, total = 0, exact = 0
    if let v = env["PMC"].flatMap(Double.init) { decoder.predictionMinChar = v }
    if let v = env["PSW"].flatMap(Double.init) { decoder.predictionSplitWord = v }
    if let v = env["PSP"].flatMap(Double.init) { decoder.predictionSplitPenalty = v }
    if let v = env["PNB"].flatMap(Double.init) { decoder.grammar?.contextBonus = v }
    if let v = env["PSTOP"].flatMap(Int.init) { decoder.grammar?.continuationStop = v }
    for f in files {
        for line in (try! String(contentsOfFile: String(f), encoding: .utf8)).split(separator: "\n") {
            guard let t0 = line.split(separator: "\t").first else { continue }
            let words = t0.split(separator: " ").map(String.init)
            let c = Array(words.joined())
            var bounds = Set<Int>(); var acc = 0
            for w in words { acc += w.count; bounds.insert(acc) }
            total += c.count
            for k in 1..<c.count where !segmented || bounds.contains(k) {
                let p = decoder.predictions(after: Array(c[..<k]), limit: 6)
                guard !p.isEmpty else { continue }
                points += 1
                let rest = String(c[k...])
                if let first = p.first, rest.hasPrefix(first) { hit1 += 1 }
                if let m = p.filter({ rest.hasPrefix($0) }).max(by: { $0.count < $1.count }) { hit6 += 1; saved += m.count }
                if segmented, let wi = words.indices.first(where: { words[..<$0].joined().count == k }), p.contains(words[wi]) { exact += 1 }
            }
        }
    }
    print(String(format: "predbench: points %d  top1 %.1f%%  top6 %.1f%%  next word in top6 %.1f%%  chars covered %.1f%%", points,
                 100 * Double(hit1) / Double(points), 100 * Double(hit6) / Double(points), 100 * Double(exact) / Double(points),
                 100 * Double(saved) / Double(total)))

case "predict":
    // stdin: one context per line → what tends to follow it
    guard let g = decoder.grammar else { print("no grammar"); exit(1) }
    while let line = readLine() {
        let t0 = Date()
        let c = decoder.predictions(after: Array(line))
        _ = g
        print(line, "→", c.joined(separator: " "),
              String(format: "%.1f ms", Date().timeIntervalSince(t0) * 1000))
    }

case "codes":
    for s in lex.syllables { print(s, XiaoheScheme.code(for: s) ?? "-") }

case "type":
    let letters = args.count > 3 ? args[3] : ""
    let t0 = Date()
    let t9 = ProcessInfo.processInfo.environment["T9"] == "1"   // keys are 九宫格 digits (2–9, ' for 分词)
    if let spec = ProcessInfo.processInfo.environment["LEARN"] {   // "zhang zi xuan|张梓萱;..." learned once each first
        let ud = UserDictionary(lexicon: lex, url: nil)
        let idMap = Dictionary(uniqueKeysWithValues: lex.syllables.enumerated().map { ($1, UInt16($0)) })
        for item in spec.split(separator: ";") {
            let f = item.split(separator: "|")
            let ids = f[0].split(separator: " ").compactMap { idMap[String($0)] }
            for _ in 0..<(f.count > 2 ? Int(f[2])! : 1) { ud.learn(syllables: ids, text: String(f[1])) }
        }
        decoder.user = ud
    }
    let r = decoder.decode(letters.map { t9 ? Tap.t9($0) : Tap.exact($0) })
    let ms = Date().timeIntervalSince(t0) * 1000
    print("preedit: \(r.preedit)   (\(String(format: "%.1f", ms)) ms)")
    if t9 { print("拼音:", decoder.t9SyllableChoices(letters.map { Tap.t9($0) }).choices.prefix(12).map { $0.text }.joined(separator: " ")) }
    for c in r.candidates.prefix(15) {
        let fx = decoder.fixes(for: c, taps: letters.map { t9 ? Tap.t9($0) : Tap.exact($0) }).map { "\($0.typed)→\($0.meant)" }.joined(separator: " ")
        print(String(format: "%6.2f", c.score), c.text, "taps=\(c.tapCount)", c.corrected ? "[corrected \(fx)]" : "")
    }

case "bench", "gate":
    var metrics: [String: Double] = [:]
    // Test items: common 2–4 syllable words sampled from the lexicon + everyday sentences.
    let items = gateWords()
    // Everyday sentences with pinyin (EngineCLI/sentences.tsv, generated with pypinyin and spot-checked).
    // two sets: the first written while tuning, the second (180 sentences of chat, work, shopping, children, travel)
    // kept apart and only measured — together they are the gate's sentences
    let files = (env["SENTENCES"] ?? "EngineCLI/sentences.tsv,EngineCLI/sentences2.tsv").split(separator: ",")
    let tsv = files.compactMap { try? String(contentsOfFile: String($0), encoding: .utf8) }.joined(separator: "\n")
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
            if refs.last == t { refIsTarget += 1 } else if env["PERFECT_DEBUG"] != nil, name == "sentences" { print("  ✗", t, "→", refs.last!) }
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
            var offOK = 0, onOK = 0, onTop3 = 0, harmed = 0, cleanItems = 0, fixed = 0, noisyItems = 0, onTrue = 0
            for (k, (intended, ids)) in set.enumerated() {
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
                if on == intended { onTrue += 1 }
                if on == refs[k] { onOK += 1 } else if env["NOISY_DEBUG"] != nil, name == "sentences" {
                    print("   ", refs[k], "→", on, "| typed", String(taps.map { $0.key }), wrong > 0 ? "(\(wrong) wrong)" : "(clean)")
                }
                if onR.prefix(3).contains(where: { $0.text == refs[k] }) { onTop3 += 1 }
                if wrong == 0 { cleanItems += 1; if on != refs[k] { harmed += 1 } }
                else { noisyItems += 1; if on == refs[k] { fixed += 1 } }
            }
            let n = Double(set.count)
            if abs(sg - 0.22) < 1e-9 {
                metrics["\(name).on"] = 100 * Double(onOK) / n
                metrics["\(name).true"] = 100 * Double(onTrue) / n
                print(String(format: "   (σ=0.22, correction on, top1 == intended text: %.1f%%)", 100 * Double(onTrue) / n))
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
            let all = set.map { ($0.0, codeLetters($0.1).map { Tap.t9(Tap.t9Digit($0)) }) }
            for (t, taps) in all {
                let c = decoder.decode(taps).candidates
                if c.first?.text == t { top1 += 1 } else if env["T9_DEBUG"] != nil, name == "sentences" { print("  ✗", t, "→", c.first?.text ?? "-") }
                if c.prefix(3).contains(where: { $0.text == t }) { top3 += 1 }
            }
            // timing: best of two warm passes (a busy shared CI runner must not fail the gate on noise)
            var ms = Double.infinity
            for _ in 0..<2 {
                let t0 = Date()
                for (_, taps) in all { _ = decoder.decode(taps) }
                ms = min(ms, Date().timeIntervalSince(t0) * 1000 / Double(all.count))
            }
            metrics["t9.\(name).top1"] = 100 * Double(top1) / Double(set.count)
            metrics["t9.\(name).top3"] = 100 * Double(top3) / Double(set.count)
            metrics["t9.\(name).ms"] = ms
            print(String(format: "== 九宫格 %@: top1 %.1f%%  top3 %.1f%%  %.2f ms", name, metrics["t9.\(name).top1"]!, metrics["t9.\(name).top3"]!, ms))
        }
    }

    // 中英混输 inside sentences: EngineCLI/mixed.tsv (text, pinyin syllables and |english words), top-1 equals the text (letter case aside)
    if let raw = try? String(contentsOfFile: env["MIXED"] ?? "EngineCLI/mixed.tsv", encoding: .utf8) {
        decoder.correctionEnabled = true
        var ok = 0, total = 0
        for line in raw.split(separator: "\n") {
            let f = line.split(separator: "\t"); guard f.count == 2 else { continue }
            // keys: pinyin syllables (typed in the scheme under test) and |english words, space-separated
            let keys = f[1].split(separator: " ").map { tok -> String in
                tok.hasPrefix("|") ? String(tok.dropFirst()) : lex.id(of: String(tok)).map { decoder.spelling(of: $0) } ?? String(tok)
            }.joined()
            let c = decoder.decode(keys.map { Tap.exact($0) }).candidates
            total += 1
            if c.first?.text.lowercased() == f[0].lowercased() { ok += 1 } else if env["MIX_DEBUG"] != nil { print("   ≠", f[0], "→", c.first?.text ?? "-") }
        }
        metrics["mixed.sentences.top1"] = 100 * Double(ok) / Double(max(total, 1))
        print(String(format: "== 中英混输 sentences: top1 %.1f%% (n=%d)", metrics["mixed.sentences.top1"]!, total))
    }

    // 多按了一个键: every sentence typed once more with one key too many, somewhere inside — the key before it
    // pressed twice, or a neighbour of the next key brushed on the way — perfect keys otherwise.
    //   extra.sentences.top1 — top-1 equals the intended sentence (%)
    do {
        decoder.correctionEnabled = true
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map(Array.init)
        func neighbour(_ c: Character, _ r: inout RNG) -> Character {
            for row in rows { if let i = row.firstIndex(of: c) {
                let j = i == 0 ? 1 : i == row.count - 1 ? i - 1 : (r.next() < 0.5 ? i - 1 : i + 1)
                return row[j]
            } }
            return c
        }
        var rng = RNG(s: 7), ok = 0, top3 = 0, total = 0
        // fix.caption.coverage: of the first candidates read with a correction, how many can say what was changed
        var fixMarked = 0, fixSaid = 0
        func countFix(_ c: Candidate?, _ letters: [Character]) {
            guard let c, c.corrected else { return }
            fixMarked += 1
            if !decoder.fixes(for: c, taps: letters.map { Tap.exact($0) }).isEmpty { fixSaid += 1 }
            else if env["FIX_DEBUG"] != nil { print("   ? no fix:", c.text, "|", String(letters)) }
        }
        // dedupe.pairs: among the first three candidates, two whole readings that differ only in their last character
        // (开心那 / 开心你, 方案没 / 方案吗) — the second takes a place a different reading should have
        // dedupe.pairs counts pairs whose last words are both one character (what the decoder sets aside);
        // dedupe.pairs.any every pair differing only in the last character (homophone words too: 门口 / 门扣)
        var dupPairs = 0, dupAny = 0
        func countDup(_ c: [Candidate], _ n: Int) {
            let top = c.prefix(3).filter { $0.tapCount == n && $0.text.count >= 2 }
            for x in 0..<top.count { for y in (x + 1)..<max(x + 1, top.count) where top[x].text.count == top[y].text.count
                && top[x].text.dropLast() == top[y].text.dropLast() {
                dupAny += 1
                let single = top[x].lastWordLength == 1 && top[y].lastWordLength == 1
                if single { dupPairs += 1 }
                if env["DUP_DEBUG"] != nil { print("   dup\(single ? "1" : "*"):", top[x].text, "/", top[y].text) }
            } }
        }
        for (k, (t, ids)) in sentItems.enumerated() {
            var letters = Array(codeLetters(ids))
            guard letters.count >= 4 else { continue }
            let p = 1 + Int(rng.next() * Double(letters.count - 2))
            letters.insert(k % 2 == 0 ? letters[p - 1] : neighbour(letters[p], &rng), at: p)
            let c = decoder.decode(letters.map { Tap.exact($0) }).candidates
            total += 1
            countFix(c.first, letters)
            countDup(c, letters.count)
            if c.first?.text == t { ok += 1 } else if env["EXTRA_DEBUG"] != nil { print("   +", t, "→", c.first?.text ?? "-", "|", String(letters)) }
            if c.prefix(3).contains(where: { $0.text == t }) { top3 += 1 }
        }
        metrics["extra.sentences.top1"] = 100 * Double(ok) / Double(max(total, 1))
        // and with one key left out instead (小鹤 too, as a record: a pair missing a key shifts every pair after it)
        var mok = 0, mtotal = 0
        for (t, ids) in sentItems {
            var letters = Array(codeLetters(ids))
            guard letters.count >= 4 else { continue }
            letters.remove(at: 1 + Int(rng.next() * Double(letters.count - 2)))
            let c = decoder.decode(letters.map { Tap.exact($0) }).candidates
            mtotal += 1
            if decoder.scheme == .quanpin { countFix(c.first, letters) }
            countDup(c, letters.count)
            if c.first?.text == t { mok += 1 } else if env["MISS_DEBUG"] != nil { print("   -", t, "→", c.first?.text ?? "-", "|", String(letters)) }
        }
        metrics["missing.sentences.top1"] = 100 * Double(mok) / Double(max(mtotal, 1))
        // 句末多按: one key too many after the last key (全拼) — half the sentences the last key pressed twice, half a
        // neighbour of it brushed; perfect keys otherwise. extra.tail.top1 / top3 (%)
        if decoder.scheme == .quanpin {
            var rngT = RNG(s: 7), tok = 0, t3 = 0, tn = 0
            for (k, (t, ids)) in sentItems.enumerated() {
                var letters = Array(codeLetters(ids))
                guard letters.count >= 4 else { continue }
                letters.append(k % 2 == 0 ? letters.last! : neighbour(letters.last!, &rngT))
                let c = decoder.decode(letters.map { Tap.exact($0) }).candidates
                tn += 1
                countFix(c.first, letters)
                countDup(c, letters.count)
                if c.first?.text == t { tok += 1 } else if env["TAIL_DEBUG"] != nil {
                    print("   ▸", t, "→", c.prefix(3).map { $0.text }.joined(separator: " / "), "|", String(letters))
                }
                if c.prefix(3).contains(where: { $0.text == t }) { t3 += 1 }
            }
            metrics["extra.tail.top1"] = 100 * Double(tok) / Double(max(tn, 1))
            metrics["extra.tail.top3"] = 100 * Double(t3) / Double(max(tn, 1))
            print(String(format: "== one key too many after the last: sentences top1 %.1f%%  top3 %.1f%%  (n=%d)",
                         metrics["extra.tail.top1"]!, metrics["extra.tail.top3"]!, tn))
        }
        metrics["dedupe.pairs"] = Double(dupPairs)
        metrics["dedupe.pairs.any"] = Double(dupAny)
        print(String(format: "== first three readings differing only in their last character: %d pairs with one-character last words, %d in all", dupPairs, dupAny))
        // 两处按错: one key too many or left out in the first half of the sentence and another in the second half
        // (a key pressed twice, a neighbour brushed, or a key left out), both schemes. two.sentences.top1 / top3 (%)
        do {
            var rngW = RNG(s: 11), wok = 0, w3 = 0, wn = 0
            for (t, ids) in sentItems {
                var letters = Array(codeLetters(ids))
                guard letters.count >= 8 else { continue }
                let h = letters.count / 2
                let b = h + 1 + Int(rngW.next() * Double(letters.count - 2 - h))
                let a = 1 + Int(rngW.next() * Double(h - 2))
                for idx in [b, a] {
                    if rngW.next() < 0.5 {
                        letters.insert(rngW.next() < 0.5 ? letters[idx - 1] : neighbour(letters[idx], &rngW), at: idx)
                    } else {
                        letters.remove(at: idx)
                    }
                }
                let c = decoder.decode(letters.map { Tap.exact($0) }).candidates
                wn += 1
                if c.first?.text == t { wok += 1 } else if env["TWO_DEBUG"] != nil { print("   ±", t, "→", c.first?.text ?? "-", "|", String(letters)) }
                if c.prefix(3).contains(where: { $0.text == t }) { w3 += 1 }
            }
            metrics["two.sentences.top1"] = 100 * Double(wok) / Double(max(wn, 1))
            metrics["two.sentences.top3"] = 100 * Double(w3) / Double(max(wn, 1))
            print(String(format: "== two keys wrong (one too many or left out, in each half): sentences top1 %.1f%%  top3 %.1f%%  (n=%d)",
                         metrics["two.sentences.top1"]!, metrics["two.sentences.top3"]!, wn))
        }
        metrics["fix.caption.coverage"] = 100 * Double(fixSaid) / Double(max(fixMarked, 1))
        print(String(format: "== corrections that say what changed: %.1f%% (%d of %d)", metrics["fix.caption.coverage"]!, fixSaid, fixMarked))
        if mtotal > 0 { print(String(format: "== one key missing: sentences top1 %.1f%%", metrics["missing.sentences.top1"]!)) }
        print(String(format: "== one key too many: sentences top1 %.1f%%  top3 %.1f%%  (n=%d)", metrics["extra.sentences.top1"]!, 100 * Double(top3) / Double(max(total, 1)), total))
    }

    // Touch adaptation: a user whose thumbs land off-centre in a pattern (keys on the left hit to their right, on the
    // right to their left, the top row low), σ=0.22 noise on top. Words typed with corrections learned from what was
    // committed; then fresh words measured with what was learned.
    //   adapt.before / adapt.after — top-1 on unseen words before and after 1000 words of use (%)
    do {
        decoder.correctionEnabled = true
        let user = SpatialModel.standard()
        let kw = user.keyWidth, kh = user.keyHeight
        func biased(_ letters: String, _ m: SpatialModel, _ r: inout RNG) -> [Tap] {
            letters.map { c in
                let (cx, cy) = m.center(of: c) ?? (0, 0)
                let left = cx < 5 * kw
                let row0 = cy < kh
                let x = cx + (left ? 0.22 : -0.22) * kw + r.gauss() * 0.22 * kw
                let y = cy + (row0 ? 0.25 : 0.05) * kh + r.gauss() * 0.198 * kh
                return m.tap(x: x, y: y)
            }
        }
        func accuracy(_ m: SpatialModel, _ set: ArraySlice<(String, [UInt16])>, seed: UInt64) -> Double {
            var r = RNG(s: seed), ok = 0
            for (t, ids) in set where decoder.decode(biased(codeLetters(ids), m, &r)).candidates.first?.text == t { ok += 1 }
            return 100 * Double(ok) / Double(set.count)
        }
        let learnSet = items[..<1000], testSet = items[1000...]
        let fresh = SpatialModel.standard()
        metrics["adapt.before"] = accuracy(fresh, testSet, seed: 7)
        let m = SpatialModel.standard()
        if let v = env["KR"].flatMap(Double.init) { m.keyRate = v }
        if env["AH"] == "0" { m.adaptiveHits = false }
        var r = RNG(s: 3)
        for (t, ids) in learnSet {
            let letters = codeLetters(ids)
            let taps = biased(letters, m, &r)
            // committed as intended (the user picks it if it is not first); learn from the keys it stands for
            guard decoder.decode(taps).candidates.prefix(5).contains(where: { $0.text == t }) else { continue }
            for (tap, key) in zip(taps, letters) { m.observe(tap: tap, intended: key) }
        }
        metrics["adapt.after"] = accuracy(m, testSet, seed: 7)
        print(String(format: "== touch adaptation (thumbs off-centre): unseen words %.1f%% → %.1f%% after 1000 words (offset %.2f, %.2f)",
                     metrics["adapt.before"]!, metrics["adapt.after"]!, m.offsetX, m.offsetY))
    }

    // Learning, as a user would teach it: type each sentence; when the first candidate is not what was meant, pick the
    // longest candidate that is (as the keyboard learns from picks), repeating until the sentence is in.
    //   learn.picks  — candidate picks per sentence on the first pass (1.0 = space was enough every time)
    //   learn.same   — the same sentences typed again: right first time (%)
    //   learn.heldout — sentences never typed, after learning the others: right first time (%), against
    //   learn.base   — the same held-out sentences with nothing learned (learning must not make them worse)
    do {
        decoder.correctionEnabled = true
        func typeIn(_ t: String, _ ids: [UInt16], _ ud: UserDictionary) -> Int {
            var taps = codeLetters(ids).map { Tap.exact($0) }
            var rest = Substring(t)
            var picks = 0
            var parts: [(String, [UInt16])] = []
            while !taps.isEmpty, picks < 20 {
                let r = decoder.decode(taps)
                guard let c = r.candidates.first(where: { $0.tapCount > 0 && !$0.syllables.isEmpty && rest.hasPrefix($0.text) }) else { break }
                if r.candidates.first?.text != c.text || picks > 0 || c.tapCount < taps.count { picks += 1 }
                ud.learn(syllables: c.syllables, text: c.text)
                parts.append((c.text, c.syllables))
                rest = rest.dropFirst(c.text.count)
                taps.removeFirst(c.tapCount)
            }
            ud.learn(parts: parts.map { (text: $0.0, ids: $0.1) })
            return max(1, picks)
        }
        func firstTime(_ set: ArraySlice<(String, [UInt16])>) -> Double {
            var ok = 0
            for (t, ids) in set {
                let top = decoder.decode(codeLetters(ids).map { Tap.exact($0) }).candidates.first?.text
                if top == t { ok += 1 } else if env["LEARN_DEBUG"] != nil { print("  ", t, "→", top ?? "") }
            }
            return 100 * Double(ok) / Double(set.count)
        }
        let half = sentItems.count / 2
        decoder.user = nil
        metrics["learn.base"] = firstTime(sentItems[half...])
        let ud = UserDictionary(lexicon: lex, url: nil)
        decoder.user = ud
        var picks = 0
        for (t, ids) in sentItems[..<half] { picks += typeIn(t, ids, ud) }
        metrics["learn.heldout"] = firstTime(sentItems[half...])
        for (t, ids) in sentItems[half...] { picks += typeIn(t, ids, ud) }
        metrics["learn.picks"] = Double(picks) / Double(sentItems.count)
        metrics["learn.same"] = firstTime(sentItems[...])
        metrics["learn.harm"] = metrics["learn.base"]! - metrics["learn.heldout"]!
        decoder.user = nil
        // 自造词: a phrase the lexicon does not read (names, the user's own terms), committed once — typed again alone
        // it must come first, and inside a sentence it must be read as that phrase
        do {
            var rngU = RNG(s: 11)
            var phrases: [(text: String, ids: [UInt16], sentence: Int)] = []
            for (si, (t, ids)) in sentItems.enumerated() where t.count >= 6 {
                let chars = Array(t)
                let L = 3 + Int(rngU.next() * 2)
                let a = Int(rngU.next() * Double(chars.count - L))
                let pt = String(chars[a..<a + L]), pids = Array(ids[a..<a + L])
                guard pt.allSatisfy({ $0.unicodeScalars.first!.value >= 0x4E00 }) else { continue }
                let top = decoder.decode(codeLetters(pids).map { Tap.exact($0) }).candidates.first?.text
                if top != pt { phrases.append((pt, pids, si)) }
            }
            let ud2 = UserDictionary(lexicon: lex, url: nil)
            for ph in phrases { ud2.learn(syllables: ph.ids, text: ph.text) }
            decoder.user = ud2
            var alone = 0, inside = 0, insideN = 0
            for ph in phrases {
                let top = decoder.decode(codeLetters(ph.ids).map { Tap.exact($0) }).candidates.first?.text
                if top == ph.text { alone += 1 } else if env["USER_DEBUG"] != nil { print("   alone", ph.text, "→", top ?? "") }
                let (t, ids) = sentItems[ph.sentence]
                guard ids.count <= 14 else { continue }
                insideN += 1
                let st = decoder.decode(codeLetters(ids).map { Tap.exact($0) }).candidates.first?.text ?? ""
                if st.contains(ph.text) { inside += 1 } else if env["USER_DEBUG"] != nil { print("   inside", ph.text, "|", t, "→", st) }
            }
            // by initials and half typed (全拼): 莫斯托 from mst, 摸索台灯 second from mosuotai
            if decoder.scheme == .quanpin {
                let idMap = Dictionary(uniqueKeysWithValues: lex.syllables.enumerated().map { ($1, UInt16($0)) })
                ud2.learn(syllables: ["mo", "si", "tuo"].compactMap { idMap[$0] }, text: "莫斯托")
                ud2.learn(syllables: ["mo", "suo", "tai", "deng"].compactMap { idMap[$0] }, text: "摸索台灯")
                let a = decoder.decode("mst".map { Tap.exact($0) }).candidates.first?.text
                let b = decoder.decode("mosuotai".map { Tap.exact($0) }).candidates.prefix(2).map { $0.text }
                if a != "莫斯托" || !b.contains("摸索台灯") { alone = 0; print("   自造词 mst →", a ?? "", "| mosuotai →", b) }
            }
            decoder.user = nil
            metrics["userword.alone"] = 100 * Double(alone) / Double(max(phrases.count, 1))
            metrics["userword.inside"] = 100 * Double(inside) / Double(max(insideN, 1))
            print(String(format: "== 自造词: alone top1 %.1f%% (n=%d) | inside its sentence %.1f%% (n=%d)",
                         metrics["userword.alone"]!, phrases.count, metrics["userword.inside"]!, insideN))
        }
        print(String(format: "== learning: picks/sentence %.2f | typed again %.1f%% | unseen after learning %.1f%% (nothing learned %.1f%%)",
                     metrics["learn.picks"]!, metrics["learn.same"]!, metrics["learn.heldout"]!, metrics["learn.base"]!))
    }

    if let en = decoder.english, decoder.scheme == .xiaohe {
        let m = englishBench(EnglishDecoder(lexicon: en))
        for (k, v) in m { metrics[k] = v }
    }

    if args[2] == "gate" {
        // Regression gate for CI: the release does not go out if typing quality drops below these floors.
        // 小鹤双拼 and 全拼 each have their own floors (set a little under the measured values)
        let floors: [(String, Double, Bool)] = decoder.scheme == .xiaohe ? [
            ("words.on", 96.0, true),          // σ=0.22 touch noise, correction on, top-1 (%)
            ("words.broken", 1.0, false),      // clean words changed by correction (%) — at most
            ("sentences.perfect", 91.0, true), // perfect keys, top-1 equals the intended sentence (%)
            ("sentences.on", 90.0, true),
            ("sentences.true", 87.5, true),    // σ=0.22 touch noise, correction on, top-1 equals the intended sentence (%)
            ("words.ms", 3.0, false),          // average decode time (ms) — at most
            ("en.kept", 99.0, true),            // English: correctly typed words left alone (%)
            ("en.on", 97.0, true),              // English: σ=0.22 touch noise, what space types is the word (%)
            ("en.top3", 98.0, true),            // English: the word among the first three suggestions (%)
            ("t9.words.top1", 47.0, true),     // 九宫格 (each key = its 3–4 letters), perfect keys
            ("t9.sentences.top3", 55.0, true),
            ("t9.sentences.ms", 20.0, false),
            ("learn.same", 95.0, true),        // sentences typed again after picking them once (%)
            ("userword.alone", 98.0, true),    // 自造词 typed again alone: first (%)
            ("userword.inside", 94.0, true),   // 自造词 inside its sentence: read as that phrase (%)
            ("adapt.after", 78.0, true),       // off-centre thumbs, unseen words after 1000 words of use (%)
            ("learn.harm", 1.0, false),        // unseen sentences made worse by what was learned (points) — at most
            ("fuzz.bad", 0.0, false),          // random input: candidates that use no keys, too many, or have no text
            ("fuzz.p99.ms", 40.0, false),      // random input: 99th-percentile decode time (ms) — at most
            ("extra.sentences.top1", 55.0, true),  // a sentence with one key too many still read right (%)
            ("mixed.sentences.top1", 72.0, true),  // an English word inside a Chinese sentence (%)
            ("fix.caption.coverage", 98.0, true), // a corrected first candidate says what it changed (%)
            ("dedupe.pairs", 100.0, false),    // first three readings differing only in a last one-character word (at most two per sentence)
            // R4 按偏一个键 (a quarter key onto a neighbour; the keys as typed still spell something = legal)
            ("slip.words.legal.top1", 79.0, true),
            ("slip.words.legal.top3", 96.5, true),
            ("slip.words.other.top1", 96.5, true),   // control: the keys as typed spell nothing
            ("slip.sent.legal.top1", 79.0, true),
            ("slip.sent.legal.top3", 93.0, true),
            ("slip.sent.other.top1", 96.0, true),
            ("slip.words.edge.legal.top1", 85.5, true),   // on the key's edge (the gate's touch noise)
            ("slip.words.centre.legal.top1", 40.5, true), // on the neighbour's centre
            ("rare.kept", 99.5, true),         // uncommon words typed on purpose stay first (%)
        ] : [
            ("words.on", 97.0, true),
            ("words.broken", 1.0, false),
            ("sentences.perfect", 91.0, true),
            ("sentences.on", 92.0, true),
            ("sentences.true", 88.0, true),
            ("sentences.ms", 16.0, false),     // CI runners vary 2–5× (1.2 ms locally)
            ("t9.words.top1", 66.0, true),
            ("t9.sentences.top1", 71.0, true),
            ("t9.sentences.ms", 150.0, false),
            ("learn.same", 95.0, true),
            ("userword.alone", 98.0, true),
            ("userword.inside", 94.0, true),
            ("learn.harm", 1.0, false),
            ("fuzz.bad", 0.0, false),
            ("fuzz.p99.ms", 100.0, false),
            ("extra.sentences.top1", 84.0, true),
            ("missing.sentences.top1", 48.0, true), // a sentence with one key left out still read right (%)
            ("mixed.sentences.top1", 78.0, true),
            ("fix.caption.coverage", 98.0, true),
            ("extra.tail.top1", 71.0, true),   // one key too many after the last key still read right (%)
            ("extra.tail.top3", 90.0, true),   // … among the first three (%)
            ("dedupe.pairs", 100.0, false),
            ("slip.words.legal.top1", 85.0, true),
            ("slip.words.legal.top3", 97.5, true),
            ("slip.words.other.top1", 97.5, true),
            ("slip.sent.legal.top1", 85.0, true),
            ("slip.sent.legal.top3", 95.0, true),
            ("slip.sent.other.top1", 96.0, true),
            ("rare.kept", 99.5, true),
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
        // 小鹤双拼 with an odd number of keys: the dangling key carries the reading on (可以 + l → 可以了)
        if decoder.scheme == .xiaohe {
            decoder.correctionEnabled = true
            let odd: [(String, String)] = [("keyil", "可以了"), ("nihcm", "你好吗"), ("hcden", "好的呢"), ("wogg", "我")]
            var bad: [String] = []
            for (k, want) in odd {
                let c = decoder.decode(k.map { Tap.exact($0) }).candidates.first
                let ok = k.count % 2 == 1 ? c?.text == want && c?.tapCount == k.count : c?.text.hasPrefix(want) == true
                if !ok { bad.append("\(k)→\(c?.text ?? "-")") }
            }
            print(bad.isEmpty ? "PASS odd.top1 \(odd.count)/\(odd.count)" : "FAIL odd.top1 " + bad.joined(separator: " "))
            if !bad.isEmpty { failed = true }
        }
        // Learned words survive a save and a reload; an unreadable file is set aside (not lost, not a crash)
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mosto-ud-\(getpid())")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("userdict.json")
            let ud = UserDictionary(lexicon: lex, url: url)
            let words: [(String, String)] = [("ni hao", "你好"), ("ke yi le", "可以了"), ("mo tou", "魔头")]
            for (py, t) in words { ud.learn(syllables: py.split(separator: " ").map { lex.id(of: String($0))! }, text: t) }
            ud.save()
            let back = UserDictionary(lexicon: lex, url: url)
            let kept = words.allSatisfy { back.contains(syllables: $0.0.split(separator: " ").map { lex.id(of: String($0))! }, text: $0.1) }
            try? Data("{not json".utf8).write(to: url)
            let broken = UserDictionary(lexicon: lex, url: url)
            let aside = FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path)
            let ok = kept && back.count == words.count && broken.count == 0 && aside
            print(ok ? "PASS userdict.roundtrip" : "FAIL userdict.roundtrip kept=\(kept) count=\(back.count) broken=\(broken.count) aside=\(aside)")
            if !ok { failed = true }
            try? FileManager.default.removeItem(at: dir)
        }
        // the key chart (键位提示 and the app's 小鹤双拼 page) agrees with the code table
        do {
            let bad = XiaoheScheme.guideAgrees()
            print(bad.isEmpty ? "PASS xiaohe.keyguide" : "FAIL xiaohe.keyguide " + bad.joined(separator: " "))
            if !bad.isEmpty { failed = true }
        }
        // 联想: the model's suggestions, and what this user wrote after the same words before
        do {
            let ud = UserDictionary(lexicon: lex, url: nil)
            let d2 = Decoder(lexicon: lex, user: ud)
            d2.grammar = decoder.grammar
            d2.predictionGrammar = decoder.predictionGrammar
            func ids(_ py: String) -> [UInt16] { py.split(separator: " ").map { lex.id(of: String($0))! } }
            ud.learn(parts: [("魔头", ids("mo tou")), ("小金冠", ids("xiao jin guan"))])
            let model = d2.predictions(after: Array("我们"))
            let mine = d2.predictions(after: Array("今天的魔头"))
            let ok = model.count >= 4 && model.contains("在") && mine.first == "小金冠"
            print(ok ? "PASS predict.model+user" : "FAIL predict.model+user 我们→\(model) 魔头→\(mine)")
            if !ok { failed = true }
        }
        // Fuzz: random keys, separators, 九宫格 mixes and long runs. Every decode must give candidates that each
        // use 1…n keys and have text, committing the first candidate over and over must use up all keys, and the
        // slowest decode must stay quick enough to keep up with typing.
        do {
            var rng = RNG(s: 7)
            let letters = Array("abcdefghijklmnopqrstuvwxyz")
            var bad: [String] = []
            var worst = 0.0, worstInput = ""
            var times: [Double] = []
            decoder.correctionEnabled = true
            for i in 0..<1500 {
                let n = i < 1400 ? 1 + Int(rng.next() * 16) : 24 + Int(rng.next() * 17)
                var taps: [Tap] = []
                for _ in 0..<n {
                    let r = rng.next()
                    if r < 0.05 { taps.append(Tap(key: "'", alternatives: [])) }
                    else if r < 0.25 { taps.append(Tap.t9(Character(String(2 + Int(rng.next() * 8))))) }
                    else {
                        let c = letters[Int(rng.next() * 26)]
                        taps.append(r < 0.6 ? Tap.exact(c) : noisyTaps(String(c), sigmaX: 0.3, sigmaY: 0.27, rng: &rng)[0])
                    }
                }
                let raw = String(taps.map { $0.key })
                var rest = taps, rounds = 0
                while !rest.isEmpty && rounds <= taps.count {
                    // timed twice, the faster counts: the first can stall on pages of the memory-mapped lexicon the
                    // shared CI runner has not read yet (disk, not decoder: 3.7 ms locally vs 137 ms on a busy runner)
                    var ms = Double.infinity
                    var r = Decoder.Result(candidates: [], preedit: "")
                    for _ in 0..<2 {
                        let t0 = Date()
                        r = decoder.decode(rest)
                        if rest.contains(where: { $0.group }) { _ = decoder.t9SyllableChoices(rest) }
                        ms = min(ms, Date().timeIntervalSince(t0) * 1000)
                    }
                    times.append(ms)
                    if ms > worst { worst = ms; worstInput = String(rest.map { $0.key }) }
                    if let c = r.candidates.first(where: { $0.tapCount < 1 || $0.tapCount > rest.count || $0.text.isEmpty }) {
                        bad.append("\(raw): \(c.text)/\(c.tapCount)"); break
                    }
                    // what the keyboard commits: the first candidate, or the keys as typed when there is none
                    guard let first = r.candidates.first else { break }
                    rest.removeFirst(first.tapCount)
                    rounds += 1
                }
                if !rest.isEmpty && rounds > taps.count { bad.append("\(raw): no progress") }
                if bad.count >= 5 { break }
            }
            metrics["fuzz.bad"] = Double(bad.count)
            // the gate holds the 99th percentile: the single slowest decode on a shared CI runner is mostly a page
            // fault into the memory-mapped lexicon (13 ms locally, 120 ms on a busy runner), not the decoder
            times.sort()
            let p99 = times.isEmpty ? 0 : times[min(times.count - 1, Int(Double(times.count) * 0.99))]
            metrics["fuzz.p99.ms"] = p99
            print(String(format: "== fuzz: 1500 inputs, invalid %d, decode p99 %.1f ms, slowest %.1f ms (%@)", bad.count, p99, worst, worstInput))
            for b in bad { print("   ", b) }
        }
        // R4 按偏一个键: every key of the gate's words and sentences (those the clean centre taps read right) replaced
        // by each neighbour, the touch a quarter key from the key hit toward the one meant (also on the key's edge and
        // centre, words). legal = the keys as typed still spell something; other = they spell nothing (control).
        // rare.kept: uncommon words typed on purpose stay first once correction is on. (`slips` has the root causes.)
        if env["SLIPS"] != "0" {
            let t0 = Date()
            let words = slipItems("words"), sents = slipItems("sentences")
            func put(_ name: String, _ r: SlipCount, other: Bool) {
                metrics["slip.\(name).legal.top1"] = r.pct(r.legal1, r.legal)
                metrics["slip.\(name).legal.top3"] = r.pct(r.legal3, r.legal)
                if other { metrics["slip.\(name).other.top1"] = r.pct(r.other1, r.other) }
                print(String(format: "== slips %@: legal n=%d top1 %.1f%% top3 %.1f%% | other n=%d top1 %.1f%%", name, r.legal,
                             r.pct(r.legal1, r.legal), r.pct(r.legal3, r.legal), r.other, r.pct(r.other1, r.other)))
            }
            put("words", countSlips(words, depth: "quarter", split: false, diagnose: false), other: true)
            put("sent", countSlips(sents, depth: "quarter", split: false, diagnose: false), other: true)
            // the key's edge and centre: 小鹤 (全拼 in `slips`: its words take 2 ms each, the gate would double)
            if decoder.scheme == .xiaohe {
                put("words.edge", countSlips(words, depth: "edge", split: false, diagnose: false), other: false)
                put("words.centre", countSlips(words, depth: "centre", split: false, diagnose: false), other: false)
            }
            let rk = rareKept()
            metrics["rare.kept"] = 100 * Double(rk.kept) / Double(max(rk.n, 1))
            print(String(format: "== rare words typed on purpose kept first: %.2f%% (%d of %d) %@ | slips %.0f s", metrics["rare.kept"]!, rk.kept, rk.n,
                         rk.examples.joined(separator: " "), Date().timeIntervalSince(t0)))
        }
        // Records (R2: measured and reported, not floors): R1 现场错例 with centre-of-key taps and the old exact reading,
        // two keys wrong in a sentence, 小鹤 one key left out
        if decoder.scheme == .quanpin {
            let r = r1Typos(env["TYPOS"] ?? "EngineCLI/r1_typos.tsv", debug: env["TYPO_DEBUG"] != nil)
            print("RECORD r1.top1 \(r.top1)/\(r.total)  r1.top3 \(r.top3)/\(r.total)  r1.exact.top1 \(r.exact1)/\(r.total)  r1.exact.top3 \(r.exact3)/\(r.total)")
        }
        for k in ["two.sentences.top1", "two.sentences.top3"] + (decoder.scheme == .xiaohe ? ["missing.sentences.top1"] : []) {
            print(String(format: "RECORD %@ %.2f", k, metrics[k] ?? .nan))
        }
        for (k, v, atLeast) in floors {
            if env["SLIPS"] == "0", k.hasPrefix("slip.") || k == "rare.kept" { continue }
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
