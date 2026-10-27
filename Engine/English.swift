import Foundation

/// English words offered while typing in Chinese mode (中英混输): "ok" → OK, "ios" → iOS, "iph" → iPhone.
/// A sorted list of lowercase words with their frequency (zipf: log10 of occurrences per billion words) and the way
/// each is written. Lookups are exact or by prefix (binary search), cheap enough for every keystroke.
public final class EnglishLexicon {
    public struct Word {
        public let key: String       // lowercase letters, as typed
        public let display: String   // as written: iOS, iPhone, OK, Wi-Fi, or the word itself
        public let zipf: Double
        /// Natural-log probability of the word, comparable with the decoder's ln(freq) scale.
        public var logp: Double { (zipf - 9) * 2.302585 }
    }

    public private(set) var words: [Word] = []

    public init(path: String) throws {
        // Parsed from raw UTF-8 bytes (no per-line String splitting): the keyboard loads this on every launch.
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var list: [Word] = []
        list.reserveCapacity(40000)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            var i = 0
            while i < n {
                var f: [Int] = [i]
                var j = i
                while j < n, b[j] != 10 { if b[j] == 9 { f.append(j + 1) }; j += 1 }
                if f.count >= 3 {
                    let key = String(decoding: UnsafeBufferPointer(rebasing: b[f[0]..<(f[1] - 1)]), as: UTF8.self)
                    var z = 0.0, scale = 0.0
                    for k in f[1]..<(f[2] - 1) {
                        let c = b[k]
                        if c == 46 { scale = 1 } else if c >= 48, c <= 57 {
                            if scale > 0 { scale /= 10; z += Double(c - 48) * scale } else { z = z * 10 + Double(c - 48) }
                        }
                    }
                    let shown = String(decoding: UnsafeBufferPointer(rebasing: b[f[2]..<j]), as: UTF8.self)
                    list.append(Word(key: key, display: shown == key ? key : shown, zipf: z))
                }
                i = j + 1
            }
        }
        // the file is written sorted (Tools/build_english.py); sort only if it is not
        if zip(list, list.dropFirst()).contains(where: { $0.key > $1.key }) { list.sort { $0.key < $1.key } }
        words = list
    }

    private func lowerBound(_ s: String) -> Int {
        var lo = 0, hi = words.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if words[mid].key < s { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    public func exact(_ s: String) -> Word? {
        let i = lowerBound(s)
        return i < words.count && words[i].key == s ? words[i] : nil
    }

    /// The most frequent longer word starting with `prefix` (nil when there is none).
    public func completion(_ prefix: String, limit: Int = 4000) -> Word? {
        var i = lowerBound(prefix)
        var best: Word?
        var scanned = 0
        while i < words.count, words[i].key.hasPrefix(prefix), scanned < limit {
            let w = words[i]
            if w.key.count > prefix.count, best == nil || w.zipf > best!.zipf { best = w }
            i += 1
            scanned += 1
        }
        return best
    }
}
