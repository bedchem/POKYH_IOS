import SwiftUI

/// Warm shadow in light mode (it never reads as dirt on the warm canvas), plain black in dark,
/// where cards get half the lift and lean on tone instead.
struct WarmShadow: ViewModifier {
    let elevation: Elevation
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let radius = dark && elevation == .level1 ? elevation.radius / 2 : elevation.radius
        let umber = Color(hex: 0x3A2E1F)
        content
            .shadow(color: dark ? .black.opacity(0.30) : umber.opacity(0.07), radius: radius / 2, y: 0)
            .shadow(color: dark ? .black.opacity(0.40) : umber.opacity(0.12), radius: radius, y: radius / 2)
    }
}

extension View {
    /// The one card recipe: card fill, continuous corners, a whisper of warm shadow, no border.
    public func cardSurface(radius: CGFloat = Radius.xl, fill: Color = Palette.card, elevation: Elevation = .level1) -> some View {
        background(fill, in: .pokyh(radius))
            .modifier(WarmShadow(elevation: elevation))
    }

    /// Recessed fill inside a card: inputs, segmented tracks, skeletons. No shadow.
    public func insetSurface(radius: CGFloat = Radius.md, fill: Color = Palette.cardAlt) -> some View {
        background(fill, in: .pokyh(radius))
    }

    /// A large panel nested inside a card. Hue-free, unlike cardAlt.
    public func nestedSurface(radius: CGFloat = Radius.md) -> some View {
        background(Palette.nested, in: .pokyh(radius))
    }

    /// The accent's quiet form: selected chip, icon tile, badge.
    public func accentSurface(radius: CGFloat = Radius.md) -> some View {
        background(Palette.accentTint, in: .pokyh(radius))
    }

    /// Chrome that really floats. On iOS 26 that's glass, which is what floating chrome is now.
    public func floatingSurface(radius: CGFloat = Radius.xl, interactive: Bool = false) -> some View {
        modifier(FloatingSurface(radius: radius, interactive: interactive))
    }

    /// Screen roots: the canvas color, full bleed.
    public func screenBackground() -> some View {
        background(Palette.bg.ignoresSafeArea())
    }

    /// Caps the column on wide windows and centers it. A no-op on phones.
    public func readableContent(maxWidth: CGFloat = WidthClass.readableMaxWidth) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    /// Home, timetable and Mensa get the wider measure.
    public func wideContent() -> some View {
        readableContent(maxWidth: WidthClass.wideMaxWidth)
    }

    /// Login and lock forms. Applies on phones too, it's only ever a cap.
    public func centeredForm(maxWidth: CGFloat = WidthClass.formMaxWidth) -> some View {
        readableContent(maxWidth: maxWidth)
    }
}

struct FloatingSurface: ViewModifier {
    let radius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.glassEffect(interactive ? .regular.interactive() : .regular, in: .pokyh(radius))
        #else
        content.background(Palette.card, in: .pokyh(radius))
        #endif
    }
}

/// Whole tiles shrink a little while held.
public struct PressableStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Rows inside a card don't scale (they'd break out of it), they get a faint scrim.
public struct RowPressStyle: ButtonStyle {
    let radius: CGFloat?

    public init(radius: CGFloat? = nil) {
        self.radius = radius
    }

    public func makeBody(configuration: Configuration) -> some View {
        RowPressBody(configuration: configuration, radius: radius)
    }

    private struct RowPressBody: View {
        let configuration: Configuration
        let radius: CGFloat?
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let alpha = configuration.isPressed ? (scheme == .dark ? 0.07 : 0.045) : 0
            configuration.label
                .contentShape(.rect)
                .overlay {
                    if let radius {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.textPrimary.opacity(alpha))
                    } else {
                        Rectangle().fill(Palette.textPrimary.opacity(alpha))
                    }
                }
                .animation(.easeOut(duration: Motion.fast), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableStyle {
    public static var pressable: PressableStyle { PressableStyle() }
}

extension ButtonStyle where Self == RowPressStyle {
    public static var rowPress: RowPressStyle { RowPressStyle() }
    public static func rowPress(radius: CGFloat) -> RowPressStyle { RowPressStyle(radius: radius) }
}
