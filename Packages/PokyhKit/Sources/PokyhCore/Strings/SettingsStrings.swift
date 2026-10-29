// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct SettingsStrings: Sendable {
    public let title: String
    public let lead: String
    public let appearance: String
    public let theme: String
    public let system: String
    public let light: String
    public let dark: String
    public let language: String
    public let languageSystem: String
    public let languageHint: String
    public let accountSecurity: String
    public let changePassword: String
    public let changePasswordHint: String
    public let forgotPassword: String
    public let forgotPasswordHint: String
    public let profile: String
    public let profileHint: String
    public let webSignIn: String
    public let webSignInHint: String
    public let webSignInConfirmTitle: String
    public let webSignInConfirmHint: String
    public let webSignInConfirm: String
    public let webSignInUnknownDevice: String
    public let webSignInDoneTitle: String
    public let webSignInDoneBody: String
    public let webSignInNotPokyh: String
    public let webSignInGone: String
    public let webSignInNoScanner: String
    public let webSignInScanAgain: String
    public let storage: String
    public let clearCache: String
    public let clearCacheHint: String
    public let cleared: String
    public let clearAll: String
    public let clearAllHint: String
    public let clearAllTitle: String
    public let clearAllBody: String
    public let clearAllConfirm: String
    public let about: String
    public let imprint: String
    public let privacy: String
    public let learnPrivacy: String
    public let contactSupport: String
    public let checkUpdates: String
    public let upToDate: String
    public let updateFailed: String
    public let version: String
    public let footer: String
    public let logout: String
    public let logoutTitle: String
    public let logoutBody: String
    public let supportTitle: String
    public let supportText: String
    public let supportAction: String
    public let devicesTitle: String
    public let devicesLead: String
    public let devicesHint: String
    public let devicesLoadError: String
    public let devicesFailed: String
    public let thisDevice: String
    public let otherDevices: String
    public let noOthers: String
    public let signOutOthers: String
    public let signOutOthersConfirm: String
    public let signedOutOthers: String
    public let history: String
    public let historyEmpty: String
    public let historyHint: @Sendable (Int) -> String
    public let showMore: String
    public let lastActive: @Sendable (String) -> String
    public let unknownDevice: String
    public let unknownPlace: String
    public let signOutShort: String
    public let notifications: String
    public let notificationsOn: String
    public let notificationsOff: String
    public let privacySection: String
    public let usage: String
    public let usageHint: String
    public let acknowledged: String
    public let never: String
    public let saveError: String
    public let exportTitle: String
    public let exportHint: String
    public let exporting: String
    public let tfApps: String
    public let tfCode: String
    public let tfCodeFormat: String
    public let tfCodeHint: String
    public let tfCopied: String
    public let tfCopy: String
    public let tfDisableText: String
    public let tfDisableTitle: String
    public let tfDisabling: String
    public let tfDone: String
    public let tfDoneNote: String
    public let tfDoneTitle: String
    public let tfEnable: String
    public let tfEnabling: String
    public let tfIntro: String
    public let tfManual: String
    public let tfRenewNote: String
    public let tfScan: String
    public let tfStart: String
    public let tfTitle: String
    public let acctTwoFactorDisable: String
    public let acctEmail: String
    public let acctEmailAdd: String
    public let acctEmailChange: String
    public let acctEmailInvalid: String
    public let acctEmailLead: String
    public let acctEmailNone: String
    public let acctEmailSave: String
    public let acctEmailSaved: String
    public let acctEmailSaving: String
    public let acctForward: String
    public let acctForwardHint: String
    public let acctForwardNeedsEmail: String
    public let acctTwoFactor: String
    public let acctTwoFactorCardOff: String
    public let acctTwoFactorCardOn: String
    public let acctTwoFactorRequired: String
    public let acctTwoFactorSetup: String
    public let tfDisableShort: String
    public let tfOpenApp: String
    public let tfNoApp: String
    public let untisLanguage: String
    public let untisLanguageHint: String
}


extension SettingsStrings {
    static let de = SettingsStrings(
        title: "Einstellungen",
        lead: "Darstellung, Konto, Speicher und Datenschutz.",
        appearance: "Darstellung",
        theme: "Farbschema",
        system: "System",
        light: "Hell",
        dark: "Dunkel",
        language: "Sprache",
        languageSystem: "Wie das Gerät",
        languageHint: "Gilt für die ganze App.",
        accountSecurity: "Konto & Sicherheit",
        changePassword: "WebUntis-Passwort ändern",
        changePasswordHint: "Gilt danach auch in der WebUntis-App.",
        forgotPassword: "Passwort zurücksetzen",
        forgotPasswordHint: "WebUntis schickt dir einen Link per E-Mail.",
        profile: "Profil & Aktivität",
        profileHint: "Deine Daten und wann du POKYH genutzt hast.",
        webSignIn: "Am Computer anmelden",
        webSignInHint: "QR-Code auf pokyh.com scannen, ohne Passwort.",
        webSignInConfirmTitle: "Diesen Computer anmelden?",
        webSignInConfirmHint: "Bestätige nur, wenn du selbst gerade an diesem Computer sitzt. Er sieht dann alles, was du in POKYH siehst.",
        webSignInConfirm: "Anmelden",
        webSignInUnknownDevice: "Unbekanntes Gerät",
        webSignInDoneTitle: "Angemeldet",
        webSignInDoneBody: "Der Computer ist jetzt mit deinem Konto angemeldet. Abmelden kannst du ihn auf der Website unter Einstellungen → Geräte.",
        webSignInNotPokyh: "Das ist kein Anmelde-Code von POKYH. Öffne pokyh.com/login am Computer und wähle „Mit der POKYH-App anmelden“.",
        webSignInGone: "Dieser Code ist abgelaufen. Die Website zeigt gleich einen neuen, scanne ihn noch einmal.",
        webSignInNoScanner: "Der QR-Scanner ist gerade nicht verfügbar. Er braucht die Google Play-Dienste; versuch es gleich noch einmal.",
        webSignInScanAgain: "Noch einmal scannen",
        storage: "Speicher & Daten",
        clearCache: "Cache leeren",
        clearCacheHint: "Offline-Kopien und Bilder · du bleibst angemeldet",
        cleared: "Geleert",
        clearAll: "Alle Daten löschen",
        clearAllHint: "Konten, Passwörter und Einstellungen · meldet dich ab",
        clearAllTitle: "Alle Daten löschen?",
        clearAllBody: "Alle Konten, gespeicherten Passwörter, Einstellungen und Offline-Daten werden von diesem Gerät entfernt. Du wirst abgemeldet und musst dich neu anmelden.",
        clearAllConfirm: "Alles löschen",
        about: "Über & Rechtliches",
        imprint: "Impressum",
        privacy: "Datenschutzerklärung",
        learnPrivacy: "Pokyh Learn · Datenschutz",
        contactSupport: "Support kontaktieren",
        checkUpdates: "Nach Updates suchen",
        upToDate: "Aktuell",
        updateFailed: "Fehlgeschlagen",
        version: "Version",
        footer: "POKYH · Nicht offiziell mit der LBS Brixen oder WebUntis verbunden.",
        logout: "Abmelden",
        logoutTitle: "Wirklich abmelden?",
        logoutBody: "Du wirst abgemeldet. Dein gespeichertes Konto bleibt auf dem Gerät, du kannst dich jederzeit wieder anmelden.",
        supportTitle: "POKYH unterstützen",
        supportText: "POKYH ist kostenlos, ohne Werbung und entsteht in unserer Freizeit. Wenn dir die App hilft und du magst, kannst du uns einen Kaffee spendieren. Ganz freiwillig: alles bleibt für alle gleich.",
        supportAction: "Buy me a coffee",
        devicesTitle: "Geräte & Anmeldungen",
        devicesLead: "Hier siehst du, wo du bei POKYH angemeldet bist. Kennst du ein Gerät nicht? Melde es ab und ändere dein Passwort.",
        devicesHint: "Wo du angemeldet bist, mit Ort und Zeit. Du kannst jedes Gerät abmelden.",
        devicesLoadError: "Die Geräte konnten gerade nicht geladen werden.",
        devicesFailed: "Das hat nicht geklappt. Versuch es noch einmal.",
        thisDevice: "Dieses Gerät",
        otherDevices: "Andere Geräte",
        noOthers: "Du bist auf keinem anderen Gerät angemeldet.",
        signOutOthers: "Alle anderen abmelden",
        signOutOthersConfirm: "Wirklich abmelden?",
        signedOutOthers: "Alle anderen Geräte sind abgemeldet.",
        history: "Anmeldungen",
        historyEmpty: "Noch keine Anmeldungen gespeichert.",
        historyHint: { "Deine Anmeldungen der letzten \($0) Tage." },
        showMore: "Mehr anzeigen",
        lastActive: { "Zuletzt aktiv \($0)" },
        unknownDevice: "Unbekanntes Gerät",
        unknownPlace: "Ort unbekannt",
        signOutShort: "Abmelden",
        notifications: "Benachrichtigungen",
        notificationsOn: "An – Noten, Nachrichten und Erinnerungen kommen als Mitteilung.",
        notificationsOff: "Aus – in den Systemeinstellungen einschalten.",
        privacySection: "Datenschutz",
        usage: "Persönliche Nutzungsstatistik",
        usageHint: "Ordnet deine Nutzung deinem Konto zu, damit du deine Aktivität im Profil siehst. Ohne Zustimmung wird nur anonym gezählt.",
        acknowledged: "Datenschutzhinweis bestätigt",
        never: "Noch nicht",
        saveError: "Konnte nicht gespeichert werden. Versuch es nochmal.",
        exportTitle: "Meine Daten herunterladen",
        exportHint: "Alles, was POKYH über dich speichert, sofort als Datei. Stundenplan, Noten und Nachrichten speichert POKYH nicht.",
        exporting: "Wird erstellt…",
        tfApps: "Du brauchst eine Authenticator-App, zum Beispiel Google Authenticator, Microsoft Authenticator oder 2FAS.",
        tfCode: "Code aus der App",
        tfCodeFormat: "Der Code hat 6 Ziffern.",
        tfCodeHint: "Der 6-stellige Code, den die App gerade zeigt.",
        tfCopied: "Kopiert",
        tfCopy: "Kopieren",
        tfDisableText: "Dann reicht zur Anmeldung wieder dein Passwort. Dein Konto ist damit schlechter geschützt.",
        tfDisableTitle: "Zwei-Faktor-Anmeldung ausschalten?",
        tfDisabling: "Wird ausgeschaltet…",
        tfDone: "Ab jetzt fragen WebUntis und POKYH bei der Anmeldung nach dem Code aus deiner App.",
        tfDoneNote: "Lösche den Eintrag in der App nicht. Ohne ihn kommst du nicht mehr in dein Konto.",
        tfDoneTitle: "Eingeschaltet",
        tfEnable: "Einschalten",
        tfEnabling: "Wird eingeschaltet…",
        tfIntro: "Zusätzlich zum Passwort brauchst du bei der Anmeldung einen 6-stelligen Code. Eine App auf deinem Handy erzeugt ihn alle 30 Sekunden neu. Wer nur dein Passwort kennt, kommt so nicht in dein Konto.",
        tfManual: "Kein Scannen möglich? Gib diesen Schlüssel in der App ein:",
        tfRenewNote: "Das gilt für WebUntis und für POKYH. POKYH fragt dich nach dem Code, wenn du dich neu anmeldest.",
        tfScan: "Scanne den QR-Code mit deiner Authenticator-App.",
        tfStart: "Weiter",
        tfTitle: "Zwei-Faktor-Anmeldung",
        acctTwoFactorDisable: "Ausschalten",
        acctEmail: "E-Mail-Adresse",
        acctEmailAdd: "Hinzufügen",
        acctEmailChange: "Ändern",
        acctEmailInvalid: "Bitte gib eine gültige E-Mail-Adresse ein.",
        acctEmailLead: "Hierhin schickt WebUntis Links zum Zurücksetzen deines Passworts und, wenn du willst, deine Nachrichten.",
        acctEmailNone: "Keine hinterlegt. Ohne E-Mail-Adresse kannst du dein Passwort nicht zurücksetzen.",
        acctEmailSave: "Speichern",
        acctEmailSaved: "Gespeichert. Schickt WebUntis dir eine Bestätigung, öffne den Link in der E-Mail.",
        acctEmailSaving: "Wird gespeichert…",
        acctForward: "Nachrichten auch per E-Mail",
        acctForwardHint: "WebUntis schickt dir neue Nachrichten zusätzlich an deine E-Mail-Adresse.",
        acctForwardNeedsEmail: "Dafür brauchst du zuerst eine E-Mail-Adresse.",
        acctTwoFactor: "Zwei-Faktor-Anmeldung",
        acctTwoFactorCardOff: "Schützt dein Konto mit einem Code aus einer App, auch wenn jemand dein Passwort kennt.",
        acctTwoFactorCardOn: "Bei jeder Anmeldung brauchst du den Code aus deiner App.",
        acctTwoFactorRequired: "An. Deine Schule verlangt sie für dein Konto.",
        acctTwoFactorSetup: "Einrichten",
        tfDisableShort: "Ausschalten",
        tfOpenApp: "In der Authenticator-App öffnen",
        tfNoApp: "Keine Authenticator-App gefunden. Gib den Schlüssel unten ein.",
        untisLanguage: "Sprache in WebUntis",
        untisLanguageHint: "Für WebUntis selbst und seine E-Mails. POKYH hat oben seine eigene Sprache.",
    )
}

extension SettingsStrings {
    static let it = SettingsStrings(
        title: "Impostazioni",
        lead: "Aspetto, account, memoria e privacy.",
        appearance: "Aspetto",
        theme: "Tema",
        system: "Sistema",
        light: "Chiaro",
        dark: "Scuro",
        language: "Lingua",
        languageSystem: "Come il dispositivo",
        languageHint: "Vale per tutta l’app.",
        accountSecurity: "Account e sicurezza",
        changePassword: "Cambia la password WebUntis",
        changePasswordHint: "Vale poi anche nell’app WebUntis.",
        forgotPassword: "Reimposta la password",
        forgotPasswordHint: "WebUntis ti invia un link per e-mail.",
        profile: "Profilo e attività",
        profileHint: "I tuoi dati e quando hai usato POKYH.",
        webSignIn: "Accedi sul computer",
        webSignInHint: "Scansiona il codice QR su pokyh.com, senza password.",
        webSignInConfirmTitle: "Accedere su questo computer?",
        webSignInConfirmHint: "Conferma solo se sei tu davanti a questo computer. Vedrà tutto ciò che vedi in POKYH.",
        webSignInConfirm: "Accedi",
        webSignInUnknownDevice: "Dispositivo sconosciuto",
        webSignInDoneTitle: "Accesso effettuato",
        webSignInDoneBody: "Il computer ora è collegato al tuo account. Puoi disconnetterlo sul sito in Impostazioni → Dispositivi.",
        webSignInNotPokyh: "Non è un codice di accesso POKYH. Apri pokyh.com/login sul computer e scegli «Accedi con l’app POKYH».",
        webSignInGone: "Questo codice è scaduto. Il sito ne mostra subito uno nuovo: scansionalo di nuovo.",
        webSignInNoScanner: "Lo scanner QR non è disponibile al momento. Richiede i servizi Google Play; riprova tra poco.",
        webSignInScanAgain: "Scansiona di nuovo",
        storage: "Memoria e dati",
        clearCache: "Svuota la cache",
        clearCacheHint: "Copie offline e immagini · resti connesso",
        cleared: "Svuotata",
        clearAll: "Elimina tutti i dati",
        clearAllHint: "Account, password e impostazioni · ti disconnette",
        clearAllTitle: "Eliminare tutti i dati?",
        clearAllBody: "Tutti gli account, le password salvate, le impostazioni e i dati offline verranno rimossi da questo dispositivo. Verrai disconnesso e dovrai accedere di nuovo.",
        clearAllConfirm: "Elimina tutto",
        about: "Info e note legali",
        imprint: "Note legali",
        privacy: "Informativa sulla privacy",
        learnPrivacy: "Pokyh Learn · privacy",
        contactSupport: "Contatta il supporto",
        checkUpdates: "Cerca aggiornamenti",
        upToDate: "Aggiornata",
        updateFailed: "Non riuscito",
        version: "Versione",
        footer: "POKYH · Non collegato ufficialmente alla LBS Bressanone o a WebUntis.",
        logout: "Esci",
        logoutTitle: "Vuoi davvero uscire?",
        logoutBody: "Verrai disconnesso. Il tuo account salvato resta sul dispositivo e puoi accedere di nuovo in qualsiasi momento.",
        supportTitle: "Sostieni POKYH",
        supportText: "POKYH è gratuito, senza pubblicità e nasce nel nostro tempo libero. Se l’app ti è utile e ti va, puoi offrirci un caffè. Del tutto facoltativo: tutto resta uguale per tutti.",
        supportAction: "Buy me a coffee",
        devicesTitle: "Dispositivi e accessi",
        devicesLead: "Qui vedi dove sei connesso a POKYH. Non riconosci un dispositivo? Disconnettilo e cambia la password.",
        devicesHint: "Dove sei connesso, con luogo e ora. Puoi disconnettere ogni dispositivo.",
        devicesLoadError: "Non è stato possibile caricare i dispositivi.",
        devicesFailed: "Non è andato a buon fine. Riprova.",
        thisDevice: "Questo dispositivo",
        otherDevices: "Altri dispositivi",
        noOthers: "Non sei connesso su nessun altro dispositivo.",
        signOutOthers: "Disconnetti tutti gli altri",
        signOutOthersConfirm: "Disconnettere davvero?",
        signedOutOthers: "Tutti gli altri dispositivi sono disconnessi.",
        history: "Accessi",
        historyEmpty: "Nessun accesso salvato finora.",
        historyHint: { "I tuoi accessi degli ultimi \($0) giorni." },
        showMore: "Mostra di più",
        lastActive: { "Ultima attività \($0)" },
        unknownDevice: "Dispositivo sconosciuto",
        unknownPlace: "Luogo sconosciuto",
        signOutShort: "Disconnetti",
        notifications: "Notifiche",
        notificationsOn: "Attive – voti, messaggi e promemoria arrivano come notifica.",
        notificationsOff: "Disattivate – attivale nelle impostazioni di sistema.",
        privacySection: "Privacy",
        usage: "Statistiche d’uso personali",
        usageHint: "Collega il tuo utilizzo al tuo account, così vedi la tua attività nel profilo. Senza consenso si conta solo in forma anonima.",
        acknowledged: "Informativa privacy confermata",
        never: "Non ancora",
        saveError: "Impossibile salvare. Riprova.",
        exportTitle: "Scarica i miei dati",
        exportHint: "Tutto ciò che POKYH salva su di te, subito come file. Orario, voti e messaggi POKYH non li salva.",
        exporting: "Creazione…",
        tfApps: "Ti serve un’app di autenticazione, per esempio Google Authenticator, Microsoft Authenticator o 2FAS.",
        tfCode: "Codice dell’app",
        tfCodeFormat: "Il codice ha 6 cifre.",
        tfCodeHint: "Il codice di 6 cifre che l’app mostra adesso.",
        tfCopied: "Copiato",
        tfCopy: "Copia",
        tfDisableText: "Per accedere basterà di nuovo la password. Il tuo account sarà meno protetto.",
        tfDisableTitle: "Disattivare l’accesso a due fattori?",
        tfDisabling: "Disattivazione…",
        tfDone: "D’ora in poi WebUntis e POKYH chiedono all’accesso il codice della tua app.",
        tfDoneNote: "Non eliminare la voce nell’app. Senza di essa non entri più nel tuo account.",
        tfDoneTitle: "Attivato",
        tfEnable: "Attiva",
        tfEnabling: "Attivazione…",
        tfIntro: "Oltre alla password, all’accesso ti serve un codice di 6 cifre. Un’app sul telefono lo genera ogni 30 secondi. Chi conosce solo la tua password non entra nel tuo account.",
        tfManual: "Non puoi scansionare? Inserisci questa chiave nell’app:",
        tfRenewNote: "Vale per WebUntis e per POKYH. POKYH ti chiede il codice quando accedi di nuovo.",
        tfScan: "Scansiona il codice QR con la tua app di autenticazione.",
        tfStart: "Avanti",
        tfTitle: "Accesso a due fattori",
        acctTwoFactorDisable: "Disattiva",
        acctEmail: "Indirizzo e-mail",
        acctEmailAdd: "Aggiungi",
        acctEmailChange: "Modifica",
        acctEmailInvalid: "Inserisci un indirizzo e-mail valido.",
        acctEmailLead: "Qui WebUntis invia i link per reimpostare la password e, se vuoi, i tuoi messaggi.",
        acctEmailNone: "Nessuno. Senza e-mail non puoi reimpostare la password.",
        acctEmailSave: "Salva",
        acctEmailSaved: "Salvato. Se WebUntis ti invia una conferma, apri il link nell’e-mail.",
        acctEmailSaving: "Salvataggio…",
        acctForward: "Messaggi anche via e-mail",
        acctForwardHint: "WebUntis ti invia i nuovi messaggi anche al tuo indirizzo e-mail.",
        acctForwardNeedsEmail: "Prima ti serve un indirizzo e-mail.",
        acctTwoFactor: "Accesso a due fattori",
        acctTwoFactorCardOff: "Protegge il tuo account con un codice da un’app, anche se qualcuno conosce la tua password.",
        acctTwoFactorCardOn: "A ogni accesso ti serve il codice della tua app.",
        acctTwoFactorRequired: "Attivo. La tua scuola lo richiede per il tuo account.",
        acctTwoFactorSetup: "Configura",
        tfDisableShort: "Disattiva",
        tfOpenApp: "Apri nell’app di autenticazione",
        tfNoApp: "Nessuna app di autenticazione trovata. Inserisci la chiave qui sotto.",
        untisLanguage: "Lingua in WebUntis",
        untisLanguageHint: "Per WebUntis e le sue e-mail. POKYH ha la sua lingua più sopra.",
    )
}

extension SettingsStrings {
    static let en = SettingsStrings(
        title: "Settings",
        lead: "Appearance, account, storage and privacy.",
        appearance: "Appearance",
        theme: "Colour scheme",
        system: "System",
        light: "Light",
        dark: "Dark",
        language: "Language",
        languageSystem: "Same as device",
        languageHint: "Applies to the whole app.",
        accountSecurity: "Account & security",
        changePassword: "Change WebUntis password",
        changePasswordHint: "Also applies in the WebUntis app afterwards.",
        forgotPassword: "Reset password",
        forgotPasswordHint: "WebUntis sends you a link by e-mail.",
        profile: "Profile & activity",
        profileHint: "Your data and when you used POKYH.",
        webSignIn: "Sign in on a computer",
        webSignInHint: "Scan the QR code on pokyh.com, no password needed.",
        webSignInConfirmTitle: "Sign in this computer?",
        webSignInConfirmHint: "Only confirm if you are sitting at this computer yourself. It will see everything you see in POKYH.",
        webSignInConfirm: "Sign in",
        webSignInUnknownDevice: "Unknown device",
        webSignInDoneTitle: "Signed in",
        webSignInDoneBody: "The computer is now signed in to your account. You can sign it out on the website under Settings → Devices.",
        webSignInNotPokyh: "This is not a POKYH sign-in code. Open pokyh.com/login on the computer and choose “Sign in with the POKYH app”.",
        webSignInGone: "This code has expired. The website shows a new one right away; scan it again.",
        webSignInNoScanner: "The QR scanner is not available right now. It needs Google Play services; try again in a moment.",
        webSignInScanAgain: "Scan again",
        storage: "Storage & data",
        clearCache: "Clear cache",
        clearCacheHint: "Offline copies and images · you stay signed in",
        cleared: "Cleared",
        clearAll: "Delete all data",
        clearAllHint: "Accounts, passwords and settings · signs you out",
        clearAllTitle: "Delete all data?",
        clearAllBody: "All accounts, saved passwords, settings and offline data will be removed from this device. You will be signed out and need to sign in again.",
        clearAllConfirm: "Delete everything",
        about: "About & legal",
        imprint: "Imprint",
        privacy: "Privacy policy",
        learnPrivacy: "Pokyh Learn · privacy",
        contactSupport: "Contact support",
        checkUpdates: "Check for updates",
        upToDate: "Up to date",
        updateFailed: "Failed",
        version: "Version",
        footer: "POKYH · Not officially affiliated with LBS Brixen or WebUntis.",
        logout: "Sign out",
        logoutTitle: "Sign out?",
        logoutBody: "You will be signed out. Your saved account stays on this device, and you can sign in again at any time.",
        supportTitle: "Support POKYH",
        supportText: "POKYH is free, has no ads and is built in our spare time. If the app helps you and you feel like it, you can buy us a coffee. Entirely optional: everything stays the same for everyone.",
        supportAction: "Buy me a coffee",
        devicesTitle: "Devices & sign-ins",
        devicesLead: "This is where you are signed in to POKYH. Don’t recognise a device? Sign it out and change your password.",
        devicesHint: "Where you are signed in, with place and time. You can sign out any device.",
        devicesLoadError: "The devices couldn’t be loaded right now.",
        devicesFailed: "That didn’t work. Please try again.",
        thisDevice: "This device",
        otherDevices: "Other devices",
        noOthers: "You aren’t signed in on any other device.",
        signOutOthers: "Sign out all others",
        signOutOthersConfirm: "Really sign out?",
        signedOutOthers: "All other devices are signed out.",
        history: "Sign-ins",
        historyEmpty: "No sign-ins saved yet.",
        historyHint: { "Your sign-ins of the last \($0) days." },
        showMore: "Show more",
        lastActive: { "Last active \($0)" },
        unknownDevice: "Unknown device",
        unknownPlace: "Unknown place",
        signOutShort: "Sign out",
        notifications: "Notifications",
        notificationsOn: "On – grades, messages and reminders arrive as notifications.",
        notificationsOff: "Off – turn them on in the system settings.",
        privacySection: "Privacy",
        usage: "Personal usage statistics",
        usageHint: "Links your use to your account so you can see your activity in your profile. Without consent it is only counted anonymously.",
        acknowledged: "Privacy notice acknowledged",
        never: "Not yet",
        saveError: "Could not be saved. Please try again.",
        exportTitle: "Download my data",
        exportHint: "Everything POKYH keeps about you, right away as a file. POKYH doesn’t keep your timetable, grades or messages.",
        exporting: "Preparing…",
        tfApps: "You need an authenticator app, for example Google Authenticator, Microsoft Authenticator or 2FAS.",
        tfCode: "Code from the app",
        tfCodeFormat: "The code has 6 digits.",
        tfCodeHint: "The 6-digit code the app shows right now.",
        tfCopied: "Copied",
        tfCopy: "Copy",
        tfDisableText: "Your password alone will be enough to sign in again. Your account will be less protected.",
        tfDisableTitle: "Turn off two-factor sign-in?",
        tfDisabling: "Turning off…",
        tfDone: "From now on WebUntis and POKYH ask for the code from your app when you sign in.",
        tfDoneNote: "Don’t delete the entry in the app. Without it you can’t get into your account.",
        tfDoneTitle: "Turned on",
        tfEnable: "Turn on",
        tfEnabling: "Turning on…",
        tfIntro: "Besides your password, signing in needs a 6-digit code. An app on your phone makes a new one every 30 seconds. Someone who only knows your password can’t get into your account.",
        tfManual: "Can’t scan? Enter this key in the app:",
        tfRenewNote: "This applies to WebUntis and POKYH. POKYH asks for the code when you sign in again.",
        tfScan: "Scan the QR code with your authenticator app.",
        tfStart: "Continue",
        tfTitle: "Two-factor sign-in",
        acctTwoFactorDisable: "Turn off",
        acctEmail: "E-mail address",
        acctEmailAdd: "Add",
        acctEmailChange: "Change",
        acctEmailInvalid: "Please enter a valid e-mail address.",
        acctEmailLead: "WebUntis sends password reset links here and, if you like, your messages.",
        acctEmailNone: "None yet. Without an e-mail address you can’t reset your password.",
        acctEmailSave: "Save",
        acctEmailSaved: "Saved. If WebUntis sends you a confirmation, open the link in the e-mail.",
        acctEmailSaving: "Saving…",
        acctForward: "Messages by e-mail too",
        acctForwardHint: "WebUntis also sends new messages to your e-mail address.",
        acctForwardNeedsEmail: "You need an e-mail address for this first.",
        acctTwoFactor: "Two-factor sign-in",
        acctTwoFactorCardOff: "Protects your account with a code from an app, even if someone knows your password.",
        acctTwoFactorCardOn: "Every sign-in needs the code from your app.",
        acctTwoFactorRequired: "On. Your school requires it for your account.",
        acctTwoFactorSetup: "Set up",
        tfDisableShort: "Turn off",
        tfOpenApp: "Open in the authenticator app",
        tfNoApp: "No authenticator app found. Enter the key below.",
        untisLanguage: "Language in WebUntis",
        untisLanguageHint: "For WebUntis itself and its e-mails. POKYH has its own language above.",
    )
}
