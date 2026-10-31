import Foundation
import Testing
@testable import PokyhCore

struct RecapFiguresTests {
    private let now = RecapFigures.Now(day: 20260320, minutes: 12 * 60)

    private func lesson(_ start: Int, _ end: Int, _ subject: String, teacher: String = "Huber", room: String = "A1", state: RecapFigures.State = .lesson) -> RecapFigures.Lesson {
        RecapFigures.Lesson(start: start, end: end, subject: subject, teachers: teacher, room: room, state: state)
    }

    /// Monday 2 March and Tuesday 3 March 2026.
    private var week: RecapFigures.Week {
        RecapFigures.Week(at: 1, days: [
            20260302: [lesson(480, 530, "Mathematik"), lesson(530, 580, "Mathematik"), lesson(600, 650, "Deutsch", teacher: "Moser, Huber", room: "B2")],
            20260303: [lesson(480, 530, "Deutsch", teacher: "Moser", state: .substitution), lesson(530, 580, "Turnen", state: .cancelled), lesson(600, 700, "Informatik", state: .exam)],
        ])
    }

    private func source(from: Int = 20260302, to: Int = 20260308, weeks: [String: RecapFigures.Week]? = nil,
                        absences: [RecapFigures.AbsenceIn]? = nil, times: [RecapFigures.TimeIn]? = nil,
                        grades: [RecapFigures.GradeSubjectIn]? = nil, homework: [RecapFigures.HomeworkIn]? = nil,
                        classreg: [Int]? = nil) -> RecapFigures.Sources {
        RecapFigures.Sources(from: from, to: to, now: now, weeks: weeks ?? ["2026-03-02": week], absences: absences, times: times,
                             grades: grades, homework: homework, classreg: classreg)
    }

    // ── Days ────────────────────────────────────────────────────────────────

    @Test func weeksOfAPeriod() {
        #expect(RecapFigures.periodWeeks(from: 20260304, to: 20260312, now: now) == ["2026-03-02", "2026-03-09"])
        // Stops at today, across a month.
        #expect(RecapFigures.periodWeeks(from: 20260225, to: 20260630, now: now) == ["2026-02-23", "2026-03-02", "2026-03-09", "2026-03-16"])
        #expect(RecapFigures.periodWeeks(from: 20260401, to: 20260430, now: now).isEmpty)
    }

    @Test func aSundayBelongsToTheWeekBefore() {
        #expect(RecapFigures.periodWeeks(from: 20260308, to: 20260308, now: now) == ["2026-03-02"])
    }

    @Test func schoolYears() {
        #expect(RecapFigures.schoolYear(of: 20260915) == 2026)
        #expect(RecapFigures.schoolYear(of: 20260630) == 2025)
        #expect(RecapFigures.numOfISO("2026-03-02") == 20260302)
        #expect(RecapFigures.numOfISO("nope") == 0)
    }

    @Test func timesToMinutes() {
        #expect(RecapFigures.toMinutes(745) == 465)
        #expect(RecapFigures.toMinutes(0) == 0)
        #expect(RecapFigures.toMinutes(2400) == 2400)
        #expect(RecapFigures.toMinutes(760) == 760)
    }

    @Test func lessonFromATimetableEntry() {
        let exam = RecapFigures.lesson(startTime: 800, endTime: 850, subject: "M", teachers: "H", room: "A", cancelled: false, exam: true, substitution: true)
        #expect(exam?.state == .exam)
        #expect(exam?.start == 480)
        // Cancelled beats everything else.
        #expect(RecapFigures.lesson(startTime: 800, endTime: 850, subject: "M", teachers: "", room: "", cancelled: true, exam: true, substitution: false)?.state == .cancelled)
        #expect(RecapFigures.lesson(startTime: 800, endTime: 800, subject: "M", teachers: "", room: "", cancelled: false, exam: false, substitution: false) == nil)
        #expect(RecapFigures.lesson(startTime: 800, endTime: 850, subject: "", teachers: "", room: "", cancelled: false, exam: false, substitution: false) == nil)
    }

    @Test func storedWeeksGoStaleAtDifferentSpeeds() {
        let clock = DayClock(zone: TimeZone(secondsFromGMT: 0)!)
        let monday = "2026-03-02"
        let over = clock.parse("2026-03-09")!
        let minute: Int64 = 60_000
        #expect(RecapFigures.weekIsDue(nil, monday: monday, now: over, clock: clock))
        // Read while it was still running: half an hour.
        let early = RecapFigures.Week(at: over - 1000, days: [:])
        #expect(!RecapFigures.weekIsDue(early, monday: monday, now: over + 10 * minute, clock: clock))
        #expect(RecapFigures.weekIsDue(early, monday: monday, now: over + 31 * minute, clock: clock))
        // Read after it, just over: a day.
        let late = RecapFigures.Week(at: over + 1000, days: [:])
        #expect(!RecapFigures.weekIsDue(late, monday: monday, now: over + 23 * 60 * minute, clock: clock))
        #expect(RecapFigures.weekIsDue(late, monday: monday, now: over + 25 * 60 * minute, clock: clock))
        // Long gone: a month.
        let day = 24 * 60 * minute
        let settled = RecapFigures.Week(at: over + 20 * day, days: [:])
        #expect(!RecapFigures.weekIsDue(settled, monday: monday, now: over + 40 * day, clock: clock))
        #expect(RecapFigures.weekIsDue(settled, monday: monday, now: over + 51 * day, clock: clock))
    }

    @Test func weeksSurviveTheDiskCache() throws {
        let data = try JSONEncoder().encode(["2026-03-02": week])
        #expect(try JSONDecoder().decode([String: RecapFigures.Week].self, from: data)["2026-03-02"] == week)
    }

    // ── School ──────────────────────────────────────────────────────────────

    @Test func schoolFigures() throws {
        let u = RecapFigures.untis(source())
        #expect(u.complete)
        #expect(u.weeksLoaded == 1)
        #expect(u.weeksTotal == 1)
        let s = try #require(u.school)
        #expect(s.days == 2)
        // Double lessons count by their length: 3 on Monday, 1 + 2 on Tuesday.
        #expect(s.lessons == 6)
        #expect(s.minutes == 100 + 50 + 50 + 100)
        #expect(s.cancelled == 1)
        #expect(s.substitutions == 1)
        // All three add up to 100 minutes in two lessons, so the name decides.
        #expect(s.subjects.map(\.name) == ["Deutsch", "Informatik", "Mathematik"])
        #expect(s.subjects.first?.value == 100)
        #expect(s.teachers.first?.name == "Huber")
        #expect(s.teachers.map(\.name).contains("Moser"))
        #expect(s.rooms.first?.name == "A1")
        #expect(s.longestDay == RecapFigures.LongestDay(date: 20260303, start: 480, end: 700))
        #expect(s.earliest == RecapFigures.DayTime(date: 20260302, minutes: 480))
        #expect(s.latest == RecapFigures.DayTime(date: 20260303, minutes: 700))
    }

    @Test func lessonsAtTheSameTimeCountOnce() throws {
        let doubled = RecapFigures.Week(at: 1, days: [20260302: [lesson(480, 530, "M"), lesson(480, 530, "M", room: "B"), lesson(500, 560, "E")]])
        let s = try #require(RecapFigures.untis(source(weeks: ["2026-03-02": doubled])).school)
        #expect(s.minutes == 80)
        #expect(s.subjects.first { $0.name == "M" }?.lessons == 1)
    }

    @Test func todayOnlyCountsWhatHasEnded() throws {
        let today = RecapFigures.Week(at: 1, days: [20260320: [lesson(480, 530, "M"), lesson(700, 750, "D")]])
        let u = RecapFigures.untis(source(from: 20260316, to: 20260331, weeks: ["2026-03-16": today]))
        let s = try #require(u.school)
        #expect(s.lessons == 1)
        #expect(s.subjects.map(\.name) == ["M"])
    }

    @Test func missingWeeksMakeItPartial() {
        let u = RecapFigures.untis(source(from: 20260302, to: 20260315))
        #expect(!u.complete)
        #expect(u.weeksTotal == 2)
        #expect(u.weeksLoaded == 1)
        #expect(u.school != nil)
    }

    @Test func noWeekNoSchoolFigures() {
        let u = RecapFigures.untis(source(weeks: [:]))
        #expect(u.school == nil)
        #expect(u.exams == nil)
        #expect(!u.complete)
    }

    // ── Absences ────────────────────────────────────────────────────────────

    @Test func theSchoolsOwnMinutesWin() throws {
        let absence = RecapFigures.AbsenceIn(id: 1, startDate: 20260302, endDate: 20260302, startTime: 800, endTime: 1000, isExcused: true, hours: 2, subjectName: "M")
        let time = RecapFigures.TimeIn(absenceId: 1, minutes: 45, subject: "Deutsch", excused: false, date: 20260302)
        let a = try #require(RecapFigures.untis(source(absences: [absence], times: [time])).absences)
        #expect(a.missedMinutes == 45)
        // The absence decides whether it's excused.
        #expect(a.excusedMinutes == 45)
        #expect(a.entries == 1)
        #expect(a.openEntries == 0)
        #expect(a.bySubject.first?.name == "Deutsch")
        #expect(a.byWeekday[0] == 45)
        #expect(a.missedDays == 1)
    }

    @Test func otherwiseWorkedOutFromTheTimetable() throws {
        let absence = RecapFigures.AbsenceIn(id: 1, startDate: 20260302, endDate: 20260302, startTime: 900, endTime: 1100, isExcused: false, hours: 2, subjectName: nil)
        let a = try #require(RecapFigures.untis(source(absences: [absence])).absences)
        // 09:00 to 11:00 against 08:00–09:40 and 10:00–10:50.
        #expect(a.missedMinutes == 40 + 50)
        #expect(a.openEntries == 1)
        #expect(a.bySubject.map(\.name) == ["Deutsch", "Mathematik"])
    }

    @Test func aDayLongAbsenceTakesEveryLesson() throws {
        let absence = RecapFigures.AbsenceIn(id: 1, startDate: 20260302, endDate: 20260303, startTime: 0, endTime: 0, isExcused: true, hours: 8, subjectName: nil)
        let a = try #require(RecapFigures.untis(source(absences: [absence])).absences)
        #expect(a.missedMinutes == 150 + 150)
        #expect(a.missedDays == 2)
    }

    @Test func aWeekNotLoadedFallsBackToHoursTimesLessonLength() throws {
        let absence = RecapFigures.AbsenceIn(id: 1, startDate: 20260310, endDate: 20260310, startTime: 800, endTime: 900, isExcused: false, hours: 3, subjectName: "Englisch")
        let u = RecapFigures.untis(source(from: 20260302, to: 20260315, absences: [absence]))
        let a = try #require(u.absences)
        // Monday's lessons: the 50-minute span is the usual one here.
        #expect(a.missedMinutes == 150)
        #expect(a.bySubject.first?.name == "Englisch")
        // Not every week there, so no rate.
        #expect(a.rate == nil)
        #expect(a.possibleMinutes == nil)
    }

    @Test func rateAgainstAllLessonsWhenComplete() throws {
        let time = RecapFigures.TimeIn(absenceId: 9, minutes: 30, subject: "", excused: true, date: 20260302)
        let a = try #require(RecapFigures.untis(source(times: [time])).absences)
        #expect(a.possibleMinutes == 300)
        #expect(a.rate == 10)
        // Official rows only: one entry per absence they name. No subject reads as a dash.
        #expect(a.entries == 1)
        #expect(a.openEntries == 0)
        #expect(a.bySubject.first?.name == "—")
    }

    @Test func nothingFromEitherSourceMeansNoFigures() {
        #expect(RecapFigures.untis(source()).absences == nil)
        #expect(RecapFigures.untis(source(absences: [])).absences?.missedMinutes == 0)
    }

    // ── Grades, exams, the rest ─────────────────────────────────────────────

    @Test func gradeFigures() throws {
        let subjects: [RecapFigures.GradeSubjectIn] = [
            .init(subjectName: "Mathematik", grades: [.init(date: 20260303, value: 9), .init(date: 20260304, value: 8), .init(date: 20250101, value: 2)]),
            .init(subjectName: "Deutsch", grades: [.init(date: 20260305, value: 10), .init(date: 20260306, value: 0)]),
            .init(subjectName: "Englisch", grades: [.init(date: 20260305, value: 5)]),
        ]
        let g = try #require(RecapFigures.untis(source(grades: subjects)).grades)
        #expect(g.count == 4)
        #expect(g.average == 8)
        #expect(g.positive == 3)
        #expect(g.negative == 1)
        #expect(g.subjects.map(\.name) == ["Deutsch", "Mathematik", "Englisch"])
        // The best needs two grades when anyone has two.
        #expect(g.best?.name == "Mathematik")
        #expect(g.top == RecapFigures.TopGrade(value: 10, subject: "Deutsch", date: 20260305))
    }

    @Test func noGradesInThePeriod() throws {
        let g = try #require(RecapFigures.untis(source(grades: [.init(subjectName: "M", grades: [.init(date: 20250101, value: 9)])])).grades)
        #expect(g.count == 0)
        #expect(g.best == nil)
    }

    @Test func aSubjectInTwoLessonsIsOneSubject() throws {
        let g = try #require(RecapFigures.untis(source(grades: [
            .init(subjectName: "M", grades: [.init(date: 20260303, value: 8)]),
            .init(subjectName: "M", grades: [.init(date: 20260304, value: 6)]),
        ])).grades)
        #expect(g.subjects == [RecapFigures.SubjectAverage(name: "M", average: 7, count: 2)])
    }

    @Test func examsHomeworkAndRegisterWithinThePeriodOnly() {
        let u = RecapFigures.untis(source(
            homework: [.init(id: 1, dueDate: 20260303), .init(id: 1, dueDate: 20260303), .init(id: 2, dueDate: 20260501), .init(id: 3, dueDate: 20260304)],
            classreg: [20260302, 20260305, 20260601]
        ))
        #expect(u.exams == 1)
        #expect(u.homework == 2)
        #expect(u.classreg == 2)
    }

    @Test func aSourceThatFailedStaysNil() {
        let u = RecapFigures.untis(source())
        #expect(u.homework == nil)
        #expect(u.classreg == nil)
        #expect(u.grades == nil)
    }

    @Test func nowFromTheClock() {
        let clock = DayClock(zone: TimeZone(secondsFromGMT: 3600)!)
        let now = RecapFigures.Now(ms: clock.parse("2026-03-20T07:45:00")!, clock: clock)
        #expect(now == RecapFigures.Now(day: 20260320, minutes: 465))
    }
}
