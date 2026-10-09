import AVFoundation
import CoreGraphics
import Foundation

/// Makes a music library for the emulator from a folder of music files (the files are only read),
/// and writes the album thumbnail file for a real iPod.
public enum MusicImport {
    public struct Song { public var url: URL; public var tags: MP4Tags }

    public static func scan(_ folder: URL) -> [Song] {
        var out: [Song] = []
        let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = e?.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            guard ext == "m4a" || ext == "mp4", !url.lastPathComponent.hasPrefix("._"),
                  let tags = try? MP4Tags.read(url) else { continue }
            out.append(Song(url: url, tags: tags))
        }
        return out.sorted { $0.url.path < $1.url.path }
    }

    /// Up to `limit` songs, a maximum of `perAlbum` from each album, one album of each artist in turn.
    public static func pick(_ songs: [Song], limit: Int, perAlbum: Int) -> [Song] {
        var albums = [String: [Song]]()
        for s in songs {
            let artist = s.tags.albumArtist.isEmpty ? s.tags.artist : s.tags.albumArtist
            albums["\(artist)\u{1}\(s.tags.album)", default: []].append(s)
        }
        var byArtist = [String: [[Song]]]()
        for key in albums.keys.sorted() {
            let artist = String(key.split(separator: "\u{1}", omittingEmptySubsequences: false)[0])
            let list = albums[key]!.sorted { ($0.tags.disc, $0.tags.track) < ($1.tags.disc, $1.tags.track) }
            byArtist[artist, default: []].append(Array(list.prefix(perAlbum)))
        }
        var chosen: [Song] = []
        while chosen.count < limit, byArtist.values.contains(where: { !$0.isEmpty }) {
            for artist in byArtist.keys.sorted() where !byArtist[artist]!.isEmpty && chosen.count < limit {
                chosen += byArtist[artist]!.removeFirst().prefix(limit - chosen.count)
            }
        }
        return chosen
    }

    /// Write iPod_Control (iTunesDB, ArtworkDB, album thumbnails and, if `copyAudio`, the music files) under `out`.
    @discardableResult
    public static func makeLibrary(from songs: [Song], to out: URL, copyAudio: Bool) throws -> (tracks: Int, albums: Int) {
        let fm = FileManager.default
        let itunes = out.appendingPathComponent("iPod_Control/iTunes")
        try fm.createDirectory(at: itunes, withIntermediateDirectories: true)
        var tracks: [DBTrack] = []
        var covers = [String: Data]()
        var art: [(track: Int, item: ArtworkDB.Item)] = []
        var decoded = [Data: CGImage]()
        for (n, s) in songs.enumerated() {
            let t = s.tags
            let album = t.album.isEmpty ? "Unknown Album" : t.album
            let folder = String(format: "F%02d", n % 50), name = String(format: "T%05d.%@", n, s.url.pathExtension.lowercased())
            if copyAudio {
                let dir = out.appendingPathComponent("iPod_Control/Music/\(folder)")
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent(name)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: s.url, to: dest)
            }
            let size = (try? fm.attributesOfItem(atPath: s.url.path)[.size] as? NSNumber)?.uint32Value ?? 0
            tracks.append(DBTrack(title: t.title.isEmpty ? s.url.deletingPathExtension().lastPathComponent : t.title,
                                  artist: t.artist.isEmpty ? "Unknown Artist" : t.artist, album: album,
                                  path: ":iPod_Control:Music:\(folder):\(name)", size: size, lengthMS: UInt32(t.lengthMS),
                                  trackNumber: UInt32(t.track), trackCount: UInt32(t.tracks), year: UInt32(t.year),
                                  genre: t.genre, albumArtist: t.albumArtist, disc: UInt32(t.disc)))
            tracks[n].dbid = 0x1000_0000_0000 + UInt64(n)
            if let c = t.cover {
                if decoded[c] == nil, let img = ArtworkDB.image(c) { decoded[c] = img }
                if let img = decoded[c] {
                    art.append((n, ArtworkDB.Item(trackDBID: tracks[n].dbid, image: img, originalSize: UInt32(c.count))))
                    if covers[album] == nil { covers[album] = c }
                }
            }
        }
        let (artworkDB, ithmb) = ArtworkDB.build(art.map(\.item))
        for (i, a) in art.enumerated() {
            tracks[a.track].imageID = ArtworkDB.firstID + UInt32(i)
            tracks[a.track].artworkSize = a.item.originalSize
        }
        try Data(ITunesDB.build(tracks)).write(to: itunes.appendingPathComponent("iTunesDB"))
        let artwork = out.appendingPathComponent("iPod_Control/Artwork")
        try fm.createDirectory(at: artwork, withIntermediateDirectories: true)
        try Data(artworkDB).write(to: artwork.appendingPathComponent("ArtworkDB"))
        for (name, data) in ithmb { try Data(data).write(to: artwork.appendingPathComponent(name)) }
        try Data(AlbumArt.build(covers)).write(to: itunes.appendingPathComponent(AlbumArt.fileName))
        return (tracks.count, Set(tracks.map(\.album)).count)
    }

    /// Cover art of any audio file: MP4 tags first, then AVFoundation (for MP3 and other formats).
    static func cover(_ url: URL) -> Data? {
        if ["m4a", "mp4", "m4b", "m4p"].contains(url.pathExtension.lowercased()), let c = try? MP4Tags.read(url).cover { return c }
        let asset = AVURLAsset(url: url)
        let item = AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: .commonIdentifierArtwork).first
        return item?.dataValue
    }

    /// Write iPod_Control/iTunes/iPodFirmAlbumArt on a mounted iPod, from its own database and music files.
    /// A playlist gets its custom image (see `setPlaylistArt`), or a collage of the covers of its albums.
    public static func writeThumbnails(volume: URL, progress: ((Int, Int) -> Void)? = nil) throws
        -> (albums: Int, covers: Int, playlists: Int, playlistArt: Int) {
        let itunes = volume.appendingPathComponent("iPod_Control/iTunes")
        let db = [UInt8](try Data(contentsOf: itunes.appendingPathComponent("iTunesDB")))
        let tracks = ITunesDB.readTrackRecords(db)
        guard !tracks.isEmpty else { throw FirmwareError("The iPod music database has no tracks, or iPodFirm cannot read it.") }
        var firstFile = [String: [String]]()
        for t in tracks where !t.album.isEmpty { firstFile[t.album, default: []].append(t.path) }
        var covers = [String: Data]()
        let albums = firstFile.keys.sorted()
        for (i, album) in albums.enumerated() {
            progress?(i, albums.count)
            for path in firstFile[album]!.prefix(3) {
                let rel = path.split(separator: ":").joined(separator: "/")
                if let c = cover(volume.appendingPathComponent(rel)) { covers[album] = c; break }
            }
        }
        let art = playlistArt(volume: volume, db: db, tracks: tracks, albumCovers: covers)
        var entries = covers
        for (name, data) in art { entries[AlbumArt.playlistKey(name)] = data }
        try Data(AlbumArt.build(entries)).write(to: itunes.appendingPathComponent(AlbumArt.fileName), options: .atomic)
        return (albums.count, covers.count, ITunesDB.readPlaylists(db).count, art.count)
    }

    // MARK: playlist artwork

    /// A playlist on the iPod and the image that its row shows.
    public struct PlaylistArt: Identifiable {
        public var name: String
        public var isCustom: Bool
        public var image: Data?          // PNG or JPEG; nil: no custom image and no album covers
        public var id: String { name }
    }

    /// The playlists of the iPod at `volume`, each with its custom image or its automatic collage.
    public static func playlists(volume: URL) throws -> [PlaylistArt] {
        let db = [UInt8](try Data(contentsOf: volume.appendingPathComponent("iPod_Control/iTunes/iTunesDB")))
        let tracks = ITunesDB.readTrackRecords(db)
        let art = playlistArt(volume: volume, db: db, tracks: tracks, albumCovers: [:]) { path in
            cover(volume.appendingPathComponent(path.split(separator: ":").joined(separator: "/")))
        }
        return ITunesDB.readPlaylists(db).map { p in
            PlaylistArt(name: p.name, isCustom: customPlaylistArt(volume: volume, name: p.name) != nil, image: art[p.name])
        }
    }

    /// The image for each playlist: the custom image, or a collage of the first four album covers.
    /// `albumCovers` maps an album name to its cover. `loadCover` reads the cover of a track file
    /// (iPod path with colons) for an album that is not in `albumCovers`.
    static func playlistArt(volume: URL, db: [UInt8], tracks: [(id: UInt32, album: String, path: String)],
                            albumCovers: [String: Data], loadCover: ((String) -> Data?)? = nil) -> [String: Data] {
        var byID = [UInt32: (album: String, path: String)]()
        for t in tracks { byID[t.id] = (t.album, t.path) }
        var out = [String: Data]()
        for p in ITunesDB.readPlaylists(db) where !p.name.isEmpty && out[p.name] == nil {
            if let custom = customPlaylistArt(volume: volume, name: p.name) {
                out[p.name] = custom
                continue
            }
            var seen = Set<String>(), images = [Data]()
            for id in p.trackIDs {
                guard images.count < 4, let t = byID[id], !t.album.isEmpty, !seen.contains(t.album) else { continue }
                if let c = albumCovers[t.album] ?? loadCover?(t.path) {
                    seen.insert(t.album)
                    images.append(c)
                }
            }
            if let c = collage(images) { out[p.name] = c }
        }
        return out
    }

    /// A 2×2 PNG from the first four images. With fewer than four images, the first image.
    public static func collage(_ images: [Data], side: Int = 200) -> Data? {
        guard let first = images.first else { return nil }
        guard images.count >= 4 else { return first }
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &buf, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return first }
        ctx.interpolationQuality = .high
        let half = CGFloat(side) / 2
        for (i, data) in images.prefix(4).enumerated() {
            guard let img = ArtworkDB.image(data) else { continue }
            let s = min(img.width, img.height)
            let square = img.cropping(to: CGRect(x: (img.width - s) / 2, y: (img.height - s) / 2, width: s, height: s)) ?? img
            // CoreGraphics has y up: images 0 and 1 go in the top row.
            ctx.draw(square, in: CGRect(x: CGFloat(i % 2) * half, y: CGFloat(1 - i / 2) * half, width: half, height: half))
        }
        return ctx.makeImage().flatMap(ImageCodec.pngData) ?? first
    }

    static func playlistArtURL(volume: URL, name: String) -> URL {
        volume.appendingPathComponent("iPod_Control/iTunes/\(AlbumArt.playlistArtFolder)")
            .appendingPathComponent(String(format: "%08x.png", AlbumArt.fnv1a(name)))
    }

    /// The custom image of a playlist on the iPod, or nil.
    public static func customPlaylistArt(volume: URL, name: String) -> Data? {
        try? Data(contentsOf: playlistArtURL(volume: volume, name: name))
    }

    /// Keep `image` (any image file) as the custom image of a playlist on the iPod. iPodFirm keeps
    /// the centre square, at a maximum of 200 × 200 pixels.
    public static func setPlaylistArt(volume: URL, name: String, image: URL) throws {
        let img = try ImageCodec.load(image)
        let s = min(img.width, img.height), side = min(s, 200)
        let square = img.cropping(to: CGRect(x: (img.width - s) / 2, y: (img.height - s) / 2, width: s, height: s)) ?? img
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &buf, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              side > 0 else { throw FirmwareError("iPodFirm cannot read the image \(image.lastPathComponent).") }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))     // a transparent image gets a white background
        ctx.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let png = ctx.makeImage().flatMap(ImageCodec.pngData) else {
            throw FirmwareError("iPodFirm cannot read the image \(image.lastPathComponent).")
        }
        let url = playlistArtURL(volume: volume, name: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
    }

    /// Remove the custom image of a playlist. The playlist then gets the automatic collage.
    public static func removePlaylistArt(volume: URL, name: String) throws {
        let url = playlistArtURL(volume: volume, name: name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

/// Corrections for drives that the emulator's `ipod-boot make-disk` builds (see src/ipodfw/emudrive.py).
public enum EmulatorDrive {
    /// `make-disk` makes the osos length 0x600 bytes shorter. Set the full length and the checksum again.
    @discardableResult
    public static func fixOSOSLength(drive: URL, ososLength: Int) throws -> Bool {
        let fh = try FileHandle(forUpdating: drive)
        defer { try? fh.close() }
        let mbr = [UInt8](try fh.read(upToCount: 512) ?? Data())
        guard mbr.count == 512, mbr[510] == 0x55, mbr[511] == 0xAA else { throw FirmwareError("The emulator drive has no MBR.") }
        let start = UInt64(le32(mbr, 0x1BE + 8)) * 512
        try fh.seek(toOffset: start)
        var head = [UInt8](try fh.read(upToCount: 0x5000) ?? Data())
        let dir = Int(le32(head, 0x104)) + 0x200
        for k in 0..<10 {
            let p = dir + 40 * k
            guard p + 40 <= head.count, Array(head[p + 4..<p + 8]) == Array("soso".utf8) else { continue }
            let devOffset = UInt64(le32(head, p + 12)), length = Int(le32(head, p + 16))
            if length >= ososLength { return false }
            try fh.seek(toOffset: start + 0x200 + devOffset)
            let data = [UInt8](try fh.read(upToCount: ososLength) ?? Data())
            put32(&head, p + 16, UInt32(ososLength))
            put32(&head, p + 28, byteSum(data))
            try fh.seek(toOffset: start + UInt64(p))
            try fh.write(contentsOf: Data(head[p..<p + 40]))
            return true
        }
        throw FirmwareError("The emulator drive has no osos entry.")
    }
}
