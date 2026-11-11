import SwiftUI
import PokyhCore
import PokyhDesign

/// Lock screen. Tries Face ID once on appear (not right after signing out on purpose). The saved
/// accounts and "Manuell anmelden" are always there; only the status line reacts to failed
/// attempts. Same calm layout as sign-in. Nothing of the account's data is shown here.
/// Accounts can be removed from here (edit mode or their menu), as no password is needed for that.
struct LockView: View {
    @Environment(AppState.self) var app
    @Environment(\.strings) private var s
    @State private var appeared = false
    @State private var failures = 0
    /// What actually went wrong after the face was accepted, so a failed WebUntis login
    /// doesn't read as a failed Face ID.
    @State private var problem: String?
    /// Tapping an account asks to remove it instead of unlocking it.
    @State private var editing = false
    @State private var accountToRemove: SavedAccount?

    private var showFallback: Bool { problem != nil || failures >= 3 }

    /// The saved account whose sign-in just failed, offered with its password.
    private var failedAccount: SavedAccount? {
        guard problem != nil, let name = app.failedAccount else { return nil }
        return AccountRoster.find(name, in: app.accounts)
    }

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
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: editing)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: app.accounts)
        .task {
            // A sign-in that failed behind the app before it locked says why here.
            if let message = app.error {
                problem = message
                app.error = nil
            }
            guard !appeared else { return }
            appeared = true
            if app.consumeAutoUnlock() { await attemptUnlock() }
        }
        .onChange(of: app.showAddAccount) { _, open in
            // Signing in by hand: the failed unlock's message no longer applies.
            if open {
                problem = nil
                editing = false
            }
        }
        .sheet(isPresented: Bindable(app).showAddAccount) {
            NavigationStack { LoginView(isAdditional: true, prompt: app.passwordPrompt) }
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
                // Whatever went wrong, the account's own password still gets in.
                if !app.busy, let failedAccount {
                    TextLinkButton(s.login.lockWithPassword, symbol: "key") {
                        app.enterPassword(for: failedAccount.username)
                    }
                    .transition(.opacity)
                }
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
                    Button { app.addAccount() } label: {
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
                Button { app.addAccount() } label: {
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
        // Waiting for the authenticator code isn't a failed attempt.
        guard !ok, !app.showAddAccount, app.twoFactor == nil else { return }
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
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Button { editing.toggle() } label: {
                        Text(editing ? s.common.done : s.common.edit)
                            .textStyle(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.accentText)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: 36)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contentTransition(.opacity)
                }
            ListCard(app.accounts) { acc in
                accountRow(acc)
            }
        }
        .frame(maxWidth: 340)
    }

    private func accountRow(_ acc: SavedAccount) -> some View {
        let hasPassword = app.accountHasPassword(acc.username)
        return PokyhRow(acc.title, subtitle: acc.displayName, showChevron: !editing, action: {
            if editing {
                accountToRemove = acc
            } else {
                Task { await attemptUnlock(acc.username) }
            }
        }) {
            HStack(spacing: Spacing.md) {
                if editing {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Palette.danger)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .accessibilityLabel(s.profile.removeAccountConfirm)
                }
                AvatarView(url: acc.imageUrl, name: acc.username, size: 36, colorSeed: acc.username)
            }
        } trailing: {
            if !editing {
                HStack(spacing: Spacing.sm) {
                    if acc.username == app.defaultUsername {
                        MiniBadge(s.login.lockDefault, symbol: "star.fill", color: Palette.accent)
                    }
                    // Face ID opens it, or the password has to be typed again.
                    Image(systemName: hasPassword ? app.biometricInfo.symbol : "key")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            }
        }
        // The lifted row in the menu gets the card under it, not a see-through cut-out.
        .background(Palette.card)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .contextMenu {
            if !editing {
                Button { app.enterPassword(for: acc.username) } label: {
                    Label(s.login.lockWithPassword, systemImage: "key")
                }
                Button(role: .destructive) { accountToRemove = acc } label: {
                    Label(s.profile.removeAccountConfirm, systemImage: "trash")
                }
            }
        }
        .accessibilityValue(hasPassword ? "" : s.profile.needsPassword)
        .accessibilityAction(named: s.profile.removeAccountConfirm) { accountToRemove = acc }
        // On the row, so the iPad's popover points at it.
        .confirmationDialog(s.profile.removeAccountTitle, isPresented: removing(acc), titleVisibility: .visible) {
            Button(s.profile.removeAccountConfirm, role: .destructive) { remove(acc) }
            Button(s.common.cancel, role: .cancel) {}
        } message: {
            Text(s.profile.removeAccountBody(acc.title))
        }
    }

    private func removing(_ acc: SavedAccount) -> Binding<Bool> {
        Binding {
            accountToRemove?.id == acc.id
        } set: { shown in
            if !shown, accountToRemove?.id == acc.id { accountToRemove = nil }
        }
    }

    private func remove(_ acc: SavedAccount) {
        accountToRemove = nil
        if AccountRoster.same(app.failedAccount ?? "", acc.username) { problem = nil }
        Task {
            // The dialog leaves first: the last account takes the lock screen with it.
            try? await Task.sleep(for: .milliseconds(350))
            app.removeAccount(username: acc.username)
            if app.accounts.isEmpty { editing = false }
        }
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
