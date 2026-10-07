import AppKit
import IPodFWKit
import SwiftUI
import UniformTypeIdentifiers

/// Code patches: changes to the behaviour of the iPod software. Each one can be switched on or off.
struct PatchesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            AppearanceSection()
            VersionSection()
            Section {
                Text("A patch adds new code to the iPod software. The switched-on patches are included when you save, flash, export an .ipsw or run the emulator. Your picture and text changes stay as they are.")
                    .fixedSize(horizontal: false, vertical: true)
                if model.editor == nil {
                    Label("Open a firmware to see which patches agree with it.", systemImage: "info.circle").foregroundStyle(.secondary)
                }
            }
            ForEach(model.patches) { patch in
                Section {
                    PatchRow(patch: patch)
                    if patch.spec.name == "album-art" { AlbumArtControls() }
                    if patch.spec.name == "usb-host-probe" { USBProbeControls() }
                } header: {
                    HStack(spacing: 6) {
                        Text(patch.spec.name)
                        if let letter = patch.spec.version_letter {
                            Text(letter).font(.caption.monospaced().bold())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                .help("The version letter of this patch. The About screen shows it after the version when \"Add a letter for each switched-on patch\" is on.")
                        }
                    }
                }
            }
            if model.patches.isEmpty {
                Section { Text("This copy of iPodFirm has no patches.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}

struct PatchRow: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        let on = Binding(
            get: { model.enabledPatches.contains(patch.spec.name) },
            set: { v in
                if v && !confirmOnHDD() { return }
                if v { model.enabledPatches.insert(patch.spec.name) } else { model.enabledPatches.remove(patch.spec.name) }
            })
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: on) {
                Text(patch.spec.description ?? patch.spec.name).fixedSize(horizontal: false, vertical: true)
            }
            if let warning = patch.spec.hdd_warning {
                if let gb = model.currentIPod?.likelyOriginalHDD {
                    Label("The connected iPod has approximately \(gb) GB. This is the size of an original hard drive. \(warning)",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                } else if let ipod = model.currentIPod {
                    Label("The connected iPod has \(ByteCountFormatter.string(fromByteCount: ipod.size, countStyle: .decimal)). No original iPod drive has this size, thus the storage is flash.",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green).fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("Connect the iPod to check its storage.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.editor != nil {
                if model.isCompatible(patch) {
                    Label("Agrees with the open firmware (iPod Video 1.3).", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label("Does not agree with the open firmware. It is only for the original Apple firmware 1.3; it is not applied.",
                          systemImage: "xmark.octagon.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

extension PatchRow {
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

/// The trigger of the usb-host-probe patch. Refer to USB-AUDIO-OUT.md (Stage 0).
struct USBProbeControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("""
                Do these steps after you flash a firmware with this patch:
                1. Click Start the Probe at the Next Restart, then click Eject iPod.
                2. Disconnect the iPod. Restart it (hold Menu and Select until the Apple logo shows).
                3. Connect a USB flash drive or a card reader through a USB-C OTG adapter with a power input. Connect a charger to the power input.
                4. Press a button on the iPod. First the iPod plays each sign one time: a long low tone, then high, low, high. Then three short beeps and a silence. Then the real result: a long low tone means that the USB host mode operates (a second one: the hub in the adapter). High, low, high means that the iPod found the flash drive or card reader. The iPod does not react for approximately 7 seconds during the tones.
                5. Wait. Approximately 10 seconds after the result tones, the iPod writes the USB log and gives two short low beeps.
                6. Disconnect the adapter and restart the iPod. The next start is normal.
                7. Connect the iPod to the Mac and click Show USB Log.
                """)
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Start the Probe at the Next Restart") { model.armUSBProbe() }
                    .disabled(model.currentIPod == nil)
                Button("Show USB Log") { model.readUSBProbeLog() }
                    .disabled(model.currentIPod == nil)
                Button("Eject iPod") { Task { await model.ejectIPod() } }
                    .disabled(model.currentIPod == nil)
                if model.currentIPod == nil { Text("Connect the iPod.").font(.caption).foregroundStyle(.secondary) }
            }
            if let s = model.usbProbeStatus { Label(s, systemImage: "checkmark.circle").font(.caption) }
            if let log = model.usbProbeLog {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("USB Log").font(.headline)
                        Spacer()
                        Button("Copy Log") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(USBProbeLog.text(log), forType: .string)
                        }
                        .disabled(log.isEmpty)
                    }
                    .padding(.top, 6)
                    if log.isEmpty {
                        Text("The log is empty. The probe did not start the host stack, or no driver was called. Press Menu after the tones, so that the iPod writes the log.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(log.enumerated()), id: \.offset) { i, e in
                        Text("\(i + 1). \(e.text)").font(.caption.monospaced()).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct AlbumArtControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The iPod also needs a thumbnail file made from its own music. Write it after you flash this patch, and again after each sync that adds albums or playlists. You do not have to restart the iPod: the new thumbnails show after you scroll through a list.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Write Thumbnails to iPod") { Task { await model.writeThumbnails() } }
                    .disabled(model.currentIPod == nil)
                Button("Eject iPod") { Task { await model.ejectIPod() } }
                    .disabled(model.currentIPod == nil)
                if model.currentIPod == nil { Text("Connect the iPod.").font(.caption).foregroundStyle(.secondary) }
            }
            if let s = model.thumbnailStatus { Label(s, systemImage: "checkmark.circle").font(.caption) }
            if !model.playlistArt.isEmpty { PlaylistArtList() }
        }
        .task(id: model.currentIPod?.disk) { await model.loadPlaylists() }
    }
}

/// The thumbnail of each playlist: a custom image, or a collage of the covers of its first four albums.
struct PlaylistArtList: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Playlist Artwork").font(.headline).padding(.top, 8)
            Text("A playlist without a custom image shows the covers of its first four albums. To set a custom image, click Choose Image or drag an image onto the playlist. iPodFirm keeps the custom images on the iPod.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.playlistArtChanged {
                Label("Click Write Thumbnails to iPod to send the changes to the iPod.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(model.playlistArt) { p in PlaylistArtRow(playlist: p) }
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

/// Light, Dark or Switch on iPod, and the imported dark themes.
struct AppearanceSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            Text("Light uses the Apple colours. Dark applies an imported dark theme when you save, flash, export an .ipsw or run the emulator. Switch on iPod adds a \"Dark Mode\" item to Settings on the iPod.")
                .fixedSize(horizontal: false, vertical: true)
            AppearanceControl(selection: $model.appearance) { a in
                switch a {
                case .light: true
                case .dark: !model.themes.isEmpty
                case .onIPod: !model.themes.isEmpty && AppModel.darkModePatch != nil
                }
            }
            .frame(maxWidth: 380)
            if model.appearance == .onIPod {
                Text("The firmware starts light. In Settings on the iPod, select \"Dark Mode\" to change between light and dark. The iPod saves its settings and restarts (a few seconds). The choice is in the file iPod_Control/iTunes/iPodFirmDarkMode.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if model.themes.isEmpty {
                Label("Import a dark theme first.", systemImage: "info.circle").foregroundStyle(.secondary)
            } else if let current = model.selectedTheme {
                Picker("Dark theme", selection: Binding(get: { current.name }, set: { model.selectedThemeName = $0 })) {
                    ForEach(model.themes) { Text($0.name).tag($0.name) }
                }
                if model.editor != nil {
                    if model.isCompatible(current.theme) {
                        Label("Agrees with the open firmware (iPod Video 1.3).", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Label("Does not agree with the open firmware. The theme is only for the original Apple firmware 1.3.",
                              systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                if model.appearance != .light {
                    Text("The theme makes the iPod software larger. iPodFirm moves the rsrc image (fonts and video firmware) to free space in the firmware partition. It does not move or change aupd or hibe.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Show Import Report") { model.themeReport = current.theme }
                    Button("Delete Theme", role: .destructive) { model.deleteTheme(current) }
                }
            }
            Button("Import iPodWizard Theme…") { model.importTheme() }
            Text("Select the theme file (a firmware file from iPodWizard), then the Apple firmware that the theme came from, for example iPod_25.1.2.1.ipsw. iPodFirm moves the pictures, colours and layouts of the theme to firmware 1.3.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } header: { Text("iPod Appearance") }
    }
}

/// A different version on the About screen of the iPod, and letters for the switched-on patches. Off by default.
struct VersionSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            Toggle("Show a different version on the About screen", isOn: $model.customVersionOn)
            if model.customVersionOn {
                TextField("Version", text: $model.customVersion, prompt: Text("1.3.1"))
                    .frame(maxWidth: 260)
                if FirmwareVersion(model.customVersion) == nil {
                    Label("This version is not valid. Use the format 1.3 or 1.3.1. The first number is 0–255. The other numbers are 0–15. The firmware keeps version 1.3.",
                          systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Add a letter for each switched-on patch", isOn: $model.versionLettersOn)
            if let v = model.activeVersion {
                Text("Settings > About on the iPod shows \"\(v.description)\".")
                    .font(.caption).foregroundStyle(.secondary)
                if v.description.count > FirmwareVersion.maxTextLength {
                    Label("This version has more than \(FirmwareVersion.maxTextLength) characters. The About screen cannot show it. Switch off some patches or the letters.",
                          systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("This changes only the text on the iPod. iTunes and Finder continue to see version 1.3. The letter of each patch shows next to the name of the patch.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } header: { Text("Software Version") }
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
