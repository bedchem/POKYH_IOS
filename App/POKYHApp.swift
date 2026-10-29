import SwiftUI
import PokyhCore
import PokyhDesign

@main
struct POKYHApp: App {
    private let accounts: AccountStore
    private let watch: WatchLink

    init() {
        let config = AppConfig.current
        accounts = AccountStore(store: KeychainStore(service: config.appBundleID))
        watch = WatchLink(store: accounts)
        watch.activate()
        #if DEBUG
        DebugAccount.applyLaunchArguments(accounts: accounts, watch: watch)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DesignCatalog()
        }
    }
}

#if DEBUG
/// Until the real sign-in lands: `-POKYHDemoAccount` signs a demo account in (and hands it to
/// the watch), `-POKYHSignOut` signs it out. Debug builds only.
enum DebugAccount {
    @MainActor
    static func applyLaunchArguments(accounts: AccountStore, watch: WatchLink) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-POKYHDemoAccount") {
            let account = StoredAccount(
                username: "max.muster",
                displayName: "Max Muster",
                school: School(loginName: "demo", server: "demo.webuntis.com", name: "Demo-Schule"),
                secret: "appkey:ABCDEFGHIJKLMNOP"
            )
            try? accounts.save(account)
            // The session needs a moment to activate before it can send.
            Task {
                try? await Task.sleep(for: .seconds(1))
                watch.signedIn(account)
            }
        } else if arguments.contains("-POKYHSignOut") {
            try? accounts.clear()
            Task {
                try? await Task.sleep(for: .seconds(1))
                watch.signedOut()
            }
        }
    }
}
#endif
