import AppKit
import IPodFWKit
import SwiftUI

@main
struct IPodFirmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @StateObject private var emulator = EmulatorManager()
    @StateObject private var session = EmulatorSession()

    var body: some Scene {
        WindowGroup("iPodFirm") {
            ContentView()
                .environmentObject(model)
                .environmentObject(emulator)
                .environmentObject(session)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    session.stop()
                }
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { delegate.attach(model) }
                // A patch that Finder opened before the user accepted the disclaimer waits for the acceptance.
                .onChange(of: model.showDisclaimer) { _, shown in
                    if !shown {
                        delegate.attach(model)
                        Task { await model.checkForUpdate(manual: false) }
                    }
                }
                // All copies of iPodFirm share the user patches folder. Another copy can add, change or remove a patch.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.reloadPatches()
                }
        }
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Firmware…") { model.openPanel() }.keyboardShortcut("o")
                Button("Download Apple Firmware 1.3") { Task { await model.downloadAppleFirmware() } }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Firmware") { model.save() }.keyboardShortcut("s")
                    .disabled(model.editor == nil)
                Button("Save Firmware As…") { model.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.editor == nil)
                Button("Export as .ipsw…") { model.exportIPSW() }
                    .disabled(model.editor == nil)
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export Pictures & Text…") { model.exportFolder() }.disabled(model.editor == nil)
                Button("Import Pictures & Text…") { model.importFolder() }.disabled(model.editor == nil)
                Divider()
                Button("Import iPodWizard Theme…") { model.importTheme() }
                Button("New Patch…") { model.newPatch() }
                Button("Install Patch…") { model.choosePatchToInstall() }
            }
            CommandMenu("iPod") {
                Button("Flash to iPod…") { model.section = .ipod; Task { await model.flashEdited() } }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(!model.canFlash)
                Button("Back Up iPod") { model.section = .ipod; Task { await model.backupNow() } }
                    .disabled(model.currentIPod == nil || model.currentIPodIsUnsupported || model.busy != nil)
                Button("Eject iPod") { Task { await model.ejectIPod() } }
                    .keyboardShortcut("e")
                    .disabled(model.currentIPod == nil || model.busy != nil)
                Divider()
                Button("Run in Emulator") { model.section = .emulator; model.runInEmulator(emulator, session) }
                    .keyboardShortcut("r")
                    .disabled(model.editor == nil || !emulator.toolsReady)
            }
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(Array(([Pane.ipod] + Pane.tools).enumerated()), id: \.element) { i, pane in
                    Button(pane.rawValue) { model.section = pane }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await model.checkForUpdate(manual: true) } }
            }
            // The app has no help book. The default Help item only gives an error.
            CommandGroup(replacing: .help) {
                Button("iPodFirm Documentation") { NSWorkspace.shared.open(UpdateCheck.repository) }
                Divider()
                Button("Show Disclaimer") { model.showDisclaimerReview = true }
                Button("Thanks…") { model.showThanks = true }
                Divider()
                Button("Open Log") { model.openLog() }
                Button("Save Log…") { model.saveLog() }
                Button("Report a Problem on GitHub…") { model.reportOnGitHub(nil) }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// The settings window (⌘,): the permissions that the app needs to write to the iPod, and the
/// firmware layout (the empty margin below 8 MB).
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showHelp = false
    @AppStorage(ThemeImport.ososMarginKey) private var ososMargin = ThemeImport.OSOSMargin.current.rawValue
    @AppStorage("showPatchSummaries") private var showPatchSummaries = true

    var body: some View {
        TabView {
            Form {
                Section {
                    HelperRow()
                    if model.helperStatus == .enabled {
                        Toggle("Ask for Touch ID before a flash or a restore", isOn: $model.requireTouchID)
                    }
                } header: {
                    Text("Touch ID")
                }
                Section {
                    FullDiskAccessRow { showHelp = true }
                } header: {
                    Text("Full Disk Access")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Permissions", systemImage: "lock.shield") }
            Form {
                Section {
                    Picker("Empty margin below 8 MB", selection: $ososMargin) {
                        ForEach(ThemeImport.OSOSMargin.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .help("A theme, the Dark Mode items and the extended patches stay below this limit. Use 16 KB if the patches do not fit. Use 64 KB to test if the margin causes a problem. The setting applies to the next build.")
                } header: {
                    Text("Firmware Layout")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Layout", systemImage: "square.stack.3d.up") }
            Form {
                Section {
                    Toggle("Enable Test Patches", isOn: $model.showTestPatches)
                        .help("Test patches are for research. They can make the iPod unstable. When this setting is off, the Patches pane does not show them, and iPodFirm does not include them in a firmware.")
                } header: {
                    Text("Test Patches")
                }
                Section {
                    Toggle("Show Descriptions in the Patch List", isOn: $showPatchSummaries)
                } header: {
                    Text("Patch List")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Patches", systemImage: "puzzlepiece.extension") }
            Form {
                Section {
                    Toggle("Check for a new version at launch", isOn: $model.checkForUpdates)
                        .help("iPodFirm asks GitHub for the number of the newest release. It sends no data about you or your iPod. iPodFirm does not download the update.")
                } header: {
                    Text("Updates")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 560, height: 380)
        .onAppear { model.recheckFullDiskAccess() }
        .sheet(isPresented: $showHelp) { FullDiskAccessSheet().environmentObject(model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    /// Files that macOS opened before the window showed.
    private var pending: [URL] = []

    @MainActor func attach(_ model: AppModel) {
        self.model = model
        guard Disclaimer.accepted else { return }
        let urls = pending
        pending = []
        for url in urls { Task { await model.installPatch(from: url) } }
    }

    /// A double-click on a .ipodpatch file in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        let patches = urls.filter(isPatchURL)
        Task { @MainActor in
            guard let model, Disclaimer.accepted else { pending += patches; return }
            for url in patches { await model.installPatch(from: url) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary ?? [:]
        AppLog.info("Launch: iPodFirm \(info["CFBundleShortVersionString"] as? String ?? "dev") (\(info["CFBundleVersion"] as? String ?? "0")), \(AppLog.systemDescription)")
        NSApp.setActivationPolicy(.regular)
        UpdateNotifier.shared.register()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.confirmQuit() == false ? .terminateCancel : .terminateNow
    }
}

/// Connects the window to the unsaved work. The close button shows the dot of an edited document, and
/// a close of the window asks before it loses work. SwiftUI owns the delegate of the window. Thus this
/// delegate gets only windowShouldClose and sends all other calls to the delegate of SwiftUI.
struct WindowGuard: NSViewRepresentable {
    let edited: Bool
    let shouldClose: () -> Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.shouldClose = shouldClose
        let edited = edited
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isDocumentEdited = edited
            context.coordinator.attach(to: window)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(shouldClose: shouldClose) }

    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldClose: () -> Bool
        private var original: NSWindowDelegate?

        init(shouldClose: @escaping () -> Bool) { self.shouldClose = shouldClose }

        func attach(to window: NSWindow) {
            guard window.delegate !== self else { return }
            original = window.delegate
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldClose() else { return false }
            return original?.windowShouldClose?(sender) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : nil
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                Section("Device") {
                    IPodSidebarRow().tag(Pane.ipod)
                }
                Section("Tools") {
                    ForEach(Pane.tools) { s in
                        Label(s.rawValue, systemImage: s.symbol).tag(s)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            Group {
                switch model.section {
                case .overview: model.editor == nil ? AnyView(WelcomeView()) : AnyView(OverviewView())
                case .pictures: model.editor == nil ? AnyView(WelcomeView()) : AnyView(PicturesView())
                case .strings: model.editor == nil ? AnyView(WelcomeView()) : AnyView(StringsView())
                case .patches: AnyView(PatchesView())
                case .games: AnyView(GamesView())
                case .ipod: AnyView(IPodView())
                case .emulator: AnyView(EmulatorView())
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { model.openPanel() } label: { Label("Open", systemImage: "folder") }
                        .help("Open an .ipsw file, a firmware image or a backup")
                    Button { model.saveAs() } label: { Label("Save As", systemImage: "square.and.arrow.down") }
                        .disabled(model.editor == nil).help("Save the changed firmware image")
                    Button { model.section = .ipod; Task { await model.flashEdited() } } label: {
                        Label("Flash to iPod…", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(!model.canFlash).help("Make a backup of the iPod, then write this firmware to the iPod")
                }
            }
        }
        .navigationTitle(title)
        .background(WindowGuard(edited: model.hasUnsavedWork) { model.confirmQuit() })
        .overlay {
            if let busy = model.busy {
                BusyOverlay(text: busy, progress: model.downloadProgress, cancel: model.downloadTask.map { task in { task.cancel() } })
            }
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
               presenting: model.alert) { a in
            // A fault gives two more choices: a report on GitHub, and the log as a file to share.
            if a.isFault {
                Button("Report on GitHub…") { model.reportOnGitHub(a) }
                Button("Save Log…") { model.saveLog() }
                Button("OK", role: .cancel) {}.keyboardShortcut(.defaultAction)
            } else {
                Button("OK") {}
            }
        } message: { a in
            Text(a.message)
        }
        .sheet(item: $model.flashPlan) { plan in FlashConfirmSheet(plan: plan) }
        .sheet(item: $model.themeReport) { t in ThemeReportSheet(theme: t) }
        .sheet(item: $model.pendingInstall) { c in InstallPatchSheet(candidate: c) }
        .sheet(item: $model.patchEditor) { s in PatchEditorSheet(state: s) }
        .sheet(isPresented: $model.showFullDiskAccessHelp) { FullDiskAccessSheet() }
        .sheet(isPresented: $model.showFinderRestoreHelp) { FinderRestoreSheet() }
        .sheet(isPresented: $model.showDisclaimer) { DisclaimerSheet(review: false).interactiveDismissDisabled() }
        .sheet(isPresented: $model.showDisclaimerReview) { DisclaimerSheet(review: true) }
        .sheet(isPresented: $model.showThanks) { ThanksSheet() }
        .sheet(item: $model.shownLog) { IPodLogSheet(log: $0) }
        .task { await model.refreshIPods() }
        .task {
            // A connected or disconnected iPod: find the iPods again, and read the patches on a new iPod.
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didMountNotification) {
                await model.refreshIPods()
            }
        }
        .task {
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didUnmountNotification) {
                await model.refreshIPods()
            }
        }
        .task { await model.recordMissingPatchSizes() }
        .task { await model.checkForUpdate(manual: false) }
        // The fallback if macOS does not allow notifications from iPodFirm.
        .alert("A New Version of iPodFirm Is Available",
               isPresented: Binding(get: { model.availableUpdate != nil }, set: { if !$0 { model.availableUpdate = nil } }),
               presenting: model.availableUpdate) { release in
            Button("Open GitHub") { NSWorkspace.shared.open(release.url) }.keyboardShortcut(.defaultAction)
            Button("Skip This Version") { model.skippedUpdateVersion = release.version }
            Button("Later", role: .cancel) {}
        } message: { release in
            Text("Version \(release.version) is on GitHub. You have version \(model.shortVersion). Download the new version from the GitHub release page.")
        }
    }

    var title: String {
        guard let url = model.fileURL else { return "iPodFirm" }
        return url.lastPathComponent + (model.isDirty ? " — Edited" : "")
    }
}

/// The iPod row of the sidebar. The text gives the state in words, so that color is not the only signal.
struct IPodSidebarRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Label {
            Text(model.currentIPodStatus).lineLimit(1)
        } icon: {
            Image(systemName: Pane.ipod.symbol)
        }
        .listItemTint(model.currentIPod != nil && !model.currentIPodIsUnsupported ? ListItemTint.fixed(.green) : .monochrome)
        .accessibilityLabel("\(Pane.ipod.rawValue): \(model.currentIPodStatus)")
    }
}

struct SidebarFooter: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Text("Version \(model.version)").font(.caption2).foregroundStyle(.tertiary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BusyOverlay: View {
    let text: String
    /// The fraction that is complete, if the operation knows it.
    var progress: Double?
    /// The action of the Cancel button. A flash has no Cancel: a stop in the write damages the firmware.
    var cancel: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                if let progress {
                    ProgressView(value: progress).frame(width: 220)
                } else {
                    ProgressView()
                }
                Text(text).multilineTextAlignment(.center)
                if let cancel { Button("Cancel", action: cancel) }
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            Text("Customise the Firmware of Your iPod").font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                Button("Open Firmware…") { model.openPanel() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                Button("Download Apple Firmware 1.3") { Task { await model.downloadAppleFirmware() } }
                Button("Go to iPod") { model.section = .ipod }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
