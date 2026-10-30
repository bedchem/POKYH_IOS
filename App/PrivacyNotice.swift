import SwiftUI
import PokyhCore
import PokyhDesign

// The privacy notice, like the website's PrivacyGate: once after an account's first sign-in,
// and once as "aktualisiert" when it changed, without signing in again. The current version
// comes from the website, the acknowledgement goes to the backend. It isn't consent, only proof
// the notice was shown, and without a network nothing is blocked.
struct PrivacyNoticePrompt: Identifiable, Equatable {
    enum Kind { case first, updated }
    let kind: Kind
    let version: String
    let username: String
    var id: String { "\(username)|\(version)" }
}

extension AppState {
    /// Shows the notice if the backend hasn't seen this version acknowledged for the account.
    /// `fresh`: the password was just typed in, so this is the first sign-in.
    func checkPrivacyNotice(fresh: Bool) async {
        guard !isOffline, let s = session, let token = s.apiToken else { return }
        guard let notice = await BackendClient.shared.currentPrivacyNotice(),
              let status = await BackendClient.shared.privacyStatus(token: token),
              status.acknowledgedVersion != notice.version,
              session?.username == s.username else { return }
        privacyNotice = PrivacyNoticePrompt(kind: fresh ? .first : .updated, version: notice.version, username: s.username)
    }

    /// "Verstanden": record it with the backend, then close.
    func acknowledgePrivacyNotice() async -> Bool {
        guard let notice = privacyNotice, let token = session?.apiToken else { return false }
        guard await BackendClient.shared.acknowledgePrivacy(version: notice.version, token: token) else { return false }
        if privacyNotice == notice { privacyNotice = nil }
        return true
    }
}

/// A banner at the top, where the offline notice sits. Blocks nothing and stays until
/// "Verstanden". It informs, it doesn't ask, so there's nothing to decline.
struct PrivacyNoticeBanner: View {
    @EnvironmentObject var app: AppState
    let notice: PrivacyNoticePrompt
    @Environment(\.strings) private var s
    @State private var saving = false
    @State private var failed = false

    private var title: String {
        notice.kind == .first ? s.system.privacy : s.system.privacyUpdated
    }

    // Kept short; what the notice says is behind the link.
    private var message: String {
        switch notice.kind {
        case .first: return s.system.privacyFirst
        case .updated: return s.system.privacyChanged
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 32, height: 32)
                    .background(Palette.accent.opacity(0.14), in: .pokyh(Radius.sm))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .textStyle(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text(message)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: Config.privacyURL) {
                        Link(destination: url) {
                            Text(s.system.privacyRead).textStyle(.footnote)
                        }
                        .foregroundStyle(Palette.accentText)
                    }
                    if failed {
                        Text(s.system.privacyFailed)
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
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
                HStack(spacing: Spacing.sm) {
                    if saving { ProgressView().controlSize(.small).tint(.white) }
                    Text(s.system.understood)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary(compact: true))
            .disabled(saving)
        }
        .padding(Spacing.lg)
        .background(Palette.card, in: .pokyh(Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        .warmShadow(.level3)
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: WidthClass.formMaxWidth + Spacing.md * 2)
        .padding(.top, Spacing.sm)
        .animation(.easeOut(duration: Motion.fast), value: failed)
    }
}
