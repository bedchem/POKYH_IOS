import Foundation

/// When the app locks itself again after being away. Measured on the continuous clock, which
/// keeps running while the phone sleeps and can't be wound back in Settings.
public struct AutoLock: Sendable, Equatable {
    /// Ten minutes in the background, same as Android.
    public static let standardInterval: Duration = .seconds(600)

    public let interval: Duration
    private(set) var leftAt: ContinuousClock.Instant?

    public init(interval: Duration = AutoLock.standardInterval) {
        self.interval = interval
    }

    /// The app went to the background. Only a signed-in app has anything to lock.
    public mutating func didLeave(signedIn: Bool, at now: ContinuousClock.Instant = .now) {
        guard signedIn else { leftAt = nil; return }
        // A second background event (say after a background refresh) keeps the first time.
        if leftAt == nil { leftAt = now }
    }

    /// Whether the time is up, without coming back (background work checks this).
    public func isDue(at now: ContinuousClock.Instant = .now) -> Bool {
        guard let leftAt else { return false }
        return now - leftAt >= interval
    }

    /// The app is on screen again: whether it has to lock first.
    public mutating func didReturn(at now: ContinuousClock.Instant = .now) -> Bool {
        defer { leftAt = nil }
        return isDue(at: now)
    }
}
