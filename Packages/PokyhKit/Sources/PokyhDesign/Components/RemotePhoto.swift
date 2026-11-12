#if canImport(UIKit)
import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// Public photos, like the dishes: decoded at the size they're drawn and kept in memory, so a
/// long menu doesn't hold full-size bitmaps or fetch them again on every scroll. The bytes stay
/// in Caches, so the next launch shows them without the network. Pictures of people don't come
/// through here, they're sealed (see the app's ImageCache).
public enum RemotePhotos {
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    private static let loads = Loads()

    public static func cached(_ url: URL, maxPixel: Int) -> UIImage? {
        memory.object(forKey: key(url, maxPixel) as NSString)
    }

    public static func load(_ url: URL, maxPixel: Int) async -> UIImage? {
        let key = key(url, maxPixel)
        if let image = memory.object(forKey: key as NSString) { return image }
        return await loads.run(key) {
            guard let data = await bytes(url), let image = decode(data, maxPixel: maxPixel) else { return nil }
            remember(image, key)
            return image
        }
    }

    /// Fetches what a screen is about to show, so the photos are on disk before anyone scrolls.
    public static func prefetch(_ urls: [URL]) {
        pruneOnce()
        let missing = Array(Set(urls)).filter { !FileManager.default.fileExists(atPath: file(for: $0).path) }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                // A few at a time: the menu shouldn't crowd out what's loading on screen.
                for (index, url) in missing.enumerated() {
                    if index >= 4 { await group.next() }
                    group.addTask { _ = await bytes(url) }
                }
            }
        }
    }

    // Photos come from any site a menu links to: no cookies they could set and send back,
    // no second copy in URLCache (the bytes are kept below).
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    /// From disk, else the network, saved for next time.
    private static func bytes(_ url: URL) async -> Data? {
        let path = file(for: url)
        if let stored = try? Data(contentsOf: path) { return stored }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: path, options: .atomic)
        return data
    }

    /// Last month's dishes won't be served again; their bytes go once per launch.
    private static func pruneOnce() {
        guard !pruned.swap(true) else { return }
        Task.detached(priority: .background) {
            let fm = FileManager.default
            let cutoff = Date.now.addingTimeInterval(-maxAge)
            let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if modified < cutoff { try? fm.removeItem(at: file) }
            }
        }
    }
    private static let pruned = Flag()
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    private static let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("RemotePhotos", isDirectory: true)
    }()

    private static func file(for url: URL) -> URL {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    /// Off the main thread and no bigger than `maxPixel` on the long side; a 4000 px photo
    /// would otherwise cost 64 MB once drawn.
    public static func decode(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    public static func purge() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
    }

    static func key(_ url: URL, _ maxPixel: Int) -> String {
        "\(url.absoluteString)|\(maxPixel)"
    }

    private static func remember(_ image: UIImage, _ key: String) {
        let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
        memory.setObject(image, forKey: key as NSString, cost: pixels * 4)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        /// Sets it and says what it was.
        func swap(_ new: Bool) -> Bool {
            lock.withLock {
                let old = value
                value = new
                return old
            }
        }
    }

    /// One download per photo, however many plates ask for it at once.
    private actor Loads {
        private var running: [String: Task<UIImage?, Never>] = [:]

        func run(_ key: String, _ work: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
            if let task = running[key] { return await task.value }
            let task = Task { await work() }
            running[key] = task
            let image = await task.value
            running[key] = nil
            return image
        }
    }
}

/// A public photo at the size it's shown, fading in once it's there.
public struct RemotePhoto<Content: View, Placeholder: View>: View {
    let url: URL
    let maxPixel: Int
    let content: (Image) -> Content
    let placeholder: Placeholder
    /// Keyed, so a reused view never shows the photo it had before.
    @State private var loaded: (key: String, image: UIImage)?

    public init(url: URL, maxPixel: Int, @ViewBuilder content: @escaping (Image) -> Content,
                @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.maxPixel = maxPixel
        self.content = content
        self.placeholder = placeholder()
    }

    public var body: some View {
        let key = RemotePhotos.key(url, maxPixel)
        let image = loaded?.key == key ? loaded?.image : RemotePhotos.cached(url, maxPixel: maxPixel)
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder
            }
        }
        .task(id: key) {
            guard RemotePhotos.cached(url, maxPixel: maxPixel) == nil,
                  let fresh = await RemotePhotos.load(url, maxPixel: maxPixel) else { return }
            withAnimation(.easeIn(duration: 0.25)) { loaded = (key, fresh) }
        }
    }
}
#endif
