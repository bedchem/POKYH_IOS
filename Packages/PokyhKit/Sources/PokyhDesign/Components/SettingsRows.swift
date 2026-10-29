import SwiftUI

// Settings and profile lay their rows out on the canvas under thin rules, no cards,
// the way the web settings page does. Bigger, bolder type than the rest of the app.

enum SettingsType {
    static let pageTitle = TextStyle(34, 36, .heavy, tracking: -0.02, relativeTo: .largeTitle)
    static let pageLead = TextStyle(15, 24, .regular, relativeTo: .subheadline)
    static let groupTitle = TextStyle(22, 28, .heavy, tracking: -0.01, relativeTo: .title2)
    static let rowTitle = TextStyle(16.5, 22, .bold, tracking: -0.005, relativeTo: .body)
    static let rowHint = TextStyle(14.5, 22.5, .regular, relativeTo: .subheadline)
    static let rowValue = TextStyle(15, 21, .semibold, relativeTo: .subheadline)
}

public struct SettingsPageHeader: View {
    let title: String
    let lead: String?

    public init(_ title: String, lead: String? = nil) {
        self.title = title
        self.lead = lead
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).textStyle(SettingsType.pageTitle).foregroundStyle(Palette.textPrimary)
            if let lead {
                Text(lead).textStyle(SettingsType.pageLead).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.lg)
        .padding(.bottom, 28)
    }
}

public struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .textStyle(SettingsType.groupTitle)
                .foregroundStyle(Palette.textPrimary)
                .padding(.bottom, Spacing.md)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

public struct SettingsRule: View {
    public init() {}

    public var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// Title, hint and an optional alert line on the left, the control on the right.
/// Stacks the control under the text when the two don't fit side by side.
public struct SettingsItem<Control: View>: View {
    let title: String
    let hint: String?
    let alert: String?
    let danger: Bool
    let control: Control

    public init(_ title: String, hint: String? = nil, alert: String? = nil, danger: Bool = false, @ViewBuilder control: () -> Control = { EmptyView() }) {
        self.title = title
        self.hint = hint
        self.alert = alert
        self.danger = danger
        self.control = control()
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsRule()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Spacing.xxxl) {
                    text
                    Spacer(minLength: 0)
                    control
                }
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    text
                    control
                }
            }
            .padding(.vertical, Spacing.xl)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .textStyle(SettingsType.rowTitle)
                .foregroundStyle(danger ? Palette.dangerText : Palette.textPrimary)
            if let hint {
                Text(hint).textStyle(SettingsType.rowHint).foregroundStyle(Palette.textSecondary)
            }
            if let alert {
                Text(alert).textStyle(SettingsType.rowHint.weight(.semibold)).foregroundStyle(Palette.dangerText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A value shown in a settings row, e.g. the current language.
public struct SettingsValue: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text).textStyle(SettingsType.rowValue).foregroundStyle(Palette.textSecondary)
    }
}
