import CoreGraphics
import Foundation
import ImageIO

// Swift port of src/ipodfw/albumart.py and src/ipodfw/mp4tags.py:
// the album thumbnail file for the album-art patch, and a reader for MP4 tags and cover art.

public enum AlbumArt {
    public static let fileName = "iPodFirmAlbumArt"
    public static let defaultSize = 20
    /// The folder on the iPod (in iPod_Control/iTunes) for the custom playlist images.
    public static let playlistArtFolder = "iPodFirmPlaylistArt"

    /// The name in the thumbnail file for a playlist. The patch hashes the byte 0x01 and the name
    /// for a playlist row, thus a playlist and an album with the same name have different thumbnails.
    public static func playlistKey(_ name: String) -> String { "\u{1}" + name }

    public static func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return h
    }

    /// RGB565 little-endian pixels of the centre square of `image`, scaled to `size`.
    public static func rgb565(_ image: CGImage, size: Int) -> [UInt8] {
        let side = min(image.width, image.height)
        let crop = image.cropping(to: CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)) ?? image
        var buf = [UInt8](repeating: 0, count: size * size * 4)
        let ctx = CGContext(data: &buf, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: size, height: size))
        var out = [UInt8]()
        out.reserveCapacity(size * size * 2)
        for i in stride(from: 0, to: buf.count, by: 4) {
            let v = UInt16(buf[i] >> 3) << 11 | UInt16(buf[i + 1] >> 2) << 5 | UInt16(buf[i + 2] >> 3)
            out += [UInt8(v & 0xFF), UInt8(v >> 8)]
        }
        return out
    }

    /// `albums` maps the album name (as the iPod shows it) or the `playlistKey` of a playlist to the
    /// encoded image data (JPEG or PNG).
    public static func build(_ albums: [String: Data], size: Int = defaultSize) -> [UInt8] {
        var entries = [UInt32: [UInt8]]()
        for (name, data) in albums {
            let h = fnv1a(name)
            guard entries[h] == nil, let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            entries[h] = rgb565(img, size: size)
        }
        let hashes = entries.keys.sorted()
        var out = [UInt8](Array("IFAT".utf8))
        func u16(_ v: Int) { out += [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: UInt32) { for i in 0..<4 { out.append(UInt8(v >> (8 * UInt32(i)) & 0xFF)) } }
        let dataStart = 16 + 8 * hashes.count
        var table = [UInt8]()
        for (i, h) in hashes.enumerated() {
            for v in [h, UInt32(dataStart + i * size * size * 2)] { for k in 0..<4 { table.append(UInt8(v >> (8 * UInt32(k)) & 0xFF)) } }
        }
        let body = table + hashes.flatMap { entries[$0]! }
        // The stamp is the FNV-1a hash of the entry table and the thumbnails. The patch reads the
        // file again when it changes.
        var stamp: UInt32 = 2_166_136_261
        for b in body { stamp = (stamp ^ UInt32(b)) &* 16_777_619 }
        u16(1); u16(size); u32(UInt32(hashes.count)); u32(stamp)
        out += body
        return out
    }
}

public struct MP4Tags {
    public var title = "", artist = "", albumArtist = "", album = "", genre = ""
    public var year = 0, track = 0, tracks = 0, disc = 0, lengthMS = 0
    public var cover: Data?

    /// Read the iTunes tags and the cover of an MP4/M4A file. The file is only read.
    /// The top-level atoms are found with small reads; then the "moov" atom is read into memory once.
    public static func read(_ url: URL) throws -> MP4Tags {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let size = Int(try fh.seekToEnd())
        var moov: [UInt8]?
        var pos = 0
        while pos + 8 <= size {
            try fh.seek(toOffset: UInt64(pos))
            let h = [UInt8](try fh.read(upToCount: 16) ?? Data())
            guard h.count >= 8 else { break }
            var len = Int(be32(h, 0)), hlen = 8
            if len == 1, h.count >= 16 { len = Int(UInt64(be32(h, 8)) << 32 | UInt64(be32(h, 12))); hlen = 16 }
            if len == 0 { len = size - pos }
            if len < hlen { break }
            if h[4] == 0x6D, h[5] == 0x6F, h[6] == 0x6F, h[7] == 0x76 {          // "moov"
                try fh.seek(toOffset: UInt64(pos + hlen))
                moov = [UInt8](try fh.read(upToCount: len - hlen) ?? Data())
                break
            }
            pos += len
        }
        guard let m = moov else { return MP4Tags() }
        return parse(moov: m)
    }

    /// Parse the body of a "moov" atom.
    static func parse(moov m: [UInt8]) -> MP4Tags {
        func atoms(_ start: Int, _ end: Int) -> [(String, Int, Int)] {
            var out: [(String, Int, Int)] = []
            var pos = start
            while pos + 8 <= end {
                var len = Int(be32(m, pos)), hlen = 8
                if len == 1, pos + 16 <= end { len = Int(UInt64(be32(m, pos + 8)) << 32 | UInt64(be32(m, pos + 12))); hlen = 16 }
                if len == 0 { len = end - pos }
                if len < hlen || pos + len > end { break }
                // Latin-1: tag names such as "\u{A9}nam" start with the byte 0xA9, which is not valid UTF-8.
                out.append((String(bytes: m[pos + 4..<pos + 8], encoding: .isoLatin1) ?? "", pos + hlen, pos + len))
                pos += len
            }
            return out
        }
        func find(_ start: Int, _ end: Int, _ path: [String]) -> (Int, Int)? {
            for (kind, body, stop) in atoms(start, end) where kind == path[0] {
                if path.count == 1 { return (body, stop) }
                if let r = find(kind == "meta" ? body + 4 : body, stop, Array(path.dropFirst())) { return r }
            }
            return nil
        }
        var t = MP4Tags()
        if let (body, stop) = find(0, m.count, ["mvhd"]), stop - body >= 32 {
            let isV0 = m[body] == 0
            let o = body + (isV0 ? 12 : 20)
            let scale = Int(be32(m, o))
            let dur = isV0 ? Int(be32(m, o + 4)) : Int(UInt64(be32(m, o + 4)) << 32 | UInt64(be32(m, o + 8)))
            if scale > 0 { t.lengthMS = dur * 1000 / scale }
        }
        guard let ilst = find(0, m.count, ["udta", "meta", "ilst"]) else { return t }
        for (kind, body, stop) in atoms(ilst.0, ilst.1) {
            guard let d = find(body, stop, ["data"]), d.1 - d.0 > 8 else { continue }
            if kind == "covr" {
                if t.cover == nil { t.cover = Data(m[(d.0 + 8)..<d.1]) }
                continue
            }
            let value = Array(m[(d.0 + 8)..<d.1])
            let text = String(decoding: value, as: UTF8.self)
            switch kind {
            case "\u{A9}nam": t.title = text
            case "\u{A9}ART": t.artist = text
            case "aART": t.albumArtist = text
            case "\u{A9}alb": t.album = text
            case "\u{A9}gen": t.genre = text
            case "\u{A9}day": t.year = Int(text.prefix(4)) ?? 0
            case "trkn" where value.count >= 6: t.track = Int(be16(value, 2)); t.tracks = Int(be16(value, 4))
            case "disk" where value.count >= 4: t.disc = Int(be16(value, 2))
            default: break
            }
        }
        return t
    }

    static func be16(_ d: [UInt8], _ o: Int) -> UInt16 { UInt16(d[o]) << 8 | UInt16(d[o + 1]) }
}
