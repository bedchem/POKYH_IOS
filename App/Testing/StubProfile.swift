#if DEBUG
import Foundation

/// WebUntis' account pages for the UI tests, with the state a test changes through them. What an
/// account starts with comes from `POKYH_STUB_PROFILE`, a comma list: noemail, required, on,
/// nochange, notavailable. The secret and code are made up; 123456 is right, as for `zweifa`.
nonisolated enum StubProfile {
    private struct State {
        var email: String
        var forward: Bool
        var language = "de"
        var twoFactor: Bool
        var password: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var states: [String: State] = [:]

    private static let flags = Set((ProcessInfo.processInfo.environment["POKYH_STUB_PROFILE"] ?? "").split(separator: ",").map(String.init))
    private static let secret = "JBSW Y3DP EHPK 3PXP"

    private static func state(_ user: String) -> State {
        states[user] ?? State(email: flags.contains("noemail") ? "" : "\(user)@stub.invalid", forward: false, twoFactor: flags.contains("on") || flags.contains("required"))
    }

    /// Once a test changed the password, only the new one signs in.
    static func rejects(_ user: String, password: String?) -> Bool {
        lock.withLock { state(user).password.map { $0 != password } ?? false }
    }

    static func asksForCode(_ user: String) -> Bool {
        lock.withLock { states[user]?.twoFactor ?? false }
    }

    static func answer(_ path: String, method: String, user: String, body: Data) -> StubAnswer {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        return lock.withLock {
            var current = state(user)
            defer { states[user] = current }
            switch (method, path) {
            case ("GET", "/api/profile/general"):
                let profile: [String: Any] = ["email": current.email, "forwardMessageToEmail": current.forward, "languageCode": current.language, "userTaskNotifications": true,
                                              "itemOnStartPage": "TIMETABLE", "showLessonsOfDay": NSNull(), "showNextDayPeriods": 2]
                return StubAnswer(json: ["data": ["pwChangeAllowed": !flags.contains("nochange"), "profile": profile] as [String: Any]])
            case ("POST", "/api/profile/general"):
                let email = json["email"] as? String ?? ""
                if email.hasPrefix("abgelehnt@") {
                    return StubAnswer(json: ["validationErrors": [["errorMessage": "Diese Adresse nimmt WebUntis nicht."]]], status: 400)
                }
                current.email = email
                current.forward = json["forwardMessageToEmail"] as? Bool ?? false
                current.language = json["languageCode"] as? String ?? ""
                return StubAnswer(json: ["data": [String: Any]()])
            case ("GET", "/api/profile/access"):
                let totp: [String: Any] = ["secret": current.twoFactor ? secret : NSNull(), "isTotpRequired": flags.contains("required")]
                return StubAnswer(json: ["data": ["canUseTotp": !flags.contains("notavailable"), "totpCredentials": totp] as [String: Any]])
            case ("GET", "/api/profile/languages"):
                return StubAnswer(json: ["data": ["languages": [["key": "de", "name": "Deutsch"], ["key": "it", "name": "Italiano"], ["key": "en", "name": "English"]]]])
            case ("POST", "/api/profile/access/password"):
                let old = json["oldPassword"] as? String
                if old == "falsch" || current.password.map({ $0 != old }) ?? false {
                    return StubAnswer(json: ["errorMessage": "Das aktuelle Passwort stimmt nicht."], status: 400)
                }
                current.password = json["newPassword"] as? String
                return StubAnswer(json: [String: Any]())
            case ("POST", "/api/profile/access/totp/create"):
                return StubAnswer(json: ["data": ["totpCredentials": ["secret": secret, "qrText": "otpauth://totp/POKYH:\(user)?secret=JBSWY3DPEHPK3PXP&issuer=POKYH"]]])
            case ("POST", "/api/profile/access/totp"):
                guard json["token"] as? Int == 123456, json["algorithm"] as? String == "STANDARD",
                      (json["key"] as? String) == secret.filter({ !$0.isWhitespace }) else {
                    return StubAnswer(json: ["errors": [["title": "invalid token"]]], status: 400)
                }
                current.twoFactor = true
                return StubAnswer(json: ["data": ["totpCredentials": ["secret": secret]]])
            case ("DELETE", "/api/profile/access/totp"):
                current.twoFactor = false
                return StubAnswer(json: [String: Any]())
            default:
                StubServer.log("UNROUTED profile \(method) \(path)")
                return StubAnswer(json: [String: Any]())
            }
        }
    }
}
#endif
