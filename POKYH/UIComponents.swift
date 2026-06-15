import SwiftUI

/// Wiederverwendbare UI-Bausteine (entsprechen components/ui/* im Frontend).

// ── Skeleton-Loader (Shimmer wie `.skeleton` im Web) ────────────────────────

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.18), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 1.5)
                    .offset(x: phase * geo.size.width * 1.5)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

struct SkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    var radius: CGFloat = 8
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.cardAlt)
            .frame(width: width, height: height)
            .modifier(Shimmer())
    }
}

/// Generische Listen-Skeleton (Karten-Reihen).
struct ListSkeleton: View {
    var rows = 6
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(Palette.cardAlt).frame(width: 42, height: 42).modifier(Shimmer())
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(height: 13, width: 160)
                        SkeletonBlock(height: 10, width: 110)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
    }
}

struct TimetableSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 3).fill(Palette.cardAlt).frame(width: 5, height: 42).modifier(Shimmer())
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(height: 13, width: 130)
                            SkeletonBlock(height: 10, width: 90)
                        }
                        Spacer()
                        SkeletonBlock(height: 24, width: 40)
                    }
                    .padding(12)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
        }
    }
}

struct LoadingView: View {
    var body: some View { ListSkeleton() }
}

// ── Zustände ────────────────────────────────────────────────────────────────

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38)).foregroundStyle(Palette.orange)
            Text(message).font(.callout).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button { retry() } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glassProminent).tint(Palette.accent)
            }
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
        .fadeIn()
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44)).foregroundStyle(Palette.accent.opacity(0.7))
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.headline).foregroundStyle(Palette.textSecondary)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        .fadeIn()
    }
}

/// Detaillierte Meldung, wenn eine POKYH-Funktion (Todos/Erinnerungen/Klasse) nicht
/// verfügbar ist — zeigt den konkreten Grund aus `AppState.backendStatus` statt eines
/// generischen „benötigt ein Konto". Bei „Keine Klasse" gibt es einen Hinweis auf die
/// Diagnose im Profil.
struct BackendUnavailableView: View {
    @EnvironmentObject var app: AppState
    let feature: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 96, height: 96)
                Image(systemName: icon).font(.system(size: 40, weight: .medium))
                    .foregroundStyle(tint).symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 8) {
                Text(title).font(.title3.bold()).foregroundStyle(Palette.textPrimary)
                Text(message).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            if case .noClass = app.backendStatus {
                Label("Profil → POKYH-Konto öffnen", systemImage: "person.crop.circle")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Palette.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(32)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fadeIn()
    }

    private var icon: String {
        switch app.backendStatus {
        case .notStudent: return "person.fill.xmark"
        case .noClass:    return "person.2.slash"
        case .failed:     return "wifi.exclamationmark"
        default:          return "lock"
        }
    }
    private var tint: Color {
        if case .failed = app.backendStatus { return Palette.danger }
        return Palette.orange
    }
    private var title: String {
        switch app.backendStatus {
        case .notStudent: return "Nur für Schülerkonten"
        case .noClass:    return "Keine Klasse gefunden"
        case .failed:     return "Verbindungsfehler"
        default:          return "Nicht verfügbar"
        }
    }
    private var message: String {
        switch app.backendStatus {
        case .notStudent:
            return "\(feature) ist nur mit einem Schülerkonto verfügbar."
        case .noClass:
            return "Für \(feature) wird deine WebUntis-Klasse benötigt — sie konnte für dein Konto nicht ermittelt werden."
        case .failed(let m):
            return "\(feature) konnte nicht geladen werden:\n\(m)"
        default:
            return "\(feature) benötigt ein POKYH-Konto."
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

/// Kopf-Aktionen oben rechts (auf jeder Seite): Nachrichten + Profil.
/// Getrennte Toolbar-Items → native Abstände, kein Hit-Testing-Bug.
struct ProfileToolbar: ViewModifier {
    @EnvironmentObject var app: AppState
    @State private var showProfile = false
    @State private var showMessages = false
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showMessages = true } label: {
                        Image(systemName: "envelope")
                    }
                    .accessibilityLabel("Nachrichten")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: {
                        if let s = app.session {
                            AvatarView(url: s.imageUrl, name: s.personName ?? s.username, size: 28)
                        } else {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .accessibilityLabel("Profil")
                }
            }
            .sheet(isPresented: $showProfile) {
                NavigationStack { ProfileView() }
            }
            .sheet(isPresented: $showMessages) {
                MessagesSheet()
            }
    }
}

/// Nachrichten als Modal mit „Fertig"-Button.
struct MessagesSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            MessagesView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Fertig") { dismiss() } }
                }
        }
    }
}

extension View {
    func profileToolbar() -> some View { modifier(ProfileToolbar()) }
}

/// Avatar-Kreis mit Initiale.
struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 40
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Palette.sender(name), Palette.sender(name).opacity(0.7)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

/// Profilbild (WebUntis) mit Initial-Fallback, während/ohne Bild.
struct AvatarView: View {
    let url: String?
    let name: String
    var size: CGFloat = 40
    var body: some View {
        if let url, let u = URL(string: url) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    InitialAvatar(name: name, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            InitialAvatar(name: name, size: size)
        }
    }
}
