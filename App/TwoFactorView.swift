import SwiftUI
import UIKit
import PokyhCore
import PokyhDesign

/// WebUntis wants the authenticator app's code: the password was right. `wrongCode`: one was
/// sent and it was wrong or has expired.
struct TwoFactorRequired: Error {
    let wrongCode: Bool
}

/// A sign-in waiting for that code. The password stays in memory only, while the prompt is up.
struct TwoFactorRequest: Equatable {
    let username: String
    let password: String
    let save: Bool
    let school: School
    var wrongCode: Bool
    var checking = false
    var problem: String?
}

/// The prompt itself, Android's TwoFactorDialog. Stays up while the code is checked, and says
/// there what went wrong, because the screen underneath can't.
struct TwoFactorCard: View {
    let request: TwoFactorRequest
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.strings) private var s
    @State private var code = ""
    @FocusState private var focused: Bool

    private var input: Binding<String> {
        Binding(get: { code }, set: { code = TwoFactorCode.input($0) })
    }

    private var canSubmit: Bool { TwoFactorCode.isComplete(code) && !request.checking }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(s.login.codeTitle)
                .textStyle(.title2)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(s.login.codeHint)
                .textStyle(.callout)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = request.problem ?? (request.wrongCode ? s.login.codeWrong : nil) {
                Text(message)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                EyebrowLabel(s.login.codeLabel, color: Palette.textSecondary)
                TextField("", text: input, prompt: Text(verbatim: "123 456").foregroundStyle(Palette.textTertiary))
                    .keyboardType(.numberPad)
                    // Lets the Passwords app and SMS suggest the code above the keyboard.
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .textStyle(.statMedium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textPrimary)
                    .tint(Brand.accent)
                    .focused($focused)
                    .disabled(request.checking)
                    .padding(.horizontal, Spacing.lg)
                    .frame(minHeight: 56)
                    .insetSurface(radius: Radius.md)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(focused ? Brand.accent : .clear, lineWidth: 1.5)
                    }
                    .accessibilityLabel(s.login.codeLabel)
            }
            .padding(.top, Spacing.xs)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.md) { buttons }
                VStack(spacing: Spacing.sm) { buttons }
            }
            .padding(.top, Spacing.sm)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 400)
        .floatingSurface(radius: Radius.xl)
        .padding(.horizontal, Spacing.screenH)
        .onAppear { focused = true }
        // A wrong code is of no more use, the next one goes in an empty field.
        .onChange(of: request.wrongCode) { _, wrong in
            if wrong {
                code = ""
                focused = true
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        Button(s.common.cancel, action: onCancel)
            .buttonStyle(.secondary)
            .disabled(request.checking)
            .frame(maxWidth: .infinity)
        Button {
            onSubmit(code)
        } label: {
            if request.checking {
                ProgressView().tint(.white)
            } else {
                Text(s.login.codeConfirm)
            }
        }
        .buttonStyle(.primary)
        .disabled(!canSubmit)
        .frame(maxWidth: .infinity)
    }
}

private struct TwoFactorHost: View {
    @ObservedObject var app: AppState

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                Group {
                    if let request = app.twoFactor {
                        TwoFactorCard(
                            request: request,
                            onSubmit: { code in Task { await app.submitTwoFactorCode(code) } },
                            onCancel: { app.cancelTwoFactor() }
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.never)
        }
        .background(Color.black.opacity(0.42).ignoresSafeArea())
        .environment(\.strings, Strings.of(LanguageChoice.current(in: .standard)))
        .preferredColorScheme(app.colorScheme)
        .tint(Palette.accent)
    }
}

/// A window over the app's own, like PrivacyShield below it in ContentView.swift: the code can be
/// asked for while a sheet is up (adding an account, switching in the profile), and a sheet can't
/// be presented over another from the root. PrivacyShield stays above this one, so the app
/// switcher never shows the prompt.
@MainActor
enum TwoFactorPresenter {
    private static var window: UIWindow?

    static func show(_ app: AppState) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let host = UIHostingController(rootView: TwoFactorHost(app: app))
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.backgroundColor = .clear
        window.windowLevel = .alert
        window.alpha = 0
        window.makeKeyAndVisible()
        UIView.animate(withDuration: Motion.fast) { window.alpha = 1 }
        self.window = window
    }

    static func hide() {
        guard let leaving = window else { return }
        window = nil
        let scene = leaving.windowScene
        UIView.animate(withDuration: Motion.fast) {
            leaving.alpha = 0
        } completion: { _ in
            leaving.isHidden = true
        }
        scene?.windows.first { $0 !== leaving && $0.windowLevel == .normal && !$0.isHidden }?.makeKey()
    }
}

#Preview("Asking") {
    TwoFactorCard(request: .init(username: "anna", password: "", save: false, school: .fallback, wrongCode: false),
                  onSubmit: { _ in }, onCancel: {})
}

#Preview("Wrong code") {
    TwoFactorCard(request: .init(username: "anna", password: "", save: false, school: .fallback, wrongCode: true),
                  onSubmit: { _ in }, onCancel: {})
}
