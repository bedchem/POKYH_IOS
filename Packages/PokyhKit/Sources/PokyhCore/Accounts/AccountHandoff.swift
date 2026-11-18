import Foundation

/// What the iPhone tells the watch about the account, as a WatchConnectivity payload.
/// Plain property-list types only, so it fits applicationContext, userInfo and messages alike.
public struct AccountHandoff: Sendable, Equatable {
    public var account: StoredAccount?
    public var sentAt: Date
    /// When the person last chose to connect the watch on the phone. A watch signed out from the
    /// device list only takes the account again after a newer choice than that.
    public var connectedAt: Date?

    public init(account: StoredAccount?, sentAt: Date = .now, connectedAt: Date? = nil) {
        self.account = account
        self.sentAt = sentAt
        self.connectedAt = connectedAt
    }

    static let accountKey = "pokyh.account"
    static let sentAtKey = "pokyh.sentAt"
    static let connectedAtKey = "pokyh.connectedAt"
    public static let requestKey = "pokyh.requestAccount"

    /// Asks the phone for the current account (sent by the watch when it has none).
    public static var request: [String: Any] { [requestKey: true] }

    public static func isRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? Bool == true
    }

    public var payload: [String: Any] {
        var payload: [String: Any] = [Self.sentAtKey: sentAt.timeIntervalSince1970]
        if let connectedAt { payload[Self.connectedAtKey] = connectedAt.timeIntervalSince1970 }
        if let account, let data = try? JSONEncoder().encode(account) {
            payload[Self.accountKey] = data
        }
        return payload
    }

    /// nil for anything that isn't a hand-off.
    public init?(payload: [String: Any]) {
        guard let sentAt = payload[Self.sentAtKey] as? TimeInterval else { return nil }
        let connectedAt = (payload[Self.connectedAtKey] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        if let data = payload[Self.accountKey] as? Data {
            guard let account = try? JSONDecoder().decode(StoredAccount.self, from: data) else { return nil }
            self.init(account: account, sentAt: Date(timeIntervalSince1970: sentAt), connectedAt: connectedAt)
        } else {
            self.init(account: nil, sentAt: Date(timeIntervalSince1970: sentAt), connectedAt: connectedAt)
        }
    }

    /// Stores it unless something newer is already there.
    @discardableResult
    public func apply(to store: AccountStore) throws -> Bool {
        try store.apply(account, changedAt: sentAt)
    }
}
