import SwiftUI

// Placeholder sekcji powłoki (Faza 1). Treść ekranów wchodzi w Fazach 3+;
// ta ekran-wypełniacz tylko pokazuje, że sekcja istnieje i ma polskie etykiety.

struct SectionPlaceholderView: View {
    let section: ShellSection

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: section.symbolName)
                .font(.system(size: 48))
                .foregroundStyle(Color.wspPrimary)
            Text(section.title)
                .font(.wspTitle())
                .foregroundStyle(Color.wspText)
            Text(section.headline)
                .font(.wspBody(16))
                .foregroundStyle(Color.wspMutedText)
                .multilineTextAlignment(.center)
            Text("Ta sekcja powstanie w jednej z kolejnych faz.")
                .font(.wspBody(13))
                .foregroundStyle(Color.wspMutedText)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wspBackground)
        .navigationTitle(section.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private extension ShellSection {
    var headline: String {
        switch kind {
        case .feed: "Tu pojawi się kronika rodziny."
        case .library: "Tu zobaczysz wszystkie zdjęcia kiedykolwiek udostępnione przez rodzinę."
        case .albums: "Tu będą albumy ze zdjęciami z okazji rodzinnych."
        case .chat: "Tu będzie czat rodzinny na żywo."
        case .aiChat: "Tu będzie asystent AL — pomoc AI dla rodziny."
        case .calendar: "Tu będzie kalendarz rodzinny."
        case .stats: "Tu będą statystyki rodziny."
        }
    }
}
