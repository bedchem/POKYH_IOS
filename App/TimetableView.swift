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
        return Changes(
            subject: FieldChanges.changed(current: e.subjectName, original: e.originalSubject, added: e.addedSubjects ?? []),
            teacher: FieldChanges.changed(current: e.teacherName, original: e.originalTeacher, added: e.addedTeachers ?? []),
            room: FieldChanges.changed(current: e.roomName, original: e.originalRoom, added: e.addedRooms ?? [])
        )
    }

    /// The absence behind a lesson, as of now. Nobody is absent from a lesson that doesn't happen.
    static func absence(of e: TimetableEntry, in absences: [AbsenceEntry]) -> LessonAbsence<AbsenceEntry>? {
        guard !e.isCancelled else { return nil }
        return AbsenceMarks.lessonAbsence(absences, date: e.date, start: Fmt.minutes(e.startTime), end: Fmt.minutes(e.endTime),
                                          nowDate: SchoolDates.todayNum(), nowMinute: minuteNow())
    }

    /// What an empty week is called. Another timetable's only counts as a break when the school
    /// has the whole week off: a room nobody uses this week isn't on holiday.
    static func emptyWeekName(_ days: [Int], holidays: [SchoolHoliday], names: [String: String], source: TimetableSource?) -> String? {
        SchoolHolidays.name(ofDays: days, in: holidays, names: names, atLeast: source == nil ? 1 : 5)
    }

    /// The school year (from 1 September) a YYYYMMDD day belongs to.
    static func schoolYear(ofDay day: Int) -> Int {
        day / 100 % 100 >= 9 ? day / 10000 : day / 10000 - 1
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
    /// The timetable it was tapped in, when that isn't the own one.
    var source: TimetableSource? = nil
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

// ── Holidays ────────────────────────────────────────────────────────────────

extension SchoolHolidays {
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

/// The backend's subject photos. They go through the API client because the route only takes its
/// key as a header, and they're sealed on disk like everything else, so they show offline too.
enum SubjectPhotos {
    private static let keysLifetime: TimeInterval = 6 * 60 * 60
    private static let keysFile = "subject-image-keys"
    private static var keys: Set<String>?
    private static var keysLoaded: Date?
    private static var reported = false

    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40
        return cache
    }()

    private static func file(_ key: String) -> String { "subject-image-\(key)" }

    /// The subjects there's a photo of. The backend has no placeholder, so nothing else is asked for.
    static func availableKeys() async -> Set<String> {
        if let keys, let keysLoaded, Date().timeIntervalSince(keysLoaded) < keysLifetime { return keys }
        if let data = try? await BackendClient.shared.request(TimetableRoutes.subjectImages, token: nil) {
            let fresh = SubjectImageKeys.read(data)
            keys = fresh
            keysLoaded = Date()
            DiskCache.save(Array(fresh), key: keysFile)
            return fresh
        }
        return keys ?? Set(DiskCache.load([String].self, key: keysFile) ?? [])
    }

    /// nil without a photo; the sheet then keeps the subject's monogram.
    static func image(long: String, short: String) async -> UIImage? {
        let key = SubjectImageKeys.key(long: long, short: short)
        guard !key.isEmpty else { return nil }
        if let image = memory.object(forKey: key as NSString) { return image }
        if let data = DiskCache.load(Data.self, key: file(key)), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            // Shows at once; a photo replaced on the backend arrives with the next launch.
            Task { _ = await download(key) }
            return image
        }
        return await download(key)
    }

    private static func download(_ key: String) async -> UIImage? {
        guard await availableKeys().contains(key),
              let data = try? await BackendClient.shared.request(SubjectImageKeys.path(for: key), token: nil),
              let image = UIImage(data: data) else { return nil }
        DiskCache.save(data, key: file(key))
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    /// Tells the backend once per launch which subjects there are, so it can make the missing
    /// photos. A hint, nothing waits for it.
    static func report(_ entries: [TimetableEntry], token: String?) {
        guard !reported, let token else { return }
        let rows = SubjectImageKeys.report(entries.map { (short: $0.subjectName, long: $0.subjectLong) })
        guard !rows.isEmpty else { return }
        reported = true
        Task {
            _ = try? await BackendClient.shared.request(TimetableRoutes.subjectImages + "/report", method: "POST", token: token, body: ["subjects": rows])
            keysLoaded = nil
        }
    }
}

extension LessonMark {
    var symbol: String {
        switch self {
        case .homework: "backpack"
        case .exam: "list.clipboard"
        case .attachment: "paperclip"
        case .substitution: "arrow.left.arrow.right"
        case .online: "bolt"
        case .classRegister: "book.closed"
        case .note: "doc.text"
        case .unknown: "info.circle"
        }
    }
}

extension TimetableKind {
    var symbol: String {
        switch self {
        case .klass: "person.3.fill"
        case .teacher: "person.fill"
        case .room: "mappin.and.ellipse"
        }
    }

    func label(_ t: TimetableStrings) -> String {
        switch self {
        case .klass: t.kindClass
        case .teacher: t.kindTeacher
        case .room: t.kindRoom
        }
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
    /// Another timetable shown instead of the own one; nil is the own.
    @State private var source: TimetableSource?
    @State private var pickingSource = false
    @State private var holidays: [SchoolHoliday] = []
    @State private var absencesByYear: [Int: [AbsenceEntry]] = [:]
    /// School years whose whole list came in since the screen opened.
    @State private var freshYears: Set<Int> = []
    @Environment(\.scenePhase) private var scenePhase

    enum Mode: CaseIterable { case week, day }

    private struct WeekKey: Hashable {
        let offset: Int
        let source: TimetableSource?
    }

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

    /// Another timetable shows nobody's absences.
    private func absences(ofWeek offset: Int) -> [AbsenceEntry] {
        source == nil ? absencesByYear[schoolYear(of: offset)] ?? [] : []
    }

    var body: some View {
        // A sheet's closure gets the last value `body` itself read, and week mode only reads this
        // inside the GeometryReader. Read here, absences reach the sheet, also while it's up.
        let absenceLists = absencesByYear
        VStack(spacing: 0) {
            if let source {
                HStack {
                    TimetableSourceChip(source: source, open: { pickingSource = true }, clear: { choose(nil) })
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.top, Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
        .task(id: WeekKey(offset: weekOffset, source: source)) { await load() }
        // The week's absences land with its lessons, the rest of the school year behind them.
        .task(id: source == nil ? weekOffset : nil) { await loadAbsences() }
        .task { await loadHolidays() }
        .onAppear { if !takeJump() { selectInitialDay() } }
        .onChange(of: app.timetableHomeSignal) {
            withAnimation(.snappy(duration: 0.3)) { weekOffset = 0; selectInitialDay() }
            reloadAbsences()
        }
        // An absence excused in the meantime stops showing as unexcused.
        .onChange(of: scenePhase) { _, phase in if phase == .active { reloadAbsences() } }
        .onChange(of: TimetableJump.shared.day) { _ = takeJump() }
        .sheet(item: $detail) { item in
            LessonDetailView(item: item, absences: item.source == nil
                ? absenceLists[Timetable.schoolYear(ofDay: item.slot.display.date)] ?? []
                : [])
        }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $pickingSource) {
            OtherTimetablesSheet(source: source, pick: choose)
        }
        .animation(Motion.standardEase, value: source)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { exportWeek() } label: {
                        Label(s.timetable.exportWeek, systemImage: "calendar")
                    }
                    if source == nil {
                        Button { Task { await exportExams() } } label: {
                            Label(s.timetable.exportExams, systemImage: "graduationcap")
                        }
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
            Divider()
            Button { pickingSource = true } label: {
                Label(s.timetable.otherTimetables, systemImage: "person.2")
            }
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
                                              source: source,
                                              absences: absences(ofWeek: off),
                                              holidays: holidays,
                                              onTap: { detail = LessonDetailItem(slot: $0, tone: $1, source: source) })
                                .containerRelativeFrame(.horizontal)
                                .id(off)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: scrollWeekBinding, anchor: .center)
                // Every page belongs to one timetable; another one starts over.
                .id(source)
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
        if let source { return UntisClient.shared.cachedTimetable(source: source, date: DateFmt.isoString(m), session) }
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
            let name = Timetable.emptyWeekName((0..<6).map(dayNum), holidays: holidays, names: s.timetable.holidayNames, source: source)
            if source != nil, name == nil {
                InlineNotice(s.timetable.noLessons, symbol: "checkmark.circle.fill", tint: Brand.success)
            } else {
                SpecialDayCard(kind: .holiday, compact: false, plate: true, holidayKey: SchoolHolidays.weekKey(monday), holidayName: name)
            }
        } else {
            let slots = Timetable.buildSlots(de)
            let kind = Timetable.dayKind(de, slots: slots, hasOtherDayEntries: anyDayHasEntries, index: selectedDay)
            let hues = Timetable.hues(for: entries)
            let holidayName = SchoolHolidays.name(onDay: dayNum(selectedDay), in: holidays, names: s.timetable.holidayNames)
            // A teacher or room without lessons on a day is no holiday, unless the school says so.
            if kind == .weekend || (kind == .holiday && source != nil && holidayName == nil) {
                // An empty Saturday is the absence of a timetable, not an entry in it.
                InlineNotice(s.timetable.noLessons, symbol: "checkmark.circle.fill", tint: Brand.success)
            } else if kind != .normal {
                let tappable = kind != .allCancelled && kind != .holiday
                SpecialDayCard(kind: kind, compact: false, plate: true,
                               holidayKey: kind == .holiday ? holidayKey(selectedDay) : nil,
                               holidayName: kind == .holiday ? holidayName : nil)
                    .contentShape(.rect)
                    .onTapGesture {
                        if tappable, let first = slots.first {
                            detail = LessonDetailItem(slot: first, tone: Timetable.tone(first.display, kind: first.kind, hues: hues), source: source)
                        }
                    }
            } else {
                let weekAbsences = absences(ofWeek: weekOffset)
                LazyVStack(spacing: Spacing.rowGap) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { idx, slot in
                        let shown = slot.replacement ?? slot.display
                        let tone = Timetable.tone(shown, kind: slot.replacement == nil ? slot.kind : .replacement, hues: hues)
                        DaySlotRow(slot: slot, tone: tone, absenceMark: Timetable.absence(of: shown, in: weekAbsences)?.mark) {
                            detail = LessonDetailItem(slot: slot, tone: tone, source: source)
                        }
                        .fadeIn(delay: Double(idx) * 0.03)
                    }
                }
            }
        }
    }

    /// The break a free weekday of the shown week belongs to, named by when it is.
    private func holidayKey(_ day: Int) -> String? {
        let nums = (0..<6).map(dayNum)
        let kinds = (0..<6).map { Timetable.dayKind(entriesFor($0), hasOtherDayEntries: anyDayHasEntries, index: $0) }
        return SchoolHolidays.dayKeys(dayNums: nums, kinds: kinds)[day]
    }

    private func selectInitialDay() {
        let today = SchoolDates.todayNum()
        selectedDay = (0..<6).first(where: { dayNum($0) == today }) ?? 0
    }

    private func week(_ iso: String, _ session: UserSession) async throws -> [TimetableEntry] {
        if let source { return try await UntisClient.shared.timetable(source: source, date: iso, session) }
        return try await UntisClient.shared.timetable(date: iso, session)
    }

    /// Another timetable, or with nil the own one again, from the same week on.
    private func choose(_ next: TimetableSource?) {
        pickingSource = false
        guard next != source else { return }
        source = next
        entries = []
        loading = true
        error = nil
    }

    private func load() async {
        guard let session = app.session else { return }
        guard session.hasUntis else { loading = false; return }
        let shown = source
        loading = true; error = nil
        do {
            let fresh = try await week(DateFmt.isoString(monday), session)
            // An answer for a timetable no longer shown is dropped.
            guard shown == source else { return }
            entries = fresh
            // Only the own timetable feeds the rest of the app.
            if shown == nil {
                WatchSync.timetable(entries, week: DateFmt.isoString(monday), for: session)
                SubjectPhotos.report(entries, token: session.apiToken)
                // This week of the default account feeds the widget and the Live Activity.
                if weekOffset == 0, app.isDefaultAccountActive {
                    WidgetBridge.publish(entries); app.refreshLiveActivity(from: entries)
                }
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
            Task { _ = try? await week(iso, session) }
        }
    }

    private func loadHolidays() async {
        guard let session = app.session, session.hasUntis else { return }
        holidays = UntisClient.shared.storedHolidays(session)
        holidays = await UntisClient.shared.refreshedHolidays(session)
    }

    /// The stored list first, then the shown week on its own (a school year walks page by page and
    /// would leave the grid without its overlay for a while), then the whole year behind it.
    private func loadAbsences() async {
        guard source == nil, let session = app.session, session.hasUntis else { return }
        let year = schoolYear(of: weekOffset)
        if absencesByYear[year] == nil, let stored = UntisClient.shared.storedAbsences(year: year, session) {
            absencesByYear[year] = stored
        }
        let from = DateFmt.compact.string(from: monday), to = DateFmt.compact.string(from: dayDate(5))
        if let week = try? await UntisClient.shared.absences(startDate: from, endDate: to, session), !Task.isCancelled {
            var merged = Dictionary((absencesByYear[year] ?? []).map { ($0.id, $0) }) { _, new in new }
            for absence in week { merged[absence.id] = absence }
            absencesByYear[year] = Array(merged.values)
        }
        guard !freshYears.contains(year) else { return }
        if let all = try? await UntisClient.shared.schoolYearAbsences(year: year, session), !Task.isCancelled {
            absencesByYear[year] = all
            freshYears.insert(year)
        }
    }

    private func reloadAbsences() {
        freshYears = []
        Task { await loadAbsences() }
    }
}

/// Whose timetable is shown when it isn't the own one; the cross goes back to the own.
struct TimetableSourceChip: View {
    let source: TimetableSource
    let open: () -> Void
    let clear: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        let tone = Decorative.periwinkle
        HStack(spacing: 6) {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: source.kind.symbol).font(.system(size: 13, weight: .semibold))
                    Text(source.name).textStyle(TextStyle.footnote.weight(.bold)).lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(s.timetable.otherTimetables)
            Button(action: clear) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.timetable.myTimetable)
        }
        .foregroundStyle(tone.ink)
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .background(tone.fill, in: .capsule)
    }
}

/// The classes, teachers and rooms whose timetable the school shows this account, as WebUntis
/// lists them (often only some kinds, or only the own class), and the way back to the own one.
struct OtherTimetablesSheet: View {
    let source: TimetableSource?
    let pick: (TimetableSource?) -> Void
    @EnvironmentObject private var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var kind: TimetableKind
    @State private var lists: [TimetableKind: [TimetableResource]] = [:]
    @State private var failed: Set<TimetableKind> = []

    init(source: TimetableSource?, pick: @escaping (TimetableSource?) -> Void) {
        self.source = source
        self.pick = pick
        _kind = State(initialValue: source?.kind ?? .klass)
    }

    var body: some View {
        NavigationStack {
            OtherTimetablesList(source: source, kind: $kind, list: lists[kind], failed: failed.contains(kind), pick: pick) {
                Task { await load(kind, force: true) }
            }
            .navigationTitle(s.timetable.otherTimetables)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.bg)
        .presentationCornerRadius(Radius.xxl)
        .task(id: kind) { await load(kind) }
    }

    private func load(_ kind: TimetableKind, force: Bool = false) async {
        guard force || lists[kind] == nil, let session = app.session else { return }
        failed.remove(kind)
        lists[kind] = nil
        do {
            lists[kind] = try await UntisClient.shared.timetableFilters(kind, session)
        } catch let e as AppError where e.isSessionExpired {
            app.handleSessionExpired()
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failed.insert(kind) }
        }
    }
}

/// The sheet's content, without the loading.
struct OtherTimetablesList: View {
    let source: TimetableSource?
    @Binding var kind: TimetableKind
    /// nil while it loads.
    let list: [TimetableResource]?
    let failed: Bool
    let pick: (TimetableSource?) -> Void
    let retry: () -> Void
    @Environment(\.strings) private var s
    @State private var query = ""

    /// Below this a search field would only be in the way.
    private static let searchFrom = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ownRow
                PokyhSegmentedControl(TimetableKind.allCases, selection: $kind) { $0.label(s.timetable) }
                if (list?.count ?? 0) > Self.searchFrom {
                    PokyhTextField(placeholder: s.timetable.otherSearch, text: $query, symbol: "magnifyingglass")
                }
                content
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: WidthClass.readableMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg.ignoresSafeArea())
        .onChange(of: kind) { query = "" }
    }

    private var ownRow: some View {
        Button { pick(nil) } label: {
            HStack(spacing: Spacing.iconText) {
                Image(systemName: "person.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Decorative.periwinkle.ink)
                    .frame(width: 40, height: 40)
                    .background(Decorative.periwinkle.fill, in: .circle)
                Text(s.timetable.myTimetable)
                    .textStyle(TextStyle.callout.weight(.bold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: source == nil ? "checkmark" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(source == nil ? Palette.accentText : Palette.textTertiary)
            }
            .padding(Spacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(.rowPress(radius: Radius.lg))
        .background(source == nil ? Brand.accent.opacity(0.10) : Palette.card, in: .pokyh(Radius.lg))
    }

    @ViewBuilder
    private var content: some View {
        if failed {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(s.timetable.otherFailed)
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .foregroundStyle(Brand.danger)
                Button(s.common.retry, action: retry).buttonStyle(.secondary(compact: true))
            }
            .padding(.vertical, Spacing.sm)
        } else if let list {
            let shown = list.filter { $0.matches(query) }
            if shown.isEmpty {
                Text(s.timetable.otherNone)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.xl)
            } else {
                ListCard(shown) { row($0) }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxxl)
        }
    }

    private func row(_ resource: TimetableResource) -> some View {
        let active = source?.kind == kind && source?.id == resource.id
        return Button { pick(TimetableSource(kind: kind, id: resource.id, name: resource.name)) } label: {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(resource.name)
                        .textStyle(TextStyle.callout.weight(.bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    if !resource.longName.isEmpty, resource.longName != resource.name {
                        Text(resource.longName)
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: active ? "checkmark" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? Palette.accentText : Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.card)
            .padding(.vertical, Spacing.md)
            .contentShape(.rect)
        }
        .buttonStyle(.rowPress)
        .background(active ? Brand.accent.opacity(0.10) : .clear)
    }
}

// ── One week page ───────────────────────────────────────────────────────────

struct WeekTimetablePage: View {
    let weekOffset: Int
    let size: CGSize
    let source: TimetableSource?
    let absences: [AbsenceEntry]
    let holidays: [SchoolHoliday]
    let onTap: (MergedSlot, Tone) -> Void
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var entries: [TimetableEntry]
    @State private var loading: Bool
    @State private var error: String?

    /// Starts from the prefetch cache when it can; `.task` then revalidates quietly.
    init(weekOffset: Int, size: CGSize, initialEntries: [TimetableEntry]?, source: TimetableSource? = nil,
         absences: [AbsenceEntry] = [], holidays: [SchoolHoliday] = [], onTap: @escaping (MergedSlot, Tone) -> Void) {
        self.weekOffset = weekOffset
        self.size = size
        self.source = source
        self.absences = absences
        self.holidays = holidays
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
                let name = Timetable.emptyWeekName((0..<6).map(dayNum), holidays: holidays, names: s.timetable.holidayNames, source: source)
                if source != nil, name == nil {
                    StateView(s.timetable.noLessons, art: { IconTile("calendar", color: Brand.accent, size: 64) })
                } else {
                    HolidayWeek(month: Calendar.current.component(.month, from: monday),
                                holidayKey: SchoolHolidays.weekKey(monday), name: name)
                }
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
                    absences: absences.filter { $0.endDate >= nums[0] && $0.startDate <= nums[5] },
                    holidayTitles: nums.map { SchoolHolidays.name(onDay: $0, in: holidays, names: s.timetable.holidayNames) },
                    guessesHolidays: source == nil,
                    onTap: onTap
                )
                .equatable()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let session = app.session else { return }
        guard session.hasUntis else { loading = false; return }
        loading = entries.isEmpty
        error = nil
        do {
            if let source {
                entries = try await UntisClient.shared.timetable(source: source, date: DateFmt.isoString(monday), session)
            } else {
                entries = try await UntisClient.shared.timetable(date: DateFmt.isoString(monday), session)
            }
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
    let absences: [AbsenceEntry]
    /// The school's own name for each day's break, where it falls in one.
    let holidayTitles: [String?]
    let onTap: (MergedSlot, Tone) -> Void

    private let gutter: CGFloat = 42
    private let colGap: CGFloat = 3
    private let edge: CGFloat = 6
    private let headerRoom: CGFloat = 64
    private let minCellHeight: CGFloat = 26
    /// Below this an absence's label takes its short form.
    private let narrowColumn: CGFloat = 110

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
         monthLabel: String, todayNum: Int, dayNums: [Int], size: CGSize, absences: [AbsenceEntry] = [],
         holidayTitles: [String?] = [], guessesHolidays: Bool = true, onTap: @escaping (MergedSlot, Tone) -> Void) {
        self.dayEntries = dayEntries
        self.dayLabels = dayLabels
        self.dayNumbers = dayNumbers
        self.weekLabel = weekLabel
        self.monthLabel = monthLabel
        self.todayNum = todayNum
        self.dayNums = dayNums
        self.size = size
        self.absences = absences
        self.holidayTitles = holidayTitles
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
            var kind = Timetable.dayKind(entries, slots: s, hasOtherDayEntries: anyDay, index: d)
            // A teacher or room without lessons on a day is no holiday, unless the school says so.
            if kind == .holiday, !guessesHolidays, (holidayTitles.indices.contains(d) ? holidayTitles[d] : nil) == nil { kind = .normal }
            kinds.append(kind)
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
            && l.absences == r.absences && l.holidayTitles == r.holidayTitles
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
                SpecialDayCard(kind: kind, compact: true, plate: true, holidayKey: holidayKeys[d],
                               holidayName: holidayTitles.indices.contains(d) ? holidayTitles[d] : nil)
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
                ForEach(Array(absenceBands(d, minute: minute).enumerated()), id: \.offset) { _, band in
                    AbsenceOverlay(mark: band.mark, narrow: colW < narrowColumn)
                        .frame(width: colW, height: max(0, CGFloat(band.endMinute - band.startMinute) * pxPerMin))
                        .offset(y: CGFloat(band.startMinute - minMins) * pxPerMin)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: colW, height: totalHeight, alignment: .topLeading)
    }

    private func absenceBands(_ d: Int, minute: Int) -> [AbsenceBand] {
        guard !absences.isEmpty else { return [] }
        let lessons = dayCells[d].filter { !$0.isCancelled }.map { (start: $0.start, end: $0.end) }
        return AbsenceMarks.bands(absences, date: dayNums[d], lessons: lessons, nowDate: todayNum, nowMinute: minute)
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

// ── Absence overlay ─────────────────────────────────────────────────────────

/// One translucent block over the column, from exactly where the absence starts to where it ends,
/// the way WebUntis marks it. Only the text color says which. A tap goes through to the lesson.
struct AbsenceOverlay: View {
    let mark: AbsenceMark
    let narrow: Bool
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
        let ink: Color = mark == .absent
            ? Color(hex: dark ? 0xEF4444 : 0xB91C1C)
            : Color(hex: dark ? 0x22C55E : 0x15803D)
        Text(narrow ? s.timetable.shortLabel(mark) : s.timetable.label(mark))
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(dark ? Color(hex: 0x14171D, opacity: 0.88) : Color(hex: 0xCBD5E1, opacity: 0.90)))
            // A hairline of light along the edge: a dark outline on a dark block can't be seen.
            .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.24) : Color(hex: 0x64748B, opacity: 0.55), lineWidth: 1.5))
            .accessibilityLabel(s.timetable.label(mark))
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

    /// The corner of a small cell isn't a list; the sheet shows them all.
    private static let maxMarks = 2

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
            (parts(entry.teacherName, added: entry.addedTeachers, original: entry.originalTeacher), TextStyle.gridCellTime),
            (parts(entry.roomName, added: entry.addedRooms, original: entry.originalRoom), TextStyle.gridCellRoom),
        ].filter { !$0.0.isEmpty }

        ZStack(alignment: .topLeading) {
            shape.fill(cell.tone.fill)
            // Below about 34pt a cell carries no text; the tint and ring already say enough.
            if width >= 34 {
                VStack(alignment: .leading, spacing: 1) {
                    line([FieldPart(Timetable.subjectText(entry), changes.subject ? .added : .plain)],
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
        .overlay(alignment: .bottomTrailing) { marks }
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

    /// Homework set, a note, an attachment: in the corner, the one part of a cell that's always
    /// free, so the subject, teacher and room lines stay where they are.
    @ViewBuilder
    private var marks: some View {
        if width >= 34, let icons = entry.icons, !icons.isEmpty {
            HStack(spacing: 1) {
                ForEach(Array(icons.prefix(Self.maxMarks).enumerated()), id: \.offset) { _, name in
                    Image(systemName: LessonMark(untisName: name).symbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(cell.tone.ink.opacity(0.72))
                }
            }
            .padding(2)
            .accessibilityHidden(true)
        }
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
    private func line(_ parts: [FieldPart], style: TextStyle, color: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part.mark {
                case .plain:
                    Text(part.text)
                        .textStyle(style)
                        .foregroundStyle(color)
                        .strikethrough(cancelled)
                        .lineLimit(1)
                case .added, .removed:
                    Text(part.text)
                        .textStyle(style)
                        .foregroundStyle(Brand.onAccent)
                        .strikethrough(part.mark == .removed)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(part.mark == .added ? Brand.accent : Brand.danger, in: .pokyh(4))
                }
            }
        }
    }

    /// A cancelled lesson isn't changed, it's gone: nothing on it gets a chip.
    private func parts(_ current: String, added: [String]?, original: String?) -> [FieldPart] {
        FieldChanges.parts(current: current, added: cancelled ? [] : added ?? [], original: cancelled ? nil : original, dense: dense)
    }
}

// ── Day mode row ────────────────────────────────────────────────────────────

/// Same shape as Home's lesson row. For a substitution the lesson that happens leads and the
/// cancelled one becomes the "statt …" line under it.
struct DaySlotRow: View {
    let slot: MergedSlot
    let tone: Tone
    var absenceMark: AbsenceMark? = nil
    let action: () -> Void
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var scheme

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
                    if let absenceMark {
                        TagChip(s.timetable.label(absenceMark), color: absenceMark == .absent ? Brand.danger : Palette.textSecondary)
                    }
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
        // The same wash the week grid lays over an absence.
        .overlay {
            if let absenceMark {
                let dark = scheme == .dark
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(absenceMark == .absent
                          ? Brand.danger.opacity(dark ? 0.16 : 0.08)
                          : Palette.textSecondary.opacity(dark ? 0.18 : 0.12))
                    .allowsHitTesting(false)
            }
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
    /// The school's own name for it, which wins over the one going by the date.
    var holidayName: String? = nil
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var scheme

    private var config: (color: Color, icon: String, title: String, subtitle: String) {
        let t = s.timetable
        switch kind {
        case .holiday:        return (Brand.orange, "beach.umbrella.fill", holidayName ?? holidayKey.flatMap { t.holidayNames[$0] } ?? t.holiday, t.noLessons)
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
            if compact {
                // In a narrow column a long word shrinks to fit instead of breaking in the middle.
                VStack(spacing: 0) {
                    ForEach(Array(c.title.split(separator: " ").enumerated()), id: \.offset) { _, word in
                        Text(word)
                            .textStyle(.caption)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            } else {
                Text(c.title)
                    .textStyle(.title2)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
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
    var name: String? = nil
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
                Text(name ?? holidayKey.flatMap { s.timetable.holidayNames[$0] } ?? s.timetable.holiday)
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

/// Loads what only the lesson's detail knows (classes, group, texts, homework) and hands it to the
/// sheet, which stays a plain renderer. A failed detail only means the sheet shows what the
/// timetable knows.
struct LessonDetailView: View {
    let item: LessonDetailItem
    var absences: [AbsenceEntry] = []
    @EnvironmentObject private var app: AppState
    @State private var detail: LessonDetail?
    @State private var loading = true
    @State private var waited = false
    @State private var sent: [SentExcuse] = []
    @State private var photo: UIImage?

    /// How long the part below the hero waits for the detail, so it fills in once, not row by row.
    private static let detailWait: Duration = .milliseconds(3500)

    private var entry: TimetableEntry { item.slot.display }
    private var missed: Bool { Timetable.absence(of: entry, in: absences)?.mark == .absent }

    var body: some View {
        LessonDetailContent(item: item, photo: photo, detail: detail, ready: !loading || waited, absences: absences, sent: sent)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.bg)
            .presentationCornerRadius(Radius.xxl)
            .task { await loadDetail() }
            .task {
                try? await Task.sleep(for: Self.detailWait)
                waited = true
            }
            .task { photo = await SubjectPhotos.image(long: entry.subjectLong, short: entry.subjectName) }
            .task(id: missed) { await loadSentExcuses() }
    }

    /// Cancelled lessons have nothing worth waiting for. A lesson seen before shows at once and
    /// offline too; the fresh answer replaces it when it lands.
    private func loadDetail() async {
        guard !entry.isCancelled, let session = app.session, session.hasUntis else { loading = false; return }
        if let stored = UntisClient.shared.storedLessonDetail(entry, source: item.source, session) {
            detail = stored
            loading = false
        }
        if let fresh = try? await UntisClient.shared.lessonDetail(entry, source: item.source, session) {
            detail = fresh
        }
        loading = false
    }

    /// Only an unexcused absence asks: one the class teachers were written about says so.
    private func loadSentExcuses() async {
        guard missed, sent.isEmpty, let session = app.session else { return }
        sent = (try? await UntisClient.shared.sentExcuses(session)) ?? []
    }
}

/// Built like a screen: the sheet is the canvas and everything on it a card, so the hero and
/// the lists separate by the same tone step as everywhere else.
struct LessonDetailContent: View {
    let item: LessonDetailItem
    var photo: UIImage? = nil
    var detail: LessonDetail? = nil
    var ready = true
    var absences: [AbsenceEntry] = []
    var sent: [SentExcuse] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s

    private var slot: MergedSlot { item.slot }
    private var tone: Tone { item.tone }
    private var d: TimetableEntry { slot.display }

    private static let headerHeight: CGFloat = 148
    private static let tileSize: CGFloat = 40
    private static var textInset: CGFloat { Spacing.card + tileSize + Spacing.iconText }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                hero
                if ready {
                    detailsCard
                    if let absence = Timetable.absence(of: d, in: absences) { absenceCard(absence) }
                    if let other = slot.replacement { insteadCard(other) }
                    if d.isExam {
                        let exam = LessonNotes.examText(detail: detail, description: d.examDescription)
                        if !exam.isEmpty { sectionCard(s.timetable.examContent, exam) }
                    }
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        sectionCard(label(note.kind), note.text)
                    }
                    if let homeworks = detail?.homeworks, !homeworks.isEmpty {
                        sectionCard(s.timetable.homework, homeworks.joined(separator: "\n\n"))
                    }
                } else {
                    skeleton
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
    }

    private var notes: [LessonNote] {
        LessonNotes.collect(note: d.note, lessonText: d.lessonText, substitutionText: d.substitutionText,
                            detail: detail, texts: d.texts ?? [])
    }

    private func label(_ kind: LessonNote.Kind) -> String {
        let t = s.timetable
        switch kind {
        case .note: return t.note
        case .lessonText: return t.lessonText
        case .substitution: return t.substitutionText
        case .teachingContent: return s.lessonExtras.teachingContent
        case .teacherNote: return s.lessonExtras.teacherNote
        case .info: return t.info
        }
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
                // Two letters of the subject, oversized and quiet, while there's no photo.
                Text(String(headerName.trimmingCharacters(in: .whitespaces).prefix(2)).uppercased())
                    .textStyle(.numeral(72))
                    .foregroundStyle(tone.ink.opacity(0.30))
                    .lineLimit(1)
            }
            .frame(height: Self.headerHeight)
            .frame(maxWidth: .infinity)
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        // Only over a photo: it keeps the chips legible on whatever the picture holds.
                        .overlay {
                            LinearGradient(stops: [.init(color: .clear, location: 0.45),
                                                   .init(color: .black.opacity(0.55), location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(Motion.standardEase, value: photo != nil)
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
                if Timetable.changes(d).subject {
                    WrapLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs) {
                        fieldChips(FieldChanges.parts(current: d.subjectName, added: d.addedSubjects ?? [], original: d.originalSubject))
                    }
                } else if !d.subjectName.isEmpty, d.subjectName.lowercased() != headerName.lowercased() {
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

    /// Stands in for the part below the hero while the detail is on its way.
    private var skeleton: some View {
        PokyhCard(padding: 0) {
            ForEach(0..<2, id: \.self) { index in
                if index > 0 { RowSeparator(inset: Self.textInset) }
                HStack(spacing: Spacing.iconText) {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(tone.fill.opacity(0.6))
                        .frame(width: Self.tileSize, height: Self.tileSize)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        PokyhDesign.SkeletonBlock(height: 9).frame(width: 64)
                        PokyhDesign.SkeletonBlock(height: 14).frame(width: index == 0 ? 150 : 90)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.card)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    // ── Teacher, room, classes, group ───────────────────────────────────────

    private struct Field {
        let label: String
        let icon: String
        let parts: [FieldPart]
    }

    /// A cancelled lesson isn't changed, it's gone, so it just names who and where it would have been.
    private func parts(current: String, long: String? = nil, added: [String]?, original: String?, originalLong: String? = nil,
                       history: [LessonDetail.Element]?) -> [FieldPart] {
        if d.isCancelled {
            let name = [long, current, originalLong, original].lazy.compactMap { $0 }.first { !$0.isEmpty }
            return name.map { [FieldPart($0)] } ?? []
        }
        return FieldChanges.detailParts(current: current, currentLong: long, added: added ?? [], original: original,
                                        originalLong: originalLong, history: history ?? [])
    }

    private var fields: [Field] {
        let t = s.timetable
        let all = [
            Field(label: t.teacher, icon: "person.fill",
                  parts: parts(current: d.teacherName, long: d.teacherLongName, added: d.addedTeachers, original: d.originalTeacher,
                               originalLong: d.originalTeacherLong, history: detail?.teachers)),
            Field(label: t.room, icon: "mappin.and.ellipse",
                  parts: parts(current: d.roomName, added: d.addedRooms, original: d.originalRoom, history: detail?.rooms)),
            Field(label: t.classes, icon: "person.3.fill",
                  parts: (detail?.classes ?? []).isEmpty ? [] : [FieldPart(detail?.classes.joined(separator: ", ") ?? "")]),
            Field(label: t.group, icon: "person.2.fill",
                  parts: (detail?.group ?? "").isEmpty ? [] : [FieldPart(detail?.group ?? "")]),
        ]
        return all.filter { !$0.parts.isEmpty }
    }

    @ViewBuilder
    private var detailsCard: some View {
        let shown = fields
        if !shown.isEmpty {
            PokyhCard(padding: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, field in
                    if index > 0 { RowSeparator(inset: Self.textInset) }
                    if field.parts.contains(where: { $0.mark != .plain }) {
                        changeRow(field)
                    } else {
                        detailRow(field.label, field.parts.map(\.text).joined(separator: ", "), icon: field.icon)
                    }
                }
            }
        }
    }

    /// The row's glyph on the subject's pastel, so the list belongs to the lesson.
    private func tile(_ icon: String, tone: Tone? = nil) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle((tone ?? self.tone).ink)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .background((tone ?? self.tone).fill, in: .pokyh(Radius.sm))
    }

    private func detailRow(_ label: String, _ value: String, icon: String, tone: Tone? = nil, valueColor: Color = Palette.textPrimary) -> some View {
        HStack(spacing: Spacing.iconText) {
            tile(icon, tone: tone)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                EyebrowLabel(label)
                Text(value).textStyle(.body).foregroundStyle(valueColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
    }

    /// Each name on its own chip: new ones in the accent, the ones that went struck through, and
    /// wrapping between names so a full name never breaks in the middle.
    private func changeRow(_ field: Field) -> some View {
        HStack(spacing: Spacing.iconText) {
            tile(field.icon)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                EyebrowLabel(field.label)
                WrapLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs) {
                    fieldChips(field.parts)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.card)
        .padding(.vertical, Spacing.md)
    }

    private func fieldChips(_ parts: [FieldPart]) -> some View {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
            switch part.mark {
            case .plain:
                Text(part.text).textStyle(.body).foregroundStyle(Palette.textPrimary)
            case .added, .removed:
                Text(part.text)
                    .textStyle(TextStyle.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.onAccent)
                    .strikethrough(part.mark == .removed)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 3)
                    .background(part.mark == .added ? Brand.accent : Brand.danger, in: .pokyh(Radius.xs))
            }
        }
    }

    // ── Absence ─────────────────────────────────────────────────────────────

    /// What the class teachers were sent about this lesson, the latest if several.
    private func sentExcuse(_ absence: LessonAbsence<AbsenceEntry>) -> SentExcuse? {
        guard absence.mark == .absent else { return nil }
        let start = d.date * 10000 + d.startTime, end = d.date * 10000 + d.endTime
        return sent.filter { $0.start < end && $0.end > start }.max { $0.sentAt < $1.sentAt }
    }

    private func sentDay(_ excuse: SentExcuse) -> String? {
        guard let day = Int(excuse.sentAt.prefix(10).replacingOccurrences(of: "-", with: "")), day > 0 else { return nil }
        let text = ClassregTone.date(day, s.lang == .de ? "d. MMM" : "d MMM", s)
        return text.isEmpty ? nil : text
    }

    private func absenceCard(_ absence: LessonAbsence<AbsenceEntry>) -> some View {
        let t = s.timetable
        let excuse = sentExcuse(absence)
        let color = excuse != nil ? Brand.warning : absence.mark == .absent ? Brand.danger : Brand.success
        let status = Tone(fill: color.opacity(0.16), ink: color)
        var reasons: [String] = []
        for name in absence.covering.compactMap(\.reasonName) where !name.isEmpty && !reasons.contains(name) { reasons.append(name) }
        return PokyhCard(padding: 0) {
            detailRow(t.absent, excuse != nil ? t.markSent : t.label(absence.mark),
                      icon: excuse != nil ? "paperplane.fill" : "person.fill.xmark", tone: status, valueColor: color)
            if let excuse, !excuse.recipients.isEmpty {
                let names = excuse.recipients.joined(separator: ", ")
                RowSeparator(inset: Self.textInset)
                detailRow(s.messages.recipients, sentDay(excuse).map { t.sentTo(names, $0) } ?? names, icon: "person.fill")
            }
            RowSeparator(inset: Self.textInset)
            detailRow(t.period, absence.covering.map { AbsenceMarks.rangeText($0, wholeDay: t.wholeDay) }.joined(separator: "\n"), icon: "clock")
            if !reasons.isEmpty {
                RowSeparator(inset: Self.textInset)
                detailRow(t.reason, reasons.joined(separator: ", "), icon: "doc.text")
            }
        }
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

    static let holidayWeek: [[TimetableEntry]] = week.enumerated().map { $0.offset == 4 ? [] : $0.element }

    static let absences = [
        AbsenceEntry(id: 1, startDate: 20261102, endDate: 20261102, startTime: 840, endTime: 1125, isExcused: true,
                     reasonName: "Krankheit", absenceType: nil, hours: 3, note: nil, excuseNote: nil, teacherName: nil, subjectName: nil),
        AbsenceEntry(id: 2, startDate: 20261103, endDate: 20261103, startTime: 750, endTime: 930, isExcused: false,
                     reasonName: nil, absenceType: nil, hours: 2, note: nil, excuseNote: nil, teacherName: nil, subjectName: nil),
    ]

    static let changedLesson: TimetableEntry = {
        var e = entry(101, day: 20261103, 750, 840, "M", teacher: "SCH", room: "Inf VI, 2.05", originalRoom: nil)
        e.subjectLong = "Mathematik"
        e.teacherLongName = "Anna Schmid"
        e.isSubstitution = true
        e.originalTeacher = "MUE"
        e.originalTeacherLong = "Hans Müller"
        e.addedRooms = ["Inf VI"]
        e.icons = ["HOMEWORK", "attachment"]
        e.note = "Taschenrechner mitbringen"
        return e
    }()

    static let detail = LessonDetail(
        texts: [.init(kind: .teachingContent, text: "Quadratische Gleichungen, Seite 42"),
                .init(kind: .teacherNote, text: "Bitte das Heft nicht vergessen")],
        classes: ["4A", "4B"], group: "Gruppe 1", homeworks: ["Seite 12, Aufgabe 3"],
        rooms: [.init(name: "1.12", status: "REMOVED")]
    )

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

#Preview("Week grid, absent and on holiday") {
    GeometryReader { geo in
        WeekGrid(dayEntries: TimetablePreviewData.holidayWeek, dayLabels: ["Mo", "Di", "Mi", "Do", "Fr", "Sa"],
                 dayNumbers: [2, 3, 4, 5, 6, 7], weekLabel: "KW 45", monthLabel: "Nov.",
                 todayNum: 20261104, dayNums: (0..<6).map { 20261102 + $0 }, size: geo.size,
                 absences: TimetablePreviewData.absences,
                 holidayTitles: [nil, nil, nil, nil, "Tag der Schulautonomie", nil], onTap: { _, _ in })
    }
    .background(Palette.bg)
}

#Preview("Lesson detail") {
    let e = TimetablePreviewData.changedLesson
    Color.clear.sheet(isPresented: .constant(true)) {
        LessonDetailContent(item: LessonDetailItem(slot: MergedSlot(display: e, replacement: nil, kind: .replacement), tone: .subject(e.subjectName)),
                            detail: TimetablePreviewData.detail, absences: TimetablePreviewData.absences)
    }
}

#Preview("Other timetables") {
    @Previewable @State var kind = TimetableKind.klass
    OtherTimetablesList(source: TimetableSource(kind: .klass, id: 2, name: "4B"), kind: $kind,
                        list: [TimetableResource(id: 1, name: "4A", longName: "4. Klasse A"), TimetableResource(id: 2, name: "4B")],
                        failed: false, pick: { _ in }, retry: {})
}
#endif
