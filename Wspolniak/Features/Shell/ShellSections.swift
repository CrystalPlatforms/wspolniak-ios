// Drzewo nawigacji powłoki — mirror NAV_ITEMS z webu (mobile-sidebar.tsx).
// Wyłączona flaga w konfiguracji instancji = sekcja nie istnieje w drzewie
// (nie renderuje się wcale). Kolejność sekcji = kolejność z webu.

enum ShellSectionKind: Equatable, Hashable {
    case feed
    case library
    case albums
    case chat
    case aiChat
    case calendar
    case stats
}

struct ShellSection: Equatable, Hashable, Identifiable {
    let kind: ShellSectionKind
    let title: String

    var id: ShellSectionKind { kind }
}

enum ShellSections {
    // Mapowanie flag → sekcji. Feed/Kalendarz/Statystyki nie mają flag w webie
    // (zawsze widoczne dla membera).
    static func sections(for config: InstanceConfig) -> [ShellSection] {
        var sections: [ShellSection] = [.init(kind: .feed, title: "Feed")]
        if config.library {
            sections.append(.init(kind: .library, title: "Biblioteka"))
        }
        if config.albums {
            sections.append(.init(kind: .albums, title: "Albumy"))
        }
        if config.chat {
            sections.append(.init(kind: .chat, title: "Chat"))
        }
        if config.ai {
            sections.append(.init(kind: .aiChat, title: "Chat AL"))
        }
        sections.append(.init(kind: .calendar, title: "Kalendarz"))
        sections.append(.init(kind: .stats, title: "Statystyki"))
        return sections
    }
}

extension InstanceConfig {
    // Wszystkie funkcje włączone — fixture/testy.
    static let allEnabled = InstanceConfig(
        markdown: true, library: true, chat: true, albums: true, ai: true
    )

    // Fallback, gdy konfiguracja instancji jest niedostępna (np. 401 bez sesji
    // w Fazie 1): wartości domyślne backendu (DEFAULT_FEATURE_FLAGS) —
    // wszystko włączone, AI wyłączone.
    static let fallback = InstanceConfig(
        markdown: true, library: true, chat: true, albums: true, ai: false
    )
}

// Ikona SF Symbol per sekcja — używana przez sidebar i placeholdery.
extension ShellSection {
    var symbolName: String {
        switch kind {
        case .feed: "house"
        case .library: "bookmark"
        case .albums: "photo.on.rectangle.angled"
        case .chat: "bubble.left.and.bubble.right"
        case .aiChat: "sparkles"
        case .calendar: "calendar"
        case .stats: "chart.bar"
        }
    }
}
