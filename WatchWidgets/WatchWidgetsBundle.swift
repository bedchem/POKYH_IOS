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
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName(strings.home.sectionNowNext)
        .description(strings.home.sectionNowNextInfo)
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
    }
}

struct NextLessonEntry: TimelineEntry {
    enum Content {
        /// Nothing about today yet, or not signed in.
        case unknown
        /// Today has no lessons.
        case free
        case dayOver
        case lesson(WatchSnapshot.Lesson, running: Bool)
    }

    let date: Date
    let content: Content
    let lang: Lang

    init(date: Date, snapshot: WatchSnapshot?) {
        self.date = date
        lang = snapshot?.lang ?? LanguageChoice.current(in: .standard)
        guard let snapshot, snapshot.knowsToday(at: date) else {
            content = .unknown
            return
        }
        if let lesson = snapshot.upcoming(at: date) {
            content = .lesson(lesson, running: snapshot.current(at: date) != nil)
        } else {
            content = snapshot.dayIsOver(at: date) ? .dayOver : .free
        }
    }

    /// For the watch face gallery: what it will look like, nobody's real timetable.
    static func sample(at date: Date) -> NextLessonEntry {
        let lang = LanguageChoice.current(in: .standard)
        let lesson = WatchSnapshot.Lesson(
            id: "sample", subject: Strings.of(lang).home.lesson, teacher: "", room: "1",
            start: date.addingTimeInterval(15 * 60), end: date.addingTimeInterval(65 * 60)
        )
        return NextLessonEntry(date: date, lesson: lesson, lang: lang)
    }

    private init(date: Date, lesson: WatchSnapshot.Lesson, lang: Lang) {
        self.date = date
        self.lang = lang
        content = .lesson(lesson, running: false)
    }
}

/// One entry per lesson edge, so the face moves on through the day without the app running.
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
        let now = Date.now
        let dates = snapshot?.timelineDates(from: now) ?? [now]
        let entries = dates.map { NextLessonEntry(date: $0, snapshot: snapshot) }
        // The last entry is midnight; the next day needs a look at what has arrived by then.
        completion(Timeline(entries: entries, policy: snapshot == nil ? .never : .atEnd))
    }
}

struct NextLessonView: View {
    let entry: NextLessonEntry
    @Environment(\.widgetFamily) private var family

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

    /// Fits the smallest faces: the room if it has one, else nothing.
    private func place(_ lesson: WatchSnapshot.Lesson) -> String {
        lesson.room.isEmpty ? lesson.teacher : lesson.room
    }

    private func detail(_ lesson: WatchSnapshot.Lesson) -> String {
        [lesson.room.isEmpty ? "" : s.home.room(lesson.room), lesson.teacher]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func clock(_ lesson: WatchSnapshot.Lesson, running: Bool) -> String {
        WatchFormat.clock(running ? lesson.end : lesson.start)
    }

    @ViewBuilder private var rectangular: some View {
        switch entry.content {
        case .lesson(let lesson, let running):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing.xs) {
                    Text(running ? s.home.now : s.home.upNext)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    // A running lesson's start is past; when it ends is what you look for.
                    Text(clock(lesson, running: running))
                        .monospacedDigit()
                        .widgetAccentable()
                }
                .font(.system(size: 13, weight: .medium))
                Text(lesson.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .widgetAccentable()
                Text(detail(lesson))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 0) {
                Text("POKYH")
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

    /// The rectangular family has room to say why there's nothing.
    private var idleTitle: String {
        switch entry.content {
        case .free: s.home.noLessonsToday
        case .dayOver: s.home.dayOver
        default: s.watch.waitingForPhone
        }
    }

    @ViewBuilder private var circular: some View {
        switch entry.content {
        case .lesson(let lesson, true):
            ProgressView(timerInterval: lesson.start...lesson.end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: -1) {
                    Text(lesson.subject)
                        .font(.system(size: 13, weight: .semibold))
                        .minimumScaleFactor(0.6)
                    Text(place(lesson))
                        .font(.system(size: 10))
                        .minimumScaleFactor(0.6)
                }
                .lineLimit(1)
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        case .lesson(let lesson, false):
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Text(lesson.subject)
                        .font(.system(size: 14, weight: .semibold))
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    Text(WatchFormat.clock(lesson.start))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
                .lineLimit(1)
                .padding(Spacing.xxs)
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: idleSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
            }
        }
    }

    private var idleSymbol: String {
        switch entry.content {
        case .free, .dayOver: "checkmark"
        default: "graduationcap.fill"
        }
    }

    @ViewBuilder private var corner: some View {
        switch entry.content {
        case .lesson(let lesson, let running):
            Text(place(lesson).isEmpty ? lesson.subject : place(lesson))
                .font(.system(size: 18, weight: .semibold))
                .widgetAccentable()
                .widgetLabel {
                    Text("\(clock(lesson, running: running)) \(lesson.subject)")
                }
        default:
            Image(systemName: idleSymbol)
                .font(.system(size: 20, weight: .semibold))
                .widgetAccentable()
                .widgetLabel { Text(idleText) }
        }
    }

    @ViewBuilder private var inline: some View {
        switch entry.content {
        case .lesson(let lesson, _):
            let room = place(lesson)
            Text("\(WatchFormat.clock(lesson.start)) \(lesson.subject)\(room.isEmpty ? "" : " · \(room)")")
        default:
            Text(idleText)
        }
    }

    /// The small families say it in one word.
    private var idleText: String {
        switch entry.content {
        case .free, .dayOver: texts.free
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
