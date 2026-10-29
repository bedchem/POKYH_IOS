import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Brücke App → Widget/Live-Activity: schreibt einen kompakten Stundenplan-Auszug
/// in den geteilten App-Group-Container und stößt ein Widget-Reload an.
enum WidgetBridge {
    /// Übernimmt die ab „jetzt" relevanten Stunden (klein gehalten, Performance).
    static func publish(_ entries: [TimetableEntry], now: Date = Date()) {
        let lessons: [LessonSnapshot] = entries
            .compactMap { e -> LessonSnapshot? in
                guard let start = UntisTime.date(e.date, e.startTime),
                      let end = UntisTime.date(e.date, e.endTime) else { return nil }
                return LessonSnapshot(
                    id: e.id, subject: e.subjectName, room: e.roomName,
                    teacher: e.teacherName, start: start, end: end,
                    isCancelled: e.isCancelled, isExam: e.isExam)
            }
            .filter { $0.end > now }                         // Vergangenes weglassen
            .sorted { $0.start < $1.start }

        let trimmed = Array(lessons.prefix(12))              // max. 12 Einträge
        SharedStore.writeSnapshot(TimetableSnapshot(generatedAt: now, lessons: trimmed))
        reload()
    }

    /// Noten-Snapshot: gewichteter Gesamtschnitt + zuletzt eingetragene Noten.
    static func publishGrades(_ subjects: [SubjectGrades], now: Date = Date()) {
        let allValues = subjects.flatMap { $0.grades.map { $0.markDisplayValue } }.filter { $0 > 0 }
        let avg = allValues.isEmpty ? 0 : (allValues.reduce(0, +) / Double(allValues.count) * 100).rounded() / 100
        let recent = subjects
            .flatMap { s in s.grades.filter { $0.markDisplayValue > 0 }.map { (s.subjectName, $0) } }
            .sorted { $0.1.id > $1.1.id }                    // zuletzt eingetragen
            .prefix(8)
            .map { GradeItem(id: $0.1.id, subject: $0.0, value: $0.1.markDisplayValue, date: $0.1.date) }
        SharedStore.writeGrades(GradesSnapshot(
            generatedAt: now, average: avg,
            positive: allValues.filter { $0 >= 6 }.count,
            negative: allValues.filter { $0 < 6 }.count,
            recent: Array(recent)))
        reload()
    }

    /// Nachrichten-Snapshot: Anzahl ungelesen + neueste Einträge.
    static func publishMessages(_ inbox: [MessagePreview], now: Date = Date()) {
        let latest = inbox.sorted { $0.id > $1.id }.prefix(6)
            .map { MessageItem(id: $0.id, sender: $0.senderName, subject: $0.subject, isRead: $0.isRead) }
        SharedStore.writeMessages(MessagesSnapshot(
            generatedAt: now, unread: inbox.filter { !$0.isRead }.count, latest: Array(latest)))
        reload()
    }

    private static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
