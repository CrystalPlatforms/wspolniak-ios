import Foundation
import Observation

// Logika feedu (Faza 3): paginacja nieskończona na kursorze web API,
// pull-to-refresh i cache offline. Widok renderuje wyłącznie stan store'a.

@MainActor
@Observable
final class FeedStore {

    enum Phase: Equatable {
        case firstLoad   // szkielet przy pierwszym ładowaniu
        case loaded
        case failed      // brak treści i nieudane pobranie → „Ponów"
    }

    private(set) var phase: Phase = .firstLoad
    private(set) var posts: [Post] = []
    private(set) var imageAccountHash = ""
    private(set) var nextCursor: FeedCursor?
    private(set) var isOffline = false
    private(set) var isLoadingMore = false
    private(set) var isRefreshing = false

    /// Wskaźnik końca listy: ostatnia strona nie ma już kursora.
    var reachedEnd: Bool {
        phase == .loaded && nextCursor == nil
    }

    private let clientProvider: () -> APIClient
    private let cache: FeedCache
    private let onUnauthorized: () -> Void

    init(
        clientProvider: @escaping () -> APIClient,
        cache: FeedCache = FeedCache(),
        onUnauthorized: @escaping () -> Void
    ) {
        self.clientProvider = clientProvider
        self.cache = cache
        self.onUnauthorized = onUnauthorized
    }

    /// Pierwsze ładowanie: cache pokazujemy natychmiast (jeśli jest),
    /// potem doładujemy świeżą stronę 1.
    func initialLoad() async {
        guard phase == .firstLoad else { return }
        if let cached = cache.load() {
            posts = cached.posts
            imageAccountHash = cached.imageAccountHash
            nextCursor = cached.nextCursor
            if !cached.posts.isEmpty {
                phase = .loaded
            }
        }
        await loadFirstPage()
    }

    /// Pull-to-refresh: świeża strona 1 w miejsce tego, co jest na ekranie.
    func refresh() async {
        await loadFirstPage()
    }

    /// Ponów po błędzie pierwszego ładowania.
    func retry() async {
        phase = .firstLoad
        await loadFirstPage()
    }

    /// Dojście do końca listy ładuje kolejną stronę (paginacja kursorowa).
    func loadNextPage() async {
        guard phase == .loaded, !isLoadingMore, !isRefreshing, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await clientProvider().fetchFeed(cursor: cursor)
            // Deduplikacja: odświeżenie między stronami może zwrócić ten sam post.
            let knownIds = Set(posts.map(\.id))
            posts.append(contentsOf: page.posts.filter { !knownIds.contains($0.id) })
            nextCursor = page.nextCursor
            persistCache()
        } catch {
            handle(error)
        }
    }

    // MARK: — mechanika

    private func loadFirstPage() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let page = try await clientProvider().fetchFeed()
            posts = page.posts
            imageAccountHash = page.imageAccountHash
            nextCursor = page.nextCursor
            isOffline = false
            phase = .loaded
            persistCache()
        } catch {
            handle(error)
        }
    }

    /// Błąd sieci przy istniejącej treści = tryb offline z dyskretnym oznaczeniem;
    /// bez treści = stan błędu z „Ponów". 401 zawsze wylogowuje (flow Fazy 2).
    private func handle(_ error: Error) {
        if case APIError.unauthorized = error {
            onUnauthorized()
            return
        }
        if posts.isEmpty {
            phase = .failed
        } else {
            isOffline = true
        }
    }

    private func persistCache() {
        guard !posts.isEmpty else { return }
        cache.save(CachedFeed(
            posts: posts,
            imageAccountHash: imageAccountHash,
            nextCursor: nextCursor,
            savedAt: Date()
        ))
    }
}
