import WidgetKit
import SwiftUI

/// Home-Screen- & Lock-Screen-Widget: Gesamtschnitt + zuletzt eingetragene Noten.
struct GradesEntry: TimelineEntry { let date: Date; let snapshot: GradesSnapshot }

struct GradesProvider: TimelineProvider {
    func placeholder(in context: Context) -> GradesEntry { GradesEntry(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (GradesEntry) -> Void) {
        completion(GradesEntry(date: Date(), snapshot: SharedStore.readGrades()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GradesEntry>) -> Void) {
        let entry = GradesEntry(date: Date(), snapshot: SharedStore.readGrades())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct GradesWidgetView: View {
    var entry: GradesEntry
    @Environment(\.widgetFamily) private var family
    private var snap: GradesSnapshot { entry.snapshot }
    private var hasData: Bool { !snap.recent.isEmpty }

    var body: some View {
        switch family {
        case .accessoryCircular:    circularView
        case .accessoryRectangular: rectangularView
        case .systemMedium:         medium.pokyhWidgetBackground()
        default:                    small.pokyhWidgetBackground()
        }
    }

    // ── Home Screen ───────────────────────────────────────────────────────────
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(icon: "chart.bar.fill", title: "Schnitt")
            Spacer(minLength: 4)
            Text(hasData ? GradeFormat.string(snap.average) : "–")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(hasData ? Brand.grade(snap.average) : .secondary)
                .minimumScaleFactor(0.5).lineLimit(1)
            Spacer(minLength: 4)
            ratioRow
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(icon: "chart.bar.fill", title: "Schnitt")
                Spacer(minLength: 4)
                Text(hasData ? GradeFormat.string(snap.average) : "–")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(hasData ? Brand.grade(snap.average) : .secondary)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Spacer(minLength: 4)
                ratioRow
            }
            .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text("ZULETZT").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                if hasData {
                    ForEach(snap.recent.prefix(4)) { g in
                        HStack(spacing: 6) {
                            Text(g.subject).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(GradeFormat.string(g.value))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Brand.grade(g.value))
                        }
                    }
                } else {
                    Text("Keine Noten").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ratioRow: some View {
        HStack(spacing: 10) {
            Label("\(snap.positive)", systemImage: "checkmark").labelStyle(.titleAndIcon)
                .foregroundStyle(Brand.positive)
            Label("\(snap.negative)", systemImage: "xmark").labelStyle(.titleAndIcon)
                .foregroundStyle(Brand.danger)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
    }

    // ── Lock Screen ─────────────────────────────────────────────────────────────
    private var circularView: some View {
        Gauge(value: hasData ? min(10, max(1, snap.average)) : 1, in: 1...10) {
            Text("Ø")
        } currentValueLabel: {
            Text(hasData ? GradeFormat.string(snap.average) : "–")
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("NOTENSCHNITT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
            Text(hasData ? GradeFormat.string(snap.average) : "–")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("\(snap.positive) positiv · \(snap.negative) negativ")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GradesWidget: Widget {
    let kind = "GradesWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GradesProvider()) { entry in
            GradesWidgetView(entry: entry)
        }
        .configurationDisplayName("Noten")
        .description("Dein Gesamtschnitt und die zuletzt eingetragenen Noten.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
