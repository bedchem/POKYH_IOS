import SwiftUI
import PokyhCore
import PokyhDesign

/// Home · Stundenplan · Schule · Noten · Mensa, in Android's order. A tab bar on the iPhone,
/// a sidebar on wide iPad windows (Android's side rail).
struct RootTabView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s

    /// Accounts that only exist on the POKYH backend have no timetable or grades,
    /// so those two tabs go away.
    private var hasUntis: Bool { app.session?.hasUntis ?? true }

    var body: some View {
        TabView(selection: tabSelection) {
            tab(.home)
            if hasUntis { tab(.timetable) }
            tab(.school)
            if hasUntis { tab(.noten) }
            tab(.mensa)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Palette.accent)
        .onAppear {
            // The stored tab belongs to WebUntis but this account has none.
            if !hasUntis, app.selectedTab == .timetable || app.selectedTab == .noten {
                app.selectedTab = .home
            }
        }
    }

    /// Tapping Stundenplan (again) jumps it back to today. A selection pointing at a hidden
    /// tab falls back to Home, so there's never an empty screen.
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

    private func tab(_ value: AppTab) -> some TabContent<AppTab> {
        Tab(value: value) {
            NavigationStack { screen(value).appBackground(wide: value == .home || value == .timetable) }
        } label: {
            // Outline normally, filled when selected, like Android's Phosphor pair.
            Label(title(value), systemImage: value == tabSelection.wrappedValue ? value.selectedSymbol : value.symbol)
                .environment(\.symbolVariants, .none)
        }
    }

    private func title(_ value: AppTab) -> String {
        switch value {
        case .home: s.nav.home
        case .timetable: s.nav.timetable
        case .school: s.nav.school
        case .noten: s.nav.grades
        case .mensa: s.nav.mensa
        }
    }

    @ViewBuilder
    private func screen(_ value: AppTab) -> some View {
        switch value {
        case .home: HomeView()
        case .timetable: TimetableView()
        case .school: SchoolHubView()
        case .noten: GradesView()
        case .mensa: MensaView()
        }
    }
}

private extension AppTab {
    // Phosphor House, CalendarBlank, GraduationCap, ChartBar, ForkKnife.
    // calendar and fork.knife have no filled twin; the tint carries their selection.
    var symbol: String {
        switch self {
        case .home: "house"
        case .timetable: "calendar"
        case .school: "graduationcap"
        case .noten: "chart.bar"
        case .mensa: "fork.knife"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .home: "house.fill"
        case .timetable: "calendar"
        case .school: "graduationcap.fill"
        case .noten: "chart.bar.fill"
        case .mensa: "fork.knife"
        }
    }
}
