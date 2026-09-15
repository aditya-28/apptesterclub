import SwiftUI

/// The server name in the title, and a way to change which one you are looking
/// at without going to Settings first.
///
/// With one server it is a plain label: a menu offering a single choice is a
/// control that does nothing, and the chevron would promise otherwise.
struct ServerPicker: View {
    let store: ServerStore
    @State private var renaming = false

    var body: some View {
        if store.servers.count > 1 {
            Menu {
                Picker("Server", selection: selection) {
                    ForEach(store.servers) { server in
                        // Two lines so instances on similar hosts stay
                        // distinguishable once renamed to something friendly.
                        VStack(alignment: .leading) {
                            Text(server.displayName)
                            Text(server.subtitle)
                        }
                        .tag(server.id as Server.ID?)
                    }
                }
                Divider()
                Button {
                    renaming = true
                } label: {
                    Label("Rename this server", systemImage: "pencil")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(store.selected?.displayName ?? "Builds")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Palette.textPrimary)
            }
            .sheet(isPresented: $renaming) { renameSheet }
        } else {
            Button {
                renaming = true
            } label: {
                Text(store.selected?.displayName ?? "Builds")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            .disabled(store.selected == nil)
            .sheet(isPresented: $renaming) { renameSheet }
        }
    }

    private var selection: Binding<Server.ID?> {
        Binding(
            get: { store.selected?.id },
            set: { id in
                guard let server = store.servers.first(where: { $0.id == id }) else { return }
                store.select(server)
            })
    }

    @ViewBuilder
    private var renameSheet: some View {
        if let server = store.selected {
            RenameServerSheet(store: store, server: server)
        }
    }
}

struct RenameServerSheet: View {
    let store: ServerStore
    let server: Server

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Work, Client, Staging…", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shown in the title. Leave it blank to use \(server.subtitle) instead.")
                }
            }
            .navigationTitle("Rename server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear {
                name = server.name
                focused = true
            }
        }
        .presentationDetents([.height(220)])
    }

    private func save() {
        store.rename(server, to: name)
        dismiss()
    }
}
