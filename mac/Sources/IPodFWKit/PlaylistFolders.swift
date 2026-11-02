import CoreGraphics
import Foundation

/// The playlist folders of the playlist-folders patch: the file iPod_Control/iTunes/iPodFirmPlaylistFolders.
/// The format is in patches/playlist-folders/playlist_folders.c. All values are little-endian and
/// each part starts at a multiple of 4 bytes:
///   "IFPF", u16 version (1), u16 flags (bit 0: alphabetical, bit 1: no folder icons, bit 2: custom order),
///   u16 folder count, u16 0
///   each folder: u16 colour (RGB565), u16 name units, u16 member count, u16 0,
///                the name (UTF-16, padded to 4 bytes), the members (u64 persistent IDs)
///   only with bit 2: u16 item count, u16 0, then the top list (u64 persistent IDs, or the folder index
///                with the high word 0xffffffff)
public struct PlaylistFolders: Equatable {
    public struct Folder: Identifiable, Equatable {
        public var id = UUID()
        public var name: String
        public var colour: UInt16
        /// The persistent IDs of the playlists in the folder (mhyp +0x1c).
        public var members: [UInt64]

        public init(name: String, colour: UInt16 = PlaylistFolders.defaultColour, members: [UInt64] = []) {
            self.name = name
            self.colour = colour
            self.members = members
        }

        public static func == (a: Folder, b: Folder) -> Bool {
            a.name == b.name && a.colour == b.colour && a.members == b.members
        }
    }

    public var folders: [Folder] = []
    /// true: the folders are in alphabetical order with the playlists. false: the folders come first.
    public var alphabetical = false
    /// true: each folder row shows the folder icon. The album-art patch draws the icon.
    public var folderIcons = true
    /// true: the patch shows `order`, and the playlists of a folder in the order of `members`.
    public var customOrder = false
    /// The top list for `customOrder`. `completedOrder` gives the full list.
    public var order: [OrderItem] = []

    /// One row of the top list. A folder item holds the `id` of the folder, because a folder can move.
    public enum OrderItem: Hashable {
        case playlist(UInt64)
        case folder(UUID)
    }

    /// The choice "Order" in the app.
    public enum Position: Hashable { case foldersFirst, alphabetical, custom }

    public var position: Position {
        get { customOrder ? .custom : alphabetical ? .alphabetical : .foldersFirst }
        set {
            customOrder = newValue == .custom
            alphabetical = newValue == .alphabetical
        }
    }

    /// Two values are equal if they give the same file. The `id` of a folder is not in the file.
    public static func == (a: PlaylistFolders, b: PlaylistFolders) -> Bool { a.encode() == b.encode() }

    public static let fileName = "iPodFirmPlaylistFolders"
    public static let path = "iPod_Control/iTunes/" + fileName
    /// The limits of the patch (MAX_FOLDERS, NAME_MAX, FILE_MAX in playlist_folders.c).
    public static let maxFolders = 64
    public static let maxNameLength = 63
    public static let maxFileSize = 0x10000
    /// Apple blue.
    public static let defaultColour: UInt16 = rgb565(red: 0x1a, green: 0x6f, blue: 0xe0)

    public init(folders: [Folder] = [], alphabetical: Bool = false, folderIcons: Bool = true, customOrder: Bool = false) {
        self.folders = folders
        self.alphabetical = alphabetical
        self.folderIcons = folderIcons
        self.customOrder = customOrder
    }

    // MARK: the file

    public func encode() -> [UInt8] {
        var b = [UInt8]("IFPF".utf8)
        func u16(_ v: Int) { b += [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        u16(1); u16((alphabetical ? 1 : 0) | (folderIcons ? 0 : 2) | (customOrder ? 4 : 0)); u16(folders.count); u16(0)
        for f in folders {
            let units = Array(f.name.utf16)
            u16(Int(f.colour)); u16(units.count); u16(f.members.count); u16(0)
            for u in units { u16(Int(u)) }
            if units.count % 2 == 1 { u16(0) }
            for id in f.members {
                for i in 0..<8 { b.append(UInt8(id >> (8 * UInt64(i)) & 0xFF)) }
            }
        }
        if customOrder {
            let items: [UInt64] = order.compactMap {
                switch $0 {
                case .playlist(let id): return id
                case .folder(let id): return folders.firstIndex { $0.id == id }.map { UInt64(0xFFFF_FFFF) << 32 | UInt64($0) }
                }
            }
            u16(items.count); u16(0)
            for id in items {
                for i in 0..<8 { b.append(UInt8(id >> (8 * UInt64(i)) & 0xFF)) }
            }
        }
        return b
    }

    /// The folders of a file, or nil if the file is not a folder file.
    public static func decode(_ b: [UInt8]) -> PlaylistFolders? {
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        guard b.count >= 12, Array(b[0..<4]) == Array("IFPF".utf8), u16(4) == 1 else { return nil }
        var out = PlaylistFolders(alphabetical: u16(6) & 1 != 0, folderIcons: u16(6) & 2 == 0, customOrder: u16(6) & 4 != 0)
        var at = 12
        for _ in 0..<u16(8) {
            guard at + 8 <= b.count else { return nil }
            let colour = UInt16(u16(at)), units = u16(at + 2), count = u16(at + 4)
            let nameBytes = (units * 2 + 3) & ~3
            guard at + 8 + nameBytes + count * 8 <= b.count else { return nil }
            let name = String(decoding: (0..<units).map { UInt16(u16(at + 8 + 2 * $0)) }, as: UTF16.self)
            let start = at + 8 + nameBytes
            let members = (0..<count).map { m in
                (0..<8).reduce(UInt64(0)) { $0 | UInt64(b[start + 8 * m + $1]) << (8 * UInt64($1)) }
            }
            out.folders.append(Folder(name: name, colour: colour, members: members))
            at = start + count * 8
        }
        if out.customOrder {
            guard at + 4 <= b.count, at + 4 + u16(at) * 8 <= b.count else { return nil }
            for i in 0..<u16(at) {
                let id = (0..<8).reduce(UInt64(0)) { $0 | UInt64(b[at + 4 + 8 * i + $1]) << (8 * UInt64($1)) }
                if id >> 32 != 0xFFFF_FFFF {
                    out.order.append(.playlist(id))
                } else if out.folders.indices.contains(Int(id & 0xFFFF_FFFF)) {
                    out.order.append(.folder(out.folders[Int(id & 0xFFFF_FFFF)].id))
                }
            }
        }
        return out
    }

    /// The folders on a mounted iPod. An iPod without the file has no folders.
    public static func read(volume: URL) -> PlaylistFolders {
        guard let data = try? Data(contentsOf: volume.appendingPathComponent(path)) else { return PlaylistFolders() }
        return decode([UInt8](data)) ?? PlaylistFolders()
    }

    /// Write the file on a mounted iPod. A file with no folders and no custom order is removed.
    public func write(volume: URL) throws {
        let url = volume.appendingPathComponent(Self.path)
        if folders.isEmpty && !customOrder {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(encode()).write(to: url, options: .atomic)
    }

    // MARK: changes

    /// The folder that holds the playlist, or nil.
    public func folderIndex(of playlist: UInt64) -> Int? {
        folders.firstIndex { $0.members.contains(playlist) }
    }

    /// Put a playlist into folder `index`, or into no folder if `index` is nil. A playlist is in one folder only.
    public mutating func move(_ playlist: UInt64, to index: Int?) {
        for i in folders.indices { folders[i].members.removeAll { $0 == playlist } }
        if let index, folders.indices.contains(index) { folders[index].members.append(playlist) }
    }

    /// Remove the members that are not playlists of the iPod.
    public mutating func removeMissing(_ playlists: Set<UInt64>) {
        for i in folders.indices { folders[i].members.removeAll { !playlists.contains($0) } }
    }

    /// `order` with each folder and each playlist outside a folder one time. A removed item goes.
    /// A new item goes at the end: first the folders, and then the playlists. The patch does the same.
    public func completedOrder(playlists: [UInt64]) -> [OrderItem] {
        let free = playlists.filter { folderIndex(of: $0) == nil }
        let valid = Set(free.map(OrderItem.playlist) + folders.map { .folder($0.id) })
        var seen = Set<OrderItem>()
        let kept = order.filter { valid.contains($0) && seen.insert($0).inserted }
        return kept + (folders.map { .folder($0.id) } + free.map(OrderItem.playlist)).filter { seen.insert($0).inserted }
    }

    /// The rows of the top list in the order that the iPod shows.
    public func shownItems(_ playlists: [ITunesDB.PlaylistEntry]) -> [OrderItem] {
        if customOrder { return completedOrder(playlists: playlists.map(\.persistentID)) }
        let free = playlists.filter { folderIndex(of: $0.persistentID) == nil }
        guard alphabetical else { return folders.map { .folder($0.id) } + free.map { .playlist($0.persistentID) } }
        let rows = folders.map { ($0.name, OrderItem.folder($0.id)) } + free.map { ($0.name, OrderItem.playlist($0.persistentID)) }
        return rows.sorted { $0.0.caseInsensitiveCompare($1.0) == .orderedAscending }.map(\.1)
    }

    /// The playlists of a folder in the order that the iPod shows.
    public func shownMembers(of folder: Folder, playlists: [ITunesDB.PlaylistEntry]) -> [UInt64] {
        if customOrder { return folder.members }
        return playlists.map(\.persistentID).filter { folder.members.contains($0) }
    }

    /// Move one item of the top list up (-1) or down (1).
    public mutating func shiftOrder(_ item: OrderItem, by delta: Int, playlists: [UInt64]) {
        order = completedOrder(playlists: playlists)
        guard let i = order.firstIndex(of: item), order.indices.contains(i + delta) else { return }
        order.swapAt(i, i + delta)
    }

    /// The folders of an iTunes library for the playlists of an iPod. A playlist in a nested folder
    /// goes into its top-level folder, because the patch has one level only. `missing` has the names
    /// of the playlists in the folders that the iPod does not have.
    public static func imported(from library: [ITunesLibrary.Playlist],
                                ipod: [ITunesDB.PlaylistEntry]) -> (folders: PlaylistFolders, missing: [String]) {
        let onIPod = ipod.filter { !$0.isMaster && !$0.isPodcast }
        let ids = Set(onIPod.map(\.persistentID))
        var byName = [String: UInt64]()
        for p in onIPod where byName[p.name] == nil { byName[p.name] = p.persistentID }
        let byID = Dictionary(library.map { ($0.persistentID, $0) }, uniquingKeysWith: { a, _ in a })

        /// The top-level folder above a playlist. The set stops a file with a loop.
        func root(of playlist: ITunesLibrary.Playlist) -> ITunesLibrary.Playlist? {
            var seen = Set<UInt64>(), at = playlist
            while let parent = byID[at.parentID], parent.isFolder, seen.insert(parent.persistentID).inserted { at = parent }
            return at.persistentID == playlist.persistentID ? nil : at
        }

        var out = PlaylistFolders()
        var index = [UInt64: Int]()
        var missing = [String]()
        for p in library where !p.isFolder {
            guard let top = root(of: p) else { continue }
            guard let member = ids.contains(p.persistentID) ? p.persistentID : byName[p.name] else {
                missing.append(p.name)
                continue
            }
            let i = index[top.persistentID] ?? out.folders.count
            if i == out.folders.count {
                index[top.persistentID] = i
                out.folders.append(Folder(name: top.name))
            }
            out.folders[i].members.append(member)
        }
        // The order of the records is the order of the library. A later top-level item keeps this order.
        let free = ids.subtracting(out.folders.flatMap(\.members))
        out.order = library.compactMap { p in
            if let i = index[p.persistentID] { return .folder(out.folders[i].id) }
            guard !p.isFolder, let id = ids.contains(p.persistentID) ? p.persistentID : byName[p.name],
                  free.contains(id) else { return nil }
            return .playlist(id)
        }
        out.customOrder = true
        return (out, missing)
    }

    /// The problems that stop a write, for example a folder that has the name of a playlist.
    public func problems(playlistNames: [String]) -> [String] {
        var out = [String]()
        if folders.count > Self.maxFolders { out.append("Use a maximum of \(Self.maxFolders) folders.") }
        let names = Set(playlistNames.map { $0.lowercased() })
        var seen = Set<String>()
        for f in folders {
            let name = f.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { out.append("Give each folder a name."); continue }
            if f.name.utf16.count > Self.maxNameLength {
                out.append("The name “\(f.name)” is too long. Use a maximum of \(Self.maxNameLength) characters.")
            }
            if names.contains(f.name.lowercased()) {
                out.append("The folder “\(f.name)” has the name of a playlist. Give the folder a different name.")
            }
            if !seen.insert(f.name.lowercased()).inserted { out.append("Two folders have the name “\(f.name)”.") }
        }
        if encode().count > Self.maxFileSize { out.append("The folders have too many playlists.") }
        return out
    }

    // MARK: colour

    public static func rgb565(red: Int, green: Int, blue: Int) -> UInt16 {
        UInt16((red >> 3) << 11 | (green >> 2) << 5 | blue >> 3)
    }

    /// The 8-bit red, green and blue values of an RGB565 colour.
    public static func components(_ c: UInt16) -> (red: Int, green: Int, blue: Int) {
        let r = Int(c >> 11 & 0x1F), g = Int(c >> 5 & 0x3F), b = Int(c & 0x1F)
        return (r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2)
    }

    /// A square PNG of one colour: the picture of the folder in the album-art file.
    public static func tile(_ colour: UInt16, side: Int = 40) -> Data? {
        let c = components(colour)
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &buf, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(srgbRed: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage().flatMap(ImageCodec.pngData)
    }

    /// The album-art entries of the folders: the playlist key of the folder name and its colour tile.
    public func artEntries() -> [String: Data] {
        var out = [String: Data]()
        for f in folders where !f.name.isEmpty {
            if let t = Self.tile(f.colour) { out[AlbumArt.playlistKey(f.name)] = t }
        }
        return out
    }
}
