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

    private init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
    }

    var isSandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
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
