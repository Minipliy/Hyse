import Foundation

/// Enriches barcode-linked foods and old entry snapshots without requiring
/// anyone to reopen or edit the food. Owned by ContentView for the app session.
@MainActor
final class OpenFoodFactsMicronutrientRefresh {
    private var pending = false
    private var worker: Task<Void, Never>?
    private var lastAttempt: [String: Date] = [:]
    private var cachedProfiles: [String: MicronutrientProfile] = [:]

    func schedule(foods: FoodStore, entries: CalorieStore, enabled: Bool) {
        guard enabled else { return }
        pending = true
        guard worker == nil else { return }
        worker = Task { [weak self, weak foods, weak entries] in
            guard let self, let foods, let entries else { return }
            while self.pending {
                self.pending = false
                await self.refresh(foods: foods, entries: entries)
            }
            self.worker = nil
        }
    }

    private func refresh(foods: FoodStore, entries: CalorieStore) async {
        let scope = foods.micronutrientScopeID
        guard scope == entries.micronutrientScopeID else { return }

        // Older entries may refer to catalogue foods that are no longer in
        // the local search cache. Recover their barcode from the exact record.
        let knownGlobalIDs = Set(foods.availableFoods.compactMap(\.globalRecordID))
        let missingGlobalIDs = Set(entries.entries.compactMap(\.globalFoodRecordID)).subtracting(knownGlobalIDs)
        if !missingGlobalIDs.isEmpty {
            await foods.hydrateGlobalFoods(recordIDs: Array(missingGlobalIDs))
        }
        guard scope == foods.micronutrientScopeID,
              scope == entries.micronutrientScopeID else { return }

        let entryFoodIDs = Set(entries.entries.compactMap(\.foodItemId))
        let entryGlobalIDs = Set(entries.entries.compactMap(\.globalFoodRecordID))
        let personalFoodIDs = Set(foods.foods.map(\.id))
        let relevantFoods = foods.availableFoods.filter { food in
            personalFoodIDs.contains(food.id)
                || entryFoodIDs.contains(food.id)
                || (food.globalRecordID.map(entryGlobalIDs.contains) ?? false)
        }
        let barcodes = Set(relevantFoods.compactMap { food -> String? in
            guard let raw = food.barcode else { return nil }
            return try? BarcodeNormalizer.normalize(raw)
        })
        for barcode in barcodes.sorted() {
            guard scope == foods.micronutrientScopeID,
                  scope == entries.micronutrientScopeID else { return }
            let key = "\(scope):\(barcode)"
            if let cached = cachedProfiles[key] {
                apply(cached, barcode: barcode, foods: foods, entries: entries)
            }
            // Refresh on the next foreground visit or after an hour. Failed
            // lookups retry sooner, while the OFF service deduplicates requests.
            let retryAfter: TimeInterval = cachedProfiles[key] == nil ? 5 * 60 : 60 * 60
            if let attempted = lastAttempt[key], Date().timeIntervalSince(attempted) < retryAfter { continue }
            lastAttempt[key] = Date()
            do {
                guard let profile = try await OpenFoodFactsService.shared.fetchProduct(barcode: barcode)?.micronutrients,
                      !profile.isEmpty else { continue }
                guard scope == foods.micronutrientScopeID,
                      scope == entries.micronutrientScopeID else { return }
                cachedProfiles[key] = profile
                apply(profile, barcode: barcode, foods: foods, entries: entries)
            } catch {
                // An offline or incomplete OFF record remains unknown and is
                // retried automatically after the short backoff.
            }
        }
    }

    private func apply(_ profile: MicronutrientProfile, barcode: String, foods: FoodStore, entries: CalorieStore) {
        foods.applyOpenFoodFactsMicronutrients(profile, barcode: barcode)
        entries.applyOpenFoodFactsMicronutrients(profile, barcode: barcode, foods: foods.availableFoods)
    }
}
