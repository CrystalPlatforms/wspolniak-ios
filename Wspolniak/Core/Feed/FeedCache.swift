import Foundation

// Cache offline feedu (decyzja „Offline" z PRD): ostatni załadowany feed trzymamy
// na dysku w Application Support. Gdy API jest nieosiągalne, feed renderuje się
// z cache z dyskretnym oznaczeniem nieświeżości (FeedStore.isOffline).

struct CachedFeed: Codable, Equatable {
    var posts: [Post]
    var imageAccountHash: String
    var nextCursor: FeedCursor?
    var savedAt: Date
}

struct FeedCache {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Wspolniak", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("feed-cache.json")
        }
    }

    func load() -> CachedFeed? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(CachedFeed.self, from: data)
    }

    func save(_ feed: CachedFeed) {
        guard let data = try? Self.encoder.encode(feed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // Własny koder z ISO-8601 — spójny w obie strony; cache nie przechodzi przez
    // dekoder APIClient, więc wystarczy strategia domyślnego formatu ISO-8601.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
