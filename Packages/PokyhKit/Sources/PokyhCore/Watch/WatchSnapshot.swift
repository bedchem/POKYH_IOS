import Foundation

/// What the watch shows: today's lessons, grades, the Mensa and the to-dos. The iPhone builds it
/// from what it just loaded; the watch keeps the last one sealed on disk, so it opens without
/// the phone, and can reload the lessons by itself (see `UntisDay`).
public struct WatchSnapshot: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case phone, watch
    }

    public struct Lesson: Codable, Sendable, Hashable, Identifiable {
        public enum Status: String, Codable, Sendable {
            case regular, cancelled, substitution, roomChange, additional, exam

            /// One status per lesson, the loudest first: a cancelled exam is cancelled.
            public static func of(cancelled: Bool, exam: Bool, substitution: Bool, additional: Bool,
                                  room: String, originalRoom: String?) -> Status {
                if cancelled { return .cancelled }
                if exam { return .exam }
                if substitution { return .substitution }
                if let originalRoom, !originalRoom.isEmpty, originalRoom != room { return .roomChange }
                if additional { return .additional }
                return .regular
            }
        }

        public var id: String
        public var subject: String
        public var subjectLong: String
        public var teacher: String
        public var room: String
        public var start: Date
        public var end: Date
        public var status: Status
        /// Who or where it was before the substitution or room change.
        public var originalTeacher: String?
        public var originalRoom: String?
        public var note: String?

        public init(id: String, subject: String, subjectLong: String = "", teacher: String, room: String,
                    start: Date, end: Date, status: Status = .regular,
                    originalTeacher: String? = nil, originalRoom: String? = nil, note: String? = nil) {
            self.id = id
            self.subject = subject
            self.subjectLong = subjectLong
            self.teacher = teacher
            self.room = room
            self.start = start
            self.end = end
            self.status = status
            self.originalTeacher = originalTeacher
            self.originalRoom = originalRoom
            self.note = note
        }

        public var isCancelled: Bool { status == .cancelled }

        /// The long name where WebUntis has one.
        public var title: String { subjectLong.isEmpty ? subject : subjectLong }

        /// 0…1 through the lesson at `date`.
        public func progress(at date: Date) -> Double {
            let total = end.timeIntervalSince(start)
            guard total > 0 else { return 0 }
            return min(1, max(0, date.timeIntervalSince(start) / total))
        }
    }

    public struct SubjectAverage: Codable, Sendable, Hashable, Identifiable {
        public var name: String
        public var average: Double
        public var count: Int

        public init(name: String, average: Double, count: Int) {
            self.name = name
            self.average = average
            self.count = count
        }

        public var id: String { name }
    }

    public struct Grade: Codable, Sendable, Hashable, Identifiable {
        public var id: Int
        public var subject: String
        public var value: Double
        public var date: Date?
        public var text: String

        public init(id: Int, subject: String, value: Double, date: Date?, text: String = "") {
            self.id = id
            self.subject = subject
            self.value = value
            self.date = date
            self.text = text
        }
    }

    public struct Dish: Codable, Sendable, Hashable, Identifiable {
        public enum Diet: String, Sendable {
            case vegan, vegetarian
        }

        public var id: String
        public var name: String
        public var category: String
        public var tags: [String]

        public init(id: String, name: String, category: String, tags: [String] = []) {
            self.id = id
            self.name = name
            self.category = category
            self.tags = tags
        }

        /// Vegan before vegetarian, read from the tags like on Home.
        public var diet: Diet? {
            let tags = tags.map { $0.lowercased() }
            if tags.contains(where: { $0.contains("vegan") }) { return .vegan }
            if tags.contains(where: { $0.contains("vegetar") }) { return .vegetarian }
            return nil
        }
    }

    public struct Todo: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var due: Date?
        public var done: Bool

        public init(id: String, title: String, due: Date? = nil, done: Bool = false) {
            self.id = id
            self.title = title
            self.due = due
            self.done = done
        }
    }

    /// Whose data this is; the watch drops a snapshot for any other account.
    public var username: String
    /// The language picked in the iPhone app, so the watch speaks the same one.
    public var lang: Lang?
    public var updatedAt: Date
    /// When the lessons were last loaded, by the phone or by the watch itself.
    public var lessonsUpdatedAt: Date
    public var source: Source
    /// Midnight of the day `lessons` belong to.
    public var day: Date
    public var lessons: [Lesson]
    /// The WebUntis person whose timetable this is (a parent's child), for the watch's own fetch.
    public var studentId: Int?
    public var overallAverage: Double?
    public var gradeCount: Int
    public var subjects: [SubjectAverage]
    public var recentGrades: [Grade]
    /// The day `dishes` are served: today, or the next day the Mensa has a menu for.
    public var mensaDay: Date?
    public var dishes: [Dish]
    public var todos: [Todo]

    public init(username: String, lang: Lang? = nil, updatedAt: Date = .now, lessonsUpdatedAt: Date? = nil,
                source: Source = .phone, day: Date, lessons: [Lesson] = [], studentId: Int? = nil,
                overallAverage: Double? = nil, gradeCount: Int = 0, subjects: [SubjectAverage] = [],
                recentGrades: [Grade] = [], mensaDay: Date? = nil, dishes: [Dish] = [], todos: [Todo] = []) {
        self.username = username
        self.lang = lang
        self.updatedAt = updatedAt
        self.lessonsUpdatedAt = lessonsUpdatedAt ?? updatedAt
        self.source = source
        self.day = day
        self.lessons = lessons.sorted { $0.start < $1.start }
        self.studentId = studentId
        self.overallAverage = overallAverage
        self.gradeCount = gradeCount
        self.subjects = subjects
        self.recentGrades = recentGrades
        self.mensaDay = mensaDay
        self.dishes = dishes
        self.todos = todos
    }

    /// Nothing loaded yet for `username`.
    public static func empty(for username: String, at date: Date = .now, calendar: Calendar = .current) -> WatchSnapshot {
        WatchSnapshot(username: username, updatedAt: .distantPast, day: calendar.startOfDay(for: date))
    }
}

// MARK: Reading it

extension WatchSnapshot {
    public func isToday(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }

    /// Whether `lessons` says anything about today. Without it "no lessons" only means "don't know".
    public func knowsToday(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        isToday(date, calendar: calendar) && lessonsUpdatedAt > .distantPast
    }

    /// Today's lessons; yesterday's snapshot has none for today.
    public func todaysLessons(at date: Date = .now, calendar: Calendar = .current) -> [Lesson] {
        isToday(date, calendar: calendar) ? lessons : []
    }

    /// The lesson running at `date`. Cancelled ones don't count.
    public func current(at date: Date = .now, calendar: Calendar = .current) -> Lesson? {
        todaysLessons(at: date, calendar: calendar).first { !$0.isCancelled && $0.start <= date && date < $0.end }
    }

    /// The next lesson that still takes place.
    public func next(after date: Date = .now, calendar: Calendar = .current) -> Lesson? {
        todaysLessons(at: date, calendar: calendar).first { !$0.isCancelled && $0.start > date }
    }

    /// Running or next: what a complication shows.
    public func upcoming(at date: Date = .now, calendar: Calendar = .current) -> Lesson? {
        current(at: date, calendar: calendar) ?? next(after: date, calendar: calendar)
    }

    /// Had lessons today, all of them over.
    public func dayIsOver(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = todaysLessons(at: date, calendar: calendar).filter { !$0.isCancelled }
        return !today.isEmpty && today.allSatisfy { $0.end <= date }
    }

    public var openTodos: [Todo] { todos.filter { !$0.done } }

    /// Old enough that the watch should ask for something newer.
    public func isStale(at date: Date = .now, maxAge: TimeInterval = 30 * 60, calendar: Calendar = .current) -> Bool {
        !isToday(date, calendar: calendar) || date.timeIntervalSince(lessonsUpdatedAt) > maxAge
    }

    /// When a complication has to change: now, every lesson start and end still to come today,
    /// and midnight, when what it shows stops being true.
    public func timelineDates(from date: Date = .now, calendar: Calendar = .current) -> [Date] {
        let edges = todaysLessons(at: date, calendar: calendar)
            .filter { !$0.isCancelled }
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > date }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return [date] + Array(Set(edges + [midnight])).sorted()
    }

    /// When the watch should look again by itself: every two hours of the school day, then not
    /// before the next morning, so the first glance at the face already shows today.
    public static func nextRefresh(after date: Date, calendar: Calendar = .current) -> Date {
        let morning = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: date) ?? date
        if date < morning { return morning }
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        let next = date.addingTimeInterval(2 * 60 * 60)
        return next <= evening ? next : calendar.date(byAdding: .day, value: 1, to: morning) ?? next
    }

    /// What to keep when `incoming` arrives: nothing if it's older (a reply can overtake a
    /// context update), otherwise it, with the fresher lessons of the two. The watch may have
    /// loaded those itself while the phone only sent a new to-do.
    public func taking(_ incoming: WatchSnapshot) -> WatchSnapshot? {
        guard incoming.updatedAt >= updatedAt else { return nil }
        guard lessonsUpdatedAt > incoming.lessonsUpdatedAt else { return incoming }
        var merged = incoming
        merged.lessons = lessons
        merged.day = day
        merged.lessonsUpdatedAt = lessonsUpdatedAt
        merged.source = source
        return merged
    }

    /// The lessons the watch loaded by itself, everything else as it was.
    public func withLessons(_ lessons: [Lesson], day: Date, studentId: Int?, at date: Date = .now) -> WatchSnapshot {
        var copy = self
        copy.lessons = lessons.sorted { $0.start < $1.start }
        copy.day = day
        copy.studentId = studentId ?? self.studentId
        copy.lessonsUpdatedAt = date
        copy.source = .watch
        return copy
    }

    /// The to-do list with the watch's not yet sent ticks on top.
    public func applying(_ queue: TodoQueue) -> WatchSnapshot {
        var copy = self
        copy.todos = todos.map { todo in
            var todo = todo
            if let pending = queue.pending(for: todo.id) { todo.done = pending.done }
            return todo
        }
        return copy
    }
}

// MARK: Over WatchConnectivity

extension WatchSnapshot {
    static let payloadKey = "pokyh.snapshot"

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) -> WatchSnapshot? {
        try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    /// A property-list dictionary, to merge into applicationContext or a reply.
    public var payload: [String: Any] {
        guard let data = try? encoded() else { return [:] }
        return [Self.payloadKey: data]
    }

    /// nil when the payload has no snapshot in it.
    public init?(payload: [String: Any]) {
        guard let data = payload[Self.payloadKey] as? Data, let snapshot = Self.decoded(from: data) else { return nil }
        self = snapshot
    }
}
