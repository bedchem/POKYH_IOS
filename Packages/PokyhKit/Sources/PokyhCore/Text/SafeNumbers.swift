import Foundation

public extension Int {
    /// `Int(Double)` traps on NaN, infinity and anything out of range, and most of our doubles come
    /// straight from a server. NaN is 0, the rest stops at the ends.
    init(saturating value: Double) {
        if value.isNaN {
            self = 0
        } else if value >= 9.2e18 {
            self = .max
        } else if value <= -9.2e18 {
            self = .min
        } else {
            self = Int(value)
        }
    }
}

/// A grade without trailing zeros, the German way (8 / 8,5).
public enum MarkText {
    public static func string(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        guard rounded.isFinite else { return "–" }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    /// Whether a server's value can be a grade at all. Schools use different scales, so this only
    /// keeps out what would break the sums: NaN, infinity and absurd sizes.
    public static func isUsable(_ value: Double) -> Bool {
        value.isFinite && abs(value) <= 100_000
    }
}

/// WebUntis dates and times as they should come: YYYYMMDD, and HHMM or minutes of the day. Anything
/// bigger is no date, and would overflow once it's multiplied up into a sort key.
public enum UntisRange {
    public static func day(_ value: Int?) -> Int {
        guard let value, (0...99_999_999).contains(value) else { return 0 }
        return value
    }

    public static func clock(_ value: Int?) -> Int {
        guard let value, (0...9_999).contains(value) else { return 0 }
        return value
    }

    /// HHMM (750) or minutes since midnight (470) into HHMM.
    public static func hhmm(_ value: Int) -> Int {
        let number = clock(value)
        let minutes = (number > 2359 || number % 100 > 59) ? number : (number / 100) * 60 + number % 100
        return (minutes / 60) * 100 + minutes % 60
    }

    /// A count of minutes or hours nothing sane goes past: a sum of a whole school year stays far
    /// from overflowing with this.
    public static func amount(_ value: Int?) -> Int {
        guard let value else { return 0 }
        return Swift.min(Swift.max(0, value), 1_000_000)
    }
}
