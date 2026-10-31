import Foundation
import Testing
@testable import PokyhCore

private struct Span: AbsenceSpan {
    var startDate = 20261103
    var endDate = 20261103
    var startTime = 0
    var endTime = 0
    var isExcused = false
}

private let day = 20261103
private func minutes(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }

struct AbsenceMarksTests {
    @Test func aLessonNotOverYetIsReportedInAdvance() {
        let a = [Span(startTime: 800, endTime: 1200)]
        #expect(AbsenceMarks.mark(a, date: day, start: minutes(8), end: minutes(9), nowDate: day - 1, nowMinute: 0) == .preExcused)
        // The same day, still running.
        #expect(AbsenceMarks.mark(a, date: day, start: minutes(8), end: minutes(9), nowDate: day, nowMinute: minutes(8, 30)) == .preExcused)
    }

    @Test func overIsExcusedOrNotAsWebUntisHasIt() {
        let open = [Span(startTime: 800, endTime: 1200)]
        let excused = [Span(startTime: 800, endTime: 1200, isExcused: true)]
        #expect(AbsenceMarks.mark(open, date: day, start: minutes(8), end: minutes(9), nowDate: day, nowMinute: minutes(9)) == .absent)
        #expect(AbsenceMarks.mark(excused, date: day, start: minutes(8), end: minutes(9), nowDate: day + 1, nowMinute: 0) == .excused)
        // One of two still open: not excused.
        let mixed = open + excused
        #expect(AbsenceMarks.mark(mixed, date: day, start: minutes(8), end: minutes(9), nowDate: day + 1, nowMinute: 0) == .absent)
    }

    @Test func aFewMinutesLateMarksNothing() {
        let late = [Span(startTime: 800, endTime: 810)]
        #expect(AbsenceMarks.mark(late, date: day, start: minutes(8), end: minutes(9), nowDate: day + 1, nowMinute: 0) == nil)
        let quarter = [Span(startTime: 800, endTime: 815)]
        #expect(AbsenceMarks.mark(quarter, date: day, start: minutes(8), end: minutes(9), nowDate: day + 1, nowMinute: 0) == .absent)
        // A lesson shorter than the threshold counts when all of it is covered.
        let short = [Span(startTime: 800, endTime: 810)]
        #expect(AbsenceMarks.mark(short, date: day, start: minutes(8), end: minutes(8, 10), nowDate: day + 1, nowMinute: 0) == .absent)
    }

    @Test func noTimesMeanTheWholeDayAcrossSeveralDays() {
        let week = [Span(startDate: 20261102, endDate: 20261104)]
        #expect(AbsenceMarks.mark(week, date: day, start: minutes(8), end: minutes(9), nowDate: day + 10, nowMinute: 0) == .absent)
        #expect(AbsenceMarks.mark(week, date: 20261105, start: minutes(8), end: minutes(9), nowDate: day + 10, nowMinute: 0) == nil)
        // No dates at all is no absence.
        #expect(AbsenceMarks.mark([Span(startDate: 0, endDate: 0)], date: day, start: minutes(8), end: minutes(9), nowDate: day, nowMinute: 0) == nil)
    }

    @Test func theLessonAbsenceListsWhatCoversIt() throws {
        let a = [Span(startTime: 800, endTime: 900), Span(startTime: 1400, endTime: 1500)]
        let found = try #require(AbsenceMarks.lessonAbsence(a, date: day, start: minutes(8), end: minutes(9), nowDate: day + 1, nowMinute: 0))
        #expect(found.mark == .absent)
        #expect(found.covering.count == 1)
    }

    @Test func aBandStartsWhereTheAbsenceDoesNotWhereTheLessonDoes() {
        let a = [Span(startTime: 1000, endTime: 1300)]
        let bands = AbsenceMarks.bands(a, date: day, lessons: [(minutes(9, 30), minutes(10, 20))], nowDate: day + 1, nowMinute: 0)
        #expect(bands == [AbsenceBand(startMinute: minutes(10), endMinute: minutes(10, 20), mark: .absent)])
    }

    @Test func aBandRunsThroughBreaksButAnAttendedLessonEndsIt() {
        let lessons = [(minutes(8), minutes(9)), (minutes(9), minutes(10)), (minutes(14), minutes(15))]
            .map { (start: $0.0, end: $0.1) }
        let wholeDay = [Span(startTime: 800, endTime: 1500)]
        #expect(AbsenceMarks.bands(wholeDay, date: day, lessons: lessons, nowDate: day + 1, nowMinute: 0)
            == [AbsenceBand(startMinute: minutes(8), endMinute: minutes(15), mark: .absent)])

        // Back for the second lesson, gone again after it.
        let twoStretches = [Span(startTime: 800, endTime: 900), Span(startTime: 1400, endTime: 1500)]
        #expect(AbsenceMarks.bands(twoStretches, date: day, lessons: lessons, nowDate: day + 1, nowMinute: 0) == [
            AbsenceBand(startMinute: minutes(8), endMinute: minutes(9), mark: .absent),
            AbsenceBand(startMinute: minutes(14), endMinute: minutes(15), mark: .absent),
        ])
    }

    @Test func aChangeOfMarkStartsANewBand() {
        let lessons = [(start: minutes(8), end: minutes(9)), (start: minutes(9), end: minutes(10))]
        let a = [Span(startTime: 800, endTime: 1000)]
        // The first lesson is over, the second still running.
        let bands = AbsenceMarks.bands(a, date: day, lessons: lessons, nowDate: day, nowMinute: minutes(9, 30))
        #expect(bands.map(\.mark) == [.absent, .preExcused])
    }

    @Test func noAbsencesNoBands() {
        #expect(AbsenceMarks.bands([Span](), date: day, lessons: [(start: 1, end: 2)], nowDate: day, nowMinute: 0).isEmpty)
    }

    @Test func rangeTextReadsLikeAndroid() {
        #expect(AbsenceMarks.rangeText(Span(startTime: 1000, endTime: 1305), wholeDay: "Ganzer Tag") == "10:00 – 13:05")
        #expect(AbsenceMarks.rangeText(Span(), wholeDay: "Ganzer Tag") == "Ganzer Tag")
        #expect(AbsenceMarks.rangeText(Span(startDate: 20261102, endDate: 20261104), wholeDay: "x") == "02.11. – 04.11.")
        #expect(AbsenceMarks.rangeText(Span(startDate: 20261102, endDate: 20261104, startTime: 800, endTime: 1200), wholeDay: "x")
            == "02.11. 08:00 – 04.11. 12:00")
    }
}
