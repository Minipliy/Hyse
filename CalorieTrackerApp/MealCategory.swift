import Foundation

struct MealCategory: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var systemKey: String?
    var order: Int
    /// Orientierungswert; Prozent hat Vorrang, wenn gesetzt.
    var targetPercentage: Double?
    var targetCalories: Double?
    var limitPercentage: Double?
    var limitCalories: Double?
    var enforceLimit: Bool

    init(id: UUID = UUID(), name: String, systemKey: String? = nil, order: Int, targetPercentage: Double? = nil, targetCalories: Double? = nil, limitPercentage: Double? = nil, limitCalories: Double? = nil, enforceLimit: Bool = false) {
        self.id = id
        self.name = name
        self.systemKey = systemKey
        self.order = order
        self.targetPercentage = targetPercentage
        self.targetCalories = targetCalories
        self.limitPercentage = limitPercentage
        self.limitCalories = limitCalories
        self.enforceLimit = enforceLimit
    }

    enum CodingKeys: String, CodingKey { case id, name, systemKey, order, targetPercentage, targetCalories, limitPercentage, limitCalories, enforceLimit }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Category"
        systemKey = try c.decodeIfPresent(String.self, forKey: .systemKey) ?? Self.legacySystemKey(for: name)
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        targetPercentage = try c.decodeIfPresent(Double.self, forKey: .targetPercentage)
        targetCalories = try c.decodeIfPresent(Double.self, forKey: .targetCalories)
        limitPercentage = try c.decodeIfPresent(Double.self, forKey: .limitPercentage)
        limitCalories = try c.decodeIfPresent(Double.self, forKey: .limitCalories)
        enforceLimit = try c.decodeIfPresent(Bool.self, forKey: .enforceLimit) ?? false
    }

    func target(for dailyGoal: Double) -> Double? { targetPercentage.map { dailyGoal * $0 / 100 } ?? targetCalories }
    func limit(for dailyGoal: Double) -> Double? { limitPercentage.map { dailyGoal * $0 / 100 } ?? limitCalories }

    var localizedName: String {
        guard let key = resolvedSystemKey else { return name }
        return LanguageStore.localizedString("meal.\(key)")
    }

    var storageKey: String { resolvedSystemKey ?? name }

    private var resolvedSystemKey: String? {
        systemKey.flatMap(Self.legacySystemKey(for:)) ?? systemKey ?? Self.legacySystemKey(for: name)
    }

    nonisolated static func legacySystemKey(for value: String) -> String? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "frühstück", "breakfast", "ui.breakfast", "meal.breakfast": "breakfast"
        case "mittag", "mittagessen", "lunch", "ui.lunch", "meal.lunch": "lunch"
        case "abendbrot", "abendessen", "dinner", "ui.dinner", "meal.dinner": "dinner"
        case "snack", "snacks", "ui.snacks", "meal.snacks": "snacks"
        default: nil
        }
    }
}
