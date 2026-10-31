import Foundation

/// Local days and the backend's timestamps as epoch milliseconds, on the Gregorian calendar
/// whatever the phone is set to. The bell's keys are built from these, so they have to come out
/// the same as on Android and the web.
public struct DayClock: Sendable {
    public let zone: TimeZone
    let calendar: Calendar

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return c
    }()

    public init(zone: TimeZone = .current) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        self.zone = zone
        calendar = c
    }

    public static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    func date(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    public func startOfDay(_ ms: Int64) -> Int64 {
        Self.ms(calendar.startOfDay(for: date(ms)))
    }

    /// The same calendar day `n` days later. Daylight saving keeps the midnight.
    public func addDays(_ ms: Int64, _ n: Int) -> Int64 {
        let day = calendar.startOfDay(for: date(ms))
        guard let moved = calendar.date(byAdding: .day, value: n, to: day) else { return ms }
        return Self.ms(calendar.startOfDay(for: moved))
    }

    /// YYYYMMDD at local midnight; 0 for something that isn't a date.
    public func untisDay(_ num: Int) -> Int64 {
        let parts = DateComponents(year: num / 10000, month: num / 100 % 100, day: num % 100)
        guard parts.isValidDate(in: calendar), let date = calendar.date(from: parts) else { return 0 }
        return Self.ms(date)
    }

    public func parts(_ ms: Int64) -> (year: Int, month: Int, day: Int, hour: Int, minute: Int) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date(ms))
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// An ISO date-time, with or without a zone, or a plain date. Nil when it can't be read.
    public func parse(_ raw: String?) -> Int64? {
        guard let raw else { return nil }
        let u = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard u.count >= 10, u[4] == 0x2D, u[7] == 0x2D,
              let year = Self.number(u, 0..<4), let month = Self.number(u, 5..<7), let day = Self.number(u, 8..<10)
        else { return nil }
        var parts = DateComponents(year: year, month: month, day: day)
        guard parts.isValidDate(in: calendar) else { return nil }
        let dayOnly = calendar.date(from: parts).map(Self.ms)

        guard u.count >= 16, u[10] == 0x54 || u[10] == 0x74 || u[10] == 0x20, u[13] == 0x3A,
              let hour = Self.number(u, 11..<13), let minute = Self.number(u, 14..<16),
              hour < 24, minute < 60
        else { return dayOnly }
        parts.hour = hour
        parts.minute = minute

        var i = 16
        var millis: Int64 = 0
        if i < u.count, u[i] == 0x3A, let second = Self.number(u, (i + 1)..<(i + 3)), second < 61 {
            parts.second = second
            i += 3
            if i < u.count, u[i] == 0x2E {
                i += 1
                var scale: Int64 = 100
                while i < u.count, (0x30...0x39).contains(u[i]) {
                    millis += Int64(u[i] - 0x30) * scale
                    scale /= 10
                    i += 1
                }
            }
        }

        // A zone on it: read it in UTC and take the offset off. Without one it's local time.
        guard let offset = Self.offsetMinutes(u, from: i) else {
            return calendar.date(from: parts).map { Self.ms($0) + millis }
        }
        return Self.utc.date(from: parts).map { Self.ms($0) + millis - Int64(offset) * 60_000 }
    }

    private static func number(_ u: [UInt8], _ range: Range<Int>) -> Int? {
        guard range.upperBound <= u.count else { return nil }
        var out = 0
        for i in range {
            guard (0x30...0x39).contains(u[i]) else { return nil }
            out = out * 10 + Int(u[i] - 0x30)
        }
        return out
    }

    private static func offsetMinutes(_ u: [UInt8], from i: Int) -> Int? {
        guard i < u.count else { return nil }
        if u[i] == 0x5A || u[i] == 0x7A { return 0 }
        guard u[i] == 0x2B || u[i] == 0x2D, let hours = number(u, (i + 1)..<(i + 3)) else { return nil }
        var minutes = 0
        if let m = number(u, (i + 4)..<(i + 6)), u[i + 3] == 0x3A {
            minutes = m
        } else if let m = number(u, (i + 3)..<(i + 5)) {
            minutes = m
        }
        let total = hours * 60 + minutes
        return u[i] == 0x2B ? total : -total
    }
}
