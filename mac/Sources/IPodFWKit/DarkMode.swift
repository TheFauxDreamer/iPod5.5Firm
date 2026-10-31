import Foundation

// Swift port of src/ipodfw/darkmode.py: the firmware for the appearance "Switch on iPod". It is
// light at the start and has a Dark Mode item in Settings.
//
// RetailOS makes its screens one time, at the start, from the View resources. Thus the dark theme
// cannot change while the iPod runs. The patch patches/dark-mode applies a switch table at the
// start, before the first View is read, if iPod_Control/iTunes/iPodFirmDarkMode contains '1'. The
// Settings item writes that file and restarts the iPod.
//
// The build puts these items after the end of osos (below ThemeImport.ososLimit):
//   the theme data outside osos (for example the background picture: in both modes)
//   the switch table: "IFDM", u32 count N, u32 data offset, N x {u32 address, u32 length}, data
//                     (old XOR new for each change, so the same table switches in both directions)
//   the Settings menu with the Dark Mode item (the resource table entry points to it)
//   the code of the patch (its symbol dark_table is the address of the table)

public enum DarkMode {
    public static let magic: UInt32 = 0x4D44_4649                 // "IFDM"
    static let settingsMenu = ThemeImport.Key(block: "main", type: "Menu", id: 24598)
    static let templateKey: UInt32 = 0x6000_60B7                  // the Sound Check item: an On/Off item
    static let insertAfterKey: UInt32 = 0x6000_6088               // the Clicker item
    public static let darkKey: UInt32 = 0x6000_60E0               // the Dark Mode item (patch: KEY)
    public static let labelID: UInt32 = 0x7E00                    // the label "Dark Mode" (patch: LABEL_ID)
    static let patchAreaEnd = 0x736800                            // the other patches use the area before this address
    /// The setting on the iPod: one byte, '0' (light) or '1' (dark).
    public static let settingFile = "iPod_Control/iTunes/iPodFirmDarkMode"

    public struct Info {
        public var table: (at: Int, length: Int)
        public var menu: (at: Int, length: Int)
        public var patchAt: Int
        /// Changes left out because the owner changed the same bytes.
        public var changesLeftOut: Int
    }

    static func align(_ n: Int, _ a: Int) -> Int { (n + a - 1) / a * a }

    /// Bytes of the Split layout that are different in the two modes.
    public struct LayoutRun {
        var at: Int
        var old: [UInt8]
        var new: [UInt8]
    }

    /// The Split layout for "Switch on iPod", with its View at `end`.
    static func layoutParts(theme: ImportedTheme, layout: ImportedTheme, osos: [UInt8], end: Int) throws
        -> (at: Int, view: [UInt8], entry: ThemeChange, extra: [LayoutRun]) {
        let at = align(end, 16)
        let place = [UInt8](repeating: 0, count: at)
        let moved = layout.movedLayout(after: place)
        let light = [UInt8](try moved.changes[0].withCopiedBytes(osos).new)
        var themed = osos
        try theme.apply(to: &themed, originalSHA256: theme.osos_sha256)
        let dark = [UInt8](try layout.movedLayout(after: place, dark: true).changes[0].withCopiedBytes(themed).new)
        var extra: [LayoutRun] = []
        var i = 0
        while i < light.count {
            var j = i
            while j < light.count && light[j] != dark[j] { j += 1 }
            if j > i { extra.append(LayoutRun(at: at + i, old: Array(light[i..<j]), new: Array(dark[i..<j]))) }
            i = max(j, i + 1)
        }
        return (at, light, moved.changes[1], extra)
    }

    /// The switch table for the changes inside osos, with the rules of `ImportedTheme.apply`: a change
    /// is used if the bytes are the old bytes, and left out if they are already the new bytes (the same
    /// change two times) or other bytes (an edit by the owner).
    public static func switchTable(_ theme: ImportedTheme, osos: [UInt8],
                                   extra: [LayoutRun] = []) -> (table: [UInt8], leftOut: Int) {
        var runs: [UInt8] = [], data: [UInt8] = [], count = 0, leftOut = 0
        var work = osos
        for c in theme.withOldBytes(osos).effectiveChanges where c.offset + c.old.count <= osos.count {
            let cur = work[c.offset..<c.offset + c.old.count]
            guard cur.elementsEqual(c.old) else {
                if !cur.elementsEqual(c.new) { leftOut += 1 }
                continue
            }
            work.replaceSubrange(c.offset..<c.offset + c.new.count, with: c.new)
            var run = [UInt8](repeating: 0, count: 8)
            put32(&run, 0, UInt32(c.offset)); put32(&run, 4, UInt32(c.new.count))
            runs += run
            data += zip(c.old, c.new).map { $0 ^ $1 }
            count += 1
        }
        for e in extra {
            var run = [UInt8](repeating: 0, count: 8)
            put32(&run, 0, UInt32(e.at)); put32(&run, 4, UInt32(e.new.count))
            runs += run
            data += zip(e.old, e.new).map { $0 ^ $1 }
            count += 1
        }
        var head = [UInt8](repeating: 0, count: 12)
        put32(&head, 0, magic); put32(&head, 4, UInt32(count)); put32(&head, 8, UInt32(12 + 8 * count))
        return (head + runs + data, leftOut)
    }

    /// What the patch does at the start (for tests).
    public static func applySwitchTable(_ osos: inout [UInt8], _ table: [UInt8]) {
        let n = Int(le32(table, 4))
        var dataAt = Int(le32(table, 8))
        for i in 0..<n {
            let at = Int(le32(table, 12 + 8 * i)), length = Int(le32(table, 16 + 8 * i))
            for k in 0..<length { osos[at + k] ^= table[dataAt + k] }
            dataAt += length
        }
    }

    /// Menu 24598 with a Dark Mode item after Clicker (a copy of the Sound Check item).
    public static func settingsMenu(_ menu: [UInt8]) throws -> [UInt8] {
        let count = Int(le32(menu, 0))
        let keys = (0..<count).map { le32(menu, 4 + 40 * $0 + 0x1C) }
        guard !keys.contains(darkKey) else { throw ThemeError("The Settings menu already has the Dark Mode item.") }
        guard keys.contains(templateKey), keys.contains(insertAfterKey) else {
            throw ThemeError("The Settings menu is not the menu of firmware 1.3.")
        }
        return try Patcher.insertSettingsItem(menu, key: darkKey, label: labelID, after: insertAfterKey, template: templateKey)
    }

    /// The positions of the items after the theme data (refer to the comment at the top).
    static func layout(themeEnd: Int, table: Int, menu: Int) -> (tableAt: Int, menuAt: Int, patchAt: Int) {
        let tableAt = align(themeEnd, 16)
        let menuAt = align(tableAt + table, 16)
        return (tableAt, menuAt, align(menuAt + menu, 16))
    }

    /// The end of the theme data after the end of osos, or `patchAreaEnd` if there is none.
    static func themeEnd(_ theme: ImportedTheme, osos: [UInt8]) -> Int {
        theme.withOldBytes(osos).effectiveChanges.filter { $0.offset + $0.old.count > osos.count }.map { $0.offset + $0.new.count }
            .reduce(patchAreaEnd, max)
    }

    /// Menu 24598 with the Dark Mode item, and its resource table entry.
    static func settingsMenu(partition: FirmwarePartition, osos: [UInt8]) throws -> ([UInt8], Resource, ResourceBlock) {
        let image = try ThemeImport.Image(partition)
        guard let entry = image.res[settingsMenu] else { throw ThemeError("The firmware has no Settings menu (Menu 24598).") }
        let (res, block) = entry
        return (try settingsMenu(Array(osos[block.abs(res)..<block.abs(res) + Int(res.size)])), res, block)
    }

    /// The bytes that "Switch on iPod" adds after the end of osos (`patchAreaEnd`): the theme data, the
    /// switch table, the Settings menu and the code of the patch (`codeSize`, the `size` in patch.json).
    /// The value is the same as the layout of `build`. The Patches pane shows it.
    public static func addedSize(partition: FirmwarePartition, osos: [UInt8], theme: ImportedTheme, codeSize: Int,
                                 layout splitLayout: ImportedTheme? = nil) throws -> Int {
        let menu = try settingsMenu(partition: partition, osos: osos).0
        var end = themeEnd(theme, osos: osos)
        var extra: [LayoutRun] = []
        if let splitLayout {
            let parts = try layoutParts(theme: theme, layout: splitLayout, osos: osos, end: end)
            end = parts.at + parts.view.count
            extra = parts.extra
        }
        let at = layout(themeEnd: end, table: switchTable(theme, osos: osos, extra: extra).table.count, menu: menu.count)
        return at.patchAt + codeSize - patchAreaEnd
    }

    /// The osos for "Switch on iPod". `osos` can have edits of the owner; `partition` gives its resources.
    /// With `layout`, both modes have the Split main menu.
    public static func build(partition: FirmwarePartition, osos: [UInt8], theme: ImportedTheme, patch: PatchInfo,
                             originalSHA256: String, layout splitLayout: ImportedTheme? = nil) throws -> ([UInt8], Info) {
        guard originalSHA256 == theme.osos_sha256 else { throw ThemeError("The theme \"\(theme.name)\" is for a different firmware.") }
        let theme = theme.withOldBytes(osos)
        var out = osos
        // 1. theme data outside osos: in both modes
        for c in theme.effectiveChanges where c.offset + c.old.count > osos.count {
            if out.count < c.offset + c.new.count { out += [UInt8](repeating: 0, count: c.offset + c.new.count - out.count) }
            out.replaceSubrange(c.offset..<c.offset + c.new.count, with: c.new)
        }
        // The layout: in both modes. The switch table changes only its colours and text styles.
        var end = themeEnd(theme, osos: osos)
        var extra: [LayoutRun] = []
        if let splitLayout {
            let parts = try layoutParts(theme: theme, layout: splitLayout, osos: osos, end: end)
            if out.count < parts.at + parts.view.count {
                out += [UInt8](repeating: 0, count: parts.at + parts.view.count - out.count)
            }
            out.replaceSubrange(parts.at..<parts.at + parts.view.count, with: parts.view)
            out.replaceSubrange(parts.entry.offset..<parts.entry.offset + parts.entry.new.count, with: parts.entry.new)
            end = parts.at + parts.view.count
            extra = parts.extra
        }
        // 2. the switch table and 3. the Settings menu
        let (table, leftOut) = switchTable(theme, osos: osos, extra: extra)
        let (menu, res, block) = try settingsMenu(partition: partition, osos: osos)
        let (tableAt, menuAt, patchAt) = layout(themeEnd: end, table: table.count, menu: menu.count)
        // 4. the patch, then the table and the menu
        out = try Patcher.apply(patch, to: out, originalSHA256: originalSHA256, loadAddress: UInt32(patchAt),
                                symbols: ["dark_table": UInt32(tableAt)], maxSize: ThemeImport.ososLimit)
        guard out[tableAt..<patchAt].allSatisfy({ $0 == 0 }) else { throw ThemeError("The space for the switch table is not empty.") }
        out.replaceSubrange(tableAt..<tableAt + table.count, with: table)
        out.replaceSubrange(menuAt..<menuAt + menu.count, with: menu)
        put32(&out, res.tablePos + 4, UInt32(menuAt - block.dataStart))
        put32(&out, res.tablePos + 8, UInt32(menu.count))
        return (out, Info(table: (tableAt, table.count), menu: (menuAt, menu.count), patchAt: patchAt, changesLeftOut: leftOut))
    }
}
