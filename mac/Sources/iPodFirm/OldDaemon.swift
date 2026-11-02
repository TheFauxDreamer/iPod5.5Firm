import Foundation
import IPodFWKit
import ServiceManagement

/// Older versions could register a root daemon. This version does not use it. At each launch, the
/// app removes a registration that it finds. Nothing asks the user, and a fault does not stop the launch.
/// macOS needs the plist in the app for this call, so the build keeps the plist. The app never calls
/// `register`, and the app has no helper program.
enum OldDaemon {
    static let plistName = "com.thefauxdreamer.ipodfirm.helper.plist"

    static func removeIfRegistered() {
        let service = SMAppService.daemon(plistName: plistName)
        guard service.status != .notRegistered, service.status != .notFound else { return }
        Task {
            do {
                try await service.unregister()
                AppLog.info("Old daemon: removed the registration")
            } catch {
                AppLog.warning("Old daemon: cannot remove the registration\n" + AppLog.describe(error))
            }
        }
    }
}
