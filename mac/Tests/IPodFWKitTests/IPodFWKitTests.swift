import AppKit
import Foundation
@testable import IPodFWKit
import XCTest

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
        XCTAssertEqual(le32(out, 0x284c7c), try Patcher.branch("bl", at: 0x284c7c, to: 0x736644))
        XCTAssertEqual(le32(out, 0x736644), 0xe594_1018)
        XCTAssertEqual(le32(out, 0xb45f4) & 0xFF00_0000, 0xEB00_0000)   // the wake hook is a bl
        XCTAssertNotEqual(le32(out, 0xb45f4), le32(osos, 0xb45f4))
        XCTAssertEqual(le32(out, 0x736648), 0xe351_0001)                 // "cmp r1, #1": a release stays a release
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

    func testPatchVersionCompare() {
        XCTAssertGreaterThan(PatchVersion("1.10")!, PatchVersion("1.9")!)
        XCTAssertEqual(PatchVersion("1"), PatchVersion("1.0.0"))
        XCTAssertLessThan(PatchVersion("1.2")!, PatchVersion("1.2.1")!)
        for bad in ["", "1.a", "1..2", "1.2.3.4", "-1", " 1"] { XCTAssertNil(PatchVersion(bad), bad) }
        XCTAssertTrue(PatchVersion.isLower(nil, than: PatchVersion("0")))
        XCTAssertFalse(PatchVersion.isLower(nil, than: nil))
    }

    /// The Patches pane needs a title, a summary, a category and an SF Symbol for each patch.
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
    /// The album-art option "source": 0 (the default) or 1. Another value stops the build.
    func testPatchOption() throws {
        guard let ipsw = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        let osos = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: ipsw)).data).image("osos")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized
        var patch = Patcher.list(in: repo.appendingPathComponent("patches")).first { $0.spec.name == "album-art" }!
        let artwork = try Patcher.apply([patch], to: osos)
        patch.options = ["source": 1]
        let file = try Patcher.apply([patch], to: osos)
        XCTAssertEqual(artwork.count, file.count)
        let changed = artwork.indices.filter { artwork[$0] != file[$0] }
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed.first.map { $0 & 3 }, 0)
        XCTAssertEqual(changed.first.map { le32(file, $0) }, 1)
        XCTAssertEqual(changed.first.map { le32(artwork, $0) }, 0)
        patch.options = ["source": 7]
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
        let use = Patcher.spaceUse(imageCount: osos.count, patches: sizes)
        XCTAssertEqual(use.end, try Patcher.apply(set, to: osos).count)
        XCTAssertTrue(use.fits)
        // after other data that leaves too little space
        let probe = sizes.first { $0.patch.spec.name == "usb-host-probe" }!
        let filled = osos + [UInt8](repeating: 0, count: Patcher.SpaceUse.limit - 0x800 - osos.count) + [1]
        let over = Patcher.spaceUse(imageCount: filled.count, patches: [probe])
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
        // the wrappers are in the probe code, which starts at 0x736800 and is shorter than 16 KB
        for at in [0x6c8730, 0x6c878c] { XCTAssertTrue((Patcher.maxOSOSSize..<Patcher.maxOSOSSize + 0x4000).contains(Int(le32(out, at)))) }
        // after other data (a theme and the Dark Mode items to 0x7eb123): the probe goes after it
        var filled = osos + [UInt8](repeating: 0, count: 0x7eb123 - osos.count)
        filled[0x7eb122] = 1
        let after = try Patcher.apply(probe, to: filled, originalSHA256: ThemeImport.sha256(osos))
        XCTAssertTrue((0x7eb130..<0x7eb130 + 0x4000).contains(Int(le32(after, 0x6c8730))))
        // with the other code patches: different areas and hook sites
        let names = ["album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input", "usb-host-probe"]
        _ = try Patcher.apply(all.filter { names.contains($0.spec.name) }, to: osos)
    }
}

/// The USB log of usb-host-probe, with the root hub record that the emulator wrote (2026-10-07).
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
    }
}

/// The setting "Firmware layout": the empty margin below 8 MB (32 KB or 64 KB).
final class OSOSMarginTests: XCTestCase {
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
}
