import Foundation

// The code of a user patch, for the Code section of the Patches pane: the C file, the firmware
// symbols, the hooks and the byte changes. PatchLibrary.check compiles and links a copy in the
// staging folder. PatchLibrary.saveCode writes the files and increases the version.

/// The code part of a patch. The order of the items is the order in the editor.
public struct PatchCode: Equatable {
    /// A firmware function or data address that the C code uses ("symbols" in patch.json).
    public struct Symbol: Equatable {
        public var name: String
        public var address: String
        public init(name: String = "", address: String = "") { self.name = name; self.address = address }
    }

    /// The C source, or nil if the patch has no C file (a data patch, or a patch with only patch.o).
    public var source: String?
    public var symbols: [Symbol]
    public var hooks: [PatchSpec.Hook]
    public var bytes: [PatchSpec.Bytes]

    public init(source: String?, symbols: [Symbol] = [], hooks: [PatchSpec.Hook] = [], bytes: [PatchSpec.Bytes] = []) {
        self.source = source
        self.symbols = symbols
        self.hooks = hooks
        self.bytes = bytes
    }

    /// The code of an installed patch.
    public init(patch: PatchInfo) {
        let file = PatchCode.sourceFile(patch.folder)
        source = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        symbols = (patch.spec.symbols ?? [:]).sorted { $0.key < $1.key }.map { Symbol(name: $0.key, address: $0.value) }
        hooks = patch.spec.hooks ?? []
        bytes = patch.spec.bytes ?? []
    }

    /// The one C file of a patch folder, or nil.
    public static func sourceFile(_ folder: URL) -> URL? {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "c" }
        return files.count == 1 ? files[0] : nil
    }

    /// The keys of patch.json. A code patch keeps empty "symbols" and "hooks", and a data patch keeps
    /// an empty "bytes". Each other empty list is `NSNull()`, so that the save removes the key.
    var jsonKeys: [String: Any] {
        let isCode = source != nil
        let syms = symbols.filter { !$0.name.isEmpty }
        let symbolMap: [String: Any] = Dictionary(syms.map { ($0.name, $0.address) }, uniquingKeysWith: { $1 })
        let hookList: [Any] = hooks.map { h -> [String: Any] in
            var d: [String: Any] = ["kind": h.kind, "at": h.at, "expect": h.expect, "to": h.to]
            if let c = h.chain { d["chain"] = c }
            if let c = h.chain_default { d["chain_default"] = c }
            return d
        }
        let byteList: [Any] = bytes.map { ["at": $0.at, "expect": $0.expect, "value": $0.value] }
        func keep(_ value: Any, empty: Bool, _ keepEmpty: Bool) -> Any { empty && !keepEmpty ? NSNull() : value }
        return ["symbols": keep(symbolMap, empty: syms.isEmpty, isCode),
                "hooks": keep(hookList, empty: hooks.isEmpty, isCode),
                "bytes": keep(byteList, empty: bytes.isEmpty, !isCode)]
    }

    /// The word at an osos offset as patch.json writes it, for example "0xebffbdc3", or nil.
    public static func word(at offset: String, in osos: [UInt8]) -> String? {
        guard let at = try? Patcher.hex(offset), Int(at) + 4 <= osos.count, at % 4 == 0 else { return nil }
        return String(format: "0x%08x", le32(osos, Int(at)))
    }

    /// `count` bytes at an osos offset as hexadecimal text, for example "0100", or nil.
    public static func bytes(at offset: String, count: Int, in osos: [UInt8]) -> String? {
        guard count > 0, let at = try? Patcher.hex(offset), Int(at) + count <= osos.count else { return nil }
        return osos[Int(at)..<Int(at) + count].map { String(format: "%02x", $0) }.joined()
    }
}

/// The result of Check Code.
public struct PatchCodeCheck: Equatable {
    /// The problems. Save is not possible if there is one.
    public var errors: [String] = []
    /// The size on the iPod, if the code links.
    public var size: Int?
    /// The global functions and data of the C code, for the "to" menu of the hooks.
    public var functions: [String] = []
    public var isOK: Bool { errors.isEmpty }
}

extension PatchLibrary {
    /// Compile and link the code in a copy of the patch, and examine the symbols, the hooks and the
    /// byte changes. `osos` is the open Apple firmware: if it is given, each `expect` must agree with it.
    public func check(_ patch: PatchInfo, _ code: PatchCode, osos: [UInt8]? = nil) -> PatchCodeCheck {
        var r = PatchCodeCheck()
        let validKinds = ["word", "b", "bl"]
        var names = Set<String>()
        for s in code.symbols where !(s.name.isEmpty && s.address.isEmpty) {
            if s.name.isEmpty || !s.name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                r.errors.append("The function name \"\(s.name)\" is not valid. Use letters, digits and \"_\".")
            }
            if (try? Patcher.hex(s.address)) == nil { r.errors.append("The address of \(s.name) is not a hexadecimal number, for example 0x1d83fc.") }
            if !names.insert(s.name).inserted { r.errors.append("The function \(s.name) is in the list two times.") }
        }
        for (i, h) in code.hooks.enumerated() {
            let n = "Hook \(i + 1)"
            if !validKinds.contains(h.kind) { r.errors.append("\(n): the kind must be word, b or bl.") }
            if (try? Patcher.hex(h.at)) == nil { r.errors.append("\(n): \"at\" is not a hexadecimal number.") }
            if (try? Patcher.hex(h.expect)) == nil { r.errors.append("\(n): \"expect\" is not a hexadecimal number.") }
            if h.to.isEmpty { r.errors.append("\(n): select the function in \"to\".") }
            if let osos, h.chain == nil, let word = PatchCode.word(at: h.at, in: osos),
               let expect = try? Patcher.hex(h.expect), (try? Patcher.hex(word)) != expect {
                r.errors.append("\(n): the open firmware has \(word) at \(h.at), not \(h.expect).")
            }
        }
        for (i, b) in code.bytes.enumerated() {
            let n = "Byte change \(i + 1)"
            let expect = try? Patcher.hexBytes(b.expect), value = try? Patcher.hexBytes(b.value)
            if (try? Patcher.hex(b.at)) == nil { r.errors.append("\(n): \"at\" is not a hexadecimal number.") }
            if expect == nil || value == nil || expect!.isEmpty {
                r.errors.append("\(n): \"expect\" and \"value\" must be hexadecimal bytes, for example 0100.")
            } else if expect!.count != value!.count {
                r.errors.append("\(n): \"expect\" and \"value\" must have the same number of bytes.")
            } else if let osos, let have = PatchCode.bytes(at: b.at, count: expect!.count, in: osos), have != b.expect.lowercased() {
                r.errors.append("\(n): the open firmware has \(have) at \(b.at), not \(b.expect).")
            }
        }
        guard let source = code.source else {
            if r.errors.isEmpty { r.size = 0 }
            return r
        }

        // Compile and link a copy, so that the installed patch does not change.
        let work: URL
        do { work = try newStagingFolder() } catch {
            r.errors.append(error.localizedDescription)
            return r
        }
        defer { cleanStaging(work) }
        do {
            let copy = work.appendingPathComponent(patch.spec.name)
            try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
            let name = PatchCode.sourceFile(patch.folder)?.lastPathComponent ?? Self.sourceFileName(patch.spec.name)
            try Data(source.utf8).write(to: copy.appendingPathComponent(name))
            let obj = try Patcher.compile(copy)
            var fw = [String: UInt32]()
            for s in code.symbols where !s.name.isEmpty { if let v = try? Patcher.hex(s.address) { fw[s.name] = v } }
            for h in code.hooks { if let c = h.chain { fw[c] = 0 } }
            let (bytes, table) = try Patcher.link(obj, base: UInt32(Patcher.maxOSOSSize), firmware: fw)
            r.size = bytes.count
            r.functions = table.keys.sorted()
            for (i, h) in code.hooks.enumerated() where !h.to.isEmpty && !h.to.hasPrefix("0x") && table[h.to] == nil {
                r.errors.append("Hook \(i + 1): the code has no global function \(h.to).")
            }
        } catch {
            // Show the file name, not the path of the staging folder.
            r.errors.append(error.localizedDescription.replacingOccurrences(of: work.path + "/" + patch.spec.name + "/", with: ""))
        }
        return r
    }

    /// Write the code into a user patch: the C file and the keys of patch.json. The measured size goes
    /// into patch.json, and the version increases. A patch.o is moved to the Trash, because the build
    /// uses patch.o before the C file. Returns the new version.
    @discardableResult
    public func saveCode(_ patch: PatchInfo, _ code: PatchCode) throws -> String {
        guard isUserPatch(patch) else {
            throw PatchError("Only a patch that you installed or made can be changed.")
        }
        let result = check(patch, code)
        if let e = result.errors.first { throw PatchError(e) }
        let fm = FileManager.default
        if let source = code.source {
            let file = PatchCode.sourceFile(patch.folder) ?? patch.folder.appendingPathComponent(Self.sourceFileName(patch.spec.name))
            try Data(source.utf8).write(to: file, options: .atomic)
            let obj = patch.folder.appendingPathComponent(Patcher.objectFile)
            if fm.fileExists(atPath: obj.path) { try fm.trashItem(at: obj, resultingItemURL: nil) }
        }
        let version = PatchVersion.next(after: patch.spec.version)
        var keys = code.jsonKeys
        keys["version"] = version
        keys["size"] = result.size ?? 0
        try Self.updateJSON(in: patch.folder, keys)
        return version
    }
}
