import Foundation

// Vorlage für POKYH/Secrets.swift. Kopieren und Werte einsetzen:
//   cp Secrets.example.swift POKYH/Secrets.swift
//
// POKYH/Secrets.swift ist in .gitignore und wird NICHT committet.
enum Secrets {
    /// Öffentlicher Backend-API-Key (NEXT_PUBLIC_API_KEY im Web-Frontend).
    static let apiKey = "YOUR_BACKEND_API_KEY"

    /// Server-zu-Server-Key (sensibel — siehe README/Sicherheit).
    static let serverKey = "YOUR_SERVER_KEY"

    /// Entwickler-/Diagnose-Modus. In Produktion `false` → keine Diagnose-UI.
    static let isDebug = false
}
