import Foundation

nonisolated struct CalorieEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var remoteID: String?
    var foodItemId: UUID?
    var recipeId: UUID?
    var globalFoodRecordID: String?
    var userRecipeRecordID: String?
    var globalRecipeRecordID: String?
    var name: String
    var grams: Double
    var categoryId: UUID
    var categoryName: String
    /// Optional snapshot of the named portion used for this historical entry.
    var portionName: String?
    var portionID: UUID?
    var portionCount: Double?

    /// Einheit der `grams`-Menge (g oder ml) – rein informativ für die Anzeige.
    var unit: FoodUnit

    // Nährwert-Snapshot per 100g/100ml
    var kcalPer100g: Double
    var carbsPer100g: Double
    var proteinPer100g: Double
    var fatPer100g: Double
    var addedSugarPer100g: Double
    var fruitSugarPer100g: Double
    var fiberPer100g: Double
    var saturatedFatPer100g: Double
    var saltPer100g: Double
    var micronutrients: MicronutrientProfile?

    var date: Date

    init(
        id: UUID = UUID(),
        remoteID: String? = nil,
        foodItemId: UUID? = nil,
        recipeId: UUID? = nil,
        globalFoodRecordID: String? = nil,
        userRecipeRecordID: String? = nil,
        globalRecipeRecordID: String? = nil,
        name: String,
        grams: Double,
        categoryId: UUID,
        categoryName: String,
        portionName: String? = nil,
        portionID: UUID? = nil,
        portionCount: Double? = nil,
        unit: FoodUnit = .gram,
        kcalPer100g: Double,
        carbsPer100g: Double = 0.0,
        proteinPer100g: Double = 0.0,
        fatPer100g: Double = 0.0,
        addedSugarPer100g: Double = 0.0,
        fruitSugarPer100g: Double = 0.0,
        fiberPer100g: Double = 0.0,
        saturatedFatPer100g: Double = 0.0,
        saltPer100g: Double = 0.0,
        micronutrients: MicronutrientProfile? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.remoteID = remoteID
        self.foodItemId = foodItemId
        self.recipeId = recipeId
        self.globalFoodRecordID = globalFoodRecordID
        self.userRecipeRecordID = userRecipeRecordID
        self.globalRecipeRecordID = globalRecipeRecordID
        self.name = name
        self.grams = grams
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.portionName = portionName
        self.portionID = portionID
        self.portionCount = portionCount.flatMap { count in
            count.isFinite && count > 0 ? count : nil
        }
        self.unit = unit
        self.kcalPer100g = kcalPer100g
        self.carbsPer100g = carbsPer100g
        self.proteinPer100g = proteinPer100g
        self.fatPer100g = fatPer100g
        self.addedSugarPer100g = addedSugarPer100g
        self.fruitSugarPer100g = fruitSugarPer100g
        self.fiberPer100g = fiberPer100g
        self.saturatedFatPer100g = saturatedFatPer100g
        self.saltPer100g = saltPer100g
        self.micronutrients = micronutrients
        self.date = date
    }

    // Dynamische Gesamtwerte skaliert auf die Mengenangabe
    var kcal: Double { (kcalPer100g * grams / 100.0).rounded(toPlaces: 1) }
    var carbs: Double { (carbsPer100g * grams / 100.0).rounded(toPlaces: 1) }
    var protein: Double { (proteinPer100g * grams / 100.0).rounded(toPlaces: 1) }
    var fat: Double { (fatPer100g * grams / 100.0).rounded(toPlaces: 1) }
    var addedSugar: Double { (addedSugarPer100g * grams / 100.0).rounded(toPlaces: 1) }
    var fruitSugar: Double { (fruitSugarPer100g * grams / 100.0).rounded(toPlaces: 1) }
    /// Gesamtzucker = zugesetzter Zucker + Fruchtzucker
    var sugar: Double { (addedSugar + fruitSugar).rounded(toPlaces: 1) }
    var fiber: Double { (fiberPer100g * grams / 100.0).rounded(toPlaces: 1) }
    var saturatedFat: Double { (saturatedFatPer100g * grams / 100.0).rounded(toPlaces: 1) }
    var salt: Double { (saltPer100g * grams / 100.0).rounded(toPlaces: 1) }
    func micronutrientAmount(_ nutrient: Micronutrient) -> Double? { micronutrients?.amount(nutrient, for: grams) }

    enum CodingKeys: String, CodingKey {
        case id, remoteID, foodItemId, recipeId, globalFoodRecordID, userRecipeRecordID, globalRecipeRecordID, name, grams, categoryId, categoryName, portionName, portionID, portionCount, unit
        case kcalPer100g, carbsPer100g, proteinPer100g, fatPer100g
        case addedSugarPer100g, fruitSugarPer100g
        case sugarPer100g // Legacy-Schlüssel (vor Obstzucker-Unterscheidung)
        case fiberPer100g, saturatedFatPer100g, saltPer100g, micronutrients, date
        case kcal, carbs, protein, fat // Uralte Legacy-Schlüssel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.remoteID = try container.decodeIfPresent(String.self, forKey: .remoteID)
        self.foodItemId = try container.decodeIfPresent(UUID.self, forKey: .foodItemId)
        self.recipeId = try container.decodeIfPresent(UUID.self, forKey: .recipeId)
        self.globalFoodRecordID = try container.decodeIfPresent(String.self, forKey: .globalFoodRecordID)
        self.userRecipeRecordID = try container.decodeIfPresent(String.self, forKey: .userRecipeRecordID)
        self.globalRecipeRecordID = try container.decodeIfPresent(String.self, forKey: .globalRecipeRecordID)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unbenannt"
        self.grams = try container.decodeIfPresent(Double.self, forKey: .grams) ?? 100.0
        self.categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId) ?? UUID()
        self.categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName) ?? "ui.snacks"
        self.portionName = try container.decodeIfPresent(String.self, forKey: .portionName)
        self.portionID = try container.decodeIfPresent(UUID.self, forKey: .portionID)
        self.portionCount = try container.decodeIfPresent(Double.self, forKey: .portionCount).flatMap { count in
            count.isFinite && count > 0 ? count : nil
        }
        self.unit = try container.decodeIfPresent(FoodUnit.self, forKey: .unit) ?? .gram
        self.date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        self.micronutrients = try container.decodeIfPresent(MicronutrientProfile.self, forKey: .micronutrients)

        if container.contains(.kcalPer100g) {
            self.kcalPer100g = try container.decode(Double.self, forKey: .kcalPer100g)
            self.carbsPer100g = try container.decodeIfPresent(Double.self, forKey: .carbsPer100g) ?? 0.0
            self.proteinPer100g = try container.decodeIfPresent(Double.self, forKey: .proteinPer100g) ?? 0.0
            self.fatPer100g = try container.decodeIfPresent(Double.self, forKey: .fatPer100g) ?? 0.0
            self.fiberPer100g = try container.decodeIfPresent(Double.self, forKey: .fiberPer100g) ?? 0.0
            self.saturatedFatPer100g = try container.decodeIfPresent(Double.self, forKey: .saturatedFatPer100g) ?? 0.0
            self.saltPer100g = try container.decodeIfPresent(Double.self, forKey: .saltPer100g) ?? 0.0

            if container.contains(.addedSugarPer100g) || container.contains(.fruitSugarPer100g) {
                self.addedSugarPer100g = try container.decodeIfPresent(Double.self, forKey: .addedSugarPer100g) ?? 0.0
                self.fruitSugarPer100g = try container.decodeIfPresent(Double.self, forKey: .fruitSugarPer100g) ?? 0.0
            } else {
                // Migration alter Einträge: kompletter Zucker wird als "zugesetzt" übernommen,
                // da rückwirkend nicht bekannt ist, ob es sich um Obst handelte.
                let legacySugar = try container.decodeIfPresent(Double.self, forKey: .sugarPer100g) ?? 0.0
                self.addedSugarPer100g = legacySugar
                self.fruitSugarPer100g = 0.0
            }

            // Some older synchronized caches contain a valid nutrient total
            // but an empty/zero amount. Recover the original amount instead
            // of presenting an irreversible "0 g" edit form.
            if !self.grams.isFinite || self.grams <= 0 {
                let legacyKcalTotal = try container.decodeIfPresent(Double.self, forKey: .kcal)
                let legacyCarbsTotal = try container.decodeIfPresent(Double.self, forKey: .carbs)
                let legacyProteinTotal = try container.decodeIfPresent(Double.self, forKey: .protein)
                let legacyFatTotal = try container.decodeIfPresent(Double.self, forKey: .fat)
                self.grams = Self.inferredAmount(
                    total: legacyKcalTotal,
                    per100: self.kcalPer100g
                ) ?? Self.inferredAmount(
                    total: legacyCarbsTotal,
                    per100: self.carbsPer100g
                ) ?? Self.inferredAmount(
                    total: legacyProteinTotal,
                    per100: self.proteinPer100g
                ) ?? Self.inferredAmount(
                    total: legacyFatTotal,
                    per100: self.fatPer100g
                ) ?? self.grams
            }
        } else {
            let legacyKcal = try container.decodeIfPresent(Double.self, forKey: .kcal) ?? 0.0
            let legacyCarbs = try container.decodeIfPresent(Double.self, forKey: .carbs) ?? 0.0
            let legacyProtein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0.0
            let legacyFat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0.0

            let factor = self.grams > 0 ? (100.0 / self.grams) : 1.0
            self.kcalPer100g = legacyKcal * factor
            self.carbsPer100g = legacyCarbs * factor
            self.proteinPer100g = legacyProtein * factor
            self.fatPer100g = legacyFat * factor
            self.addedSugarPer100g = 0.0
            self.fruitSugarPer100g = 0.0
            self.fiberPer100g = 0.0
            self.saturatedFatPer100g = 0.0
            self.saltPer100g = 0.0
        }
    }

    private static func inferredAmount(total: Double?, per100: Double) -> Double? {
        guard let total, total.isFinite, total > 0, per100.isFinite, per100 > 0 else { return nil }
        let amount = total * 100 / per100
        return amount.isFinite && amount > 0 ? amount : nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(remoteID, forKey: .remoteID)
        try container.encodeIfPresent(foodItemId, forKey: .foodItemId)
        try container.encodeIfPresent(recipeId, forKey: .recipeId)
        try container.encodeIfPresent(globalFoodRecordID, forKey: .globalFoodRecordID)
        try container.encodeIfPresent(userRecipeRecordID, forKey: .userRecipeRecordID)
        try container.encodeIfPresent(globalRecipeRecordID, forKey: .globalRecipeRecordID)
        try container.encode(name, forKey: .name)
        try container.encode(grams, forKey: .grams)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(categoryName, forKey: .categoryName)
        try container.encodeIfPresent(portionName, forKey: .portionName)
        try container.encodeIfPresent(portionID, forKey: .portionID)
        try container.encodeIfPresent(portionCount, forKey: .portionCount)
        try container.encode(unit, forKey: .unit)
        try container.encode(kcalPer100g, forKey: .kcalPer100g)
        try container.encode(carbsPer100g, forKey: .carbsPer100g)
        try container.encode(proteinPer100g, forKey: .proteinPer100g)
        try container.encode(fatPer100g, forKey: .fatPer100g)
        try container.encode(addedSugarPer100g, forKey: .addedSugarPer100g)
        try container.encode(fruitSugarPer100g, forKey: .fruitSugarPer100g)
        try container.encode(fiberPer100g, forKey: .fiberPer100g)
        try container.encode(saturatedFatPer100g, forKey: .saturatedFatPer100g)
        try container.encode(saltPer100g, forKey: .saltPer100g)
        try container.encodeIfPresent(micronutrients, forKey: .micronutrients)
        try container.encode(date, forKey: .date)
    }
}
