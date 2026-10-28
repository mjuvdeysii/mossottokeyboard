import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// English words: for 中英混输 in Chinese mode ("ok" → OK, "ios" → iOS) and for the English keyboard's autocorrect.
/// Read in place from english.bin (Tools/build_english_bin.py), memory-mapped: nothing is parsed or built when the
/// keyboard starts and the pages stay clean (they do not count against the extension's memory limit). The file holds
/// the words sorted by key (lowercase letters) with their frequency (zipf) and how each is written, and their trie.
public final class EnglishLexicon {
    public enum LoadError: Error { case open, map, format }

    public struct Word {
        public let key: String       // lowercase letters, as typed
        public let display: String   // as written: iOS, iPhone, OK, Wi-Fi, or the word itself
        public let zipf: Double
        /// Natural-log probability of the word, comparable with the decoder's ln(freq) scale.
        public var logp: Double { (zipf - 9) * 2.302585 }
    }

    private let base: UnsafeRawPointer
    private let length: Int
    public let count: Int
    let nodeCount: Int
    private let wordsOff = 24
    let nodesOff: Int
    private let textOff: Int

    public init(path: String) throws {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw LoadError.open }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw LoadError.open }
        let size = Int(st.st_size)
        guard size > 24, let p = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0),
              p != UnsafeMutableRawPointer(bitPattern: -1) else { throw LoadError.map }
        let b = UnsafeRawPointer(p)
        func u32(_ o: Int) -> Int { Int(b.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
        guard b.load(fromByteOffset: 0, as: UInt8.self) == UInt8(ascii: "X"),
              b.load(fromByteOffset: 2, as: UInt8.self) == UInt8(ascii: "E") else { munmap(p, size); throw LoadError.format }
        count = u32(8)
        nodeCount = u32(12)
        let textLen = u32(16)
        nodesOff = 24 + count * 20
        textOff = nodesOff + nodeCount * 24
        guard textOff + textLen <= size else { munmap(p, size); throw LoadError.format }
        base = b
        length = size
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: base), length) }

    // MARK: words

    @inline(__always) private func w(_ i: Int) -> Int { wordsOff + i * 20 }
    @inline(__always) public func zipf(_ i: Int) -> Double { base.loadUnaligned(fromByteOffset: w(i) + 12, as: Double.self) }
    @inline(__always) public func logp(_ i: Int) -> Double { (zipf(i) - 9) * 2.302585 }
    private func keyBytes(_ i: Int) -> UnsafeRawBufferPointer {
        let o = Int(base.loadUnaligned(fromByteOffset: w(i), as: UInt32.self))
        return UnsafeRawBufferPointer(start: base + textOff + o, count: Int(base.load(fromByteOffset: w(i) + 8, as: UInt8.self)))
    }
    public func key(_ i: Int) -> String { String(decoding: keyBytes(i), as: UTF8.self) }
    public func display(_ i: Int) -> String {
        let o = Int(base.loadUnaligned(fromByteOffset: w(i) + 4, as: UInt32.self))
        let n = Int(base.load(fromByteOffset: w(i) + 9, as: UInt8.self))
        return String(decoding: UnsafeRawBufferPointer(start: base + textOff + o, count: n), as: UTF8.self)
    }
    public func word(_ i: Int) -> Word { Word(key: key(i), display: display(i), zipf: zipf(i)) }
    /// Every word (tests and benchmarks; the keyboard never lists them all).
    public var words: [Word] { (0..<count).map(word) }

    /// Byte-wise comparison of word i's key with `s` (keys are ASCII).
    private func compare(_ i: Int, _ s: [UInt8]) -> Int {
        let k = keyBytes(i)
        let n = min(k.count, s.count)
        for j in 0..<n where k[j] != s[j] { return k[j] < s[j] ? -1 : 1 }
        return k.count == s.count ? 0 : (k.count < s.count ? -1 : 1)
    }

    private func lowerBound(_ s: [UInt8]) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if compare(mid, s) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    public func exactIndex(_ s: String) -> Int? {
        let b = Array(s.utf8)
        let i = lowerBound(b)
        return i < count && compare(i, b) == 0 ? i : nil
    }

    public func exact(_ s: String) -> Word? { exactIndex(s).map(word) }

    /// The most frequent longer word starting with `prefix` (nil when there is none).
    public func completion(_ prefix: String, limit: Int = 4000) -> Word? {
        let p = Array(prefix.utf8)
        var i = lowerBound(p)
        var best: Int?
        var scanned = 0
        while i < count, scanned < limit {
            let k = keyBytes(i)
            guard k.count >= p.count, zip(k, p).allSatisfy({ $0 == $1 }) else { break }
            if k.count > p.count, best == nil || zipf(i) > zipf(best!) { best = i }
            i += 1
            scanned += 1
        }
        return best.map(word)
    }

    // MARK: trie (node 0 is the root)

    @inline(__always) private func n(_ i: Int) -> Int { nodesOff + i * 24 }
    /// The child of `node` reached by the letter `c`, or nil.
    @inline(__always) func child(_ node: Int, _ c: UInt8) -> Int? {
        let first = Int(base.loadUnaligned(fromByteOffset: n(node), as: UInt32.self))
        let cnt = Int(base.load(fromByteOffset: n(node) + 4, as: UInt8.self))
        for k in 0..<cnt where base.load(fromByteOffset: n(first + k) + 5, as: UInt8.self) == c { return first + k }
        return nil
    }
    @inline(__always) func children(_ node: Int) -> Range<Int> {
        let first = Int(base.loadUnaligned(fromByteOffset: n(node), as: UInt32.self))
        return first..<(first + Int(base.load(fromByteOffset: n(node) + 4, as: UInt8.self)))
    }
    @inline(__always) func nodeWord(_ node: Int) -> Int { Int(base.loadUnaligned(fromByteOffset: n(node) + 8, as: Int32.self)) }
    @inline(__always) func nodeBestWord(_ node: Int) -> Int { Int(base.loadUnaligned(fromByteOffset: n(node) + 12, as: Int32.self)) }
    @inline(__always) func nodeBest(_ node: Int) -> Double {
        nodeBestWord(node) >= 0 ? base.loadUnaligned(fromByteOffset: n(node) + 16, as: Double.self) : -.infinity
    }
}
