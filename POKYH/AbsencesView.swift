import SwiftUI

struct AbsencesView: View {
    @EnvironmentObject var app: AppState
    @State private var absences: [AbsenceEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var year = SchoolDates.currentSchoolYear
    @State private var yearShown = false

    private var totalHours: Int { absences.reduce(0) { $0 + $1.hours } }
    private var excusedHours: Int { absences.filter { $0.isExcused }.reduce(0) { $0 + $1.hours } }
    private var openHours: Int { totalHours - excusedHours }

    var body: some View {
        Group {
            if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if absences.isEmpty {
                EmptyStateView(systemImage: "checkmark.seal", title: "Keine Fehlstunden", subtitle: "Du hast keine Abwesenheiten in diesem Schuljahr.")
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        statsCard
                        ForEach(absences.sorted { $0.startDate > $1.startDate }) { a in
                            AbsenceRow(absence: a)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Abwesenheiten")
        .profileToolbar()
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SchoolDates.availableYears, id: \.self) { y in
                        Button("\(String(y))/\(String((y + 1) % 100))") { year = y; Task { await load() } }
                    }
                } label: { Text("\(String(year))/\(String((year + 1) % 100))") }
                .slideIn(yearShown)
            }
        }
        .task { withAnimation(.spring(response: 0.6, dampingFraction: 0.48).delay(0.1)) { yearShown = true } }
        .task(id: year) { await load() }
    }

    private var statsCard: some View {
        HStack(spacing: 12) {
            stat("Gesamt", totalHours, .primary)
            stat("Entschuldigt", excusedHours, Palette.tint)
            stat("Offen", openHours, Palette.danger)
        }
    }
    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func load() async {
        guard let s = app.session else { return }
        loading = true; error = nil
        do {
            absences = try await UntisClient.shared.absences(
                startDate: SchoolDates.yearStart(year), endDate: SchoolDates.yearEnd(year), s)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

struct AbsenceRow: View {
    let absence: AbsenceEntry
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(Fmt.dateShort(absence.startDate).prefix(5)).font(.caption.bold())
            }
            .frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(timeRange).font(.subheadline.weight(.medium))
                    Label(absence.isExcused ? "entschuldigt" : "offen",
                          systemImage: absence.isExcused ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(absence.isExcused ? Palette.tint : Palette.danger)
                }
                if let reason = absence.reasonName, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                if let note = absence.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("\(absence.hours) Std").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var timeRange: String {
        if absence.startTime == 0 && absence.endTime == 0 { return Fmt.dateShort(absence.startDate) }
        return "\(Fmt.time(absence.startTime)) – \(Fmt.time(absence.endTime))"
    }
}
