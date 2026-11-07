import Foundation
#if os(iOS)
import ActivityKit
#endif

/// Runs the Live Activity for the running or next lesson (Lock Screen and Dynamic
/// Island): starts, updates and ends it from the timetable. The widget extension draws it
/// (`ActivityConfiguration`).
enum LiveActivityManager {
    #if os(iOS)
    static func refresh(from entries: [TimetableEntry], className: String, now: Date = Date()) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Today's lessons from now on that take place, in order.
        let upcoming = entries
            .compactMap { e -> (start: Date, end: Date, entry: TimetableEntry)? in
                guard !e.isCancelled,
                      let s = UntisTime.date(e.date, e.startTime),
                      let en = UntisTime.date(e.date, e.endTime) else { return nil }
                return (s, en, e)
            }
            .filter { $0.end > now && Calendar.current.isDateInToday($0.start) }
            .sorted { $0.start < $1.start }

        guard let next = upcoming.first else { endAll(); return }

        let running = next.start <= now
        let state = LessonActivityAttributes.ContentState(
            subject: next.entry.subjectName,
            room: next.entry.roomName,
            teacher: next.entry.teacherName,
            start: next.start,
            end: next.end,
            isBreak: !running)
        let content = ActivityContent(state: state, staleDate: next.end)

        if let activity = Activity<LessonActivityAttributes>.activities.first {
            Task { await activity.update(content) }
        } else {
            do {
                _ = try Activity.request(
                    attributes: LessonActivityAttributes(className: className),
                    content: content,
                    pushType: nil)
            } catch {
                // Quietly ignored, e.g. when Live Activities are turned off.
            }
        }
    }

    static func endAll() {
        Task {
            for activity in Activity<LessonActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    #else
    static func refresh(from entries: [TimetableEntry], className: String, now: Date = Date()) {}
    static func endAll() {}
    #endif
}
