import Foundation

/// What a lesson's detail adds to the timetable's own fields (web: lessonDetail.ts, Android:
/// UntisClient.lessonDetail). Every field is optional; what's missing just doesn't show.
public struct LessonDetail: Codable, Equatable, Sendable {
    public enum TextKind: String, Codable, Sendable {
        case teachingContent, teacherNote, lessonInfo, substitution
    }

    public struct Text: Codable, Equatable, Sendable {
        public var kind: TextKind
        public var text: String

        public init(kind: TextKind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// A teacher or room of the lesson with its status, where WebUntis says what changed.
    public struct Element: Codable, Equatable, Sendable {
        public var name: String
        public var shortName: String
        public var longName: String
        public var status: String

        public init(name: String, shortName: String = "", longName: String = "", status: String = "REGULAR") {
            self.name = name
            self.shortName = shortName
            self.longName = longName
            self.status = status
        }

        /// The exact values vary by version, so only the sense is read.
        public var mark: FieldMark {
            let value = status.uppercased()
            if value.isEmpty || value == "REGULAR" { return .plain }
            if ["REMOV", "CANCEL", "ABSENT", "DELET"].contains(where: value.contains) { return .removed }
            return .added
        }
    }

    public var texts: [Text] = []
    public var classes: [String] = []
    public var group = ""
    public var examName = ""
    public var examDescription = ""
    public var homeworks: [String] = []
    public var teachers: [Element] = []
    public var rooms: [Element] = []

    public init(texts: [Text] = [], classes: [String] = [], group: String = "", examName: String = "",
                examDescription: String = "", homeworks: [String] = [], teachers: [Element] = [], rooms: [Element] = []) {
        self.texts = texts
        self.classes = classes
        self.group = group
        self.examName = examName
        self.examDescription = examDescription
        self.homeworks = homeworks
        self.teachers = teachers
        self.rooms = rooms
    }

    private static let textFields: [(TextKind, String)] = [
        (.teachingContent, "teachingContent"),
        (.teacherNote, "notesAll"),
        (.lessonInfo, "lessonInfo"),
        (.substitution, "substText"),
    ]

    /// nil when the answer isn't a detail at all. The lesson's own teachers and rooms come from the
    /// entry with its id, or from the only entry there is; another lesson's mustn't show as history.
    public static func read(_ root: Any?, lessonId: Int) -> LessonDetail? {
        guard let list = (root as? [String: Any])?["calendarEntries"] as? [Any]
                ?? UntisValue.payload(root)["calendarEntries"] as? [Any] else { return nil }
        let entries = list.compactMap { $0 as? [String: Any] }

        var out = LessonDetail()
        for entry in entries {
            for (kind, key) in textFields {
                let text = UntisText.plain(UntisValue.string(entry[key]))
                if !text.isEmpty { out.texts.append(Text(kind: kind, text: text)) }
            }
            for klass in UntisValue.list(entry["klasses"]) {
                let name = displayName(klass)
                if !name.isEmpty, !out.classes.contains(name) { out.classes.append(name) }
            }
            if out.group.isEmpty { out.group = displayName(entry["mainStudentGroup"], nameFirst: true) }
            let exam = entry["exam"] as? [String: Any]
            if out.examName.isEmpty { out.examName = UntisText.plain(UntisValue.string(exam?["name"])) }
            if out.examDescription.isEmpty { out.examDescription = UntisText.plain(UntisValue.string(exam?["description"])) }
            for homework in UntisValue.list(entry["homeworks"]) {
                let text = UntisText.plain(UntisValue.string((homework as? [String: Any])?["text"]))
                if !text.isEmpty, !out.homeworks.contains(text) { out.homeworks.append(text) }
            }
        }

        let own = entries.first { UntisValue.int($0["id"]) == lessonId } ?? (entries.count == 1 ? entries[0] : nil)
        if let own {
            out.teachers = elements(own["teachers"])
            out.rooms = elements(own["rooms"])
        }
        return out
    }

    private static func displayName(_ value: Any?, nameFirst: Bool = false) -> String {
        guard let object = value as? [String: Any] else { return "" }
        let keys = nameFirst ? ["name", "displayName", "shortName"] : ["displayName", "name", "shortName"]
        for key in keys {
            let text = UntisText.plain(UntisValue.string(object[key]))
            if !text.isEmpty { return text }
        }
        return ""
    }

    private static func elements(_ value: Any?) -> [Element] {
        UntisValue.list(value).compactMap { item in
            guard let item = item as? [String: Any] else { return nil }
            let short = UntisValue.string(item["shortName"])?.trimmingCharacters(in: .whitespaces) ?? ""
            let display = UntisValue.string(item["displayName"])?.trimmingCharacters(in: .whitespaces) ?? ""
            let long = UntisValue.string(item["longName"])?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = display.isEmpty ? short : display
            guard !name.isEmpty else { return nil }
            return Element(name: name, shortName: short, longName: long, status: UntisValue.string(item["status"]) ?? "")
        }
    }

    /// A date and time as the route wants them, already percent-encoded. YYYYMMDD and HHMM.
    public static func queryTime(date: Int, time: Int) -> String {
        let (y, m, d) = (date / 10000, date / 100 % 100, date % 100)
        return String(format: "%04d-%02d-%02dT%02d%%3A%02d%%3A00", y, m, d, time / 100, time % 100)
    }
}

/// One free-text block of the lesson sheet.
public struct LessonNote: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case note, lessonText, substitution, teachingContent, teacherNote, info
    }

    public var kind: Kind
    public var text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum LessonNotes {
    /// Every text a period can carry, each under its own heading and each once: the timetable's
    /// own first, then what the lesson's detail adds.
    public static func collect(note: String?, lessonText: String?, substitutionText: String?,
                               detail: LessonDetail?, texts: [PeriodText]) -> [LessonNote] {
        var out: [LessonNote] = []
        func add(_ kind: LessonNote.Kind, _ text: String?) {
            let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !out.contains(where: { same($0.text, value) }) { out.append(LessonNote(kind, value)) }
        }
        add(.note, note)
        add(.lessonText, lessonText)
        add(.substitution, substitutionText)
        for text in detail?.texts ?? [] {
            switch text.kind {
            case .teachingContent: add(.teachingContent, text.text)
            case .teacherNote: add(.teacherNote, text.text)
            case .lessonInfo: add(.note, text.text)
            case .substitution: add(.substitution, text.text)
            }
        }
        for text in texts {
            switch text.type {
            case "SUBSTITUTION": add(.substitution, text.text)
            case "LESSON_TEXT": add(.lessonText, text.text)
            case "LESSON_INFO": add(.note, text.text)
            default: add(.info, text.text)
            }
        }
        return out
    }

    /// The exam's name and what it covers, once each.
    public static func examText(detail: LessonDetail?, description: String?) -> String {
        let own = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        for line in [detail?.examName ?? "", own.isEmpty ? (detail?.examDescription ?? "") : own]
        where !line.isEmpty && !lines.contains(line) {
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        func squeezed(_ s: String) -> String {
            s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces).lowercased()
        }
        return squeezed(a) == squeezed(b)
    }
}

/// Labels the shared tables don't have yet, as the web words them.
public struct LessonExtraStrings: Sendable {
    public let teachingContent: String
    public let teacherNote: String

    public static func of(_ lang: Lang) -> LessonExtraStrings {
        switch lang {
        case .de: LessonExtraStrings(teachingContent: "Lehrstoff", teacherNote: "Notiz der Lehrkraft")
        case .it: LessonExtraStrings(teachingContent: "Contenuto della lezione", teacherNote: "Nota del docente")
        case .en: LessonExtraStrings(teachingContent: "Lesson content", teacherNote: "Teacher’s note")
        }
    }
}

extension Strings {
    public var lessonExtras: LessonExtraStrings { .of(lang) }
}
