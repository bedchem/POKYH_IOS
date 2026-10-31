import Foundation

/// The kinds of other timetable a student can look at.
public enum TimetableKind: String, CaseIterable, Codable, Hashable, Sendable {
    case klass = "CLASS"
    case teacher = "TEACHER"
    case room = "ROOM"

    /// WebUntis' number for it: 1 class, 2 teacher, 3 subject, 4 room, 5 student.
    public var elementType: Int {
        switch self {
        case .klass: 1
        case .teacher: 2
        case .room: 4
        }
    }
}

/// Another timetable shown instead of the own one.
public struct TimetableSource: Codable, Equatable, Hashable, Sendable {
    public var kind: TimetableKind
    public var id: Int
    public var name: String

    public init(kind: TimetableKind, id: Int, name: String) {
        self.kind = kind
        self.id = id
        self.name = name
    }

    /// For cache keys.
    public var key: String { "\(kind.rawValue)\(id)" }
}

/// A class, teacher or room whose timetable the school shows this account.
public struct TimetableResource: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var longName: String

    public init(id: Int, name: String, longName: String = "") {
        self.id = id
        self.name = name
        self.longName = longName
    }

    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || "\(name) \(longName)".range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// The entries of WebUntis' "Weitere Stundenpläne" picker. Read tolerantly: the answer nests them
/// under keys that differ by kind and version (`classes[].class`, ...), and the departments it
/// groups them by aren't timetables (backend webuntis/timetableFilter.ts).
public enum TimetableFilter {
    private static let skipped: Set<String> = [
        "departments", "department", "departmentIds", "periods", "lessons", "days", "gridEntries",
    ]

    public static func read(_ json: Any?) -> [TimetableResource] {
        var found: [Int: TimetableResource] = [:]

        func text(_ value: Any?) -> String { (value as? String)?.trimmingCharacters(in: .whitespaces) ?? "" }
        func firstNonEmpty(_ values: String...) -> String { values.first { !$0.isEmpty } ?? "" }

        func visit(_ node: Any?, depth: Int) {
            guard depth <= 6 else { return }
            if let list = node as? [Any] {
                for item in list { visit(item, depth: depth + 1) }
                return
            }
            guard let object = node as? [String: Any] else { return }
            let name = firstNonEmpty(text(object["shortName"]), text(object["displayName"]), text(object["name"]))
            if let id = object["id"] as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(), id.intValue > 0, !name.isEmpty {
                let display = text(object["displayName"])
                let long = firstNonEmpty(text(object["longName"]), display != name ? display : "")
                // The same class can come twice, and only once with its long name.
                if let known = found[id.intValue] {
                    if known.longName.isEmpty, !long.isEmpty { found[id.intValue]?.longName = long }
                } else {
                    found[id.intValue] = TimetableResource(id: id.intValue, name: name, longName: long)
                }
            }
            for (key, value) in object where !skipped.contains(key) {
                visit(value, depth: depth + 1)
            }
        }

        visit(json, depth: 0)
        let german = Locale(identifier: "de")
        return found.values.sorted {
            $0.name.compare($1.name, options: [.numeric, .caseInsensitive], locale: german) == .orderedAscending
        }
    }
}
