import SwiftUI
import PokyhCore
import PokyhDesign

/// Sign-in, Android's calm auth layout: mark, big title, two fields, one button, all on the
/// plain canvas with no card. `isAdditional` is the "Konto hinzufügen" / "Passwort nötig" sheet.
struct LoginView: View {
    var isAdditional = false
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s

    @State private var username = ""
    @State private var password = ""
    @State private var saveCredentials = true
    @State private var showPassword = false
    @State private var size: CGSize = .zero
    @FocusState private var focus: Field?

    enum Field { case user, pass }

    // Android sets the title in its display face at 44.
    private static let titleStyle = TextStyle(44, 44, .heavy, tracking: -0.022, relativeTo: .largeTitle)

    /// Wide windows get Android's split: the mark on a panel of its own beside the form.
    private var wide: Bool { !isAdditional && WidthClass(width: size.width) == .expanded }

    var body: some View {
        HStack(spacing: 0) {
            if wide {
                brandPanel
                    .frame(width: size.width * 0.55)
                    .transition(.opacity)
            }
            ScrollView {
                form
                    .padding(.horizontal, Spacing.screenH)
                    .centeredForm(maxWidth: wide ? 420 : WidthClass.formMaxWidth)
                    // Wide windows center the form beside the panel instead of hanging it from the top.
                    .frame(minHeight: wide ? size.height : nil)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.bg.ignoresSafeArea())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .animation(.easeOut(duration: Motion.fast), value: app.error)
        .animation(.easeInOut(duration: Motion.standard), value: app.busy)
        .toolbar {
            if isAdditional {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .onAppear {
            app.error = nil
            if let u = app.prefillUsername { username = u; app.prefillUsername = nil; focus = .pass }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: isAdditional ? Spacing.lg : Spacing.huge)

            VStack(spacing: Spacing.lg) {
                if !wide { AppLogo(size: 84) }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(s.login.signIn)
                        .textStyle(Self.titleStyle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(s.login.subtitle)
                        .textStyle(.callout)
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fadeIn()

            Spacer().frame(height: Spacing.xxl)

            VStack(spacing: Spacing.md) {
                field(s.login.username, text: $username, field: .user, symbol: "person", secure: false)
                    .submitLabel(.next)
                    .onSubmit { focus = .pass }
                field(s.login.password, text: $password, field: .pass, symbol: "key", secure: true)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }

                if app.biometricAvailable { biometricToggle }

                if let err = app.error {
                    Text(err)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                Button { Task { await submit() } } label: {
                    HStack(spacing: Spacing.sm) {
                        if app.busy { ProgressView().controlSize(.small).tint(.white) }
                        Text(app.busy ? (app.statusText.isEmpty ? s.login.signingIn : app.statusText) : s.login.signIn)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(app.busy || username.isEmpty || password.isEmpty)
                .padding(.top, Spacing.xs)
            }
            .fadeIn(delay: 0.05)

            Spacer().frame(height: Spacing.xxl)
            finePrint
            Spacer().frame(height: Spacing.huge)
        }
    }

    /// Android's PokyhTextField: recessed fill, accent ring and icon while focused. Built here
    /// rather than taken from the package so the keyboard can hop from one field to the next.
    private func field(_ placeholder: String, text: Binding<String>, field: Field, symbol: String, secure: Bool) -> some View {
        let focused = focus == field
        let prompt = Text(placeholder).foregroundStyle(Palette.textTertiary)
        return HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(focused ? Palette.accentText : Palette.textTertiary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Group {
                if secure && !showPassword {
                    SecureField("", text: text, prompt: prompt)
                } else {
                    TextField("", text: text, prompt: prompt)
                }
            }
            .textStyle(.body)
            .foregroundStyle(Palette.textPrimary)
            .tint(Palette.accent)
            .textContentType(secure ? .password : .username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            .accessibilityLabel(placeholder)

            if secure {
                Button {
                    showPassword.toggle()
                    // Swapping SecureField for TextField drops the focus; keep typing.
                    focus = .pass
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPassword ? s.login.hidePassword : s.login.showPassword)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(minHeight: 52)
        .background(Palette.cardAlt, in: .pokyh(Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(focused ? Palette.accent : .clear, lineWidth: 1.5)
        }
        .contentShape(.rect)
        .onTapGesture { focus = field }
        .animation(.easeOut(duration: Motion.fast), value: focused)
    }

    private var biometricToggle: some View {
        Toggle(isOn: $saveCredentials) {
            HStack(spacing: Spacing.md) {
                Image(systemName: app.biometricInfo.symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 20)
                Text(s.login.saveBiometric)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .tint(Palette.accent)
        .padding(.vertical, Spacing.xs)
    }

    /// Age, then the legal pages where the data is entered (Art. 13 DSGVO), on one line.
    private var finePrint: some View {
        FlowRow(spacing: Spacing.lg, lineSpacing: Spacing.xs) {
            Text(s.login.ageShort)
                .textStyle(.caption)
                .foregroundStyle(Palette.textTertiary)
            ForEach(legalLinks, id: \.title) { link in
                Link(destination: link.url) {
                    Text(link.title).textStyle(.caption.weight(.semibold))
                }
                .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var legalLinks: [(title: String, url: URL)] {
        [(s.login.privacyLink, Config.privacyURL), (s.login.terms, Config.termsURL)]
            .compactMap { title, string in URL(string: string).map { (title, $0) } }
    }

    // MARK: - Wide panel

    private var brandPanel: some View {
        VStack(spacing: Spacing.xl) {
            AppLogo(size: min(200, size.width * 0.16))
            Text("POKYH")
                .textStyle(.wordmark)
                .foregroundStyle(Palette.textPrimary)
        }
        .fadeIn()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.card, in: .pokyh(Radius.xxl))
        .padding(Spacing.lg)
    }

    private func submit() async {
        guard !username.isEmpty, !password.isEmpty else { return }
        focus = nil
        await app.loginNew(username: username, password: password, save: saveCredentials)
        if isAdditional && app.session != nil { dismiss() }
    }
}

/// Lays its children out in centered lines, wrapping like text.
private struct FlowRow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(for: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - line.width) / 2
            for index in line.indices {
                let item = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - item.height) / 2), proposal: ProposedViewSize(item))
                x += item.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private func lines(for maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let item = subviews[index].sizeThatFits(.unspecified)
            if !line.indices.isEmpty, line.width + spacing + item.width > maxWidth {
                lines.append(line)
                line = Line()
            }
            line.width += (line.indices.isEmpty ? 0 : spacing) + item.width
            line.height = max(line.height, item.height)
            line.indices.append(index)
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }
}
