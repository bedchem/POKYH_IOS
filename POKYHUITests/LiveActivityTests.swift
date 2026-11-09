import XCTest

/// The Live Activity is opt-in: a fresh install has the switch off, turning it on sticks across a
/// relaunch, and turning it off again sticks too.
final class LiveActivityTests: AppTestCase {
    private var toggle: XCUIElement {
        app.switches.matching(NSPredicate(format: "label == %@", "Live-Aktivität")).firstMatch
    }

    private func openSettings() {
        openProfile()
        tap("Einstellungen", timeout: 3)
        pause(0.8)
    }

    /// Scrolled to it: the settings page is taller than the screen.
    private func revealToggle(file: StaticString = #filePath, line: UInt = #line) {
        let height = app.windows.firstMatch.frame.height
        for _ in 0..<12 {
            if toggle.exists, toggle.frame.midY > 130, toggle.frame.midY < height - 130 { return }
            app.swipeUp(velocity: .slow)
            pause(0.3)
        }
        XCTFail("No Live Activity switch in the settings", file: file, line: line)
    }

    private var isOn: Bool { (toggle.value as? String) == "1" }

    func testOffByDefaultAndRemembered() {
        launch()
        waitForTabs()
        openSettings()
        revealToggle()
        attachScreen("live activity off")
        XCTAssertFalse(isOn, "a fresh install starts with the Live Activity on")

        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        pause(0.5)
        XCTAssertTrue(isOn, "the switch doesn't turn on")
        attachScreen("live activity on")

        app.terminate()
        launch(reset: false)
        waitForTabs()
        openSettings()
        revealToggle()
        XCTAssertTrue(isOn, "turned on, but off again after a relaunch")

        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        pause(0.5)
        app.terminate()
        launch(reset: false)
        waitForTabs()
        openSettings()
        revealToggle()
        XCTAssertFalse(isOn, "turned off, but on again after a relaunch")
    }
}
