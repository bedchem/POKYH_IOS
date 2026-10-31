import Foundation

/// The authenticator app's code as people type or paste it ("123 456").
public enum TwoFactorCode {
    public static let length = 6

    /// What the field keeps: digits and the one space apps show in the middle.
    public static func input(_ raw: String) -> String {
        String(raw.filter { $0.isASCII && ($0.isNumber || $0 == " ") }.prefix(length + 1))
    }

    public static func digits(_ raw: String) -> String {
        raw.filter { $0.isASCII && $0.isNumber }
    }

    public static func isComplete(_ raw: String) -> Bool {
        digits(raw).count == length
    }
}

/// What WebUntis' own sign-in form (`j_spring_security_check`) answered.
public enum FormLoginAnswer: Equatable, Sendable {
    /// Signed in. The session is the one the answer set, or the page's when it set none.
    case ok
    case codeRequired
    case codeWrong
    case badCredentials
    case refused
    case unavailable

    /// `sentCode`: this attempt carried a code, so being asked for one means it was wrong.
    public static func parse(_ body: Data, status: Int, sentCode: Bool) -> FormLoginAnswer {
        guard let answer = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return status >= 500 ? .unavailable : .refused
        }
        switch answer["state"] as? String {
        case "SUCCESS": return .ok
        case "TOKEN_REQUIRED":
            return sentCode || (answer["invalidToken"] as? Bool) == true ? .codeWrong : .codeRequired
        case "LOGIN_ERROR": return .badCredentials
        default: return .refused
        }
    }

    /// `application/x-www-form-urlencoded`. Passwords hold anything, `&` and `+` included.
    public static func formBody(_ fields: [(String, String)]) -> Data {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = fields.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: safe) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: safe) ?? "")"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}

/// The sign-in code in what the scanner read: the website's QR code holds it as plain text or
/// as a link, depending on how the backend is set up (`services/qrLogin.ts`).
public enum WebSignInCode {
    private static let prefix = "POKYH-LOGIN:"
    private static let linkPath = "l"

    /// `host`: the website, a link to anywhere else isn't ours. Nil for anything that isn't ours.
    public static func of(_ scanned: String, host: String?) -> String? {
        let text = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Some camera apps lowercase it when they open it as a link.
        if text.lowercased().hasPrefix(prefix.lowercased()) {
            return valid(String(text.dropFirst(prefix.count)))
        }
        guard let host, let parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.port == nil,
              let found = parts.host?.lowercased(), matches(found, host.lowercased()) else { return nil }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: true)
        guard path.count == 2, path[0] == linkPath else { return nil }
        return valid(String(path[1]))
    }

    /// The site itself or anything under it. "www." on the configured host doesn't narrow it.
    private static func matches(_ found: String, _ host: String) -> Bool {
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return found == site || found.hasSuffix("." + site)
    }

    private static func valid(_ code: String) -> String? {
        code.range(of: "^[A-Za-z0-9_-]{24,64}$", options: .regularExpression) != nil ? code : nil
    }
}

/// How the device list words a signed-in device.
public enum DeviceLabels {
    /// Two of model, browser and system, whichever are known.
    public static func name(model: String, os: String, browser: String, unknown: String) -> String {
        let parts = distinct([model, browser, os]).prefix(2)
        return parts.isEmpty ? unknown : parts.joined(separator: " · ")
    }

    public static func place(city: String?, region: String?, country: String, unknown: String) -> String {
        let parts = distinct([city ?? "", region ?? "", country])
        return parts.isEmpty ? unknown : parts.joined(separator: ", ")
    }

    /// "31. Okt. 2026, 08:15" in the zone given. What can't be read shows as it came.
    public static func when(_ iso: String, lang: Lang, timeZone: TimeZone = .current) -> String {
        guard let date = date(iso) else {
            return String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        let format = DateFormatter()
        format.locale = lang.locale
        format.timeZone = timeZone
        format.dateFormat = lang == .de ? "d. MMM yyyy, HH:mm" : "d MMM yyyy, HH:mm"
        return format.string(from: date)
    }

    private static func date(_ iso: String) -> Date? {
        let reader = ISO8601DateFormatter()
        reader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = reader.date(from: iso) { return date }
        reader.formatOptions = [.withInternetDateTime]
        return reader.date(from: iso)
    }

    private static func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
