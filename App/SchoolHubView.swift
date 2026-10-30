import SwiftUI
import PokyhCore
import PokyhDesign

/// The school hub: color-blocked tiles for everything without a tab of its own, in the web's
/// order. Tones cycle by position, so the grid repeats four tones instead of growing a fifth.
struct SchoolHubView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s

    private enum Destination: Hashable {
        case messages, absences, todos, reminders, classreg, klasse
    }

    private struct HubItem: Identifiable {
        let destination: Destination
        let title: String
        let subtitle: String
        let symbol: String
        var id: Destination { destination }
    }

    @State private var path: Destination?

    private var hasUntis: Bool { app.session?.hasUntis ?? true }
    private var hasBackend: Bool { app.session?.apiToken != nil }

    private var items: [HubItem] {
        let t = s.school
        var list: [HubItem] = []
        if hasUntis {
            list.append(HubItem(destination: .messages, title: s.nav.messages, subtitle: t.messagesInfo, symbol: "envelope.fill"))
            list.append(HubItem(destination: .absences, title: t.absences, subtitle: t.absencesInfo, symbol: "person.fill.xmark"))
        }
        list.append(HubItem(destination: .todos, title: t.todos, subtitle: t.todosInfo, symbol: "checklist"))
        // Parent accounts see the class but not its reminders.
        if !app.isParent {
            list.append(HubItem(destination: .reminders, title: t.reminders, subtitle: t.remindersInfo, symbol: "bell.fill"))
        }
        if hasUntis {
            list.append(HubItem(destination: .classreg, title: t.classreg, subtitle: t.classregInfo, symbol: "book.closed.fill"))
        }
        if hasUntis || hasBackend {
            list.append(HubItem(destination: .klasse, title: t.klasse, subtitle: t.klasseInfo, symbol: "person.3.fill"))
        }
        return list
    }

    /// "4BFS · LBS Brixen", like the web's hub.
    private var subtitle: String {
        [app.session?.klasseName ?? "", DefaultSchool.name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    FeatureTile(item.title, subtitle: item.subtitle, tone: Decorative.cycle(index), symbol: item.symbol, height: 168) {
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
        .profileToolbar()
        .appBackground()
        .navigationDestination(item: $path) { destination in
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
