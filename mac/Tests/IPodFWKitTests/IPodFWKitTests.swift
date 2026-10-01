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

    func testReadTracksRoundTrip() {
        let tracks = (0..<5).map { DBTrack(title: "Song \($0)", artist: "A", album: "Album \($0 / 2)", path: ":iPod_Control:Music:F00:T\($0).m4a", size: 1, lengthMS: 1) }
        let read = ITunesDB.readTracks(ITunesDB.build(tracks))
        XCTAssertEqual(read.map(\.album), tracks.map(\.album))
        XCTAssertEqual(read.map(\.path), tracks.map(\.path))
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
