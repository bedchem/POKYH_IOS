import SwiftUI

/// Die Datenschutzerklärung in der App — wie das PrivacyGate der Website:
///
/// - Nach der **ersten Anmeldung** eines Kontos (Benutzername + Passwort eingegeben)
///   einmal zum Bestätigen.
/// - Ändert sich die Erklärung, bekommen **bereits angemeldete** Konten sie einmal als
///   „aktualisiert" — ohne neue Anmeldung, ein Tippen auf „Verstanden" genügt.
///
/// Der Hinweis selbst bleibt kurz; was drinsteht, zeigt der Link „Mehr Informationen" auf
/// der Website. Die aktuelle Version kommt von dort (`/api/privacy-notice`), die
/// Bestätigung geht wie auf der Website ans Backend (`POST /privacy/acknowledge`). Sie ist
/// keine Einwilligung, nur der Nachweis, dass der Hinweis angezeigt wurde. Ohne Netz wird
/// nichts blockiert; der Hinweis kommt beim nächsten Mal.
struct PrivacyNoticePrompt: Identifiable, Equatable {
    enum Kind { case first, updated }
    let kind: Kind
    let version: String
    let username: String
    var id: String { "\(username)|\(version)" }
}

extension AppState {
    /// Nach einer Anmeldung: Kennt das Backend für dieses Konto die aktuelle Fassung noch
    /// nicht, wird sie gezeigt. `fresh` = Zugangsdaten gerade eingegeben (erste Anmeldung).
    func checkPrivacyNotice(fresh: Bool) async {
        guard !isOffline, let s = session, let token = s.apiToken else { return }
        guard let notice = await BackendClient.shared.currentPrivacyNotice(),
              let status = await BackendClient.shared.privacyStatus(token: token),
              status.acknowledgedVersion != notice.version,
              session?.username == s.username else { return }
        privacyNotice = PrivacyNoticePrompt(kind: fresh ? .first : .updated, version: notice.version, username: s.username)
    }

    /// „Verstanden": beim Backend festhalten, dann schließen.
    func acknowledgePrivacyNotice() async -> Bool {
        guard let notice = privacyNotice, let token = session?.apiToken else { return false }
        guard await BackendClient.shared.acknowledgePrivacy(version: notice.version, token: token) else { return false }
        if privacyNotice == notice { privacyNotice = nil }
        return true
    }
}

/// Ein Banner oben, wie der Offline-Hinweis: blockiert nichts und bleibt, bis „Verstanden"
/// getippt ist. Ein Hinweis, keine Einwilligung — daher nichts zum Ablehnen.
struct PrivacyNoticeBanner: View {
    @EnvironmentObject var app: AppState
    let notice: PrivacyNoticePrompt
    @State private var saving = false
    @State private var failed = false

    private var title: String {
        notice.kind == .first ? "Datenschutzerklärung" : "Datenschutzerklärung aktualisiert"
    }

    private var message: String {
        switch notice.kind {
        case .first: return "Wie POKYH mit deinen Daten umgeht, steht in der Datenschutzerklärung."
        case .updated: return "Wir haben unsere Datenschutzerklärung aktualisiert."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.subheadline)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 32, height: 32)
                    .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: Config.privacyURL) {
                        Link("Datenschutzerklärung lesen", destination: url)
                            .font(.footnote.weight(.semibold))
                    }
                    if failed {
                        Text("Das hat nicht geklappt. Bitte versuche es noch einmal.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 0)
            }
            Button {
                Task {
                    saving = true
                    failed = !(await app.acknowledgePrivacyNotice())
                    saving = false
                }
            } label: {
                Text(saving ? "Wird gespeichert…" : "Verstanden")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(height: 40)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .disabled(saving)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
