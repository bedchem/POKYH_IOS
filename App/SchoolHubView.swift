import SwiftUI
import PokyhCore
import PokyhDesign

/// The school hub: color-blocked tiles for everything without a tab of its own, in the web's
/// order. Tones cycle by position, so the grid repeats four tones instead of growing a fifth.
struct SchoolHubView: View {
    @Environment(AppState.self) var app
    @Environment(\.strings) private var s

    private enum Destination: Hashable {
        case messages, absences, todos, reminders, classreg, klasse
    }

    private struct HubItem: Identifiable {
        let destination: Destination
        let title: String
        let symbol: String
        var id: Destination { destination }
    }

    @State private var path: Destination?

    private var hasUntis: Bool { app.session?.hasUntis ?? true }
    private var hasBackend: Bool { app.session?.hasBackend ?? false }

    private var items: [HubItem] {
        let t = s.school
        var list: [HubItem] = []
        if hasUntis {
            list.append(HubItem(destination: .messages, title: s.nav.messages, symbol: "envelope.fill"))
            list.append(HubItem(destination: .absences, title: t.absences, symbol: "person.fill.xmark"))
        }
        list.append(HubItem(destination: .todos, title: t.todos, symbol: "checklist"))
        // Parent accounts see the class but not its reminders.
        if !app.isParent {
            list.append(HubItem(destination: .reminders, title: t.reminders, symbol: "bell.fill"))
        }
        if hasUntis {
            list.append(HubItem(destination: .classreg, title: t.classreg, symbol: "book.closed.fill"))
        }
        if hasUntis || hasBackend {
            list.append(HubItem(destination: .klasse, title: t.klasse, symbol: "person.3.fill"))
        }
        return list
    }

    /// The class and the school, like the web's hub.
    private var subtitle: String {
        [app.session?.klasseName ?? "", app.session?.schoolRef.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    FeatureTile(item.title, tone: Decorative.cycle(index), symbol: item.symbol, height: 132) {
                        path = item.destination
                    }
                    .fadeIn(delay: Double(index / 2) * 0.05)
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxl)
        }
        .navigationTitle(s.nav.school)
        .navigationSubtitle(subtitle)
        // Back on this tab it's the six tiles again, not the page left open before.
        .onChange(of: app.selectedTab) { _, tab in
            guard tab != .school, path != nil else { return }
            var quietly = Transaction()
            quietly.disablesAnimations = true
            withTransaction(quietly) { path = nil }
        }
        .profileToolbar()
        .appBackground()
        .pushed(item: $path) { destination in
            switch destination {
            case .messages: MessagesView()
            case .absences: AbsencesView()
            case .todos: TodosView()
            case .reminders: RemindersView()
            case .classreg: ClassregEventsView()
            case .klasse: ClassView()
            }
        }
    }
}
