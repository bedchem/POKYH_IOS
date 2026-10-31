import Combine
import Foundation
import PokyhCore
import UIKit
@preconcurrency import UserNotifications

// ── Kinds and switches ───────────────────────────────────────────────────────

/// What POKYH can notify about. Messages, to-dos and reminders also come as push from the
/// backend; grades and cancelled lessons only from the checks on this phone.
nonisolated enum NotificationKind: String, CaseIterable, Sendable {
    case messages, grades, cancellations, todos, reminders

    /// The backend's thread-id for its pushes (pushNotices.ts), ours for the local ones.
    var thread: String {
        switch self {
        case .messages: "messages"
        case .grades: "grades"
        case .cancellations: "timetable"
        case .todos: "todos"
        case .reminders: "reminders"
        }
    }

    init?(thread: String) {
        guard let kind = Self.allCases.first(where: { $0.thread == thread }) else { return nil }
        self = kind
    }
}

/// One switch per kind, on this phone only. Everything starts on.
nonisolated enum NotificationPrefs {
    private static func key(_ kind: NotificationKind) -> String { "pokyh_notify_\(kind.rawValue)" }

    static func isOn(_ kind: NotificationKind) -> Bool {
        UserDefaults.standard.object(forKey: key(kind)) as? Bool ?? true
    }

    static func store(_ kind: NotificationKind, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: key(kind))
    }
}

/// What the backend pushes to this phone right now, so the local checks don't say it twice.
nonisolated enum PushCoverage {
    private static let key = "pokyh_push_covered"

    static func covers(_ kind: NotificationKind) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(kind.rawValue)
    }

    static func set(_ kinds: Set<NotificationKind>) {
        UserDefaults.standard.set(kinds.map(\.rawValue).sorted(), forKey: key)
    }

    /// Whether this phone has to show the kind itself.
    static func local(_ kind: NotificationKind) -> Bool {
        NotificationPrefs.isOn(kind) && !covers(kind)
    }
}

/// The switches' labels, and the one local text the shared tables don't have.
nonisolated struct NotificationText: Sendable {
    let messages: String
    let messagesHint: String
    let grades: String
    let gradesHint: String
    let cancellations: String
    let cancellationsHint: String
    let todos: String
    let todosHint: String
    let reminders: String
    let remindersHint: String
    let classReminder: String

    func title(_ kind: NotificationKind) -> String {
        switch kind {
        case .messages: messages
        case .grades: grades
        case .cancellations: cancellations
        case .todos: todos
        case .reminders: reminders
        }
    }

    func hint(_ kind: NotificationKind) -> String {
        switch kind {
        case .messages: messagesHint
        case .grades: gradesHint
        case .cancellations: cancellationsHint
        case .todos: todosHint
        case .reminders: remindersHint
        }
    }

    static func of(_ lang: Lang) -> NotificationText {
        switch lang {
        case .de: de
        case .it: it
        case .en: en
        }
    }

    static let de = NotificationText(
        messages: "Nachrichten", messagesHint: "Neue Mitteilungen aus WebUntis.",
        grades: "Noten", gradesHint: "Sobald eine neue Note eingetragen ist.",
        cancellations: "Stundenausfälle", cancellationsHint: "Wenn eine deiner Stunden entfällt.",
        todos: "To-dos", todosHint: "Wenn ein To-do fällig wird.",
        reminders: "Erinnerungen", remindersHint: "Die Erinnerungen deiner Klasse.",
        classReminder: "Klassen-Erinnerung"
    )

    static let it = NotificationText(
        messages: "Messaggi", messagesHint: "Nuove comunicazioni da WebUntis.",
        grades: "Voti", gradesHint: "Appena viene inserito un nuovo voto.",
        cancellations: "Ore saltate", cancellationsHint: "Quando una delle tue ore viene annullata.",
        todos: "To-do", todosHint: "Quando un to-do è in scadenza.",
        reminders: "Promemoria", remindersHint: "I promemoria della tua classe.",
        classReminder: "Promemoria di classe"
    )

    static let en = NotificationText(
        messages: "Messages", messagesHint: "New messages from WebUntis.",
        grades: "Grades", gradesHint: "As soon as a new grade is entered.",
        cancellations: "Cancelled lessons", cancellationsHint: "When one of your lessons is cancelled.",
        todos: "To-dos", todosHint: "When a to-do is due.",
        reminders: "Reminders", remindersHint: "Your class’s reminders.",
        classReminder: "Class reminder"
    )
}

// ── Local notifications and the delegate ─────────────────────────────────────

/// Deliberately `nonisolated` with completion handlers: the center's callbacks run on any thread,
/// and under the project's default MainActor isolation they would abort at runtime otherwise.
nonisolated final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let seenKey = "pokyh_seen_message_ids"
    private let seenGradesKey = "pokyh_seen_grade_ids"
    private let seenCancelKey = "pokyh_seen_cancelled_lessons"
    private let askedKey = "pokyh_notif_asked"
    private let reminderPrefix = "reminder-"

    func configure() {
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UserDefaults.standard.set(true, forKey: askedKey)
    }

    // Banners in the foreground too, except for a kind switched off here. The backend can't tell
    // to-dos from reminders, so this is where a push it sent anyway stops while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        if notification.request.trigger is UNPushNotificationTrigger, content.threadIdentifier == NotificationKind.messages.thread {
            Task { @MainActor in PushRouter.shared.messagesArrived() }
        }
        if let kind = NotificationKind(thread: content.threadIdentifier), !NotificationPrefs.isOn(kind) {
            completionHandler([])
            return
        }
        completionHandler([.banner, .list, .sound, .badge])
    }

    // A tap opens what the notification is about.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let path = response.notification.request.content.userInfo["url"] as? String,
           let route = PushRoute(path: path) {
            Task { @MainActor in PushRouter.shared.offer(route) }
        }
        completionHandler()
    }

    private var strings: Strings { Strings.of(LanguageChoice.current(in: .standard)) }

    private func post(_ id: String, kind: NotificationKind, title: String, body: String, url: String, trigger: UNNotificationTrigger? = nil) {
        center.add(request(id, kind: kind, title: title, body: body, url: url, trigger: trigger))
    }

    private func request(_ id: String, kind: NotificationKind, title: String, body: String, url: String, trigger: UNNotificationTrigger?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = kind.thread
        content.userInfo = ["url": url]
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    // Reminders fire with the app closed too. Added inside the callback: removing the old ones
    // after adding would take the new ones with them, they share their identifiers.
    func scheduleReminders(_ reminders: [ApiReminder]) {
        var fresh: [UNNotificationRequest] = []
        if PushCoverage.local(.reminders) {
            let fallback = NotificationText.of(strings.lang).classReminder
            let now = Date()
            for r in reminders {
                guard let date = MessageFormat.parse(r.remindAt), date > now else { continue }
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                fresh.append(request("\(reminderPrefix)\(r.id)", kind: .reminders, title: r.title,
                                     body: r.body.isEmpty ? fallback : r.body, url: "/reminders/\(r.id)",
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }
        let center = center, prefix = reminderPrefix
        center.getPendingNotificationRequests { pending in
            let keep = Set(fresh.map(\.identifier))
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) && !keep.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            fresh.forEach { center.add($0) }
        }
    }

    /// Takes back what's still scheduled for a kind that's off or now comes from the backend.
    func withdrawReminders() {
        scheduleReminders([])
    }

    /// The next check only takes stock, so switching back on doesn't bring up everything since.
    /// Not for messages: the inbox is read either way, so their list is never behind.
    func forgetSeen(_ kind: NotificationKind) {
        switch kind {
        case .grades: UserDefaults.standard.removeObject(forKey: seenGradesKey)
        case .cancellations: UserDefaults.standard.removeObject(forKey: seenCancelKey)
        case .messages, .todos, .reminders: break
        }
    }

    // The list and the badge stay right even when nothing shows here, or a later switch to local
    // notifications would announce the whole inbox.
    func checkNewMessages(_ messages: [MessagePreview]) {
        let unread = messages.filter { !$0.isRead }
        let stored = UserDefaults.standard.array(forKey: seenKey) as? [Int] ?? []
        let seen = Set(stored)
        if !stored.isEmpty, PushCoverage.local(.messages) {
            for m in unread where !seen.contains(m.id) {
                post("msg-\(m.id)", kind: .messages, title: strings.system.newMessage,
                     body: m.subject.isEmpty ? m.senderName : "\(m.senderName): \(m.subject)", url: "/messages")
            }
        }
        UserDefaults.standard.set(Array(seen.union(messages.map { $0.id })), forKey: seenKey)
        center.setBadgeCount(unread.count)
    }

    /// The first run only takes stock, no alerts for old grades.
    func checkNewGrades(_ subjects: [SubjectGrades]) {
        let pairs: [(subject: String, grade: GradeEntry)] = subjects.flatMap { s in
            s.grades.filter { $0.markDisplayValue > 0 }.map { (s.subjectName, $0) }
        }
        let stored = UserDefaults.standard.array(forKey: seenGradesKey) as? [Int] ?? []
        let seen = Set(stored)
        if !stored.isEmpty, PushCoverage.local(.grades) {
            for p in pairs where !seen.contains(p.grade.id) {
                post("grade-\(p.grade.id)", kind: .grades, title: strings.system.newGrade,
                     body: "\(p.subject): \(Self.fmtMark(p.grade.markDisplayValue))", url: "/grades")
            }
        }
        UserDefaults.standard.set(Array(seen.union(pairs.map { $0.grade.id })), forKey: seenGradesKey)
    }

    /// Lessons from today on; each cancellation speaks up once.
    func checkTimetableChanges(_ entries: [TimetableEntry]) {
        let todayNum = Int(Self.dateNum(Date()))
        let cancelled = entries.filter { $0.isCancelled && $0.date >= todayNum }
        let stored = UserDefaults.standard.array(forKey: seenCancelKey) as? [String] ?? []
        let seen = Set(stored)
        func key(_ e: TimetableEntry) -> String { "\(e.date)-\(e.startTime)-\(e.lessonId)" }
        if !stored.isEmpty, PushCoverage.local(.cancellations) {
            for e in cancelled where !seen.contains(key(e)) {
                post("cancel-\(key(e))", kind: .cancellations, title: strings.system.lessonCancelled,
                     body: strings.system.cancelledBody(e.subjectName, Self.fmtDate(e.date), Self.fmtTime(e.startTime)),
                     url: "/timetable")
            }
        }
        // Past keys may stay: the list is small and they can't fire again.
        UserDefaults.standard.set(Array(seen.union(cancelled.map(key))), forKey: seenCancelKey)
    }

    private static func fmtMark(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        var str = String(format: "%.2f", r)
        while str.hasSuffix("0") { str.removeLast() }
        if str.hasSuffix(".") { str.removeLast() }
        return str.replacingOccurrences(of: ".", with: ",")
    }

    /// HHMM to "HH:MM".
    private static func fmtTime(_ hhmm: Int) -> String {
        String(format: "%02d:%02d", hhmm / 100, hhmm % 100)
    }

    /// YYYYMMDD to "DD.MM.".
    private static func fmtDate(_ yyyymmdd: Int) -> String {
        let mm = (yyyymmdd / 100) % 100, dd = yyyymmdd % 100
        return String(format: "%02d.%02d.", dd, mm)
    }

    private static func dateNum(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }
}

// ── Tapped notifications ─────────────────────────────────────────────────────

/// Where a notification leads, from its `url`: the backend's `/messages`, `/todos/<id>` and
/// `/reminders/<id>`, and the local checks' `/grades` and `/timetable`.
nonisolated enum PushRoute: Hashable, Identifiable, Sendable {
    case messages
    case todos
    case reminders(id: String?)
    case grades
    case timetable

    var id: String {
        switch self {
        case .messages: "messages"
        case .todos: "todos"
        case .reminders(let id): "reminders-\(id ?? "")"
        case .grades: "grades"
        case .timetable: "timetable"
        }
    }

    init?(path: String) {
        let parts = path.split(separator: "/").map(String.init)
        switch parts.first {
        case "messages": self = .messages
        case "todos": self = .todos
        case "reminders": self = .reminders(id: parts.count > 1 ? parts[1] : nil)
        case "grades": self = .grades
        case "timetable": self = .timetable
        default: return nil
        }
    }
}

/// The screen a tap asked for, until the signed-in app has gone there, as Android's
/// NotificationRoute: it waits through the lock screen and a cold start.
@MainActor
final class PushRouter: ObservableObject {
    static let shared = PushRouter()

    @Published private(set) var pending: PushRoute?
    /// Goes up when the backend pushed new messages while the app was open.
    @Published private(set) var inboxSignal = 0

    func offer(_ route: PushRoute) {
        pending = route
    }

    func take() -> PushRoute? {
        defer { pending = nil }
        return pending
    }

    func messagesArrived() {
        inboxSignal += 1
    }
}

// ── The device token on the backend ──────────────────────────────────────────

/// Keeps `/push/apns` in step with the account, the system permission and the switches.
/// Locking changes nothing, a locked phone keeps getting push; signing out takes the token back.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    /// What the backend holds for this phone, kept to take it back and to know what it covers.
    private struct Registered: Codable {
        var token: String
        var username: String
        var kinds: [String]
    }

    private let registeredKey = "pokyh_push_registered"
    private weak var app: AppState?
    private var observers: Set<AnyCancellable> = []
    private var deviceToken: String?
    /// The signed-in session, nil while locked or offline (those have no backend token).
    private var session: UserSession?
    /// Outlives the session by one turn of the run loop: "clear all data" drops it first.
    private var lastAuth: (username: String, token: String)?
    private var registered: Registered?
    /// The last request that went through in this run. Each launch sends once, each sign-in again.
    private var sent: Int?
    /// nil until the system was asked.
    private var allowed: Bool?
    private var tokenRequested = false
    private var queue: Task<Void, Never>?

    private init() {
        registered = UserDefaults.standard.data(forKey: registeredKey)
            .flatMap { try? JSONDecoder().decode(Registered.self, from: $0) }
    }

    /// The sinks run as the values are set, before AppState moves on to the next step of a sign-out.
    func attach(_ app: AppState) {
        guard self.app == nil else { return }
        self.app = app
        app.$session.sink { [weak self] in self?.sessionChanged($0) }.store(in: &observers)
        app.$accounts.dropFirst().sink { [weak self] in self?.dropIfSignedOut($0) }.store(in: &observers)
    }

    /// At launch, after the permission question, and back from the system settings.
    func appBecameActive() {
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            switch status {
            case .authorized, .provisional, .ephemeral:
                allowed = true
                if !tokenRequested {
                    tokenRequested = true
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .denied:
                allowed = false
                tokenRequested = false
            default:
                allowed = nil
            }
            sync()
        }
    }

    func received(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        sync()
    }

    func registrationFailed() {
        tokenRequested = false
    }

    func setEnabled(_ kind: NotificationKind, _ on: Bool) {
        NotificationPrefs.store(kind, on)
        if on {
            NotificationManager.shared.forgetSeen(kind)
        } else if kind == .reminders {
            NotificationManager.shared.withdrawReminders()
        }
        sync()
    }

    private func sessionChanged(_ new: UserSession?) {
        guard let new else {
            session = nil
            dropIfSignedOut(app?.accounts ?? [])
            DispatchQueue.main.async { [weak self] in
                if self?.session == nil { self?.lastAuth = nil }
            }
            return
        }
        guard let token = new.apiToken else {
            session = nil
            return
        }
        session = new
        lastAuth = (new.username, token)
        updateCoverage()
        sync()
    }

    /// Saved with its password: signed in, locked or not. Saved without: signed out. Never saved
    /// at all: gone as soon as it leaves the screen.
    private func isSignedOut(_ username: String, in accounts: [SavedAccount]) -> Bool {
        if AccountRoster.find(username, in: accounts) != nil {
            return !(app?.accountHasPassword(username) ?? false)
        }
        return !(session.map { AccountRoster.same($0.username, username) } ?? false)
    }

    private func dropIfSignedOut(_ accounts: [SavedAccount]) {
        guard let registered, isSignedOut(registered.username, in: accounts) else { return }
        unregister()
    }

    private func sync() {
        let previous = queue
        queue = Task {
            await previous?.value
            await reconcile()
        }
    }

    private func reconcile() async {
        guard let session, let apiToken = session.apiToken else { return }
        if allowed == false {
            unregister()
            return
        }
        guard allowed == true, let deviceToken else { return }

        let kinds = serverKinds(session)
        guard !kinds.isEmpty else {
            unregister()
            return
        }
        // Without a WebUntis session the backend has no inbox to poll, and only that stops messages.
        let polls = kinds.contains(.messages)
        let jsessionid = polls ? session.sessionId : nil
        let bearer = polls && !session.bearerToken.isEmpty && session.bearerToken.count <= 1000 ? session.bearerToken : nil

        var request = Hasher()
        request.combine(deviceToken)
        request.combine(session.username)
        request.combine(jsessionid)
        request.combine(bearer)
        request.combine(kinds)
        let signature = request.finalize()
        guard signature != sent else { return }

        do {
            try await BackendClient.shared.registerPush(
                deviceToken: deviceToken, environment: AppConfig.current.apnsEnvironment,
                kinds: kinds.map(\.rawValue).sorted(),
                jsessionid: jsessionid, bearerToken: bearer, token: apiToken)
            sent = signature
            registered = Registered(token: deviceToken, username: session.username, kinds: kinds.map(\.rawValue))
            persist()
            // Signed out while this was on its way.
            if isSignedOut(session.username, in: app?.accounts ?? []) {
                unregister(token: apiToken)
                return
            }
        } catch {
            let status = (error as? AppError)?.status
            // 503: the server has no APNs key. 404: a backend from before push. Nothing will
            // come from there, so this phone goes on watching everything itself.
            if status == 503 || status == 404 {
                registered = nil
                persist()
            // The session the backend still has may be stale, so this phone watches the inbox
            // itself again until a request goes through. To-dos and reminders don't depend on it.
            } else if var same = registered, AccountRoster.same(same.username, session.username) {
                same.kinds.removeAll { $0 == NotificationKind.messages.rawValue }
                registered = same
                persist()
            }
        }
        updateCoverage()
    }

    private func serverKinds(_ session: UserSession) -> Set<NotificationKind> {
        var kinds: Set<NotificationKind> = []
        if NotificationPrefs.isOn(.messages), session.hasUntis, !session.sessionId.isEmpty { kinds.insert(.messages) }
        if NotificationPrefs.isOn(.todos) { kinds.insert(.todos) }
        // The backend sends parents no reminders.
        if NotificationPrefs.isOn(.reminders), !session.isParent { kinds.insert(.reminders) }
        return kinds
    }

    /// The token's gone from here at once; without a backend token to ask with, the backend keeps
    /// it until the next sign-in moves it to that account.
    private func unregister(token: String? = nil) {
        guard let leaving = registered else {
            PushCoverage.set([])
            return
        }
        let auth = token ?? backendToken(for: leaving.username)
        registered = nil
        sent = nil
        persist()
        PushCoverage.set([])
        guard let auth else { return }
        let previous = queue
        queue = Task {
            await previous?.value
            try? await BackendClient.shared.unregisterPush(deviceToken: leaving.token, token: auth)
        }
    }

    private func backendToken(for username: String) -> String? {
        if let session, AccountRoster.same(session.username, username), let token = session.apiToken { return token }
        if let lastAuth, AccountRoster.same(lastAuth.username, username) { return lastAuth.token }
        return nil
    }

    private func updateCoverage() {
        guard let session else { return }
        guard allowed != false, let registered, AccountRoster.same(registered.username, session.username) else {
            PushCoverage.set([])
            return
        }
        PushCoverage.set(Set(registered.kinds.compactMap(NotificationKind.init(rawValue:))))
        if PushCoverage.covers(.reminders) { NotificationManager.shared.withdrawReminders() }
    }

    private func persist() {
        if let registered, let data = try? JSONEncoder().encode(registered) {
            UserDefaults.standard.set(data, forKey: registeredKey)
        } else {
            UserDefaults.standard.removeObject(forKey: registeredKey)
        }
    }
}
