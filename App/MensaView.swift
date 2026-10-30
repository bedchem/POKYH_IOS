import SwiftUI
import PokyhCore
import PokyhDesign

/// The days of the menu from today on, oldest first. Past days never come back as a fallback,
/// so no menu means an empty plan. Home uses it too.
nonisolated enum MensaSchedule {
    static func days(from dishes: [Dish]) -> [(date: Date, dishes: [Dish])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var byDay: [Date: [Dish]] = [:]
        for d in dishes {
            if let date = f.date(from: String(d.date.prefix(10))) {
                byDay[cal.startOfDay(for: date), default: []].append(d)
            }
        }
        return byDay.keys.sorted()
            .filter { $0 >= today }
            .map { (date: $0, dishes: byDay[$0] ?? []) }
    }

    /// "Heute", "Morgen" or "Mittwoch, 29. Oktober".
    static func label(for date: Date, _ s: Strings) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return s.mensa.today }
        if cal.isDateInTomorrow(date) { return s.mensa.tomorrow }
        let f = DateFormatter()
        f.locale = s.lang.locale
        f.dateFormat = s.mensa.dayPattern
        let text = f.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The Monday a date's week starts on, to group the plan by week.
    static func weekStart(_ date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// The day a dish is served, parsed from its `yyyy-MM-dd…` date.
    static func date(of dish: Dish) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: String(dish.date.prefix(10)))
    }

    /// One decimal in the language's style ("4,2").
    static func fixed(_ value: Double, _ digits: Int, _ s: Strings) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: String(s.common.decimal))
    }
}

/// Mensa: the next dish served large on its plate, the day's other dishes as chips, then the
/// whole plan week by week. The one screen built from image cards, since the food is the point.
struct MensaView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var dishes: [Dish] = []
    @State private var ratings: [String: DishRatingsData] = [:]
    @State private var loading = true
    @State private var ratingsLoading = false
    @State private var error: String?
    @State private var selectedDish: Dish?

    private var token: String? { app.session?.apiToken }

    private var days: [(date: Date, dishes: [Dish])] { MensaSchedule.days(from: dishes) }

    var body: some View {
        Group {
            if loading && dishes.isEmpty {
                MensaLoading()
            } else if let error, days.isEmpty {
                ErrorStateView(message: error) { Task { await load(force: true) } }
            } else if days.isEmpty {
                ScrollView {
                    EmptyStateView(systemImage: "fork.knife", title: s.mensa.emptyTitle, subtitle: s.mensa.emptySubtitle)
                        .padding(.top, Spacing.huge)
                }
            } else {
                MensaPlan(days: days, ratings: ratings, ratingsLoading: ratingsLoading, unknown: token == nil) { selectedDish = $0 }
            }
        }
        .navigationTitle(s.nav.mensa)
        .profileToolbar()
        .appBackground()
        .navigationDestination(item: $selectedDish) { dish in
            DishDetailView(dish: dish, data: ratings[dish.id], canRate: token != nil) { stars in
                Task { await rate(dish, stars) }
            }
        }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        loading = dishes.isEmpty
        error = nil
        do {
            dishes = try await BackendClient.shared.dishes(force: force)
            loading = false
            await loadRatings()
        } catch {
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func loadRatings() async {
        guard let token else { return }
        let ids = dishes.map { $0.id }
        guard !ids.isEmpty else { return }
        ratingsLoading = ratings.isEmpty
        if let batch = try? await BackendClient.shared.dishRatingsBatch(ids: ids, token: token) {
            ratings = batch
        }
        ratingsLoading = false
    }

    private func rate(_ dish: Dish, _ stars: Int) async {
        guard let token else { return }
        var d = ratings[dish.id] ?? DishRatingsData(ratings: [:], myRating: nil)
        d.myRating = stars
        if let uid = app.session?.stableUid { d.ratings[uid] = Double(stars) }
        ratings[dish.id] = d
        try? await BackendClient.shared.rateDish(id: dish.id, stars: stars, token: token)
        if let fresh = try? await BackendClient.shared.dishRatings(id: dish.id, token: token) {
            ratings[dish.id] = fresh
        }
    }
}

// ── The plan ─────────────────────────────────────────────────────────────────

private struct MensaPlan: View {
    let days: [(date: Date, dishes: [Dish])]
    let ratings: [String: DishRatingsData]
    let ratingsLoading: Bool
    let unknown: Bool
    let open: (Dish) -> Void
    @Environment(\.strings) private var s

    private var weeks: [(start: Date, days: [(date: Date, dishes: [Dish])])] {
        var order: [Date] = []
        var byWeek: [Date: [(date: Date, dishes: [Dish])]] = [:]
        for day in days {
            let week = MensaSchedule.weekStart(day.date)
            if byWeek[week] == nil { order.append(week) }
            byWeek[week, default: []].append(day)
        }
        return order.map { (start: $0, days: byWeek[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let next = days.first, let served = Self.lead(next.dishes) {
                    ServedDish(day: next.date, served: served, others: next.dishes.filter { $0 != served },
                               rating: ratings[served.id], ratingsLoading: ratingsLoading, unknown: unknown, open: open)
                        .fadeIn()
                }

                Text(s.mensa.allDays)
                    .textStyle(.largeTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, 56)

                ForEach(weeks, id: \.start) { week in
                    Text(weekTitle(week.start, firstDay: week.days.first?.date ?? week.start))
                        .textStyle(TextStyle.callout.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, Spacing.xxxl)
                        .padding(.bottom, Spacing.md)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Spacing.md)], alignment: .leading, spacing: Spacing.md) {
                        ForEach(week.days, id: \.date) { day in
                            ForEach(day.dishes) { dish in
                                PlanRow(dish: dish, dayLabel: MensaSchedule.label(for: day.date, s), rating: ratings[dish.id],
                                        ratingsLoading: ratingsLoading, unknown: unknown) { open(dish) }
                                    .fadeIn()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
        }
    }

    /// The dish served large: the first with a photo, else the first.
    static func lead(_ dishes: [Dish]) -> Dish? {
        dishes.first { !($0.imageUrl ?? "").isEmpty } ?? dishes.first
    }

    private func weekTitle(_ start: Date, firstDay: Date) -> String {
        let thisWeek = MensaSchedule.weekStart(Date())
        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: thisWeek) { return s.mensa.thisWeek }
        if let next = cal.date(byAdding: .day, value: 7, to: thisWeek), cal.isDate(start, inSameDayAs: next) {
            return s.mensa.nextWeek
        }
        let c = cal.dateComponents([.day, .month], from: firstDay)
        return s.mensa.fromDate(s.common.dayMonth(c.day ?? 1, c.month ?? 1))
    }
}

/// The next dish: on its plate between fork and knife, what it is, how the school rated it.
private struct ServedDish: View {
    let day: Date
    let served: Dish
    let others: [Dish]
    let rating: DishRatingsData?
    let ratingsLoading: Bool
    let unknown: Bool
    let open: (Dish) -> Void
    @Environment(\.strings) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Button { open(served) } label: {
                DishPlate(dish: served, size: .table)
                    .contentShape(.rect)
            }
            .buttonStyle(PressableStyle())

            Text(MensaSchedule.label(for: day, s))
                .textStyle(TextStyle.callout.weight(.semibold))
                .foregroundStyle(Palette.textTertiary)
            Text(served.name)
                .textStyle(.title1)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let desc = served.description, !desc.isEmpty {
                Text(desc)
                    .textStyle(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RatingLine(rating: rating, loading: ratingsLoading, unknown: unknown)
            Button { open(served) } label: {
                HStack(spacing: Spacing.sm) {
                    Text(s.mensa.rateAndComment)
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                }
            }
            .buttonStyle(.primary)

            if !others.isEmpty {
                MensaFlow(spacing: Spacing.sm) {
                    ForEach(others) { dish in
                        Button { open(dish) } label: {
                            HStack(spacing: Spacing.sm) {
                                DishPlate(dish: dish, size: .plate).frame(width: 36)
                                Text(dish.name)
                                    .textStyle(TextStyle.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, Spacing.xs)
                            .padding(.trailing, Spacing.lg)
                            .padding(.vertical, Spacing.xs)
                            .background(Palette.card, in: .capsule)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }
}

/// One dish of the plan: its small plate, the day, the name, the rating.
private struct PlanRow: View {
    let dish: Dish
    let dayLabel: String
    let rating: DishRatingsData?
    let ratingsLoading: Bool
    let unknown: Bool
    let action: () -> Void

    var body: some View {
        PokyhCard(padding: Spacing.md, action: action) {
            HStack(spacing: Spacing.lg) {
                DishPlate(dish: dish, size: .plate).frame(width: 72)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(dayLabel)
                        .textStyle(TextStyle.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                    Text(dish.name)
                        .textStyle(.headline)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    RatingLine(rating: rating, loading: ratingsLoading, unknown: unknown)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The stars and "4,2 · 12 Bewertungen", or that nobody has voted yet. Holds its height while
/// the ratings load, so the list doesn't jump when they arrive.
private struct RatingLine: View {
    let rating: DishRatingsData?
    let loading: Bool
    let unknown: Bool
    @Environment(\.strings) private var s

    var body: some View {
        let count = rating?.count ?? 0
        HStack(spacing: Spacing.sm) {
            if loading && rating == nil {
                SkeletonBlock(height: 12, width: 64, radius: 4)
            } else {
                StarRow(value: rating?.average ?? 0, size: 12)
            }
            if count > 0, let rating {
                Text("\(MensaSchedule.fixed(rating.average, 1, s)) · \(count == 1 ? s.mensa.ratingOne : s.mensa.ratingMany(count))")
                    .textStyle(TextStyle.footnote.weight(.regular))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            } else if !loading && !unknown {
                Text(s.mensa.noRatingYet)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 18)
    }
}

/// Five stars filled up to a rounded value.
private struct StarRow: View {
    let value: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                let on = Double(star) <= value.rounded()
                Image(systemName: on ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(on ? Brand.star : Palette.textTertiary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// While the menu loads: an empty plate where the next dish goes, rows holding their place.
private struct MensaLoading: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                DishPlate(dish: nil, size: .table)
                SkeletonBlock(height: 16, width: 96)
                SkeletonBlock(height: 34, width: 280)
                SkeletonBlock(height: 20, width: 176)
                Spacer().frame(height: Spacing.xl)
                ForEach(0..<3, id: \.self) { _ in
                    PokyhCard(padding: Spacing.md) {
                        HStack(spacing: Spacing.lg) {
                            DishPlate(dish: nil, size: .plate).frame(width: 72)
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                SkeletonBlock(height: 12, width: 96)
                                SkeletonBlock(height: 18, width: 200)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.screenH)
        }
        .scrollDisabled(true)
    }
}

// ── Plate ────────────────────────────────────────────────────────────────────

/// A dish on a glazed plate, lit from the top left, the photo lying in the well. Without a photo
/// a small glyph of the kind of meal stands in. `.table` adds fork and knife for the next dish.
struct DishPlate: View {
    enum Size { case table, plate }

    let dish: Dish?
    var size: Size = .plate

    var body: some View {
        switch size {
        case .plate:
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { PlateDisc(dish: dish) }
        case .table:
            Color.clear
                .aspectRatio(112.0 / 64.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    GeometryReader { geo in
                        let d = geo.size.height * 0.89
                        HStack(spacing: d * 0.16) {
                            ForkShape(height: d * 0.92)
                            PlateDisc(dish: dish).frame(width: d, height: d)
                            KnifeShape(height: d * 0.92)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dish?.name ?? "")
        }
    }
}

private struct PlateDisc: View {
    let dish: Dish?

    private static let rim = Color(light: 0xFFFFFF, dark: 0x3A3A41)
    private static let rimShade = Color(light: 0xE6E1D8, dark: 0x2A2A30)
    private static let well = Color(light: 0xF4F1EB, dark: 0x303036)

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Self.rim, Self.rimShade], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.16), radius: d * 0.04, x: d * 0.03, y: d * 0.06)
                Circle()
                    .fill(Self.well)
                    .frame(width: d * 0.80, height: d * 0.80)
                    .overlay(Circle().strokeBorder(Self.rimShade.opacity(0.7), lineWidth: max(0.5, d * 0.012)))
                food
                    .frame(width: d * 0.68, height: d * 0.68)
                    .clipShape(.circle)
            }
            .frame(width: d, height: d)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder private var food: some View {
        if let dish, let raw = dish.imageUrl, let url = URL(string: raw) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    stand(in: dish)
                }
            }
        } else if let dish {
            stand(in: dish)
        } else {
            Self.well
        }
    }

    /// The kind of meal when there's no photo (the web's `foodStyleOf`).
    private func stand(in dish: Dish) -> some View {
        let text = "\(dish.category) \(dish.tags.joined(separator: " "))".lowercased()
        let style: (symbol: String, tone: Tone)
        if text.contains("salat") || text.contains("vegan") || text.contains("vegetar") {
            style = ("leaf.fill", Decorative.sage)
        } else if text.contains("suppe") || text.contains("pasta") || text.contains("nudel") {
            style = ("frying.pan.fill", Decorative.butter)
        } else if text.contains("fisch") {
            style = ("fish.fill", Decorative.periwinkle)
        } else {
            style = ("fork.knife", Decorative.blush)
        }
        return GeometryReader { geo in
            Image(systemName: style.symbol)
                .font(.system(size: geo.size.width * 0.42, weight: .semibold))
                .foregroundStyle(style.tone.ink)
                .frame(width: geo.size.width, height: geo.size.height)
                .background(style.tone.fill)
        }
    }
}

private struct ForkShape: View {
    let height: CGFloat
    var body: some View {
        let w = height * 0.16
        VStack(spacing: 0) {
            HStack(spacing: w * 0.18) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().frame(width: w * 0.2, height: height * 0.26)
                }
            }
            UnevenRoundedRectangle(bottomLeadingRadius: w * 0.5, bottomTrailingRadius: w * 0.5)
                .frame(width: w, height: height * 0.12)
            Capsule().frame(width: w * 0.42, height: height * 0.62)
        }
        .foregroundStyle(Palette.textTertiary.opacity(0.45))
        .accessibilityHidden(true)
    }
}

private struct KnifeShape: View {
    let height: CGFloat
    var body: some View {
        let w = height * 0.14
        VStack(spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: w * 0.2, topTrailingRadius: w)
                .frame(width: w, height: height * 0.44)
            Capsule().frame(width: w * 0.62, height: height * 0.56)
        }
        .foregroundStyle(Palette.textTertiary.opacity(0.45))
        .accessibilityHidden(true)
    }
}

// ── Dish card ────────────────────────────────────────────────────────────────

struct DishCard: View {
    let dish: Dish
    let data: DishRatingsData?

    var body: some View {
        BleedCard {
            DishImage(dish: dish, height: 150)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    if !dish.category.isEmpty {
                        TagChip(dish.category.uppercased(), color: Palette.subject(dish.category))
                    }
                    Spacer()
                    if let price = dish.price, price > 0 {
                        Text(String(format: "%.2f €", price)).textStyle(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                Text(dish.name)
                    .textStyle(.title3)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let desc = dish.description, !desc.isEmpty {
                    Text(desc)
                        .textStyle(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let data, data.average > 0 {
                    MiniStars(value: data.average, count: data.count)
                }
            }
            .padding(Spacing.card)
        }
    }
}

// ── Dish page ────────────────────────────────────────────────────────────────

struct DishDetailView: View {
    let dish: Dish
    let data: DishRatingsData?
    var canRate = true
    let onRate: (Int) -> Void
    @Environment(\.strings) private var s

    private var ratings: DishRatingsData { data ?? DishRatingsData(ratings: [:], myRating: nil) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if let raw = dish.imageUrl, !raw.isEmpty {
                    DishImage(dish: dish, height: 210)
                        .clipShape(.pokyh(Radius.xxl))
                        .fadeIn()
                } else {
                    DishPlate(dish: dish, size: .table).fadeIn()
                }

                header.fadeIn(delay: 0.04)

                PokyhSection(s.mensa.rating) {
                    PokyhCard {
                        DishRatingBlock(ratings: ratings, onRate: canRate ? onRate : nil)
                    }
                }
                .fadeIn(delay: 0.08)

                DishNutritionSection(dish: dish).fadeIn(delay: 0.12)

                if !dish.allergens.isEmpty {
                    PokyhSection(s.mensa.allergens) {
                        MensaFlow(spacing: 6) {
                            ForEach(dish.allergens, id: \.self) { allergen in
                                Text(allergen)
                                    .textStyle(TextStyle.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.xs)
                                    .background(Palette.nested, in: .capsule)
                            }
                        }
                    }
                }

                CommentSection(
                    title: s.common.comments,
                    load: { try await BackendClient.shared.dishComments(dishId: dish.id, token: $0) },
                    create: { try await BackendClient.shared.createDishComment(dishId: dish.id, body: $1, token: $0) },
                    delete: { try await BackendClient.shared.deleteDishComment(dishId: dish.id, commentId: $1, token: $0) },
                    ratings: ratings.ratings,
                    reportPath: "/canteen/\(dish.id)"
                )
                .fadeIn(delay: 0.16)
            }
            .padding(.horizontal, Spacing.screenH)
            .padding(.bottom, Spacing.xxxl)
        }
        .navigationTitle(dish.category.isEmpty ? s.mensa.dish : dish.category)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
    }

    /// The day, the name large, stars and kcal, the text, the diet tags and the price.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let date = MensaSchedule.date(of: dish) {
                Text(MensaSchedule.label(for: date, s))
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            Text(dish.name)
                .textStyle(TextStyle(34, 36, .heavy, tracking: -0.02, relativeTo: .largeTitle))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "star.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.star)
                Text(ratings.count > 0 ? MensaSchedule.fixed(ratings.average, 1, s) : "–")
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("(\(ratings.count))").textStyle(.callout).foregroundStyle(Palette.textSecondary)
                if let kcal = dish.calories {
                    Text("·").textStyle(.callout).foregroundStyle(Palette.textSecondary)
                    Text("\(Int(kcal)) kcal").textStyle(.callout).foregroundStyle(Palette.textSecondary)
                }
            }
            if let desc = dish.description, !desc.isEmpty {
                Text(desc)
                    .textStyle(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dish.tags.isEmpty {
                MensaFlow(spacing: 6) {
                    ForEach(Self.prioritized(dish.tags), id: \.self) { DietTag(tag: $0) }
                }
                .padding(.top, Spacing.xs)
            }
            if let price = dish.price, price > 0 {
                TagChip(MensaSchedule.fixed(price, 2, s) + " €", color: Palette.textSecondary, large: true)
            }
        }
    }

    /// Vegan first, then vegetarian, then the rest.
    static func prioritized(_ tags: [String]) -> [String] {
        func rank(_ t: String) -> Int {
            let l = t.lowercased()
            if l.contains("vegan") { return 0 }
            if l.contains("vegetar") { return 1 }
            return 2
        }
        return tags.sorted { rank($0) < rank($1) }
    }
}

/// Sage for vegan and vegetarian, butter gluten-free, periwinkle halal.
private struct DietTag: View {
    let tag: String

    private var tone: Tone? {
        let l = tag.lowercased()
        if l.contains("vegan") || l.contains("vegetar") { return Decorative.sage }
        if l.contains("glutenfrei") { return Decorative.butter }
        if l.contains("halal") { return Decorative.periwinkle }
        return nil
    }

    var body: some View {
        Text(tag)
            .textStyle(TextStyle.footnote.weight(.semibold))
            .foregroundStyle(tone?.ink ?? Palette.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(tone?.fill ?? Palette.nested, in: .capsule)
    }
}

/// The average large with its stars, the 5→1 bars beside it, and "Deine Bewertung" with the
/// five stars to tap and the word for the one picked.
private struct DishRatingBlock: View {
    let ratings: DishRatingsData
    let onRate: ((Int) -> Void)?
    @Environment(\.strings) private var s

    var body: some View {
        let values = Array(ratings.ratings.values)
        let count = values.count
        let bins = [5, 4, 3, 2, 1].map { star in values.filter { Int($0.rounded()) == star }.count }
        let maxBin = max(1, bins.max() ?? 0)

        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .center, spacing: Spacing.xxl) {
                VStack(spacing: 0) {
                    Text(count > 0 ? MensaSchedule.fixed(ratings.average, 1, s) : "–")
                        .textStyle(.statLarge)
                        .foregroundStyle(Palette.textPrimary)
                    StarRow(value: ratings.average, size: 13).padding(.top, Spacing.sm)
                    Text(count == 0 ? s.mensa.noRatingYet : count == 1 ? s.mensa.ratingOne : s.mensa.ratingMany(count))
                        .textStyle(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .frame(minWidth: 88)

                VStack(spacing: 6) {
                    ForEach(Array(bins.enumerated()), id: \.offset) { index, n in
                        HStack(spacing: Spacing.sm) {
                            Text("\(5 - index)").textStyle(.caption2).foregroundStyle(Palette.textTertiary).frame(width: 12)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.nested)
                                    Capsule().fill(Brand.star).frame(width: geo.size.width * CGFloat(n) / CGFloat(maxBin))
                                }
                            }
                            .frame(height: 6)
                            Text("\(n)").textStyle(.caption2).foregroundStyle(Palette.textTertiary).frame(width: 22, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            yourRating
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yourRating: some View {
        let mine = ratings.myRating ?? 0
        let labels = s.mensa.rateLabels
        return HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.mensa.yourRating)
                    .textStyle(TextStyle.callout.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(onRate == nil ? s.mensa.offlineRating : (mine > 0 && mine <= labels.count ? labels[mine - 1] : " "))
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onRate {
                StarRating(avg: 0, count: 0, myRating: mine, canRate: true, onRate: onRate)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .background(Palette.nested, in: .pokyh(Radius.md))
    }
}

/// kcal and the macros as tiles, each with its colour, the macros' shares as one bar. Both
/// qualifiers (estimated, per 100 g) sit where the numbers are, not in a footer.
private struct DishNutritionSection: View {
    let dish: Dish
    @Environment(\.strings) private var s

    private var macros: [(label: String, value: Double, color: Color)] {
        var list: [(label: String, value: Double, color: Color)] = []
        if let p = dish.protein { list.append((s.mensa.protein, p, Decorative.blush.ink)) }
        if let c = dish.carbs { list.append((s.mensa.carbsLong, c, Decorative.butter.ink)) }
        if let f = dish.fat { list.append((s.mensa.fat, f, Decorative.periwinkle.ink)) }
        return list
    }

    var body: some View {
        if dish.calories != nil || !macros.isEmpty {
            PokyhSection(s.mensa.nutrition) {
                PokyhCard {
                    HStack(spacing: Spacing.sm) {
                        Text(s.mensa.per100)
                            .textStyle(.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MiniBadge(s.mensa.estimated, symbol: "info.circle.fill", color: Brand.warning)
                    }
                    .padding(.bottom, Spacing.lg)

                    HStack(spacing: Spacing.sm) {
                        if let kcal = dish.calories { tile("\(Int(kcal))", "kcal", nil) }
                        ForEach(macros, id: \.label) { m in tile("\(Int(m.value)) g", m.label, m.color) }
                    }

                    let total = macros.reduce(0) { $0 + $1.value }
                    if total > 0 {
                        GeometryReader { geo in
                            let gaps = CGFloat(max(0, macros.count - 1)) * 4
                            HStack(spacing: 4) {
                                ForEach(macros, id: \.label) { m in
                                    Capsule().fill(m.color)
                                        .frame(width: max(2, (geo.size.width - gaps) * CGFloat(m.value / total)))
                                }
                            }
                        }
                        .frame(height: 8)
                        .padding(.top, Spacing.md)
                    }

                    Text(s.mensa.estimatedNote)
                        .textStyle(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.md)
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String, _ dot: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .textStyle(TextStyle.headline.weight(.heavy))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(label)
                    .textStyle(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.nested, in: .pokyh(Radius.md))
    }
}

// ── Photo ────────────────────────────────────────────────────────────────────

struct DishImage: View {
    let dish: Dish
    var height: CGFloat
    var body: some View {
        // A fixed band the photo fills whatever its own size.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                if let urlStr = dish.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
    private var placeholder: some View {
        LinearGradient(colors: [Palette.subject(dish.category).opacity(0.34), Palette.subject(dish.name).opacity(0.20)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "fork.knife").font(.system(size: 40, weight: .semibold)).foregroundStyle(Palette.card.opacity(0.85)))
    }
}

// ── Stars ────────────────────────────────────────────────────────────────────

/// Five tappable stars, 44pt targets, each read out with its word ("Mega").
struct StarRating: View {
    let avg: Double
    let count: Int
    let myRating: Int
    let canRate: Bool
    let onRate: (Int) -> Void
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                Button { if canRate { onRate(star) } } label: {
                    Image(systemName: star <= myRating ? "star.fill" : "star")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(star <= myRating ? Brand.star : Palette.textTertiary)
                        .symbolEffect(.bounce, value: myRating == star)
                        .frame(width: 40, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!canRate)
                .accessibilityLabel("\(star)/5 · \(s.mensa.rateLabels.indices.contains(star - 1) ? s.mensa.rateLabels[star - 1] : "")")
            }
            if avg > 0 {
                Text(MensaSchedule.fixed(avg, 1, s)).textStyle(TextStyle.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary).padding(.leading, 2)
                Text("(\(count))").textStyle(.caption).foregroundStyle(Palette.textTertiary)
            }
        }
        .sensoryFeedback(.selection, trigger: myRating)
    }
}

struct MiniStars: View {
    let value: Double
    let count: Int
    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: Spacing.sm) {
            StarRow(value: value, size: 11)
            Text("\(MensaSchedule.fixed(value, 1, s)) · \(count == 1 ? s.mensa.ratingOne : s.mensa.ratingMany(count))")
                .textStyle(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

struct DishSkeleton: View {
    var body: some View {
        PokyhCard(padding: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                DishPlate(dish: nil, size: .plate).frame(width: 72)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SkeletonBlock(height: 12, width: 96)
                    SkeletonBlock(height: 18, width: 200)
                }
            }
        }
    }
}

/// Chips that wrap onto the next line, like Compose's FlowRow.
private struct MensaFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
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
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
