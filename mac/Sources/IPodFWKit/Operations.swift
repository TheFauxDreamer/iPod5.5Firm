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
    @discardableResult
    public static func save(_ data: [UInt8], ipod: IPodDisk, reason: String, in dir: URL, owner: uid_t?) throws -> BackupInfo {
        let fw = try FirmwarePartition(data: data)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let now = Date()
        var names = ["\(stamp.string(from: now)) \(reason).bin"]
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(originalName).path) {
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
                                  model: fw.model, mediaName: ipod.mediaName, bytes: data.count, sha256: sha,
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
        let current = try FirmwarePartition(data: currentBytes)
        var newBytes = [UInt8](try Data(contentsOf: imageURL))
        guard newBytes.count <= currentBytes.count else {
            throw FirmwareError("The image (\(newBytes.count) bytes) is larger than the iPod's firmware partition (\(currentBytes.count)).")
        }
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
}
