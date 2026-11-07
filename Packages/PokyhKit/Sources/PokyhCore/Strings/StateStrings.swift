// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct StateStrings: Sendable {
    public let notStudentTitle: String
    public let noClassTitle: String
    public let failedTitle: String
    public let unavailableTitle: String
    public let notStudent: @Sendable (String) -> String
    public let noClass: @Sendable (String) -> String
    /// The class waits for its check at the next sign-in.
    public let noClassPending: @Sendable (String) -> String
    /// WebUntis names no class for the account.
    public let noClassInUntis: @Sendable (String) -> String
    /// Another account signs in on the same WebUntis pupil; an admin sorts it out.
    public let noClassShared: @Sendable (String) -> String
    public let failed: @Sendable (String, String) -> String
    public let offline: @Sendable (String) -> String
    public let needsAccount: @Sendable (String) -> String
    public let openAccount: String
    public let featureTodos: String
    public let featureReminders: String
    public let featureClassList: String
}


extension StateStrings {
    static let de = StateStrings(
        notStudentTitle: "Nur für Schülerkonten",
        noClassTitle: "Keine Klasse gefunden",
        failedTitle: "Verbindungsfehler",
        unavailableTitle: "Nicht verfügbar",
        notStudent: { "\($0) ist nur mit einem Schülerkonto verfügbar." },
        noClass: { "Für \($0) wird deine WebUntis-Klasse benötigt. Sie konnte für dein Konto nicht ermittelt werden." },
        noClassPending: { "Für \($0) wird deine Klasse gerade neu bei WebUntis geprüft. Das passiert bei der nächsten Anmeldung von selbst." },
        noClassInUntis: { "Für \($0) wird deine Klasse benötigt, aber dein WebUntis-Konto nennt keine. Wenn das nicht stimmt, wende dich an deine Schule." },
        noClassShared: { "Für \($0) wird deine Klasse benötigt. Ein anderes Konto meldet sich auf demselben WebUntis-Schüler an; ein Admin ordnet das bald zu." },
        failed: { f, r in "\(f) konnte nicht geladen werden:\n\(r)" },
        offline: { "Du bist offline, und \($0) wurde auf diesem Gerät noch nicht gespeichert. Sobald du wieder Internet hast, wird es geladen." },
        needsAccount: { "\($0) benötigt ein POKYH-Konto." },
        openAccount: "Profil → POKYH-Konto öffnen",
        featureTodos: "Todos",
        featureReminders: "Erinnerungen",
        featureClassList: "Die Klassenliste",
    )
}

extension StateStrings {
    static let it = StateStrings(
        notStudentTitle: "Solo per account studente",
        noClassTitle: "Nessuna classe trovata",
        failedTitle: "Errore di connessione",
        unavailableTitle: "Non disponibile",
        notStudent: { "\($0) è disponibile solo con un account studente." },
        noClass: { "Per \($0) serve la tua classe di WebUntis, che non è stato possibile determinare per il tuo account." },
        noClassPending: { "Per \($0) stiamo verificando di nuovo la tua classe con WebUntis. Succede da solo al prossimo accesso." },
        noClassInUntis: { "Per \($0) serve la tua classe, ma il tuo account WebUntis non ne indica nessuna. Se non è corretto, rivolgiti alla tua scuola." },
        noClassShared: { "Per \($0) serve la tua classe. Un altro account accede con lo stesso studente WebUntis; un amministratore lo assegnerà a breve." },
        failed: { f, r in "Impossibile caricare \(f):\n\(r)" },
        offline: { "Sei offline e \($0) non è ancora salvato su questo dispositivo. Appena torni online verrà caricato." },
        needsAccount: { "\($0) richiede un account POKYH." },
        openAccount: "Profilo → apri account POKYH",
        featureTodos: "I to-do",
        featureReminders: "I promemoria",
        featureClassList: "L’elenco della classe",
    )
}

extension StateStrings {
    static let en = StateStrings(
        notStudentTitle: "Student accounts only",
        noClassTitle: "No class found",
        failedTitle: "Connection error",
        unavailableTitle: "Not available",
        notStudent: { "\($0) is only available with a student account." },
        noClass: { "\($0) needs your WebUntis class, which couldn't be determined for your account." },
        noClassPending: { "For \($0), your class is being checked with WebUntis again. It happens on its own at your next sign-in." },
        noClassInUntis: { "\($0) needs your class, but your WebUntis account doesn't name one. If that's wrong, contact your school." },
        noClassShared: { "\($0) needs your class. Another account signs in as the same WebUntis student; an admin will sort it out soon." },
        failed: { f, r in "\(f) couldn't be loaded:\n\(r)" },
        offline: { "You are offline, and \($0) hasn't been saved on this device yet. It will load as soon as you're back online." },
        needsAccount: { "\($0) needs a POKYH account." },
        openAccount: "Profile → open POKYH account",
        featureTodos: "To-dos",
        featureReminders: "Reminders",
        featureClassList: "The class list",
    )
}
