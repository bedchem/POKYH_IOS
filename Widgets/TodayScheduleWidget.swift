import WidgetKit
import SwiftUI

/// Home-Screen-Widget: heutiger Stundenplan als Liste (verbleibende Stunden).
struct TodayEntry: TimelineEntry { let date: Date; let snapshot: TimetableSnapshot }

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: SharedStore.readSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snap = SharedStore.readSnapshot()
        let now = Date()
        var pivots: [Date] = [now]
        for l in snap.lessons.prefix(8) where l.end > now { pivots.append(l.end) }
        let entries = Array(Set(pivots)).sorted().map { TodayEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries.isEmpty ? [TodayEntry(date: now, snapshot: snap)] : entries,
                            policy: .after(now.addingTimeInterval(3600))))
    }
}

struct TodayWidgetView: View {
    var entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var todays: [LessonSnapshot] {
        entry.snapshot.lessons.filter { Calendar.current.isDateInToday($0.start) && $0.end > entry.date }
    }
    private var maxRows: Int { family == .systemLarge ? 8 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.accent)
                Text("HEUTE").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(entry.date, format: .dateTime.weekday(.wide))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            }
            if todays.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Brand.positive)
                    Text("Keine Stunden mehr").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(todays.prefix(maxRows)) { row($0) }
                Spacer(minLength: 0)
            }
        }
        .pokyhWidgetBackground()
    }

    private func row(_ l: LessonSnapshot) -> some View {
        HStack(spacing: 9) {
            Text(l.start, style: .time)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            Capsule().fill(l.isExam ? Brand.danger : Brand.accent).frame(width: 3, height: 16)
            Text(l.subject).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            if !l.room.isEmpty {
                Text(l.room).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

struct TodayScheduleWidget: Widget {
    let kind = "TodayScheduleWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Heutiger Plan")
        .description("Alle verbleibenden Stunden von heute auf einen Blick.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
