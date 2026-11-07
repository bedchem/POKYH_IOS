import XCTest

/// Walks the main screens in Italian and English and writes every text on them to a file, then
/// fails on words only German has. School data from the stub (names, subjects) stays German on
/// purpose, so it's listed as allowed.
final class LanguageTests: AppTestCase {
    private struct Labels {
        let tabs: [String]
        let tiles: [String]
        let profile: String
        let settings: String
    }

    private let labels: [String: Labels] = [
        "it": Labels(tabs: ["Home", "Orario", "Scuola", "Voti", "Mensa"],
                     tiles: ["Messaggi", "Assenze", "To-do", "Promemoria", "Registro di classe", "Classe"],
                     profile: "Profilo", settings: "Impostazioni"),
        "en": Labels(tabs: ["Home", "Timetable", "School", "Grades", "Canteen"],
                     tiles: ["Messages", "Absences", "To-dos", "Reminders", "Class register", "Class"],
                     profile: "Profile", settings: "Settings"),
    ]

    /// UI words that only turn up when a German string slipped through.
    private let german = ["Heute", "Morgen", "Stunde", "Woche", "Keine", "keine", "nicht", "Einstellungen", "Konto",
                          "Abmelden", "Nachricht", "Abwesenheit", "Erinnerung", "Klassenbuch", "Fertig", "Abbrechen",
                          "Löschen", "Bearbeiten", "Speichern", "Suchen", "Hinzufügen", "Schließen", "Zurück",
                          "Noten", "Durchschnitt", "Entschuldig", "Fehlstunden", "Stundenplan", "Schule", "Gestern",
                          " und ", " der ", " die ", " das ", " mit ", " für ", " von ", "Uhr"]

    /// The stub's school data, which a real school would send in its own language.
    private let stubData = ["Mathematik", "Deutsch", "Geschichte", "Schularbeit", "Klassenfahrt", "Elternsprechtag",
                            "Wandertag", "Brixen", "Müller", "Schuljahr", "Hausaufgabe", "Turnen", "Religion",
                            "Vorschau von", "Teststadt Schule", "Andere Schule", "Hauptstraße", "Ausflug", "Schulball", "Erledigt"]

    func testItalian() { walk("it") }
    func testEnglish() { walk("en") }
    func testItalianSignIn() { signIn("it") }
    func testEnglishSignIn() { signIn("en") }

    /// The first thing App Review sees: the sign-in and the school search.
    private func signIn(_ lang: String) {
        launch(account: nil, language: lang)
        pause(3)
        var texts = Set<String>()
        func collect() {
            guard let root = try? app.snapshot() else { return }
            func walk(_ node: XCUIElementSnapshot) {
                for text in [node.label, node.value as? String ?? "", node.placeholderValue ?? ""] where !text.isEmpty {
                    texts.insert(text)
                }
                node.children.forEach(walk)
            }
            walk(root)
        }
        collect()
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            typeInto(field, "Test")
            pause(2)
            collect()
        }
        let flagged = texts.filter { text in
            let cleaned = stubData.reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
            return german.contains { cleaned.contains($0) }
        }
        try? texts.sorted().joined(separator: "\n").write(toFile: "\(Self.outputDir)/texts-signin-\(lang).txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(flagged.isEmpty, "German on the sign-in in \(lang):\n" + flagged.sorted().joined(separator: "\n"))
    }

    private func walk(_ lang: String) {
        guard let l = labels[lang] else { return }
        launch(language: lang)
        guard arrives(element(l.tabs[2]), timeout: 15) else { return XCTFail("no tabs in \(lang)") }
        pause(2)
        var found: [String: Set<String>] = [:]
        func collect(_ screen: String) {
            pause(1.5)
            guard let root = try? app.snapshot() else { return }
            var texts = Set<String>()
            func walk(_ node: XCUIElementSnapshot) {
                for text in [node.label, node.value as? String ?? "", node.placeholderValue ?? ""] where !text.isEmpty {
                    texts.insert(text)
                }
                node.children.forEach(walk)
            }
            walk(root)
            found[screen] = texts
        }
        for tab in l.tabs {
            tap(tab)
            collect(tab)
        }
        tap(l.tabs[2])
        for tile in l.tiles {
            guard tap(tile) else { continue }
            collect(tile)
            backOrClose()
            pause(0.5)
            tap(l.tabs[2])
        }
        tap(l.tabs[0])
        if tap(l.profile) {
            collect(l.profile)
            if tap(l.settings) { collect(l.settings) }
        }

        var report = ""
        var flagged: [String] = []
        for (screen, texts) in found.sorted(by: { $0.key < $1.key }) {
            report += "## \(screen)\n" + texts.sorted().joined(separator: "\n") + "\n\n"
            for text in texts {
                let cleaned = stubData.reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
                if german.contains(where: { cleaned.contains($0) }) { flagged.append("\(screen): \(text)") }
            }
        }
        try? report.write(toFile: "\(Self.outputDir)/texts-\(lang).txt", atomically: true, encoding: .utf8)
        try? flagged.joined(separator: "\n").write(toFile: "\(Self.outputDir)/german-in-\(lang).txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(flagged.isEmpty, "German in \(lang):\n" + flagged.joined(separator: "\n"))
    }
}
