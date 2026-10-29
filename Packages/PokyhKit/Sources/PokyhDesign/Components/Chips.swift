import SwiftUI

// A chip's fill is always its own color at 13%, so it agrees with the icon or text beside it.
private let chipFill = 0.13

public struct TagChip: View {
    let text: String
    let symbol: String?
    let color: Color
    let large: Bool

    public init(_ text: String, symbol: String? = nil, color: Color, large: Bool = false) {
        self.text = text
        self.symbol = symbol
        self.color = color
        self.large = large
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: large ? 12 : 9, weight: .bold))
            }
            Text(text).textStyle(large ? .caption : .badgeChip).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, large ? Spacing.md : Spacing.sm)
        .padding(.vertical, large ? 6 : 3)
        .background(color.opacity(chipFill), in: .capsule)
    }
}

public struct MiniBadge: View {
    let text: String
    let symbol: String?
    let color: Color

    public init(_ text: String, symbol: String? = nil, color: Color) {
        self.text = text
        self.symbol = symbol
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            }
            Text(text).textStyle(.badgeChip).lineLimit(1).fixedSize()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(chipFill), in: .capsule)
    }
}

/// A symbol on a 13% wash of its own color. Radius follows the size so the corner reads the same.
public struct IconTile: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    public init(_ symbol: String, color: Color, size: CGFloat = 44) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(chipFill), in: .pokyh(size <= 40 ? Radius.sm : Radius.md))
            .accessibilityHidden(true)
    }
}

public struct NeutralIconTile: View {
    let symbol: String
    let size: CGFloat

    public init(_ symbol: String, size: CGFloat = 44) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .frame(width: size, height: size)
            .background(Palette.cardAlt, in: .pokyh(size <= 40 ? Radius.sm : Radius.md))
            .accessibilityHidden(true)
    }
}

/// Symbol + caption in one status color, no fill.
public struct StatusLabel: View {
    let text: String
    let symbol: String
    let color: Color

    public init(_ text: String, symbol: String, color: Color) {
        self.text = text
        self.symbol = symbol
        self.color = color
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(text).textStyle(.caption).lineLimit(1)
        }
        .foregroundStyle(color)
    }
}

/// Accent count bubble, ringed in the canvas color so it sits cleanly on any icon.
public struct UnreadBadge: View {
    let count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .textStyle(.badgeChip)
                .foregroundStyle(Brand.onAccent)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Brand.accent, in: .capsule)
                .padding(2)
                .background(Palette.bg, in: .capsule)
                .accessibilityLabel("\(count)")
        }
    }
}
