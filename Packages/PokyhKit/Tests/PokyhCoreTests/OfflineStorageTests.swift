import Foundation
import Testing
@testable import PokyhCore

/// One folder per account inside the sealed store, and the pruning of what nobody read for long.
struct SealedFoldersTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("folders-\(UUID().uuidString)", isDirectory: true)
    let key = Vault.makeKeyData()

    func files() -> SealedFiles {
        let data = key
        return SealedFiles(directory: dir, protection: .complete) { try? Vault(keyData: data) }
    }

    @Test func eachAccountHasItsOwnFolder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = files()
        let anna = try #require(store.folder("anna"))
        let max = try #require(store.folder("max"))
        anna.write(Data("anna".utf8), name: "tt-1-2026-11-02")
        max.write(Data("max".utf8), name: "tt-1-2026-11-02")
        #expect(anna.read("tt-1-2026-11-02") == Data("anna".utf8))
        #expect(max.read("tt-1-2026-11-02") == Data("max".utf8))
        // Same name at the top level is something else again.
        #expect(store.read("tt-1-2026-11-02") == nil)
    }

    @Test func folderNamesGiveNothingAway() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try #require(files().folder("anna.rossi")).write(Data("x".utf8), name: "session")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.count == 1)
        #expect(!names[0].contains("anna"))
    }

    @Test func removingAFolderLeavesTheOthers() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = files()
        try #require(store.folder("anna")).write(Data("a".utf8), name: "session")
        try #require(store.folder("max")).write(Data("m".utf8), name: "session")
        store.write(Data("shared".utf8), name: "holidays-demo")
        store.removeFolder("anna")
        #expect(try #require(store.folder("anna")).read("session") == nil)
        #expect(try #require(store.folder("max")).read("session") == Data("m".utf8))
        #expect(store.read("holidays-demo") == Data("shared".utf8))
    }

    @Test func withoutAKeyThereIsNoFolder() {
        let store = SealedFiles(directory: dir, protection: .complete) { nil }
        #expect(store.folder("anna") == nil)
    }

    @Test func pruningDropsWhatNobodyWroteForLong() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = files()
        let vault = try Vault(keyData: key)
        let anna = try #require(store.folder("anna"))
        anna.write(Data("old".utf8), name: "tt-1-2026-01-05")
        anna.write(Data("new".utf8), name: "tt-1-2026-11-02")
        store.write(Data("old".utf8), name: "holidays-demo")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let longAgo = now.addingTimeInterval(-90 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: anna.url("tt-1-2026-01-05", vault).path)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: store.url("holidays-demo", vault).path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: anna.url("tt-1-2026-11-02", vault).path)

        store.prune(olderThan: 45 * 86_400, now: now)

        #expect(anna.read("tt-1-2026-01-05") == nil)
        #expect(anna.read("tt-1-2026-11-02") == Data("new".utf8))
        #expect(store.read("holidays-demo") == nil)
    }

    @Test func pruningRemovesFoldersLeftEmpty() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = files()
        let vault = try Vault(keyData: key)
        let gone = try #require(store.folder("gone"))
        gone.write(Data("x".utf8), name: "session")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-100 * 86_400)],
                                              ofItemAtPath: gone.url("session", vault).path)
        store.prune(olderThan: 45 * 86_400, now: now)
        #expect(!FileManager.default.fileExists(atPath: store.folderURL("gone", vault).path))
    }
}

struct PendingQueueTests {
    @Test func keepsOrderAndKinds() {
        var queue = PendingQueue()
        let todo = PendingItem(kind: .todo, title: "Mathe lernen", text: "", date: nil)
        let reminder = PendingItem(kind: .reminder, title: "Ausflug", text: "Jause", date: "2026-11-06T08:00:00Z")
        queue.add(todo)
        queue.add(reminder)
        #expect(queue.items.map(\.title) == ["Mathe lernen", "Ausflug"])
        #expect(queue.of(.todo) == [todo])
        #expect(queue.of(.reminder) == [reminder])
        queue.remove(todo.id)
        #expect(queue.items == [reminder])
    }

    @Test func survivesBeingStored() throws {
        var queue = PendingQueue()
        queue.add(PendingItem(kind: .todo, title: "Buch kaufen", text: "Bibliothek", date: "2026-11-10T12:00:00Z",
                              createdAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let data = try JSONEncoder().encode(queue)
        #expect(try JSONDecoder().decode(PendingQueue.self, from: data) == queue)
    }

    @Test func hasALimit() {
        var queue = PendingQueue()
        var accepted = 0
        for i in 0..<PendingQueue.limit where queue.add(PendingItem(kind: .todo, title: "\(i)", text: "", date: nil)) { accepted += 1 }
        let overflow = queue.add(PendingItem(kind: .todo, title: "one too many", text: "", date: nil))
        #expect(accepted == PendingQueue.limit)
        #expect(!overflow)
        #expect(queue.items.count == PendingQueue.limit)
    }

    @Test func whatIsWorthTryingAgain() {
        #expect(PendingQueue.keepsForLater(status: nil, connectionLost: true))
        #expect(PendingQueue.keepsForLater(status: nil, connectionLost: false))
        #expect(PendingQueue.keepsForLater(status: 503, connectionLost: false))
        #expect(PendingQueue.keepsForLater(status: 401, connectionLost: false))
        #expect(PendingQueue.keepsForLater(status: 429, connectionLost: false))
        #expect(!PendingQueue.keepsForLater(status: 400, connectionLost: false))
        #expect(!PendingQueue.keepsForLater(status: 403, connectionLost: false))
        #expect(!PendingQueue.keepsForLater(status: 404, connectionLost: false))
    }
}

/// The phone's copy of the watch account only opens while the phone is unlocked.
struct WatchCopyTests {
    let school = School(loginName: "demo-school", server: "demo.webuntis.com", name: "Demo School")

    @Test func aLockedStoreGivesNoAnswerRatherThanASignOut() throws {
        let store = AccountStore(store: LockedKeychain())
        #expect(throws: KeychainError.self) { try store.handoff() }
        // The old reads still say "nothing", which is why the reply to the watch uses handoff().
        #expect(store.load() == nil)
    }

    @Test func theAnswerCarriesTheStoredTime() throws {
        let backing = MemorySecureStore()
        let store = AccountStore(store: backing)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let account = StoredAccount(username: "anna", displayName: "Anna", school: school, secret: "pw", signedInAt: at)
        try store.apply(account, changedAt: at)
        let answer = try store.handoff()
        #expect(answer.account == account)
        #expect(answer.sentAt == at)
    }

    @Test func nothingStoredIsASignedOutAnswer() throws {
        let answer = try AccountStore(store: MemorySecureStore()).handoff()
        #expect(answer.account == nil)
    }

    @Test func resealingKeepsTheTime() throws {
        let backing = MemorySecureStore()
        let store = AccountStore(store: backing)
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        try store.apply(StoredAccount(username: "anna", displayName: "Anna", school: school, secret: "pw"), changedAt: at)
        try store.reseal()
        #expect(store.changedAt == at)
        #expect(store.load()?.username == "anna")
    }
}

private struct LockedKeychain: SecureStore {
    func data(for key: String) throws -> Data? { throw KeychainError(status: -25308) }
    func set(_ data: Data?, for key: String) throws { throw KeychainError(status: -25308) }
}
