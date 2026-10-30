//
//  ContentView.swift
//  POKYH
//

import SwiftUI
import PokyhCore
import PokyhDesign

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s

    /// The scheme actually applied. It switches under a short fade so light ⇄ dark
    /// crossfades instead of snapping.
    @State private var appliedScheme: ColorScheme?
    @State private var themeFade = false
    /// The offline notice stays until closed; closing it holds until the next time we go offline.
    @State private var offlineDismissed = false

    private static let fadeDuration = 0.22

    var body: some View {
        Group {
            switch app.phase {
            case .authed: RootTabView().id(app.session?.username ?? "")  // new account, fresh tabs
            case .lock:   LockView().transition(.opacity)
            case .login:  LoginView().transition(.opacity)
            }
        }
        .overlay {
            if app.busy && app.phase == .authed {
                SwitchingOverlay(text: app.statusText.isEmpty ? s.nav.switching : app.statusText)
                    .transition(.opacity)
            }
        }
        // Running on cached data: drops in from the top, like Android's OfflineNotice.
        .overlay(alignment: .top) {
            if app.isOffline && app.phase == .authed && !offlineDismissed {
                OfflineBanner { offlineDismissed = true }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: app.isOffline)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: offlineDismissed)
        .onChange(of: app.isOffline) { _, offline in
            if !offline { offlineDismissed = false }
        }
        // Privacy notice after the first sign-in or when it changed. A banner, signed in only,
        // until "Verstanden".
        .overlay(alignment: .top) {
            if let notice = app.privacyNotice, app.phase == .authed {
                PrivacyNoticeBanner(notice: notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: app.privacyNotice)
        .overlay {
            if themeFade {
                Color(.systemBackground).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: app.phase)
        .animation(.easeInOut(duration: 0.25), value: app.busy)
        .tint(Palette.accent)
        .preferredColorScheme(appliedScheme)
        .onAppear { if appliedScheme == nil { appliedScheme = app.colorScheme } }
        .onChange(of: app.themeMode) { _, _ in crossfadeTheme() }
    }

    /// Fade in, switch the scheme underneath, fade out.
    private func crossfadeTheme() {
        let target = app.colorScheme
        guard target != appliedScheme else { return }
        withAnimation(.easeInOut(duration: Self.fadeDuration)) { themeFade = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration) {
            appliedScheme = target
            withAnimation(.easeInOut(duration: Self.fadeDuration)) { themeFade = false }
        }
    }
}

/// Dimmed page plus a spinner card, e.g. while switching accounts.
struct SwitchingOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Palette.bg.opacity(0.72).ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                ProgressView().controlSize(.large).tint(Palette.accent)
                Text(text).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
            }
            .padding(Spacing.xxxl)
            .floatingSurface(radius: Radius.xl)
        }
    }
}

/// Signed in on stored data. Says so, says what that means, and waits to be closed.
struct OfflineBanner: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.md) {
            IconTile("wifi.slash", color: Palette.warning, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.system.offlineSignedIn)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                Text(s.system.savedShown)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 40, height: 40)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.system.closeNotice)
            }
        }
        .padding(.leading, Spacing.lg)
        .padding(.vertical, Spacing.lg)
        .padding(.trailing, Spacing.xs)
        .floatingSurface(radius: Radius.lg)
        .padding(.horizontal, Spacing.screenH)
        .frame(maxWidth: WidthClass.formMaxWidth + Spacing.screenH * 2)
        .padding(.top, Spacing.sm)
    }
}

extension AppState.Phase: Equatable {}

#Preview {
    ContentView().environmentObject(AppState())
}
