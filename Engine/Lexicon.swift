import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Read-only, memory-mapped lexicon produced by Tools/build_lexicon.py.
/// The file is mmapped so its pages stay clean and do not count toward the
/// keyboard extension's memory limit.
public final class Lexicon {
    public enum LoadError: Error { case open, map, format }

    public let syllables: [String]
    /// 2-key Xiaohe code -> syllable ids (e.g. "hc" -> [hao]).
    public let codeToSyllables: [String: [UInt16]]
    /// First key -> syllable ids whose code starts with it (for a dangling single tap).
    public let firstKeyToSyllables: [Character: [UInt16]]
    public let entryCount: Int

    private let base: UnsafeRawPointer
    private let length: Int
    private let indexOff: Int
    private let entriesOff: Int
    private let sylBlobOff: Int
    private let textOff: Int

    public struct Entry {
        public let textOffset: Int
        public let sylOffset: Int
        public let score: Int16
        public let textLength: Int
        public let sylCount: Int
    }

    public init(path: String) throws {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw LoadError.open }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw LoadError.open }
        let size = Int(st.st_size)
        guard let p = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0),
              p != UnsafeMutableRawPointer(bitPattern: -1) else { throw LoadError.map }
        let b = UnsafeRawPointer(p)
        base = b
        length = size

        // version 2: entries sorted by first syllable, second syllable, length, score (see followers)
        guard size > 24,
              b.load(fromByteOffset: 0, as: UInt8.self) == UInt8(ascii: "X"),
              b.load(fromByteOffset: 3, as: UInt8.self) == UInt8(ascii: "X"),
              b.loadUnaligned(fromByteOffset: 4, as: UInt32.self) >= 2 else {
            munmap(p, size)
            throw LoadError.format
        }
        func u32(_ o: Int) -> Int { Int(UInt32(littleEndian: b.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }
        let sylCount = u32(8)
        entryCount = u32(12)
        let sylBlobCount = u32(16)
        let textLen = u32(20)

        var names: [String] = []
        names.reserveCapacity(sylCount)
        var o = 24
        for _ in 0..<sylCount {
            var bytes: [UInt8] = []
            for k in 0..<8 {
                let ch = b.load(fromByteOffset: o + k, as: UInt8.self)
                if ch == 0 { break }
                bytes.append(ch)
            }
            names.append(String(decoding: bytes, as: UTF8.self))
            o += 8
        }
        syllables = names
        indexOff = o
        entriesOff = indexOff + sylCount * 8
        sylBlobOff = entriesOff + entryCount * 12
        textOff = sylBlobOff + sylBlobCount * 2
        guard textOff + textLen <= size else { munmap(p, size); throw LoadError.format }

        var c2s: [String: [UInt16]] = [:]
        var f2s: [Character: [UInt16]] = [:]
        for (i, s) in names.enumerated() {
            guard let code = XiaoheScheme.code(for: s) else { continue }
            c2s[code, default: []].append(UInt16(i))
            f2s[code.first!, default: []].append(UInt16(i))
        }
        codeToSyllables = c2s
        firstKeyToSyllables = f2s
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: base), length) }

    @inline(__always) public func range(firstSyllable s: UInt16) -> Range<Int> {
        let o = indexOff + Int(s) * 8
        let a = Int(base.loadUnaligned(fromByteOffset: o, as: UInt32.self))
        let b = Int(base.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self))
        return a..<max(a, b)
    }

    @inline(__always) public func entry(_ i: Int) -> Entry {
        let o = entriesOff + i * 12
        return Entry(
            textOffset: Int(base.loadUnaligned(fromByteOffset: o, as: UInt32.self)),
            sylOffset: Int(base.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self)),
            score: base.loadUnaligned(fromByteOffset: o + 8, as: Int16.self),
            textLength: Int(base.load(fromByteOffset: o + 10, as: UInt8.self)),
            sylCount: Int(base.load(fromByteOffset: o + 11, as: UInt8.self)))
    }

    @inline(__always) public func syllable(_ e: Entry, _ k: Int) -> UInt16 {
        base.loadUnaligned(fromByteOffset: sylBlobOff + (e.sylOffset + k) * 2, as: UInt16.self)
    }

    public func text(_ e: Entry) -> String {
        String(decoding: UnsafeRawBufferPointer(start: base + textOff + e.textOffset, count: e.textLength), as: UTF8.self)
    }

    public func syllableIDs(_ e: Entry) -> [UInt16] { (0..<e.sylCount).map { syllable(e, $0) } }

    /// Single characters of a syllable, best first: the start of its run (the file sorts them first). Cached per
    /// syllable on first use — a few entries each.
    private var singlesCache: [[Int]?] = []
    public func singles(_ s: UInt16) -> [Int] {
        if singlesCache.isEmpty { singlesCache = Array(repeating: nil, count: syllables.count) }
        if let c = singlesCache[Int(s)] { return c }
        var out: [Int] = []
        for i in range(firstSyllable: s) {
            guard entry(i).sylCount == 1 else { break }
            out.append(i)
        }
        singlesCache[Int(s)] = out
        return out
    }

    /// The words that start with syllables `first`, `second`: the two-syllable ones, then the longer ones, each best
    /// first. They are one run in the file (sorted by first syllable, second syllable, length, score), found by binary
    /// search — so the decoder visits only words whose second syllable can actually follow, can stop at the first
    /// two-syllable word that no longer makes the cut, and keeps no index in memory.
    public func followers(first: UInt16, second: UInt16) -> (pairs: Range<Int>, longer: Range<Int>) {
        let r = range(firstSyllable: first)
        @inline(__always) func key(_ i: Int) -> Int {
            let e = entry(i)
            return e.sylCount == 1 ? -1 : Int(syllable(e, 1)) * 2 + (e.sylCount > 2 ? 1 : 0)
        }
        func lower(_ k: Int) -> Int {
            var lo = r.lowerBound, hi = r.upperBound
            while lo < hi {
                let m = (lo + hi) >> 1
                if key(m) < k { lo = m + 1 } else { hi = m }
            }
            return lo
        }
        // remembered per pair of syllables (a 2 MB table, filled as pairs come up): the decoder asks about the same
        // pairs on every key
        let S = syllables.count
        if pairCache.isEmpty { pairCache = [Int32](repeating: -1, count: S * S * 3) }
        let slot = (Int(first) * S + Int(second)) * 3
        if pairCache[slot] >= 0 {
            let a = Int(pairCache[slot]), b = Int(pairCache[slot + 1]), c = Int(pairCache[slot + 2])
            return (a..<b, b..<c)
        }
        let k = Int(second) * 2
        let a = lower(k), b = lower(k + 1), c = lower(k + 2)
        pairCache[slot] = Int32(a); pairCache[slot + 1] = Int32(b); pairCache[slot + 2] = Int32(c)
        return (a..<b, b..<c)
    }
    private var pairCache: [Int32] = []

    /// The lexicon's own score for this word (text and syllables), if it has it.
    public func score(of ids: [UInt16], text: String) -> Int16? {
        guard let f = ids.first else { return nil }
        let candidates: [Int]
        if ids.count == 1 {
            candidates = singles(f)
        } else {
            let r = followers(first: f, second: ids[1])
            candidates = Array(ids.count == 2 ? r.pairs : r.longer)
        }
        for i in candidates {
            let e = entry(i)
            if e.sylCount == ids.count, self.text(e) == text, syllableIDs(e) == ids { return e.score }
        }
        return nil
    }

    public func id(of syllable: String) -> UInt16? {
        syllables.firstIndex(of: syllable).map { UInt16($0) }
    }
}
