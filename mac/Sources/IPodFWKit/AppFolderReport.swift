import Foundation
import Security

// Facts for a fault report: the state of the app folder and the signature of the app.

/// The owner, the mode, the flags and the ACL state of `path`, for a report. The call does not follow a link.
public func permissionState(_ path: String) -> String {
    var info = stat()
    guard lstat(path, &info) == 0 else { return "\(URL(fileURLWithPath: path).lastPathComponent): no item" }
    let acl = acl_get_link_np(path, ACL_TYPE_EXTENDED)
    defer { if let acl { acl_free(UnsafeMutableRawPointer(acl)) } }
    return "\(URL(fileURLWithPath: path).lastPathComponent): owner \(info.st_uid), mode \(String(info.st_mode & 0o7777, radix: 8)), "
        + "flags \(String(info.st_flags, radix: 16)), ACL \(acl == nil ? "no" : "yes")"
}

/// Make and delete a small file in `dir`. A real write shows more than the mode: it also shows a block
/// of macOS. Gives "write ok", or the error of the system.
public func writeTest(_ dir: URL) -> String {
    let file = dir.appendingPathComponent(".write-test-\(UUID().uuidString)").path
    let fd = open(file, O_CREAT | O_EXCL | O_WRONLY, 0o600)
    guard fd >= 0 else { return "write fails: \(String(cString: strerror(errno))) (errno \(errno))" }
    close(fd)
    unlink(file)
    return "write ok"
}

/// The state of the app folder for a fault report: one line for each main folder, and the user of the app.
public func appFolderReport(_ appFolder: URL) -> [String] {
    var lines = [permissionState(appFolder.deletingLastPathComponent().path) + " (parent)"]
    for dir in [appFolder, appFolder.appendingPathComponent("Staging"), appFolder.appendingPathComponent("Backups")] {
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isFolder) && isFolder.boolValue
        lines.append(permissionState(dir.path) + (exists ? ", " + writeTest(dir) : ""))
    }
    return lines + ["App user \(getuid()), effective user \(geteuid())"]
}

/// The signing information of this program.
func ownSigningInformation() -> [String: Any]? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as? [String: Any] else { return nil }
    return dict
}

/// The signature of this program, for a fault report.
public func ownSignatureDescription() -> String {
    guard let info = ownSigningInformation(), let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value else { return "unknown" }
    let adHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    let hardened = flags & SecCodeSignatureFlags.runtime.rawValue != 0
    return "\(adHoc ? "ad-hoc" : "team \(info[kSecCodeInfoTeamIdentifier as String] ?? "none")"), hardened runtime: \(hardened)"
}
