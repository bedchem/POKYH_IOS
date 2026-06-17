import SwiftUI
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
    static let bg          = dyn("#F1F0F8", "#09090C")
    static let surface     = dyn("#FAFAFA", "#111116")
    static let card        = dyn("#F5F4FC", "#18181E")
    static let cardAlt     = dyn("#ECEAF6", "#20202A")
    static let border      = dyn("#E0DEEE", "#222230")
    static let separator   = dyn("#D8D6EA", "#1C1C28")
    static let textPrimary = dyn("#0D0C1A", "#F0F0F8")
    static let textSecondary = dyn("#5A5870", "#8A8A9C")
    static let textTertiary  = dyn("#9A98B0", "#52525F")

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

// ── Wiederverwendbare Stile / Animationen (GSAP-artig: weich, federnd) ──────

/// Press-Scale wie `.press-scale` im Web (transform: scale(0.97)).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// `.fade-in` (opacity 0→1, translateY 8px→0) — leicht verzögerbar.
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

/// Pop-In (Scale 0.5→1 + Opacity, federnd) — für neu erscheinende Items, z. B. den
/// Jahres-Wähler oben rechts. Standard-Items bleiben stabil.
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

/// Premium-Slide-In von rechts (Offset + Fade + sanftes Entschärfen), federnd.
/// Für neu erscheinende Header-Items wie den Jahres-Wähler.
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

/// Wie SlideInTrailing, aber von außen gesteuert (`active`) — animiert nur einmal,
/// wenn der gebundene Zustand wechselt (kein Re-Animieren bei Daten-Refresh).
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

/// 3D-Würfel-Drehung — für Seitenwechsel (Stundenplan), wie ein gedrehter Cube.
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
    /// Würfel-Drehung. `forward` = Wisch nach links (nächste Seite).
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

    /// Karte im Web-Stil (solide `--app-card`, weiche Ecken).
    func cardSurface(radius: CGFloat = 16) -> some View {
        self.background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    /// Zentriert schmale Inhalte (Login-/Sperr-Formular) und begrenzt sie auf eine
    /// angenehme Breite — auf dem iPhone wirkungslos (Breite > Display), auf iPad
    /// zentriert. `maxWidth` ist eine Layout-Größe, kein Gerät-Hardcoding.
    func centeredForm(_ maxWidth: CGFloat = 480) -> some View {
        self.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    /// App-Hintergrund (`--app-bg`) + responsive Breite (iPad/regular size class:
    /// Inhalt auf eine lesbare Breite begrenzen und zentrieren, Hintergrund bleibt
    /// vollflächig). Auf dem iPhone (compact) unverändert.
    func appBackground() -> some View {
        self.modifier(ReadableContent()).background(Palette.bg.ignoresSafeArea())
    }
}

/// Begrenzt Inhalte auf eine angenehm lesbare Breite und zentriert sie — nur in
/// der „regular" horizontalen Größenklasse (iPad, breite Fenster). So wirkt die
/// App auf großen Displays nicht gestreckt. Kein Geräte-Check / kein Hardcoding
/// von Modellen — rein an der Größenklasse orientiert.
struct ReadableContent: ViewModifier {
    /// Obergrenze der Inhaltsbreite (über iPhone-Breite → auf dem iPhone wirkungslos).
    static let maxWidth: CGFloat = 760
    @Environment(\.horizontalSizeClass) private var hSize
    func body(content: Content) -> some View {
        if hSize == .regular {
            content.frame(maxWidth: Self.maxWidth).frame(maxWidth: .infinity)
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
