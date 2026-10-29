// iOS-only: the watch app has no Android counterpart yet (see docs/android-parity.md).

public struct WatchStrings: Sendable {
    public let signInTitle: String
    public let signInMessage: String
    public let waitingForPhone: String
    public let hello: @Sendable (String) -> String
}

extension WatchStrings {
    static let de = WatchStrings(
        signInTitle: "Auf dem iPhone anmelden",
        signInMessage: "Öffne POKYH auf deinem iPhone und melde dich an. Danach siehst du hier deinen Tag.",
        waitingForPhone: "Wartet auf das iPhone …",
        hello: { "Hallo, \($0)" }
    )

    static let it = WatchStrings(
        signInTitle: "Accedi sull’iPhone",
        signInMessage: "Apri POKYH sul tuo iPhone ed effettua l’accesso. Poi qui vedrai la tua giornata.",
        waitingForPhone: "In attesa dell’iPhone …",
        hello: { "Ciao, \($0)" }
    )

    static let en = WatchStrings(
        signInTitle: "Sign in on your iPhone",
        signInMessage: "Open POKYH on your iPhone and sign in. Your day shows up here after that.",
        waitingForPhone: "Waiting for the iPhone …",
        hello: { "Hi, \($0)" }
    )
}
