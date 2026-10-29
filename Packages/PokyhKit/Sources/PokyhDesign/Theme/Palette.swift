import SwiftUI
import PokyhCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    public init(_ rgb: RGB, opacity: Double = 1) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }

    public init(hex: UInt32, opacity: Double = 1) {
        self.init(RGB(hex: hex), opacity: opacity)
    }

    /// Resolves per color scheme. The watch is always dark.
    public init(light: RGB, dark: RGB) {
        #if os(watchOS)
        self.init(dark)
        #elseif canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #endif
    }

    public init(light: UInt32, dark: UInt32) {
        self.init(light: RGB(hex: light), dark: RGB(hex: dark))
    }
}

/// Brand colors, the same in both themes.
public enum Brand {
    public static let accent = Color(hex: 0x6366F1)
    /// Darker step for accent text on light surfaces; read `Palette.accentText` instead.
    public static let accentInk = Color(hex: 0x4F46E5)
    public static let onAccent = Color.white
    public static let success = Color(hex: 0x10B981)
    public static let warning = Color(hex: 0xF59E0B)
    public static let danger = Color(hex: 0xEF4444)
    /// Rating stars only.
    public static let star = Color(hex: 0xF5B301)
    /// Second warning step, for "changed" next to "warning".
    public static let orange = Color(hex: 0xF97316)
    public static let accentSoft = Color(hex: 0x8B5CF6)

    static let accentRGB = RGB(hex: 0x6366F1)
    static let successRGB = RGB(hex: 0x10B981)
    static let warningRGB = RGB(hex: 0xF59E0B)
    static let dangerRGB = RGB(hex: 0xEF4444)
    static let orangeRGB = RGB(hex: 0xF97316)
}

/// The neutral ramp. bg is the canvas, card sits on it (tone does the separating, no border),
/// cardAlt is the recessed fill inside a card, nested a hue-free panel inside a card.
public enum Palette {
    public static let bg = Color(light: 0xF5F2ED, dark: 0x111114)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x1B1B1F)
    public static let card = Color(light: 0xFFFFFF, dark: 0x1B1B1F)
    public static let cardAlt = Color(light: 0xEEEAE3, dark: 0x26262B)
    public static let nested = Color(light: 0xECECEB, dark: 0x232323)
    public static let nav = Color(light: 0xEBE7E0, dark: 0x212126)
    public static let border = Color(light: 0xE7E2D9, dark: 0x303036)
    public static let separator = Color(light: 0xF0ECE5, dark: 0x232327)
    public static let line = Color(light: 0xE0D9CE, dark: 0x2E2E34)
    public static let dangerText = Color(light: 0xB91C1C, dark: 0xF87171)
    public static let textPrimary = Color(light: 0x1C1A17, dark: 0xF2F2F4)
    public static let textSecondary = Color(light: 0x6C655C, dark: 0x9C9CA2)
    public static let textTertiary = Color(light: 0xA39B90, dark: 0x67676E)
    public static let accentTint = Color(light: 0xEDECFD, dark: 0x20203A)
    public static let accentText = Color(light: 0x4F46E5, dark: 0x6366F1)

    // Identity colors, see PokyhCore/IdentityColors.
    public static func subject(_ name: String) -> Color { Color(IdentityColors.subject(name)) }
    public static func sender(_ name: String) -> Color { Color(IdentityColors.sender(name)) }
    public static func avatar(hue: Double) -> Color { Color(IdentityColors.avatar(hue: hue)) }
    public static func grade(_ value: Double) -> Color { Color(IdentityColors.grade(value)) }
    public static func distribution(_ grade: Int) -> Color { Color(IdentityColors.distribution(grade)) }
    /// Widgets only need pass/fail.
    public static func gradeSimple(_ value: Double) -> Color { value >= 6 ? Brand.success : Brand.danger }
}

/// A block of color plus the ink that's readable on it, contrast-checked in both themes.
public struct Tone: Sendable {
    public let fill: Color
    public let ink: Color
    public let bar: Color

    public init(fill: Color, ink: Color, bar: Color? = nil) {
        self.fill = fill
        self.ink = ink
        self.bar = bar ?? ink
    }
}

/// Four hand-picked category tones (Home shortcuts, School hub tiles). Only four on purpose,
/// a fifth turns the grid into assorted pastels.
public enum Decorative {
    public static let periwinkle = Tone(fill: Color(light: 0xDEDDFB, dark: 0x24244C), ink: Color(light: 0x4A46A6, dark: 0xBAB8F4))
    public static let butter = Tone(fill: Color(light: 0xF7E7AC, dark: 0x473B16), ink: Color(light: 0x85641A, dark: 0xEBD79A))
    public static let sage = Tone(fill: Color(light: 0xD5E4D0, dark: 0x23351E), ink: Color(light: 0x4B6E45, dark: 0xB4D0AD))
    public static let blush = Tone(fill: Color(light: 0xF7D9D3, dark: 0x46241F), ink: Color(light: 0x9F5347, dark: 0xEFC1B8))

    public static let all = [periwinkle, butter, sage, blush]

    /// Grids cycle by index so a tile keeps its color across launches.
    public static func cycle(_ index: Int) -> Tone {
        all[((index % all.count) + all.count) % all.count]
    }
}

extension Tone {
    /// A subject as a pastel block, built in HSL so every hue lands at the same lightness.
    /// The hue comes from the week's `SubjectHues`, so web and app color a week alike.
    public static func subject(_ name: String, hues: SubjectHues = .shared) -> Tone {
        let hue = hues.hue(for: name)
        return Tone(
            fill: Color(light: .hsl(hue, 0.62, 0.84), dark: .hsl(hue, 0.42, 0.25)),
            ink: Color(light: .hsl(hue, 0.54, 0.26), dark: .hsl(hue, 0.80, 0.86)),
            bar: Color(light: .hsl(hue, 0.48, 0.57), dark: .hsl(hue, 0.58, 0.62))
        )
    }

    /// A status (cancelled, exam, substitution) at the same visual weight as a subject.
    public static func status(_ rgb: RGB) -> Tone {
        let hue = rgb.hueDegrees
        return Tone(
            fill: Color(light: .hsl(hue, 0.82, 0.85), dark: .hsl(hue, 0.58, 0.29)),
            ink: Color(light: .hsl(hue, 0.65, 0.27), dark: .hsl(hue, 0.92, 0.88)),
            bar: Color(rgb)
        )
    }

    public static let cancelled = status(Brand.dangerRGB)
    public static let exam = status(Brand.warningRGB)
    public static let substitution = status(Brand.orangeRGB)
    public static let event = status(Brand.accentRGB)
}

extension RGB {
    /// Softened toward white for solid decorative use, never for status dots.
    public var softenedFill: RGB { mixed(with: .white, amount: 0.18) }
}
