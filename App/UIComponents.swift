import SwiftUI
import PokyhCore
import PokyhDesign

// Shared building blocks, styled after Android's ui/components.

// MARK: - Skeletons

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.18), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 1.5)
                        .offset(x: phase * geo.size.width * 1.5)
                    }
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

struct SkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    var radius: CGFloat = Radius.xs
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.cardAlt)
            .frame(width: width, height: height)
            .modifier(Shimmer())
            .accessibilityHidden(true)
    }
}

/// Stands in for a list card: one card, hairline-separated rows, same height as the real ones.
struct ListSkeleton: View {
    var rows = 6
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                if index > 0 { RowSeparator() }
                HStack(spacing: Spacing.iconText) {
                    Circle().fill(Palette.cardAlt).frame(width: 40, height: 40).modifier(Shimmer())
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SkeletonBlock(height: 14, width: 150)
                        SkeletonBlock(height: 11, width: 100)
                    }
                    Spacer(minLength: 0)
                    SkeletonBlock(height: 14, width: 44)
                }
                .padding(.horizontal, Spacing.card)
                .frame(height: 72)
            }
        }
        .clipShape(.pokyh(Radius.xl))
        .cardSurface()
        .padding(.horizontal, Spacing.screenH)
        .padding(.vertical, Spacing.md)
        .accessibilityHidden(true)
    }
}

/// Stands in for the lesson rows: standalone tile rows with the leading accent bar.
struct TimetableSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.rowGap) {
                ForEach(0..<7, id: \.self) { _ in
                    HStack(spacing: Spacing.iconText) {
                        SkeletonBlock(height: 40, width: 4, radius: 2)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SkeletonBlock(height: 14, width: 130)
                            SkeletonBlock(height: 11, width: 90)
                        }
                        Spacer(minLength: 0)
                        SkeletonBlock(height: 14, width: 44)
                    }
                    .padding(Spacing.row)
                    .cardSurface(radius: Radius.lg)
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.vertical, Spacing.md)
        }
        .accessibilityHidden(true)
    }
}

struct LoadingView: View {
    var body: some View { ListSkeleton() }
}

// MARK: - States

/// Something went wrong and retrying is the answer. Says what kind of failure it was, then
/// the technical reason in small type, like Android's ErrorStateView.
struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?
    @Environment(\.strings) private var s

    private var kind: FailureKind { FailureKind(message: message) }

    private var title: String {
        switch kind {
        case .session: s.common.errSessionTitle
        case .offline: s.common.errOfflineTitle
        case .generic: s.common.errGenericTitle
        }
    }

    private var note: String {
        switch kind {
        case .session: s.common.errSessionDetail
        case .offline: s.common.errOfflineDetail
        case .generic: s.common.errGenericDetail
        }
    }

    /// The raw reason, without addresses and kept short.
    private var reason: String? {
        let cleaned = message
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(140))
    }

    var body: some View {
        StateView(title, message: note, detail: reason, sprite: kind.sprite) {
            if let retry {
                Button(action: retry) {
                    ButtonLabel(s.common.retry, symbol: "arrow.clockwise")
                }
                .buttonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fadeIn()
    }
}

/// Nothing to show, and that's fine.
struct EmptyStateView: View {
    let sprite: PixelSprite
    let title: String
    var subtitle: String?

    init(sprite: PixelSprite = .empty, title: String, subtitle: String? = nil) {
        self.sprite = sprite
        self.title = title
        self.subtitle = subtitle
    }

    /// For callers that still name a symbol: the scene that says the same thing.
    init(systemImage: String, title: String, subtitle: String? = nil) {
        let sprite: PixelSprite = switch systemImage {
        case "magnifyingglass": .search
        case "tray", "envelope": .mail
        case "bell": .bell
        default: .empty
        }
        self.init(sprite: sprite, title: title, subtitle: subtitle)
    }

    var body: some View {
        StateView(title, message: subtitle, sprite: sprite)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fadeIn()
    }
}

/// Why a POKYH feature (Todos, Erinnerungen, Klasse) isn't available, with the concrete reason
/// from `AppState.backendStatus` rather than one generic line: each has a different fix.
struct BackendUnavailableView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    let feature: String

    var body: some View {
        StateView(title, message: message, sprite: sprite) {
            if case .noClass = app.backendStatus {
                Text(s.states.openAccount)
                    .textStyle(.caption)
                    .foregroundStyle(Palette.accentText)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(Palette.accentTint, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fadeIn()
    }

    private var sprite: PixelSprite {
        switch app.backendStatus {
        case .failed: .unplugged
        case .noClass: .search
        default: .lock
        }
    }
    private var title: String {
        switch app.backendStatus {
        case .notStudent: return s.states.notStudentTitle
        case .noClass:    return s.states.noClassTitle
        case .failed:     return s.states.failedTitle
        default:          return s.states.unavailableTitle
        }
    }
    private var message: String {
        switch app.backendStatus {
        case .notStudent: return s.states.notStudent(feature)
        case .noClass: return s.states.noClass(feature)
        case .failed(let m): return s.states.failed(feature, m)
        default: return s.states.needsAccount(feature)
        }
    }
}

// MARK: - Cards

/// Android's PokyhCard: one radius, one padding, one elevation.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Spacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

// MARK: - Unread messages

extension AppState {
    /// The badges' count, for the School tab and the envelope. Without WebUntis there's no inbox.
    var unreadBadge: Int { session?.hasUntis == true ? unreadMessages : 0 }

    /// An inbox loaded anywhere sets the count.
    func noteInbox(_ inbox: [MessagePreview]) {
        guard let name = session?.username else { return }
        UnreadCheck.last[name] = Date()
        unreadMessages = inbox.filter { !$0.isRead }.count
    }

    /// Counts the inbox again unless that was just done, so a tab switch doesn't ask WebUntis
    /// every time.
    func refreshUnread(force: Bool = false) async {
        guard let s = session, s.hasUntis, !s.bearerToken.isEmpty else { return }
        if !force, let last = UnreadCheck.last[s.username], Date().timeIntervalSince(last) < UnreadCheck.interval { return }
        guard let inbox = try? await UntisClient.shared.messages(folder: .inbox, s),
              session?.username == s.username else { return }
        noteInbox(inbox)
    }
}

private enum UnreadCheck {
    static var last: [String: Date] = [:]
    static let interval: TimeInterval = 30
}

// MARK: - Tab root actions

extension EnvironmentValues {
    /// The iPhone's tab bar has room for five tabs, so with all of them shown the search moves up
    /// here, where Android has it too.
    @Entry var searchInToolbar = false
}

/// Top right on every tab root: messages and the profile picture, like Android's TabRootActions.
/// Separate toolbar items so they get native spacing.
struct ProfileToolbar: ViewModifier {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.searchInToolbar) private var searchInToolbar
    @State private var showProfile = false
    @State private var showMessages = false
    @State private var showSearch = false

    // WebUntis keeps the messages, so an account without it has no envelope.
    private var hasUntis: Bool { app.session?.hasUntis ?? true }

    func body(content: Content) -> some View {
        let unread = app.unreadBadge
        content
            .toolbar {
                if searchInToolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(s.search.title)
                    }
                    if !hasUntis { ToolbarSpacer(.fixed, placement: .topBarTrailing) }
                }
                if hasUntis {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showMessages = true } label: {
                            Image(systemName: "envelope")
                                .overlay(alignment: .topTrailing) {
                                    UnreadBadge(unread)
                                        .fixedSize()
                                        .offset(x: 11, y: -9)
                                        .allowsHitTesting(false)
                                }
                        }
                        .accessibilityLabel(unread > 0 ? s.nav.messagesUnread(unread) : s.nav.messages)
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: {
                        if let s = app.session {
                            AvatarView(url: s.imageUrl, name: s.personName ?? s.username, size: 36, colorSeed: s.username)
                        } else {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.nav.profile)
                }
                // The photo is already a circle; a glass disc around it only makes it look small.
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $showProfile) {
                NavigationStack { ProfileView() }
            }
            .sheet(isPresented: $showSearch) {
                NavigationStack {
                    SearchView(focusOnAppear: true) { tab in
                        showSearch = false
                        app.selectedTab = tab
                    }
                    .appBackground()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .close) { showSearch = false }
                        }
                    }
                }
            }
            // Whatever was read in there shows on the badge right away.
            .sheet(isPresented: $showMessages, onDismiss: {
                Task { await app.refreshUnread(force: true) }
            }) {
                MessagesSheet()
            }
    }
}

/// Messages as a sheet with a "Fertig" button.
struct MessagesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s
    var body: some View {
        NavigationStack {
            MessagesView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(s.common.done) { dismiss() } }
                }
        }
    }
}

extension View {
    func profileToolbar() -> some View { modifier(ProfileToolbar()) }
}

// MARK: - Avatars

/// Initial on a colored disc. With `colorSeed` (the username) the color is the persisted
/// random one from the profile; without, it hashes the name (message senders).
struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 40
    var colorSeed: String? = nil

    private var color: Color {
        if let seed = colorSeed, !seed.isEmpty { return Palette.color(for: seed) }
        return Palette.sender(name)
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// Profile picture from the local cache (instant, works offline) over the initial, which
/// stays as the placeholder until the picture has loaded.
struct AvatarView: View {
    let url: String?
    let name: String
    var size: CGFloat = 40
    var colorSeed: String? = nil

    @State private var loaded: UIImage?

    private var owner: String { colorSeed ?? name }
    private var key: String { ImageCache.avatarKey(owner) }

    var body: some View {
        let image = loaded ?? ImageCache.inMemory(key)
        ZStack {
            InitialAvatar(name: name, size: size, colorSeed: colorSeed)
                .opacity(image == nil ? 1 : 0)
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(key)|\(url ?? "")") { await load() }
    }

    private func load() async {
        if ImageCache.inMemory(key) == nil, let stored = await ImageCache.stored(key) { show(stored) }
        // Other saved accounts have no session here, so they show what's stored.
        guard let auth = UntisImageAuth.current, AccountRoster.same(auth.username, owner),
              let target = auth.resolve(url) else { return }
        if let fresh = await ImageCache.fetch(target, key: key, headers: auth.headers(for: target)) { show(fresh) }
    }

    private func show(_ image: UIImage) {
        withAnimation(.easeOut(duration: 0.25)) { loaded = image }
    }
}
