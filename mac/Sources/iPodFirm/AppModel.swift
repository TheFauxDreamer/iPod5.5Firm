import AppKit
import CryptoKit
import Foundation
import IPodFWKit
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Firmware", pictures = "Pictures", strings = "Text", ipod = "iPod", emulator = "Emulator"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "cpu"
        case .pictures: "photo.on.rectangle"
        case .strings: "textformat"
        case .ipod: "externaldrive.connected.to.line.below"
        case .emulator: "play.display"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: Pane = .overview
    @Published var editor: FirmwareEditor?
    @Published var fileURL: URL?
    @Published var sourceIPSW: URL?
    @Published var openedFromBackup = false
    @Published var isDirty = false
    @Published var revision = 0
    @Published var busy: String?
    @Published var alert: AlertInfo?
    @Published var ipods: [IPodDisk] = []
    @Published var selectedIPod: String?
    @Published var backups: [BackupInfo] = []
    @Published var flashPlan: FlashPlan?

    struct AlertInfo: Identifiable { let id = UUID(); let title: String; let message: String }
    struct FlashPlan: Identifiable {
        let id = UUID()
        let ipod: IPodDisk
        let image: URL
        let reason: String
        let result: HelperResult
    }

    static let supportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("iPodFirm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let backupDir = supportDir.appendingPathComponent("Backups")
    static let appleFirmwareSHA256 = "840b2480ad5b692c098cb772c3d2bf8f58bf37557788782b596ac01c27ecdc32"

    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "dev") (\(info["CFBundleVersion"] as? String ?? "0"))"
    }

    var currentIPod: IPodDisk? { ipods.first { $0.disk == selectedIPod } ?? ipods.first }

    // MARK: helpers

    func fail(_ title: String, _ error: Error) {
        alert = AlertInfo(title: title, message: error.localizedDescription)
    }

    func work<T>(_ label: String, _ body: @escaping () throws -> T) async throws -> T {
        busy = label
        defer { busy = nil }
        return try await Task.detached(priority: .userInitiated) { try body() }.value
    }

    func edited() {
        isDirty = true
        revision += 1
    }

    // MARK: opening & saving

    func confirmDiscard() -> Bool {
        guard isDirty else { return true }
        let a = NSAlert()
        a.messageText = "Discard your unsaved changes?"
        a.informativeText = "The firmware you are editing has changes that have not been saved or flashed."
        a.addButton(withTitle: "Discard")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    func open(_ url: URL, fromBackup: Bool = false) async {
        guard confirmDiscard() else { return }
        do {
            let isIPSW = url.pathExtension.lowercased() == "ipsw"
            let ed = try await work("Opening \(url.lastPathComponent)…") {
                let bytes = isIPSW ? try IPSW.extractFirmware(url).data : [UInt8](try Data(contentsOf: url))
                return try FirmwareEditor(partition: FirmwarePartition(data: bytes))
            }
            editor = ed
            fileURL = url
            if isIPSW { sourceIPSW = url }
            openedFromBackup = fromBackup
            isDirty = false
            revision += 1
            section = .overview
        } catch {
            fail("Couldn't open \(url.lastPathComponent)", error)
        }
    }

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = []
        p.allowsOtherFileTypes = true
        p.message = "Choose an Apple .ipsw, a firmware .bin, or an iPod backup"
        p.directoryURL = Self.backupDir
        if p.runModal() == .OK, let url = p.url { Task { await open(url) } }
    }

    func saveAs() {
        guard let editor else { return }
        let p = NSSavePanel()
        p.nameFieldStringValue = "custom-firmware.bin"
        p.message = "Save the customised firmware partition image"
        guard p.runModal() == .OK, let url = p.url else { return }
        guard !url.path.hasPrefix(Self.backupDir.path) else {
            alert = AlertInfo(title: "Not saved", message: "Backups are never overwritten. Choose a location outside the Backups folder.")
            return
        }
        do {
            try Data(editor.partition.data).write(to: url, options: .atomic)
            isDirty = false
        } catch { fail("Couldn't save", error) }
    }

    func downloadAppleFirmware() async {
        let dest = Self.supportDir.appendingPathComponent("Firmware/iPod_25.1.3.ipsw")
        do {
            if !FileManager.default.fileExists(atPath: dest.path) {
                busy = "Downloading Apple firmware 1.3…"
                defer { busy = nil }
                let (tmp, _) = try await URLSession.shared.download(from: IPSW.videoFirmware13)
                let data = try Data(contentsOf: tmp)
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard sha == Self.appleFirmwareSHA256 else { throw FirmwareError("The download did not match Apple's published file (SHA-256 mismatch).") }
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: dest)
            }
            await open(dest)
        } catch { fail("Download failed", error) }
    }

    // MARK: pictures

    func exportPicture(_ item: PictureItem) {
        guard let data = editor?.png(of: item) else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = String(format: "%04d_%d.png", item.index, item.resourceID)
        if p.runModal() == .OK, let url = p.url {
            do { try data.write(to: url) } catch { fail("Couldn't export", error) }
        }
    }

    func replacePicture(_ item: PictureItem, from url: URL) {
        guard let editor else { return }
        do {
            let img = try ImageCodec.load(url)
            guard img.width == item.picture.width, img.height == item.picture.height else {
                throw PictureError("That image is \(img.width)×\(img.height). This picture must stay \(item.picture.width)×\(item.picture.height).")
            }
            if try editor.replacePicture(item, rgba: ImageCodec.rgba(img)) { edited() }
        } catch { fail("Couldn't replace picture", error) }
    }

    func chooseReplacement(for item: PictureItem) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.png, .image]
        p.message = "Choose a \(item.picture.width)×\(item.picture.height) image"
        if p.runModal() == .OK, let url = p.url { replacePicture(item, from: url) }
    }

    func exportFolder() {
        guard let editor else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Export Here"
        p.message = "Choose an empty folder for the pictures (PNG) and text (JSON)"
        guard p.runModal() == .OK, let url = p.url else { return }
        Task {
            do {
                try await work("Exporting…") { try editor.exportFolder(to: url) }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { fail("Export failed", error) }
        }
    }

    func importFolder() {
        guard let editor else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Import"
        p.message = "Choose a folder previously exported by iPodFirm or ipodfw"
        guard p.runModal() == .OK, let url = p.url else { return }
        Task {
            do {
                let changed = try await work("Importing…") { try editor.importFolder(from: url) }
                if !changed.isEmpty { edited() }
                alert = AlertInfo(title: "Import finished", message: changed.isEmpty ? "No changes found." : "\(changed.count) file(s) applied.")
            } catch { fail("Import failed", error) }
        }
    }

    // MARK: strings

    func applyStrings(blockIndex: Int, _ values: [String: String]) -> Bool {
        guard let editor else { return false }
        do {
            if try editor.setStrings(blockIndex: blockIndex, values) { edited() }
            return true
        } catch {
            fail("Couldn't apply text", error)
            return false
        }
    }

    // MARK: iPod

    func refreshIPods() async {
        do {
            ipods = try await Task.detached { try Device.findIPods() }.value
            if selectedIPod == nil || !ipods.contains(where: { $0.disk == selectedIPod }) { selectedIPod = ipods.first?.disk }
        } catch { fail("Couldn't list disks", error) }
        refreshBackups()
    }

    func refreshBackups() { backups = Backups.list(in: Self.backupDir) }

    func backupURL(_ b: BackupInfo) -> URL { Self.backupDir.appendingPathComponent(b.file) }

    private func helperArgs(_ cmd: String, _ ipod: IPodDisk) -> [String] {
        [cmd, "--disk", ipod.disk, "--backup-dir", Self.backupDir.path, "--owner", String(getuid())]
    }

    func backupNow() async {
        guard let ipod = currentIPod else { return }
        busy = "Backing up the iPod's firmware partition…"
        defer { busy = nil; refreshBackups() }
        do {
            let r = try await Privileged.run(helperArgs("backup", ipod))
            guard r.ok else { throw FirmwareError(r.message) }
            alert = AlertInfo(title: "Backup saved", message: "\(r.message)\n\n\(r.backup?.file ?? "")")
        } catch { fail("Backup failed", error) }
    }

    /// Step 1 of flashing: dry run (no writes) to show exactly what would change.
    func prepareFlash(image: URL, reason: String) async {
        guard let ipod = currentIPod else { return }
        busy = "Checking the iPod (nothing is written yet)…"
        defer { busy = nil }
        do {
            let r = try await Privileged.run(helperArgs("flash", ipod) + ["--image", image.path, "--reason", reason, "--dry-run"])
            guard r.ok else { throw FirmwareError(r.message) }
            if r.ranges?.isEmpty ?? true {
                alert = AlertInfo(title: "Nothing to do", message: r.message)
            } else {
                flashPlan = FlashPlan(ipod: ipod, image: image, reason: reason, result: r)
            }
        } catch { fail("Can't flash", error) }
    }

    /// Step 2: the helper backs up the current partition, writes only changed blocks, and verifies.
    func performFlash(_ plan: FlashPlan) async {
        flashPlan = nil
        busy = "Backing up, writing and verifying… don't disconnect the iPod."
        defer { busy = nil; refreshBackups() }
        do {
            let r = try await Privileged.run(helperArgs("flash", plan.ipod) + ["--image", plan.image.path, "--reason", plan.reason])
            guard r.ok else { throw FirmwareError(r.message) }
            if plan.reason == "flash" { isDirty = false }
            alert = AlertInfo(title: plan.reason == "restore" ? "Restored" : "Flashed",
                              message: "\(r.message)\nBackup taken first: \(r.backup?.file ?? "-")\n\nEject the iPod. If it doesn't start, reset it (hold Menu+Select), then hold Select+Play for disk mode and restore a backup here.")
        } catch { fail("Flash failed", error) }
    }

    func flashEdited() async {
        guard let editor else { return }
        let staging = Self.supportDir.appendingPathComponent("Staging/flash.bin")
        do {
            try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(editor.partition.data).write(to: staging, options: .atomic)
            await prepareFlash(image: staging, reason: "flash")
        } catch { fail("Can't flash", error) }
    }

    func restore(_ b: BackupInfo) async { await prepareFlash(image: backupURL(b), reason: "restore") }

    // MARK: emulator

    func exportIPSW() {
        guard let editor else { return }
        var original = sourceIPSW
        let cached = Self.supportDir.appendingPathComponent("Firmware/iPod_25.1.3.ipsw")
        if original == nil, FileManager.default.fileExists(atPath: cached.path) { original = cached }
        if original == nil {
            let p = NSOpenPanel()
            p.message = "Choose Apple's iPod_25.1.3.ipsw (or use Download Apple Firmware first)"
            guard p.runModal() == .OK, let url = p.url else { return }
            original = url
        }
        let s = NSSavePanel()
        s.nameFieldStringValue = "custom-iPod_25.1.3.ipsw"
        guard s.runModal() == .OK, let out = s.url, let original else { return }
        let data = editor.partition.data
        Task {
            do {
                try await work("Writing .ipsw…") { try IPSW.repack(original: original, firmware: data, to: out) }
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch { fail("Couldn't write .ipsw", error) }
        }
    }
}
