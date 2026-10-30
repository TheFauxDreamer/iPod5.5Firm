import AppKit
import IPodFWKit
import SwiftUI
import UniformTypeIdentifiers

/// A disclosure group that opens and closes with a click on the title, not only on the chevron.
struct TitleDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded, content: content) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { expanded.toggle() } }
        }
    }
}

/// The controls of a patch from the "ui" object of its patch.json: actions, switches, steps, a readme
/// and built-in tools. A new patch gets these controls with no change to the Swift code.
struct PatchControls: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        if let ui = patch.spec.ui {
            let actions = ui.actions ?? [], toggles = ui.toggles ?? []
            if !actions.isEmpty || !toggles.isEmpty {
                Section("On the iPod") {
                    if !actions.isEmpty {
                        IPodActionsRow {
                            ForEach(actions, id: \.title) { a in
                                Button(a.title) { model.runPatchAction(patch, a) }
                            }
                        }
                    }
                    ForEach(toggles, id: \.path) { t in
                        Toggle(t.title, isOn: Binding(get: { model.patchToggleStates[t.path] ?? false },
                                                      set: { model.setPatchToggle(t, on: $0) }))
                            .toggleStyle(.switch)
                            .disabled(model.currentIPod == nil)
                    }
                    if actions.isEmpty && model.currentIPod == nil {
                        Text("Connect the iPod.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let s = model.patchActionStatus[patch.spec.name] { Label(s, systemImage: "checkmark.circle").font(.callout) }
                }
            }
            if let steps = ui.steps, !steps.isEmpty {
                Section {
                    TitleDisclosure(title: ui.steps_title ?? "Procedure") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in Step(n: i + 1, text: text) }
                        }
                        .font(.callout)
                        .padding(.top, 4)
                    }
                    .id(patch.spec.name)   // each patch starts closed
                }
            }
            if let file = ui.readme, !file.contains("/"),
               let text = try? String(contentsOf: patch.folder.appendingPathComponent(file), encoding: .utf8) {
                Section("Read Me") {
                    Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                         ?? AttributedString(text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(ui.tools ?? [], id: \.self) { PatchTool(id: $0) }
        }
    }
}

/// The built-in Swift tools that a patch can name in "ui.tools". Keep the ids in PatchSpec.knownTools.
struct PatchTool: View {
    let id: String

    var body: some View {
        switch id {
        case "album-thumbnails": AlbumArtSections()
        case "usb-log": USBLogSection()
        case "playlist-folders": PlaylistFoldersSection()
        case "playback-log": PlaybackLogSection()
        default: EmptyView()
        }
    }
}

// MARK: playlist-folders

/// The folder editor of the playlist-folders patch. It writes iPod_Control/iTunes/iPodFirmPlaylistFolders.
struct PlaylistFoldersSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            if model.currentIPod == nil {
                Text("Connect the iPod.").foregroundStyle(.secondary)
            } else if model.folderPlaylists.isEmpty {
                Text("The iPod has no playlists.").foregroundStyle(.secondary)
            } else {
                Picker("Folder position", selection: $model.playlistFolders.alphabetical) {
                    Text("Folders First").tag(false)
                    Text("Alphabetical").tag(true)
                }
                .pickerStyle(.segmented)
                ForEach($model.playlistFolders.folders) { $folder in
                    PlaylistFolderRow(folder: $folder)
                }
                HStack {
                    Button("Add Folder") {
                        model.playlistFolders.folders.append(.init(name: newName()))
                    }
                    .disabled(model.playlistFolders.folders.count >= PlaylistFolders.maxFolders)
                    Spacer()
                    Button("Write Folders to iPod") { Task { await model.writePlaylistFolders() } }
                        .disabled(!model.playlistFolderProblems.isEmpty || model.playlistFolders == model.savedPlaylistFolders)
                }
                ForEach(model.playlistFolderProblems, id: \.self) { p in
                    Label(p, systemImage: "exclamationmark.triangle").labelStyle(StatusLabelStyle(tint: .orange))
                }
                if model.playlistFolders != model.savedPlaylistFolders {
                    Label("Click Write Folders to iPod to send the changes to the iPod.", systemImage: "exclamationmark.circle")
                        .labelStyle(StatusLabelStyle(tint: .orange))
                }
                if let s = model.playlistFoldersStatus { Label(s, systemImage: "checkmark.circle").font(.callout) }
            }
        } header: {
            Text("Playlist Folders")
        } footer: {
            FormFooter("Put each playlist into one folder, or into no folder. A folder without playlists does not show on the iPod.")
        }
        .task(id: model.currentIPod?.disk) { await model.loadPlaylistFolders() }
    }

    /// "New Folder", or "New Folder 2" and so on if that name is used.
    func newName() -> String {
        let used = Set(model.playlistFolders.folders.map(\.name))
        var n = 1
        while used.contains(n == 1 ? "New Folder" : "New Folder \(n)") { n += 1 }
        return n == 1 ? "New Folder" : "New Folder \(n)"
    }
}

struct PlaylistFolderRow: View {
    @EnvironmentObject var model: AppModel
    @Binding var folder: PlaylistFolders.Folder
    @State private var expanded = false

    // Saved for later: the folder colour. The colour squares did not show on the real iPod.
    // Refer to re/playlist-folders.md, "Folder colours".
    var colour: Binding<Color> {
        Binding(get: {
            let c = PlaylistFolders.components(folder.colour)
            return Color(.sRGB, red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255)
        }, set: { new in
            guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
            folder.colour = PlaylistFolders.rgb565(red: Int((c.redComponent * 255).rounded()),
                                                   green: Int((c.greenComponent * 255).rounded()),
                                                   blue: Int((c.blueComponent * 255).rounded()))
        })
    }

    var index: Int? { model.playlistFolders.folders.firstIndex { $0.id == folder.id } }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(model.folderPlaylists) { p in
                let home = model.playlistFolders.folderIndex(of: p.persistentID)
                Toggle(isOn: Binding(get: { home != nil && home == index },
                                     set: { on in model.playlistFolders.move(p.persistentID, to: on ? index : nil) })) {
                    HStack {
                        Text(p.name.isEmpty ? "(No name)" : p.name)
                        if let home, home != index {
                            Text("in “\(model.playlistFolders.folders[home].name)”").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } label: {
            HStack {
                // ColorPicker("Colour", selection: colour, supportsOpacity: false).labelsHidden()
                TextField("Folder name", text: $folder.name).textFieldStyle(.roundedBorder)
                Text(counted(folder.members.count, "playlist")).font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    if let i = index { model.playlistFolders.folders.remove(at: i) }
                } label: { Image(systemName: "trash") }
                .help("Delete the folder. Its playlists go back to the Playlists list.")
                .accessibilityLabel("Delete folder")
            }
        }
    }
}

// MARK: playback-log

/// The log that the playback-log patch writes on the iPod: the shuffle, the playback and the memory.
struct PlaybackLogSection: View {
    var body: some View {
        Section {
            PlaybackLogContent()
        } header: {
            Text("Playback Log")
        } footer: {
            FormFooter(PlaybackLogContent.footer)
        }
    }
}

/// The buttons and the text of the playback log, in the Patches pane and in `IPodLogSheet`.
struct PlaybackLogContent: View {
    static let footer = "Report on GitHub saves the log as a text file and opens a new issue in the browser. Drag the file into the issue. You need a GitHub account. The file has the names of the songs in the log, and an issue is public."

    @EnvironmentObject var model: AppModel
    var showsRead = true

    var body: some View {
        Group {
            HStack {
                if showsRead {
                    Button("Show Playback Log") { model.readPlaybackLog() }.disabled(model.currentIPod == nil)
                }
                Spacer()
                if let log = model.playbackLog, !log.isEmpty {
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log, forType: .string)
                    }
                    Button("Save the Log to Share…") { model.savePlaybackLog() }
                    Button("Report on GitHub…") { model.reportPlaybackLog() }
                }
            }
            if let log = model.playbackLog {
                if log.isEmpty {
                    Text("The log is empty. Play music. Then press a button, so that the iPod writes the log. Wait 15 seconds before you connect the iPod.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        Text(log)
                            .font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 80, maxHeight: 400)
                }
            }
        }
    }
}

// MARK: usb-log

/// The log that the usb-host-probe patch writes on the iPod. Refer to USB-AUDIO-OUT.md (Stage 0).
struct USBLogSection: View {
    var body: some View {
        Section {
            USBLogContent()
        } header: {
            Text("USB Log")
        }
    }
}

/// The buttons and the text of the USB log, in the Patches pane and in `IPodLogSheet`.
struct USBLogContent: View {
    @EnvironmentObject var model: AppModel
    var showsRead = true

    var body: some View {
        Group {
            HStack {
                if showsRead {
                    Button("Show USB Log") { model.readUSBProbeLog() }.disabled(model.currentIPod == nil)
                }
                Spacer()
                if let log = model.usbProbeLog {
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(USBProbeLog.text(log), forType: .string)
                    }
                    .disabled(log.isEmpty)
                }
            }
            if let log = model.usbProbeLog {
                if log.isEmpty {
                    Text("The log is empty. The probe did not start the host stack, or no driver was called. Press Menu after the tones, so that the iPod writes the log.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        Text(log.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n"))
                            .font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 80, maxHeight: 320)
                }
            }
        }
    }
}

/// A log on the iPod. The iPod pane opens this sheet.
struct IPodLogSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let log: IPodLogFile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(log.title).font(.title3.bold())
            Text(log.details).font(.caption).foregroundStyle(.secondary)
            switch log.kind {
            case .playback:
                PlaybackLogContent(showsRead: false)
                FormFooter(PlaybackLogContent.footer)
            case .usb:
                USBLogContent(showsRead: false)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 660, height: 600)
        .onAppear {
            switch log.kind {
            case .playback: model.readPlaybackLog()
            case .usb: model.readUSBProbeLog()
            }
        }
    }
}

// MARK: album-thumbnails

/// The thumbnail file and the playlist artwork of the album-art patch.
struct AlbumArtSections: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            Text("Albums show the artwork that iTunes or Finder put on the iPod. They need no step here. After a sync, the iPod makes the album pictures one time and keeps them in a file. The iPod also makes the collage of each playlist. The thumbnail file of iPodFirm is necessary only for custom playlist images. Write it after you flash this patch, and again after each change. The file also has the album covers and the collages. On the iPod, the pictures of the file come first. Thus write the file again after you change a cover.")
                .fixedSize(horizontal: false, vertical: true)
            IPodActionsRow {
                Button("Write Thumbnails to iPod") { Task { await model.writeThumbnails() } }
            }
            if let s = model.thumbnailStatus { Label(s, systemImage: "checkmark.circle").font(.callout) }
        } header: {
            Text("Thumbnails")
        } footer: {
            FormFooter("You do not have to restart the iPod. The new thumbnails show after you scroll through a list.")
        }
        .task(id: model.currentIPod?.disk) { await model.loadPlaylists() }
        if !model.playlistArt.isEmpty {
            Section {
                if model.playlistArtChanged {
                    Label("Click Write Thumbnails to iPod to send the changes to the iPod.", systemImage: "exclamationmark.circle")
                        .labelStyle(StatusLabelStyle(tint: .orange))
                }
                ForEach(model.playlistArt) { p in PlaylistArtRow(playlist: p) }
            } header: {
                Text("Playlist Artwork")
            } footer: {
                FormFooter("A playlist without a custom image shows the covers of its first four albums. To set a custom image, click Choose Image or drag an image onto the playlist. iPodFirm keeps the custom images on the iPod.")
            }
        }
    }
}

struct PlaylistArtRow: View {
    @EnvironmentObject var model: AppModel
    let playlist: MusicImport.PlaylistArt
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let data = playlist.image, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(1, contentMode: .fill)
                } else {
                    Image(systemName: "music.note.list").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name.isEmpty ? "(No name)" : playlist.name).lineLimit(1)
                Text(playlist.isCustom ? "Custom image" : playlist.image == nil ? "No album covers" : "Automatic")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose Image…") { model.choosePlaylistArt(playlist.name) }
            Button("Use Automatic") { Task { await model.resetPlaylistArt(playlist.name) } }
                .disabled(!playlist.isCustom)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: targeted ? 2 : 0))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await model.setPlaylistArt(playlist.name, from: url) }
            }
            return true
        }
    }
}

// MARK: install

/// The patch that the owner opened: what it is, the problems and the notes. Install or Cancel.
struct InstallPatchSheet: View {
    @EnvironmentObject var model: AppModel
    let candidate: PatchCandidate
    @State private var confirmBuiltIn = false

    /// For example "1.2", or "1.1 → 1.2" for an update.
    func versionText(_ spec: PatchSpec) -> String {
        candidate.change == .new ? spec.versionText : "\(candidate.installedVersion ?? "–") → \(spec.versionText)"
    }

    var buttonTitle: String {
        if candidate.replacesBuiltIn { return "Replace Built-In Patch" }
        switch candidate.change {
        case .new: return "Install"
        case .update: return "Update"
        case .same: return "Reinstall"
        case .downgrade: return "Downgrade"
        }
    }

    /// A caution for a downgrade or for a patch that replaces a built-in patch.
    var caution: String? {
        if candidate.replacesBuiltIn {
            return "This patch replaces a patch that is built into iPodFirm. Make sure that you trust the person that made it."
        }
        if candidate.change == .downgrade {
            return "This file has an older version than the installed patch. The older version can have problems that the newer version corrects."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let spec = candidate.spec {
                HStack(spacing: 14) {
                    SymbolTile(symbol: validSymbol(spec.symbol), tint: .accentColor, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(spec.displayTitle).font(.title2.weight(.semibold))
                        if let summary = spec.summary { Text(summary).foregroundStyle(.secondary) }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let caution = spec.caution {
                            Label(caution, systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(StatusLabelStyle(tint: .orange)).fixedSize(horizontal: false, vertical: true)
                        }
                        if let d = spec.description { Text(d).fixedSize(horizontal: false, vertical: true) }
                        ForEach(spec.details ?? [], id: \.self) { BulletRow(text: $0) }
                        ForEach(spec.requires ?? [], id: \.self) { BulletRow(text: "You need: \($0)", symbol: "checkmark.circle", tint: .green) }
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow { Text("Name").foregroundStyle(.secondary); Text(spec.name).monospaced() }
                            GridRow { Text("Version").foregroundStyle(.secondary); Text(versionText(spec)) }
                            GridRow { Text("For").foregroundStyle(.secondary); Text(spec.targetText) }
                            GridRow { Text("Letter").foregroundStyle(.secondary); Text(candidate.assignedLetter ?? spec.version_letter ?? "-") }
                            GridRow { Text("Code").foregroundStyle(.secondary); Text(candidate.codeSize.map { "\($0) bytes" } ?? "No code (data only)") }
                            GridRow { Text("Size on iPod").foregroundStyle(.secondary); Text((candidate.assignedSize ?? spec.size).map(PatchSpec.byteText) ?? "–") }
                            GridRow { Text("Changes").foregroundStyle(.secondary); Text("\(spec.hooks?.count ?? 0) hooks, \(spec.bytes?.count ?? 0) byte runs") }
                        }
                        .font(.callout)
                        ForEach(candidate.errors, id: \.self) { e in
                            Label(e, systemImage: "xmark.octagon.fill").labelStyle(StatusLabelStyle(tint: .red)).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(candidate.notes, id: \.self) { n in
                            Label(n, systemImage: "info.circle").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            } else {
                Label("iPodFirm cannot install this patch", systemImage: "xmark.octagon.fill").font(.title3.bold())
                ForEach(candidate.errors, id: \.self) { e in Text(e).fixedSize(horizontal: false, vertical: true) }
            }
            if candidate.canInstall, let caution {
                Label(caution, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(StatusLabelStyle(tint: .orange)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if candidate.canInstall {
                Label("A patch puts new code on your iPod. Install only patches from people that you trust. iPodFirm makes a backup before each flash.",
                      systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(StatusLabelStyle(tint: .orange)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelInstall(candidate) }.keyboardShortcut(.cancelAction)
                if candidate.canInstall {
                    Button(buttonTitle) {
                        if candidate.replacesBuiltIn { confirmBuiltIn = true } else { model.confirmInstall(candidate) }
                    }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(22)
        .frame(width: 520)
        .confirmationDialog("Replace the built-in patch \"\(candidate.spec?.displayTitle ?? "")\"?", isPresented: $confirmBuiltIn) {
            Button("Replace Built-In Patch", role: .destructive) { model.confirmInstall(candidate) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("iPodFirm uses this patch in place of the built-in patch. To use the built-in patch again, remove this patch.")
        }
    }
}

/// The SF Symbol of a patch, or the puzzle piece if macOS does not have the symbol.
func validSymbol(_ name: String?) -> String {
    guard let name, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return "puzzlepiece.extension" }
    return name
}

/// true: the URL is a .ipodpatch file or a folder with patch.json.
func isPatchURL(_ url: URL) -> Bool {
    url.pathExtension == PatchLibrary.fileExtension
        || FileManager.default.fileExists(atPath: url.appendingPathComponent("patch.json").path)
}
