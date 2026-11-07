import Foundation
import Network
import Observation
import PokyhCore

/// Whether the device has any way out. Without one the unlock opens the stored copy at once
/// instead of waiting for a sign-in that can't work, and coming back online signs in again.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    /// Low Data Mode is on: nothing is fetched ahead of a tap.
    private(set) var lowData = false
    /// Set by AppState: the connection is back.
    @ObservationIgnored var onReconnect: (() -> Void)?
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let constrained = path.isConstrained
            Task { @MainActor in self?.update(online, constrained: constrained) }
        }
        monitor.start(queue: DispatchQueue(label: "pokyh.network"))
    }

    private func update(_ online: Bool, constrained: Bool) {
        let cameBack = online && !isOnline
        if lowData != constrained { lowData = constrained }
        if isOnline != online { isOnline = online }
        if cameBack { onReconnect?() }
    }
}

/// New to-dos and reminders made offline, waiting for a connection (Android's Outbox). Each
/// account's queue is sealed in that account's offline folder, so it goes with it on sign-out.
/// Ticking, editing and deleting aren't queued: they act on what the server has, and doing them
/// blind could undo someone else's change. Those say "not available offline" instead.
@MainActor
@Observable
final class Outbox {
    static let shared = Outbox()

    private var queues: [String: PendingQueue] = [:]
    @ObservationIgnored private var flushing: Set<String> = []
    private static let key = "outbox"

    /// Reads the account's queue from disk, once.
    func prepare(_ username: String) {
        let owner = AccountRoster.key(username)
        guard queues[owner] == nil else { return }
        queues[owner] = DiskCache.load(PendingQueue.self, key: Self.key, owner: username) ?? PendingQueue()
    }

    func items(_ kind: PendingItem.Kind, for username: String) -> [PendingItem] {
        queues[AccountRoster.key(username)]?.of(kind) ?? []
    }

    /// False when the queue is full.
    @discardableResult
    func add(_ kind: PendingItem.Kind, title: String, text: String, date: String?, for username: String) -> Bool {
        prepare(username)
        let owner = AccountRoster.key(username)
        guard queues[owner]?.add(PendingItem(kind: kind, title: title, text: text, date: date)) == true else { return false }
        persist(owner, username)
        return true
    }

    func remove(_ id: String, for username: String) {
        let owner = AccountRoster.key(username)
        queues[owner]?.remove(id)
        persist(owner, username)
    }

    /// Sends what the signed-in account queued. Stops at the first connection problem; an item
    /// the server refuses is dropped.
    func flush(_ s: UserSession) async {
        prepare(s.username)
        let owner = AccountRoster.key(s.username)
        guard s.apiToken != nil, !flushing.contains(owner), let pending = queues[owner]?.items, !pending.isEmpty else { return }
        flushing.insert(owner)
        defer { flushing.remove(owner) }
        let client = BackendClient.shared
        for item in pending {
            guard let token = s.apiToken else { return }
            do {
                switch item.kind {
                case .todo:
                    _ = try await client.createTodo(username: s.username, title: item.title, details: item.text, dueAt: item.date, token: token)
                case .reminder:
                    // No class known yet: keep it until there is one.
                    guard let classId = await client.classId(s), let date = item.date else { continue }
                    _ = try await client.createReminder(classId: classId, title: item.title, body: item.text, remindAt: date, token: token)
                }
            } catch {
                let status = (error as? AppError)?.status
                if PendingQueue.keepsForLater(status: status, connectionLost: error is URLError) { return }
            }
            remove(item.id, for: s.username)
        }
    }

    /// Signed out or removed: the files go with the account's folder, this is the copy in memory.
    func forget(_ username: String) {
        queues[AccountRoster.key(username)] = nil
    }

    func clearAll() {
        queues = [:]
    }

    private func persist(_ owner: String, _ username: String) {
        guard let queue = queues[owner] else { return }
        if queue.items.isEmpty {
            DiskCache.remove(key: Self.key, owner: username)
        } else {
            DiskCache.save(queue, key: Self.key, owner: username)
        }
    }
}
