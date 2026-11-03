import AppKit
import CryptoKit
import Foundation
import IPodFWKit
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
    /// A `.ipodeq` file that waits for the decision of the user.
    @Published var pendingEQ: SharedEQ?
    @Published var ipods: [IPodDisk] = []
    @Published var selectedIPod: String?
    /// iPods for which an operation gave OperationResult.unsupportedIPod (for example an iPod classic).
    @Published var unsupportedIPods: Set<IPodDisk> = []
    /// The name of the connected iPod that iTunes set. Nil if the iPod has no music database.
    @Published var ipodLibraryName: String?
    @Published var backups: [BackupInfo] = []
    @Published var flashPlan: FlashPlan?
    /// Not nil during a write to the iPod.
    private var writeActivity: NSObjectProtocol?
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
    /// The EQs of the patch custom-eq. Keep this before `patchOptions`: the first load moves the
    /// bands of an older version from the options to this list.
    @Published var customEQs: [NamedEQ] = AppModel.loadEQs() {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(customEQs), forKey: "customEQs")
            switchesChanged(oldValue != customEQs)
        }
    }
    @Published var selectedEQName = ""

    static func loadEQs() -> [NamedEQ] {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "customEQs"), let eqs = try? JSONDecoder().decode([NamedEQ].self, from: data), !eqs.isEmpty {
            return Array(eqs.prefix(CustomEQ.maxEQs))
        }
        var options = d.dictionary(forKey: "patchOptions") as? [String: [String: Int]] ?? [:]
        let eq = NamedEQ(options: options["custom-eq"] ?? [:])
        options["custom-eq"] = nil
        d.set(options, forKey: "patchOptions")
        d.set(try? JSONEncoder().encode([eq]), forKey: "customEQs")
        return [eq]
    }

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
    /// The layout of the main menu.
    @Published var layout: Layout = Layout(rawValue: UserDefaults.standard.string(forKey: "layout") ?? "") ?? .stock {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: "layout")
            switchesChanged(oldValue != layout)
            if !oldValue.hasSplit && layout.hasSplit && !mirroring { turnOnSplitPatch() }
        }
    }

    /// The size of the text in the panel of the Split layout.
    @Published var splitText: SplitText = SplitText(rawValue: UserDefaults.standard.string(forKey: "splitText") ?? "") ?? .standard {
        didSet {
            UserDefaults.standard.set(splitText.rawValue, forKey: "splitText")
            switchesChanged(oldValue != splitText)
        }
    }

    /// The widths of the list and the panel in the Split layout.
    @Published var splitWidth: SplitWidth = SplitWidth(rawValue: UserDefaults.standard.string(forKey: "splitWidth") ?? "") ?? .twoThirds {
        didSet {
            UserDefaults.standard.set(splitWidth.rawValue, forKey: "splitWidth")
            switchesChanged(oldValue != splitWidth)
        }
    }

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
    @Published var batteryLog: String?
    /// The text of the playback log (nil: not read; empty: the file has no log).
    @Published var playbackLog: String?
    /// The text of the diagnostic log (nil: not read; empty: the file has no log).
    @Published var diagnosticLog: String?
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
    /// Settings > Updates: ask GitHub for a newer release at each launch.
    @AppStorage("checkForUpdates") var checkForUpdates = true
    /// The release that the user skipped with "Skip This Version". The launch check ignores it.
    @AppStorage(UpdateNotifier.skippedKey) var skippedUpdateVersion = ""
    /// A newer release, if macOS does not allow the notification. The app shows an alert instead.
    @Published var availableUpdate: UpdateCheck.Release?
    @Published var showFinderRestoreHelp = false

    /// The appearance of the iPod software.
    enum Appearance: String, CaseIterable, Identifiable {
        case light, dark, onIPod = "switch"
        var id: String { rawValue }
        var title: String { self == .onIPod ? "Switch on iPod" : rawValue.capitalized }
    }

    /// The layout of the iPod software.
    enum Layout: String, CaseIterable, Identifiable {
        case stock, split, onIPod
        var id: String { rawValue }
        var title: String { self == .onIPod ? "Switch on iPod" : rawValue.capitalized }
        /// True if the firmware has the Split View: Split, or Switch on iPod (a Split View item in Settings).
        var hasSplit: Bool { self != .stock }
    }

    enum SplitText: String, CaseIterable, Identifiable {
        case standard, small
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum SplitWidth: String, CaseIterable, Identifiable {
        case twoThirds, half
        var id: String { rawValue }
        var title: String { self == .twoThirds ? "⅔ – ⅓" : "½ – ½" }
    }

    /// What the output build does with the dark theme or the layout.
    enum AppearanceBuild {
        /// The layout theme is in the firmware.
        case layout(ImportedTheme)
        /// The theme is in the firmware: always dark. The layout can follow it.
        case dark(ImportedTheme, layout: ImportedTheme?)
        /// Light firmware with a Dark Mode item in Settings (DarkMode.build). With `layoutSwitch`, also a
        /// Split View item.
        case switchOnIPod(ImportedTheme, PatchInfo, layout: ImportedTheme?, layoutSwitch: Bool)
        /// Always light (no theme) or always dark, with the Split View and a Split View item in Settings.
        case layoutSwitch(ImportedTheme?, PatchInfo, layout: ImportedTheme)
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
        let result: OperationResult
        /// MiMusic was open when iPodFirm made the plan.
        var musicAppRunning = false
    }

    nonisolated static let supportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("iPodFirm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    /// Temporary files. A flash image needs no backup, and a root-owned `Staging` folder of an older app
    /// in the support folder has no effect here.
    nonisolated static let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("iPodFirm")
    static let backupDir = supportDir.appendingPathComponent("Backups")
    static let themesDir = supportDir.appendingPathComponent("Themes")
    static var patchesDir: URL { Bundle.main.resourceURL!.appendingPathComponent("patches") }
    /// The built-in patches and the patches that the owner installs (Application Support/iPodFirm/Patches).
    static let patchLibrary = PatchLibrary(builtInDir: patchesDir, userDir: supportDir.appendingPathComponent("Patches"),
                                           stagingDir: cacheDir.appendingPathComponent("Staging"))
    /// The SHA-256 of Apple's .ipsw file.
    static let appleFirmwareSHA256 = "840b2480ad5b692c098cb772c3d2bf8f58bf37557788782b596ac01c27ecdc32"
    /// The SHA-256 of the osos image in Apple's .ipsw file.
    static let appleOSOSSHA256 = "784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251"

    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "dev") (\(info["CFBundleVersion"] as? String ?? "0"))"
    }

    var currentIPod: IPodDisk? { ipods.first { $0.disk == selectedIPod } ?? ipods.first }

    /// True if an operation found that the selected iPod is not an iPod Video.
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
        var title = title
        if (error as? FirmwareError)?.code == OperationResult.unsupportedIPod, let ipod = currentIPod {
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

    /// The lines about the iPod in a report.
    private var ipodReportLines: [String] {
        guard let ipod = currentIPod else { return ["iPod: none"] }
        return ["iPod: \(ipod.mediaName), \(ipod.size) bytes, block size \(ipod.blockSize)" + (currentIPodIsUnsupported ? ", not supported" : ""),
                "  \(ipod.sysInfoReport), original drive: \(IPodDisk.likelyOriginalHDD(size: ipod.size).map { "probably \($0) GB" } ?? "no")"]
    }

    /// The short text for a new issue. The saved log has all other data.
    func issueSummary(_ fault: AlertInfo?) -> String {
        let state = (["iPodFirm \(version), \(AppLog.systemDescription)"] + ipodReportLines).joined(separator: "\n")
        let excerpt = fault?.details.map { AppLog.faultExcerpt(details: $0, steps: AppLog.recentSteps(3)) }
        return AppLog.redact(excerpt.map { state + "\n\n" + $0 } ?? state)
    }

    /// The state of the app and of the iPod, for a fault report.
    func diagnosticSnapshot() -> String {
        var lines = ["iPodFirm \(version), \(AppLog.systemDescription)"]
        if let editor {
            let apple = editor.originalOSOSHash == Self.appleOSOSSHA256 ? "Apple 1.3" : "not Apple 1.3"
            lines.append("Open file: \(fileURL?.lastPathComponent ?? "-") (osos \(apple), \(editor.osos.count) bytes, edited: \(isDirty))")
        } else {
            lines.append("Open file: none")
        }
        lines += ipodReportLines
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
        lines.append("Appearance: \(appearance.rawValue), layout: \(layout.rawValue), panel text: \(splitText.rawValue), split width: \(splitWidth.rawValue), theme: \(selectedThemeName ?? "-"), margin: \(ThemeImport.OSOSMargin.current.rawValue), test patches: \(showTestPatches)")
        lines.append("Full Disk Access: \(Self.checkFullDiskAccess())")
        lines.append("App: \(Bundle.main.bundlePath), signature: \(ownSignatureDescription())")
        lines.append("App folder:")
        lines += appFolderReport(Self.supportDir).map { "  " + $0 }
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
        NSWorkspace.shared.open(AppLog.issueURL(title: fault?.title ?? "Problem report", message: fault?.message ?? "",
                                                details: issueSummary(fault), fileName: file?.lastPathComponent))
    }

    /// For a fault report. The app does not need Full Disk Access. Only this permission can read the system TCC database.
    nonisolated static func checkFullDiskAccess() -> Bool {
        let probe = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let h = FileHandle(forReadingAtPath: probe) else { return false }
        try? h.close()
        return true
    }

    /// Run an operation away from the main thread. A fault gives a result with `ok == false`.
    private func operation(_ body: @escaping @Sendable () throws -> OperationResult) async -> OperationResult {
        let r = await Task.detached { () -> OperationResult in
            do { return try body() } catch { return OperationResult(failure: error) }
        }.value
        if r.ok {
            AppLog.info("Result: \(r.message)")
        } else {
            AppLog.warning("Fault: \(r.message) (code \(r.code ?? "none"))\n\(r.fault.map(AppLog.describe) ?? "No detail.")")
        }
        return r
    }

    private func runBackup(_ ipod: IPodDisk) async -> OperationResult {
        let start = Date()
        defer { recordAppInBackups(since: start) }
        AppLog.step("Back up \(ipod.disk)")
        let dir = Self.backupDir
        return await operation { try Operations.backup(ipod, to: dir, access: .authOpen()) }
    }

    /// reason is "flash", "restore", or "rescue" (a restore onto a damaged firmware partition).
    private func runFlash(_ ipod: IPodDisk, image: URL, reason: String, dryRun: Bool) async -> OperationResult {
        AppLog.step("\(reason) of \(image.lastPathComponent) on \(ipod.disk)\(dryRun ? " (dry run)" : "")")
        let dir = Self.backupDir
        let start = Date()
        if !dryRun { beginWrite() }
        defer {
            if !dryRun {
                endWrite()
                recordAppInBackups(since: start)
            }
        }
        return await operation {
            if reason == "rescue" { return try Operations.rescueRestore(ipod, image: image, backupDir: dir, dryRun: dryRun, access: .authOpen()) }
            return try Operations.flash(ipod, image: image, backupDir: dir, reason: reason, dryRun: dryRun, access: .authOpen())
        }
    }

    /// Writes this app into the metadata of the new backups. A fault here does not stop the operation.
    private func recordAppInBackups(since start: Date) {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String else { return }
        do {
            try Backups.recordApp(version: version, build: info["CFBundleVersion"] as? String,
                                  name: info["CFBundleName"] as? String, in: Self.backupDir, since: start)
        } catch { AppLog.warning("Could not record the app in the backup metadata: \(AppLog.describe(error))") }
    }

    /// The app does the write itself. It must not quit, and macOS must not stop it or sleep, during a write.
    private func beginWrite() {
        writeActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled, .automaticTerminationDisabled],
                                                              reason: "Writing the firmware of the iPod")
    }

    private func endWrite() {
        if let writeActivity { ProcessInfo.processInfo.endActivity(writeActivity) }
        writeActivity = nil
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
        guard writeActivity == nil else {
            let a = NSAlert()
            a.messageText = "iPodFirm Is Writing to the iPod"
            a.informativeText = "If iPodFirm quits now, the iPod can get a partial firmware. Wait until the write is complete."
            a.runModal()
            return false
        }
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

    /// The Split layout theme. It comes with the app and is not in the list of dark themes.
    static let splitTheme: ImportedTheme? = Bundle.main.resourceURL
        .flatMap { try? ImportedTheme.load($0.appendingPathComponent("Layouts/Split.ipodtheme")) }

    /// The Split layout with the selected text size and width. Nil for the Stock layout.
    var activeSplit: ImportedTheme? {
        guard layout.hasSplit, var split = Self.splitTheme else { return nil }
        if splitText == .small { split = split.withSmallText() }
        if splitWidth == .half { split = split.withHalfWidth() }
        return split
    }

    /// The appearance build for the output: nothing for Light with the Stock layout.
    var activeAppearance: AppearanceBuild? {
        let split = activeSplit, layoutSwitch = layout == .onIPod
        if appearance == .light {
            if layoutSwitch, let split, let patch = Self.darkModePatch { return .layoutSwitch(nil, patch, layout: split) }
            return split.map { .layout($0) }
        }
        guard let theme = selectedTheme?.theme else { return nil }
        switch appearance {
        case .light: return nil
        case .dark:
            if layoutSwitch, let split, let patch = Self.darkModePatch { return .layoutSwitch(theme, patch, layout: split) }
            return .dark(theme, layout: split)
        case .onIPod:
            return Self.darkModePatch.map { .switchOnIPod(theme, $0, layout: split, layoutSwitch: layoutSwitch) }
        }
    }

    /// The bytes that the Split View, the Split View item and the switch code add, for the layout
    /// "Switch on iPod" with the appearance Light or Dark. Nil without the open firmware 1.3.
    var layoutSwitchSize: Int? {
        guard layout == .onIPod, let editor, let split = activeSplit, isCompatible(split),
              let patch = Self.darkModePatch else { return nil }
        let key = "\(revision) \(splitText.rawValue) \(splitWidth.rawValue)"
        if let c = layoutSwitchSizeCache, c.key == key { return c.size }
        let size = try? DarkMode.addedSize(partition: editor.partition, osos: editor.osos, theme: nil, darkSwitch: false,
                                           codeSize: patch.spec.size ?? 0, layout: split, layoutSwitch: true)
        layoutSwitchSizeCache = (key, size)
        return size
    }
    private var layoutSwitchSizeCache: (key: String, size: Int?)?

    /// The version for the About screen: the custom version (or 1.3) and the letters of the switched-on patches.
    /// Nothing when the result is the Apple version.
    var activeVersion: FirmwareVersion? {
        var v = (customVersionOn ? FirmwareVersion(customVersion) : nil) ?? .stock
        if versionLettersOn { v.letters = activePatches.compactMap(\.spec.version_letter).sorted().joined() }
        return v == .stock ? nil : v
    }

    func isCompatible(_ t: ImportedTheme) -> Bool { editor?.originalOSOSHash == t.osos_sha256 }

    /// The bytes that "Switch on iPod" adds to the firmware: the theme data, the switch table, the
    /// Settings menu and the dark-mode code. This is the last known value until
    /// `refreshSwitchOnIPodSize` ends. Show it only if `switchSizeKey` is not nil.
    @Published var switchOnIPodSize = UserDefaults.standard.object(forKey: "switchSizeLast") as? Int
    /// True while `refreshSwitchOnIPodSize` calculates.
    @Published var measuringSwitchSize = false
    private var switchSizeDone: String?

    /// The input of `switchOnIPodSize`. Nil if no theme agrees with the open firmware.
    var switchSizeKey: String? {
        guard editor != nil, let file = selectedTheme, isCompatible(file.theme), Self.darkModePatch != nil else { return nil }
        return "\(revision) \(themeRevision) \(file.name) \(layout.rawValue)"
    }

    /// Calculate `switchOnIPodSize` away from the main thread. The calculation takes seconds, so the
    /// view must not do it. The old value stays visible until the new value is ready. The result stays
    /// on the Mac for each firmware, theme file and layout, and a new version of the app calculates again.
    func refreshSwitchOnIPodSize() async {
        measuringSwitchSize = false
        guard let key = switchSizeKey, let editor, let file = selectedTheme, let patch = Self.darkModePatch else {
            switchSizeDone = nil
            return
        }
        guard key != switchSizeDone else { return }
        measuringSwitchSize = true
        let partition = editor.partition, osos = editor.osos, split = activeSplit
        let version = version, layoutName = layout.rawValue, layoutSwitch = layout == .onIPod
        let size = await Task.detached(priority: .utility) { () -> Int? in
            let defaults = UserDefaults.standard
            let themeBytes = (try? Data(contentsOf: file.url)) ?? Data()
            let input = "\(ThemeImport.sha256(osos + themeBytes)) \(layoutName)"
            var sizes = defaults.string(forKey: "switchSizesVersion") == version
                ? defaults.dictionary(forKey: "switchSizes") as? [String: Int] ?? [:] : [:]
            if let size = sizes[input] { return size }
            guard let size = try? DarkMode.addedSize(partition: partition, osos: osos, theme: file.theme,
                                                     codeSize: patch.spec.size ?? 0, layout: split,
                                                     layoutSwitch: layoutSwitch) else { return nil }
            sizes[input] = size
            defaults.set(sizes, forKey: "switchSizes")
            defaults.set(version, forKey: "switchSizesVersion")
            return size
        }.value
        guard !Task.isCancelled else { return }
        switchSizeDone = key
        switchOnIPodSize = size
        UserDefaults.standard.set(size, forKey: "switchSizeLast")
        measuringSwitchSize = false
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

    /// The Split layout turns this patch on one time. The patch keeps its own switch.
    static let splitPatch = "no-now-playing-timer"
    private func turnOnSplitPatch() {
        if let p = patches.first(where: { $0.spec.name == Self.splitPatch }) { setPatch(p, on: true) }
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
            if action.write.contains(where: { $0.path == Self.diagnosticLogFile }) { diagnosticLog = nil }
            if action.write.contains(where: { $0.path == Self.batteryLogFile }) { batteryLog = nil }
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
            if p.spec.eq_editor != nil { p.customEQs = customEQs }
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

    /// The EQ that the editor shows.
    var selectedEQ: NamedEQ { customEQs.first { $0.name == selectedEQName } ?? customEQs[0] }

    private func updateSelectedEQ(_ change: (inout NamedEQ) -> Void) {
        guard let i = customEQs.firstIndex(of: selectedEQ) else { return }
        change(&customEQs[i])
    }

    func addEQ(named name: String) {
        if let problem = CustomEQ.nameProblem(name, in: customEQs, excluding: nil) {
            alert = AlertInfo(title: "Cannot Add the EQ", message: problem)
        } else if customEQs.count >= CustomEQ.maxEQs {
            alert = AlertInfo(title: "Cannot Add the EQ", message: "The iPod can have a maximum of \(CustomEQ.maxEQs) EQs.")
        } else {
            customEQs.append(NamedEQ(name: name))
            selectedEQName = name
        }
    }

    func renameSelectedEQ(to name: String) {
        if let problem = CustomEQ.nameProblem(name, in: customEQs, excluding: selectedEQ.name) {
            alert = AlertInfo(title: "Cannot Rename the EQ", message: problem)
            return
        }
        updateSelectedEQ { $0.name = name }
        selectedEQName = name
    }

    func deleteSelectedEQ() {
        guard customEQs.count > 1 else { return }
        customEQs.removeAll { $0.name == selectedEQ.name }
        selectedEQName = customEQs[0].name
    }

    /// The 5 bands of the selected EQ, as the build uses them.
    func eqBands(_ patch: PatchInfo) -> [CustomEQ.Band] { selectedEQ.activeBands }

    func setEQBands(_ patch: PatchInfo, _ bands: [CustomEQ.Band]) { updateSelectedEQ { $0.bands = bands } }

    func eqUsesAdvanced(_ patch: PatchInfo) -> Bool { selectedEQ.advanced }

    /// The Simple view has fixed bands. A change to it keeps only the gains.
    func setEQUsesAdvanced(_ patch: PatchInfo, _ on: Bool) {
        updateSelectedEQ {
            $0.advanced = on
            if !on { $0.bands = CustomEQ.simple(from: $0.bands) }
        }
    }

    func eqUsesAllBands(_ patch: PatchInfo) -> Bool { selectedEQ.allBands }

    /// The view asks the user to agree to `CustomEQ.allBandsWarning` before it sets this to on.
    func setEQUsesAllBands(_ patch: PatchInfo, _ on: Bool) { updateSelectedEQ { $0.allBands = on } }

    /// Start from an Apple preset. The Simple view has fixed bands, so the view changes to Advanced.
    func applyEQPreset(_ patch: PatchInfo, _ preset: CustomEQ.Preset) {
        updateSelectedEQ {
            $0.bands = CustomEQ.bands(forPreset: preset)
            $0.advanced = true
        }
    }

    func eqUsesFullGain(_ patch: PatchInfo) -> Bool { selectedEQ.fullGain == true }

    /// The view asks the user to agree to `CustomEQ.fullGainWarning` before it sets this to on.
    func setEQUsesFullGain(_ patch: PatchInfo, _ on: Bool) { updateSelectedEQ { $0.fullGain = on ? true : nil } }

    func eqUsesPrecut(_ patch: PatchInfo) -> Bool { selectedEQ.preventClipping }

    func setEQUsesPrecut(_ patch: PatchInfo, _ on: Bool) { updateSelectedEQ { $0.preventClipping = on } }

    /// The patch that has the EQ editor.
    var eqPatch: PatchInfo? { patches.first { $0.spec.eq_editor != nil } }

    /// Write the EQ of the patch to a `.ipodeq` file. The name of the file is the name of the EQ.
    func exportEQ(_ patch: PatchInfo) {
        let s = NSSavePanel()
        s.nameFieldStringValue = "\(selectedEQ.name).\(SharedEQ.fileExtension)"
        s.allowedContentTypes = [UTType(filenameExtension: SharedEQ.fileExtension) ?? .json]
        s.message = "The file has only the EQ settings. Send it to another iPodFirm user."
        guard s.runModal() == .OK, let url = s.url else { return }
        do {
            let eq = SharedEQ(name: url.deletingPathExtension().lastPathComponent, bands: selectedEQ.activeBands,
                              preventClipping: selectedEQ.preventClipping, advanced: selectedEQ.advanced)
            try eq.encode().write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { fail("Cannot Export the EQ", error) }
    }

    func chooseEQToImport() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: SharedEQ.fileExtension) ?? .json]
        p.message = "Select a .\(SharedEQ.fileExtension) file."
        if p.runModal() == .OK, let url = p.url { importEQ(from: url) }
    }

    /// Examine a `.ipodeq` file. The sheet asks the user before the bands change.
    func importEQ(from url: URL) {
        do {
            let fh = try FileHandle(forReadingFrom: url)
            defer { try? fh.close() }
            pendingEQ = try SharedEQ.decode(try fh.read(upToCount: SharedEQ.maxFileSize + 1) ?? Data())
        } catch {
            // A bad file from another person is not a fault of the app.
            alert = AlertInfo(title: "Cannot Open the EQ", message: error.localizedDescription)
        }
    }

    /// Replace the bands with a file that the user accepted. The iPod changes only at the next flash.
    func applyEQ(_ eq: SharedEQ) {
        pendingEQ = nil
        guard let patch = eqPatch else {
            alert = AlertInfo(title: "Cannot Open the EQ", message: "The Custom EQ patch is not in this version of iPodFirm.")
            return
        }
        let new = NamedEQ(shared: eq, in: customEQs)
        guard customEQs.count < CustomEQ.maxEQs else {
            alert = AlertInfo(title: "Cannot Import the EQ", message: "The iPod has room for \(CustomEQ.maxEQs) EQs. Delete an EQ, then try again.")
            return
        }
        customEQs.append(new)
        selectedEQName = new.name
        setPatch(patch, on: true)
        section = .patches
        patchSelection = patch.spec.name
        guard alert == nil else { return }
        alert = AlertInfo(title: "EQ Imported", message: "\"\(new.name)\" is now in your list of EQs. Flash the iPod to put it on the iPod.")
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
        case .layout(let theme):
            AppLog.step("Build: apply the layout \(theme.name)")
            try theme.apply(to: &osos, originalSHA256: editor.originalOSOSHash)
        case .dark(let theme, let layout):
            AppLog.step("Build: apply the dark theme \(theme.name)")
            try theme.apply(to: &osos, originalSHA256: editor.originalOSOSHash)
            if let layout {
                AppLog.step("Build: apply the layout \(layout.name)")
                try layout.movedLayout(after: osos, dark: true).apply(to: &osos, originalSHA256: editor.originalOSOSHash)
            }
        case .switchOnIPod(let theme, let patch, let layout, let layoutSwitch):
            AppLog.step("Build: add Dark Mode with the theme \(theme.name) and the patch \(patch.spec.name) \(patch.spec.versionText)")
            osos = try DarkMode.build(partition: editor.partition, osos: osos, theme: theme, patch: patch,
                                      originalSHA256: editor.originalOSOSHash, layout: layout, layoutSwitch: layoutSwitch).0
        case .layoutSwitch(let theme, let patch, let layout):
            AppLog.step("Build: add Split View with the layout \(layout.name), the theme \(theme?.name ?? "-") and the patch \(patch.spec.name) \(patch.spec.versionText)")
            osos = try DarkMode.build(partition: editor.partition, osos: osos, theme: theme, darkSwitch: false, patch: patch,
                                      originalSHA256: editor.originalOSOSHash, layout: layout, layoutSwitch: true).0
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
            let path = volume.appendingPathComponent(Self.logFile(kind)).path
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

    /// The logs of the playback-log and the diagnostic-log patches. The action in the patch.json makes
    /// the file empty; the patch writes it on the iPod.
    static let playbackLogFile = "iPod_Control/iTunes/iPodFirmPlaybackLog"
    static let diagnosticLogFile = "iPod_Control/iTunes/iPodFirmDiagnosticLog"

    static let batteryLogFile = "iPod_Control/iTunes/iPodFirmBatteryLog"

    /// Read the text of the battery log.
    func readBatteryLog() {
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        guard let data = try? Data(contentsOf: volume.appendingPathComponent(Self.batteryLogFile)) else {
            alert = AlertInfo(title: "No Battery Log", message: "The iPod has no battery log. Click Clear the Battery Log. Then do the test.")
            return
        }
        batteryLog = BatteryLog.text(data)
    }

    static func logFile(_ kind: IPodLogFile.Kind) -> String {
        switch kind {
        case .playback: playbackLogFile
        case .diagnostic: diagnosticLogFile
        case .usb: usbProbeLogFile
        case .battery: batteryLogFile
        }
    }

    /// The text of a log with songs: the playback log or the diagnostic log.
    func songLog(_ kind: IPodLogFile.Kind) -> String? {
        kind == .diagnostic ? diagnosticLog : playbackLog
    }

    func readSongLog(_ kind: IPodLogFile.Kind) {
        let name = kind == .diagnostic ? "Diagnostic Log" : "Playback Log"
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        guard let data = try? Data(contentsOf: volume.appendingPathComponent(Self.logFile(kind))) else {
            alert = AlertInfo(title: "No \(name)", message: "The iPod has no \(name.lowercased()). Click Clear the \(name). Then do the test.")
            return
        }
        var letters: [String: String] = [:]
        for p in Self.patchLibrary.list() { if let l = p.spec.version_letter { letters[p.spec.name] = l } }
        let database = (try? Data(contentsOf: volume.appendingPathComponent("iPod_Control/iTunes/iTunesDB"))).map { [UInt8]($0) } ?? []
        let text = PlaybackLog.text([UInt8](data), letters: letters, songs: ITunesDB.readTrackInfo(database)) ?? ""
        if kind == .diagnostic { diagnosticLog = text } else { playbackLog = text }
    }

    /// Save a log as a text file, then show the file in Finder. Returns the file, or nil.
    @discardableResult
    func saveSongLog(_ kind: IPodLogFile.Kind) -> URL? {
        let name = kind == .diagnostic ? "Diagnostic Log" : "Playback Log"
        guard let log = songLog(kind), !log.isEmpty else { return nil }
        let s = NSSavePanel()
        s.nameFieldStringValue = PlaybackLog.fileName(name: name)
        s.allowedContentTypes = [.plainText]
        s.message = "Save the \(name.lowercased()) as a text file. Then send the file to the developer."
        guard s.runModal() == .OK, let url = s.url else { return nil }
        do {
            try ("iPodFirm on the Mac: \(version)\n" + log + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            fail("Cannot Save the \(name)", error)
            return nil
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    /// Save a log, then open a new issue on GitHub. The owner of the log drags the file into the issue.
    func reportSongLog(_ kind: IPodLogFile.Kind) {
        guard let log = songLog(kind), let url = saveSongLog(kind) else { return }
        NSWorkspace.shared.open(PlaybackLog.issueURL(log: log, appVersion: version, fileName: url.lastPathComponent, diagnostic: kind == .diagnostic))
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

    /// Replace the folders in the editor with the folders of an iTunes library. The iPod does not
    /// change until "Write Folders to iPod".
    func importITunesFolders() {
        let p = NSOpenPanel()
        p.allowedContentTypes = ["itl"].compactMap { UTType(filenameExtension: $0) }
        p.message = "Choose the file iTunes Library.itl"
        p.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/iTunes")
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let library = try ITunesLibrary.playlists([UInt8](try Data(contentsOf: url)))
            var (folders, missing) = PlaylistFolders.imported(from: library, ipod: folderPlaylists)
            folders.folderIcons = playlistFolders.folderIcons
            playlistFolders = folders
            var status = "Imported \(counted(folders.folders.count, "folder"))."
            if !missing.isEmpty { status += " The iPod does not have \(counted(missing.count, "playlist")) of these folders." }
            playlistFoldersStatus = status + " The copy of a custom iTunes order is not tested. Examine the order."
        } catch { fail("Cannot Import from iTunes", error) }
    }

    /// Write the folder file to the iPod.
    func writePlaylistFolders() async {
        guard let volume = ipodMusicVolume() else {
            alert = AlertInfo(title: "iPod Volume Not Found", message: "Connect the iPod so that it shows in Finder. Then try again.")
            return
        }
        if playlistFolders.customOrder {
            playlistFolders.order = playlistFolders.completedOrder(playlists: folderPlaylists.map(\.persistentID))
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

    func backupNow() async {
        guard busy == nil, let ipod = currentIPod else { return }
        busy = "Backing up the iPod's firmware partition…"
        defer { busy = nil; refreshBackups() }
        do {
            let r = await runBackup(ipod)
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
            var r = await runFlash(ipod, image: image, reason: reason, dryRun: true)
            if !r.ok, r.code == OperationResult.firmwareUnreadable, reason == "restore" {
                // An interrupted write left the iPod's firmware unreadable: the normal restore cannot compare with it.
                reason = "rescue"
                r = await runFlash(ipod, image: image, reason: reason, dryRun: true)
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

    /// Step 2: the app backs up the current partition, writes only changed blocks, and verifies.
    func performFlash(_ plan: FlashPlan) async {
        flashPlan = nil
        busy = "Backup, write and check in progress… Do not disconnect the iPod."
        defer { busy = nil; refreshBackups() }
        do {
            // Do the check again: a sync can start while the sheet is open.
            try checkNoMusicSync()
            // The write unmounts the volume, thus change the settings file first.
            let mixNote = clearAlbumMixIfNeeded(image: plan.image)
            let r = await runFlash(plan.ipod, image: plan.image, reason: plan.reason, dryRun: false)
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
        let staging = Self.patchLibrary.stagingDir.appendingPathComponent("flash.bin")
        do {
            try Self.patchLibrary.prepareStagingFolder()
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
