import SwiftUI

// Primary: the one thing the screen wants you to do. Secondary: the accent's quiet form.
// Destructive: a soft red. All capsules, 52pt (42 compact), text fitted to one line.

public struct PokyhButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, secondary, destructive }

    let kind: Kind
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    public init(_ kind: Kind, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(compact ? .headline : .button)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? Spacing.lg : Spacing.xxl)
            .frame(minWidth: compact ? 88 : 120, minHeight: compact ? 42 : 52)
            .background(background, in: .capsule)
            .overlay {
                Capsule().fill(Palette.textPrimary.opacity(configuration.isPressed ? (scheme == .dark ? 0.07 : 0.045) : 0))
            }
            .contentShape(.capsule)
            .animation(.easeOut(duration: Motion.fast), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: Brand.accent.opacity(isEnabled ? 1 : 0.45)
        case .secondary: Palette.accentTint
        case .destructive: Brand.danger.opacity(scheme == .dark ? 0.18 : 0.09)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Brand.onAccent.opacity(isEnabled ? 1 : 0.85)
        case .secondary: isEnabled ? Palette.accentText : Palette.textTertiary
        case .destructive: Brand.danger
        }
    }
}

extension ButtonStyle where Self == PokyhButtonStyle {
    public static var primary: PokyhButtonStyle { PokyhButtonStyle(.primary) }
    public static var secondary: PokyhButtonStyle { PokyhButtonStyle(.secondary) }
    public static var destructive: PokyhButtonStyle { PokyhButtonStyle(.destructive) }
    public static func primary(compact: Bool) -> PokyhButtonStyle { PokyhButtonStyle(.primary, compact: compact) }
    public static func secondary(compact: Bool) -> PokyhButtonStyle { PokyhButtonStyle(.secondary, compact: compact) }
}

/// Button content with an optional leading symbol or a spinner while busy.
public struct ButtonLabel: View {
    let title: String
    let symbol: String?
    let busy: Bool

    public init(_ title: String, symbol: String? = nil, busy: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.busy = busy
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            if busy {
                ProgressView().controlSize(.small).tint(.primary)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
            }
            Text(title)
        }
    }
}

/// Plain accent text, for "Alle anzeigen" and friends.
public struct TextLinkButton: View {
    let title: String
    let symbol: String?
    let color: Color
    let action: () -> Void

    public init(_ title: String, symbol: String? = nil, color: Color = Palette.accentText, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Text(title).textStyle(.headline).lineLimit(2)
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(.capsule)
        }
        .buttonStyle(.rowPress(radius: 999))
        .foregroundStyle(color)
    }
}

/// Round icon button, 40pt by default, optionally on a cardAlt disc.
public struct IconButton: View {
    let symbol: String
    let label: String
    let tinted: Bool
    let size: CGFloat
    let tint: Color
    let action: () -> Void

    public init(_ symbol: String, label: String, tinted: Bool = false, size: CGFloat = 40, tint: Color = Palette.textPrimary, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.tinted = tinted
        self.size = size
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(tinted ? Palette.cardAlt : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.rowPress(radius: size / 2))
        .accessibilityLabel(label)
    }
}

/// The floating action button. On iOS 26 it's tinted glass, which is what Apple's own apps float now.
public struct FloatingActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    public init(_ title: String, symbol: String = "plus", action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .textStyle(.headline)
                .foregroundStyle(Brand.onAccent)
                .padding(.horizontal, Spacing.xl)
                .frame(height: 50)
        }
        #if os(iOS)
        .glassEffect(.regular.tint(Brand.accent).interactive(), in: .capsule)
        #endif
    }
}
