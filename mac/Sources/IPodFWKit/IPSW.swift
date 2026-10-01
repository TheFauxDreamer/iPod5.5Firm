import Foundation

/// Apple iPod .ipsw files are zips holding `manifest.plist` and one `Firmware-*` partition image.
public enum IPSW {
    public static let videoFirmware13 = URL(string: "http://appldnld.apple.com.edgesuite.net/content.info.apple.com/iPod/SBML/osx/bundles/061-2967.20080313.Cnvkg/iPod_25.1.3.ipsw")!

    static func unpack(_ ipsw: URL) throws -> (dir: URL, name: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ipsw-\(UUID().uuidString)")
        _ = try runTool("/usr/bin/ditto", ["-x", "-k", ipsw.path, dir.path])
        var name: String?
        if let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            name = (plist["FirmwarePayload"] as? [String: Any])?["FirmwareName"] as? String
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        if name == nil || !files.contains(name!) {
            let candidates = files.filter { $0.hasPrefix("Firmware-") }
            guard candidates.count == 1 else { throw FirmwareError("Cannot find the firmware inside \(ipsw.lastPathComponent).") }
            name = candidates[0]
        }
        return (dir, name!)
    }

    public static func extractFirmware(_ ipsw: URL) throws -> (name: String, data: [UInt8]) {
        let (dir, name) = try unpack(ipsw)
        defer { try? FileManager.default.removeItem(at: dir) }
        return (name, [UInt8](try Data(contentsOf: dir.appendingPathComponent(name))))
    }

    /// Copy an ipsw with its firmware payload replaced (for the emulator or a manual restore).
    public static func repack(original: URL, firmware: [UInt8], to output: URL) throws {
        let (dir, name) = try unpack(original)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(firmware).write(to: dir.appendingPathComponent(name))
        try? FileManager.default.removeItem(at: output)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-q", "-X", "-r", output.path, "."]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw FirmwareError("zip failed while writing \(output.lastPathComponent).") }
    }
}
