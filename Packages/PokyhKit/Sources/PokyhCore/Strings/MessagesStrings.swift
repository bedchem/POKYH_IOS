// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct MessagesStrings: Sendable {
    public let markAllRead: String
    public let compose: String
    public let emptyTitle: String
    public let emptyFolder: String
    public let attachment: String
    public let attachments: String
    public let attachmentsLoading: String
    public let attachmentFailed: String
    public let noAppFor: @Sendable (String) -> String
    public let download: String
    public let message: String
    public let reply: String
    public let replyFailed: String
    public let noReply: String
    public let pickTeacher: String
    public let needSubject: String
    public let needText: String
    public let needSomething: String
    public let fileUnreadable: String
    public let toTeacher: String
    public let unavailable: String
    public let choose: String
    public let recipientsCount: @Sendable (Int) -> String
    public let subject: String
    public let textHint: String
    public let removeFile: @Sendable (String) -> String
    public let addAttachment: String
    public let draftSaved: String
    public let saveDraft: String
    public let recipientsFailed: String
    public let recipientsFailedLater: String
    public let recipientsLoading: String
    public let replySent: String
    public let messageSent: String
    public let recipients: String
    public let doneCount: @Sendable (Int) -> String
    public let searchTeacher: String
    public let classTeacher: String
    public let others: String
    public let selected: String
    public let at: @Sendable (String, String) -> String
    public let unknown: String
    public let noSubject: String
    public let toNames: @Sendable (String) -> String
    public let to: String
    public let externalLink: String
    public let leavingApp: String
    public let openLink: String
    public let search: String
    public let noMatches: String
    public let groupToday: String
    public let groupWeek: String
    public let groupOlder: String
    public let select: String
    public let selectAll: String
    public let selectedCount: @Sendable (Int) -> String
    public let delete: String
    public let deleteConfirm: @Sendable (Int) -> String
    public let deleteFailed: String
    public let deleteDraft: String
    public let draftLoading: String
    public let oneTeacher: String
    public let confirmTitle: String
    public let confirmText: @Sendable (String) -> String
    public let confirmAction: String
    public let confirmDone: @Sendable (String) -> String
    public let confirmDoneBy: @Sendable (String, String) -> String
    public let confirmFailed: String
    public let readStatus: @Sendable (Int, Int) -> String
    public let readCount: @Sendable (Int, Int) -> String
    public let readStatusTitle: String
    public let readStatusOpen: String
    public let readStatusFailed: String
    public let readConfirmedOn: @Sendable (String) -> String
    public let readPending: String
    public let revoke: String
    public let revokeConfirm: String
    public let revokeHint: String
    public let revokedNotice: String
    public let revokeFailed: String
    public let attachmentsError: String
    public let tapToReload: String
    public let needsConfirm: String
    public let openExternally: String
}


extension MessagesStrings {
    static let de = MessagesStrings(
        markAllRead: "Alle als gelesen",
        compose: "Mitteilung verfassen",
        emptyTitle: "Keine Nachrichten",
        emptyFolder: "Dieser Ordner ist leer.",
        attachment: "Anhang",
        attachments: "Anhänge",
        attachmentsLoading: "Anhänge werden geladen …",
        attachmentFailed: "Der Anhang konnte nicht geladen werden.",
        noAppFor: { "Keine App gefunden, die „\($0)“ öffnen kann." },
        download: "Herunterladen",
        message: "Nachricht",
        reply: "Antworten",
        replyFailed: "Antwort konnte nicht vorbereitet werden.",
        noReply: "Auf diese Nachricht kann nicht geantwortet werden.",
        pickTeacher: "Bitte mindestens eine Lehrkraft wählen.",
        needSubject: "Bitte einen Betreff eingeben.",
        needText: "Bitte einen Text eingeben.",
        needSomething: "Bitte gib einen Betreff, Text, Empfänger oder Anhang an.",
        fileUnreadable: "Mindestens eine Datei konnte nicht gelesen werden.",
        toTeacher: "Mitteilung an Lehrkraft",
        unavailable: "Nicht verfügbar",
        choose: "Wählen",
        recipientsCount: { "\($0) Empfänger" },
        subject: "Betreff",
        textHint: "Text hier eingeben",
        removeFile: { "\($0) entfernen" },
        addAttachment: "Anhang hinzufügen",
        draftSaved: "Entwurf gespeichert",
        saveDraft: "Als Entwurf speichern",
        recipientsFailed: "Empfänger konnten gerade nicht geladen werden.",
        recipientsFailedLater: "Empfänger konnten gerade nicht geladen werden. Bitte versuche es später erneut.",
        recipientsLoading: "Empfänger werden geladen …",
        replySent: "Antwort gesendet.",
        messageSent: "Nachricht gesendet.",
        recipients: "Empfänger",
        doneCount: { ($0 == 0) ? "Fertig" : "Fertig (\($0))" },
        searchTeacher: "Lehrkraft suchen…",
        classTeacher: "Klassenlehrkraft",
        others: "Andere",
        selected: "Ausgewählt",
        at: { d, t in "\(d) um \(t)" },
        unknown: "Unbekannt",
        noSubject: "(Kein Betreff)",
        toNames: { "An: \($0)" },
        to: "An",
        externalLink: "Externer Link",
        leavingApp: "Du verlässt die POKYH App",
        openLink: "Öffnen",
        search: "Nachrichten durchsuchen",
        noMatches: "Keine Nachricht gefunden.",
        groupToday: "Heute",
        groupWeek: "Diese Woche",
        groupOlder: "Älter",
        select: "Auswählen",
        selectAll: "Alle auswählen",
        selectedCount: { "\($0) ausgewählt" },
        delete: "Löschen",
        deleteConfirm: { ($0 == 1) ? "Diese Nachricht löschen?" : "\($0) Nachrichten löschen?" },
        deleteFailed: "Die Nachrichten konnten nicht gelöscht werden.",
        deleteDraft: "Entwurf löschen",
        draftLoading: "Entwurf wird geladen …",
        oneTeacher: "Eine Nachricht geht an eine Lehrperson.",
        confirmTitle: "Lesebestätigung erbeten",
        confirmText: { "\($0) möchte wissen, dass du die Nachricht gelesen hast." },
        confirmAction: "Lesen bestätigen",
        confirmDone: { "Lesen bestätigt am \($0)" },
        confirmDoneBy: { n, d in "\(n) hat das Lesen am \(d) bestätigt" },
        confirmFailed: "Die Lesebestätigung konnte nicht gesendet werden.",
        readStatus: { c, t in "\(c) von \(t) haben das Lesen bestätigt" },
        readCount: { c, t in "\(c)/\(t) gelesen" },
        readStatusTitle: "Lesebestätigungen",
        readStatusOpen: "Ansehen",
        readStatusFailed: "Die Lesebestätigungen konnten gerade nicht geladen werden.",
        readConfirmedOn: { "Bestätigt am \($0)" },
        readPending: "Noch nicht bestätigt",
        revoke: "Zurücknehmen",
        revokeConfirm: "Wirklich zurücknehmen?",
        revokeHint: "Die Empfänger sehen die Nachricht danach nicht mehr.",
        revokedNotice: "Zurückgenommen: Die Empfänger sehen diese Nachricht nicht mehr.",
        revokeFailed: "Die Nachricht konnte nicht zurückgenommen werden.",
        attachmentsError: "Fehler beim Laden",
        tapToReload: "Tippen zum erneuten Laden",
        needsConfirm: "Bestätigung erbeten",
        openExternally: "In anderer App öffnen",
    )
}

extension MessagesStrings {
    static let it = MessagesStrings(
        markAllRead: "Segna tutti come letti",
        compose: "Scrivi un messaggio",
        emptyTitle: "Nessun messaggio",
        emptyFolder: "Questa cartella è vuota.",
        attachment: "Allegato",
        attachments: "Allegati",
        attachmentsLoading: "Caricamento degli allegati …",
        attachmentFailed: "Impossibile caricare l’allegato.",
        noAppFor: { "Nessuna app trovata che possa aprire «\($0)»." },
        download: "Scarica",
        message: "Messaggio",
        reply: "Rispondi",
        replyFailed: "Impossibile preparare la risposta.",
        noReply: "Non è possibile rispondere a questo messaggio.",
        pickTeacher: "Scegli almeno un docente.",
        needSubject: "Inserisci un oggetto.",
        needText: "Inserisci un testo.",
        needSomething: "Indica un oggetto, un testo, un destinatario o un allegato.",
        fileUnreadable: "Almeno un file non è stato letto.",
        toTeacher: "Messaggio al docente",
        unavailable: "Non disponibile",
        choose: "Scegli",
        recipientsCount: { ($0 == 1) ? "1 destinatario" : "\($0) destinatari" },
        subject: "Oggetto",
        textHint: "Scrivi qui il testo",
        removeFile: { "Rimuovi \($0)" },
        addAttachment: "Aggiungi allegato",
        draftSaved: "Bozza salvata",
        saveDraft: "Salva come bozza",
        recipientsFailed: "Impossibile caricare i destinatari al momento.",
        recipientsFailedLater: "Impossibile caricare i destinatari al momento. Riprova più tardi.",
        recipientsLoading: "Caricamento dei destinatari …",
        replySent: "Risposta inviata.",
        messageSent: "Messaggio inviato.",
        recipients: "Destinatari",
        doneCount: { ($0 == 0) ? "Fatto" : "Fatto (\($0))" },
        searchTeacher: "Cerca docente…",
        classTeacher: "Coordinatore di classe",
        others: "Altri",
        selected: "Selezionato",
        at: { d, t in "\(d) alle \(t)" },
        unknown: "Sconosciuto",
        noSubject: "(Nessun oggetto)",
        toNames: { "A: \($0)" },
        to: "A",
        externalLink: "Link esterno",
        leavingApp: "Stai lasciando l’app POKYH",
        openLink: "Apri",
        search: "Cerca nei messaggi",
        noMatches: "Nessun messaggio trovato.",
        groupToday: "Oggi",
        groupWeek: "Questa settimana",
        groupOlder: "Meno recenti",
        select: "Seleziona",
        selectAll: "Seleziona tutti",
        selectedCount: { "\($0) selezionati" },
        delete: "Elimina",
        deleteConfirm: { ($0 == 1) ? "Eliminare questo messaggio?" : "Eliminare \($0) messaggi?" },
        deleteFailed: "Non è stato possibile eliminare i messaggi.",
        deleteDraft: "Elimina bozza",
        draftLoading: "Caricamento bozza …",
        oneTeacher: "Un messaggio va a un solo docente.",
        confirmTitle: "Conferma di lettura richiesta",
        confirmText: { "\($0) vuole sapere se hai letto il messaggio." },
        confirmAction: "Conferma lettura",
        confirmDone: { "Lettura confermata il \($0)" },
        confirmDoneBy: { n, d in "\(n) ha confermato la lettura il \(d)" },
        confirmFailed: "Non è stato possibile inviare la conferma di lettura.",
        readStatus: { c, t in "\(c) su \(t) hanno confermato la lettura" },
        readCount: { c, t in "\(c)/\(t) letti" },
        readStatusTitle: "Conferme di lettura",
        readStatusOpen: "Vedi",
        readStatusFailed: "Non è stato possibile caricare le conferme di lettura.",
        readConfirmedOn: { "Confermato il \($0)" },
        readPending: "Non ancora confermato",
        revoke: "Ritira",
        revokeConfirm: "Ritirare davvero?",
        revokeHint: "I destinatari non vedranno più il messaggio.",
        revokedNotice: "Ritirato: i destinatari non vedono più questo messaggio.",
        revokeFailed: "Non è stato possibile ritirare il messaggio.",
        attachmentsError: "Errore durante il caricamento",
        tapToReload: "Tocca per ricaricare",
        needsConfirm: "Conferma richiesta",
        openExternally: "Apri in un’altra app",
    )
}

extension MessagesStrings {
    static let en = MessagesStrings(
        markAllRead: "Mark all as read",
        compose: "Write a message",
        emptyTitle: "No messages",
        emptyFolder: "This folder is empty.",
        attachment: "Attachment",
        attachments: "Attachments",
        attachmentsLoading: "Loading attachments …",
        attachmentFailed: "The attachment couldn’t be loaded.",
        noAppFor: { "No app found that can open “\($0)”." },
        download: "Download",
        message: "Message",
        reply: "Reply",
        replyFailed: "The reply couldn’t be prepared.",
        noReply: "This message can’t be replied to.",
        pickTeacher: "Please choose at least one teacher.",
        needSubject: "Please enter a subject.",
        needText: "Please enter a text.",
        needSomething: "Please add a subject, text, recipient or attachment.",
        fileUnreadable: "At least one file couldn’t be read.",
        toTeacher: "Message to a teacher",
        unavailable: "Not available",
        choose: "Choose",
        recipientsCount: { ($0 == 1) ? "1 recipient" : "\($0) recipients" },
        subject: "Subject",
        textHint: "Type your text here",
        removeFile: { "Remove \($0)" },
        addAttachment: "Add attachment",
        draftSaved: "Draft saved",
        saveDraft: "Save as draft",
        recipientsFailed: "Recipients couldn’t be loaded right now.",
        recipientsFailedLater: "Recipients couldn’t be loaded right now. Please try again later.",
        recipientsLoading: "Loading recipients …",
        replySent: "Reply sent.",
        messageSent: "Message sent.",
        recipients: "Recipients",
        doneCount: { ($0 == 0) ? "Done" : "Done (\($0))" },
        searchTeacher: "Search for a teacher…",
        classTeacher: "Class teacher",
        others: "Others",
        selected: "Selected",
        at: { d, t in "\(d) at \(t)" },
        unknown: "Unknown",
        noSubject: "(No subject)",
        toNames: { "To: \($0)" },
        to: "To",
        externalLink: "External link",
        leavingApp: "You’re leaving the POKYH app",
        openLink: "Open",
        search: "Search messages",
        noMatches: "No message found.",
        groupToday: "Today",
        groupWeek: "This week",
        groupOlder: "Older",
        select: "Select",
        selectAll: "Select all",
        selectedCount: { "\($0) selected" },
        delete: "Delete",
        deleteConfirm: { ($0 == 1) ? "Delete this message?" : "Delete \($0) messages?" },
        deleteFailed: "The messages couldn’t be deleted.",
        deleteDraft: "Delete draft",
        draftLoading: "Loading draft …",
        oneTeacher: "A message goes to one teacher.",
        confirmTitle: "Read confirmation requested",
        confirmText: { "\($0) would like to know that you have read this message." },
        confirmAction: "Confirm reading",
        confirmDone: { "Reading confirmed on \($0)" },
        confirmDoneBy: { n, d in "\(n) confirmed reading on \(d)" },
        confirmFailed: "The read confirmation could not be sent.",
        readStatus: { c, t in "\(c) of \(t) confirmed reading" },
        readCount: { c, t in "\(c)/\(t) read" },
        readStatusTitle: "Read confirmations",
        readStatusOpen: "View",
        readStatusFailed: "The read confirmations could not be loaded right now.",
        readConfirmedOn: { "Confirmed on \($0)" },
        readPending: "Not confirmed yet",
        revoke: "Take back",
        revokeConfirm: "Really take back?",
        revokeHint: "Recipients will no longer see the message.",
        revokedNotice: "Taken back: recipients no longer see this message.",
        revokeFailed: "The message could not be taken back.",
        attachmentsError: "Failed to load",
        tapToReload: "Tap to reload",
        needsConfirm: "Confirmation requested",
        openExternally: "Open in another app",
    )
}
