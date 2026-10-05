import Foundation

// Parser linków logowania (Faza 2). Magic link webu ma postać <host>/app/u/<token>
// (server.ts kieruje /app/u/* do authRoute, auth.ts: GET /:token). Universal link
// z Maila otwiera apkę, stąd bierzemy token i wymieniamy go na sesję.
// Obce domeny i zniekształcone URL-e są odrzucane (nil).

enum UniversalLink {
    static let magicPathPrefix = "/app/u/"

    /// Token z linka /app/u/<token> albo nil. Akceptujemy wyłącznie hosty z
    /// allowedHosts (prod: wspolniak.com, dev: host instancji deweloperskiej).
    static func token(from url: URL, allowedHosts: Set<String>) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              allowedHosts.contains(host),
              components.path.hasPrefix(magicPathPrefix)
        else { return nil }

        // Token to 32 bajty base64url (crypto.ts) — pojedynczy segment ścieżki.
        let token = String(components.path.dropFirst(magicPathPrefix.count))
        guard !token.isEmpty, !token.contains("/") else { return nil }
        return token
    }

    /// Token ze ścieżki redirectu "/app/u/<token>" — odpowiedź POST /api/share/login.
    static func token(fromRedirectPath path: String) -> String? {
        guard path.hasPrefix(magicPathPrefix) else { return nil }
        let token = String(path.dropFirst(magicPathPrefix.count))
        return token.isEmpty ? nil : token
    }

    /// Hosty uznawane za nasze: prod domena (+ wariant www) i host aktualnej
    /// konfiguracji build. Linki z localhost/127.0.0.1 akceptuje WYŁĄCZNIE
    /// wariant dev (magic linki kopiowane z dev weba na http://localhost:3000) —
    /// prod gada wyłącznie z wspolniak.com (story 35). Bezpieczne zawsze: z linka
    /// bierzemy tylko token, a wymiana idzie do skonfigurowanego baseURL.
    static func allowedHosts(baseURL: URL) -> Set<String> {
        var hosts: Set<String> = ["wspolniak.com", "www.wspolniak.com"]
        let configuredHost = baseURL.host?.lowercased()
        if let configuredHost {
            hosts.insert(configuredHost)
        }
        if let configuredHost, configuredHost != "wspolniak.com", configuredHost != "www.wspolniak.com" {
            hosts.formUnion(["localhost", "127.0.0.1"])
        }
        return hosts
    }
}
