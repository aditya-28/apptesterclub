import SwiftUI

/// Apps moved out of the way.
///
/// Nothing is deleted — the builds are still on the server and still
/// installable from here. This exists because a list of twenty-four apps when
/// you are testing two is noise, and hiding the other twenty-two is not the
/// same as wanting them gone.
struct ArchiveScreen: View {
    let apps: [CatalogApp]
    let prefs: Preferences
    let installerFor: (CatalogApp) -> Installer

    var body: some View {
        List {
            ForEach(apps) { app in
                AppRow(
                    app: app,
                    installer: installerFor(app),
                    isPinned: false,
                    isArchived: true,
                    onTogglePin: {},
                    onToggleArchive: { withAnimation { prefs.toggleArchive(app.slug) } })
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
