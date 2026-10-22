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
