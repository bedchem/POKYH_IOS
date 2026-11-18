import Foundation
import Testing
@testable import PokyhCore

// The watch without its phone: its own loads from WebUntis and the backend, its own POKYH
// session, and how its parts and the phone's come together.

private let rome: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Rome")!
    return c
}()

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 30) -> Date {
    rome.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

/// An access token as the backend makes them, unsigned: the watch only reads it.
private func jwt(username: String = "anna", expires: Date) -> String {
    func part(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    return part(#"{"alg":"HS256"}"#) + "." + part(#"{"username":"\#(username)","exp":\#(Int(expires.timeIntervalSince1970))}"#) + ".sig"
}

// MARK: The parts and how they come together

struct WatchPartsTests {
    private let base = WatchSnapshot(username: "anna", updatedAt: at(7), day: rome.startOfDay(for: at(8)),
                                      overallAverage: 7, gradeCount: 2, todos: [WatchSnapshot.Todo(id: "a", title: "Alt")])

    @Test func partsKnowWhenTheyWereLoaded() {
        #expect(base.updated(.grades) == at(7) && base.updated(.lessons) == at(7))
        #expect(base.knowsAnything && base.knows(.mensa))
        let empty = WatchSnapshot.empty(for: "anna", at: at(8), calendar: rome)
        #expect(!empty.knowsAnything)
        // The watch's own grades: the rest stays as unknown as it was.
        let own = empty.withGrades(WatchGrades([WatchGrades.Subject(name: "MAT", marks: [.init(id: 1, value: 8, date: 20261020)])]), at: at(8))
        #expect(own.knows(.grades) && !own.knows(.todos) && !own.knows(.lessons))
        #expect(own.knowsAnything)
        #expect(own.updatedAt == .distantPast)
    }

    @Test func eachPartGoesStaleAtItsOwnPace() {
        var snap = base
        snap.lessonsUpdatedAt = at(8)
        snap.gradesUpdatedAt = at(8)
        snap.mensaUpdatedAt = at(8)
        snap.todosUpdatedAt = at(8)
        snap.mensaDay = rome.startOfDay(for: at(8))
        #expect(!snap.isStale(.todos, at: at(8, 4), calendar: rome))
        #expect(snap.isStale(.todos, at: at(8, 6), calendar: rome))
        #expect(!snap.isStale(.grades, at: at(8, 50), calendar: rome))
        #expect(snap.isStale(.grades, at: at(9, 1), calendar: rome))
        #expect(!snap.isStale(.mensa, at: at(8, 30), calendar: rome))
        // Yesterday's menu says nothing about today.
        snap.mensaDay = rome.startOfDay(for: at(8, day: 29))
        #expect(snap.isStale(.mensa, at: at(8, 30), calendar: rome))
        #expect(snap.isStale(.lessons, at: at(8, 31), calendar: rome))
    }

    @Test func theFresherPartWinsWhicheverSideItCameFrom() throws {
        // The watch loaded grades and to-dos at 9; the phone sends at 9:30 what it loaded at 8.
        let grades = WatchGrades([WatchGrades.Subject(name: "MAT", marks: [.init(id: 5, value: 9, date: 20261029)])])
        let own = base.withGrades(grades, at: at(9)).withTodos([WatchSnapshot.Todo(id: "w", title: "Watch")], at: at(9))
        var phone = base
        phone.updatedAt = at(9, 30)
        phone.lessonsUpdatedAt = at(8)
        phone.gradesUpdatedAt = at(8)
        phone.todosUpdatedAt = at(9, 30)
        phone.overallAverage = 5
        phone.todos = [WatchSnapshot.Todo(id: "p", title: "Phone")]
        phone.dishes = [WatchSnapshot.Dish(id: "d", name: "Pasta", category: "Main")]
        phone.mensaUpdatedAt = at(9, 30)
        phone.lang = .it

        let merged = try #require(own.taking(phone))
        #expect(merged.overallAverage == 9)
        #expect(merged.updated(.grades) == at(9))
        #expect(merged.todos.map(\.id) == ["p"])
        #expect(merged.updated(.todos) == at(9, 30))
        #expect(merged.dishes.map(\.id) == ["d"])
        #expect(merged.lang == .it)
        #expect(merged.updatedAt == at(9, 30))
        // What the merge kept from the watch still says when the watch loaded it.
        #expect(merged.gradesUpdatedAt == at(9))
        // Nothing newer: nothing to take.
        #expect(merged.taking(phone) == nil)
    }

    @Test func aReplyOvertakingTheContextChangesNothing() {
        var newer = base
        newer.updatedAt = at(9)
        newer.todosUpdatedAt = at(9)
        newer.todos = []
        var older = base
        older.updatedAt = at(8)
        older.todosUpdatedAt = at(8)
        let kept = newer.taking(older)
        #expect(kept == nil || kept?.todos.isEmpty == true)
    }

    @Test func thePhoneWritesDownItsStampsBeforeMovingOn() {
        var snap = base
        snap.settleStamps()
        snap.updatedAt = at(10)
        snap.todosUpdatedAt = at(10)
        // Grades it didn't touch stay as old as they are.
        #expect(snap.updated(.grades) == at(7))
        #expect(snap.updated(.todos) == at(10))
        #expect(WatchSnapshot.decoded(from: try! snap.encoded()) == snap)
    }

    @Test func aLoadLeavesWhatThePhoneSentMeanwhile() {
        var phone = base
        phone.todosUpdatedAt = at(9, 5)
        phone.todos = [WatchSnapshot.Todo(id: "p", title: "Phone")]
        var load = WatchLoad()
        load.todos = [WatchSnapshot.Todo(id: "w", title: "Watch")]
        load.grades = WatchGrades([WatchGrades.Subject(name: "MAT", marks: [.init(id: 1, value: 9, date: 0)])])
        // The load started at 9, the phone's to-dos are from 9:05.
        let next = load.applied(to: phone, at: at(9), calendar: rome)
        #expect(next.todos.map(\.id) == ["p"])
        #expect(next.overallAverage == 9)
        #expect(next.updated(.grades) == at(9))
    }

    @Test func gradesLikeTheGradesTab() {
        let grades = WatchGrades([
            WatchGrades.Subject(name: "MAT", marks: [.init(id: 10, value: 8, date: 20261020, text: "Schularbeit"),
                                                    .init(id: 11, value: 7.5, date: 20261027), .init(id: 99, value: 0, date: 20261027)]),
            WatchGrades.Subject(name: "DEU", marks: [.init(id: 12, value: 6, date: 0)]),
            WatchGrades.Subject(name: "GEO", marks: []),
        ], calendar: rome)
        #expect(grades.overall == 7.17)
        #expect(grades.count == 3)
        #expect(grades.subjects.map(\.name) == ["MAT", "DEU"])
        #expect(grades.subjects[0].average == 7.75)
        #expect(grades.subjects[0].grades?.map(\.id) == [11, 10])
        #expect(grades.recent.map(\.id) == [12, 11, 10])
        #expect(grades.recent[2].date == rome.startOfDay(for: at(8, day: 20)))
        // No date is no date, not the year 0.
        #expect(grades.recent[0].date == nil)
        #expect(WatchGrades([]).overall == nil)
    }

    @Test func manyGradesAreCut() {
        let marks = (1...20).map { WatchGrades.Mark(id: $0, value: 8, date: 20261001, text: String(repeating: "x", count: 100)) }
        let grades = WatchGrades([WatchGrades.Subject(name: "MAT", marks: marks)])
        #expect(grades.subjects[0].grades?.count == 12)
        #expect(grades.subjects[0].grades?.first?.id == 20)
        #expect(grades.recent.count == 5)
        #expect(grades.recent[0].text.count == 60)
        #expect(grades.subjects[0].count == 20)
    }

    @Test func todosInTheWebsOrder() throws {
        let json = #"""
        [{"id":"late","title":"Später","dueAt":"2026-11-05T10:00:00.000Z","done":false,"createdAt":"2026-10-01T10:00:00Z"},
         {"id":"none","title":"Ohne Datum","dueAt":null,"done":false,"createdAt":"2026-10-02T10:00:00Z"},
         {"id":"soon","title":"Bald","dueAt":"2026-10-31T10:00:00Z","done":false,"createdAt":"2026-10-03T10:00:00Z"},
         {"id":"ticked","title":"Erledigt","done":true,"doneAt":"2026-10-30T06:00:00Z","createdAt":"2026-10-01T10:00:00Z"},
         {"id":"gone","title":"Lange her","done":true,"doneAt":"2026-10-20T06:00:00Z","createdAt":"2026-10-01T10:00:00Z"},
         {"title":"Ohne id"}]
        """#
        let items = try #require(WatchTodos.items(from: Data(json.utf8)))
        #expect(items.count == 5)
        let todos = WatchTodos.build(items, now: at(9))
        #expect(todos.map(\.id) == ["soon", "late", "none", "ticked"])
        #expect(todos[0].due == ISO8601DateFormatter().date(from: "2026-10-31T10:00:00Z"))
        #expect(todos[3].done)
        #expect(WatchTodos.items(from: Data(#"{"error":"x"}"#.utf8)) == nil)
    }

    @Test func backendDatesInEveryFormTheyCome() {
        #expect(BackendDate.parse("2026-10-30T07:00:00Z") == ISO8601DateFormatter().date(from: "2026-10-30T07:00:00Z"))
        #expect(BackendDate.parse("2026-10-30T07:00:00.250Z") != nil)
        #expect(BackendDate.parse("2026-10-30") != nil)
        #expect(BackendDate.parse("gestern") == nil)
        #expect(BackendDate.day(20261030, calendar: rome) == rome.startOfDay(for: at(9)))
        #expect(BackendDate.day(0) == nil && BackendDate.day(20261399) == nil)
    }

    static let menu = #"""
    {"available":true,"menu":{"dishes":[
      {"id":"old","name":"Gestern","category":"Hauptgericht","date":"2026-10-29","tags":[]},
      {"id":"d1","name":{"de":"Nudeln","it":"Pasta"},"description":{"de":"Mit Tomaten"},"category":"Hauptgericht",
       "date":"2026-10-30","imageUrl":"/dishes/d1/image?v=2","price":4.5,"calories":620,"tags":["Vegetarisch"]},
      {"id":"d2","name":"Suppe","description":"","category":"Vorspeise","date":"2026-10-30","price":0,"calories":"viel","tags":["vegan"]},
      {"id":"d3","name":"Fisch","category":"Hauptgericht","date":"2026-11-02","imageUrl":"https://cdn.example.org/f.jpg"},
      {"name":"Ohne id","date":"2026-10-30"}
    ]}}
    """#

    @Test func theMenuOfTodayOrTheNextDayWithOne() {
        let served = WatchMensa.served(from: Data(Self.menu.utf8), backend: URL(string: "https://backend.test")!)
        #expect(served.map(\.dish.id) == ["old", "d1", "d2", "d3"])
        let today = WatchMensa.menu(served, now: at(9), calendar: rome)
        #expect(today.day == rome.startOfDay(for: at(9)))
        #expect(today.dishes.map(\.id) == ["d1", "d2"])
        let pasta = today.dishes[0]
        #expect(pasta.name == "Nudeln" && pasta.text == "Mit Tomaten")
        #expect(pasta.photo?.absoluteString == "https://backend.test/dishes/d1/image?v=2")
        #expect(pasta.price == 4.5 && pasta.calories == 620 && pasta.diet == .vegetarian)
        let soup = today.dishes[1]
        #expect(soup.text == nil && soup.price == nil && soup.calories == nil && soup.diet == .vegan)
        // Saturday: Monday's menu.
        let saturday = WatchMensa.menu(served, now: at(9, day: 31), calendar: rome)
        #expect(saturday.dishes.map(\.id) == ["d3"])
        #expect(WatchMensa.menu(served, now: at(9, day: 40), calendar: rome).day == nil)
        // The other shapes the answer comes in.
        #expect(WatchMensa.served(from: Data(#"[{"id":"x","name":"A","date":"2026-10-30"}]"#.utf8), backend: URL(string: "https://b.test")!).count == 1)
        #expect(WatchMensa.served(from: Data(#"{"dishes":[{"id":"x","name":"A"}]}"#.utf8), backend: URL(string: "https://b.test")!).count == 1)
    }

    @Test func ratingsAsMeanAndCount() {
        let ratings = WatchMensa.ratings(from: Data(#"{"d1":{"ratings":{"a":4,"b":5},"myRating":4},"d2":{"ratings":{},"myRating":null},"d3":{"ratings":{"a":9}}}"#.utf8))
        #expect(ratings["d1"]?.stars == 4.5 && ratings["d1"]?.count == 2)
        #expect(ratings["d2"]?.stars == nil && ratings["d2"]?.count == 0)
        #expect(ratings["d3"]?.stars == 5)
        let dishes = [WatchSnapshot.Dish(id: "d1", name: "A", category: ""), WatchSnapshot.Dish(id: "d2", name: "B", category: ""),
                      WatchSnapshot.Dish(id: "x", name: "C", category: "", stars: 3, ratings: 1)]
        let rated = WatchMensa.rated(dishes, with: ratings)
        #expect(rated[0].stars == 4.5 && rated[0].ratings == 2)
        #expect(rated[1].stars == nil && rated[1].ratings == 0)
        #expect(rated[2].stars == 3)
    }

    @Test func aNewMenuKeepsTheStarsUntilItsOwnCome() {
        var snap = base
        snap.dishes = [WatchSnapshot.Dish(id: "d1", name: "A", category: "", stars: 4, ratings: 3)]
        let next = snap.withMenu(day: at(0), dishes: [WatchSnapshot.Dish(id: "d1", name: "A", category: ""),
                                                      WatchSnapshot.Dish(id: "d2", name: "B", category: "", stars: 2, ratings: 1)], at: at(9))
        #expect(next.dishes[0].stars == 4 && next.dishes[0].ratings == 3)
        #expect(next.dishes[1].stars == 2)
        #expect(next.updated(.mensa) == at(9))
    }

    @Test func theHandoffSaysWhenThePersonConnected() throws {
        let account = StoredAccount(username: "anna", displayName: "Anna", school: School(loginName: "s", server: "s.test"),
                                    secret: "pw", backend: .parent, studentId: 4711)
        let handoff = AccountHandoff(account: account, sentAt: at(8), connectedAt: at(7))
        let back = try #require(AccountHandoff(payload: handoff.payload))
        #expect(back == handoff)
        #expect(back.account?.backend == .parent && back.account?.studentId == 4711)
        #expect(AccountHandoff(payload: AccountHandoff(account: nil, sentAt: at(8)).payload)?.connectedAt == nil)
    }

    @Test func anAccountFromAnOlderPhoneStillReads() throws {
        let old = #"{"username":"anna","displayName":"Anna","school":{"loginName":"s","server":"s.test","name":"","address":""},"secret":"pw","signedInAt":0}"#
        let account = try JSONDecoder().decode(StoredAccount.self, from: Data(old.utf8))
        #expect(account.backend == nil && account.studentId == nil)
        #expect(!WatchBackend.canSignIn(account))
    }

    @Test func whoSignsInHowAtPOKYH() {
        func account(_ access: BackendAccess?) -> StoredAccount {
            StoredAccount(username: "a", displayName: "a", school: School(loginName: "s", server: "s"), secret: "x", backend: access)
        }
        #expect(WatchBackend.canSignIn(account(.student)) && WatchBackend.signsInWithUntis(account(.student)))
        #expect(WatchBackend.canSignIn(account(.parent)) && WatchBackend.signsInWithUntis(account(.parent)))
        #expect(WatchBackend.canSignIn(account(.password)) && !WatchBackend.signsInWithUntis(account(.password)))
        #expect(!WatchBackend.canSignIn(account(.untisOnly)) && !WatchBackend.canSignIn(account(nil)))
    }

    @Test func tokensSayWhoseAndUntilWhen() {
        let token = jwt(username: "max.muster", expires: at(10))
        #expect(JWTClaims.username(of: token) == "max.muster")
        #expect(JWTClaims.expiry(of: token) == at(10))
        #expect(JWTClaims.expiry(of: "nope") == nil)
    }

    @Test func gradesFromTheirAnswer() {
        let answer = #"{"data":{"grades":[{"id":1,"date":20261020,"text":"SA","mark":{"markValue":8,"markDisplayValue":8.25}},{"id":2,"mark":{"markValue":0}},{"id":3,"mark":{"markValue":"x"}},{"id":4,"mark":{"markValue":7}}]}}"#
        let marks = UntisDay.marks(Data(answer.utf8))
        #expect(marks == [WatchGrades.Mark(id: 1, value: 8.25, date: 20261020, text: "SA"), WatchGrades.Mark(id: 4, value: 7, date: 0)])
    }
}

// MARK: Against a stand-in for WebUntis and the backend

/// Answers every request from one handler and remembers what it was asked, in order.
private final class FakeServer: URLProtocol, @unchecked Sendable {
    struct Request: Sendable {
        var method: String
        var host: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: [String: Any] { (try? JSONSerialization.jsonObject(with: raw) as? [String: Any]) ?? [:] }
        var raw: Data
        /// JSON-RPC's method, for WebUntis.
        var rpc: String? { body["method"] as? String }
    }

    struct Answer {
        var status = 200
        var headers: [String: String] = [:]
        var body = "{}"
    }

    typealias Handler = @Sendable (Request) throws -> Answer

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler = { _ in Answer(status: 404) }
    nonisolated(unsafe) private static var seen: [Request] = []

    static func reset(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            seen = []
        }
    }

    static var requests: [Request] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var raw = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                raw.append(buffer, count: count)
            }
            stream.close()
        }
        let url = request.url!
        let query = Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? []) { a, _ in a }
        let seenRequest = Request(method: request.httpMethod ?? "GET", host: url.host ?? "", path: url.path, query: query,
                                  headers: request.allHTTPHeaderFields ?? [:], raw: raw)
        let handler = Self.lock.withLock {
            Self.seen.append(seenRequest)
            return Self.handler
        }
        do {
            let answer = try handler(seenRequest)
            let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

/// A school and a backend that do what they should, with switches for what they shouldn't.
private struct World: Sendable {
    static let untisHost = "demo.test"
    static let backendHost = "backend.test"

    var loginStatus = 200
    var loginCode: String?
    var refreshStatus = 200
    var todosFirstStatus = 200
    var token = jwt(expires: Date().addingTimeInterval(3600))
    var refreshed = jwt(expires: Date().addingTimeInterval(7200))

    func answer(_ r: FakeServer.Request) throws -> FakeServer.Answer {
        if r.host == Self.untisHost { return untis(r) }
        guard r.host == Self.backendHost else { throw URLError(.cannotFindHost) }
        switch (r.method, r.path) {
        case ("POST", "/auth/login"):
            guard loginStatus == 200 else {
                return .init(status: loginStatus, body: #"{"error":"Nein","code":"\#(loginCode ?? "x")"}"#)
            }
            return .init(body: #"{"token":"\#(token)","refreshToken":"R1","user":{"stableUid":"u1","username":"anna","isAdmin":false}}"#)
        case ("POST", "/auth/refresh"):
            guard refreshStatus == 200 else { return .init(status: refreshStatus, body: #"{"error":"Invalid or expired refresh token"}"#) }
            return .init(body: #"{"token":"\#(refreshed)","refreshToken":"R2"}"#)
        case ("POST", "/auth/logout"):
            return .init(body: #"{"ok":true}"#)
        case ("GET", "/users/anna/todos"):
            if todosFirstStatus != 200, r.headers["Authorization"] == "Bearer \(token)" {
                return .init(status: todosFirstStatus, body: #"{"error":"expired"}"#)
            }
            return .init(body: #"[{"id":"t1","title":"Referat","dueAt":"2026-10-31T10:00:00Z","done":false,"createdAt":"2026-10-01T10:00:00Z"}]"#)
        case ("PATCH", "/users/anna/todos/t1"):
            return .init(body: "{}")
        case ("PATCH", _):
            return .init(status: 404, body: #"{"error":"Not found"}"#)
        case ("GET", "/dishes"):
            return .init(body: WatchPartsTests.menu)
        case ("POST", "/dish-ratings/batch"):
            return .init(body: #"{"d1":{"ratings":{"a":4,"b":5},"myRating":null},"d2":{"ratings":{}}}"#)
        default:
            return .init(status: 404, body: #"{"error":"Not found"}"#)
        }
    }

    private func untis(_ r: FakeServer.Request) -> FakeServer.Answer {
        switch r.path {
        case "/WebUntis/jsonrpc.do":
            switch r.rpc {
            case "authenticate":
                return .init(headers: ["Set-Cookie": "JSESSIONID=S1; Path=/WebUntis; HttpOnly"],
                             body: #"{"result":{"sessionId":"S1","personId":77,"personType":5}}"#)
            case "getCurrentSchoolyear": return .init(body: #"{"result":{"id":12}}"#)
            default: return .init(body: #"{"result":null}"#)
            }
        case "/WebUntis/api/token/new":
            return .init(body: "aaa.bbb.ccc")
        case "/WebUntis/api/rest/view/v1/timetable/entries":
            return .init(body: UntisDayTests.answer)
        case "/WebUntis/api/classreg/grade/grading/list":
            return .init(body: #"{"data":{"lessons":[{"id":1,"subjects":"MAT","teachers":"MUE"},{"id":2,"subjects":"DEU"},{"id":3,"subjects":"GEO"}]}}"#)
        case "/WebUntis/api/classreg/grade/grading/lesson":
            switch r.query["lessonId"] {
            case "1": return .init(body: #"{"data":{"grades":[{"id":10,"date":20261020,"mark":{"markValue":8,"markDisplayValue":8}},{"id":11,"date":20261027,"mark":{"markValue":7.5}}]}}"#)
            case "2": return .init(body: #"{"data":{"grades":[{"id":12,"date":20261028,"mark":{"markValue":6}}]}}"#)
            default: return .init(status: 500, body: "<html>")
            }
        default:
            return .init(status: 404, body: "<html>")
        }
    }
}

@Suite(.serialized)
struct WatchLoaderTests {
    let school = School(loginName: "demo", server: World.untisHost, name: "Demo")
    let store = MemorySecureStore()

    private func backend(defaultSchool: School? = nil) -> WatchBackend {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [FakeServer.self]
        let config = AppConfig(backendURL: URL(string: "https://\(World.backendHost)")!, websiteURL: URL(string: "https://web.test")!,
                               supportEmail: "", apiKey: "KEY", serverKey: "SERVER", appGroup: "", keychainGroup: "",
                               backgroundTask: "", appBundleID: "test", apsEnvironment: "", version: "2.1.0", build: "1")
        let client = BackendClient(config: config, device: DeviceIdentity(id: "watch-device-0001", userAgent: "POKYH-iOS/2.1.0 (watchOS 27.2; Watch7,5)"),
                                   errors: Strings.of(.de).errors, session: URLSession(configuration: settings))
        return WatchBackend(client: client, store: store, defaultSchool: defaultSchool)
    }

    private func loader(_ backend: WatchBackend) -> WatchLoader {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [FakeServer.self]
        return WatchLoader(untis: UntisDay(session: URLSession(configuration: settings)), backend: backend)
    }

    private func account(_ access: BackendAccess? = .student, secret: String = "geheim") -> StoredAccount {
        StoredAccount(username: "anna", displayName: "Anna", school: school, secret: secret, backend: access)
    }

    private let all = Set(WatchSnapshot.Part.allCases)

    @Test func everythingWithOneSchoolSignIn() async throws {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend()
        let load = await loader(backend).load(all, for: account(), studentId: nil, now: at(9), days: 8, calendar: rome)

        #expect(load.reachedNetwork && !load.revoked)
        #expect(load.lessons?.lessons.map(\.subject) == ["MAT", "DEU", "ENG", "BIO"])
        #expect(load.lessons?.studentId == 77)
        #expect(load.grades?.overall == 7.17)
        #expect(load.grades?.subjects.map(\.name) == ["DEU", "MAT"])
        #expect(load.menu?.dishes.map(\.id) == ["d1", "d2"])
        #expect(load.menu?.dishes.first?.stars == 4.5)
        #expect(load.todos?.map(\.title) == ["Referat"])

        let requests = FakeServer.requests
        #expect(requests.filter { $0.rpc == "authenticate" }.count == 1)
        // The backend checks the session with WebUntis, so it signs in before the watch signs out.
        let login = try #require(requests.firstIndex { $0.path == "/auth/login" })
        let logout = try #require(requests.firstIndex { $0.rpc == "logout" })
        #expect(login < logout)
        let body = requests[login].body
        #expect(body["untisSessionId"] as? String == "S1")
        #expect(body["renewal"] as? Bool == true)
        #expect(body["role"] as? String == "student")
        #expect(body["school"] as? String == "demo" && body["schoolServer"] as? String == World.untisHost)
        #expect(body["method"] == nil)
        #expect(requests[login].headers["X-Server-Key"] == "SERVER")
        // Every backend request names the watch as its own device.
        for request in requests where request.host == World.backendHost {
            #expect(request.headers["X-API-Key"] == "KEY")
            #expect(request.headers["X-Pokyh-Device"] == "watch-device-0001")
            #expect(request.headers["User-Agent"]?.hasPrefix("POKYH-iOS/") == true)
        }
        #expect(requests.first { $0.path == "/users/anna/todos" }?.headers["Authorization"] == "Bearer \(world.token)")
        // The menu as the phone asks for it, without the account.
        #expect(requests.first { $0.path == "/dishes" }?.headers["Authorization"] == nil)
        #expect(await backend.session()?.refreshToken == "R1")

        // Applied, the snapshot knows every part.
        let snapshot = load.applied(to: .empty(for: "anna", at: at(9), calendar: rome), at: at(9), calendar: rome)
        #expect(WatchSnapshot.Part.allCases.allSatisfy { snapshot.knows($0) })
        #expect(snapshot.todaysLessons(at: at(9), calendar: rome).count == 4)
        #expect(snapshot.source == .watch)
    }

    @Test func theNextLoadUsesTheSessionItHas() async {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend()
        _ = await loader(backend).load([.todos], for: account(), studentId: nil, now: at(9), calendar: rome)
        FakeServer.reset { [world] in try world.answer($0) }
        let load = await loader(backend).load([.todos, .mensa], for: account(), studentId: nil, now: at(9), calendar: rome)
        #expect(load.todos?.count == 1)
        // No school sign-in, no backend sign-in: just the reads.
        #expect(!FakeServer.requests.contains { $0.host == World.untisHost || $0.path == "/auth/login" || $0.path == "/auth/refresh" })
    }

    @Test func anExpiredTokenIsRefreshedOnceForEveryone() async throws {
        var world = World()
        world.token = jwt(expires: Date().addingTimeInterval(-10))
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend()
        try await backend.signIn(account(), untisSessionId: "S1")
        FakeServer.reset { [world] in try world.answer($0) }
        async let first = backend.storedToken(for: account())
        async let second = backend.storedToken(for: account())
        let tokens = try await [first, second]
        #expect(tokens == [world.refreshed, world.refreshed])
        #expect(FakeServer.requests.filter { $0.path == "/auth/refresh" }.count == 1)
        #expect(FakeServer.requests.first?.body["refreshToken"] as? String == "R1")
        // The rotated refresh token is the one kept.
        #expect(await backend.session()?.refreshToken == "R2")
    }

    @Test func aDeadRefreshTokenMeansSigningInAgain() async throws {
        var world = World()
        world.token = jwt(expires: Date().addingTimeInterval(-10))
        world.refreshStatus = 401
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend()
        try await backend.signIn(account(), untisSessionId: "S1")
        #expect(try await backend.storedToken(for: account()) == nil)
        #expect(await backend.session()?.refreshToken == nil)
        // A server that's down keeps the tokens for later.
        world.refreshStatus = 503
        FakeServer.reset { [world] in try world.answer($0) }
        try await backend.signIn(account(), untisSessionId: "S1")
        await #expect(throws: WatchBackendError.unavailable) { try await backend.storedToken(for: account()) }
        #expect(await backend.session()?.refreshToken == "R1")
    }

    @Test func aTokenTheBackendTurnsDownIsRenewedAndTheReadTriedAgain() async throws {
        var world = World()
        world.todosFirstStatus = 401
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend()
        try await backend.signIn(account(), untisSessionId: "S1")
        let todos = try await backend.todos(for: account())
        #expect(todos.map(\.id) == ["t1"])
        #expect(FakeServer.requests.map(\.path).suffix(3) == ["/users/anna/todos", "/auth/refresh", "/users/anna/todos"])
    }

    @Test func ticksGoStraightToTheBackend() async throws {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend()
        try await backend.signIn(account(), untisSessionId: "S1")
        try await backend.setTodo(TodoToggle(id: "t1", done: true, at: at(9)), for: account())
        let patch = try #require(FakeServer.requests.last)
        #expect(patch.method == "PATCH" && patch.path == "/users/anna/todos/t1")
        #expect(patch.body["done"] as? Bool == true)
        #expect(patch.body["doneAt"] as? String == ISO8601DateFormatter().string(from: at(9)))
        // A to-do that's gone is a no from the backend, not something to try again.
        await #expect(throws: WatchBackendError.rejected(404)) {
            try await backend.setTodo(TodoToggle(id: "gone", done: true), for: self.account())
        }
        // Unticking sends null, as the web does.
        try await backend.setTodo(TodoToggle(id: "t1", done: false), for: account())
        #expect(FakeServer.requests.last?.body["doneAt"] is NSNull)
    }

    @Test func signedOutFromTheDeviceListStaysOut() async throws {
        var world = World()
        world.loginStatus = 401
        world.loginCode = "session_revoked"
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend()
        let load = await loader(backend).load(all, for: account(), studentId: nil, now: at(9), calendar: rome)
        #expect(load.revoked)
        #expect(load.todos == nil)
        // WebUntis still answered: the watch is online, just signed out of POKYH.
        #expect(load.lessons != nil && load.reachedNetwork)
        #expect(backend.revokedAt(of: "anna") != nil)
        #expect(backend.revokedAt(of: "Anna ") != nil)
        #expect(try await backend.storedToken(for: account()) == nil)

        // Connected again on the phone: a real sign-in, which the backend lets through.
        world.loginStatus = 200
        FakeServer.reset { [world] in try world.answer($0) }
        try await backend.signIn(account(), untisSessionId: "S2")
        #expect(FakeServer.requests.last?.body["renewal"] as? Bool == false)
        #expect(backend.revokedAt(of: "anna") == nil)
        // And renewals after that.
        try await backend.signIn(account(), untisSessionId: "S3")
        #expect(FakeServer.requests.last?.body["renewal"] as? Bool == true)
    }

    @Test func leavingTheWatchEndsItsSessionButNotTheSignOut() async throws {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend()
        try await backend.signIn(account(), untisSessionId: "S1")
        await backend.forget()
        let logout = try #require(FakeServer.requests.last)
        #expect(logout.path == "/auth/logout" && logout.body["refreshToken"] as? String == "R1")
        #expect(logout.headers["Authorization"] == "Bearer \(world.token)")
        #expect(await backend.session() == nil)

        var revoked = world
        revoked.loginStatus = 401
        revoked.loginCode = "session_revoked"
        FakeServer.reset { [revoked] in try revoked.answer($0) }
        await #expect(throws: WatchBackendError.revoked) { try await backend.signIn(self.account(), untisSessionId: "S1") }
        await backend.forget()
        #expect(backend.revokedAt(of: "anna") != nil)
    }

    @Test func guardiansAppKeysAndTheBuildsOwnSchool() async throws {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let backend = backend(defaultSchool: School(loginName: "demo", server: World.untisHost))
        try await backend.signIn(account(.parent, secret: AppKey.prefix + "JBSWY3DPEHPK3PXP"), untisSessionId: "S1")
        let body = FakeServer.requests.last?.body ?? [:]
        #expect(body["role"] as? String == "parent")
        #expect(body["method"] as? String == "office")
        // The backend's default school goes without naming it, as the phone does it.
        #expect(body["school"] == nil && body["schoolServer"] == nil)
    }

    @Test func aGuardianLoadsTheChild() async {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let load = await loader(backend()).load([.lessons, .grades], for: account(.parent), studentId: 4711, now: at(9), calendar: rome)
        #expect(load.lessons?.studentId == 4711)
        let requests = FakeServer.requests
        #expect(requests.first { $0.path.hasSuffix("/timetable/entries") }?.query["resources"] == "4711")
        #expect(requests.filter { $0.path.hasSuffix("/grading/lesson") }.allSatisfy { $0.query["studentId"] == "4711" })
        #expect(requests.first { $0.path.hasSuffix("/grading/list") }?.query["schoolyearId"] == "12")
    }

    @Test func teachersHaveNoPOKYHAccount() async {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let load = await loader(backend()).load(all, for: account(.untisOnly), studentId: nil, now: at(9), calendar: rome)
        #expect(load.lessons != nil && load.menu != nil && load.todos == nil)
        #expect(!FakeServer.requests.contains { $0.path.hasPrefix("/auth") || $0.path.hasPrefix("/users") })
    }

    @Test func pokyhOnlyAccountsNeverAskWebUntis() async throws {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let load = await loader(backend()).load(all, for: account(.password), studentId: nil, now: at(9), calendar: rome)
        #expect(load.todos?.count == 1 && load.lessons == nil && load.grades == nil)
        #expect(!FakeServer.requests.contains { $0.host == World.untisHost })
        let login = try #require(FakeServer.requests.first { $0.path == "/auth/login" })
        #expect(login.headers["X-Server-Key"] == nil)
        #expect(login.body["username"] as? String == "anna" && login.body["password"] as? String == "geheim")
    }

    @Test func noConnectionAtAll() async {
        FakeServer.reset { _ in throw URLError(.notConnectedToInternet) }
        let backend = backend()
        let load = await loader(backend).load(all, for: account(), studentId: nil, now: at(9), calendar: rome)
        #expect(load.isEmpty && !load.reachedNetwork && !load.revoked)
        // Nothing is lost by it.
        #expect(backend.revokedAt(of: "anna") == nil)
    }

    @Test func aSchoolThatSaysNoIsStillAConnection() async {
        var world = World()
        world.loginStatus = 500
        FakeServer.reset { [world] request in
            if request.rpc == "authenticate" { return .init(body: #"{"error":{"code":-8504,"message":"bad credentials"}}"#) }
            return try world.answer(request)
        }
        let load = await loader(backend()).load(all, for: account(), studentId: nil, now: at(9), calendar: rome)
        #expect(load.reachedNetwork)
        #expect(load.lessons == nil && load.grades == nil && load.todos == nil)
        // The menu needs no account.
        #expect(load.menu?.dishes.count == 2)
    }

    @Test func oneSubjectFailingLeavesTheOthers() async {
        let world = World()
        FakeServer.reset { [world] in try world.answer($0) }
        let load = await loader(backend()).load([.grades], for: account(.untisOnly), studentId: nil, now: at(9), calendar: rome)
        // GEO answers with an error page; MAT and DEU still count.
        #expect(load.grades?.count == 3)
        #expect(FakeServer.requests.filter { $0.path.hasSuffix("/grading/lesson") }.count == 3)
    }
}
