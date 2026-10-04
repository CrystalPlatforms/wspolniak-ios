import XCTest
@testable import Wspolniak

// Założenia (issue #2, AC feature toggles):
// - Sekcje powłoki mirrorują NAV_ITEMS z webu (mobile-sidebar.tsx) w tej samej
//   kolejności: Feed, Biblioteka, Albumy, Chat, Chat AL, Kalendarz, Statystyki.
//   (Admin nie ma sekcji w web menu — apka rodzinna, też pomijamy.)
// - Flaga wyłączona → sekcja NIE istnieje w drzewie nawigacji (nie renderuje
//   się wcale — nie „wyszarzona”).
// - „Chat AL" odpowiada fladze ai — jedyna domyślnie wyłączona (backend
//   DEFAULT_FEATURE_FLAGS). Fallback bez konfiguracji = flagi domyślne.
// - Tytuły sekcji są polskie i odwzorowują web („Chat", nie „Czat" — decyzja
//   użytkownika z webu, F8 #159).
// - NIE testujemy tu: SwiftUI rendering, iPad layout (Faza 12).

final class ShellSectionsTests: XCTestCase {

    func testDisabledFlagRemovesSectionFromNavigationTree() {
        var config = InstanceConfig.allEnabled
        config.library = false
        let sections = ShellSections.sections(for: config)

        XCTAssertFalse(sections.contains { $0.kind == .library },
                       "Wyłączona Biblioteka nie może istnieć w drzewie nawigacji")
        XCTAssertTrue(sections.contains { $0.kind == .feed },
                      "Feed jest zawsze widoczny (bez flagi)")
    }

    func testAllSectionsPresentWhenAllFlagsEnabled() {
        let config = InstanceConfig(
            markdown: true, library: true, chat: true, albums: true, ai: true
        )
        let sections = ShellSections.sections(for: config)

        XCTAssertEqual(sections.map { $0.kind },
                       [.feed, .library, .albums, .chat, .aiChat, .calendar, .stats],
                       "Kolejność jak w web NAV_ITEMS")
    }

    func testFallbackConfigHidesAIChat() {
        // Bez dostępu do konfiguracji (401 w Fazie 1) apka używa domyślnych flag
        // backendu: wszystko ON, AI OFF → „Chat AL" nie istnieje.
        let sections = ShellSections.sections(for: .fallback)

        XCTAssertFalse(sections.contains { $0.kind == .aiChat })
        XCTAssertTrue(sections.contains { $0.kind == .chat })
    }

    func testSectionTitlesArePolish() {
        let config = InstanceConfig(
            markdown: true, library: true, chat: true, albums: true, ai: true
        )
        let titles = ShellSections.sections(for: config).map { $0.title }

        XCTAssertEqual(titles, ["Feed", "Biblioteka", "Albumy", "Chat", "Chat AL",
                                "Kalendarz", "Statystyki"])
    }
}
