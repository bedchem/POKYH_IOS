import UIKit
import PokyhCore

/// Profile pictures: memory, then disk, then network, so they show at once and offline too.
/// On disk they're sealed with the vault key and only readable while the phone is unlocked;
/// the download skips URLCache, which would keep a plain copy.
enum ImageCache {
    private static let requestTimeout: TimeInterval = 15

    private static let mem: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = requestTimeout
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    private static let files = SealedFiles(
        directory: SecureStorage.directory("images", caches: true),
        protection: .complete
    ) { LocalVault.current() }

    /// nil when it can't be had (offline without a copy, say).
    static func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString
        if let cached = mem.object(forKey: key as NSString) { return cached }

        if let data = files.read(key), let img = UIImage(data: data) {
            mem.setObject(img, forKey: key as NSString)
            return img
        }

        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200,
              let img = UIImage(data: data) else { return nil }
        files.write(data, name: key)
        mem.setObject(img, forKey: key as NSString)
        return img
    }

    /// Löscht alle gecachten Bilder (Platte + Memory).
    static func purge() {
        mem.removeAllObjects()
        files.removeAll()
    }
}
