import Foundation
import Combine
import OSLog

nonisolated enum RecipeFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case fish, meat, vegan, vegetarian, pescetarian, carnivore, glutenFree, lactoseFree, lowSugar, highProtein, lowCalorie
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { LanguageStore.localizedString("recipe.filter.\(rawValue)") }
    static var dietary: [RecipeFilter] { [.fish, .meat, .vegan, .vegetarian, .pescetarian, .carnivore, .glutenFree, .lactoseFree, .lowSugar, .highProtein, .lowCalorie] }
    static var meals: [RecipeFilter] { [.breakfast, .lunch, .dinner, .snack] }
}

nonisolated enum RecipeSyncStatus: String, Codable, Sendable {
    case local
    case pendingSync = "pending_sync"
    case synced
    case failed
    case conflict
}

nonisolated enum RecipeModerationStatus: String, Codable, Sendable {
    case pending, approved, rejected
}

nonisolated enum RecipeOrigin: String, Codable, Sendable {
    case personal, global
}

/// The embedded food is an immutable nutrition snapshot. Catalogue references
/// remain available through the embedded FoodItem's stable IDs.
nonisolated struct RecipeIngredient: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var food: FoodItem
    var grams: Double
    var unit: FoodUnit

    init(id: UUID = UUID(), food: FoodItem, grams: Double, unit: FoodUnit? = nil) {
        self.id = id; self.food = food; self.grams = grams; self.unit = unit ?? food.unit
    }

    var globalFoodRecordID: String? { food.globalRecordID }
    var personalFoodClientID: UUID? { food.globalRecordID == nil ? food.id : nil }

    enum CodingKeys: String, CodingKey { case id, food, grams, unit }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        food = try c.decode(FoodItem.self, forKey: .food)
        grams = try c.decodeIfPresent(Double.self, forKey: .grams) ?? 100
        unit = try c.decodeIfPresent(FoodUnit.self, forKey: .unit) ?? food.unit
    }
}

nonisolated struct Recipe: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var remoteID: String?
    var name: String
    var recipeDescription: String = ""
    var ingredients: [RecipeIngredient] = []
    var servings: Double = 1
    var totalWeightGrams: Double?
    var preparationSteps: [String] = []
    var preparationMinutes: Int?
    var tags: [String] = []
    var isFavorite: Bool = false
    var filters: Set<RecipeFilter> = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var syncStatus: RecipeSyncStatus = .local
    var origin: RecipeOrigin = .personal
    var globalRecordID: String?
    var globalSubmissionID: String?
    var moderationStatus: RecipeModerationStatus?
    var rejectionReason: String?
    var imageFileName: String?
    var remoteImageFileName: String?
    var shareRecordID: String?

    var hasReliableTotalWeight: Bool {
        if let totalWeightGrams { return totalWeightGrams > 0 }
        return !ingredients.isEmpty && ingredients.allSatisfy {
            $0.grams > 0 && $0.unit.converted($0.grams, to: .gram) != nil
        }
    }

    /// A fallback reference amount keeps legacy and volume-only recipes usable,
    /// but the UI only calls it weight when `hasReliableTotalWeight` is true.
    var totalGrams: Double {
        if let totalWeightGrams, totalWeightGrams > 0 { return totalWeightGrams }
        let amount = ingredients.reduce(0) { result, ingredient in
            result + (ingredient.unit.converted(max(ingredient.grams, 0), to: .gram) ?? max(ingredient.grams, 0))
        }
        return amount > 0 ? amount : max(servings, 1) * 100
    }

    /// Precise internal calculation; views decide how to round values.
    var totalNutrients: CalculatedNutrients {
        ingredients.reduce(CalculatedNutrients.zero) { result, ingredient in
            let factor = max(ingredient.grams, 0) / 100
            let food = ingredient.food
            return CalculatedNutrients(
                kcal: result.kcal + food.kcalPer100g * factor,
                carbs: result.carbs + food.carbsPer100g * factor,
                protein: result.protein + food.proteinPer100g * factor,
                fat: result.fat + food.fatPer100g * factor,
                sugar: result.sugar + food.sugarPer100g * factor,
                fiber: result.fiber + food.fiberPer100g * factor,
                saturatedFat: result.saturatedFat + food.saturatedFatPer100g * factor,
                salt: result.salt + food.saltPer100g * factor
            )
        }
    }

    var nutrientsPer100g: CalculatedNutrients { totalGrams > 0 ? totalNutrients.scaled(by: 100 / totalGrams) : .zero }
    var nutrientsPerServing: CalculatedNutrients { totalNutrients.scaled(by: 1 / max(servings, 1)) }
    var gramsPerServing: Double { totalGrams / max(servings, 1) }
    var caloriesPerServing: Double { nutrientsPerServing.kcal }
    var displayDescription: String { recipeDescription.trimmingCharacters(in: .whitespacesAndNewlines) }

    enum CodingKeys: String, CodingKey {
        case id, remoteID, name, recipeDescription, ingredients, servings, totalWeightGrams
        case preparationSteps, preparationMinutes, tags, isFavorite, filters, createdAt, updatedAt
        case syncStatus, origin, globalRecordID, globalSubmissionID, moderationStatus
        case rejectionReason, imageFileName, remoteImageFileName, shareRecordID
    }

    init(
        id: UUID = UUID(), remoteID: String? = nil, name: String,
        recipeDescription: String = "", ingredients: [RecipeIngredient] = [],
        servings: Double = 1, totalWeightGrams: Double? = nil,
        preparationSteps: [String] = [], preparationMinutes: Int? = nil,
        tags: [String] = [], isFavorite: Bool = false,
        filters: Set<RecipeFilter> = [], createdAt: Date = Date(),
        updatedAt: Date = Date(), syncStatus: RecipeSyncStatus = .local,
        origin: RecipeOrigin = .personal, globalRecordID: String? = nil,
        globalSubmissionID: String? = nil,
        moderationStatus: RecipeModerationStatus? = nil,
        rejectionReason: String? = nil, imageFileName: String? = nil,
        remoteImageFileName: String? = nil,
        shareRecordID: String? = nil
    ) {
        self.id = id; self.remoteID = remoteID; self.name = name
        self.recipeDescription = recipeDescription; self.ingredients = ingredients
        self.servings = max(servings, 0.0001); self.totalWeightGrams = totalWeightGrams
        self.preparationSteps = preparationSteps; self.preparationMinutes = preparationMinutes
        self.tags = tags; self.isFavorite = isFavorite; self.filters = filters
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.syncStatus = syncStatus
        self.origin = origin; self.globalRecordID = globalRecordID
        self.globalSubmissionID = globalSubmissionID; self.moderationStatus = moderationStatus
        self.rejectionReason = rejectionReason; self.imageFileName = imageFileName
        self.remoteImageFileName = remoteImageFileName
        self.shareRecordID = shareRecordID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        remoteID = try c.decodeIfPresent(String.self, forKey: .remoteID)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        recipeDescription = try c.decodeIfPresent(String.self, forKey: .recipeDescription) ?? ""
        ingredients = try c.decodeIfPresent([RecipeIngredient].self, forKey: .ingredients) ?? []
        servings = max(try c.decodeIfPresent(Double.self, forKey: .servings) ?? 1, 0.0001)
        totalWeightGrams = try c.decodeIfPresent(Double.self, forKey: .totalWeightGrams)
        preparationSteps = try c.decodeIfPresent([String].self, forKey: .preparationSteps) ?? []
        preparationMinutes = try c.decodeIfPresent(Int.self, forKey: .preparationMinutes)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        filters = try c.decodeIfPresent(Set<RecipeFilter>.self, forKey: .filters) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        syncStatus = try c.decodeIfPresent(RecipeSyncStatus.self, forKey: .syncStatus) ?? .local
        origin = try c.decodeIfPresent(RecipeOrigin.self, forKey: .origin) ?? .personal
        globalRecordID = try c.decodeIfPresent(String.self, forKey: .globalRecordID)
        globalSubmissionID = try c.decodeIfPresent(String.self, forKey: .globalSubmissionID)
        moderationStatus = try c.decodeIfPresent(RecipeModerationStatus.self, forKey: .moderationStatus)
        rejectionReason = try c.decodeIfPresent(String.self, forKey: .rejectionReason)
        imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        remoteImageFileName = try c.decodeIfPresent(String.self, forKey: .remoteImageFileName)
        shareRecordID = try c.decodeIfPresent(String.self, forKey: .shareRecordID)
    }

    func personalCopy() -> Recipe {
        Recipe(name: name, recipeDescription: recipeDescription, ingredients: ingredients,
               servings: servings, totalWeightGrams: totalWeightGrams,
               preparationSteps: preparationSteps, preparationMinutes: preparationMinutes,
               tags: tags, filters: filters, globalRecordID: globalRecordID ?? remoteID)
    }
}

enum RecipeStoreSyncState: Equatable { case idle, syncing, synced(Date), offline, failed }

@MainActor
final class RecipeStore: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var globalRecipes: [Recipe] = []
    @Published private(set) var syncState: RecipeStoreSyncState = .idle
    @Published private(set) var pendingGuestRecipeMergeCount = 0
    @Published private(set) var isMergingGuestRecipes = false
    @Published private(set) var lastError: String?

    weak var authManager: AuthManager?
    private var activatedAccountID: String?
    private var profileRevision: UInt = 0
    private var syncRevision: UInt = 0
    private var syncTask: Task<Void, Never>?
    private var deferredSyncTask: Task<Void, Never>?
    private var shareRevocationTask: Task<Void, Never>?
    private var lastSuccessfulSyncAt: Date?
    private let legacyStorageKey = "saved_recipes_v1"
    private let storagePrefix = "saved_recipes_v2"
    private let globalCatalogueRefreshKey = "global_recipes_last_refresh_v1"
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "RecipeScope")

    private var scope: String { activatedAccountID.map { "account_\($0)" } ?? "guest" }
    private var storageKey: String { "\(storagePrefix)_\(scope)" }
    private func dirtyKey(_ accountID: String) -> String { "user_recipes_dirty_\(accountID)_v1" }
    private func deletedKey(_ accountID: String) -> String { "user_recipes_deleted_\(accountID)_v1" }
    private func pendingGuestKey(_ accountID: String) -> String { "user_recipes_pending_guest_\(accountID)_v1" }
    private func handledGuestKey(_ accountID: String) -> String { "user_recipes_handled_guest_\(accountID)_v1" }
    private func lastSuccessfulSyncKey(_ accountID: String) -> String { "user_recipes_last_successful_sync_\(accountID)_v1" }
    private func shareRevocationsKey(_ accountID: String) -> String { "recipe_share_revocations_\(accountID)_v1" }
    private var globalFavoritesKey: String { activatedAccountID.map { "global_recipe_favorites_\($0)_v1" } ?? "global_recipe_favorites_guest_v1" }

    init() { migrateLegacyRecipesIfNeeded(); load(); loadCachedGlobals() }
    func attach(_ authManager: AuthManager) { self.authManager = authManager }

    func add(_ recipe: Recipe) {
        var value = recipe; let now = Date()
        value.createdAt = now; value.updatedAt = now; value.origin = .personal
        value.syncStatus = activatedAccountID == nil ? .local : .pendingSync
        recipes.append(value)
        if activatedAccountID != nil { markDirty(value.id) }
        save(); schedulePendingRecipeSync()
    }

    func update(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        var value = recipe
        value.remoteID = recipes[index].remoteID; value.createdAt = recipes[index].createdAt
        value.remoteImageFileName = value.imageFileName == nil ? nil : (value.remoteImageFileName ?? recipes[index].remoteImageFileName)
        value.updatedAt = Date(); value.origin = .personal
        value.syncStatus = activatedAccountID == nil ? .local : .pendingSync
        recipes[index] = value
        if activatedAccountID != nil { markDirty(value.id) }
        save(); schedulePendingRecipeSync()
    }

    func delete(id: UUID) {
        guard let recipe = recipes.first(where: { $0.id == id }) else { return }
        if let shareID = recipe.shareRecordID, let accountID = activatedAccountID {
            var pending = Set(UserDefaults.standard.stringArray(forKey: shareRevocationsKey(accountID)) ?? [])
            pending.insert(shareID)
            UserDefaults.standard.set(Array(pending), forKey: shareRevocationsKey(accountID))
        }
        recipes.removeAll { $0.id == id }
        if activatedAccountID != nil { markDeleted(id) }
        save(); schedulePendingRecipeSync(); retryShareRevocations()
    }

    func search(_ query: String) -> [Recipe] { sorted(filtered(recipes, query: query)) }
    func searchAll(_ query: String) -> [Recipe] {
        let personalFingerprints = Set(recipes.map(RecipeSyncService.fingerprint))
        let globals = globalRecipes.filter { !personalFingerprints.contains(RecipeSyncService.fingerprint($0)) }
        return sorted(filtered(recipes + globals, query: query))
    }
    func isGlobalFavorite(_ recipe: Recipe) -> Bool {
        guard let id = recipe.globalRecordID ?? recipe.remoteID else { return false }
        return globalFavoriteIDs.contains(id)
    }
    func toggleGlobalFavorite(_ recipe: Recipe) {
        guard let id = recipe.globalRecordID ?? recipe.remoteID else { return }
        var values = globalFavoriteIDs
        if values.contains(id) { values.remove(id) } else { values.insert(id) }
        UserDefaults.standard.set(Array(values), forKey: globalFavoritesKey); refreshGlobalFavoriteFlags()
    }
    func saveGlobalRecipe(_ recipe: Recipe) { add(recipe.personalCopy()) }

    func submitGlobally(id: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == id }),
              let authManager, authManager.isLoggedIn, !authManager.token.isEmpty else { return }
        var recipe = recipes[index]; recipe.moderationStatus = .pending
        recipe.rejectionReason = nil; recipe.updatedAt = Date(); recipes[index] = recipe; save()
        let accountID = authManager.accountID, token = authManager.token, revision = profileRevision
        Task {
            let result = await RecipeSyncService.shared.submitGlobal(recipe: recipe, userID: accountID, token: token)
            guard self.profileRevision == revision, self.activatedAccountID == accountID,
                  let currentIndex = self.recipes.firstIndex(where: { $0.id == id }) else { return }
            guard let result else {
                self.recipes[currentIndex].moderationStatus = nil
                self.lastError = LanguageStore.localizedString("recipes.global_submit_failed")
                self.save(); return
            }
            self.recipes[currentIndex].globalRecordID = result.globalRecipeID
            self.recipes[currentIndex].globalSubmissionID = result.submissionID
            self.recipes[currentIndex].moderationStatus = result.status
            self.recipes[currentIndex].rejectionReason = result.rejectionReason
            self.recipes[currentIndex].updatedAt = Date()
            self.markDirty(id); self.save(); self.schedulePendingRecipeSync()
        }
    }

    func activateAccount() {
        guard let authManager, authManager.isLoggedIn, !authManager.accountID.isEmpty,
              activatedAccountID != authManager.accountID else { return }
        profileRevision &+= 1; syncRevision &+= 1; syncTask?.cancel()
        let accountID = authManager.accountID; activatedAccountID = accountID
        recipes = []; load(); loadCachedGlobals()
        lastSuccessfulSyncAt = UserDefaults.standard.object(forKey: lastSuccessfulSyncKey(accountID)) as? Date
        if let lastSuccessfulSyncAt { syncState = .synced(lastSuccessfulSyncAt) }
        let guest = loadRecipes(key: "\(storagePrefix)_guest")
        let handled = Set(UserDefaults.standard.stringArray(forKey: handledGuestKey(accountID)) ?? [])
        let pending = guest.filter { !handled.contains($0.id.uuidString.lowercased()) }
        pendingGuestRecipeMergeCount = pending.count
        if let data = try? JSONEncoder().encode(pending), !pending.isEmpty { UserDefaults.standard.set(data, forKey: pendingGuestKey(accountID)) }
        else { UserDefaults.standard.removeObject(forKey: pendingGuestKey(accountID)) }
        syncPendingRecipes()
    }

    func deactivateAccount() {
        profileRevision &+= 1; syncRevision &+= 1; syncTask?.cancel(); deferredSyncTask?.cancel(); syncTask = nil; deferredSyncTask = nil
        shareRevocationTask?.cancel(); shareRevocationTask = nil
        activatedAccountID = nil; pendingGuestRecipeMergeCount = 0; isMergingGuestRecipes = false
        lastSuccessfulSyncAt = nil
        syncState = .idle; lastError = nil; recipes = []; globalRecipes = []; load(); loadCachedGlobals()
    }

    func resolveGuestMerge(shouldMerge: Bool) {
        guard let accountID = activatedAccountID,
              let data = UserDefaults.standard.data(forKey: pendingGuestKey(accountID)),
              let pending = try? JSONDecoder().decode([Recipe].self, from: data) else { pendingGuestRecipeMergeCount = 0; return }
        guard shouldMerge else {
            markGuestHandled(pending, accountID: accountID); UserDefaults.standard.removeObject(forKey: pendingGuestKey(accountID))
            pendingGuestRecipeMergeCount = 0; return
        }
        isMergingGuestRecipes = true
        let knownIDs = Set(recipes.map(\.id))
        for var value in pending where !knownIDs.contains(value.id) {
            value.origin = .personal; value.syncStatus = .pendingSync; value.updatedAt = max(value.updatedAt, Date())
            recipes.append(value); markDirty(value.id)
        }
        save(); schedulePendingRecipeSync()
    }

    func syncPendingRecipes() {
        guard let authManager, authManager.isLoggedIn,
              let accountID = activatedAccountID, accountID == authManager.accountID,
              !authManager.token.isEmpty else { return }
        retryShareRevocations()
        deferredSyncTask?.cancel(); deferredSyncTask = nil
        let dirty = storedIDs(dirtyKey(accountID)), deleted = storedIDs(deletedKey(accountID))
        if dirty.isEmpty, deleted.isEmpty,
           case .synced = syncState,
           let lastSuccessfulSyncAt, Date().timeIntervalSince(lastSuccessfulSyncAt) < 3_600 { return }
        syncState = .syncing; lastError = nil; syncRevision &+= 1
        let expectedSync = syncRevision, expectedProfile = profileRevision
        let token = authManager.token, local = recipes
        let lastGlobalRefresh = UserDefaults.standard.object(forKey: globalCatalogueRefreshKey) as? Date
        let refreshGlobalRecipes = globalRecipes.isEmpty
            || lastGlobalRefresh.map { Date().timeIntervalSince($0) >= 86_400 } != false
        syncTask?.cancel()
        syncTask = Task {
            let result = await RecipeSyncService.shared.sync(recipes: local, dirtyIDs: dirty, deletedIDs: deleted, userID: accountID, token: token, refreshGlobalRecipes: refreshGlobalRecipes)
            guard !Task.isCancelled, self.profileRevision == expectedProfile,
                  self.syncRevision == expectedSync, self.activatedAccountID == accountID,
                  self.authManager?.accountID == accountID else { return }
            guard result.didFetch else {
                self.syncState = .offline
                self.recipes = self.recipes.map { value in var copy = value; if dirty.contains(value.id) { copy.syncStatus = .failed }; return copy }
                self.save(); return
            }
            let remainingDirty = dirty.subtracting(result.confirmedIDs)
            let remainingDeleted = deleted.subtracting(result.deletedIDs)
            self.storeIDs(remainingDirty, key: self.dirtyKey(accountID)); self.storeIDs(remainingDeleted, key: self.deletedKey(accountID))
            let currentByID = Dictionary(uniqueKeysWithValues: self.recipes.map { ($0.id, $0) })
            var merged = Dictionary(uniqueKeysWithValues: result.remoteRecipes.map { ($0.id, $0) })
            for id in remainingDirty where !remainingDeleted.contains(id) { if let value = currentByID[id] { merged[id] = value } }
            result.conflictCopies.forEach { merged[$0.id] = $0 }; remainingDeleted.forEach { merged.removeValue(forKey: $0) }
            self.recipes = Array(merged.values).map { value in
                var copy = value
                if remainingDirty.contains(copy.id) { copy.syncStatus = .failed }
                else if copy.syncStatus != .conflict { copy.syncStatus = .synced }
                return copy
            }
            if let globalRecipes = result.globalRecipes {
                self.globalRecipes = globalRecipes
                self.refreshGlobalFavoriteFlags()
                self.saveCachedGlobals()
                UserDefaults.standard.set(Date(), forKey: self.globalCatalogueRefreshKey)
            }
            self.save()
            self.finishGuestMerge(accountID: accountID, confirmedIDs: result.confirmedIDs, remainingDirty: remainingDirty)
            let now = Date()
            self.syncState = remainingDirty.isEmpty && remainingDeleted.isEmpty ? .synced(now) : .failed
            self.lastSuccessfulSyncAt = now
            UserDefaults.standard.set(now, forKey: self.lastSuccessfulSyncKey(accountID))
            self.lastError = remainingDirty.isEmpty ? nil : LanguageStore.localizedString("recipes.sync_failed")
        }
    }

    private func schedulePendingRecipeSync() {
        guard activatedAccountID != nil else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.deferredSyncTask = nil
            self.syncPendingRecipes()
        }
    }

    private func retryShareRevocations() {
        guard shareRevocationTask == nil, let accountID = activatedAccountID,
              let authManager, authManager.accountID == accountID, !authManager.token.isEmpty else { return }
        let key = shareRevocationsKey(accountID)
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !ids.isEmpty else { return }
        let token = authManager.token
        shareRevocationTask = Task {
            for id in ids where !Task.isCancelled {
                guard (try? await RecipeShareService.shared.revoke(id: id, token: token)) != nil,
                      activatedAccountID == accountID else { continue }
                var pending = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
                pending.remove(id)
                UserDefaults.standard.set(Array(pending), forKey: key)
            }
            shareRevocationTask = nil
        }
    }

    private var globalFavoriteIDs: Set<String> { Set(UserDefaults.standard.stringArray(forKey: globalFavoritesKey) ?? []) }
    private func refreshGlobalFavoriteFlags() {
        let favorites = globalFavoriteIDs
        globalRecipes = globalRecipes.map { value in var copy = value; if let id = copy.globalRecordID ?? copy.remoteID { copy.isFavorite = favorites.contains(id) }; return copy }
    }
    private func filtered(_ values: [Recipe], query: String) -> [Recipe] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return values.filter {
            q.isEmpty || $0.name.localizedCaseInsensitiveContains(q)
                || $0.recipeDescription.localizedCaseInsensitiveContains(q)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
    private func sorted(_ values: [Recipe]) -> [Recipe] { values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    private func save() { if let data = try? JSONEncoder().encode(recipes) { UserDefaults.standard.set(data, forKey: storageKey) } }
    private func load() { recipes = loadRecipes(key: storageKey) }
    private func loadRecipes(key: String) -> [Recipe] {
        guard let data = UserDefaults.standard.data(forKey: key), let values = try? JSONDecoder().decode([Recipe].self, from: data) else { return [] }
        return values
    }
    private func saveCachedGlobals() { if let data = try? JSONEncoder().encode(globalRecipes) { UserDefaults.standard.set(data, forKey: "global_recipes_cache_v1") } }
    private func loadCachedGlobals() { globalRecipes = loadRecipes(key: "global_recipes_cache_v1"); refreshGlobalFavoriteFlags() }
    private func migrateLegacyRecipesIfNeeded() {
        let marker = "saved_recipes_v2_migrated"; guard !UserDefaults.standard.bool(forKey: marker) else { return }
        if let data = UserDefaults.standard.data(forKey: legacyStorageKey), var values = try? JSONDecoder().decode([Recipe].self, from: data) {
            values = values.map { value in var copy = value; copy.syncStatus = .local; copy.origin = .personal; return copy }
            if let encoded = try? JSONEncoder().encode(values) { UserDefaults.standard.set(encoded, forKey: "\(storagePrefix)_guest") }
        }
        UserDefaults.standard.set(true, forKey: marker)
    }
    private func storedIDs(_ key: String) -> Set<UUID> { Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))) }
    private func storeIDs(_ ids: Set<UUID>, key: String) { UserDefaults.standard.set(ids.map { $0.uuidString.lowercased() }, forKey: key) }
    private func markDirty(_ id: UUID) {
        guard let accountID = activatedAccountID else { return }
        var dirty = storedIDs(dirtyKey(accountID)); dirty.insert(id); storeIDs(dirty, key: dirtyKey(accountID))
        var deleted = storedIDs(deletedKey(accountID)); deleted.remove(id); storeIDs(deleted, key: deletedKey(accountID))
    }
    private func markDeleted(_ id: UUID) {
        guard let accountID = activatedAccountID else { return }
        var deleted = storedIDs(deletedKey(accountID)); deleted.insert(id); storeIDs(deleted, key: deletedKey(accountID))
        var dirty = storedIDs(dirtyKey(accountID)); dirty.remove(id); storeIDs(dirty, key: dirtyKey(accountID))
    }
    private func markGuestHandled(_ values: [Recipe], accountID: String) {
        var handled = Set(UserDefaults.standard.stringArray(forKey: handledGuestKey(accountID)) ?? [])
        handled.formUnion(values.map { $0.id.uuidString.lowercased() }); UserDefaults.standard.set(Array(handled), forKey: handledGuestKey(accountID))
    }
    private func finishGuestMerge(accountID: String, confirmedIDs: Set<UUID>, remainingDirty: Set<UUID>) {
        guard let data = UserDefaults.standard.data(forKey: pendingGuestKey(accountID)), let pending = try? JSONDecoder().decode([Recipe].self, from: data) else { return }
        let confirmed = pending.filter { confirmedIDs.contains($0.id) && !remainingDirty.contains($0.id) }
        guard !confirmed.isEmpty else { isMergingGuestRecipes = false; return }
        markGuestHandled(confirmed, accountID: accountID)
        let confirmedSet = Set(confirmed.map(\.id)); let guestKey = "\(storagePrefix)_guest"
        let remainingGuest = loadRecipes(key: guestKey).filter { !confirmedSet.contains($0.id) }
        if let encoded = try? JSONEncoder().encode(remainingGuest) { UserDefaults.standard.set(encoded, forKey: guestKey) }
        let stillPending = pending.filter { !confirmedSet.contains($0.id) }
        pendingGuestRecipeMergeCount = stillPending.count; isMergingGuestRecipes = false
        if stillPending.isEmpty { UserDefaults.standard.removeObject(forKey: pendingGuestKey(accountID)) }
        else if let encoded = try? JSONEncoder().encode(stillPending) { UserDefaults.standard.set(encoded, forKey: pendingGuestKey(accountID)) }
    }
}
