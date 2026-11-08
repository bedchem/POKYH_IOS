import XCTest

/// A returning account opens on what it had at once, while the sign-in is still on its way.
final class QuickStartTests: AppTestCase {
    func testUnlockOpensAtOnceWhileTheSignInIsSlow() {
        launch(env: ["POKYH_STUB_AUTOLOCK": "1"])
        waitForTabs()
        // Something stored to open on.
        tap("Noten")
        XCTAssertTrue(see("Mathematik", timeout: 8), "no grades to store")
        tap("Home")
        pause(1)

        // Locked, then back with a server that takes 2.5 s per answer: the sign-in alone takes
        // longer than that several times over.
        XCUIDevice.shared.press(.home)
        pause(2.5)
        setMode("slow")
        let back = Date()
        app.activate()
        waitForTabs(timeout: 4)
        let opened = Date().timeIntervalSince(back)
        XCTAssertLessThan(opened, 4, "waited for the sign-in instead of opening on the stored copy")
        XCTAssertFalse(see("letzte Stand", timeout: 1), "said offline while the sign-in was only on its way")

        // The stored grades are there before the sign-in is.
        tap("Noten")
        XCTAssertTrue(see("Mathematik", timeout: 2), "the stored grades didn't show at once")
        attachScreen("opened on the stored copy")

        // The server is quick again: the sign-in gets through and nothing says offline.
        setMode("good")
        pause(12)
        tap("Home")
        pause(1)
        XCTAssertFalse(see("letzte Stand", timeout: 1), "still offline after the sign-in got through")
        assertAlive("after the sign-in behind the stored copy")
    }
}
