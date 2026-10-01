import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Swift port of src/ipodfw/pictures.py (iPodWizard Picture.cpp, header type 2).

public struct PictureError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Picture: Equatable {
    public var pos: Int
    public var textureFormat: UInt16
    public var bytesPerRow: Int
    public var depth: Int
    public var width: Int
    public var height: Int

    public var dataPos: Int { pos + 28 }
    public var hasAlpha: Bool { depth == 16 && textureFormat == 0x1444 }
    public var isGrey: Bool { depth != 16 }
    public var formatName: String {
        if depth == 16 { return textureFormat == 0x1444 ? "ARGB4444" : textureFormat == 0x2565 ? "RGB565-BE" : "RGB565" }
        return "grey\(depth)"
    }

    public static func parse(_ d: [UInt8], at pos: Int) -> Picture? {
        guard pos + 28 <= d.count else { return nil }
        let tf = le16(d, pos), bpr = Int(le16(d, pos + 4)), depth = Int(le16(d, pos + 6))
        let h = Int(le32(d, pos + 16)), w = Int(le32(d, pos + 20)), blockLen = Int(le32(d, pos + 24))
        guard tf != 0, d[pos + 8..<pos + 16].allSatisfy({ $0 == 0 }), (1...1024).contains(w), (1...1024).contains(h),
              [1, 2, 4, 16].contains(depth), bpr * 8 >= w * depth, blockLen >= bpr * h,
              pos + 28 + blockLen <= d.count else { return nil }
        return Picture(pos: pos, textureFormat: tf, bytesPerRow: bpr, depth: depth, width: w, height: h)
    }

    /// Non-premultiplied RGBA8, width*height*4 bytes.
    public func decode(_ d: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = pixel(d, x, y)
                let o = (y * width + x) * 4
                out[o] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = a
            }
        }
        return out
    }

    func pixel(_ d: [UInt8], _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let row = dataPos + y * bytesPerRow
        if depth == 16 {
            let v = textureFormat == 0x2565 ? UInt16(d[row + 2 * x]) << 8 | UInt16(d[row + 2 * x + 1]) : le16(d, row + 2 * x)
            if textureFormat == 0x1444 {
                return (UInt8((v >> 8) & 15) * 17, UInt8((v >> 4) & 15) * 17, UInt8(v & 15) * 17, UInt8((v >> 12) & 15) * 17)
            }
            let r = UInt8((v >> 11) & 31), g = UInt8((v >> 5) & 63), b = UInt8(v & 31)
            return (r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2, 255)
        }
        let perByte = 8 / depth, maxv = (1 << depth) - 1
        let shift = (perByte - 1 - x % perByte) * depth
        let level = (Int(d[row + x / perByte]) >> shift) & maxv
        let grey = UInt8((maxv - level) * 255 / maxv)
        return (grey, grey, grey, 255)
    }

    /// Write RGBA8 pixels into the picture. Pixels that look identical to the current ones keep
    /// their original bytes, so an unchanged image is byte-identical. Returns true if anything changed.
    @discardableResult
    public func encode(_ d: inout [UInt8], rgba: [UInt8]) throws -> Bool {
        guard rgba.count == width * height * 4 else {
            throw PictureError("Image must be \(width)×\(height) pixels to replace this picture.")
        }
        let before = Array(d[dataPos..<dataPos + bytesPerRow * height])
        for y in 0..<height {
            let row = dataPos + y * bytesPerRow
            for x in 0..<width {
                let o = (y * width + x) * 4
                let r = Int(rgba[o]), g = Int(rgba[o + 1]), b = Int(rgba[o + 2]), a = Int(rgba[o + 3])
                if depth == 16 {
                    let v: UInt16
                    if textureFormat == 0x1444 {
                        let cur = pixel(d, x, y)
                        if a >> 4 == 0 && cur.3 == 0 { continue }       // both fully transparent
                        v = UInt16(a >> 4) << 12 | UInt16(r >> 4) << 8 | UInt16(g >> 4) << 4 | UInt16(b >> 4)
                    } else {
                        v = UInt16(r >> 3) << 11 | UInt16(g >> 2) << 5 | UInt16(b >> 3)
                    }
                    if textureFormat == 0x2565 {
                        d[row + 2 * x] = UInt8(v >> 8); d[row + 2 * x + 1] = UInt8(v & 0xFF)
                    } else {
                        d[row + 2 * x] = UInt8(v & 0xFF); d[row + 2 * x + 1] = UInt8(v >> 8)
                    }
                } else {
                    let perByte = 8 / depth, maxv = (1 << depth) - 1
                    let shift = (perByte - 1 - x % perByte) * depth
                    let grey = (r * 299 + g * 587 + b * 114 + 500) / 1000
                    let level = maxv - (grey * maxv + 127) / 255
                    let i = row + x / perByte
                    d[i] = UInt8((Int(d[i]) & ~(maxv << shift) & 0xFF) | (level << shift))
                }
            }
        }
        return Array(d[dataPos..<dataPos + bytesPerRow * height]) != before
    }
}

public struct PictureItem: Identifiable, Equatable {
    public var id: Int { index }
    public var index: Int
    public var resourceID: Int16
    public var picture: Picture
}

public enum Pictures {
    public static func list(_ osos: [UInt8], _ block: ResourceBlock) -> [PictureItem] {
        block.ofType("BMap").enumerated().compactMap { n, r in
            Picture.parse(osos, at: block.abs(r)).map { PictureItem(index: n, resourceID: r.id, picture: $0) }
        }
    }
}

// MARK: - PNG <-> RGBA

public enum ImageCodec {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func cgImage(rgba: [UInt8], width: Int, height: Int, grey: Bool = false, alpha: Bool = true) -> CGImage? {
        if grey {
            let g = stride(from: 0, to: rgba.count, by: 4).map { rgba[$0] }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                           provider: CGDataProvider(data: Data(g) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        let info = alpha ? CGImageAlphaInfo.last : CGImageAlphaInfo.noneSkipLast
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: srgb, bitmapInfo: CGBitmapInfo(rawValue: info.rawValue),
                       provider: CGDataProvider(data: Data(rgba) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    public static func png(for item: Picture, osos: [UInt8]) -> Data? {
        cgImage(rgba: item.decode(osos), width: item.width, height: item.height, grey: item.isGrey, alpha: item.hasAlpha).flatMap(pngData)
    }

    public static func load(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw PictureError("Could not read an image from \(url.lastPathComponent).")
        }
        return img
    }

    /// Non-premultiplied RGBA8 pixels of any CGImage.
    public static func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        // Fast path: exact bytes for the 8-bit formats this app writes.
        if image.bitsPerComponent == 8, let data = image.dataProvider?.data as Data? {
            let src = [UInt8](data), bpr = image.bytesPerRow
            let alphaInfo = image.alphaInfo, order = image.bitmapInfo.intersection(.byteOrderMask)
            let defaultOrder = order == [] || order == .byteOrder32Big
            if image.bitsPerPixel == 8, image.colorSpace?.model == .monochrome, alphaInfo == .none {
                var out = [UInt8](repeating: 255, count: w * h * 4)
                for y in 0..<h { for x in 0..<w { let v = src[y * bpr + x]; let o = (y * w + x) * 4; out[o] = v; out[o + 1] = v; out[o + 2] = v } }
                return out
            }
            if image.colorSpace?.model == .rgb, defaultOrder,
               (image.bitsPerPixel == 32 && [.last, .noneSkipLast].contains(alphaInfo)) || (image.bitsPerPixel == 24 && alphaInfo == .none) {
                let n = image.bitsPerPixel / 8
                var out = [UInt8](repeating: 255, count: w * h * 4)
                for y in 0..<h {
                    for x in 0..<w {
                        let s = y * bpr + x * n, o = (y * w + x) * 4
                        out[o] = src[s]; out[o + 1] = src[s + 1]; out[o + 2] = src[s + 2]
                        if alphaInfo == .last { out[o + 3] = src[s + 3] }
                    }
                }
                return out
            }
        }
        // General path: draw into a premultiplied sRGB context and un-premultiply.
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 0, to: buf.count, by: 4) where buf[i + 3] != 0 && buf[i + 3] != 255 {
            let a = Int(buf[i + 3])
            for c in 0..<3 { buf[i + c] = UInt8(min(255, (Int(buf[i + c]) * 255 + a / 2) / a)) }
        }
        return buf
    }
}
