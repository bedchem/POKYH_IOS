import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    @State private var accountToRemove: SavedAccount?
    @State private var renameTarget: SavedAccount?
    @State private var renameText = ""
    @State private var showConnectionStatus = false
    @State private var confirmClearData = false

    var body: some View {
        List {
            if let s = app.session {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(url: s.imageUrl, name: s.personName ?? s.username, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.personName ?? s.username).font(.headline)
                            Text(s.isParent ? "Erziehungsberechtigt" : "Schüler/in")
                                .font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Palette.card)

                Section("Konto") {
                    row("Benutzername", s.username)
                    if !s.klasseName.isEmpty { row("Klasse", s.klasseName) }
                    row("Schule", "LBS Brixen")
                    // Tippbare Status-Zeile → öffnet die (für alle zugängliche) Diagnose.
                    Button { showConnectionStatus = true } label: {
                        HStack {
                            Text("POKYH-Konto").foregroundStyle(Palette.textSecondary)
                            Spacer()
                            backendStatusBadge
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Palette.card)
            }

            Section("Darstellung") {
                Picker(selection: $app.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                } label: {
                    Label("Erscheinungsbild", systemImage: "paintbrush.fill")
                }
                .pickerStyle(.menu)
            }
            .listRowBackground(Palette.card)

            Section("Konten") {
                ForEach(app.accounts) { acc in
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await app.switchAccount(username: acc.username)
                                // Nur schließen, wenn KEIN Passwort-Sheet geöffnet wurde —
                                // sonst würde das Schließen von Profil dessen Sheet mitreißen.
                                if !app.showAddAccount { dismiss() }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                InitialAvatar(name: acc.title, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Text(acc.title).foregroundStyle(Palette.textPrimary)
                                        if acc.username == app.defaultUsername { badge("Standard", Palette.accent) }
                                        if !app.accountHasPassword(acc.username) { badge("Passwort nötig", Palette.orange) }
                                    }
                                    // Bei vergebenem Spitznamen zusätzlich den echten Benutzernamen zeigen.
                                    Text(acc.nickname?.isEmpty == false ? "\(acc.username) · \(acc.displayName)" : acc.displayName)
                                        .font(.caption2).foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                                if acc.username == app.session?.username {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // 3-Punkte-Menü: Standard · Aktualisieren · Umbenennen · Abmelden · Entfernen
                        Menu {
                            if acc.username == app.defaultUsername {
                                Button { app.defaultUsername = nil } label: {
                                    Label("Als Standard entfernen", systemImage: "star.slash")
                                }
                            } else {
                                Button { app.defaultUsername = acc.username } label: {
                                    Label("Als Standard festlegen", systemImage: "star")
                                }
                            }
                            Button {
                                Task { await app.refreshAccount(username: acc.username) }
                            } label: {
                                Label("Konto aktualisieren", systemImage: "arrow.clockwise")
                            }
                            Button {
                                renameText = acc.nickname ?? ""
                                renameTarget = acc
                            } label: {
                                Label("Umbenennen", systemImage: "pencil")
                            }
                            if app.accountHasPassword(acc.username) {
                                Button { app.signOutAccount(username: acc.username) } label: {
                                    Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                            Button(role: .destructive) { accountToRemove = acc } label: {
                                Label("Account entfernen", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Palette.textSecondary)
                                .padding(.leading, 4).contentShape(Rectangle())
                        }
                    }
                }
                if app.accounts.count > 1 {
                    Picker(selection: Binding(
                        get: { app.defaultUsername ?? "" },
                        set: { app.defaultUsername = $0 }
                    )) {
                        ForEach(app.accounts) { acc in Text(acc.username).tag(acc.username) }
                    } label: {
                        Label("Standard-Konto", systemImage: "star")
                    }
                }
                Button {
                    app.showAddAccount = true
                } label: {
                    Label("Konto hinzufügen", systemImage: "person.badge.plus")
                }
            }
            .listRowBackground(Palette.card)

            Section {
                Button(role: .destructive) {
                    confirmLogout = true
                } label: {
                    Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .listRowBackground(Palette.card)

            Section {
                Button(role: .destructive) {
                    confirmClearData = true
                } label: {
                    Label("Cache & Daten löschen", systemImage: "trash")
                }
            } footer: {
                Text("Löscht alle gespeicherten Konten, den Offline-Stundenplan, Noten-Cache und alle App-Daten von diesem Gerät.")
            }
            .listRowBackground(Palette.card)

            Section {
                Text("POKYH · Nicht offiziell mit der LBS Brixen oder WebUntis verbunden.")
                    .font(.caption2).foregroundStyle(Palette.textTertiary)
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
        }
        // Bestätigungen (user-freundlich) ─────────────────────────────────────
        .confirmationDialog("Wirklich abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { app.logout(); dismiss() }
            if let u = app.session?.username, app.accounts.contains(where: { $0.username == u }) {
                Button("Abmelden & Konto vom Gerät löschen", role: .destructive) {
                    app.removeAccount(username: u); app.logout(); dismiss()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Du kannst dich abmelden oder das gespeicherte Konto ganz vom Gerät entfernen.")
        }
        .confirmationDialog(
            "Konto entfernen?",
            isPresented: Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Konto entfernen", role: .destructive) {
                if let acc = accountToRemove { app.removeAccount(username: acc.username) }
                accountToRemove = nil
            }
            Button("Abbrechen", role: .cancel) { accountToRemove = nil }
        } message: {
            Text("Die gespeicherten Anmeldedaten von \(accountToRemove?.username ?? "") werden vom Gerät gelöscht.")
        }
        .confirmationDialog("Cache & alle Daten löschen?", isPresented: $confirmClearData, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) { app.clearAllData(); dismiss() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle gespeicherten Konten, Anmeldedaten, der Offline-Stundenplan, der Noten-Cache und sämtliche App-Einstellungen werden entfernt. Du musst dich danach neu anmelden.")
        }
        .alert("Konto umbenennen", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Spitzname", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Speichern") {
                if let t = renameTarget { app.setNickname(renameText, for: t.username) }
                renameTarget = nil
            }
            if renameTarget?.nickname?.isEmpty == false {
                Button("Spitzname entfernen", role: .destructive) {
                    if let t = renameTarget { app.setNickname(nil, for: t.username) }
                    renameTarget = nil
                }
            }
            Button("Abbrechen", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Vergib einen eigenen Namen für \(renameTarget?.username ?? "") (nur lokal sichtbar).")
        }
        .sheet(isPresented: $app.showAddAccount) {
            NavigationStack { LoginView(isAdditional: true) }
        }
        .sheet(isPresented: $showConnectionStatus) {
            if let s = app.session { ConnectionStatusView(session: s) }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(value)
        }
    }

    /// Kompakter Status-Indikator (Icon + Kurztext) für die tappbare Zeile.
    @ViewBuilder private var backendStatusBadge: some View {
        let connected = app.backendStatus == .connected
        HStack(spacing: 6) {
            Image(systemName: connected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(connected ? Palette.success : Palette.orange)
            Text(app.backendStatus.label)
                .foregroundStyle(connected ? Palette.textPrimary : Palette.textSecondary)
        }
        .font(.subheadline)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.2), in: Capsule()).foregroundStyle(color)
    }
}

/// Benutzerfreundlicher Konto-/Verbindungsstatus für JEDEN eingeloggten User:
/// verständliche Statuskarte + Infos, technische Details optional eingeklappt.
struct ConnectionStatusView: View {
    let session: UserSession
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var details: String?
    @State private var loadingDetails = false

    private var connected: Bool { app.backendStatus == .connected }
    private var tint: Color {
        switch app.backendStatus {
        case .connected: return Palette.success
        case .failed:    return Palette.danger
        default:         return Palette.orange
        }
    }
    private var icon: String {
        switch app.backendStatus {
        case .connected:  return "checkmark.seal.fill"
        case .notStudent: return "person.fill.xmark"
        case .noClass:    return "person.2.slash"
        case .failed:     return "wifi.exclamationmark"
        case .unknown:    return "questionmark.circle"
        }
    }
    private var explanation: String {
        switch app.backendStatus {
        case .connected:
            return "Dein POKYH-Konto ist aktiv. Todos, Erinnerungen und Klasse stehen zur Verfügung."
        case .notStudent:
            return "POKYH-Funktionen sind nur mit einem Schülerkonto verfügbar."
        case .noClass:
            return "Deine WebUntis-Klasse konnte nicht ermittelt werden — dadurch sind Todos & Erinnerungen gesperrt. Tippe auf Erneut prüfen; hilft das nicht, sende die technischen Details an den Support."
        case .failed(let m):
            return "Verbindung zum POKYH-Server fehlgeschlagen: \(m)"
        case .unknown:
            return "Status noch nicht ermittelt."
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(tint.opacity(0.15)).frame(width: 76, height: 76)
                            Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(tint)
                        }
                        Text(app.backendStatus.label).font(.title3.bold()).foregroundStyle(Palette.textPrimary)
                        Text(explanation).font(.subheadline).foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .listRowBackground(Palette.card)

                Section("Dein Konto") {
                    infoRow("Name", session.personName ?? session.username)
                    if !session.klasseName.isEmpty { infoRow("Klasse", session.klasseName) }
                    infoRow("Schule", "LBS Brixen")
                    infoRow("Rolle", session.isParent ? "Erziehungsberechtigt" : (session.isStudent ? "Schüler/in" : "Lehrkraft/Verwaltung"))
                }
                .listRowBackground(Palette.card)

                Section {
                    Button { Task { await reload() } } label: {
                        HStack(spacing: 8) {
                            if loadingDetails { ProgressView().controlSize(.small) }
                            Label("Erneut prüfen", systemImage: "arrow.clockwise")
                        }
                    }.disabled(loadingDetails)

                    DisclosureGroup("Technische Details (für Support)") {
                        Text(details ?? "Wird geladen…")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let details {
                            ShareLink(item: details) { Label("Teilen", systemImage: "square.and.arrow.up") }
                                .font(.caption)
                        }
                    }
                    Label("Enthält nur deine WebUntis-Daten – keine Passwörter.", systemImage: "lock.shield")
                        .font(.caption2).foregroundStyle(Palette.textTertiary)
                }
                .listRowBackground(Palette.card)
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Konto & Verbindung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
            .task { if details == nil { await reload() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(Palette.textSecondary); Spacer(); Text(value) }
    }

    private func reload() async {
        loadingDetails = true
        details = await UntisClient.shared.classDiagnostics(session)
        loadingDetails = false
    }
}
