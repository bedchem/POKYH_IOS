import Foundation

/// The part of an absence the timetable needs. Dates YYYYMMDD, times HHMM.
public protocol AbsenceSpan {
    var startDate: Int { get }
    var endDate: Int { get }
    var startTime: Int { get }
    var endTime: Int { get }
    var isExcused: Bool { get }
}

/// What the timetable says about a lesson the student is or was absent from: not over yet means
/// reported in advance, otherwise excused or not as WebUntis has it.
public enum AbsenceMark: Equatable, Sendable {
    case preExcused, excused, absent
}

/// One stretch of a day under the same mark, in minutes of the day.
public struct AbsenceBand: Equatable, Sendable {
    public var startMinute: Int
    public var endMinute: Int
    public var mark: AbsenceMark

    public init(startMinute: Int, endMinute: Int, mark: AbsenceMark) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.mark = mark
    }
}

/// A lesson's absence status and the absences behind it.
public struct LessonAbsence<Item: AbsenceSpan> {
    public let mark: AbsenceMark
    public let covering: [Item]
}

public enum AbsenceMarks {
    private static let minutesPerDay = 1440
    /// Arriving two minutes late shouldn't draw a sliver over the lesson.
    private static let minCoveredMinutes = 15

    public static func clockMinutes(_ hhmm: Int) -> Int { hhmm / 100 * 60 + hhmm % 100 }

    public static func mark<Item: AbsenceSpan>(_ absences: [Item], date: Int, start: Int, end: Int,
                                               nowDate: Int, nowMinute: Int) -> AbsenceMark? {
        coverage(absences, date: date, start: start, end: end, nowDate: nowDate, nowMinute: nowMinute)?.band.mark
    }

    public static func lessonAbsence<Item: AbsenceSpan>(_ absences: [Item], date: Int, start: Int, end: Int,
                                                        nowDate: Int, nowMinute: Int) -> LessonAbsence<Item>? {
        coverage(absences, date: date, start: start, end: end, nowDate: nowDate, nowMinute: nowMinute)
            .map { LessonAbsence(mark: $0.band.mark, covering: $0.covering) }
    }

    /// Bands for one day, from exactly where the absence starts to where it ends. A band runs on
    /// through breaks and free periods; only a lesson that was attended ends it. Callers leave
    /// cancelled lessons out, nobody is absent from a lesson that doesn't happen.
    public static func bands<Item: AbsenceSpan>(_ absences: [Item], date: Int, lessons: [(start: Int, end: Int)],
                                                nowDate: Int, nowMinute: Int) -> [AbsenceBand] {
        guard !absences.isEmpty else { return [] }
        var out: [AbsenceBand] = []
        var open = false
        for lesson in lessons.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            guard let covered = coverage(absences, date: date, start: lesson.start, end: lesson.end,
                                         nowDate: nowDate, nowMinute: nowMinute)?.band else {
                open = false
                continue
            }
            if open, let last = out.last, last.mark == covered.mark {
                out[out.count - 1].endMinute = max(last.endMinute, covered.endMinute)
            } else {
                out.append(covered)
                open = true
            }
        }
        return out
    }

    /// "10:00 – 13:05", or with dates when it spans several days.
    public static func rangeText<Item: AbsenceSpan>(_ absence: Item, wholeDay: String) -> String {
        func clock(_ time: Int) -> String {
            let minutes = clockMinutes(time)
            return String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
        func day(_ date: Int) -> String { String(format: "%02d.%02d.", date % 100, date / 100 % 100) }
        let from = absence.startTime > 0 ? clock(absence.startTime) : ""
        let to = absence.endTime > 0 ? clock(absence.endTime) : ""
        if absence.startDate == absence.endDate {
            return !from.isEmpty && !to.isEmpty ? "\(from) – \(to)" : wholeDay
        }
        let start = from.isEmpty ? day(absence.startDate) : "\(day(absence.startDate)) \(from)"
        let end = to.isEmpty ? day(absence.endDate) : "\(day(absence.endDate)) \(to)"
        return "\(start) – \(end)"
    }

    /// The mark plus the part of the lesson the absence covers: an absence from 10:00 over a
    /// 09:30–10:20 lesson covers 10:00–10:20, not the lesson.
    private static func coverage<Item: AbsenceSpan>(_ absences: [Item], date: Int, start: Int, end: Int,
                                                    nowDate: Int, nowMinute: Int) -> (band: AbsenceBand, covering: [Item])? {
        let dayStart = date * minutesPerDay
        let lessonStart = dayStart + start
        let lessonEnd = dayStart + end
        var from = Int.max
        var to = Int.min
        let covering = absences.filter { a in
            guard a.startDate != 0, a.endDate != 0 else { return false }
            let absenceStart = a.startDate * minutesPerDay + (a.startTime > 0 ? clockMinutes(a.startTime) : 0)
            let absenceEnd = a.endDate * minutesPerDay + (a.endTime > 0 ? clockMinutes(a.endTime) : minutesPerDay)
            let coveredFrom = max(lessonStart, absenceStart)
            let coveredTo = min(lessonEnd, absenceEnd)
            guard coveredTo - coveredFrom >= min(minCoveredMinutes, lessonEnd - lessonStart) else { return false }
            from = min(from, coveredFrom)
            to = max(to, coveredTo)
            return true
        }
        guard !covering.isEmpty else { return nil }
        let over = date < nowDate || (date == nowDate && end <= nowMinute)
        let mark: AbsenceMark = !over ? .preExcused : covering.allSatisfy(\.isExcused) ? .excused : .absent
        return (AbsenceBand(startMinute: from - dayStart, endMinute: to - dayStart, mark: mark), covering)
    }
}

extension TimetableStrings {
    public func label(_ mark: AbsenceMark) -> String {
        switch mark {
        case .preExcused: markPreExcused
        case .excused: markExcused
        case .absent: markAbsent
        }
    }

    public func shortLabel(_ mark: AbsenceMark) -> String {
        switch mark {
        case .preExcused: markPreExcusedShort
        case .excused: markExcusedShort
        case .absent: markAbsentShort
        }
    }
}
