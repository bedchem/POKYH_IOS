// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct TasksStrings: Sendable {
    public let todos: String
    public let todosEyebrow: @Sendable (Int, Int) -> String
    public let new: String
    public let todosEmpty: String
    public let todosEmptyText: String
    public let todosOffline: String
    public let addTask: String
    public let done: String
    public let open: String
    public let newTodo: String
    public let title: String
    public let dueDate: String
    public let add: String
    public let apply: String
    public let reminders: String
    public let remindersFeature: String
    public let upcoming: @Sendable (Int) -> String
    public let noClass: String
    public let noClassText: String
    public let remindersEmpty: String
    public let remindersOffline: String
    public let remindersEmptyText: String
    public let newReminder: String
    public let remindOn: String
    public let reminder: String
    public let reminderNotFound: String
    public let noClassFound: String
    public let by: @Sendable (String) -> String
    public let classreg: String
    public let classregEmpty: String
    public let classregEmptyText: String
    public let klasseNamed: @Sendable (String) -> String
    public let myClass: String
    public let newClassreg: String
    public let last3Months: String
    public let noClassreg3: String
    public let openAbsences: String
    public let noOpenAbsences: String
    public let more: @Sendable (Int) -> String
    public let services: String
    public let noServices: String
    public let exams: String
    public let noExamsThisWeek: String
    public let noExamsNextWeek: String
    public let examsPartly: String
    public let noExamsAhead: String
    public let homework: String
    public let noHomeworkThisWeek: String
    public let noHomeworkNextWeek: String
    public let noHomeworkAhead: String
    public let classList: String
    public let members: String
    public let all: String
    public let exam: String
    public let homeworkOne: String
    public let due: String
    public let joinCode: String
    public let joinCodeHint: String
    public let collapse: String
    public let expand: String
    public let username: String
    public let joined: String
    public let offlineNotStored: String
    public let titleField: String
    public let detailsField: String
    public let descriptionField: String
    public let overdue: String
    public let todayAt: @Sendable (String) -> String
    public let dateTime: @Sendable (String, String) -> String
    public let saveFailed: String
    public let dueTime: String
    public let markDone: String
    public let markOpen: String
    public let inDay: String
    public let inDays: @Sendable (Int) -> String
    public let inHours: @Sendable (Int) -> String
    public let soon: String
    public let deleteAsAdmin: String
    public let deleteItem: String
    public let dayLong: String
    public let dayShort: String
    public let totalEntries: String
    public let subjectsLabel: String
    public let lastEntry: String
    public let topCategory: String
    public let filterAll: String
    public let filter1m: String
    public let filter3m: String
    public let sortBy: String
    public let sortDateDesc: String
    public let sortDateAsc: String
    public let sortSubject: String
    public let sortCategory: String
    public let noCategory: String
    public let noEntriesRange: String
    public let editTodo: String
    public let editReminder: String
    public let edit: String
    public let saveChanges: String
}


extension TasksStrings {
    static let de = TasksStrings(
        todos: "To-dos",
        todosEyebrow: { o, t in "\(o) offen · \(t) gesamt" },
        new: "Neu",
        todosEmpty: "Keine To-dos",
        todosEmptyText: "Lege eine Aufgabe an, um sie hier zu sehen.",
        todosOffline: "Du bist offline. Neue Aufgaben werden gesendet, sobald du wieder Internet hast.",
        addTask: "Aufgabe anlegen",
        done: "Erledigt",
        open: "Offen",
        newTodo: "Neues To-do",
        title: "Titel",
        dueDate: "Fälligkeitsdatum",
        add: "Hinzufügen",
        apply: "Übernehmen",
        reminders: "Klassen-Erinnerungen",
        remindersFeature: "Erinnerungen",
        upcoming: { "\($0) anstehend" },
        noClass: "Keine Klasse",
        noClassText: "Du bist noch keiner Klasse beigetreten.",
        remindersEmpty: "Keine Erinnerungen",
        remindersOffline: "Du bist offline. Neue Erinnerungen werden gesendet, sobald du wieder Internet hast.",
        remindersEmptyText: "Lege eine Klassen-Erinnerung an, um sie hier zu sehen.",
        newReminder: "Neue Erinnerung",
        remindOn: "Erinnern am",
        reminder: "Erinnerung",
        reminderNotFound: "Erinnerung nicht gefunden.",
        noClassFound: "Keine Klasse gefunden.",
        by: { "von \($0)" },
        classreg: "Klassenbuch",
        classregEmpty: "Keine Einträge",
        classregEmptyText: "Im Klassenbuch sind für dieses Schuljahr keine Einträge vorhanden.",
        klasseNamed: { "Klasse \($0)" },
        myClass: "Meine Klasse",
        newClassreg: "Neue Klassenbuch-Einträge",
        last3Months: "Letzte 3 Monate",
        noClassreg3: "Keine Einträge in den letzten 3 Monaten",
        openAbsences: "Offene Abwesenheiten",
        noOpenAbsences: "Keine offenen Abwesenheiten",
        more: { "+\($0) weitere" },
        services: "Klassendienste",
        noServices: "Keine Klassendienste eingetragen",
        exams: "Prüfungen",
        noExamsThisWeek: "Keine Prüfungen diese Woche",
        noExamsNextWeek: "Keine Prüfungen nächste Woche",
        examsPartly: "Offline – Prüfungen nur teilweise bekannt",
        noExamsAhead: "Keine Prüfungen in Zukunft",
        homework: "Hausaufgaben",
        noHomeworkThisWeek: "Keine Hausaufgaben diese Woche",
        noHomeworkNextWeek: "Keine Hausaufgaben nächste Woche",
        noHomeworkAhead: "Keine Hausaufgaben in Zukunft",
        classList: "Die Klassenliste",
        members: "Mitglieder",
        all: "Alle",
        exam: "Prüfung",
        homeworkOne: "Hausaufgabe",
        due: "Fällig",
        joinCode: "Beitrittscode",
        joinCodeHint: "Zum Teilen mit Klassenkamerad:innen",
        collapse: "Einklappen",
        expand: "Aufklappen",
        username: "Benutzername",
        joined: "Beigetreten",
        offlineNotStored: "Offline – auf diesem Gerät nicht gespeichert",
        titleField: "Titel",
        detailsField: "Details",
        descriptionField: "Beschreibung",
        overdue: "Überfällig",
        todayAt: { "Heute, \($0)" },
        dateTime: { d, t in "\(d), \(t)" },
        saveFailed: "Speichern fehlgeschlagen.",
        dueTime: "Uhrzeit",
        markDone: "Als erledigt markieren",
        markOpen: "Als offen markieren",
        inDay: "in 1 Tag",
        inDays: { "in \($0) Tagen" },
        inHours: { "in \($0) Std." },
        soon: "Gleich",
        deleteAsAdmin: "Als Admin löschen",
        deleteItem: "Löschen",
        dayLong: "EEEE, d. MMMM",
        dayShort: "EEE, d. MMM",
        totalEntries: "Einträge gesamt",
        subjectsLabel: "Fächer",
        lastEntry: "Letzte Eintragung",
        topCategory: "Häufigste Kategorie",
        filterAll: "Alle",
        filter1m: "Letzter Monat",
        filter3m: "Letzte 3 Monate",
        sortBy: "Sortieren",
        sortDateDesc: "Datum ↓",
        sortDateAsc: "Datum ↑",
        sortSubject: "Fach",
        sortCategory: "Kategorie",
        noCategory: "Ohne Kategorie",
        noEntriesRange: "Keine Einträge im gewählten Zeitraum",
        editTodo: "To-do bearbeiten",
        editReminder: "Erinnerung bearbeiten",
        edit: "Bearbeiten",
        saveChanges: "Speichern",
    )
}

extension TasksStrings {
    static let it = TasksStrings(
        todos: "To-do",
        todosEyebrow: { o, t in "\(o) aperti · \(t) in totale" },
        new: "Nuovo",
        todosEmpty: "Nessun to-do",
        todosEmptyText: "Crea un compito per vederlo qui.",
        todosOffline: "Sei offline. I nuovi compiti verranno inviati appena avrai di nuovo Internet.",
        addTask: "Crea compito",
        done: "Fatto",
        open: "Aperto",
        newTodo: "Nuovo to-do",
        title: "Titolo",
        dueDate: "Scadenza",
        add: "Aggiungi",
        apply: "Applica",
        reminders: "Promemoria della classe",
        remindersFeature: "Promemoria",
        upcoming: { "\($0) in arrivo" },
        noClass: "Nessuna classe",
        noClassText: "Non sei ancora entrato in una classe.",
        remindersEmpty: "Nessun promemoria",
        remindersOffline: "Sei offline. I nuovi promemoria verranno inviati appena avrai di nuovo Internet.",
        remindersEmptyText: "Crea un promemoria della classe per vederlo qui.",
        newReminder: "Nuovo promemoria",
        remindOn: "Ricorda il",
        reminder: "Promemoria",
        reminderNotFound: "Promemoria non trovato.",
        noClassFound: "Nessuna classe trovata.",
        by: { "di \($0)" },
        classreg: "Registro di classe",
        classregEmpty: "Nessuna annotazione",
        classregEmptyText: "Nel registro non ci sono annotazioni per quest’anno scolastico.",
        klasseNamed: { "Classe \($0)" },
        myClass: "La mia classe",
        newClassreg: "Nuove annotazioni nel registro",
        last3Months: "Ultimi 3 mesi",
        noClassreg3: "Nessuna annotazione negli ultimi 3 mesi",
        openAbsences: "Assenze da giustificare",
        noOpenAbsences: "Nessuna assenza da giustificare",
        more: { "+\($0) altri" },
        services: "Servizi di classe",
        noServices: "Nessun servizio di classe registrato",
        exams: "Verifiche",
        noExamsThisWeek: "Nessuna verifica questa settimana",
        noExamsNextWeek: "Nessuna verifica la prossima settimana",
        examsPartly: "Offline – verifiche note solo in parte",
        noExamsAhead: "Nessuna verifica in programma",
        homework: "Compiti",
        noHomeworkThisWeek: "Nessun compito questa settimana",
        noHomeworkNextWeek: "Nessun compito la prossima settimana",
        noHomeworkAhead: "Nessun compito in programma",
        classList: "L’elenco della classe",
        members: "Membri",
        all: "Tutti",
        exam: "Verifica",
        homeworkOne: "Compito",
        due: "In scadenza",
        joinCode: "Codice di accesso",
        joinCodeHint: "Da condividere con i compagni di classe",
        collapse: "Comprimi",
        expand: "Espandi",
        username: "Nome utente",
        joined: "Entrato il",
        offlineNotStored: "Offline – non salvato su questo dispositivo",
        titleField: "Titolo",
        detailsField: "Dettagli",
        descriptionField: "Descrizione",
        overdue: "Scaduto",
        todayAt: { "Oggi, \($0)" },
        dateTime: { d, t in "\(d), \(t)" },
        saveFailed: "Salvataggio non riuscito.",
        dueTime: "Ora",
        markDone: "Segna come fatto",
        markOpen: "Segna come da fare",
        inDay: "tra 1 giorno",
        inDays: { "tra \($0) giorni" },
        inHours: { "tra \($0) h" },
        soon: "A breve",
        deleteAsAdmin: "Elimina come admin",
        deleteItem: "Elimina",
        dayLong: "EEEE d MMMM",
        dayShort: "EEE d MMM",
        totalEntries: "Annotazioni totali",
        subjectsLabel: "Materie",
        lastEntry: "Ultima annotazione",
        topCategory: "Categoria più frequente",
        filterAll: "Tutte",
        filter1m: "Ultimo mese",
        filter3m: "Ultimi 3 mesi",
        sortBy: "Ordina",
        sortDateDesc: "Data ↓",
        sortDateAsc: "Data ↑",
        sortSubject: "Materia",
        sortCategory: "Categoria",
        noCategory: "Senza categoria",
        noEntriesRange: "Nessuna annotazione nel periodo scelto",
        editTodo: "Modifica to-do",
        editReminder: "Modifica promemoria",
        edit: "Modifica",
        saveChanges: "Salva",
    )
}

extension TasksStrings {
    static let en = TasksStrings(
        todos: "To-dos",
        todosEyebrow: { o, t in "\(o) open · \(t) total" },
        new: "New",
        todosEmpty: "No to-dos",
        todosEmptyText: "Add a task to see it here.",
        todosOffline: "You’re offline. New tasks are sent as soon as you’re back online.",
        addTask: "Add task",
        done: "Done",
        open: "Open",
        newTodo: "New to-do",
        title: "Title",
        dueDate: "Due date",
        add: "Add",
        apply: "Apply",
        reminders: "Class reminders",
        remindersFeature: "Reminders",
        upcoming: { "\($0) upcoming" },
        noClass: "No class",
        noClassText: "You haven’t joined a class yet.",
        remindersEmpty: "No reminders",
        remindersOffline: "You’re offline. New reminders are sent as soon as you’re back online.",
        remindersEmptyText: "Add a class reminder to see it here.",
        newReminder: "New reminder",
        remindOn: "Remind on",
        reminder: "Reminder",
        reminderNotFound: "Reminder not found.",
        noClassFound: "No class found.",
        by: { "by \($0)" },
        classreg: "Class register",
        classregEmpty: "No entries",
        classregEmptyText: "There are no entries in the class register for this school year.",
        klasseNamed: { "Class \($0)" },
        myClass: "My class",
        newClassreg: "New class register entries",
        last3Months: "Last 3 months",
        noClassreg3: "No entries in the last 3 months",
        openAbsences: "Open absences",
        noOpenAbsences: "No open absences",
        more: { "+\($0) more" },
        services: "Class duties",
        noServices: "No class duties entered",
        exams: "Exams",
        noExamsThisWeek: "No exams this week",
        noExamsNextWeek: "No exams next week",
        examsPartly: "Offline – exams only partly known",
        noExamsAhead: "No upcoming exams",
        homework: "Homework",
        noHomeworkThisWeek: "No homework this week",
        noHomeworkNextWeek: "No homework next week",
        noHomeworkAhead: "No upcoming homework",
        classList: "The class list",
        members: "Members",
        all: "All",
        exam: "Exam",
        homeworkOne: "Homework",
        due: "Due",
        joinCode: "Join code",
        joinCodeHint: "To share with your classmates",
        collapse: "Collapse",
        expand: "Expand",
        username: "Username",
        joined: "Joined",
        offlineNotStored: "Offline – not stored on this device",
        titleField: "Title",
        detailsField: "Details",
        descriptionField: "Description",
        overdue: "Overdue",
        todayAt: { "Today, \($0)" },
        dateTime: { d, t in "\(d), \(t)" },
        saveFailed: "Couldn’t save.",
        dueTime: "Time",
        markDone: "Mark as done",
        markOpen: "Mark as open",
        inDay: "in 1 day",
        inDays: { "in \($0) days" },
        inHours: { "in \($0) h" },
        soon: "Soon",
        deleteAsAdmin: "Delete as admin",
        deleteItem: "Delete",
        dayLong: "EEEE, d MMMM",
        dayShort: "EEE, d MMM",
        totalEntries: "Total entries",
        subjectsLabel: "Subjects",
        lastEntry: "Latest entry",
        topCategory: "Most common category",
        filterAll: "All",
        filter1m: "Last month",
        filter3m: "Last 3 months",
        sortBy: "Sort",
        sortDateDesc: "Date ↓",
        sortDateAsc: "Date ↑",
        sortSubject: "Subject",
        sortCategory: "Category",
        noCategory: "No category",
        noEntriesRange: "No entries in the selected period",
        editTodo: "Edit to-do",
        editReminder: "Edit reminder",
        edit: "Edit",
        saveChanges: "Save",
    )
}
