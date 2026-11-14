import Foundation
import OSLog
import UIKit

actor RecipeSyncService {
    static let shared = RecipeSyncService()
    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "RecipeSync")

    struct Result: Sendable {
        let remoteRecipes: [Recipe]
        let globalRecipes: [Recipe]?
        let confirmedIDs: Set<UUID>
        let deletedIDs: Set<UUID>
        let conflictCopies: [Recipe]
        let didFetch: Bool
    }

    struct GlobalSubmissionResult: Sendable {
        let submissionID: String?
        let globalRecipeID: String?
        let status: RecipeModerationStatus
        let rejectionReason: String?
    }

    private struct RemoteRecipe: Decodable, Sendable {
        let id: String
        let clientID: String
        let snapshot: Recipe
        let globalRecipe: String
        let globalSubmission: String
        let createdLocal: String
        let updatedLocal: String
        let updated: String
        let image: String
        enum CodingKeys: String, CodingKey {
            case id, updated, image
            case clientID = "client_id"
            case snapshot = "snapshot_json"
            case globalRecipe = "global_recipe"
            case globalSubmission = "global_submission"
            case createdLocal = "created_at_local"
            case updatedLocal = "updated_at_local"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            clientID = try c.decode(String.self, forKey: .clientID)
            snapshot = try c.decode(Recipe.self, forKey: .snapshot)
            globalRecipe = try c.decodeIfPresent(String.self, forKey: .globalRecipe) ?? ""
            globalSubmission = try c.decodeIfPresent(String.self, forKey: .globalSubmission) ?? ""
            createdLocal = try c.decodeIfPresent(String.self, forKey: .createdLocal) ?? ""
            updatedLocal = try c.decodeIfPresent(String.self, forKey: .updatedLocal) ?? ""
            updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? ""
            image = try c.decodeIfPresent(String.self, forKey: .image) ?? ""
        }
    }

    private struct RemoteGlobalRecipe: Decodable, Sendable {
        let id: String
        let creator: String
        let snapshot: Recipe
        let updated: String
        enum CodingKeys: String, CodingKey { case id, creator, updated; case snapshot = "snapshot_json" }
    }

    private struct RemoteSubmission: Decodable, Sendable {
        let id: String
        let status: String
        let rejectionReason: String
        let globalRecipe: String
        enum CodingKeys: String, CodingKey {
            case id, status
            case rejectionReason = "rejection_reason"
            case globalRecipe = "global_recipe"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
            rejectionReason = try c.decodeIfPresent(String.self, forKey: .rejectionReason) ?? ""
            globalRecipe = try c.decodeIfPresent(String.self, forKey: .globalRecipe) ?? ""
        }
    }

    private struct Page<T: Decodable & Sendable>: Decodable, Sendable {
        let page: Int
        let totalPages: Int
        let items: [T]
    }

    private struct SubmitResponse: Decodable, Sendable {
        let submissionID: String?
        let globalRecipeID: String?
        let status: String
        let rejectionReason: String?
        enum CodingKeys: String, CodingKey {
            case status
            case submissionID = "submission_id"
            case globalRecipeID = "global_recipe_id"
            case rejectionReason = "rejection_reason"
        }
    }

    func sync(recipes: [Recipe], dirtyIDs: Set<UUID>, deletedIDs: Set<UUID>, userID: String, token: String, refreshGlobalRecipes: Bool) async -> Result {
        guard !userID.isEmpty, !token.isEmpty, let initialRemote = await fetchPersonal(token: token) else {
            return Result(remoteRecipes: [], globalRecipes: nil, confirmedIDs: [], deletedIDs: [], conflictCopies: [], didFetch: false)
        }
        var remoteByClientID = Dictionary(uniqueKeysWithValues: initialRemote.compactMap { remote in UUID(uuidString: remote.clientID).map { ($0, remote) } })
        var successfulDeletes = Set<UUID>()
        for id in deletedIDs {
            guard let remote = remoteByClientID[id] else { successfulDeletes.insert(id); continue }
            if await delete(remoteID: remote.id, token: token) {
                successfulDeletes.insert(id); remoteByClientID.removeValue(forKey: id)
            }
        }

        let localByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        var fingerprintToRemote: [String: RemoteRecipe] = [:]
        initialRemote.forEach { fingerprintToRemote[Self.fingerprint(recipe(from: $0))] = $0 }
        var confirmed = Set<UUID>()
        var conflicts: [Recipe] = []

        for id in dirtyIDs where !deletedIDs.contains(id) {
            guard let local = localByID[id] else { continue }
            if let duplicate = fingerprintToRemote[Self.fingerprint(local)], duplicate.clientID.lowercased() != id.uuidString.lowercased() {
                confirmed.insert(id)
                continue
            }
            if let remote = remoteByClientID[id] {
                let remoteRecipe = recipe(from: remote)
                if remoteRecipe.updatedAt.timeIntervalSince(local.updatedAt) > 1 {
                    var copy = local
                    copy.id = UUID(); copy.remoteID = nil; copy.globalSubmissionID = nil
                    copy.syncStatus = .conflict; copy.updatedAt = Date()
                    conflicts.append(copy)
                    confirmed.insert(id)
                    continue
                }
            }
            if let saved = await send(local, remoteID: remoteByClientID[id]?.id, userID: userID, token: token) {
                remoteByClientID[id] = saved; confirmed.insert(id)
                fingerprintToRemote[Self.fingerprint(local)] = saved
            }
        }

        // Every successful mutation above returned its full PocketBase record,
        // so remoteByClientID is already current and a second complete fetch of
        // all personal recipes would only duplicate traffic.
        let needsSubmissionState = remoteByClientID.values.contains { !$0.globalSubmission.isEmpty }
        async let submissionsResult: [RemoteSubmission]? = needsSubmissionState ? fetchSubmissions(token: token) : []
        async let globalsResult: [RemoteGlobalRecipe]? = refreshGlobalRecipes ? fetchGlobals(token: token) : nil
        let submissions = await submissionsResult ?? []
        let submissionByID = Dictionary(uniqueKeysWithValues: submissions.map { ($0.id, $0) })
        let personal = remoteByClientID.values.compactMap { remote -> Recipe? in
            guard var value = optionalRecipe(from: remote) else { return nil }
            if let submissionID = value.globalSubmissionID, let submission = submissionByID[submissionID] {
                value.moderationStatus = RecipeModerationStatus(rawValue: submission.status)
                value.rejectionReason = submission.rejectionReason.isEmpty ? nil : submission.rejectionReason
                if !submission.globalRecipe.isEmpty { value.globalRecordID = submission.globalRecipe }
            }
            return value
        }
        let globals = await globalsResult?.map(recipe(from:))
        return Result(remoteRecipes: personal, globalRecipes: globals, confirmedIDs: confirmed,
                      deletedIDs: successfulDeletes, conflictCopies: conflicts, didFetch: true)
    }

    func submitGlobal(recipe: Recipe, userID: String, token: String) async -> GlobalSubmissionResult? {
        guard let url = URL(string: "\(baseURL)/api/hyse/global-recipes/submit"),
              let snapshot = Self.jsonObject(recipe) else { return nil }
        var payload: [String: Any] = [
            "client_id": recipe.id.uuidString.lowercased(), "snapshot_json": snapshot,
            "normalized_key": Self.fingerprint(recipe)
        ]
        if let source = recipe.globalRecordID, !source.isEmpty { payload["source_recipe"] = source }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let decoded = try? JSONDecoder().decode(SubmitResponse.self, from: data),
                  let status = RecipeModerationStatus(rawValue: decoded.status) else {
                logger.error("Global recipe submission rejected with status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }
            return GlobalSubmissionResult(submissionID: decoded.submissionID, globalRecipeID: decoded.globalRecipeID,
                                          status: status, rejectionReason: decoded.rejectionReason)
        } catch {
            logger.error("Global recipe submission failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    nonisolated static func fingerprint(_ recipe: Recipe) -> String {
        let normalizedName = normalize(recipe.name)
        let ingredients = recipe.ingredients.map {
            "\(normalize($0.food.name)):\($0.unit.rawValue):\((max($0.grams, 0) * 1000).rounded() / 1000)"
        }.sorted().joined(separator: "|")
        return "\(normalizedName)|\(ingredients)|\((max(recipe.servings, 0) * 1000).rounded() / 1000)"
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func recipe(from remote: RemoteRecipe) -> Recipe { optionalRecipe(from: remote) ?? remote.snapshot }
    private func optionalRecipe(from remote: RemoteRecipe) -> Recipe? {
        guard let id = UUID(uuidString: remote.clientID) else { return nil }
        var value = remote.snapshot
        value.id = id; value.remoteID = remote.id; value.origin = .personal; value.syncStatus = .synced
        value.globalRecordID = remote.globalRecipe.isEmpty ? value.globalRecordID : remote.globalRecipe
        value.globalSubmissionID = remote.globalSubmission.isEmpty ? value.globalSubmissionID : remote.globalSubmission
        value.remoteImageFileName = remote.image.isEmpty ? nil : remote.image
        value.createdAt = Self.date(remote.createdLocal) ?? value.createdAt
        value.updatedAt = Self.date(remote.updatedLocal) ?? Self.date(remote.updated) ?? value.updatedAt
        return value
    }
    private func recipe(from remote: RemoteGlobalRecipe) -> Recipe {
        var value = remote.snapshot
        value.remoteID = remote.id; value.globalRecordID = remote.id; value.origin = .global
        value.syncStatus = .synced; value.moderationStatus = .approved
        value.updatedAt = Self.date(remote.updated) ?? value.updatedAt
        return value
    }

    private func fetchPersonal(token: String) async -> [RemoteRecipe]? { await fetch(collection: "user_recipes", sort: "-updated", token: token) }
    private func fetchGlobals(token: String) async -> [RemoteGlobalRecipe]? { await fetch(collection: "global_recipes", sort: "name", token: token) }
    private func fetchSubmissions(token: String) async -> [RemoteSubmission]? { await fetch(collection: "global_recipe_submissions", sort: "-created", token: token) }
    private func fetch<T: Decodable & Sendable>(collection: String, sort: String, token: String) async -> [T]? {
        var page = 1; var values: [T] = []
        while true {
            var parts = URLComponents(string: "\(baseURL)/api/collections/\(collection)/records")
            parts?.queryItems = [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "perPage", value: "100"), URLQueryItem(name: "sort", value: sort)]
            guard let url = parts?.url else { return nil }
            var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    logger.error("\(collection, privacy: .public) fetch rejected with status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return nil
                }
                let decoded = try JSONDecoder().decode(Page<T>.self, from: data)
                values += decoded.items
                if decoded.page >= decoded.totalPages { return values }
                page += 1
            } catch {
                logger.error("\(collection, privacy: .public) fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private func send(_ recipe: Recipe, remoteID: String?, userID: String, token: String) async -> RemoteRecipe? {
        let endpoint = remoteID.map { "/records/\($0)" } ?? "/records"
        guard let url = URL(string: "\(baseURL)/api/collections/user_recipes\(endpoint)"),
              let snapshot = Self.jsonObject(recipe) else { return nil }
        let n = recipe.totalNutrients
        var payload: [String: Any] = [
            "client_id": recipe.id.uuidString.lowercased(), "name": recipe.name,
            "description": recipe.recipeDescription, "ingredients": Self.ingredientObjects(recipe.ingredients),
            "servings": recipe.servings, "total_weight_grams": recipe.totalWeightGrams ?? 0,
            "preparation_steps": recipe.preparationSteps, "preparation_minutes": recipe.preparationMinutes ?? 0,
            "tags": recipe.tags, "filters": recipe.filters.map(\.rawValue), "is_favorite": recipe.isFavorite,
            "calories": n.kcal, "carbs": n.carbs, "protein": n.protein, "fat": n.fat,
            "sugar": n.sugar, "fiber": n.fiber, "saturated_fat": n.saturatedFat, "salt": n.salt,
            "created_at_local": Self.string(recipe.createdAt), "updated_at_local": Self.string(recipe.updatedAt),
            "snapshot_json": snapshot
        ]
        if recipe.imageFileName == nil { payload["image"] = "" }
        if remoteID == nil { payload["user"] = userID }
        if let value = recipe.globalRecordID, !value.isEmpty { payload["global_recipe"] = value }
        if let value = recipe.globalSubmissionID, !value.isEmpty { payload["global_submission"] = value }
        var request = URLRequest(url: url); request.httpMethod = remoteID == nil ? "POST" : "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else { logger.error("user_recipes upload rejected with status \(status)"); return nil }
            let saved = try JSONDecoder().decode(RemoteRecipe.self, from: data)
            if let image = RecipeImageStore.data(for: recipe.imageFileName) {
                return await uploadImage(image, remoteID: saved.id, token: token)
            }
            return saved
        } catch {
            logger.error("user_recipes upload failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func uploadImage(_ image: Data, remoteID: String, token: String) async -> RemoteRecipe? {
        guard let url = URL(string: "\(baseURL)/api/collections/user_recipes/records/\(remoteID)") else { return nil }
        let boundary = "HyseRecipe-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"recipe.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else { return nil }
            return try JSONDecoder().decode(RemoteRecipe.self, from: data)
        } catch { return nil }
    }

    func downloadImage(remoteID: String, fileName: String, token: String) async -> Data? {
        guard !token.isEmpty, !remoteID.isEmpty, !fileName.isEmpty,
              let tokenURL = URL(string: "\(baseURL)/api/files/token") else { return nil }
        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        struct FileToken: Decodable { let token: String }
        do {
            let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
            guard (tokenResponse as? HTTPURLResponse)?.statusCode == 200,
                  let fileToken = try? JSONDecoder().decode(FileToken.self, from: tokenData) else { return nil }
            var parts = URLComponents(string: "\(baseURL)/api/files/user_recipes/\(remoteID)/\(fileName)")
            parts?.queryItems = [URLQueryItem(name: "token", value: fileToken.token)]
            guard let url = parts?.url else { return nil }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  !data.isEmpty, data.count <= 2_100_000, UIImage(data: data) != nil else { return nil }
            return data
        } catch { return nil }
    }

    private func delete(remoteID: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/user_recipes/records/\(remoteID)") else { return false }
        var request = URLRequest(url: url); request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do { let (_, response) = try await URLSession.shared.data(for: request); return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false }
        catch { logger.error("user_recipes delete failed: \(error.localizedDescription, privacy: .public)"); return false }
    }

    nonisolated private static func ingredientObjects(_ values: [RecipeIngredient]) -> [[String: Any]] {
        values.map { ingredient in
            var result: [String: Any] = [
                "client_id": ingredient.id.uuidString.lowercased(), "food_client_id": ingredient.food.id.uuidString.lowercased(),
                "name": ingredient.food.name, "amount": ingredient.grams, "unit": ingredient.unit.rawValue,
                "kcal_per_100": ingredient.food.kcalPer100g, "carbs_per_100": ingredient.food.carbsPer100g,
                "protein_per_100": ingredient.food.proteinPer100g, "fat_per_100": ingredient.food.fatPer100g,
                "sugar_per_100": ingredient.food.sugarPer100g, "fiber_per_100": ingredient.food.fiberPer100g,
                "saturated_fat_per_100": ingredient.food.saturatedFatPer100g, "salt_per_100": ingredient.food.saltPer100g
            ]
            if let id = ingredient.globalFoodRecordID { result["global_food"] = id }
            return result
        }
    }
    nonisolated private static func jsonObject(_ recipe: Recipe) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(recipe),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
    nonisolated private static func string(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    nonisolated private static func date(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        var normalized = value
        if normalized.count > 10 {
            let separator = normalized.index(normalized.startIndex, offsetBy: 10)
            if normalized[separator] == " " { normalized.replaceSubrange(separator...separator, with: "T") }
        }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: normalized) ?? ISO8601DateFormatter().date(from: normalized)
    }
}
