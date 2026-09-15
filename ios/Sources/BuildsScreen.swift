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
    var lastChecked: Date?

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
            lastChecked = Date()
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct BuildsScreen: View {
    let store: ServerStore

    @State private var catalog = Catalog()
    @State private var prefs = Preferences(serverKey: "")
    @State private var installers: [String: Installer] = [:]
    @State private var isEditing = false

    private var serverKey: String { store.selected?.id.uuidString ?? "" }

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

            if let checked = catalog.lastChecked {
                // Wrapped in a timeline so "2 minutes ago" keeps counting while
                // the app sits open, rather than freezing on whatever it said
                // when the view was last built.
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text("Last checked \(checked.ago)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
            }

            let arranged = prefs.arrange(catalog.apps)

            if !arranged.pinned.isEmpty {
                Section {
                    ForEach(arranged.pinned) { app in row(app) }
                        .onMove { from, to in move(arranged.pinned, from, to) }
                } header: {
                    sectionHeader("Pinned", systemImage: "pin.fill")
                }
            }

            if !arranged.rest.isEmpty {
                Section {
                    ForEach(arranged.rest) { app in row(app) }
                        .onMove { from, to in move(arranged.rest, from, to) }
                } header: {
                    // No point labelling the second section when it is the only one.
                    arranged.pinned.isEmpty ? nil : sectionHeader("All apps", systemImage: "square.stack")
                }
            }

            if catalog.hasLoaded && catalog.apps.isEmpty && catalog.failure == nil {
                Text("No builds yet. Run atc push after a build and it lands here.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metric.md)
                    .plainRow()
            }

            let archived = prefs.archivedApps(catalog.apps)
            if !archived.isEmpty {
                ZStack {
                    NavigationLink {
                        ArchiveScreen(allApps: catalog.apps, prefs: prefs, installerFor: installer(for:))
                    } label: { EmptyView() }
                        .opacity(0)

                    HStack(spacing: Metric.sm) {
                        Image(systemName: "archivebox")
                        Text("Archived")
                        Spacer()
                        Text("\(archived.count)")
                            .monospacedDigit()
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(Metric.md)
                    .card()
                }
                .plainRow()
            }

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { Palette.base.ignoresSafeArea() }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ServerPicker(store: store)
            }
            ToolbarItem(placement: .topBarLeading) {
                if !catalog.apps.isEmpty {
                    Button {
                        withAnimation { isEditing.toggle() }
                    } label: {
                        Image(systemName: isEditing
                              ? "checkmark"
                              : "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(isEditing ? "Done arranging" : "Arrange apps")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await catalog.reload(server: store.selected) }
                } label: {
                    if catalog.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(catalog.isLoading)
                .accessibilityLabel("Check for new builds")
            }
        }
        .refreshable { await catalog.reload(server: store.selected) }
        .overlay {
            if catalog.isLoading && catalog.apps.isEmpty {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: store.selectedID) {
            prefs = Preferences(serverKey: serverKey)
            await catalog.reload(server: store.selected)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.textSecondary)
            .textCase(nil)
    }

    private func row(_ app: CatalogApp) -> some View {
        AppRow(
            app: app,
            installer: installer(for: app),
            isPinned: prefs.isPinned(app.slug),
            isArchived: false,
            onTogglePin: { withAnimation { prefs.togglePin(app.slug) } },
            onToggleArchive: { withAnimation { prefs.toggleArchive(app.slug) } })
    }

    /// One installer per app, kept here rather than in the row so its state
    /// survives the list re-rendering after a refresh.
    private func installer(for app: CatalogApp) -> Installer {
        let key = "\(serverKey).\(app.slug)"
        if let existing = installers[key] { return existing }
        let made = Installer(key: key, urlScheme: app.latest?.urlScheme)
        installers[key] = made
        return made
    }

    private func move(_ section: [CatalogApp], _ from: IndexSet, _ to: Int) {
        var slugs = section.map(\.slug)
        slugs.move(fromOffsets: from, toOffset: to)
        prefs.reorder(slugs)
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

/// One row per app. Standing at your desk the question is "is my phone
/// current?", not "what were the last nine builds" — that is behind the row.
struct AppRow: View {
    let app: CatalogApp
    let installer: Installer
    let isPinned: Bool
    let isArchived: Bool
    let onTogglePin: () -> Void
    let onToggleArchive: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            // An invisible link rather than a NavigationLink label: the label
            // form adds a disclosure chevron that cannot be turned off, and it
            // crowds the action button on the right.
            NavigationLink {
                HistoryScreen(app: app, installer: installer)
            } label: { EmptyView() }
                .opacity(0)

            content
        }
        .plainRow()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { installer.refresh(for: app) }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isArchived {
                Button(action: onTogglePin) {
                    Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                }
                .tint(Palette.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onToggleArchive) {
                Label(isArchived ? "Restore" : "Archive",
                      systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(isArchived ? Palette.success : Palette.textTertiary)
        }
        .contextMenu {
            if !isArchived {
                Button(action: onTogglePin) {
                    Label(isPinned ? "Unpin" : "Pin to top", systemImage: isPinned ? "pin.slash" : "pin")
                }
            }
            Button(action: onToggleArchive) {
                Label(isArchived ? "Move back" : "Archive",
                      systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            if let latest = app.latest {
                Button {
                    openURL(latest.installURL)
                } label: {
                    Label("Open install page", systemImage: "safari")
                }
            }
        }
    }

    private var content: some View {
        HStack(spacing: Metric.md) {
            AppIcon(url: app.iconUrl, symbol: app.symbolName)
                .overlay(alignment: .topLeading) {
                    // The attention dot. Top-left rather than the usual right,
                    // so it never sits under the action button.
                    if needsAttention {
                        Circle()
                            .fill(Palette.danger)
                            .frame(width: 11, height: 11)
                            .overlay { Circle().strokeBorder(Palette.base, lineWidth: 2) }
                            .offset(x: -3, y: -3)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                if installer.isBusy {
                    // The person is about to leave for the Home Screen, so say
                    // where the result will be rather than just spinning.
                    Text("Sent to iOS — check your Home Screen")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else if let latest = app.latest {
                    Text("\(latest.version) (\(latest.buildNumber)) · \(latest.relativeAge)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(needsAttention ? Palette.danger : Palette.textSecondary)
                        .lineLimit(1)
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

    private var needsAttention: Bool {
        if case .idle = installer.phase { return installer.needsUpdate(for: app) }
        if case .done = installer.phase { return installer.needsUpdate(for: app) }
        return false
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
        case .working:
            ProgressView()
                .controlSize(.small)
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
            if action.isQuiet {
                Button(action.title, action: tap)
                    .buttonStyle(QuietButton())
                    .disabled(action == .installed)
            } else {
                Button(action.title, action: tap).buttonStyle(PrimaryButton())
            }
        }
    }
}
