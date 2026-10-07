import CryptoKit
import Foundation

// Swift port of src/ipodfw/patcher.py: compile, link and apply code patches to the osos image.
// A patch is a folder with patch.json and one C file. The C file is compiled with Xcode clang
// for the ARM7TDMI. A small linker puts the code at "load_address" and resolves relocations.
// A patch can also change data ("bytes" and "strings"). A patch with no C file has no code.

public struct PatchError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct PatchSpec: Codable, Identifiable, Hashable {
    public struct Hook: Codable, Hashable { public var kind, at, expect, to: String }
    /// A data change: `expect` and `value` are hexadecimal bytes.
    public struct Bytes: Codable, Hashable { public var at, expect, value: String }
    public var id: String { name }
    public var name: String
    public var description: String?
    public var osos_sha256: String
    public var load_address: String?
    public var symbols: [String: String]?
    public var hooks: [Hook]?
    public var bytes: [Bytes]?
    /// Block index -> string key -> new text.
    public var strings: [String: [String: String]]?
    /// A warning for an iPod that probably has the original hard drive (see IPodDisk.likelyOriginalHDD).
    public var hdd_warning: String?
    /// One letter a–z that the About screen can show after the version (see FirmwareVersion.letters).
    public var version_letter: String?
    /// true: the patch is part of a build step (for example the dark-mode switch) and is not shown
    /// in the list of patches.
    public var `internal`: Bool?
}

public struct PatchInfo: Identifiable, Hashable {
    public var id: String { spec.name }
    public var spec: PatchSpec
    public var folder: URL
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

    /// The load address of an extended patch in `osos`: after its end, aligned to 16 bytes.
    public static func extendedBase(_ osos: [UInt8]) -> UInt32 {
        UInt32((max(osos.count, maxOSOSSize) + 15) & ~15)
    }

    public static func list(in folder: URL) -> [PatchInfo] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("patch.json")),
                  let spec = try? JSONDecoder().decode(PatchSpec.self, from: data) else { return nil }
            return PatchInfo(spec: spec, folder: dir)
        }.sorted { $0.spec.name < $1.spec.name }
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
    public static func apply(_ patches: [PatchInfo], to osos: [UInt8], originalSHA256: String? = nil) throws -> [UInt8] {
        let original = originalSHA256 ?? sha256(osos)
        var out = osos
        for p in patches { out = try apply(p, to: out, originalSHA256: original) }
        return out
    }

    public static func isCompatible(_ patch: PatchInfo, originalSHA256: String) -> Bool {
        originalSHA256 == patch.spec.osos_sha256
    }

    /// Apply one patch. `loadAddress` replaces the address in patch.json, and `symbols` adds
    /// addresses that the build decides (for example the address of a table in the osos image).
    public static func apply(_ patch: PatchInfo, to current: [UInt8], originalSHA256: String, loadAddress: UInt32? = nil,
                             symbols: [String: UInt32] = [:], maxSize: Int = maxOSOSSize) throws -> [UInt8] {
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
            (code, table) = try link(try compile(patch.folder), base: base, firmware: fw)
        }
        let end = Int(base) + code.count
        guard end <= maxSize else { throw PatchError("The patch code ends at \(String(end, radix: 16)); the maximum is \(String(maxSize, radix: 16)).") }
        var out = current
        let size = max(out.count, (end + 0x7FF) / 0x800 * 0x800)
        if out.count < size { out += [UInt8](repeating: 0, count: size - out.count) }
        guard out[Int(base)..<end].allSatisfy({ $0 == 0 }) else {
            throw PatchError("The code area of \"\(spec.name)\" is not empty. Two patches possibly use the same area.")
        }
        out.replaceSubrange(Int(base)..<end, with: code)
        for h in spec.hooks ?? [] {
            let at = Int(try hex(h.at))
            let expect = try hex(h.expect)
            guard le32(out, at) == expect else {
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
        return out
    }

    static func hasCode(_ folder: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.pathExtension == "c" }
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
