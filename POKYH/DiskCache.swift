import Foundation

/// Persistenter JSON-Cache auf der Platte — überlebt App-Neustarts und dient als
/// Offline-Fallback, wenn das Netz nicht erreichbar ist.
///
/// Sicherheit: speichert ausschließlich fachliche Daten (Stundenplan/Noten),
/// NIE Zugangsdaten — Passwörter bleiben im verschlüsselten Keychain. Der
/// App-Group-Container ist sandboxed und folgt dem Daten-Schutz des Systems.
enum DiskCache {
    private static var dir: URL {
        let d = AppGroup.containerURL.appendingPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func fileURL(_ key: String) -> URL {
        // Schlüssel säubern → keine Pfadtrenner / Sonderzeichen.
        let safe = key.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        return dir.appendingPathComponent("\(safe).json")
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(key), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: fileURL(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Löscht ALLE persistierten Offline-Daten (alle Nutzer).
    static func purge() {
        try? FileManager.default.removeItem(at: dir)
    }
}
