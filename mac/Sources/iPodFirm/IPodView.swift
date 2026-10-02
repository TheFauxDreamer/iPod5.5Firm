import AppKit
import ServiceManagement
import IPodFWKit
import SwiftUI

struct IPodView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                HelperRow()
                FullDiskAccessRow()
                if model.helperStatus == .enabled {
                    Toggle("Ask for Touch ID before flashing or restoring", isOn: $model.requireTouchID)
                }
            } header: { Text("Permission") }

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
                    Button("Eject") { Task { await model.ejectIPod() } }
                        .disabled(model.currentIPod == nil)
                        .help("Unmount the iPod so that you can disconnect it")
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
                Label("CAUTION: Charge the iPod before a recovery. An iPod with an empty battery does not show disk mode.",
                      systemImage: "battery.25percent").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Step(n: 1, text: "Push and hold Menu and Select until the iPod restarts.")
                    Step(n: 2, text: "When the Apple logo shows, push and hold Select and Play until disk mode shows.")
                    Step(n: 3, text: "Connect the iPod to the Mac and click Refresh.")
                    Step(n: 4, text: "Click Restore… on a backup. If the firmware on the iPod is damaged, iPodFirm does a rescue restore.")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("If iPodFirm cannot restore a backup, restore the Apple firmware with Finder.")
                        Text("Finder also repairs a damaged partition table. Finder erases the music on the iPod.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore with Finder…") { Task { await model.restoreWithFinder() } }
                }
            } header: { Text("Recovery") }

            Section {
                SafetyRow(symbol: "externaldrive.badge.timemachine", text: "Every flash or restore first backs up the iPod's whole firmware partition. The very first backup is also kept as a permanent “Original”. Backups are read back to check them, and never overwritten.")
                SafetyRow(symbol: "lock.shield", text: "The boot-flash updater (aupd), the only part that could brick the iPod, is never modified. Flashing is refused if it would change, or if any write would touch it.")
                SafetyRow(symbol: "checklist", text: "The new firmware must pass its checksums and match the iPod's partition layout. You see a preview of exactly what will be written before anything happens.")
                SafetyRow(symbol: "checkmark.circle", text: "Only changed blocks are written, and each is read back and compared.")
                SafetyRow(symbol: "lifepreserver", text: "If the iPod won't start: hold Menu+Select to reset, then Select+Play for disk mode, and restore a backup here. Restoring in Finder also returns it to stock.")
            } header: { Text("Protections") }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshBackups(); model.recheckFullDiskAccess() }
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
                .disabled(model.currentIPod == nil || backup.model == Backups.damagedModel)
                .help(backup.model == Backups.damagedModel ? "This backup is a copy of a damaged firmware. You cannot restore it." : "")
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
            Label(plan.reason == "flash" ? "Flash the edited firmware to the iPod?" : "Restore this backup to the iPod?",
                  systemImage: "bolt.horizontal.circle.fill")
                .font(.title3.bold())
            Text("Target: \(plan.ipod.volumeName ?? plan.ipod.mediaName) (/dev/\(plan.ipod.disk))")
            if plan.reason == "rescue" {
                Label("WARNING: The firmware on the iPod is damaged. iPodFirm cannot compare the backup with it. iPodFirm compares the backup with the original backup, then writes the full backup.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("A backup of the iPod's current firmware is taken first.", systemImage: "externaldrive.badge.timemachine")
                Label("\(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)) will be written in \(ranges.count) place(s), then read back and verified.", systemImage: "square.and.pencil")
                Label("The boot-flash updater (aupd) is not touched.", systemImage: "lock.shield")
            }
            .foregroundStyle(.secondary)
            Text(model.helperStatus == .enabled
                 ? "Keep the iPod connected until this finishes.\(model.requireTouchID ? " You'll confirm with Touch ID." : "")"
                 : "Keep the iPod connected until this finishes. macOS will ask for your administrator password.")
                .font(.callout)
            HStack {
                Spacer()
                Button("Cancel") { model.flashPlan = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(plan.reason == "flash" ? "Back Up & Flash" : "Back Up & Restore") {
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

struct FinderRestoreSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Restore the Apple Firmware with Finder", systemImage: "lifepreserver").font(.title3.bold())
            Text("CAUTION: Finder erases all the music and data on the iPod. Your backups in iPodFirm stay on the Mac.")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Step(n: 1, text: "Put the iPod in disk mode and connect it to the Mac.")
                Step(n: 2, text: "In Finder, select the iPod in the sidebar.")
                Step(n: 3, text: "Push and hold the Option key, then click Restore iPod.")
                Step(n: 4, text: "Select the file iPod_25.1.3.ipsw. A Finder window shows this file now.")
                Step(n: 5, text: "Wait until Finder completes the restore. Do not disconnect the iPod.")
            }
            Text("After the restore, the iPod has the Apple firmware 1.3. You can then restore a backup in iPodFirm.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}

struct FullDiskAccessRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            if model.hasFullDiskAccess {
                Label("Full Disk Access granted: iPodFirm can read and write the iPod's firmware partition.", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Full Disk Access is needed for backups and flashing.", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("How to Allow…") { model.showFullDiskAccessHelp = true }
            }
        }
    }
}

struct FullDiskAccessSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Allow Full Disk Access", systemImage: "lock.shield").font(.title3.bold())
            Text("macOS blocks every app, even with your administrator password, from reading a removable disk directly unless the app has Full Disk Access. iPodFirm needs it to back up and flash the iPod's hidden firmware partition. It only ever reads or writes that partition.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Step(n: 1, text: "Click Open Privacy Settings.")
                Step(n: 2, text: "Turn on iPodFirm in the list. If it isn't listed, click +, choose Applications → iPodFirm.")
                Step(n: 3, text: "Quit and reopen iPodFirm when macOS asks, then try again.")
                Step(n: 4, text: "If the Touch ID helper is on and this still shows orange, also add the helper: click +, press ⌘⇧G and paste its path (Copy Helper Path below).")
            }
            HStack {
                Button("Copy Helper Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Privileged.helperPath, forType: .string)
                }
                Button("Check Again") {
                    model.recheckFullDiskAccess()
                    if model.hasFullDiskAccess { dismiss() }
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open Privacy Settings") { model.openFullDiskAccessSettings() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}

struct HelperRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            switch model.helperStatus {
            case .enabled:
                Label("Touch ID helper is on: no password prompts.", systemImage: "touchid").foregroundStyle(.green)
                Spacer()
                Button("Turn Off") { model.removeHelper() }
            case .requiresApproval:
                Label("Approve “iPodFirm” in System Settings → General → Login Items (Allow in the Background).", systemImage: "touchid")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                Button("Check Again") { model.recheckFullDiskAccess() }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Use Touch ID instead of typing your password.", systemImage: "touchid")
                    Text("Installs a small helper that only iPodFirm can use. You approve it once.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let err = model.helperSetupError { Text(err).font(.caption).foregroundStyle(.red) }
                }
                Spacer()
                Button("Set Up Touch ID") { model.setUpHelper() }.buttonStyle(.borderedProminent)
            }
        }
    }
}

struct Step: View {
    let n: Int
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "\(n).circle.fill") }
    }
}
