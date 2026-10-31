import SwiftUI
import Charts
import PokyhCore
import PokyhDesign

// Noten, the way Android (and the web) lay it out: school-year title, a 2x2 grid of stat cards,
// then the subjects as one card whose rows open in place. The dashboard renders with zeroed
// values too, so the screen looks like itself on the first day of a school year.

struct GradesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var subjects: [SubjectGrades] = []
    @State private var loading = true
    @State private var error: String?
    @State private var year = SchoolDates.currentSchoolYear
    @State private var sort: GradeSort = .name
    @State private var expanded: Set<Int> = []
    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            if loading {
                GradesSkeleton()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else {
                content
            }
        }
        .navigationTitle(s.grades.schoolYearTitle(year))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { yearMenu }
        }
        .profileToolbar()
        .appBackground()
        .task(id: year) { await load() }
    }

    private var yearMenu: some View {
        Menu {
            Picker(selection: $year) {
                ForEach(SchoolDates.availableYears, id: \.self) { y in
                    Text("\(String(y)) / \(String(y + 1))").tag(y)
                }
            } label: { EmptyView() }
        } label: {
            Text("\(String(year))/\(String((year + 1) % 100))")
                .textStyle(TextStyle.subheadline.weight(.semibold).tabularDigits)
        }
    }

    private var content: some View {
        let dash = GradesDashboard(subjects: subjects, months: s.common.monthsShort)
        let compact = WidthClass(width: width) == .compact
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                EyebrowLabel(eyebrow(dash))
                    .fadeIn()
                StatCardGrid(dashboard: dash, compact: compact)
                subjectsSection
                    .fadeIn(delay: 0.16)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.xxxl)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func eyebrow(_ d: GradesDashboard) -> String {
        guard d.hasGrades else { return s.grades.noGradesYear }
        let stand = d.latestDate > 0 ? GradesLook.dateLong(d.latestDate, s.common) : "—"
        return s.grades.summary(stand, d.subjectCount, d.allCount)
    }

    // ── Fächer ──────────────────────────────────────────────────────────────

    /// Ungraded subjects always go last; their average of 0 isn't a real "worst".
    private var sortedSubjects: [(subject: SubjectGrades, avg: Double)] {
        let rows = subjects.map { sub -> (subject: SubjectGrades, avg: Double, latest: Int) in
            let vals = sub.grades.map(\.markDisplayValue).filter { $0 > 0 }
            return (sub, GradeMath.averageOf(vals), sub.grades.map(\.date).max() ?? 0)
        }
        let sorted: [(subject: SubjectGrades, avg: Double, latest: Int)]
        switch sort {
        case .name:
            sorted = rows.sorted { $0.subject.subjectName.compare($1.subject.subjectName, options: [.caseInsensitive, .diacriticInsensitive], locale: s.lang.locale) == .orderedAscending }
        case .best:
            sorted = rows.sorted { (ungraded($0.avg), -$0.avg) < (ungraded($1.avg), -$1.avg) }
        case .worst:
            sorted = rows.sorted { (ungraded($0.avg), $0.avg) < (ungraded($1.avg), $1.avg) }
        case .recent:
            sorted = rows.sorted { (ungraded($0.avg), -$0.latest) < (ungraded($1.avg), -$1.latest) }
        }
        return sorted.map { ($0.subject, $0.avg) }
    }

    private func ungraded(_ avg: Double) -> Int { avg <= 0 ? 1 : 0 }

    private var subjectsSection: some View {
        let rows = sortedSubjects
        let allExpanded = !rows.isEmpty && expanded.count == rows.count
        return VStack(alignment: .leading, spacing: Spacing.headerContent) {
            SectionHeader(s.grades.subjects) {
                HStack(spacing: Spacing.xs) {
                    sortMenu
                    TextLinkButton(allExpanded ? s.grades.collapseAll : s.grades.expandAll) {
                        withAnimation(.easeInOut(duration: Motion.standard)) {
                            expanded = allExpanded ? [] : Set(rows.map(\.subject.lessonId))
                        }
                    }
                }
            }
            if rows.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Palette.textTertiary)
                    Text(s.grades.emptyTitle).textStyle(.headline).foregroundStyle(Palette.textPrimary)
                    Text(s.grades.noSubjects).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.card)
                .cardSurface(radius: Radius.xl, fill: Palette.card)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.subject.id) { index, row in
                        if index > 0 { RowSeparator(inset: 0) }
                        SubjectRow(
                            subject: row.subject,
                            average: row.avg,
                            isExpanded: expanded.contains(row.subject.lessonId),
                            subjects: subjects
                        ) {
                            withAnimation(.easeInOut(duration: Motion.standard)) {
                                if expanded.contains(row.subject.lessonId) {
                                    expanded.remove(row.subject.lessonId)
                                } else {
                                    expanded.insert(row.subject.lessonId)
                                }
                            }
                        }
                    }
                }
                .clipShape(.pokyh(Radius.xl))
                .cardSurface(radius: Radius.xl, fill: Palette.card)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(selection: $sort.animation()) {
                ForEach(GradeSort.allCases, id: \.self) { mode in
                    Text(label(mode)).tag(mode)
                }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                Text(label(sort)).textStyle(TextStyle.footnote.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 32)
            .background(Palette.cardAlt, in: .capsule)
        }
    }

    private func label(_ mode: GradeSort) -> String {
        switch mode {
        case .name: s.grades.sortName
        case .best: s.grades.sortBest
        case .worst: s.grades.sortWorst
        case .recent: s.grades.sortRecent
        }
    }

    private func load() async {
        guard let session = app.session else { return }
        loading = true
        error = nil
        do {
            subjects = try await UntisClient.shared.grades(year: year == SchoolDates.currentSchoolYear ? nil : year, session)
            if year == SchoolDates.currentSchoolYear { WatchSync.grades(subjects, for: session) }
            // Only the default account's current year feeds the grades widget.
            if year == SchoolDates.currentSchoolYear, app.isDefaultAccountActive {
                WidgetBridge.publishGrades(subjects)
            }
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

enum GradeSort: CaseIterable { case name, best, worst, recent }

// ── Subject row ─────────────────────────────────────────────────────────────

/// One line: the subject on its timetable pastel, the count, the average, a chevron. Opens in
/// place to list the grades, with a way into the subject's own page.
struct SubjectRow: View {
    let subject: SubjectGrades
    let average: Double
    let isExpanded: Bool
    let subjects: [SubjectGrades]
    let onToggle: () -> Void
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tone = Tone.subject(subject.subjectName)
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        Text(subject.subjectName)
                            .textStyle(TextStyle.callout.weight(.semibold))
                            .foregroundStyle(tone.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(tone.fill, in: .pokyh(Radius.xs))
                        Text(s.grades.gradeCount(subject.grades.count))
                            .textStyle(.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: 0)
                    }
                    Text(average > 0 ? GradesLook.num(average, s) : "–")
                        .textStyle(TextStyle.title3.tabularDigits)
                        .foregroundStyle(average > 0 ? GradesLook.band(average) : Palette.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityLabel(isExpanded ? s.grades.collapse : s.grades.expand)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, Spacing.card)
                .padding(.vertical, Spacing.xs)
                .contentShape(.rect)
            }
            .buttonStyle(.rowPress)

            if isExpanded {
                panel(tone)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    private func panel(_ tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if subject.grades.isEmpty {
                Text(s.grades.noSingleGrades)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, Spacing.sm)
            } else {
                ForEach(subject.grades.sorted { $0.date > $1.date }) { grade in
                    HStack(spacing: Spacing.md) {
                        Text(Fmt.dateShort(grade.date))
                            .textStyle(TextStyle.caption.tabularDigits)
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 62, alignment: .leading)
                        Text(gradeDisplay(grade, exam: s.grades.exam))
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(GradesLook.num(grade.markDisplayValue, s))
                            .textStyle(TextStyle.headline.tabularDigits)
                            .foregroundStyle(GradesLook.band(grade.markDisplayValue))
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
            HStack {
                Spacer()
                NavigationLink {
                    GradeSubjectView(lessonId: subject.lessonId, subjects: subjects)
                } label: {
                    ButtonLabel(s.grades.openDetails, symbol: "chevron.right")
                }
                .buttonStyle(.secondary(compact: true))
            }
            .padding(.top, Spacing.md)
        }
        .padding(.horizontal, Spacing.card)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The subject's own pastel, so the open panel belongs to the chip above it.
        .background(tone.fill.opacity(scheme == .dark ? 0.55 : 0.85))
    }
}

/// What a grade was: text, else mark name, else exam type, else "Prüfung". A label that is
/// really just the mark again ("7", "6.5", "7/10") counts as no label, as on the web.
func gradeDisplay(_ g: GradeEntry, exam: String) -> String {
    let raw = (!g.text.isEmpty ? g.text : (!g.markName.isEmpty ? g.markName : g.examType))
        .trimmingCharacters(in: .whitespaces)
    if raw.isEmpty { return exam }
    let normalized = raw.replacingOccurrences(of: ",", with: ".")
        .replacingOccurrences(of: "[−–—]", with: "-", options: .regularExpression)
    let gradeLike = #"^(?:\d{1,2}(?:\.\d{1,2})?[+\-]?|\d{1,2}/\d{1,2})$"#
    return normalized.range(of: gradeLike, options: .regularExpression) != nil ? exam : raw
}

// ── Shared look for the grade screens ───────────────────────────────────────

enum GradesLook {
    /// The web's four bands: ≥9 excellent, ≥6 positive, >4 negative, else critical.
    static func band(_ v: Double) -> Color {
        if v >= 9 { return Color(RGB(hex: 0x10B981).softenedFill) }
        if v >= 6 { return Brand.success }
        if v > 4 { return Brand.orange }
        return Brand.danger
    }

    /// A grade as a block: sage from 6.4, butter from 6, blush below.
    static func tone(_ v: Double) -> Tone {
        if v >= 6.4 { return Decorative.sage }
        if v >= 6 { return Decorative.butter }
        return Decorative.blush
    }

    static func num(_ v: Double, _ s: Strings, digits: Int = 2) -> String {
        Fmt.num(v, digits: digits).replacingOccurrences(of: ",", with: String(s.common.decimal))
    }

    static func dateLong(_ date: Int, _ c: CommonStrings) -> String {
        let d = date % 100, m = (date / 100) % 100, y = date / 10000
        guard (1...12).contains(m) else { return String(date) }
        return c.dateLong(d, m, y)
    }
}

extension TextStyle {
    /// Same style with tabular figures, for numbers that change in place.
    var tabularDigits: TextStyle {
        TextStyle(size, lineHeight, weight, tracking: tracking, relativeTo: relativeTo, design: design, monospacedDigits: true)
    }
}

// ── Dashboard numbers (the web's `dashboard` memo, ported 1:1) ──────────────

struct GradesDashboard {
    struct SparkPoint: Identifiable { let id: Int; let avg: Double; let label: String }
    struct Recent: Identifiable { let id: Int; let subject: String; let value: Double; let date: Int }
    struct Segment: Identifiable { var id: Int { grade }; let grade: Int; let count: Int; let start: Double; let sweep: Double }

    var allCount = 0
    var subjectCount = 0
    var latestDate = 0
    var overallAvg = 0.0
    var best = 0.0
    var pos = 0
    var neg = 0
    var passRate = 0.0
    var mode = 0
    var median = 0.0
    var sigma = 0.0
    var delta = 0.0
    var previousMonthAvg = 0.0
    var spark: [SparkPoint] = []
    var sparkMin = 1.0
    var sparkMax = 10.0
    var recent: [Recent] = []
    var segments: [Segment] = []
    var hasGrades: Bool { allCount > 0 }

    init(subjects: [SubjectGrades], months: [String], today: Date = Date()) {
        let all = subjects
            .flatMap { sub in sub.grades.map { (entry: $0, subject: sub.subjectName) } }
            .sorted { $0.entry.date < $1.entry.date }
        let values = all.map(\.entry.markDisplayValue).filter { $0 > 0 }
        allCount = all.count
        subjectCount = subjects.count
        latestDate = all.last?.entry.date ?? 0
        overallAvg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        best = values.max() ?? 0
        pos = values.filter { $0 >= 6 }.count
        neg = values.filter { $0 < 6 }.count
        passRate = values.isEmpty ? 0 : Double(pos) / Double(values.count) * 100

        var distribution = [Int](repeating: 0, count: 10)
        for v in values { distribution[Self.bucket(v) - 1] += 1 }
        mode = (distribution.firstIndex(of: distribution.max() ?? 0) ?? 0) + 1

        let sorted = values.sorted()
        if !sorted.isEmpty {
            median = sorted.count % 2 == 1
                ? sorted[(sorted.count - 1) / 2]
                : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            let avg = overallAvg
            sigma = (values.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(values.count)).squareRoot()
        }

        // "Vormonat": the average over everything older than about a month.
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: today)
        let month = c.month ?? 1, yearNow = c.year ?? 2000, day = c.day ?? 1
        let monthAgoKey = (month == 1 ? yearNow - 1 : yearNow) * 10000 + (month == 1 ? 12 : month - 1) * 100 + day
        let older = all.filter { $0.entry.date < monthAgoKey }.map(\.entry.markDisplayValue).filter { $0 > 0 }
        previousMonthAvg = older.isEmpty ? overallAvg : older.reduce(0, +) / Double(older.count)
        delta = overallAvg - previousMonthAvg

        // Running average per month, so the sparkline is a trend rather than noise.
        let monthKeys = Array(Set(all.map { $0.entry.date / 100 })).sorted()
        var cumulative: [Double] = []
        for key in monthKeys {
            let vals = all.filter { $0.entry.date / 100 <= key }.map(\.entry.markDisplayValue).filter { $0 > 0 }
            cumulative.append(vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count))
        }
        // Scaled to the data's own range, else 6.8 to 7.1 is a flat line.
        let valid = cumulative.filter { $0 > 0 }
        let lo = valid.min() ?? 1, hi = valid.max() ?? 10
        let pad = max(0.4, (hi - lo) * 0.3)
        sparkMin = max(1, lo - pad)
        sparkMax = min(10, hi + pad)
        if sparkMax <= sparkMin { sparkMax = sparkMin + 1 }
        spark = monthKeys.enumerated().map { i, key in
            let m = key % 100, y = key / 100
            let name = (1...12).contains(m) && months.count >= 12 ? months[m - 1] : ""
            return SparkPoint(id: i, avg: cumulative[i], label: "\(name) \(String(format: "%02d", y % 100))")
        }

        // Newest by id, the order they were entered in (the web does b.id - a.id).
        recent = all.filter { $0.entry.markDisplayValue > 0 }
            .sorted { $0.entry.id > $1.entry.id }
            .prefix(3)
            .map { Recent(id: $0.entry.id, subject: $0.subject, value: $0.entry.markDisplayValue, date: $0.entry.date) }

        // Donut arcs, grade 10 first, clockwise from the top, with the web's small gap.
        if !values.isEmpty {
            let gap = 0.035
            var start = -Double.pi / 2
            for i in stride(from: 9, through: 0, by: -1) where distribution[i] > 0 {
                let sweep = max(0.01, Double(distribution[i]) / Double(values.count) * 2 * .pi - gap)
                segments.append(Segment(grade: i + 1, count: distribution[i], start: start, sweep: sweep))
                start += sweep + gap
            }
        }
    }

    /// The whole grade a value counts as, rounded half up like the web's Math.round.
    static func bucket(_ v: Double) -> Int { min(10, max(1, Int((v + 0.5).rounded(.down)))) }
}

// ── Stat cards ──────────────────────────────────────────────────────────────

/// Square tiles on a phone; on wider windows the full card, each row as tall as its tallest.
private struct StatCardGrid: View {
    let dashboard: GradesDashboard
    let compact: Bool

    var body: some View {
        VStack(spacing: Spacing.md) {
            row(
                AverageStatCard(d: dashboard, compact: compact).fadeIn(),
                RatioStatCard(d: dashboard, compact: compact).fadeIn(delay: 0.04)
            )
            row(
                DistributionStatCard(d: dashboard, compact: compact).fadeIn(delay: 0.08),
                RecentStatCard(d: dashboard, compact: compact).fadeIn(delay: 0.12)
            )
        }
    }

    @ViewBuilder private func row(_ a: some View, _ b: some View) -> some View {
        if compact {
            HStack(spacing: Spacing.md) {
                Color.clear.aspectRatio(1, contentMode: .fit).overlay { a }
                Color.clear.aspectRatio(1, contentMode: .fit).overlay { b }
            }
        } else {
            HStack(spacing: Spacing.md) {
                a.frame(maxHeight: .infinity)
                b.frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The card every stat shares: header, a body that takes the slack, footer.
private struct StatShell<Header: View, Content: View, Footer: View>: View {
    let compact: Bool
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: compact ? Spacing.sm : Spacing.lg).frame(maxHeight: compact ? .infinity : Spacing.lg)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: compact ? Spacing.sm : Spacing.md).frame(maxHeight: compact ? .infinity : Spacing.md)
            footer
        }
        .padding(compact ? Spacing.md : Spacing.card)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Radius.xl, fill: Palette.card)
    }
}

private struct CardHeader<Pill: View>: View {
    let title: String
    let subtitle: String
    let compact: Bool
    @ViewBuilder var pill: Pill

    var body: some View {
        HStack(alignment: compact ? .center : .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                // One line when compact, so the title shrinks instead of breaking mid-word.
                Text(title)
                    .textStyle(compact ? TextStyle.footnote.weight(.semibold) : .headline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(compact ? 0.68 : 0.78)
                if !compact {
                    Text(subtitle).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            pill
        }
    }
}

private struct StatPill: View {
    let text: String
    var color: Color = Palette.textSecondary
    var fill: Color = Palette.cardAlt

    var body: some View {
        Text(text)
            .textStyle(.caption2)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(fill, in: .capsule)
    }
}

/// Two facts: side by side at full width, stacked with values right-aligned when compact.
private struct CardFooter: View {
    let left: (String, String, Color)
    let right: (String, String, Color)
    let compact: Bool

    var body: some View {
        if compact {
            VStack(spacing: Spacing.xxs) {
                fact(left, fill: true)
                fact(right, fill: true)
            }
        } else {
            HStack {
                fact(left, fill: false)
                Spacer(minLength: Spacing.sm)
                fact(right, fill: false)
            }
        }
    }

    private func fact(_ f: (String, String, Color), fill: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(f.0).textStyle(.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
            if fill { Spacer(minLength: 0) }
            Text(f.1).textStyle(TextStyle.caption.tabularDigits).foregroundStyle(f.2).lineLimit(1)
        }
    }
}

private struct AverageStatCard: View {
    let d: GradesDashboard
    let compact: Bool
    @Environment(\.strings) private var s

    var body: some View {
        let improving = d.delta >= 0
        let trend = improving ? Brand.success : Brand.danger
        let line = d.hasGrades ? GradesLook.band(d.overallAvg) : Palette.textTertiary
        StatShell(compact: compact) {
            CardHeader(title: s.grades.avgTitle, subtitle: s.grades.avgSub, compact: compact) {
                StatPill(text: "\(improving ? "↗" : "↘") \(GradesLook.num(abs(d.delta), s))", color: trend, fill: trend.opacity(0.14))
            }
        } content: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(d.hasGrades ? GradesLook.num(d.overallAvg, s) : "–")
                    .textStyle(compact ? .statMedium : .statLarge)
                    .foregroundStyle(line)
                    .contentTransition(.numericText())
                Sparkline(d: d, color: line)
                    .frame(height: compact ? 34 : 64)
            }
        } footer: {
            CardFooter(
                left: (s.grades.prevMonth, d.hasGrades ? GradesLook.num(d.previousMonthAvg, s) : "–", Palette.textPrimary),
                right: (s.grades.bestGrade, d.best > 0 ? GradesLook.num(d.best, s) : "—", Palette.textPrimary),
                compact: compact
            )
        }
    }
}

/// The running average per month. A tap shows that month and the average so far.
private struct Sparkline: View {
    let d: GradesDashboard
    let color: Color
    @State private var picked: Int?
    @Environment(\.strings) private var s

    var body: some View {
        let points = d.spark
        if points.isEmpty {
            // No data yet: a faint baseline, so the card still reads as "a chart lives here".
            Capsule().fill(color.opacity(0.28)).frame(height: 1.5).frame(maxHeight: .infinity)
        } else {
            let line: [(x: Double, y: Double)] = points.count == 1
                ? [(0, points[0].avg), (1, points[0].avg)]
                : points.map { (Double($0.id), $0.avg > 0 ? $0.avg : d.sparkMin) }
            let maxX = max(1, Double(points.count - 1))
            Chart {
                ForEach(Array(line.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("x", p.x), yStart: .value("min", d.sparkMin), yEnd: .value("avg", p.y))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.18), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("x", p.x), y: .value("avg", p.y))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                if points.count > 1 {
                    ForEach(points) { p in
                        PointMark(x: .value("x", Double(p.id)), y: .value("avg", p.avg > 0 ? p.avg : d.sparkMin))
                            .foregroundStyle(color.opacity(picked == p.id ? 1 : 0.45))
                            .symbolSize(picked == p.id ? 40 : 14)
                    }
                }
                if let i = picked, i < points.count {
                    let p = points[i]
                    PointMark(x: .value("x", points.count == 1 ? 0.5 : Double(i)), y: .value("avg", p.avg))
                        .symbolSize(0)
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text("\(p.label) · Ø \(GradesLook.num(p.avg, s))")
                                .textStyle(TextStyle.caption2.weight(.bold))
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize()
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Palette.nested, in: .pokyh(Radius.sm))
                        }
                }
            }
            .chartXScale(domain: 0...maxX)
            .chartYScale(domain: d.sparkMin...d.sparkMax)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(.rect)
                        .onTapGesture { location in
                            guard let frame = proxy.plotFrame else { return }
                            let x = location.x - geo[frame].minX
                            guard let value: Double = proxy.value(atX: x) else { return }
                            let hit = min(points.count - 1, max(0, Int(value.rounded())))
                            withAnimation(.easeOut(duration: Motion.fast)) { picked = picked == hit ? nil : hit }
                        }
                }
            }
        }
    }
}

private struct RatioStatCard: View {
    let d: GradesDashboard
    let compact: Bool
    @Environment(\.strings) private var s

    var body: some View {
        StatShell(compact: compact) {
            CardHeader(title: s.grades.ratioTitle, subtitle: s.grades.ratioSub, compact: compact) {
                StatPill(text: "\(Int(d.passRate.rounded())) %")
            }
        } content: {
            VStack(alignment: .leading, spacing: compact ? Spacing.md : Spacing.lg) {
                HStack(alignment: .lastTextBaseline, spacing: compact ? Spacing.sm : Spacing.md) {
                    Text("\(d.pos)").textStyle(compact ? .statMedium : .statLarge).foregroundStyle(Brand.success)
                    Text("/")
                        .textStyle((compact ? TextStyle.title3 : .title1).weight(.light))
                        .foregroundStyle(Palette.textTertiary)
                    Text("\(d.neg)").textStyle(compact ? .statSmall : .statMedium).foregroundStyle(Brand.danger)
                }
                RatioBar(passRate: d.passRate, hasGrades: d.hasGrades, height: 6)
            }
        } footer: {
            CardFooter(
                left: (s.grades.above6, "\(d.pos)", Brand.success),
                right: (s.grades.below6, "\(d.neg)", Brand.danger),
                compact: compact
            )
        }
    }
}

/// Green for the pass share, red for the rest, on the recessed track.
struct RatioBar: View {
    let passRate: Double
    let hasGrades: Bool
    var height: CGFloat = 6
    var gap: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let share = min(1, max(0, passRate / 100))
            HStack(spacing: hasGrades && share > 0 && share < 1 ? gap : 0) {
                if hasGrades {
                    if share > 0 { Capsule().fill(Brand.success).frame(width: (geo.size.width - gap) * share) }
                    if share < 1 { Capsule().fill(Brand.danger) }
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
            .background(Palette.cardAlt, in: .capsule)
        }
        .frame(height: height)
    }
}

private struct DistributionStatCard: View {
    let d: GradesDashboard
    let compact: Bool
    @Environment(\.strings) private var s

    var body: some View {
        StatShell(compact: compact) {
            CardHeader(title: s.grades.distTitle, subtitle: s.grades.distSub, compact: compact) {
                StatPill(text: "σ \(GradesLook.num(d.sigma, s))")
            }
        } content: {
            Group {
                if compact {
                    // The square tile has about 60pt for the ring; labels would be smudges there.
                    DistributionDonut(segments: d.segments, showLabels: false)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(minHeight: 40, maxHeight: .infinity)
                } else {
                    DistributionDonut(segments: d.segments, showLabels: true)
                        .frame(width: 168, height: 168)
                }
            }
            .frame(maxWidth: .infinity)
        } footer: {
            CardFooter(
                left: (s.grades.mode, d.hasGrades ? "\(d.mode)" : "—", Palette.textPrimary),
                right: (s.grades.median, d.hasGrades ? GradesLook.num(d.median, s) : "—", Palette.textPrimary),
                compact: compact
            )
        }
    }
}

/// The web's donut in its 110×110 viewBox: radius 29, stroke 16. A tap on an arc keeps it bright
/// and puts its count in the hole.
private struct DistributionDonut: View {
    let segments: [GradesDashboard.Segment]
    let showLabels: Bool
    @State private var selected: Int?
    @Environment(\.strings) private var s

    private static let viewport = 110.0, cx = 55.0, cy = 55.0, radius = 29.0, stroke = 16.0

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Self.viewport
            let origin = CGPoint(x: (geo.size.width - Self.viewport * scale) / 2, y: (geo.size.height - Self.viewport * scale) / 2)
            Canvas { ctx, _ in
                let center = CGPoint(x: origin.x + Self.cx * scale, y: origin.y + Self.cy * scale)
                let r = Self.radius * scale
                let lineWidth = Self.stroke * scale
                if segments.isEmpty {
                    ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                               with: .color(Palette.cardAlt), lineWidth: lineWidth)
                    return
                }
                for seg in segments {
                    var path = Path()
                    path.addArc(center: center, radius: r, startAngle: .radians(seg.start), endAngle: .radians(seg.start + seg.sweep), clockwise: false)
                    ctx.stroke(path, with: .color(color(seg.grade)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
                if let seg = segments.first(where: { $0.grade == selected }) {
                    let text = Text(s.grades.distTimes(seg.count))
                        .font(.system(size: max(14 * scale, 13), weight: .bold))
                        .foregroundColor(PokyhDesign.Palette.distribution(seg.grade))
                    ctx.draw(text, at: center)
                }
                guard showLabels else { return }
                let outer = Self.radius + Self.stroke / 2 + 1, tickEnd = outer + 6, labelR = outer + 13
                for seg in segments where seg.sweep >= 0.18 {
                    let mid = seg.start + seg.sweep / 2
                    func at(_ radius: Double) -> CGPoint {
                        CGPoint(x: center.x + radius * scale * cos(mid), y: center.y + radius * scale * sin(mid))
                    }
                    var tick = Path()
                    tick.move(to: at(outer))
                    tick.addLine(to: at(tickEnd))
                    ctx.stroke(tick, with: .color(color(seg.grade).opacity(0.8)), lineWidth: 1.2 * scale)
                    ctx.draw(Text("\(seg.grade)").font(.system(size: 9 * scale, weight: .bold)).foregroundColor(color(seg.grade)), at: at(labelR))
                }
            }
            .contentShape(.rect)
            .onTapGesture { location in
                let dx = (location.x - origin.x) / scale - Self.cx
                let dy = (location.y - origin.y) / scale - Self.cy
                let dist = (dx * dx + dy * dy).squareRoot()
                guard dist >= Self.radius - 14, dist <= Self.radius + 14 else { selected = nil; return }
                var angle = atan2(dy, dx)
                if angle < -Double.pi / 2 { angle += 2 * .pi }
                let hit = segments.first { angle >= $0.start - 0.02 && angle <= $0.start + $0.sweep + 0.02 }
                withAnimation(.easeOut(duration: Motion.fast)) {
                    selected = hit == nil || hit?.grade == selected ? nil : hit?.grade
                }
            }
        }
        .accessibilityLabel(s.grades.distHint)
    }

    private func color(_ grade: Int) -> Color {
        PokyhDesign.Palette.distribution(grade).opacity(selected == nil || selected == grade ? 1 : 0.35)
    }
}

private struct RecentStatCard: View {
    let d: GradesDashboard
    let compact: Bool
    @Environment(\.strings) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: s.grades.recentTitle, subtitle: s.grades.recentSub(d.recent.count), compact: compact) { EmptyView() }
            if d.recent.isEmpty {
                Text(s.grades.recentEmpty)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(compact ? .center : .leading)
                    .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil, alignment: compact ? .center : .leading)
                    .padding(.top, compact ? 0 : Spacing.lg)
            } else if compact {
                // Three equal bands that fill the tile, one line each.
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        if i > 0 && i < d.recent.count { Rectangle().fill(Palette.separator).frame(height: 1) }
                        Group {
                            if i < d.recent.count {
                                let item = d.recent[i]
                                HStack(spacing: Spacing.xs) {
                                    Text(item.subject)
                                        .textStyle(TextStyle.footnote.weight(.semibold))
                                        .foregroundStyle(Palette.textPrimary)
                                        .lineLimit(1)
                                    Text(Fmt.dateShort(item.date))
                                        .textStyle(TextStyle.caption2.tabularDigits)
                                        .foregroundStyle(Palette.textTertiary)
                                        .lineLimit(1)
                                        .fixedSize()
                                    Spacer(minLength: 0)
                                    Text(GradesLook.num(item.value, s))
                                        .textStyle(TextStyle.footnote.weight(.semibold).tabularDigits)
                                        .foregroundStyle(GradesLook.band(item.value))
                                        .fixedSize()
                                }
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .padding(.top, Spacing.md)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(d.recent) { item in
                        let tone = recentTone(item.value)
                        HStack(spacing: Spacing.xs) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.subject).textStyle(.headline).foregroundStyle(Palette.textPrimary).lineLimit(1)
                                Text(Fmt.dateShort(item.date)).textStyle(TextStyle.caption2.tabularDigits).foregroundStyle(Palette.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(GradesLook.num(item.value, s))
                                .textStyle(TextStyle.subheadline.weight(.bold).tabularDigits)
                                .foregroundStyle(tone.ink)
                                .padding(.horizontal, Spacing.sm)
                                .frame(minWidth: 44, minHeight: 34)
                                .background(tone.fill, in: .pokyh(11))
                        }
                    }
                }
                .padding(.top, Spacing.lg)
            }
        }
        .padding(compact ? Spacing.md : Spacing.card)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Radius.xl, fill: Palette.card)
    }

    /// Sage for a pass, butter below, blush when critical.
    private func recentTone(_ v: Double) -> Tone {
        if v >= 6 { return Decorative.sage }
        if v > 4 { return Decorative.butter }
        return Decorative.blush
    }
}

// ── Loading ─────────────────────────────────────────────────────────────────

private struct GradesSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                SkeletonBlock(height: 11, width: 210)
                VStack(spacing: Spacing.md) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: Spacing.md) {
                            ForEach(0..<2, id: \.self) { _ in
                                Color.clear.aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        VStack(alignment: .leading, spacing: Spacing.md) {
                                            SkeletonBlock(height: 12, width: 90)
                                            Spacer()
                                            SkeletonBlock(height: 28, width: 70)
                                            SkeletonBlock(height: 10)
                                        }
                                        .padding(Spacing.md)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .cardSurface(radius: Radius.xl, fill: Palette.card)
                                    }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.headerContent) {
                    SkeletonBlock(height: 18, width: 90)
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { i in
                            if i > 0 { RowSeparator(inset: 0) }
                            HStack(spacing: Spacing.md) {
                                SkeletonBlock(height: 24, width: 84)
                                SkeletonBlock(height: 10, width: 52)
                                Spacer()
                                SkeletonBlock(height: 16, width: 30)
                            }
                            .frame(height: 56)
                            .padding(.horizontal, Spacing.card)
                        }
                    }
                    .cardSurface(radius: Radius.xl, fill: Palette.card)
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxxl)
        }
        .scrollDisabled(true)
    }
}
