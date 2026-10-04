import Foundation

// Konfiguracja instancji (feature toggles "Wspólniak On/Off") — mirror
// FeatureFlags z web API (src/db/instance/queries.ts). Kształt JSON:
// { "markdown": Bool, "library": Bool, "chat": Bool, "albums": Bool, "ai": Bool }.
// AI jest jedyną flagą domyślnie wyłączoną po stronie backendu.

struct InstanceConfig: Codable, Equatable {
    var markdown: Bool
    var library: Bool
    var chat: Bool
    var albums: Bool
    var ai: Bool
}
