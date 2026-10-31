import Foundation
import Testing
@testable import PokyhCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Rome")!
    return c
}()

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 30) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func lesson(_ subject: String, _ from: (Int, Int), _ to: (Int, Int), status: WatchSnapshot.Lesson.Status = .regular, room: String = "R1") -> WatchSnapshot.Lesson {
    WatchSnapshot.Lesson(id: subject + "\(from.0)", subject: subject, teacher: "T", room: room,
                         start: at(from.0, from.1), end: at(to.0, to.1), status: status)
}

private let day = WatchSnapshot(
    username: "anna",
    updatedAt: at(7, 30),
    day: calendar.startOfDay(for: at(8)),
    lessons: [
        lesson("MAT", (8, 0), (8, 50)),
        lesson("DEU", (8, 50), (9, 40), status: .cancelled),
        lesson("ENG", (9, 40), (10, 30), room: "R7"),
    ],
    overallAverage: 7.5,
    gradeCount: 4,
    todos: [
        WatchSnapshot.Todo(id: "a", title: "Hausaufgabe"),
        WatchSnapshot.Todo(id: "b", title: "Referat", done: true),
    ]
)

struct WatchSnapshotTests {
    @Test func theLoudestStatusWins() {
        typealias S = WatchSnapshot.Lesson.Status
        #expect(S.of(cancelled: true, exam: true, substitution: true, additional: false, room: "1", originalRoom: "2") == .cancelled)
        #expect(S.of(cancelled: false, exam: true, substitution: true, additional: false, room: "1", originalRoom: nil) == .exam)
        #expect(S.of(cancelled: false, exam: false, substitution: true, additional: false, room: "1", originalRoom: "2") == .substitution)
        #expect(S.of(cancelled: false, exam: false, substitution: false, additional: true, room: "1", originalRoom: "2") == .roomChange)
        // The same room listed as removed and current isn't a change.
        #expect(S.of(cancelled: false, exam: false, substitution: false, additional: false, room: "1", originalRoom: "1") == .regular)
        #expect(S.of(cancelled: false, exam: false, substitution: false, additional: true, room: "1", originalRoom: "") == .additional)
    }

    @Test func nowAndNextSkipCancelledLessons() {
        #expect(day.current(at: at(8, 10), calendar: calendar)?.subject == "MAT")
        #expect(day.next(after: at(8, 10), calendar: calendar)?.subject == "ENG")
        // DEU is cancelled: between the two there's nothing running.
        #expect(day.current(at: at(9, 0), calendar: calendar) == nil)
        #expect(day.upcoming(at: at(9, 0), calendar: calendar)?.subject == "ENG")
        #expect(day.upcoming(at: at(7), calendar: calendar)?.subject == "MAT")
        #expect(day.upcoming(at: at(11), calendar: calendar) == nil)
    }

    @Test func theDayIsOverAfterTheLastLesson() {
        #expect(!day.dayIsOver(at: at(10), calendar: calendar))
        #expect(day.dayIsOver(at: at(10, 30), calendar: calendar))
        #expect(!WatchSnapshot.empty(for: "anna", at: at(12), calendar: calendar).dayIsOver(at: at(12), calendar: calendar))
    }

    @Test func yesterdaysSnapshotHasNoLessonsToday() {
        let tomorrow = at(8, day: 31)
        #expect(day.todaysLessons(at: tomorrow, calendar: calendar).isEmpty)
        #expect(day.upcoming(at: tomorrow, calendar: calendar) == nil)
        #expect(day.isStale(at: tomorrow, calendar: calendar))
    }

    @Test func staleAfterHalfAnHour() {
        #expect(!day.isStale(at: at(7, 50), calendar: calendar))
        #expect(day.isStale(at: at(8, 1), calendar: calendar))
    }

    @Test func complicationsChangeAtEveryEdge() {
        let dates = day.timelineDates(from: at(8, 10), calendar: calendar)
        #expect(dates == [at(8, 10), at(8, 50), at(9, 40), at(10, 30), at(0, day: 31)])
    }

    @Test func aDayItHasNoLessonsForIsNotAFreeDay() {
        #expect(day.knowsToday(at: at(8), calendar: calendar))
        #expect(!day.knowsToday(at: at(8, day: 31), calendar: calendar))
        // Only the to-dos have come so far: no lessons doesn't mean a free day.
        #expect(!WatchSnapshot.empty(for: "anna", at: at(8), calendar: calendar).knowsToday(at: at(8), calendar: calendar))
    }

    @Test func looksAgainThroughTheSchoolDayThenInTheMorning() {
        #expect(WatchSnapshot.nextRefresh(after: at(3), calendar: calendar) == at(6))
        #expect(WatchSnapshot.nextRefresh(after: at(9), calendar: calendar) == at(11))
        #expect(WatchSnapshot.nextRefresh(after: at(16), calendar: calendar) == at(18))
        #expect(WatchSnapshot.nextRefresh(after: at(17), calendar: calendar) == at(6, day: 31))
        #expect(WatchSnapshot.nextRefresh(after: at(23), calendar: calendar) == at(6, day: 31))
    }

    @Test func anOlderSnapshotArrivingLateIsDropped() {
        var older = day
        older.updatedAt = at(7)
        #expect(day.taking(older) == nil)
        var newer = day
        newer.updatedAt = at(8)
        #expect(day.taking(newer) == newer)
    }

    @Test func theWatchsOwnFresherLessonsSurviveAPhoneUpdate() {
        let own = day.withLessons([lesson("BIO", (11, 0), (11, 50))], day: day.day, studentId: nil, at: at(10))
        var phone = day
        phone.updatedAt = at(10, 5)
        phone.todos = []
        let merged = own.taking(phone)
        #expect(merged?.lessons.map(\.subject) == ["BIO"])
        #expect(merged?.source == .watch)
        #expect(merged?.lessonsUpdatedAt == at(10))
        #expect(merged?.todos.isEmpty == true)
        #expect(merged?.updatedAt == at(10, 5))

        // Once the phone has loaded them later still, its lessons count again.
        phone.lessonsUpdatedAt = at(10, 5)
        #expect(own.taking(phone)?.lessons.map(\.subject) == ["MAT", "DEU", "ENG"])
    }

    @Test func lessonProgress() {
        let math = day.lessons[0]
        #expect(math.progress(at: at(7)) == 0)
        #expect(abs(math.progress(at: at(8, 25)) - 0.5) < 0.001)
        #expect(math.progress(at: at(9)) == 1)
    }

    @Test func lessonsLoadedOnTheWatchKeepTheRest() {
        let fresh = day.withLessons([lesson("BIO", (11, 0), (11, 50))], day: day.day, studentId: 42, at: at(10))
        #expect(fresh.lessons.map(\.subject) == ["BIO"])
        #expect(fresh.source == .watch)
        #expect(fresh.lessonsUpdatedAt == at(10))
        #expect(fresh.updatedAt == day.updatedAt)
        #expect(fresh.overallAverage == 7.5)
        #expect(fresh.studentId == 42)
    }

    @Test func goesThroughWatchConnectivityPayloads() {
        let payload = day.payload
        #expect(WatchSnapshot(payload: payload) == day)
        #expect(WatchSnapshot(payload: [:]) == nil)
        #expect(WatchSnapshot(payload: ["pokyh.snapshot": Data("nope".utf8)]) == nil)
    }

    @Test func sharesTheContextWithTheAccountHandoff() {
        let account = StoredAccount(username: "anna", displayName: "Anna", school: School(loginName: "s", server: "s.webuntis.com"), secret: "pw")
        let context = AccountHandoff(account: account).payload.merging(day.payload) { $1 }
        #expect(AccountHandoff(payload: context)?.account == account)
        #expect(WatchSnapshot(payload: context)?.username == "anna")
    }

    @Test func dishDiet() {
        #expect(WatchSnapshot.Dish(id: "1", name: "Curry", category: "", tags: ["Vegan"]).diet == .vegan)
        #expect(WatchSnapshot.Dish(id: "2", name: "Pasta", category: "", tags: ["vegetarisch", "vegan"]).diet == .vegan)
        #expect(WatchSnapshot.Dish(id: "3", name: "Risotto", category: "", tags: ["vegetarian"]).diet == .vegetarian)
        #expect(WatchSnapshot.Dish(id: "4", name: "Schnitzel", category: "").diet == nil)
    }
}

struct WatchFormatTests {
    let texts = WatchTexts.of(.de)
    let common = Strings.of(.de).common

    @Test func clockIsTwentyFourHours() {
        #expect(WatchFormat.clock(at(8, 5), calendar: calendar) == "08:05")
        #expect(WatchFormat.clock(at(14), calendar: calendar) == "14:00")
    }

    @Test func marksLoseTheirZeros() {
        #expect(WatchFormat.mark(8, decimal: ",") == "8")
        #expect(WatchFormat.mark(8.5, decimal: ",") == "8,5")
        #expect(WatchFormat.mark(7.25, decimal: ".") == "7.25")
        #expect(WatchFormat.average(7.5, decimal: ",") == "7,50")
    }

    @Test func stampsSayHowOld() {
        #expect(WatchFormat.stamp(at(10, 42), now: at(11), texts: texts, common: common, calendar: calendar) == "Stand 10:42")
        #expect(WatchFormat.stamp(at(18, 3, day: 29), now: at(11), texts: texts, common: common, calendar: calendar) == "Stand gestern, 18:03")
        #expect(WatchFormat.stamp(at(9, day: 20), now: at(11), texts: texts, common: common, calendar: calendar).hasPrefix("Stand 20"))
    }

    @Test func everyLanguageHasTheTexts() {
        for lang in Lang.allCases {
            let t = WatchTexts.of(lang)
            #expect(!t.queued.isEmpty && !t.noDataTitle.isEmpty && !t.free.isEmpty)
            #expect(t.updated("10:42").contains("10:42"))
        }
        #expect(WatchTexts.of(.it).free != WatchTexts.of(.en).free)
    }
}

struct TodoQueueTests {
    @Test func tickingBackCancelsTheTick() {
        var queue = TodoQueue()
        queue.toggle("a", to: true, phoneSays: false)
        #expect(queue.pending(for: "a")?.done == true)
        queue.toggle("a", to: false, phoneSays: false)
        #expect(queue.isEmpty)
    }

    @Test func oneTickPerTodo() {
        var queue = TodoQueue()
        queue.toggle("a", to: true, phoneSays: false)
        queue.toggle("b", to: false, phoneSays: true)
        queue.toggle("a", to: true, phoneSays: false)
        #expect(queue.items.map(\.id) == ["b", "a"])
    }

    @Test func pendingTicksShowOnTop() {
        var queue = TodoQueue()
        queue.toggle("a", to: true, phoneSays: false)
        queue.toggle("b", to: false, phoneSays: true)
        let shown = day.applying(queue)
        #expect(shown.todos.map(\.done) == [true, false])
        #expect(shown.openTodos.map(\.id) == ["b"])
    }

    @Test func aSnapshotSettlesWhatItShows() {
        var queue = TodoQueue()
        queue.toggle("a", to: true, phoneSays: false)   // not on the phone yet
        queue.toggle("b", to: true, phoneSays: false)   // the phone has it already
        queue.toggle("gone", to: true, phoneSays: false)
        queue.settle(with: day)
        #expect(queue.items.map(\.id) == ["a"])
    }

    @Test func togglesAndRepliesRoundTrip() {
        let toggle = TodoToggle(id: "a", done: true, at: at(9))
        #expect(TodoToggle(payload: toggle.payload) == toggle)
        #expect(TodoToggle(payload: WatchRequest.snapshot) == nil)
        #expect(toggle.doneAt?.hasPrefix("2026-10-30T") == true)
        #expect(TodoToggle(id: "a", done: false).doneAt == nil)

        let reply = TodoToggleResult.applied.reply(with: day)
        #expect(TodoToggleResult(reply: reply) == .applied)
        #expect(WatchSnapshot(payload: reply) == day)
        #expect(TodoToggleResult(reply: TodoToggleResult.later.reply(with: nil)) == .later)
        #expect(TodoToggleResult(reply: [:]) == nil)
    }

    @Test func snapshotRequests() {
        #expect(WatchRequest.isSnapshotRequest(WatchRequest.snapshot))
        #expect(!WatchRequest.isSnapshotRequest(AccountHandoff.request))
    }
}

struct WatchStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString)", isDirectory: true)
    let vault = try! Vault(keyData: Vault.makeKeyData())

    var store: WatchStore {
        let vault = vault
        return WatchStore(files: SealedFiles(directory: dir, protection: .untilFirstUnlock) { vault })
    }

    @Test func keepsTheSnapshotSealed() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.snapshot() == nil)
        #expect(store.save(day))
        #expect(store.snapshot() == day)
        // Nothing readable on disk: no user name, no subject.
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            #expect(Vault.isSealed(bytes))
            #expect(bytes.range(of: Data("anna".utf8)) == nil)
            #expect(bytes.range(of: Data("MAT".utf8)) == nil)
        }
    }

    @Test func keepsTheQueue() {
        defer { try? FileManager.default.removeItem(at: dir) }
        var queue = TodoQueue()
        queue.toggle("a", to: true, phoneSays: false)
        store.save(queue)
        #expect(store.queue() == queue)
        store.save(TodoQueue())
        #expect(store.queue().isEmpty)
    }

    @Test func clearingForgetsEverything() {
        defer { try? FileManager.default.removeItem(at: dir) }
        store.save(day)
        var queue = TodoQueue()
        queue.toggle("a", to: true, phoneSays: false)
        store.save(queue)
        store.clear()
        #expect(store.snapshot() == nil)
        #expect(store.queue().isEmpty)
    }

    @Test func anotherKeyReadsNothing() {
        defer { try? FileManager.default.removeItem(at: dir) }
        store.save(day)
        let other = try! Vault(keyData: Vault.makeKeyData())
        let foreign = WatchStore(files: SealedFiles(directory: dir, protection: .untilFirstUnlock, dropsUnreadable: false) { other })
        #expect(foreign.snapshot() == nil)
        #expect(store.snapshot() == day)
    }
}

struct UntisDayTests {
    static let answer = #"""
    {"days":[{"date":"2026-10-30","gridEntries":[
      {"ids":[101],"duration":{"start":"2026-10-30T08:00","end":"2026-10-30T08:50"},"type":"NORMAL_TEACHING_PERIOD","status":"REGULAR",
       "position1":[{"current":{"type":"TEACHER","shortName":"MUE","displayName":"Müller"}}],
       "position2":[{"current":{"type":"SUBJECT","shortName":"MAT","longName":"Mathematik","displayName":"MAT"}}],
       "position3":[{"current":{"type":"ROOM","shortName":"R1","displayName":"R1"}}],"lessonInfo":""},
      {"ids":[102],"duration":{"start":"2026-10-30T08:50","end":"2026-10-30T09:40"},"type":"NORMAL_TEACHING_PERIOD","status":"CHANGED",
       "position1":[{"current":{"displayName":"Rossi"},"removed":{"displayName":"Huber"}}],
       "position2":[{"current":{"shortName":"DEU","longName":"Deutsch"}}],
       "position3":[{"current":{"displayName":"R2"}}]},
      {"ids":[103],"duration":{"start":"2026-10-30T09:40","end":"2026-10-30T10:30"},"type":"NORMAL_TEACHING_PERIOD","status":"CHANGED",
       "position1":[{"current":{"displayName":"Kofler"}}],
       "position2":[{"current":{"shortName":"ENG","longName":"Englisch"}}],
       "position3":[{"current":{"displayName":"R9"},"removed":{"displayName":"R3"}}]},
      {"ids":[104],"duration":{"start":"2026-10-30T10:45","end":"2026-10-30T11:35"},"type":"EXAM","status":"CANCELLED",
       "position1":[],"position2":[{"removed":{"shortName":"BIO","longName":"Biologie"}}],"position3":null,
       "lessonText":"Fällt aus"},
      {"ids":"not-a-list","duration":{"start":"bad"},"position2":[]}
    ]}]}
    """#

    @Test func readsLessonsLikeThePhone() throws {
        let lessons = try UntisDay.parse(Data(Self.answer.utf8), calendar: calendar)
        #expect(lessons.map(\.subject) == ["MAT", "DEU", "ENG", "BIO"])
        #expect(lessons[0].title == "Mathematik")
        #expect(lessons[0].teacher == "Müller")
        #expect(lessons[0].room == "R1")
        #expect(lessons[0].status == .regular)
        #expect(lessons[0].note == nil)
        #expect(lessons[0].start == at(8))
        #expect(lessons[0].end == at(8, 50))
        #expect(lessons[1].status == .substitution)
        #expect(lessons[1].originalTeacher == "Huber")
        #expect(lessons[2].status == .roomChange)
        #expect(lessons[2].originalRoom == "R3")
        #expect(lessons[3].status == .cancelled)
        #expect(lessons[3].room == "")
        #expect(lessons[3].note == "Fällt aus")
    }

    @Test func anEmptyDayIsNoError() throws {
        #expect(try UntisDay.parse(Data(#"{"days":[]}"#.utf8)).isEmpty)
        #expect(try UntisDay.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func schoolTimesAreLocal() {
        #expect(UntisDay.localDate("2026-10-30T13:05", calendar: calendar) == at(13, 5))
        #expect(UntisDay.localDate("2026-10-30T13:05:00+01:00", calendar: calendar) == at(13, 5))
        #expect(UntisDay.localDate("13:05", calendar: calendar) == nil)
        #expect(UntisDay.isoDay(at(23, 30), calendar: calendar) == "2026-10-30")
    }

    @Test func schoolNamesInCookieAndQuery() {
        let school = School(loginName: "IIS Galilei & Co", server: "x.webuntis.com")
        #expect(UntisDay.query(school) == "IIS%20Galilei%20%26%20Co")
        #expect(UntisDay.cookie("abc", school: school) == "JSESSIONID=abc; schoolname=\"_\(Data("IIS Galilei & Co".utf8).base64EncodedString())\"")
        #expect(UntisDay.base(school) == "https://x.webuntis.com/WebUntis")
    }
}

/// A stand-in for WebUntis: answers from a table and remembers what it was asked.
private final class FakeUntis: URLProtocol, @unchecked Sendable {
    struct Answer {
        var status = 200
        var headers: [String: String] = [:]
        var body = ""
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: Answer] = [:]
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func reset(_ table: [String: Answer]) {
        lock.withLock {
            answers = table
            seen = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // URLSession hands the body over as a stream; keep it readable for the checks.
        var kept = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            kept.httpBody = data
        }
        let path = request.url?.path ?? ""
        let answer = Self.lock.withLock {
            Self.seen.append(kept)
            return Self.answers.first { path.hasSuffix($0.key) }?.value ?? Answer(status: 404)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct UntisDaySignInTests {
    let school = School(loginName: "lbs test", server: "demo.invalid")

    var untis: UntisDay {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeUntis.self]
        return UntisDay(session: URLSession(configuration: config))
    }

    private func account(secret: String) -> StoredAccount {
        StoredAccount(username: " Anna ", displayName: "Anna", school: school, secret: secret)
    }

    private static let signedIn = FakeUntis.Answer(
        headers: ["Set-Cookie": "JSESSIONID=SESSION1; Path=/WebUntis; HttpOnly"],
        body: #"{"result":{"sessionId":"BODY","personId":77,"personType":5}}"#
    )
    private static let token = FakeUntis.Answer(body: "aaa.bbb.ccc")
    private static let day = FakeUntis.Answer(body: UntisDayTests.answer)

    private func body(of request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
    }

    @Test func signsInLoadsTheDayAndSignsOut() async throws {
        FakeUntis.reset(["/jsonrpc.do": Self.signedIn, "/api/token/new": Self.token, "/timetable/entries": Self.day])
        let result = try await untis.lessons(for: account(secret: "secret"), studentId: nil, on: at(8), calendar: calendar)
        #expect(result.studentId == 77)
        #expect(result.lessons.map(\.subject) == ["MAT", "DEU", "ENG", "BIO"])

        let requests = FakeUntis.requests
        #expect(requests.count == 4)
        let params = body(of: requests[0])["params"] as? [String: Any]
        #expect(body(of: requests[0])["method"] as? String == "authenticate")
        #expect(params?["user"] as? String == "anna")
        #expect(params?["password"] as? String == "secret")
        #expect(params?["client"] as? String == UntisDay.clientName)
        #expect(requests[0].url?.query?.contains("school=lbs%20test") == true)

        let timetable = requests[2]
        let query = timetable.url?.query ?? ""
        #expect(query.contains("start=2026-10-30") && query.contains("end=2026-10-30") && query.contains("resources=77"))
        #expect(timetable.value(forHTTPHeaderField: "Authorization") == "Bearer aaa.bbb.ccc")
        #expect(timetable.value(forHTTPHeaderField: "Cookie")?.hasPrefix("JSESSIONID=SESSION1;") == true)

        #expect(body(of: requests[3])["method"] as? String == "logout")
    }

    @Test func loadsTheChildThePhoneLoadsForAParent() async throws {
        FakeUntis.reset(["/jsonrpc.do": Self.signedIn, "/api/token/new": Self.token, "/timetable/entries": Self.day])
        let result = try await untis.lessons(for: account(secret: "secret"), studentId: 4711, on: at(8), calendar: calendar)
        #expect(result.studentId == 4711)
        #expect(FakeUntis.requests[2].url?.query?.contains("resources=4711") == true)
    }

    @Test func anAppKeySendsTheOneTimeCodeNotThePassword() async throws {
        let answer = FakeUntis.Answer(
            headers: ["Set-Cookie": "JSESSIONID=KEY1; Path=/"],
            body: #"{"result":{"userData":{"elemId":55,"elemType":"STUDENT"}}}"#
        )
        FakeUntis.reset(["/jsonrpc_intern.do": answer, "/jsonrpc.do": .init(body: "{}"), "/api/token/new": Self.token, "/timetable/entries": Self.day])
        let result = try await untis.lessons(for: account(secret: AppKey.prefix + "JBSWY3DPEHPK3PXP"), studentId: nil, on: at(8), calendar: calendar)
        #expect(result.studentId == 55)

        let first = FakeUntis.requests[0]
        #expect(first.url?.path.hasSuffix("/jsonrpc_intern.do") == true)
        let text = String(decoding: first.httpBody ?? Data(), as: UTF8.self)
        #expect(text.contains("otp"))
        #expect(!text.contains("JBSWY3DPEHPK3PXP"))
    }

    @Test func wrongCredentialsSayWhy() async {
        FakeUntis.reset(["/jsonrpc.do": .init(body: #"{"error":{"code":-8504,"message":"bad credentials"}}"#)])
        await #expect(throws: UntisDayError.signInFailed("bad credentials")) {
            try await untis.lessons(for: account(secret: "wrong"), studentId: nil, on: at(8), calendar: calendar)
        }
        // Nothing else is asked of the school after that.
        #expect(FakeUntis.requests.count == 1)
    }

    @Test func aLoginPageInsteadOfJSONIsAnErrorAndStillSignsOut() async {
        FakeUntis.reset(["/jsonrpc.do": Self.signedIn, "/api/token/new": Self.token, "/timetable/entries": .init(body: "<html>")])
        await #expect(throws: UntisDayError.badAnswer(200)) {
            try await untis.lessons(for: account(secret: "secret"), studentId: nil, on: at(8), calendar: calendar)
        }
        #expect(body(of: FakeUntis.requests.last!)["method"] as? String == "logout")
    }

    @Test func noPersonNoTimetable() async {
        let answer = FakeUntis.Answer(
            headers: ["Set-Cookie": "JSESSIONID=KEY1; Path=/"],
            body: #"{"result":{"userData":{"elemId":0}}}"#
        )
        FakeUntis.reset(["/jsonrpc_intern.do": answer, "/jsonrpc.do": .init(body: "{}"), "/api/token/new": Self.token])
        await #expect(throws: UntisDayError.noPerson) {
            try await untis.lessons(for: account(secret: AppKey.prefix + "JBSWY3DPEHPK3PXP"), studentId: nil, on: at(8), calendar: calendar)
        }
        #expect(!FakeUntis.requests.contains { $0.url?.path.hasSuffix("/timetable/entries") == true })
    }
}
