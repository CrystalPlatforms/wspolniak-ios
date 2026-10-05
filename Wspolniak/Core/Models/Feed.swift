import Foundation

// Modele feedu — mirror PostWithAuthorAndImages + commentCount/pinned z web API
// (src/db/posts/queries.ts, src/core/feed.ts). Backend = jedyne źródło prawdy;
// tu tylko odwzorowanie kształtu JSON, zero logiki biznesowej.
// Codable (od Fazy 3) — feed trafia też do cache offline na dysku (FeedCache).

// Odpowiedź GET /api/app/posts — { data: [post], meta: { nextCursor, imageAccountHash } }.
// Uwaga: feed nie siedzi w dodatkowej kopercie APIEnvelope — sam ją stanowi.
// imageAccountHash bywa POMINIĘTY (dev bez zmiennej CLOUDFLARE_IMAGES_ACCOUNT_HASH
// serializuje meta bez tego klucza) — więc opcjonalny z wartością domyślną.
struct FeedPage: Decodable, Equatable {
    let posts: [Post]
    let nextCursor: FeedCursor?
    let imageAccountHash: String

    enum CodingKeys: String, CodingKey {
        case posts = "data"
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        posts = try container.decode([Post].self, forKey: .posts)
        let meta = try container.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta)
        nextCursor = try meta.decodeIfPresent(FeedCursor.self, forKey: .nextCursor)
        imageAccountHash = try meta.decodeIfPresent(String.self, forKey: .imageAccountHash) ?? ""
    }

    private enum MetaKeys: String, CodingKey {
        case nextCursor
        case imageAccountHash
    }
}

// Kursor paginacji — traktowany jako nieprzezroczysty. W query web API leci
// jako "<createdAt>_<id>" (posts.ts dzieli po ostatnim "_").
struct FeedCursor: Codable, Equatable {
    let createdAt: String
    let id: String

    var queryValue: String { "\(createdAt)_\(id)" }
}

struct Post: Codable, Equatable, Identifiable {
    let id: String
    let authorId: String
    let description: String?
    let videos: [PostVideo]
    let createdAt: Date
    let updatedAt: Date
    let author: Author
    let images: [PostImage]
    let commentCount: Int
    // „pinned" dostają tylko przypięte posty na pierwszej stronie feedu.
    let pinned: Bool?
}

struct Author: Codable, Equatable {
    let id: String
    let name: String
}

// Wideo osadzone w poście (link YouTube) — kolumna JSONB `posts.videos`.
struct PostVideo: Codable, Equatable {
    let youtubeVideoId: String
    let title: String
    let thumbnailUrl: URL
}

struct PostImage: Codable, Equatable, Identifiable {
    let id: String
    let postId: String
    let cfImageId: String
    let displayOrder: Int
    let createdAt: Date
}
