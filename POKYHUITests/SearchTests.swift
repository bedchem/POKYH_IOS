import XCTest

/// The search: focus, fast typing, leaving and coming back, rotating, no data.
final class SearchTests: AppTestCase {
    private var field: XCUIElement { app.searchFields.firstMatch }

    private func openSheet() {
        let button = app.buttons["Suchen"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no search button")
        tapBlindly(button)
        note("open search")
    }

    private func clear(_ count: Int) {
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
    }

    private func row(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The sheet comes up ready to type, and a result opened and left again keeps the query.
    func testSheetFocusesAndKeepsQueryAcrossDetail() {
        launch()
        waitForTabs()
        openSheet()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "keyboard didn't come up with the sheet")
        app.typeText("Mathe")
        XCTAssertTrue(row("Mathematik").waitForExistence(timeout: 5), "no subject for Mathe")
        XCTAssertTrue(see("FÄCHER", timeout: 1))
        attachScreen("search mathe")
        tapBlindly(row("Mathematik"))
        pause(1)
        assertAlive("in the subject")
        // The back button says "Suchen", which the shared helper leaves alone.
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 2), "no way back")
        back.tap()
        pause(0.8)
        XCTAssertEqual(field.value as? String, "Mathe", "query lost after coming back")
        XCTAssertTrue(row("Mathematik").exists, "results gone after coming back")
    }

    /// Typing on fast ends on what was typed last, never on an earlier word's results.
    func testFastTypingSettlesOnLastQuery() {
        launch()
        waitForTabs()
        openSheet()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        app.typeText("Mathe")
        clear(5)
        app.typeText("Ausflug")
        XCTAssertTrue(row("Ausflug").waitForExistence(timeout: 5), "reminder not found")
        pause(0.5)
        XCTAssertFalse(row("Mathematik").exists, "results of the earlier query stayed")
        clear(7)
        app.typeText("zzqq")
        XCTAssertTrue(see("Nichts gefunden.", timeout: 3), "no empty state")
        attachScreen("nothing found")
        clear(4)
        XCTAssertTrue(see("SEITEN", timeout: 2), "pages didn't come back")
        XCTAssertFalse(see("Nichts gefunden.", timeout: 0.5))
    }

    /// Closed and opened again: an empty field, and the index is there at once.
    func testReopenStartsEmptyAndKeepsIndex() {
        launch()
        waitForTabs()
        openSheet()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        app.typeText("Spaghetti")
        XCTAssertTrue(row("Spaghetti").waitForExistence(timeout: 5))
        // The sheet's own close button, which stays up while typing.
        let close = app.navigationBars["Suchen"].buttons["Schließen"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 2), "no close button while typing")
        close.tap()
        pause(0.8)
        // Everything the index needs is offline now, so what shows comes from before.
        setMode("offline")
        openSheet()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        XCTAssertNotEqual(field.value as? String, "Spaghetti", "the old query came back")
        app.typeText("Spag")
        XCTAssertTrue(row("Spaghetti").waitForExistence(timeout: 1.5), "index lost between two opens")
        clear(4)
        app.typeText("Sprache")
        XCTAssertTrue(row("Sprache ändern").waitForExistence(timeout: 2), "pages missing offline")
        assertAlive("offline")
    }

    /// Turning the phone doesn't lose what was typed.
    func testRotationKeepsQuery() {
        launch()
        waitForTabs()
        openSheet()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        app.typeText("Mathe")
        XCTAssertTrue(row("Mathematik").waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(1.5)
        attachScreen("landscape")
        assertAlive("after rotating")
        if !field.exists { tapBlindly(app.buttons["Suchen"].firstMatch); pause(0.8) }
        XCTAssertEqual(field.value as? String, "Mathe", "query lost on rotation")
        XCUIDevice.shared.orientation = .portrait
        pause(1.2)
        if !field.exists { openSheet(); pause(0.8) }
        XCTAssertEqual(field.value as? String, "Mathe", "query lost rotating back")
    }

    /// As a tab (an account without WebUntis), the query stays while other tabs are open.
    func testTabKeepsQueryAcrossTabs() {
        launch(account: "nurpokyh")
        waitForTabs()
        tap("Suchen")
        pause(0.8)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { field.tap() }
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 2)
        app.typeText("Spaghetti")
        XCTAssertTrue(row("Spaghetti").waitForExistence(timeout: 5))
        attachScreen("tab search")
        tap("Home")
        pause(0.6)
        tap("Suchen")
        pause(0.8)
        XCTAssertEqual(field.value as? String, "Spaghetti", "query lost switching tabs")
        XCTAssertTrue(row("Spaghetti").exists)
    }

    /// Light and dark, for looking at.
    func testLooks() {
        for theme in ["light", "dark"] {
            launch(theme: theme)
            waitForTabs()
            pause(1)
            openSheet()
            pause(1)
            attachScreen("\(theme) open")
            app.typeText("m")
            pause(1.2)
            attachScreen("\(theme) m")
            app.typeText("ath")
            pause(1)
            attachScreen("\(theme) math")
            if let show = Optional(app.buttons["Alle anzeigen"].firstMatch), show.exists {
                tapBlindly(show)
                pause(0.8)
                attachScreen("\(theme) all")
            }
            clear(4)
            app.typeText("qqq")
            pause(1)
            attachScreen("\(theme) nothing")
            app.terminate()
        }
    }
}
