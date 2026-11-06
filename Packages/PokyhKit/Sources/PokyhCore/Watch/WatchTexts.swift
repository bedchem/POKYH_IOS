import Foundation

// iOS-only, like WatchStrings: the few texts the watch pages and complications need on top of
// the app's own tables.

public struct WatchTexts: Sendable {
    public let updated: @Sendable (String) -> String
    public let updatedYesterday: @Sendable (String) -> String
    public let noDataTitle: String
    public let noDataText: String
    public let phoneAway: String
    public let queued: String
    public let instead: @Sendable (String) -> String
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
        noDataText: "Öffne POKYH auf dem iPhone.",
        phoneAway: "iPhone nicht erreichbar",
        queued: "Wartet aufs iPhone",
        instead: { "statt \($0)" },
        free: "Frei",
        weekend: "Wochenende"
    )

    static let it = WatchTexts(
        updated: { "Aggiornato \($0)" },
        updatedYesterday: { "Aggiornato ieri, \($0)" },
        noDataTitle: "Ancora niente",
        noDataText: "Apri POKYH sull’iPhone.",
        phoneAway: "iPhone non raggiungibile",
        queued: "In attesa dell’iPhone",
        instead: { "invece di \($0)" },
        free: "Libero",
        weekend: "Fine settimana"
    )

    static let en = WatchTexts(
        updated: { "Updated \($0)" },
        updatedYesterday: { "Updated yesterday, \($0)" },
        noDataTitle: "Nothing yet",
        noDataText: "Open POKYH on your iPhone.",
        phoneAway: "iPhone out of reach",
        queued: "Waiting for iPhone",
        instead: { "instead of \($0)" },
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
