import Foundation

/// The WebUntis routes the watch uses on its own. The same paths as the phone's Config.Routes.
public enum UntisRoutes {
    public static let jsonRpc = "/jsonrpc.do"
    public static let jsonRpcIntern = "/jsonrpc_intern.do"
    public static let token = "/api/token/new"
    public static let timetable = "/api/rest/view/v1/timetable/entries"
}

public enum UntisDayError: Error, Equatable {
    case signInFailed(String?)
    case noPerson
    case badAnswer(Int)
}

/// Today's timetable straight from WebUntis, for when the phone is out of reach: signs in with
/// the account the phone handed over (password or app key), loads one day, signs out again.
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

    /// The lessons on `day` and whose they were. `studentId` is the person the phone loads
    /// (a parent's child); without it the account's own person.
    public func lessons(for account: StoredAccount, studentId: Int?, on day: Date = .now,
                        calendar: Calendar = .current) async throws -> (lessons: [WatchSnapshot.Lesson], studentId: Int) {
        let school = account.school
        var signedIn = try await signIn(account)
        signedIn.bearer = (try? await token(signedIn, school: school)) ?? ""
        let person = studentId.flatMap { $0 > 0 ? $0 : nil } ?? signedIn.personId
        let result: Result<[WatchSnapshot.Lesson], any Error>
        do {
            guard person > 0 else { throw UntisDayError.noPerson }
            result = .success(try await timetable(person: person, on: day, signedIn, school: school, calendar: calendar))
        } catch {
            result = .failure(error)
        }
        await signOut(signedIn, school: school)
        return (try result.get(), person)
    }

    func timetable(person: Int, on day: Date, _ signedIn: SignedIn, school: School, calendar: Calendar) async throws -> [WatchSnapshot.Lesson] {
        let date = Self.isoDay(day, calendar: calendar)
        var components = URLComponents(string: Self.base(school) + UntisRoutes.timetable)
        components?.queryItems = [
            URLQueryItem(name: "start", value: date),
            URLQueryItem(name: "end", value: date),
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
        let auth: [String: Any] = ["clientTime": Int(date.timeIntervalSince1970 * 1000), "user": user, "otp": AppKey.totp(key, at: date)]
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

    private func post(_ address: String, body: [String: Any]) async throws -> ([String: Any]?, URLResponse) {
        guard let url = URL(string: address) else { throw UntisDayError.badAnswer(0) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                    id: "\(id)-\(Int(start.timeIntervalSince1970))",
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
