import SwiftUI

// Powłoka aplikacji (Faza 1): główna nawigacja sterowana feature toggles
// instancji. Layout adaptacyjny od pierwszego dnia — NavigationSplitView daje
// sidebar na iPadzie i stos na iPhonie (baza pod Fazę 12).
// Konfiguracja pobierana z instancji; przy braku dostępu (np. 401 bez sesji
// w Fazie 1) spadamy na domyślne flagi backendu.

struct ShellView: View {
    @State private var config: InstanceConfig = .fallback
    @State private var selectedSection: ShellSection?

    private var sections: [ShellSection] {
        ShellSections.sections(for: config)
    }

    var body: some View {
        NavigationSplitView {
            List(sections, selection: $selectedSection) { section in
                Label {
                    Text(section.title)
                        .font(.wspBody(18))
                        .foregroundStyle(Color.wspText)
                } icon: {
                    Image(systemName: section.symbolName)
                        .foregroundStyle(Color.wspPrimary)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Wspólniak")
        } detail: {
            detail
        }
        .task { await loadInstanceConfig() }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedSection {
            SectionPlaceholderView(section: selectedSection)
        } else {
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
    }

    private func loadInstanceConfig() async {
        let client = APIClient(baseURL: AppConfig.baseURL)
        do {
            config = try await client.fetchInstanceConfig()
        } catch {
            // Faza 1: bez sesji admina endpoint flag zwraca 401 — zostają
            // domyślne flagi backendu (wszystko ON, AI OFF).
            config = .fallback
        }
    }
}
