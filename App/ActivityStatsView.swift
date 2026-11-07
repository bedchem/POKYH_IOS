import SwiftUI
import Charts
import PokyhCore
import PokyhDesign

// The profile's activity and the statistics behind it. Everything comes from /users/me/activity,
// which only shows what the POKYH server already keeps; time in POKYH and the most used pages
// need the personal usage statistics.

@Observable
final class ActivityModel {
    enum Load {
        case loading, unavailable, failed
        case loaded(AccountActivity)
    }

    private(set) var load = Load.loading
    /// Laid out once per answer, not on every redraw of the profile.
    private(set) var grid: ActivityGridLayout?
    let token: String?
    /// One per signed-in account, kept between visits: the profile opens with the last answer at
    /// once and refreshes underneath.
    private static var current: ActivityModel?

    var activity: AccountActivity? {
        if case .loaded(let activity) = load { activity } else { nil }
    }

    private init(token: String?) {
        self.token = token
    }

    static func forToken(_ token: String?) -> ActivityModel {
        if let current, current.token == token { return current }
        let fresh = ActivityModel(token: token)
        current = fresh
        return fresh
    }

    /// Coming back from the settings refreshes what's showing without taking it away.
    func reload(token: String?) async {
        guard let token, !token.isEmpty else {
            load = .unavailable
            return
        }
        if activity == nil { load = .loading }
        do {
            let fresh = try await BackendClient.shared.accountActivity(token: token)
            // The same answer again would only redraw the page while the sheet is still sliding in.
            guard !Task.isCancelled, fresh != activity else { return }
            grid = ActivityGridLayout(days: fresh.days)
            load = .loaded(fresh)
        } catch {
            guard !Task.isCancelled, activity == nil else { return }
            load = .failed
        }
    }
}

private enum ActivityType {
    static let figureLabel = TextStyle(13.5, 18, .semibold, relativeTo: .footnote)
    static let noticeTitle = TextStyle(16.5, 22, .bold, tracking: -0.005, relativeTo: .body)
    static let gridLabel = TextStyle(12, 16, .semibold, relativeTo: .caption)
}

// ── On the profile ───────────────────────────────────────────────────────────

/// Four figures, the grid of days and the way to the statistics. Gone without a POKYH account.
struct ActivitySection: View {
    let openSettings: () -> Void
    @Environment(AppState.self) var app
    @Environment(\.strings) private var s
    private var model: ActivityModel { .forToken(app.session?.apiToken) }
    @State private var showStats = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .unavailable = model.load {
                EmptyView()
            } else {
                SettingsGroup(s.profile.activity) { content }
                    .padding(.bottom, groupGap)
            }
        }
        .task(id: app.session?.apiToken) { await model.reload(token: app.session?.apiToken) }
        .navigationDestination(isPresented: $showStats) { StatsView(model: model) }
    }

    @ViewBuilder private var content: some View {
        if case .failed = model.load {
            PokyhCard {
                ErrorStateView(message: s.profile.activityFailed) {
                    Task { await model.reload(token: app.session?.apiToken) }
                }
            }
        } else {
            let activity = model.activity
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let activity, !activity.usageConsent {
                    StatsOffNotice(openSettings: openSettings)
                }
                FigureRow(first: .init(s.profile.daysOnline, activity.map { "\($0.totals.activeDays)" }),
                          second: .init(s.profile.logins, activity.map { "\($0.totals.logins)" }))
                FigureRow(first: .init(s.profile.currentStreak, activity.map { s.common.days($0.totals.currentStreak) }),
                          second: .init(s.profile.longestStreak, activity.map { s.common.days($0.totals.longestStreak) }))
                PokyhCard {
                    if let grid = model.grid {
                        ActivityGridView(layout: grid)
                        GridLegend().padding(.top, Spacing.lg)
                    } else {
                        SkeletonBlock(height: 170, radius: Radius.sm)
                    }
                }
                if activity != nil {
                    Button { showStats = true } label: {
                        HStack(spacing: Spacing.sm) {
                            Text(s.profile.moreStats)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                        }
                    }
                    .buttonStyle(.secondary(compact: true))
                    .padding(.top, Spacing.sm)
                }
            }
        }
    }
}

private struct Figure {
    let label: String
    let value: String?
    var sub: String?

    init(_ label: String, _ value: String?, sub: String? = nil) {
        self.label = label
        self.value = value
        self.sub = sub
    }
}

/// Two tiles of the same height, whatever each has to say.
private struct FigureRow: View {
    let first: Figure
    let second: Figure

    var body: some View {
        HStack(spacing: Spacing.md) {
            FigureTile(figure: first)
            FigureTile(figure: second)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FigureTile: View {
    let figure: Figure

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(figure.label)
                .textStyle(ActivityType.figureLabel)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let value = figure.value {
                Text(value)
                    .textStyle(.statMedium)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                SkeletonBlock(height: 26).frame(width: 56)
            }
            if let sub = figure.sub {
                Text(sub)
                    .textStyle(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(radius: Radius.lg)
        .accessibilityElement(children: .combine)
    }
}

/// Personal statistics are off: where they go on.
private struct StatsOffNotice: View {
    let openSettings: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        let tone = Decorative.butter
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(s.profile.statsOffTitle)
                .textStyle(ActivityType.noticeTitle)
                .foregroundStyle(tone.ink)
            Button(s.account.consentLink, action: openSettings)
                .buttonStyle(.plain)
                .textStyle(.footnote.weight(.bold))
                .foregroundStyle(tone.ink)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 36)
                .background(tone.ink.opacity(0.14), in: .capsule)
                .contentShape(.capsule)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.fill, in: .pokyh(Radius.xl))
    }
}

// ── The grid of days ─────────────────────────────────────────────────────────

private enum ActivityShade {
    /// One hue, stronger the more was going on.
    static func color(_ level: Int) -> Color {
        switch level {
        case 1: Brand.accent.opacity(0.28)
        case 2: Brand.accent.opacity(0.48)
        case 3: Brand.accent.opacity(0.72)
        case 4: Brand.accent
        default: Palette.textPrimary.opacity(0.07)
        }
    }
}

private struct GridLegend: View {
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: 6) {
            Text(s.account.less).padding(.trailing, Spacing.xs)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ActivityShade.color(level))
                    .frame(width: 14, height: 14)
            }
            Text(s.account.more).padding(.leading, Spacing.xs)
        }
        .textStyle(ActivityType.gridLabel)
        .foregroundStyle(Palette.textTertiary)
        .accessibilityHidden(true)
    }
}

/// One column per week, Monday on top, the stronger the indigo the more was going on and today
/// ringed. Tap a day for its figures. A whole school year draws smaller squares and opens at today.
private struct ActivityGridView: View {
    let layout: ActivityGridLayout
    @Environment(\.strings) private var s
    @State private var picked: Int?
    @State private var width: CGFloat = 0

    /// Room for today's ring.
    private let inset: CGFloat = 4

    /// A short window fits as a whole, with no week cut in half at the edge.
    private var cell: CGFloat {
        if layout.isDense { return 13 }
        guard width > 0 else { return 20 }
        let weeks = CGFloat(layout.weeks.count)
        return min(20, max(13, ((width - inset * 2 - gap * (weeks - 1)) / weeks).rounded(.down)))
    }
    private var gap: CGFloat { layout.isDense ? 3 : 4 }
    private var radius: CGFloat { (cell * 0.3).rounded() }
    private var pitch: CGFloat { cell + gap }

    var body: some View {
        if !layout.weeks.isEmpty {
            HStack(alignment: .top, spacing: Spacing.sm) {
                dayLabels
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        months
                        weeks
                    }
                    .padding(inset)
                }
                .defaultScrollAnchor(.trailing, for: .initialOffset)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                // A year scrolls: the weeks before fade out instead of ending in half a square.
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: layout.isDense ? Spacing.lg : 0)
                        Color.black
                    }
                }
            }
        }
    }

    /// Mon, Wed, Fri stay in place while the weeks scroll beside them.
    private var dayLabels: some View {
        VStack(alignment: .leading, spacing: gap) {
            Color.clear.frame(width: 1, height: 16 + Spacing.sm - gap)
            ForEach(0..<7, id: \.self) { row in
                Text(row < 5 && row.isMultiple(of: 2) ? label(row) : "")
                    .textStyle(ActivityType.gridLabel)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: cell)
            }
        }
        .padding(.top, inset)
        .accessibilityHidden(true)
    }

    private func label(_ row: Int) -> String {
        let shorts = s.common.weekdaysShort
        guard shorts.indices.contains(row) else { return "" }
        return shorts[row].replacingOccurrences(of: ".", with: "")
    }

    private var months: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: pitch * CGFloat(layout.weeks.count), height: 16)
            ForEach(Array(layout.months.enumerated()), id: \.offset) { _, start in
                Text(monthName(start.month))
                    .textStyle(ActivityType.gridLabel)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: pitch * CGFloat(start.column))
            }
        }
        .accessibilityHidden(true)
    }

    private func monthName(_ month: Int) -> String {
        let names = s.common.monthsShort
        return names.indices.contains(month - 1) ? names[month - 1] : ""
    }

    /// One drawing for the whole window: a year as hundreds of buttons, each with its own popover,
    /// was what made the profile slow to slide in.
    private var weeks: some View {
        let columns = CGFloat(layout.weeks.count)
        let size = CGSize(width: pitch * columns - gap + inset * 2, height: pitch * 7 - gap + inset * 2)
        return Canvas { context, _ in
            let ring = Palette.textPrimary.opacity(0.35)
            for (column, week) in layout.weeks.enumerated() {
                for (row, entry) in week.enumerated() {
                    guard let entry else { continue }
                    let rect = frame(column: column, row: row)
                    context.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                                 with: .color(ActivityShade.color(entry.level)))
                    if entry.isLast {
                        let around = Path(roundedRect: rect.insetBy(dx: -2.25, dy: -2.25), cornerRadius: radius + 2.25, style: .continuous)
                        context.stroke(around, with: .color(ring), lineWidth: 1.5)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        // The ring of the last day reaches past the squares; the stack keeps its own margin.
        .padding(-inset)
        .contentShape(.rect)
        .onTapGesture { point in
            let slot = self.slot(at: point)
            picked = slot == picked ? nil : slot
        }
        .overlay(alignment: .topLeading) {
            if let picked, let entry = entry(picked) {
                let rect = frame(column: picked / 7, row: picked % 7)
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .padding(.leading, rect.minX - inset)
                    .padding(.top, rect.minY - inset)
                    .popover(isPresented: Binding(get: { self.picked != nil }, set: { if !$0 { self.picked = nil } }),
                             attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        Text(ActivityGridLayout.describe(entry, s))
                            .textStyle(ActivityType.gridLabel)
                            .foregroundStyle(Palette.textPrimary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(s.profile.activity)
        .accessibilityValue(entry(picked ?? lastSlot).map { ActivityGridLayout.describe($0, s) } ?? "")
        .accessibilityAdjustableAction { direction in
            let slots = filledSlots
            guard let current = picked ?? lastSlot, let here = slots.firstIndex(of: current) else { return }
            let next = direction == .increment ? here + 1 : here - 1
            if slots.indices.contains(next) { picked = slots[next] }
        }
    }

    /// Where a square sits in the drawing, the margin for the ring included.
    private func frame(column: Int, row: Int) -> CGRect {
        CGRect(x: inset + CGFloat(column) * pitch, y: inset + CGFloat(row) * pitch, width: cell, height: cell)
    }

    private func slot(at point: CGPoint) -> Int? {
        let column = Int(((point.x - inset) / pitch).rounded(.down))
        let row = Int(((point.y - inset) / pitch).rounded(.down))
        guard (0..<7).contains(row), layout.weeks.indices.contains(column) else { return nil }
        let slot = column * 7 + row
        return entry(slot) == nil ? nil : slot
    }

    private func entry(_ slot: Int?) -> ActivityGridLayout.Cell? {
        guard let slot, slot >= 0, layout.weeks.indices.contains(slot / 7) else { return nil }
        let week = layout.weeks[slot / 7]
        return week.indices.contains(slot % 7) ? week[slot % 7] : nil
    }

    private var filledSlots: [Int] {
        layout.weeks.enumerated().flatMap { column, week in
            week.indices.compactMap { row in week[row] == nil ? nil : column * 7 + row }
        }
    }

    private var lastSlot: Int? { filledSlots.last }
}

// ── The statistics ───────────────────────────────────────────────────────────

/// How POKYH is used, shown to the account itself only.
struct StatsView: View {
    let model: ActivityModel
    @Environment(AppState.self) var app
    @Environment(\.strings) private var s
    @State private var showSettings = false

    var body: some View {
        Group {
            switch model.load {
            case .loaded(let activity):
                ScrollView { content(activity) }
            case .failed:
                ErrorStateView(message: s.profile.activityFailed) {
                    Task { await model.reload(token: app.session?.apiToken) }
                }
            case .unavailable:
                ErrorStateView(message: s.profile.statsNeedAccount)
            case .loading:
                LoadingStateView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(s.profile.statsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
        .task { await model.reload(token: app.session?.apiToken) }
        .refreshable { await model.reload(token: app.session?.apiToken) }
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
    }

    private func content(_ a: AccountActivity) -> some View {
        let consent = a.usageConsent
        return VStack(alignment: .leading, spacing: Spacing.section) {
            if !consent {
                StatsOffNotice { showSettings = true }.fadeIn()
            }
            VStack(spacing: Spacing.md) {
                FigureRow(first: .init(s.profile.daysOnline, "\(a.totals.activeDays)", sub: s.profile.currentStreakIs(s.common.days(a.totals.currentStreak))),
                          second: .init(s.profile.logins, "\(a.totals.logins)", sub: s.profile.longestStreakIs(s.common.days(a.totals.longestStreak))))
                if consent {
                    FigureRow(first: .init(s.profile.usageTime, AccountActivity.duration(a.totals.activeSeconds), sub: s.profile.visits(a.totals.visits)),
                              second: .init(s.profile.perDay, a.averageSeconds.map(AccountActivity.duration) ?? "–", sub: s.profile.screensOpened(a.totals.screens)))
                }
            }
            .fadeIn(delay: 0.02)

            if consent, !a.hourColumns.isEmpty {
                PokyhSection(s.profile.whenOnline) {
                    PokyhCard {
                        ColumnChart(columns: a.hourColumns, axis: stride(from: 6, through: 21, by: 3).map(String.init)) {
                            AccountActivity.duration($0)
                        }
                    }
                }
                .fadeIn(delay: 0.04)
            }

            let weekdays = a.weekdayColumns(s)
            if !weekdays.isEmpty {
                PokyhSection(s.profile.weekdays) {
                    PokyhCard {
                        ColumnChart(columns: weekdays, axis: weekdays.map(\.label)) { s.common.days($0) }
                    }
                }
                .fadeIn(delay: 0.06)
            }

            PokyhSection(s.profile.devices) {
                PokyhCard {
                    let p = a.platforms
                    BarRows(rows: [(s.profile.phone, p.phone), (s.profile.computer, p.desktop), (s.profile.app, p.app), (s.profile.browser, p.web)]) {
                        s.common.days($0)
                    }
                }
            }
            .fadeIn(delay: 0.08)

            if consent, !a.pages.isEmpty {
                PokyhSection(s.profile.topPages) {
                    PokyhCard {
                        BarRows(rows: a.pages.map { (AccountActivity.pageName($0.page, s), $0.views) }) { s.profile.views($0) }
                    }
                }
                .fadeIn(delay: 0.1)
            }

            PokyhSection(s.profile.created) {
                PokyhCard { created(a) }
            }
            .fadeIn(delay: 0.12)
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xxxl)
    }

    private func created(_ a: AccountActivity) -> some View {
        let c = a.created
        var items = [(s.profile.todosDone, "\(c.todosDone)"), (s.profile.todosOpen, "\(c.todosOpen)"),
                     (s.profile.reminders, "\(c.reminders)"), (s.profile.comments, "\(c.comments)"),
                     (s.profile.ratings, "\(c.ratings)")]
        if let since = a.memberSinceText(s) { items.append((s.profile.memberSince, since)) }
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                         alignment: .leading, spacing: Spacing.lg) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    EyebrowLabel(item.0)
                    Text(item.1)
                        .textStyle(.statSmall)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Upright bars, the tallest solid. Touch one for its figure; the axis has no numbers to read.
private struct ColumnChart: View {
    let columns: [ActivityColumn]
    let axis: [String]
    let valueText: (Int) -> String
    @State private var picked: String?

    var body: some View {
        Chart(columns) { column in
            BarMark(x: .value("x", column.label), y: .value("y", column.height), width: .ratio(0.78))
                .cornerRadius(4)
                .foregroundStyle(column.isTallest ? Brand.accent : Brand.accent.opacity(0.38))
                .accessibilityLabel(column.label)
                .accessibilityValue(valueText(column.value))
            if column.label == picked {
                RuleMark(x: .value("x", column.label))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(valueText(column.value))
                            .textStyle(.caption)
                            .foregroundStyle(Palette.textPrimary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(Palette.cardAlt, in: .capsule)
                    }
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: axis) { _ in
                AxisValueLabel(collisionResolution: .disabled)
                    .font(.caption2)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .chartXSelection(value: $picked)
        .frame(height: 150)
        .padding(.top, Spacing.xl)
    }
}

/// A few named values as bars lying down, the largest at full width.
private struct BarRows: View {
    let rows: [(label: String, value: Int)]
    let valueText: (Int) -> String

    var body: some View {
        let values = rows.map(\.value)
        VStack(spacing: Spacing.md) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                        Text(row.label)
                            .textStyle(.subheadline)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(valueText(row.value))
                            .textStyle(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Capsule()
                        .fill(Palette.textPrimary.opacity(0.08))
                        .frame(height: 10)
                        .overlay(alignment: .leading) {
                            GeometryReader { track in
                                Capsule()
                                    .fill(Brand.accent)
                                    .frame(width: track.size.width * ActivityShare.of(row.value, among: values))
                            }
                        }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
