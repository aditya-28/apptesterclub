import SwiftUI
import UserNotifications

@main
struct AppTesterClubApp: App {
    @State private var store = ServerStore()
    /// The only way to receive an APNs device token in a SwiftUI app: that
    /// callback arrives on an application delegate and nowhere else.
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var push

    var body: some Scene {
        WindowGroup {
            Root(store: store)
                .environment(store)
                .fontDesign(.rounded)
                .tint(Palette.accent)
                .task {
                    PushDelegate.store = store
                    await Push.shared.requestAuthorization(then: store.servers)
                }
                .onOpenURL { url in
                    if let target = PairingLink.parseOpen(url) {
                        Push.shared.pending = target
                        return
                    }
                    // Pairing links open the app directly, so scanning with the
                    // system camera works as well as scanning in Settings.
                    guard let server = PairingLink.parse(url) else { return }
                    store.add(server)
                    // Tell it about this device now rather than at the next
                    // launch, or its first build would arrive silently.
                    Task { await Push.shared.register(with: server) }
                }
        }
    }

}

struct Root: View {
    let store: ServerStore

    var body: some View {
        TabView {
            NavigationStack { BuildsScreen(store: store) }
                .tabItem { Label("Builds", systemImage: "shippingbox") }

            NavigationStack { SettingsScreen(store: store) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
