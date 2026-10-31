import Foundation
import Testing
@testable import PokyhCore

// The feed's shape is routes/popups.ts: GET /popups/active. Slots as in slotMs() there.
struct PopupScheduleTests {
    let clock = DayClock(zone: TimeZone(secondsFromGMT: 0)!)
    private let day: Int64 = 86_400_000

    private func at(_ iso: String) -> Int64 { clock.parse(iso)! }

    /// "7× in 7 days" from 1 November.
    private var weekly: AnnouncementPopup {
        AnnouncementPopup(id: "w", revision: 1, title: "Woche", html: "<p>x</p>", showCount: 7,
                          startsAt: "2026-11-01T00:00:00.000Z", endsAt: "2026-11-08T00:00:00.000Z", slotMs: day)
    }

    private var once: AnnouncementPopup {
        AnnouncementPopup(id: "o", revision: 1, title: "Einmal", html: "<p>y</p>", showCount: 1)
    }

    @Test func decodesTheFeed() throws {
        let json = #"""
        {"now":"2026-11-02T08:00:00.000Z","popups":[
          {"id":"a1","revision":2,"title":"Hallo","html":"<p>Text</p>","showCount":1,"startsAt":null,"endsAt":null,"slotMs":null},
          {"id":"b2","revision":1,"title":"Woche","html":"<h1>T</h1>","showCount":7,
           "startsAt":"2026-11-01T00:00:00.000Z","endsAt":"2026-11-08T00:00:00.000Z","slotMs":86400000}]}
        """#
        let feed = try JSONDecoder().decode(AnnouncementPopupFeed.self, from: Data(json.utf8))
        #expect(feed.popups.map(\.key) == ["a1:2", "b2:1"])
        #expect(feed.popups[0].slotMs == nil)
        #expect(feed.popups[1].slotMs == 86_400_000)
        #expect(try JSONDecoder().decode(AnnouncementPopupFeed.self, from: Data("{}".utf8)).popups.isEmpty)
    }

    @Test func oncePopupShowsOnce() {
        let now = at("2026-11-02T08:00:00")
        #expect(PopupSchedule.isDue(once, seen: [:], now: now, clock: clock))
        let seen = PopupSchedule.withSeen([:], popups: [once], now: now, clock: clock)
        #expect(seen["o:1"] == PopupSeenEntry(slot: 0, count: 1, at: now))
        #expect(!PopupSchedule.isDue(once, seen: seen, now: now + 30 * day, clock: clock))
    }

    @Test func aNewRevisionShowsAgain() {
        let now = at("2026-11-02T08:00:00")
        let seen = PopupSchedule.withSeen([:], popups: [once], now: now, clock: clock)
        let edited = AnnouncementPopup(id: "o", revision: 2, title: "Einmal", html: "", showCount: 1)
        #expect(PopupSchedule.isDue(edited, seen: seen, now: now, clock: clock))
    }

    @Test func recurringShowsOncePerSlot() {
        let first = at("2026-11-01T09:00:00")
        var seen = PopupSchedule.withSeen([:], popups: [weekly], now: first, clock: clock)
        #expect(seen["w:1"]?.slot == 0)
        // Later the same day: the slot is spent.
        #expect(!PopupSchedule.isDue(weekly, seen: seen, now: first + 3_600_000, clock: clock))
        // Next day: due again.
        let second = first + day
        #expect(PopupSchedule.isDue(weekly, seen: seen, now: second, clock: clock))
        seen = PopupSchedule.withSeen(seen, popups: [weekly], now: second, clock: clock)
        #expect(seen["w:1"] == PopupSeenEntry(slot: 1, count: 2, at: second))
    }

    @Test func missedSlotsArentCaughtUp() {
        let first = at("2026-11-01T09:00:00")
        var seen = PopupSchedule.withSeen([:], popups: [weekly], now: first, clock: clock)
        let later = first + 4 * day
        seen = PopupSchedule.withSeen(seen, popups: [weekly], now: later, clock: clock)
        #expect(seen["w:1"] == PopupSeenEntry(slot: 4, count: 2, at: later))
        #expect(!PopupSchedule.isDue(weekly, seen: seen, now: later + 1000, clock: clock))
    }

    @Test func markingTwiceInASlotDoesntCostAShowing() {
        let now = at("2026-11-01T09:00:00")
        let once = PopupSchedule.withSeen([:], popups: [weekly], now: now, clock: clock)
        let twice = PopupSchedule.withSeen(once, popups: [weekly], now: now + 1000, clock: clock)
        #expect(twice == once)
    }

    @Test func nothingOutsideTheWindow() {
        #expect(PopupSchedule.currentSlot(weekly, now: at("2026-10-31T23:00:00"), clock: clock) == nil)
        #expect(PopupSchedule.currentSlot(weekly, now: at("2026-11-08T00:00:00"), clock: clock) == nil)
        #expect(!PopupSchedule.isDue(weekly, seen: [:], now: at("2026-11-08T00:00:01"), clock: clock))
    }

    @Test func theLastSlotHoldsUntilTheEnd() {
        // Rounded-down slot lengths leave a little over at the end of the window.
        var popup = weekly
        popup = AnnouncementPopup(id: popup.id, revision: 1, title: "", html: "", showCount: 3,
                                  startsAt: "2026-11-01T00:00:00.000Z", endsAt: "2026-11-02T00:00:00.000Z", slotMs: day / 3)
        #expect(PopupSchedule.currentSlot(popup, now: at("2026-11-01T23:59:59"), clock: clock) == 2)
    }

    @Test func noMoreThanItsCount() {
        let seen = ["w:1": PopupSeenEntry(slot: 2, count: 7, at: at("2026-11-03T00:00:00"))]
        #expect(!PopupSchedule.isDue(weekly, seen: seen, now: at("2026-11-05T00:00:00"), clock: clock))
    }

    @Test func oldEntriesArePruned() {
        let now = at("2026-11-01T09:00:00")
        let seen = ["gone:1": PopupSeenEntry(slot: 0, count: 1, at: now - 400 * day)]
        #expect(PopupSchedule.withSeen(seen, popups: [], now: now, clock: clock).isEmpty)
    }

    // ── The stack ───────────────────────────────────────────────────────────

    private func popup(_ id: String) -> AnnouncementPopup {
        AnnouncementPopup(id: id, revision: 1, title: id, html: "", showCount: 1)
    }

    @Test func aPopupIsLockedUntilViewed() {
        var stack = PopupStack(popups: [popup("a"), popup("b")])
        #expect(stack.locked)
        #expect(!stack.canReach(1))
        var closes = stack.next()
        #expect(!closes)
        #expect(stack.index == 0)
        stack.markViewed(popup("a"))
        #expect(!stack.locked)
        #expect(stack.canReach(1))
        closes = stack.next()
        #expect(!closes)
        #expect(stack.index == 1)
        #expect(stack.locked)
        // Back is always allowed, even while locked.
        stack.back()
        #expect(stack.index == 0)
    }

    @Test func theLastOneClosesTheStack() {
        var stack = PopupStack(popups: [popup("a")])
        var closes = stack.next()
        #expect(!closes)
        stack.markViewed(popup("a"))
        #expect(stack.isLast)
        closes = stack.next()
        #expect(closes)
    }

    @Test func noSkippingPastOneNotViewedYet() {
        var stack = PopupStack(popups: [popup("a"), popup("b"), popup("c")])
        stack.markViewed(popup("a"))
        #expect(!stack.canReach(2))
        stack.go(to: 2)
        #expect(stack.index == 0)
        #expect(stack.waiting == 2)
        stack.markViewed(popup("c"))
        #expect(stack.canReach(2))
    }

    @Test func checkingAgainDoesntDuplicate() {
        var stack = PopupStack(popups: [popup("a")])
        stack.add([popup("a"), popup("b")])
        #expect(stack.popups.map(\.id) == ["a", "b"])
        #expect(PopupStack().current == nil)
        #expect(!PopupStack().locked)
    }

    // ── The page ────────────────────────────────────────────────────────────

    @Test func documentCarriesTheContentAndTheTheme() {
        let dark = PopupSchedule.document(body: "<p>Hallo</p>", isDark: true)
        let light = PopupSchedule.document(body: "<p>Hallo</p>", isDark: false, fontSize: 18)
        #expect(dark.contains("<body><p>Hallo</p></body>"))
        #expect(dark.contains("#F2F2F4"))
        #expect(light.contains("#1C1A17"))
        #expect(light.contains("font-size:18.0px"))
        // Scripts stay off even if one slipped through the server's sanitiser.
        #expect(dark.contains("script-src 'none'"))
    }
}
