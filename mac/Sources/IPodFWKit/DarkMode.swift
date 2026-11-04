import Foundation

// Swift port of src/ipodfw/darkmode.py: the firmware with switches on the iPod. With the appearance
// "Switch on iPod", it is light at the start and has a Dark Mode item in Settings. With the layout
// "Switch on iPod", it has the Split main menu and a Split View item in Settings.
//
// RetailOS makes its screens one time, at the start, from the View resources. Thus the dark theme
// cannot change while the iPod runs. The patch patches/dark-mode applies a switch table at the
// start, before the first View is read, if iPod_Control/iTunes/iPodFirmDarkMode contains '1'. The
// Settings item writes that file and restarts the iPod.
//
// The build puts these items after the end of osos (below ThemeImport.ososLimit):
//   the theme data outside osos (for example the background picture: in both modes)
//   the Split View, if the layout is Split
//   the dark switch table: "IFD2" (DarkTable.swift: colour maps and palettes of the light pictures), or
//                     "IFDM" if that is smaller: u32 count N, u32 data offset, N x {u32 address,
//                     u32 length}, data (old XOR new for each change)
//   the layout switch table, in the same format (one run: the table entry of View 24430)
//   the Settings menu with the items (the resource table entry points to it)
//   the code of the patch (its symbols dark_table and layout_table are the addresses of the tables)
// A switch that is off has a table with no changes.

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
    public static let layoutKey: UInt32 = 0x6000_7E15             // the Split View item (patch: LAYOUT_KEY)
    public static let layoutLabelID: UInt32 = 0x7E14              // the label "Split View" (patch: LAYOUT_LABEL)
    /// The layout setting on the iPod: one byte, '0' (stock) or '1' (Split). No file: Split.
    public static let layoutSettingFile = "iPod_Control/iTunes/iPodFirmLayout"

    public struct Info {
        public var table: (at: Int, length: Int)
        public var layoutTable: (at: Int, length: Int)
        public var menu: (at: Int, length: Int)
        public var patchAt: Int
        /// Changes left out because the owner changed the same bytes.
        public var changesLeftOut: Int
        /// The dark table in the image (IFD2 or IFDM), and the IFDM table. After other patches, check the
        /// result with `DarkTable.check`.
        public var darkTable: [UInt8] = []
        public var ifdmTable: [UInt8] = []
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

    /// The IFD2 table for `light` (the image before the patch), or `ifdm` if IFD2 is not smaller.
    static func smallerTable(light: [UInt8], ifdm: [UInt8], partition: FirmwarePartition) throws -> [UInt8] {
        let image = try ThemeImport.Image(partition)
        var dark = light
        applySwitchTable(&dark, ifdm)
        let positions = image.res.filter { $0.key.type == "BMap" }.map { image.pos($0.key) }
        let table = try DarkTable.encode(light: light, dark: dark,
                                         pictures: DarkTable.pictureRanges(light, positions: positions))
        return table.count < ifdm.count ? table : ifdm
    }

    /// What the patch does at the start with an IFDM table (for tests).
    public static func applySwitchTable(_ osos: inout [UInt8], _ table: [UInt8]) {
        let n = Int(le32(table, 4))
        var dataAt = Int(le32(table, 8))
        for i in 0..<n {
            let at = Int(le32(table, 12 + 8 * i)), length = Int(le32(table, 16 + 8 * i))
            for k in 0..<length { osos[at + k] ^= table[dataAt + k] }
            dataAt += length
        }
    }

    /// Menu 24598 with a Dark Mode item after Clicker (a copy of the Sound Check item) if `dark`, and a
    /// Split View item after it if `layout`.
    public static func settingsMenu(_ menu: [UInt8], dark: Bool = true, layout: Bool = false) throws -> [UInt8] {
        let count = Int(le32(menu, 0))
        let keys = (0..<count).map { le32(menu, 4 + 40 * $0 + 0x1C) }
        guard !keys.contains(darkKey), !keys.contains(layoutKey) else {
            throw ThemeError("The Settings menu already has the Dark Mode item or the Split View item.")
        }
        guard keys.contains(templateKey), keys.contains(insertAfterKey) else {
            throw ThemeError("The Settings menu is not the menu of firmware 1.3.")
        }
        var out = menu
        if dark {
            out = try Patcher.insertSettingsItem(out, key: darkKey, label: labelID, after: insertAfterKey, template: templateKey)
        }
        if layout {
            out = try Patcher.insertSettingsItem(out, key: layoutKey, label: layoutLabelID,
                                                 after: dark ? darkKey : insertAfterKey, template: templateKey)
        }
        return out
    }

    /// A switch table with no changes. The patch reads the header and does nothing.
    static var emptyTable: [UInt8] {
        var t = [UInt8](repeating: 0, count: 12)
        put32(&t, 0, magic); put32(&t, 8, 12)
        return t
    }

    /// The layout switch table: one run of the 8 bytes (offset and size) of the table entry of View 24430,
    /// with the Split entry XOR the stock entry.
    static func layoutTable(entryAt: Int, stock: [UInt8], split: [UInt8]) -> [UInt8] {
        var t = [UInt8](repeating: 0, count: 20)
        put32(&t, 0, magic); put32(&t, 4, 1); put32(&t, 8, 20); put32(&t, 12, UInt32(entryAt)); put32(&t, 16, 8)
        return t + zip(stock, split).map { $0 ^ $1 }
    }

    /// The end of the theme data after the end of osos, or `patchAreaEnd` if there is none.
    static func themeEnd(_ theme: ImportedTheme, osos: [UInt8]) -> Int {
        theme.withOldBytes(osos).effectiveChanges.filter { $0.offset + $0.old.count > osos.count }.map { $0.offset + $0.new.count }
            .reduce(patchAreaEnd, max)
    }

    /// Menu 24598 with the items of the switches, and its resource table entry.
    static func settingsMenu(partition: FirmwarePartition, osos: [UInt8], dark: Bool = true,
                             layout: Bool = false) throws -> ([UInt8], Resource, ResourceBlock) {
        let image = try ThemeImport.Image(partition)
        guard let entry = image.res[settingsMenu] else { throw ThemeError("The firmware has no Settings menu (Menu 24598).") }
        let (res, block) = entry
        return (try settingsMenu(Array(osos[block.abs(res)..<block.abs(res) + Int(res.size)]), dark: dark, layout: layout), res, block)
    }

    /// The parts of a build with switches, before the patch: the osos with the theme and the layout, the
    /// end of the data, the 2 switch tables and the Settings menu.
    struct Parts {
        var out: [UInt8]
        var end: Int
        var darkTable: [UInt8]
        var ifdmTable: [UInt8]
        var layoutTable: [UInt8]
        var leftOut: Int
        var menu: [UInt8]
        var res: Resource
        var block: ResourceBlock

        /// The positions after the data: the dark table, the layout table, the Settings menu and the patch.
        var positions: (dark: Int, layout: Int, menu: Int, patch: Int) {
            let dark = DarkMode.align(end, 16)
            let layout = DarkMode.align(dark + darkTable.count, 16)
            let menuAt = DarkMode.align(layout + layoutTable.count, 16)
            return (dark, layout, menuAt, DarkMode.align(menuAt + menu.count, 16))
        }
    }

    /// The parts for the appearance and the layout:
    /// - `darkSwitch`: light at the start, with a Dark Mode item. `theme` must not be nil.
    /// - `theme` without `darkSwitch`: always dark.
    /// - no `theme`: always light.
    /// With `layout`, the main menu is Split. With `layoutSwitch` also, a Split View item changes it back to stock.
    static func parts(partition: FirmwarePartition, osos: [UInt8], theme: ImportedTheme?, darkSwitch: Bool,
                      originalSHA256: String, layout splitLayout: ImportedTheme?, layoutSwitch: Bool) throws -> Parts {
        if let theme, originalSHA256 != theme.osos_sha256 {
            throw ThemeError("The theme \"\(theme.name)\" is for a different firmware.")
        }
        if darkSwitch && theme == nil { throw ThemeError("Dark Mode on the iPod needs a dark theme.") }
        var out = osos
        var end = patchAreaEnd
        var extra: [LayoutRun] = []
        if darkSwitch, let theme {
            // The theme data outside osos: in both modes.
            for c in theme.withOldBytes(osos).effectiveChanges where c.offset + c.old.count > osos.count {
                if out.count < c.offset + c.new.count { out += [UInt8](repeating: 0, count: c.offset + c.new.count - out.count) }
                out.replaceSubrange(c.offset..<c.offset + c.new.count, with: c.new)
            }
            end = themeEnd(theme, osos: osos)
        } else if let theme {
            try theme.apply(to: &out, originalSHA256: originalSHA256)
            end = max(end, out.count)
        }
        var layoutTable = emptyTable
        if let splitLayout {
            // The layout: in both modes. The dark table changes only its colours and text styles.
            let at: Int, view: [UInt8], entry: ThemeChange
            if darkSwitch, let theme {
                let p = try layoutParts(theme: theme, layout: splitLayout, osos: osos, end: end)
                (at, view, entry, extra) = (p.at, p.view, p.entry, p.extra)
            } else {
                let moved = splitLayout.movedLayout(after: [UInt8](repeating: 0, count: end), dark: theme != nil)
                at = moved.changes[0].offset
                view = [UInt8](try moved.changes[0].withCopiedBytes(out).new)
                entry = moved.changes[1]
            }
            if out.count < at + view.count { out += [UInt8](repeating: 0, count: at + view.count - out.count) }
            out.replaceSubrange(at..<at + view.count, with: view)
            let stockEntry = Array(out[entry.offset..<entry.offset + entry.new.count])
            out.replaceSubrange(entry.offset..<entry.offset + entry.new.count, with: entry.new)
            end = at + view.count
            if layoutSwitch { layoutTable = Self.layoutTable(entryAt: entry.offset, stock: stockEntry, split: [UInt8](entry.new)) }
        }
        var darkTable = emptyTable, leftOut = 0
        if darkSwitch, let theme { (darkTable, leftOut) = switchTable(theme, osos: osos, extra: extra) }
        let ifdm = darkTable
        if darkSwitch { darkTable = try smallerTable(light: out, ifdm: ifdm, partition: partition) }
        let (menu, res, block) = try settingsMenu(partition: partition, osos: osos, dark: darkSwitch,
                                                  layout: layoutSwitch && splitLayout != nil)
        return Parts(out: out, end: end, darkTable: darkTable, ifdmTable: ifdm, layoutTable: layoutTable, leftOut: leftOut,
                     menu: menu, res: res, block: block)
    }

    /// The bytes that the switches add after the end of osos (`patchAreaEnd`): the theme data, the
    /// Split View, the switch tables, the Settings menu and the code of the patch (`codeSize`, the `size`
    /// in patch.json). The value is the same as the layout of `build`. The Patches pane shows it.
    public static func addedSize(partition: FirmwarePartition, osos: [UInt8], theme: ImportedTheme?, darkSwitch: Bool = true,
                                 codeSize: Int, layout splitLayout: ImportedTheme? = nil, layoutSwitch: Bool = false) throws -> Int {
        let p = try parts(partition: partition, osos: osos, theme: theme, darkSwitch: darkSwitch,
                          originalSHA256: theme?.osos_sha256 ?? ThemeImport.sha256(osos), layout: splitLayout, layoutSwitch: layoutSwitch)
        return p.positions.patch + codeSize - patchAreaEnd
    }

    /// The osos with the switches. `osos` can have edits of the owner; `partition` gives its resources.
    /// The defaults give "Switch on iPod" for the appearance: light at the start, with a Dark Mode item.
    /// With `layout`, both modes have the Split main menu.
    public static func build(partition: FirmwarePartition, osos: [UInt8], theme: ImportedTheme?, darkSwitch: Bool = true,
                             patch: PatchInfo, originalSHA256: String, layout splitLayout: ImportedTheme? = nil,
                             layoutSwitch: Bool = false) throws -> ([UInt8], Info) {
        let p = try parts(partition: partition, osos: osos, theme: theme, darkSwitch: darkSwitch,
                          originalSHA256: originalSHA256, layout: splitLayout, layoutSwitch: layoutSwitch)
        let at = p.positions
        // The patch, then the tables and the menu.
        var out = try Patcher.apply(patch, to: p.out, originalSHA256: originalSHA256, loadAddress: UInt32(at.patch),
                                    symbols: ["dark_table": UInt32(at.dark), "layout_table": UInt32(at.layout)],
                                    maxSize: ThemeImport.ososLimit)
        guard out[at.dark..<at.patch].allSatisfy({ $0 == 0 }) else { throw ThemeError("The space for the switch table is not empty.") }
        out.replaceSubrange(at.dark..<at.dark + p.darkTable.count, with: p.darkTable)
        out.replaceSubrange(at.layout..<at.layout + p.layoutTable.count, with: p.layoutTable)
        out.replaceSubrange(at.menu..<at.menu + p.menu.count, with: p.menu)
        put32(&out, p.res.tablePos + 4, UInt32(at.menu - p.block.dataStart))
        put32(&out, p.res.tablePos + 8, UInt32(p.menu.count))
        try DarkTable.check(out, ifdm: p.ifdmTable, table: p.darkTable)
        return (out, Info(table: (at.dark, p.darkTable.count), layoutTable: (at.layout, p.layoutTable.count),
                          menu: (at.menu, p.menu.count), patchAt: at.patch, changesLeftOut: p.leftOut,
                          darkTable: p.darkTable, ifdmTable: p.ifdmTable))
    }
}
