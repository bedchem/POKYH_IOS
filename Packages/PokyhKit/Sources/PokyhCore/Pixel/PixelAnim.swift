// Sprite animations the way a CSS @keyframes rule runs them, so they move as on the web and on
// Android: keyframes at offsets 0 to 1, and between two of them the value moves in `steps` jumps
// (CSS `steps(n, end)` per interval). One step holds each value until the next keyframe.

public struct PxTrack: Sendable {
    private let steps: Int
    private let frames: [(Double, Double)]

    public init(_ steps: Int, _ frames: [(Double, Double)]) {
        self.steps = steps
        self.frames = frames
    }

    public func at(_ p: Double) -> Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        if p <= first.0 { return first.1 }
        for i in 0..<(frames.count - 1) {
            let (k0, v0) = frames[i]
            let (k1, v1) = frames[i + 1]
            if p < k1 {
                if k1 <= k0 { return v1 }
                let f = (((p - k0) / (k1 - k0)) * Double(steps)).rounded(.down) / Double(steps)
                return v0 + (v1 - v0) * f
            }
        }
        return last.1
    }
}

/// A layer's place at one moment: offset in drawing pixels, opacity, turn in degrees.
public struct PixelFrame: Sendable {
    public var tx = 0.0
    public var ty = 0.0
    public var alpha = 1.0
    public var rotate = 0.0

    public init() {}
}

/// One of the web's `.px-*` / `.ms-*` classes. Lengths are pixels of the drawing. `baseOpacity` is
/// the layer's own opacity outside the animation; `reduced*` is what Reduce Motion shows instead.
public struct PxAnim: Sendable {
    let durationMs: Int64
    let delayMs: Int64
    let infinite: Bool
    /// Keep the last keyframe after a one-shot ends and the first during its delay (CSS `both`).
    let fillBoth: Bool
    let tx: PxTrack?
    let ty: PxTrack?
    let opacity: PxTrack?
    /// Degrees, about the layer's own middle.
    let rotate: PxTrack?
    let baseOpacity: Double
    let reducedTx: Double
    let reducedTy: Double
    let reducedOpacity: Double?

    init(
        _ durationMs: Int64,
        delayMs: Int64 = 0,
        infinite: Bool = true,
        fillBoth: Bool = false,
        tx: PxTrack? = nil,
        ty: PxTrack? = nil,
        opacity: PxTrack? = nil,
        rotate: PxTrack? = nil,
        baseOpacity: Double = 1,
        reducedTx: Double = 0,
        reducedTy: Double = 0,
        reducedOpacity: Double? = nil
    ) {
        self.durationMs = durationMs
        self.delayMs = delayMs
        self.infinite = infinite
        self.fillBoth = fillBoth
        self.tx = tx
        self.ty = ty
        self.opacity = opacity
        self.rotate = rotate
        self.baseOpacity = baseOpacity
        self.reducedTx = reducedTx
        self.reducedTy = reducedTy
        self.reducedOpacity = reducedOpacity
    }

    public func delayed(_ ms: Int64) -> PxAnim {
        PxAnim(durationMs, delayMs: ms, infinite: infinite, fillBoth: fillBoth, tx: tx, ty: ty, opacity: opacity, rotate: rotate,
               baseOpacity: baseOpacity, reducedTx: reducedTx, reducedTy: reducedTy, reducedOpacity: reducedOpacity)
    }

    // The phase 0 to 1, or nil for "not running".
    private func phase(_ elapsedMs: Int64) -> Double? {
        let t = elapsedMs - delayMs
        if t < 0 { return fillBoth ? 0 : nil }
        if infinite { return Double(t % durationMs) / Double(durationMs) }
        if t >= durationMs { return fillBoth ? 1 : nil }
        return Double(t) / Double(durationMs)
    }

    /// Adds this animation's effect at `elapsedMs` to the frame.
    public func apply(_ elapsedMs: Int64, reduced: Bool, to f: inout PixelFrame) {
        if reduced {
            f.tx += reducedTx
            f.ty += reducedTy
            f.alpha *= reducedOpacity ?? baseOpacity
            return
        }
        guard let p = phase(elapsedMs) else {
            f.alpha *= baseOpacity
            return
        }
        if let tx { f.tx += tx.at(p) }
        if let ty { f.ty += ty.at(p) }
        f.alpha *= opacity?.at(p) ?? baseOpacity
        if let rotate { f.rotate += rotate.at(p) }
    }
}

private func tr(_ steps: Int, _ frames: (Double, Double)...) -> PxTrack { PxTrack(steps, frames) }

/// The web's sprite animations (app/globals.css), by their class names.
public enum Px {
    // MARK: The state scenes (.px-*)

    public static let plug = PxAnim(2400, tx: tr(1, (0, 0), (0.25, 0), (0.30, 2), (0.36, 4), (0.62, 4), (0.70, 2), (0.78, 0), (1, 0)))
    public static let spark = PxAnim(2400, opacity: tr(1, (0, 0), (0.38, 0), (0.40, 1), (0.46, 0), (0.50, 1), (0.56, 0), (1, 0)), baseOpacity: 0, reducedOpacity: 1)
    public static let sparkLate = spark.delayed(150)
    public static let lens = PxAnim(
        3600,
        tx: tr(1, (0, 5), (0.12, 5), (0.18, 10), (0.30, 10), (0.36, 15), (0.48, 15), (0.54, 19), (0.66, 19), (0.72, 11), (0.84, 11), (0.90, 5), (1, 5)),
        ty: tr(1, (0, 4), (0.12, 4), (0.18, 6), (0.30, 6), (0.36, 4), (0.48, 4), (0.54, 7), (0.66, 7), (0.72, 8), (0.84, 8), (0.90, 4), (1, 4)),
        reducedTx: 5,
        reducedTy: 4
    )
    public static let question = PxAnim(3600, opacity: tr(1, (0, 0), (0.60, 0), (0.62, 1), (0.74, 1), (0.76, 0), (0.78, 1), (0.90, 1), (0.92, 0), (1, 0)))
    public static let shackle = PxAnim(1800, ty: tr(1, (0, 0), (0.40, 0), (0.45, -1), (0.50, -2), (0.62, -2), (0.67, -1), (0.72, 0), (1, 0)))
    public static let tumble = PxAnim(4600, tx: tr(54, (0, -11), (0.86, 43), (1, 43)), reducedTx: 4)
    public static let hop = PxAnim(700, ty: tr(1, (0, 0), (0.24, 0), (0.25, -1), (0.39, -1), (0.40, -2), (0.59, -2), (0.60, -1), (0.74, -1), (0.75, 0), (1, 0)))
    public static let turn = PxAnim(800, rotate: tr(4, (0, 0), (1, 360)))
    public static let blink = PxAnim(1200, opacity: tr(1, (0, 1), (0.59, 1), (0.60, 0.25), (1, 0.25)))
    public static let ray = PxAnim(1400, opacity: tr(1, (0, 1), (0.49, 1), (0.50, 0), (1, 0)))
    public static let waves = PxAnim(2400, tx: tr(1, (0, 0), (0.16, 0), (0.17, 1), (0.33, 1), (0.34, 2), (0.49, 2), (0.50, 3), (0.66, 3), (0.67, 4), (0.83, 4), (0.84, 5), (1, 5)))
    public static let cloud = PxAnim(9000, tx: tr(60, (0, -16), (1, 42)), reducedTx: 2)
    public static let flag = PxAnim(900, opacity: tr(1, (0, 1), (0.49, 1), (0.50, 0), (1, 0)))
    public static let flagAlt = PxAnim(900, opacity: tr(1, (0, 0), (0.49, 0), (0.50, 1), (1, 1)), reducedOpacity: 0)
    public static let arrowR = PxAnim(1600, tx: tr(1, (0, -1), (0.24, -1), (0.25, 0), (0.49, 0), (0.50, 1), (0.74, 1), (0.75, 0), (1, 0)))
    public static let arrowL = PxAnim(1600, tx: tr(1, (0, 1), (0.24, 1), (0.25, 0), (0.49, 0), (0.50, -1), (0.74, -1), (0.75, 0), (1, 0)))
    public static let type = PxAnim(1500, ty: tr(1, (0, -1), (0.30, -1), (0.31, 0), (1, 0)), opacity: tr(1, (0, 1), (0.30, 1), (0.31, 0.25), (1, 0.25)), baseOpacity: 0.25, reducedOpacity: 1)
    public static let reply = PxAnim(3000, ty: tr(1, (0, 1), (0.60, 1), (0.61, 0), (1, 0)), opacity: tr(1, (0, 0), (0.55, 0), (0.56, 1), (0.92, 1), (0.93, 0), (1, 0)), baseOpacity: 0, reducedOpacity: 1)
    public static let z = PxAnim(2600, ty: tr(6, (0, 5), (1, -1)), opacity: tr(6, (0, 0), (0.15, 1), (0.80, 1), (1, 0)), baseOpacity: 0, reducedOpacity: 1)
    public static let swing = PxAnim(800, tx: tr(1, (0, -1), (0.24, -1), (0.25, 0), (0.49, 0), (0.50, 1), (0.74, 1), (0.75, 0), (1, 0)))
    public static let clapper = PxAnim(800, tx: tr(1, (0, 1), (0.24, 1), (0.25, 0), (0.49, 0), (0.50, -1), (0.74, -1), (0.75, 0), (1, 0)))
    public static let wave = PxAnim(800, opacity: tr(1, (0, 1), (0.30, 1), (0.31, 0), (1, 0)), baseOpacity: 0, reducedOpacity: 1)
    public static let snow = PxAnim(
        2400,
        tx: tr(1, (0, 0), (0.25, 0), (0.37, 1), (0.50, 1), (0.62, 0), (0.75, 0), (0.88, -1), (1, -1)),
        ty: tr(1, (0, -2), (0.12, -1), (0.25, 0), (0.37, 1), (0.50, 2), (0.62, 3), (0.75, 4), (0.88, 5), (1, 6)),
        opacity: tr(1, (0, 0), (0.12, 1), (0.88, 1), (1, 0))
    )
    public static let flutter = PxAnim(
        2800,
        tx: tr(1, (0, 0), (0.2, -1), (0.4, -2), (0.6, -1), (0.8, 1), (1, 0)),
        ty: tr(1, (0, 0), (0.2, -1), (0.4, 0), (0.6, 1), (0.8, 0), (1, 0))
    )
    public static let fall = PxAnim(
        3300,
        tx: tr(1, (0, 0), (0.20, 1), (0.35, 2), (0.50, 1), (0.65, 0), (0.80, 1), (1, 2)),
        ty: tr(1, (0, 0), (0.20, 1), (0.35, 3), (0.50, 4), (0.65, 5), (0.80, 6), (1, 7)),
        opacity: tr(1, (0, 0), (0.08, 1), (0.80, 1), (1, 0)),
        baseOpacity: 0,
        reducedOpacity: 1
    )

    // MARK: The mascot (.ms-*)

    public static let breathe = PxAnim(1800, ty: tr(1, (0, 0), (0.49, 0), (0.50, 1), (1, 1)))
    public static let msHop = PxAnim(300, infinite: false, ty: tr(3, (0, 0), (0.40, -3), (1, 0)))
    public static let msJump = PxAnim(700, infinite: false, ty: tr(7, (0, 0), (0.15, 1), (0.45, -6), (0.70, -2), (1, 0)))
    public static let msShake = PxAnim(500, infinite: false, tx: tr(1, (0, 0), (0.15, -2), (0.35, 2), (0.55, -1), (0.75, 1), (1, 0)))
    public static let msOpen = PxAnim(4400, delayMs: 1000, opacity: tr(1, (0, 1), (0.92, 1), (0.93, 0), (0.96, 0), (0.97, 1), (1, 1)))
    public static let msBlink = PxAnim(4400, delayMs: 1000, opacity: tr(1, (0, 0), (0.92, 0), (0.93, 1), (0.96, 1), (0.97, 0), (1, 0)), baseOpacity: 0, reducedOpacity: 0)
    public static let frameA = PxAnim(840, opacity: tr(1, (0, 1), (0.24, 1), (0.25, 0), (1, 0)))
    public static let frameB = PxAnim(840, opacity: tr(1, (0, 0), (0.24, 0), (0.25, 1), (0.49, 1), (0.50, 0), (0.74, 0), (0.75, 1), (1, 1)), baseOpacity: 0, reducedOpacity: 0)
    public static let frameC = PxAnim(840, opacity: tr(1, (0, 0), (0.49, 0), (0.50, 1), (0.74, 1), (0.75, 0), (1, 0)), baseOpacity: 0, reducedOpacity: 0)
    public static let fume = PxAnim(400, tx: tr(1, (0, 0), (0.25, -1), (0.75, 1), (1, 0)))
    public static let throb = PxAnim(600, tx: tr(1, (0, 0), (0.49, 0), (0.50, 1), (1, 1)), ty: tr(1, (0, 0), (0.49, 0), (0.50, -1), (1, -1)))
    public static let steam = PxAnim(1200, ty: tr(4, (0, 0), (1, -4)), opacity: tr(4, (0, 1), (1, 0)))
    public static let buzz = PxAnim(320, tx: tr(1, (0, -1), (0.25, 1), (0.50, -1), (0.75, 1), (1, -1)), ty: tr(1, (0, 0), (0.25, -2), (0.50, -3), (0.75, -1), (1, 0)))
    public static let pop = PxAnim(240, infinite: false, fillBoth: true, ty: tr(3, (0, 2), (1, 0)), opacity: tr(3, (0, 0), (1, 1)))
    public static let drip = PxAnim(1100, ty: tr(3, (0, 0), (1, 3)), opacity: tr(3, (0, 1), (1, 0.4)))
}
