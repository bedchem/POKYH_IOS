// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct LoginStrings: Sendable {
    public let tagline: String
    public let username: String
    public let password: String
    public let showPassword: String
    public let hidePassword: String
    public let saveBiometric: String
    public let signIn: String
    public let signingIn: String
    public let forgotPassword: String
    public let hint: String
    public let privacyNote: String
    public let privacyRead: String
    public let mascotHello: String
    public let mascotHelloName: @Sendable (String) -> String
    public let mascotGo: String
    public let mascotOops: String
    public let mascotAngry: String
    public let resetTitle: String
    public let resetLead: String
    public let resetUser: String
    public let resetEmail: String
    public let resetSend: String
    public let resetSentTitle: String
    public let resetSentText: String
    public let resetUnreachable: String
    public let codeTitle: String
    public let codeHint: String
    public let codeWrong: String
    public let codeLabel: String
    public let codeConfirm: String
    public let mascotBack: String
    public let mascotTaps: [String]
    public let lockTitle: String
    public let lockSubtitle: String
    public let lockFailed: String
    public let lockNoBiometric: String
    public let lockChoose: String
    public let lockUnavailable: String
    public let lockPrompt: String
    public let lockOr: String
    public let lockSaved: String
    public let lockDefault: String
    public let lockManual: String
    public let lockAddOther: String
    public let mascotTapLabel: String
    public let schoolLabel: String
    public let schoolPlaceholder: String
    public let schoolShort: String
    public let schoolTooMany: String
    public let schoolNone: String
    public let schoolError: String
    public let schoolRate: String
    public let schoolLast: String
    public let schoolChange: String
    public let schoolClear: String
    public let subtitle: String
    public let serverShort: @Sendable (String) -> String
    public let ageShort: String
    public let imprint: String
    public let terms: String
    public let privacyLink: String
    public let resetOfficial: String
    public let office: String
    public let or: String
    public let officeStep1: String
    public let officeStep2: String
    public let officeStep3: String
    public let officeOpenLogin: String
    public let officeOpenProfile: String
    public let officeAdmin: String
    public let officeUser: String
    public let officeKey: String
    public let officeKeyHint: String
    public let errKeyMissing: String
    public let errKeyInvalid: String
    public let officeLead: String
    public let badKey: String
    public let officePaste: String
    public let mascotTooMuch: String
}


extension LoginStrings {
    static let de = LoginStrings(
        tagline: "Deine Schule in einer App",
        username: "Benutzername",
        password: "Passwort",
        showPassword: "Passwort anzeigen",
        hidePassword: "Passwort verbergen",
        saveBiometric: "Mit Biometrie speichern",
        signIn: "Anmelden",
        signingIn: "Anmelden…",
        forgotPassword: "Passwort vergessen?",
        hint: "Melde dich mit deinem WebUntis-Konto an.",
        privacyNote: "Wie POKYH mit deinen Daten umgeht, steht in der Datenschutzerklärung.",
        privacyRead: "Datenschutzerklärung lesen",
        mascotHello: "Hallo!",
        mascotHelloName: { "Hallo, \($0)!" },
        mascotGo: "Los geht's!",
        mascotOops: "Hoppla!",
        mascotAngry: "Hey! So nicht!",
        resetTitle: "Passwort vergessen",
        resetLead: "Gib deinen WebUntis-Benutzernamen und die E-Mail-Adresse ein, die in WebUntis hinterlegt ist. WebUntis schickt dir dann einen Link für ein neues Passwort.",
        resetUser: "Benutzername",
        resetEmail: "E-Mail-Adresse",
        resetSend: "Link anfordern",
        resetSentTitle: "E-Mail ist unterwegs.",
        resetSentText: "WebUntis schickt dir einen Link, mit dem du ein neues Passwort setzt. Schau auch im Spam-Ordner nach.",
        resetUnreachable: "WebUntis ist gerade nicht erreichbar.",
        codeTitle: "Code eingeben",
        codeHint: "Dein Konto ist mit Zwei-Faktor-Anmeldung geschützt. Gib den 6-stelligen Code aus deiner Authenticator-App ein.",
        codeWrong: "Der Code stimmt nicht oder ist abgelaufen. Nimm den neuen Code aus der App.",
        codeLabel: "Code",
        codeConfirm: "Anmelden",
        mascotBack: "Da bist du ja wieder!",
        mascotTaps: ["Hihi!", "Das kitzelt!", "Hey, du!", "Huch!", "Nochmal!"],
        lockTitle: "Entsperren",
        lockSubtitle: "Mit Biometrie oder Geräte-PIN anmelden",
        lockFailed: "Anmeldung fehlgeschlagen. Bitte erneut versuchen.",
        lockNoBiometric: "Biometrie nicht verfügbar.",
        lockChoose: "Wähle ein Konto oder melde dich mit Passwort an.",
        lockUnavailable: "Entsperren nicht möglich.",
        lockPrompt: "Mit Biometrie entsperren",
        lockOr: "oder",
        lockSaved: "Gespeicherte Konten",
        lockDefault: "Standard",
        lockManual: "Manuell anmelden",
        lockAddOther: "Anderes Konto hinzufügen",
        mascotTapLabel: "Maskottchen antippen",
        schoolLabel: "Schule suchen",
        schoolPlaceholder: "Schulname, Ort oder Adresse",
        schoolShort: "Gib mindestens 3 Zeichen ein.",
        schoolTooMany: "Zu viele Treffer. Ergänze den Ort oder die Postleitzahl.",
        schoolNone: "Keine Schule gefunden. Prüf die Schreibweise oder such nach dem Ort.",
        schoolError: "Die Schulsuche ist gerade nicht erreichbar. Versuch es gleich noch einmal.",
        schoolRate: "Viele Suchen in kurzer Zeit. In einer Minute geht es weiter.",
        schoolLast: "Zuletzt gewählt",
        schoolChange: "Andere Schule",
        schoolClear: "Suche leeren",
        subtitle: "Mit deinem WebUntis-Konto.",
        serverShort: { "Geht nur an \($0)" },
        ageShort: "Ab 14 Jahren",
        imprint: "Impressum",
        terms: "Nutzungsbedingungen",
        privacyLink: "Datenschutzerklärung",
        resetOfficial: "Stattdessen in WebUntis öffnen",
        office: "Mit Office 365 anmelden",
        or: "oder",
        officeStep1: "Melde dich bei WebUntis mit „Office 365 Anmeldung“ an.",
        officeStep2: "Öffne dein Profil, Reiter „Freigaben“. Tippe bei „Zugriff über Untis Mobile“ auf „Anzeigen“.",
        officeStep3: "Übernimm „Benutzer“ und „Schlüssel“ hier. Du kannst auch alles auf einmal kopieren und einfügen.",
        officeOpenLogin: "WebUntis öffnen",
        officeOpenProfile: "Profil öffnen",
        officeAdmin: "Steht dort, dass der Zugriff erst freigeschaltet werden muss, kann das nur deine Schule ändern.",
        officeUser: "Benutzer",
        officeKey: "Schlüssel",
        officeKeyHint: "Geht nur an den WebUntis-Server deiner Schule.",
        errKeyMissing: "Bitte Benutzer und Schlüssel eingeben.",
        errKeyInvalid: "Das ist kein gültiger Schlüssel. Kopiere ihn genau so, wie WebUntis ihn zeigt.",
        officeLead: "Dein Microsoft-Passwort braucht POKYH nicht. WebUntis gibt dir dafür einen Schlüssel für Apps:",
        badKey: "Benutzername oder Schlüssel ist falsch.",
        officePaste: "Aus der Zwischenablage einfügen",
        mascotTooMuch: "Hey, lass das!",
    )
}

extension LoginStrings {
    static let it = LoginStrings(
        tagline: "L’app scolastica della LBS Bressanone",
        username: "Nome utente",
        password: "Password",
        showPassword: "Mostra password",
        hidePassword: "Nascondi password",
        saveBiometric: "Salva con biometria",
        signIn: "Accedi",
        signingIn: "Accesso…",
        forgotPassword: "Password dimenticata?",
        hint: "Accedi con il tuo account WebUntis.",
        privacyNote: "Come POKYH tratta i tuoi dati è spiegato nell’informativa sulla privacy.",
        privacyRead: "Leggi l’informativa sulla privacy",
        mascotHello: "Ciao!",
        mascotHelloName: { "Ciao, \($0)!" },
        mascotGo: "Si parte!",
        mascotOops: "Ops!",
        mascotAngry: "Ehi! Così no!",
        resetTitle: "Password dimenticata",
        resetLead: "Inserisci il tuo nome utente WebUntis e l’indirizzo e-mail salvato in WebUntis. WebUntis ti invierà un link per una nuova password.",
        resetUser: "Nome utente",
        resetEmail: "Indirizzo e-mail",
        resetSend: "Richiedi il link",
        resetSentTitle: "L’e-mail è in arrivo.",
        resetSentText: "WebUntis ti invia un link per impostare una nuova password. Controlla anche lo spam.",
        resetUnreachable: "WebUntis non è raggiungibile al momento.",
        codeTitle: "Inserisci il codice",
        codeHint: "Il tuo account è protetto con l’accesso a due fattori. Inserisci il codice a 6 cifre della tua app di autenticazione.",
        codeWrong: "Il codice non è corretto o è scaduto. Usa il nuovo codice dell’app.",
        codeLabel: "Codice",
        codeConfirm: "Accedi",
        mascotBack: "Eccoti di nuovo!",
        mascotTaps: ["Ih ih!", "Mi fai il solletico!", "Ehi, tu!", "Ops!", "Ancora!"],
        lockTitle: "Sblocca",
        lockSubtitle: "Accedi con la biometria o il PIN del dispositivo",
        lockFailed: "Accesso non riuscito. Riprova.",
        lockNoBiometric: "Biometria non disponibile.",
        lockChoose: "Scegli un account o accedi con la password.",
        lockUnavailable: "Impossibile sbloccare.",
        lockPrompt: "Sblocca con la biometria",
        lockOr: "oppure",
        lockSaved: "Account salvati",
        lockDefault: "Predefinito",
        lockManual: "Accedi manualmente",
        lockAddOther: "Aggiungi un altro account",
        mascotTapLabel: "Tocca la mascotte",
        schoolLabel: "Cerca la scuola",
        schoolPlaceholder: "Nome della scuola, città o indirizzo",
        schoolShort: "Inserisci almeno 3 caratteri.",
        schoolTooMany: "Troppi risultati. Aggiungi la città o il CAP.",
        schoolNone: "Nessuna scuola trovata. Controlla come l’hai scritta o cerca per città.",
        schoolError: "La ricerca delle scuole non è raggiungibile al momento. Riprova tra poco.",
        schoolRate: "Molte ricerche in poco tempo. Tra un minuto puoi continuare.",
        schoolLast: "Scelta l’ultima volta",
        schoolChange: "Altra scuola",
        schoolClear: "Cancella ricerca",
        subtitle: "Con il tuo account WebUntis.",
        serverShort: { "Va solo a \($0)" },
        ageShort: "Dai 14 anni",
        imprint: "Note legali",
        terms: "Condizioni d’uso",
        privacyLink: "Informativa sulla privacy",
        resetOfficial: "Apri invece in WebUntis",
        office: "Accedi con Office 365",
        or: "oppure",
        officeStep1: "Accedi a WebUntis con “Login Office 365”.",
        officeStep2: "Apri il tuo profilo, scheda “Attivazioni”. In “Accesso da Untis Mobile” tocca “Mostrare”.",
        officeStep3: "Riporta qui “Utente” e “Chiave”. Puoi anche copiare e incollare tutto in una volta.",
        officeOpenLogin: "Apri WebUntis",
        officeOpenProfile: "Apri il profilo",
        officeAdmin: "Se lì c’è scritto che l’accesso deve prima essere attivato, solo la tua scuola può farlo.",
        officeUser: "Utente",
        officeKey: "Chiave",
        officeKeyHint: "Va solo al server WebUntis della tua scuola.",
        errKeyMissing: "Inserisci utente e chiave.",
        errKeyInvalid: "Questa non è una chiave valida. Copiala esattamente come la mostra WebUntis.",
        officeLead: "POKYH non ha bisogno della tua password Microsoft. WebUntis ti dà una chiave per le app:",
        badKey: "Nome utente o chiave errati.",
        officePaste: "Incolla dagli appunti",
        mascotTooMuch: "Ehi, smettila!",
    )
}

extension LoginStrings {
    static let en = LoginStrings(
        tagline: "The school app for LBS Brixen",
        username: "Username",
        password: "Password",
        showPassword: "Show password",
        hidePassword: "Hide password",
        saveBiometric: "Save with biometrics",
        signIn: "Sign in",
        signingIn: "Signing in…",
        forgotPassword: "Forgot password?",
        hint: "Sign in with your WebUntis account.",
        privacyNote: "How POKYH handles your data is explained in the privacy policy.",
        privacyRead: "Read the privacy policy",
        mascotHello: "Hi!",
        mascotHelloName: { "Hi, \($0)!" },
        mascotGo: "Let's go!",
        mascotOops: "Oops!",
        mascotAngry: "Hey! Not cool!",
        resetTitle: "Forgot password",
        resetLead: "Enter your WebUntis username and the e-mail address stored in WebUntis. WebUntis will then send you a link for a new password.",
        resetUser: "Username",
        resetEmail: "E-mail address",
        resetSend: "Request link",
        resetSentTitle: "The e-mail is on its way.",
        resetSentText: "WebUntis sends you a link to set a new password. Check your spam folder too.",
        resetUnreachable: "WebUntis can't be reached right now.",
        codeTitle: "Enter code",
        codeHint: "Your account is protected with two-factor sign-in. Enter the 6-digit code from your authenticator app.",
        codeWrong: "The code is wrong or has expired. Use the new code from the app.",
        codeLabel: "Code",
        codeConfirm: "Sign in",
        mascotBack: "There you are again!",
        mascotTaps: ["Hehe!", "That tickles!", "Hey, you!", "Whoa!", "Again!"],
        lockTitle: "Unlock",
        lockSubtitle: "Sign in with biometrics or your device PIN",
        lockFailed: "Sign-in failed. Please try again.",
        lockNoBiometric: "Biometrics not available.",
        lockChoose: "Choose an account or sign in with your password.",
        lockUnavailable: "Unlocking isn't possible.",
        lockPrompt: "Unlock with biometrics",
        lockOr: "or",
        lockSaved: "Saved accounts",
        lockDefault: "Default",
        lockManual: "Sign in manually",
        lockAddOther: "Add another account",
        mascotTapLabel: "Tap the mascot",
        schoolLabel: "Search for your school",
        schoolPlaceholder: "School name, city or address",
        schoolShort: "Type at least 3 characters.",
        schoolTooMany: "Too many matches. Add the town or postcode.",
        schoolNone: "No school found. Check the spelling or search by town.",
        schoolError: "The school search is not reachable right now. Try again in a moment.",
        schoolRate: "Lots of searches in a short time. You can carry on in a minute.",
        schoolLast: "Picked last time",
        schoolChange: "Other school",
        schoolClear: "Clear search",
        subtitle: "With your WebUntis account.",
        serverShort: { "Only sent to \($0)" },
        ageShort: "Ages 14 and up",
        imprint: "Imprint",
        terms: "Terms of use",
        privacyLink: "Privacy policy",
        resetOfficial: "Open in WebUntis instead",
        office: "Sign in with Office 365",
        or: "or",
        officeStep1: "Sign in to WebUntis with “Office 365 login”.",
        officeStep2: "Open your profile, tab “Data access”. Under “Access via Untis Mobile”, tap “Display”.",
        officeStep3: "Copy “User” and “Key” here. You can also copy and paste everything at once.",
        officeOpenLogin: "Open WebUntis",
        officeOpenProfile: "Open profile",
        officeAdmin: "If it says the access has to be activated first, only your school can do that.",
        officeUser: "User",
        officeKey: "Key",
        officeKeyHint: "Only sent to your school’s WebUntis server.",
        errKeyMissing: "Please enter your user and key.",
        errKeyInvalid: "That is not a valid key. Copy it exactly as WebUntis shows it.",
        officeLead: "POKYH does not need your Microsoft password. WebUntis gives you a key for apps instead:",
        badKey: "Wrong user name or key.",
        officePaste: "Paste from clipboard",
        mascotTooMuch: "Hey, stop that!",
    )
}
