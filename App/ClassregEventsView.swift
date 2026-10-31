import SwiftUI
import PokyhCore
import PokyhDesign

/// Klassenbuch: the year in four figures and its split by category, then the entries in a time
/// range, by month, subject or category, each group one list card.
struct ClassregEventsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var events: [ClassregEvent] = []
    @State private var loading = true
    @State private var error: String?
    @State private var year = SchoolDates.currentSchoolYear
    @State private var yearShown = false

    var body: some View {
        Group {
            if loading {
                LoadingView()
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if events.isEmpty {
                StateView(s.tasks.classregEmpty, message: s.tasks.classregEmptyText, art: {
                    IconTile("book.closed", color: Brand.accent, size: 64)
                })
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        ClassregStats(events: events).fadeIn()
                        ClassregList(events: events)
                    }
                    .padding(.horizontal, Spacing.screenH)
                    .padding(.bottom, Spacing.xxxl)
                }
            }
        }
        .navigationTitle(s.tasks.classreg)
        .navigationSubtitle(s.common.schoolYear(year))
        .appBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SchoolDates.availableYears, id: \.self) { y in
                        Button { year = y } label: {
                            if y == year {
                                Label(Self.yearLabel(y), systemImage: "checkmark")
                            } else {
                                Text(Self.yearLabel(y))
                            }
                        }
                    }
                } label: {
                    Text(Self.yearLabel(year)).monospacedDigit()
                }
                .slideIn(yearShown)
            }
        }
        .task { withAnimation(.spring(response: 0.6, dampingFraction: 0.48).delay(0.1)) { yearShown = true } }
        .task(id: year) { await load() }
    }

    static func yearLabel(_ y: Int) -> String { "\(String(y))/\(String((y + 1) % 100))" }

    private func load() async {
        guard let s = app.session else { return }
        // No WebUntis: nothing to ask, and no error to show for it.
        guard s.hasUntis else { events = []; loading = false; return }
        error = nil
        // The stored year shows at once, the fresh one replaces it when it lands.
        let stored = UntisClient.shared.storedClassreg(year: year, s)
        events = stored ?? []
        loading = stored == nil
        do {
            events = try await UntisClient.shared.classreg(year: year, s)
        } catch let e as AppError where e.message == "session_expired" {
            app.handleSessionExpired()
        } catch {
            // What's on screen stays when there's only a refresh to lose.
            if stored == nil { self.error = (error as? AppError)?.message ?? error.localizedDescription }
        }
        loading = false
    }
}

/// The category's tone: blush for discipline and cheating, butter for notes, periwinkle else.
enum ClassregTone {
    static func of(_ category: String, reason: String = "") -> Tone {
        let l = "\(category) \(reason)".lowercased()
        let problem = ["täuschung", "betrug", "disziplin", "discipl", "verweis", "richiamo", "cheat"]
        if problem.contains(where: l.contains) { return Decorative.blush }
        if l.contains("vermerk") || l.contains("nota") || l.contains("note") { return Decorative.butter }
        return Decorative.periwinkle
    }

    /// Only the two categories that mean "problem" get a status color.
    static func accent(_ event: ClassregEvent) -> Color {
        let l = event.categoryName.lowercased()
        if l.contains("täuschung") || l.contains("betrug") { return Brand.danger }
        if l.contains("vermerk") { return Brand.warning }
        return Brand.accent
    }

    static func date(_ n: Int, _ pattern: String, _ s: Strings) -> String {
        var c = DateComponents()
        c.year = n / 10000; c.month = n / 100 % 100; c.day = n % 100
        guard let date = Calendar.current.date(from: c) else { return "" }
        let f = DateFormatter()
        f.locale = s.lang.locale
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

/// The year in four figures and the split by category, as on the web.
private struct ClassregStats: View {
    let events: [ClassregEvent]
    @Environment(\.strings) private var s

    private struct Category: Identifiable {
        let name: String
        let count: Int
        let tone: Tone
        var id: String { name }
    }

    var body: some View {
        let t = s.tasks
        let subjects = Set(events.map(\.subjectName).filter { !$0.isEmpty }).count
        let latest = events.map(\.createDate).max() ?? 0
        let categories = Dictionary(grouping: events) { $0.categoryName.isEmpty ? t.noCategory : $0.categoryName }
            .map { name, list in
                Category(name: name, count: list.count,
                         tone: ClassregTone.of(name == t.noCategory ? "" : name, reason: list.first?.eventReasonName ?? ""))
            }
            .sorted { $0.count > $1.count }
        let top = categories.first { $0.name != t.noCategory }?.name ?? ""
        var figures: [(label: String, value: String, small: Bool)] = [
            (t.totalEntries, "\(events.count)", false),
            (t.subjectsLabel, "\(subjects)", false),
            (t.lastEntry, latest > 0 ? ClassregTone.date(latest, s.lang == .de ? "d. MMM" : "d MMM", s) : "-", false),
        ]
        if !top.isEmpty { figures.append((t.topCategory, top, true)) }

        return VStack(alignment: .leading, spacing: Spacing.xl) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.xl, alignment: .topLeading),
                                GridItem(.flexible(), spacing: Spacing.xl, alignment: .topLeading)],
                      alignment: .leading, spacing: Spacing.xl) {
                ForEach(figures, id: \.label) { figure in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(figure.label)
                            .textStyle(TextStyle.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                        Text(figure.value)
                            .textStyle(figure.small ? TextStyle.title2.weight(.heavy) : .largeTitle)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }

            if categories.count > 1 {
                GeometryReader { geo in
                    let gaps = CGFloat(categories.count - 1) * 3
                    HStack(spacing: 3) {
                        ForEach(categories) { c in
                            Capsule().fill(c.tone.ink)
                                .frame(width: max(3, (geo.size.width - gaps) * CGFloat(c.count) / CGFloat(events.count)))
                        }
                    }
                }
                .frame(height: 10)

                WrapLayout(spacing: Spacing.xl, lineSpacing: 6) {
                    ForEach(categories) { c in
                        HStack(spacing: 6) {
                            Circle().fill(c.tone.ink).frame(width: 8, height: 8)
                            Text(c.name).textStyle(.footnote).foregroundStyle(Palette.textSecondary)
                            Text("\(c.count)").textStyle(TextStyle.footnote.weight(.bold)).foregroundStyle(Palette.textPrimary)
                        }
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.xl, fill: Palette.card)
    }
}

/// The entries in a time range, sorted and grouped: by month, or by subject or category.
private struct ClassregList: View {
    let events: [ClassregEvent]
    @Environment(\.strings) private var s

    private struct EntryGroup: Identifiable {
        let key: String
        let title: String
        let items: [ClassregEvent]
        var id: String { key }
    }

    @State private var range: ClassregRange = .all
    @State private var sort: ClassregSort = .dateDesc

    var body: some View {
        let groups = grouped()
        VStack(alignment: .leading, spacing: Spacing.section) {
            HStack(spacing: Spacing.sm) {
                PokyhSegmentedControl(ClassregRange.allCases, selection: $range) { rangeLabel($0) }
                Menu {
                    Picker(s.tasks.sortBy, selection: $sort) {
                        ForEach(ClassregSort.allCases, id: \.self) { Text(sortLabel($0)).tag($0) }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(sortLabel(sort)).textStyle(TextStyle.footnote.weight(.semibold))
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 44)
                    .insetSurface(radius: 22)
                }
            }

            if groups.isEmpty {
                Text(s.tasks.noEntriesRange)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, Spacing.lg)
            }
            ForEach(groups) { group in
                PokyhSection(group.title) {
                    EyebrowLabel("\(group.items.count)")
                } content: {
                    ListCard(group.items) { ClassregRow(event: $0) }
                }
                .fadeIn()
                .id("\(sort)-\(group.key)")
            }
        }
        .animation(Motion.standardEase, value: range)
        .animation(Motion.standardEase, value: sort)
    }

    private func grouped() -> [EntryGroup] {
        ClassregGrouping.groups(events, range: range, sort: sort, noCategory: s.tasks.noCategory).map { group in
            let title: String
            if sort.groupsByName {
                title = group.key
            } else {
                let month = ClassregTone.date(group.items.first?.createDate ?? 0, "LLLL yyyy", s)
                title = month.prefix(1).uppercased() + month.dropFirst()
            }
            return EntryGroup(key: group.key, title: title, items: group.items)
        }
    }

    private func rangeLabel(_ r: ClassregRange) -> String {
        switch r {
        case .all: s.tasks.filterAll
        case .month: s.tasks.filter1m
        case .months3: s.tasks.filter3m
        }
    }

    private func sortLabel(_ v: ClassregSort) -> String {
        switch v {
        case .dateDesc: s.tasks.sortDateDesc
        case .dateAsc: s.tasks.sortDateAsc
        case .subject: s.tasks.sortSubject
        case .category: s.tasks.sortCategory
        }
    }
}

struct ClassregRow: View {
    let event: ClassregEvent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.iconText) {
            Text(Fmt.dateShort(event.createDate))
                .textStyle(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(event.subjectName)
                        .textStyle(.headline)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !event.categoryName.isEmpty {
                        TagChip(event.categoryName, color: ClassregTone.accent(event))
                    }
                }
                let text = event.text.isEmpty ? event.eventReasonName : event.text
                if !text.isEmpty {
                    Text(text)
                        .textStyle(.callout)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !event.creatorName.isEmpty {
                    Text(event.creatorName).textStyle(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .padding(Spacing.card)
    }
}

/// Wraps its children onto new lines. A child wider than the line gets the line's width.
struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func size(of view: LayoutSubview, proposal: ProposedViewSize) -> CGSize {
        view.sizeThatFits(ProposedViewSize(width: proposal.width.map { min($0, view.sizeThatFits(.unspecified).width) }, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = size(of: view, proposal: proposal)
            if x > 0 && x + size.width > width {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = size(of: view, proposal: proposal)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
