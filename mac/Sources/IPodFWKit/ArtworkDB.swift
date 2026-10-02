import CoreGraphics
import Foundation
import ImageIO

// Swift port of src/ipodfw/artworkdb.py: the album artwork database of the iPod Video
// (iPod_Control/Artwork/ArtworkDB and the .ithmb files). RetailOS shows the artwork in Now Playing
// from these files. The layout follows libgpod (db-artwork-writer.c, db-itunes-parser.h).

public enum ArtworkDB {
    /// (format ID, width, height): the cover art formats of the iPod Video, RGB565 little-endian.
    public static let formats: [(id: UInt32, width: Int, height: Int)] = [(1028, 100, 100), (1029, 200, 200)]
    /// libgpod starts the image IDs at 0x64.
    public static let firstID: UInt32 = 100

    public struct Item {
        public var trackDBID: UInt64
        public var image: CGImage
        public var originalSize: UInt32
        public init(trackDBID: UInt64, image: CGImage, originalSize: UInt32) {
            self.trackDBID = trackDBID; self.image = image; self.originalSize = originalSize
        }
    }

    public static func ithmbName(_ format: UInt32) -> String { "F\(format)_1.ithmb" }

    static func header(_ tag: String, _ length: Int) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: length)
        h.replaceSubrange(0..<4, with: Array(tag.utf8))
        put32(&h, 4, UInt32(length))
        return h
    }

    static func closed(_ b: [UInt8]) -> [UInt8] {
        var b = b
        put32(&b, 8, UInt32(b.count))
        return b
    }

    static func stringMHOD(_ text: String) -> [UInt8] {
        let body = Array(text.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        let padding = (4 - (0x24 + body.count) % 4) % 4
        var h = header("mhod", 0x24)
        put32(&h, 4, 0x18)                         // iTunes puts the length of the short header here
        h[0x0C] = 3                                // type 3: file name
        h[0x0F] = UInt8(padding)
        put32(&h, 0x18, UInt32(body.count))
        h[0x1C] = 2                                // UTF-16
        return closed(h + body + [UInt8](repeating: 0, count: padding))
    }

    static func mhni(_ format: UInt32, _ width: Int, _ height: Int, offset: Int) -> [UInt8] {
        var h = header("mhni", 0x4C)
        put32(&h, 0x0C, 1); put32(&h, 0x10, format); put32(&h, 0x14, UInt32(offset)); put32(&h, 0x18, UInt32(width * height * 2))
        h[0x20] = UInt8(height & 0xFF); h[0x21] = UInt8(height >> 8)
        h[0x22] = UInt8(width & 0xFF); h[0x23] = UInt8(width >> 8)
        return closed(h + stringMHOD(":" + ithmbName(format)))
    }

    static func containerMHOD(_ child: [UInt8]) -> [UInt8] {
        var h = header("mhod", 0x18)
        h[0x0C] = 2                                // type 2: location of a thumbnail
        return closed(h + child)
    }

    /// The ArtworkDB file and the .ithmb files (name -> data). The image ID of item n is firstID + n.
    public static func build(_ items: [Item]) -> (db: [UInt8], ithmb: [String: [UInt8]]) {
        var ithmb = [UInt32: [UInt8]]()
        var images = [UInt8]()
        for (n, item) in items.enumerated() {
            var mhods = [UInt8]()
            for f in formats {
                let offset = ithmb[f.id, default: []].count
                ithmb[f.id, default: []] += AlbumArt.rgb565(item.image, size: f.width)
                mhods += containerMHOD(mhni(f.id, f.width, f.height, offset: offset))
            }
            var mhii = header("mhii", 0x98)
            put32(&mhii, 0x0C, UInt32(formats.count))
            put32(&mhii, 0x10, firstID + UInt32(n))
            put32(&mhii, 0x14, UInt32(item.trackDBID & 0xFFFF_FFFF)); put32(&mhii, 0x18, UInt32(item.trackDBID >> 32))
            put32(&mhii, 0x30, item.originalSize)
            images += closed(mhii + mhods)
        }
        var mhli = header("mhli", 0x5C); put32(&mhli, 8, UInt32(items.count))
        let mhla = header("mhla", 0x5C)
        var mhlf = header("mhlf", 0x5C); put32(&mhlf, 8, UInt32(formats.count))
        var mhifs = [UInt8]()
        for f in formats {
            var mhif = header("mhif", 0x7C)
            put32(&mhif, 8, 0x7C); put32(&mhif, 0x10, f.id); put32(&mhif, 0x14, UInt32(f.width * f.height * 2))
            mhifs += mhif
        }
        func mhsd(_ index: UInt8, _ body: [UInt8]) -> [UInt8] {
            var h = header("mhsd", 0x60)
            h[0x0C] = index
            return closed(h + body)
        }
        let sections = mhsd(1, mhli + images) + mhsd(2, mhla) + mhsd(3, mhlf + mhifs)
        var mhfd = header("mhfd", 0x84)
        put32(&mhfd, 0x10, 2); put32(&mhfd, 0x14, 3); put32(&mhfd, 0x1C, firstID + UInt32(items.count))   // unknown2, children, next ID
        mhfd[0x30] = 2
        return (closed(mhfd + sections), Dictionary(uniqueKeysWithValues: formats.map { (ithmbName($0.id), ithmb[$0.id] ?? []) }))
    }

    /// The image of encoded artwork data (JPEG or PNG).
    public static func image(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
