import Foundation

// The sprites' palette, the same as the web's components/pixel/palette.ts: five tones per material
// worked out from the app's own colours. Shades lean towards a cool violet and lights towards a
// warm white, as hand-drawn sprites do, instead of plain black and white.

public enum PixelPalette {
    /// A colour that may differ between the themes, as ARGB.
    private struct Tone {
        let light: UInt32
        let dark: UInt32

        init(_ light: UInt32, _ dark: UInt32? = nil) {
            self.light = light
            self.dark = dark ?? light
        }

        func of(dark isDark: Bool) -> UInt32 { isDark ? dark : light }
    }

    private struct Material {
        let base: Tone
        var shade: UInt32 = PixelPalette.defaultShade
        var out: UInt32 = PixelPalette.defaultOut
        var light: UInt32 = PixelPalette.defaultLight
        var fixed: [Int: Tone] = [:]
    }

    private static func rgb(_ value: UInt32) -> UInt32 { 0xFF00_0000 | value }

    private static func t(_ light: UInt32, _ dark: UInt32? = nil) -> Tone {
        Tone(rgb(light), dark.map(rgb))
    }

    private static func rgba(_ r: UInt32, _ g: UInt32, _ b: UInt32, _ a: Double) -> UInt32 {
        let alpha = UInt32(min(255, max(0, Int(a * 255 + 0.5))))
        return (alpha << 24) | (r << 16) | (g << 8) | b
    }

    private static let defaultShade = rgb(0x2A1F55)
    private static let defaultOut = rgb(0x140D2B)
    private static let defaultLight = rgb(0xFFF8E6)

    private static let materials: [String: Material] = [
        // The accent: indigo.
        "ac": Material(base: t(0x6366F1)),
        // Gold: the sun, sparks, keys.
        "gd": Material(base: t(0xF5B301), shade: rgb(0xA2400F), out: rgb(0x4A1C06)),
        // Red: crosses, stripes, pins.
        "rd": Material(base: t(0xEF4444), shade: rgb(0x5A1236), out: rgb(0x2E0718)),
        // Green: plants.
        "gn": Material(base: t(0x10B981), shade: rgb(0x0B3B4A), out: rgb(0x05202A)),
        // Steel: prongs, poles, hinges.
        "st": Material(base: t(0xBCC1CC), shade: rgb(0x3B4160), out: rgb(0x262A3D), light: rgb(0xFFFFFF)),
        // Paper: soft outlines, like the Mensa plate's glaze.
        "pp": Material(
            base: t(0xF4F1EB, 0xDCD8D0),
            fixed: [0: t(0xBDB3A4, 0x2A2830), 1: t(0xDDD6CB, 0xB4AFA6), 3: t(0xFFFFFF, 0xECE9E3), 4: t(0xFFFFFF)]
        ),
        // The ghost: white, a firm dark outline, cool blue shade.
        "gh": Material(base: t(0xEEF2FB), fixed: [0: t(0x28234D), 1: t(0xA9B5DB), 3: t(0xFFFFFF), 4: t(0xFFFFFF)]),
        // Orange: pumpkins, autumn leaves, a carrot nose.
        "or": Material(base: t(0xF0892B), shade: rgb(0x7A2A10), out: rgb(0x3D1406)),
        // Wood and dry grass.
        "wd": Material(base: t(0xA8693A), shade: rgb(0x3D1D2A), out: rgb(0x24100F)),
        // Sand.
        "sd": Material(base: t(0xEFD790), shade: rgb(0x9A5A2A), out: rgb(0x5A3416)),
        // Water and sky.
        "wt": Material(base: t(0x5AA9E6), shade: rgb(0x1D2F73), out: rgb(0x0F1A45)),
        // Cheeks.
        "pk": Material(base: t(0xF59AB0), shade: rgb(0xB0446A)),
        // The sky in windows, by day and by night.
        "sk": Material(base: t(0x8FCDF3), shade: rgb(0x1D2F73), out: rgb(0x0F1A45)),
        "nt": Material(base: t(0x1D2652), shade: rgb(0x05081F), out: rgb(0x03040F), light: rgb(0x6D7FD0)),
        // Eyes and dark details.
        "ik": Material(base: t(0x1D1730), fixed: [3: t(0x3D3460), 4: t(0xFFFFFF)]),
        // The mascot's pupils: indigo from deep at the top to lighter low down, a white catch-light.
        "pu": Material(base: t(0x3B3494), fixed: [0: t(0x1F1A52), 1: t(0x2C2672), 3: t(0x5A52C4), 4: t(0xFFFFFF)]),
    ]

    // Shadows on the ground and faint lines: one tone each.
    private static let extras: [String: Tone] = [
        "sh": Tone(rgba(48, 30, 70, 0.16), rgba(0, 0, 0, 0.38)),
        "shd": Tone(rgba(48, 30, 70, 0.26), rgba(0, 0, 0, 0.55)),
        "fn": Tone(rgba(0x1C, 0x1A, 0x17, 0.16), rgba(0xF2, 0xF2, 0xF4, 0.16)),
        // Glass: what lies behind it shows through.
        "gl": Tone(rgba(140, 190, 250, 0.38), rgba(140, 190, 250, 0.22)),
        // Warm light falling out of an open door, off a lamp or a screen.
        "lit": Tone(rgba(255, 226, 150, 0.42), rgba(255, 205, 120, 0.3)),
        "glow": Tone(rgba(255, 214, 140, 0.22)),
    ]

    private static func resolve(_ m: Material, _ step: Int, dark: Bool) -> UInt32 {
        if let fixed = m.fixed[step] { return fixed.of(dark: dark) }
        let base = m.base.of(dark: dark)
        switch step {
        case 0: return mixOklab(base, m.out, 0.62)
        case 1: return mixOklab(base, m.shade, 0.32)
        case 3: return mixOklab(base, m.light, 0.38)
        case 4: return mixOklab(base, m.light, 0.76)
        default: return base
        }
    }

    private static func table(dark: Bool) -> [String: UInt32] {
        var out: [String: UInt32] = [:]
        for (name, m) in materials {
            for step in 0...4 { out["\(name)\(step)"] = resolve(m, step, dark: dark) }
        }
        for (name, e) in extras { out[name] = e.of(dark: dark) }
        return out
    }

    private static let lightTones = table(dark: false)
    private static let darkTones = table(dark: true)

    /// Every tone's colour in one theme, as ARGB.
    public static func tones(dark: Bool) -> [String: UInt32] { dark ? darkTones : lightTones }

    // MARK: - color-mix(in oklab, a, b p%)

    private static func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func toSrgb(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    private static func oklab(_ argb: UInt32) -> [Double] {
        let r = toLinear(Double((argb >> 16) & 255) / 255)
        let g = toLinear(Double((argb >> 8) & 255) / 255)
        let b = toLinear(Double(argb & 255) / 255)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
        ]
    }

    private static func fromOklab(_ lab: [Double]) -> UInt32 {
        let l = lab[0] + 0.3963377774 * lab[1] + 0.2158037573 * lab[2]
        let m = lab[0] - 0.1055613458 * lab[1] - 0.0638541728 * lab[2]
        let s = lab[0] - 0.0894841775 * lab[1] - 1.2914855480 * lab[2]
        let l3 = l * l * l, m3 = m * m * m, s3 = s * s * s
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let b = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        func ch(_ v: Double) -> UInt32 {
            UInt32(min(255, max(0, Int(toSrgb(min(1, max(0, v))) * 255 + 0.5))))
        }
        return 0xFF00_0000 | (ch(r) << 16) | (ch(g) << 8) | ch(b)
    }

    /// `a` mixed with `p` of `b`, in oklab: CSS `color-mix(in oklab, a, b p%)`.
    public static func mixOklab(_ a: UInt32, _ b: UInt32, _ p: Double) -> UInt32 {
        let la = oklab(a), lb = oklab(b)
        return fromOklab((0..<3).map { la[$0] * (1 - p) + lb[$0] * p })
    }
}
