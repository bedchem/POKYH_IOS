import SwiftUI
import QuickLook
import PokyhCore
import PokyhDesign

// Abwesenheiten as on Android: the absence rate as the hero, missed time per month as bars that
// jump to the month, then the absences grouped by month. Missed time comes from the real
// timetable (the lessons inside each absence), not WebUntis' `hours`, and is shown in
// 60-minute hours like the web.

// ── Lesson calendar (the web's lib/absence-calc.ts) ─────────────────────────

private struct Lesson { var start: Int; var end: Int }

/// The lessons of a school year, per week (its Monday, yyyy-MM-dd), per day (yyyyMMdd).
private struct LessonCalendar {
    var weeks: [String: [Int: [Lesson]]] = [:]
    var failed: Set<String> = []
}

private struct AbsenceFigures {
    var perAbsence: [Int: Int] = [:]
    var minutes = 0
    var excusedMinutes = 0
    /// Lesson minutes so far (or the whole year); nil until every week is loaded.
    var possible: Int?
    var rate: Double?
}

private enum AbsenceCalc {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }()

    /// WebUntis gives times as HHMM or as minutes of the day; HHMM can't have more than 59 minutes.
    static func toMinutes(_ t: Int) -> Int {
        if t == 0 { return 0 }
        if t > 2359 || t % 100 > 59 { return t }
        return (t / 100) * 60 + t % 100
    }

    static func date(_ n: Int) -> Date? {
        cal.date(from: DateComponents(year: n / 10000, month: (n / 100) % 100, day: n % 100))
    }

    static func num(_ d: Date) -> Int {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    static func monday(_ d: Date) -> Date {
        let weekday = cal.component(.weekday, from: d)   // 1 = Sunday
        return cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: cal.startOfDay(for: d)) ?? d
    }

    /// Up to now, or to the end of 30 June for the whole year and for years that are over.
    static func countUntil(_ year: Int, whole: Bool, now: Date = Date()) -> Date {
        let end = cal.date(from: DateComponents(year: year + 1, month: 6, day: 30, hour: 23, minute: 59)) ?? now
        return !whole && now < end ? now : end
    }

    /// The Mondays from 1 September up to now (whole: up to 30 June).
    static func schoolYearWeeks(_ year: Int, whole: Bool) -> [String] {
        guard let sep = date(year * 10000 + 901) else { return [] }
        let until = countUntil(year, whole: whole)
        var out: [String] = []
        var d = monday(sep)
        while d <= until {
            out.append(DateFmt.isoString(d))
            d = cal.date(byAdding: .day, value: 7, to: d) ?? until.addingTimeInterval(1)
        }
        return out
    }

    /// The Mondays of the weeks the absences touch.
    static func absenceWeeks(_ absences: [AbsenceEntry]) -> [String] {
        var out = Set<String>()
        for a in absences {
            guard let start = date(a.startDate), let end = date(a.endDate) else { continue }
            var d = monday(start)
            var n = 0
            // Longer than 60 weeks is a typo in the dates, not an absence.
            while d <= end && n < 60 {
                out.insert(DateFmt.isoString(d))
                d = cal.date(byAdding: .day, value: 7, to: d) ?? end.addingTimeInterval(1)
                n += 1
            }
        }
        return Array(out)
    }

    /// A week as lessons per day: cancelled and subject-less entries left out, overlaps merged.
    static func lessons(_ entries: [TimetableEntry]) -> [Int: [Lesson]] {
        var byDay: [Int: [Lesson]] = [:]
        for e in entries where !e.isCancelled && !(e.subjectName.isEmpty && e.subjectLong.isEmpty) {
            let start = toMinutes(e.startTime), end = toMinutes(e.endTime)
            if end > start { byDay[e.date, default: []].append(Lesson(start: start, end: end)) }
        }
        return byDay.mapValues { slots in
            var merged: [Lesson] = []
            for s in slots.sorted(by: { $0.start < $1.start }) {
                // Only overlaps merge; back-to-back lessons each count once they're over.
                if let last = merged.last, s.start < last.end {
                    merged[merged.count - 1].end = max(last.end, s.end)
                } else {
                    merged.append(s)
                }
            }
            return merged
        }
    }

    static func hasWholeYear(_ c: LessonCalendar, _ year: Int, whole: Bool) -> Bool {
        schoolYearWeeks(year, whole: whole).allSatisfy { c.weeks[$0] != nil }
    }

    /// Every lesson from 1 September that has ended (whole: up to 30 June).
    static func possibleMinutes(_ c: LessonCalendar, _ year: Int, whole: Bool) -> Int {
        let from = year * 10000 + 901
        let until = countUntil(year, whole: whole)
        let today = num(until)
        let parts = cal.dateComponents([.hour, .minute], from: until)
        let clock = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        var total = 0
        for week in c.weeks.values {
            for (day, slots) in week where day >= from && day <= today {
                for s in slots where day < today || s.end <= clock { total += s.end - s.start }
            }
        }
        return total
    }

    /// The lesson minutes inside an absence; nil while one of its weeks is missing.
    static func minutesFromLessons(_ a: AbsenceEntry, _ c: LessonCalendar) -> Int? {
        guard var d = date(a.startDate), let end = date(a.endDate) else { return nil }
        let multiDay = a.startDate != a.endDate
        let absStart = toMinutes(a.startTime), absEnd = toMinutes(a.endTime)
        var total = 0
        var n = 0
        while d <= end && n < 420 {
            guard let week = c.weeks[DateFmt.isoString(monday(d))] else { return nil }
            let day = num(d)
            for s in week[day] ?? [] {
                var from = s.start, to = s.end
                // The times belong to the first and last day; the days between count whole.
                if absStart > 0 && (!multiDay || day == a.startDate) { from = max(from, absStart) }
                if absEnd > 0 && (!multiDay || day == a.endDate) { to = min(to, absEnd) }
                if to > from { total += to - from }
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? end.addingTimeInterval(1)
            n += 1
        }
        return total
    }

    /// The most common lesson length in the timetable; 50 when there is none.
    static func usualLesson(_ c: LessonCalendar) -> Int {
        var count: [Int: Int] = [:]
        for week in c.weeks.values { for slots in week.values { for s in slots { count[s.end - s.start, default: 0] += 1 } } }
        return count.max { $0.value < $1.value }?.key ?? 50
    }

    static func figures(_ absences: [AbsenceEntry], _ c: LessonCalendar, _ year: Int, whole: Bool) -> AbsenceFigures {
        var f = AbsenceFigures()
        let lesson = usualLesson(c)
        for a in absences {
            let m = minutesFromLessons(a, c) ?? a.hours * lesson
            f.perAbsence[a.id] = m
            f.minutes += m
            if a.isExcused { f.excusedMinutes += m }
        }
        if hasWholeYear(c, year, whole: whole) {
            let possible = possibleMinutes(c, year, whole: whole)
            f.possible = possible
            f.rate = possible > 0 ? min(100, Double(f.minutes) / Double(possible) * 100) : nil
        }
        return f
    }
}

/// "3h" rounded, "3h 20m" exact.
private func formatAbsence(_ m: Int, exact: Bool) -> String {
    if !exact { return "\(Int((Double(m) / 60).rounded()))h" }
    let h = m / 60, min = m % 60
    return min == 0 ? "\(h)h" : "\(h)h \(min)m"
}

private struct MonthGroup: Identifiable {
    let id: String
    let label: String
    let entries: [AbsenceEntry]
    let totalMinutes: Int
}

// ── Screen ──────────────────────────────────────────────────────────────────

struct AbsencesView: View {
    /// Opened from Home's "Abwesenheit melden": the report sheet once reporting is allowed.
    var openReport = false

    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var absences: [AbsenceEntry] = []
    @State private var calendar = LessonCalendar()
    @State private var figures = AbsenceFigures()
    @State private var loading = true
    @State private var calcBusy = false
    @State private var error: String?
    @State private var year = SchoolDates.currentSchoolYear
    @State private var exact = false
    @State private var wholeYear = false
    @State private var canReport = false
    @State private var reporting = false
    @State private var reportOpened = false
    @State private var excusing: AbsenceEntry?
    // Excuses found in "Gesendet", and those sent just now; "Gesendet" wins, it knows the message.
    @State private var excuses: [SentExcuse] = []
    @State private var sentNow: [SentExcuse] = []
    @State private var letterLoading = false
    @State private var letterError: String?
    @State private var letterURL: URL?
    @State private var letterFile: URL?
    @State private var openMessage: Int?

    private var canWhole: Bool { year == SchoolDates.currentSchoolYear }
    private func fmt(_ m: Int) -> String { formatAbsence(m, exact: exact) }

    private var groups: [MonthGroup] {
        var map: [String: [AbsenceEntry]] = [:]
        for e in absences where e.startDate > 10_000_000 {
            map[String(format: "%04d-%02d", e.startDate / 10000, (e.startDate / 100) % 100), default: []].append(e)
        }
        return map.map { key, entries in
            let parts = key.split(separator: "-")
            let month = Int(parts[1]) ?? 1
            let name = s.common.months.indices.contains(month - 1) ? s.common.months[month - 1] : ""
            let total = entries.reduce(0) { $0 + (figures.perAbsence[$1.id] ?? 0) }
            return MonthGroup(id: key, label: "\(name) \(parts[0])", entries: entries.sorted { $0.startDate > $1.startDate }, totalMinutes: total)
        }
        .sorted { $0.id > $1.id }
    }

    var body: some View {
        Group {
            if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else {
                content
            }
        }
        .navigationTitle(s.absences.title)
        .navigationSubtitle(s.common.schoolYear(year))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: Motion.fast)) { exact.toggle() }
                } label: {
                    Label(exact ? s.absences.exact : s.absences.rounded, systemImage: exact ? "clock.badge.checkmark" : "clock")
                        .labelStyle(.titleAndIcon)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $year) {
                        ForEach(SchoolDates.availableYears, id: \.self) { y in
                            Text("\(String(y))/\(String((y + 1) % 100))").tag(y)
                        }
                    } label: { EmptyView() }
                } label: {
                    Text("\(String(year))/\(String((year + 1) % 100))")
                }
            }
        }
        .appBackground()
        .task(id: year) {
            wholeYear = false
            await load()
        }
        .task { await loadPermissions() }
        .onChange(of: canReport) {
            if openReport && canReport && !reportOpened {
                reportOpened = true
                reporting = true
            }
        }
        .sheet(isPresented: $reporting) {
            ReportAbsenceSheet { await load() }
        }
        .sheet(item: $excusing) { a in
            ExcuseAbsenceSheet(absence: a, summary: [AbsenceText.title(a, s.common), AbsenceText.sub(a)].filter { !$0.isEmpty }.joined(separator: " · ")) { result in
                if let sent = result.excuse { sentNow.append(sent) }
                // Saved in WebUntis instead of a message: the absence itself changed.
                if result.viaMessage { await loadExcuses() } else { await load() }
            }
        }
        .navigationDestination(item: $openMessage) { id in
            MessageDetailScreen(preview: MessagePreview(id: id, subject: "", contentPreview: "", senderName: "", senderId: 0,
                                                        sentDate: "", isRead: true, hasAttachments: false), folder: .sent)
        }
        .quickLookPreview($letterURL)
        .onDisappear {
            guard letterURL == nil, let letterFile else { return }
            AttachmentFiles.discard([letterFile])
            self.letterFile = nil
        }
    }

    private var allExcuses: [SentExcuse] {
        excuses + sentNow.filter { n in !excuses.contains { $0.start == n.start && $0.end == n.end } }
    }

    private var content: some View {
        let groups = groups
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    rateCard.fadeIn()
                    MonthBars(year: year, groups: groups, fmt: fmt) { key in
                        withAnimation(.easeInOut(duration: Motion.slow)) { proxy.scrollTo(key, anchor: .top) }
                    }
                    .fadeIn(delay: 0.03)
                    actions.fadeIn(delay: 0.04)
                    NavigationLink {
                        AbsenceCalculatorView(
                            absent: canWhole ? Double(figures.minutes) / 60 : nil,
                            total: canWhole ? soFarMinutes.map { Double($0) / 60 } : nil,
                            yearTotal: canWhole ? wholeYearMinutes.map { Double($0) / 60 } : nil
                        )
                    } label: {
                        ButtonLabel(s.absences.calc, symbol: "percent")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary(compact: true))
                    .fadeIn(delay: 0.05)

                    if absences.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.seal")
                                .font(.system(size: 34))
                                .foregroundStyle(Palette.textTertiary)
                            Text(s.absences.emptyTitle).textStyle(.headline).foregroundStyle(Palette.textPrimary)
                            Text(s.absences.emptySubtitle).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.card)
                        .cardSurface(radius: Radius.xl, fill: Palette.card)
                    }

                    ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                        VStack(alignment: .leading, spacing: Spacing.headerContent) {
                            SectionHeader(group.label) { EyebrowLabel(fmt(group.totalMinutes)) }
                            VStack(spacing: 0) {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, a in
                                    if i > 0 { RowSeparator(inset: Spacing.card).padding(.trailing, Spacing.card) }
                                    let sent = a.isExcused ? nil : AbsenceText.sentExcuse(for: a, in: allExcuses)
                                    AbsenceRow(absence: a, label: fmt(figures.perAbsence[a.id] ?? 0), sent: sent,
                                               canExcuse: canReport && !a.isExcused && sent == nil,
                                               onExcuse: { excusing = a },
                                               onOpenMessage: { openMessage = $0 })
                                }
                            }
                            .cardSurface(radius: Radius.xl, fill: Palette.card)
                        }
                        .padding(.top, Spacing.sm)
                        .id(group.id)
                        .fadeIn(delay: min(0.4, 0.07 + Double(idx) * 0.03))
                    }
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xxxl)
            }
            .refreshable { await load() }
        }
    }

    // ── Melden, Entschuldigungsschreiben ────────────────────────────────────

    @ViewBuilder private var actions: some View {
        let hasOpen = absences.contains { !$0.isExcused }
        if canReport || hasOpen || letterError != nil {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if canReport {
                    Button { reporting = true } label: {
                        ButtonLabel(s.absences.report, symbol: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                }
                if hasOpen {
                    // A butter banner, as on the web: the open absences' letter, as WebUntis prints it.
                    let tone = Decorative.butter
                    Button { Task { await fetchLetter() } } label: {
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.absences.letter).textStyle(.headline).foregroundStyle(tone.ink)
                                Text(s.absences.letterHint).textStyle(.footnote).foregroundStyle(tone.ink.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if letterLoading {
                                ProgressView().tint(tone.ink)
                            } else {
                                Image(systemName: "doc.richtext").font(.system(size: 20, weight: .medium)).foregroundStyle(tone.ink)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .background(tone.fill, in: .pokyh(Radius.xl))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.rowPress(radius: Radius.xl))
                    .disabled(letterLoading)
                }
                if let letterError {
                    Text(letterError).textStyle(.footnote).foregroundStyle(Brand.danger)
                }
            }
            .sensoryFeedback(.success, trigger: letterURL) { _, url in url != nil }
        }
    }

    // ── Fehlquote ───────────────────────────────────────────────────────────

    private var rateCard: some View {
        let total = figures.minutes
        let excused = figures.excusedMinutes
        let unexcused = total - excused
        let whole = wholeYear && canWhole
        let rate = figures.rate
        let rateColor: Color = {
            guard let rate else { return Palette.textTertiary }
            if rate < 5 { return Brand.success }
            if rate < 15 { return Decorative.butter.ink }
            return Brand.danger
        }()
        let rateText: String? = {
            if let possible = figures.possible {
                return whole ? s.absences.ofLessonsYear(fmt(total), fmt(possible)) : s.absences.ofLessons(fmt(total), fmt(possible))
            }
            return calcBusy ? s.absences.rateCounting : nil
        }()
        let share = total > 0 ? Double(excused) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowLabel(s.absences.rate, color: Palette.textSecondary)
                Spacer(minLength: Spacing.sm)
                if canWhole {
                    PokyhSegmentedControl([false, true], selection: Binding(get: { wholeYear }, set: { setWholeYear($0) })) {
                        $0 ? s.absences.spanYear : s.absences.spanSoFar
                    }
                    .frame(maxWidth: 220)
                }
            }
            Group {
                if let rate {
                    Text("\(String(format: "%.1f", rate).replacingOccurrences(of: ".", with: String(s.common.decimal))) %")
                        .textStyle(.statLarge)
                        .foregroundStyle(rateColor)
                        .contentTransition(.numericText())
                } else if calcBusy {
                    SkeletonBlock(height: 44, width: 150)
                } else {
                    Text("–").textStyle(.statLarge).foregroundStyle(rateColor)
                }
            }
            .padding(.top, Spacing.sm)
            Group {
                if let rateText {
                    Text(rateText).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                } else {
                    HStack(spacing: Spacing.xs) {
                        Text(s.absences.rateMissing).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                        Button(s.absences.rateRetry) { Task { await refreshCalendar(whole: whole) } }
                            .textStyle(TextStyle.footnote.weight(.semibold))
                            .underline()
                            .foregroundStyle(Palette.textPrimary)
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, Spacing.sm)

            // Excused against unexcused.
            GeometryReader { geo in
                let gap: CGFloat = share > 0 && unexcused > 0 ? 3 : 0
                HStack(spacing: gap) {
                    if share > 0 { Capsule().fill(Brand.success).frame(width: max(0, (geo.size.width - gap) * share)) }
                    if unexcused > 0 { Capsule().fill(Brand.danger) }
                }
                .frame(width: geo.size.width, height: 10, alignment: .leading)
                .background(Palette.cardAlt, in: .capsule)
                .animation(.easeOut(duration: 0.7), value: share)
            }
            .frame(height: 10)
            .padding(.top, Spacing.xl)

            HStack(alignment: .top, spacing: Spacing.md) {
                figure(s.absences.totalMissed, fmt(total), dot: nil, valueColor: Palette.textPrimary)
                figure(s.absences.excused, fmt(excused), dot: Brand.success, valueColor: Palette.textPrimary)
                figure(s.absences.unexcused, fmt(unexcused), dot: Brand.danger, valueColor: unexcused > 0 ? Brand.danger : Palette.textPrimary)
            }
            .padding(.top, Spacing.lg)
        }
        .padding(Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.xl, fill: Palette.card)
    }

    private func figure(_ label: String, _ value: String, dot: Color?, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(label).textStyle(.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
            }
            Text(value).textStyle(TextStyle.title3.tabularDigits).foregroundStyle(valueColor).lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Loading ─────────────────────────────────────────────────────────────

    private var soFarMinutes: Int? {
        AbsenceCalc.hasWholeYear(calendar, year, whole: false) ? AbsenceCalc.possibleMinutes(calendar, year, whole: false) : nil
    }

    private var wholeYearMinutes: Int? {
        AbsenceCalc.hasWholeYear(calendar, year, whole: true) ? AbsenceCalc.possibleMinutes(calendar, year, whole: true) : nil
    }

    private func loadPermissions() async {
        guard let session = app.session, session.hasUntis, !app.isOffline else { return }
        async let excused: Void = loadExcuses()
        canReport = await UntisClient.shared.canReportAbsence(session)
        await excused
    }

    private func loadExcuses() async {
        guard let session = app.session else { return }
        if let list = try? await UntisClient.shared.sentExcuses(session) { excuses = list }
    }

    /// The year's letter for the open absences, shown in QuickLook (which also shares it).
    private func fetchLetter() async {
        guard let session = app.session, !letterLoading else { return }
        letterLoading = true
        letterError = nil
        defer { letterLoading = false }
        let open = absences.filter { !$0.isExcused }.map(\.id)
        do {
            let file = try await UntisClient.shared.excuseLetter(startDate: year * 10000 + 901, endDate: (year + 1) * 10000 + 630,
                                                                 absenceIds: open, session)
            if let old = letterFile { AttachmentFiles.discard([old]) }
            guard let url = AttachmentFiles.write(file) else { letterError = s.absences.letterFailed; return }
            letterFile = url
            letterURL = url
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch {
            letterError = (error as? AppError)?.message ?? s.absences.letterFailed
        }
    }

    private func recompute() {
        figures = AbsenceCalc.figures(absences, calendar, year, whole: wholeYear && canWhole)
    }

    private func setWholeYear(_ whole: Bool) {
        wholeYear = whole
        recompute()
        // The weeks still to come are only needed for the whole year.
        if whole && !AbsenceCalc.hasWholeYear(calendar, year, whole: true) {
            Task { await refreshCalendar(whole: true) }
        }
    }

    private func load() async {
        guard let session = app.session else { return }
        if absences.isEmpty { loading = true }
        error = nil
        do {
            absences = try await UntisClient.shared.absences(
                startDate: SchoolDates.yearStart(year), endDate: SchoolDates.yearEnd(year), session)
            calendar = LessonCalendar()
            recompute()
            loading = false
            await refreshCalendar(whole: wholeYear && canWhole)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    /// Loads the timetable weeks still missing, six at a time; failed weeks are tried again next time.
    private func refreshCalendar(whole: Bool) async {
        guard let session = app.session else { return }
        let wanted = Array(Set(AbsenceCalc.schoolYearWeeks(year, whole: whole) + AbsenceCalc.absenceWeeks(absences)))
            .filter { calendar.weeks[$0] == nil }
            .sorted()
        guard !wanted.isEmpty else { recompute(); return }
        let forYear = year
        calcBusy = true
        defer { calcBusy = false }
        do {
            let loaded = try await Self.fetchWeeks(wanted, session)
            guard forYear == year else { return }
            for (monday, days) in loaded.weeks { calendar.weeks[monday] = days }
            calendar.failed = loaded.failed
            recompute()
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            recompute()
        }
    }

    private static func fetchWeeks(_ mondays: [String], _ s: UserSession) async throws -> LessonCalendar {
        var out = LessonCalendar()
        try await withThrowingTaskGroup(of: (String, [TimetableEntry]?).self) { group in
            var next = 0
            func start(_ monday: String) {
                group.addTask {
                    do { return (monday, try await UntisClient.shared.timetable(date: monday, s)) }
                    catch let e as AppError where e.message == "session_expired" { throw e }
                    catch { return (monday, nil) }
                }
            }
            while next < min(6, mondays.count) { start(mondays[next]); next += 1 }
            while let (monday, entries) = try await group.next() {
                if let entries { out.weeks[monday] = AbsenceCalc.lessons(entries) } else { out.failed.insert(monday) }
                if next < mondays.count { start(mondays[next]); next += 1 }
            }
        }
        return out
    }
}

// ── Per month ───────────────────────────────────────────────────────────────

/// September to June, missed time per month; a bar jumps to its month.
private struct MonthBars: View {
    let year: Int
    let groups: [MonthGroup]
    let fmt: (Int) -> String
    let onPick: (String) -> Void
    @Environment(\.strings) private var s
    @State private var grown = false

    private struct Bar: Identifiable { let id: String; let minutes: Int; let future: Bool; let label: String }

    var body: some View {
        let today = SchoolDates.todayNum()
        let months = ([9, 10, 11, 12].map { (year, $0) } + (1...6).map { (year + 1, $0) })
        let bars = months.map { pair -> Bar in
            let (y, m) = pair
            let key = String(format: "%04d-%02d", y, m)
            let label = s.common.monthsShort.indices.contains(m - 1) ? s.common.monthsShort[m - 1] : ""
            return Bar(
                id: key,
                minutes: groups.first { $0.id == key }?.totalMinutes ?? 0,
                future: y * 10000 + m * 100 + 1 > today,
                label: label.hasSuffix(".") ? String(label.dropLast()) : label
            )
        }
        let maxMinutes = max(1, bars.map(\.minutes).max() ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            EyebrowLabel(s.absences.perMonth, color: Palette.textSecondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.element.id) { i, bar in
                    let has = bar.minutes > 0
                    Button { onPick(bar.id) } label: {
                        VStack(spacing: Spacing.xs) {
                            Spacer(minLength: 0)
                            Text(has ? fmt(bar.minutes) : "")
                                .textStyle(TextStyle.caption2.tabularDigits)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                            GeometryReader { geo in
                                let fraction = has ? max(0.08, Double(bar.minutes) / Double(maxMinutes)) : 0
                                VStack {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: Radius.xs / 2, style: .continuous)
                                        .fill(has ? Brand.accent : Palette.cardAlt.opacity(bar.future ? 0.5 : 1))
                                        .frame(height: has ? geo.size.height * (grown ? fraction : 0.02) : 4)
                                        .animation(.easeOut(duration: 0.5).delay(Double(i) * 0.03), value: grown)
                                }
                            }
                            .frame(height: 112)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!has)
                }
            }
            .frame(height: 150)
            .padding(.top, Spacing.lg)
            HStack(spacing: 6) {
                ForEach(bars) { bar in
                    Text(bar.label)
                        .textStyle(TextStyle.caption2.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary.opacity(bar.future ? 0.6 : 1))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, Spacing.sm)
        }
        .padding(Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.xl, fill: Palette.card)
        .onAppear { grown = true }
    }
}

// ── Absence row ─────────────────────────────────────────────────────────────

struct AbsenceRow: View {
    let absence: AbsenceEntry
    let label: String
    /// An excuse sent to the class teachers for it, waiting for them.
    var sent: SentExcuse? = nil
    var canExcuse = false
    var onExcuse: (() -> Void)? = nil
    var onOpenMessage: ((Int) -> Void)? = nil
    @Environment(\.strings) private var s

    var body: some View {
        // Excused in WebUntis, an excuse sent and waiting, or open.
        let tone = absence.isExcused ? Decorative.sage : sent != nil ? Decorative.butter : Decorative.blush
        let start = AbsenceCalc.date(absence.startDate)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.md) {
                // The day as a tile in the status tone.
                VStack(spacing: 0) {
                    Text(String(absence.startDate % 100))
                        .textStyle(TextStyle.headline.tabularDigits)
                        .foregroundStyle(tone.ink)
                    Text(weekdayShort(start).uppercased())
                        .textStyle(TextStyle.caption2.weight(.semibold))
                        .foregroundStyle(tone.ink.opacity(0.8))
                }
                .frame(width: 48, height: 48)
                .background(tone.fill, in: .pokyh(Radius.md))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top) {
                        Text(AbsenceText.title(absence, s.common)).textStyle(.headline).foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(label).textStyle(TextStyle.headline.tabularDigits).foregroundStyle(Palette.textPrimary)
                    }
                    let sub = AbsenceText.sub(absence)
                    if !sub.isEmpty {
                        Text(sub).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    let extra = [absence.reasonName, absence.note].compactMap { $0 }.filter { !$0.isEmpty }
                    if !extra.isEmpty {
                        Text(extra.joined(separator: " · ")).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    if let sent, let line = sentLine(sent) {
                        Text(line).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            HStack(spacing: Spacing.sm) {
                if let sent {
                    // Stays until the class teachers mark it excused; opens the message.
                    chip(s.absences.exSent, symbol: "paperplane.fill", tone: tone,
                         action: sent.messageId.flatMap { id in onOpenMessage.map { open in { open(id) } } })
                } else {
                    chip(absence.isExcused ? s.absences.statusExcused : s.absences.statusOpen,
                         symbol: absence.isExcused ? "checkmark.circle.fill" : "xmark.circle.fill", tone: tone, action: nil)
                }
                // As in WebUntis: only who may report absences excuses them.
                if canExcuse, let onExcuse {
                    chip(s.absences.exAction, symbol: nil, tone: Decorative.periwinkle, action: onExcuse)
                }
            }
            .padding(.leading, 48 + Spacing.md)
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func chip(_ text: String, symbol: String?, tone: Tone, action: (() -> Void)?) -> some View {
        let content = HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            }
            Text(text).textStyle(TextStyle.footnote.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(tone.ink)
        .padding(.horizontal, Spacing.md)
        .frame(height: 32)
        .background(tone.fill, in: .capsule)
        if let action {
            Button(action: action) { content.contentShape(.capsule) }
                .buttonStyle(.rowPress(radius: 16))
        } else {
            content
        }
    }

    private func sentLine(_ e: SentExcuse) -> String? {
        let names = e.recipients.joined(separator: ", ")
        let date = MessageFormat.parse(e.sentAt).map {
            let c = Calendar.current.dateComponents([.day, .month], from: $0)
            return s.common.dayMonthShort(c.day ?? 1, c.month ?? 1)
        } ?? ""
        if !names.isEmpty && !date.isEmpty { return s.absences.exSentTo(names, date) }
        if !names.isEmpty { return s.absences.exDoneTo(names) }
        return date.isEmpty ? nil : date
    }

    private func weekdayShort(_ d: Date?) -> String {
        guard let i = AbsenceText.weekdayIndex(d), s.common.weekdaysShort.indices.contains(i) else { return "" }
        return s.common.weekdaysShort[i]
    }
}

/// How an absence reads: the title, the times line, and which excuse belongs to it.
enum AbsenceText {
    static func weekdayIndex(_ d: Date?) -> Int? {
        guard let d else { return nil }
        return (AbsenceCalc.cal.component(.weekday, from: d) + 5) % 7   // Monday = 0
    }

    /// "Mittwoch, 17. Dezember" for one day, "17. Dez. – 19. Dez." for several.
    static func title(_ a: AbsenceEntry, _ c: CommonStrings) -> String {
        let sd = a.startDate % 100, sm = (a.startDate / 100) % 100
        guard (1...12).contains(sm) else { return Fmt.dateShort(a.startDate) }
        if a.startDate != a.endDate {
            let ed = a.endDate % 100, em = (a.endDate / 100) % 100
            guard (1...12).contains(em) else { return Fmt.dateShort(a.startDate) }
            return "\(c.dayMonthShort(sd, sm)) – \(c.dayMonthShort(ed, em))"
        }
        guard let i = weekdayIndex(AbsenceCalc.date(a.startDate)), c.weekdays.indices.contains(i) else {
            return c.dayMonth(sd, sm)
        }
        let weekday = c.weekdays[i]
        return "\(weekday.prefix(1).uppercased())\(weekday.dropFirst()), \(c.dayMonth(sd, sm))"
    }

    static func sub(_ a: AbsenceEntry) -> String {
        var parts: [String] = []
        if a.startTime != 0 || a.endTime != 0 {
            parts.append("\(time(a.startTime)) – \(time(a.endTime))")
        }
        if let sub = a.subjectName, !sub.isEmpty { parts.append(sub) }
        if let t = a.teacherName, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    static func time(_ t: Int) -> String {
        if t == 0 { return "" }
        let m = AbsenceCalc.toMinutes(t)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// From and to as YYYYMMDDHHMM, a day without times running to 23:59, as the excuse subject has it.
    static func span(_ a: AbsenceEntry) -> (start: Int, end: Int) {
        let hasTimes = a.startTime > 0 || a.endTime > 0
        let s = max(0, AbsenceCalc.toMinutes(a.startTime))
        let e = hasTimes ? AbsenceCalc.toMinutes(a.endTime) : 23 * 60 + 59
        return (a.startDate * 10_000 + (s / 60) * 100 + s % 60, a.endDate * 10_000 + (e / 60) * 100 + e % 60)
    }

    /// The newest excuse whose span overlaps the absence.
    static func sentExcuse(for a: AbsenceEntry, in excuses: [SentExcuse]) -> SentExcuse? {
        let span = span(a)
        var found: SentExcuse?
        for e in excuses where e.start < span.end && e.end > span.start {
            if found.map({ e.sentAt > $0.sentAt }) ?? true { found = e }
        }
        return found
    }
}

// ── Calculator (the web's public absence calculator) ───────────────────────

/// Absences in percent and the hours left before the limit (25 %, the three-quarter rule).
/// Filled in with the year's own numbers when opened from the page; nothing leaves the device.
private struct AbsenceCalculatorView: View {
    let absent: Double?
    let total: Double?
    let yearTotal: Double?

    @Environment(\.strings) private var s
    @State private var absentInput = ""
    @State private var weeklyMode = true
    @State private var wholeYear = false
    @State private var totalInput = ""
    @State private var weeklyInput = ""
    @State private var weeksInput = ""
    @State private var limitInput = "25"
    @State private var filled = false

    private var prefilled: Bool { total != nil || yearTotal != nil }

    var body: some View {
        let absentHours = parse(absentInput)
        let weekly = parse(weeklyInput), weeks = parse(weeksInput)
        let yearHours: Double? = weeklyMode ? (weekly.flatMap { w in weeks.map { w * $0 } }) : parse(totalInput)
        let limit = parse(limitInput)
        let tooMany = absentHours != nil && yearHours != nil && (yearHours ?? 0) > 0 && (absentHours ?? 0) > (yearHours ?? 0)
        let stats: (pct: Double, left: Int)? = {
            guard let a = absentHours, let t = yearHours, let l = limit else { return nil }
            return Self.stats(absent: a, total: t, limit: min(l, 100))
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(s.absences.calcLead).textStyle(.callout).foregroundStyle(Palette.textSecondary)
                resultCard(stats, limit: limit, tooMany: tooMany).fadeIn()
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    numberField(s.absences.calcAbsent, $absentInput, invalid: (!absentInput.isEmpty && absentHours == nil) || tooMany)
                    if total != nil && yearTotal != nil {
                        PokyhSegmentedControl([false, true], selection: Binding(get: { wholeYear }, set: { whole in
                            wholeYear = whole
                            weeklyMode = false
                            totalInput = shown(whole ? yearTotal : total)
                        })) { $0 ? s.absences.spanYear : s.absences.spanSoFar }
                    }
                    EyebrowLabel(s.absences.calcTotalMode, color: Palette.textSecondary)
                    PokyhSegmentedControl([true, false], selection: $weeklyMode) {
                        $0 ? s.absences.calcModeWeekly : s.absences.calcModeTotal
                    }
                    if weeklyMode {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            numberField(s.absences.calcWeekly, $weeklyInput, invalid: !weeklyInput.isEmpty && weekly == nil)
                            numberField(s.absences.calcWeeks, $weeksInput, invalid: !weeksInput.isEmpty && weeks == nil)
                        }
                        if let yearHours, yearHours > 0 {
                            Text(s.absences.calcYear(number(yearHours, 1))).textStyle(.footnote).foregroundStyle(Palette.textTertiary)
                        }
                    } else {
                        numberField(s.absences.calcTotal, $totalInput, invalid: !totalInput.isEmpty && parse(totalInput) == nil)
                    }
                    numberField(s.absences.calcLimit, $limitInput, invalid: limit == nil || (limit ?? 0) > 100, suffix: "%")
                }
                .padding(Spacing.card)
                .cardSurface(radius: Radius.xl, fill: Palette.card)
                .fadeIn(delay: 0.04)

                if prefilled {
                    Text(s.absences.calcFromYear).textStyle(.footnote).foregroundStyle(Palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(s.absences.calcRuleTitle).textStyle(.headline).foregroundStyle(Palette.textPrimary)
                    Text(s.absences.calcRule).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                }
                .padding(Spacing.card)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: Radius.xl, fill: Palette.card)
                .fadeIn(delay: 0.08)
                Text(s.absences.calcPrivacy).textStyle(.caption).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(s.absences.calc)
        .navigationBarTitleDisplayMode(.large)
        .appBackground()
        .onAppear {
            guard !filled else { return }
            filled = true
            absentInput = shown(absent)
            weeklyMode = !prefilled
            wholeYear = total == nil && yearTotal != nil
            totalInput = shown(total ?? yearTotal)
        }
    }

    private func resultCard(_ stats: (pct: Double, left: Int)?, limit: Double?, tooMany: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let stats {
                HStack(alignment: .lastTextBaseline, spacing: Spacing.md) {
                    Text("\(number(stats.pct, 1)) %").textStyle(.statLarge).foregroundStyle(Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text(s.absences.calcResult).textStyle(.headline).foregroundStyle(Palette.textSecondary)
                }
                // The bar runs to twice the limit, so the limit's marker sits in the middle.
                let span = max((limit ?? 25) * 2, stats.pct, 1)
                let tone: Color = {
                    guard let limit else { return Palette.textTertiary }
                    if stats.left < 0 { return Brand.danger }
                    if stats.pct >= limit * 0.6 { return Brand.warning }
                    return Decorative.sage.ink
                }()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.cardAlt).frame(height: 12)
                        Capsule().fill(tone).frame(width: geo.size.width * min(1, max(0, stats.pct / span)), height: 12)
                        if let limit {
                            Capsule().fill(Palette.textPrimary)
                                .frame(width: 2, height: 20)
                                .offset(x: geo.size.width * min(1, max(0, limit / span)) - 1)
                        }
                    }
                    .frame(height: 20)
                    .animation(.easeOut(duration: 0.5), value: stats.pct)
                }
                .frame(height: 20)
                .padding(.top, Spacing.lg)
                Text(s.absences.calcPresent(number(100 - stats.pct, 1)))
                    .textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                    .padding(.top, Spacing.md)
                Text(stats.left > 0 ? s.absences.calcLeft(number(Double(stats.left), 0))
                     : stats.left == 0 ? s.absences.calcAtLimit
                     : s.absences.calcOver(number(Double(-stats.left), 0)))
                    .textStyle(.headline).foregroundStyle(Palette.textPrimary)
                    .padding(.top, Spacing.sm)
            } else {
                Text(tooMany ? s.absences.calcInvalid : s.absences.calcEmpty).textStyle(.body).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.xl, fill: Palette.card)
    }

    private func numberField(_ label: String, _ text: Binding<String>, invalid: Bool, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EyebrowLabel(label, color: Palette.textSecondary)
            HStack(spacing: Spacing.sm) {
                TextField("", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(7)) }))
                    .keyboardType(.decimalPad)
                    .textStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .tint(Brand.accent)
                if let suffix { Text(suffix).textStyle(.body).foregroundStyle(Palette.textTertiary) }
            }
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 52)
            .background(Palette.cardAlt, in: .pokyh(Radius.md))
            .overlay(alignment: .bottom) {
                if invalid { Capsule().fill(Brand.danger).frame(height: 2).padding(.horizontal, Spacing.sm) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static func stats(absent: Double, total: Double, limit: Double) -> (pct: Double, left: Int)? {
        guard total > 0, absent >= 0, absent <= total, (0...100).contains(limit) else { return nil }
        let left = total * limit / 100 - absent
        return (absent / total * 100, left >= 0 ? Int((left + 1e-9).rounded(.down)) : -Int((-left - 1e-9).rounded(.up)))
    }

    private func parse(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, let v = Double(text), v.isFinite, v >= 0 else { return nil }
        return v
    }

    private func number(_ v: Double, _ digits: Int) -> String {
        var out = String(format: "%.\(digits)f", v)
        if digits > 0 {
            while out.hasSuffix("0") { out.removeLast() }
            if out.hasSuffix(".") { out.removeLast() }
        }
        return out.replacingOccurrences(of: ".", with: String(s.common.decimal))
    }

    private func shown(_ v: Double?) -> String {
        guard let v else { return "" }
        return number((v * 10).rounded() / 10, 1)
    }
}

// ── Abwesenheit melden ──────────────────────────────────────────────────────

// The web's two absence sheets, built like the compose sheet: fields on the sheet, the reason list
// and the lesson picker pushed inside it, the action below, a confirmation before it leaves.
// Reasons and presets come from WebUntis' own report dialog. Nothing shows as saved unless
// WebUntis saved it.

/// Dates as YYYYMMDD and times as HHMM, the way WebUntis takes them.
private enum AbsenceClock {
    static func day(_ d: Date) -> Int { AbsenceCalc.num(d) }

    static func hhmm(_ t: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return (c.hour ?? 0) * 100 + (c.minute ?? 0)
    }

    /// A clock time on some day; only hour and minute count.
    static func time(_ hhmm: Int) -> Date? {
        guard hhmm >= 0, hhmm / 100 < 24, hhmm % 100 < 60 else { return nil }
        return Calendar.current.date(bySettingHour: hhmm / 100, minute: hhmm % 100, second: 0, of: Date())
    }

    static func label(_ t: Date) -> String { TaskDates.time(t) }

    /// "Mi., 29.10." for the confirmation.
    static func short(_ d: Date, _ c: CommonStrings) -> String {
        let parts = AbsenceCalc.cal.dateComponents([.day, .month], from: d)
        let i = AbsenceText.weekdayIndex(d) ?? 0
        let weekday = c.weekdaysShort.indices.contains(i) ? c.weekdaysShort[i] : ""
        return "\(weekday) \(c.dayMonthShort(parts.day ?? 1, parts.month ?? 1))"
    }

    static func monday(_ d: Date) -> String { DateFmt.isoString(AbsenceCalc.monday(d)) }
}

private struct ReportAbsenceSheet: View {
    let onDone: () async -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var meta: AbsenceMeta?
    @State private var metaFailed = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var startTime: Date?
    @State private var endTime: Date?
    @State private var reason: AbsenceReason?
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    @State private var done = false
    @State private var started = false

    private var t: AbsencesStrings { s.absences }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if done {
                        SheetDone(text: t.reported, detail: reportedRange)
                    } else {
                        form
                    }
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxxl)
                .animation(Motion.standardEase, value: done)
                .animation(Motion.standardEase, value: error)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle(t.reportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel(s.common.close)
                }
            }
        }
        .interactiveDismissDisabled(saving)
        .presentationDetents([.large])
        .presentationSizing(.form)
        .sensoryFeedback(.success, trigger: done) { _, now in now }
        .task {
            guard !started else { return }
            started = true
            await loadPresets()
        }
    }

    @ViewBuilder private var form: some View {
        // Who it is for.
        let name = app.session?.personName.flatMap { $0.isEmpty ? nil : $0 } ?? t.me
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EyebrowLabel(t.forLabel, color: Palette.textSecondary)
            HStack(spacing: Spacing.iconText) {
                InitialAvatar(name: name, size: 36, colorSeed: app.session?.username)
                Text(name).textStyle(.body).foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nestedSurface(radius: Radius.lg)
        }

        // Moving the start keeps the end on the same day and never before the start, as the web does.
        DateTimeField(label: t.from, date: $startDate, time: $startTime, enabled: !saving)
            .onChange(of: startDate) {
                endDate = startDate
                if let s = startTime, let e = endTime, AbsenceClock.hhmm(e) < AbsenceClock.hhmm(s) { endTime = s }
            }
            .onChange(of: startTime) {
                if let s = startTime, let e = endTime, startDate.isSameDay(as: endDate), AbsenceClock.hhmm(e) < AbsenceClock.hhmm(s) {
                    endTime = s
                }
            }
        DateTimeField(label: t.until, date: $endDate, time: $endTime, enabled: !saving, from: startDate)

        NavigationLink {
            LessonPicker(initial: startDate) { day, from, to in
                startDate = day
                endDate = day
                startTime = AbsenceClock.time(from)
                endTime = AbsenceClock.time(to)
            }
        } label: {
            Label(t.fromTimetable, systemImage: "calendar")
                .textStyle(.headline)
                .foregroundStyle(Palette.accentText)
                .padding(.vertical, Spacing.xs)
        }
        .disabled(saving)

        NavigationLink {
            ReasonList(reasons: meta?.reasons, failed: metaFailed, selected: $reason)
        } label: {
            SheetField(label: t.reason, value: reason?.name ?? t.choose, placeholder: reason == nil)
        }
        .buttonStyle(.rowPress(radius: Radius.lg))
        .disabled(saving)

        TaskTextArea(label: t.text, placeholder: t.textPlaceholder, text: Binding(get: { text }, set: { text = String($0.prefix(1000)) }))
            .disabled(saving)

        if let error { SheetNote(error, color: Brand.danger) }

        Button { Task { await report() } } label: {
            ButtonLabel(t.reportAction, symbol: "paperplane.fill", busy: saving).frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(saving)
    }

    /// What was reported, under "Gemeldet".
    private var reportedRange: String? {
        guard let from = startTime, let to = endTime else { return nil }
        let c = s.common
        if startDate.isSameDay(as: endDate) {
            return "\(AbsenceClock.short(startDate, c)) \(AbsenceClock.label(from)) – \(AbsenceClock.label(to))"
        }
        return "\(AbsenceClock.short(startDate, c)) \(AbsenceClock.label(from)) – \(AbsenceClock.short(endDate, c)) \(AbsenceClock.label(to))"
    }

    /// The dialog's presets once they arrive, without overwriting what was already picked; else
    /// today's lessons from the timetable.
    private func loadPresets() async {
        guard let session = app.session else { return }
        var found = try? await UntisClient.shared.absenceMeta(session)
        if found == nil, let reasons = try? await UntisClient.shared.absenceReasons(session), !reasons.isEmpty {
            found = AbsenceMeta(reasons: reasons, defaultReasonId: nil, defaultDate: nil, defaultStartTime: nil, defaultEndTime: nil)
        }
        meta = found
        metaFailed = found == nil
        if reason == nil, let m = found { reason = m.reasons.first { $0.id == m.defaultReasonId } }
        if let m = found, let day = m.defaultDate.flatMap(AbsenceCalc.date),
           let from = m.defaultStartTime.flatMap(AbsenceClock.time), let to = m.defaultEndTime.flatMap(AbsenceClock.time) {
            if startTime == nil { startDate = day; startTime = from }
            if endTime == nil { endDate = day; endTime = to }
            return
        }
        let today = Date()
        guard let week = try? await UntisClient.shared.timetable(date: AbsenceClock.monday(today), session) else { return }
        let lessons = week.filter { $0.date == AbsenceClock.day(today) && !$0.isCancelled }
        guard let first = lessons.map(\.startTime).min(), let last = lessons.map(\.endTime).max() else { return }
        if startTime == nil { startTime = AbsenceClock.time(first) }
        if endTime == nil { endTime = AbsenceClock.time(last) }
    }

    private func report() async {
        guard let session = app.session, !saving else { return }
        guard let from = startTime, let to = endTime else { error = t.errChooseRange; return }
        let sd = AbsenceClock.day(startDate), ed = AbsenceClock.day(endDate)
        let st = AbsenceClock.hhmm(from), et = AbsenceClock.hhmm(to)
        if ed * 10_000 + et <= sd * 10_000 + st { error = t.errEndAfterStart; return }
        guard let chosen = reason else { error = t.errChooseReason; return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await UntisClient.shared.reportAbsence(startDate: sd, startTime: st, endDate: ed, endTime: et, reasonId: chosen.id,
                                                       text: text.trimmingCharacters(in: .whitespacesAndNewlines), session)
            done = true
            await onDone()
            // The confirmation stays a moment, then the sheet leaves.
            try? await Task.sleep(for: .milliseconds(1600))
            dismiss()
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
            error = s.common.sessionExpired
        } catch {
            self.error = (error as? AppError)?.message ?? s.errors.reportFailed
        }
    }
}

// ── Entschuldigen ───────────────────────────────────────────────────────────

/// "Entschuldigen" for absences that are over: WebUntis takes no reason for those, so the excuse
/// goes to the class teachers as a message and they mark it excused. A partial send stays open, so
/// the names it missed can be read.
private struct ExcuseAbsenceSheet: View {
    let absence: AbsenceEntry
    let summary: String
    let onDone: (ExcuseResult) async -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var meta: AbsenceMeta?
    @State private var metaFailed = false
    @State private var teachers: [String]?
    @State private var teachersFailed = false
    @State private var reason: AbsenceReason?
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?
    @State private var result: ExcuseResult?
    @State private var started = false

    private var t: AbsencesStrings { s.absences }
    private var noTeacher: Bool { teachers?.isEmpty == true && !teachersFailed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let result {
                        SheetDone(text: result.viaMessage ? t.exDone : t.exSavedInUntis,
                                  detail: result.viaMessage ? t.exDoneTo(result.sentTo.joined(separator: ", ")) : reason?.name,
                                  warning: result.failed.isEmpty ? nil : t.exPartial(result.failed.joined(separator: ", ")))
                    } else {
                        form
                    }
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxxl)
                .animation(Motion.standardEase, value: result)
                .animation(Motion.standardEase, value: error)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle(t.exTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                        .accessibilityLabel(s.common.close)
                }
            }
        }
        .interactiveDismissDisabled(saving)
        .presentationDetents([.large])
        .presentationSizing(.form)
        .sensoryFeedback(trigger: result) { _, r in
            guard let r else { return nil }
            return r.failed.isEmpty ? .success : .warning
        }
        .task {
            guard !started else { return }
            started = true
            await load()
        }
    }

    @ViewBuilder private var form: some View {
        Text(t.exLead).textStyle(.footnote).foregroundStyle(Palette.textSecondary)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            EyebrowLabel(t.exAbsence, color: Palette.textSecondary)
            HStack(spacing: Spacing.iconText) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Brand.danger)
                Text(summary).textStyle(.body).foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .insetSurface(radius: Radius.lg)
        }

        // Who it goes to: the class teachers WebUntis names for the class.
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EyebrowLabel(t.exTo, color: Palette.textSecondary)
            HStack(spacing: Spacing.iconText) {
                if let teachers, !teachers.isEmpty {
                    TeacherStack(names: teachers)
                } else {
                    Image(systemName: "person.2").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
                Text(teacherText)
                    .textStyle(.body)
                    .foregroundStyle(teachers?.isEmpty == false ? Palette.textPrimary : Palette.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .insetSurface(radius: Radius.lg)
            if noTeacher {
                Text(t.exNoTeacher).textStyle(.footnote).foregroundStyle(Brand.danger)
            }
        }

        NavigationLink {
            ReasonList(reasons: meta?.reasons, failed: metaFailed, selected: $reason)
        } label: {
            SheetField(label: t.reason, value: reason?.name ?? t.choose, placeholder: reason == nil)
        }
        .buttonStyle(.rowPress(radius: Radius.lg))
        .disabled(saving)

        TaskTextArea(label: t.exNote, placeholder: s.common.optional, text: Binding(get: { note }, set: { note = String($0.prefix(1000)) }))
            .disabled(saving)

        if let error { SheetNote(error, color: Brand.danger) }

        Button { Task { await excuse() } } label: {
            ButtonLabel(saving ? t.exSaving : t.exSave, symbol: "paperplane.fill", busy: saving).frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(saving || noTeacher)
    }

    private var teacherText: String {
        guard let teachers else { return "…" }
        if teachersFailed { return t.exToSchool }
        return teachers.isEmpty ? t.notAvailable : teachers.joined(separator: ", ")
    }

    private func load() async {
        guard let session = app.session else { return }
        async let people = UntisClient.shared.messageRecipients(session)
        var found = try? await UntisClient.shared.absenceMeta(session)
        if found == nil, let reasons = try? await UntisClient.shared.absenceReasons(session), !reasons.isEmpty {
            found = AbsenceMeta(reasons: reasons, defaultReasonId: nil, defaultDate: nil, defaultStartTime: nil, defaultEndTime: nil)
        }
        meta = found
        metaFailed = found == nil
        if reason == nil, let m = found { reason = m.reasons.first { $0.id == m.defaultReasonId } }
        do {
            var seen = Set<Int>()
            teachers = try await people.filter { $0.isClassTeacher && seen.insert($0.id).inserted }.map(\.name)
        } catch {
            teachers = []
            teachersFailed = true
        }
    }

    private func excuse() async {
        guard let session = app.session, !saving, result == nil else { return }
        guard let chosen = reason else { error = t.exPick; return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let r = try await UntisClient.shared.excuseByMessage(absences: [absence], reason: chosen,
                                                                  note: note.trimmingCharacters(in: .whitespacesAndNewlines), session)
            result = r
            await onDone(r)
            guard r.failed.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(1600))
            dismiss()
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
            error = s.common.sessionExpired
        } catch {
            self.error = (error as? AppError)?.message ?? t.exSendFailed
        }
    }
}

/// Up to three class teachers' initials, overlapping.
private struct TeacherStack: View {
    let names: [String]

    var body: some View {
        let shown = Array(names.prefix(3))
        let tone = Decorative.periwinkle
        ZStack(alignment: .leading) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, name in
                Text(Self.initials(name))
                    .textStyle(TextStyle.caption.weight(.semibold))
                    .foregroundStyle(tone.ink)
                    .frame(width: 30, height: 30)
                    .background(tone.fill, in: .circle)
                    .padding(2)
                    .background(Palette.cardAlt, in: .circle)
                    .offset(x: CGFloat(i) * 22)
            }
        }
        .frame(width: CGFloat(34 + (shown.count - 1) * 22), height: 34, alignment: .leading)
        .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace || $0 == "," }).prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
}

// ── Sheet parts ─────────────────────────────────────────────────────────────

/// Label, then the day and the time on one recessed strip, as in the reminders.
private struct DateTimeField: View {
    let label: String
    @Binding var date: Date
    @Binding var time: Date?
    var enabled = true
    /// The first day the end may be on.
    var from: Date? = nil
    @Environment(\.strings) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            EyebrowLabel(label, color: Palette.textSecondary)
            HStack(spacing: Spacing.sm) {
                Image(systemName: "calendar").foregroundStyle(Palette.accentText)
                Group {
                    if let from {
                        DatePicker("", selection: $date, in: Calendar.current.startOfDay(for: from)..., displayedComponents: .date)
                    } else {
                        DatePicker("", selection: $date, displayedComponents: .date)
                    }
                }
                .labelsHidden()
                Spacer(minLength: 0)
                Image(systemName: "clock").foregroundStyle(time == nil ? Palette.textTertiary : Palette.accentText)
                if let value = time {
                    DatePicker("", selection: Binding(get: { value }, set: { time = $0 }), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                } else {
                    // No time yet: the next full hour to start from.
                    Button(s.absences.time) {
                        let hour = Calendar.current.component(.hour, from: Date())
                        time = AbsenceClock.time(min(23, hour + 1) * 100)
                    }
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, Spacing.sm)
                }
            }
            .environment(\.locale, s.lang.locale)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .insetSurface(radius: Radius.md)
            .disabled(!enabled)
        }
    }
}

/// The reasons WebUntis offers; picking one goes back to the form.
private struct ReasonList: View {
    let reasons: [AbsenceReason]?
    let failed: Bool
    @Binding var selected: AbsenceReason?
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.rowGap) {
                if let reasons, !reasons.isEmpty {
                    ForEach(reasons) { r in
                        let on = r.id == selected?.id
                        Button {
                            selected = r
                            dismiss()
                        } label: {
                            HStack {
                                Text(r.name)
                                    .textStyle(on ? TextStyle.body.weight(.semibold) : .body)
                                    .foregroundStyle(Palette.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if on {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Brand.accent)
                                        .accessibilityLabel(s.absences.selected)
                                }
                            }
                            .padding(Spacing.md)
                            .background(on ? Palette.accentTint : .clear, in: .pokyh(Radius.lg))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.rowPress(radius: Radius.lg))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                } else {
                    Text(failed ? s.absences.reasonsFailed : reasons == nil ? s.absences.reasonsLoading : s.absences.noReasons)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, Spacing.xl)
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
        }
        .appBackground()
        .navigationTitle(s.absences.reason)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// "Aus Stundenplan wählen": one day's lessons to tick; the range runs from the first picked
/// lesson's start to the last one's end. The day moves back and forth.
private struct LessonPicker: View {
    let initial: Date
    let onTake: (_ day: Date, _ from: Int, _ to: Int) -> Void

    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var lessons: [TimetableEntry]?
    @State private var picked: Set<Int> = []

    init(initial: Date, onTake: @escaping (_ day: Date, _ from: Int, _ to: Int) -> Void) {
        self.initial = initial
        self.onTake = onTake
        _day = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    IconButton("chevron.left", label: s.absences.prevDay) { move(-1) }
                    Text(TaskDates.dayLong(day, s))
                        .textStyle(TextStyle.callout.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                    IconButton("chevron.right", label: s.absences.nextDay) { move(1) }
                }
                .padding(Spacing.xs)
                .nestedSurface(radius: Radius.lg)

                if let lessons {
                    if lessons.isEmpty {
                        Text(s.absences.noLessonsDay).textStyle(.callout).foregroundStyle(Palette.textSecondary)
                            .padding(.vertical, Spacing.md)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(Array(lessons.enumerated()), id: \.offset) { i, l in lessonRow(i, l) }
                        }
                    }
                } else {
                    SkeletonBlock(height: 48)
                }

                Button {
                    let chosen = picked.compactMap { lessons?.indices.contains($0) == true ? lessons?[$0] : nil }
                    guard let from = chosen.map(\.startTime).min(), let to = chosen.map(\.endTime).max() else { return }
                    onTake(day, from, to)
                    dismiss()
                } label: {
                    ButtonLabel(s.absences.takeLessons(picked.count)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(picked.isEmpty)
                .padding(.top, Spacing.sm)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
        }
        .appBackground()
        .navigationTitle(s.absences.chooseLessons)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: day) { await load() }
        .sensoryFeedback(.selection, trigger: picked)
    }

    private func lessonRow(_ i: Int, _ l: TimetableEntry) -> some View {
        let on = picked.contains(i)
        return Button {
            if on { picked.remove(i) } else { picked.insert(i) }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Brand.accent : Palette.textTertiary)
                Text("\(AbsenceText.time(l.startTime)) – \(AbsenceText.time(l.endTime))")
                    .textStyle(TextStyle.footnote.weight(.semibold).tabularDigits)
                    .foregroundStyle(Palette.textSecondary)
                Text((l.subjectName.isEmpty ? l.subjectLong : l.subjectName) + (l.isCancelled ? s.absences.cancelledSuffix : ""))
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(on ? Palette.accentTint : Palette.nested, in: .pokyh(Radius.lg))
            .contentShape(.rect)
        }
        .buttonStyle(.rowPress(radius: Radius.lg))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func move(_ days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        withAnimation(Motion.standardEase) { day = next }
    }

    private func load() async {
        guard let session = app.session else { return }
        lessons = nil
        picked = []
        let num = AbsenceClock.day(day)
        let week = (try? await UntisClient.shared.timetable(date: AbsenceClock.monday(day), session)) ?? []
        var seen = Set<Int>()
        lessons = week.filter { $0.date == num && seen.insert($0.startTime).inserted }.sorted { $0.startTime < $1.startTime }
    }
}

private extension Date {
    func isSameDay(as other: Date) -> Bool { Calendar.current.isDate(self, inSameDayAs: other) }
}
