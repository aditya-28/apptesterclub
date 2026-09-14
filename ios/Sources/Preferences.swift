import Foundation
import SwiftUI

/// Pinning and ordering, per server.
///
/// Deliberately local rather than on the instance: which apps you care about
/// this week is a property of the person holding the phone, not of the server.
/// Two people sharing an instance should not fight over each other's order.
@MainActor
@Observable
final class Preferences {
    private(set) var pinned: Set<String> = []
    private(set) var archived: Set<String> = []
    private(set) var order: [String] = []

    private let serverKey: String

    init(serverKey: String) {
        self.serverKey = serverKey
        pinned = Set(UserDefaults.standard.stringArray(forKey: key("pinned")) ?? [])
        archived = Set(UserDefaults.standard.stringArray(forKey: key("archived")) ?? [])
        order = UserDefaults.standard.stringArray(forKey: key("order")) ?? []
    }

    private func key(_ name: String) -> String { "club.apptester.\(name).\(serverKey)" }

    func isPinned(_ slug: String) -> Bool { pinned.contains(slug) }
    func isArchived(_ slug: String) -> Bool { archived.contains(slug) }

    func togglePin(_ slug: String) {
        if pinned.contains(slug) {
            pinned.remove(slug)
        } else {
            pinned.insert(slug)
            // Pinned and archived are opposite intentions, so one clears the other.
            archived.remove(slug)
            save("archived", archived)
        }
        save("pinned", pinned)
    }

    func toggleArchive(_ slug: String) {
        if archived.contains(slug) {
            archived.remove(slug)
        } else {
            archived.insert(slug)
            pinned.remove(slug)
            save("pinned", pinned)
        }
        save("archived", archived)
    }

    private func save(_ name: String, _ value: Set<String>) {
        UserDefaults.standard.set(Array(value), forKey: key(name))
    }

    /// Apps split into the two sections the list renders, each in the person's
    /// own order. Anything never seen before sorts to the end of its section by
    /// name, so a newly pushed app appears without disturbing what you arranged.
    func arrange(_ apps: [CatalogApp]) -> (pinned: [CatalogApp], rest: [CatalogApp]) {
        let visible = apps.filter { !archived.contains($0.slug) }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        func sort(_ list: [CatalogApp]) -> [CatalogApp] {
            list.sorted { a, b in
                switch (rank[a.slug], rank[b.slug]) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
            }
        }
        return (sort(visible.filter { pinned.contains($0.slug) }),
                sort(visible.filter { !pinned.contains($0.slug) }))
    }

    /// Archived apps, for the screen that exists so they are out of the way
    /// rather than gone. Nothing is deleted; the builds are still on the server.
    func archivedApps(_ apps: [CatalogApp]) -> [CatalogApp] {
        apps.filter { archived.contains($0.slug) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Records a new arrangement. Both sections are written into one list, so
    /// pinning something later keeps the position it already had.
    func reorder(_ slugs: [String]) {
        var next = slugs
        // Anything not in the moved section keeps its existing relative place.
        for slug in order where !next.contains(slug) { next.append(slug) }
        order = next
        UserDefaults.standard.set(order, forKey: key("order"))
    }
}
