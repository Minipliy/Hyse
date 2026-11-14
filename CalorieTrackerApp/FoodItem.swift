import Foundation

nonisolated enum FoodUnit: String, Codable, CaseIterable, Sendable {
    case gram = "g"
    case milliliter = "ml"
    case ounce = "oz"
    case fluidOunce = "fl oz"

    var localizationKey: String {
        switch self {
        case .gram: "ui.grams_g"
        case .milliliter: "ui.millilitres_ml"
        case .ounce: "unit.ounce_weight"
        case .fluidOunce: "unit.fluid_ounce"
        }
    }

    var isVolume: Bool { self == .milliliter || self == .fluidOunce }
    static let weightUnits: [FoodUnit] = [.gram, .ounce]
    static let volumeUnits: [FoodUnit] = [.milliliter, .fluidOunce]
    /// Metric nutrition labels conventionally use 100 g/ml, while US labels
    /// are much easier to enter and understand per single ounce.
    var nutritionReferenceAmount: Double {
        switch self {
        case .gram, .milliliter: 100
        case .ounce, .fluidOunce: 1
        }
    }

    func displayedNutrientValue(fromPer100 value: Double) -> Double {
        value * nutritionReferenceAmount / 100
    }

    func per100NutrientValue(fromDisplayed value: Double) -> Double {
        value * 100 / nutritionReferenceAmount
    }

    func convertedNutrientDisplayValue(_ value: Double, to target: FoodUnit) -> Double {
        if let amountInSourceUnit = target.converted(target.nutritionReferenceAmount, to: self) {
            return value / nutritionReferenceAmount * amountInSourceUnit
        }
        // Weight-to-volume density is unknown. Preserve the entered density per
        // selected reference instead of accidentally multiplying it by 100.
        return value * target.nutritionReferenceAmount / nutritionReferenceAmount
    }

    /// The amount a nutrition label is expressed for in the food's own unit.
    /// This keeps list rows and editor labels in sync for metric and ounce
    /// based foods alike.
    var nutritionReferenceLabel: String {
        "\(Int(nutritionReferenceAmount)) \(rawValue)"
    }

    private var canonicalFactor: Double {
        switch self {
        case .gram, .milliliter: 1
        case .ounce: 28.349_523_125
        case .fluidOunce: 29.573_529_562_5
        }
    }

    func converted(_ amount: Double, to target: FoodUnit) -> Double? {
        guard isVolume == target.isVolume else { return nil }
        return amount * canonicalFactor / target.canonicalFactor
    }
}

nonisolated enum GlobalModerationStatus: String, Codable, Sendable {
    case pending, approved, rejected
}

nonisolated struct CalculatedNutrients: Codable, Equatable, Sendable {
    let kcal: Double
    let carbs: Double
    let protein: Double
    let fat: Double
    let sugar: Double
    let fiber: Double
    let saturatedFat: Double
    let salt: Double

    static let zero = CalculatedNutrients(
        kcal: 0, carbs: 0, protein: 0, fat: 0,
        sugar: 0, fiber: 0, saturatedFat: 0, salt: 0
    )

    func scaled(by factor: Double) -> CalculatedNutrients {
        CalculatedNutrients(
            kcal: kcal * factor,
            carbs: carbs * factor,
            protein: protein * factor,
            fat: fat * factor,
            sugar: sugar * factor,
            fiber: fiber * factor,
            saturatedFat: saturatedFat * factor,
            salt: salt * factor
        )
    }
}

nonisolated enum FoodAmountLimit {
    /// More than a metric ton in a single food entry is an input error.
    static let maximumBaseAmount = 1_000_000.0

    static func accepts(_ amount: Double) -> Bool {
        amount.isFinite && amount > 0 && amount <= maximumBaseAmount
    }
}

nonisolated struct FoodItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// Optional reviewed German catalogue name. Personal foods keep using
    /// `name` in the language entered by the user.
    var nameDE: String?
    var brand: String?
    /// PocketBase relation to the reusable global brand. `brand` remains a
    /// display snapshot so existing/offline records keep their label.
    var brandRecordID: String?
    var kcalPer100g: Double
    var carbsPer100g: Double
    var proteinPer100g: Double
    var fatPer100g: Double
    var sugarPer100g: Double
    var fiberPer100g: Double
    var saturatedFatPer100g: Double
    var saltPer100g: Double
    var micronutrients: MicronutrientProfile?
    var barcode: String?
    /// Provenance for data imported into a private food record.
    var externalSource: String?
    var externalSourceID: String?
    var externalFetchedAt: Date?
    var isFavorite: Bool
    var globalRecordID: String?
    var globalCreatorID: String?
    var globalModerationStatus: GlobalModerationStatus?
    var globalSubmissionID: String?
    var globalRejectionReason: String?
    /// Local retry marker for the independent global catalogue workflow.
    var globalSubmissionPending: Bool

    /// Einheit, in der die "pro 100"-Werte angegeben sind (Gramm oder Milliliter).
    var unit: FoodUnit
    /// Optionale definierte Portionsgröße in `unit` (z. B. 20 g für "1 Möhre").
    var servingSizeAmount: Double?
    /// Named portions. The legacy servingSizeAmount remains readable and is
    /// migrated into one default portion when older records are decoded.
    var portions: [FoodPortion]
    /// Kennzeichnet Obst, dessen Zucker als Fruchtzucker statt als zugesetzter Zucker gilt.
    var isFruit: Bool

    /// Nutrition is persisted canonically per 100 g. These values express it
    /// in the reference amount shown everywhere in the UI (100 g/ml or 1 oz).
    var kcalPerNutritionReference: Double { unit.displayedNutrientValue(fromPer100: kcalPer100g) }
    var carbsPerNutritionReference: Double { unit.displayedNutrientValue(fromPer100: carbsPer100g) }
    var proteinPerNutritionReference: Double { unit.displayedNutrientValue(fromPer100: proteinPer100g) }
    var fatPerNutritionReference: Double { unit.displayedNutrientValue(fromPer100: fatPer100g) }

    init(
        id: UUID = UUID(),
        name: String,
        nameDE: String? = nil,
        brand: String? = nil,
        brandRecordID: String? = nil,
        kcalPer100g: Double,
        carbsPer100g: Double = 0.0,
        proteinPer100g: Double = 0.0,
        fatPer100g: Double = 0.0,
        sugarPer100g: Double = 0.0,
        fiberPer100g: Double = 0.0,
        saturatedFatPer100g: Double = 0.0,
        saltPer100g: Double = 0.0,
        micronutrients: MicronutrientProfile? = nil,
        barcode: String? = nil,
        externalSource: String? = nil,
        externalSourceID: String? = nil,
        externalFetchedAt: Date? = nil,
        isFavorite: Bool = false,
        globalRecordID: String? = nil,
        globalCreatorID: String? = nil,
        globalModerationStatus: GlobalModerationStatus? = nil,
        globalSubmissionID: String? = nil,
        globalRejectionReason: String? = nil,
        globalSubmissionPending: Bool = false,
        unit: FoodUnit = .gram,
        servingSizeAmount: Double? = nil,
        portions: [FoodPortion] = [],
        isFruit: Bool = false
    ) {
        self.id = id
        self.name = name
        self.nameDE = nameDE
        self.brand = brand
        self.brandRecordID = brandRecordID
        self.kcalPer100g = kcalPer100g
        self.carbsPer100g = carbsPer100g
        self.proteinPer100g = proteinPer100g
        self.fatPer100g = fatPer100g
        self.sugarPer100g = sugarPer100g
        self.fiberPer100g = fiberPer100g
        self.saturatedFatPer100g = saturatedFatPer100g
        self.saltPer100g = saltPer100g
        self.micronutrients = micronutrients
        self.barcode = barcode
        self.externalSource = externalSource
        self.externalSourceID = externalSourceID
        self.externalFetchedAt = externalFetchedAt
        self.isFavorite = isFavorite
        self.globalRecordID = globalRecordID
        self.globalCreatorID = globalCreatorID
        self.globalModerationStatus = globalModerationStatus
        self.globalSubmissionID = globalSubmissionID
        self.globalRejectionReason = globalRejectionReason
        self.globalSubmissionPending = globalSubmissionPending
        self.unit = unit
        var normalizedPortions = portions.normalized(defaultUnit: unit)
        if normalizedPortions.isEmpty, let legacy = servingSizeAmount, legacy > 0 {
            normalizedPortions = [FoodPortion(id: Self.legacyPortionID(foodID: id), nameKey: "serving", customName: "", amount: legacy, unit: unit, isDefault: true, createdAt: .distantPast, updatedAt: .distantPast)]
        }
        self.portions = normalizedPortions
        self.servingSizeAmount = normalizedPortions.first(where: \.isDefault)?.baseAmount(in: unit) ?? servingSizeAmount
        self.isFruit = isFruit
    }

    /// Berechnet die Nährwerte für eine gegebene Menge in der Einheit des Lebensmittels (g oder ml).
    func calculatedValues(forGrams grams: Double) -> CalculatedNutrients {
        let factor = grams / 100.0
        return CalculatedNutrients(
            kcal: (kcalPer100g * factor).rounded(toPlaces: 1),
            carbs: (carbsPer100g * factor).rounded(toPlaces: 1),
            protein: (proteinPer100g * factor).rounded(toPlaces: 1),
            fat: (fatPer100g * factor).rounded(toPlaces: 1),
            sugar: (sugarPer100g * factor).rounded(toPlaces: 1),
            fiber: (fiberPer100g * factor).rounded(toPlaces: 1),
            saturatedFat: (saturatedFatPer100g * factor).rounded(toPlaces: 1),
            salt: (saltPer100g * factor).rounded(toPlaces: 1)
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, nameDE, brand, brandRecordID, kcalPer100g, carbsPer100g, proteinPer100g, fatPer100g, sugarPer100g, fiberPer100g, saturatedFatPer100g, saltPer100g, micronutrients, barcode, externalSource, externalSourceID, externalFetchedAt, isFavorite, globalRecordID, globalCreatorID, globalModerationStatus, globalSubmissionID, globalRejectionReason, globalSubmissionPending
        case unit, servingSizeAmount, portions, isFruit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unbenannt"
        nameDE = try c.decodeIfPresent(String.self, forKey: .nameDE)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        brandRecordID = try c.decodeIfPresent(String.self, forKey: .brandRecordID)
        kcalPer100g = try c.decodeIfPresent(Double.self, forKey: .kcalPer100g) ?? 0
        carbsPer100g = try c.decodeIfPresent(Double.self, forKey: .carbsPer100g) ?? 0
        proteinPer100g = try c.decodeIfPresent(Double.self, forKey: .proteinPer100g) ?? 0
        fatPer100g = try c.decodeIfPresent(Double.self, forKey: .fatPer100g) ?? 0
        sugarPer100g = try c.decodeIfPresent(Double.self, forKey: .sugarPer100g) ?? 0
        fiberPer100g = try c.decodeIfPresent(Double.self, forKey: .fiberPer100g) ?? 0
        saturatedFatPer100g = try c.decodeIfPresent(Double.self, forKey: .saturatedFatPer100g) ?? 0
        saltPer100g = try c.decodeIfPresent(Double.self, forKey: .saltPer100g) ?? 0
        micronutrients = try c.decodeIfPresent(MicronutrientProfile.self, forKey: .micronutrients)
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        externalSource = try c.decodeIfPresent(String.self, forKey: .externalSource)
        externalSourceID = try c.decodeIfPresent(String.self, forKey: .externalSourceID)
        externalFetchedAt = try c.decodeIfPresent(Date.self, forKey: .externalFetchedAt)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        globalRecordID = try c.decodeIfPresent(String.self, forKey: .globalRecordID)
        globalCreatorID = try c.decodeIfPresent(String.self, forKey: .globalCreatorID)
        globalModerationStatus = try c.decodeIfPresent(GlobalModerationStatus.self, forKey: .globalModerationStatus)
        globalSubmissionID = try c.decodeIfPresent(String.self, forKey: .globalSubmissionID)
        globalRejectionReason = try c.decodeIfPresent(String.self, forKey: .globalRejectionReason)
        globalSubmissionPending = try c.decodeIfPresent(Bool.self, forKey: .globalSubmissionPending) ?? false
        unit = try c.decodeIfPresent(FoodUnit.self, forKey: .unit) ?? .gram
        servingSizeAmount = try c.decodeIfPresent(Double.self, forKey: .servingSizeAmount)
        portions = (try c.decodeIfPresent([FoodPortion].self, forKey: .portions) ?? []).normalized(defaultUnit: unit)
        if portions.isEmpty, let legacy = servingSizeAmount, legacy > 0 {
            portions = [FoodPortion(id: Self.legacyPortionID(foodID: id), nameKey: "serving", customName: "", amount: legacy, unit: unit, isDefault: true, createdAt: .distantPast, updatedAt: .distantPast)]
        } else if let defaultPortion = portions.first(where: \.isDefault) {
            servingSizeAmount = defaultPortion.baseAmount(in: unit)
        }
        isFruit = try c.decodeIfPresent(Bool.self, forKey: .isFruit) ?? false
    }

    var sortedPortions: [FoodPortion] { portions.sorted { $0.sortOrder < $1.sortOrder } }
    var defaultPortion: FoodPortion? { portions.first(where: \.isDefault) ?? portions.sorted { $0.sortOrder < $1.sortOrder }.first }
    var defaultPortionBaseAmount: Double? { defaultPortion?.baseAmount(in: unit) ?? servingSizeAmount }

    @MainActor func displayName(using language: LanguageStore) -> String {
        guard language.isGerman,
              let localized = nameDE?.trimmingCharacters(in: .whitespacesAndNewlines),
              !localized.isEmpty else { return name }
        return localized
    }

    private static func legacyPortionID(foodID: UUID) -> UUID {
        var value = foodID.uuid
        value.15 ^= 0xA5
        return UUID(uuid: value)
    }
}

nonisolated extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
