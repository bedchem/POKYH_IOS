import SwiftUI

/// Recessed field with an accent ring on focus, label above as an eyebrow.
public struct PokyhTextField: View {
    let label: String?
    let placeholder: String
    let symbol: String?
    let secure: Bool
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var revealed = false

    public init(_ label: String? = nil, placeholder: String, text: Binding<String>, symbol: String? = nil, secure: Bool = false) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.symbol = symbol
        self.secure = secure
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let label {
                EyebrowLabel(label, color: Palette.textSecondary)
            }
            HStack(spacing: Spacing.md) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(focused ? Palette.accentText : Palette.textTertiary)
                        .frame(width: 20)
                }
                field
                    .textStyle(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .tint(Brand.accent)
                    .focused($focused)
                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 52)
            .insetSurface(radius: Radius.md)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(focused ? Brand.accent : .clear, lineWidth: 1.5)
            }
            .animation(.easeOut(duration: Motion.fast), value: focused)
        }
    }

    @ViewBuilder private var field: some View {
        let prompt = Text(placeholder).foregroundStyle(Palette.textTertiary)
        if secure && !revealed {
            SecureField("", text: $text, prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt)
        }
    }
}
