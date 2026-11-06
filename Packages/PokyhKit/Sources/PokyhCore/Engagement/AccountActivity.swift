import Foundation

/// /users/me/activity: what the POKYH server already keeps about the account's use. Parsed by
/// hand so that one bad field empties itself instead of failing the whole screen.
public struct AccountActivity: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public var date: String
        public var active: Bool
        public var logins: Int
        public var activeSeconds: Int

        public init(date: String, active: Bool, logins: Int = 0, activeSeconds: Int = 0) {
            self.date = date
            self.active = active
            self.logins = logins
            self.activeSeconds = activeSeconds
        }
    }

    public struct Totals: Equatable, Sendable {
        public var activeDays = 0
        public var logins = 0
        public var activeSeconds = 0
        public var visits = 0
        public var screens = 0
        public var currentStreak = 0
        public var longestStreak = 0
    }

    public struct Platforms: Equatable, Sendable {
        public var phone = 0
        public var desktop = 0
        public var app = 0
        public var web = 0
    }

    public struct Page: Equatable, Sendable {
        public var page: String
        public var views: Int
    }

    public struct Created: Equatable, Sendable {
        public var todosDone = 0
        public var todosOpen = 0
        public var reminders = 0
        public var comments = 0
        public var ratings = 0
    }

    public var usageConsent: Bool
    public var memberSince: String?
    public var days: [Day]
    public var totals: Totals
    /// Active days per weekday, Monday first.
    public var weekdays: [Int]
    /// Foreground seconds by the hour a visit started in.
    public var hours: [Int]
    public var platforms: Platforms
    public var pages: [Page]
    public var created: Created

    /// nil when it isn't a JSON object at all.
    public init?(data: Data) {
        let json = LooseJSON(data: data)
        guard json.object != nil else { return nil }
        usageConsent = json["usageConsent"].bool == true
        memberSince = json["memberSince"].string
        // A school year is at most 366 days; anything far past that is no answer to show.
        days = json["days"].array.suffix(Self.mostDays).compactMap { day in
            guard let date = day["date"].string else { return nil }
            return Day(date: date, active: day["active"].bool == true,
                       logins: day["logins"].count, activeSeconds: day["activeSeconds"].count)
        }
        let t = json["totals"]
        totals = Totals(activeDays: t["activeDays"].count, logins: t["logins"].count, activeSeconds: t["activeSeconds"].count,
                        visits: t["visits"].count, screens: t["screens"].count,
                        currentStreak: t["currentStreak"].count, longestStreak: t["longestStreak"].count)
        weekdays = json["weekdays"].array.map(\.count)
        hours = json["hours"].array.map(\.count)
        let p = json["platforms"]
        platforms = Platforms(phone: p["phone"].count, desktop: p["desktop"].count, app: p["app"].count, web: p["web"].count)
        pages = json["pages"].array.prefix(20).compactMap { row in
            guard let page = row["page"].string else { return nil }
            return Page(page: page, views: row["views"].count)
        }
        let c = json["created"]
        created = Created(todosDone: c["todosDone"].count, todosOpen: c["todosOpen"].count, reminders: c["reminders"].count,
                          comments: c["comments"].count, ratings: c["ratings"].count)
    }

    private static let mostDays = 400

    // ── Figures ──────────────────────────────────────────────────────────────

    /// Time in POKYH per day that has any, nil before the first one.
    public var averageSeconds: Int? {
        let withTime = days.count { $0.activeSeconds > 0 }
        return withTime > 0 ? totals.activeSeconds / withTime : nil
    }

    /// "Mai 2026", from a timestamp that starts with a date.
    public func memberSinceText(_ strings: Strings) -> String? {
        guard let memberSince, let date = ActivityDate(iso: String(memberSince.prefix(10))),
              strings.common.months.indices.contains(date.month - 1) else { return nil }
        let month = strings.common.months[date.month - 1]
        return "\(month.prefix(1).uppercased())\(month.dropFirst()) \(date.year)"
    }

    public static func pageName(_ page: String, _ strings: Strings) -> String {
        strings.profile.pageNames[page.trimmingCharacters(in: CharacterSet(charactersIn: "/"))] ?? page
    }

    /// "12 min", "2 h 5 min".
    public static func duration(_ seconds: Int) -> String {
        let minutes = Int(saturating: (Double(seconds) / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

// ── Bars ─────────────────────────────────────────────────────────────────────

/// One column of a chart, the tallest one marked.
public struct ActivityColumn: Equatable, Identifiable, Sendable {
    public var label: String
    public var value: Int
    /// 0...1 of the chart's height. Never quite nothing, so an empty day still reads as a day.
    public var height: Double
    public var isTallest: Bool
    public var id: String { label }

    /// Bars for `values`, with `labels` beside them: none at all when the two don't line up.
    public static func columns(values: [Int], labels: [String]) -> [ActivityColumn] {
        guard !values.isEmpty, values.count == labels.count, Set(labels).count == labels.count else { return [] }
        let tallest = values.max() ?? 0
        let first = tallest > 0 ? values.firstIndex(of: tallest) : nil
        return values.indices.map { i in
            let share = Double(values[i]) / Double(max(tallest, 1))
            return ActivityColumn(label: labels[i], value: values[i], height: max(share, values[i] > 0 ? 0.05 : 0.02), isTallest: i == first)
        }
    }
}

extension AccountActivity {
    /// The waking hours, 6 to 22.
    public var hourColumns: [ActivityColumn] {
        guard hours.count >= 23 else { return [] }
        return ActivityColumn.columns(values: Array(hours[6...22]), labels: (6...22).map(String.init))
    }

    public func weekdayColumns(_ strings: Strings) -> [ActivityColumn] {
        ActivityColumn.columns(values: weekdays, labels: strings.common.weekdaysShort)
    }
}

/// Width of a horizontal bar: how much of the largest it is.
public enum ActivityShare {
    public static func of(_ value: Int, among values: [Int]) -> Double {
        let largest = values.max() ?? 0
        return largest > 0 ? min(1, max(0, Double(value) / Double(largest))) : 0
    }
}

// ── The grid of days ─────────────────────────────────────────────────────────

/// A real calendar day from "YYYY-MM-DD", nil for anything else.
public struct ActivityDate: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    /// Monday is 0.
    public var weekday: Int

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return c
    }()

    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard year >= 1, components.isValidDate(in: Self.calendar),
              let date = Self.calendar.date(from: components) else { return nil }
        self.year = year
        self.month = month
        self.day = day
        // .weekday counts from Sunday, 1 up.
        weekday = (Self.calendar.component(.weekday, from: date) + 5) % 7
    }
}

/// The days the way GitHub draws contributions: one column per week, Monday on top.
public struct ActivityGridLayout: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        public var date: ActivityDate
        public var day: AccountActivity.Day
        public var level: Int
        public var isLast: Bool
    }

    public struct MonthStart: Equatable, Sendable {
        public var column: Int
        public var month: Int
    }

    public var weeks: [[Cell?]]
    public var months: [MonthStart]

    /// A whole school year draws smaller squares.
    public var isDense: Bool { weeks.count > 20 }

    /// Days whose date is no date are left out.
    public init(days: [AccountActivity.Day]) {
        let cells = days.compactMap { day in
            ActivityDate(iso: day.date).map { Cell(date: $0, day: day, level: Self.level(of: day), isLast: false) }
        }
        var slots: [Cell?] = Array(repeating: nil, count: cells.first?.date.weekday ?? 0)
        slots.append(contentsOf: cells.enumerated().map { index, cell in
            var cell = cell
            cell.isLast = index == cells.count - 1
            return cell
        })
        weeks = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<min($0 + 7, slots.count)]) }
        var last = 0
        let starts: [MonthStart] = weeks.enumerated().compactMap { column, week in
            guard let first = week.lazy.compactMap({ $0 }).first, first.date.month != last else { return nil }
            last = first.date.month
            return MonthStart(column: column, month: first.date.month)
        }
        // A name needs about three weeks before the next one and two before the edge, or it runs
        // into them; a month the window only just catches goes unnamed.
        let end = weeks.count
        months = starts.enumerated().compactMap { index, start in
            let next = starts.indices.contains(index + 1) ? starts[index + 1].column : Int.max
            return next - start.column >= Self.labelColumns && end - start.column >= 2 ? start : nil
        }
    }

    static let labelColumns = 3

    /// Strength 0 to 4: minutes when known, else sign-ins.
    public static func level(of day: AccountActivity.Day) -> Int {
        guard day.active else { return 0 }
        let minutes = Double(day.activeSeconds) / 60
        if minutes > 0 {
            return minutes >= 45 ? 4 : minutes >= 20 ? 3 : minutes >= 5 ? 2 : 1
        }
        return day.logins >= 3 ? 4 : day.logins == 2 ? 3 : day.logins == 1 ? 2 : 1
    }

    /// "Mo., 3. Nov. · 2 Anmeldungen · 12 min in POKYH"
    public static func describe(_ cell: Cell, _ strings: Strings) -> String {
        let shorts = strings.common.weekdaysShort
        let weekday = shorts.indices.contains(cell.date.weekday) ? shorts[cell.date.weekday] : ""
        let label = "\(weekday), \(strings.common.dayMonthShort(cell.date.day, cell.date.month))"
        guard cell.day.active else { return "\(label) · \(strings.profile.notOnline)" }
        var parts = [label]
        if cell.day.logins > 0 { parts.append(strings.profile.loginCount(cell.day.logins)) }
        if cell.day.activeSeconds >= 60 { parts.append(strings.profile.inPokyh(AccountActivity.duration(cell.day.activeSeconds))) }
        if parts.count == 1 { parts.append(strings.profile.online) }
        return parts.joined(separator: " · ")
    }
}
