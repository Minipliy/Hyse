import Foundation
import Combine

nonisolated enum StreakRewardSource: Sendable, Equatable {
    case nutrition
    case training
}

nonisolated struct StreakRewardEvent: Identifiable, Sendable {
    let id = UUID()
    let source: StreakRewardSource
    let amount: Int
}

/// Local-first streak economy. Reward receipts are persisted by calendar day,
/// so deleting and recreating entries cannot award currency more than once.
@MainActor
final class StreakRewardsStore: ObservableObject {
    static let nutritionReward = StreakRewardsState.nutritionReward
    static let trainingReward = StreakRewardsState.trainingReward
    static let nutritionFreezeCost = StreakRewardsState.nutritionFreezeCost
    static let trainingFreezeCost = StreakRewardsState.trainingFreezeCost
    static let maximumFreezeCount = StreakRewardsState.maximumFreezeCount

    @Published private(set) var iceCrystals = 0
    @Published private(set) var nutritionFreezeCount = 0
    @Published private(set) var trainingFreezeCount = 0
    @Published private(set) var nutritionFrozenDayKeys: Set<String> = []
    @Published private(set) var trainingFrozenWeekKeys: Set<String> = []
    @Published private(set) var lastReward: StreakRewardEvent?

    weak var authManager: AuthManager?

    private var state = StreakRewardsState()
    private var scope = "guest"
    private var activeAccountID: String?
    private var profileRevision: UInt = 0
    private var stateRevision: UInt = 0
    private var cloudHydrated = true
    private var latestNutritionActivityDays: Set<String> = []
    private var latestWorkoutDates: [Date] = []
    private var rewardDismissTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var deferredSyncTask: Task<Void, Never>?
    private var lastSuccessfulSyncAt: Date?

    init() {
        load(scope: scope)
    }

    func activate(accountID: String?) {
        let nextScope = accountID.map { "account_\($0)" } ?? "guest"
        guard nextScope != scope else {
            activeAccountID = accountID
            if accountID != nil { syncPendingState() }
            return
        }
        profileRevision &+= 1
        syncTask?.cancel()
        deferredSyncTask?.cancel()
        activeAccountID = accountID
        scope = nextScope
        lastSuccessfulSyncAt = accountID.flatMap { UserDefaults.standard.object(forKey: lastSuccessfulSyncKey($0)) as? Date }
        cloudHydrated = accountID == nil || UserDefaults.standard.data(forKey: storageKey(for: nextScope)) != nil
        load(scope: nextScope)
        if accountID != nil { syncPendingState() }
    }

    func reconcile(nutritionActivityDays: Set<String>, workoutDates: [Date], now: Date = Date()) {
        latestNutritionActivityDays = nutritionActivityDays
        latestWorkoutDates = workoutDates
        let previousState = state
        let calendar = Calendar.autoupdatingCurrent
        let todayKey = StreakTracker.dayKey(for: now, calendar: calendar)

        if nutritionActivityDays.contains(todayKey), state.rewardedNutritionDayKeys.insert(todayKey).inserted {
            state.iceCrystals += Self.nutritionReward
            showReward(source: .nutrition, amount: Self.nutritionReward)
        }
        if workoutDates.contains(where: { calendar.isDate($0, inSameDayAs: now) }),
           state.rewardedTrainingDayKeys.insert(todayKey).inserted {
            state.iceCrystals += Self.trainingReward
            showReward(source: .training, amount: Self.trainingReward)
        }

        applyAvailableFreezes(now: now, calendar: calendar)
        if state != previousState { persistAndPublish() }
        else { publish() }
    }

    @discardableResult
    func buyNutritionFreeze() -> Bool {
        guard state.nutritionFreezeCount < Self.maximumFreezeCount,
              state.iceCrystals >= Self.nutritionFreezeCost else { return false }
        state.iceCrystals -= Self.nutritionFreezeCost
        state.nutritionFreezeCount += 1
        applyAvailableFreezes(now: Date(), calendar: .autoupdatingCurrent)
        persistAndPublish()
        return true
    }

    @discardableResult
    func buyTrainingFreeze() -> Bool {
        guard state.trainingFreezeCount < Self.maximumFreezeCount,
              state.iceCrystals >= Self.trainingFreezeCost else { return false }
        state.iceCrystals -= Self.trainingFreezeCost
        state.trainingFreezeCount += 1
        applyAvailableFreezes(now: Date(), calendar: .autoupdatingCurrent)
        persistAndPublish()
        return true
    }

    func clearLastReward() {
        rewardDismissTask?.cancel()
        rewardDismissTask = nil
        lastReward = nil
    }

    private func applyAvailableFreezes(now: Date, calendar: Calendar) {
        applyNutritionFreezes(now: now, calendar: calendar)
        applyTrainingFreezes(now: now, calendar: calendar)
    }

    private func applyNutritionFreezes(now: Date, calendar: Calendar) {
        guard state.nutritionFreezeCount > 0,
              let target = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return }
        let effectiveKeys = latestNutritionActivityDays.union(state.nutritionFrozenDayKeys)
        guard let latest = effectiveKeys.compactMap({ StreakTracker.date(forDayKey: $0, calendar: calendar) })
            .filter({ $0 <= target }).max() else { return }

        var missing: [String] = []
        var cursor = latest
        while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next <= target {
            cursor = next
            let key = StreakTracker.dayKey(for: cursor, calendar: calendar)
            if !effectiveKeys.contains(key) { missing.append(key) }
        }
        guard !missing.isEmpty, missing.count <= state.nutritionFreezeCount else { return }
        state.nutritionFreezeCount -= missing.count
        state.nutritionFrozenDayKeys.formUnion(missing)
    }

    private func applyTrainingFreezes(now: Date, calendar: Calendar) {
        guard state.trainingFreezeCount > 0,
              let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let target = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek) else { return }
        let workoutWeekKeys = Set(latestWorkoutDates.compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0).map { StreakTracker.dayKey(for: $0.start, calendar: calendar) }
        })
        let effectiveKeys = workoutWeekKeys.union(state.trainingFrozenWeekKeys)
        guard let latest = effectiveKeys.compactMap({ StreakTracker.date(forDayKey: $0, calendar: calendar) })
            .filter({ $0 <= target }).max() else { return }

        var missing: [String] = []
        var cursor = latest
        while let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor), next <= target {
            cursor = next
            let key = StreakTracker.dayKey(for: cursor, calendar: calendar)
            if !effectiveKeys.contains(key) { missing.append(key) }
        }
        guard !missing.isEmpty, missing.count <= state.trainingFreezeCount else { return }
        state.trainingFreezeCount -= missing.count
        state.trainingFrozenWeekKeys.formUnion(missing)
    }

    private func showReward(source: StreakRewardSource, amount: Int) {
        let event = StreakRewardEvent(source: source, amount: amount)
        lastReward = event
        rewardDismissTask?.cancel()
        rewardDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, self?.lastReward?.id == event.id else { return }
            self?.lastReward = nil
        }
    }

    private func storageKey(for scope: String) -> String {
        "streak_rewards_\(scope)_v1"
    }

    private func load(scope: String) {
        if let data = UserDefaults.standard.data(forKey: storageKey(for: scope)),
           let decoded = try? JSONDecoder().decode(StreakRewardsState.self, from: data) {
            state = decoded
            state.nutritionFreezeCount = min(state.nutritionFreezeCount, Self.maximumFreezeCount)
            state.trainingFreezeCount = min(state.trainingFreezeCount, Self.maximumFreezeCount)
        } else {
            state = StreakRewardsState()
        }
        lastReward = nil
        publish()
    }

    private func persistAndPublish() {
        stateRevision &+= 1
        UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: storageKey(for: scope))
        UserDefaults.standard.set(Date(), forKey: modificationDateKey(for: scope))
        UserDefaults.standard.set(true, forKey: pendingSyncKey(for: scope))
        publish()
        schedulePendingSync()
    }

    private func publish() {
        iceCrystals = state.iceCrystals
        nutritionFreezeCount = state.nutritionFreezeCount
        trainingFreezeCount = state.trainingFreezeCount
        nutritionFrozenDayKeys = state.nutritionFrozenDayKeys
        trainingFrozenWeekKeys = state.trainingFrozenWeekKeys
    }

    func syncPendingState() {
        guard let authManager, authManager.isLoggedIn,
              let accountID = activeAccountID,
              accountID == authManager.accountID,
              !authManager.token.isEmpty else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = nil
        let hasPendingLocalChange = UserDefaults.standard.bool(forKey: pendingSyncKey(for: scope))
        if !hasPendingLocalChange,
           let lastSuccessfulSyncAt, Date().timeIntervalSince(lastSuccessfulSyncAt) < 3_600 { return }
        let localState = state
        let localUpdatedAt = UserDefaults.standard.object(forKey: modificationDateKey(for: scope)) as? Date ?? .distantPast
        let expectedProfileRevision = profileRevision
        let expectedStateRevision = stateRevision
        let token = authManager.token
        let mergeFirstLocalActions = !cloudHydrated
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            let result = await StreakRewardsSyncService.shared.sync(
                localState: localState,
                localUpdatedAt: localUpdatedAt,
                mergeFirstLocalActions: mergeFirstLocalActions,
                userID: accountID,
                token: token
            )
            guard !Task.isCancelled, let self,
                  self.profileRevision == expectedProfileRevision,
                  self.stateRevision == expectedStateRevision,
                  self.activeAccountID == accountID,
                  self.authManager?.accountID == accountID else { return }
            guard result.didSync, let resolvedState = result.state else {
                self.scheduleRetry()
                return
            }
            self.cloudHydrated = true
            self.state = resolvedState
            self.state.nutritionFreezeCount = min(self.state.nutritionFreezeCount, Self.maximumFreezeCount)
            self.state.trainingFreezeCount = min(self.state.trainingFreezeCount, Self.maximumFreezeCount)
            UserDefaults.standard.set(try? JSONEncoder().encode(self.state), forKey: self.storageKey(for: self.scope))
            UserDefaults.standard.set(result.updatedAt, forKey: self.modificationDateKey(for: self.scope))
            UserDefaults.standard.set(false, forKey: self.pendingSyncKey(for: self.scope))
            let now = Date()
            self.lastSuccessfulSyncAt = now
            UserDefaults.standard.set(now, forKey: self.lastSuccessfulSyncKey(accountID))
            self.publish()
            self.reconcile(
                nutritionActivityDays: self.latestNutritionActivityDays,
                workoutDates: self.latestWorkoutDates
            )
        }
    }

    func flushPendingState() async {
        deferredSyncTask?.cancel()
        deferredSyncTask = nil
        syncPendingState()
        await syncTask?.value
    }

    private func modificationDateKey(for scope: String) -> String {
        "streak_rewards_updated_\(scope)_v1"
    }

    private func pendingSyncKey(for scope: String) -> String { "streak_rewards_pending_\(scope)_v1" }
    private func lastSuccessfulSyncKey(_ accountID: String) -> String { "streak_rewards_last_sync_\(accountID)_v1" }

    private func schedulePendingSync() {
        guard activeAccountID != nil else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.deferredSyncTask = nil
            self.syncPendingState()
        }
    }

    private func scheduleRetry() {
        deferredSyncTask?.cancel()
        deferredSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            self.deferredSyncTask = nil
            self.syncPendingState()
        }
    }
}
