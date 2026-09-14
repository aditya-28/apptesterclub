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
    /// On this phone, but not launchable: the build declares no URL scheme, and
    /// iOS gives no other way to open another app. Saying "Open" here would be
    /// a button that does nothing.
    case installed

    var title: String {
        switch self {
        case .install: "Install"
        case .update: "Update"
        case .open: "Open"
        case .installed: "Installed"
        case .viewOnly: "View"
        }
    }

    var isQuiet: Bool { self == .open || self == .installed || self == .viewOnly }
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

    let key: String
    private let urlScheme: String?
    private var poller: Task<Void, Never>?

    /// How long the hand-off message stays up no matter what.
    ///
    /// The moment iOS accepts an install the person leaves for the Home Screen,
    /// and resolving instantly means they come back to a button that looks like
    /// nothing happened. Holding it puts the answer where they will look.
    private let dwell: Duration = .seconds(12)

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

    /// What the button should say.
    ///
    /// Our own record comes first and `canOpenURL` second. That order matters:
    /// `canOpenURL` only answers for apps whose URL scheme is listed in
    /// `LSApplicationQueriesSchemes`, and most builds declare no scheme at all.
    /// Asking it first meant every one of those read "Install" forever, even
    /// straight after installing them. If we put a build on this phone, we know
    /// it is there.
    func action(for app: CatalogApp) -> AppAction {
        guard app.platform == "ios" else { return .viewOnly }
        guard let latest = app.latest else { return .install }

        if let installed = InstalledRegistry.token(forApp: key) {
            if installed != latest.shareToken { return .update }
            return canOpenApp ? .open : .installed
        }
        // No record. The scheme can still prove it is present — from a previous
        // install, or one done outside this app.
        return isInstalled ? .update : .install
    }

    /// Whether a build is the one this phone has.
    func isOnThisPhone(_ build: Build) -> Bool {
        InstalledRegistry.token(forApp: key) == build.shareToken
    }

    /// True while iOS is being handed the install, so callers can disable their
    /// own buttons rather than each inventing the rule.
    var isBusy: Bool {
        if case .working = phase { return true }
        return false
    }

    /// Whether this app has an update waiting, for the attention dot.
    func needsUpdate(for app: CatalogApp) -> Bool {
        action(for: app) == .update
    }

    func perform(_ action: AppAction, build: Build) {
        switch action {
        case .open: openApp()
        case .installed, .viewOnly: break
        case .install, .update: start(build: build)
        }
    }

    /// Only possible when the build declares a URL scheme. Without one there is
    /// no way to launch another app, so the caller offers this conditionally.
    var canOpenApp: Bool { urlScheme != nil }

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
        let wasInstalled = isInstalled || InstalledRegistry.token(forApp: key) != nil
        phase = .working(wasInstalled ? .update : .install)
        let began = ContinuousClock.now

        UIApplication.shared.open(build.installDirectURL, options: [:]) { [weak self] _ in
            // The boolean lies for itms-services, so decide from whether there
            // is anything to probe rather than from the result.
            guard let self else { return }
            guard self.urlScheme != nil else {
                // Nothing to probe. Record it rather than leaving the row saying
                // "Install" forever after a successful install, but hold the
                // message for the dwell so it does not resolve before the person
                // has even looked at their Home Screen.
                InstalledRegistry.record(build.shareToken, forApp: self.key)
                self.settle(after: began)
                return
            }
            self.watch(startedInstalled: wasInstalled, token: build.shareToken, began: began)
        }
    }

    /// Leaves the hand-off message up for the rest of the dwell, then resolves.
    private func settle(after began: ContinuousClock.Instant) {
        poller?.cancel()
        poller = Task { [weak self] in
            guard let self else { return }
            let elapsed = ContinuousClock.now - began
            if elapsed < self.dwell {
                try? await Task.sleep(for: self.dwell - elapsed)
            }
            guard !Task.isCancelled else { return }
            self.phase = .done
        }
    }

    private func watch(startedInstalled: Bool, token: String, began: ContinuousClock.Instant) {
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
                    if sawItGo && now { return self.finish(token, began: began) }
                } else if now {
                    return self.finish(token, began: began)
                }

                if ContinuousClock.now - began > .seconds(120) {
                    // Out of patience. For an update the dip is short and easy
                    // to miss, so take the likely outcome — the row still
                    // offers Reinstall if this guessed wrong.
                    if startedInstalled && self.isInstalled { self.finish(token, began: began) }
                    else { self.phase = .unconfirmed }
                    return
                }
            }
        }
    }

    private func finish(_ token: String, began: ContinuousClock.Instant) {
        InstalledRegistry.record(token, forApp: key)
        settle(after: began)
    }
}
