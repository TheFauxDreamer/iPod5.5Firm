import CommonCrypto
import Compression
import Foundation

/// A read-only reader of the playlists in "iTunes Library.itl". The app never writes this file.
/// The format is in re/playlist-folders.md, "iTunes folders". It is a private format, so each
/// failed check stops the read. An unknown file must give an error, not wrong folders.
public enum ITunesLibrary {
    public struct Playlist: Equatable {
        public var name: String
        public var persistentID: UInt64
        /// The persistent ID of the folder of the playlist, or 0.
        public var parentID: UInt64
        public var isFolder: Bool

        public init(name: String, persistentID: UInt64, parentID: UInt64 = 0, isFolder: Bool = false) {
            self.name = name
            self.persistentID = persistentID
            self.parentID = parentID
            self.isFolder = isFolder
        }
    }

    public enum ReadError: LocalizedError {
        case notALibrary
        case unknownFormat

        public var errorDescription: String? {
            switch self {
            case .notALibrary: return "This file is not an iTunes library."
            case .unknownFormat: return "The app cannot read this version of the iTunes library."
            }
        }
    }

    /// The same AES key is in each copy of iTunes. It is not a secret of a person.
    static let key = Array("BHUILuilfghuila3".utf8)
    /// The value that iTunes uses if the header has no limit.
    static let defaultEncryptedLimit = 0x19000
    static let maxBodySize = 1 << 30

    // The offsets in a "miph" playlist record.
    static let idOffset = 440
    static let folderOffset = 522
    static let parentOffset = 528
    static let nameType = 100

    /// All playlists of the library, with the special playlists of iTunes.
    public static func playlists(_ file: [UInt8]) throws -> [Playlist] {
        let body = try decode(file)
        var r = Reader(body)
        var out = [Playlist]()
        let (start, end) = try r.playlistSection()
        var at = start
        while at < end {
            let (playlist, length) = try r.playlist(at: at, end: end)
            out.append(playlist)
            at += length
        }
        let parents = Set(out.map(\.parentID))
        for i in out.indices where parents.contains(out[i].persistentID) { out[i].isFolder = true }
        return out
    }

    /// The plain body of the file: the data after the header, decrypted and inflated.
    static func decode(_ file: [UInt8]) throws -> [UInt8] {
        guard file.count >= 0x60, Array(file[0..<4]) == Array("hdfm".utf8) else { throw ReadError.notALibrary }
        func u32(_ o: Int) -> Int { file[o..<o + 4].reduce(0) { $0 << 8 | Int($1) } }
        let header = u32(4), limit = u32(0x5c)
        guard header >= 0x60, header < file.count else { throw ReadError.notALibrary }
        let body = Array(file[header...])
        let encrypted = min(limit == 0 ? defaultEncryptedLimit : limit, body.count & ~15)
        guard let plain = crypt(CCOperation(kCCDecrypt), Array(body[0..<encrypted])) else { throw ReadError.unknownFormat }
        guard let out = inflate(plain + body[encrypted...]) else { throw ReadError.unknownFormat }
        return out
    }

    static func crypt(_ operation: CCOperation, _ data: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: data.count)
        var moved = 0
        let status = CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode), key, key.count, nil,
                             data, data.count, &out, out.count, &moved)
        return status == kCCSuccess && moved == data.count ? out : nil
    }

    /// Inflate zlib data. The Compression framework reads the data after the 2-byte zlib header.
    static func inflate(_ data: [UInt8]) -> [UInt8]? {
        guard data.count > 2, data[0] & 0x0F == 8, (Int(data[0]) << 8 | Int(data[1])) % 31 == 0 else { return nil }
        var capacity = max(data.count * 8, 0x10000)
        while capacity <= maxBodySize {
            var out = [UInt8](repeating: 0, count: capacity)
            let n = data[2...].withUnsafeBufferPointer {
                compression_decode_buffer(&out, capacity, $0.baseAddress!, $0.count, nil, COMPRESSION_ZLIB)
            }
            if n == 0 { return nil }
            // A full buffer can be a cut result. Try again with a larger buffer.
            if n < capacity { return Array(out[0..<n]) }
            capacity *= 2
        }
        return nil
    }

    private struct Reader {
        let b: [UInt8]
        init(_ b: [UInt8]) { self.b = b }

        func tag(_ o: Int) -> [UInt8] { Array(b[o..<o + 4]) }
        func u32(_ o: Int) -> Int { (0..<4).reduce(0) { $0 | Int(b[o + $1]) << (8 * $1) } }
        func u64(_ o: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(b[o + $1]) << (8 * UInt64($1)) } }

        /// The range of the "miph" records: the section of type 2.
        func playlistSection() throws -> (start: Int, end: Int) {
            var at = 0
            while at + 16 <= b.count {
                guard tag(at) == Array("msdh".utf8) else { throw ReadError.unknownFormat }
                let header = u32(at + 4), total = u32(at + 8), type = u32(at + 12)
                guard header >= 16, total >= header, total <= b.count - at else { throw ReadError.unknownFormat }
                if type == 2 {
                    let list = at + header
                    guard list + 16 <= at + total, tag(list) == Array("mlph".utf8) else { throw ReadError.unknownFormat }
                    let start = list + u32(list + 4)
                    guard start <= at + total else { throw ReadError.unknownFormat }
                    return (start, at + total)
                }
                at += total
            }
            throw ReadError.unknownFormat
        }

        /// One "miph" record and its total length.
        func playlist(at: Int, end: Int) throws -> (Playlist, Int) {
            guard at + 12 <= end, tag(at) == Array("miph".utf8) else { throw ReadError.unknownFormat }
            let header = u32(at + 4), total = u32(at + 8)
            guard header >= parentOffset + 8, total >= header, total <= end - at else { throw ReadError.unknownFormat }
            let p = Playlist(name: try name(from: at + header, end: at + total), persistentID: u64(at + idOffset),
                             parentID: u64(at + parentOffset), isFolder: b[at + folderOffset] != 0)
            return (p, total)
        }

        /// The first "mhoh" record of the name type.
        func name(from start: Int, end: Int) throws -> String {
            var at = start
            while at + 0x28 <= end, tag(at) == Array("mhoh".utf8) {
                let total = u32(at + 8), type = u32(at + 12)
                guard total >= 0x28, total <= end - at else { throw ReadError.unknownFormat }
                if type == nameType {
                    let encoding = u32(at + 0x18), length = u32(at + 0x1c)
                    guard length <= total - 0x28 else { throw ReadError.unknownFormat }
                    let text = Data(b[at + 0x28..<at + 0x28 + length])
                    let name: String?
                    switch encoding {
                    case 0, 3: name = String(data: text, encoding: .utf8)
                    case 1: name = String(data: text, encoding: .utf16LittleEndian)
                    default: name = nil
                    }
                    guard let name else { throw ReadError.unknownFormat }
                    return name
                }
                at += total
            }
            throw ReadError.unknownFormat
        }
    }
}
