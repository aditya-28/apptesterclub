import SwiftUI
import UIKit

/// Remembers which build this app installed, per app.
///
/// iOS will not tell one app the version of another. `canOpenURL` answers
/// installed or not and nothing else, so the only way to say "you have 1.2,
/// 1.3 is out" is to remember what we put there.
///
/// A build installed some other way — Xcode, a Safari link — is invisible to
/// this record, so the button offers Update rather than Open. Updating to a
/// version you already have is harmless, which is why that is the safe
/// direction to be wrong in.
@MainActor
enum InstalledRegistry {
    private static let prefix = "club.apptester.installed."

    static func token(forApp key: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + key)
    }

    static func record(_ token: String, forApp key: String) {
        UserDefaults.standard.set(token, forKey: prefix + key)
    }
}

enum AppAction: Equatable {
    case install, update, open, viewOnly

    var title: String {
        switch self {
        case .install: "Install"
        case .update: "Update"
        case .open: "Open"
        case .viewOnly: "View"
        }
    }
}

/// Drives one app from Install or Update through to Open.
///
/// Three things make this less obvious than it looks:
///
/// 1. SwiftUI's `openURL` silently declines `itms-services://`. UIKit's
///    `open(_:options:completionHandler:)` fires it — and reports `false` even
///    when the install starts, so the result cannot be trusted either.
///
/// 2. iOS never announces that an install finished. The only signal is
///    `canOpenURL` against the app's own scheme, which requires that scheme in
///    `LSApplicationQueriesSchemes`. So we poll for the change.
///
/// 3. An **update** has no not-installed-to-installed edge to wait for. There
///    is a different one: iOS removes the old copy before laying down the new,
///    so the scheme goes true, false, true. We watch for that dip, which is why
///    updates poll faster than fresh installs.
@MainActor
@Observable
final class Installer {
    enum Phase: Equatable {
        case idle
        case working(AppAction)
        case done
        /// Handed to iOS but never confirmed. It probably worked; we could not
        /// see it — usually because the build declares no URL scheme.
        case unconfirmed
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let key: String
    private let urlScheme: String?
    private var poller: Task<Void, Never>?

    /// Not cancelled in `deinit`: that is a nonisolated context and cannot
    /// touch main-actor state. The loop holds a weak reference and falls out on
    /// its own when the row goes away.
    init(key: String, urlScheme: String?) {
        self.key = key
        self.urlScheme = urlScheme
    }

    var isInstalled: Bool {
        guard let scheme = urlScheme, let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func action(for app: CatalogApp) -> AppAction {
        guard app.platform == "ios" else { return .viewOnly }
        guard isInstalled else { return .install }
        guard let latest = app.latest else { return .open }
        return InstalledRegistry.token(forApp: key) == latest.shareToken ? .open : .update
    }

    func perform(_ action: AppAction, build: Build) {
        switch action {
        case .open: openApp()
        case .viewOnly: break
        case .install, .update: start(build: build)
        }
    }

    func openApp() {
        guard let scheme = urlScheme, let url = URL(string: "\(scheme)://") else { return }
        UIApplication.shared.open(url, options: [:]) { _ in }
    }

    func reset() {
        poller?.cancel()
        poller = nil
        phase = .idle
    }

    /// Re-check after returning to the foreground: the install happened while
    /// another app was frontmost.
    func refresh(for app: CatalogApp) {
        guard case .working = phase else { return }
        if isInstalled, InstalledRegistry.token(forApp: key) == app.latest?.shareToken {
            phase = .done
        }
    }

    private func start(build: Build) {
        let wasInstalled = isInstalled
        phase = .working(wasInstalled ? .update : .install)

        UIApplication.shared.open(build.installDirectURL, options: [:]) { [weak self] _ in
            // The boolean lies for itms-services, so decide from whether there
            // is anything to probe rather than from the result.
            guard let self else { return }
            guard self.urlScheme != nil else {
                self.phase = .unconfirmed
                return
            }
            self.watch(startedInstalled: wasInstalled, token: build.shareToken)
        }
    }

    private func watch(startedInstalled: Bool, token: String) {
        poller?.cancel()
        // An update shows only a brief dip, so sample it more often than a
        // fresh install, which just has to appear once.
        let interval: Duration = startedInstalled ? .milliseconds(600) : .seconds(2)
        poller = Task { [weak self] in
            let began = ContinuousClock.now
            var sawItGo = false
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                let now = self.isInstalled

                if startedInstalled {
                    if !now { sawItGo = true }
                    if sawItGo && now { return self.finish(token) }
                } else if now {
                    return self.finish(token)
                }

                if ContinuousClock.now - began > .seconds(120) {
                    // Out of patience. For an update the dip is short and easy
                    // to miss, so take the likely outcome — the row still
                    // offers Reinstall if this guessed wrong.
                    if startedInstalled && self.isInstalled { self.finish(token) }
                    else { self.phase = .unconfirmed }
                    return
                }
            }
        }
    }

    private func finish(_ token: String) {
        InstalledRegistry.record(token, forApp: key)
        phase = .done
    }
}
