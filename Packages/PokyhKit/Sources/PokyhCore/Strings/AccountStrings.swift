// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct AccountStrings: Sendable {
    public let settingsLead: String
    public let themeHint: String
    public let email: String
    public let emailCardHint: String
    public let emailNone: String
    public let missing: String
    public let emailChange: String
    public let emailAdd: String
    public let accountError: String
    public let retry: String
    public let passwordTitle: String
    public let passwordCardHint: String
    public let passwordChange: String
    public let passwordForgot: String
    public let stateOn: String
    public let stateOff: String
    public let recommended: String
    public let devicesOne: String
    public let devicesCount: @Sendable (Int) -> String
    public let devicesView: String
    public let webSignInScan: String
    public let push: String
    public let pushOn: String
    public let pushOff: String
    public let pushBlocked: String
    public let pushEnable: String
    public let exportButton: String
    public let exportDone: String
    public let policy: String
    public let clearCacheTitle: String
    public let clearCacheHint: String
    public let cleared: String
    public let legal: String
    public let faq: String
    public let source: String
    public let checkButton: String
    public let logoutHint: String
    public let logoutConfirm: String
    public let website: String
    public let websiteHint: String
    public let settingsHint: String
    public let schoolLabel: String
    public let activityKept: @Sendable (Int) -> String
    public let activityKeptConsent: @Sendable (Int) -> String
    public let activityKeptYear: String
    public let activityKeptYearConsent: String
    public let less: String
    public let more: String
    public let accountsHint: String
    public let consentLink: String
    public let scanPrompt: String
    public let cameraNeeded: String
    public let openSettings: String
    public let crashTitle: String
    public let crashBody: String
    public let crashShare: String
}


extension AccountStrings {
    static let de = AccountStrings(
        settingsLead: "Darstellung, Konto, Sicherheit, Mitteilungen und Datenschutz.",
        themeHint: "System folgt der Einstellung deines Geräts.",
        email: "E-Mail-Adresse",
        emailCardHint: "Für das Zurücksetzen deines Passworts und Nachrichten per E-Mail.",
        emailNone: "Keine hinterlegt. Ohne E-Mail-Adresse kannst du dein Passwort nicht zurücksetzen.",
        missing: "Fehlt",
        emailChange: "Ändern",
        emailAdd: "Hinzufügen",
        accountError: "Dein WebUntis-Konto konnte gerade nicht geladen werden.",
        retry: "Nochmal versuchen",
        passwordTitle: "Passwort",
        passwordCardHint: "Dein WebUntis-Passwort. Es gilt auch in der WebUntis-App.",
        passwordChange: "Ändern",
        passwordForgot: "Vergessen?",
        stateOn: "An",
        stateOff: "Aus",
        recommended: "Empfohlen",
        devicesOne: "Nur auf diesem Gerät angemeldet.",
        devicesCount: { n in "Auf \(n) Geräten angemeldet." },
        devicesView: "Ansehen",
        webSignInScan: "Scannen",
        push: "Benachrichtigungen",
        pushOn: "Eingeschaltet",
        pushOff: "Neue Nachrichten, fällige To-dos und Erinnerungen melden.",
        pushBlocked: "In den Einstellungen deines Handys ausgeschaltet. Erlaube sie dort für POKYH.",
        pushEnable: "Einschalten",
        exportButton: "Herunterladen",
        exportDone: "Heruntergeladen",
        policy: "Datenschutzerklärung",
        clearCacheTitle: "Offline-Kopien löschen",
        clearCacheHint: "Gespeicherte Stundenpläne, Noten und Nachrichten auf diesem Gerät. Du bleibst angemeldet.",
        cleared: "Gelöscht",
        legal: "Impressum & Rechtliches",
        faq: "Häufige Fragen",
        source: "Quellcode auf GitHub",
        checkButton: "Prüfen",
        logoutHint: "Meldet dich auf diesem Gerät ab.",
        logoutConfirm: "Wirklich abmelden?",
        website: "Website",
        websiteHint: "Die öffentliche Seite von POKYH mit allen Infos.",
        settingsHint: "Darstellung, Sprache, Benachrichtigungen und Datenschutz.",
        schoolLabel: "Schule",
        activityKept: { n in "POKYH bewahrt Server-Protokolle \(n) Tage auf; ältere Tage bleiben leer." },
        activityKeptConsent: { n in "Nutzungszeit wird mit deiner Zustimmung \(n) Tage deinem Konto zugeordnet." },
        activityKeptYear: "POKYH bewahrt deine aktiven Tage und Anmeldungen für das laufende Schuljahr auf; am Schuljahresende kommen sie ins Schuljahresarchiv.",
        activityKeptYearConsent: "Nutzungszeit wird mit deiner Zustimmung ebenso lange deinem Konto zugeordnet.",
        less: "Weniger",
        more: "Mehr",
        accountsHint: "Auf diesem Gerät gespeichert. Tippe auf ein Konto, um zu wechseln.",
        consentLink: "In den Einstellungen einschalten",
        scanPrompt: "Halte die Kamera auf den QR-Code auf pokyh.com.",
        cameraNeeded: "Zum Scannen braucht POKYH die Kamera. Erlaube sie in den Einstellungen.",
        openSettings: "Einstellungen öffnen",
        crashTitle: "POKYH ist abgestürzt",
        crashBody: "Beim letzten Mal ist POKYH unerwartet beendet worden. Schick uns den Bericht, damit wir den Fehler beheben können. Er enthält nur den Fehler, die App-Version und das Handymodell.",
        crashShare: "Bericht teilen",
    )
}

extension AccountStrings {
    static let it = AccountStrings(
        settingsLead: "Aspetto, account, sicurezza, notifiche e privacy.",
        themeHint: "Sistema segue l’impostazione del dispositivo.",
        email: "Indirizzo e-mail",
        emailCardHint: "Per reimpostare la password e ricevere i messaggi via e-mail.",
        emailNone: "Nessuno. Senza e-mail non puoi reimpostare la password.",
        missing: "Manca",
        emailChange: "Modifica",
        emailAdd: "Aggiungi",
        accountError: "Il tuo account WebUntis non si è potuto caricare.",
        retry: "Riprova",
        passwordTitle: "Password",
        passwordCardHint: "La tua password di WebUntis. Vale anche nell’app di WebUntis.",
        passwordChange: "Cambia",
        passwordForgot: "Dimenticata?",
        stateOn: "Attivo",
        stateOff: "Disattivo",
        recommended: "Consigliato",
        devicesOne: "Connesso solo su questo dispositivo.",
        devicesCount: { n in "Connesso su \(n) dispositivi." },
        devicesView: "Vedi",
        webSignInScan: "Scansiona",
        push: "Notifiche",
        pushOn: "Attive",
        pushOff: "Avvisa di nuovi messaggi, to-do in scadenza e promemoria.",
        pushBlocked: "Disattivate nelle impostazioni del telefono. Consentile lì per POKYH.",
        pushEnable: "Attiva",
        exportButton: "Scarica",
        exportDone: "Scaricato",
        policy: "Informativa sulla privacy",
        clearCacheTitle: "Elimina le copie offline",
        clearCacheHint: "Orari, voti e messaggi salvati su questo dispositivo. Resti connesso.",
        cleared: "Eliminate",
        legal: "Note legali",
        faq: "Domande frequenti",
        source: "Codice sorgente su GitHub",
        checkButton: "Verifica",
        logoutHint: "Esci su questo dispositivo.",
        logoutConfirm: "Vuoi davvero uscire?",
        website: "Sito web",
        websiteHint: "Il sito pubblico di POKYH con tutte le informazioni.",
        settingsHint: "Aspetto, lingua, notifiche e privacy.",
        schoolLabel: "Scuola",
        activityKept: { n in "POKYH conserva i log del server per \(n) giorni; i giorni più vecchi restano vuoti." },
        activityKeptConsent: { n in "Con il tuo consenso il tempo d’uso resta collegato al tuo account per \(n) giorni." },
        activityKeptYear: "POKYH conserva i tuoi giorni attivi e i tuoi accessi per l’anno scolastico in corso; alla fine dell’anno passano nell’archivio dell’anno scolastico.",
        activityKeptYearConsent: "Con il tuo consenso il tempo d’uso resta collegato al tuo account per lo stesso periodo.",
        less: "Meno",
        more: "Più",
        accountsHint: "Salvati su questo dispositivo. Tocca un account per passare a quello.",
        consentLink: "Attiva nelle impostazioni",
        scanPrompt: "Inquadra il codice QR su pokyh.com.",
        cameraNeeded: "Per scansionare POKYH ha bisogno della fotocamera. Consentila nelle impostazioni.",
        openSettings: "Apri impostazioni",
        crashTitle: "POKYH si è chiuso",
        crashBody: "L’ultima volta POKYH si è chiuso inaspettatamente. Inviaci il rapporto, così possiamo correggere l’errore. Contiene solo l’errore, la versione dell’app e il modello del telefono.",
        crashShare: "Condividi rapporto",
    )
}

extension AccountStrings {
    static let en = AccountStrings(
        settingsLead: "Appearance, account, security, notifications and privacy.",
        themeHint: "System follows your device’s setting.",
        email: "E-mail address",
        emailCardHint: "For resetting your password and getting messages by e-mail.",
        emailNone: "None yet. Without an e-mail address you can’t reset your password.",
        missing: "Missing",
        emailChange: "Change",
        emailAdd: "Add",
        accountError: "Your WebUntis account could not be loaded right now.",
        retry: "Try again",
        passwordTitle: "Password",
        passwordCardHint: "Your WebUntis password. It also applies in the WebUntis app.",
        passwordChange: "Change",
        passwordForgot: "Forgot it?",
        stateOn: "On",
        stateOff: "Off",
        recommended: "Recommended",
        devicesOne: "Signed in on this device only.",
        devicesCount: { n in "Signed in on \(n) devices." },
        devicesView: "View",
        webSignInScan: "Scan",
        push: "Notifications",
        pushOn: "On",
        pushOff: "Tell me about new messages, due to-dos and reminders.",
        pushBlocked: "Turned off in your phone’s settings. Allow them there for POKYH.",
        pushEnable: "Turn on",
        exportButton: "Download",
        exportDone: "Downloaded",
        policy: "Privacy policy",
        clearCacheTitle: "Delete offline copies",
        clearCacheHint: "Timetables, grades and messages saved on this device. You stay signed in.",
        cleared: "Deleted",
        legal: "Imprint & legal",
        faq: "Frequently asked questions",
        source: "Source code on GitHub",
        checkButton: "Check",
        logoutHint: "Signs you out on this device.",
        logoutConfirm: "Really log out?",
        website: "Website",
        websiteHint: "The public POKYH site with all the details.",
        settingsHint: "Appearance, language, notifications and privacy.",
        schoolLabel: "School",
        activityKept: { n in "POKYH keeps server logs for \(n) days; older days stay empty." },
        activityKeptConsent: { n in "With your consent, time in POKYH stays linked to your account for \(n) days." },
        activityKeptYear: "POKYH keeps your active days and sign-ins for the current school year; at its end they move to the school-year archive.",
        activityKeptYearConsent: "With your consent, your time in POKYH stays linked to your account just as long.",
        less: "Less",
        more: "More",
        accountsHint: "Saved on this device. Tap an account to switch to it.",
        consentLink: "Turn it on in settings",
        scanPrompt: "Point the camera at the QR code on pokyh.com.",
        cameraNeeded: "POKYH needs the camera to scan. Allow it in the settings.",
        openSettings: "Open settings",
        crashTitle: "POKYH crashed",
        crashBody: "Last time, POKYH closed unexpectedly. Send us the report so we can fix it. It only contains the error, the app version and the phone model.",
        crashShare: "Share report",
    )
}
