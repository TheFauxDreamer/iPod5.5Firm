import AppKit
import ServiceManagement
import IPodFWKit
import SwiftUI

struct IPodView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                PermissionSummaryRow()
            } header: { Text("Permission") }

            Section {
                if model.ipods.isEmpty {
                    Label("No iPod is connected. Connect the iPod. If the Mac does not find it, put it in disk mode: hold Menu and Select to reset it, then hold Select and Play.",
                          systemImage: "cable.connector.slash").foregroundStyle(.secondary)
                } else {
                    Picker("iPod", selection: $model.selectedIPod) {
                        ForEach(model.ipods) { i in
                            Text("\(i.volumeName ?? i.mediaName) — \(ByteCountFormatter.string(fromByteCount: i.size, countStyle: .file)) (/dev/\(i.disk))")
                                .tag(Optional(i.disk))
                        }
                    }
                }
                if model.currentIPodIsUnsupported {
                    Label("Unsupported iPod. This iPod is not an iPod Video (5G/5.5G). iPodFirm does not back up, flash or restore it.",
                          systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
                HStack {
                    Button("Refresh") { Task { await model.refreshIPods() } }
                    Button("Eject") { Task { await model.ejectIPod() } }
                        .disabled(model.currentIPod == nil)
                        .help("Unmount the iPod so that you can disconnect it")
                    Spacer()
                    Button("Back Up Now") { Task { await model.backupNow() } }
                        .disabled(model.currentIPod == nil || model.currentIPodIsUnsupported)
                    Button("Flash Edited Firmware…") { Task { await model.flashEdited() } }
                        .disabled(model.currentIPod == nil || model.editor == nil || model.currentIPodIsUnsupported)
                        .buttonStyle(.borderedProminent)
                }
            } header: { Text("Connected iPod") }

            if model.currentIPod != nil && !model.currentIPodIsUnsupported {
                Section {
                    IPodPatchesSection()
                } header: { Text("Patches on This iPod") }
            }

            Section {
                if model.backups.isEmpty {
                    Text("There are no backups. iPodFirm makes a backup before each flash. You can also click Back Up Now.")
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
                Label("Charge the iPod before a recovery. An iPod with an empty battery does not show disk mode.",
                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
                SafetyRow(symbol: "externaldrive.badge.timemachine", text: "Before each flash or restore, iPodFirm makes a backup of the full firmware partition of the iPod. iPodFirm keeps the first backup as a permanent “Original”. iPodFirm reads each backup again to check it, and never overwrites a backup.")
                SafetyRow(symbol: "lock.shield", text: "iPodFirm never changes the boot-flash updater (aupd). Only a change to aupd can make the iPod unusable. iPodFirm stops a flash that changes aupd or writes to aupd.")
                SafetyRow(symbol: "checklist", text: "The new firmware must have correct checksums and agree with the partition layout of the iPod. Before a write, iPodFirm shows each part that it will write.")
                SafetyRow(symbol: "checkmark.circle", text: "iPodFirm writes only the changed blocks. It reads each block again and compares it.")
                SafetyRow(symbol: "lifepreserver", text: "If the iPod does not start, hold Menu and Select to reset it. Then hold Select and Play for disk mode, and restore a backup in iPodFirm. A restore in Finder also puts the Apple firmware on the iPod.")
            } header: { Text("Protections") }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshBackups(); model.recheckFullDiskAccess() }
        .onChange(of: model.selectedIPod) { Task { await model.refreshIPods() } }
    }
}

/// The patches on the connected iPod: from the iPodFirm list in its firmware, or from the changed words.
struct IPodPatchesSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let state = model.ipodState {
            let rows = model.detectablePatches.compactMap { p -> (String, String)? in
                switch state.detections[p.spec.name] ?? .absent {
                case .installed(let v): return (p.spec.displayTitle, v.map { "Version \($0)" } ?? "Installed")
                case .unknown: return (p.spec.displayTitle, "Not known")
                case .absent: return nil
                }
            }
            if rows.isEmpty {
                Text("The iPod has no iPodFirm patches.").foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0) { LabeledContent($0.0, value: $0.1) }
            ForEach(state.unknownNames(known: Set(model.patches.map(\.spec.name))), id: \.self) { name in
                LabeledContent(name, value: "Not in iPodFirm")
            }
            if let list = state.list {
                LabeledContent("Appearance", value: list.appearance.map { a in
                    (AppModel.Appearance(rawValue: a)?.title ?? a) + (list.theme.map { ": \($0)" } ?? "")
                } ?? "Not known")
                LabeledContent("Made with", value: "iPodFirm \(list.app)")
            } else {
                Text("The firmware on the iPod has no iPodFirm list. iPodFirm found the patches from their changes in the firmware. The versions are not known. A flash with this version of iPodFirm adds the list.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else if let status = model.ipodReadStatus {
            Text(status).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Text("iPodFirm did not read the patches on this iPod.").foregroundStyle(.secondary)
        }
        HStack {
            if let state = model.ipodState {
                Text("Read \(state.date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Read iPod") { Task { await model.readIPodPatches(automatic: false) } }
                .disabled(model.busy != nil)
                .help("Read the firmware on the iPod to see its patches. iPodFirm writes nothing to the iPod.")
        }
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
                        Text("Original").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
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
                .disabled(model.currentIPod == nil || model.currentIPodIsUnsupported || backup.model == Backups.damagedModel)
                .help(backup.model == Backups.damagedModel ? "This backup is a copy of a damaged firmware. You cannot restore it." : "")
            Button { NSWorkspace.shared.activateFileViewerSelecting([model.backupURL(backup)]) } label: {
                Image(systemName: "folder")
            }
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")
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
                Label("The firmware on the iPod is damaged. iPodFirm cannot compare the backup with it. iPodFirm compares the backup with the original backup, then writes the full backup.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plan.reason == "flash", let gb = plan.ipod.likelyOriginalHDD {
                ForEach(model.activePatches.filter { $0.spec.hdd_warning != nil }) { p in
                    Label("The iPod has approximately \(gb) GB, the size of an original hard drive. The patch \"\(p.spec.name)\" is on. \(p.spec.hdd_warning ?? "")",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if plan.musicAppRunning {
                Label("MiMusic is open. iPodFirm disconnects the iPod volume during the write. Let each MiMusic sync finish, or quit MiMusic, before you continue.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("First, iPodFirm makes a backup of the current firmware on the iPod.", systemImage: "externaldrive.badge.timemachine")
                Label("iPodFirm writes \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)) in \(ranges.count) place(s). Then it reads the data again and checks it.", systemImage: "square.and.pencil")
                Label("iPodFirm does not change the boot-flash updater (aupd).", systemImage: "lock.shield")
            }
            .foregroundStyle(.secondary)
            Text(model.helperWorks
                 ? "Keep the iPod connected until the operation is complete.\(model.requireTouchID ? " Touch ID asks for a confirmation." : "")"
                 : "Keep the iPod connected until the operation is complete. macOS asks for your administrator password.")
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
            Label("Finder erases all the music and data on the iPod. Your backups in iPodFirm stay on the Mac.",
                  systemImage: "exclamationmark.triangle.fill")
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
    var showHelp: () -> Void
    var body: some View {
        HStack {
            if model.hasFullDiskAccess {
                Label("Full Disk Access is on. iPodFirm can read and write the firmware partition of the iPod.", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Full Disk Access is necessary for backups and flashes.", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("How to Allow…") { showHelp() }
            }
        }
    }
}

/// The permission status in the iPod pane. The Settings window has the controls.
struct PermissionSummaryRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            if model.hasFullDiskAccess {
                Label(model.helperWorks ? "Full Disk Access and Touch ID are on." : "Full Disk Access is on.",
                      systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Full Disk Access is necessary for backups and flashes.", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if !model.hasFullDiskAccess {
                Button("How to Allow…") { model.showFullDiskAccessHelp = true }
            }
            SettingsLink { Text("Settings…") }
        }
    }
}

struct FullDiskAccessSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Allow Full Disk Access", systemImage: "lock.shield").font(.title3.bold())
            Text("macOS does not let an app read a removable disk directly without Full Disk Access. Your administrator password does not change this. iPodFirm needs Full Disk Access to back up and flash the hidden firmware partition of the iPod. It reads and writes only that partition.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Step(n: 1, text: "Click Open Privacy Settings.")
                Step(n: 2, text: "Turn on iPodFirm in the list. If the list does not show iPodFirm, click + and select Applications → iPodFirm.")
                Step(n: 3, text: "When macOS asks, quit iPodFirm and open it again. Then do the operation again.")
                Step(n: 4, text: "If the Touch ID helper is on and the status stays orange, add the helper too. Click +, press ⌘⇧G and paste the path from Copy Helper Path.")
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
                switch model.helperReply {
                case .replied(let version):
                    VStack(alignment: .leading, spacing: 2) {
                        Label("The Touch ID helper is on. macOS does not ask for your password.", systemImage: "touchid")
                            .foregroundStyle(.green)
                        Text("The helper replied (protocol version \(version)).").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Again") { model.recheckFullDiskAccess() }
                    Button("Turn Off") { model.removeHelper() }
                case .noReply:
                    VStack(alignment: .leading, spacing: 2) {
                        Label("The Touch ID helper does not reply.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("macOS shows the helper as on, but cannot start it. iPodFirm asks for your administrator password. Click Repair to register the helper again.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let err = model.helperSetupError { Text(err).font(.caption).foregroundStyle(.red) }
                    }
                    Spacer()
                    Button("Check Again") { model.recheckFullDiskAccess() }
                    Button("Repair") { model.repairHelper() }.buttonStyle(.borderedProminent)
                case .checking, .unknown:
                    ProgressView().controlSize(.small)
                    Text("iPodFirm examines the Touch ID helper…").foregroundStyle(.secondary)
                    Spacer()
                }
            case .requiresApproval:
                Label("Approve “iPodFirm” in System Settings → General → Login Items (Allow in the Background).", systemImage: "touchid")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                Button("Check Again") { model.recheckFullDiskAccess() }
            // An ad-hoc build has no team identifier, and the daemon refuses to start without one.
            case _ where ownTeamIdentifier() == nil:
                VStack(alignment: .leading, spacing: 2) {
                    Label("This build has no developer signature. Touch ID is not available.", systemImage: "touchid")
                    Text("iPodFirm asks for your administrator password before it writes to the iPod.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Use Touch ID, not your password.", systemImage: "touchid")
                    Text("iPodFirm installs a small helper that only iPodFirm can use. You approve it one time.")
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
