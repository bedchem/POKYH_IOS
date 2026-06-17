import SwiftUI

/// Sperrbildschirm: beim Öffnen startet automatisch Face ID, danach Login.
/// Mehrere Konten wählbar. Liquid-Glass-Elemente.
struct LockView: View {
    @EnvironmentObject var app: AppState
    @State private var appeared = false
    @State private var failures = 0

    /// Nach 3 Fehlversuchen: Konto-Auswahl + Passwort-Login anbieten.
    private var showFallback: Bool { failures >= 3 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.accent.opacity(0.28), Palette.accentSoft.opacity(0.12), Palette.bg],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()
                AppLogo(size: 96).fadeIn()

                VStack(spacing: 6) {
                    Text("POKYH").font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(statusText)
                        .font(.subheadline).foregroundStyle(showFallback ? Palette.danger : Palette.textSecondary)
                        .multilineTextAlignment(.center).contentTransition(.opacity)
                }
                .fadeIn(delay: 0.05)

                if app.busy {
                    ProgressView().controlSize(.large).tint(Palette.accent).frame(height: 64)
                } else {
                    unlockButton.fadeIn(delay: 0.1)
                }

                // Konto-Auswahl: ab 2 Konten immer, nach 3 Fehlversuchen hervorgehoben.
                if app.accounts.count > 1 || showFallback {
                    accountChooser.fadeIn(delay: 0.15)
                }

                Spacer()

                VStack(spacing: 12) {
                    if showFallback {
                        Button { app.showAddAccount = true } label: {
                            Label("Mit Passwort anmelden", systemImage: "key.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                        }
                        .buttonStyle(.glassProminent).tint(Palette.accent).frame(maxWidth: 280)
                    }
                    Button { app.showAddAccount = true } label: {
                        Label("Anderes Konto hinzufügen", systemImage: "person.badge.plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.pressable).tint(Palette.accent)
                }
                .padding(.bottom, 24)
                .fadeIn(delay: 0.2)
            }
            .padding(.horizontal, 24)
            .centeredForm()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: app.busy)
        .animation(.easeInOut, value: showFallback)
        .task {
            if !appeared { appeared = true; await attemptUnlock() }
        }
        .sheet(isPresented: $app.showAddAccount) {
            NavigationStack { LoginView(isAdditional: true) }
        }
    }

    private var statusText: String {
        if app.busy { return app.statusText.isEmpty ? "Anmelden…" : app.statusText }
        if showFallback { return "\(app.biometricInfo.typeName) fehlgeschlagen.\nWähle ein Konto oder melde dich mit Passwort an." }
        return "Mit \(app.biometricInfo.typeName) entsperren"
    }

    private func attemptUnlock(_ username: String? = nil) async {
        let ok = await app.unlock(into: username)
        if !ok { failures += 1 }
    }

    private var unlockButton: some View {
        Button { Task { await attemptUnlock() } } label: {
            HStack(spacing: 10) {
                Image(systemName: app.biometricInfo.symbol).font(.title3)
                Text(showFallback ? "Erneut versuchen" : "Entsperren").font(.headline)
            }
            .frame(maxWidth: .infinity).frame(height: 56).padding(.horizontal, 24)
        }
        .buttonStyle(.glassProminent).tint(Palette.accent).frame(maxWidth: 280)
    }

    private var accountChooser: some View {
        VStack(spacing: 8) {
            Text("Konto wählen").font(.caption).foregroundStyle(Palette.textTertiary)
            ForEach(app.accounts) { acc in
                Button { Task { await attemptUnlock(acc.username) } } label: {
                    HStack(spacing: 12) {
                        AvatarView(url: acc.imageUrl, name: acc.username, size: 34, colorSeed: acc.username)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(acc.username).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                                if acc.username == app.defaultUsername {
                                    Text("Standard").font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Palette.accent.opacity(0.2), in: Capsule()).foregroundStyle(Palette.accent)
                                }
                            }
                            Text(acc.displayName).font(.caption2).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: app.biometricInfo.symbol).font(.caption).foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.pressable)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
        }
        .frame(maxWidth: 320)
    }
}

/// App-Logo — verwendet das echte Frontend-Icon (Asset „AppLogo").
struct AppLogo: View {
    var size: CGFloat = 84
    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}
