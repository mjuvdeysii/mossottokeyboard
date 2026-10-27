import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Next-word predictions (联想) read from predictions.bin (Tools/build_predictions.py), memory-mapped.
/// After a commit the keyboard asks for continuations of the committed text, as Gboard pinyin does.
public final class Predictor {
    private let base: UnsafeRawPointer
    private let length: Int
    private let keyCount: Int
    private let keysOff: Int
    private let itemsOff: Int
    private let textOff: Int

    public init(path: String) throws {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw Lexicon.LoadError.open }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw Lexicon.LoadError.open }
        let size = Int(st.st_size)
        guard let p = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0),
              p != UnsafeMutableRawPointer(bitPattern: -1) else { throw Lexicon.LoadError.map }
        let b = UnsafeRawPointer(p)
        guard size >= 20, b.load(fromByteOffset: 0, as: UInt8.self) == UInt8(ascii: "X"),
              b.load(fromByteOffset: 2, as: UInt8.self) == UInt8(ascii: "P") else {
            munmap(p, size); throw Lexicon.LoadError.format
        }
        func u32(_ o: Int) -> Int { Int(b.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
        let kc = u32(8), ic = u32(12), tl = u32(16)
        let ko = 20, io = ko + kc * 12, to = io + ic * 8
        guard to + tl <= size else { munmap(p, size); throw Lexicon.LoadError.format }
        base = b; length = size; keyCount = kc; keysOff = ko; itemsOff = io; textOff = to
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: base), length) }

    private func keyBytes(_ i: Int) -> UnsafeRawBufferPointer {
        let o = keysOff + i * 12
        let off = Int(base.loadUnaligned(fromByteOffset: o, as: UInt32.self))
        let len = Int(base.loadUnaligned(fromByteOffset: o + 4, as: UInt16.self))
        return UnsafeRawBufferPointer(start: base + textOff + off, count: len)
    }

    private static func compare(_ a: UnsafeRawBufferPointer, _ b: [UInt8]) -> Int {
        let n = min(a.count, b.count)
        for i in 0..<n where a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }

    private func lookup(_ key: [UInt8]) -> [String] {
        var lo = 0, hi = keyCount - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let c = Self.compare(keyBytes(mid), key)
            if c == 0 {
                let o = keysOff + mid * 12
                let first = Int(base.loadUnaligned(fromByteOffset: o + 6, as: UInt32.self))
                let count = Int(base.loadUnaligned(fromByteOffset: o + 10, as: UInt16.self))
                return (0..<count).map { k in
                    let io = itemsOff + (first + k) * 8
                    let off = Int(base.loadUnaligned(fromByteOffset: io, as: UInt32.self))
                    let len = Int(base.loadUnaligned(fromByteOffset: io + 4, as: UInt16.self))
                    return String(decoding: UnsafeRawBufferPointer(start: base + textOff + off, count: len), as: UTF8.self)
                }
            }
            if c < 0 { lo = mid + 1 } else { hi = mid - 1 }
        }
        return []
    }

    /// Continuations for the text just committed: the whole commit first (up to four characters), then its tail.
    public func predict(after text: String, limit: Int = 8) -> [String] {
        let chars = Array(text.filter { !$0.isWhitespace })
        guard !chars.isEmpty else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        // a single trailing character only stands for itself when it was the whole commit
        let shortest = chars.count == 1 ? 1 : 2
        for n in stride(from: min(4, chars.count), through: shortest, by: -1) {
            for s in lookup(Array(String(chars.suffix(n)).utf8)) where seen.insert(s).inserted {
                out.append(s)
                if out.count == limit { return out }
            }
            if !out.isEmpty { break }   // a shorter tail only adds noise once a longer match was found
        }
        return out
    }
}
