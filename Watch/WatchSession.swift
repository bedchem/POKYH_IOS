import Foundation
import Observation
import PokyhCore
import WatchConnectivity
import WatchKit
import WidgetKit

/// The watch's side of the iPhone link. Signs in once with what the phone hands over and keeps
/// the account in the watch's own Keychain, so it stays signed in across launches and restarts
/// until the phone says otherwise. Keeps the phone's last snapshot sealed on disk, sends ticked
/// to-dos back, and loads the day's lessons by itself when the phone can't help.
@Observable
@MainActor
final class WatchSession: NSObject {
    static let shared = WatchSession(
        accounts: AccountStore(store: KeychainStore(service: AppConfig.current.appBundleID)),
        store: .shared(createsKey: true)
    )

    private(set) var account: StoredAccount?
    /// The last snapshot with the not yet confirmed ticks on top: what the pages show.
    private(set) var snapshot: WatchSnapshot?
    private(set) var queue = TodoQueue()
    /// Loading the lessons by itself right now.
    private(set) var loading = false

    /// How long the phone gets to answer with something newer before the watch loads by itself.
    private static let phoneGrace: Duration = .seconds(8)
    /// WebUntis gets a sign-in from here this often at most, whatever the outcome.
    private static let ownLoadInterval: TimeInterval = 10 * 60
    /// The phone said "later" (locked, offline): don't ask again right away.
    private static let queueHold: TimeInterval = 60

    @ObservationIgnored private let accounts: AccountStore
    @ObservationIgnored private let store: WatchStore
    @ObservationIgnored private let untis = UntisDay()
    @ObservationIgnored private let session: WCSession? = WCSession.isSupported() ? .default : nil
    /// The snapshot as it came, without the ticks.
    @ObservationIgnored private var received: WatchSnapshot?
    @ObservationIgnored private var sending: Set<String> = []
    @ObservationIgnored private var queueHeldUntil = Date.distantPast
    @ObservationIgnored private var lastOwnLoad = Date.distantPast

    init(accounts: AccountStore, store: WatchStore) {
        self.accounts = accounts
        self.store = store
        let account = accounts.load()
        self.account = account
        super.init()
        if let account, let saved = store.snapshot(), AccountRoster.same(saved.username, account.username) {
            received = saved
            queue = store.queue()
            snapshot = saved.applying(queue)
        }
        // Early, so a context arriving while the app runs in the background finds a delegate.
        session?.delegate = self
        session?.activate()
    }

    // MARK: What the pages call

    /// The app came on screen: send what's waiting, then get something newer.
    func refresh() {
        guard account != nil, let session, session.activationState == .activated else { return }
        flushQueue()
        guard session.isReachable else {
            Task { await loadByItself() }
            return
        }
        askPhone(WatchRequest.snapshot) { [weak self] reply in
            guard let self else { return }
            take(reply)
            // The phone answers with what it has; a locked one has nothing newer coming.
            Task {
                try? await Task.sleep(for: Self.phoneGrace)
                await self.loadByItself()
            }
        } failed: { [weak self] in
            guard let self else { return }
            Task { await self.loadByItself() }
        }
    }

    /// Ticks or unticks at once; the phone hears about it now or as soon as it can.
    func toggle(_ todo: WatchSnapshot.Todo) {
        guard let received else { return }
        let phoneSays = received.todos.first { $0.id == todo.id }?.done ?? todo.done
        queue.toggle(todo.id, to: !todo.done, phoneSays: phoneSays)
        store.save(queue)
        snapshot = received.applying(queue)
        queueHeldUntil = .distantPast
        flushQueue()
    }

    func isQueued(_ todo: WatchSnapshot.Todo) -> Bool {
        queue.pending(for: todo.id) != nil
    }

    // MARK: Background

    /// Called for the background refresh the system grants.
    func backgroundRefresh() async {
        await loadByItself()
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
        scheduleBackgroundRefresh()
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
        if before?.lessons != next.lessons || before?.day != next.day || before?.lang != next.lang {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Signed out or another account: nothing of the old one stays on the watch.
    private func forgetData() {
        received = nil
        snapshot = nil
        queue = TodoQueue()
        store.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// No account yet: ask the phone, in case the watch app came after the sign-in.
    private func sessionIsUp() {
        guard let session, session.activationState == .activated else { return }
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
        guard let session, session.activationState == .activated, session.isReachable,
              Date() >= queueHeldUntil else { return }
        for toggle in queue.items where !sending.contains(toggle.id) {
            sending.insert(toggle.id)
            askPhone(toggle.payload) { [weak self] reply in
                self?.finished(toggle, reply: reply)
            } failed: { [weak self] in
                self?.sending.remove(toggle.id)
            }
        }
    }

    private func finished(_ toggle: TodoToggle, reply: [String: Any]) {
        sending.remove(toggle.id)
        switch TodoToggleResult(reply: reply) {
        case .later, nil:
            queueHeldUntil = Date().addingTimeInterval(Self.queueHold)
        case .rejected:
            WKInterfaceDevice.current().play(.failure)
            drop(toggle)
        case .applied:
            drop(toggle)
        }
        take(reply)
    }

    /// Done with this tick, unless it was changed again while on its way.
    private func drop(_ toggle: TodoToggle) {
        guard queue.pending(for: toggle.id) == toggle else { return }
        queue.remove(toggle.id)
        store.save(queue)
        if let received { snapshot = received.applying(queue) }
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

    /// Only when the phone couldn't help: today's lessons straight from WebUntis, with the
    /// account the phone handed over. Grades, Mensa and to-dos stay as the phone last sent them.
    private func loadByItself() async {
        guard let account, !loading, received?.isStale() ?? true,
              Date().timeIntervalSince(lastOwnLoad) > Self.ownLoadInterval else { return }
        loading = true
        lastOwnLoad = Date()
        defer { loading = false }
        let day = Calendar.current.startOfDay(for: Date())
        // No connection, or the school said no: the page keeps saying how old its data is.
        guard let result = try? await untis.lessons(for: account, studentId: received?.studentId),
              let current = self.account, AccountRoster.same(current.username, account.username) else { return }
        let base = received ?? .empty(for: account.username)
        show(base.withLessons(result.lessons, day: day, studentId: result.studentId))
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
