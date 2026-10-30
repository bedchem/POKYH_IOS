import Foundation
import Testing
@testable import PokyhCore

struct AccountRosterTests {
    struct Account: RosterEntry, Equatable {
        var username: String
        var nickname: String?
        var school: String?
    }

    let student = Account(username: "max.muster", nickname: "Max", school: "lbs")
    let parent = Account(username: "eltern.muster", school: "lbs")

    @Test func addsNewAccountsAtTheEnd() {
        let list = AccountRoster.upsert(parent, into: [student])
        #expect(list.map(\.username) == ["max.muster", "eltern.muster"])
    }

    @Test func signingInAgainKeepsThePlaceAndTheNickname() {
        let again = Account(username: "Max.Muster", nickname: nil, school: nil)
        let list = AccountRoster.upsert(again, into: [student, parent]) { new, old in
            if new.nickname == nil { new.nickname = old.nickname }
            if new.school == nil { new.school = old.school }
        }
        #expect(list.count == 2)
        #expect(list[0].username == "Max.Muster")
        #expect(list[0].nickname == "Max")
        #expect(list[0].school == "lbs")
        #expect(list[1] == parent)
    }

    @Test func duplicatesFromOlderBuildsCollapse() {
        let list = AccountRoster.upsert(student, into: [student, parent, Account(username: "MAX.MUSTER")])
        #expect(list.map(\.username) == ["max.muster", "eltern.muster"])
    }

    @Test func removingIgnoresCase() {
        #expect(AccountRoster.removing("MAX.muster ", from: [student, parent]) == [parent])
    }

    @Test func pointersMoveOnWhenTheirAccountGoes() {
        let rest = [parent]
        #expect(AccountRoster.successor(for: "max.muster", removed: "max.muster", remaining: rest) == "eltern.muster")
        #expect(AccountRoster.successor(for: "eltern.muster", removed: "max.muster", remaining: rest) == "eltern.muster")
        #expect(AccountRoster.successor(for: nil, removed: "max.muster", remaining: rest) == "eltern.muster")
        #expect(AccountRoster.successor(for: "max.muster", removed: "max.muster", remaining: [Account]()) == nil)
    }

    @Test func findsWhateverTheCase() {
        #expect(AccountRoster.find("ELTERN.MUSTER", in: [student, parent]) == parent)
        #expect(AccountRoster.find("nobody", in: [student, parent]) == nil)
        #expect(AccountRoster.key("  Max.Muster ") == "max.muster")
    }
}

struct AutoLockTests {
    let start = ContinuousClock.now

    @Test func staysOpenForAShortTrip() {
        var lock = AutoLock()
        lock.didLeave(signedIn: true, at: start)
        let locks = lock.didReturn(at: start + .seconds(599))
        #expect(!locks)
    }

    @Test func locksAfterTenMinutes() {
        var lock = AutoLock()
        lock.didLeave(signedIn: true, at: start)
        #expect(lock.isDue(at: start + .seconds(600)))
        let locks = lock.didReturn(at: start + .seconds(600))
        #expect(locks)
    }

    @Test func nothingToLockWhenNotSignedIn() {
        var lock = AutoLock()
        lock.didLeave(signedIn: false, at: start)
        let locks = lock.didReturn(at: start + .seconds(3600))
        #expect(!locks)
    }

    @Test func aSecondBackgroundEventKeepsTheFirstTime() {
        var lock = AutoLock()
        lock.didLeave(signedIn: true, at: start)
        lock.didLeave(signedIn: true, at: start + .seconds(500))
        let locks = lock.didReturn(at: start + .seconds(650))
        #expect(locks)
    }

    @Test func comingBackStartsOver() {
        var lock = AutoLock(interval: .seconds(60))
        lock.didLeave(signedIn: true, at: start)
        let locks = lock.didReturn(at: start + .seconds(30))
        #expect(!locks)
        // Back on screen for a while, then away again briefly.
        lock.didLeave(signedIn: true, at: start + .seconds(300))
        let locksAgain = lock.didReturn(at: start + .seconds(330))
        #expect(!locksAgain)
        #expect(!lock.isDue(at: start + .seconds(10_000)))
    }
}

struct UnlockStringsTests {
    @Test func everyLanguageNamesTheAccount() {
        for lang in Lang.allCases {
            let t = UnlockStrings.of(lang)
            #expect(t.switchReason("max.muster").contains("max.muster"))
            #expect(!t.unlockReason.isEmpty && !t.confirmReason.isEmpty && !t.confirming.isEmpty)
        }
    }
}
