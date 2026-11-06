import Foundation
import Testing
@testable import PokyhCore

// Values a server can send and nobody thought of. Each of these used to trap, see POKYHUITests'
// BadDataTests for the same thing through the screens.
struct BadServerDataTests {
    // ── Doubles into Ints ───────────────────────────────────────────────────

    @Test func saturatingIntNeverTraps() {
        #expect(Int(saturating: .nan) == 0)
        #expect(Int(saturating: .infinity) == .max)
        #expect(Int(saturating: -.infinity) == .min)
        #expect(Int(saturating: 1e300) == .max)
        #expect(Int(saturating: -1e300) == .min)
        #expect(Int(saturating: Double(Int.max)) == .max)
        #expect(Int(saturating: 8.9) == 8)
        #expect(Int(saturating: -8.9) == -8)
    }

    @Test func gradesPrintWhateverTheyAre() {
        #expect(MarkText.string(8) == "8")
        #expect(MarkText.string(8.5) == "8,5")
        #expect(MarkText.string(8.25) == "8,25")
        #expect(MarkText.string(.nan) == "–")
        #expect(MarkText.string(.infinity) == "–")
        #expect(MarkText.string(1e300) != "")
        #expect(MarkText.string(Double.greatestFiniteMagnitude) != "")
    }

    @Test func onlyRealNumbersCountAsGrades() {
        #expect(MarkText.isUsable(8.5))
        #expect(MarkText.isUsable(100))
        #expect(!MarkText.isUsable(.nan))
        #expect(!MarkText.isUsable(.infinity))
        #expect(!MarkText.isUsable(1e300))
    }

    // ── Dates and times ─────────────────────────────────────────────────────

    @Test(arguments: Lang.allCases) func monthZeroAndThirteenHaveNoName(_ lang: Lang) {
        let c = Strings.of(lang).common
        for month in [0, 13, -1, 99, Int.max, Int.min + 1] {
            _ = c.dateLong(1, month, 2026)
            _ = c.dayMonth(1, month)
            _ = c.dayMonthShort(1, month)
        }
        #expect(!c.dayMonth(1, 1).isEmpty)
        #expect(c.dayMonth(1, 12).contains(c.months[11]))
    }

    @Test func untisRangesKeepOutWhatWouldOverflow() {
        #expect(UntisRange.day(20261103) == 20261103)
        #expect(UntisRange.day(.max) == 0)
        #expect(UntisRange.day(-1) == 0)
        #expect(UntisRange.day(nil) == 0)
        #expect(UntisRange.clock(750) == 750)
        #expect(UntisRange.clock(.max) == 0)
        #expect(UntisRange.clock(.min) == 0)
        #expect(UntisRange.amount(.max) == 1_000_000)
        #expect(UntisRange.amount(-5) == 0)
        // Multiplied into a sort key, the way the excuses and absences do.
        _ = UntisRange.day(.max) * 10_000 + UntisRange.clock(.max)
    }

    @Test func clockShapesComeOutAsHHMM() {
        #expect(UntisRange.hhmm(750) == 750)
        #expect(UntisRange.hhmm(470) == 750)
        #expect(UntisRange.hhmm(Int.max) == 0)
        #expect(UntisRange.hhmm(Int.min) == 0)
        #expect(UntisRange.hhmm(-5) == 0)
    }

    // ── The bell ────────────────────────────────────────────────────────────

    @Test(arguments: [Double.nan, .infinity, -.infinity, 1e300, -1e300])
    func aBellRowWithAnAbsurdGrade(_ value: Double) {
        var item = BellFeed.Item(key: "k", source: .grades, kind: .grade, at: 1_700_000_000_000, allDay: false, title: "t", target: .todos)
        item.value = value
        let text = BellFeed.rowText(item, now: 1_700_000_100_000, strings: .of(.de))
        #expect(!text.title.isEmpty)
    }

    // ── Popups ──────────────────────────────────────────────────────────────

    @Test(arguments: [Int.min, -1, 0, 1, Int.max])
    func anAbsurdShowCount(_ count: Int) {
        let clock = DayClock(zone: TimeZone(secondsFromGMT: 0)!)
        let popup = AnnouncementPopup(id: "p", revision: 1, title: "t", html: "", showCount: count,
                                      startsAt: "2026-11-01T00:00:00.000Z", endsAt: "2099-11-08T00:00:00.000Z", slotMs: 86_400_000)
        let now = clock.parse("2026-11-03T00:00:00.000Z")!
        #expect(PopupSchedule.currentSlot(popup, now: now, clock: clock) != nil)
        _ = PopupSchedule.isDue(popup, seen: [:], now: now, clock: clock)
        _ = PopupSchedule.withSeen([:], popups: [popup], now: now, clock: clock)
    }

    @Test func anAbsurdSlot() {
        let clock = DayClock(zone: TimeZone(secondsFromGMT: 0)!)
        let popup = AnnouncementPopup(id: "p", revision: 1, title: "t", html: "", showCount: 3,
                                      startsAt: "2026-11-01T00:00:00.000Z", endsAt: nil, slotMs: .max)
        let now = clock.parse("2026-11-03T00:00:00.000Z")!
        #expect(PopupSchedule.currentSlot(popup, now: now, clock: clock) == 0)
    }

    // ── Recap ───────────────────────────────────────────────────────────────

    @Test(arguments: [Int.max, Int.min, 0, -1])
    func aRecapWithAbsurdFigures(_ n: Int) throws {
        let json = #"""
        {"covered":{"from":"2026-13-45","to":"0000-00-00"},"usageConsent":true,
         "totals":{"activeDays":N,"activeSeconds":N,"longestStreak":N},
         "weekdays":[N,N,N,N,N,N,N,N,N],"hours":[N,N,N],
         "created":{"todosDone":N,"reminders":N,"comments":N,"ratings":N},
         "rank":{"topPercent":N}}
        """#.replacingOccurrences(of: "N", with: String(n))
        let pokyh = try JSONDecoder().decode(RecapPokyh.self, from: Data(json.utf8))
        let input = RecapStoryModel.Input(title: "t", firstName: "x", periodFrom: "2026-13-45", periodTo: "2026-00-00",
                                          sections: ["school", "absences", "grades", "exams", "classreg", "pokyh"], untis: nil, pokyh: pokyh)
        _ = RecapStoryModel.build(input, RecapFormatter(strings: .of(.de)))
        _ = RecapStoryModel.summaryItems(input, RecapFormatter(strings: .of(.de)))
    }

    @Test(arguments: [Int.max, 1_000_000, 0])
    func aRecapWithAbsurdUntisFigures(_ n: Int) {
        let ranked = RecapFigures.Ranked(name: "M", value: n, lessons: n)
        let school = RecapFigures.School(days: n, lessons: n, minutes: n, cancelled: n, substitutions: n, subjects: [ranked], teachers: [ranked], rooms: [ranked],
                                         longestDay: .init(date: 20260317, start: 465, end: 1000), earliest: .init(date: 20260302, minutes: n), latest: .init(date: 20261345, minutes: n))
        let absences = RecapFigures.Absences(entries: n, openEntries: n, missedMinutes: n, excusedMinutes: n, possibleMinutes: n, rate: Double(n), missedDays: n,
                                             bySubject: [ranked], byWeekday: [n, n, n, n, n, n, n])
        let best = RecapFigures.SubjectAverage(name: "I", average: 1e300, count: n)
        let grades = RecapFigures.Grades(count: n, average: .greatestFiniteMagnitude, positive: n, negative: n, subjects: [best], best: best, top: .init(value: .greatestFiniteMagnitude, subject: "I", date: 0))
        let untis = RecapFigures.Untis(complete: true, weeksLoaded: n, weeksTotal: n, school: school, absences: absences, grades: grades, exams: n, homework: n, classreg: n)
        let input = RecapStoryModel.Input(title: "t", firstName: "x", periodFrom: "2026-01-01", periodTo: "2026-06-01",
                                          sections: ["school", "absences", "grades", "exams", "classreg", "pokyh"], untis: untis, pokyh: nil)
        _ = RecapStoryModel.build(input, RecapFormatter(strings: .of(.de)))
        _ = RecapStoryModel.summaryItems(input, RecapFormatter(strings: .of(.de)))
    }

    @Test func aRecapFormatterWithAbsurdDays() {
        let f = RecapFormatter(strings: .of(.de))
        for n in [0, 20261345, 20260000, 99999999, -1, Int.max] {
            _ = f.date(n)
            _ = f.day(String(n))
        }
        for i in [Int.min, -1, 7, 99, Int.max] { _ = f.weekday(i) }
    }
}
