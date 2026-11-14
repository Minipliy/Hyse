import Foundation
import OSLog

actor FoodSyncService {
    static let shared = FoodSyncService()
    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "SavedFoodSync")

    struct Result: Sendable {
        let foods: [RemoteFood]
        let uploaded: Set<UUID>
        let deleted: Set<UUID>
        let didFetch: Bool
        let hadFailures: Bool
    }
    struct RemoteFood: Codable, Sendable {
        let id: String; let clientID: String; let name: String; let brand: String; let brandRelation: String
        let calories: Double; let carbs: Double; let protein: Double; let fat: Double
        let sugar: Double; let fiber: Double; let saturatedFat: Double; let salt: Double
        let micronutrients: MicronutrientProfile?
        let barcode: String; let unit: String; let servingSize: Double; let isFavorite: Bool; let isFruit: Bool; let globalFood: String; let globalSubmission: String?
        let externalSource: String?; let externalSourceID: String?; let externalFetchedAt: String?
        enum CodingKeys: String, CodingKey {
            case id, name, brand, calories, carbs, protein, fat, sugar, fiber, barcode, unit, micronutrients
            case brandRelation = "brand_relation"
            case clientID = "client_id"; case saturatedFat = "saturated_fat"; case salt
            case servingSize = "serving_size"; case isFavorite = "is_favorite"; case isFruit = "is_fruit"; case globalFood = "global_food"; case globalSubmission = "global_submission"
            case externalSource = "external_source"; case externalSourceID = "external_source_id"; case externalFetchedAt = "external_fetched_at"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            clientID = try values.decode(String.self, forKey: .clientID)
            name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
            brand = try values.decodeIfPresent(String.self, forKey: .brand) ?? ""
            brandRelation = try values.decodeIfPresent(String.self, forKey: .brandRelation) ?? ""
            calories = try values.decodeIfPresent(Double.self, forKey: .calories) ?? 0
            carbs = try values.decodeIfPresent(Double.self, forKey: .carbs) ?? 0
            protein = try values.decodeIfPresent(Double.self, forKey: .protein) ?? 0
            fat = try values.decodeIfPresent(Double.self, forKey: .fat) ?? 0
            sugar = try values.decodeIfPresent(Double.self, forKey: .sugar) ?? 0
            fiber = try values.decodeIfPresent(Double.self, forKey: .fiber) ?? 0
            saturatedFat = try values.decodeIfPresent(Double.self, forKey: .saturatedFat) ?? 0
            salt = try values.decodeIfPresent(Double.self, forKey: .salt) ?? 0
            micronutrients = try values.decodeIfPresent(MicronutrientProfile.self, forKey: .micronutrients)
            barcode = try values.decodeIfPresent(String.self, forKey: .barcode) ?? ""
            unit = try values.decodeIfPresent(String.self, forKey: .unit) ?? FoodUnit.gram.rawValue
            servingSize = try values.decodeIfPresent(Double.self, forKey: .servingSize) ?? 0
            isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
            isFruit = try values.decodeIfPresent(Bool.self, forKey: .isFruit) ?? false
            globalFood = try values.decodeIfPresent(String.self, forKey: .globalFood) ?? ""
            globalSubmission = try values.decodeIfPresent(String.self, forKey: .globalSubmission)
            externalSource = try values.decodeIfPresent(String.self, forKey: .externalSource)
            externalSourceID = try values.decodeIfPresent(String.self, forKey: .externalSourceID)
            externalFetchedAt = try values.decodeIfPresent(String.self, forKey: .externalFetchedAt)
        }
    }
    private struct Page: Decodable { let page: Int; let totalPages: Int; let items: [RemoteFood] }

    func lookupBarcode(_ barcode: String, token: String) async -> [FoodItem] {
        var parts = URLComponents(string: "\(baseURL)/api/collections/user_foods/records")
        parts?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "perPage", value: "2"),
            URLQueryItem(name: "skipTotal", value: "1"),
            URLQueryItem(name: "filter", value: "record_type = 'saved' && barcode_normalized = '\(barcode)'")
        ]
        guard let url = parts?.url else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 1.6; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            return try JSONDecoder().decode(Page.self, from: data).items.compactMap { food(from: $0) }
        } catch { return [] }
    }

    func sync(foods: [FoodItem], dirty: Set<UUID>, deleted: Set<UUID>, userID: String, token: String) async -> Result {
        guard !userID.isEmpty, !token.isEmpty, let initial = await fetchAll(token: token) else {
            return Result(foods: [], uploaded: [], deleted: [], didFetch: false, hadFailures: true)
        }
        var remoteByID = Dictionary(uniqueKeysWithValues: initial.compactMap { value in UUID(uuidString: value.clientID).map { ($0, value) } })
        var deletedOK = Set<UUID>()
        for id in deleted {
            guard let remote = remoteByID[id] else { deletedOK.insert(id); continue }
            if await deleteRecord(remote.id, token: token) { deletedOK.insert(id); remoteByID.removeValue(forKey: id) }
        }
        let local = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        let effectiveDirty = dirty.intersection(local.keys)
        // Old app versions could leave a dirty marker behind after its local
        // food had already disappeared. Treat those orphan markers as resolved
        // instead of keeping the account in a permanent retry loop.
        var uploadedOK = dirty.subtracting(local.keys).subtracting(deleted)
        for id in effectiveDirty where !deleted.contains(id) {
            guard let food = local[id] else { continue }
            // A similar food under another client UUID is not an upload
            // confirmation. Treating it as one used to clear the dirty flag
            // even though this logical record never reached PocketBase.
            if let saved = await send(food, remoteID: remoteByID[id]?.id, userID: userID, token: token) {
                remoteByID[id] = saved
                uploadedOK.insert(id)
            }
        }
        let failedUploads = effectiveDirty.subtracting(deleted).subtracting(uploadedOK)
        let failedDeletes = deleted.subtracting(deletedOK)
        return Result(
            // PocketBase returns the complete saved record for every create or
            // update. Merge those responses into the initial snapshot instead
            // of downloading the user's entire food collection a second time.
            foods: Array(remoteByID.values),
            uploaded: uploadedOK,
            deleted: deletedOK,
            didFetch: true,
            hadFailures: !failedUploads.isEmpty || !failedDeletes.isEmpty
        )
    }

    nonisolated func food(from remote: RemoteFood, portions: [FoodPortion] = []) -> FoodItem? {
        guard let id = UUID(uuidString: remote.clientID) else { return nil }
        return FoodItem(id: id, name: remote.name, brand: remote.brand.isEmpty ? nil : remote.brand, brandRecordID: remote.brandRelation.isEmpty ? nil : remote.brandRelation, kcalPer100g: remote.calories, carbsPer100g: remote.carbs, proteinPer100g: remote.protein, fatPer100g: remote.fat, sugarPer100g: remote.sugar, fiberPer100g: remote.fiber, saturatedFatPer100g: remote.saturatedFat, saltPer100g: remote.salt, micronutrients: remote.micronutrients?.isEmpty == false ? remote.micronutrients : nil, barcode: remote.barcode.isEmpty ? nil : remote.barcode, externalSource: remote.externalSource, externalSourceID: remote.externalSourceID, externalFetchedAt: remote.externalFetchedAt.flatMap(CalorieEntrySyncService.date(from:)), isFavorite: remote.isFavorite, globalRecordID: remote.globalFood.isEmpty ? nil : remote.globalFood, globalSubmissionID: remote.globalSubmission.flatMap { $0.isEmpty ? nil : $0 }, unit: FoodUnit(rawValue: remote.unit) ?? .gram, servingSizeAmount: remote.servingSize > 0 ? remote.servingSize : nil, portions: portions, isFruit: remote.isFruit)
    }

    nonisolated static func fingerprint(_ food: FoodItem) -> String {
        let name = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let barcode = food.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !barcode.isEmpty {
            return "barcode:\(barcode)"
        }
        return "\(name)|\(food.unit.rawValue)|\(food.kcalPer100g)|\(food.carbsPer100g)|\(food.proteinPer100g)|\(food.fatPer100g)"
    }

    private func fetchAll(token: String) async -> [RemoteFood]? {
        var page = 1; var result: [RemoteFood] = []
        while true {
            var parts = URLComponents(string: "\(baseURL)/api/collections/user_foods/records")
            parts?.queryItems = [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "perPage", value: "100"), URLQueryItem(name: "sort", value: "name"), URLQueryItem(name: "filter", value: "record_type = \"saved\" || record_type = \"\"")]
            guard let url = parts?.url else { return nil }
            var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(status) else {
                    logger.error("user_foods saved fetch rejected with status \(status)")
                    return nil
                }
                let value = try JSONDecoder().decode(Page.self, from: data); result += value.items
                if value.page >= value.totalPages { return result }; page += 1
            } catch {
                logger.error("user_foods saved fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private func send(_ food: FoodItem, remoteID: String?, userID: String, token: String) async -> RemoteFood? {
        let suffix = remoteID.map { "/records/\($0)" } ?? "/records"
        guard let url = URL(string: "\(baseURL)/api/collections/user_foods\(suffix)") else { return nil }
        // Historical foods may still contain a formatted or invalid barcode.
        // The server accepts only canonical GTINs in barcode_normalized.
        let barcode = BarcodeNormalizer.normalizedIfValid(food.barcode) ?? ""
        var payload: [String: Any] = ["record_type": "saved", "client_id": food.id.uuidString.lowercased(), "name": food.name, "brand": food.brand ?? "", "brand_relation": food.brandRecordID ?? "", "calories": food.kcalPer100g, "carbs": food.carbsPer100g, "protein": food.proteinPer100g, "fat": food.fatPer100g, "sugar": food.sugarPer100g, "fiber": food.fiberPer100g, "saturated_fat": food.saturatedFatPer100g, "salt": food.saltPer100g, "barcode": barcode, "barcode_raw": barcode, "barcode_normalized": barcode, "unit": food.unit.rawValue, "serving_size": food.servingSizeAmount ?? 0, "is_favorite": food.isFavorite, "is_fruit": food.isFruit]
        if let profile = food.micronutrients, !profile.isEmpty { payload["micronutrients"] = profile.serverValue }
        if let source = food.externalSource { payload["external_source"] = source }
        if let sourceID = food.externalSourceID { payload["external_source_id"] = sourceID }
        if let fetchedAt = food.externalFetchedAt { payload["external_fetched_at"] = ISO8601DateFormatter().string(from: fetchedAt) }
        // Catalogue moderation is a separate workflow managed by FoodStore.
        // This private upload must never wait for global_foods or submissions.
        if let globalID = food.globalRecordID, !globalID.isEmpty { payload["global_food"] = globalID }
        if let submissionID = food.globalSubmissionID, !submissionID.isEmpty { payload["global_submission"] = submissionID }
        if remoteID == nil { payload["user"] = userID }
        var request = URLRequest(url: url); request.httpMethod = remoteID == nil ? "POST" : "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                let message = (try? JSONDecoder().decode(SavedFoodServerError.self, from: data).message) ?? "PocketBase rejected the payload"
                logger.error("user_foods saved upload rejected with status \(status): \(message, privacy: .public)")
                return nil
            }
            return try JSONDecoder().decode(RemoteFood.self, from: data)
        } catch {
            logger.error("user_foods saved upload failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func deleteRecord(_ id: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/user_foods/records/\(id)") else { return false }
        var request = URLRequest(url: url); request.httpMethod = "DELETE"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(status) { logger.error("user_foods saved delete rejected with status \(status)") }
            return (200...299).contains(status)
        } catch {
            logger.error("user_foods saved delete failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

nonisolated private struct SavedFoodServerError: Decodable { let message: String }
