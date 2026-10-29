// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct BellStrings: Sendable {
    public let title: String
    public let labelNew: @Sendable (Int) -> String
    public let newCount: @Sendable (Int) -> String
    public let clear: String
    public let clearAll: String
    public let streakLost: @Sendable (Int) -> String
    public let streakLostSub: String
    public let streakDays: @Sendable (Int) -> String
    public let streakOne: String
    public let streakNone: String
    public let streakLongest: @Sendable (Int) -> String
    public let streakKeep: String
    public let milestone: @Sendable (Int) -> String
    public let milestoneSub: String
    public let gradeNew: @Sendable (String) -> String
    public let reminderBy: @Sendable (String) -> String
    public let reminderSoon: String
    public let todoDue: String
    public let todoOverdue: String
    public let today: String
    public let yesterday: String
    public let todayAt: @Sendable (String) -> String
    public let tomorrowAt: @Sendable (String) -> String
    public let yesterdayAt: @Sendable (String) -> String
    public let inMinutes: @Sendable (Int) -> String
    public let inHours: @Sendable (Int) -> String
    public let emptyTitle: String
    public let emptyText: String
    public let noSubject: String
}


extension BellStrings {
    static let de = BellStrings(
        title: "Benachrichtigungen",
        labelNew: { "Benachrichtigungen, \($0) neu" },
        newCount: { "\($0) neu" },
        clear: "Entfernen",
        clearAll: "Alle entfernen",
        streakLost: { "Deine Serie von \($0) Tagen ist vorbei" },
        streakLostSub: "Fang heute eine neue an",
        streakDays: { "\($0) Tage in Folge" },
        streakOne: "1 Tag in Folge",
        streakNone: "Heute startet deine Serie",
        streakLongest: { "Längste Serie: \($0)" },
        streakKeep: "Schau heute vorbei, damit sie hält",
        milestone: { "\($0) Tage in Folge!" },
        milestoneSub: "Deine Serie läuft",
        gradeNew: { "Neue Note in \($0)" },
        reminderBy: { "Neue Erinnerung von \($0)" },
        reminderSoon: "Erinnerung",
        todoDue: "Fällig",
        todoOverdue: "Überfällig",
        today: "Heute",
        yesterday: "Gestern",
        todayAt: { "heute \($0)" },
        tomorrowAt: { "morgen \($0)" },
        yesterdayAt: { "gestern \($0)" },
        inMinutes: { "in \($0) Min." },
        inHours: { "in \($0) Std." },
        emptyTitle: "Alles ruhig",
        emptyText: "Neue Noten, Nachrichten und Erinnerungen tauchen hier auf.",
        noSubject: "(Kein Betreff)",
    )
}

extension BellStrings {
    static let it = BellStrings(
        title: "Notifiche",
        labelNew: { "Notifiche, \($0) nuove" },
        newCount: { "\($0) nuove" },
        clear: "Rimuovi",
        clearAll: "Rimuovi tutte",
        streakLost: { "La tua serie di \($0) giorni è finita" },
        streakLostSub: "Iniziane una nuova oggi",
        streakDays: { "\($0) giorni di fila" },
        streakOne: "1 giorno di fila",
        streakNone: "Oggi inizia la tua serie",
        streakLongest: { "Serie più lunga: \($0)" },
        streakKeep: "Passa oggi per tenerla viva",
        milestone: { "\($0) giorni di fila!" },
        milestoneSub: "La tua serie continua",
        gradeNew: { "Nuovo voto in \($0)" },
        reminderBy: { "Nuovo promemoria da \($0)" },
        reminderSoon: "Promemoria",
        todoDue: "Scade",
        todoOverdue: "Scaduto",
        today: "Oggi",
        yesterday: "Ieri",
        todayAt: { "oggi \($0)" },
        tomorrowAt: { "domani \($0)" },
        yesterdayAt: { "ieri \($0)" },
        inMinutes: { "tra \($0) min" },
        inHours: { "tra \($0) h" },
        emptyTitle: "Tutto tranquillo",
        emptyText: "Qui compaiono nuovi voti, messaggi e promemoria.",
        noSubject: "(Nessun oggetto)",
    )
}

extension BellStrings {
    static let en = BellStrings(
        title: "Notifications",
        labelNew: { "Notifications, \($0) new" },
        newCount: { "\($0) new" },
        clear: "Clear",
        clearAll: "Clear all",
        streakLost: { "Your \($0)-day streak ran out" },
        streakLostSub: "Start a new one today",
        streakDays: { "\($0) days in a row" },
        streakOne: "1 day in a row",
        streakNone: "Your streak starts today",
        streakLongest: { "Longest streak: \($0)" },
        streakKeep: "Drop by today to keep it going",
        milestone: { "\($0) days in a row!" },
        milestoneSub: "Your streak is on",
        gradeNew: { "New grade in \($0)" },
        reminderBy: { "New reminder from \($0)" },
        reminderSoon: "Reminder",
        todoDue: "Due",
        todoOverdue: "Overdue",
        today: "Today",
        yesterday: "Yesterday",
        todayAt: { "today \($0)" },
        tomorrowAt: { "tomorrow \($0)" },
        yesterdayAt: { "yesterday \($0)" },
        inMinutes: { "in \($0) min" },
        inHours: { "in \($0) h" },
        emptyTitle: "All quiet",
        emptyText: "New grades, messages and reminders show up here.",
        noSubject: "(No subject)",
    )
}
