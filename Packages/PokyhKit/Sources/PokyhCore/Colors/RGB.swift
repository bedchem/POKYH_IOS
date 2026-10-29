import Foundation

/// A plain sRGB color, 0...1 per channel. The color math lives here, away from SwiftUI,
/// so it's testable on the Mac and identical in app, widgets and watch.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    public static let white = RGB(red: 1, green: 1, blue: 1)
    public static let black = RGB(red: 0, green: 0, blue: 0)

    public func mixed(with other: RGB, amount t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    /// Hue in degrees, the inverse of the hue that goes into `hsv`/`hsl`.
    public var hueDegrees: Double {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let d = maxC - minC
        if d <= 0.0001 { return 0 }
        let h: Double
        if maxC == red {
            h = ((green - blue) / d).truncatingRemainder(dividingBy: 6)
        } else if maxC == green {
            h = (blue - red) / d + 2
        } else {
            h = (red - green) / d + 4
        }
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Same as SwiftUI's `Color(hue:saturation:brightness:)`, hue in degrees.
    public static func hsv(_ hue: Double, _ saturation: Double, _ value: Double) -> RGB {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let s = min(max(saturation, 0), 1)
        let v = min(max(value, 0), 1)
        let c = v * s
        return sector(h, chroma: c, offset: v - c)
    }

    public static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> RGB {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let s = min(max(saturation, 0), 1)
        let l = min(max(lightness, 0), 1)
        let c = (1 - abs(2 * l - 1)) * s
        return sector(h, chroma: c, offset: l - c / 2)
    }

    private static func sector(_ h: Double, chroma c: Double, offset m: Double) -> RGB {
        let hPrime = h / 60
        let x = c * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch hPrime {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return RGB(red: r + m, green: g + m, blue: b + m)
    }
}

public enum ColorMath {
    /// The web's 32-bit string hash, per UTF-16 unit. Web, Android and iOS must agree on it
    /// or fallback colors for subjects, senders and avatars drift apart.
    public static func jsHash(_ s: String) -> Int {
        var hash: Int32 = 0
        for unit in s.utf16 {
            hash = (hash &<< 5) &- hash &+ Int32(unit)
        }
        // Kotlin's abs(Int.MIN_VALUE) stays negative; keep that so the hue matches.
        return hash == .min ? Int(hash) : Int(abs(hash))
    }
}
