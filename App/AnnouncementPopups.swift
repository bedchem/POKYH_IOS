import SwiftUI
import Combine
import UIKit
import WebKit
import PokyhCore
import PokyhDesign

/// Admin announcements for the signed-in app, as one stack. Checked on every return to the
/// foreground (throttled here), shown once the app has settled.
@MainActor
final class PopupStore: ObservableObject {
    static let shared = PopupStore()

    @Published private(set) var stack = PopupStack()

    private static let seenKey = "pokyh_popups_seen"
    private var lastCheck: Int64 = 0
    private var owner: String?

    private var seen: [String: PopupSeenEntry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.seenKey) else { return [:] }
            return (try? JSONDecoder().decode([String: PopupSeenEntry].self, from: data)) ?? [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: Self.seenKey) }
        }
    }

    func check(_ app: AppState) {
        // Another account may have its own popups, and shouldn't get the last one's.
        if owner != app.session?.username {
            owner = app.session?.username
            stack = PopupStack()
            lastCheck = 0
        }
        let now = DayClock.ms(Date())
        if now - lastCheck < PopupSchedule.recheckMs { return }
        lastCheck = now
        let who = owner
        Task {
            // Optional by nature: a network or parse failure never surfaces.
            guard let live = try? await BackendClient.shared.activePopups(token: app.session?.apiToken), who == owner else { return }
            let clock = DayClock()
            let seen = seen
            let at = DayClock.ms(Date())
            stack.add(live.filter { PopupSchedule.isDue($0, seen: seen, now: at, clock: clock) })
        }
    }

    /// On screen for the minimum time: unlocked, and it counts as seen.
    func markViewed(_ popup: AnnouncementPopup) {
        stack.markViewed(popup)
        markSeen([popup])
    }

    func go(to index: Int) { stack.go(to: index) }
    func back() { stack.back() }

    func next() {
        if stack.next() { close() }
    }

    /// Closes the whole stack and counts all of it as seen, so what was skipped doesn't come back
    /// on the next start.
    func close() {
        guard !stack.locked else { return }
        let popups = stack.popups
        stack = PopupStack()
        markSeen(popups)
    }

    private func markSeen(_ popups: [AnnouncementPopup]) {
        guard !popups.isEmpty else { return }
        seen = PopupSchedule.withSeen(seen, popups: popups, now: DayClock.ms(Date()))
    }

    #if DEBUG
    /// For previews.
    func preview(_ stack: PopupStack) { self.stack = stack }
    #endif
}

/// Whether a sheet or popover is up anywhere. An overlay at the root would sit underneath it and
/// run down its countdown unseen, and a cover can't be presented over it.
enum PresentedModal {
    static var isUp: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .presentedViewController != nil
    }
}

/// Shows what's due over the whole app. A popup never flashes past while the sign-in check or a
/// sheet is still settling, and waits behind a recap that's open.
struct AnnouncementPopupHost: ViewModifier {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = PopupStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    private var due: Bool { store.stack.current != nil }

    func body(content: Content) -> some View {
        content
            .overlay {
                if settled, due {
                    AnnouncementPopupDialog(store: store)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: Motion.fast) : .spring(response: 0.4, dampingFraction: 0.85), value: settled && due)
            .task { store.check(app) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.check(app) }
            }
            .task(id: due) {
                settled = false
                guard due else { return }
                try? await Task.sleep(for: .milliseconds(PopupSchedule.settleMs))
                while !Task.isCancelled {
                    let active = UIApplication.shared.applicationState == .active
                    if active, !app.busy, RecapStore.shared.open == nil, !PresentedModal.isUp {
                        settled = true
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}

/// A card in the app's own language: an icon tile, the title, the backend's content and a footer
/// with "Zurück", one dot per popup and "Weiter". The ones still waiting peek out above the card.
/// Until a popup has been up for the minimum time a countdown ring sits where the X goes and nothing
/// closes or skips it. Only time the app is actually in the foreground counts.
private struct AnnouncementPopupDialog: View {
    @ObservedObject var store: PopupStore
    @Environment(\.strings) private var s
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var elapsed: Int64 = 0
    @State private var forward = true

    private static let peek: CGFloat = 9

    var body: some View {
        let stack = store.stack
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    // Tapping outside closes, once it may be closed.
                    .onTapGesture { store.close() }
                    .accessibilityHidden(true)
                if let current = stack.current {
                    card(stack, current, maxHeight: proxy.size.height * 0.82)
                        .frame(maxWidth: WidthClass.formMaxWidth + 80)
                        .padding(.horizontal, Spacing.xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAddTraits(.isModal)
        .task(id: "\(stack.current?.key ?? "")|\(stack.locked)|\(scenePhase == .active)") { await countDown() }
        .onChange(of: stack.current?.key) { elapsed = 0 }
    }

    private func countDown() async {
        guard let current = store.stack.current, store.stack.locked, scenePhase == .active else { return }
        var last = ContinuousClock.now
        while elapsed < PopupSchedule.minViewMs {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            let time = ContinuousClock.now
            let passed = (time - last).components
            last = time
            // Capped so a stalled frame can't jump the countdown ahead.
            let step = min(passed.seconds * 1000 + passed.attoseconds / 1_000_000_000_000_000, 100)
            elapsed = min(elapsed + step, PopupSchedule.minViewMs)
        }
        store.markViewed(current)
    }

    private func card(_ stack: PopupStack, _ current: AnnouncementPopup, maxHeight: CGFloat) -> some View {
        let tone = Decorative.periwinkle
        return ZStack(alignment: .top) {
            layer(visible: stack.waiting >= 2, inset: Spacing.huge, top: 0, opacity: 0.55)
            layer(visible: stack.waiting >= 1, inset: Spacing.xl, top: Self.peek, opacity: 1)

            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tone.ink)
                        .frame(width: 44, height: 44)
                        .background(tone.fill, in: .pokyh(Radius.md))
                        .accessibilityHidden(true)
                    Text(current.title)
                        .textStyle(.title2)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("title-\(current.key)")
                        .accessibilityAddTraits(.isHeader)
                    closeOrCountdown(locked: stack.locked)
                }

                PopupBody(popup: current)
                    .id(current.key)
                    .transition(stepTransition)

                footer(stack)
            }
            .padding(Spacing.xl)
            .modifier(CappedHeightModifier(limit: maxHeight))
            .background(Palette.card, in: .pokyh(Radius.xxl))
            .warmShadow(.level4)
            .padding(.top, Self.peek * 2)
            .animation(reduceMotion ? nil : .easeInOut(duration: Motion.standard), value: stack.index)
        }
    }

    /// Next slides in from the right, back from the left; with Reduce Motion it only fades.
    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)), removal: .opacity)
    }

    private func layer(visible: Bool, inset: CGFloat, top: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(Palette.cardAlt)
            .frame(height: Spacing.huge)
            .padding(.horizontal, inset)
            .padding(.top, top)
            .opacity(visible ? opacity : 0)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func closeOrCountdown(locked: Bool) -> some View {
        if locked {
            PopupCountdownRing(elapsed: elapsed)
        } else {
            Button { store.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Palette.cardAlt, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.common.close)
        }
    }

    private func footer(_ stack: PopupStack) -> some View {
        HStack(spacing: Spacing.sm) {
            // Equal widths on both sides keep the dots exactly centered.
            Group {
                if stack.index > 0 {
                    TextLinkButton(s.common.back, color: Palette.textSecondary) {
                        forward = false
                        store.back()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if stack.popups.count > PopupSchedule.maxDots {
                Text("\(stack.index + 1) / \(stack.popups.count)")
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            } else if stack.popups.count > 1 {
                PopupDots(stack: stack) { i in
                    forward = i > stack.index
                    store.go(to: i)
                }
            }

            Button(stack.isLast ? s.common.done : s.system.next) {
                forward = true
                store.next()
            }
            .buttonStyle(.primary(compact: true))
            .disabled(stack.locked)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// As tall as the content, up to a limit. `.frame(maxHeight:)` would always take the whole limit.
private struct CappedHeight: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = min(proposal.height ?? limit, limit)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private struct CappedHeightModifier: ViewModifier {
    let limit: CGFloat

    func body(content: Content) -> some View {
        CappedHeight(limit: limit) { content }
    }
}

/// The seconds left inside a ring that drains with them.
private struct PopupCountdownRing: View {
    let elapsed: Int64
    @Environment(\.strings) private var s

    var body: some View {
        let total = PopupSchedule.minViewMs
        let seconds = max(1, Int((total - elapsed + 999) / 1000))
        let remaining = 1 - Double(elapsed) / Double(total)
        ZStack {
            Circle().fill(Palette.cardAlt)
            Circle().stroke(Palette.textTertiary.opacity(0.25), lineWidth: 2.5).padding(3)
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(Brand.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Text("\(seconds)")
                .textStyle(TextStyle.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(width: 36, height: 36)
        .frame(width: 44, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.system.closeIn(seconds))
    }
}

/// One dot per popup; the current one stretches into a pill. A dot only leads somewhere the
/// stack allows, not past one still counting down.
private struct PopupDots: View {
    let stack: PopupStack
    let select: (Int) -> Void
    @Environment(\.strings) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(stack.popups.indices, id: \.self) { i in
                let active = i == stack.index
                Button { select(i) } label: {
                    Capsule()
                        .fill(active ? Brand.accent : Palette.textTertiary)
                        .frame(width: active ? 22 : 7, height: 7)
                        .padding(.horizontal, 3)
                        .frame(height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!active && !stack.canReach(i))
                .accessibilityLabel(s.system.popupOf(i + 1, stack.popups.count))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Motion.standard), value: stack.index)
    }
}

/// The content in a web view: Markdown, tables, colors and images come out far more faithfully
/// there than rebuilt by hand. Grows with its content and scrolls once the card is full.
private struct PopupBody: View {
    let popup: AnnouncementPopup
    @State private var height: CGFloat = 1
    @Environment(\.colorScheme) private var scheme
    // Read so the page comes out again when the text size changes.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let size = UIFontMetrics(forTextStyle: .body).scaledValue(for: 15)
        PopupWebView(document: PopupSchedule.document(body: popup.html, isDark: scheme == .dark, fontSize: Double(size)), height: $height)
            // As tall as its content, less when the card is full: the title and buttons stay.
            .frame(maxHeight: height)
            .layoutPriority(-1)
            .accessibilityLabel(popup.title)
    }
}

private struct PopupWebView: UIViewRepresentable {
    let document: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // The HTML is sanitised on the server; it gets no scripts and leaves nothing behind anyway.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.bounces = false
        view.scrollView.showsHorizontalScrollIndicator = false
        view.navigationDelegate = context.coordinator
        context.coordinator.watch(view) { height in
            self.height = max(1, height)
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != document else { return }
        context.coordinator.loaded = document
        view.loadHTMLString(document, baseURL: URL(string: Config.backendURL))
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        private var observation: NSKeyValueObservation?

        func watch(_ view: WKWebView, onHeight: @escaping (CGFloat) -> Void) {
            // Images decode late, so it's the content size that says how tall this gets.
            observation = view.scrollView.observe(\.contentSize, options: [.new]) { _, change in
                guard let size = change.newValue, size.height > 0 else { return }
                DispatchQueue.main.async { onHeight(size.height) }
            }
        }

        func stop() {
            observation = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                // The page itself; anything else it tries to load in its own frame stays out.
                decisionHandler(action.navigationType == .other ? .allow : .cancel)
                return
            }
            // Links open outside the app.
            if ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}

#if DEBUG
#Preview("Popups") {
    let html = "<h2>Neue Mensa-Zeiten</h2><p>Ab Montag öffnet die Mensa um <b>11:30</b>.</p><ul><li>Montag bis Freitag</li><li>Nur mit Vorbestellung</li></ul>"
    let stack = PopupStack(popups: [
        AnnouncementPopup(id: "a", revision: 1, title: "Mensa", html: html, showCount: 1),
        AnnouncementPopup(id: "b", revision: 1, title: "Skitag", html: "<p>Am 12. Februar.</p>", showCount: 1),
    ])
    Color.gray.ignoresSafeArea()
        .overlay { AnnouncementPopupDialog(store: { PopupStore.shared.preview(stack); return PopupStore.shared }()) }
        .environment(\.strings, .of(.de))
}
#endif
