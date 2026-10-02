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
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Firmware…") { model.openPanel() }.keyboardShortcut("o")
                Button("Download Apple Firmware 1.3") { Task { await model.downloadAppleFirmware() } }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Firmware As…") { model.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.editor == nil)
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Export Pictures & Text…") { model.exportFolder() }.disabled(model.editor == nil)
                Button("Import Pictures & Text…") { model.importFolder() }.disabled(model.editor == nil)
                Divider()
                Button("Import iPodWizard Theme…") { model.importTheme() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
                        .help("Open an .ipsw, firmware image or backup")
                    Button { model.saveAs() } label: { Label("Save As", systemImage: "square.and.arrow.down") }
                        .disabled(model.editor == nil).help("Save the customised firmware image")
                    Button { model.section = .ipod; Task { await model.flashEdited() } } label: {
                        Label("Flash to iPod", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(model.editor == nil).help("Back up the iPod, then write this firmware to it")
                }
            }
        }
        .navigationTitle(title)
        .overlay { if let busy = model.busy { BusyOverlay(text: busy) } }
        .alert(item: $model.alert) { a in Alert(title: Text(a.title), message: Text(a.message)) }
        .sheet(item: $model.flashPlan) { plan in FlashConfirmSheet(plan: plan) }
        .sheet(item: $model.themeReport) { t in ThemeReportSheet(theme: t) }
        .sheet(isPresented: $model.showFullDiskAccessHelp) { FullDiskAccessSheet() }
        .sheet(isPresented: $model.showFinderRestoreHelp) { FinderRestoreSheet() }
        .task { await model.refreshIPods() }
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
            Text("Customise your iPod's stock firmware").font(.title2.weight(.semibold))
            Text("Open Apple's firmware or a backup of your iPod, change pictures and text, then flash it.\nThe iPod is backed up automatically before every flash.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Open Firmware…") { model.openPanel() }
                Button("Download Apple Firmware 1.3") { Task { await model.downloadAppleFirmware() } }
                Button("Back Up My iPod…") { model.section = .ipod }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
