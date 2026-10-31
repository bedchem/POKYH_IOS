import SwiftUI
import PokyhCore
import PokyhDesign

/// Home · Stundenplan · Schule · Noten · Mensa, in Android's order, plus the search tab.
/// A tab bar on the iPhone, a sidebar on wide iPad windows (Android's side rail).
struct RootTabView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var searching = false

    /// Accounts that only exist on the POKYH backend have no timetable or grades,
    /// so those two tabs go away.
    private var hasUntis: Bool { app.session?.hasUntis ?? true }

    /// A compact tab bar holds five tabs; a sixth would push Mensa and the search into "More".
    /// Then the search sits in the tab roots' toolbar instead, beside the messages.
    private var searchIsTab: Bool { sizeClass == .regular || !hasUntis }

    /// Read here rather than from the environment: a language picked in the settings has to
    /// reach every tab and sheet at once, and this view redraws whenever AppState changes.
    private var strings: Strings { Strings.of(LanguageChoice.current(in: .standard)) }

    var body: some View {
        let s = strings
        TabView(selection: selection) {
            tab(.home, s)
            if hasUntis { tab(.timetable, s) }
            tab(.school, s)
            if hasUntis { tab(.noten, s) }
            tab(.mensa, s)
            if searchIsTab {
                Tab(s.search.title, systemImage: "magnifyingglass", value: RootTab.search, role: .search) {
                    NavigationStack {
                        SearchView { leave(to: $0) }.appBackground()
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The bar stays as it is: same size, same place, on every screen.
        .tabBarMinimizeBehavior(.never)
        .tint(Palette.accent)
        .modifier(RecapHost())
        .modifier(AnnouncementPopupHost())
        .modifier(WebSignInHost(scanning: .constant(false), working: .constant(false), takesLinks: true))
        .environment(\.strings, s)
        .environment(\.searchInToolbar, !searchIsTab)
        .onChange(of: searchIsTab) { _, isTab in if !isTab { searching = false } }
        .onAppear {
            // The stored tab belongs to WebUntis but this account has none.
            if !hasUntis, app.selectedTab == .timetable || app.selectedTab == .noten {
                app.selectedTab = .home
            }
        }
        .onChange(of: app.selectedTab) {
            searching = false
            Task { await app.refreshUnread() }
        }
        .task {
            // Home loads the inbox itself at launch; a moment's wait usually finds that count fresh.
            try? await Task.sleep(for: .seconds(2))
            await app.refreshUnread()
        }
    }

    /// A selection pointing at a hidden tab falls back to Home, so there's never an empty screen.
    private var shownTab: AppTab {
        if !hasUntis, app.selectedTab == .timetable || app.selectedTab == .noten { return .home }
        return app.selectedTab
    }

    /// Tapping Stundenplan (again) jumps it back to today.
    private var selection: Binding<RootTab> {
        Binding(
            get: { searching && searchIsTab ? .search : .app(shownTab) },
            set: { newValue in
                switch newValue {
                case .search:
                    searching = true
                case .app(let tab):
                    if tab == .timetable { app.timetableHomeSignal += 1 }
                    searching = false
                    app.selectedTab = tab
                }
            }
        )
    }

    /// A search result that lives in a tab: go there without the "back to today" tap behaviour.
    private func leave(to tab: AppTab) {
        searching = false
        app.selectedTab = tab
    }

    private func tab(_ value: AppTab, _ s: Strings) -> some TabContent<RootTab> {
        Tab(value: RootTab.app(value)) {
            NavigationStack { screen(value).appBackground(wide: value == .home || value == .timetable) }
        } label: {
            // Outline normally, filled when selected, like Android's Phosphor pair.
            Label(title(value, s), systemImage: value == shownTab && !searching ? value.selectedSymbol : value.symbol)
                .environment(\.symbolVariants, .none)
        }
        // Messages live under Schule, so that's where their unread count shows.
        .badge(value == .school ? app.unreadBadge : 0)
    }

    private func title(_ value: AppTab, _ s: Strings) -> String {
        switch value {
        case .home: s.nav.home
        case .timetable: s.nav.timetable
        case .school: s.nav.school
        case .noten: s.nav.grades
        case .mensa: s.nav.mensa
        }
    }

    @ViewBuilder
    private func screen(_ value: AppTab) -> some View {
        switch value {
        case .home: HomeView()
        case .timetable: TimetableView()
        case .school: SchoolHubView()
        case .noten: GradesView()
        case .mensa: MensaView()
        }
    }
}

/// The tab bar's selection: one of the app's tabs, or the search.
private enum RootTab: Hashable {
    case app(AppTab)
    case search
}

private extension AppTab {
    // Phosphor House, CalendarBlank, GraduationCap, ChartBar, ForkKnife.
    // calendar and fork.knife have no filled twin; the tint carries their selection.
    var symbol: String {
        switch self {
        case .home: "house"
        case .timetable: "calendar"
        case .school: "graduationcap"
        case .noten: "chart.bar"
        case .mensa: "fork.knife"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .home: "house.fill"
        case .timetable: "calendar"
        case .school: "graduationcap.fill"
        case .noten: "chart.bar.fill"
        case .mensa: "fork.knife"
        }
    }
}

// ── Search ──────────────────────────────────────────────────────────────────

/// Where a search result leads.
private enum SearchTarget {
    case tab(AppTab)
    case page(SearchRoute)
    case profile
    case lesson(day: Int)
    case theme
}

/// Pages a result opens inside the search tab.
private enum SearchRoute: Hashable {
    case messages, absences, classreg, klasse, todos, reminders, settings
    case grade(lessonId: Int)
    case message(Int)
    case reminder(String)
}

/// What a content result is, for its tag, glyph and tone.
private enum SearchSource {
    case classreg, reminder, todo, subject, grade, lesson, message, dish

    func label(_ t: SearchStrings) -> String {
        switch self {
        case .classreg: t.srcClassreg
        case .reminder: t.srcReminder
        case .todo: t.srcTodo
        case .subject: t.srcSubject
        case .grade: t.srcGrade
        case .lesson: t.srcLesson
        case .message: t.srcMessage
        case .dish: t.srcDish
        }
    }

    var symbol: String {
        switch self {
        case .classreg: "book.closed.fill"
        case .reminder: "bell.fill"
        case .todo: "checklist"
        case .subject, .grade: "chart.bar.fill"
        case .lesson: "calendar"
        case .message: "envelope.fill"
        case .dish: "fork.knife"
        }
    }

    var tone: Tone {
        switch self {
        case .todo: Decorative.sage
        case .classreg, .dish: Decorative.butter
        case .reminder: Decorative.blush
        default: Decorative.periwinkle
        }
    }
}

private struct SearchPage: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tone: Tone?
    let keywords: String
    let target: SearchTarget
}

private struct SearchDoc: Identifiable {
    let id: String
    let source: SearchSource
    let title: String
    var subtitle = ""
    var keywords = ""
    let target: SearchTarget
}

/// Android's search, the web's palette: "Seiten" are the places and actions of the app,
/// "Inhalte" what is on them, each row naming where it comes from. Everything is matched on
/// the device, word by word and without accents.
struct SearchView: View {
    /// Opened as a sheet the field starts focused, as on Android; as a tab the system does that.
    let focusOnAppear: Bool
    let leave: (AppTab) -> Void
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var scheme

    @State private var fieldActive = false
    @State private var query = ""
    @State private var content: [String: [SearchDoc]] = [:]
    @State private var subjects: [SubjectGrades] = []
    @State private var inbox: [MessagePreview] = []
    @State private var reminders: [ApiReminder] = []
    @State private var classId: String?
    @State private var route: SearchRoute?
    @State private var showProfile = false

    init(focusOnAppear: Bool = false, leave: @escaping (AppTab) -> Void) {
        self.focusOnAppear = focusOnAppear
        self.leave = leave
    }

    private var hasUntis: Bool { app.session?.hasUntis != false }

    private var pages: [SearchPage] {
        let peri = Decorative.periwinkle, butter = Decorative.butter, sage = Decorative.sage, blush = Decorative.blush
        let t = s.search, nav = s.nav, school = s.school
        var out: [SearchPage] = [
            SearchPage(id: "home", title: nav.home, symbol: "house.fill", tone: peri, keywords: "dashboard start übersicht panoramica", target: .tab(.home)),
        ]
        if hasUntis {
            out += [
                SearchPage(id: "tt", title: nav.timetable, symbol: "calendar", tone: peri, keywords: "plan stunden lessons orario", target: .tab(.timetable)),
                SearchPage(id: "grades", title: nav.grades, symbol: "chart.bar.fill", tone: peri, keywords: "voti marks durchschnitt media", target: .tab(.noten)),
                SearchPage(id: "msg", title: nav.messages, symbol: "envelope.fill", tone: peri, keywords: "mail post inbox messaggi", target: .page(.messages)),
            ]
        }
        out.append(SearchPage(id: "mensa", title: nav.mensa, symbol: "fork.knife", tone: butter, keywords: "essen menu speiseplan cafeteria", target: .tab(.mensa)))
        if hasUntis {
            out += [
                SearchPage(id: "abs", title: school.absences, symbol: "person.fill.xmark", tone: butter, keywords: "fehlstunden assenze", target: .page(.absences)),
                SearchPage(id: "creg", title: school.classreg, symbol: "book.closed.fill", tone: butter, keywords: "klassenbuch registro einträge vermerk", target: .page(.classreg)),
            ]
        }
        out.append(SearchPage(id: "todos", title: school.todos, symbol: "checklist", tone: sage, keywords: "aufgaben tasks", target: .page(.todos)))
        // Parent accounts see the class but not its reminders, as in the hub.
        if !app.isParent {
            out.append(SearchPage(id: "rem", title: school.reminders, symbol: "bell.fill", tone: blush, keywords: "termine promemoria", target: .page(.reminders)))
        }
        if hasUntis || app.session?.apiToken != nil {
            out.append(SearchPage(id: "class", title: school.klasse, symbol: "person.3.fill", tone: sage, keywords: "mitschüler classe klassendienste dienste", target: .page(.klasse)))
        }
        out += [
            SearchPage(id: "school", title: nav.school, symbol: "graduationcap.fill", tone: peri, keywords: "hub übersicht", target: .tab(.school)),
            SearchPage(id: "profile", title: s.profile.title, symbol: "person.crop.circle.fill", tone: peri, keywords: "konto account", target: .profile),
            SearchPage(id: "settings", title: s.settings.title, symbol: "gearshape.fill", tone: sage, keywords: "einstellungen impostazioni darstellung theme", target: .page(.settings)),
        ]
        // Writing and reporting have no screens of their own yet; their lists are the way in.
        if hasUntis {
            out += [
                SearchPage(id: "compose", title: t.actionCompose, symbol: "square.and.pencil", tone: nil, keywords: "nachricht schreiben senden lehrer", target: .page(.messages)),
                SearchPage(id: "report", title: t.actionReport, symbol: "person.badge.minus", tone: nil, keywords: "krank fehlen abwesend", target: .page(.absences)),
            ]
        }
        out += [
            SearchPage(id: "theme", title: t.actionTheme, symbol: scheme == .dark ? "sun.max.fill" : "moon.fill", tone: nil, keywords: "dark mode dunkel hell theme farbe", target: .theme),
            SearchPage(id: "lang", title: t.actionLanguage, symbol: "globe", tone: nil, keywords: "sprache lingua deutsch italiano english", target: .page(.settings)),
        ]
        return out
    }

    private var words: [String] {
        Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var pageRows: [SearchPage] {
        let w = words
        guard !w.isEmpty else { return pages }
        return pages
            .map { ($0, Self.score($0.title, $0.keywords, w)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map(\.0)
    }

    private var contentRows: [SearchDoc] {
        let w = words
        guard !w.isEmpty else { return [] }
        let t = s.search
        var seen = Set<String>()
        let docs: [SearchDoc] = content.keys.sorted().flatMap { content[$0] ?? [] }.filter { seen.insert($0.id).inserted }
        let scored: [(SearchDoc, Int)] = docs.map { d in
            (d, Self.score(d.title, [d.subtitle, d.keywords, d.source.label(t)].joined(separator: " "), w))
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(40).map(\.0)
    }

    var body: some View {
        let pageRows = pageRows, contentRows = contentRows, typing = !words.isEmpty
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !typing {
                    Text(s.search.empty)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, Spacing.sm)
                }
                if !pageRows.isEmpty {
                    EyebrowLabel(s.search.pages)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xs)
                    ForEach(pageRows) { p in
                        SearchResultRow(title: p.title, symbol: p.symbol, tone: p.tone) { open(p.target) }
                    }
                }
                if !contentRows.isEmpty {
                    EyebrowLabel(s.search.contents)
                        .padding(.top, Spacing.lg)
                        .padding(.bottom, Spacing.xs)
                    ForEach(contentRows) { d in
                        SearchResultRow(title: d.title, subtitle: d.subtitle, tag: d.source.label(s.search),
                                        symbol: d.source.symbol, tone: d.source.tone) { open(d.target) }
                    }
                }
                if typing && pageRows.isEmpty && contentRows.isEmpty {
                    Text(s.search.noResults)
                        .textStyle(.callout)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, Spacing.xl)
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: WidthClass.readableMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(s.search.title)
        .searchable(text: $query, isPresented: $fieldActive, prompt: s.search.placeholder)
        .onAppear { if focusOnAppear { fieldActive = true } }
        .navigationDestination(item: $route) { destination($0) }
        .sheet(isPresented: $showProfile) { NavigationStack { ProfileView() } }
        .task(id: app.session?.username) { await load() }
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
        case .grade(let id): GradeSubjectView(lessonId: id, subjects: subjects)
        case .message(let id):
            if let m = inbox.first(where: { $0.id == id }) {
                MessageDetailScreen(preview: m, folder: .inbox) {
                    if let i = inbox.firstIndex(where: { $0.id == id }) { inbox[i].isRead = true }
                    app.messageWasRead()
                }
            }
        case .reminder(let id):
            if let r = reminders.first(where: { $0.id == id }), let classId {
                ReminderDetailView(reminder: r, classId: classId)
            }
        }
    }

    // ── Matching ────────────────────────────────────────────────────────────

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }

    /// The web's scoring: the title's start counts most, then a word in it, then anywhere in it,
    /// then the rest. Every word has to match somewhere.
    private static func score(_ title: String, _ rest: String, _ words: [String]) -> Int {
        let t = fold(title), r = fold(rest)
        var total = 0
        for w in words {
            if t.hasPrefix(w) { total += 4 }
            else if t.contains(" \(w)") || t.contains("-\(w)") { total += 3 }
            else if t.contains(w) { total += 2 }
            else if r.contains(w) { total += 1 }
            else { return 0 }
        }
        return total
    }

    // ── Content ─────────────────────────────────────────────────────────────

    /// What the app has loaded anyway, each source on its own so a slow one holds nothing up.
    private func load() async {
        guard let session = app.session else { return }
        let days = SearchDays(s)
        async let grades: () = loadGrades(session, days)
        async let lessons: () = loadLessons(session, days)
        async let messages: () = loadMessages(session)
        async let classreg: () = loadClassreg(session, days)
        async let tasks: () = loadTasks(session)
        async let mensa: () = loadMensa(days)
        _ = await (grades, lessons, messages, classreg, tasks, mensa)
    }

    private func loadGrades(_ session: UserSession, _ days: SearchDays) async {
        guard session.hasUntis, let list = try? await UntisClient.shared.grades(year: nil, session) else { return }
        subjects = list
        content["grades"] = list.flatMap { sub -> [SearchDoc] in
            let target = SearchTarget.page(.grade(lessonId: sub.lessonId))
            let subject = SearchDoc(id: "subject:\(sub.lessonId)", source: .subject, title: sub.subjectName, subtitle: sub.teacherName, target: target)
            return [subject] + sub.grades.filter { $0.markDisplayValue > 0 }.map { g in
                SearchDoc(
                    id: "grade:\(g.id)", source: .grade,
                    title: "\(g.markName.isEmpty ? Fmt.num(g.markDisplayValue) : g.markName) · \(sub.subjectName)",
                    subtitle: [g.examType, g.text, days.short(g.date)].filter { !$0.isEmpty }.joined(separator: " · "),
                    target: target
                )
            }
        }
    }

    private func loadLessons(_ session: UserSession, _ days: SearchDays) async {
        guard session.hasUntis,
              let list = try? await UntisClient.shared.timetable(date: SchoolDates.mondayISO(of: Date()), session) else { return }
        var seen = Set<String>()
        content["lessons"] = list.filter { !$0.isCancelled && seen.insert("\($0.date)-\($0.startTime)").inserted }.map { e in
            SearchDoc(
                id: "lesson:\(e.date)-\(e.startTime)", source: .lesson,
                title: e.subjectLong.isEmpty ? (e.subjectName.isEmpty ? (e.note ?? "–") : e.subjectName) : e.subjectLong,
                subtitle: ["\(days.weekday(e.date)) \(Fmt.time(e.startTime))", e.roomName, e.teacherLongName ?? e.teacherName]
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " · "),
                keywords: "\(e.subjectName) \(e.teacherName) \(e.note ?? "")",
                target: .lesson(day: e.date)
            )
        }
    }

    private func loadMessages(_ session: UserSession) async {
        guard session.hasUntis, let list = try? await UntisClient.shared.messages(folder: .inbox, session) else { return }
        inbox = list
        app.noteInbox(list)
        content["messages"] = list.map { m in
            SearchDoc(id: "msg:\(m.id)", source: .message, title: m.subject.isEmpty ? "–" : m.subject,
                      subtitle: m.senderName, keywords: Self.plain(m.contentPreview), target: .page(.message(m.id)))
        }
    }

    private func loadClassreg(_ session: UserSession, _ days: SearchDays) async {
        guard session.hasUntis, let list = try? await UntisClient.shared.classregEvents(year: nil, session) else { return }
        content["classreg"] = list.map { e in
            let title = [e.text, e.categoryName, e.eventReasonName].first { !$0.isEmpty } ?? "–"
            return SearchDoc(
                id: "event:\(e.id)", source: .classreg, title: title,
                subtitle: [e.categoryName, e.subjectName, days.short(e.createDate)].filter { !$0.isEmpty }.joined(separator: " · "),
                keywords: "\(e.eventReasonName) \(e.creatorName)",
                target: .page(.classreg)
            )
        }
    }

    private func loadTasks(_ session: UserSession) async {
        guard let token = session.apiToken else { return }
        if let list = try? await BackendClient.shared.todos(username: session.username, token: token) {
            content["todos"] = list.map { SearchDoc(id: "todo:\($0.id)", source: .todo, title: $0.title, keywords: $0.details, target: .page(.todos)) }
        }
        guard !session.isParent else { return }
        var id = session.classId
        if id == nil { id = try? await BackendClient.shared.myClass(token: token)?.id }
        guard let id, let list = try? await BackendClient.shared.reminders(classId: id, token: token) else { return }
        classId = id
        reminders = list
        content["reminders"] = list.map {
            SearchDoc(id: "rem:\($0.id)", source: .reminder, title: $0.title, subtitle: $0.createdByName, keywords: $0.body, target: .page(.reminder($0.id)))
        }
    }

    private func loadMensa(_ days: SearchDays) async {
        guard let dishes = try? await BackendClient.shared.dishes() else { return }
        let today = SchoolDates.todayISO()
        content["mensa"] = dishes.filter { String($0.date.prefix(10)) >= today }.map { d in
            let num = Int(d.date.prefix(10).replacingOccurrences(of: "-", with: "")) ?? 0
            return SearchDoc(id: "dish:\(d.id)-\(num)", source: .dish, title: d.name, subtitle: days.long(num),
                             keywords: "\(d.category) \(d.tags.joined(separator: " "))", target: .tab(.mensa))
        }
    }

    /// Message previews come as HTML.
    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Dates of result subtitles in the app's language ("Mo 3. Nov." / "lun 3 nov").
private struct SearchDays {
    private let shortFormat: DateFormatter
    private let longFormat: DateFormatter
    private let weekdayFormat: DateFormatter

    init(_ s: Strings) {
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

/// Glyph on its tone, title and subtitle, and where it comes from at the end.
private struct SearchResultRow: View {
    let title: String
    var subtitle: String? = nil
    var tag: String? = nil
    let symbol: String
    let tone: Tone?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.iconText) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tone?.ink ?? Palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(tone?.fill ?? Palette.nested, in: .pokyh(Radius.md))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .textStyle(TextStyle.callout.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let tag {
                    Text(tag)
                        .textStyle(TextStyle.caption2.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.rowPress(radius: Radius.lg))
    }
}
