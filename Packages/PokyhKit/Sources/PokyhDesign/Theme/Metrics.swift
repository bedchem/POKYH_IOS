import SwiftUI

/// 4pt grid. Reach for a token, not a literal.
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let xxxl: CGFloat = 32
    public static let huge: CGFloat = 40

    /// Screen side margin.
    public static let screenH = xl
    /// Between sections on a screen.
    public static let section = xxl
    /// Inside a card.
    public static let card = xl
    /// Row padding inside grouped lists.
    public static let row = lg
    public static let rowGap = sm
    public static let iconText = md
    public static let headerContent = md
}

/// Corner radii, always continuous (the Android squircle is the same curve).
public enum Radius {
    /// Small accent bars, badge corners.
    public static let xs: CGFloat = 8
    /// Inputs, day pills, timetable cells, thumbnails.
    public static let sm: CGFloat = 12
    /// Inset blocks and small icon tiles.
    public static let md: CGFloat = 16
    /// A row standing alone on the canvas.
    public static let lg: CGFloat = 20
    /// Default card and sheet radius.
    public static let xl: CGFloat = 24
    /// Hero surfaces, stat cards, images.
    public static let xxl: CGFloat = 28
}

extension Shape where Self == RoundedRectangle {
    public static func pokyh(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// Four lift levels; the level says what the thing is. Shadows are a warm umber, never black,
/// and cards are nearly flat because tone already separates them.
public enum Elevation: Sendable {
    /// Cards and rows. An edge softener.
    case level1
    /// Picked up: a dragged row, a floating button.
    case level2
    /// Floating chrome: banners.
    case level3
    /// Modal layers.
    case level4

    var radius: CGFloat {
        switch self {
        case .level1: 2
        case .level2: 6
        case .level3: 14
        case .level4: 24
        }
    }
}

/// Short and purposeful: press answers at once, selection crossfades, pushes slide.
public enum Motion {
    public static let fast: Double = 0.14
    public static let standard: Double = 0.26
    public static let slow: Double = 0.40

    /// Press feedback, small flips.
    public static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.6)
    /// Bigger surfaces.
    public static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.62)
    public static let standardEase = Animation.easeInOut(duration: standard)
}

/// Width classes, same breakpoints as Android (600 / 840).
public enum WidthClass: Sendable {
    case compact, medium, expanded

    public init(width: CGFloat) {
        switch width {
        case 840...: self = .expanded
        case 600...: self = .medium
        default: self = .compact
        }
    }

    public static let readableMaxWidth: CGFloat = 760
    public static let wideMaxWidth: CGFloat = 1240
    public static let formMaxWidth: CGFloat = 480
}
