import Foundation

/// WebUntis-Client — repliziert die Server-Proxy-Routen des Frontends direkt nativ:
/// JSON-RPC `authenticate`, Bearer-Token, Stundenplan/Noten/Abwesenheiten/Nachrichten.
final class UntisClient {
    static let shared = UntisClient()

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    private var base: String { Config.untisBase }

    private func cookieHeader(_ sessionId: String) -> String {
        "JSESSIONID=\(sessionId); schoolname=\"\(Config.schoolCookie)\""
    }

    private func headers(_ s: UserSession) -> [String: String] {
        var h = ["Cookie": cookieHeader(s.sessionId), "Accept": "application/json"]
        if !s.bearerToken.isEmpty { h["Authorization"] = "Bearer \(s.bearerToken)" }
        return h
    }

    private func get(_ urlString: String, _ s: UserSession, timeout: TimeInterval? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw AppError(message: "Ungültige URL") }
        var req = URLRequest(url: url)
        if let timeout { req.timeoutInterval = timeout }
        for (k, v) in headers(s) { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AppError(message: "Keine Antwort") }
        return (data, http)
    }

    private func isHtmlOrAuthError(_ data: Data, _ http: HTTPURLResponse) -> Bool {
        if http.statusCode == 401 || http.statusCode == 403 { return true }
        let prefix = String(decoding: data.prefix(1), as: UTF8.self)
        return prefix == "<"
    }

    // ── Login ──────────────────────────────────────────────────────────────

    func login(username rawUsername: String, password: String) async throws -> UserSession {
        let username = rawUsername.trimmingCharacters(in: .whitespaces).lowercased()
        guard !username.isEmpty, !password.isEmpty else {
            throw AppError(message: "Benutzername und Passwort erforderlich.")
        }

        // 1. JSON-RPC authenticate
        let rpcBody: [String: Any] = [
            "id": "pockyh-web", "method": "authenticate",
            "params": ["user": username, "password": password, "client": Config.untisClient],
            "jsonrpc": "2.0",
        ]
        guard let rpcURL = URL(string: "\(base)/jsonrpc.do?school=\(Config.school)") else {
            throw AppError(message: "Ungültige URL")
        }
        var req = URLRequest(url: rpcURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: rpcBody)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AppError(message: "Keine Antwort von Untis.") }

        // Set-Cookie → JSESSIONID
        let setCookie = (http.value(forHTTPHeaderField: "Set-Cookie")) ?? ""
        let sessionId = Self.match(#"JSESSIONID=([^;]+)"#, in: setCookie) ?? ""

        let json = JSON.parse(data)
        if json.error.exists {
            let msg = json.error.message.string ?? "Anmeldung fehlgeschlagen."
            throw AppError(message: msg)
        }
        guard let studentId = json.result.personId.int else {
            throw AppError(message: "Anmeldung fehlgeschlagen.")
        }
        let klasseId = json.result.klasseId.int ?? 0
        let personType = json.result.personType.int

        var s = UserSession(
            sessionId: sessionId, bearerToken: "", studentId: studentId,
            klasseId: klasseId, klasseName: "", username: username,
            personName: nil, personType: personType, isParent: false
        )

        // 2. Bearer-Token
        s.bearerToken = (try? await fetchToken(s)) ?? ""

        // 3. Klassenname + 4. Schüler-Liste.
        // Wichtig: unveränderliche Kopie für die nebenläufigen Tasks (kein Data Race —
        // `s` darf erst NACH dem Await mutiert werden).
        let snapshot = s
        async let klassen = fetchKlassen(snapshot, klasseId: klasseId)
        async let students = fetchStudents(snapshot)
        let klasseName = (try? await klassen) ?? ""
        let studentList = (try? await students) ?? []
        s.klasseName = klasseName

        // Effektiven Schüler/Eltern auflösen + Namen + klasseId.
        // personType 5 = Schüler (WebUntis); so wird ein Schüler nie fälschlich als
        // Elternteil behandelt, auch wenn `getStudents` leer ist.
        let isStudentType = (personType == 5)
        let isStudentSelf = studentList.contains { $0.id == studentId }
        let isParentCandidate = !isStudentType && !isStudentSelf

        if isStudentType || isStudentSelf {
            let me = studentList.first { $0.id == studentId }
            s.personName = me?.name
            // Eigene klasseId aus dem Schüler-Datensatz, falls `authenticate` 0 lieferte.
            if s.klasseId <= 0, let kid = me?.klasseId, kid > 0 { s.klasseId = kid }
        } else if let first = studentList.first {
            // Eltern, die doch eine Schülerliste erhalten.
            s.studentId = first.id
            if let kid = first.klasseId { s.klasseId = kid }
            s.personName = first.name
            s.isParent = true
        }

        // App-Daten HÖCHSTENS EINMAL laden (teuer: mehrere Endpunkte) — nur, wenn noch
        // etwas fehlt: klasseId unbekannt oder echtes Elternkonto ohne Schülerliste.
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
            // Profilbild (user.person.imageUrl) — best effort.
            s.imageUrl = appData.user.person.imageUrl.string ?? appData.data.user.person.imageUrl.string
        }

        // Letzte Quelle für Schüler: die Klasse steckt nur im Stundenplan (LBS Brixen:
        // authenticate=0, getStudents gesperrt, app/data ohne Klasse). Klassen-Name aus
        // dem Stundenplan ziehen → via getKlassen auf die numerische ID mappen. Gecacht.
        if s.klasseId <= 0, isStudentType {
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

    private func fetchToken(_ s: UserSession) async throws -> String {
        let (data, http) = try await get("\(base)/api/token/new", s)
        guard http.statusCode == 200 else { return "" }
        let tok = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return tok.filter { $0 == "." }.count == 2 ? tok : ""
    }

    private func rpc(_ method: String, _ s: UserSession, id: String) async throws -> JSON {
        guard let url = URL(string: "\(base)/jsonrpc.do?school=\(Config.school)") else {
            throw AppError(message: "Ungültige URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cookieHeader(s.sessionId), forHTTPHeaderField: "Cookie")
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

    // ── Klassen-Auflösung über den Stundenplan (Schüler) ───────────────────────
    // Die Klasse steht je Stunde als Element mit `type == "CLASS"` (ohne numerische
    // id). Name extrahieren → via getKlassen auf die ID mappen.

    /// Kombiniert: Klassennamen aus dem Stundenplan holen und auf die numerische
    /// klasseId mappen. Liefert (id, name) oder nil.
    private func resolveStudentClass(_ s: UserSession) async -> (id: Int, name: String)? {
        guard let cls = await classNameFromTimetable(s) else { return nil }
        guard let id = await klasseId(forName: cls, s), id > 0 else { return nil }
        return (id, cls.short)
    }

    /// Sucht eine Woche MIT Unterricht und liefert (shortName, longName) der Klasse.
    /// Wichtig: An Berufsschulen (Blockunterricht) sind ganze Wochen frei → daher über
    /// das ganze Schuljahr verteilte Stichproben (zuerst die aktuelle Woche).
    private func classNameFromTimetable(_ s: UserSession) async -> (short: String, long: String)? {
        let cal = Calendar.current
        let sy = SchoolDates.currentSchoolYear
        var days: [Date] = [Date()]
        // Schulmonate (Sept–Dez im Startjahr, Jän–Juni im Folgejahr), jeweils Mitte.
        for m in [9, 10, 11, 12] {
            if let d = DateFmt.iso.date(from: String(format: "%04d-%02d-15", sy, m)) { days.append(d) }
        }
        for m in [1, 2, 3, 4, 5, 6] {
            if let d = DateFmt.iso.date(from: String(format: "%04d-%02d-15", sy + 1, m)) { days.append(d) }
        }
        for day in days {
            let start = DateFmt.isoString(day)
            let end = DateFmt.isoString(cal.date(byAdding: .day, value: 5, to: day) ?? day)
            let url = "\(base)\(Config.Routes.timetable)?start=\(start)&end=\(end)&format=1&resourceType=STUDENT&resources=\(s.studentId)&periodTypes=&timetableType=MY_TIMETABLE&layout=START_TIME"
            guard let (data, http) = try? await get(url, s, timeout: 8), http.statusCode == 200 else { continue }
            if let cls = Self.extractClassName(JSON.parse(data)) { return cls }
        }
        return nil
    }

    /// Klassen-Element (`type == "CLASS"`) aus den Stundenplan-Positionen ziehen.
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

    /// `getKlassen` MIT Schuljahr-Kontext. Ohne `schoolyearId` wirft WebUntis zwischen
    /// den Schuljahren „schoolyear is null". Daher das Schuljahr explizit mitgeben.
    func getKlassen(schoolyearId: Int?, _ s: UserSession) async throws -> JSON {
        guard let url = URL(string: "\(base)/jsonrpc.do?school=\(Config.school)") else {
            throw AppError(message: "Ungültige URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cookieHeader(s.sessionId), forHTTPHeaderField: "Cookie")
        var params: [String: Any] = [:]
        if let schoolyearId { params["schoolyearId"] = schoolyearId }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": "pockyh-klassen", "method": "getKlassen", "params": params, "jsonrpc": "2.0",
        ])
        let (data, _) = try await session.data(for: req)
        return JSON.parse(data)
    }

    /// Schuljahr-ID für ein Jahr (über getSchoolyears, robust auch wenn „current" null ist).
    func resolvedSchoolyearId(_ s: UserSession) async -> Int? {
        let id = try? await schoolyearId(year: SchoolDates.currentSchoolYear, s)
        if let id, id > 0 { return id }
        return nil
    }

    /// numerische klasseId per Namensabgleich über getKlassen (mit Schuljahr-Kontext).
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

    // ── Klassen-Cache (pro Benutzer + Schuljahr) → spart Stundenplan/getKlassen ──
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

    /// Liefert (id, klasseId?, name) der zugänglichen Schüler.
    private func fetchStudents(_ s: UserSession) async throws -> [(id: Int, klasseId: Int?, name: String)] {
        let result = try await rpc("getStudents", s, id: "pockyh-students")
        return result.array.compactMap { st in
            guard let id = st.id.int else { return nil }
            let fore = st.foreName.string ?? st.firstName.string ?? ""
            let long = st.longName.string ?? st.lastName.string ?? ""
            let full = [fore, long].filter { !$0.isEmpty }.joined(separator: " ")
            // klasseId direkt oder als eingebettetes `klasse`-Objekt.
            let kid = st.klasseId.int ?? st.klasse.id.int
            return (id, kid, full.isEmpty ? (st.name.string ?? "") : full)
        }
    }

    // ── App-Daten (für Eltern-/Erziehungsberechtigtenkonten) ───────────────────

    private static let appDataPaths = [
        "/api/rest/view/v1/app/data", "/api/app/data",
        "/api/rest/view/v1/users/me/data", "/api/rest/view/v2/app/data",
    ]

    /// On-Demand-Diagnose: zeigt, welche App-Daten WebUntis liefert und wo die
    /// Klasse steckt (alle Felder, deren Schlüssel „klass" enthält). Keine Passwörter
    /// /Tokens — nur Struktur + Klassen-bezogene Werte, damit die Auflösung exakt
    /// angepasst werden kann.
    func classDiagnostics(_ s: UserSession) async -> String {
        var out = "studentId=\(s.studentId)  personType=\(s.personType.map(String.init) ?? "nil")\n"
        out += "klasseId=\(s.klasseId)  klasseName=\(s.klasseName.isEmpty ? "—" : s.klasseName)\n\n"

        // 1) getStudents (JSON-RPC) — liefert je Schüler oft die klasseId.
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

        // 2) App-Daten: das `user`-Objekt (Klasse/Rolle steckt meist hier).
        out += "\n── app/data ──\n"
        for path in Self.appDataPaths {
            guard let (data, http) = try? await get("\(base)\(path)", s, timeout: 6) else { continue }
            guard http.statusCode == 200, case let dict as [String: Any] = JSON.parse(data).raw else { continue }
            out += "\(path) → top: \(dict.keys.sorted().joined(separator: ", "))\n"
            if let user = dict["user"] { out += "user:\n" + Self.pretty(user, max: 1500) + "\n" }
            break
        }

        // 3) Stundenplan — die Klasse steckt nur hier (mehrere Wochen probieren, da die
        //    aktuelle Woche am Schuljahresende leer sein kann).
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
            let url = "\(base)/api/rest/view/v1/timetable/entries?start=\(start)&end=\(end)&format=1&resourceType=STUDENT&resources=\(s.studentId)&periodTypes=&timetableType=MY_TIMETABLE&layout=START_TIME"
            guard let (data, http) = try? await get(url, s, timeout: 8), http.statusCode == 200 else { continue }
            if let first = JSON.parse(data).days.array.flatMap({ $0.gridEntries.array }).first?.raw {
                out += "Woche ab \(start):\n" + Self.pretty(first, max: 2000)
                dumped = true
                break
            }
        }
        if !dumped { out += "keine Stunden in den geprüften Wochen gefunden" }

        // 4) Klassen-Auflösung End-to-End testen: Name aus Stundenplan → getKlassen → ID.
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

    /// Kompaktes, gekürztes JSON für die Diagnose-Anzeige.
    private static func pretty(_ obj: Any, max: Int) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { return String(String(describing: obj).prefix(max)) }
        return String(String(decoding: data, as: UTF8.self).prefix(max))
    }

    private func fetchAppData(_ s: UserSession) async throws -> JSON? {
        // Jeder Endpunkt unabhängig + zeitlich begrenzt → ein langsamer Endpunkt
        // blockiert nicht den ganzen Login (verhinderte den mehrsekündigen Hang).
        for path in Self.appDataPaths {
            guard let (data, http) = try? await get("\(base)\(path)", s, timeout: 6) else { continue }
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

    /// Kind-Schüler-ID aus den App-Daten (user.students[0].id) — wie im Frontend.
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

    /// Klassen-ID aus den App-Daten (für Schüler, deren `authenticate`/`getStudents`
    /// keine klasseId liefert). Priorität: Klasse des angemeldeten Schülers
    /// (`personId`), dann `students[].klasseId`, dann beliebiges `klasse.id`/`klasseId`.
    private func extractKlasseId(_ json: JSON, personId: Int) -> Int? {
        var matched: [Int] = []        // Klasse genau des angemeldeten Schülers
        var fromStudents: [Int] = []   // aus students/children-Arrays
        var fromKlassenArr: [Int] = [] // aus `klassen`-Array (masterData) — Schüler: eigene Klasse
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
            // Datensatz des angemeldeten Schülers selbst?
            let oid = intVal(o["id"]) ?? intVal(o["personId"]) ?? intVal(o["studentId"])
            if let oid, oid == personId, let kid = klasseIdOf(o) { matched.append(kid) }
            for case let c as [String: Any] in (o["students"] as? [Any] ?? []) {
                if let kid = klasseIdOf(c) { fromStudents.append(kid) }
            }
            for case let c as [String: Any] in (o["children"] as? [Any] ?? []) {
                if let kid = klasseIdOf(c) { fromStudents.append(kid) }
            }
            // `klassen`-Array (z. B. masterData.klassen) — bei Schülern auf die eigene
            // Klasse gefiltert; Objekte tragen die ID als `id`.
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

    // ── Caches (In-Memory, nach Schüler-ID gekeyt → kein Account-Leak) ─────────
    private let timetableCache = TTLCache<String, [TimetableEntry]>(ttl: 300)   // key: "studentId-yyyy-MM-dd"
    private let gradesCache = TTLCache<String, [SubjectGrades]>(ttl: 300)        // key: "studentId-year"

    private let examsCache = TTLCache<Int, [TimetableEntry]>(ttl: 600)   // key: studentId

    func clearCaches() { timetableCache.removeAll(); gradesCache.removeAll(); examsCache.removeAll() }

    /// Kommende Prüfungen/Schularbeiten (ab heute, ~40 Tage), gecacht.
    func upcomingExams(_ s: UserSession) async throws -> [TimetableEntry] {
        if let cached = examsCache.get(s.studentId) { return cached }
        let start = DateFmt.isoString(Date())
        let end = DateFmt.isoString(Calendar.current.date(byAdding: .day, value: 40, to: Date())!)
        let url = "\(base)\(Config.Routes.timetable)?start=\(start)&end=\(end)&format=1&resourceType=STUDENT&resources=\(s.studentId)&periodTypes=&timetableType=MY_TIMETABLE&layout=START_TIME"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { return [] }
        let todayNum = DateFmt.num(Date())
        let exams = Self.parseTimetable(JSON.parse(data))
            .filter { $0.isExam && $0.date >= todayNum }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.startTime < $1.startTime }
        examsCache.set(s.studentId, exams)
        return exams
    }

    // ── Stundenplan ──────────────────────────────────────────────────────────

    /// Synchroner Cache-Peek (kein Netzwerk) — erlaubt der UI, eine bereits
    /// vorgeladene Woche sofort und ohne Spinner-Flash anzuzeigen.
    func cachedTimetable(date: String, _ s: UserSession) -> [TimetableEntry]? {
        timetableCache.get("\(s.studentId)-\(date)")
    }

    func timetable(date: String, _ s: UserSession) async throws -> [TimetableEntry] {
        let key = "\(s.studentId)-\(date)"
        if let cached = timetableCache.get(key) { return cached }
        // Ende = Start + 5 Tage (Mo–Sa)
        guard let d = DateFmt.iso.date(from: date) else { throw AppError(message: "Ungültiges Datum") }
        let end = DateFmt.isoString(Calendar.current.date(byAdding: .day, value: 5, to: d)!)
        let url = "\(base)/api/rest/view/v1/timetable/entries?start=\(date)&end=\(end)&format=1&resourceType=STUDENT&resources=\(s.studentId)&periodTypes=&timetableType=MY_TIMETABLE&layout=START_TIME"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: "Stundenplan nicht ladbar (HTTP \(http.statusCode)).") }
        let entries = Self.parseTimetable(JSON.parse(data))
        timetableCache.set(key, entries)
        return entries
    }

    static func parseTimetable(_ json: JSON) -> [TimetableEntry] {
        var entries: [TimetableEntry] = []
        for day in json.days.array {
            guard let dateStr = day.date.string else { continue }
            let dateNum = Int(dateStr.replacingOccurrences(of: "-", with: "")) ?? 0
            for ge in day.gridEntries.array {
                guard let startStr = ge.duration.start.string,
                      let endStr = ge.duration.end.string else { continue }
                func hm(_ iso: String) -> Int {
                    let parts = iso.split(separator: "T")
                    guard parts.count == 2 else { return 0 }
                    let t = parts[1].split(separator: ":")
                    let h = Int(t.first ?? "0") ?? 0
                    let m = t.count > 1 ? (Int(t[1]) ?? 0) : 0
                    return h * 100 + m
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
                let isSubstitution = isChanged && !removedTeachers.isEmpty

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
                    note: ge.lessonInfo.string ?? ge.lessonText.string,
                    examDescription: ge.exam.description.string
                ))
            }
        }
        return entries.sorted { $0.date != $1.date ? $0.date < $1.date : $0.startTime < $1.startTime }
    }

    // ── Noten ──────────────────────────────────────────────────────────────

    func grades(year: Int?, _ s: UserSession) async throws -> [SubjectGrades] {
        let cacheKey = "\(s.studentId)-\(year ?? 0)"
        if let cached = gradesCache.get(cacheKey) { return cached }
        guard let schoolyearId = try await schoolyearId(year: year, s) else {
            throw AppError(message: "Schuljahr nicht gefunden.")
        }
        if schoolyearId == -1 { throw AppError.sessionExpired }

        let listURL = "\(base)/api/classreg/grade/grading/list?studentId=\(s.studentId)&schoolyearId=\(schoolyearId)"
        let (data, http) = try await get(listURL, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: "Noten nicht ladbar (HTTP \(http.statusCode)).") }

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
        return result
    }

    private func gradesForLesson(lessonId: Int, subjectName: String, teacherName: String, _ s: UserSession) async throws -> SubjectGrades? {
        let url = "\(base)/api/classreg/grade/grading/lesson?studentId=\(s.studentId)&lessonId=\(lessonId)"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) || http.statusCode != 200 { return nil }
        let json = JSON.parse(data)
        let entries: [GradeEntry] = json.data.grades.array.compactMap { g in
            let markValue = g.mark.markValue.double ?? 0
            guard markValue > 0 else { return nil }
            return GradeEntry(
                id: g.id.int ?? 0,
                text: g.text.string ?? "",
                date: g.date.int ?? 0,
                markName: g.mark.name.string ?? "",
                markValue: markValue,
                markDisplayValue: g.mark.markDisplayValue.double ?? markValue,
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

    /// Liefert Schuljahr-ID; -1 = Session abgelaufen, nil = nicht gefunden.
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
        guard let url = URL(string: "\(base)/jsonrpc.do?school=\(Config.school)") else {
            throw AppError(message: "Ungültige URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cookieHeader(s.sessionId), forHTTPHeaderField: "Cookie")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": id, "method": method, "params": [:], "jsonrpc": "2.0",
        ])
        let (data, _) = try await session.data(for: req)
        return JSON.parse(data)
    }

    // ── Abwesenheiten ────────────────────────────────────────────────────────

    func absences(startDate: String, endDate: String, _ s: UserSession) async throws -> [AbsenceEntry] {
        let pageSize = 100
        let baseURL = "\(base)/api/classreg/absences/students?studentId=\(s.studentId)&startDate=\(startDate)&endDate=\(endDate)&excuseStatusId=-1&limit=\(pageSize)&pageSize=\(pageSize)"
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
                if page == 0 { throw AppError(message: "Abwesenheiten nicht ladbar (HTTP \(http.statusCode)).") }
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
        let startTime = item.startTime.int ?? 0
        let endTime = item.endTime.int ?? 0
        let rawHours = item.hours.int ?? item.lessonHours.int
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
            startDate: item.startDate.int ?? 0,
            endDate: item.endDate.int ?? 0,
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
        let path: String
        switch folder {
        case .inbox: path = "/api/rest/view/v1/messages"
        case .sent: path = "/api/rest/view/v1/messages/sent"
        case .drafts: path = "/api/rest/view/v1/messages/drafts"
        }
        let url = "\(base)\(path)?pageSize=100&start=0"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: "Nachrichten nicht ladbar (HTTP \(http.statusCode)).") }
        return Self.parseMessages(JSON.parse(data))
    }

    static func parseMessages(_ json: JSON) -> [MessagePreview] {
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
            let recipientLabel = m.recipients.array
                .compactMap { $0.displayName.string ?? $0.name.string }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let senderName = sender.displayName.string
                ?? sender.name.string
                ?? m.senderName.string
                ?? (recipientLabel.isEmpty ? "Unbekannt" : "An: \(recipientLabel)")
            let sentDate = m.sentDateTime.string ?? m.sentDate.string ?? m.date.string ?? ""
            let isRead = m.isRead.bool ?? m.read.bool ?? m.readFlag.bool ?? true
            return MessagePreview(
                id: m.id.int ?? 0,
                subject: m.subject.string ?? "(Kein Betreff)",
                contentPreview: m.contentPreview.string ?? "",
                senderName: senderName,
                senderId: sender.userId.int ?? 0,
                sentDate: sentDate,
                isRead: isRead,
                hasAttachments: m.hasAttachments.bool ?? false
            )
        }
    }

    func messageDetail(id: Int, _ s: UserSession) async throws -> MessageDetail {
        let url = "\(base)/api/rest/view/v1/messages/\(id)"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: "Nachricht nicht ladbar (HTTP \(http.statusCode)).") }
        let m = JSON.parse(data)
        let sender = m.sender
        let senderName = sender.displayName.string ?? sender.name.string ?? m.senderName.string ?? "Unbekannt"
        let attachments = m.attachments.array.map { a in
            MessageAttachment(
                id: a.id.string ?? a.storageId.string ?? UUID().uuidString,
                name: a.name.string ?? a.fileName.string ?? "Anhang",
                size: a.size.int ?? 0
            )
        }
        return MessageDetail(
            id: m.id.int ?? id,
            subject: m.subject.string ?? "(Kein Betreff)",
            senderName: senderName,
            sentDate: m.sentDateTime.string ?? m.sentDate.string ?? "",
            body: m.body.string ?? m.content.string ?? "",
            attachments: attachments
        )
    }

    func markRead(id: Int, _ s: UserSession) async {
        guard let url = URL(string: "\(base)/api/rest/view/v1/messages/\(id)/markasread") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in headers(s) { req.setValue(v, forHTTPHeaderField: k) }
        _ = try? await session.data(for: req)
    }

    // ── Klassenbuch ──────────────────────────────────────────────────────────

    func classregEvents(year: Int?, _ s: UserSession) async throws -> [ClassregEvent] {
        let y = year ?? SchoolDates.currentSchoolYear
        let url = "\(base)/api/classreg/classregevents?startDate=\(y)0908&endDate=\(y + 1)0612&studentId=\(s.studentId)"
        let (data, http) = try await get(url, s)
        if isHtmlOrAuthError(data, http) { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: "Klassenbuch nicht ladbar (HTTP \(http.statusCode)).") }
        let json = JSON.parse(data)
        return json.data.rows.array.map { r in
            ClassregEvent(
                id: r.id.int ?? 0,
                subjectName: r.subjectName.string ?? "",
                creatorName: r.creatorName.string ?? "",
                createDate: r.createDate.int ?? 0,
                eventReasonName: r.eventReasonName.string ?? "",
                categoryName: r.categoryName.string ?? "",
                text: r.text.string ?? ""
            )
        }
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
