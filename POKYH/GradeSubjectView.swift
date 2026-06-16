import SwiftUI

/// Fach-Detail mit Notenrechner + Zielnote-Rechner — 1:1 wie das Frontend.
struct GradeSubjectView: View {
    let lessonId: Int
    let subjects: [SubjectGrades]

    @State private var draft = GradeDraft()
    @State private var newGradeInput = ""
    @State private var targetInput = ""

    private var subject: SubjectGrades? { subjects.first { $0.lessonId == lessonId } }

    private struct TeacherRow: Identifiable { let id: Int; let label: String; let date: Int; let value: Double; let removed: Bool }

    private var teacherRows: [TeacherRow] {
        guard let subject else { return [] }
        let removed = Set(draft.removedTeacherGradeIds)
        return subject.grades.sorted { $0.date > $1.date }.map {
            TeacherRow(id: $0.id, label: gradeDisplay($0), date: $0.date,
                       value: GradeMath.round2($0.markDisplayValue), removed: removed.contains($0.id))
        }
    }
    private var liveValues: [Double] {
        teacherRows.filter { !$0.removed }.map { $0.value } + draft.customGrades
    }
    private var liveAvg: Double { GradeMath.averageOf(liveValues) }
    private var positive: Int { liveValues.filter { $0 >= 6 }.count }
    private var negative: Int { liveValues.filter { $0 < 6 }.count }
    private var hasDraft: Bool { !draft.isEmpty }
    private var targetResult: GradeMath.TargetResult? { GradeMath.target(targetInput, values: liveValues) }

    /// Chronologisch (Lehrernoten nach Datum + eigene am Ende) für den Trend.
    private var chronological: [Double] {
        guard let subject else { return [] }
        let removed = Set(draft.removedTeacherGradeIds)
        let teacher = subject.grades.filter { !removed.contains($0.id) }
            .sorted { $0.date < $1.date }.map { GradeMath.round2($0.markDisplayValue) }
        return teacher + draft.customGrades
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                averageCard.fadeIn()
                if chronological.count >= 2 { TrendChart(values: chronological).fadeIn(delay: 0.05) }
                gradesCard.fadeIn(delay: 0.08)
                targetCard.fadeIn(delay: 0.12)
                if hasDraft {
                    Button(role: .destructive) { reset() } label: {
                        Label("Rechner zurücksetzen", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(Palette.danger)
                    .fadeIn(delay: 0.15)
                }
            }
            .padding(16)
        }
        .navigationTitle(subject?.subjectName ?? "Fach")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .onAppear { draft = GradeDraftStore.get(lessonId) }
        .onChange(of: draft) { _, new in GradeDraftStore.set(lessonId, new) }
    }

    // ── Schnitt ───────────────────────────────────────────────────────────────
    private var averageCard: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hasDraft ? "Schnitt (mit Rechner)" : "Schnitt").font(.caption).foregroundStyle(Palette.textSecondary)
                Text(liveAvg > 0 ? Fmt.num(liveAvg) : "–")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(liveAvg > 0 ? Palette.grade(liveAvg) : Palette.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: liveAvg)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                pill("\(positive) positiv", Palette.tint)
                pill("\(negative) negativ", Palette.danger)
                Text("\(liveValues.count) Noten").font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(18).cardSurface(radius: 18)
    }
    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }

    // ── Noten + Notenrechner ──────────────────────────────────────────────────
    private var gradesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Noten").font(.headline).foregroundStyle(Palette.textPrimary)
            ForEach(teacherRows) { row in
                gradeRow(value: row.value, label: row.label, sub: Fmt.dateFull(row.date),
                         removed: row.removed, isCustom: false) {
                    if row.removed { draft.removedTeacherGradeIds.removeAll { $0 == row.id } }
                    else { draft.removedTeacherGradeIds.append(row.id) }
                }
            }
            ForEach(Array(draft.customGrades.enumerated()), id: \.offset) { idx, val in
                gradeRow(value: val, label: "Eigene Note", sub: "Notenrechner",
                         removed: false, isCustom: true) {
                    draft.customGrades.remove(at: idx)
                }
            }

            HStack(spacing: 8) {
                TextField("Note (1–10)", text: $newGradeInput)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Palette.cardAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button { addCustom() } label: {
                    Label("Hinzufügen", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent).tint(Palette.accent)
                .disabled(GradeMath.parseGradeInput(newGradeInput) == nil)
            }
            .padding(.top, 4)
        }
        .padding(16).cardSurface()
    }

    private func gradeRow(value: Double, label: String, sub: String, removed: Bool, isCustom: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(Fmt.num(value, digits: value == value.rounded() ? 0 : 1))
                .font(.headline.monospacedDigit())
                .frame(width: 42, height: 42)
                .background((removed ? Color.gray : Palette.grade(value)).opacity(0.18), in: Circle())
                .foregroundStyle(removed ? Palette.textTertiary : Palette.grade(value))
                .overlay(removed ? Circle().strokeBorder(Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3])) : nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline.weight(.medium))
                    .foregroundStyle(removed ? Palette.textTertiary : Palette.textPrimary)
                    .strikethrough(removed)
                HStack(spacing: 4) {
                    if isCustom { Image(systemName: "function").font(.caption2).foregroundStyle(Palette.accent) }
                    Text(sub).font(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer()
            Button(action: action) {
                Image(systemName: isCustom ? "trash" : (removed ? "arrow.uturn.backward" : "xmark"))
                    .font(.footnote)
                    .foregroundStyle(isCustom ? Palette.danger : (removed ? Palette.accent : Palette.textTertiary))
            }.buttonStyle(.pressable)
        }
        .padding(.vertical, 2)
    }

    // ── Zielnote-Rechner ──────────────────────────────────────────────────────
    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Zielnote-Rechner", systemImage: "target").font(.headline).foregroundStyle(Palette.textPrimary)
            TextField("Zielnote (z. B. 7)", text: $targetInput)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Palette.cardAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let r = targetResult {
                Text(targetText(r)).font(.subheadline).foregroundStyle(targetColor(r))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else if !targetInput.isEmpty {
                Text("Gib eine gültige Note (1–10) ein.").font(.caption).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(16).cardSurface()
        .animation(.easeInOut, value: targetResult?.needed)
    }

    private func targetText(_ r: GradeMath.TargetResult) -> String {
        switch r.status {
        case .reached: return "Du hast die Zielnote \(Fmt.num(r.target)) bereits erreicht."
        case .impossible: return "Die Zielnote \(Fmt.num(r.target)) ist nicht erreichbar."
        case .reachable:
            let verb = liveAvg < r.target ? "mindestens" : "höchstens"
            let noun = r.count == 1 ? "Note" : "Noten"
            return "Du brauchst \(r.count) \(noun) mit \(verb) \(Fmt.num(r.needed)), um \(Fmt.num(r.target)) zu erreichen."
        }
    }
    private func targetColor(_ r: GradeMath.TargetResult) -> Color {
        switch r.status {
        case .reached: return Palette.tint
        case .impossible: return Palette.danger
        case .reachable: return Palette.textSecondary
        }
    }

    // ── Aktionen ──────────────────────────────────────────────────────────────
    private func addCustom() {
        guard let v = GradeMath.parseGradeInput(newGradeInput) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            draft.customGrades.append(v)
        }
        newGradeInput = ""
    }
    private func reset() {
        withAnimation { draft = GradeDraft(); newGradeInput = ""; targetInput = "" }
    }
}

/// Schlichter Trend-Sparkline (SwiftUI Path).
struct TrendChart: View {
    let values: [Double]
    private let yTicks: [Double] = [10, 8, 6, 4, 2]   // Y-Achse: Note
    private let chartHeight: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Notenverlauf", systemImage: "chart.xyaxis.line").font(.caption.bold()).foregroundStyle(Palette.textSecondary)
                Spacer()
                legendDot(Palette.accent.opacity(0.6), "Noten")
                legendDot(Palette.grade(cumulativeAverages.last ?? 0), "Ø")
                legendDot(Palette.orange, "Trend \(trendArrow)")
            }

            HStack(alignment: .top, spacing: 8) {
                // Y-Achse (Note)
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(yTicks, id: \.self) { t in
                        Text(Fmt.num(t, digits: 0)).font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
                        if t != yTicks.last { Spacer(minLength: 0) }
                    }
                }
                .frame(width: 16, height: chartHeight)

                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let gradePts = points(values, in: CGSize(width: w, height: h))
                    let cumAvgs = cumulativeAverages
                    let avgPts = points(cumAvgs, in: CGSize(width: w, height: h))
                    let finalAvg = cumAvgs.last ?? 0
                    let avgColor = Palette.grade(finalAvg)
                    ZStack {
                        // Hilfslinien je Note
                        ForEach(yTicks, id: \.self) { t in
                            let y = h - CGFloat((t - 1) / 9) * h
                            Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                                .stroke((t == 6 ? Palette.tint : Palette.separator).opacity(t == 6 ? 0.5 : 0.4),
                                        style: StrokeStyle(lineWidth: t == 6 ? 1 : 0.5, dash: t == 6 ? [4] : []))
                        }
                        // Einzelnoten – feine Linie + Punkte (die „Kurse")
                        Path { p in
                            guard let first = gradePts.first else { return }
                            p.move(to: first); for pt in gradePts.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(Palette.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        ForEach(Array(gradePts.enumerated()), id: \.offset) { _, pt in
                            Circle().fill(Palette.accent).frame(width: 5, height: 5).position(pt)
                        }
                        // Kumulativer Durchschnitt (laufender Mittelwert – wie ein Moving Average)
                        Path { p in
                            guard let first = avgPts.first else { return }
                            p.move(to: first); for pt in avgPts.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(avgColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        // Trend-„Stich": dünne lineare Regression – zeigt, ob es steigt/sinkt.
                        if let r = regression {
                            let y0 = yFor(r.intercept, h)
                            let y1 = yFor(r.slope * Double(values.count - 1) + r.intercept, h)
                            Path { p in p.move(to: CGPoint(x: 0, y: y0)); p.addLine(to: CGPoint(x: w, y: y1)) }
                                .stroke(Palette.orange.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                        }
                        // Endpunkt + Label = aktueller Gesamtschnitt
                        if let last = avgPts.last {
                            Circle().fill(avgColor).frame(width: 7, height: 7).position(last)
                            Text("Ø \(Fmt.num(finalAvg))")
                                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(avgColor, in: Capsule())
                                .position(x: min(w - 22, last.x), y: max(9, last.y - 12))
                        }
                    }
                }
                .frame(height: chartHeight)
            }

            // X-Achse (Reihenfolge der Noten)
            HStack {
                Text("Note 1").font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("Note \(values.count)").font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
            }
            .padding(.leading, 24)
        }
        .padding(16).cardSurface()
    }

    /// Laufender (kumulativer) Mittelwert: an Position i der Schnitt aller Noten bis i.
    /// Eigene eingegebene Noten sind in `values` bereits enthalten.
    private var cumulativeAverages: [Double] {
        var sum = 0.0
        return values.enumerated().map { i, v in sum += v; return sum / Double(i + 1) }
    }

    /// Mappt eine Wertreihe gleichmäßig über die Breite (Y = Note 1…10).
    private func points(_ vals: [Double], in size: CGSize) -> [CGPoint] {
        guard !vals.isEmpty else { return [] }
        guard vals.count > 1 else {
            let y = size.height - CGFloat((min(10, max(1, vals[0])) - 1) / 9) * size.height
            return [CGPoint(x: size.width / 2, y: y)]
        }
        return vals.enumerated().map { idx, v in
            let x = CGFloat(idx) / CGFloat(vals.count - 1) * size.width
            let y = size.height - CGFloat((min(10, max(1, v)) - 1) / 9) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    /// Lineare Regression über die Noten (x = Index, y = Note) für die Trendlinie.
    private var regression: (slope: Double, intercept: Double)? {
        let n = values.count
        guard n >= 2 else { return nil }
        let meanX = Double(n - 1) / 2
        let meanY = values.reduce(0, +) / Double(n)
        var num = 0.0, den = 0.0
        for i in 0..<n {
            let dx = Double(i) - meanX
            num += dx * (values[i] - meanY); den += dx * dx
        }
        guard den != 0 else { return nil }
        let slope = num / den
        return (slope, meanY - slope * meanX)
    }

    /// Trendrichtung als Pfeil für die Legende.
    private var trendArrow: String {
        guard let r = regression else { return "→" }
        if r.slope > 0.05 { return "↗" }
        if r.slope < -0.05 { return "↘" }
        return "→"
    }

    /// Note → Y-Position (Skala 1…10), geklemmt.
    private func yFor(_ v: Double, _ h: CGFloat) -> CGFloat {
        h - CGFloat((min(10, max(1, v)) - 1) / 9) * h
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
        }
    }
}
