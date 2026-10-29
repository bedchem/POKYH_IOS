import SwiftUI
import PokyhCore

/// Every token and component on one screen, for checking them against Android side by side.
public struct DesignCatalog: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    section("Palette") {
                        swatches([
                            ("bg", Palette.bg), ("card", Palette.card), ("cardAlt", Palette.cardAlt),
                            ("nested", Palette.nested), ("nav", Palette.nav), ("accentTint", Palette.accentTint),
                        ])
                        swatches([
                            ("accent", Brand.accent), ("success", Brand.success), ("warning", Brand.warning),
                            ("danger", Brand.danger), ("orange", Brand.orange), ("star", Brand.star),
                        ])
                    }
                    section("Decorative") {
                        HStack(spacing: Spacing.sm) {
                            ForEach(Array(Decorative.all.enumerated()), id: \.offset) { _, tone in
                                Text("Aa")
                                    .textStyle(.headline)
                                    .foregroundStyle(tone.ink)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .background(tone.fill, in: .pokyh(Radius.md))
                            }
                        }
                    }
                    section("Subjects") {
                        HStack(spacing: Spacing.sm) {
                            ForEach(["D", "M", "IT", "ENGL", "Bew.Sport"], id: \.self) { name in
                                let tone = Tone.subject(name)
                                Text(name)
                                    .textStyle(.gridCellSubject)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, Spacing.xs)
                                    .foregroundStyle(tone.ink)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(tone.fill, in: .pokyh(Radius.sm))
                            }
                        }
                    }
                    section("Components") {
                        ComponentSamples()
                    }
                    section("Type") {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Display").textStyle(.display)
                            Text("Large Title").textStyle(.largeTitle)
                            Text("Title 1").textStyle(.title1)
                            Text("Headline").textStyle(.headline)
                            Text("Body text for reading.").textStyle(.body)
                            Text("Footnote").textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                            Text("LABEL").textStyle(.label).foregroundStyle(Palette.textTertiary)
                            Text("7,85").textStyle(.statLarge).foregroundStyle(Palette.grade(7.85))
                        }
                        .foregroundStyle(Palette.textPrimary)
                        .padding(Spacing.card)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                    }
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.vertical, Spacing.lg)
                .readableContent()
            }
            .screenBackground()
            .navigationTitle("Design")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title.uppercased())
                .textStyle(.label)
                .foregroundStyle(Palette.textTertiary)
            content()
        }
    }

    private func swatches(_ items: [(String, Color)]) -> some View {
        HStack(spacing: Spacing.sm) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: Spacing.xs) {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(color)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).stroke(Palette.border))
                    Text(name).textStyle(.caption2).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
        }
    }
}

#Preview {
    DesignCatalog()
}
