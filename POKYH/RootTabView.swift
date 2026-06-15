import SwiftUI

/// Bottom-Navigation — Home · Stundenplan · Schule · Noten · Mensa.
struct RootTabView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView(selection: tabSelection) {
            tab("Home", "house.fill", .home) { HomeView() }
            tab("Stundenplan", "calendar", .timetable) { TimetableView() }
            tab("Schule", "graduationcap.fill", .school) { SchoolHubView() }
            tab("Noten", "chart.bar.fill", .noten) { GradesView() }
            tab("Mensa", "fork.knife", .mensa) { MensaView() }
        }
        .tint(Palette.accent)
    }

    /// Beim Antippen des Stundenplan-Tabs „heute" signalisieren (auch beim Re-Tap).
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { app.selectedTab },
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
