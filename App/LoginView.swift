import SwiftUI
import PokyhCore
import PokyhDesign

/// Sign-in, Android's calm auth layout: mascot, big title, then two steps like WebUntis itself:
/// first the school (any school on WebUntis, through the public search), then the account.
/// `isAdditional` is the "Konto hinzufügen" / "Passwort nötig" sheet.
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

    /// Remembered until the end of the school year, so the next sign-in starts at the password.
    @State private var school: School? = SchoolChoice.read()
    private let lastSchool = SchoolChoice.read()
    @State private var schoolQuery = ""
    @State private var lookup: SchoolLookup = .idle
    @State private var loginOptions: LoginOptions?
    @State private var resetting = false
    @State private var officeOpen = false

    // What the mascot answers: the keys and what happens to the form.
    @State private var keys = 0
    @State private var mascotEvent: MascotEvent?
    @State private var taps: Int64 = 0

    enum Field { case user, pass, school }

    enum SchoolLookup: Equatable { case idle, searching, done(SchoolSearch) }

    // Android sets the title in its display face at 44.
    private static let titleStyle = TextStyle(44, 44, .heavy, tracking: -0.022, relativeTo: .largeTitle)

    /// Wide windows get Android's split: the mascot large on a panel of its own beside the form.
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
            if let u = app.prefillUsername {
                username = u
                app.prefillUsername = nil
                // A saved account signs in at its own school; one saved before the search, at the fallback.
                if app.accounts.contains(where: { $0.username.caseInsensitiveCompare(u) == .orderedSame }) {
                    school = app.school(for: u)
                }
                if school != nil { focus = .pass }
            }
        }
        .onChange(of: schoolQuery) { _, query in search(query) }
        // A failed attempt: the mascot wobbles.
        .onChange(of: app.error) { _, error in
            if error != nil { mascotEvent = MascotEvent(.error, n: Self.now) }
        }
        .task(id: school) {
            loginOptions = nil
            guard let school else { return }
            loginOptions = await BackendClient.shared.loginOptions(for: school)
        }
        .sheet(isPresented: $resetting) {
            PasswordResetSheet(initialUsername: username, school: school ?? lastSchool ?? .fallback)
        }
        .sheet(isPresented: $officeOpen) {
            if let school {
                OfficeSignInSheet(school: school, initialUser: username) { user, key in
                    username = user
                    SchoolChoice.save(school)
                    await app.loginNew(username: user, password: AppKey.prefix + key, save: saveCredentials, school: school)
                    if isAdditional && app.session != nil { dismiss() }
                }
            }
        }
    }

    /// Searches a moment after the last key, as the web does.
    private func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { lookup = .idle; return }
        guard q.count >= 3 else { lookup = .done(.tooShort); return }
        lookup = .searching
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard q == schoolQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            let answer = await BackendClient.shared.searchSchools(q)
            guard q == schoolQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            lookup = .done(answer)
        }
    }

    // MARK: - Mascot

    private static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private var mascot: LoginMascotBadge {
        LoginMascotBadge(
            state: LoginMascotState(
                focus: focus == .user ? .user : focus == .pass ? .password : nil,
                username: username,
                showPassword: showPassword,
                loading: app.busy,
                keys: keys,
                event: mascotEvent
            ),
            onTap: {
                taps += 1
                mascotEvent = MascotEvent(.tap, n: taps)
            },
            maxWidth: wide ? 560 : 252
        )
    }

    /// The field's text, counting keys for the mascot. Several characters at once is the phone
    /// filling the form in (autofill, a paste): one event for both fields.
    private func typed(_ text: Binding<String>) -> Binding<String> {
        Binding {
            text.wrappedValue
        } set: { new in
            let old = text.wrappedValue
            text.wrappedValue = new
            guard new != old else { return }
            keys += 1
            guard new.count - old.count >= 3 else { return }
            if let last = mascotEvent, last.kind == .autofill, Self.now - last.n < 1500 { return }
            mascotEvent = MascotEvent(.autofill, n: Self.now)
        }
    }

    private func pick(_ picked: School) {
        // Remembered as soon as it's picked, as on the web.
        SchoolChoice.save(picked)
        school = picked
        schoolQuery = ""
        lookup = .idle
        focus = username.isEmpty ? .user : .pass
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: isAdditional ? Spacing.lg : Spacing.huge)

            VStack(spacing: Spacing.lg) {
                if !wide { mascot }
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

            if let chosen = school {
                accountStep(chosen)
                    .fadeIn(delay: 0.05)
            } else {
                schoolStep
                    .fadeIn(delay: 0.05)
            }

            Spacer().frame(height: Spacing.xxl)
            finePrint
            Spacer().frame(height: Spacing.huge)
        }
    }

    private var passwordAllowed: Bool { loginOptions?.password != false }

    private func accountStep(_ chosen: School) -> some View {
        VStack(spacing: Spacing.md) {
            // Choosing another keeps this one offered first in the list.
            SchoolChip(school: chosen) {
                school = nil
                focus = .school
            }

            if loginOptions?.office365 == true {
                OfficeButton(showOr: passwordAllowed) { officeOpen = true }
            }

            if passwordAllowed {
                field(s.login.username, text: typed($username), field: .user, symbol: "person", secure: false)
                    .submitLabel(.next)
                    .onSubmit { focus = .pass }
                field(s.login.password, text: typed($password), field: .pass, symbol: "key", secure: true)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
            }

            if app.biometricAvailable { biometricToggle }

            if let err = app.error {
                Text(err)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if passwordAllowed {
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

            TextLinkButton(s.login.forgotPassword) { resetting = true }
                .frame(maxWidth: .infinity)
        }
    }

    private var schoolStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            searchField

            if lookup == .searching {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Palette.accent)
                    .padding(.horizontal, Spacing.md)
                    .transition(.opacity)
            }
            if let message = lookupMessage {
                Text(message)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .transition(.opacity)
            }
            ForEach(foundSchools) { found in
                SchoolRow(school: found) { pick(found) }
            }
            if schoolQuery.isEmpty, let lastSchool {
                SchoolRow(school: lastSchool, caption: s.login.schoolLast) { pick(lastSchool) }
            }
        }
        .animation(.easeOut(duration: Motion.fast), value: lookup)
    }

    private var foundSchools: [School] {
        if case .done(.found(let list)) = lookup { return list }
        return []
    }

    private var lookupMessage: String? {
        guard case .done(let answer) = lookup else { return nil }
        switch answer {
        case .tooShort: return s.login.schoolShort
        case .tooMany: return s.login.schoolTooMany
        case .rateLimited: return s.login.schoolRate
        case .failed: return s.login.schoolError
        case .found(let list): return list.isEmpty ? s.login.schoolNone : nil
        }
    }

    private var searchField: some View {
        let focused = focus == .school
        return HStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(focused ? Palette.accentText : Palette.textTertiary)
                .frame(width: 20)
                .accessibilityHidden(true)
            TextField("", text: $schoolQuery, prompt: Text(s.login.schoolPlaceholder).foregroundStyle(Palette.textTertiary))
                .textStyle(.body)
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focus, equals: .school)
                .accessibilityLabel(s.login.schoolLabel)
            if !schoolQuery.isEmpty {
                Button { schoolQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.login.schoolClear)
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
        .onTapGesture { focus = .school }
        .animation(.easeOut(duration: Motion.fast), value: focused)
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
                Text(app.biometricInfo.phrase(s.login.saveBiometric, s.lang))
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .tint(Palette.accent)
        .padding(.vertical, Spacing.xs)
    }

    /// Age, then the legal pages where the data is entered (Art. 13 DSGVO), imprint and terms.
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
        [(s.login.privacyLink, Config.privacyURL), (s.login.imprint, Config.imprintURL), (s.login.terms, Config.termsURL)]
            .compactMap { title, string in URL(string: string).map { (title, $0) } }
    }

    // MARK: - Wide panel

    private var brandPanel: some View {
        mascot
            .padding(Spacing.xxxl)
            .fadeIn()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.card, in: .pokyh(Radius.xxl))
            .padding(Spacing.lg)
    }

    private func submit() async {
        guard !username.isEmpty, !password.isEmpty, let school else { return }
        focus = nil
        SchoolChoice.save(school)
        await app.loginNew(username: username, password: password, save: saveCredentials, school: school)
        if isAdditional && app.session != nil { dismiss() }
    }
}

// MARK: - School

/// Initials on a tone per school, so results are told apart at a glance.
private struct SchoolBadge: View {
    let school: School

    var body: some View {
        let tone = Decorative.all[Self.stableHash(school.loginName) % Decorative.all.count]
        Text(initials)
            .textStyle(.footnote.weight(.heavy))
            .foregroundStyle(tone.ink)
            .frame(width: 40, height: 40)
            .background(tone.fill, in: .pokyh(Radius.sm))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = school.name.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "–" })
            .filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        let letters = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return (letters.isEmpty ? String(school.loginName.prefix(2)) : letters).uppercased()
    }

    /// Same tone on every launch (Swift's own hash changes per run), like Java's hashCode.
    private static func stableHash(_ text: String) -> Int {
        var h: Int32 = 0
        for unit in text.utf16 { h = h &* 31 &+ Int32(unit) }
        return Int(h.magnitude)
    }
}

/// A school as a row: badge, name, address.
private struct SchoolRow: View {
    let school: School
    var caption: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                SchoolBadge(school: school)
                VStack(alignment: .leading, spacing: 1) {
                    if let caption {
                        Text(caption).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                    }
                    Text(school.name.isEmpty ? school.loginName : school.name)
                        .textStyle(.callout.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                    if !school.address.isEmpty {
                        Text(school.address)
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.rowPress(radius: Radius.md))
    }
}

/// The chosen school above the account form, with the way back to choose another.
private struct SchoolChip: View {
    let school: School
    let change: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.md) {
            SchoolBadge(school: school)
            VStack(alignment: .leading, spacing: 2) {
                Text(school.name.isEmpty ? school.loginName : school.name)
                    .textStyle(.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Label {
                    Text(s.login.serverShort(school.server)).lineLimit(1)
                } icon: {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
                }
                .labelStyle(.titleAndIcon)
                .textStyle(.caption)
                .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
            Button(action: change) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 36, height: 36)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.login.schoolChange)
        }
        .padding(.leading, Spacing.sm)
        .padding(.trailing, Spacing.xs)
        .padding(.vertical, Spacing.sm)
        .background(Palette.cardAlt, in: .pokyh(Radius.lg))
    }
}

// MARK: - Office 365

/// Microsoft's four squares, the mark of every "sign in with Microsoft" button.
private struct MicrosoftMark: View {
    var size: CGFloat = 18
    // Microsoft's own brand colours.
    private static let colors: [Color] = [Color(hex: 0xF25022), Color(hex: 0x7FBA00), Color(hex: 0x00A4EF), Color(hex: 0xFFB900)]

    var body: some View {
        let cell = size / 2 - 1
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow { square(0, cell); square(1, cell) }
            GridRow { square(2, cell); square(3, cell) }
        }
        .accessibilityHidden(true)
    }

    private func square(_ i: Int, _ cell: CGFloat) -> some View {
        Rectangle().fill(Self.colors[i]).frame(width: cell, height: cell)
    }
}

/// "Mit Office 365 anmelden", first, as on the school's own WebUntis page.
private struct OfficeButton: View {
    let showOr: Bool
    let action: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Button(action: action) {
                HStack(spacing: 10) {
                    MicrosoftMark()
                    Text(s.login.office)
                        .textStyle(.callout.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Palette.card, in: .pokyh(Radius.lg))
                .contentShape(.rect)
            }
            .buttonStyle(.pressable)
            if showOr {
                Text(s.login.or).textStyle(.caption).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// Office 365 schools sign their people in through Microsoft, which only WebUntis can finish.
/// POKYH signs in with the app key WebUntis shows every account instead: the steps to it, with
/// links into the school's own WebUntis, then user and key.
private struct OfficeSignInSheet: View {
    let school: School
    let initialUser: String
    let submit: (_ user: String, _ key: String) async -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.strings) private var s
    @State private var user = ""
    @State private var key = ""
    @State private var problem: String?

    init(school: School, initialUser: String, submit: @escaping (_ user: String, _ key: String) async -> Void) {
        self.school = school
        self.initialUser = initialUser
        self.submit = submit
        _user = State(initialValue: initialUser)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack(spacing: 10) {
                        MicrosoftMark(size: 22)
                        Text(s.login.office).textStyle(.title2).foregroundStyle(Palette.textPrimary)
                    }
                    Text(s.login.officeLead).textStyle(.callout).foregroundStyle(Palette.textSecondary)

                    SignInStep(1, s.login.officeStep1) {
                        TextLinkButton(s.login.officeOpenLogin, symbol: "arrow.up.right") { open("/basic/login") }
                    }
                    SignInStep(2, s.login.officeStep2) {
                        TextLinkButton(s.login.officeOpenProfile, symbol: "arrow.up.right") { open("/basic/profile") }
                        Text(s.login.officeAdmin).textStyle(.caption).foregroundStyle(Palette.textTertiary)
                    }
                    SignInStep(3, s.login.officeStep3) {
                        // The system's paste button: no "allow paste" prompt.
                        PasteButton(payloadType: String.self) { texts in
                            guard let text = texts.first else { return }
                            Task { @MainActor in if !take(text) { problem = s.login.errKeyInvalid } }
                        }
                        .buttonBorderShape(.capsule)
                        .tint(Palette.accent)
                        .labelStyle(.titleAndIcon)
                        .padding(.top, Spacing.xs)
                    }

                    PokyhTextField(s.login.officeUser, placeholder: s.login.officeUser, text: $user, symbol: "person")
                        .textContentType(.username)
                        .onChange(of: user) { _, value in
                            if value.count > 30, take(value) { return }
                            if value.count > 100 { user = String(value.prefix(100)) }
                        }
                    PokyhTextField(s.login.officeKey, placeholder: s.login.officeKey, text: $key, symbol: "key", secure: true)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: key) { _, value in
                            if value.count > 30, take(value) { return }
                            if value.count > 200 { key = String(value.prefix(200)) }
                        }
                    Text(s.login.officeKeyHint).textStyle(.caption).foregroundStyle(Palette.textTertiary)

                    if let message = problem ?? app.error {
                        Text(message).textStyle(.footnote).foregroundStyle(Palette.danger)
                    }

                    Button {
                        Task { await signIn() }
                    } label: {
                        ButtonLabel(app.busy ? s.login.signingIn : s.login.signIn, busy: app.busy)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    .disabled(app.busy)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, Spacing.screenH)
                .padding(.bottom, Spacing.xxl)
                .centeredForm()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .onAppear { app.error = nil }
    }

    private func open(_ fragment: String) {
        if let url = school.page(fragment) { openURL(url) }
    }

    /// WebUntis' table copied whole (or the QR code's link) fills both fields.
    @discardableResult
    private func take(_ text: String) -> Bool {
        let parsed = AppKey.parse(text)
        guard let k = parsed.key else { return false }
        key = k
        if let u = parsed.user { user = u }
        problem = nil
        return true
    }

    private func signIn() async {
        problem = nil
        let u = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !key.isEmpty else { problem = s.login.errKeyMissing; return }
        let k = AppKey.normalise(key)
        guard !k.isEmpty else { problem = s.login.errKeyInvalid; return }
        await submit(u, k)
    }
}

private struct SignInStep<Extra: View>: View {
    let number: Int
    let text: String
    let extra: Extra

    init(_ number: Int, _ text: String, @ViewBuilder extra: () -> Extra) {
        self.number = number
        self.text = text
        self.extra = extra()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text("\(number)")
                .textStyle(.caption.weight(.bold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24, height: 24)
                .background(Palette.nested, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).textStyle(.callout).foregroundStyle(Palette.textPrimary)
                extra
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Password reset

/// "Passwort vergessen": username and the e-mail address stored in WebUntis; WebUntis sends a
/// link for a new password. POKYH never sees a password here.
private struct PasswordResetSheet: View {
    let school: School
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.strings) private var s
    @State private var username: String
    @State private var email = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    init(initialUsername: String, school: School) {
        self.school = school
        _username = State(initialValue: initialUsername.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if sent { done } else { form }
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.bottom, Spacing.xxxl)
                .centeredForm()
                .animation(.easeInOut(duration: Motion.standard), value: sent)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle(s.login.resetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(s.login.resetLead).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
            PokyhTextField(s.login.resetUser, placeholder: s.login.resetUser, text: $username, symbol: "person")
                .textContentType(.username)
            PokyhTextField(s.login.resetEmail, placeholder: s.login.resetEmail, text: $email, symbol: "envelope")
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
            if let error {
                Text(error).textStyle(.footnote).foregroundStyle(Palette.danger)
            }
            Button {
                Task { await send() }
            } label: {
                ButtonLabel(s.login.resetSend, symbol: "paperplane", busy: sending)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(sending || username.trimmingCharacters(in: .whitespaces).isEmpty || email.trimmingCharacters(in: .whitespaces).isEmpty)

            // WebUntis' own page of the school.
            if let url = school.page("/basic/resetPassword") {
                TextLinkButton(s.login.resetOfficial, symbol: "arrow.up.right", color: Palette.textSecondary) { openURL(url) }
                    .frame(maxWidth: .infinity)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private var done: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Palette.success)
                .frame(width: 64, height: 64)
                .accentSurface(radius: Radius.xl)
            Text(s.login.resetSentTitle).textStyle(.headline).foregroundStyle(Palette.textPrimary)
            Text(s.login.resetSentText)
                .textStyle(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text(s.common.done).frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .padding(.top, Spacing.sm)
        }
        .padding(.vertical, Spacing.xl)
        .transition(.opacity)
    }

    private func send() async {
        guard !sending else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            try await UntisClient.shared.requestPasswordReset(username: username, email: email, school: school)
            sent = true
        } catch let e as AppError {
            error = e.message
        } catch {
            self.error = s.login.resetUnreachable
        }
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
