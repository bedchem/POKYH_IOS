import Foundation
import PokyhCore

// ── Session ────────────────────────────────────────────────────────────────

struct UserSession: Codable, Equatable {
    var sessionId: String
    var bearerToken: String
    var studentId: Int
    var klasseId: Int
    var klasseName: String
    var username: String
    var personName: String?
    var personType: Int?
    var isParent: Bool
    /// POKYH-Backend Tokens (für Todos / Erinnerungen / Klasse)
    var apiToken: String?
    var apiRefresh: String?
    var stableUid: String?
    var classId: String?
    /// Profilbild-URL aus den WebUntis-App-Daten (`user.person.imageUrl`).
    var imageUrl: String?
    /// The WebUntis school the account signs in at; nil for accounts from before the school search.
    var school: School? = nil

    var schoolRef: School { school ?? .fallback }

    /// Hat diese Sitzung ein verknüpftes WebUntis-Konto (Stundenplan/Noten)?
    /// Reine POKYH-Backend-Konten (Login-Fallback) haben `studentId == 0`. Gilt auch
    /// für die token-lose Offline-Sitzung (Stundenplan kommt dann aus dem Cache).
    var hasUntis: Bool { studentId > 0 }

    /// WebUntis-`personType` 5 = Schüler. Eltern werden ausgeschlossen.
    /// Fällt `personType` weg, gilt ein eigener Klassenkontext (klasseId > 0,
    /// kein Elternteil) als Schüler-Indiz.
    var isStudent: Bool {
        if isParent { return false }
        if let t = personType { return t == 5 }
        return klasseId > 0
    }
}

// ── Gespeicherte Konten (Mehrbenutzer + Face ID) ───────────────────────────

struct SavedAccount: Codable, Equatable, Identifiable {
    var username: String           // dient als ID & Keychain-Schlüssel
    var displayName: String        // Klassenname o. Benutzername
    var nickname: String?          // optionaler, lokal vergebener Spitzname
    var imageUrl: String?          // Profilbild-URL (WebUntis) für die Konten-Liste
    var school: School? = nil      // nil: saved before the school search, so the default school
    var id: String { username }

    /// Primär anzuzeigender Name: Spitzname falls vorhanden, sonst Benutzername.
    var title: String {
        if let n = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return username
    }
}

// ── Stundenplan ────────────────────────────────────────────────────────────

struct TimetableEntry: Identifiable, Equatable, Codable {
    var id: Int
    var lessonId: Int
    var date: Int          // YYYYMMDD
    var startTime: Int     // HHMM
    var endTime: Int       // HHMM
    var subjectName: String
    var subjectLong: String
    var teacherName: String
    var teacherLongName: String?
    var roomName: String
    var isExam: Bool
    var isCancelled: Bool
    var isSubstitution: Bool
    var isAdditional: Bool
    var originalSubject: String?
    var originalSubjectLong: String?
    var originalTeacher: String?
    var originalTeacherLong: String?
    var originalRoom: String?
    var note: String?
    var examDescription: String?
}

// ── Noten ──────────────────────────────────────────────────────────────────

struct GradeEntry: Identifiable, Equatable, Codable {
    var id: Int
    var text: String
    var date: Int
    var markName: String
    var markValue: Double
    var markDisplayValue: Double
    var examType: String
}

struct SubjectGrades: Identifiable, Equatable, Codable {
    var id: Int { lessonId }
    var lessonId: Int
    var subjectName: String
    var teacherName: String
    var grades: [GradeEntry]
    var average: Double
    var positiveCount: Int
    var negativeCount: Int
}

// ── Abwesenheiten ──────────────────────────────────────────────────────────

struct AbsenceEntry: Identifiable, Equatable {
    var id: Int
    var startDate: Int
    var endDate: Int
    var startTime: Int
    var endTime: Int
    var isExcused: Bool
    var reasonName: String?
    var absenceType: String?
    var hours: Int
    var note: String?
    var excuseNote: String?
    var teacherName: String?
    var subjectName: String?
}

// ── Abwesenheit melden / entschuldigen ─────────────────────────────────────

struct AbsenceReason: Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
}

/// What WebUntis' own report dialog starts with. Dates YYYYMMDD, times HHMM.
struct AbsenceMeta: Equatable {
    var reasons: [AbsenceReason]
    var defaultReasonId: Int?
    var defaultDate: Int?
    var defaultStartTime: Int?
    var defaultEndTime: Int?
}

/// An excuse sent to the class teachers, found again in "Gesendet". Times are YYYYMMDDHHMM.
struct SentExcuse: Codable, Equatable {
    var start: Int
    var end: Int
    var sentAt: String
    var recipients: [String]
    var messageId: Int?
}

/// How an excuse went out: as a message to the class teachers, or saved on the absence itself
/// when the account may write to no teacher.
struct ExcuseResult: Equatable {
    var viaMessage: Bool
    var sentTo: [String]
    var failed: [String]
    var excuse: SentExcuse?
}

// ── Schuljahr / Ferien ─────────────────────────────────────────────────────

struct SchoolYear: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var startDate: Int   // YYYYMMDD
    var endDate: Int     // YYYYMMDD
}

/// One of the school's breaks: days as YYYY-MM-DD, with the real names WebUntis has for it.
struct SchoolHoliday: Codable, Equatable {
    var start: String
    var end: String
    var names: [String] = []
}

/// getHolidays into the school's breaks. Naming one without a real name ("Ferien3") is the
/// timetable's `SchoolHolidays.key`.
enum HolidayList {
    // "Ferien3", "Feiertag", "8.12.", "25/5/2026": a placeholder, not a name.
    private static func isPlaceholder(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty
            || n.range(of: #"^(ferien|feiertag|holiday|vacanz[ae]|frei)\s*\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || n.range(of: #"^[\d./\s-]+$"#, options: .regularExpression) != nil
    }

    private static func ymd(_ n: Int?) -> String? {
        guard let n, n >= 10_000_000, n <= 99_999_999 else { return nil }
        return String(format: "%04d-%02d-%02d", n / 10000, (n / 100) % 100, n % 100)
    }

    /// getHolidays' result into the breaks from `from` (YYYY-MM-DD) on, overlapping and
    /// adjoining ones merged.
    static func read(_ result: JSON, from: String) -> [SchoolHoliday] {
        let entries = result.array.compactMap { r -> SchoolHoliday? in
            guard let start = ymd(r.startDate.int), let end = ymd(r.endDate.int), end >= start else { return nil }
            var names: [String] = []
            for n in [r.longName.string, r.name.string].compactMap({ $0?.trimmingCharacters(in: .whitespaces) })
            where !isPlaceholder(n) && !names.contains(n) { names.append(n) }
            return SchoolHoliday(start: start, end: end, names: names)
        }
        .filter { $0.end >= from }
        .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
        var merged: [SchoolHoliday] = []
        for h in entries {
            if var last = merged.last, let lastEnd = DateFmt.iso.date(from: last.end),
               let next = Calendar.current.date(byAdding: .day, value: 1, to: lastEnd), h.start <= DateFmt.isoString(next) {
                last.end = max(last.end, h.end)
                for n in h.names where !last.names.contains(n) { last.names.append(n) }
                merged[merged.count - 1] = last
            } else {
                merged.append(h)
            }
        }
        return merged
    }

    /// The break a YYYYMMDD day falls in, if any.
    static func on(_ dayNum: Int, in holidays: [SchoolHoliday]) -> SchoolHoliday? {
        guard let iso = ymd(dayNum) else { return nil }
        return holidays.first { $0.start <= iso && iso <= $0.end }
    }
}

// ── Nachrichten ────────────────────────────────────────────────────────────

struct MessagePreview: Identifiable, Equatable {
    var id: Int
    var subject: String
    var contentPreview: String
    var senderName: String
    var senderId: Int
    var sentDate: String
    var isRead: Bool
    var hasAttachments: Bool
    /// The sender asked this reader to confirm reading (inbox).
    var needsConfirmation = false
    /// How many recipients confirmed reading, of how many were asked (sent).
    var readConfirmed: Int? = nil
    var readTotal: Int? = nil
}

struct MessageDetail: Equatable {
    var id: Int
    var subject: String
    var senderName: String
    var sentDate: String
    var body: String
    var attachments: [MessageAttachment]
}

struct MessageAttachment: Identifiable, Equatable {
    var id: String
    var name: String
    var size: Int
    /// The storage UUID, the only id the MessageCenter's download URL takes.
    var storageId = ""
    /// WebUntis' numeric attachment id, 0 when it only has a storage id.
    var fileId = 0
}

/// A file as it came down: the bytes and the type the server labelled them with.
struct DownloadedAttachment: Equatable {
    var name: String
    var mimeType: String
    var data: Data
}

/// A file picked on the device, to go out with a message.
struct OutgoingAttachment: Equatable {
    var name: String
    var mimeType: String
    var data: Data
}

/// Someone the account may write to. `type` is CLASS_TEACHERS, TEACHERS or OTHERS.
struct MessageRecipient: Identifiable, Equatable, Hashable {
    var id: Int
    var type: String
    var name: String
    var role: String? = nil
    var isClassTeacher = false
}

/// A saved draft to go on with.
struct MessageDraft: Equatable {
    var id: Int
    var subject: String
    var content: String
    var recipients: [MessageRecipient]
}

/// The reply form WebUntis prefills: subject and who it goes back to.
struct ReplyForm: Equatable {
    var subject: String
    var recipientName: String
}

/// Who of a sent message's recipients confirmed reading; a class lists its people.
struct ReadStatusRecipient: Equatable {
    var name: String
    var className: String
    var confirmedAt: String?
    var people: [(name: String, confirmedAt: String?)]

    static func == (a: Self, b: Self) -> Bool {
        a.name == b.name && a.className == b.className && a.confirmedAt == b.confirmedAt
            && a.people.map(\.name) == b.people.map(\.name) && a.people.map(\.confirmedAt) == b.people.map(\.confirmedAt)
    }
}

enum MessageFolder: String, CaseIterable, Identifiable {
    case inbox, sent, drafts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inbox: return "Posteingang"
        case .sent: return "Gesendet"
        case .drafts: return "Entwürfe"
        }
    }
}

// ── Mensa ──────────────────────────────────────────────────────────────────

struct Dish: Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var description: String?
    var category: String
    var date: String
    var imageUrl: String?
    var price: Double?
    var allergens: [String]
    var tags: [String]
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}

struct DishRatingsData: Equatable {
    var ratings: [String: Double]   // Stimmen je Eintrag
    var myRating: Int?
    var average: Double {
        let vals = Array(ratings.values)
        return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
    }
    var count: Int { ratings.count }
}

// ── Klassenbuch ────────────────────────────────────────────────────────────

struct ClassregEvent: Identifiable, Equatable {
    var id: Int
    var subjectName: String
    var creatorName: String
    var createDate: Int   // YYYYMMDD
    var eventReasonName: String
    var categoryName: String
    var text: String
}

// ── Backend: Todos / Erinnerungen / Klasse ─────────────────────────────────

struct ApiTodo: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var details: String
    var dueAt: String?
    var done: Bool
    var doneAt: String?
    var createdAt: String
}

struct ApiReminder: Identifiable, Codable, Equatable {
    var id: String
    var classId: String
    var title: String
    var body: String
    var remindAt: String
    var createdBy: String
    var createdByName: String
    var createdByUsername: String
    var createdAt: String
}

struct ApiClassMember: Codable, Equatable, Identifiable {
    var stableUid: String
    var username: String
    var joinedAt: String?
    var id: String { stableUid }
}

struct ApiClass: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var code: String
    var webuntisKlasseId: Int
    var createdBy: String
    var createdByName: String
    var createdAt: String
    var members: [ApiClassMember]
}

struct ApiComment: Identifiable, Codable, Equatable {
    var id: String
    var stableUid: String
    var username: String
    var body: String
    var createdAt: String
    var updatedAt: String?
}

struct ApiUser: Codable, Equatable {
    var stableUid: String
    var username: String
    var webuntisKlasseId: Int?
    var webuntisKlasseName: String?
    var classId: String?
    var isAdmin: Bool
    /// Account-Rolle: "student" (Standard) oder "parent" (Elternkonto).
    var role: String?
}

// ── Fehler ─────────────────────────────────────────────────────────────────

struct AppError: LocalizedError {
    var message: String
    /// The backend's HTTP status, where it answered.
    var status: Int? = nil
    var errorDescription: String? { message }
    static let sessionExpired = AppError(message: "session_expired")
    var isSessionExpired: Bool { message == Self.sessionExpired.message }
}
