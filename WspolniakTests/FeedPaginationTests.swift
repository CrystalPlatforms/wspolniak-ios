import XCTest
@testable import Wspolniak

// Założenia (issue #4, AC paginacji):
// - GET /api/app/posts[?cursor=<createdAt>_<id>] — kursor w formacie web
//   (posts.ts dzieli po ostatnim "_"); pierwsza strona bez parametru.
// - Dojście do końca strony ładuje kolejną (loadNextPage); po stronie bez
//   nextCursor → reachedEnd i ZERO dalszych żądań.
// - Deduplikacja: posty już znane nie dublują się przy doklejaniu.
// - Pull-to-refresh wraca do strony 1 i podmienia treść.
// - Wszystko na mocku (StubURLProtocol) z 3 stronami; cache na pliku tymczasowym.
// - NIE testujemy tu: SwiftUI rendering i gestów (HITL), dekodowania kształtu
//   JSON (FeedDecodingTests).

@MainActor
final class FeedPaginationTests: XCTestCase {

    private var cacheURL: URL!

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.responseInspector = nil
        cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("feed-pagination-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheURL)
        super.tearDown()
    }

    private func makeStore() -> FeedStore {
        FeedStore(
            clientProvider: {
                APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
            },
            cache: FeedCache(fileURL: cacheURL),
            onUnauthorized: {}
        )
    }

    private static let pageCursors: [FeedCursor?] = [
        FeedCursor(createdAt: "2026-09-01T10:00:00.000Z", id: "p2"),
        FeedCursor(createdAt: "2026-09-02T10:00:00.000Z", id: "p4"),
        nil,
    ]

    private static func pageJSON(postIds: [String], pageIndex: Int) -> Data {
        let posts = postIds.map { id in
            """
            {"id":"\(id)","authorId":"u1","description":"Post \(id)","videos":[],
             "createdAt":"2026-09-01T10:00:00.000Z","updatedAt":"2026-09-01T10:00:00.000Z",
             "author":{"id":"u1","name":"Mama"},"images":[],"commentCount":0}
            """
        }.joined(separator: ",")
        let cursorPart: String
        if let next = pageCursors[pageIndex] {
            cursorPart = """
            "nextCursor":{"createdAt":"\(next.createdAt)","id":"\(next.id)"}
            """
        } else {
            cursorPart = #""nextCursor":null"#
        }
        return Data("""
        {"data":[\(posts)],"meta":{\(cursorPart),"imageAccountHash":"hash"}}
        """.utf8)
    }

    /// Mock 3 stron: routowanie po wartości kursora (nie po liczbie żądań) —
    /// brak kursora zawsze zwraca stronę 1, kursor z paginy N → strona N+1.
    private func stubThreePages(onRequest: @escaping (String?) -> Void) {
        StubURLProtocol.handler = { request in
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "cursor" })?
                .value
            onRequest(cursor)
            let pageIndex: Int
            if cursor == nil {
                pageIndex = 0
            } else if cursor == Self.pageCursors[0]?.queryValue {
                pageIndex = 1
            } else {
                pageIndex = 2
            }
            return .ok(200, Self.pageJSON(postIds: Self.pagePostIds[pageIndex], pageIndex: pageIndex))
        }
    }

    private static let pagePostIds: [[String]] = [["p1", "p2"], ["p3", "p4"], ["p5"]]

    func testPaginationLoadsAllThreePagesAndStopsAtEnd() async throws {
        var requestedCursors: [String?] = []
        stubThreePages { requestedCursors.append($0) }

        let store = makeStore()
        await store.initialLoad()
        XCTAssertEqual(store.posts.map(\.id), ["p1", "p2"], "Pierwsza strona bez kursora")
        XCTAssertNil(requestedCursors[0])
        XCTAssertFalse(store.reachedEnd)

        await store.loadNextPage()
        XCTAssertEqual(store.posts.map(\.id), ["p1", "p2", "p3", "p4"])
        XCTAssertEqual(requestedCursors[1], "2026-09-01T10:00:00.000Z_p2", "Kursor w formacie <createdAt>_<id>")
        XCTAssertFalse(store.reachedEnd)

        await store.loadNextPage()
        XCTAssertEqual(store.posts.map(\.id), ["p1", "p2", "p3", "p4", "p5"])
        XCTAssertEqual(requestedCursors[2], "2026-09-02T10:00:00.000Z_p4")
        XCTAssertTrue(store.reachedEnd, "Ostatnia strona bez nextCursor = koniec listy")

        // Koniec listy: kolejna próba nie generuje żadnego żądania.
        let requestsBefore = requestedCursors.count
        await store.loadNextPage()
        XCTAssertEqual(requestedCursors.count, requestsBefore)
    }

    func testRefreshReturnsToFirstPageAndReplacesContent() async throws {
        var sawCursorlessRequest = false
        stubThreePages { cursor in
            if cursor == nil { sawCursorlessRequest = true }
        }

        let store = makeStore()
        await store.initialLoad()
        await store.loadNextPage()
        XCTAssertEqual(store.posts.map(\.id), ["p1", "p2", "p3", "p4"])

        sawCursorlessRequest = false
        await store.refresh()
        XCTAssertEqual(store.posts.map(\.id), ["p1", "p2"], "Refresh podmienia treść stroną 1")
        XCTAssertTrue(sawCursorlessRequest, "Refresh zaczyna od świeżej strony 1 (bez kursora)")
        XCTAssertFalse(store.isOffline)
        XCTAssertTrue(store.phase == .loaded)
    }

    func testDuplicatePostsAreNotAppended() async throws {
        // Serwer zwrócił w page 2 posty p2 (już znany z page 1) i p3.
        var requests = 0
        StubURLProtocol.handler = { _ in
            defer { requests += 1 }
            return requests == 0
                ? .ok(200, Self.pageJSON(postIds: ["p1", "p2"], pageIndex: 0))
                : .ok(200, Self.pageJSON(postIds: ["p2", "p3"], pageIndex: 0))
        }

        let store = makeStore()
        await store.initialLoad()
        await store.loadNextPage()

        XCTAssertEqual(store.posts.map(\.id), ["p1", "p2", "p3"], "Duplikat p2 nie wraca do listy")
    }

    func testNextPageFailureKeepsContentAndMarksOffline() async throws {
        var requests = 0
        StubURLProtocol.handler = { _ in
            defer { requests += 1 }
            return requests == 0
                ? .ok(200, Self.pageJSON(postIds: ["p1"], pageIndex: 0))
                : .failure(URLError(.notConnectedToInternet))
        }

        let store = makeStore()
        await store.initialLoad()
        await store.loadNextPage()

        XCTAssertTrue(store.phase == .loaded, "Treść zostaje na ekranie")
        XCTAssertEqual(store.posts.map(\.id), ["p1"])
        XCTAssertTrue(store.isOffline, "Zerwane dociąganie = dyskretne oznaczenie offline")
    }
}
