import Foundation
import Combine
import WidgetKit // 1. WICHTIG: WidgetKit importieren
import OSLog

extension Notification.Name {
    static let hyseFoodEntriesAdded = Notification.Name("hyse.foodEntriesAdded")
}

enum EntrySyncState: Equatable { case idle, syncing, synced(Date), offline, failed }
enum EntryRecordSyncStatus: String, Equatable { case local, syncing, synced, pendingSync = "pending_sync", failed }

private enum EntryDataScope: Equatable {
    case guest
    case account(String)

    var accountID: String? {
        guard case .account(let id) = self else { return nil }
        return id
    }
    var diagnosticName: String { accountID.map { "user:\($0)" } ?? "guest" }
}

@MainActor
final class CalorieStore: ObservableObject {
    @Published private(set) var entries: [CalorieEntry] = [] {
        didSet {
            let calendar = Calendar.autoupdatingCurrent
            let hasToday = entries.contains(where: { calendar.isDateInToday($0.date) })
            if hasToday {
                MotivationNotificationManager.shared.cancelFoodLogReminder()
            } else if oldValue.contains(where: { calendar.isDateInToday($0.date) }) {
                MotivationNotificationManager.shared.restoreTodayFoodLogReminderIfNeeded(language: .persisted)
            }
        }
    }
    @Published private(set) var streakActivityDayKeys: Set<String> = []
    @Published private(set) var streakFrozenDayKeys: Set<String> = []
    weak var healthKitManager: HealthKitManager?
    weak var authManager: AuthManager?
    weak var categoryStore: CategoryStore?
    weak var userSettings: UserSettingsStore?
    weak var fastingStore: FastingStore?
    weak var trainingStore: TrainingStore?
    @Published private(set) var lastFoodTrackingRestriction: FoodTrackingRestriction?
    @Published private(set) var lastLocalSaveFailed = false
    @Published private(set) var localDiaryUnreadable = false

    private let storageKey = "calorie_entries"
    private var activeScope: EntryDataScope = .guest
    private var syncAccountID: String? { activeScope.accountID }
    private func dirtyKey(_ accountID: String) -> String { "calorie_entries_dirty_\(accountID)" }
    private func deletedKey(_ accountID: String) -> String { "calorie_entries_deleted_\(accountID)" }
    private func lastSuccessfulSyncKey(_ accountID: String) -> String { "calorie_entries_last_successful_sync_\(accountID)_v1" }
    private func lastFullRefreshKey(_ accountID: String) -> String { "calorie_entries_last_full_refresh_\(accountID)_v1" }
    @Published private(set) var pendingGuestMergeCount = 0
    @Published private(set) var isMergingGuestEntries = false
    @Published private(set) var syncState: EntrySyncState = .idle
    private var activatedAccountID: String?
    private var scopeRevision: UInt = 0
    private var syncRevision: UInt = 0
    private var syncTask: Task<Void, Never>?
    private var syncIsRunning = false
    private var syncRequestedWhileRunning = false
    private var deferredSyncTask: Task<Void, Never>?
    private var widgetRefreshTask: Task<Void, Never>?
    private var lastSuccessfulSyncAt: Date?
    private var unreadableScope: EntryDataScope?
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "EntryScope")

    private func handledGuestIDsKey(_ accountID: String) -> String { "calorie_entries_handled_guest_ids_\(accountID)" }
    private func pendingGuestKey(_ accountID: String) -> String { "calorie_entries_pending_guest_merge_\(accountID)" }
    private func storageKey(for scope: EntryDataScope) -> String {
        switch scope {
        case .guest: return "\(storageKey)_guest"
        case .account(let id): return "\(storageKey)_account_\(id)"
        }
    }
    private func streakStorageKey(for scope: EntryDataScope) -> String {
        switch scope {
        case .guest: return "streak_activity_days_guest_v1"
        case .account(let id): return "streak_activity_days_account_\(id)_v1"
        }
    }

    init() {
        load()
        loadStreakActivity(scope: .guest)
    }

    @discardableResult
    func addEntry(_ entry: CalorieEntry) -> Bool {
        addEntries([entry])
    }

    /// Adds a logical batch with one persistence pass and one sync attempt. Every
    /// entry keeps its client UUID, so retries are idempotent in PocketBase.
    @discardableResult
    func addEntries(
        _ newEntries: [CalorieEntry],
        countsTowardStreak: Bool = true,
        enforceTrackingRules: Bool = true
    ) -> Bool {
        guard unreadableScope != activeScope else { lastLocalSaveFailed = true; return false }
        guard !newEntries.isEmpty else { return false }
        let existingIDs = Set(entries.map(\.id))
        let candidates = newEntries.filter { !existingIDs.contains($0.id) }
        guard !candidates.isEmpty else { return false }
        if enforceTrackingRules {
            let calendar = Calendar.current
            for date in Set(candidates.map { calendar.startOfDay(for: $0.date) }) {
                if let restriction = trackingRestriction(for: date) {
                    lastFoodTrackingRestriction = restriction
                    return false
                }
                if let settings = userSettings, settings.enforceCalorieLimit {
                    let incomingCalories = candidates
                        .filter { calendar.isDate($0.date, inSameDayAs: date) }
                        .reduce(0) { $0 + $1.kcal }
                    if totalKcal(for: date) + incomingCalories > maximumAllowedCalories(for: date, settings: settings) {
                        lastFoodTrackingRestriction = .calorieLimitExceeded
                        return false
                    }
                }
            }
        }
        let normalized = candidates.map(normalizedCategory)
        lastFoodTrackingRestriction = nil
        lastLocalSaveFailed = false
        // The retry intent must reach disk before the changed snapshot. If
        // iOS stops the process between the two writes, an old server value
        // must never be mistaken for a newer local edit.
        normalized.forEach { markDirty($0.id) }
        _ = UserDefaults.standard.synchronize()
        guard persistEntries(entries + normalized, scope: activeScope) else {
            lastLocalSaveFailed = true
            return false
        }
        entries.append(contentsOf: normalized)
        if countsTowardStreak { normalized.forEach { recordStreakActivityIfToday($0.date) } }
        // The entry snapshot is already on disk before the add action ends.
        normalized.forEach { healthKitManager?.saveDietaryEntry($0) }
        updateWidget()
#if DEBUG
        logger.debug("Local batch create scope=\(self.activeScope.diagnosticName, privacy: .public) added=\(normalized.count) visible=\(self.entries.count)")
#endif
        schedulePendingSync()
        NotificationCenter.default.post(name: .hyseFoodEntriesAdded, object: normalized)
        return true
    }

    func trackingRestriction(for entryDate: Date, at now: Date = Date()) -> FoodTrackingRestriction? {
        guard let userSettings else { return nil }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: entryDate)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let previousEnergy = healthKitManager?.energy(for: previousDay)
        let dayEnergy = healthKitManager?.energy(for: day)
        let baseTarget = userSettings.calorieTarget(for: day, previousDayEnergy: previousEnergy).targetKilocalories
        let availableCalories = userSettings.availableCalories(
            for: day,
            targetKilocalories: baseTarget,
            activeEnergy: dayEnergy?.active ?? 0,
            isTrainingDay: isTrainingDay(day)
        )
        let remainingCalories = availableCalories - totalKcal(for: day)
        return userSettings.foodTrackingRestriction(
            at: now,
            remainingCalories: remainingCalories,
            isFasting: fastingStore?.isFasting ?? false
        )
    }

    func calorieAllowance(for date: Date) -> Double? {
        guard let userSettings else { return nil }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let previousEnergy = healthKitManager?.energy(for: previousDay)
        let activeEnergy = healthKitManager?.energy(for: day)?.active ?? 0
        let target = userSettings.calorieTarget(for: day, previousDayEnergy: previousEnergy).targetKilocalories
        return userSettings.availableCalories(
            for: day,
            targetKilocalories: target,
            activeEnergy: activeEnergy,
            isTrainingDay: isTrainingDay(day)
        )
    }

    private func maximumAllowedCalories(for entryDate: Date, settings: UserSettingsStore) -> Double {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: entryDate)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let previousEnergy = healthKitManager?.energy(for: previousDay)
        let activeEnergy = healthKitManager?.energy(for: day)?.active ?? 0
        let target = settings.calorieTarget(for: day, previousDayEnergy: previousEnergy).targetKilocalories
        let availableCalories = settings.availableCalories(
            for: day,
            targetKilocalories: target,
            activeEnergy: activeEnergy,
            isTrainingDay: isTrainingDay(day)
        )
        return settings.maximumAllowedCalories(availableCalories)
    }

    /// A planned routine changes the allowance just like a completed workout.
    /// This is deliberately shared by the entry restriction and the hard
    /// calorie limit so the two nutrition flows can never disagree about a
    /// scheduled training day.
    private func isTrainingDay(_ date: Date) -> Bool {
        guard let trainingStore else { return false }
        let hasWorkout = !trainingStore.workouts(on: date).isEmpty
        let hasPlannedRoutine = !trainingStore.routines(plannedFor: date).isEmpty
        return hasWorkout || (userSettings?.trainingDayStatus(for: date, currentlyTraining: hasPlannedRoutine) ?? hasPlannedRoutine)
    }

    func syncStatus(for entryID: UUID) -> EntryRecordSyncStatus {
        guard let accountID = syncAccountID else { return .local }
        guard storedIDs(forKey: dirtyKey(accountID)).contains(entryID) else { return .synced }
        switch syncState {
        case .syncing: return .syncing
        case .failed: return .failed
        case .offline, .idle, .synced: return .pendingSync
        }
    }

    @discardableResult
    func updateEntry(_ entry: CalorieEntry) -> Bool {
        guard unreadableScope != activeScope else { lastLocalSaveFailed = true; return false }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return false }
        let normalized = normalizedCategory(in: entry)
        guard entries[index] != normalized else { return true }
        var updatedEntries = entries
        updatedEntries[index] = normalized
        lastLocalSaveFailed = false
        markDirty(entry.id)
        _ = UserDefaults.standard.synchronize()
        guard persistEntries(updatedEntries, scope: activeScope) else {
            lastLocalSaveFailed = true
            return false
        }
        entries = updatedEntries
        healthKitManager?.updateDietaryEntry(normalized)
        updateWidget()
#if DEBUG
        logger.debug("Local update scope=\(self.activeScope.diagnosticName, privacy: .public) visible=\(self.entries.count)")
#endif
        schedulePendingSync()
        return true
    }

    @discardableResult
    func updateEntries(_ changedEntries: [CalorieEntry]) -> Bool {
        guard unreadableScope != activeScope else { lastLocalSaveFailed = true; return false }
        guard !changedEntries.isEmpty else { return true }
        var updatedEntries = entries
        var updated: [CalorieEntry] = []
        for entry in changedEntries {
            guard let index = updatedEntries.firstIndex(where: { $0.id == entry.id }) else { continue }
            let normalized = normalizedCategory(in: entry)
            guard updatedEntries[index] != normalized else { continue }
            updatedEntries[index] = normalized
            updated.append(normalized)
        }
        guard !updated.isEmpty else { return true }
        lastLocalSaveFailed = false
        updated.forEach { markDirty($0.id) }
        _ = UserDefaults.standard.synchronize()
        guard persistEntries(updatedEntries, scope: activeScope) else {
            lastLocalSaveFailed = true
            return false
        }
        entries = updatedEntries
        updated.forEach { healthKitManager?.updateDietaryEntry($0) }
        updateWidget()
        schedulePendingSync()
        return true
    }

    var micronutrientScopeID: String { activeScope.accountID ?? "guest" }

    /// A food's newly saved micronutrients also belong to older diary snapshots
    /// that point to that exact food. Names alone are never a safe match.
    func refreshMicronutrients(from foods: [FoodItem]) {
        let byID = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        var byGlobalID: [String: FoodItem] = [:]
        var ambiguousGlobalIDs = Set<String>()
        for food in foods where food.micronutrients?.isEmpty == false {
            guard let id = food.globalRecordID else { continue }
            if byGlobalID[id] != nil { ambiguousGlobalIDs.insert(id) }
            else { byGlobalID[id] = food }
        }
        let changes = entries.compactMap { entry -> CalorieEntry? in
            let exact = entry.foodItemId.flatMap { byID[$0] }
            let food = exact?.micronutrients?.isEmpty == false ? exact
                : entry.globalFoodRecordID.flatMap { ambiguousGlobalIDs.contains($0) ? nil : byGlobalID[$0] }
            guard let food, let profile = food.micronutrients, !profile.isEmpty else { return nil }
            let updated = profile.converted(from: food.unit, to: entry.unit)
            guard entry.micronutrients != updated else { return nil }
            var changed = entry
            changed.micronutrients = updated
            return changed
        }
        guard !changes.isEmpty else { return }
        persistMicronutrientChanges(changes)
    }

    /// Refresh historical snapshots as well as today's entry. Only entries
    /// linked to the exact barcode-bearing food are eligible.
    func applyOpenFoodFactsMicronutrients(
        _ imported: MicronutrientProfile,
        barcode: String,
        foods: [FoodItem]
    ) {
        guard !imported.isEmpty else { return }
        let matching = foods.filter { BarcodeNormalizer.normalizedIfValid($0.barcode) == barcode }
        let foodIDs = Set(matching.map(\.id))
        let globalIDs = Set(matching.compactMap(\.globalRecordID))
        guard !foodIDs.isEmpty || !globalIDs.isEmpty else { return }
        let changes = entries.compactMap { entry -> CalorieEntry? in
            guard (entry.foodItemId.map(foodIDs.contains) ?? false)
                || (entry.globalFoodRecordID.map(globalIDs.contains) ?? false) else { return nil }
            let converted = imported.converted(from: .gram, to: entry.unit)
            let updated = entry.micronutrients?.addingOpenFoodFacts(converted) ?? converted
            guard entry.micronutrients != updated else { return nil }
            var changed = entry
            changed.micronutrients = updated
            return changed
        }
        guard !changes.isEmpty else { return }
        persistMicronutrientChanges(changes)
    }

    private func persistMicronutrientChanges(_ changes: [CalorieEntry]) {
        guard unreadableScope != activeScope else { lastLocalSaveFailed = true; return }
        let byID = Dictionary(uniqueKeysWithValues: changes.map { ($0.id, $0) })
        let updatedEntries = entries.map { byID[$0.id] ?? $0 }
        lastLocalSaveFailed = false
        changes.forEach { markDirty($0.id) }
        _ = UserDefaults.standard.synchronize()
        guard persistEntries(updatedEntries, scope: activeScope) else {
            lastLocalSaveFailed = true
            return
        }
        entries = updatedEntries
        healthKitManager?.reconcileDietaryMicronutrients(entries: changes)
        schedulePendingSync()
    }

    func deleteEntry(id: UUID) {
        deleteEntries(ids: [id])
    }

    func deleteEntries(ids: Set<UUID>) {
        guard unreadableScope != activeScope else { lastLocalSaveFailed = true; return }
        guard !ids.isEmpty else { return }
        let presentIDs = ids.intersection(Set(entries.map(\.id)))
        guard !presentIDs.isEmpty else { return }
        let remaining = entries.filter { !presentIDs.contains($0.id) }
        let accountID = syncAccountID
        let previousDirty = accountID.map { storedIDs(forKey: dirtyKey($0)) }
        let previousDeleted = accountID.map { storedIDs(forKey: deletedKey($0)) }
        // Record the deletion before changing the snapshot. If the process is
        // interrupted between the writes, loading the scope still filters it.
        presentIDs.forEach(markDeleted)
        _ = UserDefaults.standard.synchronize()
        guard persistEntries(remaining, scope: activeScope) else {
            if let accountID, let previousDirty, let previousDeleted {
                storeIDs(previousDirty, forKey: dirtyKey(accountID))
                storeIDs(previousDeleted, forKey: deletedKey(accountID))
                _ = UserDefaults.standard.synchronize()
            }
            lastLocalSaveFailed = true
            return
        }
        lastLocalSaveFailed = false
        entries = remaining
        updateWidget()
        presentIDs.forEach { healthKitManager?.deleteDietaryEntry(id: $0) }
#if DEBUG
        logger.debug("Local batch delete scope=\(self.activeScope.diagnosticName, privacy: .public) removed=\(presentIDs.count) visible=\(self.entries.count)")
#endif
        schedulePendingSync()
    }

    func restoreEntries(_ removedEntries: [CalorieEntry]) {
        addEntries(removedEntries, countsTowardStreak: false, enforceTrackingRules: false)
    }

    func moveEntries(ids: Set<UUID>, to category: MealCategory, date: Date) {
        let calendar = Calendar.current
        let changed = entries.filter { ids.contains($0.id) }.map { source -> CalorieEntry in
            var value = source
            value.categoryId = category.id
            value.categoryName = category.storageKey
            let time = calendar.dateComponents([.hour, .minute, .second], from: source.date)
            value.date = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
            return value
        }
        updateEntries(changed)
    }

    @discardableResult
    func copyEntries(ids: Set<UUID>, to category: MealCategory, date: Date, countsTowardStreak: Bool = false) -> Bool {
        let calendar = Calendar.current
        let copies = entries.filter { ids.contains($0.id) }.map { source in
            let time = calendar.dateComponents([.hour, .minute, .second], from: source.date)
            return CalorieEntry(
                id: UUID(), foodItemId: source.foodItemId, recipeId: source.recipeId,
                globalFoodRecordID: source.globalFoodRecordID, userRecipeRecordID: source.userRecipeRecordID,
                globalRecipeRecordID: source.globalRecipeRecordID, name: source.name, grams: source.grams,
                categoryId: category.id, categoryName: category.storageKey,
                portionName: source.portionName, portionID: source.portionID, portionCount: source.portionCount, unit: source.unit,
                kcalPer100g: source.kcalPer100g, carbsPer100g: source.carbsPer100g,
                proteinPer100g: source.proteinPer100g, fatPer100g: source.fatPer100g,
                addedSugarPer100g: source.addedSugarPer100g, fruitSugarPer100g: source.fruitSugarPer100g,
                fiberPer100g: source.fiberPer100g, saturatedFatPer100g: source.saturatedFatPer100g,
                saltPer100g: source.saltPer100g, micronutrients: source.micronutrients,
                date: calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
            )
        }
        return addEntries(copies, countsTowardStreak: countsTowardStreak)
    }

    /// Kann beim Login und nach jedem lokalen Speichern gefahrlos aufgerufen werden.
    /// Ohne Konto geschieht absichtlich nichts; lokale Einträge bleiben erhalten.
    func syncPendingEntries() {
        guard unreadableScope != activeScope else { syncState = .failed; return }
        guard let authManager, authManager.isLoggedIn,
              let userID = syncAccountID,
              userID == authManager.accountID,
              !authManager.token.isEmpty else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = nil
        if syncIsRunning {
            // Login, foreground activation and a view can request the same
            // sync almost simultaneously. Keep the running request alive and
            // coalesce everything else into one follow-up pass.
            syncRequestedWhileRunning = true
            return
        }
        let pendingDirty = storedIDs(forKey: dirtyKey(userID))
        let pendingDeleted = storedIDs(forKey: deletedKey(userID))
        if pendingDirty.isEmpty, pendingDeleted.isEmpty,
           let lastSuccessfulSyncAt, Date().timeIntervalSince(lastSuccessfulSyncAt) < 3_600 {
            syncState = .synced(lastSuccessfulSyncAt)
            return
        }
        syncState = .syncing
        let localEntries = entries
        let token = authManager.token
        let expectedScope = activeScope
        let expectedScopeRevision = scopeRevision
        syncRevision &+= 1
        let expectedSyncRevision = syncRevision
        let dirtyIDs = pendingDirty
        let deletedIDs = pendingDeleted
        let lastFullRefresh = UserDefaults.standard.object(forKey: lastFullRefreshKey(userID)) as? Date
        // Ordinary diary edits only need one create/update request. Periodic
        // full refreshes still merge changes made on another device, and every
        // deletion performs a full refresh so its PocketBase record is known.
        let fullRefresh = !deletedIDs.isEmpty
            || lastFullRefresh.map { Date().timeIntervalSince($0) >= 3_600 } != false
        syncIsRunning = true
#if DEBUG
        logger.debug("Sync start scope=\(expectedScope.diagnosticName, privacy: .public) local=\(localEntries.count) dirty=\(dirtyIDs.count)")
#endif
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.syncRevision == expectedSyncRevision {
                    self.syncIsRunning = false
                    self.syncTask = nil
                    if self.syncRequestedWhileRunning {
                        self.syncRequestedWhileRunning = false
                        self.syncPendingEntries()
                    }
                }
            }
            let result = await CalorieEntrySyncService.shared.sync(entries: localEntries, dirtyIDs: dirtyIDs, deletedIDs: deletedIDs, userID: userID, token: token, fullRefresh: fullRefresh)
            let remote = result.remoteEntries.compactMap { CalorieEntrySyncService.shared.entry(from: $0) }
            guard result.didFetch else {
                await MainActor.run {
                    guard self.isCurrent(scope: expectedScope, scopeRevision: expectedScopeRevision, syncRevision: expectedSyncRevision) else {
#if DEBUG
                        self.logger.debug("Ignored stale failed sync scope=\(expectedScope.diagnosticName, privacy: .public)")
#endif
                        return
                    }
                    self.syncState = .offline
                    self.isMergingGuestEntries = false
                }
                return
            }
            await MainActor.run {
                guard self.isCurrent(scope: expectedScope, scopeRevision: expectedScopeRevision, syncRevision: expectedSyncRevision),
                      self.authManager?.isLoggedIn == true,
                      self.authManager?.accountID == userID else {
#if DEBUG
                    self.logger.debug("Ignored stale sync response scope=\(expectedScope.diagnosticName, privacy: .public)")
#endif
                    return
                }
                let uploadedSnapshot = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.id, $0) })
                let currentSnapshot = Dictionary(uniqueKeysWithValues: self.entries.map { ($0.id, $0) })
                let remoteIDs = Set(result.remoteEntries.compactMap { UUID(uuidString: $0.clientID) })
                let orphanedDirtyIDs = dirtyIDs.subtracting(uploadedSnapshot.keys)
                let confirmedUploads = result.uploadedIDs.filter {
                    orphanedDirtyIDs.contains($0)
                        || (currentSnapshot[$0] == uploadedSnapshot[$0] && remoteIDs.contains($0))
                }
                var remainingDirty = self.storedIDs(forKey: self.dirtyKey(userID))
                remainingDirty.subtract(confirmedUploads)
                var remainingDeleted = self.storedIDs(forKey: self.deletedKey(userID))
                remainingDeleted.subtract(result.deletedIDs)

                let currentByID = currentSnapshot
                var remoteByID: [UUID: CalorieEntry] = [:]
                for remoteEntry in remote {
                    var entry = remoteEntry
                    // Never replace a valid offline-first amount with a broken
                    // zero returned by an old/malformed PocketBase record.
                    if (!entry.grams.isFinite || entry.grams <= 0),
                       let local = currentByID[entry.id],
                       local.grams.isFinite, local.grams > 0 {
                        entry = local
                    }
                    let normalized = self.normalizedCategory(in: entry)
                    remoteByID[normalized.id] = normalized
                }
                let merge = CalorieEntrySyncMerge.reconcile(
                    local: currentByID,
                    remote: remoteByID,
                    confirmedRemoteIDs: remoteIDs,
                    pendingDirtyIDs: remainingDirty,
                    pendingDeletedIDs: remainingDeleted,
                    didFullFetch: result.didFullFetch
                )
                remainingDirty.formUnion(merge.retryIDs)
                let reconciled = Array(merge.entries.values)
                    .sorted { $0.date < $1.date }
                guard self.persistEntries(reconciled, scope: expectedScope) else {
                    self.lastLocalSaveFailed = true
                    self.syncState = .failed
                    return
                }
                self.lastLocalSaveFailed = false
                self.storeIDs(remainingDirty, forKey: self.dirtyKey(userID))
                self.storeIDs(remainingDeleted, forKey: self.deletedKey(userID))
                self.entries = reconciled
                let healthMicronutrientChanges = reconciled.filter { entry in
                    let previous = currentSnapshot[entry.id]
                    guard previous != entry else { return false }
                    return previous?.micronutrients != entry.micronutrients
                        || previous?.grams != entry.grams
                        || previous?.date != entry.date
                }.filter { $0.micronutrients?.isEmpty == false || currentSnapshot[$0.id]?.micronutrients?.isEmpty == false }
                self.healthKitManager?.reconcileDietaryMicronutrients(entries: healthMicronutrientChanges)
                self.updateWidget()
                self.migrateLegacyStreakActivityIfNeeded(scope: expectedScope)
                let now = Date()
                self.syncState = remainingDirty.isEmpty && remainingDeleted.isEmpty ? .synced(now) : .failed
                if remainingDirty.isEmpty && remainingDeleted.isEmpty {
                    self.lastSuccessfulSyncAt = now
                    UserDefaults.standard.set(now, forKey: self.lastSuccessfulSyncKey(userID))
                    if result.didFullFetch {
                        UserDefaults.standard.set(now, forKey: self.lastFullRefreshKey(userID))
                    }
                }
                self.finishGuestMergeIfConfirmed(
                    accountID: userID,
                    remoteIDs: remoteIDs,
                    remainingDirty: remainingDirty
                )
                if !dirtyIDs.isEmpty || !deletedIDs.isEmpty {
                    NotificationCenter.default.post(name: .foodUsageShouldRefresh, object: nil)
                }
#if DEBUG
                self.logger.debug("Sync end scope=\(expectedScope.diagnosticName, privacy: .public) visible=\(self.entries.count) pending=\(remainingDirty.count)")
#endif
            }
        }
    }

    private func isCurrent(scope: EntryDataScope, scopeRevision: UInt, syncRevision: UInt) -> Bool {
        activeScope == scope && self.scopeRevision == scopeRevision && self.syncRevision == syncRevision
    }

    /// Quick consecutive edits share one server round trip. Local persistence
    /// and HealthKit updates still happen immediately.
    private func schedulePendingSync() {
        guard syncAccountID != nil else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.deferredSyncTask = nil
            self.syncPendingEntries()
        }
    }

    /// Wechselt beim Login in den privaten Datenspeicher des Kontos. Gastdaten
    /// werden nicht automatisch zugeordnet, sondern erst nach expliziter Auswahl.
    func activateAccount() {
        guard let authManager, authManager.isLoggedIn, !authManager.accountID.isEmpty else { return }
        let accountID = authManager.accountID
        guard activatedAccountID != accountID || activeScope != .account(accountID) else { return }
        switchScope(to: .account(accountID))
        let guest = storedEntries(for: .guest) ?? []
        activatedAccountID = accountID
        load(scope: activeScope)
        lastSuccessfulSyncAt = UserDefaults.standard.object(forKey: lastSuccessfulSyncKey(accountID)) as? Date
        if let lastSuccessfulSyncAt { syncState = .synced(lastSuccessfulSyncAt) }
        loadStreakActivity(scope: activeScope)
        let migrationKey = "calorie_entries_sync_initialized_\(accountID)"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            storeIDs(Set(entries.map(\.id)), forKey: dirtyKey(accountID))
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        let handledIDs = Set(UserDefaults.standard.stringArray(forKey: handledGuestIDsKey(accountID)) ?? [])
        let pendingGuest = guest.filter { !handledIDs.contains($0.id.uuidString.lowercased()) }
        pendingGuestMergeCount = pendingGuest.count
        if !pendingGuest.isEmpty { UserDefaults.standard.set(try? JSONEncoder().encode(pendingGuest), forKey: pendingGuestKey(accountID)) }
        else { UserDefaults.standard.removeObject(forKey: pendingGuestKey(accountID)) }
#if DEBUG
        logger.debug("Hydrated scope=\(self.activeScope.diagnosticName, privacy: .public) cached=\(self.entries.count) guestPending=\(pendingGuest.count)")
#endif
        syncPendingEntries()
    }

    /// Removes account data from the visible in-memory store without touching the server.
    func deactivateAccount() {
        switchScope(to: .guest)
        activatedAccountID = nil
        load(scope: .guest)
        loadStreakActivity(scope: .guest)
        pendingGuestMergeCount = 0
        isMergingGuestEntries = false
        syncState = .idle
#if DEBUG
        logger.debug("Hydrated scope=guest cached=\(self.entries.count)")
#endif
    }

    func resolveGuestMerge(shouldMerge: Bool) {
        guard unreadableScope != activeScope else { lastLocalSaveFailed = true; return }
        guard let accountID = syncAccountID,
              activeScope == .account(accountID),
              let data = UserDefaults.standard.data(forKey: pendingGuestKey(accountID)),
              let guest = try? JSONDecoder().decode([CalorieEntry].self, from: data) else {
            pendingGuestMergeCount = 0
            isMergingGuestEntries = false
            return
        }
        guard shouldMerge else {
            markGuestEntriesHandled(guest, accountID: accountID)
            pendingGuestMergeCount = 0
            UserDefaults.standard.removeObject(forKey: pendingGuestKey(accountID))
            isMergingGuestEntries = false
            return
        }
        isMergingGuestEntries = true
        mergeGuestStreakActivityIntoActiveAccount(accountID: accountID)
        let known = Set(entries.map(\.id))
        entries.append(contentsOf: guest.filter { !known.contains($0.id) }.map(normalizedCategory))
        guest.forEach { markDirty($0.id) }
        save(scope: activeScope)
#if DEBUG
        logger.debug("Merge start scope=user:\(accountID, privacy: .public) entries=\(guest.count)")
#endif
        syncPendingEntries()
    }

    private func finishGuestMergeIfConfirmed(accountID: String, remoteIDs: Set<UUID>, remainingDirty: Set<UUID>) {
        guard isMergingGuestEntries,
              let data = UserDefaults.standard.data(forKey: pendingGuestKey(accountID)),
              let guest = try? JSONDecoder().decode([CalorieEntry].self, from: data) else {
            isMergingGuestEntries = false
            return
        }
        let guestIDs = Set(guest.map(\.id))
        guard guestIDs.isSubset(of: remoteIDs), guestIDs.isDisjoint(with: remainingDirty) else {
            pendingGuestMergeCount = guest.count
            isMergingGuestEntries = false
            return
        }
        guard removeConfirmedGuestCopies(ids: guestIDs) else {
            pendingGuestMergeCount = guest.count
            isMergingGuestEntries = false
            return
        }
        markGuestEntriesHandled(guest, accountID: accountID)
        UserDefaults.standard.removeObject(forKey: pendingGuestKey(accountID))
        _ = UserDefaults.standard.synchronize()
        pendingGuestMergeCount = 0
        isMergingGuestEntries = false
#if DEBUG
        logger.debug("Merge confirmed scope=user:\(accountID, privacy: .public) entries=\(guest.count)")
#endif
    }

    private func markGuestEntriesHandled(_ guest: [CalorieEntry], accountID: String) {
        var handledIDs = Set(UserDefaults.standard.stringArray(forKey: handledGuestIDsKey(accountID)) ?? [])
        handledIDs.formUnion(guest.map { $0.id.uuidString.lowercased() })
        UserDefaults.standard.set(Array(handledIDs), forKey: handledGuestIDsKey(accountID))
    }

    private func removeConfirmedGuestCopies(ids: Set<UUID>) -> Bool {
        guard let guest = storedEntries(for: .guest) else { return true }
        let remaining = guest.filter { !ids.contains($0.id) }
        return persistEntries(remaining, scope: .guest)
    }

    private func switchScope(to scope: EntryDataScope) {
        scopeRevision &+= 1
        syncRevision &+= 1
        syncTask?.cancel()
        deferredSyncTask?.cancel()
        syncTask = nil
        deferredSyncTask = nil
        syncIsRunning = false
        syncRequestedWhileRunning = false
        lastSuccessfulSyncAt = nil
        unreadableScope = nil
        localDiaryUnreadable = false
        activeScope = scope
        entries = []
        streakActivityDayKeys = []
    }

    func deleteEntry(at offsets: IndexSet, inCategory categoryId: UUID? = nil, date: Date = Date()) {
        let filtered = entries(for: date, categoryId: categoryId)
        let idsToDelete = offsets.map { filtered[$0].id }
        for id in idsToDelete {
            deleteEntry(id: id)
        }
    }

    func entriesForToday(categoryId: UUID? = nil) -> [CalorieEntry] {
        entries(for: Date(), categoryId: categoryId)
    }

    func entries(for date: Date, categoryId: UUID? = nil) -> [CalorieEntry] {
        let calendar = Calendar.current
        return entries.filter { entry in
            let isToday = calendar.isDate(entry.date, inSameDayAs: date)
            if let categoryId = categoryId {
                guard isToday else { return false }
                if entry.categoryId == categoryId { return true }
                guard let category = categoryStore?.categories.first(where: { $0.id == categoryId }) else { return false }
                return stableMealKey(entry.categoryName) == category.storageKey
            }
            return isToday
        }.sorted { $0.date > $1.date }
    }

    func totalKcal(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.kcal } }

    var activeDays: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        return Array(Set(entries.map { calendar.startOfDay(for: $0.date) })).sorted(by: >)
    }

    private var effectiveStreakDayKeys: Set<String> { streakActivityDayKeys.union(streakFrozenDayKeys) }
    var currentStreak: Int { StreakTracker.currentStreak(activityDays: effectiveStreakDayKeys) }
    var longestStreak: Int { StreakTracker.longestStreak(activityDays: effectiveStreakDayKeys) }
    var hasStreakActivityToday: Bool { StreakTracker.hasActivityToday(activityDays: streakActivityDayKeys) }
    func applyStreakFreezeDays(_ days: Set<String>) {
        streakFrozenDayKeys = days
    }
    func applyServerStreakDays(_ days: Set<String>) {
        guard syncAccountID != nil else { return }
        streakActivityDayKeys = days
        saveStreakActivity(scope: activeScope)
    }
    func totalCarbs(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.carbs } }
    func totalProtein(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.protein } }
    func totalFat(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.fat } }
    /// Gesamtzucker (zugesetzt + Frucht)
    func totalSugar(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.sugar } }
    /// Nur zugesetzter Zucker (ohne Obst)
    func totalAddedSugar(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.addedSugar } }
    /// Nur Fruchtzucker (aus als Obst markierten Lebensmitteln)
    func totalFruitSugar(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.fruitSugar } }
    func totalFiber(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.fiber } }
    func totalSaturatedFat(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.saturatedFat } }
    func totalSalt(for date: Date, categoryId: UUID? = nil) -> Double { entries(for: date, categoryId: categoryId).reduce(0) { $0 + $1.salt } }

    var totalKcalToday: Double { entriesForToday().reduce(0) { $0 + $1.kcal } }
    var totalCarbsToday: Double { entriesForToday().reduce(0) { $0 + $1.carbs } }
    var totalProteinToday: Double { entriesForToday().reduce(0) { $0 + $1.protein } }
    var totalFatToday: Double { entriesForToday().reduce(0) { $0 + $1.fat } }
    var totalSugarToday: Double { entriesForToday().reduce(0) { $0 + $1.sugar } }
    var totalAddedSugarToday: Double { entriesForToday().reduce(0) { $0 + $1.addedSugar } }
    var totalFruitSugarToday: Double { entriesForToday().reduce(0) { $0 + $1.fruitSugar } }
    var totalFiberToday: Double { entriesForToday().reduce(0) { $0 + $1.fiber } }
    var totalSaturatedFatToday: Double { entriesForToday().reduce(0) { $0 + $1.saturatedFat } }
    var totalSaltToday: Double { entriesForToday().reduce(0) { $0 + $1.salt } }

    func totalKcalToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.kcal }
    }
    func totalCarbsToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.carbs }
    }
    func totalProteinToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.protein }
    }
    func totalFatToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.fat }
    }
    func totalSugarToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.sugar }
    }
    func totalAddedSugarToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.addedSugar }
    }
    func totalFruitSugarToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.fruitSugar }
    }
    func totalFiberToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.fiber }
    }
    func totalSaturatedFatToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.saturatedFat }
    }
    func totalSaltToday(for categoryId: UUID) -> Double {
        entriesForToday(categoryId: categoryId).reduce(0) { $0 + $1.salt }
    }

    @discardableResult
    private func save(scope: EntryDataScope? = nil) -> Bool {
        let destination = scope ?? activeScope
        guard persistEntries(entries, scope: destination) else { return false }
        // 2. WICHTIG: Widget-Daten bei jedem Speichern aktualisieren
        updateWidget()
        return true
    }

    private func persistEntries(_ values: [CalorieEntry], scope: EntryDataScope) -> Bool {
        guard unreadableScope != scope else { return false }
        do {
            let data = try JSONEncoder().encode(values)
            try CalorieEntryDiskStore().write(data, forKey: storageKey(for: scope))
            // Keep the old UserDefaults representation for migration and for
            // existing code that reads the guest snapshot during login.
            UserDefaults.standard.set(data, forKey: storageKey(for: scope))
            _ = UserDefaults.standard.synchronize()
            return true
        } catch {
            logger.error("Failed to save local diary scope=\(scope.diagnosticName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func storedEntries(for scope: EntryDataScope) -> [CalorieEntry]? {
        if let diskStore = try? CalorieEntryDiskStore(),
           let diskData = diskStore.read(forKey: storageKey(for: scope)),
           let decoded = try? JSONDecoder().decode([CalorieEntry].self, from: diskData) {
            return decoded
        }
        let scopedData = UserDefaults.standard.data(forKey: storageKey(for: scope))
        let legacyGuestData = scope == .guest ? UserDefaults.standard.data(forKey: storageKey) : nil
        for data in [scopedData, legacyGuestData].compactMap({ $0 }) {
            if let decoded = try? JSONDecoder().decode([CalorieEntry].self, from: data) { return decoded }
        }
        if let previous = (try? CalorieEntryDiskStore())?.readPrevious(forKey: storageKey(for: scope)) {
            return try? JSONDecoder().decode([CalorieEntry].self, from: previous)
        }
        return nil
    }

    private func recordStreakActivityIfToday(_ entryDate: Date) {
        let updated = StreakTracker.recordingActivity(for: entryDate, existing: streakActivityDayKeys)
        guard updated != streakActivityDayKeys else { return }
        streakActivityDayKeys = updated
        saveStreakActivity(scope: activeScope)
    }

    private func saveStreakActivity(scope: EntryDataScope) {
        UserDefaults.standard.set(Array(streakActivityDayKeys).sorted(), forKey: streakStorageKey(for: scope))
    }

    private func loadStreakActivity(scope: EntryDataScope) {
        let key = streakStorageKey(for: scope)
        if let saved = UserDefaults.standard.stringArray(forKey: key) {
            streakActivityDayKeys = Set(saved)
        } else {
            streakActivityDayKeys = []
            migrateLegacyStreakActivityIfNeeded(scope: scope)
        }
    }

    /// One-time compatibility migration for activity that predates the explicit
    /// streak ledger. New backdated entries never pass through this migration.
    private func migrateLegacyStreakActivityIfNeeded(scope: EntryDataScope) {
        let key = streakStorageKey(for: scope)
        guard UserDefaults.standard.object(forKey: key) == nil, !entries.isEmpty else { return }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        streakActivityDayKeys = Set(entries.compactMap { entry in
            calendar.startOfDay(for: entry.date) <= today ? StreakTracker.dayKey(for: entry.date, calendar: calendar) : nil
        })
        saveStreakActivity(scope: scope)
    }

    private func mergeGuestStreakActivityIntoActiveAccount(accountID: String) {
        let guestKeys = Set(UserDefaults.standard.stringArray(forKey: streakStorageKey(for: .guest)) ?? [])
        guard !guestKeys.isEmpty else { return }
        streakActivityDayKeys.formUnion(guestKeys)
        saveStreakActivity(scope: .account(accountID))
    }

    private func markDirty(_ id: UUID) {
        guard let accountID = syncAccountID else { return }
        var dirty = storedIDs(forKey: dirtyKey(accountID)); dirty.insert(id); storeIDs(dirty, forKey: dirtyKey(accountID))
        var deleted = storedIDs(forKey: deletedKey(accountID)); deleted.remove(id); storeIDs(deleted, forKey: deletedKey(accountID))
    }

    private func markDeleted(_ id: UUID) {
        guard let accountID = syncAccountID else { return }
        var dirty = storedIDs(forKey: dirtyKey(accountID)); dirty.remove(id); storeIDs(dirty, forKey: dirtyKey(accountID))
        var deleted = storedIDs(forKey: deletedKey(accountID)); deleted.insert(id); storeIDs(deleted, forKey: deletedKey(accountID))
    }

    private func storedIDs(forKey key: String) -> Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    private func storeIDs(_ ids: Set<UUID>, forKey key: String) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
    }

    private func load(scope: EntryDataScope? = nil) {
        let source = scope ?? activeScope
        guard let decoded = storedEntries(for: source) else {
            let key = storageKey(for: source)
            let diskStore = try? CalorieEntryDiskStore()
            let hasUnreadableData = diskStore?.read(forKey: key) != nil
                || diskStore?.readPrevious(forKey: key) != nil
                || UserDefaults.standard.data(forKey: key) != nil
                || (source == .guest && UserDefaults.standard.data(forKey: storageKey) != nil)
            if hasUnreadableData {
                unreadableScope = source
                localDiaryUnreadable = true
                syncState = .failed
                logger.error("Diary snapshot cannot be decoded for scope=\(source.diagnosticName, privacy: .public); refusing to overwrite it")
            }
            entries = []
            updateWidget()
            return
        }
        unreadableScope = nil
        localDiaryUnreadable = false
        let pendingDeletions = source.accountID.map { storedIDs(forKey: deletedKey($0)) } ?? []
        entries = decoded.filter { !pendingDeletions.contains($0.id) }.map(normalizedCategory)
        if entries.count != decoded.count { _ = persistEntries(entries, scope: source) }
        updateWidget() // Synchronisiert die Daten direkt beim Start
    }

    func attachCategoryStore(_ store: CategoryStore) {
        categoryStore = store
        let normalized = entries.map(normalizedCategory)
        if normalized != entries {
            entries = normalized
            save()
        }
    }

    private func stableMealKey(_ value: String) -> String {
        MealCategory.legacySystemKey(for: value) ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedCategory(in entry: CalorieEntry) -> CalorieEntry {
        var value = entry
        let key = stableMealKey(entry.categoryName)
        value.categoryName = key
        if let category = categoryStore?.categories.first(where: { $0.storageKey == key }) {
            value.categoryId = category.id
        }
        return value
    }

    /// Writes the current value into the shared container before asking iOS to
    /// reload the widget. This can safely be called when the app becomes active,
    /// even if no entry was edited in that session.
    func refreshWidget(immediately: Bool = false) {
        widgetRefreshTask?.cancel()
        guard !immediately else {
            updateWidget()
            return
        }
        widgetRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.updateWidget()
        }
    }

    private func updateWidget() {
        let appGroupID = HyseConfiguration.appGroup
        if let userDefaults = UserDefaults(suiteName: appGroupID) {
            userDefaults.set(Int(totalKcalToday.rounded()), forKey: "todayEatenKcal")
            userDefaults.set(totalCarbsToday, forKey: "widgetCarbsGrams")
            userDefaults.set(totalProteinToday, forKey: "widgetProteinGrams")
            userDefaults.set(totalFatToday, forKey: "widgetFatGrams")
            userDefaults.set(
                Calendar.autoupdatingCurrent.startOfDay(for: Date()).timeIntervalSince1970,
                forKey: "todayEatenDate"
            )
            userDefaults.set(Date().timeIntervalSince1970, forKey: "widgetMacroDate")
            userDefaults.set(Date().timeIntervalSince1970, forKey: "widgetDataUpdatedAt")
            // Flush the app-group domain before WidgetKit starts a separate
            // process to read it. Without this, fast edits can show stale data.
            userDefaults.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
