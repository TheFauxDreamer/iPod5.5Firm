import Foundation
import IPodFWKit
import LocalAuthentication
import ServiceManagement

/// Talks to the privileged helper daemon (registered once with SMAppService and approved in
/// System Settings → Login Items). Falls back to the password prompt when it isn't enabled.
enum HelperClient {
    static let service = SMAppService.daemon(plistName: helperPlistName)

    /// The status of the helper for this copy of the app. The daemon is registered for the whole Mac, and each
    /// copy with the same bundle identifier sees it. An ad-hoc build cannot use the daemon, because the
    /// daemon accepts only a signed app. Thus an ad-hoc build always gets `.notRegistered`.
    static var serviceStatus: SMAppService.Status { ownTeamIdentifier() == nil ? .notRegistered : service.status }

    static var isEnabled: Bool { serviceStatus == .enabled }

    /// True if the helper replies to `status` in a short time. If launchd cannot start the helper,
    /// the helper never replies, and the app must use the password prompt.
    static func isResponding() async -> Bool {
        guard isEnabled else { return false }
        return (try? await call(timeout: 10) { p, reply in p.status(reply: reply) }) != nil
    }

    static func register() throws {
        if service.status == .enabled { return }
        try service.register()
    }

    static func unregister() async throws { try await service.unregister() }

    /// Touch ID (or Apple Watch / password fallback) before anything that writes to the iPod.
    static func authenticate(_ reason: String) async throws {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Password"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw FirmwareError("This Mac cannot do the authentication now: \(error?.localizedDescription ?? "unknown error").")
        }
        do {
            _ = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let e as LAError where [.userCancel, .appCancel, .systemCancel].contains(e.code) {
            throw FirmwareError("Cancelled.")
        }
    }

    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    /// Without `timeout`, the call waits until the helper replies. A backup or a flash can take a long time.
    static func call(timeout: TimeInterval? = nil,
                     _ body: @escaping (HelperXPCProtocol, @escaping (Data) -> Void) -> Void) async throws -> Data {
        let conn = NSXPCConnection(machServiceName: helperMachService, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        if let team = ownTeamIdentifier() {
            // make sure we are talking to our own helper
            conn.setCodeSigningRequirement(signingRequirement(identifier: "com.thefauxdreamer.ipodfirm.helper", team: team))
        }
        conn.resume()
        defer { conn.invalidate() }
        return try await withCheckedThrowingContinuation { cont in
            let once = Once()
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                if once.take() { cont.resume(throwing: FirmwareError("The iPodFirm helper did not respond: \(error.localizedDescription)")) }
            } as! HelperXPCProtocol
            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if once.take() { cont.resume(throwing: FirmwareError("The iPodFirm helper did not respond.")) }
                }
            }
            body(proxy) { data in if once.take() { cont.resume(returning: data) } }
        }
    }

    static func status() async throws -> HelperStatus {
        try HelperJSON.decode(HelperStatus.self, try await call(timeout: 10) { p, reply in p.status(reply: reply) })
    }

    static func backup(disk: String, backupDir: URL) async throws -> HelperResult {
        try HelperJSON.decode(HelperResult.self, try await call { p, reply in
            p.backup(disk: disk, backupDir: backupDir.path, reply: reply)
        })
    }

    static func readOSOS(disk: String, dir: URL) async throws -> HelperResult {
        try HelperJSON.decode(HelperResult.self, try await call(timeout: 120) { p, reply in
            p.readOSOS(disk: disk, dir: dir.path, reply: reply)
        })
    }

    static func flash(disk: String, image: URL, backupDir: URL, reason: String, dryRun: Bool) async throws -> HelperResult {
        try HelperJSON.decode(HelperResult.self, try await call { p, reply in
            p.flash(disk: disk, image: image.path, backupDir: backupDir.path, reason: reason, dryRun: dryRun, reply: reply)
        })
    }

    static func rescueRestore(disk: String, image: URL, backupDir: URL, dryRun: Bool) async throws -> HelperResult {
        try HelperJSON.decode(HelperResult.self, try await call { p, reply in
            p.rescueRestore(disk: disk, image: image.path, backupDir: backupDir.path, dryRun: dryRun, reply: reply)
        })
    }
}
