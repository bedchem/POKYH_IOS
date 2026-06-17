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
    /// Offline-Modus aktiv (gecachte Daten, Login kam nicht durch).
    @Published var isOffline = false
    @Published var statusText = ""
    @Published var error: String?
    @Published var showAddAccount = false
    @Published var prefillUsername: String?   // vorausgefüllter Benutzername bei Passwort-Neueingabe
    @Published var selectedTab: AppTab = .home
    @Published var backendStatus: BackendStatus = .unknown
    /// Biometrie-Status (Face ID / Touch ID). Wird off-main ermittelt (siehe init),
    /// startet mit einem günstigen Default → kein Hänger beim ersten Render.
    @Published var biometricInfo = Biometric.Info(available: false, typeName: "Code", symbol: "lock.fill")
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
        // Biometrie-Status (erster `canEvaluatePolicy`-Aufruf ist teuer, ~300 ms!)
        // KOMPLETT off-main ermitteln und reaktiv nachreichen → kein Main-Thread-Hänger
        // beim ersten Render (Views lesen `biometricInfo`, nie `Biometric.info` direkt).
        Task.detached(priority: .userInitiated) {
            let info = Biometric.info
            await MainActor.run { self.biometricInfo = info }
        }
    }

    var colorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var isParent: Bool { session?.isParent ?? false }
    var biometricAvailable: Bool { biometricInfo.available }

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
        await performLogin(username: username, password: password, save: false, allowOffline: true)
    }

    // ── Neuer / manueller Login ──────────────────────────────────────────────

    func loginNew(username: String, password: String, save: Bool) async {
        await performLogin(username: username, password: password, save: save)
    }

    /// Zeit, nach der ohne Login-Antwort (kein Internet) in den Offline-Modus
    /// gewechselt wird — sofern ein wiederkehrendes Konto + Cache vorliegt.
    private static let offlineTimeout: Double = 5

    private enum LoginOutcome { case done(UserSession), timedOut, failed(Error) }
    private enum RaceResult: Sendable { case finished, timedOut }

    private func performLogin(username: String, password: String, save: Bool, allowOffline: Bool = false) async {
        // Wurde der Login aus dem „Konto hinzufügen“/„Passwort nötig“-Sheet gestartet?
        // (Dann müssen wir den Sheet-Wechsel sorgfältig sequenzieren – siehe finalize.)
        let viaSheet = showAddAccount
        busy = true; error = nil
        statusText = "Verbinde mit WebUntis…"

        // Offline-Fallback nur für wiederkehrende Konten mit vorhandenem Cache.
        let snap: UserSession? = allowOffline ? Self.offlineCandidate(username: username) : nil
        let loginTask = Task { try await self.buildSession(username: username, password: password) }

        // Ohne Offline-Option: normal auf das Ergebnis warten. Mit Option: 5-s-Rennen.
        let outcome: LoginOutcome
        if snap == nil {
            do { outcome = .done(try await loginTask.value) }
            catch { outcome = .failed(error) }
        } else {
            switch await Self.race(loginTask, timeout: Self.offlineTimeout) {
            case .finished:
                // Login ist durch → Ergebnis (Sitzung oder Fehler) abholen.
                do { outcome = .done(try await loginTask.value) }
                catch { outcome = .failed(error) }
            case .timedOut:
                outcome = .timedOut
            }
        }

        switch outcome {
        case .done(let s):
            await finalize(s, save: save, password: password, viaSheet: viaSheet)
            busy = false; statusText = ""
        case .timedOut:
            // Kein Internet rechtzeitig → Offline-Modus aus dem Snapshot, Login läuft
            // im Hintergrund weiter und „upgradet" die Sitzung bei Erfolg.
            guard let snap else { busy = false; statusText = ""; return }
            enterOffline(snap, viaSheet: viaSheet)
            Task { [weak self] in
                if let s = try? await loginTask.value {
                    await self?.upgradeFromBackground(s, save: save, password: password)
                }
            }
        case .failed(let e):
            // Schneller Netzwerkfehler (z. B. Flugmodus) + Cache → ebenfalls offline.
            if let snap, e is URLError {
                enterOffline(snap, viaSheet: viaSheet)
            } else {
                self.error = (e as? AppError)?.message ?? e.localizedDescription
            }
            busy = false; statusText = ""
        }
    }

    /// Eigentlicher Netzwerk-Login: WebUntis → Fallback POKYH-Backend → Backend-Konto
    /// beziehen. Baut die fertige Sitzung inkl. Tokens und setzt `backendStatus`.
    private func buildSession(username: String, password: String) async throws -> UserSession {
        var s: UserSession
        var backendOnly = false
        do {
            s = try await UntisClient.shared.login(username: username, password: password)
        } catch let untisError {
            // Kein (funktionierendes) WebUntis-Konto? → direkter POKYH-Backend-Login
            // als Fallback (gleiche Zugangsdaten). Das Backend kennt reine POKYH-Konten.
            do {
                let backend = try await BackendClient.shared.login(
                    username: username, password: password)
                s = Self.backendOnlySession(from: backend)
                backendStatus = .connected
                backendOnly = true
            } catch {
                // Beide fehlgeschlagen. Die Backend-Meldung ist für ein POKYH-Konto
                // aussagekräftiger (z. B. „Ungültige Zugangsdaten"); bei einem reinen
                // Netzwerkfehler den ursprünglichen WebUntis-Fehler durchreichen.
                throw (error is URLError) ? untisError : error
            }
        }
        // POKYH-Konto für Schüler- UND Elternkonten beziehen/anlegen (kein
        // Lehrer-/Adminkonto). Eltern bekommen ein Elternkonto (role=parent):
        // eigene Todos, sehen nur den Klassennamen, keine Erinnerungen,
        // unsichtbares Mitglied. Die klasseId ist bei Eltern die des Kindes
        // (in UntisClient aufgelöst). Das Backend legt das Konto automatisch an.
        // Reine Backend-Konten (Fallback) haben ihre Tokens bereits.
        if !backendOnly {
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
        }
        return s
    }

    /// Abschluss eines erfolgreichen Online-Logins: Konto sichern, Offline-Snapshot
    /// persistieren, Sitzung übernehmen (mit sorgfältiger Sheet-Sequenzierung).
    private func finalize(_ s: UserSession, save: Bool, password: String, viaSheet: Bool) async {
        // Konto + Passwort sichern, BEVOR die Session getauscht wird, damit es
        // auch dann lokal gespeichert ist, wenn der View-Wechsel dazwischenkommt.
        if save {
            let account = SavedAccount(
                username: s.username,
                displayName: s.klasseName.isEmpty ? s.username : s.klasseName,
                imageUrl: s.imageUrl)
            store.save(account, password: password)
        }
        store.lastActive = s.username
        // Profilbild auch beim stillen Login (save:false) nachtragen → Konten-Liste
        // & Sperrbildschirm zeigen das gecachte Bild.
        store.updateImageUrl(s.imageUrl, for: s.username)
        accounts = store.accounts
        // Token-losen Snapshot für späteren Offline-Restore ablegen.
        if s.hasUntis { DiskCache.save(Self.offlineSnapshot(s), key: Self.sessionKey(s.username)) }

        if viaSheet {
            // Bereits eingeloggt + Login lief über ein Sheet (Konto hinzufügen /
            // Passwort-Neueingabe): ERST das Sheet schließen und die Dismiss-
            // Animation abwarten, DANN die Session tauschen. Sonst kollidiert der
            // View-Identitätswechsel (ContentView: `RootTabView().id(username)`)
            // mit der noch laufenden Sheet-Animation → das Modal hängt auf echten
            // Geräten („nichts passiert / lässt sich nicht schließen“).
            showAddAccount = false
            busy = false; statusText = ""
            try? await Task.sleep(for: .milliseconds(420))
        }
        session = s
        phase = .authed
        showAddAccount = false
        isOffline = false
        onAuthenticated()
    }

    /// Wechselt in den Offline-Modus: gecachte (token-lose) Sitzung anzeigen.
    private func enterOffline(_ snap: UserSession, viaSheet: Bool) {
        busy = false; statusText = ""
        if viaSheet { showAddAccount = false }
        session = snap
        phase = .authed
        isOffline = true
        store.lastActive = snap.username
    }

    /// Hintergrund-Login nach Offline-Restore erfolgreich → Sitzung „upgraden".
    private func upgradeFromBackground(_ s: UserSession, save: Bool, password: String) async {
        guard session?.username == s.username else { return }   // Konto noch aktiv?
        if save {
            let account = SavedAccount(
                username: s.username,
                displayName: s.klasseName.isEmpty ? s.username : s.klasseName,
                imageUrl: s.imageUrl)
            store.save(account, password: password)
            accounts = store.accounts
        }
        if s.hasUntis { DiskCache.save(Self.offlineSnapshot(s), key: Self.sessionKey(s.username)) }
        withAnimation(.easeInOut(duration: 0.3)) {
            session = s
            isOffline = false
        }
        onAuthenticated()
    }

    // ── Offline-Helfer ────────────────────────────────────────────────────────

    private static func sessionKey(_ username: String) -> String {
        "session-\(username.lowercased())"
    }

    /// Liefert einen Offline-Snapshot nur, wenn ein WebUntis-Konto gecacht ist
    /// (`studentId > 0` → Stundenplan-Cache kann gelesen werden).
    private static func offlineCandidate(username: String) -> UserSession? {
        guard let snap = DiskCache.load(UserSession.self, key: sessionKey(username)),
              snap.studentId > 0 else { return nil }
        return snap
    }

    /// Rennen: ist der Login durch oder läuft die Zeit ab? Der Login-Task läuft bei
    /// Timeout weiter (nur die Warte-Tasks werden abgebrochen).
    private static func race(_ task: Task<UserSession, Error>, timeout: Double) async -> RaceResult {
        await withTaskGroup(of: RaceResult.self) { group in
            group.addTask {
                _ = try? await task.value
                return .finished
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    /// Baut eine reine POKYH-Backend-Sitzung (kein WebUntis): nur API-Tokens +
    /// Stammdaten, WebUntis-Felder bleiben neutral → `hasUntis == false`.
    private static func backendOnlySession(
        from backend: (token: String, refresh: String, user: ApiUser)) -> UserSession {
        var s = UserSession(
            sessionId: "", bearerToken: "", studentId: 0,
            klasseId: 0, klasseName: backend.user.webuntisKlasseName ?? "",
            username: backend.user.username,
            personName: nil, personType: nil,
            isParent: backend.user.role == "parent")
        s.apiToken = backend.token
        s.apiRefresh = backend.refresh
        s.stableUid = backend.user.stableUid
        s.classId = backend.user.classId
        return s
    }

    /// Token-loser Sitzungs-Snapshot für den Offline-Restore. Enthält NUR
    /// nicht-sensible Anzeige-/Cache-Schlüssel-Felder — niemals Tokens/Cookies.
    /// Die kommen beim echten Re-Login zurück; offline brauchen wir nur die
    /// Cache-Keys (`studentId`) + Anzeigedaten.
    private static func offlineSnapshot(_ s: UserSession) -> UserSession {
        UserSession(
            sessionId: "", bearerToken: "", studentId: s.studentId,
            klasseId: s.klasseId, klasseName: s.klasseName, username: s.username,
            personName: s.personName, personType: s.personType, isParent: s.isParent,
            apiToken: nil, apiRefresh: nil, stableUid: nil, classId: nil,
            imageUrl: s.imageUrl)
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
        if biometricInfo.available {
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
            isOffline = false
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
            isOffline = false
            phase = accounts.isEmpty ? .login : .lock
        }
    }

    func logout() {
        session = nil
        isOffline = false
        phase = accounts.isEmpty ? .login : .lock
    }

    /// „Cache & Daten löschen": entfernt ALLES Gespeicherte/Gecachte vom Gerät —
    /// Anmeldedaten (Keychain), Offline-Stundenplan/Noten, geteilte Widget-Snapshots,
    /// In-Memory-Caches und alle App-Einstellungen. Danach: zurück zum Login.
    func clearAllData() {
        // 1. In-Memory-Caches
        UntisClient.shared.clearCaches()
        BackendClient.shared.clearCaches()
        ImageCache.purge()
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
        isOffline = false
        accounts = []
        backendStatus = .unknown
        themeMode = .system
        phase = .login
    }

    func handleSessionExpired() {
        session = nil
        isOffline = false
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
