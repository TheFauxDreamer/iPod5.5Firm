import CryptoKit
import Foundation

/// Metadata written next to every backup (`<name>.bin.json`).
public struct BackupInfo: Codable, Identifiable, Hashable {
    public var id: String { file }
    public var file: String          // file name of the .bin inside the backup folder
    public var created: Date
    public var reason: String
    public var model: String
    public var mediaName: String
    public var bytes: Int
    public var sha256: String
    public var isOriginal: Bool
}

public enum Backups {
    public static let originalName = "Original (first backup).bin"
    /// `BackupInfo.model` of a backup taken from a damaged partition. Such a backup cannot be restored.
    public static let damagedModel = "damaged"

    public static func list(in dir: URL) -> [BackupInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? dec.decode(BackupInfo.self, from: Data(contentsOf: $0)) }
            .filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.file).path) }
            .sorted { $0.created > $1.created }
    }

    /// Save `data` as a new timestamped backup; also as the permanent original if none exists yet.
    /// A damaged partition is kept too (it is the iPod's last state), but never as the original.
    @discardableResult
    public static func save(_ data: [UInt8], ipod: IPodDisk, reason: String, in dir: URL, owner: uid_t?,
                            damaged: Bool = false) throws -> BackupInfo {
        let model = damaged ? damagedModel : try FirmwarePartition(data: data).model
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let now = Date()
        var names = ["\(stamp.string(from: now)) \(reason).bin"]
        if !damaged, !FileManager.default.fileExists(atPath: dir.appendingPathComponent(originalName).path) {
            names.insert(originalName, at: 0)
        }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        var last: BackupInfo?
        for name in names {
            let url = dir.appendingPathComponent(name)
            try Data(data).write(to: url, options: .atomic)
            // read back: a backup we cannot trust is worse than none
            guard try Data(contentsOf: url) == Data(data) else { throw FirmwareError("Backup \(name) did not read back correctly.") }
            let info = BackupInfo(file: name, created: now, reason: name == originalName ? "original" : reason,
                                  model: model, mediaName: ipod.mediaName, bytes: data.count, sha256: sha,
                                  isOriginal: name == originalName)
            let meta = dir.appendingPathComponent(name + ".json")
            try enc.encode(info).write(to: meta, options: .atomic)
            if let owner {
                chown(url.path, owner, gid_t(UInt32.max))
                chown(meta.path, owner, gid_t(UInt32.max))
            }
            last = info
        }
        if let owner { chown(dir.path, owner, gid_t(UInt32.max)) }
        return last!
    }
}

/// Result reported by the privileged helper (one JSON object on stdout).
public struct HelperResult: Codable {
    public static let fullDiskAccess = "full-disk-access"
    /// The firmware partition on the iPod does not parse (e.g. after an interrupted write): use rescueRestore.
    public static let firmwareUnreadable = "firmware-unreadable"
    public var ok: Bool
    public var message: String
    public var code: String?
    public var ranges: [FirmwareFlasher.WriteRange]?
    public var backup: BackupInfo?
    public init(ok: Bool, message: String, code: String? = nil, ranges: [FirmwareFlasher.WriteRange]? = nil, backup: BackupInfo? = nil) {
        self.ok = ok; self.message = message; self.code = code; self.ranges = ranges; self.backup = backup
    }
}

public enum Operations {
    static func readCurrent(_ ipod: IPodDisk) throws -> (bytes: [UInt8], start: Int) {
        let disk = try RawDisk(path: ipod.rawPath, blockSize: ipod.blockSize)
        let (start, size) = try FirmwareFlasher.locatePartition(disk)
        return (try disk.read(start, size), start)
    }

    public static func backup(_ ipod: IPodDisk, to dir: URL, owner: uid_t?) throws -> HelperResult {
        let (bytes, _) = try readCurrent(ipod)
        let info = try Backups.save(bytes, ipod: ipod, reason: "manual backup", in: dir, owner: owner)
        return HelperResult(ok: true, message: "Backed up \(bytes.count / 1_048_576) MB firmware partition.", backup: info)
    }

    /// Flash `imageURL` onto the iPod. Always backs up the current partition first (unless dryRun).
    public static func flash(_ ipod: IPodDisk, image imageURL: URL, backupDir: URL, reason: String,
                             dryRun: Bool, owner: uid_t?) throws -> HelperResult {
        let (currentBytes, partStart) = try readCurrent(ipod)
        let current: FirmwarePartition
        do { current = try FirmwarePartition(data: currentBytes) } catch {
            throw FirmwareError("The firmware on the iPod is damaged (\(error.localizedDescription)). Use the rescue restore.",
                                code: HelperResult.firmwareUnreadable)
        }
        var newBytes = [UInt8](try Data(contentsOf: imageURL))
        guard newBytes.count <= currentBytes.count else {
            throw FirmwareError("The image (\(newBytes.count) bytes) is larger than the iPod's firmware partition (\(currentBytes.count)).")
        }
        newBytes = try FirmwareFlasher.fitLayout(new: newBytes, current: current)
        try FirmwareFlasher.preserveHibernation(new: &newBytes, current: current)
        let new = try FirmwarePartition(data: newBytes)
        try FirmwareFlasher.checkCompatible(current: current, new: new, label: "New firmware")

        let bs = ipod.blockSize
        if newBytes.count % bs != 0 {
            let tail = bs - newBytes.count % bs
            newBytes += currentBytes[newBytes.count..<min(currentBytes.count, newBytes.count + tail)]
        }
        let protected = current.has("aupd") ? try current.imageRange("aupd") : 0..<0
        let ranges = try FirmwareFlasher.planWrites(current: currentBytes, new: newBytes, blockSize: bs, protected: protected)
        if ranges.isEmpty { return HelperResult(ok: true, message: "The iPod already has this firmware; nothing to write.", ranges: []) }
        let total = ranges.reduce(0) { $0 + $1.length }
        if dryRun { return HelperResult(ok: true, message: "Would write \(total) bytes in \(ranges.count) range(s).", ranges: ranges) }

        // Mandatory backup of exactly what is about to be replaced.
        let info = try Backups.save(currentBytes, ipod: ipod, reason: "before \(reason)", in: backupDir, owner: owner)

        try Device.unmount(ipod)
        let disk = try RawDisk(path: ipod.rawPath, blockSize: bs, writable: true)
        for r in ranges {
            try disk.writeAligned(partStart + r.offset, newBytes[r.offset..<r.offset + r.length])
        }
        disk.sync()
        for r in ranges where try disk.read(partStart + r.offset, r.length) != Array(newBytes[r.offset..<r.offset + r.length]) {
            throw FirmwareError("Verification failed at partition offset 0x\(String(r.offset, radix: 16)). Restore the backup \"\(info.file)\".")
        }
        return HelperResult(ok: true, message: "Wrote and verified \(total) bytes in \(ranges.count) range(s).", ranges: ranges, backup: info)
    }

    /// Restore a backup to an iPod whose firmware partition no longer parses (an interrupted write).
    /// `flash` cannot do this: it checks the new image against the iPod's current firmware. Here the
    /// permanent original backup takes that role. Only the partition table must still be intact.
    public static func rescueRestore(_ ipod: IPodDisk, image imageURL: URL, backupDir: URL,
                                     dryRun: Bool, owner: uid_t?) throws -> HelperResult {
        let (currentBytes, partStart) = try readCurrent(ipod)
        guard (try? FirmwarePartition(data: currentBytes)) == nil else {
            throw FirmwareError("The firmware on the iPod is not damaged. Use the normal restore.")
        }
        let originalURL = backupDir.appendingPathComponent(Backups.originalName)
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            throw FirmwareError("There is no original backup to compare with. Restore the iPod with Finder.")
        }
        let original = try FirmwarePartition(contentsOf: originalURL)
        guard original.data.count == currentBytes.count else {
            throw FirmwareError("The original backup is not from this iPod (the partition size is different). Restore the iPod with Finder.")
        }
        var newBytes = [UInt8](try Data(contentsOf: imageURL))
        let new: FirmwarePartition
        do { new = try FirmwarePartition(data: newBytes) } catch {
            throw FirmwareError("This backup is damaged too (\(error.localizedDescription)). Select a different backup.")
        }
        guard newBytes.count <= currentBytes.count else {
            throw FirmwareError("The backup (\(newBytes.count) bytes) is larger than the iPod's firmware partition (\(currentBytes.count)).")
        }
        // Same layout, valid checksums and an aupd identical to the one the iPod had at the first backup.
        try FirmwareFlasher.checkCompatible(current: original, new: new, label: "Backup")

        let bs = ipod.blockSize
        if newBytes.count % bs != 0 {
            let tail = bs - newBytes.count % bs
            newBytes += currentBytes[newBytes.count..<min(currentBytes.count, newBytes.count + tail)]
        }
        let protected = new.has("aupd") ? try new.imageRange("aupd") : 0..<0
        let ranges: [FirmwareFlasher.WriteRange]
        do { ranges = try FirmwareFlasher.planWrites(current: currentBytes, new: newBytes, blockSize: bs, protected: protected) } catch {
            throw FirmwareError("The damage includes the aupd area, which iPodFirm never writes. Restore the iPod with Finder.")
        }
        if ranges.isEmpty { return HelperResult(ok: true, message: "The iPod already has this firmware; nothing to write.", ranges: []) }
        let total = ranges.reduce(0) { $0 + $1.length }
        if dryRun { return HelperResult(ok: true, message: "Would write \(total) bytes in \(ranges.count) range(s).", ranges: ranges) }

        let info = try Backups.save(currentBytes, ipod: ipod, reason: "before rescue", in: backupDir, owner: owner, damaged: true)

        try Device.unmount(ipod)
        let disk = try RawDisk(path: ipod.rawPath, blockSize: bs, writable: true)
        for r in ranges {
            try disk.writeAligned(partStart + r.offset, newBytes[r.offset..<r.offset + r.length])
        }
        disk.sync()
        for r in ranges where try disk.read(partStart + r.offset, r.length) != Array(newBytes[r.offset..<r.offset + r.length]) {
            throw FirmwareError("Verification failed at partition offset 0x\(String(r.offset, radix: 16)). Try the rescue restore again, or restore the iPod with Finder.")
        }
        return HelperResult(ok: true, message: "Wrote and verified \(total) bytes in \(ranges.count) range(s).", ranges: ranges, backup: info)
    }
}
