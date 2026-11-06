import Foundation
import Testing
@testable import PokyhCore

struct AccountActivityTests {
    private func parse(_ json: String) throws -> AccountActivity {
        try #require(AccountActivity(data: Data(json.utf8)))
    }

    /// The shape services/accountActivity.ts answers.
    private let full = #"""
    {"today":"2026-11-03","from":"2026-07-28","timezone":"Europe/Rome",
     "retention":{"activeDays":30,"usage":30,"schoolYear":true,"pages":30},
     "usageConsent":true,"memberSince":"2025-09-12T07:00:00.000Z",
     "days":[{"date":"2026-11-02","active":true,"logins":2,"activeSeconds":1500,"visits":3,"screens":9},
             {"date":"2026-11-03","active":false,"logins":0,"activeSeconds":0,"visits":0,"screens":0}],
     "totals":{"activeDays":1,"logins":2,"activeSeconds":1500,"visits":3,"screens":9,"currentStreak":1,"longestStreak":4},
     "weekdays":[1,0,0,0,0,0,0],
     "hours":[0,0,0,0,0,0,0,60,0,0,0,0,0,0,0,0,300,0,0,0,0,0,0,0],
     "platforms":{"phone":1,"desktop":0,"app":1,"web":0},
     "pages":[{"page":"/timetable","views":12},{"page":"/geheim","views":3}],
     "created":{"todosDone":5,"todosOpen":2,"reminders":1,"comments":4,"ratings":3}}
    """#

    @Test func readsTheBackendsAnswer() throws {
        let a = try parse(full)
        #expect(a.usageConsent)
        #expect(a.days.count == 2)
        #expect(a.days[0].logins == 2 && a.days[0].activeSeconds == 1500)
        #expect(a.totals.longestStreak == 4)
        #expect(a.platforms.phone == 1 && a.platforms.app == 1)
        #expect(a.pages.first?.views == 12)
        #expect(a.created.comments == 4)
        #expect(a.averageSeconds == 1500)
    }

    @Test func notAnObjectIsNoAnswer() {
        for bad in ["", "null", "[]", "12", "<html>", "{\"days\":"] {
            #expect(AccountActivity(data: Data(bad.utf8)) == nil, "\(bad)")
        }
    }

    @Test func nothingAtAllIsZeros() throws {
        let a = try parse("{}")
        #expect(!a.usageConsent)
        #expect(a.days.isEmpty && a.weekdays.isEmpty && a.hours.isEmpty && a.pages.isEmpty)
        #expect(a.totals == .init())
        #expect(a.averageSeconds == nil)
        #expect(a.hourColumns.isEmpty)
        #expect(a.weekdayColumns(.of(.de)).isEmpty)
        #expect(a.memberSinceText(.of(.de)) == nil)
    }

    @Test func nullsAndWrongTypesReadAsNothing() throws {
        let a = try parse(#"""
        {"usageConsent":"ja","memberSince":12,"days":{"a":1},"totals":[1],"weekdays":"x","hours":null,"platforms":7,"pages":[null,{"views":3},{"page":9}],"created":false}
        """#)
        #expect(!a.usageConsent)
        #expect(a.memberSince == nil)
        #expect(a.days.isEmpty && a.pages.isEmpty)
        #expect(a.totals == .init() && a.created == .init() && a.platforms == .init())
    }

    @Test func absurdNumbersStayInRange() throws {
        let a = try parse(#"""
        {"days":[{"date":"2026-11-02","active":true,"activeSeconds":1e300,"logins":-5}],
         "totals":{"activeSeconds":1e300,"logins":-1e300,"visits":"12","screens":true},
         "weekdays":[1e300,-1e300,0.5,0,0,0,0],"hours":[1e300]}
        """#)
        #expect(a.days[0].logins == 0)
        #expect(a.days[0].activeSeconds == LooseJSON.biggestCount)
        #expect(a.totals.activeSeconds == LooseJSON.biggestCount)
        #expect(a.totals.logins == 0 && a.totals.visits == 0)
        _ = a.averageSeconds
        _ = a.weekdayColumns(.of(.de))
        _ = AccountActivity.duration(a.totals.activeSeconds)
        _ = ActivityGridLayout(days: a.days)
    }

    @Test func tooManyDaysAreCut() throws {
        let days = (0..<2000).map { _ in #"{"date":"2026-11-02","active":true}"# }.joined(separator: ",")
        #expect(try parse("{\"days\":[\(days)]}").days.count == 400)
    }

    // ── Time ─────────────────────────────────────────────────────────────────

    @Test func durations() {
        #expect(AccountActivity.duration(0) == "0 min")
        #expect(AccountActivity.duration(29) == "0 min")
        #expect(AccountActivity.duration(90) == "2 min")
        #expect(AccountActivity.duration(3540) == "59 min")
        #expect(AccountActivity.duration(3600) == "1 h 0 min")
        #expect(AccountActivity.duration(7500) == "2 h 5 min")
    }

    @Test func thePerDayFigureOnlyCountsDaysWithTime() throws {
        let a = try parse(#"""
        {"days":[{"date":"2026-11-01","active":true,"activeSeconds":100},{"date":"2026-11-02","active":true,"activeSeconds":0},{"date":"2026-11-03","active":true,"activeSeconds":300}],
         "totals":{"activeSeconds":400}}
        """#)
        #expect(a.averageSeconds == 200)
    }

    @Test(arguments: Lang.allCases) func memberSinceNamesTheMonth(_ lang: Lang) throws {
        let strings = Strings.of(lang)
        let text = try #require(try parse(#"{"memberSince":"2025-09-12T07:00:00.000Z"}"#).memberSinceText(strings))
        #expect(text.hasSuffix(" 2025"))
        #expect(text.first?.isUppercase == true)
        for bad in ["", "gestern", "2025-13-12", "0000-00-00", "2025-02-30T00:00:00Z"] {
            let json = try JSONSerialization.data(withJSONObject: ["memberSince": bad])
            #expect(try #require(AccountActivity(data: json)).memberSinceText(strings) == nil, "\(bad)")
        }
    }

    @Test func pageNames() {
        let s = Strings.of(.de)
        #expect(AccountActivity.pageName("/timetable", s) == "Stundenplan")
        #expect(AccountActivity.pageName("/geheim", s) == "/geheim")
        #expect(AccountActivity.pageName("/", s) == "/")
        #expect(AccountActivity.pageName("", s) == "")
    }

    // ── Bars ─────────────────────────────────────────────────────────────────

    @Test func theHourChartIsTheWakingHours() throws {
        let columns = try parse(full).hourColumns
        #expect(columns.count == 17)
        #expect(columns.first?.label == "6" && columns.last?.label == "22")
        let tallest = columns.filter(\.isTallest)
        #expect(tallest.map(\.label) == ["16"])
        #expect(tallest.first?.height == 1)
        // 60 of 300 seconds; an empty hour keeps a sliver.
        #expect(columns.first { $0.label == "7" }?.height == 0.2)
        #expect(columns.first { $0.label == "6" }?.height == 0.02)
    }

    @Test func tooFewHoursDrawNoChart() throws {
        let short = Array(repeating: "1", count: 22).joined(separator: ",")
        #expect(try parse("{\"hours\":[\(short)]}").hourColumns.isEmpty)
    }

    @Test func columnsWithNothingInThemMarkNoTop() {
        let columns = ActivityColumn.columns(values: [0, 0], labels: ["a", "b"])
        #expect(columns.allSatisfy { !$0.isTallest && $0.height == 0.02 })
        #expect(ActivityColumn.columns(values: [1], labels: ["a", "b"]).isEmpty)
        #expect(ActivityColumn.columns(values: [1, 2], labels: ["a", "a"]).isEmpty)
        #expect(ActivityColumn.columns(values: [], labels: []).isEmpty)
    }

    @Test func aTieMarksTheFirst() {
        let columns = ActivityColumn.columns(values: [1, 3, 3], labels: ["a", "b", "c"])
        #expect(columns.map(\.isTallest) == [false, true, false])
    }

    @Test(arguments: Lang.allCases) func weekdaysNeedAllSeven(_ lang: Lang) throws {
        let s = Strings.of(lang)
        #expect(try parse(#"{"weekdays":[1,2,3,4,5,6,7]}"#).weekdayColumns(s).count == 7)
        #expect(try parse(#"{"weekdays":[1,2,3]}"#).weekdayColumns(s).isEmpty)
    }

    @Test func horizontalBarsShareTheLargest() {
        #expect(ActivityShare.of(5, among: [5, 10]) == 0.5)
        #expect(ActivityShare.of(10, among: [5, 10]) == 1)
        #expect(ActivityShare.of(0, among: [0, 0]) == 0)
        #expect(ActivityShare.of(1, among: []) == 0)
    }

    // ── The grid ─────────────────────────────────────────────────────────────

    @Test func dates() throws {
        // 2 November 2026 is a Monday.
        #expect(ActivityDate(iso: "2026-11-02")?.weekday == 0)
        #expect(ActivityDate(iso: "2026-11-08")?.weekday == 6)
        for bad in ["", "2026", "2026-13-45", "0000-00-00", "2026-00-10", "2026-02-30", "not a date", "1-1-1", "99999-01-01", "2026-13-01T00:00:00Z", "٢٠٢٦-١١-٠٢"] {
            #expect(ActivityDate(iso: bad) == nil, "\(bad)")
        }
    }

    private func days(from first: String, count: Int) throws -> [AccountActivity.Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = .gmt
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let start = try #require(f.date(from: first))
        return try (0..<count).map { offset in
            AccountActivity.Day(date: f.string(from: try #require(calendar.date(byAdding: .day, value: offset, to: start))), active: true, logins: 1)
        }
    }

    @Test func weeksStartOnMonday() throws {
        // Wednesday, so two empty squares first.
        let layout = ActivityGridLayout(days: try days(from: "2026-11-04", count: 10))
        #expect(layout.weeks.count == 2)
        #expect(layout.weeks[0].count == 7)
        #expect(layout.weeks[0][0] == nil && layout.weeks[0][1] == nil)
        #expect(layout.weeks[0][2]?.date.day == 4)
        #expect(layout.weeks[1].count == 5)
        #expect(layout.weeks[1].last??.isLast == true)
        #expect(layout.weeks[0][2]?.isLast == false)
    }

    @Test func aMonthIsNamedOnce() throws {
        let layout = ActivityGridLayout(days: try days(from: "2026-10-05", count: 42))
        #expect(layout.months == [.init(column: 0, month: 10), .init(column: 4, month: 11)])
    }

    @Test func aMonthWithoutRoomGoesUnnamed() throws {
        // 26 October is the last week of the month: its name would run into November's.
        let layout = ActivityGridLayout(days: try days(from: "2026-10-26", count: 21))
        #expect(layout.months == [.init(column: 1, month: 11)])
        // Nor at the very edge.
        #expect(ActivityGridLayout(days: try days(from: "2026-10-26", count: 8)).months.isEmpty)
        #expect(ActivityGridLayout(days: try days(from: "2026-10-19", count: 14)).months == [.init(column: 0, month: 10)])
    }

    @Test func aSchoolYearIsDrawnDense() throws {
        #expect(ActivityGridLayout(days: try days(from: "2026-08-03", count: 98)).weeks.count == 14)
        #expect(!ActivityGridLayout(days: try days(from: "2026-08-03", count: 98)).isDense)
        #expect(ActivityGridLayout(days: try days(from: "2026-08-03", count: 300)).isDense)
    }

    @Test func badDatesFallOut() {
        let layout = ActivityGridLayout(days: [.init(date: "nope", active: true), .init(date: "2026-11-02", active: true), .init(date: "2026-13-45", active: true)])
        #expect(layout.weeks.count == 1)
        #expect(layout.weeks[0].count == 1)
        #expect(ActivityGridLayout(days: []).weeks.isEmpty)
        #expect(ActivityGridLayout(days: [.init(date: "x", active: true)]).weeks.isEmpty)
    }

    @Test func duplicatesAndDisorderDontBreakIt() {
        let layout = ActivityGridLayout(days: [.init(date: "2026-11-03", active: true), .init(date: "2026-11-02", active: true), .init(date: "2026-11-02", active: true)])
        #expect(layout.weeks.flatMap { $0 }.compactMap { $0 }.count == 3)
    }

    @Test func levelsFollowMinutesThenSignIns() {
        func level(_ active: Bool, logins: Int = 0, minutes: Int = 0) -> Int {
            ActivityGridLayout.level(of: .init(date: "", active: active, logins: logins, activeSeconds: minutes * 60))
        }
        #expect(level(false, logins: 9, minutes: 99) == 0)
        #expect(level(true, minutes: 1) == 1)
        #expect(level(true, minutes: 5) == 2)
        #expect(level(true, minutes: 20) == 3)
        #expect(level(true, minutes: 45) == 4)
        #expect(level(true) == 1)
        #expect(level(true, logins: 1) == 2)
        #expect(level(true, logins: 2) == 3)
        #expect(level(true, logins: 3) == 4)
    }

    @Test(arguments: Lang.allCases) func describesADay(_ lang: Lang) throws {
        let s = Strings.of(lang)
        let date = try #require(ActivityDate(iso: "2026-11-02"))
        func text(_ day: AccountActivity.Day) -> String {
            ActivityGridLayout.describe(.init(date: date, day: day, level: 0, isLast: false), s)
        }
        #expect(text(.init(date: "", active: false)).contains(s.profile.notOnline))
        #expect(text(.init(date: "", active: true)).contains(s.profile.online))
        let busy = text(.init(date: "", active: true, logins: 2, activeSeconds: 720))
        #expect(busy.contains(s.profile.loginCount(2)))
        #expect(busy.contains("12 min"))
        #expect(!busy.contains("—"))
    }
}
