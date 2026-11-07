import Foundation

/// An in-memory cache whose entries expire, shared by the clients instead of a
/// dictionary in each.
///
/// Main-actor isolated on purpose: every client uses it from there, so it needs no
/// locks and can't race.
final class TTLCache<Key: Hashable, Value> {
    private struct Entry { let value: Value; let time: Date }
    private var store: [Key: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval) { self.ttl = ttl }

    /// The value while it's fresh, else nil; an expired one is dropped.
    func get(_ key: Key) -> Value? {
        guard let e = store[key] else { return nil }
        if Date().timeIntervalSince(e.time) >= ttl { store[key] = nil; return nil }
        return e.value
    }

    /// Expired ones too, as a fallback when the network fails.
    func stale(_ key: Key) -> Value? { store[key]?.value }

    func set(_ key: Key, _ value: Value) { store[key] = Entry(value: value, time: Date()) }
    func remove(_ key: Key) { store[key] = nil }
    func removeAll() { store.removeAll() }
}
