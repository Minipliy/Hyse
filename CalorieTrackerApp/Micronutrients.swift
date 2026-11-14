import Foundation

nonisolated enum Micronutrient: String, CaseIterable, Codable, Sendable {
    case vitaminA, vitaminC, vitaminD, vitaminE, vitaminK, vitaminB6, vitaminB12, folate
    case calcium, iron, magnesium, potassium, zinc, sodium, iodine, selenium

    var unit: String {
        switch self {
        case .vitaminA, .vitaminD, .vitaminK, .vitaminB12, .folate, .iodine, .selenium: "µg"
        default: "mg"
        }
    }

    var localizationKey: String { "micronutrient.\(rawValue)" }

    /// Open Food Facts normalizes its `_100g` mineral and vitamin values to grams.
    var openFoodFactsKey: String {
        switch self {
        case .vitaminA: "vitamin-a"
        case .vitaminC: "vitamin-c"
        case .vitaminD: "vitamin-d"
        case .vitaminE: "vitamin-e"
        case .vitaminK: "vitamin-k"
        case .vitaminB6: "vitamin-b6"
        case .vitaminB12: "vitamin-b12"
        case .folate: "vitamin-b9"
        default: rawValue
        }
    }

    var gramsToDisplayUnit: Double { unit == "µg" ? 1_000_000 : 1_000 }
    // Foods may be stored per 100 oz/fl oz; that reference can weigh ~3 kg.
    var maximumPer100g: Double { unit == "µg" ? 3_100_000_000 : 3_100_000 }
}

nonisolated enum MicronutrientSource: String, Codable, Sendable {
    case database, estimated, manual, mixed
}

/// Only measured, label-reported or explicitly estimated values are present.
/// Missing nutrients stay unknown; they are never silently counted as zero.
nonisolated struct MicronutrientProfile: Codable, Hashable, Sendable {
    var valuesPer100g: [String: Double]
    var source: MicronutrientSource
    var sourceName: String?

    init(valuesPer100g: [String: Double], source: MicronutrientSource, sourceName: String? = nil) {
        self.valuesPer100g = valuesPer100g.filter { key, value in
            guard let nutrient = Micronutrient(rawValue: key) else { return false }
            return value.isFinite && value >= 0 && value <= nutrient.maximumPer100g
        }
        self.source = source
        self.sourceName = sourceName
    }

    private enum CodingKeys: String, CodingKey { case valuesPer100g, source, sourceName }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            valuesPer100g: try values.decodeIfPresent([String: Double].self, forKey: .valuesPer100g) ?? [:],
            source: try values.decodeIfPresent(MicronutrientSource.self, forKey: .source) ?? .manual,
            sourceName: try values.decodeIfPresent(String.self, forKey: .sourceName)
        )
    }

    var isEmpty: Bool { valuesPer100g.isEmpty }

    /// Preserve user-entered values. A newer OFF result replaces only values
    /// that were previously imported from OFF; absent fields stay unknown.
    func addingOpenFoodFacts(_ imported: MicronutrientProfile) -> MicronutrientProfile {
        guard !imported.isEmpty else { return self }
        var merged = valuesPer100g
        let replaceImported = source == .database && sourceName == "Open Food Facts"
        for (key, value) in imported.valuesPer100g where replaceImported || merged[key] == nil {
            merged[key] = value
        }
        if merged == valuesPer100g { return self }
        return MicronutrientProfile(
            valuesPer100g: merged,
            source: replaceImported ? .database : .mixed,
            sourceName: replaceImported ? "Open Food Facts" : sourceName
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(source)
        hasher.combine(sourceName)
        for key in valuesPer100g.keys.sorted() {
            hasher.combine(key)
            hasher.combine(valuesPer100g[key])
        }
    }

    func amount(_ nutrient: Micronutrient, for amount: Double) -> Double? {
        guard amount.isFinite, amount >= 0, let per100g = valuesPer100g[nutrient.rawValue] else { return nil }
        return per100g * amount / 100
    }

    var serverValue: [String: Any] {
        ["valuesPer100g": valuesPer100g, "source": source.rawValue, "sourceName": sourceName ?? ""]
    }

    static func combined(_ ingredients: [(profile: MicronutrientProfile?, grams: Double)], totalGrams: Double) -> MicronutrientProfile? {
        guard totalGrams.isFinite, totalGrams > 0 else { return nil }
        var combined: [String: Double] = [:]
        for nutrient in Micronutrient.allCases {
            // If any ingredient is unknown, a complete recipe total is unknown.
            guard ingredients.allSatisfy({ $0.grams <= 0 || $0.profile?.valuesPer100g[nutrient.rawValue] != nil }) else { continue }
            let amount = ingredients.reduce(0.0) { total, ingredient in
                total + (ingredient.profile?.amount(nutrient, for: ingredient.grams) ?? 0)
            }
            combined[nutrient.rawValue] = amount / totalGrams * 100
        }
        guard !combined.isEmpty else { return nil }
        return MicronutrientProfile(valuesPer100g: combined, source: .mixed)
    }
}
