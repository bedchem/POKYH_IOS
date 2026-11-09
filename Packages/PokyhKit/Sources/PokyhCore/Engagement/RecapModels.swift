import Foundation

// What /recaps answers. The backend decides who gets one and adds its POKYH figures; the WebUntis
// figures are worked out on the device (RecapFigures). Missing fields fall back to empty, an
// account with nothing in the period gets little more than `covered: null`. A field of the wrong
// type costs that field only, a broken entry only that entry: the feature must never vanish over it.

public struct Recap: Codable, Equatable, Identifiable, Sendable {
    /// The parts a recap can show, in the order the story tells them (services/recapRules.ts).
    public static let allSections = ["school", "absences", "grades", "exams", "classreg", "pokyh"]

    public var id: String
    public var title: String
    /// YYYY-MM-DD, both included.
    public var periodFrom: String
    public var periodTo: String
    public var endsAt: String?
    public var sections: [String]
    public var openedAt: String?
    public var finishedAt: String?

    public init(id: String, title: String, periodFrom: String, periodTo: String, endsAt: String? = nil,
                sections: [String] = [], openedAt: String? = nil, finishedAt: String? = nil) {
        self.id = id; self.title = title; self.periodFrom = periodFrom; self.periodTo = periodTo
        self.endsAt = endsAt; self.sections = Self.parts(sections); self.openedAt = openedAt; self.finishedAt = finishedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        periodFrom = try c.decode(String.self, forKey: .periodFrom)
        periodTo = try c.decode(String.self, forKey: .periodTo)
        endsAt = try? c.decodeIfPresent(String.self, forKey: .endsAt)
        // A list today; the stored form ("school,grades") is read as well.
        if let list = try? c.decodeIfPresent([String].self, forKey: .sections) {
            sections = Self.parts(list)
        } else {
            sections = Self.parts(((try? c.decodeIfPresent(String.self, forKey: .sections)) ?? "").components(separatedBy: ","))
        }
        openedAt = try? c.decodeIfPresent(String.self, forKey: .openedAt)
        finishedAt = try? c.decodeIfPresent(String.self, forKey: .finishedAt)
    }

    /// Like parseSections on the server: known parts in story order, none known means every part.
    static func parts(_ raw: [String]) -> [String] {
        let chosen = Set(raw.map { $0.trimmingCharacters(in: .whitespaces) })
        let known = allSections.filter(chosen.contains)
        return known.isEmpty ? allSections : known
    }

    /// Not watched to its end yet.
    public var isNew: Bool { finishedAt == nil }
    /// Anything to load from WebUntis at all.
    public var wantsUntis: Bool { sections.contains { $0 != "pokyh" } }
}

/// One entry of a list that may not decode; the others still do.
struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// A whole number however it came: 12, 12.0 or "12". Nil when it's none of these.
    func number(_ key: Key) -> Int? {
        if let n = try? decodeIfPresent(Int.self, forKey: key) { return n }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite {
            return d >= Double(Int.max) ? .max : d <= Double(Int.min) ? .min : Int(d)
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// A list of whole numbers; an entry that isn't one counts as 0.
    func numbers(_ key: Key) -> [Int]? {
        guard let list = try? decodeIfPresent([Lenient<Double>].self, forKey: key) else { return nil }
        return list.map { entry in
            guard let d = entry.value, d.isFinite else { return 0 }
            return d >= Double(Int.max) ? .max : d <= Double(Int.min) ? .min : Int(d)
        }
    }
}

public struct RecapList: Decodable, Sendable {
    public var recaps: [Recap]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Something else than a list is a broken answer and throws: the last good one stays.
        recaps = (try c.decodeIfPresent([Lenient<Recap>].self, forKey: .recaps) ?? []).compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey { case recaps }
}

public struct RecapSeen: Decodable, Equatable, Sendable {
    public var openedAt: String?
    public var finishedAt: String?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openedAt = try? c.decodeIfPresent(String.self, forKey: .openedAt)
        finishedAt = try? c.decodeIfPresent(String.self, forKey: .finishedAt)
    }

    private enum CodingKeys: String, CodingKey { case openedAt, finishedAt }
}

public struct RecapDetail: Decodable, Sendable {
    public var recap: Recap
    /// Null when the recap doesn't show the POKYH part; a broken one is left out like that too.
    public var pokyh: RecapPokyh?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recap = try c.decode(Recap.self, forKey: .recap)
        pokyh = (try? c.decodeIfPresent(RecapPokyh.self, forKey: .pokyh)) ?? nil
    }

    private enum CodingKeys: String, CodingKey { case recap, pokyh }
}

/// The account's POKYH figures for a recap's period (services/recaps.ts).
/// The story adds these up and multiplies them; a server's Int.max would trap there.
enum RecapCount {
    // Small enough for the watch's 32-bit Int, far above any real count.
    static func clamp(_ value: Int?) -> Int { min(max(0, value ?? 0), 100_000_000) }
}

public struct RecapPokyh: Decodable, Equatable, Sendable {
    public struct Span: Decodable, Equatable, Sendable {
        public var from: String
        public var to: String
        public init(from: String = "", to: String = "") {
            self.from = from
            self.to = to
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            from = (try? c.decodeIfPresent(String.self, forKey: .from)) ?? ""
            to = (try? c.decodeIfPresent(String.self, forKey: .to)) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case from, to }
    }

    public struct Totals: Decodable, Equatable, Sendable {
        public var activeDays = 0
        public var activeSeconds = 0
        public var longestStreak = 0

        public init(activeDays: Int = 0, activeSeconds: Int = 0, longestStreak: Int = 0) {
            self.activeDays = activeDays
            self.activeSeconds = activeSeconds
            self.longestStreak = longestStreak
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            activeDays = RecapCount.clamp(c.number(.activeDays))
            activeSeconds = RecapCount.clamp(c.number(.activeSeconds))
            longestStreak = RecapCount.clamp(c.number(.longestStreak))
        }

        private enum CodingKeys: String, CodingKey { case activeDays, activeSeconds, longestStreak }
    }

    public struct Created: Decodable, Equatable, Sendable {
        public var todosDone = 0
        public var reminders = 0
        public var comments = 0
        public var ratings = 0

        public init(todosDone: Int = 0, reminders: Int = 0, comments: Int = 0, ratings: Int = 0) {
            self.todosDone = todosDone
            self.reminders = reminders
            self.comments = comments
            self.ratings = ratings
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            todosDone = RecapCount.clamp(c.number(.todosDone))
            reminders = RecapCount.clamp(c.number(.reminders))
            comments = RecapCount.clamp(c.number(.comments))
            ratings = RecapCount.clamp(c.number(.ratings))
        }

        private enum CodingKeys: String, CodingKey { case todosDone, reminders, comments, ratings }
    }

    public struct DishName: Decodable, Equatable, Sendable {
        public var de = ""
        public var it = ""
        public var en = ""

        public init(de: String = "", it: String = "", en: String = "") {
            self.de = de
            self.it = it
            self.en = en
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            de = (try? c.decodeIfPresent(String.self, forKey: .de)) ?? ""
            it = (try? c.decodeIfPresent(String.self, forKey: .it)) ?? ""
            en = (try? c.decodeIfPresent(String.self, forKey: .en)) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case de, it, en }
    }

    public struct Dish: Decodable, Equatable, Sendable {
        public var name: DishName
        public init(name: DishName) { self.name = name }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let names = try? c.decode(DishName.self, forKey: .name) {
                name = names
            } else {
                name = DishName(de: try c.decode(String.self, forKey: .name))
            }
        }

        private enum CodingKeys: String, CodingKey { case name }
    }

    public struct Rank: Decodable, Equatable, Sendable {
        public var topPercent: Int
        public init(topPercent: Int) { self.topPercent = topPercent }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let top = c.number(.topPercent) else {
                throw DecodingError.dataCorruptedError(forKey: .topPercent, in: c, debugDescription: "no rank")
            }
            topPercent = top
        }

        private enum CodingKeys: String, CodingKey { case topPercent }
    }

    public var covered: Span?
    public var usageConsent = false
    public var totals: Totals?
    /// Active days per weekday, Monday first.
    public var weekdays: [Int] = []
    /// Foreground seconds by starting hour (with consent only).
    public var hours: [Int]?
    public var created: Created?
    public var favouriteDish: Dish?
    public var rank: Rank?

    public init(covered: Span? = nil, usageConsent: Bool = false, totals: Totals? = nil, weekdays: [Int] = [],
                hours: [Int]? = nil, created: Created? = nil, favouriteDish: Dish? = nil, rank: Rank? = nil) {
        self.covered = covered; self.usageConsent = usageConsent; self.totals = totals; self.weekdays = weekdays
        self.hours = hours; self.created = created; self.favouriteDish = favouriteDish; self.rank = rank
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        covered = (try? c.decodeIfPresent(Span.self, forKey: .covered)) ?? nil
        usageConsent = (try? c.decodeIfPresent(Bool.self, forKey: .usageConsent)) ?? false
        totals = (try? c.decodeIfPresent(Totals.self, forKey: .totals)) ?? nil
        weekdays = (c.numbers(.weekdays) ?? []).map(RecapCount.clamp)
        hours = c.numbers(.hours)?.map(RecapCount.clamp)
        created = (try? c.decodeIfPresent(Created.self, forKey: .created)) ?? nil
        favouriteDish = (try? c.decodeIfPresent(Dish.self, forKey: .favouriteDish)) ?? nil
        rank = (try? c.decodeIfPresent(Rank.self, forKey: .rank)) ?? nil
    }

    private enum CodingKeys: String, CodingKey {
        case covered, usageConsent, totals, weekdays, hours, created, favouriteDish, rank
    }
}
