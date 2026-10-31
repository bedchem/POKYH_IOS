import SwiftUI
import Combine
import PokyhCore
import PokyhDesign

/// What the bell shows, read from where the rest of the app reads it: the grades, the inbox, the
/// to-dos and the class's reminders, the streak from the account's activity. What was seen and
/// cleared is remembered per account on the device and with the account, so every device, web and
/// Android included, shows the same. One store for the whole app.
@MainActor
final class BellStore: ObservableObject {
    static let shared = BellStore()

    @Published private(set) var feed = BellFeed.Feed()
    @Published private(set) var fresh: Set<String> = []
    /// New since the bell was last opened; 0 until the account's marks are in.
    @Published private(set) var newCount = 0
    @Published private(set) var streak: BellStreakSummary?
    /// Nothing has arrived yet.
    @Published private(set) var loading = true
    @Published private(set) var now = DayClock.ms(Date())

    /// The inbox as last read, for opening a message Home doesn't list.
    private(set) var inbox: [MessagePreview] = []

    private weak var app: AppState?
    private var owner = ""
    private var input = BellFeed.Input()
    private var seen = BellFeed.SeenState()
    private var firstSeen = GradeFirstSeen()
    private var synced = false
    private var asked: [BellFeed.Source: Int64] = [:]
    private var refreshedAt: Int64 = 0

    // The account's copy of the marks: what it is known to hold, when it was last read.
    private var remoteSeen = Set<String>()
    private var remoteCleared = Set<String>()
    private var remoteRead = false
    private var pulledAt: Int64 = 0
    private var pushTask: Task<Void, Never>?

    /// How long each source rests before opening the bell reads it again.
    private static func rest(_ source: BellFeed.Source) -> Int64 {
        switch source {
        case .todos, .reminders: 30_000
        case .grades, .messages: 60_000
        case .streak: 600_000
        }
    }

    private static let resumeAfter: Int64 = 5 * 60_000
    private static let pullEvery: Int64 = 30_000

    private var clock: DayClock { DayClock() }
    private var currentMs: Int64 { DayClock.ms(Date()) }
    private var session: UserSession? { app?.session }

    /// Two schools can have the same login name.
    private static func owner(of s: UserSession) -> String {
        "\(s.schoolRef.loginName)|\(s.username.lowercased())"
    }

    /// Starts (or switches to) the signed-in account and reads what isn't read yet.
    func start(_ app: AppState) {
        self.app = app
        guard let s = app.session else { return }
        if refreshedAt == 0 { refreshedAt = currentMs }
        if Self.owner(of: s) != owner { adopt(s) }
        load(s, force: false)
        pull(s)
    }

    /// On opening the bell: everything old enough again, and the account's marks.
    func refresh(_ app: AppState) {
        self.app = app
        guard let s = app.session else { return }
        refreshedAt = currentMs
        if Self.owner(of: s) != owner { adopt(s) }
        load(s, force: true)
        pull(s)
    }

    /// Back in the app after a while: everything again.
    func resumed(_ app: AppState) {
        if currentMs - refreshedAt >= Self.resumeAfter { refresh(app) }
    }

    /// Times and what is due move with the clock.
    func tick() { publish() }

    /// Everything shown counts as seen.
    func seeAll() {
        let settled = BellFeed.settleSeen(seen, feed: feed, loaded: input.loaded, now: currentMs)
        save(BellFeed.markSeen(settled, feed: feed))
    }

    /// These items leave the feed for good, on every device of the account.
    func clear(_ keys: [String]) {
        save(BellFeed.clearKeys(seen, keys: keys))
    }

    /// A message opened in the app has nothing more to tell.
    func messageRead(_ id: Int) {
        input.messages = input.messages?.map { m in
            var m = m
            if m.id == id { m.read = true }
            return m
        }
        if let i = inbox.firstIndex(where: { $0.id == id }) { inbox[i].isRead = true }
        publish()
    }

    /// The unread count moved, so the inbox isn't what was read last. Read elsewhere in the app.
    func inboxChanged() {
        guard let s = session, s.hasUntis, !owner.isEmpty else { return }
        // Home counting the inbox at launch isn't news; it was only just read here too.
        if let at = asked[.messages], currentMs - at < 5_000 { return }
        asked[.messages] = currentMs
        Task { await loadMessages(s, who: owner) }
    }

    func message(_ id: Int) -> MessagePreview? { inbox.first { $0.id == id } }

    // ── Reading ─────────────────────────────────────────────────────────────

    private func adopt(_ s: UserSession) {
        owner = Self.owner(of: s)
        input = BellFeed.Input()
        inbox = []
        seen = DiskCache.load(BellFeed.SeenState.self, key: seenKey) ?? BellFeed.SeenState()
        firstSeen = DiskCache.load(GradeFirstSeen.self, key: firstSeenKey) ?? GradeFirstSeen()
        synced = false
        asked = [:]
        remoteSeen = []
        remoteCleared = []
        remoteRead = false
        pulledAt = 0
        streak = nil
        publish()
    }

    private func due(_ source: BellFeed.Source, force: Bool) -> Bool {
        let now = currentMs
        if let at = asked[source], !(force && now - at > Self.rest(source)) { return false }
        asked[source] = now
        return true
    }

    private func load(_ s: UserSession, force: Bool) {
        let who = owner
        if s.hasUntis {
            if due(.grades, force: force) { Task { await loadGrades(s, who: who) } }
            if due(.messages, force: force) { Task { await loadMessages(s, who: who) } }
        }
        guard let token = s.apiToken else { return }
        if due(.todos, force: force) { Task { await loadTodos(s, token: token, who: who) } }
        if !s.isParent, due(.reminders, force: force) { Task { await loadReminders(s, token: token, who: who) } }
        if due(.streak, force: force) { Task { await loadStreak(token: token, who: who) } }
    }

    private func loadGrades(_ s: UserSession, who: String) async {
        do {
            let subjects = try await UntisClient.shared.grades(year: nil, s)
            guard who == owner else { return }
            let ids = subjects.flatMap { $0.grades.map(\.id) }
            if firstSeen.observe(ids, now: currentMs) { DiskCache.save(firstSeen, key: firstSeenKey) }
            input.grades = subjects.flatMap { subject in
                subject.grades.map { g in
                    BellFeed.GradeIn(id: g.id, subject: subject.subjectName, lessonId: subject.lessonId, value: g.markDisplayValue,
                                     date: g.date, examType: g.examType, enteredAt: firstSeen.enteredAt(g.id))
                }
            }
            publish()
        } catch {
            if who == owner { asked[.grades] = nil }
        }
    }

    private func loadMessages(_ s: UserSession, who: String) async {
        do {
            let list = try await UntisClient.shared.messages(folder: .inbox, s)
            guard who == owner else { return }
            let clock = clock
            inbox = list
            input.messages = list.map {
                BellFeed.MessageIn(id: $0.id, subject: $0.subject, sender: $0.senderName, sent: clock.parse($0.sentDate) ?? 0, read: $0.isRead)
            }
            publish()
        } catch {
            guard who == owner else { return }
            asked[.messages] = nil
            // No backend account to wait for either: stop showing the skeleton.
            if s.apiToken == nil, input.messages == nil {
                input.messages = []
                publish()
            }
        }
    }

    private func loadTodos(_ s: UserSession, token: String, who: String) async {
        do {
            let list = try await BackendClient.shared.todos(username: s.username, token: token)
            guard who == owner else { return }
            let clock = clock
            input.todos = list.map { BellFeed.TodoIn(id: $0.id, title: $0.title, dueAt: clock.parse($0.dueAt), done: $0.done) }
            publish()
        } catch {
            if who == owner { asked[.todos] = nil }
        }
    }

    private func loadReminders(_ s: UserSession, token: String, who: String) async {
        do {
            var classId = s.classId
            if classId == nil { classId = try await BackendClient.shared.myClass(token: token)?.id }
            guard let classId else {
                if who == owner { asked[.reminders] = nil }
                return
            }
            let list = try await BackendClient.shared.reminders(classId: classId, token: token)
            guard who == owner else { return }
            let clock = clock
            input.reminders = list.map {
                BellFeed.ReminderIn(
                    id: $0.id, title: $0.title,
                    remindAt: clock.parse($0.remindAt) ?? 0,
                    createdAt: clock.parse($0.createdAt) ?? 0,
                    by: $0.createdByUsername.isEmpty ? $0.createdByName : $0.createdByUsername,
                    mine: (s.stableUid != nil && $0.createdBy == s.stableUid) || $0.createdByUsername == s.username
                )
            }
            publish()
        } catch {
            if who == owner { asked[.reminders] = nil }
        }
    }

    private func loadStreak(token: String, who: String) async {
        let activity = try? await BackendClient.shared.bellActivity(token: token)
        guard who == owner else { return }
        if let activity {
            let read = BellFeed.streak(from: activity, now: currentMs, clock: clock)
            input.streak = read.input
            streak = read.summary
        }
        input.streakRead = true
        publish()
    }

    /// Builds the feed from what is read; a source read for the first time settles what is old.
    private func publish() {
        let now = currentMs
        let clock = clock
        let built = BellFeed.withoutCleared(BellFeed.build(input, now: now, clock: clock), cleared: seen.cleared)
        let settled = BellFeed.settleSeen(seen, feed: built, loaded: input.loaded, now: now)
        if settled != seen { save(settled, republish: false) }
        let keys = BellFeed.freshKeys(built, seen: seen)
        feed = built
        fresh = keys
        newCount = synced ? keys.count : 0
        loading = input.loaded.isEmpty && session.map { $0.hasUntis || $0.apiToken != nil } ?? false
        self.now = now
    }

    private func save(_ next: BellFeed.SeenState, republish: Bool = true) {
        if next == seen { return }
        seen = next
        if !owner.isEmpty { DiskCache.save(next, key: seenKey) }
        if republish { publish() }
        schedulePush()
    }

    private var seenKey: String { "bell-seen-\(owner)" }
    private var firstSeenKey: String { "bell-grades-\(owner)" }

    // ── The account's marks ─────────────────────────────────────────────────

    private func pull(_ s: UserSession) {
        guard let token = s.apiToken else {
            synced = true
            publish()
            return
        }
        if currentMs - pulledAt < Self.pullEvery { return }
        pulledAt = currentMs
        let who = owner
        // The badge waits for the account's marks (at most 4 s), so what another device cleared
        // never flashes up as new.
        Task {
            try? await Task.sleep(for: .seconds(4))
            if who == owner, !synced {
                synced = true
                publish()
            }
        }
        Task {
            if let marks = try? await BackendClient.shared.bellMarks(token: token), who == owner {
                remoteSeen.formUnion(marks.seen)
                remoteCleared.formUnion(marks.cleared)
                remoteRead = true
                seen = BellFeed.mergeRemote(seen, seen: marks.seen, cleared: marks.cleared)
                DiskCache.save(seen, key: seenKey)
                schedulePush()
            }
            if who == owner {
                synced = true
                publish()
            }
        }
    }

    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, remoteRead, let s = session, let token = s.apiToken, Self.owner(of: s) == owner else { return }
            let marks = BellFeed.marksToPush(seen, remoteSeen: remoteSeen, remoteCleared: remoteCleared)
            if marks.isEmpty { return }
            guard (try? await BackendClient.shared.markBell(marks, token: token)) != nil else { return }
            remoteSeen.formUnion(marks.seen)
            remoteSeen.formUnion(marks.cleared)
            remoteCleared.formUnion(marks.cleared)
        }
    }
}

/// The bell beside the messages in the header: a count of what is new since it was last opened,
/// a short ring when that goes up. A sheet on the iPhone, a popover on the iPad.
struct BellToolbarButton: View {
    /// Where a row leads; the bell has closed by then.
    let onPick: (BellFeed.Target) -> Void

    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = BellStore.shared
    @Environment(\.strings) private var s
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var picked: BellFeed.Target?
    @State private var ring = 0

    var body: some View {
        Button {
            open = true
            store.refresh(app)
        } label: {
            Image(systemName: "bell")
                .symbolEffect(.wiggle, options: .nonRepeating, value: ring)
                .overlay(alignment: .topTrailing) {
                    UnreadBadge(store.newCount)
                        .fixedSize()
                        .offset(x: 11, y: -9)
                        .allowsHitTesting(false)
                }
        }
        .accessibilityLabel(store.newCount > 0 ? s.bell.labelNew(store.newCount) : s.bell.title)
        .popover(isPresented: $open) {
            BellPanel(store: store) { target in
                picked = target
                open = false
            }
            .frame(minWidth: 320, idealWidth: 400, idealHeight: 560)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: open) { _, isOpen in
            guard !isOpen else { return }
            store.seeAll()
            if let target = picked {
                picked = nil
                onPick(target)
            }
        }
        .onChange(of: store.newCount) { old, new in
            if new > old, !reduceMotion { ring += 1 }
        }
        .onChange(of: app.unreadMessages) { store.inboxChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.resumed(app) }
        }
        .task(id: app.session?.username) {
            store.start(app)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                store.tick()
            }
        }
    }
}

/// The streak on top, then what is due soon, then what happened lately. Opening it counts
/// everything as seen; what was new keeps its dot while it stays open.
private struct BellPanel: View {
    @ObservedObject var store: BellStore
    let onPick: (BellFeed.Target) -> Void

    @Environment(\.strings) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Set<String> = []

    private func isFresh(_ item: BellFeed.Item) -> Bool {
        shown.contains(item.key) || store.fresh.contains(item.key)
    }

    private func clear(_ keys: [String]) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: Motion.standard)) { store.clear(keys) }
    }

    var body: some View {
        let items = store.feed.all
        let newShown = items.filter(isFresh).count
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Text(s.bell.title)
                    .textStyle(.title3)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if newShown > 0 {
                    Text(s.bell.newCount(newShown))
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.sm)
                if !items.isEmpty {
                    Button { clear(items.map(\.key)) } label: {
                        Label(s.bell.clearAll, systemImage: "trash")
                            .textStyle(TextStyle.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.sm)

            List {
                if let streak = store.streak {
                    BellStreakCard(streak: streak).bellListRow(trailing: Spacing.md)
                }
                if store.loading {
                    ForEach(0..<3, id: \.self) { _ in BellRowSkeleton().bellListRow() }
                } else if items.isEmpty {
                    BellEmpty().bellListRow()
                } else {
                    ForEach(store.feed.current) { row($0) }
                    if !store.feed.current.isEmpty && !store.feed.recent.isEmpty {
                        Color.clear.frame(height: Spacing.xs).bellListRow()
                    }
                    ForEach(store.feed.recent) { row($0) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // The gap between what's due and what happened is smaller than a row.
            .environment(\.defaultMinListRowHeight, 0)
        }
        .onAppear {
            shown = store.fresh
            store.seeAll()
        }
    }

    private func row(_ item: BellFeed.Item) -> some View {
        BellRow(item: item, now: store.now, fresh: isFresh(item),
                onPick: { onPick(item.target) }, onClear: { clear([item.key]) })
            .bellListRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(s.bell.clear, systemImage: "trash", role: .destructive) { clear([item.key]) }
            }
    }
}

private extension View {
    /// The rows' own close button brings them closer to the edge than a card should go.
    func bellListRow(trailing: CGFloat = Spacing.xs) -> some View {
        listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.md, bottom: Spacing.xs, trailing: trailing))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// How many days in a row, the longest, and the last week as bars.
private struct BellStreakCard: View {
    let streak: BellStreakSummary
    @Environment(\.strings) private var s

    private var title: String {
        switch streak.days {
        case 0: s.bell.streakNone
        case 1: s.bell.streakOne
        default: s.bell.streakDays(streak.days)
        }
    }

    private var subtitle: String {
        !streak.todayActive && streak.days > 0 ? s.bell.streakKeep : s.bell.streakLongest(max(streak.longest, streak.days))
    }

    var body: some View {
        let tone = Decorative.butter
        HStack(spacing: Spacing.md) {
            Image(systemName: streak.days > 0 ? "flame.fill" : "flame")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tone.ink)
                .frame(width: 44, height: 44)
                .background(tone.fill, in: .pokyh(Radius.md))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .textStyle(TextStyle.headline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(Array(streak.week.enumerated()), id: \.offset) { i, active in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(active ? Brand.accent : Palette.textPrimary.opacity(0.1))
                        .frame(width: 9, height: i == streak.week.count - 1 ? 18 : 14)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .background(Palette.cardAlt, in: .pokyh(Radius.lg))
        .accessibilityElement(children: .combine)
    }
}

private struct BellRow: View {
    let item: BellFeed.Item
    let now: Int64
    let fresh: Bool
    let onPick: () -> Void
    let onClear: () -> Void

    @Environment(\.strings) private var s

    private var tone: Tone {
        switch item.kind {
        case .grade:
            let v = item.value ?? 0
            return v >= 6.4 ? Decorative.sage : v >= 6 ? Decorative.butter : Decorative.blush
        case .message: return Decorative.periwinkle
        case .reminder, .reminderSoon: return Decorative.blush
        case .todo: return Decorative.sage
        case .streak: return Decorative.butter
        case .streakLost: return Tone(fill: Palette.cardAlt, ink: Palette.textTertiary)
        }
    }

    private var symbol: String? {
        switch item.kind {
        case .grade: nil
        case .message: "envelope.fill"
        case .reminder: "bell.badge.fill"
        case .reminderSoon: "alarm.fill"
        case .todo: "checklist"
        case .streak: "flame.fill"
        case .streakLost: "flame"
        }
    }

    var body: some View {
        let text = BellFeed.rowText(item, now: now, strings: s)
        let tone = tone
        HStack(spacing: Spacing.xs) {
            Button(action: onPick) {
                HStack(spacing: Spacing.md) {
                    Group {
                        if let symbol {
                            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                        } else {
                            Text(Fmt.num(item.value ?? 0))
                                .textStyle(TextStyle.footnote.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(tone.ink)
                    .frame(width: 40, height: 40)
                    .background(tone.fill, in: .pokyh(Radius.md))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(text.title)
                            .textStyle(fresh ? TextStyle.callout.weight(.semibold) : .callout)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Text(text.subtitle)
                            .textStyle(.caption)
                            .foregroundStyle(item.overdue ? Palette.dangerText : Palette.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if fresh {
                        Circle().fill(Brand.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 36, height: 36)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.bell.clear)
        }
    }
}

private struct BellRowSkeleton: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            SkeletonBlock(height: 40, radius: Radius.md).frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(height: 12).frame(width: 180)
                SkeletonBlock(height: 10).frame(width: 110)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct BellEmpty: View {
    @Environment(\.strings) private var s

    var body: some View {
        let tone = Decorative.periwinkle
        VStack(spacing: Spacing.sm) {
            Image(systemName: "bell")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tone.ink)
                .frame(width: 72, height: 72)
                .background(tone.fill, in: .pokyh(Radius.xl))
                .padding(.bottom, Spacing.xs)
                .accessibilityHidden(true)
            Text(s.bell.emptyTitle)
                .textStyle(.headline)
                .foregroundStyle(Palette.textPrimary)
            Text(s.bell.emptyText)
                .textStyle(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}
