import Foundation
#if os(iOS)
import ActivityKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(SwiftUI)

/// Marken-Farben als EINE Quelle für App und Widget (entspricht `Palette`).
enum Brand {
    static let accent   = Color(red: 99/255,  green: 102/255, blue: 241/255) // #6366F1
    static let positive = Color(red: 16/255,  green: 185/255, blue: 129/255) // #10B981
    static let danger   = Color(red: 239/255, green: 68/255,  blue: 68/255)  // #EF4444
    /// Notenfarbe: positiv (≥6) grün, sonst rot.
    static func grade(_ v: Double) -> Color { v >= 6 ? positive : danger }
}
#endif

/// Note ohne überflüssige Nullen, deutsche Schreibweise (8 / 8,5) — App + Widget.
enum GradeFormat {
    static func string(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",")
    }
}

#if canImport(SwiftUI)
// ── Einheitliche, minimalistische Widget-Bausteine (Apple-Stil) ───────────────

#if canImport(WidgetKit)
extension View {
    /// Standard-Hintergrund aller Home-Screen-Widgets.
    func pokyhWidgetBackground() -> some View {
        containerBackground(for: .widget) { Color(.systemBackground) }
    }
}
#endif

/// Schlanke, einheitliche Kopfzeile: kleines Icon + Großbuchstaben-Label.
struct WidgetHeader: View {
    let icon: String
    let title: String
    var accent: Color = Brand.accent
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
#endif

/// Geteilte Grundlage für App ⇄ Widget ⇄ Live Activity.

// ── App Group ────────────────────────────────────────────────────────────────

enum AppGroup {
    /// Muss mit der App-Group-Entitlement von App UND Widget übereinstimmen.
    static let id = "group.dev.plattnericus.POKYH"

    /// Container der App-Group. Fällt auf den app-eigenen Application-Support-Ordner
    /// zurück, falls die Entitlement (noch) nicht greift — so funktioniert der
    /// Offline-Cache auch ohne Provisioning (z. B. im Simulator-Test).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return base
    }
}

// ── WebUntis-Zeit → Date (geteilt) ────────────────────────────────────────────

enum UntisTime {
    /// `yyyymmdd` + `HHMM` (lokale Schulzeit) → `Date` in der Geräte-Zeitzone.
    static func date(_ yyyymmdd: Int, _ hhmm: Int) -> Date? {
        var c = DateComponents()
        c.year = yyyymmdd / 10000
        c.month = (yyyymmdd / 100) % 100
        c.day = yyyymmdd % 100
        c.hour = hhmm / 100
        c.minute = hhmm % 100
        return Calendar.current.date(from: c)
    }
}

// ── Snapshot-Modell (entkoppelt vom schweren TimetableEntry) ──────────────────

/// Minimale, `Sendable` Stundeninfo für Widget/Live Activity.
struct LessonSnapshot: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var subject: String
    var room: String
    var teacher: String
    var start: Date
    var end: Date
    var isCancelled: Bool
    var isExam: Bool
}

/// Vom Hauptprogramm geschriebener, von Widget/Activity gelesener Stundenplan-Auszug.
struct TimetableSnapshot: Codable, Sendable {
    var generatedAt: Date
    var lessons: [LessonSnapshot]          // chronologisch sortiert
    static let empty = TimetableSnapshot(generatedAt: .distantPast, lessons: [])

    /// Nächste relevante Stunde ab `date` (laufende oder kommende, nicht entfallene).
    func nextLesson(after date: Date = Date()) -> LessonSnapshot? {
        lessons.first { !$0.isCancelled && $0.end > date }
    }
}

// ── Noten-Snapshot ────────────────────────────────────────────────────────────

struct GradeItem: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var subject: String
    var value: Double
    var date: Int          // yyyymmdd
}

struct GradesSnapshot: Codable, Sendable {
    var generatedAt: Date
    var average: Double     // gewichteter Gesamtschnitt (über alle Einzelnoten)
    var positive: Int
    var negative: Int
    var recent: [GradeItem] // zuletzt eingetragen (absteigend)
    static let empty = GradesSnapshot(generatedAt: .distantPast, average: 0, positive: 0, negative: 0, recent: [])
}

// ── Nachrichten-Snapshot ──────────────────────────────────────────────────────

struct MessageItem: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var sender: String
    var subject: String
    var isRead: Bool
}

struct MessagesSnapshot: Codable, Sendable {
    var generatedAt: Date
    var unread: Int
    var latest: [MessageItem]
    static let empty = MessagesSnapshot(generatedAt: .distantPast, unread: 0, latest: [])
}

// ── Geteilter JSON-Store im App-Group-Container ───────────────────────────────

enum SharedStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private static func url(_ name: String) -> URL { AppGroup.containerURL.appendingPathComponent(name) }

    private static func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }
    private static func read<T: Decodable>(_ type: T.Type, from name: String, fallback: T) -> T {
        guard let data = try? Data(contentsOf: url(name)),
              let value = try? decoder.decode(type, from: data) else { return fallback }
        return value
    }

    // Stundenplan
    static func writeSnapshot(_ s: TimetableSnapshot) { write(s, to: "timetable_snapshot.json") }
    static func readSnapshot() -> TimetableSnapshot { read(TimetableSnapshot.self, from: "timetable_snapshot.json", fallback: .empty) }
    // Noten
    static func writeGrades(_ s: GradesSnapshot) { write(s, to: "grades_snapshot.json") }
    static func readGrades() -> GradesSnapshot { read(GradesSnapshot.self, from: "grades_snapshot.json", fallback: .empty) }
    // Nachrichten
    static func writeMessages(_ s: MessagesSnapshot) { write(s, to: "messages_snapshot.json") }
    static func readMessages() -> MessagesSnapshot { read(MessagesSnapshot.self, from: "messages_snapshot.json", fallback: .empty) }

    /// Löscht alle geteilten Snapshots (Stundenplan/Noten/Nachrichten).
    static func purgeAll() {
        for name in ["timetable_snapshot.json", "grades_snapshot.json", "messages_snapshot.json"] {
            try? FileManager.default.removeItem(at: url(name))
        }
    }
}

// ── Live Activity Attributes (in App + Widget genutzt) ────────────────────────

#if os(iOS)
/// Live-Activity-Definition: zeigt die laufende/nächste Stunde mit Countdown.
struct LessonActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var subject: String
        var room: String
        var teacher: String
        var start: Date
        var end: Date
        var isBreak: Bool          // true = Pause bis zur nächsten Stunde
    }
    /// Statisch: Klassenname (ändert sich während der Activity nicht).
    var className: String
}
#endif
