import Foundation
import UIKit

nonisolated enum RecipeShareLink {
    static let host = HyseConfiguration.serverHost

    static func url(id: String, isGerman: Bool) -> URL? {
        guard validID(id) else { return nil }
        return URL(string: "https://\(host)/\(isGerman ? "de/rezept" : "en/recipe")/\(id)")
    }

    static func recipeID(from url: URL) -> String? {
        let path = url.pathComponents.filter { $0 != "/" }
        let candidate: String?
        if url.scheme == "hyseapp", url.host == "recipe" {
            candidate = path.count == 1 ? path[0] : nil
        } else if url.scheme == "https", url.host == host, path.count == 3,
                  (path[0] == "de" && path[1] == "rezept") || (path[0] == "en" && path[1] == "recipe") {
            candidate = path[2]
        } else {
            candidate = nil
        }
        return candidate.flatMap { validID($0) ? $0 : nil }
    }

    private static func validID(_ value: String) -> Bool {
        value.count == 15 && value.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
    }
}

nonisolated struct SharedRecipeSnapshot: Codable, Sendable {
    struct Ingredient: Codable, Sendable {
        let name: String
        let amount: Double
        let unit: String
    }
    let name: String
    let description: String
    let ingredients: [Ingredient]
    let steps: [String]
    let servings: Double
    let minutes: Int?
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    init(recipe: Recipe) {
        name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        description = recipe.displayDescription == recipe.preparationSteps.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            ? "" : recipe.displayDescription
        ingredients = recipe.ingredients.map {
            Ingredient(name: $0.food.name, amount: $0.grams, unit: $0.unit.rawValue)
        }
        steps = recipe.preparationSteps.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        servings = recipe.servings
        minutes = recipe.preparationMinutes
        kcal = recipe.nutrientsPerServing.kcal
        protein = recipe.nutrientsPerServing.protein
        carbs = recipe.nutrientsPerServing.carbs
        fat = recipe.nutrientsPerServing.fat
    }
}

nonisolated struct SharedRecipe: Decodable, Identifiable, Sendable {
    let id: String
    let snapshot: SharedRecipeSnapshot
    let image: String

    enum CodingKeys: String, CodingKey { case id, image; case snapshot = "snapshot_json" }

    var imageURL: URL? {
        guard !image.isEmpty else { return nil }
        return URL(string: "https://\(RecipeShareLink.host)/api/files/recipe_shares/\(id)/\(image)")
    }
}

enum RecipeShareError: Error { case invalidResponse, uploadFailed, server(Int) }

actor RecipeShareService {
    static let shared = RecipeShareService()
    private let base = "\(HyseConfiguration.serverURL)/api/collections/recipe_shares/records"
    private struct PublishedRecord: Decodable { let id: String }

    func publish(recipe: Recipe, ownerID: String, token: String) async throws -> String {
        guard !ownerID.isEmpty, !token.isEmpty, let url = URL(string: base + (recipe.shareRecordID.map { "/\($0)" } ?? "")) else {
            throw RecipeShareError.invalidResponse
        }
        let snapshot = SharedRecipeSnapshot(recipe: recipe)
        var imageData = RecipeImageStore.data(for: recipe.imageFileName)
            ?? RecipeImageStore.cachedRemoteData(remoteID: recipe.remoteID, fileName: recipe.remoteImageFileName)
        if imageData == nil, let remoteID = recipe.remoteID, let fileName = recipe.remoteImageFileName {
            imageData = await RecipeSyncService.shared.downloadImage(remoteID: remoteID, fileName: fileName, token: token)
            if let imageData { RecipeImageStore.cacheRemote(imageData, remoteID: remoteID, fileName: fileName) }
        }
        var payload: [String: Any] = ["snapshot_json": try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))]
        if recipe.shareRecordID == nil { payload["owner"] = ownerID }
        if recipe.imageFileName == nil { payload["image"] = "" }
        var request = URLRequest(url: url)
        request.httpMethod = recipe.shareRecordID == nil ? "POST" : "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw RecipeShareError.invalidResponse
        }
        guard (200...299).contains(status) else { throw RecipeShareError.server(status) }
        guard let id = try? JSONDecoder().decode(PublishedRecord.self, from: data).id,
              RecipeShareLink.url(id: id, isGerman: true) != nil else {
            throw RecipeShareError.invalidResponse
        }
        if let imageData {
            let uploadData = await MainActor.run {
                UIImage(data: imageData)?.hyseCompressedJPEG(maxDimension: 1400, maxBytes: 1_800_000)
            }
            if let uploadData { try? await uploadImage(uploadData, id: id, token: token) }
        }
        return id
    }

    func fetch(id: String) async throws -> SharedRecipe {
        guard let url = URL(string: "https://\(RecipeShareLink.host)/api/hyse/public-recipes/\(id)") else { throw RecipeShareError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else { throw RecipeShareError.invalidResponse }
        return try JSONDecoder().decode(SharedRecipe.self, from: data)
    }

    func revoke(id: String, token: String) async throws {
        guard let url = URL(string: base + "/\(id)") else { throw RecipeShareError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) || status == 404 else { throw RecipeShareError.invalidResponse }
    }

    private func uploadImage(_ data: Data, id: String, token: String) async throws {
        guard let url = URL(string: base + "/\(id)") else { throw RecipeShareError.invalidResponse }
        let boundary = "HyseRecipe-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"recipe.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else { throw RecipeShareError.uploadFailed }
    }
}

nonisolated enum RecipeImageStore {
    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HyseRecipeImages", isDirectory: true)
    }

    static func data(for fileName: String?) -> Data? {
        guard let fileName, fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              let directory else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(fileName))
    }

    static func save(_ data: Data) throws -> String {
        guard let directory else { throw RecipeShareError.invalidResponse }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString.lowercased() + ".jpg"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func cachedRemoteData(remoteID: String?, fileName: String?) -> Data? {
        guard let remoteID, let fileName, safeFilePart(remoteID), safeFilePart(fileName) else { return nil }
        return data(for: "remote-\(remoteID)-\(fileName)")
    }

    static func cacheRemote(_ data: Data, remoteID: String, fileName: String) {
        guard safeFilePart(remoteID), safeFilePart(fileName), let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("remote-\(remoteID)-\(fileName)"), options: .atomic)
    }

    private static func safeFilePart(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
        }
    }
}
