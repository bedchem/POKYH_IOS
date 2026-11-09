import XCTest

/// Starts the app against its stub server (App/Testing/StubServer.swift) and moves around in it.
/// Everything looks elements up by what they say, in German, which the launch arguments force for
/// this one process. Nothing changes on the simulator itself.
class AppTestCase: XCTestCase {
    let app = XCUIApplication()
    private(set) var trail: [String] = []
    /// Taps in the crawl that changed nothing on screen, for its report.
    private var silent: [String] = []
    private var crashes = 0

    /// Where logs and the mode file go. `make uitest` points it at a folder of its own.
    static var outputDir: String {
        let env = ProcessInfo.processInfo.environment
        return env["POKYH_UITEST_DIR"] ?? NSTemporaryDirectory()
    }

    private var controlFile: String { "\(Self.outputDir)/stub-mode-\(ProcessInfo.processInfo.processIdentifier).txt" }

    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        // The default is 10 minutes, and big answers make every look at the screen slow.
        executionTimeAllowance = 1500
        try? FileManager.default.createDirectory(atPath: Self.outputDir, withIntermediateDirectories: true)
        setMode("")
        // Permission questions come from the system, not the app.
        addUIInterruptionMonitor(withDescription: "system alert") { alert in
            for label in ["Nicht erlauben", "Don’t Allow", "Don't Allow", "Abbrechen", "Cancel", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    override func tearDown() {
        if app.state != .notRunning { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        try? FileManager.default.removeItem(atPath: controlFile)
        super.tearDown()
    }

    // ── Launching ────────────────────────────────────────────────────────────

    /// `account`: signed in by itself at launch, the sign-in screens are tested on their own.
    func launch(mode: String = "good", account: String? = "anna", reset: Bool = true, theme: String? = nil,
                env: [String: String] = [:], arguments: [String] = [], language: String = "de") {
        setMode("")
        app.launchArguments = ["-POKYHStubServer", "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_IT"] + arguments
        if reset { app.launchArguments.append("-POKYHStubReset") }
        if let theme { app.launchArguments += ["-pokyh_theme", theme] }
        var environment = env
        environment["POKYH_STUB_MODE"] = mode
        environment["POKYH_STUB_CONTROL"] = controlFile
        environment["POKYH_STUB_LOG"] = "\(Self.outputDir)/stub.log"
        if let account { environment["POKYH_STUB_SIGNIN"] = account }
        // Sanitizer reports go to files: an app started by XCTest has nobody reading its stderr.
        let dir = Self.outputDir
        environment["TSAN_OPTIONS"] = "log_path=\(dir)/tsan:halt_on_error=0:second_deadlock_stack=1"
        environment["ASAN_OPTIONS"] = "log_path=\(dir)/asan:halt_on_error=1:detect_stack_use_after_return=1"
        environment["UBSAN_OPTIONS"] = "log_path=\(dir)/ubsan:print_stacktrace=1:halt_on_error=0"
        if ProcessInfo.processInfo.environment["POKYH_MAIN_THREAD_CHECK"] != nil {
            environment["DYLD_INSERT_LIBRARIES"] = "/usr/lib/libMainThreadChecker.dylib"
            environment["MTC_CRASH_ON_REPORT"] = "1"
        }
        app.launchEnvironment = environment
        app.launch()
        note("launch mode=\(mode) account=\(account ?? "-")")
    }

    /// From now on the server answers like this, the running app included.
    func setMode(_ mode: String) {
        FileManager.default.createFile(atPath: controlFile, contents: Data(mode.utf8))
    }

    // ── Staying alive ────────────────────────────────────────────────────────

    func note(_ step: String) {
        trail.append(step)
        if trail.count > 40 { trail.removeFirst() }
    }

    /// False when the app died. Records it with how it got there and starts it again.
    @discardableResult
    func assertAlive(_ context: String = "", file: StaticString = #filePath, line: UInt = #line) -> Bool {
        if app.state == .runningForeground { return true }
        if app.state == .runningBackground || app.state == .runningBackgroundSuspended {
            app.activate()
            return true
        }
        crashes += 1
        let steps = trail.suffix(15).joined(separator: "\n  ")
        XCTFail("App died \(context). Last steps:\n  \(steps)", file: file, line: line)
        return false
    }

    /// Like assertAlive, but the walk goes on: one crash shouldn't hide the next.
    func relaunchIfDead(mode: String, account: String?, env: [String: String] = [:], context: String = "") -> Bool {
        if assertAlive(context) { return false }
        launch(mode: mode, account: account, reset: false, env: env)
        waitForTabs()
        return true
    }

    // ── Elements ─────────────────────────────────────────────────────────────

    func pause(_ seconds: TimeInterval = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Anything tappable that says `label`.
    func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND elementType IN %@", label, [
            XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.link.rawValue,
            XCUIElement.ElementType.staticText.rawValue, XCUIElement.ElementType.tab.rawValue,
            XCUIElement.ElementType.switch.rawValue, XCUIElement.ElementType.menuItem.rawValue,
        ])).firstMatch
    }

    @discardableResult
    func tap(_ label: String, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let target = element(label)
        guard arrives(target, timeout: timeout) else {
            note("missing: \(label)")
            return false
        }
        note("tap \(label)")
        tapBlindly(target)
        pause(0.2)
        assertAlive("after tapping \(label)", file: file, line: line)
        return true
    }

    func see(_ label: String, timeout: TimeInterval = 3) -> Bool {
        arrives(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch, timeout: timeout)
    }

    /// waitForExistence sleeps a second before its first look, even for what's already there.
    func arrives(_ target: XCUIElement, timeout: TimeInterval) -> Bool {
        target.exists || target.waitForExistence(timeout: timeout)
    }

    /// isHittable fails the test for elements without a usable activation point, and SwiftUI has
    /// plenty of those, so tap where it is instead of asking first.
    func tapBlindly(_ target: XCUIElement) {
        // One look, then tap where it was: a second query fails the test when the element left in
        // between, which is the app moving on (a list reloading), not a bug.
        guard let found = try? target.snapshot(), found.frame.width > 0 else { return }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: found.frame.midX, dy: found.frame.midY)).tap()
    }

    func typeInto(_ field: XCUIElement, _ text: String) {
        guard field.waitForExistence(timeout: 5) else { note("no field for \(text)"); return }
        field.tap()
        // A slow app (sanitizers) takes focus late; keys typed before that go nowhere.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 4) { field.tap() }
        pause(0.4)
        app.typeText(text)
        note("typed \(text)")
    }

    // ── Moving around ────────────────────────────────────────────────────────

    /// The tabs a signed-in account has, in the order of the bar.
    var tabs: [String] { ["Home", "Stundenplan", "Schule", "Noten", "Mensa"] }

    func waitForTabs(timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        if !arrives(element("Schule"), timeout: timeout) {
            XCTFail("Tabs never came up", file: file, line: line)
            attachScreen("no tabs")
        }
    }

    func goToTab(_ name: String) {
        leaveEverything()
        tap(name)
    }

    /// One step back: a pushed screen pops, a sheet closes. False when there was nothing to leave.
    @discardableResult
    func backOrClose() -> Bool {
        guard let root = try? app.snapshot() else { return false }
        var bars: [XCUIElementSnapshot] = []
        var closers: [(label: String, frame: CGRect)] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .navigationBar { bars.append(node) }
            if node.elementType == .button, node.isEnabled, node.frame.width > 1, Self.closeLabels.contains(node.label) {
                closers.append((node.label, node.frame))
            }
            node.children.forEach(walk)
        }
        walk(root)
        var target = closers.last
        // Sheets come later in the tree, so the last bar is the one on top.
        if target == nil || target?.label == "Zurück" {
            for bar in bars.reversed() {
                var buttons: [XCUIElementSnapshot] = []
                func collect(_ node: XCUIElementSnapshot) {
                    if node.elementType == .button { buttons.append(node) }
                    node.children.forEach(collect)
                }
                collect(bar)
                if let first = buttons.min(by: { $0.frame.minX < $1.frame.minX }), !first.label.isEmpty,
                   first.frame.minX < bar.frame.minX + 70, !Self.barButtonsThatStay.contains(first.label) {
                    target = (first.label, first.frame)
                    break
                }
            }
        }
        guard let target else { return false }
        note("back (\(target.label))")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.frame.midX, dy: target.frame.midY)).tap()
        pause(0.3)
        return true
    }

    private static let closeLabels: Set<String> = ["Schließen", "Close", "Fertig", "Abbrechen", "OK", "Verstanden", "Zurück"]
    private static let barButtonsThatStay: Set<String> = ["Profil", "Nachrichten", "Suchen", "Suche", "Bearbeiten", "Einstellungen", "Benachrichtigungen",
                                                          "Seitenleiste ein-/ausblenden", "Mehr", "Neu", "Exportieren"]

    func leaveEverything() {
        for _ in 0..<6 where backOrClose() {}
    }

    /// The code prompt's own "Anmelden", the one beside its cancel button; the form under it has one too.
    func confirmCode() {
        let cancel = app.buttons["Abbrechen"].firstMatch
        let submit = app.buttons.matching(NSPredicate(format: "label == %@", "Anmelden")).allElementsBoundByIndex
            .filter { $0.frame.width > 1 }
            .min { abs($0.frame.midY - cancel.frame.midY) < abs($1.frame.midY - cancel.frame.midY) }
        guard let submit else {
            XCTFail("no way to send the code")
            return
        }
        note("confirm code")
        tapBlindly(submit)
    }

    func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Signed in on the home screen with an open profile sheet.
    func openProfile() {
        tap("Home")
        tap("Profil")
        pause(0.5)
    }

    func signIn(school: String = "Teststadt", user: String, password: String) {
        if let schoolField = Optional(app.textFields.firstMatch), schoolField.waitForExistence(timeout: 5), !app.secureTextFields.firstMatch.exists {
            typeInto(schoolField, school)
            tap("Teststadt Schule", timeout: 6)
        }
        fillAccount(user: user, password: password)
    }

    func fillAccount(user: String, password: String) {
        let userField = app.textFields.firstMatch
        typeInto(userField, user)
        typeInto(app.secureTextFields.firstMatch, password)
        // Return in the password field submits; the button can sit under the keyboard in a sheet.
        app.typeText("\n")
        note("submit \(user)")
    }

    // ── The crawl ────────────────────────────────────────────────────────────

    /// What the crawl leaves alone: leads out of the app, or ends the walk. The scripted tests do those.
    private static let offLimits: [String] = [
        "Abmelden", "Konto löschen", "Alle Daten löschen", "Cache & Daten löschen", "Daten löschen", "Konto entfernen", "Entfernen",
        "Website", "Datenschutz", "Impressum", "Nutzungsbedingungen", "Support", "E-Mail", "Teilen", "Share", "Exportieren",
        "Offiziellen", "WebUntis öffnen", "Tastatur", "Keyboard", "Diktieren", "Dictate", "Emoji", "Link öffnen", "Extern öffnen",
        "Abwesenheitsbrief", "Kamera", "QR-Code scannen",
    ]

    private struct Target {
        let label: String
        let frame: CGRect
        let type: XCUIElement.ElementType
    }

    /// Taps everything it can reach once per screen, up to `budget` taps, over all tabs.
    func crawl(budget: Int, mode: String = "good", account: String? = "anna", env: [String: String] = [:], tabs names: [String]? = nil) {
        var visited = Set<String>()
        var taps = 0
        for tabName in names ?? tabs {
            if taps >= budget { break }
            if !arrives(element(tabName), timeout: 2) { continue }
            leaveEverything()
            tap(tabName)
            var idle = 0
            while taps < budget, idle < 6 {
                if relaunchIfDead(mode: mode, account: account, env: env, context: "during crawl") { tap(tabName) }
                let targets = currentTargets()
                let screen = screenName()
                let next = targets.first { !visited.contains("\(screen)|\($0.label)") }
                guard let next else {
                    idle += 1
                    if !backOrClose() { break }
                    continue
                }
                idle = 0
                visited.insert("\(screen)|\(next.label)")
                taps += 1
                note("crawl[\(screen)] \(next.label)")
                let before = fingerprint()
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: next.frame.midX, dy: next.frame.midY)).tap()
                pause(0.45)
                // Nothing on screen moved: a button that does nothing, or one that only
                // vibrates. Listed for a look, not failed: a few are meant to (a selected tab).
                if app.alerts.count == 0, app.keyboards.count == 0, fingerprint() == before {
                    silent.append("\(screen) | \(next.label)")
                }
                fillFieldsIfAny()
                dismissForeignAlert()
            }
        }
        if relaunchIfDead(mode: mode, account: account, env: env, context: "at the end of the crawl") { note("relaunched") }
        note("crawl done after \(taps) taps")
        let report = "\(taps) taps, \(silent.count) without a visible change\n\n" + silent.joined(separator: "\n")
        try? report.write(toFile: "\(Self.outputDir)/silent-taps-\(name.filter(\.isLetter)).txt", atomically: true, encoding: .utf8)
    }


    /// Everything readable on screen and the state of every control, to tell whether a tap did anything.
    private func fingerprint() -> String {
        guard let root = try? app.snapshot() else { return "" }
        let screen = root.frame
        var parts: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.frame.intersection(screen).width > 2, !node.label.isEmpty || node.value != nil {
                parts.append("\(node.elementType.rawValue)|\(node.label)|\(String(describing: node.value))|\(node.isSelected)|\(Int(node.frame.minY))")
            }
            node.children.forEach(walk)
        }
        walk(root)
        return parts.joined(separator: "\n")
    }

    func screenName() -> String {
        let bar = app.navigationBars.firstMatch
        return bar.exists ? (bar.identifier.isEmpty ? bar.label : bar.identifier) : "?"
    }

    private func currentTargets() -> [Target] {
        guard let root = try? app.snapshot() else { return [] }
        let screen = root.frame
        var out: [Target] = []
        func walk(_ node: XCUIElementSnapshot) {
            switch node.elementType {
            case .button, .cell, .link, .switch, .segmentedControl, .slider, .stepper, .textField, .secureTextField, .textView, .menuItem:
                let text = node.label.isEmpty ? node.identifier : node.label
                let visible = node.frame.intersection(screen).width > 8 && node.frame.intersection(screen).height > 8
                if node.isEnabled, visible, !text.isEmpty, !Self.offLimits.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                    out.append(Target(label: "\(node.elementType.rawValue):\(text.prefix(40))", frame: node.frame, type: node.elementType))
                }
            default:
                break
            }
            if node.elementType != .keyboard { node.children.forEach(walk) }
        }
        walk(root)
        return out
    }

    private func fillFieldsIfAny() {
        // A keyboard can belong to QuickLook's own process (a PDF's text) or be on its way out:
        // then nothing of the app has the focus and typing fails.
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == 1")).firstMatch
        guard app.keyboards.count > 0, focused.exists else { return }
        focused.typeText("Test 12")
        note("typed in a field")
    }

    private func dismissForeignAlert() {
        // A tap on the app gives the interruption monitor its chance.
        if app.alerts.count > 0, let cancel = ["Abbrechen", "Cancel", "OK"].first(where: { app.alerts.buttons[$0].exists }) {
            app.alerts.buttons[cancel].tap()
            note("alert closed with \(cancel)")
        }
    }

    // ── A walk over the main screens, quicker than the crawl ─────────────────

    /// What the hub's tiles start with; the rest of their label is their description.
    static let hubTiles = ["Nachrichten", "Abwesenheiten", "To-dos", "Erinnerungen", "Klassenbuch", "Klasse"]

    /// Taps what starts with `prefix`. False when nothing does.
    @discardableResult
    func tapStarting(_ prefix: String, timeout: TimeInterval = 1) -> Bool {
        let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        guard arrives(target, timeout: timeout) else { note("missing: \(prefix)"); return false }
        note("tap \(prefix)")
        tapBlindly(target)
        pause(0.2)
        return true
    }

    private func closeIsUp() -> Bool {
        app.buttons["Schließen"].exists || app.buttons["Abbrechen"].exists
    }

    /// Opens up to `limit` rows of the screen one after the other and comes back from each, so the
    /// detail screens get the same data. A row that only expands stays put.
    func openRows(_ screen: String, limit: Int, mode: String, account: String?, env: [String: String] = [:]) {
        for index in 0..<limit {
            let rows = currentTargets().filter { target in
                guard target.type == .button || target.type == .cell else { return false }
                let label = target.label.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                return target.frame.minY > 130 && target.frame.height > 28 && target.frame.width > 44
                    && !tabs.contains(label) && !Self.chrome.contains(where: { label.hasPrefix($0) })
            }
            guard rows.indices.contains(index) else { return }
            let row = rows[index]
            let before = screenName(), closable = closeIsUp()
            note("row \(index) on \(screen): \(row.label)")
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: row.frame.midX, dy: row.frame.midY)).tap()
            pause(0.6)
            dismissForeignAlert()
            if relaunchIfDead(mode: mode, account: account, env: env, context: "in row \(index) of \(screen)") { return }
            if screenName() != before || closeIsUp() != closable { backOrClose(); pause(0.2) }
        }
    }

    /// Bars and switches around the content, not content.
    private static let chrome = ["Seitenleiste", "Suchen", "Profil", "Benachrichtigungen", "Startseite anordnen", "Exportieren", "Nächste Woche", "Vorherige Woche",
                                 "Woche", "Tag", "Schließen", "Mehr", "Neu", "Abmelden", "Alles löschen", "Konto löschen", "Offline-Kopien"]

    /// Every tab and hub tile, the first rows of each with their details, bell, profile, settings,
    /// devices. For the data modes: what they break shows on a screen with data, not on a menu.
    func walkMainScreens(mode: String, account: String? = "anna", env: [String: String] = [:], rows: Int = 2) {
        for name in tabs where element(name).exists {
            tap(name)
            pause(0.7)
            if relaunchIfDead(mode: mode, account: account, env: env, context: "on tab \(name)") { continue }
            if name == "Stundenplan" {
                // Both views, and a week either way.
                tap("Tag", timeout: 0.5)
                pause(0.4)
                tap("Woche", timeout: 0.5)
                pause(0.4)
                tap("Nächste Woche", timeout: 0.5)
                pause(0.5)
                tap("Vorherige Woche", timeout: 0.5)
                pause(0.3)
            }
            openRows(name, limit: name == "Home" ? rows + 2 : rows, mode: mode, account: account, env: env)
            leaveEverything()
        }
        for tile in Self.hubTiles {
            guard element("Schule").exists else { break }
            tap("Schule")
            guard tap(tile) else { continue }
            pause(0.8)
            if relaunchIfDead(mode: mode, account: account, env: env, context: "on \(tile)") { continue }
            openRows(tile, limit: rows, mode: mode, account: account, env: env)
            leaveEverything()
        }
        guard element("Home").exists else {
            assertAlive("after the walk in mode \(mode)")
            return
        }
        tap("Home")
        if tapStarting("Benachrichtigungen") {
            pause(0.8)
            _ = relaunchIfDead(mode: mode, account: account, env: env, context: "in the bell")
            leaveEverything()
        }
        if element("Profil").exists {
            tap("Profil")
            pause(0.7)
            _ = relaunchIfDead(mode: mode, account: account, env: env, context: "in the profile")
            tap("Einstellungen", timeout: 0.5)
            pause(0.6)
            _ = relaunchIfDead(mode: mode, account: account, env: env, context: "in the settings")
            for _ in 0..<3 where !tapStarting("Geräte", timeout: 0.2) { app.swipeUp(); pause(0.2) }
            pause(0.8)
            _ = relaunchIfDead(mode: mode, account: account, env: env, context: "on the devices")
            leaveEverything()
        }
        assertAlive("after the walk in mode \(mode)")
    }
}
