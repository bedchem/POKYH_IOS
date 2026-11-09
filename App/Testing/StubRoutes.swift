#if DEBUG
import Foundation

/// The good answers, same shapes as the real servers (UntisClient, BackendClient and the package's
/// test fixtures). Dates follow today, so the screens have something to show on any day.
nonisolated enum StubRoutes {
    // ── Accounts ─────────────────────────────────────────────────────────────
    // anna: student. eltern: parent of Anna. nurpokyh: no WebUntis account. zweifa: authenticator
    // code 123456. Any other password than "falsch" is right.

    private static let studentId = 501
    private static let parentId = 900
    private static let klasseId = 11
    private static let classId = "class-1"

    private static func username(_ headers: [String: String]) -> String {
        let cookie = headers["Cookie"] ?? ""
        return cookie.range(of: "JSESSIONID=stub-").flatMap { range in
            cookie[range.upperBound...].split(separator: ";").first.map(String.init)
        } ?? "anna"
    }

    private static func cookie(_ user: String) -> [String: String] {
        ["Set-Cookie": "JSESSIONID=stub-\(user); Path=/WebUntis; HttpOnly"]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var todos: [[String: Any]] = seedTodos()
    nonisolated(unsafe) private static var reminders: [[String: Any]] = seedReminders()
    nonisolated(unsafe) private static var comments: [[String: Any]] = seedComments()
    nonisolated(unsafe) private static var counter = 100

    private static func nextId(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }

    // ── Dates ────────────────────────────────────────────────────────────────

    private static let isoDay: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let isoFull: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func day(_ offset: Int, from date: Date = Date()) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: date) ?? date
    }
    private static func dayString(_ offset: Int) -> String { isoDay.string(from: day(offset)) }
    private static func dayNum(_ offset: Int) -> Int { Int(dayString(offset).replacingOccurrences(of: "-", with: "")) ?? 0 }
    private static func stamp(_ offsetDays: Int) -> String { isoFull.string(from: day(offsetDays)) }

    private static var schoolYearStart: Int {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
        return (c.month ?? 1) >= 9 ? (c.year ?? 2026) : (c.year ?? 2026) - 1
    }

    // ── Dispatch ─────────────────────────────────────────────────────────────

    static func answer(url: URL, method: String, headers: [String: String], body: Data) -> StubAnswer {
        var path = url.path
        if path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.contains("/img/") { return image }
        let query = Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? []) { a, _ in a }
        if path.hasPrefix("/WebUntis") {
            path.removeFirst("/WebUntis".count)
            return untis(path, url: url, method: method, query: query, headers: headers, body: body)
        }
        if let answer = engagement(path, method: method, query: query, headers: headers, body: body) { return answer }
        return backend(path, method: method, query: query, body: body)
    }

    private static let image: StubAnswer = {
        // One white pixel.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==") ?? Data()
        return StubAnswer(raw: png, type: "image/png")
    }()

    private static func object(_ body: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    // ── WebUntis ─────────────────────────────────────────────────────────────

    private static func untis(_ path: String, url: URL, method: String, query: [String: String], headers: [String: String], body: Data) -> StubAnswer {
        let user = username(headers)
        let isParent = user == "eltern"
        switch path {
        case "/jsonrpc.do", "/jsonrpc_intern.do":
            return rpc(object(body), user: user)
        case "/", "":
            let html = "<html><script>var config = {\"csrfToken\":\"stub-csrf\",\"tenantId\":\"1234\"};</script></html>"
            return StubAnswer(raw: Data(html.utf8), type: "text/html", isAuth: true, headers: ["Set-Cookie": "JSESSIONID=stub-anonymous; Path=/"])
        case "/j_spring_security_check":
            return form(body)
        case "/api/token/new":
            return StubAnswer(raw: Data("eyJhbGciOiJub25lIn0.eyJ0ZW5hbnRfaWQiOiIxMjM0In0.c3R1Yg".utf8), type: "text/plain", isAuth: true)
        case "/api/rest/view/v1/app/data":
            return StubAnswer(json: appData(isParent: isParent), isAuth: true)
        case "/api/app/data", "/api/rest/view/v1/users/me/data", "/api/rest/view/v2/app/data":
            return StubAnswer(json: ["error": "nope"], status: 404, isAuth: true)
        case "/api/rest/view/v1/timetable/entries":
            return StubAnswer(json: timetable(start: query["start"]))
        case "/api/rest/view/v1/timetable/filter":
            return StubAnswer(json: timetableFilter)
        case "/api/rest/view/v2/calendar-entry/detail":
            return StubAnswer(json: lessonDetail)
        case "/api/classreg/grade/grading/list":
            return StubAnswer(json: ["data": ["lessons": gradeLessons]])
        case "/api/classreg/grade/grading/lesson":
            return StubAnswer(json: ["data": ["grades": grades(lesson: Int(query["lessonId"] ?? "") ?? 0)]])
        case "/api/classreg/absences/students":
            return StubAnswer(json: ["data": ["absences": absences, "absenceReasons": absenceReasons, "showCreateAbsence": true, "totalCount": absences.count] as [String: Any]])
        case "/api/classreg/absences/meta":
            return StubAnswer(json: ["data": ["absenceReasons": absenceReasons, "defaultAbsenceReason": ["id": 1], "defaultDate": dayNum(0), "defaultStartTime": 750, "defaultEndTime": 1600] as [String: Any]])
        case "/api/classreg/absences/students/self", "/api/classreg/absences/students/edit":
            return StubAnswer(json: ["data": ["conflicts": [Any]()]])
        case "/api/classreg/absences/student":
            return StubAnswer(json: ["data": ["absence": absences.first ?? [:]]])
        case "/api/classreg/absencetimes/student":
            return StubAnswer(json: ["data": ["absenceTimes": [
                ["absenceId": 1, "missedMins": 100, "subjectName": "Mathematik", "excused": true, "date": dayNum(-14)],
                ["absenceId": 2, "missedMins": 50, "subjectName": "Deutsch", "excused": false, "date": dayNum(-7)],
            ]]])
        case "/api/classreg/classregevents":
            return StubAnswer(json: ["data": ["rows": classregRows]])
        case "/api/classreg/classservices":
            return StubAnswer(json: classServices)
        case "/api/homeworks/lessons":
            return StubAnswer(json: homeworks)
        case "/passwordReset/resetPassword.do":
            return StubAnswer(json: [String: Any]())
        case "/reports.do":
            if query["msgId"] != nil { return StubAnswer(raw: Data(Self.planPDF.utf8), type: "application/pdf") }
            return StubAnswer(json: ["data": ["finished": true, "messageId": "m1", "reportParams": "name=Excuse"] as [String: Any]])
        default:
            if path.hasPrefix("/api/rest/view/v1/messages") || path.hasPrefix("/api/rest/view/v2/messages") {
                return messages(path, method: method)
            }
            if path.hasPrefix("/api/profile") {
                return StubProfile.answer(path, method: method, user: user, body: body)
            }
            StubServer.log("UNROUTED untis \(method) \(path)")
            return StubAnswer(json: [String: Any]())
        }
    }

    private static func rpc(_ request: [String: Any], user: String) -> StubAnswer {
        let method = request["method"] as? String ?? ""
        let id = request["id"] ?? "stub"
        func ok(_ result: Any, isAuth: Bool = false, headers: [String: String] = [:]) -> StubAnswer {
            StubAnswer(json: ["jsonrpc": "2.0", "id": id, "result": result], isAuth: isAuth, headers: headers)
        }
        func error(_ code: Int, _ message: String) -> StubAnswer {
            StubAnswer(json: ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]], isAuth: true)
        }
        switch method {
        case "authenticate":
            let params = request["params"] as? [String: Any] ?? [:]
            let name = (params["user"] as? String ?? "").lowercased()
            if params["password"] as? String == "falsch" || name == "nurpokyh" || StubProfile.rejects(name, password: params["password"] as? String) {
                return error(-8504, "bad credentials")
            }
            if name == "zweifa" || StubProfile.asksForCode(name) { return error(-8998, "two factor") }
            let person = name == "eltern" ? parentId : studentId
            let result: [String: Any] = ["sessionId": "stub-\(name)", "personId": person, "klasseId": name == "eltern" ? 0 : klasseId,
                                         "personType": name == "eltern" ? 12 : 5]
            return ok(result, isAuth: true, headers: cookie(name))
        case "getUserData2017":
            let data: [String: Any] = ["elemId": studentId, "elemType": "STUDENT", "klassenIds": [klasseId]]
            return ok(["userData": data], isAuth: true, headers: cookie("anna"))
        case "getKlassen":
            let rows: [[String: Any]] = [["id": klasseId, "name": "4A", "longName": "4. Klasse A"], ["id": 22, "name": "1C", "longName": "1. Klasse C"]]
            return ok(rows, isAuth: true)
        case "getStudents":
            let rows: [[String: Any]] = [["id": studentId, "foreName": "Anna", "longName": "Rossi", "klasseId": klasseId],
                                         ["id": 502, "foreName": "Luca", "longName": "Bianchi", "klasseId": klasseId]]
            return ok(rows, isAuth: true)
        case "getSchoolyears":
            let y = schoolYearStart
            let rows: [[String: Any]] = [["id": 1, "name": "\(y - 1)/\(y)", "startDate": (y - 1) * 10000 + 901, "endDate": y * 10000 + 630],
                                         ["id": 2, "name": "\(y)/\(y + 1)", "startDate": y * 10000 + 901, "endDate": (y + 1) * 10000 + 630]]
            return ok(rows, isAuth: true)
        case "getCurrentSchoolyear":
            let y = schoolYearStart
            let year: [String: Any] = ["id": 2, "name": "\(y)/\(y + 1)", "startDate": y * 10000 + 901, "endDate": (y + 1) * 10000 + 630]
            return ok(year)
        case "getHolidays":
            let rows: [[String: Any]] = [["id": 1, "name": "Herbst", "longName": "Herbstferien", "startDate": dayNum(10), "endDate": dayNum(14)],
                                         ["id": 2, "name": "Weih", "longName": "Weihnachten", "startDate": dayNum(40), "endDate": dayNum(55)]]
            return ok(rows)
        default:
            StubServer.log("UNROUTED rpc \(method)")
            return ok([Any]())
        }
    }

    /// The sign-in form: where the second factor lives.
    private static func form(_ body: Data) -> StubAnswer {
        let fields = Dictionary(String(decoding: body, as: UTF8.self).split(separator: "&").map { pair -> (String, String) in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts.first ?? "", (parts.count > 1 ? parts[1] : "").removingPercentEncoding ?? "")
        }) { a, _ in a }
        let name = (fields["j_username"] ?? "").lowercased()
        if fields["j_password"] == "falsch" || StubProfile.rejects(name, password: fields["j_password"]) { return StubAnswer(json: ["state": "LOGIN_ERROR"], isAuth: true) }
        guard name == "zweifa" || StubProfile.asksForCode(name) else { return StubAnswer(json: ["state": "SUCCESS"], isAuth: true, headers: cookie(name)) }
        guard let token = fields["token"] else { return StubAnswer(json: ["state": "TOKEN_REQUIRED"], isAuth: true) }
        if token == "123456" { return StubAnswer(json: ["state": "SUCCESS"], isAuth: true, headers: cookie(name)) }
        return StubAnswer(json: ["state": "TOKEN_REQUIRED", "invalidToken": true] as [String: Any], isAuth: true)
    }

    private static func appData(isParent: Bool) -> [String: Any] {
        let child: [String: Any] = ["id": studentId, "displayName": "Anna Rossi", "imageUrl": "/WebUntis/img/anna.png", "klasseId": klasseId]
        let person: [String: Any] = ["id": isParent ? parentId : studentId, "imageUrl": "/WebUntis/img/me.png", "displayName": isParent ? "Maria Rossi" : "Anna Rossi"]
        let students: [Any] = isParent ? [child] : []
        let user: [String: Any] = ["person": person, "students": students, "roles": [isParent ? "LEGAL_GUARDIAN" : "STUDENT"], "permissions": ["STUDABS_REPORT:RW"]]
        return ["user": user]
    }

    // ── Timetable ────────────────────────────────────────────────────────────

    private static func element(_ short: String, _ long: String, type: String) -> [String: Any] {
        ["type": type, "status": "REGULAR", "shortName": short, "longName": long, "displayName": short]
    }

    private static func timetable(start: String?) -> [String: Any] {
        let first = start.flatMap(isoDay.date(from:)) ?? day(0)
        let subjects = [("M", "Mathematik", "MUE", "Müller Hans"), ("D", "Deutsch", "BER", "Berger Eva"), ("ENGL", "Englisch", "SCH", "Schmid Anna"),
                        ("IT", "Italienisch", "ROS", "Rossi Marta"), ("R", "Religion", "VER", "Verdi Luca"), ("SPO", "Sport", "KOF", "Kofler Max")]
        let periods = [("07:50", "08:40"), ("08:40", "09:30"), ("09:45", "10:35"), ("10:35", "11:25"), ("11:25", "12:15")]
        var days: [[String: Any]] = []
        for d in 0..<6 {
            let date = isoDay.string(from: self.day(d, from: first))
            guard d < 5 else {
                days.append(["date": date, "status": "NO_DATA", "gridEntries": [Any]()])
                continue
            }
            var entries: [[String: Any]] = []
            for (p, period) in periods.enumerated() {
                let subject = subjects[(d + p) % subjects.count]
                var entry: [String: Any] = [
                    "ids": [1000 + d * 10 + p],
                    "duration": ["start": "\(date)T\(period.0)", "end": "\(date)T\(period.1)"],
                    "type": "NORMAL_TEACHING_PERIOD",
                    "status": "REGULAR",
                    "position1": [["current": element(subject.2, subject.3, type: "TEACHER"), "removed": NSNull()] as [String: Any]],
                    "position2": [["current": element(subject.0, subject.1, type: "SUBJECT"), "removed": NSNull()] as [String: Any]],
                    "position3": [["current": element("2.05", "Klasse 2.05", type: "ROOM"), "removed": NSNull()] as [String: Any]],
                    "position4": [["current": element("4A", "4. Klasse A", type: "CLASS"), "removed": NSNull()] as [String: Any]],
                ]
                switch (d, p) {
                case (0, 1):
                    entry["type"] = "EXAM"
                    entry["exam"] = ["name": "Schularbeit", "description": "Kapitel 3"]
                case (1, 2):
                    entry["status"] = "CANCELLED"
                case (2, 0):
                    entry["status"] = "CHANGED"
                    entry["position1"] = [["current": element("SCH", "Schmid Anna", type: "TEACHER"), "removed": NSNull()] as [String: Any],
                                          ["current": NSNull(), "removed": element("MUE", "Müller Hans", type: "TEACHER")] as [String: Any]]
                    entry["texts"] = [["type": "LESSON_INFO", "text": "Buch mitnehmen"], ["type": "SUBSTITUTION", "text": "statt Müller"]]
                    entry["icons"] = ["HOMEWORK"]
                case (3, 3):
                    entry["type"] = "ADDITIONAL"
                    entry["lessonInfo"] = "Zusatzstunde"
                case (4, 4):
                    entry["position2"] = [Any]()
                    entry["lessonInfo"] = "Ausflug"
                default:
                    break
                }
                entries.append(entry)
            }
            days.append(["date": date, "status": "REGULAR", "gridEntries": entries])
        }
        return ["days": days]
    }

    private static var timetableFilter: [String: Any] {
        ["departments": [["id": 9, "name": "Informatik"]],
         "preSelected": ["id": klasseId, "shortName": "4A", "longName": "4. Klasse A"] as [String: Any],
         "classes": [["class": ["id": klasseId, "shortName": "4A", "longName": "4. Klasse A"] as [String: Any], "department": ["id": 9, "name": "Informatik"]],
                     ["class": ["id": 22, "shortName": "1C", "displayName": "1. C"] as [String: Any]]],
         "teachers": [["teacher": ["id": 1, "shortName": "MUE", "longName": "Müller Hans"] as [String: Any]]],
         "rooms": [["room": ["id": 3, "shortName": "2.05", "longName": "Klasse 2.05"] as [String: Any]]]]
    }

    private static var lessonDetail: [String: Any] {
        ["calendarEntries": [[
            "id": 1000,
            "startDateTime": "\(dayString(0))T07:50:00", "endDateTime": "\(dayString(0))T08:40:00",
            "status": "CHANGED",
            "teachingContent": "<p>Quadratische Gleichungen</p><p>Seite&nbsp;42</p>",
            "notesAll": "Taschenrechner &amp; Heft", "lessonInfo": "Buch mitnehmen", "substText": "statt Müller",
            "klasses": [["id": klasseId, "shortName": "4A", "displayName": "4A", "status": "REGULAR"] as [String: Any]],
            "mainStudentGroup": ["id": 5, "name": "Gruppe 1", "displayName": "G1"] as [String: Any],
            "teachers": [["id": 1, "shortName": "SCH", "longName": "Schmid Anna", "displayName": "SCH", "status": "SUBSTITUTED"] as [String: Any],
                         ["id": 2, "shortName": "MUE", "longName": "Müller Hans", "displayName": "MUE", "status": "REMOVED"]],
            "rooms": [["id": 3, "shortName": "Inf VI", "longName": "Informatik VI", "displayName": "Inf VI", "status": "REGULAR"] as [String: Any]],
            "exam": ["name": "Schularbeit", "description": "Kapitel 3 und 4"],
            "homeworks": [["id": 70, "text": "<p>Seite 12,<br>Aufgabe 3</p>", "completed": false] as [String: Any]],
        ] as [String: Any]]]
    }

    // ── Grades, absences, class register ─────────────────────────────────────

    private static let gradeLessons: [[String: Any]] = [
        ["id": 40, "subjects": "Mathematik", "teachers": "Müller Hans"],
        ["id": 41, "subjects": "Deutsch", "teachers": "Berger Eva"],
        ["id": 42, "subjects": "Englisch", "teachers": "Schmid Anna"],
    ]

    private static func grades(lesson: Int) -> [[String: Any]] {
        let marks: [(Double, Int)] = lesson == 40 ? [(8, -60), (5.5, -30), (9, -5)] : lesson == 41 ? [(7, -40), (6.5, -10)] : [(10, -20)]
        return marks.enumerated().map { i, mark in
            ["id": lesson &* 10 &+ i, "text": "Test \(i + 1)", "date": dayNum(mark.1),
             "mark": ["name": String(mark.0), "markValue": mark.0, "markDisplayValue": mark.0] as [String: Any],
             "examType": ["name": "SA", "longname": "Schularbeit"]]
        }
    }

    private static var absences: [[String: Any]] {
        [["id": 1, "startDate": dayNum(-14), "endDate": dayNum(-14), "startTime": 750, "endTime": 1300, "isExcused": true, "reasonName": "Krank",
          "absenceType": "ABSENCE", "hours": 6, "text": "Fieber", "excuseNote": "", "teacherName": "Müller Hans", "subject": "Mathematik", "canEdit": true],
         ["id": 2, "startDate": dayNum(-7), "endDate": dayNum(-6), "startTime": 0, "endTime": 0, "isExcused": false, "reasonName": "Arzt",
          "absenceType": "ABSENCE", "lessonHours": 3, "note": "", "teacherFirstname": "Eva", "teacherLastname": "Berger", "canEdit": true],
         ["id": 3, "startDate": dayNum(-1), "endDate": dayNum(-1), "startTime": 840, "endTime": 930, "isExcused": false, "absenceType": "LATE", "canEdit": false]]
    }

    private static let absenceReasons: [[String: Any]] = [["id": 1, "name": "Krank"], ["id": 2, "name": "Arzt"], ["id": 3, "name": "---"]]

    private static var classregRows: [[String: Any]] {
        [["id": 1, "subjectName": "Mathematik", "creatorName": "Müller Hans", "createDate": dayNum(-10), "eventReasonName": "Ermahnung", "categoryName": "Verhalten", "text": "Hausaufgaben vergessen"],
         ["id": 2, "subjectName": "", "creatorName": "Berger Eva", "createDate": dayNum(-2), "eventReasonName": "", "categoryName": "Lob", "text": "Sehr gut mitgearbeitet"]]
    }

    private static let classServices: [String: Any] = [
        "data": [
            "classRoles": [
                ["id": 1, "personId": studentId, "klasse": ["id": klasseId, "name": "4A"], "foreName": "Anna", "longName": "Rossi", "duty": ["id": 7, "label": "Klassensprecher"]] as [String: Any],
                ["id": 2, "personId": 502, "klasse": ["id": klasseId, "name": "4A"], "longName": "Bianchi", "duty": ["id": 8, "label": "Tafeldienst"]],
            ],
            "klasses": [["id": klasseId, "name": "4A"]],
        ] as [String: Any],
    ]

    private static var homeworks: [String: Any] {
        ["data": [
            "records": [["homeworkId": 1, "teacherId": 9, "elementIds": [studentId]] as [String: Any], ["homeworkId": 2, "teacherId": 9, "elementIds": [klasseId]]],
            "homeworks": [["id": 1, "lessonId": 40, "date": dayNum(-2), "dueDate": dayNum(3), "text": "<p>Seite 12</p>", "remark": "", "completed": false, "attachments": [Any]()] as [String: Any],
                          ["id": 2, "lessonId": 41, "date": dayNum(-2), "dueDate": dayNum(5), "text": "Aufsatz &amp; Skizze", "completed": false]],
            "teachers": [["id": 9, "name": "MUE"]],
            "lessons": [["id": 40, "subject": "Mathematik", "lessonType": "Unterricht"], ["id": 41, "subject": "Deutsch", "lessonType": "Unterricht"]],
        ] as [String: Any]]
    }

    // ── Messages ─────────────────────────────────────────────────────────────

    private static func message(_ id: Int, _ subject: String, read: Bool, confirm: Bool = false) -> [String: Any] {
        ["id": id, "subject": subject, "contentPreview": "Vorschau von \(subject)",
         "sender": ["displayName": "Müller Hans", "userId": 9] as [String: Any],
         "sentDateTime": stamp(-id), "isMessageRead": read, "hasAttachments": id == 1,
         "requestConfirmation": ["allowSendRequestConfirmation": confirm, "confirmationDate": ""] as [String: Any]]
    }

    private static func messages(_ path: String, method: String) -> StubAnswer {
        let parts = path.split(separator: "/").map(String.init)
        let root = "/api/rest/view/v1/messages"
        if method == "DELETE" || path.hasSuffix("/markasread") || path.hasSuffix("/read-confirmation") || path.hasSuffix("/revoke") || path.hasSuffix("/reply") {
            return StubAnswer(json: [String: Any]())
        }
        if method == "POST" || method == "PUT" { return StubAnswer(json: ["id": 77]) }
        switch path {
        case root:
            return StubAnswer(json: ["incomingMessages": [message(1, "Elternsprechtag", read: false, confirm: true), message(2, "Ausflug", read: true), message(3, "Schulball", read: false)]])
        case root + "/sent":
            var excuse = message(4, "Entschuldigung: \(Self.germanDate(-7)), 08:00-09:00", read: true)
            excuse["recipientPersons"] = [["displayName": "Müller Hans"]]
            excuse["requestConfirmationStatus"] = ["confirmedRequestCount": 1, "totalRequestCount": 3]
            return StubAnswer(json: ["sentMessages": [excuse]])
        case root + "/drafts":
            return StubAnswer(json: ["draftMessages": [message(5, "Entwurf", read: true)]])
        case root + "/recipients/static/persons":
            return StubAnswer(json: [["type": "CLASS_TEACHERS", "persons": [["userId": 9, "displayName": "Müller Hans", "tags": ["Klassenvorstand"]] as [String: Any]]] as [String: Any],
                                     ["type": "TEACHERS", "persons": [["userId": 9, "displayName": "Müller Hans"] as [String: Any], ["userId": 10, "displayName": "Berger Eva"]]]])
        case root + "/permissions":
            return StubAnswer(json: ["recipientOptions": ["TEACHER"], "maxFileSize": 7_000_000, "maxFileCount": 5] as [String: Any])
        default:
            break
        }
        if path.hasSuffix("/attachmentstorageurl") {
            return StubAnswer(json: ["downloadUrl": "https://stub-school.invalid/WebUntis/reports.do?msgId=file", "additionalHeaders": [["key": "X-Stub", "value": "1"]]] as [String: Any])
        }
        if path.contains("/attachments/") || path.hasSuffix("/content") { return StubAnswer(raw: Data(Self.planPDF.utf8), type: "application/pdf") }
        if path.hasSuffix("/attachments") {
            return StubAnswer(json: ["attachments": [["id": 7, "storageId": "stor-1", "name": "Plan.pdf", "size": 2048] as [String: Any]]])
        }
        if path.hasSuffix("/reply-form") || path.contains("reply-form") {
            return StubAnswer(json: ["subject": "AW: Elternsprechtag", "recipient": ["displayName": "Müller Hans"]] as [String: Any])
        }
        if path.hasSuffix("/request-confirmation-status") {
            return StubAnswer(json: [["recipientDisplayName": "Müller Hans", "recipientClassName": "", "confirmationStates": [["userDisplayName": "Müller Hans", "date": stamp(-1)]]] as [String: Any]])
        }
        if parts.contains("drafts") {
            return StubAnswer(json: ["id": 5, "subject": "Entwurf", "content": "<p>Text</p>", "recipientPersons": [["id": 9, "type": "TEACHER", "displayName": "Müller Hans"] as [String: Any]]] as [String: Any])
        }
        let id = Int(parts.last ?? "") ?? 1
        return StubAnswer(json: ["id": id, "subject": "Elternsprechtag", "sender": ["displayName": "Müller Hans", "userId": 9] as [String: Any],
                                 "sentDateTime": stamp(-1), "body": "<p>Liebe Eltern,</p><p>der Elternsprechtag findet am <b>Freitag</b> statt.<br>https://example.invalid/info</p>",
                                 "attachments": [["id": 7, "storageId": "stor-1", "name": "Plan.pdf", "size": 2048] as [String: Any]]] as [String: Any])
    }

    private static func germanDate(_ offset: Int) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day(offset))
        return String(format: "%02d.%02d.%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2026)
    }

    // ── POKYH backend ────────────────────────────────────────────────────────

    private static func user(_ name: String) -> [String: Any] {
        ["stableUid": "uid-\(name)", "username": name, "webuntisKlasseId": klasseId, "webuntisKlasseName": "4A", "classId": classId,
         "isAdmin": false, "role": name == "eltern" ? "parent" : "student"]
    }

    private static func backend(_ path: String, method: String, query: [String: String], body: Data) -> StubAnswer {
        let parts = path.split(separator: "/").map(String.init)
        let json = object(body)
        switch path {
        case "/auth/login", "/auth/register":
            let name = (json["username"] as? String ?? "anna").lowercased()
            if let password = json["password"] as? String, name != "nurpokyh" || password == "falsch" {
                return StubAnswer(json: ["error": "Ungültige Zugangsdaten"], status: 401, isAuth: true)
            }
            return StubAnswer(json: ["token": "stub-token-\(name)", "refreshToken": "stub-refresh-\(name)", "user": user(name)] as [String: Any], isAuth: true)
        case "/auth/refresh":
            return StubAnswer(json: ["token": "stub-token-renewed", "refreshToken": "stub-refresh-renewed"], isAuth: true)
        case "/auth/me":
            return StubAnswer(json: user("anna"), isAuth: true)
        case "/auth/sessions":
            return StubAnswer(json: ["sessions": deviceRows])
        case "/auth/sessions/sign-out-others", "/usage/ping", "/push/apns", "/privacy/acknowledge", "/privacy/usage-stats":
            return StubAnswer(json: [String: Any]())
        case "/auth/login-history":
            return StubAnswer(json: ["logins": loginRows, "keptDays": 90] as [String: Any])
        case "/webuntis/schools":
            return schools(query["q"] ?? "")
        case "/webuntis/login-options":
            return StubAnswer(json: ["office365": true, "password": true], isAuth: true)
        case "/privacy/status":
            let version = StubServer.showsPrivacyNotice ? "old" : "2026-01"
            return StubAnswer(json: ["acknowledgedVersion": version, "acknowledgedAt": stamp(-30), "usageStats": true, "usageStatsAt": stamp(-30)] as [String: Any])
        case "/api/privacy-notice":
            return StubAnswer(json: ["version": "2026-01", "title": "Datenschutz", "summary": "Kurz gesagt"])
        case "/users/me":
            return StubAnswer(raw: Data(), type: "application/json", status: 204)
        case "/users/me/export":
            return StubAnswer(json: ["username": "anna", "todos": [Any]()] as [String: Any])
        case "/users/me/bell":
            return StubAnswer(json: ["seen": [Any](), "cleared": [Any]()])
        case "/users/me/activity":
            return StubAnswer(json: activity)
        case "/classes/mine":
            return StubAnswer(json: apiClass)
        case "/dishes":
            return StubAnswer(json: ["menu": ["dishes": dishes]])
        case "/dish-ratings/batch":
            let ids = json["dishIds"] as? [String] ?? []
            return StubAnswer(json: Dictionary(ids.map { ($0, rating) }) { a, _ in a })
        case "/subject-images":
            return StubAnswer(json: [["subject": "mathematik"]])
        case "/subject-images/report":
            return StubAnswer(json: [String: Any]())
        default:
            break
        }
        if parts.first == "dish-ratings" {
            return StubAnswer(json: rating)
        }
        if parts.first == "dish-comments" {
            return commentRoute(parts: Array(parts.dropFirst(2)), method: method, json: json)
        }
        if parts.first == "subject-images" { return image }
        if parts.first == "auth", parts.count >= 2, parts[1] == "sessions" { return StubAnswer(json: [String: Any]()) }
        if parts.first == "auth", parts.count >= 3, parts[1] == "qr" {
            // What the computer gets, by field name only: tests check the password and a session go along.
            if method == "POST", parts.last == "approve" {
                var fields = json.keys.sorted()
                if let school = json["school"] as? [String: Any] { fields += school.keys.sorted().map { "school.\($0)" } }
                StubServer.log("QR approve \(fields.joined(separator: ","))")
            }
            return StubAnswer(json: ["label": "Safari auf Mac", "ip": "203.0.113.5", "place": "Brixen"])
        }
        if parts.first == "users", parts.count >= 3, parts[2] == "todos" {
            return todoRoute(parts: Array(parts.dropFirst(3)), method: method, json: json)
        }
        if parts.first == "classes", parts.count >= 3, parts[2] == "reminders" {
            return reminderRoute(parts: Array(parts.dropFirst(3)), method: method, json: json)
        }
        StubServer.log("UNROUTED backend \(method) \(path)")
        return StubAnswer(json: [String: Any]())
    }

    private static func schools(_ q: String) -> StubAnswer {
        if q.count < 3 { return StubAnswer(json: ["error": "too short"], status: 400, isAuth: true) }
        if q.lowercased().hasPrefix("viele") { return StubAnswer(json: ["error": "too many"], status: 422, isAuth: true) }
        if q.lowercased().hasPrefix("limit") { return StubAnswer(json: ["error": "slow down"], status: 429, isAuth: true) }
        if q.lowercased().hasPrefix("keine") { return StubAnswer(json: ["schools": [Any]()], isAuth: true) }
        let school = StubServer.school
        return StubAnswer(json: ["schools": [
            ["id": 1, "loginName": school.loginName, "name": school.name, "address": "Hauptstraße 1, Teststadt", "server": school.server] as [String: Any],
            ["id": 2, "loginName": "andere-schule", "name": "Andere Schule", "server": "andere.invalid"],
        ]], isAuth: true)
    }

    private static var deviceRows: [[String: Any]] {
        [["id": "dev-1", "current": true, "client": "app", "platform": "ios", "os": "iOS 27", "browser": "", "model": "iPhone18,2", "ip": "203.0.113.1", "country": "IT", "region": "BZ", "city": "Brixen", "createdAt": stamp(-30), "lastUsedAt": stamp(0)],
         ["id": "dev-2", "current": false, "client": "web", "platform": "mac", "os": "macOS", "browser": "Safari", "model": "", "ip": "203.0.113.2", "country": "AT", "region": NSNull(), "city": NSNull(), "createdAt": stamp(-10), "lastUsedAt": stamp(-2)]]
    }

    private static var loginRows: [[String: Any]] {
        [["id": "log-1", "at": stamp(0), "method": "password", "client": "app", "platform": "ios", "os": "iOS 27", "browser": "", "model": "iPhone18,2", "ip": "203.0.113.1", "country": "IT", "region": "BZ", "city": "Brixen"],
         ["id": "log-2", "at": stamp(-5), "method": "qr", "client": "web", "platform": "mac", "os": "macOS", "browser": "Safari", "model": "", "ip": NSNull(), "country": "", "region": NSNull(), "city": NSNull()]]
    }

    /// The shape of the backend's services/accountActivity.ts. `POKYH_STUB_CONSENT=off`: the account
    /// said no to the personal statistics, so the time and pages aren't there.
    /// `POKYH_STUB_ACTIVITY_DAYS`: how many days back, a school year instead of 14 weeks.
    /// A real one-page PDF, so the viewer has something to draw.
    private static let planPDF = """
%PDF-1.4
1 0 obj
<</Type/Catalog/Pages 2 0 R>>
endobj
2 0 obj
<</Type/Pages/Kids[3 0 R]/Count 1>>
endobj
3 0 obj
<</Type/Page/Parent 2 0 R/MediaBox[0 0 420 300]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>
endobj
4 0 obj
<</Length 35>>
stream
BT /F1 28 Tf 60 150 Td (Plan) Tj ET
endstream
endobj
5 0 obj
<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>
endobj
xref
0 6
0000000000 65535 f 
0000000009 00000 n 
0000000054 00000 n 
0000000105 00000 n 
0000000217 00000 n 
0000000300 00000 n 
trailer
<</Size 6/Root 1 0 R>>
startxref
363
%%EOF
"""

    private static var activity: [String: Any] {
        let env = ProcessInfo.processInfo.environment
        let consent = env["POKYH_STUB_CONSENT"] != "off"
        let span = env["POKYH_STUB_ACTIVITY_DAYS"].flatMap(Int.init) ?? 98
        let days: [[String: Any]] = ((1 - span)...0).map { offset in
            let active = offset % 3 != 0
            let seconds = consent && active ? abs(offset) * 47 % 3600 : 0
            return ["date": dayString(offset), "active": active, "logins": active ? abs(offset) % 3 : 0, "activeSeconds": seconds,
                    "visits": seconds > 0 ? 2 : 0, "screens": seconds > 0 ? 7 : 0]
        }
        var hours = Array(repeating: 0, count: 24)
        if consent { (7...21).forEach { hours[$0] = ($0 * 37 + 11) % 19 * 120 } }
        let pages: [[String: Any]] = consent ? [["page": "/timetable", "views": 120], ["page": "/grades", "views": 64], ["page": "/mensa", "views": 31], ["page": "/unbekannt", "views": 4]] : []
        return ["today": dayString(0), "from": dayString(1 - span), "timezone": "Europe/Rome",
                "retention": ["activeDays": 30, "usage": 30, "schoolYear": false, "pages": 30] as [String: Any],
                "usageConsent": consent, "memberSince": stamp(-420),
                "days": days,
                "totals": ["activeDays": 65, "logins": 42, "activeSeconds": consent ? 92_700 : 0, "visits": consent ? 130 : 0, "screens": consent ? 455 : 0, "currentStreak": 3, "longestStreak": 9],
                "weekdays": [14, 12, 13, 11, 9, 4, 2],
                "hours": hours,
                "platforms": ["phone": 58, "desktop": 12, "app": 55, "web": 15],
                "pages": pages,
                "created": ["todosDone": 23, "todosOpen": 4, "reminders": 6, "comments": 9, "ratings": 14]]
    }

    private static var apiClass: [String: Any] {
        ["id": classId, "name": "4A", "code": "ABC123", "webuntisKlasseId": klasseId, "createdBy": "uid-anna", "createdByName": "anna", "createdAt": stamp(-100),
         "members": [["stableUid": "uid-anna", "username": "anna", "joinedAt": stamp(-100)] as [String: Any], ["stableUid": "uid-luca", "username": "luca", "joinedAt": NSNull()]]]
    }

    private static var dishes: [[String: Any]] {
        (0..<6).flatMap { offset -> [[String: Any]] in
            [["id": "dish-\(offset)-1", "name": ["de": "Spaghetti", "it": "Spaghetti", "en": "Spaghetti"], "description": ["de": "Mit Tomatensauce"],
              "category": "Hauptgericht", "date": dayString(offset), "imageUrl": "https://stub-school.invalid/img/dish.jpg", "price": 5.5,
              "allergens": ["A", "G"], "tags": ["vegetarisch"], "calories": 450.0, "protein": 12.5, "carbs": 70.0, "fat": 9.0],
             ["id": "dish-\(offset)-2", "name": "Salat", "category": "Beilage", "date": dayString(offset), "allergens": [Any](), "tags": [Any]()]]
        }
    }

    private static var rating: [String: Any] {
        ["ratings": ["uid-anna": 4, "uid-luca": 5], "myRating": 4]
    }

    private static func seedTodos() -> [[String: Any]] {
        [["id": "todo-1", "title": "Mathe lernen", "details": "Kapitel 4", "dueAt": stamp(2), "done": false, "doneAt": NSNull(), "createdAt": stamp(-3)],
         ["id": "todo-2", "title": "Buch kaufen", "details": "", "dueAt": NSNull(), "done": false, "doneAt": NSNull(), "createdAt": stamp(-1)],
         ["id": "todo-3", "title": "Erledigt", "details": "", "dueAt": stamp(-1), "done": true, "doneAt": stamp(0), "createdAt": stamp(-9)]]
    }

    private static func seedReminders() -> [[String: Any]] {
        [["id": "rem-1", "classId": classId, "title": "Ausflug", "body": "Jause mitnehmen", "remindAt": stamp(3), "createdBy": "uid-anna", "createdByName": "Anna", "createdByUsername": "anna", "createdAt": stamp(-2)],
         ["id": "rem-2", "classId": classId, "title": "Abgabe", "body": "", "remindAt": stamp(-1), "createdBy": "uid-luca", "createdByName": "Luca", "createdByUsername": "luca", "createdAt": stamp(-5)]]
    }

    private static func seedComments() -> [[String: Any]] {
        [["id": "com-1", "stableUid": "uid-anna", "username": "anna", "body": "Sehr gut", "createdAt": stamp(-1), "updatedAt": NSNull()],
         ["id": "com-2", "stableUid": "uid-luca", "username": "luca", "body": "Naja", "createdAt": stamp(-2), "updatedAt": stamp(-1)]]
    }

    private static func todoRoute(parts: [String], method: String, json: [String: Any]) -> StubAnswer {
        lock.withLock {
            switch (method, parts.first) {
            case ("POST", _):
                let todo: [String: Any] = ["id": nextId("todo"), "title": json["title"] ?? "", "details": json["details"] ?? "", "dueAt": json["dueAt"] ?? NSNull(), "done": false, "doneAt": NSNull(), "createdAt": stamp(0)]
                todos.append(todo)
                return StubAnswer(json: todo)
            case ("PATCH", let id?):
                if let i = todos.firstIndex(where: { $0["id"] as? String == id }) { todos[i].merge(json) { $1 } }
                return StubAnswer(json: [String: Any]())
            case ("DELETE", let id?):
                todos.removeAll { $0["id"] as? String == id }
                return StubAnswer(json: [String: Any]())
            default:
                return StubAnswer(json: todos)
            }
        }
    }

    private static func reminderRoute(parts: [String], method: String, json: [String: Any]) -> StubAnswer {
        if parts.count >= 2, parts[1] == "comments" {
            return commentRoute(parts: Array(parts.dropFirst(2)), method: method, json: json)
        }
        return lock.withLock {
            switch (method, parts.first) {
            case ("POST", _):
                let reminder: [String: Any] = ["id": nextId("rem"), "classId": classId, "title": json["title"] ?? "", "body": json["body"] ?? "", "remindAt": json["remindAt"] ?? stamp(1),
                                               "createdBy": "uid-anna", "createdByName": "Anna", "createdByUsername": "anna", "createdAt": stamp(0)]
                reminders.append(reminder)
                return StubAnswer(json: reminder)
            case ("PATCH", let id?):
                guard let i = reminders.firstIndex(where: { $0["id"] as? String == id }) else { return StubAnswer(json: ["error": "gone"], status: 404) }
                reminders[i].merge(json) { $1 }
                return StubAnswer(json: reminders[i])
            case ("DELETE", let id?):
                reminders.removeAll { $0["id"] as? String == id }
                return StubAnswer(json: [String: Any]())
            default:
                return StubAnswer(json: reminders)
            }
        }
    }

    private static func commentRoute(parts: [String], method: String, json: [String: Any]) -> StubAnswer {
        lock.withLock {
            switch (method, parts.first) {
            case ("POST", _):
                let comment: [String: Any] = ["id": nextId("com"), "stableUid": "uid-anna", "username": "anna", "body": json["body"] ?? "", "createdAt": stamp(0), "updatedAt": NSNull()]
                comments.insert(comment, at: 0)
                return StubAnswer(json: comment)
            case ("PATCH", let id?):
                guard let i = comments.firstIndex(where: { $0["id"] as? String == id }) else { return StubAnswer(json: ["error": "gone"], status: 404) }
                comments[i]["body"] = json["body"] ?? ""
                comments[i]["updatedAt"] = stamp(0)
                return StubAnswer(json: comments[i])
            case ("DELETE", let id?):
                comments.removeAll { $0["id"] as? String == id }
                return StubAnswer(json: [String: Any]())
            default:
                return StubAnswer(json: comments)
            }
        }
    }

    // ── Recaps and popups (routes/recaps.ts, routes/popups.ts) ─────────────────
    // What the backend sends, field for field, so the app meets the same nulls and the same need
    // for a token: /recaps answers 401 without one, /popups/active leaves out a school's own popups.

    nonisolated(unsafe) private static var recapViews: [String: (openedAt: String, finishedAt: String?)] = [:]

    /// toISOString(): always with milliseconds.
    private static let isoMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static func stampMs(_ offsetDays: Int) -> String { isoMillis.string(from: day(offsetDays)) }

    /// The session as requireAuth and optionalAuth read it: a bearer token, or none.
    private static func bearer(_ headers: [String: String]) -> String? {
        let value = headers.first { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame }?.value ?? ""
        guard value.hasPrefix("Bearer ") else { return nil }
        let token = value.dropFirst("Bearer ".count).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    private static func engagement(_ path: String, method: String, query: [String: String], headers: [String: String], body: Data) -> StubAnswer? {
        let parts = path.split(separator: "/").map(String.init)
        switch parts.first {
        case "popups":
            guard parts.count == 2, parts[1] == "active" else { return nil }
            guard ["web", "android", "ios"].contains(query["platform"] ?? "") else {
                return StubAnswer(json: ["error": "Ungültige Eingabe"], status: 400)
            }
            let signedIn = query["audience"] != "guest" && bearer(headers) != nil
            let list = StubServer.showsPopups ? everySchoolPopups + (signedIn ? schoolPopups : []) : []
            return StubAnswer(json: ["now": stampMs(0), "popups": list] as [String: Any])
        case "recaps":
            guard bearer(headers) != nil else { return StubAnswer(json: ["error": "Missing Authorization header"], status: 401) }
            return lock.withLock { recapRoute(Array(parts.dropFirst()), method: method, json: object(body)) }
        default:
            return nil
        }
    }

    private static func recapRoute(_ parts: [String], method: String, json: [String: Any]) -> StubAnswer {
        let mine = StubServer.showsRecap ? [recap] : []
        guard let id = parts.first else { return StubAnswer(json: ["recaps": mine]) }
        guard UUID(uuidString: id) != nil else { return StubAnswer(json: ["error": "Ungültige Eingabe"], status: 400) }
        guard let found = mine.first(where: { $0["id"] as? String == id }) else {
            return StubAnswer(json: ["error": "Recap nicht gefunden"], status: 404)
        }
        if parts.count == 1 { return StubAnswer(json: ["recap": found, "pokyh": recapFigures] as [String: Any]) }
        guard parts.count == 2, parts[1] == "view", method == "POST" else { return StubAnswer(json: ["error": "Not found"], status: 404) }
        // The first opening and the first time to the end count; watching again changes nothing.
        var view = recapViews[id] ?? (openedAt: stampMs(0), finishedAt: nil)
        if json["finished"] as? Bool == true, view.finishedAt == nil { view.finishedAt = stampMs(0) }
        recapViews[id] = view
        return StubAnswer(json: ["openedAt": view.openedAt, "finishedAt": view.finishedAt ?? NSNull()] as [String: Any])
    }

    private static let recapId = "6f1b2a10-0000-4000-8000-0000000000a1"

    /// clientRow: every part (stored as ""), seen as this run of the app has marked it.
    private static var recap: [String: Any] {
        let view = recapViews[recapId]
        return ["id": recapId, "title": "Dein Schuljahr", "periodFrom": dayString(-60), "periodTo": dayString(-1), "endsAt": stampMs(20),
                "sections": ["school", "absences", "grades", "exams", "classreg", "pokyh"],
                "openedAt": view?.openedAt ?? NSNull(), "finishedAt": view?.finishedAt ?? NSNull()]
    }

    /// recapPokyhFigures with everything it can answer.
    private static var recapFigures: [String: Any] {
        ["covered": ["from": dayString(-60), "to": dayString(-1)], "usageConsent": true, "memberSince": stampMs(-400),
         "kept": ["liveFrom": dayString(-90), "archive": false] as [String: Any],
         "totals": ["activeDays": 42, "logins": 12, "activeSeconds": 36000, "visits": 180, "screens": 640, "longestStreak": 9],
         "weekdays": [9, 8, 7, 9, 6, 2, 1],
         "hours": [0, 0, 0, 0, 0, 0, 120, 2400, 5300, 900, 400, 300, 2600, 3100, 4200, 3900, 2700, 2100, 3300, 4800, 3500, 1800, 400, 0],
         "platforms": ["phone": 30, "desktop": 4, "app": 28, "web": 6], "firstDay": dayString(-58),
         "busiestDay": ["date": dayString(-20), "activeSeconds": 2400, "logins": 2] as [String: Any],
         "pages": [["page": "/timetable", "views": 120], ["page": "/grades", "views": 64]] as [[String: Any]],
         "created": ["todos": 7, "todosDone": 5, "reminders": 2, "comments": 3, "ratings": 4],
         "favouriteDish": ["name": ["de": "Spinatknödel", "it": "Canederli agli spinaci", "en": "Spinach dumplings"], "stars": 5] as [String: Any],
         "rank": ["topPercent": 10, "group": 240]]
    }

    // contentHtml as services/popupRender.ts makes it from the admin's Markdown. Text only: a web
    // view would fetch an image for real, past this stub.
    private static var everySchoolPopups: [[String: Any]] {
        [["id": "0b7d2c1e-4f3a-4c7e-9a51-2f6b8e1d0a01", "revision": 1, "title": "Neue Mensa-Zeiten",
          "html": "<p>Ab <strong>Montag</strong> öffnet die Mensa um <span style=\"color:#e11d48\">11:30</span>.</p>\n<ul>\n<li>Montag bis Freitag</li>\n<li><input checked disabled=\"disabled\" type=\"checkbox\" /> Vorbestellung in der App</li>\n</ul>\n<blockquote>\n<p>Bitte Tabletts zurückbringen.</p>\n</blockquote>\n<table>\n<thead>\n<tr>\n<th>Tag</th>\n<th>Bis</th>\n</tr>\n</thead>\n<tbody><tr>\n<td>Mo–Do</td>\n<td>14:00</td>\n</tr>\n<tr>\n<td>Fr</td>\n<td>13:00</td>\n</tr>\n</tbody></table>\n<p>Mehr auf <a href=\"https://pokyh.com\" target=\"_blank\" rel=\"noopener noreferrer nofollow\">pokyh.com</a>.</p>\n",
          "showCount": 1, "startsAt": NSNull(), "endsAt": NSNull(), "slotMs": NSNull()]]
    }

    /// A school's own: only with the account's session.
    private static var schoolPopups: [[String: Any]] {
        [["id": "0b7d2c1e-4f3a-4c7e-9a51-2f6b8e1d0a02", "revision": 2, "title": "Skitag",
          "html": "<p>Der <strong>Skitag</strong> ist am 12. Februar.<br />Treffpunkt: <code>Busbahnhof</code>, 7:15 Uhr.</p>\n<details><summary>Was mitnehmen?</summary>Helm, Handschuhe, Jause.</details>",
          "showCount": 3, "startsAt": stampMs(-1), "endsAt": stampMs(2), "slotMs": 86_400_000]]
    }
}
#endif
