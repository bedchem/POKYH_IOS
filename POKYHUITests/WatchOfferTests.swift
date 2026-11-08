import XCTest

/// The question when a watch shows up. The test runs have no watch, so a debug switch brings it.
final class WatchOfferTests: AppTestCase {
    private func shot(_ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(Self.outputDir)/watch-offer-\(name).png"))
    }

    private func launchOffering(_ offer: String, language: String = "de", fresh: Bool = true) {
        var arguments = ["-POKYHWatchOffer", offer]
        if fresh { arguments += ["-pokyh_watch_offer_forced_seen", "NO"] }
        // A reset would forget the answer too.
        launch(reset: fresh, arguments: arguments, language: language)
        if language == "de" { waitForTabs() }
    }

    func testConnectIsAskedOnceAndNotNowCloses() {
        launchOffering("connect")
        XCTAssertTrue(see("POKYH auf der Apple Watch", timeout: 10), "the question never came")
        shot("connect-de")
        XCTAssertTrue(tap("Nicht jetzt"))
        pause(1)
        XCTAssertFalse(see("POKYH auf der Apple Watch", timeout: 1), "still up after Not now")
        assertAlive("after Not now")

        // Answered once, not asked again.
        app.terminate()
        launchOffering("connect", fresh: false)
        pause(4)
        XCTAssertFalse(see("POKYH auf der Apple Watch", timeout: 1), "asked a second time")
    }

    func testInstallHint() {
        launchOffering("install")
        XCTAssertTrue(see("Verfügbare Apps", timeout: 10), "no install hint")
        shot("install-de")
        XCTAssertTrue(tap("OK"))
        pause(1)
        XCTAssertFalse(see("Verfügbare Apps", timeout: 1))
    }

    func testItalianAndEnglish() {
        launchOffering("connect", language: "it")
        XCTAssertTrue(see("POKYH su Apple Watch", timeout: 10))
        XCTAssertTrue(element("Non ora").exists)
        shot("connect-it")
        app.terminate()
        launchOffering("connect", language: "en")
        XCTAssertTrue(see("POKYH on Apple Watch", timeout: 10))
        XCTAssertTrue(element("Not now").exists)
        shot("connect-en")
    }
}
