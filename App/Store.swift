import SwiftUI
import LocalAuthentication
import PokyhCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The app's state: the phase (locked, signing in, signed in), several accounts and the
/// Face ID unlock. Passwords sit in the Keychain behind Face ID, never in plain text.
/// The tabs (top-level and `nonisolated`, so comparing them is safe anywhere).
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

/// How the POKYH backend connection stands (to-dos, reminders, class), shown in the
/// profile when something's wrong.
enum BackendStatus: Equatable {
    case unknown
    case connected
    case notStudent        // not a pupil: no POKYH account, on purpose
    case noClass           // pupil WebUntis names no class for (why: AppState.backendClassNote)
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
@Observable
final class AppState {
    enum Phase { case lock, login, authed }

    var phase: Phase
    var session: UserSession? {
        // Another account, or signed out: the notice was for someone else.
        didSet {
            PushRegistration.shared.sessionDidChange(session, in: self)
            if session?.username != privacyNotice?.username { privacyNotice = nil }
            UntisImageAuth.current = UntisImageAuth(session)
            ensureProfileImageUrl()
        }
    }
    /// The privacy notice waiting to be accepted (see PrivacyNotice.swift).
    var privacyNotice: PrivacyNoticePrompt?
    /// A website sign-in opened from the phone's camera, waiting for the signed-in app.
    var pendingWebSignIn: String?
    var accounts: [SavedAccount] {
        didSet {
            storeRevision += 1
            PushRegistration.shared.accountsDidChange(accounts, in: self)
        }
    }
    /// The app's language; views read it so a pick in the settings shows everywhere at once.
    var language = LanguageChoice.current(in: .standard)
    /// Bumped whenever `store` changes, which isn't observed itself, so reads through it refresh.
    private var storeRevision = 0
    var busy = false
    /// Offline: stored data on screen, the sign-in didn't get through.
    var isOffline = false
    /// Opened on the stored copy while the sign-in is still on its way. Offline underneath (no
    /// tokens yet), but nothing says so unless it takes longer than a sign-in usually does.
    var signingInBehind = false
    /// What the screens show as offline.
    var showsOffline: Bool { isOffline && !signingInBehind }
    var statusText = ""
    var error: String?
    var showAddAccount = false
    var prefillUsername: String?   // filled in when the password is asked for again
    /// A sign-in waiting for the authenticator app's code, from any path: the sign-in screen, an
    /// unlock, a relaunch. An account like that can't sign itself in.
    private(set) var twoFactor: TwoFactorRequest?
    var selectedTab: AppTab = .home {
        didSet { if selectedTab != oldValue { UsageReporter.shared.noteScreen() } }
    }
    var backendStatus: BackendStatus = .unknown
    /// With `.noClass`: why, as the backend says ("pending", "no_class_found", "shared_person", …).
    var backendClassNote: String?
    /// Unread inbox messages, for the badges. Refreshed with the notification sync.
    var unreadMessages = 0
    /// Face ID or Touch ID. Found out off the main thread (see init); it starts with a
    /// cheap default so the first frame never waits for it.
    var biometricInfo = Biometric.Info.unknown
    /// Goes up when the timetable tab is tapped again, which jumps the view to today.
    var timetableHomeSignal = 0
    var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "pokyh_theme") }
    }
    /// The Face ID / passcode sheet is up. It makes the app inactive, which must not bring up
    /// the privacy cover over it.
    private(set) var authenticating = false
    /// Hides the app in the app switcher and whenever it isn't the active app.
    private(set) var privacyCover = false

    @ObservationIgnored private let store = CredentialStore.shared
    private var unlockText: UnlockStrings { .of(Strings.current.lang) }
    /// The lock screen tries Face ID by itself on launch and after the auto-lock, not right
    /// after someone signed out on purpose.
    @ObservationIgnored private var autoUnlockArmed = true
    /// Goes up with every lock, so a sign-in still running from before can't open the app again.
    @ObservationIgnored private var lockEpoch = 0
    /// While the account is being deleted a token renewal would create it anew, empty.
    @ObservationIgnored private var deletingAccount = false
    /// A sign-in in the background while offline; one at a time.
    @ObservationIgnored private var reconnecting = false

    init() {
        let saved = store.accounts
        accounts = saved
        phase = saved.isEmpty ? .login : .lock
        let raw = UserDefaults.standard.string(forKey: "pokyh_theme") ?? ThemeMode.system.rawValue
        themeMode = ThemeMode(rawValue: raw) ?? .system
        // The first `canEvaluatePolicy` call takes about 300 ms, so it runs off the main thread
        // and the answer arrives later. Views read `biometricInfo`, never `Biometric.info`.
        Task.detached(priority: .userInitiated) {
            let info = Biometric.info
            await MainActor.run { self.biometricInfo = info }
        }
        BackgroundRefresh.liveSession = { [weak self] in self?.sessionForBackgroundWork() }
        BackendClient.shared.tokenRenewal = { [weak self] in await self?.renewBackendToken(expired: $0) }
        NetworkMonitor.shared.onReconnect = { [weak self] in Task { await self?.reconnect() } }
        #if DEBUG
        if let seconds = StubServer.autoLockSeconds { autoLock = AutoLock(interval: .seconds(seconds)) }
        if let account = StubServer.autoSignIn {
            let school = School(loginName: StubServer.school.loginName, server: StubServer.school.server, name: StubServer.school.name)
            Task { await loginNew(username: account, password: "stub", save: true, school: school) }
        }
        #endif
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

    // ── Default account (settings) ───────────────────────────────────────────
    var defaultUsername: String? {
        get { _ = storeRevision; return store.defaultUsername }
        set { store.defaultUsername = newValue; storeRevision += 1 }
    }

    // ── Lock screen: Face ID, then the sign-in by itself ─────────────────────

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
        // Waiting for the code still counts as this unlock.
        if session == nil, twoFactor == nil { UnlockSession.end() }
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
    func savedPassword(for username: String) async -> String? {
        if let password = store.password(for: username, context: UnlockSession.context) { return password }
        guard let ctx = await authenticate(reason: unlockText.confirmReason) else { return nil }
        UnlockSession.begin(ctx)
        return store.password(for: username, context: ctx)
    }

    // ── Neuer / manueller Login ──────────────────────────────────────────────

    /// The school picked on the sign-in screen, for the sign-in under way only: a failed one at
    /// the wrong school must not stick to later silent or Face ID re-logins.
    @ObservationIgnored private var loginSchool: (username: String, school: School)?

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

    // ── Two-factor sign-in ───────────────────────────────────────────────────

    /// Signs in again with the code. The prompt stays up until there's an answer.
    func submitTwoFactorCode(_ code: String) async {
        guard var request = twoFactor, !request.checking, TwoFactorCode.isComplete(code) else { return }
        request.checking = true
        request.wrongCode = false
        request.problem = nil
        twoFactor = request
        // The person is right here typing, so this counts as signing in, not as the app renewing.
        loginSchool = (request.username.trimmingCharacters(in: .whitespaces).lowercased(), request.school)
        await performLogin(username: request.username, password: request.password, save: request.save,
                           fresh: true, token: TwoFactorCode.digits(code))
        loginSchool = nil
    }

    func cancelTwoFactor() {
        guard twoFactor?.checking != true else { return }
        twoFactor = nil
        busy = false; statusText = ""
        if session == nil { UnlockSession.end() }
    }

    /// True when `error` was WebUntis asking for the code; the prompt then takes over from the error.
    private func askForCode(_ error: Error, username: String, password: String, save: Bool, school: School) -> Bool {
        guard let asked = error as? TwoFactorRequired else { return false }
        twoFactor = TwoFactorRequest(username: username, password: password, save: save, school: school, wrongCode: asked.wrongCode)
        return true
    }

    /// Called when messages were opened or marked read, so the badge drops at once.
    func messageWasRead(count: Int = 1) {
        unreadMessages = max(0, unreadMessages - count)
    }

    /// How long a sign-in may go unanswered (no internet) before a returning account with
    /// stored data opens offline.
    private static let offlineTimeout: Double = 5

    private enum LoginOutcome { case done(UserSession), timedOut, failed(Error) }
    private enum RaceResult: Sendable { case finished, timedOut }

    /// `fresh`: the credentials were just typed in, not read from the Keychain.
    /// `token`: the authenticator app's code, for an account with two-factor sign-in.
    private func performLogin(username: String, password: String, save: Bool, allowOffline: Bool = false, fresh: Bool = false, token: String? = nil) async {
        // Started from the add-account or password sheet? Then the sheet has to leave first,
        // see finalize.
        let viaSheet = showAddAccount
        let epoch = lockEpoch
        busy = true; error = nil
        statusText = "Verbinde mit WebUntis…"

        // Offline only for a returning account with stored data.
        let snap: UserSession? = allowOffline ? Self.offlineCandidate(username: username) : nil
        if let snap, !NetworkMonitor.shared.isOnline {
            // No way out at all: the stored copy right away, the sign-in once the connection is back.
            await enterOffline(snap, viaSheet: viaSheet, epoch: epoch)
            return
        }
        let school = school(for: username)
        let loginTask = Task { try await self.buildSession(username: username, password: password, school: school, renewal: !fresh, token: token) }

        // A returning account opens at once on what it had last time; the sign-in finishes
        // behind it and swaps the fresh data in. Waiting for WebUntis first took a second or
        // three on every unlock. A typed password or a new account still waits.
        if let snap, !viaSheet, !fresh, token == nil {
            await enterOffline(snap, viaSheet: false, epoch: epoch)
            signingInBehind = true
            reconnecting = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.offlineTimeout))
                // Slower than usual: from here on it's said like any offline start.
                if self?.lockEpoch == epoch { self?.signingInBehind = false }
            }
            Task { [weak self] in
                defer {
                    self?.reconnecting = false
                    if self?.lockEpoch == epoch { self?.signingInBehind = false }
                }
                do {
                    let s = try await loginTask.value
                    await self?.upgradeFromBackground(s, save: save, password: password, epoch: epoch)
                } catch {
                    guard let self, epoch == self.lockEpoch else { return }
                    if self.askForCode(error, username: username, password: password, save: save, school: school) { return }
                    // No connection: the stored copy stays, the banner says so, and coming back
                    // online signs in again.
                    if error is URLError { return }
                    // Refused (password changed, signed out elsewhere): back to the lock screen
                    // with the reason, like a sign-in that failed there.
                    self.lock(deliberate: true)
                    self.error = (error as? AppError)?.message ?? error.localizedDescription
                }
            }
            return
        }

        // Without the offline way out it simply waits; with it, the sign-in races five seconds.
        let outcome: LoginOutcome
        if snap == nil {
            do { outcome = .done(try await loginTask.value) }
            catch { outcome = .failed(error) }
        } else {
            switch await Self.race(loginTask, timeout: Self.offlineTimeout) {
            case .finished:
                // The sign-in finished: take its session or its error.
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
            twoFactor = nil
            await finalize(s, save: save, password: password, viaSheet: viaSheet, fresh: fresh, epoch: epoch)
            busy = false; statusText = ""
        case .timedOut:
            // No internet in time: open offline from the snapshot. The sign-in carries on and
            // upgrades the session when it gets through.
            guard let snap else { busy = false; statusText = ""; return }
            await enterOffline(snap, viaSheet: viaSheet, epoch: epoch)
            reconnecting = true
            Task { [weak self] in
                defer { self?.reconnecting = false }
                do {
                    let s = try await loginTask.value
                    await self?.upgradeFromBackground(s, save: save, password: password, epoch: epoch)
                } catch {
                    // The connection came back and WebUntis wants the code after all.
                    guard let self, epoch == self.lockEpoch else { return }
                    _ = self.askForCode(error, username: username, password: password, save: save, school: school)
                }
            }
        case .failed(let e):
            if askForCode(e, username: username, password: password, save: save, school: school) {
                // The prompt takes over.
            } else if token != nil {
                // Asked from the prompt, so it's the one to say so; the screen under it can't be seen.
                twoFactor?.checking = false
                twoFactor?.problem = (e as? AppError)?.message ?? Strings.current.errors.noConnection
            // A quick network failure (flight mode) with a stored copy: offline as well.
            } else if let snap, e is URLError {
                await enterOffline(snap, viaSheet: viaSheet, epoch: epoch)
            } else {
                self.error = (e as? AppError)?.message ?? e.localizedDescription
            }
            busy = false; statusText = ""
        }
    }

    /// The sign-in itself: WebUntis, else the POKYH backend alone, then the backend account.
    /// Builds the whole session with its tokens and sets `backendStatus`.
    private func buildSession(username: String, password: String, school: School, renewal: Bool, token: String? = nil) async throws -> UserSession {
        var s: UserSession
        var backendOnly = false
        let withKey = AppKey.isKey(password)
        do {
            s = try await UntisClient.shared.login(username: username, password: password, token: token, school: school)
        } catch let untisError {
            // An app key is never a POKYH password. And WebUntis asking for the code means the
            // password was right, so this is no POKYH-only account either.
            if withKey || token != nil || untisError is TwoFactorRequired { throw untisError }
            // No working WebUntis account: sign in to the POKYH backend directly with the same
            // credentials. The backend knows POKYH-only accounts.
            do {
                let backend = try await BackendClient.shared.login(
                    username: username, password: password)
                s = Self.backendOnlySession(from: backend)
                backendStatus = .connected
                backendOnly = true
            } catch {
                // Both failed. For a POKYH-only account the backend's message says more (wrong
                // credentials, say); a plain network failure passes on WebUntis' error.
                throw (error is URLError) ? untisError : error
            }
        }
        // Students and guardians get a POKYH account (teachers and admins don't). A guardian's
        // is role=parent: own to-dos, the class name only, no reminders, an invisible member.
        // Their klasseId is the child's (UntisClient finds it). The backend creates the
        // account on first sign-in.
        // Reine Backend-Konten (Fallback) haben ihre Tokens bereits.
        if !backendOnly {
            if s.isStudent || s.isParent {
                let role = s.isParent ? "parent" : "student"
                // The backend asks WebUntis itself, with this very session, whose it is and
                // which class the account has; the class worked out here does not count.
                switch await BackendClient.shared.loginWithUntis(
                    username: s.username, untisSessionId: s.sessionId, role: role,
                    renewal: renewal, school: s.school, method: withKey ? "office" : nil) {
                case .ok(let token, let refresh):
                    s.apiToken = token
                    s.apiRefresh = refresh
                    backendStatus = .connected
                    backendClassNote = nil
                    if let user = try? await BackendClient.shared.me(token: token) {
                        s.stableUid = user.stableUid
                        s.classId = user.classId
                        // A pupil without a class: why, as the backend says (shown in the views).
                        if user.classId == nil, user.role ?? "student" == "student", s.isStudent {
                            backendStatus = .noClass
                            backendClassNote = user.classCheckPending == true ? "pending" : user.classNote
                        }
                    }
                case .untisSessionExpired:
                    backendStatus = .failed(Strings.current.common.sessionExpired)
                case .untisUnavailable(let msg), .failed(let msg):
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

    /// The end of a sign-in that got through: the account and an offline snapshot
    /// saved, the session taken over, with the sheet leaving first.
    private func finalize(_ s: UserSession, save: Bool, password: String, viaSheet: Bool, fresh: Bool, epoch: Int) async {
        // The account and password are saved before the session changes, so they're kept even
        // when the switch of views gets in between.
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
        // The picture on a silent sign-in too, so the list of accounts and the lock screen
        // show it.
        store.updateImageUrl(s.imageUrl, for: s.username)
        accounts = store.accounts
        // A snapshot without tokens, to open offline later.
        if s.hasUntis { DiskCache.save(Self.offlineSnapshot(s), key: Self.sessionKey, owner: s.username) }

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

    /// A sign-in from a sheet (add account, password again): the sheet closes and finishes
    /// its animation before the session changes. Otherwise swapping the views
    /// (`RootTabView().id(username)` in ContentView, or lock to signed in) runs into the
    /// sheet's animation, and the sheet hangs on real devices.
    private func closeSheetBeforeSwap() async {
        showAddAccount = false
        try? await Task.sleep(for: .milliseconds(420))
    }

    /// Goes offline: shows the stored session, which has no tokens.
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

    /// The sign-in behind an offline start got through: upgrade the session.
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
        // What a sign-in on the lock screen does too, now that it can finish behind the app.
        WatchSync.signedIn(username: s.username, displayName: s.personName ?? s.username, password: password)
        store.lastActive = s.username
        store.updateImageUrl(s.imageUrl, for: s.username)
        accounts = store.accounts
        if s.hasUntis { DiskCache.save(Self.offlineSnapshot(s), key: Self.sessionKey, owner: s.username) }
        withAnimation(.easeInOut(duration: 0.3)) {
            session = s
            isOffline = false
            signingInBehind = false
        }
        onAuthenticated()
        Task { await checkPrivacyNotice(fresh: false) }
    }

    /// Signed in offline: tries the real sign-in again with the password this unlock already
    /// opened, so it never asks for Face ID by itself. On the way back online, on returning to
    /// the app, and from pull to refresh.
    func reconnect() async {
        guard isOffline, phase == .authed, !reconnecting, !busy, let snap = session,
              let password = store.password(for: snap.username, context: UnlockSession.context) else { return }
        reconnecting = true
        defer { reconnecting = false }
        let epoch = lockEpoch
        let school = school(for: snap.username)
        do {
            let fresh = try await buildSession(username: snap.username, password: password, school: school, renewal: true)
            await upgradeFromBackground(fresh, save: false, password: password, epoch: epoch)
        } catch {
            guard epoch == lockEpoch else { return }
            _ = askForCode(error, username: snap.username, password: password, save: false, school: school)
        }
    }

    // ── Offline-Helfer ────────────────────────────────────────────────────────

    /// In the account's own folder, like everything else it left offline.
    private static let sessionKey = "session"

    /// Only for a WebUntis account (`studentId > 0`), whose stored timetable can be read.
    private static func offlineCandidate(username: String) -> UserSession? {
        guard let snap = DiskCache.load(UserSession.self, key: sessionKey, owner: username),
              snap.studentId > 0 else { return nil }
        return snap
    }

    /// Which comes first, the sign-in or the timeout? On a timeout only the waiting stops;
    /// the sign-in itself goes on.
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

    /// A POKYH-only session, no WebUntis: the API tokens and the basics, the WebUntis
    /// fields left empty, so `hasUntis` is false.
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

    /// The session to open offline with: only what's shown and the cache keys, never
    /// tokens or cookies. Those come back with the next real sign-in.
    private static func offlineSnapshot(_ s: UserSession) -> UserSession {
        UserSession(
            sessionId: "", bearerToken: "", studentId: s.studentId,
            klasseId: s.klasseId, klasseName: s.klasseName, username: s.username,
            personName: s.personName, firstName: s.firstName, personType: s.personType, isParent: s.isParent,
            apiToken: nil, apiRefresh: nil, stableUid: s.stableUid, classId: s.classId,
            imageUrl: s.imageUrl, school: s.school, backendLinked: s.apiToken != nil ? true : nil)
    }

    // ── Kontowechsel / -verwaltung ───────────────────────────────────────────

    /// Switches with a Face ID check and a loading state (`busy`). The check is also what
    /// opens the other account's password, so it's never skipped.
    func switchAccount(username: String) async {
        guard !busy, !AccountRoster.same(username, session?.username ?? "") else { return }
        // No saved password: ask for it, no Face ID needed.
        guard store.hasPassword(username) else { askForPassword(username); return }
        busy = true; statusText = unlockText.confirming
        let name = AccountRoster.find(username, in: accounts)?.title ?? username
        guard let ctx = await authenticate(reason: unlockText.switchReason(name)) else {
            busy = false; statusText = ""; return
        }
        UnlockSession.begin(ctx)
        await loginSaved(username: username, context: ctx)
    }

    /// A Keychain query per account on every redraw of the profile adds up; asked once per change.
    func accountHasPassword(_ username: String) -> Bool {
        let revision = storeRevision
        if passwordsKnownAt != revision {
            passwordsKnown = [:]
            passwordsKnownAt = revision
        }
        if let known = passwordsKnown[username] { return known }
        let has = store.hasPassword(username)
        passwordsKnown[username] = has
        return has
    }
    @ObservationIgnored private var passwordsKnown: [String: Bool] = [:]
    @ObservationIgnored private var passwordsKnownAt = -1

    /// The widgets and the Live Activity show the default account. Without a default,
    /// the active one counts (one account only).
    var isDefaultAccountActive: Bool {
        guard let active = session?.username else { return false }
        guard let fallback = store.defaultUsername else { return true }
        return AccountRoster.same(fallback, active)
    }

    /// Updates the Live Activity (running or next lesson) from the timetable.
    func refreshLiveActivity(from entries: [TimetableEntry]) {
        guard let s = session else { return }
        LiveActivityManager.refresh(from: entries, className: s.klasseName)
    }

    /// The settings' switch. Turned on, it starts from this week's last copy right away instead
    /// of waiting for the next timetable load.
    func setLiveActivity(_ on: Bool) {
        LiveActivityManager.isEnabled = on
        guard on else { LiveActivityManager.endAll(); return }
        guard let s = session, isDefaultAccountActive else { return }
        Task {
            guard let week = await UntisClient.shared.storedTimetable(date: SchoolDates.mondayISO(of: Date()), s),
                  let current = session, AccountRoster.same(current.username, s.username) else { return }
            refreshLiveActivity(from: week)
        }
    }

    /// Sets or clears an account's local nickname (empty clears it).
    func setNickname(_ nickname: String?, for username: String) {
        store.setNickname(nickname, for: username)
        accounts = store.accounts
    }

    /// Reloads an account: signs in to WebUntis again for a fresh name and class.
    /// - The active account gets a new session and backend status.
    /// - Another one only gets its class, in the background; the active session stays as
    ///   it is (each session has its own cookies).
    /// Without a saved password it asks for one.
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

    /// Signing out keeps the account in the list (name and picture, to sign in again quickly) and
    /// takes everything else: the password, its offline copies, unsent to-dos, the widgets'
    /// data if they showed it.
    func signOutAccount(username: String) {
        WatchSync.signedOut(username: username)
        store.signOut(username)
        let wasActive = isActive(username)
        forgetData(of: username)
        accounts = store.accounts
        if wasActive { lock(deliberate: true) }
    }

    /// What an account left on this device besides its row in the list.
    private func forgetData(of username: String) {
        DiskCache.forget(owner: username)
        Outbox.shared.forget(username)
        if AccountRoster.same(store.defaultUsername ?? "", username) {
            SharedStore.purgeAll()
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        if isActive(username) {
            LiveActivityManager.endAll()
            NotificationManager.shared.withdrawReminders()
        }
    }

    /// Removes the account from the device with its offline copies. If the widgets showed its
    /// data (default account) or it was the last one, they go blank too.
    func removeAccount(username: String) {
        ImageCache.forget(ImageCache.avatarKey(username))
        WatchSync.signedOut(username: username)
        let wasDefault = AccountRoster.same(store.defaultUsername ?? "", username)
        let wasActive = isActive(username)
        forgetData(of: username)
        store.remove(username)
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

    enum AccountDeletion: Equatable {
        case deleted
        /// The backend doesn't know the route yet.
        case notAvailable
        case failed(String)
    }

    /// Deletes the POKYH account for good, then forgets it on this device like signing out.
    func deleteAccount() async -> AccountDeletion {
        let t = Strings.current
        guard !isOffline, let s = session, let stale = s.apiToken else { return .failed(t.common.noConnection) }
        // A token that ran out is renewed now, not halfway through: once the backend has revoked
        // it, requests failing at that moment would renew themselves and create the account anew.
        _ = try? await BackendClient.shared.me(token: stale)
        guard let current = session, isActive(s.username), let token = current.apiToken else { return .failed(t.common.sessionExpired) }
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            try await BackendClient.shared.deleteAccount(token: token)
        } catch let error as AppError {
            switch error.status {
            case 404: return .notAvailable
            case 401: return .failed(t.common.sessionExpired)
            default: return .failed(error.message)
            }
        } catch {
            return .failed(t.common.noConnection)
        }
        removeAccount(username: s.username)
        return .deleted
    }

    private func isActive(_ username: String) -> Bool {
        guard let active = session?.username else { return false }
        return AccountRoster.same(active, username)
    }

    /// Back to the lock screen, or to sign-in when nothing is saved. The unlock goes with the
    /// session, so the passwords need Face ID again.
    private func lock(deliberate: Bool) {
        lockEpoch += 1
        twoFactor = nil
        UnlockSession.end()
        autoUnlockArmed = !deliberate
        busy = false; statusText = ""
        unreadMessages = 0
        session = nil
        isOffline = false
        signingInBehind = false
        // What was loaded stays sealed on disk; nothing of it lingers in memory behind the lock.
        UntisClient.shared.clearCaches()
        BackendClient.shared.clearCaches()
        phase = accounts.isEmpty ? .login : .lock
    }

    /// "Cache & Daten löschen": everything stored goes, the credentials (Keychain), offline
    /// copies, the widgets' snapshots, the caches in memory and every setting. Then back to
    /// the sign-in.
    func clearAllData() {
        WatchSync.signedOut()
        lockEpoch += 1
        twoFactor = nil
        UnlockSession.end()
        // 1. Caches in memory
        UntisClient.shared.clearCaches()
        BackendClient.shared.clearCaches()
        ImageCache.purge()
        URLCache.shared.removeAllCachedResponses()
        // 2. Keychain (every password)
        Keychain.purgeAll()
        // 3. Offline copies and the shared snapshots (app group), then the key they were sealed with
        DiskCache.purge()
        Outbox.shared.clearAll()
        SharedStore.purgeAll()
        LocalVault.destroy()
        // Scheduled reminders and banners still in the Notification Center carry titles and names.
        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
        // 4. Every UserDefaults key of ours, found by prefix rather than by name. The storage
        //    format markers stay: without them the next launch would treat what's saved after
        //    this as left over from an old build and wipe it.
        let defaults = UserDefaults.standard
        let keep = Set([CredentialStore.formatDefaultsKey, SecureStorage.formatDefaultsKey])
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pokyh_") && !keep.contains(key) {
            defaults.removeObject(forKey: key)
        }
        // 5. End the Live Activity, empty the widgets
        LiveActivityManager.endAll()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        // 6. Reset the state, back to the sign-in
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

    // ── Profile picture ───────────────────────────────────────────────────────
    @ObservationIgnored private var profileImageAttempted: Set<String> = []

    /// Sign-in only learns the picture's address when it happened to need app data for something
    /// else, so it's asked for here, once per account, as on Android.
    private func ensureProfileImageUrl() {
        guard let current = session, current.imageUrl == nil, current.hasUntis, !current.sessionId.isEmpty,
              profileImageAttempted.insert(AccountRoster.key(current.username)).inserted else { return }
        Task {
            guard let resolved = await UntisClient.shared.fetchProfileImageUrl(current),
                  let latest = session, AccountRoster.same(latest.username, current.username) else { return }
            session?.imageUrl = resolved
            store.updateImageUrl(resolved, for: latest.username)
            accounts = store.accounts
        }
    }

    // ── Backend token ─────────────────────────────────────────────────────────
    @ObservationIgnored private var tokenRenewal: Task<(token: String, refresh: String)?, Never>?

    /// The backend token once there is one. A returning account opens on its stored copy, which
    /// has none, and signs in behind it; a link opened from the camera lands in that moment, so it
    /// waits for that sign-in instead of calling the session expired. Nil when it doesn't bring one.
    func backendTokenWhenReady(within limit: Duration = .seconds(20)) async -> String? {
        let deadline = ContinuousClock.now + limit
        while session != nil, session?.apiToken == nil, reconnecting || signingInBehind || busy,
              ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return session?.apiToken
    }

    /// The POKYH access token lasts an hour. After a 401 the app signs in to the backend again,
    /// the way Android does. Requests failing together share one renewal.
    func renewBackendToken(expired: String) async -> String? {
        guard !deletingAccount, let s = session else { return nil }
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
            let role = s.isParent ? "parent" : "student"
            var outcome = await BackendClient.shared.loginWithUntis(
                username: s.username, untisSessionId: s.sessionId, role: role, renewal: true, school: s.school)
            // The WebUntis session has ended: sign in to WebUntis again (with what this unlock
            // still covers, never a surprise Face ID prompt) and once more at the backend.
            if case .untisSessionExpired = outcome, let renewed = await renewedUntisSession(for: s) {
                outcome = await BackendClient.shared.loginWithUntis(
                    username: s.username, untisSessionId: renewed.sessionId, role: role, renewal: true, school: s.school)
            }
            switch outcome {
            case .ok(let token, let refresh):
                return (token, refresh)
            case .revoked:
                return nil
            case .untisUnavailable, .untisSessionExpired, .failed:
                // WebUntis away or the session not renewable now: the device's own refresh token
                // keeps the POKYH session going until the next sign-in checks again.
                if let refresh = s.apiRefresh, let fresh = await BackendClient.shared.refresh(refreshToken: refresh) {
                    return fresh
                }
                return nil
            }
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

    /// A new WebUntis session for the account, signed in with the password (or key) this unlock
    /// still covers; the active session takes it over. Nil when none is at hand.
    func renewedUntisSession(for s: UserSession) async -> UserSession? {
        guard let password = store.password(for: s.username, context: UnlockSession.context),
              let renewed = try? await UntisClient.shared.login(username: s.username, password: password, school: s.school) else { return nil }
        if let current = session, AccountRoster.same(current.username, s.username) {
            session?.sessionId = renewed.sessionId
            session?.bearerToken = renewed.bearerToken
        }
        return renewed
    }

    // ── Lock after time in the background, privacy cover ─────────────────────
    /// Ten minutes in the background lock the app (Face ID again), as on Android.
    @ObservationIgnored private var autoLock = AutoLock()

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
        if isOffline { Task { await reconnect() } }
    }

    /// For background refresh: the live session, unless the app should have locked by now.
    private func sessionForBackgroundWork() -> UserSession? {
        if phase == .authed, autoLock.isDue() { lock(deliberate: false) }
        guard phase == .authed, !isOffline else { return nil }
        return session
    }

    // ── After a sign-in: set up notifications ─────────────────────────────────
    // Not at launch on the sign-in screen: on real hardware that ended the app at runtime.
    // Here the UI is up, which is safe.
    func onAuthenticated() {
        NotificationManager.shared.configure()
        requestNotificationPermissionIfNeeded()
        Task { await syncNotifications() }
        if let session {
            // Online again: what was typed offline goes out, and copies nobody reads go.
            Task { await Outbox.shared.flush(session) }
            DiskCache.pruneIfDue()
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        let key = "pokyh_notif_asked"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        // An empty completion, so no actor or thread trouble.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // ── Notification checks (messages, reminders) ─────────────────────────────
    @ObservationIgnored private var lastNotifSync = Date.distantPast
    // A longer pause for the heavier checks (grades, timetable): grades load per subject,
    // too much for the messages' 60 seconds.
    @ObservationIgnored private var lastHeavySync = Date.distantPast
    @ObservationIgnored private let heavySyncInterval: TimeInterval = 1800   // 30 min

    func syncNotifications() async {
        guard let s = session else { return }
        // At most once a minute.
        guard Date().timeIntervalSince(lastNotifSync) > 60 else { return }
        lastNotifSync = Date()

        if let inbox = try? await UntisClient.shared.messages(folder: .inbox, s) {
            unreadMessages = inbox.filter { !$0.isRead }.count
            NotificationManager.shared.checkNewMessages(inbox)
            if isDefaultAccountActive { WidgetBridge.publishMessages(inbox) }   // default account only
        }
        if let token = s.apiToken, let classId = s.classId,
           let reminders = try? await BackendClient.shared.reminders(classId: classId, token: token) {
            NotificationManager.shared.scheduleReminders(reminders)
        }

        // The heavier checks less often: new grades and cancelled lessons.
        if Date().timeIntervalSince(lastHeavySync) > heavySyncInterval {
            lastHeavySync = Date()
            await syncGradeAndTimetableAlerts(s)
        }
    }

    /// New grades and cancelled lessons as local notifications. Students only: guardians
    /// and teachers have no MY_TIMETABLE grades.
    private func syncGradeAndTimetableAlerts(_ s: UserSession) async {
        if s.isStudent, let subjects = try? await UntisClient.shared.grades(year: nil, s) {
            NotificationManager.shared.checkNewGrades(subjects)
            if isDefaultAccountActive { WidgetBridge.publishGrades(subjects) }   // default account only
        }
        // The timetable from today (Monday to Saturday) for lessons still to be cancelled.
        if let entries = try? await UntisClient.shared.timetable(date: SchoolDates.todayISO(), s) {
            NotificationManager.shared.checkTimetableChanges(entries)
        }
    }
}
