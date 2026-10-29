// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct ProfileStrings: Sendable {
    public let title: String
    public let settings: String
    public let settingsHint: String
    public let account: String
    public let username: String
    public let klasse: String
    public let school: String
    public let schoolName: String
    public let pokyhAccount: String
    public let accounts: String
    public let addAccount: String
    public let parent: String
    public let student: String
    public let staff: String
    public let openPicture: String
    public let removeAccountTitle: String
    public let removeAccountBody: @Sendable (String) -> String
    public let removeAccountConfirm: String
    public let renameTitle: String
    public let renameBody: @Sendable (String) -> String
    public let nickname: String
    public let remove: String
    public let switchErrorTitle: String
    public let noSavedPassword: @Sendable (String) -> String
    public let refreshFailed: String
    public let standard: String
    public let needsPassword: String
    public let activeAccount: String
    public let setDefault: String
    public let unsetDefault: String
    public let refreshAccount: String
    public let rename: String
    public let signOut: String
    public let removeAccount: String
    public let statusUnknown: String
    public let statusOk: String
    public let statusNotStudent: String
    public let statusNoClass: String
    public let statusFailed: @Sendable (String) -> String
    public let statusOffline: String
    public let connectionTitle: String
    public let heroOk: String
    public let heroNotStudent: String
    public let heroNoClass: String
    public let heroFailed: @Sendable (String) -> String
    public let heroUnknown: String
    public let heroOffline: String
    public let yourAccount: String
    public let name: String
    public let role: String
    public let diagnosis: String
    public let checkAgain: String
    public let technicalDetails: String
    public let forSupport: String
    public let share: String
    public let detailsNote: String
    public let activity: String
    public let activityLead: String
    public let daysOnline: String
    public let logins: String
    public let currentStreak: String
    public let longestStreak: String
    public let activityFailed: String
    public let moreStats: String
    public let tapDay: String
    public let loginCount: @Sendable (Int) -> String
    public let online: String
    public let notOnline: String
    public let inPokyh: @Sendable (String) -> String
    public let statsTitle: String
    public let statsOnlyYou: String
    public let statsNeedAccount: String
    public let onlyWithConsent: String
    public let statsOffNotice: String
    public let currentStreakIs: @Sendable (String) -> String
    public let longestStreakIs: @Sendable (String) -> String
    public let usageTime: String
    public let visits: @Sendable (Int) -> String
    public let perDay: String
    public let screensOpened: @Sendable (Int) -> String
    public let whenOnline: String
    public let whenOnlineLead: String
    public let weekdays: String
    public let weekdaysLead: String
    public let devices: String
    public let devicesLead: String
    public let phone: String
    public let computer: String
    public let app: String
    public let browser: String
    public let topPages: String
    public let topPagesLead: String
    public let created: String
    public let todosDone: String
    public let todosOpen: String
    public let reminders: String
    public let comments: String
    public let ratings: String
    public let memberSince: String
    public let statsFooter: String
    public let pageNames: [String: String]
    public let changePassword: String
    public let passwordChanged: String
    public let passwordChangedText: String
    public let passwordLead: String
    public let currentPassword: String
    public let newPassword: String
    public let repeatPassword: String
    public let errBothPasswords: String
    public let errPasswordsDiffer: String
    public let errSamePassword: String
    public let errPasswordFailed: String
    public let views: @Sendable (Int) -> String
    public let studentId: String
    public let userId: String
    public let classIdLabel: String
    public let copy: String
    public let copied: String
    public let statsOffTitle: String
    public let statsOffText: String
}


extension ProfileStrings {
    static let de = ProfileStrings(
        title: "Profil",
        settings: "Einstellungen",
        settingsHint: "Darstellung, Sprache, Speicher und mehr",
        account: "Konto",
        username: "Benutzername",
        klasse: "Klasse",
        school: "Schule",
        schoolName: "LBS Brixen",
        pokyhAccount: "POKYH-Konto",
        accounts: "Konten",
        addAccount: "Konto hinzufügen",
        parent: "Erziehungsberechtigt",
        student: "Schüler/in",
        staff: "Lehrkraft/Verwaltung",
        openPicture: "Profilbild öffnen",
        removeAccountTitle: "Konto entfernen?",
        removeAccountBody: { "Die gespeicherten Anmeldedaten von \($0) werden vom Gerät gelöscht." },
        removeAccountConfirm: "Konto entfernen",
        renameTitle: "Konto umbenennen",
        renameBody: { "Vergib einen eigenen Namen für \($0) (nur lokal sichtbar)." },
        nickname: "Spitzname",
        remove: "Entfernen",
        switchErrorTitle: "Fehler beim Kontowechsel",
        noSavedPassword: { "Kein gespeichertes Passwort für \($0)." },
        refreshFailed: "Konto konnte nicht aktualisiert werden.",
        standard: "Standard",
        needsPassword: "Passwort nötig",
        activeAccount: "Aktives Konto",
        setDefault: "Als Standard festlegen",
        unsetDefault: "Als Standard entfernen",
        refreshAccount: "Konto aktualisieren",
        rename: "Umbenennen",
        signOut: "Abmelden",
        removeAccount: "Account entfernen",
        statusUnknown: "Unbekannt",
        statusOk: "Verbunden",
        statusNotStudent: "Nur für Schülerkonten",
        statusNoClass: "Keine Klasse gefunden",
        statusFailed: { "Nicht verbunden – \($0)" },
        statusOffline: "Offline",
        connectionTitle: "Konto & Verbindung",
        heroOk: "Dein POKYH-Konto ist aktiv. Todos, Erinnerungen und Klasse stehen zur Verfügung.",
        heroNotStudent: "POKYH-Funktionen sind nur mit einem Schülerkonto verfügbar.",
        heroNoClass: "Deine WebUntis-Klasse konnte nicht ermittelt werden — dadurch sind Todos & Erinnerungen gesperrt. Tippe auf Erneut prüfen; hilft das nicht, sende die technischen Details an den Support.",
        heroFailed: { "Verbindung zum POKYH-Server fehlgeschlagen: \($0)" },
        heroUnknown: "Status noch nicht ermittelt.",
        heroOffline: "Du bist offline angemeldet. Todos, Erinnerungen und Klasse zeigen den zuletzt gespeicherten Stand.",
        yourAccount: "Dein Konto",
        name: "Name",
        role: "Rolle",
        diagnosis: "Diagnose",
        checkAgain: "Erneut prüfen",
        technicalDetails: "Technische Details",
        forSupport: "Für den Support",
        share: "Teilen",
        detailsNote: "Enthält nur deine WebUntis-Daten – keine Passwörter.",
        activity: "Aktivität",
        activityLead: "An welchen Tagen du POKYH genutzt hast.",
        daysOnline: "Tage online",
        logins: "Anmeldungen",
        currentStreak: "Aktuelle Serie",
        longestStreak: "Längste Serie",
        activityFailed: "Deine Aktivität kann gerade nicht geladen werden.",
        moreStats: "Mehr Statistiken",
        tapDay: "Tippe auf einen Tag für Details.",
        loginCount: { ($0 == 1) ? "1 Anmeldung" : "\($0) Anmeldungen" },
        online: "Online",
        notOnline: "Nicht online",
        inPokyh: { "\($0) in POKYH" },
        statsTitle: "Statistiken",
        statsOnlyYou: "Nur für dich sichtbar",
        statsNeedAccount: "Statistiken gibt es mit einem POKYH-Konto, das gerade verbunden ist.",
        onlyWithConsent: "Nur mit persönlicher Nutzungsstatistik.",
        statsOffNotice: "Persönliche Statistiken sind ausgeschaltet. Darum siehst du hier nur, an welchen Tagen du online warst, nicht wie lange und was du am meisten öffnest. Einschalten kannst du sie auf pokyh.com unter Einstellungen → Datenschutz.",
        currentStreakIs: { "Aktuelle Serie: \($0)" },
        longestStreakIs: { "Längste Serie: \($0)" },
        usageTime: "Nutzungszeit",
        visits: { "Besuche: \($0)" },
        perDay: "Ø pro Tag",
        screensOpened: { "Geöffnete Seiten: \($0)" },
        whenOnline: "Wann du online bist",
        whenOnlineLead: "Nutzungszeit nach Uhrzeit.",
        weekdays: "Wochentage",
        weekdaysLead: "An welchen Wochentagen du online warst.",
        devices: "Geräte",
        devicesLead: "Tage, an denen du das jeweilige Gerät genutzt hast.",
        phone: "Handy",
        computer: "Computer",
        app: "App",
        browser: "Browser",
        topPages: "Meistgenutzte Seiten",
        topPagesLead: "Auf der Website, in den letzten Wochen.",
        created: "Was du erstellt hast",
        todosDone: "To-dos erledigt",
        todosOpen: "To-dos offen",
        reminders: "Erinnerungen",
        comments: "Kommentare",
        ratings: "Mensa-Bewertungen",
        memberSince: "Dabei seit",
        statsFooter: "Gezeigt wird, was der POKYH-Server ohnehin speichert (Datenschutzerklärung). Nur du siehst diese Übersicht.",
        pageNames: [
                "home": "Home", "timetable": "Stundenplan", "grades": "Noten", "messages": "Nachrichten",
                "absences": "Abwesenheiten", "classregevents": "Klassenbuch", "todos": "To-dos", "reminders": "Erinnerungen",
                "class": "Klasse", "canteen": "Mensa", "mensa": "Mensa", "school": "Schule", "profile": "Profil", "settings": "Einstellungen",
            ],
        changePassword: "Passwort ändern",
        passwordChanged: "Passwort geändert.",
        passwordChangedText: "Melde dich ab jetzt überall mit dem neuen Passwort an.",
        passwordLead: "Das ist dein WebUntis-Passwort. Es geht nur an WebUntis, POKYH speichert es nicht auf dem Server.",
        currentPassword: "Aktuelles Passwort",
        newPassword: "Neues Passwort",
        repeatPassword: "Neues Passwort wiederholen",
        errBothPasswords: "Bitte beide Passwörter eingeben.",
        errPasswordsDiffer: "Die neuen Passwörter stimmen nicht überein.",
        errSamePassword: "Das neue Passwort muss sich vom alten unterscheiden.",
        errPasswordFailed: "Das Passwort konnte nicht geändert werden.",
        views: { ($0 == 1) ? "1 Aufruf" : "\($0) Aufrufe" },
        studentId: "Schüler-ID",
        userId: "POKYH-ID",
        classIdLabel: "Klassen-ID",
        copy: "Kopieren",
        copied: "Kopiert",
        statsOffTitle: "Persönliche Statistiken sind ausgeschaltet",
        statsOffText: "Darum siehst du hier nur, an welchen Tagen du online warst, nicht wie lange und was du am meisten öffnest. Du kannst sie in den Einstellungen jederzeit einschalten und wieder ausschalten.",
    )
}

extension ProfileStrings {
    static let it = ProfileStrings(
        title: "Profilo",
        settings: "Impostazioni",
        settingsHint: "Aspetto, lingua, memoria e altro",
        account: "Account",
        username: "Nome utente",
        klasse: "Classe",
        school: "Scuola",
        schoolName: "LBS Bressanone",
        pokyhAccount: "Account POKYH",
        accounts: "Account",
        addAccount: "Aggiungi account",
        parent: "Genitore/tutore",
        student: "Studente/ssa",
        staff: "Docente/amministrazione",
        openPicture: "Apri l’immagine del profilo",
        removeAccountTitle: "Rimuovere l’account?",
        removeAccountBody: { "I dati di accesso salvati di \($0) verranno eliminati dal dispositivo." },
        removeAccountConfirm: "Rimuovi account",
        renameTitle: "Rinomina account",
        renameBody: { "Dai un nome personale a \($0) (visibile solo qui)." },
        nickname: "Soprannome",
        remove: "Rimuovi",
        switchErrorTitle: "Errore nel cambio account",
        noSavedPassword: { "Nessuna password salvata per \($0)." },
        refreshFailed: "Impossibile aggiornare l’account.",
        standard: "Predefinito",
        needsPassword: "Serve la password",
        activeAccount: "Account attivo",
        setDefault: "Imposta come predefinito",
        unsetDefault: "Rimuovi come predefinito",
        refreshAccount: "Aggiorna account",
        rename: "Rinomina",
        signOut: "Esci",
        removeAccount: "Rimuovi account",
        statusUnknown: "Sconosciuto",
        statusOk: "Connesso",
        statusNotStudent: "Solo per account studente",
        statusNoClass: "Nessuna classe trovata",
        statusFailed: { "Non connesso – \($0)" },
        statusOffline: "Offline",
        connectionTitle: "Account e connessione",
        heroOk: "Il tuo account POKYH è attivo. To-do, promemoria e classe sono disponibili.",
        heroNotStudent: "Le funzioni POKYH sono disponibili solo con un account studente.",
        heroNoClass: "Non è stato possibile determinare la tua classe WebUntis, quindi to-do e promemoria sono bloccati. Tocca Ricontrolla; se non basta, invia i dettagli tecnici al supporto.",
        heroFailed: { "Connessione al server POKYH non riuscita: \($0)" },
        heroUnknown: "Stato non ancora determinato.",
        heroOffline: "Sei connesso offline. To-do, promemoria e classe mostrano l’ultimo stato salvato.",
        yourAccount: "Il tuo account",
        name: "Nome",
        role: "Ruolo",
        diagnosis: "Diagnosi",
        checkAgain: "Ricontrolla",
        technicalDetails: "Dettagli tecnici",
        forSupport: "Per il supporto",
        share: "Condividi",
        detailsNote: "Contiene solo i tuoi dati WebUntis, nessuna password.",
        activity: "Attività",
        activityLead: "In quali giorni hai usato POKYH.",
        daysOnline: "Giorni online",
        logins: "Accessi",
        currentStreak: "Serie attuale",
        longestStreak: "Serie più lunga",
        activityFailed: "Al momento non è possibile caricare la tua attività.",
        moreStats: "Altre statistiche",
        tapDay: "Tocca un giorno per i dettagli.",
        loginCount: { ($0 == 1) ? "1 accesso" : "\($0) accessi" },
        online: "Online",
        notOnline: "Non online",
        inPokyh: { "\($0) in POKYH" },
        statsTitle: "Statistiche",
        statsOnlyYou: "Visibile solo a te",
        statsNeedAccount: "Le statistiche sono disponibili con un account POKYH connesso.",
        onlyWithConsent: "Solo con la statistica d’uso personale.",
        statsOffNotice: "Le statistiche personali sono disattivate. Per questo vedi solo in quali giorni eri online, non per quanto tempo e cosa apri di più. Puoi attivarle su pokyh.com in Impostazioni → Privacy.",
        currentStreakIs: { "Serie attuale: \($0)" },
        longestStreakIs: { "Serie più lunga: \($0)" },
        usageTime: "Tempo d’uso",
        visits: { "Visite: \($0)" },
        perDay: "Ø al giorno",
        screensOpened: { "Pagine aperte: \($0)" },
        whenOnline: "Quando sei online",
        whenOnlineLead: "Tempo d’uso per ora del giorno.",
        weekdays: "Giorni della settimana",
        weekdaysLead: "In quali giorni della settimana eri online.",
        devices: "Dispositivi",
        devicesLead: "Giorni in cui hai usato ciascun dispositivo.",
        phone: "Telefono",
        computer: "Computer",
        app: "App",
        browser: "Browser",
        topPages: "Pagine più usate",
        topPagesLead: "Sul sito, nelle ultime settimane.",
        created: "Cosa hai creato",
        todosDone: "To-do completati",
        todosOpen: "To-do aperti",
        reminders: "Promemoria",
        comments: "Commenti",
        ratings: "Valutazioni mensa",
        memberSince: "Iscritto da",
        statsFooter: "Viene mostrato ciò che il server POKYH salva comunque (informativa sulla privacy). Solo tu vedi questa panoramica.",
        pageNames: [
                "home": "Home", "timetable": "Orario", "grades": "Voti", "messages": "Messaggi",
                "absences": "Assenze", "classregevents": "Registro di classe", "todos": "To-do", "reminders": "Promemoria",
                "class": "Classe", "canteen": "Mensa", "mensa": "Mensa", "school": "Scuola", "profile": "Profilo", "settings": "Impostazioni",
            ],
        changePassword: "Cambia password",
        passwordChanged: "Password cambiata.",
        passwordChangedText: "D’ora in poi accedi ovunque con la nuova password.",
        passwordLead: "È la tua password WebUntis. Va solo a WebUntis, POKYH non la salva sul server.",
        currentPassword: "Password attuale",
        newPassword: "Nuova password",
        repeatPassword: "Ripeti la nuova password",
        errBothPasswords: "Inserisci entrambe le password.",
        errPasswordsDiffer: "Le nuove password non coincidono.",
        errSamePassword: "La nuova password deve essere diversa da quella vecchia.",
        errPasswordFailed: "Impossibile cambiare la password.",
        views: { ($0 == 1) ? "1 visita" : "\($0) visite" },
        studentId: "ID studente",
        userId: "ID POKYH",
        classIdLabel: "ID classe",
        copy: "Copia",
        copied: "Copiato",
        statsOffTitle: "Le statistiche personali sono disattivate",
        statsOffText: "Per questo qui vedi solo in quali giorni sei stato online, non per quanto tempo né cosa apri di più. Puoi attivarle e disattivarle nelle impostazioni in qualsiasi momento.",
    )
}

extension ProfileStrings {
    static let en = ProfileStrings(
        title: "Profile",
        settings: "Settings",
        settingsHint: "Appearance, language, storage and more",
        account: "Account",
        username: "Username",
        klasse: "Class",
        school: "School",
        schoolName: "LBS Brixen",
        pokyhAccount: "POKYH account",
        accounts: "Accounts",
        addAccount: "Add account",
        parent: "Guardian",
        student: "Student",
        staff: "Teacher/staff",
        openPicture: "Open profile picture",
        removeAccountTitle: "Remove account?",
        removeAccountBody: { "The saved sign-in data of \($0) will be deleted from this device." },
        removeAccountConfirm: "Remove account",
        renameTitle: "Rename account",
        renameBody: { "Give \($0) a name of your own (only visible here)." },
        nickname: "Nickname",
        remove: "Remove",
        switchErrorTitle: "Couldn't switch accounts",
        noSavedPassword: { "No saved password for \($0)." },
        refreshFailed: "The account couldn't be refreshed.",
        standard: "Default",
        needsPassword: "Password needed",
        activeAccount: "Active account",
        setDefault: "Set as default",
        unsetDefault: "Remove as default",
        refreshAccount: "Refresh account",
        rename: "Rename",
        signOut: "Sign out",
        removeAccount: "Remove account",
        statusUnknown: "Unknown",
        statusOk: "Connected",
        statusNotStudent: "Student accounts only",
        statusNoClass: "No class found",
        statusFailed: { "Not connected – \($0)" },
        statusOffline: "Offline",
        connectionTitle: "Account & connection",
        heroOk: "Your POKYH account is active. To-dos, reminders and class are available.",
        heroNotStudent: "POKYH features are only available with a student account.",
        heroNoClass: "Your WebUntis class couldn't be determined, so to-dos and reminders are locked. Tap Check again; if that doesn't help, send the technical details to support.",
        heroFailed: { "Connecting to the POKYH server failed: \($0)" },
        heroUnknown: "Status not determined yet.",
        heroOffline: "You are signed in offline. To-dos, reminders and class show the last saved state.",
        yourAccount: "Your account",
        name: "Name",
        role: "Role",
        diagnosis: "Diagnosis",
        checkAgain: "Check again",
        technicalDetails: "Technical details",
        forSupport: "For support",
        share: "Share",
        detailsNote: "Contains only your WebUntis data, no passwords.",
        activity: "Activity",
        activityLead: "The days you used POKYH.",
        daysOnline: "Days online",
        logins: "Sign-ins",
        currentStreak: "Current streak",
        longestStreak: "Longest streak",
        activityFailed: "Your activity can't be loaded right now.",
        moreStats: "More statistics",
        tapDay: "Tap a day for details.",
        loginCount: { ($0 == 1) ? "1 sign-in" : "\($0) sign-ins" },
        online: "Online",
        notOnline: "Not online",
        inPokyh: { "\($0) in POKYH" },
        statsTitle: "Statistics",
        statsOnlyYou: "Only visible to you",
        statsNeedAccount: "Statistics come with a POKYH account that is connected.",
        onlyWithConsent: "Only with personal usage statistics.",
        statsOffNotice: "Personal statistics are switched off, so you only see the days you were online, not for how long or what you open most. You can switch them on at pokyh.com under Settings → Privacy.",
        currentStreakIs: { "Current streak: \($0)" },
        longestStreakIs: { "Longest streak: \($0)" },
        usageTime: "Usage time",
        visits: { "Visits: \($0)" },
        perDay: "Ø per day",
        screensOpened: { "Pages opened: \($0)" },
        whenOnline: "When you are online",
        whenOnlineLead: "Usage time by time of day.",
        weekdays: "Weekdays",
        weekdaysLead: "The weekdays you were online.",
        devices: "Devices",
        devicesLead: "Days you used each device.",
        phone: "Phone",
        computer: "Computer",
        app: "App",
        browser: "Browser",
        topPages: "Most used pages",
        topPagesLead: "On the website, in the last weeks.",
        created: "What you created",
        todosDone: "To-dos done",
        todosOpen: "To-dos open",
        reminders: "Reminders",
        comments: "Comments",
        ratings: "Canteen ratings",
        memberSince: "Member since",
        statsFooter: "This shows what the POKYH server stores anyway (privacy policy). Only you see this overview.",
        pageNames: [
                "home": "Home", "timetable": "Timetable", "grades": "Grades", "messages": "Messages",
                "absences": "Absences", "classregevents": "Class register", "todos": "To-dos", "reminders": "Reminders",
                "class": "Class", "canteen": "Canteen", "mensa": "Canteen", "school": "School", "profile": "Profile", "settings": "Settings",
            ],
        changePassword: "Change password",
        passwordChanged: "Password changed.",
        passwordChangedText: "From now on, sign in everywhere with the new password.",
        passwordLead: "This is your WebUntis password. It only goes to WebUntis; POKYH doesn't store it on its server.",
        currentPassword: "Current password",
        newPassword: "New password",
        repeatPassword: "Repeat new password",
        errBothPasswords: "Please enter both passwords.",
        errPasswordsDiffer: "The new passwords don't match.",
        errSamePassword: "The new password must differ from the old one.",
        errPasswordFailed: "The password couldn't be changed.",
        views: { ($0 == 1) ? "1 view" : "\($0) views" },
        studentId: "Student ID",
        userId: "POKYH ID",
        classIdLabel: "Class ID",
        copy: "Copy",
        copied: "Copied",
        statsOffTitle: "Personal statistics are switched off",
        statsOffText: "That’s why you only see which days you were online here, not for how long or what you open most. You can switch them on and off in the settings at any time.",
    )
}
