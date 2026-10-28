import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Which words go together: the language model of Rime's octagram plugin (lotem/rime-octagram-data, LGPL-3.0), read
/// in place from its .gram file — a double-array trie (darts-clone) over character n-grams of up to four characters,
/// each with ln(count) × 10 000. A word is scored against the up to three characters before it (Rime's rules: a
/// collocation of three or more characters, or the whole query, counts in full; a shorter one weakly; none at all
/// costs the same as Rime's "non-collocation" penalty), so 收货 + 地址 beats 收获 + 地址 and 再 + 想想 beats 在 + 想想
/// only when the counts say so.
public final class Grammar {
    public enum LoadError: Error { case open, map, format }
    private let base: UnsafeRawPointer
    private let length: Int
    private let array: UnsafePointer<UInt32>
    private let size: Int

    public var collocationPenalty = -12.0
    public var nonCollocationPenalty = -12.0
    public var weakCollocationPenalty = -24.0
    public var collocationMinLength = 3

    public init(path: String) throws {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw LoadError.open }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw LoadError.open }
        let fsize = Int(st.st_size)
        guard fsize > 64, let p = mmap(nil, fsize, PROT_READ, MAP_PRIVATE, fd, 0),
              p != UnsafeMutableRawPointer(bitPattern: -1) else { throw LoadError.map }
        let b = UnsafeRawPointer(p)
        // Metadata: format char[32] ("Rime::Grammar/…"), checksum u32, array size u32, offset i32 (from its own address)
        let magic = String(decoding: UnsafeRawBufferPointer(start: b, count: 14), as: UTF8.self)
        let n = Int(b.loadUnaligned(fromByteOffset: 36, as: UInt32.self))
        let off = Int(b.loadUnaligned(fromByteOffset: 40, as: Int32.self))
        guard magic == "Rime::Grammar/", 40 + off + n * 4 <= fsize, (40 + off) % 4 == 0 else {
            munmap(p, fsize); throw LoadError.format
        }
        base = b
        length = fsize
        array = (b + 40 + off).assumingMemoryBound(to: UInt32.self)
        size = n
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: base), length) }

    // darts-clone units
    @inline(__always) private func unit(_ i: Int) -> UInt32 { i < size ? array[i] : 0 }
    @inline(__always) private func offset(_ u: UInt32) -> Int { Int((u >> 10) << ((u & (1 << 9)) >> 6)) }
    @inline(__always) private func label(_ u: UInt32) -> UInt32 { u & ((1 << 31) | 0xFF) }
    @inline(__always) private func hasLeaf(_ u: UInt32) -> Bool { (u >> 8) & 1 == 1 }

    /// The node reached by `key` from the root, or nil.
    private func traverse(_ key: ArraySlice<UInt8>) -> Int? {
        var id = 0
        var u = unit(0)
        for c in key {
            id ^= offset(u) ^ Int(c)
            u = unit(id)
            if label(u) != UInt32(c) { return nil }
        }
        return id
    }

    /// Keys continuing from `node` that are prefixes of `key`: (bytes matched, value).
    private func prefixes(from node: Int, _ key: [UInt8], into out: inout [(Int, Int)]) {
        var u = unit(node)
        var id = node ^ offset(u)
        for (k, c) in key.enumerated() {
            id ^= Int(c)
            u = unit(id)
            if label(u) != UInt32(c) { return }
            id ^= offset(u)
            if hasLeaf(u) { out.append((k + 1, Int(unit(id) & 0x7FFF_FFFF))) }
        }
    }

    /// Rime's encoding of characters: CJK in two bytes, ASCII in one, anything else in a short escape.
    static func encode(_ chars: ArraySlice<Character>) -> [UInt8] {
        var out: [UInt8] = []
        for ch in chars {
            for s in ch.unicodeScalars {
                var u = s.value
                if u < 0x80 {
                    out.append(u == 0 ? 0xE0 : UInt8(u))
                } else if u >= 0x4000 && u < 0xA000 {
                    if u & 0xFF == 0 { out.append(0xE1); out.append(UInt8((u >> 8) + 0x40)) }
                    else { out.append(UInt8((u >> 8) + 0x40)); out.append(UInt8(u & 0xFF)) }
                } else {
                    var bits = 32
                    while bits > 0 && (u & 0xFE00_0000) == 0 { bits -= 7; u <<= 7 }
                    var n = (bits + 6) / 7
                    out.append(UInt8(0xE0 | n))
                    while n > 0 { n -= 1; out.append(UInt8(((u >> 25) & 0x7F) | 0x80)); u <<= 7 }
                }
            }
        }
        return out
    }

    /// Length in characters of the first `bytes` bytes of an encoded string.
    private static func chars(_ enc: [UInt8], _ bytes: Int) -> Int {
        var i = 0, n = 0
        while i < bytes && i < enc.count {
            let b = enc[i]
            i += b & 0x80 == 0 ? 1 : (b & 0xF0 == 0xE0 ? Int(b & 0x0F) + 1 : 2)
            n += 1
        }
        return n
    }

    /// How well `word` follows `context` (the text before it): Rime's octagram score, in natural-log units.
    public func query(context: [Character], word: [Character]) -> Double {
        guard !context.isEmpty, !word.isEmpty else { return nonCollocationPenalty }
        let n = 3
        let ctx = context.suffix(n)
        let w = Grammar.encode(word.prefix(n))
        var best = nonCollocationPenalty
        var matches: [(Int, Int)] = []
        var c = ctx.startIndex
        while c < ctx.endIndex {
            let ctxLen = ctx.endIndex - c
            let full = c == ctx.startIndex
            if let node = traverse(Grammar.encode(ctx[c...])[...]) {
                matches.removeAll(keepingCapacity: true)
                prefixes(from: node, w, into: &matches)
                for (bytes, v) in matches {
                    let collocation = ctxLen + Grammar.chars(w, bytes)
                    let strong = collocation >= collocationMinLength || (full && bytes == w.count)
                    best = max(best, Double(v) / 10_000 + (strong ? collocationPenalty : weakCollocationPenalty))
                }
            }
            c = ctx.index(after: c)
        }
        return best
    }
}
