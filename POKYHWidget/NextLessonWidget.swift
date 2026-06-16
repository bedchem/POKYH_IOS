import WidgetKit
import SwiftUI

/// Home-Screen- & Lock-Screen-Widget: laufende oder nächste Stunde.
struct NextLessonEntry: TimelineEntry {
    let date: Date
    let snapshot: TimetableSnapshot
}

struct NextLessonProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextLessonEntry {
        NextLessonEntry(date: Date(), snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (NextLessonEntry) -> Void) {
        completion(NextLessonEntry(date: Date(), snapshot: SharedStore.readSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextLessonEntry>) -> Void) {
        let snap = SharedStore.readSnapshot()
        let now = Date()
        var pivots: [Date] = [now]
        for l in snap.lessons.prefix(6) where !l.isCancelled {
            if l.start > now { pivots.append(l.start) }
            if l.end > now { pivots.append(l.end) }
        }
        let entries = Array(Set(pivots)).sorted().map { NextLessonEntry(date: $0, snapshot: snap) }
        let safe = entries.isEmpty ? [NextLessonEntry(date: now, snapshot: snap)] : entries
        completion(Timeline(entries: safe, policy: .after(now.addingTimeInterval(3600))))
    }
}

struct NextLessonWidgetView: View {
    var entry: NextLessonProvider.Entry
    @Environment(\.widgetFamily) private var family

    private var current: LessonSnapshot? {
        entry.snapshot.lessons.first { !$0.isCancelled && $0.end > entry.date }
    }
    private var following: LessonSnapshot? {
        entry.snapshot.lessons.first { !$0.isCancelled && $0.start > (current?.end ?? entry.date) }
    }
    private var running: Bool { (current?.start ?? .distantFuture) <= entry.date }

    var body: some View {
        switch family {
        case .accessoryInline:      inlineView
        case .accessoryCircular:    circularView
        case .accessoryRectangular: rectangularView
        default:                    homeView.pokyhWidgetBackground()
        }
    }

    // ── Home Screen ───────────────────────────────────────────────────────────
    @ViewBuilder private var homeView: some View {
        if let l = current {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(icon: l.isExam ? "pencil.and.list.clipboard" : "book.fill",
                             title: running ? "Jetzt" : "Als Nächstes")
                Spacer(minLength: 6)
                Text(l.subject)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    if running {
                        Text(l.end, style: .timer)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(Brand.accent).fixedSize()
                        Text("übrig").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(l.start, style: .time)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(Brand.accent)
                        if !l.room.isEmpty { dot; Text(l.room).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                if running, !l.room.isEmpty || !l.teacher.isEmpty {
                    Text([l.room, l.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).padding(.top, 1)
                }
                if family != .systemSmall, let f = following {
                    Spacer(minLength: 6)
                    HStack(spacing: 5) {
                        Text("Danach").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        Text(f.subject).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(f.start, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            emptyHome
        }
    }

    private var dot: some View { Text("·").font(.caption2).foregroundStyle(.tertiary) }

    private var emptyHome: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Brand.positive)
            Text("Keine Stunden").font(.footnote.weight(.medium))
            Text("frei").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Lock Screen ─────────────────────────────────────────────────────────────
    @ViewBuilder private var inlineView: some View {
        if let l = current {
            if running { Label("\(l.subject) · \(timeString(l.end))", systemImage: "book.fill") }
            else { Label("\(l.subject) · \(timeString(l.start))", systemImage: "clock") }
        } else {
            Label("Keine Stunden", systemImage: "checkmark.circle")
        }
    }

    @ViewBuilder private var circularView: some View {
        if let l = current {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: l.isExam ? "pencil" : "book.fill").font(.system(size: 12, weight: .semibold))
                    Text(running ? l.end : l.start, style: .time)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                }
            }
        } else {
            ZStack { AccessoryWidgetBackground(); Image(systemName: "checkmark") }
        }
    }

    @ViewBuilder private var rectangularView: some View {
        if let l = current {
            VStack(alignment: .leading, spacing: 1) {
                Text(running ? "Jetzt" : "Als Nächstes")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
                Text(l.subject).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    if running {
                        Text(l.end, style: .timer).monospacedDigit().fixedSize()
                    } else {
                        Text(l.start, style: .time).monospacedDigit()
                    }
                    if !l.room.isEmpty { Text("· \(l.room)").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label("Keine Stunden mehr heute", systemImage: "checkmark.circle")
                .font(.subheadline)
        }
    }

    private func timeString(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

struct NextLessonWidget: Widget {
    let kind = "NextLessonWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextLessonProvider()) { entry in
            NextLessonWidgetView(entry: entry)
        }
        .configurationDisplayName("Nächste Stunde")
        .description("Deine laufende oder nächste Stunde – auch auf dem Sperrbildschirm.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
