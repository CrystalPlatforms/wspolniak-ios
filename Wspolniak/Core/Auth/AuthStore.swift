import Foundation
import Observation

// Moduł AuthStore (Faza 2, drugi z trzech głębokich modułów PRD): sesja
// wyłącznie w Keychain. Magic link / kod rodzinny (mirror web /share) →
// wymiana tokenu na sesję → Keychain; start aplikacji z sesją wchodzi
// od razu zalogowany; 401 z API = sesja cofnięta → czyszczenie.

@MainActor
@Observable
final class AuthStore {

    enum AuthState: Equatable {
        case unknown      // dopiero sprawdzamy Keychain
        case loggedOut
        case loggedIn(Session)
    }

    private(set) var state: AuthState = .unknown
    private(set) var isWorking = false
    var errorMessage: String?

    private let client: APIClient
    private let keychain: KeychainSessionStore
    private let linkHosts: Set<String>

    init(
        client: APIClient = APIClient(baseURL: AppConfig.baseURL, session: .noRedirects),
        keychain: KeychainSessionStore = KeychainSessionStore()
    ) {
        self.client = client
        self.keychain = keychain
        self.linkHosts = UniversalLink.allowedHosts(baseURL: client.baseURL)
    }

    var isLoggedIn: Bool {
        if case .loggedIn = state { return true }
        return false
    }

    var sessionToken: String? {
        if case let .loggedIn(session) = state { return session.token }
        return nil
    }

    // MARK: — Cykl życia sesji

    /// Start aplikacji: istniejąca sesja z Keychain → od razu zalogowany (story 5).
    func restoreSession() async {
        if let token = keychain.read() {
            state = .loggedIn(Session(token: token))
        } else {
            state = .loggedOut
        }
    }

    /// Universal link z Maila / Safari — token z linka wymieniany na sesję (story 4).
    /// Obce linki są ignorowane bez komunikatu.
    func handleUniversalLink(_ url: URL) async {
        guard let token = UniversalLink.token(from: url, allowedHosts: linkHosts) else {
            return
        }
        await exchange(token: token)
    }

    /// Wklejony link z zaproszenia (dev: universal links nie działają na adresach LAN).
    /// W odróżnieniu od otwierania linków z systemu pokazujemy komunikat,
    /// gdy link jest obcy lub zniekształcony — użytkownik właśnie wykonał akcję.
    func loginWithLinkText(_ text: String) async {
        guard let match = text.firstMatch(of: /https?:\/\/\S+/),
              let url = URL(string: String(match.0)),
              let token = UniversalLink.token(from: url, allowedHosts: linkHosts)
        else {
            errorMessage = "To nie wygląda jak link z zaproszenia do Wspólniaka."
            return
        }
        await exchange(token: token)
    }

    /// Kod rodzinny → lista członków do wyboru (nil przy błędzie, komunikat w errorMessage).
    func verifyCode(_ code: String) async -> ShareVerification? {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            return try await client.verifyShareCode(code)
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    /// Logowanie wybranego członka kodem rodzinnym (admin: memberId = nil).
    func login(code: String, memberId: String?) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let token = try await client.shareLogin(code: code, memberId: memberId)
            await exchange(token: token)
            return isLoggedIn
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Wylogowanie z poziomu aplikacji (story 6): backend czyści ciasteczko,
    /// apka czyści Keychain i wraca na ekran logowania.
    func logout() async {
        await client.logout()
        keychain.delete()
        state = .loggedOut
    }

    /// 401 z API = sesja cofnięta (np. regeneracja linka przez admina) → czyszczenie.
    func sessionWasRevoked() {
        keychain.delete()
        state = .loggedOut
    }

    // MARK: — Wymiana tokenu na sesję

    private func exchange(token: String) async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let sessionValue = try await client.exchangeLoginToken(token)
            try keychain.save(sessionValue)
            state = .loggedIn(Session(token: sessionValue))
        } catch {
            // 401/błąd wymiany → sesja wyczyszczona, powrót na ekran logowania
            // (AC issue #3): nieudane logowanie nigdy nie zostawia sesji.
            keychain.delete()
            state = .loggedOut
            errorMessage = Self.message(for: error)
        }
    }

    // Komunikaty po polsku — mirror treści z webu (share-page.tsx).
    static func message(for error: Error) -> String {
        switch error as? APIError {
        case .unauthorized:
            "Kod lub link jest nieprawidłowy albo już wygasł."
        case .rateLimited:
            "Zbyt wiele prób — odczekaj chwilę i spróbuj ponownie."
        case .timeout, .network:
            "Brak połączenia z Wspólniakiem. Sprawdź internet i spróbuj ponownie."
        case .server:
            "Wspólniak chwilowo nie odpowiada. Spróbuj ponownie za chwilę."
        case .forbidden, .notFound, .decoding, nil:
            "Coś poszło nie tak. Spróbuj ponownie."
        }
    }
}
