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
    /// WebUntis' own first name for the person, when it says it apart; Home greets with it.
    var firstName: String? = nil
    var personType: Int?
    var isParent: Bool
    /// POKYH backend tokens (to-dos, reminders, class).
    var apiToken: String?
    var apiRefresh: String?
    var stableUid: String?
    var classId: String?
    /// The picture's URL from WebUntis' app data (`user.person.imageUrl`).
    var imageUrl: String?
    /// The WebUntis school the account signs in at; nil for accounts from before the school search.
    var school: School? = nil
    /// Kept in the offline copy, which has no token: the account has a POKYH account, so its
    /// to-dos, reminders and class show from what's stored.
    var backendLinked: Bool? = nil

    var schoolRef: School { school ?? .fallback }

    /// To-dos, reminders and class: live with a token, from the stored copy offline.
    var hasBackend: Bool { apiToken != nil || backendLinked == true }

    /// Whether a WebUntis account is behind this session (timetable, grades). POKYH-only
    /// accounts have `studentId == 0`. True for the token-less offline session too, which
    /// reads the timetable from disk.
    var hasUntis: Bool { studentId > 0 }

    /// WebUntis `personType` 5 is a student; guardians are left out. Without a `personType`,
    /// a class of one's own (klasseId > 0, not a guardian) counts as a student.
    var isStudent: Bool {
        if isParent { return false }
        if let t = personType { return t == 5 }
        return klasseId > 0
    }
}

// ── Gespeicherte Konten (Mehrbenutzer + Face ID) ───────────────────────────

struct SavedAccount: Codable, Equatable, Identifiable {
    var username: String           // the id and the Keychain key
    var displayName: String        // class name, else the user name
    var nickname: String?          // optionaler, lokal vergebener Spitzname
    var imageUrl: String?          // WebUntis profile picture, for the list of accounts
    var school: School? = nil      // nil: saved before the school search, so the default school
    var id: String { username }

    /// The name to show: the nickname if there is one, else the username.
    var title: String {
        if let n = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return username
    }
}

// ── Timetable ──────────────────────────────────────────────────────────────

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
    // What changed on this occurrence and what's noted on it. Optional: copies on disk from
    // older builds have none of these and still have to decode.
    var addedTeachers: [String]? = nil
    var addedSubjects: [String]? = nil
    var addedRooms: [String]? = nil
    var icons: [String]? = nil
    var substitutionText: String? = nil
    var lessonText: String? = nil
    var texts: [PeriodText]? = nil
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

struct AbsenceEntry: Identifiable, Equatable, Codable, AbsenceSpan {
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

// ── Nachrichten ────────────────────────────────────────────────────────────

struct MessagePreview: Identifiable, Equatable, Codable {
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

struct MessageDetail: Equatable, Codable {
    var id: Int
    var subject: String
    var senderName: String
    var sentDate: String
    var body: String
    var attachments: [MessageAttachment]
}

struct MessageAttachment: Identifiable, Equatable, Codable {
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
struct OutgoingAttachment: Equatable, Identifiable {
    let id = UUID()
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
    func label(_ s: MessagesStrings) -> String {
        switch self {
        case .inbox: s.inbox
        case .sent: s.sent
        case .drafts: s.drafts
        }
    }
}

// ── Mensa ──────────────────────────────────────────────────────────────────

struct Dish: Identifiable, Equatable, Hashable, Codable {
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

struct ClassregEvent: Identifiable, Equatable, Codable, ClassregRecord {
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
    /// The account's role: "student" (the default) or "parent" (a guardian).
    var role: String?
    /// Why the account has no class (the backend's ClassNote, e.g. "no_class_found"); nil with one.
    var classNote: String? = nil
    /// The class waits for its check at the next sign-in (new rules on the server).
    var classCheckPending: Bool? = nil
}

// ── Fehler ─────────────────────────────────────────────────────────────────

struct AppError: LocalizedError {
    var message: String
    /// The backend's HTTP status, where it answered.
    var status: Int? = nil
    /// Set when these credentials won't sign in again as they are, so a stored copy is no use.
    var refusal: Refusal? = nil
    var errorDescription: String? { message }

    enum Refusal: Equatable {
        /// WebUntis turned the password or app key down (and POKYH too, for an account of its own).
        case wrongCredentials
        /// This device was signed out from another one; the backend won't renew it.
        case signedOutElsewhere
    }
    static let sessionExpired = AppError(message: "session_expired")
    var isSessionExpired: Bool { message == Self.sessionExpired.message }
}
