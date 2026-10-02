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
        guard data.count > 0x200, Array(data[0..<stopSignPrefix.count]) == stopSignPrefix else {
            throw FirmwareError("Missing Apple STOP banner: this is not an iPod firmware partition.")
        }
        guard Array(data[0x100..<0x104]) == Array("]ih[".utf8) else {
            throw FirmwareError("Bad firmware directory magic (expected ']ih[').")
        }
        self.data = data
        formatVersion = le16(data, 0x10A)
        dirOffset = Int(le32(data, 0x104)) + 0x200

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
        self.entries = entries
        guard let osos = entries.first(where: { $0.name == "osos" }) else {
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

    /// Move rsrc if an osos of `ososLength` bytes does not fit before it.
    ///
    /// An iPod partition has free space after its last image: rsrc goes there, and aupd and hibe
    /// stay where they are. A firmware file has no free space: rsrc and the images after it move
    /// forward together and the file becomes longer. The content of the images does not change.
    /// The OS finds each image through the directory.
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
            // an iPod partition: put rsrc after the last image
            let at = imageBase + lastEnd
            guard data[at..<at + Int(rsrc.length)].allSatisfy({ $0 == 0 }) else {
                throw FirmwareError("The space after the last image is not empty; rsrc cannot move there.")
            }
            data.replaceSubrange(at..<at + Int(rsrc.length), with: rsrcData)
            rsrc.devOffset = UInt32(lastEnd)
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
