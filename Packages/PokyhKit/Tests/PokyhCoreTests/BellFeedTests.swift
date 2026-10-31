import Foundation
import Testing
@testable import PokyhCore

// Fixtures follow what the backend answers (routes/users.ts, services/bellMarks.ts) and what
// Android feeds its BellFeed, in a fixed zone so daylight saving is part of the test.
struct BellFeedTests {
    let clock = DayClock(zone: TimeZone(identifier: "Europe/Rome")!)
    let de = Strings.of(.de)

    private func at(_ iso: String) -> Int64 { clock.parse(iso)! }

    private var now: Int64 { at("2026-10-31T12:00:00") }

    // ── Keys are shared with Android and the web ────────────────────────────

    @Test func keysMatchTheOtherClients() {
        let due = at("2026-10-31T18:00:00")
        let feed = BellFeed.build(BellFeed.Input(
            grades: [.init(id: 4711, subject: "Mathematik", lessonId: 7, value: 8, date: 20261030, examType: "Schularbeit", enteredAt: at("2026-10-30T10:00:00"))],
            messages: [.init(id: 12, subject: "Ausflug", sender: "Frau Huber", sent: at("2026-10-31T08:00:00"), read: false)],
            reminders: [
                .init(id: "soon", title: "Elternabend", remindAt: at("2026-11-01T08:00:00"), createdAt: at("2026-10-20T08:00:00"), by: "max", mine: false),
                .init(id: "later", title: "Skitag", remindAt: at("2026-12-01T08:00:00"), createdAt: at("2026-10-30T08:00:00"), by: "max", mine: false),
            ],
            todos: [.init(id: "abc-1", title: "Lesen", dueAt: due, done: false)],
            streak: .init(days: 8, end: at("2026-10-31"), lost: nil),
            streakRead: true
        ), now: now, clock: clock)

        let keys = Set(feed.all.map(\.key))
        #expect(keys.contains("grade:4711"))
        #expect(keys.contains("msg:12"))
        #expect(keys.contains("rem-soon:soon"))
        #expect(keys.contains("rem:later"))
        #expect(keys.contains("todo:abc-1:\(due)"))
        #expect(keys.contains("streak:\(at("2026-10-24")):7"))
        #expect(feed.all.allSatisfy { BellFeed.isSendable($0.key) })
    }

    @Test func gradeWithoutEntryTimeIsADayOfItsExam() {
        let feed = BellFeed.build(BellFeed.Input(grades: [
            .init(id: 1, subject: "D", lessonId: 1, value: 7, date: 20261029, examType: "", enteredAt: 0),
        ]), now: now, clock: clock)
        #expect(feed.recent[0].allDay)
        #expect(feed.recent[0].at == at("2026-10-29"))
    }

    @Test func whatFallsOutOfTheFeed() {
        let feed = BellFeed.build(BellFeed.Input(
            grades: [
                .init(id: 1, subject: "old", lessonId: 1, value: 7, date: 20260901, examType: "", enteredAt: 0),
                .init(id: 2, subject: "no mark", lessonId: 1, value: 0, date: 20261030, examType: "", enteredAt: 0),
                .init(id: 3, subject: "future", lessonId: 1, value: 7, date: 20261120, examType: "", enteredAt: 0),
            ],
            messages: [.init(id: 1, subject: "old", sender: "", sent: at("2026-09-01T08:00:00"), read: false),
                       .init(id: 2, subject: "unreadable date", sender: "", sent: 0, read: false)],
            reminders: [
                .init(id: "past", title: "", remindAt: at("2026-10-01T08:00:00"), createdAt: at("2026-10-30T08:00:00"), by: "max", mine: false),
                .init(id: "mine", title: "", remindAt: at("2026-12-01T08:00:00"), createdAt: at("2026-10-30T08:00:00"), by: "me", mine: true),
            ],
            todos: [
                .init(id: "done", title: "", dueAt: at("2026-10-31T18:00:00"), done: true),
                .init(id: "none", title: "", dueAt: nil, done: false),
                .init(id: "far", title: "", dueAt: at("2026-11-20T18:00:00"), done: false),
                .init(id: "ancient", title: "", dueAt: at("2026-09-01T18:00:00"), done: false),
            ]
        ), now: now, clock: clock)
        #expect(feed.all.isEmpty)
    }

    @Test func dueComesFirstOldestOnTopThenWhatHappenedNewestOnTop() {
        let feed = BellFeed.build(BellFeed.Input(
            messages: [.init(id: 1, subject: "a", sender: "", sent: at("2026-10-30T08:00:00"), read: false),
                       .init(id: 2, subject: "b", sender: "", sent: at("2026-10-31T08:00:00"), read: false)],
            todos: [.init(id: "late", title: "", dueAt: at("2026-11-01T08:00:00"), done: false),
                    .init(id: "overdue", title: "", dueAt: at("2026-10-29T08:00:00"), done: false)]
        ), now: now, clock: clock)
        #expect(feed.current.map(\.title) == ["", ""])
        #expect(feed.current[0].overdue)
        #expect(!feed.current[1].overdue)
        #expect(feed.recent.map(\.title) == ["b", "a"])
    }

    @Test func recentIsCappedButDueIsNot() {
        let messages = (1...50).map { BellFeed.MessageIn(id: $0, subject: "m", sender: "", sent: now - Int64($0) * 60_000, read: false) }
        let feed = BellFeed.build(BellFeed.Input(messages: messages), now: now, clock: clock)
        #expect(feed.recent.count == 30)
        #expect(feed.recent[0].key == "msg:1")
    }

    // ── New, seen, cleared ──────────────────────────────────────────────────

    @Test func aReadMessageIsNeverNew() {
        let feed = BellFeed.build(BellFeed.Input(messages: [
            .init(id: 1, subject: "read", sender: "", sent: now - 1000, read: true),
            .init(id: 2, subject: "unread", sender: "", sent: now - 1000, read: false),
        ]), now: now, clock: clock)
        #expect(BellFeed.freshKeys(feed, seen: .init()) == ["msg:2"])
    }

    @Test func firstLoadOfASourceDoesntFloodTheBell() {
        let feed = BellFeed.build(BellFeed.Input(
            messages: [.init(id: 1, subject: "old", sender: "", sent: at("2026-10-20T08:00:00"), read: false),
                       .init(id: 2, subject: "new", sender: "", sent: at("2026-10-30T08:00:00"), read: false)],
            todos: [.init(id: "t", title: "", dueAt: at("2026-10-20T08:00:00"), done: false)]
        ), now: now, clock: clock)
        let settled = BellFeed.settleSeen(.init(), feed: feed, loaded: [.messages, .todos], now: now)
        #expect(settled.sources == [.messages, .todos])
        #expect(settled.keys == ["msg:1"])
        // The old to-do stays new, it still wants doing.
        let fresh = BellFeed.freshKeys(feed, seen: settled)
        #expect(fresh.contains("msg:2"))
        #expect(fresh.contains { $0.hasPrefix("todo:t:") })
        // Second time round nothing changes.
        #expect(BellFeed.settleSeen(settled, feed: feed, loaded: [.messages, .todos], now: now) == settled)
    }

    @Test func clearingRemovesEverywhereAndCountsAsSeen() {
        let feed = BellFeed.build(BellFeed.Input(messages: [
            .init(id: 1, subject: "a", sender: "", sent: now - 1000, read: false),
            .init(id: 2, subject: "b", sender: "", sent: now - 2000, read: false),
        ]), now: now, clock: clock)
        let state = BellFeed.clearKeys(.init(), keys: ["msg:1"])
        #expect(state.keys == ["msg:1"])
        #expect(state.cleared == ["msg:1"])
        #expect(BellFeed.withoutCleared(feed, cleared: state.cleared).all.map(\.key) == ["msg:2"])
        #expect(BellFeed.clearKeys(state, keys: []) == state)
    }

    @Test func openingCountsEverythingAsSeen() {
        let feed = BellFeed.build(BellFeed.Input(messages: [.init(id: 1, subject: "a", sender: "", sent: now - 1000, read: false)]), now: now, clock: clock)
        let state = BellFeed.markSeen(.init(), feed: feed)
        #expect(BellFeed.freshKeys(feed, seen: state).isEmpty)
    }

    @Test func rememberedKeysAreCappedNewestFirst() {
        let old = (0..<400).map { "old:\($0)" }
        let state = BellFeed.clearKeys(.init(keys: old), keys: ["new:1"])
        #expect(state.keys.count == 400)
        #expect(state.keys[0] == "new:1")
        #expect(!state.keys.contains("old:399"))
    }

    // ── The account's copy ──────────────────────────────────────────────────

    @Test func marksFromTheBackend() throws {
        let json = #"{"seen":["grade:1","msg:2","rem:x"],"cleared":["msg:2"]}"#
        let marks = try JSONDecoder().decode(BellMarks.self, from: Data(json.utf8))
        let merged = BellFeed.mergeRemote(.init(keys: ["msg:9"]), seen: marks.seen, cleared: marks.cleared)
        #expect(merged.keys == ["msg:9", "grade:1", "msg:2", "rem:x"])
        #expect(merged.cleared == ["msg:2"])
        #expect(try JSONDecoder().decode(BellMarks.self, from: Data("{}".utf8)).isEmpty)
    }

    @Test func onlyWhatTheAccountDoesntHaveIsPushed() {
        let state = BellFeed.SeenState(keys: ["a:1", "a:2", "gone:1", "bad key!"], cleared: ["gone:1", "gone:2"])
        let marks = BellFeed.marksToPush(state, remoteSeen: ["a:1"], remoteCleared: ["gone:2"])
        // A key the backend's pattern refuses would sink the whole batch.
        #expect(marks.seen == ["a:2"])
        #expect(marks.cleared == ["gone:1"])
        #expect(BellFeed.marksToPush(.init(), remoteSeen: [], remoteCleared: []).isEmpty)
    }

    @Test func pushIsCappedAtTheBackendsBatch() {
        let state = BellFeed.SeenState(keys: (0..<900).map { "k:\($0)" })
        #expect(BellFeed.marksToPush(state, remoteSeen: [], remoteCleared: []).seen.count == 400)
    }

    // ── The streak ──────────────────────────────────────────────────────────

    @Test func streakMilestoneAndLostRun() {
        let today = at("2026-10-31")
        let active = (0..<5).map { clock.addDays(at("2026-10-20"), $0) }
        let lost = BellFeed.lostStreak(active: active + [active[0]], today: today, clock: clock)
        #expect(lost == BellFeed.StreakRun(days: 5, start: at("2026-10-20"), end: at("2026-10-24")))

        let feed = BellFeed.build(BellFeed.Input(streak: .init(days: 2, end: today, lost: lost), streakRead: true), now: now, clock: clock)
        #expect(feed.recent.map(\.key) == ["streak-lost:\(at("2026-10-20")):5"])
        #expect(feed.recent[0].at == at("2026-10-26"))
    }

    @Test func aQuietTodayDoesntEndAStreak() {
        let today = at("2026-10-31")
        let active = (1...4).map { clock.addDays(today, -$0) }
        #expect(BellFeed.lostStreak(active: active, today: today, clock: clock) == nil)
        // One whole day missed does.
        let older = (2...5).map { clock.addDays(today, -$0) }
        #expect(BellFeed.lostStreak(active: older, today: today, clock: clock)?.days == 4)
    }

    @Test func aRunTooShortIsNoLoss() {
        let today = at("2026-10-31")
        #expect(BellFeed.lostStreak(active: [at("2026-10-20"), at("2026-10-21")], today: today, clock: clock) == nil)
    }

    @Test func streakFromTheActivityRoute() throws {
        // GET /users/me/activity, shortened to what's read.
        let json = #"""
        {"today":"2026-10-31","usageConsent":false,"days":[
          {"date":"2026-10-24","active":true,"logins":1},{"date":"2026-10-25","active":false},
          {"date":"2026-10-26","active":true},{"date":"2026-10-27","active":true},
          {"date":"2026-10-28","active":true},{"date":"2026-10-29","active":true},
          {"date":"2026-10-30","active":true},{"date":"2026-10-31","active":false}],
         "totals":{"activeDays":6,"currentStreak":5,"longestStreak":9},"weekdays":[1,1,1,1,1,1,0]}
        """#
        let activity = try JSONDecoder().decode(BellActivity.self, from: Data(json.utf8))
        let streak = BellFeed.streak(from: activity, now: now, clock: clock)
        #expect(streak.summary == BellStreakSummary(days: 5, longest: 9, week: [false, true, true, true, true, true, false]))
        #expect(!streak.summary.todayActive)
        #expect(streak.input.end == at("2026-10-30"))
        #expect(streak.input.lost == nil)
    }

    // ── Reading an item ─────────────────────────────────────────────────────

    private func item(_ at: Int64, kind: BellFeed.Kind = .message, allDay: Bool = false) -> BellFeed.Item {
        BellFeed.Item(key: "k", source: .messages, kind: kind, at: at, allDay: allDay, title: "t", target: .todos)
    }

    private func when(_ item: BellFeed.Item) -> String {
        BellFeed.whenText(item, now: now, strings: de, clock: clock)
    }

    @Test func timesInThePast() {
        #expect(when(item(now - 20_000)) == "Gerade eben")
        #expect(when(item(now - 5 * 60_000)) == "vor 5 Min.")
        #expect(when(item(now - 2 * 3_600_000)) == "vor 2 Std.")
        #expect(when(item(at("2026-10-30T08:05:00"))) == "gestern 08:05")
        #expect(when(item(at("2026-10-28T08:05:00"))) == "vor 3 Tagen")
        #expect(when(item(at("2026-10-12T08:05:00"))) == "12. Okt")
    }

    @Test func timesAhead() {
        #expect(when(item(now + 90_000)) == "in 2 Min.")
        #expect(when(item(now + 3 * 3_600_000)) == "in 3 Std.")
        #expect(when(item(now + 3 * 3_600_000, kind: .todo)) == "heute 15:00")
        #expect(when(item(at("2026-11-01T08:00:00"))) == "morgen 08:00")
        #expect(when(item(at("2026-11-05T08:00:00"))) == "5. Nov 08:00")
    }

    @Test func wholeDays() {
        #expect(when(item(at("2026-10-31"), allDay: true)) == "Heute")
        #expect(when(item(at("2026-10-30"), allDay: true)) == "Gestern")
        #expect(when(item(at("2026-10-27"), allDay: true)) == "vor 4 Tagen")
        #expect(when(item(at("2026-10-12"), allDay: true)) == "12. Okt")
    }

    @Test func overdueTodoSaysSo() {
        let feed = BellFeed.build(BellFeed.Input(todos: [.init(id: "t", title: "Lesen", dueAt: at("2026-10-30T09:00:00"), done: false)]), now: now, clock: clock)
        let row = BellFeed.rowText(feed.current[0], now: now, strings: de, clock: clock)
        #expect(row.title == "Lesen")
        #expect(row.subtitle == "Überfällig · gestern 09:00")
    }

    @Test func rowsLeaveOutWhatsEmpty() {
        let feed = BellFeed.build(BellFeed.Input(
            grades: [.init(id: 1, subject: "Mathematik", lessonId: 1, value: 8, date: 20261031, examType: "", enteredAt: 0)],
            messages: [.init(id: 1, subject: "", sender: "Frau Huber", sent: now - 60_000, read: false)]
        ), now: now, clock: clock)
        let rows = feed.recent.map { BellFeed.rowText($0, now: now, strings: de, clock: clock) }
        #expect(rows.contains { $0.title == "Neue Note in Mathematik" && $0.subtitle == "Heute" })
        #expect(rows.contains { $0.title == "(Kein Betreff)" && $0.subtitle == "Frau Huber · vor 1 Min." })
    }

    // ── When a grade appeared ───────────────────────────────────────────────

    @Test func gradesThereOnTheFirstLookArentNew() {
        var seen = GradeFirstSeen()
        var changed = seen.observe([1, 2, 0], now: 100)
        #expect(changed)
        #expect(seen.enteredAt(1) == 0)
        changed = seen.observe([1, 2], now: 200)
        #expect(!changed)
        changed = seen.observe([1, 2, 3], now: 300)
        #expect(changed)
        #expect(seen.enteredAt(3) == 300)
        #expect(seen.times[0] == nil)
    }

    @Test func firstSeenSurvivesCoding() throws {
        var seen = GradeFirstSeen()
        seen.observe([5], now: 1)
        seen.observe([6], now: 2)
        let back = try JSONDecoder().decode(GradeFirstSeen.self, from: JSONEncoder().encode(seen))
        #expect(back == seen)
    }

    // ── Timestamps ──────────────────────────────────────────────────────────

    @Test func parsesWhatTheBackendsSend() {
        let utc = DayClock(zone: TimeZone(secondsFromGMT: 0)!)
        let expected = utc.parse("2026-10-31T10:15:00")!
        #expect(clock.parse("2026-10-31T10:15:00Z") == expected)
        #expect(clock.parse("2026-10-31T10:15:00.000Z") == expected)
        #expect(clock.parse("2026-10-31T10:15:00.250Z") == expected + 250)
        #expect(clock.parse("2026-10-31T11:15:00+01:00") == expected)
        #expect(clock.parse("2026-10-31T11:15:00+0100") == expected)
        #expect(clock.parse("2026-10-31T05:15:00-05:00") == expected)
        #expect(clock.parse("  2026-10-31T10:15:00Z ") == expected)
        // No zone: local time.
        #expect(clock.parse("2026-10-31T11:15:00") == expected)
        #expect(clock.parse("2026-10-31 11:15") == expected)
        #expect(clock.parse("2026-10-31") == clock.startOfDay(expected))
    }

    @Test func nonsenseIsNil() {
        #expect(clock.parse(nil) == nil)
        #expect(clock.parse("") == nil)
        #expect(clock.parse("yesterday") == nil)
        #expect(clock.parse("2026-13-40") == nil)
        #expect(clock.untisDay(20261340) == 0)
    }

    @Test func daylightSavingKeepsTheMidnight() {
        // Clocks go back on 25 October 2026 in Rome: that day has 25 hours.
        let before = at("2026-10-25")
        let after = clock.addDays(before, 1)
        #expect(after - before == 25 * 3_600_000)
        #expect(after == at("2026-10-26"))
        #expect(clock.startOfDay(at("2026-10-25T23:30:00")) == before)
    }
}
