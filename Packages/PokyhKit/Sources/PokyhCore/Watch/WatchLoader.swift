import Foundation
import Synchronization

/// What one load by the watch itself brought back. A part that failed stays nil.
public struct WatchLoad: Sendable {
    public struct Lessons: Sendable, Equatable {
        public var lessons: [WatchSnapshot.Lesson]
        public var from: Date
        public var until: Date
        public var studentId: Int
    }

    public struct Menu: Sendable, Equatable {
        public var day: Date?
        public var dishes: [WatchSnapshot.Dish]
    }

    public var lessons: Lessons?
    public var grades: WatchGrades?
    public var menu: Menu?
    public var todos: [WatchSnapshot.Todo]?
    /// Some server answered. False when nothing got through: no Wi-Fi, no phone, no cellular.
    public var reachedNetwork = false
    /// This watch was signed out from the account's device list.
    public var revoked = false

    public var isEmpty: Bool { lessons == nil && grades == nil && menu == nil && todos == nil }

    /// The snapshot with what came, everything else as it was. `date` is when the load started:
    /// a part the phone sent fresher while it ran stays the phone's.
    public func applied(to snapshot: WatchSnapshot, at date: Date = .now, calendar: Calendar = .current) -> WatchSnapshot {
        var next = snapshot
        if let lessons, snapshot.updated(.lessons) <= date {
            next = next.withLessons(lessons.lessons, from: lessons.from, until: lessons.until, studentId: lessons.studentId,
                                    source: .watch, at: date, calendar: calendar)
        }
        if let grades, snapshot.updated(.grades) <= date { next = next.withGrades(grades, at: date) }
        if let menu, snapshot.updated(.mensa) <= date { next = next.withMenu(day: menu.day, dishes: menu.dishes, at: date) }
        if let todos, snapshot.updated(.todos) <= date { next = next.withTodos(todos, at: date) }
        return next
    }
}

/// Loads what the watch shows over its own connection (Wi-Fi or cellular, or through the phone
/// when it's near but the iPhone app can't answer): lessons and grades straight from WebUntis
/// with one sign-in, the to-dos and the menu from the POKYH backend.
public struct WatchLoader: Sendable {
    let untis: UntisDay
    let backend: WatchBackend

    public init(untis: UntisDay, backend: WatchBackend) {
        self.untis = untis
        self.backend = backend
    }

    public func load(_ parts: Set<WatchSnapshot.Part>, for account: StoredAccount, studentId: Int?, now: Date = .now,
                     days: Int = 8, calendar: Calendar = .current) async -> WatchLoad {
        let reach = Reach()
        // POKYH-only accounts have no WebUntis account behind them.
        let untisParts = account.backend == .password ? [] : parts.intersection([.lessons, .grades])
        let backendOK = WatchBackend.canSignIn(account)

        // A token at hand, or a sign-in needed for the to-dos.
        var needsSignIn = false
        var tokenFailed = false
        if parts.contains(.todos), backendOK {
            do {
                needsSignIn = try await backend.storedToken(for: account, now: now) == nil
            } catch {
                // Offline, or the backend down: no sign-in either.
                tokenFailed = true
                reach.failed(error)
            }
        }
        let signInHere = needsSignIn && WatchBackend.signsInWithUntis(account)
        let revoked = Mutex(false)
        let signedIn = Mutex(false)
        let backend = backend

        async let menu = parts.contains(.mensa) ? loadMenu(for: account, now: now, calendar: calendar, reach: reach) : nil
        async let visit: UntisVisit? = {
            guard !untisParts.isEmpty || signInHere else { return nil }
            let day = calendar.startOfDay(for: now)
            do {
                let visit = try await untis.visit(
                    account, studentId: studentId,
                    lessonsFrom: untisParts.contains(.lessons) ? day : nil, days: days,
                    grades: untisParts.contains(.grades), calendar: calendar
                ) { sessionId in
                    guard signInHere else { return }
                    do {
                        try await backend.signIn(account, untisSessionId: sessionId)
                        signedIn.withLock { $0 = true }
                        reach.answered()
                    } catch {
                        if error as? WatchBackendError == .revoked { revoked.withLock { $0 = true } }
                        reach.failed(error)
                    }
                }
                reach.answered()
                return visit
            } catch {
                reach.failed(error)
                return nil
            }
        }()
        async let passwordSignIn: Void = {
            guard needsSignIn, account.backend == .password else { return }
            do {
                try await backend.signIn(account, untisSessionId: nil)
                signedIn.withLock { $0 = true }
                reach.answered()
            } catch {
                reach.failed(error)
            }
        }()

        var load = WatchLoad()
        let untisVisit = await visit
        await passwordSignIn
        if let untisVisit {
            let day = calendar.startOfDay(for: now)
            if case .success(let lessons)? = untisVisit.lessons {
                let end = calendar.date(byAdding: .day, value: days, to: day) ?? day
                load.lessons = WatchLoad.Lessons(lessons: lessons, from: day, until: end, studentId: untisVisit.studentId)
            }
            if case .success(let grades)? = untisVisit.grades { load.grades = grades }
        }
        // Only with a session to read them with.
        if parts.contains(.todos), backendOK, !tokenFailed, !needsSignIn || signedIn.withLock({ $0 }) {
            do {
                load.todos = WatchTodos.build(try await backend.todos(for: account), now: now)
                reach.answered()
            } catch {
                reach.failed(error)
            }
        }
        load.menu = await menu
        load.revoked = revoked.withLock { $0 }
        load.reachedNetwork = reach.reached
        return load
    }

    private func loadMenu(for account: StoredAccount, now: Date, calendar: Calendar, reach: Reach) async -> WatchLoad.Menu? {
        do {
            let served = WatchMensa.served(from: try await backend.menu(), backend: backend.backendURL)
            reach.answered()
            let menu = WatchMensa.menu(served, now: now, calendar: calendar)
            // Without the stars the dishes still show; the ones known so far stay.
            guard let ratings = try? await backend.ratings(menu.dishes.map(\.id), for: account) else {
                return WatchLoad.Menu(day: menu.day, dishes: menu.dishes)
            }
            return WatchLoad.Menu(day: menu.day, dishes: WatchMensa.rated(menu.dishes, with: WatchMensa.ratings(from: ratings)))
        } catch {
            reach.failed(error)
            return nil
        }
    }
}

/// Whether anything got through. A server that answers with an error still counts: the watch is
/// online, the server just didn't like the question.
final class Reach: Sendable {
    private let state = Mutex(false)

    var reached: Bool { state.withLock { $0 } }

    func answered() {
        state.withLock { $0 = true }
    }

    func failed(_ error: any Error) {
        if !Self.isOffline(error) { answered() }
    }

    static func isOffline(_ error: any Error) -> Bool {
        if error is URLError { return true }
        if let error = error as? WatchBackendError { return error == .noConnection }
        if let error = error as? BackendError { return error.code == "no_connection" }
        return false
    }
}
