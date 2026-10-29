// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct SystemStrings: Sendable {
    public let next: String
    public let closeIn: @Sendable (Int) -> String
    public let popupOf: @Sendable (Int, Int) -> String
    public let updateTitle: String
    public let updateConfirm: String
    public let tomorrow: String
    public let updateText: @Sendable (String, String) -> String
    public let downloading: String
    public let connecting: String
    public let allowInstall: String
    public let openSettings: String
    public let allowInstallText: String
    public let updateFailed: String
    public let githubStatus: @Sendable (Int) -> String
    public let downloadFailedCode: @Sendable (Int) -> String
    public let saveFailed: String
    public let corrupt: String
    public let otherVariant: @Sendable (String) -> String
    public let notNewer: String
    public let installFailed: String
    public let noInternet: String
    public let downloadTimeout: String
    public let downloadFailed: String
    public let noConnection: String
    public let notAnswering: @Sendable (String) -> String
    public let allCached: String
    public let untisStale: String
    public let backendStale: String
    public let savedShown: String
    public let offlineSignedIn: String
    public let deviceOffline: String
    public let unreachable: @Sendable (String) -> String
    public let internetWorks: String
    public let backOnline: String
    public let reachableAgain: @Sendable (String) -> String
    public let connected: String
    public let asOf: @Sendable (String) -> String
    public let closeNotice: String
    public let unknownTime: String
    public let todayAt: @Sendable (String) -> String
    public let yesterdayAt: @Sendable (String) -> String
    public let server: String
    public let serverError: @Sendable (Int) -> String
    public let noConn: String
    public let timeout: String
    public let notReachable: String
    public let privacy: String
    public let privacyUpdated: String
    public let privacyFirst: String
    public let privacyChanged: String
    public let privacyRead: String
    public let privacyFailed: String
    public let understood: String
    public let channelInfo: String
    public let newMessage: String
    public let newMessages: @Sendable (Int) -> String
    public let newGrade: String
    public let lessonCancelled: String
    public let cancelledBody: @Sendable (String, String, String) -> String
    public let widgetGrades: String
    public let widgetNoGrades: String
    public let widgetNext: String
    public let widgetNoMore: String
    public let widgetEvent: String
}


extension SystemStrings {
    static let de = SystemStrings(
        next: "Weiter",
        closeIn: { "Schließen in \($0) Sekunden möglich" },
        popupOf: { i, n in "Mitteilung \(i) von \(n)" },
        updateTitle: "Update verfügbar",
        updateConfirm: "Aktualisieren",
        tomorrow: "Morgen",
        updateText: { v, i in "Version \(v) ist verfügbar (installiert: \(i))." },
        downloading: "Wird heruntergeladen…",
        connecting: "Verbinde…",
        allowInstall: "Installation erlauben",
        openSettings: "Einstellungen öffnen",
        allowInstallText: "Das Update ist heruntergeladen. Erlaube POKYH einmalig, Apps zu installieren („Aus dieser Quelle zulassen“), und komm dann zurück — die Installation startet automatisch.",
        updateFailed: "Update fehlgeschlagen",
        githubStatus: { "GitHub antwortet mit \($0)" },
        downloadFailedCode: { "Download fehlgeschlagen (\($0))" },
        saveFailed: "Update konnte nicht gespeichert werden",
        corrupt: "Die heruntergeladene Datei ist beschädigt.",
        otherVariant: { "Dieses Update ist für eine andere App-Variante (\($0))." },
        notNewer: "Das Update ist nicht neuer als die installierte Version.",
        installFailed: "Installation konnte nicht gestartet werden.",
        noInternet: "Keine Internetverbindung.",
        downloadTimeout: "Zeitüberschreitung beim Download.",
        downloadFailed: "Download fehlgeschlagen.",
        noConnection: "Keine Internetverbindung",
        notAnswering: { "\($0) antwortet nicht" },
        allCached: "Alle Daten stammen aus dem Zwischenspeicher",
        untisStale: "Stundenplan und Noten evtl. nicht aktuell",
        backendStale: "Mensa, To-dos und Erinnerungen evtl. nicht aktuell",
        savedShown: "Gespeicherte Daten werden angezeigt",
        offlineSignedIn: "Offline angemeldet",
        deviceOffline: "Dein Gerät ist offline",
        unreachable: { "\($0) nicht erreichbar" },
        internetWorks: "Dein Internet funktioniert",
        backOnline: "Wieder online",
        reachableAgain: { "\($0) wieder erreichbar" },
        connected: "Verbindung steht — Daten sind wieder aktuell",
        asOf: { "Stand \($0)" },
        closeNotice: "Hinweis schließen",
        unknownTime: "unbekannt",
        todayAt: { "heute, \($0)" },
        yesterdayAt: { "gestern, \($0)" },
        server: "POKYH-Server",
        serverError: { "Server antwortet mit Fehler \($0)" },
        noConn: "Keine Verbindung",
        timeout: "Zeitüberschreitung",
        notReachable: "Nicht erreichbar",
        privacy: "Datenschutzerklärung",
        privacyUpdated: "Datenschutzerklärung aktualisiert",
        privacyFirst: "Wie POKYH mit deinen Daten umgeht, steht in der Datenschutzerklärung.",
        privacyChanged: "Wir haben unsere Datenschutzerklärung aktualisiert.",
        privacyRead: "Datenschutzerklärung lesen",
        privacyFailed: "Das hat nicht geklappt. Bitte versuche es noch einmal.",
        understood: "Verstanden",
        channelInfo: "Nachrichten, Noten, Stundenausfälle und Erinnerungen",
        newMessage: "Neue Nachricht",
        newMessages: { "\($0) neue Nachrichten" },
        newGrade: "Neue Note",
        lessonCancelled: "Stunde fällt aus",
        cancelledBody: { s, d, t in "\(s) am \(d) um \(t) entfällt." },
        widgetGrades: "Noten",
        widgetNoGrades: "Keine Noten verfügbar",
        widgetNext: "Nächste Stunde",
        widgetNoMore: "Keine weiteren Stunden",
        widgetEvent: "Veranstaltung",
    )
}

extension SystemStrings {
    static let it = SystemStrings(
        next: "Avanti",
        closeIn: { "Chiudibile tra \($0) secondi" },
        popupOf: { i, n in "Avviso \(i) di \(n)" },
        updateTitle: "Aggiornamento disponibile",
        updateConfirm: "Aggiorna",
        tomorrow: "Domani",
        updateText: { v, i in "È disponibile la versione \(v) (installata: \(i))." },
        downloading: "Download in corso…",
        connecting: "Connessione…",
        allowInstall: "Consenti l’installazione",
        openSettings: "Apri impostazioni",
        allowInstallText: "L’aggiornamento è stato scaricato. Consenti una volta a POKYH di installare app («Consenti da questa fonte») e torna qui: l’installazione parte da sola.",
        updateFailed: "Aggiornamento non riuscito",
        githubStatus: { "GitHub risponde con \($0)" },
        downloadFailedCode: { "Download non riuscito (\($0))" },
        saveFailed: "Impossibile salvare l’aggiornamento",
        corrupt: "Il file scaricato è danneggiato.",
        otherVariant: { "Questo aggiornamento è per un’altra variante dell’app (\($0))." },
        notNewer: "L’aggiornamento non è più recente della versione installata.",
        installFailed: "Impossibile avviare l’installazione.",
        noInternet: "Nessuna connessione a Internet.",
        downloadTimeout: "Tempo scaduto durante il download.",
        downloadFailed: "Download non riuscito.",
        noConnection: "Nessuna connessione a Internet",
        notAnswering: { "\($0) non risponde" },
        allCached: "Tutti i dati provengono dalla memoria locale",
        untisStale: "Orario e voti forse non aggiornati",
        backendStale: "Mensa, to-do e promemoria forse non aggiornati",
        savedShown: "Vengono mostrati i dati salvati",
        offlineSignedIn: "Accesso offline",
        deviceOffline: "Il tuo dispositivo è offline",
        unreachable: { "\($0) non raggiungibile" },
        internetWorks: "La tua connessione funziona",
        backOnline: "Di nuovo online",
        reachableAgain: { "\($0) di nuovo raggiungibile" },
        connected: "Connessione attiva: i dati sono di nuovo aggiornati",
        asOf: { "Aggiornato \($0)" },
        closeNotice: "Chiudi avviso",
        unknownTime: "sconosciuto",
        todayAt: { "oggi, \($0)" },
        yesterdayAt: { "ieri, \($0)" },
        server: "Server POKYH",
        serverError: { "Il server risponde con l’errore \($0)" },
        noConn: "Nessuna connessione",
        timeout: "Tempo scaduto",
        notReachable: "Non raggiungibile",
        privacy: "Informativa sulla privacy",
        privacyUpdated: "Informativa sulla privacy aggiornata",
        privacyFirst: "Come POKYH tratta i tuoi dati è spiegato nell’informativa sulla privacy.",
        privacyChanged: "Abbiamo aggiornato la nostra informativa sulla privacy.",
        privacyRead: "Leggi l’informativa",
        privacyFailed: "Non ha funzionato. Riprova.",
        understood: "Ho capito",
        channelInfo: "Messaggi, voti, ore saltate e promemoria",
        newMessage: "Nuovo messaggio",
        newMessages: { "\($0) nuovi messaggi" },
        newGrade: "Nuovo voto",
        lessonCancelled: "Ora saltata",
        cancelledBody: { s, d, t in "\(s) del \(d) alle \(t) è annullata." },
        widgetGrades: "Voti",
        widgetNoGrades: "Nessun voto disponibile",
        widgetNext: "Prossima ora",
        widgetNoMore: "Nessun’altra ora",
        widgetEvent: "Evento",
    )
}

extension SystemStrings {
    static let en = SystemStrings(
        next: "Next",
        closeIn: { "Can be closed in \($0) seconds" },
        popupOf: { i, n in "Notice \(i) of \(n)" },
        updateTitle: "Update available",
        updateConfirm: "Update",
        tomorrow: "Tomorrow",
        updateText: { v, i in "Version \(v) is available (installed: \(i))." },
        downloading: "Downloading…",
        connecting: "Connecting…",
        allowInstall: "Allow installing",
        openSettings: "Open settings",
        allowInstallText: "The update has been downloaded. Allow POKYH once to install apps (“Allow from this source”), then come back — the installation starts by itself.",
        updateFailed: "Update failed",
        githubStatus: { "GitHub answers with \($0)" },
        downloadFailedCode: { "Download failed (\($0))" },
        saveFailed: "The update couldn’t be saved",
        corrupt: "The downloaded file is damaged.",
        otherVariant: { "This update is for another variant of the app (\($0))." },
        notNewer: "The update isn’t newer than the installed version.",
        installFailed: "The installation couldn’t be started.",
        noInternet: "No internet connection.",
        downloadTimeout: "The download timed out.",
        downloadFailed: "Download failed.",
        noConnection: "No internet connection",
        notAnswering: { "\($0) isn’t answering" },
        allCached: "All data comes from the cache",
        untisStale: "Timetable and grades may be out of date",
        backendStale: "Canteen, to-dos and reminders may be out of date",
        savedShown: "Showing saved data",
        offlineSignedIn: "Signed in offline",
        deviceOffline: "Your device is offline",
        unreachable: { "\($0) can’t be reached" },
        internetWorks: "Your internet works",
        backOnline: "Back online",
        reachableAgain: { "\($0) reachable again" },
        connected: "Connected — data is up to date again",
        asOf: { "As of \($0)" },
        closeNotice: "Close notice",
        unknownTime: "unknown",
        todayAt: { "today, \($0)" },
        yesterdayAt: { "yesterday, \($0)" },
        server: "POKYH server",
        serverError: { "Server answers with error \($0)" },
        noConn: "No connection",
        timeout: "Timed out",
        notReachable: "Not reachable",
        privacy: "Privacy policy",
        privacyUpdated: "Privacy policy updated",
        privacyFirst: "How POKYH handles your data is in the privacy policy.",
        privacyChanged: "We have updated our privacy policy.",
        privacyRead: "Read the privacy policy",
        privacyFailed: "That didn’t work. Please try again.",
        understood: "Got it",
        channelInfo: "Messages, grades, cancelled lessons and reminders",
        newMessage: "New message",
        newMessages: { "\($0) new messages" },
        newGrade: "New grade",
        lessonCancelled: "Lesson cancelled",
        cancelledBody: { s, d, t in "\(s) on \(d) at \(t) is cancelled." },
        widgetGrades: "Grades",
        widgetNoGrades: "No grades available",
        widgetNext: "Next lesson",
        widgetNoMore: "No more lessons",
        widgetEvent: "Event",
    )
}
