import SwiftUI
import PokyhCore
import PokyhDesign
import UserNotifications
import Combine

// Profile and settings lay their rows out on the canvas under thin rules, no cards, the way the
// web's settings page does. Settings is its own page behind the gear, like on Android.

/// Bigger, bolder type than the rest of the app (PokyhDesign's SettingsType, which isn't public).
private enum ProfileType {
    static let name = TextStyle(32, 34, .heavy, tracking: -0.05, relativeTo: .largeTitle)
    static let meta = TextStyle(15, 21, .regular, relativeTo: .subheadline)
    static let groupTitle = TextStyle(22, 28, .heavy, tracking: -0.01, relativeTo: .title2)
    static let lead = TextStyle(15, 24, .regular, relativeTo: .subheadline)
    static let rowTitle = TextStyle(16.5, 22, .bold, tracking: -0.005, relativeTo: .body)
    static let rowHint = TextStyle(14.5, 22.5, .regular, relativeTo: .subheadline)
    static let rowValue = TextStyle(15.5, 21, .semibold, relativeTo: .subheadline)
    static let pill = TextStyle(13, 16, .bold, relativeTo: .footnote)
}

/// Between two settings groups.
private let groupGap: CGFloat = 56

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    @State private var confirmLogout = false
    @State private var accountToRemove: SavedAccount?
    @State private var renameTarget: SavedAccount?
    @State private var renameText = ""
    @State private var showConnectionStatus = false
    @State private var showSettings = false
    @State private var switchingTo: String?
    @State private var switchError: String?

    /// The default account always first, then the active one, then by name.
    private var sortedAccounts: [SavedAccount] {
        app.accounts.sorted { a, b in
            let aDefault = a.username == app.defaultUsername
            let bDefault = b.username == app.defaultUsername
            if aDefault != bDefault { return aDefault }
            let aActive = a.username == app.session?.username
            let bActive = b.username == app.session?.username
            if aActive != bActive { return aActive }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private var switchSpring: Animation { .spring(response: 0.46, dampingFraction: 0.72) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let session = app.session {
                    ProfileHeader(session: session).fadeIn()
                }
                accountsSection.fadeIn(delay: 0.06)
                if let session = app.session {
                    accountGroup(session)
                        .padding(.top, groupGap)
                        .fadeIn(delay: 0.1)
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, 80)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(s.profile.title)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(s.profile.settings)
            }
        }
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
        .modifier(ProfileDialogs(
            confirmLogout: $confirmLogout,
            accountToRemove: $accountToRemove,
            renameTarget: $renameTarget,
            renameText: $renameText,
            switchError: $switchError
        ))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: switchingTo)
        .animation(switchSpring, value: app.session?.username)
        .animation(switchSpring, value: app.defaultUsername)
        .animation(switchSpring, value: app.accounts)
        .sensoryFeedback(.success, trigger: app.session?.username)
        .sensoryFeedback(.selection, trigger: app.defaultUsername)
        .sheet(isPresented: $app.showAddAccount) {
            NavigationStack { LoginView(isAdditional: true) }
        }
        .sheet(isPresented: $showConnectionStatus) {
            if let s = app.session { ConnectionStatusView(session: s) }
        }
    }

    // ── Accounts ─────────────────────────────────────────────────────────────

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(s.profile.accounts)
                .textStyle(ProfileType.groupTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(s.account.accountsHint)
                .textStyle(ProfileType.lead)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 6)
                .padding(.bottom, Spacing.md)
            ForEach(sortedAccounts) { acc in
                AccountRow(
                    account: acc,
                    isActive: acc.username == app.session?.username,
                    isDefault: acc.username == app.defaultUsername,
                    hasPassword: app.accountHasPassword(acc.username),
                    isSwitching: acc.username == switchingTo,
                    busy: switchingTo != nil,
                    onSwitch: { switchTo(acc) },
                    menu: { accountMenu(acc) }
                )
            }
            AddAccountRow { app.showAddAccount = true }
        }
    }

    private func switchTo(_ acc: SavedAccount) {
        Task {
            withAnimation(switchSpring) { switchingTo = acc.username }
            await app.switchAccount(username: acc.username)
            withAnimation(switchSpring) { switchingTo = nil }
            let switched = app.session?.username == acc.username
            if switched {
                dismiss()
            } else if !app.showAddAccount, let e = app.error {
                switchError = e
                app.error = nil
            }
        }
    }

    @ViewBuilder
    private func accountMenu(_ acc: SavedAccount) -> some View {
        if acc.username == app.defaultUsername {
            Button { withAnimation(switchSpring) { app.defaultUsername = nil } } label: {
                Label(s.profile.unsetDefault, systemImage: "star.slash")
            }
        } else {
            Button { withAnimation(switchSpring) { app.defaultUsername = acc.username } } label: {
                Label(s.profile.setDefault, systemImage: "star")
            }
        }
        Button {
            Task { await app.refreshAccount(username: acc.username) }
        } label: {
            Label(s.profile.refreshAccount, systemImage: "arrow.clockwise")
        }
        Button {
            renameText = acc.nickname ?? ""
            renameTarget = acc
        } label: {
            Label(s.profile.rename, systemImage: "pencil")
        }
        if app.accountHasPassword(acc.username) {
            Button { app.signOutAccount(username: acc.username) } label: {
                Label(s.profile.signOut, systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        Button(role: .destructive) { accountToRemove = acc } label: {
            Label(s.profile.removeAccount, systemImage: "trash")
        }
    }

    // ── Account ──────────────────────────────────────────────────────────────

    private func accountGroup(_ session: UserSession) -> some View {
        let p = s.profile
        let details: [(label: String, value: String, copy: Bool, mono: Bool)] = [
            (p.username, session.username, true, false),
            (p.studentId, session.hasUntis && session.studentId > 0 ? "\(session.studentId)" : "", true, false),
            (p.klasse, session.klasseName, false, false),
            (s.account.schoolLabel, DefaultSchool.name, false, false),
            (p.userId, session.stableUid ?? "", true, true),
            (p.classIdLabel, session.classId ?? "", true, true),
        ].filter { !$0.value.isEmpty }

        return SettingsGroup(p.account) {
            ForEach(details, id: \.label) { d in
                SettingsRow(d.label) {
                    HStack(spacing: 6) {
                        Text(d.value)
                            .textStyle(d.mono ? TextStyle(14, 20, .regular, relativeTo: .subheadline, design: .monospaced) : ProfileType.rowValue)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if d.copy { CopyValueButton(value: d.value, label: d.label) }
                    }
                }
            }
            SettingsLinkRow(p.pokyhAccount, action: { showConnectionStatus = true }) {
                let connected = app.backendStatus == .connected
                ProfilePill(text: BackendStatusText.label(app.backendStatus, s), tone: connected ? Decorative.sage : Decorative.butter)
            }
            SettingsLinkRow(p.settings, hint: s.account.settingsHint) { showSettings = true }
            SettingsLinkRow(s.account.website, hint: s.account.websiteHint, external: true) {
                openURL(AppConfig.current.websiteURL)
            }
            LogoutRow { confirmLogout = true }
        }
    }
}

/// The picture, the name large beside it, class, school and role under it.
private struct ProfileHeader: View {
    let session: UserSession
    @Environment(\.strings) private var s
    @State private var pictureOpen = false

    var body: some View {
        let name = session.personName ?? session.username
        let meta = [session.klasseName, DefaultSchool.name, session.isParent ? s.profile.parent : s.profile.student]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        HStack(spacing: Spacing.xl) {
            Button { pictureOpen = true } label: {
                AvatarView(url: session.imageUrl, name: name, size: 88, colorSeed: session.username)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(s.profile.openPicture)
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .textStyle(ProfileType.name)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(meta)
                    .textStyle(ProfileType.meta)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.huge)
        .fullScreenCover(isPresented: $pictureOpen) {
            ZStack {
                Color.black.opacity(0.82).ignoresSafeArea()
                VStack(spacing: Spacing.xl) {
                    AvatarView(url: session.imageUrl, name: name, size: 280, colorSeed: session.username)
                    Text(name).textStyle(.title2).foregroundStyle(.white)
                }
                .padding(Spacing.xxxl)
            }
            .contentShape(.rect)
            .onTapGesture { pictureOpen = false }
            .presentationBackground(.clear)
        }
    }
}

/// A saved account as a row under a rule: its picture (ringed while signed in), name and badges,
/// who it is, and its menu.
private struct AccountRow<MenuItems: View>: View {
    let account: SavedAccount
    let isActive: Bool
    let isDefault: Bool
    let hasPassword: Bool
    let isSwitching: Bool
    let busy: Bool
    let onSwitch: () -> Void
    @ViewBuilder let menu: () -> MenuItems
    @Environment(\.strings) private var s

    var body: some View {
        let secondary = account.nickname?.isEmpty == false
            ? "\(account.username) · \(account.displayName)" : account.displayName
        VStack(spacing: 0) {
            SettingsRule()
            HStack(spacing: 14) {
                Button(action: onSwitch) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Brand.accent).opacity(isActive ? 1 : 0)
                            AvatarView(url: account.imageUrl, name: account.title, size: isActive ? 38 : 44, colorSeed: account.username)
                                .scaleEffect(isSwitching ? 1.08 : 1)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Spacing.sm) {
                                Text(account.title)
                                    .textStyle(ProfileType.rowTitle)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                if isDefault {
                                    ProfilePill(text: s.profile.standard, tone: Decorative.periwinkle, symbol: "star.fill")
                                        .transition(.scale.combined(with: .opacity))
                                }
                                if !hasPassword {
                                    ProfilePill(text: s.profile.needsPassword, tone: Decorative.butter)
                                }
                            }
                            Text(secondary)
                                .textStyle(ProfileType.rowHint)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if isSwitching {
                            ProgressView().controlSize(.small).tint(Brand.accent)
                                .transition(.scale.combined(with: .opacity))
                        } else if isActive {
                            Image(systemName: "checkmark")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Brand.accent)
                                .symbolEffect(.bounce, value: isActive)
                                .accessibilityLabel(s.profile.activeAccount)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, Spacing.md)
                    .contentShape(.rect)
                }
                .buttonStyle(.rowPress(radius: 14))
                .disabled(busy || isActive)

                Menu { menu() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.circle)
                }
                .accessibilityLabel(s.common.more)
                .disabled(busy)
            }
            .padding(.vertical, 6)
        }
    }
}

/// "Konto hinzufügen", the last row of the accounts, in the accent.
private struct AddAccountRow: View {
    let action: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        VStack(spacing: 0) {
            SettingsRule()
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 44, height: 44)
                        .background(Palette.accentTint, in: .circle)
                    Text(s.profile.addAccount)
                        .textStyle(ProfileType.rowTitle)
                        .foregroundStyle(Palette.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.rowPress(radius: 14))
            .padding(.vertical, 6)
        }
    }
}

/// Every confirmation of the profile page in one place.
private struct ProfileDialogs: ViewModifier {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s
    @Binding var confirmLogout: Bool
    @Binding var accountToRemove: SavedAccount?
    @Binding var renameTarget: SavedAccount?
    @Binding var renameText: String
    @Binding var switchError: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(s.settings.logoutTitle, isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(s.settings.logout, role: .destructive) { app.logout(); dismiss() }
                if let u = app.session?.username, app.accounts.contains(where: { $0.username == u }) {
                    Button(ProfileText.of(s.lang).logoutAndRemove, role: .destructive) {
                        app.removeAccount(username: u); app.logout(); dismiss()
                    }
                }
                Button(s.common.cancel, role: .cancel) {}
            } message: {
                Text(s.settings.logoutBody)
            }
            .confirmationDialog(
                s.profile.removeAccountTitle,
                isPresented: Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } }),
                titleVisibility: .visible
            ) {
                Button(s.profile.removeAccountConfirm, role: .destructive) {
                    if let acc = accountToRemove { app.removeAccount(username: acc.username) }
                    accountToRemove = nil
                }
                Button(s.common.cancel, role: .cancel) { accountToRemove = nil }
            } message: {
                Text(s.profile.removeAccountBody(accountToRemove?.username ?? ""))
            }
            .alert(s.profile.switchErrorTitle, isPresented: Binding(
                get: { switchError != nil },
                set: { if !$0 { switchError = nil } }
            )) {
                Button(s.common.ok, role: .cancel) { switchError = nil }
            } message: {
                if let e = switchError { Text(e) }
            }
            .alert(s.profile.renameTitle, isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField(s.profile.nickname, text: $renameText)
                    .textInputAutocapitalization(.words)
                Button(s.common.save) {
                    if let t = renameTarget { app.setNickname(renameText, for: t.username) }
                    renameTarget = nil
                }
                if renameTarget?.nickname?.isEmpty == false {
                    Button(s.profile.remove, role: .destructive) {
                        if let t = renameTarget { app.setNickname(nil, for: t.username) }
                        renameTarget = nil
                    }
                }
                Button(s.common.cancel, role: .cancel) { renameTarget = nil }
            } message: {
                Text(s.profile.renameBody(renameTarget?.username ?? ""))
            }
    }
}

// ── Settings ─────────────────────────────────────────────────────────────────

/// Android's SettingsScreen: how POKYH looks and speaks, notifications, the watch, privacy,
/// storage and about, each group's rows under thin rules.
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    @State private var confirmLogout = false
    @State private var confirmClearData = false
    @State private var language = LanguageChoice.chosen(in: .standard)
    @State private var cacheCleared = false

    /// The phone's language by default; a pick here overrides it at once, everywhere.
    private var languageSelection: Binding<Lang?> {
        Binding(
            get: { language },
            set: { choice in
                language = choice
                LanguageChoice.choose(choice, in: .standard)
                app.objectWillChange.send()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsPageHeader(s.settings.title, lead: s.account.settingsLead).fadeIn()

                SettingsGroup(s.settings.appearance) {
                    SettingsRule()
                    settingBlock(s.settings.theme, hint: s.account.themeHint) {
                        ThemeChooser(selection: $app.themeMode).padding(.top, Spacing.lg)
                    }
                    SettingsRow(s.settings.language, hint: s.settings.languageHint) {
                        LanguageMenu(selection: languageSelection)
                    }
                }
                .fadeIn(delay: 0.02)

                SettingsGroup(s.settings.notifications) {
                    NotificationsItem()
                }
                .padding(.top, groupGap)
                .fadeIn(delay: 0.03)

                WatchSettingsGroup()
                    .padding(.top, groupGap)
                    .fadeIn(delay: 0.04)

                SettingsGroup(s.settings.privacySection) {
                    if let url = URL(string: Config.privacyURL) {
                        SettingsLinkRow(s.account.policy, external: true) { openURL(url) }
                    }
                    if let url = URL(string: Config.termsURL) {
                        SettingsLinkRow(s.login.terms, external: true) { openURL(url) }
                    }
                }
                .padding(.top, groupGap)
                .fadeIn(delay: 0.05)

                SettingsGroup(s.settings.storage) {
                    SettingsRow(s.account.clearCacheTitle, hint: s.account.clearCacheHint) {
                        if cacheCleared {
                            ProfilePill(text: s.account.cleared, tone: Decorative.sage, symbol: "checkmark")
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Button(s.account.clearCacheTitle) { clearCache() }
                                .buttonStyle(.secondary(compact: true))
                        }
                    }
                    SettingsRow(s.settings.clearAll, hint: s.settings.clearAllHint, danger: true) {
                        Button(s.settings.clearAllConfirm) { confirmClearData = true }
                            .buttonStyle(.destructive)
                    }
                }
                .padding(.top, groupGap)
                .fadeIn(delay: 0.06)

                SettingsGroup(s.settings.about) {
                    SettingsRow(s.settings.version) {
                        Text(Config.appVersion)
                            .textStyle(TextStyle(15, 21, .regular, relativeTo: .subheadline, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    if let url = URL(string: "mailto:\(Config.supportEmail)") {
                        SettingsLinkRow(s.settings.contactSupport, external: true) { openURL(url) }
                    }
                    if app.session != nil {
                        LogoutRow { confirmLogout = true }
                    }
                }
                .padding(.top, groupGap)
                .fadeIn(delay: 0.08)

                Text(s.settings.footer)
                    .textStyle(.caption2)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, 80)
            .frame(maxWidth: WidthClass.readableMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(s.settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .confirmationDialog(s.settings.logoutTitle, isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(s.settings.logout, role: .destructive) { app.logout(); dismiss() }
            Button(s.common.cancel, role: .cancel) {}
        } message: {
            Text(s.settings.logoutBody)
        }
        .confirmationDialog(s.settings.clearAllTitle, isPresented: $confirmClearData, titleVisibility: .visible) {
            Button(s.settings.clearAllConfirm, role: .destructive) { app.clearAllData(); dismiss() }
            Button(s.common.cancel, role: .cancel) {}
        } message: {
            Text(s.settings.clearAllBody)
        }
    }

    /// Title and hint over a control that needs the full width.
    private func settingBlock<Control: View>(_ title: String, hint: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).textStyle(ProfileType.rowTitle).foregroundStyle(Palette.textPrimary)
            Text(hint).textStyle(ProfileType.rowHint).foregroundStyle(Palette.textSecondary)
            control()
        }
        .padding(.vertical, Spacing.xl)
    }

    /// Offline copies and pictures go, the accounts stay; the next screen loads fresh.
    private func clearCache() {
        UntisClient.shared.clearCaches()
        BackendClient.shared.clearCaches()
        ImageCache.purge()
        DiskCache.purge()
        URLCache.shared.removeAllCachedResponses()
        withAnimation(Motion.snappy) { cacheCleared = true }
    }
}

/// Title and hint on the left, the control on the right; the control goes under the text when
/// the two don't fit side by side, and then both start at the leading edge.
private struct SettingsRow<Control: View>: View {
    let title: String
    let hint: String?
    let alert: String?
    let danger: Bool
    let control: Control

    init(_ title: String, hint: String? = nil, alert: String? = nil, danger: Bool = false, @ViewBuilder control: () -> Control = { EmptyView() }) {
        self.title = title
        self.hint = hint
        self.alert = alert
        self.danger = danger
        self.control = control()
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsRule()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xxxl) {
                    text
                    Spacer(minLength: 0)
                    control
                }
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    text
                    control
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.xl)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .textStyle(ProfileType.rowTitle)
                .foregroundStyle(danger ? Palette.dangerText : Palette.textPrimary)
            if let hint {
                Text(hint).textStyle(ProfileType.rowHint).foregroundStyle(Palette.textSecondary)
            }
            if let alert {
                Text(alert).textStyle(ProfileType.rowHint.weight(.semibold)).foregroundStyle(Palette.dangerText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The phone's language or one of the app's three, as a menu on a pill: four names don't fit a
/// segmented control on a phone.
private struct LanguageMenu: View {
    @Binding var selection: Lang?
    @Environment(\.strings) private var s

    var body: some View {
        Menu {
            Picker(s.settings.language, selection: $selection) {
                Text(s.settings.languageSystem).tag(Lang?.none)
                ForEach(Lang.allCases, id: \.self) { Text($0.nativeName).tag(Lang?.some($0)) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(selection?.nativeName ?? s.settings.languageSystem)
                    .textStyle(ProfileType.rowValue)
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
    }
}

/// The colour scheme as the web picks it: three small drawings of the app, system split light
/// and dark on the diagonal, the chosen one ringed in the accent with a tick by its name.
private struct ThemeChooser: View {
    @Binding var selection: ThemeMode
    @Environment(\.strings) private var s

    private static let label = TextStyle(14.5, 20, .semibold, relativeTo: .subheadline)

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ForEach(ThemeMode.allCases) { mode in
                let active = mode == selection
                Button { if !active { selection = mode } } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        ThemePreview(mode: mode)
                            .aspectRatio(16 / 10, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .padding(4)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Brand.accent, lineWidth: 2.5)
                                    .opacity(active ? 1 : 0)
                            }
                        HStack(spacing: 6) {
                            if active {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Brand.accent)
                            }
                            Text(name(mode))
                                .textStyle(Self.label)
                                .foregroundStyle(active ? Palette.textPrimary : Palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 4)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(name(mode))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .animation(Motion.standardEase, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func name(_ mode: ThemeMode) -> String {
        switch mode {
        case .system: s.settings.system
        case .light: s.settings.light
        case .dark: s.settings.dark
        }
    }
}

/// A drawing of the app in a theme: the side bar, a title, a block, two cards. The colours are
/// the two themes' own, fixed, so each drawing looks the same whatever the app is set to.
private struct ThemePreview: View {
    let mode: ThemeMode

    private struct Colors { let bg, nav, card, tone, ink: Color }
    private static let light = Colors(bg: Color(hex: 0xF2EEE7), nav: Color(hex: 0xE9E4DB), card: Color(hex: 0xFBF9F5), tone: Color(hex: 0xDEDDFB), ink: Color(hex: 0x1C1A17))
    private static let dark = Colors(bg: Color(hex: 0x111114), nav: Color(hex: 0x1E1E23), card: Color(hex: 0x1B1B1F), tone: Color(hex: 0x24244C), ink: Color(hex: 0xF2F2F4))

    var body: some View {
        Canvas { ctx, size in
            Self.draw(ctx, size, mode == .dark ? Self.dark : Self.light)
            if mode == .system {
                var half = Path()
                half.move(to: CGPoint(x: size.width, y: 0))
                half.addLine(to: CGPoint(x: size.width, y: size.height))
                half.addLine(to: CGPoint(x: 0, y: size.height))
                half.closeSubpath()
                var dark = ctx
                dark.clip(to: half)
                Self.draw(dark, size, Self.dark)
            }
        }
        .accessibilityHidden(true)
    }

    private static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ c: Colors) {
        let w = size.width, h = size.height
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat, _ color: Color) {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius), with: .color(color))
        }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c.bg))
        // The side bar, 26% wide: the selected item in the tone, two more as faint lines.
        let navW = w * 0.26, mx = navW * 0.18
        ctx.fill(Path(CGRect(x: 0, y: 0, width: navW, height: h)), with: .color(c.nav))
        let y1 = navW * 0.22
        rect(mx, y1, navW - 2 * mx, h * 0.07, radius: h * 0.035, c.tone)
        let y2 = y1 + h * 0.07 + navW * 0.12
        rect(mx, y2, navW - 2 * mx, h * 0.05, radius: h * 0.025, c.ink.opacity(0.25))
        rect(mx, y2 + h * 0.05 + navW * 0.10, navW - 2 * mx, h * 0.05, radius: h * 0.025, c.ink.opacity(0.25))
        // The page: a title, a block in the tone, two cards.
        let pad = w * 0.08, x0 = navW + pad
        let innerW = w - navW - 2 * pad, innerH = h - 2 * pad
        let gap = innerH * 0.07, titleH = innerH * 0.09, rowH = innerH * 0.22
        rect(x0, pad, innerW * 0.55, titleH, radius: titleH / 2, c.ink.opacity(0.8))
        let blockY = pad + titleH + gap
        let blockH = innerH - titleH - rowH - 2 * gap
        rect(x0, blockY, innerW, blockH, radius: min(innerW, blockH) * 0.1, c.tone)
        let cardW = (innerW - innerW * 0.07) / 2, cardY = blockY + blockH + gap
        rect(x0, cardY, cardW, rowH, radius: min(cardW, rowH) * 0.18, c.card)
        rect(x0 + cardW + innerW * 0.07, cardY, cardW, rowH, radius: min(cardW, rowH) * 0.18, c.card)
    }
}

/// Notifications on this phone, as Android's push row: on, a sage "Eingeschaltet"; off, a way
/// to turn them on, the system's question the first time and its settings after that.
private struct NotificationsItem: View {
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus?

    private var isOn: Bool { status == .authorized || status == .provisional || status == .ephemeral }

    var body: some View {
        SettingsRow(s.account.push, hint: isOn ? s.settings.notificationsOn : status == .denied ? s.account.pushBlocked : s.account.pushOff) {
            if isOn {
                ProfilePill(text: s.account.pushOn, tone: Decorative.sage, symbol: "checkmark")
            } else if status != nil {
                Button(action: turnOn) {
                    ButtonLabel(s.account.pushEnable, symbol: "bell.badge")
                }
                .buttonStyle(.secondary(compact: true))
            }
        }
        .animation(Motion.standardEase, value: status)
        .task { await refresh() }
        // Coming back from the system settings with them switched on.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func turnOn() {
        if status == .notDetermined {
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await refresh()
            }
        } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }
}

/// Paired? POKYH on the watch? And the button that hands the signed-in account over again.
private struct WatchSettingsGroup: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var result: WatchSync.PairResult?
    @State private var sending = false

    private var pairing: WatchPairing { WatchSync.pairing }

    var body: some View {
        let t = ProfileText.of(s.lang)
        SettingsGroup(t.watchTitle) {
            SettingsRow(t.watchStatus, hint: statusHint(t)) {
                ProfilePill(text: statusLabel(t), tone: pairing.canSend ? Decorative.sage : Decorative.butter,
                            symbol: pairing.canSend ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
            }
            SettingsRow(t.connect, hint: connectHint(t), alert: alert(t)) {
                Button {
                    connect()
                } label: {
                    ButtonLabel(t.connectButton, symbol: "applewatch", busy: sending)
                }
                .buttonStyle(.secondary(compact: true))
                .disabled(sending || app.session == nil || pairing.state == .unsupported)
            }
        }
        .animation(Motion.standardEase, value: pairing.state)
        .sensoryFeedback(.success, trigger: pairing.lastSent)
    }

    private func connect() {
        sending = true
        let session = app.session
        let password = session.flatMap { Keychain.password(for: $0.username) }
        result = WatchSync.pairNow(username: session?.username,
                                   displayName: session.map { $0.personName ?? $0.username },
                                   password: password)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            sending = false
        }
    }

    private func statusLabel(_ t: ProfileText) -> String {
        switch pairing.state {
        case .checking: t.checking
        case .unsupported: t.unsupported
        case .notPaired: t.notPaired
        case .appMissing: t.appMissing
        case .ready: t.ready
        }
    }

    private func statusHint(_ t: ProfileText) -> String {
        switch pairing.state {
        case .checking: t.checkingHint
        case .unsupported: t.unsupportedHint
        case .notPaired: t.notPairedHint
        case .appMissing: t.appMissingHint
        case .ready: t.readyHint
        }
    }

    private func connectHint(_ t: ProfileText) -> String {
        guard let sent = pairing.lastSent else { return t.connectHint }
        return t.connectHint + " " + t.lastSent(TaskDates.dueLabel(sent, s))
    }

    private func alert(_ t: ProfileText) -> String? {
        switch result {
        case .noWatch: pairing.state == .appMissing ? t.appMissingHint : t.notPairedHint
        case .noAccount: t.noAccount
        default: nil
        }
    }
}

// ── Account & connection ─────────────────────────────────────────────────────

/// The POKYH account's status for everyone signed in: what it means, the account, and the
/// technical details for support, folded away.
struct ConnectionStatusView: View {
    let session: UserSession
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s
    @State private var details: String?
    @State private var loadingDetails = false
    @State private var showDetails = false

    private var tint: Color {
        switch app.backendStatus {
        case .connected: return Brand.success
        case .failed: return Brand.danger
        default: return Brand.warning
        }
    }

    private var icon: String {
        switch app.backendStatus {
        case .connected: return "checkmark.seal.fill"
        case .notStudent: return "person.fill.xmark"
        case .noClass: return "person.2.slash"
        case .failed: return "wifi.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }

    private var explanation: String {
        switch app.backendStatus {
        case .connected: return s.profile.heroOk
        case .notStudent: return s.profile.heroNotStudent
        case .noClass: return s.profile.heroNoClass
        case .failed(let m): return s.profile.heroFailed(m)
        case .unknown: return s.profile.heroUnknown
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        IconTile(icon, color: tint, size: 64)
                        Text(BackendStatusText.label(app.backendStatus, s))
                            .textStyle(SettingsHeaderStyle.title)
                            .foregroundStyle(Palette.textPrimary)
                        Text(explanation)
                            .textStyle(ProfileType.lead)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxxl)

                    SettingsGroup(s.profile.yourAccount) {
                        SettingsRow(s.profile.name) { SettingsValue(session.personName ?? session.username) }
                        if !session.klasseName.isEmpty {
                            SettingsRow(s.profile.klasse) { SettingsValue(session.klasseName) }
                        }
                        SettingsRow(s.profile.school) { SettingsValue(DefaultSchool.name) }
                        SettingsRow(s.profile.role) {
                            SettingsValue(session.isParent ? s.profile.parent : (session.isStudent ? s.profile.student : s.profile.staff))
                        }
                    }

                    SettingsGroup(s.profile.diagnosis) {
                        SettingsRow(s.profile.checkAgain) {
                            Button { Task { await reload() } } label: {
                                ButtonLabel(s.profile.checkAgain, symbol: "arrow.clockwise", busy: loadingDetails)
                            }
                            .buttonStyle(.secondary(compact: true))
                            .disabled(loadingDetails)
                        }
                        SettingsLinkRow(s.profile.technicalDetails, hint: s.profile.forSupport) {
                            withAnimation(Motion.standardEase) { showDetails.toggle() }
                        }
                        if showDetails {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text(details ?? s.common.loading)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Palette.textSecondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Spacing.lg)
                                    .nestedSurface(radius: Radius.md)
                                if let details {
                                    ShareLink(item: details) { ButtonLabel(s.profile.share, symbol: "square.and.arrow.up") }
                                        .buttonStyle(.secondary(compact: true))
                                }
                            }
                            .padding(.bottom, Spacing.lg)
                            .transition(.opacity)
                        }
                        SettingsRule()
                        Label(s.profile.detailsNote, systemImage: "lock.shield")
                            .textStyle(.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.top, Spacing.lg)
                    }
                    .padding(.top, groupGap)
                }
                .padding(.horizontal, Spacing.screenH)
                .padding(.bottom, Spacing.xxxl)
            }
            .appBackground()
            .navigationTitle(s.profile.connectionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task { if details == nil { await reload() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func reload() async {
        loadingDetails = true
        details = await UntisClient.shared.classDiagnostics(session)
        loadingDetails = false
    }
}

// ── Pieces ───────────────────────────────────────────────────────────────────

private enum SettingsHeaderStyle {
    static let title = TextStyle(28, 32, .heavy, tracking: -0.02, relativeTo: .largeTitle)
}

/// The backend status in the language in use.
enum BackendStatusText {
    static func label(_ status: BackendStatus, _ s: Strings) -> String {
        switch status {
        case .unknown: s.profile.statusUnknown
        case .connected: s.profile.statusOk
        case .notStudent: s.profile.statusNotStudent
        case .noClass: s.profile.statusNoClass
        case .failed(let m): s.profile.statusFailed(m)
        }
    }
}

/// A row that goes somewhere: title, hint, an optional trailing view, then the chevron (or the
/// arrow out of the app).
private struct SettingsLinkRow<Trailing: View>: View {
    let title: String
    let hint: String?
    let external: Bool
    let action: () -> Void
    let trailing: Trailing

    init(_ title: String, hint: String? = nil, external: Bool = false, action: @escaping () -> Void,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.hint = hint
        self.external = external
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsRule()
            Button(action: action) {
                HStack(spacing: Spacing.xxl) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title).textStyle(ProfileType.rowTitle).foregroundStyle(Palette.textPrimary)
                        if let hint {
                            Text(hint).textStyle(ProfileType.rowHint).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    trailing
                    Image(systemName: external ? "arrow.up.right" : "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.rowPress(radius: 14))
            .padding(.vertical, 6)
            .padding(.horizontal, -Spacing.md)
        }
    }
}

/// "Abmelden" in the danger colours, the confirmation comes as a dialog.
private struct LogoutRow: View {
    let action: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        SettingsRow(s.settings.logout, hint: s.account.logoutHint, danger: true) {
            Button(action: action) {
                ButtonLabel(s.settings.logout, symbol: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.destructive)
        }
    }
}

private struct ProfilePill: View {
    let text: String
    let tone: Tone
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            }
            Text(text).textStyle(ProfileType.pill).lineLimit(1)
        }
        .foregroundStyle(tone.ink)
        .padding(.horizontal, Spacing.md)
        .frame(height: 28)
        .background(tone.fill, in: .capsule)
        .fixedSize()
    }
}

/// Copies a value; the icon turns into a green tick for a moment.
private struct CopyValueButton: View {
    let value: String
    let label: String
    @Environment(\.strings) private var s
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(copied ? Brand.success : Palette.textTertiary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .contentShape(.circle)
        }
        .buttonStyle(.rowPress(radius: 16))
        .accessibilityLabel(copied ? s.profile.copied : "\(label) \(s.profile.copy)")
        .sensoryFeedback(.success, trigger: copied) { _, now in now }
    }
}

/// Texts only the iOS app has (the watch, a combined sign-out), in the app's three languages.
struct ProfileText {
    let watchTitle: String
    let watchStatus: String
    let checking: String
    let checkingHint: String
    let unsupported: String
    let unsupportedHint: String
    let notPaired: String
    let notPairedHint: String
    let appMissing: String
    let appMissingHint: String
    let ready: String
    let readyHint: String
    let connect: String
    let connectHint: String
    let connectButton: String
    let lastSent: (String) -> String
    let noAccount: String
    let logoutAndRemove: String

    static func of(_ lang: Lang) -> ProfileText {
        switch lang {
        case .de: de
        case .it: it
        case .en: en
        }
    }

    static let de = ProfileText(
        watchTitle: "Apple Watch",
        watchStatus: "Status",
        checking: "Wird geprüft",
        checkingHint: "POKYH fragt gerade bei der Apple Watch nach.",
        unsupported: "Nicht verfügbar",
        unsupportedHint: "Auf diesem Gerät gibt es keine Apple Watch.",
        notPaired: "Nicht gekoppelt",
        notPairedHint: "Mit diesem iPhone ist keine Apple Watch gekoppelt.",
        appMissing: "App fehlt",
        appMissingHint: "Die Apple Watch ist gekoppelt, aber POKYH ist darauf nicht installiert. Installiere es in der Watch-App.",
        ready: "Bereit",
        readyHint: "Gekoppelt, POKYH ist auf der Uhr installiert.",
        connect: "Mit Apple Watch verbinden",
        connectHint: "Überträgt dein angemeldetes Konto auf die Uhr. Sie bleibt danach angemeldet.",
        connectButton: "Verbinden",
        lastSent: { "Zuletzt gesendet: \($0)." },
        noAccount: "Melde dich zuerst auf dem iPhone an.",
        logoutAndRemove: "Abmelden & Konto vom Gerät löschen"
    )

    static let it = ProfileText(
        watchTitle: "Apple Watch",
        watchStatus: "Stato",
        checking: "Verifica in corso",
        checkingHint: "POKYH sta contattando l’Apple Watch.",
        unsupported: "Non disponibile",
        unsupportedHint: "Su questo dispositivo non c’è un Apple Watch.",
        notPaired: "Non abbinato",
        notPairedHint: "Nessun Apple Watch è abbinato a questo iPhone.",
        appMissing: "App mancante",
        appMissingHint: "L’Apple Watch è abbinato, ma POKYH non è installato. Installalo dall’app Watch.",
        ready: "Pronto",
        readyHint: "Abbinato, POKYH è installato sull’orologio.",
        connect: "Collega ad Apple Watch",
        connectHint: "Trasferisce il tuo account sull’orologio, che poi resta connesso.",
        connectButton: "Collega",
        lastSent: { "Ultimo invio: \($0)." },
        noAccount: "Prima accedi sull’iPhone.",
        logoutAndRemove: "Esci e rimuovi l’account dal dispositivo"
    )

    static let en = ProfileText(
        watchTitle: "Apple Watch",
        watchStatus: "Status",
        checking: "Checking",
        checkingHint: "POKYH is asking the Apple Watch right now.",
        unsupported: "Not available",
        unsupportedHint: "There's no Apple Watch on this device.",
        notPaired: "Not paired",
        notPairedHint: "No Apple Watch is paired with this iPhone.",
        appMissing: "App missing",
        appMissingHint: "The Apple Watch is paired, but POKYH isn't installed on it. Install it from the Watch app.",
        ready: "Ready",
        readyHint: "Paired, POKYH is installed on the watch.",
        connect: "Connect to Apple Watch",
        connectHint: "Sends your signed-in account to the watch. It stays signed in after that.",
        connectButton: "Connect",
        lastSent: { "Last sent: \($0)." },
        noAccount: "Sign in on the iPhone first.",
        logoutAndRemove: "Sign out & remove account from device"
    )
}
