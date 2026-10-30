import SwiftUI
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
                                    AbsenceRow(absence: a, label: fmt(figures.perAbsence[a.id] ?? 0))
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
    @Environment(\.strings) private var s

    var body: some View {
        let tone = absence.isExcused ? Decorative.sage : Decorative.blush
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
                        Text(title).textStyle(.headline).foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(label).textStyle(TextStyle.headline.tabularDigits).foregroundStyle(Palette.textPrimary)
                    }
                    if !subText.isEmpty {
                        Text(subText).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                    let extra = [absence.reasonName, absence.note].compactMap { $0 }.filter { !$0.isEmpty }
                    if !extra.isEmpty {
                        Text(extra.joined(separator: " · ")).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            HStack(spacing: Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: absence.isExcused ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(absence.isExcused ? s.absences.statusExcused : s.absences.statusOpen)
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(tone.ink)
                .padding(.horizontal, Spacing.md)
                .frame(height: 32)
                .background(tone.fill, in: .capsule)
            }
            .padding(.leading, 48 + Spacing.md)
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func weekdayIndex(_ d: Date?) -> Int? {
        guard let d else { return nil }
        return (AbsenceCalc.cal.component(.weekday, from: d) + 5) % 7   // Monday = 0
    }

    private func weekdayShort(_ d: Date?) -> String {
        guard let i = weekdayIndex(d), s.common.weekdaysShort.indices.contains(i) else { return "" }
        return s.common.weekdaysShort[i]
    }

    /// "Mittwoch, 17. Dezember" for one day, "17. Dez. – 19. Dez." for several.
    private var title: String {
        let c = s.common
        let sd = absence.startDate % 100, sm = (absence.startDate / 100) % 100
        guard (1...12).contains(sm) else { return Fmt.dateShort(absence.startDate) }
        if absence.startDate != absence.endDate {
            let ed = absence.endDate % 100, em = (absence.endDate / 100) % 100
            guard (1...12).contains(em) else { return Fmt.dateShort(absence.startDate) }
            return "\(c.dayMonthShort(sd, sm)) – \(c.dayMonthShort(ed, em))"
        }
        guard let i = weekdayIndex(AbsenceCalc.date(absence.startDate)), c.weekdays.indices.contains(i) else {
            return c.dayMonth(sd, sm)
        }
        let weekday = c.weekdays[i]
        return "\(weekday.prefix(1).uppercased())\(weekday.dropFirst()), \(c.dayMonth(sd, sm))"
    }

    private var subText: String {
        var parts: [String] = []
        if absence.startTime != 0 || absence.endTime != 0 {
            parts.append("\(time(absence.startTime)) – \(time(absence.endTime))")
        }
        if let sub = absence.subjectName, !sub.isEmpty { parts.append(sub) }
        if let t = absence.teacherName, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    private func time(_ t: Int) -> String {
        if t == 0 { return "" }
        let m = AbsenceCalc.toMinutes(t)
        return String(format: "%02d:%02d", m / 60, m % 60)
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
