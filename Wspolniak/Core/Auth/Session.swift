import Foundation

// Sesja użytkownika — wartość ciasteczka "session" z backendu (JWT z
// src/db/identity/session.ts). Przechowywana wyłącznie w Keychain (AuthStore);
// tożsamość czytamy z payloadu JWT bez sieci (userId, name, role).

struct Session: Equatable {
    let token: String

    /// Tożsamość zdekodowana z payloadu JWT (bez sieci). Nil, gdy payload jest
    /// nieczytelny — token i tak pozostaje ważny dla backendu.
    var identity: SessionIdentity? {
        Self.identity(fromToken: token)
    }

    static func identity(fromToken token: String) -> SessionIdentity? {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payload = Data(base64URLEncoded: String(parts[1])),
              let identity = try? JSONDecoder().decode(SessionIdentity.self, from: payload)
        else { return nil }
        return identity
    }
}

// Payload JWT sesji: { userId, name, role, iat, exp } — czytamy tylko tożsamość.
struct SessionIdentity: Codable, Equatable {
    let userId: String
    let name: String
    let role: String
}

extension Data {
    /// Dekodowanie base64url (alfabet JWT: "-" i "_") z uzupełnieniem paddingu.
    init?(base64URLEncoded string: String) {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: normalized)
    }
}
