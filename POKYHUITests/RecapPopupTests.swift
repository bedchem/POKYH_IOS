import XCTest

/// Announcement popups and the recap. The stub answers both like the backend: /recaps only with a
/// token, a school's own popup only with the account's session, every date with milliseconds.
final class RecapPopupTests: AppTestCase {
    private let both = ["POKYH_STUB_POPUPS": "1", "POKYH_STUB_RECAP": "1"]

    /// Signed in by hand: the popups first, the recap opens by itself once they're closed, then it
    /// waits on Home.
    func testPopupsThenRecapAfterSigningIn() {
        launch(theme: "light", env: both)
        waitForTabs()
        closePopups([("Neue Mensa-Zeiten", "Tabletts"), ("Skitag", "Busbahnhof")], shots: "light")
        watchRecap(shots: "light")
        openAgainFromHome(shots: "light")
    }

    /// How the app usually starts: Face ID, the stored copy at once and the sign-in behind it. The
    /// token comes a moment after Home, and both still have to turn up, the school's popup included.
    func testPopupsThenRecapAfterUnlocking() {
        launch()
        waitForTabs()
        pause(1)
        app.terminate()

        launch(account: nil, reset: false, theme: "dark", env: both)
        waitForTabs(timeout: 20)
        closePopups([("Neue Mensa-Zeiten", "Tabletts"), ("Skitag", "Busbahnhof")], shots: "dark")
        watchRecap(shots: "dark")
        openAgainFromHome(shots: "dark")
    }

    // ── Steps ────────────────────────────────────────────────────────────────

    /// Each popup in turn: its title, its content laid out and readable, closed once the countdown
    /// let go. `popups` pairs a title with a few words of its content.
    private func closePopups(_ popups: [(title: String, says: String)], shots: String) {
        for (i, popup) in popups.enumerated() {
            XCTAssertTrue(see(popup.title, timeout: 15), "popup \(popup.title) never showed")
            // The countdown waits for the content, however long the page takes to load. A simulator
            // that was just created starts WebKit slowly the first time, hence the generous wait.
            XCTAssertTrue(see(popup.says, timeout: 15), "the content of \(popup.title) isn't there")
            let content = app.webViews.firstMatch
            XCTAssertGreaterThan(content.exists ? content.frame.height : 0, 20, "the content of \(popup.title) came out flat")
            if i == 0 { shoot("popup-\(shots)") }
            let last = i == popups.count - 1
            let button = app.buttons[last ? "Fertig" : "Weiter"].firstMatch
            // Locked for the first three seconds.
            XCTAssertTrue(becomes(button, "isEnabled == true", timeout: 8), "\(popup.title) never let go")
            if !last { shoot("popup-stack-\(shots)") }
            button.tap()
            pause(0.6)
        }
        let lastTitle = app.staticTexts[popups.last?.title ?? ""].firstMatch
        XCTAssertTrue(becomes(lastTitle, "exists == false", timeout: 4), "the popups didn't close")
    }

    /// Opens by itself, steps through every page to the summary and closes with "Fertig".
    private func watchRecap(shots: String) {
        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Los geht")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 25), "the recap never opened")
        shoot("recap-intro-\(shots)")
        start.tap()
        pause(0.8)
        var pages = 1
        while pages < 40 {
            let done = app.buttons["Fertig"].firstMatch
            if done.exists {
                shoot("recap-summary-\(shots)")
                let share = app.buttons["Teilen"].firstMatch
                XCTAssertTrue(share.exists, "no share on the summary")
                share.tap()
                // The poster to keep, in the sheet; only it has a navigation bar here.
                let closePoster = app.navigationBars.buttons.firstMatch
                if closePoster.waitForExistence(timeout: 5) {
                    pause(1.5)
                    shoot("recap-poster-\(shots)")
                    // The picture goes to the system's share sheet, which offers to keep it.
                    let shareCard = app.buttons.matching(NSPredicate(format: "label == %@", "Teilen")).allElementsBoundByIndex
                        .last { $0.isHittable }
                    XCTAssertNotNil(shareCard, "no share button on the poster")
                    shareCard?.tap()
                    let keep = app.descendants(matching: .any).matching(NSPredicate(
                        format: "label IN %@", ["Bild sichern", "Kopieren", "In „Dateien“ sichern", "Save Image", "Copy"])).firstMatch
                    XCTAssertTrue(keep.waitForExistence(timeout: 8), "the share sheet didn't come up with the picture")
                    shoot("recap-share-\(shots)")
                    // A sheet on the phone, a popover on the iPad: a tap on the poster sheet's title
                    // closes either and leaves the poster sheet up.
                    app.staticTexts["Anpassen"].firstMatch.tap()
                    pause(1)
                    XCTAssertFalse(keep.exists, "the share sheet didn't go away")
                    closePoster.tap()
                    pause(0.8)
                } else {
                    XCTFail("the poster never opened")
                }
                done.tap()
                break
            }
            let next = app.buttons["Weiter"].firstMatch
            guard next.waitForExistence(timeout: 3) else {
                XCTFail("stuck on page \(pages) of the recap")
                attachScreen("recap stuck")
                return
            }
            if pages == 2 { shoot("recap-page-\(shots)") }
            next.tap()
            pages += 1
            pause(0.5)
        }
        XCTAssertGreaterThan(pages, 4, "hardly any pages: the figures didn't load")
        XCTAssertTrue(becomes(app.buttons["Fertig"].firstMatch, "exists == false", timeout: 4), "the recap didn't close")
        assertAlive("after the recap")
    }

    /// Watched to the end, the banner on Home says so and opens it again.
    private func openAgainFromHome(shots: String) {
        XCTAssertTrue(see("Nochmal ansehen", timeout: 8), "no recap banner on Home")
        shoot("home-banner-\(shots)")
        tapStarting("Dein Rückblick", timeout: 3)
        XCTAssertTrue(see("Los geht", timeout: 15), "the banner didn't open the recap")
        tap("Schließen")
        XCTAssertTrue(see("Nochmal ansehen", timeout: 5))
        assertAlive()
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private func becomes(_ element: XCUIElement, _ format: String, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)], timeout: timeout) == .completed
    }

    /// Kept beside the logs as well, to look at without opening the result bundle.
    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "\(Self.outputDir)/\(name).png"))
        attachScreen(name)
    }
}
