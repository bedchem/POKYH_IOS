import SwiftUI
import Charts
import PokyhCore
import PokyhDesign

// A subject zoomed in: average, ratio and target calculator up top, then the trend, the grade
// list and the average calculator. Excluded and added grades are a local draft per subject.

struct GradeSubjectView: View {
    let lessonId: Int
    let subjects: [SubjectGrades]

    @Environment(\.strings) private var s
    @State private var draft = GradeDraft()
    @State private var newGradeInput = ""
    @State private var targetInput = ""
    @State private var width: CGFloat = 0

    private var subject: SubjectGrades? { subjects.first { $0.lessonId == lessonId } }

    private struct TeacherRow: Identifiable { let id: Int; let label: String; let date: Int; let value: Double; let removed: Bool }

    private var teacherRows: [TeacherRow] {
        guard let subject else { return [] }
        let removed = Set(draft.removedTeacherGradeIds)
        return subject.grades.filter { $0.date > 0 }.sorted { $0.date > $1.date }.map {
            TeacherRow(id: $0.id, label: gradeDisplay($0, exam: s.grades.exam), date: $0.date,
                       value: GradeMath.round2($0.markDisplayValue), removed: removed.contains($0.id))
        }
    }
    private var liveValues: [Double] { teacherRows.filter { !$0.removed }.map(\.value) + draft.customGrades }
    private var hasDraft: Bool { !draft.isEmpty }

    /// Teacher grades by date, the own ones after them.
    private var chronological: [GradeTrendPoint] {
        teacherRows.filter { !$0.removed }.sorted { $0.date < $1.date }
            .map { GradeTrendPoint(value: $0.value, date: $0.date, label: $0.label, own: false) }
            + draft.customGrades.map { GradeTrendPoint(value: $0, date: nil, label: s.grades.ownGrade, own: true) }
    }

    private var subtitle: String {
        guard let subject else { return "" }
        var parts: [String] = []
        if !subject.teacherName.isEmpty { parts.append(subject.teacherName) }
        if let last = subject.grades.map(\.date).filter({ $0 > 0 }).max() {
            parts.append("\(s.grades.lastGrade) \(Fmt.dateFull(last))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if subject == nil {
                EmptyStateView(systemImage: "magnifyingglass", title: s.grades.subjectNotFound)
            } else {
                content
            }
        }
        .navigationTitle(subject?.subjectName ?? s.grades.subject)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .appBackground()
        .onAppear { draft = GradeDraftStore.get(lessonId) }
        .onChange(of: draft) { _, new in GradeDraftStore.set(lessonId, new) }
    }

    private var content: some View {
        let values = liveValues
        let avg = GradeMath.averageOf(values)
        let teacherAvg = GradeMath.averageOf(teacherRows.map(\.value))
        let points = chronological
        let trend: Int = {
            guard points.count >= 2, let first = points.first, let last = points.last else { return 0 }
            let d = last.value - first.value
            return abs(d) < 0.3 ? 0 : (d > 0 ? 1 : -1)
        }()
        let wide = WidthClass(width: width) != .compact
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            averageCard(avg, values, teacherAvg, trend).frame(maxHeight: .infinity)
                            ratioCard(values).frame(maxHeight: .infinity)
                            targetCard(values).frame(maxHeight: .infinity)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: Spacing.md) {
                            averageCard(avg, values, teacherAvg, trend)
                            ratioCard(values)
                            targetCard(values)
                        }
                    }
                }
                .fadeIn()

                PokyhSection(s.grades.trendTitle) {
                    if hasDraft {
                        TextLinkButton(s.grades.reset, symbol: "arrow.counterclockwise") { reset() }
                    }
                } content: {
                    if points.isEmpty {
                        Text(s.grades.noGradesYet).textStyle(.callout).foregroundStyle(Palette.textTertiary)
                    } else {
                        TrendChart(points: points)
                    }
                    Text(s.grades.trendSub).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                        .padding(.top, Spacing.xs)
                }
                .fadeIn(delay: 0.05)

                gradesSection.fadeIn(delay: 0.08)
                calcSection.fadeIn(delay: 0.11)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    // ── Schnitt · Notenverhältnis · Was brauche ich? ─────────────────────────

    private func averageCard(_ avg: Double, _ values: [Double], _ teacherAvg: Double, _ trend: Int) -> some View {
        let tone = avg > 0 ? GradesLook.tone(avg) : Tone(fill: Palette.card, ink: Palette.textPrimary)
        let chip: (String, String, Tone) = switch trend {
        case 1: (s.grades.rising, "arrow.up.right", Decorative.sage)
        case -1: (s.grades.falling, "arrow.down.right", Decorative.blush)
        default: (s.grades.stable, "arrow.right", Tone(fill: Palette.nested, ink: Palette.textSecondary))
        }
        let delta = avg > 0 && teacherAvg > 0 ? avg - teacherAvg : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.grades.average).textStyle(TextStyle.callout.weight(.bold)).foregroundStyle(tone.ink)
                    Text(s.grades.gradeCount(values.count) + (hasDraft ? " · \(s.grades.simulation)" : ""))
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .foregroundStyle(tone.ink.opacity(0.75))
                }
                Spacer(minLength: Spacing.sm)
                HStack(spacing: Spacing.xs) {
                    Image(systemName: chip.1).font(.system(size: 11, weight: .bold))
                    Text(chip.0).textStyle(TextStyle.caption.weight(.bold))
                }
                .foregroundStyle(chip.2.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(chip.2.fill, in: .capsule)
            }
            Spacer(minLength: Spacing.lg)
            HStack(alignment: .lastTextBaseline) {
                Text(avg > 0 ? GradesLook.num(avg, s) : "—")
                    .textStyle(.statLarge)
                    .foregroundStyle(tone.ink)
                    .contentTransition(.numericText())
                    .animation(Motion.smooth, value: avg)
                Spacer(minLength: Spacing.sm)
                if hasDraft && abs(delta) > 0.005 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(s.grades.teacherAvg) \(GradesLook.num(teacherAvg, s))")
                            .textStyle(TextStyle.caption.weight(.semibold))
                            .foregroundStyle(tone.ink.opacity(0.8))
                        Text((delta >= 0 ? "+" : "−") + GradesLook.num(abs(delta), s))
                            .textStyle(TextStyle.callout.weight(.heavy))
                            .foregroundStyle(tone.ink)
                    }
                } else if let best = values.max() {
                    Text(s.grades.best(GradesLook.num(best, s)))
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .foregroundStyle(tone.ink.opacity(0.8))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Radius.xxl, fill: tone.fill)
    }

    private func ratioCard(_ values: [Double]) -> some View {
        let positive = values.filter { $0 >= 6 }.count
        let negative = values.count - positive
        let rate = values.isEmpty ? 0 : Double(positive) * 100 / Double(values.count)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.grades.ratioTitle).textStyle(TextStyle.callout.weight(.bold)).foregroundStyle(Palette.textPrimary)
                    Text(s.grades.ratioSub).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Text("\(Int(rate.rounded())) %")
                    .textStyle(TextStyle.caption.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Palette.nested, in: .capsule)
            }
            Spacer(minLength: Spacing.lg)
            HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                Text("\(positive)").textStyle(.statLarge).foregroundStyle(Brand.success)
                Text("/").textStyle(.title2).foregroundStyle(Palette.textTertiary)
                Text("\(negative)").textStyle(TextStyle.title1.weight(.heavy)).foregroundStyle(Brand.danger)
            }
            RatioBar(passRate: rate, hasGrades: !values.isEmpty, height: 8, gap: 3)
                .padding(.top, Spacing.md)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Radius.xxl, fill: Palette.card)
    }

    private func targetCard(_ values: [Double]) -> some View {
        let tone = Decorative.periwinkle
        let r = GradeMath.target(targetInput, values: values)
        let hint: String = {
            guard let r else { return s.grades.hintEnter }
            switch r.status {
            case .reached: return s.grades.hintReached
            case .impossible: return s.grades.hintImpossible
            case .reachable: return r.count == 1 ? s.grades.hintNext : s.grades.hintMany(r.count, GradesLook.num(r.needed, s))
            }
        }()
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.grades.whatDoINeed).textStyle(TextStyle.callout.weight(.bold)).foregroundStyle(tone.ink)
                    Text(s.grades.targetCalc).textStyle(TextStyle.footnote.weight(.semibold)).foregroundStyle(tone.ink.opacity(0.75))
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "target").font(.system(size: 18, weight: .semibold)).foregroundStyle(tone.ink)
            }
            HStack(spacing: Spacing.md) {
                TextField("", text: gradeBinding($targetInput), prompt: Text(s.grades.targetShort).foregroundStyle(tone.ink.opacity(0.55)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .textStyle(TextStyle.title2.weight(.heavy))
                    .foregroundStyle(tone.ink)
                    .tint(tone.ink)
                    .frame(width: 96)
                    .padding(.vertical, Spacing.md)
                    .background(tone.ink.opacity(0.12), in: .pokyh(Radius.lg))
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(tone.ink)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    if let r, r.status == .reachable {
                        if r.count > 1 {
                            Text("\(r.count)× ").textStyle(.headline).foregroundStyle(tone.ink.opacity(0.75))
                        }
                        Text(GradesLook.num(r.needed, s))
                    } else {
                        Text(r == nil ? "-" : (r?.status == .reached ? "✓" : "✕"))
                    }
                }
                .textStyle(TextStyle.title1.weight(.heavy))
                .foregroundStyle(tone.ink)
                .contentTransition(.numericText())
            }
            Text(hint).textStyle(TextStyle.footnote.weight(.semibold)).foregroundStyle(tone.ink.opacity(0.8))
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Radius.xxl, fill: tone.fill)
        .animation(.easeInOut(duration: Motion.fast), value: r?.needed)
    }

    // ── Noten-Liste ──────────────────────────────────────────────────────────

    private var gradesSection: some View {
        let rows = teacherRows
        return PokyhSection(s.grades.gradeList) {
            Text(s.grades.activeExcluded(rows.filter { !$0.removed }.count, rows.filter(\.removed).count))
                .textStyle(TextStyle.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
        } content: {
            if rows.isEmpty {
                Text(s.grades.noGradesYet).textStyle(.callout).foregroundStyle(Palette.textTertiary)
            } else {
                ListCard(rows) { row in teacherGradeRow(row) }
            }
        }
    }

    private func teacherGradeRow(_ row: TeacherRow) -> some View {
        let tone = GradesLook.tone(row.value)
        return HStack(spacing: Spacing.iconText) {
            Text(GradesLook.num(row.value, s))
                .textStyle(TextStyle.callout.weight(.heavy).tabularDigits)
                .strikethrough(row.removed)
                .foregroundStyle(row.removed ? Palette.textTertiary : tone.ink)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 10)
                .frame(minWidth: 52)
                .background(row.removed ? Palette.nested : tone.fill, in: .pokyh(Radius.md))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.label).textStyle(TextStyle.callout.weight(.semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Text("\(Fmt.dateShort(row.date)) · \(relativeDay(row.date))").textStyle(.footnote).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.easeInOut(duration: Motion.fast)) {
                    if row.removed { draft.removedTeacherGradeIds.removeAll { $0 == row.id } }
                    else { draft.removedTeacherGradeIds.append(row.id) }
                }
            } label: {
                Image(systemName: row.removed ? "arrow.uturn.backward" : "eye.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 36, height: 36)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.removed ? s.grades.restoreGrade : s.grades.excludeGrade)
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, 10)
        .opacity(row.removed ? 0.45 : 1)
    }

    // ── Mittelwert-Rechner ───────────────────────────────────────────────────

    private var calcSection: some View {
        PokyhSection(s.grades.avgCalc) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(s.grades.avgCalcSub).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                HStack(spacing: Spacing.sm) {
                    TextField("", text: gradeBinding($newGradeInput), prompt: Text(s.grades.examplePlaceholder).foregroundStyle(Palette.textTertiary))
                        .keyboardType(.decimalPad)
                        .textStyle(.body)
                        .foregroundStyle(Palette.textPrimary)
                        .tint(Brand.accent)
                        .padding(.horizontal, Spacing.lg)
                        .frame(minHeight: 48)
                        .background(Palette.cardAlt, in: .pokyh(Radius.md))
                        .onSubmit(addCustom)
                    Button(action: addCustom) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Brand.onAccent)
                            .frame(width: 44, height: 44)
                            .background(Brand.accent.opacity(GradeMath.parseGradeInput(newGradeInput) == nil ? 0.45 : 1), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .disabled(GradeMath.parseGradeInput(newGradeInput) == nil)
                    .accessibilityLabel(s.grades.add)
                }
                // Quick test: a tap adds that grade.
                HStack(spacing: 6) {
                    ForEach(4...10, id: \.self) { v in
                        let tone = GradesLook.tone(Double(v))
                        Button {
                            withAnimation(Motion.snappy) { draft.customGrades.append(Double(v)) }
                        } label: {
                            Text("\(v)")
                                .textStyle(TextStyle.callout.weight(.heavy))
                                .foregroundStyle(tone.ink)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(tone.fill, in: .pokyh(Radius.md))
                        }
                        .buttonStyle(.rowPress(radius: Radius.md))
                    }
                }
                if draft.customGrades.isEmpty {
                    Text(s.grades.noOwnGrades).textStyle(.footnote).foregroundStyle(Palette.textTertiary)
                } else {
                    ChipFlow(spacing: 6) {
                        ForEach(Array(draft.customGrades.enumerated()), id: \.offset) { idx, value in
                            Button {
                                withAnimation(Motion.snappy) { _ = draft.customGrades.remove(at: idx) }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(GradesLook.num(value, s)).textStyle(TextStyle.footnote.weight(.bold)).foregroundStyle(Palette.textPrimary)
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.textTertiary)
                                }
                                .padding(.leading, 12)
                                .padding(.trailing, 8)
                                .padding(.vertical, 6)
                                .background(Palette.nested, in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(s.grades.removeOwnGrade)
                        }
                    }
                }
            }
            .padding(Spacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Radius.xl, fill: Palette.card)
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    /// Up to two digits, a comma or point, two decimals, as the web's grade fields take it.
    private func gradeBinding(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { new in
                if new.range(of: #"^\d{0,2}([.,]\d{0,2})?$"#, options: .regularExpression) != nil {
                    text.wrappedValue = new
                }
            }
        )
    }

    /// "heute", "gestern", "vor 3 Tagen" and so on.
    private func relativeDay(_ date: Int) -> String {
        var c = DateComponents()
        c.year = date / 10000; c.month = (date / 100) % 100; c.day = date % 100
        let cal = Calendar(identifier: .gregorian)
        guard let d = cal.date(from: c) else { return "" }
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        let g = s.grades
        switch diff {
        case ..<1: return g.relToday
        case 1: return g.relYesterday
        case ..<7: return g.daysAgo(diff)
        case ..<30: return g.weeksAgo(Int((Double(diff) / 7).rounded()))
        case ..<365: return g.monthsAgo(Int((Double(diff) / 30).rounded()))
        default: return g.yearsAgo(Int((Double(diff) / 365).rounded()))
        }
    }

    private func addCustom() {
        guard let v = GradeMath.parseGradeInput(newGradeInput) else { return }
        withAnimation(Motion.snappy) { draft.customGrades.append(v) }
        newGradeInput = ""
    }

    private func reset() {
        withAnimation { draft = GradeDraft(); newGradeInput = ""; targetInput = "" }
    }
}

/// Chips that wrap onto the next line.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// ── Trend chart ─────────────────────────────────────────────────────────────

/// One grade on the trend: a teacher's (with its date) or one of the student's own.
struct GradeTrendPoint: Equatable {
    let value: Double
    let date: Int?
    let label: String
    let own: Bool
}

/// Each grade a dot (below 6 red, own ones hollow on a dashed line), the running average as a
/// line, the band under 6 tinted. A tap on a dot shows its date, label, value and average so far.
struct TrendChart: View {
    let points: [GradeTrendPoint]
    @Environment(\.strings) private var s
    @State private var selected: Int?

    private var running: [Double] {
        var sum = 0.0
        return points.enumerated().map { i, p in sum += p.value; return sum / Double(i + 1) }
    }

    var body: some View {
        let run = running
        let lowest = points.map(\.value).min() ?? 6
        let yMin = max(1, min(4, lowest).rounded(.down))
        let avgColor = PokyhDesign.Palette.grade(run.last ?? 6)
        let firstOwn = points.firstIndex { $0.own }
        let n = points.count
        let xDomain = n <= 1 ? -1.0...1.0 : -0.35...(Double(n - 1) + 0.35)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Chart {
                RuleMark(y: .value("6", 6.0))
                    .foregroundStyle(Palette.textTertiary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                if n > 1 {
                    ForEach(Array(run.enumerated()), id: \.offset) { i, a in
                        LineMark(x: .value("i", Double(i)), y: .value("avg", a), series: .value("s", "avg"))
                            .foregroundStyle(avgColor)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
                if let f = firstOwn, f > 0 {
                    ForEach(Array((f - 1)..<n), id: \.self) { i in
                        LineMark(x: .value("i", Double(i)), y: .value("own", points[i].value), series: .value("s", "own"))
                            .foregroundStyle(Palette.textTertiary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    PointMark(x: .value("i", n <= 1 ? 0 : Double(i)), y: .value("grade", p.value))
                        .symbol { dot(p, big: selected == i) }
                }
                if let i = selected, i < n {
                    PointMark(x: .value("i", n <= 1 ? 0 : Double(i)), y: .value("grade", points[i].value))
                        .symbolSize(0)
                        .annotation(position: .top, spacing: 10, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            detailCard(points[i], average: run[i])
                        }
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yMin...10)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: yMin, through: 10, by: 1))) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Palette.textTertiary.opacity(0.15))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))").textStyle(.caption2).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            .chartBackground { proxy in
                // The band under 6.
                GeometryReader { geo in
                    if let anchor = proxy.plotFrame, let y6 = proxy.position(forY: 6.0) {
                        let plot = geo[anchor]
                        Rectangle()
                            .fill(Brand.danger.opacity(0.07))
                            .frame(width: plot.width, height: max(0, plot.height - y6))
                            .offset(x: plot.minX, y: plot.minY + y6)
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(.rect)
                        .onTapGesture { location in
                            guard let anchor = proxy.plotFrame, n > 0 else { return }
                            let x = location.x - geo[anchor].minX
                            guard let v: Double = proxy.value(atX: x) else { return }
                            let hit = n <= 1 ? 0 : min(n - 1, max(0, Int(v.rounded())))
                            withAnimation(.easeOut(duration: Motion.fast)) { selected = selected == hit ? nil : hit }
                        }
                }
            }
            .frame(height: 200)

            // The first, middle and last grade's dates.
            let dated = points.enumerated().compactMap { i, p in p.date.map { (i, $0) } }
            if !dated.isEmpty {
                let shown = [dated.first, dated.count > 2 ? dated[dated.count / 2] : nil, dated.count > 1 ? dated.last : nil].compactMap { $0 }
                HStack {
                    ForEach(Array(shown.enumerated()), id: \.offset) { idx, item in
                        Text(Fmt.dateShort(item.1))
                            .textStyle(.caption2)
                            .foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: idx == 0 ? .leading : (idx == shown.count - 1 ? .trailing : .center))
                    }
                }
                .padding(.leading, 22)
            }

            HStack(spacing: Spacing.md) {
                Circle().fill(avgColor).frame(width: 10, height: 10)
                Text(s.grades.average).textStyle(.caption).foregroundStyle(Palette.textSecondary)
                if firstOwn != nil {
                    Circle().strokeBorder(Palette.textTertiary, lineWidth: 2).frame(width: 10, height: 10)
                    Text(s.grades.ownGrade).textStyle(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .padding(Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.xl, fill: Palette.card)
    }

    @ViewBuilder private func dot(_ p: GradeTrendPoint, big: Bool) -> some View {
        let tone = p.value < 6 ? Brand.danger : Palette.textPrimary
        let size: CGFloat = big ? 12 : 9
        if p.own {
            Circle().fill(Palette.card)
                .overlay(Circle().strokeBorder(tone, lineWidth: 2))
                .frame(width: size, height: size)
        } else {
            Circle().fill(tone).frame(width: size, height: size)
        }
    }

    private func detailCard(_ p: GradeTrendPoint, average: Double) -> some View {
        var head: [String] = []
        if let date = p.date { head.append(Fmt.dateShort(date)) }
        if !p.label.isEmpty { head.append(p.label) }
        return VStack(alignment: .leading, spacing: 1) {
            Text(head.joined(separator: " · "))
                .textStyle(.caption2)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
            Text(GradesLook.num(p.value, s))
                .textStyle(TextStyle.headline.weight(.heavy))
                .foregroundStyle(PokyhDesign.Palette.grade(p.value))
            Text("Ø \(GradesLook.num(average, s))")
                .textStyle(.caption2)
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(width: 120, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.sm)
        .background(Palette.nested, in: .pokyh(Radius.md))
    }
}
