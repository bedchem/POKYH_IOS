import CryptoKit
import Foundation

/// AES-GCM with one 256-bit key for everything the apps keep on disk.
///
/// A sealed blob is a short header, then nonce, ciphertext and tag. The label goes in as
/// associated data, so a file copied over another one (say one account's snapshot over
/// another's) doesn't open either.
public struct Vault: Sendable {
    public enum Failure: Error, Equatable {
        case badKey
        /// Not something this vault wrote, e.g. a plain JSON file from an older build.
        case notSealed
        /// Wrong key, wrong label or changed bytes.
        case damaged
    }

    public static let keySize = 32
    static let header = Data("PKV1".utf8)

    private let key: SymmetricKey
    /// Separate key for file names, so naming never touches the encryption key itself.
    let nameKey: SymmetricKey

    public init(keyData: Data) throws {
        guard keyData.count == Self.keySize else { throw Failure.badKey }
        key = SymmetricKey(data: keyData)
        nameKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: Data("file-names".utf8), outputByteCount: Self.keySize)
    }

    public static func makeKeyData() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func isSealed(_ data: Data) -> Bool {
        data.starts(with: header)
    }

    public func seal(_ plain: Data, label: String) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key, authenticating: Data(label.utf8))
        guard let combined = box.combined else { throw Failure.damaged }
        return Self.header + combined
    }

    public func open(_ sealed: Data, label: String) throws -> Data {
        guard Self.isSealed(sealed) else { throw Failure.notSealed }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(Self.header.count))
            return try AES.GCM.open(box, using: key, authenticating: Data(label.utf8))
        } catch {
            throw Failure.damaged
        }
    }
}

/// Where the vault key lives: a Keychain item the app and its widgets share, readable after
/// the first unlock (widgets and background refresh run while the phone is locked) and never
/// leaving the device.
public struct VaultKeyStore: Sendable {
    static let item = "vault.key.v1"

    let store: any SecureStore

    public init(store: any SecureStore) {
        self.store = store
    }

    /// The vault, or nil while there is no key yet and `create` is false. Throws when the
    /// Keychain can't be read right now (before the first unlock): making a new key then
    /// would orphan every file written with the old one. Only the app creates, widgets read.
    public func vault(create: Bool) throws -> Vault? {
        if let data = try store.data(for: Self.item), let vault = try? Vault(keyData: data) {
            return vault
        }
        // Missing, or a broken item nothing could have been sealed with.
        guard create else { return nil }
        let data = Vault.makeKeyData()
        try store.set(data, for: Self.item)
        return try Vault(keyData: data)
    }

    /// Forgets the key, which makes every sealed file unreadable.
    public func destroy() throws {
        try store.set(nil, for: Self.item)
    }
}
