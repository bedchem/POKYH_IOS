import Foundation
import UIKit

/// Nutzungsstatistik fürs Admin-Panel: wie lange POKYH im Vordergrund ist und auf welcher
/// Plattform. In der Datenschutzerklärung unter „Nutzungsstatistik" beschrieben.
///
/// - Nur angemeldet; ohne POKYH-Konto wird nichts gesendet.
/// - Pro Besuch eine zufällige ID, nur im Speicher — keine Geräte-ID, nichts auf der Platte.
/// - Etwa einmal pro Minute im Vordergrund ein Ping mit den Vordergrund-Sekunden und den
///   geöffneten Tabs seit dem letzten, und ein letzter beim Wechsel in den Hintergrund.
/// - War die App länger als 30 Minuten im Hintergrund, beginnt ein neuer Besuch.
@MainActor
final class UsageReporter {
    static let shared = UsageReporter()

    private let pingInterval: TimeInterval = 60
    private let newVisitAfter: TimeInterval = 30 * 60

    /// Liefert das angemeldete Konto; ohne Konto wird nicht gemessen.
    private weak var state: AppState?

    private var visitId: String?
    private var visitUid: String?
    private var foregroundSince: Date?
    private var backgroundedAt: Date?
    private var pendingSeconds: TimeInterval = 0
    private var pendingScreens = 0
    private var timer: Timer?

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
        send(final: false)
    }

    func appEnteredBackground() {
        timer?.invalidate()
        timer = nil
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
        // Das Backend nimmt nur [0-9A-Za-z.+_-] bis 32 Zeichen an.
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
            // Zeit unter einem anderen Konto (oder abgemeldet) gehört nicht zu diesem.
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

        // Der letzte Ping beim Wechsel in den Hintergrund bekommt etwas Laufzeit, damit
        // iOS die App nicht anhält, bevor er raus ist.
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

/// Eine kurze Hintergrund-Laufzeit für einen letzten Request.
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
