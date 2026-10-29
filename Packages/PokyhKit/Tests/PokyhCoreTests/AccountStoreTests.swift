import Foundation
import Testing
@testable import PokyhCore

struct AccountStoreTests {
    let school = School(loginName: "demo-school", server: "demo.webuntis.com", name: "Demo School")

    func account(_ name: String = "max.muster") -> StoredAccount {
        StoredAccount(username: name, displayName: "Max Muster", school: school, secret: "appkey:ABCDEFGHIJKLMNOP", signedInAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func remembersTheAccountUntilSignedOut() throws {
        let store = AccountStore(store: MemorySecureStore())
        #expect(store.load() == nil)
        try store.save(account())
        #expect(store.load() == account())
        try store.clear()
        #expect(store.load() == nil)
    }

    @Test func survivesARelaunch() throws {
        // A new AccountStore on the same backing store is what a relaunch looks like.
        let backing = MemorySecureStore()
        try AccountStore(store: backing).save(account())
        #expect(AccountStore(store: backing).load()?.username == "max.muster")
    }

    @Test func handoffRoundTrips() throws {
        let sent = AccountHandoff(account: account(), sentAt: Date(timeIntervalSince1970: 1_800_000_100))
        #expect(AccountHandoff(payload: sent.payload) == sent)
        let signedOut = AccountHandoff(account: nil, sentAt: Date(timeIntervalSince1970: 1_800_000_200))
        #expect(AccountHandoff(payload: signedOut.payload) == signedOut)
    }

    @Test func somethingElseIsNotAHandoff() {
        #expect(AccountHandoff(payload: [:]) == nil)
        #expect(AccountHandoff(payload: AccountHandoff.request) == nil)
        #expect(AccountHandoff(payload: ["pokyh.sentAt": 1.0, "pokyh.account": Data("nope".utf8)]) == nil)
        #expect(AccountHandoff.isRequest(AccountHandoff.request))
    }

    @Test func aLateOlderHandoffDoesNotUndoANewerOne() throws {
        let store = AccountStore(store: MemorySecureStore())
        let signIn = AccountHandoff(account: account(), sentAt: Date(timeIntervalSince1970: 100))
        let signOut = AccountHandoff(account: nil, sentAt: Date(timeIntervalSince1970: 200))

        #expect(try signOut.apply(to: store))
        // userInfo transfers can arrive after the newer applicationContext.
        #expect(try signIn.apply(to: store) == false)
        #expect(store.load() == nil)

        let signInAgain = AccountHandoff(account: account("anna.beispiel"), sentAt: Date(timeIntervalSince1970: 300))
        #expect(try signInAgain.apply(to: store))
        #expect(store.load()?.username == "anna.beispiel")
    }
}
