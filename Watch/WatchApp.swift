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
            Group {
                if session.account != nil {
                    WatchMenu(session: session)
                } else {
                    NavigationStack { SignInOnPhoneView(signedOut: session.signedOutHere) }
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

/// What the watch shows until the iPhone has handed over a signed-in account, or after the
/// account's device list signed the watch out.
struct SignInOnPhoneView: View {
    var signedOut = false
    @Environment(\.strings) private var s

    var body: some View {
        ScrollView {
            if signedOut {
                MascotLine(look: .searching, title: s.watch.signedOutTitle)
                Text(s.watch.signedOutMessage)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)
            } else {
                MascotLine(look: .waving, title: s.watch.signInTitle)
            }
        }
    }
}

// MARK: Menu

private enum Page: String, Hashable, CaseIterable {
    case today, grades, mensa, todos
}

private enum Route: Hashable {
    case page(Page)
    case dish(String)

    /// Nothing open, or in debug builds what `-POKYHWatchPage` and `-POKYHWatchDish` name, for screenshots.
    static var launch: [Route] {
        #if DEBUG
        var path: [Route] = []
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "POKYHWatchPage"), let page = Page(rawValue: name) { path.append(.page(page)) }
        if let dish = defaults.string(forKey: "POKYHWatchDish") { path.append(.dish(dish)) }
        return path
        #else
        return []
        #endif
    }
}

/// Where the app opens: the menu, and one crown turn below it the school day as a circle.
/// A row opens its page.
struct WatchMenu: View {
    let session: WatchSession
    @Environment(\.strings) private var s
    @State private var path = Route.launch
    @State private var home = Home.launch

    private enum Home: String, Hashable {
        case menu, day

        /// The menu, or in debug builds the circle with `-POKYHWatchHome day`, for screenshots.
        static var launch: Home {
            #if DEBUG
            UserDefaults.standard.string(forKey: "POKYHWatchHome").flatMap(Home.init(rawValue:)) ?? .menu
            #else
            .menu
            #endif
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $home) {
                // The rows count in minutes.
                TimelineView(.everyMinute) { context in
                    MenuList(session: session, snapshot: session.snapshot, now: context.date)
                }
                .tag(Home.menu)
                DayPage(session: session)
                    .tag(Home.day)
                    .navigationTitle(WatchTexts.of(s.lang).schoolDay)
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .page(.today): TodayPage(session: session)
                case .page(.grades): GradesPage(session: session).navigationTitle(s.nav.grades)
                case .page(.mensa): MensaPage(session: session).navigationTitle(s.nav.mensa)
                case .page(.todos): TodosPage(session: session).navigationTitle(s.tasks.todos)
                case .dish(let id): DishPage(session: session, id: id)
                }
            }
        }
    }
}

/// The app's name the way the iPhone's lock screen sets it, with the mascot.
private struct Wordmark: View {
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        HStack(spacing: Spacing.sm) {
            MascotView(look: .waving, size: 34)
                .opacity(dimmed ? 0.55 : 1)
            Text(AppConfig.appName())
                .textStyle(TextStyle.numeral(26))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppConfig.appName())
        .accessibilityAddTraits(.isHeader)
    }
}

private struct MenuList: View {
    let session: WatchSession
    let snapshot: WatchSnapshot?
    let now: Date
    @Environment(\.strings) private var s

    private var known: WatchSnapshot? {
        guard let snapshot, snapshot.knowsAnything else { return nil }
        return snapshot
    }

    var body: some View {
        List {
            Wordmark()
                .listRowBackground(Color.clear)
            if session.hasUntis {
                NavigationLink(value: Route.page(.today)) {
                    let line = timetableLine
                    MenuRow(symbol: "calendar", tone: Decorative.periwinkle, title: s.nav.timetable, info: line?.text, infoTint: line?.tint) {
                        EmptyView()
                    }
                }
            }
            NavigationLink(value: Route.page(.mensa)) {
                MenuRow(symbol: "fork.knife", tone: Decorative.butter, title: s.nav.mensa, info: mensaLine) {
                    EmptyView()
                }
            }
            if session.hasTodos {
                NavigationLink(value: Route.page(.todos)) {
                    let next = nextTodo
                    MenuRow(symbol: "checklist", tone: Decorative.blush, title: s.tasks.todos, info: next?.title,
                            infoTint: next?.isOverdue(at: now) == true ? Palette.dangerText : nil) {
                        if let open = known?.openTodos.count, open > 0 {
                            Text("\(open)")
                                .textStyle(TextStyle.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                }
            }
            if session.hasUntis {
                NavigationLink(value: Route.page(.grades)) {
                    MenuRow(symbol: "graduationcap.fill", tone: Decorative.sage, title: s.nav.grades, info: latestGrade, sensitive: true) {
                        if let average = known?.overallAverage {
                            MarkChip(value: average, text: WatchFormat.average(average, decimal: s.common.decimal))
                        }
                    }
                }
            }
            if session.loading || known == nil {
                MenuFooter(session: session)
                    .listRowBackground(Color.clear)
            }
        }
        .refreshable { await session.reload() }
        .wash(Brand.accent, for: .tabView)
    }

    /// The lesson of the moment and its room, or what stands in for one.
    private var timetableLine: (text: String, tint: Color?)? {
        guard let snapshot else { return nil }
        let texts = WatchTexts.of(s.lang)
        let moment = snapshot.moment(at: now)
        switch snapshot.plan(at: now) {
        case .today:
            guard let lesson = moment.lesson else { return nil }
            let tint: Color? = lesson.status == .regular ? nil : lesson.tone.ink
            let what = [lesson.name(s), lesson.room].filter { !$0.isEmpty }.joined(separator: " · ")
            if case .running = moment {
                return ("\(what) · \(s.home.left(minutesLeft(lesson.end.timeIntervalSince(now), s)))", tint)
            }
            let when = moment.span(at: now) != nil
                ? texts.startsIn(minutesLeft(lesson.start.timeIntervalSince(now), s))
                : WatchFormat.clock(lesson.start)
            return ("\(what) · \(when)", tint)
        case .upcoming(let day):
            guard let first = day.lessons.first else { return nil }
            return ("\(dayTitle(day.date, now: now, s)) · \(WatchFormat.clock(first.start))", nil)
        case .over:
            return (s.home.dayOver, nil)
        case .free:
            return (Calendar.current.isDateInWeekend(now) ? texts.weekend : s.home.noLessonsToday, nil)
        case .unknown:
            return nil
        }
    }

    private var latestGrade: String? {
        guard let grade = known?.recentGrades.first else { return nil }
        let mark = WatchFormat.mark(grade.value, decimal: s.common.decimal)
        return grade.subject.isEmpty ? mark : "\(grade.subject) · \(mark)"
    }

    private var mensaLine: String? {
        guard let known else { return nil }
        guard let dish = known.dishes.first else { return s.home.noMenu }
        guard let day = known.mensaDay, !Calendar.current.isDateInToday(day) else { return dish.name }
        return "\(dayTitle(day, now: now, s)) · \(dish.name)"
    }

    /// The one due first; without dates, the top of the list.
    private var nextTodo: WatchSnapshot.Todo? {
        guard let open = known?.openTodos, !open.isEmpty else { return nil }
        return open.filter { $0.due != nil }.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) } ?? open.first
    }
}

/// One way into a page: its sign, its name and the line worth a glance.
private struct MenuRow<Trailing: View>: View {
    let symbol: String
    let tone: Tone
    let title: String
    let info: String?
    var infoTint: Color?
    /// Grades: hidden while the wrist is down, the name of the page stays.
    var sensitive = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.sm + Spacing.xxs) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone.ink)
                .frame(width: 32, height: 32)
                .background(tone.fill, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .textStyle(TextStyle.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let info, !info.isEmpty {
                    Text(info)
                        .textStyle(.caption)
                        .foregroundStyle(infoTint ?? Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitive(sensitive)
                }
            }
            Spacer(minLength: 0)
            trailing
                .privacySensitive(sensitive)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// Under the menu while nothing has come yet.
private struct MenuFooter: View {
    let session: WatchSession
    @Environment(\.strings) private var s

    var body: some View {
        let texts = WatchTexts.of(s.lang)
        HStack(spacing: Spacing.xs) {
            if session.loading {
                ProgressView()
                    .frame(width: 18, height: 18)
                    .accessibilityLabel(s.common.loading)
            } else {
                Image(systemName: session.connection.symbol)
                    .accessibilityHidden(true)
                Text(session.connection == .offline ? s.common.noConnection : texts.noDataText(AppConfig.appName()))
            }
        }
        .textStyle(.caption)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity)
    }
}

/// "Morgen", a weekday within the week, a date further off.
private func dayTitle(_ date: Date, now: Date, _ s: Strings) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) { return s.common.today }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
        return s.common.tomorrow
    }
    // Monday first, like the tables; Calendar counts Sunday as 1.
    let index = (calendar.component(.weekday, from: date) + 5) % 7
    let ahead = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    if (0..<7).contains(ahead) { return s.common.weekdays[index] }
    let c = calendar.dateComponents([.day, .month], from: date)
    return "\(s.common.weekdaysShort[index]) \(s.common.dayMonthShort(c.day ?? 1, c.month ?? 1))"
}

extension View {
    /// A page's color fading into the watch's black. Plain black on the Always-On display.
    fileprivate func wash(_ color: Color?, for placement: ContainerBackgroundPlacement = .navigation) -> some View {
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
    /// No way to anything newer right now: says why it's old.
    var offline = false
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if offline {
                Image(systemName: WatchSession.Connection.offline.symbol)
                    .accessibilityLabel(s.common.noConnection)
            }
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
                Image(systemName: session.connection.symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                Text(session.connection == .offline ? s.common.noConnection : texts.noDataText(AppConfig.appName()))
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

    var body: some View {
        // Bells ring on the minute, and the rows count in minutes. The Always-On display gets
        // the same, so it never says more than it can keep up with.
        TimelineView(.everyMinute) { context in
            TodayContent(session: session, snapshot: session.snapshot, now: context.date)
        }
    }
}

/// The whole day, the running lesson marked, scrolled to what's next. Once the last one is
/// over it's the next school day's.
private struct TodayContent: View {
    let session: WatchSession
    let snapshot: WatchSnapshot?
    let now: Date
    @Environment(\.strings) private var s

    private var plan: WatchSnapshot.Plan { snapshot?.plan(at: now) ?? .unknown }
    private var moment: WatchSnapshot.Moment { snapshot?.moment(at: now) ?? .unknown }

    /// Beside the clock: which day the list is.
    private var title: String {
        guard case .upcoming(let day) = plan else { return s.common.today }
        return dayTitle(day.date, now: now, s)
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
            StoppingScroll(session: session) {
                if isOld, let snapshot {
                    AgeLine(date: snapshot.lessonsUpdatedAt, offline: session.connection == .offline)
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

// MARK: Schultag

/// The school day as a circle running out, one stretch per lesson in its color.
private struct DayPage: View {
    let session: WatchSession

    var body: some View {
        TimelineView(.everyMinute) { context in
            DayContent(session: session, snapshot: session.snapshot, now: context.date)
        }
    }
}

private struct DayContent: View {
    let session: WatchSession
    let snapshot: WatchSnapshot?
    let now: Date
    @Environment(\.strings) private var s

    private var plan: WatchSnapshot.Plan { snapshot?.plan(at: now) ?? .unknown }
    private var call: WatchSnapshot.RoomCall? { snapshot?.roomCall(at: now) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .wash(call?.lesson.tone.bar ?? (plan == .unknown ? nil : Brand.accent), for: .tabView)
    }

    @ViewBuilder private var content: some View {
        let texts = WatchTexts.of(s.lang)
        switch plan {
        case .today(let lessons):
            if let span = WatchSnapshot.daySpan(of: lessons) {
                DayDial(span: span, day: nil, now: now, call: call)
            } else {
                MascotLine(look: .waving, title: s.home.noLessonsToday)
            }
        case .upcoming(let day):
            if let span = WatchSnapshot.daySpan(of: day.lessons) {
                DayDial(span: span, day: day.date, now: now, call: nil)
            } else {
                MascotLine(look: .waving, title: s.home.noLessonsToday)
            }
        case .over:
            MascotLine(look: .cheering, title: s.home.dayOver)
        case .free:
            MascotLine(look: .dozing, title: Calendar.current.isDateInWeekend(now) ? texts.weekend : s.home.noLessonsToday)
        case .unknown:
            NothingYet(session: session, date: snapshot?.lessonsUpdatedAt)
        }
    }
}

/// The circle: what's left of the day bright, what's over faded, a dot at the moment. In the
/// middle how long school still goes, under it the room that matters now.
private struct DayDial: View {
    let span: WatchSnapshot.DaySpan
    /// The day it shows when that isn't today.
    let day: Date?
    let now: Date
    let call: WatchSnapshot.RoomCall?
    @Environment(\.strings) private var s
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    private var texts: WatchTexts { .of(s.lang) }
    private var running: Bool { day == nil && span.start <= now && now < span.end }
    private var elapsed: Double { day == nil ? span.elapsed(at: now) : 0 }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let line = (side * 0.085).rounded()
                ZStack {
                    ring(side: side, line: line)
                    middle(side: side)
                        .padding(.horizontal, line + Spacing.sm)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let room {
                room
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, Spacing.sm)
            }
        }
        .onAppear {
            guard !filled else { return }
            if reduceMotion { filled = true } else { withAnimation(Motion.smooth) { filled = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texts.schoolDay)
        .accessibilityValue(accessibilityValue)
    }

    private func ring(side: CGFloat, line: CGFloat) -> some View {
        // A sliver between lessons, so back-to-back ones stay apart.
        let gap = 0.006
        let style = StrokeStyle(lineWidth: line, lineCap: .butt)
        return ZStack {
            ForEach(span.lessons) { lesson in
                let share = span.share(of: lesson)
                let from = share.lowerBound + gap
                let to = max(from, share.upperBound - gap)
                let left = min(to, max(from, elapsed))
                Circle()
                    .trim(from: from, to: to)
                    .stroke(lesson.tone.bar.opacity(0.22), style: style)
                Circle()
                    .trim(from: left, to: filled ? to : left)
                    .stroke(lesson.tone.bar, style: style)
            }
            if running {
                Circle()
                    .fill(Palette.textPrimary)
                    .overlay { Circle().stroke(.black, lineWidth: 2) }
                    .frame(width: line * 1.2, height: line * 1.2)
                    .offset(x: (side - line) / 2)
                    .rotationEffect(.degrees(elapsed * 360))
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(line / 2)
        .opacity(dimmed ? 0.55 : 1)
    }

    @ViewBuilder private func middle(side: CGFloat) -> some View {
        VStack(spacing: 0) {
            if let day {
                caption(dayTitle(day, now: now, s))
            } else if !running {
                caption(s.common.today)
            }
            big(side: side)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Palette.textPrimary)
            caption(texts.until(WatchFormat.clock(span.end)))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .textStyle(.caption)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// While school runs, how long it still goes; before, when it starts.
    private func big(side: CGFloat) -> Text {
        let number = Font.system(size: side * (dimmed ? 0.2 : 0.24), weight: .bold, design: .rounded).monospacedDigit()
        let unit = Font.system(size: side * 0.1, weight: .semibold, design: .rounded)
        guard running else { return Text(WatchFormat.clock(span.start)).font(number) }
        let minutes = max(1, Int((span.end.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 {
            return Text("\(Text(verbatim: "\(minutes)").font(number)) \(Text(texts.minuteUnit).font(unit))")
        }
        let clock = String(format: "%d:%02d", minutes / 60, minutes % 60)
        return Text("\(Text(verbatim: clock).font(number)) \(Text(texts.hourUnit).font(unit))")
    }

    /// The room that matters now, or the first one of a day still to come.
    private var room: Text? {
        let lesson = call?.lesson ?? (running ? nil : span.lessons.first)
        guard let lesson else { return nil }
        var parts = [lesson.name(s), lesson.room].filter { !$0.isEmpty }
        if let call, day == nil {
            parts.append(call.isNow
                ? s.home.left(minutesLeft(lesson.end.timeIntervalSince(now), s))
                : texts.startsIn(minutesLeft(lesson.start.timeIntervalSince(now), s)))
        }
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(lesson.status == .regular ? Palette.textPrimary : lesson.tone.ink)
    }

    private var accessibilityValue: String {
        let until = texts.until(WatchFormat.clock(span.end))
        guard running else { return "\(WatchFormat.clock(span.start)), \(until)" }
        return "\(s.home.left(minutesLeft(span.end.timeIntervalSince(now), s))), \(until)"
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
            if let snapshot, snapshot.knows(.grades) {
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
                PageAge(session: session, date: snapshot.updated(.grades))
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
            AgeLine(date: date, offline: session.connection == .offline)
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
        .wash(Palette.grade(subject.average))
        .privacySensitive()
    }
}

// MARK: Mensa

private struct MensaPage: View {
    let session: WatchSession
    @Environment(\.strings) private var s

    private var snapshot: WatchSnapshot? { session.snapshot }

    var body: some View {
        StoppingScroll(session: session) {
            if let snapshot, snapshot.knows(.mensa) {
                if let day = snapshot.mensaDay, !snapshot.dishes.isEmpty {
                    // Only a day that isn't today needs saying.
                    if !Calendar.current.isDateInToday(day) { Heading(dayTitle(day, now: .now, s)) }
                    ForEach(snapshot.dishes) { dish in
                        NavigationLink(value: Route.dish(dish.id)) {
                            DishRow(dish: dish)
                        }
                        .buttonStyle(.plain)
                    }
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
                PageAge(session: session, date: snapshot.updated(.mensa))
            } else {
                NothingYet(session: session)
                    .containerRelativeFrame(.vertical)
            }
        }
        .onAppear {
            RemotePhotos.prefetch(snapshot?.dishes.compactMap(\.photo) ?? [])
        }
        .wash(Brand.orange)
    }
}

extension WatchSnapshot.Dish {
    fileprivate func diet(_ s: Strings) -> String? {
        switch diet {
        case .vegan: s.home.vegan
        case .vegetarian: s.home.vegetarian
        case nil: nil
        }
    }

    fileprivate var plate: PixelPlate {
        PixelPlate(style: .of(category: category, tags: tags), seed: id, size: .plate)
    }
}

/// The dish's photo in a circle; its pixel plate while the photo loads, or without one.
private struct DishThumb: View {
    let dish: WatchSnapshot.Dish
    let side: CGFloat

    var body: some View {
        if let photo = dish.photo {
            RemotePhoto(url: photo, maxPixel: Int(side * 2)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                dish.plate.padding(side * 0.08)
            }
            .frame(width: side, height: side)
            .clipShape(.circle)
            .accessibilityHidden(true)
        } else {
            dish.plate
                .frame(width: side)
                .accessibilityHidden(true)
        }
    }
}

private struct DishRow: View {
    let dish: WatchSnapshot.Dish
    @Environment(\.strings) private var s

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Small enough on a narrow watch that long words stay whole.
            DishThumb(dish: dish, side: WKInterfaceDevice.current().screenBounds.width < 170 ? 32 : 42)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(dish.name)
                    .textStyle(TextStyle.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.xs) {
                    if let stars = dish.stars { Stars(value: stars) }
                    if let diet = dish.diet(s) {
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

/// One dish: its photo as wide as the screen, tap for the whole screen, then what there is to know.
private struct DishPage: View {
    let session: WatchSession
    let id: String
    @State private var showsPhoto = DishPage.launchesWithPhoto
    @Environment(\.strings) private var s

    private var dish: WatchSnapshot.Dish? {
        session.snapshot?.dishes.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            if let dish {
                details(dish)
            } else {
                Text(s.mensa.dishNotFound)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .navigationTitle(dish.map { $0.category.isEmpty ? s.mensa.dish : $0.category } ?? s.nav.mensa)
        .wash(Brand.orange)
        .fullScreenCover(isPresented: $showsPhoto) {
            if let dish, let photo = dish.photo {
                PhotoViewer(url: photo, name: dish.name)
            }
        }
    }

    private func details(_ dish: WatchSnapshot.Dish) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            hero(dish)
            Text(dish.name)
                .textStyle(.headline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let stars = dish.stars {
                HStack(spacing: Spacing.xs) {
                    Stars(value: stars)
                    if let count = dish.ratings, count > 0 {
                        Text(count == 1 ? s.mensa.ratingOne : s.mensa.ratingMany(count))
                            .textStyle(.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            if let diet = dish.diet(s) {
                Label(diet, systemImage: "leaf.fill")
                    .textStyle(TextStyle.caption.weight(.semibold))
                    .foregroundStyle(Brand.success)
            }
            if let facts = facts(dish) {
                Text(facts)
                    .textStyle(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            if let text = dish.text {
                Text(text)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func hero(_ dish: WatchSnapshot.Dish) -> some View {
        if let photo = dish.photo {
            Button { showsPhoto = true } label: {
                Color.white.opacity(0.08)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        RemotePhoto(url: photo, maxPixel: 480) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                    }
                    .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .padding(Spacing.xs + Spacing.xxs)
                            .glassEffect(.regular, in: .circle)
                            .padding(Spacing.xs)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dish.name)
            .accessibilityAddTraits(.isImage)
        } else {
            dish.plate
                .frame(width: 84)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }

    /// Kilocalories and price, where the Mensa gives them.
    private func facts(_ dish: WatchSnapshot.Dish) -> String? {
        var parts: [String] = []
        if let calories = dish.calories { parts.append(DishFormat.energy(calories, lang: s.lang)) }
        if let price = dish.price { parts.append(DishFormat.price(price, currency: AppConfig.currencyCode(), lang: s.lang)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Debug builds open the photo right away with `-POKYHWatchPhoto YES`, for screenshots.
    private static var launchesWithPhoto: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "POKYHWatchPhoto")
        #else
        false
        #endif
    }
}

/// The photo over the whole screen. The crown zooms, a finger moves it around, a double tap
/// zooms in or back out.
private struct PhotoViewer: View {
    let url: URL
    let name: String
    @State private var zoom = 1.0
    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            RemotePhoto(url: url, maxPixel: 1000) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .offset(clamped(offset, in: geo.size))
            } placeholder: {
                ProgressView()
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard zoom > 1 else { return }
                        offset = CGSize(width: dragStart.width + value.translation.width,
                                        height: dragStart.height + value.translation.height)
                    }
                    .onEnded { _ in
                        offset = clamped(offset, in: geo.size)
                        dragStart = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(Motion.standardEase) {
                    zoom = zoom > 1.05 ? 1 : 2.5
                    offset = .zero
                    dragStart = .zero
                }
            }
        }
        .ignoresSafeArea()
        .background(.black)
        .focusable()
        .digitalCrownRotation($zoom, from: 1, through: 4, by: 0.05, sensitivity: .low,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: zoom) {
            guard zoom <= 1.01 else { return }
            withAnimation(Motion.standardEase) {
                offset = .zero
                dragStart = .zero
            }
        }
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isImage)
    }

    /// Never further than the zoomed photo reaches past the screen.
    private func clamped(_ offset: CGSize, in size: CGSize) -> CGSize {
        let x = size.width * (zoom - 1) / 2, y = size.height * (zoom - 1) / 2
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
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
            if let snapshot, snapshot.knows(.todos) {
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
        PageAge(session: session, date: snapshot.updated(.todos))
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
