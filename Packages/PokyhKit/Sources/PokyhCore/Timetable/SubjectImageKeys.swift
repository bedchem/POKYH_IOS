import Foundation

/// The backend's subject photos. It has no placeholder, so a subject is only asked for once the
/// key list says there's a photo. Keys have to match the web's, or the apps show different ones.
public enum SubjectImageKeys {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func key(long: String, short: String) -> String {
        let name = long.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? short : long
        return name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `GET /subject-images`: `[{subject}]`.
    public static func read(_ data: Data) -> Set<String> {
        let rows = UntisValue.list(UntisValue.parse(data)).compactMap { $0 as? [String: Any] }
        return Set(rows.compactMap { ($0["subject"] as? String)?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    public static func path(for key: String) -> String {
        TimetableRoutes.subjectImages + "/" + (key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? key)
    }

    /// What `POST /subject-images/report` takes: each subject once, within the route's limits.
    public static func report(_ subjects: [(short: String, long: String)]) -> [[String: String]] {
        var seen = Set<String>()
        var rows: [[String: String]] = []
        for subject in subjects {
            let key = key(long: subject.long, short: subject.short)
            guard !key.isEmpty, key.count <= 200, seen.insert(key).inserted else { continue }
            let long = subject.long.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append([
                "key": key,
                "longName": String((long.isEmpty ? subject.short : long).prefix(200)),
                "shortName": String(subject.short.prefix(50)),
            ])
            if rows.count == 100 { break }
        }
        return rows
    }
}
