import Foundation
import PokyhCore

/// Offline copies on disk (timetable, grades, the token-less session snapshot), so the app
/// still shows something without a network. Never credentials. Sealed with the vault key,
/// readable only while the phone is unlocked, in the app's own container (widgets don't need it).
enum DiskCache {
    private static let files = SealedFiles(
        directory: SecureStorage.directory("offline"),
        protection: .complete
    ) { LocalVault.current() }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        files.write(data, name: key)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = files.read(key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(key: String) {
        files.remove(key)
    }

    /// Löscht ALLE persistierten Offline-Daten (alle Nutzer).
    static func purge() {
        files.removeAll()
    }
}

/// Where the sealed folders live, and the one-time cleanup of what older builds left in plain text.
enum SecureStorage {
    /// Survives "clear all data", see AppState.clearAllData.
    static let formatDefaultsKey = "pokyh_storage_format"
    private static var formatKey: String { formatDefaultsKey }
    /// 2 = everything sealed with the vault key.
    private static let currentFormat = 2

    /// A folder in the app's own Application Support (or Caches for what may be thrown away).
    static func directory(_ name: String, caches: Bool = false) -> URL {
        let base = (try? FileManager.default.url(
            for: caches ? .cachesDirectory : .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sealed", isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }

    /// Old plain files go rather than being converted; it all loads again on the next sign-in.
    /// Runs at launch before anything reads or writes.
    static func prepare() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: formatKey) < currentFormat else { return }
        let fm = FileManager.default
        for name in ["offline", "images"] {
            try? fm.removeItem(at: AppGroup.containerURL.appendingPathComponent(name, isDirectory: true))
        }
        SharedStore.dropLegacyFiles()
        // Nothing sealed is left at this point (first run, or after "clear all data"), so a key
        // an earlier install left in the Keychain can go too.
        DiskCache.purge()
        ImageCache.purge()
        SharedStore.purgeAll()
        LocalVault.destroy()
        defaults.set(currentFormat, forKey: formatKey)
    }
}
