import SwiftUI
import PokyhCore
import PokyhDesign

/// Home: a personal greeting instead of a title, then the blocks in the order the day happens.
/// On wide windows the shortcuts span the width and the other blocks pair up side by side.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s

    // Timetable: this week and the next, so "tomorrow" works on a Friday too.
    @State private var weekEntries: [TimetableEntry] = []
    @State private var hues = SubjectHues()
    @State private var loadingToday = true
    @State private var todayFailed = false
    @State private var nextExam: TimetableEntry?
    @State private var examsLoaded = false
    @State private var examsFailed = false
    @State private var subjects: [SubjectGrades] = []
    @State private var loadingGrades = true
    @State private var gradesFailed = false
    @State private var messages: [MessagePreview] = []
    @State private var loadingMessages = true
    @State private var messagesFailed = false
    @State private var mensaDay: MensaDay?
    @State private var loadingMensa = true
    @State private var ratings: [String: DishRatingsData] = [:]
    @State private var loadingRatings = false
    @State private var absenceHours: Int?
    @State private var todos: [ApiTodo] = []
    @State private var todosLoaded = false
    @State private var todosFailed = false
    @State private var reminders: [ApiReminder] = []
    @State private var remindersLoaded = false
    @State private var remindersFailed = false

    @State private var width: CGFloat = 0
    @State private var route: Route?
    @State private var arranging = false
    /// Which blocks Home shows and in what order, by block name (see HomeLayout).
    @AppStorage("pokyh_home_layout") private var storedLayout = ""

    struct MensaDay { let date: Date; let dishes: [Dish] }

    private enum Route: Hashable {
        case grades, absences, todos, reminders, messages, mensa
        // The greeting's shortcuts open the sheet straight away.
        case composeMessage, reportAbsence
        case message(Int)
        case gradeSubject(Int)
    }

    private var wide: Bool { width >= 760 }
    private var hasUntis: Bool { app.session?.hasUntis ?? false }
    private var hasBackend: Bool { app.session?.apiToken != nil }
    private var showsMensa: Bool { loadingMensa || mensaDay != nil }

    private var layout: Binding<HomeLayout> {
        Binding(get: { HomeLayout(stored: storedLayout) }, set: { storedLayout = $0.stored })
    }

    /// The arranged blocks this account can fill: the Mensa only with a menu, the lists only
    /// with a POKYH account.
    private var blocks: [HomeSection] {
        layout.wrappedValue.visible.filter { b in
            switch b {
            case .mensa: showsMensa
            case .todos, .reminders: hasBackend
            default: true
            }
        }
    }

    /// Shortcuts across the whole width, everything else in pairs.
    private var wideRows: [[HomeSection]] {
        var rows: [[HomeSection]] = []
        var pending: HomeSection?
        for b in blocks {
            if b == .shortcuts {
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([b])
            } else if let p = pending {
                rows.append([p, b]); pending = nil
            } else {
                pending = b
            }
        }
        if let p = pending { rows.append([p]) }
        return rows
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                greeting.fadeIn()
                if !hasUntis {
                    // Without WebUntis only what works without a school account.
                    noUntisBlock.fadeIn(delay: 0.04)
                    if blocks.contains(.mensa) { mensaBlock.fadeIn(delay: 0.08) }
                } else if blocks.isEmpty {
                    InlineNotice(s.home.noWidgets, symbol: "pencil").fadeIn(delay: 0.04)
                } else if wide {
                    ForEach(Array(wideRows.enumerated()), id: \.offset) { index, row in
                        WeightedRow(weights: row.map { row.count == 1 ? 1 : ($0 == .exam || $0 == .mensa ? 5 : 7) }, spacing: Spacing.xxl) {
                            ForEach(row, id: \.self) { block($0) }
                        }
                        .fadeIn(delay: 0.04 + Double(index) * 0.04)
                    }
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.element) { index, b in
                        block(b).fadeIn(delay: 0.04 + Double(index) * 0.04)
                    }
                }
            }
            .padding(.horizontal, wide ? Spacing.xxxl : Spacing.screenH)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: WidthClass.wideMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle(s.nav.home)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The greeting is the heading here; the title only names the back button.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            if hasUntis {
                ToolbarItem(placement: .topBarLeading) {
                    Button { arranging = true } label: { Image(systemName: "pencil") }
                        .accessibilityLabel(s.nav.arrangeHome)
                }
            }
        }
        .profileToolbar()
        .sheet(isPresented: $arranging) { HomeArrangeSheet(layout: layout) }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: storedLayout)
        .navigationDestination(item: $route) { destination($0) }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    @ViewBuilder
    private func destination(_ r: Route) -> some View {
        switch r {
        case .grades: GradesView()
        case .absences: AbsencesView()
        case .todos: TodosView()
        case .reminders: RemindersView()
        case .messages: MessagesView()
        case .composeMessage: MessagesView(startCompose: true)
        case .reportAbsence: AbsencesView(openReport: true)
        case .mensa: MensaView()
        case .gradeSubject(let id): GradeSubjectView(lessonId: id, subjects: subjects)
        case .message(let id):
            if let m = messages.first(where: { $0.id == id }) {
                MessageDetailScreen(preview: m, folder: .inbox) {
                    if let i = messages.firstIndex(where: { $0.id == id }) { messages[i].isRead = true }
                    app.messageWasRead()
                }
            }
        }
    }

    @ViewBuilder
    private func block(_ b: HomeSection) -> some View {
        switch b {
        case .shortcuts: shortcuts
        case .nowNext: nowNextBlock
        case .exam: examBlock
        case .today: todayBlock
        case .changes: changesBlock
        case .grades: gradesBlock
        case .average: averageBlock
        case .messages: messagesBlock
        case .mensa: mensaBlock
        case .todos: todosBlock
        case .reminders: remindersBlock
        }
    }

    // ── Greeting ────────────────────────────────────────────────────────────

    private var greetingWord: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 11 ? s.home.morning : hour < 17 ? s.home.day : s.home.evening
    }

    /// WebUntis gives "Pfeifer Emanuel", surname first, so the word a part of the login name
    /// starts with is the first name. Guardians are greeted without one.
    private var firstName: String {
        guard let session = app.session else { return "" }
        if session.isParent { return "" }
        if !session.hasUntis { return session.username }
        let words = (session.personName ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        let parts = session.username.lowercased()
            .split(whereSeparator: { "-._ ".contains($0) })
            .map(String.init)
            .filter { $0.count >= 2 }
        for part in parts.reversed() {
            if let w = words.first(where: { $0.lowercased().hasPrefix(part) }) { return w }
        }
        return ""
    }

    private var heading: AttributedString {
        let name = app.session == nil ? s.home.welcome : firstName
        var text = AttributedString(greetingWord)
        if !name.isEmpty {
            text += AttributedString(", ")
            var n = AttributedString(name)
            n.foregroundColor = Brand.accent
            text += n
        }
        return text
    }

    private var dateLine: String {
        let now = Date(), cal = Calendar.current
        let day = s.common.weekdays[Timetable.weekdayIndex(now)] + ", "
            + s.common.dayMonth(cal.component(.day, from: now), cal.component(.month, from: now))
        return [day, app.session?.klasseName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static let wideHeading = TextStyle(44, 46, .heavy, tracking: -0.022, relativeTo: .largeTitle)

    /// The heading and the web's two actions: beside it on wide windows, under it on phones.
    @ViewBuilder
    private var greeting: some View {
        if wide {
            HStack(alignment: .bottom, spacing: Spacing.xxl) {
                greetingText.frame(maxWidth: .infinity, alignment: .leading)
                if hasUntis { greetingActions(fill: false) }
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                greetingText
                if hasUntis { greetingActions(fill: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var greetingText: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(heading)
                .textStyle(wide ? Self.wideHeading : .display)
                .foregroundStyle(Palette.textPrimary)
            Text(dateLine)
                .textStyle(wide ? .body : .callout)
                .foregroundStyle(Palette.textSecondary)
            if app.isOffline {
                let tone = Decorative.butter
                Label(s.home.offlineLine, systemImage: "wifi.slash")
                    .textStyle(TextStyle.footnote.weight(.semibold))
                    .foregroundStyle(tone.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.sm)
                    .background(tone.fill, in: .capsule)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    // Writing and reporting have no screens of their own yet, so they open the two lists.
    private func greetingActions(fill: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            GreetingAction(s.home.writeMessage, symbol: "square.and.pencil", accent: true, fill: fill) { route = .composeMessage }
            GreetingAction(s.home.reportAbsence, symbol: "person.badge.minus", accent: false, fill: fill) { route = .reportAbsence }
        }
    }

    // ── Shortcuts ───────────────────────────────────────────────────────────

    /// One decorative tone per destination, always in this order, so the grid is learnable by color.
    private var shortcuts: some View {
        let t = s.home
        let gradeNote: String? = overallAverage.map { "Ø \(fixed($0, 2)) · \(t.subjects(subjects.count))" }
        let items: [(String, Tone, String, Route, String?)] = [
            (s.nav.grades, Decorative.periwinkle, "chart.bar.fill", .grades, gradeNote),
            (t.absences, Decorative.butter, "calendar.badge.exclamationmark", .absences, absenceHours.map { t.absencesHours("\($0)") }),
            (t.todos, Decorative.sage, "checklist", .todos, todosLoaded && !todosFailed ? t.todosNote(openTodos.count) : nil),
            (t.reminders, Decorative.blush, "bell.fill", .reminders, remindersLoaded && !remindersFailed ? t.remindersNote(upcomingReminders.count) : nil),
        ]
        let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md, alignment: .top), count: wide ? 4 : 2)
        return LazyVGrid(columns: columns, spacing: Spacing.md) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                FeatureTile(item.0, subtitle: item.4, tone: item.1, symbol: item.2, minHeight: 132) { route = item.3 }
            }
        }
    }

    // ── Next exam ───────────────────────────────────────────────────────────

    /// The page's one colored block: when it is, large, then the subject and the time.
    private var examBlock: some View {
        let tone = Decorative.butter
        return PokyhSection(s.home.sectionExam) {
            if !examsLoaded {
                examPlate(tone) {
                    PokyhDesign.SkeletonBlock(height: 24).frame(width: 110)
                    PokyhDesign.SkeletonBlock(height: 44).frame(width: 150)
                    PokyhDesign.SkeletonBlock(height: 20).frame(width: 200)
                }
            } else if let exam = nextExam {
                Button {
                    TimetableJump.shared.day = exam.date
                    app.selectedTab = .timetable
                } label: {
                    examPlate(tone) { examContent(exam, tone: tone) }
                }
                .buttonStyle(PressableStyle())
            } else {
                examPlate(tone) {
                    Image(systemName: examsFailed ? "wifi.slash" : "checkmark.circle")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(tone.ink)
                    Text(examsFailed ? s.home.examOffline : s.home.noExam)
                        .textStyle(TextStyle.title2.weight(.heavy))
                        .foregroundStyle(tone.ink)
                }
            }
        }
    }

    private func examPlate<Content: View>(_ tone: Tone, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            .background(tone.fill, in: .pokyh(26))
    }

    @ViewBuilder
    private func examContent(_ exam: TimetableEntry, tone: Tone) -> some View {
        let date = Timetable.date(exam.date)
        let cal = Calendar.current
        let days = date.map { cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: $0)).day ?? 0 } ?? 0
        let when = days <= 0 ? s.home.today : days == 1 ? s.home.tomorrow : s.home.inDays(days)
        let chip = date.map {
            "\(s.common.weekdaysShort[Timetable.weekdayIndex($0)]), \(s.common.dayMonthShort(cal.component(.day, from: $0), cal.component(.month, from: $0)))"
        } ?? ""
        let meta = [exam.startTime > 0 ? Fmt.time(exam.startTime) : nil, exam.roomName.isEmpty ? nil : exam.roomName]
            .compactMap { $0 }.joined(separator: " · ")

        Text(chip)
            .textStyle(TextStyle.footnote.weight(.bold))
            .foregroundStyle(tone.ink)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(tone.ink.opacity(0.13), in: .capsule)
        VStack(alignment: .leading, spacing: 0) {
            Text(when)
                .textStyle(Self.wideHeading)
                .foregroundStyle(tone.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(exam.subjectLong.isEmpty ? (exam.subjectName.isEmpty ? s.home.exam : exam.subjectName) : exam.subjectLong)
                .textStyle(.title2)
                .underline()
                .foregroundStyle(tone.ink)
                .padding(.top, Spacing.md)
            if !meta.isEmpty {
                Text(meta)
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .foregroundStyle(tone.ink.opacity(0.8))
                    .padding(.top, 6)
            }
        }
    }

    // ── Now & next ──────────────────────────────────────────────────────────

    private var todayEntries: [TimetableEntry] {
        let today = SchoolDates.todayNum()
        return weekEntries.filter { $0.date == today }
    }

    private var nowNextBlock: some View {
        PokyhSection(s.home.sectionNowNext) {
            // Parallel lessons count once; a cancelled one isn't "now".
            let lessons = Dictionary(grouping: todayEntries.filter { !$0.isCancelled }, by: \.startTime)
                .compactMap { $0.value.first }
                .sorted { $0.startTime < $1.startTime }
            if loadingToday {
                TileRowSkeleton(rows: 1)
            } else if todayFailed && lessons.isEmpty {
                stateCard(s.home.offlineWidget, symbol: "wifi.slash", color: Brand.warning)
            } else if lessons.isEmpty {
                stateCard(s.home.noLessonsToday, symbol: "sun.max.fill", color: Brand.success)
            } else {
                TimelineView(.periodic(from: .now, by: 20)) { context in
                    nowNextCard(lessons, minute: Timetable.minuteNow(context.date))
                }
            }
        }
    }

    @ViewBuilder
    private func nowNextCard(_ lessons: [TimetableEntry], minute: Int) -> some View {
        let current = lessons.first { Fmt.minutes($0.startTime) <= minute && minute < Fmt.minutes($0.endTime) }
        let next = lessons.first { Fmt.minutes($0.startTime) > minute }
        if current == nil && next == nil {
            InlineNotice(s.home.dayOver, symbol: "checkmark.circle.fill", tint: Brand.success)
        } else {
            PokyhCard(action: { app.selectedTab = .timetable }) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let current {
                        let start = Fmt.minutes(current.startTime), end = Fmt.minutes(current.endTime)
                        let progress = min(1, max(0, Double(minute - start) / Double(max(1, end - start))))
                        lessonLine(s.home.now, current, trailing: s.home.left(duration(end - minute)), accent: Brand.accent)
                        // A thin bar is enough to read how far through the lesson is.
                        Capsule()
                            .fill(Palette.cardAlt)
                            .frame(height: 6)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule().fill(Brand.accent).frame(width: geo.size.width * progress)
                                }
                            }
                    }
                    if current != nil && next != nil { RowSeparator(inset: 0) }
                    if let next {
                        let gap = Fmt.minutes(next.startTime) - minute
                        lessonLine(current == nil ? s.home.upNext : s.home.afterThat, next,
                                   trailing: s.home.inTime(duration(gap), Fmt.time(next.startTime)), accent: Brand.orange)
                    }
                }
            }
        }
    }

    private func lessonLine(_ label: String, _ e: TimetableEntry, trailing: String, accent: Color) -> some View {
        HStack(spacing: Spacing.md) {
            bar(accent, height: 40)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                EyebrowLabel(label)
                Text(e.subjectLong.isEmpty ? (e.subjectName.isEmpty ? (e.note ?? s.home.lesson) : e.subjectName) : e.subjectLong)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                let details = [e.roomName, e.teacherName].filter { !$0.isEmpty }.joined(separator: " · ")
                if !details.isEmpty {
                    Text(details).textStyle(.footnote).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(trailing)
                .textStyle(.caption)
                .monospacedDigit()
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
        }
    }

    private func duration(_ minutes: Int) -> String {
        if minutes < 60 { return s.home.minutes(minutes) }
        if minutes % 60 == 0 { return s.home.hours(minutes / 60) }
        return s.home.hoursMinutes(minutes / 60, minutes % 60)
    }

    // ── Today ───────────────────────────────────────────────────────────────

    private var todayBlock: some View {
        PokyhSection(s.home.sectionToday) {
            let slots = Timetable.buildSlots(todayEntries)
            if loadingToday {
                TileRowSkeleton(rows: 2)
            } else if todayFailed && slots.isEmpty {
                stateCard(s.home.todayOffline, symbol: "wifi.slash", color: Brand.warning)
            } else if slots.isEmpty {
                stateCard(s.home.noLessonsToday, symbol: "sun.max.fill", color: Brand.success)
            } else {
                ForEach(Array(slots.enumerated()), id: \.element.id) { idx, slot in
                    lessonRow(slot).fadeIn(delay: Double(idx) * 0.03)
                }
            }
        }
    }

    /// Same shape and bar color as the timetable's day list, so a lesson looks alike on both.
    private func lessonRow(_ slot: MergedSlot) -> some View {
        let shown = slot.replacement ?? slot.display
        let tone: Tone = switch slot.kind {
        case .cancelled: .cancelled
        case .exam: .exam
        case .replacement: .substitution
        case .event: .event
        case .normal: .subject(shown.subjectName, hues: hues)
        }
        let meta = [shown.teacherName, shown.roomName].filter { !$0.isEmpty }.joined(separator: " · ")
        return TileRow(action: { app.selectedTab = .timetable }) {
            bar(tone.bar, height: 40)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(shown.subjectName.isEmpty ? (shown.subjectLong.isEmpty ? s.home.event : shown.subjectLong) : shown.subjectName)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .strikethrough(slot.kind == .cancelled)
                    .lineLimit(1)
                if !meta.isEmpty {
                    Text(meta).textStyle(.footnote).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(Fmt.time(shown.startTime))\n\(Fmt.time(shown.endTime))")
                .textStyle(.caption2)
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    // ── Changes ─────────────────────────────────────────────────────────────

    /// Cancellations, substitutions and room or teacher changes for today and the next school day.
    private var changes: [TimetableEntry] {
        let today = SchoolDates.todayNum()
        let nextDay = weekEntries.map(\.date).filter { $0 > today }.min()
        var days: Set<Int> = [today]
        if let nextDay { days.insert(nextDay) }
        return weekEntries
            .filter { days.contains($0.date) && isChange($0) }
            .sorted { ($0.date, $0.startTime) < ($1.date, $1.startTime) }
    }

    private func isChange(_ e: TimetableEntry) -> Bool {
        let c = Timetable.changes(e)
        return e.isCancelled || e.isSubstitution || e.isAdditional || c.room || c.teacher || c.subject
    }

    private var changesBlock: some View {
        PokyhSection(s.home.sectionChanges) {
            let list = changes
            if loadingToday {
                TileRowSkeleton(rows: 2)
            } else if todayFailed && list.isEmpty {
                stateCard(s.home.offlineWidget, symbol: "wifi.slash", color: Brand.warning)
            } else if list.isEmpty {
                InlineNotice(s.home.noChanges, symbol: "checkmark.circle.fill", tint: Brand.success)
            } else {
                PokyhCard(padding: 0, action: { app.selectedTab = .timetable }) {
                    ForEach(Array(list.prefix(5).enumerated()), id: \.offset) { index, entry in
                        if index > 0 { RowSeparator() }
                        changeRow(entry)
                    }
                    if list.count > 5 {
                        RowSeparator()
                        Text(s.home.moreInTimetable(list.count - 5))
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.accentText)
                            .padding(Spacing.card)
                    }
                }
            }
        }
    }

    private func changeRow(_ e: TimetableEntry) -> some View {
        let t = s.home
        let c = Timetable.changes(e)
        let (kind, color): (String, Color) =
            e.isCancelled ? (t.cancelled, Brand.danger)
            : (e.isSubstitution || c.teacher) ? (t.substitution, Brand.orange)
            : c.room ? (t.roomChange, Brand.warning)
            : e.isAdditional ? (t.additional, Brand.accent)
            : (t.changed, Brand.warning)
        let detail = (c.room && !e.isSubstitution && !e.isCancelled)
            ? t.room(e.roomName)
            : [e.teacherName, e.roomName].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: Spacing.md) {
            bar(color, height: 36)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(e.subjectLong.isEmpty ? (e.subjectName.isEmpty ? (e.note ?? t.lesson) : e.subjectName) : e.subjectLong)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).textStyle(.footnote).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(kind).textStyle(.caption).foregroundStyle(color)
                Text(verbatim: "\(dayLabel(e.date)) · \(Fmt.time(e.startTime))")
                    .textStyle(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(Spacing.card)
    }

    private func dayLabel(_ num: Int) -> String {
        guard let date = Timetable.date(num) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return s.home.today }
        if cal.isDateInTomorrow(date) { return s.home.tomorrow }
        return s.common.weekdaysShort[Timetable.weekdayIndex(date)]
    }

    // ── Grades ──────────────────────────────────────────────────────────────

    private struct RecentGrade: Identifiable { let id: Int; let lessonId: Int; let subject: String; let value: Double; let date: Int }

    /// The grades entered last (by id, as the web does), not the latest exam dates.
    private var recentGrades: [RecentGrade] {
        subjects.flatMap { subj in
            subj.grades.filter { $0.markDisplayValue > 0 }.map {
                RecentGrade(id: $0.id, lessonId: subj.lessonId, subject: subj.subjectName, value: $0.markDisplayValue, date: $0.date)
            }
        }
        .sorted { $0.id > $1.id }
        .prefix(3)
        .map { $0 }
    }

    /// A flat mean over every single grade, like the Grades tab.
    private var overallAverage: Double? {
        let values = subjects.flatMap { $0.grades.map(\.markDisplayValue) }.filter { $0 > 0 }
        return values.isEmpty ? nil : GradeMath.averageOf(values)
    }

    private var gradeCount: Int { subjects.flatMap { $0.grades }.filter { $0.markDisplayValue > 0 }.count }

    private var weakest: (String, Double)? {
        subjects.compactMap { subj -> (String, Double)? in
            let v = subj.grades.map(\.markDisplayValue).filter { $0 > 0 }
            return v.isEmpty ? nil : (subj.subjectName, v.reduce(0, +) / Double(v.count))
        }
        .min { $0.1 < $1.1 }
    }

    /// The web's mark tones: sage from 6, butter above 4, blush at 4 and below.
    private func markTone(_ v: Double) -> Tone {
        v >= 6 ? Decorative.sage : v > 4 ? Decorative.butter : Decorative.blush
    }

    private var gradesBlock: some View {
        PokyhSection(s.grades.recentTitle, trailing: {
            TextLinkButton(s.home.all) { app.selectedTab = .noten }
        }) {
            let grades = recentGrades
            if loadingGrades && subjects.isEmpty {
                TileRowSkeleton(rows: 3)
            } else if gradesFailed && grades.isEmpty {
                stateCard(s.home.gradesOffline, symbol: "wifi.slash", color: Brand.warning)
            } else if grades.isEmpty {
                // Kept in place at the start of a year, so the screen doesn't change shape.
                stateCard(s.home.noGrades, symbol: "tray", color: Palette.textTertiary)
            } else {
                PokyhCard(padding: Spacing.sm) {
                    ForEach(grades) { g in
                        Button { route = .gradeSubject(g.lessonId) } label: {
                            gradeRow(g)
                        }
                        .buttonStyle(.rowPress(radius: Radius.md))
                    }
                }
            }
        }
    }

    private func gradeRow(_ g: RecentGrade) -> some View {
        let tone = markTone(g.value)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(g.subject.isEmpty ? "–" : g.subject)
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: Fmt.dateShort(g.date))
                    .textStyle(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: Fmt.num(g.value))
                .textStyle(TextStyle.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tone.ink)
                .lineLimit(1)
                .padding(.horizontal, Spacing.sm)
                .frame(minWidth: 48, minHeight: 38)
                .background(tone.fill, in: .pokyh(Radius.sm))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var averageBlock: some View {
        PokyhSection(s.home.sectionAverage) {
            if loadingGrades && subjects.isEmpty {
                TileRowSkeleton(rows: 1)
            } else if let avg = overallAverage {
                PokyhCard(action: { app.selectedTab = .noten }) {
                    HStack(spacing: Spacing.lg) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            EyebrowLabel(s.home.overall)
                            Text(verbatim: Fmt.num(avg))
                                .textStyle(.statLarge)
                                .foregroundStyle(PokyhDesign.Palette.grade(avg))
                            Text(s.home.fromGrades(gradeCount)).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let weakest {
                            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                                EyebrowLabel(s.home.weakest)
                                Text(weakest.0).textStyle(.headline).foregroundStyle(Palette.textPrimary).lineLimit(1)
                                StatusLabel(Fmt.num(weakest.1), symbol: "chart.line.downtrend.xyaxis", color: PokyhDesign.Palette.grade(weakest.1))
                            }
                        }
                    }
                }
            } else {
                stateCard(gradesFailed ? s.home.offlineWidget : s.home.noGrades,
                          symbol: gradesFailed ? "wifi.slash" : "tray",
                          color: gradesFailed ? Brand.warning : Palette.textTertiary)
            }
        }
    }

    // ── Messages ────────────────────────────────────────────────────────────

    private var messagesBlock: some View {
        PokyhSection(s.nav.messages, trailing: {
            TextLinkButton(s.home.all) { route = .messages }
        }) {
            if loadingMessages && messages.isEmpty {
                TileRowSkeleton(rows: 3)
            } else if messages.isEmpty {
                stateCard(messagesFailed ? s.home.loadFailed : s.home.noMessages,
                          symbol: messagesFailed ? "wifi.slash" : "envelope",
                          color: messagesFailed ? Brand.warning : Brand.accent)
            } else {
                PokyhCard(padding: Spacing.sm) {
                    ForEach(messages.prefix(4)) { m in
                        Button { route = .message(m.id) } label: { messageRow(m) }
                            .buttonStyle(.rowPress(radius: 18))
                    }
                }
            }
        }
    }

    private func messageRow(_ m: MessagePreview) -> some View {
        HStack(spacing: 14) {
            PokyhDesign.InitialAvatar(m.senderName, color: Palette.textSecondary, size: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.subject.isEmpty ? s.messages.noSubject : m.subject)
                    .textStyle(m.isRead ? .callout : TextStyle.callout.weight(.bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(m.senderName.isEmpty ? s.messages.unknown : m.senderName)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Text(MessageFormat.dateLabel(m.sentDate, s.common)).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                if !m.isRead {
                    Circle().fill(Brand.accent).frame(width: 10, height: 10)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    // ── Mensa ───────────────────────────────────────────────────────────────

    /// Today's (or the next) dishes: the first one large with its photo and stars, the rest as rows.
    private var mensaBlock: some View {
        let title: String = {
            guard let day = mensaDay, !Calendar.current.isDateInToday(day.date) else { return s.home.mensaToday }
            return "\(s.home.mensaNext) · \(s.common.weekdays[Timetable.weekdayIndex(day.date)])"
        }()
        return PokyhSection(title, trailing: {
            TextLinkButton(s.nav.mensa) { app.selectedTab = .mensa }
        }) {
            if let day = mensaDay, let lead = day.dishes.first {
                let butter = Decorative.butter
                PokyhCard(padding: Spacing.sm) {
                    Button { route = .mensa } label: {
                        HStack(spacing: Spacing.lg) {
                            dishThumb(lead, width: 128, height: 96, radius: Radius.md, tone: butter)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(lead.name)
                                    .textStyle(TextStyle.headline.weight(.bold))
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(2)
                                ratingRow(lead)
                                if let diet = diet(lead) {
                                    let sage = Decorative.sage
                                    Text(diet)
                                        .textStyle(TextStyle.caption.weight(.bold))
                                        .foregroundStyle(sage.ink)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, 2)
                                        .background(sage.fill, in: .capsule)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(Spacing.sm)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.rowPress(radius: 18))
                    ForEach(day.dishes.dropFirst().prefix(2)) { dish in
                        Button { route = .mensa } label: {
                            HStack(spacing: Spacing.md) {
                                dishThumb(dish, width: 44, height: 44, radius: Radius.sm, tone: butter)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(dish.name)
                                        .textStyle(TextStyle.callout.weight(.semibold))
                                        .foregroundStyle(Palette.textPrimary)
                                        .lineLimit(1)
                                    ratingRow(dish)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.rowPress(radius: 18))
                    }
                }
            } else {
                TileRowSkeleton(rows: 1)
            }
        }
    }

    private func dishThumb(_ dish: Dish, width: CGFloat, height: CGFloat, radius: CGFloat, tone: Tone) -> some View {
        ZStack {
            tone.fill
            if let raw = dish.imageUrl, let url = URL(string: raw) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        dishGlyph(tone, size: width > 60 ? 30 : 18)
                    }
                }
            } else {
                dishGlyph(tone, size: width > 60 ? 30 : 18)
            }
        }
        .frame(width: width, height: height)
        .clipShape(.pokyh(radius))
    }

    private func dishGlyph(_ tone: Tone, size: CGFloat) -> some View {
        Image(systemName: "fork.knife")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(tone.ink.opacity(0.6))
    }

    /// Reserved whether or not ratings are in yet, so the card doesn't reflow when they land.
    @ViewBuilder
    private func ratingRow(_ dish: Dish) -> some View {
        let r = ratings[dish.id]
        let count = r?.count ?? 0
        HStack(spacing: 6) {
            if count > 0, let r {
                HomeStars(average: r.average)
                Text(verbatim: fixed(r.average, 1))
                    .textStyle(TextStyle.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text(verbatim: "(\(count))").textStyle(.footnote).foregroundStyle(Palette.textSecondary)
            } else if loadingRatings {
                PokyhDesign.SkeletonBlock(height: 14).frame(width: 70)
            } else {
                Text(s.home.noRatingYet).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(minHeight: 18)
    }

    /// Vegan before vegetarian, from the dish's tags.
    private func diet(_ d: Dish) -> String? {
        let tags = d.tags.map { $0.lowercased() }
        if tags.contains(where: { $0.contains("vegan") }) { return s.home.vegan }
        if tags.contains(where: { $0.contains("vegetar") }) { return s.home.vegetarian }
        return nil
    }

    // ── To-dos and reminders ────────────────────────────────────────────────

    private var openTodos: [ApiTodo] { todos.filter { !$0.done } }

    private var upcomingReminders: [ApiReminder] {
        let now = Date()
        return reminders
            .filter { (MessageFormat.parse($0.remindAt) ?? .distantFuture) >= now }
            .sorted { $0.remindAt < $1.remindAt }
    }

    private var todosBlock: some View {
        PokyhSection(s.home.sectionTodos, trailing: {
            TextLinkButton(s.home.all) { route = .todos }
        }) {
            let open = openTodos
            if !todosLoaded {
                TileRowSkeleton(rows: 2)
            } else if todosFailed && open.isEmpty {
                stateCard(s.home.offlineWidget, symbol: "wifi.slash", color: Brand.warning)
            } else if open.isEmpty {
                stateCard(s.home.allDone, symbol: "checkmark.circle", color: Brand.success)
            } else {
                PokyhCard(padding: 0, action: { route = .todos }) {
                    ForEach(Array(open.prefix(3).enumerated()), id: \.element.id) { index, todo in
                        if index > 0 { RowSeparator() }
                        compactRow("circle", tint: Palette.textTertiary, title: todo.title,
                                   trailing: todo.dueAt.flatMap(MessageFormat.parse).map { dueLabel($0, withTime: false) })
                    }
                    if open.count > 3 {
                        RowSeparator()
                        moreLine(open.count - 3)
                    }
                }
            }
        }
    }

    private var remindersBlock: some View {
        PokyhSection(s.home.sectionReminders, trailing: {
            TextLinkButton(s.home.all) { route = .reminders }
        }) {
            let upcoming = upcomingReminders
            if !remindersLoaded {
                TileRowSkeleton(rows: 2)
            } else if remindersFailed && upcoming.isEmpty {
                stateCard(s.home.offlineWidget, symbol: "wifi.slash", color: Brand.warning)
            } else if upcoming.isEmpty {
                stateCard(s.home.noReminders, symbol: "bell", color: Brand.orange)
            } else {
                PokyhCard(padding: 0, action: { route = .reminders }) {
                    ForEach(Array(upcoming.prefix(3).enumerated()), id: \.element.id) { index, reminder in
                        if index > 0 { RowSeparator() }
                        compactRow("bell.fill", tint: Brand.orange, title: reminder.title,
                                   trailing: MessageFormat.parse(reminder.remindAt).map { dueLabel($0, withTime: true) })
                    }
                    if upcoming.count > 3 {
                        RowSeparator()
                        moreLine(upcoming.count - 3)
                    }
                }
            }
        }
    }

    private func compactRow(_ symbol: String, tint: Color, title: String, trailing: String?) -> some View {
        HStack(spacing: Spacing.md) {
            IconTile(symbol, color: tint, size: 30)
            Text(title)
                .textStyle(.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing).textStyle(.caption).foregroundStyle(Brand.orange)
            }
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
    }

    private func moreLine(_ more: Int) -> some View {
        Text(s.home.moreDishes(more))
            .textStyle(.footnote)
            .foregroundStyle(Palette.accentText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.card)
            .padding(.vertical, Spacing.md)
    }

    private func dueLabel(_ date: Date, withTime: Bool) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(date) { day = s.home.today }
        else if cal.isDateInTomorrow(date) { day = s.home.tomorrow }
        else { day = s.common.dayMonthShort(cal.component(.day, from: date), cal.component(.month, from: date)) }
        let minute = Timetable.minuteNow(date)
        return withTime && minute > 0 ? "\(day) · \(Timetable.hhmm(minute))" : day
    }

    // ── Without WebUntis ────────────────────────────────────────────────────

    /// The school's blocks need a school account; this says so and leads to what works without one.
    private var noUntisBlock: some View {
        let tone = Decorative.periwinkle
        return VStack(alignment: .leading, spacing: Spacing.xxl) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(s.home.untisTitle).textStyle(TextStyle.title2.weight(.heavy)).foregroundStyle(tone.ink)
                Text(s.home.untisText).textStyle(.callout).foregroundStyle(tone.ink.opacity(0.85))
            }
            HStack(spacing: Spacing.sm) {
                ForEach(Array([(s.school.todos, Route.todos), (s.school.reminders, Route.reminders)].enumerated()), id: \.offset) { _, item in
                    Button { route = item.1 } label: {
                        Text(item.0)
                            .textStyle(TextStyle.callout.weight(.semibold))
                            .foregroundStyle(tone.fill)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(tone.ink, in: .capsule)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.fill, in: .pokyh(26))
    }

    // ── Pieces ──────────────────────────────────────────────────────────────

    private func bar(_ color: Color, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 4, height: height)
    }

    /// A block with nothing to show, or that couldn't load: a glyph and why.
    private func stateCard(_ title: String, symbol: String, color: Color) -> some View {
        PokyhCard(padding: 0) {
            StateView(title, compact: true, art: {
                IconTile(symbol, color: color, size: 52)
            })
        }
    }

    private func fixed(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: String(s.common.decimal))
    }

    // ── Loading (independent, in parallel) ─────────────────────────────────

    private func loadAll() async {
        // The Mensa comes from the backend, so it always loads; the rest needs WebUntis.
        async let mensa: () = loadMensa()
        async let tasks: () = loadTasks()
        if hasUntis {
            async let week: () = loadWeek()
            async let grades: () = loadGrades()
            async let exams: () = loadExams()
            async let inbox: () = loadMessages()
            async let absences: () = loadAbsences()
            _ = await (week, grades, exams, inbox, absences)
        }
        _ = await (mensa, tasks)
    }

    private func loadWeek() async {
        guard let session = app.session else { return }
        loadingToday = weekEntries.isEmpty
        let cal = Calendar.current
        let monday = SchoolDates.mondayISO(of: Date())
        let nextMonday = SchoolDates.mondayISO(of: cal.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        do {
            let this = try await UntisClient.shared.timetable(date: monday, session)
            let next = (try? await UntisClient.shared.timetable(date: nextMonday, session)) ?? []
            weekEntries = this + next
            hues = Timetable.hues(for: this)
            todayFailed = false
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            todayFailed = true
        }
        loadingToday = false
    }

    private func loadExams() async {
        guard let session = app.session else { return }
        do {
            let exams = try await UntisClient.shared.upcomingExams(session)
            // One that already ended today is skipped.
            let today = SchoolDates.todayNum(), minute = Timetable.minuteNow()
            nextExam = exams
                .filter { !$0.isCancelled && ($0.date > today || ($0.date == today && Fmt.minutes($0.endTime) > minute)) }
                .min { ($0.date, $0.startTime) < ($1.date, $1.startTime) }
            examsFailed = false
        } catch {
            examsFailed = true
        }
        examsLoaded = true
    }

    private func loadGrades() async {
        guard let session = app.session else { return }
        loadingGrades = subjects.isEmpty
        do {
            subjects = try await UntisClient.shared.grades(year: nil, session)
            gradesFailed = false
        } catch {
            gradesFailed = true
        }
        loadingGrades = false
    }

    private func loadMessages() async {
        guard let session = app.session else { return }
        loadingMessages = messages.isEmpty
        do {
            let inbox = try await UntisClient.shared.messages(folder: .inbox, session)
            messages = Array(inbox.prefix(4))
            app.noteInbox(inbox)
            messagesFailed = false
        } catch {
            messagesFailed = true
        }
        loadingMessages = false
    }

    private func loadAbsences() async {
        guard let session = app.session else { return }
        if let list = try? await UntisClient.shared.absences(startDate: SchoolDates.yearStart(), endDate: SchoolDates.yearEnd(), session) {
            absenceHours = list.reduce(0) { $0 + $1.hours }
        }
    }

    private func loadMensa() async {
        loadingMensa = mensaDay == nil
        defer { loadingMensa = false }
        guard let dishes = try? await BackendClient.shared.dishes() else { return }
        // Same date rule as the Mensa tab: today or the next day the menu has.
        guard let day = MensaSchedule.days(from: dishes).first(where: { !$0.dishes.isEmpty }) else {
            mensaDay = nil
            return
        }
        mensaDay = MensaDay(date: day.date, dishes: day.dishes)
        guard let token = app.session?.apiToken else { return }
        loadingRatings = true
        if let batch = try? await BackendClient.shared.dishRatingsBatch(ids: day.dishes.prefix(3).map(\.id), token: token) {
            ratings = batch
        }
        loadingRatings = false
    }

    private func loadTasks() async {
        guard let session = app.session, let token = session.apiToken else { return }
        do {
            todos = try await BackendClient.shared.todos(username: session.username, token: token)
            todosFailed = false
        } catch {
            todosFailed = true
        }
        todosLoaded = true

        do {
            var classId = session.classId
            if classId == nil { classId = try await BackendClient.shared.myClass(token: token)?.id }
            if let classId {
                reminders = try await BackendClient.shared.reminders(classId: classId, token: token)
            }
            remindersFailed = false
        } catch {
            remindersFailed = true
        }
        remindersLoaded = true
    }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Columns of a row by weight, each as tall as it wants; the row takes the tallest.
private struct WeightedRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat

    private func widths(_ total: CGFloat, count: Int) -> [CGFloat] {
        let w = (0..<count).map { $0 < weights.count ? weights[$0] : 1 }
        let sum = max(w.reduce(0, +), 1)
        let free = max(0, total - spacing * CGFloat(max(0, count - 1)))
        return w.map { free * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.replacingUnspecifiedDimensions().width
        let cols = widths(total, count: subviews.count)
        let height = zip(subviews, cols).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, w) in zip(subviews, widths(bounds.width, count: subviews.count)) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: nil))
            x += w + spacing
        }
    }
}

/// Five small stars, halves included.
private struct HomeStars: View {
    let average: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                let v = average - Double(i)
                Image(systemName: v >= 0.75 ? "star.fill" : v >= 0.25 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.star)
            }
        }
        .accessibilityHidden(true)
    }
}

// ── Arranging Home (Android's ui/home/HomeLayout.kt) ────────────────────────

/// One block of Home. The raw value is what gets stored, so a case is never renamed: a renamed
/// one would silently drop out of every saved layout. Add and retire instead.
/// `defaultVisible` decides what a block does the first time a layout meets it: the web's five
/// are on for everyone, anything later starts in "Widgets hinzufügen".
private enum HomeSection: String, CaseIterable, Identifiable {
    case shortcuts = "Shortcuts"
    case exam = "Exam"
    case grades = "Grades"
    case messages = "Messages"
    case mensa = "Mensa"
    case today = "Today"
    case nowNext = "NowNext"
    case changes = "Changes"
    case average = "Average"
    case todos = "OpenTodos"
    case reminders = "UpcomingReminders"

    var id: String { rawValue }

    var defaultVisible: Bool {
        switch self {
        case .shortcuts, .exam, .grades, .messages, .mensa: true
        default: false
        }
    }

    static var defaultOrder: [HomeSection] { allCases.filter(\.defaultVisible) }

    var symbol: String {
        switch self {
        case .shortcuts: "square.grid.2x2.fill"
        case .exam: "pencil.and.list.clipboard"
        case .grades: "chart.bar.fill"
        case .messages: "envelope.fill"
        case .mensa: "fork.knife"
        case .today: "calendar"
        case .nowNext: "clock.fill"
        case .changes: "arrow.left.arrow.right"
        case .average: "chart.line.uptrend.xyaxis"
        case .todos: "checklist"
        case .reminders: "bell.fill"
        }
    }

    func title(_ t: HomeStrings) -> String {
        switch self {
        case .shortcuts: t.sectionShortcuts
        case .exam: t.sectionExam
        case .grades: t.sectionGrades
        case .messages: t.sectionMessages
        case .mensa: t.sectionMensa
        case .today: t.sectionToday
        case .nowNext: t.sectionNowNext
        case .changes: t.sectionChanges
        case .average: t.sectionAverage
        case .todos: t.sectionTodos
        case .reminders: t.sectionReminders
        }
    }

    /// What the block is for, under its name in the arrange list.
    func info(_ t: HomeStrings) -> String {
        switch self {
        case .shortcuts: t.sectionShortcutsInfo
        case .exam: t.sectionExamInfo
        case .grades: t.sectionGradesInfo
        case .messages: t.sectionMessagesInfo
        case .mensa: t.sectionMensaInfo
        case .today: t.sectionTodayInfo
        case .nowNext: t.sectionNowNextInfo
        case .changes: t.sectionChangesInfo
        case .average: t.sectionAverageInfo
        case .todos: t.sectionTodosInfo
        case .reminders: t.sectionRemindersInfo
        }
    }
}

/// Which blocks Home shows, and in what order. `order` arranges the shown ones, `hidden` is what
/// was taken off; a block in neither is one this layout has never seen. Both by name, so a
/// layout from an older or newer build still reads back.
private struct HomeLayout: Codable, Equatable {
    var order: [String] = HomeSection.defaultOrder.map(\.rawValue)
    var hidden: [String] = []

    init() {}

    init(order: [String], hidden: [String]) {
        self.order = order
        self.hidden = hidden
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? HomeSection.defaultOrder.map(\.rawValue)
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
    }

    init(stored: String) {
        self = stored.data(using: .utf8).flatMap { try? JSONDecoder().decode(HomeLayout.self, from: $0) } ?? HomeLayout()
    }

    var stored: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private var hiddenSections: Set<HomeSection> { Set(hidden.compactMap(HomeSection.init(rawValue:))) }

    /// Every block once, saved ones first; unknown names fall out.
    private var sanitized: [HomeSection] {
        var seen = Set<HomeSection>()
        let known = order.compactMap(HomeSection.init(rawValue:)).filter { seen.insert($0).inserted }
        return known + HomeSection.allCases.filter { !seen.contains($0) }
    }

    /// The blocks to show, in order.
    var visible: [HomeSection] {
        let placed = Set(order.compactMap(HomeSection.init(rawValue:)))
        let off = hiddenSections
        return sanitized.filter { !off.contains($0) && (placed.contains($0) || $0.defaultVisible) }
    }

    /// Everything not on Home, in the enum's order.
    var available: [HomeSection] {
        let shown = Set(visible)
        return HomeSection.allCases.filter { !shown.contains($0) }
    }

    func moved(from source: IndexSet, to destination: Int) -> HomeLayout {
        var list = visible
        list.move(fromOffsets: source, toOffset: destination)
        return HomeLayout(order: list.map(\.rawValue), hidden: hidden)
    }

    func removed(_ section: HomeSection) -> HomeLayout {
        HomeLayout(order: visible.filter { $0 != section }.map(\.rawValue),
                   hidden: (hiddenSections.union([section])).map(\.rawValue).sorted())
    }

    /// Added at the end, right above where it was picked.
    func added(_ section: HomeSection) -> HomeLayout {
        HomeLayout(order: (visible.filter { $0 != section } + [section]).map(\.rawValue),
                   hidden: hiddenSections.subtracting([section]).map(\.rawValue).sorted())
    }
}

/// The blocks on Home as a list to drag into order, a minus to take one off, and below it the
/// rest with what each is for. "Standard" puts the web's five back.
private struct HomeArrangeSheet: View {
    @Binding var layout: HomeLayout
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s

    var body: some View {
        let t = s.home
        NavigationStack {
            List {
                Section {
                    if layout.visible.isEmpty {
                        Text(t.noWidgets)
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .listRowBackground(Palette.card)
                    }
                    ForEach(layout.visible) { section in
                        row(section) {
                            Button { change { layout.removed(section) } } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 22))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Brand.danger)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(t.remove(section.title(t)))
                        }
                    }
                    .onMove { from, to in change { layout.moved(from: from, to: to) } }
                } header: {
                    Text(s.nav.home)
                }

                Section {
                    if layout.available.isEmpty {
                        Label(t.allWidgetsShown, systemImage: "checkmark.circle.fill")
                            .textStyle(.callout)
                            .foregroundStyle(Brand.success)
                            .listRowBackground(Palette.card)
                    }
                    ForEach(layout.available) { section in
                        row(section) {
                            Button { change { layout.added(section) } } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Brand.accent)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(section.title(t))
                        }
                    }
                } header: {
                    Text(t.addWidgets)
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(s.nav.arrangeHome)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t.standard) { change { HomeLayout() } }
                        .disabled(layout.visible == HomeLayout().visible)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
            .sensoryFeedback(.selection, trigger: layout)
        }
        .presentationDetents([.large])
    }

    private func change(_ next: () -> HomeLayout) {
        withAnimation(.snappy(duration: 0.3)) { layout = next() }
    }

    private func row<Control: View>(_ section: HomeSection, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: Spacing.iconText) {
            control()
            IconTile(section.symbol, color: Brand.accent, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title(s.home))
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(section.info(s.home))
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .listRowBackground(Palette.card)
    }
}

/// One of the greeting's pill buttons: the accent one first, the quiet one beside it.
private struct GreetingAction: View {
    let title: String
    let symbol: String
    let accent: Bool
    let fill: Bool
    let action: () -> Void

    init(_ title: String, symbol: String, accent: Bool, fill: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.accent = accent
        self.fill = fill
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                Text(title)
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(accent ? Palette.accentText : Palette.textPrimary)
            .padding(.horizontal, fill ? Spacing.md : 18)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: 48)
            .background(accent ? Palette.accentTint : Palette.cardAlt, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(PressableStyle())
    }
}
