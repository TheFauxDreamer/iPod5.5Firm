import Foundation

// Swift port of src/ipodfw/device.py: find iPods, locate the firmware
// partition (MBR or APM), and flash safely. Raw I/O needs root, so the app
// runs these through the bundled ipodfw-helper with administrator rights.

public struct IPodDisk: Codable, Identifiable, Hashable {
    public var id: String { disk }
    public var disk: String          // e.g. "disk4"
    public var mediaName: String
    public var blockSize: Int
    public var size: Int64
    public var volumeName: String?
    public var rawPath: String { "/dev/r\(disk)" }
}

func runTool(_ path: String, _ args: [String]) throws -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw FirmwareError("\(URL(fileURLWithPath: path).lastPathComponent) \(args.joined(separator: " ")) failed: \(msg)")
    }
    return data
}

func diskutil(_ verb: String, _ args: String...) throws -> [String: Any] {
    let data = try runTool("/usr/sbin/diskutil", [verb, "-plist"] + args)
    return (try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]) ?? [:]
}

public enum Device {
    public static func findIPods() throws -> [IPodDisk] {
        let listing = try diskutil("list", "external", "physical")
        var found: [IPodDisk] = []
        for entry in listing["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            guard let disk = entry["DeviceIdentifier"] as? String else { continue }
            let info = try diskutil("info", disk)
            let name = (info["MediaName"] as? String) ?? (info["IORegistryEntryName"] as? String) ?? ""
            guard name.lowercased().contains("ipod") else { continue }
            let volume = (entry["Partitions"] as? [[String: Any]])?.compactMap { $0["VolumeName"] as? String }.first
            found.append(IPodDisk(disk: disk, mediaName: name, blockSize: info["DeviceBlockSize"] as? Int ?? 512,
                                  size: (info["Size"] as? NSNumber)?.int64Value ?? 0, volumeName: volume))
        }
        return found
    }

    public static func unmount(_ ipod: IPodDisk) throws {
        _ = try runTool("/usr/sbin/diskutil", ["unmountDisk", ipod.disk])
    }
}

public protocol BlockReader {
    var blockSize: Int { get }
    func read(_ offset: Int, _ length: Int) throws -> [UInt8]
}

public final class RawDisk: BlockReader {
    public let blockSize: Int
    let fd: Int32

    public init(path: String, blockSize: Int, writable: Bool = false) throws {
        self.blockSize = blockSize
        fd = open(path, writable ? O_RDWR : O_RDONLY)
        guard fd >= 0 else {
            if errno == EPERM {
                throw FirmwareError("macOS blocked access to \(path). iPodFirm needs Full Disk Access to read and write the iPod's firmware partition.",
                                    code: HelperResult.fullDiskAccess)
            }
            throw FirmwareError("Cannot open \(path): \(String(cString: strerror(errno)))")
        }
    }

    deinit { close(fd) }

    public func read(_ offset: Int, _ length: Int) throws -> [UInt8] {
        let start = offset - offset % blockSize
        let end = (offset + length + blockSize - 1) / blockSize * blockSize
        var buf = [UInt8](repeating: 0, count: end - start)
        var pos = 0
        while pos < buf.count {
            let n = min(4 << 20, buf.count - pos)
            let got = buf.withUnsafeMutableBytes { pread(fd, $0.baseAddress! + pos, n, off_t(start + pos)) }
            guard got == n else { throw FirmwareError("Short read from disk at \(start + pos).") }
            pos += n
        }
        return Array(buf[(offset - start)..<(offset - start + length)])
    }

    public func writeAligned(_ offset: Int, _ data: ArraySlice<UInt8>) throws {
        guard offset % blockSize == 0, data.count % blockSize == 0 else { throw FirmwareError("Unaligned raw write.") }
        let written = data.withUnsafeBytes { pwrite(fd, $0.baseAddress!, data.count, off_t(offset)) }
        guard written == data.count else { throw FirmwareError("Short write at \(offset): \(String(cString: strerror(errno)))") }
    }

    public func sync() { fsync(fd) }
}

public enum FirmwareFlasher {
    /// (start, size) in bytes of the firmware partition.
    public static func locatePartition(_ disk: BlockReader) throws -> (start: Int, size: Int) {
        let bs = disk.blockSize
        let s0 = try disk.read(0, bs)
        if s0[510] == 0x55 && s0[511] == 0xAA {
            func part(_ i: Int) -> (type: UInt8, start: Int, count: Int) {
                let o = 0x1BE + 16 * i
                return (s0[o + 4], Int(le32(s0, o + 8)), Int(le32(s0, o + 12)))
            }
            let p0 = part(0), p1 = part(1)
            guard p0.type == 0, p0.count > 0, [0x0B, 0x0C].contains(p1.type) else {
                throw FirmwareError("The partition layout is not an iPod's (MBR).")
            }
            return (p0.start * bs, p0.count * bs)
        }
        if s0[0] == UInt8(ascii: "E") && s0[1] == UInt8(ascii: "R") {
            let mul = Int(s0[2]) / 2
            var blk = 1, count = 1
            while blk <= count {
                let e = try disk.read(blk * mul * 512, bs)
                guard e[0] == UInt8(ascii: "P"), e[1] == UInt8(ascii: "M") else { break }
                count = Int(be32(e, 4))
                if Array(e[48..<58]) == Array("Apple_MDFW".utf8) {
                    return (Int(be32(e, 8)) * bs, Int(be32(e, 12)) * bs)
                }
                blk += 1
            }
            throw FirmwareError("No Apple_MDFW firmware partition in the Apple partition map.")
        }
        throw FirmwareError("Unrecognised partition table.")
    }

    /// new may differ from current only in the osos/rsrc length and checksum, and in the rsrc
    /// position; aupd must be identical. rsrc can move (to make room for a larger osos), but it
    /// must not overlap osos, aupd or hibe.
    public static func checkCompatible(current: FirmwarePartition, new: FirmwarePartition, label: String) throws {
        guard current.imageBase == new.imageBase, current.dirOffset == new.dirOffset else {
            throw FirmwareError("\(label): partition layout differs from the iPod's.")
        }
        guard current.entries.count == new.entries.count else {
            throw FirmwareError("\(label): different number of firmware images than the iPod.")
        }
        for (c, n) in zip(current.entries, new.entries) {
            guard c.type == n.type, c.devOffset == n.devOffset || c.name == "rsrc" else {
                throw FirmwareError("\(label): image \(c.name) is at a different position than on the iPod.")
            }
            if !["osos", "rsrc", "hibe"].contains(c.name), c.packed != n.packed {
                throw FirmwareError("\(label): directory entry for \(c.name) differs from the iPod's.")
            }
        }
        if new.has("rsrc") {
            let r = try new.imageRange("rsrc")
            guard r.upperBound <= new.data.count else { throw FirmwareError("\(label): rsrc runs past the end of the image.") }
            for (fw, name) in [(new, "osos"), (new, "aupd"), (current, "hibe")] where fw.has(name) {
                if try fw.imageRange(name).overlaps(r) { throw FirmwareError("\(label): rsrc overlaps \(name); refusing.") }
            }
        }
        for name in ["osos", "rsrc"] where new.has(name) && !new.checksumOK(name) {
            throw FirmwareError("\(label): \(name) checksum does not verify.")
        }
        if current.has("aupd"), try current.image("aupd") != new.image("aupd") {
            throw FirmwareError("\(label): aupd (boot-flash updater) differs from the iPod's; refusing.")
        }
    }

    /// Put the osos and rsrc of a firmware file into the iPod's own layout.
    ///
    /// A firmware file that has a larger osos has rsrc and aupd moved forward (see makeRoom). On the
    /// iPod, aupd must stay where it is. For such a file, the result is the iPod's partition with the
    /// new osos and rsrc. A partition from an iPod (with hibe), or an image with aupd at the iPod's
    /// position, does not change: a restore writes the layout of the backup.
    public static func fitLayout(new newBytes: [UInt8], current: FirmwarePartition) throws -> [UInt8] {
        let new = try FirmwarePartition(data: newBytes)
        guard !new.has("hibe"), current.has("aupd"), new.has("aupd"),
              try new.entry("aupd").devOffset != current.entry("aupd").devOffset else { return newBytes }
        let out = try FirmwarePartition(data: current.data)
        let osos = try new.image("osos")
        try out.makeRoom(ososLength: osos.count)
        try out.replaceImage("osos", with: osos)
        if new.has("rsrc"), out.has("rsrc") { try out.replaceImage("rsrc", with: new.image("rsrc")) }
        return out.data
    }

    /// The hibernation image (hibe) is RAM state the iPod writes to itself while asleep. It belongs to
    /// the iPod, not to the firmware: copy the iPod's current hibe entry and data into the image being
    /// flashed so it is never written (and never rolled back to a stale snapshot).
    public static func preserveHibernation(new: inout [UInt8], current: FirmwarePartition) throws {
        guard current.has("hibe") else { return }
        let e = try current.entry("hibe")
        let at = current.dirOffset + e.index * 40
        guard at + 40 <= new.count else { return }
        new.replaceSubrange(at..<at + 40, with: current.data[at..<at + 40])
        let r = try current.imageRange("hibe")
        let lo = min(r.lowerBound, new.count), hi = min(r.upperBound, new.count, current.data.count)
        if lo < hi { new.replaceSubrange(lo..<hi, with: current.data[lo..<hi]) }
    }

    public struct WriteRange: Codable, Equatable {
        public var offset: Int
        public var length: Int
    }

    public static func planWrites(current: [UInt8], new: [UInt8], blockSize bs: Int, protected: Range<Int>) throws -> [WriteRange] {
        var ranges: [WriteRange] = []
        var off = 0
        while off < new.count {
            let end = min(off + bs, new.count)
            if current.count < end || current[off..<end] != new[off..<end] {
                if let last = ranges.last, last.offset + last.length == off {
                    ranges[ranges.count - 1].length += bs
                } else {
                    ranges.append(WriteRange(offset: off, length: bs))
                }
            }
            off += bs
        }
        for r in ranges where r.offset < protected.upperBound && r.offset + r.length > protected.lowerBound {
            throw FirmwareError("A planned write overlaps the aupd image; refusing.")
        }
        return ranges
    }
}
