import SwiftUI
import PokyhCore
import PokyhDesign

// ── Slots and day kinds (ported from the web's app/timetable/page.tsx) ──────

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

    /// Groups one day's entries into slots, folding a cancellation and its stand-in together.
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

        // A cancellation that sits entirely inside a lesson that happens adds nothing.
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

    /// Same, for callers that already built the slots.
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

    /// This school's bell schedule. Only gives the axis its period numbers.
    static let periods: [(num: Int, s: Int, e: Int)] = [
        (1, 470, 520), (2, 520, 570), (3, 570, 620), (4, 635, 685), (5, 685, 735),
        (6, 735, 785), (7, 795, 845), (8, 845, 895), (9, 905, 955), (10, 955, 1005),
    ]

    /// Hues are handed out per week, so a week looks the same on the web, Android and here.
    static func hues(for entries: [TimetableEntry]) -> SubjectHues {
        let hues = SubjectHues()
        hues.register(entries.map(\.subjectName))
        return hues
    }

    /// At grid density the state is what you scan for, so it outranks the subject.
    static func tone(_ entry: TimetableEntry, kind: SlotKind, hues: SubjectHues) -> Tone {
        if kind == .cancelled || entry.isCancelled { return .cancelled }
        if entry.isExam || kind == .exam { return .exam }
        if kind == .event || entry.subjectName.isEmpty { return .event }
        return .subject(entry.subjectName, hues: hues)
    }

    struct Changes { var subject = false, teacher = false, room = false }

    /// Which fields WebUntis changed. A cancelled lesson isn't changed, it's gone.
    static func changes(_ e: TimetableEntry) -> Changes {
        guard !e.isCancelled else { return Changes() }
        func changed(_ original: String?, _ current: String) -> Bool {
            let o = (original ?? "").trimmingCharacters(in: .whitespaces)
            return !o.isEmpty && o != current.trimmingCharacters(in: .whitespaces)
        }
        return Changes(
            subject: changed(e.originalSubject, e.subjectName),
            teacher: changed(e.originalTeacher, e.teacherName),
            room: changed(e.originalRoom, e.roomName)
        )
    }

    static func date(_ num: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: num / 10000, month: num / 100 % 100, day: num % 100))
    }

    /// Monday is 0, like the string tables.
    static func weekdayIndex(_ date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7
    }

    static func minuteNow(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    static func subjectText(_ e: TimetableEntry) -> String {
        e.subjectName.isEmpty ? (e.note ?? "—") : e.subjectName
    }
}

/// What the detail sheet opens with: the slot and the color it had where it was tapped.
struct LessonDetailItem: Identifiable {
    let slot: MergedSlot
    let tone: Tone
    var id: UUID { slot.id }
}

/// A day another screen wants the timetable to open on (a search result, Home's exam).
/// The timetable takes it when it next shows and clears it.
@Observable
final class TimetableJump {
    static let shared = TimetableJump()
    /// YYYYMMDD
    var day: Int?
}

// ── Holidays (Android's core/util/SchoolHolidays) ───────────────────────────

/// Names the breaks an empty timetable stands for. WebUntis often calls them only "Ferien3",
/// so a break is named by when it is: the holidays of the Italian (and South Tyrolean) school
/// year and the public holidays around them. Gives a key into `holidayNames`.
enum SchoolHolidays {
    /// Easter Sunday (anonymous Gregorian algorithm).
    static func easterSunday(_ year: Int) -> Date {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private static let calendar = Calendar(identifier: .gregorian)

    private static let fixed: [String: String] = [
        "01-01": "newYear", "01-06": "epiphany", "04-25": "liberation", "05-01": "labour",
        "06-02": "republic", "08-15": "assumption", "11-01": "allSaints", "12-08": "immaculate",
        "12-25": "christmasDay", "12-26": "stStephen",
    ]

    static func publicHoliday(on date: Date) -> String? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        if let key = fixed[String(format: "%02d-%02d", c.month ?? 0, c.day ?? 0)] { return key }
        let fromEaster = calendar.dateComponents([.day], from: easterSunday(c.year ?? 0), to: calendar.startOfDay(for: date)).day
        switch fromEaster {
        case 1: return "easterMonday"
        case 39: return "ascension"
        case 50: return "pentecost"
        case 60: return "corpusChristi"
        default: return nil
        }
    }

    /// What kind of break the days from `start` to `end` are (the web's holidayKey). A week
    /// that's empty from Monday to Sunday doesn't show how long the break really is, so there
    /// the time of year decides.
    static func key(from start: Date, to end: Date, wholeWeek: Bool = false) -> String {
        let start = calendar.startOfDay(for: start), end = calendar.startOfDay(for: end)
        let length = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let startYear = calendar.component(.year, from: start)
        let month = calendar.component(.month, from: start)
        func covers(_ d: Date) -> Bool { d >= start && d <= end }
        func inside(_ m: Int, _ d: Int) -> Bool {
            [startYear, startYear + 1].contains { y in
                calendar.date(from: DateComponents(year: y, month: m, day: d)).map(covers) ?? false
            }
        }

        if inside(12, 25) || inside(1, 1) { return length >= 3 ? "christmas" : inside(12, 25) ? "christmasDay" : "newYear" }
        let easter = easterSunday(startYear)
        let easterMonday = calendar.date(byAdding: .day, value: 1, to: easter) ?? easter
        if length >= 3, covers(easter) || covers(easterMonday) { return "easter" }
        if wholeWeek {
            // The first days of January still belong to Christmas; a free week in summer is summer.
            if month == 1, calendar.component(.day, from: start) <= 7 { return "christmas" }
            let thursday = calendar.date(byAdding: .day, value: 3, to: start) ?? start
            if (6...9).contains(calendar.component(.month, from: thursday)) { return "summer" }
        }
        if length >= 3 {
            if length >= 21, (6...8).contains(month) { return "summer" }
            if month == 10 || month == 11 { return "autumn" }
            if month == 2 || (month == 3 && calendar.component(.day, from: start) <= 7) { return "carnival" }
        }
        var day = start
        while day <= end {
            if let key = publicHoliday(on: day) { return key }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end.addingTimeInterval(1)
        }
        return length >= 3 ? "break" : "dayOff"
    }

    /// A whole week without lessons, Monday to Sunday.
    static func weekKey(_ monday: Date) -> String {
        key(from: monday, to: calendar.date(byAdding: .day, value: 6, to: monday) ?? monday, wholeWeek: true)
    }

    /// The key for each holiday day of a week, taken over the run of free weekdays it sits in,
    /// so a Wednesday-to-Friday break is named as one.
    static func dayKeys(dayNums: [Int], kinds: [DayKind]) -> [String?] {
        var out = [String?](repeating: nil, count: kinds.count)
        var i = 0
        while i < kinds.count {
            guard kinds[i] == .holiday else { i += 1; continue }
            var j = i
            while j + 1 < kinds.count, kinds[j + 1] == .holiday { j += 1 }
            if let a = Timetable.date(dayNums[i]), let b = Timetable.date(dayNums[j]) {
                let k = key(from: a, to: b)
                for d in i...j { out[d] = k }
            }
            i = j + 1
        }
        return out
    }
}

// ── Screen ──────────────────────────────────────────────────────────────────

struct TimetableView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var weekOffset = 0
    @State private var entries: [TimetableEntry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var mode: Mode = .week
    @State private var selectedDay = 0
    @State private var detail: LessonDetailItem?
    @State private var shareItem: ShareItem?
    @State private var exporting = false
    @State private var width: CGFloat = 0

    enum Mode: CaseIterable { case week, day }

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
    private var compact: Bool { WidthClass(width: width) == .compact }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
            if !compact {
                WeekFigures(entries: entries, todayNum: SchoolDates.todayNum())
                    .padding(.horizontal, Spacing.screenH)
                    .padding(.bottom, Spacing.md)
            }
            PokyhSegmentedControl(Mode.allCases, selection: $mode) {
                $0 == .week ? s.timetable.modeWeek : s.timetable.modeDay
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.md)
            content
        }
        .frame(maxWidth: WidthClass.wideMaxWidth)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle(s.nav.timetable)
        .navigationBarTitleDisplayMode(.inline)
        .profileToolbar()
        .task(id: weekOffset) { await load() }
        .onAppear { if !takeJump() { selectInitialDay() } }
        .onChange(of: app.timetableHomeSignal) {
            withAnimation(.snappy(duration: 0.3)) { weekOffset = 0; selectInitialDay() }
        }
        .onChange(of: TimetableJump.shared.day) { _ = takeJump() }
        .sheet(item: $detail) { LessonDetailView(item: $0) }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { exportWeek() } label: {
                        Label(s.timetable.exportWeek, systemImage: "calendar")
                    }
                    Button { Task { await exportExams() } } label: {
                        Label(s.timetable.exportExams, systemImage: "graduationcap")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(s.timetable.export)
                .disabled(exporting)
            }
        }
    }

    // ── .ics export ─────────────────────────────────────────────────────────

    private func share(_ entries: [TimetableEntry], name: String) {
        guard !entries.isEmpty else { return }
        let ics = ICSExport.makeCalendar(entries, calendarName: name)
        if let url = ICSExport.writeTempFile(ics, name: name) { shareItem = ShareItem(url: url) }
    }
    private func exportWeek() {
        share((0..<6).flatMap { entriesFor($0) }, name: s.timetable.icsWeekName)
    }
    private func exportExams() async {
        guard let session = app.session else { return }
        exporting = true; defer { exporting = false }
        let exams = (try? await UntisClient.shared.upcomingExams(session)) ?? []
        share(exams, name: s.timetable.icsExamsName)
    }

    // ── Week stepper ────────────────────────────────────────────────────────

    /// Android's phone header: the week in the middle, and beside it the school year, or the
    /// way back to today once another week is showing.
    private var weekHeader: some View {
        HStack(spacing: Spacing.sm) {
            IconButton("chevron.left", label: s.timetable.prevWeek, tinted: true, tint: Palette.accentText) { step(-1) }
            VStack(spacing: Spacing.xxs) {
                Text(rangeText)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(verbatim: weekOffset == 0 ? "\(s.timetable.cw(weekNumber)) · \(s.timetable.thisWeek)" : s.timetable.cw(weekNumber))
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            if weekOffset != 0 {
                Button(s.timetable.toToday) {
                    withAnimation(.snappy(duration: 0.34, extraBounce: 0.08)) { weekOffset = 0; selectInitialDay() }
                }
                .buttonStyle(.plain)
                .textStyle(TextStyle.footnote.weight(.semibold))
                .foregroundStyle(Palette.accentText)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 36)
                .background(Palette.accentTint, in: .capsule)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                yearMenu.transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            IconButton("chevron.right", label: s.timetable.nextWeek, tinted: true, tint: Palette.accentText) { step(1) }
        }
        .animation(Motion.standardEase, value: weekOffset == 0)
        .padding(.horizontal, Spacing.screenH)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.md)
    }

    private func step(_ by: Int) {
        withAnimation(.snappy(duration: 0.34, extraBounce: 0.08)) { weekOffset += by }
    }

    // ── School year ─────────────────────────────────────────────────────────

    /// The school year (from 1 September) the week at `offset` belongs to. Thursday decides,
    /// like the ISO week number, so a week across 1 September counts toward the new year.
    private func schoolYear(of offset: Int) -> Int {
        let cal = Calendar.current
        let thursday = cal.date(byAdding: .day, value: offset * 7 + 3, to: thisMonday) ?? thisMonday
        let year = cal.component(.year, from: thursday)
        return cal.component(.month, from: thursday) >= 9 ? year : year - 1
    }

    private func yearLabel(_ year: Int, short: Bool) -> String {
        short ? String(format: "%02d/%02d", year % 100, (year + 1) % 100) : "\(year)/\(String(format: "%02d", (year + 1) % 100))"
    }

    /// The current school year goes back to today, any other to the same week shifted into that year.
    private func selectSchoolYear(_ year: Int) {
        let shown = schoolYear(of: weekOffset)
        guard year != shown else { return }
        withAnimation(.snappy(duration: 0.34)) {
            if year == SchoolDates.currentSchoolYear {
                weekOffset = 0
                selectInitialDay()
                return
            }
            let cal = Calendar.current
            var c = cal.dateComponents([.year, .month, .day], from: monday)
            c.year = (c.year ?? 0) + (year - shown)
            if let target = cal.date(from: c) { weekOffset = offset(to: target) }
        }
    }

    private var yearMenu: some View {
        let shown = schoolYear(of: weekOffset)
        return Menu {
            Picker(s.common.schoolYear(shown), selection: Binding(get: { shown }, set: selectSchoolYear)) {
                ForEach(SchoolDates.availableYears, id: \.self) { y in
                    Text(verbatim: yearLabel(y, short: false)).tag(y)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(verbatim: yearLabel(shown, short: compact))
                    .textStyle(TextStyle.footnote.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            .background(Palette.cardAlt, in: .capsule)
            .contentShape(.capsule)
        }
        .accessibilityLabel(s.common.schoolYear(shown))
    }

    // ── Jumping to a day ────────────────────────────────────────────────────

    /// Weeks from this week to the one holding `date`.
    private func offset(to date: Date) -> Int {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let target = cal.date(from: comps) ?? date
        let days = Calendar.current.dateComponents([.day], from: thisMonday, to: target).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    /// Opens the week and day another screen asked for; false when nothing was asked.
    private func takeJump() -> Bool {
        guard let day = TimetableJump.shared.day else { return false }
        TimetableJump.shared.day = nil
        guard let date = Timetable.date(day) else { return false }
        withAnimation(.snappy(duration: 0.34)) {
            weekOffset = offset(to: date)
            selectedDay = min(5, Timetable.weekdayIndex(date))
        }
        return true
    }

    private var weekNumber: Int { Calendar(identifier: .iso8601).component(.weekOfYear, from: monday) }
    private var rangeText: String {
        let cal = Calendar.current
        let start = monday, end = dayDate(5)
        let a = s.common.dayMonthShort(cal.component(.day, from: start), cal.component(.month, from: start))
        let b = s.common.dayMonthShort(cal.component(.day, from: end), cal.component(.month, from: end))
        return "\(a) – \(b) \(cal.component(.year, from: end))"
    }

    // Wide enough for every school year in the year menu; pages are light and only visible ones load.
    private let pageSpan = 220
    private var weekRange: ClosedRange<Int> { -pageSpan...pageSpan }

    @ViewBuilder
    private var content: some View {
        if mode == .week {
            // Paging horizontal ScrollView: only the visible weeks render, size measured once.
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(weekRange, id: \.self) { off in
                            WeekTimetablePage(weekOffset: off, size: geo.size,
                                              initialEntries: cachedEntries(for: off),
                                              onTap: { detail = LessonDetailItem(slot: $0, tone: $1) })
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

    /// Swiping and the chevrons both drive `weekOffset`.
    private var scrollWeekBinding: Binding<Int?> {
        Binding(get: { weekOffset }, set: { if let v = $0, v != weekOffset { weekOffset = v } })
    }

    /// A week that's already prefetched shows at once, without a skeleton flash.
    private func cachedEntries(for off: Int) -> [TimetableEntry]? {
        guard let session = app.session,
              let m = Calendar.current.date(byAdding: .day, value: off * 7, to: thisMonday) else { return nil }
        return UntisClient.shared.cachedTimetable(date: DateFmt.isoString(m), session)
    }

    // ── Day mode ────────────────────────────────────────────────────────────

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

    private var dayView: some View {
        VStack(spacing: 0) {
            DayPills(
                days: (0..<6).map { dayDate($0) },
                selection: $selectedDay,
                isToday: { DateFmt.num($0) == SchoolDates.todayNum() },
                weekday: { s.common.weekdaysShort[Timetable.weekdayIndex($0)].capitalized },
                dayNumber: { "\(Calendar.current.component(.day, from: $0))" }
            )
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.lg)

            ScrollView {
                dayContent
                    .padding(.horizontal, Spacing.screenH)
                    .padding(.bottom, Spacing.xxxl)
            }
            .id(selectedDay)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .simultaneousGesture(daySwipe)
        }
    }

    @ViewBuilder
    private var dayContent: some View {
        let de = entriesFor(selectedDay)
        if loading && entries.isEmpty {
            TileRowSkeleton(rows: 5)
        } else if let error, entries.isEmpty {
            PokyhDesign.ErrorStateView(error) { Task { await load() } }
        } else if entries.isEmpty && app.isOffline {
            OfflineWeekState { Task { await load() } }
        } else if !anyDayHasEntries {
            SpecialDayCard(kind: .holiday, compact: false, plate: true, holidayKey: SchoolHolidays.weekKey(monday))
        } else {
            let slots = Timetable.buildSlots(de)
            let kind = Timetable.dayKind(de, slots: slots, hasOtherDayEntries: anyDayHasEntries, index: selectedDay)
            let hues = Timetable.hues(for: entries)
            if kind == .weekend {
                // An empty Saturday is the absence of a timetable, not an entry in it.
                InlineNotice(s.timetable.noLessons, symbol: "checkmark.circle.fill", tint: Brand.success)
            } else if kind != .normal {
                let tappable = kind != .allCancelled && kind != .holiday
                SpecialDayCard(kind: kind, compact: false, plate: true,
                               holidayKey: kind == .holiday ? holidayKey(selectedDay) : nil)
                    .contentShape(.rect)
                    .onTapGesture {
                        if tappable, let first = slots.first {
                            detail = LessonDetailItem(slot: first, tone: Timetable.tone(first.display, kind: first.kind, hues: hues))
                        }
                    }
            } else {
                LazyVStack(spacing: Spacing.rowGap) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { idx, slot in
                        let shown = slot.replacement ?? slot.display
                        let tone = Timetable.tone(shown, kind: slot.replacement == nil ? slot.kind : .replacement, hues: hues)
                        DaySlotRow(slot: slot, tone: tone) {
                            detail = LessonDetailItem(slot: slot, tone: tone)
                        }
                        .fadeIn(delay: Double(idx) * 0.03)
                    }
                }
            }
        }
    }

    /// The break a free weekday of the shown week belongs to.
    private func holidayKey(_ day: Int) -> String? {
        let nums = (0..<6).map(dayNum)
        let kinds = (0..<6).map { Timetable.dayKind(entriesFor($0), hasOtherDayEntries: anyDayHasEntries, index: $0) }
        return SchoolHolidays.dayKeys(dayNums: nums, kinds: kinds)[day]
    }

    private func selectInitialDay() {
        let today = SchoolDates.todayNum()
        selectedDay = (0..<6).first(where: { dayNum($0) == today }) ?? 0
    }

    private func load() async {
        guard let session = app.session else { return }
        loading = true; error = nil
        do {
            entries = try await UntisClient.shared.timetable(date: DateFmt.isoString(monday), session)
            WatchSync.timetable(entries, week: DateFmt.isoString(monday), for: session)
            // This week of the default account feeds the widget and the Live Activity.
            if weekOffset == 0, app.isDefaultAccountActive {
                WidgetBridge.publish(entries); app.refreshLiveActivity(from: entries)
            }
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
        prefetchAdjacent()
    }

    /// Two weeks either side stay in the cache, so paging never waits.
    private static let preloadRadius = 2

    private func prefetchAdjacent() {
        guard let session = app.session else { return }
        for off in (-Self.preloadRadius...Self.preloadRadius) where off != 0 {
            guard let m = Calendar.current.date(byAdding: .day, value: (weekOffset + off) * 7, to: thisMonday) else { continue }
            let iso = DateFmt.isoString(m)
            Task { _ = try? await UntisClient.shared.timetable(date: iso, session) }
        }
    }
}

// ── One week page ───────────────────────────────────────────────────────────

struct WeekTimetablePage: View {
    let weekOffset: Int
    let size: CGSize
    let onTap: (MergedSlot, Tone) -> Void
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var entries: [TimetableEntry]
    @State private var loading: Bool
    @State private var error: String?

    /// Starts from the prefetch cache when it can; `.task` then revalidates quietly.
    init(weekOffset: Int, size: CGSize, initialEntries: [TimetableEntry]?, onTap: @escaping (MergedSlot, Tone) -> Void) {
        self.weekOffset = weekOffset
        self.size = size
        self.onTap = onTap
        _entries = State(initialValue: initialEntries ?? [])
        _loading = State(initialValue: initialEntries == nil)
    }

    private var thisMonday: Date {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }
    private var monday: Date { Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: thisMonday) ?? thisMonday }
    private func dayDate(_ i: Int) -> Date { Calendar.current.date(byAdding: .day, value: i, to: monday) ?? monday }
    private func dayNum(_ i: Int) -> Int { DateFmt.num(dayDate(i)) }

    var body: some View {
        Group {
            if loading {
                WeekGridSkeleton(size: size)
            } else if let error {
                PokyhDesign.ErrorStateView(error) { Task { await load() } }
            } else if entries.isEmpty && app.isOffline {
                // An empty week off the disk isn't proof of holidays.
                OfflineWeekState { Task { await load() } }
            } else if entries.isEmpty {
                HolidayWeek(month: Calendar.current.component(.month, from: monday), holidayKey: SchoolHolidays.weekKey(monday))
            } else {
                let cal = Calendar.current
                let dates = (0..<6).map { dayDate($0) }
                let nums = dates.map { DateFmt.num($0) }
                WeekGrid(
                    dayEntries: nums.map { n in entries.filter { $0.date == n } },
                    dayLabels: dates.map { s.common.weekdaysShort[Timetable.weekdayIndex($0)].capitalized },
                    dayNumbers: dates.map { cal.component(.day, from: $0) },
                    weekLabel: s.timetable.cw(Calendar(identifier: .iso8601).component(.weekOfYear, from: monday)),
                    monthLabel: s.common.monthsShort[cal.component(.month, from: monday) - 1],
                    todayNum: SchoolDates.todayNum(),
                    dayNums: nums,
                    size: size,
                    onTap: onTap
                )
                .equatable()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let session = app.session else { return }
        loading = entries.isEmpty
        error = nil
        do {
            entries = try await UntisClient.shared.timetable(date: DateFmt.isoString(monday), session)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}

// ── Week grid ───────────────────────────────────────────────────────────────

/// One box in a day column, already resolved to its times and its slice of the column width.
/// A substitution is two boxes: the lesson that happens and the one that was called off.
struct GridCell: Identifiable {
    let id: String
    /// What a tap opens.
    let slot: MergedSlot
    let entry: TimetableEntry
    let kind: SlotKind
    let tone: Tone
    let start: Int
    let end: Int
    /// Left edge and width in per-mille of the column.
    var lane = 0
    var span = GridCell.perMille

    static let perMille = 1000

    var isCancelled: Bool { kind == .cancelled || entry.isCancelled }
    func overlaps(_ o: GridCell) -> Bool { start < o.end && o.start < end }
}

enum GridLayout {
    /// What the lesson that happens keeps when a cancellation runs alongside it.
    static let activeShare = 750

    static func cells(_ slots: [MergedSlot], hues: SubjectHues) -> [GridCell] {
        var cells: [GridCell] = []
        func cell(_ id: String, _ slot: MergedSlot, _ entry: TimetableEntry, _ kind: SlotKind) -> GridCell {
            GridCell(id: id, slot: slot, entry: entry, kind: kind,
                     tone: Timetable.tone(entry, kind: kind, hues: hues),
                     start: Fmt.minutes(entry.startTime), end: Fmt.minutes(entry.endTime))
        }
        for slot in slots {
            if slot.kind == .replacement, let replacement = slot.replacement {
                let key = slot.id.uuidString
                // The lesson that happens, at its own times.
                cells.append(cell(key + "-active",
                                  MergedSlot(display: replacement, replacement: slot.display, kind: .replacement),
                                  replacement, .replacement))
                // The original only gets its own box when it isn't already a standalone slot.
                let standalone = slots.contains { $0.kind == .cancelled && $0.display.id == slot.display.id }
                if !standalone {
                    cells.append(cell(key + "-cancelled",
                                      MergedSlot(display: slot.display, replacement: replacement, kind: .cancelled),
                                      slot.display, .cancelled))
                }
            } else {
                cells.append(cell(slot.id.uuidString, slot, slot.display, slot.kind))
            }
        }
        // One lesson covering two cancelled periods comes back twice; draw it once.
        var seen = Set<String>()
        let unique = cells.filter { c in
            guard c.end > c.start else { return false }
            return seen.insert("\(c.entry.id)-\(c.start)-\(c.end)-\(c.kind)").inserted
        }
        return resolveHorizontal(unique)
    }

    /// The lesson that happens leads, cancellations fill in behind it, and a cell widens into
    /// any lane that stays free for its whole duration.
    static func resolveHorizontal(_ cells: [GridCell]) -> [GridCell] {
        let ordered = cells.sorted {
            if $0.isCancelled != $1.isCancelled { return !$0.isCancelled }
            if $0.start != $1.start { return $0.start < $1.start }
            return ($0.end - $0.start) > ($1.end - $1.start)
        }
        var lanes: [String: Int] = [:]
        for c in ordered {
            var lane = 0
            while ordered.contains(where: { $0.id != c.id && lanes[$0.id] == lane && $0.overlaps(c) }) { lane += 1 }
            lanes[c.id] = lane
        }
        let laneCount = (lanes.values.max() ?? 0) + 1
        let trailing = ordered.filter { lanes[$0.id] == 1 }
        let leading = ordered.filter { lanes[$0.id] == 0 }
        let weighted = laneCount == 2 && !trailing.isEmpty
            && trailing.allSatisfy(\.isCancelled) && leading.contains { !$0.isCancelled }
        let edges = weighted
            ? [0, activeShare, GridCell.perMille]
            : (0...laneCount).map { $0 * GridCell.perMille / laneCount }

        return ordered.map { c in
            let lane = lanes[c.id] ?? 0
            var last = lane
            while last + 1 < laneCount,
                  !ordered.contains(where: { $0.id != c.id && lanes[$0.id] == last + 1 && $0.overlaps(c) }) {
                last += 1
            }
            var out = c
            out.lane = edges[lane]
            out.span = edges[last + 1] - edges[lane]
            return out
        }
    }
}

/// Six day columns against a time axis built from the week's own lesson times. The day is
/// spread over the height there is, so a whole school day shows without scrolling.
struct WeekGrid: View, Equatable {
    let dayEntries: [[TimetableEntry]]
    let dayLabels: [String]
    let dayNumbers: [Int]
    let weekLabel: String
    let monthLabel: String
    let todayNum: Int
    let dayNums: [Int]
    let size: CGSize
    let onTap: (MergedSlot, Tone) -> Void

    private let gutter: CGFloat = 42
    private let colGap: CGFloat = 3
    private let edge: CGFloat = 6
    private let headerRoom: CGFloat = 64
    private let minCellHeight: CGFloat = 26

    // Worked out once, so scrolling recomputes nothing.
    private let daySlots: [[MergedSlot]]
    private let dayKinds: [DayKind]
    private let holidayKeys: [String?]
    private let dayCells: [[GridCell]]
    private let hues: SubjectHues
    private let minMins: Int
    private let maxMins: Int
    private let pxPerMin: CGFloat
    private let visiblePeriods: [(num: Int, s: Int, e: Int)]
    private let boundaryTimes: [Int]

    init(dayEntries: [[TimetableEntry]], dayLabels: [String], dayNumbers: [Int], weekLabel: String,
         monthLabel: String, todayNum: Int, dayNums: [Int], size: CGSize, onTap: @escaping (MergedSlot, Tone) -> Void) {
        self.dayEntries = dayEntries
        self.dayLabels = dayLabels
        self.dayNumbers = dayNumbers
        self.weekLabel = weekLabel
        self.monthLabel = monthLabel
        self.todayNum = todayNum
        self.dayNums = dayNums
        self.size = size
        self.onTap = onTap

        let all = dayEntries.flatMap { $0 }
        let hues = Timetable.hues(for: all)
        self.hues = hues
        let anyDay = dayEntries.contains { !$0.isEmpty }
        var slots: [[MergedSlot]] = [], kinds: [DayKind] = [], cells: [[GridCell]] = []
        for d in 0..<6 {
            let entries = dayEntries.indices.contains(d) ? dayEntries[d] : []
            let s = Timetable.buildSlots(entries)
            slots.append(s)
            kinds.append(Timetable.dayKind(entries, slots: s, hasOtherDayEntries: anyDay, index: d))
            cells.append(GridLayout.cells(s, hues: hues))
        }
        daySlots = slots
        dayKinds = kinds
        holidayKeys = SchoolHolidays.dayKeys(dayNums: dayNums, kinds: kinds)
        dayCells = cells

        let periods = Timetable.periods
        let mn = all.map { Fmt.minutes($0.startTime) }.min() ?? periods.first!.s
        let mx = all.map { Fmt.minutes($0.endTime) }.max() ?? periods.last!.e
        minMins = mn
        maxMins = mx
        let fitted = (size.height - headerRoom - Spacing.xxxl) / CGFloat(max(1, mx - mn))
        pxPerMin = min(max(fitted, 0.62), 2.4)

        // Period numbers only when the lessons actually follow this bell schedule.
        let onGrid = all.filter { e in periods.contains { $0.s == Fmt.minutes(e.startTime) } }.count
        let vis = (!all.isEmpty && onGrid * 2 < all.count) ? [] : periods.filter { $0.e > mn && $0.s < mx }
        visiblePeriods = vis
        var set = Set<Int>()
        for p in vis { set.insert(p.s); set.insert(p.e) }
        for e in all { set.insert(Fmt.minutes(e.startTime)); set.insert(Fmt.minutes(e.endTime)) }
        boundaryTimes = set.filter { $0 >= mn - 2 && $0 <= mx + 2 }.sorted()
    }

    /// Data only; the closure is ignored so paging skips re-rendering unchanged weeks.
    static func == (l: WeekGrid, r: WeekGrid) -> Bool {
        l.size == r.size && l.todayNum == r.todayNum && l.dayNums == r.dayNums
            && l.dayEntries == r.dayEntries && l.dayLabels == r.dayLabels
    }

    private var colW: CGFloat { max(10, (size.width - gutter - edge * 2 - colGap * 6) / 6) }
    private var totalHeight: CGFloat { CGFloat(maxMins - minMins) * pxPerMin }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow.padding(.bottom, Spacing.sm)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let minute = Timetable.minuteNow(context.date)
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: colGap) {
                            timeAxis
                            ForEach(0..<6, id: \.self) { d in dayColumn(d, minute: minute) }
                        }
                        nowLine(minute).allowsHitTesting(false)
                    }
                    .frame(height: totalHeight, alignment: .topLeading)
                }
            }
            .padding(.horizontal, edge)
            .padding(.bottom, Spacing.xxxl)
        }
        .scrollIndicators(.hidden)
    }

    /// Week number and month in the corner above the axis; today's date on an accent disc.
    private var headerRow: some View {
        HStack(alignment: .bottom, spacing: colGap) {
            VStack(alignment: .leading, spacing: 1) {
                Text(weekLabel).textStyle(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1)
                Text(monthLabel).textStyle(TextStyle.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            .frame(width: gutter, alignment: .leading)
            .padding(.bottom, 2)
            ForEach(0..<6, id: \.self) { d in
                let isToday = dayNums[d] == todayNum
                VStack(spacing: 2) {
                    Text(dayLabels[d])
                        .textStyle(.caption2)
                        .foregroundStyle(isToday ? Palette.accentText : Palette.textTertiary)
                        .lineLimit(1)
                    Text(verbatim: "\(dayNumbers[d])")
                        .textStyle(TextStyle.caption.weight(.semibold))
                        .foregroundStyle(isToday ? Brand.onAccent : Palette.textPrimary)
                        .lineLimit(1)
                        .frame(width: 24, height: 24)
                        .background(isToday ? Brand.accent : .clear, in: .circle)
                }
                .frame(width: colW)
            }
        }
    }

    /// Clock times at the period edges, the period number in the band between them.
    private var timeAxis: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visiblePeriods, id: \.num) { p in
                Text(verbatim: "\(p.num).")
                    .textStyle(.timeAxisPeriod)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .frame(width: gutter - 6)
                    .offset(y: CGFloat((p.s + p.e) / 2 - minMins) * pxPerMin - 9)
            }
            ForEach(boundaryTimes, id: \.self) { m in
                Text(verbatim: Timetable.hhmm(m))
                    .textStyle(.timeAxisBoundary)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .frame(width: gutter - 6, alignment: .leading)
                    .offset(y: CGFloat(m - minMins) * pxPerMin - 6)
            }
        }
        .frame(width: gutter, height: totalHeight, alignment: .topLeading)
    }

    /// Today is marked in the header only; an empty Saturday draws nothing at all.
    private func dayColumn(_ d: Int, minute: Int) -> some View {
        let kind = dayKinds[d]
        return ZStack(alignment: .topLeading) {
            ForEach(boundaryTimes, id: \.self) { m in
                Rectangle()
                    .fill(Palette.separator.opacity(0.55))
                    .frame(width: colW, height: 1)
                    .offset(y: CGFloat(m - minMins) * pxPerMin)
            }
            if kind == .weekend {
                EmptyView()
            } else if kind != .normal {
                let first = daySlots[d].first
                let tappable = kind != .allCancelled && kind != .holiday
                SpecialDayCard(kind: kind, compact: true, plate: true, holidayKey: holidayKeys[d])
                    .frame(width: colW, height: max(0, totalHeight - 4))
                    .offset(y: 2)
                    .contentShape(.rect)
                    .onTapGesture {
                        if tappable, let first {
                            onTap(first, Timetable.tone(first.display, kind: first.kind, hues: hues))
                        }
                    }
            } else {
                ForEach(dayCells[d]) { cell in
                    cellView(cell, dayNum: dayNums[d], minute: minute)
                }
            }
        }
        .frame(width: colW, height: totalHeight, alignment: .topLeading)
    }

    private func cellView(_ cell: GridCell, dayNum: Int, minute: Int) -> some View {
        let top = CGFloat(cell.start - minMins) * pxPerMin
        let h = max(minCellHeight, CGFloat(cell.end - cell.start) * pxPerMin)
        // The seam comes off the leading edge, so the trailing lane stays flush.
        let left = colW * CGFloat(cell.lane) / CGFloat(GridCell.perMille) + (cell.lane > 0 ? 2 : 0)
        let right = colW * CGFloat(cell.lane + cell.span) / CGFloat(GridCell.perMille)
        let w = max(10, right - left)
        let past = dayNum < todayNum || (dayNum == todayNum && cell.end <= minute)
        return Button { onTap(cell.slot, cell.tone) } label: {
            GridLessonCell(cell: cell, width: w, height: h - 2, dense: cell.span < GridCell.perMille, past: past)
        }
        .buttonStyle(PressableStyle())
        .offset(x: left, y: top + 1)
    }

    /// A faint rule across the week at the current time, a strong one on today's column.
    @ViewBuilder
    private func nowLine(_ minute: Int) -> some View {
        if let today = dayNums.firstIndex(of: todayNum), minute >= minMins, minute <= maxMins {
            let y = CGFloat(minute - minMins) * pxPerMin - 0.75
            let gridStart = gutter + colGap
            Rectangle()
                .fill(Brand.accent.opacity(0.35))
                .frame(width: colW * 6 + colGap * 5, height: 1.5)
                .offset(x: gridStart, y: y)
            Rectangle()
                .fill(Brand.accent.opacity(0.9))
                .frame(width: colW, height: 1.5)
                .offset(x: gridStart + (colW + colGap) * CGFloat(today), y: y)
        }
    }
}

// ── Grid cell ───────────────────────────────────────────────────────────────

/// One soft pastel block. Only an outline means something: red cancelled, yellow exam.
/// A changed teacher or room is drawn as a filled chip on that field instead.
struct GridLessonCell: View {
    let cell: GridCell
    let width: CGFloat
    let height: CGFloat
    let dense: Bool
    let past: Bool
    @Environment(\.colorScheme) private var scheme

    enum PartMark { case plain, added, removed }

    private var entry: TimetableEntry { cell.entry }
    private var cancelled: Bool { cell.isCancelled }

    private var outline: Color? {
        let dark = scheme == .dark
        if cancelled { return Brand.danger.opacity(dark ? 0.85 : 0.60) }
        if entry.isExam || cell.kind == .exam { return Brand.warning.opacity(dark ? 0.95 : 0.80) }
        return nil
    }

    private var lineRoom: Int { height > 42 ? 2 : height > 28 ? 1 : 0 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
        let changes = Timetable.changes(entry)
        let secondary = [
            (Self.parts(entry.teacherName, original: entry.originalTeacher, changed: changes.teacher, dense: dense), TextStyle.gridCellTime),
            (Self.parts(entry.roomName, original: entry.originalRoom, changed: changes.room, dense: dense), TextStyle.gridCellRoom),
        ].filter { !$0.0.isEmpty }

        ZStack(alignment: .topLeading) {
            shape.fill(cell.tone.fill)
            // Below about 34pt a cell carries no text; the tint and ring already say enough.
            if width >= 34 {
                VStack(alignment: .leading, spacing: 1) {
                    line([(Timetable.subjectText(entry), changes.subject ? .added : .plain)],
                         style: .gridCellSubject, color: cell.tone.ink)
                    ForEach(Array(secondary.prefix(lineRoom).enumerated()), id: \.offset) { _, item in
                        line(item.0, style: item.1, color: cell.tone.ink.opacity(0.78))
                    }
                }
                .padding(.horizontal, dense ? 3 : 5)
                .padding(.vertical, 2.5)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(shape)
        .overlay {
            if let outline { shape.strokeBorder(outline, lineWidth: 1.5) }
        }
        .overlay {
            if past { pastShade(shape) }
        }
        .compositingGroup()
        .contentShape(shape)
    }

    /// Finished lessons keep a hint of their color and step back, like the web timetable.
    @ViewBuilder
    private func pastShade(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(Color(hex: 0x8A8F99).opacity(0.35)).blendMode(.color)
            if scheme == .dark {
                shape.fill(Color.black.opacity(0.5))
            } else {
                shape.fill(Color(hex: 0xC4CAD4)).blendMode(.multiply)
            }
        }
        .allowsHitTesting(false)
    }

    /// One line of a cell; a changed part becomes a solid chip, the one saturated block on the page.
    private func line(_ parts: [(String, PartMark)], style: TextStyle, color: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part.1 {
                case .plain:
                    Text(part.0)
                        .textStyle(style)
                        .foregroundStyle(color)
                        .strikethrough(cancelled)
                        .lineLimit(1)
                case .added, .removed:
                    Text(part.0)
                        .textStyle(style)
                        .foregroundStyle(Brand.onAccent)
                        .strikethrough(part.1 == .removed)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(part.1 == .added ? Brand.accent : Brand.danger, in: .pokyh(4))
                }
            }
        }
    }

    /// Splits a comma-joined field, changed parts first. A dense cell drops the unchanged ones.
    static func parts(_ joined: String, original: String?, changed: Bool, dense: Bool) -> [(String, PartMark)] {
        func split(_ s: String) -> [String] {
            s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let current = split(joined)
        let before = changed ? split(original ?? "") : []
        var out: [(String, PartMark)] = current.map { ($0, changed && !before.contains($0) ? .added : .plain) }
        out += before.filter { !current.contains($0) }.map { ($0, .removed) }
        let marked = out.filter { $0.1 != .plain }
        if dense && !marked.isEmpty { return marked }
        return marked + out.filter { $0.1 == .plain }
    }
}

// ── Day mode row ────────────────────────────────────────────────────────────

/// Same shape as Home's lesson row. For a substitution the lesson that happens leads and the
/// cancelled one becomes the "statt …" line under it.
struct DaySlotRow: View {
    let slot: MergedSlot
    let tone: Tone
    let action: () -> Void
    @Environment(\.strings) private var s

    private var shown: TimetableEntry { slot.replacement ?? slot.display }
    private var original: TimetableEntry? { slot.replacement != nil ? slot.display : nil }

    var body: some View {
        let changes = Timetable.changes(shown)
        TileRow(alignment: .top, action: action) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tone.bar)
                .frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(Timetable.subjectText(shown))
                        .textStyle(.headline)
                        .foregroundStyle(shown.isCancelled ? Brand.danger : Palette.textPrimary)
                        .strikethrough(shown.isCancelled)
                        .lineLimit(1)
                    badge
                }
                HStack(spacing: Spacing.xs) {
                    meta(shown.teacherName, changed: changes.teacher)
                    if !shown.teacherName.isEmpty && !shown.roomName.isEmpty {
                        Text(verbatim: "·").textStyle(.footnote).foregroundStyle(Palette.textTertiary)
                    }
                    meta(shown.roomName, changed: changes.room)
                }
                if let original {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text(s.timetable.insteadOf(Timetable.subjectText(original)))
                            .textStyle(.caption)
                            .strikethrough()
                    }
                    .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(Fmt.time(shown.startTime))\n\(Fmt.time(shown.endTime))")
                .textStyle(TextStyle.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func meta(_ text: String, changed: Bool) -> some View {
        if !text.isEmpty {
            if changed {
                Text(text)
                    .textStyle(.caption)
                    .foregroundStyle(Brand.onAccent)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 1)
                    .background(Brand.accent, in: .pokyh(Radius.xs))
            } else {
                Text(text).textStyle(.footnote).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        let d = slot.display
        if d.isCancelled && slot.replacement == nil { TagChip(s.timetable.cancelled, color: Brand.danger) }
        else if d.isExam { TagChip(s.timetable.exam, color: Brand.warning) }
        else if slot.kind == .replacement { TagChip(s.timetable.substitution, color: Brand.orange) }
        else if slot.kind == .event { TagChip(s.timetable.event, color: Brand.accent) }
    }
}

// ── Whole-day states ────────────────────────────────────────────────────────

/// Instead of a lesson list when a whole day has no normal lessons. As a plate it fills its day
/// in the day's own color, so the day reads as one block, like a cancelled lesson does.
struct SpecialDayCard: View {
    let kind: DayKind
    var compact: Bool
    var plate: Bool
    /// Which break a holiday is, so it carries its name ("Herbstferien") instead of just "Ferien".
    var holidayKey: String? = nil
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var scheme

    private var config: (color: Color, icon: String, title: String, subtitle: String) {
        let t = s.timetable
        switch kind {
        case .holiday:        return (Brand.orange, "beach.umbrella.fill", holidayKey.flatMap { t.holidayNames[$0] } ?? t.holiday, t.noLessons)
        case .weekend:        return (Brand.success, "sun.max.fill", t.weekend, t.free)
        case .allCancelled:   return (Brand.danger, "xmark.circle.fill", t.cancelled, t.allCancelled)
        case .allReplacement: return (Brand.accent, "arrow.left.arrow.right", t.substitution, t.allReplaced)
        case .fullDayEvent:   return (Brand.accent, "calendar", t.event, t.allDay)
        case .normal:         return (Brand.accent, "calendar", "", "")
        }
    }

    var body: some View {
        let c = config
        let dark = scheme == .dark
        VStack(spacing: compact ? Spacing.sm : Spacing.lg) {
            Image(systemName: c.icon)
                .font(.system(size: compact ? 15 : 32, weight: .semibold))
                .foregroundStyle(c.color)
                .frame(width: compact ? 30 : 72, height: compact ? 30 : 72)
                .background(c.color.opacity(0.14), in: .circle)
            Text(c.title)
                .textStyle(compact ? .caption : .title2)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            Text(c.subtitle)
                .textStyle(compact ? .caption2 : .callout)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .padding(compact ? Spacing.xs : Spacing.card)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: compact ? CGFloat.infinity : nil)
        .frame(height: compact ? nil : CGFloat(340))
        .background {
            if plate {
                let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                shape.fill(c.color.opacity(dark ? 0.20 : 0.12))
                    .overlay(shape.strokeBorder(c.color.opacity(dark ? 0.60 : 0.45), lineWidth: 1.5))
            }
        }
    }
}

/// A week without school, large, in the mood of the time of year.
struct HolidayWeek: View {
    let month: Int
    var holidayKey: String? = nil
    @Environment(\.strings) private var s

    private var symbol: String {
        switch month {
        case 12, 1, 2: "snowflake"
        case 3, 4, 5: "leaf.fill"
        case 6, 7, 8: "beach.umbrella.fill"
        default: "wind"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(Brand.orange)
                    .frame(width: 160, height: 160)
                    .background(Brand.orange.opacity(0.12), in: .circle)
                Text(holidayKey.flatMap { s.timetable.holidayNames[$0] } ?? s.timetable.holiday)
                    .textStyle(.largeTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, 28)
                Text(s.timetable.noLessons)
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Spacing.xs)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.huge)
        }
    }
}

/// Offline and nothing stored for this week: it could be holidays, saying so would be a guess.
struct OfflineWeekState: View {
    let retry: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        StateView(s.timetable.unknownTitle, message: s.timetable.offlineUnknown) {
            IconTile("wifi.slash", color: Brand.warning, size: 64)
        } actions: {
            Button(s.common.retry, action: retry).buttonStyle(.secondary(compact: true))
        }
    }
}

/// The week's counts in pills, on wide screens only.
struct WeekFigures: View {
    let entries: [TimetableEntry]
    let todayNum: Int
    @Environment(\.strings) private var s

    var body: some View {
        let t = s.timetable
        let todayActive = entries.filter { $0.date == todayNum && !$0.isCancelled }
        let todayLessons = Timetable.periods.filter { p in
            todayActive.contains { Fmt.minutes($0.startTime) <= p.s && Fmt.minutes($0.endTime) >= p.e }
        }.count
        let figures: [(Int, String, Color)] = [
            (todayLessons, "\(t.hoursUnit) · \(s.mensa.today)", Palette.textPrimary),
            (entries.filter(\.isCancelled).count, t.cancellations, Decorative.blush.ink),
            (entries.filter(\.isExam).count, t.examsLabel, Decorative.butter.ink),
            (entries.filter { $0.isSubstitution && !$0.isCancelled }.count, t.substitutions, Decorative.periwinkle.ink),
        ]
        HStack(spacing: Spacing.sm) {
            ForEach(Array(figures.enumerated()), id: \.offset) { _, f in
                let color = f.0 == 0 ? Palette.textTertiary : f.2
                HStack(spacing: 6) {
                    Text(verbatim: "\(f.0)").textStyle(TextStyle.callout.weight(.heavy))
                    Text(f.1).textStyle(.footnote)
                }
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Palette.card, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// ── Skeletons ───────────────────────────────────────────────────────────────

struct WeekGridSkeleton: View {
    let size: CGSize

    // (start, height) per column, as fractions of the column.
    private static let pattern: [[(CGFloat, CGFloat)]] = [
        [(0.00, 0.18), (0.20, 0.26), (0.52, 0.16)],
        [(0.00, 0.26), (0.30, 0.18), (0.54, 0.28)],
        [(0.06, 0.20), (0.30, 0.34)],
        [(0.00, 0.16), (0.18, 0.22), (0.44, 0.30)],
        [(0.10, 0.30), (0.46, 0.18)],
        [(0.00, 0.22)],
    ]

    var body: some View {
        let gap: CGFloat = 3
        let colW = max(10, (size.width - Spacing.md * 2 - 36 - gap * 6) / 6)
        let height = max(200, size.height - 96)
        VStack(spacing: Spacing.md) {
            HStack(spacing: gap) {
                Color.clear.frame(width: 36, height: 1)
                ForEach(0..<6, id: \.self) { _ in
                    VStack(spacing: Spacing.xs) {
                        PokyhDesign.SkeletonBlock(height: 12).frame(width: 18)
                        PokyhDesign.SkeletonBlock(height: 22, radius: 11).frame(width: 22)
                    }
                    .frame(width: colW)
                }
            }
            HStack(alignment: .top, spacing: gap) {
                Color.clear.frame(width: 36, height: 1)
                ForEach(0..<6, id: \.self) { d in
                    ZStack(alignment: .top) {
                        ForEach(Array(Self.pattern[d].enumerated()), id: \.offset) { _, block in
                            PokyhDesign.SkeletonBlock(height: height * block.1, radius: Radius.xs)
                                .offset(y: height * block.0)
                        }
                    }
                    .frame(width: colW, height: height, alignment: .top)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Bar, two text lines and a value, as many rows as asked for.
struct TileRowSkeleton: View {
    var rows = 3

    var body: some View {
        VStack(spacing: Spacing.rowGap) {
            ForEach(0..<rows, id: \.self) { _ in
                TileRow {
                    PokyhDesign.SkeletonBlock(height: 40, radius: 2).frame(width: 4)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        PokyhDesign.SkeletonBlock(height: 14).frame(width: 140)
                        PokyhDesign.SkeletonBlock(height: 11).frame(width: 90)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PokyhDesign.SkeletonBlock(height: 16).frame(width: 40)
                }
            }
        }
    }
}

// ── Lesson detail ───────────────────────────────────────────────────────────

/// Built like a screen: the sheet is the canvas and everything on it a card, so the hero and
/// the lists separate by the same tone step as everywhere else.
struct LessonDetailView: View {
    let item: LessonDetailItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s

    private var slot: MergedSlot { item.slot }
    private var tone: Tone { item.tone }
    private var d: TimetableEntry { slot.display }

    private static let headerHeight: CGFloat = 148
    private static let tileSize: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                hero
                detailsCard
                if let other = slot.replacement { insteadCard(other) }
                if d.isExam, let desc = d.examDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    sectionCard(s.timetable.examContent, desc)
                }
                if let note = d.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    sectionCard(s.timetable.note, note)
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: WidthClass.readableMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Palette.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.bg)
        .presentationCornerRadius(Radius.xxl)
    }

    private var headerName: String {
        d.subjectLong.isEmpty ? (d.subjectName.isEmpty ? (d.note ?? s.timetable.lesson) : d.subjectName) : d.subjectLong
    }

    private var tags: [(String, Color)] {
        let t = s.timetable
        var out: [(String, Color)] = []
        if d.isCancelled { out.append((t.cancelled, Brand.danger)) }
        if slot.kind == .replacement { out.append((t.substitution, Brand.orange)) }
        if d.isExam { out.append((t.exam, Brand.warning)) }
        if d.isSubstitution && !d.isCancelled && slot.kind != .replacement { out.append((t.substitution, Brand.orange)) }
        if slot.kind == .event { out.append((t.event, Brand.accent)) }
        return out
    }

    private var dayLine: String {
        guard let date = Timetable.date(d.date) else { return "" }
        let cal = Calendar.current
        let weekday = s.common.weekdays[Timetable.weekdayIndex(date)]
        let day = s.common.dayMonth(cal.component(.day, from: date), cal.component(.month, from: date))
        return "\(weekday.prefix(1).uppercased())\(weekday.dropFirst()), \(day)"
    }

    private var hero: some View {
        BleedCard {
            ZStack {
                tone.fill
                // Two letters of the subject, oversized and quiet, where Android shows its photo.
                Text(String(headerName.trimmingCharacters(in: .whitespaces).prefix(2)).uppercased())
                    .textStyle(.numeral(72))
                    .foregroundStyle(tone.ink.opacity(0.30))
                    .lineLimit(1)
            }
            .frame(height: Self.headerHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 34, height: 34)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(s.common.close)
                .padding(Spacing.md)
            }
            .overlay(alignment: .bottomLeading) {
                if !tags.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                            TagChip(tag.0, color: tag.1, large: true)
                                .background(Palette.card, in: .capsule)
                        }
                    }
                    .padding(Spacing.md)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(headerName)
                    .textStyle(.title2)
                    .foregroundStyle(Palette.textPrimary)
                    .strikethrough(d.isCancelled && slot.replacement == nil)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if !d.subjectName.isEmpty, d.subjectName.lowercased() != headerName.lowercased() {
                    Text(d.subjectName).textStyle(.subheadline).foregroundStyle(Palette.textSecondary)
                }
                if !dayLine.isEmpty {
                    Text(dayLine)
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, Spacing.xs)
                }
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "clock").font(.system(size: 12, weight: .semibold))
                    Text(verbatim: "\(Fmt.time(d.startTime)) – \(Fmt.time(d.endTime))")
                        .textStyle(.footnote)
                        .monospacedDigit()
                }
                .foregroundStyle(tone.ink)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(tone.fill, in: .capsule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.card)
        }
    }

    @ViewBuilder
    private var detailsCard: some View {
        let teacher = d.teacherLongName ?? d.teacherName
        let origTeacher = d.originalTeacherLong ?? (d.originalTeacher ?? "")
        let room = d.roomName, origRoom = d.originalRoom ?? ""
        let hasTeacher = !teacher.isEmpty || !origTeacher.isEmpty
        let hasRoom = !room.isEmpty || !origRoom.isEmpty
        if hasTeacher || hasRoom {
            PokyhCard(padding: 0) {
                if hasTeacher {
                    if !origTeacher.isEmpty && origTeacher != teacher && !teacher.isEmpty {
                        changeRow(s.timetable.teacher, from: origTeacher, to: teacher, icon: "person.fill")
                    } else {
                        detailRow(s.timetable.teacher, teacher.isEmpty ? origTeacher : teacher, icon: "person.fill")
                    }
                }
                if hasRoom {
                    if hasTeacher { RowSeparator(inset: Spacing.card + Self.tileSize + Spacing.iconText) }
                    if !origRoom.isEmpty && origRoom != room && !room.isEmpty {
                        changeRow(s.timetable.room, from: origRoom, to: room, icon: "mappin.and.ellipse")
                    } else {
                        detailRow(s.timetable.room, room.isEmpty ? origRoom : room, icon: "mappin.and.ellipse")
                    }
                }
            }
        }
    }

    /// The row's glyph on the subject's pastel, so the list belongs to the lesson.
    private func tile(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tone.ink)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .background(tone.fill, in: .pokyh(Radius.sm))
    }

    private func detailRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: Spacing.iconText) {
            tile(icon)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                EyebrowLabel(label)
                Text(value).textStyle(.body).foregroundStyle(Palette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
    }

    /// Old and new on their own lines, so two full names never wrap mid-name.
    private func changeRow(_ label: String, from: String, to: String, icon: String) -> some View {
        HStack(spacing: Spacing.iconText) {
            tile(icon)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                EyebrowLabel(label)
                Text(from).textStyle(.body).foregroundStyle(Brand.danger).strikethrough()
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                    Text(to).textStyle(.body).foregroundStyle(Brand.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
    }

    /// The other half of a substitution, whichever half was tapped.
    private func insteadCard(_ other: TimetableEntry) -> some View {
        let cancelled = other.isCancelled
        let meta = [other.teacherName, other.roomName].filter { !$0.isEmpty }.joined(separator: " · ")
        return PokyhCard {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                EyebrowLabel(cancelled ? s.timetable.insteadShort : s.timetable.instead)
            }
            Text(other.subjectLong.isEmpty ? Timetable.subjectText(other) : other.subjectLong)
                .textStyle(.headline)
                .foregroundStyle(cancelled ? Palette.textTertiary : Palette.textPrimary)
                .strikethrough(cancelled)
                .lineLimit(2)
                .padding(.top, Spacing.sm)
            if !meta.isEmpty {
                Text(meta).textStyle(.footnote).foregroundStyle(Palette.textSecondary).padding(.top, Spacing.xxs)
            }
        }
    }

    private func sectionCard(_ title: String, _ body: String) -> some View {
        PokyhCard {
            EyebrowLabel(title)
            Text(body)
                .textStyle(.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .padding(.top, Spacing.sm)
        }
    }
}

// ── Previews ────────────────────────────────────────────────────────────────

#if DEBUG
private enum TimetablePreviewData {
    static func entry(_ id: Int, day: Int, _ start: Int, _ end: Int, _ subject: String, teacher: String = "MÜL",
                      room: String = "2.05", cancelled: Bool = false, exam: Bool = false,
                      originalRoom: String? = nil) -> TimetableEntry {
        TimetableEntry(id: id, lessonId: id, date: day, startTime: start, endTime: end, subjectName: subject,
                       subjectLong: subject, teacherName: teacher, teacherLongName: nil, roomName: room,
                       isExam: exam, isCancelled: cancelled, isSubstitution: originalRoom != nil, isAdditional: false,
                       originalSubject: nil, originalSubjectLong: nil, originalTeacher: nil, originalTeacherLong: nil,
                       originalRoom: originalRoom, note: nil, examDescription: exam ? "Kapitel 3 und 4" : nil)
    }

    static let week: [[TimetableEntry]] = {
        let base = 20261102
        return (0..<6).map { d in
            guard d < 5 else { return [] }
            return [
                entry(d * 10 + 1, day: base + d, 750, 840, ["D", "M", "IT", "ENGL", "R"][d]),
                entry(d * 10 + 2, day: base + d, 840, 930, ["M", "ENGL", "D", "IT", "Bew.Sport"][d], exam: d == 2),
                entry(d * 10 + 3, day: base + d, 945, 1035, ["IT", "R", "M", "D", "ENGL"][d], cancelled: d == 1),
                entry(d * 10 + 4, day: base + d, 1035, 1125, ["ENGL", "D", "R", "M", "IT"][d], originalRoom: d == 3 ? "1.12" : nil),
            ]
        }
    }()
}

#Preview("Week grid") {
    GeometryReader { geo in
        WeekGrid(dayEntries: TimetablePreviewData.week, dayLabels: ["Mo", "Di", "Mi", "Do", "Fr", "Sa"],
                 dayNumbers: [2, 3, 4, 5, 6, 7], weekLabel: "KW 45", monthLabel: "Nov.",
                 todayNum: 20261104, dayNums: (0..<6).map { 20261102 + $0 }, size: geo.size, onTap: { _, _ in })
    }
    .background(Palette.bg)
}

#Preview("Lesson detail") {
    let e = TimetablePreviewData.week[2][1]
    Color.clear.sheet(isPresented: .constant(true)) {
        LessonDetailView(item: LessonDetailItem(slot: MergedSlot(display: e, replacement: nil, kind: .exam), tone: .exam))
    }
}
#endif
