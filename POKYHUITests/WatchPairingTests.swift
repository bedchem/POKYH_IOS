import XCTest

/// The real hand-off to a paired watch simulator. Skipped where no watch with POKYH is paired.
/// Writes marker files so the watch can be looked at from outside at each step.
final class WatchPairingTests: AppTestCase {
    private func mark(_ name: String) {
        FileManager.default.createFile(atPath: "\(Self.outputDir)/watch-step-\(name)", contents: nil)
    }

    private func shot(_ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(Self.outputDir)/watch-pair-\(name).png"))
    }

    func testConnectThenNotNow() throws {
        launch(arguments: ["-POKYHStubWatch", "YES"])
        waitForTabs()
        guard see("POKYH auf der Apple Watch", timeout: 20) else {
            throw XCTSkip("No paired watch simulator with POKYH on it")
        }
        shot("1-offer")
        XCTAssertTrue(tap("Verbinden"))
        pause(1)
        XCTAssertFalse(see("POKYH auf der Apple Watch", timeout: 1), "still asking after Connect")
        // Home loads, the snapshot goes out a second later.
        pause(12)
        mark("connected")
        pause(8)

        // The settings say so.
        app.buttons["Profil"].firstMatch.tap()
        pause(1.5)
        tap("Einstellungen")
        pause(1.5)
        for _ in 0..<4 where !see("Bereit", timeout: 1) { app.swipeUp() }
        XCTAssertTrue(see("Bereit", timeout: 3), "settings don't show the watch as connected")
        shot("2-settings")

        // Asked again from scratch and declined: the watch is signed out.
        app.terminate()
        launch(arguments: ["-POKYHStubWatch", "YES"])
        waitForTabs()
        XCTAssertTrue(see("POKYH auf der Apple Watch", timeout: 20))
        XCTAssertTrue(tap("Nicht jetzt"))
        pause(10)
        mark("declined")
        pause(8)
    }
}
