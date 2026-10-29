import AppKit
import IPodFWKit
import UserNotifications

/// Shows a macOS notification when GitHub has a newer release. The notification opens the
/// release page in the browser. The app does not download the update.
final class UpdateNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UpdateNotifier()
    static let skippedKey = "skippedUpdateVersion"

    private static let category = "update"
    private static let openAction = "open"
    private static let skipAction = "skip"

    /// Call this one time in applicationDidFinishLaunching. Then a click on a notification
    /// operates also when the click starts the app.
    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: Self.openAction, title: "Open GitHub", options: [.foreground])
        let skip = UNNotificationAction(identifier: Self.skipAction, title: "Skip This Version", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [open, skip],
                                                                 intentIdentifiers: [])])
    }

    /// Posts the notification. Returns false if the user does not allow notifications from iPodFirm.
    /// Then the caller shows an alert in the app.
    func notify(_ release: UpdateCheck.Release, local: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = "A New Version of iPodFirm Is Available"
        content.body = "Version \(release.version) is on GitHub. You have version \(local). Click to open the release page."
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["url": release.url.absoluteString, "version": release.version]
        // The same identifier for the same version: a second check replaces the notification.
        let request = UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil)
        do { try await center.add(request) } catch { return false }
        return true
    }

    /// At the launch the app is in front. Without this, macOS does not show the banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case Self.skipAction:
            if let version = info["version"] as? String { UserDefaults.standard.set(version, forKey: Self.skippedKey) }
        case Self.openAction, UNNotificationDefaultActionIdentifier:
            if let s = info["url"] as? String, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        default:
            break
        }
        completionHandler()
    }
}
