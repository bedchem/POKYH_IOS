import XCTest

/// Good data, every way through the app: the accounts, the screens, and how it's left and come back to.
final class JourneyTests: AppTestCase {
    func testSignInWithSchoolSearch() {
        launch(account: nil)
        signIn(user: "anna", password: "richtig")
        waitForTabs()
        assertAlive()
    }

    func testWrongPasswordThenRight() {
        launch(account: nil)
        signIn(user: "anna", password: "falsch")
        pause(2)
        assertAlive("after a wrong password")
        let password = app.secureTextFields.firstMatch
        if password.waitForExistence(timeout: 3) {
            password.tap()
            password.press(forDuration: 0.1)
            password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
            password.typeText("richtig")
            app.buttons.matching(NSPredicate(format: "label == %@", "Anmelden")).allElementsBoundByIndex.last?.tap()
        }
        waitForTabs()
    }

    func testSchoolSearchAnswers() {
        launch(account: nil)
        let field = app.textFields.firstMatch
        for query in ["ab", "viele", "limit", "keine", "Teststadt"] {
            guard field.waitForExistence(timeout: 3) else { break }
            typeInto(field, query)
            pause(0.8)
            assertAlive("searching \(query)")
            field.tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: query.count))
        }
    }

    func testTwoFactor() {
        launch(account: nil)
        signIn(user: "zweifa", password: "richtig")
        let code = app.textFields["Code"].firstMatch
        XCTAssertTrue(see("Code", timeout: 8), "the code prompt never came")
        assertAlive("with the code prompt up")
        if code.waitForExistence(timeout: 2) { typeInto(code, "111111") } else { app.typeText("111111") }
        pause(1)
        confirmCode()
        pause(1.5)
        assertAlive("after a wrong code")
        // The code field again, not the first field on screen: that's the user name behind the
        // card, and tapping it moved the card away from under the next tap.
        typeInto(code, String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "123456")
        pause(0.5)
        confirmCode()
        waitForTabs()
    }

    func testPokyhOnlyAccount() {
        launch(account: nil)
        signIn(user: "nurpokyh", password: "richtig")
        waitForTabs()
        XCTAssertFalse(element("Noten").exists, "a POKYH-only account has no grades tab")
        crawl(budget: 60, account: "nurpokyh", tabs: ["Home", "Schule", "Mensa"])
    }

    func testEverythingAsStudent() {
        launch()
        waitForTabs()
        crawl(budget: budget(300))
    }

    func testEverythingAsParent() {
        launch(account: "eltern")
        waitForTabs()
        crawl(budget: budget(150), account: "eltern")
    }

    func testEverythingInDarkMode() {
        launch(theme: "dark")
        waitForTabs()
        crawl(budget: budget(120))
    }

    func testRecapStory() {
        launch(env: ["POKYH_STUB_RECAP": "1"])
        // It opens by itself over everything.
        XCTAssertTrue(see("Los geht", timeout: 10), "the recap never opened")
        tapBlindly(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Los geht")).firstMatch)
        pause(1)
        for _ in 0..<20 where app.state == .runningForeground {
            tapBlindly(app.buttons["Weiter"].firstMatch)
            pause(0.2)
        }
        assertAlive("at the end of the recap")
        // The poster at the end.
        tap("Teilen", timeout: 1)
        pause(1)
        assertAlive("on the recap's poster")
        leaveEverything()
        tap("Schließen", timeout: 1)
        assertAlive("after closing the recap")
    }

    func testPopupsAndPrivacyNotice() {
        launch(env: ["POKYH_STUB_POPUPS": "1", "POKYH_STUB_PRIVACY": "1"])
        waitForTabs()
        pause(6)
        assertAlive("with the popups up")
        tap("Weiter", timeout: 3)
        pause(3.5)
        tap("Weiter", timeout: 3)
        pause(3.5)
        tap("Schließen", timeout: 2)
        tap("Verstanden", timeout: 2)
        assertAlive()
    }

    func testAccountsAddSwitchRemoveSignOut() {
        launch()
        waitForTabs()
        openProfile()
        // A tap at the row's spot can land while the sheet still settles; XCTest's own waits for that.
        let add = app.buttons["Konto hinzufügen"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        pause(0.5)
        signIn(user: "eltern", password: "richtig")
        pause(2.5)
        assertAlive("after adding an account")
        waitForTabs()
        openProfile()
        // Back to the first account. It may need a moment to swap the whole tab tree.
        tap("anna", timeout: 3)
        pause(2.5)
        assertAlive("after switching")
        waitForTabs()
        openProfile()
        tap("Abmelden", timeout: 3)
        tap("Abmelden", timeout: 2)
        pause(1.5)
        assertAlive("after signing out")
    }

    func testRemoveAccountFromProfile() {
        launch()
        waitForTabs()
        openProfile()
        // Long press gives the row's menu.
        let row = element("anna")
        if row.waitForExistence(timeout: 3) {
            row.press(forDuration: 1.0)
            pause(0.5)
            tap("Entfernen", timeout: 2)
            tap("Entfernen", timeout: 2)
            pause(1.5)
        }
        assertAlive("after removing the account")
    }

    func testLockBackgroundForeground() {
        launch(env: ["POKYH_STUB_AUTOLOCK": "1"])
        waitForTabs()
        for round in 0..<4 {
            tap(tabs[round % tabs.count])
            XCUIDevice.shared.press(.home)
            pause(2.5)
            app.activate()
            pause(1.5)
            assertAlive("back from the background, round \(round)")
            waitForTabs(timeout: 10)
        }
    }

    func testBackgroundWithSheetOpen() {
        launch(env: ["POKYH_STUB_AUTOLOCK": "1"])
        waitForTabs()
        openProfile()
        tap("Einstellungen", timeout: 2)
        XCUIDevice.shared.press(.home)
        pause(2.5)
        app.activate()
        pause(2)
        assertAlive("back with a sheet open")
        waitForTabs(timeout: 10)
    }

    func testFailedFaceID() {
        launch(account: "anna", env: ["POKYH_STUB_BIOMETRY": "fail", "POKYH_STUB_AUTOLOCK": "1"])
        waitForTabs()
        XCUIDevice.shared.press(.home)
        pause(2.5)
        app.activate()
        pause(2)
        assertAlive("on the lock screen")
        tap("Passwort", timeout: 1)
        leaveEverything()
        assertAlive()
    }

    func testRapidTabSwitching() {
        launch()
        waitForTabs()
        for i in 0..<40 {
            let target = element(tabs[(i * 3) % tabs.count])
            tapBlindly(target)
            if i % 8 == 0 { assertAlive("switching tabs") }
        }
        assertAlive("after switching tabs")
    }

    func testPullToRefreshWhileNavigatingAway() {
        launch(mode: "slow")
        waitForTabs(timeout: 25)
        for name in tabs {
            tap(name)
            pause(0.2)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
            // Gone before the slow answer comes back.
            tapBlindly(element(tabs[(tabs.firstIndex(of: name)! + 2) % tabs.count]))
            pause(0.2)
            assertAlive("refreshing on \(name)")
        }
        setMode("good")
        for tile in Self.hubTiles.prefix(4) {
            tap("Schule")
            setMode("slow")
            tapStarting(tile, timeout: 2)
            pause(0.1)
            backOrClose()
            pause(0.1)
        }
        pause(3)
        assertAlive("after leaving screens mid-load")
    }

    func testRotationEverywhere() {
        launch()
        waitForTabs()
        let turns: [UIDeviceOrientation] = [.landscapeLeft, .portrait, .landscapeRight, .portrait]
        for (i, name) in tabs.enumerated() {
            tap(name)
            XCUIDevice.shared.orientation = turns[i % turns.count]
            pause(0.8)
            assertAlive("turning on \(name)")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(0.6)
        crawl(budget: budget(50))
        XCUIDevice.shared.orientation = .portrait
    }

    func testHomeArrangeMode() {
        launch()
        waitForTabs()
        tap("Home")
        pause(1)
        // Further down the page.
        for _ in 0..<4 where !element("Startseite anordnen").exists { app.swipeUp() }
        if tap("Startseite anordnen", timeout: 2) {
            pause(0.6)
            let removes = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "entfernen")).allElementsBoundByIndex.prefix(2)
            for remove in removes { tapBlindly(remove); pause(0.3) }
            assertAlive("arranging")
            let drag = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "verschieben")).firstMatch
            if drag.exists { drag.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))) }
            tap("Fertig", timeout: 2)
            assertAlive("after arranging")
        }
    }

    func testComposeReportEditDelete() {
        launch()
        waitForTabs()
        // A to-do made, ticked and opened.
        tap("Schule")
        tapStarting("Eigene To-dos")
        pause(1)
        openRows("To-dos", limit: 3, mode: "good", account: "anna")
        tap("Neu", timeout: 1)
        pause(0.6)
        typeIfPossible("Neues To-do")
        tap("Speichern", timeout: 1)
        pause(0.6)
        assertAlive("after adding a to-do")
        leaveEverything()
        // A reminder and its comments.
        tap("Schule")
        tapStarting("Erinnerungen, Hausaufgaben")
        pause(1)
        openRows("Erinnerungen", limit: 1, mode: "good", account: "anna")
        leaveEverything()
        // An absence reported from Home, one excused.
        tap("Home")
        tapStarting("Abwesenheit melden")
        pause(1)
        assertAlive("reporting an absence")
        tap("Melden", timeout: 1)
        pause(1)
        leaveEverything()
        tap("Schule")
        tapStarting("Abwesenheiten, Fehlstunden")
        pause(1)
        tap("Entschuldigen", timeout: 1)
        pause(1)
        assertAlive("excusing an absence")
        leaveEverything()
        // A message read, answered, written.
        tap("Schule")
        tapStarting("Nachrichten, Posteingang")
        pause(1)
        tapStarting("Elternsprechtag", timeout: 2)
        pause(1)
        assertAlive("in a message")
        tap("Antworten", timeout: 1)
        pause(1)
        assertAlive("replying")
        leaveEverything()
        tap("Schule")
        tapStarting("Nachrichten, Posteingang")
        pause(0.6)
        tap("Mitteilung verfassen", timeout: 1)
        pause(1)
        assertAlive("composing")
        leaveEverything()
    }

    func testGradeWhatIf() {
        launch()
        waitForTabs()
        tap("Noten")
        pause(1)
        tapStarting("Mathematik")
        pause(0.5)
        openRows("Noten", limit: 3, mode: "good", account: "anna")
        assertAlive("in a subject")
    }

    private func typeIfPossible(_ text: String) {
        if app.keyboards.count > 0 { app.typeText(text) } else if app.textFields.firstMatch.exists { typeInto(app.textFields.firstMatch, text) }
    }

    func testSearch() {
        launch()
        waitForTabs()
        let search = app.buttons["Suche"].firstMatch
        if search.waitForExistence(timeout: 2) { search.tap() }
        pause(1)
        if app.keyboards.count > 0 {
            app.typeText("Mathe")
            pause(1.5)
            assertAlive("searching")
            app.typeText("\u{8}\u{8}\u{8}\u{8}\u{8}Spaghetti")
            pause(1)
        }
        assertAlive("after searching")
        leaveEverything()
    }

    private func budget(_ taps: Int) -> Int {
        ProcessInfo.processInfo.environment["POKYH_CRAWL_TAPS"].flatMap(Int.init) ?? taps
    }
}
