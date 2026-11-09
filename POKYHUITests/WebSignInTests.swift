import XCTest

/// Signing a computer in with the website's code, opened as a link like the phone's camera does.
/// The computer can only renew its sign-in with the password, so it has to go along with the
/// app's WebUntis session and the school.
final class WebSignInTests: AppTestCase {
    private func stubLog() -> String {
        (try? String(contentsOfFile: "\(Self.outputDir)/stub.log", encoding: .utf8)) ?? ""
    }

    func testApproveHandsOverPasswordSessionAndSchool() {
        try? FileManager.default.removeItem(atPath: "\(Self.outputDir)/stub.log")
        launch()
        waitForTabs()

        let code = String(repeating: "aB3_", count: 8)
        app.open(URL(string: "pokyh-login:\(code)")!)
        XCTAssertTrue(see("Diesen Computer anmelden?", timeout: 8), "no question which computer")
        attachScreen("confirm computer")
        tap("Anmelden")
        XCTAssertTrue(see("Angemeldet", timeout: 8), "the computer isn't signed in")
        attachScreen("computer signed in")

        let approve = stubLog().split(separator: "\n").last { $0.hasPrefix("QR approve ") }.map(String.init) ?? ""
        let fields = Set(approve.dropFirst("QR approve ".count).split(separator: ",").map(String.init))
        for field in ["username", "password", "sessionId", "school", "school.loginName", "school.server", "school.name"] {
            XCTAssertTrue(fields.contains(field), "\(field) missing in what the computer gets: \(approve)")
        }
    }

    /// The phone's camera opens the link while the app is still locked: Face ID, the stored copy
    /// at once, the sign-in behind it still running. The link has to wait for that sign-in, not
    /// call the session expired.
    func testCameraLinkWhileSigningInBehind() {
        launch()
        waitForTabs()
        pause(1)
        app.terminate()
        try? FileManager.default.removeItem(atPath: "\(Self.outputDir)/stub.log")

        // Slow answers keep the sign-in behind the stored copy going for a while.
        launch(mode: "slow", account: nil, reset: false)
        let code = String(repeating: "cAm3", count: 8)
        app.open(URL(string: "pokyh-login:\(code)")!)
        waitForTabs(timeout: 25)
        pause(2)
        setMode("good")

        let expired = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Sitzung abgelaufen")).firstMatch
        XCTAssertTrue(see("Diesen Computer anmelden?", timeout: 30), "no question which computer after opening the link")
        XCTAssertFalse(expired.exists, "the link ran into an expired session")
        attachScreen("camera link confirm")
        tap("Anmelden")
        XCTAssertTrue(see("Angemeldet", timeout: 15), "the computer isn't signed in")
        XCTAssertFalse(expired.exists, "the approval ran into an expired session")

        let approve = stubLog().split(separator: "\n").last { $0.hasPrefix("QR approve ") }.map(String.init) ?? ""
        let fields = Set(approve.dropFirst("QR approve ".count).split(separator: ",").map(String.init))
        for field in ["username", "password", "sessionId", "school.loginName", "school.server"] {
            XCTAssertTrue(fields.contains(field), "\(field) missing in what the computer gets: \(approve)")
        }
    }
}
