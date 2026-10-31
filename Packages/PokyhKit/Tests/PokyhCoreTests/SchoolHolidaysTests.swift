import Foundation
import Testing
@testable import PokyhCore

// As one school really has them (backend tests/webuntisHolidays.test.mjs).
private var school: [[String: Any]] { [
    ["id": 1, "name": "Ferien1", "longName": "31.10.2022-31.10.2022", "startDate": 20261101, "endDate": 20261108],
    ["id": 2, "name": "1.11.", "longName": "1.11.2026", "startDate": 20261101, "endDate": 20261101],
    ["id": 3, "name": "Ferien8", "longName": "23.12.2023-23.12.2023", "startDate": 20261207, "endDate": 20261208],
    ["id": 4, "name": "8.12.", "longName": "8.12.2022", "startDate": 20261208, "endDate": 20261208],
    ["id": 5, "name": "Ferien5", "longName": "24.12.2026-24.12.2026", "startDate": 20261224, "endDate": 20270106],
    ["id": 6, "name": "6.1.", "longName": "6.1.2027", "startDate": 20270106, "endDate": 20270106],
    ["id": 7, "name": "Faschingsferien", "longName": "Faschingsferien", "startDate": 20270208, "endDate": 20270214],
    ["id": 8, "name": "Ferien1", "longName": "x", "startDate": 20251027, "endDate": 20251102],
] }

private let names = ["autumn": "Herbstferien", "christmas": "Weihnachtsferien", "easter": "Osterferien",
                     "summer": "Sommerferien", "carnival": "Faschingsferien", "immaculate": "Mariä Empfängnis",
                     "dayOff": "Schulfrei", "break": "Ferien"]

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))!
}

struct SchoolHolidaysTests {
    @Test func placeholdersAreToldFromRealNames() {
        for name in ["Ferien1", "Ferien", "8.12.", "25/5/2026", "31.10.2022-31.10.2022", "Feiertag 2", ""] {
            #expect(HolidayList.isPlaceholder(name), "\(name)")
        }
        for name in ["Weihnachtsferien", "Faschingsferien", "Tag der Republik"] {
            #expect(!HolidayList.isPlaceholder(name), "\(name)")
        }
    }

    @Test func overlappingEntriesBecomeOneBreakPastOnesAreLeftOut() {
        let holidays = HolidayList.read(school, from: "2026-09-01")
        #expect(holidays.map(\.start) == ["2026-11-01", "2026-12-07", "2026-12-24", "2027-02-08"])
        #expect(holidays.map(\.end) == ["2026-11-08", "2026-12-08", "2027-01-06", "2027-02-14"])
        #expect(holidays[0].names.isEmpty)
        #expect(holidays[3].names == ["Faschingsferien"])
    }

    @Test func adjoiningDaysJoinAGapDoesNot() {
        let holidays = HolidayList.read([
            ["name": "A", "startDate": 20270101, "endDate": 20270102],
            ["name": "B", "startDate": 20270103, "endDate": 20270103],
            ["name": "C", "startDate": 20270105, "endDate": 20270105],
        ], from: "2026-01-01")
        #expect(holidays.map(\.end) == ["2027-01-03", "2027-01-05"])
        #expect(holidays[0].names == ["A", "B"])
        #expect(HolidayList.read(nil, from: "2026-01-01").isEmpty)
    }

    @Test func monthEndsJoinToo() {
        let holidays = HolidayList.read([
            ["name": "A", "startDate": 20270131, "endDate": 20270131],
            ["name": "B", "startDate": 20270201, "endDate": 20270201],
        ], from: "2026-01-01")
        #expect(holidays.count == 1)
    }

    @Test func aRealNameWinsOverTheDate() {
        let holidays = HolidayList.read(school, from: "2026-09-01")
        #expect(SchoolHolidays.name(onDay: 20270210, in: holidays, names: names) == "Faschingsferien")
    }

    @Test func aPlaceholderIsNamedByWhenItIs() {
        let holidays = HolidayList.read(school, from: "2026-09-01")
        #expect(SchoolHolidays.name(onDay: 20261104, in: holidays, names: names) == "Herbstferien")
        #expect(SchoolHolidays.name(onDay: 20261228, in: holidays, names: names) == "Weihnachtsferien")
        // Two days around a public holiday are that holiday.
        #expect(SchoolHolidays.name(onDay: 20261207, in: holidays, names: names) == "Mariä Empfängnis")
    }

    @Test func aDayOutsideEveryBreakHasNoName() {
        let holidays = HolidayList.read(school, from: "2026-09-01")
        #expect(SchoolHolidays.name(onDay: 20261110, in: holidays, names: names) == nil)
        #expect(HolidayList.on(20261110, in: holidays) == nil)
        #expect(HolidayList.on(0, in: holidays) == nil)
    }

    @Test func aWeekTakesTheBreakThatCoversMostOfIt() {
        let holidays = HolidayList.read(school, from: "2026-09-01")
        #expect(SchoolHolidays.name(ofDays: [20261109, 20261110], in: holidays, names: names) == nil)
        #expect(SchoolHolidays.name(ofDays: [20270207, 20270208], in: holidays, names: names) == "Faschingsferien")

        let two = [SchoolHoliday(start: "2026-10-26", end: "2026-10-26", names: ["Ein Tag"]),
                   SchoolHoliday(start: "2026-10-28", end: "2026-10-30", names: ["Drei Tage"])]
        let week = [20261026, 20261027, 20261028, 20261029, 20261030, 20261031]
        #expect(SchoolHolidays.name(ofDays: week, in: two, names: names) == "Drei Tage")
    }

    @Test func aWeekCanAskForMoreThanOneFreeDay() {
        // A room nobody uses in a week with one free Wednesday isn't on holiday all week.
        let one = [SchoolHoliday(start: "2026-10-28", end: "2026-10-28", names: ["Schulfrei"])]
        let week = [20261026, 20261027, 20261028, 20261029, 20261030, 20261031]
        #expect(SchoolHolidays.name(ofDays: week, in: one, names: names, atLeast: 5) == nil)
        #expect(SchoolHolidays.name(ofDays: week, in: one, names: names) == "Schulfrei")
        let all = [SchoolHoliday(start: "2026-10-26", end: "2026-10-30", names: ["Ferien im Herbst"])]
        #expect(SchoolHolidays.name(ofDays: week, in: all, names: names, atLeast: 5) == "Ferien im Herbst")
    }

    @Test func easterAndTheBreaksAroundIt() {
        #expect(SchoolHolidays.easterSunday(2026) == date(2026, 4, 5))
        #expect(SchoolHolidays.easterSunday(2027) == date(2027, 3, 28))
        #expect(SchoolHolidays.key(from: date(2026, 4, 2), to: date(2026, 4, 7)) == "easter")
        #expect(SchoolHolidays.publicHoliday(on: date(2026, 4, 6)) == "easterMonday")
        #expect(SchoolHolidays.publicHoliday(on: date(2026, 11, 1)) == "allSaints")
        #expect(SchoolHolidays.publicHoliday(on: date(2026, 11, 2)) == nil)
    }

    @Test func aWholeEmptyWeekGoesByTheTimeOfYear() {
        // Monday 3 August and Monday 4 January.
        #expect(SchoolHolidays.weekKey(date(2026, 8, 3)) == "summer")
        #expect(SchoolHolidays.weekKey(date(2027, 1, 4)) == "christmas")
        #expect(SchoolHolidays.key(from: date(2026, 10, 12), to: date(2026, 10, 12)) == "dayOff")
    }

    @Test func listSurvivesTheDiskCache() throws {
        let holidays = HolidayList.read(school, from: "2026-09-01")
        let copy = try JSONDecoder().decode([SchoolHoliday].self, from: JSONEncoder().encode(holidays))
        #expect(copy == holidays)
    }
}
