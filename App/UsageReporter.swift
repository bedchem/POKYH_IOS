import Foundation
import UIKit

/// Usage for the admin panel: how long POKYH is in the foreground and on which platform.
/// The privacy policy describes it under "Nutzungsstatistik".
///
/// - Signed in only; without a POKYH account nothing is sent.
/// - A random id per visit, in memory only: no device id, nothing on disk.
/// - A ping right when the app opens or someone signs in, then every 30 seconds in the
///   foreground with the seconds and tabs since the last one, and a last one when the app
///   goes to the background.
/// - After more than 30 minutes in the background a new visit starts.
@MainActor
final class UsageReporter {
    static let shared = UsageReporter()

    private let pingInterval: TimeInterval = 30
    private let newVisitAfter: TimeInterval = 30 * 60
    /// How often the foreground checks for a fresh sign-in (cheap).
    private let signInCheckInterval: TimeInterval = 1

    /// The signed-in account; without one nothing is measured.
    private weak var state: AppState?

    private var visitId: String?
    private var visitUid: String?
    private var foregroundSince: Date?
    private var backgroundedAt: Date?
    private var pendingSeconds: TimeInterval = 0
    private var pendingScreens = 0
    private var timer: Timer?
    private var signInTimer: Timer?

    private init() {}

    func attach(_ state: AppState) {
        self.state = state
    }

    func appBecameActive() {
        if let since = backgroundedAt, Date().timeIntervalSince(since) > newVisitAfter {
            visitId = nil
        }
        backgroundedAt = nil
        if foregroundSince == nil { foregroundSince = Date() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { _ in
            Task { @MainActor in UsageReporter.shared.send(final: false) }
        }
        // A sign-in (or a switch of account) starts the visit at once, not with the next ping,
        // so it shows up in the admin panel right away.
        signInTimer?.invalidate()
        signInTimer = Timer.scheduledTimer(withTimeInterval: signInCheckInterval, repeats: true) { _ in
            Task { @MainActor in UsageReporter.shared.startVisitIfSignedIn() }
        }
        send(final: false)
    }

    private func startVisitIfSignedIn() {
        guard let account, visitId == nil || visitUid != account.uid else { return }
        send(final: false)
    }

    func appEnteredBackground() {
        timer?.invalidate()
        timer = nil
        signInTimer?.invalidate()
        signInTimer = nil
        send(final: true)
        foregroundSince = nil
        backgroundedAt = Date()
    }

    /// Ein weiterer Tab/Bildschirm in diesem Besuch.
    func noteScreen() {
        pendingScreens += 1
    }

    private var account: (uid: String, token: String)? {
        guard let state, state.phase == .authed,
              let session = state.session,
              let uid = session.stableUid, !uid.isEmpty,
              let token = session.apiToken else { return nil }
        return (uid, token)
    }

    private var appVersion: String {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        // The backend takes [0-9A-Za-z.+_-], up to 32 characters.
        return String(raw.filter { $0.isASCII && ($0.isLetter || $0.isNumber || ".+_-".contains($0)) }.prefix(32))
    }

    private func send(final: Bool) {
        let now = Date()
        if let since = foregroundSince {
            pendingSeconds += now.timeIntervalSince(since)
            foregroundSince = final ? nil : now
        }

        guard let account else {
            visitId = nil
            visitUid = nil
            pendingSeconds = 0
            pendingScreens = 0
            return
        }
        if visitId == nil || visitUid != account.uid {
            // Time under another account, or signed out, isn't this one's.
            if visitId != nil {
                pendingSeconds = 0
                pendingScreens = 0
            }
            visitId = UUID().uuidString.lowercased()
            visitUid = account.uid
        }
        guard let visitId else { return }

        let seconds = Int(pendingSeconds.rounded(.down))
        pendingSeconds -= Double(seconds)
        let screens = pendingScreens
        pendingScreens = 0
        let version = appVersion

        // The last ping on the way to the background gets a little run time, so iOS doesn't
        // suspend the app before it's out.
        let background = final ? BackgroundTask.begin() : nil
        Task {
            await BackendClient.shared.usagePing(
                sessionId: visitId,
                activeSeconds: seconds,
                screens: screens,
                appVersion: version,
                token: account.token
            )
            background?.end()
        }
    }
}

/// A short stretch of background time for one last request.
@MainActor
private final class BackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    static func begin() -> BackgroundTask {
        let task = BackgroundTask()
        task.id = UIApplication.shared.beginBackgroundTask(withName: "usage-ping") { [weak task] in
            task?.end()
        }
        return task
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
