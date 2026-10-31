import PokyhCore
import Synchronization
import SwiftUI

// Small pixel icons, 16 × 16, drawn like the scenes and meant for three times their size so every
// pixel stays square. The settings use them beside the account's e-mail, password, two-factor
// sign-in and devices; `qr` is for signing in on a computer with the phone.

public enum PixelIconName: CaseIterable, Sendable {
    case mail, key, shieldOn, shieldOff, fingerprint, devices, qr

    public var scene: PixelScene { PixelIcons.scene(self) }
}

public struct PixelIcon: View {
    let name: PixelIconName
    let size: CGFloat

    public init(_ name: PixelIconName, size: CGFloat = 48) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        PixelArt(scene: name.scene).frame(width: size)
    }
}

enum PixelIcons: PixelDrawing {
    private static let size = 16
    private static let built = Mutex<[PixelIconName: PixelScene]>([:])

    static func scene(_ name: PixelIconName) -> PixelScene {
        built.withLock { scenes in
            if let done = scenes[name] { return done }
            let made = PixelScene(w: size, h: size, layers: [PixelLayer(sprite(name))])
            scenes[name] = made
            return made
        }
    }

    private static func sprite(_ name: PixelIconName) -> Sprite {
        switch name {
        case .mail: mail()
        case .key: key()
        case .shieldOn: shieldOn()
        case .shieldOff: shieldOff()
        case .fingerprint: fingerprint()
        case .devices: devices()
        case .qr: qr()
        }
    }

    // An envelope seen from the back, its flap closed with a red seal.
    private static func mail() -> Sprite {
        let s = Sprite().mass(rect(1, 3, 14, 10), "pp", deep: true)
        s.fill([p(1, 3), p(2, 4), p(3, 5), p(4, 6), p(5, 7), p(6, 8), p(14, 3), p(13, 4), p(12, 5), p(11, 6), p(10, 7), p(9, 8)], "pp0")
        s.fill([p(1, 12), p(2, 11), p(3, 10), p(14, 12), p(13, 11), p(12, 10)], "pp1")
        s.mass(rect(7, 8, 2, 2), "rd", outline: false)
        return s.set(7, 8, "rd3")
    }

    // A gold key, its bow a ring, two teeth.
    private static func key() -> Sprite {
        let bow = minus(disc(4.5, 8.0, 3.7), disc(4.5, 8.0, 1.6))
        return Sprite().mass(bow + rect(8, 7, 6, 2) + rect(11, 9, 1, 2) + rect(13, 9, 1, 3), "gd", deep: true)
            .fill([p(3, 5), p(2, 6)], "gd4")
    }

    private static let shield = grid([
        "############",
        "############",
        "############",
        "############",
        "############",
        "############",
        ".##########.",
        ".##########.",
        "..########..",
        "..########..",
        "...######...",
        "....####....",
        ".....##.....",
    ], 2, 1)

    // A green shield with a tick: two-factor sign-in on.
    private static func shieldOn() -> Sprite {
        let tick = [p(4, 6), p(5, 7), p(6, 8), p(7, 7), p(8, 6), p(9, 5), p(10, 4), p(11, 3)]
        return Sprite().mass(shield, "gn", deep: true).fill(tick + tick.map { p($0.x, $0.y + 1) }, "pp3")
    }

    // A gold shield with an exclamation mark: two-factor sign-in off.
    private static func shieldOff() -> Sprite {
        Sprite().mass(shield, "gd", deep: true).fill(rect(7, 3, 2, 5) + rect(7, 9, 2, 2), "gd0")
    }

    // Light ridges on an indigo tile: signing in with the device's lock.
    private static func fingerprint() -> Sprite {
        let ridges = grid([
            "..######..",
            ".#......#.",
            "#..####..#",
            "#.#....#.#",
            "#.#.##.#.#",
            "#.#.#..#.#",
            "#.#.#.#..#",
            "..#.#.#.#.",
            "#...#.#.#.",
            "....#...#.",
        ], 3, 3)
        return Sprite().mass(rounded(1, 1, 14, 14, 3), "ac", deep: true).fill(ridges, "pp3")
    }

    // A screen on its stand, a phone in front of it.
    private static func devices() -> Sprite {
        let s = Sprite().mass(rect(1, 2, 11, 8) + rect(5, 10, 3, 1) + rect(3, 11, 7, 1), "st")
        s.fill(rect(2, 3, 9, 6), "wt2").fill([p(3, 4), p(4, 4), p(3, 5)], "wt4")
        s.mass(rounded(10, 6, 5, 9, 1), "ac", deep: true)
        return s.fill(rect(11, 7, 3, 6), "wt2").set(11, 7, "wt4").set(12, 13, "ac3")
    }

    // A code on a white card, its three corner squares.
    private static func qr() -> Sprite {
        let code = grid([
            "####..#.####",
            "#..#.#..#..#",
            "#..#..#.#..#",
            "####.#..####",
            "............",
            "..#.##.#.#..",
            "#.#..#..##.#",
            "............",
            "####.#.#.#..",
            "#..#..##..#.",
            "#..#.#..##.#",
            "####..#.#.##",
        ], 2, 2)
        return Sprite().mass(rounded(1, 1, 14, 14, 1), "pp", deep: true).fill(code, "ik2")
    }
}
