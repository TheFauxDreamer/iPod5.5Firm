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
        }
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Firmware…") { model.openPanel() }.keyboardShortcut("o")
                Button("Download Apple Firmware 1.3") { Task { await model.downloadAppleFirmware() } }
            }
            CommandGroup(replacing: .saveItem) {
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
                Button("Install Patch…") { model.choosePatchToInstall() }
            }
            CommandMenu("iPod") {
                Button("Flash to iPod…") { model.section = .ipod; Task { await model.flashEdited() } }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(model.editor == nil)
                Button("Back Up iPod") { model.section = .ipod; Task { await model.backupNow() } }
                    .disabled(model.currentIPod == nil || model.currentIPodIsUnsupported)
                Button("Eject iPod") { Task { await model.ejectIPod() } }
                    .keyboardShortcut("e")
                    .disabled(model.currentIPod == nil)
                Divider()
                Button("Run in Emulator") { model.section = .emulator; model.runInEmulator(emulator, session) }
                    .keyboardShortcut("r")
                    .disabled(model.editor == nil || !emulator.toolsReady)
            }
        }
        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// The settings window (⌘,): the permissions that the app needs to write to the iPod.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showHelp = false

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
        }
        .frame(width: 560, height: 300)
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
        let urls = pending
        pending = []
        for url in urls { Task { await model.installPatch(from: url) } }
    }

    /// A double-click on a .ipodpatch file in Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        let patches = urls.filter(isPatchURL)
        Task { @MainActor in
            guard let model else { pending += patches; return }
            for url in patches { await model.installPatch(from: url) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $model.section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            Group {
                switch model.section {
                case .overview: model.editor == nil ? AnyView(WelcomeView()) : AnyView(OverviewView())
                case .pictures: model.editor == nil ? AnyView(WelcomeView()) : AnyView(PicturesView())
                case .strings: model.editor == nil ? AnyView(WelcomeView()) : AnyView(StringsView())
                case .patches: AnyView(PatchesView())
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
                        Label("Flash to iPod", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(model.editor == nil).help("Make a backup of the iPod, then write this firmware to the iPod")
                }
            }
        }
        .navigationTitle(title)
        .overlay { if let busy = model.busy { BusyOverlay(text: busy) } }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
               presenting: model.alert) { _ in
            Button("OK") {}
        } message: { a in
            Text(a.message)
        }
        .sheet(item: $model.flashPlan) { plan in FlashConfirmSheet(plan: plan) }
        .sheet(item: $model.themeReport) { t in ThemeReportSheet(theme: t) }
        .sheet(item: $model.pendingInstall) { c in InstallPatchSheet(candidate: c) }
        .sheet(isPresented: $model.showFullDiskAccessHelp) { FullDiskAccessSheet() }
        .sheet(isPresented: $model.showFinderRestoreHelp) { FinderRestoreSheet() }
        .task { await model.refreshIPods() }
        .task { await model.recordMissingPatchSizes() }
    }

    var title: String {
        guard let url = model.fileURL else { return "iPodFirm" }
        return url.lastPathComponent + (model.isDirty ? " — Edited" : "")
    }
}

struct SidebarFooter: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ipod = model.currentIPod {
                Label(ipod.volumeName ?? ipod.mediaName, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            } else {
                Label("No iPod connected", systemImage: "circle.dashed").foregroundStyle(.secondary).font(.caption)
            }
            Text("Version \(model.version)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BusyOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text(text).multilineTextAlignment(.center)
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
            Text("Open the Apple firmware or a backup of your iPod. Change the pictures and the text. Then flash the firmware to the iPod.\niPodFirm makes a backup of the iPod before each flash.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Open Firmware…") { model.openPanel() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                Button("Download Apple Firmware 1.3") { Task { await model.downloadAppleFirmware() } }
                Button("Back Up My iPod…") { model.section = .ipod }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
