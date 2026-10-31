import Foundation

/// What the watch asks the phone for. Plain property-list dictionaries, like `AccountHandoff`.
public enum WatchRequest {
    static let snapshotKey = "pokyh.requestSnapshot"

    /// "Send me what you have", answered with a snapshot payload.
    public static var snapshot: [String: Any] { [snapshotKey: true] }

    public static func isSnapshotRequest(_ message: [String: Any]) -> Bool {
        message[snapshotKey] as? Bool == true
    }
}

/// A to-do ticked (or unticked) on the watch, on its way to the phone.
public struct TodoToggle: Codable, Sendable, Hashable {
    public var id: String
    public var done: Bool
    public var at: Date

    public init(id: String, done: Bool, at: Date = .now) {
        self.id = id
        self.done = done
        self.at = at
    }

    static let key = "pokyh.toggleTodo"

    public var payload: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data]
    }

    public init?(payload: [String: Any]) {
        guard let data = payload[Self.key] as? Data,
              let toggle = try? JSONDecoder().decode(TodoToggle.self, from: data) else { return nil }
        self = toggle
    }

    /// The backend's `doneAt`: when it was ticked, ISO 8601 as the web sends it.
    public var doneAt: String? {
        done ? ISO8601DateFormatter().string(from: at) : nil
    }
}

/// How the phone dealt with a `TodoToggle`.
public enum TodoToggleResult: String, Sendable {
    /// Saved at the backend.
    case applied
    /// The backend said no (the to-do is gone, say); the snapshot in the reply is what's true.
    case rejected
    /// The phone can't right now (locked, offline); keep it and try again later.
    case later

    static let key = "pokyh.toggleResult"

    /// The reply, with the phone's snapshot after the change where it has one.
    public func reply(with snapshot: WatchSnapshot?) -> [String: Any] {
        var reply: [String: Any] = [Self.key: rawValue]
        if let snapshot { reply.merge(snapshot.payload) { $1 } }
        return reply
    }

    public init?(reply: [String: Any]) {
        guard let raw = reply[Self.key] as? String, let result = TodoToggleResult(rawValue: raw) else { return nil }
        self = result
    }
}

/// The watch's ticks the phone hasn't confirmed yet. One per to-do: ticking and unticking
/// again before it went out leaves nothing to send.
public struct TodoQueue: Codable, Sendable, Equatable {
    public private(set) var items: [TodoToggle]

    public init(items: [TodoToggle] = []) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }

    public func pending(for id: String) -> TodoToggle? {
        items.first { $0.id == id }
    }

    /// Adds a tick. `shownDone` is what the phone last said; going back to it cancels the tick.
    public mutating func toggle(_ id: String, to done: Bool, phoneSays shownDone: Bool, at date: Date = .now) {
        items.removeAll { $0.id == id }
        if done != shownDone { items.append(TodoToggle(id: id, done: done, at: date)) }
    }

    public mutating func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// Drops what a new snapshot already shows, or what isn't in it any more.
    public mutating func settle(with snapshot: WatchSnapshot) {
        items.removeAll { item in
            guard let todo = snapshot.todos.first(where: { $0.id == item.id }) else { return true }
            return todo.done == item.done
        }
    }
}
