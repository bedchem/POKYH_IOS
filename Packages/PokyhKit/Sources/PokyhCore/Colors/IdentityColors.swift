import Foundation
import Synchronization

/// Colors that identify things (subjects, people, grades). They have to match the web and
/// Android, so they're derived the same way and never tuned per platform.
public enum IdentityColors {
    /// Keyed by the exact WebUntis short name; anything else gets a hashed hue.
    static let fixedSubjects: [String: RGB] = [
        "D": RGB(hex: 0x5AA0E8),
        "M": RGB(hex: 0x4ED87A),
        "IT": RGB(hex: 0xE73BDF),
        "Bew.Sport": RGB(hex: 0xAA8EE0),
        "ENGL": RGB(hex: 0x3DC4CE),
        "R": RGB(hex: 0xC6E84A),
        "M5-M7": RGB(hex: 0xE08899),
        "M8": RGB(hex: 0xE89E6E),
        "Re-Wiku": RGB(hex: 0x6AB87A),
    ]

    public static func subject(_ name: String) -> RGB {
        if let fixed = fixedSubjects[name] { return fixed }
        return .hsv(Double(ColorMath.jsHash(name) % 360), 0.50, 0.62)
    }

    public static func sender(_ name: String) -> RGB {
        .hsv(Double(ColorMath.jsHash(name) % 360), 0.60, 0.55)
    }

    /// `hue` in 0..<1, as the avatar store keeps it.
    public static func avatar(hue: Double) -> RGB {
        .hsv(hue * 360, 0.60, 0.55)
    }

    /// Italian 1–10 scale, as the web's lib/colors.ts: green ramp from 6.4, orange for a bare
    /// pass, red ramp below 6.
    public static func grade(_ value: Double) -> RGB {
        let greenLight = RGB(red: 134 / 255, green: 239 / 255, blue: 172 / 255)
        let greenDark = RGB(red: 21 / 255, green: 128 / 255, blue: 61 / 255)
        let redLight = RGB(red: 252 / 255, green: 165 / 255, blue: 165 / 255)
        let redDark = RGB(red: 153 / 255, green: 27 / 255, blue: 27 / 255)
        if value >= 6.4 { return greenLight.mixed(with: greenDark, amount: (value - 6.4) / 3.6) }
        if value >= 6.0 { return RGB(hex: 0xF97316) }
        return redLight.mixed(with: redDark, amount: (6.0 - value) / 5.0)
    }

    /// The grade distribution donut. Only 4–10 are real marks at the school; 7 is the
    /// accent on purpose since it's the most common one.
    public static func distribution(_ grade: Int) -> RGB {
        switch grade {
        case 10: RGB(hex: 0x34C759)
        case 9: RGB(hex: 0x30C0A8)
        case 8: RGB(hex: 0x4B9BF5)
        case 7: RGB(hex: 0x6366F1)
        case 6: RGB(hex: 0xF2C744)
        case 5: RGB(hex: 0xF59E4B)
        case 4: RGB(hex: 0xEF6B5E)
        default: RGB(hex: 0x8A8A8F)
        }
    }
}

/// Hands out the timetable's subject hues for one week. Same routine as the web timetable:
/// sorted by name, each subject keeps its preferred hue if it's free, otherwise takes the free
/// hue farthest from the ones in use. So the same week looks the same everywhere.
public final class SubjectHues: Sendable {
    public static let shared = SubjectHues()

    static let hues: [Double] = stride(from: 10.0, through: 350.0, by: 20.0).map { $0 }

    private let assigned = Mutex<[String: Double]>([:])

    public init() {}

    static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    static func preferredHue(_ name: String) -> Double {
        let own = IdentityColors.subject(name).hueDegrees
        return hues.min { distance($0, own) < distance($1, own) } ?? hues[0]
    }

    public func register<S: Sequence>(_ names: S) where S.Element == String {
        let subjects = Array(Set(names.filter { !$0.isEmpty })).sorted()
        var next: [String: Double] = [:]
        var used: [Double] = []
        for name in subjects {
            var hue = Self.preferredHue(name)
            if used.contains(hue) {
                let free = Self.hues.filter { !used.contains($0) }
                if let farthest = free.max(by: { a, b in
                    used.map { Self.distance($0, a) }.min()! < used.map { Self.distance($0, b) }.min()!
                }) {
                    hue = farthest
                }
            }
            next[name] = hue
            used.append(hue)
        }
        assigned.withLock { $0 = next }
    }

    public func hue(for name: String) -> Double {
        assigned.withLock { $0[name] } ?? Self.preferredHue(name)
    }
}
