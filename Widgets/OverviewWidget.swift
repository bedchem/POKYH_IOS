import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

/// Next lesson, grade average and unread messages together. Grades and message details are
/// private, so a locked phone gets a lock in their place.
struct OverviewEntry: TimelineEntry {
    let date: Date
    let timetable: TimetableSnapshot
    let grades: GradesSnapshot
    let messages: MessagesSnapshot
    var sealed = false
}

struct OverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> OverviewEntry {
        OverviewEntry(date: .now, timetable: WidgetSamples.timetable(),
                      grades: WidgetSamples.grades, messages: WidgetSamples.messages)
    }

    func getSnapshot(in context: Context, completion: @escaping (OverviewEntry) -> Void) {
        completion(entry(at: .now, preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OverviewEntry>) -> Void) {
        let now = Date.now
        let current = entry(at: now, preview: false)
        let entries = LessonTimeline.dates(for: current.timetable, from: now).map {
            OverviewEntry(date: $0, timetable: current.timetable, grades: current.grades,
                          messages: current.messages, sealed: current.sealed)
        }
        completion(Timeline(entries: entries, policy: LessonTimeline.policy(from: now)))
    }

    private func entry(at date: Date, preview: Bool) -> OverviewEntry {
        let timetable = WidgetData.timetable(preview: preview)
        let grades = WidgetData.grades(preview: preview)
        let messages = WidgetData.messages(preview: preview)
        return OverviewEntry(date: date, timetable: timetable.snapshot, grades: grades.snapshot,
                             messages: messages.snapshot,
                             sealed: timetable.sealed && grades.sealed && messages.sealed)
    }
}

struct OverviewWidgetView: View {
    let entry: OverviewEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.hidesPrivateData) private var hidesPrivateData

    private var s: Strings { WidgetText.app }
    private var t: WidgetStrings { WidgetText.own }
    private var hues: SubjectHues { entry.timetable.hues }
    private var large: Bool { family == .systemLarge }
    private var lessons: [LessonSnapshot] {
        entry.timetable.lessons.filter { !$0.isCancelled && $0.end > entry.date }
    }
    private var hasGrades: Bool { !entry.grades.recent.isEmpty }

    var body: some View {
        Group {
            if entry.sealed {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    WidgetLabel(title: t.overviewName, symbol: "square.grid.2x2.fill")
                    WidgetNotice.locked(sealed: true)
                }
            } else {
                VStack(alignment: .leading, spacing: large ? Spacing.md : Spacing.sm) {
                    lessonBlock
                    HStack(spacing: Spacing.sm) {
                        gradeTile
                        messageTile
                    }
                    if large { largeExtras }
                }
            }
        }
        .widgetCanvas()
    }

    // ── Next lesson ──────────────────────────────────────────────────────────

    @ViewBuilder private var lessonBlock: some View {
        if let lesson = lessons.first {
            let running = lesson.start <= entry.date
            HStack(spacing: 10) {
                LessonBar(color: lesson.barColor(hues), height: 50)
                VStack(alignment: .leading, spacing: 1) {
                    WidgetLabel(title: running ? s.home.now : s.home.upNext,
                                symbol: running ? "clock.fill" : "clock")
                    Text(lesson.name)
                        .textStyle(.headline)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !lesson.place.isEmpty {
                        Text(lesson.place)
                            .textStyle(.caption2)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                // A running timer asks for all the width it can get, so it gets a limit.
                LessonClock(lesson: lesson, now: entry.date, style: .statMedium, alignment: .trailing)
                    .frame(maxWidth: 104, alignment: .trailing)
            }
        } else {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.success)
                    .widgetAccentable()
                Text(s.system.widgetNoMore)
                    .textStyle(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // ── Tiles ────────────────────────────────────────────────────────────────

    private var gradeTile: some View {
        tile(title: s.system.widgetGrades, symbol: "chart.bar.fill") {
            if hidesPrivateData {
                lockValue
            } else {
                Text(hasGrades ? WidgetText.grade(entry.grades.average) : "–")
                    .widgetNumeral(.statMedium)
                    .foregroundStyle(hasGrades ? Brand.grade(entry.grades.average) : Palette.textTertiary)
                    .widgetAccentable()
                    .privacySensitive()
            }
        }
    }

    private var messageTile: some View {
        tile(title: s.home.sectionMessages, symbol: "envelope.fill") {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(entry.messages.unread, format: .number)
                    .widgetNumeral(.statMedium)
                    .foregroundStyle(entry.messages.unread > 0 ? Brand.accent : Palette.textTertiary)
                    .widgetAccentable()
                    .privacySensitive()
                Text(t.unread)
                    .textStyle(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var lockValue: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Brand.accent)
            .frame(height: 33)
            .widgetAccentable()
    }

    private func tile(title: String, symbol: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: title, symbol: symbol)
            value()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetTile(radius: Radius.md)
    }

    // ── Large ────────────────────────────────────────────────────────────────

    private var largeExtras: some View {
        FittingCount(most: 4) { level in
            extras(lessonRows: max(0, level - 2), gradeRows: level == 1 ? 2 : 3)
        }
    }

    private func extras(lessonRows: Int, gradeRows: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if lessonRows > 0 && lessons.count > 1 {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    WidgetLabel(title: s.home.afterThat)
                    ForEach(lessons.dropFirst().prefix(lessonRows)) { LessonRow(lesson: $0, hues: hues) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                WidgetLabel(title: s.grades.recentTitle)
                if hidesPrivateData {
                    WidgetNotice.locked(sealed: false, compact: true)
                } else if hasGrades {
                    ForEach(entry.grades.recent.prefix(gradeRows)) { GradeLine(item: $0, hues: entry.grades.hues) }
                } else {
                    Text(s.system.widgetNoGrades)
                        .textStyle(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}

struct OverviewWidget: Widget {
    let kind = "OverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OverviewProvider()) { entry in
            OverviewWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetText.own.overviewName)
        .description(WidgetText.own.overviewInfo)
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// ── Previews ─────────────────────────────────────────────────────────────────

private extension OverviewEntry {
    static var running: OverviewEntry {
        OverviewEntry(date: .now, timetable: WidgetSamples.timetable(),
                      grades: WidgetSamples.grades, messages: WidgetSamples.messages)
    }
    static var between: OverviewEntry {
        OverviewEntry(date: .now, timetable: WidgetSamples.timetableBreak(),
                      grades: WidgetSamples.grades, messages: WidgetSamples.messages)
    }
    static var free: OverviewEntry {
        OverviewEntry(date: .now, timetable: .empty, grades: .empty, messages: .empty)
    }
    static var closed: OverviewEntry {
        OverviewEntry(date: .now, timetable: .empty, grades: .empty, messages: .empty, sealed: true)
    }
}

#Preview("Medium", as: .systemMedium) {
    OverviewWidget()
} timeline: {
    OverviewEntry.running
    OverviewEntry.between
    OverviewEntry.free
    OverviewEntry.closed
}

#Preview("Large", as: .systemLarge) {
    OverviewWidget()
} timeline: {
    OverviewEntry.running
    OverviewEntry.between
    OverviewEntry.free
    OverviewEntry.closed
}
