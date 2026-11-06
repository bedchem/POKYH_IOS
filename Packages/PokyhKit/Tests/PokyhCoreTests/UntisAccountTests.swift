import Foundation
import Testing
@testable import PokyhCore

struct UntisAccountTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private let general = #"""
    {"data":{"pwChangeAllowed":false,"profile":{"email":" anna@stub.invalid ","forwardMessageToEmail":true,"languageCode":"de",
    "userTaskNotifications":true,"itemOnStartPage":"timetable","showLessonsOfDay":null}}}
    """#

    // ── Reading ──────────────────────────────────────────────────────────────

    @Test func readsTheThreeAnswers() throws {
        let access = data(#"{"data":{"canUseTotp":true,"totpCredentials":{"secret":"ABC","isTotpRequired":true}}}"#)
        let languages = data(#"{"data":{"languages":[{"key":"de","name":"Deutsch"},{"key":"it","name":"Italiano"}]}}"#)
        let account = try #require(UntisAccount(general: data(general), access: access, languages: languages))
        #expect(account.email == "anna@stub.invalid")
        #expect(account.forwardToEmail)
        #expect(!account.passwordChangeAllowed)
        #expect(account.twoFactorAvailable && account.twoFactorEnabled && account.twoFactorRequired)
        #expect(account.languageName == "Deutsch")
    }

    @Test func noProfileIsNoAccount() {
        for bad in ["", "null", "[]", "{}", #"{"data":null}"#, #"{"data":{"profile":null}}"#, #"{"data":{"profile":12}}"#, "<html>"] {
            #expect(UntisAccount(general: data(bad), access: nil, languages: nil) == nil)
        }
    }

    @Test func aBareProfileStillWorks() throws {
        let account = try #require(UntisAccount(general: data(#"{"data":{"profile":{}}}"#), access: nil, languages: nil))
        #expect(account.email == "")
        #expect(!account.hasEmail)
        #expect(!account.forwardToEmail)
        #expect(account.passwordChangeAllowed)
        #expect(!account.offersTwoFactor)
        #expect(account.languages.isEmpty)
    }

    @Test func junkInEveryFieldReadsAsNothing() throws {
        let general = data(#"{"data":{"pwChangeAllowed":"nein","profile":{"email":12,"forwardMessageToEmail":"ja","languageCode":[1]}}}"#)
        let access = data(#"{"data":{"canUseTotp":3,"totpCredentials":{"secret":"   ","isTotpRequired":{}}}}"#)
        let languages = data(#"{"data":{"languages":[{"key":"de"},{"name":"X"},7,null,{"key":"","name":""},{"key":"de","name":"A"},{"key":"de","name":"B"}]}}"#)
        let account = try #require(UntisAccount(general: general, access: access, languages: languages))
        #expect(account.email == "")
        #expect(!account.forwardToEmail)
        #expect(account.passwordChangeAllowed)
        #expect(!account.twoFactorEnabled && !account.twoFactorRequired && !account.twoFactorAvailable)
        #expect(account.languages == [.init(key: "de", name: "A")])
    }

    // ── Saving ───────────────────────────────────────────────────────────────

    @Test func savingKeepsTheRestAsItCame() throws {
        let body = try #require(UntisAccount.saveBody(general: data(general), email: " neu@stub.invalid "))
        #expect(body["email"] as? String == "neu@stub.invalid")
        #expect(body["forwardMessageToEmail"] as? Bool == true)
        #expect(body["languageCode"] as? String == "de")
        #expect(body["userTaskNotifications"] as? Bool == true)
        #expect(body["itemOnStartPage"] as? String == "timetable")
        #expect(body["showLessonsOfDay"] is NSNull)
        #expect(body["showNextDayPeriods"] == nil)
    }

    @Test func savingChangesWhatItWasTold() throws {
        let body = try #require(UntisAccount.saveBody(general: data(general), forwardToEmail: false, languageCode: "it"))
        #expect(body["forwardMessageToEmail"] as? Bool == false)
        #expect(body["languageCode"] as? String == "it")
        #expect(body["email"] as? String == " anna@stub.invalid ")
    }

    @Test func nothingToSaveFromWithoutAProfile() {
        for bad in ["", "null", #"{"data":{}}"#, "<html>"] {
            #expect(UntisAccount.saveBody(general: data(bad), email: "a@b.c") == nil)
        }
    }

    @Test func emailAddresses() {
        for good in ["", "  ", "a@b.c", " anna.rossi+x@schule.example.org "] {
            #expect(UntisAccount.isValidEmail(good), "\(good)")
        }
        for bad in ["anna", "a@b", "@b.c", "a b@c.d", "a@@b.c", String(repeating: "x", count: 200) + "@b.c"] {
            #expect(!UntisAccount.isValidEmail(bad), "\(bad)")
        }
    }

    // ── Two-factor ───────────────────────────────────────────────────────────

    @Test func aNewSecretIsCleanedUp() throws {
        let reply = data(#"{"data":{"totpCredentials":{"secret":" jbsw y3dp\nehpk 3pxp==","qrText":"otpauth://totp/POKYH:anna?secret=JBSWY3DPEHPK3PXP"}}}"#)
        let setup = try #require(TwoFactorSetup(created: reply))
        #expect(setup.secret == "JBSWY3DPEHPK3PXP==")
        #expect(setup.groupedSecret == "JBSW Y3DP EHPK 3PXP")
        #expect(setup.link?.scheme == "otpauth")
    }

    @Test func aLinkMustBeAnAuthenticatorLink() throws {
        for bad in ["https://evil.invalid/?secret=ABC", "javascript:alert(1)", "", "ohne scheme"] {
            let reply = ["data": ["totpCredentials": ["secret": "ABCD", "qrText": bad]]]
            let setup = try #require(TwoFactorSetup(created: JSONSerialization.data(withJSONObject: reply)))
            #expect(setup.link == nil, "\(bad)")
        }
        #expect(try #require(TwoFactorSetup(created: data(#"{"data":{"totpCredentials":{"secret":"ABCD"}}}"#))).link == nil)
    }

    @Test func noSecretNoSetup() {
        let long = String(repeating: "A", count: 257)
        for bad in ["", "{}", "null", #"{"data":{"totpCredentials":null}}"#, #"{"data":{"totpCredentials":{"secret":""}}}"#,
                    #"{"data":{"totpCredentials":{"secret":"   "}}}"#, #"{"data":{"totpCredentials":{"secret":12345}}}"#,
                    #"{"data":{"totpCredentials":{"secret":"äöü"}}}"#, "{\"data\":{\"totpCredentials\":{\"secret\":\"\(long)\"}}}"] {
            #expect(TwoFactorSetup(created: data(bad)) == nil, "\(bad)")
        }
    }

    @Test func theSecretKeepsOutOfLogs() throws {
        let setup = try #require(TwoFactorSetup(created: data(#"{"data":{"totpCredentials":{"secret":"JBSWY3DP","qrText":"otpauth://totp/x?secret=JBSWY3DP"}}}"#)))
        #expect(!"\(setup)".contains("JBSWY3DP"))
        #expect(!String(reflecting: setup).contains("JBSWY3DP"))
    }

    @Test func groupingCopesWithShortAndOddKeys() throws {
        func grouped(_ secret: String) throws -> String {
            try #require(TwoFactorSetup(created: data("{\"data\":{\"totpCredentials\":{\"secret\":\"\(secret)\"}}}"))).groupedSecret
        }
        #expect(try grouped("A") == "A")
        #expect(try grouped("ABCDE") == "ABCD E")
        #expect(try grouped("====") == "")
    }

    // ── Passwords ────────────────────────────────────────────────────────────

    @Test func newPasswordsGetCheckedFirst() {
        #expect(PasswordChangeProblem.check(old: "", new: "b", repeated: "b") == .missing)
        #expect(PasswordChangeProblem.check(old: "a", new: "", repeated: "") == .missing)
        #expect(PasswordChangeProblem.check(old: "a", new: "b", repeated: "c") == .mismatch)
        #expect(PasswordChangeProblem.check(old: "a", new: "a", repeated: "a") == .unchanged)
        #expect(PasswordChangeProblem.check(old: "a", new: "b", repeated: "b") == nil)
        // A space is part of a password.
        #expect(PasswordChangeProblem.check(old: "a", new: "b ", repeated: "b") == .mismatch)
    }

    // ── The copy the watch signs in with ─────────────────────────────────────

    private func store(holding secret: String, of name: String = "anna") throws -> AccountStore {
        let store = AccountStore(store: MemorySecureStore())
        try store.save(StoredAccount(username: name, displayName: "Anna", school: School(loginName: "s", server: "s.invalid"), secret: secret))
        return store
    }

    @Test func theNewPasswordReachesTheWatch() throws {
        let phone = try store(holding: "alt")
        let sent = try #require(try phone.replacePassword("neu", of: "ANNA"))
        #expect(sent.secret == "neu")
        #expect(phone.load()?.secret == "neu")

        // What the watch does with the hand-off that goes out with it.
        let watch = try store(holding: "alt")
        try #require(AccountHandoff(payload: AccountHandoff(account: sent, sentAt: .now.addingTimeInterval(1)).payload)).apply(to: watch)
        #expect(watch.load()?.secret == "neu")
    }

    @Test func anotherAccountOnTheWatchStays() throws {
        let phone = try store(holding: "seines", of: "luca")
        #expect(try phone.replacePassword("neu", of: "anna") == nil)
        #expect(phone.load()?.secret == "seines")
        #expect(phone.load()?.username == "luca")
    }

    @Test func anAppKeyIsNotThePassword() throws {
        let phone = try store(holding: "appkey:ABCDEFGHIJKLMNOP")
        #expect(try phone.replacePassword("neu", of: "anna") == nil)
        #expect(phone.load()?.secret == "appkey:ABCDEFGHIJKLMNOP")
    }

    @Test func nothingStoredStaysNothing() throws {
        let phone = AccountStore(store: MemorySecureStore())
        #expect(try phone.replacePassword("neu", of: "anna") == nil)
        #expect(phone.load() == nil)
    }
}
