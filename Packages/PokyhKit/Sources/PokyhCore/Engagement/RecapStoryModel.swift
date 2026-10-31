import Foundation

/// The pages of a recap story: which pages there are, what each says (keys of the recap texts with
/// their values) and how the mascot reacts. Every figure has its own tiers, from the crown for not
/// one hour missed to covering its eyes above 25 %. A page without data is left out.
public enum RecapStoryModel {
    public enum Mood: String, CaseIterable, Sendable {
        case wave, legend, great, good, ok, meh, worried, alarm, proud, love, focused, sleepy
        case party, cool, curious, peek, angry, angel, zap, night, early, cheer
    }

    public enum Theme: String, CaseIterable, Sendable {
        case night, ocean, sunset, forest, dusk, candy, gold, mint, grape, teal, ember, alarm, brand, sky, rose
    }

    public enum Tier: String, CaseIterable, Sendable {
        case legend = "Legend", great = "Great", good = "Good", ok = "Ok", meh = "Meh", worried = "Worried", alarm = "Alarm"
    }

    public enum Layout: Sendable { case intro, number, list, summary }
    public enum Place: Sendable { case bottom, left, right, corner }

    public struct Text: Equatable, Sendable {
        public var key: String
        public var vars: [String: String]
        public init(_ key: String, _ vars: [String: String] = [:]) {
            self.key = key
            self.vars = vars
        }
    }

    public enum Value: Equatable, Sendable {
        case count(Double, decimals: Int = 0, prefix: String = "", suffix: String = "", from: Double = 0)
        case words(String)
    }

    public struct ListRow: Equatable, Sendable {
        public var label: String
        public var labelKey: String?
        public var value: Double
        public var display: String
    }

    public struct Slide: Equatable, Identifiable, Sendable {
        public var id: String
        public var theme: Theme
        public var mood: Mood
        public var layout: Layout
        public var place: Place
        public var lead: Text?
        public var value: Value?
        public var unit: Text?
        public var body: [Text] = []
        public var quip: Text?
        public var list: [ListRow] = []
        /// The absence rate against the 25 % limit.
        public var meter: (value: Double, limit: Double)?

        public static func == (a: Slide, b: Slide) -> Bool {
            a.id == b.id && a.theme == b.theme && a.mood == b.mood && a.value == b.value && a.body == b.body
                && a.quip == b.quip && a.list == b.list && a.meter?.value == b.meter?.value
        }
    }

    public struct SummaryItem: Equatable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var value: String
    }

    public struct Input: Sendable {
        public var title: String
        public var firstName: String
        public var periodFrom: String
        public var periodTo: String
        public var sections: [String]
        public var untis: RecapFigures.Untis?
        public var pokyh: RecapPokyh?

        public init(title: String, firstName: String, periodFrom: String, periodTo: String, sections: [String],
                    untis: RecapFigures.Untis?, pokyh: RecapPokyh?) {
            self.title = title; self.firstName = firstName; self.periodFrom = periodFrom; self.periodTo = periodTo
            self.sections = sections; self.untis = untis; self.pokyh = pokyh
        }

        func wants(_ section: String) -> Bool { sections.contains(section) }
    }

    public static let absenceLimit = 25.0

    public static func absenceTier(rate: Double, missedMinutes: Int) -> Tier {
        if missedMinutes <= 0 { return .legend }
        if rate < 2 { return .great }
        if rate < 5 { return .good }
        if rate < 10 { return .ok }
        if rate < 15 { return .meh }
        return rate < absenceLimit ? .worried : .alarm
    }

    private static func gradeTier(_ average: Double) -> String {
        if average >= 9 { return "legend" }
        if average >= 8 { return "great" }
        if average >= 7 { return "good" }
        return average >= 6 ? "ok" : "low"
    }

    private static func mood(_ t: Tier) -> Mood {
        switch t {
        case .legend: .legend
        case .great: .great
        case .good: .good
        case .ok: .ok
        case .meh: .meh
        case .worried: .worried
        case .alarm: .alarm
        }
    }

    private static func theme(_ t: Tier) -> Theme {
        switch t {
        case .legend: .gold
        case .great: .mint
        case .good: .teal
        case .ok: .sky
        case .meh: .dusk
        case .worried: .ember
        case .alarm: .alarm
        }
    }

    private static func round(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }
    private static func hours(_ minutes: Int) -> Int { round(Double(minutes) / 60) }

    private static func maxIndex(_ values: [Int]) -> Int {
        var best = 0
        for i in values.indices where values[i] > values[best] { best = i }
        return best
    }

    private static func schoolSlides(_ u: RecapFigures.Untis, withAbsences: Bool, _ f: any RecapFormat) -> [Slide] {
        guard let s = u.school, s.lessons > 0 else { return [] }
        var out: [Slide] = []
        let missed = withAbsences ? (u.absences?.missedMinutes ?? 0) : 0
        let attended = max(0, s.minutes - missed)
        var body = [Text("hoursBody", ["days": f.num(Double(s.days)), "lessons": f.num(Double(s.lessons))])]
        if !u.complete { body.append(Text("partial", ["n": String(u.weeksTotal - u.weeksLoaded)])) }
        out.append(Slide(
            id: "hours", theme: .ocean, mood: .proud, layout: .number, place: .bottom,
            lead: Text("hoursLead"), value: .count(Double(hours(attended))), unit: Text("hoursUnit"), body: body,
            quip: Text("hoursQuip", ["days": f.num(Double(attended) / 60 / 24, digits: 1)])
        ))
        if let top = s.subjects.first {
            out.append(Slide(
                id: "subject", theme: .sunset, mood: .love, layout: .list, place: .corner,
                lead: Text("subjectLead"), value: .words(top.name),
                unit: Text("subjectUnit", ["hours": f.num(Double(hours(top.value))), "lessons": f.num(Double(top.lessons))]),
                quip: Text("subjectQuip"),
                list: s.subjects.map { ListRow(label: $0.name, value: Double($0.value), display: "\(f.num(Double(hours($0.value)))) h") }
            ))
        }
        if let teacher = s.teachers.first {
            let room = s.rooms.first
            out.append(Slide(
                id: "teacher", theme: .forest, mood: .wave, layout: .number, place: .right,
                lead: Text("teacherLead"), value: .words(teacher.name),
                unit: Text("teacherUnit", ["n": f.num(Double(teacher.lessons))]),
                body: room.map { [Text("teacherRoom", ["room": $0.name, "n": f.num(Double($0.lessons))])] } ?? [],
                quip: Text("teacherQuip")
            ))
        }
        if let day = s.longestDay {
            var body: [Text] = []
            if let early = s.earliest, let late = s.latest {
                body = [Text("longestBody", ["early": f.time(early.minutes), "late": f.time(late.minutes)])]
            }
            out.append(Slide(
                id: "longest", theme: .dusk, mood: .sleepy, layout: .number, place: .left,
                lead: Text("longestLead"), value: .words(f.date(day.date)),
                unit: Text("longestUnit", ["start": f.time(day.start), "end": f.time(day.end)]),
                body: body, quip: Text("longestQuip")
            ))
        }
        let subs: [Text] = s.substitutions == 1 ? [Text("cancelledSubsOne")]
            : s.substitutions > 1 ? [Text("cancelledSubs", ["n": f.num(Double(s.substitutions))])] : []
        out.append(Slide(
            id: "cancelled",
            theme: s.cancelled == 0 ? .teal : .candy,
            mood: s.cancelled == 0 ? .cool : s.cancelled >= 30 ? .party : .cheer,
            layout: .number, place: .bottom,
            lead: Text("cancelledLead"), value: .count(Double(s.cancelled)),
            unit: Text(s.cancelled == 1 ? "cancelledUnitOne" : "cancelledUnit"),
            body: s.cancelled == 0 ? [Text("cancelledNone")] + subs : subs,
            quip: Text(s.cancelled == 0 ? "cancelledQuipNone" : s.cancelled >= 30 ? "cancelledQuipMany" : "cancelledQuipSome")
        ))
        return out
    }

    private static func absenceSlides(_ u: RecapFigures.Untis, _ f: any RecapFormat) -> [Slide] {
        guard let a = u.absences else { return [] }
        var out: [Slide] = []
        let missedHours = Double(a.missedMinutes) / 60
        if let rate = a.rate, let possible = a.possibleMinutes, possible > 0 {
            let tier = absenceTier(rate: rate, missedMinutes: a.missedMinutes)
            let left = max(0, Double(possible) * absenceLimit / 100 - Double(a.missedMinutes)) / 60
            out.append(Slide(
                id: "rate", theme: theme(tier), mood: mood(tier), layout: .number,
                place: tier == .alarm || tier == .worried ? .right : .bottom,
                lead: Text("rateLead"),
                value: .count(rate, decimals: rate == 0 ? 0 : 1, suffix: " %"),
                unit: Text("rateUnit"),
                body: [Text("rateBody\(tier.rawValue)", ["hours": f.num(Double(round(missedHours))), "left": f.num(left.rounded(.down))])],
                quip: Text("quip\(tier.rawValue)"),
                meter: (rate, absenceLimit)
            ))
        } else {
            let tier: Tier = a.missedMinutes == 0 ? .legend : .ok
            out.append(Slide(
                id: "missed", theme: theme(tier), mood: mood(tier), layout: .number, place: .bottom,
                lead: Text("missedLead"), value: .count(Double(round(missedHours))), unit: Text("missedUnit"),
                body: a.missedMinutes == 0 ? [Text("missedNone")] : [],
                quip: Text("quip\(tier.rawValue)")
            ))
        }
        if a.missedMinutes <= 0 { return out }
        let excusedShare = round(Double(a.excusedMinutes) / Double(a.missedMinutes) * 100)
        let open = a.openEntries == 0 ? Text("detailsAllDone")
            : a.openEntries == 1 ? Text("detailsOpenOne")
            : Text("detailsOpen", ["n": f.num(Double(a.openEntries))])
        if a.entries > 0 {
            out.append(Slide(
                id: "details", theme: a.openEntries == 0 ? .mint : .ember, mood: a.openEntries == 0 ? .good : .curious,
                layout: .number, place: .left,
                lead: Text("detailsLead"), value: .count(Double(a.entries)),
                unit: a.entries == 1 ? Text("detailsUnitOne") : Text("detailsUnit", ["days": f.num(Double(a.missedDays))]),
                body: [Text("detailsExcused", ["n": String(excusedShare)]), open],
                quip: Text(a.openEntries == 0 ? "detailsQuipDone" : "detailsQuipOpen")
            ))
        }
        if let subject = a.bySubject.first {
            let day = maxIndex(a.byWeekday)
            out.append(Slide(
                id: "pattern", theme: .rose, mood: .peek, layout: .number, place: .right,
                lead: Text("patternLead"), value: .words(subject.name),
                unit: Text("patternUnit", ["hours": f.num(Double(max(1, round(Double(subject.value) / 60))))]),
                body: a.byWeekday[day] > 0 ? [Text("patternBody", ["weekday": f.weekday(day)])] : [],
                quip: Text(day == 0 ? "patternQuipMonday" : day == 4 ? "patternQuipFriday" : "patternQuip")
            ))
        }
        return out
    }

    private static func gradeSlides(_ u: RecapFigures.Untis, _ f: any RecapFormat) -> [Slide] {
        guard let g = u.grades, g.count > 0 else { return [] }
        let tier = gradeTier(g.average)
        let mood: Mood = switch tier {
        case "legend": .legend
        case "great": .great
        case "good": .good
        case "ok": .ok
        default: .worried
        }
        let quip = "gradesQuip" + tier.prefix(1).uppercased() + tier.dropFirst()
        var out = [Slide(
            id: "grades", theme: tier == "low" ? .ember : .grape, mood: mood, layout: .number, place: .bottom,
            lead: Text("gradesLead"), value: .count(Double(g.count)),
            unit: Text(g.count == 1 ? "gradesUnitOne" : "gradesUnit"),
            body: [
                Text("gradesBody", ["avg": f.num(g.average, digits: 2)]),
                g.negative > 0
                    ? Text("gradesMixed", ["pos": f.num(Double(g.positive)), "neg": f.num(Double(g.negative))])
                    : Text("gradesAllPositive"),
            ],
            quip: Text(quip)
        )]
        if let best = g.best {
            let avg = f.num(best.average, digits: 2)
            var body: [Text] = []
            if let top = g.top {
                let digits = top.value.truncatingRemainder(dividingBy: 1) != 0 ? 2 : 0
                body = [Text("bestTop", ["value": f.num(top.value, digits: digits), "subject": top.subject, "date": f.date(top.date)])]
            }
            out.append(Slide(
                id: "best", theme: .gold, mood: gradeTier(best.average) == "legend" ? .party : .proud, layout: .list, place: .corner,
                lead: Text("bestLead"), value: .words(best.name),
                unit: best.count == 1 ? Text("bestUnitOne", ["avg": avg]) : Text("bestUnit", ["avg": avg, "n": String(best.count)]),
                body: body,
                quip: Text("bestQuip"),
                list: g.subjects.prefix(4).map { ListRow(label: $0.name, value: $0.average, display: f.num($0.average, digits: 2)) }
            ))
        }
        return out
    }

    private static func examSlides(_ u: RecapFigures.Untis, _ f: any RecapFormat) -> [Slide] {
        let exams = u.exams ?? 0, homework = u.homework ?? 0
        if exams == 0 && homework == 0 { return [] }
        let examFirst = exams > 0
        return [Slide(
            id: "exams", theme: .teal, mood: .focused, layout: .number, place: .right,
            lead: Text("examsLead"), value: .count(Double(examFirst ? exams : homework)),
            unit: Text(examFirst ? (exams == 1 ? "examsUnitOne" : "examsUnit") : "homeworkUnit"),
            body: examFirst && homework > 0 ? [Text("examsHomework", ["n": f.num(Double(homework))])] : [],
            quip: Text("examsQuip")
        )]
    }

    private static func classregSlides(_ u: RecapFigures.Untis) -> [Slide] {
        guard let n = u.classreg else { return [] }
        let level = n == 0 ? "None" : n <= 3 ? "Few" : "Many"
        return [Slide(
            id: "classreg",
            theme: level == "None" ? .sky : level == "Few" ? .dusk : .ember,
            mood: level == "None" ? .angel : level == "Few" ? .meh : .angry,
            layout: .number, place: .bottom,
            lead: Text("classregLead"), value: .count(Double(n)),
            body: [Text("classreg\(level)")],
            quip: Text("classregQuip\(level)")
        )]
    }

    private static func pokyhSlides(_ p: RecapPokyh, _ f: any RecapFormat, schoolDays: Int) -> [Slide] {
        let c = p.created
        let madeCount = c.map { $0.todosDone + $0.reminders + $0.comments + $0.ratings } ?? 0
        guard let t = p.totals, t.activeDays != 0 else {
            if madeCount > 0 || p.favouriteDish != nil || p.covered == nil { return [] }
            return [Slide(
                id: "pokyh-none", theme: .night, mood: .curious, layout: .number, place: .right,
                lead: Text("pokyhNoneLead"), unit: Text("pokyhNoneUnit"), body: [Text("pokyhNoneBody")], quip: Text("pokyhNoneQuip")
            )]
        }
        var out: [Slide] = []
        let zap = schoolDays > 0 && Double(t.activeDays) >= Double(schoolDays) * 0.6
        out.append(Slide(
            id: "days", theme: .brand, mood: zap ? .zap : .wave, layout: .number, place: .bottom,
            lead: Text("daysLead"), value: .count(Double(t.activeDays)),
            unit: Text(t.activeDays == 1 ? "daysUnitOne" : "daysUnit"),
            body: [t.longestStreak == 1 ? Text("daysBodyOne") : Text("daysBody", ["n": f.num(Double(t.longestStreak))])],
            quip: Text(zap ? "daysQuipZap" : "daysQuip")
        ))
        let weekdays = p.weekdays
        let day = weekdays.isEmpty ? 0 : maxIndex(weekdays)
        if p.usageConsent, t.activeSeconds >= 60, let hoursOfDay = p.hours, !hoursOfDay.isEmpty {
            let hour = maxIndex(hoursOfDay)
            let night = hour >= 21 || hour < 5
            let early = (5...7).contains(hour)
            let asHours = t.activeSeconds >= 3600
            out.append(Slide(
                id: "time", theme: night ? .night : early ? .sky : .sunset, mood: night ? .night : early ? .early : .cool,
                layout: .number, place: .left,
                lead: Text("timeLead"),
                value: .count(Double(round(Double(t.activeSeconds) / (asHours ? 3600 : 60)))),
                unit: Text(asHours ? "timeUnitHours" : "timeUnitMinutes"),
                body: [Text("timeBody", ["hour": String(hour), "weekday": f.weekday(day)])],
                quip: Text(night ? "timeQuipNight" : early ? "timeQuipEarly" : "timeQuipDay")
            ))
        } else if weekdays.indices.contains(day), weekdays[day] > 0 {
            out.append(Slide(
                id: "when", theme: .sky, mood: .cool, layout: .number, place: .left,
                lead: Text("whenLead"), value: .words(f.weekday(day)),
                unit: Text("whenUnit", ["n": f.num(Double(weekdays[day]))]), quip: Text("whenQuip")
            ))
        }
        let made: [(String, Int)] = c.map { [("madeTodos", $0.todosDone), ("madeReminders", $0.reminders), ("madeComments", $0.comments), ("madeRatings", $0.ratings)] } ?? []
        let rows = made.filter { $0.1 > 0 }.map { ListRow(label: "", labelKey: $0.0, value: Double($0.1), display: f.num(Double($0.1))) }
        if !rows.isEmpty || p.favouriteDish != nil {
            out.append(Slide(
                id: "made", theme: .mint, mood: p.favouriteDish != nil ? .love : .cheer, layout: .list, place: .corner,
                lead: Text("madeLead"),
                body: p.favouriteDish.map { [Text("madeDish", ["dish": f.dish($0.name)])] } ?? [],
                quip: Text("madeQuip"),
                list: rows
            ))
        }
        if let rank = p.rank, rank.topPercent <= 50 {
            let legend = rank.topPercent <= 5
            out.append(Slide(
                id: "rank", theme: .gold, mood: legend ? .legend : rank.topPercent <= 20 ? .party : .great, layout: .number, place: .bottom,
                lead: Text("rankLead"), value: .count(Double(rank.topPercent), prefix: "Top ", suffix: " %", from: 100),
                unit: Text("rankUnit"), quip: Text(legend ? "rankQuipLegend" : "rankQuip")
            ))
        }
        return out
    }

    /// The first page. It's there at once, before any figure has been loaded.
    public static func intro(title: String, firstName: String, periodFrom: String, periodTo: String, _ f: any RecapFormat) -> Slide {
        Slide(
            id: "intro", theme: .night, mood: .wave, layout: .intro, place: .bottom,
            lead: firstName.isEmpty ? Text("introHelloAnon") : Text("introHello", ["name": firstName]),
            value: .words(title),
            body: [Text("introLead", ["from": f.day(periodFrom), "to": f.day(periodTo)])],
            quip: Text("introQuip")
        )
    }

    /// The story's pages, in order: hello, the chosen parts, the summary.
    public static func build(_ input: Input, _ f: any RecapFormat) -> [Slide] {
        var slides = [intro(title: input.title, firstName: input.firstName, periodFrom: input.periodFrom, periodTo: input.periodTo, f)]
        if let u = input.untis {
            if input.wants("school") { slides += schoolSlides(u, withAbsences: input.wants("absences"), f) }
            if input.wants("absences") { slides += absenceSlides(u, f) }
            if input.wants("grades") { slides += gradeSlides(u, f) }
            if input.wants("exams") { slides += examSlides(u, f) }
            if input.wants("classreg") { slides += classregSlides(u) }
        }
        if let p = input.pokyh, input.wants("pokyh") {
            slides += pokyhSlides(p, f, schoolDays: input.untis?.school?.days ?? 0)
        }
        slides.append(Slide(id: "summary", theme: .night, mood: .party, layout: .summary, place: .corner,
                            value: .words(input.title), quip: Text("summaryQuip")))
        return slides
    }

    /// Every figure the summary can show, the most telling first.
    public static func summaryItems(_ input: Input, _ f: any RecapFormat) -> [SummaryItem] {
        var out: [SummaryItem] = []
        func add(_ id: String, _ label: String, _ value: String) { out.append(SummaryItem(id: id, label: label, value: value)) }
        let u = input.untis, p = input.pokyh
        let school = u?.school
        let wantsSchool = input.wants("school"), wantsAbsences = input.wants("absences")
        let wantsGrades = input.wants("grades"), wantsExams = input.wants("exams"), wantsPokyh = input.wants("pokyh")
        if let school, wantsSchool, school.lessons > 0 {
            add("hours", "cardHours", f.num(Double(hours(max(0, school.minutes - (wantsAbsences ? u?.absences?.missedMinutes ?? 0 : 0))))))
        }
        if let r = u?.absences?.rate, wantsAbsences { add("rate", "cardRate", "\(f.num(r, digits: r == 0 ? 0 : 1)) %") }
        if let g = u?.grades, g.count > 0, wantsGrades { add("average", "cardAverage", f.num(g.average, digits: 2)) }
        if let t = p?.totals, t.activeDays > 0, wantsPokyh { add("days", "cardDays", f.num(Double(t.activeDays))) }
        if let r = p?.rank, r.topPercent <= 50, wantsPokyh { add("rank", "cardRank", "Top \(r.topPercent) %") }
        if let s = school?.subjects.first, wantsSchool { add("subject", "cardSubject", s.name) }
        if let b = u?.grades?.best, wantsGrades { add("best", "cardBest", b.name) }
        if let e = u?.exams, e > 0, wantsExams { add("exams", "cardExams", f.num(Double(e))) }
        if let h = u?.homework, h > 0, wantsExams { add("homework", "cardHomework", f.num(Double(h))) }
        if let a = u?.absences, wantsAbsences { add("missed", "cardMissed", f.num(Double(round(Double(a.missedMinutes) / 60)))) }
        if let school, wantsSchool, school.lessons > 0 { add("cancelled", "cardCancelled", f.num(Double(school.cancelled))) }
        if let t = school?.teachers.first, wantsSchool { add("teacher", "cardTeacher", t.name) }
        if let t = p?.totals, t.longestStreak > 1, wantsPokyh { add("streak", "cardStreak", f.num(Double(t.longestStreak))) }
        if let c = p?.created, c.todosDone > 0, wantsPokyh { add("todos", "cardTodos", f.num(Double(c.todosDone))) }
        if let n = u?.classreg, input.wants("classreg") { add("classreg", "cardClassreg", f.num(Double(n))) }
        return out
    }

    /// WebUntis gives "Pfeifer Emanuel", surname first, so the word a part of the login name starts
    /// with is the first name. Guardians are greeted without one.
    public static func firstName(personName: String?, username: String, isParent: Bool, hasUntis: Bool) -> String {
        if isParent { return "" }
        if !hasUntis { return username }
        let words = (personName ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        let parts = username.lowercased()
            .split(whereSeparator: { "-._ ".contains($0) })
            .map(String.init)
            .filter { $0.count >= 2 }
        for part in parts.reversed() {
            if let word = words.first(where: { $0.lowercased().hasPrefix(part) }) { return word }
        }
        return ""
    }
}

/// Figures as the reader's language writes them.
public protocol RecapFormat: Sendable {
    /// YYYYMMDD to "Dienstag, 14. März"
    func date(_ n: Int) -> String
    /// YYYY-MM-DD to "1. September 2025"
    func day(_ iso: String) -> String
    /// Monday = 0 to "Montag"
    func weekday(_ i: Int) -> String
    /// Minutes of the day to "07:45"
    func time(_ minutes: Int) -> String
    func num(_ n: Double, digits: Int) -> String
    func dish(_ name: RecapPokyh.DishName) -> String
}

extension RecapFormat {
    public func num(_ n: Double) -> String { num(n, digits: 0) }
}

public struct RecapFormatter: RecapFormat {
    let strings: Strings

    public init(strings: Strings) {
        self.strings = strings
    }

    public func date(_ n: Int) -> String {
        guard let d = RecapFigures.date(n) else { return "" }
        return "\(strings.common.weekdays[RecapFigures.weekday(d)]), \(strings.common.dayMonth(n % 100, n / 100 % 100))"
    }

    public func day(_ iso: String) -> String {
        let n = RecapFigures.numOfISO(iso)
        guard RecapFigures.date(n) != nil else { return iso }
        return strings.common.dateLong(n % 100, n / 100 % 100, n / 10000)
    }

    public func weekday(_ i: Int) -> String {
        strings.common.weekdays[min(max(i, 0), 6)]
    }

    public func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    public func num(_ n: Double, digits: Int) -> String {
        n.formatted(.number.locale(strings.lang.locale).precision(.fractionLength(digits)))
    }

    public func dish(_ name: RecapPokyh.DishName) -> String {
        switch strings.lang {
        case .it: name.it.isEmpty ? name.de : name.it
        case .en: name.en.isEmpty ? name.de : name.en
        case .de: name.de
        }
    }
}

/// The card to keep and share: what can be picked, and which ink reads on which color.
public enum RecapPoster {
    public static let slots = 5
    public static let colors: [UInt32] = [0xFF5D3A, 0x2F6BFF, 0x0F9D63, 0xFFBF1F, 0x8B3DFF, 0xFF4F9A, 0x1B1640]

    public enum Pose: String, CaseIterable, Sendable {
        case cool, legend, wave, proud, party, love, cheer, zap, sleepy, angel

        public var textKey: String { "pose" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        public var mood: RecapStoryModel.Mood {
            switch self {
            case .cool: .cool
            case .legend: .legend
            case .wave: .wave
            case .proud: .proud
            case .party: .party
            case .love: .love
            case .cheer: .cheer
            case .zap: .zap
            case .sleepy: .sleepy
            case .angel: .angel
            }
        }

        public func stepped(_ by: Int) -> Pose {
            let all = Pose.allCases
            let i = all.firstIndex(of: self) ?? 0
            return all[(i + by + all.count) % all.count]
        }
    }

    public struct Inks: Equatable, Sendable {
        public var ink: RGB
        public var soft: RGB
        public var box: RGB
    }

    /// Dark text on the light colors, and rows a step darker than the card.
    public static func inks(_ color: UInt32) -> Inks {
        let r = Int((color >> 16) & 255), g = Int((color >> 8) & 255), b = Int(color & 255)
        let light = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b) > 150
        func shade(_ v: Int) -> Int { Int(Double(v) * (light ? 0.86 : 0.78)) }
        func mix(_ v: Int, _ to: Int) -> Int { Int(Double(v) + Double(to - v) * 0.7) }
        func rgb(_ r: Int, _ g: Int, _ b: Int) -> RGB { RGB(hex: UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)) }
        return Inks(
            ink: light ? RGB(hex: 0x1A1405) : .white,
            soft: light ? rgb(mix(r, 26), mix(g, 20), mix(b, 5)) : rgb(mix(r, 255), mix(g, 255), mix(b, 255)),
            box: rgb(shade(r), shade(g), shade(b))
        )
    }

    /// A figure on or off the card; a full card takes no more.
    public static func toggled(_ picked: [String], _ id: String) -> [String] {
        if picked.contains(id) { return picked.filter { $0 != id } }
        return picked.count >= slots ? picked : picked + [id]
    }
}
