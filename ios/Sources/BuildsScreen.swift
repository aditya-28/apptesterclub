import SwiftUI

@MainActor
@Observable
final class Catalog {
    var apps: [CatalogApp] = []
    var failure: String?
    var isLoading = false
    /// Separates "nothing pushed yet" from "we have not looked yet", which
    /// otherwise render identically and make an empty screen look broken.
    var hasLoaded = false

    func reload(server: Server?) async {
        guard let server else {
            apps = []
            failure = APIError.noServer.localizedDescription
            hasLoaded = true
            return
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            apps = try await API(server: server).apps()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct BuildsScreen: View {
    let store: ServerStore
    @State private var catalog = Catalog()

    var body: some View {
        List {
            if let failure = catalog.failure {
                Text(failure)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metric.md)
                    .card()
                    .plainRow()
            }

            ForEach(catalog.apps) { app in
                AppRow(app: app, serverKey: store.selected?.id.uuidString ?? "")
            }

            if catalog.hasLoaded && catalog.apps.isEmpty && catalog.failure == nil {
                Text("No builds yet. Run atc push after a build and it lands here.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metric.md)
                    .plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { Palette.base.ignoresSafeArea() }
        .navigationTitle(store.selected?.displayName ?? "Builds")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await catalog.reload(server: store.selected) }
        .overlay {
            if catalog.isLoading && catalog.apps.isEmpty {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: store.selectedID) { await catalog.reload(server: store.selected) }
    }
}

/// Rounded-square icon, falling back to a glyph when a build carries none.
struct AppIcon: View {
    let url: URL?
    let symbol: String
    var side: CGFloat = 52

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side * 0.226))
        .overlay {
            RoundedRectangle(cornerRadius: side * 0.226)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        }
    }

    private var placeholder: some View {
        ZStack {
            Palette.surface2
            Image(systemName: symbol)
                .font(.system(size: side * 0.42, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
        }
    }
}

/// One row per app, not per build. Standing at your desk the question is "is my
/// phone current?", not "what were the last nine builds" — that is behind the row.
private struct AppRow: View {
    let app: CatalogApp
    let serverKey: String

    @State private var installer: Installer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(app: CatalogApp, serverKey: String) {
        self.app = app
        self.serverKey = serverKey
        // Keyed per server as well as per app, so the same app on two instances
        // does not share one "what is installed" record.
        _installer = State(initialValue: Installer(
            key: "\(serverKey).\(app.slug)",
            urlScheme: app.latest?.urlScheme))
    }

    var body: some View {
        NavigationLink {
            HistoryScreen(app: app, installer: installer)
        } label: {
            HStack(spacing: Metric.md) {
                AppIcon(url: app.iconUrl, symbol: app.symbolName)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    if let latest = app.latest {
                        Text("Version \(latest.version) (\(latest.buildNumber))")
                            .font(.system(size: 12, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }

                    Text(detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.textTertiary)
                }

                Spacer(minLength: Metric.sm)
                trailing
            }
            .padding(Metric.md)
            .card()
        }
        .buttonStyle(.plain)
        .plainRow()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { installer.refresh(for: app) }
        }
    }

    private var detail: String {
        let n = app.builds.count
        var parts = [app.platformLabel]
        if let latest = app.latest { parts.append(latest.shortSize) }
        parts.append("\(n) build\(n == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        switch installer.phase {
        case .working(let action):
            VStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text(action == .update ? "Updating" : "Installing")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(width: 74)

        case .unconfirmed:
            Button("Check") { installer.reset() }.buttonStyle(QuietButton())

        case .failed:
            Button("Retry") { installer.reset() }.buttonStyle(QuietButton())

        case .idle, .done:
            let action = installer.action(for: app)
            let tap = {
                guard let latest = app.latest else { return }
                if action == .viewOnly { openURL(latest.installURL) }
                else { installer.perform(action, build: latest) }
            }
            // Open is the resting state; Install and Update are the call to action.
            if action == .open {
                Button(action.title, action: tap).buttonStyle(QuietButton())
            } else {
                Button(action.title, action: tap).buttonStyle(PrimaryButton())
            }
        }
    }
}
