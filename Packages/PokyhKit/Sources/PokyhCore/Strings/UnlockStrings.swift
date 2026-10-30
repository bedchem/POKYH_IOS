// iOS-only: what the Face ID / Touch ID / passcode sheet says. Android's prompt has its own
// title and subtitle (LoginStrings.lockTitle/lockSubtitle); the system sheet here takes a reason.

public struct UnlockStrings: Sendable {
    /// Unlocking the app into an account.
    public let unlockReason: String
    /// Switching to another saved account.
    public let switchReason: @Sendable (String) -> String
    /// Reading a saved password later on (refreshing an account, pairing the watch).
    public let confirmReason: String
    /// Status line while the check runs.
    public let confirming: String

    public static func of(_ lang: Lang) -> UnlockStrings {
        switch lang {
        case .de: de
        case .it: it
        case .en: en
        }
    }

    static let de = UnlockStrings(
        unlockReason: "Entsperre POKYH, um dich anzumelden.",
        switchReason: { "Wechsel zu \($0) bestätigen." },
        confirmReason: "Bestätige, dass du es bist.",
        confirming: "Identität wird bestätigt …"
    )

    static let it = UnlockStrings(
        unlockReason: "Sblocca POKYH per accedere.",
        switchReason: { "Conferma il passaggio a \($0)." },
        confirmReason: "Conferma che sei tu.",
        confirming: "Verifica dell’identità …"
    )

    static let en = UnlockStrings(
        unlockReason: "Unlock POKYH to sign in.",
        switchReason: { "Confirm switching to \($0)." },
        confirmReason: "Confirm it’s you.",
        confirming: "Confirming it’s you …"
    )
}
