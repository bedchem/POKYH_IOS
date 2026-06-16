import Foundation

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
    var errorDescription: String? { message }
    static let sessionExpired = AppError(message: "session_expired")
}
