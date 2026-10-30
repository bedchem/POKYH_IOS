import Foundation

#if os(iOS) || os(visionOS)
import BackgroundTasks

/// Hintergrund-Aktualisierung: ruft periodisch (von iOS getaktet, „best effort")
/// Nachrichten + Erinnerungen ab und feuert lokale Benachrichtigungen, solange die App
/// entsperrt im Hintergrund liegt. Everything else comes as APNs push from the backend.
enum BackgroundRefresh {
    static let identifier = Config.bgRefreshId

    /// Beim App-Start registrieren (aus `POKYHApp.init`).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(refresh)
        }
    }

    /// Nächsten Lauf einplanen (frühestens in ~15 Min — iOS entscheidet den Zeitpunkt).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // immer den nächsten Lauf nachlegen
        let work = Task { @MainActor in
            await runSync()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// The signed-in session, handed over by AppState; nil while the app is locked.
    static var liveSession: (() -> UserSession?)?

    /// Leiser Abruf, but only while the app is unlocked: passwords sit behind Face ID, which
    /// can't be asked for in the background, and a locked app shouldn't fetch anything.
    @MainActor
    private static func runSync() async {
        guard let session = liveSession?() else { return }

        if let inbox = try? await UntisClient.shared.messages(folder: .inbox, session) {
            NotificationManager.shared.checkNewMessages(inbox)
        }
        if let token = session.apiToken, let classId = session.classId,
           let reminders = try? await BackendClient.shared.reminders(classId: classId, token: token) {
            NotificationManager.shared.scheduleReminders(reminders)
        }
    }
}

#else
// macOS u. a.: kein BGTaskScheduler/BGAppRefreshTask → No-ops.
enum BackgroundRefresh {
    static var liveSession: (() -> UserSession?)?
    static func register() {}
    static func schedule() {}
}
#endif
