import XCTest
@testable import Wspolniak

// Założenia zakodowane w tych testach (issue #2, Faza 1):
// - Backend (Hono) opakowuje odpowiedzi JSON w kopertę { "data": ... }.
// - Feature flags to 5 booleanów: markdown, library, chat, albums, ai.
//   Odpowiednio: domyślnie wszystko włączone, AI domyślnie wyłączone (backend
//   DEFAULT_FEATURE_FLAGS — nie wymuszamy tego po stronie apki).
// - Ścieżka: GET {baseURL}/api/admin/features (jedyne miejsce z flagami w web API);
//   wymaga sesji admina — bez niej backend zwraca 401, a apka w Fazie 1
//   spada na domyślne flagi (pokryte testem fallbacku w ShellSectionsTests).
// - Mock sieci tylko na granicy systemowej (URLProtocol); wnętrza nie mockujemy.
// - NIE testujemy w tej iteracji: logowania (Faza 2), maintenance mode, cache.

final class InstanceConfigTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
    }

    func testFetchesInstanceConfigFromDataEnvelope() async throws {
        // Fixture odpowiadające kształtowi GET /api/admin/features z web API.
        StubURLProtocol.handler = { _ in .ok(200, Data(#"{"data":{"markdown":true,"library":false,"chat":true,"albums":true,"ai":false}}"#.utf8)) }

        let client = APIClient(baseURL: URL(string: "http://192.168.9.14:3000")!, session: .stubbed)
        let config = try await client.fetchInstanceConfig()

        XCTAssertEqual(config.markdown, true)
        XCTAssertEqual(config.library, false)
        XCTAssertEqual(config.chat, true)
        XCTAssertEqual(config.albums, true)
        XCTAssertEqual(config.ai, false)
    }

    // Tabela status → błąd aplikacji (zachowanie z issue #2:
    // „mapowanie błędów HTTP (401/403/404/5xx) na typy błędów aplikacji").
    func testMapsHTTPStatusesToAppErrors() async throws {
        let cases: [(status: Int, expected: APIError)] = [
            (401, .unauthorized),
            (403, .forbidden),
            (404, .notFound),
            (500, .server),
            (503, .server),
        ]
        for testCase in cases {
            StubURLProtocol.handler = { _ in .ok(testCase.status, Data("{\"error\":\"x\"}".utf8)) }
            let client = APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
            do {
                _ = try await client.fetchInstanceConfig()
                XCTFail("Status \(testCase.status): oczekiwano błędu, dostano sukces")
            } catch let error as APIError {
                XCTAssertEqual(error, testCase.expected, "Status \(testCase.status)")
            }
        }
    }

    func testMapsNetworkTimeoutToTimeoutError() async throws {
        StubURLProtocol.handler = { _ in .failure(URLError(.timedOut)) }
        let client = APIClient(baseURL: URL(string: "http://192.168.9.14:3000")!, session: .stubbed)
        do {
            _ = try await client.fetchInstanceConfig()
            XCTFail("Oczekiwano błędu timeout")
        } catch let error as APIError {
            XCTAssertEqual(error, .timeout)
        }
    }

    func testMapsMalformedJSONToDecodingError() async throws {
        StubURLProtocol.handler = { _ in .ok(200, Data("to nie jest json".utf8)) }
        let client = APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
        do {
            _ = try await client.fetchInstanceConfig()
            XCTFail("Oczekiwano błędu dekodowania")
        } catch let error as APIError {
            XCTAssertEqual(error, .decoding)
        }
    }

    func testRequestGoesToAdminFeaturesPath() async throws {
        StubURLProtocol.handler = { request in
            .ok(200, Self.configJSON(markdown: true))
        }

        var requestedPath: String?
        StubURLProtocol.responseInspector = { request in
            requestedPath = request.url?.path
        }

        let client = APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
        _ = try await client.fetchInstanceConfig()

        XCTAssertEqual(requestedPath, "/api/admin/features")
    }

    private static func configJSON(markdown: Bool) -> Data {
        Data("""
        {"data":{"markdown":\(markdown),"library":true,"chat":true,"albums":true,"ai":true}}
        """.utf8)
    }
}

// Granica systemowa: sztuczny URLProtocol zamiast prawdziwej sieci.
enum StubResponse {
    case ok(Int, Data)
    case okWithHeaders(Int, Data, [String: String])
    case failure(URLError)
}

final class StubURLProtocol: URLProtocol {

    nonisolated(unsafe) static var handler: ((URLRequest) -> StubResponse)?
    nonisolated(unsafe) static var responseInspector: ((URLRequest) -> Void)?

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        Self.responseInspector?(request)
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch handler(request) {
        case let .ok(status, data):
            respond(status: status, data: data, headers: ["Content-Type": "application/json"])
        case let .okWithHeaders(status, data, headers):
            var allHeaders = headers
            allHeaders["Content-Type"] = allHeaders["Content-Type"] ?? "application/json"
            respond(status: status, data: data, headers: allHeaders)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func respond(status: Int, data: Data, headers: [String: String]) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    nonisolated override func stopLoading() {}
}

extension URLSession {
    static var stubbed: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
