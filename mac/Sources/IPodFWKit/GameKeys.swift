import Foundation

// The key store of the games of the iPod, and the files of a game.
//
// The file iPod_Control/iTunes/iEKInfo holds the keys of the accounts of the Apple ID.
// The file holds one record for each account. Each account holds one record for each
// key of the account. The key of a game is 16 bytes.
//
// The file iPod_Control/iTunes/IC-Info.sidb holds the same keys in a form that the app
// cannot read. The app copies the file. The app never changes the bytes of the file.
//
// The file sinf of a game holds the number of the account, the number of the key, the
// vector of AES and the encrypted data of the program.
//
// The research is in [../../re/games-keyfile.md](../../re/games-keyfile.md).
// This is the Swift version of src/ipodfw/games.py.

public enum GameKeys {
    /// The name of the file of the keys in the folder iPod_Control/iTunes.
    public static let keyStoreName = "iEKInfo"

    /// The name of the other file of the keys. The app copies the file. The app cannot
    /// read the file.
    public static let keyFileName = "IC-Info.sidb"

    /// The offset of the first record of the file iEKInfo. The first 0x4C bytes are the
    /// header of the file.
    public static let keyStoreHeaderSize = 0x4C

    /// The size of one key, in bytes.
    public static let keySize = 16

    public enum StoreError: Error, CustomStringConvertible {
        case tooShort
        case notAKeyStore(String)

        public var description: String {
            switch self {
            case .tooShort: return "The file is too short to be a file of keys."
            case .notAKeyStore(let name): return "The file does not start with a key store. It has the name \"\(name)\"."
            }
        }
    }

    /// One record of the file iEKInfo.
    public struct Record {
        public var tag: String              // the name of the record, for example "user"
        public var fields: [UInt32]         // the 32-bit numbers at the start of the record
        public var data: Data               // the bytes after the numbers
        public var children: [Record]       // the records of the body

        public func child(_ tag: String) -> Record? {
            children.first { $0.tag == tag }
        }

        public func children(_ tag: String) -> [Record] {
            children.filter { $0.tag == tag }
        }
    }

    /// One key of one account.
    public struct Key: Identifiable {
        public var index: Int               // the number of the key, for example 4
        public var value: Data              // the key, 16 bytes
        public var id: Int { index }

        public var hex: String { value.map { String(format: "%02x", $0) }.joined() }
    }

    /// One account of the Apple ID, with all of its keys.
    public struct Account: Identifiable {
        public var number: UInt32           // the number of the account of the purchase
        public var keys: [Key]
        public var id: UInt32 { number }

        public func key(_ index: Int) -> Key? {
            keys.first { $0.index == index }
        }
    }

    /// The file iEKInfo: the keys of the accounts of the iPod.
    public struct KeyStore {
        public var accounts: [Account]
        public var deviceIDs: [Data]         // the records "guid"
        public var version: Int              // the number of the first record

        public func account(_ number: UInt32) -> Account? {
            accounts.first { $0.number == number }
        }

        public func key(_ number: UInt32, _ index: Int) -> Key? {
            account(number)?.key(index)
        }

        public var keyCount: Int { accounts.reduce(0) { $0 + $1.keys.count } }
    }

    // MARK: - The reader of the file of the keys

    /// Read one record at this offset. Give nil when the bytes are not a record.
    ///
    /// A record has a length of 4 bytes, a name of 4 bytes and a body. The length
    /// counts the name and the body. The length and the name are big endian.
    static func readRecord(_ data: [UInt8], _ off: Int) -> (length: Int, tag: String, body: [UInt8])? {
        if off < 0 || off + 8 > data.count { return nil }
        let length = Int(be32(data, off))
        if length < 8 || off + length > data.count { return nil }
        let tag = String(bytes: data[(off + 4)..<(off + 8)], encoding: .isoLatin1) ?? ""
        return (length, tag, Array(data[(off + 8)..<(off + length)]))
    }

    /// Tell whether the name of a record is a name.
    ///
    /// The name of a record has 4 characters. Each character is printable. The name of
    /// a record of the file of the keys is "sean", "valu", "indx", "user", "key " or "guid".
    static func hasName(_ tag: String) -> Bool {
        tag.count == 4 && tag.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7E }
    }

    /// Read the records from off to end. Give the offsets of the records.
    ///
    /// The function gives nil when the records do not fill the whole range, or when a
    /// record has no name.
    static func tile(_ data: [UInt8], _ off: Int, _ end: Int) -> [Int]? {
        var out: [Int] = []
        var p = off
        while p < end {
            guard let rec = readRecord(data, p), hasName(rec.tag) else { return nil }
            out.append(p)
            p += rec.length
        }
        return p == end ? out : nil
    }

    /// Find the records that the body of a record holds.
    ///
    /// The body of a record starts with some 32-bit numbers. The records come after
    /// the numbers. The function tries every count of numbers and keeps the count that
    /// gives the most records.
    static func findChildren(_ data: [UInt8], _ off: Int, _ length: Int) -> [Int] {
        let bodyLength = max(0, length - 8)
        var best: [Int] = []
        var skip = 0
        while skip <= min(bodyLength, 60) {
            if let found = tile(data, off + 8 + skip, off + length), found.count > best.count {
                best = found
            }
            skip += 4
        }
        return best
    }

    /// Make a record and all of its child records.
    static func parse(_ data: [UInt8], _ off: Int) -> Record? {
        guard let rec = readRecord(data, off) else { return nil }
        let fields = stride(from: 0, to: max(0, rec.body.count - 3), by: 4).map { be32(rec.body, $0) }
        var record = Record(tag: rec.tag, fields: fields, data: Data(rec.body), children: [])
        for childOff in findChildren(data, off, rec.length) {
            if let child = parse(data, childOff) { record.children.append(child) }
        }
        return record
    }

    /// Read the file iEKInfo. Give the keys of the accounts.
    public static func parseKeyStore(_ data: Data) throws -> KeyStore {
        let bytes = [UInt8](data)
        guard bytes.count >= keyStoreHeaderSize + 8 else { throw StoreError.tooShort }
        guard let top = readRecord(bytes, keyStoreHeaderSize) else { throw StoreError.tooShort }
        guard top.tag == "sean" else { throw StoreError.notAKeyStore(top.tag) }

        var store = KeyStore(accounts: [], deviceIDs: [], version: 0)
        for childOff in findChildren(bytes, keyStoreHeaderSize, top.length) {
            guard let child = parse(bytes, childOff) else { continue }
            switch child.tag {
            case "user": store.accounts.append(account(child))
            case "guid": store.deviceIDs.append(child.data.count >= 12 ? child.data.subdata(in: 12..<child.data.count) : Data())
            case "indx": store.version = child.fields.first.map { Int($0) } ?? 0
            default: break
            }
        }
        return store
    }

    /// Make an account and its keys from a record "user".
    static func account(_ rec: Record) -> Account {
        let number = rec.fields.first ?? 0
        var keys: [Key] = []
        for keyRec in rec.children("key ") {
            let index = Int(keyRec.fields.first ?? 0)
            guard let valueRec = keyRec.child("valu"), valueRec.data.count >= 12 + keySize else { continue }
            let value = valueRec.data.subdata(in: 12..<(12 + keySize))
            keys.append(Key(index: index, value: value))
        }
        return Account(number: number, keys: keys)
    }

    /// Read the file iEKInfo at this path.
    public static func loadKeyStore(_ path: String) throws -> KeyStore {
        try parseKeyStore(Data(contentsOf: URL(fileURLWithPath: path)))
    }

    // MARK: - The reader of the file sinf of a game

    /// Read the atoms of a file. Give the name and the body of each atom.
    ///
    /// An atom has a size of 4 bytes, a name of 4 bytes and a body. The size counts
    /// the name and the body. The size and the name are big endian.
    static func atoms(_ data: [UInt8], _ off: Int, _ end: Int) -> [(tag: String, body: [UInt8])] {
        var out: [(tag: String, body: [UInt8])] = []
        var p = off
        while p + 8 <= end {
            let size = Int(be32(data, p))
            if size < 8 || p + size > end { break }
            let tag = String(bytes: data[(p + 4)..<(p + 8)], encoding: .isoLatin1) ?? ""
            out.append((tag, Array(data[(p + 8)..<(p + size)])))
            p += size
        }
        return out
    }

    /// Read the file sinf of a game. Give the body of each atom.
    ///
    /// The atoms "user", "key ", "iviv", "righ", "name" and "priv" are in the atom
    /// "schi" of the atom "sinf".
    public static func parseSinf(_ data: Data) -> [String: [UInt8]] {
        let bytes = [UInt8](data)
        var out: [String: [UInt8]] = [:]
        for atom in atoms(bytes, 0, bytes.count) where atom.tag == "sinf" {
            for atom2 in atoms(atom.body, 0, atom.body.count) {
                if atom2.tag == "schi" {
                    for atom3 in atoms(atom2.body, 0, atom2.body.count) { out[atom3.tag] = atom3.body }
                } else {
                    out[atom2.tag] = atom2.body
                }
            }
        }
        return out
    }

    /// The keys of one game, and the account that owns the game.
    public struct GameKey {
        public var number: UInt32       // the number of the account, from the atom "user"
        public var keyIndex: Int        // the number of the key, from the atom "key "
        public var iv: Data             // the vector of AES, 16 bytes, from the atom "iviv"
        public var name: String         // the name of the account, from the atom "name"
        public var key: Key?            // the key of the account, when the file of the keys has it
    }

    /// Read the file sinf of a game. Give the account and the key of the game.
    public static func gameKeys(_ sinf: Data, _ store: KeyStore?) -> GameKey {
        let atoms = parseSinf(sinf)
        let number = atoms["user"].map { be32($0, 0) } ?? 0
        let index = atoms["key "].map { Int(be32($0, 0)) } ?? 0
        let iv = Data(atoms["iviv"] ?? [])
        let name = String(data: Data((atoms["name"] ?? []).prefix { $0 != 0 }), encoding: .isoLatin1) ?? ""
        return GameKey(number: number, keyIndex: index, iv: iv, name: name,
                       key: store?.key(number, index))
    }

    /// One game of a folder of games.
    public struct Game {
        public var folder: String       // the name of the folder of the game
        public var sinfPath: URL        // the path of the file sinf
        public var keys: GameKey
    }

    /// Find the folder with the games in a folder iPod_Control.
    ///
    /// The firmware asks for the name `games_RO` with small letters. The program of
    /// iTunes writes the name `Games_RO` with a capital letter. The function accepts
    /// both names. The function gives nil when the folder has no such folder.
    public static func gamesDirectory(at root: String) -> String? {
        for name in ["games_RO", "Games_RO"] {
            let dir = (root as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
        }
        return nil
    }

    /// Find the games in a folder. Give the name of the game and the file sinf.
    ///
    /// The folder holds one folder for each game. The folder holds the file sinf of the
    /// program of the game.
    public static func findGames(_ dir: String, _ store: KeyStore?) -> [Game] {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: dir)
        guard let folders = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [Game] = []
        for folder in folders.sorted() {
            let exeDir = root.appendingPathComponent(folder).appendingPathComponent("Executables")
            guard let names = try? fm.contentsOfDirectory(atPath: exeDir.path) else { continue }
            for name in names.sorted() where name.hasSuffix(".sinf") {
                let path = exeDir.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: path) else { continue }
                out.append(Game(folder: folder, sinfPath: path, keys: gameKeys(data, store)))
            }
        }
        return out
    }
}

// The reader of the manifest of a game, and the copy of the games to an iPod.
// This is the Swift version of src/ipodfw/games.py.

/// One file of the array Files of the manifest of a game.
public struct ManifestFile {
    public var path: String        // the path of the file, for example "Fonts/Arial15Hira13Hybrid0.ipd"
    public var size: Int           // the size of the file in bytes
    public var digest: String      // the digest of the file, 40 hexadecimal characters
}

/// The file Manifest.plist of a game.
public struct GameManifest {
    public var guid: String                        // the name of the folder of the game
    public var name: String                        // the name of the game, for example "iQuiz"
    public var version: String
    public var buildID: String
    public var platformID: Int                     // the PlatformID of the platform of the game
    public var executable: String                  // the path of the program of the game
    public var executableSize: Int
    public var files: [ManifestFile]               // the array Files of the manifest
    public var sampleDataPath: String = ""
    public var userDataPath: String = ""

    /// The sum of the sizes of the files of the array Files.
    public var totalSize: Int { files.reduce(0) { $0 + $1.size } }

    public enum ManifestError: Error, CustomStringConvertible {
        case notAPlist
        case noPlatform

        public var description: String {
            switch self {
            case .notAPlist: return "The file is not a plist of a game."
            case .noPlatform: return "The manifest has no platform."
            }
        }
    }

    /// Read the file Manifest.plist of a game.
    public static func parse(_ data: Data) throws -> GameManifest {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ManifestError.notAPlist
        }
        guard let platforms = root["Platforms"] as? [[String: Any]], let platform = platforms.first else {
            throw ManifestError.noPlatform
        }
        var files: [ManifestFile] = []
        for entry in root["Files"] as? [[String: Any]] ?? [] {
            files.append(ManifestFile(path: entry["Path"] as? String ?? "",
                                      size: (entry["Size"] as? NSNumber)?.intValue ?? 0,
                                      digest: entry["Digest"] as? String ?? ""))
        }
        return GameManifest(guid: root["GUID"] as? String ?? "",
                            name: root["Name"] as? String ?? "",
                            version: root["Version"] as? String ?? "",
                            buildID: root["BuildIdentifier"] as? String ?? "",
                            platformID: (platform["PlatformID"] as? NSNumber)?.intValue ?? 0,
                            executable: platform["ExecutablePath"] as? String ?? "",
                            executableSize: (platform["Size"] as? NSNumber)?.intValue ?? 0,
                            files: files,
                            sampleDataPath: root["SampleDataPath"] as? String ?? "",
                            userDataPath: root["UserDataPath"] as? String ?? "")
    }
}

/// One game of a folder of games.
public struct GameLibraryItem {
    public var folder: String          // the name of the folder of the game, the GUID of the game
    public var path: URL               // the path of the folder of the game
    public var manifest: GameManifest
    public var name: String { manifest.name.isEmpty ? folder : manifest.name }
}

/// The library of the games of a folder.
public enum GameLibrary {
    /// The name of the folder of the games. The firmware asks for the name with small
    /// letters. The program of iTunes writes the name with a capital letter.
    public static let gamesDirName = "games_RO"
    public static let gamesDirNameITunes = "Games_RO"

    /// The files that the app copies in addition to the array Files of the manifest.
    /// The file Manifest.plist.p7b is the signature of the manifest. The app must
    /// never change the manifest or its signature.
    public static let extraFiles = ["Manifest.plist", "Manifest.plist.p7b", "iTunesMetaData"]

    /// Read the game in this folder. The folder must hold the file Manifest.plist.
    public static func loadGame(_ folder: URL) throws -> GameLibraryItem {
        let manifestURL = folder.appendingPathComponent("Manifest.plist")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try GameManifest.parse(data)
        return GameLibraryItem(folder: folder.lastPathComponent, path: folder, manifest: manifest)
    }

    /// Read the games in a folder. Give the list of the games.
    ///
    /// The function skips a folder that has no file Manifest.plist.
    public static func load(_ dir: String) -> [GameLibraryItem] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var out: [GameLibraryItem] = []
        for folder in folders.sorted() {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(folder)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard (try? loadGame(url)) != nil else { continue }
            out.append((try? loadGame(url))!)
        }
        return out
    }

    /// Check the game against its manifest. Give the list of the problems.
    ///
    /// An empty list means that the game is complete.
    public static func check(_ game: GameLibraryItem) -> [String] {
        var problems: [String] = []
        for f in game.manifest.files {
            let url = game.path.appendingPathComponent(f.path)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int else {
                problems.append("\(f.path) is missing")
                continue
            }
            if size != f.size {
                problems.append("\(f.path) has the size \(size), the manifest says \(f.size)")
            }
        }
        for name in extraFiles where !FileManager.default.fileExists(atPath: game.path.appendingPathComponent(name).path) {
            problems.append("\(name) is missing")
        }
        if !game.manifest.executable.isEmpty,
           !FileManager.default.fileExists(atPath: game.path.appendingPathComponent(game.manifest.executable).path) {
            problems.append("\(game.manifest.executable) is missing")
        }
        return problems
    }
}

/// The copy of the games to the folder iPod_Control of an iPod.
public enum GameInstaller {
    /// The name of the file of the keys that the DRM library of the system reads.
    /// The app copies the file. The app never changes the bytes of the file.
    public static let keyFileName = "IC-Info.sidb"

    /// The result of the copy of the games to an iPod.
    public struct Report {
        public var installed: [String] = []     // the GUID of each game
        public var skipped: [String] = []       // the GUID of each game that was not copied
        public var warnings: [String] = []      // the reason of each skip
        public var bytesCopied: Int = 0
        public var keyFileCopied = false
    }

    public enum InstallError: Error, CustomStringConvertible {
        case incomplete(String)

        public var description: String {
            switch self {
            case .incomplete(let text): return text
            }
        }
    }

    /// Copy one game to the folder iPod_Control of an iPod.
    ///
    /// The target root is the folder `iPod_Control` of the iPod. The app writes the game
    /// to the folder `games_RO/<GUID>`. The app uses the name with small letters. The app
    /// never removes a file of the iPod. The app copies over the files of the game only.
    ///
    /// The app copies the whole folder of the game. The array `Files` of the manifest holds
    /// the signed files. The other files of the folder hold the content of the game, for
    /// example the packs of questions. The app checks the size of each file of the array
    /// `Files` before the copy.
    public static func install(_ game: GameLibraryItem, to targetRoot: URL,
                                copyKeyFile: Bool = false, keyFileSource: URL? = nil) throws -> Report {
        let problems = GameLibrary.check(game)
        guard problems.isEmpty else {
            throw InstallError.incomplete("The game \(game.folder) is not complete: "
                                          + problems.prefix(5).joined(separator: "; "))
        }
        let fm = FileManager.default
        let dest = targetRoot.appendingPathComponent(GameLibrary.gamesDirName)
            .appendingPathComponent(game.folder)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        var report = Report()
        let files = allFiles(under: game.path)
        for rel in files {
            let src = game.path.appendingPathComponent(rel)
            let out = dest.appendingPathComponent(rel)
            try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The app copies over the files of the game. The app never removes a file
            // of the iPod that is not a file of the game.
            if fm.fileExists(atPath: out.path) { try fm.removeItem(at: out) }
            try fm.copyItem(at: src, to: out)
            let attrs = try? fm.attributesOfItem(atPath: out.path)
            report.bytesCopied += (attrs?[.size] as? Int) ?? 0
        }
        report.installed.append(game.folder)

        if copyKeyFile, let keyFileSource {
            let out = targetRoot.appendingPathComponent("iTunes").appendingPathComponent(keyFileName)
            try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: out.path) { try fm.removeItem(at: out) }
            try fm.copyItem(at: keyFileSource, to: out)
            report.keyFileCopied = true
        }
        return report
    }

    /// Copy the games to the folder iPod_Control of an iPod.
    ///
    /// The function copies each game that is complete. The function skips a game that is
    /// not complete and gives the reason in the report.
    public static func install(_ games: [GameLibraryItem], to targetRoot: URL,
                                copyKeyFile: Bool = false, keyFileSource: URL? = nil) -> Report {
        var report = Report()
        for game in games {
            do {
                let one = try install(game, to: targetRoot, copyKeyFile: copyKeyFile, keyFileSource: keyFileSource)
                report.installed.append(contentsOf: one.installed)
                report.bytesCopied += one.bytesCopied
                report.keyFileCopied = report.keyFileCopied || one.keyFileCopied
            } catch {
                report.skipped.append(game.folder)
                report.warnings.append(error.localizedDescription)
            }
        }
        return report
    }

    /// Give the paths of all the files of a folder, relative to the folder.
    ///
    /// The function uses the parts of the path and not the path as a string. The file
    /// system of macOS keeps no case by default. The enumerator can give a name with
    /// another case than the folder. A compare of the paths as a string would fail.
    static func allFiles(under root: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: nil) else { return [] }
        let fm = FileManager.default
        // The parts of the path of the folder. The function uses the resolved path. The
        // enumerator resolves the links in the path, for example the link /var. The
        // parts of the path of the folder must have the same form.
        let rootParts = root.resolvingSymlinksInPath().pathComponents.filter { !$0.isEmpty }
        var out: [String] = []
        for case let url as URL in walker {
            // The key isRegularFileKey gives no value inside the walker. The attributes
            // of the file give the type of the file.
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            guard (attrs?[.type] as? FileAttributeType) == .typeRegular else { continue }
            let parts = url.resolvingSymlinksInPath().pathComponents.filter { !$0.isEmpty }
            guard parts.count > rootParts.count else { continue }
            let rel = parts[rootParts.count...].joined(separator: "/")
            guard !rel.isEmpty else { continue }
            out.append(rel)
        }
        return out.sorted()
    }
}

/// The removal of the games from an iPod. The removal deletes the folder of the
/// game only. The folders `gamedata_RW` and `gamestats_WO` hold the saves and
/// the scores of the games. The removal does not touch them.
public enum GameRemover {
    /// The result of the removal of the games from an iPod.
    public struct Report {
        public var removed: [String] = []     // the GUID of each game
        public var refused: [String] = []     // the GUID of each game that the removal refused
        public init() {}
    }

    public enum RemoveError: Error, CustomStringConvertible {
        case noGamesFolder(String)
        case notAGuid(String)

        public var description: String {
            switch self {
            case .noGamesFolder(let path): return "The folder \(path) has no folder of the games."
            case .notAGuid(let name): return "\(name) is not the GUID of a game."
            }
        }
    }

    /// The GUID of each game folder in the folder of the games.
    ///
    /// The function gives only folders with a name of hexadecimal characters.
    /// The folders `gamedata_RW` and `gamestats_WO` of the iPod are not game
    /// folders: their names hold letters that are not hexadecimal.
    public static func removableFolders(_ gamesDir: String) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: gamesDir) else { return [] }
        return names.filter { name in
            name.allSatisfy { $0.isHexDigit } && !name.isEmpty
                && (try? fm.attributesOfItem(atPath: gamesDir + "/" + name))?[.type] as? String == FileAttributeType.typeDirectory.rawValue
        }.sorted()
    }

    /// Remove games from the folder iPod_Control of an iPod.
    ///
    /// The function removes the folder `games_RO/<GUID>` of each selected game.
    /// The GUID must hold hexadecimal characters only. The function refuses every
    /// other name: it never removes a file outside the folder of a game.
    public static func remove(_ targetRoot: String, _ guids: [String]) throws -> Report {
        guard let gamesDir = GameKeys.gamesDirectory(at: targetRoot) else {
            throw RemoveError.noGamesFolder(targetRoot)
        }
        var report = Report()
        let fm = FileManager.default
        for guid in guids {
            guard !guid.isEmpty, guid.allSatisfy({ $0.isHexDigit }) else {
                throw RemoveError.notAGuid(guid)
            }
            let folder = gamesDir + "/" + guid
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else { continue }
            try fm.removeItem(atPath: folder)
            report.removed.append(guid)
        }
        return report
    }
}
