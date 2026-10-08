import CoreGraphics
import CoreText
import Foundation

/// The cover file of the cover-flow patch: iPod_Control/iTunes/iPodFirmCoverFlow.
/// The format is in patches/cover-flow/cover_flow.c and in docs/modifications.md.
public enum CoverFlowFile {
    public static let fileName = "iPodFirmCoverFlow"
    public static let defaultSize = 128
    public static let captionWidth = 320
    public static let captionHeight = 32
    public static let headerSize = 0x20

    public struct Album {
        public var name: String
        public var artist: String
        public var cover: Data?          // JPEG or PNG; nil: the file gets a placeholder
        public init(name: String, artist: String, cover: Data?) { self.name = name; self.artist = artist; self.cover = cover }
    }

    /// The albums in the order of the Albums list of the iPod. With a sort index (mhod 52,
    /// album), the order of the index. Without it, the album names in alphabetical order.
    /// A track without an album name is not in the Albums list.
    public static func albumOrder(tracks: [ITunesDB.TrackInfo], albumIndex: [Int]?) -> [String] {
        var seen = Set<String>(), out: [String] = []
        if let index = albumIndex, index.count == tracks.count {
            for i in index where i >= 0 && i < tracks.count {
                let a = tracks[i].album
                if !a.isEmpty, seen.insert(a).inserted { out.append(a) }
            }
            return out
        }
        for t in tracks where !t.album.isEmpty && seen.insert(t.album).inserted { out.append(t.album) }
        return out.sorted { $0.compare($1, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedAscending }
    }

    /// The artist line of an album, from the tracks of the album: the album artist, else the
    /// artist. "Various Artists" if the tracks have different artists and no album artist.
    public static func artist(of list: [ITunesDB.TrackInfo]) -> String {
        if let a = list.first(where: { !$0.albumArtist.isEmpty })?.albumArtist { return a }
        let artists = Set(list.map(\.artist).filter { !$0.isEmpty })
        if artists.count > 1 { return "Various Artists" }
        return artists.first ?? ""
    }

    /// FNV-1a hash of the UTF-8 album name (the same as the thumbnail file).
    public static func hash(_ name: String) -> UInt32 { AlbumArt.fnv1a(name) }

    public static func recordSize(size: Int) -> Int { size * size * 2 + captionWidth * captionHeight / 2 }

    /// The whole file. The patch reads the albums in this order.
    public static func build(_ albums: [Album], size: Int = defaultSize) -> [UInt8] {
        var body = [UInt8]()
        let record = recordSize(size: size)
        body.reserveCapacity(albums.count * (4 + record))
        func u32(_ v: UInt32, _ out: inout [UInt8]) { for i in 0..<4 { out.append(UInt8(v >> (8 * UInt32(i)) & 0xFF)) } }
        for a in albums { u32(hash(a.name), &body) }
        for a in albums {
            let img = a.cover.flatMap(ArtworkDB.image) ?? placeholder(name: a.name)
            body += AlbumArt.rgb565(img, size: size)
            body += caption(album: a.name, artist: a.artist)
        }
        var stamp: UInt32 = 2_166_136_261
        for b in body { stamp = (stamp ^ UInt32(b)) &* 16_777_619 }
        var out = [UInt8](Array("IFCF".utf8))
        out += [1, 0, UInt8(size & 0xFF), UInt8(size >> 8)]
        u32(UInt32(albums.count), &out)
        u32(stamp, &out)
        out += [UInt8(captionWidth & 0xFF), UInt8(captionWidth >> 8), UInt8(captionHeight), 0]
        u32(UInt32(record), &out)
        u32(UInt32(headerSize + 4 * albums.count), &out)
        u32(0, &out)
        return out + body
    }

    /// A grey square with a music note, for an album without a cover.
    static func placeholder(name: String) -> CGImage {
        let side = 128
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.22, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(CGColor(gray: 0.30, alpha: 1))
        ctx.fill(CGRect(x: 6, y: 6, width: side - 12, height: side - 12))
        let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
        let text = NSAttributedString(string: "\u{266B}", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.62, alpha: 1)])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(side) - bounds.width) / 2 - bounds.minX,
                                   y: (CGFloat(side) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    /// The caption: the album name (bold, white) and the artist (grey), centred, as 4-bit grey
    /// levels, two pixels in each byte (the left pixel in the high bits).
    public static func caption(album: String, artist: String) -> [UInt8] {
        let w = captionWidth, h = captionHeight
        var grey = [UInt8](repeating: 0, count: w * h)
        grey.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setShouldSmoothFonts(false)
            func draw(_ s: String, font: CTFont, grey level: CGFloat, baseline: CGFloat) {
                guard !s.isEmpty else { return }
                let attr = NSAttributedString(string: s, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: level, alpha: 1)])
                let full = CTLineCreateWithAttributedString(attr)
                let dots = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: level, alpha: 1)]))
                let line = CTLineCreateTruncatedLine(full, Double(w - 16), .end, dots) ?? full
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                ctx.textPosition = CGPoint(x: (CGFloat(w) - CGFloat(width)) / 2, y: baseline)
                CTLineDraw(line, ctx)
            }
            // CoreGraphics has y up: the album line is at the top.
            draw(album, font: CTFontCreateWithName("Helvetica-Bold" as CFString, 14, nil), grey: 1, baseline: 19)
            draw(artist, font: CTFontCreateWithName("Helvetica" as CFString, 12, nil), grey: 0.68, baseline: 4)
        }
        var out = [UInt8](repeating: 0, count: w * h / 2)
        for i in 0..<out.count {
            let a = UInt8((UInt16(grey[2 * i]) * 15 + 127) / 255), b = UInt8((UInt16(grey[2 * i + 1]) * 15 + 127) / 255)
            out[i] = a << 4 | b
        }
        return out
    }
}
