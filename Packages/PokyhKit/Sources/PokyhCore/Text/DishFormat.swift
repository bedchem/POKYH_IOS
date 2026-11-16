import Foundation

/// Price and energy of a dish, written the way the app's language writes them.
public enum DishFormat {
    /// "4,50 €" in German and Italian, "€4.50" in English. Without a currency just the amount.
    public static func price(_ value: Double, currency: String?, lang: Lang) -> String {
        let locale = Locale(identifier: lang.rawValue)
        guard let currency else {
            return value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        }
        return value.formatted(.currency(code: currency).locale(locale))
    }

    /// "640 kcal".
    public static func energy(_ kilocalories: Double, lang: Lang) -> String {
        Measurement(value: kilocalories.rounded(), unit: UnitEnergy.kilocalories)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(Locale(identifier: lang.rawValue)))
    }
}
