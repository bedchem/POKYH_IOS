import Foundation
import LocalAuthentication
import PokyhCore
import Security

/// Saved passwords, one Keychain item per account. Reading one takes Face ID, Touch ID or the
/// device passcode (`.userPresence`); the items only open while the phone is unlocked and never
/// leave it (no iCloud Keychain, no backup). WebUntis wants the password itself on the next
/// sign-in, so it can't be kept as a hash.
///
/// Reads never show UI here. The app runs the check first (`Biometric.authenticate`) and hands
/// that context in, so one Face ID covers the unlock and the sign-in behind it.
enum Keychain {
    private static var service: String { AppConfig.current.appBundleID + ".credentials" }

    /// Never evaluated and never allowed to ask: reads with it only work for items without a lock.
    nonisolated(unsafe) private static let silent: LAContext = {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        return ctx
    }()

    /// Keeps the password behind user presence. False when the device can't check that (no
    /// passcode set): then nothing is kept and the next sign-in asks for the password again.
    @discardableResult
    static func set(password: String, for username: String) -> Bool {
        let account = AccountRoster.key(username)
        SecItemDelete(query(account) as CFDictionary)
        guard Biometric.available,
              let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil)
        else { return false }
        var add = query(account)
        add[kSecValueData as String] = Data(password.utf8)
        add[kSecAttrAccessControl as String] = access
        add[kSecAttrSynchronizable as String] = false
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// The password, read with a context the person already confirmed. nil without one.
    static func password(for username: String, context: LAContext?) -> String? {
        var q = query(AccountRoster.key(username))
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationContext as String] = context ?? silent
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Only while the app is unlocked; never asks.
    static func password(for username: String) -> String? {
        password(for: username, context: UnlockSession.context)
    }

    /// Whether a password is kept, without reading it (attributes need no Face ID).
    static func exists(username: String) -> Bool {
        var q = query(AccountRoster.key(username))
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnAttributes as String] = true
        q[kSecUseAuthenticationContext as String] = silent
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete(username: String) {
        SecItemDelete(query(AccountRoster.key(username)) as CFDictionary)
    }

    /// Every saved password, also from older builds. Deleting needs no Face ID.
    static func purgeAll() {
        for svc in [service] + Legacy.services {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: svc,
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary)
        }
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    // ── Older builds ──────────────────────────────────────────────────────────

    /// Builds up to 2.1.0 kept the password AES-sealed under a key that sat next to it in the
    /// Keychain, readable without Face ID. Their names are fixed, they're what those builds used.
    private enum Legacy {
        static let credentials = "com.pokyh.credentials"
        static let masterKey = "com.pokyh.masterkey"
        static let masterKeyAccount = "aes-gcm-key-v1"
        static var services: [String] { [credentials, masterKey] }
    }

    enum MigrationResult { case done, retryLater }

    /// Moves passwords of the sealed format behind Face ID. A password that can't be moved
    /// (no passcode on the device) is dropped, that account asks for it once.
    static func migrateSealedPasswords(of usernames: [String]) -> MigrationResult {
        switch legacyRead(service: Legacy.masterKey, account: Legacy.masterKeyAccount) {
        case .locked:
            return .retryLater
        case .missing:
            break
        case .found(let key):
            for username in usernames {
                let account = username.lowercased()
                switch legacyRead(service: Legacy.credentials, account: account) {
                case .locked: return .retryLater
                case .missing: continue
                case .found(let sealed):
                    if let plain = AppCrypto.open(sealed, keyData: key) {
                        set(password: String(decoding: plain, as: UTF8.self), for: username)
                    }
                }
            }
        }
        for svc in Legacy.services {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: svc] as CFDictionary)
        }
        return .done
    }

    private enum LegacyRead { case found(Data), missing, locked }

    private static func legacyRead(service: String, account: String) -> LegacyRead {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: silent,
        ] as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .missing }
            return .found(data)
        case errSecInteractionNotAllowed:
            // Phone not unlocked since boot (background launch): try again next time.
            return .locked
        default:
            return .missing
        }
    }
}

/// The Face ID / passcode check the app was unlocked with. Kept so the passwords can be read
/// again without asking (sign-in, silent renewal, pairing the watch) until the app locks.
enum UnlockSession {
    private(set) static var context: LAContext?

    static func begin(_ ctx: LAContext) {
        if context !== ctx { context?.invalidate() }
        // From here on it only vouches; it never puts up a sheet of its own.
        ctx.interactionNotAllowed = true
        context = ctx
    }

    static func end() {
        context?.invalidate()
        context = nil
    }
}

/// Face ID / Touch ID with the device passcode as the fallback (`.deviceOwnerAuthentication`).
/// What the device has is asked once with a context kept alive: short-lived contexts made on
/// every render crashed the app (`-[OS_dispatch_mach_msg _setContext:]`).
nonisolated enum Biometric {
    enum Kind: Sendable { case faceID, touchID, opticID, passcode }

    struct Info: Sendable {
        let available: Bool
        let kind: Kind
        let symbol: String
        /// False until the device was asked; that first call is slow and runs off the main thread.
        var known = true

        /// Apple's own name for it; the passcode has no brand name, so it gets none.
        var typeName: String {
            switch kind {
            case .faceID: "Face ID"
            case .touchID: "Touch ID"
            case .opticID: "Optic ID"
            case .passcode: "Code"
            }
        }

        static let unknown = Info(available: false, kind: .passcode, symbol: "lock.fill", known: false)
    }

    nonisolated(unsafe) private static let probeContext = LAContext()

    static let info: Info = {
        let ok = probeContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch probeContext.biometryType {
        case .faceID:  return Info(available: ok, kind: .faceID, symbol: "faceid")
        case .touchID: return Info(available: ok, kind: .touchID, symbol: "touchid")
        case .opticID: return Info(available: ok, kind: .opticID, symbol: "opticid")
        default:       return Info(available: ok, kind: .passcode, symbol: "lock.fill")
        }
    }()

    static var available: Bool { info.available }
    static var typeName: String { info.typeName }
    static var symbol: String { info.symbol }

    /// Runs the check; on success the context is returned so the Keychain can use it without
    /// asking again. nil when cancelled, failed or not possible on this device.
    @MainActor
    static func authenticate(reason: String) async -> LAContext? {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return nil }
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                cont.resume(returning: success)
            }
        }
        return ok ? ctx : nil
    }
}

extension Biometric.Info {
    /// Android's texts say "Biometrie"; on Apple devices they name what the device has.
    func phrase(_ text: String, _ lang: Lang) -> String {
        let name: String
        switch kind {
        case .passcode:
            switch lang {
            case .de: name = "Gerätecode"
            case .it: name = "codice del dispositivo"
            case .en: name = "device passcode"
            }
        default:
            name = typeName
        }
        var out = text
        for word in ["la biometria", "Biometrie", "biometria", "Biometria", "biometrics", "Biometrics"] {
            out = out.replacingOccurrences(of: word, with: name)
        }
        return out
    }
}

/// The saved accounts: the list in UserDefaults (names, class, picture, school; no secrets),
/// the passwords in the Keychain behind Face ID.
@MainActor
final class CredentialStore {
    static let shared = CredentialStore()
    nonisolated private static let accountsKey = "pokyh_accounts"
    private let lastActiveKey = "pokyh_last_active"
    private let defaultKey = "pokyh_default_account"
    /// Survives "clear all data", see AppState.clearAllData.
    static let formatDefaultsKey = "pokyh_keychain_format"
    private var formatKey: String { Self.formatDefaultsKey }
    /// 4 = AES-sealed next to its key, 5 = one item per account behind `.userPresence`.
    private let currentFormat = 5
    private let sealedFormat = 4

    private init() { migrateKeychainIfNeeded() }

    /// The sealed format moves over without asking anyone to sign in again. Anything older (or
    /// a fresh install finding items an earlier install left behind) is cleared.
    private func migrateKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        let format = defaults.integer(forKey: formatKey)
        guard format != currentFormat else { return }
        if format == sealedFormat {
            guard Keychain.migrateSealedPasswords(of: accounts.map(\.username)) == .done else { return }
        } else {
            Keychain.purgeAll()
        }
        defaults.set(currentFormat, forKey: formatKey)
    }

    var accounts: [SavedAccount] {
        guard let data = UserDefaults.standard.data(forKey: Self.accountsKey),
              let list = try? JSONDecoder().decode([SavedAccount].self, from: data) else { return [] }
        return list
    }

    var lastActive: String? {
        get { UserDefaults.standard.string(forKey: lastActiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastActiveKey) }
    }

    /// Standard-Konto: das erste gespeicherte, in den Einstellungen änderbar.
    var defaultUsername: String? {
        get { UserDefaults.standard.string(forKey: defaultKey) ?? accounts.first?.username }
        set { UserDefaults.standard.set(newValue, forKey: defaultKey) }
    }

    /// Saves the account and, when the device can protect it, its password. Signing in again
    /// keeps the account's place, nickname, picture and school.
    func save(_ account: SavedAccount, password: String) {
        persist(AccountRoster.upsert(account, into: accounts) { new, old in
            if new.nickname == nil { new.nickname = old.nickname }
            if new.imageUrl == nil { new.imageUrl = old.imageUrl }
            if new.school == nil { new.school = old.school }
        })
        Keychain.set(password: password, for: account.username)
        lastActive = account.username
        if UserDefaults.standard.string(forKey: defaultKey) == nil {
            defaultUsername = account.username
        }
    }

    /// The school a saved account signs in at, read straight from the defaults so code off the
    /// main actor (background refresh) can ask too.
    nonisolated static func savedSchool(for username: String) -> School? {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let list = try? JSONDecoder().decode([SavedAccountSchool].self, from: data) else { return nil }
        return AccountRoster.find(username, in: list)?.school
    }

    func password(for username: String, context: LAContext?) -> String? {
        Keychain.password(for: username, context: context)
    }

    func hasPassword(_ username: String) -> Bool { Keychain.exists(username: username) }

    /// Abmelden: nur das gespeicherte Passwort entfernen, Konto bleibt in der Liste.
    func signOut(_ username: String) { Keychain.delete(username: username) }

    /// Lokalen Spitznamen setzen/entfernen (leer → entfernen). Berührt keine Credentials.
    func setNickname(_ nickname: String?, for username: String) {
        update(username) { account in
            let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
            account.nickname = (trimmed?.isEmpty == false) ? trimmed : nil
        }
    }

    /// Anzeigenamen (Klasse) eines Kontos aktualisieren — z. B. nach „Konto aktualisieren".
    func updateDisplayName(_ displayName: String, for username: String) {
        update(username) { $0.displayName = displayName }
    }

    /// Profilbild-URL eines gespeicherten Kontos aktualisieren (auch beim stillen
    /// Re-Login, damit die Konten-Liste das Bild zeigt). No-op, wenn unverändert.
    func updateImageUrl(_ imageUrl: String?, for username: String) {
        guard let imageUrl, !imageUrl.isEmpty,
              AccountRoster.find(username, in: accounts)?.imageUrl != imageUrl else { return }
        update(username) { $0.imageUrl = imageUrl }
    }

    func remove(_ username: String) {
        let remaining = AccountRoster.removing(username, from: accounts)
        persist(remaining)
        Keychain.delete(username: username)
        lastActive = AccountRoster.successor(for: lastActive, removed: username, remaining: remaining)
        let storedDefault = UserDefaults.standard.string(forKey: defaultKey)
        defaultUsername = AccountRoster.successor(for: storedDefault, removed: username, remaining: remaining)
    }

    private func update(_ username: String, _ change: (inout SavedAccount) -> Void) {
        var list = accounts
        guard let index = list.firstIndex(where: { AccountRoster.same($0.username, username) }) else { return }
        change(&list[index])
        persist(list)
    }

    private func persist(_ list: [SavedAccount]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.accountsKey)
        }
    }
}

extension SavedAccount: RosterEntry {}

/// Just the part of a saved account that says where it signs in.
nonisolated private struct SavedAccountSchool: Decodable, RosterEntry {
    var username: String
    var school: School?
}
