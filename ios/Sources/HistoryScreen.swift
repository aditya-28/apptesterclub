import SwiftUI

/// Every build ever pushed for one app, newest first.
///
/// The previous screen answers "is my phone current?". This one answers "what
/// changed, and can I go back?" — so it carries notes, commit and size, and
/// lets any version be installed. Finding the build where something broke is
/// the reason to keep history at all.
struct HistoryScreen: View {
    let app: CatalogApp
    let installer: Installer

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ServerStore.self) private var store: ServerStore?

    @State private var editingNote: Build?
    /// Notes edited on this screen, shown immediately rather than waiting for
    /// the next catalogue fetch.
    @State private var localNotes: [String: String] = [:]

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
                        Text("\(app.platformLabel) · \(app.builds.count) build\(app.builds.count == 1 ? "" : "s")")
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
                        note: localNotes[build.shareToken] ?? build.userNote,
                        installer: installer,
                        onEditNote: { editingNote = build })
                }
            } header: {
                Text("History")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .textCase(nil)
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
        .sheet(item: $editingNote) { build in
            NoteEditor(
                build: build,
                existing: localNotes[build.shareToken] ?? build.userNote ?? "",
                server: store?.selected) { saved in
                    localNotes[build.shareToken] = saved
                }
        }
    }

    private var installerKey: String { app.slug }
}

private struct BuildRow: View {
    let app: CatalogApp
    let build: Build
    let isLatest: Bool
    let isOnThisPhone: Bool
    let note: String?
    let installer: Installer
    let onEditNote: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: Metric.sm) {
                Text("\(build.version) (\(build.buildNumber))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)

                if isLatest { Tag(text: "Latest") }
                if isOnThisPhone { Tag(text: "On this phone", tint: Palette.success) }

                Spacer(minLength: 0)

                Text(build.relativeAge)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
            }

            if build.isExpired {
                Label("Signing expired. iOS will refuse this build.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.danger)
            } else if let days = build.expiresInDays, days <= 14 {
                Label("Signing expires in \(days) day\(days == 1 ? "" : "s").", systemImage: "clock")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.warning)
            }

            if let release = build.notes, !release.isEmpty {
                Text(release)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(subtitle)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Palette.textTertiary)

            if let note, !note.isEmpty {
                Button(action: onEditNote) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 11))
                            .padding(.top, 1)
                        Text(note)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(Metric.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface2, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Full-width so the whole strip is the target. These used to be
            // small pill buttons, which is a poor thing to aim at one-handed.
            if app.platform == "ios" && !build.isExpired {
                Button {
                    installer.perform(isOnThisPhone ? .update : .install, build: build)
                } label: {
                    Label(isOnThisPhone ? "Reinstall this version" : "Install this version",
                          systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.accent.opacity(isOnThisPhone ? 0.12 : 1),
                                    in: .rect(cornerRadius: 10))
                        .foregroundStyle(isOnThisPhone ? Palette.accent : Palette.onAccent)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Metric.sm) {
                Button(note?.isEmpty == false ? "Edit note" : "Add note", action: onEditNote)
                    .buttonStyle(QuietButton())
                Button("Share link") { openURL(build.installURL) }
                    .buttonStyle(QuietButton())
                Spacer(minLength: 0)
            }
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

/// Notes live on the server rather than the phone, so whoever else is testing
/// sees "crashes on launch" too. That is the point of writing it down.
private struct NoteEditor: View {
    let build: Build
    let existing: String
    let server: Server?
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var isSaving = false
    @State private var failure: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What should someone know about this build?",
                              text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                } footer: {
                    Text("Saved on the server, so anyone else using this instance sees it.")
                }

                if let failure {
                    Section {
                        Text(failure)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("\(build.version) (\(build.buildNumber))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save") { save() }
                    }
                }
            }
            .onAppear {
                text = existing
                focused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let server else {
            failure = APIError.noServer.localizedDescription
            return
        }
        isSaving = true
        failure = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await API(server: server).saveNote(trimmed, on: build)
                onSaved(trimmed)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
            isSaving = false
        }
    }
}
