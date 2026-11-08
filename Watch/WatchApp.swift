import SwiftUI
import PokyhCore
import PokyhDesign

@main
struct POKYHWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = WatchSession.shared

    /// The language picked in the iPhone app, once the phone has said which.
    private var strings: Strings {
        Strings.of(session.snapshot?.lang ?? LanguageChoice.current(in: .standard))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if session.account != nil {
                    DayPages(session: session)
                } else {
                    SignInOnPhoneView()
                }
            }
            .environment(\.strings, strings)
            .animation(Motion.standardEase, value: session.account)
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active: session.refresh()
                case .background: session.scheduleBackgroundRefresh()
                default: break
                }
            }
        }
    }
}

/// What the watch shows until the iPhone has handed over a signed-in account.
struct SignInOnPhoneView: View {
    @Environment(\.strings) private var s

    var body: some View {
        ScrollView {
            MascotLine(look: .waving, title: s.watch.signInTitle)
        }
    }
}

// MARK: Pages

private enum Page: String, Hashable {
    case today, grades, mensa, todos

    /// Today, or in debug builds the page `-POKYHWatchPage` names, for screenshots.
    static var first: Page {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "POKYHWatchPage"), let page = Page(rawValue: name) { return page }
        #endif
        return .today
    }
}

/// Heute, Noten, Mensa and To-dos, one crown turn apart. Each says what it is beside the clock,
/// like the system's own apps; a bare "7,50" didn't say it was the grades.
struct DayPages: View {
    let session: WatchSession
    @Environment(\.strings) private var s
    @State private var page = Page.first

    var body: some View {
        TabView(selection: $page) {
            TodayPage(session: session).tag(Page.today).navigationTitle(s.common.today)
            GradesPage(session: session).tag(Page.grades).navigationTitle(s.nav.grades)
            MensaPage(session: session).tag(Page.mensa).navigationTitle(s.nav.mensa)
            TodosPage(session: session).tag(Page.todos).navigationTitle(s.tasks.todos)
        }
        .tabViewStyle(.verticalPage)
        .sensoryFeedback(.selection, trigger: page)
    }
}

extension View {
    /// A page's color fading into the watch's black. Plain black on the Always-On display.
    fileprivate func wash(_ color: Color?, for placement: ContainerBackgroundPlacement = .tabView) -> some View {
        modifier(Wash(color: color, placement: placement))
    }
}

private struct Wash: ViewModifier {
    let color: Color?
    let placement: ContainerBackgroundPlacement
    @Environment(\.isLuminanceReduced) private var dimmed

    func body(content: Content) -> some View {
        content.containerBackground(for: placement) {
            if let color, !dimmed {
                LinearGradient(colors: [color.opacity(0.42), .black], startPoint: .top, endPoint: .bottom)
            } else {
                Color.black
            }
        }
    }
}

/// A scrolling page that stops on each thing rather than anywhere in between.
private struct StoppingScroll<Content: View>: View {
    let session: WatchSession
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .refreshable { await session.reload() }
    }
}

/// The mascot and a line, for what has nothing to count.
private struct MascotLine: View {
    let look: MascotLook
    let title: String
    var size: CGFloat = 92
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        VStack(spacing: Spacing.sm) {
            MascotView(look: look, size: size)
                .opacity(dimmed ? 0.55 : 1)
                .accessibilityHidden(true)
            Text(title)
                .textStyle(.headline)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

extension MascotLook {
    fileprivate static let waving = MascotLook(pose: Mascot.Pose(arms: .wave), wave: true)
    fileprivate static let cheering = MascotLook(pose: Mascot.Pose(eyes: .happy, mouth: .grin, arms: .cheer))
    fileprivate static let thumbsUp = MascotLook(pose: Mascot.Pose(eyes: .happy, mouth: .grin, arms: .thumb))
    fileprivate static let dozing = MascotLook(pose: Mascot.Pose(eyes: .closed))
    fileprivate static let searching = MascotLook(pose: Mascot.Pose(mouth: .flat, arms: .lens))
}

/// Says how old what's on screen is, once that matters.
private struct AgeLine: View {
    let date: Date
    var away = false
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if away { Image(systemName: "iphone.slash") }
            Text(WatchFormat.stamp(date, texts: WatchTexts.of(s.lang), common: s.common))
        }
        .textStyle(.caption2)
        .foregroundStyle(Brand.warning)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }
}

/// Nothing to show on a page yet: waiting for it, or saying why it isn't coming.
private struct NothingYet: View {
    let session: WatchSession
    var date: Date?
    @Environment(\.strings) private var s

    var body: some View {
        let texts = WatchTexts.of(s.lang)
        VStack(spacing: Spacing.sm) {
            if session.loading {
                ProgressView()
                    .accessibilityLabel(s.common.loading)
            } else {
                Image(systemName: session.phoneReachable ? "iphone" : "iphone.slash")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                Text(session.phoneReachable ? texts.noDataText : texts.phoneAway)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let date, date > .distantPast { AgeLine(date: date) }
                Button(s.common.retry) {
                    Task { await session.reload() }
                }
                .buttonStyle(.glass)
                .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: Heute

private struct TodayPage: View {
    let session: WatchSession

    var body: some View {
        // Once a second up close, once a minute on the Always-On display: the system slows it down.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            TodayContent(session: session, snapshot: session.snapshot, now: context.date)
        }
    }
}

private struct TodayContent: View {
    let session: WatchSession
    let snapshot: WatchSnapshot?
    let now: Date
    @Environment(\.strings) private var s

    private var moment: WatchSnapshot.Moment { snapshot?.moment(at: now) ?? .unknown }

    private var washColor: Color? {
        switch moment {
        case .running(let lesson), .waiting(let lesson, _): lesson.tone.bar
        case .free, .over: Brand.accent
        case .unknown: nil
        }
    }

    /// The bell itself: what the page is about just moved on.
    private var bell: String {
        switch moment {
        case .running(let lesson): "running-\(lesson.id)"
        case .waiting(let lesson, _): "waiting-\(lesson.id)"
        case .free, .over, .unknown: "none"
        }
    }

    /// What's still ahead below the big lesson. What's over isn't worth a crown turn, and the
    /// follower is already on screen unless there's more to say about it.
    private var rest: [WatchSnapshot.Lesson] {
        guard let snapshot else { return [] }
        switch moment {
        case .unknown, .over:
            return []
        case .free:
            return snapshot.todaysLessons(at: now)
        case .running, .waiting:
            let follower = snapshot.follower(at: now)
            return snapshot.todaysLessons(at: now).filter { lesson in
                guard lesson.end > now, lesson != moment.lesson else { return false }
                return lesson != follower || lesson.status == .substitution || lesson.status == .roomChange
            }
        }
    }

    private var isOld: Bool {
        guard let snapshot, !session.loading else { return false }
        return snapshot.isStale(at: now) && snapshot.lessonsUpdatedAt > .distantPast
    }

    var body: some View {
        StoppingScroll(session: session) {
            first
                .containerRelativeFrame(.vertical)
            ForEach(rest) { DayRow(lesson: $0) }
        }
        .wash(washColor)
        .sensoryFeedback(.start, trigger: bell)
    }

    /// The first screen: the lesson, or what stands in for one.
    @ViewBuilder private var first: some View {
        let texts = WatchTexts.of(s.lang)
        switch moment {
        case .running, .waiting:
            if let snapshot, let lesson = moment.lesson {
                LessonHero(moment: moment, lesson: lesson, follower: snapshot.follower(at: now),
                           now: now, oldDate: isOld ? snapshot.lessonsUpdatedAt : nil, away: !session.phoneReachable)
            }
        case .over:
            quiet(.cheering, s.home.dayOver)
        case .free:
            if Calendar.current.isDateInWeekend(now) {
                quiet(.dozing, texts.weekend)
            } else {
                quiet(.waving, s.home.noLessonsToday)
            }
        case .unknown:
            NothingYet(session: session, date: snapshot?.lessonsUpdatedAt)
        }
    }

    private func quiet(_ look: MascotLook, _ title: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Spacer(minLength: 0)
            MascotLine(look: look, title: title)
            Spacer(minLength: 0)
            if isOld, let snapshot {
                AgeLine(date: snapshot.lessonsUpdatedAt, away: !session.phoneReachable)
            }
        }
    }
}

extension WatchSnapshot.Lesson {
    /// Changes wear the status color, everything else its subject's.
    fileprivate var tone: Tone {
        switch status {
        case .cancelled: .cancelled
        case .exam: .exam
        case .substitution, .roomChange: .substitution
        case .additional: .event
        case .regular: .subject(subject)
        }
    }

    /// What's different about it, in the fewest words.
    fileprivate func change(_ s: Strings) -> String? {
        let texts = WatchTexts.of(s.lang)
        switch status {
        case .regular: return nil
        case .cancelled: return s.home.cancelled
        case .exam: return s.home.exam
        case .additional: return s.home.additional
        case .substitution:
            guard let originalTeacher else { return s.home.substitution }
            return "\(teacher) \(texts.instead(originalTeacher))"
        case .roomChange:
            guard let originalRoom else { return s.home.roomChange }
            return "\(s.home.room(room)) \(texts.instead(originalRoom))"
        }
    }

    fileprivate func place(_ s: Strings) -> String {
        room.isEmpty ? teacher : s.home.room(room)
    }

    fileprivate func name(_ s: Strings) -> String {
        title.isEmpty ? s.home.lesson : title
    }
}


/// Minutes to the bell for the Always-On display and VoiceOver: no seconds there.
private func minutesLeft(_ seconds: TimeInterval, _ s: Strings) -> String {
    let minutes = max(1, Int((seconds / 60).rounded(.up)))
    if minutes < 60 { return s.home.minutes(minutes) }
    return minutes % 60 == 0 ? s.home.hours(minutes / 60) : s.home.hoursMinutes(minutes / 60, minutes % 60)
}

/// The lesson as the whole screen: a ring running out at the bell, with the corners left free
/// for the clock.
private struct LessonHero: View {
    let moment: WatchSnapshot.Moment
    let lesson: WatchSnapshot.Lesson
    let follower: WatchSnapshot.Lesson?
    let now: Date
    let oldDate: Date?
    let away: Bool
    @Environment(\.strings) private var s

    var body: some View {
        VStack(spacing: Spacing.xs) {
            CountdownRing(moment: moment, lesson: lesson, now: now)
            if let oldDate { AgeLine(date: oldDate, away: away) }
            if let change = lesson.change(s) {
                ChangeCapsule(text: change, tone: lesson.tone)
            }
            if let follower { FollowerLine(lesson: follower) }
        }
    }
}

private struct CountdownRing: View {
    let moment: WatchSnapshot.Moment
    let lesson: WatchSnapshot.Lesson
    let now: Date
    @Environment(\.strings) private var s
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    private var isRunning: Bool {
        if case .running = moment { return true }
        return false
    }

    private var bell: Date { isRunning ? lesson.end : lesson.start }

    /// Counting down, unless the first lesson is more than an hour off: then just when it starts.
    private var big: String {
        guard moment.span(at: now) != nil else { return WatchFormat.clock(lesson.start) }
        let left = bell.timeIntervalSince(now)
        return dimmed ? minutesLeft(left, s) : WatchFormat.countdown(left)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = (side * 0.08).rounded()
            let tone = lesson.tone
            ZStack {
                Dial(value: filled ? moment.remaining(at: now) ?? 0 : 0, color: tone.bar, width: line)
                    .opacity(dimmed ? 0.5 : 1)
                VStack(spacing: 0) {
                    if !isRunning {
                        Text(s.home.upNext)
                            .textStyle(.caption2)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    ViewThatFits(in: .horizontal) {
                        Text(lesson.name(s))
                        Text(lesson.subject.isEmpty ? lesson.name(s) : lesson.subject)
                    }
                    .textStyle(TextStyle.subheadline.weight(.semibold))
                    .foregroundStyle(dimmed ? Palette.textSecondary : tone.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Text(big)
                        .font(.system(size: side * (dimmed ? 0.2 : 0.26), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    // A changed room is in the capsule below.
                    if lesson.status != .roomChange {
                        Text(lesson.place(s))
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, line + Spacing.sm)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard !filled else { return }
            if reduceMotion { filled = true } else { withAnimation(Motion.smooth) { filled = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRunning ? "\(lesson.name(s)), \(lesson.place(s))" : "\(s.home.upNext): \(lesson.name(s)), \(lesson.place(s))")
        .accessibilityValue(moment.span(at: now) != nil ? s.home.left(minutesLeft(bell.timeIntervalSince(now), s)) : WatchFormat.clock(lesson.start))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A round dial: a full ring by default, a gauge with its gap at the bottom with a smaller sweep.
private struct Dial: View {
    /// 0 to 1.
    let value: Double
    let color: Color
    let width: CGFloat
    var sweep = 1.0

    var body: some View {
        let style = StrokeStyle(lineWidth: width, lineCap: .round)
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(color.opacity(0.22), style: style)
            Circle()
                .trim(from: 0, to: sweep * min(1, max(0, value)))
                .stroke(color, style: style)
        }
        .rotationEffect(.degrees(sweep < 1 ? 90 + (1 - sweep) * 180 : -90))
        .padding(width / 2)
    }
}

/// Solid, the one loud thing on the screen.
private struct ChangeCapsule: View {
    let text: String
    let tone: Tone
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        Text(text)
            .textStyle(TextStyle.caption.weight(.bold))
            .foregroundStyle(dimmed ? tone.ink : .black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Spacing.sm + Spacing.xxs)
            .padding(.vertical, Spacing.xxs + 1)
            .background(dimmed ? tone.fill : tone.bar, in: .capsule)
            .frame(maxWidth: .infinity)
    }
}

/// One line under the ring: what comes after.
private struct FollowerLine: View {
    let lesson: WatchSnapshot.Lesson
    @Environment(\.strings) private var s
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        let tone = lesson.tone
        HStack(spacing: Spacing.xs + Spacing.xxs) {
            Text(WatchFormat.clock(lesson.start))
                .monospacedDigit()
                .foregroundStyle(lesson.status == .regular ? Palette.textSecondary : tone.ink)
            Text(lesson.name(s))
                .fontWeight(.semibold)
                .foregroundStyle(lesson.status == .regular ? Palette.textPrimary : tone.ink)
                .strikethrough(lesson.isCancelled)
            if lesson.status != .regular, let change = lesson.change(s), lesson.status != .substitution, lesson.status != .roomChange {
                Text(change)
                    .fontWeight(.bold)
                    .foregroundStyle(tone.ink)
            } else if !lesson.room.isEmpty {
                Text(lesson.room)
                    .foregroundStyle(lesson.status == .regular ? Palette.textSecondary : tone.ink)
            }
        }
        .textStyle(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, lesson.status == .regular ? 0 : Spacing.sm + Spacing.xxs)
        .padding(.vertical, lesson.status == .regular ? 0 : Spacing.xxs + 1)
        .background(lesson.status == .regular || dimmed ? .clear : tone.fill, in: .capsule)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One lesson of the day. A change fills the whole row with its color.
private struct DayRow: View {
    let lesson: WatchSnapshot.Lesson
    @Environment(\.strings) private var s
    @Environment(\.isLuminanceReduced) private var dimmed

    private var detail: String {
        lesson.change(s) ?? lesson.place(s)
    }

    var body: some View {
        let tone = lesson.tone
        let changed = lesson.status != .regular
        HStack(spacing: Spacing.sm) {
            Capsule()
                .fill(tone.bar)
                .frame(width: 4)
                .padding(.vertical, Spacing.xxs)
            VStack(alignment: .leading, spacing: 0) {
                Text(lesson.name(s))
                    .textStyle(TextStyle.subheadline.weight(.semibold))
                    .foregroundStyle(changed ? tone.ink : Palette.textPrimary)
                    .strikethrough(lesson.isCancelled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !detail.isEmpty {
                    Text(detail)
                        .textStyle(changed ? TextStyle.caption.weight(.bold) : .caption)
                        .foregroundStyle(changed ? tone.ink : Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Text(WatchFormat.clock(lesson.start))
                .textStyle(.caption)
                .monospacedDigit()
                .foregroundStyle(changed ? tone.ink : Palette.textSecondary)
                .fixedSize()
        }
        .padding(.vertical, Spacing.sm)
        .padding(.leading, Spacing.sm)
        .padding(.trailing, Spacing.sm + Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(dimmed ? Color.clear : changed ? tone.fill : Color.white.opacity(0.1))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Noten

/// Marks run from 4 to 10 here, so that's what the gauge spans.
private let gaugeRange = 4.0...10.0

private struct GradesPage: View {
    let session: WatchSession
    @Environment(\.strings) private var s

    private var snapshot: WatchSnapshot? { session.snapshot }

    private var washColor: Color {
        snapshot?.overallAverage.map { Palette.grade($0) } ?? Brand.accent
    }

    var body: some View {
        StoppingScroll(session: session) {
            if let snapshot, snapshot.updatedAt > .distantPast {
                if let overall = snapshot.overallAverage {
                    OverallGauge(value: overall, count: snapshot.gradeCount)
                        .containerRelativeFrame(.vertical) { height, _ in height * 0.9 }
                    ForEach(snapshot.recentGrades.prefix(3)) { grade in
                        link(to: snapshot.subjects.first { $0.name == grade.subject }, in: snapshot) {
                            GradeRow(grade: grade, title: grade.subject)
                        }
                    }
                    if !snapshot.subjects.isEmpty {
                        Spacer().frame(height: Spacing.sm)
                        ForEach(snapshot.subjectsByAverage) { subject in
                            link(to: subject, in: snapshot) {
                                SubjectRow(subject: subject)
                            }
                        }
                    }
                } else {
                    MascotLine(look: .searching, title: s.grades.noGradesYet)
                        .containerRelativeFrame(.vertical)
                }
                PageAge(session: session, date: snapshot.updatedAt)
            } else {
                NothingYet(session: session)
                    .containerRelativeFrame(.vertical)
            }
        }
        .wash(washColor)
        .privacySensitive()
    }

    @ViewBuilder private func link<Label: View>(to subject: WatchSnapshot.SubjectAverage?, in snapshot: WatchSnapshot,
                                                @ViewBuilder label: () -> Label) -> some View {
        if let subject {
            NavigationLink {
                SubjectPage(subject: subject, grades: snapshot.grades(of: subject))
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            label()
        }
    }
}

/// A small heading, in line with the text inside the rows.
private struct Heading: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .textStyle(TextStyle.footnote.weight(.semibold))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)
            .accessibilityAddTraits(.isHeader)
    }
}

/// How old a page's data is, at its end, once it's more than half a day.
private struct PageAge: View {
    let session: WatchSession
    let date: Date

    var body: some View {
        if !session.loading, Date.now.timeIntervalSince(date) > 12 * 60 * 60 {
            AgeLine(date: date, away: !session.phoneReachable)
                .padding(.top, Spacing.xs)
        }
    }
}

private struct OverallGauge: View {
    let value: Double
    let count: Int
    @Environment(\.strings) private var s
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    private var share: Double {
        (value - gaugeRange.lowerBound) / (gaugeRange.upperBound - gaugeRange.lowerBound)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = (side * 0.09).rounded()
            ZStack {
                Dial(value: filled ? share : 0, color: Palette.grade(value), width: line, sweep: 0.75)
                    .opacity(dimmed ? 0.5 : 1)
                Text(WatchFormat.average(value, decimal: s.common.decimal))
                    .font(.system(size: side * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, line + Spacing.sm)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard !filled else { return }
            if reduceMotion { filled = true } else { withAnimation(Motion.smooth.delay(0.1)) { filled = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.home.overall)
        .accessibilityValue("\(WatchFormat.average(value, decimal: s.common.decimal)), \(s.home.fromGrades(count))")
    }
}

/// A mark on its own grade color. The ramp ends dark, so the ink depends on the mark.
private struct MarkChip: View {
    let value: Double
    let text: String
    @Environment(\.isLuminanceReduced) private var dimmed

    private var ink: Color {
        let c = IdentityColors.grade(value)
        return 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue > 0.55 ? .black : .white
    }

    var body: some View {
        Text(text)
            .textStyle(TextStyle.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(dimmed ? Palette.textPrimary : ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minWidth: 40, minHeight: 28)
            .background(Palette.grade(value).opacity(dimmed ? 0.35 : 1), in: .rect(cornerRadius: Radius.xs, style: .continuous))
    }
}

/// A row of the app's translucent kind on the page's color.
private struct Platter: ViewModifier {
    @Environment(\.isLuminanceReduced) private var dimmed

    func body(content: Content) -> some View {
        content
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(dimmed ? Color.clear : Color.white.opacity(0.1))
            }
            .contentShape(.rect(cornerRadius: Radius.md, style: .continuous))
    }
}

private func dayText(_ date: Date, _ s: Strings) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return s.common.today }
    if calendar.isDateInYesterday(date) { return s.common.yesterday }
    if calendar.isDateInTomorrow(date) { return s.common.tomorrow }
    let c = calendar.dateComponents([.day, .month], from: date)
    return s.common.dayMonthShort(c.day ?? 1, c.month ?? 1)
}

private struct GradeRow: View {
    let grade: WatchSnapshot.Grade
    let title: String
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.sm) {
            MarkChip(value: grade.value, text: WatchFormat.mark(grade.value, decimal: s.common.decimal))
            VStack(alignment: .leading, spacing: 0) {
                if !title.isEmpty {
                    Text(title)
                        .textStyle(TextStyle.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let date = grade.date {
                    Text(dayText(date, s))
                        .textStyle(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .modifier(Platter())
        .accessibilityElement(children: .combine)
    }
}

private struct SubjectRow: View {
    let subject: WatchSnapshot.SubjectAverage
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(subject.name)
                .textStyle(TextStyle.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Spacing.xs)
            MarkChip(value: subject.average, text: WatchFormat.average(subject.average, decimal: s.common.decimal))
        }
        .modifier(Platter())
        .accessibilityElement(children: .combine)
    }
}

/// One subject, its average and every grade, newest first.
private struct SubjectPage: View {
    let subject: WatchSnapshot.SubjectAverage
    let grades: [WatchSnapshot.Grade]
    @Environment(\.strings) private var s

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(subject.name)
                        .textStyle(.headline)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(WatchFormat.average(subject.average, decimal: s.common.decimal))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xs)
                .accessibilityElement(children: .combine)
                if grades.isEmpty {
                    Text(s.grades.noSingleGrades)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                }
                ForEach(grades) { grade in
                    GradeRow(grade: grade, title: grade.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .wash(Palette.grade(subject.average), for: .navigation)
        .privacySensitive()
    }
}

// MARK: Mensa

private struct MensaPage: View {
    let session: WatchSession
    @Environment(\.strings) private var s

    private var snapshot: WatchSnapshot? { session.snapshot }

    /// Only a day that isn't today needs saying.
    private func heading(_ day: Date) -> String? {
        guard !Calendar.current.isDateInToday(day) else { return nil }
        if Calendar.current.isDateInTomorrow(day) { return s.common.tomorrow }
        // Monday first, like the tables; Calendar counts Sunday as 1.
        let index = (Calendar.current.component(.weekday, from: day) + 5) % 7
        return s.common.weekdays[index]
    }

    var body: some View {
        StoppingScroll(session: session) {
            if let snapshot, snapshot.updatedAt > .distantPast {
                if let day = snapshot.mensaDay, !snapshot.dishes.isEmpty {
                    if let heading = heading(day) { Heading(heading) }
                    ForEach(snapshot.dishes) { DishRow(dish: $0) }
                } else {
                    VStack(spacing: Spacing.sm) {
                        PixelPlate(style: .pasta, seed: "empty", size: .plate, empty: true)
                            .frame(width: 84)
                            .accessibilityHidden(true)
                        Text(s.home.noMenu)
                            .textStyle(.headline)
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                PageAge(session: session, date: snapshot.updatedAt)
            } else {
                NothingYet(session: session)
                    .containerRelativeFrame(.vertical)
            }
        }
        .wash(Brand.orange)
    }
}

private struct DishRow: View {
    let dish: WatchSnapshot.Dish
    @Environment(\.strings) private var s

    private var diet: String? {
        switch dish.diet {
        case .vegan: s.home.vegan
        case .vegetarian: s.home.vegetarian
        case nil: nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Small enough on a narrow watch that long words stay whole.
            PixelPlate(style: .of(category: dish.category, tags: dish.tags), seed: dish.id, size: .plate)
                .frame(width: WKInterfaceDevice.current().screenBounds.width < 170 ? 26 : 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(dish.name)
                    .textStyle(TextStyle.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.xs) {
                    if let stars = dish.stars { Stars(value: stars) }
                    if let diet {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.success)
                            .accessibilityLabel(diet)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .modifier(Platter())
        .accessibilityElement(children: .combine)
    }
}

private struct Stars: View {
    let value: Double
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(star))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Brand.star)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.mensa.starsLabel(Int(value.rounded())))
    }

    private func symbol(_ star: Int) -> String {
        let left = value - Double(star - 1)
        if left >= 0.75 { return "star.fill" }
        return left >= 0.25 ? "star.leadinghalf.filled" : "star"
    }
}

// MARK: To-dos

private struct TodosPage: View {
    let session: WatchSession
    /// Just ticked: they stay a moment to be seen before they go.
    @State private var leaving: [String: UUID] = [:]
    @Environment(\.strings) private var s
    @Environment(\.isLuminanceReduced) private var dimmed

    private var snapshot: WatchSnapshot? { session.snapshot }

    var body: some View {
        Group {
            if let snapshot, snapshot.updatedAt > .distantPast {
                let open = snapshot.todos.filter { !$0.done || leaving[$0.id] != nil }
                let done = snapshot.todos.filter { $0.done && leaving[$0.id] == nil }
                list(open, done, in: snapshot)
            } else {
                ScrollView {
                    NothingYet(session: session)
                        .containerRelativeFrame(.vertical)
                }
            }
        }
        .wash(Brand.accent)
    }

    private func list(_ open: [WatchSnapshot.Todo], _ done: [WatchSnapshot.Todo], in snapshot: WatchSnapshot) -> some View {
        List {
            if open.isEmpty {
                MascotLine(look: .thumbsUp, title: s.home.allDone)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, Spacing.sm)
            }
            ForEach(open) { row($0) }
            Section {
                ForEach(done) { row($0) }
            }
            footer(in: snapshot)
        }
        .refreshable { await session.reload() }
    }

    @ViewBuilder private func footer(in snapshot: WatchSnapshot) -> some View {
        if !session.queue.isEmpty {
            Label(WatchTexts.of(s.lang).queued, systemImage: "clock")
                .textStyle(.caption2)
                .foregroundStyle(Brand.warning)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .listRowBackground(Color.clear)
        }
        PageAge(session: session, date: snapshot.updatedAt)
            .listRowBackground(Color.clear)
    }

    private func row(_ todo: WatchSnapshot.Todo) -> some View {
        TodoRow(todo: todo) { tick(todo) }
            .listRowBackground(rowBackground(todo))
    }

    private func rowBackground(_ todo: WatchSnapshot.Todo) -> some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(dimmed ? Color.clear : todo.isOverdue() ? Tone.cancelled.fill : Color.white.opacity(0.1))
    }

    private func tick(_ todo: WatchSnapshot.Todo) {
        guard !todo.done else {
            // Back into the list right away, ticked by mistake or not.
            WKInterfaceDevice.current().play(.click)
            withAnimation(Motion.smooth) {
                leaving[todo.id] = nil
                session.toggle(todo)
            }
            return
        }
        WKInterfaceDevice.current().play(.success)
        let mine = UUID()
        withAnimation(Motion.snappy) {
            leaving[todo.id] = mine
            session.toggle(todo)
        }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard leaving[todo.id] == mine else { return }
            withAnimation(Motion.standardEase) { leaving[todo.id] = nil }
        }
    }
}

private struct TodoRow: View {
    let todo: WatchSnapshot.Todo
    let onToggle: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        let overdue = todo.isOverdue()
        Button(action: onToggle) {
            HStack(spacing: Spacing.sm + Spacing.xxs) {
                Tick(done: todo.done, overdue: overdue)
                VStack(alignment: .leading, spacing: 0) {
                    Text(todo.title)
                        .textStyle(TextStyle.subheadline.weight(.semibold))
                        .foregroundStyle(todo.done ? Palette.textTertiary : Palette.textPrimary)
                        .strikethrough(todo.done)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let due = todo.due, !todo.done {
                        Text(dayText(due, s))
                            .textStyle(overdue ? TextStyle.caption.weight(.bold) : .caption)
                            .foregroundStyle(overdue ? Palette.dangerText : Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todo.title)
        .accessibilityValue(accessibilityValue(overdue: overdue))
    }

    private func accessibilityValue(overdue: Bool) -> String {
        if todo.done { return s.tasks.done }
        guard let due = todo.due else { return s.tasks.open }
        return overdue ? "\(s.tasks.overdue), \(dayText(due, s))" : dayText(due, s)
    }
}

/// The circle a to-do is ticked in: the check pops in with a bit of spring.
private struct Tick: View {
    let done: Bool
    let overdue: Bool
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(overdue ? Palette.dangerText : Palette.textTertiary, lineWidth: 2)
            if done {
                Circle()
                    .fill(dimmed ? Palette.textTertiary : Brand.success)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

#Preview("Signed out") {
    NavigationStack { SignInOnPhoneView() }
}
