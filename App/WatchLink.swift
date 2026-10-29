import Foundation
import PokyhCore
import WatchConnectivity

/// The iPhone's side of the hand-off: whenever the account changes, the watch hears about it.
/// applicationContext always holds the latest state (also for a watch app installed later),
/// userInfo queues the change so it arrives even if the watch is off right now.
@MainActor
final class WatchLink: NSObject {
    private let store: AccountStore
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    init(store: AccountStore) {
        self.store = store
        super.init()
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    func signedIn(_ account: StoredAccount) {
        send(AccountHandoff(account: account))
    }

    func signedOut() {
        send(AccountHandoff(account: nil))
    }

    private func send(_ handoff: AccountHandoff) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(handoff.payload)
        session.transferUserInfo(handoff.payload)
    }

    /// What the watch gets when it asks.
    fileprivate func currentHandoff() -> AccountHandoff {
        AccountHandoff(account: store.load(), sentAt: store.changedAt ?? .now)
    }

    /// Re-sends the current state once the session is up, e.g. after the watch app was installed.
    fileprivate func syncCurrentState() {
        guard store.changedAt != nil else { return }
        let handoff = currentHandoff()
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(handoff.payload)
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
        guard AccountHandoff.isRequest(message) else {
            replyHandler([:])
            return
        }
        let reply = ReplyHandler(replyHandler)
        Task { @MainActor in reply.call(self.currentHandoff().payload) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch: start over with that one.
        session.activate()
    }
}

private struct ReplyHandler: @unchecked Sendable {
    let call: ([String: Any]) -> Void

    init(_ call: @escaping ([String: Any]) -> Void) {
        self.call = call
    }
}

/// What the rest of the app calls: sign-in and sign-out in AppState end up on the watch.
@MainActor
enum WatchSync {
    private static let accounts = AccountStore(store: KeychainStore(service: AppConfig.current.appBundleID))
    private static let link = WatchLink(store: accounts)

    static func start() {
        link.activate()
    }

    static func signedIn(username: String, displayName: String, password: String) {
        let school = PokyhCore.School(
            loginName: Config.school,
            server: Bundle.main.object(forInfoDictionaryKey: "POKYHDefaultUntisServer") as? String ?? "",
            name: Bundle.main.object(forInfoDictionaryKey: "POKYHDefaultSchoolName") as? String ?? Config.school
        )
        let account = StoredAccount(username: username, displayName: displayName, school: school, secret: password)
        try? accounts.save(account)
        link.signedIn(account)
    }

    /// Only if it's the account the watch has; switching between saved accounts doesn't count.
    static func signedOut(username: String? = nil) {
        if let username, accounts.load()?.username != username { return }
        try? accounts.clear()
        link.signedOut()
    }
}
