// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct SchoolStrings: Sendable {
    public let gradesInfo: String
    public let absences: String
    public let absencesInfo: String
    public let klasse: String
    public let klasseInfo: String
    public let classreg: String
    public let classregInfo: String
    public let reminders: String
    public let remindersInfo: String
    public let todos: String
    public let todosInfo: String
    public let unread: @Sendable (Int) -> String
    public let messagesInfo: String
}


extension SchoolStrings {
    static let de = SchoolStrings(
        gradesInfo: "Alle Fächer & Bewertungen",
        absences: "Abwesenheiten",
        absencesInfo: "Fehlstunden & Entschuldigungen",
        klasse: "Klasse",
        klasseInfo: "Übersicht, Prüfungen & Mitglieder",
        classreg: "Klassenbuch",
        classregInfo: "Einträge & Vermerke",
        reminders: "Erinnerungen",
        remindersInfo: "Hausaufgaben & Termine der Klasse",
        todos: "Eigene To-dos",
        todosInfo: "Deine persönliche Aufgabenliste",
        unread: { "\($0) ungelesen" },
        messagesInfo: "Posteingang der Schule",
    )
}

extension SchoolStrings {
    static let it = SchoolStrings(
        gradesInfo: "Tutte le materie e i voti",
        absences: "Assenze",
        absencesInfo: "Ore di assenza e giustificazioni",
        klasse: "Classe",
        klasseInfo: "Panoramica, verifiche e membri",
        classreg: "Registro di classe",
        classregInfo: "Annotazioni e note",
        reminders: "Promemoria",
        remindersInfo: "Compiti e appuntamenti della classe",
        todos: "I miei to-do",
        todosInfo: "La tua lista personale di compiti",
        unread: { "\($0) non letti" },
        messagesInfo: "Posta della scuola",
    )
}

extension SchoolStrings {
    static let en = SchoolStrings(
        gradesInfo: "All subjects & marks",
        absences: "Absences",
        absencesInfo: "Missed lessons & excuses",
        klasse: "Class",
        klasseInfo: "Overview, exams & members",
        classreg: "Class register",
        classregInfo: "Entries & notes",
        reminders: "Reminders",
        remindersInfo: "Homework & class dates",
        todos: "My to-dos",
        todosInfo: "Your personal task list",
        unread: { "\($0) unread" },
        messagesInfo: "The school’s inbox",
    )
}
