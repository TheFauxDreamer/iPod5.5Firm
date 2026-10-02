import AppKit
import IPodFWKit
import SwiftUI

/// Code patches: changes to the behaviour of the iPod software. Each one can be switched on or off.
struct PatchesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            AppearanceSection()
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
                } header: { Text(patch.spec.name) }
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
                if v { model.enabledPatches.insert(patch.spec.name) } else { model.enabledPatches.remove(patch.spec.name) }
            })
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: on) {
                Text(patch.spec.description ?? patch.spec.name).fixedSize(horizontal: false, vertical: true)
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

struct AlbumArtControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The iPod also needs a thumbnail file made from its own music. Write it after you flash this patch, and again after each sync that adds albums.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Write Thumbnails to iPod") { Task { await model.writeThumbnails() } }
                    .disabled(model.currentIPod == nil)
                if model.currentIPod == nil { Text("Connect the iPod.").font(.caption).foregroundStyle(.secondary) }
            }
            if let s = model.thumbnailStatus { Label(s, systemImage: "checkmark.circle").font(.caption) }
        }
    }
}

/// Light, Dark or Timed, and the imported dark themes.
struct AppearanceSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            Text("Light uses the Apple colours. Dark applies an imported dark theme when you save, flash, export an .ipsw or run the emulator. Timed changes between light and dark at set hours.")
                .fixedSize(horizontal: false, vertical: true)
            AppearanceControl(selection: $model.appearance) { a in
                switch a {
                case .light: true
                case .dark: !model.themes.isEmpty
                case .timed: false
                }
            }
            .frame(maxWidth: 320)
            Text("Timed is not available yet. It needs a code patch that reads the clock of the iPod.")
                .font(.caption).foregroundStyle(.secondary)
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
                if model.appearance == .dark {
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
