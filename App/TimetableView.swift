import SwiftUI

// ── Slot-/Tag-Logik (1:1 aus app/timetable/page.tsx portiert) ───────────────

enum SlotKind { case normal, cancelled, replacement, exam, event }
enum DayKind { case normal, holiday, allCancelled, allReplacement, fullDayEvent, weekend }

struct MergedSlot: Identifiable {
    let id = UUID()
    var display: TimetableEntry
    var replacement: TimetableEntry?
    var kind: SlotKind
}

enum Timetable {
    static func mins(_ t: Int) -> Int { Fmt.minutes(t) }

    /// Entries eines Tages zu Slots gruppieren (Vertretung/Entfall zusammenführen).
    static func buildSlots(_ dayEntries: [TimetableEntry]) -> [MergedSlot] {
        var groups: [Int: [TimetableEntry]] = [:]
        for e in dayEntries { groups[e.startTime, default: []].append(e) }

        var slots: [MergedSlot] = []
        for groupStart in groups.keys.sorted() {
            let group = groups[groupStart]!
            let cancelled = group.filter { $0.isCancelled }
            var active = group.filter { !$0.isCancelled }

            let spanningCancelled: [TimetableEntry] = cancelled.isEmpty
                ? dayEntries.filter { $0.isCancelled && mins($0.startTime) < mins(groupStart) && mins($0.endTime) > mins(groupStart) }
                : []
            let effectiveCancelled = cancelled.isEmpty ? spanningCancelled : cancelled

            if active.isEmpty && !effectiveCancelled.isEmpty {
                let spanning = dayEntries.filter { !$0.isCancelled && mins($0.startTime) < mins(groupStart) && mins($0.endTime) > mins(groupStart) }
                if !spanning.isEmpty { active = spanning }
            }

            if active.isEmpty {
                if let first = effectiveCancelled.first {
                    slots.append(MergedSlot(display: first, replacement: nil, kind: .cancelled))
                }
                continue
            }
            if !effectiveCancelled.isEmpty {
                slots.append(MergedSlot(display: effectiveCancelled[0], replacement: active[0], kind: .replacement))
                continue
            }

            let display = active.first(where: { $0.isExam })
                ?? active.first(where: { $0.isAdditional })
                ?? active.first(where: { $0.subjectName.isEmpty && ($0.note?.isEmpty == false) })
                ?? active.first(where: { $0.isSubstitution })
                ?? active[0]

            let kind: SlotKind
            if display.isExam { kind = .exam }
            else if display.isAdditional { kind = .normal }
            else if display.subjectName.isEmpty && (display.note?.isEmpty == false) { kind = .event }
            else if display.isSubstitution { kind = .replacement }
            else { kind = .normal }
            slots.append(MergedSlot(display: display, replacement: nil, kind: kind))
        }

        // Entfall-Slots entfernen, die optisch in einem aktiven Slot liegen
        let activeSlots = slots.filter { !$0.display.isCancelled }
        return slots.filter { slot in
            if !slot.display.isCancelled { return true }
            let sm = mins(slot.display.startTime), em = mins(slot.display.endTime)
            return !activeSlots.contains { a in
                mins(a.display.startTime) <= sm && mins(a.display.endTime) >= em
            }
        }
    }

    static func dayKind(_ dayEntries: [TimetableEntry], hasOtherDayEntries: Bool, index: Int) -> DayKind {
        dayKind(dayEntries, slots: buildSlots(dayEntries), hasOtherDayEntries: hasOtherDayEntries, index: index)
    }

    /// Variante mit bereits berechneten Slots (Performance: kein doppeltes `buildSlots`).
    static func dayKind(_ dayEntries: [TimetableEntry], slots: [MergedSlot], hasOtherDayEntries: Bool, index: Int) -> DayKind {
        if index == 5 && dayEntries.isEmpty { return .weekend }
        let base = baseDayKind(dayEntries, hasOtherDayEntries: hasOtherDayEntries)
        if base == .normal, !slots.isEmpty, slots.allSatisfy({ $0.kind == .replacement }) {
            let first = slots[0].replacement
            let same = slots.allSatisfy {
                $0.replacement?.subjectName == first?.subjectName &&
                $0.replacement?.note == first?.note &&
                $0.replacement?.teacherName == first?.teacherName
            }
            if same { return .allReplacement }
        }
        return base
    }

    private static func baseDayKind(_ dayEntries: [TimetableEntry], hasOtherDayEntries: Bool) -> DayKind {
        if dayEntries.isEmpty { return hasOtherDayEntries ? .holiday : .normal }
        if dayEntries.count == 1, !dayEntries[0].isCancelled, dayEntries[0].subjectName.isEmpty, (dayEntries[0].note?.isEmpty == false) {
            return .fullDayEvent
        }
        if dayEntries.allSatisfy({ $0.isCancelled }) { return .allCancelled }
        return .normal
    }

    static func color(_ slot: MergedSlot) -> Color {
        let d = slot.display
        if d.isCancelled { return Palette.danger }
        if d.isExam { return Palette.warning }
        if slot.kind == .replacement { return Palette.orange }
        if slot.kind == .event { return Palette.accent }
        return Palette.subject(d.subjectName)
    }
}

// ── Hauptansicht ────────────────────────────────────────────────────────────

struct TimetableView: View {
    @EnvironmentObject var app: AppState
    @State private var weekOffset = 0
    @State private var entries: [TimetableEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var mode: Mode = .week
    @State private var selectedDay = 0
    @State private var detail: MergedSlot?
    @State private var shareItem: ShareItem?
    @State private var exporting = false

    enum Mode: String, CaseIterable { case week = "Woche", day = "Tag" }

    private let dayLabels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    private let dayLong = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]

    private var thisMonday: Date {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }
    private var monday: Date { Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: thisMonday) ?? thisMonday }
    private func dayDate(_ i: Int) -> Date { Calendar.current.date(byAdding: .day, value: i, to: monday) ?? monday }
    private func dayNum(_ i: Int) -> Int { DateFmt.num(dayDate(i)) }
    private func entriesFor(_ i: Int) -> [TimetableEntry] {
        entries.filter { $0.date == dayNum(i) }
    }
    private var anyDayHasEntries: Bool { (0..<6).contains { !entriesFor($0).isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
            Picker("Ansicht", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.bottom, 8)
            Divider().overlay(Palette.separator)
            content
        }
        .navigationTitle("Stundenplan")
        .profileToolbar()
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .task(id: weekOffset) { await load(); prefetchAdjacent() }
        .onAppear { selectInitialDay() }
        .onChange(of: app.timetableHomeSignal) {
            withAnimation(.snappy(duration: 0.3)) { weekOffset = 0; selectInitialDay() }
        }
        .sheet(item: $detail) { LessonDetailView(slot: $0) }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { exportWeek() } label: {
                        Label("Diese Woche exportieren", systemImage: "calendar")
                    }
                    Button { Task { await exportExams() } } label: {
                        Label("Prüfungen exportieren", systemImage: "graduationcap")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(exporting)
            }
        }
    }

    // ── .ics-Export ─────────────────────────────────────────────────────────
    private func share(_ entries: [TimetableEntry], name: String) {
        guard !entries.isEmpty else { return }
        let ics = ICSExport.makeCalendar(entries, calendarName: name)
        if let url = ICSExport.writeTempFile(ics, name: name) { shareItem = ShareItem(url: url) }
    }
    private func exportWeek() {
        share((0..<6).flatMap { entriesFor($0) }, name: "POKYH Stundenplan")
    }
    private func exportExams() async {
        guard let s = app.session else { return }
        exporting = true; defer { exporting = false }
        let exams = (try? await UntisClient.shared.upcomingExams(s)) ?? []
        share(exams, name: "POKYH Prüfungen")
    }

    /// Tagesansicht: horizontaler Swipe → Tag wechseln (clean, federnd).
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4,
                      abs(value.translation.width) > 48 else { return }
                let forward = value.translation.width < 0
                withAnimation(.snappy(duration: 0.3, extraBounce: 0.06)) {
                    if forward {
                        if selectedDay < 5 { selectedDay += 1 } else { weekOffset += 1; selectedDay = 0 }
                    } else {
                        if selectedDay > 0 { selectedDay -= 1 } else { weekOffset -= 1; selectedDay = 5 }
                    }
                }
            }
    }

    /// Wie viele Wochen je Richtung um die aktuelle vorgeladen werden.
    /// Radius 2 ⇒ stets ein 5-Wochen-Fenster (−2…+2) vollständig im Cache.
    private static let preloadRadius = 2

    /// Precaching: das gesamte 5-Wochen-Fenster im Hintergrund laden → „unendliches",
    /// flüssiges Blättern ohne Nachladen beim Swipen (alle Daten liegen im Cache).
    private func prefetchAdjacent() {
        guard let s = app.session else { return }
        for off in (-Self.preloadRadius...Self.preloadRadius) where off != 0 {
            guard let m = Calendar.current.date(byAdding: .day, value: (weekOffset + off) * 7, to: thisMonday) else { continue }
            let iso = DateFmt.isoString(m)
            Task { _ = try? await UntisClient.shared.timetable(date: iso, s) }  // füllt den Cache
        }
    }

    private var weekHeader: some View {
        HStack {
            Button { withAnimation(.snappy(duration: 0.34, extraBounce: 0.08)) { weekOffset -= 1 } } label: {
                Image(systemName: "chevron.left").font(.headline)
            }.buttonStyle(.pressable)
            Spacer()
            VStack(spacing: 2) {
                Text(rangeText).font(.subheadline.bold()).foregroundStyle(Palette.textPrimary)
                if weekOffset != 0 {
                    Button("Heute") { withAnimation(.snappy(duration: 0.34, extraBounce: 0.08)) { weekOffset = 0; selectInitialDay() } }
                        .font(.caption2).tint(Palette.accent)
                } else {
                    Text("KW \(weekNumber) · Diese Woche").font(.caption2).foregroundStyle(Palette.accent)
                }
            }
            Spacer()
            Button { withAnimation(.snappy(duration: 0.34, extraBounce: 0.08)) { weekOffset += 1 } } label: {
                Image(systemName: "chevron.right").font(.headline)
            }.buttonStyle(.pressable)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .tint(Palette.accent)
    }

    private var weekNumber: Int { Calendar(identifier: .iso8601).component(.weekOfYear, from: monday) }
    private var rangeText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "d. MMM"
        let f2 = DateFormatter(); f2.locale = Locale(identifier: "de_DE"); f2.dateFormat = "d. MMM yyyy"
        return "\(f.string(from: monday)) – \(f2.string(from: dayDate(5)))"
    }

    // Großzügiger Wochenbereich → fühlt sich „unendlich" an (Seiten sind leicht,
    // Daten laden nur sichtbare Seiten, mit Cache + Precaching).
    private let pageSpan = 40
    private var weekRange: ClosedRange<Int> { -pageSpan...pageSpan }

    @ViewBuilder
    private var content: some View {
        if mode == .week {
            // Performantes, flüssiges Paging: horizontaler ScrollView + LazyHStack
            // (nur sichtbare Seiten werden gerendert) mit nativem Paging-Snapping.
            // Breite EINMAL messen und an alle Seiten durchreichen.
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(weekRange, id: \.self) { off in
                            WeekTimetablePage(weekOffset: off, width: geo.size.width,
                                              initialEntries: cachedEntries(for: off), onTap: { detail = $0 })
                                .containerRelativeFrame(.horizontal)
                                .id(off)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: scrollWeekBinding, anchor: .center)
            }
        } else {
            dayView
        }
    }

    /// Bindet die Scroll-Seite an `weekOffset` (zwei Wege: Wischen ↔ Buttons).
    private var scrollWeekBinding: Binding<Int?> {
        Binding(get: { weekOffset }, set: { if let v = $0, v != weekOffset { weekOffset = v } })
    }

    /// Bereits vorgeladene Woche aus dem Cache (synchron) → Seite ohne Spinner.
    private func cachedEntries(for off: Int) -> [TimetableEntry]? {
        guard let s = app.session,
              let m = Calendar.current.date(byAdding: .day, value: off * 7, to: thisMonday) else { return nil }
        return UntisClient.shared.cachedTimetable(date: DateFmt.isoString(m), s)
    }

    private var dayView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    let isToday = dayNum(i) == SchoolDates.todayNum()
                    Button { withAnimation(.spring(response: 0.3)) { selectedDay = i } } label: {
                        VStack(spacing: 2) {
                            Text(dayLabels[i]).font(.caption2.weight(.semibold))
                            Text("\(Calendar.current.component(.day, from: dayDate(i)))").font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(selectedDay == i ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(selectedDay == i ? .white : (isToday ? Palette.accent : Palette.textPrimary))
                    }.buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            let de = entriesFor(selectedDay)
            let kind = Timetable.dayKind(de, hasOtherDayEntries: anyDayHasEntries, index: selectedDay)
            ScrollView {
                if kind != .normal {
                    SpecialDayCard(kind: kind, fullWidth: true)
                        .frame(maxWidth: .infinity).frame(height: 380).padding(16)
                } else {
                    let slots = Timetable.buildSlots(de)
                    LazyVStack(spacing: 10) {
                        ForEach(Array(slots.enumerated()), id: \.element.id) { idx, slot in
                            Button { detail = slot } label: { SlotRow(slot: slot) }
                                .buttonStyle(.pressable)
                                .fadeIn(delay: Double(idx) * 0.03)
                        }
                    }
                    .padding(16)
                }
            }
            .id(selectedDay)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .simultaneousGesture(daySwipe)
        }
    }

    private func selectInitialDay() {
        let today = SchoolDates.todayNum()
        selectedDay = (0..<6).first(where: { dayNum($0) == today }) ?? 0
    }

    private func load() async {
        guard let s = app.session else { return }
        loading = true; error = nil
        do {
            entries = try await UntisClient.shared.timetable(date: DateFmt.isoString(monday), s)
            // Aktuelle Woche des STANDARD-Kontos → Widget/Live-Activity aktualisieren.
            if weekOffset == 0, app.isDefaultAccountActive {
                WidgetBridge.publish(entries); app.refreshLiveActivity(from: entries)
            }
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
        prefetchAdjacent()   // Nachbarwochen vorladen → flüssiges Blättern
    }
}

// ── Eine Wochen-Seite (für das paginierte TabView) ──────────────────────────

struct WeekTimetablePage: View {
    let weekOffset: Int
    let width: CGFloat
    let onTap: (MergedSlot) -> Void
    @EnvironmentObject var app: AppState
    @State private var entries: [TimetableEntry]
    @State private var loading: Bool
    @State private var error: String?

    /// `initialEntries` aus dem Vorlade-Cache → die Seite rendert sofort (kein
    /// Spinner-Flash beim Swipen); `.task` revalidiert danach still im Hintergrund.
    init(weekOffset: Int, width: CGFloat, initialEntries: [TimetableEntry]?, onTap: @escaping (MergedSlot) -> Void) {
        self.weekOffset = weekOffset
        self.width = width
        self.onTap = onTap
        _entries = State(initialValue: initialEntries ?? [])
        _loading = State(initialValue: initialEntries == nil)
    }

    private let dayLabels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    private var thisMonday: Date {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }
    private var monday: Date { Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: thisMonday) ?? thisMonday }
    private func dayDate(_ i: Int) -> Date { Calendar.current.date(byAdding: .day, value: i, to: monday) ?? monday }
    private func dayNum(_ i: Int) -> Int { DateFmt.num(dayDate(i)) }
    private func entriesFor(_ i: Int) -> [TimetableEntry] { entries.filter { $0.date == dayNum(i) } }
    private var anyDayHasEntries: Bool { (0..<6).contains { !entriesFor($0).isEmpty } }

    var body: some View {
        Group {
            if loading {
                // Leichter Spinner statt dauer-animiertem Shimmer (kein Redraw-Stau beim Swipen).
                ProgressView().controlSize(.large).tint(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if entries.isEmpty {
                ScrollView {
                    SpecialDayCard(kind: .holiday, fullWidth: true)
                        .frame(maxWidth: .infinity).frame(height: 420).padding(16)
                }
            } else {
                WeekGrid(dayEntries: (0..<6).map { entriesFor($0) },
                         dayLabels: dayLabels,
                         dates: (0..<6).map { dayDate($0) },
                         todayNum: SchoolDates.todayNum(),
                         dayNums: (0..<6).map { dayNum($0) },
                         anyDayHasEntries: anyDayHasEntries, onTap: onTap, width: width)
                    .equatable()
            }
        }
        .task { await load() }   // lädt beim Erscheinen; TabView rendert Nachbarseiten vor
    }

    private func load() async {
        guard let s = app.session else { return }
        loading = entries.isEmpty
        error = nil
        do {
            entries = try await UntisClient.shared.timetable(date: DateFmt.isoString(monday), s)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

// ── Wochenraster ────────────────────────────────────────────────────────────

struct WeekGrid: View, Equatable {
    let dayEntries: [[TimetableEntry]]
    let dayLabels: [String]
    let dates: [Date]
    let todayNum: Int
    let dayNums: [Int]
    let anyDayHasEntries: Bool
    let onTap: (MergedSlot) -> Void
    /// Breite wird EINMAL von außen gemessen (kein GeometryReader pro Seite → performant).
    let width: CGFloat

    private let gutter: CGFloat = 42
    private let pxPerMin: CGFloat = 0.82

    // Einmalig im init vorberechnet → beim Scrollen wird NICHTS neu gerechnet.
    private let daySlots: [[MergedSlot]]
    private let dayKinds: [DayKind]
    private let minMins: Int
    private let maxMins: Int
    private let totalHeight: CGFloat
    private let boundaryTimes: [Int]
    private let visiblePeriods: [(num: Int, s: Int, e: Int)]

    /// Festes Periodenraster (wie im Frontend): Stundennummer + Start/Ende.
    private static let periods: [(num: Int, s: Int, e: Int)] = [
        (1, 470, 520), (2, 520, 570), (3, 570, 620), (4, 635, 685), (5, 685, 735),
        (6, 735, 785), (7, 795, 845), (8, 845, 895), (9, 905, 955), (10, 955, 1005),
    ]

    init(dayEntries: [[TimetableEntry]], dayLabels: [String], dates: [Date], todayNum: Int,
         dayNums: [Int], anyDayHasEntries: Bool, onTap: @escaping (MergedSlot) -> Void, width: CGFloat) {
        self.dayEntries = dayEntries
        self.dayLabels = dayLabels
        self.dates = dates
        self.todayNum = todayNum
        self.dayNums = dayNums
        self.anyDayHasEntries = anyDayHasEntries
        self.onTap = onTap
        self.width = width

        // Slots + Tagestyp je Tag EINMAL berechnen (statt mehrfach pro Frame).
        var slots: [[MergedSlot]] = []
        var kinds: [DayKind] = []
        slots.reserveCapacity(6); kinds.reserveCapacity(6)
        for d in 0..<6 {
            let s = dayEntries.indices.contains(d) ? Timetable.buildSlots(dayEntries[d]) : []
            slots.append(s)
            kinds.append(Timetable.dayKind(dayEntries.indices.contains(d) ? dayEntries[d] : [],
                                           slots: s, hasOtherDayEntries: anyDayHasEntries, index: d))
        }
        self.daySlots = slots
        self.dayKinds = kinds

        let all = dayEntries.flatMap { $0 }
        let mn = all.map { Fmt.minutes($0.startTime) }.min() ?? 470
        let mx = all.map { Fmt.minutes($0.endTime) }.max() ?? 1005
        self.minMins = mn
        self.maxMins = mx
        self.totalHeight = max(380, CGFloat(mx - mn) * 0.82)
        let vis = Self.periods.filter { $0.e > mn && $0.s < mx }
        self.visiblePeriods = vis
        var set = Set<Int>()
        for p in vis { set.insert(p.s); set.insert(p.e) }
        self.boundaryTimes = set.filter { $0 >= mn - 2 && $0 <= mx + 2 }.sorted()
    }

    /// Nur Daten vergleichen (Closure ignorieren) → SwiftUI überspringt das Neu-Rendern
    /// beim horizontalen Blättern, solange sich die Wochendaten nicht ändern.
    static func == (l: WeekGrid, r: WeekGrid) -> Bool {
        l.width == r.width && l.todayNum == r.todayNum &&
        l.dayNums == r.dayNums && l.dates == r.dates && l.dayEntries == r.dayEntries
    }

    private func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
    private var colW: CGFloat { (width - gutter - 10) / 6 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                headerRow(colW: colW)
                HStack(alignment: .top, spacing: 0) {
                    timeAxis
                    ForEach(0..<6, id: \.self) { d in
                        dayColumn(d, width: colW)
                    }
                }
                .frame(height: totalHeight)
            }
            .padding(.horizontal, 5).padding(.bottom, 16)
        }
    }

    private func headerRow(colW: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(0..<6, id: \.self) { d in
                let isToday = dayNums[d] == todayNum
                VStack(spacing: 1) {
                    Text(dayLabels[d]).font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? Palette.accent : Palette.textSecondary)
                    Text("\(Calendar.current.component(.day, from: dates[d]))")
                        .font(.footnote.bold())
                        .foregroundStyle(isToday ? .white : Palette.textPrimary)
                        .frame(width: 22, height: 22)
                        .background(isToday ? Palette.accent : Color.clear, in: Circle())
                }
                .frame(width: colW)
            }
        }
        .padding(.vertical, 6)
    }

    private var timeAxis: some View {
        ZStack(alignment: .topLeading) {
            // Periodennummern (zentriert in der Stunde)
            ForEach(visiblePeriods, id: \.num) { p in
                Text("\(p.num).")
                    .font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
                    .frame(width: gutter - 4, alignment: .trailing)
                    .offset(y: CGFloat((p.s + p.e) / 2 - minMins) * pxPerMin - 6)
            }
            // Uhrzeiten an den Periodengrenzen
            ForEach(boundaryTimes, id: \.self) { m in
                Text(hhmm(m))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    .frame(width: gutter - 4, alignment: .trailing)
                    .offset(y: CGFloat(m - minMins) * pxPerMin - 6)
            }
        }
        .frame(width: gutter, height: totalHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func dayColumn(_ d: Int, width: CGFloat) -> some View {
        let kind = dayKinds[d]
        ZStack(alignment: .topLeading) {
            ForEach(boundaryTimes, id: \.self) { m in
                Rectangle().fill(Palette.separator.opacity(0.35)).frame(height: 0.5)
                    .offset(y: CGFloat(m - minMins) * pxPerMin)
            }
            if kind != .normal {
                SpecialDayCard(kind: kind, fullWidth: false)
                    .frame(width: width - 4, height: totalHeight - 6)
                    .offset(x: 2, y: 3)
            } else {
                ForEach(daySlots[d]) { slot in
                    let top = CGFloat(Fmt.minutes(slot.display.startTime) - minMins) * pxPerMin
                    let h = max(24, CGFloat(Fmt.minutes(slot.display.endTime) - Fmt.minutes(slot.display.startTime)) * pxPerMin)
                    Button { onTap(slot) } label: { GridLessonCell(slot: slot, height: h) }
                        .buttonStyle(.pressable)
                        .frame(width: width - 4, height: h)
                        .offset(x: 2, y: top)
                }
            }
        }
        .frame(width: width, height: totalHeight, alignment: .topLeading)
    }
}

// ── Stunden-Zelle (Wochenraster) ────────────────────────────────────────────

struct GridLessonCell: View {
    let slot: MergedSlot
    let height: CGFloat

    private var d: TimetableEntry { slot.display }
    private var color: Color { Timetable.color(slot) }
    private var subjectText: String {
        d.subjectName.isEmpty ? (d.note ?? "—") : d.subjectName
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            HStack(spacing: 0) {
                if slot.kind == .normal && !d.isCancelled {
                    Rectangle().fill(color).frame(width: 3)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(subjectText).font(.system(size: 10, weight: .bold))
                        .strikethrough(d.isCancelled, color: Palette.danger)
                        .foregroundStyle(d.isCancelled ? Palette.danger.opacity(0.8) : Palette.textPrimary)
                        .lineLimit(height > 32 ? 2 : 1)
                    if height > 30 {
                        Text("\(Fmt.time(d.startTime))–\(Fmt.time(d.endTime))")
                            .font(.system(size: 7.5, weight: .medium)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                    if height > 52, !d.roomName.isEmpty {
                        Text(d.roomName).font(.system(size: 8)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                Spacer(minLength: 0)
            }
            statusIcon
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(borderColor, lineWidth: borderWidth))
    }

    @ViewBuilder private var background: some View {
        switch slot.kind {
        case .cancelled:
            DiagonalStripes().fill(Palette.danger.opacity(0.12))
                .background(Palette.danger.opacity(0.06))
        case .exam:    Palette.warning.opacity(0.13)
        case .replacement: Palette.orange.opacity(0.12)
        case .event:   Palette.accent.opacity(0.12)
        case .normal:  Palette.surface
        }
    }
    private var borderColor: Color {
        switch slot.kind {
        case .cancelled: return Palette.danger.opacity(0.6)
        case .exam: return Palette.warning.opacity(0.4)
        case .replacement: return Palette.orange.opacity(0.4)
        case .event: return Palette.accent.opacity(0.35)
        case .normal: return Palette.border
        }
    }
    private var borderWidth: CGFloat { slot.kind == .cancelled ? 1.5 : 0.6 }

    @ViewBuilder private var statusIcon: some View {
        let sym: String? = {
            if d.isCancelled && slot.replacement != nil { return "arrow.left.arrow.right" }
            if d.isCancelled { return "xmark" }
            if d.isExam { return "doc.text" }
            if slot.kind == .replacement { return "arrow.left.arrow.right" }
            if slot.kind == .event { return "calendar" }
            return nil
        }()
        if let sym, height > 28 {
            Image(systemName: sym).font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(4)
        }
    }
}

/// Stundenzeile für die Tagesansicht.
struct SlotRow: View {
    let slot: MergedSlot
    private var d: TimetableEntry { slot.display }
    private var color: Color { Timetable.color(slot) }
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 5, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(d.subjectName.isEmpty ? (d.note ?? "—") : d.subjectName)
                        .font(.subheadline.bold())
                        .strikethrough(d.isCancelled, color: Palette.danger)
                        .foregroundStyle(Palette.textPrimary)
                    badge
                }
                if !d.teacherName.isEmpty || !d.roomName.isEmpty {
                    Text([d.teacherName, d.roomName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
                if let r = slot.replacement {
                    Label("Ersatz: \(r.subjectName.isEmpty ? (r.note ?? "") : r.subjectName)", systemImage: "arrow.left.arrow.right")
                        .font(.caption2).foregroundStyle(Palette.orange)
                }
            }
            Spacer()
            Text("\(Fmt.time(d.startTime))\n\(Fmt.time(d.endTime))")
                .font(.caption2.monospacedDigit()).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .cardSurface(radius: 12)
    }
    @ViewBuilder private var badge: some View {
        if d.isCancelled { tag("Entfall", Palette.danger) }
        else if d.isExam { tag("Prüfung", Palette.warning) }
        else if slot.kind == .replacement { tag("Vertretung", Palette.orange) }
        else if slot.kind == .event { tag("Veranstaltung", Palette.accent) }
    }
    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 9, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.2), in: Capsule()).foregroundStyle(c)
    }
}

// ── Spezial-Tag (Ferien / Wochenende / Entfall / Vertretung / Veranstaltung) ─

struct SpecialDayCard: View {
    let kind: DayKind
    var fullWidth: Bool

    private var config: (color: Color, icon: String, title: String, desc: String) {
        switch kind {
        case .holiday:       return (Palette.orange, "beach.umbrella.fill", "Ferien", "Kein Unterricht")
        case .weekend:       return (Palette.tint, "sun.max.fill", "Wochenende", "Frei")
        case .allCancelled:  return (Palette.danger, "xmark.circle.fill", "Entfall", "Alle Stunden ausgefallen")
        case .allReplacement:return (Palette.accent, "arrow.left.arrow.right", "Vertretung", "Tag durchgehend ersetzt")
        case .fullDayEvent:  return (Palette.accent, "calendar", "Veranstaltung", "Ganztägig")
        case .normal:        return (Palette.accent, "calendar", "", "")
        }
    }

    var body: some View {
        let c = config
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.color.opacity(0.08))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(c.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
            VStack(spacing: 6) {
                Image(systemName: c.icon)
                    .font(.system(size: fullWidth ? 26 : 15))
                    .foregroundStyle(c.color)
                    .frame(width: fullWidth ? 48 : 28, height: fullWidth ? 48 : 28)
                    .background(c.color.opacity(0.18), in: Circle())
                Text(c.title).font(fullWidth ? .headline : .system(size: 11, weight: .bold))
                    .foregroundStyle(c.color).multilineTextAlignment(.center)
                Text(c.desc).font(fullWidth ? .subheadline : .system(size: 8.5))
                    .foregroundStyle(Palette.textTertiary).multilineTextAlignment(.center)
            }
            .padding(8)
        }
        // füllt die Höhe, die der Aufrufer vorgibt (Spalte = bis ganz unten).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Diagonale Streifen für Entfall-Zellen (wie repeating-linear-gradient im Web).
struct DiagonalStripes: Shape {
    var spacing: CGFloat = 7
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.height))
            p.addLine(to: CGPoint(x: x + rect.height, y: 0))
            p.addLine(to: CGPoint(x: x + rect.height + spacing / 2, y: 0))
            p.addLine(to: CGPoint(x: x + spacing / 2, y: rect.height))
            p.closeSubpath()
            x += spacing
        }
        return p
    }
}

// ── Detail-Sheet (Liquid Glass) ──────────────────────────────────────────────

struct LessonDetailView: View {
    let slot: MergedSlot
    @Environment(\.dismiss) private var dismiss

    private var d: TimetableEntry { slot.display }
    private var accent: Color { Timetable.color(slot) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        if d.isCancelled && slot.replacement == nil { tag("Entfall", Palette.danger) }
                        if slot.replacement != nil { tag("Vertretung", Palette.orange) }
                        if d.isExam { tag("Prüfung", Palette.warning) }
                        if d.isSubstitution && !d.isCancelled && slot.replacement == nil { tag("Vertretung", Palette.orange) }
                        if slot.kind == .event { tag("Veranstaltung", Palette.accent) }
                    }
                    Text(headerName).font(.largeTitle.bold())
                        .strikethrough(d.isCancelled && slot.replacement == nil, color: Palette.danger)
                        .foregroundStyle(Palette.textPrimary)
                    Label("\(Fmt.time(d.startTime)) – \(Fmt.time(d.endTime))", systemImage: "clock")
                        .foregroundStyle(Palette.textSecondary)

                    detailsCard
                    if let r = slot.replacement { replacementCard(r) }
                    if let note = d.note, !note.isEmpty { section("Notiz", note) }
                    if d.isExam, let desc = d.examDescription, !desc.isEmpty { section("Prüfungsinhalt", desc) }
                    Spacer()
                }
                .padding(20)
            }
            .appBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.regularMaterial)
    }

    private var headerName: String {
        if let r = slot.replacement { return r.subjectLong.isEmpty ? (r.subjectName.isEmpty ? (r.note ?? "") : r.subjectName) : r.subjectLong }
        return d.subjectLong.isEmpty ? (d.subjectName.isEmpty ? (d.note ?? "Stunde") : d.subjectName) : d.subjectLong
    }

    @ViewBuilder private var detailsCard: some View {
        let teacher = d.teacherLongName ?? d.teacherName
        let origTeacher = d.originalTeacherLong ?? (d.originalTeacher ?? "")
        VStack(alignment: .leading, spacing: 12) {
            if !teacher.isEmpty || !origTeacher.isEmpty {
                if !origTeacher.isEmpty && origTeacher != teacher {
                    changeRow("Lehrer", from: origTeacher, to: teacher, icon: "person.fill")
                } else {
                    detailRow("Lehrer", teacher.isEmpty ? origTeacher : teacher, "person.fill")
                }
            }
            let room = d.roomName, origRoom = d.originalRoom ?? ""
            if !room.isEmpty || !origRoom.isEmpty {
                if !origRoom.isEmpty && origRoom != room {
                    changeRow("Raum", from: origRoom, to: room, icon: "mappin.circle.fill")
                } else {
                    detailRow("Raum", room.isEmpty ? origRoom : room, "mappin.circle.fill")
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func replacementCard(_ r: TimetableEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Statt", systemImage: "arrow.left.arrow.right").font(.caption.bold()).foregroundStyle(Palette.textSecondary)
            Text(d.subjectLong.isEmpty ? d.subjectName : d.subjectLong)
                .font(.subheadline.bold()).foregroundStyle(Palette.textTertiary)
                .strikethrough(true, color: Palette.danger)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
            .background(c.opacity(0.2), in: Capsule()).foregroundStyle(c)
    }
    private func detailRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased()).font(.caption2).foregroundStyle(Palette.textTertiary)
                Text(value).font(.subheadline.weight(.medium)).foregroundStyle(Palette.textPrimary)
            }
            Spacer()
        }
    }
    private func changeRow(_ label: String, from: String, to: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(.caption2).foregroundStyle(Palette.textTertiary)
                HStack(spacing: 6) {
                    Text(from).strikethrough(true, color: Palette.danger).foregroundStyle(Palette.danger)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Palette.textTertiary)
                    Text(to).foregroundStyle(Palette.orange)
                }.font(.subheadline.weight(.medium))
            }
            Spacer()
        }
    }
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(Palette.textSecondary)
            Text(body).font(.subheadline).foregroundStyle(Palette.textPrimary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }
}
