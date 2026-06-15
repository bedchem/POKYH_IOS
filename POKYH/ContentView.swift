//
//  ContentView.swift
//  POKYH
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

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
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: app.phase)
        .animation(.easeInOut(duration: 0.25), value: app.busy)
        .tint(Palette.accent)
        .preferredColorScheme(app.colorScheme)
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
