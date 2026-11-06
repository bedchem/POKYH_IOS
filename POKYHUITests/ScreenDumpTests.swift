import XCTest

/// Writes each main screen's accessibility tree to the output folder. For working on these tests:
/// what's on screen under which label.
final class ScreenDumpTests: AppTestCase {
    private func dump(_ name: String) {
        let path = "\(Self.outputDir)/screen-\(isPad ? "pad" : "phone")-\(name).txt"
        try? app.debugDescription.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func testDumpScreens() {
        launch()
        waitForTabs()
        pause(2)
        for name in tabs {
            tap(name)
            pause(1.5)
            dump(name)
        }
        tap("Schule")
        for tile in ["Nachrichten", "Abwesenheiten", "To-dos", "Erinnerungen", "Klassenbuch", "Klasse"] {
            tap(tile)
            pause(1.5)
            dump(tile)
            backOrClose()
            pause(0.5)
            tap("Schule")
        }
        tap("Home")
        tap("Profil")
        pause(1.5)
        dump("Profil")
        tap("Einstellungen")
        pause(1.5)
        dump("Einstellungen")
    }
}
