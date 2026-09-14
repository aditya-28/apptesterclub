import Foundation

/// Reads the build catalogue from one instance. This client never writes a
/// build — those arrive through the `atc` command on the machine that compiled
/// them, which is the only place the signing material exists.

extension Date {
    /// "just now", then "2 minutes ago", "1 hour ago", "3 days ago".
    ///
    /// The system's relative format produces "in 0 seconds" for anything within
    /// a second or so of the present, which is both wrong in tense and useless
    /// to read, so the first minute is handled here instead.
    var ago: String {
        let seconds = Date().timeIntervalSince(self)
        if seconds < 60 { return "just now" }
        return formatted(.relative(presentation: .numeric))
    }
}

struct Build: Codable, Sendable, Identifiable, Hashable {
    let shareToken: String
    let version: String
    let buildNumber: String
    let fileName: String
    let fileSize: Int64
    let notes: String?
    let gitSha: String?
    let branch: String?
    let minOs: String?
    /// A note a person added after the build was pushed, as opposed to `notes`,
    /// which is the release note supplied at upload.
    let userNote: String?
    let urlScheme: String?
    let iconUrl: URL?
    let profileType: String?
    let profileExpiresAt: Date?
    let deviceCount: Int?
    let createdAt: Date
    let installURL: URL
    /// A ready-made `itms-services://` URL on iOS, the binary itself elsewhere.
    /// The server forms it so every client agrees on the OTA rules.
    let installDirectURL: URL

    var id: String { shareToken }

    var shortSize: String {
        let mb = Double(fileSize) / 1_048_576
        return mb < 1 ? "\(fileSize / 1024) KB" : String(format: "%.1f MB", mb)
    }

    var expiresInDays: Int? {
        guard let expiry = profileExpiresAt else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }

    var isExpired: Bool { (expiresInDays ?? 1) < 0 }

    /// "2 minutes ago" reads faster than a timestamp when the question is
    /// really "is this fresh?".
    /// Numeric rather than named: "1 day ago" is what you want to read here,
    /// where named would say "yesterday" and lose the scale at a glance.
    var relativeAge: String { createdAt.ago }
}

struct CatalogApp: Codable, Sendable, Identifiable, Hashable {
    let slug: String
    let name: String
    let platform: String
    let bundleId: String?
    let iconUrl: URL?
    let builds: [Build]

    var id: String { slug }
    var latest: Build? { builds.first }

    var platformLabel: String {
        switch platform {
        case "ios": "iOS"
        case "macos": "macOS"
        case "android": "Android"
        default: platform.capitalized
        }
    }

    var symbolName: String {
        switch platform {
        case "ios": "iphone"
        case "macos": "laptopcomputer"
        case "android": "candybarphone"
        default: "app.dashed"
        }
    }
}

enum APIError: LocalizedError {
    case noServer
    case unauthorized
    case status(Int)
    case offline

    var errorDescription: String? {
        switch self {
        case .noServer: "No server yet. Add one in Settings."
        case .unauthorized: "That server rejected the token. Check it in Settings."
        case .status(let code): "The server returned \(code)."
        case .offline: "Could not reach the server."
        }
    }
}

struct API: Sendable {
    let server: Server
    var session: URLSession = .shared

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct Catalog: Decodable { let apps: [CatalogApp] }

    func apps() async throws -> [CatalogApp] {
        let data = try await get("api/builds")
        return try Self.decoder.decode(Catalog.self, from: data).apps
    }

    /// Adds or replaces the note on a build. The server appends rather than
    /// rewrites, so the change is readable immediately.
    func saveNote(_ text: String, on build: Build) async throws {
        var request = signed("api/builds/\(build.shareToken)/note")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["text": text])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode) }
    }

    /// Registers this device for push. Harmless if the instance has no APNs key
    /// configured — it simply records the token and never sends anything.
    func register(deviceToken: String, sandbox: Bool) async {
        var request = signed("api/devices")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode([
            "token": deviceToken,
            "platform": "ios",
            "environment": sandbox ? "sandbox" : "production",
        ])
        _ = try? await session.data(for: request)
    }

    private func signed(_ path: String) -> URLRequest {
        var request = URLRequest(url: server.url.appending(path: path))
        request.setValue("Bearer \(server.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func get(_ path: String) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: signed(path))
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode) }
        return data
    }
}
