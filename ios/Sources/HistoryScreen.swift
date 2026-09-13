import SwiftUI

/// Every build ever pushed for one app, newest first.
///
/// The previous screen answers "is my phone current?". This one answers "what
/// changed, and can I go back?" — so it carries notes, commit and size, and
/// lets any version be installed, not only the newest. Finding the build where
/// something broke is the reason to keep history at all.
struct HistoryScreen: View {
    let app: CatalogApp
    let installer: Installer

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                HStack(spacing: Metric.md) {
                    AppIcon(url: app.iconUrl, symbol: app.symbolName, side: 62)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                        if let bundleId = app.bundleId {
                            Text(bundleId)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text(app.platformLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Metric.md)
                .card()
                .plainRow()
            }

            Section {
                ForEach(Array(app.builds.enumerated()), id: \.element.id) { index, build in
                    BuildRow(
                        app: app,
                        build: build,
                        isLatest: index == 0,
                        isOnThisPhone: InstalledRegistry.token(forApp: installerKey) == build.shareToken,
                        installer: installer)
                }
            } header: {
                Text("History")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { Palette.base.ignoresSafeArea() }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { installer.refresh(for: app) }
        }
    }

    private var installerKey: String { app.slug }
}

private struct BuildRow: View {
    let app: CatalogApp
    let build: Build
    let isLatest: Bool
    let isOnThisPhone: Bool
    let installer: Installer

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Metric.sm) {
                Text("\(build.version) (\(build.buildNumber))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)

                if isLatest { Tag(text: "Latest") }
                if isOnThisPhone { Tag(text: "On this phone", tint: Palette.success) }

                Spacer(minLength: 0)

                Text(build.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
            }

            if build.isExpired {
                Text("Signing profile expired. iOS will refuse this build.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.danger)
            } else if let days = build.expiresInDays, days <= 14 {
                Text("Signing expires in \(days) day\(days == 1 ? "" : "s").")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.warning)
            }

            if let notes = build.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(subtitle)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Palette.textTertiary)

            HStack(spacing: Metric.sm) {
                if app.platform == "ios" && !build.isExpired {
                    Button(isOnThisPhone ? "Reinstall" : "Install this version") {
                        installer.perform(isOnThisPhone ? .update : .install, build: build)
                    }
                    .buttonStyle(QuietButton())
                }
                Button("Share link") { openURL(build.installURL) }
                    .buttonStyle(QuietButton())
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.md)
        .card()
        .plainRow()
    }

    private var subtitle: String {
        var parts = [build.shortSize]
        if let branch = build.branch, !branch.isEmpty { parts.append(branch) }
        if let sha = build.gitSha, sha.count >= 7 { parts.append(String(sha.prefix(7))) }
        if let minOs = build.minOs, !minOs.isEmpty { parts.append("iOS \(minOs)+") }
        if let type = build.profileType { parts.append(type) }
        return parts.joined(separator: " · ")
    }
}
