import Foundation
import PokyhCore

/// Offline copies on disk (timetable, grades, messages, to-dos, the token-less session snapshot),
/// so the app opens and shows its last good state without a network. Never credentials or tokens.
/// Sealed with the vault key, readable only while the phone is unlocked, in the app's own
/// container (widgets don't need it). Each account has a folder of its own, so signing out
/// takes all of its data at once; `owner: nil` is what any account may read (school holidays,
/// the menu).
nonisolated enum DiskCache {
    /// Sealing and opening cost real time (AES-GCM, JSON); none of it belongs on the main thread.
    /// One queue keeps a read behind the writes before it.
    private static let queue = DispatchQueue(label: "pokyh.offline", qos: .utility)
    private static let files = SealedFiles(
        directory: SecureStorage.directory("offline"),
        protection: .complete
    ) { LocalVault.current() }

    /// What nobody wrote again in this time goes: old weeks, messages long gone from the inbox.
    private static let maxAge: TimeInterval = 45 * 86_400
    private static let prunedKey = "pokyh_offline_pruned"

    private static func store(_ owner: String?) -> SealedFiles? {
        guard let owner else { return files }
        return files.folder(AccountRoster.key(owner))
    }

    /// Written in the background; nothing waits for it.
    static func save<T: Encodable>(_ value: T, key: String, owner: String?) {
        let target = store(owner)
        queue.async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            target?.write(data, name: key)
        }
    }

    /// For the few callers that can't wait; screens use `loaded`.
    static func load<T: Decodable>(_ type: T.Type, key: String, owner: String?) -> T? {
        let target = store(owner)
        return queue.sync {
            guard let data = target?.read(key) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
    }

    /// The same, read and decoded off the main thread.
    static func loaded<T: Decodable>(_ type: T.Type, key: String, owner: String?) async -> T? {
        let target = store(owner)
        return await withCheckedContinuation { done in
            queue.async {
                let value = target?.read(key).flatMap { try? JSONDecoder().decode(type, from: $0) }
                done.resume(returning: value)
            }
        }
    }

    static func remove(key: String, owner: String?) {
        let target = store(owner)
        queue.async { target?.remove(key) }
    }

    /// Shared copies: what isn't any one account's.
    static func save<T: Encodable>(_ value: T, key: String) { save(value, key: key, owner: nil) }
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? { load(type, key: key, owner: nil) }
    static func remove(key: String) { remove(key: key, owner: nil) }

    /// Everything one account left on this device.
    static func forget(owner: String) {
        queue.sync { files.removeFolder(AccountRoster.key(owner)) }
    }

    /// Once a day, after an online sign-in: offline, the old copies are all there is.
    static func pruneIfDue(now: Date = .now) {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: prunedKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) > 86_400 else { return }
        defaults.set(now, forKey: prunedKey)
        queue.async { files.prune(olderThan: maxAge, now: now) }
    }

    /// Every account's offline data.
    static func purge() {
        queue.sync { files.removeAll() }
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
    nonisolated static func directory(_ name: String, caches: Bool = false) -> URL {
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
