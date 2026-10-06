import Foundation

// The version on the About screen of the iPod (Settings > About).
// The firmware does not keep the text "1.3". FUN_0009ee70 makes a version object with
// "mov r1, #major" at 0x9ee90 and "mov r2, #minor<<4|fix" at 0x9ee94, and the object writes the text.
// The VisibleBuildID that the iPod sends to the computer uses other instructions. This change does not touch them.
//
// The version object can add only the stage texts "d", "a", "b" or "fc" and a number (FUN_00188d94, table 0x4fc298).
// For letters, apply() writes a new body into FUN_0009ee70 that shows a fixed text.

public struct FirmwareVersion: Equatable, CustomStringConvertible {
    public var major, minor, fix: Int
    /// Letters a–z after the numbers, for example "abrs" for "1.3.1abrs". Empty: no letters.
    public var letters = ""

    static let majorAt = 0x9ee90, minorAt = 0x9ee94
    static let stockMajor: UInt32 = 0xe3a0_1001      // mov r1, #1
    static let stockMinor: UInt32 = 0xe3a0_2030      // mov r2, #0x30

    /// FUN_0009ee70 in the Apple firmware 1.3: 104 bytes.
    static let functionAt = 0x9ee70, textAt = 0x9eea0, functionEnd = 0x9eed8
    static let stockFunction = try! Patcher.hexBytes("10402de962df4de20040a0e10030a0e38000a0e300308de50030a0e108008de20110a0e33020a0e30fa803eb6420a0e324108de208008de2b9a703ebff20a0e388108de224008de2a2ceffeb0410a0e188008de27ed1ffeb08008de220a803eb62df8de21080bde8")
    static let cToPascal = 0x92948, pascalToText = 0x934c4

    /// The largest number of characters that the About screen shows on one line.
    public static let maxTextLength = 24

    public static let stock = FirmwareVersion(major: 1, minor: 3, fix: 0)

    public init(major: Int, minor: Int, fix: Int, letters: String = "") {
        self.major = major; self.minor = minor; self.fix = fix; self.letters = letters
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
    public var description: String { (fix == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(fix)") + letters }

    /// Writes the version into the firmware. The osos must have the Apple instructions there.
    /// Without letters, only the two mov instructions change. With letters, FUN_0009ee70 gets a new body.
    public static func apply(_ v: FirmwareVersion, to osos: inout [UInt8]) throws {
        if !v.letters.isEmpty { return try applyText(v.description, letters: v.letters, to: &osos) }
        guard osos.count > minorAt + 4, le32(osos, majorAt) == stockMajor, le32(osos, minorAt) == stockMinor else {
            throw PatchError("The version instructions at 0x9ee90 are not the instructions of the Apple firmware 1.3. The version is not changed.")
        }
        put32(&osos, majorAt, 0xe3a0_1000 | UInt32(v.major))
        put32(&osos, minorAt, 0xe3a0_2000 | UInt32(v.minor << 4 | v.fix))
    }

    /// The new body copies a C text into a Pascal text (FUN_00092948), then into the About string (FUN_000934c4),
    /// as the last two calls of the Apple function do.
    static func applyText(_ text: String, letters: String, to osos: inout [UInt8]) throws {
        guard letters.allSatisfy({ ("a"..."z").contains($0) }) else {
            throw PatchError("The version letters \"\(letters)\" are not valid. Use only the letters a–z.")
        }
        guard text.count <= maxTextLength else {
            throw PatchError("The version \"\(text)\" has more than \(maxTextLength) characters. The About screen cannot show it.")
        }
        guard osos.count >= functionEnd, Array(osos[functionAt..<functionEnd]) == stockFunction else {
            throw PatchError("The version function at 0x9ee70 is not the function of the Apple firmware 1.3. The version is not changed.")
        }
        func bl(_ at: Int, _ to: Int) -> UInt32 { 0xeb00_0000 | (UInt32(bitPattern: Int32((to - at - 8) >> 2)) & 0x00ff_ffff) }
        let code: [UInt32] = [
            0xe92d_4010,                                                    // push {r4, lr}
            0xe24d_df62,                                                    // sub sp, sp, #392
            0xe1a0_4000,                                                    // mov r4, r0
            0xe28f_0000 | UInt32(textAt - (functionAt + 12 + 8)),           // add r0, pc, #(text)
            0xe28d_1088,                                                    // add r1, sp, #136
            0xe3a0_20ff,                                                    // mov r2, #255
            bl(functionAt + 24, cToPascal),                                 // bl FUN_00092948
            0xe1a0_1004,                                                    // mov r1, r4
            0xe28d_0088,                                                    // add r0, sp, #136
            bl(functionAt + 36, pascalToText),                              // bl FUN_000934c4
            0xe28d_df62,                                                    // add sp, sp, #392
            0xe8bd_8010,                                                    // pop {r4, pc}
        ]
        for (i, w) in code.enumerated() { put32(&osos, functionAt + 4 * i, w) }
        var bytes = Array(text.utf8)
        bytes += Array(repeating: 0, count: functionEnd - textAt - bytes.count)
        osos.replaceSubrange(textAt..<functionEnd, with: bytes)
    }
}

