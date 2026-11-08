import SwiftUI
import PokyhCore
import PokyhDesign

/// Asks once when a watch shows up: connect it if POKYH is on it, or how to put POKYH on it.
/// Waits behind whatever else wants the screen first (sign-in, notices, announcements).
struct WatchOfferHost: ViewModifier {
    @Environment(AppState.self) private var app
    @State private var offer: WatchSync.Offer?
    @State private var shown: WatchSync.Offer?
    @State private var answered = false

    private var due: WatchSync.Offer? { WatchSync.offer(signedIn: app.session != nil) }

    func body(content: Content) -> some View {
        content
            .sheet(item: $offer, onDismiss: dismissed) { offer in
                WatchOfferSheet(offer: offer) { connect in
                    answered = true
                    WatchSync.answered(offer, connect: connect, session: app.session)
                    self.offer = nil
                }
            }
            .task(id: due) { await present() }
    }

    private func present() async {
        guard let wanted = due, offer == nil else { return }
        try? await Task.sleep(for: .seconds(2))
        while !Task.isCancelled {
            let free = UIApplication.shared.applicationState == .active && !app.busy && app.privacyNotice == nil
                && PopupStore.shared.stack.current == nil && RecapStore.shared.open == nil && !PresentedModal.isUp
            if free {
                guard due == wanted else { return }
                answered = false
                shown = wanted
                offer = wanted
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Swiped away without an answer: the same as "Not now".
    private func dismissed() {
        guard let shown, !answered else { return }
        WatchSync.answered(shown, connect: false, session: app.session)
    }
}

private struct WatchOfferSheet: View {
    let offer: WatchSync.Offer
    let answer: (Bool) -> Void

    @Environment(\.strings) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var height: CGFloat = 380

    var body: some View {
        let t = ProfileText.of(s.lang)
        VStack(spacing: Spacing.lg) {
            Image(systemName: offer == .connect ? "applewatch.radiowaves.left.and.right" : "applewatch")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Brand.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: offer == .connect && !reduceMotion)
                .frame(height: 72)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.sm) {
                Text(offer == .connect ? t.offerTitle : t.installTitle)
                    .textStyle(.title2)
                    .foregroundStyle(Palette.textPrimary)
                Text(offer == .connect ? t.offerBody : t.installBody)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Spacing.xs) {
                Button { answer(true) } label: {
                    Text(offer == .connect ? t.connectButton : s.common.ok).frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                if offer == .connect {
                    Button(t.offerLater) { answer(false) }
                        .buttonStyle(.plain)
                        .textStyle(.headline)
                        .foregroundStyle(Palette.accentText)
                        .frame(minHeight: 44)
                }
            }
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: WidthClass.formMaxWidth)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.bg)
        .sensoryFeedback(.impact(weight: .light), trigger: offer)
    }
}
