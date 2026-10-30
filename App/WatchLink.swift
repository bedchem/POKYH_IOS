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
@MainActor
final class WatchLink: NSObject {
    let pairing = WatchPairing()
    private let store: AccountStore
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    /// Tapped "connect" before the session was up; send once it is.
    private var resendWhenActive = false

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
        send(AccountHandoff(account: account))
    }

    func signedOut() {
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
        try? session.updateApplicationContext(handoff.payload)
        session.transferUserInfo(handoff.payload)
        pairing.lastSent = .now
        return true
    }

    private func send(_ handoff: AccountHandoff) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(handoff.payload)
        session.transferUserInfo(handoff.payload)
        pairing.lastSent = .now
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
        if resendWhenActive, session?.activationState == .activated {
            resendWhenActive = false
            resend()
            return
        }
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
        let account = StoredAccount(username: username, displayName: displayName, school: DefaultSchool.school, secret: password)
        try? accounts.save(account)
        link.signedIn(account)
    }

    /// "Connect now" in the settings: hands the signed-in account to the watch again. Accounts
    /// signed in before the watch existed have nothing stored yet, so the caller may pass one.
    @discardableResult
    static func pairNow(username: String? = nil, displayName: String? = nil, password: String? = nil) -> PairResult {
        var account = accounts.load()
        if let username, let password, !password.isEmpty, account?.username != username {
            account = StoredAccount(username: username, displayName: displayName ?? username, school: DefaultSchool.school, secret: password)
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
}
