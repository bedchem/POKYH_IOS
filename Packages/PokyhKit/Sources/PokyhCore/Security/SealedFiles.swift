import CryptoKit
import Foundation

/// A folder of vault-sealed files with the system's file protection on top, kept out of
/// backups (the key never leaves the device, so a restored copy couldn't be opened anyway).
///
/// File names are keyed hashes of the item names, so the folder doesn't give away which
/// student or week is cached. Anything that doesn't open, a plain file from an older build or
/// one sealed with a lost key, is deleted on read unless `dropsUnreadable` is off.
public struct SealedFiles: Sendable {
    public enum Protection: Sendable {
        /// Readable only while the device is unlocked.
        case complete
        /// Readable once the device was unlocked after booting; for widgets and background work.
        case untilFirstUnlock
    }

    public let directory: URL
    let protection: Protection
    let dropsUnreadable: Bool
    let vault: @Sendable () -> Vault?

    /// `vault` is asked on every access and may return nil (no key yet, Keychain locked); the
    /// store then reads nothing and writes nothing. Widgets pass `dropsUnreadable: false`: one
    /// holding an outdated key must not delete what the app just wrote.
    public init(directory: URL, protection: Protection, dropsUnreadable: Bool = true,
                vault: @escaping @Sendable () -> Vault?) {
        self.directory = directory
        self.protection = protection
        self.dropsUnreadable = dropsUnreadable
        self.vault = vault
    }

    @discardableResult
    public func write(_ data: Data, name: String) -> Bool {
        guard let vault = vault(), let sealed = try? vault.seal(data, label: name) else { return false }
        prepareDirectory()
        do {
            try sealed.write(to: url(name, vault), options: [.atomic, writingProtection])
            return true
        } catch {
            return false
        }
    }

    public func read(_ name: String) -> Data? {
        guard let vault = vault() else { return nil }
        let file = url(name, vault)
        guard let sealed = try? Data(contentsOf: file) else { return nil }
        do {
            return try vault.open(sealed, label: name)
        } catch {
            if dropsUnreadable { try? FileManager.default.removeItem(at: file) }
            return nil
        }
    }

    public func remove(_ name: String) {
        guard let vault = vault() else { return }
        try? FileManager.default.removeItem(at: url(name, vault))
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    func url(_ name: String, _ vault: Vault) -> URL {
        directory.appendingPathComponent(vault.fileName(for: name) + ".sealed", isDirectory: false)
    }

    private var writingProtection: Data.WritingOptions {
        switch protection {
        case .complete: .completeFileProtection
        case .untilFirstUnlock: .completeFileProtectionUntilFirstUserAuthentication
        }
    }

    private var fileProtection: FileProtectionType {
        switch protection {
        case .complete: .complete
        case .untilFirstUnlock: .completeUntilFirstUserAuthentication
        }
    }

    private func prepareDirectory() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: directory.path) else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: fileProtection])
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }
}

extension Vault {
    /// A file name for `label` that only this key can produce.
    func fileName(for label: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(label.utf8), using: nameKey)
        return mac.prefix(20).map { String(format: "%02x", $0) }.joined()
    }
}
