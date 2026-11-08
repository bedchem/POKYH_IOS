import Foundation
import PokyhCore
import UIKit

/// POKYH-Backend-Client (api.pokyh.com): App-Auth, Todos, Erinnerungen, Klasse, Mensa.
final class BackendClient {
    static let shared = BackendClient()

    private let session: URLSession
    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        #if DEBUG
        StubServer.attach(to: cfg)
        #endif
        session = URLSession(configuration: cfg)
    }

    private var base: String { Config.backendURL }

    /// This install as the backend files it under "Geräte & Anmeldungen". Read each time, so a
    /// fresh id follows "Cache & Daten löschen" right away.
    private var device: DeviceIdentity {
        let d = UIDevice.current
        return DeviceIdentity(defaults: .standard, version: Config.appVersion.components(separatedBy: " ").first ?? "",
                              system: "\(d.systemName) \(d.systemVersion)", model: Self.model)
    }

    /// The hardware model ("iPhone17,1"), the simulator's when running in one.
    private static let model: String = {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    /// API key, device id and user agent: what every request to the backend carries.
    private func stamp(_ req: inout URLRequest) {
        let device = device
        req.setValue(Config.apiKey, forHTTPHeaderField: "X-API-Key")
        req.setValue(device.id, forHTTPHeaderField: "X-Pokyh-Device")
        req.setValue(device.userAgent, forHTTPHeaderField: "User-Agent")
    }

    // ── Auth ─────────────────────────────────────────────────────────────────

    /// What the server-to-server sign-in answered, with what the UI needs to explain it.
    enum UntisLoginResult {
        case ok(token: String, refresh: String)
        case failed(String)        // HTTP or network failure, with its message
        /// This device was signed out somewhere else; only on a renewal. Sign in again by hand.
        case revoked(String)
        /// The WebUntis session handed over has ended: sign in to WebUntis again, then once more here.
        case untisSessionExpired
        /// The backend could not reach WebUntis to check the session: keep the POKYH session going
        /// with the refresh token for now.
        case untisUnavailable(String)
    }

    /// Sign-in at the backend after the WebUntis sign-in, with the app's WebUntis session
    /// (`untisSessionId`, its JSESSIONID): the backend asks WebUntis itself whose it is and which
    /// class the account belongs to; nothing the app works out counts. The app key proves nothing
    /// on its own. `role: "parent"` only ever makes a new account a parent's.
    /// `renewal`: the app signing itself in again (launch, Face ID), not a sign-in by the person.
    /// `school`: where WebUntis checked the account; the build's own school is left out, as on Android.
    /// `method`: "office" for an app key sign-in.
    func loginWithUntis(username: String, untisSessionId: String, role: String = "student",
                        renewal: Bool = false, school: School? = nil, method: String? = nil) async -> UntisLoginResult {
        let t = Strings.current.errors
        guard !untisSessionId.isEmpty else { return .untisSessionExpired }
        guard let url = URL(string: "\(base)\(Config.Routes.authLogin)") else { return .failed(t.badAnswer) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.serverKey, forHTTPHeaderField: "X-Server-Key")
        stamp(&req)
        var body: [String: Any] = [
            "username": username, "untisSessionId": untisSessionId, "role": role, "renewal": renewal,
        ]
        if let method { body["method"] = method }
        if let school, !school.isFallback {
            body["school"] = school.loginName
            body["schoolName"] = school.name
            body["schoolServer"] = school.server
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return .failed(t.noConnection) }
        let j = JSON.parse(data)
        guard http.statusCode == 200 else {
            switch j.code.string {
            case "session_revoked": return .revoked(j.error.string ?? t.loginFailed)
            case "untis_session_invalid": return .untisSessionExpired
            case "webuntis_unavailable": return .untisUnavailable(j.error.string ?? t.noConnection)
            default: return .failed(j.error.string ?? "HTTP \(http.statusCode)")
            }
        }
        guard let token = j.token.string, let refresh = j.refreshToken.string else {
            return .failed(t.badAnswer)
        }
        return .ok(token: token, refresh: refresh)
    }

    /// Signs in to the backend alone (an account without WebUntis): user name and password.
    func login(username: String, password: String) async throws -> (token: String, refresh: String, user: ApiUser) {
        try await authPost(Config.Routes.authLogin, body: ["username": username.lowercased(), "password": password])
    }

    func register(username: String, password: String) async throws -> (token: String, refresh: String, user: ApiUser) {
        try await authPost(Config.Routes.authRegister, body: ["username": username.lowercased(), "password": password])
    }

    private func authPost(_ path: String, body: [String: Any]) async throws -> (token: String, refresh: String, user: ApiUser) {
        guard let url = URL(string: "\(base)\(path)") else { throw AppError(message: Strings.current.errors.badAnswer) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        stamp(&req)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let j = JSON.parse(data)
        guard http?.statusCode == 200 else {
            throw AppError(message: j.error.string ?? Strings.current.errors.loginFailed, status: http?.statusCode)
        }
        guard let token = j.token.string, let refresh = j.refreshToken.string else {
            throw AppError(message: Strings.current.errors.badAnswer)
        }
        let user = ApiUser(
            stableUid: j.user.stableUid.string ?? "",
            username: j.user.username.string ?? username(body),
            webuntisKlasseId: j.user.webuntisKlasseId.int,
            webuntisKlasseName: j.user.webuntisKlasseName.string,
            classId: j.user.classId.string,
            isAdmin: j.user.isAdmin.bool ?? false,
            role: j.user.role.string
        )
        return (token, refresh, user)
    }

    private func username(_ body: [String: Any]) -> String { (body["username"] as? String) ?? "" }

    // ── Authentifizierte Requests ──────────────────────────────────────────────

    /// Set by AppState: a new access token after a 401, or nil when there's none to be had.
    var tokenRenewal: ((_ expired: String) async -> String?)?

    /// The access token lasts an hour, so a 401 gets one more try with a fresh one, as on Android.
    func request(_ path: String, method: String = "GET", token: String?, body: [String: Any]? = nil) async throws -> Data {
        do {
            return try await send(path, method: method, token: token, body: body)
        } catch let error as AppError where error.status == 401 {
            guard let token, let fresh = await tokenRenewal?(token) else { throw error }
            return try await send(path, method: method, token: fresh, body: body)
        }
    }

    private func send(_ path: String, method: String, token: String?, body: [String: Any]?) async throws -> Data {
        guard let url = URL(string: "\(base)\(path)") else { throw AppError(message: Strings.current.errors.badAnswer) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        stamp(&req)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if ["POST", "PUT", "PATCH"].contains(method) {
            req.httpBody = Data("{}".utf8)
        }
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        guard let code = http?.statusCode, (200..<300).contains(code) else {
            let j = JSON.parse(data)
            throw AppError(message: j.error.string ?? "HTTP \(http?.statusCode ?? 0)", status: http?.statusCode)
        }
        return data
    }

    private static func query(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }

    /// A new access token from the refresh token, no password involved.
    func refresh(refreshToken: String) async -> (token: String, refresh: String)? {
        guard let data = try? await send(Config.Routes.authRefresh, method: "POST", token: nil, body: ["refreshToken": refreshToken]) else { return nil }
        let j = JSON.parse(data)
        guard let token = j.token.string, let refresh = j.refreshToken.string else { return nil }
        return (token, refresh)
    }

    func me(token: String) async throws -> ApiUser {
        let data = try await request(Config.Routes.authMe, token: token)
        return try JSONDecoder().decode(ApiUser.self, from: data)
    }

    // ── Todos ──────────────────────────────────────────────────────────────────

    func todos(username: String, token: String) async throws -> [ApiTodo] {
        let data = try await request("/users/\(username.urlEncoded)/todos", token: token)
        return try JSONDecoder().decode([ApiTodo].self, from: data)
    }

    func createTodo(username: String, title: String, details: String, dueAt: String?, token: String) async throws -> ApiTodo {
        var body: [String: Any] = ["title": title, "details": details]
        if let dueAt { body["dueAt"] = dueAt }
        let data = try await request("/users/\(username.urlEncoded)/todos", method: "POST", token: token, body: body)
        return try JSONDecoder().decode(ApiTodo.self, from: data)
    }

    func updateTodo(username: String, id: String, done: Bool, token: String) async throws {
        _ = try await request("/users/\(username.urlEncoded)/todos/\(id)", method: "PATCH", token: token, body: ["done": done])
    }

    /// Ticks a to-do off with the time it was done, as the web sends it (done ones leave a day later).
    func updateTodo(username: String, id: String, done: Bool, doneAt: String?, token: String) async throws {
        _ = try await request("\(Config.Routes.todos(username.urlEncoded))/\(id)", method: "PATCH", token: token,
                              body: ["done": done, "doneAt": doneAt ?? NSNull()])
    }

    /// Changes a to-do's title, details and due time.
    func editTodo(username: String, id: String, title: String, details: String, dueAt: String?, token: String) async throws {
        _ = try await request("\(Config.Routes.todos(username.urlEncoded))/\(id)", method: "PATCH", token: token,
                              body: ["title": title, "details": details, "dueAt": dueAt ?? NSNull()])
    }

    func deleteTodo(username: String, id: String, token: String) async throws {
        _ = try await request("/users/\(username.urlEncoded)/todos/\(id)", method: "DELETE", token: token)
    }

    // ── Nutzungsstatistik ────────────────────────────────────────────────────

    /// A heartbeat for the admin panel's usage figures (see `UsageReporter`): foreground
    /// seconds and tabs since the last ping. Best effort: a failure is swallowed, it must
    /// never get in the app's way.
    func usagePing(sessionId: String, activeSeconds: Int, screens: Int, appVersion: String, token: String) async {
        _ = try? await request("/usage/ping", method: "POST", token: token, body: [
            "sessionId": sessionId,
            "device": "ios",
            "client": "app",
            "appVersion": appVersion,
            "activeSeconds": activeSeconds,
            "screens": screens,
        ])
    }

    // ── Push ─────────────────────────────────────────────────────────────────

    /// This phone's APNs token, with the WebUntis session the backend polls the inbox with.
    /// Sent on every launch and sign-in, so that session stays fresh.
    func registerPush(deviceToken: String, environment: String, kinds: [String], jsessionid: String?, bearerToken: String?, token: String) async throws {
        var body: [String: Any] = ["token": deviceToken, "environment": environment, "kinds": kinds]
        if let jsessionid { body["jsessionid"] = jsessionid }
        if let bearerToken { body["bearerToken"] = bearerToken }
        _ = try await request(Config.Routes.pushApns, method: "POST", token: token, body: body)
    }

    /// Signed out, or notifications switched off.
    func unregisterPush(deviceToken: String, token: String) async throws {
        _ = try await request(Config.Routes.pushApns, method: "DELETE", token: token, body: ["token": deviceToken])
    }

    // ── Privacy notice (see PrivacyNotice.swift) ─────────────────────────────

    struct PrivacyNotice { let version: String }

    /// Which notice the account confirmed, and whether it agreed to the personal usage statistics.
    struct PrivacyStatus {
        let acknowledgedVersion: String?
        var acknowledgedAt: String? = nil
        var usageStats = false
        var usageStatsAt: String? = nil
    }

    /// The current version from the website that holds the text. `nil` without a network.
    func currentPrivacyNotice() async -> PrivacyNotice? {
        guard let url = URL(string: Config.privacyNoticeURL),
              let answer = try? await session.data(from: url),
              (answer.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let j = JSON.parse(answer.0)
        guard let version = j.version.string, !version.isEmpty else { return nil }
        return PrivacyNotice(version: version)
    }

    /// Which version this account accepted. `nil` without an answer (then nothing shows).
    func privacyStatus(token: String) async -> PrivacyStatus? {
        guard let data = try? await request(Config.Routes.privacyStatus, token: token) else { return nil }
        let j = JSON.parse(data)
        return PrivacyStatus(acknowledgedVersion: j.acknowledgedVersion.string, acknowledgedAt: j.acknowledgedAt.string,
                             usageStats: j.usageStats.bool ?? false, usageStatsAt: j.usageStatsAt.string)
    }

    func acknowledgePrivacy(version: String, token: String) async -> Bool {
        (try? await request(Config.Routes.privacyAcknowledge, method: "POST", token: token, body: ["version": version])) != nil
    }

    /// Gives or withdraws the consent to the personal usage statistics.
    func setUsageStats(_ enabled: Bool, token: String) async throws {
        _ = try await request(Config.Routes.usageStats, method: "PUT", token: token, body: ["enabled": enabled])
    }

    /// Everything POKYH keeps about the account, as one JSON file.
    func exportData(token: String) async throws -> Data {
        try await request(Config.Routes.dataExport, token: token)
    }

    // ── Devices and sign-ins ─────────────────────────────────────────────────

    /// A device signed in to the account. `current` is this one.
    struct DeviceSession: Identifiable, Equatable {
        var id: String
        var current: Bool
        var client: String
        var platform: String
        var os: String
        var browser: String
        var model: String
        var ip: String?
        var country: String
        var region: String?
        var city: String?
        var createdAt: String
        var lastUsedAt: String
    }

    /// One sign-in of the account.
    struct LoginEntry: Identifiable, Equatable {
        var id: String
        var at: String
        var method: String
        var client: String
        var platform: String
        var os: String
        var browser: String
        var model: String
        var ip: String?
        var country: String
        var region: String?
        var city: String?
    }

    struct LoginHistory: Equatable {
        var logins: [LoginEntry]
        var keptDays: Int
    }

    /// The devices signed in to the account.
    func deviceSessions(token: String) async throws -> [DeviceSession] {
        let j = JSON.parse(try await request(Config.Routes.sessions, token: token))
        return j.sessions.array.compactMap { d in
            guard let id = d.id.string else { return nil }
            return DeviceSession(id: id, current: d.current.bool ?? false, client: d.client.string ?? "other",
                                 platform: d.platform.string ?? "other", os: d.os.string ?? "", browser: d.browser.string ?? "",
                                 model: d.model.string ?? "", ip: d.ip.string, country: d.country.string ?? "",
                                 region: d.region.string, city: d.city.string,
                                 createdAt: d.createdAt.string ?? "", lastUsedAt: d.lastUsedAt.string ?? "")
        }
    }

    /// Signs one device out.
    func signOutDevice(id: String, token: String) async throws {
        _ = try await request("\(Config.Routes.sessions)/\(Self.query(id))", method: "DELETE", token: token)
    }

    /// Signs every device but this one out.
    func signOutOtherDevices(token: String) async throws {
        _ = try await request(Config.Routes.signOutOthers, method: "POST", token: token)
    }

    /// The account's recent sign-ins and how many days they are kept.
    func loginHistory(token: String) async throws -> LoginHistory {
        let j = JSON.parse(try await request(Config.Routes.loginHistory, token: token))
        let logins = j.logins.array.compactMap { e -> LoginEntry? in
            guard let id = e.id.string else { return nil }
            return LoginEntry(id: id, at: e.at.string ?? "", method: e.method.string ?? "", client: e.client.string ?? "other",
                              platform: e.platform.string ?? "other", os: e.os.string ?? "", browser: e.browser.string ?? "",
                              model: e.model.string ?? "", ip: e.ip.string, country: e.country.string ?? "",
                              region: e.region.string, city: e.city.string)
        }
        return LoginHistory(logins: logins, keptDays: j.keptDays.int ?? 0)
    }

    // ── Schulsuche ───────────────────────────────────────────────────────────

    /// Any school on WebUntis by name, town or postcode. Public, no account needed.
    func searchSchools(_ query: String) async -> SchoolSearch {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return .tooShort }
        do {
            let data = try await request("\(Config.Routes.schoolSearch)?q=\(Self.query(q))", token: nil)
            let list = JSON.parse(data).schools
            guard list.isArray else { return .failed }
            // Lenient like Android: a school without an address still counts.
            return .found(list.array.compactMap { j in
                guard let login = j.loginName.string, let server = j.server.string, !login.isEmpty, !server.isEmpty else { return nil }
                return School(loginName: login, server: server, name: j.name.string ?? "", address: j.address.string ?? "")
            })
        } catch let error as AppError {
            switch error.status {
            case 400: return .tooShort
            case 422: return .tooMany
            case 429: return .rateLimited
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// How the school's people sign in (Office 365, a password, both); nil when unknown.
    func loginOptions(for school: School) async -> LoginOptions? {
        let path = "\(Config.Routes.loginOptions)?school=\(Self.query(school.loginName))&server=\(Self.query(school.server))"
        guard let data = try? await request(path, token: nil) else { return nil }
        return try? JSONDecoder().decode(LoginOptions.self, from: data)
    }

    // ── Klasse / Erinnerungen ────────────────────────────────────────────────

    func myClass(token: String) async throws -> ApiClass? {
        let data = try? await request("/classes/mine", token: token)
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(ApiClass.self, from: data)
    }

    func reminders(classId: String, token: String) async throws -> [ApiReminder] {
        let data = try await request("/classes/\(classId)/reminders", token: token)
        return try JSONDecoder().decode([ApiReminder].self, from: data)
    }

    func createReminder(classId: String, title: String, body: String, remindAt: String, token: String) async throws -> ApiReminder {
        let data = try await request("/classes/\(classId)/reminders", method: "POST", token: token,
                                     body: ["title": title, "body": body, "remindAt": remindAt])
        return try JSONDecoder().decode(ApiReminder.self, from: data)
    }

    /// Changes a reminder (its creator or an admin).
    func editReminder(classId: String, id: String, title: String, body: String, remindAt: String, token: String) async throws -> ApiReminder {
        let data = try await request("\(Config.Routes.reminders(classId))/\(id)", method: "PATCH", token: token,
                                     body: ["title": title, "body": body, "remindAt": remindAt])
        return try JSONDecoder().decode(ApiReminder.self, from: data)
    }

    func deleteReminder(classId: String, id: String, token: String) async throws {
        _ = try await request("/classes/\(classId)/reminders/\(id)", method: "DELETE", token: token)
    }

    // ── Erinnerungs-Kommentare ─────────────────────────────────────────────────

    func reminderComments(classId: String, reminderId: String, token: String) async throws -> [ApiComment] {
        let data = try await request("/classes/\(classId)/reminders/\(reminderId)/comments", token: token)
        return try JSONDecoder().decode([ApiComment].self, from: data)
    }
    func createReminderComment(classId: String, reminderId: String, body: String, token: String) async throws -> ApiComment {
        let data = try await request("/classes/\(classId)/reminders/\(reminderId)/comments", method: "POST", token: token, body: ["body": body])
        return try JSONDecoder().decode(ApiComment.self, from: data)
    }
    /// Changes the text of an own reminder comment.
    func updateReminderComment(classId: String, reminderId: String, commentId: String, body: String, token: String) async throws -> ApiComment {
        let data = try await request("/classes/\(classId)/reminders/\(reminderId)/comments/\(commentId)", method: "PATCH", token: token, body: ["body": body])
        return try JSONDecoder().decode(ApiComment.self, from: data)
    }
    func deleteReminderComment(classId: String, reminderId: String, commentId: String, token: String) async throws {
        _ = try await request("/classes/\(classId)/reminders/\(reminderId)/comments/\(commentId)", method: "DELETE", token: token)
    }

    // ── Mensa-Kommentare ───────────────────────────────────────────────────────

    func dishComments(dishId: String, token: String) async throws -> [ApiComment] {
        let data = try await request("/dish-comments/\(dishId.urlEncoded)", token: token)
        return try JSONDecoder().decode([ApiComment].self, from: data)
    }
    func createDishComment(dishId: String, body: String, token: String) async throws -> ApiComment {
        let data = try await request("/dish-comments/\(dishId.urlEncoded)", method: "POST", token: token, body: ["body": body])
        return try JSONDecoder().decode(ApiComment.self, from: data)
    }
    /// Changes the text of an own dish comment.
    func updateDishComment(dishId: String, commentId: String, body: String, token: String) async throws -> ApiComment {
        let data = try await request("/dish-comments/\(dishId.urlEncoded)/\(commentId)", method: "PATCH", token: token, body: ["body": body])
        return try JSONDecoder().decode(ApiComment.self, from: data)
    }
    func deleteDishComment(dishId: String, commentId: String, token: String) async throws {
        _ = try await request("/dish-comments/\(dishId.urlEncoded)/\(commentId)", method: "DELETE", token: token)
    }

    // ── Mensa ──────────────────────────────────────────────────────────────────

    // Zentrales Caching (Performance): /dishes max. alle 5 Min neu laden.
    private let dishCache = TTLCache<String, [Dish]>(ttl: 300)
    private let dishKey = "dishes"

    /// Leert alle In-Memory-Caches dieses Clients (z. B. „Cache leeren").
    func clearCaches() { dishCache.removeAll() }

    /// The menu from memory, else the network, else (offline) the copy on disk.
    func dishes(force: Bool = false) async throws -> [Dish] {
        if !force, let cached = dishCache.get(dishKey) { return cached }
        do {
            return try await fetchDishes()
        } catch let error as URLError {
            if let stored = dishCache.stale(dishKey) ?? DiskCache.load([Dish].self, key: dishKey) { return stored }
            throw error
        }
    }

    private func fetchDishes() async throws -> [Dish] {
        guard let url = URL(string: "\(base)\(Config.Routes.dishes)") else { throw AppError(message: Strings.current.errors.badAnswer) }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        stamp(&req)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            // On a failure the older copy, if there is one.
            if let stale = dishCache.stale(dishKey) { return stale }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw AppError(message: Strings.current.errors.mensa(code))
        }
        let json = JSON.parse(data)
        var arr = json.isArray ? json.array : []
        if arr.isEmpty { arr = json.menu.dishes.array }   // { menu: { dishes: [...] } }
        if arr.isEmpty { arr = json.dishes.array }
        if arr.isEmpty { arr = json.data.array }
        let dishes = arr.map(Self.parseDish)
        dishCache.set(dishKey, dishes)
        // The menu is the same for everyone, so any account may show it offline.
        DiskCache.save(dishes, key: dishKey)
        return dishes
    }


    static func localized(_ j: JSON) -> String {
        if let s = j.string { return s }
        return j.de.string ?? j.it.string ?? j.en.string ?? ""
    }

    // ── Bewertungen ──────────────────────────────────────────────────────────

    func dishRatings(id: String, token: String) async throws -> DishRatingsData {
        let data = try await request("/dish-ratings/\(id.urlEncoded)", token: token)
        return Self.parseRatings(JSON.parse(data))
    }

    func dishRatingsBatch(ids: [String], token: String) async throws -> [String: DishRatingsData] {
        let data = try await request("/dish-ratings/batch", method: "POST", token: token, body: ["dishIds": ids])
        let json = JSON.parse(data)
        var out: [String: DishRatingsData] = [:]
        for (key, value) in json.dictionary {
            out[key] = Self.parseRatings(value)
        }
        return out
    }

    func rateDish(id: String, stars: Int, token: String) async throws {
        _ = try await request("/dish-ratings/\(id.urlEncoded)", method: "POST", token: token, body: ["stars": stars])
    }

    private static func parseRatings(_ j: JSON) -> DishRatingsData {
        var ratings: [String: Double] = [:]
        // One to five stars; anything else can't be averaged or drawn.
        for (k, v) in j.ratings.dictionary { ratings[k] = min(5, max(0, v.double.flatMap { $0.isFinite ? $0 : nil } ?? 0)) }
        return DishRatingsData(ratings: ratings, myRating: j.myRating.int)
    }

    static func parseDish(_ j: JSON) -> Dish {
        Dish(
            id: j.id.string ?? UUID().uuidString,
            name: localized(j.name),
            description: { let d = localized(j.description); return d.isEmpty ? nil : d }(),
            category: j.category.string ?? "",
            date: j.date.string ?? "",
            imageUrl: j.imageUrl.string,
            price: finite(j.price.double),
            allergens: j.allergens.array.compactMap { $0.string },
            tags: j.tags.array.compactMap { $0.string },
            calories: finite(j.calories.double),
            protein: finite(j.protein.double),
            carbs: finite(j.carbs.double),
            fat: finite(j.fat.double)
        )
    }

    /// Double("NaN") is a valid parse, and these end up in widths and labels.
    private static func finite(_ value: Double?) -> Double? {
        guard let value, MarkText.isUsable(value) else { return nil }
        return value
    }
}

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}

// ── Offline copies ────────────────────────────────────────────────────────────

extension BackendClient {
    /// The fresh answer, which then replaces the copy on disk; the copy when there's no token
    /// (offline session) or no network. Kept in the account's own folder.
    private func storedOrFresh<T: Codable>(_ key: String, _ s: UserSession, fetch: (String) async throws -> T) async throws -> T {
        guard let token = s.apiToken else {
            if let copy = DiskCache.load(T.self, key: key, owner: s.username) { return copy }
            throw AppError(message: Strings.current.tasks.offlineNotStored)
        }
        do {
            let fresh = try await fetch(token)
            DiskCache.save(fresh, key: key, owner: s.username)
            return fresh
        } catch let error as URLError {
            if let copy = DiskCache.load(T.self, key: key, owner: s.username) { return copy }
            throw error
        }
    }

    func todos(_ s: UserSession) async throws -> [ApiTodo] {
        try await storedOrFresh("todos", s) { try await todos(username: s.username, token: $0) }
    }

    func reminders(classId: String, _ s: UserSession) async throws -> [ApiReminder] {
        try await storedOrFresh("reminders-\(classId)", s) { try await reminders(classId: classId, token: $0) }
    }

    /// nil is no class. `myClass(token:)` also says nil when the request failed, so a nil only
    /// replaces the copy when the backend really answered.
    func myClass(_ s: UserSession) async -> ApiClass? {
        let key = "class"
        guard let token = s.apiToken else { return DiskCache.load(ApiClass.self, key: key, owner: s.username) }
        do {
            let data = try await request(Config.Routes.classesMine, token: token)
            guard !data.isEmpty, let fresh = try? JSONDecoder().decode(ApiClass.self, from: data) else {
                DiskCache.remove(key: key, owner: s.username)
                return nil
            }
            DiskCache.save(fresh, key: key, owner: s.username)
            return fresh
        } catch let error as AppError where error.status == 404 {
            DiskCache.remove(key: key, owner: s.username)
            return nil
        } catch {
            return DiskCache.load(ApiClass.self, key: key, owner: s.username)
        }
    }

    /// The class id to read reminders with: the session's, else the class's.
    func classId(_ s: UserSession) async -> String? {
        if let id = s.classId { return id }
        return await myClass(s)?.id
    }
}
