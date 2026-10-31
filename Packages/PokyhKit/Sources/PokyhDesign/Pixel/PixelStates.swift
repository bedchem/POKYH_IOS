import Foundation
import PokyhCore
import Synchronization
import SwiftUI

// The small scenes for empty and failed states, 40 × 25 pixels: what stands on the ground stands
// on row 20 and casts a dithered shadow on rows 21 and 22.

public enum PixelSprite: CaseIterable, Sendable {
    /// A plug reaching for its socket: connection, loading.
    case unplugged
    /// A magnifier going over a page, finding nothing: something isn't there.
    case search
    /// A padlock whose shackle won't stay shut: the session ended.
    case lock
    /// A tumbleweed rolling past a cactus: nothing here yet.
    case empty
    /// Sun, a beach umbrella and waves rolling in: a week without school.
    case holiday
    /// The sun in sunglasses, a cloud drifting by: a day without school.
    case sun
    /// A calendar page with a blinking cross: every lesson cancelled.
    case cancelled
    /// A flag in the wind: a day-long event.
    case event
    /// Two arrows trading places: every lesson substituted.
    case swap
    /// A speech bubble typing, an answer popping up: no comments yet.
    case chat
    /// A mailbox, its flag going up and down: no messages.
    case mail
    /// Someone asleep in bed, z's rising: a day excused from school.
    case excused
    /// A bell ringing: no reminders, no notifications.
    case bell
    /// The holidays through the year, see `forHoliday`.
    case winter, spring, autumn
    /// A mug of coffee, steam rising: supporting POKYH.
    case coffee

    /// The scene for days off in a month (1 to 12): the beach in summer, the sun for a single day.
    public static func forHoliday(month: Int, wholeWeek: Bool = true) -> PixelSprite {
        switch month {
        case 12, ...2: .winter
        case ...5: .spring
        case ...8: wholeWeek ? .holiday : .sun
        default: .autumn
        }
    }

    public var scene: PixelScene { PixelStates.scene(self) }
}

/// A state scene on its own, `width` wide.
public struct PixelSpriteArt: View {
    let sprite: PixelSprite
    let width: CGFloat

    public init(_ sprite: PixelSprite, width: CGFloat = 160) {
        self.sprite = sprite
        self.width = width
    }

    public var body: some View {
        PixelArt(scene: sprite.scene).frame(width: width)
    }
}

enum PixelStates: PixelDrawing {
    private static let w = 40
    private static let h = 25
    private static let built = Mutex<[PixelSprite: PixelScene]>([:])

    static func scene(_ sprite: PixelSprite) -> PixelScene {
        built.withLock { scenes in
            if let done = scenes[sprite] { return done }
            let made = build(sprite)
            scenes[sprite] = made
            return made
        }
    }

    private static func build(_ sprite: PixelSprite) -> PixelScene {
        switch sprite {
        case .unplugged: unplugged()
        case .search: search()
        case .lock: lock()
        case .empty: empty()
        case .holiday: holiday()
        case .sun: sun()
        case .cancelled: cancelled()
        case .event: event()
        case .swap: swap()
        case .chat: chat()
        case .mail: mail()
        case .excused: excused()
        case .bell: bell()
        case .winter: winter()
        case .spring: spring()
        case .autumn: autumn()
        case .coffee: coffee()
        }
    }

    private static func layer(_ sprite: Sprite, _ anims: PxAnim...) -> PixelLayer {
        PixelLayer(sprite, anims: anims)
    }

    private static func scene(_ layers: [PixelLayer]) -> PixelScene {
        PixelScene(w: w, h: h, layers: layers)
    }

    /// A soft shadow on the ground: a dithered ellipse with a denser middle.
    @discardableResult
    private static func shadow(_ s: Sprite, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double = 1.2) -> Sprite {
        s.fill(dither(ellipse(cx, cy, rx, ry)), "sh")
        s.fill(dither(ellipse(cx, cy, rx * 0.55, ry * 0.8)), "shd")
        return s
    }

    // MARK: - Unplugged

    private static func unplugged() -> PixelScene {
        let wall = Sprite()
        wall.fill(rect(37, 1, 1, 20), "fn")
        wall.fill(dither(rect(0, 21, 40, 1), 1), "fn")
        wall.mass(rounded(29, 6, 8, 13, 1), "pp")
        for y in [9, 10, 14, 15] {
            wall.set(28, y, "ik0")
            wall.set(29, y, "ik3")
        }
        wall.fill(rect(31, 8, 1, 9), "pp1")
        wall.set(30, 7, "pp4")

        let plug = Sprite()
        shadow(plug, 15.0, 21.5, 6.0)
        plug.mass(rect(-8, 19, 14, 2) + rect(4, 13, 2, 6) + rect(5, 11, 6, 2) + [p(4, 12)], "ik")
        plug.mass(rounded(10, 7, 9, 11, 2) + rect(15, 7, 4, 11), "ac", deep: true)
        for y in 9...15 {
            plug.set(12, y, "ac1")
            plug.set(13, y, "ac3")
            plug.set(15, y, "ac1")
            plug.set(16, y, "ac3")
        }
        plug.set(11, 8, "ac4")
        plug.mass(rect(19, 9, 4, 2), "st")
        plug.mass(rect(19, 14, 4, 2), "st")

        func spark(_ cx: Int, _ cy: Int) -> Sprite {
            Sprite()
                .fill([p(cx, cy - 1), p(cx - 1, cy), p(cx + 1, cy), p(cx, cy + 1)], "gd2")
                .fill([p(cx, cy - 2), p(cx - 2, cy), p(cx + 2, cy), p(cx, cy + 2)], "gd3")
                .set(cx, cy, "gd4")
        }
        return scene([
            layer(wall),
            layer(plug, Px.plug),
            layer(spark(26, 7), Px.spark),
            layer(spark(27, 17), Px.sparkLate),
        ])
    }

    // MARK: - Search

    private static func search() -> PixelScene {
        let page = Sprite()
        let sheet = minus(rect(5, 3, 27, 18), [p(31, 3), p(30, 3), p(29, 3), p(31, 4), p(30, 4), p(31, 5)])
        page.fill(dither(shift(sheet, 1, 1)), "sh")
        page.mass(sheet, "pp")
        page.fill([p(29, 4), p(30, 5), p(29, 5), p(28, 4)], "pp1").fill([p(28, 3), p(31, 6)], "pp0")
            .fill([p(29, 3), p(30, 4), p(31, 5)], "pp0")
        page.fill(rect(8, 6, 11, 2), "ac3")
        let lines: [(Int, [(Int, Int)])] = [(10, [(8, 9), (19, 7)]), (13, [(8, 14), (24, 5)]), (16, [(8, 6), (16, 11)])]
        for (y, runs) in lines {
            for (x, n) in runs { page.fill(rect(x, y, n, 1), "st1") }
        }

        let lens = Sprite()
        lens.fill(dither(disc(7.5, 8.5, 5.5)), "sh")
        let ring = minus(disc(5.5, 5.5, 5.5), disc(5.5, 5.5, 3.6))
        lens.fill(disc(5.5, 5.5, 3.6), "gl")
        lens.mass(ring, "ac", round: (5.5, 5.5))
        lens.fill([p(3, 3), p(4, 3), p(3, 4)], "pp4")
        lens.mass(line(9, 9, 12, 12) + line(10, 9, 13, 12) + line(9, 10, 12, 13), "wd")

        let mark = Sprite().mass(grid([".####.", "##..##", "....##", "...##.", "..##..", "..##..", "......", "..##.."], 32, 1), "gd")
        return scene([layer(page), layer(lens, Px.lens), layer(mark, Px.question)])
    }

    // MARK: - Lock

    private static func lock() -> PixelScene {
        let base = shadow(Sprite(), 20.0, 21.5, 9.0)
        let shackle = Sprite().mass(grid([
            "...######...",
            "..########..",
            ".###....###.",
            ".##......##.",
            ".##......##.",
            ".##......##.",
            ".##......##.",
            ".##......##.",
        ], 14, 2), "st", deep: true)
        shackle.fill([p(18, 2), p(19, 2)], "st4")
        let body = Sprite().mass(rounded(12, 9, 16, 12, 2), "ac", deep: true)
        body.fill(rect(13, 11, 14, 1), "ac3")
        body.fill(disc(20.0, 14.0, 1.6) + rect(19, 15, 2, 3), "ik2").set(19, 13, "ik3")
        let glint = Sprite().fill([p(24, 3), p(23, 4), p(25, 4), p(24, 5)], "gd3").set(24, 4, "pp4")
        return scene([layer(base), layer(shackle, Px.shackle), layer(body), layer(glint, Px.spark)])
    }

    // MARK: - Empty

    private static func empty() -> PixelScene {
        let land = Sprite()
        let dune = ellipse(21.0, 23.6, 19.0, 3.0).filter { $0.y >= 21 }
        land.mass(dune, "sd", outline: false)
        land.fill(dither(dune.filter { $0.y >= 23 }), "sd1")
        land.fill([p(6, 22), p(14, 23), p(33, 22), p(36, 23)], "sd0")
        land.fill(dither(rect(29, 20, 7, 2)), "sh")
        let cactus = rounded(24, 4, 5, 17, 2) + rounded(19, 8, 4, 8, 1) + rect(21, 13, 4, 3) + rounded(30, 6, 4, 7, 1) + rect(28, 10, 4, 3)
        land.mass(cactus, "gn", deep: true)
        for y in 6...19 { land.set(26, y, "gn1") }
        for q in [p(25, 7), p(27, 10), p(25, 13), p(27, 16), p(20, 10), p(31, 8)] { land.set(q.x, q.y, "pp4") }
        land.fill([p(25, 3), p(27, 3), p(26, 2)], "pk2").set(26, 3, "gd2")

        let weed = Sprite()
        let ball = minus(disc(4.0, 4.0, 3.9), [p(2, 3), p(3, 5), p(5, 2), p(5, 5), p(4, 3), p(2, 5)])
        weed.mass(ball, "wd", round: (4.0, 4.0))
        weed.fill([p(3, 3), p(4, 4), p(5, 3), p(2, 4)], "wd1")
        let dust = Sprite().fill([p(-3, 7), p(-5, 6), p(-6, 7)], "fn")
        return scene([
            layer(land),
            layer(dust, Px.tumble, Px.blink),
            layer(weed.shifted(0, 12), Px.tumble, Px.hop, Px.turn),
        ])
    }

    // MARK: - Holiday

    @discardableResult
    private static func sunBall(_ s: Sprite, _ cx: Double, _ cy: Double, _ r: Double) -> Sprite {
        s.mass(disc(cx, cy, r), "gd", round: (cx, cy))
    }

    private static func rays(_ cx: Double, _ cy: Double, _ r: Double, long: Bool) -> Sprite {
        let s = Sprite()
        let reach = r + (long ? 3 : 2)
        for i in 0..<8 {
            let a = (Double(i) / 8) * .pi * 2
            s.set(jsRound(cx - 0.5 + cos(a) * reach), jsRound(cy - 0.5 + sin(a) * reach), long ? "gd3" : "gd2")
        }
        return s
    }

    private static func holiday() -> PixelScene {
        let sky = Sprite()
        sunBall(sky, 8.0, 7.0, 4.2)
        sky.fill([p(6, 5), p(7, 5), p(6, 6)], "gd4")

        let beach = Sprite()
        var sand: [Pt] = []
        for y in 18..<h {
            var x = 40 - (y - 17) * 4 - 10
            while x < w {
                sand.append(p(max(x, 0), y))
                x += 1
            }
        }
        beach.mass(sand, "sd", outline: false)
        beach.fill(dither(sand.filter { $0.y > 20 }, 1), "sd1")
        beach.fill(dither(rect(24, 20, 9, 1)), "sh")
        beach.mass(rect(24, 6, 2, 15), "st")
        let canopy = ellipse(24.5, 10.5, 11.0, 7.0).filter { $0.y <= 10 }.filter { $0.y < 10 || $0.x % 3 != 0 }
        beach.mass(canopy, "rd", round: (24.5, 10.5))
        // The remainder keeps its sign, as in JavaScript: a stripe index of -1 is not an odd stripe.
        beach.recolor(canopy.filter { Int(((Double($0.x) - 13.5) / 4.5).rounded(.down)) % 2 == 1 }, from: "rd", to: "pp")
        beach.mass(rect(24, 2, 2, 2), "gd")

        let water = Sprite()
        var sea: [Pt] = []
        for y in 20..<h {
            var x = -6
            while x < 46 - (y - 17) * 4 - 10 {
                sea.append(p(x, y))
                x += 1
            }
        }
        water.mass(sea, "wt", outline: false, deep: true)
        var x = -6
        while x < 30 {
            water.fill([p(x, 20), p(x + 1, 20), p(x + 2, 21), p(x + 4, 22)], "pp4")
            x += 6
        }
        return scene([
            layer(sky),
            layer(rays(8.0, 7.0, 4.2, long: false)),
            layer(rays(8.0, 7.0, 4.2, long: true), Px.ray),
            layer(beach),
            layer(water, Px.waves),
        ])
    }

    // MARK: - Winter

    /// Flakes scattered over the picture, one tone each.
    private static func scatter(_ points: [Pt], _ tone: String) -> Sprite {
        let s = Sprite()
        for q in points {
            s.fill([p(q.x, q.y - 1), p(q.x - 1, q.y), p(q.x, q.y), p(q.x + 1, q.y), p(q.x, q.y + 1)], "\(tone)2").set(q.x, q.y, "\(tone)4")
        }
        return s
    }

    private static func winter() -> PixelScene {
        let land = Sprite()
        let drift = ellipse(20.0, 24.5, 22.0, 4.6).filter { $0.y >= 20 }
        land.mass(drift, "pp")
        land.fill(dither(drift.filter { $0.y >= 23 }, 1), "pp1")
        land.mass(rect(32, 17, 2, 4), "wd")
        func tier(_ top: Int, _ half: Int, _ rows: Int) -> [Pt] {
            var out: [Pt] = []
            for j in 0..<rows {
                let w = jsRound(1 + Double(half * (j + 1)) / Double(rows))
                for x in (33 - w)...(32 + w) { out.append(p(x, top + j)) }
            }
            return out
        }
        let tiers = [tier(3, 3, 5), tier(7, 4, 5), tier(11, 6, 6)]
        for t in tiers { land.mass(t, "gn", deep: true) }
        for t in tiers {
            let top = t.map(\.y).min() ?? 0
            let rows = t.filter { $0.y == top + 1 || $0.y == top + 2 }
            land.fill(rows.enumerated().filter { $0.offset % 3 != 1 }.map(\.element), "pp3")
        }
        let man = shadow(Sprite(), 15.0, 20.8, 6.5, 0.9)
        man.mass(line(10, 13, 5, 9) + [p(5, 8), p(4, 9)], "wd")
        man.mass(line(20, 13, 25, 10) + [p(25, 9), p(26, 10)], "wd")
        man.mass(disc(15.0, 15.5, 5.2), "pp", round: (15.0, 15.5))
        man.mass(disc(15.0, 8.3, 3.6), "pp", round: (15.0, 8.3))
        man.fill([p(13, 7), p(16, 7), p(15, 14), p(15, 17)], "ik2")
        man.mass([p(15, 9), p(16, 9), p(17, 9), p(18, 10)], "or", outline: false)
        man.mass(rect(11, 11, 9, 2) + rect(17, 13, 2, 3), "rd")
        man.mass(rect(11, 4, 9, 1) + rect(12, 1, 7, 3), "ik")
        man.fill(rect(12, 3, 7, 1), "rd2")
        let flakes = scatter([p(3, 2), p(24, 1), p(36, 6), p(8, 13), p(28, 15)], "wt")
        let flakes2 = scatter([p(18, 3), p(2, 9), p(38, 12), p(26, 5), p(9, 3)], "wt")
        return scene([
            layer(land),
            layer(man),
            layer(flakes, Px.snow),
            layer(flakes2, Px.snow.delayed(-1200)),
        ])
    }

    // MARK: - Spring

    private static func tulip(_ s: Sprite, _ x: Int, _ top: Int, _ mat: String) {
        s.mass(rect(x, top + 4, 1, 20 - top - 4), "gn")
        s.mass([p(x - 1, 16), p(x - 2, 15), p(x - 2, 14), p(x - 1, 15), p(x - 3, 13)], "gn", outline: false)
        s.mass(grid(["#.#.#", "#####", "#####", ".###."], x - 2, top), mat, deep: true)
    }

    private static func wings(open: Bool) -> Sprite {
        let shape = open
            ? grid(["##...##", "###.###", ".##.##.", ".#...#."], 28, 3)
            : grid([".#.#.", ".###.", "..#.."], 29, 4)
        return Sprite().mass(shape, "pk", deep: true).mass(rect(31, 3, 1, 4), "ik", outline: false)
    }

    private static func spring() -> PixelScene {
        let meadow = Sprite()
        let mound = ellipse(20.0, 23.5, 19.0, 3.6).filter { $0.y >= 20 }
        meadow.mass(mound, "gn", outline: false)
        meadow.fill(dither(mound.filter { $0.y >= 22 }), "gn1")
        meadow.fill([p(6, 21), p(33, 21), p(16, 23)], "gn3")
        tulip(meadow, 12, 9, "rd")
        tulip(meadow, 19, 6, "gd")
        tulip(meadow, 26, 10, "ac")
        for q in [p(5, 20), p(31, 21), p(36, 20)] {
            meadow.fill([p(q.x, q.y - 1), p(q.x - 1, q.y), p(q.x + 1, q.y)], "pp3").set(q.x, q.y, "gd2")
        }
        return scene([
            layer(meadow),
            layer(wings(open: true), Px.flutter, Px.flag),
            layer(wings(open: false), Px.flutter, Px.flagAlt),
        ])
    }

    // MARK: - Autumn

    private static func autumn() -> PixelScene {
        let ground = Sprite()
        let mound = ellipse(20.0, 23.5, 19.0, 3.6).filter { $0.y >= 20 }
        ground.mass(mound, "gn", outline: false)
        ground.fill(dither(mound.filter { $0.y >= 22 }), "gn1")
        ground.fill([p(5, 21), p(7, 22), p(19, 21), p(22, 22), p(34, 21)], "or2").fill([p(6, 21), p(20, 22), p(35, 22)], "rd2")
        ground.mass(rect(12, 10, 3, 11) + line(14, 12, 18, 9) + line(12, 13, 9, 10), "wd", deep: true)
        let crown = disc(13.5, 6.0, 5.4) + disc(9.0, 9.0, 3.8) + disc(18.5, 8.5, 3.9) + disc(13.5, 10.4, 3.4)
        ground.mass(crown, "or", round: (13.0, 6.0))
        let red = Set(dither(disc(9.0, 11.0, 2.6) + disc(18.0, 11.0, 2.8) + disc(16.0, 3.0, 1.8)))
        let gold = Set(dither(disc(10.5, 4.5, 2.4) + disc(6.5, 8.0, 1.6)))
        ground.recolor(crown.filter(red.contains), from: "or", to: "rd")
        ground.recolor(crown.filter(gold.contains), from: "or", to: "gd")
        shadow(ground, 29.0, 20.8, 6.0, 0.9)
        ground.mass(ellipse(29.0, 17.6, 5.4, 3.2), "or", round: (28.0, 16.5))
        ground.fill([p(27, 15), p(27, 16), p(27, 17), p(27, 18), p(31, 15), p(31, 16), p(31, 17), p(31, 18)], "or1")
        ground.mass(rect(29, 12, 1, 3) + [p(30, 12)], "gn")
        func leaf(_ x: Int, _ y: Int, _ mat: String) -> Sprite {
            Sprite().mass([p(x, y), p(x + 1, y), p(x, y + 1), p(x + 1, y + 1), p(x + 2, y + 1)], mat, outline: false)
        }
        return scene([
            layer(ground),
            layer(leaf(5, 13, "or"), Px.fall),
            layer(leaf(20, 13, "rd"), Px.fall.delayed(-1100)),
            layer(leaf(14, 14, "gd"), Px.fall.delayed(-2200)),
        ])
    }

    // MARK: - Coffee

    private static func coffee() -> PixelScene {
        let table = shadow(Sprite(), 19.0, 21.4, 12.0, 1.0)
        table.mass(ellipse(19.0, 20.2, 11.0, 1.6), "pp")
        table.mass(rect(25, 10, 5, 2) + rect(28, 11, 2, 6) + rect(25, 16, 5, 2), "ac", deep: true)
        table.mass(rounded(10, 8, 17, 12, 3), "ac", deep: true)
        table.mass(ellipse(18.5, 10.2, 6.4, 1.1), "wd", outline: false)
        table.fill([p(14, 10), p(15, 10)], "wd3")
        table.fill(grid(["##.##", "#####", ".###.", "..#.."], 16, 12), "pp3")
        func wisp(_ x: Int, _ y: Int) -> Sprite {
            Sprite().fill([p(x, y), p(x + 1, y + 1), p(x + 1, y + 2), p(x, y + 3), p(x, y + 4), p(x + 1, y + 5)], "fn")
        }
        return scene([
            layer(table),
            layer(wisp(14, 1), Px.z),
            layer(wisp(20, 0), Px.z.delayed(1300)),
        ])
    }

    // MARK: - Sun

    private static func sun() -> PixelScene {
        let body = sunBall(Sprite(), 20.0, 11.5, 6.6)
        body.fill(rect(15, 9, 4, 3) + rect(21, 9, 4, 3) + rect(19, 9, 2, 1), "ik2")
        body.fill([p(15, 9), p(21, 9)], "ik3").set(16, 9, "ik4").set(22, 9, "ik4")
        body.fill([p(17, 14), p(18, 15), p(19, 15), p(20, 15), p(21, 15), p(22, 14)], "gd0")
        body.fill([p(16, 7), p(17, 6), p(16, 6)], "gd4")
        let cloud = Sprite().mass(disc(4.0, 4.5, 2.6) + disc(8.0, 3.5, 3.3) + disc(11.5, 5.0, 2.4) + rect(2, 5, 11, 2), "pp", round: (7.0, 4.0))
        return scene([
            layer(rays(20.0, 11.5, 6.6, long: false)),
            layer(rays(20.0, 11.5, 6.6, long: true), Px.ray),
            layer(body),
            layer(cloud.shifted(0, 16), Px.cloud),
        ])
    }

    // MARK: - Cancelled

    private static func cancelled() -> PixelScene {
        let cal = shadow(Sprite(), 20.0, 21.5, 10.0)
        cal.mass(rounded(11, 6, 18, 15, 1), "pp", deep: true)
        cal.mass(rect(11, 6, 18, 4), "ac")
        for x in [15, 24] { cal.mass(rect(x, 3, 2, 5), "st") }
        for row in 0..<3 {
            for col in 0..<4 { cal.fill(rect(13 + col * 4, 11 + row * 3, 2, 2), "pp1") }
        }
        let cross = Sprite().mass(line(15, 11, 24, 20) + line(16, 11, 25, 20) + line(24, 11, 15, 20) + line(25, 11, 16, 20), "rd")
        return scene([layer(cal), layer(cross, Px.blink)])
    }

    // MARK: - Event

    private static func flagFrame(_ phase: Double) -> Sprite {
        var cloth: [Pt] = []
        var stripe: [Pt] = []
        for i in 0..<16 {
            let off = jsRound(sin(Double(i) / 4 + phase) * min(1.4, Double(i) / 5))
            for j in 0..<9 {
                if j == 4 {
                    stripe.append(p(14 + i, 4 + off + j))
                } else {
                    cloth.append(p(14 + i, 4 + off + j))
                }
            }
        }
        return Sprite().mass(cloth + stripe, "ac", deep: true).recolor(stripe, from: "ac", to: "pp")
    }

    private static func event() -> PixelScene {
        let ground = Sprite()
        let mound = ellipse(13.0, 22.5, 8.0, 2.6).filter { $0.y >= 20 }
        ground.mass(mound, "gn", outline: false)
        ground.fill(dither(mound.filter { $0.y >= 22 }), "gn1")
        ground.mass(rect(12, 3, 2, 18), "st")
        ground.mass(disc(13.0, 2.0, 1.8), "gd", round: (13.0, 2.0))
        return scene([layer(ground), layer(flagFrame(0), Px.flag), layer(flagFrame(.pi), Px.flagAlt)])
    }

    // MARK: - Swap

    private static func arrow(right: Bool, _ mat: String) -> Sprite {
        let rows = [
            "..............##....",
            "..............####..",
            "####################",
            "####################",
            "####################",
            "..............####..",
            "..............##....",
        ]
        return Sprite().mass(grid(right ? rows : rows.map { String($0.reversed()) }), mat, deep: true)
    }

    private static func swap() -> PixelScene {
        scene([
            layer(shadow(Sprite(), 20.0, 21.5, 11.0)),
            layer(arrow(right: true, "ac").shifted(8, 3), Px.arrowR),
            layer(arrow(right: false, "gd").shifted(12, 12), Px.arrowL),
        ])
    }

    // MARK: - Chat

    private static func chat() -> PixelScene {
        let ground = shadow(Sprite(), 20.0, 21.5, 11.0)
        let bubble = Sprite()
        bubble.mass(rounded(8, 3, 25, 13, 3) + [p(12, 16), p(13, 16), p(14, 16), p(12, 17), p(13, 17), p(12, 18)], "pp", deep: true)
        func dot(_ x: Int) -> Sprite { Sprite().mass(rect(x, 9, 2, 2), "ac") }
        let reply = Sprite().mass(rounded(27, 13, 11, 7, 2) + [p(34, 20), p(35, 20), p(35, 21)], "ac", deep: true)
        reply.fill([p(30, 16), p(32, 16), p(34, 16)], "pp3")
        return scene([
            layer(ground),
            layer(bubble),
            layer(dot(13), Px.type),
            layer(dot(18), Px.type.delayed(250)),
            layer(dot(23), Px.type.delayed(500)),
            layer(reply, Px.reply),
        ])
    }

    // MARK: - Mail

    private static func mail() -> PixelScene {
        let ground = Sprite()
        let grass = ellipse(20.0, 22.5, 12.0, 2.4).filter { $0.y >= 20 }
        ground.mass(grass, "gn", outline: false)
        ground.fill(dither(grass.filter { $0.y >= 22 }), "gn1")
        ground.mass(rect(19, 12, 3, 9), "wd")
        let box = Sprite().mass(rounded(10, 4, 20, 9, 1) + rect(10, 8, 20, 5), "ac", deep: true)
        box.mass(rect(11, 7, 4, 5), "ik", outline: false)
        box.fill([p(11, 7), p(12, 7)], "ik3")
        box.fill(rect(16, 6, 12, 1), "ac3")
        func flag(up: Bool) -> Sprite {
            Sprite().mass(up ? rect(30, 2, 2, 8) + rect(32, 2, 4, 3) : rect(30, 8, 8, 2) + rect(36, 8, 2, 4), "rd")
        }
        return scene([layer(ground), layer(box), layer(flag(up: true), Px.flag), layer(flag(up: false), Px.flagAlt)])
    }

    // MARK: - Excused

    private static func excused() -> PixelScene {
        let room = shadow(Sprite(), 20.0, 21.5, 15.0)
        room.mass(rect(5, 7, 3, 14) + rect(33, 12, 3, 9), "wd", deep: true)
        room.mass(rect(8, 15, 25, 3), "wd")
        room.mass(rect(8, 13, 25, 2), "pp", outline: false)
        room.mass(rounded(8, 10, 7, 4, 1), "pp")
        room.mass(rounded(14, 10, 19, 6, 2) + rect(14, 13, 19, 3), "ac", deep: true)
        room.fill(dither(rect(16, 12, 15, 1), 1), "ac3")
        room.mass(disc(13.0, 10.0, 2.4), "pk", round: (13.0, 10.0))
        room.fill([p(12, 10), p(14, 10)], "pk0")
        room.fill([p(11, 7), p(12, 7), p(13, 7), p(14, 7), p(10, 8), p(11, 8), p(12, 8), p(13, 8), p(15, 8), p(10, 9), p(11, 9)], "wd1")
        func z(_ x: Int, _ y: Int) -> Sprite { Sprite().mass(grid(["###", "..#", ".#.", "#..", "###"], x, y), "gd") }
        return scene([layer(room), layer(z(17, 3), Px.z), layer(z(22, 0), Px.z.delayed(1300))])
    }

    // MARK: - Bell

    private static func bell() -> PixelScene {
        let ground = shadow(Sprite(), 20.0, 21.5, 9.0)
        let body = grid([
            "......######......",
            "....##########....",
            "...############...",
            "...############...",
            "...############...",
            "...############...",
            "..##############..",
            "..##############..",
            "..##############..",
            ".################.",
            "##################",
            "##################",
        ], 11, 4)
        let shell = Sprite().mass(body, "gd", deep: true)
        shell.mass(rect(19, 1, 2, 2), "gd")
        shell.fill([p(16, 6), p(15, 7), p(15, 8), p(15, 9), p(14, 10), p(14, 11)], "gd4")
        shell.fill(rect(13, 12, 14, 1), "gd1")
        let clapper = Sprite().mass(disc(20.0, 18.5, 1.6), "st", round: (20.0, 18.5))
        func arc(_ x: Int, _ y: Int, flip: Bool, long: Bool) -> [Pt] {
            (long ? [0, 1, 1, 1, 0] : [0, 1, 1, 0]).enumerated().map { i, d in p(flip ? x + d : x - d, y + i) }
        }
        func waves(right: Bool) -> Sprite {
            Sprite().fill(
                right
                    ? arc(32, 7, flip: true, long: false) + arc(35, 6, flip: true, long: true)
                    : arc(7, 7, flip: false, long: false) + arc(4, 6, flip: false, long: true),
                "gd2"
            )
        }
        return scene([
            layer(ground),
            layer(clapper, Px.clapper),
            layer(shell, Px.swing),
            layer(waves(right: false), Px.wave),
            layer(waves(right: true), Px.wave.delayed(400)),
        ])
    }
}
