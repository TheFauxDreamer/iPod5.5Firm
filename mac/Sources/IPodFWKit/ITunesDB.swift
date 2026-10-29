import CoreGraphics
import Foundation

// Swift port of src/ipodfw/itunesdb.py: a minimal iTunesDB writer.
// The layout follows the libgpod writer (itdb_itunesdb.c).

public struct DBTrack {
    public var title: String
    public var artist: String
    public var album: String
    public var path: String          // iPod path with colons, for example ":iPod_Control:Music:F00:T0001.m4a"
    public var size: UInt32
    public var lengthMS: UInt32
    public var trackNumber: UInt32 = 0
    public var trackCount: UInt32 = 0
    public var year: UInt32 = 0
    public var genre: String = ""
    public var albumArtist: String = ""
    public var disc: UInt32 = 0
    public var dbid: UInt64 = 0          // 0: build() makes one
    public var imageID: UInt32 = 0       // the mhii of the artwork in ArtworkDB (0: no artwork)
    public var artworkSize: UInt32 = 0   // bytes of the artwork in the music file

    public init(title: String, artist: String, album: String, path: String, size: UInt32, lengthMS: UInt32,
                trackNumber: UInt32 = 0, trackCount: UInt32 = 0, year: UInt32 = 0, genre: String = "",
                albumArtist: String = "", disc: UInt32 = 0) {
        self.title = title; self.artist = artist; self.album = album; self.path = path; self.size = size
        self.lengthMS = lengthMS; self.trackNumber = trackNumber; self.trackCount = trackCount
        self.year = year; self.genre = genre; self.albumArtist = albumArtist; self.disc = disc
    }
}

enum NSColorLike {
    /// A saturated colour for a hue from 0 to 1.
    static func rgb(hue: CGFloat) -> (UInt8, UInt8, UInt8) {
        let h = hue * 6, x = 1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (CGFloat, CGFloat, CGFloat) = h < 1 ? (1, x, 0) : h < 2 ? (x, 1, 0) : h < 3 ? (0, 1, x) : h < 4 ? (0, x, 1) : h < 5 ? (x, 0, 1) : (1, 0, x)
        return (UInt8(r * 220 + 20), UInt8(g * 220 + 20), UInt8(b * 220 + 20))
    }
}

public enum ITunesDB {
    struct Writer {
        var b = [UInt8]()
        mutating func u8(_ v: UInt8) { b.append(v) }
        mutating func u16(_ v: UInt16) { b += [UInt8(v & 0xFF), UInt8(v >> 8)] }
        mutating func u32(_ v: UInt32) { for i in 0..<4 { b.append(UInt8(v >> (8 * UInt32(i)) & 0xFF)) } }
        mutating func u64(_ v: UInt64) { for i in 0..<8 { b.append(UInt8(v >> (8 * UInt64(i)) & 0xFF)) } }
        mutating func tag(_ s: String) { b += Array(s.utf8) }
        mutating func zeros(_ n: Int) { b += [UInt8](repeating: 0, count: n) }
        mutating func pad(to n: Int, from start: Int) { zeros(n - (b.count - start)) }
        mutating func set32(_ at: Int, _ v: UInt32) { for i in 0..<4 { b[at + i] = UInt8(v >> (8 * UInt32(i)) & 0xFF) } }
        /// Write the total size (offset +8) of the chunk that starts at `at`.
        mutating func closeChunk(_ at: Int) { set32(at + 8, UInt32(b.count - at)) }
    }

    static func stringMHOD(_ kind: UInt32, _ text: String) -> [UInt8] {
        var w = Writer()
        let body = Array(text.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        w.tag("mhod"); w.u32(24); w.u32(UInt32(40 + body.count)); w.u32(kind); w.zeros(8)
        w.u32(1); w.u32(UInt32(body.count)); w.u32(1); w.u32(0)
        w.b += body
        return w.b
    }

    static func positionMHOD(_ pos: UInt32) -> [UInt8] {
        var w = Writer()
        w.tag("mhod"); w.u32(24); w.u32(44); w.u32(100); w.zeros(8); w.u32(pos); w.zeros(16)
        return w.b
    }

    static func longPlaylistMHOD() -> [UInt8] {
        var w = Writer()
        w.tag("mhod"); w.u32(0x18); w.u32(0x288); w.u32(100); w.zeros(24)
        let words: [UInt32] = [0x010084, 5, 9, 3, 0x120001, 0, 0, 0, 0xC80002, 0, 0, 0, 0x3C000D, 0, 0, 0, 0x7D0004, 0, 0, 0,
                               0x7D0003, 0, 0, 0, 0x640008, 0, 0, 0, 0x640017, 1, 0, 0, 0x500014, 1, 0, 0, 0x7D0015, 1]
        words.forEach { w.u32($0) }
        w.zeros(4 * 114)
        return w.b
    }

    /// `playlists` gives the name of each playlist and the indexes of its tracks in `tracks`.
    public static func build(_ tracks: [DBTrack], libraryName: String = "iPod", playlists: [(name: String, tracks: [Int])] = []) -> [UInt8] {
        var rng = SystemRandomNumberGenerator()
        let now = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970) + 2_082_844_800)
        var w = Writer()

        // mhbd
        w.tag("mhbd"); w.u32(244); w.u32(0); w.u32(1); w.u32(0x13); w.u32(2); w.u64(rng.next()); w.u16(1)
        w.pad(to: 244, from: 0)
        w.b[0x46] = UInt8(ascii: "e"); w.b[0x47] = UInt8(ascii: "n")

        // mhsd type 1: tracks
        let mhsd1 = w.b.count
        w.tag("mhsd"); w.u32(96); w.u32(0); w.u32(1); w.zeros(80)
        w.tag("mhlt"); w.u32(92); w.u32(UInt32(tracks.count)); w.zeros(80)
        for (i, t) in tracks.enumerated() {
            var mhods = [stringMHOD(1, t.title), stringMHOD(4, t.artist), stringMHOD(3, t.album),
                         stringMHOD(6, "AAC audio file"), stringMHOD(2, t.path),
                         stringMHOD(22, t.albumArtist.isEmpty ? t.artist : t.albumArtist)]
            if !t.genre.isEmpty { mhods.append(stringMHOD(5, t.genre)) }
            let start = w.b.count
            w.tag("mhit"); w.u32(0x248); w.u32(0); w.u32(UInt32(mhods.count))
            w.u32(UInt32(1000 + i)); w.u32(1); w.u32(0x4D34_4120)        // id, visible, "M4A "
            w.u8(0); w.u8(0); w.u8(0); w.u8(0)                            // type1, type2, compilation, rating
            w.u32(now); w.u32(t.size); w.u32(t.lengthMS); w.u32(t.trackNumber)
            w.u32(t.trackCount); w.u32(t.year); w.u32(128); w.u32(44100 << 16)
            w.pad(to: 0x5C, from: start); w.u32(t.disc)
            w.pad(to: 0x68, from: start); w.u32(now)                      // date added
            let dbid = rng.next()
            w.pad(to: 0x70, from: start); w.u64(t.dbid != 0 ? t.dbid : dbid); w.u8(1)   // dbid, checked
            if t.imageID != 0 {
                w.pad(to: 0x7C, from: start); w.u16(1); w.zeros(2); w.u32(t.artworkSize)    // artwork count and size
                w.pad(to: 0xA4, from: start); w.u8(1)                                         // has artwork
            }
            w.pad(to: 0xD0, from: start); w.u32(1)                        // media type: audio
            w.pad(to: 0x12C, from: start); w.u32(t.size)
            w.pad(to: 0x134, from: start); w.u64(0x8080_8080_8080)
            if t.imageID != 0 { w.pad(to: 0x160, from: start); w.u32(t.imageID) }             // mhii link
            w.pad(to: 0x168, from: start); w.u32(1)
            w.pad(to: 0x248, from: start)
            mhods.forEach { w.b += $0 }
            w.closeChunk(start)
        }
        w.closeChunk(mhsd1)

        // mhsd type 2: playlists (the master playlist first)
        let lists = [(name: libraryName, tracks: Array(tracks.indices))] + playlists
        let mhsd2 = w.b.count
        w.tag("mhsd"); w.u32(96); w.u32(0); w.u32(2); w.zeros(80)
        w.tag("mhlp"); w.u32(92); w.u32(UInt32(lists.count)); w.zeros(80)
        for (n, list) in lists.enumerated() {
            let master = n == 0
            let mhyp = w.b.count
            w.tag("mhyp"); w.u32(108); w.u32(0); w.u32(master ? 2 : 1); w.u32(UInt32(list.tracks.count))
            w.u8(master ? 1 : 0); w.u8(0); w.u8(0); w.u8(0); w.u32(now); w.u64(rng.next())
            w.u32(0); w.u16(1); w.u16(0); w.u32(0)
            w.pad(to: 108, from: mhyp)
            w.b += stringMHOD(1, list.name)
            if master { w.b += longPlaylistMHOD() }
            for (pos, index) in list.tracks.enumerated() {
                let mhip = w.b.count
                w.tag("mhip"); w.u32(76); w.u32(0); w.u32(1); w.u32(0); w.u32(0); w.u32(UInt32(1000 + index)); w.u32(0); w.u32(0)
                w.zeros(40)
                w.b += positionMHOD(UInt32(pos))
                w.closeChunk(mhip)
            }
            w.closeChunk(mhyp)
        }
        w.closeChunk(mhsd2)
        w.closeChunk(0)
        return w.b
    }

    /// Write `iPod_Control/{Music/F00/*.m4a, iTunes/iTunesDB}` under `dir`.
    /// `songs` AAC files (sine tones, made with afconvert). With `tracks` > `songs`, the extra
    /// tracks use the same files with their own titles and albums. Ten tracks make one album.
    /// The library has two playlists. "Test Album 1" has the same name as an album.
    public static func makeLibrary(at dir: URL, songs: Int = 6, tracks: Int = 60, seconds: Int = 30) throws {
        let fm = FileManager.default
        let music = dir.appendingPathComponent("iPod_Control/Music/F00")
        let itunes = dir.appendingPathComponent("iPod_Control/iTunes")
        try fm.createDirectory(at: music, withIntermediateDirectories: true)
        try fm.createDirectory(at: itunes, withIntermediateDirectories: true)
        var files: [(name: String, size: UInt32)] = []
        for i in 0..<songs {
            let name = String(format: "T%04d.m4a", i)
            let m4a = music.appendingPathComponent(name)
            if !fm.fileExists(atPath: m4a.path) {
                let wav = fm.temporaryDirectory.appendingPathComponent("ipodfirm-\(i).wav")
                try sineWAV(seconds: seconds, frequency: 220 * pow(2, Double(i) / 12)).write(to: wav)
                defer { try? fm.removeItem(at: wav) }
                _ = try runTool("/usr/bin/afconvert", ["-f", "m4af", "-d", "aac", "-b", "128000", wav.path, m4a.path])
            }
            let size = (try fm.attributesOfItem(atPath: m4a.path)[.size] as? NSNumber)?.uint32Value ?? 0
            files.append((name, size))
        }
        let list: [DBTrack] = (0..<max(tracks, songs)).map { n in
            let f = files[n % songs]
            return DBTrack(title: "Test Song \(n + 1)", artist: "Test Artist \(n / 50 + 1)", album: "Test Album \(n / 10 + 1)",
                           path: ":iPod_Control:Music:F00:\(f.name)", size: f.size, lengthMS: UInt32(seconds * 1000),
                           trackNumber: UInt32(n % 10 + 1), trackCount: 10, year: 2006, genre: "Test")
        }
        let count = max(tracks, songs)
        let playlists = [(name: "Test Album 1", tracks: Array(stride(from: 0, to: count, by: 7))),
                         (name: "Road Trip", tracks: Array(stride(from: count - 1, through: 0, by: -3)))]
        try Data(build(list, playlists: playlists)).write(to: itunes.appendingPathComponent("iTunesDB"))
        // A plain-colour cover for each test album, so that the album-art patch has artwork to show.
        // The playlists get grey covers: a different colour from the album with the same name.
        var covers = [String: Data]()
        func cover(_ c: (UInt8, UInt8, UInt8)) -> Data? {
            let px: [UInt8] = (0..<(8 * 8)).flatMap { _ -> [UInt8] in [c.0, c.1, c.2, 255] }
            return ImageCodec.cgImage(rgba: px, width: 8, height: 8, alpha: false).flatMap(ImageCodec.pngData)
        }
        for album in Set(list.map(\.album)) {
            let n = Int(album.split(separator: " ").last ?? "1") ?? 1
            covers[album] = cover(NSColorLike.rgb(hue: CGFloat((n * 47) % 360) / 360))
        }
        for (i, p) in playlists.enumerated() { covers[AlbumArt.playlistKey(p.name)] = cover(i == 0 ? (90, 90, 90) : (200, 200, 200)) }
        try Data(AlbumArt.build(covers)).write(to: itunes.appendingPathComponent(AlbumArt.fileName))
    }

    /// Read (album, path) of each track in an iTunesDB. `path` is the iPod path with colons.
    public static func readTracks(_ db: [UInt8]) -> [(album: String, path: String)] {
        readTrackRecords(db).map { ($0.album, $0.path) }
    }

    /// Read (track ID, album, path) of each track in an iTunesDB. The track ID is the value that the
    /// playlists use.
    public static func readTrackRecords(_ db: [UInt8]) -> [(id: UInt32, album: String, path: String)] {
        guard db.count > 12, Array(db[0..<4]) == Array("mhbd".utf8) else { return [] }
        // Go from one mhsd to the next with its total size. The other sections (for example
        // the album list, mhla, which iTunes writes first) do not all keep their size at +8.
        var p = Int(le32(db, 4))
        while p + 16 <= db.count, String(decoding: db[p..<p + 4], as: UTF8.self) == "mhsd" {
            let hlen = Int(le32(db, p + 4)), total = Int(le32(db, p + 8))
            guard total > 0 else { break }
            if le32(db, p + 12) == 1 {
                return readTrackList(db, from: p + hlen, to: min(p + total, db.count))
            }
            p += total
        }
        return []
    }

    static func readTrackList(_ db: [UInt8], from start: Int, to end: Int) -> [(id: UInt32, album: String, path: String)] {
        guard start + 12 <= end, String(decoding: db[start..<start + 4], as: UTF8.self) == "mhlt" else { return [] }
        var out: [(UInt32, String, String)] = []
        var p = start + Int(le32(db, start + 4))
        for _ in 0..<Int(le32(db, start + 8)) {
            guard p + 20 <= end, String(decoding: db[p..<p + 4], as: UTF8.self) == "mhit" else { break }
            let hlen = Int(le32(db, p + 4)), total = Int(le32(db, p + 8))
            guard total >= hlen, hlen > 0 else { break }
            var album = "", path = ""
            var q = p + hlen
            for _ in 0..<Int(le32(db, p + 12)) {
                guard q + 40 <= min(p + total, end), String(decoding: db[q..<q + 4], as: UTF8.self) == "mhod" else { break }
                let kind = le32(db, q + 12), len = Int(le32(db, q + 8))
                guard len > 0 else { break }
                if kind == 2 || kind == 3, let text = mhodString(db, q) {
                    if kind == 2 { path = text } else { album = text }
                }
                q += len
            }
            out.append((le32(db, p + 16), album, path))
            p += total
        }
        return out
    }

    /// Read the name and the track IDs of each playlist in an iTunesDB, in the order of the
    /// database. The master playlist (the whole library) is not included.
    public static func readPlaylists(_ db: [UInt8]) -> [(name: String, trackIDs: [UInt32])] {
        readPlaylistEntries(db).map { ($0.name, $0.trackIDs) }
    }

    /// A playlist of an iTunesDB.
    public struct PlaylistEntry: Identifiable, Equatable {
        public var name: String
        /// The persistent ID (mhyp +0x1c). The firmware keeps it at playlist + 0x18.
        public var persistentID: UInt64
        public var trackIDs: [UInt32]
        /// A podcast playlist (mhyp +0x2a). The Playlists list of the iPod does not show it.
        public var isPodcast: Bool
        public var id: UInt64 { persistentID }
    }

    /// The playlists of an iTunesDB, in the order of the database, without the master playlist.
    public static func readPlaylistEntries(_ db: [UInt8]) -> [PlaylistEntry] {
        guard db.count > 12, Array(db[0..<4]) == Array("mhbd".utf8) else { return [] }
        var p = Int(le32(db, 4))
        while p + 16 <= db.count, String(decoding: db[p..<p + 4], as: UTF8.self) == "mhsd" {
            let hlen = Int(le32(db, p + 4)), total = Int(le32(db, p + 8))
            guard total > 0 else { break }
            if le32(db, p + 12) == 2 {
                return readPlaylistList(db, from: p + hlen, to: min(p + total, db.count))
            }
            p += total
        }
        return []
    }

    static func readPlaylistList(_ db: [UInt8], from start: Int, to end: Int) -> [PlaylistEntry] {
        guard start + 12 <= end, String(decoding: db[start..<start + 4], as: UTF8.self) == "mhlp" else { return [] }
        var out: [PlaylistEntry] = []
        var p = start + Int(le32(db, start + 4))
        for _ in 0..<Int(le32(db, start + 8)) {
            guard p + 21 <= end, String(decoding: db[p..<p + 4], as: UTF8.self) == "mhyp" else { break }
            let hlen = Int(le32(db, p + 4)), total = Int(le32(db, p + 8))
            guard total >= hlen, hlen > 0 else { break }
            let hidden = db[p + 20] != 0
            var name = "", ids = [UInt32]()
            var q = p + hlen
            while q + 12 <= min(p + total, end) {
                let tag = String(decoding: db[q..<q + 4], as: UTF8.self), len = Int(le32(db, q + 8))
                guard len > 0 else { break }
                if tag == "mhod", le32(db, q + 12) == 1, let text = mhodString(db, q) { name = text }
                if tag == "mhip", q + 28 <= end { ids.append(le32(db, q + 24)) }
                q += len
            }
            if !hidden {
                let pid = hlen >= 0x24 ? UInt64(le32(db, p + 0x1c)) | UInt64(le32(db, p + 0x20)) << 32 : 0
                let podcast = hlen >= 0x2c && (UInt16(db[p + 0x2a]) | UInt16(db[p + 0x2b]) << 8) != 0
                out.append(PlaylistEntry(name: name, persistentID: pid, trackIDs: ids, isPodcast: podcast))
            }
            p += total
        }
        return out
    }

    /// The text of a string mhod at `q`, or nil if it is not a string mhod.
    static func mhodString(_ db: [UInt8], _ q: Int) -> String? {
        guard q + 40 <= db.count else { return nil }
        let encoding = le32(db, q + 24)
        guard encoding == 1 || encoding == 2 else { return nil }
        let n = Int(le32(db, q + 28))
        let raw = Array(db[(q + 40)..<min(q + 40 + n, db.count)])
        return encoding == 2 ? String(decoding: raw, as: UTF8.self)
            : String(decoding: stride(from: 0, to: raw.count - 1, by: 2).map { UInt16(raw[$0]) | UInt16(raw[$0 + 1]) << 8 }, as: UTF16.self)
    }

    static func sineWAV(seconds: Int, frequency: Double) -> Data {
        let rate = 44100, frames = rate * seconds
        var w = Writer()
        w.tag("RIFF"); w.u32(UInt32(36 + frames * 4)); w.tag("WAVE")
        w.tag("fmt "); w.u32(16); w.u16(1); w.u16(2); w.u32(UInt32(rate)); w.u32(UInt32(rate * 4)); w.u16(4); w.u16(16)
        w.tag("data"); w.u32(UInt32(frames * 4))
        w.b.reserveCapacity(w.b.count + frames * 4)
        for n in 0..<frames {
            let v = UInt16(bitPattern: Int16(6000 * sin(2 * .pi * frequency * Double(n) / Double(rate))))
            w.u16(v); w.u16(v)
        }
        return Data(w.b)
    }
}
