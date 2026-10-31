import PokyhCore
import SwiftUI

// The mascot of the sign-in screen, the way the web shows it on phones: on its own above the form,
// its speech bubble beside it. It answers the form: a wave and "Hallo, …!" while the name is typed,
// both hands over its eyes for the password (peeking when the password is shown), wide eyes and
// then a thumb up when the phone fills the form in, thinking while signing in, a wobble and a drop
// of sweat at an error. A word it must not say in the name makes it angry. Otherwise it blinks and
// breathes; each key makes it hop.

public enum MascotFocus: Sendable { case user, password }

public enum MascotEventKind: Sendable { case autofill, error, tap }

/// Something that happened, numbered so the same kind twice still counts twice.
public struct MascotEvent: Equatable, Sendable {
    public let kind: MascotEventKind
    public let n: Int64

    public init(_ kind: MascotEventKind, n: Int64) {
        self.kind = kind
        self.n = n
    }
}

public struct LoginMascotState: Sendable {
    public var focus: MascotFocus?
    public var username: String
    public var showPassword: Bool
    public var loading: Bool
    /// Counts keystrokes: each one makes it hop.
    public var keys: Int
    public var event: MascotEvent?
    /// Back on the saved accounts: it waves and says so.
    public var welcomeBack: Bool

    public init(
        focus: MascotFocus? = nil,
        username: String = "",
        showPassword: Bool = false,
        loading: Bool = false,
        keys: Int = 0,
        event: MascotEvent? = nil,
        welcomeBack: Bool = false
    ) {
        self.focus = focus
        self.username = username
        self.showPassword = showPassword
        self.loading = loading
        self.keys = keys
        self.event = event
        self.welcomeBack = welcomeBack
    }
}

/// The small mascot with its speech bubble. With `onTap` it can be tapped; the caller counts the
/// taps into a `.tap` event, and many in a row make it mad. `centered` is for the middle of a
/// screen: the mascot centred, its words above it, keep the room at `centeredAspect`.
public struct LoginMascotBadge: View {
    let state: LoginMascotState
    let onTap: (() -> Void)?
    let maxWidth: CGFloat
    let centered: Bool

    @Environment(\.strings) private var s
    @State private var phase: Phase?
    @State private var taps: [Date] = []

    public init(state: LoginMascotState, onTap: (() -> Void)? = nil, maxWidth: CGFloat = 252, centered: Bool = false) {
        self.state = state
        self.onTap = onTap
        self.maxWidth = maxWidth
        self.centered = centered
    }

    // Moments that play out on their own after an event.
    private enum Phase { case surprise, thumb, error, mad }

    private enum Say {
        case hello, helloName(String), oops, angry, back, tooMuch

        var key: String {
            switch self {
            case .hello, .helloName: "hello"
            case .oops: "oops"
            case .angry: "angry"
            case .back: "back"
            case .tooMuch: "toomuch"
            }
        }
    }

    // The drawing's width: the mascot and room beside it for a bubble on up to three lines.
    private static let badgeW = 112
    // Room above the head, so the form below doesn't move while it talks.
    private static let top = -12

    // The centred drawing: room either side for a bubble over its head, and above the signs for
    // one on two lines.
    private static let centeredW = 96
    private static let centeredLine = 80
    private static let tailY = -1
    private static let tailYSigns = -11
    private static let centeredTop = tailYSigns - 2 - (2 * 6 + 5) - 1

    /// Width to height of the centred drawing, for keeping its room while something stands in.
    public static let centeredAspect = CGFloat(centeredW) / CGFloat(Mascot.height - centeredTop)

    public var body: some View {
        let (figure, say) = look()
        PixelArt(scene: scene(figure, say), label: onTap == nil ? nil : s.login.mascotTapLabel, clip: false)
            .frame(maxWidth: maxWidth)
            .modifier(MascotTap(action: onTap))
            .onChange(of: state.event, initial: true) { _, event in react(to: event) }
            .task(id: phase) { await playOut() }
    }

    private func react(to event: MascotEvent?) {
        switch event?.kind {
        case .autofill: phase = .surprise
        case .error: phase = .error
        case .tap:
            // A tap does nothing, only many in a row make it mad.
            let now = Date()
            taps.append(now)
            taps.removeAll { now.timeIntervalSince($0) > 3 }
            if taps.count >= 6 {
                taps.removeAll()
                phase = .mad
            }
        case nil: break
        }
    }

    // Keyed on the look, not the event: one more tap must not cancel the wait that ends it.
    private func playOut() async {
        let (wait, next): (Int, Phase?) = switch phase {
        case .surprise: (950, .thumb)
        case .thumb: (1750, nil)
        case .error: (2600, nil)
        case .mad: (2200, nil)
        case nil: (0, nil)
        }
        guard phase != nil else { return }
        try? await Task.sleep(for: .milliseconds(wait))
        if !Task.isCancelled { phase = next }
    }

    private func look() -> (MascotLook, Say?) {
        let fuming = MascotLook(pose: .init(eyes: .angry, mouth: .frown, arms: .fists), anger: true, motion: .fume)
        switch phase {
        case .error: return (MascotLook(pose: .init(look: Pt(0, 1), mouth: .wobble), sweat: true, motion: .shake), .oops)
        case .surprise: return (MascotLook(pose: .init(eyes: .wide, mouth: .o), mark: "!", motion: .jump), nil)
        case .thumb: return (MascotLook(pose: .init(eyes: .happy, mouth: .grin, arms: .thumb)), nil)
        case .mad: return (fuming, .tooMuch)
        case nil: break
        }
        if state.loading { return (MascotLook(pose: .init(look: Pt(1, 0)), think: true), nil) }
        let typing: MascotMotion = state.keys > 0 ? .hop : .bob
        let name = state.username.trimmingCharacters(in: .whitespacesAndNewlines)
        switch state.focus {
        case .password:
            if state.showPassword {
                return (MascotLook(pose: .init(look: Pt(1, 1), mouth: .o, arms: .peek), motion: typing), nil)
            }
            return (MascotLook(pose: .init(eyes: .closed, mouth: .flat, arms: .cover), motion: typing), nil)
        case .user:
            if !name.isEmpty && WordFilter.isOffensive(name) { return (fuming, .angry) }
            if !name.isEmpty {
                return (MascotLook(pose: .init(eyes: .happy, mouth: .grin, arms: .wave), wave: true, motion: typing), .helloName(name))
            }
            return (MascotLook(pose: .init(look: Pt(1, 0), arms: .wave), wave: true), .hello)
        case nil:
            if !name.isEmpty && WordFilter.isOffensive(name) { return (fuming, .angry) }
            if state.welcomeBack { return (MascotLook(pose: .init(eyes: .happy, arms: .wave), wave: true), .back) }
            return (MascotLook(pose: .init(look: Pt(1, 0)), blink: true), nil)
        }
    }

    private func text(_ say: Say) -> String {
        let t = s.login
        switch say {
        case .hello: return t.mascotHello
        // A name it shouldn't say gets a plain hello instead.
        case .helloName(let name): return WordFilter.isOffensive(name) ? t.mascotHello : t.mascotHelloName(name)
        case .oops: return t.mascotOops
        case .angry: return t.mascotAngry
        case .back: return t.mascotBack
        case .tooMuch: return t.mascotTooMuch
        }
    }

    private func scene(_ figure: MascotLook, _ say: Say?) -> PixelScene {
        let motionKey: String = switch figure.motion {
        case .hop: "h\(state.keys)"
        case .bob: "bob"
        default: "\(figure.motion)\(state.event?.n ?? 0)"
        }
        let signs = figure.anger || figure.mark != nil || figure.think
        let speech = say.map { say in
            centered
                ? Mascot.bubbleAbove(text(say), cx: Mascot.width / 2, y: signs ? Self.tailYSigns : Self.tailY, maxWidth: Self.centeredLine)
                : Mascot.bubble(text(say), x: Mascot.width - 2, y: 17, maxWidth: Self.badgeW - Mascot.width - 4)
        }
        var layers = Mascot.layers(figure, motionKey: motionKey, marksBeside: !centered)
        if let speech, let say { layers.append(PixelLayer(speech, anims: [Px.pop], startKey: "say:\(say.key)")) }
        if centered {
            return PixelScene(
                w: Self.centeredW,
                h: Mascot.height - Self.centeredTop,
                layers: layers,
                x0: Mascot.width / 2 - Self.centeredW / 2,
                y0: Self.centeredTop
            )
        }
        let top = min(Self.top, speech.map { $0.top() - 1 } ?? 0)
        return PixelScene(w: Self.badgeW, h: Mascot.height - top, layers: layers, y0: top)
    }
}

private struct MascotTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(.rect)
                .onTapGesture(perform: action)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}
