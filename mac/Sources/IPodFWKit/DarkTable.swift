import Foundation

// Swift port of src/ipodfw/darktable.py: the "IFD2" dark switch table, which the patch dark-mode 1.3
// applies at a dark start.
//
// The IFDM table holds "old XOR new" for each byte of the theme. But the light pictures are already in
// RAM when the patch applies the table. Thus IFD2 gives most dark pictures as a colour map of the light
// picture, or as a palette. With Dark Gray, the table is 65,084 bytes, not 681,853. The research is in
// re/dark-mode-compression.md and re/dark-table-map/.
//
// The table (little-endian, each record on a 4-byte boundary):
//   u32 "IFD2", u32 number of records, u32 size of the table in bytes, records.
// Each record: u32 address, u32 (kind << 28 | length in bytes), then the data of the kind:
//   RAW (0): the new bytes, then zeros to a 4-byte boundary.
//   MAP (1): u32 N, N x {u16 light, u16 dark}, sorted by light. Other values do not change.
//   PAL (2): u16 number of colours, u16 bits (1, 2, 4 or 8), the colours (u16), zeros to a 4-byte
//            boundary, the indices (MSB first), zeros to a 4-byte boundary.
// RAW records after a MAP record correct the pixels that the map does not give.
//
// A MAP record reads the light pixels. Thus the table is correct only on the image that it was made
// from. The build checks this after all patches (`check`).

public enum DarkTable {
    public static let magic: UInt32 = 0x3244_4649                // "IFD2"
    static let raw = 0, map = 1, pal = 2
    static let gap = 8                                            // join two RAW runs if fewer bytes separate them
    static let limit = 0x80_0000                                  // the decoder writes only below this address

    /// The ranges in lo..<hi where a and b differ, joined across gaps below `gap`.
    static func runs(_ a: [UInt8], _ b: [UInt8], _ lo: Int, _ hi: Int) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var i = lo
        while i < hi {
            if a[i] == b[i] { i += 1; continue }
            let start = i
            var end = i + 1
            i += 1
            while i < hi && i - end < gap {
                if a[i] != b[i] { end = i + 1 }
                i += 1
            }
            out.append((start, end))
        }
        return out
    }

    /// The parts of s..<t that are not in a covered range.
    static func outside(_ s: Int, _ t: Int, _ covered: [(Int, Int)]) -> [(Int, Int)] {
        for (a, e) in covered where a < t && e > s {
            var out: [(Int, Int)] = []
            if a > s { out += outside(s, a, covered) }
            if e < t { out += outside(e, t, covered) }
            return out
        }
        return [(s, t)]
    }

    static func pad(_ b: inout [UInt8]) {
        b += [UInt8](repeating: 0, count: (4 - b.count % 4) % 4)
    }

    static func head(_ at: Int, _ kind: Int, _ length: Int) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 8)
        put32(&h, 0, UInt32(at)); put32(&h, 4, UInt32(kind << 28 | length))
        return h
    }

    static func rawRecord(_ at: Int, _ end: Int, _ dark: [UInt8]) -> [UInt8] {
        var r = head(at, raw, end - at) + dark[at..<end]
        pad(&r)
        return r
    }

    static func u16s(_ d: [UInt8], _ at: Int, _ n: Int) -> [UInt16] {
        (0..<n).map { UInt16(d[at + 2 * $0]) | UInt16(d[at + 2 * $0 + 1]) << 8 }
    }

    static func put16(_ d: inout [UInt8], _ v: UInt16) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8))
    }

    /// The pixel data (start, end) of each 16-bit picture. `positions` are the BMap resource positions.
    public static func pictureRanges(_ osos: [UInt8], positions: [Int]) -> [(Int, Int)] {
        var out = Set<[Int]>()
        for pos in positions {
            if let p = Picture.parse(osos, at: pos), p.depth == 16 {
                out.insert([p.dataPos, p.dataPos + p.bytesPerRow * p.height])
            }
        }
        return out.map { ($0[0], $0[1]) }.sorted { $0 < $1 }
    }

    /// The IFD2 table that changes `light` into `dark`. For each picture, the smallest record is used
    /// (RAW, then MAP, then PAL if the sizes are the same). All other differences become RAW records.
    public static func encode(light: [UInt8], dark: [UInt8], pictures: [(Int, Int)]) throws -> [UInt8] {
        guard light.count == dark.count, light.count <= limit else {
            throw ThemeError("The light image and the dark image do not have the same size.")
        }
        var records: [[UInt8]] = []
        var covered: [(Int, Int)] = []
        let pics = Set(pictures.map { [$0.0, $0.1] }).map { ($0[0], $0[1]) }.sorted { $0 < $1 }
        for (x, y) in zip(pics, pics.dropFirst()) where y.0 < x.1 {
            // A second MAP on the same pixels gives wrong colours (MAP is not idempotent).
            throw ThemeError(String(format: "The pixel ranges 0x%x and 0x%x overlap.", x.0, y.0))
        }
        for (a, e) in pics {
            guard a % 2 == 0, e % 2 == 0, e <= light.count, light[a..<e] != dark[a..<e] else { continue }
            covered.append((a, e))
            let n = (e - a) / 2
            let lx = u16s(light, a, n), dx = u16s(dark, a, n)
            var options: [(size: Int, kind: Int, records: [[UInt8]])] = []
            let rawRecords = runs(light, dark, a, e).map { rawRecord($0.0, $0.1, dark) }
            options.append((rawRecords.reduce(0) { $0 + $1.count }, raw, rawRecords))
            // MAP: for each light value, the most frequent dark value; with the same count, the smaller value.
            var counts: [UInt16: [UInt16: Int]] = [:]
            for (x, y) in zip(lx, dx) { counts[x, default: [:]][y, default: 0] += 1 }
            var best: [UInt16: UInt16] = [:]
            for (x, c) in counts {
                best[x] = c.min { ($0.value, $1.key) > ($1.value, $0.key) }!.key
            }
            let pairs = best.filter { $0.key != $0.value }.sorted { $0.key < $1.key }
            var rec = head(a, map, e - a)
            rec += [UInt8](repeating: 0, count: 4)
            put32(&rec, 8, UInt32(pairs.count))
            for (x, y) in pairs { put16(&rec, x); put16(&rec, y) }
            var mapped = [UInt8]()
            mapped.reserveCapacity(e - a)
            for x in lx { put16(&mapped, best[x]!) }
            var mapRecords = [rec]
            mapRecords += runs(mapped, Array(dark[a..<e]), 0, e - a).map { rawRecord(a + $0.0, a + $0.1, dark) }
            options.append((mapRecords.reduce(0) { $0 + $1.count }, map, mapRecords))
            // PAL
            let colours = Array(Set(dx)).sorted()
            if colours.count <= 256 {
                let bits = [1, 2, 4, 8].first { 1 << $0 >= colours.count }!
                var index: [UInt16: Int] = [:]
                for (i, c) in colours.enumerated() { index[c] = i }
                var buf = [UInt8](repeating: 0, count: (n * bits + 7) / 8)
                for (i, y) in dx.enumerated() {
                    let bit = i * bits
                    buf[bit / 8] |= UInt8(index[y]! << (8 - bits - bit % 8))
                }
                var p = head(a, pal, e - a)
                put16(&p, UInt16(colours.count)); put16(&p, UInt16(bits))
                for c in colours { put16(&p, c) }
                pad(&p)
                p += buf
                pad(&p)
                options.append((p.count, pal, [p]))
            }
            records += options.min { ($0.size, $0.kind) < ($1.size, $1.kind) }!.records
        }
        // All other differences: the parts of each run outside the pictures (the records above did those).
        for (s, t) in runs(light, dark, 0, light.count) {
            for (s2, t2) in outside(s, t, covered) { records.append(rawRecord(s2, t2, dark)) }
        }
        let body = records.flatMap { $0 }
        var out = [UInt8](repeating: 0, count: 12)
        put32(&out, 0, magic); put32(&out, 4, UInt32(records.count)); put32(&out, 8, UInt32(12 + body.count))
        return out + body
    }

    /// The size of the record at p, or nil if the decoder stops at it.
    static func fits(_ t: [UInt8], _ p: Int, _ end: Int) -> Int? {
        guard end - p >= 8 else { return nil }
        let ck = Int(le32(t, p + 4)), kind = ck >> 28, n = ck & 0x0FFF_FFFF
        let room = end - p - 8
        switch kind {
        case raw:
            return n <= room - (room & 3) ? 8 + n + (4 - n % 4) % 4 : nil
        case map:
            guard room >= 4 else { return nil }
            let count = Int(le32(t, p + 8))
            return count <= (room - 4) >> 2 ? 12 + 4 * count : nil
        case pal:
            guard room >= 4 else { return nil }
            let count = Int(le16(t, p + 8)), bits = Int(le16(t, p + 10))
            guard [1, 2, 4, 8].contains(bits) else { return nil }
            let headSize = 4 + ((2 * count + 3) & ~3), bytes = ((n >> 1) * bits + 7) >> 3
            return headSize <= room && ((bytes + 3) & ~3) <= room - headSize ? 8 + headSize + ((bytes + 3) & ~3) : nil
        default:
            return nil
        }
    }

    /// What the patch (apply_table2 in dark_mode.c) does with an IFD2 table. `osos` is the image in RAM.
    public static func apply(_ osos: inout [UInt8], _ t: [UInt8]) throws {
        guard t.count >= 12, le32(t, 0) == magic, le32(t, 8) >= 12 else { return }
        let count = Int(le32(t, 4)), end = min(Int(le32(t, 8)), t.count)
        var p = 12
        for _ in 0..<count {
            guard let size = fits(t, p, end) else { return }
            let at = Int(le32(t, p)), ck = Int(le32(t, p + 4)), kind = ck >> 28, n = ck & 0x0FFF_FFFF
            defer { p += size }
            guard at < limit, n <= limit - at, kind == raw || (at | n) & 1 == 0 else { continue }
            guard at + n <= osos.count else {
                throw ThemeError(String(format: "The dark switch table writes at 0x%x, after the end of the image.", at))
            }
            switch kind {
            case raw:
                osos.replaceSubrange(at..<at + n, with: t[p + 8..<p + 8 + n])
            case map:
                let pairs = Int(le32(t, p + 8))
                var m: [UInt16: UInt16] = [:]
                for j in 0..<pairs { m[le16(t, p + 12 + 4 * j)] = le16(t, p + 14 + 4 * j) }
                for j in 0..<n / 2 {
                    let x = le16(osos, at + 2 * j)
                    if let y = m[x] { osos[at + 2 * j] = UInt8(y & 0xFF); osos[at + 2 * j + 1] = UInt8(y >> 8) }
                }
            default:
                let colours = Int(le16(t, p + 8)), bits = Int(le16(t, p + 10))
                let index = p + 12 + ((2 * colours + 3) & ~3), mask = (1 << bits) - 1
                for j in 0..<n / 2 {
                    let bit = j * bits
                    let v = Int(t[index + bit / 8]) >> (8 - bits - bit % 8) & mask
                    if v < colours {
                        let c = le16(t, p + 12 + 2 * v)
                        osos[at + 2 * j] = UInt8(c & 0xFF); osos[at + 2 * j + 1] = UInt8(c >> 8)
                    }
                }
            }
        }
    }

    /// What the patch does with the dark table at a dark start: IFD2 or IFDM.
    public static func applyDark(_ osos: inout [UInt8], _ table: [UInt8]) throws {
        if le32(table, 0) == magic { try apply(&osos, table) } else { DarkMode.applySwitchTable(&osos, table) }
    }

    /// Make sure that `table` gives on `osos` the same dark image as the IFDM table. Do this on the final
    /// osos, after all patches: a patch that writes into a range of the table makes it wrong.
    public static func check(_ osos: [UInt8], ifdm: [UInt8], table: [UInt8]) throws {
        guard table != ifdm else { return }
        var want = osos, got = osos
        DarkMode.applySwitchTable(&want, ifdm)
        try apply(&got, table)
        if let at = got.indices.first(where: { got[$0] != want[$0] }) {
            throw ThemeError(String(format: "The dark switch table does not give the dark theme at 0x%x. "
                                    + "A patch can write into the dark theme. The firmware is not made.", at))
        }
    }
}
