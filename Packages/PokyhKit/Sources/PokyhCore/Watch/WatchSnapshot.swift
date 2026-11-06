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
        /// Its single grades. Older phones don't send them.
        public var grades: [Grade]?

        public init(name: String, average: Double, count: Int, grades: [Grade]? = nil) {
            self.name = name
            self.average = average
            self.count = count
            self.grades = grades
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
        /// The mean rating, 1 to 5; nil until someone has rated it or the phone has said so.
        public var stars: Double?
        public var ratings: Int?

        public init(id: String, name: String, category: String, tags: [String] = [], stars: Double? = nil, ratings: Int? = nil) {
            self.id = id
            self.name = name
            self.category = category
            self.tags = tags
            self.stars = stars
            self.ratings = ratings
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

        /// The same rule as the To-dos screen on the phone.
        public func isOverdue(at date: Date = .now) -> Bool {
            guard !done, let due else { return false }
            return due < date
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

    /// Lowest average first: that's the one to look at. Ties by name, so the order never jumps.
    public var subjectsByAverage: [SubjectAverage] {
        subjects.sorted { $0.average != $1.average ? $0.average < $1.average : $0.name < $1.name }
    }

    /// A subject's grades, newest first. Without single grades from the phone, the recent ones.
    public func grades(of subject: SubjectAverage) -> [Grade] {
        (subject.grades ?? recentGrades.filter { $0.subject == subject.name }).sorted { $0.id > $1.id }
    }

    /// Old enough that the watch should ask for something newer.
    public func isStale(at date: Date = .now, maxAge: TimeInterval = 30 * 60, calendar: Calendar = .current) -> Bool {
        !isToday(date, calendar: calendar) || date.timeIntervalSince(lessonsUpdatedAt) > maxAge
    }

    /// When a complication has to change: every bell left today, the run-up to each one, the
    /// hour before school, and midnight, when what it shows stops being true.
    public func timelineDates(from date: Date = .now, calendar: Calendar = .current) -> [Date] {
        let taking = todaysLessons(at: date, calendar: calendar).filter { !$0.isCancelled }
        var edges = taking.flatMap { lesson in
            [lesson.start, lesson.end, lesson.start - Self.runUp, lesson.end - Self.runUp]
        }
        if let first = taking.first { edges.append(first.start - Self.morningHour) }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return [date] + Set(edges + [midnight]).filter { $0 > date }.sorted()
    }

    /// How much the Smart Stack should want this moment, 0 to 1: most just before a bell,
    /// more still when what comes next has changed.
    public func relevance(at date: Date = .now, calendar: Calendar = .current) -> Double {
        let ahead = upcomingChange(at: date, calendar: calendar)
        switch moment(at: date, calendar: calendar) {
        case .unknown, .free, .over:
            return 0
        case .running(let lesson):
            guard lesson.end.timeIntervalSince(date) <= Self.runUp else { return 0.2 }
            return ahead ? 1 : 0.8
        case .waiting(let next, _):
            guard next.start.timeIntervalSince(date) <= Self.runUp else { return ahead ? 0.5 : 0.3 }
            return ahead ? 1 : 0.8
        }
    }

    /// Whether the very next thing on the timetable is different from the usual.
    private func upcomingChange(at date: Date, calendar: Calendar) -> Bool {
        let next = todaysLessons(at: date, calendar: calendar).first { $0.start > date }
        return next.map { $0.status != .regular } ?? false
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

// MARK: Where the day stands

extension WatchSnapshot {
    /// Ten minutes before a bell the next thing starts to matter.
    public static let runUp: TimeInterval = 10 * 60
    /// The first lesson's countdown starts an hour ahead; earlier it's just a time of day.
    public static let morningHour: TimeInterval = 60 * 60

    /// Heute and the complications read the same answer.
    public enum Moment: Equatable, Sendable {
        /// Nothing known about today.
        case unknown
        /// No lesson takes place today.
        case free
        /// A break or the morning. `since` is when the last lesson ended.
        case waiting(next: Lesson, since: Date?)
        case running(Lesson)
        case over

        public var lesson: Lesson? {
            switch self {
            case .running(let lesson), .waiting(let lesson, _): lesson
            case .unknown, .free, .over: nil
            }
        }

        /// What the countdown runs over; nil while the first lesson is more than an hour away.
        public func span(at date: Date = .now) -> ClosedRange<Date>? {
            switch self {
            case .running(let lesson):
                return lesson.start < lesson.end ? lesson.start...lesson.end : nil
            case .waiting(let next, let since):
                let start = since ?? next.start - WatchSnapshot.morningHour
                return start <= date && start < next.start ? start...next.start : nil
            case .unknown, .free, .over:
                return nil
            }
        }

        /// How much of the span is left, 1 down to 0.
        public func remaining(at date: Date = .now) -> Double? {
            guard let span = span(at: date) else { return nil }
            let total = span.upperBound.timeIntervalSince(span.lowerBound)
            return min(1, max(0, span.upperBound.timeIntervalSince(date) / total))
        }
    }

    public func moment(at date: Date = .now, calendar: Calendar = .current) -> Moment {
        guard knowsToday(at: date, calendar: calendar) else { return .unknown }
        if let lesson = current(at: date, calendar: calendar) { return .running(lesson) }
        if let lesson = next(after: date, calendar: calendar) {
            let since = todaysLessons(at: date, calendar: calendar)
                .filter { !$0.isCancelled && $0.end <= date }
                .map(\.end)
                .max()
            return .waiting(next: lesson, since: since)
        }
        return dayIsOver(at: date, calendar: calendar) ? .over : .free
    }

    /// What goes under the big lesson: a cancelled slot before it first, because that's the
    /// news, otherwise whatever follows it, cancelled or not.
    public func follower(at date: Date = .now, calendar: Calendar = .current) -> Lesson? {
        let today = todaysLessons(at: date, calendar: calendar)
        guard let hero = upcoming(at: date, calendar: calendar) else { return nil }
        if let gone = today.first(where: { $0.isCancelled && $0.end > date && $0.start < hero.start }) { return gone }
        return today.first { $0.id != hero.id && $0.start >= hero.end }
    }
}

// MARK: Over WatchConnectivity

extension WatchSnapshot {
    static let payloadKey = "pokyh.snapshot"
    /// WatchConnectivity refuses a context past about 64 KB, and the handoff shares it.
    static let payloadLimit = 48_000

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) -> WatchSnapshot? {
        try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    /// A property-list dictionary, to merge into applicationContext or a reply.
    public var payload: [String: Any] {
        guard let data = try? encoded() else { return [:] }
        if data.count <= Self.payloadLimit { return [Self.payloadKey: data] }
        // Too big would mean nothing arrives at all. Averages and the newest grades still fit.
        var smaller = self
        smaller.subjects = subjects.map { subject in
            var subject = subject
            subject.grades = nil
            return subject
        }
        guard let fitted = try? smaller.encoded() else { return [:] }
        return [Self.payloadKey: fitted]
    }

    /// nil when the payload has no snapshot in it.
    public init?(payload: [String: Any]) {
        guard let data = payload[Self.payloadKey] as? Data, let snapshot = Self.decoded(from: data) else { return nil }
        self = snapshot
    }
}
