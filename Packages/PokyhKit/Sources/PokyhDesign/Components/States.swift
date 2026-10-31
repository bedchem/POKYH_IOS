import SwiftUI
import PokyhCore

/// Empty, error and offline states. The pixel scene goes on top when there is one.
public struct StateView<Art: View, Actions: View>: View {
    let title: String
    let message: String?
    let detail: String?
    let compact: Bool
    let art: Art
    let actions: Actions

    public init(
        _ title: String,
        message: String? = nil,
        detail: String? = nil,
        compact: Bool = false,
        @ViewBuilder art: () -> Art = { EmptyView() },
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.detail = detail
        self.compact = compact
        self.art = art()
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 0) {
            art.padding(.bottom, compact ? Spacing.lg : Spacing.xl)
            Text(title)
                .textStyle((compact ? TextStyle.callout : .headline).weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: 340)
            if let message {
                Text(message)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: 360)
                    .padding(.top, 6)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: 380)
                    .padding(.top, 6)
                    .selectableText()
            }
            actions.padding(.top, Spacing.xl)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, compact ? Spacing.xl : Spacing.huge)
        .frame(maxWidth: .infinity)
    }
}

extension StateView where Art == PixelSpriteArt {
    /// The usual state: a pixel scene, smaller when compact.
    public init(
        _ title: String,
        message: String? = nil,
        detail: String? = nil,
        compact: Bool = false,
        sprite: PixelSprite,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.init(title, message: message, detail: detail, compact: compact, art: {
            PixelSpriteArt(sprite, width: compact ? 120 : 160)
        }, actions: actions)
    }
}

/// What kind of failure a message describes, the way the web's ErrorView reads it.
public enum FailureKind: Sendable {
    case session, offline, generic

    public init(message: String) {
        let m = message.lowercased()
        let session = ["session", "sitzung", "sessione", "login", "auth", "unauthorized", "angemeldet", "anmelden", "accedi", "sign in"]
        let offline = ["network", "netzwerk", "fetch", "offline", "verbindung", "connessione", "connection", "timeout", "econnrefused", "internet"]
        if session.contains(where: m.contains) {
            self = .session
        } else if offline.contains(where: m.contains) {
            self = .offline
        } else {
            self = .generic
        }
    }

    public var sprite: PixelSprite { self == .session ? .lock : .unplugged }
}

public struct ErrorStateView: View {
    let message: String
    let retry: (() -> Void)?
    @Environment(\.strings) private var s

    public init(_ message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        StateView(s.states.failedTitle, message: message, sprite: FailureKind(message: message).sprite) {
            if let retry {
                Button(s.common.retry, action: retry).buttonStyle(.secondary(compact: true))
            }
        }
    }
}

public struct LoadingStateView: View {
    let label: String?

    public init(_ label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView().controlSize(.large).tint(Brand.accent)
            if let label {
                Text(label).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.huge)
    }
}

/// A quiet notice inside a screen: tinted icon tile and a line of text.
public struct InlineNotice: View {
    let text: String
    let symbol: String
    let tint: Color

    public init(_ text: String, symbol: String = "info.circle.fill", tint: Color = Brand.accent) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: Spacing.md) {
            IconTile(symbol, color: tint, size: 38)
            Text(text)
                .textStyle(.callout)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The same with a pixel scene beside it: for a block with nothing to show, so an empty block
/// still looks like POKYH.
public struct PixelNotice: View {
    let sprite: PixelSprite
    let text: String

    public init(_ sprite: PixelSprite, text: String) {
        self.sprite = sprite
        self.text = text
    }

    public var body: some View {
        HStack(spacing: Spacing.md) {
            PixelSpriteArt(sprite, width: 72)
            Text(text)
                .textStyle(.callout)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Grey blocks while loading. Pulses unless Reduce Motion is on.
public struct SkeletonBlock: View {
    let height: CGFloat
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    public init(height: CGFloat = 16, radius: CGFloat = Radius.xs) {
        self.height = height
        self.radius = radius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.cardAlt)
            .frame(height: height)
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

extension View {
    // The watch has no text selection.
    @ViewBuilder func selectableText() -> some View {
        #if os(watchOS)
        self
        #else
        textSelection(.enabled)
        #endif
    }
}
