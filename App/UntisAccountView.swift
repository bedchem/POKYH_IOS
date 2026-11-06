import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import PokyhCore
import PokyhDesign

extension AppState {
    /// WebUntis took a new password, so the next silent sign-in has to use it: the saved one behind
    /// Face ID and the copy the watch signs in with. Nothing saved stays nothing saved, and an
    /// app key isn't the password, it goes on working without it.
    func keepNewPassword(_ password: String, for username: String) {
        let store = CredentialStore.shared
        // Right after a fresh sign-in nothing has unlocked the Keychain yet; the watch's copy of
        // that same sign-in tells a password from an app key without asking for Face ID.
        let saved = store.password(for: username, context: UnlockSession.context) ?? WatchSync.storedSecret(of: username)
        if store.hasPassword(username), !(saved.map(AppKey.isKey) ?? false) {
            Keychain.set(password: password, for: username)
        }
        WatchSync.passwordChanged(username: username, to: password)
    }
}

/// The WebUntis account as Konto & Sicherheit reads it, and what's being saved right now.
@Observable
final class UntisAccountModel {
    enum Load: Equatable {
        case loading, failed
        case ready(UntisAccount)
    }

    private(set) var load = Load.loading
    private(set) var saving = false
    private(set) var saveError: String?

    var account: UntisAccount? {
        if case .ready(let account) = load { account } else { nil }
    }

    /// Coming back to the page refreshes what's showing without taking it away.
    func reload(_ session: UserSession?) async {
        guard !saving else { return }
        if account == nil { load = .loading }
        guard let session else {
            load = .failed
            return
        }
        do {
            let fresh = try await UntisClient.shared.untisAccount(session)
            guard !Task.isCancelled else { return }
            load = .ready(fresh)
        } catch {
            guard !Task.isCancelled, account == nil else { return }
            load = .failed
        }
    }

    func change(_ update: (inout UntisAccount) -> Void) {
        guard var account else { return }
        update(&account)
        load = .ready(account)
    }

    func setForward(_ on: Bool, app: AppState) {
        save(app, optimistic: { $0.forwardToEmail = on }) { try await UntisClient.shared.saveUntisAccount($0, forwardToEmail: on) }
    }

    func setLanguage(_ key: String, app: AppState) {
        save(app, optimistic: { $0.languageCode = key }) { try await UntisClient.shared.saveUntisAccount($0, languageCode: key) }
    }

    /// One setting at a time. On a failure the row goes back and the reason shows under it.
    private func save(_ app: AppState, optimistic: (inout UntisAccount) -> Void, call: @escaping (UserSession) async throws -> Void) {
        guard let before = account, let session = app.session, !saving else { return }
        saving = true
        saveError = nil
        change(optimistic)
        Task {
            defer { saving = false }
            do {
                try await call(session)
            } catch let error as AppError where error.isSessionExpired {
                load = .ready(before)
                app.handleSessionExpired()
            } catch let error as AppError {
                load = .ready(before)
                saveError = error.message
            } catch {
                load = .ready(before)
                saveError = Strings.current.settings.saveError
            }
        }
    }
}

private enum UntisSheet: String, Identifiable {
    case email, password, reset, twoFactor
    var id: String { rawValue }
}

// ── Rows ─────────────────────────────────────────────────────────────────────

/// The top of Konto & Sicherheit: address, password, two-factor.
struct UntisSecurityRows: View {
    let model: UntisAccountModel
    @Environment(AppState.self) var app
    @Environment(\.strings) private var s
    @State private var sheet: UntisSheet?
    @State private var confirmDisable = false
    @State private var disabling = false
    @State private var disableError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            emailRow
            SettingsLinkRow(s.account.passwordTitle) {
                sheet = model.account?.passwordChangeAllowed ?? true ? .password : .reset
            }
            twoFactorRow
        }
        .task(id: app.session?.username) { await model.reload(app.session) }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .email: EmailSheet(model: model, current: model.account?.email ?? "")
            case .password: ChangePasswordSheet()
            case .reset: resetSheet
            case .twoFactor: TwoFactorSheet(model: model)
            }
        }
        .confirmationDialog(s.settings.tfDisableTitle, isPresented: $confirmDisable, titleVisibility: .visible) {
            Button(s.settings.tfDisableShort, role: .destructive) { Task { await disableTwoFactor() } }
            Button(s.common.cancel, role: .cancel) {}
        } message: {
            Text(s.settings.tfDisableText)
        }
    }

    @ViewBuilder private var resetSheet: some View {
        if let session = app.session {
            PasswordResetSheet(initialUsername: session.username, school: session.schoolRef)
        }
    }

    @ViewBuilder private var emailRow: some View {
        switch model.load {
        case .loading:
            VStack(alignment: .leading, spacing: 0) {
                SettingsRule()
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SkeletonBlock(height: 16).frame(width: 128)
                    SkeletonBlock(height: 14).frame(width: 200)
                }
                .padding(.vertical, Spacing.xl)
            }
        case .failed:
            SettingsRow(s.account.email, alert: s.account.accountError) {
                Button(s.common.retry) { Task { await model.reload(app.session) } }
                    .buttonStyle(.secondary(compact: true))
            }
        case .ready(let account):
            SettingsLinkRow(s.account.email, hint: account.hasEmail ? account.email : nil, action: { sheet = .email }) {
                if !account.hasEmail { ProfilePill(text: s.account.missing, tone: Decorative.blush) }
            }
        }
    }

    @ViewBuilder private var twoFactorRow: some View {
        if let account = model.account, account.offersTwoFactor {
            let on = ProfilePill(text: s.account.stateOn, tone: Decorative.sage, symbol: "checkmark")
            if !account.twoFactorEnabled {
                SettingsLinkRow(s.settings.acctTwoFactor) { sheet = .twoFactor } trailing: {
                    ProfilePill(text: s.account.stateOff, tone: Decorative.butter)
                }
            } else if account.twoFactorRequired {
                SettingsRow(s.settings.acctTwoFactor, hint: s.settings.acctTwoFactorRequired) { on }
            } else {
                SettingsLinkRow(s.settings.acctTwoFactor) { confirmDisable = true } trailing: {
                    if disabling { ProgressView().controlSize(.small) } else { on }
                }
                .disabled(disabling)
            }
            if let disableError {
                Text(disableError)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.dangerText)
                    .padding(.bottom, Spacing.md)
            }
        }
    }

    private func disableTwoFactor() async {
        guard let session = app.session else { return }
        disabling = true
        disableError = nil
        defer { disabling = false }
        do {
            try await UntisClient.shared.disableTwoFactor(session)
            model.change { $0.twoFactorEnabled = false }
        } catch let error as AppError where error.isSessionExpired {
            app.handleSessionExpired()
        } catch let error as AppError {
            disableError = error.message
        } catch {
            disableError = s.settings.saveError
        }
    }
}

/// Further down the group: messages by e-mail too, and WebUntis' own language.
struct UntisPreferenceRows: View {
    let model: UntisAccountModel
    @Environment(AppState.self) var app
    @Environment(\.strings) private var s

    var body: some View {
        if let account = model.account {
            SettingsRow(s.settings.acctForward, hint: account.hasEmail ? nil : s.settings.acctForwardNeedsEmail, alert: model.saveError) {
                Toggle(s.settings.acctForward, isOn: Binding(
                    get: { account.hasEmail && account.forwardToEmail },
                    set: { model.setForward($0, app: app) }
                ))
                .labelsHidden()
                .tint(Palette.accent)
                .disabled(!account.hasEmail || model.saving)
            }
            if !account.languages.isEmpty {
                SettingsRow(s.settings.untisLanguage) { languageMenu(account) }
            }
        }
    }

    private func languageMenu(_ account: UntisAccount) -> some View {
        Menu {
            Picker(s.settings.untisLanguage, selection: Binding(
                get: { account.languageCode },
                set: { model.setLanguage($0, app: app) }
            )) {
                ForEach(account.languages) { Text($0.name).tag($0.key) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(account.languageName)
                    .textStyle(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 40)
            .background(Palette.cardAlt, in: .capsule)
            .contentShape(.capsule)
        }
        .fixedSize()
        .disabled(model.saving)
    }
}

// ── Sheets ───────────────────────────────────────────────────────────────────

/// The frame all of them share.
private struct SheetPage<Content: View>: View {
    let title: String
    let busy: Bool
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) { content }
                    .padding(.horizontal, Spacing.screenH)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxxl)
                    .centeredForm()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }.disabled(busy)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(busy)
    }
}

private struct ProblemText: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .textStyle(.footnote)
                .foregroundStyle(Palette.dangerText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The big green tick at the end of a change.
private struct DoneMark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Palette.success)
            .frame(width: 64, height: 64)
            .accentSurface(radius: Radius.xl)
            .accessibilityHidden(true)
    }
}

private struct EmailSheet: View {
    let model: UntisAccountModel
    @Environment(AppState.self) var app
    @Environment(\.strings) private var s
    @State private var saved: String
    @State private var mail: String
    @State private var busy = false
    @State private var problem: String?
    @State private var done = false

    init(model: UntisAccountModel, current: String) {
        self.model = model
        _saved = State(initialValue: current)
        _mail = State(initialValue: current)
    }

    private var trimmed: String { mail.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SheetPage(title: s.settings.acctEmail, busy: busy) {
            PokyhTextField(placeholder: s.settings.acctEmail, text: $mail, symbol: "envelope")
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(busy)
                .onChange(of: mail) {
                    problem = nil
                    done = false
                }
            ProblemText(text: problem)
            if done {
                Text(s.settings.acctEmailSaved)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { Task { await save() } } label: {
                ButtonLabel(s.settings.acctEmailSave, busy: busy).frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(busy || trimmed == saved)
        }
        .sensoryFeedback(.success, trigger: done) { _, now in now }
    }

    private func save() async {
        guard let session = app.session else { return }
        let address = trimmed
        guard UntisAccount.isValidEmail(address) else {
            problem = s.settings.acctEmailInvalid
            return
        }
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await UntisClient.shared.saveUntisAccount(session, email: address)
            model.change { $0.email = address }
            saved = address
            done = true
        } catch let error as AppError where error.isSessionExpired {
            app.handleSessionExpired()
        } catch let error as AppError {
            problem = error.message
        } catch {
            problem = s.settings.saveError
        }
    }
}

/// The old password and the new one twice; WebUntis checks the old one and its own rules.
private struct ChangePasswordSheet: View {
    @Environment(AppState.self) var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s
    @State private var old = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var done = false
    @State private var resetting = false

    var body: some View {
        SheetPage(title: s.settings.changePassword, busy: busy) {
            if done {
                VStack(spacing: Spacing.md) {
                    DoneMark()
                    Text(s.profile.passwordChanged).textStyle(.headline).foregroundStyle(Palette.textPrimary)
                    Text(s.profile.passwordChangedText)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
                .transition(.opacity)
            } else {
                form
            }
        }
        .animation(.easeInOut(duration: Motion.standard), value: done)
        .sensoryFeedback(.success, trigger: done) { _, now in now }
        .sheet(isPresented: $resetting) {
            if let session = app.session {
                PasswordResetSheet(initialUsername: session.username, school: session.schoolRef)
            }
        }
    }

    @ViewBuilder private var form: some View {
        Group {
            PokyhTextField(s.profile.currentPassword, placeholder: s.profile.currentPassword, text: $old, symbol: "lock", secure: true)
                .textContentType(.password)
            PokyhTextField(s.profile.newPassword, placeholder: s.profile.newPassword, text: $new, symbol: "key", secure: true)
                .textContentType(.newPassword)
            PokyhTextField(s.profile.repeatPassword, placeholder: s.profile.repeatPassword, text: $repeated, symbol: "key", secure: true)
                .textContentType(.newPassword)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(busy)
        ProblemText(text: problem)
        Button { Task { await change() } } label: {
            ButtonLabel(s.profile.changePassword, busy: busy).frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(busy)
        TextLinkButton(s.account.passwordForgot, color: Palette.textSecondary) { resetting = true }
            .frame(maxWidth: .infinity)
    }

    private func change() async {
        guard let session = app.session else { return }
        switch PasswordChangeProblem.check(old: old, new: new, repeated: repeated) {
        case .missing: problem = s.profile.errBothPasswords; return
        case .mismatch: problem = s.profile.errPasswordsDiffer; return
        case .unchanged: problem = s.profile.errSamePassword; return
        case nil: break
        }
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await UntisClient.shared.changePassword(old: old, new: new, session)
            // First thing, whatever happens to this sheet: WebUntis only knows the new one now.
            app.keepNewPassword(new, for: session.username)
            old = ""
            new = ""
            repeated = ""
            done = true
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
        } catch let error as AppError where error.isSessionExpired {
            problem = s.common.sessionExpired
            app.handleSessionExpired()
        } catch let error as AppError {
            problem = error.message
        } catch {
            problem = s.profile.errPasswordFailed
        }
    }
}

/// As WebUntis' own wizard: what it means, then the new secret, then the app's first code turns
/// it on. The secret lives in this sheet while it's open and nowhere else.
private struct TwoFactorSheet: View {
    let model: UntisAccountModel
    @Environment(AppState.self) var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.strings) private var s
    @State private var setup: TwoFactorSetup?
    @State private var qr: UIImage?
    @State private var code = ""
    @State private var busy = false
    @State private var problem: String?
    @State private var copied = false
    @State private var done = false

    private var input: Binding<String> {
        // Digits only and never more than six. The sixth sends it, as iOS does with codes: the
        // number pad has no return key and covers the button on smaller phones.
        Binding(get: { code }, set: {
            let next = String(TwoFactorCode.digits($0).prefix(TwoFactorCode.length))
            let completed = next != code && TwoFactorCode.isComplete(next)
            code = next
            problem = nil
            if completed, !busy, let setup { Task { await enable(setup) } }
        })
    }

    var body: some View {
        SheetPage(title: done ? s.settings.tfDoneTitle : s.settings.tfTitle, busy: busy) {
            if done {
                finished
            } else if let setup {
                scan(setup)
            } else {
                intro
            }
            ProblemText(text: problem)
        }
        .animation(.easeInOut(duration: Motion.standard), value: done)
        .sensoryFeedback(.success, trigger: done) { _, now in now }
        .onDisappear {
            setup = nil
            qr = nil
            code = ""
        }
    }

    @ViewBuilder private var intro: some View {
        Text(s.settings.tfIntro)
            .textStyle(.callout)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        Button { Task { await start() } } label: {
            ButtonLabel(s.settings.tfStart, busy: busy).frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(busy)
    }

    @ViewBuilder private func scan(_ setup: TwoFactorSetup) -> some View {
        if let link = setup.link {
            // A QR code can't be scanned by the phone showing it, so this comes first.
            Button {
                openURL(link) { opened in
                    if !opened { problem = s.settings.tfNoApp }
                }
            } label: {
                ButtonLabel(s.settings.tfOpenApp, symbol: "lock.shield").frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondary)
        }
        if let qr {
            VStack(spacing: Spacing.sm) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(Spacing.sm)
                    // Black on white in dark mode too, or scanners give up.
                    .background(.white, in: .pokyh(Radius.md))
                    .privacySensitive()
                    .accessibilityLabel(s.settings.tfScan)
                Text(s.settings.tfScan)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(s.settings.tfManual).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
            HStack(spacing: Spacing.md) {
                Text(setup.groupedSecret)
                    .textStyle(TextStyle(15, 21, .semibold, relativeTo: .callout, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .privacySensitive()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(copied ? s.settings.tfCopied : s.settings.tfCopy) { copy(setup.secret) }
                    .buttonStyle(.plain)
                    .textStyle(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accentText)
            }
            .padding(Spacing.lg)
            .nestedSurface(radius: Radius.lg)
        }
        PokyhTextField(s.settings.tfCode, placeholder: "123456", text: input, symbol: "number")
            .keyboardType(.numberPad)
            // Lets the Passwords app offer the code it just learned.
            .textContentType(.oneTimeCode)
            .autocorrectionDisabled()
            .disabled(busy)
        Button { Task { await enable(setup) } } label: {
            ButtonLabel(s.settings.tfEnable, busy: busy).frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .disabled(busy || !TwoFactorCode.isComplete(code))
    }

    private var finished: some View {
        VStack(spacing: Spacing.md) {
            DoneMark()
            Text(s.settings.tfDoneNote)
                .textStyle(.footnote.weight(.semibold))
                .foregroundStyle(Palette.warning)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { dismiss() } label: {
                Text(s.common.close).frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .transition(.opacity)
    }

    /// Not to other devices through the shared clipboard, and not for long.
    private func copy(_ secret: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: secret]],
                                      options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
        copied = true
    }

    private func start() async {
        guard let session = app.session else { return }
        busy = true
        problem = nil
        defer { busy = false }
        do {
            let fresh = try await UntisClient.shared.startTwoFactorSetup(session)
            qr = fresh.link.flatMap(QRCode.image)
            setup = fresh
        } catch let error as AppError where error.isSessionExpired {
            app.handleSessionExpired()
        } catch let error as AppError {
            problem = error.message
        } catch {
            problem = s.settings.saveError
        }
    }

    private func enable(_ setup: TwoFactorSetup) async {
        guard let session = app.session else { return }
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await UntisClient.shared.enableTwoFactor(session, secret: setup.secret, code: code)
            model.change { $0.twoFactorEnabled = true }
            self.setup = nil
            qr = nil
            code = ""
            done = true
        } catch let error as AppError where error.isSessionExpired {
            app.handleSessionExpired()
        } catch let error as AppError {
            code = ""
            problem = error.message
        } catch {
            code = ""
            problem = s.settings.saveError
        }
    }
}

/// Drawn right here, so the link with the secret in it goes through no service.
private enum QRCode {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func image(for link: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return context.createCGImage(scaled, from: scaled.extent).map { UIImage(cgImage: $0) }
    }
}
