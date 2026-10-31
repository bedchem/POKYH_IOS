import Foundation
import PokyhCore

extension Config.Routes {
    /// The bell, recaps and announcement popups.
    enum Engagement {
        static let bellMarks = "/users/me/bell"
        static let activity = "/users/me/activity"
        static let recaps = "/recaps"
        static func recap(_ id: String) -> String { "/recaps/\(id.urlEncoded)" }
        static func recapView(_ id: String) -> String { "/recaps/\(id.urlEncoded)/view" }
        static let popupsActive = "/popups/active?platform=ios&audience=user"
        // WebUntis, for the recap's own figures.
        static let absenceTimes = "/api/classreg/absencetimes/student"
    }
}

extension BackendClient {
    // ── The bell ────────────────────────────────────────────────────────────

    /// Which of the bell's items the account has seen and cleared, on any device.
    func bellMarks(token: String) async throws -> BellMarks {
        let data = try await request(Config.Routes.Engagement.bellMarks, token: token)
        return try JSONDecoder().decode(BellMarks.self, from: data)
    }

    /// Marks more of them. Identifiers only; nothing is ever unmarked.
    func markBell(_ marks: BellMarks, token: String) async throws {
        _ = try await request(Config.Routes.Engagement.bellMarks, method: "POST", token: token,
                              body: ["seen": marks.seen, "cleared": marks.cleared])
    }

    /// The account's activity, for the streak.
    func bellActivity(token: String) async throws -> BellActivity {
        let data = try await request(Config.Routes.Engagement.activity, token: token)
        return try JSONDecoder().decode(BellActivity.self, from: data)
    }

    // ── Recaps ──────────────────────────────────────────────────────────────

    /// The recaps the account may open now, the newest period first.
    func recaps(token: String) async throws -> [Recap] {
        let data = try await request(Config.Routes.Engagement.recaps, token: token)
        return try JSONDecoder().decode(RecapList.self, from: data).recaps
    }

    /// One recap with the account's POKYH figures for its period.
    func recap(id: String, token: String) async throws -> RecapDetail {
        let data = try await request(Config.Routes.Engagement.recap(id), token: token)
        return try JSONDecoder().decode(RecapDetail.self, from: data)
    }

    /// Notes that the story was opened and, with `finished`, watched to its end, on every device.
    func markRecapView(id: String, finished: Bool, token: String) async throws -> RecapSeen {
        let data = try await request(Config.Routes.Engagement.recapView(id), method: "POST", token: token, body: ["finished": finished])
        return try JSONDecoder().decode(RecapSeen.self, from: data)
    }

    // ── Popups ──────────────────────────────────────────────────────────────

    /// What's inside its window right now. With a session the backend adds the ones meant for this
    /// account or its class; whether this device already saw one is decided here (PopupSchedule).
    func activePopups(token: String?) async throws -> [AnnouncementPopup] {
        let data = try await request(Config.Routes.Engagement.popupsActive, token: token)
        return try JSONDecoder().decode(AnnouncementPopupFeed.self, from: data).popups
    }
}
