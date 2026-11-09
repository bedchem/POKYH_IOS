import Foundation
import Testing
@testable import PokyhCore

// The fixtures are what pokyh-backend answers: routes/popups.ts GET /popups/active (contentHtml from
// services/popupRender.ts), routes/recaps.ts clientRow and services/recaps.ts recapPokyhFigures.
// Every date is toISOString(), so with milliseconds; whatever may be null is null somewhere here.
struct EngagementFeedTests {
    private let clock = DayClock(zone: TimeZone(secondsFromGMT: 0)!)

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    // ── Popups ──────────────────────────────────────────────────────────────

    @Test func readsThePopupFeed() throws {
        let feed = try JSONDecoder().decode(AnnouncementPopupFeed.self, from: fixture("popups-active"))
        // The one without an id is the only one lost.
        #expect(feed.popups.map(\.title) == ["Neue Mensa-Zeiten", "Skitag", "Elternsprechtag", "Seltsam"])

        let once = feed.popups[0]
        #expect(once.showCount == 1 && once.startsAt == nil && once.endsAt == nil && once.slotMs == nil)
        #expect(once.html.contains("<table>") && once.html.contains(#"target="_blank""#))

        let weekly = feed.popups[1]
        #expect(weekly.key == "0b7d2c1e-4f3a-4c7e-9a51-2f6b8e1d0a02:3")
        #expect(weekly.slotMs == 86_400_000)
        #expect(clock.parse(weekly.startsAt) == clock.parse("2026-11-01T00:00:00Z"))

        // Wrong types fall back field by field.
        let odd = feed.popups[3]
        #expect(odd.revision == 2 && odd.showCount == 1 && odd.html.isEmpty)
        #expect(odd.startsAt == nil && odd.slotMs == nil)
    }

    @Test func thePopupsOfTheFeedAreDue() throws {
        let popups = try JSONDecoder().decode(AnnouncementPopupFeed.self, from: fixture("popups-active")).popups
        let now = try #require(clock.parse("2026-11-02T08:00:00.000Z"))
        // Inside every window, nothing seen yet: all of them.
        #expect(popups.filter { PopupSchedule.isDue($0, seen: [:], now: now, clock: clock) }.count == 4)
        #expect(PopupSchedule.currentSlot(popups[1], now: now, clock: clock) == 1)

        let seen = PopupSchedule.withSeen([:], popups: popups, now: now, clock: clock)
        #expect(popups.allSatisfy { !PopupSchedule.isDue($0, seen: seen, now: now + 60_000, clock: clock) })
        // The next day only the weekly one is back; the "once" ones never are.
        let tomorrow = now + 86_400_000
        #expect(popups.filter { PopupSchedule.isDue($0, seen: seen, now: tomorrow, clock: clock) }.map(\.title) == ["Skitag"])
        // After its window nothing shows, not even the slot it never got.
        let after = try #require(clock.parse("2026-11-08T00:00:00.000Z"))
        #expect(!PopupSchedule.isDue(popups[1], seen: [:], now: after, clock: clock))
    }

    @Test func aPopupOnlyNeedsItsId() throws {
        let json = #"{"now":"2026-11-02T08:00:00.000Z","popups":[{"id":"x"}]}"#
        let popup = try #require(JSONDecoder().decode(AnnouncementPopupFeed.self, from: Data(json.utf8)).popups.first)
        #expect(popup.key == "x:1" && popup.showCount == 1)
        #expect(PopupSchedule.isDue(popup, seen: [:], now: 0, clock: clock))
    }

    @Test func aSlotPastInt32Stays() throws {
        // A month in one slot, more than the watch's Int holds.
        let json = #"{"popups":[{"id":"m","revision":1,"title":"t","html":"","showCount":2,"startsAt":"2026-01-01T00:00:00.000Z","endsAt":"2026-03-02T00:00:00.000Z","slotMs":2592000000}]}"#
        let popup = try #require(JSONDecoder().decode(AnnouncementPopupFeed.self, from: Data(json.utf8)).popups.first)
        #expect(popup.slotMs == 2_592_000_000)
    }

    @Test func aPopupListThatIsNoListThrows() {
        // Thrown, not empty: the app then keeps what it had.
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AnnouncementPopupFeed.self, from: Data(#"{"popups":{"id":"x"}}"#.utf8))
        }
    }

    // ── Recaps ──────────────────────────────────────────────────────────────

    @Test func readsTheRecapList() throws {
        let recaps = try JSONDecoder().decode(RecapList.self, from: fixture("recaps-list")).recaps
        #expect(recaps.map(\.title) == ["Dein Halbjahr", "Dein Schuljahr", "Nur POKYH"])
        #expect(recaps[0].sections == Recap.allSections)
        #expect(recaps[0].isNew && recaps[0].openedAt == nil && recaps[0].wantsUntis)
        #expect(!recaps[1].isNew && recaps[1].sections == ["grades", "pokyh"])
        #expect(recaps[2].isNew && recaps[2].openedAt != nil && !recaps[2].wantsUntis)
        // The one that opens by itself is the newest never opened anywhere, like the web's dueAutoRecap.
        #expect(recaps.first { $0.openedAt == nil }?.title == "Dein Halbjahr")
    }

    @Test func sectionsReadLikeTheServerStoresThem() throws {
        func sections(_ raw: String) throws -> [String] {
            let json = #"{"id":"a","title":"A","periodFrom":"2026-01-07","periodTo":"2026-02-28","sections":\#(raw)}"#
            return try JSONDecoder().decode(Recap.self, from: Data(json.utf8)).sections
        }
        #expect(try sections(#"["pokyh","school"]"#) == ["school", "pokyh"])
        #expect(try sections(#""school,grades""#) == ["school", "grades"])
        // Empty or unknown only: every part, as parseSections says.
        #expect(try sections("[]") == Recap.allSections)
        #expect(try sections(#"["later"]"#) == Recap.allSections)
        #expect(try sections(#"["later","exams"]"#) == ["exams"])
        #expect(try sections("null") == Recap.allSections)
    }

    @Test func readsTheRecapDetail() throws {
        let detail = try JSONDecoder().decode(RecapDetail.self, from: fixture("recap-detail"))
        #expect(detail.recap.openedAt == "2026-11-02T08:00:00.000Z")
        let p = try #require(detail.pokyh)
        #expect(p.covered == .init(from: "2026-09-08", to: "2026-10-31"))
        #expect(p.usageConsent)
        #expect(p.totals == .init(activeDays: 38, activeSeconds: 41820, longestStreak: 11))
        #expect(p.weekdays == [8, 9, 7, 8, 5, 1, 0])
        #expect(p.hours?.count == 24)
        #expect(p.created == .init(todosDone: 7, reminders: 2, comments: 3, ratings: 4))
        #expect(p.favouriteDish?.name.it == "Canederli agli spinaci")
        #expect(p.rank?.topPercent == 12)

        let input = RecapStoryModel.Input(title: detail.recap.title, firstName: "Anna", periodFrom: detail.recap.periodFrom,
                                          periodTo: detail.recap.periodTo, sections: detail.recap.sections, untis: nil, pokyh: p)
        let f = RecapFormatter(strings: .of(.de))
        #expect(RecapStoryModel.build(input, f).map(\.id) == ["intro", "days", "time", "made", "rank", "summary"])
        #expect(RecapStoryModel.summaryItems(input, f).map(\.id).contains("rank"))
    }

    @Test func theFiguresOfAQuietAccount() throws {
        // Nothing in the period: no rank, no dish, no busiest day, hours all zero without consent.
        let json = #"""
        {"recap":{"id":"a","title":"A","periodFrom":"2026-09-08","periodTo":"2026-10-31","endsAt":null,"sections":["pokyh"],"openedAt":null,"finishedAt":null},
         "pokyh":{"covered":{"from":"2026-09-08","to":"2026-10-31"},"usageConsent":false,"memberSince":null,"kept":{"liveFrom":"2026-09-01","archive":false},
          "totals":{"activeDays":0,"logins":0,"activeSeconds":0,"visits":0,"screens":0,"longestStreak":0},
          "weekdays":[0,0,0,0,0,0,0],"hours":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
          "platforms":{"phone":0,"desktop":0,"app":0,"web":0},"firstDay":null,"busiestDay":null,"pages":[],
          "created":{"todos":0,"todosDone":0,"reminders":0,"comments":0,"ratings":0},"favouriteDish":null,"rank":null}}
        """#
        let detail = try JSONDecoder().decode(RecapDetail.self, from: Data(json.utf8))
        let p = try #require(detail.pokyh)
        #expect(p.favouriteDish == nil && p.rank == nil && p.totals?.activeDays == 0)
        let input = RecapStoryModel.Input(title: "A", firstName: "", periodFrom: "2026-09-08", periodTo: "2026-10-31",
                                          sections: ["pokyh"], untis: nil, pokyh: p)
        #expect(RecapStoryModel.build(input, RecapFormatter(strings: .of(.de))).map(\.id) == ["intro", "pokyh-none", "summary"])
    }

    @Test func aBrokenFigureCostsOnlyItself() throws {
        let json = #"""
        {"recap":{"id":"a","title":"A","periodFrom":"2026-09-08","periodTo":"2026-10-31","sections":["pokyh"]},
         "pokyh":{"covered":"2026-09-08","usageConsent":"yes","totals":{"activeDays":12.0,"activeSeconds":"600","longestStreak":null},
          "weekdays":[1,"x",3],"hours":"none","created":[],"favouriteDish":{"name":"Knödel","stars":4.5},"rank":{"topPercent":null}}}
        """#
        let p = try #require(try JSONDecoder().decode(RecapDetail.self, from: Data(json.utf8)).pokyh)
        #expect(p.covered == nil && !p.usageConsent)
        #expect(p.totals == .init(activeDays: 12, activeSeconds: 600, longestStreak: 0))
        #expect(p.weekdays == [1, 0, 3] && p.hours == nil && p.created == nil && p.rank == nil)
        #expect(p.favouriteDish?.name.de == "Knödel")

        // A POKYH part that isn't an object leaves the recap itself.
        let odd = #"{"recap":{"id":"a","title":"A","periodFrom":"2026-09-08","periodTo":"2026-10-31","sections":["pokyh"]},"pokyh":[1,2]}"#
        let detail = try JSONDecoder().decode(RecapDetail.self, from: Data(odd.utf8))
        #expect(detail.pokyh == nil && detail.recap.id == "a")
    }

    @Test func readsWhatMarkingAViewAnswers() throws {
        let seen = try JSONDecoder().decode(RecapSeen.self, from: Data(#"{"openedAt":"2026-11-02T08:00:00.000Z","finishedAt":null}"#.utf8))
        #expect(seen.openedAt == "2026-11-02T08:00:00.000Z" && seen.finishedAt == nil)
    }
}
