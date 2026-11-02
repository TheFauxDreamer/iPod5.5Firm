import Foundation

// Swift port of src/ipodfw/device.py: find iPods, locate the firmware
// partition (MBR or APM), and flash safely. Only the open of the raw disk needs
// a privilege. The app gets the open disk from authopen (AuthOpen.swift).

public struct IPodDisk: Codable, Identifiable, Hashable {
    public var id: String { disk }
    public var disk: String          // e.g. "disk4"
    public var mediaName: String
    public var blockSize: Int
    public var size: Int64
    public var volumeName: String?
    public var rawPath: String { "/dev/r\(disk)" }

    /// The keys of the SysInfo file that a report can show. The file also holds the serial number and
    /// the FireWire GUID, thus each other key is left out.
    static let reportSysInfoKeys = ["ModelNumStr", "visibleBuildID", "BoardHwName"]

    /// The allowed lines of the text of a SysInfo file, in words for a report.
    static func reportSysInfo(_ text: String) -> String {
        var found: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, reportSysInfoKeys.contains(parts[0]) { found[parts[0]] = String(parts[1].prefix(40)) }
        }
        let shown = reportSysInfoKeys.compactMap { key in found[key].map { "\(key) \($0)" } }
        return shown.isEmpty ? "SysInfo: no model data" : "SysInfo: " + shown.joined(separator: ", ")
    }

    /// The model data of `iPod_Control/Device/SysInfo` on the mounted volume, for a report.
    public var sysInfoReport: String {
        guard let volumeName else { return "SysInfo: none" }
        let file = URL(fileURLWithPath: "/Volumes").appendingPathComponent(volumeName).appendingPathComponent("iPod_Control/Device/SysInfo")
        guard let data = try? Data(contentsOf: file) else { return "SysInfo: none" }
        return Self.reportSysInfo(String(decoding: data, as: UTF8.self))
    }

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

    /// The slice of the firmware partition that starts at byte `start`, or nil if the disk has no such
    /// slice. An iPod in the Mac format has an Apple_MDFW slice. A firmware partition with MBR type 0 can
    /// have no slice. A slice at a different position is a fault: the app must not write to it.
    static func firmwareSlice(_ partitions: [(id: String, content: String, offset: Int?)], start: Int) throws -> String? {
        guard let slice = partitions.first(where: { $0.content == "Apple_MDFW" }) else { return nil }
        guard slice.offset == start else {
            throw FirmwareError("The firmware slice \(slice.id) is not at the position in the partition map.")
        }
        return slice.id
    }

    /// The slice of the firmware partition of `ipod`. Refer to `firmwareSlice(_:start:)`.
    public static func firmwareSlice(_ ipod: IPodDisk, start: Int) throws -> String? {
        let listing = try diskutil("list", ipod.disk)
        let disks = listing["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        let partitions = try (disks.first?["Partitions"] as? [[String: Any]] ?? []).compactMap { p -> (id: String, content: String, offset: Int?)? in
            guard let id = p["DeviceIdentifier"] as? String, let content = p["Content"] as? String else { return nil }
            guard content == "Apple_MDFW" else { return (id, content, nil) }
            return (id, content, (try diskutil("info", id))["PartitionMapPartitionOffset"] as? Int)
        }
        return try firmwareSlice(partitions, start: start)
    }

    /// Unmount all volumes of the iPod before a write to the firmware partition. A busy volume
    /// gets the same attempts as the eject.
    public static func unmount(_ ipod: IPodDisk) throws {
        try retryWhileBusy(["unmountDisk", ipod.disk], action: "unmount")
    }

    /// The maximum number of attempts, and the time between two attempts in seconds.
    static let ejectAttempts = 5
    static let ejectRetryDelay = 2.0

    /// The message when the iPod stays busy after all attempts. Spotlight or another app is
    /// still reading the iPod volume.
    public static func busyMessage(_ action: String) -> String {
        "The app could not \(action) your iPod. macOS is still accessing your iPod. Try again in a second."
    }

    /// True if the diskutil error says that a process uses the volume.
    static func isBusy(_ text: String) -> Bool {
        text.contains("dissented") || text.contains("could not be unmounted") ||
            text.localizedCaseInsensitiveContains("busy")
    }

    /// Unmount all volumes of the iPod and eject it, as Finder does. Then the iPod can be disconnected.
    public static func eject(_ ipod: IPodDisk) throws {
        try retryWhileBusy(["eject", ipod.disk], action: "eject")
    }

    /// Run diskutil. Spotlight (mds) often reads the volume after a write and stops the unmount.
    /// Thus a busy volume gets ejectAttempts attempts, ejectRetryDelay seconds apart. Other errors
    /// stop at once.
    static func retryWhileBusy(_ args: [String], action: String) throws {
        for attempt in 1...ejectAttempts {
            do {
                _ = try runTool("/usr/sbin/diskutil", args)
                return
            } catch {
                guard isBusy(error.localizedDescription) else { throw error }
                if attempt < ejectAttempts { Thread.sleep(forTimeInterval: ejectRetryDelay) }
            }
        }
        throw FirmwareError(busyMessage(action))
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

/// How an operation gets the raw disk. The app uses `authOpen`. The tests use `direct` with a disk image.
public struct DiskAccess {
    /// Open the whole disk for a read.
    public var read: (IPodDisk) throws -> RawDisk
    /// Ask for the permission to write. Call this before the unmount. `start` is the firmware partition.
    public var authorizeWrite: (IPodDisk, _ start: Int) throws -> Void
    /// Open the disk for a write. Call this after the unmount.
    public var write: (IPodDisk, _ start: Int) throws -> RawDisk

    public init(read: @escaping (IPodDisk) throws -> RawDisk, authorizeWrite: @escaping (IPodDisk, Int) throws -> Void,
                write: @escaping (IPodDisk, Int) throws -> RawDisk) {
        self.read = read; self.authorizeWrite = authorizeWrite; self.write = write
    }

    /// The caller already has the right to open the disk.
    public static let direct = DiskAccess(read: { try RawDisk(path: $0.rawPath, blockSize: $0.blockSize) },
                                          authorizeWrite: { _, _ in },
                                          write: { ipod, _ in try RawDisk(path: ipod.rawPath, blockSize: ipod.blockSize, writable: true) })

    /// macOS asks for the password, and `authopen` opens the disk. The password is good for all the opens in
    /// a short time. A write goes to the firmware slice if the iPod has one, because a read-write open of the
    /// whole disk gives EBUSY while a volume is mounted.
    public static func authOpen(_ auth: AuthOpen = .shared) -> DiskAccess {
        let prompt = "iPodFirm needs an administrator password to read and write the firmware partition of your iPod."
        return DiskAccess(
            read: { ipod in
                try auth.authorize(paths: [ipod.rawPath], writable: false, prompt: prompt)
                return try RawDisk(descriptor: auth.open(path: ipod.rawPath, writable: false), blockSize: ipod.blockSize)
            },
            authorizeWrite: { ipod, start in
                let slice = try Device.firmwareSlice(ipod, start: start).map { "/dev/r\($0)" }
                try auth.authorize(paths: [slice ?? ipod.rawPath], writable: true, prompt: prompt)
            },
            write: { ipod, start in
                let slice = try Device.firmwareSlice(ipod, start: start).map { "/dev/r\($0)" }
                return try RawDisk(descriptor: auth.open(path: slice ?? ipod.rawPath, writable: true), blockSize: ipod.blockSize,
                                   origin: slice == nil ? 0 : start)
            })
    }
}

public final class RawDisk: BlockReader {
    public let blockSize: Int
    let fd: Int32
    /// The position of `fd` on the whole disk. All offsets of this class are positions on the whole disk.
    let origin: Int

    public init(path: String, blockSize: Int, writable: Bool = false) throws {
        self.blockSize = blockSize
        origin = 0
        fd = open(path, writable ? O_RDWR : O_RDONLY)
        guard fd >= 0 else {
            if errno == EPERM {
                throw FirmwareError("macOS blocked access to \(path). Turn on Full Disk Access for iPodFirm, then try again.")
            }
            throw FirmwareError("Cannot open \(path): \(String(cString: strerror(errno)))")
        }
    }

    /// Use an open descriptor. This object closes it. `origin` is the position of the descriptor on the disk.
    public init(descriptor: Int32, blockSize: Int, origin: Int = 0) {
        fd = descriptor
        self.blockSize = blockSize
        self.origin = origin
    }

    deinit { close(fd) }

    public func read(_ offset: Int, _ length: Int) throws -> [UInt8] {
        let start = offset - offset % blockSize
        let end = (offset + length + blockSize - 1) / blockSize * blockSize
        var buf = [UInt8](repeating: 0, count: end - start)
        var pos = 0
        while pos < buf.count {
            let n = min(4 << 20, buf.count - pos)
            let got = buf.withUnsafeMutableBytes { pread(fd, $0.baseAddress! + pos, n, off_t(start + pos - origin)) }
            guard got == n else { throw FirmwareError("Short read from disk at \(start + pos).") }
            pos += n
        }
        return Array(buf[(offset - start)..<(offset - start + length)])
    }

    public func writeAligned(_ offset: Int, _ data: ArraySlice<UInt8>) throws {
        guard offset % blockSize == 0, data.count % blockSize == 0 else { throw FirmwareError("Unaligned raw write.") }
        guard offset >= origin else { throw FirmwareError("A write before the firmware partition; refusing.") }
        let written = data.withUnsafeBytes { pwrite(fd, $0.baseAddress!, data.count, off_t(offset - origin)) }
        if written < 0, errno == EPERM {
            throw FirmwareError("macOS blocked the write to the iPod. Turn on Full Disk Access for iPodFirm, then try again.")
        }
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
    /// new osos and rsrc. When the file and the iPod differ in the hibe image, the result follows the
    /// iPod. An image that already agrees with the iPod does not change: a restore writes the layout
    /// of the backup.
    public static func fitLayout(new newBytes: [UInt8], current: FirmwarePartition) throws -> [UInt8] {
        let new = try FirmwarePartition(data: newBytes)
        AppLog.step("Layout of the new image:\n\(new.layoutDescription)")
        guard current.has("aupd"), new.has("aupd") else { return newBytes }
        guard new.has("hibe") == current.has("hibe"),
              try new.entry("aupd").devOffset == current.entry("aupd").devOffset else {
            // the file and the iPod differ: rebuild from the iPod's own partition
            let out = try FirmwarePartition(data: current.data)
            let osos = try new.image("osos")
            try out.makeRoom(ososLength: osos.count)
            try out.replaceImage("osos", with: osos)
            if new.has("rsrc"), out.has("rsrc") { try out.replaceImage("rsrc", with: new.image("rsrc")) }
            return out.data
        }
        return newBytes
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
