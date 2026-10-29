import SwiftUI
import PokyhCore

// The container vocabulary, same as Android: section, card, list card, tile row, feature tile.
// A card means "these belong together"; twenty same-shaped rows are one list card, not twenty cards.

extension EnvironmentValues {
    /// The texts in the language in use. Set once at the app root.
    @Entry public var strings: Strings = .of(.system())
}

/// A titled band of the page; content sits on the canvas.
public struct PokyhSection<Trailing: View, Content: View>: View {
    let title: String?
    let spacing: CGFloat
    let trailing: Trailing
    let content: Content

    public init(
        _ title: String? = nil,
        spacing: CGFloat = Spacing.rowGap,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.spacing = spacing
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.headerContent) {
            if let title {
                SectionHeader(title) { trailing }
            }
            VStack(alignment: .leading, spacing: spacing) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .textStyle(.title2)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            trailing
        }
    }
}

/// All-caps eyebrow. A signpost, not a heading.
public struct EyebrowLabel: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color = Palette.textTertiary) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text.uppercased())
            .textStyle(.label)
            .foregroundStyle(color)
    }
}

/// One radius, one padding, one elevation. Pass an action and it presses like a row.
public struct PokyhCard<Content: View>: View {
    let radius: CGFloat
    let padding: CGFloat
    let action: (() -> Void)?
    let content: Content

    public init(radius: CGFloat = Radius.xl, padding: CGFloat = Spacing.card, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.padding = padding
        self.action = action
        self.content = content()
    }

    public var body: some View {
        let inner = VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let action {
            Button(action: action) { inner }
                .buttonStyle(.rowPress(radius: radius))
                .cardSurface(radius: radius)
        } else {
            inner.cardSurface(radius: radius)
        }
    }
}

/// Content that bleeds to the card edge (an image header, a chart). Clips instead of padding.
public struct BleedCard<Content: View>: View {
    let radius: CGFloat
    let content: Content

    public init(radius: CGFloat = Radius.xl, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(.pokyh(radius))
            .cardSurface(radius: radius)
    }
}

/// A card of same-shaped rows with hairlines between them and none at the ends.
public struct ListCard<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let radius: CGFloat
    let row: (Item) -> Row

    public init(_ items: [Item], radius: CGFloat = Radius.xl, @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.radius = radius
        self.row = row
    }

    public var body: some View {
        if !items.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowSeparator() }
                    row(item)
                }
            }
            .clipShape(.pokyh(radius))
            .cardSurface(radius: radius)
        }
    }
}

/// Hairline between rows, inset to where the text starts.
public struct RowSeparator: View {
    let inset: CGFloat

    public init(inset: CGFloat = Spacing.card) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The standard row: leading, title + subtitle, trailing, chevron when it navigates.
/// 56pt minimum, same horizontal padding as a card so they line up.
public struct PokyhRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let titleColor: Color
    let strikethrough: Bool
    let showChevron: Bool
    let action: (() -> Void)?
    let leading: Leading
    let trailing: Trailing

    public init(
        _ title: String,
        subtitle: String? = nil,
        titleColor: Color = Palette.textPrimary,
        strikethrough: Bool = false,
        showChevron: Bool? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.strikethrough = strikethrough
        self.showChevron = showChevron ?? (action != nil)
        self.action = action
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.rowPress)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Spacing.iconText) {
            leading
            // Side by side while it fits, stacked once a word would have to break.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.iconText) {
                    titleBlock.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    trailing
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    titleBlock
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
        .contentShape(.rect)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .textStyle(.body)
                .foregroundStyle(titleColor)
                .strikethrough(strikethrough)
                .lineLimit(2)
            if let subtitle {
                Text(subtitle)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

/// A row standing alone on the canvas, one radius step below a card. For swipeable or
/// independently ordered rows that can't live in a list card.
public struct TileRow<Content: View>: View {
    let radius: CGFloat
    let padding: CGFloat
    let alignment: VerticalAlignment
    let action: (() -> Void)?
    let content: Content

    public init(radius: CGFloat = Radius.lg, padding: CGFloat = Spacing.row, alignment: VerticalAlignment = .center, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.padding = padding
        self.alignment = alignment
        self.action = action
        self.content = content()
    }

    public var body: some View {
        let row = HStack(alignment: alignment, spacing: Spacing.iconText) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let action {
            Button(action: action) { row }
                .buttonStyle(.rowPress(radius: radius))
                .cardSurface(radius: radius)
        } else {
            row.cardSurface(radius: radius)
        }
    }
}

/// Color-blocked category tile: title on top, a big faint glyph and the open arrow at the bottom.
public struct FeatureTile: View {
    let title: String
    let subtitle: String?
    let tone: Tone
    let symbol: String
    let minHeight: CGFloat
    let height: CGFloat?
    let action: () -> Void

    public init(_ title: String, subtitle: String? = nil, tone: Tone, symbol: String, minHeight: CGFloat = 148, height: CGFloat? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.symbol = symbol
        self.minHeight = minHeight
        self.height = height
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .textStyle(.title3)
                        .foregroundStyle(tone.ink)
                        .lineLimit(height == nil ? 2 : 1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(.caption)
                            .foregroundStyle(tone.ink.opacity(0.78))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: Spacing.md)
                HStack(alignment: .bottom) {
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(tone.ink.opacity(0.20))
                        .frame(width: 52, height: 52, alignment: .bottomLeading)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tone.ink)
                        .frame(width: 30, height: 30)
                        .background(tone.ink.opacity(0.14), in: .capsule)
                }
            }
            .padding(Spacing.row)
            .frame(maxWidth: .infinity, minHeight: height ?? minHeight, maxHeight: height, alignment: .topLeading)
            .cardSurface(radius: Radius.xxl, fill: tone.fill)
        }
        .buttonStyle(.pressable)
    }
}

/// A labelled number, two or three to a row.
public struct StatView: View {
    let value: String
    let label: String
    let valueColor: Color
    let alignment: HorizontalAlignment

    public init(_ value: String, label: String, valueColor: Color = Palette.textPrimary, alignment: HorizontalAlignment = .leading) {
        self.value = value
        self.label = label
        self.valueColor = valueColor
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: Spacing.xxs) {
            Text(value).textStyle(.statSmall).foregroundStyle(valueColor)
            Text(label).textStyle(.caption).foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
