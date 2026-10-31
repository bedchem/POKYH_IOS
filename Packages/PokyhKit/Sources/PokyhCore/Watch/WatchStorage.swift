import Foundation
import Security

/// The watch's last snapshot and its unsent to-do ticks, sealed with the vault key, in the
/// app group the complications read from.
public struct WatchStore: Sendable {
    static let snapshotName = "watch.snapshot"
    static let queueName = "watch.todoQueue"

    let files: SealedFiles

    public init(files: SealedFiles) {
        self.files = files
    }

    public func snapshot() -> WatchSnapshot? {
        files.read(Self.snapshotName).flatMap(WatchSnapshot.decoded(from:))
    }

    @discardableResult
    public func save(_ snapshot: WatchSnapshot) -> Bool {
        guard let data = try? snapshot.encoded() else { return false }
        return files.write(data, name: Self.snapshotName)
    }

    public func queue() -> TodoQueue {
        guard let data = files.read(Self.queueName),
              let queue = try? JSONDecoder().decode(TodoQueue.self, from: data) else { return TodoQueue() }
        return queue
    }

    public func save(_ queue: TodoQueue) {
        guard !queue.isEmpty else {
            files.remove(Self.queueName)
            return
        }
        if let data = try? JSONEncoder().encode(queue) { files.write(data, name: Self.queueName) }
    }

    /// Signed out: nothing of the account stays on the watch.
    public func clear() {
        files.removeAll()
    }
}

extension WatchStore {
    /// Info.plist key for the watch's own app group (see project.yml).
    static let appGroupKey = "POKYHWatchAppGroup"

    /// The store the watch app and its complications share. Only the app makes the key, the
    /// complications read it (`createsKey: false`) and never delete what they can't open.
    public static func shared(bundle: Bundle = .main, config: AppConfig = .current, createsKey: Bool) -> WatchStore {
        let group = bundle.object(forInfoDictionaryKey: appGroupKey) as? String ?? ""
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let key = WatchVaultKey(service: config.appBundleID + ".watch.vault", creates: createsKey)
        let files = SealedFiles(
            directory: base.appendingPathComponent("Sealed/watch", isDirectory: true),
            protection: .untilFirstUnlock,
            dropsUnreadable: createsKey
        ) { key.vault() }
        return WatchStore(files: files)
    }
}

/// The vault key in the watch's Keychain. App and complications share the watch keychain group
/// as their default one, so neither names it.
final class WatchVaultKey: @unchecked Sendable {
    private let store: VaultKeyStore
    private let creates: Bool
    private let lock = NSLock()
    private var cached: Vault?

    init(service: String, creates: Bool) {
        store = VaultKeyStore(store: KeychainStore(service: service))
        self.creates = creates
    }

    func vault() -> Vault? {
        lock.withLock {
            if let cached { return cached }
            // Locked before the first unlock: no key now, ask again next time.
            let vault = try? store.vault(create: creates)
            // The complication reads it fresh each time, so it sees a key the app just made.
            if creates { cached = vault }
            return vault
        }
    }
}
