import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import PokyhCore
import PokyhDesign

/// "Geräte & Anmeldungen", as on the web's settings/devices: where the account is signed in, and when.
struct DevicesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var devices: [BackendClient.DeviceSession]?
    @State private var logins: [BackendClient.LoginEntry]?
    @State private var keptDays = 0
    @State private var failed = false
    @State private var historyFailed = false
    /// The device being signed out, or `allOthers`.
    @State private var busy: String?
    @State private var actionFailed = false
    @State private var othersDone = false
    @State private var confirmOthers = false
    @State private var shown = 10

    private static let allOthers = "others"
    private var current: [BackendClient.DeviceSession] { devices?.filter(\.current) ?? [] }
    private var others: [BackendClient.DeviceSession] { devices?.filter { !$0.current } ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Text(s.settings.devicesLead)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textSecondary)
                if failed {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(s.settings.devicesLoadError).textStyle(.callout).foregroundStyle(Palette.textSecondary)
                        Button { Task { await load() } } label: {
                            ButtonLabel(s.common.retry, symbol: "arrow.clockwise")
                        }
                        .buttonStyle(.secondary(compact: true))
                    }
                } else {
                    if actionFailed {
                        Text(s.settings.devicesFailed).textStyle(.footnote).foregroundStyle(Palette.dangerText)
                    }
                    thisDevice.fadeIn()
                    otherDevices.fadeIn(delay: 0.03)
                    history.fadeIn(delay: 0.06)
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: WidthClass.readableMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(s.settings.devicesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(s.settings.signOutOthersConfirm, isPresented: $confirmOthers, titleVisibility: .visible) {
            Button(s.settings.signOutOthers, role: .destructive) { Task { await signOutOthers() } }
            Button(s.common.cancel, role: .cancel) {}
        }
    }

    @ViewBuilder private var thisDevice: some View {
        PokyhSection(s.settings.thisDevice) {
            if devices == nil {
                ListSkeleton(rows: 1)
            } else {
                ListCard(current) { DeviceRow(device: $0) }
            }
        }
    }

    @ViewBuilder private var otherDevices: some View {
        PokyhSection(s.settings.otherDevices) {
            if others.count > 1 {
                Button(s.settings.signOutOthers) { confirmOthers = true }
                    .buttonStyle(.plain)
                    .textStyle(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.dangerText)
                    .disabled(busy == Self.allOthers)
            }
        } content: {
            if devices == nil {
                ListSkeleton(rows: 2)
            } else if others.isEmpty {
                Text(othersDone ? s.settings.signedOutOthers : s.settings.noOthers)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            } else {
                ListCard(others) { device in
                    DeviceRow(device: device, busy: busy == device.id) {
                        Task { await signOut(device) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var history: some View {
        PokyhSection(s.settings.history) {
            if historyFailed {
                Text(s.settings.devicesLoadError).textStyle(.footnote).foregroundStyle(Palette.textTertiary)
            } else if let logins {
                if logins.isEmpty {
                    Text(s.settings.historyEmpty).textStyle(.footnote).foregroundStyle(Palette.textTertiary)
                } else {
                    if keptDays > 0 {
                        Text(s.settings.historyHint(keptDays)).textStyle(.footnote).foregroundStyle(Palette.textTertiary)
                    }
                    ListCard(Array(logins.prefix(shown))) { LoginRow(entry: $0) }
                    if logins.count > shown {
                        Button(s.settings.showMore) { shown += 20 }
                            .buttonStyle(.plain)
                            .textStyle(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.accentText)
                    }
                }
            } else {
                ListSkeleton(rows: 3)
            }
        }
    }

    private func load() async {
        failed = false
        historyFailed = false
        guard let token = app.session?.apiToken else {
            failed = true
            return
        }
        do {
            devices = try await BackendClient.shared.deviceSessions(token: token)
        } catch {
            failed = devices == nil
            return
        }
        // A token renewed on the way here would be the older one otherwise.
        let fresh = app.session?.apiToken ?? token
        do {
            let answer = try await BackendClient.shared.loginHistory(token: fresh)
            logins = answer.logins
            keptDays = answer.keptDays
        } catch {
            historyFailed = logins == nil
        }
    }

    private func signOut(_ device: BackendClient.DeviceSession) async {
        guard let token = app.session?.apiToken else { return }
        busy = device.id
        actionFailed = false
        defer { busy = nil }
        do {
            try await BackendClient.shared.signOutDevice(id: device.id, token: token)
            devices?.removeAll { $0.id == device.id }
        } catch {
            actionFailed = true
        }
    }

    private func signOutOthers() async {
        guard let token = app.session?.apiToken else { return }
        busy = Self.allOthers
        actionFailed = false
        defer { busy = nil }
        do {
            try await BackendClient.shared.signOutOtherDevices(token: token)
            othersDone = true
            devices?.removeAll { !$0.current }
        } catch {
            actionFailed = true
        }
    }
}

/// Phone or computer, in the page's one quiet tone.
private struct DeviceGlyph: View {
    let client: String
    let platform: String

    private var symbol: String {
        if platform == "ios" { return "iphone" }
        return client == "app" || platform == "android" ? "smartphone" : "laptopcomputer"
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Decorative.periwinkle.ink)
            .frame(width: 40, height: 40)
            .background(Decorative.periwinkle.fill, in: .rect(cornerRadius: Radius.md, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct DeviceRow: View {
    let device: BackendClient.DeviceSession
    var busy = false
    var onSignOut: (() -> Void)?
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.iconText) {
            DeviceGlyph(client: device.client, platform: device.platform)
            VStack(alignment: .leading, spacing: 2) {
                Text(DeviceLabels.name(model: device.model, os: device.os, browser: device.browser, unknown: s.settings.unknownDevice))
                    .textStyle(.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(DeviceLabels.place(city: device.city, region: device.region, country: device.country, unknown: s.settings.unknownPlace))
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Text(s.settings.lastActive(DeviceLabels.when(device.lastUsedAt, lang: s.lang)))
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onSignOut {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(s.settings.signOutShort, action: onSignOut)
                        .buttonStyle(.plain)
                        .textStyle(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.dangerText)
                }
            }
        }
        .padding(Spacing.card)
    }
}

private struct LoginRow: View {
    let entry: BackendClient.LoginEntry
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.iconText) {
            DeviceGlyph(client: entry.client, platform: entry.platform)
            VStack(alignment: .leading, spacing: 2) {
                Text(DeviceLabels.name(model: entry.model, os: entry.os, browser: entry.browser, unknown: s.settings.unknownDevice))
                    .textStyle(.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(DeviceLabels.place(city: entry.city, region: entry.region, country: entry.country, unknown: s.settings.unknownPlace))
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Text(DeviceLabels.when(entry.at, lang: s.lang))
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.card)
    }
}

// ── Privacy ──────────────────────────────────────────────────────────────────

/// The data export as a file to hand to the share sheet. Stays in memory, so no copy of it is
/// left on the device unless someone saves one.
private struct DataExportFile: Transferable, Equatable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.name }
    }
}

/// As on the web's settings: the consent to the personal usage statistics, when the privacy
/// notice was confirmed, and everything POKYH keeps about the account as a file.
struct PrivacySettingsRows: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var status: BackendClient.PrivacyStatus?
    @State private var saving = false
    @State private var saveFailed = false
    @State private var exporting = false
    @State private var exportFile: DataExportFile?
    @State private var exportError: String?

    private var usage: Binding<Bool> {
        Binding(get: { status?.usageStats ?? false }, set: { on in Task { await setUsage(on) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(s.settings.usage, hint: s.settings.usageHint, alert: saveFailed ? s.settings.saveError : nil) {
                Toggle(s.settings.usage, isOn: usage)
                    .labelsHidden()
                    .tint(Palette.accent)
                    .disabled(status == nil || saving)
            }
            SettingsRow(s.settings.acknowledged, hint: status?.acknowledgedAt.map { DeviceLabels.when($0, lang: s.lang) } ?? s.settings.never)
            SettingsRow(s.settings.exportTitle, hint: s.settings.exportHint, alert: exportError) {
                exportControl
            }
        }
        .task { await loadStatus() }
    }

    @ViewBuilder private var exportControl: some View {
        if let exportFile {
            ShareLink(item: exportFile, preview: SharePreview(exportFile.name)) {
                ButtonLabel(s.account.exportButton, symbol: "square.and.arrow.up")
            }
            .buttonStyle(.secondary(compact: true))
        } else {
            Button { Task { await export() } } label: {
                if exporting {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(s.settings.exporting)
                    }
                } else {
                    Text(s.account.exportButton)
                }
            }
            .buttonStyle(.secondary(compact: true))
            .disabled(exporting)
        }
    }

    private func loadStatus() async {
        guard let token = app.session?.apiToken else { return }
        status = await BackendClient.shared.privacyStatus(token: token)
    }

    private func setUsage(_ on: Bool) async {
        guard let token = app.session?.apiToken else { return }
        saving = true
        saveFailed = false
        defer { saving = false }
        do {
            try await BackendClient.shared.setUsageStats(on, token: token)
            status?.usageStats = on
        } catch {
            saveFailed = true
        }
    }

    private func export() async {
        guard let token = app.session?.apiToken else { return }
        exporting = true
        exportError = nil
        defer { exporting = false }
        do {
            let data = try await BackendClient.shared.exportData(token: token)
            exportFile = DataExportFile(data: data, name: "pokyh-daten-\(SchoolDates.todayISO()).json")
        } catch let error as AppError {
            // The backend limits this to a few times an hour and says so.
            exportError = error.message
        } catch {
            exportError = s.common.noConnection
        }
    }
}

// ── Deleting the account ─────────────────────────────────────────────────────

/// App Store guideline 5.1.1(v). iOS first, so the texts live here until Android has them too.
struct AccountDeletionText {
    let title, hint, confirmTitle, confirmBody, confirm, notAvailable, openWebsite: String

    static func of(_ lang: Lang) -> AccountDeletionText {
        switch lang {
        case .de: AccountDeletionText(
            title: "Konto löschen",
            hint: "Löscht dein POKYH-Konto und alles, was POKYH über dich speichert. Dein WebUntis-Konto bleibt.",
            confirmTitle: "POKYH-Konto endgültig löschen?",
            confirmBody: "Deine To-dos, Kommentare, Bewertungen und deine Aktivität werden gelöscht und alle Geräte abgemeldet. Erinnerungen, die du für deine Klasse angelegt hast, bleiben ohne deinen Namen. Das lässt sich nicht rückgängig machen.\n\nDein WebUntis-Konto bleibt bestehen. Meldest du dich später wieder an, beginnt ein neues, leeres POKYH-Konto.",
            confirm: "Endgültig löschen",
            notAvailable: "Der POKYH-Server kann Konten noch nicht direkt löschen. Über die Website erreichst du uns, dann löschen wir dein Konto für dich.",
            openWebsite: "Website öffnen")
        case .it: AccountDeletionText(
            title: "Elimina account",
            hint: "Elimina il tuo account POKYH e tutto ciò che POKYH salva su di te. Il tuo account WebUntis resta.",
            confirmTitle: "Eliminare definitivamente l’account POKYH?",
            confirmBody: "Le tue attività, i commenti, le valutazioni e i dati di utilizzo vengono eliminati e tutti i dispositivi disconnessi. I promemoria che hai creato per la tua classe restano senza il tuo nome. L’operazione non si può annullare.\n\nIl tuo account WebUntis resta. Se accedi di nuovo in futuro, inizierà un nuovo account POKYH vuoto.",
            confirm: "Elimina definitivamente",
            notAvailable: "Il server POKYH non può ancora eliminare direttamente gli account. Contattaci tramite il sito e lo elimineremo per te.",
            openWebsite: "Apri il sito")
        case .en: AccountDeletionText(
            title: "Delete account",
            hint: "Deletes your POKYH account and everything POKYH keeps about you. Your WebUntis account stays.",
            confirmTitle: "Delete your POKYH account for good?",
            confirmBody: "Your to-dos, comments, ratings and activity are deleted and every device is signed out. Reminders you created for your class stay, without your name. This can’t be undone.\n\nYour WebUntis account stays. If you sign in again later, a new, empty POKYH account begins.",
            confirm: "Delete for good",
            notAvailable: "The POKYH server can’t delete accounts directly yet. Reach us through the website and we’ll delete yours for you.",
            openWebsite: "Open website")
        }
    }
}

struct DeleteAccountRow: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirming = false
    @State private var working = false
    @State private var problem: String?
    @State private var notAvailable = false

    private var t: AccountDeletionText { .of(s.lang) }

    var body: some View {
        SettingsRow(t.title, hint: t.hint, danger: true) {
            Button { confirming = true } label: {
                if working {
                    ProgressView().controlSize(.small)
                } else {
                    ButtonLabel(t.title, symbol: "trash")
                }
            }
            .buttonStyle(.destructive)
            .disabled(working)
        }
        .alert(t.confirmTitle, isPresented: $confirming) {
            Button(t.confirm, role: .destructive) { Task { await delete() } }
            Button(s.common.cancel, role: .cancel) {}
        } message: {
            Text(t.confirmBody)
        }
        .alert(t.title, isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button(s.common.ok, role: .cancel) {}
        } message: {
            if let problem { Text(problem) }
        }
        .alert(t.title, isPresented: $notAvailable) {
            Button(t.openWebsite) { openURL(AppConfig.current.websiteURL) }
            Button(s.common.ok, role: .cancel) {}
        } message: {
            Text(t.notAvailable)
        }
    }

    private func delete() async {
        working = true
        defer { working = false }
        switch await app.deleteAccount() {
        case .deleted: dismiss()
        case .notAvailable: notAvailable = true
        case .failed(let message): problem = message
        }
    }
}

#Preview("Row texts") {
    let t = AccountDeletionText.of(.de)
    ScrollView {
        VStack(alignment: .leading) {
            SettingsRow(t.title, hint: t.hint, danger: true)
            Text(t.confirmBody)
        }
        .padding()
    }
}
