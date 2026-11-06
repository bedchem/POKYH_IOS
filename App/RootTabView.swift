import SwiftUI
import PokyhCore
import PokyhDesign

/// Home · Stundenplan · Schule · Noten · Mensa, in Android's order, plus the search tab.
/// A tab bar on the iPhone, a sidebar on wide iPad windows (Android's side rail).
struct RootTabView: View {
    @Environment(AppState.self) var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var searching = false
    /// Built once per account and kept while the search is closed.
    @State private var search = SearchModel()

    /// Accounts that only exist on the POKYH backend have no timetable or grades,
    /// so those two tabs go away.
    private var hasUntis: Bool { app.session?.hasUntis ?? true }

    /// A compact tab bar holds five tabs; a sixth would push Mensa and the search into "More".
    /// Then the search sits in the tab roots' toolbar instead, beside the messages.
    private var searchIsTab: Bool { sizeClass == .regular || !hasUntis }

    /// Read here rather than from the environment: a language picked in the settings has to
    /// reach every tab and sheet at once, and this view redraws whenever AppState changes.
    private var strings: Strings { Strings.of(LanguageChoice.current(in: .standard)) }

    var body: some View {
        let s = strings
        TabView(selection: selection) {
            tab(.home, s)
            if hasUntis { tab(.timetable, s) }
            tab(.school, s)
            if hasUntis { tab(.noten, s) }
            tab(.mensa, s)
            if searchIsTab {
                Tab(s.search.title, systemImage: "magnifyingglass", value: RootTab.search, role: .search) {
                    NavigationStack {
                        SearchView(inTab: true) { leave(to: $0) }.appBackground()
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The bar stays as it is: same size, same place, on every screen.
        .tabBarMinimizeBehavior(.never)
        .tint(Palette.accent)
        .modifier(RecapHost())
        .modifier(AnnouncementPopupHost())
        .modifier(WebSignInHost(scanning: .constant(false), working: .constant(false), takesLinks: true))
        .environment(\.strings, s)
        .environment(\.searchInToolbar, !searchIsTab)
        .environment(search)
        // Turned sideways mid-search, the sheet goes but the search tab takes over with the same words.
        .onChange(of: searchIsTab) { _, isTab in searching = isTab && !search.query.isEmpty }
        .onAppear {
            // The stored tab belongs to WebUntis but this account has none.
            if !hasUntis, app.selectedTab == .timetable || app.selectedTab == .noten {
                app.selectedTab = .home
            }
        }
        .onChange(of: app.selectedTab) {
            searching = false
            Task { await app.refreshUnread() }
        }
        .task {
            // Home loads the inbox itself at launch; a moment's wait usually finds that count fresh.
            try? await Task.sleep(for: .seconds(2))
            await app.refreshUnread()
        }
    }

    /// A selection pointing at a hidden tab falls back to Home, so there's never an empty screen.
    private var shownTab: AppTab {
        if !hasUntis, app.selectedTab == .timetable || app.selectedTab == .noten { return .home }
        return app.selectedTab
    }

    /// Tapping Stundenplan (again) jumps it back to today.
    private var selection: Binding<RootTab> {
        Binding(
            get: { searching && searchIsTab ? .search : .app(shownTab) },
            set: { newValue in
                switch newValue {
                case .search:
                    searching = true
                case .app(let tab):
                    if tab == .timetable { app.timetableHomeSignal += 1 }
                    searching = false
                    app.selectedTab = tab
                }
            }
        )
    }

    /// A search result that lives in a tab: go there without the "back to today" tap behaviour.
    private func leave(to tab: AppTab) {
        searching = false
        app.selectedTab = tab
    }

    private func tab(_ value: AppTab, _ s: Strings) -> some TabContent<RootTab> {
        Tab(value: RootTab.app(value)) {
            NavigationStack { screen(value).appBackground(wide: value == .home || value == .timetable) }
        } label: {
            // Outline normally, filled when selected, like Android's Phosphor pair.
            Label(title(value, s), systemImage: value == shownTab && !searching ? value.selectedSymbol : value.symbol)
                .environment(\.symbolVariants, .none)
        }
        // Messages live under Schule, so that's where their unread count shows.
        .badge(value == .school ? app.unreadBadge : 0)
    }

    private func title(_ value: AppTab, _ s: Strings) -> String {
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

/// The tab bar's selection: one of the app's tabs, or the search.
private enum RootTab: Hashable {
    case app(AppTab)
    case search
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
