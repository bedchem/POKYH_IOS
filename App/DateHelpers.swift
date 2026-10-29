import Foundation

/// Wiederverwendbare DateFormatter. Das Erzeugen eines DateFormatters ist teuer
/// (~Millisekunden) — in Render-Hot-Paths (z. B. `dayNum` im Stundenplan) wurde
/// pro Aufruf einer neu alloziert. Geteilte Instanzen sind ab iOS 7 thread-safe
/// für die Formatierung, daher hier zentral gebündelt.
enum DateFmt {
    /// `yyyy-MM-dd` (POSIX) — WebUntis-API & Wochenberechnung.
    static let iso = make("yyyy-MM-dd")
    /// `yyyyMMdd` (POSIX) — interne Tages-IDs (Int).
    static let compact = make("yyyyMMdd")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    /// Tages-ID (yyyyMMdd als Int) eines Datums.
    static func num(_ date: Date) -> Int { Int(compact.string(from: date)) ?? 0 }
    /// ISO-String (yyyy-MM-dd) eines Datums.
    static func isoString(_ date: Date) -> String { iso.string(from: date) }
}

enum SchoolDates {
    static func todayISO() -> String { DateFmt.isoString(Date()) }
    static func todayNum() -> Int { DateFmt.num(Date()) }
    /// Montag der Woche, die `date` enthält (yyyy-MM-dd).
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
