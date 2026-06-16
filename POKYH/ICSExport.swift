import SwiftUI
import UIKit

/// Erzeugt einen RFC-5545 VCALENDAR (.ics) aus Stundenplan-/Prüfungseinträgen.
/// Reines Text-Rendering — keine externen Abhängigkeiten.
enum ICSExport {

    /// Baut den .ics-Text. WebUntis-Zeiten sind lokale Schulzeiten; sie werden als
    /// absolute Zeitpunkte in UTC (`…Z`) geschrieben (vom Kalender lokal angezeigt).
    static func makeCalendar(_ entries: [TimetableEntry], calendarName: String) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//POKYH//Stundenplan//DE",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:\(escape(calendarName))",
        ]
        let stamp = dt(Date())
        for e in entries where !e.isCancelled {
            guard let start = UntisTime.date(e.date, e.startTime),
                  let end = UntisTime.date(e.date, e.endTime) else { continue }
            let uid = "pokyh-\(e.id)-\(e.date)-\(e.startTime)@pokyh.app"
            let summary = e.isExam ? "📝 \(e.subjectName)" : e.subjectName

            var desc: [String] = []
            if !e.teacherName.isEmpty { desc.append("Lehrkraft: \(e.teacherName)") }
            if e.isSubstitution { desc.append("Vertretung") }
            if e.isExam, let d = e.examDescription, !d.isEmpty { desc.append(d) }
            if let note = e.note, !note.isEmpty { desc.append(note) }

            lines += [
                "BEGIN:VEVENT",
                "UID:\(uid)",
                "DTSTAMP:\(stamp)",
                "DTSTART:\(dt(start))",
                "DTEND:\(dt(end))",
                "SUMMARY:\(escape(summary))",
            ]
            if !e.roomName.isEmpty { lines.append("LOCATION:\(escape(e.roomName))") }
            if !desc.isEmpty { lines.append("DESCRIPTION:\(escape(desc.joined(separator: "\n")))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    /// Schreibt den Kalender in eine temporäre `.ics`-Datei (für den Share-Dialog).
    static func writeTempFile(_ ics: String, name: String) -> URL? {
        let safe = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).ics")
        do { try Data(ics.utf8).write(to: url, options: .atomic); return url }
        catch { return nil }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()
    private static func dt(_ d: Date) -> String { utcFormatter.string(from: d) }

    /// RFC-5545-Escaping für Text-Werte.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// ── Teilbares Item + Share-Sheet ──────────────────────────────────────────────

/// Identifizierbarer Wrapper für `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Schlanke Brücke zu `UIActivityViewController` (zuverlässiger als ein
/// dauerhaft gerendertes `ShareLink` für dynamisch erzeugte Dateien).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
