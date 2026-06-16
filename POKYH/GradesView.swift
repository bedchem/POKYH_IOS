import SwiftUI

struct GradesView: View {
    @EnvironmentObject var app: AppState
    @State private var subjects: [SubjectGrades] = []
    @State private var loading = true
    @State private var error: String?
    @State private var year = SchoolDates.currentSchoolYear
    @State private var sort: SortMode = .name
    @State private var yearShown = false   // Header-Slide-In nur einmal

    enum SortMode: String, CaseIterable {
        case name = "Name", avgDesc = "Schnitt ↓", avgAsc = "Schnitt ↑", recent = "Letzte Note"
    }

    /// Gesamtschnitt = flacher Mittelwert ÜBER ALLE Einzelnoten (jede Note gleich
    /// gewichtet), exakt wie im Frontend — NICHT der Mittelwert der Fach-Schnitte.
    private var overallAverage: Double {
        let vals = subjects.flatMap { $0.grades.map { $0.markDisplayValue } }.filter { $0 > 0 }
        return GradeMath.averageOf(vals)
    }

    private struct RecentItem: Identifiable { let id: Int; let subject: String; let value: Double; let date: Int }

    /// „Zuletzt hinzugefügt" = nach Noten-ID absteigend (zuletzt eingetragen),
    /// exakt wie im Frontend (`b.id - a.id`), nicht nach Datum.
    private var recent: [RecentItem] {
        var items: [RecentItem] = []
        for s in subjects {
            for g in s.grades where g.markDisplayValue > 0 {
                items.append(RecentItem(id: g.id, subject: s.subjectName, value: g.markDisplayValue, date: g.date))
            }
        }
        items.sort { $0.id > $1.id }
        return Array(items.prefix(3))
    }

    private var sortedSubjects: [SubjectGrades] {
        switch sort {
        case .name: return subjects.sorted { $0.subjectName.localizedCaseInsensitiveCompare($1.subjectName) == .orderedAscending }
        case .avgDesc: return subjects.sorted { $0.average > $1.average }
        case .avgAsc: return subjects.sorted { $0.average < $1.average }
        case .recent: return subjects.sorted { ($0.grades.map { $0.date }.max() ?? 0) > ($1.grades.map { $0.date }.max() ?? 0) }
        }
    }

    var body: some View {
        Group {
            if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if subjects.isEmpty {
                EmptyStateView(systemImage: "chart.bar", title: "Keine Noten", subtitle: "Für dieses Schuljahr liegen keine Noten vor.")
            } else {
                ScrollView {
                    // VStack (nicht Lazy) → alle Fächer laden direkt, nicht erst beim Scrollen.
                    VStack(spacing: 14) {
                        averageCard.fadeIn()
                        if !recent.isEmpty { recentCard.fadeIn(delay: 0.05) }
                        sortBar.fadeIn(delay: 0.08)
                        ForEach(Array(sortedSubjects.enumerated()), id: \.element.id) { idx, subject in
                            NavigationLink { GradeSubjectView(lessonId: subject.lessonId, subjects: subjects) } label: {
                                SubjectRow(subject: subject)
                            }
                            .buttonStyle(.pressable)
                            .fadeIn(delay: min(0.5, 0.1 + Double(idx) * 0.025))
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Noten")
        .profileToolbar()
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SchoolDates.availableYears, id: \.self) { y in
                        Button("\(String(y))/\(String((y + 1) % 100))") { year = y; Task { await load() } }
                    }
                } label: { Text("\(String(year))/\(String((year + 1) % 100))").font(.subheadline) }
                .slideIn(yearShown)
            }
        }
        .task { withAnimation(.spring(response: 0.6, dampingFraction: 0.48).delay(0.1)) { yearShown = true } }
        .task(id: year) { await load() }
    }

    private var averageCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Durchschnittsnote").font(.caption).foregroundStyle(Palette.textSecondary)
                Text("Alle Fächer").font(.caption2).foregroundStyle(Palette.textTertiary)
                Text(overallAverage > 0 ? Fmt.num(overallAverage) : "–")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(overallAverage > 0 ? Palette.grade(overallAverage) : Palette.textSecondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(subjects.count) Fächer").font(.subheadline.weight(.medium)).foregroundStyle(Palette.textPrimary)
                Text("\(subjects.reduce(0) { $0 + $1.grades.count }) Noten").font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(18)
        .cardSurface(radius: 18)
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Zuletzt hinzugefügt", systemImage: "clock.arrow.circlepath")
                .font(.caption.bold()).foregroundStyle(Palette.textSecondary)
            ForEach(recent) { item in
                HStack(spacing: 12) {
                    Text(Fmt.num(item.value, digits: 1)).font(.headline.monospacedDigit())
                        .frame(width: 42, height: 42)
                        .background(Palette.grade(item.value).opacity(0.18), in: Circle())
                        .foregroundStyle(Palette.grade(item.value))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.subject).font(.subheadline.weight(.medium)).foregroundStyle(Palette.textPrimary)
                        Text(Fmt.dateFull(item.date)).font(.caption2).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .cardSurface()
    }

    private var sortBar: some View {
        HStack {
            Text("Fächer").font(.headline).foregroundStyle(Palette.textPrimary)
            Spacer()
            Menu {
                ForEach(SortMode.allCases, id: \.self) { m in
                    Button { withAnimation { sort = m } } label: {
                        if sort == m { Label(m.rawValue, systemImage: "checkmark") } else { Text(m.rawValue) }
                    }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.caption.weight(.medium))
            }
            .tint(Palette.accent)
        }
    }

    private func load() async {
        guard let s = app.session else { return }
        loading = true; error = nil
        do {
            subjects = try await UntisClient.shared.grades(year: year == SchoolDates.currentSchoolYear ? nil : year, s)
            // Aktuelles Schuljahr des STANDARD-Kontos → Noten-Widget aktualisieren.
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

struct SubjectRow: View {
    let subject: SubjectGrades
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Palette.subject(subject.subjectName)).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.subjectName).font(.headline).foregroundStyle(Palette.textPrimary)
                Text("\(subject.grades.count) Noten\(subject.teacherName.isEmpty ? "" : " · \(subject.teacherName)")")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Text(subject.average > 0 ? Fmt.num(subject.average) : "–")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(subject.average > 0 ? Palette.grade(subject.average) : Palette.textSecondary)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.textTertiary)
        }
        .padding(14)
        .cardSurface(radius: 14)
    }
}

func gradeDisplay(_ g: GradeEntry) -> String {
    let raw = !g.text.isEmpty ? g.text : (!g.markName.isEmpty ? g.markName : g.examType)
    return raw.trimmingCharacters(in: .whitespaces).isEmpty ? "Prüfung" : raw
}
