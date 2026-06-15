import Foundation

#if os(iOS) || os(visionOS)
import BackgroundTasks

/// Hintergrund-Aktualisierung: ruft periodisch (von iOS getaktet, „best effort")
/// Nachrichten + Erinnerungen ab und feuert lokale Benachrichtigungen — auch wenn
/// die App geschlossen ist. Kein Echtzeit-Push (das bräuchte server-seitiges APNs).
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

    /// Leiser Abruf für das zuletzt aktive Konto (Passwort aus dem Keychain —
    /// `AfterFirstUnlock` erlaubt den Zugriff im Hintergrund).
    @MainActor
    private static func runSync() async {
        let store = CredentialStore.shared
        guard let username = store.lastActive ?? store.defaultUsername ?? store.accounts.first?.username,
              let password = store.password(for: username),
              let session = try? await UntisClient.shared.login(username: username, password: password)
        else { return }

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
    static func register() {}
    static func schedule() {}
}
#endif
