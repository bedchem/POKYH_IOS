import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

@main
struct POKYHWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonComplication()
    }
}

struct NextLessonComplication: Widget {
    private let strings = Strings.of(LanguageChoice.current(in: .standard))

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextLessonComplication", provider: NextLessonProvider()) { entry in
            NextLessonView(entry: entry)
        }
        .configurationDisplayName(strings.home.sectionNowNext)
        .description(strings.home.sectionNowNextInfo)
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
    }
}

struct NextLessonEntry: TimelineEntry {
    let date: Date
    let moment: WatchSnapshot.Moment
    /// What's after the lesson, set only once the bell is close: then that's the question.
    let afterwards: WatchSnapshot.Lesson?
    let lang: Lang
    let relevance: TimelineEntryRelevance?

    init(date: Date, snapshot: WatchSnapshot?, until end: Date? = nil) {
        self.date = date
        lang = snapshot?.lang ?? LanguageChoice.current(in: .standard)
        moment = snapshot?.moment(at: date) ?? .unknown
        if case .running(let lesson) = moment, lesson.end.timeIntervalSince(date) <= WatchSnapshot.runUp {
            afterwards = snapshot?.follower(at: date)
        } else {
            afterwards = nil
        }
        let score = snapshot?.relevance(at: date) ?? 0
        relevance = TimelineEntryRelevance(score: Float(score), duration: end?.timeIntervalSince(date) ?? 0)
    }

    /// For the watch face gallery: what it will look like, nobody's real timetable.
    static func sample(at date: Date) -> NextLessonEntry {
        let lang = LanguageChoice.current(in: .standard)
        let lesson = WatchSnapshot.Lesson(
            id: "sample", subject: Strings.of(lang).home.lesson, teacher: "", room: "1",
            start: date.addingTimeInterval(-20 * 60), end: date.addingTimeInterval(30 * 60)
        )
        return NextLessonEntry(date: date, lesson: lesson, lang: lang)
    }

    private init(date: Date, lesson: WatchSnapshot.Lesson, lang: Lang) {
        self.date = date
        self.lang = lang
        moment = .running(lesson)
        afterwards = nil
        relevance = nil
    }
}

/// One entry per bell and run-up, so the face moves on through the day without the app running.
/// Bars and countdowns tick by themselves between them.
struct NextLessonProvider: TimelineProvider {
    private var store: WatchStore { .shared(createsKey: false) }

    func placeholder(in context: Context) -> NextLessonEntry {
        .sample(at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextLessonEntry) -> Void) {
        completion(context.isPreview ? .sample(at: .now) : NextLessonEntry(date: .now, snapshot: store.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextLessonEntry>) -> Void) {
        let snapshot = store.snapshot()
        let dates = snapshot?.timelineDates(from: .now) ?? [.now]
        let entries = dates.indices.map { index in
            NextLessonEntry(date: dates[index], snapshot: snapshot, until: dates.indices.contains(index + 1) ? dates[index + 1] : nil)
        }
        // The last entry is midnight; the next day needs a look at what has arrived by then.
        completion(Timeline(entries: entries, policy: snapshot == nil ? .never : .atEnd))
    }
}

extension WatchSnapshot.Lesson {
    fileprivate var tone: Tone {
        switch status {
        case .cancelled: .cancelled
        case .exam: .exam
        case .substitution, .roomChange: .substitution
        case .additional: .event
        case .regular: .subject(subject)
        }
    }
}

struct NextLessonView: View {
    let entry: NextLessonEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        NextLessonFace(entry: entry, family: family)
            // The Smart Stack shows this behind the widget; watch faces leave it out.
            .containerBackground(for: .widget) {
                if let lesson = entry.moment.lesson {
                    LinearGradient(colors: [lesson.tone.bar.opacity(0.5), lesson.tone.fill.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.clear
                }
            }
    }
}

struct NextLessonFace: View {
    let entry: NextLessonEntry
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var mode

    private var s: Strings { .of(entry.lang) }
    private var texts: WatchTexts { .of(entry.lang) }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        default: inline
        }
    }

    // A color only where the face shows color; the accented faces tint by themselves.
    private func tint(_ lesson: WatchSnapshot.Lesson) -> Color? {
        mode == .fullColor ? lesson.tone.bar : nil
    }

    private func short(_ lesson: WatchSnapshot.Lesson) -> String {
        lesson.subject.isEmpty ? s.home.lesson : lesson.subject
    }

    private func title(_ lesson: WatchSnapshot.Lesson) -> String {
        lesson.title.isEmpty ? s.home.lesson : lesson.title
    }

    /// Fits the smallest faces: the room if it has one, else the teacher.
    private func place(_ lesson: WatchSnapshot.Lesson) -> String {
        lesson.room.isEmpty ? lesson.teacher : lesson.room
    }

    /// The second line: what's different, or simply where.
    private func detail(_ lesson: WatchSnapshot.Lesson) -> String {
        switch lesson.status {
        case .cancelled: s.home.cancelled
        case .exam: [s.home.exam, lesson.room].filter { !$0.isEmpty }.joined(separator: " · ")
        case .substitution:
            [lesson.originalTeacher.map { "\(lesson.teacher) \(texts.instead($0))" } ?? lesson.teacher, lesson.room]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .roomChange:
            lesson.originalRoom.map { "\(s.home.room(lesson.room)) \(texts.instead($0))" } ?? s.home.room(lesson.room)
        case .additional, .regular:
            lesson.room.isEmpty ? lesson.teacher : s.home.room(lesson.room)
        }
    }

    private func clock(_ lesson: WatchSnapshot.Lesson) -> String {
        WatchFormat.clock(lesson.start)
    }

    private var isRunning: Bool {
        if case .running = entry.moment { return true }
        return false
    }

    /// The countdown and the bar run over this; it never passes an entry's own moment.
    private var span: ClosedRange<Date>? {
        entry.moment.span(at: entry.date)
    }

    // MARK: Rectangular

    @ViewBuilder private var rectangular: some View {
        if let lesson = entry.moment.lesson {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(title(lesson))
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .widgetAccentable()
                    Spacer(minLength: 0)
                    if let span {
                        Text(timerInterval: span, countsDown: true, showsHours: false)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 46, alignment: .trailing)
                    } else {
                        Text(clock(lesson))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                secondLine(lesson)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let span {
                    ProgressView(timerInterval: span, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .labelsHidden()
                    .tint(tint(lesson))
                    .widgetAccentable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "POKYH")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                Text(idleTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Near the bell it answers "where next?"; before that "where am I supposed to be?".
    @ViewBuilder private func secondLine(_ lesson: WatchSnapshot.Lesson) -> some View {
        if let next = entry.afterwards {
            let what = next.isCancelled ? s.home.cancelled : place(next)
            Text("\(clock(next)) \(title(next)) · \(what)")
                .fontWeight(next.status == .regular ? .regular : .semibold)
                .strikethrough(next.isCancelled)
        } else if lesson.status != .regular {
            Text(detail(lesson))
                .fontWeight(.semibold)
                .foregroundStyle(mode == .fullColor ? lesson.tone.ink : .primary)
        } else if isRunning || span == nil {
            Text(detail(lesson))
                .foregroundStyle(.secondary)
        } else {
            // The top line counts down, so when it starts goes here.
            Text(clock(lesson) + (place(lesson).isEmpty ? "" : " · \(place(lesson))"))
                .foregroundStyle(.secondary)
        }
    }

    private var idleTitle: String {
        switch entry.moment {
        case .free: Calendar.current.isDateInWeekend(entry.date) ? texts.weekend : s.home.noLessonsToday
        case .over: s.home.dayOver
        default: s.watch.waitingForPhone
        }
    }

    // MARK: Circular

    @ViewBuilder private var circular: some View {
        if let lesson = entry.moment.lesson {
            ZStack {
                if let span {
                    // Counting down the lesson, or the break before the next one.
                    ProgressView(timerInterval: span, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.circular)
                    .labelsHidden()
                    .tint(tint(lesson))
                    .widgetAccentable()
                } else {
                    AccessoryWidgetBackground()
                }
                VStack(spacing: -1) {
                    Text(short(lesson))
                        .font(.system(size: 13, weight: .semibold))
                        .minimumScaleFactor(0.5)
                    if let span {
                        Text(timerInterval: span, countsDown: true, showsHours: false)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                    } else {
                        Text(clock(lesson))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, Spacing.sm)
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: idleSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
            }
        }
    }

    private var idleSymbol: String {
        switch entry.moment {
        case .free, .over: "checkmark"
        default: "graduationcap.fill"
        }
    }

    // MARK: Corner

    @ViewBuilder private var corner: some View {
        if let lesson = entry.moment.lesson {
            Text(place(lesson).isEmpty ? short(lesson) : place(lesson))
                .font(.system(size: 18, weight: .semibold))
                .minimumScaleFactor(0.5)
                .widgetAccentable()
                .widgetLabel {
                    if isRunning, let span {
                        ProgressView(timerInterval: span, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(tint(lesson))
                    } else {
                        Text("\(clock(lesson)) \(short(lesson))")
                    }
                }
        } else {
            Image(systemName: idleSymbol)
                .font(.system(size: 20, weight: .semibold))
                .widgetAccentable()
                .widgetLabel { Text(idleText) }
        }
    }

    // MARK: Inline

    @ViewBuilder private var inline: some View {
        if let lesson = entry.moment.lesson {
            let room = place(lesson).isEmpty ? "" : " · \(place(lesson))"
            if isRunning, let span {
                Text("\(short(lesson))\(room) · \(Text(timerInterval: span, countsDown: true, showsHours: false))")
            } else {
                Text("\(clock(lesson)) \(short(lesson))\(room)")
            }
        } else {
            Text(idleText)
        }
    }

    /// The small families say it in one word.
    private var idleText: String {
        switch entry.moment {
        case .free, .over: texts.free
        default: "POKYH"
        }
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    NextLessonComplication()
} timeline: {
    NextLessonEntry.sample(at: .now)
}

#Preview("Circular", as: .accessoryCircular) {
    NextLessonComplication()
} timeline: {
    NextLessonEntry.sample(at: .now)
}
