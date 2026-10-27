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
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var list: [Word] = []
        list.reserveCapacity(40000)
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 3, let z = Double(f[1]) else { continue }
            list.append(Word(key: String(f[0]), display: String(f[2]), zipf: z))
        }
        words = list.sorted { $0.key < $1.key }
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
