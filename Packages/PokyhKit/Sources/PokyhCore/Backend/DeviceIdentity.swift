import Foundation
import Security

/// This install as the backend sees it: a random id (kept until the app is deleted, like on
/// Android) and a user agent the backend recognises as the iOS app (`POKYH-iOS/<version> (…)`).
public struct DeviceIdentity: Sendable {
    public let id: String
    public let userAgent: String

    static let key = "pokyh_device_id"

    public init(id: String, userAgent: String) {
        self.id = id
        self.userAgent = userAgent
    }

    public init(defaults: UserDefaults, version: String, system: String, model: String) {
        let stored = defaults.string(forKey: Self.key)
        let id: String
        if let stored, stored.wholeMatch(of: /[A-Za-z0-9_-]{16,64}/) != nil {
            id = stored
        } else {
            var bytes = [UInt8](repeating: 0, count: 18)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            id = Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            defaults.set(id, forKey: Self.key)
        }
        self.init(id: id, userAgent: "POKYH-iOS/\(Self.ascii(version)) (\(Self.ascii(system)); \(Self.ascii(model)))")
    }

    /// Header-safe and short; brackets and semicolons would break the backend's parsing.
    static func ascii(_ value: String) -> String {
        String(String(value.unicodeScalars.filter { $0.value >= 0x20 && $0.value <= 0x7E && !"();".unicodeScalars.contains($0) }).trimmingCharacters(in: .whitespaces).prefix(60))
    }
}
