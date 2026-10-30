import SwiftUI
import PokyhDesign
#if canImport(UIKit)
import UIKit
#endif

/// Design-System — exakt portiert aus `app/globals.css` der Web-App.
/// Indigo-Akzent, eigene Hintergrund-/Karten-/Textfarben für Hell & Dunkel.
enum Palette {
    // Akzente (globals.css)
    static let accent = Color(hex: "#6366F1")      // indigo
    static let accentSoft = Color(hex: "#8B5CF6")  // violet
    static let tint = Color(hex: "#10B981")        // emerald
    static let success = Color(hex: "#10B981")
    static let warning = Color(hex: "#F59E0B")
    static let danger = Color(hex: "#EF4444")
    static let orange = Color(hex: "#F97316")

    // Dynamische Tokens (hell / dunkel)
    static let bg          = dyn("#F5F2ED", "#111114")
    static let surface     = dyn("#FFFFFF", "#1B1B1F")
    static let card        = dyn("#FFFFFF", "#1B1B1F")
    static let cardAlt     = dyn("#EEEAE3", "#26262B")
    static let border      = dyn("#E7E2D9", "#303036")
    static let separator   = dyn("#F0ECE5", "#232327")
    static let textPrimary = dyn("#1C1A17", "#F2F2F4")
    static let textSecondary = dyn("#6C655C", "#9C9CA2")
    static let textTertiary  = dyn("#A39B90", "#67676E")
    // Android's extra steps (ui/theme/Palette.kt).
    static let nested      = dyn("#ECECEB", "#232323")
    static let nav         = dyn("#EBE7E0", "#212126")
    static let line        = dyn("#E0D9CE", "#2E2E34")
    static let dangerText  = dyn("#B91C1C", "#F87171")
    static let accentTint  = dyn("#EDECFD", "#20203A")
    static let accentText  = dyn("#4F46E5", "#6366F1")
    static let star        = Color(hex: "#F5B301")

    private static func dyn(_ light: String, _ dark: String) -> Color {
        #if canImport(UIKit)
        // Hex EINMAL vorab parsen (Performance: kein Scanner pro Trait-Auflösung →
        // flüssiger Hell/Dunkel-Wechsel). Es werden nur Sendable-Doubles gecaptured,
        // nie der @MainActor-`Color`-Initializer (sonst Crash auf Gerät).
        let l = rgbaFromHex(light), d = rgbaFromHex(dark)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
        #else
        return Color(hex: light)
        #endif
    }

    static let subjectColors: [String: String] = [
        "D": "#5AA0E8", "M": "#4ED87A", "IT": "#E73BDF", "Bew.Sport": "#AA8EE0",
        "ENGL": "#3DC4CE", "R": "#C6E84A", "M5-M7": "#E08899", "M8": "#E89E6E",
        "Re-Wiku": "#6AB87A",
    ]

    private static func hashString(_ s: String) -> Int {
        var hash = 0
        for ch in s.unicodeScalars {
            hash = (hash << 5) &- hash &+ Int(ch.value)
            hash = Int(Int32(truncatingIfNeeded: hash))
        }
        return abs(hash)
    }

    static func subject(_ name: String) -> Color {
        if let hex = subjectColors[name] { return Color(hex: hex) }
        let hue = Double(hashString(name) % 360) / 360.0
        return Color(hue: hue, saturation: 0.50, brightness: 0.62)
    }

    static func sender(_ name: String) -> Color {
        let hue = Double(hashString(name) % 360) / 360.0
        return Color(hue: hue, saturation: 0.60, brightness: 0.55)
    }

    /// Avatar-Farbe für ein **Benutzerprofil**: beim ersten Mal echt zufällig
    /// gewürfelt, lokal persistiert (pro stabilem Identifier) und danach immer
    /// gleich. Look identisch zu `sender` (gleiche Sättigung/Helligkeit).
    static func color(for identifier: String) -> Color {
        Color(hue: AvatarColorStore.hue(for: identifier), saturation: 0.60, brightness: 0.55)
    }

    static func grade(_ value: Double) -> Color {
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * max(0, min(1, t)) }
        func mix(_ c1: (Double, Double, Double), _ c2: (Double, Double, Double), _ t: Double) -> Color {
            Color(red: lerp(c1.0, c2.0, t) / 255, green: lerp(c1.1, c2.1, t) / 255, blue: lerp(c1.2, c2.2, t) / 255)
        }
        let greenLight = (134.0, 239.0, 172.0), greenDark = (21.0, 128.0, 61.0)
        // negativ: normales Rot (#EF4444) knapp unter 6 → dunkleres Rot (#7F1D1D) bei 1
        let redNormal = (239.0, 68.0, 68.0), redDark = (127.0, 29.0, 29.0)
        // ab 6: hellgrün (6) → dunkelgrün (10); unter 6: normalrot (knapp unter 6) → dunkelrot (1)
        if value >= 6.0 { return mix(greenLight, greenDark, (value - 6.0) / (10 - 6.0)) }
        return mix(redNormal, redDark, (6.0 - value) / (6.0 - 1))
    }
}

/// Persistiert die einmalig zufällig gewählte Farbe (Hue) je Profil-Identifier.
/// Speicher: `UserDefaults` unter einem `pokyh_`-Schlüssel → wird von
/// `clearAllData()` automatisch mit aufgeräumt (kein Hardcoding einzelner Keys).
enum AvatarColorStore {
    private static let key = "pokyh_avatar_hues"

    static func hue(for identifier: String) -> Double {
        let id = identifier.lowercased()
        var map = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
        if let h = map[id] { return h }
        let h = Double.random(in: 0..<1)
        map[id] = h
        UserDefaults.standard.set(map, forKey: key)
        return h
    }
}

/// Hex → RGBA (nonisolated, threadsicher).
nonisolated func rgbaFromHex(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double) {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    var v: UInt64 = 0
    Scanner(string: h).scanHexInt64(&v)
    switch h.count {
    case 8: return (Double((v >> 24) & 0xff)/255, Double((v >> 16) & 0xff)/255, Double((v >> 8) & 0xff)/255, Double(v & 0xff)/255)
    default: return (Double((v >> 16) & 0xff)/255, Double((v >> 8) & 0xff)/255, Double(v & 0xff)/255, 1)
    }
}

extension Color {
    nonisolated init(hex: String) {
        let c = rgbaFromHex(hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}

#if canImport(UIKit)
extension UIColor {
    /// Threadsicher (nonisolated) — sicher im dynamischen Trait-Callback nutzbar.
    nonisolated convenience init(hexString: String) {
        let c = rgbaFromHex(hexString)
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
#endif

// ── Shared styles and motion ────────────────────────────────────────────────

// The design package's press style under the old name. Files that import PokyhDesign get the
// package's `.pressable` (the same style); the rest get this one.
typealias PressableStyle = PokyhDesign.PressableStyle

extension ButtonStyle where Self == PressableStyle {
    @_disfavoredOverload
    static var pressable: PressableStyle { PressableStyle() }
}

/// Fades in while rising 10pt, like Android's `Modifier.fadeIn`.
struct FadeIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(.easeOut(duration: 0.34).delay(delay)) { shown = true }
            }
    }
}

/// Springs in from half size, for items that appear later (the year picker).
struct PopIn: ViewModifier {
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.5)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.05)) { shown = true }
            }
    }
}

/// Slides in from the trailing edge with a little blur, for late header items.
struct SlideInTrailing: ViewModifier {
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .offset(x: shown ? 0 : 44)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 5)
            .scaleEffect(shown ? 1 : 0.92, anchor: .trailing)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.08)) { shown = true }
            }
    }
}

/// SlideInTrailing driven from outside, so a data refresh doesn't replay it.
struct SlideInBound: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .offset(x: active ? 0 : 90)
            .opacity(active ? 1 : 0)
            .blur(radius: active ? 0 : 9)
            .scaleEffect(active ? 1 : 0.65, anchor: .trailing)
            .rotationEffect(.degrees(active ? 0 : 14), anchor: .trailing)
    }
}

/// Cube turn for paging the timetable.
struct CubeRotation: ViewModifier {
    let angle: Double
    let anchor: UnitPoint
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: anchor, perspective: 0.7)
            .opacity(abs(angle) > 45 ? 0 : 1)
    }
}

extension AnyTransition {
    /// `forward`: swiped left, to the next page.
    static func cube(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: CubeRotation(angle: forward ? 90 : -90, anchor: forward ? .leading : .trailing),
                identity: CubeRotation(angle: 0, anchor: forward ? .leading : .trailing)),
            removal: .modifier(
                active: CubeRotation(angle: forward ? -90 : 90, anchor: forward ? .trailing : .leading),
                identity: CubeRotation(angle: 0, anchor: forward ? .trailing : .leading))
        )
    }
}

extension View {
    func fadeIn(delay: Double = 0) -> some View { modifier(FadeIn(delay: delay)) }
    func popIn() -> some View { modifier(PopIn()) }
    func slideInTrailing() -> some View { modifier(SlideInTrailing()) }
    func slideIn(_ active: Bool) -> some View { modifier(SlideInBound(active: active)) }

    /// Android's card: card fill, continuous corners, a whisper of warm shadow, no border.
    /// The same recipe as PokyhDesign's `cardSurface`, which wins in files that import it.
    @_disfavoredOverload
    func cardSurface(radius: CGFloat = Radius.xl, fill: Color = Palette.card, elevation: Elevation = .level1) -> some View {
        self.background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(WarmShadow(elevation: elevation))
    }

    /// Caps login and lock forms at a comfortable width and centers them.
    @_disfavoredOverload
    func centeredForm(maxWidth: CGFloat = WidthClass.formMaxWidth) -> some View {
        self.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    func centeredForm(_ maxWidth: CGFloat) -> some View {
        self.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    /// The canvas color, full bleed, with the content held to a readable width on iPad.
    /// `wide` is Android's wide measure for screens laid out in columns (Home, timetable).
    func appBackground(wide: Bool = false) -> some View {
        self.modifier(ReadableContent(maxWidth: wide ? WidthClass.wideMaxWidth : ReadableContent.maxWidth))
            .background(Palette.bg.ignoresSafeArea())
    }
}

/// Warm umber in light mode so it never looks like dirt on the warm canvas; plain black in
/// dark, where cards get half the lift and lean on tone instead (Android's Elevation.kt).
struct WarmShadow: ViewModifier {
    let elevation: Elevation
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let base: CGFloat = switch elevation {
        case .level1: 2
        case .level2: 6
        case .level3: 14
        case .level4: 24
        }
        let radius = dark && elevation == .level1 ? base / 2 : base
        let umber = Color(hex: "#3A2E1F")
        content
            .shadow(color: dark ? .black.opacity(0.30) : umber.opacity(0.07), radius: radius / 2, y: 0)
            .shadow(color: dark ? .black.opacity(0.40) : umber.opacity(0.12), radius: radius, y: radius / 2)
    }
}

extension View {
    /// Shadow only, for surfaces that pick their own fill or shape.
    func warmShadow(_ elevation: Elevation = .level1) -> some View {
        modifier(WarmShadow(elevation: elevation))
    }
}

/// Caps and centers content in the regular width class only, so wide windows don't
/// stretch it. Goes by size class, never by device.
struct ReadableContent: ViewModifier {
    /// Wider than any iPhone, so phones never notice it.
    static let maxWidth: CGFloat = WidthClass.readableMaxWidth
    var maxWidth: CGFloat = ReadableContent.maxWidth
    @Environment(\.horizontalSizeClass) private var hSize
    func body(content: Content) -> some View {
        if hSize == .regular {
            content.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

// ── Formatierungs-Helfer (portiert aus lib/grades.ts) ──────────────────────

enum Fmt {
    static func num(_ value: Double, digits: Int = 2) -> String {
        let factor = pow(10.0, Double(digits))
        let rounded = (value * factor).rounded() / factor
        var s = String(format: "%.\(digits)f", rounded)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s.replacingOccurrences(of: ".", with: ",")
    }
    static func dateShort(_ date: Int) -> String {
        let s = String(date)
        guard s.count == 8 else { return s }
        let a = Array(s)
        return "\(String(a[6...7])).\(String(a[4...5])).\(String(a[2...3]))"
    }
    static func dateFull(_ date: Int) -> String {
        let s = String(date)
        guard s.count == 8 else { return s }
        let a = Array(s)
        return "\(String(a[6...7])).\(String(a[4...5])).\(String(a[0...3]))"
    }
    static func time(_ t: Int) -> String {
        let s = String(format: "%04d", t)
        let a = Array(s)
        return "\(String(a[0...1])):\(String(a[2...3]))"
    }
    static func minutes(_ t: Int) -> Int {
        let s = String(format: "%04d", t)
        let a = Array(s)
        return (Int(String(a[0...1])) ?? 0) * 60 + (Int(String(a[2...3])) ?? 0)
    }
}
