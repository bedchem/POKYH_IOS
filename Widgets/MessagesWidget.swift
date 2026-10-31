import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

/// Unread count and the latest messages. Senders and subjects are private: a locked phone keeps
/// the count, like an app badge, and gets a notice instead of the rest.
struct MessagesEntry: TimelineEntry {
    let date: Date
    let snapshot: MessagesSnapshot
    var sealed = false
}

struct MessagesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MessagesEntry {
        MessagesEntry(date: .now, snapshot: WidgetSamples.messages)
    }

    func getSnapshot(in context: Context, completion: @escaping (MessagesEntry) -> Void) {
        let data = WidgetData.messages(preview: context.isPreview)
        completion(MessagesEntry(date: .now, snapshot: data.snapshot, sealed: data.sealed))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MessagesEntry>) -> Void) {
        let now = Date.now
        let data = WidgetData.messages()
        let entry = MessagesEntry(date: now, snapshot: data.snapshot, sealed: data.sealed)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(1800))))
    }
}

/// Initials in the sender's color, as in the app's message list.
struct SenderAvatar: View {
    let name: String
    @Environment(\.widgetRenderingMode) private var mode

    private var initials: String {
        name.split(whereSeparator: \.isWhitespace).prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    var body: some View {
        let plain = mode == .fullColor
        Text(initials)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(plain ? Brand.onAccent : Palette.textPrimary)
            .frame(width: 26, height: 26)
            .background(plain ? AnyShapeStyle(Palette.sender(name)) : AnyShapeStyle(.quaternary), in: Circle())
    }
}

struct MessageLine: View {
    let item: MessageItem

    var body: some View {
        HStack(spacing: 10) {
            SenderAvatar(name: item.sender)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.sender)
                    .textStyle(.footnote.weight(item.isRead ? .medium : .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(item.subject.isEmpty ? WidgetText.app.messages.noSubject : item.subject)
                    .textStyle(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            if !item.isRead {
                SubjectDot(color: Brand.accent, size: 8)
            }
        }
        .privacySensitive()
    }
}

struct MessagesWidgetView: View {
    let entry: MessagesEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.hidesPrivateData) private var hidesPrivateData

    private var s: Strings { WidgetText.app }
    private var t: WidgetStrings { WidgetText.own }
    private var snap: MessagesSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if family == .systemSmall { small } else { medium }
        }
        .widgetCanvas()
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            WidgetLabel(title: s.home.sectionMessages, symbol: "envelope.fill")
            if snap.unread > 0 { CountBadge(count: snap.unread).privacySensitive() }
        }
    }

    @ViewBuilder private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(title: s.home.sectionMessages, symbol: "envelope.fill")
            if entry.sealed {
                WidgetNotice.locked(sealed: true)
            } else {
                Spacer(minLength: Spacing.xs)
                Text(snap.unread, format: .number)
                    .widgetNumeral()
                    .foregroundStyle(snap.unread > 0 ? Brand.accent : Palette.textTertiary)
                    .widgetAccentable()
                    .privacySensitive()
                Text(t.unread)
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: Spacing.xs)
                footer
            }
        }
    }

    /// Who wrote last, or the reason that's hidden.
    @ViewBuilder private var footer: some View {
        if hidesPrivateData {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "lock.fill")
                Text(t.unlockToView)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .textStyle(.caption2)
            .foregroundStyle(Palette.textSecondary)
        } else if let latest = snap.latest.first {
            Text(latest.sender)
                .textStyle(.caption.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .privacySensitive()
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            if entry.sealed || hidesPrivateData {
                WidgetNotice.locked(sealed: entry.sealed)
            } else if snap.latest.isEmpty {
                WidgetNotice(symbol: "envelope.open.fill", title: s.home.noMessages, tint: Brand.success)
            } else {
                FittingCount(most: min(3, snap.latest.count)) { count in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(snap.latest.prefix(count)) { MessageLine(item: $0) }
                    }
                }
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
        .configurationDisplayName(WidgetText.app.home.sectionMessages)
        .description(WidgetText.own.messagesInfo)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── Previews ─────────────────────────────────────────────────────────────────

private extension MessagesEntry {
    static var filled: MessagesEntry { MessagesEntry(date: .now, snapshot: WidgetSamples.messages) }
    static var none: MessagesEntry { MessagesEntry(date: .now, snapshot: .empty) }
    static var closed: MessagesEntry { MessagesEntry(date: .now, snapshot: .empty, sealed: true) }
}

#Preview("Small", as: .systemSmall) {
    MessagesWidget()
} timeline: {
    MessagesEntry.filled
    MessagesEntry.none
    MessagesEntry.closed
}

#Preview("Medium", as: .systemMedium) {
    MessagesWidget()
} timeline: {
    MessagesEntry.filled
    MessagesEntry.none
    MessagesEntry.closed
}
