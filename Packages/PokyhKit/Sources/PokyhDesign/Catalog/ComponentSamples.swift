import SwiftUI
import PokyhCore

private struct SampleRow: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
}

/// Live samples for the catalog. Not used by the app itself.
struct ComponentSamples: View {
    @State private var segment = 0
    @State private var day = 1
    @State private var text = ""
    @State private var password = ""

    private let rows = [
        SampleRow(id: 0, title: "Mathematik", subtitle: "3 Noten · Schnitt 7,5"),
        SampleRow(id: 1, title: "Deutsch", subtitle: "2 Noten · Schnitt 8,0"),
        SampleRow(id: 2, title: "Englisch", subtitle: "4 Noten · Schnitt 6,8"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            PokyhSegmentedControl([0, 1, 2], selection: $segment) { ["Woche", "Tag", "Liste"][$0] }

            DayPills(
                days: (0..<5).map { Calendar.current.date(byAdding: .day, value: $0, to: .now)! },
                selection: $day,
                isToday: { Calendar.current.isDateInToday($0) },
                weekday: { $0.formatted(.dateTime.weekday(.abbreviated)) },
                dayNumber: { $0.formatted(.dateTime.day()) }
            )

            ListCard(rows) { row in
                PokyhRow(row.title, subtitle: row.subtitle, action: {}) {
                    IconTile("book.closed.fill", color: Palette.subject(row.title), size: 40)
                } trailing: {
                    Text("7,5").textStyle(.statSmall).foregroundStyle(Palette.grade(7.5))
                }
            }

            HStack(spacing: Spacing.md) {
                FeatureTile("Abwesenheiten", subtitle: "Fehlstunden & Entschuldigungen", tone: Decorative.periwinkle, symbol: "person.badge.clock") {}
                FeatureTile("Nachrichten", tone: Decorative.butter, symbol: "envelope") {}
            }

            PokyhCard {
                HStack {
                    StatView("7,82", label: "Schnitt", valueColor: Palette.grade(7.82))
                    Spacer()
                    StatView("12", label: "Noten")
                    Spacer()
                    StatView("4,2 %", label: "Abwesend")
                }
            }

            HStack(spacing: Spacing.sm) {
                TagChip("Entfall", symbol: "xmark", color: Brand.danger)
                TagChip("Prüfung", symbol: "pencil", color: Brand.warning)
                TagChip("Vertretung", color: Brand.orange)
                MiniBadge("NEU", color: Brand.accent)
                UnreadBadge(3)
            }

            PokyhTextField("Benutzername", placeholder: "vorname.nachname", text: $text, symbol: "person")
            PokyhTextField("Passwort", placeholder: "••••••••", text: $password, symbol: "lock", secure: true)

            VStack(spacing: Spacing.sm) {
                Button {} label: { ButtonLabel("Anmelden", symbol: "arrow.right") }
                    .buttonStyle(.primary)
                    .frame(maxWidth: .infinity)
                Button("Später") {}.buttonStyle(.secondary)
                Button("Abmelden") {}.buttonStyle(.destructive)
            }

            InlineNotice("Du bist offline. Angezeigt wird der Stand von heute, 07:42.", symbol: "wifi.slash", tint: Brand.warning)

            VStack(spacing: Spacing.sm) {
                SkeletonBlock(height: 18)
                SkeletonBlock(height: 18).padding(.trailing, 80)
            }
            .padding(Spacing.card)
            .cardSurface()

            HStack {
                InitialAvatar("Max Muster", color: Palette.avatar(hue: 0.62))
                InitialAvatar("Anna", color: Palette.avatar(hue: 0.1), size: 32)
                Spacer()
                FloatingActionButton("Neues To-do") {}
            }
        }
    }
}
