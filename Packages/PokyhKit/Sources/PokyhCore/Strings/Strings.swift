import Foundation

/// The app's languages, the web frontend's active locales.
public enum Lang: String, CaseIterable, Sendable, Codable {
    case de, it, en

    public var nativeName: String {
        switch self {
        case .de: "Deutsch"
        case .it: "Italiano"
        case .en: "English"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// The phone's language if it's one of ours, German otherwise.
    public static func system(preferred: [String] = Locale.preferredLanguages) -> Lang {
        for identifier in preferred {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
            if let code, let lang = Lang(rawValue: code) { return lang }
        }
        return .de
    }
}

/// Every text of the app in one language, one area per part of the app. Ported 1:1 from the
/// Android tables so wording, plurals and the in-app language choice behave the same.
public struct Strings: Sendable {
    public let lang: Lang
    public let common: CommonStrings
    public let states: StateStrings
    public let grades: GradesStrings
    public let login: LoginStrings
    public let absences: AbsencesStrings
    public let profile: ProfileStrings
    public let settings: SettingsStrings
    public let account: AccountStrings
    public let bell: BellStrings
    public let nav: NavStrings
    public let home: HomeStrings
    public let timetable: TimetableStrings
    public let mensa: MensaStrings
    public let errors: ErrorStrings
    public let system: SystemStrings
    public let tasks: TasksStrings
    public let messages: MessagesStrings
    public let school: SchoolStrings
    public let search: SearchStrings
    public let recap: RecapStrings
    public let watch: WatchStrings

    public static func of(_ lang: Lang) -> Strings {
        switch lang {
        case .de: de
        case .it: it
        case .en: en
        }
    }

    static let de = Strings(
        lang: .de, common: .de, states: .de, grades: .de, login: .de, absences: .de, profile: .de,
        settings: .de, account: .de, bell: .de, nav: .de, home: .de, timetable: .de, mensa: .de,
        errors: .de, system: .de, tasks: .de, messages: .de, school: .de, search: .de, recap: .de, watch: .de
    )

    static let it = Strings(
        lang: .it, common: .it, states: .it, grades: .it, login: .it, absences: .it, profile: .it,
        settings: .it, account: .it, bell: .it, nav: .it, home: .it, timetable: .it, mensa: .it,
        errors: .it, system: .it, tasks: .it, messages: .it, school: .it, search: .it, recap: .it, watch: .it
    )

    static let en = Strings(
        lang: .en, common: .en, states: .en, grades: .en, login: .en, absences: .en, profile: .en,
        settings: .en, account: .en, bell: .en, nav: .en, home: .en, timetable: .en, mensa: .en,
        errors: .en, system: .en, tasks: .en, messages: .en, school: .en, search: .en, recap: .en, watch: .en
    )
}

/// Which language the app speaks: the phone's, unless one was picked in the settings.
/// Stored in the shared defaults so widgets and notifications follow the same choice.
public enum LanguageChoice {
    static let key = "pokyh_language"

    public static func chosen(in defaults: UserDefaults) -> Lang? {
        defaults.string(forKey: key).flatMap(Lang.init(rawValue:))
    }

    public static func choose(_ lang: Lang?, in defaults: UserDefaults) {
        if let lang {
            defaults.set(lang.rawValue, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public static func current(in defaults: UserDefaults) -> Lang {
        chosen(in: defaults) ?? .system()
    }
}
