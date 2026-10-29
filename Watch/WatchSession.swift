import Foundation
import Observation
import PokyhCore
import WatchConnectivity

/// The watch's side of the hand-off. Signs in once with what the iPhone sends and keeps the
/// account in the watch's own Keychain, so it stays signed in across launches and restarts
/// until the phone says otherwise.
@Observable
@MainActor
final class WatchSession: NSObject {
    private(set) var account: StoredAccount?

    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let session: WCSession? = WCSession.isSupported() ? .default : nil

    init(store: AccountStore) {
        self.store = store
        self.account = store.load()
        super.init()
    }

    func activate() {
        session?.delegate = self
        session?.activate()
    }

    private func receive(_ payload: [String: Any]) {
        guard let handoff = AccountHandoff(payload: payload) else { return }
        do {
            if try handoff.apply(to: store) {
                account = store.load()
            }
        } catch {
            // Keychain refused (shouldn't happen on a real watch); keep what we had.
        }
    }

    /// No account yet: ask the phone, in case the watch app came after the sign-in.
    private func askPhoneIfNeeded() {
        guard account == nil, let session, session.activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        guard account == nil, session.isReachable else { return }
        session.sendMessage(AccountHandoff.request) { [weak self] reply in
            Task { @MainActor in self?.receive(reply) }
        } errorHandler: { _ in
            // Phone went away; the applicationContext still arrives once it's back.
        }
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.askPhoneIfNeeded() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.askPhoneIfNeeded() }
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
