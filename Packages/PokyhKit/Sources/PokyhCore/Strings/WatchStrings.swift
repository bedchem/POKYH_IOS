// iOS-only: the watch app has no Android counterpart yet (see docs/android-parity.md).

public struct WatchStrings: Sendable {
    public let signInTitle: String
    /// The watch was signed out from the account's device list.
    public let signedOutTitle: String
    public let signedOutMessage: String
    public let hello: @Sendable (String) -> String
}

extension WatchStrings {
    static let de = WatchStrings(
        signInTitle: "Auf dem iPhone anmelden",
        signedOutTitle: "Abgemeldet",
        signedOutMessage: "Verbinde die Watch in den Einstellungen auf dem iPhone wieder.",
        hello: { "Hallo, \($0)" }
    )

    static let it = WatchStrings(
        signInTitle: "Accedi sull’iPhone",
        signedOutTitle: "Disconnesso",
        signedOutMessage: "Ricollega l’orologio nelle impostazioni sull’iPhone.",
        hello: { "Ciao, \($0)" }
    )

    static let en = WatchStrings(
        signInTitle: "Sign in on your iPhone",
        signedOutTitle: "Signed out",
        signedOutMessage: "Connect the watch again in the settings on your iPhone.",
        hello: { "Hi, \($0)" }
    )
}
