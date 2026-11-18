import Foundation

/// The WebUntis routes the watch uses on its own. The same paths as the phone's Config.Routes.
public enum UntisRoutes {
    public static let jsonRpc = "/jsonrpc.do"
    public static let jsonRpcIntern = "/jsonrpc_intern.do"
    public static let token = "/api/token/new"
    public static let timetable = "/api/rest/view/v1/timetable/entries"
    public static let gradingList = "/api/classreg/grade/grading/list"
    public static let gradingLesson = "/api/classreg/grade/grading/lesson"
}

public enum UntisDayError: Error, Equatable {
    case signInFailed(String?)
    case noPerson
    case noSchoolYear
    case badAnswer(Int)
}

/// What one visit to WebUntis brought back. A part that failed has its error; the visit only
/// throws when the sign-in does.
public struct UntisVisit: Sendable {
    /// Whose timetable and grades these are.
    public var studentId: Int
    /// nil when not asked for.
    public var lessons: Result<[WatchSnapshot.Lesson], any Error>?
    public var grades: Result<WatchGrades, any Error>?
}

/// Timetable and grades straight from WebUntis, for when the phone is out of reach: signs in
/// with the account the phone handed over (password or app key), loads what's asked for, signs
/// out again.
public struct UntisDay: Sendable {
    /// The client name the phone signs in with, so WebUntis sees one app.
    public static let clientName = "pockyh"

    let session: URLSession
    let client: String

    public init(client: String = UntisDay.clientName, session: URLSession? = nil) {
        self.client = client
        self.session = session ?? {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = 15
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: config)
        }()
    }

    struct SignedIn: Sendable {
        var sessionId: String
        var personId: Int
        var bearer: String
    }

    /// The lessons of `days` days from `day` on, and whose they were. `studentId` is the person
    /// the phone loads (a parent's child); without it the account's own person.
    public func lessons(for account: StoredAccount, studentId: Int?, on day: Date = .now, days: Int = 1,
                        calendar: Calendar = .current) async throws -> (lessons: [WatchSnapshot.Lesson], studentId: Int) {
        let visit = try await visit(account, studentId: studentId, lessonsFrom: day, days: days, grades: false, calendar: calendar)
        guard let lessons = visit.lessons else { throw UntisDayError.noPerson }
        return (try lessons.get(), visit.studentId)
    }

    /// One sign-in for everything: the lessons of `days` days from `lessonsFrom` on (none
    /// without a day), the grades of the school year if asked. `whileSignedIn` gets the session
    /// id while it's still valid, for the POKYH sign-in, which WebUntis has to confirm.
    public func visit(_ account: StoredAccount, studentId: Int?, lessonsFrom day: Date?, days: Int = 1, grades: Bool,
                      calendar: Calendar = .current,
                      whileSignedIn: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> UntisVisit {
        let school = account.school
        var signedIn = try await signIn(account)
        signedIn.bearer = (try? await token(signedIn, school: school)) ?? ""
        let person = studentId.flatMap { $0 > 0 ? $0 : nil } ?? signedIn.personId
        let session = signedIn

        async let hook: Void = whileSignedIn(session.sessionId)
        async let lessons: Result<[WatchSnapshot.Lesson], any Error>? = {
            guard let day else { return nil }
            guard person > 0 else { return .failure(UntisDayError.noPerson) }
            do {
                return .success(try await timetable(person: person, on: day, days: days, session, school: school, calendar: calendar))
            } catch {
                return .failure(error)
            }
        }()
        async let marks: Result<WatchGrades, any Error>? = {
            guard grades else { return nil }
            guard person > 0 else { return .failure(UntisDayError.noPerson) }
            do {
                return .success(try await self.grades(person: person, session, school: school, calendar: calendar))
            } catch {
                return .failure(error)
            }
        }()
        let visit = UntisVisit(studentId: person, lessons: await lessons, grades: await marks)
        await hook
        await signOut(signedIn, school: school)
        return visit
    }

    func timetable(person: Int, on day: Date, days: Int = 1, _ signedIn: SignedIn, school: School, calendar: Calendar) async throws -> [WatchSnapshot.Lesson] {
        let last = calendar.date(byAdding: .day, value: max(0, days - 1), to: day) ?? day
        var components = URLComponents(string: Self.base(school) + UntisRoutes.timetable)
        components?.queryItems = [
            URLQueryItem(name: "start", value: Self.isoDay(day, calendar: calendar)),
            URLQueryItem(name: "end", value: Self.isoDay(last, calendar: calendar)),
            URLQueryItem(name: "format", value: "1"),
            URLQueryItem(name: "resourceType", value: "STUDENT"),
            URLQueryItem(name: "resources", value: String(person)),
            URLQueryItem(name: "periodTypes", value: ""),
            URLQueryItem(name: "timetableType", value: "MY_TIMETABLE"),
            URLQueryItem(name: "layout", value: "START_TIME"),
        ]
        guard let url = components?.url else { throw UntisDayError.badAnswer(0) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.cookie(signedIn.sessionId, school: school), forHTTPHeaderField: "Cookie")
        if !signedIn.bearer.isEmpty { request.setValue("Bearer \(signedIn.bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, data.first != UInt8(ascii: "<") else { throw UntisDayError.badAnswer(status) }
        return try Self.parse(data, calendar: calendar)
    }

    // MARK: Grades

    /// Fewer at a time than the phone: the watch's radio is slow and its battery small.
    static let parallelLessons = 4

    /// The grades of the current school year, read the way the phone reads them.
    func grades(person: Int, _ signedIn: SignedIn, school: School, calendar: Calendar) async throws -> WatchGrades {
        guard let year = try await schoolYear(signedIn, school: school) else { throw UntisDayError.noSchoolYear }
        let list = LooseJSON(data: try await get(Self.base(school) + UntisRoutes.gradingList,
                                                 query: ["studentId": String(person), "schoolyearId": String(year)], signedIn, school: school))
        var lessons = list["data"]["lessons"].array
        if lessons.isEmpty { lessons = list["data"]["lesson"].array }
        let wanted: [(id: Int, name: String)] = lessons.compactMap { lesson in
            guard let id = lesson["id"].int else { return nil }
            return (id, lesson["subjects"].string ?? lesson["subject"].string ?? "")
        }
        var subjects: [WatchGrades.Subject] = []
        for start in stride(from: 0, to: wanted.count, by: Self.parallelLessons) {
            let batch = wanted[start..<min(start + Self.parallelLessons, wanted.count)]
            await withTaskGroup(of: WatchGrades.Subject?.self) { group in
                for lesson in batch {
                    group.addTask {
                        // One subject failing leaves the others, as on the phone.
                        guard let data = try? await self.get(Self.base(school) + UntisRoutes.gradingLesson,
                                                             query: ["studentId": String(person), "lessonId": String(lesson.id)],
                                                             signedIn, school: school) else { return nil }
                        return WatchGrades.Subject(name: lesson.name, marks: Self.marks(data))
                    }
                }
                for await subject in group {
                    if let subject, !subject.name.isEmpty, !subject.marks.isEmpty { subjects.append(subject) }
                }
            }
        }
        return WatchGrades(subjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, calendar: calendar)
    }

    /// A subject's answer into marks. What can't be a grade would break every sum after this.
    static func marks(_ data: Data) -> [WatchGrades.Mark] {
        LooseJSON(data: data)["data"]["grades"].array.compactMap { grade in
            let value = grade["mark"]["markValue"].double ?? 0
            let display = grade["mark"]["markDisplayValue"].double ?? value
            guard value > 0, MarkText.isUsable(value), MarkText.isUsable(display) else { return nil }
            return WatchGrades.Mark(id: grade["id"].int ?? 0, value: display, date: grade["date"].int ?? 0, text: grade["text"].string ?? "")
        }
    }

    /// The current school year, else the one today falls in, else the latest.
    func schoolYear(_ signedIn: SignedIn, school: School, at date: Date = .now, calendar: Calendar = .current) async throws -> Int? {
        let current = try await rpc("getCurrentSchoolyear", signedIn, school: school)
        if Self.isSignedOut(current) { throw UntisDayError.signInFailed(Self.errorMessage(current)) }
        if let id = LooseJSON(raw: current?["result"])["id"].int { return id }
        let all = try await rpc("getSchoolyears", signedIn, school: school)
        if Self.isSignedOut(all) { throw UntisDayError.signInFailed(Self.errorMessage(all)) }
        let years = LooseJSON(raw: all?["result"]).array
        let today = Int(Self.isoDay(date, calendar: calendar).replacingOccurrences(of: "-", with: "")) ?? 0
        if let now = years.first(where: { ($0["startDate"].int ?? 0) <= today && today <= ($0["endDate"].int ?? 0) }) {
            return now["id"].int
        }
        return years.max { ($0["startDate"].int ?? 0) < ($1["startDate"].int ?? 0) }?["id"].int
    }

    /// WebUntis' "not authenticated" codes.
    static func isSignedOut(_ json: [String: Any]?) -> Bool {
        let code = LooseJSON(raw: json?["error"])["code"].int ?? 0
        return [-8500, -8501, -8520].contains(code)
    }

    private func rpc(_ method: String, _ signedIn: SignedIn, school: School) async throws -> [String: Any]? {
        let body: [String: Any] = ["id": "pokyh-watch", "method": method, "params": [:], "jsonrpc": "2.0"]
        return try await post(Self.base(school) + UntisRoutes.jsonRpc + "?school=" + Self.query(school), body: body,
                              cookie: Self.cookie(signedIn.sessionId, school: school)).0
    }

    /// A REST read with the session and the bearer token. A login page instead of JSON is no answer.
    private func get(_ address: String, query: [String: String], _ signedIn: SignedIn, school: School) async throws -> Data {
        var components = URLComponents(string: address)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw UntisDayError.badAnswer(0) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.cookie(signedIn.sessionId, school: school), forHTTPHeaderField: "Cookie")
        if !signedIn.bearer.isEmpty { request.setValue("Bearer \(signedIn.bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, data.first != UInt8(ascii: "<") else { throw UntisDayError.badAnswer(status) }
        return data
    }

    // MARK: Sign-in

    func signIn(_ account: StoredAccount) async throws -> SignedIn {
        let school = account.school
        let user = account.username.trimmingCharacters(in: .whitespaces).lowercased()
        if AppKey.isKey(account.secret) {
            return try await signIn(user: user, key: String(account.secret.dropFirst(AppKey.prefix.count)), school: school)
        }
        let body: [String: Any] = [
            "id": "pokyh-watch", "method": "authenticate", "jsonrpc": "2.0",
            "params": ["user": user, "password": account.secret, "client": client],
        ]
        let (json, response) = try await post(Self.base(school) + UntisRoutes.jsonRpc + "?school=" + Self.query(school), body: body)
        let result = json?["result"] as? [String: Any]
        guard let result else { throw UntisDayError.signInFailed(Self.errorMessage(json)) }
        let sessionId = Self.sessionId(response) ?? result["sessionId"] as? String ?? ""
        guard !sessionId.isEmpty else { throw UntisDayError.signInFailed(nil) }
        return SignedIn(sessionId: sessionId, personId: Self.int(result["personId"]) ?? 0, bearer: "")
    }

    /// The app key way in: the one-time code of the moment, as the phone does it.
    func signIn(user: String, key: String, school: School, at date: Date = .now) async throws -> SignedIn {
        let auth: [String: Any] = ["clientTime": Int64(date.timeIntervalSince1970 * 1000), "user": user, "otp": AppKey.totp(key, at: date)]
        let body: [String: Any] = ["id": "pokyh-watch", "method": "getUserData2017", "jsonrpc": "2.0", "params": [["auth": auth]]]
        let url = Self.base(school) + UntisRoutes.jsonRpcIntern + "?m=getUserData2017&school=" + Self.query(school) + "&v=i2.2"
        let (json, response) = try await post(url, body: body)
        guard let result = json?["result"] as? [String: Any], let sessionId = Self.sessionId(response), !sessionId.isEmpty else {
            throw UntisDayError.signInFailed(Self.errorMessage(json))
        }
        let person = (result["userData"] as? [String: Any]).flatMap { Self.int($0["elemId"]) } ?? 0
        return SignedIn(sessionId: sessionId, personId: max(person, 0), bearer: "")
    }

    func token(_ signedIn: SignedIn, school: School) async throws -> String {
        guard let url = URL(string: Self.base(school) + UntisRoutes.token) else { return "" }
        var request = URLRequest(url: url)
        request.setValue(Self.cookie(signedIn.sessionId, school: school), forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return "" }
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.filter { $0 == "." }.count == 2 ? token : ""
    }

    /// Ends the WebUntis session again; one less left open on the school's server.
    func signOut(_ signedIn: SignedIn, school: School) async {
        guard let url = URL(string: Self.base(school) + UntisRoutes.jsonRpc + "?school=" + Self.query(school)) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.cookie(signedIn.sessionId, school: school), forHTTPHeaderField: "Cookie")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["id": "pokyh-watch", "method": "logout", "params": [:], "jsonrpc": "2.0"])
        _ = try? await session.data(for: request)
    }

    private func post(_ address: String, body: [String: Any], cookie: String? = nil) async throws -> ([String: Any]?, URLResponse) {
        guard let url = URL(string: address) else { throw UntisDayError.badAnswer(0) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any], response)
    }

    // MARK: Small parts

    static func base(_ school: School) -> String { "https://\(school.server)/WebUntis" }

    /// The login name for `?school=`: names may hold spaces, `&`, `+` or brackets.
    static func query(_ school: School) -> String {
        school.loginName.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? school.loginName
    }

    static func cookie(_ sessionId: String, school: School) -> String {
        "JSESSIONID=\(sessionId); schoolname=\"_\(Data(school.loginName.utf8).base64EncodedString())\""
    }

    static func sessionId(_ response: URLResponse) -> String? {
        let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        return header.firstMatch(of: /JSESSIONID=([^;,]+)/).map { String($0.1) }
    }

    static func errorMessage(_ json: [String: Any]?) -> String? {
        (json?["error"] as? [String: Any])?["message"] as? String
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: Parsing

extension UntisDay {
    /// The timetable entries answer into lessons, read the way the phone reads it.
    static func parse(_ data: Data, calendar: Calendar = .current) throws -> [WatchSnapshot.Lesson] {
        let answer = try JSONDecoder().decode(Entries.self, from: data)
        var lessons: [WatchSnapshot.Lesson] = []
        for day in answer.days ?? [] {
            for entry in day.gridEntries ?? [] {
                guard let start = entry.duration?.start.flatMap({ localDate($0, calendar: calendar) }),
                      let end = entry.duration?.end.flatMap({ localDate($0, calendar: calendar) }) else { continue }
                let teachers = entry.position1 ?? [], subjects = entry.position2 ?? [], rooms = entry.position3 ?? []
                let activeTeachers = teachers.compactMap { $0.current?.displayName }.filter { !$0.isEmpty }
                let removedTeachers = teachers.compactMap { $0.removed?.displayName }.filter { !$0.isEmpty }
                let activeSubject = subjects.first { $0.current != nil }?.current
                let removedSubject = subjects.first { $0.removed != nil }?.removed
                let activeRooms = rooms.compactMap { $0.current?.displayName }.filter { !$0.isEmpty }
                let removedRooms = rooms.compactMap { $0.removed?.displayName }.filter { !$0.isEmpty }

                let room = activeRooms.joined(separator: ", ")
                let originalRoom = removedRooms.isEmpty ? nil : removedRooms.joined(separator: ", ")
                let status = WatchSnapshot.Lesson.Status.of(
                    cancelled: entry.status == "CANCELLED",
                    exam: entry.type == "EXAM",
                    substitution: entry.status == "CHANGED" && !removedTeachers.isEmpty,
                    additional: entry.type == "ADDITIONAL",
                    room: room,
                    originalRoom: originalRoom
                )
                let id = entry.ids?.first.map(String.init) ?? "\(start.timeIntervalSince1970)"
                lessons.append(WatchSnapshot.Lesson(
                    id: "\(id)-\(Int64(start.timeIntervalSince1970))",
                    subject: activeSubject?.shortName ?? removedSubject?.shortName ?? "",
                    subjectLong: activeSubject?.longName ?? removedSubject?.longName ?? "",
                    teacher: activeTeachers.joined(separator: ", "),
                    room: room,
                    start: start,
                    end: end,
                    status: status,
                    originalTeacher: removedTeachers.isEmpty ? nil : removedTeachers.joined(separator: ", "),
                    originalRoom: originalRoom,
                    note: entry.lessonInfo ?? entry.lessonText
                ))
            }
        }
        return lessons.sorted { $0.start < $1.start }
    }

    /// "2026-10-30T08:00" in school time, which is the device's.
    static func localDate(_ text: String, calendar: Calendar) -> Date? {
        guard let match = text.firstMatch(of: /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/) else { return nil }
        var c = DateComponents()
        c.year = Int(match.1)
        c.month = Int(match.2)
        c.day = Int(match.3)
        c.hour = Int(match.4)
        c.minute = Int(match.5)
        return calendar.date(from: c)
    }

    // Everything optional and read leniently: WebUntis leaves out what doesn't apply.
    struct Entries: Decodable {
        var days: [Day]?
    }

    struct Day: Decodable {
        var date: String?
        var gridEntries: [GridEntry]?
    }

    struct GridEntry: Decodable {
        var ids: [Int]?
        var duration: Span?
        var type: String?
        var status: String?
        var position1: [Position]?
        var position2: [Position]?
        var position3: [Position]?
        var lessonInfo: String?
        var lessonText: String?

        enum CodingKeys: String, CodingKey {
            case ids, duration, type, status, position1, position2, position3, lessonInfo, lessonText
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ids = try? c.decodeIfPresent([Int].self, forKey: .ids)
            duration = try? c.decodeIfPresent(Span.self, forKey: .duration)
            type = try? c.decodeIfPresent(String.self, forKey: .type)
            status = try? c.decodeIfPresent(String.self, forKey: .status)
            position1 = try? c.decodeIfPresent([Position].self, forKey: .position1)
            position2 = try? c.decodeIfPresent([Position].self, forKey: .position2)
            position3 = try? c.decodeIfPresent([Position].self, forKey: .position3)
            lessonInfo = (try? c.decodeIfPresent(String.self, forKey: .lessonInfo)).flatMap { $0.isEmpty ? nil : $0 }
            lessonText = (try? c.decodeIfPresent(String.self, forKey: .lessonText)).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    struct Span: Decodable {
        var start: String?
        var end: String?
    }

    struct Position: Decodable {
        var current: Element?
        var removed: Element?

        enum CodingKeys: String, CodingKey { case current, removed }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            current = try? c.decodeIfPresent(Element.self, forKey: .current)
            removed = try? c.decodeIfPresent(Element.self, forKey: .removed)
        }
    }

    struct Element: Decodable {
        var type: String?
        var shortName: String?
        var longName: String?
        var displayName: String?
    }
}
