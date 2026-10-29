// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct HomeStrings: Sendable {
    public let morning: String
    public let day: String
    public let evening: String
    public let welcome: String
    public let arrangeHint: String
    public let remove: @Sendable (String) -> String
    public let noWidgets: String
    public let addWidgets: String
    public let standard: String
    public let allWidgetsShown: String
    public let sectionShortcuts: String
    public let sectionShortcutsInfo: String
    public let sectionExam: String
    public let sectionExamInfo: String
    public let sectionToday: String
    public let sectionTodayInfo: String
    public let sectionMensa: String
    public let sectionMensaInfo: String
    public let sectionGrades: String
    public let sectionGradesInfo: String
    public let sectionNowNext: String
    public let sectionNowNextInfo: String
    public let sectionChanges: String
    public let sectionChangesInfo: String
    public let sectionAverage: String
    public let sectionAverageInfo: String
    public let sectionTodos: String
    public let sectionTodosInfo: String
    public let sectionReminders: String
    public let sectionRemindersInfo: String
    public let absences: String
    public let todos: String
    public let reminders: String
    public let absencesNote: @Sendable (String, String) -> String
    public let absencesHours: @Sendable (String) -> String
    public let todosNote: @Sendable (Int) -> String
    public let remindersNote: @Sendable (Int) -> String
    public let exam: String
    public let examOffline: String
    public let noExam: String
    public let today: String
    public let tomorrow: String
    public let inDays: @Sendable (Int) -> String
    public let todayOffline: String
    public let noLessonsToday: String
    public let event: String
    public let noMenu: String
    public let noMenuDay: String
    public let moreDishes: @Sendable (Int) -> String
    public let thisWeek: String
    public let nextWeek: String
    public let todayShort: @Sendable (String) -> String
    public let noGrades: String
    public let gradesOffline: String
    public let grade: String
    public let all: String
    public let gradeAvg: String
    public let subjects: @Sendable (Int) -> String
    public let offlineWidget: String
    public let dayOver: String
    public let now: String
    public let upNext: String
    public let afterThat: String
    public let left: @Sendable (String) -> String
    public let inTime: @Sendable (String, String) -> String
    public let minutes: @Sendable (Int) -> String
    public let hours: @Sendable (Int) -> String
    public let hoursMinutes: @Sendable (Int, Int) -> String
    public let lesson: String
    public let noChanges: String
    public let cancelled: String
    public let substitution: String
    public let roomChange: String
    public let additional: String
    public let changed: String
    public let room: @Sendable (String) -> String
    public let overall: String
    public let fromGrades: @Sendable (Int) -> String
    public let weakest: String
    public let allDone: String
    public let noReminders: String
    public let waitingOne: String
    public let waitingMany: @Sendable (Int) -> String
    public let loadFailed: String
    public let writeMessage: String
    public let reportAbsence: String
    public let offlineLine: String
    public let noMessages: String
    public let mensaToday: String
    public let mensaNext: String
    public let noRatingYet: String
    public let sectionMessages: String
    public let sectionMessagesInfo: String
    public let vegan: String
    public let vegetarian: String
    public let moreInTimetable: @Sendable (Int) -> String
    public let untisTitle: String
    public let untisText: String
}


extension HomeStrings {
    static let de = HomeStrings(
        morning: "Guten Morgen",
        day: "Hallo",
        evening: "Guten Abend",
        welcome: "Willkommen",
        arrangeHint: "Halten zum Verschieben · ✕ zum Entfernen",
        remove: { "\($0) entfernen" },
        noWidgets: "Keine Widgets auf der Startseite – tippe auf den Stift, um welche hinzuzufügen",
        addWidgets: "Widgets hinzufügen",
        standard: "Standard",
        allWidgetsShown: "Alle Widgets sind auf deiner Startseite",
        sectionShortcuts: "Schnellzugriff",
        sectionShortcutsInfo: "Noten, Abwesenheiten, To-dos und Erinnerungen",
        sectionExam: "Nächste Prüfung",
        sectionExamInfo: "Die nächste Prüfung mit Datum und Uhrzeit",
        sectionToday: "Heute",
        sectionTodayInfo: "Alle Stunden von heute",
        sectionMensa: "Mensa",
        sectionMensaInfo: "Der Speiseplan der Woche",
        sectionGrades: "Kürzlich hinzugefügt",
        sectionGradesInfo: "Die drei neuesten Noten",
        sectionNowNext: "Jetzt & gleich",
        sectionNowNextInfo: "Laufende und nächste Stunde mit Countdown",
        sectionChanges: "Vertretungen & Entfälle",
        sectionChangesInfo: "Änderungen im Stundenplan für heute und morgen",
        sectionAverage: "Notenschnitt",
        sectionAverageInfo: "Dein Gesamtschnitt und das schwächste Fach",
        sectionTodos: "Offene To-dos",
        sectionTodosInfo: "Deine nächsten offenen Aufgaben",
        sectionReminders: "Anstehende Erinnerungen",
        sectionRemindersInfo: "Die nächsten Termine deiner Klasse",
        absences: "Abwesenheiten",
        todos: "To-dos",
        reminders: "Erinnerungen",
        absencesNote: { rate, hours in "\(rate) % · \(hours) Std." },
        absencesHours: { "\($0) Std. gefehlt" },
        todosNote: { "\($0) offen" },
        remindersNote: { "\($0) anstehend" },
        exam: "Prüfung",
        examOffline: "Offline – nicht bekannt",
        noExam: "Keine Prüfung in den nächsten zwei Wochen",
        today: "Heute",
        tomorrow: "Morgen",
        inDays: { "in \($0) Tagen" },
        todayOffline: "Offline – für heute ist kein Stundenplan gespeichert",
        noLessonsToday: "Heute kein Unterricht",
        event: "Veranstaltung",
        noMenu: "Kein Speiseplan verfügbar",
        noMenuDay: "Kein Menü",
        moreDishes: { "+\($0) weitere" },
        thisWeek: "Diese Woche",
        nextWeek: "Nächste Woche",
        todayShort: { "Heute · \($0)" },
        noGrades: "Noch keine Noten in diesem Schuljahr",
        gradesOffline: "Offline – Noten sind auf diesem Gerät nicht gespeichert",
        grade: "Note",
        all: "Alle",
        gradeAvg: "Notenschnitt",
        subjects: { ($0 == 1) ? "1 Fach" : "\($0) Fächer" },
        offlineWidget: "Offline – noch nicht auf diesem Gerät gespeichert",
        dayOver: "Unterricht für heute vorbei",
        now: "Jetzt",
        upNext: "Als Nächstes",
        afterThat: "Danach",
        left: { "noch \($0)" },
        inTime: { d, time in "in \(d) · \(time)" },
        minutes: { "\($0) Min" },
        hours: { "\($0) Std" },
        hoursMinutes: { h, m in "\(h) Std \(m) Min" },
        lesson: "Stunde",
        noChanges: "Keine Änderungen für heute und morgen",
        cancelled: "Entfall",
        substitution: "Vertretung",
        roomChange: "Raumänderung",
        additional: "Zusätzlich",
        changed: "Geändert",
        room: { "Raum \($0)" },
        overall: "Gesamtschnitt",
        fromGrades: { "aus \($0) Noten" },
        weakest: "Schwächstes Fach",
        allDone: "Alles erledigt",
        noReminders: "Keine anstehenden Erinnerungen",
        waitingOne: "1 wartet auf Internet",
        waitingMany: { "\($0) warten auf Internet" },
        loadFailed: "Konnte nicht geladen werden",
        writeMessage: "Nachricht schreiben",
        reportAbsence: "Abwesenheit melden",
        offlineLine: "Offline: angezeigt wird der letzte Stand.",
        noMessages: "Keine Nachrichten",
        mensaToday: "Heute in der Mensa",
        mensaNext: "Als Nächstes in der Mensa",
        noRatingYet: "Noch keine Bewertung",
        sectionMessages: "Nachrichten",
        sectionMessagesInfo: "Die neuesten Nachrichten aus WebUntis",
        vegan: "Vegan",
        vegetarian: "Vegetarisch",
        moreInTimetable: { "+\($0) weitere im Stundenplan" },
        untisTitle: "Schulaccount erforderlich",
        untisText: "Diese Funktion ist nur mit einem WebUntis-Schulaccount verfügbar. Melde dich mit deinem Schulaccount an, um Stundenplan, Noten und mehr zu sehen.",
    )
}

extension HomeStrings {
    static let it = HomeStrings(
        morning: "Buongiorno",
        day: "Ciao",
        evening: "Buonasera",
        welcome: "Benvenuto",
        arrangeHint: "Tieni premuto per spostare · ✕ per rimuovere",
        remove: { "Rimuovi \($0)" },
        noWidgets: "Nessun widget nella home – tocca la matita per aggiungerne",
        addWidgets: "Aggiungi widget",
        standard: "Predefinito",
        allWidgetsShown: "Tutti i widget sono nella tua home",
        sectionShortcuts: "Accesso rapido",
        sectionShortcutsInfo: "Voti, assenze, to-do e promemoria",
        sectionExam: "Prossima verifica",
        sectionExamInfo: "La prossima verifica con data e ora",
        sectionToday: "Oggi",
        sectionTodayInfo: "Tutte le ore di oggi",
        sectionMensa: "Mensa",
        sectionMensaInfo: "Il menù della settimana",
        sectionGrades: "Aggiunti di recente",
        sectionGradesInfo: "I tre voti più recenti",
        sectionNowNext: "Ora e dopo",
        sectionNowNextInfo: "L’ora in corso e la prossima, con il conto alla rovescia",
        sectionChanges: "Supplenze e ore saltate",
        sectionChangesInfo: "Modifiche all’orario di oggi e domani",
        sectionAverage: "Media dei voti",
        sectionAverageInfo: "La tua media complessiva e la materia più debole",
        sectionTodos: "To-do aperti",
        sectionTodosInfo: "I tuoi prossimi compiti aperti",
        sectionReminders: "Promemoria in arrivo",
        sectionRemindersInfo: "I prossimi appuntamenti della tua classe",
        absences: "Assenze",
        todos: "To-do",
        reminders: "Promemoria",
        absencesNote: { rate, hours in "\(rate) % · \(hours) h" },
        absencesHours: { "\($0) h di assenza" },
        todosNote: { "\($0) aperti" },
        remindersNote: { "\($0) in arrivo" },
        exam: "Verifica",
        examOffline: "Offline – non noto",
        noExam: "Nessuna verifica nelle prossime due settimane",
        today: "Oggi",
        tomorrow: "Domani",
        inDays: { "tra \($0) giorni" },
        todayOffline: "Offline – nessun orario salvato per oggi",
        noLessonsToday: "Oggi niente lezioni",
        event: "Evento",
        noMenu: "Nessun menù disponibile",
        noMenuDay: "Nessun menù",
        moreDishes: { "+\($0) altri" },
        thisWeek: "Questa settimana",
        nextWeek: "Prossima settimana",
        todayShort: { "Oggi · \($0)" },
        noGrades: "Ancora nessun voto quest’anno scolastico",
        gradesOffline: "Offline – i voti non sono salvati su questo dispositivo",
        grade: "Voto",
        all: "Tutti",
        gradeAvg: "Media dei voti",
        subjects: { ($0 == 1) ? "1 materia" : "\($0) materie" },
        offlineWidget: "Offline – non ancora salvato su questo dispositivo",
        dayOver: "Lezioni di oggi finite",
        now: "Ora",
        upNext: "Prossima",
        afterThat: "Dopo",
        left: { "ancora \($0)" },
        inTime: { d, time in "tra \(d) · \(time)" },
        minutes: { "\($0) min" },
        hours: { "\($0) h" },
        hoursMinutes: { h, m in "\(h) h \(m) min" },
        lesson: "Ora",
        noChanges: "Nessuna modifica per oggi e domani",
        cancelled: "Saltata",
        substitution: "Supplenza",
        roomChange: "Cambio aula",
        additional: "Aggiuntiva",
        changed: "Modificata",
        room: { "Aula \($0)" },
        overall: "Media complessiva",
        fromGrades: { "su \($0) voti" },
        weakest: "Materia più debole",
        allDone: "Tutto fatto",
        noReminders: "Nessun promemoria in arrivo",
        waitingOne: "1 in attesa di internet",
        waitingMany: { "\($0) in attesa di internet" },
        loadFailed: "Impossibile caricare",
        writeMessage: "Scrivi un messaggio",
        reportAbsence: "Segnala assenza",
        offlineLine: "Offline: viene mostrato l’ultimo stato.",
        noMessages: "Nessun messaggio",
        mensaToday: "Oggi in mensa",
        mensaNext: "Prossimamente in mensa",
        noRatingYet: "Ancora nessuna valutazione",
        sectionMessages: "Messaggi",
        sectionMessagesInfo: "Gli ultimi messaggi da WebUntis",
        vegan: "Vegano",
        vegetarian: "Vegetariano",
        moreInTimetable: { "+\($0) altre nell’orario" },
        untisTitle: "Account scolastico richiesto",
        untisText: "Questa funzione è disponibile solo con un account scolastico WebUntis. Accedi con il tuo account scolastico per vedere orario, voti e altro.",
    )
}

extension HomeStrings {
    static let en = HomeStrings(
        morning: "Good morning",
        day: "Hello",
        evening: "Good evening",
        welcome: "Welcome",
        arrangeHint: "Hold to move · ✕ to remove",
        remove: { "Remove \($0)" },
        noWidgets: "No widgets on Home – tap the pencil to add some",
        addWidgets: "Add widgets",
        standard: "Default",
        allWidgetsShown: "All widgets are on your Home",
        sectionShortcuts: "Shortcuts",
        sectionShortcutsInfo: "Grades, absences, to-dos and reminders",
        sectionExam: "Next exam",
        sectionExamInfo: "The next exam with its date and time",
        sectionToday: "Today",
        sectionTodayInfo: "All of today’s lessons",
        sectionMensa: "Canteen",
        sectionMensaInfo: "This week’s menu",
        sectionGrades: "Recently added",
        sectionGradesInfo: "The three newest grades",
        sectionNowNext: "Now & next",
        sectionNowNextInfo: "The current and next lesson with a countdown",
        sectionChanges: "Substitutions & cancellations",
        sectionChangesInfo: "Timetable changes for today and tomorrow",
        sectionAverage: "Grade average",
        sectionAverageInfo: "Your overall average and weakest subject",
        sectionTodos: "Open to-dos",
        sectionTodosInfo: "Your next open tasks",
        sectionReminders: "Upcoming reminders",
        sectionRemindersInfo: "Your class’s next dates",
        absences: "Absences",
        todos: "To-dos",
        reminders: "Reminders",
        absencesNote: { rate, hours in "\(rate) % · \(hours) h" },
        absencesHours: { "\($0) h missed" },
        todosNote: { "\($0) open" },
        remindersNote: { "\($0) upcoming" },
        exam: "Exam",
        examOffline: "Offline – unknown",
        noExam: "No exam in the next two weeks",
        today: "Today",
        tomorrow: "Tomorrow",
        inDays: { "in \($0) days" },
        todayOffline: "Offline – no timetable stored for today",
        noLessonsToday: "No lessons today",
        event: "Event",
        noMenu: "No menu available",
        noMenuDay: "No menu",
        moreDishes: { "+\($0) more" },
        thisWeek: "This week",
        nextWeek: "Next week",
        todayShort: { "Today · \($0)" },
        noGrades: "No grades yet this school year",
        gradesOffline: "Offline – grades aren’t stored on this device",
        grade: "Grade",
        all: "All",
        gradeAvg: "Grade average",
        subjects: { ($0 == 1) ? "1 subject" : "\($0) subjects" },
        offlineWidget: "Offline – not stored on this device yet",
        dayOver: "Lessons are over for today",
        now: "Now",
        upNext: "Up next",
        afterThat: "After that",
        left: { "\($0) left" },
        inTime: { d, time in "in \(d) · \(time)" },
        minutes: { "\($0) min" },
        hours: { "\($0) h" },
        hoursMinutes: { h, m in "\(h) h \(m) min" },
        lesson: "Lesson",
        noChanges: "No changes for today and tomorrow",
        cancelled: "Cancelled",
        substitution: "Substitution",
        roomChange: "Room change",
        additional: "Extra",
        changed: "Changed",
        room: { "Room \($0)" },
        overall: "Overall average",
        fromGrades: { "from \($0) grades" },
        weakest: "Weakest subject",
        allDone: "All done",
        noReminders: "No upcoming reminders",
        waitingOne: "1 waiting for internet",
        waitingMany: { "\($0) waiting for internet" },
        loadFailed: "Couldn’t be loaded",
        writeMessage: "Write a message",
        reportAbsence: "Report absence",
        offlineLine: "Offline: showing the last saved state.",
        noMessages: "No messages",
        mensaToday: "Today in the canteen",
        mensaNext: "Next in the canteen",
        noRatingYet: "No rating yet",
        sectionMessages: "Messages",
        sectionMessagesInfo: "The latest messages from WebUntis",
        vegan: "Vegan",
        vegetarian: "Vegetarian",
        moreInTimetable: { "+\($0) more in the timetable" },
        untisTitle: "School account required",
        untisText: "This feature is only available with a WebUntis school account. Log in with your school account to see your timetable, grades and more.",
    )
}
