import SwiftUI
import Combine
import LocalAuthentication
import PokyhCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Zentraler App-Zustand: Phasen (Sperre / Login / angemeldet), Mehrbenutzer,
/// Face-ID-Entsperrung. Passwörter liegen im Keychain hinter Face ID, nicht im Klartext.
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
    @Published var session: UserSession? {
        // Ein anderes Konto (oder abgemeldet): dessen Hinweis gilt nicht mehr.
        didSet { if session?.username != privacyNotice?.username { privacyNotice = nil } }
    }
    /// Die Datenschutzerklärung, die gerade bestätigt werden soll (siehe PrivacyNotice.swift).
    @Published var privacyNotice: PrivacyNoticePrompt?
    @Published var accounts: [SavedAccount]
    @Published var busy = false
    /// Offline-Modus aktiv (gecachte Daten, Login kam nicht durch).
    @Published var isOffline = false
    @Published var statusText = ""
    @Published var error: String?
    @Published var showAddAccount = false
    @Published var prefillUsername: String?   // vorausgefüllter Benutzername bei Passwort-Neueingabe
    @Published var selectedTab: AppTab = .home {
        didSet { if selectedTab != oldValue { UsageReporter.shared.noteScreen() } }
    }
    @Published var backendStatus: BackendStatus = .unknown
    /// Unread inbox messages, for the badges. Refreshed with the notification sync.
    @Published var unreadMessages = 0
    /// Biometrie-Status (Face ID / Touch ID). Wird off-main ermittelt (siehe init),
    /// startet mit einem günstigen Default → kein Hänger beim ersten Render.
    @Published var biometricInfo = Biometric.Info.unknown
    /// Erhöht sich, wenn der Stundenplan-Tab angetippt wird → Ansicht springt auf „heute".
    @Published var timetableHomeSignal = 0
    @Published var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "pokyh_theme") }
    }
    /// The Face ID / passcode sheet is up. It makes the app inactive, which must not bring up
    /// the privacy cover over it.
    @Published private(set) var authenticating = false
    /// Hides the app in the app switcher and whenever it isn't the active app.
    @Published private(set) var privacyCover = false

    private let store = CredentialStore.shared
    private var unlockText: UnlockStrings { .of(Strings.current.lang) }
    /// The lock screen tries Face ID by itself on launch and after the auto-lock, not right
    /// after someone signed out on purpose.
    private var autoUnlockArmed = true
    /// Goes up with every lock, so a sign-in still running from before can't open the app again.
    private var lockEpoch = 0

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
        BackgroundRefresh.liveSession = { [weak self] in self?.sessionForBackgroundWork() }
        BackendClient.shared.tokenRenewal = { [weak self] in await self?.renewBackendToken(expired: $0) }
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

    /// Whether the lock screen should try Face ID by itself this time.
    func consumeAutoUnlock() -> Bool {
        defer { autoUnlockArmed = true }
        return autoUnlockArmed
    }

    /// One Face ID / passcode check covers the unlock and reading the password behind it.
    /// Returns whether the app is signed in afterwards.
    @discardableResult
    func unlock(into username: String? = nil) async -> Bool {
        error = nil
        let target = username ?? store.defaultUsername ?? accounts.first?.username
        guard let target else { phase = .login; return false }
        guard store.hasPassword(target) else {
            // Signed out: tapping the account asks for its password, the automatic try doesn't.
            if username != nil { askForPassword(target) }
            return false
        }
        guard let ctx = await authenticate(reason: unlockText.unlockReason) else { return false }
        UnlockSession.begin(ctx)
        store.lastActive = target
        await loginSaved(username: target, context: ctx)
        if session == nil { UnlockSession.end() }
        return session != nil
    }

    private func loginSaved(username: String, context: LAContext) async {
        guard let password = store.password(for: username, context: context) else {
            // Nothing readable behind the check: ask for the password again.
            askForPassword(username)
            return
        }
        await performLogin(username: username, password: password, save: false, allowOffline: true)
    }

    private func askForPassword(_ username: String) {
        busy = false; statusText = ""
        prefillUsername = username
        showAddAccount = true
    }

    private func authenticate(reason: String) async -> LAContext? {
        authenticating = true
        defer { authenticating = false }
        return await Biometric.authenticate(reason: reason)
    }

    /// A saved password: without asking while the app is unlocked, otherwise after one more check.
    private func savedPassword(for username: String) async -> String? {
        if let password = store.password(for: username, context: UnlockSession.context) { return password }
        guard let ctx = await authenticate(reason: unlockText.confirmReason) else { return nil }
        UnlockSession.begin(ctx)
        return store.password(for: username, context: ctx)
    }

    // ── Neuer / manueller Login ──────────────────────────────────────────────

    /// The school picked on the sign-in screen, for the sign-in under way only: a failed one at
    /// the wrong school must not stick to later silent or Face ID re-logins.
    private var loginSchool: (username: String, school: School)?

    /// Where `username` signs in: the school just picked, the saved account's, or the fallback.
    func school(for username: String) -> School {
        if let pick = loginSchool, pick.username.caseInsensitiveCompare(username) == .orderedSame { return pick.school }
        return accounts.first { $0.username.caseInsensitiveCompare(username) == .orderedSame }?.school ?? .fallback
    }

    func loginNew(username: String, password: String, save: Bool, school: School? = nil) async {
        loginSchool = school.map { (username.trimmingCharacters(in: .whitespaces).lowercased(), $0) }
        await performLogin(username: username, password: password, save: save, fresh: true)
        loginSchool = nil
    }

    /// Called when messages were opened or marked read, so the badge drops at once.
    func messageWasRead(count: Int = 1) {
        unreadMessages = max(0, unreadMessages - count)
    }

    /// Zeit, nach der ohne Login-Antwort (kein Internet) in den Offline-Modus
    /// gewechselt wird — sofern ein wiederkehrendes Konto + Cache vorliegt.
    private static let offlineTimeout: Double = 5

    private enum LoginOutcome { case done(UserSession), timedOut, failed(Error) }
    private enum RaceResult: Sendable { case finished, timedOut }

    /// `fresh`: Zugangsdaten gerade eingegeben, nicht aus dem Schlüsselbund (erste Anmeldung).
    private func performLogin(username: String, password: String, save: Bool, allowOffline: Bool = false, fresh: Bool = false) async {
        // Wurde der Login aus dem „Konto hinzufügen“/„Passwort nötig“-Sheet gestartet?
        // (Dann müssen wir den Sheet-Wechsel sorgfältig sequenzieren – siehe finalize.)
        let viaSheet = showAddAccount
        let epoch = lockEpoch
        busy = true; error = nil
        statusText = "Verbinde mit WebUntis…"

        // Offline-Fallback nur für wiederkehrende Konten mit vorhandenem Cache.
        let snap: UserSession? = allowOffline ? Self.offlineCandidate(username: username) : nil
        let school = school(for: username)
        let loginTask = Task { try await self.buildSession(username: username, password: password, school: school, renewal: !fresh) }

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

        // Locked while this ran: it doesn't get to open the app again.
        guard epoch == lockEpoch else { busy = false; statusText = ""; return }

        switch outcome {
        case .done(let s):
            await finalize(s, save: save, password: password, viaSheet: viaSheet, fresh: fresh, epoch: epoch)
            busy = false; statusText = ""
        case .timedOut:
            // Kein Internet rechtzeitig → Offline-Modus aus dem Snapshot, Login läuft
            // im Hintergrund weiter und „upgradet" die Sitzung bei Erfolg.
            guard let snap else { busy = false; statusText = ""; return }
            await enterOffline(snap, viaSheet: viaSheet, epoch: epoch)
            Task { [weak self] in
                if let s = try? await loginTask.value {
                    await self?.upgradeFromBackground(s, save: save, password: password, epoch: epoch)
                }
            }
        case .failed(let e):
            // Schneller Netzwerkfehler (z. B. Flugmodus) + Cache → ebenfalls offline.
            if let snap, e is URLError {
                await enterOffline(snap, viaSheet: viaSheet, epoch: epoch)
            } else {
                self.error = (e as? AppError)?.message ?? e.localizedDescription
            }
            busy = false; statusText = ""
        }
    }

    /// Eigentlicher Netzwerk-Login: WebUntis → Fallback POKYH-Backend → Backend-Konto
    /// beziehen. Baut die fertige Sitzung inkl. Tokens und setzt `backendStatus`.
    private func buildSession(username: String, password: String, school: School, renewal: Bool) async throws -> UserSession {
        var s: UserSession
        var backendOnly = false
        let withKey = AppKey.isKey(password)
        do {
            s = try await UntisClient.shared.login(username: username, password: password, school: school)
        } catch let untisError {
            // An app key is never a POKYH password.
            if withKey { throw untisError }
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
                    username: s.username, klasseId: s.klasseId, klasseName: s.klasseName, role: role,
                    renewal: renewal, school: s.school, method: withKey ? "office" : nil) {
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
                case .revoked(let msg):
                    // Signed out from another device: the saved password goes, so this phone
                    // asks for it again instead of signing itself back in.
                    WatchSync.signedOut(username: s.username)
                    store.signOut(s.username)
                    accounts = store.accounts
                    throw AppError(message: msg)
                }
            } else {
                backendStatus = .notStudent
            }
        }
        return s
    }

    /// Abschluss eines erfolgreichen Online-Logins: Konto sichern, Offline-Snapshot
    /// persistieren, Sitzung übernehmen (mit sorgfältiger Sheet-Sequenzierung).
    private func finalize(_ s: UserSession, save: Bool, password: String, viaSheet: Bool, fresh: Bool, epoch: Int) async {
        // Konto + Passwort sichern, BEVOR die Session getauscht wird, damit es
        // auch dann lokal gespeichert ist, wenn der View-Wechsel dazwischenkommt.
        if save {
            let account = SavedAccount(
                username: s.username,
                displayName: s.klasseName.isEmpty ? s.username : s.klasseName,
                imageUrl: s.imageUrl,
                school: s.school)
            store.save(account, password: password)
        }
        // The watch signs in with the same account and stays signed in.
        WatchSync.signedIn(username: s.username, displayName: s.personName ?? s.username, password: password)
        store.lastActive = s.username
        // Profilbild auch beim stillen Login (save:false) nachtragen → Konten-Liste
        // & Sperrbildschirm zeigen das gecachte Bild.
        store.updateImageUrl(s.imageUrl, for: s.username)
        accounts = store.accounts
        // Token-losen Snapshot für späteren Offline-Restore ablegen.
        if s.hasUntis { DiskCache.save(Self.offlineSnapshot(s), key: Self.sessionKey(s.username)) }

        if viaSheet {
            busy = false; statusText = ""
            await closeSheetBeforeSwap()
            guard epoch == lockEpoch else { return }
        }
        session = s
        phase = .authed
        showAddAccount = false
        isOffline = false
        onAuthenticated()
        Task { await checkPrivacyNotice(fresh: fresh) }
    }

    /// Login lief über ein Sheet (Konto hinzufügen / Passwort-Neueingabe): ERST das Sheet
    /// schließen und die Dismiss-Animation abwarten, DANN die Session tauschen. Sonst kollidiert
    /// der View-Identitätswechsel (ContentView: `RootTabView().id(username)`, oder Sperre →
    /// angemeldet) mit der noch laufenden Sheet-Animation → das Modal hängt auf echten Geräten.
    private func closeSheetBeforeSwap() async {
        showAddAccount = false
        try? await Task.sleep(for: .milliseconds(420))
    }

    /// Wechselt in den Offline-Modus: gecachte (token-lose) Sitzung anzeigen.
    private func enterOffline(_ snap: UserSession, viaSheet: Bool, epoch: Int) async {
        busy = false; statusText = ""
        // Same sequencing as a normal sign-in; the offline path used to swap at once and hang.
        if viaSheet {
            await closeSheetBeforeSwap()
            guard epoch == lockEpoch else { return }
        }
        session = snap
        phase = .authed
        isOffline = true
        store.lastActive = snap.username
    }

    /// Hintergrund-Login nach Offline-Restore erfolgreich → Sitzung „upgraden".
    private func upgradeFromBackground(_ s: UserSession, save: Bool, password: String, epoch: Int) async {
        // Same account still on screen, and not locked in between?
        guard epoch == lockEpoch, let current = session, AccountRoster.same(current.username, s.username) else { return }
        if save {
            let account = SavedAccount(
                username: s.username,
                displayName: s.klasseName.isEmpty ? s.username : s.klasseName,
                imageUrl: s.imageUrl,
                school: s.school)
            store.save(account, password: password)
            accounts = store.accounts
        }
        if s.hasUntis { DiskCache.save(Self.offlineSnapshot(s), key: Self.sessionKey(s.username)) }
        withAnimation(.easeInOut(duration: 0.3)) {
            session = s
            isOffline = false
        }
        onAuthenticated()
        Task { await checkPrivacyNotice(fresh: false) }
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
            imageUrl: s.imageUrl, school: s.school)
    }

    // ── Kontowechsel / -verwaltung ───────────────────────────────────────────

    /// Sauberer Wechsel mit Face-ID-Bestätigung + Loading (über `busy`). The check is also what
    /// opens the other account's password, so it's never skipped.
    func switchAccount(username: String) async {
        guard !busy, !AccountRoster.same(username, session?.username ?? "") else { return }
        // Ohne gespeichertes Passwort → direkt Passwort-Neueingabe (kein Face ID nötig).
        guard store.hasPassword(username) else { askForPassword(username); return }
        busy = true; statusText = unlockText.confirming
        let name = AccountRoster.find(username, in: accounts)?.title ?? username
        guard let ctx = await authenticate(reason: unlockText.switchReason(name)) else {
            busy = false; statusText = ""; return
        }
        UnlockSession.begin(ctx)
        await loginSaved(username: username, context: ctx)
    }

    func accountHasPassword(_ username: String) -> Bool { store.hasPassword(username) }

    /// Widgets/Live Activity zeigen die Daten des **Standard-Kontos**. Ist kein
    /// Standard gesetzt, zählt das aktive Konto (Einzelnutzer-Fall).
    var isDefaultAccountActive: Bool {
        guard let active = session?.username else { return false }
        guard let fallback = store.defaultUsername else { return true }
        return AccountRoster.same(fallback, active)
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
        guard store.hasPassword(username) else { askForPassword(username); return }
        // Cancelled Face ID: leave it be.
        guard let password = await savedPassword(for: username) else { return }
        if AccountRoster.same(session?.username ?? "", username) {
            // performLogin(save: true) erneuert Sitzung + aktualisiert Anzeigenamen/Keychain.
            await performLogin(username: username, password: password, save: true)
        } else {
            busy = true; statusText = "Aktualisiere \(username)…"
            defer { busy = false; statusText = "" }
            if let s = try? await UntisClient.shared.login(username: username, password: password, school: school(for: username)) {
                store.updateDisplayName(s.klasseName.isEmpty ? s.username : s.klasseName, for: username)
                accounts = store.accounts
            } else {
                error = "Aktualisieren von \(username) fehlgeschlagen."
            }
        }
    }

    /// Abmelden: nur das Passwort entfernen — Konto bleibt gespeichert.
    func signOutAccount(username: String) {
        WatchSync.signedOut(username: username)
        store.signOut(username)
        accounts = store.accounts
        if isActive(username) { lock(deliberate: true) }
        objectWillChange.send()
    }

    /// Konto komplett vom Gerät entfernen, mit seinem Offline-Stand. Showed the widgets its
    /// data (default account) or was it the last one, they go blank too.
    func removeAccount(username: String) {
        WatchSync.signedOut(username: username)
        let wasDefault = AccountRoster.same(store.defaultUsername ?? "", username)
        let wasActive = isActive(username)
        store.remove(username)
        DiskCache.remove(key: Self.sessionKey(username))
        accounts = store.accounts
        if accounts.isEmpty {
            DiskCache.purge()
            ImageCache.purge()
        }
        if wasDefault || accounts.isEmpty {
            SharedStore.purgeAll()
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        if wasActive {
            LiveActivityManager.endAll()
            lock(deliberate: true)
        }
    }

    func logout() {
        lock(deliberate: true)
    }

    private func isActive(_ username: String) -> Bool {
        guard let active = session?.username else { return false }
        return AccountRoster.same(active, username)
    }

    /// Back to the lock screen, or to sign-in when nothing is saved. The unlock goes with the
    /// session, so the passwords need Face ID again.
    private func lock(deliberate: Bool) {
        lockEpoch += 1
        UnlockSession.end()
        autoUnlockArmed = !deliberate
        busy = false; statusText = ""
        unreadMessages = 0
        session = nil
        isOffline = false
        phase = accounts.isEmpty ? .login : .lock
    }

    /// „Cache & Daten löschen": entfernt ALLES Gespeicherte/Gecachte vom Gerät —
    /// Anmeldedaten (Keychain), Offline-Stundenplan/Noten, geteilte Widget-Snapshots,
    /// In-Memory-Caches und alle App-Einstellungen. Danach: zurück zum Login.
    func clearAllData() {
        WatchSync.signedOut()
        lockEpoch += 1
        UnlockSession.end()
        // 1. In-Memory-Caches
        UntisClient.shared.clearCaches()
        BackendClient.shared.clearCaches()
        ImageCache.purge()
        URLCache.shared.removeAllCachedResponses()
        // 2. Keychain (alle Passwörter)
        Keychain.purgeAll()
        // 3. Offline-Disk-Cache + geteilte Snapshots (App Group), then the key they were sealed with
        DiskCache.purge()
        SharedStore.purgeAll()
        LocalVault.destroy()
        // 4. Alle eigenen UserDefaults-Schlüssel (kein Hardcoding einzelner Keys). The storage
        //    format markers stay: without them the next launch would treat what's saved after
        //    this as left over from an old build and wipe it.
        let defaults = UserDefaults.standard
        let keep = Set([CredentialStore.formatDefaultsKey, SecureStorage.formatDefaultsKey])
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pokyh_") && !keep.contains(key) {
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
        unreadMessages = 0
        themeMode = .system
        phase = .login
    }

    func handleSessionExpired() {
        lock(deliberate: false)
    }

    // ── Backend token ─────────────────────────────────────────────────────────
    private var tokenRenewal: Task<(token: String, refresh: String)?, Never>?

    /// The POKYH access token lasts an hour. After a 401 the app signs in to the backend again,
    /// the way Android does. Requests failing together share one renewal.
    func renewBackendToken(expired: String) async -> String? {
        guard let s = session else { return nil }
        if let current = s.apiToken, current != expired { return current }
        if let running = tokenRenewal { return await running.value?.token }
        let task = Task { await self.freshBackendTokens(for: s) }
        tokenRenewal = task
        let fresh = await task.value
        tokenRenewal = nil
        // Switched accounts in the meantime: this token belongs to the old one.
        guard let fresh, let current = session, AccountRoster.same(current.username, s.username) else { return nil }
        session?.apiToken = fresh.token
        session?.apiRefresh = fresh.refresh
        return fresh.token
    }

    private func freshBackendTokens(for s: UserSession) async -> (token: String, refresh: String)? {
        if s.hasUntis {
            guard s.isStudent || s.isParent else { return nil }
            let outcome = await BackendClient.shared.loginWithUntis(
                username: s.username, klasseId: s.klasseId, klasseName: s.klasseName,
                role: s.isParent ? "parent" : "student", renewal: true, school: s.school)
            if case .ok(let token, let refresh) = outcome { return (token, refresh) }
            return nil
        }
        // POKYH-only accounts: the refresh token first, then the password if this unlock still
        // covers it. Never a surprise Face ID prompt in the middle of using the app.
        if let refresh = s.apiRefresh, let fresh = await BackendClient.shared.refresh(refreshToken: refresh) {
            return fresh
        }
        guard let password = store.password(for: s.username, context: UnlockSession.context),
              let login = try? await BackendClient.shared.login(username: s.username, password: password) else { return nil }
        return (login.token, login.refresh)
    }

    // ── Auto-Sperre nach Inaktivität im Hintergrund, Sichtschutz ──────────────
    /// Ten minutes in the background lock the app (Face ID again), as on Android.
    private var autoLock = AutoLock()

    /// Leaving the screen for a moment (app switcher, Control Center, a call): cover it.
    func appWillResignActive() {
        if !authenticating { privacyCover = true }
    }

    func appDidEnterBackground() {
        privacyCover = true
        autoLock.didLeave(signedIn: phase == .authed)
    }

    func appDidBecomeActive() {
        // Lock first, lift the cover after, so the content never shows in between.
        if autoLock.didReturn(), phase == .authed { lock(deliberate: false) }
        privacyCover = false
    }

    /// For background refresh: the live session, unless the app should have locked by now.
    private func sessionForBackgroundWork() -> UserSession? {
        if phase == .authed, autoLock.isDue() { lock(deliberate: false) }
        guard phase == .authed, !isOffline else { return nil }
        return session
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
            unreadMessages = inbox.filter { !$0.isRead }.count
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
