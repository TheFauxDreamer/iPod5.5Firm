import CryptoKit
import Foundation

// Swift port of src/ipodfw/patcher.py: compile, link and apply code patches to the osos image.
// A patch is a folder with patch.json and one C file. The C file is compiled with Xcode clang
// for the ARM7TDMI. A small linker puts the code at "load_address" and resolves relocations.
// A patch can also change data ("bytes" and "strings"). A patch with no C file has no code.
// A hook with "chain" can share its place with a hook of an earlier patch. A patch can add items
// to the Settings menu ("settings_items") and copies of items to other menus ("menu_items"). A patch can have options ("options"): the owner selects a
// choice in the Patches pane, and the patcher writes its value into a variable of the patch.

public struct PatchError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct PatchSpec: Codable, Identifiable, Hashable {
    /// A change of one 32-bit word. With `chain`, the hook can replace the hook of an earlier patch at
    /// the same place. The patch then gets the symbol `chain`: the address that it must call for all the
    /// work that it does not do itself (see `Patcher.chainTarget`).
    public struct Hook: Codable, Hashable {
        public var kind, at, expect, to: String
        /// The symbol that gets the previous target. Only for the kinds "word" and "b".
        public var chain: String? = nil
        /// A "b" hook: the function in the patch that runs the replaced instruction and continues in the
        /// firmware. `chain` is this function if no earlier patch hooks the place.
        public var chain_default: String? = nil
        public init(kind: String, at: String, expect: String, to: String, chain: String? = nil, chain_default: String? = nil) {
            self.kind = kind; self.at = at; self.expect = expect; self.to = to
            self.chain = chain; self.chain_default = chain_default
        }
    }
    /// An On/Off item that the patch adds to the Settings menu (Menu 24598): a copy of the item with
    /// `template_key` (default: Sound Check), with the key `key` and the label `label_id`. The item
    /// comes after the item with `after_key`, or at the end. The hooks of the patch give the label
    /// text and the action (see patches/something-comforting).
    public struct SettingsItem: Codable, Hashable {
        public var key: String
        public var label_id: String
        public var after_key: String? = nil
        public var template_key: String? = nil
    }
    /// A copy of an item in a menu, for example the Music menu (Menu 24440). The copy of the item with the
    /// label `template_label` gets the label `label_id` and goes after the item with `after_label`, or at
    /// the end. Labels are 16-bit string IDs in hexadecimal, for example "0xff82" (-126, "Artists").
    /// The copy does the action of the template item. The hooks of the patch give the label text.
    public struct MenuItem: Codable, Hashable {
        public var menu_id: Int
        public var label_id: String
        public var template_label: String
        public var after_label: String? = nil
        /// Optional. The new 32-bit value at +0x1c: the settings key of an item in a Settings list.
        public var key: String? = nil
    }
    /// A choice that the owner makes in the Patches pane before a build. The patcher writes the
    /// `value` of the selected choice (32 bits) into the global variable `symbol` of the patch.
    /// A precompiled patch.o operates the same, because the value goes into the linked bytes.
    public struct Option: Codable, Hashable {
        public struct Choice: Codable, Hashable {
            public var value: Int
            public var title: String
            public var description: String?
            /// A caution that the Patches pane shows when the owner selects this choice.
            public var caution: String?
        }
        public var id: String
        public var title: String
        public var symbol: String
        public var choices: [Choice]
        public var `default`: Int?
        /// The value without a selection: `default`, or the first choice.
        public var defaultValue: Int { `default` ?? choices.first?.value ?? 0 }
    }
    /// A data change: `expect` and `value` are hexadecimal bytes.
    public struct Bytes: Codable, Hashable {
        public var at, expect, value: String
        public init(at: String, expect: String, value: String) { self.at = at; self.expect = expect; self.value = value }
    }
    /// A firmware build that the patch is for: the iPod model and the firmware version, for display.
    /// `osos_sha256` must be the same as the `osos_sha256` of the patch. The hash is the real check.
    public struct Target: Codable, Hashable {
        public var model: String
        public var firmware: String
        public var osos_sha256: String
        public init(model: String, firmware: String, osos_sha256: String) {
            self.model = model
            self.firmware = firmware
            self.osos_sha256 = osos_sha256
        }
        public var text: String { "\(model), firmware \(firmware)" }
    }
    public var id: String { name }
    public var name: String
    public var description: String?
    public var osos_sha256: String
    /// The firmware builds that the patch is for (display only). Refer to `Target`.
    public var targets: [Target]?
    public var load_address: String?
    public var symbols: [String: String]?
    public var hooks: [Hook]?
    public var bytes: [Bytes]?
    /// Block index -> string key -> new text.
    public var strings: [String: [String: String]]?
    /// Items that the patch adds to the Settings menu.
    public var settings_items: [SettingsItem]?
    /// Copies of items that the patch adds to other menus.
    public var menu_items: [MenuItem]?
    /// Choices that the owner makes in the Patches pane (see Option).
    public var options: [Option]?
    /// A warning for an iPod that probably has the original hard drive (see IPodDisk.likelyOriginalHDD).
    public var hdd_warning: String?
    /// One letter a–z that the About screen can show after the version (see FirmwareVersion.letters).
    public var version_letter: String?
    /// The version of the patch, for example "1.2" (see PatchVersion). The install sheet compares it
    /// with the installed version.
    public var version: String?
    /// The bytes that the patch adds to the firmware on the iPod: the linked code, constants and
    /// variables. 0 for a patch with no code (it changes only bytes that are already there).
    /// The test `testPatchSizes` measures the value.
    public var size: Int?
    /// true: the patch is part of a build step (for example the dark-mode switch) and is not shown
    /// in the list of patches.
    public var `internal`: Bool?
    /// The name in the Patches pane, in title case. The pane shows `name` if there is no title.
    public var title: String?
    /// One line for the list of patches.
    public var summary: String?
    /// The changes that the owner sees on the iPod, one short sentence for each item ("What It Does").
    public var details: [String]?
    /// The hardware or the files that the patch needs ("You Need").
    public var requires: [String]?
    /// More information, one short sentence for each item ("Good to Know").
    public var notes: [String]?
    /// A caution that the Patches pane shows above the switch of the patch.
    public var caution: String?
    /// The SF Symbol of the patch in the Patches pane.
    public var symbol: String?
    /// The group in the list of patches: one of `categories`.
    public var category: String?

    /// Controls in the Patches pane that need no Swift code (see PatchUI).
    public var ui: PatchUI?

    public static let categories = ["display", "power", "audio", "fun", "test"]
    /// The ids of the built-in Swift tools that `ui.tools` can name (PatchTools.swift in the app).
    public static let knownTools = ["album-thumbnails", "usb-log"]
    public var displayTitle: String { title ?? name }
    /// The version, or nil if `version` is missing or not valid.
    public var parsedVersion: PatchVersion? { version.flatMap(PatchVersion.init) }
    /// The version for display, for example "1.2", or "–" if the patch has no version.
    public var versionText: String { version ?? "–" }

    /// The size for display, for example "3,080 bytes (3.0 KB)", or "–" if the patch has no size.
    public var sizeText: String { size.map(Self.byteText) ?? "–" }

    /// For example "3,080 bytes (3.0 KB)", or "188 bytes".
    public static func byteText(_ n: Int) -> String {
        let bytes = "\(n.formatted()) \(n == 1 ? "byte" : "bytes")"
        return n < 1024 ? bytes : bytes + " (" + ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .binary) + ")"
    }

    /// The osos builds that iPodFirm knows, by SHA-256.
    public static let knownFirmware = [
        Target(model: "iPod Video (5G/5.5G)", firmware: "1.3", osos_sha256: "784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251"),
    ]

    /// The targets of the patch. Without `targets`, the known build with the same hash.
    public var targetList: [Target] {
        if let targets, !targets.isEmpty { return targets }
        return Self.knownFirmware.filter { $0.osos_sha256 == osos_sha256 }
    }

    /// For example "iPod Video (5G/5.5G), firmware 1.3", or the start of the hash for an unknown build.
    public var targetText: String {
        let list = targetList
        return list.isEmpty ? "An unknown firmware (osos SHA-256 \(osos_sha256.prefix(12))…)" : list.map(\.text).joined(separator: "; ")
    }
}

/// The version of a patch: one to three numbers with dots, for example "1", "1.2" or "1.2.3".
/// A missing part is 0, thus "1" and "1.0" are equal. A patch with no version is lower than all versions.
public struct PatchVersion: Comparable, Hashable {
    public let parts: [Int]

    public init?(_ text: String) {
        let items = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(items.count),
              items.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy { ("0"..."9").contains($0) } }) else { return nil }
        parts = items.map { Int($0)! } + Array(repeating: 0, count: 3 - items.count)
    }

    public static func < (a: PatchVersion, b: PatchVersion) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }

    /// The version after an edit: 1 is added to the last number. "1.0" gives "1.1", "2" gives "3".
    /// A missing or incorrect version gives "1.0".
    public static func next(after text: String?) -> String {
        guard let text, PatchVersion(text) != nil else { return "1.0" }
        var items = text.split(separator: ".").map { Int($0)! }
        items[items.count - 1] += 1
        return items.map(String.init).joined(separator: ".")
    }

    /// Compare two versions. nil (no version or not valid) is lower than all versions.
    public static func isLower(_ a: PatchVersion?, than b: PatchVersion?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (a?, b?): return a < b
        }
    }
}

/// The `ui` object of patch.json: buttons, switches and text in the Patches pane.
public struct PatchUI: Codable, Hashable {
    /// The content of a file that an action writes on the iPod: a text, or a number of zero bytes.
    public struct Write: Codable, Hashable {
        public var path: String
        public var text: String?
        public var zeros: Int?
        public var data: Data { zeros.map { Data(count: $0) } ?? Data((text ?? "").utf8) }
    }
    /// A button that writes files on the mounted iPod.
    public struct Action: Codable, Hashable {
        public var title: String
        public var write: [Write]
        public var status: String?
    }
    /// A switch that reads a file on the iPod and writes `on` or `off` to it.
    public struct Toggle: Codable, Hashable {
        public var title: String
        public var path: String
        public var on: String
        public var off: String
    }
    public var tools: [String]?
    public var actions: [Action]?
    public var toggles: [Toggle]?
    public var steps_title: String?
    public var steps: [String]?
    /// A Markdown file in the patch folder.
    public var readme: String?

    /// The largest file that an action can write.
    public static let maxWrite = 1 << 20

    /// All the paths on the iPod that the controls write.
    public var paths: [String] { (actions ?? []).flatMap { $0.write.map(\.path) } + (toggles ?? []).map(\.path) }

    /// true: the path is a relative path under iPod_Control/ with no "..".
    public static func isSafePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return path.hasPrefix("iPod_Control/") && !parts.contains("..") && !parts.contains("") && !path.contains("\\")
    }
}

public struct PatchInfo: Identifiable, Hashable {
    /// Built-in: in the app bundle. User: installed in PatchLibrary.userDir.
    public enum Source: Hashable { case builtIn, user }
    public var id: String { spec.name }
    public var spec: PatchSpec
    public var folder: URL
    public var source: Source = .builtIn
    /// true: a user patch with a higher version than the built-in patch of the same name. It replaces the built-in patch.
    public var replacesBuiltIn = false
    /// The version of the built-in patch that this user patch replaces.
    public var builtInVersion: String?
    /// The selected value of each option, by option id. A missing option uses its default.
    public var options: [String: Int] = [:]
    public init(spec: PatchSpec, folder: URL, source: Source = .builtIn) {
        self.spec = spec
        self.folder = folder
        self.source = source
    }
}

public enum Patcher {
    static let clangFlags = ["--target=armv4t-none-eabi", "-mcpu=arm7tdmi", "-marm", "-mfloat-abi=soft", "-O2",
                             "-ffreestanding", "-fno-builtin", "-fno-pic", "-fno-exceptions", "-fno-unwind-tables",
                             "-fno-asynchronous-unwind-tables", "-fno-stack-protector", "-ffunction-sections",
                             "-fdata-sections", "-nostdlib", "-Wall", "-Werror", "-c"]

    /// The largest size of the osos image in firmware 1.3: the start of the rsrc image.
    public static let maxOSOSSize = 0x736800
    /// `"load_address": "extended"`: the build puts the patch after all the data that is already
    /// there (the end of the image, at least `maxOSOSSize`): after a theme, the Dark Mode items and
    /// other extended patches. The limit is `ThemeImport.ososLimit`. The osos image then gets
    /// larger than `maxOSOSSize`, thus the build moves rsrc (`FirmwarePartition.makeRoom`).
    public static let extendedLoadAddress = "extended"

    /// The start of the patch areas. A hook that points at or after this address is the hook of a patch.
    public static let patchAreaStart: UInt32 = 0x7358D0

    /// The load address of an extended patch in `osos`: after its end, aligned to 16 bytes.
    public static func extendedBase(_ osos: [UInt8]) -> UInt32 {
        UInt32((max(osos.count, maxOSOSSize) + 15) & ~15)
    }

    /// The bytes of code and data of a patch (0 for a patch without code). The size does not
    /// depend on the load address. `symbols` adds addresses that the build decides, as in `apply`.
    /// The `size` in patch.json must be this value.
    public static func codeSize(_ patch: PatchInfo, symbols: [String: UInt32] = [:]) throws -> Int {
        guard hasCode(patch.folder) else { return 0 }
        var fw = symbols
        for (k, v) in patch.spec.symbols ?? [:] { fw[k] = try hex(v) }
        for h in patch.spec.hooks ?? [] { if let c = h.chain { fw[c] = 0 } }
        return try link(objectCode(patch.folder), base: UInt32(maxOSOSSize), firmware: fw).0.count
    }

    /// The use of the area after Apple's image (`maxOSOSSize` to `ThemeImport.ososLimit`). The
    /// theme, the Dark Mode items and the extended patches share this area.
    public struct SpaceUse: Equatable {
        /// The end of the image after the build.
        public let end: Int
        public static let start = maxOSOSSize
        public static var limit: Int { ThemeImport.ososLimit }
        public var used: Int { max(0, end - Self.start) }
        public var total: Int { Self.limit - Self.start }
        public var fits: Bool { end <= Self.limit }
        public init(end: Int) { self.end = end }
    }

    /// The space that a build uses: `osos` is the image after the appearance; `patches` are the
    /// switched-on patches in build order with their code sizes. The layout is the same as the
    /// build (`apply` with several patches): an extended patch starts at `extendedBase` (16-byte
    /// steps), each menu that a patch changes ("settings_items", "menu_items") goes after it, and
    /// only the end of the image is rounded to 0x800 bytes.
    public static func spaceUse(osos: [UInt8], patches: [(patch: PatchInfo, size: Int)]) -> SpaceUse {
        var count = osos.count
        var items = [Int16: Int]()                         // the item count of each changed menu
        func itemCount(_ id: Int16) -> Int {
            if let n = items[id] { return n }
            guard let main = try? Resources.mainBlock(Resources.scan(osos, limit: maxOSOSSize)),
                  let r = main.resources.first(where: { $0.type == "Menu" && $0.id == id }),
                  main.abs(r) + 4 <= osos.count else { return 0 }
            return Int(le32(osos, main.abs(r)))
        }
        func addMenu(_ id: Int16, _ added: Int) {
            let n = itemCount(id) + added
            items[id] = n
            count = (max(count, maxOSOSSize) + 15) & ~15 + 4 + 40 * n
        }
        for (p, size) in patches {
            if p.spec.load_address == extendedLoadAddress && size > 0 {
                count = (max(count, maxOSOSSize) + 15) & ~15 + size
            }
            if let s = p.spec.settings_items, !s.isEmpty { addMenu(settingsMenuID, s.count) }
            var ids = [Int]()
            for m in p.spec.menu_items ?? [] where !ids.contains(m.menu_id) { ids.append(m.menu_id) }
            for id in ids { addMenu(Int16(id), (p.spec.menu_items ?? []).filter { $0.menu_id == id }.count) }
        }
        return SpaceUse(end: (count + 0x7FF) / 0x800 * 0x800)
    }

    /// The image with zeros to the next multiple of 0x800 bytes, as in Apple's file.
    public static func padded(_ osos: [UInt8]) -> [UInt8] {
        osos + [UInt8](repeating: 0, count: (osos.count + 0x7FF) / 0x800 * 0x800 - osos.count)
    }

    public static func list(in folder: URL, source: PatchInfo.Source = .builtIn) -> [PatchInfo] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("patch.json")),
                  let spec = try? JSONDecoder().decode(PatchSpec.self, from: data) else { return nil }
            return PatchInfo(spec: spec, folder: dir, source: source)
        }.sorted { $0.spec.name < $1.spec.name }
    }

    /// The precompiled object of a patch. If it is in the folder, the patcher links it and does not compile.
    public static let objectFile = "patch.o"

    /// The ELF object of a patch: patch.o, or the one C file compiled.
    public static func objectCode(_ folder: URL) throws -> [UInt8] {
        let obj = folder.appendingPathComponent(objectFile)
        if FileManager.default.fileExists(atPath: obj.path) { return [UInt8](try Data(contentsOf: obj)) }
        return try compile(folder)
    }

    /// Two turned-on patches that change the same place: the same fixed load address, the same
    /// hook address, overlapping "bytes" ranges or the same Settings item key. The build of such a
    /// pair fails. Hooks with "chain" can share a place.
    public static func conflicts(_ patches: [PatchInfo]) -> [(PatchInfo, PatchInfo, String)] {
        func ranges(_ p: PatchInfo) -> [(Range<Int>, String)] {
            var r: [(Range<Int>, String)] = []
            if let a = p.spec.load_address, a != extendedLoadAddress, hasCode(p.folder), let v = try? hex(a) {
                r.append((Int(v)..<Int(v) + 1, "load address \(a)"))
            }
            for h in p.spec.hooks ?? [] where h.chain == nil {
                if let v = try? hex(h.at) { r.append((Int(v)..<Int(v) + 4, "hook at \(h.at)")) }
            }
            for item in p.spec.settings_items ?? [] {
                if let v = try? hex(item.key) { r.append((Int(v)..<Int(v) + 1, "Settings item \(item.key)")) }
            }
            for item in p.spec.menu_items ?? [] {
                // A separate range for each menu: the menu ID above the 16-bit label.
                if let v = try? hex(item.label_id) {
                    let k = (1 << 32) + item.menu_id << 16 + Int(v & 0xFFFF)
                    r.append((k..<k + 1, "Menu \(item.menu_id) item \(item.label_id)"))
                }
            }
            for b in p.spec.bytes ?? [] {
                if let v = try? hex(b.at) { r.append((Int(v)..<Int(v) + max(1, b.expect.count / 2), "bytes at \(b.at)")) }
            }
            return r
        }
        var out: [(PatchInfo, PatchInfo, String)] = []
        for i in patches.indices {
            for j in patches.indices where j > i {
                let a = ranges(patches[i]), b = ranges(patches[j])
                if let hit = a.first(where: { x in b.contains { $0.0.overlaps(x.0) } }) {
                    out.append((patches[i], patches[j], hit.1))
                }
            }
        }
        return out
    }

    static func sha256(_ b: [UInt8]) -> String { SHA256.hash(data: b).map { String(format: "%02x", $0) }.joined() }

    static func hex(_ s: String) throws -> UInt32 {
        guard let v = UInt32(s.replacingOccurrences(of: "0x", with: ""), radix: 16) else { throw PatchError("Bad hexadecimal value \(s).") }
        return v
    }

    public static func isCompatible(_ patch: PatchInfo, osos: [UInt8]) -> Bool {
        sha256(osos) == patch.spec.osos_sha256
    }

    /// Apply several patches to `osos`. `originalSHA256` is the SHA-256 of the osos before any change
    /// (picture and text changes are allowed: the hooks and the code area are examined byte by byte).
    /// The patches follow each other without a gap (16-byte steps): each one starts after the code,
    /// the variables and the menus of the patch before it. Only the result is rounded to 0x800 bytes.
    public static func apply(_ patches: [PatchInfo], to osos: [UInt8], originalSHA256: String? = nil) throws -> [UInt8] {
        let original = originalSHA256 ?? sha256(osos)
        var out = osos
        for p in patches { out = try apply(p, to: out, originalSHA256: original, pad: false) }
        return padded(out)
    }

    public static func isCompatible(_ patch: PatchInfo, originalSHA256: String) -> Bool {
        originalSHA256 == patch.spec.osos_sha256
    }

    /// Apply one patch. `loadAddress` replaces the address in patch.json, and `symbols` adds
    /// addresses that the build decides (for example the address of a table in the osos image).
    /// With `pad`, the result is rounded to 0x800 bytes. Without it, the image ends at the last byte
    /// of the patch (code, variables and menus), so that the next patch can start there.
    public static func apply(_ patch: PatchInfo, to current: [UInt8], originalSHA256: String, loadAddress: UInt32? = nil,
                             symbols: [String: UInt32] = [:], maxSize: Int = maxOSOSSize, pad: Bool = true) throws -> [UInt8] {
        let spec = patch.spec
        guard originalSHA256 == spec.osos_sha256 else {
            throw PatchError("The patch \"\(spec.name)\" is for a different firmware version.")
        }
        var code = [UInt8](), table = [String: UInt32](), base: UInt32 = 0
        var maxSize = maxSize
        let extended = loadAddress == nil && spec.load_address == extendedLoadAddress
        if extended { maxSize = ThemeImport.ososLimit }
        if hasCode(patch.folder) {
            guard let address = try loadAddress ?? (extended ? Optional(extendedBase(current)) : spec.load_address.map(hex)) else {
                throw PatchError("The patch \"\(spec.name)\" has code but no load_address.")
            }
            base = address
            var fw = [String: UInt32]()
            for (k, v) in spec.symbols ?? [:] { fw[k] = try hex(v) }
            fw.merge(symbols) { $1 }
            let object = try objectCode(patch.folder)
            let chained = (spec.hooks ?? []).filter { $0.chain != nil }
            if !chained.isEmpty {
                // The layout does not depend on the symbol values. Thus a first link gives the address of chain_default.
                for h in chained { fw[h.chain!] = 0 }
                let (_, first) = try link(object, base: base, firmware: fw)
                for h in chained { fw[h.chain!] = try chainTarget(h, in: current, patchSymbols: first) }
            }
            (code, table) = try link(object, base: base, firmware: fw)
            try setOptions(spec, values: patch.options, in: &code, base: base, symbols: table)
        }
        let end = Int(base) + code.count
        guard end <= maxSize else {
            throw PatchError("The firmware is too large: the code of \"\(spec.displayTitle)\" ends at \(String(end, radix: 16)), but the maximum is \(String(maxSize, radix: 16)) (\(end - maxSize) bytes too many). Switch off a patch. The bar below the list of patches shows the space.")
        }
        var out = current
        let size = max(out.count, pad ? (end + 0x7FF) / 0x800 * 0x800 : end)
        if out.count < size { out += [UInt8](repeating: 0, count: size - out.count) }
        guard out[Int(base)..<end].allSatisfy({ $0 == 0 }) else {
            throw PatchError("The code area of \"\(spec.name)\" is not empty. Two patches possibly use the same area.")
        }
        out.replaceSubrange(Int(base)..<end, with: code)
        for h in spec.hooks ?? [] {
            let at = Int(try hex(h.at))
            let expect = try hex(h.expect)
            // A hook with "chain" can also replace the hook of an earlier patch (chainTarget examined it).
            guard le32(out, at) == expect || h.chain != nil else {
                throw PatchError("Hook at \(h.at): the firmware has 0x\(String(le32(out, at), radix: 16)), not \(h.expect).")
            }
            guard let target = h.to.hasPrefix("0x") ? try hex(h.to) : table[h.to] else {
                throw PatchError("The hook target \(h.to) is not a global function in the patch.")
            }
            let value: UInt32
            switch h.kind {
            case "word": value = target
            case "bl", "b": value = try branch(h.kind, at: UInt32(at), to: target)
            default: throw PatchError("Unknown hook kind \(h.kind).")
            }
            put32(&out, at, value)
        }
        try applyData(spec, to: &out)
        if let items = spec.settings_items, !items.isEmpty { try addSettingsItems(items, to: &out) }
        if let items = spec.menu_items, !items.isEmpty { try addMenuItems(items, to: &out) }
        return pad ? padded(out) : out
    }

    /// Write the selected value of each option into its variable in the linked code.
    static func setOptions(_ spec: PatchSpec, values: [String: Int], in code: inout [UInt8], base: UInt32,
                           symbols: [String: UInt32]) throws {
        for o in spec.options ?? [] {
            let value = values[o.id] ?? o.defaultValue
            guard o.choices.contains(where: { $0.value == value }) else {
                throw PatchError("The option \"\(o.title)\" of \"\(spec.displayTitle)\" has no choice with the value \(value).")
            }
            guard let a = symbols[o.symbol], a >= base, Int(a - base) + 4 <= code.count, a & 3 == 0 else {
                throw PatchError("The option \"\(o.id)\": \(o.symbol) is not a global 32-bit variable of the patch.")
            }
            put32(&code, Int(a - base), UInt32(truncatingIfNeeded: value))
        }
    }

    /// The previous target of a hook with `chain`. "word": the word in the firmware (`expect`), or the
    /// address that an earlier patch wrote. "b": `chain_default` if the instruction is `expect`, or the
    /// target of the branch of an earlier patch.
    static func chainTarget(_ h: PatchSpec.Hook, in osos: [UInt8], patchSymbols: [String: UInt32]) throws -> UInt32 {
        let at = Int(try hex(h.at)), expect = try hex(h.expect), word = le32(osos, at)
        switch h.kind {
        case "word":
            if word == expect || word >= patchAreaStart { return word }
        case "b":
            if word == expect {
                guard let name = h.chain_default, let target = patchSymbols[name] else {
                    throw PatchError("Hook at \(h.at): \"chain_default\" must be a global function in the patch.")
                }
                return target
            }
            if word & 0xFF00_0000 == 0xEA00_0000 {
                let offset = (Int64(word & 0xFF_FFFF) ^ 0x80_0000) - 0x80_0000
                let target = UInt32(truncatingIfNeeded: Int64(at) + 8 + offset * 4)
                if target >= patchAreaStart { return target }
            }
        default:
            throw PatchError("Hook at \(h.at): \"chain\" is possible only for the kinds \"word\" and \"b\".")
        }
        throw PatchError("Hook at \(h.at): the firmware has 0x\(String(word, radix: 16)), not \(h.expect) or the hook of a patch.")
    }

    /// The Settings menu of firmware 1.3: Menu 24598 in the main resource block.
    public static let settingsMenuID: Int16 = 24598
    /// The Sound Check item: an On/Off item.
    public static let soundCheckKey: UInt32 = 0x6000_60B7

    /// The Settings menu with one more item: a copy of the item `template`, with `key` and `label`, after the
    /// item `after` (or at the end, if the menu has no such item).
    public static func insertSettingsItem(_ menu: [UInt8], key: UInt32, label: UInt32, after: UInt32?,
                                          template: UInt32 = soundCheckKey) throws -> [UInt8] {
        let count = Int(le32(menu, 0))
        guard menu.count >= 4 + 40 * count else { throw PatchError("The Settings menu is not complete.") }
        var items = (0..<count).map { Array(menu[4 + 40 * $0..<44 + 40 * $0]) }
        let keys = items.map { le32($0, 0x1C) }
        guard !keys.contains(key) else { throw PatchError("The Settings menu already has an item with the key 0x\(String(key, radix: 16)).") }
        guard let t = keys.firstIndex(of: template) else { throw PatchError("The Settings menu is not the menu of firmware 1.3.") }
        var item = items[t]
        put32(&item, 0x18, label); put32(&item, 0x1C, key); put32(&item, 0x20, label)
        items.insert(item, at: after.flatMap { keys.firstIndex(of: $0) }.map { $0 + 1 } ?? items.count)
        var out = [UInt8](repeating: 0, count: 4)
        put32(&out, 0, UInt32(items.count))
        return out + items.flatMap { $0 }
    }

    /// Add the items to the Settings menu. The menu can be the menu of an earlier build step (for example
    /// Dark Mode): the resource table entry gives its place. The new menu goes after the end of `out`,
    /// and the table entry then points to it.
    static func addSettingsItems(_ items: [PatchSpec.SettingsItem], to out: inout [UInt8]) throws {
        let blocks = Resources.scan(out, limit: maxOSOSSize)
        let main = try Resources.mainBlock(blocks)
        guard let res = main.resources.first(where: { $0.type == "Menu" && $0.id == settingsMenuID }) else {
            throw PatchError("The firmware has no Settings menu (Menu 24598).")
        }
        let at = main.abs(res)
        guard at + Int(res.size) <= out.count else { throw PatchError("The Settings menu is outside the image.") }
        var menu = Array(out[at..<at + Int(res.size)])
        for item in items {
            menu = try insertSettingsItem(menu, key: try hex(item.key), label: try hex(item.label_id),
                                          after: try item.after_key.map(hex), template: try item.template_key.map(hex) ?? soundCheckKey)
        }
        let menuAt = Int(extendedBase(out))
        let size = menuAt + menu.count
        guard size <= ThemeImport.ososLimit else { throw PatchError("No space for the Settings menu.") }
        out += [UInt8](repeating: 0, count: size - out.count)
        out.replaceSubrange(menuAt..<menuAt + menu.count, with: menu)
        put32(&out, res.tablePos + 4, UInt32(menuAt - main.dataStart))
        put32(&out, res.tablePos + 8, UInt32(menu.count))
    }

    /// The menu with one more item: a copy of the item with the label `template`, with the label `label`,
    /// after the item with the label `after` (or at the end, if the menu has no such item).
    public static func insertMenuItem(_ menu: [UInt8], label: UInt16, template: UInt16, after: UInt16?,
                                      key: UInt32? = nil) throws -> [UInt8] {
        let count = Int(le32(menu, 0))
        guard menu.count >= 4 + 40 * count else { throw PatchError("The menu is not complete.") }
        var items = (0..<count).map { Array(menu[4 + 40 * $0..<44 + 40 * $0]) }
        let labels = items.map { UInt16($0[0x18]) | UInt16($0[0x19]) << 8 }
        guard !labels.contains(label) else { throw PatchError("The menu already has an item with the label 0x\(String(label, radix: 16)).") }
        guard let t = labels.firstIndex(of: template) else { throw PatchError("The menu has no item with the label 0x\(String(template, radix: 16)).") }
        var item = items[t]
        for at in [0x18, 0x20] { item[at] = UInt8(label & 0xFF); item[at + 1] = UInt8(label >> 8) }
        if let key { put32(&item, 0x1C, key) }
        items.insert(item, at: after.flatMap { labels.firstIndex(of: $0) }.map { $0 + 1 } ?? items.count)
        var out = [UInt8](repeating: 0, count: 4)
        put32(&out, 0, UInt32(items.count))
        return out + items.flatMap { $0 }
    }

    /// Add the items to their menus, as `addSettingsItems` does: each changed menu goes after the end of
    /// `out`, and its resource table entry then points to it.
    static func addMenuItems(_ items: [PatchSpec.MenuItem], to out: inout [UInt8]) throws {
        var ids = [Int]()
        for item in items where !ids.contains(item.menu_id) { ids.append(item.menu_id) }
        for id in ids {
            let main = try Resources.mainBlock(Resources.scan(out, limit: maxOSOSSize))
            guard let res = main.resources.first(where: { $0.type == "Menu" && Int($0.id) == id }) else {
                throw PatchError("The firmware has no Menu \(id).")
            }
            let at = main.abs(res)
            guard at + Int(res.size) <= out.count else { throw PatchError("Menu \(id) is outside the image.") }
            var menu = Array(out[at..<at + Int(res.size)])
            for item in items where item.menu_id == id {
                menu = try insertMenuItem(menu, label: UInt16(truncatingIfNeeded: try hex(item.label_id)),
                                          template: UInt16(truncatingIfNeeded: try hex(item.template_label)),
                                          after: try item.after_label.map { UInt16(truncatingIfNeeded: try hex($0)) },
                                          key: try item.key.map(hex))
            }
            let menuAt = Int(extendedBase(out))
            let size = menuAt + menu.count
            guard size <= ThemeImport.ososLimit else { throw PatchError("No space for Menu \(id).") }
            out += [UInt8](repeating: 0, count: size - out.count)
            out.replaceSubrange(menuAt..<menuAt + menu.count, with: menu)
            put32(&out, res.tablePos + 4, UInt32(menuAt - main.dataStart))
            put32(&out, res.tablePos + 8, UInt32(menu.count))
        }
    }

    static func hasCode(_ folder: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.pathExtension == "c" || $0.lastPathComponent == objectFile }
    }

    static func hexBytes(_ s: String) throws -> [UInt8] {
        let c = Array(s.utf8)
        guard c.count % 2 == 0 else { throw PatchError("Bad hexadecimal bytes \(s).") }
        return try stride(from: 0, to: c.count, by: 2).map { i in
            guard let v = UInt8(String(decoding: c[i..<i + 2], as: UTF8.self), radix: 16) else {
                throw PatchError("Bad hexadecimal bytes \(s).")
            }
            return v
        }
    }

    /// Apply the "bytes" and "strings" sections of a patch.
    static func applyData(_ spec: PatchSpec, to out: inout [UInt8]) throws {
        for e in spec.bytes ?? [] {
            let at = Int(try hex(e.at))
            let expect = try hexBytes(e.expect), value = try hexBytes(e.value)
            guard expect.count == value.count else { throw PatchError("Bytes at \(e.at): \"expect\" and \"value\" have different lengths.") }
            guard at + expect.count <= out.count, Array(out[at..<at + expect.count]) == expect else {
                throw PatchError("Bytes at \(e.at): the firmware does not have \(e.expect).")
            }
            out.replaceSubrange(at..<at + value.count, with: value)
        }
        guard let strings = spec.strings, !strings.isEmpty else { return }
        var blocks = Resources.scan(out)
        for (key, values) in strings {
            guard let i = Int(key), blocks.indices.contains(i) else {
                throw PatchError("The patch \"\(spec.name)\" has strings for block \(key), which the firmware does not have.")
            }
            do { try Resources.writeStrings(&out, &blocks[i], values) } catch {
                throw PatchError("Strings for block \(key): \(error.localizedDescription)")
            }
        }
    }

    static func branch(_ op: String, at: UInt32, to: UInt32) throws -> UInt32 {
        let offset = Int64(to) - Int64(at) - 8
        guard offset & 3 == 0, offset >= -(1 << 25), offset < (1 << 25) else { throw PatchError("A branch cannot reach its target.") }
        return (op == "bl" ? 0xEB00_0000 : 0xEA00_0000) | (UInt32(truncatingIfNeeded: offset >> 2) & 0xFF_FFFF)
    }

    static func compile(_ folder: URL) throws -> [UInt8] {
        let sources = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "c" }
        guard sources.count == 1 else { throw PatchError("A patch must have exactly one C file.") }
        let obj = FileManager.default.temporaryDirectory.appendingPathComponent("ipodfirm-\(UUID().uuidString).o")
        defer { try? FileManager.default.removeItem(at: obj) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["clang"] + clangFlags + [sources[0].path, "-o", obj.path]
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw PatchError("The compiler failed. Xcode or its command line tools are necessary.\n\(msg)")
        }
        return [UInt8](try Data(contentsOf: obj))
    }

    // MARK: ELF linker

    struct Section { var index, kind, flags, offset, size, link, info, align: Int; var name: String }

    static func link(_ e: [UInt8], base: UInt32, firmware: [String: UInt32]) throws -> ([UInt8], [String: UInt32]) {
        guard e.count > 52, Array(e[0..<4]) == [0x7F, 0x45, 0x4C, 0x46], e[4] == 1, e[5] == 1 else { throw PatchError("Not an ELF32 file.") }
        let shoff = Int(le32(e, 0x20)), shentsize = Int(le16(e, 0x2E)), shnum = Int(le16(e, 0x30)), shstrndx = Int(le16(e, 0x32))
        var secs: [Section] = []
        for i in 0..<shnum {
            let o = shoff + i * shentsize
            secs.append(Section(index: i, kind: Int(le32(e, o + 4)), flags: Int(le32(e, o + 8)), offset: Int(le32(e, o + 16)),
                                size: Int(le32(e, o + 20)), link: Int(le32(e, o + 24)), info: Int(le32(e, o + 28)),
                                align: Int(le32(e, o + 32)), name: ""))
        }
        func cstr(_ off: Int) -> String {
            var end = off
            while end < e.count && e[end] != 0 { end += 1 }
            return String(decoding: e[off..<end], as: UTF8.self)
        }
        let shstr = secs[shstrndx]
        for i in secs.indices { secs[i].name = cstr(shstr.offset + Int(le32(e, shoff + i * shentsize))) }

        // place SHF_ALLOC PROGBITS / NOBITS sections
        var place = [Int: UInt32]()
        var cursor = base
        for s in secs where s.flags & 2 != 0 && s.size > 0 && (s.kind == 1 || s.kind == 8) {
            let a = UInt32(max(s.align, 4))
            cursor = (cursor + a - 1) / a * a
            place[s.index] = cursor
            cursor += UInt32(s.size)
        }
        var out = [UInt8](repeating: 0, count: Int(cursor - base))
        for s in secs where place[s.index] != nil && s.kind == 1 {
            let at = Int(place[s.index]! - base)
            out.replaceSubrange(at..<at + s.size, with: e[s.offset..<s.offset + s.size])
        }

        guard let symtab = secs.first(where: { $0.kind == 2 }) else { throw PatchError("The object has no symbol table.") }
        let strtab = secs[symtab.link]
        struct Sym { var name: String; var value: UInt32; var info: UInt8; var shndx: Int }
        var syms: [Sym] = []
        for i in stride(from: 0, to: symtab.size, by: 16) {
            let o = symtab.offset + i
            syms.append(Sym(name: cstr(strtab.offset + Int(le32(e, o))), value: le32(e, o + 4), info: e[o + 12], shndx: Int(le16(e, o + 14))))
        }
        func addr(_ i: Int) throws -> UInt32 {
            let s = syms[i]
            if s.shndx == 0 {
                guard let a = firmware[s.name] else { throw PatchError("Undefined symbol \(s.name): add it to \"symbols\" in patch.json.") }
                return a
            }
            guard let p = place[s.shndx] else { throw PatchError("The symbol \(s.name) is in a section that is not loaded.") }
            return p + s.value
        }
        for rel in secs where rel.kind == 9 {
            guard let tbase = place[rel.info] else { continue }
            for i in stride(from: 0, to: rel.size, by: 8) {
                let rOff = le32(e, rel.offset + i), rInfo = le32(e, rel.offset + i + 4)
                let kind = rInfo & 0xFF, si = Int(rInfo >> 8)
                let p = tbase + rOff
                let at = Int(p - base)
                let word = le32(out, at)
                if kind == 0 || kind == 40 { continue }          // R_ARM_NONE, R_ARM_V4BX
                let s = try addr(si)
                let value: UInt32
                switch kind {
                case 2: value = s &+ word                       // R_ARM_ABS32
                case 3: value = s &+ word &- p                  // R_ARM_REL32
                case 28, 29:                                    // R_ARM_CALL, R_ARM_JUMP24
                    let addend = (Int64(word & 0xFF_FFFF) ^ 0x80_0000) - 0x80_0000
                    let offset = Int64(s) + addend * 4 - Int64(p)
                    guard offset & 3 == 0, offset >= -(1 << 25), offset < (1 << 25) else { throw PatchError("A branch cannot reach its target.") }
                    value = (word & 0xFF00_0000) | (UInt32(truncatingIfNeeded: offset >> 2) & 0xFF_FFFF)
                default: throw PatchError("Relocation type \(kind) is not supported.")
                }
                put32(&out, at, value)
            }
        }
        var table = [String: UInt32]()
        for (i, s) in syms.enumerated() where !s.name.isEmpty && s.shndx != 0 && s.info >> 4 == 1 && place[s.shndx] != nil {
            table[s.name] = try addr(i)
        }
        return (out, table)
    }
}
