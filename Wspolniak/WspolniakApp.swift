import SwiftUI

@main
struct WspolniakApp: App {
    @State private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView(authStore: authStore)
                .task { await authStore.restoreSession() }
                .onOpenURL { url in
                    Task { await authStore.handleUniversalLink(url) }
                }
        }
    }
}

// Korzeń aplikacji (Faza 2): sesja → powłoka, brak → ekran logowania.
// .unknown widoczny chwilę przy starcie, dopóki czytamy Keychain.
struct RootView: View {
    let authStore: AuthStore

    var body: some View {
        switch authStore.state {
        case .unknown:
            Color.wspBackground.ignoresSafeArea()
        case .loggedOut:
            LoginView(authStore: authStore)
        case .loggedIn:
            ShellView(authStore: authStore)
        }
    }
}
