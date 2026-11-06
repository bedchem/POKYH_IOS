import Foundation

/// A to-do or reminder made without a connection, waiting to be sent. Android's Outbox.
public struct PendingItem: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case todo, reminder }

    public var id: String
    public var kind: Kind
    public var title: String
    /// The to-do's details or the reminder's text.
    public var text: String
    /// When it's due (to-do) or when to remind (reminder), ISO 8601.
    public var date: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, kind: Kind, title: String, text: String, date: String?, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.date = date
        self.createdAt = createdAt
    }
}

/// One account's queue, oldest first. It only ever holds what that account typed, so it's kept
/// with that account's other offline data and goes with it on sign-out.
public struct PendingQueue: Codable, Sendable, Equatable {
    /// Nobody types more than this offline; a runaway loop mustn't fill the disk.
    public static let limit = 50

    public private(set) var items: [PendingItem]

    public init(items: [PendingItem] = []) {
        self.items = items
    }

    public func of(_ kind: PendingItem.Kind) -> [PendingItem] {
        items.filter { $0.kind == kind }
    }

    /// False when the queue is full.
    @discardableResult
    public mutating func add(_ item: PendingItem) -> Bool {
        guard items.count < Self.limit else { return false }
        items.append(item)
        return true
    }

    public mutating func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// Whether a send that failed should be tried again later: no connection, the server
    /// struggling, or an expired token (the next sign-in brings a new one). Anything else is the
    /// server refusing the item itself, and retrying that forever helps nobody.
    public static func keepsForLater(status: Int?, connectionLost: Bool) -> Bool {
        if connectionLost { return true }
        guard let status else { return true }
        return status >= 500 || status == 401 || status == 408 || status == 429
    }
}
