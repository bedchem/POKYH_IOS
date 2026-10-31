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
            VStack(spacing: Spacing.md) {
                IconTile("iphone", color: Brand.accent, size: 48)
                Text(s.watch.signInTitle)
                    .textStyle(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(s.watch.signInMessage)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.sm)
        }
        .navigationTitle("POKYH")
    }
}

// MARK: Pages

/// Heute, Noten, Mensa and To-dos, one crown turn apart.
struct DayPages: View {
    let session: WatchSession

    var body: some View {
        TabView {
            TodayPage(snapshot: session.snapshot, loading: session.loading)
            GradesPage(snapshot: session.snapshot, loading: session.loading)
            MensaPage(snapshot: session.snapshot, loading: session.loading)
            TodosPage(session: session)
        }
        .tabViewStyle(.verticalPage)
    }
}

/// A page's frame: scrolls on its own and sits on the app's dark canvas.
private struct WatchPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .containerBackground(Palette.bg, for: .tabView)
    }
}

/// A small heading, in line with the text inside the cards rather than their edge.
private struct PageEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        EyebrowLabel(text)
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.xs)
    }
}

/// How old what's on the page is, so nobody mistakes last night for now.
private struct UpdatedLine: View {
    let date: Date
    var source: WatchSnapshot.Source? = nil
    @Environment(\.strings) private var s

    var body: some View {
        let texts = WatchTexts.of(s.lang)
        let stamp = WatchFormat.stamp(date, texts: texts, common: s.common)
        let from = source.map { $0 == .watch ? texts.fromWatch : texts.fromPhone }
        Text([stamp, from].compactMap { $0 }.joined(separator: " · "))
            .textStyle(.caption2)
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, Spacing.xs)
    }
}

private struct EmptyPage: View {
    let symbol: String
    let title: String
    var text: String? = nil
    var color: Color = Brand.accent

    var body: some View {
        VStack(spacing: Spacing.sm) {
            IconTile(symbol, color: color, size: 40)
            Text(title)
                .textStyle(TextStyle.footnote.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            if let text {
                Text(text)
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
    }
}

/// Nothing from the phone yet.
private struct WaitingPage: View {
    let loading: Bool
    @Environment(\.strings) private var s

    var body: some View {
        let texts = WatchTexts.of(s.lang)
        if loading {
            VStack(spacing: Spacing.sm) {
                ProgressView()
                Text(s.common.loading)
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
        } else {
            EmptyPage(symbol: "iphone", title: texts.noDataTitle, text: texts.noDataText)
        }
    }
}

// MARK: Heute

private struct TodayPage: View {
    let snapshot: WatchSnapshot?
    let loading: Bool
    @Environment(\.strings) private var s

    var body: some View {
        WatchPage(title: s.home.sectionToday) {
            // Now and next move on by themselves while the page is open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    content(at: context.date)
                }
            }
        }
    }

    @ViewBuilder private func content(at now: Date) -> some View {
        if let snapshot, snapshot.knowsToday(at: now) {
            let lessons = snapshot.todaysLessons(at: now)
            if lessons.isEmpty {
                EmptyPage(symbol: "sun.max.fill", title: s.home.noLessonsToday, color: Brand.warning)
            } else {
                if let lesson = snapshot.upcoming(at: now) {
                    NowCard(lesson: lesson, running: snapshot.current(at: now) != nil, now: now)
                } else if snapshot.dayIsOver(at: now) {
                    Text(s.home.dayOver)
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
                ForEach(lessons) { LessonRow(lesson: $0, now: now) }
            }
            UpdatedLine(date: snapshot.lessonsUpdatedAt, source: snapshot.source)
        } else {
            WaitingPage(loading: loading)
            if let snapshot, snapshot.updatedAt > .distantPast {
                UpdatedLine(date: snapshot.lessonsUpdatedAt > .distantPast ? snapshot.lessonsUpdatedAt : snapshot.updatedAt)
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

    fileprivate func badge(_ s: Strings) -> String? {
        switch status {
        case .regular: nil
        case .cancelled: s.home.cancelled
        case .exam: s.home.exam
        case .substitution: s.home.substitution
        case .roomChange: s.home.roomChange
        case .additional: s.home.additional
        }
    }

    /// Room and teacher, and what they replaced where that's the news.
    fileprivate func detail(_ s: Strings) -> String {
        let texts = WatchTexts.of(s.lang)
        var parts: [String] = []
        if !room.isEmpty { parts.append(room) }
        if !teacher.isEmpty { parts.append(teacher) }
        if status == .substitution, let originalTeacher { parts.append(texts.instead(originalTeacher)) }
        if status == .roomChange, let originalRoom { parts.append(texts.instead(originalRoom)) }
        return parts.joined(separator: " · ")
    }
}

/// The lesson running now or coming next, big enough to read in passing.
private struct NowCard: View {
    let lesson: WatchSnapshot.Lesson
    let running: Bool
    let now: Date
    @Environment(\.strings) private var s

    private var countdown: String {
        if running { return s.home.left(duration(lesson.end.timeIntervalSince(now))) }
        return s.home.inTime(duration(lesson.start.timeIntervalSince(now)), WatchFormat.clock(lesson.start))
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return s.home.minutes(minutes) }
        return minutes % 60 == 0 ? s.home.hours(minutes / 60) : s.home.hoursMinutes(minutes / 60, minutes % 60)
    }

    var body: some View {
        let tone = lesson.tone
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text((running ? s.home.now : s.home.upNext).uppercased())
                .textStyle(.badgeChip)
                .foregroundStyle(tone.ink.opacity(0.75))
            Text(lesson.title)
                .textStyle(.headline)
                .foregroundStyle(tone.ink)
                .lineLimit(2)
            if !lesson.detail(s).isEmpty {
                Text(lesson.detail(s))
                    .textStyle(.caption)
                    .foregroundStyle(tone.ink.opacity(0.85))
                    .lineLimit(2)
            }
            Text(countdown)
                .textStyle(.caption)
                .monospacedDigit()
                .foregroundStyle(tone.ink)
            if running {
                ProgressView(value: lesson.progress(at: now))
                    .tint(tone.bar)
                    .padding(.top, Spacing.xxs)
            }
        }
        .padding(Spacing.sm + Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.fill, in: .pokyh(Radius.sm))
    }
}

private struct LessonRow: View {
    let lesson: WatchSnapshot.Lesson
    let now: Date
    @Environment(\.strings) private var s

    private var isPast: Bool { lesson.end <= now }

    var body: some View {
        let tone = lesson.tone
        HStack(spacing: Spacing.sm) {
            Capsule()
                .fill(tone.bar)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.xs) {
                    Text("\(WatchFormat.clock(lesson.start))–\(WatchFormat.clock(lesson.end))")
                        .textStyle(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    if let badge = lesson.badge(s) {
                        MiniBadge(badge, color: tone.bar)
                    }
                }
                Text(lesson.title)
                    .textStyle(TextStyle.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .strikethrough(lesson.isCancelled)
                    .lineLimit(1)
                if !lesson.detail(s).isEmpty {
                    Text(lesson.detail(s))
                        .textStyle(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, Spacing.xs + Spacing.xxs)
        .padding(.horizontal, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .pokyh(Radius.sm))
        .opacity(isPast ? 0.55 : 1)
    }
}

// MARK: Noten

private struct GradesPage: View {
    let snapshot: WatchSnapshot?
    let loading: Bool
    @Environment(\.strings) private var s

    var body: some View {
        WatchPage(title: s.grades.tab) {
            if let snapshot, snapshot.updatedAt > .distantPast {
                if let overall = snapshot.overallAverage {
                    OverallCard(value: overall, count: snapshot.gradeCount)
                    if !snapshot.recentGrades.isEmpty {
                        PageEyebrow(s.grades.recentTitle)
                        ForEach(snapshot.recentGrades) { RecentGradeRow(grade: $0) }
                    }
                    if !snapshot.subjects.isEmpty {
                        PageEyebrow(s.grades.subjects)
                        ForEach(snapshot.subjects) { SubjectRow(subject: $0) }
                    }
                } else {
                    EmptyPage(symbol: "graduationcap.fill", title: s.grades.noGradesYet, color: Brand.success)
                }
                UpdatedLine(date: snapshot.updatedAt)
            } else {
                WaitingPage(loading: loading)
            }
        }
    }
}

private struct OverallCard: View {
    let value: Double
    let count: Int
    @Environment(\.strings) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(s.home.overall.uppercased())
                .textStyle(.badgeChip)
                .foregroundStyle(Palette.textTertiary)
            Text(WatchFormat.average(value, decimal: s.common.decimal))
                .textStyle(.statMedium)
                .foregroundStyle(Palette.grade(value))
            Text(s.home.fromGrades(count))
                .textStyle(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Spacing.sm + Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .pokyh(Radius.sm))
    }
}

/// The web's mark tones: sage from 6, butter above 4, blush at 4 and below.
private func markTone(_ value: Double) -> Tone {
    value >= 6 ? Decorative.sage : value > 4 ? Decorative.butter : Decorative.blush
}

private struct RecentGradeRow: View {
    let grade: WatchSnapshot.Grade
    @Environment(\.strings) private var s

    private var when: String? {
        guard let date = grade.date else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return s.common.today }
        if calendar.isDateInYesterday(date) { return s.common.yesterday }
        let c = calendar.dateComponents([.day, .month], from: date)
        return s.common.dayMonthShort(c.day ?? 1, c.month ?? 1)
    }

    var body: some View {
        let tone = markTone(grade.value)
        HStack(spacing: Spacing.sm) {
            Text(WatchFormat.mark(grade.value, decimal: s.common.decimal))
                .textStyle(.statSmall)
                .foregroundStyle(tone.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 36, height: 32)
                .background(tone.fill, in: .pokyh(Radius.xs))
            VStack(alignment: .leading, spacing: 0) {
                Text(grade.subject)
                    .textStyle(TextStyle.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let when {
                    Text(when)
                        .textStyle(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.xs + Spacing.xxs)
        .background(Palette.card, in: .pokyh(Radius.sm))
    }
}

private struct SubjectRow: View {
    let subject: WatchSnapshot.SubjectAverage
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(subject.name)
                .textStyle(.footnote)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Spacing.xs)
            Text(WatchFormat.average(subject.average, decimal: s.common.decimal))
                .textStyle(TextStyle.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Palette.grade(subject.average))
        }
        .padding(.horizontal, Spacing.sm + Spacing.xxs)
        .padding(.vertical, Spacing.xs + Spacing.xxs)
        .background(Palette.card, in: .pokyh(Radius.sm))
    }
}

// MARK: Mensa

private struct MensaPage: View {
    let snapshot: WatchSnapshot?
    let loading: Bool
    @Environment(\.strings) private var s

    /// Today's menu, or the next day's with its weekday.
    private func heading(_ day: Date) -> String {
        guard !Calendar.current.isDateInToday(day) else { return s.home.mensaToday }
        // Monday first, like the tables; Calendar counts Sunday as 1.
        let index = (Calendar.current.component(.weekday, from: day) + 5) % 7
        return "\(s.home.mensaNext) · \(s.common.weekdays[index])"
    }

    var body: some View {
        WatchPage(title: s.nav.mensa) {
            if let snapshot, snapshot.updatedAt > .distantPast {
                if let day = snapshot.mensaDay, !snapshot.dishes.isEmpty {
                    PageEyebrow(heading(day))
                    ForEach(snapshot.dishes) { DishRow(dish: $0) }
                } else {
                    EmptyPage(symbol: "fork.knife", title: s.home.noMenu, color: Brand.orange)
                }
                UpdatedLine(date: snapshot.updatedAt)
            } else {
                WaitingPage(loading: loading)
            }
        }
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
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if !dish.category.isEmpty {
                Text(dish.category.uppercased())
                    .textStyle(.badgeChip)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Text(dish.name)
                .textStyle(TextStyle.footnote.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(3)
            if let diet {
                MiniBadge(diet, symbol: "leaf.fill", color: Brand.success)
            }
        }
        .padding(Spacing.sm + Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .pokyh(Radius.sm))
    }
}

// MARK: To-dos

private struct TodosPage: View {
    let session: WatchSession
    @Environment(\.strings) private var s

    var body: some View {
        WatchPage(title: s.home.todos) {
            if let snapshot = session.snapshot, snapshot.updatedAt > .distantPast {
                if snapshot.todos.isEmpty {
                    EmptyPage(symbol: "checkmark", title: s.home.allDone, color: Brand.success)
                } else {
                    ForEach(snapshot.todos) { todo in
                        TodoRow(todo: todo, queued: session.isQueued(todo)) {
                            WKInterfaceDevice.current().play(.click)
                            session.toggle(todo)
                        }
                    }
                }
                UpdatedLine(date: snapshot.updatedAt)
            } else {
                WaitingPage(loading: session.loading)
            }
        }
    }
}

private struct TodoRow: View {
    let todo: WatchSnapshot.Todo
    let queued: Bool
    let onToggle: () -> Void
    @Environment(\.strings) private var s

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return s.common.today }
        if calendar.isDateInTomorrow(date) { return s.common.tomorrow }
        let c = calendar.dateComponents([.day, .month], from: date)
        return s.common.dayMonthShort(c.day ?? 1, c.month ?? 1)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(todo.done ? Brand.success : Palette.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(todo.title)
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .foregroundStyle(todo.done ? Palette.textTertiary : Palette.textPrimary)
                        .strikethrough(todo.done)
                        .lineLimit(3)
                    if let due = todo.due, !todo.done {
                        Text(dueText(due))
                            .textStyle(.caption2)
                            .foregroundStyle(due < .now ? Palette.dangerText : Palette.textSecondary)
                    }
                    if queued {
                        Label(WatchTexts.of(s.lang).queued, systemImage: "clock")
                            .textStyle(.caption2)
                            .foregroundStyle(Brand.warning)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: .pokyh(Radius.sm))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todo.title)
        .accessibilityValue(todo.done ? s.tasks.done : s.tasks.open)
    }
}

#Preview("Signed out") {
    NavigationStack { SignInOnPhoneView() }
}
