import SwiftUI
import UIKit

// Design tokens — jedyne źródło stylowania UI (issue #2).
// Wartości to wierna konwersja oklch → sRGB z tożsamości webu (src/styles.css,
// motyw jasny + ciemny). Widoki używają WYŁĄCZNIE tych tokenów — żadnych
// „gołych" kolorów.

extension Color {

    // MARK: — Powierzchnie

    /// Tło aplikacji.
    static let wspBackground = dynamic(light: 0xE8E8E8, dark: 0x0D0D0D)
    /// Karty / wypukłe powierzchnie.
    static let wspCard = dynamic(light: 0xD1D1D1, dark: 0x1C1C1C)
    /// Delikatne wypełnienia (pola, pigułki).
    static let wspMuted = dynamic(light: 0xEDEDED, dark: 0x292929)
    /// Obramowania i separatory.
    static let wspBorder = dynamic(light: 0xDFDFDF, dark: 0x292929)

    // MARK: — Treść

    /// Tekst główny.
    static let wspText = dynamic(light: 0x171717, dark: 0xFFFFFF)
    /// Tekst pomocniczy.
    static let wspMutedText = dynamic(light: 0x202020, dark: 0xA2A2A2)

    // MARK: — Akcenty

    /// Zielony Wspólniaka — akcent podstawowy (przyciski, zaznaczenia).
    static let wspPrimary = dynamic(light: 0x2BC585, dark: 0x167C51)
    /// Tekst/ikona na zielonym.
    static let wspOnPrimary = dynamic(light: 0x212B27, dark: 0xFFFFFF)
    /// Niebieski — akcent poboczny (linki, informacje).
    static let wspSecondary = dynamic(light: 0x479FFF, dark: 0x0C275F)
    /// Tekst na niebieskim.
    static let wspOnSecondary = dynamic(light: 0x171717, dark: 0xFAFAFA)
    /// Czerwony — błędy i destrukcyjne akcje.
    static let wspDanger = dynamic(light: 0xDE3716, dark: 0xE60000)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// Odstępy — skala z webu (--spacing: 0.22rem ≈ 3.5px, krotności 4 pt zaokrąglone).
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let lg: CGFloat = 22
    static let xl: CGFloat = 35
}
