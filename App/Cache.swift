import Foundation

/// Generischer In-Memory-Cache mit Ablaufzeit (TTL) — eine zentrale, saubere
/// Lösung statt verstreuter Dictionaries in jedem Client.
///
/// Bewusst MainActor-isoliert (Default), da alle Clients vom MainActor aus
/// zugreifen → keine Sperren nötig, kein Data-Race.
final class TTLCache<Key: Hashable, Value> {
    private struct Entry { let value: Value; let time: Date }
    private var store: [Key: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval) { self.ttl = ttl }

    /// Gültiger Wert oder nil (wenn fehlend/abgelaufen). Abgelaufene werden entfernt.
    func get(_ key: Key) -> Value? {
        guard let e = store[key] else { return nil }
        if Date().timeIntervalSince(e.time) >= ttl { store[key] = nil; return nil }
        return e.value
    }

    /// Auch abgelaufene Werte (z. B. als Fallback bei Netzwerkfehler).
    func stale(_ key: Key) -> Value? { store[key]?.value }

    func set(_ key: Key, _ value: Value) { store[key] = Entry(value: value, time: Date()) }
    func remove(_ key: Key) { store[key] = nil }
    func removeAll() { store.removeAll() }
}
