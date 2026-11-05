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

    /// The Music import drops the special playlists and keeps the order and the folders.
    func testMusicConvert() {
        let entries: [MusicLibrary.Entry] = [
            .init(name: "Library", persistentID: 1, parentID: nil, isFolder: false, isSpecial: true),
            .init(name: "Music", persistentID: 2, parentID: nil, isFolder: false, isSpecial: true),
            .init(name: "Folder", persistentID: 3, parentID: nil, isFolder: true, isSpecial: false),
            .init(name: "In Folder", persistentID: 4, parentID: 3, isFolder: false, isSpecial: false),
            .init(name: "Loose", persistentID: 5, parentID: nil, isFolder: false, isSpecial: false),
        ]
        XCTAssertEqual(MusicLibrary.convert(entries), [
            .init(name: "Folder", persistentID: 3, isFolder: true),
            .init(name: "In Folder", persistentID: 4, parentID: 3),
            .init(name: "Loose", persistentID: 5),
        ])
    }

    /// The real Music library of this Mac, read only. Set IPODFW_MUSIC_TEST=1 to run it. The test
    /// compares the read of `MusicLibrary` with the data that the Music app gives through AppleScript.
    /// Then it imports the folders as if the iPod had each playlist of the library. The test prints
    /// the names of the playlists, so do not copy its output into the repository.
    func testRealMusicLibrary() throws {
        guard ProcessInfo.processInfo.environment["IPODFW_MUSIC_TEST"] == "1" else { throw XCTSkip("set IPODFW_MUSIC_TEST=1") }
        let library = try MusicLibrary.playlists()
        let hex = { (v: UInt64) in String(format: "%016llX", v) }

        // The data of the Music app: kind, persistent ID, parent ID, special kind and name.
        let script = """
        tell application "Music"
          set out to ""
          repeat with p in folder playlists
            set par to ""
            try
              set par to persistent ID of parent of p
            end try
            set out to out & "F" & tab & (persistent ID of p) & tab & par & tab & "none" & tab & (name of p) & linefeed
          end repeat
          repeat with p in user playlists
            if class of p is not folder playlist then
              set par to ""
              try
                set par to persistent ID of parent of p
              end try
              set out to out & "P" & tab & (persistent ID of p) & tab & par & tab & ((special kind of p) as text) & tab & (name of p) & linefeed
            end if
          end repeat
          return out
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()
        XCTAssertEqual(task.terminationStatus, 0, "osascript failed")
        struct Row { let folder: Bool; let id: String; let parent: String; let special: String; let name: String }
        let rows = output.split(separator: "\n").compactMap { line -> Row? in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5 else { return nil }
            return Row(folder: f[0] == "F", id: f[1], parent: f[2], special: f[3], name: f[4...].joined(separator: "\t"))
        }
        let music = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        print("Music app: \(rows.filter(\.folder).count) folders, \(rows.filter { !$0.folder }.count) playlists. MusicLibrary: \(library.count) items.")

        // 1. Each item of MusicLibrary agrees with the Music app.
        for p in library {
            guard let m = music[hex(p.persistentID)] else { XCTFail("not in the Music app: \(p.name)"); continue }
            XCTAssertEqual(m.name, p.name)
            XCTAssertEqual(m.folder, p.isFolder, p.name)
            XCTAssertEqual(m.parent, p.parentID == 0 ? "" : hex(p.parentID), p.name)
        }
        // 2. Each folder of the Music app is in MusicLibrary. Print the playlists that MusicLibrary drops.
        let ours = Set(library.map { hex($0.persistentID) })
        for m in rows where m.folder { XCTAssertTrue(ours.contains(m.id), "folder not read: \(m.name)") }
        for m in rows where !m.folder && !ours.contains(m.id) { print("Dropped as special: \(m.name) (\(m.special))") }

        // 3. The import, as if the iPod had each playlist of the library.
        let ipod = library.filter { !$0.isFolder }.map {
            ITunesDB.PlaylistEntry(name: $0.name, persistentID: $0.persistentID, trackIDs: [], isPodcast: false)
        }
        let (folders, missing) = PlaylistFolders.imported(from: library, ipod: ipod)
        XCTAssertEqual(missing, [])
        func top(_ id: String) -> Row? {
            var at = music[id], seen = Set<String>()
            while let a = at, !a.parent.isEmpty, let up = music[a.parent], seen.insert(up.id).inserted {
                if up.parent.isEmpty { return up }
                at = up
            }
            return nil
        }
        let playlistRows = rows.filter { !$0.folder && ours.contains($0.id) }
        for m in rows where m.folder && m.parent.isEmpty {
            let expected = playlistRows.filter { top($0.id)?.id == m.id }.map(\.id)
            let got = folders.folders.first { $0.name == m.name }?.members.map(hex) ?? []
            XCTAssertEqual(got, expected, "members of \(m.name)")
        }

        // 4. The top-level order of the iPod, and the order of Folders4Playlist (folders first).
        let byID = Dictionary(library.map { ($0.persistentID, $0.name) }, uniquingKeysWith: { a, _ in a })
        let shown = folders.shownItems(ipod).map { item -> String in
            switch item {
            case .folder(let id): return "[F] " + (folders.folders.first { $0.id == id }?.name ?? "?")
            case .playlist(let id): return byID[id] ?? "?"
            }
        }
        let theirs = rows.filter { r in r.folder && r.parent.isEmpty && folders.folders.contains { $0.name == r.name } }.map { "[F] " + $0.name }
            + playlistRows.filter { top($0.id) == nil }.map(\.name)
        print("iPodFirm top level:\n  " + shown.joined(separator: "\n  "))
        print("Same order as Folders4Playlist: \(shown == theirs)")
        if shown != theirs { print("Folders4Playlist top level:\n  " + theirs.joined(separator: "\n  ")) }
    }
}
