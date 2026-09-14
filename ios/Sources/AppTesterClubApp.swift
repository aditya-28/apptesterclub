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
                    await requestPush()
                }
                .onOpenURL { url in
                    // Pairing links open the app directly, so scanning with the
                    // system camera works as well as scanning in Settings.
                    if let server = PairingLink.parse(url) { store.add(server) }
                }
        }
    }

    /// Asking APNs for a token before the user has granted permission returns
    /// one Apple will not deliver to, so wait for the answer.
    private func requestPush() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
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
