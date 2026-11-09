import XCTest

/// No network at all: the app opens from what an earlier sign-in stored, every screen shows its
/// copy, new to-dos wait for the connection, and signing out leaves nothing behind.
final class OfflineTests: AppTestCase {
    /// The hub's tiles by their titles.
    private static let tiles = ["Nachrichten", "Abwesenheiten", "To-dos", "Erinnerungen", "Klassenbuch", "Klasse"]

    /// Signs in online and opens every screen once, so each one has its copy on disk.
    private func storeEverything() {
        launch()
        waitForTabs()
        for name in ["Stundenplan", "Noten", "Mensa"] {
            tap(name)
            pause(1.2)
        }
        for tile in Self.tiles {
            tap("Schule")
            guard tap(tile, timeout: 3) else { continue }
            pause(1.5)
            if tile == "Nachrichten" {
                // An opened message stays readable too.
                tapStarting("Elternsprechtag", timeout: 3)
                pause(1.5)
            }
            leaveEverything()
        }
        tap("Home")
        pause(1.5)
        app.terminate()
    }

    /// Back with saved accounts and no internet; the lock screen tries Face ID by itself.
    private func launchOffline() {
        launch(mode: "all:offline", account: nil, reset: false)
        waitForTabs(timeout: 20)
    }

    private func expect(_ text: String, on screen: String, file: StaticString = #filePath, line: UInt = #line) {
        if !see(text, timeout: 6) {
            attachScreen("\(screen) without \(text)")
            XCTFail("\(screen) shows no stored copy (\(text))", file: file, line: line)
        }
    }

    private func openTile(_ tile: String) {
        leaveEverything()
        tap("Schule")
        XCTAssertTrue(tap(tile, timeout: 3), "no tile \(tile)")
        pause(1)
    }

    func testColdLaunchOfflineShowsEveryStoredCopy() {
        storeEverything()
        launchOffline()
        XCTAssertTrue(see("Offline", timeout: 5), "nothing says the app is offline")
        // Home counts the stored to-dos and reminders.
        expect("2 offen", on: "Home")

        tap("Stundenplan")
        expect("2.05", on: "Stundenplan")
        tap("Noten")
        expect("Mathematik", on: "Noten")
        tap("Mensa")
        expect("Spaghetti", on: "Mensa")

        openTile("Nachrichten")
        expect("Elternsprechtag", on: "Nachrichten")
        tapStarting("Elternsprechtag", timeout: 3)
        expect("Freitag", on: "Nachricht")
        openTile("Abwesenheiten")
        expect("Fieber", on: "Abwesenheiten")
        openTile("To-dos")
        expect("Mathe lernen", on: "To-dos")
        openTile("Erinnerungen")
        expect("Ausflug", on: "Erinnerungen")
        openTile("Klassenbuch")
        expect("Hausaufgaben vergessen", on: "Klassenbuch")
        openTile("Klasse")
        expect("luca", on: "Klasse")
        assertAlive("after the offline walk")
    }

    func testNewToDoWaitsForTheConnection() {
        storeEverything()
        launchOffline()
        openTile("To-dos")
        expect("Mathe lernen", on: "To-dos")

        // Ticking needs the server: it says so instead of pretending.
        tapBlindly(app.buttons.matching(NSPredicate(format: "label == %@", "Als erledigt markieren")).firstMatch)
        XCTAssertTrue(see("Offline nicht verfügbar", timeout: 3), "a tick offline didn't say it can't be saved")
        tap("OK", timeout: 2)

        tap("Neu", timeout: 2)
        pause(0.8)
        if app.keyboards.count == 0, app.textFields.firstMatch.waitForExistence(timeout: 3) { app.textFields.firstMatch.tap() }
        app.typeText("Offline Aufgabe")
        // XCTest's own tap waits for the sheet to settle above the keyboard.
        let add = app.buttons.matching(NSPredicate(format: "label == %@", "Hinzufügen")).firstMatch
        if add.waitForExistence(timeout: 3) { add.tap() }
        pause(1)
        expect("Wartet auf Internet", on: "To-dos")
        expect("Offline Aufgabe", on: "To-dos")

        // The connection comes back while the app is away; returning signs in and sends it.
        setMode("good")
        XCUIDevice.shared.press(.home)
        pause(1.5)
        app.activate()
        let waiting = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Wartet auf Internet")).firstMatch
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: gone, evaluatedWith: waiting)], timeout: 15), .completed,
                       "the queued to-do never went out")
        expect("Offline Aufgabe", on: "To-dos after sending")
        assertAlive("after sending the queue")
    }

    func testSignOutLeavesNothingBehind() {
        storeEverything()
        launch(mode: "good", account: nil, reset: false)
        waitForTabs(timeout: 20)
        openProfile()
        XCTAssertTrue(see("Konto hinzufügen", timeout: 5), "the profile never opened")
        // The account row's "more" menu signs out; the big button at the bottom only locks.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "anna")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "no account row")
        // The accounts sit under the activity grid, below the fold on a phone.
        let bottom = app.windows.firstMatch.frame.maxY - 60
        for _ in 0..<6 where row.frame.maxY > bottom {
            app.swipeUp(velocity: .slow)
            pause(0.4)
        }
        let more = app.buttons.matching(NSPredicate(format: "label == %@", "Mehr")).allElementsBoundByIndex
            .min { abs($0.frame.midY - row.frame.midY) < abs($1.frame.midY - row.frame.midY) }
        more?.tap()
        pause(0.8)
        let item = app.buttons.matching(NSPredicate(format: "label == %@", "Abmelden")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(item, "no sign-out in the account menu")
        item?.tap()
        pause(1.5)
        app.terminate()

        // Signing in works, everything else has no connection: only stored copies could show now.
        launch(mode: "offline", account: nil, reset: false)
        pause(1.5)
        if !tap("anna", timeout: 5) { tapStarting("anna", timeout: 3) }
        let password = app.secureTextFields.firstMatch
        if password.waitForExistence(timeout: 5) {
            typeInto(password, "richtig")
            app.typeText("\n")
        } else {
            signIn(user: "anna", password: "richtig")
        }
        waitForTabs(timeout: 20)

        tap("Noten")
        XCTAssertFalse(see("Mathematik", timeout: 3), "grades survived signing out")
        openTile("To-dos")
        XCTAssertFalse(see("Mathe lernen", timeout: 3), "to-dos survived signing out")
        openTile("Nachrichten")
        XCTAssertFalse(see("Elternsprechtag", timeout: 3), "messages survived signing out")
        assertAlive("after signing in again")
    }
}
