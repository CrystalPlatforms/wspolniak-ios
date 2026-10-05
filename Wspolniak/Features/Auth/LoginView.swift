import SwiftUI

// Ekran logowania (Faza 2) — mirror web /share: kod rodzinny → wybór członka
// → sesja. Plus link z zaproszenia: universal link (klik z Maila) albo wklejony
// ręcznie — w dev universal links nie działają na adresach sieci lokalnej.
// UI w 100% po polsku, wyłącznie tokeny z design systemu.

struct LoginView: View {

    private enum Step: Equatable {
        case code
        case members([ShareMember])
        case admin
    }

    let authStore: AuthStore

    @State private var code = ""
    @State private var linkText = ""
    @State private var step: Step = .code

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                header
                stepContent
                if let error = authStore.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.wspBody(14))
                        .foregroundStyle(Color.wspDanger)
                        .multilineTextAlignment(.leading)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.wspMuted, in: RoundedRectangle(cornerRadius: 10))
                }
                linkSection
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Color.wspBackground)
        .navigationTitle("Logowanie")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.wspPrimary)
            Text("Wspólniak")
                .font(.wspTitle(28))
                .foregroundStyle(Color.wspText)
            Text("Kronika rodzinna dla najbliższych.")
                .font(.wspBody(15))
                .foregroundStyle(Color.wspMutedText)
        }
        .padding(.top, Spacing.xl)
    }

    @ViewBuilder
    private var stepContent: some View {
        if authStore.isWorking {
            // Czytelna informacja „coś się dzieje" zamiast ciszy przy wolnej sieci.
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text(step == .code ? "Sprawdzam kod…" : "Loguję…")
                    .font(.wspBody(15))
                    .foregroundStyle(Color.wspMutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
            .background(Color.wspCard, in: RoundedRectangle(cornerRadius: 14))
        } else {
            switch step {
            case .code:
                codeStep
            case .members(let members):
                membersStep(members)
            case .admin:
                adminStep
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Podaj kod rodzinny, który dostałeś od administratora.")
                .font(.wspBody(15))
                .foregroundStyle(Color.wspMutedText)
            TextField("Kod rodzinny", text: $code)
                .font(.wspBody(17))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(Spacing.md)
                .background(Color.wspMuted, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.wspText)
            Button {
                Task { await verifyCode() }
            } label: {
                Text("Dalej")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.wspPrimary)
            .disabled(code.isEmpty || authStore.isWorking)
        }
        .padding(Spacing.lg)
        .background(Color.wspCard, in: RoundedRectangle(cornerRadius: 14))
    }

    private func membersStep(_ members: [ShareMember]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Kto się loguje?")
                .font(.wspTitle(20))
                .foregroundStyle(Color.wspText)
            ForEach(members) { member in
                Button {
                    Task { await login(memberId: member.id) }
                } label: {
                    HStack {
                        Text(member.name)
                            .font(.wspBody(17))
                            .foregroundStyle(Color.wspText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.wspBody(14))
                            .foregroundStyle(Color.wspMutedText)
                    }
                    .padding(Spacing.md)
                    .background(Color.wspMuted, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(authStore.isWorking)
            }
            Button("To nie ja — wróć do kodu") {
                step = .code
            }
            .font(.wspBody(14))
            .foregroundStyle(Color.wspSecondary)
        }
        .padding(Spacing.lg)
        .background(Color.wspCard, in: RoundedRectangle(cornerRadius: 14))
    }

    private var adminStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Rozpoznano kod administratora.")
                .font(.wspBody(15))
                .foregroundStyle(Color.wspMutedText)
            Button {
                Task { await login(memberId: nil) }
            } label: {
                Text("Zaloguj jako administrator")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.wspPrimary)
            .disabled(authStore.isWorking)
        }
        .padding(Spacing.lg)
        .background(Color.wspCard, in: RoundedRectangle(cornerRadius: 14))
    }

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Masz link z zaproszenia? Wklej go tutaj albo po prostu kliknij go w Mailu — aplikacja zaloguje się sama.")
                .font(.wspBody(14))
                .foregroundStyle(Color.wspMutedText)
            TextField("https://…", text: $linkText)
                .font(.wspBody(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(Spacing.md)
                .background(Color.wspMuted, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.wspText)
            Button {
                Task { await authStore.loginWithLinkText(linkText) }
            } label: {
                Text("Zaloguj linkiem")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.wspPrimary)
            .disabled(authStore.isWorking)
        }
        .padding(Spacing.lg)
        .background(Color.wspCard, in: RoundedRectangle(cornerRadius: 14))
    }

    private func verifyCode() async {
        guard let verification = await authStore.verifyCode(code) else { return }
        step = verification.isAdmin ? .admin : .members(verification.members)
    }

    private func login(memberId: String?) async {
        _ = await authStore.login(code: code, memberId: memberId)
        // Sukces przełącza AuthStore.state — RootView sam pokaże powłokę.
    }
}
