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

    /// The drive sizes of the original iPod 5G and 5.5G, in GB (10^9 bytes, as Apple marks them).
    public static let originalHDDSizes = [30, 60, 80]

    /// The nominal size in GB if the capacity is within 5 GB of an original hard drive, else nil.
    /// A flash card of a near size (for example 64 GB) also gives a value: the result is "probably".
    public static func likelyOriginalHDD(size: Int64) -> Int? {
        originalHDDSizes.first { abs(size - Int64($0) * 1_000_000_000) <= 5_000_000_000 }
    }

    public var likelyOriginalHDD: Int? { Self.likelyOriginalHDD(size: size) }
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
    try diskutil(verb, args)
}

func diskutil(_ verb: String, _ args: [String]) throws -> [String: Any] {
    let data = try runTool("/usr/sbin/diskutil", [verb, "-plist"] + args)
    return (try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]) ?? [:]
}

public enum Device {
    /// The same command as the function `diskutil` above. The test uses it to compare
    /// the result of the detection with the result of the command.
    public static func diskutilForTest(_ verb: String, _ args: String...) throws -> [String: Any] {
        try diskutil(verb, args)
    }

    public static func findIPods() throws -> [IPodDisk] {
        let listing = try diskutil("list", "external", "physical")
        var found: [IPodDisk] = []
        // The entry of a whole disk in the list has no name on some iPods. The name is in
        // the info of the disk. The Python version (device.py) reads the name in the same way.
        for disk in listing["WholeDisks"] as? [String] ?? [] {
            let info = try diskutil("info", disk)
            let name = (info["MediaName"] as? String) ?? (info["IORegistryEntryName"] as? String) ?? ""
            guard name.lowercased().contains("ipod") else { continue }
            let volume = volumeName(in: listing, for: disk)
            found.append(IPodDisk(disk: disk, mediaName: name, blockSize: info["DeviceBlockSize"] as? Int ?? 512,
                                  size: (info["Size"] as? NSNumber)?.int64Value ?? 0, volumeName: volume))
        }
        return found
    }

    /// The name of the volume of a whole disk. The list of the disks has the name of the
    /// volume in the partitions of the disk.
    private static func volumeName(in listing: [String: Any], for disk: String) -> String? {
        let entries = listing["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        guard let entry = entries.first(where: { ($0["DeviceIdentifier"] as? String) == disk }) else { return nil }
        let partitions = entry["Partitions"] as? [[String: Any]] ?? []
        return partitions.compactMap { $0["VolumeName"] as? String }.first
    }

    public static func unmount(_ ipod: IPodDisk) throws {
        _ = try runTool("/usr/sbin/diskutil", ["unmountDisk", ipod.disk])
    }

    /// The maximum number of eject attempts, and the time between two attempts in seconds.
    static let ejectAttempts = 5
    static let ejectRetryDelay = 2.0

    /// Unmount all volumes of the iPod and eject it, as Finder does. Then the iPod can be disconnected.
    /// Spotlight (mds) often reads the volume after a write and stops the unmount. Thus the eject
    /// tries again after a short time. Other errors stop the eject immediately.
    public static func eject(_ ipod: IPodDisk) throws {
        for attempt in 1...ejectAttempts {
            do {
                _ = try runTool("/usr/sbin/diskutil", ["eject", ipod.disk])
                return
            } catch {
                let text = error.localizedDescription
                guard text.contains("dissented") || text.contains("could not be unmounted") else { throw error }
                if attempt < ejectAttempts { Thread.sleep(forTimeInterval: ejectRetryDelay) }
            }
        }
        throw FirmwareError("We were unable to eject your iPod. macOS is currently accessing it. Try again.")
    }
}

/// Find a MiMusic sync on the iPod. A firmware write unmounts the iPod volume and stops a sync.
public enum MusicAppCheck {
    /// The bundle identifier of MiMusic.
    public static let miMusicBundleID = "com.thefauxdreamer.MiMusic"

    /// The temporary files that MiMusic writes on the iPod during a sync. MiMusic renames each file after the write.
    public static let tempFiles = [
        "iPod_Control/iTunes/iTunesDB.tmp",
        "iPod_Control/Artwork/ArtworkDB.tmp",
        "iPod_Control/iTunes/iPodFirmAlbumArt.tmp",
    ]

    /// The temporary files of MiMusic that are on the volume now.
    public static func syncFiles(onVolume volume: URL) -> [String] {
        tempFiles.filter { FileManager.default.fileExists(atPath: volume.appendingPathComponent($0).path) }
    }
}

/// The settings file of the iPod, iPod_Control/Device/Preferences. The firmware loads it into its
/// settings with no check. A field at settings + X is at file offset X − 8 (re/shuffle.md).
public enum IPodPreferences {
    public static let path = "iPod_Control/Device/Preferences"
    /// The settings byte +0x93 ("shuffle the songs in each album too"), the Album Mix of the patch
    /// shuffle-album-mix.
    public static let albumMixOffset = 0x8b
    /// The file version of firmware 1.3.
    public static let version: UInt32 = 0x39

    /// true if `osos` has the patch shuffle-album-mix: the Shuffle item wraps after mode 3
    /// (`cmp r0, #3` at 0x191e9c).
    public static func hasAlbumMix(osos: [UInt8]) -> Bool {
        let at = 0x191e9c
        return osos.count >= at + 4 && osos[at..<at + 4].elementsEqual([0x03, 0x00, 0x50, 0xe3])
    }

    /// true if the firmware partition image at `image` has the patch shuffle-album-mix.
    public static func hasAlbumMix(partition image: URL) -> Bool {
        guard let p = try? FirmwarePartition(contentsOf: image), let osos = try? p.image("osos") else { return false }
        return hasAlbumMix(osos: osos)
    }

    /// Switch off Album Mix in the settings file on the mounted volume. A firmware without
    /// shuffle-album-mix still loads the byte, and then shuffles the songs in each album with no menu
    /// item to stop it. Albums stays Albums. Returns true if the file changed. The file stays as it
    /// is if it is missing, if it is shorter than the byte, or if its version is not 0x39.
    @discardableResult
    public static func clearAlbumMix(onVolume volume: URL) throws -> Bool {
        let url = volume.appendingPathComponent(path)
        guard let handle = try? FileHandle(forUpdating: url) else { return false }
        defer { try? handle.close() }
        let head = [UInt8](try handle.read(upToCount: albumMixOffset + 1) ?? Data())
        guard head.count > albumMixOffset,
              UInt32(head[0]) | UInt32(head[1]) << 8 | UInt32(head[2]) << 16 | UInt32(head[3]) << 24 == version,
              head[albumMixOffset] != 0 else { return false }
        try handle.seek(toOffset: UInt64(albumMixOffset))
        try handle.write(contentsOf: Data([0]))
        try handle.synchronize()
        return true
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
    /// position; aupd must be identical. rsrc can move (to make room for a larger osos), but
    /// it must not overlap osos, aupd or the hibernation area of the iPod. new may have one
    /// image more than current: the image hibe. The iPod can lose the entry of the image
    /// hibe (the research proved it: the entry was 36 bytes of zeros after the start that
    /// followed the flash of 23 October 2026), and a flash may bring the entry back. The
    /// extra image must be the image hibe at the place and with the size of the hibernation
    /// area of the iPod, so that the write adds the entry only.
    public static func checkCompatible(current: FirmwarePartition, new: FirmwarePartition, label: String) throws {
        guard current.imageBase == new.imageBase, current.dirOffset == new.dirOffset else {
            throw FirmwareError("\(label): partition layout differs from the iPod's.")
        }
        var cur = current.entries, nw = new.entries
        if !current.has("hibe"), new.has("hibe"), nw.count == cur.count + 1,
           let e = try? new.entry("hibe"), let area = current.hibeArea(),
           Int(e.devOffset) == area.devOffset, Int(e.length) == area.length {
            nw.removeAll { $0.name == "hibe" }
        }
        guard cur.count == nw.count else {
            throw FirmwareError("\(label): different number of firmware images than the iPod.")
        }
        for (c, n) in zip(cur, nw) {
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
            for (fw, name) in [(new, "osos"), (new, "aupd")] where fw.has(name) {
                if try fw.imageRange(name).overlaps(r) { throw FirmwareError("\(label): rsrc overlaps \(name); refusing.") }
            }
            // rsrc must not overlap the hibernation area of the iPod, with or without the entry.
            if let area = current.hibeArea() {
                let a = current.imageBase + area.devOffset
                if r.lowerBound < a + area.length && r.upperBound > a {
                    throw FirmwareError("\(label): rsrc overlaps the hibernation area; refusing.")
                }
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
    /// A firmware file has no image hibe and no free space after the last image. An iPod
    /// partition has the hibernation area: the area holds the space for a bigger osos, and
    /// the image rsrc goes after the area. The area is the image hibe when the directory
    /// has the entry. Without the entry, the area keeps its fixed place, and the function
    /// finds it by the header of the snapshot.
    ///
    /// The function always gives the layout of the iPod. The image aupd stays where the
    /// iPod has it. The image rsrc goes after the hibernation area of the iPod. The other
    /// images of the file come unchanged.
    ///
    /// The hibernation area of the iPod stays, with its data. When the file has the image
    /// hibe and the iPod does not, the iPod lost the entry: the function adds the entry of
    /// the file to the result and keeps the data of the iPod. The data of the file is a
    /// snapshot of another day, and the data of the iPod is the memory of the iPod now.
    ///
    /// The function must not return the file unchanged. A file with a hibernation area
    /// holds a snapshot of another day, and a flash of the file would put that snapshot
    /// over the snapshot of the iPod. Refer to re/firmware-hibe.md.
    public static func fitLayout(new newBytes: [UInt8], current: FirmwarePartition) throws -> [UInt8] {
        let new = try FirmwarePartition(data: newBytes)
        guard current.has("aupd"), new.has("aupd") else { return newBytes }
        let out = try FirmwarePartition(data: current.data)
        let osos = try new.image("osos")
        try out.makeRoom(ososLength: osos.count)
        try out.replaceImage("osos", with: osos)
        if new.has("rsrc"), out.has("rsrc") { try out.replaceImage("rsrc", with: new.image("rsrc")) }
        if new.has("hibe"), !out.has("hibe") {
            // The file has the entry of the image hibe and the iPod does not. The iPod
            // lost the entry. Add the entry at the place of the area of the iPod. The
            // data of the area of the iPod stays.
            let e = try new.entry("hibe")
            guard let area = out.hibeArea(),
                  Int(e.devOffset) == area.devOffset, Int(e.length) == area.length else {
                throw FirmwareError("The file has the image hibe at a different place than the hibernation area of the iPod; the file does not fit this iPod.")
            }
            try out.addHibeEntry()
        }
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
