import SwiftUI

// Powłoka aplikacji (Faza 1): główna nawigacja sterowana feature toggles
// instancji. Layout adaptacyjny:
// - iPhone (compact): klasyczny NavigationStack — tapnięcie sekcji pewnie
//   pcha ekran z przyciskiem wstecz (NavigationSplitView na wąskim ekranie
//   bywa zawodne i nie daje „wstecz").
// - iPad (regular): NavigationSplitView z sidebarem (baza pod Fazę 12).
// Od Fazy 2: przychodzi z sesją (AuthStore) — żądania idą z ciasteczkiem,
// wylogowanie czyści sesję i wraca na ekran logowania. Sekcja Feed od Fazy 3
// ma własny ekran; reszta sekcji to wciąż placeholdery (kolejne fazy).

struct ShellView: View {
    let authStore: AuthStore

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var config: InstanceConfig = .fallback
    @State private var selectedSection: ShellSection?
    @State private var showsLogoutConfirmation = false

    private var sections: [ShellSection] {
        ShellSections.sections(for: config)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                NavigationStack {
                    iphoneList
                        .navigationTitle("Wspólniak")
                        .toolbar { logoutButton }
                }
            } else {
                NavigationSplitView {
                    ipadList
                        .listStyle(.sidebar)
                        .navigationTitle("Wspólniak")
                        .toolbar { logoutButton }
                } detail: {
                    detail
                }
            }
        }
        .confirmationDialog(
            "Wylogować się?",
            isPresented: $showsLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Wyloguj się", role: .destructive) {
                Task { await authStore.logout() }
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Wrócisz na ekran logowania, a sesja zniknie z tego urządzenia.")
        }
        .task { await loadInstanceConfig() }
    }

    // MARK: — Lista sekcji

    @ViewBuilder
    private var iphoneList: some View {
        List(sections) { section in
            NavigationLink {
                sectionDetail(section)
            } label: {
                sectionRow(section)
            }
        }
    }

    private var ipadList: some View {
        List(sections, selection: $selectedSection) { section in
            sectionRow(section)
        }
    }

    private func sectionRow(_ section: ShellSection) -> some View {
        Label {
            Text(section.title)
                .font(.wspBody(18))
                .foregroundStyle(Color.wspText)
        } icon: {
            Image(systemName: section.symbolName)
                .foregroundStyle(Color.wspPrimary)
        }
    }

    private var logoutButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showsLogoutConfirmation = true
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityLabel("Wyloguj się")
        }
    }

    // MARK: — Treść

    @ViewBuilder
    private func sectionDetail(_ section: ShellSection) -> some View {
        switch section.kind {
        case .feed:
            FeedView(authStore: authStore)
        default:
            SectionPlaceholderView(section: section)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedSection {
            sectionDetail(selectedSection)
        } else {
            welcome
        }
    }

    private var welcome: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.wspPrimary)
            Text("Witaj w Wspólniaku")
                .font(.wspTitle())
                .foregroundStyle(Color.wspText)
            Text("Wybierz sekcję z menu, aby zobaczyć treść.")
                .font(.wspBody(15))
                .foregroundStyle(Color.wspMutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wspBackground)
    }

    private func loadInstanceConfig() async {
        let client = APIClient(baseURL: AppConfig.baseURL, sessionCookie: authStore.sessionToken)
        do {
            config = try await client.fetchInstanceConfig()
        } catch {
            // Flagi admina są tylko dla roli admin — członek dostaje 401,
            // zostają domyślne flagi backendu (wszystko ON, AI OFF).
            config = .fallback
        }
    }
}
