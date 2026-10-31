import Foundation

/// One of a period's texts. `type` is WebUntis' own: LESSON_INFO, LESSON_TEXT, SUBSTITUTION, ...
public struct PeriodText: Codable, Equatable, Hashable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

/// What a timetable grid entry says beyond subject, teacher and room.
public struct PeriodExtras: Equatable, Sendable {
    public var addedTeachers: [String] = []
    public var addedSubjects: [String] = []
    public var addedRooms: [String] = []
    public var icons: [String] = []
    public var lessonInfo: String?
    public var lessonText: String?
    public var substitutionText: String?
    public var texts: [PeriodText] = []

    public init() {}

    /// WebUntis flags a changed field on the current value ("status":"ADDED") and usually leaves
    /// `removed` empty, so both have to be read or a room added to a lesson looks regular.
    /// `texts` is the structured form of the flat text fields; some servers only send one of them.
    public static func read(_ gridEntry: Any?) -> PeriodExtras {
        guard let entry = gridEntry as? [String: Any] else { return PeriodExtras() }

        func added(_ key: String) -> [String] {
            UntisValue.list(entry[key]).compactMap { position in
                guard let current = (position as? [String: Any])?["current"] as? [String: Any],
                      let status = UntisValue.string(current["status"]), status != "REGULAR",
                      let name = UntisValue.string(current["displayName"]), !name.isEmpty else { return nil }
                return name
            }
        }
        func text(_ kind: String, flat: String) -> String? {
            let structured = UntisValue.list(entry["texts"]).first { (($0 as? [String: Any])?["type"] as? String) == kind }
            let value = UntisText.plain(UntisValue.string((structured as? [String: Any])?["text"]))
            if !value.isEmpty { return value }
            let plain = UntisText.plain(UntisValue.string(entry[flat]))
            return plain.isEmpty ? nil : plain
        }

        var out = PeriodExtras()
        out.addedTeachers = added("position1")
        out.addedSubjects = added("position2")
        out.addedRooms = added("position3")
        out.icons = UntisValue.list(entry["icons"]).compactMap(UntisValue.string).filter { !$0.isEmpty }
        out.lessonInfo = text("LESSON_INFO", flat: "lessonInfo")
        out.lessonText = text("LESSON_TEXT", flat: "lessonText")
        out.substitutionText = text("SUBSTITUTION", flat: "substitutionText")
        out.texts = UntisValue.list(entry["texts"]).compactMap { item in
            guard let item = item as? [String: Any] else { return nil }
            let value = UntisText.plain(UntisValue.string(item["text"]))
            return value.isEmpty ? nil : PeriodText(type: UntisValue.string(item["type"]) ?? "", text: value)
        }
        return out
    }
}

/// The little glyph a period's `icons` entry stands for. Servers spell these differently across
/// versions and the set grows, so it's matched loosely and an unknown one still shows.
public enum LessonMark: Equatable, Sendable {
    case homework, exam, attachment, substitution, online, classRegister, note, unknown

    public init(untisName: String) {
        let name = untisName.uppercased()
        func has(_ keys: String...) -> Bool { keys.contains { name.contains($0) } }
        if has("HOMEWORK") { self = .homework }
        else if has("EXAM", "TEST") { self = .exam }
        else if has("ATTACH", "FILE", "DOCUMENT") { self = .attachment }
        else if has("SUBSTITUT", "STANDIN", "STAND_IN") { self = .substitution }
        else if has("ONLINE", "VIDEO", "TEAMS", "ZOOM") { self = .online }
        else if has("CLASSREG", "CLASS_REG", "REGISTER") { self = .classRegister }
        else if has("NOTE", "INFO", "TEXT", "COMMENT") { self = .note }
        else { self = .unknown }
    }
}
