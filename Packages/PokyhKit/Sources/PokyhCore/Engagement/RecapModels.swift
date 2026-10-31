import Foundation

// What /recaps answers. The backend decides who gets one and adds its POKYH figures; the WebUntis
// figures are worked out on the device (RecapFigures). Missing fields fall back to empty, an
// account with nothing in the period gets little more than `covered: null`.

public struct Recap: Codable, Equatable, Identifiable, Sendable {
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
        self.endsAt = endsAt; self.sections = sections; self.openedAt = openedAt; self.finishedAt = finishedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        periodFrom = try c.decode(String.self, forKey: .periodFrom)
        periodTo = try c.decode(String.self, forKey: .periodTo)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt)
        sections = try c.decodeIfPresent([String].self, forKey: .sections) ?? []
        openedAt = try c.decodeIfPresent(String.self, forKey: .openedAt)
        finishedAt = try c.decodeIfPresent(String.self, forKey: .finishedAt)
    }

    /// Not watched to its end yet.
    public var isNew: Bool { finishedAt == nil }
    /// Anything to load from WebUntis at all.
    public var wantsUntis: Bool { sections.contains { $0 != "pokyh" } }
}

public struct RecapList: Decodable, Sendable {
    public var recaps: [Recap]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recaps = try c.decodeIfPresent([Recap].self, forKey: .recaps) ?? []
    }

    private enum CodingKeys: String, CodingKey { case recaps }
}

public struct RecapSeen: Decodable, Equatable, Sendable {
    public var openedAt: String?
    public var finishedAt: String?
}

public struct RecapDetail: Decodable, Sendable {
    public var recap: Recap
    public var pokyh: RecapPokyh?
}

/// The account's POKYH figures for a recap's period (services/recaps.ts).
public struct RecapPokyh: Decodable, Equatable, Sendable {
    public struct Span: Decodable, Equatable, Sendable {
        public var from: String
        public var to: String
        public init(from: String = "", to: String = "") {
            self.from = from
            self.to = to
        }
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
            activeDays = try c.decodeIfPresent(Int.self, forKey: .activeDays) ?? 0
            activeSeconds = try c.decodeIfPresent(Int.self, forKey: .activeSeconds) ?? 0
            longestStreak = try c.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
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
            todosDone = try c.decodeIfPresent(Int.self, forKey: .todosDone) ?? 0
            reminders = try c.decodeIfPresent(Int.self, forKey: .reminders) ?? 0
            comments = try c.decodeIfPresent(Int.self, forKey: .comments) ?? 0
            ratings = try c.decodeIfPresent(Int.self, forKey: .ratings) ?? 0
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
            de = try c.decodeIfPresent(String.self, forKey: .de) ?? ""
            it = try c.decodeIfPresent(String.self, forKey: .it) ?? ""
            en = try c.decodeIfPresent(String.self, forKey: .en) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case de, it, en }
    }

    public struct Dish: Decodable, Equatable, Sendable {
        public var name: DishName
        public init(name: DishName) { self.name = name }
    }

    public struct Rank: Decodable, Equatable, Sendable {
        public var topPercent: Int
        public init(topPercent: Int) { self.topPercent = topPercent }
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
        covered = try c.decodeIfPresent(Span.self, forKey: .covered)
        usageConsent = try c.decodeIfPresent(Bool.self, forKey: .usageConsent) ?? false
        totals = try c.decodeIfPresent(Totals.self, forKey: .totals)
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        hours = try c.decodeIfPresent([Int].self, forKey: .hours)
        created = try c.decodeIfPresent(Created.self, forKey: .created)
        favouriteDish = try c.decodeIfPresent(Dish.self, forKey: .favouriteDish)
        rank = try c.decodeIfPresent(Rank.self, forKey: .rank)
    }

    private enum CodingKeys: String, CodingKey {
        case covered, usageConsent, totals, weekdays, hours, created, favouriteDish, rank
    }
}
