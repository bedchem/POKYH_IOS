import SwiftUI

// ─── Abwesenheitsberechnung (1:1 portiert aus dem Frontend: app/absences/page.tsx) ───
// Die Fehlstunden werden NICHT aus dem von WebUntis gelieferten `hours`-Feld
// gerechnet, sondern exakt über den Stundenplan: pro Abwesenheit werden die
// tatsächlichen Unterrichtsminuten in deren Zeitfenster aufsummiert. Zusätzlich
// werden alle möglichen Unterrichtsminuten seit Schuljahresbeginn summiert
// (berücksichtigt Ferien, Feiertage, persönlichen Stundenplan) → daraus die
// Fehlquote. Eine „Schulstunde" zählt dabei als 50 Minuten.

private struct DaySlot { let startMins: Int; let endMins: Int }

private let absCal = Calendar(identifier: .gregorian)

/// WebUntis-Zeitwert → Minuten seit Mitternacht. Werte können als Minuten
/// (z. B. 475 = 07:55) ODER als HHMM (z. B. 755 = 07:55) kommen. Erkennung:
/// sind die letzten zwei Stellen > 59, kann es kein gültiges HHMM sein.
private func toMinutesAbs(_ t: Int) -> Int {
    if t == 0 { return 0 }
    if t > 2359 { return t }       // zu groß für HHMM
    if t % 100 > 59 { return t }   // Minutenteil > 59 → bereits Minuten
    return (t / 100) * 60 + (t % 100)
}

private func dateFromNum(_ yyyymmdd: Int) -> Date {
    var c = DateComponents()
    c.year = yyyymmdd / 10000
    c.month = (yyyymmdd / 100) % 100
    c.day = yyyymmdd % 100
    return absCal.date(from: c) ?? Date()
}

private func numFromDate(_ d: Date) -> Int {
    let c = absCal.dateComponents([.year, .month, .day], from: d)
    return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
}

/// 0 = Sonntag … 6 = Samstag (wie JavaScripts `Date.getDay`).
private func jsWeekday(_ d: Date) -> Int { absCal.component(.weekday, from: d) - 1 }

/// Montag (yyyy-MM-dd) der Woche, die `d` enthält.
private func mondayISO(_ d: Date) -> String {
    let dow = jsWeekday(d)
    let mon = absCal.date(byAdding: .day, value: -(dow == 0 ? 6 : dow - 1), to: d) ?? d
    return DateFmt.isoString(mon)
}

/// Je ein Montag pro Kalenderwoche von Schuljahresbeginn (1. Sept) bis `now`.
private func weeksForSchoolYear(now: Date, sep: Date) -> [String] {
    let dow = jsWeekday(sep)
    var d = absCal.date(byAdding: .day, value: -(dow == 0 ? 6 : dow - 1), to: sep) ?? sep
    var out: [String] = []
    while d <= now {
        out.append(DateFmt.isoString(d))
        d = absCal.date(byAdding: .day, value: 7, to: d) ?? d
    }
    return out
}

/// Je ein Montag pro Kalenderwoche, die sich mit einer Abwesenheit überschneidet.
private func weeksForAbsences(_ absences: [AbsenceEntry]) -> [String] {
    var set = Set<String>()
    for a in absences {
        var d = dateFromNum(a.startDate)
        let end = dateFromNum(a.endDate)
        while d <= end {
            set.insert(mondayISO(d))
            d = absCal.date(byAdding: .day, value: 1, to: d) ?? d
        }
    }
    return Array(set)
}

/// Exakte Unterrichtsminuten einer Abwesenheit über den Stundenplan.
private func calcAbsenceMinutes(_ entry: AbsenceEntry, _ dateMap: [Int: [DaySlot]]) -> Int {
    var total = 0
    var d = dateFromNum(entry.startDate)
    let end = dateFromNum(entry.endDate)
    let isMultiDay = entry.startDate != entry.endDate
    let absStartMin = toMinutesAbs(entry.startTime)
    let absEndMin = toMinutesAbs(entry.endTime)

    while d <= end {
        let dow = jsWeekday(d)
        if dow != 0 && dow != 6 {
            let dateNum = numFromDate(d)
            for slot in dateMap[dateNum] ?? [] {
                // Gezählte Dauer auf das Abwesenheitsfenster beschneiden.
                var countStart = slot.startMins
                var countEnd = slot.endMins
                if isMultiDay {
                    if absStartMin > 0 && dateNum == entry.startDate { countStart = max(countStart, absStartMin) }
                    if absEndMin > 0 && dateNum == entry.endDate { countEnd = min(countEnd, absEndMin) }
                } else {
                    if absStartMin > 0 { countStart = max(countStart, absStartMin) }
                    if absEndMin > 0 { countEnd = min(countEnd, absEndMin) }
                }
                if countEnd > countStart { total += countEnd - countStart }
            }
        }
        d = absCal.date(byAdding: .day, value: 1, to: d) ?? d
    }
    return total
}

private func formatMinutes(_ m: Int) -> String {
    let h = m / 50
    let min = m % 50
    return min == 0 ? "\(h)h" : "\(h)h \(min)m"
}

private func roundHours(_ m: Int) -> String { "\(Int((Double(m) / 50).rounded()))h" }

private let monthNamesDE = ["Jän", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

private struct MonthGroup: Identifiable {
    let id: String
    let label: String
    let entries: [AbsenceEntry]
    let totalMinutes: Int
}

private func groupByMonth(_ entries: [AbsenceEntry], _ minutesMap: [Int: Int]) -> [MonthGroup] {
    var map: [String: [AbsenceEntry]] = [:]
    for e in entries {
        let s = String(e.startDate)
        guard s.count == 8 else { continue }
        let key = "\(s.prefix(4))-\(s.dropFirst(4).prefix(2))"
        map[key, default: []].append(e)
    }
    return map.map { key, es in
        let parts = key.split(separator: "-")
        let year = String(parts[0])
        let month = Int(parts[1]) ?? 1
        let total = es.reduce(0) { $0 + (minutesMap[$1.id] ?? $1.hours * 50) }
        return MonthGroup(id: key, label: "\(monthNamesDE[month - 1]) \(year)", entries: es, totalMinutes: total)
    }
    .sorted { $0.id > $1.id }
}

// ─── View ─────────────────────────────────────────────────────────────────────

struct AbsencesView: View {
    @EnvironmentObject var app: AppState
    @State private var absences: [AbsenceEntry] = []
    @State private var minutesMap: [Int: Int] = [:]
    @State private var totalPossibleMins = 1
    @State private var loading = true
    @State private var error: String?
    @State private var year = SchoolDates.currentSchoolYear
    @State private var yearShown = false
    @State private var exact = false

    private func getMin(_ e: AbsenceEntry) -> Int { minutesMap[e.id] ?? e.hours * 50 }
    private func fmt(_ m: Int) -> String { exact ? formatMinutes(m) : roundHours(m) }

    private var totalMinutes: Int { absences.reduce(0) { $0 + getMin($1) } }
    private var excusedMinutes: Int { absences.filter { $0.isExcused }.reduce(0) { $0 + getMin($1) } }
    private var unexcusedMinutes: Int { totalMinutes - excusedMinutes }
    private var rate: Double { totalPossibleMins > 0 ? min(Double(totalMinutes) / Double(totalPossibleMins) * 100, 100) : 0 }
    private var rateColor: Color { rate < 5 ? Palette.tint : rate < 15 ? Palette.warning : Palette.danger }

    var body: some View {
        Group {
            if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if absences.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        overviewCard
                        EmptyStateView(systemImage: "checkmark.seal", title: "Keine Fehlstunden", subtitle: "Du hast keine Abwesenheiten in diesem Schuljahr.")
                            .padding(.top, 24)
                    }
                    .padding(16)
                }
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        overviewCard
                        ForEach(groupByMonth(absences, minutesMap)) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(group.label).font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text(fmt(group.totalMinutes)).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 2)
                                ForEach(group.entries.sorted { $0.startDate > $1.startDate }) { a in
                                    AbsenceRow(absence: a, minutes: getMin(a), label: fmt(getMin(a)))
                                }
                            }
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
                Button { withAnimation(.easeInOut(duration: 0.2)) { exact.toggle() } } label: {
                    Label(exact ? "Exakt" : "Gerundet", systemImage: exact ? "clock.badge.checkmark" : "clock")
                        .font(.caption.weight(.medium))
                }
            }
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

    private var overviewCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fehlstunden gesamt").font(.caption).foregroundStyle(.secondary)
                    Text(fmt(totalMinutes)).font(.system(size: 30, weight: .bold, design: .rounded))
                }
                Spacer()
                HStack(spacing: 18) {
                    miniStat(fmt(excusedMinutes), "Entschuldigt", Palette.tint)
                    miniStat(fmt(unexcusedMinutes), "Unentschuldigt", Palette.danger)
                }
            }
            VStack(spacing: 6) {
                HStack {
                    Text("Fehlquote").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", rate)).font(.caption.weight(.semibold)).foregroundStyle(rateColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.card)
                        Capsule().fill(rateColor).frame(width: geo.size.width * CGFloat(rate / 100))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func miniStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let s = app.session else { return }
        loading = true; error = nil
        do {
            let parsed = try await UntisClient.shared.absences(
                startDate: SchoolDates.yearStart(year), endDate: SchoolDates.yearEnd(year), s)
            absences = parsed

            // Schuljahres-Zeitraum für das gewählte Jahr.
            let sep = dateFromNum(year * 10000 + 901)                 // 1. Sept
            let now: Date = year == SchoolDates.currentSchoolYear
                ? Date()
                : dateFromNum((year + 1) * 10000 + 630)              // 30. Juni Folgejahr

            // Stundenplan für Abwesenheits-Wochen + alle Schuljahres-Wochen laden
            // (für einen korrekten Nenner der Fehlquote).
            let weeks = Array(Set(weeksForAbsences(parsed) + weeksForSchoolYear(now: now, sep: sep)))
            let dateMap = try await buildDateMap(weeks: weeks, s)

            // Exakte Minuten je Abwesenheit.
            var mins: [Int: Int] = [:]
            for e in parsed { mins[e.id] = calcAbsenceMinutes(e, dateMap) }
            minutesMap = mins

            // Alle möglichen Unterrichtsminuten seit Schuljahresbeginn.
            let sepNum = numFromDate(sep), nowNum = numFromDate(now)
            var possible = 0
            for (dateNum, slots) in dateMap where dateNum >= sepNum && dateNum <= nowNum {
                for slot in slots { possible += slot.endMins - slot.startMins }
            }
            totalPossibleMins = max(1, possible)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    /// Lädt die Wochen-Stundenpläne nebenläufig und baut eine Karte
    /// dateNum → Unterrichts-Slots (dedupliziert nach Startzeit, abgesagte und
    /// fachlose Einträge übersprungen — wie `mergeTimetableIntoMap` im Frontend).
    private func buildDateMap(weeks: [String], _ s: UserSession) async throws -> [Int: [DaySlot]] {
        var raw: [Int: [Int: DaySlot]] = [:]
        try await withThrowingTaskGroup(of: [TimetableEntry].self) { group in
            for w in weeks {
                group.addTask {
                    do { return try await UntisClient.shared.timetable(date: w, s) }
                    catch let e as AppError where e.message == "session_expired" { throw e }
                    catch { return [] }
                }
            }
            for try await entries in group {
                for e in entries {
                    if e.isCancelled { continue }
                    if e.subjectName.isEmpty && e.subjectLong.isEmpty { continue }
                    let startMins = Fmt.minutes(e.startTime)
                    let endMins = Fmt.minutes(e.endTime)
                    // Parallele Fächer (gleicher Beginn) zählen als eine Stunde.
                    if raw[e.date]?[startMins] == nil {
                        raw[e.date, default: [:]][startMins] = DaySlot(startMins: startMins, endMins: endMins)
                    }
                }
            }
        }
        return raw.mapValues { Array($0.values) }
    }
}

struct AbsenceRow: View {
    let absence: AbsenceEntry
    let minutes: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateText).font(.subheadline.weight(.medium))
                    if !subText.isEmpty {
                        Text(subText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Label(absence.isExcused ? "entschuldigt" : "offen",
                          systemImage: absence.isExcused ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(absence.isExcused ? Palette.tint : Palette.danger)
                }
            }
            if let reason = absence.reasonName, !reason.isEmpty {
                infoLine("Grund", reason)
            }
            if let note = absence.note, !note.isEmpty {
                infoLine("Text", note)
            }
        }
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dateText: String {
        absence.startDate != absence.endDate
            ? "\(Fmt.dateShort(absence.startDate)) – \(Fmt.dateShort(absence.endDate))"
            : Fmt.dateShort(absence.startDate)
    }

    private var subText: String {
        var parts: [String] = []
        if absence.startTime != 0 || absence.endTime != 0 {
            parts.append("\(Fmt.time(absence.startTime)) – \(Fmt.time(absence.endTime))")
        }
        if let sub = absence.subjectName, !sub.isEmpty { parts.append(sub) }
        if let t = absence.teacherName, !t.isEmpty { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            Text(value).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardAlt, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
