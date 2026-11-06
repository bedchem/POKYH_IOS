import Foundation

/// A WebUntis school, as the school search returns it.
public struct School: Codable, Sendable, Hashable, Identifiable {
    /// WebUntis login name, e.g. "lbs-brixen".
    public var loginName: String
    /// WebUntis host, e.g. "lbs-brixen.webuntis.com".
    public var server: String
    public var name: String
    public var address: String

    public init(loginName: String, server: String, name: String = "", address: String = "") {
        self.loginName = loginName
        self.server = server
        self.name = name
        self.address = address
    }

    public var id: String { "\(server)/\(loginName)" }

    /// WebUntis' address for this school.
    public var base: URL? { URL(string: "https://\(server)/WebUntis") }
}

/// What it takes to sign an account in again without asking: the iPhone keeps it after the
/// first sign-in and hands it to the watch, so neither asks twice.
public struct StoredAccount: Codable, Sendable, Hashable {
    public var username: String
    public var displayName: String
    public var school: School
    /// The WebUntis password, or "appkey:<KEY>" for app key accounts (see `AppKey`).
    public var secret: String
    public var signedInAt: Date

    public init(username: String, displayName: String, school: School, secret: String, signedInAt: Date = .now) {
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

    /// What to answer the watch with. Throws while the store can't be read (the phone is locked):
    /// "nothing stored" then would sign the watch out.
    public func handoff() throws -> AccountHandoff {
        guard let data = try store.data(for: Self.key) else { return AccountHandoff(account: nil) }
        guard let record = try? JSONDecoder().decode(Record.self, from: data) else { return AccountHandoff(account: nil) }
        return AccountHandoff(account: record.account, sentAt: record.changedAt)
    }

    /// Writes the record again as it is, so it takes the store's current protection.
    /// `changedAt` stays, the watch sees no change.
    public func reseal() throws {
        guard let data = try store.data(for: Self.key) else { return }
        try store.set(data, for: Self.key)
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

    /// The account's password changed: stores the new one and returns what to tell the watch.
    /// nil when another account is stored, or an app key, which goes on working without it.
    public func replacePassword(_ password: String, of username: String) throws -> StoredAccount? {
        guard var account = load(), AccountRoster.same(account.username, username), !AppKey.isKey(account.secret) else { return nil }
        account.secret = password
        try save(account)
        return account
    }

    private func record() -> Record? {
        guard let data = try? store.data(for: Self.key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
}
