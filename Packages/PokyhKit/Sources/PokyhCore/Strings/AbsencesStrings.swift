// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct AbsencesStrings: Sendable {
    public let title: String
    public let exact: String
    public let rounded: String
    public let totalMissed: String
    public let excused: String
    public let unexcused: String
    public let rate: String
    public let ofLessons: @Sendable (String, String) -> String
    public let perMonth: String
    public let emptyTitle: String
    public let emptySubtitle: String
    public let statusExcused: String
    public let statusOpen: String
    public let reason: String
    public let text: String
    public let viewInTimetable: String
    public let timetableShort: String
    public let report: String
    public let reportTitle: String
    public let reported: String
    public let from: String
    public let until: String
    public let time: String
    public let apply: String
    public let textPlaceholder: String
    public let reportAction: String
    public let errChooseRange: String
    public let errEndAfterStart: String
    public let errChooseReason: String
    public let choose: String
    public let selected: String
    public let reasonsFailed: String
    public let reasonsLoading: String
    public let noReasons: String
    public let letter: String
    public let letterHint: String
    public let letterFailed: String
    public let exAction: String
    public let exTitle: String
    public let exLead: String
    public let exAbsence: String
    public let exTo: String
    public let exToSchool: String
    public let exNote: String
    public let exSave: String
    public let exSaving: String
    public let exDone: String
    public let exSavedInUntis: String
    public let exDoneTo: @Sendable (String) -> String
    public let exPartial: @Sendable (String) -> String
    public let exNoTeacher: String
    public let exForbidden: String
    public let exAlready: String
    public let exSendFailed: String
    public let exNotAllowed: String
    public let exSent: String
    public let exSentTo: @Sendable (String, String) -> String
    public let exSentLabel: @Sendable (String, String) -> String
    public let calc: String
    public let calcAbsent: String
    public let calcModeTotal: String
    public let calcModeWeekly: String
    public let calcTotal: String
    public let calcWeekly: String
    public let calcWeeks: String
    public let calcLimit: String
    public let calcLeft: @Sendable (String) -> String
    public let calcAtLimit: String
    public let calcOver: @Sendable (String) -> String
    public let calcEmpty: String
    public let calcInvalid: String
    public let ofLessonsYear: @Sendable (String, String) -> String
    public let spanLabel: String
    public let spanSoFar: String
    public let spanYear: String
    public let rateCounting: String
    public let rateMissing: String
    public let rateRetry: String
    public let forLabel: String
    public let me: String
    public let fromTimetable: String
    public let chooseLessons: String
    public let prevDay: String
    public let nextDay: String
    public let takeLessons: @Sendable (Int) -> String
    public let cancelledSuffix: String
    public let noLessonsDay: String
    public let notAvailable: String
    public let exPick: String
}


extension AbsencesStrings {
    static let de = AbsencesStrings(
        title: "Abwesenheiten",
        exact: "Exakt",
        rounded: "Gerundet",
        totalMissed: "Fehlstunden gesamt",
        excused: "Entschuldigt",
        unexcused: "Unentschuldigt",
        rate: "Fehlquote",
        ofLessons: { m, t in "\(m) von \(t) Unterricht bisher" },
        perMonth: "Pro Monat",
        emptyTitle: "Keine Fehlstunden",
        emptySubtitle: "Du hast keine Abwesenheiten in diesem Schuljahr.",
        statusExcused: "entschuldigt",
        statusOpen: "offen",
        reason: "Grund",
        text: "Text",
        viewInTimetable: "Im Stundenplan ansehen",
        timetableShort: "Stundenplan",
        report: "Abwesenheit melden",
        reportTitle: "Abwesenheit melden",
        reported: "Abwesenheit gemeldet.",
        from: "Von",
        until: "Bis",
        time: "Uhrzeit",
        apply: "Übernehmen",
        textPlaceholder: "Optional, z. B. Arzttermin",
        reportAction: "Melden",
        errChooseRange: "Bitte Beginn und Ende wählen.",
        errEndAfterStart: "Das Ende muss nach dem Beginn liegen.",
        errChooseReason: "Bitte einen Grund wählen.",
        choose: "Wählen",
        selected: "Ausgewählt",
        reasonsFailed: "Die Gründe konnten gerade nicht geladen werden. Bitte versuche es später erneut.",
        reasonsLoading: "Gründe werden geladen …",
        noReasons: "WebUntis bietet keine Gründe an.",
        letter: "Entschuldigungsschreiben",
        letterHint: "PDF aus WebUntis für die offenen Abwesenheiten",
        letterFailed: "Das Entschuldigungsschreiben konnte nicht geladen werden.",
        exAction: "Entschuldigen",
        exTitle: "Abwesenheit entschuldigen",
        exLead: "Deine Klassenlehrer bekommen eine Nachricht mit Grund und Notiz.",
        exAbsence: "Abwesenheit",
        exTo: "An",
        exToSchool: "Deine Schule über WebUntis",
        exNote: "Notiz (optional)",
        exSave: "An Klassenlehrer senden",
        exSaving: "Wird gesendet …",
        exDone: "Nachricht gesendet.",
        exSavedInUntis: "In WebUntis gespeichert.",
        exDoneTo: { "An \($0)" },
        exPartial: { "An \($0) konnte sie nicht gesendet werden." },
        exNoTeacher: "In WebUntis ist für deine Klasse keine Klassenlehrkraft hinterlegt.",
        exForbidden: "Nachrichten an Lehrkräfte sind für dein Konto in WebUntis nicht freigegeben.",
        exAlready: "Diese Abwesenheit ist schon entschuldigt.",
        exSendFailed: "Die Nachricht konnte nicht gesendet werden. Bitte versuche es später erneut.",
        exNotAllowed: "Abwesenheiten entschuldigen ist für dein Konto in WebUntis nicht freigegeben.",
        exSent: "Nachricht gesendet",
        exSentTo: { n, d in "An \(n) · \(d)" },
        exSentLabel: { n, d in "Nachricht an \(n) gesendet am \(d). Offen, bis die Schule sie entschuldigt." },
        calc: "Fehlstunden-Rechner",
        calcAbsent: "Gefehlt (Stunden)",
        calcModeTotal: "Gesamt",
        calcModeWeekly: "Pro Woche",
        calcTotal: "Stunden im Schuljahr",
        calcWeekly: "Stunden pro Woche",
        calcWeeks: "Schulwochen",
        calcLimit: "Grenze in Prozent",
        calcLeft: { "Bis zur Grenze darfst du noch \($0) Stunden fehlen." },
        calcAtLimit: "Du hast die Grenze genau erreicht.",
        calcOver: { "Du liegst \($0) Stunden über der Grenze. Sprich mit deiner Schule über Ausnahmen." },
        calcEmpty: "Gib deine Fehlstunden und die Stunden des Schuljahres ein.",
        calcInvalid: "Die Fehlstunden können nicht mehr sein als alle Stunden.",
        ofLessonsYear: { m, t in "\(m) von \(t) Unterricht im ganzen Schuljahr" },
        spanLabel: "Zeitraum",
        spanSoFar: "Bisher",
        spanYear: "Ganzes Jahr",
        rateCounting: "Wird aus dem Stundenplan berechnet …",
        rateMissing: "Noch nicht alle Wochen des Stundenplans geladen.",
        rateRetry: "Erneut laden",
        forLabel: "Für",
        me: "Ich",
        fromTimetable: "Aus Stundenplan wählen",
        chooseLessons: "Stunden auswählen",
        prevDay: "Vorheriger Tag",
        nextDay: "Nächster Tag",
        takeLessons: { ($0 == 1) ? "1 Stunde übernehmen" : "\($0) Stunden übernehmen" },
        cancelledSuffix: " (entfällt)",
        noLessonsDay: "Keine Stunden an diesem Tag.",
        notAvailable: "nicht verfügbar",
        exPick: "Bitte wähle einen Grund.",
    )
}

extension AbsencesStrings {
    static let it = AbsencesStrings(
        title: "Assenze",
        exact: "Esatto",
        rounded: "Arrotondato",
        totalMissed: "Ore di assenza totali",
        excused: "Giustificate",
        unexcused: "Non giustificate",
        rate: "Tasso di assenza",
        ofLessons: { m, t in "\(m) su \(t) di lezione finora" },
        perMonth: "Per mese",
        emptyTitle: "Nessuna assenza",
        emptySubtitle: "In questo anno scolastico non hai assenze.",
        statusExcused: "giustificata",
        statusOpen: "aperta",
        reason: "Motivo",
        text: "Testo",
        viewInTimetable: "Vedi nell’orario",
        timetableShort: "Orario",
        report: "Segnala assenza",
        reportTitle: "Segnala assenza",
        reported: "Assenza segnalata.",
        from: "Dalle",
        until: "Alle",
        time: "Ora",
        apply: "Applica",
        textPlaceholder: "Facoltativo, es. visita medica",
        reportAction: "Segnala",
        errChooseRange: "Scegli inizio e fine.",
        errEndAfterStart: "La fine deve essere dopo l’inizio.",
        errChooseReason: "Scegli un motivo.",
        choose: "Scegli",
        selected: "Selezionato",
        reasonsFailed: "Al momento non è stato possibile caricare i motivi. Riprova più tardi.",
        reasonsLoading: "Caricamento dei motivi …",
        noReasons: "WebUntis non offre motivi.",
        letter: "Lettera di giustificazione",
        letterHint: "PDF di WebUntis per le assenze aperte",
        letterFailed: "Impossibile caricare la lettera di giustificazione.",
        exAction: "Giustifica",
        exTitle: "Giustifica l’assenza",
        exLead: "I tuoi coordinatori di classe ricevono un messaggio con motivo e nota.",
        exAbsence: "Assenza",
        exTo: "A",
        exToSchool: "La tua scuola tramite WebUntis",
        exNote: "Nota (facoltativa)",
        exSave: "Invia ai coordinatori",
        exSaving: "Invio …",
        exDone: "Messaggio inviato.",
        exSavedInUntis: "Salvato in WebUntis.",
        exDoneTo: { "A \($0)" },
        exPartial: { "Non è stato possibile inviarlo a \($0)." },
        exNoTeacher: "In WebUntis non è indicato nessun coordinatore per la tua classe.",
        exForbidden: "Il tuo account WebUntis non può inviare messaggi ai docenti.",
        exAlready: "Questa assenza è già giustificata.",
        exSendFailed: "Non è stato possibile inviare il messaggio. Riprova più tardi.",
        exNotAllowed: "Il tuo account WebUntis non può giustificare le assenze.",
        exSent: "Messaggio inviato",
        exSentTo: { n, d in "A \(n) · \(d)" },
        exSentLabel: { n, d in "Messaggio inviato a \(n) il \(d). Aperta finché la scuola non la giustifica." },
        calc: "Calcolatore assenze",
        calcAbsent: "Ore di assenza",
        calcModeTotal: "Totale",
        calcModeWeekly: "Per settimana",
        calcTotal: "Monte ore annuale",
        calcWeekly: "Ore a settimana",
        calcWeeks: "Settimane di scuola",
        calcLimit: "Limite in percentuale",
        calcLeft: { "Prima del limite puoi ancora perdere \($0) ore." },
        calcAtLimit: "Hai raggiunto esattamente il limite.",
        calcOver: { "Sei \($0) ore oltre il limite. Parla con la scuola delle deroghe." },
        calcEmpty: "Inserisci le ore di assenza e il monte ore annuale.",
        calcInvalid: "Le ore di assenza non possono superare il monte ore.",
        ofLessonsYear: { m, t in "\(m) su \(t) di lezione in tutto l’anno scolastico" },
        spanLabel: "Periodo",
        spanSoFar: "Finora",
        spanYear: "Tutto l’anno",
        rateCounting: "Calcolo dall’orario in corso …",
        rateMissing: "Non tutte le settimane dell’orario sono state caricate.",
        rateRetry: "Ricarica",
        forLabel: "Per",
        me: "Io",
        fromTimetable: "Scegli dall’orario",
        chooseLessons: "Seleziona le ore",
        prevDay: "Giorno precedente",
        nextDay: "Giorno successivo",
        takeLessons: { ($0 == 1) ? "Usa 1 ora" : "Usa \($0) ore" },
        cancelledSuffix: " (annullata)",
        noLessonsDay: "Nessuna lezione in questo giorno.",
        notAvailable: "non disponibile",
        exPick: "Scegli un motivo.",
    )
}

extension AbsencesStrings {
    static let en = AbsencesStrings(
        title: "Absences",
        exact: "Exact",
        rounded: "Rounded",
        totalMissed: "Total missed hours",
        excused: "Excused",
        unexcused: "Unexcused",
        rate: "Absence rate",
        ofLessons: { m, t in "\(m) of \(t) of lessons so far" },
        perMonth: "Per month",
        emptyTitle: "No absences",
        emptySubtitle: "You have no absences in this school year.",
        statusExcused: "excused",
        statusOpen: "open",
        reason: "Reason",
        text: "Note",
        viewInTimetable: "View in timetable",
        timetableShort: "Timetable",
        report: "Report absence",
        reportTitle: "Report absence",
        reported: "Absence reported.",
        from: "From",
        until: "Until",
        time: "Time",
        apply: "Apply",
        textPlaceholder: "Optional, e.g. doctor's appointment",
        reportAction: "Report",
        errChooseRange: "Please choose a start and an end.",
        errEndAfterStart: "The end must be after the start.",
        errChooseReason: "Please choose a reason.",
        choose: "Choose",
        selected: "Selected",
        reasonsFailed: "The reasons couldn't be loaded right now. Please try again later.",
        reasonsLoading: "Loading reasons …",
        noReasons: "WebUntis offers no reasons.",
        letter: "Excuse letter",
        letterHint: "PDF from WebUntis for your open absences",
        letterFailed: "The excuse letter couldn't be loaded.",
        exAction: "Excuse",
        exTitle: "Excuse the absence",
        exLead: "Your class teachers get a message with the reason and note.",
        exAbsence: "Absence",
        exTo: "To",
        exToSchool: "Your school via WebUntis",
        exNote: "Note (optional)",
        exSave: "Send to class teachers",
        exSaving: "Sending …",
        exDone: "Message sent.",
        exSavedInUntis: "Saved in WebUntis.",
        exDoneTo: { "To \($0)" },
        exPartial: { "It could not be sent to \($0)." },
        exNoTeacher: "WebUntis lists no class teacher for your class.",
        exForbidden: "Your WebUntis account may not message teachers.",
        exAlready: "This absence is already excused.",
        exSendFailed: "The message could not be sent. Please try again later.",
        exNotAllowed: "Your WebUntis account may not excuse absences.",
        exSent: "Message sent",
        exSentTo: { n, d in "To \(n) · \(d)" },
        exSentLabel: { n, d in "Message sent to \(n) on \(d). Open until the school excuses it." },
        calc: "Absence calculator",
        calcAbsent: "Hours missed",
        calcModeTotal: "Total",
        calcModeWeekly: "Per week",
        calcTotal: "Hours in the school year",
        calcWeekly: "Hours per week",
        calcWeeks: "School weeks",
        calcLimit: "Limit in percent",
        calcLeft: { "You can miss \($0) more hours before the limit." },
        calcAtLimit: "You are exactly at the limit.",
        calcOver: { "You are \($0) hours over the limit. Ask your school about exceptions." },
        calcEmpty: "Enter your hours missed and the hours of the school year.",
        calcInvalid: "Hours missed cannot be more than all hours.",
        ofLessonsYear: { m, t in "\(m) of \(t) of lessons in the whole school year" },
        spanLabel: "Period",
        spanSoFar: "So far",
        spanYear: "Whole year",
        rateCounting: "Working it out from the timetable …",
        rateMissing: "Not every week of the timetable has loaded yet.",
        rateRetry: "Load again",
        forLabel: "For",
        me: "Me",
        fromTimetable: "Pick from timetable",
        chooseLessons: "Select lessons",
        prevDay: "Previous day",
        nextDay: "Next day",
        takeLessons: { ($0 == 1) ? "Use 1 lesson" : "Use \($0) lessons" },
        cancelledSuffix: " (cancelled)",
        noLessonsDay: "No lessons on this day.",
        notAvailable: "not available",
        exPick: "Please choose a reason.",
    )
}
