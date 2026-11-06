import XCTest

/// The profile picture sits top right on every screen, whatever else a screen puts up there.
final class ProfilePictureTests: AppTestCase {
    func testStaysTopRightEverywhere() {
        launch()
        waitForTabs()
        for tab in tabs {
            tap(tab)
            check(tab)
        }
        tap("Schule")
        for screen in ["Nachrichten", "Abwesenheiten", "To-dos", "Erinnerungen", "Klassenbuch", "Klasse"] {
            guard tap(screen) else {
                XCTFail("Can't reach \(screen)")
                continue
            }
            check(screen)
            backOrClose()
        }
    }

    private func check(_ screen: String) {
        pause(0.8)
        attachScreen(screen)
        guard let bar = app.navigationBars.allElementsBoundByIndex.last else {
            XCTFail("\(screen) has no navigation bar")
            return
        }
        let buttons = bar.buttons.allElementsBoundByIndex.filter { $0.frame.width > 1 }
        let rightmost = buttons.max { $0.frame.maxX < $1.frame.maxX }
        XCTAssertEqual(rightmost?.label, "Profil", "\(screen): \(buttons.map(\.label))")
    }
}
