import XCTest

/// E-mail, password, two-factor and the statistics against the stub. The stub keeps what these
/// change for one launch and rejects a stale password, so a sign-in behind the lock proves what
/// the app saved. Nothing here reaches a real server.
final class AccountSettingsTests: AppTestCase {
    private func row(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// The pages aren't lazy, everything exists from the start: it has to be on screen to be tapped.
    private func reveal(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let height = app.windows.firstMatch.frame.height
        for _ in 0..<25 where target.exists {
            let y = target.frame.midY
            if y > 130, y < height - 130 { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: y > 130 ? 0.7 : 0.4))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: y > 130 ? 0.4 : 0.7))
            from.press(forDuration: 0.05, thenDragTo: to)
            pause(0.3)
        }
        if !target.exists { XCTFail("Never found \(target)", file: file, line: line) }
    }

    private func openSettings() {
        openProfile()
        tap("Einstellungen", timeout: 3)
        pause(0.8)
    }

    private func openRow(_ prefix: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = row(prefix)
        reveal(target, file: file, line: line)
        tapBlindly(target)
        pause(0.8)
    }

    /// `backOrClose` takes a back button named after the profile for the profile picture.
    private func goBack() {
        guard let back = app.navigationBars.allElementsBoundByIndex.last?.buttons.firstMatch, back.exists else { return }
        tapBlindly(back)
        pause(0.6)
    }

    private func lockAndComeBack() {
        XCUIDevice.shared.press(.home)
        pause(2.5)
        app.activate()
        pause(2)
    }

    private func replaceText(_ field: XCUIElement, _ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        pause(0.2)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + text)
    }

    // ── E-mail ───────────────────────────────────────────────────────────────

    func testChangeEmail() {
        launch()
        waitForTabs()
        openSettings()
        XCTAssertTrue(row("E-Mail-Adresse").label.contains("anna@stub.invalid"), row("E-Mail-Adresse").label)
        attachScreen("settings account group")
        openRow("E-Mail-Adresse")
        attachScreen("email sheet")

        let field = app.textFields.firstMatch
        replaceText(field, "keine adresse")
        tap("Speichern")
        XCTAssertTrue(see("gültige E-Mail"), "a bad address gets through")

        replaceText(field, "abgelehnt@stub.invalid")
        tap("Speichern")
        XCTAssertTrue(see("nimmt WebUntis nicht", timeout: 4), "WebUntis' reason isn't shown")

        replaceText(field, "neu@stub.invalid")
        tap("Speichern")
        XCTAssertTrue(see("Gespeichert", timeout: 4))
        attachScreen("email saved")
        backOrClose()
        pause(0.6)
        XCTAssertTrue(row("E-Mail-Adresse").label.contains("neu@stub.invalid"), row("E-Mail-Adresse").label)
    }

    func testNoEmailYet() {
        launch(env: ["POKYH_STUB_PROFILE": "noemail"])
        waitForTabs()
        openSettings()
        XCTAssertTrue(row("E-Mail-Adresse").label.contains("Fehlt"), row("E-Mail-Adresse").label)
        let forward = app.switches["Nachrichten auch per E-Mail"].firstMatch
        reveal(forward)
        XCTAssertFalse(forward.isEnabled, "forwarding needs an address")
        XCTAssertTrue(see("zuerst eine E-Mail-Adresse"))
        attachScreen("no email")
    }

    func testForwardAndLanguageSave() {
        launch()
        waitForTabs()
        openSettings()
        let forward = app.switches["Nachrichten auch per E-Mail"].firstMatch
        reveal(forward)
        XCTAssertEqual(forward.value as? String, "0")
        tapBlindly(forward.switches.firstMatch.exists ? forward.switches.firstMatch : forward)
        pause(1)
        XCTAssertEqual(forward.value as? String, "1", "the switch went back")

        // A failed save puts it back and says why.
        setMode("status500")
        tapBlindly(forward)
        pause(1.5)
        XCTAssertEqual(forward.value as? String, "1", "a failed save left the switch moved")
        XCTAssertTrue(see("Stub 500") || see("nicht gespeichert"), "no reason for the failed save")
        setMode("good")

        let language = row("Deutsch")
        reveal(language)
        tapBlindly(language)
        pause(0.5)
        tap("Italiano", timeout: 2)
        pause(1)
        XCTAssertTrue(row("Italiano").exists, "the language didn't change")
    }

    // ── Password ─────────────────────────────────────────────────────────────

    private func fillPassword(old: String, new: String, again: String) {
        typeInto(app.secureTextFields.element(boundBy: 0), old)
        typeInto(app.secureTextFields.element(boundBy: 1), new)
        typeInto(app.secureTextFields.element(boundBy: 2), again)
        tap("Passwort ändern")
    }

    func testChangePasswordAndSignInWithTheNewOne() {
        launch(env: ["POKYH_STUB_AUTOLOCK": "1"])
        waitForTabs()
        openSettings()
        openRow("Passwort")
        attachScreen("password sheet")

        fillPassword(old: "stub", new: "neu-geheim", again: "anders")
        XCTAssertTrue(see("stimmen nicht überein"), "mismatch not caught")
        fillPassword(old: "stub", new: "stub", again: "stub")
        XCTAssertTrue(see("unterscheiden"), "same password not caught")
        fillPassword(old: "falsch", new: "neu-geheim", again: "neu-geheim")
        XCTAssertTrue(see("aktuelle Passwort stimmt nicht", timeout: 4), "WebUntis' reason isn't shown")
        attachScreen("password wrong old")

        fillPassword(old: "stub", new: "neu-geheim", again: "neu-geheim")
        XCTAssertTrue(see("Passwort geändert", timeout: 4))
        attachScreen("password changed")
        pause(2.5)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists, "the sheet stays up")

        // Only the new password signs in now. Behind the lock the app uses the one it saved.
        lockAndComeBack()
        waitForTabs(timeout: 12)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists, "the app asks for a password it should have saved")
        attachScreen("signed in after the change")
    }

    func testPasswordChangeNotAllowedOffersTheReset() {
        launch(env: ["POKYH_STUB_PROFILE": "nochange"])
        waitForTabs()
        openSettings()
        openRow("Passwort")
        XCTAssertFalse(app.secureTextFields.firstMatch.exists, "the school doesn't let it be changed here")
        XCTAssertEqual(app.textFields.count, 2, "the reset form asks for name and address")
        attachScreen("password reset instead")
    }

    // ── Two-factor ───────────────────────────────────────────────────────────

    func testTurnOnTwoFactorThenTheCodeIsAsked() {
        launch(env: ["POKYH_STUB_AUTOLOCK": "1"])
        waitForTabs()
        openSettings()
        XCTAssertTrue(row("Zwei-Faktor-Anmeldung").label.contains("Aus"), row("Zwei-Faktor-Anmeldung").label)
        openRow("Zwei-Faktor-Anmeldung")
        attachScreen("two-factor intro")
        tap("Weiter")
        pause(0.6)
        XCTAssertTrue(see("JBSW Y3DP EHPK 3PXP", timeout: 4), "no key to type in")
        XCTAssertTrue(app.images["Mit der Authenticator-App scannen"].firstMatch.waitForExistence(timeout: 2), "no QR code")
        attachScreen("two-factor scan")

        let code = app.textFields.firstMatch
        let enable = app.buttons.matching(NSPredicate(format: "label == %@", "Einschalten")).allElementsBoundByIndex.last
        XCTAssertEqual(enable?.isEnabled, false, "a code needs six digits")
        // The sixth digit sends it.
        replaceText(code, "111111")
        XCTAssertTrue(see("Der Code stimmt nicht", timeout: 4), "a wrong code gets through")
        attachScreen("two-factor wrong code")
        replaceText(code, "123456")
        XCTAssertTrue(see("Lösche den Eintrag", timeout: 4))
        attachScreen("two-factor done")
        tap("Schließen")
        pause(0.8)
        XCTAssertTrue(row("Zwei-Faktor-Anmeldung").label.contains("An"), row("Zwei-Faktor-Anmeldung").label)

        lockAndComeBack()
        XCTAssertTrue(see("Code", timeout: 10), "the next sign-in has to ask for the code")
        let prompt = app.textFields.firstMatch
        replaceText(prompt, "123456")
        // The lock screen has its own "Anmelden" under the prompt; the prompt's sits beside its cancel.
        let cancel = app.buttons["Abbrechen"].firstMatch
        let submit = app.buttons.matching(NSPredicate(format: "label == %@", "Anmelden")).allElementsBoundByIndex
            .filter { $0.frame.width > 1 }
            .min { abs($0.frame.midY - cancel.frame.midY) < abs($1.frame.midY - cancel.frame.midY) }
        XCTAssertNotNil(submit, "no way to send the code")
        // Tapping the field put up the paste menu; the first tap after it only closes the menu.
        pause(1)
        submit?.tap()
        waitForTabs(timeout: 12)
    }

    func testTurnOffTwoFactor() {
        launch(env: ["POKYH_STUB_PROFILE": "on"])
        waitForTabs()
        openSettings()
        openRow("Zwei-Faktor-Anmeldung")
        XCTAssertTrue(see("schlechter geschützt"), "disabling doesn't say what it means")
        attachScreen("two-factor disable")
        tap("Ausschalten")
        pause(1)
        XCTAssertTrue(row("Zwei-Faktor-Anmeldung").label.contains("Aus"), row("Zwei-Faktor-Anmeldung").label)
    }

    func testTwoFactorRequiredByTheSchool() {
        launch(env: ["POKYH_STUB_PROFILE": "required"])
        waitForTabs()
        openSettings()
        XCTAssertFalse(row("Zwei-Faktor-Anmeldung").exists, "a required one can't be turned off")
        XCTAssertTrue(see("Von deiner Schule verlangt"))
        attachScreen("two-factor required")
    }

    func testNoTwoFactorWhereItIsntOffered() {
        launch(env: ["POKYH_STUB_PROFILE": "notavailable"])
        waitForTabs()
        openSettings()
        XCTAssertTrue(row("E-Mail-Adresse").exists)
        XCTAssertFalse(see("Zwei-Faktor", timeout: 1))
    }

    // ── Activity ─────────────────────────────────────────────────────────────

    func testActivityAndStatistics() {
        launch()
        waitForTabs()
        openProfile()
        XCTAssertTrue(see("Tage online", timeout: 4))
        XCTAssertTrue(see("Aktuelle Serie"))
        attachScreen("activity on the profile")

        // The last square is today, the one the grid opens at.
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Anmeldung")).allElementsBoundByIndex.last
        if let day {
            tapBlindly(day)
            pause(0.6)
            attachScreen("a day's figures")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
            pause(0.4)
        } else {
            XCTFail("No day to tap")
        }

        openRow("Mehr Statistiken")
        XCTAssertTrue(see("Nutzungszeit", timeout: 4))
        XCTAssertTrue(see("Wann du online bist"))
        attachScreen("statistics top")
        for section in ["Wochentage", "Geräte", "Meistgenutzte Seiten", "Was du erstellt hast"] {
            reveal(app.staticTexts[section].firstMatch)
            attachScreen("statistics \(section)")
        }
        XCTAssertTrue(see("Stundenplan"), "a page's name isn't translated")
        XCTAssertTrue(see("DABEI SEIT"))
        assertAlive("on the statistics")
    }

    func testWholeSchoolYearOpensAtToday() {
        launch(env: ["POKYH_STUB_ACTIVITY_DAYS": "300"])
        waitForTabs()
        openProfile()
        XCTAssertTrue(see("Tage online", timeout: 4))
        pause(1)
        attachScreen("a whole school year")
        assertAlive("with a whole school year")
    }

    func testConsentOff() {
        launch(env: ["POKYH_STUB_CONSENT": "off"])
        waitForTabs()
        openProfile()
        XCTAssertTrue(see("Persönliche Statistiken sind aus", timeout: 4))
        attachScreen("consent off on the profile")
        openRow("Mehr Statistiken")
        XCTAssertTrue(see("Wochentage", timeout: 4))
        XCTAssertFalse(see("Wann du online bist", timeout: 0.5), "no time without consent")
        XCTAssertFalse(see("Meistgenutzte Seiten", timeout: 0.5), "no pages without consent")
        attachScreen("consent off statistics")
        tapStarting("In den Einstellungen einschalten")
        pause(1)
        XCTAssertTrue(see("Darstellung", timeout: 3) || see("Konto & Sicherheit", timeout: 1), "doesn't lead to the settings")
    }

    // ── Both looks ───────────────────────────────────────────────────────────

    func testEveryScreenInLightAndDark() {
        for theme in ["light", "dark"] {
            launch(theme: theme, env: ["POKYH_STUB_CONSENT": theme == "dark" ? "off" : "on"])
            waitForTabs()
            openProfile()
            pause(1)
            attachScreen("\(theme) profile")
            openRow("Mehr Statistiken")
            pause(1)
            attachScreen("\(theme) statistics")
            for section in ["Geräte", "Was du erstellt hast"] {
                reveal(app.staticTexts[section].firstMatch)
                attachScreen("\(theme) statistics \(section)")
            }
            goBack()
            tap("Einstellungen", timeout: 3)
            pause(0.8)
            reveal(row("E-Mail-Adresse"))
            attachScreen("\(theme) settings account")
            reveal(app.switches["Nachrichten auch per E-Mail"].firstMatch)
            attachScreen("\(theme) settings forwarding")
            openRow("Zwei-Faktor-Anmeldung")
            tap("Weiter")
            pause(0.8)
            attachScreen("\(theme) two-factor scan")
            backOrClose()
            pause(0.6)
            openRow("Passwort")
            attachScreen("\(theme) password")
            backOrClose()
            pause(0.4)
            app.terminate()
        }
    }

    // ── Junk ─────────────────────────────────────────────────────────────────

    /// Whatever the server sends, these screens stay up.
    func testBadDataOnEveryScreen() {
        launch()
        waitForTabs()
        openProfile()
        pause(1)
        let modes = ["empty", "nulls", "nullsAll", "missing", "missingB", "wrongTypes", "wrongContainers", "huge", "negative", "zero", "nan", "dates",
                     "duplicates", "unicode", "garbage", "truncated", "emptyBody", "html", "htmlError", "status500", "status404", "offline", "timeout", "dropped"]
        for mode in modes {
            setMode(mode)
            note("mode \(mode)")
            // Some of these read as an expired session, and the app locks and signs in again.
            if !app.buttons["Einstellungen"].firstMatch.waitForExistence(timeout: 1) {
                setMode("good")
                waitForTabs(timeout: 15)
                openProfile()
                setMode(mode)
            }
            // Off the profile and back: both pages read the server again on the way.
            tap("Einstellungen", timeout: 2)
            pause(0.8)
            assertAlive("in the settings, mode \(mode)")
            for prefix in ["E-Mail-Adresse", "Zwei-Faktor-Anmeldung"] where row(prefix).exists {
                openRow(prefix)
                assertAlive("in \(prefix), mode \(mode)")
                if element("Weiter").exists {
                    tap("Weiter")
                    pause(0.6)
                    assertAlive("starting two-factor, mode \(mode)")
                }
                backOrClose()
                pause(0.5)
            }
            attachScreen("settings \(mode)")
            goBack()
            pause(0.4)
            assertAlive("back on the profile, mode \(mode)")
            attachScreen("profile \(mode)")
            if row("Mehr Statistiken").exists {
                openRow("Mehr Statistiken")
                assertAlive("on the statistics, mode \(mode)")
                attachScreen("statistics \(mode)")
                goBack()
            }
            assertAlive("after mode \(mode)")
        }
        setMode("good")
    }
}
