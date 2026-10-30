import IPodFWKit
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let ed = model.editor {
            let fw = ed.partition
            Form {
                Section("Firmware") {
                    LabeledContent("File", value: model.fileURL?.lastPathComponent ?? "-")
                    LabeledContent("Model", value: fw.model)
                    LabeledContent("Partition format", value: "version \(fw.formatVersion), images at +\(fw.imageBase) bytes")
                    LabeledContent("Status", value: model.isDirty ? "Edited (not saved or flashed)" : "Unmodified")
                    if model.openedFromBackup {
                        Text("Opened from a backup. Your edits never change the backup file itself.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section("Images") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow {
                            Text("Image").bold(); Text("Size").bold(); Text("Checksum").bold(); Text("Role").bold()
                        }
                        ForEach(fw.entries, id: \.index) { e in
                            GridRow {
                                Text(e.name).monospaced()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(e.length), countStyle: .file))
                                checksum(e.name, fw)
                                Text(role(e.name)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Contents") {
                    LabeledContent("Pictures", value: "\(ed.pictures.count)")
                    LabeledContent("Languages", value: "\(ed.stringBlocks.count) text blocks")
                    LabeledContent("Resource blocks", value: "\(ed.blocks.count)")
                }
            }
            .formStyle(.grouped)
            .id(model.revision)
        }
    }

    @ViewBuilder func checksum(_ name: String, _ fw: FirmwarePartition) -> some View {
        if name == "aupd" {
            Label("never modified", systemImage: "lock.fill").foregroundStyle(.secondary)
        } else if name == "hibe" {
            Label("not checked", systemImage: "moon.zzz.fill").foregroundStyle(.secondary)
        } else if fw.checksumOK(name) {
            Label("OK", systemImage: "checkmark.seal.fill").labelStyle(StatusLabelStyle(tint: .green))
        } else {
            Label("BAD", systemImage: "xmark.octagon.fill").labelStyle(StatusLabelStyle(tint: .red))
        }
    }

    func role(_ name: String) -> String {
        switch name {
        case "osos": "Apple OS: code, pictures and text (edited here)"
        case "rsrc": "Video chip firmware and fonts"
        case "aupd": "Boot-flash updater (protected)"
        case "hibe": "Hibernation snapshot written by the iPod itself (left untouched)"
        default: ""
        }
    }
}
