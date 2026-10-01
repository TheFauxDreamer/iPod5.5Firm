import Foundation

// Swift port of src/ipodfw/resources.py: resource blocks inside osos
// (format from iPodWizard firmware.h), and string re-packing.

public struct ResourceError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Resource: Equatable {
    public var type: String       // readable, e.g. "BMap", "Str "
    public var id: Int16
    public var offset: UInt32     // relative to block data start
    public var size: UInt32
    public var tablePos: Int      // absolute position of the 12-byte table entry in osos
}

public struct ResourceSection: Equatable {
    public var type: String
    public var count: Int
}

public struct ResourceBlock: Identifiable, Equatable {
    public var id: Int { index }
    public var index: Int
    public var start: Int
    public var tablesLen: Int
    public var sections: [ResourceSection]
    public var resources: [Resource]

    public var dataStart: Int { start + tablesLen }
    public func ofType(_ t: String) -> [Resource] { resources.filter { $0.type == t } }
    public func abs(_ r: Resource) -> Int { dataStart + Int(r.offset) }
}

let knownTypes: Set<String> = [" rtS", "paMB", "uneM", "epyT", "weiV", "dmCT", "enoN", "mTDL", "stiB"]

func rawTag(_ d: [UInt8], _ o: Int) -> String { String(decoding: d[o..<o + 4], as: UTF8.self) }

public enum Resources {
    public static func scan(_ osos: [UInt8], limit: Int? = nil) -> [ResourceBlock] {
        let end = min(limit ?? osos.count, osos.count)
        var blocks: [ResourceBlock] = []
        var i = 0
        while i + 28 <= end {
            if le32(osos, i) == 3, let b = tryBlock(osos, i, end: end) {
                var b = b
                b.index = blocks.count
                blocks.append(b)
                i = b.dataStart
                i += (4 - i % 4) % 4
                continue
            }
            i += 4
        }
        return blocks
    }

    static func tryBlock(_ d: [UInt8], _ i: Int, end: Int) -> ResourceBlock? {
        let tablesLen = Int(le32(d, i + 4)), nsec = Int(le32(d, i + 8))
        guard tablesLen > 0, tablesLen < 0xFFFF, nsec > 0, nsec < 50, i + 12 + nsec * 16 <= end else { return nil }
        var secs: [(String, Int, Int)] = []
        for k in 0..<nsec {
            let p = i + 12 + k * 16
            let raw = rawTag(d, p)
            guard knownTypes.contains(raw) else { return nil }
            secs.append((raw, Int(le32(d, p + 4)), Int(le32(d, p + 12))))
        }
        let total = secs.reduce(0) { $0 + $1.1 }
        guard 12 + nsec * 16 + total * 12 == tablesLen else { return nil }
        var block = ResourceBlock(index: 0, start: i, tablesLen: tablesLen,
                                  sections: secs.map { ResourceSection(type: String($0.0.reversed()), count: $0.1) },
                                  resources: [])
        for (raw, count, tableStart) in secs {
            for x in 0..<count {
                let pos = i + tableStart + x * 12
                guard pos + 12 <= d.count else { return nil }
                let r = Resource(type: String(raw.reversed()), id: Int16(bitPattern: le16(d, pos)),
                                 offset: le32(d, pos + 4), size: le32(d, pos + 8), tablePos: pos)
                guard block.dataStart + Int(r.offset) + Int(r.size) <= d.count else { return nil }
                block.resources.append(r)
            }
        }
        return block
    }

    public static func mainBlock(_ blocks: [ResourceBlock]) throws -> ResourceBlock {
        guard let b = blocks.first(where: { !$0.ofType("BMap").isEmpty }) else {
            throw ResourceError("No picture (BMap) resource block found.")
        }
        return b
    }

    // MARK: strings

    /// Stable keys for a block's strings: the id, or "id#n" for repeats (same as the Python tool).
    public static func stringKeys(_ block: ResourceBlock) -> [(key: String, res: Resource)] {
        var seen: [Int16: Int] = [:]
        return block.ofType("Str ").map { r in
            let n = seen[r.id, default: 0]
            seen[r.id] = n + 1
            return (n == 0 ? String(r.id) : "\(r.id)#\(n)", r)
        }
    }

    static func rawString(_ osos: [UInt8], _ block: ResourceBlock, _ r: Resource) -> [UInt8] {
        let a = block.abs(r)
        var raw = Array(osos[a..<a + Int(r.size)])
        while raw.last == 0 { raw.removeLast() }
        return raw
    }

    public static func readStrings(_ osos: [UInt8], _ block: ResourceBlock) -> [(key: String, value: String)] {
        stringKeys(block).map { ($0.key, String(decoding: rawString(osos, block, $0.res), as: UTF8.self)) }
    }

    /// Bytes the block's strings would need with `values`, and the bytes available.
    public static func stringBudget(_ osos: [UInt8], _ block: ResourceBlock, _ values: [String: String]) -> (used: Int, available: Int) {
        let keyed = stringKeys(block)
        guard !keyed.isEmpty else { return (0, 0) }
        let spanStart = keyed.map { Int($0.res.offset) }.min()!
        let spanEnd = keyed.map { Int($0.res.offset + $0.res.size) }.max()!
        var cursor = spanStart, lastEnd = spanStart
        for (key, r) in keyed.sorted(by: { $0.res.offset < $1.res.offset }) {
            let n = encoded(osos, block, key, r, values).count
            lastEnd = cursor + n
            cursor = (cursor + n + 3) & ~3
        }
        return (lastEnd - spanStart, spanEnd - spanStart)
    }

    static func encoded(_ osos: [UInt8], _ block: ResourceBlock, _ key: String, _ r: Resource, _ values: [String: String]) -> [UInt8] {
        let raw = rawString(osos, block, r)
        if let v = values[key], v != String(decoding: raw, as: UTF8.self) { return Array(v.utf8) + [0] }
        return raw + [0]   // unchanged: keep the original bytes exactly
    }

    /// Re-pack a block's strings inside the span they already occupy (as iPodWizard does).
    @discardableResult
    public static func writeStrings(_ osos: inout [UInt8], _ block: inout ResourceBlock, _ values: [String: String]) throws -> Bool {
        let keyed = stringKeys(block)
        let known = Set(keyed.map(\.key))
        if let bad = values.keys.first(where: { !known.contains($0) }) {
            throw ResourceError("Unknown string id \(bad) in block \(block.index).")
        }
        let changed = keyed.contains { k in
            values[k.key].map { $0 != String(decoding: rawString(osos, block, k.res), as: UTF8.self) } ?? false
        }
        guard changed else { return false }

        let spanStart = keyed.map { Int($0.res.offset) }.min()!
        let spanEnd = keyed.map { Int($0.res.offset + $0.res.size) }.max()!
        for r in block.resources where r.type != "Str " && Int(r.offset) < spanEnd && Int(r.offset + r.size) > spanStart {
            throw ResourceError("\(r.type) resource \(r.id) overlaps the string area; refusing to re-pack.")
        }
        var layout: [(Resource, Int, [UInt8])] = []
        var cursor = spanStart
        for (key, r) in keyed.sorted(by: { $0.res.offset < $1.res.offset }) {
            let raw = encoded(osos, block, key, r, values)
            layout.append((r, cursor, raw))
            cursor = (cursor + raw.count + 3) & ~3
        }
        let usedEnd = layout.last!.1 + layout.last!.2.count
        guard usedEnd <= spanEnd else {
            throw ResourceError("Strings in this language need \(usedEnd - spanStart) bytes but only \(spanEnd - spanStart) are available (\(usedEnd - spanEnd) too many).")
        }
        let base = block.dataStart
        osos.replaceSubrange(base + spanStart..<base + spanEnd, with: [UInt8](repeating: 0, count: spanEnd - spanStart))
        for (r, off, raw) in layout {
            osos.replaceSubrange(base + off..<base + off + raw.count, with: raw)
            put32(&osos, r.tablePos + 4, UInt32(off))
            put32(&osos, r.tablePos + 8, UInt32(raw.count))
            if let i = block.resources.firstIndex(of: r) {
                block.resources[i].offset = UInt32(off)
                block.resources[i].size = UInt32(raw.count)
            }
        }
        return true
    }
}
