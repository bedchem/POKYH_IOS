import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState

    @State private var todayEntries: [TimetableEntry] = []
    @State private var loadingToday = true
    @State private var recentGrades: [RecentGrade] = []
    @State private var loadingGrades = true
    @State private var todayDishes: [Dish] = []
    @State private var dishDayLabel = ""
    @State private var loadingMensa = true
    @State private var nextExam: TimetableEntry?
    @State private var examsLoaded = false

    struct RecentGrade: Identifiable { let id: Int; let subject: String; let value: Double; let date: Int }

    private var firstName: String {
        if let n = app.session?.personName, let first = n.split(separator: " ").first {
            return String(first)
        }
        return app.session?.username ?? ""
    }

    private var todaySlots: [MergedSlot] {
        Timetable.buildSlots(todayEntries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header.fadeIn()
                shortcuts.fadeIn(delay: 0.04)
                if let exam = nextExam {
                    examCard(exam).fadeIn(delay: 0.06)
                } else if examsLoaded {
                    noExamCard.fadeIn(delay: 0.06)
                }
                todaySection.fadeIn(delay: 0.08)
                mensaSection.fadeIn(delay: 0.12)
                if loadingGrades || !recentGrades.isEmpty { gradesSection.fadeIn(delay: 0.16) }
            }
            .padding(16)
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .profileToolbar()
        .task { await loadAll() }
        .refreshable { await loadAll(force: true) }
    }

    // ── Header ──────────────────────────────────────────────────────────────
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greeting),").font(.largeTitle.bold()).foregroundStyle(Palette.textPrimary)
            Text(firstName.isEmpty ? "Willkommen" : firstName)
                .font(.largeTitle.bold()).foregroundStyle(Palette.accent)
            if let s = app.session {
                Text("\(s.klasseName.isEmpty ? "LBS Brixen" : s.klasseName) · LBS Brixen")
                    .font(.subheadline).foregroundStyle(Palette.textSecondary)
            }
        }
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "Guten Morgen"
        case 11..<17: return "Hallo"
        case 17..<22: return "Guten Abend"
        default: return "Hallo"
        }
    }

    // ── Shortcuts ───────────────────────────────────────────────────────────
    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink { GradesView() } label: { card("Noten", "chart.bar.fill", Palette.accent) }.buttonStyle(.pressable)
            NavigationLink { AbsencesView() } label: { card("Abwesenheiten", "person.fill.xmark", Palette.orange) }.buttonStyle(.pressable)
            NavigationLink { TodosView() } label: { card("Todos", "checklist", Palette.accentSoft) }.buttonStyle(.pressable)
            NavigationLink { RemindersView() } label: { card("Erinnerungen", "bell.fill", Palette.tint) }.buttonStyle(.pressable)
        }
    }
    private func card(_ title: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14).cardSurface(radius: 16)
    }

    // ── Heute (Unterricht) ──────────────────────────────────────────────────
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Heute", "calendar")
            if loadingToday {
                skeletonRows(2)
            } else if todaySlots.isEmpty {
                infoCard("checkmark.circle.fill", Palette.tint, "Heute kein Unterricht")
            } else {
                ForEach(Array(todaySlots.enumerated()), id: \.element.id) { idx, slot in
                    SlotRow(slot: slot).fadeIn(delay: Double(idx) * 0.03)
                }
            }
        }
    }

    // ── Zuletzt eingetragene Noten ──────────────────────────────────────────
    private var gradesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Zuletzt eingetragen", "chart.bar.fill")
            if loadingGrades {
                skeletonRows(2)
            } else {
                VStack(spacing: 8) {
                    ForEach(recentGrades) { g in
                        HStack(spacing: 12) {
                            Text(Fmt.num(g.value, digits: g.value == g.value.rounded() ? 0 : 1))
                                .font(.headline.monospacedDigit())
                                .frame(width: 42, height: 42)
                                .background(Palette.grade(g.value).opacity(0.18), in: Circle())
                                .foregroundStyle(Palette.grade(g.value))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(g.subject).font(.subheadline.weight(.medium)).foregroundStyle(Palette.textPrimary)
                                Text(Fmt.dateFull(g.date)).font(.caption2).foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(12).cardSurface(radius: 12)
                    }
                }
            }
        }
    }

    // ── Mensa heute ─────────────────────────────────────────────────────────
    @ViewBuilder private var mensaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(dishDayLabel.isEmpty ? "Mensa heute" : "Mensa · \(dishDayLabel)", "fork.knife")
            if loadingMensa && todayDishes.isEmpty {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10).fill(Palette.cardAlt).frame(width: 56, height: 56).modifier(Shimmer())
                        VStack(alignment: .leading, spacing: 6) { SkeletonBlock(height: 11, width: 80); SkeletonBlock(height: 13, width: 160) }
                        Spacer()
                    }.padding(10).cardSurface(radius: 12)
                }
            } else if todayDishes.isEmpty {
                infoCard("fork.knife", Palette.accent, "Kein Speiseplan verfügbar")
            } else {
                NavigationLink { MensaView() } label: {
                    VStack(spacing: 8) {
                        ForEach(todayDishes.prefix(3)) { dish in
                            HStack(spacing: 12) {
                                DishImage(dish: dish, height: 56)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    if !dish.category.isEmpty {
                                        Text(dish.category.uppercased()).font(.caption2.bold()).foregroundStyle(Palette.accent)
                                    }
                                    Text(dish.name).font(.subheadline.weight(.medium)).foregroundStyle(Palette.textPrimary).lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(10).cardSurface(radius: 12)
                        }
                    }
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // ── Bausteine ───────────────────────────────────────────────────────────
    private func sectionHeader(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.title3.bold()).foregroundStyle(Palette.textPrimary)
    }
    private func infoCard(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).foregroundStyle(Palette.textSecondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).cardSurface(radius: 12)
    }
    private func skeletonRows(_ n: Int) -> some View {
        VStack(spacing: 8) {
            ForEach(0..<n, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.cardAlt).frame(width: 5, height: 42).modifier(Shimmer())
                    VStack(alignment: .leading, spacing: 6) { SkeletonBlock(height: 13, width: 140); SkeletonBlock(height: 10, width: 90) }
                    Spacer()
                }
                .padding(12).cardSurface(radius: 12)
            }
        }
    }

    // ── Nächste Schularbeit ─────────────────────────────────────────────────
    private func examCard(_ e: TimetableEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.and.list.clipboard").font(.title3).foregroundStyle(Palette.warning)
                .frame(width: 40, height: 40)
                .background(Palette.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Nächste Schularbeit").font(.caption).foregroundStyle(Palette.textSecondary)
                Text(e.subjectLong.isEmpty ? (e.subjectName.isEmpty ? "Prüfung" : e.subjectName) : e.subjectLong)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Label("\(examWhen(e.date)) · \(Fmt.time(e.startTime))", systemImage: "calendar")
                    .font(.caption2).foregroundStyle(Palette.warning)
            }
            Spacer()
        }
        .padding(14).cardSurface(radius: 16)
    }
    private var noExamCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.title3).foregroundStyle(Palette.tint)
                .frame(width: 40, height: 40)
                .background(Palette.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Nächste Schularbeit").font(.caption).foregroundStyle(Palette.textSecondary)
                Text("Keine Tests in Zukunft").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            }
            Spacer()
        }
        .padding(14).cardSurface(radius: 16)
    }
    private func examWhen(_ dateNum: Int) -> String {
        let s = String(dateNum)
        guard s.count == 8,
              let date = Calendar.current.date(from: DateComponents(
                year: Int(s.prefix(4)), month: Int(s.dropFirst(4).prefix(2)), day: Int(s.suffix(2)))) else {
            return Fmt.dateFull(dateNum)
        }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        return "in \(days) Tagen · \(Fmt.dateShort(dateNum))"
    }

    // ── Laden (unabhängig, parallel) ────────────────────────────────────────
    private func loadAll(force: Bool = false) async {
        // Mensa kommt aus dem Backend → immer; Stundenplan/Noten/Prüfungen nur mit
        // verknüpftem WebUntis-Konto.
        async let c: () = loadMensa()
        if app.session?.hasUntis ?? false {
            async let a: () = loadToday()
            async let b: () = loadGrades()
            async let d: () = loadExams()
            _ = await (a, b, d)
        }
        _ = await c
    }

    private func loadExams() async {
        guard let s = app.session else { return }
        if let exams = try? await UntisClient.shared.upcomingExams(s) {
            nextExam = exams.first
        }
        examsLoaded = true
    }

    private func loadToday() async {
        guard let s = app.session else { return }
        loadingToday = true
        do {
            let monday = SchoolDates.mondayISO(of: Date())
            let all = try await UntisClient.shared.timetable(date: monday, s)
            let today = SchoolDates.todayNum()
            todayEntries = all.filter { $0.date == today }
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch { }
        loadingToday = false
    }

    private func loadGrades() async {
        guard let s = app.session else { return }
        loadingGrades = true
        if let subjects = try? await UntisClient.shared.grades(year: nil, s) {
            var items: [RecentGrade] = []
            for subj in subjects {
                for g in subj.grades where g.markDisplayValue > 0 {
                    items.append(RecentGrade(id: g.id, subject: subj.subjectName, value: g.markDisplayValue, date: g.date))
                }
            }
            items.sort { $0.id > $1.id }
            recentGrades = Array(items.prefix(3))
        }
        loadingGrades = false
    }

    private func loadMensa() async {
        loadingMensa = true
        defer { loadingMensa = false }
        guard let dishes = try? await BackendClient.shared.dishes() else { return }
        // Gleiche Datums-Logik wie der Mensa-Tab: aktueller Tag aus der API.
        if let day = MensaSchedule.days(from: dishes).first {
            todayDishes = day.dishes
            dishDayLabel = labelFor(day.date)
        } else {
            todayDishes = []
            dishDayLabel = ""
        }
    }
    private func labelFor(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE")
        // Vergangene/spätere Tage mit klarem Datum.
        f.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) ? "EEEE" : "EEEE, d. MMM"
        return f.string(from: date)
    }
}
