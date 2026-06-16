import Foundation

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

    // ── Auth ─────────────────────────────────────────────────────────────────

    /// Ergebnis des Server-zu-Server-Logins (mit Diagnose für die UI).
    enum UntisLoginResult {
        case ok(token: String, refresh: String)
        case noClass               // klasseId ≤ 0 → Backend verlangt > 0
        case failed(String)        // HTTP-/Netzwerkfehler (Meldung)
    }

    /// Server-zu-Server-Login nach erfolgreichem WebUntis-Login (kein Passwort nötig).
    /// Das Backend legt bei gültiger klasseId automatisch ein Konto an.
    func loginWithUntis(username: String, klasseId: Int, klasseName: String) async -> UntisLoginResult {
        // Das Backend verlangt klasseId > 0 — die klasseId wird in UntisClient aus
        // mehreren Quellen aufgelöst.
        guard klasseId > 0 else { return .noClass }
        guard let url = URL(string: "\(base)/auth/login") else { return .failed("Ungültige URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.serverKey, forHTTPHeaderField: "X-Server-Key")
        req.setValue(Config.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": username, "klasseId": klasseId, "klasseName": klasseName,
        ])
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return .failed("Keine Verbindung") }
        let j = JSON.parse(data)
        guard http.statusCode == 200 else {
            return .failed(j.error.string ?? "HTTP \(http.statusCode)")
        }
        guard let token = j.token.string, let refresh = j.refreshToken.string else {
            return .failed("Ungültige Antwort")
        }
        return .ok(token: token, refresh: refresh)
    }

    /// Direkter App-Login (Nicht-Untis-Konto): Benutzername + Passwort.
    func login(username: String, password: String) async throws -> (token: String, refresh: String, user: ApiUser) {
        try await authPost("/auth/login", body: ["username": username.lowercased(), "password": password])
    }

    func register(username: String, password: String) async throws -> (token: String, refresh: String, user: ApiUser) {
        try await authPost("/auth/register", body: ["username": username.lowercased(), "password": password])
    }

    private func authPost(_ path: String, body: [String: Any]) async throws -> (token: String, refresh: String, user: ApiUser) {
        guard let url = URL(string: "\(base)\(path)") else { throw AppError(message: "Ungültige URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let j = JSON.parse(data)
        guard http?.statusCode == 200 else {
            throw AppError(message: j.error.string ?? "Anmeldung fehlgeschlagen.")
        }
        guard let token = j.token.string, let refresh = j.refreshToken.string else {
            throw AppError(message: "Ungültige Antwort vom Server.")
        }
        let user = ApiUser(
            stableUid: j.user.stableUid.string ?? "",
            username: j.user.username.string ?? username(body),
            webuntisKlasseId: j.user.webuntisKlasseId.int,
            webuntisKlasseName: j.user.webuntisKlasseName.string,
            classId: j.user.classId.string,
            isAdmin: j.user.isAdmin.bool ?? false
        )
        return (token, refresh, user)
    }

    private func username(_ body: [String: Any]) -> String { (body["username"] as? String) ?? "" }

    // ── Authentifizierte Requests ──────────────────────────────────────────────

    private func request(_ path: String, method: String = "GET", token: String?, body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "\(base)\(path)") else { throw AppError(message: "Ungültige URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.apiKey, forHTTPHeaderField: "X-API-Key")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        guard let code = http?.statusCode, (200..<300).contains(code) else {
            let j = JSON.parse(data)
            throw AppError(message: j.error.string ?? "HTTP \(http?.statusCode ?? 0)")
        }
        return data
    }

    func me(token: String) async throws -> ApiUser {
        let data = try await request("/auth/me", token: token)
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

    func deleteTodo(username: String, id: String, token: String) async throws {
        _ = try await request("/users/\(username.urlEncoded)/todos/\(id)", method: "DELETE", token: token)
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
        guard let url = URL(string: "\(base)\(Config.Routes.dishes)") else { throw AppError(message: "Ungültige URL") }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            // Bei Fehler ältere Daten liefern, falls vorhanden (robust).
            if let stale = dishCache.stale(dishKey) { return stale }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw AppError(message: "Mensa nicht ladbar (HTTP \(code)).")
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
