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
// - The resources are matched by block, type and ID. Apple moved some IDs between the
//   versions (1.2.1 View -279 is 1.3 View -277, Type 14034 is 14037), so the import finds them by their contents.
// - BMap: the import copies a picture if the target picture has the same header (format, width and
//   height). A picture that the theme made larger goes into free space after the end of osos.
// - Type: the import changes a word (4 bytes) only where the target has the base value.
// - View: a View is a count and a list of elements (u32 size - 4, u32 flags, tag, u32 ID, ...). The
//   import matches the elements and changes a field only where the target has the base value. It
//   translates the resource IDs in the fields.
// - Other resource types and program code: the import does not apply them.
// - The highlight bar keeps Apple's blue colours (ThemeImport.appleHighlight). The blue bar is easier to see.
// - Edits: the owner can replace a picture of the theme in the app. An edit replaces the theme
//   changes in the same bytes. ImportedTheme.edits keeps the edits apart from the import.

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
    /// Format 2: the hash of the old bytes, in place of the old bytes. The theme
    /// then does not store the bytes that it replaces.
    public var oldSHA256: String?
    /// Bytes to take from the firmware at the build. The file holds zeros there.
    public var copy: [ThemeCopy]?

    enum CodingKeys: String, CodingKey { case resource, offset, old, new, old_sha256, copy }

    public init(resource: String, offset: Int, old: Data, new: Data, oldSHA256: String? = nil) {
        self.resource = resource
        self.offset = offset
        self.old = old
        self.new = new
        self.oldSHA256 = oldSHA256
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resource = try c.decode(String.self, forKey: .resource)
        offset = try c.decode(Int.self, forKey: .offset)
        old = try c.decodeIfPresent(Data.self, forKey: .old) ?? Data()
        new = try c.decode(Data.self, forKey: .new)
        oldSHA256 = try c.decodeIfPresent(String.self, forKey: .old_sha256)
        copy = try c.decodeIfPresent([ThemeCopy].self, forKey: .copy)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(resource, forKey: .resource)
        try c.encode(offset, forKey: .offset)
        try c.encode(new, forKey: .new)
        if let h = oldSHA256, !h.isEmpty, old.isEmpty { try c.encode(h, forKey: .old_sha256) }
        else { try c.encode(old, forKey: .old) }
        try c.encodeIfPresent(copy, forKey: .copy)
    }

    /// The change with the bytes of its `copy` list, taken from osos. A wrong hash stops the build.
    func withCopiedBytes(_ osos: [UInt8]) throws -> ThemeChange {
        guard let copy else { return self }
        var bytes = [UInt8](new)
        for e in copy {
            guard e.source + e.length <= osos.count,
                  e.sha256.isEmpty || ThemeImport.sha256(Array(osos[e.source..<e.source + e.length])) == e.sha256 else {
                throw ThemeError("\(resource): the firmware does not have the expected bytes.")
            }
            bytes.replaceSubrange(e.at..<e.at + e.length, with: osos[e.source..<e.source + e.length])
        }
        var out = self
        out.new = Data(bytes)
        out.copy = nil
        return out
    }
}

/// A part of a theme change that comes from the firmware at the build.
public struct ThemeCopy: Codable, Equatable {
    public var at: Int              // in `new`
    public var length: Int
    public var source: Int          // in osos
    public var sha256: String       // empty: colours that a dark theme changes, with no check
}

extension ThemeChange {
    /// True when the change holds the hash of the old bytes in place of the old
    /// bytes (format 2). The change has no old bytes when its data sits after the
    /// end of osos.
    var isStripped: Bool { old.isEmpty && !(oldSHA256 ?? "").isEmpty }
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
    /// The pictures that the owner replaced in the dark theme.
    public var edits: [ThemeChange] = []

    enum CodingKeys: String, CodingKey { case format, name, source_sha256, osos_sha256, imported, skipped, changes, edits }

    public init(name: String, source_sha256: String, osos_sha256: String) {
        self.name = name
        self.source_sha256 = source_sha256
        self.osos_sha256 = osos_sha256
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        name = try c.decode(String.self, forKey: .name)
        source_sha256 = try c.decode(String.self, forKey: .source_sha256)
        osos_sha256 = try c.decode(String.self, forKey: .osos_sha256)
        imported = try c.decode([String].self, forKey: .imported)
        skipped = try c.decode([ThemeSkip].self, forKey: .skipped)
        changes = try c.decode([ThemeChange].self, forKey: .changes)
        edits = try c.decodeIfPresent([ThemeChange].self, forKey: .edits) ?? []   // not in files from earlier versions
    }

    public static func load(_ url: URL) throws -> ImportedTheme {
        let t = try JSONDecoder().decode(ImportedTheme.self, from: Data(contentsOf: url))
        guard t.format == ThemeImport.format || t.format == ThemeImport.formatStripped else {
            throw ThemeError("This theme file has an unknown format.")
        }
        return t
    }

    public func write(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// Write the theme in format 2: each change holds the hash of the old bytes in
    /// place of the old bytes. The file does not store the bytes that the theme replaces.
    public func writeStripped(to url: URL) throws {
        var out = self
        out.format = ThemeImport.formatStripped
        out.changes = changes.map { c in
            ThemeChange(resource: c.resource, offset: c.offset, old: Data(), new: c.new,
                        oldSHA256: c.old.isEmpty ? "" : (c.oldSHA256 ?? ThemeImport.sha256([UInt8](c.old))))
        }
        out.edits = edits.map { c in
            ThemeChange(resource: c.resource, offset: c.offset, old: Data(), new: c.new,
                        oldSHA256: c.old.isEmpty ? "" : (c.oldSHA256 ?? ThemeImport.sha256([UInt8](c.old))))
        }
        try out.write(to: url)
    }

    /// The layout with its View after the data in osos, and text for a dark theme if `dark`.
    /// The first change is the View, and the second change is the offset and the size in the
    /// table entry. A dark theme makes only the styles of size 18 white.
    public func movedLayout(after osos: [UInt8], dark: Bool = false) -> ImportedTheme {
        guard changes.count == 2 else { return self }
        var out = self
        let delta = max(0, (osos.count + 15) / 16 * 16 - changes[0].offset)
        out.changes[0].offset += delta
        var entry = [UInt8](changes[1].new)
        let value = entry[0..<4].reversed().reduce(0) { $0 << 8 | Int($1) } + delta
        entry.replaceSubrange(0..<4, with: (0..<4).map { UInt8(value >> ($0 * 8) & 0xFF) })
        out.changes[1].new = Data(entry)
        if dark {
            var view = [UInt8](changes[0].new)
            for i in stride(from: 0, to: view.count - 3, by: 1) where view[i..<i + 4].elementsEqual([0, 0, 0xA3, 0x5E]) {
                view[i + 2] = 0x9F
            }
            out.changes[0].new = Data(view)
        }
        return out
    }

    /// Apply the theme to osos. Returns (changes applied, changes not applied because of other edits).
    ///
    /// A theme in format 2 holds no old bytes: the hash of the old bytes stands in
    /// for them. The function takes the old bytes from the firmware again and
    /// checks the hash, through `withOldBytes`.
    @discardableResult
    public func apply(to osos: inout [UInt8], originalSHA256: String) throws -> (applied: Int, conflicts: Int) {
        guard originalSHA256 == osos_sha256 else { throw ThemeError("The theme \"\(name)\" is for a different firmware.") }
        let theme = withOldBytes(osos)
        let changes = try theme.effectiveChanges.map { try $0.withCopiedBytes(osos) }
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

    /// The same theme with the old bytes of every change.
    ///
    /// A theme in format 2 holds the hash of the old bytes in place of the old
    /// bytes. This function takes the old bytes from the firmware and checks
    /// the hash. A change whose bytes do not agree with the hash gets old bytes
    /// that agree with the firmware: the change then counts as a conflict, the
    /// same as in format 1. The function gives back the same value when the
    /// theme already holds the old bytes.
    public func withOldBytes(_ osos: [UInt8]) -> ImportedTheme {
        guard changes.contains(where: { $0.old.isEmpty && !($0.oldSHA256 ?? "").isEmpty }) else { return self }
        var out = self
        out.changes = changes.map { c in
            guard c.old.isEmpty, let h = c.oldSHA256, !h.isEmpty else { return c }
            // The old bytes come from the firmware again. A read past the end of
            // osos gives zeros: apply extends osos with zeros before it compares,
            // so the bytes there are zeros. A change can start after the end of
            // osos (issue 1), so the start of the read is also at most osos.count.
            let hi = c.offset + c.new.count
            var old = osos[min(c.offset, osos.count)..<min(hi, osos.count)].map { $0 }
            let zeroFrom = max(c.offset, osos.count)
            if hi > zeroFrom { old += [UInt8](repeating: 0, count: hi - zeroFrom) }
            if !c.new.isEmpty && ThemeImport.sha256(old) != h {
                // The bytes at the offset are not the old bytes of the change: an
                // edit by the owner sits there, or the change is already applied.
                // The old bytes are not in the file. Set the old bytes to the new
                // bytes with one bit turned over. The sentinel makes the apply step
                // take the same branch as in format 1: done when the firmware
                // already holds the new bytes, a conflict in every other case. The
                // step never writes the change, so the owner's edit stays.
                var sent = [UInt8](c.new)
                sent[0] ^= 0x80
                old = sent
            }
            return ThemeChange(resource: c.resource, offset: c.offset,
                               old: Data(old), new: c.new, oldSHA256: h)
        }
        return out
    }

    /// Replace the pixels of a theme picture. `light` is the osos without the theme. `new` is the
    /// pixel data of the picture at `offset` in the osos with the theme.
    public mutating func setEdit(resource: String, offset: Int, light: [UInt8], new: [UInt8]) {
        let old = (offset..<offset + new.count).map { $0 < light.count ? light[$0] : 0 }
        edits.removeAll { $0.offset == offset }
        edits.append(ThemeChange(resource: resource, offset: offset, old: Data(old), new: Data(new)))
    }

    /// Use the picture of the theme again.
    public mutating func removeEdit(offset: Int) {
        edits.removeAll { $0.offset == offset }
    }

    /// The bytes that the theme adds after the end of osos (`Patcher.maxOSOSSize`): the pictures
    /// that the theme made larger. The Patches pane shows this size.
    public var addedSize: Int {
        let ends = effectiveChanges.filter { $0.offset >= Patcher.maxOSOSSize }.map { $0.offset + $0.new.count }
        return max(0, (ends.max() ?? 0) - Patcher.maxOSOSSize)
    }

    /// The bytes inside osos that the theme changes. They use no new space.
    public var changedSize: Int {
        effectiveChanges.filter { $0.offset < Patcher.maxOSOSSize }.reduce(0) { $0 + $1.new.count }
    }

    /// The changes to apply: without ThemeImport.keepApple, with Apple's highlight colours, and with
    /// the edits of the owner in place of the theme changes in the same bytes.
    public var effectiveChanges: [ThemeChange] {
        var out: [ThemeChange] = []
        for c in changes where ThemeImport.keepApple[c.resource] == nil {   // skip: a theme file from an earlier version
            if edits.contains(where: { c.offset < $0.offset + $0.new.count && $0.offset < c.offset + c.new.count }) { continue }
            let k = Self.keepHighlight(c)
            if k.old != k.new { out.append(k) }
        }
        return out + edits
    }

    /// The change with Apple's highlight colours where the theme changes them.
    static func keepHighlight(_ c: ThemeChange) -> ThemeChange {
        guard c.resource.hasPrefix("View "), c.old.count == c.new.count else { return c }
        let old = [UInt8](c.old)
        var new = [UInt8](c.new)
        var i = (4 - c.offset % 4) % 4
        while i + 4 <= old.count {
            if ThemeImport.appleHighlight.contains(le32(old, i)) { new.replaceSubrange(i..<i + 4, with: old[i..<i + 4]) }
            i += 4
        }
        var out = c
        out.new = Data(new)
        return out
    }
}

public enum ThemeImport {
    public static let format = 1
    /// Format 2 stores, for each change, the SHA-256 of the old bytes in place of
    /// the old bytes. A theme in format 2 holds no byte of the Apple firmware, so
    /// the app can ship it. Both formats apply the same.
    public static let formatStripped = 2
    /// Join two changed runs if fewer bytes than this separate them.
    static let runGap = 16
    /// The IDs of a type move by a small amount between versions.
    static let idShifts = (-8...8).sorted { abs($0) < abs($1) }
    /// The reset code of RetailOS stops if the end of the OS image is after 8 MB (0x800004). A
    /// picture that the theme makes larger goes after the current end of osos, below this limit.
    /// Extended patches (`"load_address": "extended"`) also stay below this limit. The margin below
    /// 8 MB stays empty: 32 KB (the default since 9 October 2026), 64 KB (before) or 16 KB (more
    /// space for patches). The app setting "Firmware layout" selects it (`ososMarginKey` in the user
    /// defaults).
    public static var ososLimit: Int { OSOSMargin.selected.limit }

    /// The key of the margin setting in the user defaults of the app.
    public static let ososMarginKey = "ososMargin"

    /// The empty margin below 8 MB.
    /// The cases are in the order of the size of the margin; the picker shows them in this order.
    public enum OSOSMargin: String, CaseIterable, Identifiable {
        /// 16 KB: the limit 0x7FC000. More space for patches, with a smaller reserve below 8 MB.
        case compact
        /// 32 KB: the limit 0x7F8000 (the default since 9 October 2026).
        case current
        /// 64 KB: the limit 0x7F0000 (before 9 October 2026). A test: the Now Playing art with the
        /// USB host probe (patches/usb-host-probe/FINDINGS.md).
        case previous

        public var id: String { rawValue }
        public var limit: Int {
            switch self {
            case .current: 0x7F8000
            case .previous: 0x7F0000
            case .compact: 0x7FC000
            }
        }
        public var title: String {
            switch self {
            case .current: "32 KB (limit 0x7F8000, default)"
            case .previous: "64 KB (limit 0x7F0000, before 9 October 2026)"
            case .compact: "16 KB (limit 0x7FC000, more space for patches)"
            }
        }

        /// The setting of the app, or `current`.
        public static var selected: OSOSMargin {
            UserDefaults.standard.string(forKey: ososMarginKey).flatMap(OSOSMargin.init(rawValue:)) ?? .current
        }
    }
    /// Resources of the target that keep the Apple version: the progress bar in Now Playing (1.3).
    /// The dark themes make it almost black, so it is not visible.
    public static let keepApple = ["BMap 24342": "Apple's progress bar stays (the theme makes it almost invisible).",
                                   "BMap 24343": "Apple's progress bar stays (the theme makes it almost invisible)."]
    /// The colours of the highlight bar in Apple's Views (element +76 and +80, ABGR). The dark themes
    /// make the bar dark grey. The owner wants the blue bar, because it is easier to see.
    public static let appleHighlight: Set<UInt32> = [0xFFD0_6428, 0xFFE8_9858]
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
    /// Map the resource keys of base to target.
    ///
    /// Apple moved some IDs between the versions (for example Type 14034 in 1.2.1 is 14037 in 1.3).
    /// Pass 1 maps a resource to the same ID if the data is the same, else to the only resource nearby
    /// with the same data. Pass 2 maps each other resource with the shift of the nearest resource of
    /// the same type that pass 1 mapped.
    static func idMap(_ base: Image, _ target: Image) -> [Key: Key] {
        var out: [Key: Key] = [:]
        for key in base.keys {
            let data = base.data(key)
            if target.res[key] != nil, target.data(key) == data { out[key] = key; continue }
            let hits = idShifts.filter { $0 != 0 }.map { Key(block: key.block, type: key.type, id: key.id + $0) }
                .filter { target.res[$0] != nil && target.data($0) == data }
            if hits.count == 1 { out[key] = hits[0] }
        }
        var mapped: [String: [(id: Int, shift: Int)]] = [:]
        for (key, k2) in out { mapped[key.block + "/" + key.type, default: []].append((key.id, k2.id - key.id)) }
        for key in base.keys where out[key] == nil {
            guard let list = mapped[key.block + "/" + key.type],
                  let near = list.min(by: { (abs($0.id - key.id), $0.id) < (abs($1.id - key.id), $1.id) }) else { continue }
            let k2 = Key(block: key.block, type: key.type, id: key.id + near.shift)
            if let t = target.res[k2], target.data(k2) == base.data(key) || t.0.size == base.res[key]!.0.size { out[key] = k2 }
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
            guard value != 0, let k = ids[Key(block: "main", type: type, id: value)] else { return value }
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
            if let why = keepApple[label] {
                theme.skipped.append(ThemeSkip(resource: label, reason: why))
                continue
            }
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
