import XCTest
@testable import IPodFWKit

/// The FAT volume in rsrc and the fonts. Needs IPODFW_IPSW (Apple iPod_25.1.3.ipsw).
final class ResourceVolumeTests: XCTestCase {
    var partition: FirmwarePartition!
    var apple: [String: [UInt8]] = [:]

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["IPODFW_IPSW"] else { throw XCTSkip("set IPODFW_IPSW") }
        partition = try FirmwarePartition(data: IPSW.extractFirmware(URL(fileURLWithPath: path)).data)
        apple = try IPodFonts.fonts(in: partition)
    }

    /// The values that re/fonts.md gives.
    func testTheAppleVolume() throws {
        let v = try IPodFonts.volume(partition)
        XCTAssertTrue(v.isFAT12)
        XCTAssertEqual(v.bytes.count, 0x500000)
        XCTAssertEqual(v.files.count, 16)
        XCTAssertEqual(v.freeBytes, 632_832)
        XCTAssertEqual(apple["CJK.ttf"]?.count, 3_446_748)
        XCTAssertEqual(Set(apple.keys), Set(IPodFonts.names))
        for name in IPodFonts.names {
            XCTAssertEqual(try IPodFonts.strikes(apple[name]!).count, 1, name)
            XCTAssertEqual(try IPodFonts.strikes(apple[name]!)[0][2], 4, name)
        }
        XCTAssertEqual(try IPodFonts.strikes(apple["CJK.ttf"]!)[0][0], 18)
    }

    /// No fonts: rsrc stays byte for byte the Apple rsrc.
    func testNoFontsChangesNothing() throws {
        let before = partition.data
        try IPodFonts.apply([:], to: partition)
        XCTAssertEqual(partition.data, before)
        XCTAssertEqual(try IPodFonts.rsrc(of: partition, with: [:]), try partition.image("rsrc"))
    }

    /// A font of the same content gives the same bytes.
    func testTheSameFontGivesTheSameBytes() throws {
        XCTAssertEqual(try IPodFonts.rsrc(of: partition, with: ["CJK.ttf": apple["CJK.ttf"]!]), try partition.image("rsrc"))
    }

    func checkVolume(_ v: ResourceVolume, expect fonts: [String: [UInt8]], file: StaticString = #filePath, line: UInt = #line) throws {
        let first = Array(v.bytes[v.fatStart..<v.fatStart + v.fatBytes])
        XCTAssertEqual(Array(v.bytes[v.fatStart + v.fatBytes..<v.fatStart + 2 * v.fatBytes]), first, "the two FATs", file: file, line: line)
        var used = Set<Int>()
        for f in v.files {
            let c = v.chain(f.firstCluster)
            XCTAssertEqual(c.count, (f.size + v.clusterBytes - 1) / v.clusterBytes, f.path, file: file, line: line)
            XCTAssertEqual(c, Array(c.first.map { $0..<$0 + c.count } ?? 0..<0), "\(f.path) is contiguous", file: file, line: line)
            XCTAssertTrue(used.isDisjoint(with: c), f.path, file: file, line: line)
            used.formUnion(c)
        }
        let appleVolume = try IPodFonts.volume(partition)
        for f in appleVolume.files {
            let name = String(f.path.dropFirst(IPodFonts.folder.count))
            let expected = f.path.hasPrefix(IPodFonts.folder) ? (fonts[name] ?? appleVolume.read(f)) : appleVolume.read(f)
            XCTAssertEqual(v.read(v.file(f.path)!), expected, f.path, file: file, line: line)
        }
    }

    /// A larger CJK.ttf goes into the free space. All other files stay the same.
    func testALargerFontFits() throws {
        var cjk = apple["CJK.ttf"]!
        cjk += [UInt8](repeating: 0xA5, count: 300_000)
        let entryOffset = try partition.entry("rsrc").entryOffset
        try IPodFonts.apply(["CJK.ttf": cjk], to: partition)
        XCTAssertTrue(partition.checksumOK("rsrc"))
        XCTAssertEqual(try partition.entry("rsrc").entryOffset, entryOffset)
        XCTAssertEqual(try partition.image("rsrc").count, 0x500800)
        try checkVolume(IPodFonts.volume(partition), expect: ["CJK.ttf": cjk])
        XCTAssertEqual(try IPodFonts.fonts(in: partition)["CJK.ttf"], cjk)
    }

    /// No free area is large enough, but the total fits: all files go again in their order.
    func testTheFilesGoAgainInTheirOrder() throws {
        let v = try IPodFonts.volume(partition)
        let free = v.freeBytes / v.clusterBytes, own = v.chain(v.file(IPodFonts.folder + "Helvetica_17.ttf")!.firstCluster).count
        let big = [UInt8](repeating: 0x3C, count: (free + own - 2) * v.clusterBytes)
        var changed = v
        try changed.replace(IPodFonts.folder + "Helvetica_17.ttf", with: big)
        try checkVolume(changed, expect: ["Helvetica_17.ttf": big])
        XCTAssertEqual(changed.freeBytes, 2 * v.clusterBytes)
    }

    func testAFontThatIsTooLargeIsRefused() throws {
        var v = try IPodFonts.volume(partition)
        let before = v.bytes
        XCTAssertThrowsError(try v.replace(IPodFonts.folder + "CJK.ttf", with: apple["CJK.ttf"]! + [UInt8](repeating: 1, count: 700_000)))
        XCTAssertEqual(v.bytes, before)
    }

    func testTheFontCheck() throws {
        for name in IPodFonts.names { XCTAssertNoThrow(try IPodFonts.check(name, apple[name]!, apple: apple)) }
        XCTAssertThrowsError(try IPodFonts.check("Other.ttf", apple["CJK.ttf"]!, apple: apple))
        XCTAssertThrowsError(try IPodFonts.check("CJK.ttf", Array(apple["CJK.ttf"]!.prefix(100)), apple: apple))
        // a strike of 17 ppem in place of 18 ppem
        XCTAssertThrowsError(try IPodFonts.check("CJK.ttf", apple["Helvetica_17.ttf"]!, apple: apple))
    }

    /// The FAT check of macOS (fsck_msdos) examines a changed volume. Set IPODFW_DISK_TEST=1: the
    /// test attaches a disk image with hdiutil. A mount needs a kernel extension, thus no mount.
    func testMacOSAcceptsTheChangedVolume() throws {
        guard ProcessInfo.processInfo.environment["IPODFW_DISK_TEST"] == "1" else { throw XCTSkip("set IPODFW_DISK_TEST=1") }
        func sh(_ args: [String]) throws -> String { String(decoding: try runTool(args[0], Array(args.dropFirst())), as: UTF8.self) }
        func fsck(_ device: String) -> String {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/sbin/fsck_msdos")
            p.arguments = ["-n", device]
            p.standardOutput = pipe
            p.standardError = pipe
            try? p.run()
            let out = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(decoding: out, as: UTF8.self)
        }
        let v = try IPodFonts.volume(partition)
        let own = v.chain(v.file(IPodFonts.folder + "Helvetica_17.ttf")!.firstCluster).count
        let big = (0..<((v.freeBytes / v.clusterBytes + own - 2) * v.clusterBytes)).map { UInt8($0 & 0xFF) }
        let cjk = apple["CJK.ttf"]! + [UInt8](repeating: 0x11, count: 5000)
        for changes in [["CJK.ttf": cjk], ["Helvetica_17.ttf": big]] {
            var changed = v
            try changed.replace(Dictionary(uniqueKeysWithValues: changes.map { (IPodFonts.folder + $0.key, $0.value) }))
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ipodfw-fat-\(UUID().uuidString).img")
            try Data(changed.bytes).write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let out = try sh(["/usr/bin/hdiutil", "attach", "-nomount", "-readonly", "-imagekey", "diskimage-class=CRawDiskImage", tmp.path])
            let disk = String(out.split(separator: " ").first!).replacingOccurrences(of: "/dev/", with: "")
            defer { _ = try? sh(["/usr/bin/hdiutil", "detach", "/dev/\(disk)"]) }
            // The Apple volume gives the same two warnings: a long name entry for the volume label and
            // one orphan cluster. A change must give no other warning.
            let lines = fsck("/dev/r\(disk)").split(separator: "\n").map(String.init)
            let warnings = lines.filter { $0.hasPrefix("Warning") && !$0.contains("files,") }
            XCTAssertEqual(warnings, ["Warning: Invalid long filename entry for volume label",
                                      "Warning: Found orphan cluster(s)", "Warning: Found 1 orphaned clusters"], lines.joined(separator: "\n"))
        }
    }

    /// A build with a larger osos (rsrc moves) and a custom font: the flash checks accept it, and the
    /// iPod reads the font at the entryOffset of rsrc.
    func testABuildWithFontsPassesTheFlashChecks() throws {
        let ipsw = URL(fileURLWithPath: ProcessInfo.processInfo.environment["IPODFW_IPSW"]!)
        var podium = apple["PodiumSans18.ttf"]!
        podium[500] ^= 0x0F
        let osos = try partition.image("osos") + [UInt8](repeating: 1, count: 40_000)
        let built = try FirmwarePartition(data: IPSW.firmware(original: ipsw, withOSOS: osos, fonts: ["PodiumSans18.ttf": podium]))
        XCTAssertTrue(built.checksumOK("osos"))
        XCTAssertTrue(built.checksumOK("rsrc"))
        XCTAssertEqual(try built.entry("rsrc").entryOffset, 0x600)
        XCTAssertEqual(try IPodFonts.fonts(in: built)["PodiumSans18.ttf"], podium)
        XCTAssertEqual(IPodFonts.custom(try IPodFonts.fonts(in: built), apple: apple).keys.sorted(), ["PodiumSans18.ttf"])
        // the iPod: the Apple file with free space after it
        var ipod = partition.data
        ipod += [UInt8](repeating: 0, count: 0x2000000)
        let current = try FirmwarePartition(data: ipod)
        let fitted = try FirmwarePartition(data: FirmwareFlasher.fitLayout(new: built.data, current: current))
        try FirmwareFlasher.checkCompatible(current: current, new: fitted, label: "t")
        XCTAssertEqual(try IPodFonts.fonts(in: fitted)["PodiumSans18.ttf"], podium)
    }

    /// Check a font file before a real test: set IPODFW_FONT to its path. The file name must be the
    /// name of an iPod font, for example CJK.ttf. The test does the check of the import and a build.
    func testAFontFile() throws {
        guard let path = ProcessInfo.processInfo.environment["IPODFW_FONT"] else { throw XCTSkip("set IPODFW_FONT") }
        let url = URL(fileURLWithPath: path)
        let font = [UInt8](try Data(contentsOf: url))
        let name = url.lastPathComponent
        try IPodFonts.check(name, font, apple: apple)
        let free = try IPodFonts.volume(partition).freeBytes
        try IPodFonts.apply([name: font], to: partition)
        XCTAssertTrue(partition.checksumOK("rsrc"))
        XCTAssertEqual(try IPodFonts.fonts(in: partition)[name], font)
        print("IPODFW_FONT \(name): \(font.count) bytes, Apple \(apple[name]!.count) bytes, free before \(free), "
              + "free after \(try IPodFonts.volume(partition).freeBytes)")
    }

    func testCustomGivesOnlyTheChangedFonts() throws {
        var fonts = apple
        fonts["PodiumSans18.ttf"]![100] ^= 1
        XCTAssertEqual(Array(IPodFonts.custom(fonts, apple: apple).keys), ["PodiumSans18.ttf"])
    }
}
