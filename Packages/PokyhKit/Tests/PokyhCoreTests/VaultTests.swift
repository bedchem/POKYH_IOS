import Foundation
import Testing
@testable import PokyhCore

struct VaultTests {
    let vault = try! Vault(keyData: Vault.makeKeyData())
    let plain = Data(#"{"klasse":"4A","noten":[8,9.5]}"#.utf8)

    @Test func roundTrips() throws {
        let sealed = try vault.seal(plain, label: "grades-1")
        #expect(Vault.isSealed(sealed))
        #expect(sealed != plain)
        #expect(try vault.open(sealed, label: "grades-1") == plain)
    }

    @Test func sealingTwiceGivesDifferentBytes() throws {
        // Fresh nonce every time, so equal content doesn't show as equal files.
        #expect(try vault.seal(plain, label: "a") != vault.seal(plain, label: "a"))
    }

    @Test func aChangedByteFails() throws {
        var sealed = try vault.seal(plain, label: "grades-1")
        sealed[sealed.count - 20] ^= 0x01
        #expect(throws: Vault.Failure.damaged) { try vault.open(sealed, label: "grades-1") }
    }

    @Test func aCutOffBlobFails() throws {
        let sealed = try vault.seal(plain, label: "grades-1")
        #expect(throws: Vault.Failure.damaged) { try vault.open(sealed.prefix(sealed.count - 1), label: "grades-1") }
        #expect(throws: Vault.Failure.damaged) { try vault.open(Vault.header, label: "grades-1") }
    }

    @Test func theWrongKeyFails() throws {
        let sealed = try vault.seal(plain, label: "grades-1")
        let other = try Vault(keyData: Vault.makeKeyData())
        #expect(throws: Vault.Failure.damaged) { try other.open(sealed, label: "grades-1") }
    }

    @Test func aFileUnderAnotherNameFails() throws {
        // Copying one account's snapshot over another's must not work.
        let sealed = try vault.seal(plain, label: "session-anna")
        #expect(throws: Vault.Failure.damaged) { try vault.open(sealed, label: "session-max") }
    }

    @Test func plainOldFilesAreNotSealed() {
        #expect(!Vault.isSealed(plain))
        #expect(throws: Vault.Failure.notSealed) { try vault.open(plain, label: "grades-1") }
    }

    @Test func onlyFullLengthKeys() {
        #expect(throws: Vault.Failure.badKey) { try Vault(keyData: Data(repeating: 1, count: 16)) }
        #expect(Vault.makeKeyData().count == 32)
        #expect(Vault.makeKeyData() != Vault.makeKeyData())
    }

    @Test func fileNamesDependOnTheKey() throws {
        let other = try Vault(keyData: Vault.makeKeyData())
        #expect(vault.fileName(for: "tt-1") == vault.fileName(for: "tt-1"))
        #expect(vault.fileName(for: "tt-1") != vault.fileName(for: "tt-2"))
        #expect(vault.fileName(for: "tt-1") != other.fileName(for: "tt-1"))
        #expect(!vault.fileName(for: "tt-1").contains("tt"))
    }
}

struct VaultKeyStoreTests {
    @Test func widgetsDontMakeAKey() throws {
        let keys = VaultKeyStore(store: MemorySecureStore())
        #expect(try keys.vault(create: false) == nil)
    }

    @Test func theKeyStaysTheSame() throws {
        let backing = MemorySecureStore()
        let first = try #require(try VaultKeyStore(store: backing).vault(create: true))
        let sealed = try first.seal(Data("x".utf8), label: "l")
        // A relaunch, or the widget, reading the same item.
        let again = try #require(try VaultKeyStore(store: backing).vault(create: false))
        #expect(try again.open(sealed, label: "l") == Data("x".utf8))
    }

    @Test func destroyingTheKeyLocksOldFiles() throws {
        let backing = MemorySecureStore()
        let keys = VaultKeyStore(store: backing)
        let sealed = try #require(try keys.vault(create: true)).seal(Data("x".utf8), label: "l")
        try keys.destroy()
        #expect(try keys.vault(create: false) == nil)
        let fresh = try #require(try keys.vault(create: true))
        #expect(throws: Vault.Failure.damaged) { try fresh.open(sealed, label: "l") }
    }

    @Test func aBrokenItemIsReplaced() throws {
        let backing = MemorySecureStore()
        try backing.set(Data("short".utf8), for: VaultKeyStore.item)
        let keys = VaultKeyStore(store: backing)
        #expect(try keys.vault(create: false) == nil)
        #expect(try keys.vault(create: true) != nil)
        #expect(try backing.data(for: VaultKeyStore.item)?.count == 32)
    }

    @Test func aLockedKeychainIsNotAMissingKey() {
        // Before the first unlock the item exists but can't be read: no new key then.
        let keys = VaultKeyStore(store: LockedStore())
        #expect(throws: KeychainError.self) { try keys.vault(create: true) }
    }
}

struct SealedFilesTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sealed-\(UUID().uuidString)", isDirectory: true)
    let key = Vault.makeKeyData()

    func files(_ key: Data? = nil, protection: SealedFiles.Protection = .complete) -> SealedFiles {
        let data = key ?? self.key
        return SealedFiles(directory: dir, protection: protection) { try? Vault(keyData: data) }
    }

    @Test func writesAndReadsBack() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = files()
        #expect(store.write(Data("hello".utf8), name: "tt-1-2026-10-26"))
        #expect(store.read("tt-1-2026-10-26") == Data("hello".utf8))
        #expect(store.read("tt-1-2026-11-02") == nil)
    }

    @Test func nothingReadableOnDisk() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        files().write(Data("Mathematik 9,5".utf8), name: "grades-12345-0")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.count == 1)
        #expect(!names[0].contains("12345"))
        let raw = try Data(contentsOf: dir.appendingPathComponent(names[0]))
        #expect(raw.range(of: Data("Mathematik".utf8)) == nil)
    }

    @Test func aTamperedFileIsDropped() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = files()
        store.write(Data("hello".utf8), name: "n")
        let file = try #require(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        var raw = try Data(contentsOf: file)
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: file)
        #expect(store.read("n") == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func anotherKeyReadsNothing() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        files().write(Data("hello".utf8), name: "n")
        #expect(files(Vault.makeKeyData()).read("n") == nil)
    }

    @Test func aReaderWithAnOldKeyLeavesTheFileAlone() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        files().write(Data("hello".utf8), name: "n")
        let stale = Vault.makeKeyData()
        let widget = SealedFiles(directory: dir, protection: .untilFirstUnlock, dropsUnreadable: false) { try? Vault(keyData: stale) }
        #expect(widget.read("n") == nil)
        #expect(files().read("n") == Data("hello".utf8))
    }

    @Test func withoutAKeyNothingIsWritten() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SealedFiles(directory: dir, protection: .untilFirstUnlock) { nil }
        #expect(!store.write(Data("hello".utf8), name: "n"))
        #expect(store.read("n") == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func removeAndRemoveAll() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = files(protection: .untilFirstUnlock)
        store.write(Data("a".utf8), name: "a")
        store.write(Data("b".utf8), name: "b")
        store.remove("a")
        #expect(store.read("a") == nil)
        #expect(store.read("b") == Data("b".utf8))
        store.removeAll()
        #expect(store.read("b") == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func theFolderStaysOutOfBackups() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        files().write(Data("a".utf8), name: "a")
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}

/// A Keychain before the first unlock: everything fails with "interaction not allowed".
private struct LockedStore: SecureStore {
    func data(for key: String) throws -> Data? { throw KeychainError(status: -25308) }
    func set(_ data: Data?, for key: String) throws { throw KeychainError(status: -25308) }
}
