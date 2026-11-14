import Foundation

actor FavoriteSyncService {
    static let shared = FavoriteSyncService()
    private let baseURL = HyseConfiguration.serverURL

    struct Result: Sendable {
        let serverGlobalIDs: Set<String>
        let didSync: Bool
    }

    private struct Favorite: Decodable {
        let id: String
        let globalFood: String
        enum CodingKeys: String, CodingKey { case id; case globalFood = "global_food" }
    }
    private struct Page: Decodable { let page: Int; let totalPages: Int; let items: [Favorite] }

    func sync(desiredGlobalIDs: Set<String>?, userID: String, token: String) async -> Result {
        guard !userID.isEmpty, !token.isEmpty, let initial = await fetch(token: token) else {
            return Result(serverGlobalIDs: desiredGlobalIDs ?? [], didSync: false)
        }
        if desiredGlobalIDs == nil { return Result(serverGlobalIDs: Set(initial.map(\.globalFood)), didSync: true) }
        let desiredGlobalIDs = desiredGlobalIDs!
        var byGlobalID = Dictionary(uniqueKeysWithValues: initial.map { ($0.globalFood, $0) })
        var allSucceeded = true
        for favorite in initial where !desiredGlobalIDs.contains(favorite.globalFood) {
            if await delete(recordID: favorite.id, token: token) { byGlobalID.removeValue(forKey: favorite.globalFood) }
            else { allSucceeded = false }
        }
        for globalID in desiredGlobalIDs where byGlobalID[globalID] == nil {
            if await create(globalID: globalID, userID: userID, token: token) {
                byGlobalID[globalID] = Favorite(id: "", globalFood: globalID)
            } else { allSucceeded = false }
        }
        // The local map already reflects every confirmed mutation. Avoid a
        // second full favourites download after each small toggle.
        return Result(serverGlobalIDs: Set(byGlobalID.keys), didSync: allSucceeded)
    }

    private func fetch(token: String) async -> [Favorite]? {
        var page = 1
        var values: [Favorite] = []
        while true {
            var components = URLComponents(string: "\(baseURL)/api/collections/user_favorites/records")
            components?.queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "perPage", value: "100")]
            guard let url = components?.url else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
                let decoded = try JSONDecoder().decode(Page.self, from: data)
                values += decoded.items
                if decoded.page >= decoded.totalPages { return values }
                page += 1
            } catch { return nil }
        }
    }

    private func create(globalID: String, userID: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/user_favorites/records") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["user": userID, "global_food": globalID])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) || $0.statusCode == 400 } ?? false
        } catch { return false }
    }

    private func delete(recordID: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/user_favorites/records/\(recordID)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch { return false }
    }
}
