import SwiftUI
import PokyhCore
import PokyhDesign

// ── What a result is ────────────────────────────────────────────────────────

/// Where a search result leads.
nonisolated enum SearchTarget: Hashable, Sendable {
    case tab(AppTab)
    case page(SearchRoute)
    case profile
    case lesson(day: Int)
    case theme
}

/// Pages a result opens inside the search.
nonisolated enum SearchRoute: Hashable, Sendable {
    case messages, absences, classreg, klasse, todos, reminders, settings
    case grade(lessonId: Int)
    case message(Int)
    case reminder(String)
}

/// The sections, in the order they show. A fixed order, so they don't swap places while typing.
nonisolated enum SearchKind: Int, CaseIterable, Hashable, Sendable {
    case page, subject, grade, lesson, message, homework, duty, classreg, todo, reminder, dish

    /// What a content row is called, matched too: "note" finds every grade.
    func label(_ t: SearchStrings) -> String {
        switch self {
        case .page: t.pages
        case .subject: t.srcSubject
        case .grade: t.srcGrade
        case .lesson: t.srcLesson
        case .message: t.srcMessage
        case .homework: t.srcHomework
        case .duty: t.srcClassService
        case .classreg: t.srcClassreg
        case .todo: t.srcTodo
        case .reminder: t.srcReminder
        case .dish: t.srcDish
        }
    }

    func section(_ t: SearchStrings) -> String {
        switch self {
        case .page: t.pages
        case .subject: t.subjects
        case .grade: t.grades
        case .lesson: t.srcLesson
        case .message: t.messages
        case .homework: t.homework
        case .duty: t.duties
        case .classreg: t.srcClassreg
        case .todo: t.todos
        case .reminder: t.reminders
        case .dish: t.srcDish
        }
    }

    var symbol: String {
        switch self {
        case .page: "square.grid.2x2"
        case .classreg: "book.closed.fill"
        case .reminder: "bell.fill"
        case .todo: "checklist"
        case .subject, .grade: "chart.bar.fill"
        case .lesson: "calendar"
        case .message: "envelope.fill"
        case .homework, .duty: "person.3.fill"
        case .dish: "fork.knife"
        }
    }

    var tone: SearchTone {
        switch self {
        case .todo, .homework, .duty: .sage
        case .classreg, .dish: .butter
        case .reminder: .blush
        default: .periwinkle
        }
    }

    /// Rows a section shows before "Alle anzeigen".
    var cap: Int { self == .page ? 6 : 4 }
}

nonisolated enum SearchTone: Hashable, Sendable {
    case periwinkle, butter, sage, blush

    var tone: Tone {
        switch self {
        case .periwinkle: Decorative.periwinkle
        case .butter: Decorative.butter
        case .sage: Decorative.sage
        case .blush: Decorative.blush
        }
    }
}

nonisolated struct SearchEntry: Identifiable, Equatable, Sendable {
    let id: String
    let kind: SearchKind
    let title: String
    let subtitle: String
    let symbol: String
    let tone: SearchTone?
    let target: SearchTarget
    // Folded once when the index is built, so a keystroke only compares.
    let foldedTitle: String
    let foldedRest: String

    init(id: String, kind: SearchKind, title: String, subtitle: String = "", keywords: String = "",
         symbol: String? = nil, tone: SearchTone?? = nil, target: SearchTarget, label: String = "") {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol ?? kind.symbol
        self.tone = tone ?? kind.tone
        self.target = target
        foldedTitle = SearchScore.fold(title)
        foldedRest = SearchScore.fold([subtitle, keywords, label].joined(separator: " "))
    }
}

nonisolated struct SearchSection: Identifiable, Equatable, Sendable {
    let kind: SearchKind
    let entries: [SearchEntry]
    var id: SearchKind { kind }
}

nonisolated enum SearchScore {
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The web's scoring: the title's start counts most, then a word in it, then anywhere in it,
    /// then the rest. Every word has to match somewhere.
    static func score(_ e: SearchEntry, _ words: [String]) -> Int {
        var total = 0
        for w in words {
            if e.foldedTitle.hasPrefix(w) { total += 4 }
            else if e.foldedTitle.contains(" \(w)") || e.foldedTitle.contains("-\(w)") { total += 3 }
            else if e.foldedTitle.contains(w) { total += 2 }
            else if e.foldedRest.contains(w) { total += 1 }
            else { return 0 }
        }
        return total
    }

    /// Off the main thread: a big index never holds up the keyboard.
    @concurrent
    static func sections(_ words: [String], in entries: [SearchEntry]) async -> [SearchSection] {
        var byKind: [SearchKind: [(SearchEntry, Int)]] = [:]
        for (i, e) in entries.enumerated() {
            if i % 256 == 0, Task.isCancelled { return [] }
            let s = score(e, words)
            if s > 0 { byKind[e.kind, default: []].append((e, s)) }
        }
        return SearchKind.allCases.compactMap { kind in
            guard let hits = byKind[kind] else { return nil }
            // Stable: equal scores keep the order the sources gave.
            let sorted = hits.enumerated().sorted { a, b in
                a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset
            }
            return SearchSection(kind: kind, entries: sorted.map(\.element.0))
        }
    }
}

// ── The index ───────────────────────────────────────────────────────────────

/// One per signed-in account (RootTabView is built again for each), shared by the search tab
/// and the sheet, so opening the search again finds everything at once and nothing reshuffles.
@Observable
final class SearchModel {
    var query = "" {
        didSet { if query != oldValue { refilter() } }
    }
    /// The words the shown sections were found for; they lag a keystroke behind at most.
    private(set) var resultWords: [String] = []
    private(set) var sections: [SearchSection] = []
    private(set) var revision = 0
    private(set) var isLoading = false

    // What the pages opened from a result need.
    private(set) var subjects: [SubjectGrades] = []
    private(set) var inbox: [MessagePreview] = []
    private(set) var reminders: [ApiReminder] = []
    private(set) var classId: String?

    @ObservationIgnored private var pages: [SearchEntry] = []
    @ObservationIgnored private var content: [SearchKind: [SearchEntry]] = [:]
    @ObservationIgnored private var all: [SearchEntry] = []
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var filtering: Task<Void, Never>?

    var words: [String] { SearchScore.words(query) }

    /// Shown sections belong to what's in the field.
    var isCurrent: Bool { resultWords == words }

    func setPages(_ list: [SearchEntry]) {
        guard list != pages else { return }
        pages = list
        rebuildAll()
    }

    func markRead(_ id: Int) {
        if let i = inbox.firstIndex(where: { $0.id == id }) { inbox[i].isRead = true }
    }

    private func rebuildAll() {
        all = pages + SearchKind.allCases.flatMap { content[$0] ?? [] }
        refilter()
    }

    private func refilter() {
        filtering?.cancel()
        let words = words
        guard !words.isEmpty else {
            filtering = nil
            show(pages.isEmpty ? [] : [SearchSection(kind: .page, entries: pages)], for: [])
            return
        }
        let entries = all
        filtering = Task {
            let found = await SearchScore.sections(words, in: entries)
            guard !Task.isCancelled else { return }
            show(found, for: words)
        }
    }

    private func show(_ found: [SearchSection], for words: [String]) {
        guard found != sections || words != resultWords else { return }
        sections = found
        resultWords = words
        revision &+= 1
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    /// Takes what the app loads anyway. A source that fails keeps what it found before; once
    /// everything came in, the next look waits a while.
    func prepare(_ session: UserSession, _ s: Strings, app: AppState) {
        // Same name at another school, or another child: still someone else's index.
        let owner = "\(session.schoolRef.loginName)/\(session.username)/\(session.studentId)|\(s.lang)"
        if self.owner != owner {
            loading?.cancel()
            loading = nil
            content = [:]
            subjects = []
            inbox = []
            reminders = []
            classId = nil
            loadedAt = nil
            self.owner = owner
            rebuildAll()
        }
        guard loading == nil else { return }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 120 { return }
        isLoading = content.isEmpty
        loading = Task { [weak self] in
            guard let self else { return }
            let complete = await load(session, SearchDays(s), app: app)
            guard self.owner == owner else { return }
            loadedAt = complete ? Date() : nil
            isLoading = false
            loading = nil
        }
    }

    private func store(_ kind: SearchKind, _ entries: [SearchEntry]?, owner: String) -> Bool {
        guard let entries else { return false }
        guard self.owner == owner, !Task.isCancelled else { return true }
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.id).inserted }
        guard content[kind] != unique else { return true }
        content[kind] = unique
        rebuildAll()
        return true
    }

    /// Each source on its own, so a slow one holds nothing up. True when all of them answered.
    private func load(_ session: UserSession, _ days: SearchDays, app: AppState) async -> Bool {
        guard let owner else { return false }
        let t = Strings.of(days.lang).search
        async let grades = loadGrades(session, days, t, owner)
        async let lessons = loadLessons(session, days, t, owner)
        async let messages = loadMessages(session, t, owner, app)
        async let classreg = loadClassreg(session, days, t, owner)
        async let classroom = loadClassroom(session, days, t, owner)
        async let tasks = loadTasks(session, t, owner)
        async let mensa = loadMensa(days, t, owner)
        let done = await [grades, lessons, messages, classreg, classroom, tasks, mensa]
        return !done.contains(false)
    }

    private func loadGrades(_ session: UserSession, _ days: SearchDays, _ t: SearchStrings, _ owner: String) async -> Bool {
        guard session.hasUntis else { return true }
        let list = try? await UntisClient.shared.grades(year: nil, session)
        if let list, self.owner == owner { subjects = list }
        return store(.grade, list.map { list in
            list.flatMap { sub -> [SearchEntry] in
                let target = SearchTarget.page(.grade(lessonId: sub.lessonId))
                let subject = SearchEntry(id: "subject:\(sub.lessonId)", kind: .subject, title: sub.subjectName, subtitle: sub.teacherName,
                                          target: target, label: t.srcSubject)
                return [subject] + sub.grades.filter { $0.markDisplayValue > 0 }.map { g in
                    SearchEntry(
                        id: "grade:\(sub.lessonId)-\(g.id)", kind: .grade,
                        title: "\(g.markName.isEmpty ? Fmt.num(g.markDisplayValue) : g.markName) · \(sub.subjectName)",
                        subtitle: [g.examType, g.text, days.short(g.date)].filter { !$0.isEmpty }.joined(separator: " · "),
                        target: target, label: t.srcGrade
                    )
                }
            }
        }, owner: owner)
    }

    private func loadLessons(_ session: UserSession, _ days: SearchDays, _ t: SearchStrings, _ owner: String) async -> Bool {
        guard session.hasUntis else { return true }
        let list = try? await UntisClient.shared.timetable(date: SchoolDates.mondayISO(of: Date()), session)
        return store(.lesson, list.map { list in
            var seen = Set<String>()
            return list.filter { !$0.isCancelled && seen.insert("\($0.date)-\($0.startTime)").inserted }.map { e in
                SearchEntry(
                    id: "lesson:\(e.date)-\(e.startTime)", kind: .lesson,
                    title: e.subjectLong.isEmpty ? (e.subjectName.isEmpty ? (e.note ?? "–") : e.subjectName) : e.subjectLong,
                    subtitle: ["\(days.weekday(e.date)) \(Fmt.time(e.startTime))", e.roomName, e.teacherLongName ?? e.teacherName]
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " · "),
                    keywords: "\(e.subjectName) \(e.teacherName) \(e.note ?? "")",
                    target: .lesson(day: e.date), label: t.srcLesson
                )
            }
        }, owner: owner)
    }

    private func loadMessages(_ session: UserSession, _ t: SearchStrings, _ owner: String, _ app: AppState) async -> Bool {
        guard session.hasUntis else { return true }
        let list = try? await UntisClient.shared.messages(folder: .inbox, session)
        if let list, self.owner == owner {
            inbox = list
            // Only for the account it was asked for; a switch in between would count the wrong inbox.
            if app.session?.username == session.username { app.noteInbox(list) }
        }
        return store(.message, list.map { list in
            list.map { m in
                SearchEntry(id: "msg:\(m.id)", kind: .message, title: m.subject.isEmpty ? "–" : m.subject, subtitle: m.senderName,
                            keywords: Self.plain(m.contentPreview), target: .page(.message(m.id)), label: t.srcMessage)
            }
        }, owner: owner)
    }

    private func loadClassreg(_ session: UserSession, _ days: SearchDays, _ t: SearchStrings, _ owner: String) async -> Bool {
        guard session.hasUntis else { return true }
        let list = try? await UntisClient.shared.classregEvents(year: nil, session)
        return store(.classreg, list.map { list in
            list.map { e in
                SearchEntry(
                    id: "event:\(e.id)", kind: .classreg, title: [e.text, e.categoryName, e.eventReasonName].first { !$0.isEmpty } ?? "–",
                    subtitle: [e.categoryName, e.subjectName, days.short(e.createDate)].filter { !$0.isEmpty }.joined(separator: " · "),
                    keywords: "\(e.eventReasonName) \(e.creatorName)",
                    target: .page(.classreg), label: t.srcClassreg
                )
            }
        }, owner: owner)
    }

    /// Class duties and the homework of this and next week, both on the class page.
    private func loadClassroom(_ session: UserSession, _ days: SearchDays, _ t: SearchStrings, _ owner: String) async -> Bool {
        guard session.hasUntis else { return true }
        let start = DateFmt.iso.date(from: SchoolDates.mondayISO(of: Date())) ?? Date()
        // To Friday of next week, as Android.
        let end = Calendar.current.date(byAdding: .day, value: 11, to: start) ?? start
        async let duties = try? UntisClient.shared.classServices(session)
        async let homework = try? UntisClient.shared.homeworks(from: DateFmt.num(start), to: DateFmt.num(end), session)
        let (dutyList, homeworkList) = await (duties, homework)
        let a = store(.duty, dutyList.map { list in
            list.map { c in
                SearchEntry(id: "duty:\(c.id)-\(c.personName)", kind: .duty, title: c.duty.isEmpty ? "–" : c.duty, subtitle: c.personName,
                            target: .page(.klasse), label: t.srcClassService)
            }
        }, owner: owner)
        let b = store(.homework, homeworkList.map { list in
            list.compactMap { h in
                let text = Self.plain(h.text)
                guard !text.isEmpty else { return nil }
                return SearchEntry(id: "hw:\(h.id)", kind: .homework, title: text,
                                   subtitle: [h.subject, days.short(h.dueDate)].filter { !$0.isEmpty }.joined(separator: " · "),
                                   target: .page(.klasse), label: t.srcHomework)
            }
        }, owner: owner)
        return a && b
    }

    private func loadTasks(_ session: UserSession, _ t: SearchStrings, _ owner: String) async -> Bool {
        guard let token = session.apiToken else { return true }
        let todos = try? await BackendClient.shared.todos(username: session.username, token: token)
        let a = store(.todo, todos.map { list in
            list.map { SearchEntry(id: "todo:\($0.id)", kind: .todo, title: $0.title, keywords: $0.details, target: .page(.todos), label: t.srcTodo) }
        }, owner: owner)
        // Parents see the class but not its reminders, as in the hub.
        guard !session.isParent else { return a }
        var id = session.classId
        if id == nil { id = try? await BackendClient.shared.myClass(token: token)?.id }
        guard let id else { return a }
        let list = try? await BackendClient.shared.reminders(classId: id, token: token)
        if let list, self.owner == owner {
            classId = id
            reminders = list
        }
        let b = store(.reminder, list.map { list in
            list.map {
                SearchEntry(id: "rem:\($0.id)", kind: .reminder, title: $0.title, subtitle: $0.createdByName, keywords: $0.body,
                            target: .page(.reminder($0.id)), label: t.srcReminder)
            }
        }, owner: owner)
        return a && b
    }

    private func loadMensa(_ days: SearchDays, _ t: SearchStrings, _ owner: String) async -> Bool {
        let dishes = try? await BackendClient.shared.dishes()
        let today = SchoolDates.todayISO()
        return store(.dish, dishes.map { list in
            list.filter { String($0.date.prefix(10)) >= today }.map { d in
                let num = Int(d.date.prefix(10).replacingOccurrences(of: "-", with: "")) ?? 0
                return SearchEntry(id: "dish:\(d.id)-\(num)", kind: .dish, title: d.name, subtitle: days.long(num),
                                   keywords: "\(d.category) \(d.tags.joined(separator: " "))", target: .tab(.mensa), label: t.srcDish)
            }
        }, owner: owner)
    }

    /// Message previews and homework come as HTML.
    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Dates of result subtitles in the app's language ("Mo 3. Nov." / "lun 3 nov").
private struct SearchDays {
    let lang: Lang
    private let shortFormat: DateFormatter
    private let longFormat: DateFormatter
    private let weekdayFormat: DateFormatter

    init(_ s: Strings) {
        lang = s.lang
        func make(_ pattern: String) -> DateFormatter {
            let f = DateFormatter()
            f.locale = s.lang.locale
            f.dateFormat = s.lang == .de ? pattern : pattern.replacingOccurrences(of: ". ", with: " ")
            return f
        }
        shortFormat = make("EEE d. MMM")
        longFormat = make("EEEE d. MMM")
        weekdayFormat = make("EEE")
    }

    func short(_ num: Int) -> String { Timetable.date(num).map(shortFormat.string(from:)) ?? "" }
    func long(_ num: Int) -> String { Timetable.date(num).map(longFormat.string(from:)) ?? "" }
    func weekday(_ num: Int) -> String { Timetable.date(num).map(weekdayFormat.string(from:)) ?? "" }
}

// ── The screen ──────────────────────────────────────────────────────────────

/// Android's search, the web's palette: "Seiten" are the places and actions of the app, then
/// what is on them, a section per kind. Everything is matched on the device, word by word and
/// without accents.
struct SearchView: View {
    /// Opened as a sheet the field starts focused, as on Android; as a tab the system does that.
    var focusOnAppear = false
    /// The tab keeps its field under the title: a search tab on the iPhone otherwise shows none.
    var inTab = false
    let leave: (AppTab) -> Void
    @Environment(AppState.self) private var app
    @Environment(SearchModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var scheme
    @FocusState private var fieldFocused: Bool
    @State private var expanded: Set<SearchKind> = []
    @State private var route: SearchRoute?
    @State private var showProfile = false
    @State private var scroll = ScrollPosition(edge: .top)

    private var hasUntis: Bool { app.session?.hasUntis != false }

    private var ownerKey: String {
        guard let session = app.session else { return "" }
        return "\(session.schoolRef.loginName)/\(session.username)/\(session.studentId)|\(s.lang)"
    }

    var body: some View {
        let typing = !model.words.isEmpty
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.sections) { section in
                    sectionView(section)
                }
                if typing && model.sections.isEmpty && model.isCurrent {
                    if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xxl)
                    } else {
                        StateView(s.search.noResults, compact: true, sprite: .search)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: WidthClass.readableMaxWidth)
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.2), value: model.revision)
        }
        .scrollPosition($scroll)
        // Only a drag puts the keyboard away; results shrinking under it used to do that too.
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(s.search.title)
        .modifier(SearchField(inTab: inTab, text: Bindable(model).query, prompt: s.search.placeholder, focused: $fieldFocused))
        .task {
            guard focusOnAppear else { return }
            // Asked for while the sheet still slides up, the focus got dropped now and then.
            try? await Task.sleep(for: .milliseconds(350))
            fieldFocused = true
        }
        // New words, best hits first: start at the top like Apple's own lists.
        .onChange(of: model.resultWords) { scroll.scrollTo(edge: .top) }
        .onChange(of: pageKey, initial: true) { model.setPages(pages) }
        .onChange(of: typing) { _, now in if !now { expanded = [] } }
        .task(id: ownerKey) {
            if let session = app.session { model.prepare(session, s, app: app) }
        }
        .pushed(item: $route) { destination($0) }
        .sheet(isPresented: $showProfile) { NavigationStack { ProfileView() } }
    }

    @ViewBuilder
    private func sectionView(_ section: SearchSection) -> some View {
        let isOpen = expanded.contains(section.kind)
        let typing = !model.resultWords.isEmpty
        let cap = typing ? section.kind.cap : .max
        let shown = isOpen ? section.entries : Array(section.entries.prefix(cap))
        HStack(alignment: .firstTextBaseline) {
            EyebrowLabel(section.kind.section(s.search))
            Spacer()
            if section.entries.count > cap {
                Button(isOpen ? s.search.showLess : s.search.showAll) {
                    withAnimation(.smooth(duration: 0.25)) {
                        if isOpen { expanded.remove(section.kind) } else { expanded.insert(section.kind) }
                    }
                }
                .textStyle(TextStyle.footnote.weight(.semibold))
                .tint(Palette.accentText)
            }
        }
        .padding(.top, section.kind == model.sections.first?.kind ? Spacing.sm : Spacing.lg)
        .padding(.bottom, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .id("h-\(section.kind.rawValue)")
        ForEach(shown) { entry in
            SearchResultRow(entry: entry, words: model.resultWords) { open(entry.target) }
        }
    }

    private func open(_ target: SearchTarget) {
        switch target {
        case .tab(let tab): leave(tab)
        case .page(let r): route = r
        case .profile: showProfile = true
        case .lesson(let day):
            TimetableJump.shared.day = day
            leave(.timetable)
        case .theme:
            app.themeMode = scheme == .dark ? .light : .dark
        }
    }

    @ViewBuilder
    private func destination(_ r: SearchRoute) -> some View {
        switch r {
        case .messages: MessagesView()
        case .absences: AbsencesView()
        case .classreg: ClassregEventsView()
        case .klasse: ClassView()
        case .todos: TodosView()
        case .reminders: RemindersView()
        case .settings: SettingsView()
        case .grade(let id): GradeSubjectView(lessonId: id, subjects: model.subjects)
        case .message(let id):
            if let m = model.inbox.first(where: { $0.id == id }) {
                MessageDetailScreen(preview: m, folder: .inbox) {
                    model.markRead(id)
                    app.messageWasRead()
                }
            }
        case .reminder(let id):
            if let r = model.reminders.first(where: { $0.id == id }), let classId = model.classId {
                ReminderDetailView(reminder: r, classId: classId)
            }
        }
    }

    // ── Pages ───────────────────────────────────────────────────────────────

    private struct PageKey: Hashable {
        let lang: Lang
        let dark: Bool
        let hasUntis: Bool
        let isParent: Bool
        let hasToken: Bool
    }

    private var pageKey: PageKey {
        PageKey(lang: s.lang, dark: scheme == .dark, hasUntis: hasUntis, isParent: app.isParent, hasToken: app.session?.apiToken != nil)
    }

    private var pages: [SearchEntry] {
        let t = s.search, nav = s.nav, school = s.school
        func page(_ id: String, _ title: String, _ symbol: String, _ tone: SearchTone?, _ keywords: String, _ target: SearchTarget) -> SearchEntry {
            SearchEntry(id: id, kind: .page, title: title, keywords: keywords, symbol: symbol, tone: .some(tone), target: target)
        }
        var out = [page("home", nav.home, "house.fill", .periwinkle, "dashboard start übersicht panoramica", .tab(.home))]
        if hasUntis {
            out += [
                page("tt", nav.timetable, "calendar", .periwinkle, "plan stunden lessons orario", .tab(.timetable)),
                page("grades", nav.grades, "chart.bar.fill", .periwinkle, "voti marks durchschnitt media", .tab(.noten)),
                page("msg", nav.messages, "envelope.fill", .periwinkle, "mail post inbox messaggi", .page(.messages)),
            ]
        }
        out.append(page("mensa", nav.mensa, "fork.knife", .butter, "essen menu speiseplan cafeteria", .tab(.mensa)))
        if hasUntis {
            out += [
                page("abs", school.absences, "person.fill.xmark", .butter, "fehlstunden assenze", .page(.absences)),
                page("creg", school.classreg, "book.closed.fill", .butter, "klassenbuch registro einträge vermerk", .page(.classreg)),
            ]
        }
        out.append(page("todos", school.todos, "checklist", .sage, "aufgaben tasks", .page(.todos)))
        // Parent accounts see the class but not its reminders, as in the hub.
        if !app.isParent {
            out.append(page("rem", school.reminders, "bell.fill", .blush, "termine promemoria", .page(.reminders)))
        }
        if hasUntis || app.session?.apiToken != nil {
            out.append(page("class", school.klasse, "person.3.fill", .sage, "mitschüler classe klassendienste dienste hausaufgaben", .page(.klasse)))
        }
        out += [
            page("school", nav.school, "graduationcap.fill", .periwinkle, "hub übersicht", .tab(.school)),
            page("profile", s.profile.title, "person.crop.circle.fill", .periwinkle, "konto account", .profile),
            page("settings", s.settings.title, "gearshape.fill", .sage, "einstellungen impostazioni darstellung theme", .page(.settings)),
        ]
        // Writing and reporting have no screens of their own yet; their lists are the way in.
        if hasUntis {
            out += [
                page("compose", t.actionCompose, "square.and.pencil", nil, "nachricht schreiben senden lehrer", .page(.messages)),
                page("report", t.actionReport, "person.badge.minus", nil, "krank fehlen abwesend", .page(.absences)),
            ]
        }
        out += [
            page("theme", t.actionTheme, scheme == .dark ? "sun.max.fill" : "moon.fill", nil, "dark mode dunkel hell theme farbe", .theme),
            page("lang", t.actionLanguage, "globe", nil, "sprache lingua deutsch italiano english", .page(.settings)),
        ]
        return out
    }
}

/// Under the title in the tab; in the sheet where the system puts it, with the bar and its
/// close button staying while typing.
private struct SearchField: ViewModifier {
    let inTab: Bool
    let text: Binding<String>
    let prompt: String
    let focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if inTab {
            content
                .searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
                .autocorrectionDisabled()
        } else {
            content
                .listSearch(text, prompt: prompt)
                .searchFocused(focused)
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .autocorrectionDisabled()
        }
    }
}

/// Glyph on its tone, title and subtitle, the typed words picked out.
private struct SearchResultRow: View {
    let entry: SearchEntry
    let words: [String]
    let action: () -> Void

    var body: some View {
        let tone = entry.tone?.tone
        Button(action: action) {
            HStack(spacing: Spacing.iconText) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tone?.ink ?? Palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(tone?.fill ?? Palette.nested, in: .pokyh(Radius.md))
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.marked(entry.title, words))
                        .textStyle(TextStyle.callout.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if !entry.subtitle.isEmpty {
                        Text(Self.marked(entry.subtitle, words))
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.rowPress(radius: Radius.lg))
    }

    /// Each typed word tinted where it matches, at a word's start if it does there.
    static func marked(_ text: String, _ words: [String]) -> AttributedString {
        guard !words.isEmpty else { return AttributedString(text) }
        var hits: [Range<String.Index>] = []
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for w in words {
            var best: Range<String.Index>?
            var from = text.startIndex
            while from < text.endIndex, let r = text.range(of: w, options: options, range: from..<text.endIndex) {
                if best == nil { best = r }
                if r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter {
                    best = r
                    break
                }
                from = text.index(after: r.lowerBound)
            }
            if let best { hits.append(best) }
        }
        guard !hits.isEmpty else { return AttributedString(text) }
        hits.sort { $0.lowerBound < $1.lowerBound }
        var out = AttributedString()
        var cursor = text.startIndex
        for hit in hits where hit.upperBound > cursor {
            let start = max(hit.lowerBound, cursor)
            if cursor < start { out += AttributedString(String(text[cursor..<start])) }
            var part = AttributedString(String(text[start..<hit.upperBound]))
            part.foregroundColor = Palette.accentText
            out += part
            cursor = hit.upperBound
        }
        if cursor < text.endIndex { out += AttributedString(String(text[cursor...])) }
        return out
    }
}
