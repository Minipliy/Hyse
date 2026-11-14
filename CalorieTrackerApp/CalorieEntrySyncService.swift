import Foundation
import OSLog

/// Idempotent offline-first sync for account-owned `food_entries` records.
actor CalorieEntrySyncService {
    static let shared = CalorieEntrySyncService()
    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "EntrySync")

    struct Result: Sendable {
        let remoteEntries: [RemoteEntry]
        let uploadedIDs: Set<UUID>
        let deletedIDs: Set<UUID>
        let didFetch: Bool
        let didFullFetch: Bool
    }

    struct RemoteEntry: Codable, Sendable {
        let id: String
        let clientID: String
        let name: String
        let amountGrams: Double
        let eatenAt: String
        let category: String
        let portionName: String?
        let portionID: String?
        let portionCount: Double?
        let mealKey: String?
        let categoryID: String
        let unit: String
        let kcalPer100g: Double
        let carbsPer100g: Double
        let proteinPer100g: Double
        let fatPer100g: Double
        let addedSugarPer100g: Double
        let fruitSugarPer100g: Double
        let fiberPer100g: Double
        let saturatedFatPer100g: Double
        let saltPer100g: Double
        let micronutrients: MicronutrientProfile?
        let calories: Double?
        let carbs: Double?
        let protein: Double?
        let fat: Double?
        let globalFood: String
        let userRecipe: String?
        let globalRecipe: String?
        let recipeClientID: String?
        let sourceFoodClientID: String?

        enum CodingKeys: String, CodingKey {
            case id, name, unit, calories, carbs, protein, fat
            case category = "meal"
            case portionName = "portion_name"
            case portionID = "portion_id"
            case portionCount = "portion_count"
            case mealKey = "meal_key"
            case globalFood = "global_food"
            case userRecipe = "user_recipe"
            case globalRecipe = "global_recipe"
            case recipeClientID = "recipe_client_id"
            case sourceFoodClientID = "source_food_client_id"
            case clientID = "client_id"
            case amountGrams = "amount"
            case eatenAt = "eaten_at"
            case categoryID = "category_id"
            case kcalPer100g = "kcal_per_100g"
            case carbsPer100g = "carbs_per_100g"
            case proteinPer100g = "protein_per_100g"
            case fatPer100g = "fat_per_100g"
            case addedSugarPer100g = "added_sugar_per_100g"
            case fruitSugarPer100g = "fruit_sugar_per_100g"
            case fiberPer100g = "fiber_per_100g"
            case saturatedFatPer100g = "saturated_fat_per_100g"
            case saltPer100g = "salt_per_100g"
            case micronutrients
        }
    }

    private struct Page: Decodable { let page: Int; let totalPages: Int; let items: [RemoteEntry] }

    func sync(entries: [CalorieEntry], dirtyIDs: Set<UUID>, deletedIDs: Set<UUID>, userID: String, token: String, fullRefresh: Bool) async -> Result {
        guard !userID.isEmpty, !token.isEmpty else {
            return Result(remoteEntries: [], uploadedIDs: [], deletedIDs: [], didFetch: false, didFullFetch: false)
        }
        let initialRemote: [RemoteEntry]
        if fullRefresh {
            guard let fetched = await fetchAll(token: token) else {
                return Result(remoteEntries: [], uploadedIDs: [], deletedIDs: [], didFetch: false, didFullFetch: false)
            }
            initialRemote = fetched
        } else {
            initialRemote = []
        }

        var remoteByClientID = Dictionary(uniqueKeysWithValues: initialRemote.compactMap { remote in
            UUID(uuidString: remote.clientID).map { ($0, remote) }
        })
        var successfulDeletes = Set<UUID>()
        for id in deletedIDs {
            // A record that is already absent on the server is a confirmed
            // deletion, not a reason to keep retrying forever.
            guard let remote = remoteByClientID[id] else { successfulDeletes.insert(id); continue }
            if await delete(remoteID: remote.id, token: token) {
                successfulDeletes.insert(id)
                remoteByClientID.removeValue(forKey: id)
            }
        }

        let localByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        // Old versions could leave a dirty marker after its local entry was
        // removed. Resolve those orphan markers without a pointless request.
        var successfulUploads = dirtyIDs.subtracting(localByID.keys).subtracting(deletedIDs)
        for id in dirtyIDs where !deletedIDs.contains(id) {
            guard let entry = localByID[id] else { continue }
            let saved: RemoteEntry?
            let knownRemoteID = remoteByClientID[id]?.id ?? (fullRefresh ? nil : entry.remoteID)
            if let remoteID = knownRemoteID {
                saved = await send(entry, endpoint: "/records/\(remoteID)", token: token, extra: [:], method: "PATCH")
            } else {
                saved = await send(entry, endpoint: "/records", token: token, extra: ["user": userID])
            }
            if let saved, Self.acknowledges(saved, entry: entry) {
                // The create/update response is the authoritative confirmation.
                // Only clear the durable dirty marker when PocketBase echoes
                // both the client identity and the amount that was uploaded.
                // A stale 2xx response must never produce a green sync icon.
                remoteByClientID[id] = saved
                successfulUploads.insert(id)
            } else if saved != nil {
                logger.error("user_foods response did not confirm client identity and amount")
            }
        }

        let unresolvedUploads = dirtyIDs.intersection(localByID.keys)
            .subtracting(deletedIDs)
            .subtracting(successfulUploads)
        if !fullRefresh, !unresolvedUploads.isEmpty {
            // A cached record ID may have become stale after a deletion or a
            // server-side repair. Retry once against an authoritative snapshot
            // so tapping “retry” cannot get stuck in the lightweight path.
            return await sync(entries: entries, dirtyIDs: dirtyIDs, deletedIDs: deletedIDs,
                              userID: userID, token: token, fullRefresh: true)
        }

        return Result(
            remoteEntries: Array(remoteByClientID.values),
            uploadedIDs: successfulUploads,
            deletedIDs: successfulDeletes,
            didFetch: true,
            didFullFetch: fullRefresh
        )
    }

    nonisolated func entry(from remote: RemoteEntry) -> CalorieEntry? {
        guard let id = UUID(uuidString: remote.clientID), let date = Self.date(from: remote.eatenAt) else { return nil }
        let stableMeal = remote.mealKey.flatMap { $0.isEmpty ? nil : $0 } ?? MealCategory.legacySystemKey(for: remote.category) ?? remote.category
        // PocketBase serializes an unset optional number as 0. Treat that as
        // "no portion selected"; otherwise a gram entry is reopened as
        // "0 portions" and converting the picker also turns it into 0 grams.
        let validPortionCount = remote.portionCount.flatMap { count in
            count.isFinite && count > 0 ? count : nil
        }
        let recoveredAmount = Self.validAmount(remote.amountGrams)
            ?? Self.inferredAmount(total: remote.calories, per100: remote.kcalPer100g)
            ?? Self.inferredAmount(total: remote.carbs, per100: remote.carbsPer100g)
            ?? Self.inferredAmount(total: remote.protein, per100: remote.proteinPer100g)
            ?? Self.inferredAmount(total: remote.fat, per100: remote.fatPer100g)
            ?? 0
        return CalorieEntry(id: id, remoteID: remote.id, foodItemId: remote.sourceFoodClientID.flatMap(UUID.init(uuidString:)), recipeId: remote.recipeClientID.flatMap(UUID.init(uuidString:)), globalFoodRecordID: remote.globalFood.isEmpty ? nil : remote.globalFood, userRecipeRecordID: remote.userRecipe.flatMap { $0.isEmpty ? nil : $0 }, globalRecipeRecordID: remote.globalRecipe.flatMap { $0.isEmpty ? nil : $0 }, name: remote.name, grams: recoveredAmount, categoryId: UUID(uuidString: remote.categoryID) ?? UUID(), categoryName: stableMeal, portionName: remote.portionName.flatMap { $0.isEmpty ? nil : $0 }, portionID: remote.portionID.flatMap(UUID.init(uuidString:)), portionCount: validPortionCount, unit: FoodUnit(rawValue: remote.unit) ?? .gram, kcalPer100g: remote.kcalPer100g, carbsPer100g: remote.carbsPer100g, proteinPer100g: remote.proteinPer100g, fatPer100g: remote.fatPer100g, addedSugarPer100g: remote.addedSugarPer100g, fruitSugarPer100g: remote.fruitSugarPer100g, fiberPer100g: remote.fiberPer100g, saturatedFatPer100g: remote.saturatedFatPer100g, saltPer100g: remote.saltPer100g, micronutrients: remote.micronutrients?.isEmpty == false ? remote.micronutrients : nil, date: date)
    }

    nonisolated private static func validAmount(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }

    nonisolated private static func acknowledges(_ remote: RemoteEntry, entry: CalorieEntry) -> Bool {
        guard UUID(uuidString: remote.clientID) == entry.id,
              remote.amountGrams.isFinite,
              entry.grams.isFinite else { return false }
        let tolerance = max(0.000_1, abs(entry.grams) * 0.000_001)
        return abs(remote.amountGrams - entry.grams) <= tolerance
    }

    nonisolated private static func inferredAmount(total: Double?, per100: Double) -> Double? {
        guard let total, total.isFinite, total > 0, per100.isFinite, per100 > 0 else { return nil }
        return validAmount(total * 100 / per100)
    }

    private func fetchAll(token: String) async -> [RemoteEntry]? {
        var page = 1; var values: [RemoteEntry] = []
        while true {
            var components = URLComponents(string: "\(baseURL)/api/collections/user_foods/records")
            components?.queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "perPage", value: "100"), URLQueryItem(name: "sort", value: "eaten_at"), URLQueryItem(name: "filter", value: "record_type = \"entry\"")]
            guard let url = components?.url else { return nil }
            var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    logger.error("user_foods fetch rejected with status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return nil
                }
                let decoded = try JSONDecoder().decode(Page.self, from: data)
                values += decoded.items
                if decoded.page >= decoded.totalPages { return values }
                page += 1
            } catch { logger.error("user_foods fetch failed: \(error.localizedDescription, privacy: .public)"); return nil }
        }
    }

    private func delete(remoteID: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/user_foods/records/\(remoteID)") else { return false }
        var request = URLRequest(url: url); request.httpMethod = "DELETE"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do { let (_, response) = try await URLSession.shared.data(for: request); let status = (response as? HTTPURLResponse)?.statusCode ?? 0; if !(200...299).contains(status) { logger.error("user_foods delete rejected with status \(status)") }; return (200...299).contains(status) } catch { logger.error("user_foods delete failed: \(error.localizedDescription, privacy: .public)"); return false }
    }

    private func send(_ entry: CalorieEntry, endpoint: String, token: String, extra: [String: Any], method: String = "POST") async -> RemoteEntry? {
        guard let url = URL(string: "\(baseURL)/api/collections/user_foods\(endpoint)") else { return nil }
        var payload: [String: Any] = [
            "client_id": entry.id.uuidString.lowercased(), "name": entry.name,
            "calories": entry.kcal, "carbs": entry.carbs, "protein": entry.protein, "fat": entry.fat,
            "sugar": entry.sugar, "fiber": entry.fiber, "saturated_fat": entry.saturatedFat, "salt": entry.salt,
            "record_type": "entry", "amount": entry.grams, "eaten_at": Self.iso8601String(from: entry.date), "meal": entry.categoryName,
            "local_day": Self.localDayString(from: entry.date),
            "timezone_offset": TimeZone.autoupdatingCurrent.secondsFromGMT(for: entry.date) / 60,
            "category_id": entry.categoryId.uuidString.lowercased(), "unit": entry.unit.rawValue,
            "kcal_per_100g": entry.kcalPer100g, "carbs_per_100g": entry.carbsPer100g,
            "protein_per_100g": entry.proteinPer100g, "fat_per_100g": entry.fatPer100g,
            "added_sugar_per_100g": entry.addedSugarPer100g, "fruit_sugar_per_100g": entry.fruitSugarPer100g,
            "fiber_per_100g": entry.fiberPer100g, "saturated_fat_per_100g": entry.saturatedFatPer100g,
            "salt_per_100g": entry.saltPer100g
        ]
        if let profile = entry.micronutrients, !profile.isEmpty { payload["micronutrients"] = profile.serverValue }
        if let mealKey = MealCategory.legacySystemKey(for: entry.categoryName) {
            payload["meal_key"] = mealKey
        }
        if let globalFood = entry.globalFoodRecordID, !globalFood.isEmpty { payload["global_food"] = globalFood }
        if let foodID = entry.foodItemId { payload["source_food_client_id"] = foodID.uuidString.lowercased() }
        // Always send the optional portion fields. Empty values deliberately
        // clear stale PocketBase values when an entry is changed back to grams.
        payload["portion_name"] = entry.portionName ?? ""
        payload["portion_id"] = entry.portionID?.uuidString.lowercased() ?? ""
        payload["portion_count"] = entry.portionCount.flatMap { $0 > 0 ? $0 : nil } ?? 0
        if let recipeID = entry.recipeId { payload["recipe_client_id"] = recipeID.uuidString.lowercased() }
        if let userRecipe = entry.userRecipeRecordID, !userRecipe.isEmpty { payload["user_recipe"] = userRecipe }
        if let globalRecipe = entry.globalRecipeRecordID, !globalRecipe.isEmpty { payload["global_recipe"] = globalRecipe }
        extra.forEach { key, value in payload[key] = value }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for _ in 0..<4 {
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 400,
                   let field = Self.invalidOptionalRelation(in: data, presentIn: payload) {
                    // A deleted recipe or catalogue food must not block its
                    // historical diary snapshot. Keep the stable client ID,
                    // amount and nutrition while clearing only that relation.
                    payload[field] = ""
                    logger.warning("Retrying diary entry without stale \(field, privacy: .public) relation")
                    continue
                }
                guard (200...299).contains(status) else {
                    let serverMessage = (try? JSONDecoder().decode(EntrySyncServerError.self, from: data).message) ?? "Unknown PocketBase error"
                    logger.error("user_foods upload rejected with status \(status): \(serverMessage, privacy: .public)")
                    return nil
                }
                do {
                    return try JSONDecoder().decode(RemoteEntry.self, from: data)
                } catch {
                    logger.error("user_foods response decode failed after status \(status): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            } catch {
                logger.error("user_foods upload failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return nil
    }

    nonisolated static func invalidOptionalRelation(in data: Data, presentIn payload: [String: Any]) -> String? {
        guard let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let fields = response["data"] as? [String: Any] else { return nil }
        for field in ["user_recipe", "global_recipe", "global_food"] where fields[field] != nil {
            if let value = payload[field] as? String, !value.isEmpty { return field }
        }
        return nil
    }

    nonisolated private static func iso8601Formatter(fractionalSeconds: Bool = true) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        if fractionalSeconds { formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds] }
        return formatter
    }
    nonisolated private static func iso8601String(from date: Date) -> String { iso8601Formatter().string(from: date) }
    nonisolated private static func localDayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    /// PocketBase serializes date fields as `yyyy-MM-dd HH:mm:ss.SSSZ`, while
    /// ISO8601DateFormatter expects `T` between the date and time. Accept both
    /// representations so a confirmed server record is never dropped locally.
    nonisolated static func date(from value: String) -> Date? {
        var normalized = value
        if normalized.count > 10 {
            let separator = normalized.index(normalized.startIndex, offsetBy: 10)
            if normalized[separator] == " " { normalized.replaceSubrange(separator...separator, with: "T") }
        }
        return iso8601Formatter().date(from: normalized)
            ?? iso8601Formatter(fractionalSeconds: false).date(from: normalized)
    }
}
nonisolated private struct EntrySyncServerError: Decodable { let message: String }
