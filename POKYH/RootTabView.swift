import SwiftUI

/// Bottom-Navigation — Home · Stundenplan · Schule · Noten · Mensa.
struct RootTabView: View {
    @EnvironmentObject var app: AppState

    /// WebUntis-Konto verknüpft? Reine POKYH-Backend-Konten haben keinen
    /// Stundenplan/Noten → diese Tabs werden ausgeblendet.
    private var hasUntis: Bool { app.session?.hasUntis ?? true }

    var body: some View {
        TabView(selection: tabSelection) {
            tab("Home", "house.fill", .home) { HomeView() }
            if hasUntis {
                tab("Stundenplan", "calendar", .timetable) { TimetableView() }
            }
            tab("Schule", "graduationcap.fill", .school) { SchoolHubView() }
            if hasUntis {
                tab("Noten", "chart.bar.fill", .noten) { GradesView() }
            }
            tab("Mensa", "fork.knife", .mensa) { MensaView() }
        }
        .tint(Palette.accent)
        .onAppear {
            // Aktiver Tab gehört zu WebUntis, Konto hat aber keins → auf Home.
            if !hasUntis, app.selectedTab == .timetable || app.selectedTab == .noten {
                app.selectedTab = .home
            }
        }
    }

    /// Beim Antippen des Stundenplan-Tabs „heute" signalisieren (auch beim Re-Tap).
    /// Zeigt die aktuelle Auswahl auf einen ausgeblendeten Tab (WebUntis fehlt),
    /// wird sie auf „Home" korrigiert → nie ein leerer Bildschirm.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: {
                if !hasUntis, app.selectedTab == .timetable || app.selectedTab == .noten {
                    return .home
                }
                return app.selectedTab
            },
            set: { newValue in
                if newValue == .timetable { app.timetableHomeSignal += 1 }
                app.selectedTab = newValue
            }
        )
    }

    private func tab<Content: View>(_ label: String, _ icon: String, _ value: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content().appBackground() }
            .tabItem { Label(label, systemImage: icon) }
            .tag(value)
    }
}
