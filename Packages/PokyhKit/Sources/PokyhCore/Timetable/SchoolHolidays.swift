import Foundation

/// One of the school's breaks: days as YYYY-MM-DD, with the real names WebUntis has for it.
public struct SchoolHoliday: Codable, Equatable, Sendable {
    public var start: String
    public var end: String
    public var names: [String]

    public init(start: String, end: String, names: [String] = []) {
        self.start = start
        self.end = end
        self.names = names
    }
}

/// getHolidays into the school's breaks (backend webuntis/holidays.ts).
public enum HolidayList {
    // "Ferien3", "Feiertag", "8.12.", "25/5/2026": a placeholder, not a name.
    static func isPlaceholder(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty
            || n.range(of: #"^(ferien|feiertag|holiday|vacanz[ae]|frei)\s*\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || n.range(of: #"^[\d./\s-]+$"#, options: .regularExpression) != nil
    }

    static func iso(_ n: Int?) -> String? {
        guard let n, n >= 10_000_000, n <= 99_999_999 else { return nil }
        return String(format: "%04d-%02d-%02d", n / 10000, (n / 100) % 100, n % 100)
    }

    private static func dayAfter(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        let calendar = Calendar(identifier: .gregorian)
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let next = calendar.date(byAdding: .day, value: 1, to: day) else { return iso }
        let c = calendar.dateComponents([.year, .month, .day], from: next)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// getHolidays' result into the breaks from `from` (YYYY-MM-DD) on, overlapping and adjoining
    /// ones merged.
    public static func read(_ result: Any?, from: String) -> [SchoolHoliday] {
        let entries = UntisValue.list(result).compactMap { item -> SchoolHoliday? in
            guard let row = item as? [String: Any],
                  let start = iso(UntisValue.int(row["startDate"])),
                  let end = iso(UntisValue.int(row["endDate"])), end >= start else { return nil }
            var names: [String] = []
            for raw in [row["longName"], row["name"]] {
                guard let name = (raw as? String)?.trimmingCharacters(in: .whitespaces),
                      !isPlaceholder(name), !names.contains(name) else { continue }
                names.append(name)
            }
            return SchoolHoliday(start: start, end: end, names: names)
        }
        .filter { $0.end >= from }
        .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }

        var merged: [SchoolHoliday] = []
        for holiday in entries {
            if var last = merged.last, holiday.start <= dayAfter(last.end) {
                last.end = max(last.end, holiday.end)
                for name in holiday.names where !last.names.contains(name) { last.names.append(name) }
                merged[merged.count - 1] = last
            } else {
                merged.append(holiday)
            }
        }
        return merged
    }

    /// The break a YYYYMMDD day falls in, if any.
    public static func on(_ dayNum: Int, in holidays: [SchoolHoliday]) -> SchoolHoliday? {
        guard let day = iso(dayNum) else { return nil }
        return holidays.first { $0.start <= day && day <= $0.end }
    }
}

/// Names the breaks an empty timetable stands for. WebUntis often calls them only "Ferien3", so a
/// break without a real name is named by when it is: the holidays of the Italian (and South
/// Tyrolean) school year and the public holidays around them. Gives a key into `holidayNames`.
public enum SchoolHolidays {
    private static let calendar = Calendar(identifier: .gregorian)

    /// Easter Sunday (anonymous Gregorian algorithm).
    public static func easterSunday(_ year: Int) -> Date {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private static let fixed: [String: String] = [
        "01-01": "newYear", "01-06": "epiphany", "04-25": "liberation", "05-01": "labour",
        "06-02": "republic", "08-15": "assumption", "11-01": "allSaints", "12-08": "immaculate",
        "12-25": "christmasDay", "12-26": "stStephen",
    ]

    public static func publicHoliday(on date: Date) -> String? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        if let key = fixed[String(format: "%02d-%02d", c.month ?? 0, c.day ?? 0)] { return key }
        let fromEaster = calendar.dateComponents([.day], from: easterSunday(c.year ?? 0), to: calendar.startOfDay(for: date)).day
        switch fromEaster {
        case 1: return "easterMonday"
        case 39: return "ascension"
        case 50: return "pentecost"
        case 60: return "corpusChristi"
        default: return nil
        }
    }

    /// What kind of break the days from `start` to `end` are (the web's holidayKey). A week that's
    /// empty from Monday to Sunday doesn't show how long the break really is, so there the time of
    /// year decides.
    public static func key(from start: Date, to end: Date, wholeWeek: Bool = false) -> String {
        let start = calendar.startOfDay(for: start), end = calendar.startOfDay(for: end)
        let length = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let startYear = calendar.component(.year, from: start)
        let month = calendar.component(.month, from: start)
        func covers(_ d: Date) -> Bool { d >= start && d <= end }
        func inside(_ m: Int, _ d: Int) -> Bool {
            [startYear, startYear + 1].contains { y in
                calendar.date(from: DateComponents(year: y, month: m, day: d)).map(covers) ?? false
            }
        }

        if inside(12, 25) || inside(1, 1) { return length >= 3 ? "christmas" : inside(12, 25) ? "christmasDay" : "newYear" }
        let easter = easterSunday(startYear)
        let easterMonday = calendar.date(byAdding: .day, value: 1, to: easter) ?? easter
        if length >= 3, covers(easter) || covers(easterMonday) { return "easter" }
        if wholeWeek {
            // The first days of January still belong to Christmas; a free week in summer is summer.
            if month == 1, calendar.component(.day, from: start) <= 7 { return "christmas" }
            let thursday = calendar.date(byAdding: .day, value: 3, to: start) ?? start
            if (6...9).contains(calendar.component(.month, from: thursday)) { return "summer" }
        }
        if length >= 3 {
            if length >= 21, (6...8).contains(month) { return "summer" }
            if month == 10 || month == 11 { return "autumn" }
            if month == 2 || (month == 3 && calendar.component(.day, from: start) <= 7) { return "carnival" }
        }
        var day = start
        while day <= end {
            if let key = publicHoliday(on: day) { return key }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(1)
        }
        return length >= 3 ? "break" : "dayOff"
    }

    /// A whole week without lessons, Monday to Sunday.
    public static func weekKey(_ monday: Date) -> String {
        key(from: monday, to: calendar.date(byAdding: .day, value: 6, to: monday) ?? monday, wholeWeek: true)
    }

    /// What kind of break one of the school's is, by its whole length.
    public static func key(of holiday: SchoolHoliday) -> String? {
        guard let start = date(holiday.start), let end = date(holiday.end) else { return nil }
        return key(from: start, to: end)
    }

    /// Its real name where WebUntis has one, else the name of when it is.
    public static func name(of holiday: SchoolHoliday, names: [String: String]) -> String? {
        holiday.names.first ?? key(of: holiday).flatMap { names[$0] }
    }

    /// The name of the break a YYYYMMDD day falls in, if it falls in one.
    public static func name(onDay dayNum: Int, in holidays: [SchoolHoliday], names: [String: String]) -> String? {
        HolidayList.on(dayNum, in: holidays).flatMap { name(of: $0, names: names) }
    }

    /// The break that covers most of a week's days, if it covers at least `minimum` of them. One
    /// free Wednesday doesn't name a whole week another break fills.
    public static func name(ofDays dayNums: [Int], in holidays: [SchoolHoliday], names: [String: String], atLeast minimum: Int = 1) -> String? {
        var best: (holiday: SchoolHoliday, days: Int)?
        for holiday in holidays {
            let days = dayNums.filter { HolidayList.on($0, in: [holiday]) != nil }.count
            if days >= max(1, minimum), days > (best?.days ?? 0) { best = (holiday, days) }
        }
        return best.flatMap { name(of: $0.holiday, names: names) }
    }

    private static func date(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
