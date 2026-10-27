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
    nonisolated static let workDir = AppModel.supportDir.appendingPathComponent("Emulator")
    static let sourceDir = AppModel.supportDir.appendingPathComponent("emulator-src")
    static var ipodBoot: URL { sourceDir.appendingPathComponent("target/release/ipod-boot") }
    static let emuData = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ipod-emulator")
    nonisolated static let deviceName = "iPodFirm Test"
    nonisolated static let diskName = "ipodfirm-custom"

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
            append("Cannot start the installer: \(error.localizedDescription)\n")
        }
    }

    private func append(_ text: String) {
        log += text
        if log.count > 200_000 { log = String(log.suffix(150_000)) }
    }

    // MARK: run

    /// iPodFirm runs the emulator on its own data folder (IPOD_EMULATOR_DATA), so the test device
    /// can't be confused with the user's own emulator devices, and theirs are never touched.
    nonisolated static let profile = AppModel.supportDir.appendingPathComponent("EmulatorProfile")
    nonisolated static let romSeed = "5500550055005500"

    /// Build the test drive from `firmware` (an Apple-layout firmware partition) and write the profile.
    /// The music library on the emulator drive.
    enum Library: Equatable {
        case none
        case test
        case folder(URL, songs: Int)

        static var current: Library {
            let d = UserDefaults.standard
            switch d.string(forKey: "emulatorLibrary") ?? "test" {
            case "none": return .none
            case "folder":
                guard let path = d.string(forKey: "emulatorMusicFolder") else { return .test }
                let n = d.integer(forKey: "emulatorSongCount")
                return .folder(URL(fileURLWithPath: path), songs: n > 0 ? n : 200)
            default: return .test
            }
        }
    }

    func prepare(firmware: [UInt8], ososLength: Int, originalIPSW: URL, library: Library) async throws {
        guard toolsReady else { throw FirmwareError("Install the emulator first (Emulator pane).") }
        try await quitEmulator()
        let ipsw = Self.workDir.appendingPathComponent("iPodFirm custom.ipsw")
        let drive = Self.profile.appendingPathComponent("drives/\(Self.diskName).img")
        let tool = Self.ipodBoot
        try await Task.detached {
            let fm = FileManager.default
            try fm.createDirectory(at: Self.workDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: drive.deletingLastPathComponent(), withIntermediateDirectories: true)
            try IPSW.repack(original: originalIPSW, firmware: firmware, to: ipsw)
            try? fm.removeItem(at: drive)
            try Self.runTool(tool, ["make-disk", ipsw.path, drive.path])
            // make-disk makes the osos length too short for a patched image (see EmulatorDrive).
            try EmulatorDrive.fixOSOSLength(drive: drive, ososLength: ososLength)
            var lib: URL?
            switch library {
            case .none:
                break
            case .test:
                // 60 tracks in 6 albums. The audio files are made one time and kept.
                lib = Self.workDir.appendingPathComponent("TestLibrary")
                try ITunesDB.makeLibrary(at: lib!)
            case .folder(let folder, let count):
                lib = Self.workDir.appendingPathComponent("FolderLibrary")
                try? fm.removeItem(at: lib!)
                let songs = MusicImport.pick(MusicImport.scan(folder), limit: count, perAlbum: 8)
                guard !songs.isEmpty else { throw FirmwareError("The folder has no .m4a music files.") }
                try MusicImport.makeLibrary(from: songs, to: lib!, copyAudio: true)
            }
            if let lib {
                try Self.runTool(tool, ["put-files", drive.path, lib.appendingPathComponent("iPod_Control").path, "/iPod_Control"])
            }
            // a restore point from an earlier run would resume the old firmware
            try? fm.removeItem(at: Self.profile.appendingPathComponent("cache/snapshots"))
            try Self.writeProfile(drive: drive)
        }.value
        lastRun = Date()
    }

    /// Open the prepared test device in the emulator's own window.
    /// The restart of the Dark Mode item (iPodFirm emulator patch, DEV_RS). The emulated start also
    /// writes DEV_RS, so the emulator honours it only after this many instructions.
    nonisolated static let resetAfter = "1000000000"

    func openWindow() async throws {
        try await quitEmulator()
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--cold"]
        config.environment = ["IPOD_EMULATOR_DATA": Self.profile.path, "IPODFW_RESET_AFTER": Self.resetAfter]
        config.createsNewApplicationInstance = true
        try await NSWorkspace.shared.openApplication(at: Self.appURL, configuration: config)
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

    /// The whole profile: one synthesised 5.5G, one drive, one device, selected. Written in the form
    /// the emulator itself saves. Keeps the emulator's measured speed from the previous run.
    nonisolated static func writeProfile(drive: URL) throws {
        let url = profile.appendingPathComponent("settings.txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let clock = old.components(separatedBy: "\n").first { $0.hasPrefix("sustained_clock =") }
        let text = """
        # Written by iPodFirm for its "Run in Emulator" test device. Rewritten on every run.
        chassis = white
        nor_model = A444
        nor_seed = \(romSeed)
        disk = \(drive.path)
        check_updates_on_start = false
        developer = false
        welcomed = true
        work_on_copy = false
        \(clock ?? "")
        library_seeded = true

        res.0.name = iPodFirm test iPod
        res.0.kind = firmware
        res.0.nor_model = A444
        res.0.nor_seed = \(romSeed)

        disk.0.name = \(diskName)
        disk.0.path = \(drive.path)
        disk.0.built_from = iPodFirm custom
        disk.0.installed = Apple's software

        current = \(deviceName)

        device.0.name = \(deviceName)
        device.0.firmware = iPodFirm test iPod
        device.0.disk = \(drive.path)
        device.0.chassis = white
        device.0.work_on_copy = false

        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
