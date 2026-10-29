import SwiftUI

/// Capsule track with a card-colored thumb that slides to the selection. Same look as Android;
/// on iOS it also answers with a light haptic.
public struct PokyhSegmentedControl<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Namespace private var thumb

    public init(_ options: [Value], selection: Binding<Value>, label: @escaping (Value) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(Motion.snappy) { selection = option }
                } label: {
                    Text(label(option))
                        .textStyle(selected ? TextStyle.footnote.weight(.semibold) : .footnote)
                        .foregroundStyle(selected ? Palette.accentText : Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, Spacing.xs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Palette.card)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(height: 44)
        .insetSurface(radius: 22)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The week's day pills: selected is a solid accent, today the accent wash, the rest cards.
public struct DayPills: View {
    let days: [Date]
    @Binding var selection: Int
    let isToday: (Date) -> Bool
    let weekday: (Date) -> String
    let dayNumber: (Date) -> String

    public init(days: [Date], selection: Binding<Int>, isToday: @escaping (Date) -> Bool, weekday: @escaping (Date) -> String, dayNumber: @escaping (Date) -> String) {
        self.days = days
        self._selection = selection
        self.isToday = isToday
        self.weekday = weekday
        self.dayNumber = dayNumber
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let selected = index == selection
                let today = isToday(day)
                Button {
                    withAnimation(Motion.snappy) { selection = index }
                } label: {
                    VStack(spacing: Spacing.xxs) {
                        Text(weekday(day)).textStyle(.caption2).opacity(0.8)
                        Text(dayNumber(day)).textStyle(.headline)
                    }
                    .foregroundStyle(selected ? Brand.onAccent : today ? Palette.accentText : Palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(selected ? Brand.accent : today ? Palette.accentTint : Palette.card, in: .pokyh(Radius.sm))
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
