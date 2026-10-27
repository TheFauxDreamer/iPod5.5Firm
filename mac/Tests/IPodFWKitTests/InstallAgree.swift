import Foundation
@testable import IPodFWKit
import XCTest

// The test checks that the Swift version and the Python version give the same
// result for the games of the iPod of the owner. The test does not run without
// the folder iPod_Control.
final class GameInstallAgreementTests: XCTestCase {
    func testSwiftAndPythonInstallTheSameGames() throws {
        let root = "../iPod_Control"
        guard FileManager.default.fileExists(atPath: root) else {
            throw XCTSkip("The folder iPod_Control is not here.")
        }
        let gamesDir = GameLibrary.gamesDirectory(at: root)!
        let library = GameLibrary.load(gamesDir)
        XCTAssertEqual(library.map { $0.folder },
                       ["11002", "12345", "12346", "14005", "15042", "1B200", "1C300", "22022", "50514"])

        // The games that are complete. The Python version must give the same list.
        let complete = library.filter { GameLibrary.check($0).isEmpty }.map { $0.folder }
        XCTAssertEqual(complete, ["11002", "12345", "12346", "14005", "1B200", "1C300", "50514"])

        // The games that are not complete. The games 15042 and 22022 miss files.
        let incomplete = library.filter { !GameLibrary.check($0).isEmpty }.map { $0.folder }
        XCTAssertEqual(incomplete, ["15042", "22022"])

        // The copy gives the same result as the Python version.
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPodFirm-agree-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: target) }
        let report = GameInstaller.install(library, to: target)
        XCTAssertEqual(report.installed, ["11002", "12345", "12346", "14005", "1B200", "1C300", "50514"])
        XCTAssertEqual(report.skipped, ["15042", "22022"])
        XCTAssertEqual(report.bytesCopied, 226_577_300)
        XCTAssertEqual(report.warnings.count, 2)

        // The copy has the same number of files as the source.
        let source = library.first { $0.folder == "11002" }!
        XCTAssertEqual(GameInstaller.allFiles(under: source.path).count, 288)
        let dest = target.appendingPathComponent("games_RO/11002")
        var onDisk = 0
        if let e = FileManager.default.enumerator(at: dest, includingPropertiesForKeys: nil) {
            for case let u as URL in e {
                let a = try? FileManager.default.attributesOfItem(atPath: u.path)
                if (a?[.type] as? FileAttributeType) == .typeRegular { onDisk += 1 }
            }
        }
        XCTAssertEqual(onDisk, 288)
    }
}
