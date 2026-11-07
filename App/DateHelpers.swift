import Foundation

/// Shared date formatters. Making one costs about a millisecond, and the timetable
/// (`dayNum`) used to make one per call. Formatting with a shared one is thread-safe.
enum DateFmt {
    /// `yyyy-MM-dd` (POSIX): the WebUntis API and week math.
    static let iso = make("yyyy-MM-dd")
    /// `yyyyMMdd` (POSIX): day ids as Int.
    static let compact = make("yyyyMMdd")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    /// One formatter per pattern and language, made once: rows used to build a new one per call.
    nonisolated static func formatter(_ pattern: String, locale: Locale = Locale(identifier: "en_US_POSIX")) -> DateFormatter {
        let key = pattern + "|" + locale.identifier
        return lock.withLock {
            if let made = made[key] { return made }
            let f = DateFormatter()
            f.locale = locale
            f.dateFormat = pattern
            made[key] = f
            return f
        }
    }
    nonisolated(unsafe) private static var made: [String: DateFormatter] = [:]
    nonisolated private static let lock = NSLock()

    /// A date's day id (yyyyMMdd as Int).
    static func num(_ date: Date) -> Int { Int(compact.string(from: date)) ?? 0 }
    /// A date as yyyy-MM-dd.
    static func isoString(_ date: Date) -> String { iso.string(from: date) }
}

enum SchoolDates {
    static func todayISO() -> String { DateFmt.isoString(Date()) }
    static func todayNum() -> Int { DateFmt.num(Date()) }
    /// The Monday of `date`'s week (yyyy-MM-dd).
    static func mondayISO(of date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let monday = cal.date(from: comps) ?? date
        return DateFmt.isoString(monday)
    }
    static var currentSchoolYear: Int {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return (c.month ?? 1) >= 9 ? (c.year ?? 0) : (c.year ?? 0) - 1
    }
    static func yearStart(_ year: Int? = nil) -> String {
        let y = year ?? currentSchoolYear
        return "\(y)0901"
    }
    static func yearEnd(_ year: Int? = nil) -> String {
        let y = year ?? currentSchoolYear
        return "\(y + 1)0630"
    }
    static let availableYears: [Int] = (0..<4).map { currentSchoolYear - $0 }
}
