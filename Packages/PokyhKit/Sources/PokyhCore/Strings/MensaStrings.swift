// Generated from the Android app's core/i18n, then edited by hand. Keep in sync.

public struct MensaStrings: Sendable {
    public let today: String
    public let tomorrow: String
    public let thisWeek: String
    public let nextWeek: String
    public let fromDate: @Sendable (String) -> String
    public let allDays: String
    public let rateAndComment: String
    public let noRatingYet: String
    public let ratingOne: String
    public let ratingMany: @Sendable (Int) -> String
    public let emptyTitle: String
    public let emptySubtitle: String
    public let loadError: String
    public let noMensaTitle: String
    public let noMensaText: String
    public let loading: String
    public let yourRating: String
    public let rate: String
    public let rated: @Sendable (Int) -> String
    public let nutrition: String
    public let calories: String
    public let protein: String
    public let carbs: String
    public let fat: String
    public let allergens: String
    public let price: String
    public let dishNotFound: String
    public let offlineRating: String
    public let dish: String
    public let rating: String
    public let ratingNotSaved: String
    public let carbsShort: String
    public let per100: String
    public let estimated: String
    public let estimatedNote: String
    public let starsLabel: @Sendable (Int) -> String
    public let rateLabels: [String]
    public let carbsLong: String
    public let dayPattern: String
}


extension MensaStrings {
    static let de = MensaStrings(
        today: "Heute",
        tomorrow: "Morgen",
        thisWeek: "Diese Woche",
        nextWeek: "Nächste Woche",
        fromDate: { "Ab \($0)" },
        allDays: "Der ganze Plan",
        rateAndComment: "Bewerten und kommentieren",
        noRatingYet: "Noch keine Bewertung",
        ratingOne: "1 Bewertung",
        ratingMany: { "\($0) Bewertungen" },
        emptyTitle: "Kein Speiseplan",
        emptySubtitle: "Es gibt aktuell nichts bei der Mensa.",
        loadError: "Fehler beim Laden der Speisekarte",
        noMensaTitle: "Deine Schule hat in POKYH keine Mensa.",
        noMensaText: "Sobald es für deine Schule einen Speiseplan gibt, steht er hier.",
        loading: "Der Speiseplan wird geladen …",
        yourRating: "Deine Bewertung",
        rate: "Bewerten",
        rated: { "\($0) von 5 Sternen" },
        nutrition: "Nährwerte",
        calories: "Kalorien",
        protein: "Eiweiß",
        carbs: "Kohlenhydrate",
        fat: "Fett",
        allergens: "Allergene",
        price: "Preis",
        dishNotFound: "Gericht nicht gefunden",
        offlineRating: "Offline – Bewerten geht wieder mit Internet",
        dish: "Gericht",
        rating: "Bewertung",
        ratingNotSaved: "Du bist offline – die Bewertung wurde auf diesem Gerät noch nicht gespeichert.",
        carbsShort: "KH",
        per100: "Pro 100 g",
        estimated: "Geschätzt",
        estimatedNote: "Geschätzte Angaben pro 100 g — keine Laborwerte. Die tatsächliche Portion kann abweichen.",
        starsLabel: { ($0 == 1) ? "1 Stern" : "\($0) Sterne" },
        rateLabels: ["Naja", "Geht so", "Gut", "Sehr gut", "Mega"],
        carbsLong: "Kohlenhydrate",
        dayPattern: "EEEE, d. MMMM",
    )
}

extension MensaStrings {
    static let it = MensaStrings(
        today: "Oggi",
        tomorrow: "Domani",
        thisWeek: "Questa settimana",
        nextWeek: "Settimana prossima",
        fromDate: { "Dal \($0)" },
        allDays: "Tutto il menù",
        rateAndComment: "Valuta e commenta",
        noRatingYet: "Ancora nessuna valutazione",
        ratingOne: "1 valutazione",
        ratingMany: { "\($0) valutazioni" },
        emptyTitle: "Nessun menù",
        emptySubtitle: "Al momento non c’è nulla in mensa.",
        loadError: "Errore durante il caricamento del menù",
        noMensaTitle: "La tua scuola non ha una mensa su POKYH.",
        noMensaText: "Appena ci sarà un menù per la tua scuola, lo troverai qui.",
        loading: "Caricamento del menù …",
        yourRating: "La tua valutazione",
        rate: "Valuta",
        rated: { "\($0) stelle su 5" },
        nutrition: "Valori nutrizionali",
        calories: "Calorie",
        protein: "Proteine",
        carbs: "Carboidrati",
        fat: "Grassi",
        allergens: "Allergeni",
        price: "Prezzo",
        dishNotFound: "Piatto non trovato",
        offlineRating: "Offline – potrai valutare di nuovo con Internet",
        dish: "Piatto",
        rating: "Valutazione",
        ratingNotSaved: "Sei offline – la valutazione non è ancora stata salvata su questo dispositivo.",
        carbsShort: "Carb.",
        per100: "Per 100 g",
        estimated: "Stimato",
        estimatedNote: "Valori stimati per 100 g — non di laboratorio. La porzione effettiva può variare.",
        starsLabel: { ($0 == 1) ? "1 stella" : "\($0) stelle" },
        rateLabels: ["Mah", "Così così", "Buono", "Molto buono", "Top"],
        carbsLong: "Carboidrati",
        dayPattern: "EEEE d MMMM",
    )
}

extension MensaStrings {
    static let en = MensaStrings(
        today: "Today",
        tomorrow: "Tomorrow",
        thisWeek: "This week",
        nextWeek: "Next week",
        fromDate: { "From \($0)" },
        allDays: "The whole plan",
        rateAndComment: "Rate and comment",
        noRatingYet: "No ratings yet",
        ratingOne: "1 rating",
        ratingMany: { "\($0) ratings" },
        emptyTitle: "No menu",
        emptySubtitle: "There’s nothing at the cafeteria right now.",
        loadError: "Failed to load the menu",
        noMensaTitle: "Your school has no cafeteria on POKYH.",
        noMensaText: "As soon as there is a menu for your school, you will find it here.",
        loading: "Loading the menu …",
        yourRating: "Your rating",
        rate: "Rate",
        rated: { "\($0) out of 5 stars" },
        nutrition: "Nutrition",
        calories: "Calories",
        protein: "Protein",
        carbs: "Carbohydrates",
        fat: "Fat",
        allergens: "Allergens",
        price: "Price",
        dishNotFound: "Dish not found",
        offlineRating: "Offline – rating works again with internet",
        dish: "Dish",
        rating: "Rating",
        ratingNotSaved: "You’re offline – the rating hasn’t been saved on this device yet.",
        carbsShort: "Carbs",
        per100: "Per 100 g",
        estimated: "Estimated",
        estimatedNote: "Estimated values per 100 g — not lab results. The actual portion may differ.",
        starsLabel: { ($0 == 1) ? "1 star" : "\($0) stars" },
        rateLabels: ["Meh", "Okay", "Good", "Very good", "Amazing"],
        carbsLong: "Carbohydrates",
        dayPattern: "EEEE, d MMMM",
    )
}
