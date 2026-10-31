//
//  POKYHApp.swift
//  POKYH
//

import SwiftUI
import UIKit
import PokyhCore
import PokyhDesign

@main
struct POKYHApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .modifier(PushRouteHost(app: app))
                .onAppear {
                    // Nutzungsstatistik (Vordergrundzeit) — liest nur das angemeldete Konto.
                    UsageReporter.shared.attach(app)
                    UsageReporter.shared.appBecameActive()
                    PushRegistration.shared.attach(app)
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
                PushRegistration.shared.appBecameActive()
            @unknown default:
                break
            }
        }
    }
}

/// The device token comes through here, and only a delegate set before launch ends gets the tap
/// that started the app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationManager.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.shared.received(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushRegistration.shared.registrationFailed()
    }
}

/// Opens what a tapped notification is about once the app is unlocked: the tab for grades and the
/// timetable, a sheet over whatever is open for the rest.
private struct PushRouteHost: ViewModifier {
    @ObservedObject var app: AppState
    @ObservedObject private var router = PushRouter.shared
    @State private var shown: PushRoute?

    private var ready: Bool { router.pending != nil && app.phase == .authed && app.session != nil && !app.busy }

    func body(content: Content) -> some View {
        content
            .task(id: ready) {
                guard ready else { return }
                // The lock screen or the sign-in sheet finishes leaving first.
                try? await Task.sleep(for: .milliseconds(450))
                guard ready, let route = router.take() else { return }
                open(route)
            }
            .sheet(item: $shown) { route in
                NavigationStack { PushDestination(route: route) }
                    .environmentObject(app)
                    .environment(\.strings, Strings.of(LanguageChoice.current(in: .standard)))
            }
            // Nothing stays up over the lock screen or into another account.
            .onChange(of: app.phase) { _, phase in
                if phase != .authed { shown = nil }
            }
            .onChange(of: app.session?.username) { shown = nil }
            .onChange(of: router.inboxSignal) {
                Task { await app.refreshUnread(force: true) }
            }
    }

    private func open(_ route: PushRoute) {
        guard let session = app.session else { return }
        switch route {
        case .grades:
            if session.hasUntis { app.selectedTab = .noten }
        case .timetable:
            if session.hasUntis { app.selectedTab = .timetable }
        case .messages:
            if session.hasUntis { shown = route }
        case .todos:
            if session.apiToken != nil { shown = route }
        case .reminders:
            if session.apiToken != nil, !session.isParent { shown = route }
        }
    }
}

private struct PushDestination: View {
    let route: PushRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        screen.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) { dismiss() }
            }
        }
    }

    @ViewBuilder private var screen: some View {
        switch route {
        case .messages: MessagesView()
        case .todos: TodosView()
        case .reminders(let id): ReminderLanding(id: id)
        case .grades, .timetable: EmptyView()
        }
    }
}

/// A reminder's own page while it still exists, the list when it's gone.
private struct ReminderLanding: View {
    let id: String?
    @EnvironmentObject private var app: AppState
    @State private var found: (reminder: ApiReminder, classId: String)?
    @State private var looked = false

    var body: some View {
        Group {
            if let found {
                ReminderDetailView(reminder: found.reminder, classId: found.classId)
            } else if looked || id == nil {
                RemindersView()
            } else {
                LoadingView()
            }
        }
        .task {
            defer { looked = true }
            guard let id, let session = app.session, let token = session.apiToken else { return }
            var classId = session.classId
            if classId == nil { classId = try? await BackendClient.shared.myClass(token: token)?.id }
            guard let classId,
                  let list = try? await BackendClient.shared.reminders(classId: classId, token: token),
                  let reminder = list.first(where: { $0.id == id }) else { return }
            found = (reminder, classId)
        }
    }
}
