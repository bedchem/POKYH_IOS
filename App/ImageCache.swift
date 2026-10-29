import UIKit
import CryptoKit

/// Lokaler Profilbild-Cache: In-Memory (`NSCache`) → Platte → Netzwerk.
///
/// Profilbilder werden sofort aus dem Cache angezeigt (kein Flackern) und sind
/// offline verfügbar. Es werden ausschließlich Bild-Bytes gespeichert — niemals
/// Zugangsdaten/Tokens. Der App-Group-Container ist sandboxed (System-Dateischutz),
/// analog zu `DiskCache`.
enum ImageCache {
    /// Netzwerk-Timeout für einen Bild-Download (kein Hardcoding einzelner URLs).
    private static let requestTimeout: TimeInterval = 15

    private static let mem: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: cfg)
    }()

    private static var dir: URL {
        let d = AppGroup.containerURL.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Stabiler, kollisionsarmer Dateiname je URL (SHA-256, hex).
    private static func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(name).img")
    }

    /// Liefert das Bild aus Memory → Platte → Netzwerk. `nil`, wenn nicht ladbar
    /// (z. B. offline ohne Cache).
    static func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = mem.object(forKey: key) { return cached }

        let file = fileURL(for: url)
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            mem.setObject(img, forKey: key)
            return img
        }

        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode ?? 200 == 200,
              let img = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        mem.setObject(img, forKey: key)
        return img
    }

    /// Löscht alle gecachten Bilder (Platte + Memory).
    static func purge() {
        mem.removeAllObjects()
        try? FileManager.default.removeItem(at: dir)
    }
}
