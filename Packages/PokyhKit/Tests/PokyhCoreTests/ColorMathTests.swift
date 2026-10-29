import Testing
@testable import PokyhCore

// Expected values worked out with the Kotlin implementation (Palette.kt), which the web shares.
struct ColorMathTests {
    @Test func jsHashMatchesTheWeb() {
        #expect(ColorMath.jsHash("") == 0)
        #expect(ColorMath.jsHash("a") == 97)
        #expect(ColorMath.jsHash("ab") == 3105)
        #expect(ColorMath.jsHash("Mathematik") == abs(Int(Int32(truncatingIfNeeded: jsHashReference("Mathematik")))))
        // Overflows wrap like Int32 in JS/Kotlin.
        #expect(ColorMath.jsHash("Wirtschaftsgeografie und Recht") == abs(Int(Int32(truncatingIfNeeded: jsHashReference("Wirtschaftsgeografie und Recht")))))
    }

    @Test func fixedSubjectsWinOverTheHash() {
        #expect(IdentityColors.subject("D") == RGB(hex: 0x5AA0E8))
        #expect(IdentityColors.subject("M") == RGB(hex: 0x4ED87A))
    }

    @Test func hsvRoundTripsTheHue() {
        for hue in stride(from: 0.0, to: 360.0, by: 15.0) {
            let color = RGB.hsv(hue, 0.5, 0.62)
            #expect(abs(color.hueDegrees - hue) < 0.01)
        }
    }

    @Test func gradeRamp() {
        #expect(IdentityColors.grade(6.2) == RGB(hex: 0xF97316))
        let ten = IdentityColors.grade(10)
        #expect(abs(ten.green - 128.0 / 255) < 0.0001)
        let one = IdentityColors.grade(1)
        #expect(abs(one.red - 153.0 / 255) < 0.0001)
    }

    @Test func subjectHuesAreStableAndDistinct() {
        let hues = SubjectHues()
        hues.register(["M", "D", "ENGL", "IT", "Bew.Sport", "D"])
        let assigned = ["M", "D", "ENGL", "IT", "Bew.Sport"].map { hues.hue(for: $0) }
        #expect(Set(assigned).count == assigned.count)

        // Order in which the cells show up must not matter.
        let other = SubjectHues()
        other.register(["Bew.Sport", "IT", "ENGL", "D", "M"])
        #expect(["M", "D", "ENGL", "IT", "Bew.Sport"].map { other.hue(for: $0) } == assigned)
    }

    // Straight transcription of the JS loop with 64-bit math, truncated at the end of each step.
    private func jsHashReference(_ s: String) -> Int64 {
        var hash: Int64 = 0
        for unit in s.utf16 {
            hash = (hash << 5) - hash + Int64(unit)
            hash = Int64(Int32(truncatingIfNeeded: hash))
        }
        return hash
    }
}
