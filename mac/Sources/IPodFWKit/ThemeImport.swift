import CryptoKit
import Foundation

// Swift port of src/ipodfw/themeimport.py: import an iPodWizard theme into a different firmware
// version.
//
// An iPodWizard theme is a complete firmware partition. Most themes are for firmware 1.2.1. The
// import compares the theme with the Apple firmware that it came from ("base"). Then it applies the
// changes to the target firmware (for example, Apple firmware 1.3).
//
// The result is an iPodFirm theme: a list of byte changes to the target osos. Each change has the
// old bytes and the new bytes. Thus, the app can apply the theme or not, and an edit by the owner
// stays when the old bytes are different.
//
// Rules:
// - The resources are matched by block, type and ID. Apple changed the negative IDs between the
//   versions (1.2.1 -279 is 1.3 -277), so the import finds them by their contents.
// - BMap: the import copies a picture if the target picture has the same header (format, width and
//   height). A picture that the theme made larger goes into free space after the end of osos.
// - Type: the import changes a word (4 bytes) only where the target has the base value.
// - View: a View is a count and a list of elements (u32 size - 4, u32 flags, tag, u32 ID, ...). The
//   import matches the elements and changes a field only where the target has the base value. It
//   translates the resource IDs in the fields.
// - Other resource types and program code: the import does not apply them.

public struct ThemeError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct ThemeChange: Codable, Equatable {
    public var resource: String
    public var offset: Int          // in the target osos
    public var old: Data
    public var new: Data
}

public struct ThemeSkip: Codable, Equatable {
    public var resource: String
    public var reason: String
}

/// An iPodFirm theme file (JSON, the same format as `ipodfw import-theme`).
public struct ImportedTheme: Codable, Equatable, Identifiable {
    public var id: String { name + " " + osos_sha256 }
    public var format = ThemeImport.format
    public var name: String
    public var source_sha256: String
    public var osos_sha256: String
    public var imported: [String] = []
    public var skipped: [ThemeSkip] = []
    public var changes: [ThemeChange] = []

    public static func load(_ url: URL) throws -> ImportedTheme {
        let t = try JSONDecoder().decode(ImportedTheme.self, from: Data(contentsOf: url))
        guard t.format == ThemeImport.format else { throw ThemeError("This theme file has an unknown format.") }
        return t
    }

    public func write(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// Apply the theme to osos. Returns (changes applied, changes not applied because of other edits).
    @discardableResult
    public func apply(to osos: inout [UInt8], originalSHA256: String) throws -> (applied: Int, conflicts: Int) {
        guard originalSHA256 == osos_sha256 else { throw ThemeError("The theme \"\(name)\" is for a different firmware.") }
        let end = changes.map { $0.offset + $0.new.count }.max() ?? 0
        if end > osos.count { osos += [UInt8](repeating: 0, count: (end + 0x7FF) / 0x800 * 0x800 - osos.count) }
        var done = 0, conflicts = 0
        for c in changes {
            let cur = osos[c.offset..<c.offset + c.old.count]
            if cur.elementsEqual(c.old) {
                osos.replaceSubrange(c.offset..<c.offset + c.new.count, with: c.new)
                done += 1
            } else if cur.elementsEqual(c.new) {
                done += 1
            } else {
                conflicts += 1
            }
        }
        return (done, conflicts)
    }
}

public enum ThemeImport {
    public static let format = 1
    /// Join two changed runs if fewer bytes than this separate them.
    static let runGap = 16
    /// The negative IDs of a type move by a small amount between versions.
    static let idShifts = (-8...8).sorted { abs($0) < abs($1) }
    /// The reset code of RetailOS stops if the end of the OS image is after 8 MB (0x800004). A
    /// picture that the theme makes larger goes after the current end of osos, below this limit.
    public static let ososLimit = 0x7F0000
    /// Element tag -> the resource type that the ID at +12 refers to.
    static let elementIDType = ["BMap": "BMap", "Draw": "BMap", "Str ": "Str ", "None": "View"]

    struct Key: Hashable, Comparable {
        var block: String
        var type: String
        var id: Int
        static func < (a: Key, b: Key) -> Bool { (a.block, a.type, a.id) < (b.block, b.type, b.id) }
        var label: String { "\(type.trimmingCharacters(in: .whitespaces)) \(id)" + (block == "main" ? "" : " (\(block))") }
    }

    /// The Apple part of osos and its resources, keyed by (block, type, id).
    struct Image {
        let osos: [UInt8]
        let blocks: [ResourceBlock]
        var keys: [Key] = []                      // in the order of the blocks and tables
        var res: [Key: (Resource, ResourceBlock)] = [:]

        init(_ fw: FirmwarePartition) throws {
            osos = try fw.image("osos")
            blocks = Resources.scan(osos, limit: fw.appleOSLength)
            let main = try Resources.mainBlock(blocks)
            for b in blocks {
                let name = b.index == main.index ? "main" : "block\(b.index)"
                for r in b.resources {
                    let k = Key(block: name, type: r.type, id: Int(r.id))
                    if res[k] == nil { keys.append(k) }
                    res[k] = (r, b)
                }
            }
        }

        func pos(_ k: Key) -> Int { let (r, b) = res[k]!; return b.abs(r) }
        func data(_ k: Key) -> [UInt8] { let p = pos(k); return Array(osos[p..<p + Int(res[k]!.0.size)]) }
    }

    public static func sha256(_ b: [UInt8]) -> String { SHA256.hash(data: b).map { String(format: "%02x", $0) }.joined() }

    /// Map the resource keys of base to target. Negative IDs are found by their contents.
    static func idMap(_ base: Image, _ target: Image) -> [Key: Key] {
        var out: [Key: Key] = [:]
        var shifts: [String: [(shift: Int, count: Int)]] = [:]   // per block+type, in first-seen order
        for key in base.keys {
            if key.id >= 0 {
                if target.res[key] != nil { out[key] = key }
                continue
            }
            let data = base.data(key)
            for d in idShifts {
                let k2 = Key(block: key.block, type: key.type, id: key.id + d)
                if target.res[k2] != nil, target.data(k2) == data {
                    out[key] = k2
                    let group = key.block + "/" + key.type
                    if let i = shifts[group, default: []].firstIndex(where: { $0.shift == d }) {
                        shifts[group]![i].count += 1
                    } else {
                        shifts[group, default: []].append((d, 1))
                    }
                    break
                }
            }
        }
        // A changed resource has no equal copy: use the most frequent shift of its type.
        for key in base.keys where out[key] == nil && key.id < 0 {
            guard let counts = shifts[key.block + "/" + key.type], !counts.isEmpty else { continue }
            var best = counts[0]
            for c in counts.dropFirst() where c.count > best.count { best = c }
            let k2 = Key(block: key.block, type: key.type, id: key.id + best.shift)
            if let t = target.res[k2], t.0.size == base.res[key]!.0.size { out[key] = k2 }
        }
        return out
    }

    static func words(_ b: [UInt8]) -> [UInt32] {
        let padded = b + [UInt8](repeating: 0, count: (4 - b.count % 4) % 4)
        return stride(from: 0, to: padded.count, by: 4).map { le32(padded, $0) }
    }

    static func bytes(_ w: [UInt32]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w.count * 4)
        for (i, v) in w.enumerated() { put32(&out, i * 4, v) }
        return out
    }

    /// Map each index of `a` to the index of the same item in `b` (longest common subsequence).
    static func align<T: Equatable>(_ a: [T], _ b: [T]) -> [Int: Int] {
        var pairs: [Int: Int] = [:]
        var lo = 0
        while lo < a.count, lo < b.count, a[lo] == b[lo] { pairs[lo] = lo; lo += 1 }
        var ha = a.count, hb = b.count
        while ha > lo, hb > lo, a[ha - 1] == b[hb - 1] { ha -= 1; hb -= 1; pairs[ha] = hb }
        let m = ha - lo, n = hb - lo
        guard m > 0, n > 0 else { return pairs }
        // dp[i][j] = length of the common subsequence of a[lo+i..<ha] and b[lo+j..<hb]
        var dp = [[Int32]](repeating: [Int32](repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                dp[i][j] = a[lo + i] == b[lo + j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var i = 0, j = 0
        while i < m, j < n {
            if a[lo + i] == b[lo + j] {
                pairs[lo + i] = lo + j; i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }

    /// Apply the word changes base -> theme to target. Returns (result, words not applied).
    public static func mergeWords(base: [UInt8], theme: [UInt8], target: [UInt8]) -> ([UInt8], Int) {
        let bw = words(base), tw = words(theme), nw = words(target)
        var out = nw
        let at = align(bw, nw)
        var lost = 0
        for (i, (old, new)) in zip(bw, tw).enumerated() where old != new {
            if let j = at[i] { out[j] = new } else { lost += 1 }
        }
        lost += abs(tw.count - bw.count)
        return (Array(bytes(out).prefix(target.count)), lost)
    }

    struct Element { var pos, size: Int; var tag: String; var id: Int }

    /// The elements of a View, or nil if the data is not a View.
    static func viewElements(_ d: [UInt8]) -> [Element]? {
        var out: [Element] = []
        var p = 4
        while p + 16 <= d.count {
            let size = Int(le32(d, p)) + 4
            guard size >= 16, p + size <= d.count else { return nil }
            out.append(Element(pos: p, size: size, tag: String(decoding: d[p + 8..<p + 12].reversed(), as: UTF8.self),
                               id: Int(Int16(bitPattern: le16(d, p + 12)))))
            p += size
        }
        return p == d.count ? out : nil
    }

    struct ElementKey: Equatable { var size: Int; var tag: String; var id: Int }

    struct Merger {
        let ids: [Key: Key]

        /// Translate a negative resource ID from base to target.
        func tr(_ type: String, _ value: Int) -> Int {
            guard value < 0, let k = ids[Key(block: "main", type: type, id: value)] else { return value }
            return k.id
        }

        /// The words of one element, with the resource IDs translated.
        func fields(_ d: [UInt8], _ e: Element, tag: String) -> [UInt32] {
            var w = (0..<e.size / 4).map { le32(d, e.pos + 4 * $0) }
            if let type = ThemeImport.elementIDType[tag] {
                let lo = Int(Int16(bitPattern: le16(d, e.pos + 12)))
                w[3] = (w[3] & 0xFFFF_0000) | UInt32(UInt16(truncatingIfNeeded: tr(type, lo)))
            }
            if tag == "Str ", e.size > 88 {
                let hi = Int(Int16(bitPattern: le16(d, e.pos + 86)))
                w[21] = (w[21] & 0x0000_FFFF) | UInt32(UInt16(truncatingIfNeeded: tr("Type", hi))) << 16
            }
            return w
        }

        func view(base: [UInt8], theme: [UInt8], target: [UInt8]) throws -> ([UInt8], Int) {
            guard let be = viewElements(base), let te = viewElements(theme), let ne = viewElements(target) else {
                throw ThemeError("not a View")
            }
            guard be.count == te.count, zip(be, te).allSatisfy({ $0.size == $1.size }) else {
                throw ThemeError("the theme changes the structure of this View")
            }
            let at: [Int: Int]
            if be.map({ "\($0.size) \($0.tag)" }) == ne.map({ "\($0.size) \($0.tag)" }) {
                at = Dictionary(uniqueKeysWithValues: (0..<be.count).map { ($0, $0) })
            } else {
                at = ThemeImport.align(be.map { ElementKey(size: $0.size, tag: $0.tag, id: tr(ThemeImport.elementIDType[$0.tag] ?? "", $0.id)) },
                                       ne.map { ElementKey(size: $0.size, tag: $0.tag, id: $0.id) })
            }
            var out = target
            var lost = 0
            for (i, (b, t)) in zip(be, te).enumerated() {
                let bw = fields(base, b, tag: b.tag), tw = fields(theme, t, tag: t.tag)
                if bw == tw { continue }
                guard let j = at[i] else {
                    lost += zip(bw, tw).filter { $0 != $1 }.count
                    continue
                }
                let r = ne[j].pos
                var nw = (0..<b.size / 4).map { le32(target, r + 4 * $0) }
                for (f, (old, new)) in zip(bw, tw).enumerated() where old != new {
                    if nw[f] == old || (f == 3 && old & 0xFFFF_0000 == new & 0xFFFF_0000 && nw[f] & 0xFFFF == old & 0xFFFF) {
                        nw[f] = new
                    } else {
                        lost += 1
                    }
                }
                for (f, v) in nw.enumerated() { put32(&out, r + 4 * f, v) }
            }
            return (out, lost)
        }
    }

    static func runs(_ pos: Int, _ old: [UInt8], _ new: [UInt8], _ resource: String) -> [ThemeChange] {
        var out: [ThemeChange] = []
        var i = 0
        while i < old.count {
            if old[i] == new[i] { i += 1; continue }
            let start = i
            var end = i
            while i < old.count, i - end < runGap {
                if old[i] != new[i] { end = i + 1 }
                i += 1
            }
            out.append(ThemeChange(resource: resource, offset: pos + start, old: Data(old[start..<end]), new: Data(new[start..<end])))
        }
        return out
    }

    /// A 4-bit grey copy of an RGB565 picture if each pixel is grey (exact to 1/15), else data.
    static func smallerPicture(_ data: [UInt8]) -> [UInt8] {
        guard let pic = Picture.parse(data, at: 0), pic.depth == 16, pic.textureFormat != 0x1444 else { return data }
        let rgba = pic.decode(data)
        for p in stride(from: 0, to: rgba.count, by: 4) {
            let r = Int(rgba[p]), g = Int(rgba[p + 1]), b = Int(rgba[p + 2])
            guard r == g, g == b, abs(r - Int((Double(r) / 17).rounded()) * 17) <= 8 else { return data }
        }
        let bpr = (pic.width + 1) / 2
        var out = [UInt8](repeating: 0, count: 28 + bpr * pic.height)
        out[0] = 4; out[4] = UInt8(bpr & 0xFF); out[5] = UInt8(bpr >> 8); out[6] = 4
        put32(&out, 16, UInt32(pic.height)); put32(&out, 20, UInt32(pic.width)); put32(&out, 24, UInt32(bpr * pic.height))
        guard let grey = Picture.parse(out, at: 0), (try? grey.encode(&out, rgba: rgba)) != nil else { return data }
        return out
    }

    /// Make an iPodFirm theme for `target` from an iPodWizard theme and the firmware that it came from.
    ///
    /// `freeArea` is a range of the target osos for a picture that the theme made larger. The default
    /// is the space after the end of osos (where rsrc starts) to `ososLimit`. To use it, the app
    /// moves rsrc (`FirmwarePartition.makeRoom`).
    public static func make(theme themeFW: FirmwarePartition, base baseFW: FirmwarePartition, target targetFW: FirmwarePartition,
                            name: String, sourceSHA256: String = "", freeArea: Range<Int>? = nil) throws -> ImportedTheme {
        let t = try Image(themeFW), b = try Image(baseFW), n = try Image(targetFW)
        let tLen = themeFW.appleOSLength, bLen = baseFW.appleOSLength
        guard t.osos.prefix(tLen) != b.osos.prefix(bLen) else {
            throw ThemeError("The theme and the base firmware are the same. Select the Apple firmware that the theme came from.")
        }
        let same = t.keys.filter { k in b.res[k].map { $0.0.size == t.res[k]!.0.size } ?? false }.count
        guard Double(same) >= Double(t.keys.count) * 0.9 else {
            throw ThemeError("The base firmware is not the firmware that the theme came from.")
        }
        var theme = ImportedTheme(name: name, source_sha256: sourceSHA256, osos_sha256: sha256(n.osos))
        if t.osos.count == b.osos.count {
            let firstT = t.blocks.map(\.start).min() ?? 0
            let code = zip(t.osos[..<firstT], b.osos[..<firstT]).filter { $0 != $1 }.count
            if code > 0 {
                theme.skipped.append(ThemeSkip(resource: "code", reason: "The theme changes \(code) bytes of program code. The import does not apply program changes."))
            }
        }
        let ids = idMap(b, n)
        let merger = Merger(ids: ids)
        var free: Range<Int>
        if let freeArea {
            free = freeArea
        } else {
            let os = try targetFW.entry("osos"), rs = try targetFW.entry("rsrc")
            free = Int(rs.devOffset - os.devOffset)..<ososLimit
        }

        for key in t.keys.sorted() {
            guard b.res[key] != nil else { continue }
            let old = b.data(key), new = t.data(key)
            if old == new { continue }
            var label = key.label
            guard ["BMap", "View", "Type"].contains(key.type) else {
                theme.skipped.append(ThemeSkip(resource: label, reason: "The import does not change \(key.type.trimmingCharacters(in: .whitespaces)) resources."))
                continue
            }
            guard let nkey = ids[key] else {
                theme.skipped.append(ThemeSkip(resource: label, reason: "The target firmware does not have this resource."))
                continue
            }
            let cur = n.data(nkey), pos = n.pos(nkey)
            label = nkey.label
            var changes: [ThemeChange] = []
            if key.type == "BMap" {
                if new.count == cur.count, new.prefix(28) == cur.prefix(28) {
                    changes = runs(pos, cur, new, label)
                } else if new.count != old.count {
                    let blob = smallerPicture(new)
                    let at = (free.lowerBound + 3) & ~3
                    guard at + blob.count <= free.upperBound else {
                        theme.skipped.append(ThemeSkip(resource: label, reason: "The picture is larger than the free space."))
                        continue
                    }
                    free = (at + blob.count)..<free.upperBound
                    let inside = at < n.osos.count ? Array(n.osos[at..<min(at + blob.count, n.osos.count)]) : []
                    let oldArea = inside + [UInt8](repeating: 0, count: blob.count - inside.count)
                    changes = [ThemeChange(resource: label, offset: at, old: Data(oldArea), new: Data(blob))]
                    let (r, blk) = n.res[nkey]!
                    let entry = Array(n.osos[r.tablePos..<r.tablePos + 12])
                    var newEntry = entry
                    put32(&newEntry, 4, UInt32(at - blk.dataStart))
                    put32(&newEntry, 8, UInt32(blob.count))
                    changes += runs(r.tablePos, entry, newEntry, label)
                } else {
                    theme.skipped.append(ThemeSkip(resource: label, reason: "The picture has a different size or format in the target firmware."))
                    continue
                }
            } else if key.type == "View" {
                let result: [UInt8], lost: Int
                do { (result, lost) = try merger.view(base: old, theme: new, target: cur) } catch {
                    theme.skipped.append(ThemeSkip(resource: label, reason: "The import cannot use this View: \(error.localizedDescription)."))
                    continue
                }
                if lost > 0 { theme.skipped.append(ThemeSkip(resource: label, reason: "\(lost) changed fields do not agree with the target firmware.")) }
                changes = runs(pos, cur, result, label)
            } else {
                let (result, lost) = mergeWords(base: old, theme: new, target: cur)
                if lost > 0 { theme.skipped.append(ThemeSkip(resource: label, reason: "\(lost) changed words do not agree with the target firmware.")) }
                changes = runs(pos, cur, result, label)
            }
            if !changes.isEmpty {
                theme.changes += changes
                theme.imported.append(label)
            }
        }
        return theme
    }
}
