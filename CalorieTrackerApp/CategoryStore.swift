import Foundation
import Combine
import SwiftUI

final class CategoryStore: ObservableObject {
    @Published private(set) var categories: [MealCategory] = []
    var onLocalChange: (() -> Void)?

    private let storageKey = "meal_categories_v1"

    init() {
        load()
        if categories.isEmpty {
            seedDefaults()
        } else {
            migrateUntouchedDefaultCategoriesIfNeeded()
        }
    }

    func addCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newOrder = (categories.map { $0.order }.max() ?? 0) + 1
        let cat = MealCategory(name: trimmed, order: newOrder)
        categories.append(cat)
        save()
    }

    func renameCategory(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = categories.firstIndex(where: { $0.id == id }) {
            categories[index].name = trimmed
            categories[index].systemKey = nil
            save()
        }
    }

    func updateCategory(_ category: MealCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
        save()
    }

    func deleteCategory(at offsets: IndexSet) {
        categories.remove(atOffsets: offsets)
        reindexOrders()
        save()
    }

    func deleteCategory(id: UUID) {
        categories.removeAll { $0.id == id }
        reindexOrders()
        save()
    }

    func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        reindexOrders()
        save()
    }

    /// Setzt nur die bekannten Standard-Mahlzeiten zurück und erhält deren IDs,
    /// damit bereits gespeicherte Einträge weiter korrekt zugeordnet bleiben.
    func resetStandardTargets() {
        let defaults: [String: Double] = ["breakfast": 30, "lunch": 40, "dinner": 25, "snacks": 5]
        for index in categories.indices {
            guard let key = categories[index].systemKey ?? MealCategory.legacySystemKey(for: categories[index].name), let target = defaults[key] else { continue }
            categories[index].systemKey = key
            categories[index].targetPercentage = target
            categories[index].targetCalories = nil
            categories[index].limitPercentage = nil
            categories[index].limitCalories = nil
        }
        save()
    }

    private func reindexOrders() {
        for index in categories.indices {
            categories[index].order = index
        }
    }

    private func seedDefaults() {
        categories = [
            MealCategory(name: "ui.breakfast", systemKey: "breakfast", order: 0, targetPercentage: 30),
            MealCategory(name: "ui.lunch", systemKey: "lunch", order: 1, targetPercentage: 40),
            MealCategory(name: "ui.dinner", systemKey: "dinner", order: 2, targetPercentage: 25),
            MealCategory(name: "ui.snacks", systemKey: "snacks", order: 3, targetPercentage: 5)
        ]
        save()
    }

    /// Ergänzt die neuen Orientierungswerte auch bei Installationen, die noch die
    /// ursprünglichen vier Standardkategorien ohne eigene Zielwerte verwenden.
    private func migrateUntouchedDefaultCategoriesIfNeeded() {
        let legacyNames = ["ui.breakfast", "Mittag", "Abendbrot", "ui.snacks"]
        let currentNames = categories.sorted { $0.order < $1.order }.map(\.name)
        let hasNoCustomTargets = categories.allSatisfy {
            $0.targetPercentage == nil && $0.targetCalories == nil && $0.limitPercentage == nil && $0.limitCalories == nil
        }
        guard currentNames == legacyNames, hasNoCustomTargets else { return }

        let defaults: [(name: String, percentage: Double)] = [
            ("ui.breakfast", 30), ("ui.lunch", 40), ("Abendbrot", 25), ("ui.snacks", 5)
        ]
        for index in categories.indices {
            categories[index].name = defaults[index].name
            categories[index].systemKey = ["breakfast", "lunch", "dinner", "snacks"][index]
            categories[index].targetPercentage = defaults[index].percentage
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: storageKey)
            onLocalChange?()
        }
    }

    func applySyncedCategories(_ values: [MealCategory]) {
        guard !values.isEmpty else { return }
        categories = values.sorted { $0.order < $1.order }
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([MealCategory].self, from: data) else {
            return
        }
        categories = decoded.sorted { $0.order < $1.order }
    }
}
