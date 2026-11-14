import Foundation

nonisolated enum FoodBrandStatus: String, Codable, Sendable {
    case pending, approved, rejected, merged
}

nonisolated struct FoodBrand: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var normalizedName: String
    var slug: String
    var aliases: [String]
    var status: FoodBrandStatus
    var createdBy: String

    enum CodingKeys: String, CodingKey {
        case id, name, slug, aliases, status
        case normalizedName = "normalized_name"
        case createdBy = "created_by"
    }
}

nonisolated enum FoodPortionStatus: String, Codable, Sendable {
    case `private`, pending, approved, rejected
}

nonisolated struct FoodPortion: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var nameKey: String?
    var customName: String
    var amount: Double
    var unit: FoodUnit
    var gramEquivalent: Double?
    var sortOrder: Int
    var isDefault: Bool
    var status: FoodPortionStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        nameKey: String? = nil,
        customName: String,
        amount: Double,
        unit: FoodUnit,
        gramEquivalent: Double? = nil,
        sortOrder: Int = 0,
        isDefault: Bool = false,
        status: FoodPortionStatus = .private,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.nameKey = nameKey
        self.customName = customName
        self.amount = amount
        self.unit = unit
        self.gramEquivalent = gramEquivalent
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    @MainActor func displayName(using language: LanguageStore) -> String {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        guard let nameKey, !nameKey.isEmpty else { return language.text("food_portion.portion") }
        return language.text("food_portion.name.\(nameKey)")
    }

    /// Weight or volume represented by exactly one portion in the food's
    /// canonical unit. A gram equivalent is only valid for mass units.
    func baseAmount(in baseUnit: FoodUnit) -> Double? {
        if let converted = unit.converted(amount, to: baseUnit), converted > 0 {
            return converted
        }
        guard let gramEquivalent, gramEquivalent > 0 else { return nil }
        return FoodUnit.gram.converted(gramEquivalent, to: baseUnit)
    }
}

nonisolated extension Array where Element == FoodPortion {
    func normalized(defaultUnit: FoodUnit) -> [FoodPortion] {
        var seenNames = Set<String>()
        var kept: [FoodPortion] = []
        for (index, source) in sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() where source.amount > 0 {
            var value = source
            let key = (value.customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? value.nameKey ?? ""
                : value.customName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !key.isEmpty, seenNames.insert(key).inserted else { continue }
            // Never imply a mass/volume conversion without an explicit gram
            // equivalent. The portion itself may still use the food base unit.
            if value.baseAmount(in: defaultUnit) == nil { continue }
            value.sortOrder = index
            kept.append(value)
        }
        if !kept.isEmpty {
            let selected = kept.firstIndex(where: \.isDefault) ?? 0
            for index in kept.indices { kept[index].isDefault = index == selected }
        }
        return kept
    }
}
