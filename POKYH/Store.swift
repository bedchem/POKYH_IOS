import SwiftUI
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Zentraler App-Zustand: Phasen (Sperre / Login / angemeldet), Mehrbenutzer,
/// Face-ID-Entsperrung. Passwörter liegen im Keychain, nicht im Klartext.
/// Bottom-Navigation-Tabs (top-level `nonisolated` → sichere Hashable-Vergleiche).
nonisolated enum AppTab: Hashable { case home, timetable, school, noten, mensa }

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

/// Status der POKYH-Backend-Verbindung (Todos/Erinnerungen/Klasse) — für die
/// Diagnose im Profil sichtbar gemacht.
enum BackendStatus: Equatable {
    case unknown
    case connected
    case notStudent        // kein Schülerkonto → bewusst kein POKYH-Konto
    case noClass           // Schüler ohne auflösbare klasseId
    case failed(String)    // Backend-Fehler (Statuscode/Meldung)

    var label: String {
        switch self {
        case .unknown:    return "Unbekannt"
        case .connected:  return "Verbunden"
        case .notStudent: return "Nur für Schülerkonten"
        case .noClass:    return "Keine Klasse gefunden"
        case .failed(let m): return "Nicht verbunden – \(m)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    enum Phase { case lock, login, authed }

    @Published var phase: Phase
    @Published var session: UserSession?
    @Published var accounts: [SavedAccount]
    @Published var busy = false
    @Published var statusText = ""
    @Published var error: String?
    @Published var showAddAccount = false
    @Published var prefillUsername: String?   // vorausgefüllter Benutzername bei Passwort-Neueingabe
    @Published var selectedTab: AppTab = .home
    @Published var backendStatus: BackendStatus = .unknown
    /// Erhöht sich, wenn der Stundenplan-Tab angetippt wird → Ansicht springt auf „heute".
    @Published var timetableHomeSignal = 0
    @Published var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "pokyh_theme") }
    }

    private let store = CredentialStore.shared

    init() {
        accounts = store.accounts
        phase = store.accounts.isEmpty ? .login : .lock
        let raw = UserDefaults.standard.string(forKey: "pokyh_theme") ?? ThemeMode.system.rawValue
        themeMode = ThemeMode(rawValue: raw) ?? .system
    }

    var colorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var isParent: Bool { session?.isParent ?? false }
    var biometricAvailable: Bool { Biometric.available }

    // ── Standard-Konto (Einstellungen) ───────────────────────────────────────
    var defaultUsername: String? {
        get { store.defaultUsername }
        set { store.defaultUsername = newValue; objectWillChange.send() }
    }

    // ── Sperrbildschirm: Face ID → automatischer Login ───────────────────────
    /// Gibt zurück, ob die biometrische Prüfung erfolgreich war (für Fehlversuch-Zählung).
    @discardableResult
    func unlock(into username: String? = nil) async -> Bool {
        error = nil
        let target = username ?? store.defaultUsername ?? accounts.first?.username
        guard let target else { phase = .login; return false }
        let ok = await Biometric.authenticate(reason: "Entsperre POKYH, um dich anzumelden.")
        guard ok else { error = nil; return false }
        store.lastActive = target
        await loginSaved(username: target)
        return session != nil
    }

    func loginSaved(username: String) async {
        guard let password = store.password(for: username) else {
            // Kein Passwort gespeichert (abgemeldet) → Passwort-Neueingabe anbieten.
            prefillUsername = username
            showAddAccount = true
            return
        }
        await performLogin(username: username, password: password, save: false)
    }

    // ── Neuer / manueller Login ──────────────────────────────────────────────

    func loginNew(username: String, password: String, save: Bool) async {
        await performLogin(username: username, password: password, save: save)
    }

    private func performLogin(username: String, password: String, save: Bool) async {
        busy = true; error = nil
        statusText = "Verbinde mit WebUntis…"
        defer { busy = false; statusText = "" }
        do {
            var s = try await UntisClient.shared.login(username: username, password: password)
            statusText = "Lade Konto…"
            // POKYH-Konto für Schüler- UND Elternkonten beziehen/anlegen (kein
            // Lehrer-/Adminkonto). Eltern bekommen ein Elternkonto (role=parent):
            // eigene Todos, sehen nur den Klassennamen, keine Erinnerungen,
            // unsichtbares Mitglied. Die klasseId ist bei Eltern die des Kindes
            // (in UntisClient aufgelöst). Das Backend legt das Konto automatisch an.
            if s.isStudent || s.isParent {
                let role = s.isParent ? "parent" : "student"
                switch await BackendClient.shared.loginWithUntis(
                    username: s.username, klasseId: s.klasseId, klasseName: s.klasseName, role: role) {
                case .ok(let token, let refresh):
                    s.apiToken = token
                    s.apiRefresh = refresh
                    if let user = try? await BackendClient.shared.me(token: token) {
                        s.stableUid = user.stableUid
                        s.classId = user.classId
                    }
                    backendStatus = .connected
                case .noClass:
                    backendStatus = .noClass
                case .failed(let msg):
                    backendStatus = .failed(msg)
                }
            } else {
                backendStatus = .notStudent
            }
            session = s
            if save {
                let account = SavedAccount(
                    username: s.username,
                    displayName: s.klasseName.isEmpty ? s.username : s.klasseName)
                store.save(account, password: password)
            }
            store.lastActive = s.username
            accounts = store.accounts
            phase = .authed
            showAddAccount = false
            onAuthenticated()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
            if phase == .lock { /* bleibe im Sperrbildschirm */ }
        }
    }

    // ── Kontowechsel / -verwaltung ───────────────────────────────────────────

    /// Sauberer Wechsel mit Face-ID-Bestätigung + Loading (über `busy`).
    func switchAccount(username: String) async {
        guard username != session?.username else { return }
        // Ohne gespeichertes Passwort → direkt Passwort-Neueingabe (kein Face ID nötig).
        guard store.hasPassword(username) else {
            prefillUsername = username; showAddAccount = true; return
        }
        busy = true; statusText = "Bestätige Identität…"
        if Biometric.available {
            let ok = await Biometric.authenticate(reason: "Kontowechsel zu \(username) bestätigen.")
            guard ok else { busy = false; statusText = ""; return }
        }
        await loginSaved(username: username)
    }

    func accountHasPassword(_ username: String) -> Bool { store.hasPassword(username) }

    /// Widgets/Live Activity zeigen die Daten des **Standard-Kontos**. Ist kein
    /// Standard gesetzt, zählt das aktive Konto (Einzelnutzer-Fall).
    var isDefaultAccountActive: Bool {
        guard let active = session?.username else { return false }
        return store.defaultUsername == nil || store.defaultUsername == active
    }

    /// Live Activity (laufende/nächste Stunde) anhand des Stundenplans aktualisieren.
    func refreshLiveActivity(from entries: [TimetableEntry]) {
        guard let s = session else { return }
        LiveActivityManager.refresh(from: entries, className: s.klasseName)
    }

    /// Lokalen Spitznamen für ein Konto setzen/zurücksetzen (leer → zurücksetzen).
    func setNickname(_ nickname: String?, for username: String) {
        store.setNickname(nickname, for: username)
        accounts = store.accounts
    }

    /// Konto neu laden: WebUntis-Re-Login, um Name/Klasse zu aktualisieren.
    /// - Aktives Konto → volle Sitzung + Backend-Status werden erneuert.
    /// - Anderes Konto → nur Metadaten (Klasse) im Hintergrund, aktive Sitzung bleibt
    ///   unberührt (eigene ephemere Cookies pro Sitzung).
    /// Ohne gespeichertes Passwort → Passwort-Neueingabe anbieten.
    func refreshAccount(username: String) async {
        guard store.hasPassword(username), let password = store.password(for: username) else {
            prefillUsername = username; showAddAccount = true; return
        }
        if session?.username == username {
            // performLogin(save: true) erneuert Sitzung + aktualisiert Anzeigenamen/Keychain.
            await performLogin(username: username, password: password, save: true)
        } else {
            busy = true; statusText = "Aktualisiere \(username)…"
            defer { busy = false; statusText = "" }
            if let s = try? await UntisClient.shared.login(username: username, password: password) {
                store.updateDisplayName(s.klasseName.isEmpty ? s.username : s.klasseName, for: username)
                accounts = store.accounts
            } else {
                error = "Aktualisieren von \(username) fehlgeschlagen."
            }
        }
    }

    /// Abmelden: nur das Passwort entfernen — Konto bleibt gespeichert.
    func signOutAccount(username: String) {
        store.signOut(username)
        accounts = store.accounts
        if session?.username == username {
            session = nil
            phase = accounts.isEmpty ? .login : .lock
        }
        objectWillChange.send()
    }

    /// Konto komplett vom Gerät entfernen.
    func removeAccount(username: String) {
        store.remove(username)
        accounts = store.accounts
        if session?.username == username {
            session = nil
            phase = accounts.isEmpty ? .login : .lock
        }
    }

    func logout() {
        session = nil
        phase = accounts.isEmpty ? .login : .lock
    }

    /// „Cache & Daten löschen": entfernt ALLES Gespeicherte/Gecachte vom Gerät —
    /// Anmeldedaten (Keychain), Offline-Stundenplan/Noten, geteilte Widget-Snapshots,
    /// In-Memory-Caches und alle App-Einstellungen. Danach: zurück zum Login.
    func clearAllData() {
        // 1. In-Memory-Caches
        UntisClient.shared.clearCaches()
        BackendClient.shared.clearCaches()
        // 2. Keychain (alle Passwörter + Master-Key)
        Keychain.purgeAll()
        // 3. Offline-Disk-Cache + geteilte Snapshots (App Group)
        DiskCache.purge()
        SharedStore.purgeAll()
        // 4. Alle eigenen UserDefaults-Schlüssel (kein Hardcoding einzelner Keys)
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pokyh_") {
            defaults.removeObject(forKey: key)
        }
        // 5. Live Activity beenden + Widgets leeren
        LiveActivityManager.endAll()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        // 6. Zustand zurücksetzen → Login
        session = nil
        accounts = []
        backendStatus = .unknown
        themeMode = .system
        phase = .login
    }

    func handleSessionExpired() {
        session = nil
        phase = accounts.isEmpty ? .login : .lock
    }

    // ── Auto-Sperre nach Inaktivität im Hintergrund ───────────────────────────
    /// Nach so langer Zeit im Hintergrund wird automatisch gesperrt (Face-ID-Login
    /// nötig). 10 Minuten — übliche Größenordnung für sensible Apps.
    private let autoLockInterval: TimeInterval = 600
    private var backgroundedAt: Date?

    func appDidEnterBackground() {
        backgroundedAt = (phase == .authed) ? Date() : nil
    }

    func appDidBecomeActive() {
        defer { backgroundedAt = nil }
        guard phase == .authed, let since = backgroundedAt,
              Date().timeIntervalSince(since) >= autoLockInterval else { return }
        // Zu lange weg → ausloggen und zum Sperr-/Login-Bildschirm.
        handleSessionExpired()
    }

    // ── Nach erfolgreichem Login: Benachrichtigungen einrichten ───────────────
    // Bewusst NICHT beim App-Start (Login-Screen) — das löste auf echter Hardware
    // einen Laufzeit-Abbruch aus. Hier ist die UI bereits aktiv → sicher.
    func onAuthenticated() {
        NotificationManager.shared.configure()
        requestNotificationPermissionIfNeeded()
        Task { await syncNotifications() }
    }

    private func requestNotificationPermissionIfNeeded() {
        let key = "pokyh_notif_asked"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        // Leere Completion → keine Actor-/Thread-Probleme.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // ── Benachrichtigungen synchronisieren (Nachrichten + Erinnerungen) ───────
    private var lastNotifSync = Date.distantPast
    // Eigener, längerer Throttle für die teureren Abrufe (Noten/Stundenplan):
    // Noten lädt pro Fach – das ist zu schwer für den 60-s-Takt der Nachrichten.
    private var lastHeavySync = Date.distantPast
    private let heavySyncInterval: TimeInterval = 1800   // 30 min

    func syncNotifications() async {
        guard let s = session else { return }
        // Throttle (Performance): höchstens alle 60 s.
        guard Date().timeIntervalSince(lastNotifSync) > 60 else { return }
        lastNotifSync = Date()

        if let inbox = try? await UntisClient.shared.messages(folder: .inbox, s) {
            NotificationManager.shared.checkNewMessages(inbox)
            if isDefaultAccountActive { WidgetBridge.publishMessages(inbox) }   // nur Standard-Konto
        }
        if let token = s.apiToken, let classId = s.classId,
           let reminders = try? await BackendClient.shared.reminders(classId: classId, token: token) {
            NotificationManager.shared.scheduleReminders(reminders)
        }

        // Teurere Checks seltener: neue Noten + Stundenausfälle.
        if Date().timeIntervalSince(lastHeavySync) > heavySyncInterval {
            lastHeavySync = Date()
            await syncGradeAndTimetableAlerts(s)
        }
    }

    /// Neue Noten und Stundenausfälle erkennen → lokale Benachrichtigungen.
    /// Nur für Schülerkonten sinnvoll (Eltern/Lehrer haben keinen MY_TIMETABLE-Notenkontext).
    private func syncGradeAndTimetableAlerts(_ s: UserSession) async {
        if s.isStudent, let subjects = try? await UntisClient.shared.grades(year: nil, s) {
            NotificationManager.shared.checkNewGrades(subjects)
            if isDefaultAccountActive { WidgetBridge.publishGrades(subjects) }   // nur Standard-Konto
        }
        // Stundenplan ab heute (Client liefert Mo–Sa) → kommende Ausfälle.
        if let entries = try? await UntisClient.shared.timetable(date: SchoolDates.todayISO(), s) {
            NotificationManager.shared.checkTimetableChanges(entries)
        }
    }
}
