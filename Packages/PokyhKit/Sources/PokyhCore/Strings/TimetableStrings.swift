// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct TimetableStrings: Sendable {
    public let export: String
    public let exportWeek: String
    public let exportExams: String
    public let prevWeek: String
    public let nextWeek: String
    public let toToday: String
    public let thisWeek: String
    public let cw: @Sendable (Int) -> String
    public let modeWeek: String
    public let modeDay: String
    public let unknownTitle: String
    public let offlineUnknown: String
    public let noLessons: String
    public let insteadOf: @Sendable (String) -> String
    public let cancelled: String
    public let exam: String
    public let substitution: String
    public let event: String
    public let holiday: String
    public let weekend: String
    public let free: String
    public let allCancelled: String
    public let allReplaced: String
    public let allDay: String
    public let icsWeekFile: String
    public let icsWeekName: String
    public let icsExamsFile: String
    public let icsExamsName: String
    public let icsTeacher: String
    public let lesson: String
    public let note: String
    public let lessonText: String
    public let substitutionText: String
    public let examContent: String
    public let homework: String
    public let absent: String
    public let period: String
    public let reason: String
    public let teacher: String
    public let room: String
    public let classes: String
    public let group: String
    public let instead: String
    public let insteadShort: String
    public let wholeDay: String
    public let markPreExcused: String
    public let markExcused: String
    public let markAbsent: String
    public let markPreExcusedShort: String
    public let markExcusedShort: String
    public let markAbsentShort: String
    public let info: String
    public let hoursUnit: String
    public let cancellations: String
    public let examsLabel: String
    public let substitutions: String
    public let holidayNames: [String: String]
    public let markSent: String
    public let sentTo: @Sendable (String, String) -> String
    public let otherTimetables: String
    public let myTimetable: String
    public let kindClass: String
    public let kindTeacher: String
    public let kindRoom: String
    public let otherSearch: String
    public let otherFailed: String
    public let otherNone: String
}


extension TimetableStrings {
    static let de = TimetableStrings(
        export: "Exportieren",
        exportWeek: "Diese Woche exportieren",
        exportExams: "Prüfungen exportieren",
        prevWeek: "Vorherige Woche",
        nextWeek: "Nächste Woche",
        toToday: "Zu heute",
        thisWeek: "Diese Woche",
        cw: { "KW \($0)" },
        modeWeek: "Woche",
        modeDay: "Tag",
        unknownTitle: "Stundenplan unbekannt",
        offlineUnknown: "Du bist offline und für diese Woche ist kein Stundenplan gespeichert. Ob Unterricht ist, lässt sich erst sagen, wenn du wieder Internet hast.",
        noLessons: "Kein Unterricht",
        insteadOf: { "statt \($0)" },
        cancelled: "Entfall",
        exam: "Prüfung",
        substitution: "Vertretung",
        event: "Veranstaltung",
        holiday: "Ferien",
        weekend: "Wochenende",
        free: "Frei",
        allCancelled: "Alle Stunden ausgefallen",
        allReplaced: "Tag durchgehend ersetzt",
        allDay: "Ganztägig",
        icsWeekFile: "pokyh_stundenplan.ics",
        icsWeekName: "POKYH Stundenplan",
        icsExamsFile: "pokyh_pruefungen.ics",
        icsExamsName: "POKYH Prüfungen",
        icsTeacher: "Lehrer",
        lesson: "Stunde",
        note: "Notiz",
        lessonText: "Stundentext",
        substitutionText: "Vertretungstext",
        examContent: "Prüfungsinhalt",
        homework: "Hausaufgaben",
        absent: "Abwesend",
        period: "Zeitraum",
        reason: "Grund",
        teacher: "Lehrkraft",
        room: "Raum",
        classes: "Klassen",
        group: "Gruppe",
        instead: "Stattdessen",
        insteadShort: "Statt",
        wholeDay: "Ganzer Tag",
        markPreExcused: "Vorentschuldigung",
        markExcused: "Entschuldigt",
        markAbsent: "Unentschuldigt",
        markPreExcusedShort: "Vorentsch.",
        markExcusedShort: "Entsch.",
        markAbsentShort: "Unentsch.",
        info: "Info",
        hoursUnit: "Std",
        cancellations: "Entfälle",
        examsLabel: "Prüfungen",
        substitutions: "Vertretungen",
        holidayNames: ["christmas": "Weihnachtsferien", "easter": "Osterferien", "autumn": "Herbstferien", "carnival": "Faschingsferien", "summer": "Sommerferien", "newYear": "Neujahr", "epiphany": "Heilige Drei Könige", "easterMonday": "Ostermontag", "liberation": "Tag der Befreiung", "labour": "Tag der Arbeit", "ascension": "Christi Himmelfahrt", "pentecost": "Pfingstmontag", "republic": "Tag der Republik", "corpusChristi": "Fronleichnam", "assumption": "Mariä Himmelfahrt", "allSaints": "Allerheiligen", "immaculate": "Mariä Empfängnis", "christmasDay": "Weihnachten", "stStephen": "Stefanstag", "dayOff": "Schulfrei", "break": "Ferien"],
        markSent: "Nachricht an Klassenlehrer gesendet",
        sentTo: { n, d in "An \(n) · \(d)" },
        otherTimetables: "Andere Stundenpläne",
        myTimetable: "Mein Stundenplan",
        kindClass: "Klassen",
        kindTeacher: "Lehrkräfte",
        kindRoom: "Räume",
        otherSearch: "Suchen …",
        otherFailed: "Konnte gerade nicht geladen werden.",
        otherNone: "Deine Schule zeigt hier nichts an.",
    )
}

extension TimetableStrings {
    static let it = TimetableStrings(
        export: "Esporta",
        exportWeek: "Esporta questa settimana",
        exportExams: "Esporta verifiche",
        prevWeek: "Settimana precedente",
        nextWeek: "Settimana successiva",
        toToday: "Vai a oggi",
        thisWeek: "Questa settimana",
        cw: { "Sett. \($0)" },
        modeWeek: "Settimana",
        modeDay: "Giorno",
        unknownTitle: "Orario sconosciuto",
        offlineUnknown: "Sei offline e per questa settimana non è salvato nessun orario. Se ci sono lezioni si potrà sapere solo quando avrai di nuovo Internet.",
        noLessons: "Nessuna lezione",
        insteadOf: { "al posto di \($0)" },
        cancelled: "Annullata",
        exam: "Verifica",
        substitution: "Supplenza",
        event: "Evento",
        holiday: "Vacanze",
        weekend: "Fine settimana",
        free: "Libero",
        allCancelled: "Tutte le ore annullate",
        allReplaced: "Giornata interamente sostituita",
        allDay: "Tutto il giorno",
        icsWeekFile: "pokyh_orario.ics",
        icsWeekName: "POKYH Orario",
        icsExamsFile: "pokyh_verifiche.ics",
        icsExamsName: "POKYH Verifiche",
        icsTeacher: "Docente",
        lesson: "Ora",
        note: "Nota",
        lessonText: "Testo della lezione",
        substitutionText: "Testo della supplenza",
        examContent: "Contenuto della verifica",
        homework: "Compiti",
        absent: "Assente",
        period: "Periodo",
        reason: "Motivo",
        teacher: "Docente",
        room: "Aula",
        classes: "Classi",
        group: "Gruppo",
        instead: "Al suo posto",
        insteadShort: "Al posto di",
        wholeDay: "Tutto il giorno",
        markPreExcused: "Giustificazione anticipata",
        markExcused: "Giustificata",
        markAbsent: "Non giustificata",
        markPreExcusedShort: "Giust. ant.",
        markExcusedShort: "Giust.",
        markAbsentShort: "Non giust.",
        info: "Info",
        hoursUnit: "ore",
        cancellations: "Annullate",
        examsLabel: "Verifiche",
        substitutions: "Supplenze",
        holidayNames: ["christmas": "Vacanze di Natale", "easter": "Vacanze di Pasqua", "autumn": "Vacanze autunnali", "carnival": "Vacanze di Carnevale", "summer": "Vacanze estive", "newYear": "Capodanno", "epiphany": "Epifania", "easterMonday": "Lunedì dell’Angelo", "liberation": "Festa della Liberazione", "labour": "Festa dei lavoratori", "ascension": "Ascensione", "pentecost": "Lunedì di Pentecoste", "republic": "Festa della Repubblica", "corpusChristi": "Corpus Domini", "assumption": "Ferragosto", "allSaints": "Ognissanti", "immaculate": "Immacolata", "christmasDay": "Natale", "stStephen": "Santo Stefano", "dayOff": "Giorno libero", "break": "Vacanze"],
        markSent: "Messaggio inviato ai coordinatori",
        sentTo: { n, d in "A \(n) · \(d)" },
        otherTimetables: "Altri orari",
        myTimetable: "Il mio orario",
        kindClass: "Classi",
        kindTeacher: "Docenti",
        kindRoom: "Aule",
        otherSearch: "Cerca …",
        otherFailed: "Impossibile caricare ora.",
        otherNone: "La tua scuola non mostra nulla qui.",
    )
}

extension TimetableStrings {
    static let en = TimetableStrings(
        export: "Export",
        exportWeek: "Export this week",
        exportExams: "Export exams",
        prevWeek: "Previous week",
        nextWeek: "Next week",
        toToday: "Go to today",
        thisWeek: "This week",
        cw: { "Wk \($0)" },
        modeWeek: "Week",
        modeDay: "Day",
        unknownTitle: "Timetable unknown",
        offlineUnknown: "You’re offline and no timetable is saved for this week. Whether there are classes can only be known once you’re back online.",
        noLessons: "No classes",
        insteadOf: { "instead of \($0)" },
        cancelled: "Cancelled",
        exam: "Exam",
        substitution: "Substitute",
        event: "Event",
        holiday: "Holidays",
        weekend: "Weekend",
        free: "Free",
        allCancelled: "All lessons cancelled",
        allReplaced: "Whole day replaced",
        allDay: "All day",
        icsWeekFile: "pokyh_timetable.ics",
        icsWeekName: "POKYH Timetable",
        icsExamsFile: "pokyh_exams.ics",
        icsExamsName: "POKYH Exams",
        icsTeacher: "Teacher",
        lesson: "Lesson",
        note: "Note",
        lessonText: "Lesson text",
        substitutionText: "Substitution text",
        examContent: "Exam content",
        homework: "Homework",
        absent: "Absent",
        period: "Period",
        reason: "Reason",
        teacher: "Teacher",
        room: "Room",
        classes: "Classes",
        group: "Group",
        instead: "Instead",
        insteadShort: "Instead of",
        wholeDay: "All day",
        markPreExcused: "Excused in advance",
        markExcused: "Excused",
        markAbsent: "Unexcused",
        markPreExcusedShort: "Pre-exc.",
        markExcusedShort: "Exc.",
        markAbsentShort: "Unexc.",
        info: "Info",
        hoursUnit: "h",
        cancellations: "Cancelled",
        examsLabel: "Exams",
        substitutions: "Substitutions",
        holidayNames: ["christmas": "Christmas holidays", "easter": "Easter holidays", "autumn": "Autumn holidays", "carnival": "Carnival holidays", "summer": "Summer holidays", "newYear": "New Year’s Day", "epiphany": "Epiphany", "easterMonday": "Easter Monday", "liberation": "Liberation Day", "labour": "Labour Day", "ascension": "Ascension Day", "pentecost": "Whit Monday", "republic": "Republic Day", "corpusChristi": "Corpus Christi", "assumption": "Assumption Day", "allSaints": "All Saints’ Day", "immaculate": "Immaculate Conception", "christmasDay": "Christmas Day", "stStephen": "St Stephen’s Day", "dayOff": "Day off", "break": "Holidays"],
        markSent: "Message sent to class teachers",
        sentTo: { n, d in "To \(n) · \(d)" },
        otherTimetables: "Other timetables",
        myTimetable: "My timetable",
        kindClass: "Classes",
        kindTeacher: "Teachers",
        kindRoom: "Rooms",
        otherSearch: "Search …",
        otherFailed: "Could not be loaded right now.",
        otherNone: "Your school shows nothing here.",
    )
}
