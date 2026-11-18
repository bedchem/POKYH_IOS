import Foundation

// iOS-only, like WatchStrings: the few texts the watch pages and complications need on top of
// the app's own tables.

public struct WatchTexts: Sendable {
    public let updated: @Sendable (String) -> String
    public let updatedYesterday: @Sendable (String) -> String
    public let noDataTitle: String
    /// With the app's name.
    public let noDataText: @Sendable (String) -> String
    /// A tick not yet at the backend.
    public let queued: String
    public let instead: @Sendable (String) -> String
    /// When the next lesson starts, from a break: "in 5 Min".
    public let startsIn: @Sendable (String) -> String
    /// The page with the day's circle.
    public let schoolDay: String
    /// When the last lesson ends: "bis 13:20".
    public let until: @Sendable (String) -> String
    /// Units beside a big number.
    public let hourUnit: String
    public let minuteUnit: String
    /// The room complication.
    public let roomTitle: String
    public let roomInfo: String
    public let free: String
    public let weekend: String

    public static func of(_ lang: Lang) -> WatchTexts {
        switch lang {
        case .de: de
        case .it: it
        case .en: en
        }
    }

    static let de = WatchTexts(
        updated: { "Stand von \($0)" },
        updatedYesterday: { "Stand von gestern, \($0)" },
        noDataTitle: "Noch nichts da",
        noDataText: { "Öffne \($0) auf dem iPhone." },
        queued: "Noch nicht gesendet",
        instead: { "statt \($0)" },
        startsIn: { "in \($0)" },
        schoolDay: "Schultag",
        until: { "bis \($0)" },
        hourUnit: "Std",
        minuteUnit: "Min",
        roomTitle: "Raum",
        roomInfo: "In welchen Raum und wie lange noch.",
        free: "Frei",
        weekend: "Wochenende"
    )

    static let it = WatchTexts(
        updated: { "Aggiornato \($0)" },
        updatedYesterday: { "Aggiornato ieri, \($0)" },
        noDataTitle: "Ancora niente",
        noDataText: { "Apri \($0) sull’iPhone." },
        queued: "Non ancora inviato",
        instead: { "invece di \($0)" },
        startsIn: { "tra \($0)" },
        schoolDay: "Giornata",
        until: { "fino alle \($0)" },
        hourUnit: "h",
        minuteUnit: "min",
        roomTitle: "Aula",
        roomInfo: "In quale aula e per quanto ancora.",
        free: "Libero",
        weekend: "Fine settimana"
    )

    static let en = WatchTexts(
        updated: { "Updated \($0)" },
        updatedYesterday: { "Updated yesterday, \($0)" },
        noDataTitle: "Nothing yet",
        noDataText: { "Open \($0) on your iPhone." },
        queued: "Not sent yet",
        instead: { "instead of \($0)" },
        startsIn: { "in \($0)" },
        schoolDay: "School day",
        until: { "until \($0)" },
        hourUnit: "h",
        minuteUnit: "min",
        roomTitle: "Room",
        roomInfo: "Which room, and for how long.",
        free: "Free",
        weekend: "Weekend"
    )
}

/// Clock times and marks the way the app writes them. 24 hours in every language, like the timetable.
public enum WatchFormat {
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// A single mark without needless zeros: 8, 8,5, 7,25.
    public static func mark(_ value: Double, decimal: Character) -> String {
        var text = String(format: "%.2f", (value * 100).rounded() / 100)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: String(decimal))
    }

    /// An average, always two places: 7,50.
    public static func average(_ value: Double, decimal: Character) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: String(decimal))
    }

    /// A countdown: 23:41, 1:02:09. Rounded up, so it says 0:00 only at the bell.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// "Stand von 10:42", "Stand von gestern, 18:03", "Stand von 28.10.".
    public static func stamp(_ date: Date, now: Date = .now, texts: WatchTexts, common: CommonStrings, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return texts.updated(clock(date, calendar: calendar)) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return texts.updatedYesterday(clock(date, calendar: calendar))
        }
        let c = calendar.dateComponents([.day, .month], from: date)
        return texts.updated(common.dayMonthShort(c.day ?? 1, c.month ?? 1))
    }
}
