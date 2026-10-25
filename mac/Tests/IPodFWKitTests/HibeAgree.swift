import Foundation
@testable import IPodFWKit
import XCTest

// The test checks that the Swift version and the Python version give the same
// result for the partition of the iPod of the owner. The test does not run
// without the folder Backups.
final class HibeAgreementTests: XCTestCase {
    func testSwiftAndPythonAgreeOnTheRealPartition() throws {
        let backups = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iPodFirm/Backups")
        guard FileManager.default.fileExists(atPath: backups.path) else {
            throw XCTSkip("The folder of the backups is not here.")
        }
        let newest = "2026-10-24 13.23.45 manual backup.bin"
        let data = [UInt8](try Data(contentsOf: backups.appendingPathComponent(newest)))
        let partition = try FirmwarePartition(data: data)
        let report = Hibe.check(partition)

        // The partition of the iPod has no entry for the image hibe, and the
        // hibernation area is intact at its fixed place. The Python version must
        // give the same result.
        XCTAssertFalse(report.present)
        XCTAssertFalse(report.ok)
        XCTAssertEqual(report.offset, 0xD43800)
        XCTAssertEqual(report.length, 0x4000800)
        XCTAssertEqual(report.staleBytes, 0)

        // The repair writes the entry only. The data of the area does not change.
        let out = try Hibe.restore(data)
        let fixed = try FirmwarePartition(data: out)
        XCTAssertTrue(fixed.has(Hibe.name))
        XCTAssertEqual(try fixed.entry(Hibe.name).devOffset, 0xD43800)
        XCTAssertEqual(try fixed.entry(Hibe.name).length, 0x4000800)
        // The area is byte for byte the same: the repair changes the directory only.
        XCTAssertEqual(Array(out[0xD44000..<0x4D44800]), Array(data[0xD44000..<0x4D44800]))
        // The space after the hibernation area is empty, thus the image rsrc can move.
        let lastEnd = 0x4D44000
        let start = fixed.imageBase + lastEnd
        XCTAssertFalse(out[start..<(start + 0x500800)].contains { $0 != 0 })
        // The space after the last image now holds the area, thus rsrc parks after it.
        var parked = try FirmwarePartition(data: out)
        try parked.makeRoom(ososLength: Int(parked.entry("osos").length) + 0x100000)
        XCTAssertEqual(try parked.entry("rsrc").devOffset, 0x4D44000)
    }
}
