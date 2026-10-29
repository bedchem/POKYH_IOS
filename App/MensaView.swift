import SwiftUI

/// Gemeinsame Mensa-Datums-Logik: ab dem AKTUELLEN Datum (heute) alle Tage
/// aufsteigend. Liegen keine heutigen/zukünftigen Gerichte in der API vor,
/// bleibt es leer (kein Rückfall auf alte Tage). Genutzt von Home + Mensa-Tab.
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
        // STRIKT ab heute: nur heutiges + zukünftige Daten, aufsteigend.
        // Liegen keine vor, bleibt es leer (kein Rückfall auf vergangene Tage).
        return byDay.keys.sorted()
            .filter { $0 >= today }
            .map { (date: $0, dishes: byDay[$0] ?? []) }
    }
}

struct MensaView: View {
    @EnvironmentObject var app: AppState
    @State private var dishes: [Dish] = []
    @State private var ratings: [String: DishRatingsData] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var selectedDish: Dish?

    private var token: String? { app.session?.apiToken }

    private var grouped: [(date: Date, label: String, dishes: [Dish])] {
        MensaSchedule.days(from: dishes).map { (date: $0.date, label: label(for: $0.date), dishes: $0.dishes) }
    }

    var body: some View {
        Group {
            if loading {
                ScrollView { LazyVStack(spacing: 16) { ForEach(0..<3, id: \.self) { _ in DishSkeleton() } }.padding(16) }
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else if grouped.isEmpty {
                EmptyStateView(systemImage: "fork.knife", title: "Kein Speiseplan", subtitle: "Aktuell ist kein Menü verfügbar.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(grouped, id: \.label) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.label).font(.title3.bold()).foregroundStyle(Palette.textPrimary)
                                ForEach(group.dishes) { dish in
                                    Button { selectedDish = dish } label: {
                                        DishCard(dish: dish, data: ratings[dish.id])
                                    }
                                    .buttonStyle(.pressable)
                                }
                            }
                            .fadeIn()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Mensa")
        .profileToolbar()
        .appBackground()
        .navigationDestination(item: $selectedDish) { dish in
            DishDetailView(dish: dish, data: ratings[dish.id]) { stars in
                Task { await rate(dish, stars) }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = dishes.isEmpty
        error = nil
        do {
            dishes = try await BackendClient.shared.dishes()
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
        if let batch = try? await BackendClient.shared.dishRatingsBatch(ids: ids, token: token) {
            ratings = batch
        }
    }

    private func rate(_ dish: Dish, _ stars: Int) async {
        guard let token else { return }
        var d = ratings[dish.id] ?? DishRatingsData(ratings: [:], myRating: nil)
        d.myRating = stars
        ratings[dish.id] = d
        try? await BackendClient.shared.rateDish(id: dish.id, stars: stars, token: token)
        if let fresh = try? await BackendClient.shared.dishRatings(id: dish.id, token: token) {
            ratings[dish.id] = fresh
        }
    }

    private func parseDate(_ key: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: key)
    }
    private func label(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInTomorrow(date) { return "Morgen" }
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEEE, d. MMMM"
        return f.string(from: date)
    }
}

// ── Gericht-Karte (Liste, schreibgeschützte Sterne) ─────────────────────────

struct DishCard: View {
    let dish: Dish
    let data: DishRatingsData?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DishImage(dish: dish, height: 160)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if !dish.category.isEmpty {
                        Text(dish.category.uppercased()).font(.caption2.bold()).foregroundStyle(Palette.accent)
                    }
                    Spacer()
                    if let price = dish.price, price > 0 {
                        Text(String(format: "%.2f €", price)).font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                    }
                }
                Text(dish.name).font(.headline).foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let desc = dish.description, !desc.isEmpty {
                    Text(desc).font(.subheadline).foregroundStyle(Palette.textSecondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let data, data.average > 0 {
                    MiniStars(value: data.average, count: data.count)
                }
            }
            .padding(16)
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// ── Gericht-Detail (Voting + Kommentare) ────────────────────────────────────

struct DishDetailView: View {
    let dish: Dish
    let data: DishRatingsData?
    let onRate: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DishImage(dish: dish, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if !dish.category.isEmpty {
                    Text(dish.category.uppercased()).font(.caption.bold()).foregroundStyle(Palette.accent)
                }
                Text(dish.name).font(.title2.bold()).foregroundStyle(Palette.textPrimary)
                if let desc = dish.description, !desc.isEmpty {
                    Text(desc).font(.body).foregroundStyle(Palette.textSecondary)
                }

                StarRating(avg: data?.average ?? 0, count: data?.count ?? 0,
                           myRating: data?.myRating ?? 0, canRate: true, onRate: onRate)

                if dish.calories != nil || dish.protein != nil || dish.carbs != nil || dish.fat != nil {
                    HStack(spacing: 18) {
                        if let c = dish.calories { nutrient("\(Int(c))", "kcal") }
                        if let p = dish.protein { nutrient("\(Int(p))g", "Protein") }
                        if let c = dish.carbs { nutrient("\(Int(c))g", "KH") }
                        if let f = dish.fat { nutrient("\(Int(f))g", "Fett") }
                    }
                    .padding(14).frame(maxWidth: .infinity)
                    .cardSurface()
                }
                if !dish.allergens.isEmpty {
                    Text("Allergene: \(dish.allergens.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(Palette.textTertiary)
                }

                Divider().overlay(Palette.separator)

                CommentSection(
                    title: "Kommentare",
                    load: { try await BackendClient.shared.dishComments(dishId: dish.id, token: $0) },
                    create: { try await BackendClient.shared.createDishComment(dishId: dish.id, body: $1, token: $0) },
                    delete: { try await BackendClient.shared.deleteDishComment(dishId: dish.id, commentId: $1, token: $0) }
                )
            }
            .padding(16)
        }
        .navigationTitle(dish.name)
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
    }

    private func nutrient(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.bold()).foregroundStyle(Palette.textPrimary)
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
        }.frame(maxWidth: .infinity)
    }
}

// ── Bild ─────────────────────────────────────────────────────────────────────

struct DishImage: View {
    let dish: Dish
    var height: CGFloat
    var body: some View {
        // Feste Box (immer gleiches Format) — das Bild füllt sie formatunabhängig
        // (scaledToFill + clipped), egal welche Originalgröße es hat.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                if let urlStr = dish.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .empty: placeholder.overlay(ProgressView().tint(.white))
                        default: placeholder
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
        LinearGradient(colors: [Palette.subject(dish.category).opacity(0.5), Palette.subject(dish.name).opacity(0.3)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "fork.knife").font(.title).foregroundStyle(.white.opacity(0.7)))
    }
}

// ── Sterne ───────────────────────────────────────────────────────────────────

struct StarRating: View {
    let avg: Double
    let count: Int
    let myRating: Int
    let canRate: Bool
    let onRate: (Int) -> Void
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { s in
                Button { if canRate { onRate(s) } } label: {
                    Image(systemName: s <= myRating ? "star.fill" : "star")
                        .font(.system(size: 22))
                        .foregroundStyle(s <= myRating ? Color(hex: "#FFD60A") : Palette.textTertiary)
                }
                .buttonStyle(.pressable).disabled(!canRate)
            }
            if avg > 0 {
                Text(String(format: "%.1f", avg)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary).padding(.leading, 2)
                Text("(\(count))").font(.caption).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

struct MiniStars: View {
    let value: Double
    let count: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { s in
                Image(systemName: Double(s) <= value.rounded() ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(Double(s) <= value ? Color(hex: "#FFD60A") : Palette.textTertiary)
            }
            Text(String(format: "%.1f", value)).font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            Text("(\(count))").font(.caption2).foregroundStyle(Palette.textTertiary)
        }
    }
}

struct DishSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Palette.cardAlt).frame(height: 160).modifier(Shimmer())
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(height: 16, width: 180)
                SkeletonBlock(height: 12, width: 240)
                SkeletonBlock(height: 16, width: 120)
            }
            .padding(16)
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
