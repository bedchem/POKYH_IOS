import Foundation

/// The WebUntis account's own settings, as its profile pages answer them.
public struct UntisAccount: Equatable, Sendable {
    public struct Language: Equatable, Hashable, Identifiable, Sendable {
        public var key: String
        public var name: String
        public var id: String { key }

        public init(key: String, name: String) {
            self.key = key
            self.name = name
        }
    }

    public var email: String
    public var forwardToEmail: Bool
    public var passwordChangeAllowed: Bool
    public var twoFactorAvailable: Bool
    public var twoFactorEnabled: Bool
    public var twoFactorRequired: Bool
    public var languageCode: String
    public var languages: [Language]

    /// nil when `general` has no profile in it. The other two are extras: without them the
    /// account still shows, just without two-factor or a language choice.
    public init?(general: Data, access: Data?, languages: Data?) {
        let data = LooseJSON(data: general)["data"]
        let profile = data["profile"]
        guard profile.object != nil else { return nil }
        let rights = LooseJSON(data: access)["data"]
        let totp = rights["totpCredentials"]
        email = profile["email"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        forwardToEmail = profile["forwardMessageToEmail"].bool == true
        // Only a clear no hides it; WebUntis rejects the change itself if the school forbids it.
        passwordChangeAllowed = data["pwChangeAllowed"].bool != false
        twoFactorAvailable = rights["canUseTotp"].bool == true
        twoFactorEnabled = totp["secret"].string?.contains { !$0.isWhitespace } == true
        twoFactorRequired = totp["isTotpRequired"].bool == true
        languageCode = profile["languageCode"].string ?? ""
        var seen = Set<String>()
        self.languages = LooseJSON(data: languages)["data"]["languages"].array.compactMap { language in
            guard let key = language["key"].string, let name = language["name"].string,
                  !key.isEmpty, !name.isEmpty, seen.insert(key).inserted else { return nil }
            return Language(key: key, name: name)
        }
    }

    /// Whether the row for it shows at all.
    public var offersTwoFactor: Bool { twoFactorAvailable || twoFactorEnabled }
    public var hasEmail: Bool { !email.isEmpty }

    public var languageName: String {
        languages.first { $0.key == languageCode }?.name ?? languageCode
    }

    /// What goes to /api/profile/general: WebUntis takes the whole set, so what isn't changing
    /// goes back as it came. nil when the profile can't be read or sent back.
    public static func saveBody(general: Data, email: String? = nil, forwardToEmail: Bool? = nil, languageCode: String? = nil) -> [String: Any]? {
        let profile = LooseJSON(data: general)["data"]["profile"]
        guard let raw = profile.object else { return nil }
        var body: [String: Any] = [
            "languageCode": languageCode ?? profile["languageCode"].string ?? "",
            "email": email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? profile["email"].string ?? "",
            "forwardMessageToEmail": forwardToEmail ?? (profile["forwardMessageToEmail"].bool == true),
            "userTaskNotifications": profile["userTaskNotifications"].bool == true,
        ]
        for key in ["itemOnStartPage", "showLessonsOfDay", "showNextDayPeriods"] {
            if let value = raw[key] { body[key] = value }
        }
        // JSONSerialization raises instead of throwing on what it can't write.
        return JSONSerialization.isValidJSONObject(body) ? body : nil
    }

    /// Empty is fine, that removes the address.
    public static func isValidEmail(_ text: String) -> Bool {
        let mail = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if mail.isEmpty { return true }
        return mail.count <= 200 && mail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}

/// A new secret for the authenticator app. Nothing is on yet. Stays in memory while the setup
/// is open, and keeps out of logs.
public struct TwoFactorSetup: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var secret: String
    /// The otpauth link for the QR code, nil if WebUntis sent none or something else.
    public var link: URL?

    public init?(created data: Data) {
        let totp = LooseJSON(data: data)["data"]["totpCredentials"]
        guard let raw = totp["secret"].string else { return nil }
        let clean = raw.filter { !$0.isWhitespace }.uppercased()
        guard !clean.isEmpty, clean.count <= 256,
              clean.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "=") }) else { return nil }
        secret = clean
        // Opened as it is, so it can't be allowed to be just any address.
        link = totp["qrText"].string.flatMap(URL.init(string:)).flatMap { $0.scheme?.lowercased() == "otpauth" ? $0 : nil }
    }

    /// In fours, for typing it in.
    public var groupedSecret: String {
        var groups: [Substring] = []
        var rest = Substring(secret)
        while rest.last == "=" { rest = rest.dropLast() }
        while !rest.isEmpty {
            groups.append(rest.prefix(4))
            rest = rest.dropFirst(4)
        }
        return groups.joined(separator: " ")
    }

    public var description: String { "TwoFactorSetup(secret hidden)" }
    public var debugDescription: String { description }
}

/// What's wrong with a new password before WebUntis gets to judge it.
public enum PasswordChangeProblem: Equatable, Sendable {
    case missing, mismatch, unchanged

    public static func check(old: String, new: String, repeated: String) -> PasswordChangeProblem? {
        if old.isEmpty || new.isEmpty { return .missing }
        if new != repeated { return .mismatch }
        if old == new { return .unchanged }
        return nil
    }
}
