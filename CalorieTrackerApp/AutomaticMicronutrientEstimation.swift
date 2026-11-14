import Foundation

/// Estimates missing profiles after a linked food has actually been logged.
/// The diary write never waits for Apple Intelligence or a network lookup.
@MainActor
final class AutomaticMicronutrientEstimation {
    private struct Request: Codable {
        let foodID: UUID
        let globalID: String?
        let scope: String
        var key: String { "\(scope):\(foodID.uuidString)" }
    }

    private var pending: [Request] = []
    private var queued = Set<String>()
    private var lastAttempt: [String: Date] = [:]
    private var worker: Task<Void, Never>?

    private func storageKey(_ scope: String) -> String { "hyse_auto_micronutrient_pending_\(scope)_v1" }

    private func storedRequests(scope: String) -> [Request] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(scope)) else { return [] }
        return (try? JSONDecoder().decode([Request].self, from: data)) ?? []
    }

    private func store(_ requests: [Request], scope: String) {
        guard let data = try? JSONEncoder().encode(requests) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(scope))
    }

    func schedule(entries: [CalorieEntry], foods: FoodStore, diary: CalorieStore, premium: PremiumAccessStore) {
        guard premium.hasNutrition,
              foods.micronutrientScopeID == diary.micronutrientScopeID else { return }
        let scope = foods.micronutrientScopeID
        var durable = storedRequests(scope: scope)
        durable.removeAll { request in foods.food(id: request.foodID)?.micronutrients?.isEmpty == false }
        for entry in entries where entry.recipeId == nil {
            guard let foodID = entry.foodItemId else { continue }
            let request = Request(foodID: foodID, globalID: entry.globalFoodRecordID, scope: scope)
            if let food = foods.food(id: foodID), food.micronutrients?.isEmpty == false { continue }
            if !durable.contains(where: { $0.key == request.key }) { durable.append(request) }
        }
        store(durable, scope: scope)
        guard AppleMicronutrientEstimator.isAvailable else { return }
        for request in durable where !queued.contains(request.key) {
            guard lastAttempt[request.key].map({ Date().timeIntervalSince($0) >= 5 * 60 }) != false else { continue }
            queued.insert(request.key)
            pending.append(request)
        }
        guard worker == nil, !pending.isEmpty else { return }
        worker = Task { [weak self, weak foods, weak diary, weak premium] in
            guard let self, let foods, let diary, let premium else { return }
            while !self.pending.isEmpty {
                let request = self.pending.removeFirst()
                let completed = await self.process(request, foods: foods, diary: diary, premium: premium)
                if completed {
                    self.store(self.storedRequests(scope: request.scope).filter { $0.key != request.key }, scope: request.scope)
                }
                self.queued.remove(request.key)
            }
            self.worker = nil
        }
    }

    private func process(_ request: Request, foods: FoodStore, diary: CalorieStore, premium: PremiumAccessStore) async -> Bool {
        guard isCurrent(request, foods: foods, diary: diary, premium: premium) else { return false }
        if foods.food(id: request.foodID) == nil, let globalID = request.globalID {
            await foods.hydrateGlobalFoods(recordIDs: [globalID])
        }
        guard isCurrent(request, foods: foods, diary: diary, premium: premium),
              var food = findFood(request, in: foods) else { return false }
        if food.micronutrients?.isEmpty == false { return true }
        lastAttempt[request.key] = Date()

        // Label/database values are preferable to an estimate when a barcode
        // is available. An unavailable lookup never blocks the diary entry.
        if let barcode = BarcodeNormalizer.normalizedIfValid(food.barcode),
           let imported = try? await OpenFoodFactsService.shared.fetchProduct(barcode: barcode)?.micronutrients,
           !imported.isEmpty {
            guard isCurrent(request, foods: foods, diary: diary, premium: premium) else { return false }
            foods.applyOpenFoodFactsMicronutrients(imported, barcode: barcode)
            diary.applyOpenFoodFactsMicronutrients(imported, barcode: barcode, foods: foods.availableFoods)
        }
        guard isCurrent(request, foods: foods, diary: diary, premium: premium),
              let latest = findFood(request, in: foods) else { return false }
        if latest.micronutrients?.isEmpty == false { return true }
        food = latest

        guard let estimate = await AppleMicronutrientEstimator.estimate(for: food),
              isCurrent(request, foods: foods, diary: diary, premium: premium),
              var current = findFood(request, in: foods) else { return false }
        if current.micronutrients?.isEmpty == false { return true }
        let metricUnit: FoodUnit = current.unit.isVolume ? .milliliter : .gram
        current.micronutrients = estimate.converted(from: metricUnit, to: current.unit)
        foods.updateFood(current)
        diary.refreshMicronutrients(from: foods.availableFoods)
        return foods.food(id: current.id)?.micronutrients?.isEmpty == false
    }

    private func findFood(_ request: Request, in foods: FoodStore) -> FoodItem? {
        foods.food(id: request.foodID)
            ?? request.globalID.flatMap { globalID in
                foods.availableFoods.first { $0.globalRecordID == globalID }
            }
    }

    private func isCurrent(_ request: Request, foods: FoodStore, diary: CalorieStore, premium: PremiumAccessStore) -> Bool {
        premium.hasNutrition && AppleMicronutrientEstimator.isAvailable
            && foods.micronutrientScopeID == request.scope
            && diary.micronutrientScopeID == request.scope
    }
}
