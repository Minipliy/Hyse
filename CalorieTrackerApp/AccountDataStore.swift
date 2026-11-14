import Foundation
import Combine
import OSLog

nonisolated enum HyseLegalVersion {
    // Change these values only for material legal changes. Editorial website
    // corrections intentionally keep the same version.
    static let terms = "terms-2026-09-4"
    static let privacy = "privacy-2026-09-3"

    static func canMigrate(terms: String, privacy: String) -> Bool {
        // This revision changes health-data sync and removes remote analysis.
        // Earlier acknowledgements do not cover those material changes.
        false
    }
}

nonisolated struct LastUsedAmount: Codable, Equatable, Identifiable {
    let foodKey: String
    var amount: Double
    var unit: FoodUnit
    var mealKey: String
    var usedAt: Date
    var foodName: String
    var globalFoodRecordID: String?
    var portionID: UUID? = nil
    var portionCount: Double? = nil

    var id: String { foodKey }
}

nonisolated struct SyncedSettingsSnapshot: Codable, Equatable {
    var schemaVersion = 22
    var updatedAt = Date()
    var baseCalorieGoal: Double
    var enforceCalorieLimit: Bool
    var calorieLimitBufferKilocalories: Double?
    var calorieGoalMode: String
    var mealCategories: [MealCategory]?
    var blockFoodTrackingWhileFastingEnabled: Bool?
    var foodTrackingWindowEnabled: Bool?
    var foodTrackingWindowStartMinutes: Int?
    var foodTrackingWindowEndMinutes: Int?
    var hideNutritionOutsideTrackingWindow: Bool?
    var lockTrackingWindowSettingsOutsideHours: Bool?
    var lowRemainingTrackingLockEnabled: Bool?
    var lowRemainingTrackingLockStartMinutes: Int?
    var lowRemainingTrackingCaloriesThreshold: Double?
    var lowCalorieEntryWarningEnabled: Bool?
    var lowCalorieEntryWarningThreshold: Double?
    /// Legacy decode-only field retained so existing version-1 snapshots remain readable.
    var dynamicCalorieAdjustment: Double?
    var dynamicCalorieTargetMode: String?
    var fixedCalorieSurplus: Double?
    var fixedCalorieDeficit: Double?
    var trainingDayCalorieAdjustment: Double?
    var restDayCalorieAdjustment: Double?
    var dynamicDeficitPhaseStartDate: Date?
    var dynamicDeficitInitialBodyFatFraction: Double?
    var dynamicDeficitInitialWeightKilograms: Double?
    var dynamicDeficitPhases: [DynamicDeficitPhase]?
    var calorieGoalHistory: [CalorieGoalConfiguration]?
    var scheduledCaloriePhase: ScheduledCaloriePhase?
    var calorieDayTypes: [CalorieDayTypeRecord]?
    var carbsPercentage: Int
    var proteinPercentage: Int
    var fatPercentage: Int
    var macroGoalPlan: MacroGoalPlan?
    var nutritionActivityLevel: String?
    var onboardingGoal: String?
    var onboardingSex: String?
    var tracking_interest: String?
    var profileAgeYears: Int?
    var profileHeightCentimeters: Double?
    var profileWeightKilograms: Double?
    var dailyWaterGoalMilliliters: Double
    var waterGlassSizeMilliliters: Double
    var addedSugarGoalGrams: Double
    var fruitSugarGoalGrams: Double
    var saltGoalGrams: Double
    var fiberGoalGrams: Double
    var saturatedFatGoalGrams: Double
    var theme: String
    var defaultFoodUnit: String
    var defaultLiquidUnit: String?
    var trainingWeightUnit: String?
    var trainingDistanceUnit: String?
    var count_unilateral_sets_as_half: Bool?
    var default_workout_gym_name: String?
    var default_workout_gym_address: String?
    var default_workout_gym_latitude: Double?
    var default_workout_gym_longitude: Double?
    var default_workout_visibility: String?
    var automatically_start_apple_watch_workout: Bool?
    var rest_sound_enabled: Bool?
    var rest_notification_enabled: Bool?
    var rest_haptics_enabled: Bool?
    var rest_sound_variant: String?
    var rest_sound_volume: Double?
    var live_activity_enabled: Bool?
    var motivation_notifications_enabled: Bool?
    var motivation_notification_frequency: String?
    var motivational_messages_enabled: Bool?
    var food_log_reminder_enabled: Bool?
    var water_reminder_enabled: Bool?
    var planned_training_reminder_enabled: Bool?
    var missing_daily_data_reminder_enabled: Bool?
    var community_news_notifications_enabled: Bool?
    var hyse_update_notifications_enabled: Bool?
    var workout_like_notifications_enabled: Bool?
    var workout_comment_notifications_enabled: Bool?
    var friend_activity_notifications_enabled: Bool?
    var monthly_training_report_notifications_enabled: Bool?
    var visible_nutrition_metric_ids: [String]?
    var home_additional_nutrition_metric_ids: [String]?
    var selected_nutrition_profile_ids: [String]?
    var home_training_overview_visible: Bool?
    var home_section_order: [String]?
    var home_visible_section_ids: [String]?
    var language: String
}

@MainActor
final class AccountDataStore: ObservableObject {
    static let onboardingVersion = 2

    @Published private(set) var acceptedTermsVersion = ""
    @Published private(set) var acceptedPrivacyVersion = ""
    @Published private(set) var consentTimestamp: Date?
    @Published private(set) var consentLanguage = "en"
    @Published private(set) var cloudSyncConsent = false
    @Published var marketingConsent = false
    @Published private(set) var marketingConsentUpdatedAt: Date?
    @Published private(set) var marketingConsentLanguage = "en"
    @Published private(set) var marketingConsentPrivacyVersion = ""
    @Published private(set) var onboardingCompletedVersion = 0
    @Published private(set) var lastUsedAmounts: [String: LastUsedAmount] = [:]
    @Published private(set) var isSyncing = false
    @Published private(set) var isHydratingAccountSettings = true
    @Published private(set) var hasRestoredAccountSettings = false
    @Published private(set) var accountSettingsLoadFailed = false
    @Published private(set) var syncError: String?
    @Published private(set) var serverStreakDays: Set<String> = []

    weak var authManager: AuthManager?
    weak var categoryStore: CategoryStore?
    private let baseURL = HyseConfiguration.serverURL
    private let cloudSyncConsentStorageKey = "hyse_explicit_health_sync_consent_v2"
    /// Consent is a device-level legal acknowledgement, not account content.
    /// Keep a small receipt outside guest/account scopes so switching scope
    /// while the account state is hydrating can never show the prompt again.
    private let legalConsentReceiptStorageKey = "hyse_legal_consent_receipt_v1"
    private var accountID: String?
    private var stateSyncTask: Task<Void, Never>?
    private var hasResolvedInitialAccountState = false
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "AccountData")
    private var installationID: String {
        let key = "hyse_anonymous_installation_id_v1"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty { return existing }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    var hasRequiredConsent: Bool {
        acceptedTermsVersion == HyseLegalVersion.terms && acceptedPrivacyVersion == HyseLegalVersion.privacy
    }

    var hasCompletedOnboarding: Bool { onboardingCompletedVersion >= Self.onboardingVersion }
    var hasEstablishedAccountProfile: Bool { hasRestoredAccountSettings || hasCompletedOnboarding }
    var activeAccountID: String? { accountID }

    init() {
        load(scope: "guest")
        // Older app versions enabled health-data sync automatically. Never
        // migrate that value into the new explicit-consent key.
        cloudSyncConsent = false
    }

    func attach(_ authManager: AuthManager) {
        self.authManager = authManager
        cloudSyncConsent = hasHealthSyncConsentForCurrentAccount
        restoreAccountScopedConsentIfNeeded(authManager)
    }

    func attachCategoryStore(_ categoryStore: CategoryStore, settingsStore: UserSettingsStore, language: LanguageStore) {
        self.categoryStore = categoryStore
        categoryStore.onLocalChange = { [weak self, weak settingsStore, weak language] in
            guard let self, let settingsStore, let language else { return }
            self.syncSettings(settingsStore, language: language)
        }
    }

    var hasHealthSyncConsentForCurrentAccount: Bool {
        guard let authManager, authManager.isLoggedIn, !authManager.accountID.isEmpty else { return false }
        return UserDefaults.standard.string(forKey: "\(cloudSyncConsentStorageKey)_\(authManager.accountID)") == HyseLegalVersion.privacy
    }

    func activateAccount(settingsStore: UserSettingsStore, language: LanguageStore) {
        guard let authManager, authManager.isLoggedIn, !authManager.accountID.isEmpty,
              hasHealthSyncConsentForCurrentAccount else { return }
        cloudSyncConsent = true
        let id = authManager.accountID
        guard accountID != id else { return }
        isHydratingAccountSettings = true
        hasRestoredAccountSettings = false
        accountSettingsLoadFailed = false
        hasResolvedInitialAccountState = false
        let guest = localState(scope: "guest")
        accountID = id
        load(scope: "account_\(id)")
        mergeGuestState(guest)
        if let cachedSettings = loadSettingsSnapshot(scope: activeScope) {
            settingsStore.applySyncedSnapshot(cachedSettings)
            if let categories = cachedSettings.mealCategories { categoryStore?.applySyncedCategories(categories) }
            language.applySyncedPreference(cachedSettings.language)
            hasRestoredAccountSettings = true
            // A cached account snapshot is already safe to display while the
            // server refresh continues in the background.
            isHydratingAccountSettings = false
        }
        syncConsentReceipts(source: "account_activation")
        Task { await hydrateFromServer(settingsStore: settingsStore, language: language) }
    }

    func refreshAccountState(settingsStore: UserSettingsStore, language: LanguageStore) async {
        guard accountID != nil, !isSyncing else { return }
        await hydrateFromServer(settingsStore: settingsStore, language: language)
    }

    func deactivateAccount() {
        accountID = nil
        cloudSyncConsent = false
        isHydratingAccountSettings = false
        hasRestoredAccountSettings = false
        accountSettingsLoadFailed = false
        hasResolvedInitialAccountState = false
        load(scope: "guest")
        serverStreakDays = []
        syncError = nil
    }

    func acceptRequired(language: AppLanguage, marketing: Bool) {
        acceptedTermsVersion = HyseLegalVersion.terms
        acceptedPrivacyVersion = HyseLegalVersion.privacy
        consentTimestamp = Date()
        consentLanguage = language.rawValue
        marketingConsent = marketing
        marketingConsentUpdatedAt = Date()
        marketingConsentLanguage = language.rawValue
        marketingConsentPrivacyVersion = HyseLegalVersion.privacy
        save()
        saveLegalConsentReceipt()
        syncConsentReceipts(source: "first_launch")
        syncCurrentState(languageCode: language.rawValue)
    }

    func updateMarketingConsent(_ marketing: Bool, language: AppLanguage) {
        marketingConsent = marketing
        marketingConsentUpdatedAt = Date()
        marketingConsentLanguage = language.rawValue
        marketingConsentPrivacyVersion = HyseLegalVersion.privacy
        save()
        syncConsentReceipts(source: "privacy_settings", categories: ["marketing_email"])
        syncCurrentState(languageCode: language.rawValue)
    }

    func grantHealthSyncConsent(language: AppLanguage) {
        guard hasRequiredConsent, let authManager, authManager.isLoggedIn, !authManager.accountID.isEmpty else { return }
        cloudSyncConsent = true
        UserDefaults.standard.set(HyseLegalVersion.privacy, forKey: "\(cloudSyncConsentStorageKey)_\(authManager.accountID)")
        syncConsentReceipts(source: "explicit_health_sync_consent", categories: ["cloud_sync"])
    }

    private func syncConsentReceipts(source: String, categories: Set<String> = ["terms", "privacy_notice", "cloud_sync", "marketing_email"]) {
        guard let authManager, authManager.isLoggedIn, !authManager.token.isEmpty,
              let url = URL(string: "\(baseURL)/api/hyse/consents") else { return }
        var receipts: [[String: Any]] = []
        if categories.contains("terms"), acceptedTermsVersion == HyseLegalVersion.terms {
            receipts.append(["category": "terms", "granted": true, "document_version": HyseLegalVersion.terms])
        }
        if categories.contains("privacy_notice"), acceptedPrivacyVersion == HyseLegalVersion.privacy {
            receipts.append(["category": "privacy_notice", "granted": true, "document_version": HyseLegalVersion.privacy])
        }
        if categories.contains("cloud_sync") {
            receipts.append(["category": "cloud_sync", "granted": hasHealthSyncConsentForCurrentAccount, "document_version": HyseLegalVersion.privacy])
        }
        if categories.contains("marketing_email") {
            receipts.append(["category": "marketing_email", "granted": marketingConsent, "document_version": HyseLegalVersion.privacy])
        }
        guard !receipts.isEmpty else { return }
        let payload: [String: Any] = ["installation_id": installationID, "language": consentLanguage, "source": source, "receipts": receipts]
        let token = authManager.token
        Task {
            var request = URLRequest(url: url); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if !(200...299).contains(status) { logger.error("Consent receipt upload rejected with status \(status)") }
            } catch { logger.error("Consent receipt upload failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func completeOnboarding(skipped: Bool = false) {
        onboardingCompletedVersion = Self.onboardingVersion
        save()
        syncCurrentState(languageCode: AppLanguage.persisted.rawValue)
    }

    func resetOnboardingForReplay() {
        onboardingCompletedVersion = 0
        save()
    }

    func suggestion(for food: FoodItem) -> LastUsedAmount {
        let key = Self.foodKey(food)
        if let recent = lastUsedAmounts[key], recent.amount > 0, FoodUnit.allCases.contains(recent.unit) { return recent }
        let amount = food.defaultPortionBaseAmount.flatMap { $0 > 0 ? $0 : nil } ?? 100
        return LastUsedAmount(foodKey: key, amount: amount, unit: food.unit, mealKey: "", usedAt: .distantPast, foodName: food.name, globalFoodRecordID: food.globalRecordID)
    }

    func recordUsage(food: FoodItem, amount: Double, mealKey: String, portionID: UUID? = nil, portionCount: Double? = nil, usedAt: Date = Date()) {
        guard amount > 0 else { return }
        let value = LastUsedAmount(foodKey: Self.foodKey(food), amount: amount, unit: food.unit, mealKey: mealKey, usedAt: usedAt, foodName: food.name, globalFoodRecordID: food.globalRecordID, portionID: portionID, portionCount: portionCount)
        lastUsedAmounts[value.foodKey] = value
        save()
    }

    var recentUsage: [LastUsedAmount] { lastUsedAmounts.values.sorted { $0.usedAt > $1.usedAt } }

    static func foodKey(_ food: FoodItem) -> String {
        if let global = food.globalRecordID, !global.isEmpty { return "global:\(global)" }
        return "local:\(food.id.uuidString.lowercased())"
    }

    func syncSettings(_ settingsStore: UserSettingsStore, language: LanguageStore) {
        // Create one snapshot for both the local cache and the request. Two
        // independently created snapshots have subtly different timestamps,
        // which makes it possible for an older in-flight request to look newer
        // than the value we just cached.
        let snapshot = settingsStore.syncSnapshot(languagePreference: language.preference, mealCategories: categoryStore?.categories)
        saveSettingsSnapshot(snapshot, scope: activeScope)
        syncCurrentState(languageCode: language.language.rawValue, settings: snapshot)
    }

    func waitForPendingSettingsSync() async {
        await stateSyncTask?.value
    }

    /// Marks the on-device value as newer as soon as the user changes it.
    /// Uploads remain debounced by the view, but an in-flight account refresh
    /// can no longer replace the change during that short debounce window.
    func stageSettings(_ settingsStore: UserSettingsStore, language: LanguageStore) {
        saveSettingsSnapshot(
            settingsStore.syncSnapshot(languagePreference: language.preference, mealCategories: categoryStore?.categories),
            scope: activeScope
        )
    }

    private var activeScope: String { accountID.map { "account_\($0)" } ?? "guest" }
    private func key(_ name: String, scope: String) -> String { "account_data_\(name)_\(scope)_v1" }

    private struct LocalState: Codable {
        var terms = ""
        var privacy = ""
        var timestamp: Date?
        var language = "en"
        var marketing = false
        var marketingUpdatedAt: Date?
        var marketingLanguage = "en"
        var marketingPrivacyVersion = ""
        var onboarding = 0
        var usage: [String: LastUsedAmount] = [:]
    }

    private struct LegalConsentReceipt: Codable {
        var terms: String
        var privacy: String
        var timestamp: Date?
        var language: String
    }

    private func localState(scope: String) -> LocalState {
        guard let data = UserDefaults.standard.data(forKey: key("state", scope: scope)),
              let value = try? JSONDecoder().decode(LocalState.self, from: data) else { return LocalState() }
        return value
    }

    private func load(scope: String) {
        var state = localState(scope: scope)
        var changed = false
        if !isAcceptedOrMigratable(terms: state.terms, privacy: state.privacy),
           let receipt = legalConsentReceipt(),
           isAcceptedOrMigratable(terms: receipt.terms, privacy: receipt.privacy) {
            state.terms = HyseLegalVersion.terms
            state.privacy = HyseLegalVersion.privacy
            state.timestamp = state.timestamp ?? receipt.timestamp
            state.language = receipt.language == "de" ? "de" : "en"
            changed = true
        }
        if HyseLegalVersion.canMigrate(terms: state.terms, privacy: state.privacy) {
            state.terms = HyseLegalVersion.terms
            state.privacy = HyseLegalVersion.privacy
            changed = true
        }
        if changed {
            UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: key("state", scope: scope))
        }
        acceptedTermsVersion = state.terms
        acceptedPrivacyVersion = state.privacy
        consentTimestamp = state.timestamp
        consentLanguage = state.language
        marketingConsent = state.marketing
        marketingConsentUpdatedAt = state.marketingUpdatedAt
        marketingConsentLanguage = state.marketingLanguage
        marketingConsentPrivacyVersion = state.marketingPrivacyVersion
        onboardingCompletedVersion = state.onboarding
        lastUsedAmounts = state.usage

        if acceptedTermsVersion == HyseLegalVersion.terms, acceptedPrivacyVersion == HyseLegalVersion.privacy {
            saveLegalConsentReceipt()
        }
    }

    private func isAcceptedOrMigratable(terms: String, privacy: String) -> Bool {
        (terms == HyseLegalVersion.terms && privacy == HyseLegalVersion.privacy)
            || HyseLegalVersion.canMigrate(terms: terms, privacy: privacy)
    }

    /// Older app versions kept a valid acknowledgement only inside the
    /// account-scoped cache. Recover it before ContentView evaluates the
    /// first-launch gate, otherwise a signed-in returning user is asked to
    /// accept again before the account cache can be activated.
    private func restoreAccountScopedConsentIfNeeded(_ authManager: AuthManager) {
        guard !hasRequiredConsent,
              authManager.isLoggedIn,
              !authManager.accountID.isEmpty else { return }

        let accountState = localState(scope: "account_\(authManager.accountID)")
        guard isAcceptedOrMigratable(terms: accountState.terms, privacy: accountState.privacy) else { return }

        var guestState = localState(scope: "guest")
        guestState.terms = HyseLegalVersion.terms
        guestState.privacy = HyseLegalVersion.privacy
        guestState.timestamp = guestState.timestamp ?? accountState.timestamp
        guestState.language = accountState.language == "de" ? "de" : "en"
        UserDefaults.standard.set(try? JSONEncoder().encode(guestState), forKey: key("state", scope: "guest"))
        load(scope: "guest")
    }

    private func legalConsentReceipt() -> LegalConsentReceipt? {
        guard let data = UserDefaults.standard.data(forKey: legalConsentReceiptStorageKey) else { return nil }
        return try? JSONDecoder().decode(LegalConsentReceipt.self, from: data)
    }

    private func saveLegalConsentReceipt() {
        let receipt = LegalConsentReceipt(
            terms: acceptedTermsVersion,
            privacy: acceptedPrivacyVersion,
            timestamp: consentTimestamp,
            language: consentLanguage
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(receipt), forKey: legalConsentReceiptStorageKey)
    }

    private func save() {
        let state = LocalState(terms: acceptedTermsVersion, privacy: acceptedPrivacyVersion, timestamp: consentTimestamp, language: consentLanguage, marketing: marketingConsent, marketingUpdatedAt: marketingConsentUpdatedAt, marketingLanguage: marketingConsentLanguage, marketingPrivacyVersion: marketingConsentPrivacyVersion, onboarding: onboardingCompletedVersion, usage: lastUsedAmounts)
        UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: key("state", scope: activeScope))
    }

    private func mergeGuestState(_ guest: LocalState) {
        if !hasRequiredConsent, guest.terms == HyseLegalVersion.terms, guest.privacy == HyseLegalVersion.privacy {
            acceptedTermsVersion = guest.terms
            acceptedPrivacyVersion = guest.privacy
            consentTimestamp = guest.timestamp
        }
        if let guestMarketingDate = guest.marketingUpdatedAt,
           marketingConsentUpdatedAt == nil || guestMarketingDate > marketingConsentUpdatedAt! {
            marketingConsent = guest.marketing
            marketingConsentUpdatedAt = guestMarketingDate
            marketingConsentLanguage = guest.marketingLanguage
            marketingConsentPrivacyVersion = guest.marketingPrivacyVersion
        }
        onboardingCompletedVersion = max(onboardingCompletedVersion, guest.onboarding)
        // Guest usage is derived from the guest meal entries during their
        // idempotent merge. Never upload a locally editable aggregate.
        save()
    }

    private struct RemoteState: Decodable {
        var termsVersion: String?
        var privacyVersion: String?
        var consentTimestamp: String?
        var consentLanguage: String?
        var marketingConsent: Bool?
        var marketingConsentUpdatedAt: String?
        var marketingConsentLanguage: String?
        var marketingConsentPrivacyVersion: String?
        var onboardingVersion: Int?
        var usage: [LastUsedAmount]?
        var settings: SyncedSettingsSnapshot?
        var streakDays: [String]?
    }

    private func hydrateFromServer(settingsStore: UserSettingsStore, language: LanguageStore) async {
        guard let authManager, authManager.isLoggedIn, !authManager.token.isEmpty,
              let url = URL(string: "\(baseURL)/api/hyse/account-state") else {
            isHydratingAccountSettings = false
            accountSettingsLoadFailed = !hasEstablishedAccountProfile
            return
        }
        if !hasRestoredAccountSettings { isHydratingAccountSettings = true }
        accountSettingsLoadFailed = false
        isSyncing = true
        defer {
            isSyncing = false
            isHydratingAccountSettings = false
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authManager.token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let remote = try JSONDecoder().decode(RemoteState.self, from: data)
            if remote.termsVersion == HyseLegalVersion.terms { acceptedTermsVersion = HyseLegalVersion.terms }
            if remote.privacyVersion == HyseLegalVersion.privacy { acceptedPrivacyVersion = HyseLegalVersion.privacy }
            if let timestamp = remote.consentTimestamp.flatMap(CalorieEntrySyncService.date(from:)) { consentTimestamp = timestamp }
            if let value = remote.consentLanguage, value == "de" || value == "en" { consentLanguage = value }
            let remoteMarketingDate = remote.marketingConsentUpdatedAt.flatMap(CalorieEntrySyncService.date(from:))
            if marketingConsentUpdatedAt == nil || (remoteMarketingDate != nil && remoteMarketingDate! >= marketingConsentUpdatedAt!) {
                marketingConsent = remote.marketingConsent ?? marketingConsent
                if let remoteMarketingDate { marketingConsentUpdatedAt = remoteMarketingDate }
                if let value = remote.marketingConsentLanguage, value == "de" || value == "en" { marketingConsentLanguage = value }
                marketingConsentPrivacyVersion = remote.marketingConsentPrivacyVersion ?? marketingConsentPrivacyVersion
            }
            onboardingCompletedVersion = max(onboardingCompletedVersion, remote.onboardingVersion ?? 0)
            await hydrateUsageFromServer(token: authManager.token)
            // A new account can upload its tracking choice before profile
            // setup is finished. A later refresh must not treat that partial
            // snapshot as a previously configured profile.
            if !hasResolvedInitialAccountState || hasCompletedOnboarding {
                if remote.settings != nil { hasRestoredAccountSettings = true }
            }
            hasResolvedInitialAccountState = true
            if let snapshot = remote.settings,
               shouldApplyRemoteSettings(snapshot, in: activeScope) {
                settingsStore.applySyncedSnapshot(snapshot)
                if let categories = snapshot.mealCategories { categoryStore?.applySyncedCategories(categories) }
                language.applySyncedPreference(snapshot.language)
                saveSettingsSnapshot(snapshot, scope: activeScope)
            }
            serverStreakDays = Set(remote.streakDays ?? [])
            save()
            syncError = nil
            accountSettingsLoadFailed = false
            syncCurrentState(
                languageCode: language.language.rawValue,
                settings: hasRestoredAccountSettings
                    ? settingsStore.syncSnapshot(languagePreference: language.preference, mealCategories: categoryStore?.categories)
                    : nil
            )
        } catch {
            accountSettingsLoadFailed = !hasEstablishedAccountProfile
            syncError = LanguageStore.localizedString("account_data.sync_failed")
            logger.error("Account-state hydration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct UsagePage: Decodable { let page: Int; let totalPages: Int; let items: [UsageRecord] }
    private struct UsageRecord: Decodable {
        let source: String; let foodID: String?; let clientItemID: String?; let lastName: String?
        let lastAmount: Double; let lastUnit: String?; let lastMeal: String?; let lastUsedAt: String
        let lastPortionID: String?; let lastPortionCount: Double?
        enum CodingKeys: String, CodingKey {
            case source; case foodID = "food_id"; case clientItemID = "client_item_id"; case lastName = "last_name"
            case lastAmount = "last_amount"; case lastUnit = "last_unit"; case lastMeal = "last_meal"; case lastUsedAt = "last_used_at"
            case lastPortionID = "last_portion_id"; case lastPortionCount = "last_portion_count"
        }
    }

    /// Restores last-used values from the same server-owned aggregate used by
    /// sorting. This replaces legacy client-written `usage_json` after login.
    private func hydrateUsageFromServer(token: String) async {
        var page = 1
        var restored: [String: LastUsedAmount] = [:]
        while true {
            var parts = URLComponents(string: "\(baseURL)/api/collections/user_food_usage/records")
            parts?.queryItems = [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "perPage", value: "100"), URLQueryItem(name: "sort", value: "-last_used_at")]
            guard let url = parts?.url else { return }
            var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
                let result = try JSONDecoder().decode(UsagePage.self, from: data)
                for item in result.items where item.source != "recipe" {
                    let key: String?
                    if item.source == "global_food", let id = item.foodID, !id.isEmpty { key = "global:\(id)" }
                    else if let id = item.clientItemID, UUID(uuidString: id) != nil { key = "local:\(id.lowercased())" }
                    else { key = nil }
                    guard let key, let usedAt = CalorieEntrySyncService.date(from: item.lastUsedAt) else { continue }
                    restored[key] = LastUsedAmount(
                        foodKey: key, amount: item.lastAmount, unit: FoodUnit(rawValue: item.lastUnit ?? "") ?? .gram,
                        mealKey: item.lastMeal ?? "", usedAt: usedAt, foodName: item.lastName ?? "",
                        globalFoodRecordID: item.source == "global_food" ? item.foodID : nil,
                        portionID: item.lastPortionID.flatMap(UUID.init(uuidString:)), portionCount: item.lastPortionCount
                    )
                }
                if result.page >= result.totalPages { lastUsedAmounts = restored; return }
                page += 1
            } catch { return }
        }
    }

    private func syncCurrentState(languageCode: String, settings: SyncedSettingsSnapshot? = nil) {
        guard hasHealthSyncConsentForCurrentAccount,
              let authManager, authManager.isLoggedIn, !authManager.token.isEmpty,
              let url = URL(string: "\(baseURL)/api/hyse/account-state") else { return }
        let payload = RemoteWriteState(
            termsVersion: acceptedTermsVersion,
            privacyVersion: acceptedPrivacyVersion,
            marketingConsent: marketingConsent,
            language: languageCode,
            onboardingVersion: onboardingCompletedVersion,
            settings: settings
        )
        stateSyncTask = Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authManager.token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONEncoder().encode(payload)
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                syncError = nil
            } catch {
                syncError = LanguageStore.localizedString("account_data.sync_failed")
                logger.error("Account-state upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private struct RemoteWriteState: Encodable {
        let termsVersion: String
        let privacyVersion: String
        let marketingConsent: Bool
        let language: String
        let onboardingVersion: Int
        let settings: SyncedSettingsSnapshot?
    }

    private func saveSettingsSnapshot(_ snapshot: SyncedSettingsSnapshot, scope: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: key("settings", scope: scope))
    }

    private func loadSettingsSnapshot(scope: String) -> SyncedSettingsSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key("settings", scope: scope)) else { return nil }
        return try? JSONDecoder().decode(SyncedSettingsSnapshot.self, from: data)
    }

    /// A background refresh may return after the user has just changed a
    /// preference and queued its upload. Keep that newer device value instead
    /// of briefly applying a stale server response and uploading it again.
    /// Snapshots from versions before `updatedAt` existed remain compatible:
    /// they are used only when there is no timestamped local cache.
    private func shouldApplyRemoteSettings(_ remote: SyncedSettingsSnapshot, in scope: String) -> Bool {
        guard let cached = loadSettingsSnapshot(scope: scope) else { return true }
        return remote.updatedAt >= cached.updatedAt
    }
}

extension UserSettingsStore {
    func syncSnapshot(languagePreference: LanguagePreference, mealCategories: [MealCategory]? = nil) -> SyncedSettingsSnapshot {
        SyncedSettingsSnapshot(
            baseCalorieGoal: baseCalorieGoal,
            enforceCalorieLimit: enforceCalorieLimit,
            calorieLimitBufferKilocalories: calorieLimitBufferKilocalories,
            calorieGoalMode: calorieGoalMode.rawValue,
            mealCategories: mealCategories,
            blockFoodTrackingWhileFastingEnabled: blockFoodTrackingWhileFastingEnabled,
            foodTrackingWindowEnabled: foodTrackingWindowEnabled,
            foodTrackingWindowStartMinutes: foodTrackingWindowStartMinutes,
            foodTrackingWindowEndMinutes: foodTrackingWindowEndMinutes,
            hideNutritionOutsideTrackingWindow: hideNutritionOutsideTrackingWindow,
            lockTrackingWindowSettingsOutsideHours: lockTrackingWindowSettingsOutsideHours,
            lowRemainingTrackingLockEnabled: lowRemainingTrackingLockEnabled,
            lowRemainingTrackingLockStartMinutes: lowRemainingTrackingLockStartMinutes,
            lowRemainingTrackingCaloriesThreshold: lowRemainingTrackingCaloriesThreshold,
            lowCalorieEntryWarningEnabled: lowCalorieEntryWarningEnabled,
            lowCalorieEntryWarningThreshold: lowCalorieEntryWarningThreshold,
            dynamicCalorieAdjustment: nil,
            dynamicCalorieTargetMode: dynamicCalorieTargetMode.rawValue,
            fixedCalorieSurplus: fixedCalorieSurplus,
            fixedCalorieDeficit: fixedCalorieDeficit,
            trainingDayCalorieAdjustment: trainingDayCalorieAdjustment,
            restDayCalorieAdjustment: restDayCalorieAdjustment,
            dynamicDeficitPhaseStartDate: dynamicDeficitPhaseStartDate,
            dynamicDeficitInitialBodyFatFraction: dynamicDeficitInitialBodyFatFraction,
            dynamicDeficitInitialWeightKilograms: dynamicDeficitInitialWeightKilograms,
            dynamicDeficitPhases: dynamicDeficitPhases,
            calorieGoalHistory: calorieGoalHistory,
            scheduledCaloriePhase: scheduledCaloriePhase,
            calorieDayTypes: calorieDayTypes,
            carbsPercentage: carbsPercentage,
            proteinPercentage: proteinPercentage,
            fatPercentage: fatPercentage,
            macroGoalPlan: macroGoalPlan,
            nutritionActivityLevel: nutritionActivityLevel.rawValue,
            onboardingGoal: onboardingGoal.rawValue,
            onboardingSex: onboardingSex.rawValue,
            tracking_interest: trackingInterest.rawValue,
            profileAgeYears: profileAgeYears,
            profileHeightCentimeters: profileHeightCentimeters,
            profileWeightKilograms: profileWeightKilograms,
            dailyWaterGoalMilliliters: dailyWaterGoalMilliliters,
            waterGlassSizeMilliliters: waterGlassSizeMilliliters,
            addedSugarGoalGrams: addedSugarGoalGrams,
            fruitSugarGoalGrams: fruitSugarGoalGrams,
            saltGoalGrams: saltGoalGrams,
            fiberGoalGrams: fiberGoalGrams,
            saturatedFatGoalGrams: saturatedFatGoalGrams,
            theme: appTheme.rawValue,
            defaultFoodUnit: defaultFoodUnit.rawValue,
            defaultLiquidUnit: defaultLiquidUnit.rawValue,
            trainingWeightUnit: trainingWeightUnit.rawValue,
            trainingDistanceUnit: trainingDistanceUnit.rawValue,
            count_unilateral_sets_as_half: countUnilateralSetsAsHalf,
            default_workout_gym_name: defaultWorkoutGymName,
            default_workout_gym_address: defaultWorkoutGymAddress,
            default_workout_gym_latitude: defaultWorkoutGymLatitude,
            default_workout_gym_longitude: defaultWorkoutGymLongitude,
            default_workout_visibility: defaultWorkoutVisibility,
            automatically_start_apple_watch_workout: automaticallyStartAppleWatchWorkout,
            rest_sound_enabled: restSoundEnabled,
            rest_notification_enabled: restNotificationEnabled,
            rest_haptics_enabled: restHapticsEnabled,
            rest_sound_variant: restSoundVariant.rawValue,
            rest_sound_volume: restSoundVolume,
            live_activity_enabled: liveActivityEnabled,
            motivation_notifications_enabled: motivationNotificationsEnabled,
            motivation_notification_frequency: motivationNotificationFrequency.rawValue,
            motivational_messages_enabled: motivationalMessagesEnabled,
            food_log_reminder_enabled: foodLogReminderEnabled,
            water_reminder_enabled: waterReminderEnabled,
            planned_training_reminder_enabled: plannedTrainingReminderEnabled,
            missing_daily_data_reminder_enabled: missingDailyDataReminderEnabled,
            community_news_notifications_enabled: communityNewsNotificationsEnabled,
            hyse_update_notifications_enabled: hyseUpdateNotificationsEnabled,
            workout_like_notifications_enabled: workoutLikeNotificationsEnabled,
            workout_comment_notifications_enabled: workoutCommentNotificationsEnabled,
            friend_activity_notifications_enabled: friendActivityNotificationsEnabled,
            monthly_training_report_notifications_enabled: monthlyTrainingReportNotificationsEnabled,
            visible_nutrition_metric_ids: Array(visibleNutritionMetricIDs),
            home_additional_nutrition_metric_ids: Array(homeAdditionalNutritionMetricIDs),
            selected_nutrition_profile_ids: Array(selectedNutritionProfileIDs),
            home_training_overview_visible: visibleDashboardSectionIDs.contains(DashboardSection.training.rawValue),
            home_section_order: dashboardSectionIDs,
            home_visible_section_ids: Array(visibleDashboardSectionIDs),
            language: languagePreference.rawValue
        )
    }

    func applySyncedSnapshot(_ value: SyncedSettingsSnapshot) {
        guard value.schemaVersion <= 22 else { return }
        baseCalorieGoal = value.baseCalorieGoal
        enforceCalorieLimit = value.enforceCalorieLimit
        if let buffer = value.calorieLimitBufferKilocalories, buffer >= 0 {
            calorieLimitBufferKilocalories = buffer
        }
        calorieGoalMode = CalorieGoalMode(rawValue: value.calorieGoalMode) ?? .fixed
        if let enabled = value.blockFoodTrackingWhileFastingEnabled { blockFoodTrackingWhileFastingEnabled = enabled }
        if let enabled = value.foodTrackingWindowEnabled { foodTrackingWindowEnabled = enabled }
        if let minutes = value.foodTrackingWindowStartMinutes { foodTrackingWindowStartMinutes = FoodTrackingPolicy.normalizedMinutes(minutes) }
        if let minutes = value.foodTrackingWindowEndMinutes { foodTrackingWindowEndMinutes = FoodTrackingPolicy.normalizedMinutes(minutes) }
        if let enabled = value.hideNutritionOutsideTrackingWindow { hideNutritionOutsideTrackingWindow = enabled }
        if let enabled = value.lockTrackingWindowSettingsOutsideHours { lockTrackingWindowSettingsOutsideHours = enabled }
        if let enabled = value.lowRemainingTrackingLockEnabled { lowRemainingTrackingLockEnabled = enabled }
        if let minutes = value.lowRemainingTrackingLockStartMinutes { lowRemainingTrackingLockStartMinutes = FoodTrackingPolicy.normalizedMinutes(minutes) }
        if let threshold = value.lowRemainingTrackingCaloriesThreshold, threshold >= 0 { lowRemainingTrackingCaloriesThreshold = threshold }
        if let enabled = value.lowCalorieEntryWarningEnabled { lowCalorieEntryWarningEnabled = enabled }
        if let threshold = value.lowCalorieEntryWarningThreshold, threshold > 0 { lowCalorieEntryWarningThreshold = threshold }
        dynamicCalorieTargetMode = DynamicCalorieTargetMode(rawValue: value.dynamicCalorieTargetMode ?? "")
            ?? ((value.dynamicCalorieAdjustment ?? 0) > 0 ? .surplus : .deficit)
        if let surplus = value.fixedCalorieSurplus ?? value.dynamicCalorieAdjustment, surplus > 0 {
            fixedCalorieSurplus = surplus
        }
        if let deficit = value.fixedCalorieDeficit, deficit.isFinite, deficit > 0 {
            fixedCalorieDeficit = deficit
        }
        if let adjustment = value.trainingDayCalorieAdjustment, adjustment.isFinite {
            trainingDayCalorieAdjustment = adjustment
        }
        if let adjustment = value.restDayCalorieAdjustment, adjustment.isFinite {
            restDayCalorieAdjustment = adjustment
        }
        if let phases = value.dynamicDeficitPhases, !phases.isEmpty {
            restoreDynamicDeficitPhases(phases)
        } else if let start = value.dynamicDeficitPhaseStartDate,
           let bodyFat = value.dynamicDeficitInitialBodyFatFraction,
           let weight = value.dynamicDeficitInitialWeightKilograms,
           bodyFat > 0, weight > 0 {
            restoreDynamicDeficitPhase(DynamicDeficitPhase(
                startedAt: start,
                initialBodyFatFraction: bodyFat,
                initialWeightKilograms: weight
            ))
        }
        if let history = value.calorieGoalHistory, !history.isEmpty {
            restoreCalorieGoalHistory(history)
        } else {
            restoreCalorieGoalHistory(calorieGoalHistory)
        }
        if value.schemaVersion >= 22 { setScheduledCaloriePhase(value.scheduledCaloriePhase) }
        if let dayTypes = value.calorieDayTypes {
            restoreCalorieDayTypes(dayTypes)
        }
        _ = updateMacros(carbs: value.carbsPercentage, protein: value.proteinPercentage, fat: value.fatPercentage)
        if let plan = value.macroGoalPlan { _ = updateMacroGoalPlan(plan) }
        nutritionActivityLevel = NutritionActivityLevel(rawValue: value.nutritionActivityLevel ?? "") ?? .everyday
        if let goal = value.onboardingGoal.flatMap(OnboardingGoal.init(rawValue:)) { onboardingGoal = goal }
        if let sex = value.onboardingSex.flatMap(OnboardingSex.init(rawValue:)) { onboardingSex = sex }
        if let interest = value.tracking_interest.flatMap(TrackingInterest.init(rawValue:)) { trackingInterest = interest }
        if let age = value.profileAgeYears, age >= 13 { profileAgeYears = age }
        if let height = value.profileHeightCentimeters, height > 0 { profileHeightCentimeters = height }
        if let weight = value.profileWeightKilograms, weight > 0 { profileWeightKilograms = weight }
        dailyWaterGoalMilliliters = value.dailyWaterGoalMilliliters
        waterGlassSizeMilliliters = value.waterGlassSizeMilliliters
        addedSugarGoalGrams = value.addedSugarGoalGrams
        fruitSugarGoalGrams = value.fruitSugarGoalGrams
        saltGoalGrams = value.saltGoalGrams
        fiberGoalGrams = value.fiberGoalGrams
        saturatedFatGoalGrams = value.saturatedFatGoalGrams
        appTheme = AppTheme(rawValue: value.theme) ?? .system
        let syncedFoodUnit = FoodUnit(rawValue: value.defaultFoodUnit) ?? .gram
        defaultFoodUnit = syncedFoodUnit.isVolume ? .gram : syncedFoodUnit
        defaultLiquidUnit = value.defaultLiquidUnit.flatMap(FoodUnit.init(rawValue:)).flatMap { $0.isVolume ? $0 : nil }
            ?? (syncedFoodUnit.isVolume ? syncedFoodUnit : .milliliter)
        trainingWeightUnit = TrainingWeightUnit(rawValue: value.trainingWeightUnit ?? "") ?? .kilograms
        trainingDistanceUnit = TrainingDistanceUnit(rawValue: value.trainingDistanceUnit ?? "") ?? .kilometers
        if let countAsHalf = value.count_unilateral_sets_as_half {
            countUnilateralSetsAsHalf = countAsHalf
        }
        if value.schemaVersion >= 17 {
            defaultWorkoutGymName = value.default_workout_gym_name
            defaultWorkoutGymAddress = value.default_workout_gym_address
            defaultWorkoutGymLatitude = value.default_workout_gym_latitude
            defaultWorkoutGymLongitude = value.default_workout_gym_longitude
            defaultWorkoutVisibility = value.default_workout_visibility == "public" ? "public" : "private"
        }
        if let enabled = value.automatically_start_apple_watch_workout {
            automaticallyStartAppleWatchWorkout = enabled
        }
        if let enabled = value.rest_sound_enabled { restSoundEnabled = enabled }
        if let enabled = value.rest_notification_enabled { restNotificationEnabled = enabled }
        if let enabled = value.rest_haptics_enabled { restHapticsEnabled = enabled }
        if let variant = value.rest_sound_variant.flatMap(RestSoundVariant.init(rawValue:)) { restSoundVariant = variant }
        if let volume = value.rest_sound_volume { restSoundVolume = min(max(volume, 0.1), 1) }
        if let enabled = value.live_activity_enabled { liveActivityEnabled = enabled }
        if let enabled = value.motivation_notifications_enabled { motivationNotificationsEnabled = enabled }
        if let raw = value.motivation_notification_frequency.flatMap(MotivationNotificationFrequency.init(rawValue:)) { motivationNotificationFrequency = raw }
        if let enabled = value.motivational_messages_enabled { motivationalMessagesEnabled = enabled }
        if let enabled = value.food_log_reminder_enabled { foodLogReminderEnabled = enabled }
        if let enabled = value.water_reminder_enabled { waterReminderEnabled = enabled }
        if let enabled = value.planned_training_reminder_enabled { plannedTrainingReminderEnabled = enabled }
        if let enabled = value.missing_daily_data_reminder_enabled { missingDailyDataReminderEnabled = enabled }
        if let enabled = value.community_news_notifications_enabled { communityNewsNotificationsEnabled = enabled }
        if let enabled = value.hyse_update_notifications_enabled { hyseUpdateNotificationsEnabled = enabled }
        if let enabled = value.workout_like_notifications_enabled { workoutLikeNotificationsEnabled = enabled }
        if let enabled = value.workout_comment_notifications_enabled { workoutCommentNotificationsEnabled = enabled }
        if let enabled = value.friend_activity_notifications_enabled { friendActivityNotificationsEnabled = enabled }
        if let enabled = value.monthly_training_report_notifications_enabled {
            monthlyTrainingReportNotificationsEnabled = enabled
        }
        if let metricIDs = value.visible_nutrition_metric_ids {
            let valid = Set(metricIDs).intersection(Set(NutritionMetric.allCases.map(\.rawValue)))
            if !valid.isEmpty { visibleNutritionMetricIDs = valid }
        }
        homeAdditionalNutritionMetricIDs = Set(value.home_additional_nutrition_metric_ids ?? [])
            .intersection(Set(NutritionMetric.homeAdditionalOptions.map(\.rawValue)))
        if let profileIDs = value.selected_nutrition_profile_ids {
            let valid = Set(profileIDs).intersection(Set(NutritionProfile.allCases.map(\.rawValue)))
            if !valid.isEmpty { selectedNutritionProfileIDs = valid }
        }
        if let order = value.home_section_order {
            let valid = order.filter {
                DashboardSection(rawValue: $0) != nil && $0 != DashboardSection.training.rawValue
            }
            if !valid.isEmpty {
                var complete = valid
                for section in DashboardSection.allCases where section != .training && !complete.contains(section.rawValue) {
                    complete.append(section.rawValue)
                }
                dashboardSectionIDs = complete
            }
        }
        if let visible = value.home_visible_section_ids {
            let valid = Set(visible.filter {
                DashboardSection(rawValue: $0) != nil && $0 != DashboardSection.training.rawValue
            })
            if !valid.isEmpty {
                var next = valid.union([DashboardSection.meals.rawValue])
                // Older cloud snapshots predate the steps/fasting defaults.
                // Upgrade them once, then preserve future user choices.
                if !UserDefaults.standard.bool(forKey: "wellnessDashboardCloudVisibilityMigrated_v2") {
                    next.formUnion([DashboardSection.steps.rawValue, DashboardSection.fasting.rawValue])
                    UserDefaults.standard.set(true, forKey: "wellnessDashboardCloudVisibilityMigrated_v2")
                }
                visibleDashboardSectionIDs = next
            }
        }
    }
}
