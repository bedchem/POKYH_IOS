import Foundation
import CryptoKit

/// AES-GCM-Verschlüsselung (256-bit) für lokal gespeicherte Geheimnisse.
/// Bewusst in eigener Datei: ein File namens `Security.swift`, das gleichzeitig
/// das System-Framework `Security` und `CryptoKit` importiert, erzeugt einen
/// Modul-Namenskonflikt (zirkuläre Abhängigkeit). Hier nur `CryptoKit`.
enum AppCrypto {
    /// Neuer zufälliger 256-bit-Schlüssel als Rohdaten.
    static func newKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// Verschlüsselt `plaintext`; Rückgabe = `nonce || ciphertext || tag` (combined).
    static func seal(_ plaintext: Data, keyData: Data) -> Data? {
        guard let sealed = try? AES.GCM.seal(plaintext, using: SymmetricKey(data: keyData)) else { return nil }
        return sealed.combined
    }

    /// Entschlüsselt ein mit `seal` erzeugtes combined-Paket.
    static func open(_ combined: Data, keyData: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: keyData)) else { return nil }
        return plain
    }
}
