import Foundation

/// The FAT volume in the rsrc image: the fonts (`/Resources/Fonts`) and the programs of the video
/// processor (`/Resources/VideoCore`). RetailOS mounts it at the entryOffset of rsrc (0xc60ec, 0xc7f7c).
///
/// The Apple volume has the label "FAT16", but it has 2546 clusters. A FAT volume with fewer than
/// 4085 clusters is FAT12, thus the type comes from the cluster count. A change keeps the boot
/// sector, the geometry, the label and the directories. It changes only the clusters and the
/// directory entry of a file. Research: re/fonts.md.
public struct ResourceVolume {
    public private(set) var bytes: [UInt8]
    let bytesPerSector, sectorsPerCluster, fatStart, fatCount, fatBytes, rootStart, rootBytes, dataStart, clusterBytes, clusters: Int
    public let isFAT12: Bool

    /// A file in the volume. `entry` is the offset of its 32-byte directory entry in `bytes`.
    public struct File: Equatable {
        public let path: String
        public let size: Int
        public let firstCluster: Int
        let entry: Int
    }

    public init(_ bytes: [UInt8]) throws {
        guard bytes.count >= 512, bytes[510] == 0x55, bytes[511] == 0xAA else {
            throw FirmwareError("The rsrc image has no FAT volume at its entryOffset.")
        }
        let bps = Int(le16(bytes, 11)), spc = Int(bytes[13]), reserved = Int(le16(bytes, 14)), fats = Int(bytes[16])
        let rootEntries = Int(le16(bytes, 17)), total16 = Int(le16(bytes, 19)), fatSectors = Int(le16(bytes, 22))
        let total = total16 != 0 ? total16 : Int(le32(bytes, 32))
        guard [512, 1024, 2048, 4096].contains(bps), spc > 0, fats > 0, fatSectors > 0, total * bps <= bytes.count else {
            throw FirmwareError("The FAT volume in rsrc has a geometry that iPodFirm does not know.")
        }
        self.bytes = Array(bytes[0..<total * bps])
        bytesPerSector = bps
        sectorsPerCluster = spc
        fatStart = reserved * bps
        fatCount = fats
        fatBytes = fatSectors * bps
        rootStart = fatStart + fats * fatBytes
        rootBytes = (rootEntries * 32 + bps - 1) / bps * bps
        dataStart = rootStart + rootBytes
        clusterBytes = bps * spc
        clusters = (total * bps - dataStart) / clusterBytes
        isFAT12 = clusters < 4085
        guard clusters > 0, clusters < 65525 else { throw FirmwareError("The FAT volume in rsrc is not FAT12 or FAT16.") }
    }

    // MARK: the FAT

    func next(_ c: Int) -> Int {
        if isFAT12 {
            let v = Int(le16(bytes, fatStart + c * 3 / 2))
            return c & 1 == 1 ? v >> 4 : v & 0xFFF
        }
        return Int(le16(bytes, fatStart + c * 2))
    }

    /// Writes the value of cluster `c` into each copy of the FAT.
    mutating func setNext(_ c: Int, _ value: Int) {
        for copy in 0..<fatCount {
            let base = fatStart + copy * fatBytes
            if isFAT12 {
                let o = base + c * 3 / 2
                if c & 1 == 1 {
                    bytes[o] = (bytes[o] & 0x0F) | UInt8((value << 4) & 0xF0)
                    bytes[o + 1] = UInt8((value >> 4) & 0xFF)
                } else {
                    bytes[o] = UInt8(value & 0xFF)
                    bytes[o + 1] = (bytes[o + 1] & 0xF0) | UInt8((value >> 8) & 0x0F)
                }
            } else {
                bytes[base + c * 2] = UInt8(value & 0xFF)
                bytes[base + c * 2 + 1] = UInt8((value >> 8) & 0xFF)
            }
        }
    }

    var endOfChain: Int { isFAT12 ? 0xFFF : 0xFFFF }

    func chain(_ first: Int) -> [Int] {
        var out: [Int] = [], c = first
        while c >= 2, c < clusters + 2, out.count <= clusters {
            out.append(c)
            c = next(c)
        }
        return out
    }

    func clusterRange(_ c: Int) -> Range<Int> {
        let start = dataStart + (c - 2) * clusterBytes
        return start..<start + clusterBytes
    }

    // MARK: the directories

    /// The entries of a directory: (name, entry offset). Long names come from the LFN entries.
    func entries(in ranges: [Range<Int>]) -> [(name: String, entry: Int)] {
        var out: [(String, Int)] = [], long: [String] = []
        for r in ranges {
            for e in stride(from: r.lowerBound, to: r.upperBound - 31, by: 32) {
                if bytes[e] == 0 { return out }
                if bytes[e] == 0xE5 { long = []; continue }
                let attr = bytes[e + 11]
                if attr == 0x0F {
                    var units: [UInt16] = []
                    for o in [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30] { units.append(le16(bytes, e + o)) }
                    let part = String(decoding: units.prefix { $0 != 0 && $0 != 0xFFFF }, as: UTF16.self)
                    long.insert(part, at: 0)
                    continue
                }
                if attr & 0x08 != 0 { long = []; continue }
                let base = String(decoding: bytes[e..<e + 8], as: UTF8.self).trimmingCharacters(in: .whitespaces)
                let ext = String(decoding: bytes[e + 8..<e + 11], as: UTF8.self).trimmingCharacters(in: .whitespaces)
                let name = long.isEmpty ? (ext.isEmpty ? base : base + "." + ext) : long.joined()
                long = []
                if name == "." || name == ".." { continue }
                out.append((name, e))
            }
        }
        return out
    }

    /// All files, with their paths, in the order of the directories.
    public var files: [File] {
        var out: [File] = [], todo: [(String, [Range<Int>])] = [("", [rootStart..<rootStart + rootBytes])]
        while !todo.isEmpty {
            let (parent, ranges) = todo.removeFirst()
            for (name, e) in entries(in: ranges) {
                let path = parent + "/" + name, first = Int(le16(bytes, e + 26))
                if bytes[e + 11] & 0x10 != 0 {
                    todo.append((path, chain(first).map(clusterRange)))
                } else {
                    out.append(File(path: path, size: Int(le32(bytes, e + 28)), firstCluster: first, entry: e))
                }
            }
        }
        return out
    }

    public func file(_ path: String) -> File? { files.first { $0.path == path } }

    public func read(_ f: File) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(f.size)
        for c in chain(f.firstCluster) where out.count < f.size {
            out += bytes[clusterRange(c)].prefix(f.size - out.count)
        }
        return out
    }

    /// The clusters that hold a directory. They never move.
    var directoryClusters: Set<Int> {
        var out = Set<Int>(), todo: [[Range<Int>]] = [[rootStart..<rootStart + rootBytes]]
        while !todo.isEmpty {
            for (_, e) in entries(in: todo.removeFirst()) where bytes[e + 11] & 0x10 != 0 {
                let c = chain(Int(le16(bytes, e + 26)))
                out.formUnion(c)
                todo.append(c.map(clusterRange))
            }
        }
        return out
    }

    public var freeBytes: Int { (2..<clusters + 2).filter { next($0) == 0 }.count * clusterBytes }

    // MARK: changes

    /// Replaces the content of the existing file at `path`. Each file stays contiguous: the file goes
    /// into the first free area that fits it. If no area fits, all files go again in their order,
    /// contiguously, after the directories.
    public mutating func replace(_ path: String, with data: [UInt8]) throws {
        try replace([path: data])
    }

    public mutating func replace(_ changes: [String: [UInt8]]) throws {
        let all = files
        for path in changes.keys where !all.contains(where: { $0.path == path }) {
            throw FirmwareError("The rsrc volume has no file \(path).")
        }
        let size = clusterBytes
        let old = all.filter { changes[$0.path] != nil }
        var oldClusters = 0
        for f in old { oldClusters += chain(f.firstCluster).count }
        let newClusters = changes.values.reduce(0) { $0 + ($1.count + size - 1) / size }
        guard newClusters <= freeBytes / clusterBytes + oldClusters else {
            throw FirmwareError("The fonts need \(newClusters * clusterBytes) bytes, but the rsrc volume has only "
                                + "\((freeBytes / clusterBytes + oldClusters) * clusterBytes) bytes for them.")
        }
        var work = self
        for f in old { work.release(f) }
        do {
            for f in old { try work.store(changes[f.path]!, for: f) }
        } catch {
            // no area fits: put all files again in their order
            work = self
            let order = all.sorted { $0.firstCluster < $1.firstCluster }
            let data = order.map { changes[$0.path] ?? read($0) }
            for f in order { work.release(f) }
            for (f, d) in zip(order, data) { try work.store(d, for: f) }
        }
        self = work
    }

    /// Frees the clusters of a file and writes zeros into them.
    mutating func release(_ f: File) {
        for c in chain(f.firstCluster) {
            setNext(c, 0)
            bytes.replaceSubrange(clusterRange(c), with: [UInt8](repeating: 0, count: clusterBytes))
        }
    }

    /// Writes `data` into the first free area that fits it, and sets the directory entry of `f`.
    mutating func store(_ data: [UInt8], for f: File) throws {
        let n = (data.count + clusterBytes - 1) / clusterBytes
        var first = 0
        if n > 0 {
            var run = 0, c = 2
            while c < clusters + 2 {
                run = next(c) == 0 ? run + 1 : 0
                if run == n { first = c - n + 1; break }
                c += 1
            }
            guard first != 0 else { throw FirmwareError("The rsrc volume has no free area of \(n * clusterBytes) bytes.") }
            for k in 0..<n {
                setNext(first + k, k == n - 1 ? endOfChain : first + k + 1)
                let r = clusterRange(first + k), part = data[(k * clusterBytes)..<min(data.count, (k + 1) * clusterBytes)]
                bytes.replaceSubrange(r.lowerBound..<r.lowerBound + part.count, with: part)
            }
        }
        bytes[f.entry + 20] = 0
        bytes[f.entry + 21] = 0
        bytes[f.entry + 26] = UInt8(first & 0xFF)
        bytes[f.entry + 27] = UInt8(first >> 8)
        put32(&bytes, f.entry + 28, UInt32(data.count))
    }
}

/// The 8 fonts of RetailOS 1.3. They are TrueType files with embedded bitmaps (EBLC/EBDT), one 4-bit
/// strike each. RetailOS opens them by name (0x242e50). iPodWizard changes the bitmaps.
public enum IPodFonts {
    public static let folder = "/Resources/Fonts/"
    public static let names = ["CJK.ttf", "Helvetica_17.ttf", "Helvetica_23.ttf", "MonoHope_15_Italic.ttf",
                               "MonoHope_15_Plain.ttf", "MonoHope_20_Italic.ttf", "MonoHope_20_Plain.ttf", "PodiumSans18.ttf"]

    /// The FAT volume of the rsrc image of `partition`.
    public static func volume(_ partition: FirmwarePartition) throws -> ResourceVolume {
        let e = try partition.entry("rsrc")
        let image = try partition.image("rsrc")
        guard Int(e.entryOffset) < image.count else { throw FirmwareError("The entryOffset of rsrc is outside the image.") }
        return try ResourceVolume(Array(image[Int(e.entryOffset)...]))
    }

    /// The 8 fonts of `partition`, by name.
    public static func fonts(in partition: FirmwarePartition) throws -> [String: [UInt8]] {
        let v = try volume(partition)
        var out: [String: [UInt8]] = [:]
        for name in names {
            guard let f = v.file(folder + name) else { throw FirmwareError("The rsrc volume has no font \(name).") }
            out[name] = v.read(f)
        }
        return out
    }

    /// The fonts of `fonts` that are different from the fonts of `apple`.
    public static func custom(_ fonts: [String: [UInt8]], apple: [String: [UInt8]]) -> [String: [UInt8]] {
        fonts.filter { apple[$0.key] != $0.value }
    }

    /// The bitmap strikes of a font: (ppem x, ppem y, bit depth) for each strike in EBLC.
    public static func strikes(_ font: [UInt8]) throws -> [[UInt8]] {
        func be16(_ o: Int) -> Int { Int(font[o]) << 8 | Int(font[o + 1]) }
        func be32(_ o: Int) -> Int { be16(o) << 16 | be16(o + 2) }
        guard font.count >= 12, be32(0) == 0x0001_0000 else { throw FirmwareError("The file is not a TrueType font.") }
        let count = be16(4)
        guard 12 + count * 16 <= font.count else { throw FirmwareError("The table directory of the font is not complete.") }
        var tables: [String: (Int, Int)] = [:]
        for i in 0..<count {
            let r = 12 + i * 16
            let tag = String(decoding: font[r..<r + 4], as: UTF8.self)
            let (off, len) = (be32(r + 8), be32(r + 12))
            guard off + len <= font.count else { throw FirmwareError("The table \(tag) of the font is outside the file.") }
            tables[tag] = (off, len)
        }
        for tag in ["EBLC", "EBDT", "cmap"] where tables[tag] == nil {
            throw FirmwareError("The font has no \(tag) table. The iPod needs a font with bitmaps.")
        }
        let (eblc, len) = tables["EBLC"]!
        guard len >= 8 else { throw FirmwareError("The EBLC table of the font is too short.") }
        let sizes = be32(eblc + 4)
        guard 8 + sizes * 48 <= len else { throw FirmwareError("The EBLC table of the font is not complete.") }
        return (0..<sizes).map { i in let o = eblc + 8 + i * 48; return [font[o + 44], font[o + 45], font[o + 46]] }
    }

    /// Makes sure that `font` can replace the Apple font `name`: a TrueType font with bitmaps, with
    /// the same strikes (sizes and bit depth) as the Apple font.
    public static func check(_ name: String, _ font: [UInt8], apple: [String: [UInt8]]) throws {
        guard let reference = apple[name] else {
            throw FirmwareError("\(name) is not a font of the iPod. Use one of these names: \(names.joined(separator: ", ")).")
        }
        let mine: [[UInt8]]
        do { mine = try strikes(font) } catch {
            throw FirmwareError("\(name): \((error as? FirmwareError)?.message ?? error.localizedDescription)")
        }
        let theirs = try strikes(reference)
        guard mine == theirs else {
            func text(_ s: [[UInt8]]) -> String { s.map { "\($0[0]) ppem, \($0[2]) bit" }.joined(separator: "; ") }
            throw FirmwareError("\(name) has the strikes \(text(mine)). The iPod needs \(text(theirs)).")
        }
    }

    /// The rsrc image of `partition` with `fonts` in place of the fonts of the same name. The image
    /// keeps its length and its entryOffset.
    public static func rsrc(of partition: FirmwarePartition, with fonts: [String: [UInt8]]) throws -> [UInt8] {
        var image = try partition.image("rsrc")
        let start = Int(try partition.entry("rsrc").entryOffset)
        var v = try volume(partition)
        try v.replace(Dictionary(uniqueKeysWithValues: fonts.map { (folder + $0.key, $0.value) }))
        image.replaceSubrange(start..<start + v.bytes.count, with: v.bytes)
        return image
    }

    /// Puts `fonts` into the rsrc of `partition`. Nothing changes if `fonts` is empty.
    public static func apply(_ fonts: [String: [UInt8]], to partition: FirmwarePartition) throws {
        guard !fonts.isEmpty else { return }
        try partition.replaceImage("rsrc", with: rsrc(of: partition, with: fonts))
    }
}
