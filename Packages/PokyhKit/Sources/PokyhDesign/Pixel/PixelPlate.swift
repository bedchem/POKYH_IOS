import Foundation
import PokyhCore
import Synchronization
import SwiftUI

// A dish served as pixel art, like the web's components/mensa/PixelPlate.tsx: a glazed plate lit
// from the top left, its shadow dithered onto the table. The photo lies sharp in the well, cut to
// the plate's pixel edge; without one a small pixel meal in the dish's style stands in.

public enum PlateSize: Sendable {
    /// For the next dish: between fork and knife, steam rising, the glaze glinting now and then.
    case table
    /// For the plan's rows.
    case plate
}

/// Which pixel meal stands in for a dish without a photo.
public enum FoodStyle: Sendable {
    case pasta, salad, meat, fish

    /// The web's `foodStyleOf(dishTone(dish))`.
    public static func of(category: String, tags: [String]) -> FoodStyle {
        let c = "\(category) \(tags.joined(separator: " "))".lowercased()
        if c.contains("salat") || c.contains("vegan") || c.contains("vegetar") { return .salad }
        if c.contains("suppe") || c.contains("pasta") || c.contains("nudel") { return .pasta }
        if c.contains("fisch") { return .fish }
        return .meat
    }
}

/// `empty` is the plate without a meal, the table laid while the menu loads.
public struct PixelPlate: View {
    let style: FoodStyle
    let seed: String
    let size: PlateSize
    let photo: URL?
    let empty: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var shownAt = Date()
    @State private var onScreen = true

    public init(style: FoodStyle, seed: String, size: PlateSize = .table, photo: URL? = nil, empty: Bool = false) {
        self.style = style
        self.seed = seed
        self.size = size
        self.photo = photo
        self.empty = empty
    }

    public var body: some View {
        let g = PlateArt.geometry(size)
        Color.clear
            .aspectRatio(CGFloat(g.w) / CGFloat(g.h), contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let fit = PixelFit(size: geo.size, displayScale: displayScale, w: g.w, h: g.h)
                    ZStack(alignment: .topLeading) {
                        drawing(g)
                        if !empty, let photo { photoView(photo, g, fit) }
                    }
                }
            }
            .trackingOnScreen($onScreen)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func drawing(_ g: PlateGeometry) -> some View {
        // Looked up here, not per tick: the clock below shouldn't touch the caches.
        let dark = scheme == .dark
        let base = PlateArt.base(size, dark: dark)
        let meal = empty ? nil : PlateArt.meal(size, style, seed)
        let tones = dark ? PlateTones.dark : PlateTones.light
        if size == .table && !reduceMotion {
            // The steam and the glints move in steps, a tick every 100 ms is all they need.
            let paused = !onScreen || scenePhase != .active || luminanceReduced
            TimelineView(.animation(minimumInterval: 0.1, paused: paused)) { timeline in
                canvas(g, base, meal, tones, ms: Int64(timeline.date.timeIntervalSince(shownAt) * 1000))
            }
        } else {
            canvas(g, base, meal, tones, ms: nil)
        }
    }

    // `ms` nil is the still plate.
    private func canvas(_ g: PlateGeometry, _ base: CGImage?, _ meal: CGImage?, _ tones: PlateTones, ms: Int64?) -> some View {
        let displayScale = displayScale
        return Canvas { context, canvasSize in
            let fit = PixelFit(size: canvasSize, displayScale: displayScale, w: g.w, h: g.h)
            guard fit.pixel > 0 else { return }
            context.scaleBy(x: 1 / displayScale, y: 1 / displayScale)
            if let base { context.drawPixels(base, in: fit.rect(x: 0, y: 0, w: g.w, h: g.h)) }
            if let ms { PlateArt.drawSteam(&context, fit, tones, ms: ms) }
            if let meal { context.drawPixels(meal, in: fit.rect(x: Double(g.boxX), y: Double(g.boxY), w: g.boxN, h: g.boxN)) }
        }
    }

    private func photoView(_ url: URL, _ g: PlateGeometry, _ fit: PixelFit) -> some View {
        let box = fit.rect(x: Double(g.boxX), y: Double(g.boxY), w: g.boxN, h: g.boxN)
        let well = PlateTones.color((scheme == .dark ? PlateTones.dark : PlateTones.light).map[.well] ?? 0)
        return AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
            if let image = phase.image {
                // The well behind it: a photo with holes shouldn't show the stand-in.
                image.resizable().scaledToFill().background(well)
            } else {
                Color.clear
            }
        }
        .frame(width: box.width / displayScale, height: box.height / displayScale)
        .clipShape(FoodShape(g: g))
        .position(x: box.midX / displayScale, y: box.midY / displayScale)
        .allowsHitTesting(false)
    }
}

struct PlateGeometry: Sendable {
    let w: Int
    let h: Int
    let cx: Double
    let cy: Double
    let rOut: Double
    let rRim: Double
    let rFood: Double
    let shadow: (Int, Int)
    let shadowSoft: (Int, Int)

    // The food's square on the scene, in whole pixels, centred on the plate.
    var boxX: Int { Int((cx - rFood).rounded(.down)) }
    var boxY: Int { Int((cy - rFood).rounded(.down)) }
    var boxN: Int { Int((cx + rFood).rounded(.up)) - boxX }

    func inFood(_ x: Int, _ y: Int) -> Bool {
        hypot(Double(x) + 0.5 - (cx - Double(boxX)), Double(y) + 0.5 - (cy - Double(boxY))) <= rFood
    }
}

/// The food's outline in whole pixels, so the photo keeps the plate's edge.
private struct FoodShape: Shape {
    let g: PlateGeometry

    func path(in rect: CGRect) -> Path {
        let n = g.boxN
        let s = rect.width / CGFloat(n)
        var path = Path()
        for y in 0..<n {
            let row = (0..<n).filter { g.inFood($0, y) }
            guard let x0 = row.first, let x1 = row.last else { continue }
            path.addRect(CGRect(x: CGFloat(x0) * s, y: CGFloat(y) * s, width: CGFloat(x1 + 1 - x0) * s, height: s))
        }
        return path
    }
}

enum PlateTone: Hashable, Sendable {
    case shadowSoft, shadow, edge, rim, rimHi, rimLo, well, wellLo, steel, steelHi, steelLo
}

struct PlateTones: Sendable {
    let map: [PlateTone: UInt32]
    let steam: UInt32
    let spark: UInt32

    private static func argb(_ r: UInt32, _ g: UInt32, _ b: UInt32, _ a: Double) -> UInt32 {
        (UInt32(a * 255) << 24) | (r << 16) | (g << 8) | b
    }

    static func color(_ argb: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((argb >> 16) & 255) / 255,
            green: Double((argb >> 8) & 255) / 255,
            blue: Double(argb & 255) / 255,
            opacity: Double(argb >> 24) / 255 * opacity
        )
    }

    static let light = PlateTones(
        map: [
            .rim: 0xFFF4_F1EB, .rimHi: 0xFFFF_FFFF, .rimLo: 0xFFDD_D6CB, .edge: 0xFFC2_B8A9,
            .well: 0xFFEC_E7DF, .wellLo: 0xFFD6_CEC1, .shadow: argb(60, 40, 20, 0.17),
            .shadowSoft: argb(60, 40, 20, 0.1), .steel: 0xFFC9_CCD3, .steelHi: 0xFFF6_F7F9,
            .steelLo: 0xFF8E_939D,
        ],
        steam: argb(140, 132, 122, 0.5),
        spark: 0xFFFF_D86B
    )

    static let dark = PlateTones(
        map: [
            .rim: 0xFF3E_3E46, .rimHi: 0xFF5B_5B65, .rimLo: 0xFF2D_2D34, .edge: 0xFF1C_1C21,
            .well: 0xFF36_363D, .wellLo: 0xFF28_282E, .shadow: argb(0, 0, 0, 0.45),
            .shadowSoft: argb(0, 0, 0, 0.28), .steel: 0xFFA9_AEB7, .steelHi: 0xFFE6_E8ED,
            .steelLo: 0xFF68_6E78,
        ],
        steam: argb(255, 255, 255, 0.34),
        spark: 0xFFFF_FFFF
    )
}

/// The web's seeded random (FNV-1a seed, mulberry32 steps), so a dish always looks the same.
struct SeededRandom {
    private var h: UInt32 = 0x811C_9DC5

    init(seed: String) {
        for unit in seed.utf16 { h = (h ^ UInt32(unit)) &* 16_777_619 }
    }

    mutating func next() -> Double {
        h = h &+ 0x6D2B_79F5
        var t = h
        t = (t ^ (t >> 15)) &* (t | 1)
        t = t ^ (t &+ ((t ^ (t >> 7)) &* (t | 61)))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

enum PlateArt {
    static let table = PlateGeometry(w: 112, h: 64, cx: 56, cy: 31, rOut: 28.5, rRim: 23, rFood: 19.5, shadow: (2, 3), shadowSoft: (3, 5))
    static let plate = PlateGeometry(w: 36, h: 36, cx: 17, cy: 17, rOut: 15.5, rRim: 12.5, rFood: 10.5, shadow: (1, 2), shadowSoft: (2, 3))

    static func geometry(_ size: PlateSize) -> PlateGeometry { size == .table ? table : plate }

    // Light from the top left.
    private static let lx = -0.61
    private static let ly = -0.79

    private static func dist(_ x: Int, _ y: Int, _ cx: Double, _ cy: Double) -> Double {
        hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)
    }

    private static func facing(_ g: PlateGeometry, _ x: Int, _ y: Int) -> Double {
        let dx = Double(x) + 0.5 - g.cx
        let dy = Double(y) + 0.5 - g.cy
        let h = hypot(dx, dy)
        let d = h > 0 ? h : 1
        return dx / d * lx + dy / d * ly
    }

    /// The scene's pixels per tone, back to front.
    static func buildScene(_ g: PlateGeometry, cutlery: Bool) -> [(PlateTone, [Pt])] {
        var plate: [PlateTone: [Pt]] = [:]
        let k = g.rOut / 28.5
        for y in 0..<g.h {
            for x in 0..<g.w {
                let d = dist(x, y, g.cx, g.cy)
                let tone: PlateTone?
                if d <= g.rOut {
                    let f = facing(g, x, y)
                    if d > g.rRim {
                        if d > g.rOut - 1 {
                            tone = f > 0.3 ? .rimLo : .edge
                        } else if f > 0.42 && d > g.rOut - 3.6 * k {
                            tone = .rimHi
                        } else {
                            tone = f < -0.38 ? .rimLo : .rim
                        }
                    } else if d > g.rRim - 1 {
                        tone = f > 0 ? .rimLo : .rimHi
                    } else if d <= g.rFood {
                        tone = .well
                    } else if d <= g.rFood + 1.5 * k && f < -0.2 {
                        tone = .wellLo
                    } else if f > 0.3 && d > g.rRim - 3 * k {
                        tone = .wellLo
                    } else {
                        tone = .well
                    }
                } else if dist(x, y, g.cx + Double(g.shadow.0), g.cy + Double(g.shadow.1)) <= g.rOut {
                    tone = .shadow
                } else if dist(x, y, g.cx + Double(g.shadowSoft.0), g.cy + Double(g.shadowSoft.1)) <= g.rOut + 0.5 && (x + y) % 2 == 0 {
                    tone = .shadowSoft
                } else {
                    tone = nil
                }
                if let tone { plate[tone, default: []].append(Pt(x, y)) }
            }
        }
        let order: [PlateTone] = [.shadowSoft, .shadow, .edge, .rim, .rimHi, .rimLo, .well, .wellLo]
        var layers: [(PlateTone, [Pt])] = order.compactMap { t in plate[t].map { (t, $0) } }
        guard cutlery else { return layers }

        func piece(_ rows: [(y: Int, x0: Int, x1: Int)], gaps: Set<Pt>, extraHi: [Pt]) -> [(PlateTone, [Pt])] {
            var filled = Set<Pt>()
            for r in rows {
                for x in r.x0...r.x1 where !gaps.contains(Pt(x, r.y)) { filled.insert(Pt(x, r.y)) }
            }
            var b: [PlateTone: [Pt]] = [:]
            for q in filled {
                if !filled.contains(Pt(q.x - 1, q.y)) {
                    b[.steelHi, default: []].append(q)
                } else if !filled.contains(Pt(q.x + 1, q.y)) {
                    b[.steelLo, default: []].append(q)
                } else {
                    b[.steel, default: []].append(q)
                }
                if !filled.contains(Pt(q.x + 1, q.y + 1)) { b[.shadow, default: []].append(Pt(q.x + 1, q.y + 1)) }
            }
            b[.steelHi, default: []] += extraHi
            let parts: [PlateTone] = [.shadow, .steel, .steelHi, .steelLo]
            return parts.compactMap { t in b[t].map { (t, $0) } }
        }
        func span(_ y0: Int, _ y1: Int, _ x0: Int, _ x1: Int) -> [(y: Int, x0: Int, x1: Int)] {
            (y0...y1).map { (y: $0, x0: x0, x1: x1) }
        }

        // Four tines with three gaps, rounded tips.
        var fork: [(y: Int, x0: Int, x1: Int)] = [(4, 8, 8), (4, 10, 10), (4, 12, 12), (4, 14, 14)]
        fork += span(5, 15, 8, 14)
        var gaps = Set<Pt>()
        for y in 5...15 {
            for x in [9, 11, 13] { gaps.insert(Pt(x, y)) }
        }
        fork += span(16, 18, 8, 14) + span(19, 20, 9, 13) + span(21, 23, 10, 12)
        fork += span(24, 36, 10, 12) + span(37, 38, 9, 13) + span(39, 57, 9, 13)
        fork.append((58, 10, 12))
        // A table knife from above: a curved edge on the left, a straight back.
        var knife: [(y: Int, x0: Int, x1: Int)] = [(4, 101, 102), (5, 100, 102), (6, 99, 102)]
        knife += span(7, 30, 98, 102) + span(31, 32, 97, 103) + span(33, 57, 98, 102)
        knife.append((58, 99, 101))
        // A long light along the blade and one down the fork's handle.
        layers += piece(fork, gaps: gaps, extraHi: (41...54).map { Pt(11, $0) })
        layers += piece(knife, gaps: [], extraHi: (9...27).map { Pt(100, $0) })
        return layers
    }

    private static let tableScene = buildScene(table, cutlery: true)
    private static let plateScene = buildScene(plate, cutlery: false)

    // Drawn once per size and theme, then scaled without smoothing. A rectangle per pixel on every
    // frame made the list crawl with a plate per dish. Meals are kept for the app's life, so a list
    // scrolled back and forth doesn't draw them again.
    private struct BaseKey: Hashable {
        let size: PlateSize
        let dark: Bool
    }
    private struct MealKey: Hashable {
        let size: PlateSize
        let style: FoodStyle
        let seed: String
    }
    private struct ImageBox: @unchecked Sendable { let image: CGImage }
    private static let bases = Mutex<[BaseKey: ImageBox]>([:])
    private static let meals = Mutex<[MealKey: ImageBox]>([:])

    /// The pixels of the plate as straight ARGB.
    static func basePixels(_ size: PlateSize, dark: Bool) -> [UInt32] {
        let g = geometry(size)
        let tones = dark ? PlateTones.dark : PlateTones.light
        var px = [UInt32](repeating: 0, count: g.w * g.h)
        for (tone, points) in size == .table ? tableScene : plateScene {
            let c = tones.map[tone] ?? 0
            for q in points where (0..<g.w).contains(q.x) && (0..<g.h).contains(q.y) {
                px[q.y * g.w + q.x] = c
            }
        }
        return px
    }

    static func base(_ size: PlateSize, dark: Bool) -> CGImage? {
        let key = BaseKey(size: size, dark: dark)
        return bases.withLock { images in
            if let done = images[key] { return done.image }
            let g = geometry(size)
            guard let made = PixelBitmap.image(argb: basePixels(size, dark: dark), width: g.w, height: g.h) else { return nil }
            images[key] = ImageBox(image: made)
            return made
        }
    }

    static func meal(_ size: PlateSize, _ style: FoodStyle, _ seed: String) -> CGImage? {
        let key = MealKey(size: size, style: style, seed: seed)
        return meals.withLock { images in
            if let done = images[key] { return done.image }
            let g = geometry(size)
            guard let made = PixelBitmap.image(argb: mealPixels(g, style, seed), width: g.boxN, height: g.boxN) else { return nil }
            images[key] = ImageBox(image: made)
            return made
        }
    }

    private static func foodColors(_ style: FoodStyle) -> (base: UInt32, spots: [UInt32]) {
        switch style {
        case .pasta: (0xFFE9_B54A, [0xFFF6_D27A, 0xFFC9_8F2A, 0xFFC2_412D, 0xFF3F_8F3A, 0xFFF6_D27A])
        case .salad: (0xFF6F_AE45, [0xFF3E_7F2C, 0xFF9C_CB62, 0xFFD9_472F, 0xFFF2_C744, 0xFF3E_7F2C])
        case .meat: (0xFF9A_5530, [0xFF7A_3A1E, 0xFFB8_703F, 0xFFE8_C25A, 0xFF4F_8F3A, 0xFF5E_2614])
        case .fish: (0xFFEA_DBC2, [0xFFD6_BF9B, 0xFFF4_D43A, 0xFFF7_F3EA, 0xFF4F_8F3A, 0xFFC9_A97E])
        }
    }

    /// The meal at one pixel per pixel: a heap of the base colour, spots, a white light, round.
    static func mealPixels(_ g: PlateGeometry, _ style: FoodStyle, _ seed: String) -> [UInt32] {
        var rnd = SeededRandom(seed: seed)
        let (base, spots) = foodColors(style)
        let n = g.boxN
        let c = Double(n) / 2
        let k = g.rFood / 19.5
        var px = [UInt32](repeating: 0, count: n * n)
        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: UInt32) {
            for yy in max(0, y)..<max(max(0, y), min(n, y + h)) {
                for xx in max(0, x)..<max(max(0, x), min(n, x + w)) { px[yy * n + xx] = color }
            }
        }
        for y in 0..<n {
            for x in 0..<n {
                let r = hypot(Double(x) + 0.5 - c, Double(y) + 0.5 - c)
                if r <= g.rFood - (3 + rnd.next() * 2.5) * k { fill(x, y, 1, 1, base) }
            }
        }
        let count = Int((Double(style == .pasta ? 90 : 70) * k * k + 0.5).rounded(.down))
        for _ in 0..<count {
            let a = rnd.next() * .pi * 2
            let r = rnd.next().squareRoot() * (g.rFood - 6 * k)
            let x = PixelGrid.jsRound(c + cos(a) * r)
            let y = PixelGrid.jsRound(c + sin(a) * r)
            let color = spots[Int((rnd.next() * Double(spots.count)).rounded(.down))]
            if style == .pasta {
                let dir = rnd.next() > 0.5 ? 1 : -1
                for s in 0..<3 { fill(x + s, y + s * dir, 1, 1, color) }
            } else {
                let w = rnd.next() > 0.5 ? 2 : 1
                let h = rnd.next() > 0.6 ? 2 : 1
                fill(x, y, w, h, color)
            }
        }
        let light = 0.22
        func round(_ v: Double) -> UInt32 { UInt32(min(255, max(0, (v + 0.5).rounded(.down)))) }
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                if !g.inFood(x, y) {
                    px[i] = 0
                    continue
                }
                let dx = Double(x) + 0.5 - c
                let dy = Double(y) + 0.5 - c
                let r = hypot(dx, dy)
                if r < g.rFood - 6 * k && r > g.rFood - 9 * k && (dx * lx + dy * ly) / (r == 0 ? 1 : r) > 0.5 {
                    let p = px[i]
                    let da = Double(p >> 24) / 255
                    let a = light + da * (1 - light)
                    func ch(_ shift: UInt32) -> UInt32 {
                        round((255 * light + Double((p >> shift) & 255) * da * (1 - light)) / a)
                    }
                    px[i] = (round(a * 255) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
                }
            }
        }
        return px
    }

    // The steam's three wisps and the glaze's sparkles, as pixels.
    private static let wisps: [[Pt]] = [
        [Pt(50, 13), Pt(51, 11), Pt(51, 9), Pt(50, 7)],
        [Pt(56, 12), Pt(55, 10), Pt(56, 8), Pt(57, 6), Pt(56, 4)],
        [Pt(62, 13), Pt(61, 11), Pt(61, 9), Pt(62, 7)],
    ]
    private static let spark = [Pt(35, 9), Pt(34, 10), Pt(35, 10), Pt(36, 10), Pt(35, 11)]
    private static let sparkLate = [Pt(76, 52)]

    private static func floorMod(_ a: Int64, _ b: Int64) -> Int64 { ((a % b) + b) % b }

    static func drawSteam(_ context: inout GraphicsContext, _ fit: PixelFit, _ tones: PlateTones, ms t: Int64) {
        func pixel(_ q: Pt, _ color: Color, dy: Double = 0) {
            let rect = fit.rect(x: Double(q.x), y: Double(q.y) + dy, w: 1, h: 1)
            context.fill(Path(rect), with: .color(color))
        }
        // Wisps: 2.8 s each, in 7 steps, rising from 2 px below to 5 px above, fading.
        for (w, points) in wisps.enumerated() {
            let phase = Double(floorMod(t - Int64(w) * 900, 2800)) / 2800
            let step = (phase * 7).rounded(.down) / 7
            let alpha = step < 0.2 ? step / 0.2 : step < 0.7 ? 1 - (step - 0.2) / 0.5 * 0.2 : 0.8 * (1 - (step - 0.7) / 0.3)
            guard alpha > 0.01 else { continue }
            let color = PlateTones.color(tones.steam, opacity: alpha)
            for q in points { pixel(q, color, dy: 2 - 7 * step) }
        }
        // The glaze catches the light: on for a moment every 4 s.
        func on(_ delay: Int64) -> Bool { t >= delay && floorMod(t - delay, 4000) <= 260 }
        let color = PlateTones.color(tones.spark)
        if on(800) { spark.forEach { pixel($0, color) } }
        if on(2600) { sparkLate.forEach { pixel($0, color) } }
    }
}
