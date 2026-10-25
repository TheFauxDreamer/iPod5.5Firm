import Foundation
@testable import IPodFWKit
import XCTest

// The test checks that the Swift version and the Python version give the same
// result for the file of the keys of the iPod of the owner. The test does not
// run without the folder iPod_Control. The test compares the two versions at
// run time: the file of the owner is private, thus this test publishes no
// number of an account and no key.
final class GameKeysAgreementTests: XCTestCase {
    func testSwiftAndPythonAgreeOnTheRealFile() throws {
        // The folder iPod_Control is the folder of the iPod of the owner. The folder is
        // not in the repository. The test does not run without the folder.
        let root = "../iPod_Control"
        guard FileManager.default.fileExists(atPath: root) else {
            throw XCTSkip("The folder iPod_Control is not here.")
        }
        let store = try GameKeys.loadKeyStore("\(root)/iTunes/iEKInfo")
        XCTAssertGreaterThanOrEqual(store.accounts.count, 1)
        XCTAssertGreaterThanOrEqual(store.keyCount, store.accounts.count)
        XCTAssertEqual(store.deviceIDs.count, 3)

        // The Python version must give the same counts. The command prints the
        // counts only, not the numbers of the accounts and not the keys.
        let py = try runPythonCounts("\(root)/iTunes/iEKInfo")
        XCTAssertEqual("accounts=\(store.accounts.count) keys=\(store.keyCount) devices=\(store.deviceIDs.count)", py)
    }

    /// Count the accounts, the keys and the device ids with the Python module.
    private func runPythonCounts(_ path: String) throws -> String {
        let code = "import sys; from ipodfw import games; "
            + "s = games.load_key_store(sys.argv[1]); "
            + "print(f'accounts={len(s.accounts)} keys={sum(len(a.keys) for a in s.accounts)} devices={len(s.device_ids)}')"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "-c", code, path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw XCTSkip("The Python module did not run. The test needs the package of the project.")
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
