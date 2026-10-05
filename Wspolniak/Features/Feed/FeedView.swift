import SwiftUI

// Ekran feedu (Faza 3): lista postów z paginacją nieskończoną, pull-to-refresh,
// skeletonem, stanem błędu z „Ponów" i trybem offline z cache (issue #4).
// Karta posta odzwierciedla PostCard z webu: autor, czas względny, treść,
// siatka miniaturek („+N więcej"), plakaty YouTube, licznik komentarzy.

struct FeedView: View {
    // Store'y są @Observable — używamy @State, nie @StateObject.
    @State private var store: FeedStore

    init(authStore: AuthStore) {
        _store = State(wrappedValue: FeedStore(
            clientProvider: {
                APIClient(baseURL: AppConfig.baseURL, sessionCookie: authStore.sessionToken)
            },
            onUnauthorized: { authStore.sessionWasRevoked() }
        ))
    }

    var body: some View {
        FeedList(store: store)
            .refreshable { await store.refresh() }
            .task { await store.initialLoad() }
            .navigationTitle("Feed")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

private struct FeedList: View {
    let store: FeedStore

    var body: some View {
        switch store.phase {
        case .firstLoad:
            FeedSkeleton()
                .background(Color.wspBackground)
        case .failed:
            FeedErrorState {
                Task { await store.retry() }
            }
        case .loaded:
            List {
                if store.posts.isEmpty {
                    emptyState
                } else {
                    if store.isOffline {
                        offlineBanner
                    }
                    ForEach(Array(store.posts.enumerated()), id: \.element.id) { index, post in
                        FeedPostCard(post: post, imageAccountHash: store.imageAccountHash)
                            .task(id: post.id) {
                                // Dojście do końca listy dociąga kolejną stronę.
                                if index == store.posts.count - 1 {
                                    await store.loadNextPage()
                                }
                            }
                    }
                    footer
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.wspBackground)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(Color.wspMutedText)
            Text("Kronika jest jeszcze pusta.")
                .font(.wspBody(15))
                .foregroundStyle(Color.wspMutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // Dyskretne oznaczenie nieświeżości (offline) — treść zostaje z cache.
    private var offlineBanner: some View {
        Label("Offline — pokazuję zapisaną kronikę", systemImage: "wifi.slash")
            .font(.wspBody(13))
            .foregroundStyle(Color.wspMutedText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Color.wspMuted, in: RoundedRectangle(cornerRadius: 8))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var footer: some View {
        if store.isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if store.reachedEnd {
            Text("To już cała kronika.")
                .font(.wspBody(13))
                .foregroundStyle(Color.wspMutedText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

// MARK: — Karta posta

struct FeedPostCard: View {
    let post: Post
    let imageAccountHash: String

    private var sortedImages: [PostImage] {
        post.images.sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            if let description = post.description, !description.isEmpty {
                Text(description)
                    .font(.wspSerif(16))
                    .foregroundStyle(Color.wspText)
                    .lineLimit(6)
            }
            if !sortedImages.isEmpty {
                imageGrid
            }
            ForEach(post.videos, id: \.youtubeVideoId) { video in
                videoRow(video)
            }
            footer
        }
        .padding(Spacing.md)
        .background(Color.wspCard, in: RoundedRectangle(cornerRadius: 12))
        // Przypięty post — mirror webu (post-card.tsx): ramka 2 px kolorem
        // primary i okrągła pinezka zachodząca na lewy górny narożnik.
        .overlay {
            if post.pinned == true {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.wspPrimary, lineWidth: 2)
            }
        }
        .overlay(alignment: .topLeading) {
            if post.pinned == true {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.wspOnPrimary)
                    .frame(width: 26, height: 26)
                    .background(Color.wspPrimary, in: Circle())
                    .offset(x: -9, y: -9)
                    .accessibilityLabel("Przypięty post")
            }
        }
        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.md, bottom: Spacing.xs, trailing: Spacing.md))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(post.author.name)
                .font(.wspBody(16).weight(.semibold))
                .foregroundStyle(Color.wspText)
            Text(RelativeTime.polish(post.createdAt))
                .font(.wspBody(13))
                .foregroundStyle(Color.wspMutedText)
            Spacer()
        }
    }

    // Mirror siatki z webu: 1 zdjęcie na całą szerokość, dalej 2 kolumny,
    // maksymalnie 4 miniaturki z „+N więcej" na ostatniej.
    @ViewBuilder
    private var imageGrid: some View {
        let images = Array(sortedImages.prefix(4))
        if images.count == 1 {
            thumbnail(images[0], height: 210)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.sm),
                    GridItem(.flexible(), spacing: Spacing.sm),
                ],
                spacing: Spacing.sm
            ) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    let remaining = post.images.count - 4
                    thumbnail(
                        image,
                        height: 140,
                        overlayCount: index == images.count - 1 && remaining > 0 ? remaining : nil
                    )
                }
            }
        }
    }

    private func thumbnail(_ image: PostImage, height: CGFloat, overlayCount: Int? = nil) -> some View {
        AsyncImage(url: FeedImageURL.url(cfImageId: image.cfImageId, accountHash: imageAccountHash)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Rectangle().fill(Color.wspMuted)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomTrailing) {
            if let overlayCount {
                Text("+\(overlayCount) więcej")
                    .font(.wspBody(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .padding(Spacing.sm)
            }
        }
        .accessibilityLabel("Zdjęcie \(image.displayOrder + 1)")
    }

    private func videoRow(_ video: PostVideo) -> some View {
        HStack(spacing: Spacing.sm) {
            AsyncImage(url: video.thumbnailUrl) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Rectangle().fill(Color.wspMuted)
                }
            }
            .frame(width: 84, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                Image(systemName: "play.fill")
                    .font(.wspBody(13))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Filmik YouTube")
                    .font(.wspBody(12))
                    .foregroundStyle(Color.wspMutedText)
                Text(video.title)
                    .font(.wspBody(14))
                    .foregroundStyle(Color.wspText)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "bubble.left")
            Text("\(post.commentCount)")
            Spacer()
        }
        .font(.wspBody(14))
        .foregroundStyle(Color.wspMutedText)
    }
}

// MARK: — Stany ładowania

// Szkielet przy pierwszym ładowaniu — mirror post-card-skeleton z webu.
struct FeedSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                ForEach(0..<4, id: \.self) { _ in
                    FeedSkeletonCard()
                }
            }
            .padding(Spacing.md)
        }
    }
}

private struct FeedSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.wspMuted)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    skeletonBar(width: 120, height: 12)
                    skeletonBar(width: 72, height: 10)
                }
                Spacer()
            }
            skeletonBar(width: nil, height: 12)
            skeletonBar(width: 210, height: 12)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.wspMuted)
                .frame(height: 150)
        }
        .padding(Spacing.md)
        .background(Color.wspCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private func skeletonBar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.wspMuted)
            .frame(width: width, height: height)
    }
}

// Stan błędu pierwszego ładowania — „Ponów" wraca do online (issue #4).
struct FeedErrorState: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.wspMutedText)
            Text("Nie udało się załadować kroniki")
                .font(.wspTitle(20))
                .foregroundStyle(Color.wspText)
            Text("Sprawdź połączenie z internetem i spróbuj ponownie.")
                .font(.wspBody(15))
                .foregroundStyle(Color.wspMutedText)
                .multilineTextAlignment(.center)
            Button("Ponów") { onRetry() }
                .buttonStyle(.borderedProminent)
                .tint(Color.wspPrimary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wspBackground)
    }
}
