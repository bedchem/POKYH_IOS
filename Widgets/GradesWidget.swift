import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

/// The overall average and the latest grades. Grades are private: a locked phone gets a notice
/// instead of the numbers.
struct GradesEntry: TimelineEntry {
    let date: Date
    let snapshot: GradesSnapshot
    var sealed = false
}

struct GradesProvider: TimelineProvider {
    func placeholder(in context: Context) -> GradesEntry {
        GradesEntry(date: .now, snapshot: WidgetSamples.grades)
    }

    func getSnapshot(in context: Context, completion: @escaping (GradesEntry) -> Void) {
        let data = WidgetData.grades(preview: context.isPreview)
        completion(GradesEntry(date: .now, snapshot: data.snapshot, sealed: data.sealed))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GradesEntry>) -> Void) {
        let now = Date.now
        let data = WidgetData.grades()
        let entry = GradesEntry(date: now, snapshot: data.snapshot, sealed: data.sealed)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(1800))))
    }
}

/// A subject and its grade, Android's grade row.
struct GradeLine: View {
    let item: GradeItem
    let hues: SubjectHues

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SubjectDot(color: Tone.subject(item.subject, hues: hues).bar)
            Text(item.subject)
                .textStyle(.footnote)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Spacing.xs)
            Text(WidgetText.grade(item.value))
                .textStyle(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Brand.grade(item.value))
                .widgetAccentable()
        }
        .privacySensitive()
    }
}

/// How many grades passed and how many didn't, as a thin split bar with the two counts.
struct GradeRatio: View {
    let positive: Int
    let negative: Int
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            GeometryReader { geo in
                let total = max(1, positive + negative)
                let gap: CGFloat = negative > 0 && positive > 0 ? 2 : 0
                let width = max(0, geo.size.width - gap) * CGFloat(positive) / CGFloat(total)
                HStack(spacing: gap) {
                    if positive > 0 {
                        Capsule().fill(Brand.success).frame(width: width).widgetAccentable()
                    }
                    if negative > 0 {
                        Capsule().fill(Brand.danger).opacity(mode == .fullColor ? 1 : 0.3)
                    }
                }
            }
            .frame(height: 5)
            HStack(spacing: Spacing.sm) {
                tally(positive, Brand.success)
                tally(negative, Brand.danger)
            }
        }
        .privacySensitive()
    }

    private func tally(_ count: Int, _ color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            SubjectDot(color: color, size: 6)
            Text(count, format: .number)
                .textStyle(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

struct GradesWidgetView: View {
    let entry: GradesEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.hidesPrivateData) private var hidesPrivateData

    private var s: Strings { WidgetText.app }
    private var t: WidgetStrings { WidgetText.own }
    private var snap: GradesSnapshot { entry.snapshot }
    private var hasData: Bool { !snap.recent.isEmpty }
    private var hidden: Bool { entry.sealed || hidesPrivateData }
    private var average: String { hasData ? WidgetText.grade(snap.average) : "–" }

    var body: some View {
        content.widgetCanvas()
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // ── Home Screen ──────────────────────────────────────────────────────────

    private var header: some View {
        WidgetLabel(title: s.system.widgetGrades, symbol: "chart.bar.fill")
    }

    @ViewBuilder private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if hidden {
                WidgetNotice.locked(sealed: entry.sealed)
            } else if hasData {
                Spacer(minLength: Spacing.xs)
                numbers
            } else {
                noGrades
            }
        }
    }

    @ViewBuilder private var medium: some View {
        if hidden || !hasData {
            small
        } else {
            HStack(alignment: .top, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: Spacing.xs)
                    numbers
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    WidgetLabel(title: s.grades.recentTitle)
                    FittingCount(most: min(4, snap.recent.count)) { count in
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(snap.recent.prefix(count)) { GradeLine(item: $0, hues: snap.hues) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(average)
                .widgetNumeral()
                .foregroundStyle(Brand.grade(snap.average))
                .widgetAccentable()
                .privacySensitive()
            Text(s.home.fromGrades(snap.positive + snap.negative))
                .textStyle(.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .privacySensitive()
            Spacer(minLength: Spacing.xs)
            GradeRatio(positive: snap.positive, negative: snap.negative)
        }
    }

    private var noGrades: some View {
        WidgetNotice(symbol: "chart.bar.fill", title: s.system.widgetNoGrades)
    }

    // ── Lock Screen ──────────────────────────────────────────────────────────

    @ViewBuilder private var circular: some View {
        if hidden {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "lock.fill")
                    .font(.title3.weight(.semibold))
                    .widgetAccentable()
            }
        } else {
            Gauge(value: hasData ? min(10, max(1, snap.average)) : 1, in: 1...10) {
                Text(verbatim: "Ø")
            } currentValueLabel: {
                // One decimal: the ring leaves no room for two.
                Text(hasData ? WidgetText.grade((snap.average * 10).rounded() / 10) : "–")
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
            .privacySensitive()
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccessoryHeader(title: s.home.gradeAvg, symbol: "chart.bar.fill")
            if hidden {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "lock.fill")
                    Text(t.locked)
                }
                .font(.headline)
                Text(entry.sealed ? t.openApp : t.unlockToView)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if hasData {
                Text(average)
                    .widgetNumeral(.statMedium)
                    .privacySensitive()
                Text(verbatim: "\(s.grades.positiveCount(snap.positive)) · \(s.grades.negativeCount(snap.negative))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
            } else {
                Text(s.system.widgetNoGrades)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label {
            if hidden {
                Text(verbatim: "\(s.system.widgetGrades) · \(t.locked)")
            } else if hasData {
                Text(verbatim: "Ø \(average) · \(s.system.widgetGrades)")
                    .privacySensitive()
            } else {
                Text(s.system.widgetNoGrades)
            }
        } icon: {
            Image(systemName: hidden ? "lock.fill" : "chart.bar.fill")
        }
    }
}

struct GradesWidget: Widget {
    let kind = "GradesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GradesProvider()) { entry in
            GradesWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetText.app.system.widgetGrades)
        .description(WidgetText.own.gradesInfo)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// ── Previews ─────────────────────────────────────────────────────────────────

private extension GradesEntry {
    static var filled: GradesEntry { GradesEntry(date: .now, snapshot: WidgetSamples.grades) }
    static var none: GradesEntry { GradesEntry(date: .now, snapshot: .empty) }
    static var closed: GradesEntry { GradesEntry(date: .now, snapshot: .empty, sealed: true) }
}

#Preview("Small", as: .systemSmall) {
    GradesWidget()
} timeline: {
    GradesEntry.filled
    GradesEntry.none
    GradesEntry.closed
}

#Preview("Medium", as: .systemMedium) {
    GradesWidget()
} timeline: {
    GradesEntry.filled
    GradesEntry.none
    GradesEntry.closed
}

#Preview("Rectangular", as: .accessoryRectangular) {
    GradesWidget()
} timeline: {
    GradesEntry.filled
    GradesEntry.none
    GradesEntry.closed
}

#Preview("Circular", as: .accessoryCircular) {
    GradesWidget()
} timeline: {
    GradesEntry.filled
    GradesEntry.none
    GradesEntry.closed
}

#Preview("Inline", as: .accessoryInline) {
    GradesWidget()
} timeline: {
    GradesEntry.filled
    GradesEntry.none
    GradesEntry.closed
}
