import XCTest

/// The same screens with answers nobody expected. Real crashes come from these. One test per mode,
/// so a crash names its mode and `-only-testing` can pick one.
final class BadDataTests: AppTestCase {
    private func run(_ mode: String) {
        launch(mode: mode)
        // Some of these end the session as soon as anything loads: back on the lock screen is fine,
        // as long as the app is still there.
        guard arrives(element("Schule"), timeout: 25) else {
            pause(3)
            attachScreen("no tabs in mode \(mode)")
            assertAlive("waiting for the tabs in mode \(mode)")
            return
        }
        walkMainScreens(mode: mode)
    }

    // Shape of the data.
    func testEmptyLists() { run("empty") }
    func testNullFields() { run("nulls") }
    func testAllNull() { run("nullsAll") }
    func testMissingFields() { run("missing") }
    func testOtherMissingFields() { run("missingB") }
    func testWrongTypes() { run("wrongTypes") }
    func testWrongContainers() { run("wrongContainers") }

    // Values.
    func testHugeValues() { run("huge") }
    func testNegativeValues() { run("negative") }
    func testZeroes() { run("zero") }
    func testNaNStrings() { run("nan") }
    func testDatesOutOfRange() { run("dates") }
    func testDuplicateIds() { run("duplicates") }
    func testStrangeText() { run("unicode") }

    // Not JSON at all.
    func testHTMLInsteadOfJSON() { run("html") }
    func testErrorPages() { run("htmlError") }
    func testGarbageBytes() { run("garbage") }
    func testTruncatedJSON() { run("truncated") }
    func testEmptyBody() { run("emptyBody") }

    // Status codes.
    func test401() { run("status401") }
    func test403() { run("status403") }
    func test404() { run("status404") }
    func test429() { run("status429") }
    func test500() { run("status500") }
    func test503() { run("status503") }

    // The network.
    func testTimeouts() { run("timeout") }
    func testDroppedConnection() { run("dropped") }
    func testNoInternet() { run("offline") }
    func testFlakyServer() { run("flaky") }

    func testSessionExpiresMidUse() {
        launch()
        waitForTabs()
        tap("Stundenplan")
        pause(1)
        setMode("expire")
        for name in ["Noten", "Schule", "Home", "Mensa"] where element(name).exists {
            tap(name)
            pause(0.8)
        }
        pause(2)
        assertAlive("with the session gone")
        setMode("good")
        pause(3)
        assertAlive("after the session came back")
    }

    func testSessionExpiresWhileReading() {
        launch()
        waitForTabs()
        tap("Schule")
        tapStarting("Nachrichten, Posteingang")
        pause(1)
        setMode("all:status401")
        tapStarting("Elternsprechtag", timeout: 2)
        pause(2)
        assertAlive("reading with the session gone")
        setMode("all:expire")
        leaveEverything()
        pause(2)
        assertAlive("after all of it expired")
    }

    func testConnectionDropsThenComesBack() {
        launch()
        waitForTabs()
        for mode in ["dropped", "timeout", "offline", "good", "status503", "good"] {
            setMode(mode)
            for name in ["Noten", "Stundenplan", "Mensa", "Home"] where element(name).exists {
                tap(name)
                pause(0.5)
            }
            assertAlive("in mode \(mode)")
        }
    }

    func testEverythingBadFromTheStart() {
        // Sign-in itself gets the bad answers too, so it has to stay on its feet there.
        for mode in ["all:html", "all:empty", "all:nullsAll", "all:wrongTypes", "all:huge", "all:garbage", "all:status500", "all:timeout"] {
            launch(mode: mode, account: "anna")
            pause(3)
            assertAlive("signing in with \(mode)")
            app.terminate()
        }
    }

    func testBadDataOnASavedAccount() {
        launch()
        waitForTabs()
        pause(1)
        app.terminate()
        // Saved copies and accounts from the last run, the server now answers nonsense.
        launch(mode: "huge", account: nil, reset: false)
        pause(3)
        assertAlive("on the lock screen")
        tap("anna", timeout: 2)
        pause(4)
        assertAlive("after unlocking")
    }

    func testRecapWithBadData() {
        // The story opens by itself; what it reads is the most heavily computed answer in the app.
        for mode in ["huge", "negative", "nulls", "missing", "dates", "zero", "duplicates", "wrongTypes", "nan"] {
            launch(mode: mode, env: ["POKYH_STUB_RECAP": "1"])
            pause(5)
            for _ in 0..<16 where app.state == .runningForeground {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
                tapBlindly(app.buttons["Weiter"].firstMatch)
                pause(0.15)
            }
            assertAlive("in the recap in mode \(mode)")
            app.terminate()
        }
    }

    func testPopupsWithBadData() {
        for mode in ["huge", "negative", "nulls", "dates", "duplicates", "zero"] {
            launch(mode: mode, env: ["POKYH_STUB_POPUPS": "1"])
            pause(8)
            assertAlive("popups in mode \(mode)")
            app.terminate()
        }
    }
}
