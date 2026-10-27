import Foundation

/// One keystroke as seen by the decoder: the key that was hit plus the
/// probability of every plausible intended key given where the finger landed.
public struct Tap {
    public var key: Character
    /// (key, log probability). Always contains `key`. Sorted best first.
    public var alternatives: [(key: Character, logp: Double)]
    /// Raw touch point in keyboard coordinates (nil for synthetic taps).
    public var x: Double? = nil
    public var y: Double? = nil
    /// A 九宫格 key: `key` is its digit and every letter in `alternatives` is meant equally (nothing is "corrected").
    public var group = false

    /// The 九宫格 keys: 2 abc … 9 wxyz.
    public static let t9Letters: [Character: String] = ["2": "abc", "3": "def", "4": "ghi", "5": "jkl", "6": "mno",
                                                        "7": "pqrs", "8": "tuv", "9": "wxyz"]
    /// A tap on a 九宫格 key ("'" is the 分词 syllable separator).
    public static func t9(_ digit: Character) -> Tap {
        if digit == "'" { return Tap(key: "'", alternatives: []) }
        var t = Tap(key: digit, alternatives: (t9Letters[digit] ?? "").map { ($0, 0.0) })
        t.group = true
        return t
    }
    /// The digit of the 九宫格 key a letter is on.
    public static func t9Digit(_ c: Character) -> Character {
        t9Letters.first { $0.value.contains(c) }?.key ?? c
    }

    public init(key: Character, alternatives: [(key: Character, logp: Double)], x: Double? = nil, y: Double? = nil) {
        self.key = key
        self.alternatives = alternatives
        self.x = x
        self.y = y
    }

    /// A tap with no positional information (hardware keyboard, tests): no correction.
    public static func exact(_ key: Character) -> Tap {
        Tap(key: key, alternatives: [(key, 0)])
    }
}

/// Gaussian touch model over the letter keys (same idea as Gboard's spatial model):
/// P(intended key | touch point) ∝ exp(-(dx²/2σx² + dy²/2σy²)), σ relative to key size.
public final class SpatialModel {
    public struct Key {
        public let char: Character
        public let cx: Double
        public let cy: Double
        public init(char: Character, cx: Double, cy: Double) { self.char = char; self.cx = cx; self.cy = cy }
    }

    public private(set) var keys: [Key]
    public private(set) var keyWidth: Double
    public private(set) var keyHeight: Double
    /// σ as a fraction of key width / row pitch.
    public var sigmaX: Double = 0.34
    public var sigmaY: Double = 0.31
    /// Learned personal touch offset (fraction of key size); the finger tends to land
    /// consistently off-centre, so the model shifts its key centres to match.
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    /// Learned offset of each key on top of the overall one (fraction of key size): a thumb reaches the keys at the
    /// edges and the top row differently from those under it, so each key's centre moves where this user hits it.
    public var keyOffsets: [Character: (x: Double, y: Double)] = [:]
    /// Alternatives below this probability are dropped.
    public var minProbability: Double = 0.015
    public var maxAlternatives = 4

    public init(keys: [Key], keyWidth: Double, keyHeight: Double) {
        self.keys = keys
        self.keyWidth = keyWidth
        self.keyHeight = keyHeight
    }

    public func update(keys: [Key], keyWidth: Double, keyHeight: Double) {
        self.keys = keys
        self.keyWidth = keyWidth
        self.keyHeight = keyHeight
    }

    /// Key centre lookup.
    public func center(of c: Character) -> (Double, Double)? {
        keys.first { $0.char == c }.map { ($0.cx, $0.cy) }
    }

    /// Nearest key to a point (what a plain keyboard would type).
    public func nearestKey(x: Double, y: Double) -> Character {
        var best = keys[0].char
        var bestD = Double.infinity
        for k in keys {
            let dx = (x - k.cx) / keyWidth, dy = (y - k.cy) / keyHeight
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = k.char }
        }
        return best
    }

    public func tap(x: Double, y: Double, hitKey: Character? = nil) -> Tap {
        let sx = sigmaX * keyWidth, sy = sigmaY * keyHeight
        let px = x - offsetX * keyWidth, py = y - offsetY * keyHeight
        var logits: [(Character, Double)] = []
        logits.reserveCapacity(keys.count)
        var maxL = -Double.infinity
        for k in keys {
            let ko = keyOffsets[k.char] ?? (0, 0)
            let dx = (px - k.cx - ko.x * keyWidth) / sx, dy = (py - k.cy - ko.y * keyHeight) / sy
            let l = -0.5 * (dx * dx + dy * dy)
            logits.append((k.char, l))
            maxL = max(maxL, l)
        }
        var sum = 0.0
        for (_, l) in logits { sum += exp(l - maxL) }
        let lse = maxL + log(sum)
        // The key typed: the one under the finger — unless what this user's touches have taught says clearly
        // (over 60 %) that a touch here means a neighbouring key (adaptive hit areas, as Gboard).
        var literal = hitKey ?? nearestKey(x: x, y: y)
        // Never for a touch near the middle of the key under the finger: learning can shift the edges, not the key.
        if adaptiveHits, let best = logits.max(by: { $0.1 < $1.1 }), best.0 != literal, exp(best.1 - lse) > 0.6,
           let hit = center(of: literal), abs(x - hit.0) > 0.2 * keyWidth || abs(y - hit.1) > 0.2 * keyHeight {
            literal = best.0
        }
        let floor = log(minProbability)
        var alts = logits.map { ($0.0, $0.1 - lse) }
            .filter { $0.1 >= floor || $0.0 == literal }
            .sorted { $0.1 > $1.1 }
        if alts.count > maxAlternatives {
            let keep = Array(alts.prefix(maxAlternatives))
            alts = keep.contains { $0.0 == literal } ? keep : keep.dropLast() + alts.filter { $0.0 == literal }
        }
        return Tap(key: literal, alternatives: alts.map { (key: $0.0, logp: $0.1) }, x: x, y: y)
    }

    /// Update the personal offset from a committed tap whose intended key is now known.
    public func observe(tap: Tap, intended: Character, rate: Double = 0.03) {
        guard let x = tap.x, let y = tap.y, let c = center(of: intended) else { return }
        let rx = (x - c.0) / keyWidth, ry = (y - c.1) / keyHeight
        guard abs(rx) < 0.8, abs(ry) < 0.8 else { return }   // ignore outliers
        offsetX = min(0.3, max(-0.3, offsetX * (1 - rate) + rx * rate))
        offsetY = min(0.3, max(-0.3, offsetY * (1 - rate) + ry * rate))
        // what is left after the overall offset belongs to this key (learned more slowly per key: fewer samples)
        let ko = keyOffsets[intended] ?? (0, 0)
        let kr = rate * keyRate
        keyOffsets[intended] = (min(0.35, max(-0.35, ko.x * (1 - kr) + (rx - offsetX) * kr)),
                                min(0.35, max(-0.35, ko.y * (1 - kr) + (ry - offsetY) * kr)))
    }
    /// Let learned offsets move which key a touch types (see tap).
    public var adaptiveHits = true
    /// Per-key learning speed relative to the overall offset's.
    public var keyRate = 2.0

    /// Per-key offsets as plain numbers, to store and restore.
    public var keyOffsetsList: [String: [Double]] {
        get { Dictionary(uniqueKeysWithValues: keyOffsets.map { (String($0.key), [$0.value.x, $0.value.y]) }) }
        set {
            keyOffsets = [:]
            for (k, v) in newValue where v.count == 2 {
                if let c = k.first { keyOffsets[c] = (min(0.35, max(-0.35, v[0])), min(0.35, max(-0.35, v[1]))) }
            }
        }
    }

    /// Standard iPhone portrait QWERTY geometry in points (used by tests / CLI).
    public static func standard(width: Double = 390) -> SpatialModel {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        let kw = width / 10
        let rowPitch = 54.0
        var keys: [Key] = []
        for (r, row) in rows.enumerated() {
            let offset: Double = r == 0 ? 0 : (r == 1 ? 0.5 : 1.5)
            for (i, c) in row.enumerated() {
                keys.append(Key(char: c, cx: (Double(i) + offset + 0.5) * kw, cy: (Double(r) + 0.5) * rowPitch))
            }
        }
        return SpatialModel(keys: keys, keyWidth: kw, keyHeight: rowPitch)
    }
}
