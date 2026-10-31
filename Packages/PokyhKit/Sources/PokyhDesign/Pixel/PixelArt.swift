import PokyhCore
import SwiftUI

// The pixel art, drawn like the web's and Android's. What to use:
//
//   PixelSpriteArt(.empty, width: 160)          a state scene (PixelSprite lists them)
//   StateView(title, message: m, sprite: .mail) a scene with its text and actions
//   MascotView(look: MascotLook(pose: ...), size: 120)   the mascot in any pose
//   LoginMascotBadge(state: ...)                the mascot that answers the sign-in form
//   PixelIcon(.key)                             a 16 × 16 icon
//   PixelPlate(style: .pasta, seed: dish.id)    a dish on its plate
//   PixelArt(scene: PixelScene(...))            your own: Mascot.layers(...) plus bubbles and such
//
// Sprites are built once and kept, so these are cheap in lists. They redraw only while on screen,
// and Reduce Motion gets the still frame.

/// A sprite and the animations on it, outermost first (they add up). Layers with the same
/// `startKey` start together the moment the key first appears, so a new key restarts them; without
/// one a layer runs from when the drawing is first shown.
public struct PixelLayer: Sendable {
    public let sprite: Sprite
    public let anims: [PxAnim]
    public let startKey: String?
    public let dx: Int
    public let dy: Int

    public init(_ sprite: Sprite, anims: [PxAnim] = [], startKey: String? = nil, dx: Int = 0, dy: Int = 0) {
        self.sprite = sprite
        self.anims = anims
        self.startKey = startKey
        self.dx = dx
        self.dy = dy
    }
}

/// A drawing: its size in pixels, starting at (x0, y0), and its layers back to front.
public struct PixelScene: Sendable {
    public let w: Int
    public let h: Int
    public let layers: [PixelLayer]
    public let x0: Int
    public let y0: Int

    public init(w: Int, h: Int, layers: [PixelLayer], x0: Int = 0, y0: Int = 0) {
        self.w = w
        self.h = h
        self.layers = layers
        self.x0 = x0
        self.y0 = y0
    }

    var isAnimated: Bool { layers.contains { !$0.anims.isEmpty } }

    // The mascot's jumps and shakes stay within this many pixels.
    private static let motionReach = 8

    /// How far the layers can reach outside the drawing, in its pixels.
    func margins(dark: Bool) -> PixelMargins {
        var m = PixelMargins()
        for layer in layers {
            guard let b = layer.sprite.bitmap(dark: dark) else { continue }
            let reach = layer.anims.isEmpty ? 0 : Self.motionReach
            m.left = max(m.left, x0 - (b.x + layer.dx - reach))
            m.top = max(m.top, y0 - (b.y + layer.dy - reach))
            m.right = max(m.right, b.x + layer.dx + b.w + reach - (x0 + w))
            m.bottom = max(m.bottom, b.y + layer.dy + b.h + reach - (y0 + h))
        }
        return m
    }
}

struct PixelMargins {
    var left = 0
    var top = 0
    var right = 0
    var bottom = 0
}

/// How a drawing fits a space, in screen pixels: a whole number of them per drawing pixel once
/// there is room for it, so every pixel comes out the same size.
struct PixelFit {
    let pixel: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    init(size: CGSize, displayScale: CGFloat, w: Int, h: Int, x0: Int = 0, y0: Int = 0) {
        let wide = size.width * displayScale
        let high = size.height * displayScale
        let fit = max(0, min(wide / CGFloat(w), high / CGFloat(h)))
        pixel = fit >= 2 ? fit.rounded(.down) : fit
        ox = (wide - CGFloat(w) * pixel) / 2 - CGFloat(x0) * pixel
        oy = (high - CGFloat(h) * pixel) / 2 - CGFloat(y0) * pixel
    }

    func rect(x: Double, y: Double, w: Int, h: Int) -> CGRect {
        CGRect(
            x: Self.round(ox + CGFloat(x) * pixel),
            y: Self.round(oy + CGFloat(y) * pixel),
            width: Self.round(CGFloat(w) * pixel),
            height: Self.round(CGFloat(h) * pixel)
        )
    }

    private static func round(_ v: CGFloat) -> CGFloat { (v + 0.5).rounded(.down) }
}

extension GraphicsContext {
    /// A pixel bitmap without smoothing.
    mutating func drawPixels(_ image: CGImage, in rect: CGRect) {
        draw(Image(decorative: image, scale: 1).interpolation(.none).antialiased(false), in: rect)
    }
}

extension View {
    /// Keeps a flag on whether the view can be seen, so the animations can stop when it can't.
    func trackingOnScreen(_ onScreen: Binding<Bool>) -> some View {
        self
            .onAppear { onScreen.wrappedValue = true }
            .onDisappear { onScreen.wrappedValue = false }
            .onScrollVisibilityChange(threshold: 0.01) { onScreen.wrappedValue = $0 }
    }
}

/// Draws a scene as crisp square pixels, scaled to the space given and centred. The width decides
/// the size, the height follows the drawing. Decorative unless it gets a `label`.
public struct PixelArt: View {
    let scene: PixelScene
    let label: String?
    let clip: Bool
    let animate: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var clock = PixelClock()
    @State private var onScreen = true

    public init(scene: PixelScene, label: String? = nil, clip: Bool = true, animate: Bool = true) {
        self.scene = scene
        self.label = label
        self.clip = clip
        self.animate = animate
    }

    public var body: some View {
        let starts = clock.note(scene)
        Color.clear
            .aspectRatio(CGFloat(scene.w) / CGFloat(scene.h), contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    // A Canvas can't draw outside its frame, unlike Android's. So an unclipped
                    // drawing gets a bigger one, moved so the pixels stay where they belong.
                    let dark = scheme == .dark
                    let out = clip ? PixelMargins() : scene.margins(dark: dark)
                    let fit = PixelFit(size: geo.size, displayScale: displayScale, w: scene.w, h: scene.h, x0: scene.x0, y0: scene.y0)
                    let point = fit.pixel / displayScale
                    Group {
                        if animate && !reduceMotion && scene.isAnimated {
                            let paused = !onScreen || scenePhase != .active || luminanceReduced
                            // The steps are 40 ms at their shortest, there's nothing to gain from every frame.
                            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                                canvas(at: timeline.date, starts: starts, fit: fit, out: out, dark: dark)
                            }
                        } else {
                            canvas(at: clock.shownAt, starts: starts, fit: fit, out: out, dark: dark)
                        }
                    }
                    .frame(
                        width: geo.size.width + CGFloat(out.left + out.right) * point,
                        height: geo.size.height + CGFloat(out.top + out.bottom) * point
                    )
                    .offset(x: -CGFloat(out.left) * point, y: -CGFloat(out.top) * point)
                    .allowsHitTesting(false)
                }
            }
            .trackingOnScreen($onScreen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
    }

    private func canvas(at date: Date, starts: [String: Date], fit: PixelFit, out: PixelMargins, dark: Bool) -> some View {
        let scene = scene, reduced = reduceMotion
        let clip = clip, displayScale = displayScale, shownAt = clock.shownAt
        return Canvas { context, _ in
            guard fit.pixel > 0 else { return }
            context.scaleBy(x: 1 / displayScale, y: 1 / displayScale)
            context.translateBy(x: CGFloat(out.left) * fit.pixel, y: CGFloat(out.top) * fit.pixel)
            if clip {
                context.clip(to: Path(fit.rect(x: Double(scene.x0), y: Double(scene.y0), w: scene.w, h: scene.h)))
            }
            for layer in scene.layers {
                guard let bitmap = layer.sprite.bitmap(dark: dark) else { continue }
                let start = layer.startKey.flatMap { starts[$0] } ?? shownAt
                let ms = Int64(date.timeIntervalSince(start) * 1000)
                var frame = PixelFrame()
                for anim in layer.anims { anim.apply(ms, reduced: reduced, to: &frame) }
                if frame.alpha <= 0.001 { continue }
                let rect = fit.rect(
                    x: Double(bitmap.x + layer.dx) + frame.tx,
                    y: Double(bitmap.y + layer.dy) + frame.ty,
                    w: bitmap.w,
                    h: bitmap.h
                )
                var c = context
                c.opacity = min(1, frame.alpha)
                if frame.rotate.truncatingRemainder(dividingBy: 360) != 0 {
                    c.translateBy(x: rect.midX, y: rect.midY)
                    c.rotate(by: .degrees(frame.rotate))
                    c.translateBy(x: -rect.midX, y: -rect.midY)
                }
                c.drawPixels(bitmap.image, in: rect)
            }
        }
    }
}

/// When a drawing was first shown and when each start key appeared.
private final class PixelClock {
    let shownAt = Date()
    private var starts: [String: Date] = [:]

    func note(_ scene: PixelScene) -> [String: Date] {
        let keys = Set(scene.layers.compactMap(\.startKey))
        starts = starts.filter { keys.contains($0.key) }
        let now = Date()
        for key in keys where starts[key] == nil { starts[key] = now }
        return starts
    }
}
