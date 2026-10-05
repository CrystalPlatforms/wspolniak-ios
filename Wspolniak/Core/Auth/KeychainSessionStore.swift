import Foundation
import Security

// Trwała sesja — wyłącznie Keychain (PRD: moduł AuthStore). Generic password
// z serwisem com.crystal.wspolniak; odczyt w nowej instancji store'a zwraca
// ten sam token (test persistencji), usunięcie czyści wpis bez śladu.

struct KeychainSessionStore {

    enum KeychainError: Error {
        case unhandled(OSStatus)
    }

    let service: String
    let account: String

    init(
        service: String = "com.crystal.wspolniak",
        account: String = "session"
    ) {
        self.service = service
        self.account = account
    }

    func save(_ token: String) throws {
        let value = Data(token.utf8)
        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let update = [kSecValueData as String: value] as CFDictionary
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update)
            guard updateStatus == errSecSuccess else { throw KeychainError.unhandled(updateStatus) }
        case errSecItemNotFound:
            var add = baseQuery
            add[kSecValueData as String] = value
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        default:
            throw KeychainError.unhandled(status)
        }
    }

    /// Token sesji albo nil, gdy wpisu nie ma (nigdy nie zalogowano / wylogowano).
    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
