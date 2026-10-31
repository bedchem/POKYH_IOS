import Foundation

/// An admin announcement as /popups/active hands it out. `html` is sanitised on the server.
public struct AnnouncementPopup: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let revision: Int
    public let title: String
    public let html: String
    public let showCount: Int
    public let startsAt: String?
    public let endsAt: String?
    public let slotMs: Int64?

    public init(id: String, revision: Int, title: String, html: String, showCount: Int,
                startsAt: String? = nil, endsAt: String? = nil, slotMs: Int64? = nil) {
        self.id = id; self.revision = revision; self.title = title; self.html = html
        self.showCount = showCount; self.startsAt = startsAt; self.endsAt = endsAt; self.slotMs = slotMs
    }

    /// An edited popup with "show again" gets a new revision, and so counts as unseen.
    public var key: String { "\(id):\(revision)" }
}

public struct AnnouncementPopupFeed: Decodable, Sendable {
    public var popups: [AnnouncementPopup]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        popups = try c.decodeIfPresent([AnnouncementPopup].self, forKey: .popups) ?? []
    }

    private enum CodingKeys: String, CodingKey { case popups }
}

public struct PopupSeenEntry: Codable, Equatable, Sendable {
    public var slot: Int
    public var count: Int
    public var at: Int64

    public init(slot: Int, count: Int, at: Int64) {
        self.slot = slot
        self.count = count
        self.at = at
    }
}

/// The backend only filters by time window; whether a popup is due on this device is decided here,
/// like on the website. The window is split into `showCount` equal slots and a popup shows at most
/// once per slot, so "7× in 7 days" is at most once a day. A "once" popup has no slots at all.
/// Missed slots aren't caught up and nothing shows after the window.
public enum PopupSchedule {
    /// Tab hopping and quick trips out of the app stay free.
    public static let recheckMs: Int64 = 10 * 60 * 1000
    /// Long enough for the sign-in check or a redirect to finish, so nothing flashes past.
    public static let settleMs: Int64 = 1500
    /// Every popup stays up at least this long before it can be closed or skipped.
    public static let minViewMs: Int64 = 3000
    /// Beyond this the dots stop being countable at a glance.
    public static let maxDots = 7
    private static let pruneAfterMs: Int64 = 365 * 24 * 60 * 60 * 1000

    public static func currentSlot(_ popup: AnnouncementPopup, now: Int64, clock: DayClock = DayClock()) -> Int? {
        if let end = clock.parse(popup.endsAt), end <= now { return nil }
        guard let slotMs = popup.slotMs, slotMs > 0, let start = clock.parse(popup.startsAt) else { return 0 }
        if now < start { return nil }
        return min(Int((now - start) / slotMs), popup.showCount - 1)
    }

    public static func isDue(_ popup: AnnouncementPopup, seen: [String: PopupSeenEntry], now: Int64, clock: DayClock = DayClock()) -> Bool {
        guard let slot = currentSlot(popup, now: now, clock: clock) else { return false }
        guard let entry = seen[popup.key] else { return true }
        return entry.count < popup.showCount && slot > entry.slot
    }

    /// Spends the current slot of every popup still due. One already recorded for this slot is left
    /// alone, so marking the one on screen again as the stack closes never costs it a showing.
    public static func withSeen(_ seen: [String: PopupSeenEntry], popups: [AnnouncementPopup], now: Int64, clock: DayClock = DayClock()) -> [String: PopupSeenEntry] {
        var next = seen.filter { now - $0.value.at < pruneAfterMs }
        for popup in popups where isDue(popup, seen: next, now: now, clock: clock) {
            guard let slot = currentSlot(popup, now: now, clock: clock) else { continue }
            next[popup.key] = PopupSeenEntry(slot: slot, count: (next[popup.key]?.count ?? 0) + 1, at: now)
        }
        return next
    }

    /// The content as a page, in the app's colors, mirroring the admin panel's phone preview.
    /// `fontSize` is the body size in points, so it follows Dynamic Type.
    public static func document(body: String, isDark: Bool, fontSize: Double = 15) -> String {
        let t = isDark
            ? (text: "#F2F2F4", link: "#BAB8F4", accent: "#6366F1", nested: "#232323", cardAlt: "#26262B", sep: "#232327",
               peri: "#24244C", periInk: "#BAB8F4", butter: "#473B16", butterInk: "#EBD79A", sage: "#23351E", sageInk: "#B4D0AD")
            : (text: "#1C1A17", link: "#4F46E5", accent: "#6366F1", nested: "#ECECEB", cardAlt: "#EEEAE3", sep: "#F0ECE5",
               peri: "#DEDDFB", periInk: "#4A46A6", butter: "#F7E7AC", butterInk: "#85641A", sage: "#D5E4D0", sageInk: "#4B6E45")
        let css = """
        html,body{margin:0;padding:0;background:transparent}
        body{font-family:-apple-system,system-ui,sans-serif;font-size:\(fontSize)px;line-height:1.55;color:\(t.text);overflow-wrap:anywhere;-webkit-text-size-adjust:100%}
        body>:first-child{margin-top:0}body>:last-child{margin-bottom:0}
        h1{font-size:1.47em;line-height:1.25;font-weight:800;letter-spacing:-.02em;margin:18px 0 8px}
        h2{font-size:1.27em;line-height:1.3;font-weight:700;letter-spacing:-.01em;margin:16px 0 6px}
        h3{font-size:1.07em;font-weight:600;margin:14px 0 4px}
        p{margin:0 0 10px}
        a{color:\(t.link);font-weight:600;text-decoration:none}
        img{max-width:100%;height:auto;border-radius:18px;display:block;margin:10px 0}
        blockquote{margin:10px 0;padding:10px 14px;border-radius:16px;background:\(t.butter);color:\(t.butterInk)}
        blockquote p{margin:0}
        code{background:\(t.sage);color:\(t.sageInk);padding:1px 6px;border-radius:7px;font-size:.88em}
        pre{background:\(t.nested);padding:12px 14px;border-radius:16px;overflow-x:auto}
        pre code{background:none;color:inherit;padding:0}
        ul,ol{padding-left:22px;margin:0 0 10px}
        li{margin:3px 0}
        li:has(>input[type=checkbox]){list-style:none;margin-left:-20px}
        input[type=checkbox]{accent-color:\(t.accent);margin:0 6px 0 0;vertical-align:-2px}
        hr{border:0;height:2px;border-radius:2px;background:\(t.sep);margin:14px 0}
        table{border-collapse:separate;border-spacing:0;width:100%;border-radius:16px;overflow:hidden;margin:10px 0;font-size:.93em}
        th{background:\(t.peri);color:\(t.periInk);font-weight:700;text-align:left;padding:8px 12px}
        td{background:\(t.nested);padding:8px 12px}
        tr:nth-child(even) td{background:\(t.cardAlt)}
        mark{color:#1C1A17;border-radius:5px;padding:0 4px}
        details{background:\(t.nested);border-radius:16px;padding:10px 14px;margin:10px 0}
        summary{font-weight:600}
        """
        return "<!doctype html><html><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            + "<meta http-equiv=\"Content-Security-Policy\" content=\"script-src 'none'\">"
            + "<style>\(css)</style></head><body>\(body)</body></html>"
    }
}

/// The popups due right now, shown as one stack: which is on screen, and which have been on screen
/// for the minimum time. Until then nothing closes or skips the current one. A popup counts as seen
/// only once it was up that long, so one that flashed past during a sign-in comes back.
public struct PopupStack: Equatable, Sendable {
    public private(set) var popups: [AnnouncementPopup]
    public private(set) var index: Int
    public private(set) var viewed: Set<String>

    public init(popups: [AnnouncementPopup] = [], index: Int = 0, viewed: Set<String> = []) {
        self.popups = popups
        self.index = index
        self.viewed = viewed
    }

    public var current: AnnouncementPopup? { popups.indices.contains(index) ? popups[index] : nil }
    public var isLast: Bool { index >= popups.count - 1 }
    /// How many are still waiting behind the card.
    public var waiting: Int { max(0, popups.count - 1 - index) }

    /// Not on screen long enough yet: no closing, no skipping ahead.
    public var locked: Bool { current.map { !viewed.contains($0.key) } ?? false }

    /// Back is always allowed; forward only to viewed popups, or to the next once unlocked.
    public func canReach(_ i: Int) -> Bool {
        guard popups.indices.contains(i), i != index else { return false }
        return i < index || viewed.contains(popups[i].key) || (i == index + 1 && !locked)
    }

    /// New ones join at the end; ones already in the stack stay put.
    public mutating func add(_ due: [AnnouncementPopup]) {
        let known = Set(popups.map(\.key))
        popups += due.filter { !known.contains($0.key) }
    }

    public mutating func markViewed(_ popup: AnnouncementPopup) {
        viewed.insert(popup.key)
    }

    public mutating func go(to i: Int) {
        if canReach(i) { index = i }
    }

    /// Steps on; true when that was the last one and the stack should close.
    public mutating func next() -> Bool {
        if locked { return false }
        if isLast { return true }
        go(to: index + 1)
        return false
    }

    public mutating func back() {
        go(to: index - 1)
    }
}
