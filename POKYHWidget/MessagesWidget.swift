import WidgetKit
import SwiftUI

/// Home-Screen-Widget: ungelesene Nachrichten + neueste Betreffzeilen.
struct MessagesEntry: TimelineEntry { let date: Date; let snapshot: MessagesSnapshot }

struct MessagesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MessagesEntry { MessagesEntry(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (MessagesEntry) -> Void) {
        completion(MessagesEntry(date: Date(), snapshot: SharedStore.readMessages()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MessagesEntry>) -> Void) {
        let entry = MessagesEntry(date: Date(), snapshot: SharedStore.readMessages())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct MessagesWidgetView: View {
    var entry: MessagesEntry
    @Environment(\.widgetFamily) private var family
    private var snap: MessagesSnapshot { entry.snapshot }

    var body: some View {
        Group { family == .systemSmall ? AnyView(small) : AnyView(medium) }
            .pokyhWidgetBackground()
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "envelope.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.accent)
            Text("NACHRICHTEN").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if snap.unread > 0 {
                Text("\(snap.unread)")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Brand.danger, in: Capsule())
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            Text("\(snap.unread)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(snap.unread > 0 ? Brand.accent : .secondary)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text("ungelesen").font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if snap.latest.isEmpty {
                Spacer()
                Text("Keine Nachrichten").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(snap.latest.prefix(4)) { m in
                    HStack(spacing: 8) {
                        Circle().fill(m.isRead ? Color.secondary.opacity(0.25) : Brand.accent)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.sender).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(m.subject.isEmpty ? "(kein Betreff)" : m.subject)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct MessagesWidget: Widget {
    let kind = "MessagesWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MessagesProvider()) { entry in
            MessagesWidgetView(entry: entry)
        }
        .configurationDisplayName("Nachrichten")
        .description("Ungelesene Nachrichten und die neuesten Betreffzeilen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
