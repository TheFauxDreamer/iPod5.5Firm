import Foundation
import IPodFWKit

/// Runs the bundled ipodfw-helper with administrator rights (standard macOS password prompt).
enum Privileged {
    static let queue = DispatchQueue(label: "ipodfirm.privileged")

    static var helperPath: String {
        Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("ipodfw-helper").path
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func run(_ args: [String]) async throws -> HelperResult {
        let command = ([helperPath] + args).map(shellQuote).joined(separator: " ")
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        do shell script "\(escaped)" with prompt "iPodFirm needs administrator rights to read and write your iPod's firmware partition." with administrator privileges
        """
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                var error: NSDictionary?
                let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int
                    let msg = code == -128 ? "Cancelled." : (error[NSAppleScript.errorMessage] as? String ?? "The helper failed.")
                    var e = FirmwareError(msg)
                    e.cause = "AppleScript error \(code.map(String.init) ?? "none"): \(error)"
                    AppLog.warning("Helper (password) fault: \(e.cause ?? msg)")
                    cont.resume(throwing: e)
                    return
                }
                let text = output?.stringValue ?? ""
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                do {
                    cont.resume(returning: try dec.decode(HelperResult.self, from: Data(text.utf8)))
                } catch {
                    AppLog.warning("Helper (password): the output is not a result\n" + AppLog.describe(error) + "\nOutput: \(text.prefix(2000))")
                    cont.resume(throwing: FirmwareError("Unexpected helper output: \(text.prefix(300))", cause: error))
                }
            }
        }
    }
}
