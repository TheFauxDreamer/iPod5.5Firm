import AppKit
import IPodFWKit
import SwiftUI
import UniformTypeIdentifiers

/// Code patches: changes to the behaviour of the iPod software. Each one can be switched on or off.
/// A list at the left (the firmware options and the patches) and the detail of the selected row at the right.
struct PatchesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HSplitView {
            PatchList()
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder var detail: some View {
        if model.patchSelection == "version" {
            VersionDetail()
        } else if let name = model.patchSelection, let patch = model.patches.first(where: { $0.spec.name == name }) {
            PatchDetail(patch: patch)
        } else {
            AppearanceDetail()
        }
    }
}

// MARK: the list

/// The space for the theme and the patches after Apple's image. It changes when a patch or the
/// appearance changes, so the owner sees before a flash if the firmware is too large.
struct SpaceUseRow: View {
    @EnvironmentObject var model: AppModel

    var key: String {
        "\(model.enabledPatches.sorted())|\(model.appearance)|\(model.selectedThemeName ?? "")|\(model.editor.map { ObjectIdentifier($0).hashValue } ?? 0)|\(model.patches.count)"
    }

    var body: some View {
        Group {
            if let s = model.spaceUse {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: Double(min(s.used, s.total)), total: Double(s.total))
                        .tint(!s.fits ? .red : Double(s.used) > 0.9 * Double(s.total) ? .orange : .accentColor)
                        .accessibilityLabel("Space used")
                    if s.fits {
                        Text("Space for the theme and the patches: \(kb(s.used)) of \(kb(s.total)) used, \(kb(s.total - s.used)) free.")
                    } else {
                        Label("The firmware is too large by \(kb(s.end - Patcher.SpaceUse.limit)). Switch off a patch, or choose Light.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            } else if model.editor != nil {
                Text("Measuring the space…")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .task(id: key) {
            try? await Task.sleep(nanoseconds: 300_000_000)    // wait for more changes
            guard !Task.isCancelled else { return }
            await model.refreshSpaceUse()
        }
    }

    func kb(_ bytes: Int) -> String { String(format: "%.1f KB", Double(bytes) / 1024) }
}

struct PatchList: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTargeted = false
    @State private var confirmRemove: PatchInfo?

    static let groups = [("display", "Display"), ("power", "Power and Storage"), ("audio", "Sound"), ("fun", "Fun"), ("test", "Tests")]

    var groups: [(title: String, patches: [PatchInfo])] {
        var result = Self.groups.map { key, title in (title, model.patches.filter { $0.spec.category == key }) }
        result.append(("Other", model.patches.filter { !PatchSpec.categories.contains($0.spec.category ?? "") }))
        return result.filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.patchSelection) {
                Section("Firmware Options") {
                    OptionRow(title: "iPod Appearance", subtitle: appearanceSummary, symbol: "circle.lefthalf.filled", tint: .indigo)
                        .tag("appearance")
                    OptionRow(title: "Software Version", subtitle: versionSummary, symbol: "number", tint: .teal)
                        .tag("version")
                }
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.patches) { p in
                            PatchListRow(patch: p).tag(p.spec.name)
                                .contextMenu {
                                    Button("Export Patch…") { model.exportPatch(p) }
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([p.folder]) }
                                    if p.source == .user {
                                        Divider()
                                        Button("Remove Patch…") { confirmRemove = p }
                                    }
                                }
                        }
                    }
                }
                if model.patches.isEmpty {
                    Text("This copy of iPodFirm has no patches.").foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: dropTargeted ? 3 : 0))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, isPatchURL(url) else { return }
                    Task { @MainActor in await model.installPatch(from: url) }
                }
                return true
            }
            Divider()
            HStack(spacing: 0) {
                Button { model.choosePatchToInstall() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                    .help("Install a patch").accessibilityLabel("Install Patch")
                Button { confirmRemove = selectedPatch } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .disabled(selectedPatch?.source != .user)
                    .help("Remove the selected patch").accessibilityLabel("Remove Patch")
                Spacer()
                Menu {
                    Button("Install Patch…") { model.choosePatchToInstall() }
                    Button("Export Patch…") { if let p = selectedPatch { model.exportPatch(p) } }.disabled(selectedPatch == nil)
                    Divider()
                    Button("Show Patches Folder") { model.showPatchesFolder() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More Patch Actions")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8).padding(.vertical, 4)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                SpaceUseRow()
                Text("Turned-on patches: \(model.activePatches.count)")
                Text("To install a patch, drag a .ipodpatch file here.")
                if model.editor == nil {
                    Label("Open a firmware to see which patches agree with it.", systemImage: "info.circle")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .confirmationDialog("Remove the patch \"\(confirmRemove?.spec.displayTitle ?? "")\"?", isPresented: Binding(
            get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), presenting: confirmRemove) { p in
            Button("Move to Trash", role: .destructive) { model.removePatch(p) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("iPodFirm moves the patch folder to the Trash. Firmware that you flashed before does not change.")
        }
    }

    var selectedPatch: PatchInfo? { model.patches.first { $0.spec.name == model.patchSelection } }

    var appearanceSummary: String {
        let name = model.selectedTheme?.name ?? ""
        switch model.appearance {
        case .light: return "Light"
        case .dark: return "Dark: \(name)"
        case .onIPod: return "Switch on iPod: \(name)"
        }
    }

    var versionSummary: String {
        model.activeVersion.map { "About shows \($0.description)" } ?? "Not changed"
    }
}

/// A row for iPod Appearance or Software Version. It has no switch.
struct OptionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            SymbolTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

struct PatchListRow: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        HStack(spacing: 10) {
            SymbolTile(symbol: validSymbol(patch.spec.symbol), tint: patch.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(patch.spec.displayTitle)
                    LetterBadge(patch: patch)
                    if let v = patch.spec.version { Text(v).font(.caption).foregroundStyle(.secondary) }
                    if let n = patch.spec.size { Text(n.formatted(.byteCount(style: .memory))).font(.caption).foregroundStyle(.secondary) }
                }
                if let summary = patch.spec.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if let problem = model.problem(patch) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(problem).accessibilityLabel(problem)
            }
            PatchSwitch(patch: patch).controlSize(.small)
        }
        .padding(.vertical, 3)
    }
}

/// An SF Symbol in a coloured rounded square, as in System Settings.
struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

/// The version letter of a patch.
struct LetterBadge: View {
    let patch: PatchInfo

    var body: some View {
        if let letter = patch.spec.version_letter {
            Text(letter).font(.caption.monospaced().bold())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                .help("The version letter of this patch. The About screen shows it after the version when \"Add a letter for each switched-on patch\" is on.")
                .accessibilityLabel("Version letter \(letter)")
        }
    }
}

/// The switch that turns a patch on or off. Without a label, the title of the patch is the accessibility label.
struct PatchSwitch: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo
    var label: String?

    var body: some View {
        let on = Binding(
            get: { model.enabledPatches.contains(patch.spec.name) },
            set: { v in
                if v && !confirmOnHDD() { return }
                model.setPatch(patch, on: v)
            })
        if let label {
            Toggle(label, isOn: on).toggleStyle(.switch)
        } else {
            Toggle(patch.spec.displayTitle, isOn: on).toggleStyle(.switch).labelsHidden()
        }
    }

    /// true: turn the patch on. Asks first if the patch is for flash storage and the connected iPod
    /// probably has the original hard drive.
    func confirmOnHDD() -> Bool {
        guard let warning = patch.spec.hdd_warning, let gb = model.currentIPod?.likelyOriginalHDD else { return true }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "This iPod probably has the original hard drive"
        a.informativeText = "The connected iPod has approximately \(gb) GB, the size of an original iPod hard drive. \(warning) If the iPod has a flash adapter of this size, you can turn the patch on."
        a.addButton(withTitle: "Turn On")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }
}

extension PatchInfo {
    var tint: Color {
        switch spec.category {
        case "display": .blue
        case "power": .green
        case "audio": .orange
        case "fun": .pink
        default: .gray
        }
    }
}

extension AppModel {
    /// A short text if the patch has a problem: it does not agree with the open firmware, or it is
    /// for flash storage and the connected iPod probably has the original hard drive.
    func problem(_ patch: PatchInfo) -> String? {
        if editor != nil && !isCompatible(patch) { return "Does not agree with the open firmware." }
        if patch.spec.hdd_warning != nil, currentIPod?.likelyOriginalHDD != nil {
            return "The connected iPod probably has the original hard drive."
        }
        if let (other, _) = conflicts(patch).first { return "Changes the same place as \"\(other.spec.displayTitle)\"." }
        return nil
    }
}

// MARK: the detail of a patch

/// The title row at the top of each detail.
struct DetailHeader: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    var patch: PatchInfo?

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(symbol: symbol, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.title2.weight(.semibold))
                    if let patch { LetterBadge(patch: patch) }
                }
                if let subtitle { Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PatchDetail: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        Form {
            Section {
                DetailHeader(title: patch.spec.displayTitle, subtitle: patch.spec.summary,
                             symbol: validSymbol(patch.spec.symbol), tint: patch.tint, patch: patch)
                if let caution = patch.spec.caution {
                    Label(caution, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                PatchSwitch(patch: patch, label: "Include in Firmware")
                    .help("iPodFirm includes the turned-on patches when you save, flash, export an .ipsw or run the emulator. Your picture and text changes stay as they are.")
            }
            PatchAbout(spec: patch.spec)
            Section("Compatibility") {
                PatchCompatibility(patch: patch)
                ForEach(model.conflicts(patch), id: \.0.id) { other, place in
                    Label("Changes the same place as \"\(other.spec.displayTitle)\" (\(place)). You cannot turn on the two patches together.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("Version", value: patch.spec.versionText)
                LabeledContent("Size on iPod", value: patch.spec.sizeText)
                if patch.spec.size == 0 {
                    Text("The patch adds no code. It changes only bytes that are already in the firmware.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("Source", value: patch.source == .user ? "Installed by you" : "Included with iPodFirm")
                if patch.replacesBuiltIn {
                    Text("This patch replaces the built-in version \(patch.builtInVersion ?? "–"). To use the built-in patch again, remove this patch.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            PatchControls(patch: patch)
        }
        .formStyle(.grouped)
        .task(id: "\(patch.spec.name) \(model.currentIPod?.disk ?? "")") { model.loadPatchToggles(patch) }
    }
}

/// The text of a patch in sections: What It Does, You Need and Good to Know.
struct PatchAbout: View {
    let spec: PatchSpec

    var body: some View {
        Section("What It Does") {
            if let d = spec.description { Text(d).fixedSize(horizontal: false, vertical: true) }
            ForEach(spec.details ?? [], id: \.self) { BulletRow(text: $0) }
            if spec.description == nil && spec.details == nil { Text(spec.name).foregroundStyle(.secondary) }
        }
        if let items = spec.requires, !items.isEmpty {
            Section("You Need") {
                ForEach(items, id: \.self) { BulletRow(text: $0, symbol: "checkmark.circle", tint: .green) }
            }
        }
        if let items = spec.notes, !items.isEmpty {
            Section("Good to Know") {
                ForEach(items, id: \.self) { BulletRow(text: $0, symbol: "info.circle", tint: .secondary) }
            }
        }
    }
}

/// One item of a list: a symbol (or a bullet) and a text that wraps.
struct BulletRow: View {
    let text: String
    var symbol: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if let symbol { Image(systemName: symbol) } else { Text("•").bold() }
            }
            .foregroundStyle(tint)
            .frame(width: 14)
            .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The text below a section of a form. It is left-aligned: macOS aligns a footer with more than one line at the right.
struct FormFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The firmware and storage checks of a patch.
struct PatchCompatibility: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        LabeledContent("For", value: patch.spec.targetText)
        if model.editor == nil {
            Label("Open a firmware to examine this patch.", systemImage: "info.circle").foregroundStyle(.secondary)
        } else if model.isCompatible(patch) {
            Label("Agrees with the open firmware.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Does not agree with the open firmware. The patch is only for the original Apple firmware of its target. iPodFirm does not apply it.",
                  systemImage: "xmark.octagon.fill")
                .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
        if let warning = patch.spec.hdd_warning {
            if let gb = model.currentIPod?.likelyOriginalHDD {
                Label("The connected iPod has approximately \(gb) GB. This is the size of an original hard drive. \(warning)",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if let ipod = model.currentIPod {
                Label("The connected iPod has \(ByteCountFormatter.string(fromByteCount: ipod.size, countStyle: .decimal)). No original iPod drive has this size, thus the storage is flash.",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Connect the iPod to examine its storage.", systemImage: "info.circle").foregroundStyle(.secondary)
            }
        }
    }
}

/// The buttons of a tool that operates on the connected iPod, and the Eject iPod button.
struct IPodActionsRow<Actions: View>: View {
    @EnvironmentObject var model: AppModel
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack {
            actions.disabled(model.currentIPod == nil)
            Spacer()
            if model.currentIPod == nil { Text("Connect the iPod.").font(.caption).foregroundStyle(.secondary) }
            Button("Eject iPod") { Task { await model.ejectIPod() } }
                .disabled(model.currentIPod == nil)
        }
    }
}

// MARK: iPod Appearance

/// Light, Dark or Switch on iPod, and the imported dark themes.
struct AppearanceDetail: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDelete: AppModel.ThemeFile?

    var body: some View {
        Form {
            Section {
                DetailHeader(title: "iPod Appearance", subtitle: "The colours of the iPod software.",
                             symbol: "circle.lefthalf.filled", tint: .indigo)
            }
            Section {
                AppearanceControl(selection: $model.appearance) { a in
                    switch a {
                    case .light: true
                    case .dark: !model.themes.isEmpty
                    case .onIPod: !model.themes.isEmpty && AppModel.darkModePatch != nil
                    }
                }
                .frame(maxWidth: 380)
                .accessibilityLabel("Appearance")
                if model.appearance == .onIPod {
                    Text("The firmware starts light. In Settings on the iPod, select \"Dark Mode\" to change between light and dark. The iPod saves its settings and restarts (a few seconds). The choice is in the file iPod_Control/iTunes/iPodFirmDarkMode.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Appearance")
            } footer: {
                FormFooter("Light uses the Apple colours. Dark applies an imported dark theme when you save, flash, export an .ipsw or run the emulator. Switch on iPod adds a \"Dark Mode\" item to Settings on the iPod.")
            }
            Section("Dark Theme") {
                if model.themes.isEmpty {
                    Label("Import a dark theme first.", systemImage: "info.circle").foregroundStyle(.secondary)
                } else if let current = model.selectedTheme {
                    Picker("Dark theme", selection: Binding(get: { current.name }, set: { model.selectedThemeName = $0 })) {
                        ForEach(model.themes) { Text($0.name).tag($0.name) }
                    }
                    if model.editor != nil {
                        if model.isCompatible(current.theme) {
                            Label("Agrees with the open firmware (iPod Video 1.3).", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Does not agree with the open firmware. The theme is only for the original Apple firmware 1.3.",
                                  systemImage: "xmark.octagon.fill").foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    LabeledContent("Size on iPod (Dark)", value: PatchSpec.byteText(current.theme.addedSize))
                    LabeledContent("Size on iPod (Switch on iPod)",
                                   value: model.switchOnIPodSize.map(PatchSpec.byteText) ?? "Open the firmware 1.3 to calculate")
                    Text("The size is the new space after the end of the iPod software. The theme also changes \(PatchSpec.byteText(current.theme.changedSize)) of the Apple pictures and layouts. These changes use no new space. Switch on iPod also adds the Dark Mode switch table, the Settings item and the code (\(AppModel.darkModePatch?.spec.sizeText ?? "–")).")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.appearance != .light {
                        Text("The theme makes the iPod software larger. iPodFirm moves the rsrc image (fonts and video firmware) to free space in the firmware partition. It does not move or change aupd or hibe.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Show Import Report") { model.themeReport = current.theme }
                        Spacer()
                        Button("Delete Theme…", role: .destructive) { confirmDelete = current }
                    }
                }
            }
            Section {
                Button("Import iPodWizard Theme…") { model.importTheme() }
            } header: {
                Text("Import")
            } footer: {
                FormFooter("Select the theme file (a firmware file from iPodWizard), then the Apple firmware that the theme came from, for example iPod_25.1.2.1.ipsw. iPodFirm moves the pictures, colours and layouts of the theme to firmware 1.3.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete the theme \"\(confirmDelete?.name ?? "")\"?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), presenting: confirmDelete) { t in
            Button("Delete Theme", role: .destructive) { model.deleteTheme(t) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("iPodFirm removes the imported theme from this Mac. You can import it again.")
        }
    }
}

// MARK: Software Version

/// A different version on the About screen of the iPod, and letters for the switched-on patches. Off by default.
struct VersionDetail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                DetailHeader(title: "Software Version", subtitle: "The version on the About screen of the iPod.",
                             symbol: "number", tint: .teal)
            }
            Section {
                Toggle("Show a different version on the About screen", isOn: $model.customVersionOn)
                if model.customVersionOn {
                    TextField("Version", text: $model.customVersion, prompt: Text("1.3.1"))
                    if FirmwareVersion(model.customVersion) == nil {
                        Label("This version is not valid. Use the format 1.3 or 1.3.1. The first number is 0–255. The other numbers are 0–15. The firmware keeps version 1.3.",
                              systemImage: "xmark.octagon.fill").foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle("Add a letter for each switched-on patch", isOn: $model.versionLettersOn)
                LabeledContent("About screen", value: model.activeVersion?.description ?? "1.3")
                if let v = model.activeVersion, v.description.count > FirmwareVersion.maxTextLength {
                    Label("This version has more than \(FirmwareVersion.maxTextLength) characters. The About screen cannot show it. Switch off some patches or the letters.",
                          systemImage: "xmark.octagon.fill").foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Version")
            } footer: {
                FormFooter("This changes only the text on the iPod. iTunes and Finder continue to see version 1.3.")
            }
            Section("Letters") {
                ForEach(model.patches.filter { $0.spec.version_letter != nil }) { p in
                    HStack(spacing: 8) {
                        LetterBadge(patch: p)
                        Text(p.spec.displayTitle)
                        Spacer()
                        Text(model.enabledPatches.contains(p.spec.name) ? "On" : "Off").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A segmented control in which each option can be disabled.
struct AppearanceControl: NSViewRepresentable {
    @Binding var selection: AppModel.Appearance
    var isEnabled: (AppModel.Appearance) -> Bool

    func makeNSView(context: Context) -> NSSegmentedControl {
        NSSegmentedControl(labels: AppModel.Appearance.allCases.map(\.title), trackingMode: .selectOne,
                           target: context.coordinator, action: #selector(Coordinator.changed(_:)))
    }

    func updateNSView(_ c: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        for (i, a) in AppModel.Appearance.allCases.enumerated() { c.setEnabled(isEnabled(a), forSegment: i) }
        c.selectedSegment = AppModel.Appearance.allCases.firstIndex(of: selection) ?? 0
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: AppearanceControl
        init(_ parent: AppearanceControl) { self.parent = parent }
        @objc func changed(_ c: NSSegmentedControl) {
            let a = AppModel.Appearance.allCases[c.selectedSegment]
            if parent.isEnabled(a) { parent.selection = a } else { c.selectedSegment = AppModel.Appearance.allCases.firstIndex(of: parent.selection) ?? 0 }
        }
    }
}

/// What the import of a theme changed, and what it did not change.
struct ThemeReportSheet: View {
    @Environment(\.dismiss) var dismiss
    let theme: ImportedTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(theme.name).font(.title2.weight(.semibold))
            Text("Imported: \(theme.imported.count) resources (\(counts(theme.imported))). \(theme.changes.count) changes.")
            Text("Not imported: \(theme.skipped.count)").font(.headline)
            List(Array(theme.skipped.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.resource).monospaced()
                    Text(s.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 260)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }

    func counts(_ labels: [String]) -> String {
        var c: [String: Int] = [:]
        for l in labels { c[String(l.split(separator: " ").first ?? ""), default: 0] += 1 }
        return c.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }
}
