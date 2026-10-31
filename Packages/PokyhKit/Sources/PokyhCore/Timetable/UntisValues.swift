import Foundation

/// Reads WebUntis' answers the way the web's routes do: anything can be missing or nested one
/// level deeper, and a missing value is nil, never an error.
enum UntisValue {
    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    static func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    static func list(_ value: Any?) -> [Any] { value as? [Any] ?? [] }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, !isBool(number) { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber, !isBool(number) { return number.stringValue }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return string.lowercased() == "true" || string == "1" }
        return nil
    }

    /// Most routes answer `{data: {...}}`, some the object itself.
    static func payload(_ root: Any?) -> [String: Any] {
        let object = root as? [String: Any] ?? [:]
        return object["data"] as? [String: Any] ?? object
    }

    private static func isBool(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

public enum UntisText {
    /// Plain text from WebUntis' rich text: line breaks kept, tags and entities resolved.
    public static func plain(_ value: String?) -> String {
        guard let value else { return "" }
        guard value.contains("<") || value.contains("&") else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out = value
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|li|h\d)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        if let re = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            for match in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(match.range, in: out), let digits = Range(match.range(at: 1), in: out),
                      let code = UInt32(out[digits]), let scalar = Unicode.Scalar(code) else { continue }
                out.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// WebUntis routes only the timetable's extras use.
public enum TimetableRoutes {
    public static let lessonDetail = "/api/rest/view/v2/calendar-entry/detail"
    public static let filter = "/api/rest/view/v1/timetable/filter"
    public static let subjectImages = "/subject-images"
}
