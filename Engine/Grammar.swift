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

    /// The model's own count for a whole string of up to four characters, as ln(count) (nil when it never saw it).
    public func logCount(_ text: [Character]) -> Double? {
        guard !text.isEmpty, text.count <= 4 else { return nil }
        let enc = Grammar.encode(text[...])
        var out: [(Int, Int)] = []
        prefixes(from: 0, enc, into: &out)
        guard let hit = out.last, hit.0 == enc.count else { return nil }
        return Double(hit.1) / 10_000
    }

    /// What tends to come next after `context` (its last one to three characters): the characters, and two-character
    /// continuations, the model has seen right after it, most frequent first — 联想 after a commit.
    /// Each with ln(count of context + continuation).
    /// Per character of context: a longer context the model knows outranks a shorter one (strict backoff measured best)
    public var contextBonus = 10.0
    public var continuationStop = 2
    public func continuations(after context: [Character], limit: Int = 12) -> [(text: String, score: Double)] {
        var out: [String: Double] = [:]
        // longest context first: a three-character context that the model knows says more than its last character
        for n in stride(from: min(3, context.count), through: 1, by: -1) {
            guard let node = traverse(Grammar.encode(context.suffix(n))[...]) else { continue }
            // the commonest first characters only are followed a level further: each costs a scan of its node
            // (a context like 的 has thousands of continuations — all of them took seconds)
            let firsts = children(of: node).sorted { ($0.2 ?? -1) > ($1.2 ?? -1) }
            for (rank, (bytes1, node1, v1)) in firsts.enumerated() {
                let c1 = Grammar.decode(bytes1)
                guard let ch1 = c1, Grammar.isHan(ch1) else { continue }
                if let v1 { out[String(ch1)] = max(out[String(ch1)] ?? -.infinity, Double(v1) / 10_000 + Double(n) * contextBonus) }
                // two characters only after a context of one or two (the model holds four characters at most)
                guard n <= 2, rank < 24 else { continue }
                for (bytes2, _, v2) in children(of: node1) {
                    guard let v2, let ch2 = Grammar.decode(bytes2), Grammar.isHan(ch2) else { continue }
                    let t = String([ch1, ch2])
                    out[t] = max(out[t] ?? -.infinity, Double(v2) / 10_000 + Double(n) * contextBonus)
                }
            }
            if out.count >= limit * continuationStop { break }
        }
        return out.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// The nodes one character below `node`: (its bytes, the node, the count stored there if a key ends there).
    private func children(of node: Int) -> [([UInt8], Int, Int?)] {
        var out: [([UInt8], Int, Int?)] = []
        // CJK characters are two bytes: a lead byte 0x80…0xDF (or the 0xE1 escape), then any byte
        for b1 in 0x80...0xE1 {
            guard let n1 = child(node, UInt8(b1)) else { continue }
            for b2 in 0...255 {
                guard let n2 = child(n1, UInt8(b2)) else { continue }
                out.append(([UInt8(b1), UInt8(b2)], n2, leafValue(n2)))
            }
        }
        return out
    }

    @inline(__always) private func child(_ node: Int, _ c: UInt8) -> Int? {
        let id = node ^ offset(unit(node)) ^ Int(c)
        return label(unit(id)) == UInt32(c) ? id : nil
    }

    @inline(__always) private func leafValue(_ node: Int) -> Int? {
        let u = unit(node)
        guard hasLeaf(u) else { return nil }
        return Int(unit(node ^ offset(u)) & 0x7FFF_FFFF)
    }

    static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.first.map { (0x3400...0x9FFF).contains($0.value) } ?? false
    }

    /// One two-byte CJK character back from Rime's encoding.
    static func decode(_ b: [UInt8]) -> Character? {
        guard b.count == 2 else { return nil }
        let v: UInt32 = b[0] == 0xE1 ? (UInt32(b[1]) - 0x40) << 8 : (UInt32(b[0]) - 0x40) << 8 | UInt32(b[1])
        return Unicode.Scalar(v).map(Character.init)
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

    /// ln of everything the model counts right after a context node (its one-character continuations): what
    /// a joint count is divided by to read it as "how likely after this context". Cached per node.
    private var massCache: [Int: Double] = [:]
    /// New contexts measured per decode at most (each is a scan of its node; right after launch none are cached,
    /// and measuring them all held the first decodes up to a quarter second): the rest count as average.
    public var massBudget = 24
    private var massSpent = 0
    public func resetMassBudget() { massSpent = 0 }
    func logMass(_ node: Int) -> Double {
        if let m = massCache[node] { return m }
        guard massSpent < massBudget else { return massCenter }
        massSpent += 1
        var vals: [Double] = []
        for (_, _, v) in children(of: node) { if let v { vals.append(Double(v) / 10_000) } }
        let top = vals.max() ?? 0
        let m = vals.isEmpty ? 0 : top + log(vals.reduce(0) { $0 + exp($1 - top) })
        if massCache.count > 4096 { massCache.removeAll(keepingCapacity: true) }
        massCache[node] = m
        return m
    }
    public var massWeight = 0.0
    public var massCenter = 15.0

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
                    var sc = Double(v) / 10_000 + (strong ? collocationPenalty : weakCollocationPenalty)
                    if massWeight > 0 { sc -= massWeight * (logMass(node) - massCenter) }
                    best = max(best, sc)
                }
            }
            c = ctx.index(after: c)
        }
        return best
    }
}
