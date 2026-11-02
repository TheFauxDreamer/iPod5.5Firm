import CommonCrypto
import Compression
import XCTest
@testable import IPodFWKit

/// The reader of "iTunes Library.itl" and the import of its folders. The tests use a small library
/// that they make in memory. The format is in re/playlist-folders.md, "iTunes folders".
final class ITunesLibraryTests: XCTestCase {
    private func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(v >> (8 * $0) & 0xFF) } }
    private func be32(_ v: Int) -> [UInt8] { le32(v).reversed() }

    private func nameRecord(_ name: String, utf16: Bool) -> [UInt8] {
        let text = utf16 ? Array(name.data(using: .utf16LittleEndian)!) : Array(name.utf8)
        var r = Array("mhoh".utf8) + le32(0x18) + le32(0x28 + text.count) + le32(ITunesLibrary.nameType)
        r += le32(0) + le32(0) + le32(utf16 ? 1 : 3) + le32(text.count) + [UInt8](repeating: 0, count: 8)
        return r + text
    }

    private func miph(_ name: String, id: UInt64, parent: UInt64 = 0, folder: Bool = false, utf16: Bool = false) -> [UInt8] {
        let header = 3500
        let body = nameRecord(name, utf16: utf16)
        var r = Array("miph".utf8) + le32(header) + le32(header + body.count)
        r += [UInt8](repeating: 0, count: header - r.count)
        for i in 0..<8 {
            r[ITunesLibrary.idOffset + i] = UInt8(id >> (8 * UInt64(i)) & 0xFF)
            r[ITunesLibrary.parentOffset + i] = UInt8(parent >> (8 * UInt64(i)) & 0xFF)
        }
        r[ITunesLibrary.folderOffset] = folder ? 1 : 0
        return r + body
    }

    private func section(_ type: Int, _ content: [UInt8]) -> [UInt8] {
        var r = Array("msdh".utf8) + le32(96) + le32(96 + content.count) + le32(type)
        r += [UInt8](repeating: 0, count: 96 - r.count)
        return r + content
    }

    /// zlib data with stored blocks, so the test needs no compressor.
    private func zlib(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var at = 0
        repeat {
            let n = min(0xFFFF, data.count - at)
            out += [at + n == data.count ? 1 : 0, UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8(~n >> 8 & 0xFF)]
            out += data[at..<at + n]
            at += n
        } while at < data.count
        var a = 1, b = 0
        for x in data { a = (a + Int(x)) % 65521; b = (b + a) % 65521 }
        return out + be32(b << 16 | a)
    }

    private func file(_ records: [[UInt8]]) -> [UInt8] {
        let list = Array("mlph".utf8) + le32(16) + le32(records.count) + le32(0) + records.flatMap { $0 }
        let plain = zlib(section(16, [1, 2, 3, 4]) + section(2, list))
        let encrypted = min(ITunesLibrary.defaultEncryptedLimit, plain.count & ~15)
        let body = ITunesLibrary.crypt(CCOperation(kCCEncrypt), Array(plain[0..<encrypted]))! + plain[encrypted...]
        var header = Array("hdfm".utf8) + be32(0x90) + be32(0x90 + body.count)
        header += [UInt8](repeating: 0, count: 0x5c - header.count) + be32(ITunesLibrary.defaultEncryptedLimit)
        header += [UInt8](repeating: 0, count: 0x90 - header.count)
        return header + body
    }

    private func entry(_ name: String, _ id: UInt64, master: Bool = false) -> ITunesDB.PlaylistEntry {
        var e = ITunesDB.PlaylistEntry(name: name, persistentID: id, trackIDs: [], isPodcast: false)
        e.isMaster = master
        return e
    }

    func testReadPlaylists() throws {
        let out = try ITunesLibrary.playlists(file([
            miph("Top", id: 1, folder: true),
            miph("Inner", id: 2, parent: 1),        // a folder that only a child shows
            miph("Café ✓", id: 3, parent: 2, utf16: true),
            miph("Loose", id: 4),
        ]))
        XCTAssertEqual(out, [.init(name: "Top", persistentID: 1, isFolder: true),
                             .init(name: "Inner", persistentID: 2, parentID: 1, isFolder: true),
                             .init(name: "Café ✓", persistentID: 3, parentID: 2),
                             .init(name: "Loose", persistentID: 4)])
    }

    /// Reads the owner's library if the variable ITL_SAMPLE gives its path. The file is not in the repository.
    func testRealSample() throws {
        guard let path = ProcessInfo.processInfo.environment["ITL_SAMPLE"] else { throw XCTSkip("no sample") }
        let out = try ITunesLibrary.playlists([UInt8](try Data(contentsOf: URL(fileURLWithPath: path))))
        let folders = out.filter(\.isFolder)
        XCTAssertEqual(out.count, 47)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(out.filter { $0.parentID == folders[0].persistentID }.count, 7)
    }

    func testLargerFileThanEncryptedPart() throws {
        let names = (0..<80).map { miph("Playlist \($0)", id: UInt64($0 + 1)) }
        XCTAssertEqual(try ITunesLibrary.playlists(file(names)).count, 80)
    }

    func testBadFilesGiveAnError() {
        XCTAssertThrowsError(try ITunesLibrary.playlists([]))
        XCTAssertThrowsError(try ITunesLibrary.playlists([UInt8](repeating: 0, count: 0x200)))
        var good = file([miph("A", id: 1)])
        good[0x90] ^= 0xFF
        XCTAssertThrowsError(try ITunesLibrary.playlists(good))
        XCTAssertThrowsError(try ITunesLibrary.playlists(Array(file([miph("A", id: 1)]).prefix(0x100))))
        let cut = Array(miph("A", id: 1).prefix(3000))
        XCTAssertThrowsError(try ITunesLibrary.playlists(file([cut])))
    }

    func testImport() {
        let library: [ITunesLibrary.Playlist] = [
            .init(name: "Mixes", persistentID: 10, isFolder: true),
            .init(name: "Old", persistentID: 11, parentID: 10, isFolder: true),
            .init(name: "By ID", persistentID: 12, parentID: 10),
            .init(name: "By Name", persistentID: 13, parentID: 11),
            .init(name: "Gone", persistentID: 14, parentID: 10),
            .init(name: "Empty", persistentID: 20, isFolder: true),
            .init(name: "Lost", persistentID: 21, parentID: 20),
            .init(name: "Loose", persistentID: 30),
        ]
        let ipod = [entry("Library", 1, master: true), entry("By ID", 12), entry("By Name", 99), entry("Loose", 30)]
        let (folders, missing) = PlaylistFolders.imported(from: library, ipod: ipod)
        XCTAssertEqual(folders.folders, [.init(name: "Mixes", members: [12, 99])])
        XCTAssertEqual(missing, ["Gone", "Lost"])
    }

    /// The import copies the order of the records: the top list and the playlists in a folder.
    func testImportKeepsTheLibraryOrder() {
        let library: [ITunesLibrary.Playlist] = [
            .init(name: "Zed", persistentID: 1),
            .init(name: "Folder", persistentID: 2, isFolder: true),
            .init(name: "Second", persistentID: 3, parentID: 2),
            .init(name: "First", persistentID: 4, parentID: 2),
            .init(name: "Other ID", persistentID: 5),
            .init(name: "Not Here", persistentID: 6),
        ]
        let ipod = [entry("Alpha", 9), entry("First", 4), entry("Other ID", 8), entry("Second", 3), entry("Zed", 1)]
        let f = PlaylistFolders.imported(from: library, ipod: ipod).folders
        XCTAssertEqual(f.position, .custom)
        XCTAssertEqual(f.folders[0].members, [3, 4])
        XCTAssertEqual(f.shownItems(ipod), [.playlist(1), .folder(f.folders[0].id), .playlist(8), .playlist(9)])
    }

    func testImportStopsAtALoop() {
        let library: [ITunesLibrary.Playlist] = [
            .init(name: "A", persistentID: 1, parentID: 2, isFolder: true),
            .init(name: "B", persistentID: 2, parentID: 1, isFolder: true),
            .init(name: "C", persistentID: 3, parentID: 1),
        ]
        XCTAssertEqual(PlaylistFolders.imported(from: library, ipod: [entry("C", 3)]).folders.folders.count, 1)
    }
}
