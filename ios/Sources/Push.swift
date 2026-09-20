import Foundation
import UIKit
import UserNotifications

/// Where the APNs device token lives between launches.
///
/// It has to be remembered rather than only handled when it arrives: APNs
/// delivers it once, shortly after launch, and a server paired later in the
/// session would otherwise never be told about this device. That was the
/// original bug — pair a second instance and it could never notify you.
@MainActor
@Observable
final class Push {
    static let shared = Push()

    private let tokenKey = "club.apptester.pushToken"

    private(set) var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: tokenKey) }
    }
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Set when a notification is tapped, cleared once the list has navigated.
    /// Carries the origin too, because two paired servers can hold the same app
    /// slug and the tap has to land on the one that sent it.
    var pending: (origin: String, slug: String)?

    private init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
    }

    /// Which APNs environment this build's token belongs to.
    ///
    /// Not the build configuration, which is the obvious guess and wrong: a
    /// Release build signed with a *development* profile gets a sandbox token,
    /// registers itself as production, and every push comes back
    /// BadDeviceToken. The entitlement is the only thing that actually decides
    /// it, so read that.
    var isSandbox: Bool {
        guard
            let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            // The profile is CMS-signed binary with a plain XML plist inside.
            // latin1 maps every byte to a character, so the XML survives intact.
            let text = String(data: data, encoding: .isoLatin1),
            let start = text.range(of: "<?xml"),
            let end = text.range(of: "</plist>"),
            let plist = try? PropertyListSerialization.propertyList(
                from: Data(text[start.lowerBound..<end.upperBound].utf8),
                format: nil) as? [String: Any],
            let entitlements = plist["Entitlements"] as? [String: Any],
            let environment = entitlements["aps-environment"] as? String
        else {
            // No embedded profile means an App Store build, which is always
            // production. Fall back to the build config only for the simulator.
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        return environment == "development"
    }

    /// Asks once, then registers. Registering before the grant returns a token
    /// Apple will not deliver to, so the order matters.
    func requestAuthorization(then servers: [Server]) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorization = await center.notificationSettings().authorizationStatus
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        // A token from a previous launch is still valid, so anything paired
        // since then can be caught up straight away.
        await register(with: servers)
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func received(token newToken: String, servers: [Server]) async {
        token = newToken
        await register(with: servers)
    }

    /// Tells every instance about this device. Each keeps its own list, so a
    /// phone paired with two servers registers with both and neither needs to
    /// know the other exists.
    func register(with servers: [Server]) async {
        guard let token else { return }
        for server in servers {
            await API(server: server).register(deviceToken: token, sandbox: isSandbox)
        }
    }

    /// Called when a server is added after launch.
    func register(with server: Server) async {
        await register(with: [server])
    }
}
