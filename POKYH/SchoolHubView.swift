import SwiftUI

struct SchoolHubView: View {
    @EnvironmentObject var app: AppState

    private struct HubItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let accent: Color
        let destination: AnyView?   // nil → stattdessen Tab wechseln
        let tab: AppTab?
    }

    private var items: [HubItem] {
        // Wichtiges oben: Noten → Todos → Erinnerungen → Abwesenheiten → Klassenbuch → Klasse.
        // Nachrichten ist über den Briefumschlag-Button oben rechts erreichbar.
        // „Noten" wechselt zur Noten-Tab (Navbar), Rest navigiert innerhalb von Schule.
        var list: [HubItem] = [
            HubItem(title: "Noten", subtitle: "Alle Fächer & Bewertungen", icon: "chart.bar.fill", accent: Palette.accent, destination: nil, tab: .noten),
        ]
        if !app.isParent {
            list.append(HubItem(title: "Todos", subtitle: "Persönliche Aufgabenliste", icon: "checklist", accent: Palette.accentSoft, destination: AnyView(TodosView()), tab: nil))
            list.append(HubItem(title: "Erinnerungen", subtitle: "Hausaufgaben & Klassen-Erinnerungen", icon: "bell.fill", accent: Palette.tint, destination: AnyView(RemindersView()), tab: nil))
        }
        list.append(HubItem(title: "Abwesenheiten", subtitle: "Fehlstunden & Entschuldigungen", icon: "person.fill.xmark", accent: Palette.orange, destination: AnyView(AbsencesView()), tab: nil))
        list.append(HubItem(title: "Klassenbuch", subtitle: "Klassenbuch-Einträge", icon: "book.closed.fill", accent: Palette.orange, destination: AnyView(ClassregEventsView()), tab: nil))
        list.append(HubItem(title: "Klasse", subtitle: "Klassenmitglieder & Code", icon: "person.3.fill", accent: Palette.tint, destination: AnyView(ClassView()), tab: nil))
        return list
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    Group {
                        if let dest = item.destination {
                            NavigationLink { dest } label: { card(item) }
                        } else {
                            Button { if let t = item.tab { app.selectedTab = t } } label: { card(item) }
                        }
                    }
                    .buttonStyle(.pressable)
                    .fadeIn(delay: Double(idx) * 0.04)
                }
            }
            .padding(16)
        }
        .navigationTitle("Schule")
        .profileToolbar()
        .appBackground()
    }

    private func card(_ item: HubItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon).font(.title2).foregroundStyle(item.accent)
                .frame(width: 46, height: 46)
                .background(item.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).foregroundStyle(Palette.textPrimary)
                Text(item.subtitle).font(.caption).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.textTertiary)
        }
        .padding(14)
        .cardSurface()
    }
}
