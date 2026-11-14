import Foundation
import CryptoKit
import OSLog

actor GlobalFoodService {
    static let shared = GlobalFoodService()
    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "GlobalFoodSearch")

    private struct Page: Decodable {
        let page: Int
        let totalPages: Int
        let items: [RemoteFood]
    }

    private struct SearchResponse: Decodable { let items: [RemoteFood] }

    private struct RemoteFood: Decodable {
        let id: String
        let name: String?
        let nameDE: String?
        let calories: Double?
        let carbs: Double?
        let protein: Double?
        let fat: Double?
        let barcode: String?
        let brand: String?
        let unit: String?
        let servingSize: Double?
        let sugar: Double?
        let fiber: Double?
        let saturatedFat: Double?
        let salt: Double?
        let moderationStatus: String?
        let creator: String?
        let source: String?
        let sourceID: String?
        let brandRelation: String?
        let isFruit: Bool?
        let micronutrients: MicronutrientProfile?
        enum CodingKeys: String, CodingKey {
            case id, name, calories, carbs, protein, fat, barcode, brand, unit, sugar, fiber, salt, micronutrients
            case nameDE = "name_de"
            case servingSize = "serving_size"
            case saturatedFat = "saturated_fat"
            case moderationStatus = "moderation_status"; case creator, source; case sourceID = "source_id"; case brandRelation = "brand_relation"; case isFruit = "is_fruit"
        }
    }

    struct SubmissionResolution: Decodable, Sendable {
        let id: String
        let status: String
        let rejectionReason: String?
        let globalFood: String?
        enum CodingKeys: String, CodingKey { case id, status; case rejectionReason = "rejection_reason"; case globalFood = "global_food" }
    }

    struct SubmissionStatus: Sendable {
        let id: String
        let sourceFood: String
        let status: GlobalModerationStatus
        let rejectionReason: String?
    }

    private struct RemoteSubmission: Decodable {
        let id: String
        let sourceFood: String?
        let clientID: String?
        let status: String
        let rejectionReason: String?
        enum CodingKeys: String, CodingKey { case id, status; case sourceFood = "source_food"; case clientID = "personal_food_client_id"; case rejectionReason = "rejection_reason" }
    }

    private struct SubmissionPage: Decodable { let page: Int; let totalPages: Int; let items: [RemoteSubmission] }

    func submitChange(_ food: FoodItem, token: String) async throws -> SubmissionResolution {
        guard let sourceFood = food.globalRecordID, !sourceFood.isEmpty,
              let url = URL(string: "\(baseURL)/api/hyse/global-foods/submit-change") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": food.id.uuidString.lowercased(), "source_food": sourceFood,
            "name": food.name, "brand": food.brand ?? "", "brand_id": food.brandRecordID ?? "", "barcode": food.barcode ?? "",
            "unit": food.unit.rawValue, "serving_size": food.servingSizeAmount ?? 0,
            "calories": food.kcalPer100g, "carbs": food.carbsPer100g, "protein": food.proteinPer100g,
            "fat": food.fatPer100g, "sugar": food.sugarPer100g, "fiber": food.fiberPer100g,
            "saturated_fat": food.saturatedFatPer100g, "salt": food.saltPer100g,
            "is_fruit": food.isFruit
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerMessage.self, from: data).message) ?? "Food change could not be submitted."
            throw GlobalFoodError.server((response as? HTTPURLResponse)?.statusCode ?? 0, message)
        }
        return try JSONDecoder().decode(SubmissionResolution.self, from: data)
    }

    func submitNew(_ food: FoodItem, token: String) async throws -> SubmissionResolution {
        guard let url = URL(string: "\(baseURL)/api/hyse/global-foods/submit-new") else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": food.id.uuidString.lowercased(), "name": food.name, "brand": food.brand ?? "", "brand_id": food.brandRecordID ?? "", "barcode": food.barcode ?? "",
            "unit": food.unit.rawValue, "serving_size": food.servingSizeAmount ?? 0,
            "calories": food.kcalPer100g, "carbs": food.carbsPer100g, "protein": food.proteinPer100g, "fat": food.fatPer100g,
            "sugar": food.sugarPer100g, "fiber": food.fiberPer100g, "saturated_fat": food.saturatedFatPer100g,
            "salt": food.saltPer100g, "is_fruit": food.isFruit
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerMessage.self, from: data).message) ?? "Food submission could not be saved."
            throw GlobalFoodError.server((response as? HTTPURLResponse)?.statusCode ?? 0, message)
        }
        return try JSONDecoder().decode(SubmissionResolution.self, from: data)
    }

    func fetchSubmissionStatuses(token: String) async -> [String: SubmissionStatus] {
        var page = 1
        var result: [String: SubmissionStatus] = [:]
        // Keep only a compact offline starter catalogue on the phone. The full
        // catalogue is searched on demand through the bounded server route.
        while page <= 4 {
            var components = URLComponents(string: "\(baseURL)/api/collections/global_food_submissions/records")
            components?.queryItems = [
                URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "perPage", value: "100"),
                URLQueryItem(name: "sort", value: "-updated")
            ]
            guard let url = components?.url else { return result }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else { return result }
                let decoded = try JSONDecoder().decode(SubmissionPage.self, from: data)
                for item in decoded.items {
                    let source = item.sourceFood ?? ""
                    let value = SubmissionStatus(id: item.id, sourceFood: source, status: GlobalModerationStatus(rawValue: item.status) ?? .pending, rejectionReason: item.rejectionReason)
                    result[item.id] = value
                    if !source.isEmpty, result[source] == nil { result[source] = value }
                }
                if decoded.page >= decoded.totalPages { return result }
                page += 1
            } catch { return result }
        }
        return result
    }

    func fetch(token: String) async -> [FoodItem]? {
        // The complete catalogue can contain hundreds of thousands of foods.
        // Keep only a small offline starter set on the phone; all other foods
        // are loaded through the indexed search and barcode routes on demand.
        var components = URLComponents(string: "\(baseURL)/api/collections/global_foods/records")
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "perPage", value: "250"),
            URLQueryItem(name: "skipTotal", value: "1"),
            URLQueryItem(name: "sort", value: "off_de_catalog_rank,name"),
            URLQueryItem(name: "filter", value: "moderation_status = 'approved' || (moderation_status = '' && creator = '')")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try JSONDecoder().decode(Page.self, from: data).items.compactMap(Self.food)
        } catch {
            return nil
        }
    }

    /// Loads catalogue foods referenced by the user's frequency index even
    /// when they are not part of the small offline starter catalogue.
    func fetch(recordIDs: [String], token: String) async -> [FoodItem] {
        let allowed = CharacterSet.alphanumerics
        let ids = Array(Set(recordIDs.filter {
            !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains)
        })).sorted()
        guard !ids.isEmpty else { return [] }
        var result: [FoodItem] = []
        for chunkStart in stride(from: 0, to: ids.count, by: 35) {
            guard !Task.isCancelled else { return result }
            let chunk = Array(ids[chunkStart..<min(chunkStart + 35, ids.count)])
            let filter = chunk.map { "id = '\($0)'" }.joined(separator: " || ")
            var components = URLComponents(string: "\(baseURL)/api/collections/global_foods/records")
            components?.queryItems = [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "perPage", value: String(chunk.count)),
                URLQueryItem(name: "skipTotal", value: "1"),
                URLQueryItem(name: "filter", value: filter)
            ]
            guard let url = components?.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                result += try JSONDecoder().decode(Page.self, from: data).items.compactMap(Self.food)
            } catch {
                logger.error("Frequent global food hydration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return result
    }

    /// `nil` means the request failed. An empty array is a successful search
    /// with no matches. Keeping those states separate prevents a temporary
    /// backend failure from being cached as "nothing found".
    func search(_ query: String, token: String) async -> [FoodItem]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "\(baseURL)/api/hyse/global-foods/search")
        components?.queryItems = [URLQueryItem(name: "q", value: String(trimmed.prefix(80)))]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                logger.error("Global food search rejected with status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }
            return try JSONDecoder().decode(SearchResponse.self, from: data).items.compactMap(Self.food)
        } catch is CancellationError {
            return nil
        } catch {
            logger.error("Global food search failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func lookupBarcode(_ barcode: String, token: String) async -> [FoodItem] {
        var components = URLComponents(string: "\(baseURL)/api/collections/global_foods/records")
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "perPage", value: "1"),
            URLQueryItem(name: "skipTotal", value: "1"),
            URLQueryItem(name: "filter", value: "barcode_normalized = '\(barcode)' && moderation_status = 'approved'")
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url); request.timeoutInterval = 1.6; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            return try JSONDecoder().decode(Page.self, from: data).items.compactMap(Self.food)
        } catch { return [] }
    }

    nonisolated private static func food(_ remote: RemoteFood) -> FoodItem? {
        guard let name = remote.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let externalSource: String?
        switch remote.source {
        case "open_food_facts": externalSource = "Open Food Facts"
        case "manufacturer": externalSource = remote.brand?.isEmpty == false ? remote.brand : "Hersteller"
        default: externalSource = nil
        }
        return FoodItem(
            id: stableID(for: remote.id),
            name: name,
            nameDE: remote.nameDE,
            brand: remote.brand,
            brandRecordID: remote.brandRelation,
            kcalPer100g: remote.calories ?? 0,
            carbsPer100g: remote.carbs ?? 0,
            proteinPer100g: remote.protein ?? 0,
            fatPer100g: remote.fat ?? 0, sugarPer100g: remote.sugar ?? 0, fiberPer100g: remote.fiber ?? 0,
            saturatedFatPer100g: remote.saturatedFat ?? 0, saltPer100g: remote.salt ?? 0,
            micronutrients: remote.micronutrients?.isEmpty == false ? remote.micronutrients : nil,
            barcode: remote.barcode?.isEmpty == false ? remote.barcode : nil,
            externalSource: externalSource,
            externalSourceID: externalSource == nil ? nil : (remote.sourceID?.isEmpty == false ? remote.sourceID : remote.barcode),
            globalRecordID: remote.id,
            globalCreatorID: remote.creator,
            globalModerationStatus: GlobalModerationStatus(rawValue: remote.moderationStatus ?? "approved"),
            unit: FoodUnit(rawValue: remote.unit ?? "g") ?? .gram,
            servingSizeAmount: remote.servingSize.flatMap { $0 > 0 ? $0 : nil },
            isFruit: remote.isFruit ?? false
        )
    }

    nonisolated private static func stableID(for recordID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("hyse-global-food:\(recordID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

nonisolated private struct ServerMessage: Decodable { let message: String }
nonisolated enum GlobalFoodError: LocalizedError {
    case server(Int, String)
    var errorDescription: String? {
        switch self { case .server(let code, let message): return "PocketBase \(code): \(message)" }
    }
}
