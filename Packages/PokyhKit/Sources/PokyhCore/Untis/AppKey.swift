import CryptoKit
import Foundation

/// Signing in with a WebUntis account's app key (Profil → Freigaben → "Zugriff über Untis Mobile"),
/// the way in for Office 365 schools whose people have no WebUntis password. The sign-in sends
/// the current one-time code (TOTP, RFC 6238), like the official app.
///
/// A key account stores "appkey:<KEY>" where a password account stores its password, so every
/// re-login (Face ID, silent renewal, the watch) takes the same path.
public enum AppKey {
    public static let prefix = "appkey:"

    public static func isKey(_ secret: String) -> Bool {
        secret.hasPrefix(prefix)
    }

    /// Upper-cased base32 without spaces, dashes and padding, or "" if it can't be a key.
    public static func normalise(_ text: String) -> String {
        var key = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        while key.hasSuffix("=") { key.removeLast() }
        return key.wholeMatch(of: /[A-Z2-7]{16,128}/) != nil ? key : ""
    }

    /// User and key from whatever was pasted or scanned: an `untis://setschool?…` link,
    /// the labelled text WebUntis shows, or just the key.
    public static func parse(_ text: String) -> (user: String?, key: String?) {
        let pasted = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = pasted.firstMatch(of: /(?i)untis:\/\/setschool\?(\S+)/) {
            var params: [String: String] = [:]
            for pair in match.1.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                params[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            }
            let user = params["user"]?.trimmingCharacters(in: .whitespaces)
            let key = normalise(params["key"] ?? "")
            return (user?.isEmpty == false ? user : nil, key.isEmpty ? nil : key)
        }

        let keyLabel = /(?im)^\s*(?:Schlüssel|Key|Chiave)\s*:?[ \t]*([A-Za-z2-7 =-]{16,})/
        let userLabel = /(?im)^\s*(?:Benutzer|User|Utente)\s*:?[ \t]*(\S+)/
        if let keyMatch = pasted.firstMatch(of: keyLabel) {
            let key = normalise(String(keyMatch.1.split(separator: "\n").first ?? ""))
            let user = pasted.firstMatch(of: userLabel).map { String($0.1) }
            return (user, key.isEmpty ? nil : key)
        }

        let key = normalise(pasted)
        return (nil, key.isEmpty ? nil : key)
    }

    static func base32(_ text: String) -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0
        var value = 0
        var out = Data()
        for char in text.uppercased() {
            guard let index = alphabet.firstIndex(of: char) else { continue }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return out
    }

    /// The six-digit code for `key` at `date`: HMAC-SHA1, 30 s steps.
    public static func totp(_ key: String, at date: Date = .now) -> String {
        totp(secret: base32(key), at: date, digits: 6)
    }

    static func totp(secret: Data, at date: Date, digits: Int) -> String {
        var step = UInt64(date.timeIntervalSince1970 / 30).bigEndian
        let message = Data(bytes: &step, count: 8)
        let mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits { modulus *= 10 }
        let code = String(binary % modulus)
        return String(repeating: "0", count: max(0, digits - code.count)) + code
    }
}
