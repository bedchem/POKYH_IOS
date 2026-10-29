import Foundation
import UserNotifications

/// Benachrichtigungen — bewusst `nonisolated` + Completion-Handler (kein async,
/// kein @MainActor): die UNUserNotificationCenter-Callbacks laufen auf beliebigen
/// Threads; unter projektweiter MainActor-Isolation würde async/@MainActor sonst
/// einen Actor-Laufzeit-Abbruch auslösen.
nonisolated final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let seenKey = "pokyh_seen_message_ids"
    private let seenGradesKey = "pokyh_seen_grade_ids"
    private let seenCancelKey = "pokyh_seen_cancelled_lessons"
    private let askedKey = "pokyh_notif_asked"

    func configure() {
        center.delegate = self
    }

    /// Beim ersten Start die Berechtigung anfragen (System-Dialog erscheint einmal).
    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UserDefaults.standard.set(true, forKey: askedKey)
    }

    // Banner auch im Vordergrund anzeigen.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // ── Erinnerungen → geplante lokale Notifications (feuern auch geschlossen) ──
    func scheduleReminders(_ reminders: [ApiReminder]) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let stale = reqs.filter { $0.identifier.hasPrefix("reminder-") }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale)
        }
        let now = Date()
        for r in reminders {
            guard let date = MessageFormat.parse(r.remindAt), date > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body.isEmpty ? "Klassen-Erinnerung" : r.body
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "reminder-\(r.id)", content: content, trigger: trigger))
        }
    }

    // ── Neue Nachrichten erkennen → Hinweis ────────────────────────────────────
    func checkNewMessages(_ messages: [MessagePreview]) {
        let unread = messages.filter { !$0.isRead }
        let stored = UserDefaults.standard.array(forKey: seenKey) as? [Int] ?? []
        let seen = Set(stored)
        if !stored.isEmpty {
            for m in unread where !seen.contains(m.id) {
                let content = UNMutableNotificationContent()
                content.title = "Neue Nachricht"
                content.body = m.subject.isEmpty ? m.senderName : "\(m.senderName): \(m.subject)"
                content.sound = .default
                center.add(UNNotificationRequest(identifier: "msg-\(m.id)", content: content, trigger: nil))
            }
        }
        UserDefaults.standard.set(Array(seen.union(messages.map { $0.id })), forKey: seenKey)
        center.setBadgeCount(unread.count)
    }

    // ── Neue Noten erkennen → Hinweis ──────────────────────────────────────────
    /// Beim ersten Lauf wird nur der Bestand gemerkt (kein Nachschlag für Alt-Noten);
    /// danach feuert jede neu hinzugekommene Note eine Benachrichtigung.
    func checkNewGrades(_ subjects: [SubjectGrades]) {
        let pairs: [(subject: String, grade: GradeEntry)] = subjects.flatMap { s in
            s.grades.filter { $0.markDisplayValue > 0 }.map { (s.subjectName, $0) }
        }
        let stored = UserDefaults.standard.array(forKey: seenGradesKey) as? [Int] ?? []
        let seen = Set(stored)
        if !stored.isEmpty {
            for p in pairs where !seen.contains(p.grade.id) {
                let content = UNMutableNotificationContent()
                content.title = "Neue Note"
                content.body = "\(p.subject): \(Self.fmtMark(p.grade.markDisplayValue))"
                content.sound = .default
                center.add(UNNotificationRequest(identifier: "grade-\(p.grade.id)", content: content, trigger: nil))
            }
        }
        UserDefaults.standard.set(Array(seen.union(pairs.map { $0.grade.id })), forKey: seenGradesKey)
    }

    // ── Stundenausfälle erkennen → Hinweis ─────────────────────────────────────
    /// Nur künftige/heutige entfallende Stunden; jeder Ausfall meldet sich einmal.
    func checkTimetableChanges(_ entries: [TimetableEntry]) {
        let todayNum = Int(Self.dateNum(Date()))
        let cancelled = entries.filter { $0.isCancelled && $0.date >= todayNum }
        let stored = UserDefaults.standard.array(forKey: seenCancelKey) as? [String] ?? []
        let seen = Set(stored)
        func key(_ e: TimetableEntry) -> String { "\(e.date)-\(e.startTime)-\(e.lessonId)" }
        if !stored.isEmpty {
            for e in cancelled where !seen.contains(key(e)) {
                let content = UNMutableNotificationContent()
                content.title = "Stunde fällt aus"
                content.body = "\(e.subjectName) am \(Self.fmtDate(e.date)) um \(Self.fmtTime(e.startTime)) entfällt."
                content.sound = .default
                center.add(UNNotificationRequest(identifier: "cancel-\(key(e))", content: content, trigger: nil))
            }
        }
        // Bestand zusammenführen; alte (vergangene) Keys mitzunehmen ist unkritisch,
        // da der Bestand klein bleibt und Vergangenes nie erneut feuert.
        UserDefaults.standard.set(Array(seen.union(cancelled.map(key))), forKey: seenCancelKey)
    }

    // ── kleine, lokale Formatierer (keine teuren DateFormatter im Hot-Path) ─────
    private static func fmtMark(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100          // auf 2 Stellen runden
        if r == r.rounded() { return String(Int(r)) }   // ganze Zahl → "8"
        var str = String(format: "%.2f", r)             // sonst Null-Endungen kappen
        while str.hasSuffix("0") { str.removeLast() }
        if str.hasSuffix(".") { str.removeLast() }
        return str.replacingOccurrences(of: ".", with: ",")  // deutsche Schreibweise
    }
    /// "HHMM" (Int) → "HH:MM".
    private static func fmtTime(_ hhmm: Int) -> String {
        String(format: "%02d:%02d", hhmm / 100, hhmm % 100)
    }
    /// "YYYYMMDD" (Int) → "DD.MM.".
    private static func fmtDate(_ yyyymmdd: Int) -> String {
        let mm = (yyyymmdd / 100) % 100, dd = yyyymmdd % 100
        return String(format: "%02d.%02d.", dd, mm)
    }
    private static func dateNum(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }
}
