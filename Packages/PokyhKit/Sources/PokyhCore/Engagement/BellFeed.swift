import Foundation

/// What the bell shows: what happened lately (new grades and messages, reminders a classmate put
/// up), to-dos and reminders coming due, the streak reaching a milestone or running out; which of
/// it the account hasn't looked at yet and what it cleared away. Same rules as Android and the web,
/// and the same keys, because seen and cleared are shared between them through /users/me/bell.
public enum BellFeed {
    private static let day: Int64 = 86_400_000

    /// How far back the feed reaches.
    public static let feedDays = 14
    /// To-dos and reminders join the feed this long before they are due.
    public static let soonMs = day
    /// On a source's first load, only what is younger than this counts as new.
    public static let freshMs = 3 * day
    /// Streak lengths worth a line of their own.
    public static let streakMilestones = [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365]
    /// How many seen and cleared keys are remembered, newest first. Also the backend's batch limit.
    public static let seenLimit = 400
    public static let recentLimit = 30

    public enum Source: String, Codable, CaseIterable, Sendable {
        case grades, messages, reminders, todos, streak
    }

    public enum Kind: String, Sendable {
        case grade, message, reminder, reminderSoon, todo, streak, streakLost
    }

    public enum Target: Equatable, Hashable, Sendable {
        case grade(lessonId: Int)
        case message(id: Int)
        case reminders
        case todos
        case profile
    }

    public struct GradeIn: Equatable, Sendable {
        public var id: Int, subject: String, lessonId: Int, value: Double, date: Int, examType: String, enteredAt: Int64
        public init(id: Int, subject: String, lessonId: Int, value: Double, date: Int, examType: String, enteredAt: Int64) {
            self.id = id; self.subject = subject; self.lessonId = lessonId; self.value = value
            self.date = date; self.examType = examType; self.enteredAt = enteredAt
        }
    }

    public struct MessageIn: Equatable, Sendable {
        public var id: Int, subject: String, sender: String, sent: Int64, read: Bool
        public init(id: Int, subject: String, sender: String, sent: Int64, read: Bool) {
            self.id = id; self.subject = subject; self.sender = sender; self.sent = sent; self.read = read
        }
    }

    public struct ReminderIn: Equatable, Sendable {
        public var id: String, title: String, remindAt: Int64, createdAt: Int64, by: String, mine: Bool
        public init(id: String, title: String, remindAt: Int64, createdAt: Int64, by: String, mine: Bool) {
            self.id = id; self.title = title; self.remindAt = remindAt
            self.createdAt = createdAt; self.by = by; self.mine = mine
        }
    }

    public struct TodoIn: Equatable, Sendable {
        public var id: String, title: String, dueAt: Int64?, done: Bool
        public init(id: String, title: String, dueAt: Int64?, done: Bool) {
            self.id = id; self.title = title; self.dueAt = dueAt; self.done = done
        }
    }

    /// A run of active days: its length, its first and last day (local midnight).
    public struct StreakRun: Equatable, Sendable {
        public var days: Int, start: Int64, end: Int64
        public init(days: Int, start: Int64, end: Int64) {
            self.days = days; self.start = start; self.end = end
        }
    }

    /// The running streak: its length, the last day it counts, and the last one that ran out.
    public struct StreakIn: Equatable, Sendable {
        public var days: Int, end: Int64, lost: StreakRun?
        public init(days: Int, end: Int64, lost: StreakRun?) {
            self.days = days; self.end = end; self.lost = lost
        }
    }

    /// Each source is nil until it has been read.
    public struct Input: Equatable, Sendable {
        public var grades: [GradeIn]?
        public var messages: [MessageIn]?
        public var reminders: [ReminderIn]?
        public var todos: [TodoIn]?
        public var streak: StreakIn?
        public var streakRead = false

        public init(grades: [GradeIn]? = nil, messages: [MessageIn]? = nil, reminders: [ReminderIn]? = nil,
                    todos: [TodoIn]? = nil, streak: StreakIn? = nil, streakRead: Bool = false) {
            self.grades = grades; self.messages = messages; self.reminders = reminders
            self.todos = todos; self.streak = streak; self.streakRead = streakRead
        }

        public var loaded: [Source] {
            var out: [Source] = []
            if grades != nil { out.append(.grades) }
            if messages != nil { out.append(.messages) }
            if reminders != nil { out.append(.reminders) }
            if todos != nil { out.append(.todos) }
            if streakRead { out.append(.streak) }
            return out
        }
    }

    public struct Item: Equatable, Identifiable, Sendable {
        /// Stable, for remembering what was seen.
        public let key: String
        public let source: Source
        public let kind: Kind
        /// When it happened, or when it is due.
        public let at: Int64
        /// `at` is a day, not a moment.
        public var allDay = false
        public let title: String
        public var sub = ""
        public let target: Target
        /// The mark of a grade, the days of a streak.
        public var value: Double?
        public var overdue = false
        /// Nothing to tell (a message already read): never counts as new.
        public var settled = false

        public var id: String { key }
    }

    public struct Feed: Equatable, Sendable {
        public var current: [Item]
        public var recent: [Item]
        public init(current: [Item] = [], recent: [Item] = []) {
            self.current = current
            self.recent = recent
        }
        public var all: [Item] { current + recent }
    }

    public struct SeenState: Codable, Equatable, Sendable {
        public var keys: [String]
        public var sources: [Source]
        public var cleared: [String]
        public init(keys: [String] = [], sources: [Source] = [], cleared: [String] = []) {
            self.keys = keys
            self.sources = sources
            self.cleared = cleared
        }
    }

    /// The latest milestone the running streak has passed, the day it did, and where it began.
    private static func milestone(_ streak: StreakIn, _ clock: DayClock) -> (days: Int, at: Int64, start: Int64)? {
        guard let days = streakMilestones.last(where: { $0 <= streak.days }) else { return nil }
        let start = clock.addDays(streak.end, -(streak.days - 1))
        return (days, clock.addDays(start, days - 1), start)
    }

    /// The latest streak of at least the first milestone that ran out: a whole day without POKYH
    /// after it. A quiet today doesn't end one yet, as on the backend.
    public static func lostStreak(active: [Int64], today: Int64, clock: DayClock = DayClock()) -> StreakRun? {
        var runs: [StreakRun] = []
        for day in Set(active).sorted() {
            if let run = runs.last, clock.addDays(run.end, 1) == day {
                runs[runs.count - 1].days = run.days + 1
                runs[runs.count - 1].end = day
            } else {
                runs.append(StreakRun(days: 1, start: day, end: day))
            }
        }
        return runs.last { $0.days >= streakMilestones[0] && clock.addDays($0.end, 2) <= today }
    }

    public static func build(_ input: Input, now: Int64, clock: DayClock = DayClock()) -> Feed {
        let since = clock.addDays(clock.startOfDay(now), -feedDays)
        var current: [Item] = []
        var recent: [Item] = []

        for g in input.grades ?? [] {
            // When it was entered, when that is known; else the day of the exam.
            let entered = g.enteredAt > 0
            let at = entered ? g.enteredAt : clock.untisDay(g.date)
            if g.value <= 0 || at < since || at > now { continue }
            recent.append(Item(key: "grade:\(g.id)", source: .grades, kind: .grade, at: at, allDay: !entered,
                               title: g.subject, sub: g.examType, target: .grade(lessonId: g.lessonId), value: g.value))
        }
        for m in input.messages ?? [] {
            if m.sent <= 0 || m.sent < since { continue }
            recent.append(Item(key: "msg:\(m.id)", source: .messages, kind: .message, at: m.sent,
                               title: m.subject, sub: m.sender, target: .message(id: m.id), settled: m.read))
        }
        for r in input.reminders ?? [] {
            if r.remindAt > now && r.remindAt <= now + soonMs {
                current.append(Item(key: "rem-soon:\(r.id)", source: .reminders, kind: .reminderSoon, at: r.remindAt,
                                    title: r.title, sub: r.mine ? "" : r.by, target: .reminders))
            } else if !r.mine && r.createdAt >= since && r.createdAt <= now && r.remindAt > now {
                recent.append(Item(key: "rem:\(r.id)", source: .reminders, kind: .reminder, at: r.createdAt,
                                   title: r.title, sub: r.by, target: .reminders))
            }
        }
        for t in input.todos ?? [] {
            guard let due = t.dueAt else { continue }
            if t.done || due < since || due > now + soonMs { continue }
            current.append(Item(key: "todo:\(t.id):\(due)", source: .todos, kind: .todo, at: due,
                                title: t.title, target: .todos, overdue: due < now))
        }
        if let streak = input.streak {
            if let m = milestone(streak, clock), m.at >= since {
                recent.append(Item(key: "streak:\(m.start):\(m.days)", source: .streak, kind: .streak, at: m.at, allDay: true,
                                   title: "", target: .profile, value: Double(m.days)))
            }
            // Gone at the end of the first day missed.
            if let lost = streak.lost {
                let at = clock.addDays(lost.end, 2)
                if at >= since && at <= now {
                    recent.append(Item(key: "streak-lost:\(lost.start):\(lost.days)", source: .streak, kind: .streakLost, at: at, allDay: true,
                                       title: "", target: .profile, value: Double(lost.days)))
                }
            }
        }
        current.sort { ($0.at, $0.key) < ($1.at, $1.key) }
        recent.sort { $0.at != $1.at ? $0.at > $1.at : $0.key < $1.key }
        return Feed(current: current, recent: Array(recent.prefix(recentLimit)))
    }

    public static func withoutCleared(_ feed: Feed, cleared: [String]) -> Feed {
        if cleared.isEmpty { return feed }
        let gone = Set(cleared)
        return Feed(current: feed.current.filter { !gone.contains($0.key) },
                    recent: feed.recent.filter { !gone.contains($0.key) })
    }

    private static func merge(_ front: [String], _ rest: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for key in front + rest where seen.insert(key).inserted {
            out.append(key)
            if out.count == seenLimit { break }
        }
        return out
    }

    /// These items are cleared away, and count as seen.
    public static func clearKeys(_ state: SeenState, keys: [String]) -> SeenState {
        if keys.isEmpty { return state }
        var next = state
        next.keys = merge(keys, state.keys)
        next.cleared = merge(keys, state.cleared)
        return next
    }

    public static func isNew(_ item: Item, seen: Set<String>) -> Bool {
        !item.settled && !seen.contains(item.key)
    }

    /// Keys of the items in the feed not seen yet.
    public static func freshKeys(_ feed: Feed, seen: SeenState) -> Set<String> {
        let keys = Set(seen.keys)
        return Set(feed.all.filter { isNew($0, seen: keys) }.map(\.key))
    }

    /// A source read for the first time on this device doesn't flood the bell: what is older than
    /// `freshMs` counts as seen. Due to-dos and reminders stay new, they still want doing.
    public static func settleSeen(_ state: SeenState, feed: Feed, loaded: [Source], now: Int64) -> SeenState {
        let first = loaded.filter { !state.sources.contains($0) }
        if first.isEmpty { return state }
        let old = feed.recent.filter { first.contains($0.source) && $0.at < now - freshMs }.map(\.key)
        var next = state
        next.keys = merge(old, state.keys)
        next.sources = state.sources + first
        return next
    }

    /// Everything in the feed now counts as seen.
    public static func markSeen(_ state: SeenState, feed: Feed) -> SeenState {
        var next = state
        next.keys = merge(feed.all.map(\.key), state.keys)
        return next
    }

    /// The account's marks, from any device, joined into this device's.
    public static func mergeRemote(_ state: SeenState, seen: [String], cleared: [String]) -> SeenState {
        var next = state
        next.keys = merge(state.keys, seen)
        next.cleared = merge(state.cleared, cleared)
        return next
    }

    // The backend turns away a whole batch for one key it doesn't like (routes/users.ts).
    static func isSendable(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 120 && key.utf8.allSatisfy { c in
            (0x30...0x39).contains(c) || (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
                || c == 0x3A || c == 0x2E || c == 0x5F || c == 0x2D
        }
    }

    /// What the account's copy doesn't hold yet. Nothing is ever unmarked.
    public static func marksToPush(_ state: SeenState, remoteSeen: Set<String>, remoteCleared: Set<String>) -> BellMarks {
        let cleared = Set(state.cleared)
        return BellMarks(
            seen: Array(state.keys.filter { !remoteSeen.contains($0) && !cleared.contains($0) && isSendable($0) }.prefix(seenLimit)),
            cleared: Array(state.cleared.filter { !remoteCleared.contains($0) && isSendable($0) }.prefix(seenLimit))
        )
    }

    // ── Reading an item ─────────────────────────────────────────────────────

    /// "vor 5 Min.", "in 2 Std.", "morgen 08:00", "Gestern", "12. Okt."
    public static func whenText(_ item: Item, now: Int64, strings: Strings, clock: DayClock = DayClock()) -> String {
        let t = strings.bell, c = strings.common
        let days = Int((Double(clock.startOfDay(now) - clock.startOfDay(item.at)) / Double(day)).rounded())
        let p = clock.parts(item.at)
        let date = c.dayMonthShort(p.day, p.month)
        if item.allDay {
            if days <= 0 { return t.today }
            if days == 1 { return t.yesterday }
            return days < 7 ? c.daysAgo(days) : date
        }
        let time = String(format: "%02d:%02d", p.hour, p.minute)
        let ahead = item.at - now
        if ahead > 0 {
            if ahead < 3_600_000 { return t.inMinutes(max(1, Int((Double(ahead) / 60_000).rounded()))) }
            if days == 0 { return item.kind == .todo ? t.todayAt(time) : t.inHours(Int((Double(ahead) / 3_600_000).rounded())) }
            if days == -1 { return t.tomorrowAt(time) }
            return "\(date) \(time)"
        }
        if item.kind == .todo {
            if days == 0 { return t.todayAt(time) }
            return days == 1 ? t.yesterdayAt(time) : date
        }
        let minutes = Int(-ahead / 60_000)
        if minutes < 1 { return c.justNow }
        if minutes < 60 { return c.minutesAgo(minutes) }
        if days == 0 { return c.hoursAgo(minutes / 60) }
        if days == 1 { return t.yesterdayAt(time) }
        return days < 7 ? c.daysAgo(days) : date
    }

    /// The two lines of a row.
    public static func rowText(_ item: Item, now: Int64, strings: Strings, clock: DayClock = DayClock()) -> (title: String, subtitle: String) {
        let t = strings.bell
        let at = whenText(item, now: now, strings: strings, clock: clock)
        let days = Int(item.value ?? 0)
        let title: String
        let parts: [String]
        switch item.kind {
        case .grade:
            title = t.gradeNew(item.title)
            parts = [item.sub, at]
        case .message:
            title = item.title.isEmpty ? t.noSubject : item.title
            parts = [item.sub, at]
        case .reminder:
            title = item.title
            parts = [t.reminderBy(item.sub), at]
        case .reminderSoon:
            title = item.title
            parts = ["\(t.reminderSoon) \(at)", item.sub]
        case .todo:
            title = item.title
            parts = [item.overdue ? "\(t.todoOverdue) · \(at)" : "\(t.todoDue) \(at)"]
        case .streak:
            title = t.milestone(days)
            parts = [t.milestoneSub, at]
        case .streakLost:
            title = t.streakLost(days)
            parts = [t.streakLostSub, at]
        }
        return (title, parts.filter { !$0.isEmpty }.joined(separator: " · "))
    }
}

/// Which of the bell's items the account has seen and cleared, as /users/me/bell has them.
public struct BellMarks: Codable, Equatable, Sendable {
    public var seen: [String]
    public var cleared: [String]

    public init(seen: [String] = [], cleared: [String] = []) {
        self.seen = seen
        self.cleared = cleared
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seen = try c.decodeIfPresent([String].self, forKey: .seen) ?? []
        cleared = try c.decodeIfPresent([String].self, forKey: .cleared) ?? []
    }

    public var isEmpty: Bool { seen.isEmpty && cleared.isEmpty }
}

/// When a grade appeared. WebUntis doesn't say, so it's the moment this device first saw it. On the
/// very first look everything counts as "already there" (0); only what appears later is new.
public struct GradeFirstSeen: Codable, Equatable, Sendable {
    private static let limit = 3000
    public private(set) var times: [Int: Int64]

    public init(times: [Int: Int64] = [:]) {
        self.times = times
    }

    /// True when something new was noted and it should be stored again.
    @discardableResult
    public mutating func observe(_ ids: [Int], now: Int64) -> Bool {
        let ids = ids.filter { $0 != 0 }
        if ids.isEmpty { return false }
        let first = times.isEmpty
        var changed = false
        for id in ids where times[id] == nil {
            times[id] = first ? 0 : now
            changed = true
        }
        if changed, times.count > Self.limit {
            let newest = times.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key > $1.key }.prefix(Self.limit)
            times = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        return changed
    }

    public func enteredAt(_ id: Int) -> Int64 { times[id] ?? 0 }
}

/// The part of /users/me/activity the bell's streak reads.
public struct BellActivity: Decodable, Equatable, Sendable {
    public struct Day: Decodable, Equatable, Sendable {
        public var date: String
        public var active: Bool

        public init(date: String, active: Bool) {
            self.date = date
            self.active = active
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decode(String.self, forKey: .date)
            active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
        }

        private enum CodingKeys: String, CodingKey { case date, active }
    }

    public struct Totals: Decodable, Equatable, Sendable {
        public var currentStreak: Int
        public var longestStreak: Int

        public init(currentStreak: Int = 0, longestStreak: Int = 0) {
            self.currentStreak = currentStreak
            self.longestStreak = longestStreak
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
            longestStreak = try c.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        }

        private enum CodingKeys: String, CodingKey { case currentStreak, longestStreak }
    }

    public var today: String
    public var days: [Day]
    public var totals: Totals

    public init(today: String, days: [Day], totals: Totals) {
        self.today = today
        self.days = days
        self.totals = totals
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today = try c.decodeIfPresent(String.self, forKey: .today) ?? ""
        days = try c.decodeIfPresent([Day].self, forKey: .days) ?? []
        totals = try c.decodeIfPresent(Totals.self, forKey: .totals) ?? Totals()
    }

    private enum CodingKeys: String, CodingKey { case today, days, totals }
}

/// The streak card on top of the bell: how many days, the longest, the last week.
public struct BellStreakSummary: Equatable, Sendable {
    public var days: Int
    public var longest: Int
    public var week: [Bool]

    public var todayActive: Bool { week.last ?? false }

    public init(days: Int, longest: Int, week: [Bool]) {
        self.days = days
        self.longest = longest
        self.week = week
    }
}

extension BellFeed {
    public static func streak(from activity: BellActivity, now: Int64, clock: DayClock = DayClock()) -> (input: StreakIn, summary: BellStreakSummary) {
        let today = clock.parse(activity.today) ?? clock.startOfDay(now)
        let todayActive = activity.days.last?.active ?? false
        let active = activity.days.filter(\.active).compactMap { clock.parse($0.date) }
        let input = StreakIn(
            days: activity.totals.currentStreak,
            end: todayActive ? today : clock.addDays(today, -1),
            lost: lostStreak(active: active, today: today, clock: clock)
        )
        let summary = BellStreakSummary(days: activity.totals.currentStreak, longest: activity.totals.longestStreak,
                                        week: activity.days.suffix(7).map(\.active))
        return (input, summary)
    }
}
