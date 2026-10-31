import CoreGraphics
import Testing
@testable import PokyhCore

// Expected values come from running Android's ui/pixel code, so a change here means the drawings
// no longer match the other apps.
struct PixelEngineTests {
    private typealias G = PixelGrid

    private func text(_ points: [Pt]) -> String {
        points.map { "\($0.x),\($0.y)" }.joined(separator: ";")
    }

    private func cells(_ s: Sprite) -> [Pt: String] {
        var out: [Pt: String] = [:]
        s.forEachCell { x, y, tone in out[Pt(x, y)] = tone }
        return out
    }

    // MARK: Grids

    @Test func gridPicksTheMarkedPixels() {
        #expect(G.grid(["#.#", ".#."], 2, 1) == [Pt(2, 1), Pt(4, 1), Pt(3, 2)])
        #expect(G.grid(["x#"], ch: "x") == [Pt(0, 0)])
    }

    @Test func rectAndEmptyRect() {
        #expect(G.rect(1, 2, 2, 1) == [Pt(1, 2), Pt(2, 2)])
        #expect(G.rect(0, 0, 0, 5).isEmpty)
        #expect(G.rect(0, 0, -1, 5).isEmpty)
    }

    @Test func roundedCutsCornersStraight() {
        #expect(text(G.rounded(0, 0, 6, 5, 2)) == "2,0;3,0;1,1;2,1;3,1;4,1;0,2;1,2;2,2;3,2;4,2;5,2;1,3;2,3;3,3;4,3;2,4;3,4")
    }

    @Test func softRoundsCorners() {
        #expect(text(G.soft(0, 0, 7, 6, 2.5)) == "1,0;2,0;3,0;4,0;5,0;0,1;1,1;2,1;3,1;4,1;5,1;6,1;0,2;1,2;2,2;3,2;4,2;5,2;6,2;0,3;1,3;2,3;3,3;4,3;5,3;6,3;0,4;1,4;2,4;3,4;4,4;5,4;6,4;1,5;2,5;3,5;4,5;5,5")
    }

    @Test func discAndEllipse() {
        #expect(text(G.disc(5.5, 5.5, 3.6)) == "4,2;5,2;6,2;3,3;4,3;5,3;6,3;7,3;2,4;3,4;4,4;5,4;6,4;7,4;8,4;2,5;3,5;4,5;5,5;6,5;7,5;8,5;2,6;3,6;4,6;5,6;6,6;7,6;8,6;3,7;4,7;5,7;6,7;7,7;4,8;5,8;6,8")
        #expect(G.ellipse(20, 24.5, 22, 4.6).count == 320)
    }

    @Test func limbHasNoDuplicates() {
        let limb = G.limb(7.4, 19.4, 4.4, 23.4, 2.6)
        #expect(limb.count == 47)
        #expect(Set(limb).count == limb.count)
    }

    @Test func lineIsBresenham() {
        #expect(text(G.line(0, 0, 5, 2)) == "0,0;1,0;2,1;3,1;4,2;5,2")
        #expect(text(G.line(2, 2, 0, 0)) == "2,2;1,1;0,0")
    }

    @Test func shiftAndMinus() {
        #expect(G.shift([Pt(1, 1)], 2, -3) == [Pt(3, -2)])
        #expect(G.minus([Pt(0, 0), Pt(1, 0)], [Pt(0, 0)]) == [Pt(1, 0)])
    }

    // MARK: Outline, dither, facing

    @Test func outlineIsWhatTouchesTheShape() {
        let ring = Set(G.outlineOf(G.rect(0, 0, 2, 2)))
        #expect(ring == [Pt(-1, 0), Pt(-1, 1), Pt(0, -1), Pt(0, 2), Pt(1, -1), Pt(1, 2), Pt(2, 0), Pt(2, 1)])
    }

    @Test func outlineSkipsHolesAlreadyFilled() {
        // The corners don't touch, and nothing inside the shape counts.
        let outline = G.outlineOf(G.rect(0, 0, 3, 3))
        #expect(!outline.contains(Pt(-1, -1)))
        #expect(!outline.contains(Pt(1, 1)))
        #expect(outline.count == 12)
    }

    @Test func ditherIsEveryOtherPixelLeftOfZeroToo() {
        #expect(text(G.dither(G.rect(-1, -1, 3, 2), 1)) == "0,-1;-1,0;1,0")
        #expect(text(G.dither(G.rect(-1, -1, 3, 2), 0)) == "-1,-1;1,-1;0,0")
    }

    @Test func facingLooksToTheTopLeft() {
        #expect(abs(G.facing((0, 0), -3, -4) - 0.9974) < 0.0001)
        #expect(abs(G.facing((0, 0), 2, 3) + 0.9974) < 0.0001)
        #expect(G.facing((5.5, 5.5), 5, 5) == 0)
    }

    @Test func jsRoundGoesUpOnHalves() {
        #expect(G.jsRound(0.5) == 1)
        #expect(G.jsRound(-0.5) == 0)
        #expect(G.jsRound(-1.5) == -1)
        #expect(G.jsRound(2.4) == 2)
    }

    // MARK: Sprite

    @Test func massLightsTheTopLeftAndShadesTheRest() {
        let tones = cells(Sprite().mass(G.rect(0, 0, 3, 3), "ac"))
        #expect(tones[Pt(0, 0)] == "ac3")
        #expect(tones[Pt(1, 0)] == "ac3")
        #expect(tones[Pt(0, 1)] == "ac3")
        #expect(tones[Pt(1, 1)] == "ac2")
        #expect(tones[Pt(2, 1)] == "ac1")
        #expect(tones[Pt(1, 2)] == "ac1")
        #expect(tones[Pt(-1, 1)] == "ac0")
        #expect(tones[Pt(3, 1)] == "ac0")
    }

    @Test func massCanLeaveTheOutlineOff() {
        #expect(cells(Sprite().mass(G.rect(0, 0, 2, 2), "ac", outline: false)).count == 4)
    }

    @Test func recolorKeepsTheStepAndOnlyTouchesTheMaterial() {
        let s = Sprite().set(0, 0, "rd3").set(1, 0, "rd").set(2, 0, "gd2")
        s.recolor([Pt(0, 0), Pt(1, 0), Pt(2, 0), Pt(3, 0)], from: "rd", to: "pp")
        #expect(s.get(0, 0) == "pp3")
        #expect(s.get(1, 0) == "rd")
        #expect(s.get(2, 0) == "gd2")
        #expect(s.get(3, 0) == nil)
    }

    @Test func settingNilClearsACell() {
        let s = Sprite().set(0, 0, "ac2").set(0, 0, nil)
        #expect(s.isEmpty)
        #expect(s.bounds() == nil)
        #expect(s.top() == 0)
    }

    @Test func shiftedAndBounds() {
        let s = Sprite().set(1, 2, "ac2").set(3, 5, "ac2").shifted(-2, 1)
        let box = s.bounds()
        #expect(box?.minX == -1 && box?.minY == 3 && box?.maxX == 1 && box?.maxY == 6)
        #expect(s.top() == 3)
    }

    @Test func rowsFollowTheLegend() {
        let s = Sprite().rows(["1.", " 2", "3x"], 0, 0, legend: ["1": "pu1", "2": "pu2", "3": "pu3"])
        #expect(s.get(0, 0) == "pu1")
        #expect(s.get(1, 1) == "pu2")
        #expect(s.get(0, 2) == "pu3")
        #expect(s.get(1, 2) == nil)
    }

    @Test func bitmapIsPerThemeAndKept() throws {
        let s = Sprite().set(2, 3, "pp2").set(3, 3, "sh")
        let light = try #require(s.bitmap(dark: false))
        #expect(light.x == 2 && light.y == 3 && light.w == 2 && light.h == 1)
        #expect(light.image.width == 2 && light.image.height == 1)
        #expect(s.bitmap(dark: false)?.image === light.image)
        #expect(s.bitmap(dark: true)?.image !== light.image)
        #expect(Sprite().bitmap(dark: false) == nil)
    }

    @Test func premultiplies() {
        #expect(PixelBitmap.premultiplied(0xFF10_2030) == 0xFF10_2030)
        #expect(PixelBitmap.premultiplied(0x80FF_0000) == 0x8080_0000)
        #expect(PixelBitmap.premultiplied(0x00FF_FFFF) == 0)
    }

    // MARK: Text

    @Test func textMeasuresAndFallsBack() {
        #expect(G.textPixels("HI").width == 7)
        #expect(G.textPixels("").width == 0)
        // Accents go, ß doubles, what the font lacks is a question mark.
        #expect(G.textPixels("é").points == G.textPixels("E").points)
        #expect(G.textPixels("ß").points == G.textPixels("SS").points)
        #expect(G.textPixels("§").points == G.textPixels("?").points)
    }

    @Test func wrapBreaksAtSeparatorsAndCuts() {
        #expect(G.wrapText("Hallo, Anna!", 66) == ["Hallo, Anna!"])
        #expect(G.wrapText("Hallo, anna-maria.mustermann!", 66) == ["Hallo, anna-", "maria.mustermann!"])
        #expect(G.wrapText("   ", 66) == [""])
        #expect(G.wrapText("", 66) == [""])
        let long = G.wrapText("a_very_long_username_without_any_break_at_all_really", 30)
        #expect(long.count == 3)
        #expect(long.last?.hasSuffix("…") == true)
        for line in long { #expect(G.textPixels(line).width <= 30) }
    }

    // MARK: Palette

    @Test func tonesMatchAndroid() {
        let light = PixelPalette.tones(dark: false)
        let dark = PixelPalette.tones(dark: true)
        #expect(light["ac0"] == 0xFF30_2C6F)
        #expect(light["ac1"] == 0xFF50_4EBC)
        #expect(light["ac2"] == 0xFF63_66F1)
        #expect(light["ac3"] == 0xFF98_A2F2)
        #expect(light["ac4"] == 0xFFD5_D7ED)
        #expect(light["gd1"] == 0xFFDB_8E0B)
        #expect(light["pp0"] == 0xFFBD_B3A4)
        #expect(dark["pp0"] == 0xFF2A_2830)
        #expect(dark["pp2"] == 0xFFDC_D8D0)
        #expect(light["sh"] == 0x2930_1E46)
        #expect(dark["sh"] == 0x6100_0000)
        #expect(light["gl"] == 0x618C_BEFA)
        #expect(dark["gl"] == 0x388C_BEFA)
        // The accent doesn't change with the theme.
        #expect(light["ac2"] == dark["ac2"])
    }

    @Test func mixesInOklab() {
        #expect(PixelPalette.mixOklab(0xFF63_66F1, 0xFF14_0D2B, 0.62) == 0xFF30_2C6F)
        #expect(PixelPalette.mixOklab(0xFF63_66F1, 0xFF14_0D2B, 0) == 0xFF63_66F1)
    }

    // MARK: Animation

    @Test func oneStepHoldsEachKeyframe() {
        let t = PxTrack(1, [(0, 0), (0.5, 10), (1, 20)])
        #expect(t.at(0) == 0)
        #expect(t.at(0.49) == 0)
        #expect(t.at(0.5) == 10)
        #expect(t.at(0.99) == 10)
        #expect(t.at(1) == 20)
    }

    @Test func stepsJumpBetweenKeyframes() {
        let t = PxTrack(4, [(0, 0), (1, 360)])
        #expect(t.at(0.1) == 0)
        #expect(t.at(0.25) == 90)
        #expect(t.at(0.74) == 180)
        #expect(t.at(0.8) == 270)
    }

    @Test func infiniteAnimationsLoop() {
        var a = PixelFrame(), b = PixelFrame()
        Px.breathe.apply(0, reduced: false, to: &a)
        Px.breathe.apply(1800, reduced: false, to: &b)
        #expect(a.ty == b.ty)
        var c = PixelFrame()
        Px.breathe.apply(900, reduced: false, to: &c)
        #expect(c.ty == 1)
    }

    @Test func oneShotsEndWhereTheyFill() {
        var hop = PixelFrame()
        Px.msHop.apply(10_000, reduced: false, to: &hop)
        #expect(hop.ty == 0)
        #expect(hop.alpha == 1)
        var pop = PixelFrame()
        Px.pop.apply(-50, reduced: false, to: &pop)
        #expect(pop.alpha == 0)
        #expect(pop.ty == 2)
        var popped = PixelFrame()
        Px.pop.apply(10_000, reduced: false, to: &popped)
        #expect(popped.alpha == 1)
        #expect(popped.ty == 0)
    }

    @Test func aNegativeDelayStartsPartWayThrough() {
        var a = PixelFrame(), b = PixelFrame()
        Px.snow.delayed(-1200).apply(0, reduced: false, to: &a)
        Px.snow.apply(1200, reduced: false, to: &b)
        #expect(a.ty == b.ty)
        #expect(a.alpha == b.alpha)
    }

    @Test func reduceMotionShowsTheStillFrame() {
        var lens = PixelFrame()
        Px.lens.apply(1234, reduced: true, to: &lens)
        #expect(lens.tx == 5 && lens.ty == 4)
        var spark = PixelFrame()
        Px.spark.apply(1234, reduced: true, to: &spark)
        #expect(spark.alpha == 1)
        var blink = PixelFrame()
        Px.msBlink.apply(1234, reduced: true, to: &blink)
        #expect(blink.alpha == 0)
    }
}
