import Foundation

/// Links in backend answers, made loadable. Pictures the backend keeps itself (dishes, popups)
/// come as a bare path ("/dishes/<id>/image?v=…") when it has no PUBLIC_BASE_URL, and a path
/// loads nothing on its own.
public enum BackendLink {
    /// Absolute https stays; "/path" and "//host/path" go behind the backend address, as on
    /// the website. Plain http only for a backend that is itself on http (a local dev server):
    /// in a release it would be a request into the phone's network, which ATS lets through for
    /// local hosts. Anything that isn't http(s) with a host after that is dropped.
    public static func resolve(_ raw: String?, against base: URL) -> URL? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return nil }
        let joined: String
        if value.hasPrefix("//") {
            joined = "\(base.scheme ?? "https"):\(value)"
        } else if value.hasPrefix("/") {
            // Appended rather than resolved, so a backend served below a path keeps it.
            var root = base.absoluteString
            while root.hasSuffix("/") { root.removeLast() }
            joined = root + value
        } else {
            joined = value
        }
        let plainAllowed = base.scheme?.lowercased() == "http"
        guard let url = URL(string: joined),
              let scheme = url.scheme?.lowercased(), scheme == "https" || (scheme == "http" && plainAllowed),
              let host = url.host, !host.isEmpty,
              // The backend refuses links with credentials too (mensa.json and the panel).
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

extension AppConfig {
    /// A link from a backend answer against this build's backend address.
    public func backendLink(_ raw: String?) -> URL? {
        BackendLink.resolve(raw, against: backendURL)
    }
}
