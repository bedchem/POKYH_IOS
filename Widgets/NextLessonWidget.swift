import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

/// The running or next lesson and its room, on the Home Screen and the Lock Screen.
struct NextLessonEntry: TimelineEntry {
    let date: Date
    let snapshot: TimetableSnapshot
    var sealed = false
}

struct NextLessonProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextLessonEntry {
        NextLessonEntry(date: .now, snapshot: WidgetSamples.timetable())
    }

    func getSnapshot(in context: Context, completion: @escaping (NextLessonEntry) -> Void) {
        let data = WidgetData.timetable(preview: context.isPreview)
        completion(NextLessonEntry(date: .now, snapshot: data.snapshot, sealed: data.sealed))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextLessonEntry>) -> Void) {
        let now = Date.now
        let data = WidgetData.timetable()
        let entries = LessonTimeline.dates(for: data.snapshot, from: now, ring: true).map {
            NextLessonEntry(date: $0, snapshot: data.snapshot, sealed: data.sealed)
        }
        completion(Timeline(entries: entries, policy: LessonTimeline.policy(from: now)))
    }
}

/// The number under a lesson: time left while it runs, a countdown in the hour before it,
/// otherwise its start time and day.
struct LessonClock: View {
    let lesson: LessonSnapshot
    let now: Date
    var style: TextStyle = .widgetBigNumber
    var alignment: HorizontalAlignment = .leading

    private var running: Bool { lesson.start <= now }
    private var soon: Bool { lesson.start.timeIntervalSince(now) <= LessonTimeline.countdownLead }

    private var caption: String {
        if running { return WidgetText.own.endsIn }
        return soon ? WidgetText.own.startsIn : WidgetText.day(lesson.start, from: now)
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(caption.uppercased())
                .textStyle(.widgetHeader)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
            number
                .widgetNumeral(style)
                .foregroundStyle(running ? Brand.accent : Brand.orange)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .widgetAccentable()
        }
    }

    @ViewBuilder private var number: some View {
        if running {
            Text(timerInterval: lesson.span, countsDown: true)
        } else if soon {
            Text(timerInterval: now...lesson.start, countsDown: true)
        } else {
            Text(WidgetText.time(lesson.start))
        }
    }
}

/// A lesson the way the timetable draws it: a pastel block in the subject's hue.
struct SubjectBlock: View {
    let lesson: LessonSnapshot
    let hues: SubjectHues
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let tone = lesson.tone(hues)
        let plain = mode == .fullColor
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Spacing.xs) {
                Text(lesson.name)
                    .textStyle(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // A glyph, the word would leave no room for the subject.
                if lesson.isExam {
                    Spacer(minLength: 0)
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityLabel(WidgetText.app.timetable.exam)
                        .widgetAccentable()
                }
            }
            .foregroundStyle(plain ? tone.ink : Palette.textPrimary)
            if !lesson.place.isEmpty {
                Text(lesson.place)
                    .textStyle(.caption)
                    .foregroundStyle(plain ? tone.ink.opacity(0.78) : Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetTile(fill: tone.fill)
    }
}

/// One line of a day: subject bar, name, room and teacher, the time on the right.
struct LessonRow: View {
    let lesson: LessonSnapshot
    let hues: SubjectHues
    var current = false
    /// Narrow columns only have room for the start time.
    var narrow = false

    var body: some View {
        HStack(spacing: 10) {
            LessonBar(color: lesson.barColor(hues))
            VStack(alignment: .leading, spacing: 0) {
                Text(lesson.name)
                    .textStyle(current ? .headline : .subheadline.weight(.medium))
                    .foregroundStyle(lesson.isCancelled ? Palette.textTertiary : Palette.textPrimary)
                    .strikethrough(lesson.isCancelled)
                    .lineLimit(1)
                let place = narrow && !lesson.room.isEmpty ? lesson.room : lesson.place
                if !place.isEmpty {
                    Text(place)
                        .textStyle(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.xs)
            VStack(alignment: .trailing, spacing: 0) {
                Text(narrow ? WidgetText.time(lesson.start) : lesson.timeRange)
                    .textStyle(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(current ? Brand.accent : Palette.textSecondary)
                    .lineLimit(1)
                if let status {
                    Text(status.text.uppercased())
                        .textStyle(.badgeChip)
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                        .widgetAccentable()
                }
            }
        }
    }

    private var status: (text: String, color: Color)? {
        let table = WidgetText.app.timetable
        if lesson.isCancelled { return (table.cancelled, Palette.dangerText) }
        if lesson.isExam { return (table.exam, Brand.warning) }
        return nil
    }
}

struct NextLessonWidgetView: View {
    let entry: NextLessonEntry
    @Environment(\.widgetFamily) private var family

    private var s: Strings { WidgetText.app }
    private var t: WidgetStrings { WidgetText.own }
    private var hues: SubjectHues { entry.snapshot.hues }
    private var lessons: [LessonSnapshot] {
        entry.snapshot.lessons.filter { !$0.isCancelled && $0.end > entry.date }
    }
    private var current: LessonSnapshot? { lessons.first }
    private var running: Bool { current.map { $0.start <= entry.date } ?? false }
    private var title: String { running ? s.home.now : s.home.upNext }
    private var symbol: String { running ? "clock.fill" : "clock" }

    var body: some View {
        content.widgetCanvas()
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: focus
        }
    }

    // ── Home Screen ──────────────────────────────────────────────────────────

    @ViewBuilder private var focus: some View {
        if let lesson = current {
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel(title: title, symbol: symbol)
                Spacer(minLength: Spacing.xs)
                SubjectBlock(lesson: lesson, hues: hues)
                Spacer(minLength: Spacing.xs)
                LessonClock(lesson: lesson, now: entry.date)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                WidgetLabel(title: s.system.widgetNext, symbol: "clock")
                if entry.sealed { WidgetNotice.locked(sealed: true) } else { WidgetNotice.dayOver() }
            }
        }
    }

    @ViewBuilder private var medium: some View {
        if current == nil {
            focus
        } else {
            HStack(alignment: .top, spacing: Spacing.lg) {
                focus.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    WidgetLabel(title: s.home.afterThat)
                    if lessons.count > 1 {
                        let after = lessons.dropFirst()
                        FittingCount(most: min(3, after.count)) { count in
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(after.prefix(count)) { LessonRow(lesson: $0, hues: hues, narrow: true) }
                            }
                        }
                    } else {
                        Text(s.system.widgetNoMore)
                            .textStyle(.caption)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // ── Lock Screen ──────────────────────────────────────────────────────────

    private var inline: some View {
        Label {
            Text(inlineText)
        } icon: {
            Image(systemName: inlineSymbol)
        }
    }

    private var inlineText: String {
        guard let lesson = current else { return entry.sealed ? t.locked : s.system.widgetNoMore }
        let when = running ? lesson.timeRange : WidgetText.time(lesson.start)
        return [lesson.name, lesson.room, when].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var inlineSymbol: String {
        if current != nil { return symbol }
        return entry.sealed ? "lock.fill" : "checkmark.circle"
    }

    @ViewBuilder private var circular: some View {
        if let lesson = current {
            if running {
                Gauge(value: lesson.elapsed(at: entry.date)) {
                    Text(lesson.name)
                } currentValueLabel: {
                    ringLabel(lesson.name, lesson.room)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    ringLabel(lesson.name, lesson.room.isEmpty ? WidgetText.time(lesson.start) : lesson.room)
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.sealed ? "lock.fill" : "checkmark")
                    .font(.title3.weight(.semibold))
                    .widgetAccentable()
            }
        }
    }

    private func ringLabel(_ top: String, _ bottom: String) -> some View {
        VStack(spacing: 0) {
            Text(top)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !bottom.isEmpty {
                Text(bottom)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    @ViewBuilder private var rectangular: some View {
        if let lesson = current {
            VStack(alignment: .leading, spacing: 0) {
                AccessoryHeader(title: title, symbol: symbol)
                Text(lesson.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: Spacing.xs) {
                    if !lesson.room.isEmpty {
                        Image(systemName: "mappin.and.ellipse")
                        Text(lesson.room).lineLimit(1)
                        Text(verbatim: "·")
                    }
                    if running {
                        Text(timerInterval: lesson.span, countsDown: true)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(WidgetText.time(lesson.start))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                AccessoryHeader(title: s.system.widgetNext, symbol: "clock")
                Text(entry.sealed ? t.locked : s.system.widgetNoMore)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if entry.sealed {
                    Text(t.openApp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NextLessonWidget: Widget {
    let kind = "NextLessonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextLessonProvider()) { entry in
            NextLessonWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetText.app.system.widgetNext)
        .description(WidgetText.own.nextInfo)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// ── Previews ─────────────────────────────────────────────────────────────────

private extension NextLessonEntry {
    static var running: NextLessonEntry { NextLessonEntry(date: .now, snapshot: WidgetSamples.timetable()) }
    static var between: NextLessonEntry { NextLessonEntry(date: .now, snapshot: WidgetSamples.timetableBreak()) }
    static var free: NextLessonEntry { NextLessonEntry(date: .now, snapshot: .empty) }
    static var closed: NextLessonEntry { NextLessonEntry(date: .now, snapshot: .empty, sealed: true) }
}

#Preview("Small", as: .systemSmall) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry.running
    NextLessonEntry.between
    NextLessonEntry.free
    NextLessonEntry.closed
}

#Preview("Medium", as: .systemMedium) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry.running
    NextLessonEntry.between
    NextLessonEntry.free
    NextLessonEntry.closed
}

#Preview("Rectangular", as: .accessoryRectangular) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry.running
    NextLessonEntry.between
    NextLessonEntry.free
    NextLessonEntry.closed
}

#Preview("Circular", as: .accessoryCircular) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry.running
    NextLessonEntry.between
    NextLessonEntry.free
    NextLessonEntry.closed
}

#Preview("Inline", as: .accessoryInline) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry.running
    NextLessonEntry.between
    NextLessonEntry.free
    NextLessonEntry.closed
}
