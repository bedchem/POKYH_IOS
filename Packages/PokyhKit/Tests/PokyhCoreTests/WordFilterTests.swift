import Testing
@testable import PokyhCore

// Expected values checked against Android's core/util/WordFilter.kt, which mirrors the web's.
struct WordFilterTests {
    @Test(arguments: ["Anna", "anna-maria", "Niccolò", "Maria", "mueller", "müller", "12345", ""])
    func ordinaryNamesPass(_ name: String) {
        #expect(!WordFilter.isOffensive(name))
    }

    // Words that only count on their own stay allowed inside a longer name.
    @Test(arguments: ["Hancock", "hancock", "Hitchcock", "Scunthorpe", "Sussex", "Annalena", "figaro", "Montenegro", "drape", "flag", "count"])
    func wholeWordsInsideNamesPass(_ name: String) {
        #expect(!WordFilter.isOffensive(name))
    }

    @Test(arguments: ["cock", "Cock", "shit", "shit head", "arsch", "nazi", "piss"])
    func wholeWordsOnTheirOwnAreCaught(_ name: String) {
        #expect(WordFilter.isOffensive(name))
    }

    @Test(arguments: ["Arschloch", "ficken", "fuck", "FUCK", "scheisse", "Hitler", "bastard", "cazzo"])
    func anywhereWordsAreCaught(_ name: String) {
        #expect(WordFilter.isOffensive(name))
        #expect(WordFilter.isOffensive("xx\(name)yy"))
    }

    @Test(arguments: ["sh1t", "c0ck", "4rsch", "n4z1", "h1tler", "b!tch", "b1tch", "w@nker", "sch3iss3"])
    func digitsAndSignsForLetters(_ name: String) {
        #expect(WordFilter.isOffensive(name))
    }

    @Test(arguments: ["fuuuck", "shiit", "merdaaa", "pusy", "cazo", "kkkk"])
    func repeatedLetters(_ name: String) {
        #expect(WordFilter.isOffensive(name))
    }

    @Test(arguments: ["f*ck", "sh*t", "sch**sse"])
    func starsStandForVowels(_ name: String) {
        #expect(WordFilter.isOffensive(name))
    }

    @Test(arguments: ["f***", "f****", "****", "*"])
    func starsAloneSayNothing(_ name: String) {
        #expect(!WordFilter.isOffensive(name))
    }

    @Test(arguments: ["a.r.s.c.h", "f i c k", "k k k"])
    func spelledOut(_ name: String) {
        #expect(WordFilter.isOffensive(name))
    }

    @Test func accentsAndSharpS() {
        #expect(WordFilter.isOffensive("fück"))
        #expect(WordFilter.isOffensive("scheiße"))
    }

    // Android flags these, since "kkk" squashes to "k". Nobody should get shouted at for that.
    @Test(arguments: ["k", "K", "kk", "anna k", "kevin.k", "Kevin", "k k"])
    func aLoneKIsNotAWord(_ name: String) {
        #expect(!WordFilter.isOffensive(name))
    }

    @Test func theFullWordStillCounts() {
        #expect(WordFilter.isOffensive("kkk"))
    }
}
