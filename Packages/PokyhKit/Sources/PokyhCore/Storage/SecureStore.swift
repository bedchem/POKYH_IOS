import Foundation
import Security

/// Small key → data store for secrets. The Keychain in the apps, memory in tests.
public protocol SecureStore: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data?, for key: String) throws
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Generic-password items, this device only, so nothing ends up in backups or on another device.
/// By default readable after the first unlock, so background refreshes work.
public struct KeychainStore: SecureStore {
    public enum Access: Sendable {
        /// After the first unlock since boot: widgets and background work while the phone is locked.
        case afterFirstUnlock
        /// Only while the phone is unlocked.
        case whenUnlocked
    }

    let service: String
    let accessGroup: String?
    let access: Access

    public init(service: String, accessGroup: String? = nil, access: Access = .afterFirstUnlock) {
        self.service = service
        self.accessGroup = accessGroup
        self.access = access
    }

    private var accessible: CFString {
        switch access {
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlocked: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }

    private func query(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func data(for key: String) throws -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    public func set(_ data: Data?, for key: String) throws {
        guard let data else {
            let status = SecItemDelete(query(key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
        var status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(key).merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

/// For tests and previews.
public final class MemorySecureStore: SecureStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(for key: String) throws -> Data? {
        lock.withLock { items[key] }
    }

    public func set(_ data: Data?, for key: String) throws {
        lock.withLock { items[key] = data }
    }
}
