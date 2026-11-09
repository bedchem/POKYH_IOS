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
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        StubServer.prepare()
        #endif
        // Plain files from older builds go before anything reads or writes the sealed ones.
        SecureStorage.prepare()
        GradeDraftLeftovers.remove()

        // Disk copies of the public dish photos; the decoded ones live in RemotePhotos, so memory
        // here only holds the raw bytes for a moment. Pictures of people use the sealed ImageCache.
        let cache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                             diskCapacity: 128 * 1024 * 1024)
        URLCache.shared = cache

        // Background refresh has to be registered early in the launch.
        BackgroundRefresh.register()
        WatchSync.start()
    }

    /// Comes up as soon as the app is signed in: at once when it was open, else after the lock screen.
    private func offerWebSignIn(_ url: URL) {
        if let code = WebSignInCode.of(url.absoluteString, host: AppConfig.current.websiteURL.host()) {
            app.pendingWebSignIn = code
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                // German, Italian or English: the phone's language unless one was picked in the app.
                .environment(\.strings, Strings.of(app.language))
                .onOpenURL { offerWebSignIn($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { offerWebSignIn(url) }
                }
                .modifier(PushRouteHost(app: app))
                .onAppear {
                    // Usage figures (time in the foreground), for the signed-in account only.
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
                app.appDidBecomeActive()        // locks after a long time away
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
        // One left running by a version that started them unasked.
        if !LiveActivityManager.isEnabled { LiveActivityManager.endAll() }
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
    let app: AppState
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
                    .environment(app)
                    .environment(\.strings, Strings.of(app.language))
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
            if session.hasBackend { shown = route }
        case .reminders:
            if session.hasBackend, !session.isParent { shown = route }
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
    @Environment(AppState.self) private var app
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
