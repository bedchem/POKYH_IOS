import Foundation
import Observation
import PokyhCore
import WatchConnectivity

/// What the settings show about the watch. WatchConnectivity tells us when any of it changes.
@MainActor
@Observable
final class WatchPairing {
    enum State: Equatable {
        /// Not activated yet, so we can't tell.
        case checking
        /// iPad or a phone without WatchConnectivity.
        case unsupported
        case notPaired
        /// Paired, but the POKYH watch app isn't on it.
        case appMissing
        case ready
    }

    fileprivate(set) var state: State = .checking
    fileprivate(set) var lastSent: Date?

    var canSend: Bool { state == .ready }
}

/// The iPhone's side of the hand-off: whenever the account changes, the watch hears about it.
/// applicationContext always holds the latest state (also for a watch app installed later),
/// userInfo queues the change so it arrives even if the watch is off right now.
///
/// The same context carries the watch's snapshot of the day. Each load in the app replaces its
/// part of it, and the watch can ask for a fresh one or send a ticked to-do.
@MainActor
final class WatchLink: NSObject {
    let pairing = WatchPairing()
    private let store: AccountStore
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    /// Tapped "connect" before the session was up; send once it is.
    private var resendWhenActive = false
    /// What the watch last got (or will get once the send below goes out).
    private(set) var snapshot: WatchSnapshot?
    /// Home loads its parts at the same time; they go out together.
    private var pendingSend: Task<Void, Never>?
    private var lastWatchRefresh = Date.distantPast

    init(store: AccountStore) {
        self.store = store
        super.init()
        if session == nil { pairing.state = .unsupported }
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func signedIn(_ account: StoredAccount) {
        if let snapshot, !AccountRoster.same(snapshot.username, account.username) { self.snapshot = nil }
        send(AccountHandoff(account: account))
    }

    func signedOut() {
        snapshot = nil
        pendingSend?.cancel()
        send(AccountHandoff(account: nil))
    }

    /// Sends the stored account again, both ways. Returns false when no watch can take it.
    @discardableResult
    func resend() -> Bool {
        guard let session else { return false }
        guard session.activationState == .activated else {
            resendWhenActive = true
            session.activate()
            return true
        }
        refreshPairing()
        guard pairing.canSend else { return false }
        let handoff = currentHandoff()
        try? session.updateApplicationContext(context(handoff))
        session.transferUserInfo(handoff.payload)
        pairing.lastSent = .now
        return true
    }

    private func send(_ handoff: AccountHandoff) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(context(handoff))
        session.transferUserInfo(handoff.payload)
        pairing.lastSent = .now
    }

    /// The account, plus the snapshot when it's that account's.
    private func context(_ handoff: AccountHandoff) -> [String: Any] {
        var payload = handoff.payload
        if let snapshot, let account = handoff.account, AccountRoster.same(snapshot.username, account.username) {
            payload.merge(snapshot.payload) { $1 }
        }
        return payload
    }

    // MARK: Snapshot

    /// Changes the snapshot of `username`, if that's the account the watch has.
    func updateSnapshot(for username: String, _ change: (inout WatchSnapshot) -> Void) {
        guard let account = store.load(), AccountRoster.same(account.username, username) else { return }
        var next = snapshot.flatMap { AccountRoster.same($0.username, username) ? $0 : nil } ?? .empty(for: account.username)
        change(&next)
        next.updatedAt = .now
        next.source = .phone
        next.lang = LanguageChoice.current(in: .standard)
        snapshot = next
        scheduleSend()
    }

    /// The account the watch has, for parts that don't come with a session (the Mensa).
    var accountUsername: String? { store.load()?.username }

    private func scheduleSend() {
        pendingSend?.cancel()
        pendingSend = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.sendSnapshot()
        }
    }

    private func sendSnapshot() {
        pendingSend?.cancel()
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              store.changedAt != nil else { return }
        try? session.updateApplicationContext(context(currentHandoff()))
    }

    /// Picks up what was sent before the app was last closed, so a load adds to it.
    private func restoreSnapshot() {
        guard snapshot == nil, let session, let account = store.load(),
              let sent = WatchSnapshot(payload: session.applicationContext),
              AccountRoster.same(sent.username, account.username) else { return }
        snapshot = sent
    }

    /// The watch asked: load what the app would show, unless that just happened. Only while
    /// the app is unlocked, the same rule as for background refresh.
    fileprivate func refreshForWatch() async {
        guard Date().timeIntervalSince(lastWatchRefresh) > 30,
              let live = BackgroundRefresh.liveSession?(),
              let account = store.load(), AccountRoster.same(account.username, live.username) else { return }
        lastWatchRefresh = Date()
        await WatchSync.load(live)
        sendSnapshot()
    }

    /// A to-do ticked on the watch, saved the way the To-dos screen saves it.
    fileprivate func apply(_ toggle: TodoToggle) async -> TodoToggleResult {
        guard let live = BackgroundRefresh.liveSession?(), let token = live.apiToken,
              let account = store.load(), AccountRoster.same(account.username, live.username) else { return .later }
        let result: TodoToggleResult
        do {
            try await BackendClient.shared.updateTodo(username: live.username, id: toggle.id, done: toggle.done, doneAt: toggle.doneAt, token: token)
            result = .applied
            updateSnapshot(for: live.username) { snapshot in
                if let i = snapshot.todos.firstIndex(where: { $0.id == toggle.id }) { snapshot.todos[i].done = toggle.done }
            }
        } catch let error as AppError where (400..<500).contains(error.status ?? 0) && error.status != 401 {
            // Gone or not this account's: what the backend has is what counts.
            result = .rejected
        } catch {
            return .later
        }
        if let todos = try? await BackendClient.shared.todos(username: live.username, token: token) {
            WatchSync.todos(todos, for: live)
        }
        sendSnapshot()
        return result
    }

    /// What the watch gets when it asks.
    fileprivate func currentHandoff() -> AccountHandoff {
        AccountHandoff(account: store.load(), sentAt: store.changedAt ?? .now)
    }

    fileprivate func refreshPairing() {
        guard let session else {
            pairing.state = .unsupported
            return
        }
        guard session.activationState == .activated else {
            pairing.state = .checking
            return
        }
        if !session.isPaired {
            pairing.state = .notPaired
        } else if !session.isWatchAppInstalled {
            pairing.state = .appMissing
        } else {
            pairing.state = .ready
        }
    }

    /// Re-sends the current state once the session is up, e.g. after the watch app was installed.
    fileprivate func syncCurrentState() {
        refreshPairing()
        restoreSnapshot()
        if resendWhenActive, session?.activationState == .activated {
            resendWhenActive = false
            resend()
            return
        }
        guard store.changedAt != nil else { return }
        let handoff = currentHandoff()
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(context(handoff))
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.syncCurrentState() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.syncCurrentState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = ReplyHandler(replyHandler)
        if AccountHandoff.isRequest(message) {
            Task { @MainActor in reply.call(self.currentHandoff().payload) }
        } else if WatchRequest.isSnapshotRequest(message) {
            // What we have right away; anything newer follows as applicationContext.
            Task { @MainActor in
                reply.call(self.snapshot?.payload ?? [:])
                await self.refreshForWatch()
            }
        } else if let toggle = TodoToggle(payload: message) {
            Task { @MainActor in
                let result = await self.apply(toggle)
                reply.call(result.reply(with: self.snapshot))
            }
        } else {
            replyHandler([:])
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.refreshPairing() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch: start over with that one.
        session.activate()
    }
}

nonisolated private struct ReplyHandler: @unchecked Sendable {
    let call: ([String: Any]) -> Void

    init(_ call: @escaping ([String: Any]) -> Void) {
        self.call = call
    }
}

/// The school this build signs in to, from Info.plist, until the school search lands on iOS.
enum DefaultSchool {
    static var loginName: String { Config.school }
    static var server: String { info("POKYHDefaultUntisServer") }
    static var name: String {
        let name = info("POKYHDefaultSchoolName")
        return name.isEmpty ? loginName : name
    }

    static var school: PokyhCore.School {
        PokyhCore.School(loginName: loginName, server: server, name: name)
    }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}

/// What the rest of the app calls: sign-in and sign-out in AppState end up on the watch.
@MainActor
enum WatchSync {
    enum PairResult {
        case sent
        /// No paired watch, or POKYH isn't installed on it.
        case noWatch
        /// Nothing signed in that the watch could take over.
        case noAccount
    }

    private static let accounts = AccountStore(store: KeychainStore(service: AppConfig.current.appBundleID))
    private static let link = WatchLink(store: accounts)

    /// Paired? App installed? Last sent? For the settings.
    static var pairing: WatchPairing { link.pairing }

    static func start() {
        link.activate()
    }

    static func signedIn(username: String, displayName: String, password: String) {
        let account = StoredAccount(username: username, displayName: displayName, school: school(of: username), secret: password)
        try? accounts.save(account)
        link.signedIn(account)
    }

    /// The account's own school first: the last one picked may be another account's, and the
    /// watch signs in by itself with what it gets here.
    private static func school(of username: String) -> PokyhCore.School {
        CredentialStore.savedSchool(for: username) ?? SchoolChoice.read() ?? DefaultSchool.school
    }

    /// "Connect now" in the settings: hands the signed-in account to the watch again. Accounts
    /// signed in before the watch existed have nothing stored yet, so the caller may pass one.
    @discardableResult
    static func pairNow(username: String? = nil, displayName: String? = nil, password: String? = nil) -> PairResult {
        var account = accounts.load()
        if let username, let password, !password.isEmpty, account?.username != username {
            account = StoredAccount(username: username, displayName: displayName ?? username, school: school(of: username), secret: password)
        }
        guard let account else { return .noAccount }
        // A fresh timestamp, so the watch takes it even over a sign-out it heard earlier.
        try? accounts.save(account)
        return link.resend() ? .sent : .noWatch
    }

    /// Only if it's the account the watch has; switching between saved accounts doesn't count.
    static func signedOut(username: String? = nil) {
        if let username, accounts.load()?.username != username { return }
        try? accounts.clear()
        link.signedOut()
    }

    // MARK: What the watch shows

    // The screens call these after a successful load, so a failed one never blanks the watch.
    // An offline session has no token and reads the disk cache: nothing new for the watch.

    /// A week of timetable. `week` is its Monday; only the current week says anything about today.
    static func timetable(_ entries: [TimetableEntry], week: String, for session: UserSession) {
        guard !session.bearerToken.isEmpty, week == SchoolDates.mondayISO(of: Date()) else { return }
        let lessons = WatchSnapshotBuilder.lessons(entries, on: SchoolDates.todayNum())
        let day = Calendar.current.startOfDay(for: Date())
        link.updateSnapshot(for: session.username) { snapshot in
            snapshot = snapshot.withLessons(lessons, day: day, studentId: session.studentId)
        }
    }

    static func grades(_ subjects: [SubjectGrades], for session: UserSession) {
        guard !session.bearerToken.isEmpty else { return }
        let grades = WatchSnapshotBuilder.grades(subjects)
        link.updateSnapshot(for: session.username) { snapshot in
            snapshot.overallAverage = grades.overall
            snapshot.gradeCount = grades.count
            snapshot.subjects = grades.subjects
            snapshot.recentGrades = grades.recent
        }
    }

    static func mensa(_ dishes: [Dish]) {
        guard let username = link.accountUsername else { return }
        let menu = WatchSnapshotBuilder.menu(dishes)
        link.updateSnapshot(for: username) { snapshot in
            snapshot.mensaDay = menu.day
            snapshot.dishes = menu.dishes
        }
    }

    static func todos(_ todos: [ApiTodo], for session: UserSession) {
        let list = WatchSnapshotBuilder.todos(todos)
        link.updateSnapshot(for: session.username) { $0.todos = list }
    }

    /// Everything at once, when the watch asks. The clients keep what the screens just loaded
    /// for a few minutes, so this rarely costs a request.
    static func load(_ session: UserSession) async {
        async let menu: () = loadMenu()
        async let tasks: () = loadTodos(session)
        if session.hasUntis, !session.bearerToken.isEmpty {
            async let week: () = loadWeek(session)
            async let marks: () = loadGrades(session)
            _ = await (week, marks)
        }
        _ = await (menu, tasks)
    }

    private static func loadMenu() async {
        if let dishes = try? await BackendClient.shared.dishes() { mensa(dishes) }
    }

    private static func loadTodos(_ session: UserSession) async {
        guard let token = session.apiToken,
              let list = try? await BackendClient.shared.todos(username: session.username, token: token) else { return }
        todos(list, for: session)
    }

    private static func loadWeek(_ session: UserSession) async {
        let monday = SchoolDates.mondayISO(of: Date())
        if let entries = try? await UntisClient.shared.timetable(date: monday, session) {
            timetable(entries, week: monday, for: session)
        }
    }

    private static func loadGrades(_ session: UserSession) async {
        if let subjects = try? await UntisClient.shared.grades(year: nil, session) {
            grades(subjects, for: session)
        }
    }
}

/// The app's models into the watch's small ones, picked the way Home picks them.
enum WatchSnapshotBuilder {
    /// Keeps the context small; nobody scrolls further on a wrist.
    private static let maxTodos = 30
    private static let maxRecentGrades = 5

    static func lessons(_ entries: [TimetableEntry], on day: Int) -> [WatchSnapshot.Lesson] {
        entries.filter { $0.date == day }.compactMap { entry in
            guard let start = UntisTime.date(entry.date, entry.startTime),
                  let end = UntisTime.date(entry.date, entry.endTime) else { return nil }
            let originalRoom = entry.originalRoom.flatMap { $0.isEmpty ? nil : $0 }
            return WatchSnapshot.Lesson(
                id: "\(entry.id)-\(entry.date)-\(entry.startTime)",
                subject: entry.subjectName,
                subjectLong: entry.subjectLong,
                teacher: entry.teacherName,
                room: entry.roomName,
                start: start,
                end: end,
                status: .of(cancelled: entry.isCancelled, exam: entry.isExam, substitution: entry.isSubstitution,
                            additional: entry.isAdditional, room: entry.roomName, originalRoom: originalRoom),
                originalTeacher: entry.originalTeacher.flatMap { $0.isEmpty ? nil : $0 },
                originalRoom: originalRoom,
                note: entry.note.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
            )
        }
    }

    /// A flat mean over every single grade, like Home and the Grades tab; newest by id, as the web does.
    static func grades(_ subjects: [SubjectGrades]) -> (overall: Double?, count: Int, subjects: [WatchSnapshot.SubjectAverage], recent: [WatchSnapshot.Grade]) {
        let values = subjects.flatMap { $0.grades.map(\.markDisplayValue) }.filter { $0 > 0 }
        let averages = subjects.compactMap { subject -> WatchSnapshot.SubjectAverage? in
            let marks = subject.grades.map(\.markDisplayValue).filter { $0 > 0 }
            guard !marks.isEmpty else { return nil }
            return WatchSnapshot.SubjectAverage(name: subject.subjectName, average: GradeMath.averageOf(marks), count: marks.count)
        }
        let recent = subjects
            .flatMap { subject in subject.grades.filter { $0.markDisplayValue > 0 }.map { (subject.subjectName, $0) } }
            .sorted { $0.1.id > $1.1.id }
            .prefix(maxRecentGrades)
            .map { WatchSnapshot.Grade(id: $0.1.id, subject: $0.0, value: $0.1.markDisplayValue, date: UntisTime.date($0.1.date, 0), text: $0.1.text) }
        return (values.isEmpty ? nil : GradeMath.averageOf(values), values.count, averages, Array(recent))
    }

    /// Same date rule as Home: today, or the next day the menu has.
    static func menu(_ dishes: [Dish]) -> (day: Date?, dishes: [WatchSnapshot.Dish]) {
        guard let day = MensaSchedule.days(from: dishes).first(where: { !$0.dishes.isEmpty }) else { return (nil, []) }
        return (day.date, day.dishes.map { WatchSnapshot.Dish(id: $0.id, name: $0.name, category: $0.category, tags: $0.tags) })
    }

    static func todos(_ todos: [ApiTodo]) -> [WatchSnapshot.Todo] {
        TodoOrder.arranged(todos).prefix(maxTodos).map {
            WatchSnapshot.Todo(id: $0.id, title: String($0.title.prefix(120)), due: $0.dueAt.flatMap(MessageFormat.parse), done: $0.done)
        }
    }
}
