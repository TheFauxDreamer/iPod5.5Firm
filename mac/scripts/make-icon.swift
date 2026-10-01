// Draws the app icon (an iPod Video front) into an .iconset folder.
// usage: swift make-icon.swift OUT.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // body
    let body = CGRect(x: s * 0.2, y: s * 0.06, width: s * 0.6, height: s * 0.88)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: s * 0.09, cornerHeight: s * 0.09, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor(white: 0.13, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(white: 0.24, alpha: 1).cgColor, NSColor(white: 0.08, alpha: 1).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    // screen
    let screen = CGRect(x: body.minX + s * 0.06, y: body.maxY - s * 0.43, width: body.width - s * 0.12, height: s * 0.36)
    let screenPath = CGPath(roundedRect: screen, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil)
    let sg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(calibratedRed: 0.36, green: 0.66, blue: 1, alpha: 1).cgColor,
                                 NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.85, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.saveGState(); ctx.addPath(screenPath); ctx.clip()
    ctx.drawLinearGradient(sg, start: CGPoint(x: screen.minX, y: screen.maxY), end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
    // menu rows
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    for i in 0..<4 {
        let y = screen.maxY - s * 0.075 - CGFloat(i) * s * 0.07
        ctx.fill(CGRect(x: screen.minX + s * 0.03, y: y, width: screen.width * (i == 0 ? 0.6 : 0.45), height: s * 0.022))
    }
    ctx.restoreGState()

    // click wheel
    let c = CGPoint(x: s / 2, y: body.minY + s * 0.22)
    let r = s * 0.17
    ctx.setFillColor(NSColor(white: 0.32, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ctx.setFillColor(NSColor(white: 0.14, alpha: 1).cgColor)
    let r2 = r * 0.38
    ctx.fillEllipse(in: CGRect(x: c.x - r2, y: c.y - r2, width: r2 * 2, height: r2 * 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
