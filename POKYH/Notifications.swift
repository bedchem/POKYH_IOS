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
}
