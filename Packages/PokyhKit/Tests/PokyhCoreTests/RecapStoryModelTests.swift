import Foundation
import Testing
@testable import PokyhCore

// The detail fixture follows services/recaps.ts recapPokyhFigures and routes/recaps.ts clientRow.
struct RecapStoryModelTests {
    private let f = RecapFormatter(strings: .of(.de))

    private let detailJSON = #"""
    {"recap":{"id":"6f1b2a10-0000-4000-8000-000000000001","title":"Dein Schuljahr","periodFrom":"2025-09-08","periodTo":"2026-06-12",
      "endsAt":null,"sections":["school","absences","grades","exams","classreg","pokyh"],"openedAt":null,"finishedAt":null},
     "pokyh":{"covered":{"from":"2025-09-08","to":"2026-06-12"},"usageConsent":true,"memberSince":"2025-09-10T08:00:00.000Z",
      "kept":{"liveFrom":"2025-09-01","archive":false},
      "totals":{"activeDays":120,"logins":40,"activeSeconds":7200,"visits":300,"screens":900,"longestStreak":14},
      "weekdays":[20,25,30,20,15,5,5],"hours":[0,0,0,0,0,0,0,0,10,20,0,0,0,0,0,0,0,0,0,0,0,0,50,0],
      "platforms":{"phone":100,"desktop":10,"app":90,"web":20},"firstDay":"2025-09-10","busiestDay":null,"pages":[],
      "created":{"todos":12,"todosDone":10,"reminders":3,"comments":2,"ratings":0},
      "favouriteDish":{"name":{"de":"Knödel","it":"","en":"Dumplings"},"stars":5},
      "rank":{"topPercent":4,"group":200}}}
    """#

    private var rich: RecapFigures.Untis {
        let subject = RecapFigures.Ranked(name: "Mathematik", value: 6000, lessons: 120)
        let school = RecapFigures.School(
            days: 180, lessons: 900, minutes: 45000, cancelled: 12, substitutions: 5,
            subjects: [subject], teachers: [.init(name: "Huber", value: 100, lessons: 100)], rooms: [.init(name: "A1", value: 50, lessons: 50)],
            longestDay: .init(date: 20260317, start: 465, end: 1000), earliest: .init(date: 20260302, minutes: 465), latest: .init(date: 20260317, minutes: 1000)
        )
        let absences = RecapFigures.Absences(
            entries: 3, openEntries: 2, missedMinutes: 2700, excusedMinutes: 1350, possibleMinutes: 45000, rate: 6,
            missedDays: 2, bySubject: [.init(name: "Deutsch", value: 120, lessons: 2)], byWeekday: [0, 0, 0, 0, 2700, 0, 0]
        )
        let best = RecapFigures.SubjectAverage(name: "Informatik", average: 9.25, count: 2)
        let grades = RecapFigures.Grades(count: 20, average: 7.5, positive: 18, negative: 2, subjects: [best], best: best, top: .init(value: 9.5, subject: "Informatik", date: 20260212))
        return RecapFigures.Untis(complete: true, weeksLoaded: 40, weeksTotal: 40, school: school, absences: absences, grades: grades, exams: 15, homework: 40, classreg: 2)
    }

    private func input(untis: RecapFigures.Untis?, pokyh: RecapPokyh?, sections: [String] = ["school", "absences", "grades", "exams", "classreg", "pokyh"], name: String = "Emanuel") -> RecapStoryModel.Input {
        RecapStoryModel.Input(title: "Dein Schuljahr", firstName: name, periodFrom: "2025-09-08", periodTo: "2026-06-12", sections: sections, untis: untis, pokyh: pokyh)
    }

    private func detail() throws -> RecapDetail {
        try JSONDecoder().decode(RecapDetail.self, from: Data(detailJSON.utf8))
    }

    // ── From the backend ────────────────────────────────────────────────────

    @Test func decodesTheDetail() throws {
        let d = try detail()
        #expect(d.recap.title == "Dein Schuljahr")
        #expect(d.recap.isNew)
        #expect(d.recap.wantsUntis)
        #expect(d.pokyh?.totals?.activeDays == 120)
        #expect(d.pokyh?.created?.todosDone == 10)
        #expect(d.pokyh?.favouriteDish?.name.en == "Dumplings")
        #expect(d.pokyh?.rank?.topPercent == 4)
    }

    @Test func aPeriodNotCoveredDecodesToo() throws {
        let json = #"{"recap":{"id":"x","title":"T","periodFrom":"2025-09-08","periodTo":"2026-06-12","sections":["pokyh"]},"pokyh":{"covered":null,"usageConsent":false,"memberSince":null,"kept":{"liveFrom":"2025-09-01","archive":false}}}"#
        let d = try JSONDecoder().decode(RecapDetail.self, from: Data(json.utf8))
        #expect(d.pokyh?.totals == nil)
        #expect(!d.recap.wantsUntis)
        #expect(RecapStoryModel.build(input(untis: nil, pokyh: d.pokyh), f).map(\.id) == ["intro", "summary"])
    }

    @Test func aPokyhOnlyRecapHasNoPokyhField() throws {
        let json = #"{"recap":{"id":"x","title":"T","periodFrom":"2025-09-08","periodTo":"2026-06-12","sections":["school"]},"pokyh":null}"#
        #expect(try JSONDecoder().decode(RecapDetail.self, from: Data(json.utf8)).pokyh == nil)
    }

    @Test func decodesTheList() throws {
        let json = #"{"recaps":[{"id":"a","title":"A","periodFrom":"2025-09-08","periodTo":"2026-06-12","endsAt":"2026-07-01T00:00:00.000Z","sections":["school"],"openedAt":"2026-06-20T10:00:00.000Z","finishedAt":"2026-06-20T10:05:00.000Z"}]}"#
        let list = try JSONDecoder().decode(RecapList.self, from: Data(json.utf8))
        #expect(list.recaps.count == 1)
        #expect(!list.recaps[0].isNew)
        #expect(try JSONDecoder().decode(RecapSeen.self, from: Data(#"{"openedAt":"x","finishedAt":null}"#.utf8)).finishedAt == nil)
    }

    // ── Tiers ───────────────────────────────────────────────────────────────

    @Test func absenceTiers() {
        typealias T = RecapStoryModel.Tier
        func tier(_ rate: Double, missed: Int = 10) -> T { RecapStoryModel.absenceTier(rate: rate, missedMinutes: missed) }
        #expect(tier(0, missed: 0) == .legend)
        #expect(tier(1.9) == .great)
        #expect(tier(2) == .good)
        #expect(tier(4.9) == .good)
        #expect(tier(5) == .ok)
        #expect(tier(10) == .meh)
        #expect(tier(15) == .worried)
        #expect(tier(24.9) == .worried)
        #expect(tier(25) == .alarm)
        #expect(tier(90) == .alarm)
    }

    private func absenceSlide(rate: Double, missed: Int) -> RecapStoryModel.Slide? {
        var u = rich
        u.absences?.rate = rate
        u.absences?.missedMinutes = missed
        return RecapStoryModel.build(input(untis: u, pokyh: nil, sections: ["absences"]), f).first { $0.id == "rate" }
    }

    @Test func aTierPicksMoodThemeAndWords() {
        let legend = absenceSlide(rate: 0, missed: 0)
        #expect(legend?.mood == .legend)
        #expect(legend?.theme == .gold)
        #expect(legend?.body.first?.key == "rateBodyLegend")
        #expect(legend?.quip?.key == "quipLegend")
        #expect(legend?.value == .count(0, decimals: 0, suffix: " %"))

        let alarm = absenceSlide(rate: 30, missed: 13500)
        #expect(alarm?.mood == .alarm)
        #expect(alarm?.theme == .alarm)
        #expect(alarm?.place == .right)
        #expect(alarm?.meter?.limit == 25)
        #expect(alarm?.value == .count(30, decimals: 1, suffix: " %"))
    }

    @Test func hoursLeftBeforeTheLimit() {
        let worried = absenceSlide(rate: 20, missed: 9000)
        // A quarter of 45000 minutes less 9000 is 2250 minutes, 37.5 hours, rounded down.
        #expect(worried?.body.first?.vars["left"] == "37")
        #expect(worried?.body.first?.vars["hours"] == "150")
    }

    @Test func gradeTiersPickTheQuip() {
        func slide(_ avg: Double) -> RecapStoryModel.Slide? {
            var u = rich
            u.grades?.average = avg
            return RecapStoryModel.build(input(untis: u, pokyh: nil, sections: ["grades"]), f).first { $0.id == "grades" }
        }
        #expect(slide(9.5)?.quip?.key == "gradesQuipLegend")
        #expect(slide(8)?.quip?.key == "gradesQuipGreat")
        #expect(slide(7)?.quip?.key == "gradesQuipGood")
        #expect(slide(6)?.quip?.key == "gradesQuipOk")
        #expect(slide(5.9)?.quip?.key == "gradesQuipLow")
        #expect(slide(5.9)?.theme == .ember)
    }

    // ── The pages ───────────────────────────────────────────────────────────

    @Test func allPagesInOrder() throws {
        let slides = RecapStoryModel.build(input(untis: rich, pokyh: try detail().pokyh), f)
        #expect(slides.map(\.id) == [
            "intro", "hours", "subject", "teacher", "longest", "cancelled", "rate", "details", "pattern",
            "grades", "best", "exams", "classreg", "days", "time", "made", "rank", "summary",
        ])
    }

    @Test func onlyTheChosenParts() throws {
        let slides = RecapStoryModel.build(input(untis: rich, pokyh: try detail().pokyh, sections: ["grades"]), f)
        #expect(slides.map(\.id) == ["intro", "grades", "best", "summary"])
    }

    @Test func missedTimeComesOffTheHours() throws {
        let slides = RecapStoryModel.build(input(untis: rich, pokyh: nil), f)
        #expect(slides.first { $0.id == "hours" }?.value == .count(705))
        let without = RecapStoryModel.build(input(untis: rich, pokyh: nil, sections: ["school"]), f)
        #expect(without.first { $0.id == "hours" }?.value == .count(750))
    }

    @Test func aPartialYearSaysSo() throws {
        var u = rich
        u.complete = false
        u.weeksLoaded = 37
        let hours = RecapStoryModel.build(input(untis: u, pokyh: nil), f).first { $0.id == "hours" }
        #expect(hours?.body.last == RecapStoryModel.Text("partial", ["n": "3"]))
    }

    @Test func noneOfTheFiguresJustHelloAndGoodbye() {
        #expect(RecapStoryModel.build(input(untis: nil, pokyh: nil), f).map(\.id) == ["intro", "summary"])
        #expect(RecapStoryModel.build(input(untis: .init(), pokyh: nil), f).map(\.id) == ["intro", "summary"])
    }

    @Test func noMissedTimeSkipsTheDetails() {
        var u = rich
        u.absences?.missedMinutes = 0
        u.absences?.rate = 0
        let ids = RecapStoryModel.build(input(untis: u, pokyh: nil, sections: ["absences"]), f).map(\.id)
        #expect(ids == ["intro", "rate", "summary"])
    }

    @Test func withoutARateJustTheHours() {
        var u = rich
        u.absences?.rate = nil
        u.absences?.possibleMinutes = nil
        let ids = RecapStoryModel.build(input(untis: u, pokyh: nil, sections: ["absences"]), f).map(\.id)
        #expect(ids.contains("missed"))
        #expect(!ids.contains("rate"))
    }

    @Test func nothingInPokyhStillGetsAPage() {
        let empty = RecapPokyh(covered: .init(from: "2025-09-08", to: "2026-06-12"), totals: .init(), weekdays: [0, 0, 0, 0, 0, 0, 0])
        #expect(RecapStoryModel.build(input(untis: nil, pokyh: empty), f).map(\.id) == ["intro", "pokyh-none", "summary"])
        // Unless something was made after all.
        let made = RecapPokyh(covered: .init(), totals: .init(), created: .init(todosDone: 1))
        #expect(RecapStoryModel.build(input(untis: nil, pokyh: made), f).map(\.id) == ["intro", "summary"])
    }

    @Test func withoutConsentTheWeekdayInsteadOfTheTime() {
        let p = RecapPokyh(usageConsent: false, totals: .init(activeDays: 10, activeSeconds: 7200, longestStreak: 1), weekdays: [1, 5, 2, 0, 0, 0, 0], hours: nil)
        let slides = RecapStoryModel.build(input(untis: nil, pokyh: p), f)
        #expect(slides.map(\.id) == ["intro", "days", "when", "summary"])
        #expect(slides.first { $0.id == "when" }?.value == .words("Dienstag"))
        #expect(slides.first { $0.id == "days" }?.body.first?.key == "daysBodyOne")
    }

    @Test func aRankOutsideTheTopHalfIsLeftOut() {
        let p = RecapPokyh(totals: .init(activeDays: 1), rank: .init(topPercent: 51))
        #expect(!RecapStoryModel.build(input(untis: nil, pokyh: p), f).map(\.id).contains("rank"))
        let top = RecapPokyh(totals: .init(activeDays: 1), rank: .init(topPercent: 50))
        let slide = RecapStoryModel.build(input(untis: nil, pokyh: top), f).first { $0.id == "rank" }
        #expect(slide?.value == .count(50, prefix: "Top ", suffix: " %", from: 100))
    }

    @Test func busyEnoughOnSchoolDaysGetsTheZap() throws {
        let p = RecapPokyh(totals: .init(activeDays: 120))
        let days = RecapStoryModel.build(input(untis: rich, pokyh: p), f).first { $0.id == "days" }
        #expect(days?.mood == .zap)
        #expect(days?.quip?.key == "daysQuipZap")
    }

    @Test func introGreetsByNameOrNot() {
        let named = RecapStoryModel.build(input(untis: nil, pokyh: nil), f)[0]
        #expect(named.lead == .init("introHello", ["name": "Emanuel"]))
        let anon = RecapStoryModel.build(input(untis: nil, pokyh: nil, name: ""), f)[0]
        #expect(anon.lead?.key == "introHelloAnon")
    }

    // ── Every key has a text ────────────────────────────────────────────────

    private func keys(_ slides: [RecapStoryModel.Slide]) -> [String] {
        slides.flatMap { s -> [String] in
            var out = s.body.map(\.key) + s.list.compactMap(\.labelKey)
            out += [s.lead?.key, s.unit?.key, s.quip?.key].compactMap { $0 }
            return out
        }
    }

    @Test(arguments: Lang.allCases)
    func everyPageResolves(_ lang: Lang) throws {
        let table = Strings.of(lang).recap
        var variants: [RecapStoryModel.Input] = [input(untis: rich, pokyh: try detail().pokyh)]
        // Every tier of the absences and every level of the others.
        for (rate, missed) in [(0.0, 0), (1.0, 10), (3.0, 10), (7.0, 10), (12.0, 10), (20.0, 10), (30.0, 10)] {
            var u = rich
            u.absences?.rate = rate
            u.absences?.missedMinutes = missed
            u.absences?.openEntries = missed == 0 ? 0 : 1
            u.classreg = [0, 2, 9].randomElement()
            u.grades?.average = [9.5, 8.5, 7.5, 6.5, 4.0].randomElement() ?? 7
            variants.append(input(untis: u, pokyh: nil))
        }
        var cancelled = rich
        cancelled.school?.cancelled = 0
        cancelled.school?.substitutions = 1
        cancelled.classreg = 0
        cancelled.absences?.rate = nil
        cancelled.absences?.possibleMinutes = nil
        cancelled.absences?.openEntries = 0
        cancelled.grades?.count = 1
        variants.append(input(untis: cancelled, pokyh: RecapPokyh(covered: .init(), totals: .init(activeDays: 1, activeSeconds: 120, longestStreak: 1), weekdays: [1], hours: [1, 0, 0, 0, 0, 2], rank: .init(topPercent: 20))))
        variants.append(input(untis: nil, pokyh: RecapPokyh(covered: .init(), totals: .init())))

        for variant in variants {
            for key in keys(RecapStoryModel.build(variant, RecapFormatter(strings: .of(lang)))) {
                #expect(table.text(key) != key, "\(key) has no text")
            }
            for item in RecapStoryModel.summaryItems(variant, RecapFormatter(strings: .of(lang))) {
                #expect(table.text(item.label) != item.label)
            }
        }
        for pose in RecapPoster.Pose.allCases { #expect(table.text(pose.textKey) != pose.textKey) }
        for key in ["bannerNew", "bannerSeen", "bannerOpen", "bannerAgain", "start", "next", "back", "done", "replay", "share", "retry", "errorAll", "errorUntis", "customize", "customizeColor", "customizeFigures", "customizeRoom", "customizeName", "shareText", "shareCopy", "shareCopied", "slideOf", "rateLimit", "close", "loading", "loadingShort"] {
            #expect(table.text(key) != key)
        }
    }

    // ── The summary ─────────────────────────────────────────────────────────

    @Test func summaryMostTellingFirst() throws {
        let items = RecapStoryModel.summaryItems(input(untis: rich, pokyh: try detail().pokyh), f)
        #expect(items.map(\.id) == ["hours", "rate", "average", "days", "rank", "subject", "best", "exams", "homework", "missed", "cancelled", "teacher", "streak", "todos", "classreg"])
        #expect(items[0].value == "705")
        #expect(items[1].value == "6,0 %")
        #expect(items[2].value == "7,50")
        #expect(items[4].value == "Top 4 %")
    }

    @Test func summaryRespectsTheSections() {
        let items = RecapStoryModel.summaryItems(input(untis: rich, pokyh: nil, sections: ["grades"]), f)
        #expect(items.map(\.id) == ["average", "best"])
    }

    // ── The reader's language ───────────────────────────────────────────────

    @Test func formatting() {
        #expect(f.date(20260317) == "Dienstag, 17. März")
        #expect(f.day("2025-09-01") == "1. September 2025")
        #expect(f.weekday(0) == "Montag")
        #expect(f.weekday(9) == "Sonntag")
        #expect(f.time(465) == "07:45")
        #expect(f.num(1234) == "1.234")
        #expect(f.num(7.5, digits: 2) == "7,50")
        #expect(RecapFormatter(strings: .of(.en)).num(7.5, digits: 2) == "7.50")
    }

    @Test func dishInTheReadersLanguage() {
        let dish = RecapPokyh.DishName(de: "Knödel", it: "", en: "Dumplings")
        #expect(f.dish(dish) == "Knödel")
        #expect(RecapFormatter(strings: .of(.en)).dish(dish) == "Dumplings")
        #expect(RecapFormatter(strings: .of(.it)).dish(dish) == "Knödel")
    }

    @Test func firstNames() {
        func name(_ person: String?, _ user: String, parent: Bool = false, untis: Bool = true) -> String {
            RecapStoryModel.firstName(personName: person, username: user, isParent: parent, hasUntis: untis)
        }
        #expect(name("Pfeifer Emanuel", "pfeifer.emanuel") == "Emanuel")
        #expect(name("Pfeifer Emanuel", "xy123") == "")
        #expect(name(nil, "pfeifer") == "")
        #expect(name("Pfeifer Emanuel", "pfeifer.emanuel", parent: true) == "")
        #expect(name(nil, "maxi", untis: false) == "maxi")
    }

    // ── The poster ──────────────────────────────────────────────────────────

    @Test func inkReadsOnEveryPosterColor() {
        // Yellow is light: dark text. Blue is dark: white text.
        #expect(RecapPoster.inks(0xFFBF1F).ink == RGB(hex: 0x1A1405))
        #expect(RecapPoster.inks(0x2F6BFF).ink == .white)
        let dark = RecapPoster.inks(0x1B1640)
        #expect(dark.ink == .white)
        // The rows sit a step darker than the card.
        #expect(dark.box.red < RGB(hex: 0x1B1640).red)
        #expect(RecapPoster.inks(0xFFBF1F).box.red < 1)
    }

    @Test func aCardHoldsFiveFigures() {
        let full = ["a", "b", "c", "d", "e"]
        #expect(RecapPoster.toggled(full, "f") == full)
        #expect(RecapPoster.toggled(full, "c") == ["a", "b", "d", "e"])
        #expect(RecapPoster.toggled(["a"], "b") == ["a", "b"])
    }

    @Test func posesGoRound() {
        #expect(RecapPoster.Pose.cool.stepped(-1) == .angel)
        #expect(RecapPoster.Pose.angel.stepped(1) == .cool)
        #expect(RecapPoster.Pose.legend.textKey == "poseLegend")
        #expect(RecapPoster.Pose.zap.mood == .zap)
    }
}
