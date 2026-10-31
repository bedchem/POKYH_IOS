import ActivityKit
import SwiftUI
import WidgetKit
import PokyhCore
import PokyhDesign

private typealias LessonState = LessonActivityAttributes.ContentState

private extension LessonActivityAttributes.ContentState {
    var name: String { subject.isEmpty ? WidgetText.app.system.widgetEvent : subject }
    var label: String { isBreak ? WidgetText.own.pause : WidgetText.app.home.now }
    var caption: String { isBreak ? WidgetText.own.startsIn : WidgetText.own.endsIn }
    var symbol: String { isBreak ? "cup.and.saucer.fill" : "clock.fill" }
    var place: String { [room, teacher].filter { !$0.isEmpty }.joined(separator: " · ") }
    var tint: Color { isBreak ? Brand.orange : Brand.accent }
    var bar: Color { Tone.subject(subject).bar }
    var span: ClosedRange<Date> { start <= end ? start...end : end...end }

    /// During a break it runs to the next lesson's start, otherwise to the end of this one.
    var countdown: Text {
        if isBreak {
            return Text(timerInterval: min(Date.now, start)...start, countsDown: true)
        }
        return Text(timerInterval: span, countsDown: true)
    }
}

/// How far the lesson has come, drawn by the system so it moves without updates.
private struct LessonProgress: View {
    let state: LessonState

    var body: some View {
        ProgressView(timerInterval: state.span, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(state.tint)
    }
}

/// Lock Screen and the banner on devices without an island.
private struct LessonActivityView: View {
    let state: LessonState
    let className: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                LessonBar(color: state.bar, height: 52)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    WidgetLabel(title: className.isEmpty ? state.label : "\(state.label) · \(className)",
                                symbol: state.symbol, tint: state.tint)
                    Text(state.name)
                        .textStyle(.title2)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !state.place.isEmpty {
                        Text(state.place)
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(state.caption.uppercased())
                        .textStyle(.widgetHeader)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                    state.countdown
                        .textStyle(.liveActivityCountdown)
                        .foregroundStyle(state.tint)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                // A running timer asks for all the width it can get, so it gets a limit.
                .frame(width: 96, alignment: .trailing)
            }
            if !state.isBreak { LessonProgress(state: state) }
        }
        .padding(Spacing.lg)
    }
}

struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { context in
            LessonActivityView(state: context.state, className: context.attributes.className)
                .activityBackgroundTint(Palette.card)
                .activitySystemActionForegroundColor(Palette.textPrimary)
        } dynamicIsland: { context in
            island(context.state)
        }
    }

    private func island(_ state: LessonState) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    WidgetLabel(title: state.label, symbol: state.symbol, tint: state.tint)
                    Text(state.name)
                        .textStyle(.title3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.leading, Spacing.xs)
            }
            DynamicIslandExpandedRegion(.trailing) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(state.caption.uppercased())
                        .textStyle(.widgetHeader)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    state.countdown
                        .textStyle(.liveActivityCountdown)
                        .foregroundStyle(state.tint)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: 96, alignment: .trailing)
                .padding(.trailing, Spacing.xs)
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if !state.place.isEmpty {
                        Text(state.place)
                            .textStyle(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !state.isBreak { LessonProgress(state: state) }
                }
                .padding(.horizontal, Spacing.xs)
            }
        } compactLeading: {
            HStack(spacing: 5) {
                Circle().fill(state.bar).frame(width: 8, height: 8)
                Text(state.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: 64, alignment: .leading)
        } compactTrailing: {
            state.countdown
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(state.tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 44, alignment: .trailing)
        } minimal: {
            if state.isBreak {
                Image(systemName: state.symbol).foregroundStyle(state.tint)
            } else {
                Text(state.name.prefix(1))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(state.bar)
            }
        }
        .keylineTint(state.tint)
    }
}

// ── Previews ─────────────────────────────────────────────────────────────────

private extension LessonActivityAttributes {
    static var sample: LessonActivityAttributes { LessonActivityAttributes(className: "3A") }
}

private extension LessonActivityAttributes.ContentState {
    static var lesson: LessonState {
        LessonState(subject: "M", room: "A12", teacher: "Huber",
                    start: .now.addingTimeInterval(-1200), end: .now.addingTimeInterval(1800), isBreak: false)
    }
    static var pause: LessonState {
        LessonState(subject: "ENGL", room: "A12", teacher: "Kofler",
                    start: .now.addingTimeInterval(420), end: .now.addingTimeInterval(3420), isBreak: true)
    }
}

#Preview("Lock Screen", as: .content, using: LessonActivityAttributes.sample) {
    LessonLiveActivity()
} contentStates: {
    LessonActivityAttributes.ContentState.lesson
    LessonActivityAttributes.ContentState.pause
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: LessonActivityAttributes.sample) {
    LessonLiveActivity()
} contentStates: {
    LessonActivityAttributes.ContentState.lesson
    LessonActivityAttributes.ContentState.pause
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: LessonActivityAttributes.sample) {
    LessonLiveActivity()
} contentStates: {
    LessonActivityAttributes.ContentState.lesson
    LessonActivityAttributes.ContentState.pause
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: LessonActivityAttributes.sample) {
    LessonLiveActivity()
} contentStates: {
    LessonActivityAttributes.ContentState.lesson
    LessonActivityAttributes.ContentState.pause
}
