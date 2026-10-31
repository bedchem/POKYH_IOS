import SwiftUI
import Combine
import UIKit
import PokyhCore
import PokyhDesign

// ── The store ───────────────────────────────────────────────────────────────

struct RecapProgress: Equatable {
    var done: Int
    var total: Int
}

/// Recaps in the app: the ones the account may open now (backend /recaps), which one is on screen,
/// and the WebUntis figures of a recap's period, worked out on this device and sent nowhere. A recap
/// no device of the account has shown yet opens by itself once the app is quiet for a moment.
/// Whether it was shown, and watched to the end, is kept with the account.
@MainActor
final class RecapStore: ObservableObject {
    static let shared = RecapStore()

    /// Nil until the first answer.
    @Published private(set) var recaps: [Recap]?
    /// The recap on screen.
    @Published var open: Recap?
    @Published private(set) var progress: [String: RecapProgress] = [:]

    private static let refreshEvery = 15.0 * 60
    /// The story waits this long, then for anything else on screen to go away, then gives up until
    /// the next refresh.
    private static let quietMs = 2200
    private static let quietTries = 60
    private static let preloadAfter = 3.0
    private static let keptWeeks = 60

    private var owner: String?
    private var autoTried = Set<String>()
    private var preloaded = Set<String>()
    private var running: [String: Task<RecapFigures.Untis, Error>] = [:]

    /// Follows the signed-in account: its recaps, every 15 minutes again.
    func follow(_ app: AppState) async {
        if owner != app.session?.username {
            owner = app.session?.username
            recaps = nil
            open = nil
            autoTried = []
            preloaded = []
            running = [:]
            progress = [:]
        }
        while !Task.isCancelled {
            await refresh(app)
            preload(app)
            await maybeOpen(app)
            try? await Task.sleep(for: .seconds(Self.refreshEvery))
        }
    }

    /// An error leaves the last answer, or none, in place.
    private func refresh(_ app: AppState) async {
        guard let token = app.session?.apiToken, let list = try? await BackendClient.shared.recaps(token: token) else { return }
        recaps = list
    }

    private func maybeOpen(_ app: AppState) async {
        guard let due = recaps?.first(where: { $0.openedAt == nil }), !autoTried.contains(due.id), open == nil else { return }
        try? await Task.sleep(for: .milliseconds(Self.quietMs))
        for _ in 0..<Self.quietTries {
            if Task.isCancelled { return }
            let active = UIApplication.shared.applicationState == .active
            if active, app.phase == .authed, !app.busy, open == nil, PopupStore.shared.stack.current == nil, !PresentedModal.isUp {
                autoTried.insert(due.id)
                open = due
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// The figures of the newest recap not watched to its end, ahead of time.
    private func preload(_ app: AppState) {
        guard let waiting = recaps?.first(where: \.isNew), waiting.wantsUntis, !preloaded.contains(waiting.id),
              let session = app.session, session.studentId > 0, !session.bearerToken.isEmpty else { return }
        preloaded.insert(waiting.id)
        Task {
            try? await Task.sleep(for: .seconds(Self.preloadAfter))
            if self.owner == session.username { _ = self.loadUntis(waiting, session) }
        }
    }

    func detail(_ recap: Recap, token: String) async throws -> RecapDetail {
        try await BackendClient.shared.recap(id: recap.id, token: token)
    }

    /// Opened and, with `finished`, watched to the end, on every device of the account.
    func markView(_ recap: Recap, finished: Bool, token: String?) {
        guard let token else { return }
        Task {
            guard let seen = try? await BackendClient.shared.markRecapView(id: recap.id, finished: finished, token: token) else { return }
            if let i = recaps?.firstIndex(where: { $0.id == recap.id }) {
                recaps?[i].openedAt = seen.openedAt
                recaps?[i].finishedAt = seen.finishedAt
            }
        }
    }

    // ── The WebUntis figures ────────────────────────────────────────────────

    func progressKey(_ recap: Recap, _ session: UserSession) -> String {
        "\(session.schoolRef.loginName):\(session.studentId):\(recap.periodFrom):\(recap.periodTo):\(recap.sections.joined(separator: ","))"
    }

    /// The banner's preload and the story share one load. Parts WebUntis doesn't give this account
    /// come back as nil.
    func loadUntis(_ recap: Recap, _ session: UserSession) -> Task<RecapFigures.Untis, Error> {
        let key = progressKey(recap, session)
        if let task = running[key], !task.isCancelled { return task }
        let task = Task { [self] in
            do {
                return try await run(session, recap, key: key)
            } catch {
                running[key] = nil
                throw error
            }
        }
        running[key] = task
        return task
    }

    /// What one load has so far. Its parts run side by side, all on the main actor.
    private final class Run {
        var stored: [String: RecapFigures.Week]
        var queue: [String]
        var failed: [String] = []
        var expired: AppError?
        var done = 0
        let total: Int

        init(stored: [String: RecapFigures.Week], queue: [String], total: Int) {
            self.stored = stored
            self.queue = queue
            self.total = total
        }

        func next() -> String? { queue.isEmpty ? nil : queue.removeFirst() }
    }

    private func step(_ state: Run, key: String) {
        state.done += 1
        progress[key] = RecapProgress(done: state.done, total: state.total)
    }

    private func settle<T>(_ state: Run, key: String, _ work: () async throws -> T) async -> T? {
        defer { step(state, key: key) }
        do {
            return try await work()
        } catch let error as AppError where error.isSessionExpired {
            state.expired = error
            return nil
        } catch {
            return nil
        }
    }

    private func run(_ s: UserSession, _ recap: Recap, key: String) async throws -> RecapFigures.Untis {
        let clock = DayClock()
        let from = RecapFigures.numOfISO(recap.periodFrom), to = RecapFigures.numOfISO(recap.periodTo)
        let nowMs = DayClock.ms(Date())
        let now = RecapFigures.Now(ms: nowMs, clock: clock)
        let until = min(to, now.day)
        let wants = { (section: String) in recap.sections.contains(section) }
        let weeksKey = "recap-weeks-\(s.schoolRef.loginName)-\(s.studentId)"
        let stored = DiskCache.load([String: RecapFigures.Week].self, key: weeksKey) ?? [:]
        // Offline there's only what is stored. An empty answer here would read as "nothing missed".
        let online = !s.bearerToken.isEmpty
        let mondays = wants("school") || wants("absences") ? RecapFigures.periodWeeks(from: from, to: to, now: now) : []
        let due = online ? mondays.filter { RecapFigures.weekIsDue(stored[$0], monday: $0, now: nowMs, clock: clock) } : []
        let others = online ? [wants("absences"), wants("absences"), wants("grades"), wants("exams"), wants("classreg")].filter { $0 }.count : 0
        let state = Run(stored: stored, queue: due, total: due.count + others)
        progress[key] = RecapProgress(done: 0, total: state.total)

        let years = Array(Set([RecapFigures.schoolYear(of: from), RecapFigures.schoolYear(of: until)]))
        let yearArg = { (y: Int) in y == SchoolDates.currentSchoolYear ? nil : y }

        let absences = Task { () -> [RecapFigures.AbsenceIn]? in
            guard online, wants("absences") else { return nil }
            return await settle(state, key: key) {
                try await UntisClient.shared.absences(startDate: "\(from)", endDate: "\(to)", s).map {
                    RecapFigures.AbsenceIn(id: $0.id, startDate: $0.startDate, endDate: $0.endDate, startTime: $0.startTime,
                                           endTime: $0.endTime, isExcused: $0.isExcused, hours: $0.hours, subjectName: $0.subjectName)
                }
            }
        }
        let times = Task { () -> [RecapFigures.TimeIn]? in
            guard online, wants("absences") else { return nil }
            return await settle(state, key: key) { try await RecapUntisCalls.absenceTimes(from: from, to: to, s) }
        }
        let grades = Task { () -> [RecapFigures.GradeSubjectIn]? in
            guard online, wants("grades") else { return nil }
            return await settle(state, key: key) {
                var out: [RecapFigures.GradeSubjectIn] = []
                for year in years {
                    let subjects = try await UntisClient.shared.grades(year: yearArg(year), s)
                    out += subjects.map { subject in
                        RecapFigures.GradeSubjectIn(subjectName: subject.subjectName,
                                                    grades: subject.grades.map { .init(date: $0.date, value: $0.markDisplayValue) })
                    }
                }
                return out
            }
        }
        let homework = Task { () -> [RecapFigures.HomeworkIn]? in
            guard online, wants("exams") else { return nil }
            return await settle(state, key: key) {
                try await UntisClient.shared.homeworks(from: from, to: to, s).map { RecapFigures.HomeworkIn(id: $0.id, dueDate: $0.dueDate) }
            }
        }
        let classreg = Task { () -> [Int]? in
            guard online, wants("classreg") else { return nil }
            return await settle(state, key: key) {
                var out: [Int] = []
                for year in years { out += try await UntisClient.shared.classregEvents(year: yearArg(year), s).map(\.createDate) }
                return out
            }
        }

        // The weeks, a few at a time; a failed one once more at the end.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(3, due.count) {
                group.addTask { @MainActor in
                    while state.expired == nil, let monday = state.next() {
                        await self.loadWeek(monday, s, state, retry: false)
                        self.step(state, key: key)
                    }
                }
            }
        }
        for monday in state.failed where state.expired == nil {
            await loadWeek(monday, s, state, retry: true)
        }
        if !due.isEmpty {
            let kept = state.stored.keys.sorted().suffix(Self.keptWeeks)
            DiskCache.save(state.stored.filter { kept.contains($0.key) }, key: weeksKey)
        }

        let sources = RecapFigures.Sources(
            from: from, to: to, now: now,
            weeks: state.stored.filter { mondays.contains($0.key) },
            absences: await absences.value,
            times: await times.value,
            grades: await grades.value,
            homework: await homework.value,
            classreg: await classreg.value
        )
        if let expired = state.expired { throw expired }
        return RecapFigures.untis(sources)
    }

    private func loadWeek(_ monday: String, _ s: UserSession, _ state: Run, retry: Bool) async {
        do {
            let entries = try await UntisClient.shared.timetable(date: monday, s)
            state.stored[monday] = RecapFigures.Week(at: DayClock.ms(Date()), days: Self.lessons(entries))
        } catch let error as AppError where error.isSessionExpired {
            state.expired = error
        } catch {
            if !retry { state.failed.append(monday) }
        }
    }

    private static func lessons(_ entries: [TimetableEntry]) -> [Int: [RecapFigures.Lesson]] {
        var byDay: [Int: [RecapFigures.Lesson]] = [:]
        for e in entries {
            let lesson = RecapFigures.lesson(
                startTime: e.startTime, endTime: e.endTime,
                subject: e.subjectLong.isEmpty ? e.subjectName : e.subjectLong,
                teachers: e.teacherLongName ?? e.teacherName, room: e.roomName,
                cancelled: e.isCancelled, exam: e.isExam, substitution: e.isSubstitution
            )
            if let lesson { byDay[e.date, default: []].append(lesson) }
        }
        return byDay.mapValues { $0.sorted { $0.start < $1.start } }
    }
}

/// The one WebUntis answer only the recap reads, with the session's own credentials.
private enum RecapUntisCalls {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static func get(_ path: String, _ s: UserSession) async throws -> JSON {
        guard let url = URL(string: s.schoolRef.baseString + path) else { throw AppError(message: Strings.current.errors.badAnswer) }
        var req = URLRequest(url: url)
        req.setValue("JSESSIONID=\(s.sessionId); schoolname=\"\(s.schoolRef.cookie)\"", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(s.bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AppError(message: Strings.current.errors.untisDown) }
        if http.statusCode == 401 || data.first == UInt8(ascii: "<") { throw AppError.sessionExpired }
        guard http.statusCode == 200 else { throw AppError(message: "HTTP \(http.statusCode)", status: http.statusCode) }
        return JSON.parse(data)
    }

    /// The school's own "Fehlzeiten".
    static func absenceTimes(from: Int, to: Int, _ s: UserSession) async throws -> [RecapFigures.TimeIn] {
        let query = "?startDate=\(from)&endDate=\(to)&studentId=\(s.studentId)&excuseStatusId=-1&excludeAbsences=false&excludeLateness=false"
        let root = try await get(Config.Routes.Engagement.absenceTimes + query, s)
        let list = root.data.absenceTimes.exists ? root.data.absenceTimes : root.absenceTimes
        guard list.exists else { throw AppError(message: Strings.current.errors.badAnswer) }
        return list.array.map {
            RecapFigures.TimeIn(absenceId: $0.absenceId.int ?? 0, minutes: max(0, $0.missedMins.int ?? 0),
                                subject: ($0.subjectName.string ?? "").trimmingCharacters(in: .whitespaces),
                                excused: $0.excused.bool ?? false, date: $0.date.int ?? 0)
        }
    }
}

// ── The mascot ──────────────────────────────────────────────────────────────

/// The pixel mascot wherever a recap shows it: banner, story and poster. Same pose for each mood
/// as Android's reactionOf.
struct RecapMascot: View {
    let mood: RecapStoryModel.Mood
    var size: CGFloat = 88
    var fill: Color = Palette.accentTint
    var ink: Color = Palette.accentText

    private var look: MascotLook {
        switch mood {
        case .wave: MascotLook(pose: .init(eyes: .happy, look: Pt(0, 0), mouth: .grin, arms: .wave), wave: true, motion: .hop)
        case .legend: MascotLook(pose: .init(eyes: .happy, look: Pt(0, 0), mouth: .grin, arms: .cheer), motion: .jump)
        case .great: MascotLook(pose: .init(eyes: .happy, look: Pt(0, 0), mouth: .grin, arms: .cheer), motion: .jump)
        case .good: MascotLook(pose: .init(eyes: .happy, look: Pt(0, 0), mouth: .grin, arms: .thumb), motion: .hop)
        case .ok: MascotLook(pose: .init(eyes: .open, look: Pt(1, 0), mouth: .smile, arms: .wave), blink: true, wave: true)
        case .meh: MascotLook(pose: .init(eyes: .open, look: Pt(-1, 0), mouth: .wobble, arms: .down), blink: true, sweat: true)
        case .worried: MascotLook(pose: .init(eyes: .wide, look: Pt(0, 0), mouth: .o, arms: .peek), mark: "!", sweat: true, motion: .shake)
        case .alarm: MascotLook(pose: .init(eyes: .closed, look: Pt(0, 0), mouth: .frown, arms: .cover), mark: "!", sweat: true, motion: .shake)
        case .proud: MascotLook(pose: .init(eyes: .happy, look: Pt(0, 0), mouth: .grin, arms: .thumb), motion: .hop)
        case .love: MascotLook(pose: .init(eyes: .happy, look: Pt(0, 0), mouth: .grin, arms: .wave), wave: true, motion: .hop)
        case .focused: MascotLook(pose: .init(eyes: .open, look: Pt(1, 0), mouth: .flat, arms: .lens), blink: true)
        case .sleepy: MascotLook(pose: .init(eyes: .closed, look: Pt(0, 0), mouth: .o, arms: .down), think: true)
        case .party: MascotLook(pose: .init(eyes: .happy, look: Pt(0, 0), mouth: .grin, arms: .cheer), motion: .jump)
        case .cool: MascotLook(pose: .init(eyes: .open, look: Pt(1, 0), mouth: .smile, arms: .thumb), motion: .hop)
        case .curious: MascotLook(pose: .init(eyes: .open, look: Pt(1, -1), mouth: .o, arms: .lens), mark: "?")
        case .peek: MascotLook(pose: .init(eyes: .open, look: Pt(1, 1), mouth: .o, arms: .peek), blink: true)
        case .angry: MascotLook(pose: .init(eyes: .angry, look: Pt(0, 0), mouth: .frown, arms: .fists), anger: true, motion: .fume)
        case .angel: MascotLook(pose: .init(eyes: .closed, look: Pt(0, 0), mouth: .smile, arms: .down), motion: .hop)
        case .zap: MascotLook(pose: .init(eyes: .wide, look: Pt(0, 0), mouth: .grin, arms: .cheer), motion: .buzz)
        case .night: MascotLook(pose: .init(eyes: .closed, look: Pt(0, 0), mouth: .smile, arms: .down))
        case .early: MascotLook(pose: .init(eyes: .wide, look: Pt(0, 0), mouth: .grin, arms: .wave), wave: true, motion: .jump)
        case .cheer: MascotLook(pose: .init(eyes: .happy, look: Pt(0, 0), mouth: .grin, arms: .cheer), motion: .hop)
        }
    }

    var body: some View {
        MascotView(look: look, size: size * 0.82, motionKey: mood.rawValue)
            .frame(width: size, height: size)
            .background(fill, in: .pokyh(size * 0.28))
            .accessibilityHidden(true)
    }
}

// ── Home: the banner, and the host ──────────────────────────────────────────

/// On Home while there's a recap to open, its ring turning while it's new.
struct RecapBanner: View {
    @ObservedObject private var store = RecapStore.shared
    @Environment(\.strings) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        if let recap = store.recaps?.first {
            let isNew = recap.isNew
            Button { store.open = recap } label: {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .strokeBorder(Brand.accent, style: StrokeStyle(lineWidth: 3, dash: isNew ? [6, 4] : []))
                            .rotationEffect(.degrees(turning && isNew && !reduceMotion ? 360 : 0))
                        RecapMascot(mood: .wave, size: 34, fill: .clear)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.recap.text(isNew ? "bannerNew" : "bannerSeen"))
                            .textStyle(.headline)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(2)
                        Text(recap.title)
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(s.recap.text(isNew ? "bannerOpen" : "bannerAgain"))
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Palette.accentTint, in: .capsule)
                }
                .padding(Spacing.md)
                .contentShape(.rect)
            }
            .buttonStyle(.rowPress(radius: Radius.xl))
            .cardSurface()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { turning = true }
            }
        }
    }
}

/// Keeps the store going and shows the story while one is open.
struct RecapHost: ViewModifier {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = RecapStore.shared

    func body(content: Content) -> some View {
        content
            .task(id: app.session?.username) { await store.follow(app) }
            .fullScreenCover(item: $store.open) { recap in
                RecapStoryView(recap: recap, store: store)
            }
    }
}

// ── The pages' colors ───────────────────────────────────────────────────────

private struct StoryColors {
    let bg, dot, ground, edge, chip, soft, accent, accentInk: Color

    init(_ bg: UInt32, _ dot: UInt32, _ ground: UInt32, _ edge: UInt32, _ chip: UInt32, _ soft: UInt32, _ accent: UInt32, _ accentInk: UInt32) {
        self.bg = Color(hex: bg)
        self.dot = Color(hex: dot)
        self.ground = Color(hex: ground)
        self.edge = Color(hex: edge)
        self.chip = Color(hex: chip)
        self.soft = Color(hex: soft)
        self.accent = Color(hex: accent)
        self.accentInk = Color(hex: accentInk)
    }
}

private extension RecapStoryModel.Theme {
    var colors: StoryColors {
        switch self {
        case .night: StoryColors(0x1B1640, 0x231D52, 0x2C2566, 0x3D3488, 0x2F2870, 0xD4CFFB, 0xFFD166, 0x1B1640)
        case .brand: StoryColors(0x312A92, 0x3A32A6, 0x262079, 0x4F46E5, 0x3D35B0, 0xE0E7FF, 0x7EE8FA, 0x1E1B4B)
        case .ocean: StoryColors(0x0B3B66, 0x0E4677, 0x0E5289, 0x1769AA, 0x0F4A7D, 0xD3E9FF, 0xFFD166, 0x0B3B66)
        case .sky: StoryColors(0x1D4F91, 0x2259A1, 0x173F74, 0x3B82D6, 0x255EA8, 0xDBEAFE, 0xFDE68A, 0x16365F)
        case .teal: StoryColors(0x0D4D4D, 0x105858, 0x116363, 0x178080, 0x125D5D, 0xCCFBF1, 0xFDE047, 0x0B3B3B)
        case .mint: StoryColors(0x0F5132, 0x125C3A, 0x146C43, 0x1B8A56, 0x156240, 0xD1FAE5, 0xFEF08A, 0x0D3B25)
        case .forest: StoryColors(0x1F3D1A, 0x25481F, 0x2D5A26, 0x3B7532, 0x2A5223, 0xDCFCE7, 0xFDBA74, 0x1F3D1A)
        case .gold: StoryColors(0x6B4300, 0x7A4D00, 0x8A5800, 0xA86C00, 0x7D4F00, 0xFEF3C7, 0xFFE066, 0x3F2700)
        case .sunset: StoryColors(0x7C2D12, 0x883214, 0x9A3412, 0xC2410C, 0x8F3313, 0xFFEDD5, 0xFDE047, 0x45180A)
        case .candy: StoryColors(0x831843, 0x8F1B4A, 0x9D174D, 0xBE185D, 0x921A4B, 0xFCE7F3, 0xFDE68A, 0x4A0D26)
        case .rose: StoryColors(0x881337, 0x94163D, 0x9F1239, 0xBE123C, 0x97163E, 0xFFE4E6, 0xFED7AA, 0x4C0A1F)
        case .grape: StoryColors(0x4C1D95, 0x5521A6, 0x5B21B6, 0x6D28D9, 0x5622AB, 0xEDE9FE, 0xF9A8D4, 0x2E1065)
        case .dusk: StoryColors(0x2A2770, 0x302C7E, 0x3730A3, 0x4338CA, 0x332F8C, 0xE0E7FF, 0xF0ABFC, 0x1E1B4B)
        case .ember: StoryColors(0x8A3A0C, 0x97400E, 0xA54A0F, 0xC2570C, 0x9A440E, 0xFFEDD5, 0xFCD34D, 0x451A03)
        case .alarm: StoryColors(0x7F1D1D, 0x8C2020, 0x991B1B, 0xB91C1C, 0x922020, 0xFEE2E2, 0xFDE047, 0x450A0A)
        }
    }
}

private enum StoryParticles {
    case confetti, stars, rain, alarm

    init?(_ mood: RecapStoryModel.Mood) {
        switch mood {
        case .wave, .great, .angel, .night: self = .stars
        case .legend, .party, .cheer: self = .confetti
        case .worried: self = .rain
        case .alarm: self = .alarm
        default: return nil
        }
    }
}

// ── The story ───────────────────────────────────────────────────────────────

/// A recap as a story, page after page: a figure, what it means and the mascot's take on it. Each
/// page is a little scene, a sky in the page's color and the ground the mascot stands on. A tap on
/// the right or "Weiter" goes on, on the left back; a swipe down closes. Nothing moves on by itself.
struct RecapStoryView: View {
    let recap: Recap
    @ObservedObject var store: RecapStore

    @EnvironmentObject private var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Load {
        case waiting
        case ready(slides: [RecapStoryModel.Slide], summary: [RecapStoryModel.SummaryItem], notice: String?)
        case failed(String)
    }

    @State private var load = Load.waiting
    @State private var index = 0
    @State private var attempt = 0
    @State private var forward = true
    @State private var drag: CGFloat = 0
    @State private var posterOpen = false

    private var format: RecapFormatter { RecapFormatter(strings: s) }

    private var firstName: String {
        guard let session = app.session else { return "" }
        return RecapStoryModel.firstName(personName: session.personName, username: session.username,
                                         isParent: session.isParent, hasUntis: session.hasUntis)
    }

    private var slides: [RecapStoryModel.Slide] {
        if case .ready(let slides, _, _) = load { return slides }
        // The first page is there at once; its button shows how far the figures are.
        return [RecapStoryModel.intro(title: recap.title, firstName: firstName, periodFrom: recap.periodFrom, periodTo: recap.periodTo, format)]
    }

    private var summary: [RecapStoryModel.SummaryItem] {
        if case .ready(_, let summary, _) = load { return summary }
        return []
    }

    private var isReady: Bool {
        if case .ready = load { return true }
        return false
    }

    private var isFailed: Bool {
        if case .failed = load { return true }
        return false
    }

    private var slide: RecapStoryModel.Slide {
        let all = slides
        return all[min(max(index, 0), all.count - 1)]
    }

    /// Only the first page shows why something is missing.
    private var notice: String? {
        guard index == 0 else { return nil }
        switch load {
        case .ready(_, _, let notice): return notice
        case .failed(let message): return message
        case .waiting: return nil
        }
    }

    private var primaryLabel: String {
        let t = s.recap
        if slide.layout == .summary { return t.text("done") }
        if isFailed { return t.text("retry") }
        if !isReady {
            if let session = app.session, let p = store.progress[store.progressKey(recap, session)], p.total > 0 {
                return t.text("loading", ["done": String(p.done), "total": String(p.total)])
            }
            return t.text("loadingShort")
        }
        return index == 0 ? t.text("start") : t.text("next")
    }

    private func close() { store.open = nil }

    private func next() {
        guard isReady else { return }
        if index < slides.count - 1 {
            forward = true
            withAnimation(pageAnimation) { index += 1 }
        } else {
            close()
        }
    }

    private func back() {
        guard index > 0 else { return }
        forward = false
        withAnimation(pageAnimation) { index -= 1 }
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: Motion.fast) : .easeInOut(duration: Motion.standard)
    }

    /// With Reduce Motion the pages only crossfade.
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 28 : -28)), removal: .opacity)
    }

    var body: some View {
        let slide = slide
        let colors = slide.theme.colors
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            ZStack {
                colors.bg.ignoresSafeArea()
                RecapPage(slide: slide, summary: summary, notice: notice, safeBottom: bottomInset, format: format)
                    .id(slide.id)
                    .transition(pageTransition)
                chrome(colors)
            }
            .contentShape(.rect)
            .onTapGesture { location in
                if location.x < proxy.size.width / 3 { back() } else { next() }
            }
        }
        .offset(y: reduceMotion ? 0 : drag)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    if value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) {
                        drag = value.translation.height * 0.5
                    }
                }
                .onEnded { value in
                    if value.translation.height > 160 {
                        close()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
                    }
                }
        )
        .background(colors.bg.ignoresSafeArea())
        .statusBarHidden()
        .task { store.markView(recap, finished: false, token: app.session?.apiToken) }
        .task(id: attempt) { await loadFigures() }
        .onChange(of: slide.id) {
            if slide.layout == .summary { store.markView(recap, finished: true, token: app.session?.apiToken) }
        }
        .accessibilityAction(named: s.recap.text("next")) { next() }
        .accessibilityAction(named: s.recap.text("back")) { back() }
        .accessibilityAction(.escape) { close() }
        .sheet(isPresented: $posterOpen) {
            RecapPosterSheet(title: recap.title, firstName: firstName.isEmpty ? nil : firstName, items: summary)
        }
    }

    private func loadFigures() async {
        load = .waiting
        let t = s.recap
        let session = app.session
        var detail: RecapDetail?
        if let token = session?.apiToken { detail = try? await store.detail(recap, token: token) }
        var untis: RecapFigures.Untis?
        if let session, session.hasUntis, recap.wantsUntis {
            untis = try? await store.loadUntis(recap, session).value
        }
        if detail == nil && untis == nil {
            load = .failed(t.text("errorAll"))
            return
        }
        let input = RecapStoryModel.Input(title: recap.title, firstName: firstName, periodFrom: recap.periodFrom, periodTo: recap.periodTo,
                                          sections: recap.sections, untis: untis, pokyh: detail?.pokyh)
        let missing = recap.wantsUntis && untis == nil
        load = .ready(slides: RecapStoryModel.build(input, format), summary: RecapStoryModel.summaryItems(input, format),
                      notice: missing ? t.text("errorUntis") : nil)
    }

    /// The progress through the pages, the way out, and the buttons on the ground. The quiet buttons
    /// take the ground's lit edge color: its checker tiles would swallow one in their own.
    private func chrome(_ colors: StoryColors) -> some View {
        let t = s.recap
        let all = slides
        return VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    ForEach(all.indices, id: \.self) { i in
                        Capsule()
                            .fill(i <= index ? colors.accent : colors.chip)
                            .frame(height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t.text("slideOf", ["n": String(index + 1), "total": String(all.count)]))
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.soft)
                        .frame(width: 36, height: 36)
                        .background(colors.chip, in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.text("close"))
            }
            .padding(.leading, Spacing.lg)
            .padding(.trailing, Spacing.sm)
            Spacer(minLength: 0)
            HStack(spacing: Spacing.sm) {
                if index > 0 {
                    Button(t.text("back"), action: back)
                        .buttonStyle(StoryButtonStyle(fill: colors.edge, ink: colors.soft))
                }
                if slide.layout == .summary {
                    Button(t.text("replay")) {
                        forward = false
                        withAnimation(pageAnimation) { index = 0 }
                    }
                    .buttonStyle(StoryButtonStyle(fill: colors.edge, ink: colors.soft))
                    Button(t.text("share")) { posterOpen = true }
                        .buttonStyle(StoryButtonStyle(fill: colors.edge, ink: colors.soft))
                        .disabled(summary.isEmpty)
                }
                Spacer(minLength: 0)
                Button(primaryLabel) {
                    if isFailed { attempt += 1 } else { next() }
                }
                .buttonStyle(StoryButtonStyle(fill: colors.accent, ink: colors.accentInk))
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
    }
}

private struct StoryButtonStyle: ButtonStyle {
    let fill: Color
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.button)
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 48)
            .background(fill, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.capsule)
    }
}

/// One page: sky and ground, the words, the mascot on the ground.
private struct RecapPage: View {
    let slide: RecapStoryModel.Slide
    let summary: [RecapStoryModel.SummaryItem]
    let notice: String?
    let safeBottom: CGFloat
    let format: any RecapFormat

    /// What the buttons need to stand on, above the safe area.
    private static let ground: CGFloat = 88

    var body: some View {
        let colors = slide.theme.colors
        ZStack {
            StorySky(colors: colors, groundHeight: Self.ground + safeBottom)
            if let particles = StoryParticles(slide.mood) {
                StoryParticleField(kind: particles, seed: slide.id)
            }
            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        if slide.layout == .summary {
                            StorySummary(slide: slide, items: summary, colors: colors)
                        } else {
                            StoryWords(slide: slide, notice: notice, colors: colors, format: format)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 56)
                    .padding(.bottom, Spacing.lg)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                StoryMascot(slide: slide, colors: colors)
                    .padding(.bottom, -Spacing.sm)
                Color.clear.frame(height: Self.ground)
            }
            .padding(.horizontal, Spacing.xxl)
            .frame(maxWidth: 640)
        }
    }
}

/// The sky's dotted pattern and the ground's checker of tiles, with its lit top edge.
private struct StorySky: View {
    let colors: StoryColors
    let groundHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 12, dot: CGFloat = 2, tile: CGFloat = 8
            let groundTop = size.height - groundHeight
            var y: CGFloat = 5
            var dots = Path()
            while y < groundTop {
                var x: CGFloat = 5
                while x < size.width {
                    dots.addRect(CGRect(x: x, y: y, width: dot, height: dot))
                    x += step
                }
                y += step
            }
            context.fill(dots, with: .color(colors.dot))
            context.fill(Path(CGRect(x: 0, y: groundTop, width: size.width, height: groundHeight)), with: .color(colors.ground))
            var tiles = Path()
            var row = 0
            var tileY = groundTop
            while tileY < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : tile
                while x < size.width {
                    tiles.addRect(CGRect(x: x, y: tileY, width: tile, height: tile))
                    x += tile * 2
                }
                tileY += tile
                row += 1
            }
            context.fill(tiles, with: .color(colors.chip))
            context.fill(Path(CGRect(x: 0, y: groundTop, width: size.width, height: 4)), with: .color(colors.edge))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Confetti, stars, rain or an alarm light, seeded per page so they stay where they are. Nothing
/// at all with Reduce Motion.
private struct StoryParticleField: View {
    let kind: StoryParticles
    let seed: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let confetti: [Color] = [0xFDE047, 0xF472B6, 0x60A5FA, 0x34D399, 0xFB923C, 0xC4B5FD, 0xF87171].map { Color(hex: $0) }
    private static let period = 4.0

    /// Four numbers per piece, the same on every draw.
    private var pieces: [[Double]] {
        let count = switch kind {
        case .confetti: 28
        case .stars: 14
        case .rain: 30
        case .alarm: 0
        }
        var state = seed.utf8.reduce(UInt64(5381)) { $0 &* 33 &+ UInt64($1) }
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 40) / Double(1 << 24)
        }
        return (0..<count).map { _ in [next(), next(), next(), next()] }
    }

    var body: some View {
        if !reduceMotion {
            let pieces = pieces
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let t = time.truncatingRemainder(dividingBy: Self.period) / Self.period
                    draw(pieces, t: t, in: &context, size: size)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func wrapped(_ x: Double) -> Double { x - x.rounded(.down) }

    private func draw(_ pieces: [[Double]], t: Double, in context: inout GraphicsContext, size: CGSize) {
        switch kind {
        case .confetti:
            for (i, p) in pieces.enumerated() {
                let side = 6 + (p[2] * 2).rounded() * 2
                let y = wrapped(t * (1 + (p[1] * 2).rounded(.down)) + p[3]) * size.height
                let x = p[0] * size.width + (p[2] - 0.5) * 60 * sin(t * .pi * 2)
                context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(Self.confetti[i % Self.confetti.count]))
            }
        case .stars:
            for p in pieces where wrapped(t * (1 + (p[2] * 2).rounded(.down)) + p[3]) < 0.5 {
                let x = (0.04 + p[0] * 0.92) * size.width, y = (0.08 + p[1] * 0.58) * size.height, u: CGFloat = 3
                var star = Path(CGRect(x: x, y: y - u, width: u, height: u * 3))
                star.addRect(CGRect(x: x - u, y: y, width: u * 3, height: u))
                context.fill(star, with: .color(.white.opacity(0.45)))
            }
        case .rain:
            for p in pieces {
                let y = wrapped(t * (3 + (p[1] * 2).rounded(.down)) + p[3]) * size.height
                context.fill(Path(CGRect(x: p[0] * size.width, y: y, width: 2, height: 12)), with: .color(.white.opacity(0.35)))
            }
        case .alarm:
            if Int(t * 5) % 2 == 0 {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xFF2020, opacity: 0.2)))
            }
        }
    }
}

/// A page's words: the lead, the figure, its unit, a meter or a list, the body.
private struct StoryWords: View {
    let slide: RecapStoryModel.Slide
    let notice: String?
    let colors: StoryColors
    let format: any RecapFormat
    @Environment(\.strings) private var s

    private static let figure = TextStyle.numeral(64)
    private static let bigWords = TextStyle(40, 44, .heavy, tracking: -0.02, relativeTo: .largeTitle)
    private static let words = TextStyle(34, 40, .heavy, tracking: -0.02, relativeTo: .largeTitle)

    private func text(_ t: RecapStoryModel.Text) -> String { s.recap.text(t.key, t.vars) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lead = slide.lead {
                Text(text(lead))
                    .textStyle(.title3)
                    .foregroundStyle(colors.soft)
            }
            switch slide.value {
            case .count(let n, let decimals, let prefix, let suffix, let from):
                StoryCountUp(target: n, from: from, style: Self.figure, color: colors.accent) { value in
                    // Whole figures don't show their fractions while counting.
                    prefix + format.num(decimals == 0 ? value.rounded() : value, digits: decimals) + suffix
                }
            case .words(let words):
                Text(words)
                    .textStyle(slide.layout == .intro ? Self.bigWords : Self.words)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
            case nil:
                EmptyView()
            }
            if let unit = slide.unit {
                Text(text(unit))
                    .textStyle(.headline)
                    .foregroundStyle(colors.soft)
            }
            if let meter = slide.meter {
                StoryMeter(value: meter.value, limit: meter.limit, label: s.recap.text("rateLimit"), colors: colors)
            }
            if !slide.list.isEmpty {
                StoryList(rows: slide.list, colors: colors)
                    .padding(.top, Spacing.xs)
            }
            ForEach(Array(slide.body.enumerated()), id: \.offset) { _, line in
                Text(text(line))
                    .textStyle(.body)
                    .foregroundStyle(colors.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .textStyle(.footnote)
                    .foregroundStyle(colors.soft)
                    .padding(.top, Spacing.xs)
            }
        }
    }
}

/// The figure counts up, or for a ranking down, then stands. Just stands with Reduce Motion.
private struct StoryCountUp: View {
    let target: Double
    let from: Double
    let style: TextStyle
    let color: Color
    let render: (Double) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false

    var body: some View {
        CountingText(value: started || reduceMotion ? target : from, style: style, color: color, render: render)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: started)
            .onAppear { started = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(render(target))
    }
}

private struct CountingText: View, Animatable {
    var value: Double
    let style: TextStyle
    let color: Color
    let render: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(render(value))
            .textStyle(style)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// The absence rate against the limit, its label ending at the mark it names.
private struct StoryMeter: View {
    let value: Double
    let limit: Double
    let label: String
    let colors: StoryColors
    @State private var width: CGFloat = 0

    var body: some View {
        let scale = max(limit * 1.6, value)
        let mark = width * limit / scale
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ZStack(alignment: .leading) {
                Capsule().fill(colors.chip)
                Capsule()
                    .fill(value >= limit ? Color(hex: 0xEF4444) : colors.accent)
                    .frame(width: max(14, width * min(value / scale, 1)))
                Rectangle()
                    .fill(.white)
                    .frame(width: 3)
                    .offset(x: mark - 1.5)
            }
            .frame(height: 14)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            Text(label)
                .textStyle(.caption)
                .foregroundStyle(colors.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: max(0, mark + 1.5), alignment: .trailing)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct StoryList: View {
    let rows: [RecapStoryModel.ListRow]
    let colors: StoryColors
    @Environment(\.strings) private var s

    var body: some View {
        let most = rows.map(\.value).max().flatMap { $0 > 0 ? $0 : nil } ?? 1
        VStack(spacing: Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(spacing: Spacing.xs) {
                    HStack {
                        Text(row.labelKey.map { s.recap.text($0) } ?? row.label)
                            .textStyle(.callout)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.sm)
                        Text(row.display)
                            .textStyle(TextStyle.callout.weight(.bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(colors.chip)
                            Capsule()
                                .fill(colors.accent)
                                .frame(width: proxy.size.width * max(0.04, min(row.value / most, 1)))
                        }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The mascot at the page's place, with what it says in a bubble.
private struct StoryMascot: View {
    let slide: RecapStoryModel.Slide
    let colors: StoryColors
    @Environment(\.strings) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hop = 0

    private var alignment: HorizontalAlignment {
        switch slide.place {
        case .left: .leading
        case .right, .corner: .trailing
        case .bottom: .center
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: Spacing.sm) {
            if let quip = slide.quip {
                Text(s.recap.text(quip.key, quip.vars))
                    .textStyle(TextStyle.footnote.weight(.semibold))
                    .foregroundStyle(colors.accentInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(colors.accent, in: .pokyh(Radius.md))
            }
            RecapMascot(mood: slide.mood, size: 84, fill: colors.chip, ink: colors.accent)
                .symbolEffect(.bounce, value: hop)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .onAppear { if !reduceMotion { hop += 1 } }
    }
}

/// The last page: the period's figures at a glance.
private struct StorySummary: View {
    let slide: RecapStoryModel.Slide
    let items: [RecapStoryModel.SummaryItem]
    let colors: StoryColors
    @Environment(\.strings) private var s

    private static let heading = TextStyle(34, 40, .heavy, tracking: -0.02, relativeTo: .largeTitle)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .words(let title) = slide.value {
                Text(title)
                    .textStyle(Self.heading)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(s.recap.text(item.label))
                            .textStyle(.footnote)
                            .foregroundStyle(colors.soft)
                            .lineLimit(2)
                        Text(item.value)
                            .textStyle(.title2)
                            .foregroundStyle(colors.accent)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                    .background(colors.chip, in: .pokyh(Radius.md))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// ── The poster ──────────────────────────────────────────────────────────────

/// The card to keep and share: the pose, the color, which figures (up to five) and whether the
/// first name is on it. Rendered to a picture for the share sheet.
private struct RecapPosterSheet: View {
    let title: String
    let firstName: String?
    let items: [RecapStoryModel.SummaryItem]

    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var pose = RecapPoster.Pose.cool
    @State private var color = RecapPoster.colors[0]
    @State private var picked: [String] = []
    @State private var showName = true
    @State private var rendered: Image?
    @State private var copied = false

    private var website: String {
        let host = AppConfig.current.websiteURL.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var shareText: String {
        s.recap.text("shareText", ["title": title, "url": website])
    }

    private var card: RecapPosterCard {
        let shown = picked.compactMap { id in items.first { $0.id == id } }
        return RecapPosterCard(
            title: title,
            name: showName ? (firstName ?? "") : "",
            figures: shown.map { (s.recap.text($0.label), $0.value) },
            pose: pose, color: color, website: website
        )
    }

    /// Everything that changes the picture.
    private var cardKey: String { "\(pose)|\(color)|\(picked)|\(showName)" }

    var body: some View {
        let t = s.recap
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    preview
                    posePicker(t)
                    group(t.text("customizeColor")) { colorPicker }
                    group("\(t.text("customizeFigures")) · \(t.text("customizeRoom", ["n": String(RecapPoster.slots)]))") {
                        VStack(spacing: Spacing.xs) {
                            ForEach(items) { item in
                                let on = picked.contains(item.id)
                                check(t.text(item.label), value: item.value, on: on, enabled: on || picked.count < RecapPoster.slots) {
                                    picked = RecapPoster.toggled(picked, item.id)
                                }
                            }
                            if let firstName {
                                check(t.text("customizeName"), value: firstName, on: showName, enabled: true) { showName.toggle() }
                            }
                        }
                    }
                    actions(t)
                }
                .padding(Spacing.screenH)
                .frame(maxWidth: WidthClass.formMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(t.text("customize"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .onAppear {
            if picked.isEmpty { picked = Array(items.prefix(RecapPoster.slots).map(\.id)) }
        }
        .task(id: cardKey) { render() }
    }

    private func render() {
        // Fixed at the card's own size, so the picture doesn't change with the phone's settings.
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: RecapPosterCard.size.width, height: RecapPosterCard.size.height)
        rendered = renderer.uiImage.map { Image(uiImage: $0) }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if let rendered {
                rendered.resizable().scaledToFit()
            } else {
                Color(hex: color)
            }
        }
        .aspectRatio(RecapPosterCard.size.width / RecapPosterCard.size.height, contentMode: .fit)
        .frame(maxWidth: 300)
        .clipShape(.pokyh(Radius.md))
        .warmShadow(.level3)
        .accessibilityLabel(title)
    }

    private func posePicker(_ t: RecapStrings) -> some View {
        HStack(spacing: Spacing.md) {
            stepButton("chevron.left", label: s.common.back) { pose = pose.stepped(-1) }
            Text(t.text(pose.textKey))
                .textStyle(.headline)
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 120)
            stepButton("chevron.right", label: s.system.next) { pose = pose.stepped(1) }
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 44, height: 44)
                .background(Palette.cardAlt, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var colorPicker: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(RecapPoster.colors, id: \.self) { c in
                Button { color = c } label: {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(Color(hex: c))
                        .frame(height: 36)
                        .overlay {
                            if c == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color(RecapPoster.inks(c).ink))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(c == color ? .isSelected : [])
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .textStyle(TextStyle.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func check(_ label: String, value: String, on: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Palette.accent : Palette.textTertiary)
                Text(label)
                    .textStyle(.callout)
                    .foregroundStyle(enabled ? Palette.textPrimary : Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(Palette.card, in: .pokyh(Radius.sm))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func actions(_ t: RecapStrings) -> some View {
        VStack(spacing: Spacing.sm) {
            if let rendered {
                ShareLink(item: rendered, message: Text(shareText), preview: SharePreview(title, image: rendered)) {
                    ButtonLabel(t.text("share"), symbol: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
            }
            Button {
                UIPasteboard.general.string = shareText
                copied = true
            } label: {
                ButtonLabel(copied ? t.text("shareCopied") : t.text("shareCopy"), symbol: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.secondary)
        }
    }
}

/// The picture itself: the title, the first figure huge, the others on rows of their own, the
/// mascot at the bottom, all on a bold color. Sizes are fixed, it's a picture and not a screen.
private struct RecapPosterCard: View {
    static let size = CGSize(width: 360, height: 640)

    let title: String
    let name: String
    let figures: [(label: String, value: String)]
    let pose: RecapPoster.Pose
    let color: UInt32
    let website: String

    private func font(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    var body: some View {
        let inks = RecapPoster.inks(color)
        let ink = Color(inks.ink), soft = Color(inks.soft), box = Color(inks.box)
        ZStack(alignment: .bottom) {
            Color(hex: color)
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(font(32))
                    .foregroundStyle(ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if !name.isEmpty {
                    Text(name)
                        .font(font(17, .semibold))
                        .foregroundStyle(soft)
                        .lineLimit(1)
                }
                if let big = figures.first {
                    VStack(spacing: 2) {
                        Text(big.value)
                            .font(font(84, .black))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                        Text(big.label)
                            .font(font(19, .bold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                }
                ForEach(Array(figures.dropFirst().enumerated()), id: \.offset) { _, figure in
                    HStack(spacing: Spacing.sm) {
                        Text(figure.label)
                            .font(font(15, .semibold))
                            .foregroundStyle(soft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: Spacing.xs)
                        Text(figure.value)
                            .font(font(21))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 44)
                    .background(box, in: .pokyh(Radius.xs))
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.xl)
            HStack(alignment: .bottom) {
                Text(website.uppercased())
                    .font(font(13, .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RecapMascot(mood: pose.mood, size: 92, fill: box, ink: ink)
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

#if DEBUG
private enum RecapPreviewData {
    static let format = RecapFormatter(strings: .of(.de))
    static let input: RecapStoryModel.Input = {
        let subject = RecapFigures.Ranked(name: "Mathematik", value: 6000, lessons: 120)
        let school = RecapFigures.School(days: 180, lessons: 900, minutes: 45000, cancelled: 12, substitutions: 5, subjects: [subject],
                                         teachers: [.init(name: "Huber", value: 100, lessons: 100)], rooms: [.init(name: "A1", value: 50, lessons: 50)],
                                         longestDay: .init(date: 20260317, start: 465, end: 1000),
                                         earliest: .init(date: 20260302, minutes: 465), latest: .init(date: 20260317, minutes: 1000))
        let absences = RecapFigures.Absences(entries: 3, openEntries: 1, missedMinutes: 2700, excusedMinutes: 1350, possibleMinutes: 45000, rate: 6,
                                             missedDays: 2, bySubject: [.init(name: "Deutsch", value: 120, lessons: 2)], byWeekday: [0, 0, 0, 0, 2700, 0, 0])
        let untis = RecapFigures.Untis(complete: true, weeksLoaded: 40, weeksTotal: 40, school: school, absences: absences, exams: 15, homework: 40, classreg: 2)
        return RecapStoryModel.Input(title: "Dein Schuljahr", firstName: "Emanuel", periodFrom: "2025-09-08", periodTo: "2026-06-12",
                                     sections: ["school", "absences", "exams", "classreg"], untis: untis, pokyh: nil)
    }()
}

#Preview("Story page") {
    let slides = RecapStoryModel.build(RecapPreviewData.input, RecapPreviewData.format)
    GeometryReader { proxy in
        RecapPage(slide: slides[1], summary: [], notice: nil, safeBottom: proxy.safeAreaInsets.bottom, format: RecapPreviewData.format)
    }
    .background(slides[1].theme.colors.bg)
    .environment(\.strings, .of(.de))
}

#Preview("Poster") {
    RecapPosterSheet(title: "Dein Schuljahr", firstName: "Emanuel",
                     items: RecapStoryModel.summaryItems(RecapPreviewData.input, RecapPreviewData.format))
        .environment(\.strings, .of(.de))
}
#endif
