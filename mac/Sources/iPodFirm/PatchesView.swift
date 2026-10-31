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
                    SpaceBar(use: s, parts: parts(s))
                    if s.fits {
                        Text("\(kb(s.used)) of \(kb(s.total)) used, \(kb(s.total - s.used)) remaining · \(onCount)")
                    } else {
                        Label("The firmware is too large by \(kb(s.end - Patcher.SpaceUse.limit)). Switch off a patch, or choose Light.", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(StatusLabelStyle(tint: .red))
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

    var onCount: String { model.activePatches.count == 1 ? "1 patch on" : "\(model.activePatches.count) patches on" }

    func kb(_ bytes: Int) -> String { String(format: "%.1f KB", Double(bytes) / 1024) }

    /// The parts of the bar with a name and a color: the patches get the colors of a fixed palette in
    /// build order, so that two patches of the same category are different.
    func parts(_ s: Patcher.SpaceUse) -> [SpacePart] {
        var index = 0
        return s.parts.map { part in
            switch part.kind {
            case .appearance:
                return SpacePart(name: "Theme and Dark Mode", bytes: part.bytes, color: .indigo)
            case .list:
                return SpacePart(name: "iPodFirm list", bytes: part.bytes, color: .gray)
            case .padding:
                return SpacePart(name: "Rounding to 2 KB", bytes: part.bytes, color: .gray.opacity(0.5))
            case .patch(let name):
                defer { index += 1 }
                let title = model.patches.first { $0.spec.name == name }?.spec.displayTitle ?? name
                return SpacePart(name: title, bytes: part.bytes, color: SpacePart.palette[index % SpacePart.palette.count])
            }
        }
    }
}

/// One part of the space bar.
struct SpacePart: Identifiable {
    let name: String
    let bytes: Int
    let color: Color
    var id: String { name }
    static let palette: [Color] = [.blue, .green, .orange, .pink, .teal, .yellow, .purple, .mint, .brown, .cyan]
    var text: String { "\(name): " + String(format: "%.1f KB", Double(bytes) / 1024) }
}

/// The bar: a part for each patch, the theme and the rounding, on the free space. Too large: red at the end.
struct SpaceBar: View {
    let use: Patcher.SpaceUse
    let parts: [SpacePart]

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Double(max(use.total, use.used, 1))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.2))
                HStack(spacing: 0) {
                    ForEach(parts) { p in
                        Rectangle().fill(p.color)
                            .frame(width: max(1, Double(p.bytes) * scale))
                            .help(p.text)
                    }
                }
                if !use.fits {                                  // the limit
                    Rectangle().fill(Color.red).frame(width: 2).offset(x: Double(use.total) * scale - 1)
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel("Space used")
        .accessibilityValue(parts.map(\.text).joined(separator: ", "))
    }
}

struct PatchList: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTargeted = false
    @State private var confirmRemove: PatchInfo?

    static let groups = [("display", "Display"), ("power", "Power and Storage"), ("audio", "Sound"), ("playback", "Playback"), ("fun", "Fun"), ("test", "Tests")]

    /// A patch in the group "Community": an installed patch (not a newer copy of a built-in patch), or
    /// a patch with no known category.
    static func isCommunity(_ p: PatchInfo) -> Bool {
        (p.source == .user && !p.replacesBuiltIn) || !PatchSpec.categories.contains(p.spec.category ?? "")
    }

    var groups: [(title: String, patches: [PatchInfo])] {
        let community = model.patches.filter(Self.isCommunity)
        var result = Self.groups.map { key, title in
            (title, model.patches.filter { $0.spec.category == key && !Self.isCommunity($0) })
        }
        result.append(("Community", community))
        return result.filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            IPodSyncBanner()
            List(selection: $model.patchSelection) {
                Section("Firmware Options") {
                    OptionRow(title: "iPod Appearance", symbol: "circle.lefthalf.filled", tint: .indigo)
                        .tag("appearance")
                    OptionRow(title: "Software Version", symbol: "number", tint: .teal)
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
                                        Button("Edit Patch…") { model.editPatch(p) }
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
                    .help("Install a patch. You can also drag a .ipodpatch file to the list.").accessibilityLabel("Install Patch")
                Button { confirmRemove = selectedPatch } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .disabled(selectedPatch?.source != .user)
                    .help("Remove the selected patch").accessibilityLabel("Remove Patch")
                Spacer()
                Menu {
                    Button("New Patch…") { model.newPatch() }
                    Button("Install Patch…") { model.choosePatchToInstall() }
                    Button("Edit Patch…") { if let p = selectedPatch { model.editPatch(p) } }.disabled(selectedPatch?.source != .user)
                    Button("Export Patch…") { if let p = selectedPatch { model.exportPatch(p) } }.disabled(selectedPatch == nil)
                    Button("Remove Patch…") { confirmRemove = selectedPatch }.disabled(selectedPatch?.source != .user)
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
}

/// A row for iPod Appearance or Software Version. It has no switch.
struct OptionRow: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            SymbolTile(symbol: symbol, tint: tint, size: 20)
            Text(title).lineLimit(1)
        }
        .padding(.vertical, 1)
    }
}

struct PatchListRow: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("showPatchSummaries") private var showSummary = true
    let patch: PatchInfo

    var body: some View {
        HStack(spacing: 8) {
            SymbolTile(symbol: validSymbol(patch.spec.symbol), tint: patch.tint, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(patch.spec.displayTitle).lineLimit(1)
                    LetterBadge(patch: patch)
                }
                if showSummary, let summary = patch.spec.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let mark = model.ipodMark(patch) { IPodMarkLabel(mark: mark) }
            }
            Spacer(minLength: 4)
            if let problem = model.problem(patch) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(problem).accessibilityLabel(problem)
            }
            PatchSwitch(patch: patch).controlSize(.small)
        }
        .padding(.vertical, 1)
        .help(patch.spec.summary ?? "")
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
            // A Form puts the label of a Toggle far from the switch. Show the text here to keep the two together.
            HStack(spacing: 8) {
                Text(label)
                Toggle(label, isOn: on).toggleStyle(.switch).labelsHidden()
            }
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
        case "playback": .purple
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
        if let name = (patch.spec.needs ?? []).first(where: { n in !patches.contains { $0.spec.name == n } }) {
            return "Needs the patch \"\(name)\", which is not installed."
        }
        return nil
    }
}

// MARK: the detail of a patch

/// The title row at the top of each detail.
struct DetailHeader: View {
    let title: String
    let symbol: String
    let tint: Color
    var patch: PatchInfo?

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(symbol: symbol, tint: tint, size: 44)
            Text(title).font(.title2.weight(.semibold))
            if let patch { LetterBadge(patch: patch) }
        }
        .padding(.vertical, 4)
    }
}

/// The red warning at the top of a test patch (category "test").
struct TestPatchWarning: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Test Patch", systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
            Text("For research only. It can make the iPod unstable. Do not use it on an iPod that you use every day.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PatchDetail: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        Form {
            Section {
                HStack {
                    DetailHeader(title: patch.spec.displayTitle,
                                 symbol: validSymbol(patch.spec.symbol), tint: patch.tint, patch: patch)
                    Spacer()
                    PatchSwitch(patch: patch, label: "Include in Firmware")
                        .fixedSize()
                        .help("iPodFirm includes the turned-on patches when you save, flash, export an .ipsw or run the emulator. Your picture and text changes stay as they are.")
                }
                if patch.spec.isTest { TestPatchWarning() }
                if let caution = patch.spec.caution {
                    Label(caution, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(StatusLabelStyle(tint: .orange)).fixedSize(horizontal: false, vertical: true)
                }
                PatchWarnings(patch: patch)
                if let mark = model.ipodMark(patch), mark != .onIPod {
                    IPodMarkLabel(mark: mark, long: true)
                }
            }
            PatchAbout(spec: patch.spec)
            PatchOptions(patch: patch)
            if patch.spec.eq_editor != nil { CustomEQView(patch: patch) }
            PatchControls(patch: patch)
            Section("Information") {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        InfoItem(title: "Version", value: patch.spec.versionText)
                        InfoItem(title: "Size on iPod", value: patch.spec.sizeText)
                    }
                    GridRow {
                        InfoItem(title: "For", value: patch.spec.targetText)
                        InfoItem(title: "Source", value: sourceText)
                    }
                    if let state = model.ipodState {
                        GridRow { InfoItem(title: "On the iPod", value: ipodText(state)) }
                    }
                }
                PatchChecks(patch: patch)
            }
            PatchNotes(spec: patch.spec)
            if patch.source == .user { PatchCodeSections(patch: patch) }
        }
        .formStyle(.grouped)
        .task(id: "\(patch.spec.name) \(model.currentIPod?.disk ?? "")") { model.loadPatchToggles(patch) }
    }

    var sourceText: String {
        if patch.replacesBuiltIn { return "Replaces the built-in version \(patch.builtInVersion ?? "–")" }
        return patch.source == .user ? "Installed by you" : "Included with iPodFirm"
    }

    func ipodText(_ state: IPodPatchState) -> String {
        switch state.detections[patch.spec.name] ?? .absent {
        case .installed(let v): return v.map { "Version \($0)" } ?? "Yes (the version is not known)"
        case .absent: return "No"
        case .unknown: return "Not known"
        }
    }
}

/// One fact in the Information section of a patch.
struct InfoItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The mark of a patch row: the switch compared with the patches on the iPod.
struct IPodMarkLabel: View {
    let mark: IPodMark
    var long = false

    var body: some View {
        Label(long ? mark.help : mark.title, systemImage: symbol)
            .font(long ? .callout : .caption)
            .labelStyle(StatusLabelStyle(tint: color))
            .fixedSize(horizontal: false, vertical: true)
            .help(mark.help)
    }

    var symbol: String {
        switch mark {
        case .onIPod: "checkmark.circle.fill"
        case .notFlashed: "arrow.up.circle.fill"
        case .willBeRemoved: "minus.circle.fill"
        case .update: "arrow.triangle.2.circlepath.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch mark {
        case .onIPod: .green
        case .notFlashed, .willBeRemoved, .update: .orange
        case .unknown: .secondary
        }
    }
}

/// The top of the list of patches: do the switches agree with the iPod?
struct IPodSyncBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.currentIPod != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let state = model.ipodState {
                    let diff = model.ipodDifferences
                    if diff.isEmpty && !model.ipodAppearanceDiffers {
                        Label("The switches agree with the iPod.", systemImage: "checkmark.circle.fill")
                            .labelStyle(StatusLabelStyle(tint: .green))
                    } else {
                        Label(differenceText(diff), systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(StatusLabelStyle(tint: .orange))
                        HStack {
                            Button("Match iPod") { model.matchIPod() }
                                .help("Set the switches to the patches on the iPod.")
                            Button("Flash to iPod…") { model.section = .ipod; Task { await model.flashEdited() } }
                                .disabled(!model.canFlash)
                                .help(model.flashBlockReason ?? "Write the firmware with the current switches to the iPod.")
                        }
                        .controlSize(.small)
                        FlashHint()
                    }
                    let unknown = state.unknownNames(known: Set(model.patches.map(\.spec.name)))
                    if !unknown.isEmpty {
                        Text("The iPod also has patches that iPodFirm does not have: \(unknown.joined(separator: ", ")).")
                            .foregroundStyle(.secondary)
                    }
                    if state.list == nil {
                        Text("The firmware on the iPod has no iPodFirm list. The versions are not known.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if let status = model.ipodReadStatus { Text(status).foregroundStyle(.secondary) }
                    Button("Read iPod") { Task { await model.readIPodPatches(automatic: false) } }
                        .controlSize(.small)
                        .disabled(model.busy != nil)
                        .help("Read the firmware on the iPod to see its patches. iPodFirm writes nothing to the iPod.")
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            Divider()
        }
    }

    func differenceText(_ diff: [(PatchInfo, IPodMark)]) -> String {
        let add = diff.filter { $0.1 == .notFlashed }.count
        let remove = diff.filter { $0.1 == .willBeRemoved }.count
        let update = diff.count - add - remove
        var parts = [String]()
        if add > 0 { parts.append("\(add) to add") }
        if remove > 0 { parts.append("\(remove) to remove") }
        if update > 0 { parts.append("\(update) to update") }
        if model.ipodAppearanceDiffers { parts.append("a different appearance") }
        return "Different from the iPod: " + parts.joined(separator: ", ") + "."
    }
}

/// A section for each option of a patch (`options` in patch.json). The build uses the selected choice.
struct PatchOptions: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        ForEach(patch.spec.options ?? [], id: \.id) { o in
            let value = model.optionValue(patch, o)
            Section {
                Picker(o.title, selection: Binding(get: { value }, set: { model.setOptionValue(patch, o, $0) })) {
                    ForEach(o.choices, id: \.value) { c in Text(c.title).tag(c.value) }
                }
                .pickerStyle(.menu)
                .help(o.choices.first { $0.value == value }?.description ?? "iPodFirm uses this choice when you save, flash, export an .ipsw or run the emulator. To change the iPod, flash it again.")
                if let caution = o.choices.first(where: { $0.value == value })?.caution {
                    Label(caution, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(StatusLabelStyle(tint: .orange)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The text of a patch: What It Does and You Need.
struct PatchAbout: View {
    let spec: PatchSpec

    var body: some View {
        Section("What It Does") {
            if let d = spec.description { Text(d).fixedSize(horizontal: false, vertical: true) }
            ForEach(spec.details ?? [], id: \.self) { BulletRow(text: $0) }
            if spec.description == nil && spec.details == nil { Text(spec.name).foregroundStyle(.secondary) }
        }
        let items = (spec.requires ?? []) + (spec.needs ?? []).map { "The patch \"\($0)\" (it turns on with this patch)" }
        if !items.isEmpty {
            Section("You Need") {
                ForEach(items, id: \.self) { BulletRow(text: $0, symbol: "checkmark.circle", tint: .green) }
            }
        }
    }
}

/// The notes of a patch, folded.
struct PatchNotes: View {
    let spec: PatchSpec

    var body: some View {
        if let items = spec.notes, !items.isEmpty {
            Section {
                TitleDisclosure(title: "Good to Know") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { BulletRow(text: $0, symbol: "info.circle", tint: .secondary) }
                    }
                    .padding(.top, 4)
                }
                .id(spec.name)
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

/// A status: the symbol has the color, and the text stays primary so that it is easy to read.
struct StatusLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        Label { configuration.title } icon: { configuration.icon.foregroundStyle(tint) }
    }
}

/// The problems of a patch. They show at the top of the detail.
struct PatchWarnings: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        if model.editor != nil && !model.isCompatible(patch) {
            Label("Does not agree with the open firmware. The patch is only for the original Apple firmware of its target. iPodFirm does not apply it.",
                  systemImage: "xmark.octagon.fill")
                .labelStyle(StatusLabelStyle(tint: .orange)).fixedSize(horizontal: false, vertical: true)
        }
        if let warning = patch.spec.hdd_warning, let gb = model.currentIPod?.likelyOriginalHDD {
            Label("The connected iPod has approximately \(gb) GB. This is the size of an original hard drive. \(warning)",
                  systemImage: "exclamationmark.triangle.fill")
                .labelStyle(StatusLabelStyle(tint: .orange)).fixedSize(horizontal: false, vertical: true)
        }
        ForEach(model.conflicts(patch), id: \.0.id) { other, place in
            Label("Changes the same place as \"\(other.spec.displayTitle)\" (\(place)). You cannot turn on the two patches together.",
                  systemImage: "exclamationmark.triangle.fill")
                .labelStyle(StatusLabelStyle(tint: .orange)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The firmware and storage checks that pass or that wait for an item.
struct PatchChecks: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        if model.editor == nil {
            Label("Open a firmware to examine this patch.", systemImage: "info.circle").foregroundStyle(.secondary)
        } else if model.isCompatible(patch) {
            Label("Agrees with the open firmware.", systemImage: "checkmark.circle.fill")
                .labelStyle(StatusLabelStyle(tint: .green))
        }
        if patch.spec.hdd_warning != nil, model.currentIPod?.likelyOriginalHDD == nil {
            if let ipod = model.currentIPod {
                Label("The connected iPod has \(ByteCountFormatter.string(fromByteCount: ipod.size, countStyle: .decimal)). No original iPod drive has this size, thus the storage is flash.",
                      systemImage: "checkmark.circle.fill")
                    .labelStyle(StatusLabelStyle(tint: .green)).fixedSize(horizontal: false, vertical: true)
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
                DetailHeader(title: "iPod Appearance",
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
                .help("Light uses the Apple colours. Dark uses an imported dark theme. Switch on iPod adds a \"Dark Mode\" item to Settings on the iPod. The firmware then starts light.")
            } header: {
                Text("Appearance")
            }
            Section("Layout") {
                Picker("Layout", selection: $model.layout) {
                    ForEach(AppModel.Layout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                .disabled(model.appearance == .onIPod || AppModel.splitTheme == nil)
                .help("Split shows the cover and the current song beside the main menu. All other screens stay stock.")
                if model.appearance == .onIPod {
                    Label("Split does not operate with Switch on iPod yet.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                } else if let split = AppModel.splitTheme {
                    if model.editor != nil, !model.isCompatible(split) {
                        Label("Split does not agree with the open firmware. It is only for the original Apple firmware 1.3.",
                              systemImage: "xmark.octagon.fill").labelStyle(StatusLabelStyle(tint: .orange))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LabeledContent("Size on iPod (Split)", value: PatchSpec.byteText(split.addedSize))
                }
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
                                .labelStyle(StatusLabelStyle(tint: .green))
                        } else {
                            Label("Does not agree with the open firmware. The theme is only for the original Apple firmware 1.3.",
                                  systemImage: "xmark.octagon.fill").labelStyle(StatusLabelStyle(tint: .orange))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    LabeledContent("Size on iPod (Dark)", value: PatchSpec.byteText(current.theme.addedSize))
                        .help("The theme also changes \(PatchSpec.byteText(current.theme.changedSize)) of the Apple pictures and layouts. These changes use no new space.")
                    LabeledContent("Size on iPod (Switch on iPod)",
                                   value: model.switchOnIPodSize.map(PatchSpec.byteText) ?? "Open the firmware 1.3 to calculate")
                    HStack {
                        Button("Show Import Report") { model.themeReport = current.theme }
                        Spacer()
                        Button("Delete Theme…", role: .destructive) { confirmDelete = current }
                    }
                }
            }
            Section {
                Button("Import iPodWizard Theme…") { model.importTheme() }
                    .help("Select the theme file from iPodWizard. Then select the Apple firmware that the theme came from, for example iPod_25.1.2.1.ipsw.")
            } header: {
                Text("Import")
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
                DetailHeader(title: "Software Version",
                             symbol: "number", tint: .teal)
            }
            Section {
                Toggle("Show a different version on the About screen", isOn: $model.customVersionOn)
                    .help("This changes only the text on the iPod. iTunes and Finder continue to see version 1.3.")
                if model.customVersionOn {
                    TextField("Version", text: $model.customVersion, prompt: Text("1.3.1"))
                    if FirmwareVersion(model.customVersion) == nil {
                        Label("This version is not valid. Use the format 1.3 or 1.3.1. The first number is 0–255. The other numbers are 0–15. The firmware keeps version 1.3.",
                              systemImage: "xmark.octagon.fill").labelStyle(StatusLabelStyle(tint: .orange))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle("Add a letter for each switched-on patch", isOn: $model.versionLettersOn)
                LabeledContent("About screen", value: model.activeVersion?.description ?? "1.3")
                if let v = model.activeVersion, v.description.count > FirmwareVersion.maxTextLength {
                    Label("This version has more than \(FirmwareVersion.maxTextLength) characters. The About screen cannot show it. Switch off some patches or the letters.",
                          systemImage: "xmark.octagon.fill").labelStyle(StatusLabelStyle(tint: .orange))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Version")
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

/// The status line when the iPod is ready but no firmware is open. It gives the commands to open a
/// firmware. The pane does not change, so that the user can continue the work. The other reasons
/// are in the tooltip of the flash buttons, because the iPod pane already shows them.
struct FlashHint: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.editor == nil, model.currentIPod != nil, !model.currentIPodIsUnsupported, model.busy == nil,
           let reason = model.flashBlockReason {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(StatusLabelStyle(tint: .orange))
                .fixedSize(horizontal: false, vertical: true)
                .help("Your patch switches do not change.")
            HStack {
                Button("Download Apple Firmware 1.3") { Task { await model.downloadAppleFirmware(stay: true) } }
                Button("Open Firmware…") { model.openPanel(stay: true) }
            }
            .controlSize(.small)
        }
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
