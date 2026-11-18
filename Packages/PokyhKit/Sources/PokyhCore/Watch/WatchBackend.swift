import Foundation

/// The watch's own POKYH session, kept in its Keychain. The watch is a device of its own in
/// "Geräte & Anmeldungen": refresh tokens rotate on every use, so sharing the phone's would sign
/// one of the two out.
public struct WatchBackendSession: Codable, Sendable, Equatable {
    public var username: String
    public var token: String?
    public var refreshToken: String?
    /// Signed out from the device list. Nothing signs in again for this account until the person
    /// connects the watch on the phone after that.
    public var revokedAt: Date?

    public init(username: String, token: String? = nil, refreshToken: String? = nil, revokedAt: Date? = nil) {
        self.username = username
        self.token = token
        self.refreshToken = refreshToken
        self.revokedAt = revokedAt
    }
}

public enum WatchBackendError: Error, Equatable, Sendable {
    /// The backend couldn't be reached.
    case noConnection
    /// This watch was signed out from the device list.
    case revoked
    /// No POKYH session to be had right now; the next load tries again.
    case unavailable
    /// The backend said no to a change (the to-do is gone, say).
    case rejected(Int)
}

/// What the watch asks of the POKYH backend by itself: its session, the to-dos and the menu.
/// An actor, so two loads never rotate the same refresh token at once.
public actor WatchBackend {
    static let key = "backend.session"
    /// A token this close to its end is renewed first.
    static let expiryMargin: TimeInterval = 60

    let client: BackendClient
    let store: any SecureStore
    /// The build's own school, which the backend knows without being told (as the phone does it).
    let defaultSchool: School?
    private var refreshing: Task<String?, any Error>?

    public init(client: BackendClient, store: any SecureStore, defaultSchool: School?) {
        self.client = client
        self.store = store
        self.defaultSchool = defaultSchool
    }

    public nonisolated var backendURL: URL { client.config.backendURL }

    /// Pupils, guardians and POKYH-only accounts have a POKYH account; teachers don't.
    public nonisolated static func canSignIn(_ account: StoredAccount) -> Bool {
        switch account.backend {
        case .student?, .parent?, .password?: true
        case .untisOnly?, nil: false
        }
    }

    /// Whether a new sign-in needs a WebUntis session, which the backend checks with WebUntis.
    public nonisolated static func signsInWithUntis(_ account: StoredAccount) -> Bool {
        account.backend == .student || account.backend == .parent
    }

    // MARK: The session

    /// Read straight from the Keychain; only the actor writes it.
    public nonisolated func session() -> WatchBackendSession? {
        guard let data = try? store.data(for: Self.key) else { return nil }
        return try? JSONDecoder().decode(WatchBackendSession.self, from: data)
    }

    /// When this account was signed out from the device list, if it was.
    public nonisolated func revokedAt(of username: String) -> Date? {
        guard let session = session(), AccountRoster.same(session.username, username) else { return nil }
        return session.revokedAt
    }

    /// The account left the watch: its session ends at the backend too, so the device leaves the
    /// list. A sign-out from the device list stays on record for that account.
    public func forget() async {
        let current = session()
        if let current, let refresh = current.refreshToken {
            if let token = current.token, (try? await client.signOut(refreshToken: refresh, token: token)) != nil {
                // Signed out.
            } else if let fresh = try? await client.refresh(refreshToken: refresh) {
                try? await client.signOut(refreshToken: fresh.refreshToken, token: fresh.token)
            }
        }
        if let current, let revokedAt = current.revokedAt {
            save(WatchBackendSession(username: current.username, revokedAt: revokedAt))
        } else {
            save(nil)
        }
    }

    /// A token without signing in anew: the stored one while it lasts, else a refreshed one.
    /// nil when only a new sign-in will do.
    public func storedToken(for account: StoredAccount, now: Date = .now) async throws -> String? {
        guard Self.canSignIn(account), let current = session(), AccountRoster.same(current.username, account.username),
              current.revokedAt == nil else { return nil }
        if let token = current.token, let expiry = JWTClaims.expiry(of: token), expiry.timeIntervalSince(now) > Self.expiryMargin {
            return token
        }
        return try await refreshed(for: account)
    }

    /// One refresh at a time; whoever asks meanwhile waits for the same answer.
    private func refreshed(for account: StoredAccount) async throws -> String? {
        if let refreshing { return try await refreshing.value }
        let task = Task { try await self.refreshNow(for: account) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func refreshNow(for account: StoredAccount) async throws -> String? {
        guard let current = session(), AccountRoster.same(current.username, account.username),
              let refresh = current.refreshToken else { return nil }
        do {
            let tokens = try await client.refresh(refreshToken: refresh)
            save(WatchBackendSession(username: current.username, token: tokens.token, refreshToken: tokens.refreshToken))
            return tokens.token
        } catch let error as BackendError where error.status == 401 {
            // Expired or revoked; a new sign-in tells which.
            save(WatchBackendSession(username: current.username))
            return nil
        } catch {
            throw Self.classified(error)
        }
    }

    /// Signs in anew: with the WebUntis session for pupils and guardians, with the password for
    /// POKYH-only accounts. A renewal, like the phone's own sign-in after launch, so it doesn't
    /// count as a sign-in by the person; the first one after a sign-out from the device list is
    /// a real one, because the person connected the watch again.
    @discardableResult
    public func signIn(_ account: StoredAccount, untisSessionId: String?) async throws -> String {
        let current = session()
        let revokedAt = current.flatMap { AccountRoster.same($0.username, account.username) ? $0.revokedAt : nil }
        switch account.backend {
        case .password?:
            do {
                let (tokens, _) = try await client.signIn(username: account.username, password: account.secret)
                save(WatchBackendSession(username: account.username, token: tokens.token, refreshToken: tokens.refreshToken))
                return tokens.token
            } catch {
                throw Self.classified(error)
            }
        case .student?, .parent?:
            guard let untisSessionId, !untisSessionId.isEmpty else { throw WatchBackendError.unavailable }
            let outcome = await client.signInWithUntis(
                username: account.username,
                untisSessionId: untisSessionId,
                role: account.backend == .parent ? "parent" : "student",
                renewal: revokedAt == nil,
                school: isDefault(account.school) ? nil : account.school,
                method: AppKey.isKey(account.secret) ? "office" : nil
            )
            switch outcome {
            case .ok(let tokens):
                save(WatchBackendSession(username: account.username, token: tokens.token, refreshToken: tokens.refreshToken))
                return tokens.token
            case .revoked:
                save(WatchBackendSession(username: account.username, revokedAt: .now))
                throw WatchBackendError.revoked
            case .noConnection:
                throw WatchBackendError.noConnection
            case .untisSessionExpired, .untisUnavailable, .failed:
                throw WatchBackendError.unavailable
            }
        case .untisOnly?, nil:
            throw WatchBackendError.unavailable
        }
    }

    private func isDefault(_ school: School) -> Bool {
        guard let defaultSchool else { return false }
        return school.loginName == defaultSchool.loginName && school.server == defaultSchool.server
    }

    private func save(_ session: WatchBackendSession?) {
        let data = session.flatMap { try? JSONEncoder().encode($0) }
        try? store.set(data, for: Self.key)
    }

    // MARK: What the watch loads

    public func todos(for account: StoredAccount) async throws -> [WatchTodos.Item] {
        let data = try await authorized(account) { token, name in
            try await self.client.send(BackendRoutes.todos(name), token: token)
        }
        guard let items = WatchTodos.items(from: data) else { throw WatchBackendError.unavailable }
        return items
    }

    /// A tick from the watch, sent the way the To-dos screen sends it.
    public func setTodo(_ toggle: TodoToggle, for account: StoredAccount) async throws {
        _ = try await authorized(account) { token, name in
            try await self.client.send(BackendRoutes.todo(name, id: toggle.id), method: "PATCH", token: token,
                                       json: ["done": toggle.done, "doneAt": toggle.doneAt ?? NSNull()])
        }
    }

    /// The menu, without a token as the phone asks for it. Public at the backend.
    public func menu() async throws -> Data {
        do {
            return try await client.send(BackendRoutes.dishes)
        } catch {
            throw Self.classified(error)
        }
    }

    /// The ratings of these dishes. With the account's token where there is one, else as a guest.
    public func ratings(_ ids: [String], for account: StoredAccount) async throws -> Data {
        guard !ids.isEmpty else { return Data("{}".utf8) }
        let token = try? await storedToken(for: account)
        do {
            return try await client.send(BackendRoutes.dishRatingsBatch, method: "POST", token: token, json: ["dishIds": ids])
        } catch {
            throw Self.classified(error)
        }
    }

    /// With the account's token, renewed once if the backend no longer takes it.
    private func authorized(_ account: StoredAccount, _ request: @Sendable (String, String) async throws -> Data) async throws -> Data {
        guard let token = try await storedToken(for: account) else { throw WatchBackendError.unavailable }
        do {
            return try await request(token, JWTClaims.username(of: token) ?? account.username.lowercased())
        } catch let error as BackendError where error.status == 401 {
            guard let fresh = try await refreshed(for: account) else { throw WatchBackendError.unavailable }
            do {
                return try await request(fresh, JWTClaims.username(of: fresh) ?? account.username.lowercased())
            } catch {
                throw Self.classified(error)
            }
        } catch {
            throw Self.classified(error)
        }
    }

    static func classified(_ error: any Error) -> WatchBackendError {
        if let error = error as? WatchBackendError { return error }
        guard let error = error as? BackendError else { return .unavailable }
        if error.code == "no_connection" { return .noConnection }
        if let status = error.status, (400..<500).contains(status), status != 401, status != 429 { return .rejected(status) }
        return .unavailable
    }
}

/// What a POKYH access token says about itself. Read, never verified: the backend does that.
enum JWTClaims {
    static func expiry(of token: String) -> Date? {
        guard let seconds = LooseJSON(raw: claims(token))["exp"].double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// The account name the backend files the token under, which its routes expect.
    static func username(of token: String) -> String? {
        LooseJSON(raw: claims(token))["username"].string.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func claims(_ token: String) -> Any? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
