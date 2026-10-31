import AppKit
import CryptoKit
import Foundation
import IPodFWKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Firmware", pictures = "Pictures", strings = "Text", patches = "Patches", games = "Games", ipod = "iPod", emulator = "Emulator"
    var id: String { rawValue }
    /// The panes in the Tools section of the sidebar. The iPod pane has its own section.
    static let tools: [Pane] = [.overview, .pictures, .strings, .patches, .games, .emulator]
    var symbol: String {
        switch self {
        case .overview: "cpu"
        case .pictures: "photo.on.rectangle"
        case .strings: "textformat"
        case .patches: "puzzlepiece.extension"
        case .games: "gamecontroller"
        case .ipod: "ipod"
        case .emulator: "play.display"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: Pane = .overview
    @Published var editor: FirmwareEditor?
    @Published var fileURL: URL?
    /// The file of the last Save As. Save writes to this file.
    var saveURL: URL?
    @Published var sourceIPSW: URL?
    @Published var openedFromBackup = false
    @Published var isDirty = false
    /// The count of changes in the Text pane that the user did not apply.
    @Published var pendingStringChanges = 0
    /// true: the user agreed to discard the unsaved work. A close of the last window also quits the
    /// app, so the app asks only one time.
    var discardConfirmed = false
    @Published var revision = 0
    @Published var busy: String?
    /// The fraction of the firmware download that is complete.
    @Published var downloadProgress: Double?
    /// The firmware download. The busy overlay can cancel it.
    @Published var downloadTask: Task<(URL, URLResponse), Error>?
    @Published var alert: AlertInfo?
    @Published var ipods: [IPodDisk] = []
    @Published var selectedIPod: String?
    /// iPods for which the helper gave HelperResult.unsupportedIPod (for example an iPod classic).
    @Published var unsupportedIPods: Set<IPodDisk> = []
    /// The name of the connected iPod that iTunes set. Nil if the iPod has no music database.
    @Published var ipodLibraryName: String?
    @Published var backups: [BackupInfo] = []
    @Published var flashPlan: FlashPlan?
    @Published var hasFullDiskAccess = AppModel.checkFullDiskAccess()
    @Published var helperStatus: SMAppService.Status = HelperClient.serviceStatus
    /// The result of the last `status` call to the helper. macOS can show the helper as enabled
    /// when launchd cannot start it. Only a reply shows that Touch ID operates.
    @Published var helperReply: HelperReply = .unknown
    @Published var patches: [PatchInfo] = PatchSpec.visible(AppModel.patchLibrary.list(),
                                                            showTests: UserDefaults.standard.bool(forKey: "showTestPatches"))
    /// The disclaimer sheet. It shows at the first launch, and again after a change of `Disclaimer.version`.
    @Published var showDisclaimer = !Disclaimer.accepted
    /// Help > Show Disclaimer: the disclaimer again, with only a Close button.
    @Published var showDisclaimerReview = false
    /// Help > Thanks…: the people who reported problems or supplied fixes.
    @Published var showThanks = false
    /// Settings > Patches > Enable Test Patches. Off: the Patches pane hides the test patches, and a
    /// build does not include them.
    @Published var showTestPatches = UserDefaults.standard.bool(forKey: "showTestPatches") {
        didSet {
            UserDefaults.standard.set(showTestPatches, forKey: "showTestPatches")
            reloadPatches()
        }
    }
    @Published var enabledPatches: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledPatches") ?? []) {
        didSet { UserDefaults.standard.set(Array(enabledPatches), forKey: "enabledPatches"); switchesChanged(oldValue != enabledPatches) }
    }
    /// The selected choice of each patch option: patch name -> option id -> value (see PatchSpec.Option).
    @Published var patchOptions: [String: [String: Int]] =
        (UserDefaults.standard.dictionary(forKey: "patchOptions") as? [String: [String: Int]]) ?? [:] {
        didSet { UserDefaults.standard.set(patchOptions, forKey: "patchOptions"); switchesChanged(oldValue != patchOptions) }
    }
    @Published var appearance: Appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .light {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance"); switchesChanged(oldValue != appearance) }
    }
    /// The folder of the games that the user chooses. The folder holds the games, or the
    /// folder `iPod_Control` of an iPod.
    @Published var gamesSourceFolder: URL?
    /// The games of the folder that the user chose.
    @Published var gamesLibrary: [GameLibraryItem] = []
    /// The GUID of each game that the user selected. Empty: the user selects no game.
    @Published var selectedGameFolders: Set<String> = []
    /// The state of the last copy of the games.
    @Published var gameInstallStatus = ""
    /// The owner's key file IC-Info.sidb, or nil. The install copies it with the games.
    @Published var gameKeyFile: URL?
    /// The GUID of each game in the folder games_RO of the connected iPod.
    @Published var ipodGames: [String] = []
    /// The GUID of each game that the owner selected for the removal.
    @Published var selectedIPodGames: Set<String> = []
    /// True when the confirmation sheet of the removal is open.
    @Published var showRemoveGamesSheet = false
    /// The state of the last removal of the games.
    @Published var gameRemoveStatus = ""
    /// True if the owner changed a patch switch, an option or the appearance after the last flash, restore
    /// or read of the iPod. Then a new read of the iPod does not change the switches (`applyIPodState`).
    @Published var switchesChangedSinceSync = UserDefaults.standard.bool(forKey: "switchesChangedSinceSync") {
        didSet { UserDefaults.standard.set(switchesChangedSinceSync, forKey: "switchesChangedSinceSync") }
    }
    /// True while the app sets the switches from the iPod: this is not a change by the owner.
    var mirroring = false
    private func switchesChanged(_ changed: Bool) {
        if changed && !mirroring && !switchesChangedSinceSync { switchesChangedSinceSync = true }
    }
    /// The patches on the connected iPod (nil: not read).
    @Published var ipodState: IPodPatchState?
    /// The result of the last read of the iPod, for the Patches pane and the iPod pane.
    @Published var ipodReadStatus: String?
    @Published var themes: [ThemeFile] = AppModel.loadThemes()
    @Published var selectedThemeName: String? = UserDefaults.standard.string(forKey: "darkTheme") {
        didSet { UserDefaults.standard.set(selectedThemeName, forKey: "darkTheme"); switchesChanged(oldValue != selectedThemeName) }
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
    /// The New Patch or Edit Patch sheet.
    @Published var patchEditor: PatchEditorState?
    /// The code of each user patch that has changes that are not saved, by patch name (PatchCodeView.swift).
    @Published var codeDrafts: [String: PatchCode] = [:]
    /// The result of the last Check Code, by patch name.
    @Published var codeChecks: [String: PatchCodeCheck] = [:]
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
    /// The text of the playback log (nil: not read; empty: the file has no log).
    @Published var playbackLog: String?
    /// The log files on the connected iPod.
    @Published var ipodLogs: [IPodLogFile] = []
    /// The log in `IPodLogSheet`.
    @Published var shownLog: IPodLogFile?
    /// The playlists of the connected iPod and their thumbnails (album-art patch).
    @Published var playlistArt: [MusicImport.PlaylistArt] = []
    /// True after a change to a playlist image that is not yet in the thumbnail file on the iPod.
    @Published var playlistArtChanged = false
    /// The playlists of the connected iPod that can go into a folder (playlist-folders patch).
    @Published var folderPlaylists: [ITunesDB.PlaylistEntry] = []
    /// The folders in the editor, and the folders in the file on the iPod.
    @Published var playlistFolders = PlaylistFolders()
    @Published var savedPlaylistFolders = PlaylistFolders()
    @Published var playlistFoldersStatus: String?
    @Published var helperSetupError: String?
    @AppStorage("requireTouchID") var requireTouchID = true
    /// Settings > Updates: ask GitHub for a newer release at each launch.
    @AppStorage("checkForUpdates") var checkForUpdates = true
    /// The release that the user skipped with "Skip This Version". The launch check ignores it.
    @AppStorage(UpdateNotifier.skippedKey) var skippedUpdateVersion = ""
    /// A newer release, if macOS does not allow the notification. The app shows an alert instead.
    @Published var availableUpdate: UpdateCheck.Release?
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

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        /// For a fault: the full error, the steps and the state of the app (`faultDetails`). Then the
        /// alert shows Report on GitHub… and Save Log….
        var details: String?
        var isFault: Bool { details != nil }
    }
    struct FlashPlan: Identifiable {
        let id = UUID()
        let ipod: IPodDisk
        let image: URL
        let reason: String
        let result: HelperResult
        /// MiMusic was open when iPodFirm made the plan.
        var musicAppRunning = false
    }

    nonisolated static let supportDir: URL = {
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

    /// The state of the iPod in the sidebar.
    /// The name of the connected iPod: the name in its music database, or else the name of its volume.
    var currentIPodName: String? { currentIPod.map { ipodLibraryName ?? $0.volumeName ?? $0.mediaName } }

    var currentIPodStatus: String {
        guard let ipod = currentIPod else { return "Not Connected" }
        return currentIPodIsUnsupported ? "Not Supported" : ipodLibraryName ?? ipod.volumeName ?? ipod.mediaName
    }

    // MARK: helpers

    /// Shows a fault. The log gets the full error. The alert gives Report on GitHub… and Save Log….
    func fail(_ title: String, _ error: Error) {
        // The Cancel button of the download is not a fault.
        guard !Self.isCancellation(error) else { return }
        let details = faultDetails(error)
        AppLog.error("\(title)\n" + details)
        if (error as? FirmwareError)?.code == HelperResult.fullDiskAccess {
            hasFullDiskAccess = false
            showFullDiskAccessHelp = true
            return
        }
        var title = title
        if (error as? FirmwareError)?.code == HelperResult.unsupportedIPod, let ipod = currentIPod {
            unsupportedIPods.insert(ipod)
            title = "Unsupported iPod"
        }
        var message = error.localizedDescription
        if let step = AppLog.lastStep() { message += "\n\nLast step: \(step)" }
        alert = AlertInfo(title: title, message: message, details: details)
    }

    /// The text of a fault for the log and the GitHub report: the full error, the last steps and the
    /// state of the app. It has no serial number, no volume name and no home folder path.
    func faultDetails(_ error: Error) -> String {
        let steps = AppLog.recentSteps(15).map { "  " + $0 }.joined(separator: "\n")
        return AppLog.describe(error) + "\n\nLast steps:\n" + (steps.isEmpty ? "  none" : steps) + "\n\n" + diagnosticSnapshot()
    }

    /// The state of the app and of the iPod, for a fault report.
    func diagnosticSnapshot() -> String {
        var lines = ["iPodFirm \(version), \(AppLog.systemDescription)"]
        if let editor {
            let apple = editor.originalOSOSHash == Self.appleFirmwareSHA256 ? "Apple 1.3" : "not Apple 1.3"
            lines.append("Open file: \(fileURL?.lastPathComponent ?? "-") (osos \(apple), \(editor.osos.count) bytes, edited: \(isDirty))")
        } else {
            lines.append("Open file: none")
        }
        if let ipod = currentIPod {
            lines.append("iPod: \(ipod.mediaName), \(ipod.size) bytes, block size \(ipod.blockSize)" +
                         (currentIPodIsUnsupported ? ", not supported" : ""))
        } else {
            lines.append("iPod: none")
        }
        if let state = ipodState {
            let found = state.detections.sorted { $0.key < $1.key }.compactMap { name, d -> String? in
                if case .installed(let v) = d { return "\(name) \(v ?? "?")" }
                return d == .unknown ? "\(name) (unknown)" : nil
            }
            lines.append("Patches on the iPod: \(found.isEmpty ? "none" : found.joined(separator: ", "))")
        }
        let on = patches.filter { enabledPatches.contains($0.spec.name) }.map { p -> String in
            let o = patchOptions[p.spec.name].map { $0.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") }
            return "\(p.spec.name) \(p.spec.versionText)" + (o.map { " [\($0)]" } ?? "")
        }
        lines.append("Patches on in the app: \(on.isEmpty ? "none" : on.joined(separator: ", "))")
        lines.append("Appearance: \(appearance.rawValue), theme: \(selectedThemeName ?? "-"), margin: \(ThemeImport.OSOSMargin.current.rawValue), test patches: \(showTestPatches)")
        lines.append("Helper: \(helperStatus), reply: \(helperReply), Full Disk Access: \(hasFullDiskAccess), Touch ID: \(requireTouchID)")
        return AppLog.redact(lines.joined(separator: "\n"))
    }

    /// Help > Open Log: opens the most recent log in the default app. If no app opens it, Finder shows it.
    func openLog() {
        guard let url = AppLog.fileURL, FileManager.default.fileExists(atPath: url.path) else {
            alert = AlertInfo(title: "No log found", message: "iPodFirm has no log file. Restart iPodFirm. Then try again.")
            return
        }
        if !NSWorkspace.shared.open(url) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    /// Help > Save Log…, and Save Log… in the alert of a fault. Returns the file, or nil.
    @discardableResult
    func saveLog() -> URL? {
        let s = NSSavePanel()
        s.nameFieldStringValue = AppLog.fileName()
        s.allowedContentTypes = [.plainText]
        s.message = "Save the log of iPodFirm as a text file. Then attach the file to a report."
        guard s.runModal() == .OK, let url = s.url else { return nil }
        let text = diagnosticSnapshot() + "\n\n" + AppLog.fullText()
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            AppLog.error("Cannot save the log\n" + AppLog.describe(error))
            alert = AlertInfo(title: "Cannot Save the Log", message: error.localizedDescription)
            return nil
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    /// Report on GitHub… in the alert of a fault, and Help > Report a Problem on GitHub…. Saves the
    /// log, then opens a new issue in the browser. The user drags the file into the issue.
    func reportOnGitHub(_ fault: AlertInfo?) {
        let file = saveLog()
        let steps = AppLog.recentSteps(15).map { "  " + $0 }.joined(separator: "\n")
        let details = fault?.details ?? diagnosticSnapshot() + "\n\nLast steps:\n" + (steps.isEmpty ? "  none" : steps)
        NSWorkspace.shared.open(AppLog.issueURL(title: fault?.title ?? "Problem report", message: fault?.message ?? "",
                                                details: details, fileName: file?.lastPathComponent))
    }

    /// Reading the system TCC database is only possible with Full Disk Access.
    nonisolated static func checkFullDiskAccess() -> Bool {
        let probe = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let h = FileHandle(forReadingAtPath: probe) else { return false }
        try? h.close()
        return true
    }

    enum HelperReply: Equatable {
        case unknown, checking, noReply
        case replied(version: Int)
    }

    /// True if the helper is enabled and replied to the last check. Only then the app uses Touch ID.
    var helperWorks: Bool {
        if helperStatus == .enabled, case .replied = helperReply { return true }
        return false
    }

    func recheckFullDiskAccess() {
        hasFullDiskAccess = Self.checkFullDiskAccess()
        helperStatus = HelperClient.serviceStatus
        guard helperStatus == .enabled else { helperReply = .unknown; return }
        helperReply = .checking
        Task {
            // The helper does the disk access, so its own permission is what counts.
            if let s = try? await HelperClient.status() {
                hasFullDiskAccess = s.hasFullDiskAccess
                helperReply = .replied(version: s.version)
            } else {
                helperReply = .noReply
            }
        }
    }

    /// Unregister the helper and register it again. This gives launchd a new registration
    /// when the old one refers to an app that is not there (spawn failed, EX_CONFIG).
    func repairHelper() {
        helperReply = .checking
        Task {
            try? await HelperClient.unregister()
            setUpHelper()
        }
    }

    /// Register the Touch ID helper; macOS then asks for approval in Login Items once.
    func setUpHelper() {
        do {
            try HelperClient.register()
            helperSetupError = nil
        } catch {
            AppLog.warning("Cannot register the helper\n" + AppLog.describe(error))
            helperSetupError = error.localizedDescription
        }
        helperStatus = HelperClient.serviceStatus
        if helperStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        recheckFullDiskAccess()
    }

    func removeHelper() {
        Task {
            try? await HelperClient.unregister()
            helperStatus = HelperClient.serviceStatus
        }
    }

    /// Ask the helper for a reply, and record the result for the Settings window.
    private func helperResponds() async -> Bool {
        guard HelperClient.isEnabled else { return false }
        let ok = await HelperClient.isResponding()
        if !ok { helperReply = .noReply } else if case .replied = helperReply {} else { recheckFullDiskAccess() }
        return ok
    }

    // Route privileged work through the daemon (Touch ID) when it replies, else the password prompt.
    private func runBackup(_ ipod: IPodDisk) async throws -> HelperResult {
        if await helperResponds() {
            AppLog.step("Helper (daemon): back up \(ipod.disk)")
            return logged(try await HelperClient.backup(disk: ipod.disk, backupDir: Self.backupDir))
        }
        AppLog.step("Helper (password): back up \(ipod.disk)")
        return logged(try await Privileged.run(helperArgs("backup", ipod)))
    }

    /// Writes the result of the helper to the log. On a fault, the log also gets the detail of the helper.
    private func logged(_ r: HelperResult) -> HelperResult {
        if r.ok {
            AppLog.info("Helper result: \(r.message)")
        } else {
            AppLog.warning("Helper fault: \(r.message) (code \(r.code ?? "none"))\n\(r.detail ?? "No detail from the helper.")")
        }
        return r
    }

    /// reason is "flash", "restore", or "rescue" (a restore onto a damaged firmware partition).
    private func runFlash(_ ipod: IPodDisk, image: URL, reason: String, dryRun: Bool) async throws -> HelperResult {
        let rescue = reason == "rescue"
        let what = "\(reason) of \(image.lastPathComponent) on \(ipod.disk)\(dryRun ? " (dry run)" : "")"
        if await helperResponds() {
            AppLog.step("Helper (daemon): " + what)
            if !dryRun && requireTouchID {
                try await HelperClient.authenticate(reason == "flash" ? "write new firmware to your iPod" : "restore a backup to your iPod")
            }
            if rescue {
                return logged(try await HelperClient.rescueRestore(disk: ipod.disk, image: image, backupDir: Self.backupDir, dryRun: dryRun))
            }
            return logged(try await HelperClient.flash(disk: ipod.disk, image: image, backupDir: Self.backupDir, reason: reason, dryRun: dryRun))
        }
        AppLog.step("Helper (password): " + what)
        let args = rescue ? helperArgs("rescue", ipod) + ["--image", image.path]
                          : helperArgs("flash", ipod) + ["--image", image.path, "--reason", reason]
        return logged(try await Privileged.run(args + (dryRun ? ["--dry-run"] : [])))
    }

    func openFullDiskAccessSettings() {
        let urls = ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        for u in urls where NSWorkspace.shared.open(URL(string: u)!) { return }
    }

    func work<T>(_ label: String, _ body: @escaping () throws -> T) async throws -> T {
        AppLog.step(label)
        busy = label
        defer { busy = nil }
        return try await Task.detached(priority: .userInitiated) { try body() }.value
    }

    func edited() {
        isDirty = true
        revision += 1
    }

    // MARK: opening & saving

    /// true: a quit loses work: the firmware, text that is not applied, patch code or playlist folders.
    var hasUnsavedWork: Bool {
        isDirty || pendingStringChanges > 0 || !codeDrafts.isEmpty || playlistFolders != savedPlaylistFolders
    }

    func confirmDiscard() -> Bool {
        guard isDirty else { return true }
        return askDiscard("The firmware that you edit has changes that you did not save or flash.")
    }

    /// Asks before a quit or a close of the window.
    func confirmQuit() -> Bool {
        guard hasUnsavedWork, !discardConfirmed else { return true }
        discardConfirmed = askDiscard("iPodFirm has changes that you did not save, apply, flash or write to the iPod.")
        return discardConfirmed
    }

    /// Cancel is the default button: Return must not discard the work.
    private func askDiscard(_ text: String) -> Bool {
        let a = NSAlert()
        a.messageText = "Discard Your Unsaved Changes?"
        a.informativeText = text
        a.addButton(withTitle: "Cancel")
        a.addButton(withTitle: "Discard").hasDestructiveAction = true
        return a.runModal() == .alertSecondButtonReturn
    }

    /// `stay`: keep the current pane. The user opened the firmware from a pane to continue the work there.
    func open(_ url: URL, fromBackup: Bool = false, stay: Bool = false) async {
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
            saveURL = nil
            isDirty = false
            revision += 1
            if !stay { section = .overview }
        } catch {
            fail("Cannot Open \(url.lastPathComponent)", error)
        }
    }

    func openPanel(stay: Bool = false) {
        let p = NSOpenPanel()
        p.allowedContentTypes = ["ipsw", "bin"].compactMap { UTType(filenameExtension: $0) }
        p.message = "Choose an Apple .ipsw, a firmware .bin, or an iPod backup"
        p.directoryURL = Self.backupDir
        if p.runModal() == .OK, let url = p.url { Task { await open(url, stay: stay) } }
    }

    /// Writes to the file of the last Save As. The first save shows the panel, because the app never
    /// overwrites the file that it opened.
    func save() {
        if let saveURL { write(to: saveURL) } else { saveAs() }
    }

    func saveAs() {
        guard editor != nil else { return }
        let p = NSSavePanel()
        p.nameFieldStringValue = "custom-firmware.bin"
        p.message = "Save the customised firmware partition image"
        guard p.runModal() == .OK, let url = p.url else { return }
        guard !url.path.hasPrefix(Self.backupDir.path) else {
            alert = AlertInfo(title: "Not Saved", message: "Backups are never overwritten. Choose a location outside the Backups folder.")
            return
        }
        write(to: url)
    }

    private func write(to url: URL) {
        guard let editor else { return }
        do {
            try Data(Self.outputPartition(editor, activePatches, appearance: activeAppearance, version: activeVersion, list: activeList)).write(to: url, options: .atomic)
            isDirty = false
            saveURL = url
            fileURL = url
        } catch { fail("Cannot Save", error) }
    }

    static let cachedAppleIPSW = supportDir.appendingPathComponent("Firmware/iPod_25.1.3.ipsw")

    nonisolated static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func downloadAppleFirmware(stay: Bool = false) async {
        do { await open(try await ensureAppleIPSW(), stay: stay) } catch { fail("Download Failed", error) }
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
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
                let watcher = DownloadWatcher { [weak self] fraction in
                    Task { @MainActor in if self?.downloadTask != nil { self?.downloadProgress = fraction } }
                }
                let task = Task { try await URLSession.shared.download(from: IPSW.videoFirmware13, delegate: watcher) }
                downloadTask = task
                downloadProgress = 0
                defer { downloadTask = nil; downloadProgress = nil }
                let (tmp, _) = try await task.value
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
        var out = files.filter { $0.pathExtension == "ipodtheme" }
            .compactMap { url in (try? ImportedTheme.load(url)).map { ThemeFile(name: $0.name, url: url, theme: $0) } }
        // The themes that come with the app (Contents/Resources/Themes). The app
        // copies a built-in theme into the folder of the owner at the first start,
        // so the owner can change it like an imported theme.
        let bundled = Bundle.main.resourceURL.map { $0.appendingPathComponent("Themes") }
        let builtIn = (try? FileManager.default.contentsOfDirectory(at: bundled!, includingPropertiesForKeys: nil)) ?? []
        for url in builtIn.filter({ $0.pathExtension == "ipodtheme" }) {
            guard let theme = try? ImportedTheme.load(url) else { continue }
            if out.contains(where: { $0.name == theme.name }) { continue }
            let dest = themesDir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                // At the first start, the folder is not there. Without it, the copy fails (issue 1).
                try? FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: url, to: dest)
                if let copied = try? ImportedTheme.load(dest) {
                    out.append(ThemeFile(name: copied.name, url: dest, theme: copied))
                }
            } else if let copied = try? ImportedTheme.load(dest) {
                out.append(ThemeFile(name: copied.name, url: dest, theme: copied))
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
        do { try saveTheme(theme, to: file.url) } catch { fail("Cannot Save the Theme", error) }
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
            } catch { fail("Cannot Import the Theme", error) }
        }
    }

    func deleteTheme(_ t: ThemeFile) {
        try? FileManager.default.removeItem(at: t.url)
        themes = Self.loadThemes()
        if themes.isEmpty, appearance != .light { appearance = .light }
    }

    // MARK: updates

    /// The app version without the build number, for example "0.1.178".
    var shortVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    /// Ask GitHub for the newest release. A newer release gives a macOS notification.
    /// At the launch (`manual` false), an error gives no alert, and a skipped version gives no notification.
    /// iPodFirm > Check for Updates… (`manual` true) shows each result.
    func checkForUpdate(manual: Bool) async {
        if !manual { guard checkForUpdates, Disclaimer.accepted else { return } }
        let release: UpdateCheck.Release
        do {
            release = try await UpdateCheck.fetchLatest()
        } catch {
            if manual { fail("Cannot Check for Updates", error) }
            return
        }
        guard UpdateCheck.isNewer(release.version, than: shortVersion) else {
            if manual {
                alert = AlertInfo(title: "iPodFirm Is Up to Date",
                                  message: "Version \(shortVersion) is the newest version on GitHub.")
            }
            return
        }
        if !manual, release.version == skippedUpdateVersion { return }
        if await !UpdateNotifier.shared.notify(release, local: shortVersion) { availableUpdate = release }
    }

    // MARK: patches

    /// Record the size of each user patch that an earlier version installed without a size. One time at the start.
    func recordMissingPatchSizes() async {
        let library = Self.patchLibrary
        let changed = await Task.detached { library.recordMissingSizes() }.value
        if !changed.isEmpty { reloadPatches() }
    }

    func reloadPatches() {
        patches = PatchSpec.visible(Self.patchLibrary.list(), showTests: showTestPatches)
        if let s = patchSelection, s != "appearance", s != "version", !patches.contains(where: { $0.spec.name == s }) {
            patchSelection = "appearance"
        }
    }

    /// The turned-on patches that change the same place as `patch`.
    func conflicts(_ patch: PatchInfo) -> [(PatchInfo, String)] {
        Patcher.conflicts([patch] + activePatches.filter { $0.spec.name != patch.spec.name })
            .filter { $0.0.spec.name == patch.spec.name }.map { ($0.1, $0.2) }
    }

    /// Turn a patch on or off. A patch that conflicts with a turned-on patch stays off. A patch turns
    /// on the patches that it needs (`needs`), and a patch that is turned off turns off the patches
    /// that need it.
    func setPatch(_ patch: PatchInfo, on: Bool) {
        guard on else {
            var off = [patch.spec.name]
            while let name = off.popLast() {
                enabledPatches.remove(name)
                off += patches.filter { enabledPatches.contains($0.spec.name) && ($0.spec.needs ?? []).contains(name) }.map(\.spec.name)
            }
            return
        }
        var add: [PatchInfo] = []
        var todo = [patch]
        while let p = todo.popLast() {
            guard !enabledPatches.contains(p.spec.name), !add.contains(where: { $0.spec.name == p.spec.name }) else { continue }
            add.append(p)
            for name in p.spec.needs ?? [] {
                guard let needed = patches.first(where: { $0.spec.name == name }) else {
                    alert = AlertInfo(title: "\(patch.spec.displayTitle) Cannot Be Turned On",
                                      message: "The patch needs the patch \"\(name)\". Install it first.")
                    return
                }
                todo.append(needed)
            }
        }
        for p in add {
            if let (other, place) = conflicts(p).first {
                alert = AlertInfo(title: "\(patch.spec.displayTitle) Cannot Be Turned On",
                                  message: "\"\(p.spec.displayTitle)\" changes the same place as \"\(other.spec.displayTitle)\" (\(place)). Turn off \"\(other.spec.displayTitle)\" first.")
                return
            }
        }
        for p in add { enabledPatches.insert(p.spec.name) }
    }

    /// Examine a .ipodpatch file or a patch folder, then show the install sheet.
    func installPatch(from url: URL) async {
        section = .patches
        let library = Self.patchLibrary, existing = patches
        do {
            pendingInstall = try await work("Examining the patch \(url.lastPathComponent)…") { try library.inspect(url, existing: existing) }
        } catch { fail("Cannot Open the Patch", error) }
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
        } catch { fail("Cannot Install the Patch", error) }
    }

    func cancelInstall(_ c: PatchCandidate) {
        pendingInstall = nil
        if let staging = c.staging { Self.patchLibrary.cleanStaging(staging) }
    }

    // MARK: New Patch, Edit Patch

    func newPatch() {
        section = .patches
        patchEditor = PatchEditorState(draft: PatchDraft(), patch: nil)
    }

    func editPatch(_ patch: PatchInfo) {
        guard patch.source == .user else { return }
        section = .patches
        patchEditor = PatchEditorState(draft: PatchDraft(spec: patch.spec), patch: patch)
    }

    /// Make the new patch, or write the edit. Then select the patch.
    func savePatchEditor(_ state: PatchEditorState, _ draft: PatchDraft) {
        let library = Self.patchLibrary
        if let patch = state.patch {
            do {
                let version = try library.edit(patch, with: draft)
                patchEditor = nil
                reloadPatches()
                patchSelection = patch.spec.name
                if enabledPatches.contains(patch.spec.name) {
                    alert = AlertInfo(title: "Patch Saved",
                                      message: "The patch is now version \(version). Flash the iPod again to put the new text on it.")
                }
            } catch { fail("Cannot Save the Patch", error) }
            return
        }
        Task {
            do {
                let folder = try await work("Making the patch…") { try library.create(draft) }
                patchEditor = nil
                reloadPatches()
                patchSelection = folder.lastPathComponent
                let steps = draft.kind == .code
                    ? ["1. Write the code in the section \"C Code\" below the patch.",
                       "2. Add the firmware functions and the hooks.",
                       "3. Click Check Code, then click Save.",
                       "4. Click Export Patch… to make a file for other people."]
                    : ["1. Add the byte changes in the section \"Byte Changes\" below the patch.",
                       "2. Click Check Code, then click Save.",
                       "3. Click Export Patch… to make a file for other people."]
                alert = AlertInfo(title: "Patch Made",
                                  message: steps.joined(separator: "\n")
                                    + "\n\ndocs/patch-system.md in the iPodFirm source code tells how to write a patch.")
            } catch { fail("Cannot Make the Patch", error) }
        }
    }

    func removePatch(_ patch: PatchInfo) {
        do {
            try Self.patchLibrary.remove(patch)
            enabledPatches.remove(patch.spec.name)
            reloadPatches()
        } catch { fail("Cannot Remove the Patch", error) }
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
            } catch { fail("Cannot Export the Patch", error) }
        }
    }

    func showPatchesFolder() {
        try? FileManager.default.createDirectory(at: Self.patchLibrary.userDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.patchLibrary.userDir)
    }

    /// Write the files of an action (patch.json "ui") on the mounted iPod.
    func runPatchAction(_ patch: PatchInfo, _ action: PatchUI.Action) {
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        do {
            for w in action.write where PatchUI.isSafePath(w.path) && w.data.count <= PatchUI.maxWrite {
                let url = volume.appendingPathComponent(w.path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try w.data.write(to: url, options: .atomic)
            }
            if action.write.contains(where: { $0.path == Self.usbProbeLogFile }) { usbProbeLog = nil }
            if action.write.contains(where: { $0.path == Self.playbackLogFile }) { playbackLog = nil }
            refreshIPodLogs()
            patchActionStatus[patch.spec.name] = "\(action.status ?? "\(action.title): complete.") (\(Date().formatted(date: .omitted, time: .shortened)))"
        } catch { fail("Cannot Write the File on the iPod", error) }
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
        } catch { fail("Cannot Write the File on the iPod", error) }
    }

    /// The space after Apple's image for the switched-on patches and the appearance (nil: not known).
    @Published var spaceUse: Patcher.SpaceUse?
    /// The code size of each patch, by folder and version: the app compiles each patch one time.
    private var codeSizes = [String: Int]()

    /// Measure the space of the current selection: build the appearance, and add the code sizes and
    /// the menus of the switched-on patches. The Patches pane calls this after each change.
    func refreshSpaceUse() async {
        guard let editor else { spaceUse = nil; return }
        let patches = activePatches, appearance = activeAppearance, known = codeSizes
        let listSize = (try? activeList.encoded().count) ?? 0
        let result = try? await Task.detached(priority: .utility) { () -> ([String: Int], Patcher.SpaceUse) in
            let osos = try Self.outputOSOS(editor, [], appearance: appearance, version: nil)
            var sizes = known, list = [(patch: PatchInfo, size: Int)]()
            for p in patches {
                let key = p.folder.path + "|" + (p.spec.version ?? "")
                let size = try sizes[key] ?? Patcher.codeSize(p)
                sizes[key] = size
                list.append((p, size))
            }
            return (sizes, Patcher.spaceUse(osos: osos, patches: list, listSize: listSize))
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
    /// `list` is the iPodFirm list (`FirmwareManifest`): the build writes it after the patches.
    nonisolated static func outputOSOS(_ editor: FirmwareEditor, _ patches: [PatchInfo], appearance: AppearanceBuild?,
                                       version: FirmwareVersion?, list: FirmwareManifest? = nil) throws -> [UInt8] {
        var osos = editor.osos
        switch appearance {
        case .dark(let theme):
            AppLog.step("Build: apply the dark theme \(theme.name)")
            try theme.apply(to: &osos, originalSHA256: editor.originalOSOSHash)
        case .switchOnIPod(let theme, let patch):
            AppLog.step("Build: add Dark Mode with the theme \(theme.name) and the patch \(patch.spec.name) \(patch.spec.versionText)")
            osos = try DarkMode.build(partition: editor.partition, osos: osos, theme: theme, patch: patch,
                                      originalSHA256: editor.originalOSOSHash).0
        case nil:
            break
        }
        if !patches.isEmpty || list != nil {
            osos = try Patcher.apply(patches, to: osos, originalSHA256: editor.originalOSOSHash, list: try list?.encoded())
        }
        if let version {
            AppLog.step("Build: write the firmware version")
            try FirmwareVersion.apply(version, to: &osos)
        }
        return osos
    }

    /// The firmware partition to save or flash: the edits plus the theme and the switched-on patches.
    /// A larger osos moves rsrc (see FirmwarePartition.makeRoom).
    nonisolated static func outputPartition(_ editor: FirmwareEditor, _ patches: [PatchInfo], appearance: AppearanceBuild?,
                                            version: FirmwareVersion?, list: FirmwareManifest? = nil) throws -> [UInt8] {
        let fw = try FirmwarePartition(data: editor.partition.data)
        AppLog.step("Build: start with \(patches.count) patch(es): " + patches.map { "\($0.spec.name) \($0.spec.versionText)" }.joined(separator: ", "))
        let osos = try outputOSOS(editor, patches, appearance: appearance, version: version, list: list)
        AppLog.step("Build: make room for an osos of \(osos.count) bytes, then put it in the partition")
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

    // MARK: games

    /// The folder of the games. The firmware asks for the name `games_RO` with small
    /// letters. The program of iTunes writes the name `Games_RO` with a capital letter.
    static func gamesDirectory(at root: URL) -> URL? {
        GameLibrary.gamesDirectory(at: root.path).map { URL(fileURLWithPath: $0) }
    }

    /// Copy the games to the connected iPod. The pane of the games shows the result.
    func installGames() async {
        guard currentIPod != nil else {
            alert = AlertInfo(title: "No iPod Is Connected", message: "Connect the iPod. The pane of the games copies the games to the iPod.")
            return
        }
        guard let volume = ipodVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        guard let source = gamesSourceFolder else {
            alert = AlertInfo(title: "No Folder of Games", message: "Choose the folder with the games first.")
            return
        }
        let gamesDir = AppModel.gamesDirectory(at: source) ?? source
        let library = GameLibrary.load(gamesDir.path)
        guard !library.isEmpty else {
            alert = AlertInfo(title: "No Game Found", message: "The folder \(gamesDir.lastPathComponent) has no game with a file Manifest.plist.")
            return
        }
        let wanted = library.filter { selectedGameFolders.contains($0.folder) }
        guard !wanted.isEmpty else {
            alert = AlertInfo(title: "No Game Selected", message: "Select at least one game.")
            return
        }
        let root = volume.appendingPathComponent("iPod_Control")
        do {
            let key = gameKeyFile
            let report = try await work("Copying \(counted(wanted.count, "game")) to the iPod…") {
                GameInstaller.install(wanted, to: root, copyKeyFile: key != nil, keyFileSource: key)
            }
            gameInstallStatus = "\(counted(report.installed.count, "game")), \(report.bytesCopied) bytes"
            if report.keyFileCopied { gameInstallStatus += ", key file copied" }
            for folder in report.installed { gameInstallStatus += "  \(folder)" }
            for warning in report.warnings { gameInstallStatus += "  skipped: \(warning)" }
        } catch {
            AppLog.warning("Cannot copy the games\n" + AppLog.describe(error))
            gameInstallStatus = "The games could not be copied: \(error.localizedDescription)"
        }
    }

    /// Let the user choose the folder with the games. The folder holds the games, or the
    /// folder `iPod_Control` of an iPod. The app reads the games of the folder.
    func chooseGamesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder with the games, or the folder iPod_Control of an iPod."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        gamesSourceFolder = folder
        gameInstallStatus = ""
        let gamesDir = AppModel.gamesDirectory(at: folder) ?? folder
        gamesLibrary = GameLibrary.load(gamesDir.path)
        selectedGameFolders = Set(gamesLibrary.map { $0.folder })
    }

    /// Let the owner choose their own key file IC-Info.sidb. The app checks the name and the
    /// size. It does not read the bytes of the file.
    func chooseGameKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose your key file IC-Info.sidb, for example from a backup of the folder iPod_Control/iTunes of this iPod."
        guard panel.runModal() == .OK, let file = panel.url else { return }
        if let problem = GameInstaller.checkKeyFile(file) {
            alert = AlertInfo(title: "This Is Not a Key File", message: problem)
            return
        }
        gameKeyFile = file
        gameInstallStatus = ""
    }

    /// Select all the games, or no game.
    func selectAllGames(_ all: Bool) {
        selectedGameFolders = all ? Set(gamesLibrary.map { $0.folder }) : []
    }

    /// Read the games in the folder games_RO of the connected iPod.
    /// The pane of the games shows the list for the removal.
    func readIPodGames() async {
        guard currentIPod != nil else {
            alert = AlertInfo(title: "No iPod Is Connected", message: "Connect the iPod. The pane of the games reads the games of the iPod.")
            return
        }
        guard let volume = ipodVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        let root = volume.appendingPathComponent("iPod_Control").path
        let games = (GameLibrary.gamesDirectory(at: root)).map { GameRemover.removableFolders($0) } ?? []
        ipodGames = games
        selectedIPodGames = selectedIPodGames.intersection(Set(games))
        gameRemoveStatus = games.isEmpty ? "The folder games_RO of the iPod holds no game." : ""
    }

    /// Remove the selected games from the connected iPod. The owner confirms
    /// the removal first. The removal deletes the folder of the game only.
    func removeGames(_ guids: Set<String>) async {
        guard currentIPod != nil else {
            alert = AlertInfo(title: "No iPod Is Connected", message: "Connect the iPod. The pane of the games removes the games from the iPod.")
            return
        }
        guard let volume = ipodVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        let root = volume.appendingPathComponent("iPod_Control").path
        do {
            let report = try await work("Removing \(counted(guids.count, "game")) from the iPod…") {
                try GameRemover.remove(root, Array(guids))
            }
            gameRemoveStatus = "Removed \(counted(report.removed.count, "game"))."
            for guid in report.removed { gameRemoveStatus += "  \(guid)" }
            await readIPodGames()
        } catch {
            AppLog.warning("Cannot remove the games\n" + AppLog.describe(error))
            gameRemoveStatus = "The games could not be removed: \(error.localizedDescription)"
        }
    }

    /// The mounted volume of the connected iPod. The volume must have the folder iPod_Control.
    func ipodVolume() -> URL? {
        guard let ipod = currentIPod else { return nil }
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [])?
            .first { url in
                (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) == ipod.volumeName &&
                FileManager.default.fileExists(atPath: url.appendingPathComponent("iPod_Control").path)
            }
    }

    /// iPod_Control/iTunes/iPodFirmAlbumArt on the mounted iPod, from its own library.
    func writeThumbnails() async {
        guard currentIPod != nil else { return }
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder, then try again.")
            return
        }
        do {
            let r = try await work("Making album and playlist thumbnails from the music on the iPod…") { try MusicImport.writeThumbnails(volume: volume) }
            thumbnailStatus = "\(r.covers) of \(r.albums) albums and \(r.playlistArt) of \(r.playlists) playlists have a thumbnail (\(Date().formatted(date: .abbreviated, time: .shortened)))."
            playlistArtChanged = false
        } catch { fail("Cannot Write the Thumbnails", error) }
    }

    /// The log of the usb-host-probe patch. The action in its patch.json makes it empty and writes the
    /// trigger file; the patch writes the log on the iPod.
    static let usbProbeLogFile = "iPod_Control/iTunes/iPodFirmUSBLog"

    /// Finds the log files on the iPod. A file with no data gets no row.
    func refreshIPodLogs() {
        guard let volume = ipodMusicVolume() else { ipodLogs = []; return }
        ipodLogs = IPodLogFile.Kind.allCases.compactMap { kind in
            let file = kind == .playback ? Self.playbackLogFile : Self.usbProbeLogFile
            let path = volume.appendingPathComponent(file).path
            guard let info = try? FileManager.default.attributesOfItem(atPath: path),
                  let bytes = info[.size] as? Int, bytes > 0 else { return nil }
            return IPodLogFile(kind: kind, bytes: bytes, date: info[.modificationDate] as? Date)
        }
    }

    func readUSBProbeLog() {
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder, then try again.")
            return
        }
        guard let data = try? Data(contentsOf: volume.appendingPathComponent(Self.usbProbeLogFile)) else {
            alert = AlertInfo(title: "No USB Log", message: "The iPod has no USB log. Click Start the Probe at the Next Restart. Then do the test.")
            return
        }
        usbProbeLog = USBProbeLog.parse([UInt8](data)) ?? []
    }

    /// The log of the playback-log patch. The action in its patch.json makes it empty; the patch writes it on the iPod.
    static let playbackLogFile = "iPod_Control/iTunes/iPodFirmPlaybackLog"

    func readPlaybackLog() {
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        guard let data = try? Data(contentsOf: volume.appendingPathComponent(Self.playbackLogFile)) else {
            alert = AlertInfo(title: "No Playback Log", message: "The iPod has no playback log. Click Clear the Playback Log. Then do the test.")
            return
        }
        var letters: [String: String] = [:]
        for p in Self.patchLibrary.list() { if let l = p.spec.version_letter { letters[p.spec.name] = l } }
        let database = (try? Data(contentsOf: volume.appendingPathComponent("iPod_Control/iTunes/iTunesDB"))).map { [UInt8]($0) } ?? []
        playbackLog = PlaybackLog.text([UInt8](data), letters: letters, songs: ITunesDB.readTrackInfo(database)) ?? ""
    }

    /// Save the playback log as a text file, then show the file in Finder. Returns the file, or nil.
    @discardableResult
    func savePlaybackLog() -> URL? {
        guard let log = playbackLog, !log.isEmpty else { return nil }
        let s = NSSavePanel()
        s.nameFieldStringValue = PlaybackLog.fileName()
        s.allowedContentTypes = [.plainText]
        s.message = "Save the playback log as a text file. Then send the file to the developer."
        guard s.runModal() == .OK, let url = s.url else { return nil }
        do {
            try ("iPodFirm on the Mac: \(version)\n" + log + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            fail("Cannot Save the Playback Log", error)
            return nil
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    /// Save the playback log, then open a new issue on GitHub. The owner of the log drags the file into the issue.
    func reportPlaybackLog() {
        guard let log = playbackLog, let url = savePlaybackLog() else { return }
        NSWorkspace.shared.open(PlaybackLog.issueURL(log: log, appVersion: version, fileName: url.lastPathComponent))
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
        } catch { fail("Cannot Save the Playlist Image", error) }
    }

    func resetPlaylistArt(_ name: String) async {
        guard let volume = ipodMusicVolume() else { return }
        do {
            try MusicImport.removePlaylistArt(volume: volume, name: name)
            playlistArtChanged = true
            await loadPlaylists()
        } catch { fail("Cannot Remove the Playlist Image", error) }
    }

    // MARK: playlist folders

    /// Read the playlists and the folder file of the connected iPod.
    func loadPlaylistFolders() async {
        guard let volume = ipodMusicVolume() else {
            folderPlaylists = []
            playlistFolders = PlaylistFolders()
            savedPlaylistFolders = PlaylistFolders()
            return
        }
        let r = await Task.detached(priority: .userInitiated) { () -> ([ITunesDB.PlaylistEntry], PlaylistFolders) in
            let db = (try? Data(contentsOf: volume.appendingPathComponent("iPod_Control/iTunes/iTunesDB"))).map { [UInt8]($0) } ?? []
            return (ITunesDB.readPlaylistEntries(db).filter { !$0.isPodcast }, PlaylistFolders.read(volume: volume))
        }.value
        folderPlaylists = r.0
        var folders = r.1
        folders.removeMissing(Set(r.0.map(\.persistentID)))
        savedPlaylistFolders = r.1
        playlistFolders = folders
        playlistFoldersStatus = nil
    }

    /// The problems that stop a write of the folders.
    var playlistFolderProblems: [String] {
        playlistFolders.problems(playlistNames: folderPlaylists.map(\.name))
    }

    /// Write the folder file to the iPod.
    func writePlaylistFolders() async {
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        let folders = playlistFolders
        // Saved for later: the folder colours. The app wrote the thumbnail file again, so that
        // the folders got their colour squares. The squares did not show on the real iPod.
        // Refer to re/playlist-folders.md, "Folder colours".
        // let art = volume.appendingPathComponent("iPod_Control/iTunes/\(AlbumArt.fileName)")
        // let hasArt = FileManager.default.fileExists(atPath: art.path)
        do {
            try await work("Writing the playlist folders to the iPod…") {
                try folders.write(volume: volume)
                // if hasArt { _ = try MusicImport.writeThumbnails(volume: volume) }
            }
            savedPlaylistFolders = folders
            let time = Date().formatted(date: .abbreviated, time: .shortened)
            playlistFoldersStatus = "The iPod has \(counted(folders.folders.count, "folder")) (\(time)). Eject the iPod to see the change."
        } catch { fail("Cannot Write the Playlist Folders", error) }
    }

    // MARK: pictures

    func exportPicture(_ item: PictureItem) {
        guard let osos = shownPictures?.osos, let data = ImageCodec.png(for: item.picture, osos: osos) else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = String(format: picturesDark ? "%04d_%d_dark.png" : "%04d_%d.png", item.index, item.resourceID)
        if p.runModal() == .OK, let url = p.url {
            do { try data.write(to: url) } catch { fail("Cannot Export", error) }
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
        } catch { fail("Cannot Replace the Picture", error) }
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
            } catch { fail("Export Failed", error) }
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
                alert = AlertInfo(title: "Import Finished", message: changed.isEmpty ? "No changes found." : "\(changed.count) file(s) applied.")
            } catch { fail("Import Failed", error) }
        }
    }

    // MARK: strings

    func applyStrings(blockIndex: Int, _ values: [String: String]) -> Bool {
        guard let editor else { return false }
        do {
            if try editor.setStrings(blockIndex: blockIndex, values) { edited() }
            return true
        } catch {
            fail("Cannot Apply the Text", error)
            return false
        }
    }

    // MARK: iPod

    func refreshIPods() async {
        do {
            ipods = try await Task.detached { try Device.findIPods() }.value
            let found = ipods.map { "\($0.disk) \($0.mediaName) \($0.size) bytes" }
            AppLog.info("iPods found: \(found.isEmpty ? "none" : found.joined(separator: ", "))")
            if selectedIPod == nil || !ipods.contains(where: { $0.disk == selectedIPod }) { selectedIPod = ipods.first?.disk }
            unsupportedIPods.formIntersection(ipods)
        } catch { fail("Cannot List Disks", error) }
        refreshBackups()
        await readIPodLibraryName()
        refreshIPodLogs()
        // A different iPod (or none): the old state is not valid. Read the new iPod.
        guard busy == nil else { return }
        guard let ipod = currentIPod, !currentIPodIsUnsupported else { ipodState = nil; ipodReadStatus = nil; return }
        if ipodState?.ipodKey != IPodPatchState.key(ipod) {
            ipodState = nil
            await readIPodPatches(automatic: true)
        }
    }

    /// Read the name of the iPod from its music database.
    func readIPodLibraryName() async {
        let volume = ipodMusicVolume()
        ipodLibraryName = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let volume,
                  let db = try? Data(contentsOf: volume.appendingPathComponent("iPod_Control/iTunes/iTunesDB")) else { return nil }
            return ITunesDB.readLibraryName([UInt8](db))
        }.value
    }

    func ejectIPod() async {
        guard busy == nil, let ipod = currentIPod else { return }
        do {
            try await work("Ejecting \(ipod.volumeName ?? ipod.mediaName)…") { try Device.eject(ipod) }
            thumbnailStatus = nil
            playlistArt = []
            playlistArtChanged = false
            await refreshIPods()
        } catch { fail("The iPod Did Not Eject", error) }
    }

    func refreshBackups() { backups = Backups.list(in: Self.backupDir) }

    func backupURL(_ b: BackupInfo) -> URL { Self.backupDir.appendingPathComponent(b.file) }

    func helperArgs(_ cmd: String, dir: URL? = nil, _ ipod: IPodDisk) -> [String] {
        [cmd, "--disk", ipod.disk, "--backup-dir", (dir ?? Self.backupDir).path, "--owner", String(getuid())]
    }

    func backupNow() async {
        guard busy == nil, let ipod = currentIPod else { return }
        busy = "Backing up the iPod's firmware partition…"
        defer { busy = nil; refreshBackups() }
        do {
            let r = try await runBackup(ipod)
            guard r.ok else { throw r.failure() }
            alert = AlertInfo(title: "Backup Saved", message: "\(r.message)\n\n\(r.backup?.file ?? "")")
        } catch { fail("Backup Failed", error) }
    }

    /// Step 1 of flashing: dry run (no writes) to show exactly what would change.
    func prepareFlash(image: URL, reason: String) async {
        guard busy == nil else { return }
        guard let ipod = currentIPod else {
            alert = AlertInfo(title: "No iPod Is Connected", message: "Connect the iPod. Then try again.")
            return
        }
        busy = "Checking the iPod (nothing is written yet)…"
        defer { busy = nil }
        do {
            try checkNoMusicSync()
            var reason = reason
            var r = try await runFlash(ipod, image: image, reason: reason, dryRun: true)
            if !r.ok, r.code == HelperResult.firmwareUnreadable, reason == "restore" {
                // An interrupted write left the iPod's firmware unreadable: the normal restore cannot compare with it.
                reason = "rescue"
                r = try await runFlash(ipod, image: image, reason: reason, dryRun: true)
            }
            guard r.ok else { throw r.failure() }
            if r.ranges?.isEmpty ?? true {
                alert = AlertInfo(title: "Nothing to Do", message: r.message)
            } else {
                flashPlan = FlashPlan(ipod: ipod, image: image, reason: reason, result: r,
                                      musicAppRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: MusicAppCheck.miMusicBundleID).isEmpty)
            }
        } catch { fail("Cannot Flash", error) }
    }

    /// A firmware without the patch shuffle-album-mix still loads Album Mix from the settings file of
    /// the iPod, and then shuffles the songs in each album with no menu item to stop it. Before such a
    /// write, switch off Album Mix in the file (Albums stays Albums). Returns a note for the result.
    func clearAlbumMixIfNeeded(image: URL) -> String? {
        guard !IPodPreferences.hasAlbumMix(partition: image), let volume = ipodMusicVolume() else { return nil }
        do {
            guard try IPodPreferences.clearAlbumMix(onVolume: volume) else { return nil }
            return "The new firmware has no Album Mix. iPodFirm changed Settings > Shuffle on the iPod from Album Mix to Albums."
        } catch {
            AppLog.warning("Cannot change the Shuffle setting on the iPod\n" + AppLog.describe(error))
            return "The new firmware has no Album Mix, but iPodFirm cannot change the settings file of the iPod (\(error.localizedDescription)). On the iPod, set Settings > Shuffle to Off, Songs or Albums."
        }
    }

    /// Stop a firmware write while MiMusic writes to the iPod. The write unmounts the volume and stops the sync.
    func checkNoMusicSync() throws {
        guard let volume = ipodMusicVolume(), !MusicAppCheck.syncFiles(onVolume: volume).isEmpty else { return }
        throw FirmwareError("MiMusic is writing to the iPod. Wait until the sync is complete. Then try again.")
    }

    /// Step 2: the helper backs up the current partition, writes only changed blocks, and verifies.
    func performFlash(_ plan: FlashPlan) async {
        flashPlan = nil
        busy = "Backup, write and check in progress… Do not disconnect the iPod."
        defer { busy = nil; refreshBackups() }
        do {
            // Do the check again: a sync can start while the sheet is open.
            try checkNoMusicSync()
            // The write unmounts the volume, thus change the settings file first.
            let mixNote = clearAlbumMixIfNeeded(image: plan.image)
            let r = try await runFlash(plan.ipod, image: plan.image, reason: plan.reason, dryRun: false)
            guard r.ok else { throw r.failure() }
            if plan.reason == "flash" { isDirty = false }
            recordWrittenImage(plan.image, ipod: plan.ipod)
            alert = AlertInfo(title: plan.reason == "flash" ? "Flashed" : "Restored",
                              message: "\(r.message)\nBackup taken first: \(r.backup?.file ?? "-")\(mixNote.map { "\n\n" + $0 } ?? "")\n\nEject the iPod. If the iPod does not start, reset it (hold Menu and Select). Then hold Select and Play for disk mode, and restore a backup in iPodFirm.")
        } catch { fail("Flash Failed", error) }
    }

    /// true: the app can start a flash of the open firmware.
    var canFlash: Bool { flashBlockReason == nil }

    /// Why the app cannot start a flash, in words for the user. nil: the app can start a flash.
    var flashBlockReason: String? {
        if currentIPod == nil { return "Connect the iPod to flash it." }
        if currentIPodIsUnsupported { return "iPodFirm cannot flash this iPod." }
        if editor == nil { return "Open a firmware to flash the iPod." }
        if busy != nil { return "Wait until the current operation is complete." }
        return nil
    }

    func flashEdited() async {
        guard busy == nil, let editor else { return }
        let staging = Self.supportDir.appendingPathComponent("Staging/flash.bin")
        do {
            try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Self.outputPartition(editor, activePatches, appearance: activeAppearance, version: activeVersion, list: activeList)).write(to: staging, options: .atomic)
            await prepareFlash(image: staging, reason: "flash")
        } catch { fail("Cannot Flash", error) }
    }

    func restore(_ b: BackupInfo) async { await prepareFlash(image: backupURL(b), reason: "restore") }

    /// Last resort, e.g. for a damaged partition table: Finder rewrites the whole iPod from Apple's .ipsw.
    func restoreWithFinder() async {
        do {
            let ipsw = try await ensureAppleIPSW()
            NSWorkspace.shared.activateFileViewerSelecting([ipsw])
            showFinderRestoreHelp = true
        } catch { fail("Cannot Get the Apple Firmware", error) }
    }

    // MARK: emulator

    func exportIPSW() {
        guard let editor else { return }
        let s = NSSavePanel()
        s.nameFieldStringValue = "custom-iPod_25.1.3.ipsw"
        guard s.runModal() == .OK, let out = s.url else { return }
        let patches = activePatches, appearance = activeAppearance, version = activeVersion, list = activeList
        Task {
            do {
                let original = try await ensureAppleIPSW()
                try await work("Writing .ipsw…") {
                    let osos = try Self.outputOSOS(editor, patches, appearance: appearance, version: version, list: list)
                    try IPSW.repack(original: original, firmware: IPSW.firmware(original: original, withOSOS: osos), to: out)
                }
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch { fail("Cannot Write the .ipsw", error) }
        }
    }

    /// Build the emulator drive from the current edits and boot it in the in-app preview.
    func runInEmulator(_ emu: EmulatorManager, _ session: EmulatorSession) {
        guard let editor else { return }
        let patches = activePatches, appearance = activeAppearance, version = activeVersion, list = activeList
        let library = EmulatorManager.Library.current
        session.start { [weak self] in
            guard let self else { return }
            let original = try await self.ensureAppleIPSW()
            let (fw, ososLength) = try await Task.detached { () -> ([UInt8], Int) in
                let osos = try Self.outputOSOS(editor, patches, appearance: appearance, version: version, list: list)
                return (try IPSW.firmware(original: original, withOSOS: osos), osos.count)
            }.value
            try await emu.prepare(firmware: fw, ososLength: ososLength, originalIPSW: original, library: library)
        }
    }
}

/// The count and the noun in the correct form, for example "1 game" or "2 games".
func counted(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }

/// Gives the progress of one download to the app.
final class DownloadWatcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: (Double) -> Void

    init(progress: @escaping (Double) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    /// The async download call gives the file to the app.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
