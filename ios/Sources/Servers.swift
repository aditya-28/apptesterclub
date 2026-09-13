import Foundation
import SwiftUI

/// One AppTesterClub instance this app can talk to.
///
/// Several are supported deliberately: a contractor needs their own server and
/// a client's side by side, and that is a day-one requirement rather than a
/// later refinement.
struct Server: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var url: URL
    var token: String

    /// What to show when the operator has not named it — the host is more
    /// recognisable than a URL with a scheme and path attached.
    var displayName: String {
        name.isEmpty ? (url.host() ?? url.absoluteString) : name
    }
}

/// Servers live in UserDefaults rather than the keychain for now.
///
/// The token is a capability: it can read the catalogue and push builds to one
/// instance. That is worth protecting, and the keychain is the right home for
/// it — it is on the roadmap and called out in the README rather than quietly
/// left undone.
@MainActor
@Observable
final class ServerStore {
    private(set) var servers: [Server] = []
    var selectedID: Server.ID?

    private let key = "club.apptester.servers"
    private let selectedKey = "club.apptester.selected"

    var selected: Server? {
        servers.first { $0.id == selectedID } ?? servers.first
    }

    init() {
        load()
        if servers.isEmpty, let seeded = Self.seededFromBuild() {
            // A build made for one instance can carry it, so the person who
            // built it never sees a pairing screen.
            servers = [seeded]
            save()
        }
        selectedID = UUID(uuidString: UserDefaults.standard.string(forKey: selectedKey) ?? "")
            ?? servers.first?.id
    }

    private static func seededFromBuild() -> Server? {
        let bundle = Bundle.main
        guard
            let raw = bundle.object(forInfoDictionaryKey: "DefaultServerURL") as? String,
            let token = bundle.object(forInfoDictionaryKey: "DefaultServerToken") as? String,
            !raw.isEmpty, !token.isEmpty,
            let url = URL(string: raw)
        else { return nil }
        return Server(name: url.host() ?? "", url: url, token: token)
    }

    func add(_ server: Server) {
        // Re-pairing the same instance should replace it, not stack duplicates.
        if let i = servers.firstIndex(where: { $0.url == server.url }) {
            servers[i] = server
            selectedID = server.id
        } else {
            servers.append(server)
            selectedID = server.id
        }
        save()
    }

    func remove(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        if selectedID == server.id { selectedID = servers.first?.id }
        save()
    }

    func select(_ server: Server) {
        selectedID = server.id
        UserDefaults.standard.set(server.id.uuidString, forKey: selectedKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Server].self, from: data)
        else { return }
        servers = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: key)
        }
        UserDefaults.standard.set(selectedID?.uuidString, forKey: selectedKey)
    }
}

/// Pairing link, as produced by an instance's `/pair` page.
///
///     apptesterclub://pair?url=https%3A%2F%2Fbuilds.example.com&token=abc123
///
/// Typing a 48-character token on a phone keyboard is the worst part of setting
/// one of these up, so the scanner exists to avoid it entirely.
enum PairingLink {
    static let scheme = "apptesterclub"

    static func parse(_ url: URL) -> Server? {
        guard url.scheme == scheme, url.host == "pair",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = parts.queryItems?.first(where: { $0.name == "url" })?.value,
              let token = parts.queryItems?.first(where: { $0.name == "token" })?.value,
              let server = URL(string: raw),
              !token.isEmpty
        else { return nil }

        // Anything but HTTPS cannot install a build anyway: iOS refuses
        // over-the-air install over plain HTTP.
        guard server.scheme == "https" else { return nil }

        let name = parts.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
        return Server(name: name, url: server, token: token)
    }
}
