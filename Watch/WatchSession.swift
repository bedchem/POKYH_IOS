import Foundation
import Observation
import PokyhCore
import WatchConnectivity
import WatchKit
import WidgetKit

/// The watch's side of the iPhone link, and its own way to the servers when the phone can't
/// help. Signs in once with what the phone hands over and keeps the account in the watch's own
/// Keychain, so it stays signed in across launches and restarts until the phone says otherwise.
/// Loads lessons, grades, the Mensa and the to-dos by itself over Wi-Fi or cellular (see
/// `WatchLoader`), takes whatever the phone sends, and keeps the fresher part of both sealed on
/// disk. Ticked to-dos go to the phone, or straight to the backend when it's away.
@Observable
@MainActor
final class WatchSession: NSObject {
    static let shared = WatchSession(
        accounts: AccountStore(store: KeychainStore(service: AppConfig.current.appBundleID)),
        store: .shared(createsKey: true),
        backend: WatchSession.makeBackend()
    )

    /// How the watch gets its data right now.
    enum Connection: Equatable {
        /// The iPhone app answers.
        case phone
        /// The phone is away, the watch gets through by itself.
        case online
        /// Neither: what's on screen is what was last loaded.
        case offline

        var symbol: String {
            switch self {
            case .phone: "iphone"
            case .online: "wifi"
            case .offline: "wifi.slash"
            }
        }
    }

    private(set) var account: StoredAccount?
    /// The last snapshot with the not yet confirmed ticks on top: what the pages show.
    private(set) var snapshot: WatchSnapshot?
    private(set) var queue = TodoQueue()
    /// Whether the phone can be asked right now.
    private(set) var phoneReachable = false
    /// Whether the watch's own last load got through; nil before the first one.
    private var ownLoadReached: Bool?
    /// Signed out from the account's device list: the sign-in page says so.
    private(set) var signedOutHere = false
    /// Asking the phone or loading by itself, and at launch until the link to the phone is up.
    private var waitingFor = 0
    private var linkComingUp: Bool
    var loading: Bool { linkComingUp || waitingFor > 0 }

    var connection: Connection {
        if phoneReachable { return .phone }
        return ownLoadReached == false ? .offline : .online
    }

    /// How long the phone gets to answer with something newer before the watch loads by itself.
    private static let phoneGrace: Duration = .seconds(8)
    /// A phone that takes a message and never answers would keep the page spinning.
    private static let replyTimeout: Duration = .seconds(6)
    /// WebUntis gets a sign-in from here this often at most; a pull to refresh may go sooner.
    private static let untisInterval: TimeInterval = 10 * 60
    private static let untisIntervalForced: TimeInterval = 60
    /// The backend's to-dos and menu are cheaper, but still not on every glance.
    private static let backendInterval: TimeInterval = 2 * 60
    private static let backendIntervalForced: TimeInterval = 15
    /// Today and the week after it, enough to reach the next school day past a weekend.
    private static let ownLoadDays = 8
    /// The phone said "later" (locked, offline): don't ask it again right away.
    private static let queueHold: TimeInterval = 60
    /// The backend couldn't take a tick: try again after this, or with the next load.
    private static let directHold: TimeInterval = 30

    @ObservationIgnored private let accounts: AccountStore
    @ObservationIgnored private let store: WatchStore
    @ObservationIgnored private let backend: WatchBackend
    @ObservationIgnored private let loader: WatchLoader
    @ObservationIgnored private let session: WCSession? = WCSession.isSupported() ? .default : nil
    /// The snapshot as it came, without the ticks.
    @ObservationIgnored private var received: WatchSnapshot?
    @ObservationIgnored private var sending: Set<String> = []
    @ObservationIgnored private var queueHeldUntil = Date.distantPast
    @ObservationIgnored private var directHeldUntil = Date.distantPast
    @ObservationIgnored private var lastUntisLoad = Date.distantPast
    @ObservationIgnored private var lastBackendLoad = Date.distantPast
    @ObservationIgnored private var loadingByItself = false

    init(accounts: AccountStore, store: WatchStore, backend: WatchBackend) {
        self.accounts = accounts
        self.store = store
        self.backend = backend
        loader = WatchLoader(untis: UntisDay(), backend: backend)
        #if DEBUG
        WatchDemo.seed(accounts)
        #endif
        let account = accounts.load()
        self.account = account
        linkComingUp = account != nil && WCSession.isSupported()
        super.init()
        #if DEBUG
        if WatchDemo.isOn {
            self.account = WatchDemo.account
            linkComingUp = false
            received = WatchDemo.snapshot()
            snapshot = received
            return
        }
        #endif
        if let account, let saved = store.snapshot(), AccountRoster.same(saved.username, account.username) {
            received = saved
            queue = store.queue()
            snapshot = saved.applying(queue)
        }
        // Early, so a context arriving while the app runs in the background finds a delegate.
        session?.delegate = self
        session?.activate()
    }

    /// The watch as a device of its own at the backend, with the app's keys and its own id.
    private static func makeBackend() -> WatchBackend {
        let config = AppConfig.current
        let device = WKInterfaceDevice.current()
        let identity = DeviceIdentity(defaults: .standard, version: config.version,
                                      system: "\(device.systemName) \(device.systemVersion)", model: model)
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 20
        settings.httpCookieAcceptPolicy = .never
        settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        let client = BackendClient(config: config, device: identity,
                                   errors: Strings.of(LanguageChoice.current(in: .standard)).errors,
                                   session: URLSession(configuration: settings))
        return WatchBackend(client: client, store: KeychainStore(service: config.appBundleID),
                            defaultSchool: AppConfig.defaultSchool())
    }

    /// The hardware model ("Watch7,5"), the simulated one's in the simulator.
    private static let model: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    // MARK: What the pages call

    /// The app came on screen.
    func refresh() {
        Task { await reload(force: false) }
    }

    /// Sends what's waiting, then gets something newer: from the phone when it answers, else
    /// by itself. Returns when there's an answer, so a pull to refresh spins exactly that long.
    func reload(force: Bool = true) async {
        guard account != nil else { return }
        #if DEBUG
        if WatchDemo.isOn { return }
        #endif
        flushQueue()
        waitingFor += 1
        linkComingUp = false
        defer { waitingFor -= 1 }
        if let session, session.activationState == .activated, session.isReachable,
           let reply = await ask(WatchRequest.snapshot) {
            take(reply)
            // The phone answers with what it has; a locked one has nothing newer coming, so
            // whatever is still old after a moment is loaded here.
            Task {
                try? await Task.sleep(for: Self.phoneGrace)
                await self.loadByItself(force: false)
            }
        } else {
            await loadByItself(force: force)
        }
    }

    /// Ticks or unticks at once; the phone or the backend hears about it now or as soon as it can.
    func toggle(_ todo: WatchSnapshot.Todo) {
        guard let received else { return }
        let phoneSays = received.todos.first { $0.id == todo.id }?.done ?? todo.done
        queue.toggle(todo.id, to: !todo.done, phoneSays: phoneSays)
        store.save(queue)
        snapshot = received.applying(queue)
        queueHeldUntil = .distantPast
        directHeldUntil = .distantPast
        flushQueue()
    }

    func isQueued(_ todo: WatchSnapshot.Todo) -> Bool {
        queue.pending(for: todo.id) != nil
    }

    /// POKYH-only accounts have no timetable or grades.
    var hasUntis: Bool { account?.backend != .password }

    /// Teachers have no POKYH account and so no to-dos; an older phone didn't say.
    var hasTodos: Bool { account?.backend != .untisOnly || snapshot?.knows(.todos) == true }

    // MARK: Background

    /// Called for the background refresh the system grants. Grades wait for the app: they cost a
    /// request per subject and no complication shows them.
    func backgroundRefresh() async {
        await loadByItself(force: false, skipping: [.grades])
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        guard account != nil else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: WatchSnapshot.nextRefresh(after: .now), userInfo: nil
        ) { @Sendable _ in }
    }

    /// A context is being delivered in the background: stay up until it's here.
    func waitForDelivery() async {
        for _ in 0..<20 where session?.hasContentPending == true {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: Receiving

    private func receive(_ payload: [String: Any]) {
        // The phone speaking up by itself means it's unlocked again: the queue may go.
        queueHeldUntil = .distantPast
        if let handoff = AccountHandoff(payload: payload) { apply(handoff) }
        take(payload)
    }

    private func apply(_ handoff: AccountHandoff) {
        // Every snapshot comes with the same hand-off; no need to write the Keychain for that.
        if accounts.changedAt == handoff.sentAt, account == handoff.account { return }
        // Signed out from the device list: only a newer "connect" on the phone brings it back,
        // not the phone signing itself in again.
        if let incoming = handoff.account, let revokedAt = backend.revokedAt(of: incoming.username),
           (handoff.connectedAt ?? .distantPast) <= revokedAt {
            return
        }
        do {
            guard try handoff.apply(to: accounts) else { return }
        } catch {
            // Keychain refused (shouldn't happen on a real watch); keep what we had.
            return
        }
        let next = accounts.load()
        let sameAccount = next.flatMap { next in account.map { AccountRoster.same($0.username, next.username) } } ?? false
        if !sameAccount { forgetData() }
        account = next
        if next != nil { signedOutHere = false }
        scheduleBackgroundRefresh()
        if !sameAccount, next != nil { refresh() }
    }

    private func take(_ payload: [String: Any]) {
        guard let incoming = WatchSnapshot(payload: payload), let account,
              AccountRoster.same(incoming.username, account.username) else { return }
        if let received {
            guard let kept = received.taking(incoming) else { return }
            show(kept)
        } else {
            show(incoming)
        }
        flushQueue()
    }

    private func show(_ next: WatchSnapshot) {
        let before = received
        received = next
        queue.settle(with: next)
        store.save(queue)
        store.save(next)
        snapshot = next.applying(queue)
        // Reloads are rationed; only what the complications show counts.
        if before?.lessons != next.lessons || before?.nextDay != next.nextDay || before?.day != next.day || before?.lang != next.lang {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Signed out or another account: nothing of the old one stays on the watch, and its POKYH
    /// session ends, so the watch leaves the account's device list.
    private func forgetData() {
        received = nil
        snapshot = nil
        queue = TodoQueue()
        ownLoadReached = nil
        lastUntisLoad = .distantPast
        lastBackendLoad = .distantPast
        store.clear()
        WidgetCenter.shared.reloadAllTimelines()
        let backend = backend
        Task { await backend.forget() }
    }

    /// The account's device list signed this watch out. It stays out until the person connects
    /// it again on the phone.
    private func signedOutFromDeviceList() {
        try? accounts.clear()
        forgetData()
        account = nil
        signedOutHere = true
        WKInterfaceDevice.current().play(.failure)
    }

    /// No account yet: ask the phone, in case the watch app came after the sign-in.
    private func sessionIsUp() {
        guard let session, session.activationState == .activated else {
            linkComingUp = false
            return
        }
        phoneReachable = session.isReachable
        receive(session.receivedApplicationContext)
        if account == nil, session.isReachable {
            askPhone(AccountHandoff.request) { [weak self] reply in
                self?.receive(reply)
                self?.refresh()
            } failed: {
                // Phone went away; the applicationContext still arrives once it's back.
            }
        } else {
            refresh()
        }
    }

    // MARK: Sending

    private func flushQueue() {
        guard !queue.isEmpty else { return }
        let viaPhone = session.map { $0.activationState == .activated && $0.isReachable } == true && Date() >= queueHeldUntil
        for toggle in queue.items where !sending.contains(toggle.id) {
            if viaPhone {
                sending.insert(toggle.id)
                askPhone(toggle.payload) { [weak self] reply in
                    self?.finished(toggle, reply: reply)
                } failed: { [weak self] in
                    self?.sending.remove(toggle.id)
                    self?.sendDirectly(toggle)
                }
            } else {
                sendDirectly(toggle)
            }
        }
    }

    private func finished(_ toggle: TodoToggle, reply: [String: Any]) {
        sending.remove(toggle.id)
        switch TodoToggleResult(reply: reply) {
        case .later, nil:
            // Locked or offline phone: the watch's own connection may still get through.
            queueHeldUntil = Date().addingTimeInterval(Self.queueHold)
            sendDirectly(toggle)
        case .rejected:
            WKInterfaceDevice.current().play(.failure)
            drop(toggle)
        case .applied:
            drop(toggle)
        }
        take(reply)
    }

    /// Straight to the backend, the way the phone would have sent it.
    private func sendDirectly(_ toggle: TodoToggle) {
        guard let account, WatchBackend.canSignIn(account), !sending.contains(toggle.id), Date() >= directHeldUntil else { return }
        sending.insert(toggle.id)
        let backend = backend
        Task {
            do {
                try await backend.setTodo(toggle, for: account)
                sending.remove(toggle.id)
                guard isCurrent(account) else { return }
                drop(toggle)
                if let received { show(received.withTodo(toggle.id, done: toggle.done)) }
                await reloadTodos(for: account)
            } catch WatchBackendError.rejected {
                sending.remove(toggle.id)
                guard isCurrent(account) else { return }
                WKInterfaceDevice.current().play(.failure)
                drop(toggle)
                await reloadTodos(for: account)
            } catch {
                // Offline or no session yet: it stays queued; the next load signs in and sends it.
                sending.remove(toggle.id)
                directHeldUntil = Date().addingTimeInterval(Self.directHold)
            }
        }
    }

    /// The list as the backend has it after a tick, so the phone's ticks show up too.
    private func reloadTodos(for account: StoredAccount) async {
        let started = Date()
        guard let items = try? await backend.todos(for: account), isCurrent(account), let received,
              received.updated(.todos) <= started else { return }
        show(received.withTodos(WatchTodos.build(items, now: started), at: started))
    }

    /// Done with this tick, unless it was changed again while on its way.
    private func drop(_ toggle: TodoToggle) {
        guard queue.pending(for: toggle.id) == toggle else { return }
        queue.remove(toggle.id)
        store.save(queue)
        if let received { snapshot = received.applying(queue) }
    }

    private func ask(_ message: [String: Any]) async -> [String: Any]? {
        let reply: SendablePayload? = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            askPhone(message) { once.resume(SendablePayload($0)) } failed: { once.resume(nil) }
            Task {
                try? await Task.sleep(for: Self.replyTimeout)
                once.resume(nil)
            }
        }
        return reply?.value
    }

    /// Replies come in on a background queue. `nonisolated` keeps these closures from assuming
    /// the main actor, which would trap at runtime.
    nonisolated private func askPhone(_ message: [String: Any],
                                      reply: @escaping @MainActor @Sendable ([String: Any]) -> Void,
                                      failed: @escaping @MainActor @Sendable () -> Void) {
        WCSession.default.sendMessage(message) { @Sendable answer in
            let answer = SendablePayload(answer)
            Task { @MainActor in reply(answer.value) }
        } errorHandler: { @Sendable _ in
            Task { @MainActor in failed() }
        }
    }

    // MARK: Loading by itself

    /// Whatever is old, over the watch's own connection: the lessons of the coming week and the
    /// grades straight from WebUntis with the account the phone handed over, the to-dos and the
    /// menu from the backend. `force` (a pull to refresh) loads everything, sooner than usual.
    private func loadByItself(force: Bool, skipping skipped: Set<WatchSnapshot.Part> = []) async {
        guard let account, !loadingByItself else { return }
        let now = Date()
        let base = received ?? .empty(for: account.username)
        var parts = Set(WatchSnapshot.Part.allCases.filter { force || base.isStale($0, at: now) }).subtracting(skipped)
        if !hasUntis { parts.subtract([.lessons, .grades]) }
        if now.timeIntervalSince(lastUntisLoad) < (force ? Self.untisIntervalForced : Self.untisInterval) {
            parts.subtract([.lessons, .grades])
        }
        if now.timeIntervalSince(lastBackendLoad) < (force ? Self.backendIntervalForced : Self.backendInterval) {
            parts.subtract([.mensa, .todos])
        }
        guard !parts.isEmpty else { return }
        loadingByItself = true
        waitingFor += 1
        if !parts.isDisjoint(with: [.lessons, .grades]) { lastUntisLoad = now }
        if !parts.isDisjoint(with: [.mensa, .todos]) { lastBackendLoad = now }
        defer {
            loadingByItself = false
            waitingFor -= 1
        }
        // The phone's word on whose timetable it is comes first: a guardian's child.
        let load = await loader.load(parts, for: account, studentId: account.studentId ?? base.studentId,
                                     now: now, days: Self.ownLoadDays)
        // Signed out or switched meanwhile: what came belongs to nobody here.
        guard isCurrent(account) else { return }
        ownLoadReached = load.reachedNetwork
        if load.revoked {
            signedOutFromDeviceList()
            return
        }
        // No connection, or the school said no: the pages keep saying how old their data is.
        if !load.isEmpty {
            show(load.applied(to: received ?? .empty(for: account.username), at: now))
        }
        directHeldUntil = .distantPast
        flushQueue()
    }

    private func isCurrent(_ account: StoredAccount) -> Bool {
        self.account.map { AccountRoster.same($0.username, account.username) } ?? false
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.sessionIsUp() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.sessionIsUp() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let payload = SendablePayload(applicationContext)
        Task { @MainActor in self.receive(payload.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = SendablePayload(userInfo)
        Task { @MainActor in self.receive(payload.value) }
    }
}

/// Whichever comes first, the answer or the timeout, the other one finds nothing left to resume.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<SendablePayload?, Never>?

    init(_ continuation: CheckedContinuation<SendablePayload?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: SendablePayload?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

/// WatchConnectivity hands us property-list dictionaries; they're safe to pass to the main actor.
struct SendablePayload: @unchecked Sendable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }
}

/// The system wakes the app for two things: refreshing by itself and a context from the phone.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchSession.shared.scheduleBackgroundRefresh()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refresh as WKApplicationRefreshBackgroundTask:
                let done = BackgroundDone(refresh)
                Task {
                    await WatchSession.shared.backgroundRefresh()
                    done.call()
                }
            case let delivery as WKWatchConnectivityRefreshBackgroundTask:
                let done = BackgroundDone(delivery)
                Task {
                    await WatchSession.shared.waitForDelivery()
                    done.call()
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

/// Finishing a background task is fine from anywhere; the type just doesn't say so.
private struct BackgroundDone: @unchecked Sendable {
    let task: WKRefreshBackgroundTask

    init(_ task: WKRefreshBackgroundTask) {
        self.task = task
    }

    func call() {
        task.setTaskCompletedWithSnapshot(false)
    }
}
