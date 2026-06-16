//
//  ContentView.swift
//  POKYH
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    /// Tatsächlich angewandtes Schema — wird verzögert (unter der Fade-Blende)
    /// umgeschaltet, damit Hell⇄Dunkel weich überblendet statt hart springt.
    @State private var appliedScheme: ColorScheme?
    @State private var themeFade = false

    private static let fadeDuration = 0.22

    var body: some View {
        Group {
            switch app.phase {
            case .authed: RootTabView().id(app.session?.username ?? "")  // Kontowechsel → Tabs neu laden
            case .lock:   LockView().transition(.opacity)
            case .login:  LoginView().transition(.opacity)
            }
        }
        .overlay {
            if app.busy && app.phase == .authed {
                SwitchingOverlay(text: app.statusText.isEmpty ? "Lädt…" : app.statusText)
                    .transition(.opacity)
            }
        }
        // Weiche Überblendung beim Wechsel des Erscheinungsbilds.
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

    /// Blende einblenden → Schema unter der Blende wechseln → Blende ausblenden.
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

/// Voll­flächiger Lade-Overlay (z. B. beim Kontowechsel).
struct SwitchingOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Palette.bg.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Palette.accent)
                Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Palette.textSecondary)
            }
            .padding(26)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
    }
}

extension AppState.Phase: Equatable {}

#Preview {
    ContentView().environmentObject(AppState())
}
