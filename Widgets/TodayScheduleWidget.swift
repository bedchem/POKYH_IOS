import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

/// The rest of the day as a list. Once today is over it shows the next school day.
struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TimetableSnapshot
    var sealed = false
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: WidgetSamples.timetable())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let data = WidgetData.timetable(preview: context.isPreview)
        completion(TodayEntry(date: .now, snapshot: data.snapshot, sealed: data.sealed))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let data = WidgetData.timetable()
        let entries = LessonTimeline.dates(for: data.snapshot, from: now).map {
            TodayEntry(date: $0, snapshot: data.snapshot, sealed: data.sealed)
        }
        completion(Timeline(entries: entries, policy: LessonTimeline.policy(from: now)))
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var s: Strings { WidgetText.app }
    private var hues: SubjectHues { entry.snapshot.hues }
    private var large: Bool { family == .systemLarge }
    private var maxRows: Int { large ? 7 : 3 }

    private var day: [LessonSnapshot] {
        let upcoming = entry.snapshot.lessons.filter { $0.end > entry.date }
        guard let first = upcoming.first else { return [] }
        return upcoming.filter { Calendar.current.isDate($0.start, inSameDayAs: first.start) }
    }

    var body: some View {
        let lessons = day
        VStack(alignment: .leading, spacing: large ? Spacing.md : Spacing.sm) {
            WidgetLabel(
                title: lessons.first.map { WidgetText.day($0.start, from: entry.date) } ?? s.home.sectionToday,
                symbol: "calendar",
                trailing: WidgetText.dayMonth(lessons.first?.start ?? entry.date)
            )
            if entry.sealed {
                WidgetNotice.locked(sealed: true)
            } else if lessons.isEmpty {
                WidgetNotice.dayOver()
            } else {
                FittingCount(most: min(maxRows, lessons.count)) { count in
                    VStack(alignment: .leading, spacing: large ? Spacing.md : Spacing.sm) {
                        ForEach(lessons.prefix(count)) { lesson in
                            LessonRow(lesson: lesson, hues: hues,
                                      current: !lesson.isCancelled && lesson.start <= entry.date)
                        }
                        if large && lessons.count > count {
                            Text(s.home.moreInTimetable(lessons.count - count))
                                .textStyle(.caption2)
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
        }
        .widgetCanvas()
    }
}

struct TodayScheduleWidget: Widget {
    let kind = "TodayScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetText.own.todayName)
        .description(WidgetText.own.todayInfo)
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// ── Previews ─────────────────────────────────────────────────────────────────

private extension TodayEntry {
    static var running: TodayEntry { TodayEntry(date: .now, snapshot: WidgetSamples.timetable()) }
    static var between: TodayEntry { TodayEntry(date: .now, snapshot: WidgetSamples.timetableBreak()) }
    static var free: TodayEntry { TodayEntry(date: .now, snapshot: .empty) }
    static var closed: TodayEntry { TodayEntry(date: .now, snapshot: .empty, sealed: true) }
}

#Preview("Medium", as: .systemMedium) {
    TodayScheduleWidget()
} timeline: {
    TodayEntry.running
    TodayEntry.between
    TodayEntry.free
    TodayEntry.closed
}

#Preview("Large", as: .systemLarge) {
    TodayScheduleWidget()
} timeline: {
    TodayEntry.running
    TodayEntry.between
    TodayEntry.free
    TodayEntry.closed
}
