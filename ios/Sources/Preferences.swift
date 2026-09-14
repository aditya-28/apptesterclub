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
    private(set) var order: [String] = []

    private let serverKey: String

    init(serverKey: String) {
        self.serverKey = serverKey
        pinned = Set(UserDefaults.standard.stringArray(forKey: key("pinned")) ?? [])
        order = UserDefaults.standard.stringArray(forKey: key("order")) ?? []
    }

    private func key(_ name: String) -> String { "club.apptester.\(name).\(serverKey)" }

    func isPinned(_ slug: String) -> Bool { pinned.contains(slug) }

    func togglePin(_ slug: String) {
        if pinned.contains(slug) { pinned.remove(slug) } else { pinned.insert(slug) }
        UserDefaults.standard.set(Array(pinned), forKey: key("pinned"))
    }

    /// Apps split into the two sections the list renders, each in the person's
    /// own order. Anything never seen before sorts to the end of its section by
    /// name, so a newly pushed app appears without disturbing what you arranged.
    func arrange(_ apps: [CatalogApp]) -> (pinned: [CatalogApp], rest: [CatalogApp]) {
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
        return (sort(apps.filter { pinned.contains($0.slug) }),
                sort(apps.filter { !pinned.contains($0.slug) }))
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
