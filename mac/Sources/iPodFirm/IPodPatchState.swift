import Foundation
import IPodFWKit

/// The patches on one iPod: from the iPodFirm list in its firmware, or from the changed words.
struct IPodPatchState: Equatable {
    /// The iPod that the state is for: its disk, its name and its size.
    var ipodKey: String
    var date: Date
    var detections: [String: PatchDetection]
    /// The iPodFirm list, if the firmware has one. Without it, the versions and the appearance are not known.
    var list: FirmwareManifest?

    static func key(_ ipod: IPodDisk) -> String { "\(ipod.disk)|\(ipod.mediaName)|\(ipod.size)" }

    /// The names in the list of patches that this app does not have.
    func unknownNames(known: Set<String>) -> [String] {
        (list?.patches ?? []).map(\.name).filter { !known.contains($0) }.sorted()
    }
}

/// The mark of a patch row: the switch compared with the iPod.
enum IPodMark: Equatable {
    /// The switch is on, and the iPod has this version (or the version is not known).
    case onIPod
    /// The switch is on, but the iPod does not have the patch.
    case notFlashed
    /// The switch is off, but the iPod has the patch.
    case willBeRemoved
    /// The switch is on, and the iPod has a different version.
    case update(from: String)
    /// The app cannot see if the iPod has the patch (shared hooks, no iPodFirm list).
    case unknown

    var title: String {
        switch self {
        case .onIPod: "On iPod"
        case .notFlashed: "Not flashed"
        case .willBeRemoved: "Will be removed"
        case .update(let v): "iPod has \(v)"
        case .unknown: "Not known"
        }
    }

    var help: String {
        switch self {
        case .onIPod: "The iPod has this patch."
        case .notFlashed: "The switch is on, but the iPod does not have this patch. Flash the iPod to add it."
        case .willBeRemoved: "The iPod has this patch, but the switch is off. Flash the iPod to remove it."
        case .update(let v): "The iPod has version \(v) of this patch. Flash the iPod to put the new version on it."
        case .unknown: "iPodFirm cannot see if the iPod has this patch. The firmware on the iPod has no iPodFirm list. Flash the iPod one time to add the list."
        }
    }
}

extension AppModel {
    /// The mark for the row of `patch`, or nil if the app did not read the iPod or the switch is off
    /// and the iPod does not have the patch.
    func ipodMark(_ patch: PatchInfo) -> IPodMark? {
        guard let state = ipodState else { return nil }
        let on = enabledPatches.contains(patch.spec.name)
        switch state.detections[patch.spec.name] ?? .absent {
        case .installed(let version):
            guard on else { return .willBeRemoved }
            if let version, let mine = patch.spec.version, version != mine { return .update(from: version) }
            return .onIPod
        case .absent:
            return on ? .notFlashed : nil
        case .unknown:
            return .unknown
        }
    }

    /// The rows that do not agree with the iPod.
    var ipodDifferences: [(PatchInfo, IPodMark)] {
        patches.compactMap { p in
            guard let m = ipodMark(p), m != .onIPod, m != .unknown else { return nil }
            return (p, m)
        }
    }

    /// True if the iPodFirm list on the iPod has a different appearance or theme.
    var ipodAppearanceDiffers: Bool {
        guard let list = ipodState?.list, let a = list.appearance else { return false }
        return a != appearance.rawValue || (a != Appearance.light.rawValue && list.theme != selectedTheme?.name)
    }

    /// The iPodFirm list for the current switches: the build writes it into the firmware.
    var activeList: FirmwareManifest {
        FirmwareManifest(app: version,
                         patches: activePatches.map { .init(name: $0.spec.name, version: $0.spec.version,
                                                            options: $0.options.isEmpty ? nil : $0.options,
                                                            eqs: $0.customEQs.isEmpty ? nil : $0.customEQs) },
                         appearance: appearance.rawValue,
                         theme: appearance == .light ? nil : selectedTheme?.name)
    }

    /// The patches and the dark-mode patch, for the check of an image.
    var detectablePatches: [PatchInfo] { patches + (Self.darkModePatch.map { [$0] } ?? []) }

    /// The state of an osos image (from the iPod, or the image that the app wrote).
    func patchState(osos: [UInt8], ipod: IPodDisk) -> IPodPatchState {
        IPodPatchState(ipodKey: IPodPatchState.key(ipod), date: Date(),
                       detections: Patcher.detect(osos: osos, patches: detectablePatches),
                       list: FirmwareManifest.read(osos: osos))
    }

    /// Use a new state. If the owner did not change a switch since the last flash, restore or read,
    /// the switches, the options and the appearance go to the iPod state.
    func applyIPodState(_ state: IPodPatchState) {
        ipodState = state
        ipodReadStatus = nil
        guard !switchesChangedSinceSync else { return }
        matchIPod()
    }

    /// Set the switches, the options and the appearance from the iPod state.
    func matchIPod() {
        guard let state = ipodState else { return }
        mirroring = true
        defer { mirroring = false }
        let known = Set(patches.map(\.spec.name))
        let mirrored = PatchDetection.mirroredSwitches(current: enabledPatches, detections: state.detections, known: known)
        if mirrored != enabledPatches { enabledPatches = mirrored }
        if let list = state.list {
            for e in list.patches where known.contains(e.name) {
                // A list of a version before 0.7 has the single EQ in the options.
                if patches.first(where: { $0.spec.name == e.name })?.spec.eq_editor != nil {
                    let eqs = e.eqs ?? e.options.map { [NamedEQ(options: $0)] }
                    if let eqs = eqs.map({ Array($0.prefix(CustomEQ.maxEQs)) }), !eqs.isEmpty, customEQs != eqs { customEQs = eqs }
                } else if let o = e.options, patchOptions[e.name] != o { patchOptions[e.name] = o }
            }
            if let a = list.appearance.flatMap(Appearance.init(rawValue:)) {
                if a != .light, let t = list.theme, themes.contains(where: { $0.name == t }) { selectedThemeName = t }
                if a == .light || themes.contains(where: { $0.name == list.theme }) { appearance = a }
            }
        }
        switchesChangedSinceSync = false
    }

    /// Read the patches on the connected iPod. Nothing is written to the iPod. `automatic`: only with the
    /// Touch ID helper (version 3 or later), so that no password prompt opens when an iPod connects.
    func readIPodPatches(automatic: Bool) async {
        guard let ipod = currentIPod, busy == nil else { return }
        let dir = Self.supportDir.appendingPathComponent("Staging")
        let file = dir.appendingPathComponent(Operations.readFileName)
        do {
            let viaHelper: Bool
            if HelperClient.isEnabled, let s = try? await HelperClient.status(), s.version >= helperReadVersion {
                viaHelper = true
            } else {
                guard !automatic else {
                    ipodReadStatus = "Click Read iPod to see the patches on the iPod."
                    return
                }
                viaHelper = false
            }
            ipodReadStatus = "Reading the patches on the iPod…"
            AppLog.step("Helper (\(viaHelper ? "daemon" : "password")): read the osos of \(ipod.disk)")
            let r = viaHelper ? try await HelperClient.readOSOS(disk: ipod.disk, dir: dir)
                              : try await Privileged.run(helperArgs("read", dir: dir, ipod))
            guard r.ok else { throw r.failure() }
            let osos = try await Task.detached { [UInt8](try Data(contentsOf: file)) }.value
            try? FileManager.default.removeItem(at: file)
            applyIPodState(patchState(osos: osos, ipod: ipod))
        } catch {
            AppLog.warning("Cannot read the patches on the iPod\n" + AppLog.describe(error))
            ipodReadStatus = "Cannot read the patches on the iPod: \(error.localizedDescription)"
        }
    }

    /// After a write to the iPod: the state of the image that the app wrote. The switches then show it.
    func recordWrittenImage(_ image: URL, ipod: IPodDisk) {
        guard let p = try? FirmwarePartition(contentsOf: image), let osos = try? p.image("osos") else { return }
        switchesChangedSinceSync = false
        applyIPodState(patchState(osos: osos, ipod: ipod))
    }
}

/// One log file on the connected iPod.
struct IPodLogFile: Identifiable {
    enum Kind: CaseIterable { case playback, diagnostic, usb }

    let kind: Kind
    let bytes: Int
    let date: Date?
    var id: Kind { kind }

    var title: String {
        switch kind {
        case .playback: "Playback Log"
        case .diagnostic: "Diagnostic Log"
        case .usb: "USB Log"
        }
    }

    var details: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return date.map { "\(size) · Changed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? size
    }
}
