import Foundation
import Testing
@testable import PokyhCore

struct AppKeyTests {
    // RFC 6238 appendix B, SHA-1 seed "12345678901234567890", 8 digits.
    @Test(arguments: [
        (59.0, "94287082"),
        (1_111_111_109.0, "07081804"),
        (1_111_111_111.0, "14050471"),
        (1_234_567_890.0, "89005924"),
        (2_000_000_000.0, "69279037"),
        (20_000_000_000.0, "65353130"),
    ])
    func rfc6238Vectors(time: Double, code: String) {
        let secret = Data("12345678901234567890".utf8)
        #expect(AppKey.totp(secret: secret, at: Date(timeIntervalSince1970: time), digits: 8) == code)
    }

    @Test func base32DecodesTheRfcSeed() {
        // "12345678901234567890" in base32.
        #expect(AppKey.base32("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ") == Data("12345678901234567890".utf8))
        #expect(AppKey.totp("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", at: Date(timeIntervalSince1970: 59)) == "287082")
    }

    @Test func normaliseCleansUpWhatPeoplePaste() {
        #expect(AppKey.normalise("abcd efgh-ijkl mnop==") == "ABCDEFGHIJKLMNOP")
        #expect(AppKey.normalise("too short") == "")
        #expect(AppKey.normalise("ABCDEFGHIJKLMNO1") == "")
    }

    @Test func parsesTheSetSchoolLink() {
        let parsed = AppKey.parse("untis://setschool?url=x.webuntis.com&school=lbs&user=max.muster&key=ABCDEFGHIJKLMNOP")
        #expect(parsed.user == "max.muster")
        #expect(parsed.key == "ABCDEFGHIJKLMNOP")
    }

    @Test func parsesTheLabelledText() {
        let parsed = AppKey.parse("Benutzer: max.muster\nSchlüssel: ABCD EFGH IJKL MNOP\n")
        #expect(parsed.user == "max.muster")
        #expect(parsed.key == "ABCDEFGHIJKLMNOP")
    }

    @Test func aBareKeyIsAKey() {
        #expect(AppKey.parse("  abcdefghijklmnop ").key == "ABCDEFGHIJKLMNOP")
        #expect(AppKey.parse("hello").key == nil)
    }
}

struct StringsTests {
    @Test func everyLanguageHasItsOwnText() {
        #expect(Strings.of(.de).common.retry == "Erneut versuchen")
        #expect(Strings.of(.de).states.failed("Noten", "Timeout") == "Noten konnte nicht geladen werden:\nTimeout")
        #expect(Strings.of(.it).lang == .it)
        #expect(Strings.of(.en).recap.text("bannerNew") != Strings.of(.de).recap.text("bannerNew"))
    }

    @Test func recapFillsPlaceholdersAndFallsBack() {
        let recap = Strings.of(.en).recap
        #expect(recap.text("doesNotExist") == "doesNotExist")
        #expect(!recap.text("bannerNew").isEmpty)
    }

    @Test func systemLanguagePicksOursOrGerman() {
        #expect(Lang.system(preferred: ["it-IT", "en-US"]) == .it)
        #expect(Lang.system(preferred: ["fr-FR", "en-GB"]) == .en)
        #expect(Lang.system(preferred: ["fr-FR"]) == .de)
    }
}
