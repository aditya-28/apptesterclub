import SwiftUI

/// Apps moved out of the way.
///
/// Nothing is deleted — the builds are still on the server and still
/// installable from here. This exists because a list of twenty-four apps when
/// you are testing two is noise, and hiding the other twenty-two is not the
/// same as wanting them gone.
struct ArchiveScreen: View {
    /// The whole catalogue, not a pre-filtered list. Filtering here means the
    /// screen reacts when something is restored; capturing the filtered array at
    /// navigation time left the row sitting there afterwards, which read as the
    /// restore having failed.
    let allApps: [CatalogApp]
    let prefs: Preferences
    let installerFor: (CatalogApp) -> Installer

    @Environment(\.dismiss) private var dismiss

    private var apps: [CatalogApp] { prefs.archivedApps(allApps) }

    var body: some View {
        List {
            ForEach(apps) { app in
                ArchivedRow(
                    app: app,
                    installer: installerFor(app),
                    onRestore: {
                        withAnimation { prefs.toggleArchive(app.slug) }
                        // Nothing left to look at once the last one is back.
                        if prefs.archivedApps(allApps).isEmpty { dismiss() }
                    })
            }

            if apps.isEmpty {
                Text("Nothing archived. Swipe an app left on the Builds screen to move it here.")
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
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Deliberately not the same row as the main list. Here the question is "do I
/// want this back?", so Restore is the visible action and installing is behind
/// the row, rather than the other way round.
private struct ArchivedRow: View {
    let app: CatalogApp
    let installer: Installer
    let onRestore: () -> Void

    var body: some View {
        ZStack {
            NavigationLink {
                HistoryScreen(app: app, installer: installer)
            } label: { EmptyView() }
                .opacity(0)

            HStack(spacing: Metric.md) {
                AppIcon(url: app.iconUrl, symbol: app.symbolName, side: 44)
                    .opacity(0.75)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    if let latest = app.latest {
                        Text("\(latest.version) (\(latest.buildNumber)) · \(latest.relativeAge)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Metric.sm)

                Button("Restore", action: onRestore)
                    .buttonStyle(QuietButton())
            }
            .padding(Metric.md)
            .card()
        }
        .plainRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onRestore) {
                Label("Restore", systemImage: "tray.and.arrow.up")
            }
            .tint(Palette.success)
        }
        .contextMenu {
            Button(action: onRestore) {
                Label("Move back to Builds", systemImage: "tray.and.arrow.up")
            }
        }
    }
}
