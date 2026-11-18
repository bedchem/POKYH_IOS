import Foundation
import Synchronization

// The rules that turn grades, to-dos and the menu into the watch's small models. The phone and
// the watch both go through them, so a part looks the same whichever side loaded it.

/// The grades part of a snapshot.
public struct WatchGrades: Sendable, Equatable {
    public var overall: Double?
    public var count: Int
    public var subjects: [WatchSnapshot.SubjectAverage]
    public var recent: [WatchSnapshot.Grade]

    /// One grade as WebUntis lists it. `value` is the display value; `date` is YYYYMMDD.
    public struct Mark: Sendable, Equatable {
        public var id: Int
        public var value: Double
        public var date: Int
        public var text: String

        public init(id: Int, value: Double, date: Int, text: String = "") {
            self.id = id
            self.value = value
            self.date = date
            self.text = text
        }
    }

    public struct Subject: Sendable, Equatable {
        public var name: String
        public var marks: [Mark]

        public init(name: String, marks: [Mark]) {
            self.name = name
            self.marks = marks
        }
    }

    // Keeps the context small; nobody scrolls further on a wrist.
    static let maxRecent = 5
    static let maxPerSubject = 12
    static let maxText = 60

    /// A flat mean over every single grade, like Home and the Grades tab; newest by id, as the web does.
    public init(_ subjects: [Subject], calendar: Calendar = .current) {
        let marked = subjects.map { Subject(name: $0.name, marks: $0.marks.filter { $0.value > 0 }) }
        let values = marked.flatMap { $0.marks.map(\.value) }
        overall = values.isEmpty ? nil : Self.average(values)
        count = values.count
        self.subjects = marked.compactMap { subject in
            guard !subject.marks.isEmpty else { return nil }
            let newest = subject.marks.sorted { $0.id > $1.id }.prefix(Self.maxPerSubject)
            return WatchSnapshot.SubjectAverage(name: subject.name, average: Self.average(subject.marks.map(\.value)),
                                                count: subject.marks.count,
                                                grades: newest.map { Self.grade($0, in: subject.name, calendar: calendar) })
        }
        recent = marked
            .flatMap { subject in subject.marks.map { (subject.name, $0) } }
            .sorted { $0.1.id > $1.1.id }
            .prefix(Self.maxRecent)
            .map { Self.grade($0.1, in: $0.0, calendar: calendar) }
    }

    /// Rounded to two places, as the app shows it.
    static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return (values.reduce(0, +) / Double(values.count) * 100).rounded() / 100
    }

    static func grade(_ mark: Mark, in subject: String, calendar: Calendar) -> WatchSnapshot.Grade {
        WatchSnapshot.Grade(id: mark.id, subject: subject, value: mark.value,
                            date: BackendDate.day(mark.date, calendar: calendar), text: String(mark.text.prefix(maxText)))
    }
}

/// As on the web: the open ones by due date (none last), then newest first; the done ones after
/// them, last ticked off first, each gone a day after it was ticked off.
public enum TodoArrangement {
    public static func arranged<T>(_ todos: [T], now: Date = Date(), done: (T) -> Bool, dueAt: (T) -> Date?,
                                   doneAt: (T) -> Date?, createdAt: (T) -> Date?) -> [T] {
        let kept = todos.filter { todo in
            guard done(todo), let ticked = doneAt(todo) else { return true }
            return now.timeIntervalSince(ticked) < 86_400
        }
        let open = kept.filter { !done($0) }.sorted { a, b in
            let da = dueAt(a) ?? .distantFuture, db = dueAt(b) ?? .distantFuture
            if da != db { return da < db }
            return (createdAt(a) ?? .distantPast) > (createdAt(b) ?? .distantPast)
        }
        let finished = kept.filter(done).sorted { (doneAt($0) ?? .distantPast) > (doneAt($1) ?? .distantPast) }
        return open + finished
    }
}

/// The to-dos part of a snapshot.
public enum WatchTodos {
    /// A to-do as the backend sends it.
    public struct Item: Sendable, Equatable {
        public var id: String
        public var title: String
        public var dueAt: String?
        public var done: Bool
        public var doneAt: String?
        public var createdAt: String?

        public init(id: String, title: String, dueAt: String? = nil, done: Bool = false, doneAt: String? = nil, createdAt: String? = nil) {
            self.id = id
            self.title = title
            self.dueAt = dueAt
            self.done = done
            self.doneAt = doneAt
            self.createdAt = createdAt
        }
    }

    static let maxTodos = 30
    static let maxTitle = 120

    public static func build(_ items: [Item], now: Date = Date()) -> [WatchSnapshot.Todo] {
        let arranged = TodoArrangement.arranged(items, now: now, done: \.done, dueAt: { $0.dueAt.flatMap(BackendDate.parse) },
                                                doneAt: { $0.doneAt.flatMap(BackendDate.parse) },
                                                createdAt: { $0.createdAt.flatMap(BackendDate.parse) })
        return arranged.prefix(maxTodos).map {
            WatchSnapshot.Todo(id: $0.id, title: String($0.title.prefix(maxTitle)), due: $0.dueAt.flatMap(BackendDate.parse), done: $0.done)
        }
    }

    /// GET /users/<name>/todos. nil for anything that isn't a list.
    public static func items(from data: Data) -> [Item]? {
        guard let list = LooseJSON(data: data).raw as? [Any] else { return nil }
        return list.map(LooseJSON.init(raw:)).compactMap { json in
            guard let id = json["id"].string, !id.isEmpty else { return nil }
            return Item(id: id, title: json["title"].string ?? "", dueAt: json["dueAt"].string,
                        done: json["done"].bool ?? false, doneAt: json["doneAt"].string, createdAt: json["createdAt"].string)
        }
    }
}

/// The Mensa part of a snapshot.
public enum WatchMensa {
    /// A dish of the menu and the day it's served (YYYY-MM-DD…).
    public struct Served: Sendable, Equatable {
        public var date: String
        public var dish: WatchSnapshot.Dish

        public init(date: String, dish: WatchSnapshot.Dish) {
            self.date = date
            self.dish = dish
        }
    }

    static let maxText = 160

    /// Same date rule as Home: today, or the next day the menu has.
    public static func menu(_ served: [Served], now: Date = Date(), calendar: Calendar = .current) -> (day: Date?, dishes: [WatchSnapshot.Dish]) {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: [WatchSnapshot.Dish]] = [:]
        for item in served {
            guard let date = BackendDate.isoDay(String(item.date.prefix(10)), calendar: calendar) else { continue }
            byDay[calendar.startOfDay(for: date), default: []].append(item.dish)
        }
        guard let day = byDay.keys.sorted().first(where: { $0 >= today && !(byDay[$0] ?? []).isEmpty }) else { return (nil, []) }
        return (day, byDay[day] ?? [])
    }

    /// GET /dishes: a bare list, `{menu: {dishes}}`, `{dishes}` or `{data}`. Pictures the backend
    /// keeps itself come as a path and go behind `backend`.
    public static func served(from data: Data, backend: URL) -> [Served] {
        let json = LooseJSON(data: data)
        var list = json.array
        if list.isEmpty { list = json["menu"]["dishes"].array }
        if list.isEmpty { list = json["dishes"].array }
        if list.isEmpty { list = json["data"].array }
        return list.compactMap { dish in
            guard let id = dish["id"].string, !id.isEmpty else { return nil }
            let text = localized(dish["description"])
            return Served(date: dish["date"].string ?? "", dish: WatchSnapshot.Dish(
                id: id,
                name: localized(dish["name"]),
                category: dish["category"].string ?? "",
                tags: dish["tags"].array.compactMap(\.string),
                photo: BackendLink.resolve(dish["imageUrl"].string, against: backend),
                text: text.isEmpty ? nil : String(text.prefix(maxText)),
                price: dish["price"].double.flatMap { $0 > 0 && MarkText.isUsable($0) ? $0 : nil },
                calories: dish["calories"].double.flatMap { $0 > 0 && MarkText.isUsable($0) ? $0 : nil }
            ))
        }
    }

    /// POST /dish-ratings/batch: the mean of one to five stars and how many there are, per dish.
    public static func ratings(from data: Data) -> [String: (stars: Double?, count: Int)] {
        guard let object = LooseJSON(data: data).object else { return [:] }
        var out: [String: (stars: Double?, count: Int)] = [:]
        for (id, value) in object {
            let votes = (LooseJSON(raw: value)["ratings"].object ?? [:]).values.map { vote in
                min(5, max(0, LooseJSON(raw: vote).double ?? 0))
            }
            out[id] = (votes.isEmpty ? nil : votes.reduce(0, +) / Double(votes.count), votes.count)
        }
        return out
    }

    /// The ratings on the dishes they belong to; the others keep theirs.
    public static func rated(_ dishes: [WatchSnapshot.Dish], with ratings: [String: (stars: Double?, count: Int)]) -> [WatchSnapshot.Dish] {
        dishes.map { dish in
            guard let rating = ratings[dish.id] else { return dish }
            var dish = dish
            dish.stars = rating.count > 0 ? rating.stars : nil
            dish.ratings = rating.count
            return dish
        }
    }

    /// A name the backend may send per language; German first, as the app reads it.
    static func localized(_ json: LooseJSON) -> String {
        if let text = json.string { return text }
        return json["de"].string ?? json["it"].string ?? json["en"].string ?? ""
    }
}

/// Dates the way the backend and WebUntis write them, read in the device's time zone.
public enum BackendDate {
    /// ISO 8601 with or without fractions, then the plainer forms some answers use.
    public static func parse(_ text: String) -> Date? {
        if let date = iso.withLock({ $0.date(from: text) }) { return date }
        if let date = isoFraction.withLock({ $0.date(from: text) }) { return date }
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            if let date = plain(pattern, text, calendar: .current) { return date }
        }
        return nil
    }

    /// "2026-10-30" at midnight.
    public static func isoDay(_ text: String, calendar: Calendar = .current) -> Date? {
        plain("yyyy-MM-dd", text, calendar: calendar)
    }

    /// WebUntis' YYYYMMDD at midnight; nil for 0 and anything that isn't a day.
    public static func day(_ yyyymmdd: Int, calendar: Calendar = .current) -> Date? {
        let value = UntisRange.day(yyyymmdd)
        let year = value / 10000, month = value / 100 % 100, day = value % 100
        guard year > 0, (1...12).contains(month), (1...31).contains(day) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func plain(_ pattern: String, _ text: String, calendar: Calendar) -> Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = pattern
        return format.date(from: text)
    }

    private static let iso = Mutex(ISO8601DateFormatter())
    private static let isoFraction: Mutex<ISO8601DateFormatter> = {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Mutex(format)
    }()
}
