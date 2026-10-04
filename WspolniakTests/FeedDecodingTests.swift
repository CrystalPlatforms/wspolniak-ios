import XCTest
@testable import Wspolniak

// Założenia (issue #2 / plan Fazy 3 wstęp):
// - GET {baseURL}/api/app/posts zwraca { data: [post], meta: { nextCursor, imageAccountHash } }
//   (bez dodatkowej koperty — sprawdzono w src/hono/api/posts.ts).
// - Kształt posta (src/db/posts/queries.ts, PostWithAuthorAndImages + commentCount/pinned):
//   id, authorId, description (nullable), videos[{youtubeVideoId,title,thumbnailUrl}],
//   createdAt/updatedAt (ISO-8601 Z milisekundami z Drizzle), author{id,name},
//   images[{id,postId,cfImageId,displayOrder,createdAt}], commentCount, pinned (tylko
//   przypięte na 1. stronie — opcjonalne).
// - nextCursor bywa null (ostatnia strona). Cursor traktujemy jako nieprzezroczysty.
// - Uszkodzony/niekompletny JSON → APIError.decoding (nie	crash, nie surowy błąd).
// - NIE testujemy tu: paginacji wysyłania kursora, UI feedu (Faza 3).

final class FeedDecodingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.responseInspector = nil
    }

    func testFetchesFeedPageWithPostAndCursor() async throws {
        StubURLProtocol.handler = { _ in .ok(200, Self.feedPageJSON) }

        let client = APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
        let page = try await client.fetchFeed()

        XCTAssertEqual(page.posts.count, 1)
        let post = try XCTUnwrap(page.posts.first)
        XCTAssertEqual(post.id, "post-1")
        XCTAssertEqual(post.authorId, "user-1")
        XCTAssertEqual(post.description, "Wakacje nad morzem")
        XCTAssertEqual(post.author.name, "Mama")
        XCTAssertEqual(post.commentCount, 3)
        XCTAssertEqual(post.pinned, true)
        XCTAssertEqual(post.images.count, 1)
        XCTAssertEqual(post.images.first?.cfImageId, "img-abc")
        XCTAssertEqual(post.images.first?.displayOrder, 0)
        XCTAssertEqual(post.videos.count, 1)
        XCTAssertEqual(post.videos.first?.youtubeVideoId, "dQw4w9WgXcQ")
        XCTAssertEqual(post.videos.first?.title, "Wspólne wakacje")
        // Drizzle serializuje timestampy Z milisekundami — format musi przejść.
        let expectedDate = try XCTUnwrap(Self.isoFormatter.date(from: "2026-08-15T18:30:00.123Z"))
        XCTAssertEqual(post.createdAt, expectedDate)

        let cursor = try XCTUnwrap(page.nextCursor)
        XCTAssertEqual(cursor.id, "post-1")
        XCTAssertEqual(page.imageAccountHash, "hash123")
    }

    func testFetchesEmptyFeedPageWithoutCursor() async throws {
        StubURLProtocol.handler = { _ in
            .ok(200, Data(#"{"data":[],"meta":{"nextCursor":null,"imageAccountHash":"hash"}}"#.utf8))
        }

        let client = APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
        let page = try await client.fetchFeed()

        XCTAssertTrue(page.posts.isEmpty)
        XCTAssertNil(page.nextCursor)
        XCTAssertEqual(page.imageAccountHash, "hash")
    }

    func testFetchesFeedWithoutOptionalFields() async throws {
        // description null, brak videos? — backend wysyła videos: [] i description: null.
        StubURLProtocol.handler = { _ in
            .ok(200, Data("""
            {"data":[{"id":"p2","authorId":"u2","description":null,"videos":[],
              "createdAt":"2026-09-01T08:00:00.000Z","updatedAt":"2026-09-01T08:00:00.000Z",
              "author":{"id":"u2","name":"Tata"},"images":[],"commentCount":0}],
             "meta":{"nextCursor":null,"imageAccountHash":"h2"}}
            """.utf8))
        }

        let client = APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
        let page = try await client.fetchFeed()

        let post = try XCTUnwrap(page.posts.first)
        XCTAssertNil(post.description)
        XCTAssertTrue(post.videos.isEmpty)
        XCTAssertTrue(post.images.isEmpty)
        XCTAssertNil(post.pinned, "pinned występuje tylko przy przypiętych postach")
        XCTAssertEqual(post.commentCount, 0)
    }

    func testFeedWithBrokenPostMapsToDecodingError() async throws {
        // Post bez wymaganego pola author — dekodowanie całej strony pada na .decoding.
        StubURLProtocol.handler = { _ in
            .ok(200, Data("""
            {"data":[{"id":"p3","authorId":"u3","description":null,"videos":[],
              "createdAt":"2026-09-01T08:00:00.000Z","updatedAt":"2026-09-01T08:00:00.000Z",
              "images":[],"commentCount":0}],
             "meta":{"nextCursor":null,"imageAccountHash":"h3"}}
            """.utf8))
        }

        let client = APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
        do {
            _ = try await client.fetchFeed()
            XCTFail("Oczekiwano błędu dekodowania")
        } catch let error as APIError {
            XCTAssertEqual(error, .decoding)
        }
    }

    func testFeedRequestGoesToPostsPath() async throws {
        StubURLProtocol.handler = { _ in
            .ok(200, Data(#"{"data":[],"meta":{"nextCursor":null,"imageAccountHash":"h"}}"#.utf8))
        }
        var requestedPath: String?
        StubURLProtocol.responseInspector = { request in
            requestedPath = request.url?.path
        }

        let client = APIClient(baseURL: URL(string: "https://wspolniak.com")!, session: .stubbed)
        _ = try await client.fetchFeed()

        XCTAssertEqual(requestedPath, "/api/app/posts")
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let feedPageJSON = Data("""
    {"data":[{
        "id":"post-1","authorId":"user-1","description":"Wakacje nad morzem",
        "videos":[{"youtubeVideoId":"dQw4w9WgXcQ","title":"Wspólne wakacje",
                   "thumbnailUrl":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"}],
        "createdAt":"2026-08-15T18:30:00.123Z","updatedAt":"2026-08-15T18:30:00.123Z",
        "author":{"id":"user-1","name":"Mama"},
        "images":[{"id":"img-1","postId":"post-1","cfImageId":"img-abc","displayOrder":0,
                   "createdAt":"2026-08-15T18:30:00.123Z"}],
        "commentCount":3,"pinned":true}],
     "meta":{"nextCursor":{"createdAt":"2026-08-15T18:30:00.123Z","id":"post-1"},
             "imageAccountHash":"hash123"}}
    """.utf8)
}
