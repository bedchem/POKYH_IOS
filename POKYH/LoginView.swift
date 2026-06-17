import SwiftUI

struct LoginView: View {
    var isAdditional = false
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var saveCredentials = true
    @FocusState private var focus: Field?

    enum Field { case user, pass }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.accent.opacity(0.22), Palette.accentSoft.opacity(0.1), Palette.bg],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: isAdditional ? 24 : 64)

                    VStack(spacing: 12) {
                        AppLogo(size: 84)
                        Text("POKYH").font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                        Text("Schulapp für die LBS Brixen")
                            .font(.subheadline).foregroundStyle(Palette.textSecondary)
                    }
                    .fadeIn()

                    VStack(spacing: 14) {
                        field("Benutzername", text: $username, field: .user, icon: "person.fill", secure: false)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.next).onSubmit { focus = .pass }
                        field("Passwort", text: $password, field: .pass, icon: "lock.fill", secure: true)
                            .submitLabel(.go).onSubmit { Task { await submit() } }

                        if app.biometricAvailable {
                            Toggle(isOn: $saveCredentials) {
                                Label("Mit \(app.biometricInfo.typeName) speichern", systemImage: app.biometricInfo.symbol)
                                    .font(.subheadline)
                            }
                            .tint(Palette.accent)
                        }

                        if let err = app.error {
                            Text(err).font(.footnote).foregroundStyle(Palette.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }

                        Button { Task { await submit() } } label: {
                            HStack(spacing: 8) {
                                if app.busy { ProgressView().tint(.white) }
                                Text(app.busy ? (app.statusText.isEmpty ? "Anmelden…" : app.statusText) : "Anmelden")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity).frame(height: 52)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Palette.accent)
                        .disabled(app.busy || username.isEmpty || password.isEmpty)
                        .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .padding(.horizontal, 20)
                    .fadeIn(delay: 0.05)

                    Text("Melde dich mit deinem WebUntis-Konto an.")
                        .font(.caption).foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .centeredForm()
            }
        }
        .animation(.easeInOut, value: app.error)
        .animation(.easeInOut, value: app.busy)
        .toolbar {
            if isAdditional {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .onAppear {
            app.error = nil
            if let u = app.prefillUsername { username = u; app.prefillUsername = nil; focus = .pass }
        }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, field: Field, icon: String, secure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 22)
            Group {
                if secure { SecureField(placeholder, text: text) }
                else { TextField(placeholder, text: text) }
            }
            .focused($focus, equals: field)
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(Palette.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submit() async {
        guard !username.isEmpty, !password.isEmpty else { return }
        focus = nil
        await app.loginNew(username: username, password: password,
                           save: saveCredentials)
        if isAdditional && app.session != nil { dismiss() }
    }
}
