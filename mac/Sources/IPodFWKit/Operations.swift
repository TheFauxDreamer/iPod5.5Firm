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
    /// The size of the iPod disk in bytes. Backups from iPodFirm 0.1.28 and earlier do not have it.
    public var diskSize: Int64?
    /// The name of the iPod volume. It is nil if the volume was not mounted, and in older backups.
    public var ipodName: String?
    /// The patches in the iPodFirm list, for example "album-art 3.2". It is nil if the firmware has no
    /// list, and in older backups.
    public var patches: [String]?
    /// The version of the app that made the backup, for example "0.1.328". Older backups do not have it.
    public var appVersion: String?
    /// The build number of the app that made the backup.
    public var appBuild: String?
    /// The name of the app that made the backup, for example "iPodFirm No Artwork Test".
    public var appName: String?

    /// The app that made the backup, for example "v0.1.328" or "v0.1.322 No Artwork Test".
    public var appLabel: String? {
        guard let appVersion else { return nil }
        let test = appName.map { $0.hasPrefix("iPodFirm") ? String($0.dropFirst(8)) : " " + $0 } ?? ""
        return "v\(appVersion)\(test)"
    }
}

public enum Backups {
    public static let originalName = "Original (first backup).bin"
    /// `BackupInfo.model` of a backup taken from a damaged partition. Such a backup cannot be restored.
    public static let damagedModel = "damaged"

    /// The names and the versions of the patches in the iPodFirm list of `osos`, or nil if it has no list.
    public static func patchNames(osos: [UInt8]) -> [String]? {
        FirmwareManifest.read(osos: osos)?.patches.map { [$0.name, $0.version].compactMap { $0 }.joined(separator: " ") }
    }

    static var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }

    /// Record the app in each backup from `since` or later that has no app in its metadata.
    /// This also applies after a flash that failed.
    public static func recordApp(version: String, build: String?, name: String?, in dir: URL, since: Date) throws {
        // The metadata keeps only full seconds.
        let start = since.addingTimeInterval(-1)
        for var info in list(in: dir) where info.created >= start && info.appVersion == nil {
            info.appVersion = version
            info.appBuild = build
            info.appName = name
            try encoder.encode(info).write(to: dir.appendingPathComponent(info.file + ".json"), options: .atomic)
        }
    }

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
    public static func save(_ data: [UInt8], ipod: IPodDisk, reason: String, in dir: URL,
                            damaged: Bool = false) throws -> BackupInfo {
        var model = damagedModel
        var patches: [String]?
        if !damaged {
            let partition = try FirmwarePartition(data: data)
            guard partition.isVideo else { throw Operations.unsupported(partition.model) }
            model = partition.model
            patches = (try? partition.image("osos")).flatMap(patchNames)
        }
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
        let enc = encoder
        var last: BackupInfo?
        for name in names {
            let url = dir.appendingPathComponent(name)
            try Data(data).write(to: url, options: .atomic)
            // read back: a backup we cannot trust is worse than none
            guard try Data(contentsOf: url) == Data(data) else { throw FirmwareError("Backup \(name) did not read back correctly.") }
            let info = BackupInfo(file: name, created: now, reason: name == originalName ? "original" : reason,
                                  model: model, mediaName: ipod.mediaName, bytes: data.count, sha256: sha,
                                  isOriginal: name == originalName, diskSize: ipod.size,
                                  ipodName: ipod.volumeName, patches: patches)
            let meta = dir.appendingPathComponent(name + ".json")
            try enc.encode(info).write(to: meta, options: .atomic)
            last = info
        }
        return last!
    }
}

/// The result of an operation on the iPod.
public struct OperationResult {
    /// The firmware partition on the iPod does not parse (e.g. after an interrupted write): use rescueRestore.
    public static let firmwareUnreadable = "firmware-unreadable"
    /// The iPod is not an iPod Video (5G/5.5G), for example an iPod classic.
    public static let unsupportedIPod = "unsupported-ipod"
    public var ok: Bool
    public var message: String
    public var code: String?
    public var ranges: [FirmwareFlasher.WriteRange]?
    public var backup: BackupInfo?
    /// On a fault: the error of the operation.
    public var fault: Error?
    public init(ok: Bool, message: String, code: String? = nil, ranges: [FirmwareFlasher.WriteRange]? = nil, backup: BackupInfo? = nil) {
        self.ok = ok; self.message = message; self.code = code; self.ranges = ranges; self.backup = backup
    }

    /// The result of a fault in an operation.
    public init(failure error: Error) {
        self.init(ok: false, message: error.localizedDescription, code: (error as? FirmwareError)?.code)
        fault = error
    }
    /// The fault as an error.
    public func failure(file: String = #fileID, line: Int = #line, function: String = #function) -> Error {
        fault ?? FirmwareError(message, code: code, file: file, line: line, function: function)
    }
}

public enum Operations {
    static func unsupported(_ model: String) -> FirmwareError {
        FirmwareError("This iPod is not an iPod Video (5G/5.5G). Its firmware is for the model \"\(model)\". iPodFirm supports only the iPod Video.",
                      code: OperationResult.unsupportedIPod)
    }

    /// Stop if the directory on the iPod is readable and shows a different model.
    /// An iPod classic has its directory at a different position. Without this first test, it looks
    /// like an iPod Video with damaged firmware, and the app offers the rescue restore.
    static func checkModel(onIPod bytes: [UInt8]) throws {
        if let header = FirmwarePartition.samsungImageHeader(in: bytes) {
            throw FirmwarePartition.samsungError(header, code: OperationResult.unsupportedIPod)
        }
        if let code = FirmwarePartition.modelCode(in: bytes), code != FirmwarePartition.videoModelCode {
            throw unsupported(models[code] ?? String(format: "unknown (0x%x)", code))
        }
    }

    static func readCurrent(_ ipod: IPodDisk, _ access: DiskAccess) throws -> (bytes: [UInt8], start: Int) {
        AppLog.step("Read the firmware partition of \(ipod.disk) (\(ipod.mediaName), \(ipod.size) bytes, block size \(ipod.blockSize))")
        let disk = try access.read(ipod)
        let (start, size) = try FirmwareFlasher.locatePartition(disk)
        let bytes = try disk.read(start, size)
        AppLog.step("Layout of the iPod:\n\(layoutReport(bytes))")
        return (bytes, start)
    }

    /// The directory and the map of the partition for a report. A damaged partition gives only a note.
    static func layoutReport(_ bytes: [UInt8]) -> String {
        guard let p = try? FirmwarePartition(data: bytes) else { return "The directory is not readable (\(bytes.count) bytes)." }
        return p.layoutDescription + "\n" + p.dataMap
    }

    public static func backup(_ ipod: IPodDisk, to dir: URL, access: DiskAccess = .direct) throws -> OperationResult {
        let (bytes, _) = try readCurrent(ipod, access)
        try checkModel(onIPod: bytes)
        let info = try Backups.save(bytes, ipod: ipod, reason: "manual backup", in: dir)
        return OperationResult(ok: true, message: "Backed up \(bytes.count / 1_048_576) MB firmware partition.", backup: info)
    }

    /// Read the osos image of the iPod. Nothing is written to the iPod. The app reads the iPodFirm list and
    /// the patches from the image. `layout` is the directory and the map of the partition.
    public static func readOSOS(_ ipod: IPodDisk, access: DiskAccess = .direct) throws -> (osos: [UInt8], layout: String) {
        let (bytes, _) = try readCurrent(ipod, access)
        try checkModel(onIPod: bytes)
        do { return (try FirmwarePartition(data: bytes).image("osos"), layoutReport(bytes)) } catch {
            throw FirmwareError("The firmware on the iPod is damaged (\(error.localizedDescription)).",
                                code: OperationResult.firmwareUnreadable, cause: error)
        }
    }

    /// Flash `imageURL` onto the iPod. Always backs up the current partition first (unless dryRun).
    public static func flash(_ ipod: IPodDisk, image imageURL: URL, backupDir: URL, reason: String,
                             dryRun: Bool, access: DiskAccess = .direct) throws -> OperationResult {
        let (currentBytes, partStart) = try readCurrent(ipod, access)
        try checkModel(onIPod: currentBytes)
        let current: FirmwarePartition
        do { current = try FirmwarePartition(data: currentBytes) } catch {
            throw FirmwareError("The firmware on the iPod is damaged (\(error.localizedDescription)). Use the rescue restore.",
                                code: OperationResult.firmwareUnreadable, cause: error)
        }
        AppLog.step("Flash (\(reason)): read the new image \(imageURL.lastPathComponent)")
        var newBytes = [UInt8](try Data(contentsOf: imageURL))
        guard newBytes.count <= currentBytes.count else {
            throw FirmwareError("The image (\(newBytes.count) bytes) is larger than the iPod's firmware partition (\(currentBytes.count)).")
        }
        AppLog.step("Flash: fit the layout of \(newBytes.count) bytes to the iPod (\(currentBytes.count) bytes)")
        newBytes = try FirmwareFlasher.fitLayout(new: newBytes, current: current)
        try FirmwareFlasher.preserveHibernation(new: &newBytes, current: current)
        let new = try FirmwarePartition(data: newBytes)
        guard new.isVideo else { throw FirmwareError("The new firmware is for the model \"\(new.model)\", not for the iPod Video.") }
        try FirmwareFlasher.checkCompatible(current: current, new: new, label: "New firmware")

        let bs = ipod.blockSize
        if newBytes.count % bs != 0 {
            let tail = bs - newBytes.count % bs
            newBytes += currentBytes[newBytes.count..<min(currentBytes.count, newBytes.count + tail)]
        }
        let protected = current.has("aupd") ? try current.imageRange("aupd") : 0..<0
        AppLog.step("Flash: compare the new image with the iPod")
        let ranges = try FirmwareFlasher.planWrites(current: currentBytes, new: newBytes, blockSize: bs, protected: protected)
        if ranges.isEmpty { return OperationResult(ok: true, message: "The iPod already has this firmware; nothing to write.", ranges: []) }
        let total = ranges.reduce(0) { $0 + $1.length }
        if dryRun { return OperationResult(ok: true, message: "Would write \(total) bytes in \(ranges.count) range(s).", ranges: ranges) }

        // Ask first: if the user clicks Cancel, the iPod stays mounted.
        try access.authorizeWrite(ipod, partStart)
        // Mandatory backup of exactly what is about to be replaced.
        AppLog.step("Flash: back up the iPod before \(total) bytes in \(ranges.count) range(s)")
        let info = try Backups.save(currentBytes, ipod: ipod, reason: "before \(reason)", in: backupDir)

        AppLog.step("Unmount \(ipod.disk), then write \(ranges.count) range(s)")
        try Device.unmount(ipod)
        let disk = try access.write(ipod, partStart)
        for r in ranges {
            try disk.writeAligned(partStart + r.offset, newBytes[r.offset..<r.offset + r.length])
        }
        disk.sync()
        AppLog.step("Verify the written ranges")
        for r in ranges where try disk.read(partStart + r.offset, r.length) != Array(newBytes[r.offset..<r.offset + r.length]) {
            throw FirmwareError("Verification failed at partition offset 0x\(String(r.offset, radix: 16)). Restore the backup \"\(info.file)\".")
        }
        return OperationResult(ok: true, message: "Wrote and verified \(total) bytes in \(ranges.count) range(s).", ranges: ranges, backup: info)
    }

    /// Restore a backup to an iPod whose firmware partition no longer parses (an interrupted write).
    /// `flash` cannot do this: it checks the new image against the iPod's current firmware. Here the
    /// permanent original backup takes that role. Only the partition table must still be intact.
    public static func rescueRestore(_ ipod: IPodDisk, image imageURL: URL, backupDir: URL,
                                     dryRun: Bool, access: DiskAccess = .direct) throws -> OperationResult {
        let (currentBytes, partStart) = try readCurrent(ipod, access)
        try checkModel(onIPod: currentBytes)
        guard (try? FirmwarePartition(data: currentBytes)) == nil else {
            throw FirmwareError("The firmware on the iPod is not damaged. Use the normal restore.")
        }
        AppLog.step("Rescue: compare with the original backup, then restore \(imageURL.lastPathComponent)")
        let originalURL = backupDir.appendingPathComponent(Backups.originalName)
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            throw FirmwareError("There is no original backup to compare with. Restore the iPod with Finder.")
        }
        let original = try FirmwarePartition(contentsOf: originalURL)
        guard original.isVideo else {
            throw FirmwareError("The original backup is not from an iPod Video. Restore the iPod with Finder.")
        }
        guard original.data.count == currentBytes.count else {
            throw FirmwareError("The original backup is not from this iPod (the partition size is different). Restore the iPod with Finder.")
        }
        // The original backup is the same file for all iPods. The disk must agree with the disk of that backup.
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let meta = try? Data(contentsOf: backupDir.appendingPathComponent(Backups.originalName + ".json")),
           let info = try? dec.decode(BackupInfo.self, from: meta),
           info.mediaName != ipod.mediaName || (info.diskSize.map { $0 != ipod.size } ?? false) {
            throw FirmwareError("The original backup is not from this iPod (the disk is different). Restore the iPod with Finder.")
        }
        var newBytes = [UInt8](try Data(contentsOf: imageURL))
        let new: FirmwarePartition
        do { new = try FirmwarePartition(data: newBytes) } catch {
            throw FirmwareError("This backup is damaged too (\(error.localizedDescription)). Select a different backup.", cause: error)
        }
        guard new.isVideo else { throw FirmwareError("This backup is not from an iPod Video. Select a different backup.") }
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
        if ranges.isEmpty { return OperationResult(ok: true, message: "The iPod already has this firmware; nothing to write.", ranges: []) }
        let total = ranges.reduce(0) { $0 + $1.length }
        if dryRun { return OperationResult(ok: true, message: "Would write \(total) bytes in \(ranges.count) range(s).", ranges: ranges) }

        try access.authorizeWrite(ipod, partStart)
        let info = try Backups.save(currentBytes, ipod: ipod, reason: "before rescue", in: backupDir, damaged: true)

        AppLog.step("Unmount \(ipod.disk), then write \(ranges.count) range(s)")
        try Device.unmount(ipod)
        let disk = try access.write(ipod, partStart)
        for r in ranges {
            try disk.writeAligned(partStart + r.offset, newBytes[r.offset..<r.offset + r.length])
        }
        disk.sync()
        AppLog.step("Verify the written ranges")
        for r in ranges where try disk.read(partStart + r.offset, r.length) != Array(newBytes[r.offset..<r.offset + r.length]) {
            throw FirmwareError("Verification failed at partition offset 0x\(String(r.offset, radix: 16)). Try the rescue restore again, or restore the iPod with Finder.")
        }
        return OperationResult(ok: true, message: "Wrote and verified \(total) bytes in \(ranges.count) range(s).", ranges: ranges, backup: info)
    }
}
