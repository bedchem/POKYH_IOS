import Foundation

/// Who holds which class duty.
public struct ClassService: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var personName: String
    public var duty: String

    public init(id: Int, personName: String, duty: String) {
        self.id = id
        self.personName = personName
        self.duty = duty
    }
}

public enum ClassServices {
    /// The class duties, each person-duty once. A parent with two children can get both classes,
    /// so roles that name another class than `klasseId` go, unless that would leave nothing.
    public static func read(_ root: Any?, klasseId: Int = 0) -> [ClassService] {
        let roles = UntisValue.list(UntisValue.payload(root)["classRoles"]).compactMap { $0 as? [String: Any] }

        func klasse(of role: [String: Any]) -> Int? {
            UntisValue.int((role["klasse"] as? [String: Any])?["id"]) ?? UntisValue.int(role["klasseId"])
        }
        let own = klasseId > 0 ? roles.filter { klasse(of: $0).map { $0 == klasseId } ?? true } : roles

        var seen = Set<String>()
        return (own.isEmpty ? roles : own).compactMap { role in
            let duty = role["duty"] as? [String: Any]
            let key = "\(UntisValue.int(role["personId"]) ?? -1)-\(UntisValue.int(duty?["id"]) ?? -1)"
            guard seen.insert(key).inserted else { return nil }
            let name = [role["foreName"], role["longName"]]
                .compactMap(UntisValue.string)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return ClassService(id: UntisValue.int(role["id"]) ?? 0, personName: name, duty: UntisValue.string(duty?["label"]) ?? "")
        }
    }
}

/// A homework with the subject of the lesson it belongs to.
public struct HomeworkItem: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var subject: String
    /// YYYYMMDD
    public var dueDate: Int
    public var text: String
    public var completed: Bool

    public init(id: Int, subject: String, dueDate: Int, text: String, completed: Bool = false) {
        self.id = id
        self.subject = subject
        self.dueDate = dueDate
        self.text = text
        self.completed = completed
    }
}

public enum HomeworkList {
    /// `/api/homeworks/lessons` asks by date only, so a parent with two children gets both.
    /// `childId` keeps the one shown, but only where the answer's `records` actually name that
    /// child or class: other servers fill `elementIds` differently, and showing too much beats
    /// showing a student's homework as gone.
    public static func read(_ root: Any?, childId: Int? = nil, klasseId: Int = 0) -> [HomeworkItem] {
        let data = UntisValue.payload(root)
        // "Mathematik (4BFS_M)" → "Mathematik", as on the web.
        var subjects: [Int: String] = [:]
        for lesson in UntisValue.list(data["lessons"]) {
            guard let lesson = lesson as? [String: Any], let id = UntisValue.int(lesson["id"]) else { continue }
            let name = UntisValue.string(lesson["subject"]) ?? ""
            subjects[id] = name.components(separatedBy: " (").first ?? name
        }

        let records = UntisValue.list(data["records"]).compactMap { $0 as? [String: Any] }
        var owners: [Int: [Int]] = [:]
        for record in records {
            guard let id = UntisValue.int(record["homeworkId"]) else { continue }
            owners[id, default: []] += UntisValue.list(record["elementIds"]).compactMap(UntisValue.int)
        }
        let wanted = Set([childId, klasseId > 0 ? klasseId : nil].compactMap { $0 })
        let filters = childId != nil && owners.values.contains { !wanted.isDisjoint(with: $0) }

        var seen = Set<Int>()
        let rows = UntisValue.list(data["homeworks"]).compactMap { $0 as? [String: Any] } + records
        return rows.compactMap { row -> HomeworkItem? in
            guard let id = UntisValue.int(row["id"]), seen.insert(id).inserted else { return nil }
            if filters, let elements = owners[id], !elements.isEmpty, wanted.isDisjoint(with: elements) { return nil }
            return HomeworkItem(
                id: id,
                subject: UntisValue.int(row["lessonId"]).flatMap { subjects[$0] } ?? "",
                dueDate: UntisValue.int(row["dueDate"]) ?? 0,
                text: UntisText.plain(UntisValue.string(row["text"])),
                completed: UntisValue.bool(row["completed"]) ?? false
            )
        }
    }

    /// Open homework, soonest first (as on the web).
    public static func open(_ items: [HomeworkItem]) -> [HomeworkItem] {
        items.filter { !$0.completed && $0.dueDate > 0 }.sorted { $0.dueDate < $1.dueDate }
    }

    public static func due(_ items: [HomeworkItem], from: Int, before: Int) -> [HomeworkItem] {
        items.filter { $0.dueDate >= from && $0.dueDate < before }
    }
}

/// What the class register's list needs of an entry. `createDate` is YYYYMMDD.
public protocol ClassregRecord {
    var createDate: Int { get }
    var subjectName: String { get }
    var categoryName: String { get }
}

public enum ClassregRange: CaseIterable, Hashable, Sendable {
    case all, month, months3
}

public enum ClassregSort: CaseIterable, Hashable, Sendable {
    case dateDesc, dateAsc, subject, category

    /// Named groups rather than months.
    public var groupsByName: Bool { self == .subject || self == .category }
}

public struct ClassregGroup<Item>: Identifiable {
    public let key: String
    public let items: [Item]
    public var id: String { key }
}

/// The class register's filters: a time range, then sorted and grouped by month, subject or
/// category. Month keys are YYYYMM, the others the name itself.
public enum ClassregGrouping {
    public static func dayNum(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    public static func cutoff(_ range: ClassregRange, today: Date = Date(), calendar: Calendar = .current) -> Int {
        let months: Int
        switch range {
        case .all: return 0
        case .month: months = 1
        case .months3: months = 3
        }
        return dayNum(calendar.date(byAdding: .month, value: -months, to: today) ?? today, calendar: calendar)
    }

    public static func groups<Item: ClassregRecord>(_ items: [Item], range: ClassregRange, sort: ClassregSort, noCategory: String,
                                                    today: Date = Date(), calendar: Calendar = .current) -> [ClassregGroup<Item>] {
        let limit = cutoff(range, today: today, calendar: calendar)
        let list = items.filter { $0.createDate >= limit }
            .sorted { sort == .dateAsc ? $0.createDate < $1.createDate : $0.createDate > $1.createDate }

        var order: [String] = []
        var byKey: [String: [Item]] = [:]
        for item in list {
            let key: String = switch sort {
            case .subject: item.subjectName.trimmingCharacters(in: .whitespaces).isEmpty ? "-" : item.subjectName
            case .category: item.categoryName.trimmingCharacters(in: .whitespaces).isEmpty ? noCategory : item.categoryName
            default: String(item.createDate / 100)
            }
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(item)
        }
        if sort.groupsByName { order.sort { $0.lowercased() < $1.lowercased() } }
        return order.map { ClassregGroup(key: $0, items: byKey[$0] ?? []) }
    }

    /// The newest few of the last three months, for the class page.
    public static func recent<Item: ClassregRecord>(_ items: [Item], limit: Int = 5, today: Date = Date(),
                                                    calendar: Calendar = .current) -> [Item] {
        let since = cutoff(.months3, today: today, calendar: calendar)
        return Array(items.filter { $0.createDate >= since }.sorted { $0.createDate > $1.createDate }.prefix(limit))
    }
}
