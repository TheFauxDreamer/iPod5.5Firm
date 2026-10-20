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

/// The text of a new patch or of a patch to edit: the fields of the New Patch form (PatchEditor.swift
/// in the app). `PatchLibrary.create` and `PatchLibrary.edit` write it into patch.json.
public struct PatchDraft: Equatable {
    /// A patch with C code, or a patch that changes only bytes of the firmware ("bytes").
    public enum Kind: String, CaseIterable { case code, bytes }

    public var title = ""
    public var name = ""
    public var summary = ""
    public var description = ""
    public var details: [String] = []
    public var requires: [String] = []
    public var notes: [String] = []
    public var caution = ""
    public var symbol = "puzzlepiece.extension"
    public var category = "fun"
    public var kind = Kind.code

    public init() {}

    /// The text of an installed patch, for an edit.
    public init(spec: PatchSpec) {
        title = spec.title ?? ""
        name = spec.name
        summary = spec.summary ?? ""
        description = spec.description ?? ""
        details = spec.details ?? []
        requires = spec.requires ?? []
        notes = spec.notes ?? []
        caution = spec.caution ?? ""
        symbol = spec.symbol ?? ""
        category = spec.category ?? ""
        kind = spec.load_address == nil ? .bytes : .code
    }

    /// The patch name for a title: lower case, and "-" in place of each other character.
    /// For example "Sleep Now" gives "sleep-now".
    public static func name(fromTitle title: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        let mapped = String(title.lowercased().map { allowed.contains($0) ? $0 : "-" })
        return mapped.split(separator: "-").joined(separator: "-")
    }

    /// The problems that prevent a save. `existing` are the patches that the app has now. `editing`
    /// is the patch that the owner edits, or nil for a new patch.
    public func problems(existing: [PatchInfo], editing: PatchInfo? = nil) -> [String] {
        var r = [String]()
        if trim(title).isEmpty { r.append("Type a title.") }
        if trim(summary).isEmpty { r.append("Type a summary.") }
        if editing == nil {
            if !PatchLibrary.isValidName(name) {
                r.append("The name \"\(name)\" is not valid. Use only the letters a–z, the digits 0–9 and \"-\".")
            } else if existing.contains(where: { $0.spec.name == name }) {
                r.append("A patch with the name \"\(name)\" exists. Give the patch a different name.")
            }
        }
        if !PatchSpec.categories.contains(category) { r.append("Select a group.") }
        if trim(symbol).isEmpty { r.append("Type the name of an SF Symbol.") }
        return r
    }

    /// The text keys of patch.json. An empty value is `NSNull()`, so that an edit removes the key.
    var textKeys: [String: Any] {
        func text(_ s: String) -> Any { trim(s).isEmpty ? NSNull() : trim(s) }
        func list(_ a: [String]) -> Any {
            let items = a.map(trim).filter { !$0.isEmpty }
            return items.isEmpty ? NSNull() : items
        }
        return ["title": text(title), "summary": text(summary), "description": text(description),
                "details": list(details), "requires": list(requires), "notes": list(notes),
                "caution": text(caution), "symbol": text(symbol), "category": text(category)]
    }

    func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
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
        if !Self.isValidName(spec.name) {
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

        // The options.
        for o in spec.options ?? [] {
            let values = o.choices.map(\.value)
            if values.isEmpty || Set(values).count != values.count {
                c.errors.append("The option \"\(o.title)\" must have one or more choices with different values.")
            } else if let d = o.default, !values.contains(d) {
                c.errors.append("The default of the option \"\(o.title)\" is not one of its choices.")
            }
        }

        // A trial link finds undefined symbols and option variables that are not there.
        if c.errors.isEmpty && (hasObject || sources.count == 1) {
            do {
                var fw = [String: UInt32]()
                for (k, v) in spec.symbols ?? [:] { fw[k] = try Patcher.hex(v) }
                for h in spec.hooks ?? [] { if let c = h.chain { fw[c] = 0 } }   // the build gives the real target
                var (code, table) = try Patcher.link(try Patcher.objectCode(c.folder), base: Self.trialBase, firmware: fw)
                c.codeSize = code.count
                try Patcher.setOptions(spec, values: [:], in: &code, base: Self.trialBase, symbols: table)
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
            if let free = Self.freeLetter(used: used) {
                c.assignedLetter = free
                c.notes.append(spec.version_letter == nil
                               ? "The patch has no version letter. iPodFirm gives it the letter \"\(free)\"."
                               : "Another patch uses the letter \"\(spec.version_letter!)\". iPodFirm gives this patch the letter \"\(free)\".")
            }
        }
        if spec.title == nil || spec.symbol == nil || spec.category == nil {
            c.notes.append("The patch has no title, symbol or category in patch.json. iPodFirm shows the name of the patch, and puts the patch in the group \"Community\".")
        }
        let me = PatchInfo(spec: spec, folder: c.folder, source: .user)
        for (_, other, place) in Patcher.conflicts([me] + others).filter({ $0.0.spec.name == spec.name }) {
            c.notes.append("The patch changes the same place as \"\(other.spec.displayTitle)\" (\(place)). You cannot turn on the two patches together. Use \"load_address\": \"extended\" to prevent this.")
        }
    }

    /// true: the name has only the letters a–z, the digits 0–9 and "-". The name is also the folder name.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789-".unicodeScalars.contains($0) }
    }

    /// The first letter a–z that is not in `used`, or nil if all letters are in use.
    static func freeLetter(used: Set<String>) -> String? {
        "abcdefghijklmnopqrstuvwxyz".map(String.init).first { !used.contains($0) }
    }

    static func isARMObject(_ e: [UInt8]) -> Bool {
        e.count > 52 && Array(e[0..<4]) == [0x7F, 0x45, 0x4C, 0x46] && e[4] == 1 && e[5] == 1 && e[18] == 40 && e[19] == 0
    }

    public static func hasCompiler() -> Bool {
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

    /// true: the patch is a folder in `userDir`. The paths are compared, not the URLs: a URL of a
    /// folder that did not exist when the app started has no "/" at the end, and the URLs are then not equal.
    func isUserPatch(_ patch: PatchInfo) -> Bool {
        patch.source == .user
            && patch.folder.deletingLastPathComponent().standardizedFileURL.path == userDir.standardizedFileURL.path
    }

    /// Move a user patch to the Trash. If the folder does not exist (another copy of iPodFirm
    /// removed it), nothing occurs.
    public func remove(_ patch: PatchInfo) throws {
        guard isUserPatch(patch) else {
            throw PatchError("Only a patch that you installed can be removed.")
        }
        guard FileManager.default.fileExists(atPath: patch.folder.path) else { return }
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

    /// Write `changes` into the patch.json of `folder`. The value `NSNull()` removes the key.
    /// Nothing changes if `changes` is empty.
    static func updateJSON(in folder: URL, _ changes: [String: Any]) throws {
        guard !changes.isEmpty else { return }
        let file = folder.appendingPathComponent("patch.json")
        guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
            throw PatchError("iPodFirm cannot write into patch.json.")
        }
        json.merge(changes) { $1 }
        json = json.filter { !($0.value is NSNull) }
        try writeJSON(json, to: file)
    }

    static func writeJSON(_ json: [String: Any], to file: URL) throws {
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: file, options: .atomic)
    }

    // MARK: create, edit

    /// The name of the C file of a new code patch, for example "sleep_now.c" for "sleep-now".
    public static func sourceFileName(_ name: String) -> String { name.replacingOccurrences(of: "-", with: "_") + ".c" }

    /// Make a new user patch from the New Patch form. The patch gets the version 1.0, a free letter
    /// and the targets of the Apple firmware 1.3. A code patch gets `"load_address": "extended"`, a C
    /// file to start from and the measured size. Returns the new folder.
    @discardableResult
    public func create(_ d: PatchDraft) throws -> URL {
        let fm = FileManager.default
        let existing = list() + Patcher.list(in: builtInDir)
        if let problem = d.problems(existing: existing).first { throw PatchError(problem) }
        let folder = userDir.appendingPathComponent(d.name)
        guard !fm.fileExists(atPath: folder.path) else {
            throw PatchError("The folder \(d.name) exists in the patches folder. Give the patch a different name.")
        }
        var json = d.textKeys.filter { !($0.value is NSNull) }
        let target: [String: Any] = ["model": "iPod Video (5G/5.5G)", "firmware": "1.3", "osos_sha256": Self.firmware13OSOS]
        json["name"] = d.name
        json["osos_sha256"] = Self.firmware13OSOS
        json["targets"] = [target]
        json["version"] = "1.0"
        if let letter = Self.freeLetter(used: Set(existing.compactMap(\.spec.version_letter))) { json["version_letter"] = letter }
        switch d.kind {
        case .bytes:
            json["bytes"] = [Any]()
            json["size"] = 0
        case .code:
            json["load_address"] = Patcher.extendedLoadAddress
            json["symbols"] = [String: Any]()
            json["hooks"] = [Any]()
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try Self.writeJSON(json, to: folder.appendingPathComponent("patch.json"))
            if d.kind == .code {
                let source = Self.starterSource(name: d.name, summary: d.trim(d.summary))
                try Data(source.utf8).write(to: folder.appendingPathComponent(Self.sourceFileName(d.name)))
                let spec = try JSONDecoder().decode(PatchSpec.self, from: Data(contentsOf: folder.appendingPathComponent("patch.json")))
                try Self.updateJSON(in: folder, ["size": try Patcher.codeSize(PatchInfo(spec: spec, folder: folder))])
            }
        } catch {
            try? fm.trashItem(at: folder, resultingItemURL: nil)
            throw error
        }
        return folder
    }

    /// Write the text of the form into the patch.json of a user patch, and increase the version.
    /// The name does not change. Returns the new version.
    @discardableResult
    public func edit(_ patch: PatchInfo, with d: PatchDraft) throws -> String {
        guard isUserPatch(patch) else {
            throw PatchError("Only a patch that you installed or made can be edited.")
        }
        if let problem = d.problems(existing: list(), editing: patch).first { throw PatchError(problem) }
        let version = PatchVersion.next(after: patch.spec.version)
        try Self.updateJSON(in: patch.folder, d.textKeys.merging(["version": version]) { $1 })
        return version
    }

    /// The C file of a new code patch. It has one empty function, so that the link gives a size.
    static func starterSource(name: String, summary: String) -> String {
        """
        /* \(name): \(summary)
         *
         * Write the code of the patch in this file. iPodFirm compiles it for the ARM7TDMI CPU of the iPod.
         * The code has no C library. Use the functions of the firmware.
         *
         * To call a firmware function:
         *   1. Declare the function in this file, for example: int fw_example(void *ctl);
         *   2. Add the name and the osos offset to "symbols" in patch.json,
         *      for example: "symbols": { "fw_example": "0x1d83fc" }
         *
         * To connect a function of this file to the firmware, add a hook to "hooks" in patch.json:
         *   { "kind": "bl", "at": "<osos offset>", "expect": "<the word in the Apple firmware>", "to": "hook_example" }
         *
         * docs/patch-system.md tells about the compiler, the symbols and the hooks.
         * docs/firmware-functions.md lists the firmware functions that are known.
         * When the patch is complete, select it in the Patches pane. Then click Export Patch….
         */

        void hook_example(void)
        {
        }

        """
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
