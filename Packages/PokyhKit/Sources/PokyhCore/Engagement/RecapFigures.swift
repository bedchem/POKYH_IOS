import Foundation

/// What the timetable, absences, grades, exams, homework and class register of a period add up to.
/// Worked out on the device from what the student's own session loads; none of it is sent anywhere.
///
///   lessons in school  every lesson of the period that has ended and wasn't cancelled
///                      (lessons at the same time count once)
///   missed minutes     the school's own ("Fehlzeiten") where it gives them, else worked out from
///                      the timetable, else lesson hours × the school's usual lesson length
///   absence rate       missed minutes against lesson minutes, only when every week could be loaded
public enum RecapFigures {
    public enum State: Int, Codable, Sendable {
        case lesson, cancelled, substitution, exam
    }

    /// Minutes of the day, subject, teacher(s), room.
    public struct Lesson: Codable, Equatable, Sendable {
        public var start: Int, end: Int, subject: String, teachers: String, room: String, state: State
        public init(start: Int, end: Int, subject: String, teachers: String, room: String, state: State) {
            self.start = start; self.end = end; self.subject = subject
            self.teachers = teachers; self.room = room; self.state = state
        }
    }

    /// A week of the timetable: when it was loaded, its lessons per day (YYYYMMDD).
    public struct Week: Codable, Equatable, Sendable {
        public var at: Int64
        public var days: [Int: [Lesson]]
        public init(at: Int64, days: [Int: [Lesson]]) {
            self.at = at
            self.days = days
        }
    }

    public struct Ranked: Equatable, Sendable {
        public var name: String, value: Int, lessons: Int
        public init(name: String, value: Int, lessons: Int) {
            self.name = name
            self.value = value
            self.lessons = lessons
        }
    }

    public struct DayTime: Equatable, Sendable {
        public var date: Int, minutes: Int
        public init(date: Int, minutes: Int) {
            self.date = date
            self.minutes = minutes
        }
    }

    public struct LongestDay: Equatable, Sendable {
        public var date: Int, start: Int, end: Int
        public init(date: Int, start: Int, end: Int) {
            self.date = date
            self.start = start
            self.end = end
        }
    }

    public struct School: Equatable, Sendable {
        public var days: Int, lessons: Int, minutes: Int, cancelled: Int, substitutions: Int
        public var subjects: [Ranked], teachers: [Ranked], rooms: [Ranked]
        public var longestDay: LongestDay?
        public var earliest: DayTime?
        public var latest: DayTime?

        public init(days: Int, lessons: Int, minutes: Int, cancelled: Int, substitutions: Int, subjects: [Ranked], teachers: [Ranked],
                    rooms: [Ranked], longestDay: LongestDay?, earliest: DayTime?, latest: DayTime?) {
            self.days = days; self.lessons = lessons; self.minutes = minutes; self.cancelled = cancelled
            self.substitutions = substitutions; self.subjects = subjects; self.teachers = teachers; self.rooms = rooms
            self.longestDay = longestDay; self.earliest = earliest; self.latest = latest
        }
    }

    public struct Absences: Equatable, Sendable {
        public var entries: Int, openEntries: Int, missedMinutes: Int, excusedMinutes: Int
        public var possibleMinutes: Int?
        public var rate: Double?
        public var missedDays: Int
        public var bySubject: [Ranked]
        /// Monday first.
        public var byWeekday: [Int]

        public init(entries: Int, openEntries: Int, missedMinutes: Int, excusedMinutes: Int, possibleMinutes: Int?, rate: Double?,
                    missedDays: Int, bySubject: [Ranked], byWeekday: [Int]) {
            self.entries = entries; self.openEntries = openEntries; self.missedMinutes = missedMinutes
            self.excusedMinutes = excusedMinutes; self.possibleMinutes = possibleMinutes; self.rate = rate
            self.missedDays = missedDays; self.bySubject = bySubject; self.byWeekday = byWeekday
        }
    }

    public struct SubjectAverage: Equatable, Sendable {
        public var name: String, average: Double, count: Int
        public init(name: String, average: Double, count: Int) {
            self.name = name
            self.average = average
            self.count = count
        }
    }

    public struct TopGrade: Equatable, Sendable {
        public var value: Double, subject: String, date: Int
        public init(value: Double, subject: String, date: Int) {
            self.value = value
            self.subject = subject
            self.date = date
        }
    }

    public struct Grades: Equatable, Sendable {
        public var count: Int, average: Double, positive: Int, negative: Int
        public var subjects: [SubjectAverage]
        public var best: SubjectAverage?
        public var top: TopGrade?

        public init(count: Int, average: Double, positive: Int, negative: Int, subjects: [SubjectAverage], best: SubjectAverage?, top: TopGrade?) {
            self.count = count; self.average = average; self.positive = positive; self.negative = negative
            self.subjects = subjects; self.best = best; self.top = top
        }
    }

    public struct Untis: Equatable, Sendable {
        public var complete: Bool, weeksLoaded: Int, weeksTotal: Int
        public var school: School?
        public var absences: Absences?
        public var grades: Grades?
        public var exams: Int?
        public var homework: Int?
        public var classreg: Int?

        public init(complete: Bool = false, weeksLoaded: Int = 0, weeksTotal: Int = 0, school: School? = nil, absences: Absences? = nil,
                    grades: Grades? = nil, exams: Int? = nil, homework: Int? = nil, classreg: Int? = nil) {
            self.complete = complete; self.weeksLoaded = weeksLoaded; self.weeksTotal = weeksTotal
            self.school = school; self.absences = absences; self.grades = grades
            self.exams = exams; self.homework = homework; self.classreg = classreg
        }
    }

    public struct AbsenceIn: Equatable, Sendable {
        public var id: Int, startDate: Int, endDate: Int, startTime: Int, endTime: Int
        public var isExcused: Bool, hours: Int
        public var subjectName: String?
        public init(id: Int, startDate: Int, endDate: Int, startTime: Int, endTime: Int, isExcused: Bool, hours: Int, subjectName: String?) {
            self.id = id; self.startDate = startDate; self.endDate = endDate; self.startTime = startTime
            self.endTime = endTime; self.isExcused = isExcused; self.hours = hours; self.subjectName = subjectName
        }
    }

    /// One row of the school's own "Fehlzeiten".
    public struct TimeIn: Equatable, Sendable {
        public var absenceId: Int, minutes: Int, subject: String, excused: Bool, date: Int
        public init(absenceId: Int, minutes: Int, subject: String, excused: Bool, date: Int) {
            self.absenceId = absenceId; self.minutes = minutes; self.subject = subject
            self.excused = excused; self.date = date
        }
    }

    public struct GradeIn: Equatable, Sendable {
        public var date: Int, value: Double
        public init(date: Int, value: Double) {
            self.date = date
            self.value = value
        }
    }

    public struct GradeSubjectIn: Equatable, Sendable {
        public var subjectName: String, grades: [GradeIn]
        public init(subjectName: String, grades: [GradeIn]) {
            self.subjectName = subjectName
            self.grades = grades
        }
    }

    public struct HomeworkIn: Equatable, Sendable {
        public var id: Int, dueDate: Int
        public init(id: Int, dueDate: Int) {
            self.id = id
            self.dueDate = dueDate
        }
    }

    /// Today and the time on the clock, local.
    public struct Now: Equatable, Sendable {
        public var day: Int, minutes: Int
        public init(day: Int, minutes: Int) {
            self.day = day
            self.minutes = minutes
        }

        public init(ms: Int64, clock: DayClock = DayClock()) {
            let p = clock.parts(ms)
            self.init(day: p.year * 10000 + p.month * 100 + p.day, minutes: p.hour * 60 + p.minute)
        }
    }

    public struct Sources: Sendable {
        public var from: Int, to: Int, now: Now
        /// By their Monday, YYYY-MM-DD.
        public var weeks: [String: Week]
        public var absences: [AbsenceIn]?
        public var times: [TimeIn]?
        public var grades: [GradeSubjectIn]?
        public var homework: [HomeworkIn]?
        public var classreg: [Int]?

        public init(from: Int, to: Int, now: Now, weeks: [String: Week] = [:], absences: [AbsenceIn]? = nil, times: [TimeIn]? = nil,
                    grades: [GradeSubjectIn]? = nil, homework: [HomeworkIn]? = nil, classreg: [Int]? = nil) {
            self.from = from; self.to = to; self.now = now; self.weeks = weeks; self.absences = absences
            self.times = times; self.grades = grades; self.homework = homework; self.classreg = classreg
        }
    }

    // ── Days as numbers ─────────────────────────────────────────────────────

    private static let days: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return c
    }()

    static func date(_ n: Int) -> Date? {
        let parts = DateComponents(year: n / 10000, month: n / 100 % 100, day: n % 100)
        return parts.isValidDate(in: days) ? days.date(from: parts) : nil
    }

    static func num(_ d: Date) -> Int {
        let c = days.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    static func iso(_ d: Date) -> String {
        let c = days.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func monday(of d: Date) -> Date {
        days.date(byAdding: .day, value: -weekday(d), to: d) ?? d
    }

    /// Monday = 0 … Sunday = 6.
    static func weekday(_ d: Date) -> Int {
        (days.component(.weekday, from: d) + 5) % 7
    }

    public static func numOfISO(_ iso: String) -> Int {
        Int(iso.replacingOccurrences(of: "-", with: "")) ?? 0
    }

    /// The year a date's school year starts in: September on.
    public static func schoolYear(of n: Int) -> Int {
        n / 100 % 100 >= 9 ? n / 10000 : n / 10000 - 1
    }

    /// The Mondays (YYYY-MM-DD) of the weeks from `from` up to the earlier of `to` and today.
    public static func periodWeeks(from: Int, to: Int, now: Now) -> [String] {
        let end = min(to, now.day)
        guard end >= from, let last = date(end), let first = date(from) else { return [] }
        var out: [String] = []
        var d = monday(of: first)
        while d <= last {
            out.append(iso(d))
            guard let next = days.date(byAdding: .day, value: 7, to: d) else { break }
            d = next
        }
        return out
    }

    /// Whether a stored week should be loaded again. One read before the week was over may have
    /// changed since; one long gone hardly will.
    public static func weekIsDue(_ week: Week?, monday: String, now: Int64, clock: DayClock = DayClock()) -> Bool {
        guard let week else { return true }
        guard let start = clock.parse(monday) else { return true }
        let over = clock.addDays(start, 7)
        let minute: Int64 = 60_000
        let ttl: Int64
        if week.at < over {
            ttl = 30 * minute
        } else if now - over > 14 * 24 * 60 * minute {
            ttl = 30 * 24 * 60 * minute
        } else {
            ttl = 24 * 60 * minute
        }
        return now - week.at > ttl
    }

    /// HHMM to minutes of the day; something that isn't a time stays as it is.
    public static func toMinutes(_ t: Int) -> Int {
        if t == 0 { return 0 }
        if t > 2359 || t % 100 > 59 { return t }
        return t / 100 * 60 + t % 100
    }

    /// A lesson as the figures count it; nil for one with no subject or no length.
    public static func lesson(startTime: Int, endTime: Int, subject: String, teachers: String, room: String,
                              cancelled: Bool, exam: Bool, substitution: Bool) -> Lesson? {
        let start = toMinutes(startTime), end = toMinutes(endTime)
        guard !subject.isEmpty, end > start else { return nil }
        let state: State = cancelled ? .cancelled : exam ? .exam : substitution ? .substitution : .lesson
        return Lesson(start: start, end: end, subject: subject, teachers: teachers, room: room, state: state)
    }

    // ── Counting ────────────────────────────────────────────────────────────

    private struct Tally {
        var value = 0
        var lessons = 0
    }

    private static func ranked(_ map: [String: Tally], limit: Int = 5) -> [Ranked] {
        let rows = map.map { Ranked(name: $0.key, value: $0.value.value, lessons: $0.value.lessons) }
        let sorted = rows.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            if $0.lessons != $1.lessons { return $0.lessons > $1.lessons }
            return $0.name < $1.name
        }
        return Array(sorted.prefix(limit))
    }

    private static func count(_ map: inout [String: Tally], _ name: String, value: Int, lessons: Int) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return }
        map[key, default: Tally()].value += value
        map[key, default: Tally()].lessons += lessons
    }

    private static func parts(_ text: String) -> [String] {
        text.components(separatedBy: ", ")
    }

    private static func round(_ x: Double) -> Int {
        Int((x + 0.5).rounded(.down))
    }

    /// Lessons at the same time once: merged spans.
    private static func mergedSpans(_ lessons: [Lesson]) -> [(start: Int, end: Int)] {
        var out: [(start: Int, end: Int)] = []
        for l in lessons.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, l.start < last.end {
                out[out.count - 1].end = max(last.end, l.end)
            } else {
                out.append((l.start, l.end))
            }
        }
        return out
    }

    private struct Day {
        let date: Int
        let lessons: [Lesson]
    }

    private static func periodDays(_ src: Sources) -> [Day] {
        let until = min(src.to, src.now.day)
        var out: [Day] = []
        for week in src.weeks.values {
            for (date, lessons) in week.days where date >= src.from && date <= until {
                out.append(Day(date: date, lessons: date < src.now.day ? lessons : lessons.filter { $0.end <= src.now.minutes }))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// The length of one lesson in the period: the most common up to an hour; 50 without any.
    private static func singleLesson(_ days: [Day]) -> Int {
        var lengths: [Int: Int] = [:]
        for d in days {
            for l in d.lessons where l.end - l.start <= 60 { lengths[l.end - l.start, default: 0] += 1 }
        }
        var best = 50, most = 0
        for (length, n) in lengths where n > most || (n == most && length > best) {
            best = length
            most = n
        }
        return best
    }

    private static func periods(_ l: Lesson, single: Int) -> Int {
        max(1, round(Double(l.end - l.start) / Double(single)))
    }

    private static func distinct(_ lessons: [Lesson]) -> [Lesson] {
        var seen = Set<String>()
        return lessons.filter { seen.insert("\($0.start)-\($0.end)-\($0.subject)").inserted }
    }

    private static func schoolFigures(_ days: [Day]) -> School {
        let single = singleLesson(days)
        var subjects: [String: Tally] = [:], teachers: [String: Tally] = [:], rooms: [String: Tally] = [:]
        var lessons = 0, minutes = 0, cancelled = 0, substitutions = 0, schoolDays = 0
        var longest: LongestDay?, earliest: DayTime?, latest: DayTime?
        for day in days {
            let all = distinct(day.lessons)
            for l in all where l.state == .cancelled { cancelled += periods(l, single: single) }
            let held = all.filter { $0.state != .cancelled }
            if held.isEmpty { continue }
            schoolDays += 1
            for l in held {
                let n = periods(l, single: single)
                lessons += n
                if l.state == .substitution { substitutions += n }
                count(&subjects, l.subject, value: l.end - l.start, lessons: n)
                for t in parts(l.teachers) { count(&teachers, t, value: n, lessons: n) }
                for r in parts(l.room) { count(&rooms, r, value: n, lessons: n) }
            }
            let spans = mergedSpans(held)
            minutes += spans.reduce(0) { $0 + $1.end - $1.start }
            guard let start = spans.first?.start, let end = spans.last?.end else { continue }
            if longest.map({ end - start > $0.end - $0.start }) ?? true { longest = LongestDay(date: day.date, start: start, end: end) }
            if earliest.map({ start < $0.minutes }) ?? true { earliest = DayTime(date: day.date, minutes: start) }
            if latest.map({ end > $0.minutes }) ?? true { latest = DayTime(date: day.date, minutes: end) }
        }
        return School(days: schoolDays, lessons: lessons, minutes: minutes, cancelled: cancelled, substitutions: substitutions,
                      subjects: ranked(subjects), teachers: ranked(teachers), rooms: ranked(rooms),
                      longestDay: longest, earliest: earliest, latest: latest)
    }

    private static func usualLessonMinutes(_ days: [Day]) -> Int {
        var lengths: [Int: Int] = [:]
        for d in days {
            for s in mergedSpans(d.lessons.filter { $0.state != .cancelled }) { lengths[s.end - s.start, default: 0] += 1 }
        }
        var best = 50, most = 0
        for (length, n) in lengths.sorted(by: { $0.key < $1.key }) where n > most {
            best = length
            most = n
        }
        return best
    }

    private struct Missed {
        let day: Int, subject: String, minutes: Int
    }

    /// An absence against the lessons it covers; nil when a week it needs isn't loaded.
    private static func absenceFromLessons(_ a: AbsenceIn, _ src: Sources, until: Int) -> [Missed]? {
        var out: [Missed] = []
        let multiDay = a.startDate != a.endDate
        let absStart = toMinutes(a.startTime), absEnd = toMinutes(a.endTime)
        let first = max(a.startDate, src.from), last = min(a.endDate, src.to, until)
        if first > last { return out }
        guard var d = date(first) else { return nil }
        var steps = 0
        while num(d) <= last && steps < 420 {
            guard let week = src.weeks[iso(monday(of: d))] else { return nil }
            let day = num(d)
            let held = (week.days[day] ?? []).filter { $0.state != .cancelled }
            for s in mergedSpans(held) {
                var from = s.start, to = s.end
                if absStart > 0 && (!multiDay || day == a.startDate) { from = max(from, absStart) }
                if absEnd > 0 && (!multiDay || day == a.endDate) { to = min(to, absEnd) }
                if to <= from { continue }
                var subject = "", most = 0
                for l in held {
                    let overlap = min(to, l.end) - max(from, l.start)
                    if overlap > most {
                        most = overlap
                        subject = l.subject
                    }
                }
                out.append(Missed(day: day, subject: subject, minutes: to - from))
            }
            guard let next = days.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
            steps += 1
        }
        return out
    }

    private static func absenceFigures(_ src: Sources, days: [Day], complete: Bool) -> Absences? {
        if src.absences == nil && src.times == nil { return nil }
        let until = min(src.to, src.now.day)
        func inPeriod(_ d: Int) -> Bool { d >= src.from && d <= until }
        let absences = (src.absences ?? []).filter { $0.endDate >= src.from && $0.startDate <= until }
        var official: [Int: [TimeIn]] = [:]
        for t in src.times ?? [] where inPeriod(t.date) && t.minutes > 0 {
            official[t.absenceId, default: []].append(t)
        }
        var bySubject: [String: Tally] = [:]
        var byWeekday = [Int](repeating: 0, count: 7)
        var missedDays = Set<Int>()
        var missed = 0, excused = 0
        func add(_ day: Int, _ subject: String, _ minutes: Int, _ isExcused: Bool) {
            if minutes <= 0 { return }
            missed += minutes
            if isExcused { excused += minutes }
            let name = subject.isEmpty ? "—" : subject
            bySubject[name, default: Tally()].value += minutes
            bySubject[name, default: Tally()].lessons += 1
            if let d = date(day) { byWeekday[weekday(d)] += minutes }
            missedDays.insert(day)
        }
        let lessonLength = usualLessonMinutes(days)
        var counted = Set<Int>()
        for a in absences {
            counted.insert(a.id)
            if let own = official[a.id] {
                for t in own { add(t.date, t.subject, t.minutes, a.isExcused) }
                continue
            }
            if let pieces = absenceFromLessons(a, src, until: until) {
                for p in pieces { add(p.day, p.subject, p.minutes, a.isExcused) }
            } else if inPeriod(a.startDate) {
                add(a.startDate, a.subjectName ?? "", a.hours * lessonLength, a.isExcused)
            }
        }
        for (id, own) in official where !counted.contains(id) {
            for t in own { add(t.date, t.subject, t.minutes, t.excused) }
        }
        let possible: Int? = complete
            ? days.reduce(0) { sum, d in
                sum + mergedSpans(d.lessons.filter { $0.state != .cancelled }).reduce(0) { $0 + $1.end - $1.start }
            }
            : nil
        let officialOnly = src.absences == nil
        return Absences(
            entries: officialOnly ? official.count : absences.count,
            openEntries: officialOnly
                ? official.values.filter { $0.contains { !$0.excused } }.count
                : absences.filter { !$0.isExcused }.count,
            missedMinutes: missed,
            excusedMinutes: excused,
            possibleMinutes: possible,
            rate: possible.flatMap { $0 > 0 ? min(100, Double(missed) / Double($0) * 100) : nil },
            missedDays: missedDays.count,
            bySubject: ranked(bySubject),
            byWeekday: byWeekday
        )
    }

    private static func gradeFigures(_ src: Sources) -> Grades? {
        guard let input = src.grades else { return nil }
        var names: [String] = []
        var bySubject: [String: [GradeIn]] = [:]
        for s in input {
            if bySubject[s.subjectName] == nil { names.append(s.subjectName) }
            bySubject[s.subjectName, default: []] += s.grades
        }
        var values: [Double] = []
        var subjects: [SubjectAverage] = []
        var top: TopGrade?
        for name in names {
            let own = (bySubject[name] ?? []).filter { $0.date >= src.from && $0.date <= src.to && $0.value > 0 }
            if own.isEmpty { continue }
            subjects.append(SubjectAverage(name: name, average: own.reduce(0) { $0 + $1.value } / Double(own.count), count: own.count))
            for g in own {
                values.append(g.value)
                if top.map({ g.value > $0.value || (g.value == $0.value && g.date > $0.date) }) ?? true {
                    top = TopGrade(value: g.value, subject: name, date: g.date)
                }
            }
        }
        if values.isEmpty {
            return Grades(count: 0, average: 0, positive: 0, negative: 0, subjects: [], best: nil, top: nil)
        }
        subjects.sort {
            if $0.average != $1.average { return $0.average > $1.average }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name < $1.name
        }
        return Grades(
            count: values.count,
            average: values.reduce(0, +) / Double(values.count),
            positive: values.filter { $0 >= 6 }.count,
            negative: values.filter { $0 < 6 }.count,
            subjects: subjects,
            best: subjects.first { $0.count >= 2 } ?? subjects.first,
            top: top
        )
    }

    public static func untis(_ src: Sources) -> Untis {
        let mondays = periodWeeks(from: src.from, to: src.to, now: src.now)
        let loaded = mondays.filter { src.weeks[$0] != nil }.count
        let complete = !mondays.isEmpty && loaded == mondays.count
        let days = periodDays(src)
        let last = min(src.to, src.now.day)
        func within(_ date: Int) -> Bool { date >= src.from && date <= last }
        // The exams of the period, from the timetable: each exam lesson once.
        var exams = Set<String>()
        for week in src.weeks.values {
            for (day, lessons) in week.days where within(day) {
                for l in distinct(lessons.filter { $0.state == .exam }) { exams.insert("\(day)-\(l.start)-\(l.subject)") }
            }
        }
        return Untis(
            complete: complete,
            weeksLoaded: loaded,
            weeksTotal: mondays.count,
            school: loaded > 0 ? schoolFigures(days) : nil,
            absences: absenceFigures(src, days: days, complete: complete),
            grades: gradeFigures(src),
            exams: loaded > 0 ? exams.count : nil,
            homework: src.homework.map { Set($0.filter { within($0.dueDate) }.map(\.id)).count },
            classreg: src.classreg.map { $0.filter(within).count }
        )
    }
}
