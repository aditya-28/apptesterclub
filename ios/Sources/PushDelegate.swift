import UIKit

/// Receives the APNs device token and tells every configured server about it.
///
/// Each instance keeps its own device list, so a phone paired with two servers
/// registers with both — neither has to know the other exists.
final class PushDelegate: NSObject, UIApplicationDelegate {
    /// Set at launch. A delegate is constructed by UIKit, so it cannot be
    /// handed dependencies through an initialiser.
    @MainActor static var store: ServerStore?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif

        Task { @MainActor in
            guard let servers = PushDelegate.store?.servers else { return }
            for server in servers {
                await API(server: server).register(deviceToken: token, sandbox: sandbox)
            }
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
