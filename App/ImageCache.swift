import ImageIO
import SwiftUI
import UIKit
import PokyhCore

/// Pictures: memory, then disk, then network, so they show at once and offline too. On disk
/// they're sealed with the vault key and only readable while the phone is unlocked; downloads skip
/// URLCache, which would keep a plain copy. Nothing here runs on the main thread.
nonisolated enum ImageCache {
    private static let requestTimeout: TimeInterval = 15
    /// Big enough for the largest place a picture is shown, so nothing decodes at full size.
    private static let maxPixelSize = 840

    private nonisolated(unsafe) static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = requestTimeout
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        return URLSession(configuration: cfg)
    }()

    private nonisolated(unsafe) static let files = SealedFiles(
        directory: SecureStorage.directory("images", caches: true),
        protection: .complete
    ) { LocalVault.current() }

    private static let downloads = Downloads()

    /// Per account rather than per URL: an offline session often has no image URL at all.
    static func avatarKey(_ username: String) -> String {
        "avatar-\(username.trimmingCharacters(in: .whitespaces).lowercased())"
    }

    /// Already decoded, so a picture coming back on screen doesn't blink.
    static func inMemory(_ key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    /// What's on disk, nil when there's nothing yet.
    static func stored(_ key: String) async -> UIImage? {
        if let image = inMemory(key) { return image }
        return await Task.detached(priority: .userInitiated) {
            guard let data = files.read(key), let image = decode(data) else { return nil }
            remember(image, key)
            return image
        }.value
    }

    /// Fetches once per launch per key, however many views ask at the same moment.
    static func fetch(_ url: URL, key: String, headers: [String: String] = [:]) async -> UIImage? {
        await downloads.run(key) {
            var request = URLRequest(url: url)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = decode(data) else { return nil }
            _ = files.write(data, name: key)
            remember(image, key)
            return image
        }
    }

    static func forget(_ key: String) {
        memory.removeObject(forKey: key as NSString)
        files.remove(key)
        Task { await downloads.reset(key) }
    }

    static func purge() {
        memory.removeAllObjects()
        files.removeAll()
        Task { await downloads.resetAll() }
    }

    private static func remember(_ image: UIImage, _ key: String) {
        let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
        memory.setObject(image, forKey: key as NSString, cost: pixels * 4)
    }

    /// Thumbnail decoding keeps a 4000 px photo from costing 64 MB, and it happens here rather
    /// than during the first draw on the main thread.
    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private actor Downloads {
        private var finished: [String: UIImage] = [:]
        private var running: [String: Task<UIImage?, Never>] = [:]

        func run(_ key: String, _ work: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
            if let done = finished[key] { return done }
            if let task = running[key] { return await task.value }
            let task = Task { await work() }
            running[key] = task
            let image = await task.value
            running[key] = nil
            // A failed download may try again next time the picture is shown.
            if let image { finished[key] = image }
            return image
        }

        func reset(_ key: String) { finished[key] = nil }
        func resetAll() { finished.removeAll() }
    }
}

/// What WebUntis needs to hand out a profile picture: the signed-in session. Sent to that school's
/// own server only, never to a host named in a server response.
struct UntisImageAuth {
    let username: String
    let sessionId: String
    let bearerToken: String
    let school: School

    /// The session pictures load with; AppState keeps it current.
    static var current: UntisImageAuth?

    init?(_ session: UserSession?) {
        guard let session, session.hasUntis, !session.sessionId.isEmpty else { return nil }
        username = session.username
        sessionId = session.sessionId
        bearerToken = session.bearerToken
        school = session.schoolRef
    }

    func headers(for url: URL) -> [String: String] {
        guard url.host == school.server else { return [:] }
        var headers = ["Cookie": "JSESSIONID=\(sessionId); schoolname=\"\(school.cookie)\""]
        if !bearerToken.isEmpty { headers["Authorization"] = "Bearer \(bearerToken)" }
        return headers
    }

    /// Absolute https stays as is, anything else is a path on the school's server. Plain http is
    /// dropped rather than upgraded: this value comes from a server response.
    func resolve(_ raw: String?) -> URL? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty || value.hasPrefix("http://") { return nil }
        if value.hasPrefix("https://") { return URL(string: value) }
        return URL(string: "https://\(school.server)\(value.hasPrefix("/") ? value : "/" + value)")
    }
}

/// A remote photo (a dish, a subject) with the same cache as the profile pictures.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: UIImage?

    private var key: String { url?.absoluteString ?? "" }

    var body: some View {
        let image = loaded ?? ImageCache.inMemory(key)
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: key) {
            guard let url, image == nil else { return }
            var next = await ImageCache.stored(key)
            if next == nil { next = await ImageCache.fetch(url, key: key) }
            if let next { withAnimation(.easeOut(duration: 0.25)) { loaded = next } }
        }
    }
}
