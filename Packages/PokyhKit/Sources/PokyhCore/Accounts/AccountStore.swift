import Foundation

/// The school an account belongs to, as WebUntis' school search returns it.
public struct SchoolRef: Codable, Sendable, Hashable {
    /// WebUntis login name, e.g. "lbs-brixen".
    public var loginName: String
    public var displayName: String
    /// WebUntis host, e.g. "lbs-brixen.webuntis.com".
    public var server: String

    public init(loginName: String, displayName: String, server: String) {
        self.loginName = loginName
        self.displayName = displayName
        self.server = server
    }
}

/// What it takes to sign an account in again without asking: the iPhone keeps it after the
/// first sign-in and hands it to the watch, so neither asks twice.
public struct StoredAccount: Codable, Sendable, Hashable {
    public var username: String
    public var displayName: String
    public var school: SchoolRef
    /// The WebUntis password, or "appkey:<KEY>" for app key accounts (see `AppKey`).
    public var secret: String
    public var signedInAt: Date

    public init(username: String, displayName: String, school: SchoolRef, secret: String, signedInAt: Date = .now) {
        self.username = username
        self.displayName = displayName
        self.school = school
        self.secret = secret
        self.signedInAt = signedInAt
    }
}

/// The signed-in account, kept in the Keychain. `changedAt` remembers when the phone last said
/// something about it, so an older hand-off arriving late can't undo a newer one.
public struct AccountStore: Sendable {
    struct Record: Codable {
        var account: StoredAccount?
        var changedAt: Date
    }

    static let key = "account.current"

    let store: any SecureStore

    public init(store: any SecureStore) {
        self.store = store
    }

    public func load() -> StoredAccount? {
        record()?.account
    }

    public var changedAt: Date? {
        record()?.changedAt
    }

    /// Applies a change unless a newer one is already stored. Returns whether it was applied.
    @discardableResult
    public func apply(_ account: StoredAccount?, changedAt: Date) throws -> Bool {
        if let current = record(), current.changedAt > changedAt { return false }
        let data = try JSONEncoder().encode(Record(account: account, changedAt: changedAt))
        try store.set(data, for: Self.key)
        return true
    }

    public func save(_ account: StoredAccount) throws {
        try apply(account, changedAt: .now)
    }

    public func clear() throws {
        try apply(nil, changedAt: .now)
    }

    private func record() -> Record? {
        guard let data = try? store.data(for: Self.key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
}
