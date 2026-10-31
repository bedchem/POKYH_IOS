import CoreGraphics
import Foundation
import Synchronization

// Sprites drawn in code, the same engine as the web's components/pixel/sprite.ts and Android's
// ui/pixel/Sprite.kt, so the drawings match pixel for pixel: square pixels, a few flat tones per
// material, light from the top left, outlines in the material's darkest tone, dithered shadows.
//
// A tone is a material and a step: 0 outline, 1 shade, 2 base, 3 light, 4 highlight, e.g. "ac2"
// (the accent) or "pp3" (lit paper). A few are single colours without steps ("sh", "gl").
//
// This part has no UI so the tests can reach it. The drawings and views are in PokyhDesign/Pixel.

public struct Pt: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

/// A grid of tones. Only changed while it is being drawn, then shared read-only.
public final class Sprite: @unchecked Sendable {
    private var cells: [Pt: String] = [:]
    private let bitmaps = Mutex<(light: SpriteBitmap?, dark: SpriteBitmap?)>((nil, nil))

    public init() {}

    @discardableResult
    public func set(_ x: Int, _ y: Int, _ tone: String?) -> Sprite {
        cells[Pt(x, y)] = tone
        return self
    }

    public func get(_ x: Int, _ y: Int) -> String? { cells[Pt(x, y)] }

    @discardableResult
    public func fill(_ points: [Pt], _ tone: String?) -> Sprite {
        for p in points { cells[p] = tone }
        return self
    }

    /// Rows of characters at (ox, oy). '.' and ' ' stay empty, the legend names the rest.
    @discardableResult
    public func rows(_ rows: [String], _ ox: Int, _ oy: Int, legend: [Character: String]) -> Sprite {
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c != "." && c != " " {
                if let tone = legend[c] { set(ox + x, oy + y, tone) }
            }
        }
        return self
    }

    @discardableResult
    public func paste(_ other: Sprite, dx: Int = 0, dy: Int = 0) -> Sprite {
        for (p, tone) in other.cells { cells[Pt(p.x + dx, p.y + dy)] = tone }
        return self
    }

    /// A shape in a material: lit where it faces the top left, shaded where it faces away,
    /// outlined in the darkest tone. With `round` the light follows the direction from that centre
    /// (balls, rings). `outline: false` is for shapes inside others.
    @discardableResult
    public func mass(_ mask: [Pt], _ mat: String, outline: Bool = true, round: (Double, Double)? = nil, deep: Bool = false) -> Sprite {
        let on = Set(mask)
        func m(_ x: Int, _ y: Int) -> Bool { on.contains(Pt(x, y)) }
        if outline { fill(PixelGrid.outlineOf(mask), "\(mat)0") }
        for p in mask {
            let x = p.x, y = p.y
            var step = 2
            if let round {
                let f = PixelGrid.facing(round, x, y)
                let edge = !m(x - 1, y) || !m(x + 1, y) || !m(x, y - 1) || !m(x, y + 1)
                    || !m(x - 2, y) || !m(x + 2, y) || !m(x, y - 2) || !m(x, y + 2)
                if edge && f > 0.35 {
                    step = 3
                } else if f < -0.3 && (edge || deep) {
                    step = 1
                }
            } else if !m(x, y - 1) || !m(x - 1, y) {
                step = 3
            } else if !m(x, y + 1) || !m(x + 1, y) || (deep && (!m(x + 1, y + 1) || !m(x, y + 2) || !m(x + 2, y))) {
                step = 1
            }
            cells[p] = "\(mat)\(step)"
        }
        return self
    }

    /// Swaps one material for another, step for step (stripes, recolouring).
    @discardableResult
    public func recolor(_ points: [Pt], from: String, to: String) -> Sprite {
        for p in points {
            guard let tone = cells[p], tone.hasPrefix(from), tone.count == from.count + 1,
                  let step = tone.last, step.isNumber else { continue }
            cells[p] = "\(to)\(step)"
        }
        return self
    }

    public func shifted(_ dx: Int, _ dy: Int) -> Sprite { Sprite().paste(self, dx: dx, dy: dy) }

    public func forEachCell(_ action: (Int, Int, String) -> Void) {
        for (p, tone) in cells { action(p.x, p.y, tone) }
    }

    public var isEmpty: Bool { cells.isEmpty }

    public func bounds() -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        guard let first = cells.keys.first else { return nil }
        var box = (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in cells.keys {
            box.minX = min(box.minX, p.x)
            box.minY = min(box.minY, p.y)
            box.maxX = max(box.maxX, p.x)
            box.maxY = max(box.maxY, p.y)
        }
        return box
    }

    /// The topmost row, for the room a drawing needs above it.
    public func top() -> Int { bounds()?.minY ?? 0 }

    /// The sprite at one pixel per drawing pixel, built once per theme and kept with the sprite.
    public func bitmap(dark: Bool) -> SpriteBitmap? {
        if let done = bitmaps.withLock({ dark ? $0.dark : $0.light }) { return done }
        guard let box = bounds() else { return nil }
        let w = box.maxX - box.minX + 1
        let h = box.maxY - box.minY + 1
        let tones = PixelPalette.tones(dark: dark)
        var pixels = [UInt32](repeating: 0, count: w * h)
        for (p, tone) in cells {
            pixels[(p.y - box.minY) * w + (p.x - box.minX)] = tones[tone] ?? 0
        }
        guard let image = PixelBitmap.image(argb: pixels, width: w, height: h) else { return nil }
        let made = SpriteBitmap(image: image, x: box.minX, y: box.minY, w: w, h: h)
        bitmaps.withLock { if dark { $0.dark = made } else { $0.light = made } }
        return made
    }
}

public struct SpriteBitmap: @unchecked Sendable {
    public let image: CGImage
    /// Where its top left lies in the drawing.
    public let x: Int
    public let y: Int
    public let w: Int
    public let h: Int
}

public enum PixelBitmap {
    /// Straight ARGB pixels as an image. Core Graphics wants them premultiplied.
    public static func image(argb: [UInt32], width: Int, height: Int) -> CGImage? {
        let pixels = argb.map(premultiplied)
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func premultiplied(_ c: UInt32) -> UInt32 {
        let a = c >> 24
        if a == 255 { return c }
        func ch(_ shift: UInt32) -> UInt32 { (((c >> shift) & 255) * a + 127) / 255 }
        return (a << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }
}

public struct TextPixels: Sendable {
    public let points: [Pt]
    public let width: Int
}

/// Shapes as lists of pixels. A namespace conforms to get them unqualified, so a drawing reads as
/// its Android counterpart does.
public protocol PixelDrawing {}

public enum PixelGrid: PixelDrawing {}

extension PixelDrawing {
    public static func p(_ x: Int, _ y: Int) -> Pt { Pt(x, y) }

    /// The pixels marked with `ch` in rows of characters, placed at (ox, oy).
    public static func grid(_ rows: [String], _ ox: Int = 0, _ oy: Int = 0, ch: Character = "#") -> [Pt] {
        var out: [Pt] = []
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c == ch { out.append(Pt(ox + x, oy + y)) }
        }
        return out
    }

    public static func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> [Pt] {
        var out: [Pt] = []
        out.reserveCapacity(max(0, w * h))
        for j in 0..<max(0, h) {
            for i in 0..<max(0, w) { out.append(Pt(x + i, y + j)) }
        }
        return out
    }

    /// A rectangle with its corners cut straight by `r` steps.
    public static func rounded(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ r: Int = 1) -> [Pt] {
        rect(x, y, w, h).filter { p in
            let dx = max(x + r - p.x, p.x - (x + w - 1 - r), 0)
            let dy = max(y + r - p.y, p.y - (y + h - 1 - r), 0)
            return dx + dy <= r
        }
    }

    /// A rectangle with round corners of radius `r`.
    public static func soft(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ r: Double) -> [Pt] {
        rect(x, y, w, h).filter { p in
            let px = Double(p.x) + 0.5, py = Double(p.y) + 0.5
            let cx = min(max(px, Double(x) + r), Double(x + w) - r)
            let cy = min(max(py, Double(y) + r), Double(y + h) - r)
            return hypot(px - cx, py - cy) <= r - 0.2
        }
    }

    /// A thick stroke: discs of radius `r` along a line.
    public static func limb(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ r: Double) -> [Pt] {
        var seen = Set<Pt>()
        var out: [Pt] = []
        let steps = max(1, Int((hypot(x1 - x0, y1 - y0) * 2).rounded(.up)))
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            for p in disc(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r) where seen.insert(p).inserted {
                out.append(p)
            }
        }
        return out
    }

    /// Pixels whose centre lies within `r` of (cx, cy).
    public static func disc(_ cx: Double, _ cy: Double, _ r: Double) -> [Pt] { ellipse(cx, cy, r, r) }

    public static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> [Pt] {
        var out: [Pt] = []
        for y in Int((cy - ry - 1).rounded(.down))...Int((cy + ry + 1).rounded(.up)) {
            for x in Int((cx - rx - 1).rounded(.down))...Int((cx + rx + 1).rounded(.up)) {
                let dx = (Double(x) + 0.5 - cx) / rx
                let dy = (Double(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1 { out.append(Pt(x, y)) }
            }
        }
        return out
    }

    /// A one-pixel line (Bresenham).
    public static func line(_ fromX: Int, _ fromY: Int, _ x1: Int, _ y1: Int) -> [Pt] {
        var x0 = fromX, y0 = fromY
        var out: [Pt] = []
        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            out.append(Pt(x0, y0))
            if x0 == x1 && y0 == y1 { return out }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x0 += sx }
            if e2 <= dx { err += dx; y0 += sy }
        }
    }

    public static func shift(_ points: [Pt], _ dx: Int, _ dy: Int) -> [Pt] {
        points.map { Pt($0.x + dx, $0.y + dy) }
    }

    public static func minus(_ points: [Pt], _ cut: [Pt]) -> [Pt] {
        let gone = Set(cut)
        return points.filter { !gone.contains($0) }
    }

    /// The pixels right around a shape (above, below, left, right).
    public static func outlineOf(_ shape: [Pt]) -> [Pt] {
        let on = Set(shape)
        var seen = Set<Pt>()
        var out: [Pt] = []
        for p in shape {
            for n in [Pt(p.x - 1, p.y), Pt(p.x + 1, p.y), Pt(p.x, p.y - 1), Pt(p.x, p.y + 1)]
            where !on.contains(n) && seen.insert(n).inserted {
                out.append(n)
            }
        }
        return out
    }

    /// Every other pixel of a shape, for dithered shadows and light. Works left of zero too.
    public static func dither(_ points: [Pt], _ parity: Int = 0) -> [Pt] {
        points.filter { (($0.x + $0.y) % 2 + 2) % 2 == parity }
    }

    /// How much a pixel faces the light from the top left, seen from `centre` (-1 to 1).
    public static func facing(_ centre: (Double, Double), _ x: Int, _ y: Int) -> Double {
        let dx = Double(x) + 0.5 - centre.0
        let dy = Double(y) + 0.5 - centre.1
        let h = hypot(dx, dy)
        let d = h == 0 ? 1 : h
        return (dx / d) * -0.61 + (dy / d) * -0.79
    }

    /// JavaScript's Math.round: halves go up, towards +infinity. The drawings depend on it.
    public static func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

    /// Text in capitals; accents are dropped, signs the font doesn't have become '?'.
    public static func textPixels(_ text: String, _ ox: Int = 0, _ oy: Int = 0) -> TextPixels {
        var points: [Pt] = []
        var x = ox
        for c in PixelFont.plain(text) {
            let glyph = PixelFont.glyphs[c] ?? PixelFont.glyphs["?"] ?? []
            points += grid(glyph, x, oy)
            x += (glyph.first?.count ?? 0) + 1
        }
        return TextPixels(points: points, width: max(0, x - ox - 1))
    }

    /// Splits text into lines at most `maxWidth` pixels wide, the last one cut with "…".
    public static func wrapText(_ text: String, _ maxWidth: Int, maxLines: Int = 3) -> [String] {
        func width(_ t: String) -> Int { textPixels(t).width }
        var lines: [String] = []
        var line = ""
        func flush() {
            if !line.isEmpty { lines.append(line) }
            line = ""
        }
        for word in text.split(whereSeparator: \.isWhitespace) {
            // A word breaks after its own separators first ("anna-maria." → "anna-", "maria.").
            for (i, part) in PixelFont.parts(of: String(word)).enumerated() {
                let joined = line.isEmpty ? part : "\(line)\(i == 0 ? " " : "")\(part)"
                if width(joined) <= maxWidth {
                    line = joined
                    continue
                }
                flush()
                var rest = part
                while width(rest) > maxWidth {
                    var cut = rest.count - 1
                    while cut > 1 && width(String(rest.prefix(cut))) > maxWidth { cut -= 1 }
                    lines.append(String(rest.prefix(cut)))
                    rest = String(rest.dropFirst(cut))
                }
                line = rest
            }
        }
        flush()
        if lines.count > maxLines {
            var kept = Array(lines.prefix(maxLines))
            var last = kept[maxLines - 1]
            if let end = last.last, PixelFont.breaks.contains(end) { last.removeLast() }
            while last.count > 1 && width("\(last)…") > maxWidth { last.removeLast() }
            kept[maxLines - 1] = "\(last)…"
            return kept
        }
        return lines.isEmpty ? [""] : lines
    }
}

// A 3 × 5 pixel font: capitals, digits, a few signs.
private enum PixelFont {
    static let breaks: Set<Character> = ["-", ".", "_", "/"]

    static func parts(of word: String) -> [String] {
        var out: [String] = []
        var part = ""
        for c in word {
            part.append(c)
            if breaks.contains(c) {
                out.append(part)
                part = ""
            }
        }
        if !part.isEmpty { out.append(part) }
        return out
    }

    static func plain(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in text.decomposedStringWithCanonicalMapping.unicodeScalars where !(0x300...0x36F).contains(u.value) {
            scalars.append(u)
        }
        return String(scalars).replacingOccurrences(of: "ß", with: "SS").uppercased()
    }

    static let glyphs: [Character: [String]] = [
        "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
        "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
        "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
        "M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
        "O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
        "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
        "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
        "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", ".#.", ".#."],
        "W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
        "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
        "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
        "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
        "!": ["#", "#", "#", ".", "#"], "?": ["##.", "..#", ".#.", "...", ".#."],
        ".": [".", ".", ".", ".", "#"], ",": ["..", "..", "..", ".#", "#."],
        ":": [".", "#", ".", "#", "."], "-": ["...", "...", "###", "...", "..."],
        "_": ["...", "...", "...", "...", "###"], "'": ["#", "#", ".", ".", "."],
        "’": ["#", "#", ".", ".", "."],
        "/": ["..#", "..#", ".#.", "#..", "#.."], "@": ["###", "#.#", "#.#", "#..", ".##"],
        "+": ["...", ".#.", "###", ".#.", "..."], "…": [".....", ".....", ".....", ".....", "#.#.#"],
        "(": [".#", "#.", "#.", "#.", ".#"], ")": ["#.", ".#", ".#", ".#", "#."],
        "=": ["...", "###", "...", "###", "..."], "<": ["..#", ".#.", "#..", ".#.", "..#"],
        ">": ["#..", ".#.", "..#", ".#.", "#.."], "%": ["#.#", "..#", ".#.", "#..", "#.#"],
        "*": ["...", "#.#", ".#.", "#.#", "..."], "×": ["...", "#.#", ".#.", "#.#", "..."],
        "÷": [".#.", "...", "###", "...", ".#."], "♥": [".#.#.", "#####", "#####", ".###.", "..#.."],
        "★": ["..#..", "#####", ".###.", ".#.#.", "#...#"], "#": ["#.#", "###", "#.#", "###", "#.#"],
        " ": ["..", "..", "..", "..", ".."],
    ]
}
