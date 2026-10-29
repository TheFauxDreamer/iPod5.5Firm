import XCTest
@testable import IPodFWKit

/// The folder file of the playlist-folders patch (format: patches/playlist-folders/playlist_folders.c).
final class PlaylistFoldersTests: XCTestCase {
    func testEncodeLayout() {
        let f = PlaylistFolders(folders: [.init(name: "Road", colour: 0xf800, members: [0x1122334455667788])],
                                alphabetical: true)
        let b = f.encode()
        XCTAssertEqual(Array(b[0..<12]), Array("IFPF".utf8) + [1, 0, 1, 0, 1, 0, 0, 0])
        XCTAssertEqual(Array(b[12..<20]), [0x00, 0xf8, 4, 0, 1, 0, 0, 0])          // colour, 4 units, 1 member
        XCTAssertEqual(Array(b[20..<28]), [0x52, 0, 0x6f, 0, 0x61, 0, 0x64, 0])   // "Road"
        XCTAssertEqual(Array(b[28..<36]), [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])
        XCTAssertEqual(b.count, 36)
    }

    func testOddNameIsPadded() {
        let b = PlaylistFolders(folders: [.init(name: "Zul", members: [7])]).encode()
        XCTAssertEqual(b.count, 12 + 8 + 8 + 8)                                   // 3 units = 6 bytes, padded to 8
        XCTAssertEqual(b[28], 7)
    }

    func testRoundTrip() {
        let f = PlaylistFolders(folders: [.init(name: "Road Trip ✓", colour: 0x07e0, members: [1, 2, 3]),
                                          .init(name: "Zulu", colour: 0x001f, members: [])],
                                alphabetical: false)
        XCTAssertEqual(PlaylistFolders.decode(f.encode()), f)
    }

    func testDecodeRejectsBadFiles() {
        XCTAssertNil(PlaylistFolders.decode([]))
        XCTAssertNil(PlaylistFolders.decode(Array("IFPX".utf8) + [1, 0, 0, 0, 0, 0, 0, 0]))
        var short = PlaylistFolders(folders: [.init(name: "A", members: [1, 2])]).encode()
        short.removeLast(4)
        XCTAssertNil(PlaylistFolders.decode(short))
    }

    func testMoveKeepsOneFolder() {
        var f = PlaylistFolders(folders: [.init(name: "A"), .init(name: "B")])
        f.move(9, to: 0)
        f.move(9, to: 1)
        XCTAssertEqual(f.folders[0].members, [])
        XCTAssertEqual(f.folders[1].members, [9])
        XCTAssertEqual(f.folderIndex(of: 9), 1)
        f.move(9, to: nil)
        XCTAssertNil(f.folderIndex(of: 9))
        f.folders[0].members = [1, 2]
        f.removeMissing([2])
        XCTAssertEqual(f.folders[0].members, [2])
    }

    func testProblems() {
        let names = ["Mix", "Road Trip"]
        XCTAssertEqual(PlaylistFolders(folders: [.init(name: "Old")]).problems(playlistNames: names), [])
        XCTAssertFalse(PlaylistFolders(folders: [.init(name: "road trip")]).problems(playlistNames: names).isEmpty)
        XCTAssertFalse(PlaylistFolders(folders: [.init(name: " ")]).problems(playlistNames: names).isEmpty)
        XCTAssertFalse(PlaylistFolders(folders: [.init(name: "A"), .init(name: "a")]).problems(playlistNames: names).isEmpty)
        XCTAssertFalse(PlaylistFolders(folders: [.init(name: String(repeating: "x", count: 64))]).problems(playlistNames: names).isEmpty)
    }

    func testColour() {
        XCTAssertEqual(PlaylistFolders.rgb565(red: 255, green: 0, blue: 0), 0xf800)
        XCTAssertEqual(PlaylistFolders.components(0xf800).red, 255)
        XCTAssertEqual(PlaylistFolders.components(0xffff).green, 255)
        XCTAssertNotNil(PlaylistFolders.tile(0x07e0))
        let art = PlaylistFolders(folders: [.init(name: "Road")]).artEntries()
        XCTAssertEqual(Array(art.keys), [AlbumArt.playlistKey("Road")])
    }

    /// The persistent ID is at mhyp +0x1c. The patch compares it with playlist + 0x18.
    func testReadPlaylistEntries() {
        let tracks = (0..<3).map { DBTrack(title: "Song \($0)", artist: "A", album: "B", path: ":iPod_Control:Music:F00:T\($0).m4a", size: 1, lengthMS: 1) }
        let db = ITunesDB.build(tracks, playlists: [(name: "One", tracks: [0]), (name: "Two", tracks: [1, 2])])
        let entries = ITunesDB.readPlaylistEntries(db)
        XCTAssertEqual(entries.map(\.name), ["One", "Two"])
        var p = 0, found = [UInt64]()
        while let r = db[p...].firstIndex(of: 0x6d), r + 0x24 < db.count {
            if Array(db[r..<r + 4]) == Array("mhyp".utf8) {
                found.append((0..<8).reduce(UInt64(0)) { $0 | UInt64(db[r + 0x1c + $1]) << (8 * UInt64($1)) })
            }
            p = r + 1
        }
        XCTAssertEqual(entries.map(\.persistentID), Array(found.dropFirst()))      // not the master playlist
        XCTAssertFalse(entries.contains { $0.isPodcast })
        XCTAssertNotEqual(entries[0].persistentID, entries[1].persistentID)
    }
}
