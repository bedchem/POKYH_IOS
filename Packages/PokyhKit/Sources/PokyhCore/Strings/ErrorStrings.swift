// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct ErrorStrings: Sendable {
    public let needCredentials: String
    public let loginFailed: String
    public let badCredentials: String
    public let refused: String
    public let timetable: @Sendable (Int) -> String
    public let noSchoolYear: String
    public let grades: @Sendable (Int) -> String
    public let absenceTimes: @Sendable (Int) -> String
    public let absenceTimesPlain: String
    public let absences: @Sendable (Int) -> String
    public let messages: @Sendable (Int) -> String
    public let message: @Sendable (Int) -> String
    public let maxFiles: @Sendable (Int) -> String
    public let fileTooBig: @Sendable (String, Int) -> String
    public let draftFailed: String
    public let sendFailed: String
    public let classreg: @Sendable (Int) -> String
    public let services: String
    public let homework: @Sendable (Int) -> String
    public let details: String
    public let reasons: String
    public let endAfterStart: String
    public let reportNotAllowed: String
    public let reportFailed: String
    public let absenceNotFound: String
    public let absenceLocked: String
    public let absenceSaveFailed: String
    public let letterFailed: String
    public let letterBusy: String
    public let letterLoadFailed: String
    public let absenceExists: String
    public let bothPasswords: String
    public let tooLong: String
    public let samePassword: String
    public let passwordFailed: String
    public let userAndMail: String
    public let validMail: String
    public let untisDown: String
    public let resetNoMatch: String
    public let resetMailFailed: String
    public let resetNotAllowed: String
    public let resetInternal: String
    public let resetFailed: String
    public let replyFailed: String
    public let mensaOffline: String
    public let mensa: @Sendable (Int) -> String
    public let mensaInvalid: String
    public let connecting: String
    public let offlineNever: String
    public let signInImpossible: String
    public let checkNetwork: String
    public let tryLater: String
    public let confirming: String
    public let ratingOffline: String
    public let noRating: String
    public let waiting: String
    public let noConnection: String
    public let badAnswer: String
}


extension ErrorStrings {
    static let de = ErrorStrings(
        needCredentials: "Benutzername und Passwort erforderlich.",
        loginFailed: "Anmeldung fehlgeschlagen.",
        badCredentials: "Benutzername oder Passwort ist falsch.",
        refused: "WebUntis hat die Anmeldung abgelehnt.",
        timetable: { "Stundenplan nicht ladbar (HTTP \($0))." },
        noSchoolYear: "Schuljahr nicht gefunden.",
        grades: { "Noten nicht ladbar (HTTP \($0))." },
        absenceTimes: { "Fehlzeiten nicht ladbar (HTTP \($0))." },
        absenceTimesPlain: "Fehlzeiten nicht ladbar.",
        absences: { "Abwesenheiten nicht ladbar (HTTP \($0))." },
        messages: { "Nachrichten nicht ladbar (HTTP \($0))." },
        message: { "Nachricht nicht ladbar (HTTP \($0))." },
        maxFiles: { "Maximal \($0) Anhänge erlaubt." },
        fileTooBig: { n, mb in "„\(n)“ ist zu groß (max. \(mb) MB pro Datei)." },
        draftFailed: "Der Entwurf konnte nicht gespeichert werden. Bitte versuche es später erneut.",
        sendFailed: "Die Nachricht konnte nicht gesendet werden. Bitte versuche es später erneut.",
        classreg: { "Klassenbuch nicht ladbar (HTTP \($0))." },
        services: "Die Klassendienste konnten gerade nicht geladen werden.",
        homework: { "Hausaufgaben nicht ladbar (HTTP \($0))." },
        details: "Die Details konnten gerade nicht geladen werden.",
        reasons: "Abwesenheitsgründe konnten nicht geladen werden.",
        endAfterStart: "Das Ende muss nach dem Beginn liegen.",
        reportNotAllowed: "Abwesenheiten melden ist für dein Konto in WebUntis nicht freigegeben.",
        reportFailed: "Die Abwesenheit konnte nicht gemeldet werden.",
        absenceNotFound: "Die Abwesenheit wurde in WebUntis nicht gefunden.",
        absenceLocked: "WebUntis erlaubt dir bei dieser Abwesenheit keine Änderung.",
        absenceSaveFailed: "Die Abwesenheit konnte nicht gespeichert werden.",
        letterFailed: "Das Entschuldigungsschreiben konnte nicht erstellt werden.",
        letterBusy: "WebUntis erstellt das Schreiben noch. Versuch es gleich noch einmal.",
        letterLoadFailed: "Das Entschuldigungsschreiben konnte nicht geladen werden.",
        absenceExists: "Für diesen Zeitraum gibt es bereits eine Abwesenheit.",
        bothPasswords: "Bitte beide Passwörter eingeben.",
        tooLong: "Eingabe zu lang.",
        samePassword: "Das neue Passwort muss sich vom alten unterscheiden.",
        passwordFailed: "Das Passwort konnte nicht geändert werden.",
        userAndMail: "Bitte Benutzername und E-Mail-Adresse eingeben.",
        validMail: "Bitte eine gültige E-Mail-Adresse eingeben.",
        untisDown: "WebUntis ist gerade nicht erreichbar.",
        resetNoMatch: "Benutzername und E-Mail-Adresse passen zu keinem Konto.",
        resetMailFailed: "WebUntis konnte die E-Mail gerade nicht senden.",
        resetNotAllowed: "Das Zurücksetzen des Passworts ist an deiner Schule nicht freigegeben. Wende dich an das Sekretariat.",
        resetInternal: "WebUntis hat einen internen Fehler gemeldet.",
        resetFailed: "Das Zurücksetzen konnte nicht gestartet werden.",
        replyFailed: "Die Antwort konnte nicht gesendet werden.",
        mensaOffline: "Mensa nicht ladbar (keine Verbindung).",
        mensa: { "Mensa nicht ladbar (HTTP \($0))." },
        mensaInvalid: "Mensa nicht ladbar (ungültige Antwort).",
        connecting: "Verbinde mit WebUntis…",
        offlineNever: "Ohne Internet lässt sich nur ein Konto öffnen, das auf diesem Gerät schon einmal angemeldet war — mit dem dort gespeicherten Passwort.",
        signInImpossible: "Anmeldung nicht möglich",
        checkNetwork: "Keine Verbindung. Prüfe dein WLAN oder mobiles Netz.",
        tryLater: "Versuch es später noch einmal.",
        confirming: "Bestätige Identität…",
        ratingOffline: "Offline – Bewertung nicht geladen",
        noRating: "Noch keine Bewertung",
        waiting: "Wartet auf Internet",
        noConnection: "Keine Verbindung",
        badAnswer: "Ungültige Antwort",
    )
}

extension ErrorStrings {
    static let it = ErrorStrings(
        needCredentials: "Nome utente e password obbligatori.",
        loginFailed: "Accesso non riuscito.",
        badCredentials: "Nome utente o password errati.",
        refused: "WebUntis ha rifiutato l’accesso.",
        timetable: { "Impossibile caricare l’orario (HTTP \($0))." },
        noSchoolYear: "Anno scolastico non trovato.",
        grades: { "Impossibile caricare i voti (HTTP \($0))." },
        absenceTimes: { "Impossibile caricare le ore di assenza (HTTP \($0))." },
        absenceTimesPlain: "Impossibile caricare le ore di assenza.",
        absences: { "Impossibile caricare le assenze (HTTP \($0))." },
        messages: { "Impossibile caricare i messaggi (HTTP \($0))." },
        message: { "Impossibile caricare il messaggio (HTTP \($0))." },
        maxFiles: { "Sono consentiti al massimo \($0) allegati." },
        fileTooBig: { n, mb in "«\(n)» è troppo grande (max. \(mb) MB per file)." },
        draftFailed: "Impossibile salvare la bozza. Riprova più tardi.",
        sendFailed: "Impossibile inviare il messaggio. Riprova più tardi.",
        classreg: { "Impossibile caricare il registro di classe (HTTP \($0))." },
        services: "Impossibile caricare i servizi di classe al momento.",
        homework: { "Impossibile caricare i compiti (HTTP \($0))." },
        details: "Impossibile caricare i dettagli al momento.",
        reasons: "Impossibile caricare i motivi di assenza.",
        endAfterStart: "La fine deve essere dopo l’inizio.",
        reportNotAllowed: "Segnalare assenze non è abilitato per il tuo account in WebUntis.",
        reportFailed: "Impossibile segnalare l’assenza.",
        absenceNotFound: "L’assenza non è stata trovata in WebUntis.",
        absenceLocked: "WebUntis non ti consente di modificare questa assenza.",
        absenceSaveFailed: "Impossibile salvare l’assenza.",
        letterFailed: "Impossibile creare la giustificazione.",
        letterBusy: "WebUntis sta ancora creando il documento. Riprova tra poco.",
        letterLoadFailed: "Impossibile caricare la giustificazione.",
        absenceExists: "Per questo periodo esiste già un’assenza.",
        bothPasswords: "Inserisci entrambe le password.",
        tooLong: "Testo troppo lungo.",
        samePassword: "La nuova password deve essere diversa dalla vecchia.",
        passwordFailed: "Impossibile cambiare la password.",
        userAndMail: "Inserisci nome utente e indirizzo e-mail.",
        validMail: "Inserisci un indirizzo e-mail valido.",
        untisDown: "WebUntis non è raggiungibile al momento.",
        resetNoMatch: "Nome utente e indirizzo e-mail non corrispondono a nessun account.",
        resetMailFailed: "WebUntis non è riuscito a inviare l’e-mail.",
        resetNotAllowed: "Il ripristino della password non è abilitato nella tua scuola. Rivolgiti alla segreteria.",
        resetInternal: "WebUntis ha segnalato un errore interno.",
        resetFailed: "Impossibile avviare il ripristino.",
        replyFailed: "Impossibile inviare la risposta.",
        mensaOffline: "Impossibile caricare la mensa (nessuna connessione).",
        mensa: { "Impossibile caricare la mensa (HTTP \($0))." },
        mensaInvalid: "Impossibile caricare la mensa (risposta non valida).",
        connecting: "Connessione a WebUntis…",
        offlineNever: "Senza Internet si può aprire solo un account già usato su questo dispositivo, con la password salvata.",
        signInImpossible: "Accesso non possibile",
        checkNetwork: "Nessuna connessione. Controlla il Wi-Fi o la rete mobile.",
        tryLater: "Riprova più tardi.",
        confirming: "Verifica dell’identità…",
        ratingOffline: "Offline – valutazione non caricata",
        noRating: "Ancora nessuna valutazione",
        waiting: "In attesa di Internet",
        noConnection: "Nessuna connessione",
        badAnswer: "Risposta non valida",
    )
}

extension ErrorStrings {
    static let en = ErrorStrings(
        needCredentials: "Username and password required.",
        loginFailed: "Sign-in failed.",
        badCredentials: "Username or password is wrong.",
        refused: "WebUntis refused the sign-in.",
        timetable: { "The timetable couldn’t be loaded (HTTP \($0))." },
        noSchoolYear: "School year not found.",
        grades: { "The grades couldn’t be loaded (HTTP \($0))." },
        absenceTimes: { "The missed lessons couldn’t be loaded (HTTP \($0))." },
        absenceTimesPlain: "The missed lessons couldn’t be loaded.",
        absences: { "The absences couldn’t be loaded (HTTP \($0))." },
        messages: { "The messages couldn’t be loaded (HTTP \($0))." },
        message: { "The message couldn’t be loaded (HTTP \($0))." },
        maxFiles: { "At most \($0) attachments are allowed." },
        fileTooBig: { n, mb in "“\(n)” is too big (max. \(mb) MB per file)." },
        draftFailed: "The draft couldn’t be saved. Please try again later.",
        sendFailed: "The message couldn’t be sent. Please try again later.",
        classreg: { "The class register couldn’t be loaded (HTTP \($0))." },
        services: "The class duties couldn’t be loaded right now.",
        homework: { "The homework couldn’t be loaded (HTTP \($0))." },
        details: "The details couldn’t be loaded right now.",
        reasons: "The absence reasons couldn’t be loaded.",
        endAfterStart: "The end must be after the start.",
        reportNotAllowed: "Reporting absences isn’t enabled for your WebUntis account.",
        reportFailed: "The absence couldn’t be reported.",
        absenceNotFound: "The absence wasn’t found in WebUntis.",
        absenceLocked: "WebUntis doesn’t let you change this absence.",
        absenceSaveFailed: "The absence couldn’t be saved.",
        letterFailed: "The excuse letter couldn’t be created.",
        letterBusy: "WebUntis is still creating the letter. Try again in a moment.",
        letterLoadFailed: "The excuse letter couldn’t be loaded.",
        absenceExists: "There is already an absence for this period.",
        bothPasswords: "Please enter both passwords.",
        tooLong: "Input too long.",
        samePassword: "The new password must differ from the old one.",
        passwordFailed: "The password couldn’t be changed.",
        userAndMail: "Please enter your username and e-mail address.",
        validMail: "Please enter a valid e-mail address.",
        untisDown: "WebUntis can’t be reached right now.",
        resetNoMatch: "Username and e-mail address don’t match any account.",
        resetMailFailed: "WebUntis couldn’t send the e-mail right now.",
        resetNotAllowed: "Resetting the password isn’t enabled at your school. Ask the school office.",
        resetInternal: "WebUntis reported an internal error.",
        resetFailed: "The reset couldn’t be started.",
        replyFailed: "The reply couldn’t be sent.",
        mensaOffline: "The canteen couldn’t be loaded (no connection).",
        mensa: { "The canteen couldn’t be loaded (HTTP \($0))." },
        mensaInvalid: "The canteen couldn’t be loaded (invalid answer).",
        connecting: "Connecting to WebUntis…",
        offlineNever: "Without internet you can only open an account that has signed in on this device before — with the password saved there.",
        signInImpossible: "Sign-in not possible",
        checkNetwork: "No connection. Check your Wi-Fi or mobile data.",
        tryLater: "Try again later.",
        confirming: "Confirming identity…",
        ratingOffline: "Offline – rating not loaded",
        noRating: "No rating yet",
        waiting: "Waiting for internet",
        noConnection: "No connection",
        badAnswer: "Invalid response",
    )
}
