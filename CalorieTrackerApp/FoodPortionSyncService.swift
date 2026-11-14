import Foundation
import OSLog

actor FoodPortionSyncService {
    static let shared = FoodPortionSyncService()
    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "FoodPortions")

    struct Snapshot: Sendable {
        let personalByClientID: [UUID: [FoodPortion]]
        let globalByRecordID: [String: [FoodPortion]]
        let didSync: Bool
        static let empty = Snapshot(personalByClientID: [:], globalByRecordID: [:], didSync: false)
    }

    private struct RemotePortion: Decodable, Sendable {
        let id: String
        let owner: String
        let userFood: String
        let globalFood: String
        let clientID: String
        let nameKey: String
        let customName: String
        let amount: Double
        let unit: String
        let gramEquivalent: Double
        let sortOrder: Int
        let isDefault: Bool
        let status: String
        let created: String
        let updated: String
        enum CodingKeys: String, CodingKey {
            case id, owner, amount, unit, status, created, updated
            case userFood = "user_food"; case globalFood = "global_food"; case clientID = "client_id"
            case nameKey = "name_key"; case customName = "custom_name"; case gramEquivalent = "gram_equivalent"
            case sortOrder = "sort_order"; case isDefault = "is_default"
        }
    }
    private struct Page: Decodable { let page: Int; let totalPages: Int; let items: [RemotePortion] }

    func sync(foods: [FoodItem], remoteFoods: [FoodSyncService.RemoteFood], changedFoodIDs: Set<UUID>, globalFoodIDs: Set<String> = [], userID: String, token: String) async -> Snapshot {
        guard !userID.isEmpty, !token.isEmpty, let personalRecords = await fetch(filter: "owner = '\(userID)'", token: token) else { return .empty }
        let relatedGlobalIDs = globalFoodIDs.union(remoteFoods.compactMap { $0.globalFood.isEmpty ? nil : $0.globalFood })
        let globalRecords = await fetchApprovedRecords(globalFoodIDs: relatedGlobalIDs, token: token) ?? []
        let remoteFoodByClient = Dictionary(uniqueKeysWithValues: remoteFoods.compactMap { value in
            UUID(uuidString: value.clientID).map { ($0, value) }
        })
        var records = personalRecords + globalRecords
        var allSucceeded = true
        var needsServerRefresh = false

        for food in foods {
            // A food can change on another device while this iPhone still has an older
            // local copy. Only a local portion edit may remove remote portions.
            guard changedFoodIDs.contains(food.id) else { continue }
            guard let remoteFood = remoteFoodByClient[food.id] else { allSucceeded = false; continue }
            let remoteFoodID = remoteFood.id
            let desired = food.portions.normalized(defaultUnit: food.unit)
            let existing = records.filter { $0.userFood == remoteFoodID && $0.owner == userID }
            let desiredIDs = Set(desired.map(\.id))
            for stale in existing where !desiredIDs.contains(UUID(uuidString: stale.clientID) ?? UUID()) {
                if await delete(id: stale.id, token: token) { records.removeAll { $0.id == stale.id } } else { allSucceeded = false }
            }
            let existingByClient = Dictionary(uniqueKeysWithValues: existing.compactMap { value in UUID(uuidString: value.clientID).map { ($0, value) } })
            for portion in desired {
                let current = existingByClient[portion.id]
                guard current.map({ !matches($0, portion: portion, userFoodID: remoteFoodID) }) ?? true else { continue }
                if let saved = await send(portion, remoteID: current?.id, userFoodID: remoteFoodID, userID: userID, token: token) {
                    records.removeAll { $0.id == saved.id || $0.clientID == saved.clientID }
                    records.append(saved)
                } else { allSucceeded = false }
            }
        }

        for food in remoteFoods where !food.globalFood.isEmpty {
            for record in records where record.userFood == food.id && record.owner == userID && record.status == "pending" {
                guard let id = UUID(uuidString: record.clientID) else { continue }
                if await submit(portionID: id, userFoodID: food.id, token: token) { needsServerRefresh = true }
                else { allSucceeded = false }
            }
        }

        // Normal creates and updates already return the canonical PocketBase
        // record, so the initial snapshot can be updated in memory. Only the
        // moderation endpoint can change additional server fields and needs a
        // follow-up read.
        guard needsServerRefresh else {
            return snapshot(records, remoteFoods: remoteFoods, didSync: allSucceeded)
        }
        guard let refreshedPersonal = await fetch(filter: "owner = '\(userID)'", token: token) else {
            return snapshot(records, remoteFoods: remoteFoods, didSync: false)
        }
        let refreshedGlobal = await fetchApprovedRecords(globalFoodIDs: relatedGlobalIDs, token: token) ?? globalRecords
        return snapshot(refreshedPersonal + refreshedGlobal, remoteFoods: remoteFoods, didSync: allSucceeded)
    }

    /// Loads approved shared portions only for foods currently visible in the
    /// catalogue. This avoids downloading the complete portion catalogue.
    func fetchApproved(globalFoodIDs: Set<String>, token: String) async -> [String: [FoodPortion]] {
        guard let records = await fetchApprovedRecords(globalFoodIDs: globalFoodIDs, token: token) else { return [:] }
        var result: [String: [FoodPortion]] = [:]
        for record in records {
            guard !record.globalFood.isEmpty, let value = portion(record) else { continue }
            result[record.globalFood, default: []].append(value)
        }
        return result.mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }
    }

    private func snapshot(_ records: [RemotePortion], remoteFoods: [FoodSyncService.RemoteFood], didSync: Bool) -> Snapshot {
        let clientByRemote = Dictionary(uniqueKeysWithValues: remoteFoods.compactMap { value in UUID(uuidString: value.clientID).map { (value.id, $0) } })
        var personal: [UUID: [FoodPortion]] = [:]
        var global: [String: [FoodPortion]] = [:]
        for record in records {
            guard let value = portion(record) else { continue }
            if let clientID = clientByRemote[record.userFood] { personal[clientID, default: []].append(value) }
            if !record.globalFood.isEmpty { global[record.globalFood, default: []].append(value) }
        }
        personal = personal.mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }
        global = global.mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }
        return Snapshot(personalByClientID: personal, globalByRecordID: global, didSync: didSync)
    }

    private func portion(_ remote: RemotePortion) -> FoodPortion? {
        guard let id = UUID(uuidString: remote.clientID), let unit = FoodUnit(rawValue: remote.unit), remote.amount > 0 else { return nil }
        return FoodPortion(id: id, nameKey: remote.nameKey.isEmpty ? nil : remote.nameKey, customName: remote.customName, amount: remote.amount, unit: unit, gramEquivalent: remote.gramEquivalent > 0 ? remote.gramEquivalent : nil, sortOrder: remote.sortOrder, isDefault: remote.isDefault, status: FoodPortionStatus(rawValue: remote.status) ?? .private, createdAt: CalorieEntrySyncService.date(from: remote.created) ?? .distantPast, updatedAt: CalorieEntrySyncService.date(from: remote.updated) ?? .distantPast)
    }

    private func matches(_ remote: RemotePortion, portion: FoodPortion, userFoodID: String) -> Bool {
        remote.userFood == userFoodID
            && remote.nameKey == (portion.nameKey ?? "")
            && remote.customName == portion.customName
            && abs(remote.amount - portion.amount) < 0.000_001
            && remote.unit == portion.unit.rawValue
            && abs(remote.gramEquivalent - (portion.gramEquivalent ?? 0)) < 0.000_001
            && remote.sortOrder == portion.sortOrder
            && remote.isDefault == portion.isDefault
            && remote.status == portion.status.rawValue
    }

    private func fetchApprovedRecords(globalFoodIDs: Set<String>, token: String) async -> [RemotePortion]? {
        guard !globalFoodIDs.isEmpty else { return [] }
        let ids = globalFoodIDs.filter { !$0.isEmpty }.sorted()
        var result: [RemotePortion] = []
        for start in stride(from: 0, to: ids.count, by: 30) {
            let chunk = ids[start..<min(start + 30, ids.count)]
            let foodFilter = chunk.map { "global_food = '\($0)'" }.joined(separator: " || ")
            guard let records = await fetch(filter: "status = 'approved' && (\(foodFilter))", token: token) else { return nil }
            result.append(contentsOf: records)
        }
        return result
    }

    private func fetch(filter: String, token: String) async -> [RemotePortion]? {
        var page = 1; var result: [RemotePortion] = []
        while true {
            var parts = URLComponents(string: "\(baseURL)/api/collections/food_portions/records")
            parts?.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: "200"),
                URLQueryItem(name: "sort", value: "sort_order"),
                URLQueryItem(name: "filter", value: filter)
            ]
            guard let url = parts?.url else { return nil }
            var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(status) else { logger.error("food_portions fetch rejected with status \(status)"); return nil }
                let decoded = try JSONDecoder().decode(Page.self, from: data); result += decoded.items
                if decoded.page >= decoded.totalPages { return result }; page += 1
            } catch { logger.error("food_portions fetch failed: \(error.localizedDescription, privacy: .public)"); return nil }
        }
    }

    private func send(_ portion: FoodPortion, remoteID: String?, userFoodID: String, userID: String, token: String) async -> RemotePortion? {
        let endpoint = remoteID.map { "/records/\($0)" } ?? "/records"
        guard let url = URL(string: "\(baseURL)/api/collections/food_portions\(endpoint)") else { return nil }
        var payload: [String: Any] = [
            "owner": userID, "user_food": userFoodID, "client_id": portion.id.uuidString.lowercased(),
            "name_key": portion.nameKey ?? "", "custom_name": portion.customName,
            "amount": portion.amount, "unit": portion.unit.rawValue,
            "sort_order": portion.sortOrder, "is_default": portion.isDefault, "status": portion.status.rawValue
        ]
        if let grams = portion.gramEquivalent { payload["gram_equivalent"] = grams }
        var request = URLRequest(url: url); request.httpMethod = remoteID == nil ? "POST" : "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(status) {
                let message = (try? JSONDecoder().decode(PortionServerError.self, from: data).message) ?? "Invalid portion payload"
                logger.error("food_portions upload rejected with status \(status): \(message, privacy: .public)")
            }
            guard (200...299).contains(status) else { return nil }
            return try JSONDecoder().decode(RemotePortion.self, from: data)
        } catch { logger.error("food_portions upload failed: \(error.localizedDescription, privacy: .public)"); return nil }
    }

    private func submit(portionID: UUID, userFoodID: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/hyse/food-portions/submit-global") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "user_food": userFoodID,
            "client_id": portionID.uuidString.lowercased()
        ])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(status) { logger.error("global food portion submission rejected with status \(status)") }
            return (200...299).contains(status)
        } catch {
            logger.error("global food portion submission failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func delete(id: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/food_portions/records/\(id)") else { return false }
        var request = URLRequest(url: url); request.httpMethod = "DELETE"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do { let (_, response) = try await URLSession.shared.data(for: request); return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false }
        catch { logger.error("food_portions delete failed: \(error.localizedDescription, privacy: .public)"); return false }
    }
}

nonisolated private struct PortionServerError: Decodable { let message: String }
