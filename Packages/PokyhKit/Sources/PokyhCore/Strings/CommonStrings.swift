// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct CommonStrings: Sendable {
    public let back: String
    public let retry: String
    public let cancel: String
    public let save: String
    public let delete: String
    public let close: String
    public let done: String
    public let send: String
    public let edit: String
    public let ok: String
    public let yes: String
    public let no: String
    public let loading: String
    public let optional: String
    public let search: String
    public let clearSearch: String
    public let more: String
    public let today: String
    public let tomorrow: String
    public let yesterday: String
    public let unknown: String
    public let unknownError: String
    public let sessionExpired: String
    public let failedLater: String
    public let noConnection: String
    public let offlineNotSaved: String
    public let offlineTitle: String
    public let errSessionTitle: String
    public let errSessionDetail: String
    public let errOfflineTitle: String
    public let errOfflineDetail: String
    public let errGenericTitle: String
    public let errGenericDetail: String
    public let noPdfApp: String
    public let justNow: String
    public let minutesAgo: @Sendable (Int) -> String
    public let hoursAgo: @Sendable (Int) -> String
    public let daysAgo: @Sendable (Int) -> String
    public let edited: String
    public let hours: @Sendable (Int) -> String
    public let days: @Sendable (Int) -> String
    public let months: [String]
    public let monthsShort: [String]
    public let weekdays: [String]
    public let weekdaysShort: [String]
    public let decimal: Character
    public let dateSep: Character
    public let dateLong: @Sendable (Int, Int, Int) -> String
    public let dayMonth: @Sendable (Int, Int) -> String
    public let dayMonthShort: @Sendable (Int, Int) -> String
    public let schoolYear: @Sendable (Int) -> String
    public let comments: String
    public let noComments: String
    public let writeComment: String
    public let you: String
    public let ratedStars: @Sendable (Int) -> String
    public let noCommentsHint: String
    public let commentFailed: String
    public let sending: String
    public let editComment: String
    public let reportComment: String
    public let reportSubject: String
    public let reportBody: @Sendable (String, String, String, String, String) -> String
}

private let deMonths = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
private let deMonthsShort = ["Jän", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
private let itMonths = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
private let itMonthsShort = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
private let enMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
private let enMonthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

extension CommonStrings {
    static let de = CommonStrings(
        back: "Zurück",
        retry: "Erneut versuchen",
        cancel: "Abbrechen",
        save: "Speichern",
        delete: "Löschen",
        close: "Schließen",
        done: "Fertig",
        send: "Senden",
        edit: "Bearbeiten",
        ok: "OK",
        yes: "Ja",
        no: "Nein",
        loading: "Lädt…",
        optional: "Optional",
        search: "Suchen",
        clearSearch: "Suche leeren",
        more: "Mehr",
        today: "Heute",
        tomorrow: "Morgen",
        yesterday: "Gestern",
        unknown: "Unbekannt",
        unknownError: "Unbekannter Fehler.",
        sessionExpired: "Sitzung abgelaufen. Bitte erneut anmelden.",
        failedLater: "Das hat nicht geklappt. Bitte versuche es später erneut.",
        noConnection: "Keine Verbindung",
        offlineNotSaved: "Du bist offline, und das wurde auf diesem Gerät noch nicht gespeichert. Sobald du wieder Internet hast, wird es geladen.",
        offlineTitle: "Offline nicht verfügbar",
        errSessionTitle: "Sitzung abgelaufen",
        errSessionDetail: "Bitte melde dich erneut an.",
        errOfflineTitle: "Keine Verbindung",
        errOfflineDetail: "Überprüfe deine Internetverbindung und versuche es erneut.",
        errGenericTitle: "Daten konnten nicht geladen werden",
        errGenericDetail: "WebUntis ist gerade nicht erreichbar. Bitte versuche es später erneut.",
        noPdfApp: "Keine App gefunden, die PDFs öffnen kann.",
        justNow: "Gerade eben",
        minutesAgo: { "vor \($0) Min." },
        hoursAgo: { "vor \($0) Std." },
        daysAgo: { ($0 == 1) ? "vor 1 Tag" : "vor \($0) Tagen" },
        edited: "bearbeitet",
        hours: { ($0 == 1) ? "1 Stunde" : "\($0) Stunden" },
        days: { ($0 == 1) ? "1 Tag" : "\($0) Tage" },
        months: deMonths,
        monthsShort: deMonthsShort,
        weekdays: ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"],
        weekdaysShort: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"],
        decimal: ",",
        dateSep: ".",
        dateLong: { d, m, y in "\(d). \(deMonths[m - 1]) \(y)" },
        dayMonth: { d, m in "\(d). \(deMonths[m - 1])" },
        dayMonthShort: { d, m in "\(d). \(deMonthsShort[m - 1])" },
        schoolYear: { "Schuljahr \($0)/\(($0 + 1) % 100)" },
        comments: "Kommentare",
        noComments: "Noch keine Kommentare.",
        writeComment: "Kommentar schreiben…",
        you: "Du",
        ratedStars: { "\($0) von 5 Sternen" },
        noCommentsHint: "Schreib den ersten.",
        commentFailed: "Das hat nicht geklappt. Versuch es noch einmal.",
        sending: "Wird gesendet …",
        editComment: "Bearbeiten",
        reportComment: "Kommentar melden",
        reportSubject: "Meldung eines Inhalts auf POKYH",
        reportBody: { url, author, date, id, text in "Hallo POKYH-Team,\n\nich melde diesen Inhalt (Art. 16 Digital Services Act):\n\nWo: \(url)\nKommentar von „\(author)“ vom \(date) (ID \(id)):\n„\(text)“\n\nWarum der Inhalt rechtswidrig ist oder gegen die Nutzungsbedingungen verstößt:\n\n\nMein Name und meine E-Mail-Adresse:\n\n\nIch bestätige, dass meine Angaben nach bestem Wissen richtig und vollständig sind." },
    )
}

extension CommonStrings {
    static let it = CommonStrings(
        back: "Indietro",
        retry: "Riprova",
        cancel: "Annulla",
        save: "Salva",
        delete: "Elimina",
        close: "Chiudi",
        done: "Fatto",
        send: "Invia",
        edit: "Modifica",
        ok: "OK",
        yes: "Sì",
        no: "No",
        loading: "Caricamento…",
        optional: "Facoltativo",
        search: "Cerca",
        clearSearch: "Svuota la ricerca",
        more: "Altro",
        today: "Oggi",
        tomorrow: "Domani",
        yesterday: "Ieri",
        unknown: "Sconosciuto",
        unknownError: "Errore sconosciuto.",
        sessionExpired: "Sessione scaduta. Accedi di nuovo.",
        failedLater: "Non è andata. Riprova più tardi.",
        noConnection: "Nessuna connessione",
        offlineNotSaved: "Sei offline e questo non è ancora salvato su questo dispositivo. Appena torni online verrà caricato.",
        offlineTitle: "Non disponibile offline",
        errSessionTitle: "Sessione scaduta",
        errSessionDetail: "Accedi di nuovo.",
        errOfflineTitle: "Nessuna connessione",
        errOfflineDetail: "Controlla la connessione a internet e riprova.",
        errGenericTitle: "Impossibile caricare i dati",
        errGenericDetail: "WebUntis non è raggiungibile al momento. Riprova più tardi.",
        noPdfApp: "Nessuna app trovata per aprire i PDF.",
        justNow: "Proprio ora",
        minutesAgo: { "\($0) min fa" },
        hoursAgo: { "\($0) h fa" },
        daysAgo: { ($0 == 1) ? "1 giorno fa" : "\($0) giorni fa" },
        edited: "modificato",
        hours: { ($0 == 1) ? "1 ora" : "\($0) ore" },
        days: { ($0 == 1) ? "1 giorno" : "\($0) giorni" },
        months: itMonths,
        monthsShort: itMonthsShort,
        weekdays: ["lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica"],
        weekdaysShort: ["lun", "mar", "mer", "gio", "ven", "sab", "dom"],
        decimal: ",",
        dateSep: "/",
        dateLong: { d, m, y in "\(d) \(itMonths[m - 1]) \(y)" },
        dayMonth: { d, m in "\(d) \(itMonths[m - 1])" },
        dayMonthShort: { d, m in "\(d) \(itMonthsShort[m - 1])" },
        schoolYear: { "Anno scolastico \($0)/\(($0 + 1) % 100)" },
        comments: "Commenti",
        noComments: "Ancora nessun commento.",
        writeComment: "Scrivi un commento…",
        you: "Tu",
        ratedStars: { "\($0) stelle su 5" },
        noCommentsHint: "Scrivi il primo.",
        commentFailed: "Non è andato a buon fine. Riprova.",
        sending: "Invio in corso …",
        editComment: "Modifica",
        reportComment: "Segnala commento",
        reportSubject: "Segnalazione di un contenuto su POKYH",
        reportBody: { url, author, date, id, text in "Ciao team di POKYH,\n\nsegnalo questo contenuto (art. 16 Digital Services Act):\n\nDove: \(url)\nCommento di «\(author)» del \(date) (ID \(id)):\n«\(text)»\n\nPerché il contenuto è illegale o viola le condizioni d’uso:\n\n\nIl mio nome e il mio indirizzo e-mail:\n\n\nConfermo che le mie indicazioni sono esatte e complete secondo scienza e coscienza." },
    )
}

extension CommonStrings {
    static let en = CommonStrings(
        back: "Back",
        retry: "Try again",
        cancel: "Cancel",
        save: "Save",
        delete: "Delete",
        close: "Close",
        done: "Done",
        send: "Send",
        edit: "Edit",
        ok: "OK",
        yes: "Yes",
        no: "No",
        loading: "Loading…",
        optional: "Optional",
        search: "Search",
        clearSearch: "Clear search",
        more: "More",
        today: "Today",
        tomorrow: "Tomorrow",
        yesterday: "Yesterday",
        unknown: "Unknown",
        unknownError: "Unknown error.",
        sessionExpired: "Session expired. Please sign in again.",
        failedLater: "That didn't work. Please try again later.",
        noConnection: "No connection",
        offlineNotSaved: "You are offline, and this hasn't been saved on this device yet. It will load as soon as you're back online.",
        offlineTitle: "Not available offline",
        errSessionTitle: "Session expired",
        errSessionDetail: "Please sign in again.",
        errOfflineTitle: "No connection",
        errOfflineDetail: "Check your internet connection and try again.",
        errGenericTitle: "Data couldn't be loaded",
        errGenericDetail: "WebUntis can't be reached right now. Please try again later.",
        noPdfApp: "No app found that can open PDFs.",
        justNow: "Just now",
        minutesAgo: { "\($0) min ago" },
        hoursAgo: { "\($0) h ago" },
        daysAgo: { ($0 == 1) ? "1 day ago" : "\($0) days ago" },
        edited: "edited",
        hours: { ($0 == 1) ? "1 hour" : "\($0) hours" },
        days: { ($0 == 1) ? "1 day" : "\($0) days" },
        months: enMonths,
        monthsShort: enMonthsShort,
        weekdays: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
        weekdaysShort: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        decimal: ".",
        dateSep: "/",
        dateLong: { d, m, y in "\(d) \(enMonths[m - 1]) \(y)" },
        dayMonth: { d, m in "\(d) \(enMonths[m - 1])" },
        dayMonthShort: { d, m in "\(d) \(enMonthsShort[m - 1])" },
        schoolYear: { "School year \($0)/\(($0 + 1) % 100)" },
        comments: "Comments",
        noComments: "No comments yet.",
        writeComment: "Write a comment…",
        you: "You",
        ratedStars: { "\($0) out of 5 stars" },
        noCommentsHint: "Write the first one.",
        commentFailed: "That didn’t work. Please try again.",
        sending: "Sending …",
        editComment: "Edit",
        reportComment: "Report comment",
        reportSubject: "Report of content on POKYH",
        reportBody: { url, author, date, id, text in "Hello POKYH team,\n\nI am reporting this content (Art. 16 Digital Services Act):\n\nWhere: \(url)\nComment by “\(author)” on \(date) (ID \(id)):\n“\(text)”\n\nWhy the content is illegal or breaks the terms of use:\n\n\nMy name and e-mail address:\n\n\nI confirm that my information is accurate and complete to the best of my knowledge." },
    )
}
