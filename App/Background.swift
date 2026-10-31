import Foundation

#if os(iOS) || os(visionOS)
import BackgroundTasks

/// Background refresh, timed by iOS and best effort, while the app lies unlocked in the
/// background. The backend pushes messages, to-dos and reminders; it knows nothing of grades or
/// cancelled lessons, so those are only ever noticed here and in the foreground sync.
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

    /// Grades load subject by subject, too much for every run. Same pace as the foreground sync.
    private static var lastHeavyCheck = Date.distantPast
    private static let heavyCheckInterval: TimeInterval = 30 * 60

    /// Only while the app is unlocked: passwords sit behind Face ID, which can't be asked for in
    /// the background, and a locked app shouldn't fetch anything.
    @MainActor
    private static func runSync() async {
        guard let session = liveSession?() else { return }

        // Read even when the backend sends the banners: the badge and the seen list stay right.
        if let inbox = try? await UntisClient.shared.messages(folder: .inbox, session) {
            NotificationManager.shared.checkNewMessages(inbox)
        }
        if let token = session.apiToken, let classId = session.classId,
           let reminders = try? await BackendClient.shared.reminders(classId: classId, token: token) {
            NotificationManager.shared.scheduleReminders(reminders)
        }

        guard !Task.isCancelled, Date().timeIntervalSince(lastHeavyCheck) > heavyCheckInterval else { return }
        lastHeavyCheck = Date()
        if session.isStudent, NotificationPrefs.isOn(.grades),
           let subjects = try? await UntisClient.shared.grades(year: nil, session) {
            NotificationManager.shared.checkNewGrades(subjects)
        }
        if !Task.isCancelled, session.hasUntis, NotificationPrefs.isOn(.cancellations),
           let entries = try? await UntisClient.shared.timetable(date: SchoolDates.todayISO(), session) {
            NotificationManager.shared.checkTimetableChanges(entries)
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
