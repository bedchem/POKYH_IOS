import Foundation
import PokyhCore
import Synchronization
import SwiftUI

// POKYH's mascot as a sprite: a soft indigo block, a little tilted, with big white eyes and dark
// upright pupils, pink blush, a tiny smile, stubby arms at the lower sides and two short legs with
// round feet. 40 × 37 pixels, the feet on row 33, its shadow below. A pose is built from the eyes,
// where they look, a mouth and what the arms do; every pose is drawn once and kept.

public enum Mascot: PixelDrawing {
    public static let width = 40
    public static let height = 37

    public enum Eyes: Hashable, Sendable { case open, blink, happy, wide, closed, angry }
    public enum Mouth: Hashable, Sendable { case smile, grin, o, wobble, flat, frown }
    public enum Arms: Hashable, Sendable { case down, wave, wave2, wave3, cover, peek, thumb, lens, cheer, fists }

    public struct Pose: Hashable, Sendable {
        public var eyes: Eyes
        /// Where the pupils look, -1 to 1 each way.
        public var look: Pt
        public var mouth: Mouth
        public var arms: Arms

        public init(eyes: Eyes = .open, look: Pt = Pt(0, 0), mouth: Mouth = .smile, arms: Arms = .down) {
            self.eyes = eyes
            self.look = look
            self.mouth = mouth
            self.arms = arms
        }
    }

    /// A rounded rectangle turned about its middle, in whole pixels.
    private static func tilted(_ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ r: Double, _ deg: Double) -> [Pt] {
        let a = deg * .pi / 180
        let c = cos(a), s = sin(a)
        var out: [Pt] = []
        let reach = Double(Int((hypot(w, h) / 2).rounded(.up)) + 1)
        for y in Int((cy - reach).rounded(.down))...Int((cy + reach).rounded(.up)) {
            for x in Int((cx - reach).rounded(.down))...Int((cx + reach).rounded(.up)) {
                let dx = Double(x) + 0.5 - cx
                let dy = Double(y) + 0.5 - cy
                let u = abs(dx * c + dy * s)
                let v = abs(-dx * s + dy * c)
                let ex = max(0, u - (w / 2 - r))
                let ey = max(0, v - (h / 2 - r))
                if u <= w / 2 && v <= h / 2 && hypot(ex, ey) <= r { out.append(p(x, y)) }
            }
        }
        return out
    }

    /// Drops what the turning leaves sticking out of the top: a row of one to three pixels above a
    /// much wider one.
    private static func trimmed(_ shape: [Pt]) -> [Pt] {
        var rows: [Int: Int] = [:]
        for q in shape { rows[q.y, default: 0] += 1 }
        guard let top = rows.keys.min() else { return shape }
        return (rows[top] ?? 0) <= 3 && (rows[top + 1] ?? 0) > 6 ? shape.filter { $0.y != top } : shape
    }

    // The block leans a little to the left: its right side is higher.
    private static let body = trimmed(tilted(20.0, 13.6, 27.0, 25.4, 8.0, -5.0))
    private static let eyeL = (15.0, 12.6)
    private static let eyeR = (24.6, 11.2)

    // Stubby arms out of the lower sides, behind the body; one raised beside the head for a wave
    // (out, up, in towards the head), both up for a cheer, fists for anger.
    private static let armL = limb(7.4, 19.4, 4.4, 23.4, 2.6)
    private static let armR = limb(32.8, 17.8, 35.6, 21.8, 2.6)
    private static func hand(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Pt] {
        limb(x0, y0, x1, y1, 2.4) + disc(x1, y1, 2.9)
    }
    private static let raisedR = hand(32.2, 13.4, 36.8, 9.4)
    private static let raisedR2 = hand(32.2, 13.4, 35.8, 6.2)
    private static let raisedR3 = hand(32.2, 13.4, 33.8, 4.2)
    private static let cheerL = hand(9.0, 15.5, 4.2, 8.6)
    private static let cheerR = hand(31.0, 14.0, 35.8, 7.0)
    private static let fistL = hand(8.6, 19.0, 4.4, 14.4)
    private static let fistR = hand(31.6, 17.4, 35.8, 12.8)

    private static func legs(_ s: Sprite) {
        s.mass(rect(13, 24, 5, 7) + ellipse(14.0, 31.0, 3.9, 2.0), "ac", deep: true)
        s.mass(rect(22, 23, 5, 8) + ellipse(26.0, 31.0, 3.9, 2.0), "ac", deep: true)
    }

    private static let pupil: [Character: String] = ["1": "pu1", "2": "pu2", "3": "pu3", "4": "pu4"]

    private static func eye(_ s: Sprite, _ centre: (Double, Double), _ kind: Eyes, _ look: Pt, right: Bool, big: Bool = false) {
        let (cx, cy) = centre
        let x = Int(cx.rounded(.down))
        let y = Int(cy.rounded(.down))
        switch kind {
        case .blink:
            s.fill(rect(x - 2, y + 1, 5, 1), "pu0")
            return
        case .closed:
            // Shut tight: ◡
            s.fill([p(x - 2, y), p(x - 1, y + 1), p(x, y + 1), p(x + 1, y + 1), p(x + 2, y)], "pu0")
            return
        case .angry:
            // Open, but a brow pushed down towards the middle cuts the top off.
            eye(s, centre, .open, look, right: right, big: big)
            let inward = right ? -1 : 1
            for i in -4...4 {
                let bx = x + i
                let by = jsRound(Double(y - 4) + Double(i * inward + 4) * 0.42)
                var yy = by - 1
                while yy >= y - 6 {
                    if let tone = s.get(bx, yy), tone.hasPrefix("pp") || tone.hasPrefix("pu") { s.set(bx, yy, "ac2") }
                    yy -= 1
                }
                s.set(bx, by, "pu0")
                s.set(bx, by - 1, "pu0")
            }
            return
        case .happy:
            // Smiling eyes: ^, two pixels thick in the middle.
            s.fill([p(x - 2, y + 1), p(x - 1, y), p(x, y - 1), p(x + 1, y), p(x + 2, y + 1), p(x, y)], "pu0")
            return
        case .open, .wide:
            break
        }
        // The white, the right one a touch bigger (it is nearer), and a big dark upright pupil.
        let grow = (right ? 0.2 : 0) + (kind == .wide || big ? 0.6 : 0)
        s.fill(ellipse(cx, cy, 3.7 + grow, 4.3 + grow), "pp3")
        if big {
            // Behind the magnifier: the pupil half as big again.
            let px = jsRound(cx + 0.4 + Double(look.x) * 0.8) - 3
            let py = jsRound(cy - 0.3 + Double(look.y) * 0.8) - 4
            s.rows([".1111.", "114411", "114111", "111122", "122222", "222233", "223333", ".3333."], px, py, legend: pupil)
            return
        }
        let px = jsRound(cx + 0.4 + Double(look.x) * 1.2) - 2
        let py = jsRound(cy - 0.3 + Double(look.y) * 1.1) - 3
        s.rows([".11.", "1411", "1122", "2222", "2233", ".33."], px, py, legend: pupil)
    }

    private static func mouth(_ s: Sprite, _ kind: Mouth) {
        switch kind {
        case .smile: s.fill([p(19, 17), p(20, 18), p(21, 18), p(22, 17)], "ac0")
        case .flat: s.fill(rect(19, 18, 3, 1), "ac0")
        case .wobble: s.fill([p(18, 18), p(19, 17), p(20, 18), p(21, 17), p(22, 18)], "ac0")
        case .o: s.fill([p(20, 17), p(21, 17), p(20, 18), p(21, 18)], "pu0")
        case .frown: s.fill([p(18, 19), p(19, 18), p(20, 17), p(21, 17), p(22, 18), p(23, 19)], "pu0")
        case .grin:
            s.fill(rect(18, 17, 5, 1) + rect(19, 18, 3, 1), "pu0")
            s.set(20, 18, "pk1")
        }
    }

    private static func cheeks(_ s: Sprite, flushed: Bool) {
        for (cx, cy) in [(11.3, 18.6), (28.6, 17.0)] {
            // Angry: red right across.
            s.fill(ellipse(cx, cy, flushed ? 3.0 : 2.4, flushed ? 1.5 : 1.2), flushed ? "rd2" : "pk2")
            s.set(Int(cx.rounded(.down)) - 1, Int(cy.rounded(.down)), flushed ? "rd3" : "pk3")
        }
    }

    /// A hand in front of the body, with its own outline.
    private static func mitt(_ s: Sprite, _ shape: [Pt], fingers: [Pt] = []) {
        s.mass(shape, "ac", deep: true)
        s.fill(fingers, "ac1")
    }

    private static let cache = Mutex<[Pose: Sprite]>([:])

    public static func sprite(_ pose: Pose) -> Sprite {
        cache.withLock { poses in
            if let done = poses[pose] { return done }
            let made = draw(pose)
            poses[pose] = made
            return made
        }
    }

    private static func draw(_ pose: Pose) -> Sprite {
        let s = Sprite()
        legs(s)
        let a = pose.arms
        // Hanging arms go behind the body's outline (only what reaches out shows); raised ones in
        // front of its edge, so the waving hand is always seen.
        let raised: [[Pt]] = switch a {
        case .wave: [raisedR]
        case .wave2: [raisedR2]
        case .wave3: [raisedR3]
        case .cheer: [cheerL, cheerR]
        case .fists: [fistL, fistR]
        default: []
        }
        let hanging: [[Pt]] = switch a {
        case .down: [armL, armR]
        case .lens, .thumb, .wave, .wave2, .wave3: [armL]
        default: []
        }
        for arm in hanging { mitt(s, arm) }
        s.mass(body, "ac", deep: true)
        for arm in raised { mitt(s, arm) }
        let lens = a == .lens
        eye(s, eyeL, pose.eyes, pose.look, right: false)
        eye(s, eyeR, pose.eyes, pose.look, right: true, big: lens && (pose.eyes == .open || pose.eyes == .wide))
        cheeks(s, flushed: pose.eyes == .angry)
        mouth(s, pose.mouth)

        switch a {
        case .cover, .peek:
            // Hands flat over the eyes.
            mitt(s, limb(8.5, 20.0, 11.0, 16.5, 2.4) + soft(11, 9, 8, 8, 3.5), fingers: [p(14, 9), p(16, 9)])
            if a == .cover {
                mitt(s, limb(32.0, 18.5, 29.5, 15.0, 2.4) + soft(21, 7, 8, 8, 3.5), fingers: [p(23, 7), p(25, 7)])
            } else {
                mitt(s, limb(32.0, 19.0, 30.5, 18.0, 2.4) + soft(26, 16, 7, 6, 2.5))
            }
        case .thumb:
            // A little fist on the right, thumb up.
            mitt(s, limb(32.5, 18.0, 31.5, 16.5, 2.4) + soft(28, 12, 8, 7, 2.5), fingers: [p(30, 15), p(31, 15), p(32, 15), p(33, 15)])
            mitt(s, soft(29, 7, 3, 6, 1.4))
        case .lens:
            // A magnifier held to the right eye, the eye big behind it.
            let (cx, cy) = eyeR
            s.mass(minus(disc(cx, cy, 6.7), disc(cx, cy, 5.3)), "wd", round: (cx, cy))
            s.mass(line(29, 16, 32, 19) + line(30, 16, 33, 19), "wd")
            mitt(s, limb(33.5, 22.0, 33.5, 20.5, 2.4) + soft(30, 18, 7, 6, 2.5), fingers: [p(32, 20), p(33, 20)])
        default:
            break
        }
        return s
    }

    /// The magnifier's glass: a faint blue the eye shows through, a glint at its top left.
    public static let lensGlass = Sprite().fill(disc(eyeR.0, eyeR.1, 4.8), "gl").fill([p(21, 8), p(22, 7), p(21, 9)], "pp4")

    /// Its shadow on the floor, apart from the body so it stays down when the body hops.
    public static let shadow = Sprite().fill(dither(ellipse(20.0, 34.5, 15.0, 1.6)), "sh").fill(dither(ellipse(20.0, 34.5, 9.0, 1.2), 1), "shd")

    // MARK: - The signs around it

    // Line pitch of the bubble text: the 5-pixel font and a pixel between lines.
    private static let linePitch = 6

    /// A speech bubble with text in capitals, its tail pointing down-left to (x, y). Text wider
    /// than `maxWidth` goes on more lines and the bubble grows upwards, the tail staying put.
    public static func bubble(_ text: String, x: Int, y: Int, maxWidth: Int = .max) -> Sprite {
        let lines = wrapText(text, maxWidth)
        return drawBubble(lines, lines.map { textPixels($0).width }, bx: x + 2, x: x, y: y)
    }

    /// The same bubble centred over `cx`: for the mascot standing on its own in the middle, its
    /// words above its head.
    public static func bubbleAbove(_ text: String, cx: Int, y: Int, maxWidth: Int = .max) -> Sprite {
        let lines = wrapText(text, maxWidth)
        let widths = lines.map { textPixels($0).width }
        let bw = (widths.max() ?? 0) + 8
        return drawBubble(lines, widths, bx: cx - bw / 2, x: cx - 3, y: y)
    }

    private static func drawBubble(_ lines: [String], _ widths: [Int], bx: Int, x: Int, y: Int) -> Sprite {
        let bw = (widths.max() ?? 0) + 8
        let bh = lines.count * linePitch + 5
        let by = y - 2 - bh
        let s = Sprite()
        s.mass(soft(bx, by, bw, bh, 3.0) + [p(x + 3, y - 2), p(x + 4, y - 2), p(x + 2, y - 1), p(x + 3, y - 1), p(x + 1, y)], "pp")
        // A firm outline, so it reads over anything behind it.
        var outline: [Pt] = []
        s.forEachCell { px, py, tone in if tone == "pp0" { outline.append(p(px, py)) } }
        s.fill(outline, "ik2")
        for (i, l) in lines.enumerated() {
            let lx = bx + 4 + (bw - 8 - widths[i]) / 2
            s.fill(textPixels(l).points.map { p($0.x + lx, $0.y + by + 3 + i * linePitch) }, "ik2")
        }
        return s
    }

    /// A sign above the head: '!' or '?'.
    public static func markSprite(_ kind: Character, x: Int, y: Int) -> Sprite {
        let rows = kind == "!"
            ? ["##", "##", "##", "##", "..", "##"]
            : [".###.", "##.##", "...##", "..##.", ".....", "..##."]
        return Sprite().mass(grid(rows, x, y), "gd")
    }

    /// The anger sign of comics, a throbbing vein, beside the head.
    private static func angerSprite(_ x: Int, _ y: Int) -> Sprite {
        Sprite().mass(grid(["..#.#..", ".##.##.", "##...##", ".......", "##...##", ".##.##.", "..#.#.."], x, y), "rd")
    }

    /// A puff of steam rising off the head: a bigger cloud and a small one above it.
    private static func steamSprite(_ x: Int, _ y: Int) -> Sprite {
        let fx = Double(x), fy = Double(y)
        return Sprite().mass(disc(fx + 2.5, fy + 4.0, 2.6) + disc(fx + 5.0, fy + 3.2, 2.0) + disc(fx + 1.2, fy + 0.4, 1.3), "pp")
    }

    /// A drop of sweat beside the head.
    private static func sweatSprite(_ x: Int, _ y: Int) -> Sprite {
        Sprite()
            .mass([p(x + 1, y), p(x, y + 1), p(x + 1, y + 1), p(x, y + 2), p(x + 1, y + 2), p(x + 2, y + 2), p(x + 1, y + 3)], "wt")
            .set(x, y + 1, "wt4")
    }

    /// "…" in a small thought bubble.
    private static func thinkingSprite(_ x: Int, _ y: Int) -> Sprite {
        let s = Sprite().mass(soft(x, y, 13, 7, 2.5), "pp").mass(rounded(x - 2, y + 7, 2, 2, 0), "pp")
        return s.fill([p(x + 3, y + 3), p(x + 6, y + 3), p(x + 9, y + 3)], "ik2")
    }

    private static let steam = steamSprite(1, -6)
    private static let anger = angerSprite(22, -9)
    private static let sweat = sweatSprite(31, 3)

    /// The mascot's layers at (0, 0): shadow, body with the frames of its animations, the signs
    /// beside it, the magnifier's glass. A new `motionKey` restarts the motion, so a new key per
    /// keystroke makes it hop again. `marksBeside` puts the signs beside the head instead of above
    /// it, for small drawings.
    public static func layers(_ look: MascotLook, motionKey: String = "", marksBeside: Bool = true) -> [PixelLayer] {
        let pose = look.pose
        let base = sprite(pose)
        var waved = pose
        waved.arms = .wave2
        let wave2 = look.wave ? sprite(waved) : nil
        waved.arms = .wave3
        let wave3 = look.wave ? sprite(waved) : nil
        var shut = pose
        shut.eyes = .blink
        let blink = wave2 == nil && look.blink && pose.eyes == .open ? sprite(shut) : nil
        let mx = marksBeside ? width : 16
        let my = marksBeside ? 2 : -10
        let key = "motion:\(motionKey)"
        let motion: [PxAnim] = switch look.motion {
        case .hop: [Px.msHop]
        case .jump: [Px.msJump]
        case .shake: [Px.msShake]
        case .fume: [Px.fume]
        case .buzz: [Px.buzz]
        case .bob: []
        }
        let moving = look.motion == .bob ? motion + [Px.breathe] : motion

        func make(_ s: Sprite, _ extra: [PxAnim] = [], anims: [PxAnim]? = nil, start: String? = nil) -> PixelLayer {
            PixelLayer(s, anims: (anims ?? moving) + extra, startKey: start ?? key)
        }

        var out = [PixelLayer(shadow)]
        out.append(make(base, wave2 != nil ? [Px.frameA] : blink != nil ? [Px.msOpen] : []))
        if let wave2 { out.append(make(wave2, [Px.frameB])) }
        if let wave3 { out.append(make(wave3, [Px.frameC])) }
        if let blink { out.append(make(blink, [Px.msBlink])) }
        if pose.arms == .lens { out.append(make(lensGlass)) }
        if look.sweat { out.append(make(sweat, [Px.drip])) }
        // The signs pop up, each restarting with the motion.
        if let mark = look.mark {
            out.append(make(markSprite(mark, x: mx, y: my), [Px.pop], anims: motion, start: "\(key)/mark\(mark)"))
        }
        if look.think {
            let thought = thinkingSprite(marksBeside ? width - 2 : 24, marksBeside ? 1 : -9)
            out.append(make(thought, [Px.pop], anims: motion, start: "\(key)/think"))
        }
        if look.anger {
            out.append(make(steam, [Px.pop, Px.steam], anims: motion, start: "\(key)/anger"))
            out.append(make(anger, [Px.pop, Px.throb], anims: motion, start: "\(key)/anger"))
        }
        return out
    }
}

/// How the whole figure moves: breathing on the spot, a hop per key, a jump, a shake, fuming, buzzing.
public enum MascotMotion: Hashable, Sendable { case bob, hop, jump, shake, fume, buzz }

public struct MascotLook: Hashable, Sendable {
    public var pose: Mascot.Pose
    public var blink: Bool
    public var wave: Bool
    /// '!' or '?' above the head.
    public var mark: Character?
    public var sweat: Bool
    public var think: Bool
    public var anger: Bool
    public var motion: MascotMotion

    public init(
        pose: Mascot.Pose = Mascot.Pose(),
        blink: Bool = false,
        wave: Bool = false,
        mark: Character? = nil,
        sweat: Bool = false,
        think: Bool = false,
        anger: Bool = false,
        motion: MascotMotion = .bob
    ) {
        self.pose = pose
        self.blink = blink
        self.wave = wave
        self.mark = mark
        self.sweat = sweat
        self.think = think
        self.anger = anger
        self.motion = motion
    }
}

/// The mascot in a look, `size` points wide. Signs can reach outside the drawing, so leave room
/// beside it. `motionKey` restarts the motion when it changes.
public struct MascotView: View {
    let look: MascotLook
    let size: CGFloat
    let motionKey: String
    let marksBeside: Bool

    public init(look: MascotLook, size: CGFloat = 120, motionKey: String = "", marksBeside: Bool = true) {
        self.look = look
        self.size = size
        self.motionKey = motionKey
        self.marksBeside = marksBeside
    }

    public var body: some View {
        PixelArt(
            scene: PixelScene(w: Mascot.width, h: Mascot.height, layers: Mascot.layers(look, motionKey: motionKey, marksBeside: marksBeside)),
            clip: false
        )
        .frame(width: size)
    }
}
