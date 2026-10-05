import XCTest
@testable import Wspolniak

// Założenia (issue #4, AC offline):
// - Udane ładowanie zapisuje ostatni feed do cache na dysku.
// - API nieosiągalne, a cache jest → feed renderuje z cache ze znacznikiem
//   isOffline (dyskretne oznaczenie nieświeżości), stan pozostaje .loaded.
// - API nieosiągalne, a cache jest PUSTY (np. dopiero co zainstalowana apka)
//   → stan .failed z przyciskiem „Ponów"; Ponów po powrocie sieci → .loaded.
// - Restart apki: NOWA instancja store'a (ta sama ścieżka cache) + martwa sieć
//   → initialLoad renderuje cache offline.
// - 401 zawsze wylogowuje (przekazane przez onUnauthorized), nawet z cache.
// - NIE testujemy tu: samego Keychain/AuthStore (AuthStoreTests), UI.

@MainActor
final class FeedOfflineTests: XCTestCase {

    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.responseInspector = nil
        cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("feed-offline-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheURL)
        super.tearDown()
    }

    private func makeStore(onUnauthorized: @escaping () -> Void = {}) -> FeedStore {
        FeedStore(
            clientProvider: {
                APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
            },
            cache: FeedCache(fileURL: cacheURL),
            onUnauthorized: onUnauthorized
        )
    }

    private static let pageJSON = Data("""
    {"data":[{"id":"p1","authorId":"u1","description":"Z wakacji","videos":[],
      "createdAt":"2026-09-01T10:00:00.000Z","updatedAt":"2026-09-01T10:00:00.000Z",
      "author":{"id":"u1","name":"Mama"},"images":[],"commentCount":1}],
     "meta":{"nextCursor":{"createdAt":"2026-09-01T10:00:00.000Z","id":"p1"},
             "imageAccountHash":"hash123"}}
    """.utf8)

    private static let emptyPageJSON = Data(
        #"{"data":[],"meta":{"nextCursor":null,"imageAccountHash":"hash"}}"#.utf8
    )

    func testSuccessfulLoadPersistsCacheToDisk() async {
        StubURLProtocol.handler = { _ in .ok(200, Self.pageJSON) }

        let store = makeStore()
        await store.initialLoad()

        XCTAssertTrue(store.phase == .loaded)
        let cached = FeedCache(fileURL: cacheURL).load()
        XCTAssertEqual(cached?.posts.map(\.id), ["p1"])
        XCTAssertEqual(cached?.imageAccountHash, "hash123")
        XCTAssertNotNil(cached?.nextCursor, "Cache pamięta kursor — po restart wchodzi paginacja")
    }

    func testUnreachableAPIRendersCachedFeedWithOfflineMarker() async {
        // 1. Udane ładowanie (cache powstaje)…
        StubURLProtocol.handler = { _ in .ok(200, Self.pageJSON) }
        let store = makeStore()
        await store.initialLoad()
        XCTAssertFalse(store.isOffline)

        // 2. …sieć pada → pull-to-refresh nie nadpisuje treści.
        StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
        await store.refresh()

        XCTAssertTrue(store.phase == .loaded, "Cache pokazujemy zamiast błędu")
        XCTAssertEqual(store.posts.map(\.id), ["p1"])
        XCTAssertTrue(store.isOffline, "Dyskretne oznaczenie nieświeżości")
    }

    func testRestartWithDeadNetworkRendersCacheFromDisk() async {
        // 1. Pierwsza sesja: udane ładowanie, cache na dysku.
        StubURLProtocol.handler = { _ in .ok(200, Self.pageJSON) }
        let firstSession = makeStore()
        await firstSession.initialLoad()

        // 2. Restart apki przy martwej sieci: nowa instancja store'a.
        StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
        let restarted = makeStore()
        await restarted.initialLoad()

        XCTAssertTrue(restarted.phase == .loaded)
        XCTAssertEqual(restarted.posts.map(\.id), ["p1"])
        XCTAssertEqual(restarted.imageAccountHash, "hash123")
        XCTAssertTrue(restarted.isOffline)
    }

    func testNoCacheAndUnreachableShowsErrorThenRecoversOnRetry() async {
        StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }

        let store = makeStore()
        await store.initialLoad()

        XCTAssertTrue(store.phase == .failed, "Brak cache i brak sieci = stan błędu")
        XCTAssertTrue(store.posts.isEmpty)

        // Sieć wraca → „Ponów" ładuje feed.
        StubURLProtocol.handler = { _ in .ok(200, Self.pageJSON) }
        await store.retry()

        XCTAssertTrue(store.phase == .loaded)
        XCTAssertFalse(store.isOffline)
        XCTAssertEqual(store.posts.map(\.id), ["p1"])
    }

    func testUnauthorizedAlwaysLogsOutEvenWithContent() async {
        var revoked = false
        StubURLProtocol.handler = { _ in .ok(200, Self.pageJSON) }
        let store = makeStore(onUnauthorized: { revoked = true })
        await store.initialLoad()

        StubURLProtocol.handler = { _ in .ok(401, Data(#"{"error":"Unauthorized"}"#.utf8)) }
        await store.refresh()

        XCTAssertTrue(revoked, "401 = cofnięta sesja → flow wylogowania z Fazy 2")
        XCTAssertFalse(store.isOffline)
    }

    func testEmptyFeedLoadsAsEndOfListWithoutError() async {
        StubURLProtocol.handler = { _ in .ok(200, Self.emptyPageJSON) }

        let store = makeStore()
        await store.initialLoad()

        XCTAssertTrue(store.phase == .loaded)
        XCTAssertTrue(store.posts.isEmpty)
        XCTAssertTrue(store.reachedEnd, "Pusta strona bez kursora = koniec listy, nie błąd")
        XCTAssertNil(FeedCache(fileURL: cacheURL).load(), "Pustego feedu nie cache'ujemy")
    }
}
