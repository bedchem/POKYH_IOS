import SwiftUI

struct ClassregEventsView: View {
    @EnvironmentObject var app: AppState
    @State private var events: [ClassregEvent] = []
    @State private var loading = true
    @State private var error: String?
    @State private var year = SchoolDates.currentSchoolYear
    @State private var yearShown = false

    var body: some View {
        Group {
            if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if events.isEmpty {
                EmptyStateView(systemImage: "book.closed", title: "Keine Einträge", subtitle: "Im Klassenbuch sind keine Einträge vorhanden.")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(events.sorted { $0.createDate > $1.createDate }) { ClassregRow(event: $0) }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Klassenbuch")
        .profileToolbar()
        .navigationBarTitleDisplayMode(.inline)
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

    private func load() async {
        guard let s = app.session else { return }
        loading = true; error = nil
        do {
            events = try await UntisClient.shared.classregEvents(year: year, s)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

struct ClassregRow: View {
    let event: ClassregEvent
    private var accent: Color {
        let l = event.categoryName.lowercased()
        if l.contains("täuschung") || l.contains("betrug") { return Palette.danger }
        if l.contains("vermerk") { return Palette.warning }
        return Palette.accent
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(Fmt.dateShort(event.createDate)).font(.caption2.bold())
            }.frame(width: 58)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if !event.subjectName.isEmpty {
                        Text(event.subjectName).font(.subheadline.bold())
                    }
                    Spacer()
                    if !event.categoryName.isEmpty {
                        Text(event.categoryName).font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(accent)
                    }
                }
                if !event.text.isEmpty || !event.eventReasonName.isEmpty {
                    Text(event.text.isEmpty ? event.eventReasonName : event.text)
                        .font(.subheadline).foregroundStyle(.primary)
                }
                if !event.creatorName.isEmpty {
                    Text(event.creatorName).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
