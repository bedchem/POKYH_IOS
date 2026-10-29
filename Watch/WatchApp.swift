import SwiftUI
import PokyhCore
import PokyhDesign

@main
struct POKYHWatchApp: App {
    private let strings = Strings.of(LanguageChoice.current(in: .standard))

    var body: some Scene {
        WindowGroup {
            SignInOnPhoneView()
                .environment(\.strings, strings)
        }
    }
}

/// What the watch shows until the iPhone has handed over a signed-in account.
struct SignInOnPhoneView: View {
    @Environment(\.strings) private var s

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                IconTile("iphone", color: Brand.accent, size: 48)
                Text(s.watch.signInTitle)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(s.watch.signInMessage)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.sm)
        }
        .navigationTitle("POKYH")
    }
}

#Preview {
    SignInOnPhoneView()
}
