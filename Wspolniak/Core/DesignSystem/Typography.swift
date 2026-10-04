import SwiftUI

// Typografia — fonty z tożsamości webu (src/styles.css):
// sans → ABeeZee, serif → Source Serif 4, mono → IBM Plex Mono.
// Pliki .ttf są w bundlu i rejestrowane przez UIAppFonts (Config/*-Info.plist).

enum FontFamilyTokens {
    static let sans = "ABeeZee"
    static let serif = "SourceSerif4-Variable"
    static let mono = "IBMPlexMono-Regular"
}

extension Font {
    /// Tekst podstawowy.
    static func wspBody(_ size: CGFloat = 17) -> Font {
        .custom(FontFamilyTokens.sans, size: size)
    }

    /// Nagłówki ekranów.
    static func wspTitle(_ size: CGFloat = 28) -> Font {
        .custom(FontFamilyTokens.sans, size: size)
    }

    /// Treść postów — serif jak na webie.
    static func wspSerif(_ size: CGFloat = 17) -> Font {
        .custom(FontFamilyTokens.serif, size: size)
    }

    /// Fragmenty techniczne (kody, identyfikatory).
    static func wspMono(_ size: CGFloat = 15) -> Font {
        .custom(FontFamilyTokens.mono, size: size)
    }
}
