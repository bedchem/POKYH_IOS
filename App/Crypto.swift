import Foundation
import CryptoKit

/// The sealing older builds used for saved passwords, kept only to move those over (see
/// `Keychain.migrateSealedPasswords`). New data goes through PokyhCore's `Vault`.
/// Own file on purpose: importing the `Security` framework and CryptoKit side by side in a file
/// named Security.swift ends in a module name clash.
enum AppCrypto {
    /// Opens `nonce || ciphertext || tag` as those builds wrote it.
    static func open(_ combined: Data, keyData: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: keyData)) else { return nil }
        return plain
    }
}
