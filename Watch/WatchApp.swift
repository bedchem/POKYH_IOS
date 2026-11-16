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

private enum Page: String, Hashable, CaseIterable {
    case today, grades, mensa, todos

    /// Today, or in debug builds the page `-POKYHWatchPage` names, for screenshots.
    static var first: Page {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "POKYHWatchPage"), let page = Page(rawValue: name) { return page }
        #endif
        return .today
    }

    /// The one a crown turn further down; the last has none.
    var below: Page? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

/// Where the end of a page leads: the next page down, from the last back up to the first.
private struct Onward {
    let title: String
    let up: Bool
    let go: () -> Void
}

/// Stundenplan, Noten, Mensa and To-dos, one crown turn apart. Each says what it is beside the
/// clock, like the system's own apps, and ends on the next one's name, so it's clear there's more.
struct DayPages: View {
    let session: WatchSession
    @Environment(\.strings) private var s
    @State private var page = Page.first

    var body: some View {
        TabView(selection: $page) {
            TodayPage(session: session, onward: onward(from: .today)).tag(Page.today)
            GradesPage(session: session, onward: onward(from: .grades)).tag(Page.grades).navigationTitle(title(.grades))
            MensaPage(session: session, onward: onward(from: .mensa)).tag(Page.mensa).navigationTitle(title(.mensa))
            TodosPage(session: session, onward: onward(from: .todos)).tag(Page.todos).navigationTitle(title(.todos))
        }
        .tabViewStyle(.verticalPage)
        .sensoryFeedback(.selection, trigger: page)
    }

    private func title(_ page: Page) -> String {
        switch page {
        case .today: s.nav.timetable
        case .grades: s.nav.grades
        case .mensa: s.nav.mensa
        case .todos: s.tasks.todos
        }
    }

    private func onward(from page: Page) -> Onward {
        let target = page.below ?? .today
        return Onward(title: title(target), up: page.below == nil) {
            withAnimation(Motion.standardEase) { self.page = target }
        }
    }
}

/// The last thing on a page: the next one by name. The crown goes there too; this says it's there.
private struct OnwardButton: View {
    let onward: Onward

    var body: some View {
        Button(action: onward.go) {
            HStack(spacing: Spacing.xs) {
                Text(onward.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: onward.up ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
            }
            .textStyle(TextStyle.footnote.weight(.semibold))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sm)
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
    let onward: Onward
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                content
                OnwardButton(onward: onward)
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

// MARK: Stundenplan

private struct TodayPage: View {
    let session: WatchSession
    let onward: Onward

    var body: some View {
        // Bells ring on the minute, and the rows count in minutes. The Always-On display gets
        // the same, so it never says more than it can keep up with.
        TimelineView(.everyMinute) { context in
            TodayContent(session: session, snapshot: session.snapshot, now: context.date, onward: onward)
        }
    }
}

/// The whole day, the running lesson marked, scrolled to what's next. Once the last one is
/// over it's the next school day's.
private struct TodayContent: View {
    let session: WatchSession
    let snapshot: WatchSnapshot?
    let now: Date
    let onward: Onward
    @Environment(\.strings) private var s

    private var plan: WatchSnapshot.Plan { snapshot?.plan(at: now) ?? .unknown }
    private var moment: WatchSnapshot.Moment { snapshot?.moment(at: now) ?? .unknown }

    /// Beside the clock: which day the list is.
    private var title: String {
        guard case .upcoming(let day) = plan else { return s.common.today }
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(day.date) { return s.common.tomorrow }
        // Monday first, like the tables; Calendar counts Sunday as 1.
        let index = (calendar.component(.weekday, from: day.date) + 5) % 7
        let ahead = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day.date).day ?? 0
        if ahead < 7 { return s.common.weekdays[index] }
        let c = calendar.dateComponents([.day, .month], from: day.date)
        return "\(s.common.weekdaysShort[index]) \(s.common.dayMonthShort(c.day ?? 1, c.month ?? 1))"
    }

    private var washColor: Color? {
        switch moment {
        case .running(let lesson), .waiting(let lesson, _): lesson.tone.bar
        case .free, .over, .unknown: plan == .unknown ? nil : Brand.accent
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

    /// What the list scrolls to: the first lesson that isn't over.
    private var focus: String? {
        switch plan {
        case .today(let lessons): lessons.first { $0.end > now }?.id
        case .upcoming(let day): day.lessons.first?.id
        case .unknown, .over, .free: nil
        }
    }

    private var isOld: Bool {
        guard let snapshot, !session.loading else { return false }
        return snapshot.isStale(at: now) && snapshot.lessonsUpdatedAt > .distantPast
    }

    var body: some View {
        ScrollViewReader { proxy in
            StoppingScroll(session: session, onward: onward) {
                if isOld, let snapshot {
                    AgeLine(date: snapshot.lessonsUpdatedAt, away: !session.phoneReachable)
                }
                list
            }
            .onAppear { jump(proxy) }
            .onChange(of: focus) { jump(proxy, animated: true) }
        }
        .navigationTitle(title)
        .wash(washColor)
        .sensoryFeedback(.start, trigger: bell)
    }

    private func jump(_ proxy: ScrollViewProxy, animated: Bool = false) {
        guard let focus else { return }
        if animated {
            withAnimation(Motion.standardEase) { proxy.scrollTo(focus, anchor: .top) }
        } else {
            proxy.scrollTo(focus, anchor: .top)
        }
    }

    @ViewBuilder private var list: some View {
        let texts = WatchTexts.of(s.lang)
        switch plan {
        case .today(let lessons):
            ForEach(lessons) { lesson in
                LessonRow(lesson: lesson, phase: phase(of: lesson), now: now).id(lesson.id)
            }
        case .upcoming(let day):
            ForEach(day.lessons) { lesson in
                LessonRow(lesson: lesson, phase: .later, now: now).id(lesson.id)
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

    private func phase(of lesson: WatchSnapshot.Lesson) -> LessonRow.Phase {
        if lesson.end <= now { return .done }
        switch moment {
        case .running(let running) where running.id == lesson.id:
            return .running
        case .waiting(let next, _) where next.id == lesson.id && moment.span(at: now) != nil:
            return .next
        default:
            return .later
        }
    }

    private func quiet(_ look: MascotLook, _ title: String) -> some View {
        MascotLine(look: look, title: title)
            .padding(.vertical, Spacing.md)
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

/// Minutes to the bell: the page counts in minutes, not seconds.
private func minutesLeft(_ seconds: TimeInterval, _ s: Strings) -> String {
    let minutes = max(1, Int((seconds / 60).rounded(.up)))
    if minutes < 60 { return s.home.minutes(minutes) }
    return minutes % 60 == 0 ? s.home.hours(minutes / 60) : s.home.hoursMinutes(minutes / 60, minutes % 60)
}

/// One lesson of the day. A change fills the row with its color, the running one is outlined
/// and shows how far it is, the next one after a break when it starts. What's over fades.
private struct LessonRow: View {
    enum Phase { case done, running, next, later }

    let lesson: WatchSnapshot.Lesson
    let phase: Phase
    let now: Date
    @Environment(\.strings) private var s
    @Environment(\.isLuminanceReduced) private var dimmed

    private var changed: Bool { lesson.status != .regular }

    /// What's different, or where. The running one says who, too.
    private var detail: String {
        if let change = lesson.change(s) { return change }
        guard phase == .running, !lesson.room.isEmpty, !lesson.teacher.isEmpty else { return lesson.place(s) }
        return "\(s.home.room(lesson.room)) · \(lesson.teacher)"
    }

    private var left: String { minutesLeft(lesson.end.timeIntervalSince(now), s) }
    private var startsIn: String { WatchTexts.of(s.lang).startsIn(minutesLeft(lesson.start.timeIntervalSince(now), s)) }

    var body: some View {
        let tone = lesson.tone
        HStack(spacing: Spacing.sm) {
            Capsule()
                .fill(tone.bar)
                .frame(width: 4)
                .padding(.vertical, Spacing.xxs)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(lesson.name(s))
                        .textStyle(TextStyle.subheadline.weight(.semibold))
                        .foregroundStyle(changed ? tone.ink : Palette.textPrimary)
                        .strikethrough(lesson.isCancelled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(WatchFormat.clock(lesson.start))
                        .textStyle(.caption)
                        .monospacedDigit()
                        .foregroundStyle(changed ? tone.ink : Palette.textSecondary)
                        .fixedSize()
                }
                if !detail.isEmpty {
                    Text(detail)
                        .textStyle(changed ? TextStyle.caption.weight(.bold) : .caption)
                        .foregroundStyle(changed ? tone.ink : Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch phase {
                case .running:
                    HStack(spacing: Spacing.xs + Spacing.xxs) {
                        ProgressBar(value: lesson.progress(at: now), color: tone.bar)
                        Text(left)
                            .textStyle(TextStyle.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize()
                    }
                    .padding(.top, Spacing.xxs)
                case .next:
                    Text(startsIn)
                        .textStyle(TextStyle.caption2.weight(.semibold))
                        .foregroundStyle(tone.ink)
                        .lineLimit(1)
                case .done, .later:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.leading, Spacing.sm)
        .padding(.trailing, Spacing.sm + Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { background(tone) }
        .opacity(phase == .done ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private func background(_ tone: Tone) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return shape
            .fill(dimmed ? Color.clear : changed || phase == .running ? tone.fill : Color.white.opacity(0.1))
            .overlay {
                if phase == .running { shape.strokeBorder(tone.bar, lineWidth: 1.5) }
            }
    }

    private var accessibilityValue: String {
        switch phase {
        case .running: s.home.left(left)
        case .next: startsIn
        case .done, .later: ""
        }
    }
}

/// How far the running lesson is.
private struct ProgressBar: View {
    /// 0 to 1.
    let value: Double
    let color: Color
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        Capsule()
            .fill(color.opacity(0.25))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color.opacity(dimmed ? 0.6 : 1))
                        .frame(width: max(geo.size.height, geo.size.width * min(1, max(0, value))))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}

// MARK: Noten

/// Marks run from 4 to 10 here, so that's what the gauge spans.
private let gaugeRange = 4.0...10.0

private struct GradesPage: View {
    let session: WatchSession
    let onward: Onward
    @Environment(\.strings) private var s

    private var snapshot: WatchSnapshot? { session.snapshot }

    private var washColor: Color {
        snapshot?.overallAverage.map { Palette.grade($0) } ?? Brand.accent
    }

    var body: some View {
        StoppingScroll(session: session, onward: onward) {
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

/// A gauge with its gap at the bottom.
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
    let onward: Onward
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
        StoppingScroll(session: session, onward: onward) {
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
    let onward: Onward
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
                    OnwardButton(onward: onward)
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
        OnwardButton(onward: onward)
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
