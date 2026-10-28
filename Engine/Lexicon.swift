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
    /// Version 3 trailer: the follower table (see followers).
    private let pairStartsOff: Int
    private let pairsOff: Int

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

        // version 3: entries sorted by first syllable, second syllable, length, score, plus the follower table
        guard size > 24,
              b.load(fromByteOffset: 0, as: UInt8.self) == UInt8(ascii: "X"),
              b.load(fromByteOffset: 3, as: UInt8.self) == UInt8(ascii: "X"),
              b.loadUnaligned(fromByteOffset: 4, as: UInt32.self) >= 3,
              b.load(fromByteOffset: size - 4, as: UInt8.self) == UInt8(ascii: "P") else {
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
        let pairCount = u32(size - 8)
        pairsOff = size - 8 - pairCount * 16
        pairStartsOff = pairsOff - sylCount * 8
        guard textOff + textLen <= pairStartsOff else { munmap(p, size); throw LoadError.format }

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

    /// Single characters of a syllable, best first: the start of its run, up to where its first follower's words begin
    /// (from the follower table — no entries are read to find it).
    private var singlesCache: [[Int]?] = []
    public func singles(_ s: UInt16) -> [Int] {
        if singlesCache.isEmpty { singlesCache = Array(repeating: nil, count: syllables.count) }
        if let c = singlesCache[Int(s)] { return c }
        let r = range(firstSyllable: s)
        let (start, count) = pairBlock(s)
        let end = count > 0 ? Int(base.loadUnaligned(fromByteOffset: pairsOff + start * 16 + 4, as: UInt32.self)) : r.upperBound
        let out = Array(r.lowerBound..<max(r.lowerBound, min(end, r.upperBound)))
        singlesCache[Int(s)] = out
        return out
    }

    @inline(__always) private func pairBlock(_ first: UInt16) -> (start: Int, count: Int) {
        let o = pairStartsOff + Int(first) * 8
        return (Int(base.loadUnaligned(fromByteOffset: o, as: UInt32.self)),
                Int(base.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self)))
    }

    /// The words that start with syllables `first`, `second`: the two-syllable ones, then the longer ones, each best
    /// first — one run in the file, located through the follower table: a binary search over one syllable's small
    /// block (a page or two), never over the half-million-entry table, so a cold start does not page through the file.
    public func followers(first: UInt16, second: UInt16) -> (pairs: Range<Int>, longer: Range<Int>) {
        let (start, count) = pairBlock(first)
        var lo = 0, hi = count
        while lo < hi {
            let m = (lo + hi) >> 1
            if base.loadUnaligned(fromByteOffset: pairsOff + (start + m) * 16, as: UInt16.self) < second { lo = m + 1 } else { hi = m }
        }
        var a = 0, b = 0, c = 0
        if lo < count {
            let o = pairsOff + (start + lo) * 16
            if base.loadUnaligned(fromByteOffset: o, as: UInt16.self) == second {
                a = Int(base.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self))
                b = Int(base.loadUnaligned(fromByteOffset: o + 8, as: UInt32.self))
                c = Int(base.loadUnaligned(fromByteOffset: o + 12, as: UInt32.self))
            }
        }
        return (a..<b, b..<c)
    }

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
