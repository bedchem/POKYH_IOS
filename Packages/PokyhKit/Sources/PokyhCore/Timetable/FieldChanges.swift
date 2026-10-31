import Foundation

public enum FieldMark: Equatable, Sendable {
    case plain, added, removed
}

/// One name of a comma-joined field (a teacher, a room) and what happened to it.
public struct FieldPart: Equatable, Hashable, Sendable {
    public var text: String
    public var mark: FieldMark

    public init(_ text: String, _ mark: FieldMark = .plain) {
        self.text = text
        self.mark = mark
    }
}

/// Which of a lesson's fields differ from the plan, name by name.
public enum FieldChanges {
    /// An original only counts when it's there and really differs: WebUntis echoes the current
    /// value back on plenty of lessons that didn't change.
    public static func changed(current: String, original: String?, added: [String]) -> Bool {
        if !added.isEmpty { return true }
        let before = (original ?? "").trimmingCharacters(in: .whitespaces)
        return !before.isEmpty && before != current.trimmingCharacters(in: .whitespaces)
    }

    public static func split(_ joined: String?) -> [String] {
        (joined ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The parts of a field with the changed ones first, so what's worth reading survives a
    /// narrow grid cell. A dense cell drops the unchanged ones altogether.
    public static func parts(current: String, added: [String], original: String?, dense: Bool = false) -> [FieldPart] {
        let names = split(current)
        let before = split(original)
        let flagged = Set(added.map { $0.trimmingCharacters(in: .whitespaces) })
        var all = names.map { name in
            FieldPart(name, flagged.contains(name) || (!before.isEmpty && !before.contains(name)) ? .added : .plain)
        }
        all += before.filter { !names.contains($0) }.map { FieldPart($0, .removed) }
        let marked = all.filter { $0.mark != .plain }
        if dense && !marked.isEmpty { return marked }
        return marked + all.filter { $0.mark == .plain }
    }

    /// The same for the detail sheet: long names where WebUntis has them, and whatever the
    /// lesson's detail adds about who or what came and went.
    public static func detailParts(current: String, currentLong: String? = nil, added: [String], original: String?,
                                   originalLong: String? = nil, history: [LessonDetail.Element] = []) -> [FieldPart] {
        var long = longNames(short: current, long: currentLong)
        long.merge(longNames(short: original, long: originalLong)) { first, _ in first }
        for element in history where !element.longName.isEmpty {
            for name in [element.name, element.shortName] where !name.isEmpty && long[name] == nil {
                long[name] = element.longName
            }
        }

        var result = parts(current: current, added: added, original: original)
        for element in history {
            let mark = element.mark
            let index = result.firstIndex { $0.text == element.name || $0.text == element.shortName }
            if let index {
                // What the plain field missed; a mark the timetable already set stays.
                if result[index].mark == .plain, mark != .plain { result[index].mark = mark }
            } else if mark != .plain, !element.name.isEmpty {
                result.append(FieldPart(element.name, mark))
            }
        }
        let marked = result.filter { $0.mark != .plain }
        return (marked + result.filter { $0.mark == .plain }).map { FieldPart(long[$0.text] ?? $0.text, $0.mark) }
    }

    /// Short to long, by position. Only when both lists line up: a long name can hold a comma.
    private static func longNames(short: String?, long: String?) -> [String: String] {
        let shorts = split(short), longs = split(long)
        guard shorts.count == longs.count else { return [:] }
        return Dictionary(zip(shorts, longs)) { first, _ in first }
    }
}
