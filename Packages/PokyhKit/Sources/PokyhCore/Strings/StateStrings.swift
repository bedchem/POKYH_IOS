// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct StateStrings: Sendable {
    public let notStudentTitle: String
    public let noClassTitle: String
    public let failedTitle: String
    public let unavailableTitle: String
    public let notStudent: @Sendable (String) -> String
    public let noClass: @Sendable (String) -> String
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
        noClass: { "Für \($0) wird deine WebUntis-Klasse benötigt — sie konnte für dein Konto nicht ermittelt werden." },
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
        failed: { f, r in "\(f) couldn't be loaded:\n\(r)" },
        offline: { "You are offline, and \($0) hasn't been saved on this device yet. It will load as soon as you're back online." },
        needsAccount: { "\($0) needs a POKYH account." },
        openAccount: "Profile → open POKYH account",
        featureTodos: "To-dos",
        featureReminders: "Reminders",
        featureClassList: "The class list",
    )
}
