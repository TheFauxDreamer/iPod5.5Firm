import Foundation

// The version on the About screen of the iPod (Settings > About).
// The firmware does not keep the text "1.3". FUN_0009ee70 makes a version object with
// "mov r1, #major" at 0x9ee90 and "mov r2, #minor<<4|fix" at 0x9ee94, and the object writes the text.
// The VisibleBuildID that the iPod sends to the computer uses other instructions. This change does not touch them.

public struct FirmwareVersion: Equatable, CustomStringConvertible {
    public var major, minor, fix: Int

    static let majorAt = 0x9ee90, minorAt = 0x9ee94
    static let stockMajor: UInt32 = 0xe3a0_1001      // mov r1, #1
    static let stockMinor: UInt32 = 0xe3a0_2030      // mov r2, #0x30

    public static let stock = FirmwareVersion(major: 1, minor: 3, fix: 0)

    public init(major: Int, minor: Int, fix: Int) {
        self.major = major; self.minor = minor; self.fix = fix
    }

    /// "1.3" or "1.3.1". The major number is 0–255. The minor number and the fix number are 0–15.
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let n = parts.compactMap { Int($0) }
        guard n.count == parts.count, (0...255).contains(n[0]), n.dropFirst().allSatisfy({ (0...15).contains($0) }) else { return nil }
        self.init(major: n[0], minor: n[1], fix: n.count == 3 ? n[2] : 0)
    }

    /// The text that the iPod shows: the firmware leaves out the fix number when it is 0.
    public var description: String { fix == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(fix)" }

    /// Writes the version into the two instructions. The osos must have the Apple instructions there.
    public static func apply(_ v: FirmwareVersion, to osos: inout [UInt8]) throws {
        guard osos.count > minorAt + 4, le32(osos, majorAt) == stockMajor, le32(osos, minorAt) == stockMinor else {
            throw PatchError("The version instructions at 0x9ee90 are not the instructions of the Apple firmware 1.3. The version is not changed.")
        }
        put32(&osos, majorAt, 0xe3a0_1000 | UInt32(v.major))
        put32(&osos, minorAt, 0xe3a0_2000 | UInt32(v.minor << 4 | v.fix))
    }
}
