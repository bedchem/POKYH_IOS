// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct NavStrings: Sendable {
    public let home: String
    public let timetable: String
    public let school: String
    public let grades: String
    public let mensa: String
    public let messages: String
    public let messagesUnread: @Sendable (Int) -> String
    public let profile: String
    public let settings: String
    public let arrangeHome: String
    public let switching: String
    public let accountMenu: String
    public let website: String
    public let actionTheme: String
    public let language: String
    public let student: String
    public let guardian: String
    public let logout: String
    public let logoutConfirm: String
    public let scanQr: String
    public let notifications: String
}


extension NavStrings {
    static let de = NavStrings(
        home: "Home",
        timetable: "Stundenplan",
        school: "Schule",
        grades: "Noten",
        mensa: "Mensa",
        messages: "Nachrichten",
        messagesUnread: { "Nachrichten, \($0) ungelesen" },
        profile: "Profil",
        settings: "Einstellungen",
        arrangeHome: "Startseite anordnen",
        switching: "Lädt…",
        accountMenu: "Konto-Menü",
        website: "Startseite",
        actionTheme: "Hell/Dunkel umschalten",
        language: "Sprache",
        student: "Schüler/in",
        guardian: "Erziehungsberechtigt",
        logout: "Abmelden",
        logoutConfirm: "Wirklich abmelden?",
        scanQr: "QR-Code scannen",
        notifications: "Benachrichtigungen",
    )
}

extension NavStrings {
    static let it = NavStrings(
        home: "Home",
        timetable: "Orario",
        school: "Scuola",
        grades: "Voti",
        mensa: "Mensa",
        messages: "Messaggi",
        messagesUnread: { "Messaggi, \($0) non letti" },
        profile: "Profilo",
        settings: "Impostazioni",
        arrangeHome: "Riordina la home",
        switching: "Caricamento…",
        accountMenu: "Menu dell’account",
        website: "Pagina iniziale",
        actionTheme: "Cambia chiaro/scuro",
        language: "Lingua",
        student: "Studente/ssa",
        guardian: "Genitore",
        logout: "Esci",
        logoutConfirm: "Vuoi davvero uscire?",
        scanQr: "Scansiona il codice QR",
        notifications: "Notifiche",
    )
}

extension NavStrings {
    static let en = NavStrings(
        home: "Home",
        timetable: "Timetable",
        school: "School",
        grades: "Grades",
        mensa: "Canteen",
        messages: "Messages",
        messagesUnread: { "Messages, \($0) unread" },
        profile: "Profile",
        settings: "Settings",
        arrangeHome: "Arrange home",
        switching: "Loading…",
        accountMenu: "Account menu",
        website: "Homepage",
        actionTheme: "Toggle light/dark",
        language: "Language",
        student: "Student",
        guardian: "Guardian",
        logout: "Log out",
        logoutConfirm: "Really log out?",
        scanQr: "Scan QR code",
        notifications: "Notifications",
    )
}
