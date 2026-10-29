// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct GradesStrings: Sendable {
    public let tab: String
    public let schoolYearTitle: @Sendable (Int) -> String
    public let sortName: String
    public let sortBest: String
    public let sortWorst: String
    public let sortRecent: String
    public let summary: @Sendable (String, Int, Int) -> String
    public let noGradesYear: String
    public let emptyTitle: String
    public let emptySubtitle: String
    public let noSubjects: String
    public let avgTitle: String
    public let avgSub: String
    public let prevMonth: String
    public let bestGrade: String
    public let ratioTitle: String
    public let ratioSub: String
    public let above6: String
    public let below6: String
    public let distTitle: String
    public let distSub: String
    public let distTimes: @Sendable (Int) -> String
    public let distHint: String
    public let mode: String
    public let median: String
    public let recentTitle: String
    public let recentSub: @Sendable (Int) -> String
    public let recentEmpty: String
    public let subjects: String
    public let collapseAll: String
    public let expandAll: String
    public let collapse: String
    public let expand: String
    public let gradeCount: @Sendable (Int) -> String
    public let noSingleGrades: String
    public let openDetails: String
    public let exam: String
    public let subject: String
    public let subjectNotFound: String
    public let resetCalc: String
    public let average: String
    public let averageWithCalc: String
    public let grades: String
    public let ownGrade: String
    public let gradeCalc: String
    public let gradePlaceholder: String
    public let add: String
    public let removeOwnGrade: String
    public let restoreGrade: String
    public let excludeGrade: String
    public let targetGrade: String
    public let targetPlaceholder: String
    public let invalidGrade: String
    public let targetReached: @Sendable (String) -> String
    public let targetImpossible: @Sendable (String) -> String
    public let targetNeed: @Sendable (Int, Bool, String, String) -> String
    public let trend: String
    public let trendGrades: String
    public let trendLabel: @Sendable (String) -> String
    public let gradeN: @Sendable (Int) -> String
    public let noGradesYet: String
    public let positiveCount: @Sendable (Int) -> String
    public let negativeCount: @Sendable (Int) -> String
    public let relToday: String
    public let relYesterday: String
    public let daysAgo: @Sendable (Int) -> String
    public let weeksAgo: @Sendable (Int) -> String
    public let monthsAgo: @Sendable (Int) -> String
    public let yearsAgo: @Sendable (Int) -> String
    public let trendTitle: String
    public let reset: String
    public let trendSub: String
    public let rising: String
    public let falling: String
    public let stable: String
    public let simulation: String
    public let teacherAvg: String
    public let best: @Sendable (String) -> String
    public let lastGrade: String
    public let whatDoINeed: String
    public let targetCalc: String
    public let targetShort: String
    public let hintEnter: String
    public let hintReached: String
    public let hintImpossible: String
    public let hintNext: String
    public let hintMany: @Sendable (Int, String) -> String
    public let gradeList: String
    public let activeExcluded: @Sendable (Int, Int) -> String
    public let avgCalc: String
    public let avgCalcSub: String
    public let examplePlaceholder: String
    public let noOwnGrades: String
    public let allSubjects: String
}


extension GradesStrings {
    static let de = GradesStrings(
        tab: "Noten",
        schoolYearTitle: { "Schuljahr \($0) / \($0 + 1)" },
        sortName: "Name",
        sortBest: "Schnitt ↓",
        sortWorst: "Schnitt ↑",
        sortRecent: "Letzte Note",
        summary: { d, s, g in "Stand \(d) · \(s) Fächer · \(g) Noten" },
        noGradesYear: "Noch keine Noten in diesem Schuljahr",
        emptyTitle: "Keine Noten",
        emptySubtitle: "Für dieses Schuljahr wurden keine Noten gefunden.",
        noSubjects: "WebUntis hat für dieses Schuljahr keine Fächer gemeldet.",
        avgTitle: "Durchschnittsnote",
        avgSub: "Alle Fächer · gewichtet",
        prevMonth: "Vormonat",
        bestGrade: "Beste Note",
        ratioTitle: "Notenverhältnis",
        ratioSub: "Genügend · Ungenügend",
        above6: "über 6.0",
        below6: "unter 6.0",
        distTitle: "Notenverteilung",
        distSub: "Häufigkeit pro Note",
        distTimes: { "\($0)×" },
        distHint: "Tippe auf eine Note",
        mode: "Modus",
        median: "Median",
        recentTitle: "Kürzlich hinzugefügt",
        recentSub: { "Letzte \($0) Einträge" },
        recentEmpty: "Noch keine Noten erfasst.",
        subjects: "Fächer",
        collapseAll: "Einklappen",
        expandAll: "Alle",
        collapse: "Einklappen",
        expand: "Aufklappen",
        gradeCount: { ($0 == 1) ? "1 Note" : "\($0) Noten" },
        noSingleGrades: "Keine Einzelnoten vorhanden.",
        openDetails: "Details öffnen",
        exam: "Prüfung",
        subject: "Fach",
        subjectNotFound: "Fach nicht gefunden",
        resetCalc: "Rechner zurücksetzen",
        average: "Schnitt",
        averageWithCalc: "Schnitt · mit Rechner",
        grades: "Noten",
        ownGrade: "Eigene Note",
        gradeCalc: "Notenrechner",
        gradePlaceholder: "Note (1–10)",
        add: "Hinzufügen",
        removeOwnGrade: "Eigene Note entfernen",
        restoreGrade: "Note wieder einrechnen",
        excludeGrade: "Note aus dem Rechner nehmen",
        targetGrade: "Zielnote",
        targetPlaceholder: "Zielnote (z. B. 7)",
        invalidGrade: "Gib eine gültige Note (1–10) ein.",
        targetReached: { "Du hast die Zielnote \($0) bereits erreicht." },
        targetImpossible: { "Die Zielnote \($0) ist nicht erreichbar." },
        targetNeed: { n, atLeast, needed, target in "Du brauchst \(n) \((n == 1) ? "Note" : "Noten") mit \((atLeast) ? "mindestens" : "höchstens") \(needed), um \(target) zu erreichen." },
        trend: "Notenverlauf",
        trendGrades: "Noten",
        trendLabel: { "Trend \($0)" },
        gradeN: { "Note \($0)" },
        noGradesYet: "Noch keine Noten",
        positiveCount: { "\($0) positiv" },
        negativeCount: { "\($0) negativ" },
        relToday: "heute",
        relYesterday: "gestern",
        daysAgo: { n in "vor \(n) Tagen" },
        weeksAgo: { n in "vor \(n) Wochen" },
        monthsAgo: { n in "vor \(n) Monaten" },
        yearsAgo: { n in "vor \(n) Jahren" },
        trendTitle: "Notentrend",
        reset: "Zurücksetzen",
        trendSub: "Verlauf vom Schuljahresbeginn bis heute",
        rising: "steigend",
        falling: "fallend",
        stable: "stabil",
        simulation: "Simulation",
        teacherAvg: "Lehrer-Schnitt",
        best: { g in "Beste \(g)" },
        lastGrade: "Letzte Note",
        whatDoINeed: "Was brauche ich?",
        targetCalc: "Zielnote-Rechner",
        targetShort: "Ziel",
        hintEnter: "Trage einen Zielschnitt ein",
        hintReached: "Ziel ist mit dem aktuellen Schnitt schon erreicht",
        hintImpossible: "Ziel ist mit weiteren Noten nicht mehr erreichbar",
        hintNext: "Nächste Note für dein Ziel",
        hintMany: { n, grade in "\(n)× \(grade), um den Schnitt zu erreichen" },
        gradeList: "Noten-Liste",
        activeExcluded: { active, excluded in "\(active) aktiv · \(excluded) ausgeschlossen" },
        avgCalc: "Mittelwert-Rechner",
        avgCalcSub: "Eigene Noten zum Spielen",
        examplePlaceholder: "z.B. 7,5",
        noOwnGrades: "Noch keine eigenen Noten",
        allSubjects: "Alle Fächer →",
    )
}

extension GradesStrings {
    static let it = GradesStrings(
        tab: "Voti",
        schoolYearTitle: { "Anno scolastico \($0) / \($0 + 1)" },
        sortName: "Nome",
        sortBest: "Media ↓",
        sortWorst: "Media ↑",
        sortRecent: "Ultimo voto",
        summary: { d, s, g in "Aggiornato al \(d) · \(s) materie · \(g) voti" },
        noGradesYear: "Ancora nessun voto in questo anno scolastico",
        emptyTitle: "Nessun voto",
        emptySubtitle: "Per questo anno scolastico non sono stati trovati voti.",
        noSubjects: "WebUntis non ha indicato materie per questo anno scolastico.",
        avgTitle: "Media dei voti",
        avgSub: "Tutte le materie · ponderata",
        prevMonth: "Mese precedente",
        bestGrade: "Voto migliore",
        ratioTitle: "Rapporto voti",
        ratioSub: "Sufficiente · Insufficiente",
        above6: "sopra 6.0",
        below6: "sotto 6.0",
        distTitle: "Distribuzione voti",
        distSub: "Frequenza per voto",
        distTimes: { "\($0)×" },
        distHint: "Tocca un voto",
        mode: "Moda",
        median: "Mediana",
        recentTitle: "Aggiunti di recente",
        recentSub: { "Ultimi \($0) inserimenti" },
        recentEmpty: "Ancora nessun voto registrato.",
        subjects: "Materie",
        collapseAll: "Comprimi",
        expandAll: "Tutte",
        collapse: "Comprimi",
        expand: "Espandi",
        gradeCount: { ($0 == 1) ? "1 voto" : "\($0) voti" },
        noSingleGrades: "Nessun voto singolo disponibile.",
        openDetails: "Apri dettagli",
        exam: "Verifica",
        subject: "Materia",
        subjectNotFound: "Materia non trovata",
        resetCalc: "Ripristina il calcolatore",
        average: "Media",
        averageWithCalc: "Media · con calcolatore",
        grades: "Voti",
        ownGrade: "Voto personale",
        gradeCalc: "Calcolatore voti",
        gradePlaceholder: "Voto (1–10)",
        add: "Aggiungi",
        removeOwnGrade: "Rimuovi voto personale",
        restoreGrade: "Ricalcola il voto",
        excludeGrade: "Togli il voto dal calcolo",
        targetGrade: "Voto obiettivo",
        targetPlaceholder: "Voto obiettivo (es. 7)",
        invalidGrade: "Inserisci un voto valido (1–10).",
        targetReached: { "Hai già raggiunto il voto obiettivo \($0)." },
        targetImpossible: { "Il voto obiettivo \($0) non è raggiungibile." },
        targetNeed: { n, atLeast, needed, target in "Ti servono \(n) \((n == 1) ? "voto" : "voti") di \((atLeast) ? "almeno" : "al massimo") \(needed) per raggiungere \(target)." },
        trend: "Andamento dei voti",
        trendGrades: "Voti",
        trendLabel: { "Tendenza \($0)" },
        gradeN: { "Voto \($0)" },
        noGradesYet: "Ancora nessun voto",
        positiveCount: { "\($0) positivi" },
        negativeCount: { "\($0) negativi" },
        relToday: "oggi",
        relYesterday: "ieri",
        daysAgo: { n in "\(n) giorni fa" },
        weeksAgo: { n in "\(n) settimane fa" },
        monthsAgo: { n in "\(n) mesi fa" },
        yearsAgo: { n in "\(n) anni fa" },
        trendTitle: "Andamento dei voti",
        reset: "Ripristina",
        trendSub: "Dall’inizio dell’anno scolastico a oggi",
        rising: "in crescita",
        falling: "in calo",
        stable: "stabile",
        simulation: "Simulazione",
        teacherAvg: "Media del docente",
        best: { g in "Migliore \(g)" },
        lastGrade: "Ultimo voto",
        whatDoINeed: "Di cosa ho bisogno?",
        targetCalc: "Calcolatore voto obiettivo",
        targetShort: "Obiettivo",
        hintEnter: "Inserisci una media obiettivo",
        hintReached: "L’obiettivo è già raggiunto con la media attuale",
        hintImpossible: "L’obiettivo non è più raggiungibile con altri voti",
        hintNext: "Prossimo voto per il tuo obiettivo",
        hintMany: { n, grade in "\(n)× \(grade) per raggiungere la media" },
        gradeList: "Elenco voti",
        activeExcluded: { active, excluded in "\(active) attivi · \(excluded) esclusi" },
        avgCalc: "Calcolatore media",
        avgCalcSub: "Voti personali per simulare",
        examplePlaceholder: "es. 7,5",
        noOwnGrades: "Ancora nessun voto personale",
        allSubjects: "Tutte le materie →",
    )
}

extension GradesStrings {
    static let en = GradesStrings(
        tab: "Grades",
        schoolYearTitle: { "School year \($0) / \($0 + 1)" },
        sortName: "Name",
        sortBest: "Average ↓",
        sortWorst: "Average ↑",
        sortRecent: "Latest grade",
        summary: { d, s, g in "As of \(d) · \(s) subjects · \(g) grades" },
        noGradesYear: "No grades in this school year yet",
        emptyTitle: "No grades",
        emptySubtitle: "No grades were found for this school year.",
        noSubjects: "WebUntis reported no subjects for this school year.",
        avgTitle: "Grade average",
        avgSub: "All subjects · weighted",
        prevMonth: "Last month",
        bestGrade: "Best grade",
        ratioTitle: "Pass ratio",
        ratioSub: "Pass · Fail",
        above6: "above 6.0",
        below6: "below 6.0",
        distTitle: "Grade distribution",
        distSub: "Frequency per grade",
        distTimes: { "\($0)×" },
        distHint: "Tap a grade",
        mode: "Mode",
        median: "Median",
        recentTitle: "Recently added",
        recentSub: { "Last \($0) entries" },
        recentEmpty: "No grades recorded yet.",
        subjects: "Subjects",
        collapseAll: "Collapse",
        expandAll: "All",
        collapse: "Collapse",
        expand: "Expand",
        gradeCount: { ($0 == 1) ? "1 grade" : "\($0) grades" },
        noSingleGrades: "No individual grades available.",
        openDetails: "Open details",
        exam: "Exam",
        subject: "Subject",
        subjectNotFound: "Subject not found",
        resetCalc: "Reset calculator",
        average: "Average",
        averageWithCalc: "Average · with calculator",
        grades: "Grades",
        ownGrade: "Own grade",
        gradeCalc: "Grade calculator",
        gradePlaceholder: "Grade (1–10)",
        add: "Add",
        removeOwnGrade: "Remove own grade",
        restoreGrade: "Count the grade again",
        excludeGrade: "Leave the grade out",
        targetGrade: "Target grade",
        targetPlaceholder: "Target grade (e.g. 7)",
        invalidGrade: "Enter a valid grade (1–10).",
        targetReached: { "You have already reached the target grade \($0)." },
        targetImpossible: { "The target grade \($0) can't be reached." },
        targetNeed: { n, atLeast, needed, target in "You need \(n) \((n == 1) ? "grade" : "grades") of \((atLeast) ? "at least" : "at most") \(needed) to reach \(target)." },
        trend: "Grade trend",
        trendGrades: "Grades",
        trendLabel: { "Trend \($0)" },
        gradeN: { "Grade \($0)" },
        noGradesYet: "No grades yet",
        positiveCount: { "\($0) pass" },
        negativeCount: { "\($0) fail" },
        relToday: "today",
        relYesterday: "yesterday",
        daysAgo: { n in "\(n) days ago" },
        weeksAgo: { n in "\(n) weeks ago" },
        monthsAgo: { n in "\(n) months ago" },
        yearsAgo: { n in "\(n) years ago" },
        trendTitle: "Grade trend",
        reset: "Reset",
        trendSub: "From the start of the school year until today",
        rising: "rising",
        falling: "falling",
        stable: "stable",
        simulation: "Simulation",
        teacherAvg: "Teacher average",
        best: { g in "Best \(g)" },
        lastGrade: "Latest grade",
        whatDoINeed: "What do I need?",
        targetCalc: "Target grade calculator",
        targetShort: "Target",
        hintEnter: "Enter a target average",
        hintReached: "The target is already reached with your current average",
        hintImpossible: "The target can no longer be reached with more grades",
        hintNext: "Next grade for your target",
        hintMany: { n, grade in "\(n)× \(grade) to reach the average" },
        gradeList: "Grade list",
        activeExcluded: { active, excluded in "\(active) active · \(excluded) excluded" },
        avgCalc: "Average calculator",
        avgCalcSub: "Your own grades to play with",
        examplePlaceholder: "e.g. 7.5",
        noOwnGrades: "No own grades yet",
        allSubjects: "All subjects →",
    )
}
