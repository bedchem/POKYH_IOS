import Foundation

/// A teacher as WebUntis' class timetable picker names them: "Gi-Wo", "Girtler Wolfram".
public struct NamedTeacher: Equatable, Sendable {
    public var shortName: String
    public var longName: String

    public init(shortName: String, longName: String) {
        self.shortName = shortName
        self.longName = longName
    }
}

/// The own class's class teacher (`first`) and deputy (`second`).
public struct ClassTeachers: Equatable, Sendable {
    public var first: NamedTeacher?
    public var second: NamedTeacher?

    public init(first: NamedTeacher?, second: NamedTeacher?) {
        self.first = first
        self.second = second
    }
}

/// Who gets an excuse: the class teacher alone, never the deputy. WebUntis' message recipients
/// (CLASS_TEACHERS) list both without saying which is which, named "Girtler Wolfram, Wolfram (Gi-Wo)".
/// The class timetable picker (`timetable/filter?resourceType=CLASS`) says it per class:
/// `classTeacher1` is the class teacher, `classTeacher2` the deputy. The short name in brackets ties
/// the two together (backend webuntis/classTeacher.ts).
public enum ClassTeacherPick {
    /// The class teachers of the own class in the picker's answer: the class it preselects, or the
    /// only one it offers. Nil when it names no such class.
    public static func read(_ json: Any?) -> ClassTeachers? {
        guard let root = json as? [String: Any] else { return nil }
        let classes = (root["classes"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let preselected = number((root["preSelected"] as? [String: Any])?["id"])
        func idOf(_ entry: [String: Any]) -> Int? { number((entry["class"] as? [String: Any])?["id"]) }
        guard let own = classes.first(where: { preselected != nil && idOf($0) == preselected })
            ?? (classes.count == 1 ? classes[0] : nil) else { return nil }
        return ClassTeachers(first: teacher(own["classTeacher1"]), second: teacher(own["classTeacher2"]))
    }

    /// Whether a recipient's display name ("Girtler Wolfram, Wolfram (Gi-Wo)") is this teacher.
    public static func names(_ name: String, _ teacher: NamedTeacher) -> Bool {
        let n = norm(name)
        if !teacher.shortName.isEmpty, n.contains("(\(norm(teacher.shortName)))") { return true }
        guard !teacher.longName.isEmpty else { return false }
        let long = norm(teacher.longName)
        return n == long || n.hasPrefix(long + ",") || n.hasPrefix(long + " (")
    }

    /// The class teacher among the class teachers the account may write to. Without a name to go
    /// by, the one left once the deputy is out. Nil when it can't be told: then nobody gets the
    /// excuse, rather than the deputy.
    public static func pick<T>(_ candidates: [T], name: (T) -> String, teachers: ClassTeachers?) -> T? {
        let second = teachers?.second
        let named = candidates.map { (item: $0, name: name($0)) }
        let notDeputy = named.filter { entry in second.map { !names(entry.name, $0) } ?? true }
        if let first = teachers?.first {
            let hits = notDeputy.filter { names($0.name, first) }
            if hits.count == 1 { return hits[0].item }
        }
        return notDeputy.count == 1 ? notDeputy[0].item : nil
    }

    private static func number(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.intValue
    }

    private static func text(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func teacher(_ value: Any?) -> NamedTeacher? {
        guard let o = value as? [String: Any] else { return nil }
        let short = text(o["shortName"])
        var long = text(o["longName"])
        // "Girtler Wolfram (Gi-Wo)" without the short name, when there is no long name.
        if long.isEmpty {
            long = text(o["displayName"]).replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        }
        return short.isEmpty && long.isEmpty ? nil : NamedTeacher(shortName: short, longName: long)
    }
}
