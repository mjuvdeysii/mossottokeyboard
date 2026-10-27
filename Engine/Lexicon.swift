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

        guard size > 24,
              b.load(fromByteOffset: 0, as: UInt8.self) == UInt8(ascii: "X"),
              b.load(fromByteOffset: 3, as: UInt8.self) == UInt8(ascii: "X") else {
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

    /// Entries of one syllable (single characters), per syllable, best first — built on first use.
    private var singlesIndex: [[Int]]?
    public func singles(_ s: UInt16) -> [Int] {
        if singlesIndex == nil { singlesIndex = buildSingles() }
        return singlesIndex![Int(s)]
    }

    private func buildSingles() -> [[Int]] {
        var idx = [[Int]](repeating: [], count: syllables.count)
        for sid in 0..<syllables.count {
            for i in range(firstSyllable: UInt16(sid)) where entry(i).sylCount == 1 { idx[sid].append(i) }
        }
        return idx
    }

    /// The decoder's lookup tables, built in one pass. Only reads the mapped file, so it can run off the main thread
    /// while the keyboard comes up; `install` then hands them over (on the thread that decodes), and the first keys
    /// typed never pay for building them.
    public struct Indexes {
        fileprivate let singles: [[Int]]
        fileprivate let followers: [Followers]
    }
    public func buildIndexes() -> Indexes {
        Indexes(singles: buildSingles(), followers: (0..<syllables.count).map { buildFollowers(UInt16($0)) })
    }
    public func install(_ x: Indexes) {
        singlesIndex = x.singles
        followIndex = x.followers.map { Optional($0) }
    }

    /// Words of two or more syllables starting with `first`, grouped by their second syllable, best first — two-syllable
    /// words and longer ones apart. Built per first syllable on first use, so the decoder visits only words whose
    /// second syllable can actually follow, and can stop at the first two-syllable word that no longer makes the cut
    /// (the 九宫格 lattice has dozens of syllables per position; scanning every word of each was most of the time).
    public struct Followers {
        public var pairs: [UInt16: [Int32]] = [:]
        public var longer: [UInt16: [Int32]] = [:]
    }
    private var followIndex: [Followers?] = []
    public func followers(of s: UInt16) -> Followers {
        if followIndex.isEmpty { followIndex = Array(repeating: nil, count: syllables.count) }
        if let f = followIndex[Int(s)] { return f }
        let f = buildFollowers(s)
        followIndex[Int(s)] = f
        return f
    }

    private func buildFollowers(_ s: UInt16) -> Followers {
        var f = Followers()
        for i in range(firstSyllable: s) {
            let e = entry(i)
            if e.sylCount == 2 { f.pairs[syllable(e, 1), default: []].append(Int32(i)) }
            else if e.sylCount > 2 { f.longer[syllable(e, 1), default: []].append(Int32(i)) }
        }
        return f
    }

    public func id(of syllable: String) -> UInt16? {
        syllables.firstIndex(of: syllable).map { UInt16($0) }
    }
}
