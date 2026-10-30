//
//  POKYHApp.swift
//  POKYH
//

import SwiftUI
import PokyhCore
import PokyhDesign

@main
struct POKYHApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Plain files from older builds go before anything reads or writes the sealed ones.
        SecureStorage.prepare()

        // Größerer Bild-/Daten-Cache für flüssige Mensa-Bilder (Performance). Only public dish
        // photos go through it; pictures of people use the sealed ImageCache.
        let cache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                             diskCapacity: 256 * 1024 * 1024)
        URLCache.shared = cache

        // Hintergrund-Aktualisierung registrieren (muss früh beim Start passieren).
        BackgroundRefresh.register()
        WatchSync.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                // German, Italian or English: the phone's language unless one was picked in the app.
                .environment(\.strings, Strings.of(LanguageChoice.current(in: .standard)))
                .onAppear {
                    // Nutzungsstatistik (Vordergrundzeit) — liest nur das angemeldete Konto.
                    UsageReporter.shared.attach(app)
                    UsageReporter.shared.appBecameActive()
                }
        }
        .onChange(of: scenePhase) { old, phase in
            switch phase {
            case .background:
                UsageReporter.shared.appEnteredBackground()
                app.appDidEnterBackground()
                BackgroundRefresh.schedule()   // periodischen Abruf nachlegen
            case .inactive:
                // Leaving the screen, not arriving on it at launch.
                if old == .active { app.appWillResignActive() }   // Sichtschutz im App-Umschalter
            case .active:
                app.appDidBecomeActive()        // Auto-Sperre nach langer Inaktivität
                UsageReporter.shared.appBecameActive()
            @unknown default:
                break
            }
        }
    }
}
