import CryptoKit
import AppKit
import Foundation
@testable import IPodFWKit
import XCTest

final class BackupFolderTests: XCTestCase {
    func testBackupFolderCheckResolvesLinks() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let app = home.appendingPathComponent("Library/Application Support/iPodFirm")
        let outside = home.appendingPathComponent("outside")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: app.appendingPathComponent("link"), withDestinationURL: outside)

        // A folder in the app folder is permitted. The folder need not exist.
        XCTAssertNoThrow(try checkedBackupDirectory(app.appendingPathComponent("backups/new").path, home: home.path))
        // The folder after the link does not exist. The check must still see the link.
        XCTAssertThrowsError(try checkedBackupDirectory(app.appendingPathComponent("link/backups").path, home: home.path))
        try fm.createSymbolicLink(at: app.appendingPathComponent("broken"), withDestinationURL: outside.appendingPathComponent("none"))
        XCTAssertThrowsError(try checkedBackupDirectory(app.appendingPathComponent("broken/backups").path, home: home.path))
        XCTAssertThrowsError(try checkedBackupDirectory(app.appendingPathComponent("../other").path, home: home.path))
        XCTAssertThrowsError(try checkedBackupDirectory(outside.path, home: home.path))
    }
}

final class FlasherTests: XCTestCase {
    struct FakeDisk: BlockReader {
        var bytes: [UInt8]
        var blockSize: Int
        func read(_ offset: Int, _ length: Int) throws -> [UInt8] { Array(bytes[offset..<offset + length]) }
    }

    func testPlanWritesOnlyChangedBlocks() throws {
        let current = [UInt8](repeating: 1, count: 8192)
        var new = current
        new[5000] = 9
        XCTAssertEqual(try FirmwareFlasher.planWrites(current: current, new: new, blockSize: 512, protected: 0..<0),
                       [.init(offset: 4608, length: 512)])
    }

    func testPlanWritesRefusesAupdOverlap() {
        let current = [UInt8](repeating: 1, count: 8192)
        var new = current
        new[6000] = 9
        XCTAssertThrowsError(try FirmwareFlasher.planWrites(current: current, new: new, blockSize: 512, protected: 5632..<7000))
    }

    func testLocateMBR() throws {
        var d = [UInt8](repeating: 0, count: 4096)
        d[0x1BE + 4] = 0; put32(&d, 0x1BE + 8, 63); put32(&d, 0x1BE + 12, 1000)
        d[0x1CE + 4] = 0x0B; put32(&d, 0x1CE + 8, 1063); put32(&d, 0x1CE + 12, 9999)
        d[510] = 0x55; d[511] = 0xAA
        let r = try FirmwareFlasher.locatePartition(FakeDisk(bytes: d, blockSize: 512))
        XCTAssertEqual(r.start, 63 * 512); XCTAssertEqual(r.size, 1000 * 512)
    }

    func testHibernationImageIsPreserved() throws {
        guard let path = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        var stock = try IPSW.extractFirmware(URL(fileURLWithPath: path)).data
        // add a hibe entry + data like a real iPod's partition
        let dir = 0x4200 + 3 * 40, hibeOff = 0xd43800, hibeLen = 4096
        stock += [UInt8](repeating: 0, count: 2048 + hibeOff + hibeLen - stock.count)
        stock.replaceSubrange(dir..<dir + 8, with: Array("!ATAebih".utf8))
        put32(&stock, dir + 12, UInt32(hibeOff)); put32(&stock, dir + 16, UInt32(hibeLen))
        var onIPod = stock
        onIPod.replaceSubrange(2048 + hibeOff..<2048 + hibeOff + 16, with: [UInt8](repeating: 0xAB, count: 16))  // iPod slept since backup
        put32(&onIPod, dir + 28, 0x1234)
        let current = try FirmwarePartition(data: onIPod)
        var new = stock
        try FirmwareFlasher.preserveHibernation(new: &new, current: current)
        XCTAssertEqual(try FirmwarePartition(data: new).image("hibe"), try current.image("hibe"))
        try FirmwareFlasher.checkCompatible(current: current, new: FirmwarePartition(data: new), label: "t")
        XCTAssertEqual(try FirmwareFlasher.planWrites(current: onIPod, new: new, blockSize: 2048, protected: 0..<0), [])
    }

    func testRejectsNonFirmware() {
        XCTAssertThrowsError(try FirmwarePartition(data: [UInt8](repeating: 0, count: 8192)))
    }
}

/// Runs against Apple's real firmware when IPODFW_IPSW points at iPod_25.1.3.ipsw.
final class RealFirmwareTests: XCTestCase {
    func loadEditor() throws -> (FirmwareEditor, [UInt8]) {
        guard let path = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let (_, data) = try IPSW.extractFirmware(URL(fileURLWithPath: path))
        return (try FirmwareEditor(partition: FirmwarePartition(data: data)), data)
    }

    func testParseAndChecksums() throws {
        let (ed, _) = try loadEditor()
        XCTAssertEqual(ed.partition.imageBase, 2048)
        XCTAssertTrue(ed.partition.checksumOK("osos"))
        XCTAssertTrue(ed.partition.checksumOK("rsrc"))
        XCTAssertEqual(ed.blocks.count, 25)
        XCTAssertEqual(ed.pictures.count, 403)
        XCTAssertEqual(ed.strings(ed.mainBlock).first?.value, "January")
    }

    func testUnchangedRoundTripIsIdentical() throws {
        let (ed, data) = try loadEditor()
        for item in ed.pictures {
            // through PNG and back, exactly like a user's untouched file
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("p\(item.index).png")
            try ed.png(of: item)!.write(to: url)
            XCTAssertFalse(try ed.replacePicture(item, rgba: ImageCodec.rgba(ImageCodec.load(url))), "picture \(item.index)")
        }
        let values = Dictionary(uniqueKeysWithValues: ed.strings(ed.mainBlock).map { ($0.key, $0.value) })
        XCTAssertFalse(try ed.setStrings(blockIndex: ed.mainIndex, values))
        XCTAssertEqual(ed.partition.data, data)
    }

    func testEditsVerify() throws {
        let (ed, data) = try loadEditor()
        let item = ed.pictures[0]
        var px = ed.rgba(of: item)
        px[0] = 255; px[1] = 0; px[2] = 0
        XCTAssertTrue(try ed.replacePicture(item, rgba: px))
        XCTAssertThrowsError(try ed.setStrings(blockIndex: ed.mainIndex, ["129": "Januarius"]))   // no slack in 1.3
        XCTAssertTrue(try ed.setStrings(blockIndex: ed.mainIndex, ["129": "Januarius", "130": "Feb"]))
        let reparsed = try FirmwarePartition(data: ed.partition.data)
        XCTAssertTrue(reparsed.checksumOK("osos"))
        XCTAssertEqual(try reparsed.image("aupd"), try FirmwarePartition(data: data).image("aupd"))
        let ed2 = try FirmwareEditor(partition: reparsed)
        XCTAssertEqual(ed2.strings(ed2.mainBlock).first?.value, "Januarius")
        XCTAssertEqual(Array(ed2.rgba(of: ed2.pictures[0])[0..<3]), [255, 0, 0])
        XCTAssertThrowsError(try ed2.setStrings(blockIndex: ed2.mainIndex, ["131": String(repeating: "M", count: 4000)]))
    }
}

final class ModelCheckTests: XCTestCase {
    /// A small partition with one osos image. `vers` is the value in the directory entry.
    func partition(vers: UInt32) -> [UInt8] {
        var d = [UInt8](repeating: 0, count: 0x6000)
        d.replaceSubrange(0..<stopSignPrefix.count, with: stopSignPrefix)
        d.replaceSubrange(0x100..<0x104, with: Array("]ih[".utf8))
        put32(&d, 0x104, 0x4000)
        let dir = 0x4200, devOffset = 0x1000, length = 256
        d.replaceSubrange(dir..<dir + 8, with: Array("!ATAsoso".utf8))
        for i in 0..<length { d[2048 + devOffset + i] = UInt8(i & 0xFF) }
        put32(&d, dir + 12, UInt32(devOffset)); put32(&d, dir + 16, UInt32(length))
        put32(&d, dir + 28, byteSum(d[2048 + devOffset..<2048 + devOffset + length]))
        put32(&d, dir + 32, vers)
        return d
    }

    let ipod = IPodDisk(disk: "disk99", mediaName: "Test iPod", blockSize: 512, size: 1, volumeName: nil)

    func testVideoIsSupported() throws {
        let p = try FirmwarePartition(data: partition(vers: 0xB001))
        XCTAssertTrue(p.isVideo)
        XCTAssertNoThrow(try Operations.checkModel(onIPod: p.data))
    }

    func testOtherModelIsRefused() throws {
        let data = partition(vers: 0x1301)
        XCTAssertFalse(try FirmwarePartition(data: data).isVideo)
        XCTAssertThrowsError(try Operations.checkModel(onIPod: data)) {
            XCTAssertEqual(($0 as? FirmwareError)?.code, HelperResult.unsupportedIPod)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ipodfw-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try Backups.save(data, ipod: ipod, reason: "test", in: tmp, owner: nil)) {
            XCTAssertEqual(($0 as? FirmwareError)?.code, HelperResult.unsupportedIPod)
        }
        XCTAssertTrue(Backups.list(in: tmp).isEmpty)
    }

    /// A different model with an incorrect checksum is "unsupported", not "damaged": no rescue restore.
    func testOtherModelWithBadChecksumIsRefused() {
        var data = partition(vers: 0x1301)
        data[2048 + 0x1000] ^= 0xFF
        XCTAssertThrowsError(try FirmwarePartition(data: data))
        XCTAssertEqual(FirmwarePartition.modelCode(in: data), 0x13)
        XCTAssertThrowsError(try Operations.checkModel(onIPod: data)) {
            XCTAssertEqual(($0 as? FirmwareError)?.code, HelperResult.unsupportedIPod)
        }
    }

    /// Without a directory, the model is not known. The damaged-firmware path stays available.
    func testNoDirectoryGivesNoModel() {
        XCTAssertNil(FirmwarePartition.modelCode(in: [UInt8](repeating: 0, count: 0x6000)))
        XCTAssertNoThrow(try Operations.checkModel(onIPod: [UInt8](repeating: 0, count: 0x6000)))
    }

    /// A small partition with the layout of the iPod classic 6G firmware 1.1.2: the directory at
    /// 0x4000 + 0x1000, rsrc first, and an osos that starts with an "8702" image header.
    func classicPartition(header: String = "8702") -> [UInt8] {
        var d = [UInt8](repeating: 0, count: 0x8000)
        d.replaceSubrange(0..<stopSignPrefix.count, with: stopSignPrefix)
        d.replaceSubrange(0x100..<0x104, with: Array("]ih[".utf8))
        put32(&d, 0x104, 0x4000)
        let dir = 0x5000
        d.replaceSubrange(dir..<dir + 8, with: Array("!ATAcrsr".utf8))
        put32(&d, dir + 12, 0x6000); put32(&d, dir + 16, 0x100)
        d.replaceSubrange(dir + 40..<dir + 48, with: Array("!ATAsoso".utf8))
        put32(&d, dir + 52, 0x7000); put32(&d, dir + 56, 0x800); put32(&d, dir + 72, 0x13000)
        d.replaceSubrange(0x7000..<0x7008, with: Array(header.utf8) + Array("1.0".utf8) + [3])
        for i in 0x7800..<0x8000 { d[i] = UInt8((i * 7919) & 0xFF) }      // the "encrypted" body
        return d
    }

    /// The classic is "unsupported", not "damaged". Before this test existed, the helper offered the rescue restore.
    func testClassicIsRefusedAsUnsupported() {
        let data = classicPartition()
        XCTAssertEqual(FirmwarePartition.samsungImageHeader(in: data), "8702")
        XCTAssertNil(FirmwarePartition.modelCode(in: data))
        XCTAssertThrowsError(try Operations.checkModel(onIPod: data)) {
            XCTAssertEqual(($0 as? FirmwareError)?.code, HelperResult.unsupportedIPod)
            XCTAssertTrue($0.localizedDescription.contains("iPod classic"))
        }
    }

    /// An opened file gives a clear message, but no code: the code would mark the connected iPod as unsupported.
    func testOpenedClassicFileHasMessageButNoCode() {
        XCTAssertThrowsError(try FirmwarePartition(data: classicPartition())) {
            XCTAssertNil(($0 as? FirmwareError)?.code)
            XCTAssertTrue($0.localizedDescription.contains("encrypted and signed"))
        }
    }

    /// A damaged header still identifies the layout.
    func testClassicWithUnreadableHeaderIsRefused() {
        let data = classicPartition(header: "\u{0}\u{1}\u{2}\u{3}")
        XCTAssertEqual(FirmwarePartition.samsungImageHeader(in: data), "unknown")
        XCTAssertThrowsError(try Operations.checkModel(onIPod: data)) {
            XCTAssertEqual(($0 as? FirmwareError)?.code, HelperResult.unsupportedIPod)
        }
    }

    func testVideoIsNotSamsung() throws {
        XCTAssertNil(FirmwarePartition.samsungImageHeader(in: partition(vers: 0xB001)))
        XCTAssertNil(FirmwarePartition.samsungImageHeader(in: [UInt8](repeating: 0, count: 0x8000)))
    }
}

/// End-to-end on a real block device: a disk image laid out like a Windows-formatted iPod,
/// attached with hdiutil. Set IPODFW_IPSW and IPODFW_DISK_TEST=1.
final class DiskImageFlashTests: XCTestCase {
    func sh(_ args: [String]) throws -> String {
        String(decoding: try runTool(args[0], Array(args.dropFirst())), as: UTF8.self)
    }

    func testBackupFlashVerifyRestore() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["IPODFW_DISK_TEST"] == "1", let ipsw = env["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_DISK_TEST=1 and IPODFW_IPSW") }
        let stock = try IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ipodfw-disk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // MBR: partition 0 = firmware (type 0, 32 MB at sector 63), partition 1 = FAT32 (type 0x0B)
        let partStart = 63, partSectors = 65536
        var image = [UInt8](repeating: 0, count: (partStart + partSectors + 2048) * 512)
        image[0x1BE + 4] = 0; put32(&image, 0x1BE + 8, UInt32(partStart)); put32(&image, 0x1BE + 12, UInt32(partSectors))
        image[0x1CE + 4] = 0x0B; put32(&image, 0x1CE + 8, UInt32(partStart + partSectors)); put32(&image, 0x1CE + 12, 2048)
        image[510] = 0x55; image[511] = 0xAA
        image.replaceSubrange(partStart * 512..<partStart * 512 + stock.count, with: stock)
        let img = tmp.appendingPathComponent("ipod.img")
        try Data(image).write(to: img)

        let out = try sh(["/usr/bin/hdiutil", "attach", "-nomount", "-imagekey", "diskimage-class=CRawDiskImage", img.path])
        let disk = String(out.split(separator: " ").first!).replacingOccurrences(of: "/dev/", with: "")
        defer { _ = try? sh(["/usr/bin/hdiutil", "detach", "/dev/\(disk)"]) }
        let ipod = IPodDisk(disk: disk, mediaName: "Test iPod", blockSize: 512, size: Int64(image.count), volumeName: nil)
        let backups = tmp.appendingPathComponent("Backups")

        // 1. edit: one picture pixel + a balanced string change
        let ed = try FirmwareEditor(partition: FirmwarePartition(data: stock))
        var px = ed.rgba(of: ed.pictures[5]); px[0] = 1; px[1] = 2; px[2] = 3
        try ed.replacePicture(ed.pictures[5], rgba: px)
        try ed.setStrings(blockIndex: ed.mainIndex, ["129": "Januarius", "130": "Feb"])
        let edited = tmp.appendingPathComponent("edited.bin")
        try Data(ed.partition.data).write(to: edited)

        // 2. dry run writes nothing and takes no backup
        let dry = try Operations.flash(ipod, image: edited, backupDir: backups, reason: "flash", dryRun: true, owner: nil)
        XCTAssertFalse(dry.ranges!.isEmpty)
        XCTAssertTrue(Backups.list(in: backups).isEmpty)

        // 3. flash: backup taken first (original + timestamped), writes verified
        let r = try Operations.flash(ipod, image: edited, backupDir: backups, reason: "flash", dryRun: false, owner: nil)
        XCTAssertTrue(r.ok)
        let list = Backups.list(in: backups)
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list.contains { $0.isOriginal })
        let original = try Data(contentsOf: backups.appendingPathComponent(Backups.originalName))
        XCTAssertEqual(Array(original.prefix(stock.count)), stock)

        // device now holds the edit
        let raw = try RawDisk(path: "/dev/r\(disk)", blockSize: 512)
        let (s, size) = try FirmwareFlasher.locatePartition(raw)
        let now = try FirmwareEditor(partition: FirmwarePartition(data: raw.read(s, size)))
        XCTAssertEqual(now.strings(now.mainBlock).first?.value, "Januarius")

        // 4. a firmware with a modified aupd is refused
        var bad = ed.partition.data
        let aupd = try ed.partition.imageRange("aupd")
        bad[aupd.lowerBound + 100] ^= 0xFF
        let badURL = tmp.appendingPathComponent("bad.bin")
        try Data(bad).write(to: badURL)
        XCTAssertThrowsError(try Operations.flash(ipod, image: badURL, backupDir: backups, reason: "flash", dryRun: false, owner: nil))

        // 5. restore the original backup: device is byte-identical to stock again
        _ = try Operations.flash(ipod, image: backups.appendingPathComponent(Backups.originalName), backupDir: backups,
                                 reason: "restore", dryRun: false, owner: nil)
        XCTAssertEqual(try raw.read(s, stock.count), stock)
        XCTAssertEqual(Backups.list(in: backups).count, 3)   // the restore backed up the edited state too
        XCTAssertEqual(try Data(contentsOf: backups.appendingPathComponent(Backups.originalName)), original)  // never overwritten

        // 5a. a larger osos (as with a dark theme), in the layout of a firmware file: rsrc and aupd moved forward
        let file = try FirmwarePartition(data: stock)
        let larger = try file.image("osos") + [UInt8](repeating: 1, count: 40_000)
        try file.makeRoom(ososLength: larger.count)
        try file.replaceImage("osos", with: larger)
        XCTAssertNotEqual(try file.entry("aupd").devOffset, try FirmwarePartition(data: stock).entry("aupd").devOffset)
        let largerURL = tmp.appendingPathComponent("larger.bin")
        try Data(file.data).write(to: largerURL)
        let flashed = try Operations.flash(ipod, image: largerURL, backupDir: backups, reason: "flash", dryRun: false, owner: nil)
        XCTAssertTrue(flashed.ok)
        let onDisk = try FirmwarePartition(data: raw.read(s, size))
        XCTAssertEqual(try onDisk.image("osos"), larger)
        XCTAssertEqual(try onDisk.entry("aupd").devOffset, try FirmwarePartition(data: stock).entry("aupd").devOffset)
        XCTAssertEqual(try onDisk.image("aupd"), try FirmwarePartition(data: stock).image("aupd"))
        XCTAssertEqual(try onDisk.image("rsrc"), try FirmwarePartition(data: stock).image("rsrc"))
        XCTAssertGreaterThan(try onDisk.entry("rsrc").devOffset, try onDisk.entry("aupd").devOffset)
        // ... and the restore of the original backup gives the original partition again, also the moved rsrc area
        _ = try Operations.flash(ipod, image: backups.appendingPathComponent(Backups.originalName), backupDir: backups,
                                 reason: "restore", dryRun: false, owner: nil)
        XCTAssertEqual(try raw.read(s, size), Array(original))

        // 6. an interrupted write: the STOP banner and the directory are gone
        let w = try RawDisk(path: "/dev/r\(disk)", blockSize: 512, writable: true)
        try w.writeAligned(s, [UInt8](repeating: 0, count: 4096)[...])
        w.sync()
        XCTAssertThrowsError(try Operations.flash(ipod, image: backups.appendingPathComponent(Backups.originalName), backupDir: backups,
                                                  reason: "restore", dryRun: true, owner: nil)) {
            XCTAssertEqual(($0 as? FirmwareError)?.code, HelperResult.firmwareUnreadable)
        }

        // 7. a rescue with a changed aupd is refused; a backup that is itself damaged is refused
        XCTAssertThrowsError(try Operations.rescueRestore(ipod, image: badURL, backupDir: backups, dryRun: false, owner: nil))
        let zeroURL = tmp.appendingPathComponent("zero.bin")
        try Data(count: stock.count).write(to: zeroURL)
        XCTAssertThrowsError(try Operations.rescueRestore(ipod, image: zeroURL, backupDir: backups, dryRun: false, owner: nil))

        // 7a. the original backup is from a different disk: the rescue is refused
        var other = ipod
        other.mediaName = "Other iPod"
        XCTAssertThrowsError(try Operations.rescueRestore(other, image: backups.appendingPathComponent(Backups.originalName),
                                                          backupDir: backups, dryRun: true, owner: nil))

        // 8. the rescue writes only the damaged blocks (never aupd), keeps the damaged state, and the iPod is stock again
        let rescueDry = try Operations.rescueRestore(ipod, image: backups.appendingPathComponent(Backups.originalName),
                                                     backupDir: backups, dryRun: true, owner: nil)
        let aupdRange = try FirmwarePartition(data: stock).imageRange("aupd")
        XCTAssertFalse(rescueDry.ranges!.isEmpty)
        XCTAssertTrue(rescueDry.ranges!.allSatisfy { $0.offset + $0.length <= 4096 })   // only zeroed blocks that differ
        XCTAssertFalse(rescueDry.ranges!.contains { $0.offset < aupdRange.upperBound && $0.offset + $0.length > aupdRange.lowerBound })
        let rescued = try Operations.rescueRestore(ipod, image: backups.appendingPathComponent(Backups.originalName),
                                                   backupDir: backups, dryRun: false, owner: nil)
        XCTAssertTrue(rescued.ok)
        XCTAssertEqual(rescued.backup?.model, Backups.damagedModel)
        XCTAssertEqual(try raw.read(s, stock.count), stock)
        XCTAssertEqual(try Data(contentsOf: backups.appendingPathComponent(Backups.originalName)), original)

        // 9. the firmware is valid again, so a second rescue is refused
        XCTAssertThrowsError(try Operations.rescueRestore(ipod, image: backups.appendingPathComponent(Backups.originalName),
                                                          backupDir: backups, dryRun: true, owner: nil))
    }
}

final class ITunesDBTests: XCTestCase {
    func testChunkSizesAreConsistent() throws {
        let tracks = (0..<3).map { DBTrack(title: "Song \($0)", artist: "A", album: "B", path: ":x:T\($0).m4a", size: 100, lengthMS: 1000) }
        let db = ITunesDB.build(tracks)
        XCTAssertEqual(Array(db[0..<4]), Array("mhbd".utf8))
        XCTAssertEqual(le32(db, 4), 244)
        XCTAssertEqual(Int(le32(db, 8)), db.count)
        var p = 244 + 96 + 92
        for _ in 0..<3 {
            XCTAssertEqual(Array(db[p..<p + 4]), Array("mhit".utf8))
            var q = p + Int(le32(db, p + 4))
            for _ in 0..<Int(le32(db, p + 12)) {
                XCTAssertEqual(Array(db[q..<q + 4]), Array("mhod".utf8))
                q += Int(le32(db, q + 8))
            }
            XCTAssertEqual(q, p + Int(le32(db, p + 8)))
            p = q
        }
        XCTAssertEqual(Array(db[p..<p + 4]), Array("mhsd".utf8))
    }
}

/// Writes a test library to IPODFW_LIBRARY_OUT, for an emulator check of the Swift writer.
final class LibraryOutputTests: XCTestCase {
    func testWriteLibrary() throws {
        guard let out = ProcessInfo.processInfo.environment["IPODFW_LIBRARY_OUT"] else { throw XCTSkip("set IPODFW_LIBRARY_OUT") }
        try ITunesDB.makeLibrary(at: URL(fileURLWithPath: out))
    }
}

final class PatchAndArtTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The Swift patcher must give the same bytes as the Python patcher (IPODFW_PATCHED_OSOS).
    func testPatcherAgreesWithPython() throws {
        let env = ProcessInfo.processInfo.environment
        guard let ipsw = env["IPODFW_IPSW"], let expected = env["IPODFW_PATCHED_OSOS"] else {
            throw XCTSkip("set IPODFW_IPSW and IPODFW_PATCHED_OSOS")
        }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let patches = Patcher.list(in: Self.repo.appendingPathComponent("patches")).filter { $0.spec.name == "album-art" }
        XCTAssertEqual(patches.count, 1)
        XCTAssertTrue(Patcher.isCompatible(patches[0], osos: osos))
        let out = try Patcher.apply(patches, to: osos)
        XCTAssertEqual(out, [UInt8](try Data(contentsOf: URL(fileURLWithPath: expected))))
    }

    /// The flash-keep-awake patch: a bl at 0x284c7c to the hook, which keeps the replaced instruction.
    func testFlashKeepAwake() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let keep = all.filter { $0.spec.name == "flash-keep-awake" }
        XCTAssertEqual(keep.count, 1)
        let out = try Patcher.apply(keep, to: osos)
        XCTAssertEqual(le32(out, 0x284c7c), try Patcher.branch("bl", at: 0x284c7c, to: 0x736480))
        XCTAssertEqual(le32(out, 0x736480), 0xe594_1018)
        XCTAssertEqual(le32(out, 0xb45f4) & 0xFF00_0000, 0xEB00_0000)   // the wake hook is a bl
        XCTAssertNotEqual(le32(out, 0xb45f4), le32(osos, 0xb45f4))
        XCTAssertEqual(le32(out, 0x736484), 0xe351_0001)                 // "cmp r1, #1": a release stays a release
        // the sleep gate and the power-off call are bl hooks
        for at in [0x1d871c, 0x23344c] {
            XCTAssertEqual(le32(out, at) & 0xFF00_0000, 0xEB00_0000)
            XCTAssertNotEqual(le32(out, at), le32(osos, at))
        }
        XCTAssertEqual(le32(out, 0x1d8344), le32(osos, 0x1d8344))       // the input wake is flash-wake-on-input
        // with the album-art patch: the two patches use different areas
        _ = try Patcher.apply(all.filter { ["album-art", "flash-keep-awake"].contains($0.spec.name) }, to: osos)
    }

    /// The flash-wake-on-input patch: a bl at 0x1d8344 to the hook. It fits with the other flash and art patches.
    func testFlashWakeOnInput() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let wake = all.filter { $0.spec.name == "flash-wake-on-input" }
        XCTAssertEqual(wake.count, 1)
        let out = try Patcher.apply(wake, to: osos)
        XCTAssertEqual(le32(out, 0x1d8344), try Patcher.branch("bl", at: 0x1d8344, to: 0x736700))
        _ = try Patcher.apply(all.filter { ["album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input"].contains($0.spec.name) }, to: osos)
    }

    /// The Storage Time option: the two flash patches have the same choices, and 30 minutes is the default.
    func testStorageTimeChoices() throws {
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        for name in ["flash-keep-awake", "flash-wake-on-input"] {
            let option = try XCTUnwrap(all.first { $0.spec.name == name }?.spec.options?.first { $0.id == "time" })
            XCTAssertEqual(option.choices.map(\.value), [60000, 120000, 300000, 600000, 1800000, 3600000])
            XCTAssertEqual(option.defaultValue, 1800000)
        }
    }

    /// The Storage Time option: the patcher writes the selected time into one word of each flash patch.
    func testStorageTimeOption() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        for name in ["flash-keep-awake", "flash-wake-on-input"] {
            var patch = try XCTUnwrap(all.first { $0.spec.name == name })
            let standard = try Patcher.apply([patch], to: osos)
            patch.options = ["time": 60000]
            let short = try Patcher.apply([patch], to: osos)
            let changed = standard.indices.filter { standard[$0] != short[$0] }
            let word = try XCTUnwrap(changed.first) & ~3
            XCTAssertTrue(changed.allSatisfy { ($0 & ~3) == word })
            XCTAssertEqual(le32(standard, word), 1800000)
            XCTAssertEqual(le32(short, word), 60000)
            patch.options = ["time": 7]
            XCTAssertThrowsError(try Patcher.apply([patch], to: osos))
        }
    }

    /// The sleep-now patch: the Sleep item handler calls the patch, and the power test in 0x1ee8d0 is a bl.
    func testSleepNow() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let sleep = all.filter { $0.spec.name == "sleep-now" }
        XCTAssertEqual(sleep.count, 1)
        let out = try Patcher.apply(sleep, to: osos)
        XCTAssertEqual(le32(out, 0x69fd2c), 0x73658c)                          // the table entry
        XCTAssertEqual(le32(out, 0x1e8ce8), try Patcher.branch("bl", at: 0x1e8ce8, to: 0x73658c))
        XCTAssertEqual(le32(out, 0x1ee930) & 0xFF00_0000, 0xEB00_0000)
        XCTAssertNotEqual(le32(out, 0x1ee930), le32(osos, 0x1ee930))
        // with the other code patches: all use different areas
        _ = try Patcher.apply(all.filter { ["album-art", "flash-keep-awake", "sleep-now"].contains($0.spec.name) }, to: osos)
    }

    /// The backlight-60s patch: data only. The Backlight Timer menu has 60 Seconds in place of 2 Seconds.
    func testBacklight60s() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let backlight = all.filter { $0.spec.name == "backlight-60s" }
        XCTAssertEqual(backlight.count, 1)
        let out = try Patcher.apply(backlight, to: osos)
        XCTAssertEqual(out.count, osos.count)
        XCTAssertEqual(Array(out[0x4baa75..<0x4baa78]), [0x58, 0x00, 0x3c])           // the script pushes 60
        XCTAssertEqual(le32(out, 0x4b06a0 + 40 * 5 + 28) & 0xFFFF, 0x6039)             // item 5 sends 0x6039
        let blocks = Resources.scan(out)
        let english = Dictionary(uniqueKeysWithValues: Resources.readStrings(out, blocks[24]).map { ($0.key, $0.value) })
        XCTAssertEqual(english["-140"], "60 Seconds")
        // with a code patch
        _ = try Patcher.apply(all.filter { ["sleep-now", "backlight-60s"].contains($0.spec.name) }, to: osos)
    }

    func testVersionText() {
        XCTAssertEqual(FirmwareVersion("1.3.1"), FirmwareVersion(major: 1, minor: 3, fix: 1))
        XCTAssertEqual(FirmwareVersion("1.3"), .stock)
        XCTAssertEqual(FirmwareVersion("1.3.1")?.description, "1.3.1")
        XCTAssertEqual(FirmwareVersion("2.0.0")?.description, "2.0")
        for bad in ["", "1", "x", "1.16", "1.3.16", "256.0", "1..3", "1.3.1.1", "-1.3", "+1.3"] {
            XCTAssertNil(FirmwareVersion(bad), bad)
        }
        XCTAssertEqual(FirmwareVersion(major: 1, minor: 3, fix: 1, letters: "abrs").description, "1.3.1abrs")
        XCTAssertEqual(FirmwareVersion(major: 1, minor: 3, fix: 0, letters: "k").description, "1.3k")
    }

    /// The About-screen version: only the two mov instructions at 0x9ee90 change.
    func testVersionChangesOnlyTheAboutScreen() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        var out = osos
        try FirmwareVersion.apply(FirmwareVersion(major: 1, minor: 3, fix: 1), to: &out)
        XCTAssertEqual(out.count, osos.count)
        XCTAssertEqual(le32(out, 0x9ee90), 0xe3a0_1001)
        XCTAssertEqual(le32(out, 0x9ee94), 0xe3a0_2031)
        XCTAssertEqual((0..<osos.count).filter { osos[$0] != out[$0] }, [0x9ee94])
        XCTAssertEqual(le32(out, 0x175ae4), 0xe3a0_2030)   // VisibleBuildID stays 1.3
        XCTAssertThrowsError(try FirmwareVersion.apply(.stock, to: &out))
    }

    /// The About-screen version with letters: only FUN_0009ee70 changes, and it has the text.
    func testVersionLettersChangeOnlyTheAboutFunction() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        var out = osos
        try FirmwareVersion.apply(FirmwareVersion(major: 1, minor: 3, fix: 1, letters: "abrs"), to: &out)
        XCTAssertEqual(out.count, osos.count)
        XCTAssertTrue((0..<osos.count).filter { osos[$0] != out[$0] }.allSatisfy { (0x9ee70..<0x9eed8).contains($0) })
        XCTAssertEqual(le32(out, 0x9ee88), 0xebff_ceae)                 // bl 0x92948
        XCTAssertEqual(le32(out, 0x9ee94), 0xebff_d18a)                 // bl 0x934c4
        XCTAssertEqual(Array(out[0x9eea0..<0x9eeaa]), Array("1.3.1abrs\0".utf8))
        XCTAssertEqual(le32(out, 0x175ae4), 0xe3a0_2030)                // VisibleBuildID stays 1.3
        XCTAssertThrowsError(try FirmwareVersion.apply(FirmwareVersion(major: 1, minor: 3, fix: 1, letters: "a"), to: &out))
        var copy = osos
        XCTAssertThrowsError(try FirmwareVersion.apply(FirmwareVersion(major: 1, minor: 3, fix: 0, letters: "A"), to: &copy))
        XCTAssertThrowsError(try FirmwareVersion.apply(FirmwareVersion(major: 1, minor: 3, fix: 0, letters: String(repeating: "a", count: 22)), to: &copy))
        XCTAssertEqual(copy, osos)
    }

    /// Each patch in the Patches pane has a letter. Each letter is one letter a–z, and no two patches have the same letter.
    func testPatchVersionLetters() {
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        for p in all where p.spec.internal != true {
            XCTAssertNotNil(p.spec.version_letter, "\(p.spec.name) has no version_letter in patch.json")
        }
        let letters = all.compactMap(\.spec.version_letter)
        XCTAssertEqual(Set(letters).count, letters.count)
        for l in letters { XCTAssertTrue(l.count == 1 && ("a"..."z").contains(l), l) }
    }

    /// Each patch in the Patches pane has a valid version.
    func testMusicAppSyncFiles() throws {
        let volume = FileManager.default.temporaryDirectory.appendingPathComponent("music-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: volume) }
        let itunes = volume.appendingPathComponent("iPod_Control/iTunes")
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try Data().write(to: itunes.appendingPathComponent("iTunesDB"))
        XCTAssertEqual(MusicAppCheck.syncFiles(onVolume: volume), [])
        try Data().write(to: itunes.appendingPathComponent("iTunesDB.tmp"))
        XCTAssertEqual(MusicAppCheck.syncFiles(onVolume: volume), ["iPod_Control/iTunes/iTunesDB.tmp"])
    }

    func testPatchVersions() {
        for p in Patcher.list(in: Self.repo.appendingPathComponent("patches")) where p.spec.internal != true {
            XCTAssertNotNil(p.spec.parsedVersion, "\(p.spec.name) has no valid version in patch.json")
        }
    }

    /// Each patch records its size on the iPod in patch.json, and the value is the measured size.
    func testPatchSizes() throws {
        for p in Patcher.list(in: Self.repo.appendingPathComponent("patches")) {
            let measured = try Patcher.codeSize(p, symbols: ["dark_table": 0])   // the Dark Mode build gives dark_table
            XCTAssertEqual(p.spec.size, measured, "\(p.spec.name): set \"size\": \(measured) in patch.json")
        }
    }

    static let customEQGolden = "3b42c6967ea9203f0867f660877a10c744cd9c2a6f9b8f2bb723bd176ecdd8c7"

    /// The Q24 records of custom-eq give the requested gain. The bytes agree with tests/test_custom_eq.py.
    func testCustomEQRecords() throws {
        var bands = CustomEQ.defaults
        bands[2].gain = -60
        let (data, mask) = try CustomEQ.records(bands, precut: true)
        XCTAssertEqual(mask, 1 << 2)
        XCTAssertEqual(data.count, 200)
        for (r, rate) in CustomEQ.rates.enumerated() {
            let q = (0..<5).map { k -> Double in
                let at = 40 * 2 + (r * 5 + k) * 4
                let v = Int32(truncatingIfNeeded: (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[at + $1]) << UInt32($1 * 8) })
                return Double(v) / 16_777_216
            }
            XCTAssertEqual(CustomEQ.response([q], frequency: 910, rate: rate), -6, accuracy: 0.1)
        }
        let boost = try CustomEQ.records([CustomEQ.Band(kind: .lowShelf, frequency: 100, gain: 120, q: 71)]
                                         + CustomEQ.defaults.dropFirst(), precut: true)
        XCTAssertEqual(boost.mask, 1)
        let loud = try CustomEQ.records([CustomEQ.Band(kind: .lowShelf, frequency: 100, gain: 120, q: 71)]
                                        + CustomEQ.defaults.dropFirst())
        let b0 = Int32(truncatingIfNeeded: (0..<4).reduce(UInt32(0)) { $0 | UInt32(loud.data[$1]) << UInt32($1 * 8) })
        XCTAssertGreaterThan(b0, 1 << 24, "without the precut, the numerator keeps the boost")
        XCTAssertEqual(SHA256.hash(data: boost.data).map { String(format: "%02x", $0) }.joined(), Self.customEQGolden)
        XCTAssertEqual(try CustomEQ.records(CustomEQ.defaults).mask, 0)
        XCTAssertEqual(CustomEQ.bands(from: CustomEQ.values(of: bands)), bands)
        XCTAssertFalse(CustomEQ.usesPrecut(CustomEQ.values(of: bands)))
    }

    /// The Simple view of custom-eq keeps the gains and uses valid fixed bands.
    func testCustomEQSimple() throws {
        var bands = CustomEQ.defaults
        bands[0].gain = 60
        bands[4].gain = -30
        bands[4].frequency = 5000
        let simple = CustomEQ.simple(from: bands)
        XCTAssertEqual(simple.map(\.gain), bands.map(\.gain))
        XCTAssertEqual(simple[4].frequency, 8000)
        XCTAssertEqual(CustomEQ.simpleNames.count, CustomEQ.bandCount)
        XCTAssertEqual(try CustomEQ.records(simple).mask, 0b10001)
        XCTAssertFalse(CustomEQ.usesAdvanced([:]))
    }

    /// A change of preset asks the user only if the user edited the bands.
    func testCustomEQIsUnedited() {
        XCTAssertTrue(CustomEQ.isUnedited(CustomEQ.defaults))
        XCTAssertTrue(CustomEQ.isUnedited(CustomEQ.simpleLayout))
        for p in CustomEQ.applePresets {
            let bands = CustomEQ.bands(forPreset: p)
            XCTAssertTrue(CustomEQ.isUnedited(CustomEQ.bands(from: CustomEQ.values(of: bands))), p.name)
        }
        var edited = CustomEQ.bands(forPreset: CustomEQ.applePresets[0])
        edited[0].gain += 5
        XCTAssertFalse(CustomEQ.isUnedited(edited))
    }

    /// Each active band of each EQ gets the next filter number, to a maximum of 96.
    func testCustomEQLibrary() throws {
        var a = NamedEQ(name: "Car"), b = NamedEQ(name: "Rock Out")
        a.bands[0].gain = 30
        b.bands[0].gain = 30
        b.bands[2].gain = 30
        b.bands[1].gain = 30    // off: this EQ has no agreement for 5 bands
        let (records, list) = try CustomEQ.library([a, b])
        XCTAssertEqual(records.count, 1000)
        XCTAssertEqual(list.count, 350)
        XCTAssertEqual(Array(list[0..<4]), [3, 0, 0x43, 0])
        XCTAssertEqual(Array(list[64..<69]), [55, 0, 0, 0, 0])
        XCTAssertEqual(Array(list[(70 + 64)..<(70 + 69)]), [56, 0, 57, 0, 0])
        XCTAssertEqual(Array(records[0..<40]), Array(try CustomEQ.records(a.activeBands).data[0..<40]))

        var five = NamedEQ(name: "x", allBands: true)
        for i in 0..<5 { five.bands[i].gain = 30 }
        var eqs = (0..<5).map { i -> NamedEQ in
            var e = five
            e.name = "EQ \(i)"
            return e
        }
        XCTAssertEqual(Array(try CustomEQ.library(eqs).list[(4 * 70 + 64)..<(4 * 70 + 69)]), [75, 76, 77, 78, 79])
        eqs.append(NamedEQ(name: "Six"))
        XCTAssertThrowsError(try CustomEQ.library(eqs), "6 EQs")
    }

    /// The saved selection on the iPod is the name, so a bad name is not possible.
    func testCustomEQNames() {
        let eqs = [NamedEQ(name: "Car")]
        XCTAssertNil(CustomEQ.nameProblem("Headphones", in: eqs, excluding: nil))
        for bad in ["", " ", " A", String(repeating: "x", count: 32), "car", "rock", "OFF", "a\u{7}"] {
            XCTAssertNotNil(CustomEQ.nameProblem(bad, in: eqs, excluding: nil), bad)
        }
        XCTAssertNil(CustomEQ.nameProblem("CAR", in: eqs, excluding: "Car"))
        XCTAssertEqual(CustomEQ.uniqueName("Car", in: eqs), "Car 2")
        XCTAssertEqual(CustomEQ.uniqueName("Rock", in: eqs), "Rock 2")
        XCTAssertLessThanOrEqual(CustomEQ.uniqueName(String(repeating: "😀", count: 30), in: []).utf16.count, 31)
        XCTAssertNil(CustomEQ.nameProblem(CustomEQ.uniqueName(String(repeating: "😀", count: 30), in: []), in: [], excluding: nil))
        XCTAssertTrue(CustomEQ.nameCanFailToShow("Car 😀"))
        XCTAssertFalse(CustomEQ.nameCanFailToShow("Café"))
    }

    /// The single EQ of an older version becomes the EQ "Custom", and a file becomes a new EQ.
    func testCustomEQMoves() throws {
        var bands = CustomEQ.simpleLayout
        bands[0].gain = 60
        bands[1].gain = 30
        var values = CustomEQ.values(of: bands)
        values["all_bands"] = 1
        values["precut"] = 1
        let old = NamedEQ(options: values)
        XCTAssertEqual(old.name, "Custom")
        XCTAssertEqual(old.activeBands.filter { $0.gain != 0 }.count, 2)
        XCTAssertTrue(old.preventClipping)
        let shared = SharedEQ(name: "Custom", bands: old.activeBands, preventClipping: false, advanced: false)
        let new = NamedEQ(shared: try SharedEQ.decode(try shared.encode()), in: [old])
        XCTAssertEqual(new.name, "Custom 2")
        XCTAssertTrue(new.allBands)
    }

    /// A band stays in the range of the Apple presets until the user agrees to more.
    func testCustomEQGainRange() throws {
        XCTAssertEqual(CustomEQ.appleGainRange, -70...75)
        var eq = NamedEQ(name: "A")
        eq.bands[0].gain = 120
        eq.bands[2].gain = -120
        XCTAssertEqual(eq.activeBands[0].gain, 75)
        XCTAssertEqual(eq.activeBands[2].gain, -70)
        eq.fullGain = true
        XCTAssertEqual(eq.activeBands[0].gain, 120)
        XCTAssertEqual(eq.activeBands[2].gain, -120)
        for p in CustomEQ.applePresets {
            let bands = CustomEQ.bands(forPreset: p)
            XCTAssertEqual(NamedEQ(name: "B", bands: bands).activeBands, bands, p.name)
        }
        let loud = try SharedEQ.decode(try SharedEQ(name: "L", bands: eq.activeBands, preventClipping: false, advanced: false).encode())
        XCTAssertTrue(loud.needsFullGain)
        XCTAssertEqual(NamedEQ(shared: loud, in: []).activeBands[0].gain, 120)
        // A list from version 0.7 has no value "fullGain".
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(NamedEQ(name: "C"))) as? [String: Any])
        old["fullGain"] = nil
        XCTAssertNil(try JSONDecoder().decode(NamedEQ.self, from: JSONSerialization.data(withJSONObject: old)).fullGain)
    }

    /// The Apple presets are valid start points with the default 3 bands.
    func testCustomEQApplePresets() throws {
        XCTAssertEqual(CustomEQ.applePresets.count, 22)
        func gain(_ name: String, at frequency: Double) throws -> Double {
            let preset = try XCTUnwrap(CustomEQ.applePresets.first { $0.name == name })
            let filters = preset.bands.map { CustomEQ.biquad($0, rate: 44100) }
            return CustomEQ.response(filters, frequency: frequency, rate: 44100)
        }
        for p in CustomEQ.applePresets {
            XCTAssertLessThanOrEqual(p.bands.count, 3, p.name)
            let bands = CustomEQ.bands(forPreset: p)
            XCTAssertEqual(try CustomEQ.records(bands).mask & 0b01010, 0, p.name)
            XCTAssertNoThrow(try CustomEQ.records(bands, precut: true), p.name)
            XCTAssertEqual(CustomEQ.bands(from: CustomEQ.values(of: bands)), bands, p.name)
        }
        XCTAssertEqual(try gain("Bass Booster", at: 32), 5.8, accuracy: 0.5)
        XCTAssertEqual(try gain("Treble Booster", at: 16000), 6.0, accuracy: 0.5)
        let flat = try XCTUnwrap(CustomEQ.applePresets.first { $0.name == "Flat" })
        XCTAssertEqual(try CustomEQ.records(CustomEQ.bands(forPreset: flat)).mask, 0)
    }

    /// The colours of the curve follow the effect of each band.
    func testCustomEQBandWeights() {
        var bands = CustomEQ.simpleLayout
        bands[0].gain = 90
        let rate = CustomEQ.rates[0]
        let low = CustomEQ.bandWeights(bands, frequency: 60, rate: rate)
        XCTAssertGreaterThan(low[0], 6)
        XCTAssertEqual(low[1...].reduce(0, +), 0)
        XCTAssertEqual(CustomEQ.bandWeights(bands, frequency: 10000, rate: rate)[0], 0, accuracy: 0.1)
        bands[0].gain = -90
        XCTAssertEqual(CustomEQ.bandWeights(bands, frequency: 60, rate: rate)[0], low[0], accuracy: 0.001)
    }

    /// Without the agreement of the user, only 3 bands can operate.
    func testCustomEQThreeBandsByDefault() throws {
        var bands = CustomEQ.simpleLayout
        for i in bands.indices { bands[i].gain = 30 }
        var values = CustomEQ.values(of: bands)
        XCTAssertEqual(try CustomEQ.records(CustomEQ.bands(from: values)).mask, 0b10101)
        values["all_bands"] = 1
        XCTAssertEqual(try CustomEQ.records(CustomEQ.bands(from: values)).mask, 0b11111)
        XCTAssertTrue(try SharedEQ.decode(SharedEQ(name: "A", bands: bands, preventClipping: false, advanced: false).encode()).needsAllBands)
        bands[1].gain = 0
        bands[3].gain = 0
        XCTAssertFalse(try SharedEQ.decode(SharedEQ(name: "A", bands: bands, preventClipping: false, advanced: false).encode()).needsAllBands)
    }

    /// A .ipodeq file gives the same EQ again, and has only the settings.
    func testSharedEQRoundTrip() throws {
        var bands = CustomEQ.simpleLayout
        bands[0].gain = 60
        let data = try SharedEQ(name: "Warm Bass", bands: bands, preventClipping: true, advanced: false).encode()
        let eq = try SharedEQ.decode(data)
        XCTAssertEqual(eq.name, "Warm Bass")
        XCTAssertEqual(eq.eqBands, bands)
        XCTAssertTrue(eq.preventClipping)
        XCTAssertFalse(eq.usesAdvanced)
        let keys = Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
        XCTAssertEqual(keys, ["format", "name", "bands", "preventClipping", "view"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("/Users"))
        // Bands that the Simple view does not have need the Advanced view.
        XCTAssertTrue(try SharedEQ.decode(SharedEQ(name: "A", bands: CustomEQ.defaults, preventClipping: false, advanced: false).encode()).usesAdvanced)
        XCTAssertEqual(try SharedEQ.decode(SharedEQ(name: "\u{7}", bands: bands, preventClipping: false, advanced: false).encode()).name, "Custom EQ")
    }

    /// A received .ipodeq file is not trusted.
    func testSharedEQRejectsBadFiles() throws {
        let good = try SharedEQ(name: "A", bands: CustomEQ.simpleLayout, preventClipping: false, advanced: false)
        func edited(_ change: (inout SharedEQ) -> Void) throws -> Data {
            var eq = good
            change(&eq)
            return try eq.encode()
        }
        let bad = [Data("{".utf8), Data("[1]".utf8), Data(count: SharedEQ.maxFileSize + 1),
                   try edited { $0.format = 2 }, try edited { $0.bands.removeLast() },
                   try edited { $0.bands[0].gain = 130 }, try edited { $0.bands[0].gain = Int.min },
                   try edited { $0.bands[0].frequency = 5 }, try edited { $0.bands[0].q = 0 },
                   try edited { $0.bands[0].type = "notch" }, try edited { $0.view = "other" }]
        for data in bad { XCTAssertThrowsError(try SharedEQ.decode(data)) }
    }

    /// The checks of custom-eq reject bad bands.
    func testCustomEQChecks() {
        for bad in [CustomEQ.Band(kind: .peak, frequency: 10, gain: 10, q: 100),
                    CustomEQ.Band(kind: .peak, frequency: 1000, gain: 130, q: 100),
                    CustomEQ.Band(kind: .peak, frequency: 1000, gain: 10, q: 900)] {
            XCTAssertThrowsError(try CustomEQ.records([bad] + CustomEQ.defaults.dropFirst()))
        }
    }

    /// usb-audio-out has the code of usb-host-probe and the same hook sites: the app must not turn on both.
    func testUSBAudioOutConflictsWithProbe() {
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let pair = all.filter { ["usb-audio-out", "usb-host-probe"].contains($0.spec.name) }
        XCTAssertEqual(pair.count, 2)
        XCTAssertFalse(Patcher.conflicts(pair).isEmpty)
    }

    /// playback-log and usb-host-probe both hook 0x1d8260 with no chain: the app must not turn on both.
    /// playback-log has no conflict with the patches that are not test or internal patches.
    func testDiagnosticLogConflicts() throws {
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let log = try XCTUnwrap(all.first { $0.spec.name == "diagnostic-log" })
        let playback = try XCTUnwrap(all.first { $0.spec.name == "playback-log" })
        let probe = try XCTUnwrap(all.first { $0.spec.name == "usb-host-probe" })
        XCTAssertFalse(Patcher.conflicts([log, playback]).isEmpty)
        XCTAssertFalse(Patcher.conflicts([log, probe]).isEmpty)
        for p in all where p.spec.internal != true && !p.spec.isTest {
            XCTAssertTrue(Patcher.conflicts([log, p]).isEmpty, "diagnostic-log conflicts with \(p.spec.name)")
        }
    }

    func testPlaybackLogConflicts() throws {
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let log = try XCTUnwrap(all.first { $0.spec.name == "playback-log" })
        let probe = try XCTUnwrap(all.first { $0.spec.name == "usb-host-probe" })
        let pair = Patcher.conflicts([log, probe])
        XCTAssertEqual(pair.count, 1)
        XCTAssertEqual(pair.first?.2, "hook at 0x1d8260")
        for p in all where p.spec.internal != true && !p.spec.isTest {
            XCTAssertTrue(Patcher.conflicts([log, p]).isEmpty, "playback-log conflicts with \(p.spec.name)")
        }
    }

    /// shuffle-album-mix needs shuffle-fixes: a build without it fails. Each name in `needs` is a patch.
    func testPatchNeeds() {
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let names = Set(all.map(\.spec.name))
        for p in all {
            for n in p.spec.needs ?? [] { XCTAssertTrue(names.contains(n), "\(p.spec.name) needs \(n), which is not in patches/") }
        }
        let mix = all.first { $0.spec.name == "shuffle-album-mix" }!
        let fixes = all.first { $0.spec.name == "shuffle-fixes" }!
        XCTAssertEqual(Patcher.missingNeeds([mix]).first?.1, ["shuffle-fixes"])
        XCTAssertTrue(Patcher.missingNeeds([mix, fixes]).isEmpty)
        XCTAssertThrowsError(try Patcher.apply([mix], to: [UInt8](repeating: 0, count: 16)))
    }

    /// Before a write of a firmware without shuffle-album-mix, the app switches off Album Mix in the
    /// settings file of the iPod. Only the byte 0x8b changes, and only in a file of version 0x39.
    func testClearAlbumMix() throws {
        let volume = FileManager.default.temporaryDirectory.appendingPathComponent("prefs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: volume) }
        XCTAssertFalse(try IPodPreferences.clearAlbumMix(onVolume: volume))           // no file
        let url = volume.appendingPathComponent(IPodPreferences.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var prefs = [UInt8](repeating: 0x55, count: 0xb6c)
        prefs[0..<4] = [0x39, 0, 0, 0]
        prefs[0x8a] = 1; prefs[0x8b] = 1
        try Data(prefs).write(to: url)
        XCTAssertTrue(try IPodPreferences.clearAlbumMix(onVolume: volume))
        var expected = prefs
        expected[0x8b] = 0
        XCTAssertEqual([UInt8](try Data(contentsOf: url)), expected)                  // Albums (0x8a) stays
        XCTAssertFalse(try IPodPreferences.clearAlbumMix(onVolume: volume))           // already off
        prefs[0] = 0x38
        try Data(prefs).write(to: url)
        XCTAssertFalse(try IPodPreferences.clearAlbumMix(onVolume: volume))           // other version
        XCTAssertEqual([UInt8](try Data(contentsOf: url)), prefs)
    }

    /// The app finds shuffle-album-mix in an osos image by the wrap of the Shuffle item.
    func testHasAlbumMix() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let fixes = all.first { $0.spec.name == "shuffle-fixes" }!, mix = all.first { $0.spec.name == "shuffle-album-mix" }!
        XCTAssertFalse(IPodPreferences.hasAlbumMix(osos: osos))
        XCTAssertFalse(IPodPreferences.hasAlbumMix(osos: try Patcher.apply([fixes], to: osos)))
        XCTAssertTrue(IPodPreferences.hasAlbumMix(osos: try Patcher.apply([fixes, mix], to: osos)))
    }

    /// A patch with no code shows the bytes that it changes, not "0 KB".
    func testChangedBytesText() {
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let volume = all.first { $0.spec.name == "volume-unlimit" }!.spec
        XCTAssertEqual(volume.size, 0)
        XCTAssertEqual(volume.changedBytes, 2)
        XCTAssertEqual(volume.shortSizeText, 2.formatted(.byteCount(style: .memory)))
        XCTAssertEqual(volume.sizeText, "2 bytes")
        let probe = all.first { $0.spec.name == "usb-audio-out" }!.spec
        XCTAssertEqual(probe.changedBytes, 0)
        XCTAssertEqual(probe.sizeText, PatchSpec.byteText(probe.size!))
    }

    /// The test patches (category "test") show only when Settings > Patches > Enable Test Patches is on.
    func testTestPatchesHidden() {
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        XCTAssertTrue(all.first { $0.spec.name == "usb-host-probe" }!.spec.isTest)
        XCTAssertFalse(all.first { $0.spec.name == "usb-audio-out" }!.spec.isTest)
        let hidden = PatchSpec.visible(all, showTests: false), shown = PatchSpec.visible(all, showTests: true)
        XCTAssertFalse(hidden.contains { $0.spec.name == "usb-host-probe" })
        XCTAssertTrue(shown.contains { $0.spec.name == "usb-host-probe" })
        XCTAssertFalse(shown.contains { $0.spec.internal == true })
        XCTAssertEqual(shown.count - hidden.count, all.filter { $0.spec.isTest && $0.spec.internal != true }.count)
    }

    func testPatchVersionCompare() {
        XCTAssertGreaterThan(PatchVersion("1.10")!, PatchVersion("1.9")!)
        XCTAssertEqual(PatchVersion("1"), PatchVersion("1.0.0"))
        XCTAssertLessThan(PatchVersion("1.2")!, PatchVersion("1.2.1")!)
        for bad in ["", "1.a", "1..2", "1.2.3.4", "-1", " 1"] { XCTAssertNil(PatchVersion(bad), bad) }
        XCTAssertTrue(PatchVersion.isLower(nil, than: PatchVersion("0")))
        XCTAssertFalse(PatchVersion.isLower(nil, than: nil))
    }

    /// The Patches pane needs a title, a summary, a category and an SF Symbol for each patch.
    /// A row of the Patches pane has one line for the summary.
    func testPatchSummaryLength() {
        for p in Patcher.list(in: Self.repo.appendingPathComponent("patches")) where p.spec.internal != true {
            XCTAssertLessThanOrEqual(p.spec.summary?.count ?? 0, 50, "\(p.spec.name): the summary is too long")
        }
    }

    func testPatchMetadata() {
        for p in Patcher.list(in: Self.repo.appendingPathComponent("patches")) where p.spec.internal != true {
            XCTAssertNotNil(p.spec.title, "\(p.spec.name) has no title in patch.json")
            XCTAssertNotNil(p.spec.summary, "\(p.spec.name) has no summary in patch.json")
            XCTAssertTrue(PatchSpec.categories.contains(p.spec.category ?? ""), "\(p.spec.name) has no valid category")
            let symbol = p.spec.symbol ?? ""
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(p.spec.name): no SF Symbol \"\(symbol)\"")
            for t in p.spec.ui?.tools ?? [] { XCTAssertTrue(PatchSpec.knownTools.contains(t), "\(p.spec.name): unknown tool \(t)") }
            for path in p.spec.ui?.paths ?? [] { XCTAssertTrue(PatchUI.isSafePath(path), path) }
            XCTAssertFalse(p.spec.targets?.isEmpty ?? true, "\(p.spec.name) has no targets in patch.json")
            for t in p.spec.targets ?? [] { XCTAssertEqual(t.osos_sha256, p.spec.osos_sha256, p.spec.name) }
        }
    }

    /// The original drives are 30, 60 and 80 GB. A size within 5 GB of one of them gives a warning.
    func testLikelyOriginalHDD() {
        XCTAssertEqual(IPodDisk.likelyOriginalHDD(size: 30_000_000_000), 30)
        XCTAssertEqual(IPodDisk.likelyOriginalHDD(size: 29_800_000_000), 30)
        XCTAssertEqual(IPodDisk.likelyOriginalHDD(size: 79_900_000_000), 80)
        XCTAssertEqual(IPodDisk.likelyOriginalHDD(size: 64_000_000_000), 60)
        for size: Int64 in [16_000_000_000, 128_000_000_000, 256_000_000_000, 2_000_000_000_000] {
            XCTAssertNil(IPodDisk.likelyOriginalHDD(size: size))
        }
        let keep = Patcher.list(in: Self.repo.appendingPathComponent("patches")).first { $0.spec.name == "flash-keep-awake" }
        XCTAssertNotNil(keep?.spec.hdd_warning)
    }

    func testReadTracksRoundTrip() {
        let tracks = (0..<5).map { DBTrack(title: "Song \($0)", artist: "A", album: "Album \($0 / 2)", path: ":iPod_Control:Music:F00:T\($0).m4a", size: 1, lengthMS: 1) }
        let read = ITunesDB.readTracks(ITunesDB.build(tracks))
        XCTAssertEqual(read.map(\.album), tracks.map(\.album))
        XCTAssertEqual(read.map(\.path), tracks.map(\.path))
        let info = ITunesDB.readTrackInfo(ITunesDB.build(tracks))
        XCTAssertEqual(info.map(\.title), tracks.map(\.title))
        XCTAssertEqual(info.map(\.artist), tracks.map(\.artist))
        var withID = tracks[0]
        withID.dbid = 0x1122334455667788
        XCTAssertEqual(ITunesDB.readTrackInfo(ITunesDB.build([withID])).first?.dbidLow, 0x55667788)
    }

    func testReadLibraryName() {
        let track = DBTrack(title: "A", artist: "B", album: "C", path: ":iPod_Control:Music:F00:A.m4a", size: 1, lengthMS: 1)
        XCTAssertEqual(ITunesDB.readLibraryName(ITunesDB.build([track], libraryName: "Music Box")), "Music Box")
        XCTAssertEqual(ITunesDB.readLibraryName(ITunesDB.build([track], libraryName: "")), nil)
        XCTAssertNil(ITunesDB.readLibraryName([]))
    }

    func testReadPlaylists() {
        let tracks = (0..<6).map { DBTrack(title: "Song \($0)", artist: "A", album: "Album \($0 / 2)", path: ":iPod_Control:Music:F00:T\($0).m4a", size: 1, lengthMS: 1) }
        let db = ITunesDB.build(tracks, playlists: [(name: "Album 0", tracks: [5, 0]), (name: "Road Trip ✓", tracks: [])])
        let lists = ITunesDB.readPlaylists(db)
        XCTAssertEqual(lists.map(\.name), ["Album 0", "Road Trip ✓"])     // the master playlist is not included
        let ids = ITunesDB.readTrackRecords(db).map(\.id)
        XCTAssertEqual(lists[0].trackIDs, [ids[5], ids[0]])
        XCTAssertEqual(lists[1].trackIDs, [])
        XCTAssertEqual(ITunesDB.readTracks(db).map(\.album), tracks.map(\.album))
        XCTAssertEqual(le32(db, 8), UInt32(db.count))
    }

    /// iTunes and MiMusic write the album list (mhsd type 4, mhla) first. The u32 at +8 of
    /// mhla is the album count, not a size.
    func testReadTracksAfterAnAlbumList() {
        let tracks = (0..<4).map { DBTrack(title: "Song \($0)", artist: "A", album: "Album \($0)", path: ":iPod_Control:Music:F00:T\($0).m4a", size: 1, lengthMS: 1) }
        let db = ITunesDB.build(tracks, playlists: [(name: "Mix", tracks: [3, 1])])
        var w = ITunesDB.Writer()
        w.tag("mhsd"); w.u32(96); w.u32(96 + 92); w.u32(4); w.zeros(80)
        w.tag("mhla"); w.u32(92); w.u32(325); w.zeros(80)
        var withAlbums = Array(db[0..<244]) + w.b + Array(db[244...])
        for i in 0..<4 { withAlbums[8 + i] = UInt8(UInt32(withAlbums.count) >> (8 * UInt32(i)) & 0xFF) }
        XCTAssertEqual(ITunesDB.readTracks(withAlbums).map(\.album), tracks.map(\.album))
        let ids = ITunesDB.readTrackRecords(withAlbums).map(\.id)
        XCTAssertEqual(ITunesDB.readPlaylists(withAlbums).map(\.trackIDs), [[ids[3], ids[1]]])
    }

    func testPlaylistThumbnailKey() throws {
        // The patch starts the hash of a playlist name after the byte 0x01 (same value as the Python version).
        XCTAssertEqual(AlbumArt.fnv1a(AlbumArt.playlistKey("Charm")), 0x96a58adf)
        XCTAssertNotEqual(AlbumArt.fnv1a(AlbumArt.playlistKey("Charm")), AlbumArt.fnv1a("Charm"))
        func png(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ w: Int) -> Data {
            ImageCodec.pngData(ImageCodec.cgImage(rgba: (0..<(w * w)).flatMap { _ in [r, g, b, 255] }, width: w, height: w)!)!
        }
        XCTAssertNil(MusicImport.collage([]))
        let red = png(255, 0, 0, 10)
        XCTAssertEqual(MusicImport.collage([red, red]), red)        // fewer than four covers: the first cover
        let c = ArtworkDB.image(MusicImport.collage([red, png(0, 255, 0, 10), png(0, 0, 255, 6), png(255, 255, 255, 8)], side: 20)!)!
        XCTAssertEqual(c.width, 20)
        XCTAssertEqual(c.height, 20)
        let px = ImageCodec.rgba(c)
        func at(_ x: Int, _ y: Int) -> [UInt8] { Array(px[(y * 20 + x) * 4..<(y * 20 + x) * 4 + 3]) }
        XCTAssertEqual(at(2, 2), [255, 0, 0])                       // first cover: top left
        XCTAssertEqual(at(17, 2), [0, 255, 0])                      // second cover: top right
        XCTAssertEqual(at(2, 17), [0, 0, 255])                      // third cover: bottom left
    }

    func testPlaylistArtFiles() throws {
        let volume = FileManager.default.temporaryDirectory.appendingPathComponent("ipodfirm-playlists-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: volume) }
        try ITunesDB.makeLibrary(at: volume, songs: 1, tracks: 30, seconds: 1)
        let image = volume.appendingPathComponent("wide.png")
        try ImageCodec.pngData(ImageCodec.cgImage(rgba: (0..<(300 * 100)).flatMap { _ in [0, 0, 255, 255] }, width: 300, height: 100)!)!.write(to: image)
        try MusicImport.setPlaylistArt(volume: volume, name: "Road Trip", image: image)
        let custom = try XCTUnwrap(MusicImport.customPlaylistArt(volume: volume, name: "Road Trip"))
        XCTAssertEqual(ArtworkDB.image(custom)?.width, 100)         // the centre square
        let lists = try MusicImport.playlists(volume: volume)
        XCTAssertEqual(lists.map(\.name), ["Test Album 1", "Road Trip"])
        XCTAssertEqual(lists.map(\.isCustom), [false, true])
        try MusicImport.removePlaylistArt(volume: volume, name: "Road Trip")
        XCTAssertNil(MusicImport.customPlaylistArt(volume: volume, name: "Road Trip"))
    }

    func testAlbumArtFile() throws {
        // a 2x2 PNG, red
        let img = ImageCodec.cgImage(rgba: [255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255], width: 2, height: 2)!
        let png = ImageCodec.pngData(img)!
        let f = AlbumArt.build(["Charm": png, "Burials": png], size: 4)
        XCTAssertEqual(Array(f[0..<4]), Array("IFAT".utf8))
        XCTAssertEqual(le16(f, 6), 4)
        XCTAssertEqual(le32(f, 8), 2)
        let h0 = le32(f, 16), h1 = le32(f, 24)
        XCTAssertLessThan(h0, h1)
        XCTAssertEqual(Set([h0, h1]), Set([AlbumArt.fnv1a("Charm"), AlbumArt.fnv1a("Burials")]))
        XCTAssertEqual(AlbumArt.fnv1a("Charm"), 0x07df43f0)    // same value as the Python version
        let first = Int(le32(f, 20))
        XCTAssertEqual(le16(f, first), 0xF800)          // pure red in RGB565
        XCTAssertEqual(f.count, 16 + 16 + 2 * 4 * 4 * 2)
        XCTAssertEqual(le32(f, 12), 0x55763f97)                 // stamp: same value as the Python version
    }

    /// The cover-flow patch: three word hooks into the extended area. It fits with the other patches.
    func testCoverFlow() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: Self.repo.appendingPathComponent("patches"))
        let flow = all.filter { $0.spec.name == "cover-flow" }
        XCTAssertEqual(flow.count, 1)
        let out = try Patcher.apply(flow, to: osos)
        for (at, old) in [(0x6772c0, 0x0023b704), (0x6701f0, 0x001d81cc), (0x17ef8c, 0x0017ef98)] as [(Int, UInt32)] {
            XCTAssertEqual(le32(osos, at), old)
            XCTAssertGreaterThanOrEqual(le32(out, at), 0x736800)       // a function in the extended area
        }
        let others = ["album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input", "backlight-60s", "usb-host-probe", "cover-flow"]
        let set = all.filter { others.contains($0.spec.name) }
        XCTAssertTrue(Patcher.conflicts(set).isEmpty)
        _ = try Patcher.apply(set, to: osos)
    }
}

final class EmulatorDriveTests: XCTestCase {
    func testFixOSOSLength() throws {
        // MBR, firmware partition at sector 1; directory at partition + 0x4200; osos at devOffset 0x4E00 (base 0x200)
        var img = [UInt8](repeating: 0, count: 0x10000)
        img[510] = 0x55; img[511] = 0xAA
        put32(&img, 0x1BE + 8, 1)
        let part = 512
        put32(&img, part + 0x104, 0x4000)
        let dir = part + 0x4200
        img.replaceSubrange(dir..<dir + 8, with: Array("!ATAsoso".utf8))
        put32(&img, dir + 12, 0x4E00)
        put32(&img, dir + 16, 0x100)                    // too short
        let data = part + 0x200 + 0x4E00
        for i in 0..<0x300 { img[data + i] = UInt8(i & 0xFF) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drive-\(UUID()).img")
        try Data(img).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(try EmulatorDrive.fixOSOSLength(drive: url, ososLength: 0x300))
        let out = [UInt8](try Data(contentsOf: url))
        XCTAssertEqual(le32(out, dir + 16), 0x300)
        XCTAssertEqual(le32(out, dir + 28), byteSum(out[data..<data + 0x300]))
        XCTAssertFalse(try EmulatorDrive.fixOSOSLength(drive: url, ososLength: 0x300))   // already correct
    }
}

/// Reads real music files from IPODFW_MUSIC and compares with the values in IPODFW_MUSIC_EXPECT
/// (JSON lines from the Python reader: path, title, album, artist, track).
final class MP4TagsTests: XCTestCase {
    func testAgreesWithPythonReader() throws {
        guard let expect = ProcessInfo.processInfo.environment["IPODFW_MUSIC_EXPECT"] else { throw XCTSkip("set IPODFW_MUSIC_EXPECT") }
        let lines = try String(contentsOfFile: expect, encoding: .utf8).split(separator: "\n")
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            let j = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            let t = try MP4Tags.read(URL(fileURLWithPath: j["path"] as! String))
            XCTAssertEqual(t.title, j["title"] as? String)
            XCTAssertEqual(t.album, j["album"] as? String)
            XCTAssertEqual(t.artist, j["artist"] as? String)
            XCTAssertEqual(t.track, j["track"] as? Int)
            XCTAssertEqual(t.lengthMS, j["length_ms"] as? Int)
            XCTAssertEqual(t.cover != nil, j["cover"] as? Bool)
        }
    }
}

/// makeRoom, the flash rules for a moved rsrc, and the theme import. Needs IPODFW_IPSW (1.3).
final class ThemeTests: XCTestCase {
    var stock: [UInt8] = []

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        stock = try IPSW.extractFirmware(URL(fileURLWithPath: path)).data
    }

    /// Apple's file with a hibe image after aupd and 32 MB of free space (as on the iPod).
    func ipodLayout() -> [UInt8] {
        var d = stock
        let dir = 0x4200 + 3 * 40, hibeOff = 0xd43800, hibeLen = 0x4000
        d += [UInt8](repeating: 0, count: 2048 + hibeOff + hibeLen + 0x2000000 - d.count)
        d.replaceSubrange(dir..<dir + 8, with: Array("!ATAebih".utf8))
        put32(&d, dir + 12, UInt32(hibeOff)); put32(&d, dir + 16, UInt32(hibeLen))
        d.replaceSubrange(2048 + hibeOff..<2048 + hibeOff + hibeLen, with: [UInt8](repeating: 0x55, count: hibeLen))
        return d
    }

    /// The layout of an iPod that iTunes restored: no hibe entry, a stale dump after aupd.
    /// A restore writes the file content, removes the hibe entry, and leaves the old dump.
    /// `free` must hold rsrc (0x500800 bytes) after the stale data.
    func restoredLayout(stale: Int = 0x2000, free: Int = 0x510000) -> [UInt8] {
        var d = stock
        let fw = try! FirmwarePartition(data: stock)
        let aupdEnd = Int(try! fw.entry("aupd").devOffset + fw.entry("aupd").length)
        let staleAt = (aupdEnd + 0x7FF) / 0x800 * 0x800
        d += [UInt8](repeating: 0, count: 2048 + staleAt + stale + free - d.count)
        d.replaceSubrange(2048 + staleAt..<2048 + staleAt + stale, with: [UInt8](repeating: 0x66, count: stale))
        return d
    }

    func larger(_ fw: FirmwarePartition) throws -> [UInt8] {
        let osos = try fw.image("osos") + [UInt8](repeating: 1, count: 40_000)
        try fw.makeRoom(ososLength: osos.count)
        try fw.replaceImage("osos", with: osos)
        return osos
    }

    func testMakeRoomInAFileMovesRsrcAndAupd() throws {
        let fw = try FirmwarePartition(data: stock)
        let rsrc = try fw.image("rsrc"), aupd = try fw.image("aupd")
        let osos = try larger(fw)
        let again = try FirmwarePartition(data: fw.data)
        XCTAssertEqual(try again.image("osos"), osos)
        XCTAssertTrue(again.checksumOK("osos") && again.checksumOK("rsrc"))
        XCTAssertEqual(try again.image("rsrc"), rsrc)
        XCTAssertEqual(try again.image("aupd"), aupd)
        XCTAssertLessThan(again.data.count, 16 << 20)           // the emulator limit
    }

    func testMakeRoomOnAnIPodMovesOnlyRsrc() throws {
        let data = ipodLayout()
        let current = try FirmwarePartition(data: data)
        let fw = try FirmwarePartition(data: data)
        _ = try larger(fw)
        XCTAssertEqual(fw.data.count, data.count)
        XCTAssertEqual(try fw.entry("aupd").devOffset, try current.entry("aupd").devOffset)
        XCTAssertGreaterThan(try fw.entry("rsrc").devOffset, try current.entry("hibe").devOffset)
        XCTAssertEqual(try fw.image("rsrc"), try current.image("rsrc"))
        try FirmwareFlasher.checkCompatible(current: current, new: FirmwarePartition(data: fw.data), label: "t")
        let protected = try current.imageRange("aupd")
        XCTAssertNoThrow(try FirmwareFlasher.planWrites(current: data, new: fw.data, blockSize: 2048, protected: protected))
    }

    func testCheckCompatibleRefusesRsrcOverHibe() throws {
        let current = try FirmwarePartition(data: ipodLayout())
        let new = try FirmwarePartition(data: current.data)
        var e = try new.entry("rsrc")
        e.devOffset = try current.entry("hibe").devOffset
        new.writeEntry(e)
        XCTAssertThrowsError(try FirmwareFlasher.checkCompatible(current: current, new: FirmwarePartition(data: new.data), label: "t"))
    }

    func testFitLayoutPutsAFileIntoTheIPodLayout() throws {
        let current = try FirmwarePartition(data: ipodLayout())
        let file = try FirmwarePartition(data: stock)
        let osos = try larger(file)
        let fitted = try FirmwarePartition(data: FirmwareFlasher.fitLayout(new: file.data, current: current))
        XCTAssertEqual(try fitted.image("osos"), osos)
        XCTAssertEqual(try fitted.entry("aupd").devOffset, try current.entry("aupd").devOffset)
        XCTAssertEqual(try fitted.entry("hibe").devOffset, try current.entry("hibe").devOffset)
        try FirmwareFlasher.checkCompatible(current: current, new: fitted, label: "t")
        XCTAssertEqual(try FirmwareFlasher.fitLayout(new: current.data, current: current), current.data)   // a restore
    }

    /// A restore leaves a stale hibernation dump after aupd: makeRoom must move rsrc past it.
    func testMakeRoomOnARestoredIPodMovesRsrcPastTheStaleData() throws {
        let data = restoredLayout()
        let current = try FirmwarePartition(data: data)
        let fw = try FirmwarePartition(data: data)
        let aupd = try current.entry("aupd")
        let aupdEnd = Int(aupd.devOffset) + Int(aupd.length)
        let staleAt = (aupdEnd + 0x7FF) / 0x800 * 0x800
        _ = try larger(fw)
        XCTAssertEqual(fw.data.count, data.count)
        XCTAssertEqual(try fw.entry("aupd").devOffset, aupd.devOffset)
        let rsrcAt = Int(try fw.entry("rsrc").devOffset)
        XCTAssertGreaterThanOrEqual(rsrcAt, staleAt + 0x2000)
        XCTAssertEqual(try fw.image("rsrc"), try current.image("rsrc"))
        // the stale data stays where it is: the move does not write into it
        XCTAssertEqual(Array(fw.data[2048 + staleAt..<2048 + staleAt + 0x2000]), [UInt8](repeating: 0x66, count: 0x2000))
        try FirmwareFlasher.checkCompatible(current: current, new: FirmwarePartition(data: fw.data), label: "t")
    }

    /// When stale data fills the rest of the partition, rsrc has no empty area: refuse.
    func testMakeRoomRefusesWhenThePartitionHasNoEmptyArea() throws {
        // 0x501000 bytes of stale data: more than rsrc (0x500800), to the end of the partition
        let data = restoredLayout(stale: 0x501000, free: 0)
        let fw = try FirmwarePartition(data: data)
        XCTAssertThrowsError(try larger(fw)) { e in
            XCTAssertEqual((e as? FirmwareError)?.message, "The firmware partition has no empty area for rsrc.")
        }
    }

    /// The file has a hibe image, the restored iPod has none: the result follows the iPod.
    func testFitLayoutDropsTheFilesHibeWhenTheIPodHasNone() throws {
        let current = try FirmwarePartition(data: restoredLayout())
        let file = try FirmwarePartition(data: ipodLayout())
        let fitted = try FirmwarePartition(data: FirmwareFlasher.fitLayout(new: file.data, current: current))
        XCTAssertFalse(fitted.has("hibe"))
        XCTAssertEqual(try fitted.entry("aupd").devOffset, try current.entry("aupd").devOffset)
        XCTAssertEqual(try fitted.image("osos"), try file.image("osos"))
        try FirmwareFlasher.checkCompatible(current: current, new: fitted, label: "t")
    }

    func testMergeWords() {
        func w(_ v: [UInt32]) -> [UInt8] { ThemeImport.bytes(v) }
        let (out, lost) = ThemeImport.mergeWords(base: w([1, 2, 3, 4]), theme: w([1, 9, 3, 8]), target: w([1, 2, 7, 3, 5]))
        XCTAssertEqual(ThemeImport.words(out), [1, 9, 7, 3, 5])
        XCTAssertEqual(lost, 1)
    }

    /// The Swift import must give the same theme as `ipodfw import-theme` (IPODFW_THEME_EXPECT).
    func testImportAgreesWithPython() throws {
        let env = ProcessInfo.processInfo.environment
        guard let themePath = env["IPODFW_THEME"], let basePath = env["IPODFW_THEME_BASE"], let expect = env["IPODFW_THEME_EXPECT"] else {
            throw XCTSkip("set IPODFW_THEME, IPODFW_THEME_BASE and IPODFW_THEME_EXPECT")
        }
        let python = try ImportedTheme.load(URL(fileURLWithPath: expect))
        let themeBytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: themePath)))
        let base = try IPSW.extractFirmware(URL(fileURLWithPath: basePath)).data
        let theme = try ThemeImport.make(theme: FirmwarePartition(data: themeBytes), base: FirmwarePartition(data: base),
                                         target: FirmwarePartition(data: stock), name: python.name,
                                         sourceSHA256: ThemeImport.sha256(themeBytes))
        XCTAssertEqual(theme.skipped, python.skipped)
        XCTAssertEqual(theme.imported, python.imported)
        XCTAssertEqual(theme.changes.count, python.changes.count)
        XCTAssertEqual(theme, python)
        var osos = try FirmwarePartition(data: stock).image("osos")
        let r = try theme.apply(to: &osos, originalSHA256: theme.osos_sha256)
        XCTAssertEqual(r.conflicts, 0)
    }

    /// Writes the dark theme plus the album-art patch, built as "Run in Emulator" builds it, to
    /// IPODFW_THEMED_OUT (for a check in the emulator).
    func testWriteThemedFirmware() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["IPODFW_THEMED_OUT"], let themeFile = env["IPODFW_THEME_EXPECT"], let ipsw = env["IPODFW_IPSW"] else {
            throw XCTSkip("set IPODFW_THEMED_OUT, IPODFW_THEME_EXPECT and IPODFW_IPSW")
        }
        let theme = try ImportedTheme.load(URL(fileURLWithPath: themeFile))
        let fw = try FirmwarePartition(data: stock)
        var osos = try fw.image("osos")
        let original = ThemeImport.sha256(osos)
        XCTAssertEqual(try theme.apply(to: &osos, originalSHA256: original).conflicts, 0)
        let patchesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../patches").standardized
        let patches = Patcher.list(in: patchesDir).filter { $0.spec.name == "album-art" }
        XCTAssertEqual(patches.count, 1)
        osos = try Patcher.apply(patches, to: osos, originalSHA256: original)
        let firmware = try IPSW.firmware(original: URL(fileURLWithPath: ipsw), withOSOS: osos)
        let check = try FirmwarePartition(data: firmware)
        XCTAssertTrue(check.checksumOK("osos") && check.checksumOK("rsrc"))
        try Data(firmware).write(to: URL(fileURLWithPath: out))
    }
}

final class ArtworkDBTests: XCTestCase {
    /// The Swift ArtworkDB must be byte-identical with the Python one for the same items
    /// (src/ipodfw/artworkdb.py, tests/test_artworkdb.py). Only the scaled pixels in the .ithmb files can differ.
    func testAgreesWithPython() throws {
        let ctx = CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 1200,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let image = ctx.makeImage()!
        let items = (0..<3).map { ArtworkDB.Item(trackDBID: 0x1000_0000_0000 + UInt64($0), image: image, originalSize: 1000 + UInt32($0)) }
        let (db, ithmb) = ArtworkDB.build(items)
        XCTAssertEqual(ThemeImport.sha256(db), "7101a7be8ff4935641ade5919f906c1762a415c8f30c5bee2ea5c379b981add0")
        XCTAssertEqual(ithmb["F1028_1.ithmb"]?.count, 3 * 100 * 100 * 2)
        XCTAssertEqual(ithmb["F1029_1.ithmb"]?.count, 3 * 200 * 200 * 2)
    }

    func testTrackArtworkFields() {
        var t = DBTrack(title: "T", artist: "A", album: "B", path: ":iPod_Control:Music:F00:T0.m4a", size: 100, lengthMS: 1000)
        t.dbid = 0x1234; t.imageID = 100; t.artworkSize = 5555
        let db = ITunesDB.build([t])
        let mhit = (0..<db.count - 4).first { Array(db[$0..<$0 + 4]) == Array("mhit".utf8) }!
        XCTAssertEqual(le32(db, mhit + 0x70), 0x1234)
        XCTAssertEqual(le16(db, mhit + 0x7C), 1)
        XCTAssertEqual(le32(db, mhit + 0x80), 5555)
        XCTAssertEqual(db[mhit + 0xA4], 1)
        XCTAssertEqual(le32(db, mhit + 0x160), 100)
    }
}

/// Writes a library from IPODFW_MUSIC to IPODFW_MUSIC_LIBRARY_OUT with the Swift writers, as the
/// Emulator pane does (for a check of the artwork in the emulator).
final class MusicLibraryOutputTests: XCTestCase {
    func testWriteMusicLibrary() throws {
        let env = ProcessInfo.processInfo.environment
        guard let music = env["IPODFW_MUSIC"], let out = env["IPODFW_MUSIC_LIBRARY_OUT"] else {
            throw XCTSkip("set IPODFW_MUSIC and IPODFW_MUSIC_LIBRARY_OUT")
        }
        let songs = MusicImport.pick(MusicImport.scan(URL(fileURLWithPath: music)), limit: 8, perAlbum: 1)
        try MusicImport.makeLibrary(from: songs, to: URL(fileURLWithPath: out), copyAudio: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out + "/iPod_Control/Artwork/ArtworkDB"))
    }
}

/// The patcher options that the dark-mode build uses. Needs IPODFW_IPSW.
final class PatcherOptionTests: XCTestCase {
    func testLoadAddressAndSizeLimit() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        let patch = Patcher.list(in: repo.appendingPathComponent("patches")).first { $0.spec.name == "album-art" }!
        let sha = ThemeImport.sha256(osos)
        XCTAssertThrowsError(try Patcher.apply(patch, to: osos, originalSHA256: sha, loadAddress: 0x7eb000))
        let out = try Patcher.apply(patch, to: osos, originalSHA256: sha, loadAddress: 0x7eb000, maxSize: 0x7F0000)
        XCTAssertEqual(out.count % 0x800, 0)
        XCTAssertTrue((0x7eb000..<0x7F0000).contains(Int(le32(out, 0x677a14))))
    }

    /// A patch option: the patcher writes the selected value into the variable of the option.
    /// The up-next option "hold": 3 (the default), 0, 1 or 2. Another value stops the build.
    func testPatchOption() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        var patch = Patcher.list(in: repo.appendingPathComponent("patches")).first { $0.spec.name == "up-next" }!
        let standard = try Patcher.apply([patch], to: osos)
        patch.options = ["hold": 1]
        let next = try Patcher.apply([patch], to: osos)
        XCTAssertEqual(standard.count, next.count)
        let changed = standard.indices.filter { standard[$0] != next[$0] }
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed.first.map { $0 & 3 }, 0)
        XCTAssertEqual(changed.first.map { le32(next, $0) }, 1)
        XCTAssertEqual(changed.first.map { le32(standard, $0) }, 3)
        patch.options = ["hold": 7]
        XCTAssertThrowsError(try Patcher.apply([patch], to: osos))
    }

    /// The usb-host-probe patch: the extended area, a bl in the UI event handler and two driver table words.
    /// The space measurement agrees with a real build, and finds a build that is too large.
    func testSpaceUse() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: PatchAndArtTests.repo.appendingPathComponent("patches"))
        let set = all.filter { ["album-art", "flash-wake-on-input", "usb-host-probe"].contains($0.spec.name) }
        let sizes = try set.map { (patch: $0, size: try Patcher.codeSize($0)) }
        XCTAssertGreaterThan(sizes.first { $0.patch.spec.name == "usb-host-probe" }!.size, 1000)
        let use = Patcher.spaceUse(osos: osos, patches: sizes)
        XCTAssertEqual(use.end, try Patcher.apply(set, to: osos).count)
        XCTAssertTrue(use.fits)
        // patches with menus ("settings_items", "menu_items"): the measurement counts the menus,
        // and the patches follow each other without a 0x800 gap
        let menus = all.filter { ["album-art", "album-artists", "cover-flow", "instant-save", "something-comforting", "usb-host-probe"].contains($0.spec.name) }
        let menuSizes = try menus.map { (patch: $0, size: try Patcher.codeSize($0)) }
        let built = try Patcher.apply(menus, to: osos)
        let menuUse = Patcher.spaceUse(osos: osos, patches: menuSizes)
        XCTAssertEqual(menuUse.end, built.count)
        // the parts of the bar: one for each patch in build order, then the rounding; their sum is the used space
        XCTAssertEqual(menuUse.parts.reduce(0) { $0 + $1.bytes }, menuUse.used)
        XCTAssertEqual(menuUse.parts.compactMap { if case .patch(let n) = $0.kind { n } else { nil } }, menus.map(\.spec.name))
        XCTAssertTrue(menuUse.parts.allSatisfy { $0.bytes > 0 })
        let data = menuSizes.reduce(0) { $0 + $1.size } + (4 + 40 * 11) + (4 + 40 * 32) + (4 + 40 * 29) + (4 + 40 * 19)
        XCTAssertLessThan(built.count - Patcher.maxOSOSSize, data + 6 * 16 + 0x800)     // only the alignment and one rounding
        // after other data that leaves too little space
        let probe = sizes.first { $0.patch.spec.name == "usb-host-probe" }!
        let filled = osos + [UInt8](repeating: 0, count: Patcher.SpaceUse.limit - 0x800 - osos.count) + [1]
        let over = Patcher.spaceUse(osos: filled, patches: [probe])
        XCTAssertFalse(over.fits)
        XCTAssertThrowsError(try Patcher.apply([probe.patch], to: filled, originalSHA256: Patcher.sha256(osos)))
    }

    func testUSBHostProbe() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        let all = Patcher.list(in: repo.appendingPathComponent("patches"))
        let probe = all.filter { $0.spec.name == "usb-host-probe" }
        XCTAssertEqual(probe.count, 1)
        let out = try Patcher.apply(probe, to: osos)
        XCTAssertGreaterThan(out.count, Patcher.maxOSOSSize)
        XCTAssertEqual(le32(out, 0x1d8260) & 0xFF00_0000, 0xEB00_0000)
        XCTAssertNotEqual(le32(out, 0x1d8260), le32(osos, 0x1d8260))
        // the wrappers are in the probe code, which starts at 0x736800 and is shorter than 24 KB (version 1.21: 19760 bytes)
        for at in [0x6c8730, 0x6c878c] { XCTAssertTrue((Patcher.maxOSOSSize..<Patcher.maxOSOSSize + 0x6000).contains(Int(le32(out, at)))) }
        // after other data (a theme and the Dark Mode items to 0x7eb123): the probe goes after it
        var filled = osos + [UInt8](repeating: 0, count: 0x7eb123 - osos.count)
        filled[0x7eb122] = 1
        let after = try Patcher.apply(probe, to: filled, originalSHA256: ThemeImport.sha256(osos))
        XCTAssertTrue((0x7eb130..<0x7eb130 + 0x6000).contains(Int(le32(after, 0x6c8730))))
        // with the other code patches: different areas and hook sites
        let names = ["album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input", "usb-host-probe"]
        _ = try Patcher.apply(all.filter { names.contains($0.spec.name) }, to: osos)
    }
}

/// The USB log of usb-host-probe, with the root hub record that the emulator wrote (2026-10-07).
/// The text log of playback-log: the information block with the iPodFirm list, the lines, then zero bytes.
final class PlaybackLogTests: XCTestCase {
    func testText() throws {
        let list = String(decoding: try JSONEncoder().encode(FirmwareManifest(app: "0.1.180 (181)", patches: [
            .init(name: "up-next", version: "0.5", options: ["hold": 3]), .init(name: "shuffle-fixes", version: "2.2"), .init(name: "user-patch", version: "1.0")])), as: UTF8.self)
        let info = "PL01 playback-log 1.0\nram=32 MB heap=3100000 lowest=2900000 failed=0\nlines=2 dropped=0 lost=0 writes=1\nlist " + list
        var d = [UInt8](info.utf8) + [UInt8](repeating: 0x20, count: 2047 - info.utf8.count) + [0x0A]
        d += [UInt8]("     0.000 shuffle start count=60\n     0.012 shuffle end result=1\n".utf8)
        d += [UInt8](repeating: 0, count: PlaybackLog.fileSize - d.count)
        XCTAssertEqual(PlaybackLog.text(d, letters: ["shuffle-fixes": "f", "up-next": "n"]), """
            PL01 playback-log 1.0
            ram=32 MB heap=3100000 lowest=2900000 failed=0
            lines=2 dropped=0 lost=0 writes=1
            app: 0.1.180 (181)
            patches: 3, letters fn
              n up-next 0.5 hold=3
              f shuffle-fixes 2.2
              - user-patch 1.0
            0.000 shuffle start count=60
            0.012 shuffle end result=1
            """)
        XCTAssertNil(PlaybackLog.text([UInt8](repeating: 0, count: PlaybackLog.fileSize)))
        XCTAssertNil(PlaybackLog.text([UInt8]("VL01".utf8)))
        XCTAssertNil(PlaybackLog.text([UInt8]("PL03 other\n".utf8)))
        XCTAssertEqual(PlaybackLog.text([UInt8]("PL02 diagnostic-log 2.0\nareas playback=1 memory=0 power=0 artwork=0 performance=0\nlist none\n".utf8)),
                       "PL02 diagnostic-log 2.0\nareas playback=1 memory=0 power=0 artwork=0 performance=0\npatches: not known (none)")
        XCTAssertEqual(PlaybackLog.text([UInt8]("PL01 playback-log 1.0\nlist none\n".utf8)), "PL01 playback-log 1.0\npatches: not known (none)")
    }

    /// A line with a track ID gets the song, and a list at the end has each song in the log.
    func testSongs() {
        let log = "PL01 playback-log 1.1\nsettings shuffle=Songs repeat=Off hold=Play Next\n"
        let lines = "     0.033   shuffle n=2 first=1a,2b,0 heap=1\n     0.314 play from=abc5c song=1a flags=1 heap=2\n     1.000   set song failed: -50 song=99 heap=2\n"
        let d = [UInt8](log.utf8) + [UInt8](lines.utf8)
        let songs = [ITunesDB.TrackInfo(id: 1, dbidLow: 0x1a, title: "One", artist: "A", album: "B", path: ":iPod_Control:Music:F00:X.mp3"),
                     ITunesDB.TrackInfo(id: 2, dbidLow: 0x2b, title: "Two", artist: "C", album: "D", path: ":P")]
        let text = PlaybackLog.text(d, songs: songs) ?? ""
        XCTAssertTrue(text.contains("0.314 play from=abc5c song=1a flags=1 heap=2 \"One\" - A"))
        XCTAssertTrue(text.contains("  ID 1a: One | A | B | :iPod_Control:Music:F00:X.mp3"))
        XCTAssertTrue(text.contains("  ID 2b: Two | C | D | :P"))
        XCTAssertTrue(text.contains("  ID 99 is not in the iTunesDB"))
        XCTAssertTrue(text.contains("set song failed: -50 song=99 heap=2 (ID 99 is not in the iTunesDB)"))
        XCTAssertFalse(text.contains("ID 0 "))
        XCTAssertFalse((PlaybackLog.text(d) ?? "").contains("Songs in this log"))
    }

    func testFileName() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 29; c.hour = 23; c.minute = 15
        let date = Calendar.current.date(from: c)!
        XCTAssertEqual(PlaybackLog.fileName(date: date), "iPodFirm Playback Log 2026-10-29 2315.txt")
    }

    /// The new issue has the information lines of the log, not the timed lines, and a short body.
    func testIssueURL() throws {
        let log = "PL01 playback-log 1.0\nram=32 MB heap=3100000 lowest=2900000 failed=0\npatches: 2, letters fn\n0.000 play from=ac5b8\n1.500 stop: no next song"
        let url = PlaybackLog.issueURL(log: log, appVersion: "0.1.180 (181)", fileName: "log.txt")
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.host, "github.com")
        XCTAssertEqual(c.path, "/TheFauxDreamer/iPod5.5Firm/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["title"], "Playback log: the music stops")
        let body = try XCTUnwrap(items["body"])
        XCTAssertTrue(body.contains("ram=32 MB"))
        XCTAssertTrue(body.contains("letters fn"))
        XCTAssertTrue(body.contains("\"log.txt\""))
        XCTAssertTrue(body.contains("0.1.180 (181)"))
        XCTAssertFalse(body.contains("stop: no next song"))
        let long = PlaybackLog.issueURL(log: String(repeating: "patch line\n", count: 1000), appVersion: "1", fileName: "f.txt")
        let longBody = URLComponents(url: long, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value ?? ""
        XCTAssertLessThanOrEqual(longBody.count, 1500)
    }
}

final class USBProbeLogTests: XCTestCase {
    func testParseRootHubAndInterface() {
        var d = [UInt8]("UL01".utf8) + [2, 0, 0, 0]
        let hub: [UInt8] = [18, 1, 0, 2, 9, 0, 0, 64, 0xAC, 0x05, 0x31, 0x80, 0, 1, 1, 2, 0, 1]
        func record(_ tag: UInt8, _ r1: [UInt8], _ r2: [UInt8]) -> [UInt8] {
            [0xA5, tag, 0, 0] + [UInt8](repeating: 0, count: 16)
                + r1 + [UInt8](repeating: 0, count: 20 - r1.count) + r2 + [UInt8](repeating: 0, count: 20 - r2.count) + [0, 0, 0, 0]
        }
        d += record(2, hub, [])                                              // hub: initialize device
        d += record(15, [9, 4, 0, 0, 2, 8, 6, 0x50, 0], hub)                 // storage: initialize interface
        var port = record(30, [], [])                                        // root port: connected, power, change connection
        port.replaceSubrange(4..<16, with: [1, 0, 0, 0, 0x01, 0x01, 0x01, 0x00, 0x01, 0x10, 0x00, 0x08])
        d += port
        var regs = record(31, [], [])                                        // controller registers
        regs.replaceSubrange(4..<20, with: [1, 0, 0, 0, 0, 0x10, 0, 0, 0x01, 0x10, 0, 0, 0, 0x0E, 0, 0])
        d += regs
        d[4] = 4
        let log = USBProbeLog.parse(d)!
        XCTAssertEqual(log.count, 4)
        XCTAssertEqual(log[3].text, "Controller: USBCMD 0x00000001 (run), USBSTS 0x00001000 (halted), PORTSC 0x00001001 (connected, power, full speed), OTGSC 0x00000E00 (VBUS valid, B-session valid, A-session valid)")
        XCTAssertEqual(log[2].text, "Root port 1: status 0x0101 (connected, power), change 0x0001 (connection), PORTSC 0x08001001 (connected, power, high speed, line SE0)")
        XCTAssertEqual(log[0].text, "Hub: initialize device — device 05AC:8031, class 09/00/00 (hub)")
        XCTAssertEqual(log[1].text, "Storage: initialize interface — interface 0 (alternate 0), class 08/06/50 (storage) — device 05AC:8031, class 09/00/00 (hub)")
        XCTAssertNil(USBProbeLog.parse([UInt8](repeating: 0, count: 4096)))
        // the setup packets that the emulator logged for the root hub
        XCTAssertEqual(USBProbeLog.stageText(1, [0x80, 6, 0, 1, 0, 0, 0x12, 0]), "setup: GET_DESCRIPTOR device 0, 18 bytes")
        XCTAssertEqual(USBProbeLog.stageText(1, [0, 5, 0x30, 0, 0, 0, 0, 0]), "setup: SET_ADDRESS 48")
        XCTAssertEqual(USBProbeLog.stageText(0, []), "status stage")
        XCTAssertEqual(USBProbeLog.stageText(1, [UInt8](repeating: 0, count: 12)), "data stage, buffer 000000000000000000000000")
    }

    /// Data records (tag 44): a configuration descriptor of 51 bytes in two records of 40 bytes.
    func testConfigurationDescriptorData() {
        let config: [UInt8] = [9, 2, 51, 0, 2, 1, 0, 0x80, 50,
                               8, 11, 0, 2, 1, 0, 0x20, 0,                      // interface association, UAC2
                               9, 4, 1, 1, 1, 1, 2, 0x20, 0,                    // interface 1 alternate 1, streaming
                               7, 5, 0x01, 0x05, 0xC0, 0x00, 1,                 // endpoint 1 OUT isochronous, asynchronous
                               11, 0x24, 2, 1, 2, 2, 16, 1, 0x44, 0xAC, 0,      // UAC1 format type I, 44100 Hz
                               2, 0x24, 0, 0, 0, 0, 0]
        var d = [UInt8]("UL01".utf8) + [2, 0, 0, 0]
        for offset in stride(from: 0, to: config.count, by: 40) {
            let chunk = Array(config[offset..<min(config.count, offset + 40)])
            let regs = [UInt32(0x93C33E34), 0x93C40000, UInt32(offset), UInt32(config.count)]
            d += [0xA5, 44, 0, 0] + regs.flatMap { v in (0..<4).map { UInt8(v >> (8 * $0) & 0xFF) } }
            d += chunk + [UInt8](repeating: 0, count: 44 - chunk.count)
        }
        let log = USBProbeLog.parse(d)!
        XCTAssertEqual(log[0].text, "Data: configuration descriptor, bytes 0–39 of 51: " + config.prefix(40).map { String(format: "%02X", $0) }.joined())
        let lines = log.filter { $0.driver == "Configuration" }.map(\.call)
        XCTAssertEqual(lines.count, 6)
        XCTAssertTrue(lines[0].hasPrefix("configuration 1: total length 51, 2 interfaces, attributes 0x80, power 100 mA"))
        XCTAssertTrue(lines[1].hasPrefix("interface association: first interface 0, 2 interfaces, class 01/00/20 (audio)"))
        XCTAssertTrue(lines[2].hasPrefix("interface 1 alternate 1: 1 endpoints, class 01/02/20 (audio) (streaming), USB Audio Class 2"))
        XCTAssertTrue(lines[3].hasPrefix("endpoint 0x01 (OUT isochronous, asynchronous), max packet 192, interval 1"))
        XCTAssertTrue(lines[4].hasPrefix("audio class interface descriptor, subtype 2: format type 1, 2 channels, 2 bytes per sample, 16 bits, rates 44100 Hz"))
    }

    /// The timing record of usb-audio-out 1.5 (tag 76).
    func testTimingRecord() {
        XCTAssertEqual(USBProbeLog.audioText(76, [0x0107_0005, 0x0258_0136, 0x0302_00F5, 0x1802_0329]),
                       "timing 5 s — On, host mode, USB music route, playing; idle core 0 31.0 %, core 1 60.0 %; latest wake +24.5 ms, 2 wakes > 5 ms late, 3 > 20 ms; USBAudioTask 41 wakes, longest fill 0.3 ms, longest sleep +2 ms, fewest frames ahead 24")
        XCTAssertEqual(USBProbeLog.audioText(77, [1000, 0x0080_0003, 120, 81_500]),
                       "timing counts — 1000 USB interrupts, 3 siTD errors, host task 128 messages and 120 timeouts, packet fill 81.5 ms in total")
        XCTAssertEqual(USBProbeLog.audioText(77, [1, 0, 0x03E8_0078, 12_000]),
                       "timing counts — 1 USB interrupts, 0 siTD errors, host task 0 messages and 120 timeouts, packet fill 12.0 ms in total (1000 packets with the fast fill)")
        XCTAssertEqual(USBProbeLog.audioText(78, [44100, 44100, 0x0100_0001, 120_500]),
                       "timing source — input 44100 Hz, output 44100 Hz, converter flag 1, source +0 0, +1 0, route 1; Apple fill 120.5 ms")
        XCTAssertEqual(USBProbeLog.audioText(76, [0x0001_0000, 0x03E8_03DE, 0, 0]),
                       "timing 0 s — On, stopped; idle core 0 99.0 %, core 1 100.0 %; latest wake +0.0 ms, 0 wakes > 5 ms late, 0 > 20 ms")
    }

    /// The records of the isochronous test (tags 48–51).
    func testAudioRecords() {
        XCTAssertEqual(USBProbeLog.audioText(48, [116, 0x020201, 192, 9]),
                       "device found — address 116, interface 1 alternate 2, endpoint 2 OUT, max packet 192, clock source 9")
        XCTAssertEqual(USBProbeLog.audioText(49, [0x0002_0B01, 1, 0x0008_0E00, 0x8000_0D00]),
                       "SET_INTERFACE 1 alternate 2: correct, setup token 0x00080E00, status token 0x80000D00")
        XCTAssertEqual(USBProbeLog.audioText(49, [0x0100_0121, 0x0004_0900, 0x0008_0E00, 0x8000_0D40]),
                       "SET_CUR sampling frequency, clock 9: stall or error (0x40), setup token 0x00080E00, status token 0x80000D40")
        XCTAssertEqual(USBProbeLog.audioText(50, [1240, 3, 0x0000_0008, 0x0200_0010]),
                       "1 kHz tone: 1240 frames sent, 3 frames with an error, last error 0x00000008, frames 16 to 512")
        XCTAssertEqual(USBProbeLog.audioText(52, [44100, 0x010101, 1, 1]),
                       "music route on — 44100 Hz, output flags +0x58 1, +0x59 1, +0x5a 1 (1 = USB), stream 1")
        XCTAssertEqual(USBProbeLog.audioText(53, [60000, 2, 24, 0x0001_0101]),
                       "music — 60000 packets sent (60 s), 2 underruns, 24 packets with sound, route +0x5a 1, stream 1, source +0 1, +1 0 (1 = test signal)")
        XCTAssertEqual(USBProbeLog.audioText(55, [800, 200, 400, 10000]),
                       "CPU — 800 sleeps; probe copy 200 ms (2.0 %), Apple packet fill 400 ms (4.0 %) of 10000 ms")
        XCTAssertEqual(USBProbeLog.audioText(57, [10000, 853, 0, 2]), "CPU idle — host mode: 85.3 % (core 1 0.0 %) in 10000 ms")
        XCTAssertEqual(USBProbeLog.audioText(58, [9, 0, 120, 3000]), "art step 9 (artwork lookup) — result 0x0, 120 µs, at 3000 ms")
        XCTAssertEqual(USBProbeLog.audioText(59, [12, 4, 1, 250000]), "art summary step 12 (image load) — 4 calls, 1 with result 0, longest 250000 µs")
        XCTAssertEqual(USBProbeLog.audioText(60, [5, 9000, 1, 9000]), "art task — in step 5 (lock 1) for 9000 ms; last step 1, 9000 ms ago")
        XCTAssertEqual(USBProbeLog.audioText(60, [0, 0, 14, 20]), "art task — no step in progress; last step 14 (gate release), 20 ms ago")
        XCTAssertEqual(USBProbeLog.audioText(56, [1, 30000, 5, 2500]),
                       "music stopped — the dock was disconnected, 30000 packets, 5 siTD errors, 2500 sleeps")
        XCTAssertEqual(USBProbeLog.audioText(54, [0, 5, 0x0001_0302, 0xAC44_AC44]),
                       "decoder chain — codec buffers 0, USB buffers 5, queue write 2 read 3, ready flag 0x1081dff6 = 1, flag 0x1081dff4 = 0, music rate 44100 Hz, output rate 44100 Hz")
        XCTAssertEqual(USBProbeLog.audioText(62, [0x1088_0000, 0x10_0000, 3, 0x0001_0102]),
                       "art cache (host mode) — object 0x10880000, capacity +0x74 1048576, +0x78 3, +0x70 1, +0x71 1, +0x72 0")
        XCTAssertEqual(USBProbeLog.audioText(62, [0, 0, 0, 0]),
                       "art cache (before the host start) — object 0x00000000, capacity +0x74 0, +0x78 0, +0x70 0, +0x71 0, +0x72 0")
        XCTAssertEqual(USBProbeLog.audioText(63, [0x0402_0001, 0x1081_0000, 0x0001_0101, 0x1090_0000]),
                       "art gates — library open +0x54 1, +0x55 0, requests 2, count +0xc 4; photo import 0x10810000 state 1, active 1, the start object yes; play queue +4 0x10900000")
        XCTAssertEqual(USBProbeLog.audioText(63, [0, 0, 0xFFFF_FFFF, 0xFFFF_FFFF]),
                       "art gates — library open +0x54 0, +0x55 0, requests 0, count +0xc 0; no photo import service; no play queue object")
        XCTAssertEqual(USBProbeLog.audioText(64, [0x0102_0003, 500, 0, 5]),
                       "art queues (later) — library queue 3, cache queue 0, 2 cache entries, the art cache entry +8 = 1, library +0x30 500, task event 0x00000000")
        XCTAssertEqual(USBProbeLog.audioText(64, [0xFF00_0000, 0, 0, 0]),
                       "art queues (before the host start) — library queue 0, cache queue 0, 0 cache entries, no entry for the art cache, library +0x30 0, task event 0x00000000")
        XCTAssertEqual(USBProbeLog.audioText(65, [0x1390_0000, 0x1390_0000, 0x0001_0001, 0x0102]),
                       "art database (host mode) — ArtworkDB handle +0xd2c 0x13900000, +0xd14 0x13900000; app reload flag +0x484 1, +0x489 0, reload done +0x48a 1, +0x487 0; USB device state 1")
        XCTAssertEqual(USBProbeLog.audioText(65, [0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF, 0]),
                       "art database (before the host start) — no database object; no app object; USB device state 0")
        XCTAssertEqual(USBProbeLog.audioText(66, [0x6974_696C, 1200, 0x1390_0000, 0x00AB_CD07]),
                       "ArtworkDB — first word 0x6974696C (correct), 1200 entries, +6 0, index 0x13900000; list lookup correct, index lookup correct (dbid …00ABCD)")
        XCTAssertEqual(USBProbeLog.audioText(66, [0xFFFF_FFFF, 0, 0, 0]), "ArtworkDB — no ArtworkDB object")
        XCTAssertEqual(USBProbeLog.audioText(67, [0x29CB_FE07, 0, 0x0001_0002, 0x0102]),
                       "art add test 1 (host mode) — dbid …29CBFE07: +0x78 0 → 2, +0xc 0 → 1, added")
        XCTAssertEqual(USBProbeLog.audioText(67, [0x1234, 0x0001_0002, 0x0001_0002, 5]),
                       "art add test 0 (later) — dbid …00001234: +0x78 2 → 2, +0xc 1 → 1, nothing added")
        XCTAssertEqual(USBProbeLog.audioText(67, [0, 0xFFFF_FFFF, 0xFFFF_FFFF, 0]),
                       "art add test 0 (before the host start) — not run: no art cache or no ArtworkDB entry")
        XCTAssertEqual(USBProbeLog.audioText(68, [0xC400, 0, 0x100, 0x0108]),
                       "volume range — -60.0 dB to 0.0 dB, resolution 1.0000 dB, 1 sub-ranges")
        XCTAssertEqual(USBProbeLog.audioText(68, [0, 0, 0, 0xFF]), "volume range — no answer; the probe uses −60 dB to 0 dB")
        XCTAssertEqual(USBProbeLog.audioText(69, [128, 0xF3F5, 0x0000, 0x0003]),
                       "volume — iPod output 128 of 256 → -12.0 dB; status channel 1 0x00, channel 2 0x00; request 3, 0 errors")
        XCTAssertEqual(USBProbeLog.audioText(69, [0, 0x8000, 0x4040, 0x0001_0004]),
                       "volume — iPod output 0 of 256 → silence; status channel 1 0x40, channel 2 0x40; request 4, 1 errors")
        XCTAssertEqual(USBProbeLog.audioText(71, [0x0005_0203, 0x0000_0201, 0, 0]),
                       "button report — interface 3, 2 bytes: 0102; pushed: volume +, play/pause; 0 errors")
        XCTAssertEqual(USBProbeLog.audioText(71, [0x0000_0103, 0, 0, 0]), "button report — interface 3, 1 bytes: 00; pushed: none; 0 errors")
        XCTAssertEqual(USBProbeLog.hidDescriptorText([0x001F_0503, 0, 0x0102_0100, 0x0000_0403], [0x05, 0x0C, 0x09, 0x01] + [UInt8](repeating: 0, count: 36)),
                       "HID report descriptor — interface 3, endpoint 5 IN, 31 bytes; bytes 0–30: 050C0901000000000000000000000000000000000000000000000000000000; volume + bit 0, volume − bit 1, play/pause bit 2, next bit 3, previous bit 4, report ID 1, no array")
        XCTAssertEqual(USBProbeLog.hidDescriptorText([0x00FF_0503, 0, 0, 0], []), "HID report descriptor — interface 3: no answer")
        XCTAssertEqual(USBProbeLog.audioText(72, [0x047B, 1, 0x1390_0000, 0x1390_0000]),
                       "key posted — volume + (private) push, result 1, sender 0x13900000, app port 0x13900000")
        XCTAssertEqual(USBProbeLog.audioText(72, [0x073A, 0xFFFF_FFFF, 0, 0]), "key posted — stop release, result -1, sender 0x00000000, app port 0x00000000")
        XCTAssertEqual(USBProbeLog.audioText(72, [0x0120, 0, 0, 0]), "key to the UI task (0x1ac198) — volume + push")
        XCTAssertEqual(USBProbeLog.audioText(72, [0x001C, 0, 0, 0]), "key to the UI task (0x1ac198) — play/pause release")
        XCTAssertEqual(USBProbeLog.audioText(74, [5, 1, 1050, 0x0000_0E00]),
                       "device task — before the host start: the device session stopped (1050 ms); OTGSC 0x00000E00 (VBUS present)")
        XCTAssertEqual(USBProbeLog.audioText(74, [1, 1, 0, 0x0000_0200]),
                       "device task — the start of the device mode is blocked (host mode runs); OTGSC 0x00000200 (VBUS absent)")
        XCTAssertEqual(USBProbeLog.audioText(74, [6, 4, 0x68C, 0]), "USB host message not shown (host mode runs) — type 4, no driver")
        XCTAssertEqual(USBProbeLog.audioText(75, [1, 1, 0, 5]), "player — before the stop: playing; codec buffers 0, USB buffers 5")
        XCTAssertEqual(USBProbeLog.audioText(75, [2, 5, 3, 0]), "player — later: paused; codec buffers 3, USB buffers 0")
        XCTAssertEqual(USBProbeLog.audioText(75, [0, 3, 0, 0]), "player — after the pause key: stopped (0); codec buffers 0, USB buffers 0")
        XCTAssertEqual(USBProbeLog.audioText(74, [4, 0, 0, 0]),
                       "device task — the stop is skipped (host mode runs, no controller reset); OTGSC 0x00000000 (VBUS absent)")
        XCTAssertEqual(USBProbeLog.audioText(73, [0x057D, 50, 45, 0]), "key in the UI task — volume − (private) repeat, volume level 50 → 45")
    }
}

/// The setting "Firmware layout": the empty margin below 8 MB (32 KB or 64 KB).
final class OSOSMarginTests: XCTestCase {
    func testOptionsInSizeOrder() {
        let limits = ThemeImport.OSOSMargin.allCases.map(\.limit)
        XCTAssertEqual(limits, limits.sorted(by: >))         // a higher limit is a smaller margin
    }

    func testMarginSetting() {
        let key = ThemeImport.ososMarginKey
        let old = UserDefaults.standard.string(forKey: key)
        defer { if let old { UserDefaults.standard.set(old, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(ThemeImport.ososLimit, 0x7F8000)
        UserDefaults.standard.set(ThemeImport.OSOSMargin.previous.rawValue, forKey: key)
        XCTAssertEqual(ThemeImport.ososLimit, 0x7F0000)
        XCTAssertEqual(Patcher.SpaceUse.limit, 0x7F0000)
        XCTAssertFalse(Patcher.SpaceUse(end: 0x7F4000).fits)
        UserDefaults.standard.set("unknown", forKey: key)
        XCTAssertEqual(ThemeImport.ososLimit, 0x7F8000)
    }
}

final class DarkModeTests: XCTestCase {
    /// The owner's case: "Switch on iPod" with a large theme, then an extended patch (usb-host-probe).
    /// Needs IPODFW_IPSW and IPODFW_THEME (an .ipodtheme file).
    func testExtendedPatchAfterSwitchBuild() throws {
        let env = ProcessInfo.processInfo.environment
        guard let ipsw = env["IPODFW_IPSW"], let themePath = env["IPODFW_THEME"] else { throw XCTSkip("set IPODFW_IPSW and IPODFW_THEME") }
        let partition = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data)
        let osos = try partition.image("osos")
        let sha = ThemeImport.sha256(osos)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        let all = Patcher.list(in: repo.appendingPathComponent("patches"))
        let dark = all.first { $0.spec.name == "dark-mode" }!
        let theme = try ImportedTheme.load(URL(fileURLWithPath: themePath))
        let (switched, info) = try DarkMode.build(partition: partition, osos: osos, theme: theme, patch: dark, originalSHA256: sha)
        // The size in the Patches pane is the end of the dark-mode code after the build.
        let size = try DarkMode.addedSize(partition: partition, osos: osos, theme: theme, codeSize: dark.spec.size!)
        XCTAssertEqual(Patcher.maxOSOSSize + size, info.patchAt + dark.spec.size!)
        XCTAssertTrue(switched[(info.patchAt + dark.spec.size!)...].allSatisfy { $0 == 0 })
        XCTAssertLessThanOrEqual(theme.addedSize, size)
        let probe = all.filter { $0.spec.name == "usb-host-probe" }
        let out = try Patcher.apply(probe, to: switched, originalSHA256: sha)
        XCTAssertGreaterThan(Int(le32(out, 0x6c8730)), info.patchAt)
        XCTAssertLessThanOrEqual(out.count, ThemeImport.ososLimit)
    }

    /// The example patch something-comforting: alone, and after "Switch on iPod". Its hooks chain to the
    /// Dark Mode hooks, and the Settings menu has both items. Needs IPODFW_IPSW.
    func testSomethingComfortingAloneAndAfterSwitchBuild() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let partition = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data)
        let osos = try partition.image("osos")
        let sha = ThemeImport.sha256(osos)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        let all = Patcher.list(in: repo.appendingPathComponent("patches"))
        let dark = all.first { $0.spec.name == "dark-mode" }!
        let melody = all.filter { $0.spec.name == "something-comforting" }
        XCTAssertEqual(melody.count, 1)
        func keys(_ o: [UInt8]) throws -> [UInt32] {
            let main = try Resources.mainBlock(Resources.scan(o, limit: Patcher.maxOSOSSize))
            let r = main.resources.first { $0.type == "Menu" && $0.id == Patcher.settingsMenuID }!
            let at = main.abs(r)
            return (0..<Int(le32(o, at))).map { le32(o, at + 4 + 40 * $0 + 0x1C) }
        }
        // alone
        let alone = try Patcher.apply(melody, to: osos, originalSHA256: sha)
        var k = try keys(alone)
        XCTAssertEqual(k[k.firstIndex(of: 0x6000_6088)! + 1], 0x6000_60E4)
        XCTAssertGreaterThanOrEqual(le32(alone, 0x66c950), Patcher.patchAreaStart)
        XCTAssertEqual(alone.count % 0x800, 0)
        // after "Switch on iPod" with an empty theme
        let theme = ImportedTheme(name: "empty", source_sha256: sha, osos_sha256: sha)
        let (switched, info) = try DarkMode.build(partition: partition, osos: osos, theme: theme, patch: dark, originalSHA256: sha)
        let darkSet = le32(switched, 0x66c950)
        let out = try Patcher.apply(melody, to: switched, originalSHA256: sha)
        k = try keys(out)
        XCTAssertEqual(k.filter { $0 == DarkMode.darkKey }.count, 1)
        XCTAssertEqual(k[k.firstIndex(of: 0x6000_6088)! + 1], 0x6000_60E4)
        XCTAssertGreaterThan(Int(le32(out, 0x66c950)), info.patchAt)
        XCTAssertNotEqual(le32(out, 0x66c950), darkSet)
        XCTAssertLessThanOrEqual(out.count, ThemeImport.ososLimit)
        // two times: the item exists already
        XCTAssertThrowsError(try Patcher.apply(melody, to: out, originalSHA256: sha))
        // a hook with "chain" is not a conflict; the same Settings item key is
        XCTAssertTrue(Patcher.conflicts(melody + [dark]).isEmpty)
        XCTAssertEqual(Patcher.conflicts(melody + melody).count, 1)
    }

    /// "menu_items": a copy of an item with a new label, after the item `after_label`, or at the end.
    func testInsertMenuItem() throws {
        func item(_ label: UInt16, _ target: UInt32) -> [UInt8] {
            var i = [UInt8](repeating: 0, count: 40)
            i[0x18] = UInt8(label & 0xFF); i[0x19] = UInt8(label >> 8)
            put32(&i, 0x0C, target)
            i[0x20] = i[0x18]; i[0x21] = i[0x19]
            return i
        }
        var menu = [UInt8](repeating: 0, count: 4)
        put32(&menu, 0, 3)
        menu += item(0xFF83, 0x40B2) + item(0xFF82, 0x41A2) + item(0xFF81, 0x415A)
        let out = try Patcher.insertMenuItem(menu, label: 0x7E03, template: 0xFF82, after: 0xFF82)
        XCTAssertEqual(le32(out, 0), 4)
        let labels = (0..<4).map { UInt16(out[4 + 40 * $0 + 0x18]) | UInt16(out[4 + 40 * $0 + 0x19]) << 8 }
        XCTAssertEqual(labels, [0xFF83, 0xFF82, 0x7E03, 0xFF81])
        XCTAssertEqual(le32(out, 4 + 80 + 0x0C), 0x41A2)                     // the action of the template
        XCTAssertEqual(Array(out[4 + 80 + 0x20..<4 + 80 + 0x22]), [0x03, 0x7E])
        let keyed = try Patcher.insertMenuItem(menu, label: 0x7E04, template: 0xFF82, after: nil, key: 0x6000_7E05)
        XCTAssertEqual(le32(keyed, 4 + 120 + 0x1C), 0x6000_7E05)
        let end = try Patcher.insertMenuItem(menu, label: 0x7E03, template: 0xFF82, after: 0x1234)
        XCTAssertEqual(UInt16(end[4 + 120 + 0x18]) | UInt16(end[4 + 120 + 0x19]) << 8, 0x7E03)
        XCTAssertThrowsError(try Patcher.insertMenuItem(out, label: 0x7E03, template: 0xFF82, after: nil))
        XCTAssertThrowsError(try Patcher.insertMenuItem(menu, label: 0x7E03, template: 0x1111, after: nil))
    }

    /// The album-artists patch: alone, after "Switch on iPod", and with something-comforting (both hook the
    /// lookup with "chain"). The Music menu has "Album Artists" after Artists. Needs IPODFW_IPSW.
    func testAlbumArtistsMenuItem() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let partition = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data)
        let osos = try partition.image("osos")
        let sha = ThemeImport.sha256(osos)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        let all = Patcher.list(in: repo.appendingPathComponent("patches"))
        let dark = all.first { $0.spec.name == "dark-mode" }!
        let artists = all.filter { $0.spec.name == "album-artists" }
        let melody = all.filter { $0.spec.name == "something-comforting" }
        XCTAssertEqual(artists.count, 1)
        func musicLabels(_ o: [UInt8], menu: Int16 = 24440) throws -> [UInt16] {
            let main = try Resources.mainBlock(Resources.scan(o, limit: Patcher.maxOSOSSize))
            let r = main.resources.first { $0.type == "Menu" && $0.id == menu }!
            let at = main.abs(r)
            return (0..<Int(le32(o, at))).map { UInt16(o[at + 4 + 40 * $0 + 0x18]) | UInt16(o[at + 4 + 40 * $0 + 0x19]) << 8 }
        }
        let alone = try Patcher.apply(artists, to: osos, originalSHA256: sha)
        var labels = try musicLabels(alone)
        XCTAssertEqual(labels.count, 11)
        XCTAssertEqual(labels[labels.firstIndex(of: 0xFF82)! + 1], 0x7E03)
        let main = try musicLabels(alone, menu: 24094)                         // the main menu
        XCTAssertEqual(main.count, 32)
        XCTAssertEqual(main[main.firstIndex(of: 0x5F7C)! + 1], 0x7E03)
        let rows = try musicLabels(alone, menu: 24600)                         // Settings > Main Menu
        XCTAssertEqual(rows.count, 29)
        XCTAssertEqual(rows[rows.firstIndex(of: 0xFF5E)! + 1], 0x7E04)
        XCTAssertGreaterThanOrEqual(le32(alone, 0x6776f8), Patcher.patchAreaStart)
        XCTAssertEqual(alone.count % 0x800, 0)
        // after "Switch on iPod" with an empty theme, then something-comforting
        let theme = ImportedTheme(name: "empty", source_sha256: sha, osos_sha256: sha)
        let (switched, _) = try DarkMode.build(partition: partition, osos: osos, theme: theme, patch: dark, originalSHA256: sha)
        let out = try Patcher.apply(artists + melody, to: switched, originalSHA256: sha)
        labels = try musicLabels(out)
        XCTAssertEqual(labels.filter { $0 == 0x7E03 }.count, 1)
        XCTAssertLessThanOrEqual(out.count, ThemeImport.ososLimit)
        // two times: the item exists already
        XCTAssertThrowsError(try Patcher.apply(artists, to: alone, originalSHA256: sha))
        XCTAssertTrue(Patcher.conflicts(artists + melody + [dark]).isEmpty)
        XCTAssertEqual(Patcher.conflicts(artists + artists).count, 1)
    }

    func testChainTargetRules() throws {
        var osos = [UInt8](repeating: 0, count: 0x800)
        let word = PatchSpec.Hook(kind: "word", at: "0x100", expect: "0x00190b00", to: "h", chain: "next")
        put32(&osos, 0x100, 0x0019_0B00)
        XCTAssertEqual(try Patcher.chainTarget(word, in: osos, patchSymbols: [:]), 0x0019_0B00)
        put32(&osos, 0x100, 0x007E_B010)
        XCTAssertEqual(try Patcher.chainTarget(word, in: osos, patchSymbols: [:]), 0x007E_B010)
        put32(&osos, 0x100, 0x0012_3456)
        XCTAssertThrowsError(try Patcher.chainTarget(word, in: osos, patchSymbols: [:]))
        let b = PatchSpec.Hook(kind: "b", at: "0x200", expect: "0xe92d40f8", to: "h", chain: "next", chain_default: "orig")
        put32(&osos, 0x200, 0xE92D_40F8)
        XCTAssertEqual(try Patcher.chainTarget(b, in: osos, patchSymbols: ["orig": 0x7E_C000]), 0x7E_C000)
        put32(&osos, 0x200, try Patcher.branch("b", at: 0x200, to: 0x7E_B100))
        XCTAssertEqual(try Patcher.chainTarget(b, in: osos, patchSymbols: ["orig": 0x7E_C000]), 0x7E_B100)
    }

    func testSwitchTableSwitchesBothWaysAndKeepsEdits() {
        let osos = (0..<64).map { UInt8($0) }
        func change(_ r: String, _ at: Int, _ old: [UInt8], _ new: [UInt8]) -> ThemeChange {
            ThemeChange(resource: r, offset: at, old: Data(old), new: Data(new))
        }
        var theme = ImportedTheme(name: "t", source_sha256: "", osos_sha256: "x")
        theme.changes = [change("View 1", 4, [4, 5, 6], [9, 9, 9]), change("BMap 2", 20, [20, 21], [0, 0]),
                         change("BMap 3", 40, [99], [1]), change("View 1", 4, [4, 5, 6], [9, 9, 9])]
        let (table, leftOut) = DarkMode.switchTable(theme, osos: osos)
        XCTAssertEqual(leftOut, 1)
        var dark = osos
        DarkMode.applySwitchTable(&dark, table)
        XCTAssertEqual(Array(dark[4..<7]), [9, 9, 9]); XCTAssertEqual(Array(dark[20..<22]), [0, 0]); XCTAssertEqual(dark[40], 40)
        DarkMode.applySwitchTable(&dark, table)
        XCTAssertEqual(dark, osos)
    }

    func testThemeKeepsTheBlueHighlight() throws {
        func words(_ w: [UInt32]) -> [UInt8] { var b = [UInt8](repeating: 0, count: 4 * w.count); for (i, v) in w.enumerated() { put32(&b, 4 * i, v) }; return b }
        let old = words([0x18, 0xFFD0_6428, 0xFFE8_9858, 0x5E9E_0000]), new = words([0x30, 0xFF25_2525, 0xFF34_3434, 0x5E9E_0000])
        var theme = ImportedTheme(name: "t", source_sha256: "", osos_sha256: "x")
        theme.changes = [ThemeChange(resource: "View 22034", offset: 8, old: Data(old), new: Data(new)),
                         ThemeChange(resource: "Type 14037", offset: 24, old: Data(old[4..<8]), new: Data(new[4..<8]))]
        var osos = [UInt8](repeating: 0, count: 32)
        osos.replaceSubrange(8..<24, with: old)
        osos.replaceSubrange(24..<28, with: old[4..<8])
        try theme.apply(to: &osos, originalSHA256: "x")
        XCTAssertEqual((0..<4).map { le32(osos, 8 + 4 * $0) }, [0x30, 0xFFD0_6428, 0xFFE8_9858, 0x5E9E_0000])
        XCTAssertEqual(Array(osos[24..<28]), Array(new[4..<8]))
    }

    func testEditsReplaceTheThemePictureAndSurviveJSON() throws {
        var theme = ImportedTheme(name: "t", source_sha256: "", osos_sha256: "x")
        theme.changes = [ThemeChange(resource: "BMap 1", offset: 4, old: Data(count: 4), new: Data(repeating: 0x11, count: 4)),
                         ThemeChange(resource: "BMap 2", offset: 12, old: Data([0]), new: Data([0x22]))]
        theme.setEdit(resource: "BMap 1", offset: 4, light: [UInt8](repeating: 0, count: 16), new: [0x33, 0x33, 0x33, 0x33])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipodtheme")
        try theme.write(to: url)
        theme = try ImportedTheme.load(url)
        var osos = [UInt8](repeating: 0, count: 16)
        XCTAssertEqual(try theme.apply(to: &osos, originalSHA256: "x").applied, 2)
        XCTAssertEqual(Array(osos[4..<8]), [0x33, 0x33, 0x33, 0x33]); XCTAssertEqual(osos[12], 0x22)
        theme.removeEdit(offset: 4)
        osos = [UInt8](repeating: 0, count: 16)
        try theme.apply(to: &osos, originalSHA256: "x")
        XCTAssertEqual(Array(osos[4..<8]), [0x11, 0x11, 0x11, 0x11])
    }

    func testSettingsMenuGetsTheItemAfterClicker() throws {
        func item(_ key: UInt32, _ label: UInt32) -> [UInt8] {
            var it = [UInt8](repeating: 0, count: 40)
            put32(&it, 0x18, label); put32(&it, 0x1C, key); put32(&it, 0x20, label)
            return it
        }
        var menu = [UInt8](repeating: 0, count: 4)
        put32(&menu, 0, 3)
        menu += item(0x6000_60B7, 0xFF69) + item(0x6000_6088, 0xFF68) + item(0x6000_60AD, 0xFF67)
        let new = try DarkMode.settingsMenu(menu)
        XCTAssertEqual(le32(new, 0), 4)
        XCTAssertEqual((0..<4).map { le32(new, 4 + 40 * $0 + 0x1C) }, [0x6000_60B7, 0x6000_6088, DarkMode.darkKey, 0x6000_60AD])
        XCTAssertEqual(le32(new, 4 + 80 + 0x18), DarkMode.labelID)
        XCTAssertThrowsError(try DarkMode.settingsMenu(new))
    }

    /// The Swift build must give the same osos as `ipodfw apply-theme --switch` (IPODFW_SWITCH_EXPECT).
    func testBuildAgreesWithPython() throws {
        let env = ProcessInfo.processInfo.environment
        guard let ipsw = env["IPODFW_IPSW"], let themeFile = env["IPODFW_THEME_EXPECT"], let expect = env["IPODFW_SWITCH_EXPECT"] else {
            throw XCTSkip("set IPODFW_IPSW, IPODFW_THEME_EXPECT and IPODFW_SWITCH_EXPECT")
        }
        let fw = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data)
        let osos = try fw.image("osos")
        let theme = try ImportedTheme.load(URL(fileURLWithPath: themeFile))
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        let patch = Patcher.list(in: repo.appendingPathComponent("patches")).first { $0.spec.name == "dark-mode" }!
        XCTAssertEqual(patch.spec.internal, true)
        let (out, info) = try DarkMode.build(partition: fw, osos: osos, theme: theme, patch: patch, originalSHA256: ThemeImport.sha256(osos))
        XCTAssertEqual(info.changesLeftOut, 0)
        let python = try FirmwarePartition(contentsOf: URL(fileURLWithPath: expect)).image("osos")
        XCTAssertEqual(out.count, python.count)
        XCTAssertEqual(ThemeImport.sha256(out), ThemeImport.sha256(python))
    }
}


/// The patches that the owner installs: examine, install, remove, export and conflicts.
final class PatchLibraryTests: XCTestCase {
    static let repo = PatchAndArtTests.repo
    var tmp: URL!
    var library: PatchLibrary!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ipodfirm-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        library = PatchLibrary(builtInDir: Self.repo.appendingPathComponent("patches"),
                               userDir: tmp.appendingPathComponent("user"), stagingDir: tmp.appendingPathComponent("staging"))
    }

    override func tearDownWithError() throws {
        if let tmp, tmp.lastPathComponent.hasPrefix("ipodfirm-library-") { try? FileManager.default.removeItem(at: tmp) }
    }

    /// Make a patch folder in the temporary folder.
    func makePatch(_ json: [String: Any], files: [String: String] = [:], folder: String? = nil) throws -> URL {
        let dir = tmp.appendingPathComponent("src").appendingPathComponent(folder ?? (json["name"] as? String ?? "x"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("patch.json"))
        for (name, text) in files { try Data(text.utf8).write(to: dir.appendingPathComponent(name)) }
        return dir
    }

    func spec(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        ["name": name, "osos_sha256": PatchLibrary.firmware13OSOS, "title": "Test", "summary": "A test.",
         "symbol": "star", "category": "test", "version_letter": "z"].merging(extra) { $1 }
    }

    func inspect(_ url: URL) throws -> PatchCandidate { try library.inspect(url, existing: library.list()) }

    func testErrors() throws {
        XCTAssertFalse(try inspect(makePatch(spec("Bad_Name"), folder: "bad")).canInstall)
        XCTAssertFalse(try inspect(makePatch(spec("sleep-now"), folder: "builtin")).canInstall)
        XCTAssertFalse(try inspect(makePatch(spec("two-c", ["load_address": "extended"]), files: ["a.c": "", "b.c": ""])).canInstall)
        XCTAssertFalse(try inspect(makePatch(spec("bad-file"), files: ["run.sh": "echo"])).canInstall)
        XCTAssertFalse(try inspect(makePatch(spec("bad-object", ["load_address": "extended"]), files: ["patch.o": "not elf"])).canInstall)
        for path in ["iPod_Control/../x", "Music/x", "/iPod_Control/x"] {
            let ui: [String: Any] = ["actions": [["title": "Go", "write": [["path": path, "text": "1"]]]]]
            XCTAssertFalse(try inspect(makePatch(spec("bad-path", ["ui": ui]), folder: "p\(path.count)")).canInstall, path)
        }
        let wrong: [[String: Any]] = [["model": "iPod Video", "firmware": "1.2", "osos_sha256": String(repeating: "0", count: 64)]]
        XCTAssertFalse(try inspect(makePatch(spec("bad-target", ["targets": wrong]))).canInstall)
        let big: [String: Any] = ["actions": [["title": "Go", "write": [["path": "iPod_Control/x", "zeros": PatchUI.maxWrite + 1]]]]]
        XCTAssertFalse(try inspect(makePatch(spec("big-write", ["ui": big]))).canInstall)
    }

    /// A missing letter, or a letter in use, gets the first free letter. The install writes it into patch.json.
    func testLetters() throws {
        let used = Set(library.list().compactMap(\.spec.version_letter))
        let free = "abcdefghijklmnopqrstuvwxyz".map(String.init).first { !used.contains($0) }
        var s = spec("no-letter")
        s["version_letter"] = nil
        let c = try inspect(makePatch(s))
        XCTAssertTrue(c.canInstall)
        XCTAssertEqual(c.assignedLetter, free)
        let dest = try library.install(c)
        let installed = try JSONDecoder().decode(PatchSpec.self, from: Data(contentsOf: dest.appendingPathComponent("patch.json")))
        XCTAssertEqual(installed.version_letter, free)
        let usedNow = Set(library.list().compactMap(\.spec.version_letter))
        XCTAssertTrue(usedNow.contains("a"))
        let next = "abcdefghijklmnopqrstuvwxyz".map(String.init).first { !usedNow.contains($0) }
        XCTAssertEqual(try inspect(makePatch(spec("used-letter", ["version_letter": "a"]))).assignedLetter, next)
    }

    /// A missing or wrong size gets a note, and the install writes the measured size into patch.json.
    func testSize() throws {
        func candidate(_ extra: [String: Any], _ folder: String) throws -> PatchCandidate {
            try inspect(makePatch(spec("sized", extra), folder: folder))
        }
        let missing = try candidate([:], "s1"), correct = try candidate(["size": 0], "s2"), wrong = try candidate(["size": 5], "s3")
        XCTAssertEqual(missing.assignedSize, 0)
        XCTAssertNil(correct.assignedSize)
        XCTAssertEqual(wrong.assignedSize, 0)
        for c in [missing, correct, wrong] { XCTAssertEqual(c.notes.filter { $0.contains("size") }.count, c.assignedSize == nil ? 0 : 1) }
        try library.install(wrong)
        XCTAssertEqual(library.list().first { $0.spec.name == "sized" }?.spec.size, 0)
    }

    /// A user patch that an earlier version installed without a size gets the measured size. The version does not change.
    func testRecordMissingSizes() throws {
        let src = try String(contentsOf: Self.repo.appendingPathComponent("patches/sleep-now/sleep_now.c"), encoding: .utf8)
        let builtIn = Patcher.list(in: Self.repo.appendingPathComponent("patches")).first { $0.spec.name == "sleep-now" }!
        let extra: [String: Any] = ["load_address": "extended", "symbols": builtIn.spec.symbols ?? [:], "version": "2.0"]
        let old = library.userDir.appendingPathComponent("old-code")
        try FileManager.default.createDirectory(at: library.userDir, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: makePatch(spec("old-code", extra), files: ["sleep_now.c": src]), to: old)
        try FileManager.default.moveItem(at: makePatch(spec("old-data", ["version": "1.0"])), to: library.userDir.appendingPathComponent("old-data"))
        try FileManager.default.moveItem(at: makePatch(spec("old-sized", ["size": 7])), to: library.userDir.appendingPathComponent("old-sized"))
        let changed = library.recordMissingSizes()
        let list = library.list()
        func size(_ n: String) -> Int? { list.first { $0.spec.name == n }?.spec.size }
        XCTAssertEqual(size("old-data"), 0)
        XCTAssertEqual(size("old-sized"), 7)   // not examined: only missing sizes
        XCTAssertEqual(list.first { $0.spec.name == "old-code" }?.spec.version, "2.0")
        if PatchLibrary.hasCompiler() {
            XCTAssertEqual(Set(changed), ["old-code", "old-data"])
            XCTAssertEqual(size("old-code"), builtIn.spec.size)
        }
        XCTAssertEqual(library.recordMissingSizes(), [])
    }

    /// The install and the export of a code patch record the measured size.
    func testSizeOfCodePatch() throws {
        let src = try String(contentsOf: Self.repo.appendingPathComponent("patches/sleep-now/sleep_now.c"), encoding: .utf8)
        let builtIn = Patcher.list(in: Self.repo.appendingPathComponent("patches")).first { $0.spec.name == "sleep-now" }!
        let extra: [String: Any] = ["load_address": "extended", "symbols": builtIn.spec.symbols ?? [:]]
        let c = try inspect(makePatch(spec("sized-code", extra), files: ["sleep_now.c": src]))
        guard c.canInstall else { throw XCTSkip("the patch does not compile here: \(c.errors)") }
        XCTAssertEqual(c.assignedSize, builtIn.spec.size)
        let dest = try library.install(c)
        let installed = try JSONDecoder().decode(PatchSpec.self, from: Data(contentsOf: dest.appendingPathComponent("patch.json")))
        XCTAssertEqual(installed.size, builtIn.spec.size)
        // An export with a wrong size: the file records the measured size.
        var wrong = PatchInfo(spec: installed, folder: c.folder, source: .user)
        wrong.spec.size = 1
        let zip = tmp.appendingPathComponent("sized-code.ipodpatch"), out = tmp.appendingPathComponent("unzipped-size")
        try library.export(wrong, to: zip)
        try PatchLibrary.run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
        let exported = try JSONDecoder().decode(PatchSpec.self, from: Data(contentsOf: out.appendingPathComponent("sized-code/patch.json")))
        XCTAssertEqual(exported.size, builtIn.spec.size)
    }

    /// An update, a reinstall and a downgrade of a user patch.
    func testVersionChange() throws {
        let c1 = try inspect(makePatch(spec("versioned", ["version": "1.0"]), folder: "v1"))
        XCTAssertEqual(c1.change, .new)
        try library.install(c1)
        let c2 = try inspect(makePatch(spec("versioned", ["version": "1.1"]), folder: "v2"))
        XCTAssertTrue(c2.replaces)
        XCTAssertEqual(c2.installedVersion, "1.0")
        XCTAssertEqual(c2.change, .update)
        try library.install(c2)
        XCTAssertEqual(library.list().first { $0.spec.name == "versioned" }?.spec.version, "1.1")
        XCTAssertEqual(try inspect(makePatch(spec("versioned", ["version": "1.1.0"]), folder: "v3")).change, .same)
        let down = try inspect(makePatch(spec("versioned", ["version": "1.0"]), folder: "v4"))
        XCTAssertEqual(down.change, .downgrade)
        XCTAssertTrue(down.canInstall)
        XCTAssertTrue(down.notes.contains { $0.contains("older version") })
        XCTAssertFalse(try inspect(makePatch(spec("bad-version", ["version": "1.x"]))).canInstall)
    }

    /// A higher version replaces a built-in patch. A remove brings the built-in patch back.
    func testReplaceBuiltIn() throws {
        let builtIn = try XCTUnwrap(library.list().first { $0.spec.name == "sleep-now" })
        XCTAssertEqual(builtIn.source, .builtIn)
        XCTAssertFalse(try inspect(makePatch(spec("sleep-now", ["version": builtIn.spec.version!]), folder: "same")).canInstall)
        XCTAssertFalse(try inspect(makePatch(spec("sleep-now", ["version": "0.9"]), folder: "lower")).canInstall)
        let c = try inspect(makePatch(spec("sleep-now", ["version": "99.0"]), folder: "higher"))
        XCTAssertTrue(c.canInstall, c.errors.joined())
        XCTAssertTrue(c.replacesBuiltIn)
        XCTAssertEqual(c.change, .update)
        try library.install(c)
        let user = try XCTUnwrap(library.list().first { $0.spec.name == "sleep-now" })
        XCTAssertEqual(user.source, .user)
        XCTAssertTrue(user.replacesBuiltIn)
        XCTAssertEqual(user.builtInVersion, builtIn.spec.version)
        try library.remove(user)
        XCTAssertEqual(library.list().first { $0.spec.name == "sleep-now" }?.source, .builtIn)
    }

    /// A patch with a chained hook and an option passes the examination: the trial link defines the
    /// chain symbol and finds the variable of the option.
    func testInspectChainAndOption() throws {
        let builtIn = try XCTUnwrap(library.list().first { $0.spec.name == "album-art" })
        let src = builtIn.folder
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: src.appendingPathComponent("patch.json"))) as? [String: Any])
        json["version"] = "99.0"
        let c = try inspect(makePatch(json, files: ["album_art.c": String(contentsOf: src.appendingPathComponent("album_art.c"), encoding: .utf8)],
                                      folder: "album-art"))
        XCTAssertTrue(c.canInstall, "\(c.errors)")
        XCTAssertEqual(c.codeSize, builtIn.spec.size)
        json["options"] = [["id": "source", "title": "T", "symbol": "no_such_variable", "choices": [["value": 0, "title": "A"]]]]
        let bad = try inspect(makePatch(json, files: ["album_art.c": String(contentsOf: src.appendingPathComponent("album_art.c"), encoding: .utf8)],
                                        folder: "album-art-bad"))
        XCTAssertFalse(bad.canInstall)
    }

    func testInstallFolderZipAndRemove() throws {
        let folder = try makePatch(spec("data-patch"))
        let c = try inspect(folder)
        XCTAssertTrue(c.canInstall, c.errors.joined())
        XCTAssertNil(c.codeSize)
        try library.install(c)
        let p = try XCTUnwrap(library.list().first { $0.spec.name == "data-patch" })
        XCTAssertEqual(p.source, .user)

        // The same patch as a .ipodpatch file replaces the installed patch.
        let zip = tmp.appendingPathComponent("data-patch.ipodpatch")
        try PatchLibrary.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", folder.path, zip.path])
        let z = try inspect(zip)
        XCTAssertTrue(z.canInstall, z.errors.joined())
        XCTAssertTrue(z.replaces)
        let staging = try XCTUnwrap(z.staging)
        try library.install(z)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))

        try library.remove(try XCTUnwrap(library.list().first { $0.spec.name == "data-patch" }))
        XCTAssertNil(library.list().first { $0.spec.name == "data-patch" })
        XCTAssertThrowsError(try library.remove(try XCTUnwrap(library.list().first { $0.spec.name == "sleep-now" })))
    }

    /// Without "targets", the text comes from the known builds.
    func testTargetText() {
        let s = PatchSpec(name: "x", osos_sha256: PatchLibrary.firmware13OSOS)
        XCTAssertEqual(s.targetText, "iPod Video (5G/5.5G), firmware 1.3")
        XCTAssertTrue(PatchSpec(name: "y", osos_sha256: String(repeating: "0", count: 64)).targetText.hasPrefix("An unknown firmware"))
    }

    func testConflicts() {
        let all = library.list()
        // a copy of album-art with another name: the same load address and the same hooks
        var copy = all.first { $0.spec.name == "album-art" }!
        copy.spec.name = "album-art-copy"
        let pair = all.filter { $0.spec.name == "album-art" } + [copy]
        XCTAssertEqual(pair.count, 2)
        XCTAssertFalse(Patcher.conflicts(pair).isEmpty)
        let ok = all.filter { ["album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input", "backlight-60s"].contains($0.spec.name) }
        XCTAssertTrue(Patcher.conflicts(ok).isEmpty)
    }

    /// Export makes patch.o. A folder with only patch.o gives the same bytes as the C file.
    func testExportPrecompiled() throws {
        guard PatchLibrary.hasCompiler() else { throw XCTSkip("no clang") }
        let sleep = try XCTUnwrap(library.list().first { $0.spec.name == "sleep-now" })
        let zip = tmp.appendingPathComponent("sleep-now.ipodpatch")
        try library.export(sleep, to: zip)
        let out = tmp.appendingPathComponent("unzipped")
        try PatchLibrary.run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
        let folder = out.appendingPathComponent("sleep-now")
        let obj = folder.appendingPathComponent(Patcher.objectFile)
        XCTAssertTrue(PatchLibrary.isARMObject([UInt8](try Data(contentsOf: obj))))
        for f in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where f.pathExtension == "c" {
            try FileManager.default.removeItem(at: f)
        }
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        XCTAssertEqual(try Patcher.apply([PatchInfo(spec: sleep.spec, folder: folder)], to: osos), try Patcher.apply([sleep], to: osos))
    }

    // MARK: New Patch and Edit Patch

    func draft(_ title: String, kind: PatchDraft.Kind = .bytes) -> PatchDraft {
        var d = PatchDraft()
        d.title = title
        d.name = PatchDraft.name(fromTitle: title)
        d.summary = "A test."
        d.category = "test"
        d.symbol = "star"
        d.kind = kind
        return d
    }

    func testPatchNameFromTitle() {
        XCTAssertEqual(PatchDraft.name(fromTitle: "Sleep Now"), "sleep-now")
        XCTAssertEqual(PatchDraft.name(fromTitle: "  EU Volume!! "), "eu-volume")
        XCTAssertEqual(PatchDraft.name(fromTitle: "Über 2"), "ber-2")
    }

    func testPatchVersionNext() {
        XCTAssertEqual(PatchVersion.next(after: "1.0"), "1.1")
        XCTAssertEqual(PatchVersion.next(after: "1.9"), "1.10")
        XCTAssertEqual(PatchVersion.next(after: "2"), "3")
        XCTAssertEqual(PatchVersion.next(after: "1.2.3"), "1.2.4")
        XCTAssertEqual(PatchVersion.next(after: nil), "1.0")
        XCTAssertEqual(PatchVersion.next(after: "x"), "1.0")
    }

    /// A new data patch installs with no errors: version 1.0, size 0, a free letter and the 1.3 target.
    func testCreateBytesPatch() throws {
        var d = draft("My Bytes")
        d.details = ["One.", " ", "Two. "]
        let folder = try library.create(d)
        let c = try inspect(folder)
        XCTAssertTrue(c.canInstall, c.errors.joined(separator: " "))
        XCTAssertNil(c.assignedLetter)
        XCTAssertNil(c.assignedSize)
        let spec = try XCTUnwrap(c.spec)
        XCTAssertEqual(spec.name, "my-bytes")
        XCTAssertEqual(spec.version, "1.0")
        XCTAssertEqual(spec.size, 0)
        XCTAssertEqual(spec.details, ["One.", "Two."])
        XCTAssertNil(spec.caution)
        XCTAssertEqual(spec.targets, [PatchSpec.knownFirmware[0]])
        let used = Patcher.list(in: library.builtInDir).compactMap(\.spec.version_letter)
        XCTAssertFalse(used.contains(try XCTUnwrap(spec.version_letter)))
        XCTAssertTrue(library.list().contains { $0.spec.name == "my-bytes" && $0.source == .user })
    }

    /// A new code patch compiles, links and records its measured size.
    func testCreateCodePatch() throws {
        guard PatchLibrary.hasCompiler() else { throw XCTSkip("no clang") }
        let folder = try library.create(draft("My Code", kind: .code))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("my_code.c").path))
        let c = try inspect(folder)
        XCTAssertTrue(c.canInstall, c.errors.joined(separator: " "))
        XCTAssertNil(c.assignedSize)
        let spec = try XCTUnwrap(c.spec)
        XCTAssertEqual(spec.load_address, Patcher.extendedLoadAddress)
        XCTAssertEqual(spec.size, c.codeSize)
        XCTAssertGreaterThan(spec.size ?? 0, 0)
    }

    func testCreateRefusesUsedName() throws {
        var d = draft("Sleep Now")
        XCTAssertThrowsError(try library.create(d))            // a built-in patch
        d = draft("Dark Mode")
        XCTAssertThrowsError(try library.create(d))            // an internal built-in patch
        d = draft("Mine")
        try library.create(d)
        XCTAssertThrowsError(try library.create(d))            // a user patch
        XCTAssertFalse(d.problems(existing: library.list()).isEmpty)
        d.name = "Bad_Name"
        XCTAssertThrowsError(try library.create(d))
    }

    /// An edit writes the text, removes the empty keys and increases the version. The name stays.
    func testEditPatchIncreasesVersion() throws {
        var d = draft("Edit Me")
        d.caution = "Be careful."
        try library.create(d)
        var patch = try XCTUnwrap(library.list().first { $0.spec.name == "edit-me" })
        var e = PatchDraft(spec: patch.spec)
        XCTAssertEqual(e, d)
        e.summary = "A new summary."
        e.caution = ""
        XCTAssertEqual(try library.edit(patch, with: e), "1.1")
        patch = try XCTUnwrap(library.list().first { $0.spec.name == "edit-me" })
        XCTAssertEqual(patch.spec.summary, "A new summary.")
        XCTAssertNil(patch.spec.caution)
        XCTAssertEqual(patch.spec.version, "1.1")
        XCTAssertEqual(patch.spec.size, 0)
        let builtIn = try XCTUnwrap(library.list().first { $0.spec.name == "sleep-now" })
        XCTAssertThrowsError(try library.edit(builtIn, with: PatchDraft(spec: builtIn.spec)))
    }

    /// A patch that New Patch made can be edited, saved and removed. In the app, the user folder did
    /// not exist when the library started (a new user), thus `userDir` has no "/" at the end.
    func testRemoveNewPatch() throws {
        library = PatchLibrary(builtInDir: library.builtInDir, userDir: URL(fileURLWithPath: tmp.path + "/fresh", isDirectory: false),
                               stagingDir: library.stagingDir)
        try library.create(draft("Not Finished"))
        let patch = try userPatch("not-finished")
        XCTAssertNoThrow(try library.edit(patch, with: PatchDraft(spec: patch.spec)))
        XCTAssertNoThrow(try library.saveCode(try userPatch("not-finished"), PatchCode(patch: patch)))
        let old = try userPatch("not-finished")
        try library.remove(old)
        XCTAssertFalse(library.list().contains { $0.spec.name == "not-finished" })
        XCTAssertNoThrow(try library.remove(old))      // another copy of the app removed it already
    }

    // MARK: Code section

    func userPatch(_ name: String) throws -> PatchInfo { try XCTUnwrap(library.list().first { $0.spec.name == name }) }

    /// Check Code compiles a copy and finds the errors. Save writes the code, the size and the next version.
    func testCheckAndSaveCode() throws {
        guard PatchLibrary.hasCompiler() else { throw XCTSkip("no clang") }
        try library.create(draft("Coded", kind: .code))
        var patch = try userPatch("coded")
        var code = PatchCode(patch: patch)
        XCTAssertTrue(code.source?.contains("hook_example") == true)
        var r = library.check(patch, code)
        XCTAssertTrue(r.isOK, r.errors.joined())
        XCTAssertTrue(r.functions.contains("hook_example"))

        code.source = "int broken(void) { return x; }\n"
        r = library.check(patch, code)
        XCTAssertFalse(r.isOK)
        XCTAssertTrue(r.errors[0].contains("coded.c"), r.errors[0])
        XCTAssertFalse(r.errors[0].contains("staging"), r.errors[0])

        code.source = "int fw_example(int);\nint hook_example(int a) { return fw_example(a) + 1; }\n"
        code.symbols = [PatchCode.Symbol(name: "fw_example", address: "0x1000")]
        code.hooks = [PatchSpec.Hook(kind: "bl", at: "0x100", expect: "0x12345678", to: "hook_example")]
        XCTAssertTrue(library.check(patch, code).isOK)
        let osos = [UInt8](repeating: 0, count: 0x2000)
        XCTAssertFalse(library.check(patch, code, osos: osos).isOK)       // the firmware has 0 at 0x100
        XCTAssertEqual(PatchCode.word(at: "0x100", in: osos), "0x00000000")
        code.hooks[0].to = "nothing"
        XCTAssertFalse(library.check(patch, code).isOK)
        code.hooks[0].to = "hook_example"

        try Data("old".utf8).write(to: patch.folder.appendingPathComponent(Patcher.objectFile))
        XCTAssertEqual(try library.saveCode(patch, code), "1.1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: patch.folder.appendingPathComponent(Patcher.objectFile).path))
        patch = try userPatch("coded")
        XCTAssertEqual(patch.spec.symbols, ["fw_example": "0x1000"])
        XCTAssertEqual(patch.spec.hooks?.first?.to, "hook_example")
        XCTAssertNil(patch.spec.bytes)
        XCTAssertEqual(patch.spec.size, try Patcher.codeSize(patch))
        XCTAssertEqual(PatchCode(patch: patch), code)
        XCTAssertTrue(try inspect(patch.folder).canInstall)
    }

    func testCheckAndSaveBytes() throws {
        try library.create(draft("Data Only"))
        let patch = try userPatch("data-only")
        var code = PatchCode(patch: patch)
        XCTAssertNil(code.source)
        code.bytes = [PatchSpec.Bytes(at: "0x10", expect: "0100", value: "00")]
        XCTAssertFalse(library.check(patch, code).isOK)                   // different lengths
        code.bytes[0].value = "0001"
        var osos = [UInt8](repeating: 0, count: 0x100)
        XCTAssertFalse(library.check(patch, code, osos: osos).isOK)
        osos[0x10] = 1
        XCTAssertEqual(PatchCode.bytes(at: "0x10", count: 2, in: osos), "0100")
        XCTAssertEqual(library.check(patch, code, osos: osos), PatchCodeCheck(size: 0))
        XCTAssertEqual(try library.saveCode(patch, code), "1.1")
        let saved = try userPatch("data-only")
        XCTAssertEqual(saved.spec.bytes, code.bytes)
        XCTAssertEqual(saved.spec.size, 0)
        XCTAssertNil(saved.spec.hooks)
        let builtIn = try userPatch("volume-unlimit")
        XCTAssertThrowsError(try library.saveCode(builtIn, PatchCode(patch: builtIn)))
    }
}

/// The iPodFirm list in the firmware, and the check of the patches in an image.
final class FirmwareManifestTests: XCTestCase {
    static let list = FirmwareManifest(app: "0.1 (1)", patches: [.init(name: "shuffle-fixes", version: "2.1"),
                                                                 .init(name: "usb-audio-out", version: "1.9", options: ["rate": 48000])],
                                       appearance: "dark", theme: "Dark Gray")

    func testRoundTrip() throws {
        let bytes = try Self.list.encoded()
        XCTAssertEqual(Array(bytes.prefix(FirmwareManifest.magic.count)), FirmwareManifest.magic)
        var osos = [UInt8](repeating: 0, count: Patcher.maxOSOSSize + 0x130)
        osos += bytes
        osos += [UInt8](repeating: 0, count: 0x800 - osos.count % 0x800)
        XCTAssertEqual(FirmwareManifest.read(osos: osos), Self.list)
        // no list: an image that ends before the extended area, and an image with only zeros after it
        XCTAssertNil(FirmwareManifest.read(osos: [UInt8](repeating: 0, count: 0x736000)))
        XCTAssertNil(FirmwareManifest.read(osos: [UInt8](repeating: 0, count: Patcher.maxOSOSSize + 0x1000)))
    }

    func testMirroredSwitches() {
        let d: [String: PatchDetection] = ["a": .installed(version: "1.0"), "b": .absent, "c": .unknown, "x": .installed(version: nil)]
        let out = PatchDetection.mirroredSwitches(current: ["b", "c"], detections: d, known: ["a", "b", "c"])
        XCTAssertEqual(out, ["a", "c"])                         // "x" is not known: it stays off
    }

    /// A build without the list: the check finds the patches from their changed words. A build with the
    /// list: the list gives the names and the versions. The space measurement counts the list.
    func testDetect() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let all = Patcher.list(in: PatchAndArtTests.repo.appendingPathComponent("patches"))
        let set = all.filter { ["shuffle-fixes", "shuffle-album-mix", "something-comforting"].contains($0.spec.name) }
        XCTAssertEqual(set.count, 3)

        let stock = Patcher.detect(osos: osos, patches: all)
        XCTAssertTrue(stock.values.allSatisfy { $0 != .installed(version: nil) })

        let plain = try Patcher.apply(set, to: osos)
        XCTAssertNil(FirmwareManifest.read(osos: plain))
        let found = Patcher.detect(osos: plain, patches: all)
        XCTAssertEqual(found["shuffle-fixes"], .installed(version: nil))
        XCTAssertEqual(found["shuffle-album-mix"], .installed(version: nil))
        XCTAssertEqual(found["something-comforting"], .unknown)          // only shared (chain) hooks
        XCTAssertEqual(found["sleep-now"], .absent)

        let list = FirmwareManifest(app: "test", patches: set.map { .init(name: $0.spec.name, version: $0.spec.version) })
        let bytes = try list.encoded()
        let built = try Patcher.apply(set, to: osos, list: bytes)
        XCTAssertEqual(FirmwareManifest.read(osos: built), list)
        let withList = Patcher.detect(osos: built, patches: all)
        XCTAssertEqual(withList["something-comforting"], .installed(version: set.first { $0.spec.name == "something-comforting" }!.spec.version))
        XCTAssertEqual(withList["sleep-now"], .absent)
        // the patches are at the same places: the list goes after them
        XCTAssertEqual(Array(built.prefix(plain.count - 0x800)), Array(plain.prefix(plain.count - 0x800)))
        let sizes = try set.map { (patch: $0, size: try Patcher.codeSize($0)) }
        XCTAssertEqual(Patcher.spaceUse(osos: osos, patches: sizes, listSize: bytes.count).end, built.count)

        // all patches that are not internal or test: no patch is absent
        let every = all.filter { $0.spec.internal != true && !$0.spec.isTest }
        let everyFound = Patcher.detect(osos: try Patcher.apply(every, to: osos), patches: every)
        for p in every { XCTAssertNotEqual(everyFound[p.spec.name], .absent, p.spec.name) }

        // a build that ends before the extended area gets no list (the list would move rsrc)
        let fixed = all.filter { $0.spec.name == "sleep-now" }
        let small = try Patcher.apply(fixed, to: osos, list: bytes)
        XCTAssertEqual(small, try Patcher.apply(fixed, to: osos))
        XCTAssertEqual(Patcher.detect(osos: small, patches: all)["sleep-now"], .installed(version: nil))
    }
}

// The test of the name of the folder of the games. The firmware asks for the name
// games_RO with small letters. The program of iTunes writes the name Games_RO with a
// capital letter.
final class GamesDirectoryTests: XCTestCase {
    func testAcceptsBothNames() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPodFirm-games-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(GameLibrary.gamesDirectory(at: dir.path))

        // The file system of macOS keeps no case by default. The test uses the name of the
        // case that the file system keeps. The function must find the folder in both cases.
        for name in ["games_RO", "Games_RO"] {
            let games = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
            let found = GameLibrary.gamesDirectory(at: dir.path)
            XCTAssertNotNil(found, "The function must find the folder \(name).")
            // The two names can be the same folder on a file system without case.
            XCTAssertTrue(found!.lowercased().hasSuffix("games_ro"))
            try FileManager.default.removeItem(at: games)
        }
    }
}


// The tests of the manifest of a game and of the copy of the games to an iPod.
final class GameInstallerTests: XCTestCase {
    static func manifestData(guid: String = "11002", name: String = "iQuiz",
                              files: [[String: Any]]? = nil) -> Data {
        let list: [[String: Any]] = files ?? [
            ["Digest": String(repeating: "A", count: 40), "Path": "Fonts/Arial15Hira13Hybrid0.ipd", "Size": 19504],
            ["Digest": String(repeating: "B", count: 40), "Path": "Fonts/Arial15Hira13Hybrid0.txt", "Size": 4779],
        ]
        let root: [String: Any] = [
            "BuildIdentifier": "1446269457-ca6ac6febe09",
            "Files": list,
            "GUID": guid,
            "Name": name,
            "Platforms": [["BuildID": 2902110, "ExecutablePath": "Executables/TWA_1_1_2902110.bin",
                           "LaunchingArtwork": "iQuiz.raw.lcd5", "PlatformID": 1, "PlatformVersion": 1,
                           "Size": 463944]],
            "SampleDataPath": "UserTrivia/Samples",
            "UserDataPath": "UserTrivia/Packs",
            "Version": "1.0",
        ]
        return try! PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    /// Make a folder of a game with the files of the manifest.
    static func makeGame(_ folder: URL, guid: String = "11002", name: String = "iQuiz",
                         withFiles: Bool = true) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try manifestData(guid: guid, name: name).write(to: folder.appendingPathComponent("Manifest.plist"))
        try Data(repeating: 0x30, count: 3548).write(to: folder.appendingPathComponent("Manifest.plist.p7b"))
        try Data("<plist></plist>".utf8).write(to: folder.appendingPathComponent("iTunesMetaData"))
        let exe = folder.appendingPathComponent("Executables")
        try FileManager.default.createDirectory(at: exe, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 463944).write(to: exe.appendingPathComponent("TWA_1_1_2902110.bin"))
        if withFiles {
            for (path, size) in [("Fonts/Arial15Hira13Hybrid0.ipd", 19504), ("Fonts/Arial15Hira13Hybrid0.txt", 4779)] {
                let out = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Data(repeating: 0, count: size).write(to: out)
            }
        }
        let packs = folder.appendingPathComponent("UserTrivia/Packs")
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
        try Data("questions".utf8).write(to: packs.appendingPathComponent("sample1.txt"))
        return folder
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPodFirm-games-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testReadsTheManifest() throws {
        let m = try GameManifest.parse(Self.manifestData())
        XCTAssertEqual(m.guid, "11002")
        XCTAssertEqual(m.name, "iQuiz")
        XCTAssertEqual(m.version, "1.0")
        XCTAssertEqual(m.platformID, 1)
        XCTAssertEqual(m.executable, "Executables/TWA_1_1_2902110.bin")
        XCTAssertEqual(m.executableSize, 463944)
        XCTAssertEqual(m.files.count, 2)
        XCTAssertEqual(m.files[0].path, "Fonts/Arial15Hira13Hybrid0.ipd")
        XCTAssertEqual(m.files[0].size, 19504)
        XCTAssertEqual(m.totalSize, 19504 + 4779)
    }

    func testAFileThatIsNotAManifestIsRefused() {
        XCTAssertThrowsError(try GameManifest.parse(Data("not a plist".utf8)))
        XCTAssertThrowsError(try GameManifest.parse(try! PropertyListSerialization.data(
            fromPropertyList: ["GUID": "1"], format: .xml, options: 0)))
    }

    func testReadsTheLibrary() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.makeGame(dir.appendingPathComponent("11002"), guid: "11002", name: "iQuiz")
        try Self.makeGame(dir.appendingPathComponent("50514"), guid: "50514", name: "Royal Solitaire")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("not-a-game"),
                                                withIntermediateDirectories: true)
        let library = GameLibrary.load(dir.path)
        XCTAssertEqual(library.map { $0.folder }, ["11002", "50514"])
        XCTAssertEqual(library[0].name, "iQuiz")
    }

    func testTheCheckGivesTheProblems() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let game = try GameLibrary.loadGame(try Self.makeGame(dir.appendingPathComponent("11002")))
        XCTAssertEqual(GameLibrary.check(game), [])
        try Data(repeating: 0, count: 100).write(to: game.path.appendingPathComponent("Fonts/Arial15Hira13Hybrid0.txt"))
        XCTAssertTrue(GameLibrary.check(game).contains { $0.contains("Arial15Hira13Hybrid0.txt") })
    }

    func testInstallsAGame() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try Self.makeGame(dir.appendingPathComponent("source/11002"))
        let game = try GameLibrary.loadGame(source)
        let target = dir.appendingPathComponent("target")
        let report = try GameInstaller.install(game, to: target)
        XCTAssertEqual(report.installed, ["11002"])
        let dest = target.appendingPathComponent("games_RO/11002")
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("Manifest.plist")),
                       try Data(contentsOf: source.appendingPathComponent("Manifest.plist")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("Manifest.plist.p7b").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("iTunesMetaData").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("Executables/TWA_1_1_2902110.bin").path))
        // The files that are not in the manifest are part of the game.
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("UserTrivia/Packs/sample1.txt")),
                       Data("questions".utf8))
    }

    func testInstallsOnlyTheSelectedGames() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source")
        try Self.makeGame(source.appendingPathComponent("11002"), guid: "11002", name: "iQuiz")
        try Self.makeGame(source.appendingPathComponent("50514"), guid: "50514", name: "Royal Solitaire")
        let library = GameLibrary.load(source.path)
        let wanted = library.filter { $0.folder == "11002" }
        let target = dir.appendingPathComponent("target")
        let report = GameInstaller.install(wanted, to: target)
        XCTAssertEqual(report.installed, ["11002"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.appendingPathComponent("games_RO").path).sorted(),
                       ["11002"])
    }

    func testInstallSkipsAGameThatIsNotComplete() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source")
        try Self.makeGame(source.appendingPathComponent("11002"), guid: "11002", name: "iQuiz")
        try Self.makeGame(source.appendingPathComponent("50514"), guid: "50514", name: "Royal Solitaire", withFiles: false)
        let library = GameLibrary.load(source.path)
        let report = GameInstaller.install(library, to: dir.appendingPathComponent("target"))
        XCTAssertEqual(report.installed, ["11002"])
        XCTAssertEqual(report.skipped, ["50514"])
        XCTAssertFalse(report.warnings.isEmpty)
    }

    func testInstallCopiesTheKeyFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try Self.makeGame(dir.appendingPathComponent("source/11002"))
        let key = dir.appendingPathComponent("IC-Info.sidb")
        try Data(repeating: 0x11, count: 23396).write(to: key)
        let target = dir.appendingPathComponent("target")
        let report = try GameInstaller.install(try GameLibrary.loadGame(source), to: target,
                                               copyKeyFile: true, keyFileSource: key)
        XCTAssertTrue(report.keyFileCopied)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("iTunes/IC-Info.sidb")),
                       Data(repeating: 0x11, count: 23396))
    }

    /// The app accepts only a file with the name IC-Info.sidb that is not empty. The install of
    /// several games copies the key file one time; a wrong file gives a warning and no copy.
    func testKeyFileCheckAndLibraryInstall() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wrong = dir.appendingPathComponent("keys.bin")
        try Data(repeating: 0x11, count: 100).write(to: wrong)
        XCTAssertNotNil(GameInstaller.checkKeyFile(wrong))
        let emptyDir = dir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        let empty = emptyDir.appendingPathComponent("IC-Info.sidb")
        try Data().write(to: empty)
        XCTAssertNotNil(GameInstaller.checkKeyFile(empty))
        XCTAssertNotNil(GameInstaller.checkKeyFile(dir))
        let key = dir.appendingPathComponent("IC-Info.sidb")
        try Data(repeating: 0x22, count: 512).write(to: key)
        XCTAssertNil(GameInstaller.checkKeyFile(key))

        let source = try Self.makeGame(dir.appendingPathComponent("source/11002"))
        let library = [try GameLibrary.loadGame(source)]
        let target = dir.appendingPathComponent("target")
        let report = GameInstaller.install(library, to: target, copyKeyFile: true, keyFileSource: key)
        XCTAssertTrue(report.keyFileCopied)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("iTunes/IC-Info.sidb")),
                       Data(repeating: 0x22, count: 512))
        let bad = GameInstaller.install(library, to: target, copyKeyFile: true, keyFileSource: wrong)
        XCTAssertFalse(bad.keyFileCopied)
        XCTAssertTrue(bad.warnings.contains { $0.hasPrefix("key file") })
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("iTunes/IC-Info.sidb")),
                       Data(repeating: 0x22, count: 512))
    }

    /// A busy iPod volume gets the attempts again; the last message tells the owner to try again.
    func testEjectBusyMessage() {
        XCTAssertTrue(Device.isBusy("Unmount of disk4 failed: at least one volume could not be unmounted"))
        XCTAssertTrue(Device.isBusy("Disk disk4 failed to eject: dissented by PID 123 (mds)"))
        XCTAssertTrue(Device.isBusy("Resource busy"))
        XCTAssertFalse(Device.isBusy("Unable to find disk for disk9"))
        XCTAssertTrue(Device.busyMessage("eject").contains("macOS is still accessing your iPod. Try again in a second."))
    }

    func testInstallNeverRemovesAFile() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try Self.makeGame(dir.appendingPathComponent("source/11002"))
        let game = try GameLibrary.loadGame(source)
        let target = dir.appendingPathComponent("target")
        try GameInstaller.install(game, to: target)
        let keep = target.appendingPathComponent("games_RO/11002/KeepMe.txt")
        try Data("keep".utf8).write(to: keep)
        try GameInstaller.install(game, to: target)
        XCTAssertEqual(try Data(contentsOf: keep), Data("keep".utf8))
    }
}


// The tests of the removal of the games from an iPod. The removal deletes the
// folder of the game only.
final class GameRemoverTests: XCTestCase {
    static func makeInstalledLibrary(_ target: URL, _ guids: [String]) throws {
        for guid in guids {
            let dir = target.appendingPathComponent("games_RO/\(guid)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "code".write(to: dir.appendingPathComponent("Manifest.plist"), atomically: true, encoding: .utf8)
        }
        let data = target.appendingPathComponent("gamedata_RW/11002")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try "save".write(to: data.appendingPathComponent("save.bin"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("gamestats_WO/11002"), withIntermediateDirectories: true)
        try "x".write(to: target.appendingPathComponent("games_RO/extra.txt"), atomically: true, encoding: .utf8)
    }

    func testRemovesOnlyTheGameFolders() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPodFirm-remove-games-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Self.makeInstalledLibrary(target, ["11002", "1B200"])

        let report = try GameRemover.remove(target.path, ["11002"])

        XCTAssertEqual(report.removed, ["11002"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("games_RO/11002").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("games_RO/1B200").path))
        // the saves, the scores and the other files stay
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("gamedata_RW/11002/save.bin").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("gamestats_WO/11002").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("games_RO/extra.txt").path))
        try? FileManager.default.removeItem(at: target)
    }

    func testRefusesANameThatIsNotAGuid() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPodFirm-remove-games-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("iTunes"), withIntermediateDirectories: true)
        try Self.makeInstalledLibrary(target, ["11002"])

        XCTAssertThrowsError(try GameRemover.remove(target.path, ["../iTunes"])) { e in
            XCTAssertTrue((e as? GameRemover.RemoveError)?.description.contains("GUID") ?? false)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("iTunes").path))
        try? FileManager.default.removeItem(at: target)
    }

    func testRemovableFoldersListsOnlyGuidFolders() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPodFirm-remove-games-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Self.makeInstalledLibrary(target, ["11002"])
        try FileManager.default.createDirectory(at: target.appendingPathComponent("games_RO/gamedata_RW"), withIntermediateDirectories: true)

        let dir = try GameLibrary.gamesDirectory(at: target.path)
        XCTAssertEqual(GameRemover.removableFolders(dir!), ["11002"])
        try? FileManager.default.removeItem(at: target)
    }
}

// The tests of the theme format 2: the file holds the hash of the old bytes in
// place of the old bytes, so the app can ship a theme with no byte of the Apple
// firmware.
final class StrippedThemeTests: XCTestCase {
    /// A small theme with one change inside osos.
    static func miniTheme() -> ImportedTheme {
        var t = ImportedTheme(name: "Mini", source_sha256: "", osos_sha256: "abc")
        t.format = ThemeImport.formatStripped
        t.changes = [ThemeChange(resource: "View 1", offset: 4,
                                 old: Data(), new: Data([0x4E, 0x45, 0x57, 0x21]),
                                 oldSHA256: ThemeImport.sha256([0x4F, 0x4C, 0x44, 0x21]))]
        return t
    }

    /// The theme as decoded JSON, the way the app reads a file in format 2.
    func loadMini() throws -> ImportedTheme {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try enc.encode(Self.miniTheme())
        return try JSONDecoder().decode(ImportedTheme.self, from: data)
    }

    func testTheFileHoldsNoOldBytes() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let text = try String(data: enc.encode(Self.miniTheme()), encoding: .utf8)!
        XCTAssertFalse(text.contains("\"old\""))
        XCTAssertTrue(text.contains("old_sha256"))
    }

    func testStrippedThemeAppliesLikeTheOriginal() throws {
        let stripped = try loadMini()
        var a: [UInt8] = [0x78, 0x78, 0x78, 0x78, 0x4F, 0x4C, 0x44, 0x21]
        var b = a
        let r = try stripped.apply(to: &a, originalSHA256: "abc")
        // the original had the same new bytes: apply them by hand to b
        b.replaceSubrange(4..<8, with: [0x4E, 0x45, 0x57, 0x21])
        XCTAssertEqual(r.applied, 1)
        XCTAssertEqual(r.conflicts, 0)
        XCTAssertEqual(a, b)
    }

    func testStrippedThemeKeepsAnEditOfTheOwner() throws {
        let stripped = try loadMini()
        var edited: [UInt8] = [0x78, 0x78, 0x78, 0x78, 0x45, 0x44, 0x49, 0x54]   // an edit at the same bytes
        let r = try stripped.apply(to: &edited, originalSHA256: "abc")
        XCTAssertEqual(Array(edited[4..<8]), [0x45, 0x44, 0x49, 0x54])            // the edit stays
        XCTAssertEqual(r.conflicts, 1)
    }

    /// Issue 1: a change that starts after the end of osos. The built-in Dark Gray theme has
    /// a picture at 0x736800, after the end of Apple's osos. The old bytes there are zeros.
    func testChangePastTheEndOfOsosDoesNotCrash() throws {
        var t = ImportedTheme(name: "Past", source_sha256: "", osos_sha256: "abc")
        t.format = ThemeImport.formatStripped
        t.changes = [ThemeChange(resource: "View 2", offset: 16, old: Data(), new: Data([1, 2, 3, 4]),
                                 oldSHA256: ThemeImport.sha256([0, 0, 0, 0]))]
        let osos: [UInt8] = [0x78, 0x78, 0x78, 0x78, 0x78, 0x78, 0x78, 0x78]
        let full = t.withOldBytes(osos)
        XCTAssertEqual(full.changes[0].old, Data([0, 0, 0, 0]))
        XCTAssertEqual(DarkMode.themeEnd(t, osos: osos), DarkMode.patchAreaEnd)
        var out = osos
        let r = try t.apply(to: &out, originalSHA256: "abc")
        XCTAssertEqual(r.applied, 1)
        XCTAssertEqual(r.conflicts, 0)
        XCTAssertEqual(Array(out[16..<20]), [1, 2, 3, 4])
    }
}

/// The list of Help > Thanks…: the sort order and the rules of CLAUDE.md for each entry.
final class ThanksTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized

    /// The newest version comes first, with a numeric compare. The entries with no version come last, in the list order.
    func testThanksSortNewestFirst() {
        let list = [ThanksEntry(name: "a", reason: "r"),
                    ThanksEntry(name: "b", reason: "r", version: "0.1.9"),
                    ThanksEntry(name: "c", reason: "r", version: "0.1.10"),
                    ThanksEntry(name: "d", reason: "r"),
                    ThanksEntry(name: "e", reason: "r", version: "0.2")]
        XCTAssertEqual(Thanks.sorted(list).map(\.name), ["e", "c", "b", "a", "d"])
    }

    /// Each entry has one name only, a reason, a valid version and a valid link. The README Credits section names each person.
    func testThanksEntries() throws {
        let env = try String(contentsOf: Self.repo.appendingPathComponent("mac/version.env"), encoding: .utf8)
        let line = try XCTUnwrap(env.split(separator: "\n").first { $0.hasPrefix("MARKETING_VERSION=") })
        var limit = line.dropFirst("MARKETING_VERSION=".count).split(separator: ".").compactMap { Int($0) }
        // A new entry can name the next build before build-app.sh increases the version.
        limit[limit.count - 1] += 1

        let readme = try String(contentsOf: Self.repo.appendingPathComponent("README.md"), encoding: .utf8)
        let start = try XCTUnwrap(readme.range(of: "## Credits")).upperBound
        let credits = readme[start...].components(separatedBy: "\n## ").first ?? ""

        let names = Thanks.people.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "Each person must have only one entry in Thanks.people")
        for p in Thanks.people {
            XCTAssertFalse(p.reason.isEmpty, "\(p.name) has no reason")
            if let v = p.version {
                let parts = v.split(separator: ".", omittingEmptySubsequences: false)
                XCTAssertTrue((1...3).contains(parts.count) && parts.count == p.versionNumbers.count,
                              "\(p.name): the version \(v) is not valid")
                XCTAssertFalse(limit.lexicographicallyPrecedes(p.versionNumbers),
                               "\(p.name): the version \(v) is after the next build")
            }
            if let link = p.link { XCTAssertEqual(link.scheme, "https", "\(p.name): the link must use https") }
            let key = p.name.components(separatedBy: " (").first ?? p.name
            XCTAssertTrue(credits.contains(key), "\(p.name) is not in the Credits section of README.md")
        }
    }

}

final class UpdateCheckTests: XCTestCase {
    /// The update check compares the numbers of the versions, not the text.
    func testUpdateVersionCompare() {
        XCTAssertTrue(UpdateCheck.isNewer("0.1.180", than: "0.1.177"))
        XCTAssertTrue(UpdateCheck.isNewer("0.1.10", than: "0.1.9"))
        XCTAssertTrue(UpdateCheck.isNewer("0.2.0", than: "0.1.999"))
        XCTAssertTrue(UpdateCheck.isNewer("0.2.1", than: "0.2"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.177", than: "0.1.177"))
        XCTAssertFalse(UpdateCheck.isNewer("0.2", than: "0.2.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.176", than: "0.1.177"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.180", than: "dev"))
        XCTAssertFalse(UpdateCheck.isNewer("beta", than: "0.1.177"))
    }

    /// The reply of the GitHub API gives the version without the "v" and the release page.
    func testUpdateReleaseParse() throws {
        let json = #"{"tag_name":"v0.1.180","name":"v0.1.180","html_url":"https://github.com/TheFauxDreamer/iPod5.5Firm/releases/tag/v0.1.180","draft":false}"#
        let release = try UpdateCheck.parse(Data(json.utf8))
        XCTAssertEqual(release.version, "0.1.180")
        XCTAssertEqual(release.url.absoluteString, "https://github.com/TheFauxDreamer/iPod5.5Firm/releases/tag/v0.1.180")
        XCTAssertThrowsError(try UpdateCheck.parse(Data("{}".utf8)))
    }
}

final class AppLogTests: XCTestCase {
    var folder: URL!
    var savedDirectory: URL?
    var savedMax = 0

    override func setUpWithError() throws {
        savedDirectory = AppLog.directory
        savedMax = AppLog.maxFileSize
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("AppLogTests-\(UUID().uuidString)")
        AppLog.directory = folder
        AppLog.clearSteps()
    }

    override func tearDownWithError() throws {
        AppLog.directory = savedDirectory
        AppLog.maxFileSize = savedMax
        AppLog.clearSteps()
        // Remove only the folder that this test made.
        if folder.lastPathComponent.hasPrefix("AppLogTests-") { try? FileManager.default.removeItem(at: folder) }
    }

    /// A line goes to the file, with the level and the time.
    func testWriteAndRead() {
        AppLog.info("first line")
        AppLog.error("second line")
        let text = AppLog.recentText(maxLines: 1)
        XCTAssertTrue(text.contains("ERROR second line"), text)
        XCTAssertFalse(text.contains("first line"))
        XCTAssertTrue(AppLog.fullText().contains("INFO first line"))
    }

    /// At the size limit, the log keeps one old file. The full text has both files, the old file first.
    func testRotation() {
        AppLog.maxFileSize = 200
        for i in 0..<20 { AppLog.info("line \(i) " + String(repeating: "x", count: 20)) }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.sorted() ?? []
        XCTAssertEqual(names, ["iPodFirm.1.log", "iPodFirm.log"])
        let full = AppLog.fullText()
        XCTAssertTrue(full.contains("line 19"))
        let old = (try? String(contentsOf: folder.appendingPathComponent("iPodFirm.1.log"), encoding: .utf8)) ?? ""
        XCTAssertTrue(full.hasPrefix(old))
    }

    /// The log has no home folder path and no user name.
    func testRedact() {
        // The test makes the paths from parts. The commit check refuses a full home folder path in the text.
        let users = "/" + "Users"
        let t = AppLog.redact("\(users)/alex/Library/x and \(users)/other/y, alex said", home: users + "/alex", user: "alex")
        XCTAssertEqual(t, "~/Library/x and ~/y, <user> said")
        XCTAssertEqual(AppLog.redact("root and app", home: "/var/root", user: "root"), "root and app")
    }

    /// The steps go to the log and stay in memory, the oldest first, to a maximum of 50.
    func testSteps() {
        for i in 0..<60 { AppLog.step("step \(i)") }
        XCTAssertEqual(AppLog.recentSteps(2), ["step 58", "step 59"])
        XCTAssertEqual(AppLog.recentSteps(100).count, 50)
        XCTAssertEqual(AppLog.lastStep(), "step 59")
        XCTAssertTrue(AppLog.fullText().contains("Step: step 59"))
    }

    /// A FirmwareError records the location of the throw. The location does not change the equality.
    func testFirmwareErrorLocation() {
        let line = #line + 1
        let e = FirmwareError("No osos image.").adding("read the file").adding("open the file")
        XCTAssertEqual(e.line, line)
        XCTAssertTrue(e.file.hasSuffix("IPodFWKitTests.swift"))
        XCTAssertEqual(e.context, ["read the file", "open the file"])
        XCTAssertEqual(e, FirmwareError("No osos image."))
        let d = AppLog.describe(e)
        XCTAssertTrue(d.contains("FirmwareError: No osos image."))
        XCTAssertTrue(d.contains("IPodFWKitTests.swift:\(line)"))
        XCTAssertTrue(d.contains("while: read the file"))
    }

    /// The description follows the chain of underlying errors of NSError.
    func testDescribeUnderlying() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSUnderlyingErrorKey: posix])
        let e = FirmwareError("Cannot write the backup.", cause: cocoa)
        let d = AppLog.describe(e)
        XCTAssertTrue(d.contains("domain: NSCocoaErrorDomain, code: 513"), d)
        XCTAssertTrue(d.contains("Caused by:"), d)
        XCTAssertTrue(d.contains("code: \(EACCES) (Permission denied)"), d)
    }

    /// An error that is not a FirmwareError keeps its description as the cause.
    func testAddingToOtherError() {
        let e = CocoaError(.fileNoSuchFile).adding("read the theme")
        XCTAssertEqual(e.context, ["read the theme"])
        XCTAssertTrue(e.cause?.contains("NSCocoaErrorDomain") ?? false)
    }

    /// An older helper sends no detail. A new helper sends the error and its steps.
    func testHelperResultDetail() throws {
        let old = try JSONDecoder().decode(HelperResult.self, from: Data(#"{"ok":false,"message":"No iPod.","code":null}"#.utf8))
        XCTAssertNil(old.detail)
        XCTAssertTrue(old.failure().cause?.contains("older helper") ?? false)

        AppLog.step("Read the firmware partition of disk9")
        let r = HelperResult(failure: FirmwareError("Short read from disk at 4096."))
        XCTAssertFalse(r.ok)
        let detail = try XCTUnwrap(r.detail)
        XCTAssertTrue(detail.contains("Short read from disk at 4096."))
        XCTAssertTrue(detail.contains("Helper steps:"))
        XCTAssertTrue(detail.contains("disk9"))
        let back = try JSONDecoder().decode(HelperResult.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.failure().message, "Short read from disk at 4096.")
        XCTAssertTrue(back.failure().cause?.contains("In the helper:") ?? false)
    }

    /// The issue page has the fault and stays short. A long text is cut at the end.
    func testIssueURL() throws {
        let long = "first detail line\n" + String(repeating: "step line\n", count: 2000)
        let url = AppLog.issueURL(title: "Flash failed", message: "No rsrc image.", details: long, fileName: "iPodFirm Log.txt")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertTrue(url.path.hasSuffix("/issues/new"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "Fault: Flash failed")
        XCTAssertTrue(body.contains("No rsrc image."))
        XCTAssertTrue(body.contains("first detail line"))
        XCTAssertTrue(body.contains("iPodFirm Log.txt"))
        XCTAssertLessThanOrEqual(body.count, AppLog.maxIssueBody + 10)
        XCTAssertLessThan(url.absoluteString.count, 8000)
    }
}
