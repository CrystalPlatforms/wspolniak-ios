import Foundation

// API Client — jedyna brama do backendu Hono (PRD: jeden z trzech głębokich modułów).
// Ukrywa endpointy, kopertę {data: ...} i (od Fazy 2) nagłówek autoryzacji za
// jednym wąskim interfejsem. Widoki i feature'y nigdy nie mówią z URL-ami bezpośrednio.

struct APIClient {
    var baseURL: URL
    var session: URLSession = .shared
    // Haczyk na nagłówek autoryzacji — zapełniany przez AuthStore od Fazy 2.
    var authorizationToken: String?

    func fetchInstanceConfig() async throws -> InstanceConfig {
        let (data, _) = try await get("api/admin/features")
        return try decode(APIEnvelope<InstanceConfig>.self, from: data).data
    }

    // GET /api/app/posts — pierwsza strona feedu (kursor przychodzi w Fazie 3).
    func fetchFeed() async throws -> FeedPage {
        let (data, _) = try await get("api/app/posts")
        return try decode(FeedPage.self, from: data)
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

    private func get(_ path: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appending(path: path))
        if let authorizationToken {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
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
        switch httpResponse.statusCode {
        case 200..<300:
            return (data, httpResponse)
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 404: throw APIError.notFound
        case 500..<600: throw APIError.server
        default: throw APIError.network
        }
    }
}

// Koperta odpowiedzi backendu: { "data": ... }.
struct APIEnvelope<Value: Decodable>: Decodable {
    let data: Value
}
