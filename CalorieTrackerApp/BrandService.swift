import Foundation
import OSLog

actor BrandService {
    static let shared = BrandService()
    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "Brands")

    private struct Page: Decodable { let items: [FoodBrand] }
    private struct CreatedBrand: Decodable {
        let id: String
        let name: String
        let normalizedName: String
        let slug: String
        let aliases: [String]
        let status: FoodBrandStatus
        let createdBy: String
        enum CodingKeys: String, CodingKey {
            case id, name, slug, aliases, status
            case normalizedName = "normalized_name"
            case createdBy = "created_by"
        }
        var brand: FoodBrand { FoodBrand(id: id, name: name, normalizedName: normalizedName, slug: slug, aliases: aliases, status: status, createdBy: createdBy) }
    }

    func search(query: String, token: String) async throws -> [FoodBrand] {
        var parts = URLComponents(string: "\(baseURL)/api/hyse/brands")
        parts?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = parts?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response, action: "search")
        return try JSONDecoder().decode(Page.self, from: data).items
    }

    func create(name: String, token: String) async throws -> FoodBrand {
        guard !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
        guard let url = URL(string: "\(baseURL)/api/hyse/brands") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data: data, response: response, action: "create")
        return try JSONDecoder().decode(CreatedBrand.self, from: data).brand
    }

    private func validate(data: Data, response: URLResponse, action: String) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let message = (try? JSONDecoder().decode(BrandServerError.self, from: data).message) ?? "Brand request failed."
            logger.error("Brand \(action, privacy: .public) rejected with status \(status): \(message, privacy: .public)")
            throw BrandServiceError.server(message)
        }
    }
}

nonisolated private struct BrandServerError: Decodable { let message: String }
nonisolated enum BrandServiceError: LocalizedError {
    case server(String)
    var errorDescription: String? { if case .server(let message) = self { return message }; return nil }
}
