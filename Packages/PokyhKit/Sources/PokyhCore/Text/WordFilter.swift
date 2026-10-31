import Foundation

/// Whether a text contains a word the sign-in mascot must not say. The mascot greets you by the
/// name you type, so whatever is typed would come out of its mouth. Also caught when written with
/// digits or signs ("sh1t", "f*ck", "a.r.s.c.h") or with letters repeated ("fuuuck").
///
/// Same lists as the web's lib/word-filter.ts and Android. `anywhere` words count inside longer
/// words too; `asWord` words only on their own, so "Hancock" stays and "cock" does not.
public enum WordFilter {
    private static let anywhereWords = [
        // de
        "arschloch", "arschgeige", "hurensohn", "huresohn", "fotze", "ficken", "ficker", "wichser", "wixer", "schlampe",
        "missgeburt", "spasti", "schwuchtel", "nutte", "scheisse", "scheiss", "pisser", "vollidiot", "judensau", "kanake",
        "titten", "muschi", "pimmel", "drecksau",
        // en
        "fuck", "bitch", "whore", "asshole", "bastard", "motherf", "retard", "faggot", "nigger", "nigga", "wanker", "penis",
        "vagina", "pussy", "porno", "rapist", "hitler", "heilhitler", "siegheil",
        // it
        "cazzo", "minchia", "stronzo", "stronza", "puttana", "vaffanculo", "fanculo", "coglion", "merda", "frocio",
        "ricchione", "porcodio", "diocane", "mignotta", "zoccola", "bastardo", "bastarda", "pompino",
    ]
    private static let wholeWords = [
        "arsch", "fick", "hure", "spast", "mongo", "neger", "kacke",
        "nazi", "porn", "sex", "cunt", "cock", "shit", "fag", "slut", "twat", "rape", "kkk", "piss", "anal", "tits",
        "culo", "figa", "fica", "tette", "troia", "negro",
    ]

    // Digits and signs people put in place of letters.
    private static let leet: [Unicode.Scalar: Unicode.Scalar] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
        "@": "a", "$": "s", "!": "i", "|": "i", "€": "e",
    ]

    private static func isLetter(_ u: Unicode.Scalar) -> Bool { ("a"..."z").contains(u) }

    private static func normalise(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for u in text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            if (0x300...0x36F).contains(u.value) { continue }
            if u == "ß" {
                out.append("s")
                out.append("s")
            } else {
                out.append(leet[u] ?? u)
            }
        }
        return String(out)
    }

    private static func lettersOnly(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter(isLetter)))
    }

    /// Letters only, repeated letters once ("fuuuck" → "fuck").
    private static func squash(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars where isLetter(u) && out.last != u { out.append(u) }
        return String(out)
    }

    private static func splitWords(_ norm: String) -> [String] {
        norm.unicodeScalars.split { !isLetter($0) }.map { String(String.UnicodeScalarView($0)) }
    }

    private static let anywhere: [String] = {
        var seen = Set<String>()
        return anywhereWords.map { lettersOnly(normalise($0)) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }()
    private static let anywhereSquashed = anywhere.map(squash)
    private static let cleanWholeWords = wholeWords.map { lettersOnly(normalise($0)) }
    private static let squashedWholeWords = Set(cleanWholeWords.map(squash))

    // "kkk" squashes to "k", and a lone "k" isn't a word to be angry at: Kevin's first key press,
    // or "Anna K". Android and the web do flag that. So a squashed form needs 3 letters on both
    // sides: "kkkk" still counts, "k" and "kk" don't.
    private static let asWord = Set(cleanWholeWords + squashedWholeWords.filter { $0.unicodeScalars.count >= 3 })

    private static func isWholeWord(_ word: String) -> Bool {
        asWord.contains(word) || (word.unicodeScalars.count >= 3 && squashedWholeWords.contains(squash(word)))
    }

    /// Every way the stars of a text can stand for vowels ("f*ck" → "fack", "feck", …).
    private static func variants(_ text: String) -> [String] {
        guard let star = text.firstIndex(of: "*") else { return [text] }
        return ["a", "e", "i", "o", "u"].flatMap { vowel in
            variants(text.replacingCharacters(in: star...star, with: vowel))
        }
    }

    private static func check(_ text: String) -> Bool {
        let norm = normalise(text)
        let words = splitWords(norm)
        let plain = lettersOnly(norm)
        let all = squash(norm)
        for i in anywhere.indices where plain.contains(anywhere[i]) || all.contains(anywhereSquashed[i]) {
            return true
        }
        if words.contains(where: isWholeWord) { return true }
        // "a.r.s.c.h", "f i c k": single letters spelling a word.
        guard words.count > 1, words.allSatisfy({ $0.unicodeScalars.count == 1 }) else { return false }
        let spelled = words.joined()
        return isWholeWord(spelled) || anywhere.contains { spelled.contains($0) }
    }

    /// True when the text should not be said.
    public static func isOffensive(_ text: String) -> Bool {
        // "f*ck", "sch**sse": each star stands for a vowel, up to three of them.
        let stars = text.filter { $0 == "*" }.count
        if (1...3).contains(stars) { return variants(text).contains(where: check) }
        return check(stars > 0 ? text.replacingOccurrences(of: "*", with: "") : text)
    }
}
