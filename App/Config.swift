import Foundation

import PokyhCore

/// Central configuration. Hosts, keys and the default school come from Config/*.xcconfig via
/// Info.plist (PokyhCore.AppConfig); only API routes live here.
enum Config {
    private static var app: AppConfig { .current }
    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }

    // Must match BGTaskSchedulerPermittedIdentifiers.
    static var bgRefreshId: String { app.backgroundTask }

    // Legal pages have to be reachable for App Review.
    static var privacyURL: String { app.websiteURL.absoluteString + "/legal?view=datenschutz" }
    static var privacyNoticeURL: String { app.websiteURL.absoluteString + "/api/privacy-notice" }
    static var termsURL: String { app.websiteURL.absoluteString + "/nutzungsbedingungen" }
    static var supportEmail: String { app.supportEmail }

    static var appVersion: String { "\(app.version) (\(app.build))" }

    // POKYH backend
    static var backendURL: String { app.backendURL.absoluteString }
    static var apiKey: String { app.apiKey }
    static var serverKey: String { app.serverKey }

    // Debug helpers (class diagnosis) only in debug builds.
    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    // WebUntis. The default school until the school search lands on iOS.
    static var untisBase: String { "https://\(info("POKYHDefaultUntisServer"))/WebUntis" }
    static var school: String { info("POKYHDefaultSchool") }
    static let untisClient = "pockyh"

    // schoolname cookie: "_" + base64(school)
    static var schoolCookie: String { "_" + Data(school.utf8).base64EncodedString() }

    // ── Alle API-Routen (relative Pfade) — zentral verwaltet ────────────────
    enum Routes {
        // WebUntis
        static let jsonRpc          = "/jsonrpc.do"
        static let token            = "/api/token/new"
        static let timetable        = "/api/rest/view/v1/timetable/entries"
        static let gradeList        = "/api/classreg/grade/grading/list"
        static let gradeLesson      = "/api/classreg/grade/grading/lesson"
        static let absences         = "/api/classreg/absences/students"
        static let messages         = "/api/rest/view/v1/messages"
        static let messagesSent     = "/api/rest/view/v1/messages/sent"
        static let messagesDrafts   = "/api/rest/view/v1/messages/drafts"
        static let classregEvents   = "/api/classreg/classregevents"
        static let appDataCandidates = [
            "/api/rest/view/v1/app/data", "/api/app/data",
            "/api/rest/view/v1/users/me/data", "/api/rest/view/v2/app/data",
        ]
        static func messageDetail(_ id: Int) -> String { "\(messages)/\(id)" }
        static func messageMarkRead(_ id: Int) -> String { "\(messages)/\(id)/markasread" }
        static func messageFolder(_ folder: String) -> String {
            switch folder {
            case "sent": return messagesSent
            case "drafts": return messagesDrafts
            default: return messages
            }
        }

        // POKYH Backend
        static let authLogin    = "/auth/login"
        static let authRegister = "/auth/register"
        static let authMe       = "/auth/me"
        static let dishes       = "/dishes"
        static let dishRatings  = "/dish-ratings"        // + /{id} | /batch
        static let dishComments = "/dish-comments"       // + /{id}
        static let classesMine  = "/classes/mine"
        static func todos(_ username: String) -> String { "/users/\(username)/todos" }
        static func reminders(_ classId: String) -> String { "/classes/\(classId)/reminders" }
    }
}
