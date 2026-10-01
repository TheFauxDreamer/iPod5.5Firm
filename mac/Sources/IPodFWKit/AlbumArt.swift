import CoreGraphics
import Foundation
import ImageIO

// Swift port of src/ipodfw/albumart.py and src/ipodfw/mp4tags.py:
// the album thumbnail file for the album-art patch, and a reader for MP4 tags and cover art.

public enum AlbumArt {
    public static let fileName = "iPodFirmAlbumArt"
    public static let defaultSize = 20

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

    /// `albums` maps the album name (as the iPod shows it) to the encoded image data (JPEG or PNG).
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
        u16(1); u16(size); u32(UInt32(hashes.count)); u32(0)
        let dataStart = 16 + 8 * hashes.count
        for (i, h) in hashes.enumerated() { u32(h); u32(UInt32(dataStart + i * size * size * 2)) }
        for h in hashes { out += entries[h]! }
        return out
    }
}

public struct MP4Tags {
    public var title = "", artist = "", albumArtist = "", album = "", genre = ""
    public var year = 0, track = 0, tracks = 0, disc = 0, lengthMS = 0
    public var cover: Data?

    /// Read the iTunes tags and the cover of an MP4/M4A file. The file is only read.
    public static func read(_ url: URL) throws -> MP4Tags {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let size = Int(try fh.seekToEnd())
        func bytes(_ at: Int, _ n: Int) throws -> [UInt8] {
            try fh.seek(toOffset: UInt64(at))
            return [UInt8](try fh.read(upToCount: n) ?? Data())
        }
        func atoms(_ start: Int, _ end: Int) throws -> [(String, Int, Int)] {
            var out: [(String, Int, Int)] = []
            var pos = start
            while pos + 8 <= end {
                let h = try bytes(pos, 16)
                guard h.count >= 8 else { break }
                var len = Int(be32(h, 0)), hlen = 8
                let kind = String(decoding: h[4..<8], as: UTF8.self)
                if len == 1, h.count >= 16 { len = Int(UInt64(be32(h, 8)) << 32 | UInt64(be32(h, 12))); hlen = 16 }
                if len == 0 { len = end - pos }
                if len < hlen { break }
                out.append((kind, pos + hlen, pos + len))
                pos += len
            }
            return out
        }
        func find(_ start: Int, _ end: Int, _ path: [String]) throws -> (Int, Int)? {
            for (kind, body, stop) in try atoms(start, end) where kind == path[0] {
                if path.count == 1 { return (body, stop) }
                if let r = try find(kind == "meta" ? body + 4 : body, stop, Array(path.dropFirst())) { return r }
            }
            return nil
        }
        var t = MP4Tags()
        if let (body, _) = try find(0, size, ["moov", "mvhd"]) {
            let v = try bytes(body, 1)
            let isV0 = v.first == 0
            let b = try bytes(body + (isV0 ? 12 : 20), 12)
            if b.count >= 12 {
                let scale = Int(be32(b, 0))
                let dur = isV0 ? Int(be32(b, 4)) : Int(UInt64(be32(b, 4)) << 32 | UInt64(be32(b, 8)))
                if scale > 0 { t.lengthMS = dur * 1000 / scale }
            }
        }
        guard let ilst = try find(0, size, ["moov", "udta", "meta", "ilst"]) else { return t }
        for (kind, body, stop) in try atoms(ilst.0, ilst.1) {
            guard let d = try find(body, stop, ["data"]), d.1 - d.0 > 8 else { continue }
            let value = try bytes(d.0 + 8, d.1 - d.0 - 8)
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
            case "covr" where t.cover == nil: t.cover = Data(value)
            default: break
            }
        }
        return t
    }

    static func be16(_ d: [UInt8], _ o: Int) -> UInt16 { UInt16(d[o]) << 8 | UInt16(d[o + 1]) }
}
