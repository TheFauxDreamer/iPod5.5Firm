import Foundation

// The patches that the owner installs: a .ipodpatch file (a zip of one patch folder) or a patch folder.
// The library examines a patch before the install, copies it to the user folder, removes it and
// exports it as a .ipodpatch file with precompiled code (patch.o), so that no Xcode is necessary.

/// A patch that the library examined, before the install.
public struct PatchCandidate: Identifiable {
    public let id = UUID()
    /// The folder with patch.json (in the staging folder for a .ipodpatch file).
    public var folder: URL
    public var spec: PatchSpec?
    /// The install is not possible.
    public var errors: [String] = []
    /// The install is possible. The owner must know these items.
    public var notes: [String] = []
    /// The letter that the install writes into patch.json (the letter was missing or in use).
    public var assignedLetter: String?
    /// The size of the linked code in bytes, or nil for a data patch.
    public var codeSize: Int?
    /// The size that the install writes into patch.json (the size was missing or not the measured size).
    public var assignedSize: Int?
    /// true: a user patch with this name is installed. The install replaces it.
    public var replaces = false
    /// true: the patch has a higher version than the built-in patch of the same name. The install replaces the built-in patch.
    public var replacesBuiltIn = false
    /// The version of the patch that the install replaces (user or built-in), or nil if that patch has no version.
    public var installedVersion: String?
    /// The staging folder to delete after the install, for a .ipodpatch file.
    public var staging: URL?

    public var canInstall: Bool { errors.isEmpty && spec != nil }

    /// The relation between this patch and the patch that the install replaces.
    public enum VersionChange { case new, update, same, downgrade }
    public var change: VersionChange {
        guard replaces || replacesBuiltIn else { return .new }
        let mine = spec?.parsedVersion, old = installedVersion.flatMap(PatchVersion.init)
        if PatchVersion.isLower(old, than: mine) { return .update }
        if PatchVersion.isLower(mine, than: old) { return .downgrade }
        return .same
    }
}

public struct PatchLibrary {
    public static let fileExtension = "ipodpatch"
    /// The SHA-256 of the osos image of the Apple firmware 1.3.
    public static let firmware13OSOS = "784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251"
    /// The file types that a patch folder can have.
    static let allowedExtensions: Set<String> = ["c", "o", "json", "md", "txt", "png"]
    /// The load address of the trial link. The value is not important: the link only finds undefined symbols.
    static let trialBase: UInt32 = 0x800000

    public let builtInDir: URL
    public let userDir: URL
    public let stagingDir: URL

    public init(builtInDir: URL, userDir: URL, stagingDir: URL) {
        self.builtInDir = builtInDir
        self.userDir = userDir
        self.stagingDir = stagingDir
    }

    /// The built-in patches and the user patches. A user patch with the name of a built-in patch replaces
    /// the built-in patch only if the user patch has a higher version. Otherwise the user patch is ignored.
    public func list() -> [PatchInfo] {
        var byName = [String: PatchInfo]()
        for p in Patcher.list(in: builtInDir, source: .builtIn) { byName[p.spec.name] = p }
        for var p in Patcher.list(in: userDir, source: .user) {
            if let b = byName[p.spec.name] {
                guard b.source == .builtIn, PatchVersion.isLower(b.spec.parsedVersion, than: p.spec.parsedVersion) else { continue }
                p.replacesBuiltIn = true
                p.builtInVersion = b.spec.version
            }
            byName[p.spec.name] = p
        }
        return byName.values.sorted { $0.spec.name < $1.spec.name }
    }

    // MARK: inspect

    /// Examine a .ipodpatch file or a patch folder. `existing` are the patches that the app has now.
    public func inspect(_ url: URL, existing: [PatchInfo]) throws -> PatchCandidate {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw PatchError("The file \(url.lastPathComponent) does not exist.")
        }
        var staging: URL?
        var root = url
        if !isDir.boolValue {
            let dest = try newStagingFolder()
            staging = dest
            do {
                try Self.run("/usr/bin/ditto", ["-x", "-k", url.path, dest.path])
            } catch {
                cleanStaging(dest)
                throw PatchError("iPodFirm cannot open \(url.lastPathComponent). A patch file must be a zip of one patch folder.")
            }
            root = dest
        }
        guard let folder = Self.patchFolder(in: root) else {
            if let staging { cleanStaging(staging) }
            throw PatchError("\(url.lastPathComponent) has no patch.json. A patch must have patch.json and one C file or patch.o.")
        }
        var c = PatchCandidate(folder: folder, staging: staging)
        validate(&c, existing: existing)
        return c
    }

    /// The folder with patch.json: the root, or the one subfolder of the root.
    static func patchFolder(in root: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("patch.json").path) { return root }
        let subs = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != "__MACOSX" && fm.fileExists(atPath: $0.appendingPathComponent("patch.json").path) }
        return subs.count == 1 ? subs[0] : nil
    }

    func validate(_ c: inout PatchCandidate, existing: [PatchInfo]) {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: c.folder.appendingPathComponent("patch.json")) else {
            c.errors.append("iPodFirm cannot read patch.json.")
            return
        }
        let spec: PatchSpec
        do { spec = try JSONDecoder().decode(PatchSpec.self, from: data) } catch {
            c.errors.append("patch.json is not correct: \(error.localizedDescription)")
            return
        }
        c.spec = spec
        if spec.name.isEmpty || spec.name.unicodeScalars.contains(where: { !"abcdefghijklmnopqrstuvwxyz0123456789-".unicodeScalars.contains($0) }) {
            c.errors.append("The name \"\(spec.name)\" is not valid. Use only the letters a–z, the digits 0–9 and \"-\".")
        }
        if let v = spec.version, PatchVersion(v) == nil {
            c.errors.append("The version \"\(v)\" is not valid. Use one to three numbers with dots, for example 1.2.")
        }
        if let builtIn = Patcher.list(in: builtInDir).first(where: { $0.spec.name == spec.name }) {
            // A user patch can replace a built-in patch only with a higher version.
            if PatchVersion.isLower(builtIn.spec.parsedVersion, than: spec.parsedVersion) {
                c.replacesBuiltIn = true
                c.replaces = existing.contains { $0.spec.name == spec.name && $0.source == .user }
                c.installedVersion = existing.first { $0.spec.name == spec.name }?.spec.version
                c.notes.append("iPodFirm has version \(builtIn.spec.versionText) of this patch built in. This patch replaces it. To use the built-in patch again, remove this patch.")
            } else {
                c.errors.append("iPodFirm already has version \(builtIn.spec.versionText) of the patch \"\(spec.name)\". This file has version \(spec.versionText). Only a higher version can replace a built-in patch. Or give the patch a different name.")
            }
        } else if let other = existing.first(where: { $0.spec.name == spec.name }) {
            c.replaces = true
            c.installedVersion = other.spec.version
        }
        if c.change == .downgrade {
            c.notes.append("The installed version is \(c.installedVersion ?? "–"). This file has the older version \(spec.versionText).")
        }
        if spec.version == nil {
            c.notes.append("The patch has no version in patch.json. iPodFirm cannot compare it with other versions of the patch.")
        }
        if spec.internal == true { c.errors.append("An internal patch cannot be installed.") }

        // The files.
        let files = ((try? fm.contentsOfDirectory(at: c.folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        for f in files {
            if (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                c.errors.append("The patch has a folder (\(f.lastPathComponent)). A patch can have only files.")
            } else if !Self.allowedExtensions.contains(f.pathExtension.lowercased()) {
                c.errors.append("The patch has a file of a type that is not permitted: \(f.lastPathComponent).")
            }
        }
        let sources = files.filter { $0.pathExtension == "c" }
        let hasObject = files.contains { $0.lastPathComponent == Patcher.objectFile }
        if sources.count > 1 { c.errors.append("The patch has more than one C file.") }
        if hasObject {
            let obj = (try? Data(contentsOf: c.folder.appendingPathComponent(Patcher.objectFile))).map { [UInt8]($0) } ?? []
            if !Self.isARMObject(obj) { c.errors.append("patch.o is not an ARM ELF object.") }
        } else if sources.count == 1 && !Self.hasCompiler() {
            c.errors.append("The patch has only C source code. To compile it, install the Xcode command line tools: enter xcode-select --install in Terminal. Or ask for a .ipodpatch file with patch.o.")
        }
        if (hasObject || sources.count == 1) && spec.load_address == nil {
            c.errors.append("The patch has code but no load_address. Use \"load_address\": \"extended\".")
        }

        // The controls.
        if let ui = spec.ui {
            for p in ui.paths where !PatchUI.isSafePath(p) {
                c.errors.append("The path \"\(p)\" is not permitted. A patch can write only below iPod_Control/ on the iPod.")
            }
            for a in ui.actions ?? [] {
                for w in a.write where (w.zeros ?? 0) > PatchUI.maxWrite || (w.zeros ?? 0) < 0 || w.data.count > PatchUI.maxWrite {
                    c.errors.append("The action \"\(a.title)\" writes more than 1 MB to \(w.path).")
                }
            }
            for t in ui.tools ?? [] where !PatchSpec.knownTools.contains(t) {
                c.notes.append("This version of iPodFirm does not have the tool \"\(t)\". The patch operates, but the tool does not show.")
            }
            if let r = ui.readme, r.contains("/") || !fm.fileExists(atPath: c.folder.appendingPathComponent(r).path) {
                c.notes.append("The readme file \"\(r)\" is not in the patch.")
            }
        }

        // A trial link finds undefined symbols.
        if c.errors.isEmpty && (hasObject || sources.count == 1) {
            do {
                var fw = [String: UInt32]()
                for (k, v) in spec.symbols ?? [:] { fw[k] = try Patcher.hex(v) }
                c.codeSize = try Patcher.link(try Patcher.objectCode(c.folder), base: Self.trialBase, firmware: fw).0.count
            } catch {
                c.errors.append("The code of the patch is not correct: \(error.localizedDescription)")
            }
        }

        // The size in patch.json must be the measured size: the Patches pane shows it.
        // The install writes the measured size if it is missing or different.
        if c.errors.isEmpty, let measured = c.codeSize ?? (hasObject || !sources.isEmpty ? nil : 0), spec.size != measured {
            c.assignedSize = measured
            c.notes.append(spec.size == nil
                           ? "The patch does not record its size. iPodFirm records the measured size, \(measured) bytes."
                           : "patch.json gives the size \(spec.size!) bytes, but the measured size is \(measured) bytes. iPodFirm records the measured size.")
        }

        for t in spec.targets ?? [] where t.osos_sha256 != spec.osos_sha256 {
            c.errors.append("The target \"\(t.text)\" has a different osos_sha256 than the patch. Each target must have the osos_sha256 of the patch.")
        }

        // Notes.
        if spec.osos_sha256 != Self.firmware13OSOS {
            c.notes.append("The patch is for \(spec.targetText), not for the Apple firmware 1.3. iPodFirm cannot apply it to firmware 1.3.")
        }
        let others = existing.filter { $0.spec.name != spec.name }
        let used = Set(others.compactMap(\.spec.version_letter))
        if spec.version_letter == nil || used.contains(spec.version_letter!) {
            let free = "abcdefghijklmnopqrstuvwxyz".map(String.init).first { !used.contains($0) }
            if let free {
                c.assignedLetter = free
                c.notes.append(spec.version_letter == nil
                               ? "The patch has no version letter. iPodFirm gives it the letter \"\(free)\"."
                               : "Another patch uses the letter \"\(spec.version_letter!)\". iPodFirm gives this patch the letter \"\(free)\".")
            }
        }
        if spec.title == nil || spec.symbol == nil || spec.category == nil {
            c.notes.append("The patch has no title, symbol or category in patch.json. iPodFirm shows its name in the group \"Other\".")
        }
        let me = PatchInfo(spec: spec, folder: c.folder, source: .user)
        for (_, other, place) in Patcher.conflicts([me] + others).filter({ $0.0.spec.name == spec.name }) {
            c.notes.append("The patch changes the same place as \"\(other.spec.displayTitle)\" (\(place)). You cannot turn on the two patches together. Use \"load_address\": \"extended\" to prevent this.")
        }
    }

    static func isARMObject(_ e: [UInt8]) -> Bool {
        e.count > 52 && Array(e[0..<4]) == [0x7F, 0x45, 0x4C, 0x46] && e[4] == 1 && e[5] == 1 && e[18] == 40 && e[19] == 0
    }

    static func hasCompiler() -> Bool {
        (try? run("/usr/bin/xcrun", ["--find", "clang"])) != nil
    }

    // MARK: sizes

    /// Write the measured size into each user patch that has no `size` (a patch that an earlier
    /// version of iPodFirm installed). The version does not change. A patch that does not link keeps
    /// no size. Returns the names of the changed patches.
    @discardableResult
    public func recordMissingSizes() -> [String] {
        Patcher.list(in: userDir, source: .user).filter { $0.spec.size == nil }.compactMap { p in
            guard let size = try? Patcher.codeSize(p), (try? Self.updateJSON(in: p.folder, ["size": size])) != nil else { return nil }
            return p.spec.name
        }
    }

    // MARK: install, remove, export

    /// Copy the patch to the user folder. Returns the installed folder.
    @discardableResult
    public func install(_ c: PatchCandidate) throws -> URL {
        guard c.canInstall, let spec = c.spec else { throw PatchError("The patch cannot be installed.") }
        let fm = FileManager.default
        try fm.createDirectory(at: userDir, withIntermediateDirectories: true)
        let dest = userDir.appendingPathComponent(spec.name)
        if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
        try fm.copyItem(at: c.folder, to: dest)
        var changes = [String: Any]()
        if let letter = c.assignedLetter { changes["version_letter"] = letter }
        if let size = c.assignedSize { changes["size"] = size }
        try Self.updateJSON(in: dest, changes)
        if let staging = c.staging { cleanStaging(staging) }
        return dest
    }

    /// Move a user patch to the Trash.
    public func remove(_ patch: PatchInfo) throws {
        guard patch.source == .user, patch.folder.deletingLastPathComponent().standardizedFileURL == userDir.standardizedFileURL else {
            throw PatchError("Only a patch that you installed can be removed.")
        }
        try FileManager.default.trashItem(at: patch.folder, resultingItemURL: nil)
    }

    /// Write a .ipodpatch file: the patch folder with patch.o. The C file stays in the package as the source.
    public func export(_ patch: PatchInfo, to url: URL) throws {
        let fm = FileManager.default
        let work = try newStagingFolder()
        defer { cleanStaging(work) }
        let copy = work.appendingPathComponent(patch.spec.name)
        try fm.copyItem(at: patch.folder, to: copy)
        let obj = copy.appendingPathComponent(Patcher.objectFile)
        if Patcher.hasCode(copy) && !fm.fileExists(atPath: obj.path) {
            try Data(try Patcher.compile(copy)).write(to: obj)
        }
        let size = try Patcher.codeSize(PatchInfo(spec: patch.spec, folder: copy))
        // The exported file records the measured size.
        if patch.spec.size != size { try Self.updateJSON(in: copy, ["size": size]) }
        if fm.fileExists(atPath: url.path) { try fm.trashItem(at: url, resultingItemURL: nil) }
        try Self.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", copy.path, url.path])
    }

    /// Write `changes` into the patch.json of `folder`. Nothing changes if `changes` is empty.
    static func updateJSON(in folder: URL, _ changes: [String: Any]) throws {
        guard !changes.isEmpty else { return }
        let file = folder.appendingPathComponent("patch.json")
        guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
            throw PatchError("iPodFirm cannot write into patch.json.")
        }
        json.merge(changes) { $1 }
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: file, options: .atomic)
    }

    // MARK: staging

    func newStagingFolder() throws -> URL {
        let dir = stagingDir.appendingPathComponent("patch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Delete a folder that newStagingFolder made. Any other path is not deleted.
    public func cleanStaging(_ dir: URL) {
        let d = dir.standardizedFileURL
        guard d.deletingLastPathComponent() == stagingDir.standardizedFileURL, d.lastPathComponent.hasPrefix("patch-") else { return }
        try? FileManager.default.removeItem(at: d)
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw PatchError(String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self)
    }
}
