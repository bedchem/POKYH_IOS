import Foundation

/// Anything kept per saved account.
public protocol RosterEntry {
    var username: String { get }
}

/// The list of saved accounts on this device. WebUntis doesn't care about case in user
/// names and the Keychain items are keyed lowercased, so neither does this.
public enum AccountRoster {
    public static func key(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func same(_ a: String, _ b: String) -> Bool {
        key(a) == key(b)
    }

    public static func find<E: RosterEntry>(_ username: String, in list: [E]) -> E? {
        list.first { same($0.username, username) }
    }

    /// Replaces the account where it is (signing in again doesn't reorder the list) or adds it
    /// at the end. `merge` gets the new record and the old one to carry over what the new one lacks.
    public static func upsert<E: RosterEntry>(_ entry: E, into list: [E], merge: (inout E, E) -> Void = { _, _ in }) -> [E] {
        var list = list
        guard let index = list.firstIndex(where: { same($0.username, entry.username) }) else {
            list.append(entry)
            return list
        }
        var updated = entry
        merge(&updated, list[index])
        list[index] = updated
        // Older builds could leave the same account twice under different case.
        let duplicates = list.indices.filter { $0 != index && same(list[$0].username, entry.username) }
        for i in duplicates.reversed() { list.remove(at: i) }
        return list
    }

    public static func removing<E: RosterEntry>(_ username: String, from list: [E]) -> [E] {
        list.filter { !same($0.username, username) }
    }

    /// What a pointer like "last active" or "default" should say once `removed` is gone: the
    /// same account if it wasn't that one, otherwise the first one left.
    public static func successor<E: RosterEntry>(for pointer: String?, removed: String, remaining: [E]) -> String? {
        guard let pointer, !same(pointer, removed) else { return remaining.first?.username }
        return pointer
    }
}
