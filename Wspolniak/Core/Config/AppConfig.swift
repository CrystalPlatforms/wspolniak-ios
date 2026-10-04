import Foundation

// Odczyt aktywnej konfiguracji build (Dev/Prod).
// WSPOLNIAK_BASE_URL płynie z Config/Dev.xcconfig albo Config/Prod.xcconfig
// przez Info.plist (Config/Dev-Info.plist / Prod-Info.plist) → klucz
// „WspolniakBaseURL”. Dev = instancja deweloperska w sieci lokalnej,
// Prod = wyłącznie wspolniak.com (story 34/35).

enum AppConfig {
    static var baseURL: URL {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "WspolniakBaseURL") as? String,
            let url = URL(string: raw)
        else {
            fatalError("Brak WspolniakBaseURL w Info.plist — sprawdź konfigurację build (Dev/Prod).")
        }
        return url
    }
}
