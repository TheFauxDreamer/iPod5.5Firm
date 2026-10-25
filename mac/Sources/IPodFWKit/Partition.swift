import Foundation

// Swift port of src/ipodfw/partition.py: the iPod firmware partition
// ("]ih[" directory, 40-byte entries, plain byte-sum checksums).

public struct FirmwareError: LocalizedError, Equatable {
    public let message: String
    public var code: String?
    public init(_ message: String, code: String? = nil) { self.message = message; self.code = code }
    public var errorDescription: String? { message }
}

@inline(__always) func le32(_ d: [UInt8], _ o: Int) -> UInt32 {
    UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24
}

@inline(__always) func le16(_ d: [UInt8], _ o: Int) -> UInt16 {
    UInt16(d[o]) | UInt16(d[o + 1]) << 8
}

@inline(__always) func be32(_ d: [UInt8], _ o: Int) -> UInt32 {
    UInt32(d[o]) << 24 | UInt32(d[o + 1]) << 16 | UInt32(d[o + 2]) << 8 | UInt32(d[o + 3])
}

@inline(__always) func put32(_ d: inout [UInt8], _ o: Int, _ v: UInt32) {
    d[o] = UInt8(v & 0xFF); d[o + 1] = UInt8(v >> 8 & 0xFF)
    d[o + 2] = UInt8(v >> 16 & 0xFF); d[o + 3] = UInt8(v >> 24 & 0xFF)
}

public func byteSum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
    var s: UInt32 = 0
    for b in bytes { s &+= UInt32(b) }
    return s
}

let stopSignPrefix: [UInt8] = Array("{{~~  /-----\\   ".utf8)
let imageNames: [String: String] = ["soso": "osos", "crsr": "rsrc", "dpua": "aupd", "kbso": "osbk", "ebih": "hibe"]
let models: [UInt32: String] = [
    0x01: "1st/2nd Generation", 0x02: "3rd Generation", 0x40: "Mini 1G", 0x50: "4th Generation",
    0x60: "Photo/Color", 0x70: "Mini 2G", 0xC0: "Nano 1G", 0xB0: "Video (5G/5.5G)",
]

public struct ImageEntry: Identifiable, Equatable {
    public var index: Int
    public var dev: [UInt8]
    public var type: [UInt8]
    public var id: UInt32
    public var devOffset: UInt32
    public var length: UInt32
    public var addr: UInt32
    public var entryOffset: UInt32
    public var chksum: UInt32
    public var vers: UInt32
    public var loadAddr: UInt32

    public var name: String {
        let raw = String(decoding: type, as: UTF8.self)
        return imageNames[raw] ?? String(raw.reversed())
    }

    var packed: [UInt8] {
        var out = dev + type + [UInt8](repeating: 0, count: 32)
        for (n, v) in [id, devOffset, length, addr, entryOffset, chksum, vers, loadAddr].enumerated() {
            put32(&out, 8 + 4 * n, v)
        }
        return out
    }
}

public final class FirmwarePartition {
    public private(set) var data: [UInt8]
    public let formatVersion: UInt16
    public let dirOffset: Int
    public private(set) var entries: [ImageEntry]
    public let imageBase: Int

    public convenience init(contentsOf url: URL) throws {
        try self.init(data: [UInt8](Data(contentsOf: url)))
    }

    public init(data: [UInt8]) throws {
        let (dirOffset, entries) = try Self.readDirectory(data)
        self.data = data
        formatVersion = le16(data, 0x10A)
        self.dirOffset = dirOffset
        self.entries = entries
        guard let osos = entries.first(where: { $0.name == "osos" }) else {
            if let header = Self.samsungImageHeader(in: data) { throw Self.samsungError(header, code: nil) }
            throw FirmwareError("No osos image in the firmware directory.")
        }
        var base: Int?
        for candidate in [2048, 512, 1024, 4096, 0] {
            let start = candidate + Int(osos.devOffset)
            if start + Int(osos.length) <= data.count,
               byteSum(data[start..<start + Int(osos.length)]) == osos.chksum {
                base = candidate
                break
            }
        }
        guard let base else {
            throw FirmwareError("The osos checksum does not verify; the file is corrupt or truncated.")
        }
        imageBase = base
    }

    /// The STOP banner and the image directory. The images are not examined.
    static func readDirectory(_ data: [UInt8]) throws -> (dirOffset: Int, entries: [ImageEntry]) {
        guard data.count > 0x200, Array(data[0..<stopSignPrefix.count]) == stopSignPrefix else {
            throw FirmwareError("Missing Apple STOP banner: this is not an iPod firmware partition.")
        }
        guard Array(data[0x100..<0x104]) == Array("]ih[".utf8) else {
            throw FirmwareError("Bad firmware directory magic (expected ']ih[').")
        }
        let dirOffset = Int(le32(data, 0x104)) + 0x200
        var entries: [ImageEntry] = []
        var p = dirOffset
        let tags = [Array("!ATA".utf8), Array("DNAN".utf8)]
        while p + 40 <= data.count, tags.contains(Array(data[p..<p + 4])), entries.count < 10 {
            entries.append(ImageEntry(
                index: entries.count, dev: Array(data[p..<p + 4]), type: Array(data[p + 4..<p + 8]),
                id: le32(data, p + 8), devOffset: le32(data, p + 12), length: le32(data, p + 16),
                addr: le32(data, p + 20), entryOffset: le32(data, p + 24), chksum: le32(data, p + 28),
                vers: le32(data, p + 32), loadAddr: le32(data, p + 36)))
            p += 40
        }
        return (dirOffset, entries)
    }

    /// The model code of the iPod Video (5G and 5.5G). iPodFirm supports only this model.
    public static let videoModelCode: UInt32 = 0xB0

    /// The model code in the osos directory entry, also if an image checksum is incorrect.
    /// The value is nil if the directory cannot be read.
    public static func modelCode(in data: [UInt8]) -> UInt32? {
        guard let osos = try? readDirectory(data).entries.first(where: { $0.name == "osos" }) else { return nil }
        return osos.vers >> 8
    }

    /// The firmware of an iPod with a Samsung CPU: the iPod classic and the iPod nano 3G and later.
    /// These iPods use 4096-byte sectors, thus the directory is at the value at 0x104 + 0x1000, not
    /// + 0x200. Their osos starts with an "87xx" image header (for example "8702"). The body is
    /// encrypted and signed, so iPodFirm cannot change it. Refer to re/ipod-classic-6g.md.
    /// The result is the header tag, "unknown" if the header is not readable, or nil for other firmware.
    public static func samsungImageHeader(in data: [UInt8]) -> String? {
        guard data.count > 0x200, Array(data[0..<stopSignPrefix.count]) == stopSignPrefix,
              Array(data[0x100..<0x104]) == Array("]ih[".utf8) else { return nil }
        // A directory at the iPod Video position means a PortalPlayer firmware.
        if let video = try? readDirectory(data), !video.entries.isEmpty { return nil }
        let tags = [Array("!ATA".utf8), Array("DNAN".utf8)]
        var p = Int(le32(data, 0x104)) + 0x1000
        for _ in 0..<10 {
            guard p + 40 <= data.count, tags.contains(Array(data[p..<p + 4])) else { return nil }
            if Array(data[p + 4..<p + 8]) == Array("soso".utf8) {
                let at = Int(le32(data, p + 12))       // the image header is at devOffset
                guard at + 4 <= data.count else { return "unknown" }
                let tag = Array(data[at..<at + 4])
                let isTag = tag[0] == UInt8(ascii: "8") && tag[1] == UInt8(ascii: "7") && tag[2...].allSatisfy { (0x30...0x39).contains($0) }
                return isTag ? String(decoding: tag, as: UTF8.self) : "unknown"
            }
            p += 40
        }
        return nil
    }

    static func samsungError(_ header: String, code: String?) -> FirmwareError {
        FirmwareError("This firmware is for an iPod classic or an iPod nano 3G or later (Samsung CPU, image header \"\(header)\"). "
                      + "Its firmware is encrypted and signed. iPodFirm cannot change it. iPodFirm supports only the iPod Video (5G/5.5G).",
                      code: code)
    }

    public var modelCode: UInt32 { ((try? entry("osos").vers) ?? 0) >> 8 }

    public var isVideo: Bool { modelCode == Self.videoModelCode }

    public var model: String {
        let v = (try? entry("osos").vers) ?? 0
        return models[v >> 8] ?? String(format: "unknown (0x%x)", v)
    }

    public func entry(_ name: String) throws -> ImageEntry {
        guard let e = entries.first(where: { $0.name == name }) else { throw FirmwareError("No \(name) image.") }
        return e
    }

    public func has(_ name: String) -> Bool { entries.contains { $0.name == name } }

    public func imageRange(_ name: String) throws -> Range<Int> {
        let e = try entry(name)
        let start = imageBase + Int(e.devOffset)
        return start..<start + Int(e.length)
    }

    public func image(_ name: String) throws -> [UInt8] { Array(data[try imageRange(name)]) }

    /// Take the data and the directory of another partition.
    ///
    /// The function is for the repair of a partition, for example the restore of
    /// the hibernation image. The function changes the whole partition.
    public func replace(with other: FirmwarePartition) {
        data = other.data
        entries = other.entries
    }

    public func checksumOK(_ name: String) -> Bool {
        guard let e = try? entry(name), let r = try? imageRange(name), r.upperBound <= data.count else { return false }
        return byteSum(data[r]) == e.chksum
    }

    /// Length of Apple's own code in osos (an appended Rockbox bootloader is excluded).
    public var appleOSLength: Int {
        guard let e = try? entry("osos") else { return 0 }
        return Int(e.entryOffset != 0 ? e.entryOffset : e.length)
    }

    /// Images start at a multiple of 2048 bytes, as in Apple's files.
    static let imageAlign = 0x800

    /// The gap between the end of the image aupd and the start of the hibernation area.
    /// The research measured the gap in the backups of the owner. Refer to re/firmware-hibe.md.
    static let hibeGap = 0x1000

    /// The size of the header of a hibernation snapshot. The memory image starts after it.
    static let hibeHeader = 0x800

    /// Move rsrc if an osos of `ososLength` bytes does not fit before it.
    ///
    /// An iPod partition has free space after its last image: rsrc goes there, and aupd and hibe
    /// stay where they are. A firmware file has no free space: rsrc and the images after it move
    /// forward together and the file becomes longer. The content of the images does not change.
    /// The OS finds each image through the directory.
    ///
    /// An iPod can lose the entry of the image hibe and keep the hibernation area at its
    /// fixed place. The function then finds the area by the header of the snapshot and parks
    /// rsrc after the area. Refer to re/firmware-hibe.md.
    public func makeRoom(ososLength: Int) throws {
        let align = Self.imageAlign
        let osos = try entry("osos")
        let need = Int(osos.devOffset) + ososLength
        let later = entries.filter { $0.devOffset > osos.devOffset }.sorted { $0.devOffset < $1.devOffset }
        guard let first = later.first, Int(first.devOffset) < need else { return }
        guard first.name == "rsrc" else { throw FirmwareError("The image after osos is \(first.name); only rsrc can move.") }
        var rsrc = first
        let rsrcData = try image("rsrc")
        let lastEnd = (entries.map { Int($0.devOffset) + Int($0.length) }.max()! + align - 1) / align * align
        if imageBase + lastEnd + Int(rsrc.length) <= data.count {
            // an iPod partition: rsrc goes after the last image, and never over the
            // hibernation area of the iPod.
            var at = lastEnd
            if let area = hibeArea() {
                at = max(at, (area.devOffset + area.length + align - 1) / align * align)
            } else if data[imageBase + lastEnd..<imageBase + lastEnd + Int(rsrc.length)].contains(where: { $0 != 0 }) {
                throw FirmwareError("The space after the last image holds data that is not a hibernation area; restore the image hibe first.")
            }
            guard imageBase + at + Int(rsrc.length) <= data.count else {
                throw FirmwareError("There is no space for rsrc after the hibernation area.")
            }
            guard data[imageBase + at..<imageBase + at + Int(rsrc.length)].allSatisfy({ $0 == 0 }) else {
                throw FirmwareError("The space after the last image is not empty; rsrc cannot move there.")
            }
            data.replaceSubrange(imageBase + at..<imageBase + at + Int(rsrc.length), with: rsrcData)
            rsrc.devOffset = UInt32(at)
            writeEntry(rsrc)
            return
        }
        guard !has("hibe") else { throw FirmwareError("There is no space for rsrc after the last image, and hibe cannot move.") }
        guard data[(imageBase + lastEnd)...].allSatisfy({ $0 == 0 }) else {
            throw FirmwareError("The file has data after its last image; the images cannot move.")
        }
        // a firmware file: move rsrc and the images after it forward
        let delta = (need - Int(rsrc.devOffset) + align - 1) / align * align
        let moving = try later.map { ($0, try image($0.name)) }
        let size = imageBase + lastEnd + delta
        if data.count < size { data += [UInt8](repeating: 0, count: size - data.count) }
        for (e, _) in moving {
            let start = imageBase + Int(e.devOffset)
            data.replaceSubrange(start..<start + Int(e.length), with: [UInt8](repeating: 0, count: Int(e.length)))
        }
        for (e, img) in moving {
            var e = e
            e.devOffset += UInt32(delta)
            let start = imageBase + Int(e.devOffset)
            data.replaceSubrange(start..<start + img.count, with: img)
            writeEntry(e)
        }
    }

    /// The devOffset range of the hibernation area of this iPod, or nil.
    ///
    /// The area is the image hibe when the directory has the entry. Without the entry, the
    /// area starts at the end of the image aupd with a gap of 0x1000 bytes. A valid header
    /// of a snapshot gives the size of the area: the version 1, a page size that is a power
    /// of two of at least 0x1000, and the number of the pages. The area holds one megabyte
    /// of memory for each page: the memory of the iPod Video is 64 MB and the header gives
    /// 64 pages of 0x20000 bytes. The research proved this: the image hibe is 0x4000800
    /// bytes. Refer to re/firmware-hibe.md and re/firmware-hibernation.md.
    public func hibeArea() -> (devOffset: Int, length: Int)? {
        if let e = try? entry("hibe") { return (Int(e.devOffset), Int(e.length)) }
        guard let aupd = try? entry("aupd") else { return nil }
        let start = Int(aupd.devOffset) + Int(aupd.length) + Self.hibeGap
        let at = imageBase + start
        guard at + 0x14 <= data.count else { return nil }
        let version = le32(data, at), pageSize = le32(data, at + 4), pages = le32(data, at + 8)
        guard version == 1, pageSize >= 0x1000, pageSize & (pageSize - 1) == 0,
              pages > 0, pages <= 128 else { return nil }
        let length = Self.hibeHeader + (Int(pages) << 20)
        guard at + length <= data.count else { return nil }
        return (start, length)
    }

    /// Write the entry of the image hibe into the directory, without its data.
    ///
    /// The iPod writes the entry of the image hibe itself, through its boot code. The iPod
    /// can lose the entry and keep the hibernation area. The function writes the entry back:
    /// the fields come from the healthy partitions of the research, and the place and the
    /// size come from the hibernation area of this partition. The data of the area does not
    /// change: the area holds the memory of the iPod. Refer to re/firmware-hibe.md.
    public func addHibeEntry() throws {
        guard !has("hibe") else { throw FirmwareError("The partition already has the image hibe.") }
        guard let area = hibeArea() else {
            throw FirmwareError("The partition has no hibernation area for the image hibe.")
        }
        var entry = [UInt8](repeating: 0, count: 40)
        entry.replaceSubrange(0..<4, with: Array("!ATA".utf8))
        entry.replaceSubrange(4..<8, with: Array("ebih".utf8))
        put32(&entry, 8, 1)                        // the image id
        put32(&entry, 12, UInt32(area.devOffset))  // the place of the image
        put32(&entry, 16, UInt32(area.length))     // the size of the image
        put32(&entry, 20, 0x10000000)              // the load address in SDRAM
        put32(&entry, 24, 0)                       // the entry point
        put32(&entry, 28, 0)                       // the checksum: the image is not code
        put32(&entry, 32, 0)                       // the version
        put32(&entry, 36, 0xFFFFFFFF)              // the second load address
        let tags = [Array("!ATA".utf8), Array("DNAN".utf8)]
        for index in 0..<10 {
            let at = dirOffset + index * 40
            guard tags.contains(Array(data[at..<at + 4])) else {
                data.replaceSubrange(at..<at + 40, with: entry)
                if let reparsed = try? FirmwarePartition(data: data) { entries = reparsed.entries }
                return
            }
        }
        throw FirmwareError("The directory of the partition has no free entry.")
    }

    func writeEntry(_ e: ImageEntry) {
        entries[e.index] = e
        let at = dirOffset + e.index * 40
        data.replaceSubrange(at..<at + 40, with: e.packed)
    }

    /// Replace an image in place, updating len and checksum. aupd is always refused.
    public func replaceImage(_ name: String, with new: [UInt8]) throws {
        guard name != "aupd" else { throw FirmwareError("Refusing to modify aupd: it reflashes the NOR boot flash.") }
        var e = try entry(name)
        let start = imageBase + Int(e.devOffset)
        let following = entries.map { Int($0.devOffset) }.filter { $0 > Int(e.devOffset) }
        let end = following.min() ?? (data.count - imageBase)
        let room = end - Int(e.devOffset)
        guard new.count <= room else {
            throw FirmwareError("New \(name) (\(new.count) bytes) does not fit in the \(room) bytes available.")
        }
        let oldEnd = start + Int(e.length)
        data.replaceSubrange(start..<start + new.count, with: new)
        if start + new.count < oldEnd {
            data.replaceSubrange(start + new.count..<oldEnd, with: [UInt8](repeating: 0, count: oldEnd - start - new.count))
        }
        e.length = UInt32(new.count)
        e.chksum = byteSum(new)
        writeEntry(e)
    }
}
