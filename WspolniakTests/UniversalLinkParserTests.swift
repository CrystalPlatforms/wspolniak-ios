import XCTest
@testable import Wspolniak

// Założenia (issue #3, AC parsera universal linka):
// - Magic link webu ma postać <host>/app/u/<token> (server.ts + auth.ts).
// - Token to 32 bajty base64url (crypto.ts) — pojedynczy segment ścieżki.
// - Akceptujemy wyłącznie nasze hosty: wspolniak.com (+ www) i host dev
//   instancji z konfiguracji build (http://192.168.9.14:3000).
// - Obce domeny, złe ścieżki i zniekształcone URL-e → nil (bez wyjątków).
// - Redirect z share/login ("/app/u/<token>") parsujemy tą samą regułą ścieżki.
// - NIE testujemy tu: wymiany tokenu na sesję (AuthStoreTests), entitlementów.

final class UniversalLinkParserTests: XCTestCase {

    private let hosts = UniversalLink.allowedHosts(baseURL: URL(string: "http://192.168.9.14:3000")!)

    func testExtractsTokenFromProdLink() {
        let url = URL(string: "https://wspolniak.com/app/u/abc123DEF-_")!
        XCTAssertEqual(UniversalLink.token(from: url, allowedHosts: hosts), "abc123DEF-_")
    }

    func testExtractsTokenFromDevInstanceLink() {
        let url = URL(string: "http://192.168.9.14:3000/app/u/tok-xyz")!
        XCTAssertEqual(UniversalLink.token(from: url, allowedHosts: hosts), "tok-xyz")
    }

    func testExtractsTokenFromLocalhostDevWebLink() {
        // Dev workflow: magic link skopiowany z weba otwartego na localhost:3000.
        let localhost = URL(string: "http://localhost:3000/app/u/tok-abc")!
        let loopback = URL(string: "http://127.0.0.1:3000/app/u/tok-abc")!
        XCTAssertEqual(UniversalLink.token(from: localhost, allowedHosts: hosts), "tok-abc")
        XCTAssertEqual(UniversalLink.token(from: loopback, allowedHosts: hosts), "tok-abc")
    }

    func testAcceptsWWWVariantAndCaseInsensitiveHost() {
        let url = URL(string: "https://WWW.Wspolniak.com/app/u/token1")!
        XCTAssertEqual(UniversalLink.token(from: url, allowedHosts: hosts), "token1")
    }

    func testRejectsForeignDomain() {
        let url = URL(string: "https://zlosliwa-domena.example/app/u/abc123")!
        XCTAssertNil(UniversalLink.token(from: url, allowedHosts: hosts))
    }

    func testRejectsLookalikeDomain() {
        // Poddomena nie jest naszą domeną — host musi pasować dokładnie.
        let url = URL(string: "https://wspolniak.com.evil.example/app/u/abc123")!
        XCTAssertNil(UniversalLink.token(from: url, allowedHosts: hosts))
    }

    func testRejectsWrongPath() {
        let url = URL(string: "https://wspolniak.com/auth/error")!
        XCTAssertNil(UniversalLink.token(from: url, allowedHosts: hosts))
    }

    func testRejectsEmptyToken() {
        let url = URL(string: "https://wspolniak.com/app/u/")!
        XCTAssertNil(UniversalLink.token(from: url, allowedHosts: hosts))
    }

    func testRejectsTokenWithExtraSegments() {
        let url = URL(string: "https://wspolniak.com/app/u/abc/dodatkowy")!
        XCTAssertNil(UniversalLink.token(from: url, allowedHosts: hosts))
    }

    func testRejectsMalformedURL() {
        // URL bez schematu nie ma hosta — parser musi odrzucić, nie wywalić.
        let malformed = URL(string: "wspolniak.com/app/u/token")!
        XCTAssertNil(UniversalLink.token(from: malformed, allowedHosts: hosts))
    }

    func testExtractsTokenFromShareLoginRedirectPath() {
        XCTAssertEqual(
            UniversalLink.token(fromRedirectPath: "/app/u/tokXYZ"),
            "tokXYZ"
        )
    }

    func testRejectsForeignRedirectPath() {
        XCTAssertNil(UniversalLink.token(fromRedirectPath: "/auth/error"))
        XCTAssertNil(UniversalLink.token(fromRedirectPath: "/app/u/"))
    }

    func testAllowedHostsIncludeConfiguredBaseURLHost() {
        let hosts = UniversalLink.allowedHosts(baseURL: URL(string: "http://192.168.9.14:3000")!)
        XCTAssertTrue(hosts.contains("wspolniak.com"))
        XCTAssertTrue(hosts.contains("www.wspolniak.com"))
        XCTAssertTrue(hosts.contains("192.168.9.14"))
    }

    func testProdBuildDoesNotAcceptLocalhostLinks() {
        // Prod gada wyłącznie z wspolniak.com (story 35) — localhost tylko w dev.
        let prodHosts = UniversalLink.allowedHosts(baseURL: URL(string: "https://wspolniak.com")!)
        let localhostLink = URL(string: "http://localhost:3000/app/u/tok")!
        XCTAssertFalse(prodHosts.contains("localhost"))
        XCTAssertNil(UniversalLink.token(from: localhostLink, allowedHosts: prodHosts))

        let devHosts = UniversalLink.allowedHosts(baseURL: URL(string: "http://192.168.9.14:3000")!)
        XCTAssertTrue(devHosts.contains("localhost"))
    }
}
