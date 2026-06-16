import WidgetKit
import SwiftUI

/// Kombiniertes Widget: nächste Stunde + Notenschnitt + ungelesene Nachrichten.
struct OverviewEntry: TimelineEntry {
    let date: Date
    let timetable: TimetableSnapshot
    let grades: GradesSnapshot
    let messages: MessagesSnapshot
}

struct OverviewProvider: TimelineProvider {
    private func current(_ date: Date = Date()) -> OverviewEntry {
        OverviewEntry(date: date,
                      timetable: SharedStore.readSnapshot(),
                      grades: SharedStore.readGrades(),
                      messages: SharedStore.readMessages())
    }
    func placeholder(in context: Context) -> OverviewEntry {
        OverviewEntry(date: Date(), timetable: .empty, grades: .empty, messages: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (OverviewEntry) -> Void) { completion(current()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<OverviewEntry>) -> Void) {
        let snap = SharedStore.readSnapshot()
        let now = Date()
        var pivots: [Date] = [now]
        for l in snap.lessons.prefix(6) where !l.isCancelled {
            if l.start > now { pivots.append(l.start) }
            if l.end > now { pivots.append(l.end) }
        }
        let entries = Array(Set(pivots)).sorted().map { current($0) }
        completion(Timeline(entries: entries.isEmpty ? [current(now)] : entries,
                            policy: .after(now.addingTimeInterval(3600))))
    }
}

struct OverviewWidgetView: View {
    var entry: OverviewEntry
    @Environment(\.widgetFamily) private var family

    private var lesson: LessonSnapshot? {
        entry.timetable.lessons.first { !$0.isCancelled && $0.end > entry.date }
    }
    private var hasGrades: Bool { !entry.grades.recent.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nextLessonBlock
            Divider()
            HStack(spacing: 10) {
                statTile("chart.bar.fill", "Schnitt",
                         hasGrades ? GradeFormat.string(entry.grades.average) : "–",
                         hasGrades ? Brand.grade(entry.grades.average) : .secondary)
                statTile("envelope.fill", "Ungelesen", "\(entry.messages.unread)",
                         entry.messages.unread > 0 ? Brand.accent : .secondary)
            }
            if family == .systemLarge { largeExtras }
        }
        .pokyhWidgetBackground()
    }

    @ViewBuilder private var nextLessonBlock: some View {
        if let l = lesson {
            let running = l.start <= entry.date
            VStack(alignment: .leading, spacing: 2) {
                WidgetHeader(icon: l.isExam ? "pencil.and.list.clipboard" : "book.fill",
                             title: running ? "Jetzt" : "Als Nächstes")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(l.subject).font(.system(.headline, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if running {
                        Text(l.end, style: .timer)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Brand.accent).fixedSize()
                    } else {
                        Text(l.start, style: .time)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Brand.accent)
                    }
                }
                if !l.room.isEmpty || !l.teacher.isEmpty {
                    Text([l.room, l.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Brand.positive)
                Text("Keine Stunden mehr heute").font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var largeExtras: some View {
        if hasGrades {
            Divider()
            Text("ZULETZT").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            ForEach(entry.grades.recent.prefix(3)) { g in
                HStack {
                    Text(g.subject).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text(GradeFormat.string(g.value)).font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Brand.grade(g.value))
                }
            }
        }
        Spacer(minLength: 0)
    }

    private func statTile(_ icon: String, _ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.callout).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewWidget: Widget {
    let kind = "OverviewWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OverviewProvider()) { entry in
            OverviewWidgetView(entry: entry)
        }
        .configurationDisplayName("Überblick")
        .description("Nächste Stunde, Notenschnitt und ungelesene Nachrichten auf einen Blick.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
