import SwiftUI
import PokyhCore
import PokyhDesign

/// The class page: the join code on top (it's what you open the page to read out), then what's
/// new in the class register, open absences, the exams of this and next week, the members.
struct ClassView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var klass: ApiClass?
    @State private var loading = true
    @State private var error: String?
    @State private var recentEvents: [ClassregEvent] = []
    @State private var openAbsences: [AbsenceEntry] = []
    @State private var exams: [TimetableEntry] = []
    @State private var overviewLoading = true
    @State private var route: Route?

    private enum Route: Hashable { case classreg, absences }

    private var hasBackend: Bool { app.session?.apiToken != nil }
    private var hasUntis: Bool { app.session?.hasUntis ?? false }
    private var klasseName: String { app.session?.klasseName ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if let c = klass {
                    JoinCodeCard(code: c.code).fadeIn()
                }

                if hasUntis {
                    ClassOverviewSection(s.tasks.newClassreg, subtitle: s.tasks.last3Months,
                                         emptyText: s.tasks.noClassreg3, items: recentEvents,
                                         loading: overviewLoading, onSeeAll: { route = .classreg }) { ClassregEventRow(event: $0) }
                        .fadeIn()

                    ClassOverviewSection(s.tasks.openAbsences, emptyText: s.tasks.noOpenAbsences,
                                         items: Array(openAbsences.prefix(6)), loading: overviewLoading,
                                         onSeeAll: { route = .absences }) { OpenAbsenceRow(absence: $0) } footer: {
                        if openAbsences.count > 6 {
                            TextLinkButton(s.tasks.more(openAbsences.count - 6)) { route = .absences }
                        }
                    }
                    .fadeIn(delay: 0.04)

                    examsSection.fadeIn(delay: 0.08)
                }

                members.fadeIn(delay: 0.12)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
        }
        .navigationTitle(klasseName.isEmpty ? s.tasks.myClass : s.tasks.klasseNamed(klasseName))
        .navigationSubtitle(s.common.schoolYear(SchoolDates.currentSchoolYear))
        .appBackground()
        .navigationDestination(item: $route) { route in
            switch route {
            case .classreg: ClassregEventsView()
            case .absences: AbsencesView()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // ── Exams ────────────────────────────────────────────────────────────────

    private var examsSection: some View {
        let monday = Self.monday()
        let cal = Calendar.current
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday) ?? monday
        let afterNext = cal.date(byAdding: .day, value: 14, to: monday) ?? monday
        let thisWeek = exams.filter { $0.date >= DateFmt.num(monday) && $0.date < DateFmt.num(nextMonday) }
        let nextWeek = exams.filter { $0.date >= DateFmt.num(nextMonday) && $0.date < DateFmt.num(afterNext) }

        return VStack(alignment: .leading, spacing: Spacing.headerContent) {
            SectionHeader(s.tasks.exams)
            if thisWeek.isEmpty && nextWeek.isEmpty && overviewLoading {
                ClassLoadingLines()
            } else if thisWeek.isEmpty && nextWeek.isEmpty {
                ClassEmptyLine(text: s.tasks.noExamsAhead)
            } else {
                weekBlock(s.timetable.thisWeek + " · " + range(monday), empty: s.tasks.noExamsThisWeek, items: thisWeek)
                if !nextWeek.isEmpty {
                    weekBlock(s.timetable.nextWeek + " · " + range(nextMonday), empty: s.tasks.noExamsNextWeek, items: nextWeek)
                        .padding(.top, Spacing.xs)
                }
            }
        }
    }

    private func weekBlock(_ label: String, empty: String, items: [TimetableEntry]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EyebrowLabel(label)
            if items.isEmpty {
                ClassEmptyLine(text: empty)
            } else {
                ListCard(items) { ExamRow(exam: $0) }
            }
        }
    }

    /// "27. Okt. – 31. Okt.", Monday to Friday.
    private func range(_ monday: Date) -> String {
        let cal = Calendar.current
        let friday = cal.date(byAdding: .day, value: 4, to: monday) ?? monday
        let a = cal.dateComponents([.day, .month], from: monday)
        let b = cal.dateComponents([.day, .month], from: friday)
        return s.common.dayMonthShort(a.day ?? 1, a.month ?? 1) + " – " + s.common.dayMonthShort(b.day ?? 1, b.month ?? 1)
    }

    /// Monday of this school week; on the weekend that's already next week's.
    private static func monday() -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        var day = cal.startOfDay(for: Date())
        if cal.isDateInWeekend(day), let monday = cal.nextDate(after: day, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) {
            day = monday
        }
        return cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }

    // ── Members ──────────────────────────────────────────────────────────────

    @ViewBuilder private var members: some View {
        if !hasBackend && klass == nil {
            BackendUnavailableView(feature: s.tasks.classList)
                .frame(minHeight: 240)
        } else if let error {
            ErrorStateView(message: error) { Task { await load() } }
                .frame(minHeight: 240)
        } else if let c = klass {
            PokyhSection(s.tasks.members) {
                EyebrowLabel("\(c.members.count)")
            } content: {
                ListCard(c.members) { MemberRow(member: $0) }
            }
        } else if loading {
            ClassLoadingLines()
        } else {
            StateView(s.tasks.noClass, message: s.tasks.noClassText, compact: true, art: {
                IconTile("person.3", color: Brand.accent, size: 56)
            })
        }
    }

    private func load() async {
        guard let session = app.session else { loading = false; return }
        loading = klass == nil
        error = nil
        async let overview: Void = loadOverview(session)
        if let token = session.apiToken {
            do { klass = try await BackendClient.shared.myClass(token: token) }
            catch { self.error = (error as? AppError)?.message ?? error.localizedDescription }
        }
        loading = false
        await overview
    }

    private func loadOverview(_ session: UserSession) async {
        guard session.hasUntis else { overviewLoading = false; return }
        overviewLoading = recentEvents.isEmpty && openAbsences.isEmpty && exams.isEmpty
        async let events = try? UntisClient.shared.classregEvents(year: SchoolDates.currentSchoolYear, session)
        async let absences = try? UntisClient.shared.absences(startDate: SchoolDates.yearStart(), endDate: SchoolDates.yearEnd(), session)
        async let upcoming = try? UntisClient.shared.upcomingExams(session)
        let cutoff = DateFmt.num(Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date())
        recentEvents = (await events ?? []).filter { $0.createDate >= cutoff }.sorted { $0.createDate > $1.createDate }
        openAbsences = (await absences ?? []).filter { !$0.isExcused }.sorted { $0.startDate > $1.startDate }
        exams = await upcoming ?? []
        overviewLoading = false
    }
}

/// A titled block with an optional "Alle ›", its items in one card, or one quiet line.
private struct ClassOverviewSection<Item: Identifiable, Row: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let emptyText: String
    let items: [Item]
    let loading: Bool
    let onSeeAll: (() -> Void)?
    let row: (Item) -> Row
    let footer: Footer
    @Environment(\.strings) private var s

    init(_ title: String, subtitle: String? = nil, emptyText: String, items: [Item], loading: Bool,
         onSeeAll: (() -> Void)? = nil, @ViewBuilder row: @escaping (Item) -> Row,
         @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.emptyText = emptyText
        self.items = items
        self.loading = loading
        self.onSeeAll = onSeeAll
        self.row = row
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.headerContent) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .textStyle(.title2)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle { EyebrowLabel(subtitle) }
                }
                Spacer(minLength: Spacing.sm)
                if let onSeeAll {
                    TextLinkButton(s.tasks.all, symbol: "chevron.right", action: onSeeAll)
                }
            }
            if items.isEmpty && loading {
                ClassLoadingLines()
            } else if items.isEmpty {
                ClassEmptyLine(text: emptyText)
            } else {
                ListCard(items, row: row)
                footer
            }
        }
    }
}

/// "Nothing here", recessed instead of a card so it reads as absence, not content.
private struct ClassEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .textStyle(.footnote)
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.card)
            .padding(.vertical, Spacing.lg)
            .nestedSurface(radius: Radius.lg)
    }
}

private struct ClassLoadingLines: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SkeletonBlock(height: 16, width: 180)
            SkeletonBlock(height: 14, width: 120)
        }
        .padding(Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedSurface(radius: Radius.lg)
    }
}

/// The join code: the one accent-tinted thing on the page, since people read it out.
private struct JoinCodeCard: View {
    let code: String
    @Environment(\.strings) private var s

    var body: some View {
        PokyhCard {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel(s.tasks.joinCode)
                    Text(s.tasks.joinCodeHint).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(code)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.accentText)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .accentSurface(radius: 999)
            }
        }
        .contextMenu {
            Button { UIPasteboard.general.string = code } label: {
                Label(s.profile.copy, systemImage: "doc.on.doc")
            }
            ShareLink(item: code)
        }
    }
}

/// Day and month on the left, subject, text and author, the category chip trailing.
private struct ClassregEventRow: View {
    let event: ClassregEvent
    @Environment(\.strings) private var s

    var body: some View {
        let month = event.createDate / 100 % 100
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(spacing: 0) {
                Text("\(event.createDate % 100).")
                    .textStyle(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text(s.common.monthsShort.indices.contains(month - 1) ? s.common.monthsShort[month - 1] : "")
                    .textStyle(.caption2)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                if !event.subjectName.isEmpty {
                    Text(event.subjectName).textStyle(.headline).foregroundStyle(Palette.textPrimary)
                }
                let text = event.text.isEmpty ? event.eventReasonName : event.text
                if !text.isEmpty {
                    Text(text).textStyle(.callout).foregroundStyle(Palette.textSecondary)
                }
                if !event.creatorName.isEmpty {
                    Text(event.creatorName).textStyle(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !event.categoryName.isEmpty {
                TagChip(event.categoryName, color: ClassregTone.accent(event))
            }
        }
        .padding(Spacing.card)
    }
}

/// An unexcused absence: a danger dot, the dates, "Offen".
private struct OpenAbsenceRow: View {
    let absence: AbsenceEntry
    @Environment(\.strings) private var s

    var body: some View {
        let range = absence.startDate != absence.endDate
            ? "\(Fmt.dateShort(absence.startDate)) – \(Fmt.dateShort(absence.endDate))"
            : Fmt.dateShort(absence.startDate)
        let sub = [absence.subjectName, absence.reasonName].compactMap { $0 }.first { !$0.isEmpty }
        HStack(spacing: Spacing.md) {
            Circle().fill(Brand.danger).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(range).textStyle(.headline).monospacedDigit().foregroundStyle(Palette.textPrimary)
                if let sub {
                    Text(sub).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TagChip(s.tasks.open, color: Brand.danger)
        }
        .padding(Spacing.card)
    }
}

/// Weekday and day on the left, subject, time and room, "Prüfung" trailing.
private struct ExamRow: View {
    let exam: TimetableEntry
    @Environment(\.strings) private var s

    var body: some View {
        let weekday = Self.weekday(exam.date)
        let room = exam.roomName.isEmpty ? "" : " · \(exam.roomName)"
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(spacing: 0) {
                Text(s.common.weekdaysShort.indices.contains(weekday) ? s.common.weekdaysShort[weekday] : "")
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textTertiary)
                Text("\(exam.date % 100).")
                    .textStyle(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.subjectLong.isEmpty ? (exam.subjectName.isEmpty ? s.tasks.exam : exam.subjectName) : exam.subjectLong)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(Fmt.time(exam.startTime)) – \(Fmt.time(exam.endTime))\(room)")
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                if let note = exam.examDescription, !note.isEmpty {
                    Text(note).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TagChip(s.tasks.exam, color: Brand.warning)
        }
        .padding(Spacing.card)
    }

    /// 0 = Monday.
    private static func weekday(_ n: Int) -> Int {
        var c = DateComponents()
        c.year = n / 10000; c.month = n / 100 % 100; c.day = n % 100
        guard let date = Calendar.current.date(from: c) else { return 0 }
        return (Calendar.current.component(.weekday, from: date) + 5) % 7
    }
}

/// A member that opens to show what the class record knows about them.
private struct MemberRow: View {
    let member: ApiClassMember
    @Environment(\.strings) private var s
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(Motion.standardEase) { expanded.toggle() }
            } label: {
                HStack(spacing: Spacing.iconText) {
                    InitialAvatar(name: member.username, size: 38, colorSeed: member.username)
                    Text(member.username)
                        .textStyle(.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(minHeight: 60)
                .padding(.horizontal, Spacing.card)
                .padding(.vertical, Spacing.md)
                .contentShape(.rect)
            }
            .buttonStyle(.rowPress)
            .accessibilityHint(expanded ? s.tasks.collapse : s.tasks.expand)

            if expanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    detail(s.tasks.username, member.username)
                    if let joined = member.joinedAt, !joined.isEmpty {
                        detail(s.tasks.joined, String(joined.prefix(10)))
                    }
                    detail("POKYH ID", member.stableUid)
                }
                .padding(.horizontal, Spacing.card)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.nested)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(label).textStyle(.caption).foregroundStyle(Palette.textTertiary).frame(width: 104, alignment: .leading)
            Text(value)
                .textStyle(.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
