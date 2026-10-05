import Foundation

// Błędy API w języku aplikacji — wywołujący nie widzą statusów HTTP ani URLError.
// Mapowanie: 401 → unauthorized, 403 → forbidden, 404 → notFound,
// 429 → rateLimited (limit logowania kodem: 5/min/IP), 5xx → server,
// timeout sieci → timeout, niepoprawny JSON → decoding,
// pozostałe problemy transportowe → network.
// 401 od Fazy 2 oznacza cofniętą sesję (AuthStore wylogowuje).

enum APIError: Error, Equatable {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case server
    case timeout
    case decoding
    case network
}
