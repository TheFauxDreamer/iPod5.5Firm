import AppKit
import IPodFWKit
import SwiftUI

struct IPodView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.ipods.isEmpty {
                    Label("No iPod connected. Plug it in (or put it in disk mode: hold Menu+Select to reset, then Select+Play).",
                          systemImage: "cable.connector.slash").foregroundStyle(.secondary)
                } else {
                    Picker("iPod", selection: $model.selectedIPod) {
                        ForEach(model.ipods) { i in
                            Text("\(i.volumeName ?? i.mediaName) — \(ByteCountFormatter.string(fromByteCount: i.size, countStyle: .file)) (/dev/\(i.disk))")
                                .tag(Optional(i.disk))
                        }
                    }
                }
                HStack {
                    Button("Refresh") { Task { await model.refreshIPods() } }
                    Spacer()
                    Button("Back Up Now") { Task { await model.backupNow() } }
                        .disabled(model.currentIPod == nil)
                    Button("Flash Edited Firmware…") { Task { await model.flashEdited() } }
                        .disabled(model.currentIPod == nil || model.editor == nil)
                        .buttonStyle(.borderedProminent)
                }
            } header: { Text("Connected iPod") }

            Section {
                if model.backups.isEmpty {
                    Text("No backups yet. One is taken automatically before every flash, or use Back Up Now.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.backups) { b in BackupRow(backup: b) }
                HStack {
                    Spacer()
                    Button("Show Backups in Finder") {
                        try? FileManager.default.createDirectory(at: AppModel.backupDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(AppModel.backupDir)
                    }
                }
            } header: { Text("Backups") }

            Section {
                SafetyRow(symbol: "externaldrive.badge.timemachine", text: "Every flash or restore first backs up the iPod's whole firmware partition. The very first backup is also kept as a permanent “Original”. Backups are read back to check them, and never overwritten.")
                SafetyRow(symbol: "lock.shield", text: "The boot-flash updater (aupd), the only part that could brick the iPod, is never modified. Flashing is refused if it would change, or if any write would touch it.")
                SafetyRow(symbol: "checklist", text: "The new firmware must pass its checksums and match the iPod's partition layout. You see a preview of exactly what will be written before anything happens.")
                SafetyRow(symbol: "checkmark.circle", text: "Only changed blocks are written, and each is read back and compared.")
                SafetyRow(symbol: "lifepreserver", text: "If the iPod won't start: hold Menu+Select to reset, then Select+Play for disk mode, and restore a backup here. Restoring in Finder also returns it to stock.")
            } header: { Text("Protections") }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshBackups() }
    }
}

struct SafetyRow: View {
    let symbol: String
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(.green) }
    }
}

struct BackupRow: View {
    @EnvironmentObject var model: AppModel
    let backup: BackupInfo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(backup.created, format: .dateTime.year().month().day().hour().minute()).bold()
                    if backup.isOriginal {
                        Text("ORIGINAL").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                }
                Text("\(backup.reason) · \(ByteCountFormatter.string(fromByteCount: Int64(backup.bytes), countStyle: .file)) · \(backup.model)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit a Copy") { Task { await model.open(model.backupURL(backup), fromBackup: true) } }
                .help("Open this backup for editing. The backup file itself is never changed.")
            Button("Restore…") { Task { await model.restore(backup) } }
                .disabled(model.currentIPod == nil)
            Button { NSWorkspace.shared.activateFileViewerSelecting([model.backupURL(backup)]) } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Show in Finder")
        }
    }
}

struct FlashConfirmSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let plan: AppModel.FlashPlan

    var body: some View {
        let ranges = plan.result.ranges ?? []
        let total = ranges.reduce(0) { $0 + $1.length }
        VStack(alignment: .leading, spacing: 14) {
            Label(plan.reason == "restore" ? "Restore this backup to the iPod?" : "Flash the edited firmware to the iPod?",
                  systemImage: "bolt.horizontal.circle.fill")
                .font(.title3.bold())
            Text("Target: \(plan.ipod.volumeName ?? plan.ipod.mediaName) (/dev/\(plan.ipod.disk))")
            VStack(alignment: .leading, spacing: 6) {
                Label("A backup of the iPod's current firmware is taken first.", systemImage: "externaldrive.badge.timemachine")
                Label("\(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)) will be written in \(ranges.count) place(s), then read back and verified.", systemImage: "square.and.pencil")
                Label("The boot-flash updater (aupd) is not touched.", systemImage: "lock.shield")
            }
            .foregroundStyle(.secondary)
            Text("Keep the iPod connected until this finishes. macOS will ask for your administrator password.")
                .font(.callout)
            HStack {
                Spacer()
                Button("Cancel") { model.flashPlan = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(plan.reason == "restore" ? "Back Up & Restore" : "Back Up & Flash") {
                    Task { await model.performFlash(plan) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}
