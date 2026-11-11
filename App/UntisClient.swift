import Foundation
import PokyhCore

/// Keeps a request where it was sent instead of following a redirect.
private nonisolated final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// WebUntis, natively: what the web frontend's server routes do, done by the app itself.
/// JSON-RPC `authenticate`, the bearer token, timetable, grades, absences, messages.
final class UntisClient {
    static let shared = UntisClient()

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if DEBUG
        StubServer.attach(to: cfg)
        #endif
        session = URLSession(configuration: cfg)
    }

    /// Every call goes to the session's own school.
    private func base(_ s: UserSession) -> String { s.schoolRef.baseString }

    private func cookieHeader(_ sessionId: String, _ school: School) -> String {
        "JSESSIONID=\(sessionId); schoolname=\"\(school.cookie)\""
    }

    private func cookieHeader(_ s: UserSession) -> String { cookieHeader(s.sessionId, s.schoolRef) }

    private func headers(_ s: UserSession) -> [String: String] {
        var h = ["Cookie": cookieHeader(s), "Accept": "application/json"]
        if !s.bearerToken.isEmpty { h["Authorization"] = "Bearer \(s.bearerToken)" }
        return h
    }

    /// The offline session has no WebUntis session at all. Sent anyway, a request would come back
    /// as "signed out" the moment the network returns and lock the app; this way it reads as
    /// "no connection" and the stored copy shows.
    private func requireSession(_ s: UserSession) throws {
        if s.sessionId.isEmpty { throw URLError(.notConnectedToInternet) }
    }

    /// Same for writes, with words for the screen: nothing can be saved offline.
    private func requireSessionToWrite(_ s: UserSession) throws {
        if s.sessionId.isEmpty { throw AppError(message: Strings.current.common.offlineTitle) }
    }

    private func get(_ urlString: String, _ s: UserSession, timeout: TimeInterval? = nil) async throws -> (Data, HTTPURLResponse) {
        try requireSession(s)
        guard let url = URL(string: urlString) else { throw AppError(message: Strings.current.errors.badAnswer) }
        var req = URLRequest(url: url)
        if let timeout { req.timeoutInterval = timeout }
        for (k, v) in headers(s) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AppError(message: Strings.current.errors.untisDown) }
        return (data, http)
    }

    private func isHtmlOrAuthError(_ data: Data, _ http: HTTPURLResponse) -> Bool {
        if http.statusCode == 401 || http.statusCode == 403 { return true }
        let prefix = String(decoding: data.prefix(1), as: UTF8.self)
        return prefix == "<"
    }

    // ── Login ──────────────────────────────────────────────────────────────

    /// Signs in at `school`; without one, at the school the saved account belongs to, else the
    /// build's fallback. An "appkey:" secret signs in with the app key instead of a password.
    /// `token`: the authenticator app's code, asked for after a `TwoFactorRequired`.
    func login(username rawUsername: String, password: String, token: String? = nil, school: School? = nil) async throws -> UserSession {
        let username = rawUsername.trimmingCharacters(in: .whitespaces).lowercased()
        let t = Strings.current
        guard !username.isEmpty, !password.isEmpty else {
            throw AppError(message: t.errors.needCredentials)
        }
        let school = school ?? CredentialStore.savedSchool(for: username) ?? .fallback

        // An Office 365 account: the app key instead of a password.
        if AppKey.isKey(password) {
            return try await loginWithKey(user: username, key: String(password.dropFirst(AppKey.prefix.count)), school: school)
        }

        // With the code: only WebUntis' own sign-in form takes it.
        if let token { return try await loginWithForm(user: username, password: password, token: token, school: school) }

        // 1. JSON-RPC authenticate
        let rpcBody: [String: Any] = [
            "id": "pockyh-web", "method": "authenticate",
            "params": ["user": username, "password": password, "client": Config.untisClient],
            "jsonrpc": "2.0",
        ]
        guard let rpcURL = URL(string: "\(school.baseString)\(Config.Routes.jsonRpc)?school=\(school.query)") else {
            throw AppError(message: t.errors.badAnswer)
        }
        var req = URLRequest(url: rpcURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: rpcBody)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AppError(message: t.errors.untisDown) }

        let sessionId = Self.sessionId(http) ?? ""

        let json = JSON.parse(data)
        if json.error.exists {
            // Two-factor accounts can't sign in through JSON-RPC, the sign-in form tells if that's
            // why. Not after a plain wrong password (-8504): every typo would count twice
            // towards WebUntis' lock-out.
            if json.error.code.int != -8504 {
                let form = await formLogin(user: username, password: password, token: nil, school: school)
                switch form.answer {
                case .ok: return try await completeFormLogin(user: username, sessionId: form.sessionId, school: school)
                case .codeRequired: throw TwoFactorRequired(wrongCode: false)
                default: break
                }
            }
            let msg = json.error.message.string ?? t.errors.loginFailed
            throw AppError(message: msg)
        }
        guard let studentId = json.result.personId.int else {
            throw AppError(message: t.errors.loginFailed)
        }
        return try await completeLogin(user: username, sessionId: sessionId, studentId: studentId,
                                       klasseId: json.result.klasseId.int ?? 0,
                                       personType: json.result.personType.int, school: school)
    }

    /// The app key sign-in: the one-time code of the moment through WebUntis' mobile interface
    /// (`getUserData2017`), as the official app does. The same session comes back as for a password.
    private func loginWithKey(user: String, key: String, school: School) async throws -> UserSession {
        let t = Strings.current
        let now = Date()
        let body: [String: Any] = [
            "id": "pokyh-app", "method": "getUserData2017", "jsonrpc": "2.0",
            "params": [["auth": ["clientTime": Int(now.timeIntervalSince1970 * 1000), "user": user, "otp": AppKey.totp(key, at: now)]]],
        ]
        guard let url = URL(string: "\(school.baseString)\(Config.Routes.jsonRpcIntern)?m=getUserData2017&school=\(school.query)&v=i2.2") else {
            throw AppError(message: t.errors.badAnswer)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError(message: t.errors.untisDown)
        }
        let json = JSON.parse(data)
        if json.error.exists || !json.result.exists {
            if json.error.code.int == -8504 { throw AppError(message: t.login.badKey) }
            throw AppError(message: json.error.message.string ?? t.errors.loginFailed)
        }
        guard let sessionId = Self.sessionId(http), !sessionId.isEmpty else { throw AppError(message: t.errors.loginFailed) }
        let u = json.result.userData
        let personId = max(u.elemId.int ?? 0, 0)
        let personType: Int?
        switch u.elemType.string?.uppercased() {
        case "TEACHER": personType = 2
        case "STUDENT": personType = 5
        case "PARENT", "LEGAL_GUARDIAN": personType = 12
        default: personType = nil
        }
        let klassen = u.klassenIds.array.compactMap(\.int).filter { $0 > 0 }
        if personId == 0 { return try await completeFormLogin(user: user, sessionId: sessionId, school: school) }
        return try await completeLogin(user: user, sessionId: sessionId, studentId: personId,
                                       klasseId: klassen.count == 1 ? klassen[0] : 0, personType: personType, school: school)
    }

    /// A session that names no person yet: the app data does (`user.person.id`).
    /// WebUntis' own sign-in form, as its website uses it: the way that knows the second factor.
    /// It wants an anonymous session and its CSRF token first, from the school's sign-in page.
    private func formLogin(user: String, password: String, token: String?, school: School) async -> (answer: FormLoginAnswer, sessionId: String) {
        guard let pageURL = URL(string: "\(school.baseString)/?school=\(school.query)"),
              let formURL = URL(string: school.baseString + Config.Routes.formLogin) else { return (.unavailable, "") }
        var page = URLRequest(url: pageURL)
        page.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (html, pageResp) = try? await session.data(for: page),
              let pageHTTP = pageResp as? HTTPURLResponse,
              let anonymous = Self.sessionId(pageHTTP) else { return (.unavailable, "") }
        let config = Self.pageConfig(from: html)

        var fields = [("school", school.loginName), ("j_username", user), ("j_password", password)]
        if let token { fields.append(("token", token)) }
        var req = URLRequest(url: formURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(cookieHeader(anonymous, school), forHTTPHeaderField: "Cookie")
        if let csrf = config.csrf { req.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN") }
        if let tenant = config.tenant { req.setValue(tenant, forHTTPHeaderField: "Tenant-Id") }
        req.httpBody = FormLoginAnswer.formBody(fields)
        // A redirect would land on the HTML page and lose the session set on the way there.
        guard let (data, resp) = try? await session.data(for: req, delegate: NoRedirects()),
              let http = resp as? HTTPURLResponse else { return (.unavailable, "") }
        return (FormLoginAnswer.parse(data, status: http.statusCode, sentCode: token != nil), Self.sessionId(http) ?? anonymous)
    }

    private func loginWithForm(user: String, password: String, token: String, school: School) async throws -> UserSession {
        let t = Strings.current.errors
        let form = await formLogin(user: user, password: password, token: token, school: school)
        switch form.answer {
        case .ok: return try await completeFormLogin(user: user, sessionId: form.sessionId, school: school)
        case .codeRequired, .codeWrong: throw TwoFactorRequired(wrongCode: true)
        case .badCredentials: throw AppError(message: t.badCredentials)
        case .refused: throw AppError(message: t.refused)
        case .unavailable: throw AppError(message: t.noConnection)
        }
    }

    /// The sign-in form names no person: the app data does (`user.person.id`).
    private func completeFormLogin(user: String, sessionId: String, school: School) async throws -> UserSession {
        var bare = UserSession(sessionId: sessionId, bearerToken: "", studentId: 0, klasseId: 0, klasseName: "",
                               username: user, personName: nil, personType: nil, isParent: false)
        bare.school = school
        bare.bearerToken = (try? await fetchToken(bare)) ?? ""
        let root = (try? await fetchAppData(bare)).flatMap { $0 } ?? JSON(nil)
        let node = root.data.user.exists ? root.data.user : root.user
        let personId = node.person.id.int ?? node.personId.int ?? 0
        guard personId > 0 else { throw AppError(message: Strings.current.errors.loginFailed) }
        return try await completeLogin(user: user, sessionId: sessionId, studentId: personId, klasseId: 0, personType: nil, school: school)
    }

    /// JSESSIONID out of any of the Set-Cookie lines.
    private static func sessionId(_ http: HTTPURLResponse) -> String? {
        let setCookie = http.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        return match(#"JSESSIONID=([^;,]+)"#, in: setCookie)
    }

    /// Everything after WebUntis let the account in: bearer token, class, student list, app data.
    private func completeLogin(user username: String, sessionId: String, studentId: Int, klasseId: Int, personType: Int?, school: School) async throws -> UserSession {
        var s = UserSession(
            sessionId: sessionId, bearerToken: "", studentId: studentId,
            klasseId: klasseId, klasseName: "", username: username,
            personName: nil, personType: personType, isParent: false
        )
        s.school = school

        // 2 to 4: the bearer token, the class name and the student list, side by side. None
        // of them needs the bearer token; the token endpoint and getKlassen/getStudents
        // (JSON-RPC) go by the JSESSIONID cookie, so it's one round trip instead of three.
        // The tasks get a copy that doesn't change: `s` is only changed after the awaits,
        // so nothing races.
        let snapshot = s
        async let tokenTask = fetchToken(snapshot)
        async let klassen = fetchKlassen(snapshot, klasseId: klasseId)
        async let students = fetchStudents(snapshot)
        s.bearerToken = (try? await tokenTask) ?? ""
        let klasseName = (try? await klassen) ?? ""
        let studentList = (try? await students) ?? []
        s.klasseName = klasseName

        // Student or guardian, name and klasseId. personType 5 is a student in WebUntis,
        // so a student is never taken for a guardian, even when `getStudents` is empty.
        let isStudentType = (personType == 5)
        let isStudentSelf = studentList.contains { $0.id == studentId }
        let isParentCandidate = !isStudentType && !isStudentSelf

        if isStudentType || isStudentSelf {
            let me = studentList.first { $0.id == studentId }
            s.personName = me?.name
            s.firstName = me.map(\.fore).flatMap { $0.isEmpty ? nil : $0 }
            // The own klasseId from the student record when `authenticate` gave 0.
            if s.klasseId <= 0, let kid = me?.klasseId, kid > 0 { s.klasseId = kid }
        } else if let first = studentList.first {
            // Guardians that do get a student list.
            s.studentId = first.id
            if let kid = first.klasseId { s.klasseId = kid }
            s.personName = first.name
            s.firstName = first.fore.isEmpty ? nil : first.fore
            s.isParent = true
        }

        // The app data at most once (it's several endpoints) and only when something's
        // missing: no klasseId, or a guardian without a student list.
        let needsParentResolve = isParentCandidate && studentList.isEmpty
        if s.klasseId <= 0 || needsParentResolve, let appData = try? await fetchAppData(s) {
            if needsParentResolve {
                s.isParent = detectParent(appData)
                if let childId = extractChildStudentId(appData, exclude: studentId) { s.studentId = childId }
                if s.personName == nil { s.personName = extractChildName(appData) }
            }
            if s.klasseId <= 0, let kid = extractKlasseId(appData, personId: s.studentId), kid > 0 {
                s.klasseId = kid
            }
            s.imageUrl = extractImageUrl(appData, isParent: s.isParent)
        }

        // Last resort: some schools have the class only in the timetable (authenticate gives 0,
        // getStudents is locked, app/data has no class). The class name comes from the
        // timetable and getKlassen turns it into the id; it's cached. Guardians too: then
        // s.studentId is the child, whose timetable has the class.
        if s.klasseId <= 0, (isStudentType || s.isParent), s.studentId > 0 {
            if let cached = Self.cachedKlasse(username: s.username) {
                s.klasseId = cached.id
                if s.klasseName.isEmpty { s.klasseName = cached.name }
            } else if let resolved = await resolveStudentClass(s) {
                s.klasseId = resolved.id
                if s.klasseName.isEmpty { s.klasseName = resolved.name }
                Self.cacheKlasse(username: s.username, id: resolved.id, name: resolved.name)
            }
        }

        if s.personName?.isEmpty == true { s.personName = nil }

        return s
    }

    /// Whether WebUntis still takes the session: only a live one gets a bearer token. Unknown
    /// (no connection) counts as alive, there's nothing better to hand over then.
    func sessionAlive(_ s: UserSession) async -> Bool {
        guard !s.sessionId.isEmpty else { return false }
        guard let token = try? await fetchToken(s) else { return true }
        return !token.isEmpty
    }

    private func fetchToken(_ s: UserSession) async throws -> String {
        let (data, http) = try await get("\(base(s))/api/token/new", s)
        guard http.statusCode == 200 else { return "" }
        let tok = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return tok.filter { $0 == "." }.count == 2 ? tok : ""
    }

    private func rpc(_ method: String, _ s: UserSession, id: String) async throws -> JSON {
        guard let url = URL(string: "\(base(s))/jsonrpc.do?school=\(s.schoolRef.query)") else {
            throw AppError(message: Strings.current.errors.badAnswer)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cookieHeader(s), forHTTPHeaderField: "Cookie")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": id, "method": method, "params": [:], "jsonrpc": "2.0",
        ])
        let (data, _) = try await session.data(for: req)
        return JSON.parse(data).result
    }

    private func fetchKlassen(_ s: UserSession, klasseId: Int) async throws -> String {
        let result = try await rpc("getKlassen", s, id: "pockyh-klassen")
        for k in result.array where k.id.int == klasseId {
            return k.name.string ?? ""
        }
        return ""
    }

    // ── The class from the timetable (students) ────────────────────────────────
    // Each lesson names the class as an element with `type == "CLASS"` but no numeric
    // id; getKlassen maps the name to one.

    /// The class name from the timetable, mapped to the numeric klasseId: (id, name) or nil.
    private func resolveStudentClass(_ s: UserSession) async -> (id: Int, name: String)? {
        guard let cls = await classNameFromTimetable(s) else { return nil }
        guard let id = await klasseId(forName: cls, s), id > 0 else { return nil }
        return (id, cls.short)
    }

    /// Finds a week with lessons and returns the class's (shortName, longName). Vocational
    /// schools teach in blocks with whole weeks off, so it samples the whole school year,
    /// the current week first.
    private func classNameFromTimetable(_ s: UserSession) async -> (short: String, long: String)? {
        let cal = Calendar.current
        let sy = SchoolDates.currentSchoolYear
        var days: [Date] = [Date()]
        // The middle of each school month: September to December, then January to June.
        for m in [9, 10, 11, 12] {
            if let d = DateFmt.iso.date(from: String(format: "%04d-%02d-15", sy, m)) { days.append(d) }
        }
        for m in [1, 2, 3, 4, 5, 6] {
            if let d = DateFmt.iso.date(from: String(format: "%04d-%02d-15", sy + 1, m)) { days.append(d) }
        }
        for day in days {
            let start = DateFmt.isoString(day)
            let end = DateFmt.isoString(cal.date(byAdding: .day, value: 5, to: day) ?? day)
            let url = "\(base(s))\(Config.Routes.timetable)?start=\(start)&end=\(end)&format=1&resourceType=STUDENT&resources=\(s.studentId)&periodTypes=&timetableType=MY_TIMETABLE&layout=START_TIME"
            guard let (data, http) = try? await get(url, s, timeout: 8), http.statusCode == 200 else { continue }
            if let cls = Self.extractClassName(JSON.parse(data)) { return cls }
        }
        return nil
    }

    /// The class element (`type == "CLASS"`) among a lesson's positions.
    static func extractClassName(_ json: JSON) -> (short: String, long: String)? {
        for day in json.days.array {
            for ge in day.gridEntries.array {
                for posKey in ["position1", "position2", "position3", "position4", "position5", "position6", "position7"] {
                    for el in ge[posKey].array where el.current.type.string == "CLASS" {
                        let short = el.current.shortName.string ?? el.current.displayName.string ?? ""
                        guard !short.isEmpty else { continue }
                        return (short, el.current.longName.string ?? short)
                    }
                }
            }
        }
        return nil
    }

    /// `getKlassen` with the school year. Without `schoolyearId` WebUntis answers
    /// "schoolyear is null" between two years.
    func getKlassen(schoolyearId: Int?, _ s: UserSession) async throws -> JSON {
        guard let url = URL(string: "\(base(s))/jsonrpc.do?school=\(s.schoolRef.query)") else {
            throw AppError(message: Strings.current.errors.badAnswer)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cookieHeader(s), forHTTPHeaderField: "Cookie")
        var params: [String: Any] = [:]
        if let schoolyearId { params["schoolyearId"] = schoolyearId }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": "pockyh-klassen", "method": "getKlassen", "params": params, "jsonrpc": "2.0",
        ])
        let (data, _) = try await session.data(for: req)
        return JSON.parse(data)
    }

    /// A year's school year id from getSchoolyears; works when "current" is null too.
    func resolvedSchoolyearId(_ s: UserSession) async -> Int? {
        let id = try? await schoolyearId(year: SchoolDates.currentSchoolYear, s)
        if let id, id > 0 { return id }
        return nil
    }

    /// The numeric klasseId by matching the name in getKlassen (with the school year).
    private func klasseId(forName cls: (short: String, long: String), _ s: UserSession) async -> Int? {
        let syId = await resolvedSchoolyearId(s)
        guard let j = try? await getKlassen(schoolyearId: syId, s) else { return nil }
        let arr = j.result.array
        let short = cls.short.lowercased()
        // 1) exakter Name-Match (shortName = Klassenbezeichnung, z. B. "3.BFS-FI").
        for k in arr where (k.name.string ?? "").lowercased() == short {
            if let id = k.id.int, id > 0 { return id }
        }
        // 2) Fallback: longName-Teilstring.
        let long = cls.long.lowercased()
        for k in arr {
            let ln = (k.longName.string ?? "").lowercased()
            if !ln.isEmpty, long.contains(ln) || ln.contains(short), let id = k.id.int, id > 0 { return id }
        }
        return nil
    }

    // ── Class cache, per user and school year: saves asking the timetable again ──
    private static func klasseCacheKey(_ username: String) -> String {
        "pokyh_klasse_\(username.lowercased())_\(SchoolDates.currentSchoolYear)"
    }
    private static func cachedKlasse(username: String) -> (id: Int, name: String)? {
        guard let d = UserDefaults.standard.dictionary(forKey: klasseCacheKey(username)),
              let id = d["id"] as? Int, id > 0 else { return nil }
        return (id, d["name"] as? String ?? "")
    }
    private static func cacheKlasse(username: String, id: Int, name: String) {
        UserDefaults.standard.set(["id": id, "name": name], forKey: klasseCacheKey(username))
    }

    /// (id, klasseId?, name, first name) of the students this account can see.
    private func fetchStudents(_ s: UserSession) async throws -> [(id: Int, klasseId: Int?, name: String, fore: String)] {
        let result = try await rpc("getStudents", s, id: "pockyh-students")
        return result.array.compactMap { st in
            guard let id = st.id.int else { return nil }
            let fore = st.foreName.string ?? st.firstName.string ?? ""
            let long = st.longName.string ?? st.lastName.string ?? ""
            let full = [fore, long].filter { !$0.isEmpty }.joined(separator: " ")
            // klasseId as it is, or inside a `klasse` object.
            let kid = st.klasseId.int ?? st.klasse.id.int
            return (id, kid, full.isEmpty ? (st.name.string ?? "") : full, fore)
        }
    }

    // ── App data (guardian accounts) ───────────────────────────────────────────

    private static let appDataPaths = [
        "/api/rest/view/v1/app/data", "/api/app/data",
        "/api/rest/view/v1/users/me/data", "/api/rest/view/v2/app/data",
    ]

    /// A diagnosis on request: which app data WebUntis sends and where the class is (every
    /// field whose key has "klass" in it). No passwords or tokens, only the structure and
    /// the class values, so the lookup can be fixed for a school.
    func classDiagnostics(_ s: UserSession) async -> String {
        var out = "studentId=\(s.studentId)  personType=\(s.personType.map(String.init) ?? "nil")\n"
        out += "klasseId=\(s.klasseId)  klasseName=\(s.klasseName.isEmpty ? "–" : s.klasseName)\n\n"

        // 1) getStudents (JSON-RPC), which often has each student's klasseId.
        out += "── getStudents ──\n"
        if let j = try? await rpcFull("getStudents", s, id: "diag-students") {
            let arr = j.result.array
            if arr.isEmpty {
                out += j.error.exists ? "Fehler: \(j.error.message.string ?? "?")\n" : "leer\n"
            } else {
                out += "\(arr.count) Einträge, erster roh:\n"
                if let first = arr.first?.raw { out += Self.pretty(first, max: 800) + "\n" }
            }
        } else { out += "keine Antwort\n" }

        // 2) App data: the `user` object, which usually has the class and the role.
        out += "\n── app/data ──\n"
        for path in Self.appDataPaths {
            guard let (data, http) = try? await get("\(base(s))\(path)", s, timeout: 6) else { continue }
            guard http.statusCode == 200, case let dict as [String: Any] = JSON.parse(data).raw else { continue }
            out += "\(path) → top: \(dict.keys.sorted().joined(separator: ", "))\n"
            if let user = dict["user"] { out += "user:\n" + Self.pretty(user, max: 1500) + "\n" }
            break
        }

        // 3) The timetable, sometimes the only place with the class (several weeks, since
        //    the current one can be empty at the end of the year).
        out += "\n── timetable (erste Stunde mit Inhalt) ──\n"
        let sy = SchoolDates.currentSchoolYear
        let candidates: [Date] = [
            Date(),
            DateFmt.iso.date(from: "\(sy)-11-17"),
            DateFmt.iso.date(from: "\(sy + 1)-03-16"),
            DateFmt.iso.date(from: "\(sy)-10-13"),
        ].compactMap { $0 }
        var dumped = false
        for day in candidates {
            let start = DateFmt.isoString(day)
            let end = DateFmt.isoString(Calendar.current.date(byAdding: .day, value: 5, to: day) ?? day)
            let url = "\(base(s))/api/rest/view/v1/timetable/entries?start=\(start)&end=\(end)&format=1&resourceType=STUDENT&resources=\(s.studentId)&periodTypes=&timetableType=MY_TIMETABLE&layout=START_TIME"
            guard let (data, http) = try? await get(url, s, timeout: 8), http.statusCode == 200 else { continue }
            if let first = JSON.parse(data).days.array.flatMap({ $0.gridEntries.array }).first?.raw {
                out += "Woche ab \(start):\n" + Self.pretty(first, max: 2000)
                dumped = true
                break
            }
        }
        if !dumped { out += "keine Stunden in den geprüften Wochen gefunden" }

        // 4) The whole lookup: name from the timetable, getKlassen, id.
        out += "\n\n── Klassen-Auflösung ──\n"
        if let cls = await classNameFromTimetable(s) {
            out += "Name (Stundenplan): \(cls.short)  |  \(cls.long)\n"
            let syId = await resolvedSchoolyearId(s)
            out += "schoolyearId: \(syId.map(String.init) ?? "nil")\n"
            if let j = try? await getKlassen(schoolyearId: syId, s) {
                let arr = j.result.array
                if arr.isEmpty {
                    let err = j.error.message.string ?? "?"
                    out += j.error.exists ? "getKlassen: Fehler: \(err)\n" : "getKlassen: leer\n"
                } else {
                    out += "getKlassen: \(arr.count) Klassen\n"
                    if let m = arr.first(where: { ($0.name.string ?? "").lowercased() == cls.short.lowercased() }) {
                        out += "→ TREFFER: id=\(m.id.int ?? -1)  name=\(m.name.string ?? "")\n"
                    } else {
                        out += "→ kein Namens-Treffer. Beispiele: "
                        out += arr.prefix(10).map { "\($0.name.string ?? "?")=\($0.id.int ?? -1)" }.joined(separator: ", ") + "\n"
                    }
                }
            } else {
                out += "getKlassen: keine Antwort\n"
            }
        } else {
            out += "Kein Klassen-Element im Stundenplan gefunden.\n"
        }
        return out
    }

    /// Short, trimmed JSON for the diagnosis.
    private static func pretty(_ obj: Any, max: Int) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { return String(String(describing: obj).prefix(max)) }
        return String(String(decoding: data, as: UTF8.self).prefix(max))
    }

    private func fetchAppData(_ s: UserSession) async throws -> JSON? {
        // Each endpoint on its own and with a time limit, so a slow one can't hold up the
        // whole sign-in (it used to hang for seconds).
        for path in Self.appDataPaths {
            guard let (data, http) = try? await get("\(base(s))\(path)", s, timeout: 6) else { continue }
            if isHtmlOrAuthError(data, http) || http.statusCode != 200 { continue }
            let json = JSON.parse(data)
            if json.raw is [String: Any] { return json }
        }
        return nil
    }

    private func detectParent(_ json: JSON) -> Bool {
        let roles = ["PARENT", "GUARDIAN", "LEGAL_GUARDIAN", "LEGALGUARDIAN", "ERZIEHUNGSBERECHTIGT", "PARENT_ROLE", "PERSONTYPE_PARENT"]
        var found = false
        collectStrings(json.raw) { if roles.contains($0.uppercased()) { found = true } }
        return found
    }

    /// The child's student id from the app data (user.students[0].id), as on the web.
    private func extractChildStudentId(_ json: JSON, exclude: Int) -> Int? {
        var fromArrays: [Int] = []
        var heuristic: [Int] = []
        func walk(_ node: Any?, depth: Int) {
            guard depth <= 8 else { return }
            if let arr = node as? [Any] { for v in arr { walk(v, depth: depth + 1) }; return }
            guard let o = node as? [String: Any] else { return }
            for key in ["students", "children"] {
                if let arr = o[key] as? [Any] {
                    for child in arr {
                        if let c = child as? [String: Any] {
                            let id = (c["id"] ?? c["studentId"] ?? c["personId"]).flatMap { ($0 as? NSNumber)?.intValue }
                            if let id, id > 0, id != exclude { fromArrays.append(id) }
                        }
                    }
                }
            }
            let hasKlasse = o["klasseId"] != nil || o["klasse"] != nil || o["className"] != nil || o["klasseName"] != nil
            let typeStr = String(describing: o["type"] ?? o["role"] ?? o["personType"] ?? "").uppercased()
            if hasKlasse || typeStr.contains("STUDENT") || typeStr == "5" {
                if let id = (o["id"] ?? o["personId"] ?? o["studentId"]).flatMap({ ($0 as? NSNumber)?.intValue }),
                   id > 0, id != exclude { heuristic.append(id) }
            }
            for v in o.values { walk(v, depth: depth + 1) }
        }
        walk(json.raw, depth: 0)
        return fromArrays.first ?? heuristic.first
    }

    /// The class id from the app data, for students whose `authenticate` and `getStudents`
    /// give none. First the signed-in student's class
    /// (`personId`), then `students[].klasseId`, then any `klasse.id` or `klasseId`.
    private func extractKlasseId(_ json: JSON, personId: Int) -> Int? {
        var matched: [Int] = []        // the signed-in pupil's own class
        var fromStudents: [Int] = []   // aus students/children-Arrays
        var fromKlassenArr: [Int] = [] // from masterData's `klassen`: a pupil's own class
        var fromKlasseObj: [Int] = []  // beliebiges klasse.id
        var fromField: [Int] = []      // beliebiges klasseId
        func intVal(_ any: Any?) -> Int? { (any as? NSNumber)?.intValue ?? (any as? String).flatMap(Int.init) }
        func klasseIdOf(_ o: [String: Any]) -> Int? {
            if let k = o["klasse"] as? [String: Any], let id = intVal(k["id"]), id > 0 { return id }
            if let id = intVal(o["klasseId"]), id > 0 { return id }
            return nil
        }
        func walk(_ node: Any?, depth: Int) {
            guard depth <= 8 else { return }
            if let arr = node as? [Any] { for v in arr { walk(v, depth: depth + 1) }; return }
            guard let o = node as? [String: Any] else { return }
            // The signed-in student's own record?
            let oid = intVal(o["id"]) ?? intVal(o["personId"]) ?? intVal(o["studentId"])
            if let oid, oid == personId, let kid = klasseIdOf(o) { matched.append(kid) }
            for case let c as [String: Any] in (o["students"] as? [Any] ?? []) {
                if let kid = klasseIdOf(c) { fromStudents.append(kid) }
            }
            for case let c as [String: Any] in (o["children"] as? [Any] ?? []) {
                if let kid = klasseIdOf(c) { fromStudents.append(kid) }
            }
            // A `klassen` array (masterData.klassen, say), narrowed to the own class for
            // students; the objects carry it as `id`.
            for case let k as [String: Any] in (o["klassen"] as? [Any] ?? []) {
                if let id = intVal(k["id"]), id > 0 { fromKlassenArr.append(id) }
            }
            if let k = o["klasse"] as? [String: Any], let id = intVal(k["id"]), id > 0 { fromKlasseObj.append(id) }
            if let id = intVal(o["klasseId"]), id > 0 { fromField.append(id) }
            for v in o.values { walk(v, depth: depth + 1) }
        }
        walk(json.raw, depth: 0)
        return matched.first ?? fromStudents.first ?? fromKlassenArr.first ?? fromKlasseObj.first ?? fromField.first
    }

    private func extractChildName(_ json: JSON) -> String? {
        let students = json.data.user.students.array.first ?? json.user.students.array.first ?? json.students.array.first
        if let n = students?.displayName.string, !n.trimmingCharacters(in: .whitespaces).isEmpty { return n }
        return nil
    }

    private func collectStrings(_ node: Any?, depth: Int = 0, _ visit: (String) -> Void) {
        guard depth <= 8 else { return }
        if let s = node as? String { visit(s); return }
        if let arr = node as? [Any] { for v in arr { collectStrings(v, depth: depth + 1, visit) }; return }
        if let o = node as? [String: Any] { for v in o.values { collectStrings(v, depth: depth + 1, visit) } }
    }

    // ── Caches (in memory, keyed by student, so accounts never mix) ────────────
    private let timetableCache = TTLCache<String, [TimetableEntry]>(ttl: 300)   // key: "studentId-yyyy-MM-dd"
    private let gradesCache = TTLCache<String, [SubjectGrades]>(ttl: 300)        // key: "studentId-year"

    private let examsCache = TTLCache<Int, [TimetableEntry]>(ttl: 600)   // key: studentId

    func clearCaches() { timetableCache.removeAll(); gradesCache.removeAll(); examsCache.removeAll() }

    /// Upcoming exams (from today, about 40 days), cached.
    func upcomingExams(_ s: UserSession) async throws -> [TimetableEntry] {
        if let cached = examsCache.get(s.studentId) { return cached }
        let todayNum = DateFmt.num(Date())
        let all = try await storedOrFresh(diskKey("exams", s), s) { () async throws -> [TimetableEntry] in
            let start = DateFmt.isoString(Date())
            let end = DateFmt.isoString(Calendar.current.date(byAdding: .day, value: 40, to: Date()) ?? Date())
            let url = "\(base(s))\(Config.Routes.timetable)?start=\(start)&end=\(end)&format=1&resourceType=STUDENT&resources=\(s.studentId)&periodTypes=&timetableType=MY_TIMETABLE&layout=START_TIME"
            let (data, http) = try await get(url, s)
            if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
            guard http.statusCode == 200 else { return [] }
            return Self.parseTimetable(JSON.parse(data)).filter(\.isExam)
        }
        // A stored copy can be days old: what's past by now drops out.
        let exams = all
            .filter { $0.date >= todayNum }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.startTime < $1.startTime }
        if !s.sessionId.isEmpty { examsCache.set(s.studentId, exams) }
        return exams
    }

    // ── Timetable ────────────────────────────────────────────────────────────

    /// A look into the cache, no network: a week loaded ahead shows at once, without a
    /// spinner flashing.
    func cachedTimetable(date: String, _ s: UserSession) -> [TimetableEntry]? {
        let key = "\(s.schoolRef.loginName)-\(s.studentId)-\(date)"  // two schools can share a student id
        if let mem = timetableCache.get(key) { return mem }
        // Offline (no token): the stored week at once, without a spinner.
        if s.bearerToken.isEmpty { return DiskCache.load([TimetableEntry].self, key: "tt-\(key)", owner: s.username) }
        return nil
    }

    /// The week as last loaded, to show while it's asked again.
    func storedTimetable(date: String, _ s: UserSession) async -> [TimetableEntry]? {
        let key = "\(s.schoolRef.loginName)-\(s.studentId)-\(date)"
        if let mem = timetableCache.get(key) { return mem }
        return await DiskCache.loaded([TimetableEntry].self, key: "tt-\(key)", owner: s.username)
    }

    func timetable(date: String, _ s: UserSession) async throws -> [TimetableEntry] {
        let key = "\(s.schoolRef.loginName)-\(s.studentId)-\(date)"  // two schools can share a student id
        if let cached = timetableCache.get(key) { return cached }
        // An offline session has no token: a request without one gets a sign-in page back and
        // would sign out. So it's the stored week instead.
        if s.bearerToken.isEmpty {
            return await DiskCache.loaded([TimetableEntry].self, key: "tt-\(key)", owner: s.username) ?? []
        }
        // Monday to Saturday
        guard let d = DateFmt.iso.date(from: date) else { throw AppError(message: Strings.current.errors.badAnswer) }
        let end = DateFmt.isoString(Calendar.current.date(byAdding: .day, value: 5, to: d) ?? d)
        let url = "\(base(s))/api/rest/view/v1/timetable/entries?start=\(date)&end=\(end)&format=1&resourceType=STUDENT&resources=\(s.studentId)&periodTypes=&timetableType=MY_TIMETABLE&layout=START_TIME"
        do {
            let (data, http) = try await get(url, s)
            if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
            guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.timetable(http.statusCode)) }
            let entries = Self.parseTimetable(JSON.parse(data))
            timetableCache.set(key, entries)
            DiskCache.save(entries, key: "tt-\(key)", owner: s.username)   // for offline
            return entries
        } catch let netErr as URLError {
            // Only a real network failure falls back to the stored copy, never an auth error.
            if let offline = DiskCache.load([TimetableEntry].self, key: "tt-\(key)", owner: s.username) { return offline }
            throw netErr
        }
    }

    static func parseTimetable(_ json: JSON) -> [TimetableEntry] {
        var entries: [TimetableEntry] = []
        for day in json.days.array {
            guard let dateStr = day.date.string else { continue }
            let dateNum = UntisRange.day(Int(dateStr.replacingOccurrences(of: "-", with: "")))
            for ge in day.gridEntries.array {
                guard let startStr = ge.duration.start.string,
                      let endStr = ge.duration.end.string else { continue }
                func hm(_ iso: String) -> Int {
                    let parts = iso.split(separator: "T")
                    guard parts.count == 2 else { return 0 }
                    let t = parts[1].split(separator: ":")
                    let h = UntisRange.clock(Int(t.first ?? "0"))
                    let m = t.count > 1 ? UntisRange.clock(Int(t[1])) : 0
                    return UntisRange.clock(h * 100 + m)
                }
                let startTime = hm(startStr), endTime = hm(endStr)

                let pos1 = ge.position1.array, pos2 = ge.position2.array, pos3 = ge.position3.array
                let activeTeachers = pos1.compactMap { $0.current.displayName.string }.filter { !$0.isEmpty }
                let activeTeachersLong = pos1.compactMap { $0.current.longName.string ?? $0.current.displayName.string }.filter { !$0.isEmpty }
                let removedTeachers = pos1.compactMap { $0.removed.displayName.string }.filter { !$0.isEmpty }
                let removedTeachersLong = pos1.compactMap { $0.removed.longName.string ?? $0.removed.displayName.string }.filter { !$0.isEmpty }
                let activeSub = pos2.first { $0.current.exists }?.current
                let removedSub = pos2.first { $0.removed.exists }?.removed
                let activeRooms = pos3.compactMap { $0.current.displayName.string }.filter { !$0.isEmpty }
                let removedRooms = pos3.compactMap { $0.removed.displayName.string }.filter { !$0.isEmpty }

                let type = ge.type.string ?? ""
                let status = ge.status.string ?? ""
                let isExam = type == "EXAM"
                let isCancelled = status == "CANCELLED"
                let isChanged = status == "CHANGED"
                let extras = PeriodExtras.read(ge.raw)
                let isSubstitution = isChanged && (!removedTeachers.isEmpty || !extras.addedTeachers.isEmpty)

                entries.append(TimetableEntry(
                    id: ge.ids[0].int ?? 0,
                    lessonId: ge.ids[0].int ?? 0,
                    date: dateNum, startTime: startTime, endTime: endTime,
                    subjectName: activeSub?.shortName.string ?? removedSub?.shortName.string ?? "",
                    subjectLong: activeSub?.longName.string ?? removedSub?.longName.string ?? "",
                    teacherName: activeTeachers.joined(separator: ", "),
                    teacherLongName: activeTeachersLong.isEmpty ? nil : activeTeachersLong.joined(separator: ", "),
                    roomName: activeRooms.joined(separator: ", "),
                    isExam: isExam, isCancelled: isCancelled, isSubstitution: isSubstitution,
                    isAdditional: type == "ADDITIONAL",
                    originalSubject: removedSub?.shortName.string ?? "",
                    originalSubjectLong: removedSub?.longName.string ?? "",
                    originalTeacher: removedTeachers.joined(separator: ", "),
                    originalTeacherLong: removedTeachersLong.isEmpty ? nil : removedTeachersLong.joined(separator: ", "),
                    originalRoom: removedRooms.joined(separator: ", "),
                    note: extras.lessonInfo ?? extras.lessonText,
                    examDescription: ge.exam.description.string,
                    addedTeachers: extras.addedTeachers,
                    addedSubjects: extras.addedSubjects,
                    addedRooms: extras.addedRooms,
                    icons: extras.icons,
                    substitutionText: extras.substitutionText,
                    lessonText: extras.lessonText,
                    texts: extras.texts
                ))
            }
        }
        return entries.sorted { $0.date != $1.date ? $0.date < $1.date : $0.startTime < $1.startTime }
    }

    // ── Noten ──────────────────────────────────────────────────────────────

    /// The grades as last loaded, to show while they're asked again.
    func storedGrades(year: Int?, _ s: UserSession) async -> [SubjectGrades]? {
        let cacheKey = "\(s.schoolRef.loginName)-\(s.studentId)-\(year ?? 0)"
        if let mem = gradesCache.get(cacheKey) { return mem }
        return await DiskCache.loaded([SubjectGrades].self, key: "grades-\(cacheKey)", owner: s.username)
    }

    func grades(year: Int?, _ s: UserSession) async throws -> [SubjectGrades] {
        let cacheKey = "\(s.schoolRef.loginName)-\(s.studentId)-\(year ?? 0)"
        if let cached = gradesCache.get(cacheKey) { return cached }
        // An offline session shows the stored grades.
        if s.bearerToken.isEmpty {
            return DiskCache.load([SubjectGrades].self, key: "grades-\(cacheKey)", owner: s.username) ?? []
        }
        do {
            guard let schoolyearId = try await schoolyearId(year: year, s) else {
                throw AppError(message: Strings.current.errors.noSchoolYear)
            }
            if schoolyearId == -1 { throw AppError.sessionExpired }

            let listURL = "\(base(s))/api/classreg/grade/grading/list?studentId=\(s.studentId)&schoolyearId=\(schoolyearId)"
            let (data, http) = try await get(listURL, s)
            if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
            guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.grades(http.statusCode)) }

            let listJSON = JSON.parse(data)
            var lessons = listJSON.data.lessons.array
            if lessons.isEmpty { lessons = listJSON.data.lesson.array }
            if lessons.isEmpty { return [] }

            var subjects: [SubjectGrades] = []
            try await withThrowingTaskGroup(of: SubjectGrades?.self) { group in
                for lesson in lessons {
                    let lessonId = lesson.id.int ?? 0
                    let subjectName = lesson.subjects.string ?? lesson.subject.string ?? ""
                    let teacherName = lesson.teachers.string ?? lesson.teacher.string ?? ""
                    group.addTask { [self] in
                        try? await gradesForLesson(lessonId: lessonId, subjectName: subjectName, teacherName: teacherName, s)
                    }
                }
                for try await result in group {
                    if let r = result { subjects.append(r) }
                }
            }
            let result = subjects.filter { !$0.subjectName.isEmpty && !$0.grades.isEmpty }
                .sorted { $0.subjectName.localizedCaseInsensitiveCompare($1.subjectName) == .orderedAscending }
            gradesCache.set(cacheKey, result)
            DiskCache.save(result, key: "grades-\(cacheKey)", owner: s.username)   // Offline-Fallback
            return result
        } catch let netErr as URLError {
            // Only a real network failure falls back to the stored copy, never an auth error.
            if let offline = DiskCache.load([SubjectGrades].self, key: "grades-\(cacheKey)", owner: s.username) { return offline }
            throw netErr
        }
    }

    private func gradesForLesson(lessonId: Int, subjectName: String, teacherName: String, _ s: UserSession) async throws -> SubjectGrades? {
        let url = "\(base(s))/api/classreg/grade/grading/lesson?studentId=\(s.studentId)&lessonId=\(lessonId)"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) || http.statusCode != 200 { return nil }
        let json = JSON.parse(data)
        let entries: [GradeEntry] = json.data.grades.array.compactMap { g in
            let markValue = g.mark.markValue.double ?? 0
            let display = g.mark.markDisplayValue.double ?? markValue
            // What can't be a grade would break every sum and chart after this.
            guard markValue > 0, MarkText.isUsable(markValue), MarkText.isUsable(display) else { return nil }
            return GradeEntry(
                id: g.id.int ?? 0,
                text: g.text.string ?? "",
                date: UntisRange.day(g.date.int),
                markName: g.mark.name.string ?? "",
                markValue: markValue,
                markDisplayValue: display,
                examType: g.examType.longname.string ?? g.examType.name.string ?? ""
            )
        }
        let vals = entries.map { $0.markDisplayValue }.filter { $0 > 0 }
        let average = vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
        return SubjectGrades(
            lessonId: lessonId, subjectName: subjectName, teacherName: teacherName,
            grades: entries, average: average,
            positiveCount: vals.filter { $0 >= 6 }.count,
            negativeCount: vals.filter { $0 < 6 }.count
        )
    }

    /// The school year id; -1 when the session ran out, nil when there's none.
    private func schoolyearId(year: Int?, _ s: UserSession) async throws -> Int? {
        func isAuthErr(_ j: JSON) -> Bool {
            let code = j.error.code.int
            return code == -8500 || code == -8501 || code == -8520
        }
        if let year = year {
            let j = try await rpcFull("getSchoolyears", s, id: "sy2")
            if isAuthErr(j) { return -1 }
            for y in j.result.array where (y.startDate.int ?? 0) / 10000 == year {
                if let id = y.id.int { return id }
            }
            return nil
        }
        let cur = try await rpcFull("getCurrentSchoolyear", s, id: "sy")
        if isAuthErr(cur) { return -1 }
        if let id = cur.result.id.int { return id }
        let all = try await rpcFull("getSchoolyears", s, id: "sy2")
        if isAuthErr(all) { return -1 }
        let years = all.result.array
        let now = Int(yyyymmdd(Date())) ?? 0
        if let current = years.first(where: { (($0.startDate.int ?? 0) <= now) && (($0.endDate.int ?? 0) >= now) }) {
            return current.id.int
        }
        return years.sorted { ($0.startDate.int ?? 0) > ($1.startDate.int ?? 0) }.first?.id.int
    }

    private func rpcFull(_ method: String, _ s: UserSession, id: String) async throws -> JSON {
        guard let url = URL(string: "\(base(s))/jsonrpc.do?school=\(s.schoolRef.query)") else {
            throw AppError(message: Strings.current.errors.badAnswer)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cookieHeader(s), forHTTPHeaderField: "Cookie")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": id, "method": method, "params": [:], "jsonrpc": "2.0",
        ])
        let (data, _) = try await session.data(for: req)
        return JSON.parse(data)
    }

    // ── Abwesenheiten ────────────────────────────────────────────────────────

    func absences(startDate: String, endDate: String, _ s: UserSession) async throws -> [AbsenceEntry] {
        if s.bearerToken.isEmpty { return [] }   // kein WebUntis (offline/Backend-only)
        let pageSize = 100
        let baseURL = "\(base(s))/api/classreg/absences/students?studentId=\(s.studentId)&startDate=\(startDate)&endDate=\(endDate)&excuseStatusId=-1&limit=\(pageSize)&pageSize=\(pageSize)"
        var all: [JSON] = []
        var page = 0
        var totalCount: Int? = nil
        while page < 50 {
            let url = page == 0 ? baseURL : "\(baseURL)&page=\(page)"
            let (data, http) = try await get(url, s)
            if isHtmlOrAuthError(data, http) {
                if page == 0 { throw AppError.sessionExpired }
                break
            }
            guard http.statusCode == 200 else {
                if page == 0 { throw AppError(message: Strings.current.errors.absences(http.statusCode)) }
                break
            }
            let parsed = JSON.parse(data)
            let inner = parsed.data.exists ? parsed.data : parsed
            let pageItems = inner.absences.array
            if totalCount == nil { totalCount = inner.count.int ?? inner.totalCount.int ?? inner.totalElements.int }
            if pageItems.isEmpty { break }
            let firstId = pageItems.first?.id.int
            if page > 0, all.contains(where: { $0.id.int == firstId }) { break }
            all.append(contentsOf: pageItems)
            if pageItems.count < pageSize || (totalCount != nil && all.count >= totalCount!) { break }
            page += 1
        }
        return all.map(Self.parseAbsence)
    }

    static func parseAbsence(_ item: JSON) -> AbsenceEntry {
        let startTime = UntisRange.clock(item.startTime.int)
        let endTime = UntisRange.clock(item.endTime.int)
        let rawHours = (item.hours.int ?? item.lessonHours.int).map(UntisRange.amount)
        let hours: Int
        if let rh = rawHours, rh > 0 {
            hours = rh
        } else {
            let s = Fmt.minutes(startTime), e = Fmt.minutes(endTime)
            hours = e > s ? max(1, Int((Double(e - s) / 50).rounded())) : 1
        }
        var teacher = item.teacherName.string ?? item.teacher.string
        if teacher == nil, let fn = item.teacherFirstname.string {
            teacher = "\(fn) \(item.teacherLastname.string ?? "")"
        }
        return AbsenceEntry(
            id: item.id.int ?? 0,
            startDate: UntisRange.day(item.startDate.int),
            endDate: UntisRange.day(item.endDate.int),
            startTime: startTime, endTime: endTime,
            isExcused: item.isExcused.bool ?? false,
            reasonName: item.reasonName.string ?? item.reason.string,
            absenceType: item.absenceType.string,
            hours: hours,
            note: item.text.string ?? item.note.string,
            excuseNote: item.excuseNote.string,
            teacherName: teacher,
            subjectName: item.subject.string ?? item.subjectName.string ?? item.subjectShortName.string
        )
    }

    // ── Nachrichten ────────────────────────────────────────────────────────

    func messages(folder: MessageFolder, _ s: UserSession) async throws -> [MessagePreview] {
        guard s.hasUntis else { return [] }   // POKYH-only account
        return try await storedOrFresh(diskKey("messages", s, folder.rawValue), s) {
            try await fetchMessages(folder: folder, s)
        }
    }

    /// The folder as last read, to show while it's asked again.
    func storedMessages(folder: MessageFolder, _ s: UserSession) async -> [MessagePreview]? {
        guard s.hasUntis else { return nil }
        return await DiskCache.loaded([MessagePreview].self, key: diskKey("messages", s, folder.rawValue), owner: s.username)
    }

    private func fetchMessages(folder: MessageFolder, _ s: UserSession) async throws -> [MessagePreview] {
        let path: String
        switch folder {
        case .inbox: path = "/api/rest/view/v1/messages"
        case .sent: path = "/api/rest/view/v1/messages/sent"
        case .drafts: path = "/api/rest/view/v1/messages/drafts"
        }
        let url = "\(base(s))\(path)?pageSize=100&start=0"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.messages(http.statusCode)) }
        return Self.parseMessages(JSON.parse(data))
    }

    static func parseMessages(_ json: JSON) -> [MessagePreview] {
        let t = Strings.current.messages
        let root = json
        let data = root.data
        var arr = root.incomingMessages.array
        if arr.isEmpty { arr = root.sentMessages.array }
        if arr.isEmpty { arr = root.draftMessages.array }
        if arr.isEmpty { arr = root.messages.array }
        if arr.isEmpty { arr = data.incomingMessages.array }
        if arr.isEmpty { arr = data.sentMessages.array }
        if arr.isEmpty { arr = data.draftMessages.array }
        if arr.isEmpty, root.data.isArray { arr = root.data.array }

        return arr.map { m in
            let sender = m.sender
            let recipientLabel = recipientNames(m).joined(separator: ", ")
            let senderName = sender.displayName.string
                ?? sender.name.string
                ?? m.senderName.string
                ?? (recipientLabel.isEmpty ? t.unknown : t.toNames(recipientLabel))
            let sentDate = m.sentDateTime.string ?? m.sentDate.string ?? m.date.string ?? ""
            let subject = m.subject.string?.trimmingCharacters(in: .whitespaces) ?? ""
            let confirmation = m.requestConfirmation
            return MessagePreview(
                id: m.id.int ?? 0,
                subject: subject.isEmpty ? t.noSubject : subject,
                contentPreview: m.contentPreview.string ?? "",
                senderName: senderName,
                senderId: sender.userId.int ?? 0,
                sentDate: sentDate,
                isRead: messageIsRead(m),
                hasAttachments: m.hasAttachments.bool ?? false,
                needsConfirmation: confirmation.allowSendRequestConfirmation.bool == true
                    && (confirmation.confirmationDate.string ?? "").isEmpty,
                readConfirmed: m.requestConfirmationStatus.confirmedRequestCount.int,
                readTotal: m.requestConfirmationStatus.totalRequestCount.int
            )
        }
    }

    /// WebUntis sends `isMessageRead`; the other names cover older shapes, as a bool, 1 or "true".
    private static func messageIsRead(_ m: JSON) -> Bool {
        let raw = ["isMessageRead", "isRead", "read", "isread", "readFlag", "readStatus"].map { m[$0] }.first { $0.exists }
        guard let raw else { return true }
        if let b = raw.raw as? Bool { return b }
        return raw.int == 1 || raw.string?.lowercased() == "true"
    }

    /// Who a sent message went to: `recipientPersons` / `recipientGroups`, or the older shapes.
    private static func recipientNames(_ m: JSON) -> [String] {
        var seen = Set<String>()
        let nodes = m.recipientPersons.array + m.recipientGroups.array + m.recipients.array + (m.recipient.exists ? [m.recipient] : [])
        return nodes.compactMap { r in
            (r.raw is String ? r.string : nil) ?? r.displayName.string ?? r.name.string ?? r.longName.string ?? r.fullName.string
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Opened messages stay readable offline.
    func messageDetail(id: Int, _ s: UserSession) async throws -> MessageDetail {
        try await storedOrFresh(diskKey("message", s, "\(id)"), s) { try await fetchMessageDetail(id: id, s) }
    }

    private func fetchMessageDetail(id: Int, _ s: UserSession) async throws -> MessageDetail {
        let url = "\(base(s))\(Config.Routes.messageDetail(id))"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.message(http.statusCode)) }
        let t = Strings.current.messages
        let m = JSON.parse(data)
        let sender = m.sender
        let recipients = Self.recipientNames(m).joined(separator: ", ")
        let senderName = sender.displayName.string ?? sender.name.string ?? m.senderName.string
            ?? (recipients.isEmpty ? t.unknown : t.toNames(recipients))
        let subject = m.subject.string?.trimmingCharacters(in: .whitespaces) ?? ""
        return MessageDetail(
            id: m.id.int ?? id,
            subject: subject.isEmpty ? t.noSubject : subject,
            senderName: senderName,
            sentDate: m.sentDateTime.string ?? m.sentDate.string ?? "",
            body: m.body.string ?? m.content.string ?? "",
            attachments: Self.parseAttachments(m)
        )
    }

    /// Attachments in any shape the MessageCenter reports them: an `attachments` array (or one of
    /// its aliases), `storageAttachments` (whose `id` is the storage UUID), or one `blobAttachment`.
    static func parseAttachments(_ node: JSON) -> [MessageAttachment] {
        let fallbackName = Strings.current.messages.attachment
        let keys = ["attachments", "messageFile", "files", "fileAttachments", "attachment", "items", "content", "data"]
        let direct = keys.map { node[$0] }.first { $0.isArray } ?? (node.isArray ? node : JSON(nil))
        func storageId(_ a: JSON) -> String {
            if let id = a.storageId.string { return id }
            // A non-numeric `id` is the storage UUID on instances without `storageId`.
            if let id = a.id.raw as? String, Int(id) == nil { return id }
            return ""
        }
        let list = direct.array.map { a in
            let fileId = (a.id.raw is NSNumber ? a.id.int : nil) ?? a.fileId.int ?? 0
            let storage = storageId(a)
            return MessageAttachment(
                id: storage.isEmpty ? String(fileId) : storage,
                name: a.name.string ?? a.fileName.string ?? a.originalName.string ?? a.src.string ?? fallbackName,
                size: a.size.int ?? a.fileSize.int ?? 0,
                storageId: storage,
                fileId: fileId
            )
        }
        if !list.isEmpty { return list }
        let storage = node.storageAttachments.array.map { a in
            let id = a.id.string ?? ""
            return MessageAttachment(id: id, name: a.name.string ?? fallbackName, size: 0, storageId: id)
        }
        if !storage.isEmpty { return storage }
        let blob = node.blobAttachment
        if blob.id.exists || blob.name.exists {
            let fileId = (blob.id.raw is NSNumber ? blob.id.int : nil) ?? 0
            let sid = storageId(blob)
            return [MessageAttachment(id: sid.isEmpty ? String(fileId) : sid,
                                      name: blob.name.string ?? blob.fileName.string ?? fallbackName,
                                      size: blob.size.int ?? 0, storageId: sid, fileId: fileId)]
        }
        return []
    }

    func markRead(id: Int, _ s: UserSession) async {
        guard !s.sessionId.isEmpty, let url = URL(string: "\(base(s))/api/rest/view/v1/messages/\(id)/markasread") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in headers(s) { req.setValue(v, forHTTPHeaderField: k) }
        _ = try? await session.data(for: req)
    }

    // ── Klassenbuch ──────────────────────────────────────────────────────────

    func classregEvents(year: Int?, _ s: UserSession) async throws -> [ClassregEvent] {
        if s.bearerToken.isEmpty { return [] }   // kein WebUntis (offline/Backend-only)
        let y = year ?? SchoolDates.currentSchoolYear
        let url = "\(base(s))/api/classreg/classregevents?startDate=\(y)0908&endDate=\(y + 1)0612&studentId=\(s.studentId)"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.classreg(http.statusCode)) }
        let json = JSON.parse(data)
        return json.data.rows.array.map { r in
            ClassregEvent(
                id: r.id.int ?? 0,
                subjectName: r.subjectName.string ?? "",
                creatorName: r.creatorName.string ?? "",
                createDate: UntisRange.day(r.createDate.int),
                eventReasonName: r.eventReasonName.string ?? "",
                categoryName: r.categoryName.string ?? "",
                text: r.text.string ?? ""
            )
        }
    }

    // ── Schuljahre / Ferien ──────────────────────────────────────────────────

    /// The school years WebUntis knows for the school, oldest first.
    func schoolYears(_ s: UserSession) async throws -> [SchoolYear] {
        let j = try await rpcFull("getSchoolyears", s, id: "pokyh-years")
        if [-8500, -8501, -8520].contains(j.error.code.int ?? 0) { throw AppError.sessionExpired }
        return j.result.array.compactMap { y in
            guard let id = y.id.int else { return nil }
            return SchoolYear(id: id, name: y.name.string ?? "", startDate: UntisRange.day(y.startDate.int), endDate: UntisRange.day(y.endDate.int))
        }
        .sorted { $0.startDate < $1.startDate }
    }

    /// The school's breaks from a month ago on (getHolidays), overlapping ones merged.
    func holidays(_ s: UserSession) async throws -> [SchoolHoliday] {
        let from = DateFmt.isoString(Calendar.current.date(byAdding: .day, value: -31, to: Date()) ?? Date())
        let j = try await rpcFull("getHolidays", s, id: "holidays")
        return HolidayList.read(j.result.raw, from: from)
    }

    // ── Messages: count, read receipts, deleting ─────────────────────────────

    /// Unread messages in the inbox, for the badges.
    func unreadMessageCount(_ s: UserSession) async throws -> Int {
        try await messages(folder: .inbox, s).filter { !$0.isRead }.count
    }

    /// Marks every id read, each on its own (one failing doesn't stop the rest).
    func markAllRead(ids: [Int], _ s: UserSession) async {
        await withTaskGroup(of: Void.self) { group in
            for id in ids { group.addTask { await self.markRead(id: id, s) } }
        }
    }

    /// Confirms reading a message whose sender asked for it.
    func confirmMessageRead(id: Int, _ s: UserSession) async throws {
        let (_, http) = try await send(base(s) + Config.Routes.messageReadConfirmation(id), method: "POST", s)
        if http.statusCode == 401 { throw AppError.sessionExpired }
        guard (200..<300).contains(http.statusCode) else { throw AppError(message: Strings.current.messages.confirmFailed) }
    }

    /// Who of a sent message's recipients confirmed reading.
    func messageReadStatus(id: Int, _ s: UserSession) async throws -> [ReadStatusRecipient] {
        let (data, http) = try await get(base(s) + Config.Routes.messageReadStatus(id), s, timeout: 12)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: Strings.current.messages.readStatusFailed) }
        let root = JSON.parse(data)
        return (root.isArray ? root.array : root.data.array).map { item in
            let people = item.confirmationStates.array.map { st in
                (name: st.userDisplayName.string ?? "", confirmedAt: st.date.string.flatMap { $0.isEmpty ? nil : $0 })
            }
            return ReadStatusRecipient(name: item.recipientDisplayName.string ?? "",
                                       className: item.recipientClassName.string ?? "",
                                       confirmedAt: people.compactMap(\.confirmedAt).first, people: people)
        }
    }

    /// Takes a sent message back: the recipients no longer see it.
    func revokeMessage(id: Int, _ s: UserSession) async throws {
        let (_, http) = try await send(base(s) + Config.Routes.messageRevoke(id), method: "POST", s)
        if http.statusCode == 401 { throw AppError.sessionExpired }
        guard (200..<300).contains(http.statusCode) else { throw AppError(message: Strings.current.messages.revokeFailed) }
    }

    /// Deletes messages or drafts: all in one call, else one by one. Returns the ids that went.
    @discardableResult
    func deleteMessages(ids: [Int], _ s: UserSession) async throws -> [Int] {
        let root = base(s) + Config.Routes.messages
        let (_, all) = try await send(root + "?ids=" + ids.map(String.init).joined(separator: ","), method: "DELETE", s)
        if all.statusCode == 401 { throw AppError.sessionExpired }
        if (200..<300).contains(all.statusCode) { return ids }
        var gone: [Int] = []
        for id in ids {
            if let (_, http) = try? await send("\(root)/\(id)", method: "DELETE", s), (200..<300).contains(http.statusCode) {
                gone.append(id)
            }
        }
        return gone
    }

    /// A draft to go on with: subject, text and recipients.
    func draft(id: Int, _ s: UserSession) async throws -> MessageDraft {
        let (data, http) = try await get("\(base(s))\(Config.Routes.messagesDrafts)/\(id)", s, timeout: 12)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.message(http.statusCode)) }
        let root = JSON.parse(data)
        let d = root.data.exists ? root.data : root
        let raw = d.content.string ?? d.contentHtml.string ?? d.body.string ?? ""
        let isHtml = raw.range(of: #"<[a-z][\s\S]*>"#, options: [.regularExpression, .caseInsensitive]) != nil
        let people = d.recipientPersons.array.isEmpty ? d.recipients.array : d.recipientPersons.array
        return MessageDraft(
            id: d.id.int ?? id,
            subject: d.subject.string ?? "",
            content: isHtml ? Self.plainText(raw) : raw,
            recipients: people.compactMap { r in
                guard let rid = r.id.int ?? r.userId.int, rid > 0 else { return nil }
                return MessageRecipient(id: rid, type: (r.type.string ?? "TEACHER").uppercased(), name: r.displayName.string ?? r.name.string ?? "")
            }
        )
    }

    // ── Messages: attachments ────────────────────────────────────────────────

    /// Asks again for a message's attachments when the detail came without them. Empty means none.
    func messageAttachments(id: Int, _ s: UserSession) async -> [MessageAttachment] {
        for path in [Config.Routes.messageAttachments(id), Config.Routes.messageDetail(id)] {
            guard let (data, http) = try? await get(base(s) + path, s), http.statusCode == 200,
                  data.first != UInt8(ascii: "<") else { continue }
            let found = Self.parseAttachments(JSON.parse(data))
            if !found.isEmpty { return found }
        }
        return []
    }

    /// Downloads one attachment: the storage's signed URL first, then the direct candidates.
    /// nil when every way only answered with an error page.
    func downloadAttachment(messageId: Int, attachment: MessageAttachment, _ s: UserSession) async -> DownloadedAttachment? {
        if let file = await storageDownload(attachment, s) { return file }
        for path in Config.Routes.attachmentCandidates(messageId: messageId, storageId: attachment.storageId, fileId: attachment.fileId) {
            if let file = await fetchFile(base(s) + path, name: attachment.name, session: s) { return file }
        }
        return nil
    }

    private func storageDownload(_ attachment: MessageAttachment, _ s: UserSession) async -> DownloadedAttachment? {
        guard !attachment.storageId.isEmpty,
              let (data, http) = try? await get(base(s) + Config.Routes.attachmentStorageURL(attachment.storageId), s),
              http.statusCode == 200, data.first != UInt8(ascii: "<") else { return nil }
        let info = JSON.parse(data)
        guard let url = info.downloadUrl.string else { return nil }
        // The storage's own headers, as {key|value} (some say {name|value}); Host comes from the URL.
        var extra: [String: String] = [:]
        for h in info.additionalHeaders.array {
            guard let key = h.key.string ?? h.name.string, let value = h.value.string,
                  key.caseInsensitiveCompare("host") != .orderedSame else { continue }
            extra[key] = value
        }
        return await fetchFile(url, name: attachment.name, headers: extra)
    }

    /// A GET that has to bring a file back: HTML or JSON is an error page, not content.
    private func fetchFile(_ urlString: String, name: String, session s: UserSession? = nil, headers extra: [String: String] = [:]) async -> DownloadedAttachment? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 60)
        if let s { for (k, v) in headers(s) { req.setValue(v, forHTTPHeaderField: k) } }
        for (k, v) in extra { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req), let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if type.contains("text/html") || type.contains("application/json") { return nil }
        let mime = type.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return DownloadedAttachment(name: name, mimeType: mime.isEmpty ? "application/octet-stream" : mime, data: data)
    }

    // ── Nachrichten schreiben (MessageCenter) ────────────────────────────────

    /// The people this account may write to, grouped into class teachers / teachers / others.
    func messageRecipients(_ s: UserSession) async throws -> [MessageRecipient] {
        let (data, http) = try await get(base(s) + Config.Routes.messageRecipients, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { return [] }
        var seen = Set<String>()
        return JSON.parse(data).array.flatMap { group -> [MessageRecipient] in
            let type = (group.type.string ?? "TEACHERS").uppercased()
            return group.persons.array.compactMap { person in
                guard let id = person.userId.int ?? person.id.int else { return nil }
                let name = (person.displayName.string ?? person.name.string ?? "").trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, seen.insert("\(type):\(id)").inserted else { return nil }
                let tags = person.tags.array.compactMap(\.string).filter { !$0.isEmpty }
                return MessageRecipient(id: id, type: type, name: name,
                                        role: tags.isEmpty ? nil : tags.joined(separator: ", "),
                                        isClassTeacher: type == "CLASS_TEACHERS")
            }
        }
    }

    /// Sends a message, or saves it as a draft (`asDraft`). `draftId`: the draft it was written in,
    /// saved in its place or sent from it.
    /// WebUntis puts the picture in different places per endpoint and account type, so this walks
    /// the same list as the web. For a guardian the child comes first: that's whose data is shown.
    func extractImageUrl(_ appData: JSON, isParent: Bool) -> String? {
        let roots = [appData.data.user, appData.user, appData.data, appData]
        var candidates: [String?] = []
        if isParent { candidates += roots.map { $0.students.array.first?.imageUrl.string } }
        for root in roots { candidates += [root.person.imageUrl.string, root.imageUrl.string] }
        return candidates.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    func fetchProfileImageUrl(_ s: UserSession) async -> String? {
        guard let appData = try? await fetchAppData(s) else { return nil }
        return extractImageUrl(appData, isParent: s.isParent)
    }

    func sendMessage(subject: String, content: String, recipients: [MessageRecipient], attachments: [OutgoingAttachment] = [],
                     asDraft: Bool = false, draftId: Int? = nil, _ s: UserSession) async throws {
        let t = Strings.current.errors
        let token = await freshMessageToken(s)
        let yearId = await currentSchoolYearId(s)
        let permissions = await messagePermissions(s, token: token, schoolYearId: yearId)
        try check(attachments, permissions)

        var meta: [String: Any] = [
            "subject": subject,
            "content": content,
            "recipientOption": permissions.recipientOption,
            "recipientPersons": recipients.map { ["id": $0.id] },
            "recipientGroups": [Any](),
        ]
        if let draftId, !asDraft { meta["draftMessageId"] = draftId }
        if draftId != nil, asDraft { meta["attachmentIdsToDelete"] = [Any]() }
        let paths: [String]
        if asDraft {
            paths = draftId.map { ["\(Config.Routes.messagesV2Drafts)/\($0)", "\(Config.Routes.messagesDrafts)/\($0)"] }
                ?? [Config.Routes.messagesV2Drafts, Config.Routes.messagesDrafts]
        } else {
            paths = [Config.Routes.messagesV2, Config.Routes.messages]
        }
        let failure = asDraft ? t.draftFailed : t.sendFailed
        for path in paths {
            // A saved draft is updated in place, as the web does.
            let (data, http) = try await sendMultipart(base(s) + path, method: asDraft && draftId != nil ? "PUT" : "POST",
                                                       meta: meta, attachments: attachments, token: token, schoolYearId: yearId, s)
            // 404: this instance doesn't have the path, try the older one.
            if http.statusCode == 404 { continue }
            if http.statusCode == 401 || data.first == UInt8(ascii: "<") { throw AppError.sessionExpired }
            if (200..<300).contains(http.statusCode) { return }
            throw AppError(message: Self.serverMessage(data) ?? failure)
        }
        throw AppError(message: failure)
    }

    /// The reply form: subject and recipient prefilled. Fails when the sender forbade replies.
    func replyForm(messageId: Int, _ s: UserSession) async throws -> ReplyForm {
        let token = await freshMessageToken(s)
        let yearId = await currentSchoolYearId(s)
        guard let url = URL(string: base(s) + Config.Routes.messageReplyForm(messageId)) else { throw AppError(message: Strings.current.errors.badAnswer) }
        var req = URLRequest(url: url)
        for (k, v) in messageWriteHeaders(s, token: token, schoolYearId: yearId) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || data.first == UInt8(ascii: "<") { throw AppError.sessionExpired }
        let json = JSON.parse(data)
        guard (200..<300).contains(code) else { throw AppError(message: Self.untisError(json) ?? Strings.current.messages.noReply) }
        return ReplyForm(subject: json.subject.string ?? "", recipientName: json.recipient.displayName.string ?? "")
    }

    /// Sends a reply, the text as the HTML paragraphs WebUntis stores.
    func sendReply(messageId: Int, subject: String, content: String, attachments: [OutgoingAttachment] = [], _ s: UserSession) async throws {
        let token = await freshMessageToken(s)
        let yearId = await currentSchoolYearId(s)
        try check(attachments, await messagePermissions(s, token: token, schoolYearId: yearId))
        let meta: [String: Any] = [
            "subject": String(subject.prefix(255)),
            "content": Self.plainTextToHtml(String(content.prefix(10_000))),
            "oneDriveAttachments": [Any](),
        ]
        let (data, http) = try await sendMultipart(base(s) + Config.Routes.messageReply(messageId), method: "POST",
                                                   meta: meta, attachments: attachments, token: token, schoolYearId: yearId, s)
        if http.statusCode == 401 || data.first == UInt8(ascii: "<") { throw AppError.sessionExpired }
        if (200..<300).contains(http.statusCode) { return }
        throw AppError(message: Self.serverMessage(data) ?? Strings.current.errors.replyFailed)
    }

    private struct MessagePermissions {
        var recipientOption = "TEACHER"
        var maxFileSize = 7_000_000
        var maxFileCount = 5
    }

    private func check(_ attachments: [OutgoingAttachment], _ p: MessagePermissions) throws {
        let t = Strings.current.errors
        if attachments.count > p.maxFileCount { throw AppError(message: t.maxFiles(p.maxFileCount)) }
        if let big = attachments.first(where: { $0.data.count > p.maxFileSize }) {
            throw AppError(message: t.fileTooBig(big.name, p.maxFileSize / (1024 * 1024)))
        }
    }

    /// The MessageCenter's rules for this account: recipient option and attachment limits.
    private func messagePermissions(_ s: UserSession, token: String, schoolYearId: Int?) async -> MessagePermissions {
        let fallback = MessagePermissions()
        guard let url = URL(string: base(s) + Config.Routes.messagePermissions) else { return fallback }
        var req = URLRequest(url: url)
        for (k, v) in messageWriteHeaders(s, token: token, schoolYearId: schoolYearId) { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              data.first != UInt8(ascii: "<") else { return fallback }
        let json = JSON.parse(data)
        return MessagePermissions(
            recipientOption: json.recipientOptions.array.first?.string ?? fallback.recipientOption,
            maxFileSize: json.maxFileSize.double.map { Int(saturating: $0) } ?? fallback.maxFileSize,
            maxFileCount: json.maxFileCount.int ?? fallback.maxFileCount
        )
    }

    /// MessageCenter writes run as their own service: they need the Tenant-Id (a claim in the
    /// bearer token) and the school year header the browser sends. No Content-Type here, the
    /// multipart boundary sets its own.
    private func messageWriteHeaders(_ s: UserSession, token: String, schoolYearId: Int?) -> [String: String] {
        var h = ["Cookie": cookieHeader(s), "Accept": "application/json"]
        if !token.isEmpty { h["Authorization"] = "Bearer \(token)" }
        if let tenant = Self.tenantId(token, s.bearerToken) { h["Tenant-Id"] = tenant }
        if let schoolYearId { h["X-Webuntis-Api-School-Year-Id"] = String(schoolYearId) }
        return h
    }

    private func sendMultipart(_ urlString: String, method: String, meta: [String: Any], attachments: [OutgoingAttachment],
                               token: String, schoolYearId: Int?, _ s: UserSession) async throws -> (Data, HTTPURLResponse) {
        try requireSessionToWrite(s)
        guard let url = URL(string: urlString) else { throw AppError(message: Strings.current.errors.badAnswer) }
        let boundary = "pokyh-\(UUID().uuidString)"
        var body = Data()
        func part(_ header: String, _ content: Data) {
            body.append(Data("--\(boundary)\r\n\(header)\r\n\r\n".utf8))
            body.append(content)
            body.append(Data("\r\n".utf8))
        }
        part("Content-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json; charset=utf-8",
             try JSONSerialization.data(withJSONObject: meta))
        for file in attachments {
            let name = file.name.replacingOccurrences(of: "\"", with: "'")
            part("Content-Disposition: form-data; name=\"attachments\"; filename=\"\(name)\"\r\nContent-Type: \(file.mimeType)", file.data)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = method
        for (k, v) in messageWriteHeaders(s, token: token, schoolYearId: schoolYearId) { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AppError(message: Strings.current.errors.untisDown) }
        return (data, http)
    }

    /// WebUntis' tokens are short-lived and the web refreshes before every write; the one from
    /// sign-in is the fallback.
    private func freshMessageToken(_ s: UserSession) async -> String {
        guard let (data, http) = try? await get(base(s) + Config.Routes.token, s), http.statusCode == 200,
              data.first != UInt8(ascii: "<") else { return s.bearerToken }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("{") {
            let j = JSON.parse(data)
            return j.accessToken.string ?? j.token.string ?? j.access_token.string ?? j.jwt.string ?? s.bearerToken
        }
        let token = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return token.isEmpty ? s.bearerToken : token
    }

    private func currentSchoolYearId(_ s: UserSession) async -> Int? {
        (try? await rpcFull("getCurrentSchoolyear", s, id: "sy"))?.result.id.int
    }

    /// The `tenant_id` claim of the first token that has one. Only read, never verified.
    private static func tenantId(_ tokens: String...) -> String? {
        for token in tokens {
            let parts = token.split(separator: ".")
            guard parts.count > 1 else { continue }
            var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while payload.count % 4 != 0 { payload += "=" }
            guard let data = Data(base64Encoded: payload) else { continue }
            let claim = JSON.parse(data).tenant_id
            if let value = claim.string, !value.isEmpty { return value }
        }
        return nil
    }

    /// WebUntis' own error text, so a rule like "nur an eine einzige Lehrkraft" reaches the person.
    private static func serverMessage(_ data: Data) -> String? {
        let json = JSON.parse(data)
        if let m = json.errorMessage.string?.trimmingCharacters(in: .whitespaces), !m.isEmpty { return m }
        let joined = json.validationErrors.array.compactMap(\.errorMessage.string).filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    // ── Reporting and excusing absences ──────────────────────────────────────

    /// Just the reasons, for when the report dialog's meta can't be read.
    func absenceReasons(_ s: UserSession) async throws -> [AbsenceReason] {
        let d = DateFmt.num(Date())
        let url = "\(base(s))\(Config.Routes.absences)?studentId=\(s.studentId)&startDate=\(d)&endDate=\(d)&excuseStatusId=-1"
        let (data, http) = try await get(url, s, timeout: 12)
        guard http.statusCode == 200, data.first != UInt8(ascii: "<") else { return [] }
        let root = JSON.parse(data)
        return Self.reasons((root.data.exists ? root.data : root).absenceReasons.array)
    }

    /// Reasons and the preset range of WebUntis' own report dialog.
    func absenceMeta(_ s: UserSession) async throws -> AbsenceMeta {
        let (data, http) = try await get(base(s) + Config.Routes.absenceMeta, s, timeout: 12)
        if http.statusCode == 401 || data.first == UInt8(ascii: "<") { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.reasons) }
        let root = JSON.parse(data)
        let d = root.data.exists ? root.data : root
        let list = d.absenceReasons.array.isEmpty ? d.reasons.array : d.absenceReasons.array
        return AbsenceMeta(
            reasons: Self.reasons(list),
            defaultReasonId: d.defaultAbsenceReason.id.int,
            defaultDate: d.defaultDate.int.map { UntisRange.day($0) },
            defaultStartTime: d.defaultStartTime.int.map(Self.hhmm),
            defaultEndTime: d.defaultEndTime.int.map(Self.hhmm)
        )
    }

    private static func reasons(_ list: [JSON]) -> [AbsenceReason] {
        list.compactMap { r in
            guard let id = r.id.int else { return nil }
            let name = (r.name.string ?? r.longName.string ?? r.displayName.string ?? "").trimmingCharacters(in: .whitespaces)
            return name.isEmpty || name == "---" ? nil : AbsenceReason(id: id, name: name)
        }
    }

    /// Whether WebUntis lets this account report (and so excuse) absences itself: its own
    /// `showCreateAbsence` flag, else a write right on absences in the app data.
    func canReportAbsence(_ s: UserSession) async -> Bool {
        guard !s.bearerToken.isEmpty else { return false }
        let d = DateFmt.num(Date())
        let url = "\(base(s))\(Config.Routes.absences)?studentId=\(s.studentId)&startDate=\(d)&endDate=\(d)&excuseStatusId=-1"
        if let (data, http) = try? await get(url, s, timeout: 12), http.statusCode == 200, data.first != UInt8(ascii: "<"),
           let flag = JSON.parse(data).data.showCreateAbsence.bool {
            return flag
        }
        guard let app = (try? await fetchAppData(s)).flatMap({ $0 }), JSONSerialization.isValidJSONObject(app.raw as Any),
              let raw = try? JSONSerialization.data(withJSONObject: app.raw as Any) else { return false }
        let text = String(decoding: raw, as: UTF8.self).uppercased()
        return text.range(of: Self.absenceWriteRight, options: .regularExpression) != nil
    }

    /// "Abwesenheit melden" as the official client does it. Dates YYYYMMDD, times HHMM.
    func reportAbsence(startDate: Int, startTime: Int, endDate: Int, endTime: Int, reasonId: Int, text: String, _ s: UserSession) async throws {
        let t = Strings.current.errors
        if endDate * 10_000 + endTime <= startDate * 10_000 + startTime { throw AppError(message: t.endAfterStart) }
        guard await canReportAbsence(s) else { throw AppError(message: t.reportNotAllowed) }
        let reply = try await classicWrite(s, Config.Routes.absenceReport, method: "POST", body: [
            "studentId": s.studentId, "startDate": startDate, "startTime": startTime,
            "endDate": endDate, "endTime": endTime, "text": String(text.prefix(1000)), "reasonId": reasonId,
        ])
        try checkAbsenceWrite(reply, failure: t.reportFailed)
    }

    /// A reason and a note on existing absences, what "entschuldigen" is for a student; whether it
    /// counts as excused is the school's call. Only where WebUntis says the absence may be edited.
    func excuseAbsences(ids: [Int], reasonId: Int, text: String, _ s: UserSession) async throws {
        let t = Strings.current.errors
        var failure: String?
        for id in ids.prefix(20) {
            let (data, http) = try await get("\(base(s))\(Config.Routes.absenceSingle)?absenceId=\(id)", s, timeout: 12)
            if http.statusCode == 401 || data.first == UInt8(ascii: "<") { throw AppError.sessionExpired }
            let absence = JSON.parse(data).data.absence
            guard http.statusCode == 200, absence.exists else { failure = failure ?? t.absenceNotFound; continue }
            guard absence.canEdit.bool == true else { failure = failure ?? t.absenceLocked; continue }
            var body: [String: Any] = ["absenceId": id, "text": String(text.prefix(1000)), "reasonId": reasonId]
            for key in ["startDate", "startTime", "endDate", "endTime"] {
                if let v = absence[key].int { body[key] = v }
            }
            let reply = try await classicWrite(s, Config.Routes.absenceEdit, method: "POST", body: body)
            do {
                try checkAbsenceWrite(reply, failure: t.absenceSaveFailed)
            } catch let e as AppError {
                if e.isSessionExpired { throw e }
                failure = failure ?? e.message
            }
        }
        if let failure { throw AppError(message: failure) }
    }

    /// The class teacher an excuse goes to, among the class teachers the account may write to:
    /// never the deputy, whom WebUntis lists beside them. Nil when it can't be told.
    func mainClassTeacher(among classTeachers: [MessageRecipient], _ s: UserSession) async -> MessageRecipient? {
        let start = SchoolDates.mondayISO(of: Date())
        let monday = DateFmt.iso.date(from: start) ?? Date()
        let end = DateFmt.isoString(Calendar.current.date(byAdding: .day, value: 5, to: monday) ?? monday)
        let url = "\(base(s))\(TimetableRoutes.filter)?resourceType=CLASS&timetableType=STANDARD&start=\(start)&end=\(end)"
        var teachers: ClassTeachers?
        if let reply = try? await get(url, s, timeout: 12), reply.1.statusCode == 200 {
            teachers = ClassTeacherPick.read(JSON.parse(reply.0).raw)
        }
        return ClassTeacherPick.pick(classTeachers, name: \.name, teachers: teachers)
    }

    /// "Entschuldigen" for absences that are over: WebUntis refuses to add a reason to those, so the
    /// excuse goes to the class teacher as one message, never to the deputy. Without the right to
    /// write to teachers, it is saved on the absence.
    func excuseByMessage(absences: [AbsenceEntry], reason: AbsenceReason, note: String, _ s: UserSession) async throws -> ExcuseResult {
        let strings = Strings.current
        let t = strings.absences
        guard await canReportAbsence(s) else { throw AppError(message: t.exNotAllowed) }
        let open = absences.filter { !$0.isExcused }
        guard !open.isEmpty else { throw AppError(message: t.exAlready) }

        let (data, http) = try await get(base(s) + Config.Routes.messageRecipients, s, timeout: 12)
        if http.statusCode == 401 || data.first == UInt8(ascii: "<") { throw AppError.sessionExpired }
        if http.statusCode == 403 {
            do {
                try await excuseAbsences(ids: open.map(\.id), reasonId: reason.id, text: note, s)
            } catch let e as AppError where e.isSessionExpired {
                throw e
            } catch {
                throw AppError(message: t.exForbidden)
            }
            return ExcuseResult(viaMessage: false, sentTo: [], failed: [], excuse: nil)
        }
        guard http.statusCode == 200 else { throw AppError(message: t.exSendFailed) }
        // One entry per person: a class teacher is listed under TEACHERS too.
        var people: [(id: Int, name: String, type: String)] = []
        for group in JSON.parse(data).array {
            let type = (group.type.string ?? "").uppercased()
            for p in group.persons.array {
                guard let id = p.userId.int ?? p.id.int else { continue }
                let name = (p.displayName.string ?? p.name.string ?? "").trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { people.append((id, name, type)) }
            }
        }
        let classTeacherIds = Set(people.filter { $0.type == "CLASS_TEACHERS" }.map(\.id))
        var seen = Set<Int>()
        let teachers = people.filter { classTeacherIds.contains($0.id) && seen.insert($0.id).inserted }
            .map { MessageRecipient(id: $0.id, type: "CLASS_TEACHERS", name: $0.name, isClassTeacher: true) }
        guard !teachers.isEmpty else { throw AppError(message: t.exNoTeacher) }
        guard let teacher = await mainClassTeacher(among: teachers, s) else { throw AppError(message: t.exTeacherUnclear) }

        var childName: String?
        if s.isParent, let app = (try? await fetchAppData(s)).flatMap({ $0 }) {
            childName = app.data.user.students.array.first?.displayName.string
        }
        let (subject, text) = ExcuseMessage.compose(open, lang: strings.lang, reasonName: reason.name, note: note,
                                                    childName: childName, signature: s.isParent ? nil : s.personName)
        let html = Self.plainTextToHtml(text)
        do {
            try await sendMessage(subject: subject, content: html, recipients: [teacher], s)
        } catch let e as AppError where e.isSessionExpired {
            throw e
        } catch {
            throw AppError(message: t.exSendFailed)
        }
        let sentTo = [teacher.name]
        let span = ExcuseMessage.span(of: open)
        return ExcuseResult(viaMessage: true, sentTo: sentTo, failed: [],
                            excuse: SentExcuse(start: span.start, end: span.end, sentAt: ISO8601DateFormatter().string(from: .now),
                                               recipients: sentTo, messageId: nil))
    }

    /// The excuses sent so far, found again in "Gesendet" by their subject. Read-only.
    func sentExcuses(_ s: UserSession) async throws -> [SentExcuse] {
        guard !s.bearerToken.isEmpty else { return [] }
        let (data, http) = try await get("\(base(s))\(Config.Routes.messagesSent)?pageSize=100&start=0", s, timeout: 12)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { return [] }
        let root = JSON.parse(data)
        var list = root.sentMessages.array
        if list.isEmpty { list = root.data.sentMessages.array }
        if list.isEmpty { list = root.messages.array }
        var order: [String] = []
        var bySpan: [String: SentExcuse] = [:]
        for m in list {
            guard let span = ExcuseMessage.parseSubject(m.subject.string) else { continue }
            let key = "\(span.start)-\(span.end)"
            let sentAt = m.sentDateTime.string ?? m.sentDate.string ?? m.date.string ?? ""
            let id = m.id.int.flatMap { $0 > 0 ? $0 : nil }
            let names = Self.recipientNames(m)
            if var old = bySpan[key] {
                let newer = sentAt > old.sentAt
                if newer { old.sentAt = sentAt; if let id { old.messageId = id } }
                for name in names where !old.recipients.contains(name) { old.recipients.append(name) }
                bySpan[key] = old
            } else {
                order.append(key)
                bySpan[key] = SentExcuse(start: span.start, end: span.end, sentAt: sentAt, recipients: names, messageId: id)
            }
        }
        return order.compactMap { bySpan[$0] }
    }

    /// The excuse letter WebUntis prints for the given absences, as a PDF. Read-only.
    func excuseLetter(startDate: Int, endDate: Int, absenceIds: [Int], _ s: UserSession) async throws -> DownloadedAttachment {
        let t = Strings.current
        var params = "name=Excuse&format=pdf&rpt_sd=\(startDate)&rpt_ed=\(endDate)&excuseStatusId=1&withLateness=true&withAbsences=true&excuseGroup=1"
        for id in absenceIds.prefix(100) { params += "&id=\(id)" }
        let (data, http) = try await get("\(base(s))\(Config.Routes.reports)?\(params)", s, timeout: 20)
        if http.statusCode == 401 || data.first == UInt8(ascii: "<") { throw AppError.sessionExpired }
        let d = JSON.parse(data).data
        guard http.statusCode == 200, d.exists else { throw AppError(message: t.errors.letterFailed) }
        guard d.finished.bool == true else { throw AppError(message: t.errors.letterBusy) }
        let msgId = (d.messageId.string ?? "").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let url = "\(base(s))\(Config.Routes.reports)?msgId=\(msgId)&\(d.reportParams.string ?? "")"
        // The school year starts in September.
        let year = startDate / 10000 - ((startDate / 100) % 100 >= 9 ? 0 : 1)
        let name = "\(t.absences.letter) \(year)-\(String(format: "%02d", (year + 1) % 100)).pdf"
        guard let file = await fetchFile(url, name: name, session: s) else { throw AppError(message: t.errors.letterLoadFailed) }
        return file
    }

    /// Saved only when WebUntis reports neither errors nor conflicts, the official client's rule.
    private func checkAbsenceWrite(_ reply: UntisReply, failure: String) throws {
        if reply.expired { throw AppError.sessionExpired }
        let json = reply.json
        if !json.errors.array.isEmpty || !reply.ok { throw AppError(message: Self.untisError(json) ?? failure) }
        let conflicts = json.data.conflicts.array
        if !conflicts.isEmpty {
            let details = conflicts.compactMap { c in
                (c.raw is String ? c.string : nil) ?? ["text", "message", "title", "description", "name"].lazy.compactMap { c[$0].string }.first
            }.filter { !$0.isEmpty }.prefix(3)
            throw AppError(message: ([Strings.current.errors.absenceExists] + details).joined(separator: " "))
        }
    }

    // ── Password ─────────────────────────────────────────────────────────────

    /// Changes the WebUntis password the way the profile page does; WebUntis checks its rules.
    func changePassword(old: String, new: String, _ s: UserSession) async throws {
        let t = Strings.current.errors
        if old.isEmpty || new.isEmpty { throw AppError(message: t.bothPasswords) }
        if old.count > 200 || new.count > 200 { throw AppError(message: t.tooLong) }
        if old == new { throw AppError(message: t.samePassword) }
        let reply = try await classicWrite(s, Config.Routes.profilePassword, method: "POST", body: ["oldPassword": old, "newPassword": new])
        if reply.expired { throw AppError.sessionExpired }
        if reply.ok, reply.json.errors.array.isEmpty { return }
        throw AppError(message: Self.untisError(reply.json) ?? t.passwordFailed)
    }

    // ── The account's own settings ───────────────────────────────────────────

    /// As the web's settings read it. Only the first answer has to come; without the others the
    /// account shows without two-factor or a language choice.
    func untisAccount(_ s: UserSession) async throws -> UntisAccount {
        async let general = get(base(s) + Config.Routes.profileGeneral, s, timeout: 12)
        async let access = try? get(base(s) + Config.Routes.profileAccess, s, timeout: 12)
        async let languages = try? get(base(s) + Config.Routes.profileLanguages, s, timeout: 12)
        let (data, http) = try await general
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        let extras = await (access: access?.0, languages: languages?.0)
        guard let account = UntisAccount(general: data, access: extras.access, languages: extras.languages) else {
            throw AppError(message: Strings.current.errors.badAnswer)
        }
        return account
    }

    /// Changes some of the settings. WebUntis takes the whole set, so it's read first.
    func saveUntisAccount(_ s: UserSession, email: String? = nil, forwardToEmail: Bool? = nil, languageCode: String? = nil) async throws {
        let failed = Strings.current.settings.saveError
        let (data, http) = try await get(base(s) + Config.Routes.profileGeneral, s, timeout: 12)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard let body = UntisAccount.saveBody(general: data, email: email, forwardToEmail: forwardToEmail, languageCode: languageCode) else {
            throw AppError(message: failed)
        }
        let reply = try await classicWrite(s, Config.Routes.profileGeneral, method: "POST", body: body)
        if reply.expired { throw AppError.sessionExpired }
        if reply.ok, reply.json.errors.array.isEmpty { return }
        throw AppError(message: Self.untisError(reply.json) ?? failed)
    }

    /// A new secret for the authenticator app; nothing is on until the first code came back.
    func startTwoFactorSetup(_ s: UserSession) async throws -> TwoFactorSetup {
        let reply = try await classicWrite(s, Config.Routes.profileTotpCreate, method: "POST", body: [:])
        if reply.expired { throw AppError.sessionExpired }
        guard reply.ok, let setup = TwoFactorSetup(created: reply.data) else {
            throw AppError(message: Self.untisError(reply.json) ?? Strings.current.errors.badAnswer)
        }
        return setup
    }

    /// Turns it on with the app's current code.
    func enableTwoFactor(_ s: UserSession, secret: String, code: String) async throws {
        let wrong = Strings.current.login.codeWrong
        guard let token = Int(TwoFactorCode.digits(code)) else { throw AppError(message: wrong) }
        let reply = try await classicWrite(s, Config.Routes.profileTotp, method: "POST",
                                           body: ["key": secret, "token": token, "algorithm": "STANDARD"])
        if reply.expired { throw AppError.sessionExpired }
        guard reply.ok, reply.json.errors.array.isEmpty, !reply.json.data.totpCredentials.dictionary.isEmpty else {
            throw AppError(message: wrong)
        }
    }

    func disableTwoFactor(_ s: UserSession) async throws {
        let reply = try await classicWrite(s, Config.Routes.profileTotp, method: "DELETE", body: [:])
        if reply.expired { throw AppError.sessionExpired }
        if reply.ok, reply.json.errors.array.isEmpty { return }
        throw AppError(message: Self.untisError(reply.json) ?? Strings.current.settings.saveError)
    }

    /// "Passwort vergessen": WebUntis' own reset request, which e-mails a link to the address the
    /// account has stored. POKYH never sees a password. Needs the login page's anonymous session.
    func requestPasswordReset(username: String, email: String, school: School) async throws {
        let t = Strings.current.errors
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if user.isEmpty || mail.isEmpty { throw AppError(message: t.userAndMail) }
        if user.count > 100 || mail.count > 200 || mail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil {
            throw AppError(message: t.validMail)
        }
        guard let pageURL = URL(string: "\(school.baseString)/?school=\(school.query)"),
              let resetURL = URL(string: school.baseString + Config.Routes.passwordReset) else { throw AppError(message: t.untisDown) }
        var page = URLRequest(url: pageURL)
        page.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (html, pageResp) = try? await session.data(for: page), let pageHTTP = pageResp as? HTTPURLResponse else {
            throw AppError(message: t.untisDown)
        }
        let config = Self.pageConfig(from: html)
        guard let sessionId = Self.sessionId(pageHTTP), let csrf = config.csrf else { throw AppError(message: t.untisDown) }

        var req = URLRequest(url: resetURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(cookieHeader(sessionId, school), forHTTPHeaderField: "Cookie")
        req.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN")
        if let tenant = config.tenant { req.setValue(tenant, forHTTPHeaderField: "Tenant-Id") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": user, "email": mail])
        guard let (data, resp) = try? await session.data(for: req) else { throw AppError(message: t.untisDown) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let isJSON = text.isEmpty || text.hasPrefix("{")
        let errorCode = isJSON ? JSON.parse(data).errors[0].code.string : nil
        if (200..<300).contains(code), isJSON, errorCode == nil { return }
        switch errorCode {
        case "INVALID_USER_DATA": throw AppError(message: t.resetNoMatch)
        case "SEND_EMAIL_FAILURE": throw AppError(message: t.resetMailFailed)
        case "PW_RESET_NOT_ALLOWED": throw AppError(message: t.resetNotAllowed)
        case "INTERNAL_ERROR": throw AppError(message: t.resetInternal)
        default: throw AppError(message: t.resetFailed)
        }
    }

    // ── Classic writes (CSRF) ────────────────────────────────────────────────

    /// CSRF token and tenant of one WebUntis session, from the page WebUntis renders for it.
    private struct PageConfig {
        var csrf: String?
        var tenant: String?
    }

    private var pageConfigs: [String: PageConfig] = [:]

    private static func pageConfig(from html: Data) -> PageConfig {
        let text = String(decoding: html, as: UTF8.self)
        return PageConfig(csrf: match(#""csrfToken"\s*:\s*"([^"]+)""#, in: text),
                          tenant: match(#""tenantId"\s*:\s*"?([0-9A-Za-z-]+)"?"#, in: text))
    }

    /// The session's CSRF token, which the official client sends on every classic write.
    private func pageConfig(_ s: UserSession, force: Bool = false) async -> PageConfig {
        if !force, let cached = pageConfigs[s.sessionId] { return cached }
        guard let url = URL(string: "\(base(s))/?school=\(s.schoolRef.query)") else { return PageConfig() }
        var req = URLRequest(url: url)
        req.setValue(cookieHeader(s), forHTTPHeaderField: "Cookie")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await session.data(for: req) else { return PageConfig() }
        let config = Self.pageConfig(from: data)
        if config.csrf != nil { pageConfigs[s.sessionId] = config }
        return config
    }

    private struct UntisReply {
        var code: Int
        var data: Data
        var json: JSON { JSON.parse(data) }
        var expired: Bool { code == 401 || data.first == UInt8(ascii: "<") }
        var ok: Bool { (200..<300).contains(code) && !expired }
    }

    /// A classic write: cookie session, X-CSRF-TOKEN, Tenant-Id and JSON, no bearer. A 403 is a
    /// stale CSRF token (nothing was written), so it goes once more with a fresh one.
    private func classicWrite(_ s: UserSession, _ path: String, method: String, body: [String: Any]) async throws -> UntisReply {
        try requireSessionToWrite(s)
        guard let url = URL(string: base(s) + path) else { throw AppError(message: Strings.current.errors.badAnswer) }
        let payload = try JSONSerialization.data(withJSONObject: body)
        func send(_ config: PageConfig) async throws -> UntisReply {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue(cookieHeader(s), forHTTPHeaderField: "Cookie")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let csrf = config.csrf { req.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN") }
            if let tenant = config.tenant ?? Self.tenantId(s.bearerToken) { req.setValue(tenant, forHTTPHeaderField: "Tenant-Id") }
            req.httpBody = payload
            let (data, resp) = try await session.data(for: req)
            return UntisReply(code: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        }
        let first = try await send(await pageConfig(s))
        if first.code != 403 { return first }
        return try await send(await pageConfig(s, force: true))
    }

    /// A REST call with the session's auth and no body.
    private func send(_ urlString: String, method: String, _ s: UserSession) async throws -> (Data, HTTPURLResponse) {
        try requireSessionToWrite(s)
        guard let url = URL(string: urlString) else { throw AppError(message: Strings.current.errors.badAnswer) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers(s) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AppError(message: Strings.current.errors.untisDown) }
        return (data, http)
    }

    /// The reason WebUntis gives for a rejected request, in any of its services' shapes.
    private static func untisError(_ json: JSON) -> String? {
        if let m = json.errorMessage.string?.trimmingCharacters(in: .whitespaces), !m.isEmpty { return m }
        let joined = json.validationErrors.array.compactMap(\.errorMessage.string).filter { !$0.isEmpty }.joined(separator: " ")
        if !joined.isEmpty { return joined }
        if let first = json.errors.array.first,
           let m = [first.title.string, first.detail.string].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            return m.trimmingCharacters(in: .whitespaces)
        }
        let m = json.message.string?.trimmingCharacters(in: .whitespaces) ?? ""
        return m.isEmpty ? nil : m
    }

    /// A write right on absences in the app data ("STUDABS_REPORT:RW"); no rights part means all.
    private static let absenceWriteRight =
        #""(?:STUDABS_REPORT|SELF_ABSENCEREASON|WRITE_OWN_ABSENCE|WRITE_STUD_ABSENCE|STUDENT_ABSENCE|SELF_ABSENCE)(?::[A-Z]*[WC][A-Z]*)?""#

    /// WebUntis sends HHMM (750) or minutes since midnight (470); always answers HHMM.
    static func hhmm(_ n: Int) -> Int { UntisRange.hhmm(n) }

    /// Plain text from WebUntis' rich text: line breaks kept, tags and entities resolved.
    static func plainText(_ value: String) -> String {
        guard value.contains("<") || value.contains("&") else { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        var out = value
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|li|h\d)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        if let re = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let r = Range(m.range, in: out), let nr = Range(m.range(at: 1), in: out),
                      let code = UInt32(out[nr]), let scalar = Unicode.Scalar(code) else { continue }
                out.replaceSubrange(r, with: String(Character(scalar)))
            }
        }
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Plain text into the HTML paragraphs WebUntis stores message bodies as.
    static func plainTextToHtml(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (char, entity) in [("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&#39;")] {
            escaped = escaped.replacingOccurrences(of: char, with: entity)
        }
        return escaped.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined()
    }

    // ── Helfer ─────────────────────────────────────────────────────────────

    private func yyyymmdd(_ date: Date) -> String { DateFmt.compact.string(from: date) }

    static func match(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

/// Excusing a past absence by message, word for word as pokyh-backend's `excuseMessage.ts` writes
/// it, so the web and the app find each other's excuses again. The subject names the span in a
/// fixed form; that is how "Gesendet" gives the excuse back, nothing else is stored.
private enum ExcuseMessage {
    /// A span as YYYYMMDDHHMM numbers.
    struct Span { var start: Int; var end: Int }

    private struct Wording {
        var prefix: String
        var sep: String
        var weekdays: [String]   // Sunday first
        var hello: String
        var one: (String) -> String
        var many: String
        var oneChild: (String, String) -> String
        var manyChild: (String) -> String
        var onDay: (String, String?, String?) -> String
        var at: (String, String) -> String
        var range: (String, String) -> String
        var reason: String
        var note: String
        var bye: String
    }

    private static func wording(_ lang: Lang) -> Wording {
        switch lang {
        case .de:
            Wording(prefix: "Entschuldigung", sep: ".",
                    weekdays: ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"],
                    hello: "Guten Tag,",
                    one: { "hiermit entschuldige ich meine Abwesenheit \($0)." },
                    many: "hiermit entschuldige ich meine folgenden Abwesenheiten:",
                    oneChild: { "hiermit entschuldige ich die Abwesenheit meines Kindes \($0) \($1)." },
                    manyChild: { "hiermit entschuldige ich die folgenden Abwesenheiten meines Kindes \($0):" },
                    onDay: { d, f, t in f != nil && t != nil ? "am \(d), von \(f!) bis \(t!)" : "am \(d) (ganztägig)" },
                    at: { "\($0), \($1)" }, range: { "vom \($0) bis \($1)" },
                    reason: "Grund", note: "Bemerkung", bye: "Mit freundlichen Grüßen")
        case .it:
            Wording(prefix: "Giustificazione", sep: "/",
                    weekdays: ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"],
                    hello: "Buongiorno,",
                    one: { "con la presente giustifico la mia assenza \($0)." },
                    many: "con la presente giustifico le mie seguenti assenze:",
                    oneChild: { "con la presente giustifico l’assenza di mio/a figlio/a \($0) \($1)." },
                    manyChild: { "con la presente giustifico le seguenti assenze di mio/a figlio/a \($0):" },
                    onDay: { d, f, t in f != nil && t != nil ? "di \(d) dalle \(f!) alle \(t!)" : "di \(d) (tutto il giorno)" },
                    at: { "\($0) ore \($1)" }, range: { "dal \($0) al \($1)" },
                    reason: "Motivo", note: "Nota", bye: "Cordiali saluti")
        case .en:
            Wording(prefix: "Absence excuse", sep: "/",
                    weekdays: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
                    hello: "Hello,",
                    one: { "I am writing to excuse my absence \($0)." },
                    many: "I am writing to excuse my following absences:",
                    oneChild: { "I am writing to excuse the absence of my child \($0) \($1)." },
                    manyChild: { "I am writing to excuse the following absences of my child \($0):" },
                    onDay: { d, f, t in f != nil && t != nil ? "on \(d), from \(f!) to \(t!)" : "on \(d) (all day)" },
                    at: { "\($0), \($1)" }, range: { "from \($0) to \($1)" },
                    reason: "Reason", note: "Note", bye: "Kind regards")
        }
    }

    /// HHMM (750) or minutes of the day (470), as the classic API mixes them, into minutes.
    private static func minutes(_ t: Int) -> Int {
        if t <= 0 { return 0 }
        if t > 2359 || t % 100 > 59 { return t }
        return (t / 100) * 60 + t % 100
    }

    private static func pad(_ n: Int) -> String { String(format: "%02d", n) }

    private static func clock(_ t: Int) -> String {
        let m = minutes(t)
        return "\(pad(m / 60)):\(pad(m % 60))"
    }

    private static func date(_ d: Int, _ lang: Lang) -> String {
        let sep = wording(lang).sep
        return "\(pad(d % 100))\(sep)\(pad((d / 100) % 100))\(sep)\(d / 10000)"
    }

    /// "Mittwoch, 17.12.2025" / "mercoledì 17/12/2025".
    private static func day(_ d: Int, _ lang: Lang) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let when = cal.date(from: DateComponents(year: d / 10000, month: (d / 100) % 100, day: d % 100))
        let dow = when.map { cal.component(.weekday, from: $0) - 1 } ?? 0
        let weekday = wording(lang).weekdays[dow]
        return lang == .it ? "\(weekday) \(date(d, lang))" : "\(weekday), \(date(d, lang))"
    }

    private static func hasTimes(_ a: AbsenceEntry) -> Bool { a.startTime > 0 || a.endTime > 0 }

    static func span(_ a: AbsenceEntry) -> Span {
        let s = minutes(a.startTime)
        let e = hasTimes(a) ? minutes(a.endTime) : 23 * 60 + 59
        return Span(start: a.startDate * 10_000 + (s / 60) * 100 + s % 60,
                    end: a.endDate * 10_000 + (e / 60) * 100 + e % 60)
    }

    static func span(of absences: [AbsenceEntry]) -> Span {
        let spans = absences.map { span($0) }
        return Span(start: spans.map(\.start).min() ?? 0, end: spans.map(\.end).max() ?? 0)
    }

    private static func whenText(_ a: AbsenceEntry, _ lang: Lang) -> String {
        let t = wording(lang)
        if a.startDate == a.endDate {
            return hasTimes(a) ? t.onDay(day(a.startDate, lang), clock(a.startTime), clock(a.endTime))
                : t.onDay(day(a.startDate, lang), nil, nil)
        }
        return hasTimes(a)
            ? t.range(t.at(day(a.startDate, lang), clock(a.startTime)), t.at(day(a.endDate, lang), clock(a.endTime)))
            : t.range(day(a.startDate, lang), day(a.endDate, lang))
    }

    /// The span in the subject, what `parseSubject` reads back.
    private static func subjectSpan(_ first: AbsenceEntry, _ last: AbsenceEntry, _ lang: Lang) -> String {
        let times = hasTimes(first) || hasTimes(last)
        if first.startDate == last.endDate {
            return times ? "\(date(first.startDate, lang)), \(clock(first.startTime))-\(clock(last.endTime))" : date(first.startDate, lang)
        }
        return times
            ? "\(date(first.startDate, lang)), \(clock(first.startTime)) - \(date(last.endDate, lang)), \(clock(last.endTime))"
            : "\(date(first.startDate, lang)) - \(date(last.endDate, lang))"
    }

    /// Subject and plain-text body of the excuse.
    static func compose(_ absences: [AbsenceEntry], lang: Lang, reasonName: String?, note: String?,
                        childName: String?, signature: String?) -> (subject: String, text: String) {
        let t = wording(lang)
        let sorted = absences.sorted { span($0).start < span($1).start }
        guard let first = sorted.first, let last = sorted.max(by: { span($0).end < span($1).end }) else { return ("", "") }
        let subject = "\(t.prefix): \(subjectSpan(first, last, lang))"
        func clean(_ v: String?) -> String? {
            let x = v?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return x.isEmpty ? nil : x
        }
        let child = clean(childName)
        var lines = [t.hello, ""]
        if sorted.count == 1 {
            let w = whenText(first, lang)
            lines.append(child.map { t.oneChild($0, w) } ?? t.one(w))
        } else {
            lines.append(child.map(t.manyChild) ?? t.many)
            lines += sorted.map { "- \(whenText($0, lang))" }
        }
        let reason = clean(reasonName), n = clean(note)
        if reason != nil || n != nil {
            lines.append("")
            if let reason { lines.append("\(t.reason): \(reason)") }
            if let n { lines.append("\(t.note): \(n)") }
        }
        lines += ["", t.bye]
        if let sig = clean(signature) { lines.append(sig) }
        return (subject, lines.joined(separator: "\n"))
    }

    /// The span an excuse subject names, in any of the languages; nil for any other subject.
    static func parseSubject(_ subject: String?) -> Span? {
        let s = (subject ?? "").trimmingCharacters(in: .whitespaces)
        let lower = s.lowercased()
        guard Lang.allCases.contains(where: { lower.hasPrefix(wording($0).prefix.lowercased() + ":") }) else { return nil }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        // [0-9], not \\d: that also matches other scripts' digits, which Int() can't read.
        guard let dateRe = try? NSRegularExpression(pattern: #"([0-9]{1,2})[./]([0-9]{1,2})[./]([0-9]{4})"#),
              let timeRe = try? NSRegularExpression(pattern: #"(?<![0-9.:/])([0-9]{1,2}):([0-9]{2})(?![0-9.:/])"#) else { return nil }
        func number(_ m: NSTextCheckingResult, _ group: Int) -> Int { Int(ns.substring(with: m.range(at: group))) ?? 0 }
        let dates = dateRe.matches(in: s, range: full).map { m in
            number(m, 3) * 10_000 + number(m, 2) * 100 + number(m, 1)
        }
        guard let firstDate = dates.first, let lastDate = dates.last else { return nil }
        let times = timeRe.matches(in: s, range: full).map { m in
            number(m, 1) * 100 + number(m, 2)
        }.filter { $0 / 100 < 24 && $0 % 100 < 60 }
        let startTime = times.count >= 2 ? times[0] : 0
        let endTime = times.count >= 2 ? times[times.count - 1] : 2359
        let start = firstDate * 10_000 + startTime
        let end = lastDate * 10_000 + endTime
        return end > start ? Span(start: start, end: end) : nil
    }
}

// ── Timetable extras, class duties, homework ────────────────────────────────

extension UntisClient {
    /// Keyed by school and person like the timetable: two schools can share a student id, and a
    /// parent's copies belong to the child.
    private func diskKey(_ kind: String, _ s: UserSession, _ detail: String = "") -> String {
        let key = "\(kind)-\(s.schoolRef.loginName)-\(s.studentId)"
        return detail.isEmpty ? key : "\(key)-\(detail)"
    }

    /// A 403 here means the school doesn't show this, not that the session is gone.
    private func isSignedOut(_ data: Data, _ http: HTTPURLResponse) -> Bool {
        http.statusCode == 401 || data.first == UInt8(ascii: "<")
    }

    /// The stored copy when there's nothing to ask with or no network, else the fresh answer,
    /// which then replaces the copy.
    private func storedOrFresh<T: Codable>(_ key: String, _ s: UserSession, fetch: () async throws -> T) async throws -> T {
        if s.bearerToken.isEmpty {
            if let copy = await DiskCache.loaded(T.self, key: key, owner: s.username) { return copy }
            throw AppError(message: Strings.current.tasks.offlineNotStored)
        }
        do {
            let fresh = try await fetch()
            DiskCache.save(fresh, key: key, owner: s.username)
            return fresh
        } catch let error as URLError {
            if let copy = await DiskCache.loaded(T.self, key: key, owner: s.username) { return copy }
            throw error
        }
    }

    // ── One lesson ───────────────────────────────────────────────────────────

    private func lessonKey(_ entry: TimetableEntry, source: TimetableSource?, _ s: UserSession) -> String {
        diskKey("lesson", s, "\(source?.key ?? "own")-\(entry.date)-\(entry.startTime)-\(entry.endTime)")
    }

    func storedLessonDetail(_ entry: TimetableEntry, source: TimetableSource?, _ s: UserSession) async -> LessonDetail? {
        await DiskCache.loaded(LessonDetail.self, key: lessonKey(entry, source: source, s), owner: s.username)
    }

    /// Asks for the lesson as the timetable it was tapped in has it: at the same hour the student's
    /// own lesson is a different one, with someone else's homework.
    func lessonDetail(_ entry: TimetableEntry, source: TimetableSource?, _ s: UserSession) async throws -> LessonDetail {
        try await storedOrFresh(lessonKey(entry, source: source, s), s) {
            let element = "elementId=\(source?.id ?? s.studentId)&elementType=\(source?.kind.elementType ?? 5)"
            let times = "startDateTime=\(LessonDetail.queryTime(date: entry.date, time: entry.startTime))"
                + "&endDateTime=\(LessonDetail.queryTime(date: entry.date, time: entry.endTime))"
            let (data, http) = try await get("\(base(s))\(TimetableRoutes.lessonDetail)?\(element)&\(times)&homeworkOption=DUE", s, timeout: 10)
            if isSignedOut(data, http) { throw AppError.sessionExpired }
            guard http.statusCode == 200, let detail = LessonDetail.read(JSON.parse(data).raw, lessonId: entry.id) else {
                throw AppError(message: Strings.current.errors.details)
            }
            return detail
        }
    }

    // ── Other timetables ─────────────────────────────────────────────────────

    /// Which classes, teachers or rooms the school shows this account. Often only the own class.
    func timetableFilters(_ kind: TimetableKind, _ s: UserSession) async throws -> [TimetableResource] {
        try await storedOrFresh(diskKey("ttfilter", s, kind.rawValue), s) {
            let start = SchoolDates.mondayISO(of: Date())
            let monday = DateFmt.iso.date(from: start) ?? Date()
            let end = DateFmt.isoString(Calendar.current.date(byAdding: .day, value: 5, to: monday) ?? monday)
            let url = "\(base(s))\(TimetableRoutes.filter)?resourceType=\(kind.rawValue)&timetableType=STANDARD&start=\(start)&end=\(end)"
            let (data, http) = try await get(url, s, timeout: 12)
            if isSignedOut(data, http) { throw AppError.sessionExpired }
            if http.statusCode == 403 { return [] }
            guard http.statusCode == 200 else { throw AppError(message: Strings.current.timetable.otherFailed) }
            return TimetableFilter.read(JSON.parse(data).raw)
        }
    }

    private func sourceKey(_ source: TimetableSource, date: String, _ s: UserSession) -> String {
        "\(s.schoolRef.loginName)-\(source.key)-\(date)"
    }

    func cachedTimetable(source: TimetableSource, date: String, _ s: UserSession) -> [TimetableEntry]? {
        let key = sourceKey(source, date: date, s)
        if let cached = timetableCache.get(key) { return cached }
        return s.bearerToken.isEmpty ? DiskCache.load([TimetableEntry].self, key: "tt-\(key)", owner: s.username) : nil
    }

    /// Another timetable's week, as far as the school shows it to this account.
    func timetable(source: TimetableSource, date: String, _ s: UserSession) async throws -> [TimetableEntry] {
        let key = sourceKey(source, date: date, s)
        if let cached = timetableCache.get(key) { return cached }
        if s.bearerToken.isEmpty { return DiskCache.load([TimetableEntry].self, key: "tt-\(key)", owner: s.username) ?? [] }
        guard let start = DateFmt.iso.date(from: date),
              let saturday = Calendar.current.date(byAdding: .day, value: 5, to: start) else {
            throw AppError(message: Strings.current.errors.badAnswer)
        }
        let end = DateFmt.isoString(saturday)
        let url = "\(base(s))\(Config.Routes.timetable)?start=\(date)&end=\(end)&format=1"
            + "&resourceType=\(source.kind.rawValue)&resources=\(source.id)&periodTypes=&timetableType=STANDARD&layout=START_TIME"
        do {
            let (data, http) = try await get(url, s)
            if isSignedOut(data, http) { throw AppError.sessionExpired }
            if http.statusCode == 403 { throw AppError(message: Strings.current.timetable.otherFailed) }
            guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.timetable(http.statusCode)) }
            let entries = Self.parseTimetable(JSON.parse(data))
            timetableCache.set(key, entries)
            DiskCache.save(entries, key: "tt-\(key)", owner: s.username)
            return entries
        } catch let error as URLError {
            if let copy = DiskCache.load([TimetableEntry].self, key: "tt-\(key)", owner: s.username) { return copy }
            throw error
        }
    }

    // ── Holidays ─────────────────────────────────────────────────────────────

    private func holidaysKey(_ s: UserSession) -> String { "holidays-\(s.schoolRef.loginName)" }

    func storedHolidays(_ s: UserSession) async -> [SchoolHoliday] {
        await DiskCache.loaded([SchoolHoliday].self, key: holidaysKey(s), owner: nil) ?? []
    }

    /// An empty answer is a failed one here (getHolidays has no errors to tell apart), so it
    /// never replaces the list on disk.
    func refreshedHolidays(_ s: UserSession) async -> [SchoolHoliday] {
        guard !s.bearerToken.isEmpty, let fresh = try? await holidays(s), !fresh.isEmpty else { return await storedHolidays(s) }
        DiskCache.save(fresh, key: holidaysKey(s))
        return fresh
    }

    // ── Absences of a school year ────────────────────────────────────────────

    func storedAbsences(year: Int, _ s: UserSession) async -> [AbsenceEntry]? {
        await DiskCache.loaded([AbsenceEntry].self, key: diskKey("absences", s, "\(year)"), owner: s.username)
    }

    func schoolYearAbsences(year: Int, _ s: UserSession) async throws -> [AbsenceEntry] {
        try await storedOrFresh(diskKey("absences", s, "\(year)"), s) {
            try await absences(startDate: SchoolDates.yearStart(year), endDate: SchoolDates.yearEnd(year), s)
        }
    }

    // ── Class register ───────────────────────────────────────────────────────

    func storedClassreg(year: Int, _ s: UserSession) -> [ClassregEvent]? {
        DiskCache.load([ClassregEvent].self, key: diskKey("classreg", s, "\(year)"), owner: s.username)
    }

    func classreg(year: Int, _ s: UserSession) async throws -> [ClassregEvent] {
        try await storedOrFresh(diskKey("classreg", s, "\(year)"), s) {
            try await classregEvents(year: year, s)
        }
    }

    // ── Class duties and homework ────────────────────────────────────────────

    func classServices(_ s: UserSession) async throws -> [ClassService] {
        let year = SchoolDates.currentSchoolYear
        return try await storedOrFresh(diskKey("classservices", s, "\(year)"), s) {
            let url = "\(base(s))\(Config.Routes.classServices)?startDate=\(SchoolDates.yearStart(year))&endDate=\(SchoolDates.yearEnd(year))"
            let (data, http) = try await get(url, s, timeout: 15)
            if isSignedOut(data, http) { throw AppError.sessionExpired }
            if http.statusCode == 403 { return [] }
            guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.services) }
            return ClassServices.read(JSON.parse(data).raw, klasseId: s.klasseId)
        }
    }

    /// Homework due between two days (YYYYMMDD). The route asks by date only, so a parent's
    /// answer is narrowed down to the child shown.
    func homeworks(from start: Int, to end: Int, _ s: UserSession) async throws -> [HomeworkItem] {
        try await storedOrFresh(diskKey("homework", s, "\(start)"), s) {
            let (data, http) = try await get("\(base(s))\(Config.Routes.homeworks)?startDate=\(start)&endDate=\(end)", s, timeout: 15)
            if isSignedOut(data, http) { throw AppError.sessionExpired }
            if http.statusCode == 403 { return [] }
            guard http.statusCode == 200 else { throw AppError(message: Strings.current.errors.homework(http.statusCode)) }
            return HomeworkList.read(JSON.parse(data).raw, childId: s.isParent ? s.studentId : nil, klasseId: s.klasseId)
        }
    }
}
