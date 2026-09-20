import UIKit
import UserNotifications

/// Receives the APNs device token and tells every configured server about it.
///
/// Each instance keeps its own device list, so a phone paired with two servers
/// registers with both — neither has to know the other exists.
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set at launch. A delegate is constructed by UIKit, so it cannot be
    /// handed dependencies through an initialiser.
    @MainActor static var store: ServerStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Without this, a notification arriving while the app is open is
        // swallowed by iOS and a tap goes nowhere.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show the banner even when the app is frontmost. A build landing while
    /// you are looking at the list is exactly when you want to know.
    ///
    /// `nonisolated` because conforming to UIApplicationDelegate puts this class
    /// on the main actor, while UNUserNotificationCenterDelegate is not isolated
    /// at all — Swift 6 refuses to bridge that implicitly.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Tapping one opens the app it was about, on the server that sent it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Copy the values out here: the notification objects themselves are not
        // Sendable and must not cross onto the main actor.
        let info = response.notification.request.content.userInfo
        let slug = info["app_slug"] as? String
        let origin = info["origin"] as? String ?? ""
        guard let slug else { return }
        await MainActor.run { Push.shared.pending = (origin, slug) }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await Push.shared.received(token: token, servers: PushDelegate.store?.servers ?? [])
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simulators have no APNs, and a build without the aps-environment
        // entitlement fails here too. Neither is worth interrupting anyone over.
        print("push registration failed: \(error.localizedDescription)")
    }
}
