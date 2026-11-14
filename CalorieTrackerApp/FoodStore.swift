import Foundation
import Combine
import SwiftUI
import OSLog

private actor GlobalFoodDiskCache {
    static let shared = GlobalFoodDiskCache()

    func load(key: String, limit: Int) -> [FoodItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) else { return [] }
        return Array(decoded.lazy.filter { $0.globalModerationStatus == nil || $0.globalModerationStatus == .approved }.prefix(limit))
    }

    func save(_ foods: [FoodItem], key: String) {
        guard let data = try? JSONEncoder().encode(foods) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Shared relevance ordering for every food picker. A short, exact food name
/// (for example "Kiwi") must win over products that merely contain that word.
enum FoodSearchRanker {
    nonisolated private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    nonisolated private static func normalizedQuery(_ value: String) -> String {
        normalized(value).split(separator: " ").map { $0 == "doener" ? "doner" : String($0) }.joined(separator: " ")
    }

    nonisolated static func matches(_ food: FoodItem, query: String) -> Bool {
        let needle = normalizedQuery(query)
        guard !needle.isEmpty else { return true }
        let names = [food.name, food.nameDE].compactMap { $0 }.map(normalized)
        if names.contains(where: { $0.contains(needle) }) { return true }

        let tokens = needle.split(separator: " ").map(String.init)
        if names.contains(where: { name in tokens.allSatisfy(name.contains) }) { return true }
        if let brand = food.brand {
            let brandName = normalized(brand)
            if brandName.contains(needle) || compact(brandName).contains(compact(needle)) { return true }
            // A restaurant and its menu item can be searched together, e.g.
            // "Subway Chicken Teriyaki" or "McDonalds McRib".
            if tokens.allSatisfy({ token in
                names.contains(where: { $0.contains(token) }) || brandName.contains(token)
                    || compact(brandName).contains(compact(token))
            }) { return true }
        }
        return food.barcode?.contains(query.trimmingCharacters(in: .whitespacesAndNewlines)) ?? false
    }

    nonisolated private static func compact(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "")
    }

    nonisolated static func orderedBefore(_ lhs: FoodItem, _ rhs: FoodItem, query: String) -> Bool {
        let left = rank(lhs, query: query)
        let right = rank(rhs, query: query)
        if left.score != right.score { return left.score < right.score }
        if left.length != right.length { return left.length < right.length }
        return normalized(lhs.name) < normalized(rhs.name)
    }

    nonisolated static func relevanceScore(_ food: FoodItem, query: String) -> Int {
        rank(food, query: query).score
    }

    nonisolated private static func rank(_ food: FoodItem, query: String) -> (score: Int, length: Int) {
        let needle = normalizedQuery(query)
        let names = [food.name, food.nameDE].compactMap { $0 }.map(normalized)
        let nameLength = names.filter { $0.contains(needle) }.map(\.count).min() ?? names.map(\.count).min() ?? .max
        let rawQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let unbranded = food.brand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let referenceFood = unbranded && food.externalSource == nil
        let prefix = names.contains { $0.hasPrefix(needle + " ") }
        let rawStaple = prefix && names.contains { $0 == needle + " roh" || $0.hasPrefix(needle + " roh ") }
        let brandName = food.brand.map(normalized) ?? ""
        let tokens = needle.split(separator: " ").map(String.init)

        if food.barcode == rawQuery { return (-1, nameLength) }
        if !brandName.isEmpty && compact(brandName) == compact(needle) {
            return (food.externalSource == "Open Food Facts" ? 1 : 0, nameLength)
        }
        if food.externalSource != "Open Food Facts", !brandName.isEmpty, tokens.count > 1,
           tokens.contains(where: { brandName.contains($0) || compact(brandName).contains(compact($0)) }),
           tokens.contains(where: { token in names.contains(where: { $0.contains(token) }) }),
           tokens.allSatisfy({ token in
               names.contains(where: { $0.contains(token) }) || brandName.contains(token)
                   || compact(brandName).contains(compact(token))
           }) { return (2, nameLength) }
        if referenceFood && needle == "doner" && names.contains(where: { $0.hasPrefix("doner kebab") }) { return (1, nameLength) }
        if referenceFood && rawStaple { return (1, nameLength) }
        if referenceFood && names.contains(needle) { return (2, nameLength) }
        if referenceFood && prefix { return (3, nameLength) }
        if names.contains(needle) { return (4, nameLength) }
        if prefix { return (5, nameLength) }
        if names.contains(where: { $0.contains(needle) }) { return (6, nameLength) }

        if names.contains(where: { name in tokens.allSatisfy(name.contains) }) { return (7, nameLength) }
        if let brand = food.brand {
            let normalizedBrand = normalized(brand)
            if normalizedBrand.hasPrefix(needle + " ") { return (8, nameLength) }
            if normalizedBrand.contains(needle) { return (9, nameLength) }
            if tokens.allSatisfy({ token in
                names.contains(where: { $0.contains(token) }) || normalizedBrand.contains(token)
                    || compact(normalizedBrand).contains(compact(token))
            }) { return (10, nameLength) }
        }
        return (11, nameLength)
    }
}

/// Stable identities for food history. Catalogue products are not necessarily
/// loaded locally after a restart, so the server record ID is retained and can
/// be used to fetch the exact product again.
enum FoodHistoryIdentity {
    nonisolated static func key(for food: FoodItem) -> String {
        FrequencyStore.sourceKey(for: food)
    }

    nonisolated static func foodMap(_ foods: [FoodItem]) -> [String: FoodItem] {
        foods.reduce(into: [String: FoodItem]()) { result, food in
            result[key(for: food)] = food
            result[food.id.uuidString.lowercased()] = food // v1 history migration
            result["local:\(food.id.uuidString.lowercased())"] = food
            if let globalID = food.globalRecordID, !globalID.isEmpty {
                result["global:\(globalID)"] = food
                result["global_food:\(globalID)"] = food
            }
        }
    }

    nonisolated static func globalRecordIDs(from keys: some Sequence<String>) -> [String] {
        Array(Set(keys.compactMap { key in
            if key.hasPrefix("global_food:") { return String(key.dropFirst("global_food:".count)) }
            if key.hasPrefix("global:") { return String(key.dropFirst("global:".count)) }
            return nil
        }.filter { !$0.isEmpty }))
    }
}

enum FoodSyncState: Equatable {
    case idle, syncing, synced(Date), waitingToRetry, offline
}

@MainActor
final class FoodStore: ObservableObject {
    @Published private(set) var foods: [FoodItem] = [] {
        didSet {
            combinedFoodsCache = nil
            personalBarcodeIndex = Self.makeBarcodeIndex(foods)
        }
    }
    @Published private(set) var globalFoods: [FoodItem] = [] {
        didSet {
            combinedFoodsCache = nil
            globalBarcodeIndex = Self.makeBarcodeIndex(globalFoods, approvedOnly: true)
        }
    }
    @Published private(set) var syncState: FoodSyncState = .idle
    @Published private(set) var favoriteGlobalRecordIDs: Set<String> = [] { didSet { combinedFoodsCache = nil } }
    @Published private(set) var pendingGuestFavoriteMergeCount = 0
    weak var authManager: AuthManager?
    private var activatedAccountID: String?
    private var profileRevision: UInt = 0
    private var syncRevision: UInt = 0
    private var syncTask: Task<Void, Never>?
    private var deferredSyncTask: Task<Void, Never>?
    private var syncRetryTask: Task<Void, Never>?
    private var syncRetryAttempt = 0
    private var favoriteSyncTask: Task<Void, Never>?
    private var globalSubmissionTask: Task<Void, Never>?
    private var globalSubmissionRetryTask: Task<Void, Never>?
    private var globalSubmissionRetryAttempt = 0
    private var lastSuccessfulSyncAt: Date?
    private var barcodeLookupCache: [String: (date: Date, foods: [FoodItem])] = [:]
    private var persistedGlobalBarcodeCache: [String: [FoodItem]] = [:]
    private var personalBarcodeIndex: [String: [FoodItem]] = [:]
    private var globalBarcodeIndex: [String: [FoodItem]] = [:]
    private var globalTextSearchCache: [String: (date: Date, foods: [FoodItem])] = [:]
    private var combinedFoodsCache: [FoodItem]?
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "FoodScope")

    private let storageKey = "saved_food_items_v1"
    private let globalStorageKey = "global_food_items_v1"
    private let globalCatalogueRefreshKey = "global_food_items_last_refresh_v1"
    private let globalBarcodeStorageKey = "global_food_barcode_cache_v1"
    private let guestFavoritesKey = "global_food_favorites_guest"
    private var activeStorageKey: String {
        activatedAccountID.map { "\(storageKey)_account_\($0)" } ?? "\(storageKey)_guest"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: globalBarcodeStorageKey),
           let cached = try? JSONDecoder().decode([String: [FoodItem]].self, from: data) {
            persistedGlobalBarcodeCache = cached
        }
        load()
        loadFavoriteIDsForActiveProfile()
        if foods.isEmpty,
           UserDefaults.standard.data(forKey: activeStorageKey) == nil,
           UserDefaults.standard.data(forKey: storageKey) == nil {
            seedDefaults()
        }
        Task { [weak self] in
            let cached = await GlobalFoodDiskCache.shared.load(key: self?.globalStorageKey ?? "global_food_items_v1", limit: 500)
            guard let self, self.globalFoods.isEmpty else { return }
            self.globalFoods = cached
        }
    }

    func addFood(_ item: FoodItem) {
        barcodeLookupCache.removeAll()
        let oldPortions = foods.first { $0.id == item.id }?.portions ?? []
        if let index = foods.firstIndex(where: { $0.id == item.id }) { foods[index] = item }
        else { foods.append(item) }
        markDirty(item.id)
        if oldPortions != item.portions { markPortionsDirty(item.id) }
        save()
        schedulePendingFoodSync()
    }

    func searchBrands(_ query: String) async throws -> [FoodBrand] {
        let token = authManager?.isLoggedIn == true ? authManager?.token ?? "" : ""
        return try await BrandService.shared.search(query: query, token: token)
    }

    func createBrand(named name: String) async throws -> FoodBrand {
        guard let authManager, authManager.isLoggedIn, !authManager.token.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        return try await BrandService.shared.create(name: name, token: authManager.token)
    }

    func addFoodResolvingGlobal(_ item: FoodItem) async -> FoodItem {
        // Persist first. Global catalogue submission is a separate best-effort
        // operation and must not delay or invalidate the user's private food.
        if let authManager, authManager.isLoggedIn, activatedAccountID != authManager.accountID {
            activateAccount()
        }
        var saved = item
        // Third-party data stays a private, attributed copy and must never be
        // republished as a user-created Hyse catalogue record.
        saved.globalSubmissionPending = authManager?.isLoggedIn == true && saved.externalSource == nil
        addFood(saved)
        retryPendingGlobalSubmissions()
        return saved
    }

    private func submitGlobalRevision(_ item: FoodItem) {
        guard let authManager, authManager.isLoggedIn, !authManager.token.isEmpty else { return }
        let token = authManager.token
        let accountID = authManager.accountID
        let expectedRevision = profileRevision
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let resolution = try await GlobalFoodService.shared.submitChange(item, token: token)
                guard self.profileRevision == expectedRevision, self.activatedAccountID == accountID else { return }
                if let index = foods.firstIndex(where: { $0.id == item.id }) {
                    foods[index].globalSubmissionID = resolution.id
                    foods[index].globalRecordID = resolution.globalFood ?? item.globalRecordID
                    foods[index].globalCreatorID = accountID
                    foods[index].globalModerationStatus = GlobalModerationStatus(rawValue: resolution.status) ?? .approved
                    foods[index].globalRejectionReason = resolution.rejectionReason
                    markDirty(item.id)
                    save()
                    schedulePendingFoodSync()
                }
            } catch {
                // A revision failure never changes the private saved-food state.
            }
        }
    }

    func updateFood(_ item: FoodItem) {
        barcodeLookupCache.removeAll()
        if let index = foods.firstIndex(where: { $0.id == item.id }) {
            var value = item
            let portionsChanged = foods[index].portions != value.portions
            let shouldSubmitRevision = value.globalRecordID != nil
                && value.externalSource == nil
                && authManager?.isLoggedIn == true
                && !Self.hasSameCatalogueContent(foods[index], value)
            if shouldSubmitRevision {
                value.globalModerationStatus = .pending
                value.globalSubmissionID = nil
                value.globalRejectionReason = nil
            } else if value.globalRecordID == nil {
                value.globalSubmissionPending = authManager?.isLoggedIn == true && value.externalSource == nil
            }
            foods[index] = value
            markDirty(item.id)
            if portionsChanged { markPortionsDirty(item.id) }
            save()
            schedulePendingFoodSync()
            if shouldSubmitRevision { submitGlobalRevision(value) }
            else { retryPendingGlobalSubmissions() }
        } else if item.globalRecordID != nil {
            // Editing a catalogue result always creates an offline-first local
            // copy. New or changed portions are queued for global publication
            // by the portion editor and remain usable offline while syncing.
            var value = item
            let catalogueSource = globalFoods.first { $0.globalRecordID == item.globalRecordID }
            let shouldSubmitRevision = value.externalSource == nil
                && authManager?.isLoggedIn == true
                && catalogueSource.map { !Self.hasSameCatalogueContent($0, value) } != false
            if shouldSubmitRevision {
                value.globalModerationStatus = .pending
                value.globalSubmissionID = nil
                value.globalRejectionReason = nil
            }
            foods.append(value)
            markDirty(value.id)
            if !value.portions.isEmpty { markPortionsDirty(value.id) }
            save()
            schedulePendingFoodSync()
            if shouldSubmitRevision { submitGlobalRevision(value) }
        } else {
            // Drafts and imported foods can also receive personal portions.
            // Persist them locally even when no global catalogue relation exists.
            var value = item
            value.globalSubmissionPending = authManager?.isLoggedIn == true && value.externalSource == nil
            addFood(value)
            retryPendingGlobalSubmissions()
        }
    }

    private static func hasSameCatalogueContent(_ lhs: FoodItem, _ rhs: FoodItem) -> Bool {
        lhs.name == rhs.name
            && lhs.nameDE == rhs.nameDE
            && lhs.brand == rhs.brand
            && lhs.brandRecordID == rhs.brandRecordID
            && lhs.kcalPer100g == rhs.kcalPer100g
            && lhs.carbsPer100g == rhs.carbsPer100g
            && lhs.proteinPer100g == rhs.proteinPer100g
            && lhs.fatPer100g == rhs.fatPer100g
            && lhs.sugarPer100g == rhs.sugarPer100g
            && lhs.fiberPer100g == rhs.fiberPer100g
            && lhs.saturatedFatPer100g == rhs.saturatedFatPer100g
            && lhs.saltPer100g == rhs.saltPer100g
            && lhs.barcode == rhs.barcode
            && lhs.unit == rhs.unit
            && lhs.isFruit == rhs.isFruit
    }

    func deleteFood(id: UUID) {
        guard foods.contains(where: { $0.id == id }) else { return }
        let remaining = foods.filter { $0.id != id }
        guard let data = try? JSONEncoder().encode(remaining) else {
            logger.error("Could not encode saved foods after deletion")
            return
        }
        barcodeLookupCache.removeAll()
        markDeleted(id)
        UserDefaults.standard.set(data, forKey: activeStorageKey)
        _ = UserDefaults.standard.synchronize()
        foods = remaining
        if let accountID = authManager?.accountID, authManager?.isLoggedIn == true {
            var changed = storedIDs(portionsDirtyKey(accountID))
            changed.remove(id)
            storeIDs(changed, key: portionsDirtyKey(accountID))
        }
        schedulePendingFoodSync()
    }

    func deleteFood(at offsets: IndexSet) {
        let ids = offsets.map { foods[$0].id }
        ids.forEach(deleteFood)
    }

    func findByBarcode(_ barcode: String) -> FoodItem? {
        guard let normalized = try? BarcodeNormalizer.normalize(barcode) else { return nil }
        return barcodeMatches(normalized).first
    }

    /// Personal foods always win over the approved shared catalogue. Returning
    /// every top-priority match lets the scanner surface legacy conflicts rather
    /// than choosing an unrelated product silently.
    func barcodeMatches(_ normalizedBarcode: String) -> [FoodItem] {
        let personal = personalBarcodeIndex[normalizedBarcode] ?? []
        if !personal.isEmpty { return personal }
        let global = globalBarcodeIndex[normalizedBarcode] ?? []
        if !global.isEmpty { return global }
        return persistedGlobalBarcodeCache[normalizedBarcode] ?? []
    }

    func lookupKnownBarcode(_ normalizedBarcode: String) async -> [FoodItem] {
        let cached = barcodeMatches(normalizedBarcode)
        if !cached.isEmpty { return cached }
        if let cachedRemote = barcodeLookupCache[normalizedBarcode],
           Date().timeIntervalSince(cachedRemote.date) < 5 * 60 {
            return cachedRemote.foods
        }
        guard let authManager, authManager.isLoggedIn, !authManager.token.isEmpty else { return [] }
        let token = authManager.token

        // Both PocketBase collections are indexed by barcode. Return as soon as
        // either one has a match instead of making a global catalogue hit wait
        // for a slower personal-food request (or the other way around).
        let matches = await withTaskGroup(of: [FoodItem].self, returning: [FoodItem].self) { group in
            group.addTask {
                await FoodSyncService.shared.lookupBarcode(normalizedBarcode, token: token)
            }
            group.addTask {
                await GlobalFoodService.shared.lookupBarcode(normalizedBarcode, token: token)
            }
            while let result = await group.next() {
                if !result.isEmpty {
                    group.cancelAll()
                    return result
                }
            }
            return []
        }
        // Cache hits and misses. A short negative cache makes an accidental
        // rescan instant without hiding newly-created products for long.
        barcodeLookupCache[normalizedBarcode] = (Date(), matches)
        rememberGlobalBarcodeMatches(matches, barcode: normalizedBarcode)
        return matches
    }

    private func rememberGlobalBarcodeMatches(_ matches: [FoodItem], barcode: String) {
        let approvedGlobals = matches.filter {
            $0.globalRecordID != nil
                && ($0.globalModerationStatus == nil || $0.globalModerationStatus == .approved)
        }
        guard !approvedGlobals.isEmpty else { return }
        persistedGlobalBarcodeCache[barcode] = approvedGlobals
        while persistedGlobalBarcodeCache.count > 120,
              let staleKey = persistedGlobalBarcodeCache.keys.first(where: { $0 != barcode }) {
            persistedGlobalBarcodeCache.removeValue(forKey: staleKey)
        }
        if let data = try? JSONEncoder().encode(persistedGlobalBarcodeCache) {
            UserDefaults.standard.set(data, forKey: globalBarcodeStorageKey)
        }
        // Also expose the result to text search and the in-memory barcode index.
        mergeGlobalSearch(approvedGlobals)
    }

    private static func makeBarcodeIndex(_ values: [FoodItem], approvedOnly: Bool = false) -> [String: [FoodItem]] {
        var result: [String: [FoodItem]] = [:]
        result.reserveCapacity(min(values.count, 2_048))
        for food in values {
            if approvedOnly, food.globalModerationStatus != nil, food.globalModerationStatus != .approved { continue }
            guard let barcode = BarcodeNormalizer.normalizedIfValid(food.barcode) else { continue }
            result[barcode, default: []].append(food)
        }
        return result
    }

    func searchFoods(query: String, categoryId: UUID? = nil, frequencyStore: FrequencyStore? = nil, includeGlobals: Bool = true) -> [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [FoodItem]
        if trimmed.isEmpty {
            filtered = includeGlobals ? combinedFoods : foods
        } else {
            filtered = (includeGlobals ? combinedFoods : foods).filter { FoodSearchRanker.matches($0, query: trimmed) }
            return filtered.sorted { FoodSearchRanker.orderedBefore($0, $1, query: trimmed) }
        }

        if categoryId != nil, let freq = frequencyStore {
            return filtered.sorted {
                freq.totalUsageCount(food: $0) > freq.totalUsageCount(food: $1)
            }
        }

        return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func hydrateGlobalSearch(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let authManager, authManager.isLoggedIn, !authManager.token.isEmpty else { return }
        let cacheKey = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let cached = globalTextSearchCache[cacheKey], Date().timeIntervalSince(cached.date) < 900 {
            mergeGlobalSearch(cached.foods)
            return
        }
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        guard !Task.isCancelled else { return }
        guard let matches = await GlobalFoodService.shared.search(trimmed, token: authManager.token) else {
            // Never turn a timeout or server error into a 15-minute negative
            // cache entry. The next edit/retry can immediately query again.
            globalTextSearchCache.removeValue(forKey: cacheKey)
            return
        }
        guard !Task.isCancelled else { return }
        // Show the indexed food results immediately. Shared portion metadata
        // follows without blocking the visible search list.
        mergeGlobalSearch(matches)
        let ids = Set(matches.compactMap(\.globalRecordID))
        let portions = await FoodPortionSyncService.shared.fetchApproved(globalFoodIDs: ids, token: authManager.token)
        guard !Task.isCancelled else { return }
        let enriched = matches.map { food in
            var value = food
            if let globalID = food.globalRecordID, let shared = portions[globalID] {
                value.portions = shared.normalized(defaultUnit: food.unit)
                value.servingSizeAmount = value.defaultPortionBaseAmount
            }
            return value
        }
        globalTextSearchCache[cacheKey] = (Date(), enriched)
        if globalTextSearchCache.count > 40,
           let oldest = globalTextSearchCache.min(by: { $0.value.date < $1.value.date })?.key {
            globalTextSearchCache.removeValue(forKey: oldest)
        }
        mergeGlobalSearch(enriched)
    }

    func hydrateGlobalFoods(recordIDs: [String]) async {
        guard let authManager, authManager.isLoggedIn, !authManager.token.isEmpty else { return }
        let loaded = Set(globalFoods.compactMap(\.globalRecordID))
        let missing = Array(Set(recordIDs).subtracting(loaded))
        guard !missing.isEmpty else { return }
        let matches = await GlobalFoodService.shared.fetch(recordIDs: missing, token: authManager.token)
        guard !Task.isCancelled else { return }
        mergeGlobalSearch(matches)
    }

    private func mergeGlobalSearch(_ matches: [FoodItem]) {
        guard !matches.isEmpty else { return }
        var merged = globalFoods
        for food in matches {
            guard let recordID = food.globalRecordID else { continue }
            if let index = merged.firstIndex(where: { $0.globalRecordID == recordID }) { merged[index] = food }
            else { merged.append(food) }
        }
        if merged.count > 750 { merged = Array(merged.prefix(600)) + Array(merged.suffix(150)) }
        globalFoods = Self.deduplicatedByID(merged)
        saveGlobalFoods()
    }

    func food(id: UUID) -> FoodItem? { combinedFoods.first { $0.id == id } }
    var availableFoods: [FoodItem] { combinedFoods }
    var micronutrientScopeID: String { activatedAccountID ?? "guest" }

    /// OFF enrichment changes a private nutrient snapshot, never catalogue
    /// content. In particular this must not submit a global revision.
    func applyOpenFoodFactsMicronutrients(_ imported: MicronutrientProfile, barcode: String) {
        guard !imported.isEmpty else { return }
        var personalChanged = false
        for index in foods.indices where BarcodeNormalizer.normalizedIfValid(foods[index].barcode) == barcode {
            let converted = imported.converted(from: .gram, to: foods[index].unit)
            let updated = foods[index].micronutrients?.addingOpenFoodFacts(converted) ?? converted
            guard foods[index].micronutrients != updated else { continue }
            foods[index].micronutrients = updated
            markDirty(foods[index].id)
            personalChanged = true
        }
        if personalChanged {
            save()
            schedulePendingFoodSync()
        }
        var globalChanged = false
        for index in globalFoods.indices where BarcodeNormalizer.normalizedIfValid(globalFoods[index].barcode) == barcode {
            let converted = imported.converted(from: .gram, to: globalFoods[index].unit)
            let updated = globalFoods[index].micronutrients?.addingOpenFoodFacts(converted) ?? converted
            guard globalFoods[index].micronutrients != updated else { continue }
            globalFoods[index].micronutrients = updated
            globalChanged = true
        }
        if globalChanged { saveGlobalFoods() }
    }
    func isGlobalFood(_ id: UUID) -> Bool { globalFoods.contains { food in food.id == id } }
    func isFavorite(_ food: FoodItem) -> Bool {
        guard let globalID = food.globalRecordID else { return food.isFavorite }
        return favoriteGlobalRecordIDs.contains(globalID)
    }

    func toggleFavorite(_ food: FoodItem) {
        guard let globalID = food.globalRecordID else {
            var updated = food; updated.isFavorite.toggle(); updateFood(updated); return
        }
        if favoriteGlobalRecordIDs.contains(globalID) { favoriteGlobalRecordIDs.remove(globalID) } else { favoriteGlobalRecordIDs.insert(globalID) }
        saveFavoriteIDs()
        syncFavorites(useLocalDesiredState: true)
    }

    private var combinedFoods: [FoodItem] {
        if let combinedFoodsCache { return combinedFoodsCache }
        let personal = Self.deduplicatedByID(foods)
        let personalIDs = Set(personal.map(\.id))
        let personalFingerprints = Set(personal.map(FoodSyncService.fingerprint))
        let globals = Self.deduplicatedByID(globalFoods).filter { food in
            !personalIDs.contains(food.id)
                && !personalFingerprints.contains(FoodSyncService.fingerprint(food))
        }.map { food in
            var value = food
            value.isFavorite = value.globalRecordID.map(favoriteGlobalRecordIDs.contains) ?? false
            return value
        }
        let result = personal + globals
        combinedFoodsCache = result
        return result
    }

    private static func deduplicatedByID(_ values: [FoodItem]) -> [FoodItem] {
        var seen = Set<UUID>()
        return values.reversed().filter { seen.insert($0.id).inserted }.reversed()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(foods) {
            UserDefaults.standard.set(data, forKey: activeStorageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: activeStorageKey) ?? (authManager?.isLoggedIn == true ? nil : UserDefaults.standard.data(forKey: storageKey)),
              let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) else {
            return
        }
        foods = Self.deduplicatedByID(decoded)
    }

    private func saveGlobalFoods() {
        let snapshot = globalFoods.count <= 500
            ? globalFoods
            : Array(globalFoods.prefix(350)) + Array(globalFoods.suffix(150))
        Task { await GlobalFoodDiskCache.shared.save(snapshot, key: globalStorageKey) }
    }

    func activateAccount() {
        guard let authManager, authManager.isLoggedIn, activatedAccountID != authManager.accountID else { return }
        barcodeLookupCache.removeAll()
        let accountID = authManager.accountID
        profileRevision &+= 1
        syncRevision &+= 1
        syncTask?.cancel()
        deferredSyncTask?.cancel()
        syncRetryTask?.cancel()
        syncRetryTask = nil
        syncRetryAttempt = 0
        favoriteSyncTask?.cancel()
        globalSubmissionTask?.cancel()
        globalSubmissionRetryTask?.cancel()
        globalSubmissionRetryTask = nil
        globalSubmissionRetryAttempt = 0
        activatedAccountID = accountID
        let guestFoods: [FoodItem] = UserDefaults.standard.data(forKey: "\(storageKey)_guest").flatMap { try? JSONDecoder().decode([FoodItem].self, from: $0) } ?? []
        let guestFavorites = Set(UserDefaults.standard.stringArray(forKey: guestFavoritesKey) ?? [])
        loadFavoriteIDsForActiveProfile()
        let handledKey = "handled_guest_favorite_ids_\(accountID)"
        let handledFavorites = Set(UserDefaults.standard.stringArray(forKey: handledKey) ?? [])
        let pendingFavorites = guestFavorites.subtracting(handledFavorites)
        pendingGuestFavoriteMergeCount = pendingFavorites.count
        if !pendingFavorites.isEmpty { UserDefaults.standard.set(Array(pendingFavorites), forKey: "pending_guest_global_favorites") }
        else { UserDefaults.standard.removeObject(forKey: "pending_guest_global_favorites") }
        foods = []
        load()
        lastSuccessfulSyncAt = UserDefaults.standard.object(forKey: lastSuccessfulSyncKey(accountID)) as? Date
        if let lastSuccessfulSyncAt { syncState = .synced(lastSuccessfulSyncAt) }
        let knownFingerprints = Set(foods.map(FoodSyncService.fingerprint))
        let importedGuestFoods = guestFoods.filter {
            !Self.bundledDefaultFingerprints.contains(FoodSyncService.fingerprint($0))
                && !knownFingerprints.contains(FoodSyncService.fingerprint($0))
        }
        if !importedGuestFoods.isEmpty {
            foods.append(contentsOf: importedGuestFoods)
            var dirty = storedIDs(dirtyKey(accountID))
            dirty.formUnion(importedGuestFoods.map(\.id))
            storeIDs(dirty, key: dirtyKey(accountID))
            var changedPortions = storedIDs(portionsDirtyKey(accountID))
            changedPortions.formUnion(importedGuestFoods.filter { !$0.portions.isEmpty }.map(\.id))
            storeIDs(changedPortions, key: portionsDirtyKey(accountID))
            save()
        }
        // Earlier app versions made catalogue submission opt-in. Queue every
        // user-created food that still has no catalogue relation so those
        // records are repaired automatically after updating the app. Bundled
        // defaults are deliberately excluded.
        var queuedLegacySubmission = false
        for index in foods.indices where foods[index].globalRecordID == nil
            && foods[index].globalSubmissionID == nil
            && foods[index].externalSource == nil
            && !Self.bundledDefaultFingerprints.contains(FoodSyncService.fingerprint(foods[index])) {
            if !foods[index].globalSubmissionPending {
                foods[index].globalSubmissionPending = true
                queuedLegacySubmission = true
            }
        }
        if queuedLegacySubmission { save() }
        syncPendingFoods()
        retryPendingGlobalSubmissions()
        syncFavorites(useLocalDesiredState: UserDefaults.standard.object(forKey: favoriteAccountKey) != nil)
#if DEBUG
        logger.debug("Hydrated saved-food scope=user:\(accountID, privacy: .public) count=\(self.foods.count)")
#endif
    }

    func deactivateAccount() {
        barcodeLookupCache.removeAll()
        profileRevision &+= 1
        syncRevision &+= 1
        syncTask?.cancel()
        syncRetryTask?.cancel()
        favoriteSyncTask?.cancel()
        globalSubmissionTask?.cancel()
        globalSubmissionRetryTask?.cancel()
        syncTask = nil
        deferredSyncTask = nil
        syncRetryTask = nil
        syncRetryAttempt = 0
        favoriteSyncTask = nil
        globalSubmissionTask = nil
        globalSubmissionRetryTask = nil
        globalSubmissionRetryAttempt = 0
        activatedAccountID = nil
        favoriteGlobalRecordIDs = Set(UserDefaults.standard.stringArray(forKey: guestFavoritesKey) ?? [])
        pendingGuestFavoriteMergeCount = 0
        syncState = .idle
        lastSuccessfulSyncAt = nil
        foods = []
        load()
        if foods.isEmpty { seedDefaults() }
#if DEBUG
        logger.debug("Hydrated saved-food scope=guest count=\(self.foods.count)")
#endif
    }

    func syncPendingFoods() {
        guard let authManager, authManager.isLoggedIn,
              activatedAccountID == authManager.accountID,
              !authManager.token.isEmpty else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = nil
        syncRetryTask?.cancel()
        syncRetryTask = nil
        let accountID = authManager.accountID, token = authManager.token, local = foods
        let dirty = storedIDs(dirtyKey(accountID)), deleted = storedIDs(deletedKey(accountID))
        let changedPortions = storedIDs(portionsDirtyKey(accountID))
        if dirty.isEmpty, deleted.isEmpty, changedPortions.isEmpty,
           case .synced = syncState,
           let lastSuccessfulSyncAt, Date().timeIntervalSince(lastSuccessfulSyncAt) < 3_600 {
            return
        }
        syncState = .syncing
        let expectedProfileRevision = profileRevision
        syncRevision &+= 1
        let expectedSyncRevision = syncRevision
        let lastGlobalRefresh = UserDefaults.standard.object(forKey: globalCatalogueRefreshKey) as? Date
        let refreshGlobalCatalogue = lastGlobalRefresh.map { Date().timeIntervalSince($0) >= 86_400 } != false
        syncTask?.cancel()
        syncTask = Task {
            async let globalResult: [FoodItem]? = refreshGlobalCatalogue ? GlobalFoodService.shared.fetch(token: token) : nil
            let result = await FoodSyncService.shared.sync(foods: local, dirty: dirty, deleted: deleted, userID: accountID, token: token)
            let fetchedGlobals = await globalResult
            // Shared portions are loaded for the user's saved foods here and
            // for catalogue search results on demand. Do not fan out requests
            // across the complete offline starter catalogue.
            let portionSnapshot = await FoodPortionSyncService.shared.sync(foods: local, remoteFoods: result.foods,
                                                                          changedFoodIDs: changedPortions, userID: accountID, token: token)
            // Fetch after uploads so a newly-created revision is reflected in
            // the same UI refresh instead of briefly reverting to "approved".
            let needsSubmissionState = local.contains { $0.globalSubmissionID != nil || $0.globalSubmissionPending }
            let submissions = needsSubmissionState
                ? await GlobalFoodService.shared.fetchSubmissionStatuses(token: token)
                : [:]
            if let fetchedGlobals {
                await MainActor.run {
                    self.barcodeLookupCache.removeAll()
                    self.globalFoods = fetchedGlobals.map { food in
                        var value = food
                        if let globalID = food.globalRecordID, let portions = portionSnapshot.globalByRecordID[globalID] {
                            value.portions = portions.normalized(defaultUnit: food.unit)
                            value.servingSizeAmount = value.defaultPortionBaseAmount
                        }
                        return value
                    }
                    self.saveGlobalFoods()
                    UserDefaults.standard.set(Date(), forKey: self.globalCatalogueRefreshKey)
                }
            }
            guard result.didFetch else {
                await MainActor.run {
                    guard self.isCurrent(accountID: accountID, profileRevision: expectedProfileRevision, syncRevision: expectedSyncRevision) else { return }
                    self.syncState = .offline
                    self.scheduleSyncRetry(for: accountID)
                }
                return
            }
            let remote = result.foods.compactMap { remote in
                let id = UUID(uuidString: remote.clientID)
                return FoodSyncService.shared.food(from: remote, portions: id.flatMap { portionSnapshot.personalByClientID[$0] } ?? [])
            }
            await MainActor.run {
                guard self.isCurrent(accountID: accountID, profileRevision: expectedProfileRevision, syncRevision: expectedSyncRevision),
                      self.authManager?.isLoggedIn == true,
                      self.authManager?.accountID == accountID else {
#if DEBUG
                    self.logger.debug("Ignored stale saved-food response for user:\(accountID, privacy: .public)")
#endif
                    return
                }
                var globalStatus: [String: GlobalModerationStatus] = [:]
                var globalCreators: [String: String] = [:]
                for food in fetchedGlobals ?? self.globalFoods {
                    if let id = food.globalRecordID {
                        globalStatus[id] = food.globalModerationStatus ?? .approved
                        globalCreators[id] = food.globalCreatorID
                    }
                }
                let uploadedSnapshot = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
                let currentSnapshot = Dictionary(uniqueKeysWithValues: self.foods.map { ($0.id, $0) })
                let confirmedUploads = result.uploaded.filter { currentSnapshot[$0] == uploadedSnapshot[$0] }
                var remainingDirty = self.storedIDs(self.dirtyKey(accountID)); remainingDirty.subtract(confirmedUploads)
                var remainingDeleted = self.storedIDs(self.deletedKey(accountID)); remainingDeleted.subtract(result.deleted)
                self.storeIDs(remainingDirty, key: self.dirtyKey(accountID)); self.storeIDs(remainingDeleted, key: self.deletedKey(accountID))
                let localByID = currentSnapshot
                if portionSnapshot.didSync {
                    var remainingPortions = self.storedIDs(self.portionsDirtyKey(accountID))
                    for id in changedPortions where currentSnapshot[id]?.portions == uploadedSnapshot[id]?.portions {
                        remainingPortions.remove(id)
                    }
                    self.storeIDs(remainingPortions, key: self.portionsDirtyKey(accountID))
                }
                var merged = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
                for id in remainingDirty where !remainingDeleted.contains(id) { if let value = localByID[id] { merged[id] = value } }
                remainingDeleted.forEach { merged.removeValue(forKey: $0) }
                self.foods = Array(merged.values).map { food in
                    var value = food
                    value.globalSubmissionPending = currentSnapshot[food.id]?.globalSubmissionPending ?? value.globalSubmissionPending
                    if let submissionID = value.globalSubmissionID, let submission = submissions[submissionID] {
                        value.globalModerationStatus = submission.status
                        value.globalRejectionReason = submission.rejectionReason
                    } else if let id = value.globalRecordID, let submission = submissions[id] {
                        value.globalModerationStatus = submission.status
                        value.globalSubmissionID = submission.id
                        value.globalRejectionReason = submission.rejectionReason
                    } else if let id = value.globalRecordID {
                        value.globalModerationStatus = globalStatus[id] ?? value.globalModerationStatus
                        value.globalCreatorID = globalCreators[id]
                        value.globalSubmissionID = nil
                        value.globalRejectionReason = nil
                    }
                    return value
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.save()
                let coreSyncComplete = remainingDirty.isEmpty && remainingDeleted.isEmpty
                    && self.storedIDs(self.portionsDirtyKey(accountID)).isEmpty && !result.hadFailures
                if coreSyncComplete {
                    if portionSnapshot.didSync {
                        let now = Date()
                        self.lastSuccessfulSyncAt = now
                        UserDefaults.standard.set(now, forKey: self.lastSuccessfulSyncKey(accountID))
                        self.syncState = .synced(now)
                        self.syncRetryAttempt = 0
                    } else {
                        self.syncState = .waitingToRetry
                        self.scheduleSyncRetry(for: accountID)
                    }
                } else {
                    self.syncState = .waitingToRetry
                    self.scheduleSyncRetry(for: accountID)
                }
                self.retryPendingGlobalSubmissions()
            }
        }
    }

    /// Keeps locally queued foods durable and retries indefinitely. The delay
    /// grows after repeated failures so a server outage does not drain battery.
    private func scheduleSyncRetry(for accountID: String) {
        guard syncRetryTask == nil,
              activatedAccountID == accountID,
              authManager?.isLoggedIn == true else { return }
        let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60), .seconds(300)]
        let delay = delays[min(syncRetryAttempt, delays.count - 1)]
        syncRetryAttempt = min(syncRetryAttempt + 1, delays.count - 1)
        syncRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self,
                  self.activatedAccountID == accountID,
                  self.authManager?.isLoggedIn == true else { return }
            self.syncRetryTask = nil
            self.syncPendingFoods()
        }
    }

    private func retryPendingGlobalSubmissions() {
        guard globalSubmissionTask == nil, globalSubmissionRetryTask == nil,
              let authManager, authManager.isLoggedIn,
              activatedAccountID == authManager.accountID,
              !authManager.token.isEmpty else { return }
        // A bounded batch prevents a large offline queue from turning one
        // server-side failure into hundreds of immediate requests.
        let pending = Array(foods.lazy.filter {
            $0.globalSubmissionPending && $0.globalRecordID == nil && $0.externalSource == nil
        }.prefix(10))
        guard !pending.isEmpty else { return }
        let token = authManager.token
        let accountID = authManager.accountID
        let expectedRevision = profileRevision
        globalSubmissionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var changed = false
            var failed = false
            for item in pending {
                guard self.profileRevision == expectedRevision, self.activatedAccountID == accountID else { break }
                do {
                    let resolution = try await GlobalFoodService.shared.submitNew(item, token: token)
                    guard let index = self.foods.firstIndex(where: { $0.id == item.id }) else { continue }
                    self.foods[index].globalSubmissionID = resolution.id
                    self.foods[index].globalRecordID = resolution.globalFood
                    self.foods[index].globalCreatorID = accountID
                    self.foods[index].globalModerationStatus = GlobalModerationStatus(rawValue: resolution.status) ?? .approved
                    self.foods[index].globalRejectionReason = resolution.rejectionReason
                    self.foods[index].globalSubmissionPending = false
                    self.markDirty(item.id)
                    changed = true
                } catch {
                    self.logger.error("Global food submission retry failed: \(error.localizedDescription, privacy: .public)")
                    failed = true
                    break
                }
            }
            self.globalSubmissionTask = nil
            if changed {
                self.save()
                self.schedulePendingFoodSync()
            }
            if failed {
                self.scheduleGlobalSubmissionRetry(for: accountID, afterFailure: true)
            } else {
                self.globalSubmissionRetryAttempt = 0
                let hasMore = self.foods.contains {
                    $0.globalSubmissionPending && $0.globalRecordID == nil && $0.externalSource == nil
                }
                if hasMore { self.scheduleGlobalSubmissionRetry(for: accountID, afterFailure: false) }
            }
        }
    }

    private func scheduleGlobalSubmissionRetry(for accountID: String, afterFailure: Bool) {
        guard globalSubmissionRetryTask == nil,
              activatedAccountID == accountID,
              authManager?.isLoggedIn == true else { return }
        let failureDelays: [Duration] = [.seconds(30), .seconds(120), .seconds(300), .seconds(900), .seconds(1800)]
        let delay: Duration
        if afterFailure {
            delay = failureDelays[min(globalSubmissionRetryAttempt, failureDelays.count - 1)]
            globalSubmissionRetryAttempt = min(globalSubmissionRetryAttempt + 1, failureDelays.count - 1)
        } else {
            delay = .seconds(5)
        }
        globalSubmissionRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self,
                  self.activatedAccountID == accountID,
                  self.authManager?.isLoggedIn == true else { return }
            self.globalSubmissionRetryTask = nil
            self.retryPendingGlobalSubmissions()
        }
    }

    private func isCurrent(accountID: String, profileRevision: UInt, syncRevision: UInt) -> Bool {
        activatedAccountID == accountID && self.profileRevision == profileRevision && self.syncRevision == syncRevision
    }

    private func schedulePendingFoodSync() {
        guard activatedAccountID != nil else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            self.deferredSyncTask = nil
            self.syncPendingFoods()
        }
    }

    private var favoriteAccountKey: String { "global_food_favorites_account_\(authManager?.accountID ?? "")" }
    private func loadFavoriteIDsForActiveProfile() {
        let key = authManager?.isLoggedIn == true ? favoriteAccountKey : guestFavoritesKey
        favoriteGlobalRecordIDs = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    private func saveFavoriteIDs() {
        let key = authManager?.isLoggedIn == true ? favoriteAccountKey : guestFavoritesKey
        UserDefaults.standard.set(Array(favoriteGlobalRecordIDs), forKey: key)
    }
    func syncFavorites(useLocalDesiredState: Bool = false) {
        guard let authManager, authManager.isLoggedIn, activatedAccountID == authManager.accountID else { return }
        let desired: Set<String>? = useLocalDesiredState ? favoriteGlobalRecordIDs : nil
        let accountID = authManager.accountID
        let token = authManager.token
        let expectedRevision = profileRevision
        favoriteSyncTask?.cancel()
        favoriteSyncTask = Task {
            let result = await FavoriteSyncService.shared.sync(desiredGlobalIDs: desired, userID: accountID, token: token)
            await MainActor.run {
                guard self.profileRevision == expectedRevision,
                      self.activatedAccountID == accountID,
                      self.authManager?.isLoggedIn == true,
                      self.authManager?.accountID == accountID else { return }
                if result.didSync { self.favoriteGlobalRecordIDs = result.serverGlobalIDs; self.saveFavoriteIDs() }
            }
        }
    }
    func resolveGuestFavoriteMerge(shouldMerge: Bool) {
        let guest = Set(UserDefaults.standard.stringArray(forKey: "pending_guest_global_favorites") ?? [])
        if let accountID = authManager?.accountID {
            let key = "handled_guest_favorite_ids_\(accountID)"
            var handled = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
            handled.formUnion(guest)
            UserDefaults.standard.set(Array(handled), forKey: key)
        }
        pendingGuestFavoriteMergeCount = 0
        UserDefaults.standard.removeObject(forKey: "pending_guest_global_favorites")
        guard shouldMerge else { return }
        favoriteGlobalRecordIDs.formUnion(guest); saveFavoriteIDs(); syncFavorites(useLocalDesiredState: true)
    }

    private func dirtyKey(_ id: String) -> String { "user_foods_dirty_\(id)" }
    private func portionsDirtyKey(_ id: String) -> String { "user_food_portions_dirty_\(id)" }
    private func deletedKey(_ id: String) -> String { "user_foods_deleted_\(id)" }
    private func lastSuccessfulSyncKey(_ id: String) -> String { "user_foods_last_successful_sync_\(id)_v1" }
    private func markDirty(_ id: UUID) {
        guard let accountID = authManager?.accountID, authManager?.isLoggedIn == true else { return }
        var dirty = storedIDs(dirtyKey(accountID)); dirty.insert(id); storeIDs(dirty, key: dirtyKey(accountID))
        var deleted = storedIDs(deletedKey(accountID)); deleted.remove(id); storeIDs(deleted, key: deletedKey(accountID))
    }
    private func markPortionsDirty(_ id: UUID) {
        guard let accountID = authManager?.accountID, authManager?.isLoggedIn == true else { return }
        var changed = storedIDs(portionsDirtyKey(accountID))
        changed.insert(id)
        storeIDs(changed, key: portionsDirtyKey(accountID))
    }
    private func markDeleted(_ id: UUID) {
        guard let accountID = authManager?.accountID, authManager?.isLoggedIn == true else { return }
        var dirty = storedIDs(dirtyKey(accountID)); dirty.remove(id); storeIDs(dirty, key: dirtyKey(accountID))
        var deleted = storedIDs(deletedKey(accountID)); deleted.insert(id); storeIDs(deleted, key: deletedKey(accountID))
    }
    private func storedIDs(_ key: String) -> Set<UUID> { Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))) }
    private func storeIDs(_ ids: Set<UUID>, key: String) { UserDefaults.standard.set(ids.map(\.uuidString), forKey: key) }
    private func seedDefaults() {
        foods = [
            FoodItem(name: "Apfel", kcalPer100g: 52, carbsPer100g: 14, proteinPer100g: 0.3, fatPer100g: 0.2, sugarPer100g: 10, fiberPer100g: 2.4),
            FoodItem(name: "Haferflocken", kcalPer100g: 368, carbsPer100g: 58.7, proteinPer100g: 13.5, fatPer100g: 7, fiberPer100g: 10),
            FoodItem(name: "Magerquark", kcalPer100g: 68, carbsPer100g: 4, proteinPer100g: 12, fatPer100g: 0.2)
        ]
        save()
    }

    private static let bundledDefaultFingerprints: Set<String> = Set([
        FoodItem(name: "Apfel", kcalPer100g: 52, carbsPer100g: 14, proteinPer100g: 0.3, fatPer100g: 0.2),
        FoodItem(name: "Haferflocken", kcalPer100g: 368, carbsPer100g: 58.7, proteinPer100g: 13.5, fatPer100g: 7),
        FoodItem(name: "Magerquark", kcalPer100g: 68, carbsPer100g: 4, proteinPer100g: 12, fatPer100g: 0.2)
    ].map(FoodSyncService.fingerprint))
}
