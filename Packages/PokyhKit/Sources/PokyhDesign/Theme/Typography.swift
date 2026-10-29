import SwiftUI

/// The Android type scale on SF Pro. Sizes scale with Dynamic Type relative to the closest
/// system style, so a 16pt body grows like `.body` does.
public struct TextStyle: Sendable {
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let weight: Font.Weight
    /// In em, like Compose's letterSpacing.
    public let tracking: CGFloat
    public let relativeTo: Font.TextStyle
    public let design: Font.Design
    public let monospacedDigits: Bool

    public init(
        _ size: CGFloat,
        _ lineHeight: CGFloat,
        _ weight: Font.Weight,
        tracking: CGFloat = 0,
        relativeTo: Font.TextStyle,
        design: Font.Design = .default,
        monospacedDigits: Bool = false
    ) {
        self.size = size
        self.lineHeight = lineHeight
        self.weight = weight
        self.tracking = tracking
        self.relativeTo = relativeTo
        self.design = design
        self.monospacedDigits = monospacedDigits
    }

    public func weight(_ weight: Font.Weight) -> TextStyle {
        TextStyle(size, lineHeight, weight, tracking: tracking, relativeTo: relativeTo, design: design, monospacedDigits: monospacedDigits)
    }

    public static let display = TextStyle(36, 40, .heavy, tracking: -0.022, relativeTo: .largeTitle)
    public static let largeTitle = TextStyle(30, 36, .heavy, tracking: -0.02, relativeTo: .largeTitle)
    public static let title1 = TextStyle(24, 30, .bold, tracking: -0.015, relativeTo: .title)
    public static let title2 = TextStyle(20, 26, .bold, tracking: -0.01, relativeTo: .title2)
    public static let title3 = TextStyle(17, 23, .semibold, tracking: -0.005, relativeTo: .title3)
    public static let headline = TextStyle(16, 21, .semibold, relativeTo: .headline)
    public static let body = TextStyle(16, 23, .regular, relativeTo: .body)
    public static let callout = TextStyle(15, 21, .regular, relativeTo: .callout)
    public static let subheadline = TextStyle(14, 19, .regular, relativeTo: .subheadline)
    public static let footnote = TextStyle(13, 18, .regular, relativeTo: .footnote)
    public static let caption = TextStyle(12, 16, .medium, relativeTo: .caption)
    public static let caption2 = TextStyle(11, 14, .medium, relativeTo: .caption2)
    /// Small caps-style section labels.
    public static let label = TextStyle(11, 14, .bold, tracking: 0.09, relativeTo: .caption2)
    public static let button = TextStyle(16, 20, .semibold, tracking: -0.005, relativeTo: .body)
    public static let navLabel = TextStyle(10, 12, .semibold, tracking: 0.005, relativeTo: .caption2)

    // A big number that is the content. Tabular, since these change in place.
    public static func numeral(_ size: CGFloat, _ weight: Font.Weight = .heavy, relativeTo: Font.TextStyle = .largeTitle) -> TextStyle {
        TextStyle(size, size * 1.1, weight, tracking: -0.03, relativeTo: relativeTo, monospacedDigits: true)
    }

    public static let statLarge = numeral(46)
    public static let statMedium = numeral(28, relativeTo: .title)
    public static let statSmall = numeral(19, .bold, relativeTo: .title3)
    public static let wordmark = numeral(32)

    // Timetable grid, deliberately tiny.
    public static let gridCellSubject = TextStyle(10, 12, .bold, relativeTo: .caption2)
    public static let gridCellTime = TextStyle(7.5, 9, .medium, relativeTo: .caption2, monospacedDigits: true)
    public static let gridCellRoom = TextStyle(8, 10, .regular, relativeTo: .caption2)
    public static let timeAxisPeriod = TextStyle(13, 15, .semibold, relativeTo: .footnote, monospacedDigits: true)
    public static let timeAxisBoundary = TextStyle(9, 11, .medium, relativeTo: .caption2, monospacedDigits: true)
    public static let badgeChip = TextStyle(9, 11, .bold, tracking: 0.04, relativeTo: .caption2)

    // Widgets and Live Activity.
    public static let widgetHeader = TextStyle(10, 12, .semibold, tracking: 0.06, relativeTo: .caption2)
    public static let widgetBigNumber = numeral(38)
    public static let liveActivityCountdown = numeral(28, relativeTo: .title)
}

struct TextStyleModifier: ViewModifier {
    let style: TextStyle
    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var lineHeight: CGFloat

    init(style: TextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        _lineHeight = ScaledMetric(wrappedValue: style.lineHeight, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        var font = Font.system(size: size, weight: style.weight, design: style.design)
        if style.monospacedDigits { font = font.monospacedDigit() }
        // SF's own line height is ~1.2 × size; only add what Android has on top of that.
        return content
            .font(font)
            .tracking(style.tracking * size)
            .lineSpacing(max(0, lineHeight - size * 1.2))
    }
}

extension View {
    public func textStyle(_ style: TextStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}
