//
//  POKYHApp.swift
//  POKYH
//

import SwiftUI

@main
struct POKYHApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Größerer Bild-/Daten-Cache für flüssige Mensa-Bilder (Performance).
        let cache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                             diskCapacity: 256 * 1024 * 1024)
        URLCache.shared = cache

        // Hintergrund-Aktualisierung registrieren (muss früh beim Start passieren).
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                app.appDidEnterBackground()
                BackgroundRefresh.schedule()   // periodischen Abruf nachlegen
            case .active:
                app.appDidBecomeActive()        // Auto-Sperre nach langer Inaktivität
            default:
                break
            }
        }
    }
}
