import AppKit
import CryptoKit
import Foundation
import IPodFWKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Firmware", pictures = "Pictures", strings = "Text", patches = "Patches", ipod = "iPod", emulator = "Emulator"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "cpu"
        case .pictures: "photo.on.rectangle"
        case .strings: "textformat"
        case .patches: "puzzlepiece.extension"
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
    /// iPods for which the helper gave HelperResult.unsupportedIPod (for example an iPod classic).
    @Published var unsupportedIPods: Set<IPodDisk> = []
    @Published var backups: [BackupInfo] = []
    @Published var flashPlan: FlashPlan?
    @Published var hasFullDiskAccess = AppModel.checkFullDiskAccess()
    @Published var helperStatus: SMAppService.Status = HelperClient.service.status
    @Published var patches: [PatchInfo] = AppModel.patchLibrary.list().filter { $0.spec.internal != true }
    @Published var enabledPatches: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledPatches") ?? []) {
        didSet { UserDefaults.standard.set(Array(enabledPatches), forKey: "enabledPatches") }
    }
    /// The selected choice of each patch option: patch name -> option id -> value (see PatchSpec.Option).
    @Published var patchOptions: [String: [String: Int]] =
        (UserDefaults.standard.dictionary(forKey: "patchOptions") as? [String: [String: Int]]) ?? [:] {
        didSet { UserDefaults.standard.set(patchOptions, forKey: "patchOptions") }
    }
    @Published var appearance: Appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .light {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var themes: [ThemeFile] = AppModel.loadThemes()
    @Published var selectedThemeName: String? = UserDefaults.standard.string(forKey: "darkTheme") {
        didSet { UserDefaults.standard.set(selectedThemeName, forKey: "darkTheme") }
    }
    @Published var customVersionOn = UserDefaults.standard.bool(forKey: "customVersionOn") {
        didSet { UserDefaults.standard.set(customVersionOn, forKey: "customVersionOn") }
    }
    @Published var customVersion = UserDefaults.standard.string(forKey: "customVersion") ?? "1.3.1" {
        didSet { UserDefaults.standard.set(customVersion, forKey: "customVersion") }
    }
    @Published var versionLettersOn = UserDefaults.standard.bool(forKey: "versionLettersOn") {
        didSet { UserDefaults.standard.set(versionLettersOn, forKey: "versionLettersOn") }
    }
    @Published var themeReport: ImportedTheme?
    /// A patch that the owner opened, before the install (the install sheet shows it).
    @Published var pendingInstall: PatchCandidate?
    /// The result of the last action of each patch (patch.json "ui"), by patch name.
    @Published var patchActionStatus: [String: String] = [:]
    /// The state of the switches of the patches (patch.json "ui"), by path on the iPod.
    @Published var patchToggleStates: [String: Bool] = [:]
    /// The selected row in the Patches pane: "appearance", "version" or the name of a patch.
    @Published var patchSelection: String? = "appearance"
    /// The Pictures pane shows the pictures of the selected dark theme.
    @Published var picturesDark = false
    /// Increases when the app writes a theme file (an edit of a dark picture).
    @Published var themeRevision = 0
    @Published var thumbnailStatus: String?
    /// The decoded USB log of the probe (nil: not read).
    @Published var usbProbeLog: [USBProbeLog.Entry]?
    /// The playlists of the connected iPod and their thumbnails (album-art patch).
    @Published var playlistArt: [MusicImport.PlaylistArt] = []
    /// True after a change to a playlist image that is not yet in the thumbnail file on the iPod.
    @Published var playlistArtChanged = false
    @Published var helperSetupError: String?
    @AppStorage("requireTouchID") var requireTouchID = true
    @Published var showFullDiskAccessHelp = false
    @Published var showFinderRestoreHelp = false

    /// The appearance of the iPod software.
    enum Appearance: String, CaseIterable, Identifiable {
        case light, dark, onIPod = "switch"
        var id: String { rawValue }
        var title: String { self == .onIPod ? "Switch on iPod" : rawValue.capitalized }
    }

    /// What the output build does with the dark theme.
    enum AppearanceBuild {
        /// The theme is in the firmware: always dark.
        case dark(ImportedTheme)
        /// Light firmware with a Dark Mode item in Settings (DarkMode.build).
        case switchOnIPod(ImportedTheme, PatchInfo)
    }

    /// An imported theme in the Themes folder.
    struct ThemeFile: Identifiable {
        var id: String { name }
        var name: String
        var url: URL
        var theme: ImportedTheme
    }

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
    static let themesDir = supportDir.appendingPathComponent("Themes")
    static var patchesDir: URL { Bundle.main.resourceURL!.appendingPathComponent("patches") }
    /// The built-in patches and the patches that the owner installs (Application Support/iPodFirm/Patches).
    static let patchLibrary = PatchLibrary(builtInDir: patchesDir, userDir: supportDir.appendingPathComponent("Patches"),
                                           stagingDir: supportDir.appendingPathComponent("Staging"))
    static let appleFirmwareSHA256 = "840b2480ad5b692c098cb772c3d2bf8f58bf37557788782b596ac01c27ecdc32"

    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "dev") (\(info["CFBundleVersion"] as? String ?? "0"))"
    }

    var currentIPod: IPodDisk? { ipods.first { $0.disk == selectedIPod } ?? ipods.first }

    /// True if the helper found that the selected iPod is not an iPod Video.
    var currentIPodIsUnsupported: Bool { currentIPod.map { unsupportedIPods.contains($0) } ?? false }

    // MARK: helpers

    func fail(_ title: String, _ error: Error) {
        if (error as? FirmwareError)?.code == HelperResult.fullDiskAccess {
            hasFullDiskAccess = false
            showFullDiskAccessHelp = true
            return
        }
        if (error as? FirmwareError)?.code == HelperResult.unsupportedIPod, let ipod = currentIPod {
            unsupportedIPods.insert(ipod)
            alert = AlertInfo(title: "Unsupported iPod", message: error.localizedDescription)
            return
        }
        alert = AlertInfo(title: title, message: error.localizedDescription)
    }

    /// Reading the system TCC database is only possible with Full Disk Access.
    nonisolated static func checkFullDiskAccess() -> Bool {
        let probe = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let h = FileHandle(forReadingAtPath: probe) else { return false }
        try? h.close()
        return true
    }

    func recheckFullDiskAccess() {
        hasFullDiskAccess = Self.checkFullDiskAccess()
        helperStatus = HelperClient.service.status
        guard helperStatus == .enabled else { return }
        Task {
            // The helper does the disk access, so its own permission is what counts.
            if let s = try? await HelperClient.status() { hasFullDiskAccess = s.hasFullDiskAccess }
        }
    }

    /// Register the Touch ID helper; macOS then asks for approval in Login Items once.
    func setUpHelper() {
        do {
            try HelperClient.register()
            helperSetupError = nil
        } catch {
            helperSetupError = error.localizedDescription
        }
        helperStatus = HelperClient.service.status
        if helperStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        recheckFullDiskAccess()
    }

    func removeHelper() {
        Task {
            try? await HelperClient.unregister()
            helperStatus = HelperClient.service.status
        }
    }

    // Route privileged work through the daemon (Touch ID) when enabled, else the password prompt.
    private func runBackup(_ ipod: IPodDisk) async throws -> HelperResult {
        if HelperClient.isEnabled { return try await HelperClient.backup(disk: ipod.disk, backupDir: Self.backupDir) }
        return try await Privileged.run(helperArgs("backup", ipod))
    }

    /// reason is "flash", "restore", or "rescue" (a restore onto a damaged firmware partition).
    private func runFlash(_ ipod: IPodDisk, image: URL, reason: String, dryRun: Bool) async throws -> HelperResult {
        let rescue = reason == "rescue"
        if HelperClient.isEnabled {
            if !dryRun && requireTouchID {
                try await HelperClient.authenticate(reason == "flash" ? "write new firmware to your iPod" : "restore a backup to your iPod")
            }
            if rescue {
                return try await HelperClient.rescueRestore(disk: ipod.disk, image: image, backupDir: Self.backupDir, dryRun: dryRun)
            }
            return try await HelperClient.flash(disk: ipod.disk, image: image, backupDir: Self.backupDir, reason: reason, dryRun: dryRun)
        }
        let args = rescue ? helperArgs("rescue", ipod) + ["--image", image.path]
                          : helperArgs("flash", ipod) + ["--image", image.path, "--reason", reason]
        return try await Privileged.run(args + (dryRun ? ["--dry-run"] : []))
    }

    func openFullDiskAccessSettings() {
        let urls = ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        for u in urls where NSWorkspace.shared.open(URL(string: u)!) { return }
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
            fail("Cannot open \(url.lastPathComponent)", error)
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
            try Data(Self.outputPartition(editor, activePatches, appearance: activeAppearance, version: activeVersion)).write(to: url, options: .atomic)
            isDirty = false
        } catch { fail("Cannot save", error) }
    }

    static let cachedAppleIPSW = supportDir.appendingPathComponent("Firmware/iPod_25.1.3.ipsw")

    nonisolated static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func downloadAppleFirmware() async {
        do { await open(try await ensureAppleIPSW()) } catch { fail("Download failed", error) }
    }

    /// Apple's 1.3 .ipsw: the one this firmware came from, else a verified cached download.
    func ensureAppleIPSW() async throws -> URL {
        // Only Apple's genuine file will do: an .ipsw opened earlier may itself be a custom export.
        if let sourceIPSW, Self.sha256(of: sourceIPSW) == Self.appleFirmwareSHA256 { return sourceIPSW }
        let dest = Self.cachedAppleIPSW
        if FileManager.default.fileExists(atPath: dest.path), Self.sha256(of: dest) != Self.appleFirmwareSHA256 {
            try? FileManager.default.removeItem(at: dest)
        }
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
            return dest
        }
    }

    // MARK: appearance (dark theme)

    static func loadThemes() -> [ThemeFile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "ipodtheme" }
            .compactMap { url in (try? ImportedTheme.load(url)).map { ThemeFile(name: $0.name, url: url, theme: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedTheme: ThemeFile? { themes.first { $0.name == selectedThemeName } ?? themes.first }

    /// The dark-mode patch: not in the list of patches, because DarkMode.build adds it.
    static let darkModePatch = Patcher.list(in: AppModel.patchesDir).first { $0.spec.name == "dark-mode" }

    /// The appearance build for the output: nothing for Light.
    var activeAppearance: AppearanceBuild? {
        guard let theme = selectedTheme?.theme else { return nil }
        switch appearance {
        case .light: return nil
        case .dark: return .dark(theme)
        case .onIPod: return Self.darkModePatch.map { .switchOnIPod(theme, $0) }
        }
    }

    /// The version for the About screen: the custom version (or 1.3) and the letters of the switched-on patches.
    /// Nothing when the result is the Apple version.
    var activeVersion: FirmwareVersion? {
        var v = (customVersionOn ? FirmwareVersion(customVersion) : nil) ?? .stock
        if versionLettersOn { v.letters = activePatches.compactMap(\.spec.version_letter).sorted().joined() }
        return v == .stock ? nil : v
    }

    func isCompatible(_ t: ImportedTheme) -> Bool { editor?.originalOSOSHash == t.osos_sha256 }

    private var switchSizeCache: (key: String, size: Int?)?

    /// The bytes that "Switch on iPod" adds to the firmware: the theme data, the switch table, the
    /// Settings menu and the dark-mode code. Nil if no theme agrees with the open firmware.
    var switchOnIPodSize: Int? {
        guard let editor, let file = selectedTheme, isCompatible(file.theme), let patch = Self.darkModePatch else { return nil }
        let key = "\(revision) \(themeRevision) \(file.name)"
        if let c = switchSizeCache, c.key == key { return c.size }
        let size = try? DarkMode.addedSize(partition: editor.partition, osos: editor.osos, theme: file.theme,
                                           codeSize: patch.spec.size ?? 0)
        switchSizeCache = (key, size)
        return size
    }

    // MARK: dark theme pictures

    private var darkCache: (key: String, osos: [UInt8], items: [PictureItem])?

    /// The osos with the selected dark theme, and its pictures. Nil if no theme agrees with the open firmware.
    var darkPictures: (osos: [UInt8], items: [PictureItem])? {
        guard let editor, let file = selectedTheme, isCompatible(file.theme) else { return nil }
        let key = "\(revision) \(themeRevision) \(file.name)"
        if let c = darkCache, c.key == key { return (c.osos, c.items) }
        var osos = editor.osos
        guard (try? file.theme.apply(to: &osos, originalSHA256: editor.originalOSOSHash)) != nil,
              let main = try? Resources.mainBlock(Resources.scan(osos, limit: editor.partition.appleOSLength)) else { return nil }
        let items = Pictures.list(osos, main)
        darkCache = (key, osos, items)
        return (osos, items)
    }

    /// The pictures and the osos that the Pictures pane shows: Apple's or the dark theme.
    var shownPictures: (osos: [UInt8], items: [PictureItem])? {
        if picturesDark { return darkPictures }
        return editor.map { ($0.osos, $0.pictures) }
    }

    /// True if the owner replaced this picture of the dark theme.
    func hasDarkEdit(_ item: PictureItem) -> Bool {
        selectedTheme?.theme.edits.contains { $0.offset == item.picture.dataPos } ?? false
    }

    /// Put a picture into the selected dark theme. The light pictures do not change.
    func replaceDarkPicture(_ item: PictureItem, rgba: [UInt8]) throws {
        guard let editor, let file = selectedTheme, let dark = darkPictures else { return }
        var osos = dark.osos
        guard try item.picture.encode(&osos, rgba: rgba) else { return }
        let p = item.picture
        var theme = file.theme
        theme.setEdit(resource: "BMap \(item.resourceID)", offset: p.dataPos, light: editor.osos,
                      new: Array(osos[p.dataPos..<p.dataPos + p.bytesPerRow * p.height]))
        try saveTheme(theme, to: file.url)
    }

    /// Use the picture of the imported theme again.
    func useThemePicture(_ item: PictureItem) {
        guard let file = selectedTheme else { return }
        var theme = file.theme
        theme.removeEdit(offset: item.picture.dataPos)
        do { try saveTheme(theme, to: file.url) } catch { fail("Cannot save the theme", error) }
    }

    private func saveTheme(_ theme: ImportedTheme, to url: URL) throws {
        try theme.write(to: url)
        themes = Self.loadThemes()
        themeRevision += 1
    }

    func chooseFile(_ message: String) -> URL? {
        let p = NSOpenPanel()
        p.allowedContentTypes = []
        p.allowsOtherFileTypes = true
        p.message = message
        return p.runModal() == .OK ? p.url : nil
    }

    /// Import an iPodWizard theme: the theme file, then the Apple firmware that it came from.
    /// The target is Apple's firmware 1.3, the version of the patches.
    func importTheme() {
        guard let themeURL = chooseFile("Choose the iPodWizard theme (a firmware file, for example \"Dark Gray (04_12_20)\")"),
              let baseURL = chooseFile("Choose the Apple firmware that the theme came from (for example iPod_25.1.2.1.ipsw)") else { return }
        Task {
            do {
                let target = try await ensureAppleIPSW()
                let file = try await work("Importing \(themeURL.lastPathComponent)…") { () -> ThemeFile in
                    func partition(_ url: URL) throws -> [UInt8] {
                        url.pathExtension.lowercased() == "ipsw" ? try IPSW.extractFirmware(url).data : [UInt8](try Data(contentsOf: url))
                    }
                    let themeBytes = try partition(themeURL)
                    let name = themeURL.deletingPathExtension().lastPathComponent
                    let theme = try ThemeImport.make(theme: FirmwarePartition(data: themeBytes), base: FirmwarePartition(data: partition(baseURL)),
                                                     target: FirmwarePartition(data: partition(target)), name: name,
                                                     sourceSHA256: ThemeImport.sha256([UInt8](try Data(contentsOf: themeURL))))
                    try FileManager.default.createDirectory(at: Self.themesDir, withIntermediateDirectories: true)
                    let url = Self.themesDir.appendingPathComponent(name + ".ipodtheme")
                    try theme.write(to: url)
                    return ThemeFile(name: name, url: url, theme: theme)
                }
                themes = Self.loadThemes()
                selectedThemeName = file.name
                themeReport = file.theme
            } catch { fail("Cannot import the theme", error) }
        }
    }

    func deleteTheme(_ t: ThemeFile) {
        try? FileManager.default.removeItem(at: t.url)
        themes = Self.loadThemes()
        if themes.isEmpty, appearance != .light { appearance = .light }
    }

    // MARK: patches

    /// Record the size of each user patch that an earlier version installed without a size. One time at the start.
    func recordMissingPatchSizes() async {
        let library = Self.patchLibrary
        let changed = await Task.detached { library.recordMissingSizes() }.value
        if !changed.isEmpty { reloadPatches() }
    }

    func reloadPatches() {
        patches = Self.patchLibrary.list().filter { $0.spec.internal != true }
        if let s = patchSelection, s != "appearance", s != "version", !patches.contains(where: { $0.spec.name == s }) {
            patchSelection = "appearance"
        }
    }

    /// The turned-on patches that change the same place as `patch`.
    func conflicts(_ patch: PatchInfo) -> [(PatchInfo, String)] {
        Patcher.conflicts([patch] + activePatches.filter { $0.spec.name != patch.spec.name })
            .filter { $0.0.spec.name == patch.spec.name }.map { ($0.1, $0.2) }
    }

    /// Turn a patch on or off. A patch that conflicts with a turned-on patch stays off.
    func setPatch(_ patch: PatchInfo, on: Bool) {
        guard on else { enabledPatches.remove(patch.spec.name); return }
        if let (other, place) = conflicts(patch).first {
            alert = AlertInfo(title: "\(patch.spec.displayTitle) cannot be turned on",
                              message: "The patch changes the same place as \"\(other.spec.displayTitle)\" (\(place)). Turn off \"\(other.spec.displayTitle)\" first.")
            return
        }
        enabledPatches.insert(patch.spec.name)
    }

    /// Examine a .ipodpatch file or a patch folder, then show the install sheet.
    func installPatch(from url: URL) async {
        section = .patches
        let library = Self.patchLibrary, existing = patches
        do {
            pendingInstall = try await work("Examining the patch…") { try library.inspect(url, existing: existing) }
        } catch { fail("Cannot open the patch", error) }
    }

    func choosePatchToInstall() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.allowedContentTypes = [UTType(filenameExtension: PatchLibrary.fileExtension) ?? .zip, .folder]
        p.message = "Select a .ipodpatch file or a patch folder."
        if p.runModal() == .OK, let url = p.url { Task { await installPatch(from: url) } }
    }

    func confirmInstall(_ c: PatchCandidate) {
        pendingInstall = nil
        do {
            try Self.patchLibrary.install(c)
            reloadPatches()
            if let name = c.spec?.name {
                patchSelection = name
                if enabledPatches.contains(name), c.change != .new {
                    alert = AlertInfo(title: "Patch Installed",
                                      message: "The iPod has the old version of this patch. Flash the iPod again to put version \(c.spec?.versionText ?? "–") on it.")
                }
            }
        } catch { fail("Cannot install the patch", error) }
    }

    func cancelInstall(_ c: PatchCandidate) {
        pendingInstall = nil
        if let staging = c.staging { Self.patchLibrary.cleanStaging(staging) }
    }

    func removePatch(_ patch: PatchInfo) {
        do {
            try Self.patchLibrary.remove(patch)
            enabledPatches.remove(patch.spec.name)
            reloadPatches()
        } catch { fail("Cannot remove the patch", error) }
    }

    func exportPatch(_ patch: PatchInfo) {
        let s = NSSavePanel()
        s.nameFieldStringValue = "\(patch.spec.name).\(PatchLibrary.fileExtension)"
        s.message = "iPodFirm adds the compiled code (patch.o), so that other people do not need Xcode."
        guard s.runModal() == .OK, let url = s.url else { return }
        let library = Self.patchLibrary
        Task {
            do {
                try await work("Exporting the patch…") { try library.export(patch, to: url) }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { fail("Cannot export the patch", error) }
        }
    }

    func showPatchesFolder() {
        try? FileManager.default.createDirectory(at: Self.patchLibrary.userDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.patchLibrary.userDir)
    }

    /// Write the files of an action (patch.json "ui") on the mounted iPod.
    func runPatchAction(_ patch: PatchInfo, _ action: PatchUI.Action) {
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod volume not found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        do {
            for w in action.write where PatchUI.isSafePath(w.path) && w.data.count <= PatchUI.maxWrite {
                let url = volume.appendingPathComponent(w.path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try w.data.write(to: url, options: .atomic)
            }
            if action.write.contains(where: { $0.path == Self.usbProbeLogFile }) { usbProbeLog = nil }
            patchActionStatus[patch.spec.name] = "\(action.status ?? "\(action.title): complete.") (\(Date().formatted(date: .omitted, time: .shortened)))"
        } catch { fail("Cannot write the file on the iPod", error) }
    }

    /// Read the switches of a patch (patch.json "ui") from the mounted iPod.
    func loadPatchToggles(_ patch: PatchInfo) {
        let volume = ipodMusicVolume()
        for t in patch.spec.ui?.toggles ?? [] where PatchUI.isSafePath(t.path) {
            let text = volume.flatMap { try? String(contentsOf: $0.appendingPathComponent(t.path), encoding: .utf8) }
            patchToggleStates[t.path] = text?.trimmingCharacters(in: .whitespacesAndNewlines) == t.on
        }
    }

    func setPatchToggle(_ t: PatchUI.Toggle, on: Bool) {
        guard PatchUI.isSafePath(t.path), let volume = ipodMusicVolume() else { return }
        do {
            let url = volume.appendingPathComponent(t.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((on ? t.on : t.off).utf8).write(to: url, options: .atomic)
            patchToggleStates[t.path] = on
        } catch { fail("Cannot write the file on the iPod", error) }
    }

    /// The space after Apple's image for the switched-on patches and the appearance (nil: not known).
    @Published var spaceUse: Patcher.SpaceUse?
    /// The code size of each patch, by folder and version: the app compiles each patch one time.
    private var codeSizes = [String: Int]()

    /// Measure the space of the current selection: build the appearance, and add the code sizes of
    /// the switched-on patches. The Patches pane calls this after each change.
    func refreshSpaceUse() async {
        guard let editor else { spaceUse = nil; return }
        let patches = activePatches, appearance = activeAppearance, known = codeSizes
        let result = try? await Task.detached(priority: .utility) { () -> ([String: Int], Patcher.SpaceUse) in
            let osos = try Self.outputOSOS(editor, [], appearance: appearance, version: nil)
            var sizes = known, list = [(patch: PatchInfo, size: Int)]()
            for p in patches {
                let key = p.folder.path + "|" + (p.spec.version ?? "")
                let size = try sizes[key] ?? Patcher.codeSize(p)
                sizes[key] = size
                list.append((p, size))
            }
            return (sizes, Patcher.spaceUse(imageCount: osos.count, patches: list))
        }.value
        guard !Task.isCancelled else { return }
        if let result {
            codeSizes = result.0
            spaceUse = result.1
        } else {
            spaceUse = nil
        }
    }

    /// The switched-on patches, with the selected value of each option.
    var activePatches: [PatchInfo] {
        patches.filter { enabledPatches.contains($0.spec.name) }.map { p in
            var p = p
            p.options = patchOptions[p.spec.name] ?? [:]
            return p
        }
    }

    /// The selected value of an option of a patch, or its default.
    func optionValue(_ patch: PatchInfo, _ option: PatchSpec.Option) -> Int {
        let v = patchOptions[patch.spec.name]?[option.id] ?? option.defaultValue
        return option.choices.contains { $0.value == v } ? v : option.defaultValue
    }

    func setOptionValue(_ patch: PatchInfo, _ option: PatchSpec.Option, _ value: Int) {
        patchOptions[patch.spec.name, default: [:]][option.id] = value
    }

    func isCompatible(_ p: PatchInfo) -> Bool {
        guard let editor else { return false }
        return Patcher.isCompatible(p, originalSHA256: editor.originalOSOSHash)
    }

    /// The osos with the appearance (Dark, or Switch on iPod) and the switched-on patches applied.
    /// The edits stay as they are: the theme does not change a byte that the owner changed.
    nonisolated static func outputOSOS(_ editor: FirmwareEditor, _ patches: [PatchInfo], appearance: AppearanceBuild?,
                                       version: FirmwareVersion?) throws -> [UInt8] {
        var osos = editor.osos
        switch appearance {
        case .dark(let theme):
            try theme.apply(to: &osos, originalSHA256: editor.originalOSOSHash)
        case .switchOnIPod(let theme, let patch):
            osos = try DarkMode.build(partition: editor.partition, osos: osos, theme: theme, patch: patch,
                                      originalSHA256: editor.originalOSOSHash).0
        case nil:
            break
        }
        if !patches.isEmpty { osos = try Patcher.apply(patches, to: osos, originalSHA256: editor.originalOSOSHash) }
        if let version { try FirmwareVersion.apply(version, to: &osos) }
        return osos
    }

    /// The firmware partition to save or flash: the edits plus the theme and the switched-on patches.
    /// A larger osos moves rsrc (see FirmwarePartition.makeRoom).
    nonisolated static func outputPartition(_ editor: FirmwareEditor, _ patches: [PatchInfo], appearance: AppearanceBuild?,
                                            version: FirmwareVersion?) throws -> [UInt8] {
        let fw = try FirmwarePartition(data: editor.partition.data)
        let osos = try outputOSOS(editor, patches, appearance: appearance, version: version)
        try fw.makeRoom(ososLength: osos.count)
        try fw.replaceImage("osos", with: osos)
        return fw.data
    }

    /// The mounted volume of the connected iPod, if it has a music database.
    func ipodMusicVolume() -> URL? {
        guard let ipod = currentIPod else { return nil }
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [])?
            .first { url in
                (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) == ipod.volumeName &&
                FileManager.default.fileExists(atPath: url.appendingPathComponent("iPod_Control/iTunes/iTunesDB").path)
            }
    }

    /// iPod_Control/iTunes/iPodFirmAlbumArt on the mounted iPod, from its own library.
    func writeThumbnails() async {
        guard currentIPod != nil else { return }
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod volume not found", message: "Connect the iPod so that it shows in Finder, then try again.")
            return
        }
        do {
            let r = try await work("Making album and playlist thumbnails from the music on the iPod…") { try MusicImport.writeThumbnails(volume: volume) }
            thumbnailStatus = "\(r.covers) of \(r.albums) albums and \(r.playlistArt) of \(r.playlists) playlists have a thumbnail (\(Date().formatted(date: .abbreviated, time: .shortened)))."
            playlistArtChanged = false
        } catch { fail("Cannot write the thumbnails", error) }
    }

    /// The log of the usb-host-probe patch. The action in its patch.json makes it empty and writes the
    /// trigger file; the patch writes the log on the iPod.
    static let usbProbeLogFile = "iPod_Control/iTunes/iPodFirmUSBLog"

    func readUSBProbeLog() {
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod volume not found", message: "Connect the iPod so that it shows in Finder, then try again.")
            return
        }
        guard let data = try? Data(contentsOf: volume.appendingPathComponent(Self.usbProbeLogFile)) else {
            alert = AlertInfo(title: "No USB log", message: "The iPod has no USB log. Click Start the Probe at the Next Restart. Then do the test.")
            return
        }
        usbProbeLog = USBProbeLog.parse([UInt8](data)) ?? []
    }

    /// Read the playlists of the connected iPod and their images.
    func loadPlaylists() async {
        guard let volume = ipodMusicVolume() else { playlistArt = []; return }
        playlistArt = (try? await Task.detached(priority: .userInitiated) { try MusicImport.playlists(volume: volume) }.value) ?? []
    }

    func choosePlaylistArt(_ name: String) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.message = "Choose an image for the playlist “\(name)”. iPodFirm uses the centre square."
        if p.runModal() == .OK, let url = p.url { Task { await setPlaylistArt(name, from: url) } }
    }

    func setPlaylistArt(_ name: String, from url: URL) async {
        guard let volume = ipodMusicVolume() else { return }
        do {
            try await work("Saving the image for “\(name)” on the iPod…") { try MusicImport.setPlaylistArt(volume: volume, name: name, image: url) }
            playlistArtChanged = true
            await loadPlaylists()
        } catch { fail("Cannot save the playlist image", error) }
    }

    func resetPlaylistArt(_ name: String) async {
        guard let volume = ipodMusicVolume() else { return }
        do {
            try MusicImport.removePlaylistArt(volume: volume, name: name)
            playlistArtChanged = true
            await loadPlaylists()
        } catch { fail("Cannot remove the playlist image", error) }
    }

    // MARK: pictures

    func exportPicture(_ item: PictureItem) {
        guard let osos = shownPictures?.osos, let data = ImageCodec.png(for: item.picture, osos: osos) else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = String(format: picturesDark ? "%04d_%d_dark.png" : "%04d_%d.png", item.index, item.resourceID)
        if p.runModal() == .OK, let url = p.url {
            do { try data.write(to: url) } catch { fail("Cannot export", error) }
        }
    }

    func replacePicture(_ item: PictureItem, from url: URL) {
        guard let editor else { return }
        do {
            let img = try ImageCodec.load(url)
            guard img.width == item.picture.width, img.height == item.picture.height else {
                throw PictureError("That image is \(img.width)×\(img.height). This picture must stay \(item.picture.width)×\(item.picture.height).")
            }
            if picturesDark {
                try replaceDarkPicture(item, rgba: ImageCodec.rgba(img))
            } else if try editor.replacePicture(item, rgba: ImageCodec.rgba(img)) {
                edited()
            }
        } catch { fail("Cannot replace the picture", error) }
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
            fail("Cannot apply the text", error)
            return false
        }
    }

    // MARK: iPod

    func refreshIPods() async {
        do {
            ipods = try await Task.detached { try Device.findIPods() }.value
            if selectedIPod == nil || !ipods.contains(where: { $0.disk == selectedIPod }) { selectedIPod = ipods.first?.disk }
            unsupportedIPods.formIntersection(ipods)
        } catch { fail("Cannot list disks", error) }
        refreshBackups()
    }

    func ejectIPod() async {
        guard let ipod = currentIPod else { return }
        do {
            try await work("Ejecting \(ipod.volumeName ?? ipod.mediaName)…") { try Device.eject(ipod) }
            thumbnailStatus = nil
            playlistArt = []
            playlistArtChanged = false
            await refreshIPods()
        } catch { fail("Cannot eject the iPod", error) }
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
            let r = try await runBackup(ipod)
            guard r.ok else { throw FirmwareError(r.message, code: r.code) }
            alert = AlertInfo(title: "Backup saved", message: "\(r.message)\n\n\(r.backup?.file ?? "")")
        } catch { fail("Backup failed", error) }
    }

    /// Step 1 of flashing: dry run (no writes) to show exactly what would change.
    func prepareFlash(image: URL, reason: String) async {
        guard let ipod = currentIPod else { return }
        busy = "Checking the iPod (nothing is written yet)…"
        defer { busy = nil }
        do {
            var reason = reason
            var r = try await runFlash(ipod, image: image, reason: reason, dryRun: true)
            if !r.ok, r.code == HelperResult.firmwareUnreadable, reason == "restore" {
                // An interrupted write left the iPod's firmware unreadable: the normal restore cannot compare with it.
                reason = "rescue"
                r = try await runFlash(ipod, image: image, reason: reason, dryRun: true)
            }
            guard r.ok else { throw FirmwareError(r.message, code: r.code) }
            if r.ranges?.isEmpty ?? true {
                alert = AlertInfo(title: "Nothing to do", message: r.message)
            } else {
                flashPlan = FlashPlan(ipod: ipod, image: image, reason: reason, result: r)
            }
        } catch { fail("Cannot flash", error) }
    }

    /// Step 2: the helper backs up the current partition, writes only changed blocks, and verifies.
    func performFlash(_ plan: FlashPlan) async {
        flashPlan = nil
        busy = "Backup, write and check in progress… Do not disconnect the iPod."
        defer { busy = nil; refreshBackups() }
        do {
            let r = try await runFlash(plan.ipod, image: plan.image, reason: plan.reason, dryRun: false)
            guard r.ok else { throw FirmwareError(r.message, code: r.code) }
            if plan.reason == "flash" { isDirty = false }
            alert = AlertInfo(title: plan.reason == "flash" ? "Flashed" : "Restored",
                              message: "\(r.message)\nBackup taken first: \(r.backup?.file ?? "-")\n\nEject the iPod. If the iPod does not start, reset it (hold Menu and Select). Then hold Select and Play for disk mode, and restore a backup in iPodFirm.")
        } catch { fail("Flash failed", error) }
    }

    func flashEdited() async {
        guard let editor else { return }
        let staging = Self.supportDir.appendingPathComponent("Staging/flash.bin")
        do {
            try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Self.outputPartition(editor, activePatches, appearance: activeAppearance, version: activeVersion)).write(to: staging, options: .atomic)
            await prepareFlash(image: staging, reason: "flash")
        } catch { fail("Cannot flash", error) }
    }

    func restore(_ b: BackupInfo) async { await prepareFlash(image: backupURL(b), reason: "restore") }

    /// Last resort, e.g. for a damaged partition table: Finder rewrites the whole iPod from Apple's .ipsw.
    func restoreWithFinder() async {
        do {
            let ipsw = try await ensureAppleIPSW()
            NSWorkspace.shared.activateFileViewerSelecting([ipsw])
            showFinderRestoreHelp = true
        } catch { fail("Cannot get the Apple firmware", error) }
    }

    // MARK: emulator

    func exportIPSW() {
        guard let editor else { return }
        let s = NSSavePanel()
        s.nameFieldStringValue = "custom-iPod_25.1.3.ipsw"
        guard s.runModal() == .OK, let out = s.url else { return }
        let patches = activePatches, appearance = activeAppearance, version = activeVersion
        Task {
            do {
                let original = try await ensureAppleIPSW()
                try await work("Writing .ipsw…") {
                    let osos = try Self.outputOSOS(editor, patches, appearance: appearance, version: version)
                    try IPSW.repack(original: original, firmware: IPSW.firmware(original: original, withOSOS: osos), to: out)
                }
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch { fail("Cannot write the .ipsw", error) }
        }
    }

    /// Build the emulator drive from the current edits and boot it in the in-app preview.
    func runInEmulator(_ emu: EmulatorManager, _ session: EmulatorSession) {
        guard let editor else { return }
        let patches = activePatches, appearance = activeAppearance, version = activeVersion
        let library = EmulatorManager.Library.current
        session.start { [weak self] in
            guard let self else { return }
            let original = try await self.ensureAppleIPSW()
            let (fw, ososLength) = try await Task.detached { () -> ([UInt8], Int) in
                let osos = try Self.outputOSOS(editor, patches, appearance: appearance, version: version)
                return (try IPSW.firmware(original: original, withOSOS: osos), osos.count)
            }.value
            try await emu.prepare(firmware: fw, ososLength: ososLength, originalIPSW: original, library: library)
        }
    }
}
