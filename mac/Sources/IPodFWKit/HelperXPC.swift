import Foundation
import Security

// Shared between the app and the privileged helper daemon (registered with SMAppService).

public let helperMachService = "com.thefauxdreamer.ipodfirm.helper"
public let helperPlistName = "com.thefauxdreamer.ipodfirm.helper.plist"
public let appBundleIdentifier = "com.thefauxdreamer.ipodfirm"
/// Bump when the XPC protocol changes.
public let helperProtocolVersion = 3
/// The first protocol version with `readOSOS`.
public let helperReadVersion = 3

@objc public protocol HelperXPCProtocol {
    func status(reply: @escaping (Data) -> Void)
    func backup(disk: String, backupDir: String, reply: @escaping (Data) -> Void)
    /// Read only: writes the osos image of the iPod into `dir` (Operations.readOSOS).
    func readOSOS(disk: String, dir: String, reply: @escaping (Data) -> Void)
    func flash(disk: String, image: String, backupDir: String, reason: String, dryRun: Bool, reply: @escaping (Data) -> Void)
    func rescueRestore(disk: String, image: String, backupDir: String, dryRun: Bool, reply: @escaping (Data) -> Void)
}

public struct HelperStatus: Codable {
    public var version: Int
    public var hasFullDiskAccess: Bool
    public init(version: Int, hasFullDiskAccess: Bool) { self.version = version; self.hasFullDiskAccess = hasFullDiskAccess }
}

public enum HelperJSON {
    public static func encode<T: Encodable>(_ v: T) -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return (try? e.encode(v)) ?? Data()
    }
    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(t, from: d)
    }
}

/// The path with all symbolic links resolved. The end of the path need not exist.
/// Gives nil if a part of the path is a broken link.
func resolvedPath(_ path: String) -> String? {
    var head = URL(fileURLWithPath: path).standardizedFileURL
    var tail: [String] = []
    while true {
        if let real = realpath(head.path, nil) {
            defer { free(real) }
            return ([String(cString: real)] + tail).joined(separator: "/")
        }
        var info = stat()
        guard lstat(head.path, &info) != 0, head.path != "/" else { return nil }
        tail.insert(head.lastPathComponent, at: 0)
        head.deleteLastPathComponent()
    }
}

/// The folder for backups, if it is in `~/Library/Application Support/iPodFirm` of `home`.
/// The check resolves symbolic links. A link in the folder cannot send a write of root to a different location.
public func checkedBackupDirectory(_ path: String, home: String) throws -> URL {
    let appFolder = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/iPodFirm")
    guard let allowed = resolvedPath(appFolder.path), let real = resolvedPath(path), real.hasPrefix(allowed + "/") else {
        throw FirmwareError("Refusing to write backups outside \(appFolder.path).")
    }
    return URL(fileURLWithPath: real)
}

/// The owner, the mode, the flags and the ACL state of `path`, for a report. The call does not follow a link.
public func permissionState(_ path: String) -> String {
    var info = stat()
    guard lstat(path, &info) == 0 else { return "\(URL(fileURLWithPath: path).lastPathComponent): no item" }
    let acl = acl_get_link_np(path, ACL_TYPE_EXTENDED)
    defer { if let acl { acl_free(UnsafeMutableRawPointer(acl)) } }
    return "\(URL(fileURLWithPath: path).lastPathComponent): owner \(info.st_uid), mode \(String(info.st_mode & 0o7777, radix: 8)), "
        + "flags \(String(info.st_flags, radix: 16)), ACL \(acl == nil ? "no" : "yes")"
}

/// Give `~/Library/Application Support/iPodFirm` of `home` and all its items to `owner`, with write access to
/// each folder. Any other path is refused. Root does this work, so no step follows a symbolic link.
/// Gives the state of the main folders before the repair.
public func repairAppFolder(_ path: String, owner: uid_t, home: String) throws -> String {
    guard let realHome = resolvedPath(home), let real = resolvedPath(path),
          real == realHome + "/Library/Application Support/iPodFirm" else {
        throw FirmwareError("Refusing to repair \(path).")
    }
    let before = [real, real + "/Staging", real + "/Backups"].map(permissionState).joined(separator: "; ")
    var items = [real]
    let walk = FileManager.default.enumerator(atPath: real)
    while let item = walk?.nextObject() as? String { items.append(real + "/" + item) }
    var failures = 0
    for item in items {
        var info = stat()
        guard lstat(item, &info) == 0, lchown(item, owner, gid_t(UInt32.max)) == 0 else { failures += 1; continue }
        if info.st_mode & S_IFMT == S_IFDIR,
           fchmodat(AT_FDCWD, item, (info.st_mode & 0o7777) | S_IRWXU, AT_SYMLINK_NOFOLLOW) != 0 { failures += 1 }
    }
    guard failures == 0 else { throw FirmwareError("Cannot repair \(failures) of \(items.count) items. Before: \(before)") }
    return before
}

/// True if this process can read a file that only Full Disk Access unlocks.
public func processHasFullDiskAccess() -> Bool {
    guard let h = FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db") else { return false }
    try? h.close()
    return true
}

/// Team identifier of the running process's own code signature (nil if ad-hoc / unsigned).
public func ownTeamIdentifier() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as? [String: Any] else { return nil }
    return dict[kSecCodeInfoTeamIdentifier as String] as? String
}

/// Code-signing requirement for "signed by the same team, with this identifier".
public func signingRequirement(identifier: String, team: String) -> String {
    "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
}
