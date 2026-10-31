import Foundation
import Testing
@testable import PokyhCore

struct TwoFactorCodeTests {
    @Test func keepsWhatAuthenticatorAppsShow() {
        #expect(TwoFactorCode.input("123 456") == "123 456")
        #expect(TwoFactorCode.input("12a3-45b6") == "123456")
        #expect(TwoFactorCode.input("1234567890") == "1234567")
        #expect(TwoFactorCode.digits("123 456") == "123456")
    }

    @Test func onlySixDigitsAreACode() {
        #expect(TwoFactorCode.isComplete("123456"))
        #expect(TwoFactorCode.isComplete("123 456"))
        #expect(!TwoFactorCode.isComplete("12345"))
        #expect(!TwoFactorCode.isComplete("1234567"))
    }

    @Test func otherScriptsDigitsDontCount() {
        // A digit WebUntis wouldn't read as one.
        #expect(TwoFactorCode.digits("١٢٣٤٥٦") == "")
        #expect(!TwoFactorCode.isComplete("١٢٣٤٥٦"))
    }
}

struct FormLoginAnswerTests {
    private func parse(_ json: String, status: Int = 200, sentCode: Bool = false) -> FormLoginAnswer {
        FormLoginAnswer.parse(Data(json.utf8), status: status, sentCode: sentCode)
    }

    @Test func aPasswordAloneMeetsTheCodeQuestion() {
        #expect(parse(#"{"state":"TOKEN_REQUIRED"}"#) == .codeRequired)
    }

    @Test func aCodeThatWasSentAndAskedForAgainWasWrong() {
        #expect(parse(#"{"state":"TOKEN_REQUIRED"}"#, sentCode: true) == .codeWrong)
        #expect(parse(#"{"state":"TOKEN_REQUIRED","invalidToken":true}"#) == .codeWrong)
    }

    @Test func theOtherAnswers() {
        #expect(parse(#"{"state":"SUCCESS"}"#, sentCode: true) == .ok)
        #expect(parse(#"{"state":"LOGIN_ERROR"}"#) == .badCredentials)
        #expect(parse(#"{"state":"SOMETHING_NEW"}"#) == .refused)
    }

    @Test func whatIsntJsonIsTheServerOrARefusal() {
        #expect(parse("<html>", status: 502) == .unavailable)
        #expect(parse("<html>", status: 302) == .refused)
        #expect(parse("[1]", status: 200) == .refused)
    }

    @Test func aPasswordSurvivesTheForm() throws {
        let body = FormLoginAnswer.formBody([("j_username", "a b"), ("j_password", "p&w=1+2%ü"), ("token", "123456")])
        let text = String(decoding: body, as: UTF8.self)
        #expect(text == "j_username=a%20b&j_password=p%26w%3D1%2B2%25%C3%BC&token=123456")
        let read = try #require(URLComponents(string: "https://x/?\(text)")?.queryItems)
        #expect(read.first { $0.name == "j_password" }?.value == "p&w=1+2%ü")
    }
}

struct WebSignInCodeTests {
    private let code = "abcDEF123_-abcDEF123_-abcDEF"

    @Test func theTextInTheCode() {
        #expect(WebSignInCode.of("POKYH-LOGIN:\(code)", host: nil) == code)
        #expect(WebSignInCode.of("  pokyh-login:\(code)\n", host: "pokyh.com") == code)
    }

    @Test func aLinkToTheWebsite() {
        #expect(WebSignInCode.of("https://pokyh.com/l/\(code)", host: "pokyh.com") == code)
        #expect(WebSignInCode.of("https://www.POKYH.com/l/\(code)/?from=qr#x", host: "pokyh.com") == code)
        #expect(WebSignInCode.of("https://pokyh.com/l/\(code)", host: "www.pokyh.com") == code)
    }

    @Test(arguments: [
        "https://pokyh.com.evil.example/l/CODE",
        "https://evilpokyh.com/l/CODE",
        "https://pokyh.com@evil.example/l/CODE",
        "https://pokyh.com:8443/l/CODE",
        "http://pokyh.com/l/CODE",
        "https://pokyh.com/x/CODE",
        "https://pokyh.com/l/CODE/more",
        "CODE",
        "",
    ])
    func whatIsntOurs(text: String) {
        #expect(WebSignInCode.of(text.replacingOccurrences(of: "CODE", with: code), host: "pokyh.com") == nil)
    }

    @Test func aCodeHasItsShape() {
        #expect(WebSignInCode.of("POKYH-LOGIN:short", host: nil) == nil)
        #expect(WebSignInCode.of("POKYH-LOGIN:\(code)!", host: nil) == nil)
        #expect(WebSignInCode.of("POKYH-LOGIN:" + String(repeating: "a", count: 65), host: nil) == nil)
        #expect(WebSignInCode.of("https://pokyh.com/l/\(code)", host: nil) == nil)
    }
}

struct DeviceLabelsTests {
    @Test func aDeviceIsNamedByWhatIsKnown() {
        #expect(DeviceLabels.name(model: "iPhone17,1", os: "iOS 26", browser: "", unknown: "?") == "iPhone17,1 · iOS 26")
        #expect(DeviceLabels.name(model: "", os: "macOS", browser: "Safari", unknown: "?") == "Safari · macOS")
        #expect(DeviceLabels.name(model: "Pixel", os: "Pixel", browser: " ", unknown: "?") == "Pixel")
        #expect(DeviceLabels.name(model: "", os: "", browser: "", unknown: "?") == "?")
    }

    @Test func aPlaceLeavesOutWhatIsMissing() {
        #expect(DeviceLabels.place(city: "Brixen", region: "Südtirol", country: "IT", unknown: "?") == "Brixen, Südtirol, IT")
        #expect(DeviceLabels.place(city: nil, region: " ", country: "IT", unknown: "?") == "IT")
        #expect(DeviceLabels.place(city: "IT", region: nil, country: "IT", unknown: "?") == "IT")
        #expect(DeviceLabels.place(city: nil, region: nil, country: "", unknown: "?") == "?")
    }

    @Test func timesShowInTheLocalZone() throws {
        let rome = try #require(TimeZone(identifier: "Europe/Rome"))
        #expect(DeviceLabels.when("2026-10-31T07:15:00.000Z", lang: .en, timeZone: rome) == "31 Oct 2026, 08:15")
        #expect(DeviceLabels.when("2026-10-31T07:15:00Z", lang: .de, timeZone: rome).hasPrefix("31. Okt"))
        #expect(DeviceLabels.when("2026-10-31T07:15:00Z", lang: .de, timeZone: rome).hasSuffix("2026, 08:15"))
    }

    @Test func whatCantBeReadShowsAsItCame() {
        #expect(DeviceLabels.when("2026-10-31T07:15:99", lang: .de) == "2026-10-31 07:15")
        #expect(DeviceLabels.when("", lang: .de) == "")
    }
}
