import AppKit
import Foundation
import IPodFWKit

/// Installs/updates siggifly/ipod-emulator from source, and boots a customised firmware in it:
/// builds a drive with the emulator's own `ipod-boot make-disk`, points an "iPodFirm Test" device at
/// that drive in the emulator's (documented, hand-editable) settings.txt, and cold-boots it.
@MainActor
final class EmulatorManager: ObservableObject {
    static let appURL = URL(fileURLWithPath: "/Applications/ipod-emulator.app")
    static let bundleID = "net.siggifly.ipod-emulator"
    static let workDir = AppModel.supportDir.appendingPathComponent("Emulator")
    static let sourceDir = AppModel.supportDir.appendingPathComponent("emulator-src")
    static var ipodBoot: URL { sourceDir.appendingPathComponent("target/release/ipod-boot") }
    static let emuData = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ipod-emulator")
    static let deviceName = "iPodFirm Test"
    static let diskName = "ipodfirm-custom"

    @Published var log = ""
    @Published var installing = false
    @Published var installedVersion: String?
    @Published var lastRun: Date?

    init() { refresh() }

    func refresh() {
        let plist = Self.appURL.appendingPathComponent("Contents/Info.plist")
        installedVersion = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String)
            ?? (FileManager.default.fileExists(atPath: Self.appURL.path) ? "installed" : nil)
    }

    var toolsReady: Bool { installedVersion != nil && FileManager.default.isExecutableFile(atPath: Self.ipodBoot.path) }

    var installScript: URL? { Bundle.main.url(forResource: "install-emulator", withExtension: "sh") }

    func install() {
        guard !installing, let script = installScript else { return }
        installing = true
        log = ""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(NSHomeDirectory())/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let text = String(decoding: h.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor in self.append(text) }
        }
        p.terminationHandler = { proc in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self.installing = false
                self.append(proc.terminationStatus == 0 ? "\n✓ Done.\n" : "\n✗ Failed (exit \(proc.terminationStatus)).\n")
                self.refresh()
            }
        }
        do { try p.run() } catch {
            installing = false
            append("Couldn't start the installer: \(error.localizedDescription)\n")
        }
    }

    private func append(_ text: String) {
        log += text
        if log.count > 200_000 { log = String(log.suffix(150_000)) }
    }

    // MARK: run

    /// Boot `firmware` (an Apple-layout firmware partition) in the emulator, from cold.
    func run(firmware: [UInt8], originalIPSW: URL) async throws {
        guard toolsReady else { throw FirmwareError("Install the emulator first (Emulator pane).") }
        try await quitEmulator()
        let ipsw = Self.workDir.appendingPathComponent("iPodFirm custom.ipsw")
        let drives = Self.emuData.appendingPathComponent("drives")
        let drive = drives.appendingPathComponent("\(Self.diskName).img")
        let tool = Self.ipodBoot
        try await Task.detached {
            let fm = FileManager.default
            try fm.createDirectory(at: Self.workDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: drives, withIntermediateDirectories: true)
            try IPSW.repack(original: originalIPSW, firmware: firmware, to: ipsw)
            try? fm.removeItem(at: drive)
            try Self.runTool(tool, ["make-disk", ipsw.path, drive.path])
            // a restore point from an earlier boot would resume the old firmware
            let snaps = Self.emuData.appendingPathComponent("cache/snapshots")
            for f in (try? fm.contentsOfDirectory(atPath: snaps.path)) ?? [] where f.hasPrefix(Self.diskName + ".") {
                try? fm.removeItem(at: snaps.appendingPathComponent(f))
            }
            try Self.selectDevice(drive: drive)
        }.value
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--cold"]
        try await NSWorkspace.shared.openApplication(at: Self.appURL, configuration: config)
        lastRun = Date()
    }

    func quitEmulator() async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if running.contains(where: { !$0.isTerminated }) {
            throw FirmwareError("Please quit ipod-emulator, then try again.")
        }
    }

    nonisolated static func runTool(_ tool: URL, _ args: [String]) throws {
        let p = Process()
        p.executableURL = tool
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw FirmwareError("\(tool.lastPathComponent) \(args.first ?? "") failed: \(msg)")
        }
    }

    /// Add (or update) a drive and an "iPodFirm Test" device in the emulator's settings.txt and make it current.
    nonisolated static func selectDevice(drive: URL) throws {
        let url = emuData.appendingPathComponent("settings.txt")
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n")
        func value(_ key: String) -> String? {
            lines.first { $0.hasPrefix(key + " =") }.map { String($0.dropFirst(key.count + 2)).trimmingCharacters(in: .whitespaces) }
        }
        func set(_ key: String, _ v: String) {
            if let i = lines.firstIndex(where: { $0.hasPrefix(key + " =") }) { lines[i] = "\(key) = \(v)" } else { lines.append("\(key) = \(v)") }
        }
        func index(_ prefix: String, named name: String) -> Int {
            var n = 0
            while let existing = value("\(prefix).\(n).name") {
                if existing == name { return n }
                n += 1
            }
            return n
        }
        // Boot ROM: the one the current device uses, else any synthesised firmware resource.
        let current = value("current")
        var firmware: String?
        var n = 0
        while let name = value("device.\(n).name") {
            if name == current, let fw = value("device.\(n).firmware") { firmware = fw }
            n += 1
        }
        if firmware == nil {
            var r = 0
            while let name = value("res.\(r).name") {
                if value("res.\(r).kind") == "firmware" { firmware = name; break }
                r += 1
            }
        }
        guard let firmware else {
            throw FirmwareError("Open ipod-emulator once and finish its first-run setup, then try again.")
        }
        let d = index("disk", named: diskName)
        set("disk.\(d).name", diskName)
        set("disk.\(d).path", drive.path)
        set("disk.\(d).built_from", "iPodFirm custom")
        set("disk.\(d).installed", "Apple's software")
        let v = index("device", named: deviceName)
        set("device.\(v).name", deviceName)
        set("device.\(v).firmware", firmware)
        set("device.\(v).disk", diskName)
        set("device.\(v).chassis", value("chassis") ?? "white")
        set("current", deviceName)
        set("disk", drive.path)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
