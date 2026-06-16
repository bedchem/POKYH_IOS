import Foundation
import LocalAuthentication
import Security

/// Sicherer Passwortspeicher.
///
/// Zwei Verschlüsselungsebenen:
/// 1. **App-Ebene:** Das Passwort wird mit **AES-GCM (256-bit, CryptoKit)** ver-
///    schlüsselt. Der Master-Key liegt selbst im Keychain (gerätegebunden,
///    `…WhenUnlockedThisDeviceOnly`) und verlässt das Gerät nie.
/// 2. **System-Ebene:** Sowohl Key als auch Chiffrat liegen im iOS-Keychain, der
///    sie hardwaregestützt (Secure-Enclave-abgeleitet) erneut verschlüsselt und
///    NICHT in iCloud/Backups synchronisiert.
///
/// Der Zugriff ist zusätzlich app-seitig durch Face ID / Touch ID gegated
/// (`Biometric.authenticate` vor jedem Lesen in `AppState`). Bewusst KEINE
/// `SecAccessControl`-Biometrie am Keychain-Item selbst: das erzwingt einen
/// Geräte-Passcode und ist kontext-/reuse-abhängig — das brach den Kontowechsel.
/// Ein WebUntis-Passwort muss zum Re-Login im Klartext vorliegen und kann daher
/// nicht als Einweg-Hash gespeichert werden.
enum Keychain {
    private static let service = "com.pokyh.credentials"
    private static let keyService = "com.pokyh.masterkey"
    private static let keyAccount = "aes-gcm-key-v1"

    // ── Öffentliche API ────────────────────────────────────────────────────────

    static func set(password: String, for username: String) {
        guard let combined = AppCrypto.seal(Data(password.utf8), keyData: masterKey()) else { return }
        store(combined, service: service, account: username.lowercased())
    }

    static func password(for username: String) -> String? {
        guard let combined = read(service: service, account: username.lowercased()),
              let plain = AppCrypto.open(combined, keyData: masterKey()) else { return nil }
        return String(decoding: plain, as: UTF8.self)
    }

    /// Existenzprüfung OHNE Entschlüsselung und OHNE jeglichen UI-Prompt.
    /// `kSecUseAuthenticationUIFail` verhindert, dass ein evtl. biometrie-geschützter
    /// (alter) Eintrag beim Render Face ID auslöst und den Main-Thread blockiert.
    static func exists(username: String) -> Bool {
        var q = baseQuery(service: service, account: username.lowercased())
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete(username: String) {
        SecItemDelete(baseQuery(service: service, account: username.lowercased()) as CFDictionary)
    }

    /// Entfernt ALLE Einträge der App (Credentials + Master-Key). `SecItemDelete`
    /// erfordert keine Authentifizierung → kein Prompt, auch bei alten ACL-Einträgen.
    static func purgeAll() {
        for svc in [service, keyService] {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: svc,
            ] as CFDictionary)
        }
    }

    // ── AES-Master-Key (einmal erzeugt, dann wiederverwendet) ──────────────────

    private static func masterKey() -> Data {
        if let data = read(service: keyService, account: keyAccount) { return data }
        let data = AppCrypto.newKey()
        store(data, service: keyService, account: keyAccount)
        return data
    }

    // ── Low-Level Keychain ─────────────────────────────────────────────────────

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func store(_ data: Data, service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        var q = baseQuery(service: service, account: account)
        q[kSecValueData as String] = data
        // AfterFirstUnlock: auch für Hintergrund-Abruf (Background App Refresh) lesbar,
        // bleibt gerätegebunden + nicht in iCloud/Backups. Interaktiver Zugriff ist
        // zusätzlich app-seitig durch Face ID gegated.
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func read(service: String, account: String) -> Data? {
        var q = baseQuery(service: service, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }
}

/// Biometrische Entsperrung (Face ID / Touch ID).
/// `nonisolated`: LocalAuthentication darf von jedem Kontext genutzt werden.
/// Die Verfügbarkeit/Art wird EINMAL mit einem dauerhaft gehaltenen Context
/// ermittelt — verhindert, dass bei jedem View-Render kurzlebige LAContexts
/// erzeugt und sofort wieder freigegeben werden (das verursachte den Crash
/// `-[OS_dispatch_mach_msg _setContext:]`).
nonisolated enum Biometric {
    struct Info: Sendable { let available: Bool; let typeName: String; let symbol: String }

    nonisolated(unsafe) private static let probeContext = LAContext()

    static let info: Info = {
        let ok = probeContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch probeContext.biometryType {
        case .faceID:  return Info(available: ok, typeName: "Face ID", symbol: "faceid")
        case .touchID: return Info(available: ok, typeName: "Touch ID", symbol: "touchid")
        default:       return Info(available: ok, typeName: "Code", symbol: "lock.fill")
        }
    }()

    static var available: Bool { info.available }
    static var typeName: String { info.typeName }
    static var symbol: String { info.symbol }

    static func authenticate(reason: String) async -> Bool {
        // Eigener Context pro Authentifizierung; bleibt während des `await` am Leben.
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Code eingeben"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                cont.resume(returning: success)
            }
        }
    }
}

/// Liste gespeicherter Konten (Metadaten in UserDefaults, Passwörter verschlüsselt
/// im Keychain).
@MainActor
final class CredentialStore {
    static let shared = CredentialStore()
    private let accountsKey = "pokyh_accounts"
    private let lastActiveKey = "pokyh_last_active"
    private let defaultKey = "pokyh_default_account"
    private let formatKey = "pokyh_keychain_format"
    private let currentFormat = 4   // 4 = AES-GCM, AfterFirstUnlock (BG-fähig)

    private init() { migrateKeychainIfNeeded() }

    /// Einmalige Migration: ältere Builds speicherten Passwörter im Klartext bzw. mit
    /// biometrischer Zugriffskontrolle (`.userPresence`). Solche Einträge sind mit dem
    /// AES-Format inkompatibel UND lösten beim Lesen Face-ID-Prompts/Hänger aus.
    /// Beim ersten Start des neuen Formats werden sie bereinigt (kein Prompt) → der
    /// Nutzer meldet sich einmal neu an.
    private func migrateKeychainIfNeeded() {
        guard UserDefaults.standard.integer(forKey: formatKey) != currentFormat else { return }
        Keychain.purgeAll()
        UserDefaults.standard.set(currentFormat, forKey: formatKey)
    }

    var accounts: [SavedAccount] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
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

    func save(_ account: SavedAccount, password: String) {
        // Vorhandenen Spitznamen erhalten (z. B. bei „Konto aktualisieren"/Re-Login),
        // falls der neue Datensatz selbst keinen mitbringt.
        var account = account
        if account.nickname == nil,
           let existing = accounts.first(where: { $0.username == account.username })?.nickname {
            account.nickname = existing
        }
        var list = accounts.filter { $0.username != account.username }
        list.append(account)
        persist(list)
        Keychain.set(password: password, for: account.username)
        lastActive = account.username
        if UserDefaults.standard.string(forKey: defaultKey) == nil {
            defaultUsername = account.username
        }
    }

    func password(for username: String) -> String? { Keychain.password(for: username) }
    func hasPassword(_ username: String) -> Bool { Keychain.exists(username: username) }

    /// Abmelden: nur das gespeicherte Passwort entfernen, Konto bleibt in der Liste.
    func signOut(_ username: String) { Keychain.delete(username: username) }

    /// Lokalen Spitznamen setzen/entfernen (leer → entfernen). Berührt keine Credentials.
    func setNickname(_ nickname: String?, for username: String) {
        var list = accounts
        guard let idx = list.firstIndex(where: { $0.username == username }) else { return }
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        list[idx].nickname = (trimmed?.isEmpty == false) ? trimmed : nil
        persist(list)
    }

    /// Anzeigenamen (Klasse) eines Kontos aktualisieren — z. B. nach „Konto aktualisieren".
    func updateDisplayName(_ displayName: String, for username: String) {
        var list = accounts
        guard let idx = list.firstIndex(where: { $0.username == username }) else { return }
        list[idx].displayName = displayName
        persist(list)
    }

    func remove(_ username: String) {
        persist(accounts.filter { $0.username != username })
        Keychain.delete(username: username)
        if lastActive == username { lastActive = accounts.first?.username }
        if defaultUsername == username { defaultUsername = accounts.first?.username }
    }

    private func persist(_ list: [SavedAccount]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }
}
