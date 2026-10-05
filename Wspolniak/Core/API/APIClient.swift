import Foundation

// API Client — jedyna brama do backendu Hono (PRD: jeden z trzech głębokich modułów).
// Ukrywa endpointy, kopertę {data: ...} i nagłówek sesji za jednym wąskim
// interfejsem. Widoki i feature'y nigdy nie mówią z URL-ami bezpośrednio.
// Sesja (Faza 2): backend czyta wyłącznie ciasteczko "session" (middleware
// auth.ts), więc klient dokleja ją jako nagłówek Cookie — nie ma Bearerów.

struct APIClient {
    var baseURL: URL
    var session: URLSession = .shared
    // Wartość ciasteczka "session" (JWT z Keychain) — zapełniana przez AuthStore.
    var sessionCookie: String?

    func fetchInstanceConfig() async throws -> InstanceConfig {
        let data = try await expectingSuccess(path: "api/admin/features", method: "GET")
        return try decode(APIEnvelope<InstanceConfig>.self, from: data).data
    }

    // GET /api/app/posts[?cursor=<createdAt>_<id>] — strona feedu; paginacja
    // kursorowa jak w web (posts.ts dzieli cursor po ostatnim "_").
    func fetchFeed(cursor: FeedCursor? = nil) async throws -> FeedPage {
        var url = baseURL.appending(path: "api/app/posts")
        if let cursor {
            url.append(queryItems: [URLQueryItem(name: "cursor", value: cursor.queryValue)])
        }
        let data = try await expectingSuccess(url: url, method: "GET")
        return try decode(FeedPage.self, from: data)
    }

    // MARK: — Autoryzacja (Faza 2)

    // POST /api/share/verify — kod rodzinny → lista aktywnych członków (mirror web /share).
    func verifyShareCode(_ code: String) async throws -> ShareVerification {
        let body = try JSONEncoder().encode(["code": code])
        let data = try await expectingSuccess(path: "api/share/verify", method: "POST", body: body)
        return try decode(ShareVerification.self, from: data)
    }

    // POST /api/share/login — kod + członek → ścieżka /app/u/<token> do wymiany
    // na sesję (web robi window.location.href na tę samą ścieżkę).
    func shareLogin(code: String, memberId: String?) async throws -> String {
        let body = ShareLoginBody(code: code, memberId: memberId)
        let data = try await expectingSuccess(
            path: "api/share/login",
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
        let payload = try decode(ShareLoginResponse.self, from: data)
        guard let token = UniversalLink.token(fromRedirectPath: payload.redirectUrl) else {
            throw APIError.decoding
        }
        return token
    }

    // GET /app/u/<token> — wymiana tokenu magic linka na sesję: backend odpowiada
    // 302 z Set-Cookie: session=<JWT>. Sesja URL (noRedirects) musi blokować
    // przekierowanie, żeby odpowiedź dotarła do nas zamiast do /app.
    func exchangeLoginToken(_ token: String) async throws -> String {
        let (_, response) = try await request(path: "app/u/\(token)", method: "GET")
        guard (300..<400).contains(response.statusCode) else {
            throw Self.error(forStatus: response.statusCode)
        }
        guard let cookieHeader = response.value(forHTTPHeaderField: "Set-Cookie"),
              let sessionValue = Self.sessionCookieValue(from: cookieHeader)
        else {
            // 302 bez ciasteczka sesji — nieoczekiwany kształt odpowiedzi.
            throw APIError.decoding
        }
        return sessionValue
    }

    // POST /api/auth/logout — backend kasuje ciasteczko; apka niezależnie czyści Keychain.
    func logout() async {
        _ = try? await request(path: "api/auth/logout", method: "POST")
    }

    // MARK: — mechanika

    private func expectingSuccess(
        path: String,
        method: String,
        body: Data? = nil
    ) async throws -> Data {
        try await expectingSuccess(url: baseURL.appending(path: path), method: method, body: body)
    }

    private func expectingSuccess(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws -> Data {
        let (data, httpResponse) = try await request(url: url, method: method, body: body)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.error(forStatus: httpResponse.statusCode)
        }
        return data
    }

    private func request(
        path: String,
        method: String,
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        try await request(url: baseURL.appending(path: path), method: method, body: body)
    }

    private func request(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let sessionCookie {
            request.setValue("session=\(sessionCookie)", forHTTPHeaderField: "Cookie")
        }
        let data: Data
        let httpResponse: HTTPURLResponse
        do {
            let (payload, response) = try await session.data(for: request)
            data = payload
            guard let http = response as? HTTPURLResponse else { throw APIError.network }
            httpResponse = http
        } catch let error as URLError where error.code == .timedOut {
            throw APIError.timeout
        } catch is URLError {
            throw APIError.network
        }
        return (data, httpResponse)
    }

    static func error(forStatus status: Int) -> APIError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429: return .rateLimited
        case 500..<600: return .server
        default: return .network
        }
    }

    // "session=<JWT>; HttpOnly; Path=/" → wartość po "session=".
    static func sessionCookieValue(from header: String) -> String? {
        for pair in header.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("session=") {
                let value = String(trimmed.dropFirst("session=".count))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    // Drizzle serializuje timestampy jako ISO-8601 z milisekundami (…T18:30:00.123Z);
    // akceptujemy też format bez ułamka sekundy.
    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private var decoder: JSONDecoder {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.isoFormatterWithFractional.date(from: string) { return date }
            if let date = Self.isoFormatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Nieoczekiwany format daty: \(string)"
            )
        }
        return jsonDecoder
    }
}

// Koperta odpowiedzi backendu: { "data": ... }.
struct APIEnvelope<Value: Decodable>: Decodable {
    let data: Value
}

// Body POST /api/share/login — memberId pomijany dla kodu administratora.
private struct ShareLoginBody: Encodable {
    let code: String
    let memberId: String?
}

// Odpowiedź share/login — ścieżka redirectu do wymiany tokenu.
private struct ShareLoginResponse: Decodable {
    let redirectUrl: String
}

// Odpowiedź share/verify — lista aktywnych członków (bez koperty {data};
// kod administratora zwraca samo isAdmin, bez members).
struct ShareVerification: Decodable, Equatable {
    let members: [ShareMember]
    let isAdmin: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        members = try container.decodeIfPresent([ShareMember].self, forKey: .members) ?? []
        isAdmin = try container.decode(Bool.self, forKey: .isAdmin)
    }

    enum CodingKeys: String, CodingKey {
        case members
        case isAdmin
    }
}

struct ShareMember: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
}

extension URLSession {
    /// Sesja bez podążania za przekierowaniami — wymiana tokenu na sesję czyta
    /// Set-Cookie z odpowiedzi 302 (app/u/:token), zanim backend przekieruje na /app.
    /// Krótki timeout (10 s): nieosiągalna instancja = czytelny błąd po sekundach,
    /// nie ~minuta ciszy na domyślnym 60 s.
    static var noRedirects: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }
}

// Callback delegata przychodzi z kolejki sesji URL — poza MainActor
// (projekt ma SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
private nonisolated final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
