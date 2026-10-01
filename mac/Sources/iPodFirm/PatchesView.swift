import IPodFWKit
import SwiftUI

/// Code patches: changes to the behaviour of the iPod software. Each one can be switched on or off.
struct PatchesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
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
