import Foundation

// The reader of the manifest of a game, the copy of the games to an iPod and the
// removal of the games from an iPod.
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

    /// Find the folder with the games in a folder iPod_Control.
    ///
    /// The firmware asks for the name `games_RO` with small letters. The program of
    /// iTunes writes the name `Games_RO` with a capital letter. The function accepts
    /// both names. The function gives nil when the folder has no such folder.
    public static func gamesDirectory(at root: String) -> String? {
        for name in [gamesDirName, gamesDirNameITunes] {
            let dir = (root as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
        }
        return nil
    }

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
    /// The name of the file of the keys of the games in the folder iPod_Control/iTunes.
    /// The app copies the file. The app never reads or changes the bytes of the file.
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
            try copyKey(keyFileSource, to: targetRoot)
            report.keyFileCopied = true
        }
        return report
    }

    /// The largest key file that the app accepts. A real file is much smaller.
    public static let keyFileMaxSize = 4 * 1024 * 1024

    /// Check a key file that the owner chose. Returns the problem, or nil if the file can be
    /// copied. The file has no known format, thus the check uses only the name and the size.
    /// The function does not read the bytes of the file.
    public static func checkKeyFile(_ url: URL) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return "The file \(url.lastPathComponent) is not a file."
        }
        guard url.lastPathComponent.caseInsensitiveCompare(keyFileName) == .orderedSame else {
            return "The key file must have the name \(keyFileName). The chosen file has the name \(url.lastPathComponent)."
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > 0 else { return "The file \(url.lastPathComponent) is empty." }
        guard size <= keyFileMaxSize else {
            return "The file \(url.lastPathComponent) is too large (\(size) bytes) for a key file."
        }
        return nil
    }

    /// Copy the owner's key file to iPod_Control/iTunes/IC-Info.sidb. The app copies the bytes
    /// as they are. It never reads, changes or makes a key file.
    public static func copyKey(_ source: URL, to targetRoot: URL) throws {
        if let problem = checkKeyFile(source) { throw InstallError.incomplete(problem) }
        let fm = FileManager.default
        let out = targetRoot.appendingPathComponent("iTunes").appendingPathComponent(keyFileName)
        try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: out.path) { try fm.removeItem(at: out) }
        try fm.copyItem(at: source, to: out)
    }

    /// Copy the games to the folder iPod_Control of an iPod.
    ///
    /// The function copies each game that is complete. The function skips a game that is
    /// not complete and gives the reason in the report. If a key file is given, it copies the
    /// key file one time, after the games.
    public static func install(_ games: [GameLibraryItem], to targetRoot: URL,
                                copyKeyFile: Bool = false, keyFileSource: URL? = nil) -> Report {
        var report = Report()
        for game in games {
            do {
                let one = try install(game, to: targetRoot)
                report.installed.append(contentsOf: one.installed)
                report.bytesCopied += one.bytesCopied
            } catch {
                report.skipped.append(game.folder)
                report.warnings.append(error.localizedDescription)
            }
        }
        if copyKeyFile, let keyFileSource {
            do {
                try copyKey(keyFileSource, to: targetRoot)
                report.keyFileCopied = true
            } catch {
                report.warnings.append("key file: \(error)")
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
        guard let gamesDir = GameLibrary.gamesDirectory(at: targetRoot) else {
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
