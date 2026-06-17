import Foundation

/// Zentrale Konfiguration. Geheimnisse (Keys) liegen in der gitignorten
/// `Secrets.swift`; alle URLs und API-Routen sind hier an EINEM Ort gebündelt,
/// damit sie einfach zu verwalten sind.
enum Config {
    // ── Hintergrund-Aktualisierung (BGTaskScheduler) ─────────────────────────
    /// Muss exakt mit `BGTaskSchedulerPermittedIdentifiers` in der Info.plist übereinstimmen.
    static let bgRefreshId = "dev.plattnericus.POKYH.refresh"

    // ── Rechtliches / Support (App-Store-Pflicht: erreichbare Datenschutz-URL) ──
    // Diese Seiten MÜSSEN online erreichbar sein (sonst App-Store-Ablehnung) und die
    // Datenschutz-URL muss zusätzlich in App Store Connect hinterlegt werden.
    static let privacyURL = "https://pokyh.com/datenschutz"
    static let termsURL   = "https://pokyh.com/nutzungsbedingungen"
    static let supportEmail = "support@pokyh.com"

    /// App-Version + Build aus dem Bundle (für die „Über"-Sektion).
    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // ── POKYH Backend ──────────────────────────────────────────────────────
    static let backendURL = "https://api.pokyh.com"
    static var apiKey: String { Secrets.apiKey }
    static var serverKey: String { Secrets.serverKey }

    /// Diagnose-/Entwicklermodus. Nur dann werden Debug-Hilfen (Klassen-Diagnose)
    /// angezeigt — in Produktion (`Secrets.isDebug = false`) komplett aus.
    static var isDebug: Bool { Secrets.isDebug }

    // ── WebUntis ───────────────────────────────────────────────────────────
    static let untisBase = "https://lbs-brixen.webuntis.com/WebUntis"
    static let school = "lbs-brixen"
    static let untisClient = "pockyh"

    /// schoolname-Cookie: "_" + base64(school)
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
