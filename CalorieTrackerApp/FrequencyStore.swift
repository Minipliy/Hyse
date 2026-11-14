import Foundation
import Combine
import OSLog

extension Notification.Name { static let foodUsageShouldRefresh = Notification.Name("hyse.foodUsageShouldRefresh") }

/// A user-scoped cache of the server-owned `user_food_usage` index. For guests
/// the same shape is kept locally and is never mixed with an account scope.
@MainActor
final class FrequencyStore: ObservableObject {
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var recentItemIDs: [UUID] = []
    @Published private(set) var totalCounts: [UUID: Int] = [:]
    @Published private(set) var lastUsed: [UUID: Date] = [:]
    /// Server-owned identities survive catalogue refreshes and local copies.
    /// UUID maps stay available for recipes and backwards-compatible caches.
    @Published private(set) var sourceTotalCounts: [String: Int] = [:]
    @Published private(set) var sourceLastUsed: [String: Date] = [:]
    @Published private(set) var recentSourceKeys: [String] = []
    @Published private(set) var revision = 0
    @Published private(set) var isHydrating = false

    weak var authManager: AuthManager?
    private let baseURL = HyseConfiguration.serverURL
    private var accountID: String?
    private var lastRefreshAt: Date?
    private var refreshRequested = false
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "FoodUsage")

    private struct Cache: Codable {
        var counts: [String: Int]
        var recent: [UUID]
        var totals: [UUID: Int]
        var last: [UUID: Date]
        var sourceTotals: [String: Int]?
        var sourceLast: [String: Date]?
        var recentSources: [String]?
    }
    private struct Page: Decodable { let page: Int; let totalPages: Int; let items: [RemoteUsage] }
    private struct RemoteUsage: Decodable {
        let sourceKey: String; let usageCount: Int; let lastUsedAt: String; let clientItemID: String?
        enum CodingKeys: String, CodingKey {
            case sourceKey = "source_key"; case usageCount = "usage_count"; case lastUsedAt = "last_used_at"; case clientItemID = "client_item_id"
        }
    }

    init() {
        load(scope: "guest")
        NotificationCenter.default.publisher(for: .foodUsageShouldRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh(force: true) }
            .store(in: &cancellables)
    }

    func attach(_ authManager: AuthManager) { self.authManager = authManager }

    func activateAccount() {
        guard let authManager, authManager.isLoggedIn, !authManager.accountID.isEmpty else { return }
        let id = authManager.accountID
        guard accountID != id else { return }
        accountID = id
        load(scope: "account_\(id)")
        refresh()
    }

    func deactivateAccount() {
        accountID = nil
        lastRefreshAt = nil
        refreshRequested = false
        load(scope: "guest")
        isHydrating = false
    }

    /// Update the local index immediately. PocketBase remains authoritative for
    /// account totals and reconciles this optimistic value after entry sync.
    func recordUsage(foodId: UUID, categoryId: UUID) {
        let key = makeKey(foodId: foodId, categoryId: categoryId)
        counts[key, default: 0] += 1
        totalCounts[foodId, default: 0] += 1
        lastUsed[foodId] = Date()
        recentItemIDs.removeAll { $0 == foodId }
        recentItemIDs.insert(foodId, at: 0)
        recentItemIDs = Array(recentItemIDs.prefix(30))
        revision &+= 1
        save(scope: accountID.map { "account_\($0)" } ?? "guest")
    }

    func recordUsage(food: FoodItem, categoryId: UUID) {
        recordUsage(foodId: food.id, categoryId: categoryId)
        let sourceKey = Self.sourceKey(for: food)
        sourceTotalCounts[sourceKey, default: 0] += 1
        sourceLastUsed[sourceKey] = Date()
        recentSourceKeys.removeAll { $0 == sourceKey }
        recentSourceKeys.insert(sourceKey, at: 0)
        recentSourceKeys = Array(recentSourceKeys.prefix(30))
        revision &+= 1
        save(scope: accountID.map { "account_\($0)" } ?? "guest")
    }

    func usageCount(foodId: UUID, categoryId: UUID) -> Int {
        accountID == nil ? (counts[makeKey(foodId: foodId, categoryId: categoryId)] ?? 0) : totalUsageCount(itemId: foodId)
    }
    func recordUsage(itemId: UUID, categoryId: UUID) { recordUsage(foodId: itemId, categoryId: categoryId) }
    func usageCount(itemId: UUID, categoryId: UUID) -> Int { usageCount(foodId: itemId, categoryId: categoryId) }
    func totalUsageCount(itemId: UUID) -> Int { totalCounts[itemId] ?? 0 }
    func lastUsage(itemId: UUID) -> Date? { lastUsed[itemId] }
    func totalUsageCount(food: FoodItem) -> Int {
        max(totalCounts[food.id, default: 0], sourceTotalCounts[Self.sourceKey(for: food), default: 0])
    }
    func lastUsage(food: FoodItem) -> Date? {
        max(lastUsed[food.id] ?? .distantPast, sourceLastUsed[Self.sourceKey(for: food)] ?? .distantPast)
    }

    nonisolated static func sourceKey(for food: FoodItem) -> String {
        if let global = food.globalRecordID?.trimmingCharacters(in: .whitespacesAndNewlines), !global.isEmpty {
            return "global_food:\(global)"
        }
        if let externalID = food.externalSourceID?.trimmingCharacters(in: .whitespacesAndNewlines), !externalID.isEmpty {
            let trimmedProvider = food.externalSource?.trimmingCharacters(in: .whitespacesAndNewlines)
            let provider = trimmedProvider?.isEmpty == false ? trimmedProvider! : "external"
            return "external_food:\(provider):\(externalID)"
        }
        return "user_food:\(food.id.uuidString.lowercased())"
    }

    func refresh(force: Bool = false) {
        if isHydrating {
            if force { refreshRequested = true }
            return
        }
        guard let authManager, authManager.isLoggedIn,
              accountID == authManager.accountID, !authManager.token.isEmpty else { return }
        if !force, let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < 180 { return }
        lastRefreshAt = Date()
        isHydrating = true
        let token = authManager.token
        let expectedID = authManager.accountID
        Task {
            // Safe to call every time: the endpoint reconstructs from entries and
            // never increments an aggregate supplied by the client.
            await requestRebuild(token: token)
            let values = await fetchAll(token: token)
            guard accountID == expectedID else { isHydrating = false; return }
            if let values {
                apply(values, scope: "account_\(expectedID)")
            } else {
                lastRefreshAt = nil
            }
            isHydrating = false
            if refreshRequested {
                refreshRequested = false
                refresh(force: true)
            }
        }
    }

    private func requestRebuild(token: String) async {
        guard let url = URL(string: "\(baseURL)/api/hyse/food-usage/rebuild") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func fetchAll(token: String) async -> [RemoteUsage]? {
        var page = 1; var result: [RemoteUsage] = []
        while true {
            var parts = URLComponents(string: "\(baseURL)/api/collections/user_food_usage/records")
            parts?.queryItems = [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "perPage", value: "100"), URLQueryItem(name: "sort", value: "-usage_count,-last_used_at")]
            guard let url = parts?.url else { return nil }
            var request = URLRequest(url: url); request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
                let value = try JSONDecoder().decode(Page.self, from: data)
                result += value.items
                if value.page >= value.totalPages { return result }
                page += 1
            } catch { logger.error("Food usage hydration failed: \(error.localizedDescription, privacy: .public)"); return nil }
        }
    }

    private func apply(_ values: [RemoteUsage], scope: String) {
        var totals: [UUID: Int] = [:]; var dates: [UUID: Date] = [:]
        var sourceTotals: [String: Int] = [:]; var sourceDates: [String: Date] = [:]
        for value in values {
            sourceTotals[value.sourceKey] = value.usageCount
            let date = CalorieEntrySyncService.date(from: value.lastUsedAt)
            if let date { sourceDates[value.sourceKey] = date }
            if let rawID = value.clientItemID, let id = UUID(uuidString: rawID) {
                totals[id] = max(totals[id, default: 0], value.usageCount)
                if let date { dates[id] = max(dates[id] ?? .distantPast, date) }
            }
        }
        let recent = dates.keys.sorted { (dates[$0] ?? .distantPast) > (dates[$1] ?? .distantPast) }
        let recentSources = sourceDates.keys.sorted { (sourceDates[$0] ?? .distantPast) > (sourceDates[$1] ?? .distantPast) }
        if totalCounts != totals { totalCounts = totals }
        if lastUsed != dates { lastUsed = dates }
        if sourceTotalCounts != sourceTotals { sourceTotalCounts = sourceTotals }
        if sourceLastUsed != sourceDates { sourceLastUsed = sourceDates }
        if !counts.isEmpty { counts = [:] }
        if recentItemIDs != recent { recentItemIDs = recent }
        if recentSourceKeys != recentSources { recentSourceKeys = recentSources }
        revision &+= 1
        save(scope: scope)
    }

    private func makeKey(foodId: UUID, categoryId: UUID) -> String { "\(foodId.uuidString)_\(categoryId.uuidString)" }
    private func storageKey(_ scope: String) -> String { "food_usage_cache_\(scope)_v2" }
    private func save(scope: String) {
        let value = Cache(
            counts: counts, recent: recentItemIDs, totals: totalCounts, last: lastUsed,
            sourceTotals: sourceTotalCounts, sourceLast: sourceLastUsed, recentSources: recentSourceKeys
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: storageKey(scope))
    }
    private func load(scope: String) {
        guard let data = UserDefaults.standard.data(forKey: storageKey(scope)), let value = try? JSONDecoder().decode(Cache.self, from: data) else {
            counts = [:]; recentItemIDs = []; totalCounts = [:]; lastUsed = [:]
            sourceTotalCounts = [:]; sourceLastUsed = [:]; recentSourceKeys = []
            revision &+= 1
            return
        }
        counts = value.counts; recentItemIDs = value.recent; totalCounts = value.totals; lastUsed = value.last
        sourceTotalCounts = value.sourceTotals ?? [:]
        sourceLastUsed = value.sourceLast ?? [:]
        recentSourceKeys = value.recentSources ?? []
        revision &+= 1
    }
}
