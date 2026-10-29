import SwiftUI
import PokyhCore
import PokyhDesign

@main
struct POKYHWatchApp: App {
    @State private var session = WatchSession(
        store: AccountStore(store: KeychainStore(service: AppConfig.current.appBundleID))
    )
    private let strings = Strings.of(LanguageChoice.current(in: .standard))

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let account = session.account {
                    SignedInView(account: account)
                } else {
                    SignInOnPhoneView()
                }
            }
            .environment(\.strings, strings)
            .animation(Motion.standardEase, value: session.account)
            .task { session.activate() }
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

struct SignedInView: View {
    let account: StoredAccount
    @Environment(\.strings) private var s

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                InitialAvatar(account.displayName, color: Palette.avatar(hue: Double(ColorMath.jsHash(account.username) % 360) / 360), size: 44)
                Text(s.watch.hello(account.displayName.split(separator: " ").first.map(String.init) ?? account.displayName))
                    .textStyle(.title3)
                    .foregroundStyle(Palette.textPrimary)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(account.school.displayName)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                    Text(account.username)
                        .textStyle(.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("POKYH")
    }
}

#Preview("Signed out") {
    NavigationStack { SignInOnPhoneView() }
}
