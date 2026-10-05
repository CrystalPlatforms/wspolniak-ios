import XCTest
@testable import Wspolniak

// Założenia (issue #3, AC klienta wymiany tokenu i cyklu sesji):
// - GET /app/u/<token> odpowiada 302 z Set-Cookie: session=<JWT> (auth.ts);
//   sesja URL w testach jest stubowana, więc odpowiedź dochodzi bez redirectu.
// - Sukces wymiany → sesja zapisana w Keychain i stan loggedIn; w nowej
//   instancji store'a sesja wraca po restoreSession (restart apki).
// - 401 z wymiany → bez sesji, komunikat, powrót na ekran logowania (stan
//   loggedOut), Keychain pusty.
// - 401 z dowolnego API (sessionWasRevoked) → czyszczenie + loggedOut.
// - Wylogowanie: POST /api/auth/logout (best effort) + czyszczenie Keychain.
// - Kod rodzinny: verify → lista członków; login → redirectUrl /app/u/<token>
//   → wymiana → loggedIn. Obce linki ignorowane bez żądania sieciowego.
// - NIE testujemy tu: SwiftUI rendering (LoginView), entitlementów, Keychain
//   (osobna pula w KeychainSessionStoreTests).

@MainActor
final class AuthStoreTests: XCTestCase {

    private var service = ""

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.responseInspector = nil
        service = "test.authstore.\(UUID().uuidString)"
    }

    override func tearDown() {
        KeychainSessionStore(service: service).delete()
        super.tearDown()
    }

    private func makeStore() -> AuthStore {
        // Baza jak w wariancie DEV (sieć lokalna) — prod nie pochwala linków
        // localhost (pokryte w UniversalLinkParserTests).
        AuthStore(
            client: APIClient(baseURL: URL(string: "http://192.168.9.14:3000")!, session: .stubbed),
            keychain: KeychainSessionStore(service: service)
        )
    }

    private var keychain: KeychainSessionStore {
        KeychainSessionStore(service: service)
    }

    // MARK: — Wymiana tokenu magic linka

    func testExchangeSuccessSavesSessionAndLogsIn() async throws {
        StubURLProtocol.handler = { _ in
            .okWithHeaders(302, Data(), ["Set-Cookie": "session=hdr.payload.podpis; HttpOnly; Path=/; Max-Age=31536000"])
        }
        var requestedPath: String?
        StubURLProtocol.responseInspector = { request in
            requestedPath = request.url?.path
        }

        let store = makeStore()
        await store.handleUniversalLink(URL(string: "https://wspolniak.com/app/u/tok123")!)

        XCTAssertEqual(requestedPath, "/app/u/tok123")
        XCTAssertEqual(store.state, .loggedIn(Session(token: "hdr.payload.podpis")))
        XCTAssertEqual(store.sessionToken, "hdr.payload.podpis")
        // Sesja trafiła do Keychain — nowa instancja store'a ją przywraca.
        XCTAssertEqual(keychain.read(), "hdr.payload.podpis")
        let restarted = makeStore()
        await restarted.restoreSession()
        XCTAssertEqual(restarted.state, .loggedIn(Session(token: "hdr.payload.podpis")))
    }

    func testExchangeUnauthorizedKeepsLoggedOutAndClearsKeychain() async throws {
        // Symulacja: najpierw była sesja, potem wymiana nowego linka pada na 401.
        try keychain.save("stara.sesja")
        StubURLProtocol.handler = { _ in .ok(401, Data(#"{"error":"Unauthorized"}"#.utf8)) }

        let store = makeStore()
        await store.handleUniversalLink(URL(string: "https://wspolniak.com/app/u/zly-token")!)

        XCTAssertEqual(store.state, .loggedOut)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(keychain.read())
    }

    func testExchangeWithoutSessionCookieMapsToError() async throws {
        // 302 bez ciasteczka sesji = nieoczekiwany kształt odpowiedzi.
        StubURLProtocol.handler = { _ in .okWithHeaders(302, Data(), [:]) }

        let store = makeStore()
        await store.restoreSession()
        await store.handleUniversalLink(URL(string: "https://wspolniak.com/app/u/tok")!)

        XCTAssertEqual(store.state, .loggedOut)
        XCTAssertNotNil(store.errorMessage)
    }

    func testForeignLinkIsIgnoredWithoutNetworkRequest() async throws {
        var requestCount = 0
        StubURLProtocol.handler = { _ in
            requestCount += 1
            return .ok(200, Data())
        }

        let store = makeStore()
        await store.restoreSession()
        await store.handleUniversalLink(URL(string: "https://zla-domena.example/app/u/tok")!)

        XCTAssertEqual(requestCount, 0, "Obcy link nie może generować żądań")
        XCTAssertEqual(store.state, .loggedOut)
        XCTAssertNil(store.errorMessage, "Obcy link ignorujemy dyskretnie")
    }

    func testPastedLinkTextLogsIn() async throws {
        StubURLProtocol.handler = { _ in
            .okWithHeaders(302, Data(), ["Set-Cookie": "session=jwt.z.wklejki; Path=/"])
        }

        let store = makeStore()
        await store.loginWithLinkText("Kliknij: https://wspolniak.com/app/u/tokXYZ dzięki!")

        XCTAssertEqual(store.state, .loggedIn(Session(token: "jwt.z.wklejki")))
    }

    func testPastedLocalhostLinkLogsIn() async throws {
        // Magic link skopiowany z dev weba otwartego na localhost:3000.
        StubURLProtocol.handler = { _ in
            .okWithHeaders(302, Data(), ["Set-Cookie": "session=jwt.z.localhost; Path=/"])
        }
        var requestedPath: String?
        StubURLProtocol.responseInspector = { request in
            requestedPath = request.url?.path
        }

        let store = makeStore()
        await store.loginWithLinkText("http://localhost:3000/app/u/tokLOCAL")

        XCTAssertEqual(requestedPath, "/app/u/tokLOCAL", "Wymiana idzie do baseURL, nie do localhosta z linka")
        XCTAssertEqual(store.state, .loggedIn(Session(token: "jwt.z.localhost")))
    }

    func testPastedForeignLinkShowsMessageWithoutNetworkRequest() async throws {
        var requestCount = 0
        StubURLProtocol.handler = { _ in
            requestCount += 1
            return .ok(200, Data())
        }

        let store = makeStore()
        await store.restoreSession()
        await store.loginWithLinkText("https://zla-domena.example/app/u/tok")

        XCTAssertEqual(requestCount, 0)
        XCTAssertNotNil(store.errorMessage, "Wklejenie obcego linka nie może być cichą nicścią")
        XCTAssertEqual(store.state, .loggedOut)
    }

    // MARK: — Kod rodzinny (mirror web /share)

    func testShareCodeFlowVerifiesAndLogsIn() async throws {
        StubURLProtocol.handler = { request in
            switch (request.url?.path, request.httpMethod) {
            case ("/api/share/verify", "POST"):
                return .ok(200, Data(#"{"members":[{"id":"u1","name":"Mama"}],"isAdmin":false}"#.utf8))
            case ("/api/share/login", "POST"):
                return .ok(200, Data(#"{"redirectUrl":"/app/u/tokXYZ"}"#.utf8))
            case ("/app/u/tokXYZ", "GET"):
                return .okWithHeaders(302, Data(), ["Set-Cookie": "session=jwt.z.kodu; Path=/"])
            default:
                return .ok(404, Data())
            }
        }

        let store = makeStore()
        let verification = await store.verifyCode("4827")
        XCTAssertEqual(verification?.members.first?.name, "Mama")
        XCTAssertFalse(verification?.isAdmin ?? true)

        let loggedIn = await store.login(code: "4827", memberId: "u1")
        XCTAssertTrue(loggedIn)
        XCTAssertEqual(store.state, .loggedIn(Session(token: "jwt.z.kodu")))
        XCTAssertEqual(keychain.read(), "jwt.z.kodu")
    }

    func testShareCodeVerifyRejectsInvalidCodeWithMessage() async throws {
        StubURLProtocol.handler = { _ in .ok(401, Data(#"{"error":"Invalid code"}"#.utf8)) }

        let store = makeStore()
        await store.restoreSession()
        let verification = await store.verifyCode("0000")

        XCTAssertNil(verification)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.state, .loggedOut, "Nieudana weryfikacja kodu nie loguje")
    }

    func testAdminCodeVerifyReturnsNoMembersButAdminFlag() async throws {
        // Backend dla kodu admina zwraca samo { isAdmin: true }, bez kluczy members
        // (share.ts) — klient ma to znieść, nie wywalać dekodowaniem.
        StubURLProtocol.handler = { _ in .ok(200, Data(#"{"isAdmin":true}"#.utf8)) }

        let store = makeStore()
        let verification = await store.verifyCode("1219")

        XCTAssertEqual(verification?.isAdmin, true)
        XCTAssertEqual(verification?.members, [], "Brak listy = pusta lista, nie błąd")
    }

    // MARK: — Wylogowanie i cofnięta sesja

    func testLogoutClearsSession() async throws {
        StubURLProtocol.handler = { _ in .ok(200, Data(#"{"data":{"ok":true}}"#.utf8)) }
        try keychain.save("jwt.przed.wylogowaniem")

        let store = makeStore()
        await store.restoreSession()
        XCTAssertTrue(store.isLoggedIn)
        await store.logout()

        XCTAssertEqual(store.state, .loggedOut)
        XCTAssertNil(keychain.read())
    }

    func testLogoutSucceedsEvenWhenServerIsUnreachable() async throws {
        // Wylogowanie jest best effort — brak sieci nie może zatrzymać czyszczenia.
        StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
        try keychain.save("jwt.offline")

        let store = makeStore()
        await store.restoreSession()
        await store.logout()

        XCTAssertEqual(store.state, .loggedOut)
        XCTAssertNil(keychain.read())
    }

    func testSessionWasRevokedClearsSessionOn401() async throws {
        try keychain.save("jwt.cofnieta")

        let store = makeStore()
        await store.restoreSession()
        XCTAssertTrue(store.isLoggedIn)

        store.sessionWasRevoked()

        XCTAssertEqual(store.state, .loggedOut)
        XCTAssertNil(keychain.read())
    }

    func testRestoreSessionWithoutStoredTokenStartsLoggedOut() async {
        let store = makeStore()
        XCTAssertEqual(store.state, .unknown)

        await store.restoreSession()

        XCTAssertEqual(store.state, .loggedOut)
    }

    // MARK: — Komunikaty po polsku

    func testErrorMessagesArePolishAndSpecific() {
        XCTAssertTrue(AuthStore.message(for: APIError.unauthorized).contains("Kod lub link"))
        XCTAssertTrue(AuthStore.message(for: APIError.rateLimited).contains("Zbyt wiele prób"))
        XCTAssertTrue(AuthStore.message(for: APIError.network).contains("Brak połączenia"))
        XCTAssertTrue(AuthStore.message(for: APIError.server).contains("nie odpowiada"))
    }
}
