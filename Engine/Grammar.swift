import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Language model read in place from a memory-mapped `.gram` file — supporting both the R101 compact 8-bit quantized
/// dual-section `Mosto::GramV2` format and legacy `Rime::Grammar/` double-array tries. Each n-gram up
/// to four characters stores `ln(count)`. A word is scored against up to three preceding characters (collocations of
/// three or more characters, or the full query, count in full; shorter ones weakly; missing ones pay `nonCollocationPenalty`).
public final class Grammar {
    public enum LoadError: Error { case open, map, format }

    private static let bmpMin: UInt32 = 0x3400
    private static let bmpMax: UInt32 = 0x9FFF
    private static let bmpRange: Int = 27_648

    /// Compact 8-bit quantized 4-level CSR-Trie section (`Mosto::GramV2`).
    private struct V2Section {
        let sectionBytes: Int
        let vocabSize: Int
        let n2: Int
        let n3: Int
        let n4: Int
        let ovf3Count: Int
        let ovf4Count: Int
        let min2: Double
        let step2: Double
        let max3: Double
        let max4: Double

        let bmpToID: UnsafePointer<UInt16>
        let idToBmp: UnsafePointer<UInt16>
        let l1L2Start: UnsafePointer<UInt32>
        let l1LogMass: UnsafePointer<Float>
        let l2ID13: UnsafeRawPointer
        let l2Val: UnsafePointer<UInt8>
        let l2Deg3: UnsafePointer<UInt8>
        let l2Blk3: UnsafePointer<UInt32>
        let l2Ovf3: UnsafePointer<UInt32> // packed pairs: (idx: UInt32, deg: UInt32)
        let l2Deg4: UnsafePointer<UInt8>
        let l2Blk4: UnsafePointer<UInt32>
        let l2Ovf4: UnsafePointer<UInt32>
        let l3ID13: UnsafeRawPointer
        let l3Val: UnsafePointer<UInt8>
        let l4Key26: UnsafeRawPointer
        let l4Val: UnsafePointer<UInt8>

        let val2: [Double]
        let val3: [Double]
        let val4: [Double]
        let exp3: [Double]
        let exp4: [Double]

        static func parse(base: UnsafeRawPointer, offset: Int, fileSize: Int) -> V2Section? {
            guard offset + 144 <= fileSize else { return nil }
            let s = base + offset
            let magic = String(decoding: UnsafeRawBufferPointer(start: s, count: 14), as: UTF8.self)
            guard magic == "Mosto::GramV2\0" else { return nil }
            let ver = UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 16, as: UInt32.self))
            let secBytes = Int(UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 20, as: UInt32.self)))
            guard ver == 2, secBytes >= 144, secBytes % 8 == 0, offset + secBytes <= fileSize else { return nil }

            let vocabSize = Int(UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 24, as: UInt32.self)))
            let n2 = Int(UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 28, as: UInt32.self)))
            let n3 = Int(UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 32, as: UInt32.self)))
            let n4 = Int(UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 36, as: UInt32.self)))
            let ovf3Count = Int(UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 40, as: UInt32.self)))
            let ovf4Count = Int(UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 44, as: UInt32.self)))
            guard vocabSize > 0, vocabSize <= 8192, n2 >= 0, n3 >= 0, n4 >= 0 else { return nil }

            @inline(__always) func f32(_ byteOff: Int) -> Double {
                Double(Float(bitPattern: UInt32(littleEndian: s.loadUnaligned(fromByteOffset: byteOff, as: UInt32.self))))
            }
            let min2 = f32(48), step2 = f32(52)
            let min3 = f32(56), step3 = f32(60)
            let min4 = f32(64), step4 = f32(68)

            var offs = [Int](repeating: 0, count: 16)
            for i in 0..<16 {
                let o = Int(UInt32(littleEndian: s.loadUnaligned(fromByteOffset: 72 + i * 4, as: UInt32.self)))
                guard o >= 144, o <= secBytes, o % 8 == 0 else { return nil }
                offs[i] = o
            }
            // Validate required region sizes stay inside `secBytes`.
            let blkCount = (n2 >> 5) + 1
            let l2BitsBytes = ((n2 * 13 + 7) / 8) + 8
            let l3BitsBytes = ((n3 * 13 + 7) / 8) + 8
            let l4BitsBytes = ((n4 * 26 + 7) / 8) + 8
            guard offs[0] + bmpRange * 2 <= secBytes,
                  offs[1] + vocabSize * 2 <= secBytes,
                  offs[2] + (vocabSize + 1) * 4 <= secBytes,
                  offs[3] + vocabSize * 4 <= secBytes,
                  offs[4] + l2BitsBytes <= secBytes,
                  offs[5] + n2 <= secBytes,
                  offs[6] + n2 <= secBytes,
                  offs[7] + blkCount * 4 <= secBytes,
                  offs[8] + ovf3Count * 8 <= secBytes,
                  offs[9] + n2 <= secBytes,
                  offs[10] + blkCount * 4 <= secBytes,
                  offs[11] + ovf4Count * 8 <= secBytes,
                  offs[12] + l3BitsBytes <= secBytes,
                  offs[13] + n3 <= secBytes,
                  offs[14] + l4BitsBytes <= secBytes,
                  offs[15] + n4 <= secBytes else { return nil }

            let v2 = (0..<256).map { $0 == 0 ? 0.0 : min2 + Double($0 - 1) * step2 }
            let v3 = (0..<256).map { min3 + Double($0) * step3 }
            let v4 = (0..<256).map { min4 + Double($0) * step4 }
            let max3 = v3[255]
            let max4 = v4[255]
            let e3 = v3.map { exp($0 - max3) }
            let e4 = v4.map { exp($0 - max4) }

            return V2Section(
                sectionBytes: secBytes,
                vocabSize: vocabSize,
                n2: n2, n3: n3, n4: n4,
                ovf3Count: ovf3Count, ovf4Count: ovf4Count,
                min2: min2, step2: step2, max3: max3, max4: max4,
                bmpToID: (s + offs[0]).assumingMemoryBound(to: UInt16.self),
                idToBmp: (s + offs[1]).assumingMemoryBound(to: UInt16.self),
                l1L2Start: (s + offs[2]).assumingMemoryBound(to: UInt32.self),
                l1LogMass: (s + offs[3]).assumingMemoryBound(to: Float.self),
                l2ID13: s + offs[4],
                l2Val: (s + offs[5]).assumingMemoryBound(to: UInt8.self),
                l2Deg3: (s + offs[6]).assumingMemoryBound(to: UInt8.self),
                l2Blk3: (s + offs[7]).assumingMemoryBound(to: UInt32.self),
                l2Ovf3: (s + offs[8]).assumingMemoryBound(to: UInt32.self),
                l2Deg4: (s + offs[9]).assumingMemoryBound(to: UInt8.self),
                l2Blk4: (s + offs[10]).assumingMemoryBound(to: UInt32.self),
                l2Ovf4: (s + offs[11]).assumingMemoryBound(to: UInt32.self),
                l3ID13: s + offs[12],
                l3Val: (s + offs[13]).assumingMemoryBound(to: UInt8.self),
                l4Key26: s + offs[14],
                l4Val: (s + offs[15]).assumingMemoryBound(to: UInt8.self),
                val2: v2, val3: v3, val4: v4, exp3: e3, exp4: e4
            )
        }

        @inline(__always) func charID(_ c: Character) -> Int? {
            guard c.unicodeScalars.count == 1, let v = c.unicodeScalars.first?.value,
                  v >= Grammar.bmpMin, v <= Grammar.bmpMax else { return nil }
            let id = Int(UInt16(littleEndian: bmpToID[Int(v - Grammar.bmpMin)]))
            return id < vocabSize ? id : nil
        }

        @inline(__always) func char(forID id: Int) -> Character {
            let cp = UInt32(UInt16(littleEndian: idToBmp[id]))
            return Character(Unicode.Scalar(cp)!)
        }

        @inline(__always) func read13(_ ptr: UnsafeRawPointer, _ idx: Int) -> UInt16 {
            let bit = idx * 13
            let w = UInt32(littleEndian: ptr.loadUnaligned(fromByteOffset: bit >> 3, as: UInt32.self))
            return UInt16((w >> UInt32(bit & 7)) & 0x1FFF)
        }

        @inline(__always) func read26(_ idx: Int) -> UInt32 {
            let bit = idx * 26
            let w = UInt64(littleEndian: l4Key26.loadUnaligned(fromByteOffset: bit >> 3, as: UInt64.self))
            return UInt32((w >> UInt64(bit & 7)) & 0x03FF_FFFF)
        }

        @inline(__always) func l2Range(id0: Int) -> Range<Int> {
            let s = Int(UInt32(littleEndian: l1L2Start[id0]))
            let e = Int(UInt32(littleEndian: l1L2Start[id0 + 1]))
            return s..<e
        }

        func findID13(_ ptr: UnsafeRawPointer, _ lo0: Int, _ hi0: Int, _ target: UInt16) -> Int? {
            var lo = lo0, hi = hi0
            while lo < hi {
                let mid = lo + ((hi - lo) >> 1)
                let v = read13(ptr, mid)
                if v < target { lo = mid + 1 }
                else if v > target { hi = mid }
                else { return mid }
            }
            return nil
        }

        func lowerBound26(_ lo0: Int, _ hi0: Int, _ target: UInt32) -> Int {
            var lo = lo0, hi = hi0
            while lo < hi {
                let mid = lo + ((hi - lo) >> 1)
                if read26(mid) < target { lo = mid + 1 }
                else { hi = mid }
            }
            return lo
        }

        func findKey26(_ lo0: Int, _ hi0: Int, _ target: UInt32) -> Int? {
            let pos = lowerBound26(lo0, hi0, target)
            return pos < hi0 && read26(pos) == target ? pos : nil
        }

        @inline(__always) private func degree(_ l2Idx: Int, degPtr: UnsafePointer<UInt8>,
                                             ovfPtr: UnsafePointer<UInt32>, ovfCount: Int) -> Int {
            let d = degPtr[l2Idx]
            if d < 255 { return Int(d) }
            var lo = 0, hi = ovfCount
            let target = UInt32(l2Idx)
            while lo < hi {
                let mid = lo + ((hi - lo) >> 1)
                let k = UInt32(littleEndian: ovfPtr[mid * 2])
                if k < target { lo = mid + 1 } else { hi = mid }
            }
            return (lo < ovfCount && UInt32(littleEndian: ovfPtr[lo * 2]) == target)
                ? Int(UInt32(littleEndian: ovfPtr[lo * 2 + 1])) : 0
        }

        @inline(__always) private func childRange(_ l2Idx: Int, degPtr: UnsafePointer<UInt8>, blkPtr: UnsafePointer<UInt32>,
                                                 ovfPtr: UnsafePointer<UInt32>, ovfCount: Int) -> Range<Int> {
            let b = l2Idx >> 5
            var s = Int(UInt32(littleEndian: blkPtr[b]))
            var k = b << 5
            while k < l2Idx {
                s += degree(k, degPtr: degPtr, ovfPtr: ovfPtr, ovfCount: ovfCount)
                k += 1
            }
            let d = degree(l2Idx, degPtr: degPtr, ovfPtr: ovfPtr, ovfCount: ovfCount)
            return s..<(s + d)
        }

        @inline(__always) func l3Range(_ l2Idx: Int) -> Range<Int> {
            childRange(l2Idx, degPtr: l2Deg3, blkPtr: l2Blk3, ovfPtr: l2Ovf3, ovfCount: ovf3Count)
        }

        @inline(__always) func l4Range(_ l2Idx: Int) -> Range<Int> {
            childRange(l2Idx, degPtr: l2Deg4, blkPtr: l2Blk4, ovfPtr: l2Ovf4, ovfCount: ovf4Count)
        }

        @inline(__always) func findL2(id0: Int, id1: Int) -> Int? {
            let r = l2Range(id0: id0)
            return findID13(l2ID13, r.lowerBound, r.upperBound, UInt16(id1))
        }

        func logMassL2(_ l3: Range<Int>) -> Double {
            guard !l3.isEmpty else { return 0 }
            var sum = 0.0
            for j in l3 { sum += exp3[Int(l3Val[j])] }
            return sum > 0 ? max3 + log(sum) : 0
        }

        func logMassL3(_ l4: Range<Int>, id2: UInt32) -> Double {
            let start = lowerBound26(l4.lowerBound, l4.upperBound, id2 << 13)
            var sum = 0.0
            var j = start
            while j < l4.upperBound && (read26(j) >> 13) == id2 {
                sum += exp4[Int(l4Val[j])]
                j += 1
            }
            return sum > 0 ? max4 + log(sum) : 0
        }
    }

    private let base: UnsafeRawPointer
    private let length: Int
    private let v2Main: V2Section?
    private let v2Pred: V2Section?
    private let array: UnsafePointer<UInt32>?
    private let size: Int
    /// Appended sub-trie used exclusively for context continuations (`continuations(after:limit:)`),
    /// defaulting to the main decoding trie when a `.gram` file has only one section.
    private let predArray: UnsafePointer<UInt32>?
    private let predSize: Int

    /// True when loaded from the compact 8-bit quantized `Mosto::GramV2` format.
    public var isCompactV2: Bool { v2Main != nil }

    public var collocationPenalty = -13.0
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

        let magic14 = String(decoding: UnsafeRawBufferPointer(start: b, count: 14), as: UTF8.self)
        if magic14 == "Mosto::GramV2\0" {
            guard let s1 = V2Section.parse(base: b, offset: 0, fileSize: fsize) else {
                munmap(p, fsize); throw LoadError.format
            }
            base = b
            length = fsize
            v2Main = s1
            v2Pred = V2Section.parse(base: b, offset: s1.sectionBytes, fileSize: fsize) ?? s1
            array = nil; size = 0
            predArray = nil; predSize = 0
            return
        }

        // Legacy Metadata: format char[32] ("Rime::Grammar/…"), checksum u32, array size u32, offset i32
        let n = Int(b.loadUnaligned(fromByteOffset: 36, as: UInt32.self))
        let off = Int(b.loadUnaligned(fromByteOffset: 40, as: Int32.self))
        let sec1End = 40 + off + n * 4
        guard magic14 == "Rime::Grammar/", off >= 4, n >= 0, sec1End <= fsize, (40 + off) % 4 == 0 else {
            munmap(p, fsize); throw LoadError.format
        }
        base = b
        length = fsize
        v2Main = nil
        v2Pred = nil
        let mainArr = (b + 40 + off).assumingMemoryBound(to: UInt32.self)
        array = mainArr
        size = n
        var pArr = mainArr
        var pSize = n
        if sec1End + 44 <= fsize,
           String(decoding: UnsafeRawBufferPointer(start: b + sec1End, count: 14), as: UTF8.self) == "Rime::Grammar/" {
            let pn = Int(b.loadUnaligned(fromByteOffset: sec1End + 36, as: UInt32.self))
            let poff = Int(b.loadUnaligned(fromByteOffset: sec1End + 40, as: Int32.self))
            let predByteOff = sec1End + 40 + poff
            if poff >= 4, pn >= 0, predByteOff % 4 == 0, predByteOff + pn * 4 <= fsize {
                pArr = (b + predByteOff).assumingMemoryBound(to: UInt32.self)
                pSize = pn
            }
        }
        predArray = pArr
        predSize = pSize
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: base), length) }

    // Legacy double-array trie helpers
    @inline(__always) private func unit(_ i: Int) -> UInt32 { guard let arr = array else { return 0 }; return i < size ? arr[i] : 0 }
    @inline(__always) private func unit(_ i: Int, in arr: UnsafePointer<UInt32>, count n: Int) -> UInt32 { i < n ? arr[i] : 0 }
    @inline(__always) private func offset(_ u: UInt32) -> Int { Int((u >> 10) << ((u & (1 << 9)) >> 6)) }
    @inline(__always) private func label(_ u: UInt32) -> UInt32 { u & ((1 << 31) | 0xFF) }
    @inline(__always) private func hasLeaf(_ u: UInt32) -> Bool { (u >> 8) & 1 == 1 }

    /// The node reached by `key` from the root in `(arr, n)`, or nil.
    private func traverse(_ key: ArraySlice<UInt8>, in arr: UnsafePointer<UInt32>, count n: Int) -> Int? {
        var id = 0
        var u = unit(0, in: arr, count: n)
        for c in key {
            id ^= offset(u) ^ Int(c)
            u = unit(id, in: arr, count: n)
            if label(u) != UInt32(c) { return nil }
        }
        return id
    }
    private func traverse(_ key: ArraySlice<UInt8>) -> Int? {
        guard let array else { return nil }
        return traverse(key, in: array, count: size)
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
        if let m = v2Main {
            guard text.count >= 2 else { return nil }
            guard let id0 = m.charID(text[0]), let id1 = m.charID(text[1]),
                  let idx2 = m.findL2(id0: id0, id1: id1) else { return nil }
            if text.count == 2 {
                let q = Int(m.l2Val[idx2])
                return q == 0 ? nil : m.val2[q]
            } else if text.count == 3 {
                guard let id2 = m.charID(text[2]) else { return nil }
                let r3 = m.l3Range(idx2)
                guard let idx3 = m.findID13(m.l3ID13, r3.lowerBound, r3.upperBound, UInt16(id2)) else { return nil }
                return m.val3[Int(m.l3Val[idx3])]
            } else {
                guard let id2 = m.charID(text[2]), let id3 = m.charID(text[3]) else { return nil }
                let r4 = m.l4Range(idx2)
                let k26 = (UInt32(id2) << 13) | UInt32(id3)
                guard let idx4 = m.findKey26(r4.lowerBound, r4.upperBound, k26) else { return nil }
                return m.val4[Int(m.l4Val[idx4])]
            }
        }
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
        if let p = v2Pred {
            return continuationsV2(p, after: context, limit: limit)
        }
        guard let predArray else { return [] }
        var out: [String: Double] = [:]
        for n in stride(from: min(3, context.count), through: 1, by: -1) {
            guard let node = traverse(Grammar.encode(context.suffix(n))[...], in: predArray, count: predSize) else { continue }
            let firsts = children(of: node, in: predArray, count: predSize).sorted { ($0.2 ?? -1) > ($1.2 ?? -1) }
            for (rank, (bytes1, node1, v1)) in firsts.enumerated() {
                let c1 = Grammar.decode(bytes1)
                guard let ch1 = c1, Grammar.isHan(ch1) else { continue }
                if let v1 { out[String(ch1)] = max(out[String(ch1)] ?? -.infinity, Double(v1) / 10_000 + Double(n) * contextBonus) }
                guard n <= 2, rank < 24, v1 != nil else { continue }
                for (bytes2, _, v2) in children(of: node1, in: predArray, count: predSize) {
                    guard let v2, let ch2 = Grammar.decode(bytes2), Grammar.isHan(ch2) else { continue }
                    let t = String([ch1, ch2])
                    out[t] = max(out[t] ?? -.infinity, Double(v2) / 10_000 + Double(n) * contextBonus)
                }
            }
            if out.count >= limit * continuationStop { break }
        }
        return out.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    private func continuationsV2(_ p: V2Section, after context: [Character], limit: Int) -> [(text: String, score: Double)] {
        let suf = Array(context.suffix(3))
        var out: [String: Double] = [:]
        out.reserveCapacity(limit * 4)
        // Band-tagged Section 2 encodes 2-char-eligible entries in [8.5, 14.5] and 1-char-only entries in [0.5, 6.5].
        let banded = p.val2[255] <= 7.0 && (p.val3[255] >= 8.0 || p.val4[255] >= 8.0)
        @inline(__always) func score1(_ v: Double) -> Double { banded && v >= 7.5 ? v - 8.0 : v }
        for n in stride(from: min(3, suf.count), through: 1, by: -1) {
            let bonus = Double(n) * contextBonus
            let ctx = suf.suffix(n)
            guard let id0 = p.charID(ctx[ctx.startIndex]) else { continue }
            if n == 3 {
                guard let id1 = p.charID(ctx[ctx.startIndex + 1]),
                      let id2 = p.charID(ctx[ctx.startIndex + 2]),
                      let idx2 = p.findL2(id0: id0, id1: id1) else { continue }
                let r4 = p.l4Range(idx2)
                let hiPrefix = UInt32(id2) << 13
                var j = p.lowerBound26(r4.lowerBound, r4.upperBound, hiPrefix)
                while j < r4.upperBound {
                    let k26 = p.read26(j)
                    if (k26 >> 13) != UInt32(id2) { break }
                    let s1 = String(p.char(forID: Int(k26 & 0x1FFF)))
                    let sc = score1(p.val4[Int(p.l4Val[j])]) + bonus
                    out[s1] = max(out[s1] ?? -.infinity, sc)
                    j += 1
                }
            } else if n == 2 {
                guard let id1 = p.charID(ctx[ctx.startIndex + 1]),
                      let idx2 = p.findL2(id0: id0, id1: id1) else { continue }
                let r3 = p.l3Range(idx2)
                for j in r3 {
                    let ch1 = p.char(forID: Int(p.read13(p.l3ID13, j)))
                    let s1 = String(ch1)
                    out[s1] = max(out[s1] ?? -.infinity, score1(p.val3[Int(p.l3Val[j])]) + bonus)
                }
                let r4 = p.l4Range(idx2)
                for j in r4 {
                    let v4 = p.val4[Int(p.l4Val[j])]
                    if banded && v4 < 7.5 { continue }
                    let k26 = p.read26(j)
                    let ch1 = p.char(forID: Int(k26 >> 13))
                    let ch2 = p.char(forID: Int(k26 & 0x1FFF))
                    let s2 = String([ch1, ch2])
                    out[s2] = max(out[s2] ?? -.infinity, (banded ? v4 - 8.0 : v4) + bonus)
                }
            } else {
                let r2 = p.l2Range(id0: id0)
                for idx2 in r2 {
                    let ch1 = p.char(forID: Int(p.read13(p.l2ID13, idx2)))
                    let q2 = p.l2Val[idx2]
                    if q2 != 0 {
                        let s1 = String(ch1)
                        out[s1] = max(out[s1] ?? -.infinity, p.val2[Int(q2)] + bonus)
                    }
                    let r3 = p.l3Range(idx2)
                    for j in r3 {
                        let v3 = p.val3[Int(p.l3Val[j])]
                        if banded && v3 < 7.5 { continue }
                        let ch2 = p.char(forID: Int(p.read13(p.l3ID13, j)))
                        let s2 = String([ch1, ch2])
                        out[s2] = max(out[s2] ?? -.infinity, (banded ? v3 - 8.0 : v3) + bonus)
                    }
                }
            }
            if out.count >= limit * continuationStop { break }
        }
        return out.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// The nodes one character below `node`: (its bytes, the node, the count stored there if a key ends there).
    private func children(of node: Int, in arr: UnsafePointer<UInt32>, count n: Int) -> [([UInt8], Int, Int?)] {
        var out: [([UInt8], Int, Int?)] = []
        // CJK characters are two bytes: a lead byte 0x80…0xDF (or the 0xE1 escape), then any byte
        for b1 in 0x80...0xE1 {
            guard let n1 = child(node, UInt8(b1), in: arr, count: n) else { continue }
            for b2 in 0...255 {
                guard let n2 = child(n1, UInt8(b2), in: arr, count: n) else { continue }
                out.append(([UInt8(b1), UInt8(b2)], n2, leafValue(n2, in: arr, count: n)))
            }
        }
        return out
    }
    private func children(of node: Int) -> [([UInt8], Int, Int?)] {
        guard let array else { return [] }
        return children(of: node, in: array, count: size)
    }

    @inline(__always) private func child(_ node: Int, _ c: UInt8, in arr: UnsafePointer<UInt32>, count n: Int) -> Int? {
        let id = node ^ offset(unit(node, in: arr, count: n)) ^ Int(c)
        return label(unit(id, in: arr, count: n)) == UInt32(c) ? id : nil
    }

    @inline(__always) private func leafValue(_ node: Int, in arr: UnsafePointer<UInt32>, count n: Int) -> Int? {
        let u = unit(node, in: arr, count: n)
        guard hasLeaf(u) else { return nil }
        return Int(unit(node ^ offset(u), in: arr, count: n) & 0x7FFF_FFFF)
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
    /// a joint count is divided by to read it as "how likely after this context". Cached per node (legacy v1 only).
    private let massLock = NSLock()
    private var massCache: [Int: Double] = [:]
    public var massBudget = Int.max
    private var massSpent = 0
    public func resetMassBudget() { massLock.lock(); massSpent = 0; massLock.unlock() }
    func logMass(_ node: Int) -> Double {
        massLock.lock()
        if let m = massCache[node] { massLock.unlock(); return m }
        guard massSpent < massBudget else { massLock.unlock(); return massCenter }
        massSpent += 1
        massLock.unlock()
        var vals: [Double] = []
        for (_, _, v) in children(of: node) { if let v { vals.append(Double(v) / 10_000) } }
        let top = vals.max() ?? 0
        let m = vals.isEmpty ? 0 : top + log(vals.reduce(0) { $0 + exp($1 - top) })
        massLock.lock()
        if massCache.count > 4096 { massCache.removeAll(keepingCapacity: true) }
        massCache[node] = m
        massLock.unlock()
        return m
    }
    public var massWeight = 0.0
    public var massCenter = 15.0

    /// How well `word` follows `context` (the text before it): context language-model score, in natural-log units.
    public func query(context: [Character], word: [Character]) -> Double {
        guard !context.isEmpty, !word.isEmpty else { return nonCollocationPenalty }
        if let m = v2Main {
            return queryV2(m, context: context, word: word)
        }
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

    private func queryV2(_ m: V2Section, context: [Character], word: [Character]) -> Double {
        let ctxSlice = context.suffix(3)
        let ctxCount = ctxSlice.count
        var c0: Int?, c1: Int?, c2: Int?
        let baseIdx = ctxSlice.startIndex
        c0 = m.charID(ctxSlice[baseIdx])
        if ctxCount >= 2 { c1 = m.charID(ctxSlice[baseIdx + 1]) }
        if ctxCount >= 3 { c2 = m.charID(ctxSlice[baseIdx + 2]) }

        let wSlice = word.prefix(3)
        let wCount = wSlice.count
        let wBase = wSlice.startIndex
        guard let w0 = m.charID(wSlice[wBase]) else { return nonCollocationPenalty }
        let w1 = wCount >= 2 ? m.charID(wSlice[wBase + 1]) : nil
        let w2 = wCount >= 3 ? m.charID(wSlice[wBase + 2]) : nil

        var best = nonCollocationPenalty
        @inline(__always) func apply(_ lc: Double, collocation: Int, full: Bool, matchedChars: Int, mass: () -> Double) {
            let strong = collocation >= collocationMinLength || (full && matchedChars == wCount)
            var sc = lc + (strong ? collocationPenalty : weakCollocationPenalty)
            if massWeight > 0 { sc -= massWeight * (mass() - massCenter) }
            if sc > best { best = sc }
        }

        // ctxLen = 3 (full == true): (c0, c1, c2) + w0 -> L4
        if ctxCount == 3, let a0 = c0, let a1 = c1, let a2 = c2, let idx2 = m.findL2(id0: a0, id1: a1) {
            let r4 = m.l4Range(idx2)
            let k26 = (UInt32(a2) << 13) | UInt32(w0)
            if let idx4 = m.findKey26(r4.lowerBound, r4.upperBound, k26) {
                apply(m.val4[Int(m.l4Val[idx4])], collocation: 4, full: true, matchedChars: 1) {
                    m.logMassL3(r4, id2: UInt32(a2))
                }
            }
        }

        // ctxLen = 2: suffix of length 2 -> (p0, p1) + [w0 | w0,w1] -> L3 / L4
        if ctxCount >= 2 {
            let p0 = ctxCount == 3 ? c1 : c0
            let p1 = ctxCount == 3 ? c2 : c1
            let full2 = ctxCount == 2
            if let a0 = p0, let a1 = p1, let idx2 = m.findL2(id0: a0, id1: a1) {
                var cachedMass: Double?
                @inline(__always) func mass2() -> Double {
                    if let cm = cachedMass { return cm }
                    let val = m.logMassL2(m.l3Range(idx2))
                    cachedMass = val
                    return val
                }
                let r3 = m.l3Range(idx2)
                if let idx3 = m.findID13(m.l3ID13, r3.lowerBound, r3.upperBound, UInt16(w0)) {
                    apply(m.val3[Int(m.l3Val[idx3])], collocation: 3, full: full2, matchedChars: 1, mass: mass2)
                }
                if let b1 = w1 {
                    let r4 = m.l4Range(idx2)
                    let k26 = (UInt32(w0) << 13) | UInt32(b1)
                    if let idx4 = m.findKey26(r4.lowerBound, r4.upperBound, k26) {
                        apply(m.val4[Int(m.l4Val[idx4])], collocation: 4, full: full2, matchedChars: 2, mass: mass2)
                    }
                }
            }
        }

        // ctxLen = 1: last context char a0 + [w0 | w0,w1 | w0,w1,w2] -> L2 / L3 / L4
        let lastCtxID = ctxCount == 3 ? c2 : (ctxCount == 2 ? c1 : c0)
        let full1 = ctxCount == 1
        if let a0 = lastCtxID, let idx2 = m.findL2(id0: a0, id1: w0) {
            let m1 = Double(m.l1LogMass[a0])
            let q2 = Int(m.l2Val[idx2])
            if q2 != 0 {
                apply(m.val2[q2], collocation: 2, full: full1, matchedChars: 1) { m1 }
            }
            if let b1 = w1 {
                let r3 = m.l3Range(idx2)
                if let idx3 = m.findID13(m.l3ID13, r3.lowerBound, r3.upperBound, UInt16(b1)) {
                    apply(m.val3[Int(m.l3Val[idx3])], collocation: 3, full: full1, matchedChars: 2) { m1 }
                }
                if let b2 = w2 {
                    let r4 = m.l4Range(idx2)
                    let k26 = (UInt32(b1) << 13) | UInt32(b2)
                    if let idx4 = m.findKey26(r4.lowerBound, r4.upperBound, k26) {
                        apply(m.val4[Int(m.l4Val[idx4])], collocation: 4, full: full1, matchedChars: 3) { m1 }
                    }
                }
            }
        }

        return best
    }
}
