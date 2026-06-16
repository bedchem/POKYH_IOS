import ActivityKit
import WidgetKit
import SwiftUI

/// Live-Activity-UI für Sperrbildschirm und Dynamic Island.
/// Das Datenmodell `LessonActivityAttributes` stammt aus dem geteilten `SharedKit`.
struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { context in
            lockScreen(context.state, className: context.attributes.className)
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let st = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.isBreak ? "Pause" : "Jetzt")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(st.subject).font(.headline).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(st).font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Brand.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        if !st.room.isEmpty { tag("mappin.and.ellipse", st.room) }
                        if !st.teacher.isEmpty { tag("person.fill", st.teacher) }
                        Spacer()
                    }
                }
            } compactLeading: {
                Image(systemName: st.isBreak ? "cup.and.saucer.fill" : "book.fill")
                    .foregroundStyle(Brand.accent)
            } compactTrailing: {
                countdown(st).font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Brand.accent)
            } minimal: {
                Image(systemName: "book.fill").foregroundStyle(Brand.accent)
            }
        }
    }

    @ViewBuilder private func lockScreen(_ st: LessonActivityAttributes.ContentState, className: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(st.isBreak ? "Pause · bis zur nächsten Stunde" : "Aktuelle Stunde")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(st.subject).font(.title3.weight(.bold)).lineLimit(1)
                HStack(spacing: 10) {
                    if !st.room.isEmpty { tag("mappin.and.ellipse", st.room) }
                    if !st.teacher.isEmpty { tag("person.fill", st.teacher) }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                countdown(st).font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Brand.accent)
                Text(st.isBreak ? "bis Start" : "verbleibend")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Zeigt den Countdown bis Beginn (Pause) bzw. bis Ende (laufende Stunde).
    private func countdown(_ st: LessonActivityAttributes.ContentState) -> Text {
        Text(st.isBreak ? st.start : st.end, style: .timer)
    }

    private func tag(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}
