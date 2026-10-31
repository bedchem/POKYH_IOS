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

    /// Ergebnis des Server-zu-Server-Logins (mit Diagnose für die UI).
    enum UntisLoginResult {
        case ok(token: String, refresh: String)
        case noClass               // klasseId ≤ 0 → Backend verlangt > 0
        case failed(String)        // HTTP-/Netzwerkfehler (Meldung)
        /// This device was signed out somewhere else; only on a renewal. Sign in again by hand.
        case revoked(String)
    }

    /// Server-zu-Server-Login nach erfolgreichem WebUntis-Login (kein Passwort nötig).
    /// Das Backend legt bei gültiger klasseId automatisch ein Konto an. Bei
    /// `role: "parent"` wird ein Elternkonto erstellt (eigene Todos, sieht nur den
    /// Klassennamen, keine Erinnerungen, unsichtbares Mitglied). Für Eltern ist die
    /// klasseId die des Kindes (in UntisClient aufgelöst).
    /// `renewal`: the app signing itself in again (launch, Face ID), not a sign-in by the person.
    /// `school`: where WebUntis checked the account; the build's own school is left out, as on Android.
    /// `method`: "office" for an app key sign-in.
    func loginWithUntis(username: String, klasseId: Int, klasseName: String, role: String = "student",
                        renewal: Bool = false, school: School? = nil, method: String? = nil) async -> UntisLoginResult {
        // Das Backend verlangt klasseId > 0 — die klasseId wird in UntisClient aus
        // mehreren Quellen aufgelöst.
        guard klasseId > 0 else { return .noClass }
        let t = Strings.current.errors
        guard let url = URL(string: "\(base)\(Config.Routes.authLogin)") else { return .failed(t.badAnswer) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.serverKey, forHTTPHeaderField: "X-Server-Key")
        stamp(&req)
        var body: [String: Any] = [
            "username": username, "klasseId": klasseId, "klasseName": klasseName, "role": role, "renewal": renewal,
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
            if j.code.string == "session_revoked" { return .revoked(j.error.string ?? t.loginFailed) }
            return .failed(j.error.string ?? "HTTP \(http.statusCode)")
        }
        guard let token = j.token.string, let refresh = j.refreshToken.string else {
            return .failed(t.badAnswer)
        }
        return .ok(token: token, refresh: refresh)
    }

    /// Direkter App-Login (Nicht-Untis-Konto): Benutzername + Passwort.
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

    /// Ein Heartbeat für die Nutzungsstatistik im Admin-Panel (siehe `UsageReporter`):
    /// Vordergrund-Sekunden und geöffnete Tabs seit dem letzten Ping. Best effort —
    /// ein Fehler wird verschluckt, er darf die App nie stören.
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

    // ── Datenschutzerklärung (siehe PrivacyNotice.swift) ─────────────────────

    struct PrivacyNotice { let version: String }

    /// Which notice the account confirmed, and whether it agreed to the personal usage statistics.
    struct PrivacyStatus {
        let acknowledgedVersion: String?
        var acknowledgedAt: String? = nil
        var usageStats = false
        var usageStatsAt: String? = nil
    }

    /// Die aktuelle Version von der Website, die den Text hält. `nil` ohne Netz.
    func currentPrivacyNotice() async -> PrivacyNotice? {
        guard let url = URL(string: Config.privacyNoticeURL),
              let answer = try? await session.data(from: url),
              (answer.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let j = JSON.parse(answer.0)
        guard let version = j.version.string, !version.isEmpty else { return nil }
        return PrivacyNotice(version: version)
    }

    /// Welche Fassung dieses Konto bestätigt hat. `nil` ohne Antwort (dann nichts zeigen).
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

    // ── Geräte & Anmeldungen ─────────────────────────────────────────────────

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

    func dishes(force: Bool = false) async throws -> [Dish] {
        if !force, let cached = dishCache.get(dishKey) { return cached }
        guard let url = URL(string: "\(base)\(Config.Routes.dishes)") else { throw AppError(message: Strings.current.errors.badAnswer) }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        stamp(&req)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            // Bei Fehler ältere Daten liefern, falls vorhanden (robust).
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
        for (k, v) in j.ratings.dictionary { ratings[k] = v.double ?? 0 }
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
            price: j.price.double,
            allergens: j.allergens.array.compactMap { $0.string },
            tags: j.tags.array.compactMap { $0.string },
            calories: j.calories.double,
            protein: j.protein.double,
            carbs: j.carbs.double,
            fat: j.fat.double
        )
    }
}

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
