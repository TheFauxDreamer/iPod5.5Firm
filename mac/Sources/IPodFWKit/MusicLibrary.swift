import Foundation
import iTunesLibrary

/// A read-only reader of the playlists of the Music app (or of iTunes 12.9). It uses the Apple
/// framework iTunesLibrary, so it needs no Apple Events. macOS asks the user for access to the
/// media library one time. The app never changes the library.
public enum MusicLibrary {
    public enum ReadError: LocalizedError {
        case noAccess(String)

        public var errorDescription: String? {
            switch self {
            case .noAccess(let reason):
                return "The app cannot read the Music library. Give iPodFirm access in System Settings > Privacy & Security > Media & Apple Music. (\(reason))"
            }
        }
    }

    /// The data of one playlist that the conversion uses.
    public struct Entry {
        public var name: String
        public var persistentID: UInt64
        public var parentID: UInt64?
        public var isFolder: Bool
        /// True for the library playlist and the special playlists (Music, Podcasts and others).
        public var isSpecial: Bool

        public init(name: String, persistentID: UInt64, parentID: UInt64?, isFolder: Bool, isSpecial: Bool) {
            self.name = name
            self.persistentID = persistentID
            self.parentID = parentID
            self.isFolder = isFolder
            self.isSpecial = isSpecial
        }
    }

    /// The playlists and folders of the library, in the order of the library. The special
    /// playlists are not in the result.
    public static func playlists() throws -> [ITunesLibrary.Playlist] {
        let library: ITLibrary
        do {
            library = try ITLibrary(apiVersion: "1.1", options: .lazyLoadData)
        } catch {
            throw ReadError.noAccess(error.localizedDescription)
        }
        defer { library.unloadData() }
        // A library always has the library playlist. With lazy loading, a failed connection gives
        // an empty list and no error. Thus an empty list is a failed read, not an empty library.
        guard !library.allPlaylists.isEmpty else { throw ReadError.noAccess("The library has no playlists.") }
        return convert(library.allPlaylists.map { p in
            Entry(name: p.name, persistentID: p.persistentID.uint64Value, parentID: p.parentID?.uint64Value,
                  isFolder: p.kind == .folder, isSpecial: p.isPrimary || p.distinguishedKind != .kindNone)
        })
    }

    /// The conversion to the type of the iTunes reader, so that `PlaylistFolders.imported` reads both.
    public static func convert(_ entries: [Entry]) -> [ITunesLibrary.Playlist] {
        entries.filter { !$0.isSpecial }.map {
            ITunesLibrary.Playlist(name: $0.name, persistentID: $0.persistentID,
                                   parentID: $0.parentID ?? 0, isFolder: $0.isFolder)
        }
    }
}
