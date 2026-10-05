import XCTest
@testable import Wspolniak

// Założenia (issue #3, AC persistencji sesji):
// - Sesja żyje wyłącznie w Keychain (generic password). Zapis → odczyt w NOWEJ
//   instancji store'a zwraca ten sam token (symulacja restartu aplikacji).
// - Zapis nad istniejącym wpisem podmienia wartość (nie duplikuje).
// - Usunięcie czyści wpis — kolejny odczyt zwraca nil (wylogowanie).
// - Tożsamość (userId, name, role) czytamy z payloadu JWT bez sieci.
// - Każdy test używa unikalnego serwisu, żeby wpisy nie przeciekały między
//   testami; w tearDown sprzątamy.

final class KeychainSessionStoreTests: XCTestCase {

    private var service = ""
    private var store: KeychainSessionStore {
        KeychainSessionStore(service: service)
    }

    override func setUp() {
        super.setUp()
        service = "test.keychain.\(UUID().uuidString)"
    }

    override func tearDown() {
        store.delete()
        super.tearDown()
    }

    func testSaveAndReadAcrossNewInstances() throws {
        try store.save("jwt.pierwszy.podpis")

        // Nowa instancja = symulacja restartu aplikacji.
        let freshInstance = KeychainSessionStore(service: service)
        XCTAssertEqual(freshInstance.read(), "jwt.pierwszy.podpis")
    }

    func testOverwriteReplacesValue() throws {
        try store.save("jwt.stary")
        try store.save("jwt.nowy")

        XCTAssertEqual(store.read(), "jwt.nowy")
    }

    func testReadOnEmptyStoreReturnsNil() {
        XCTAssertNil(store.read())
    }

    func testDeleteClearsEntry() throws {
        try store.save("jwt.do-usuniecia")
        store.delete()

        XCTAssertNil(store.read())
    }

    func testSessionIdentityDecodesJWTPayload() {
        let payload = #"{"userId":"u1","name":"Mama","role":"member","iat":1,"exp":2}"#
        let encoded = Data(payload.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "naglowek.\(encoded).podpis"

        let session = Session(token: token)

        XCTAssertEqual(session.identity, SessionIdentity(userId: "u1", name: "Mama", role: "member"))
    }

    func testSessionIdentityNilForGarbageToken() {
        XCTAssertNil(Session(token: "nie-jwt").identity)
        XCTAssertNil(Session(token: "a.b.c").identity)
    }
}
