import SwiftUI
import PokyhCore
import PokyhDesign

/// Lock screen. Tries Face ID once on appear (not right after signing out on purpose). The saved
/// accounts and "Manuell anmelden" are always there; only the status line reacts to failed
/// attempts. Same calm layout as sign-in. Nothing of the account's data is shown here.
struct LockView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var appeared = false
    @State private var failures = 0
    /// What actually went wrong after the face was accepted, so a failed WebUntis login
    /// doesn't read as a failed Face ID.
    @State private var problem: String?

    private var showFallback: Bool { problem != nil || failures >= 3 }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .padding(.horizontal, Spacing.screenH)
                    .centeredForm()
                    .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.bg.ignoresSafeArea())
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: app.busy)
        .animation(.easeInOut(duration: Motion.standard), value: statusText)
        .task {
            guard !appeared else { return }
            appeared = true
            if app.consumeAutoUnlock() { await attemptUnlock() }
        }
        .onChange(of: app.showAddAccount) { _, open in
            // Signing in by hand: the failed unlock's message no longer applies.
            if open { problem = nil }
        }
        .sheet(isPresented: $app.showAddAccount) {
            NavigationStack { LoginView(isAdditional: true) }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.xxl)

            UnlockMark(busy: app.busy).fadeIn()

            Spacer().frame(height: Spacing.xl)

            VStack(spacing: Spacing.sm) {
                Text("POKYH")
                    .textStyle(.wordmark)
                    .foregroundStyle(Palette.textPrimary)
                Text(statusText)
                    .textStyle(.callout)
                    .foregroundStyle(showFallback ? Palette.danger : Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
            }
            .fadeIn(delay: 0.05)

            Spacer().frame(height: Spacing.xxxl)

            // While an unlock runs the screen is the mark and the status line, nothing to tap.
            if !app.busy {
                VStack(spacing: 0) {
                    if !app.accounts.isEmpty {
                        accountChooser
                        OrDivider(text: s.login.lockOr)
                            .frame(maxWidth: 320)
                            .padding(.vertical, Spacing.xl)
                    }
                    Button { app.showAddAccount = true } label: {
                        ButtonLabel(s.login.lockManual, symbol: "key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary)
                    .frame(maxWidth: 300)
                }
                .fadeIn(delay: 0.15)
                .transition(.opacity)
            }

            Spacer(minLength: Spacing.xxl)

            if !app.busy {
                Button { app.showAddAccount = true } label: {
                    Label(s.login.lockAddOther, systemImage: "person.badge.plus")
                        .textStyle(.headline)
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .contentShape(.capsule)
                }
                .buttonStyle(.rowPress(radius: 999))
                .padding(.bottom, Spacing.xxl)
                .fadeIn(delay: 0.2)
                .transition(.opacity)
            }
        }
    }

    private var statusText: String {
        if app.busy { return app.statusText.isEmpty ? s.login.signingIn : app.statusText }
        if let problem { return problem + "\n" + s.login.lockChoose }
        if showFallback { return s.login.lockUnavailable + "\n" + s.login.lockChoose }
        let device = app.biometricInfo
        // No passcode on the device: nothing can be unlocked, only signed into by hand.
        if device.known && !device.available { return device.phrase(s.login.lockNoBiometric, s.lang) + "\n" + s.login.lockChoose }
        // "Mit Face ID entsperren" rather than Android's generic "Biometrie".
        return device.phrase(s.login.lockPrompt, s.lang)
    }

    private func attemptUnlock(_ username: String? = nil) async {
        guard !app.busy else { return }
        problem = nil
        let ok = await app.unlock(into: username)
        guard !ok, !app.showAddAccount else { return }
        // The face was accepted when the login left an error behind.
        if let message = app.error {
            problem = message
        } else {
            failures += 1
        }
    }

    private var accountChooser: some View {
        VStack(spacing: Spacing.md) {
            EyebrowLabel(s.login.lockSaved)
            ListCard(app.accounts) { acc in
                PokyhRow(acc.title, subtitle: acc.displayName, action: {
                    Task { await attemptUnlock(acc.username) }
                }) {
                    AvatarView(url: acc.imageUrl, name: acc.username, size: 36, colorSeed: acc.username)
                } trailing: {
                    HStack(spacing: Spacing.sm) {
                        if acc.username == app.defaultUsername {
                            MiniBadge(s.login.lockDefault, symbol: "star.fill", color: Palette.accent)
                        }
                        // Face ID opens it, or the password has to be typed again.
                        Image(systemName: app.accountHasPassword(acc.username) ? app.biometricInfo.symbol : "key")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(maxWidth: 340)
    }
}

/// "—— oder ——"
private struct OrDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            line
            Text(text).textStyle(.caption).foregroundStyle(Palette.textTertiary)
            line
        }
    }

    private var line: some View {
        Rectangle().fill(Palette.border).frame(height: 1)
    }
}

/// The mark, with the unlock drawn around it while it runs: a faint track and two arcs turning
/// opposite ways, the mark rounding into a circle and breathing a little. Same footprint either
/// way, so nothing below moves when an unlock starts.
private struct UnlockMark: View {
    let busy: Bool
    private let markSize: CGFloat = 84

    var body: some View {
        ZStack {
            if busy {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let sweep = t.truncatingRemainder(dividingBy: 1.5) / 1.5 * 360
                    ZStack {
                        Circle().stroke(Palette.accent.opacity(0.14), lineWidth: 3)
                        arc(96, color: Palette.accent).rotationEffect(.degrees(sweep))
                        arc(52, color: Palette.accent.opacity(0.45)).rotationEffect(.degrees(180 - sweep * 0.65))
                    }
                    .padding(1.5)
                }
                .transition(.opacity)
            }
            AppLogo(size: markSize)
                .clipShape(RoundedRectangle(cornerRadius: busy ? markSize / 2 : markSize * 0.26, style: .continuous))
                .scaleEffect(busy ? 1.04 : 1)
        }
        .frame(width: markSize + Spacing.md * 2, height: markSize + Spacing.md * 2)
        .animation(Motion.smooth, value: busy)
        .accessibilityHidden(true)
    }

    private func arc(_ degrees: Double, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: degrees / 360)
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

/// The app logo (asset "AppLogo").
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
