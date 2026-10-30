import Foundation

import PokyhCore

/// Central configuration. Hosts, keys and the fallback school come from Config/*.xcconfig via
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
    static var imprintURL: String { app.websiteURL.absoluteString + "/legal/impressum" }
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

    // WebUntis. The build's school is only the fallback for accounts saved before the school
    // search; everyone else signs in at the school they picked (School / SchoolChoice below).
    static var untisBase: String { "https://\(defaultServer)/WebUntis" }
    static var school: String { info("POKYHDefaultSchool") }
    static var defaultServer: String { info("POKYHDefaultUntisServer") }
    static var defaultSchoolName: String { info("POKYHDefaultSchoolName") }
    static let untisClient = "pockyh"

    // schoolname cookie: "_" + base64(school)
    static var schoolCookie: String { School.fallback.cookie }

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
        static let jsonRpcIntern    = "/jsonrpc_intern.do"
        static let formLogin        = "/j_spring_security_check"
        static let classServices    = "/api/classreg/classservices"
        static let homeworks        = "/api/homeworks/lessons"
        // Absences as the official client writes them: classic endpoints with the CSRF token.
        static let absenceMeta      = "/api/classreg/absences/meta"
        static let absenceReport    = "/api/classreg/absences/students/self"
        static let absenceSingle    = "/api/classreg/absences/student"
        static let absenceEdit      = "/api/classreg/absences/students/edit"
        static let reports          = "/reports.do"
        static let profilePassword  = "/api/profile/access/password"
        static let passwordReset    = "/passwordReset/resetPassword.do"
        // MessageCenter writes go to v2 (multipart), v1 stays as the fallback for older instances.
        static let messagesV2       = "/api/rest/view/v2/messages"
        static let messagesV2Drafts = "/api/rest/view/v2/messages/drafts"
        static let messageRecipients = "/api/rest/view/v1/messages/recipients/static/persons"
        static let messagePermissions = "/api/rest/view/v1/messages/permissions"

        static func messageDetail(_ id: Int) -> String { "\(messages)/\(id)" }
        static func messageMarkRead(_ id: Int) -> String { "\(messages)/\(id)/markasread" }
        static func messageAttachments(_ id: Int) -> String { "\(messages)/\(id)/attachments" }
        static func messageReplyForm(_ id: Int) -> String { "\(messages)/\(id)/reply-form?contentAsHtml=false" }
        static func messageReply(_ id: Int) -> String { "\(messagesV2)/\(id)/reply" }
        static func messageReadConfirmation(_ id: Int) -> String { "\(messages)/\(id)/read-confirmation" }
        static func messageRevoke(_ id: Int) -> String { "\(messages)/\(id)/revoke" }
        static func messageReadStatus(_ id: Int) -> String { "\(messagesSent)/\(id)/request-confirmation-status" }
        // Keyed on the attachment's storage UUID, not on the message.
        static func attachmentStorageURL(_ storageId: String) -> String { "\(messages)/\(storageId)/attachmentstorageurl" }
        /// Direct downloads, in the order the web tries them.
        static func attachmentCandidates(messageId: Int, storageId: String, fileId: Int) -> [String] {
            var list: [String] = []
            if !storageId.isEmpty {
                list += ["\(messages)/\(messageId)/attachments/\(storageId)",
                         "\(messages)/\(messageId)/attachments/\(storageId)/content",
                         "\(messages)/\(messageId)/storage/\(storageId)"]
            }
            if fileId > 0 {
                list += ["\(messages)/\(messageId)/attachments/\(fileId)",
                         "\(messages)/\(messageId)/attachments/\(fileId)/content"]
            }
            return list
        }
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
        static let schoolSearch = "/webuntis/schools"
        static let loginOptions = "/webuntis/login-options"
        static let sessions     = "/auth/sessions"
        static let signOutOthers = "/auth/sessions/sign-out-others"
        static let loginHistory = "/auth/login-history"
        static let privacyStatus = "/privacy/status"
        static let privacyAcknowledge = "/privacy/acknowledge"
        static let usageStats   = "/privacy/usage-stats"
        static let dataExport   = "/users/me/export"
        static func todos(_ username: String) -> String { "/users/\(username)/todos" }
        static func reminders(_ classId: String) -> String { "/classes/\(classId)/reminders" }
    }
}

extension Strings {
    /// The texts in the language the app speaks right now, for code outside the views.
    static var current: Strings { .of(LanguageChoice.current(in: .standard)) }
}

// ── Schools ──────────────────────────────────────────────────────────────────

extension School {
    /// The build's school, for accounts saved before the school search.
    static var fallback: School {
        School(loginName: Config.school, server: Config.defaultServer,
               name: Config.defaultSchoolName.isEmpty ? Config.school : Config.defaultSchoolName)
    }

    var isFallback: Bool { loginName == Config.school && server == Config.defaultServer }

    /// "https://<server>/WebUntis"
    var baseString: String { "https://\(server)/WebUntis" }

    /// The login name for a `?school=` query: names may hold spaces, `&`, `+` or brackets.
    var query: String {
        loginName.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? loginName
    }

    /// schoolname cookie: "_" + base64(loginName)
    var cookie: String { "_" + Data(loginName.utf8).base64EncodedString() }

    /// The school's own WebUntis page, for the links into it (Office 365 steps, password reset).
    func page(_ fragment: String) -> URL? { URL(string: "\(baseString)/?school=\(query)#\(fragment)") }
}

/// The school picked on the sign-in screen, the web's `lib/school-choice.ts`: kept on this device
/// until the end of the school year (31 August), and for at least 30 days, so the next sign-in
/// starts at the password. Only what the public school search shows is kept.
enum SchoolChoice {
    private static let key = "pokyh_school_choice"
    private static let minDays = 30

    private struct Stored: Codable {
        var school: School
        var expires: Date
    }

    static func read() -> School? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        guard stored.expires > .now else {
            forget()
            return nil
        }
        return stored.school
    }

    static func save(_ school: School) {
        var kept = school
        kept.name = String(kept.name.prefix(200))
        kept.address = String(kept.address.prefix(300))
        guard let data = try? JSONEncoder().encode(Stored(school: kept, expires: expiry())) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 31 August, 23:59:59 of the school year the day lies in, but never sooner than 30 days.
    static func expiry(from now: Date = .now, calendar: Calendar = .current) -> Date {
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now) + (month >= 9 ? 1 : 0)
        let end = calendar.date(from: DateComponents(year: year, month: 8, day: 31, hour: 23, minute: 59, second: 59)) ?? now
        let soonest = calendar.date(byAdding: .day, value: minDays, to: now) ?? now
        return max(end, soonest)
    }
}
