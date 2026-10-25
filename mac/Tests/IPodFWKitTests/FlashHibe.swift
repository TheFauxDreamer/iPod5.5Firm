import Foundation
@testable import IPodFWKit
import XCTest

// The tests of the flash path and the hibernation area. The tests use the backups
// of the iPod of the owner. The tests do not run without the folder of the backups.
final class FlashHibeTests: XCTestCase {
    static var backups: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iPodFirm/Backups")
    }

    /// The broken partition of the iPod of the owner: no entry for the image hibe,
    /// but the hibernation area is intact at its fixed place.
    static func brokenPartition() throws -> [UInt8] {
        let broken = Self.backups.appendingPathComponent("2026-10-24 13.23.45 manual backup.bin")
        guard let data = try? [UInt8](Data(contentsOf: broken)) else {
            throw XCTSkip("The backup is not here.")
        }
        return data
    }

    /// Make a firmware file for the flash: the broken partition with a bigger osos.
    /// The file keeps the layout of the source, thus the function moves rsrc forward
    /// and aupd with it. The file has the entry of the image hibe when `withEntry`.
    static func makeFile(from data: [UInt8], withEntry: Bool) throws -> [UInt8] {
        // The source: the broken partition, with the entry written back when the
        // test wants a file with the entry.
        let source = withEntry ? try Hibe.restore(data) : data
        var fw = try FirmwarePartition(data: source)
        var osos = try fw.image("osos")
        osos += [UInt8](repeating: 0, count: 0x100000)
        try fw.makeRoom(ososLength: osos.count)
        try fw.replaceImage("osos", with: osos)
        return fw.data
    }

    func testTheFlasherKeepsTheImageHibeOfTheIPod() throws {
        let healthy = Self.backups.appendingPathComponent("Original (first backup).bin")
        guard let data = try? [UInt8](Data(contentsOf: healthy)) else { throw XCTSkip("The backup is not here.") }
        let current = try FirmwarePartition(data: data)
        XCTAssertTrue(current.has("hibe"))
        // A firmware file without the image hibe. The test uses the partition of the
        // first backup without the image hibe, which has the same layout.
        var file = data
        let at = current.dirOffset + (try current.entry("hibe")).index * 40
        file.replaceSubrange(at..<(at + 40), with: [UInt8](repeating: 0, count: 40))
        let new = try FirmwarePartition(data: file)
        XCTAssertFalse(new.has("hibe"))

        // The flash must give the layout of the iPod, with the image hibe.
        let out = try FirmwareFlasher.fitLayout(new: file, current: current)
        let fixed = try FirmwarePartition(data: out)
        XCTAssertTrue(fixed.has("hibe"))
        XCTAssertEqual(try fixed.image("hibe"), try current.image("hibe"))
        // The check of the compatibility must pass.
        XCTAssertNoThrow(try FirmwareFlasher.checkCompatible(current: current, new: fixed, label: "New firmware"))
    }

    func testTheFlasherParksRsrcOnAPartitionThatLostTheEntry() throws {
        // The iPod has no entry. The file has no entry. The flash parks rsrc
        // after the hibernation area, without the entry.
        let data = try Self.brokenPartition()
        let current = try FirmwarePartition(data: data)
        XCTAssertFalse(current.has("hibe"))
        XCTAssertEqual(current.hibeArea()?.devOffset, 0xD43800)
        XCTAssertEqual(current.hibeArea()?.length, 0x4000800)

        let file = try Self.makeFile(from: data, withEntry: false)
        let out = try FirmwareFlasher.fitLayout(new: file, current: current)
        let fixed = try FirmwarePartition(data: out)
        // The image rsrc goes after the hibernation area.
        XCTAssertEqual(try fixed.entry("rsrc").devOffset, 0x4D44000)
        XCTAssertFalse(fixed.has("hibe"))
        // The data of the area of the iPod did not change.
        XCTAssertEqual(Array(out[0xD44000..<0x4D44800]), Array(data[0xD44000..<0x4D44800]))
        // The check of the compatibility must pass.
        XCTAssertNoThrow(try FirmwareFlasher.checkCompatible(current: current, new: fixed, label: "New firmware"))
    }

    func testTheFlasherAddsTheEntryWhenTheFileHasIt() throws {
        // The iPod has no entry. The file has the entry. The flash adds the
        // entry at the place of the area and keeps the data of the iPod.
        let data = try Self.brokenPartition()
        let current = try FirmwarePartition(data: data)
        XCTAssertFalse(current.has("hibe"))

        let file = try Self.makeFile(from: data, withEntry: true)
        XCTAssertTrue(try FirmwarePartition(data: file).has("hibe"))
        let out = try FirmwareFlasher.fitLayout(new: file, current: current)
        let fixed = try FirmwarePartition(data: out)
        XCTAssertTrue(fixed.has("hibe"))
        XCTAssertEqual(try fixed.entry("hibe").devOffset, 0xD43800)
        XCTAssertEqual(try fixed.entry("hibe").length, 0x4000800)
        XCTAssertEqual(try fixed.entry("rsrc").devOffset, 0x4D44000)
        // The data of the area of the iPod did not change.
        XCTAssertEqual(Array(out[0xD44000..<0x4D44800]), Array(data[0xD44000..<0x4D44800]))
        XCTAssertNoThrow(try FirmwareFlasher.checkCompatible(current: current, new: fixed, label: "New firmware"))
    }
}
