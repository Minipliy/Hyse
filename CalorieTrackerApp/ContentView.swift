import SwiftUI
import UIKit
import Combine

/// iOS 26 already supplies the system Liquid Glass tab bar. Adding another
/// material layer underneath it is expensive during tab transitions. Older
/// systems use a stable translucent surface instead of a live blur.
private struct OptimizedMainTabBarSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(HyseColor.surface.opacity(0.97), for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}

struct ContentView: View {
    private enum NutritionHomeScrollTarget: Hashable { case top }

    private struct FoodTrackingAcknowledgement: Equatable {
        let date: Date
        let restriction: FoodTrackingRestriction

        static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.date == rhs.date else { return false }
            switch (lhs.restriction, rhs.restriction) {
            case (.activeFast, .activeFast), (.calorieLimitExceeded, .calorieLimitExceeded):
                return true
            case let (.outsideAllowedWindow(lhsStart, lhsEnd), .outsideAllowedWindow(rhsStart, rhsEnd)):
                return lhsStart == rhsStart && lhsEnd == rhsEnd
            case let (.lowRemainingCalories(lhsStart, lhsThreshold, _), .lowRemainingCalories(rhsStart, rhsThreshold, _)):
                // The remaining calorie value can change while the same lock is
                // active (for example after a Health update). It must not make
                // the already acknowledged dialog appear again.
                return lhsStart == rhsStart && lhsThreshold == rhsThreshold
            default:
                return false
            }
        }
    }

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var accountData: AccountDataStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var calorieStore = CalorieStore()
    @StateObject private var foodStore = FoodStore()
    @StateObject private var recipeStore = RecipeStore()
    @StateObject private var mealPlanStore = MealPlanStore()
    @StateObject private var categoryStore = CategoryStore()
    @StateObject private var frequencyStore = FrequencyStore()
    @StateObject private var userSettings = UserSettingsStore()
    @StateObject private var waterStore = WaterStore()
    @StateObject private var trainingStore = TrainingStore()
    @StateObject private var fastingStore = FastingStore()
    @StateObject private var dailyFoodStore = DailyFoodScheduleStore()
    @StateObject private var streakRewards = StreakRewardsStore()
    @StateObject private var notificationCenter = HyseNotificationCenterStore()
    @StateObject private var communityStore = GymCommunityStore()
    @StateObject private var sharedWorkoutSocial = TrainingSocialStore()
    @State private var micronutrientRefresh = OpenFoodFactsMicronutrientRefresh()
    @State private var automaticMicronutrientEstimation = AutomaticMicronutrientEstimation()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var caloriePlanActivationReady = false
    @State private var phaseStartPrompt: ScheduledCaloriePhase?
    @State private var phasePromptWeightKilograms: Double?
    @State private var lastPhasePromptKey: String?
    @State private var nutritionHomeScrollRequestID = UUID()
    @State private var selectedMealCategory: MealCategory?
    @State private var mealBulkSelectionActive = false
    @State private var addEntryCategory: MealCategory?
    @State private var settingsNavigationResetID = UUID()
    @State private var showingCalendar = false
    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var foodAccessClock = Date()
    @State private var selectedTab = 0
    @State private var selectedTrainingSection = TrainingRootSection.friends
    @State private var tourStep = HyseTourStep.nutrition
    @State private var showingStreak = false
    @State private var showingActiveWorkout = false
    @State private var openedActiveWorkoutFromBar = false
    @State private var showingSettings = false
    @State private var showingHealthOverview = false
    @State private var showingCalorieDetails = false
    @State private var showingNotifications = false
    @State private var showingNutritionPremium = false
    @State private var showingLoginFromDeepLink = false
    @State private var sharedWorkout: FriendWorkout?
    @State private var sharedRecipe: SharedRecipe?
    @State private var sharedRoutine: SharedRoutine?
    @State private var showingAccountCreationAfterTour = false
    @State private var showNutritionPremiumAfterCalendarDismiss = false
    @State private var foodTrackingRestrictionMessage: String?
    @State private var shortcutErrorMessage: String?
    @State private var pendingShortcutURL: URL?
    @State private var acknowledgedFoodTrackingRestriction: FoodTrackingAcknowledgement?
    @State private var keyboardVisible = false
    @State private var didActivateNotificationDefaults = false
    @GestureState private var horizontalDaySwipeIsActive = false
    @State private var suppressMealNavigationAfterDaySwipe = false
    @AppStorage("health_onboarding_status_v1") private var healthOnboardingStatus = ""
    @AppStorage("profile_setup_onboarding_status_v1") private var profileSetupOnboardingStatus = ""
    @AppStorage("tracking_interest_onboarding_status_v1") private var trackingInterestOnboardingStatus = ""
    @AppStorage("first_action_completed_scope_v1") private var firstActionCompletedScope = ""

    private var firstActionScope: String {
        authManager.isLoggedIn && !authManager.accountID.isEmpty ? "account_\(authManager.accountID)" : "guest"
    }

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var showsNutritionTab: Bool { userSettings.trackingInterest.includesNutrition }
    private var showsTrainingTab: Bool { userSettings.trackingInterest.includesTraining }
    private var showsHealthTab: Bool { userSettings.trackingInterest.includesNutrition }
    private var nutritionHiddenBySchedule: Bool { userSettings.shouldHideNutrition(at: foodAccessClock) }
    private var isSingleNutritionMode: Bool { userSettings.trackingInterest == .nutrition }
    private var isSingleTrainingMode: Bool { userSettings.trackingInterest == .training }
    private var hasRestoredSignedInProfile: Bool {
        authManager.isLoggedIn
            && accountData.activeAccountID == authManager.accountID
            && accountData.hasEstablishedAccountProfile
    }
    private var availableTabIDs: Set<Int> {
        if nutritionHiddenBySchedule {
            return showsNutritionTab ? (showsTrainingTab ? [1, 3] : [3]) : [1]
        }
        if userSettings.trackingInterest == .both {
            return [0, 1, 2, 3]
        }
        return showsTrainingTab ? [1] : [0]
    }
    private var previousDay: Date { Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate }
    private var previousDayEnergy: DailyEnergy? { healthKitManager.energy(for: previousDay) }
    private var selectedDayEnergy: DailyEnergy { healthKitManager.energy(for: selectedDate) ?? DailyEnergy(date: selectedDate, resting: 0, active: 0) }
    private var calorieTarget: DynamicCalorieTargetBreakdown { userSettings.calorieTarget(for: selectedDate, previousDayEnergy: previousDayEnergy) }
    private var calorieGoal: Double { calorieTarget.targetKilocalories }
    private var isTrainingDay: Bool {
        let hasWorkout = !trainingStore.workouts(on: selectedDate).isEmpty
        let hasPlannedRoutine = !trainingStore.routines(plannedFor: selectedDate).isEmpty
        return hasWorkout || userSettings.trainingDayStatus(for: selectedDate, currentlyTraining: hasPlannedRoutine)
    }
    private func recordSelectedDayType() {
        guard userSettings.recordTrainingDayStatus(for: selectedDate, isTrainingDay: isTrainingDay) else { return }
        accountData.stageSettings(userSettings, language: language)
        if accountData.hasEstablishedAccountProfile && !accountData.isHydratingAccountSettings {
            accountData.syncSettings(userSettings, language: language)
        }
    }
    private var dayTypeAdjustment: Double {
        userSettings.dayTypeAdjustment(for: selectedDate, isTrainingDay: isTrainingDay)
    }
    private var dynamicActiveEnergyAdjustment: Double {
        userSettings.calorieGoalConfiguration(for: selectedDate).mode == .dynamic ? selectedDayEnergy.active : 0
    }
    private var rawAvailableCalories: Double {
        calorieGoal + dynamicActiveEnergyAdjustment + dayTypeAdjustment
    }
    private var availableCalories: Double {
        userSettings.availableCalories(
            for: selectedDate,
            targetKilocalories: calorieGoal,
            activeEnergy: selectedDayEnergy.active,
            isTrainingDay: isTrainingDay
        )
    }
    private var totalKcal: Double { calorieStore.totalKcal(for: selectedDate) }
    private var calendarActivityDays: [Date] {
        let calendar = Calendar.current
        let nutritionDays = calorieStore.activeDays.map { calendar.startOfDay(for: $0) }
        let workoutDays = trainingStore.completedWorkouts.map { calendar.startOfDay(for: $0.completedAt ?? $0.startedAt) }
        return Array(Set(nutritionDays + workoutDays)).sorted(by: >)
    }

    // Zugesetzter Zucker: 10% der verfügbaren Kalorien (WHO-Richtwert für "freien"/zugesetzten Zucker)
    private var addedSugarTarget: Double { userSettings.addedSugarGoalGrams }
    private var saturatedFatTarget: Double { userSettings.saturatedFatGoalGrams }
    private var saltTarget: Double { userSettings.saltGoalGrams }
    private var fiberTarget: Double { userSettings.fiberGoalGrams }

    private var todayWaterAmount: Double { waterStore.amount(for: Date()) }

    private var notificationContext: MotivationNotificationContext {
        let calendar = Calendar.autoupdatingCurrent
        let today = Date()
        let plannedTrainings = (0..<14).flatMap { offset -> [PlannedTrainingNotification] in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            let alreadyCompleted = !trainingStore.workouts(on: date).isEmpty
            guard !alreadyCompleted else { return [] }
            return trainingStore.routines(plannedFor: date).map {
                PlannedTrainingNotification(date: date, title: $0.name)
            }
        }
        return MotivationNotificationContext(
            hasFoodToday: !calorieStore.entriesForToday().isEmpty,
            waterAmountMilliliters: waterStore.amount(for: today),
            waterGoalMilliliters: userSettings.dailyWaterGoalMilliliters,
            plannedTrainings: plannedTrainings
        )
    }

    private var notificationPreferencesSignature: String {
        [
            String(userSettings.motivationNotificationsEnabled),
            userSettings.motivationNotificationFrequency.rawValue,
            String(userSettings.motivationalMessagesEnabled),
            String(userSettings.foodLogReminderEnabled),
            String(userSettings.waterReminderEnabled),
            String(userSettings.plannedTrainingReminderEnabled),
            String(userSettings.missingDailyDataReminderEnabled)
        ].joined(separator: "|")
    }

    private var notificationDataSignature: String {
        [
            notificationPreferencesSignature,
            calorieStore.entries.map(\.id.uuidString).joined(separator: ","),
            String(format: "%.0f", todayWaterAmount),
            trainingStore.completedWorkouts.map(\.id.uuidString).joined(separator: ","),
            trainingStore.routines.map { "\($0.id)|\($0.plannedWeekday ?? 0)|\($0.name)" }.joined(separator: ","),
            language.language.rawValue
        ].joined(separator: "|")
    }

    private func refreshNotificationSchedule() {
        let configuration = userSettings.motivationNotificationConfiguration
        guard configuration.enabled else { return }
        let context = notificationContext
        Task { @MainActor in
            _ = await MotivationNotificationManager.shared.setEnabled(
                configuration,
                language: language.language,
                context: context
            )
        }
    }

    private var accountContent: some View {
        Group {
            if !accountData.hasRequiredConsent {
                LegalConsentView()
            } else if authManager.isLoggedIn &&
                        (!accountData.hasHealthSyncConsentForCurrentAccount || userSettings.profileAgeYears < 16) {
                AccountHealthSyncConsentView()
            } else if authManager.isLoggedIn &&
                        (accountData.activeAccountID != authManager.accountID || accountData.isHydratingAccountSettings) {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authManager.isLoggedIn && accountData.accountSettingsLoadFailed && !hasRestoredSignedInProfile {
                HyseEmptyState(
                    icon: "icloud.slash",
                    title: t("settings.syncing_account_settings"),
                    message: t("login.could_not_reach_server_check_internet_connection"),
                    actionTitle: t("content.retry"),
                    action: {
                        Task { await accountData.refreshAccountState(settingsStore: userSettings, language: language) }
                    }
                )
            } else if trackingInterestOnboardingStatus != "completed" && !hasRestoredSignedInProfile {
                TrackingInterestOnboardingView(settings: userSettings) {
                    trackingInterestOnboardingStatus = "completed"
                }
            } else if userSettings.profileAgeYears < 16 {
                ProfileSetupOnboardingView(settings: userSettings, trainingStore: trainingStore) {
                    profileSetupOnboardingStatus = "completed"
                }
            } else if !accountData.hasCompletedOnboarding && firstActionCompletedScope != firstActionScope {
                FirstActionOnboardingView(
                    interest: userSettings.trackingInterest,
                    logFood: { finishFirstAction(.food) },
                    startWorkout: { finishFirstAction(.training) },
                    explore: { finishFirstAction(.explore) }
                )
            } else if profileSetupOnboardingStatus != "completed" && profileSetupOnboardingStatus != "deferred" && !hasRestoredSignedInProfile {
                ProfileSetupOnboardingView(settings: userSettings, trainingStore: trainingStore) {
                    profileSetupOnboardingStatus = "completed"
                }
            } else if healthOnboardingStatus == "pending" {
                HealthConnectionOnboardingView(healthKitManager: healthKitManager) {
                    healthOnboardingStatus = "completed"
                }
            } else {
                mainContent
            }
        }
    }

    private enum FirstActionChoice { case food, training, explore }

    private func finishFirstAction(_ choice: FirstActionChoice) {
        firstActionCompletedScope = firstActionScope
        if profileSetupOnboardingStatus != "completed" { profileSetupOnboardingStatus = "deferred" }
        if healthOnboardingStatus == "pending" { healthOnboardingStatus = "deferred" }
        accountData.completeOnboarding(skipped: true)
        switch choice {
        case .food:
            selectedTab = 0
            DispatchQueue.main.async { presentAddEntry() }
        case .training:
            selectedTab = 1
            selectedTrainingSection = .training
            _ = trainingStore.startEmptyWorkout()
            DispatchQueue.main.async { showingActiveWorkout = true }
        case .explore:
            break
        }
    }

    private var presentedContent: some View {
        accountContent
        .environmentObject(userSettings)
        .environmentObject(notificationCenter)
        .environmentObject(communityStore)
        .environmentObject(trainingStore)
        .environmentObject(streakRewards)
        .task(id: "\(authManager.isLoggedIn)|\(authManager.accountID)") {
            communityStore.activate(auth: authManager)
            await premium.updateAccount(authManager)
        }
        .environmentObject(dailyFoodStore)
        .environmentObject(mealPlanStore)
        .environmentObject(categoryStore)
        .environmentObject(calorieStore)
        .environmentObject(frequencyStore)
        .sheet(isPresented: $showingNotifications) {
            HyseNotificationCenterView()
                .environmentObject(language)
                .environmentObject(authManager)
                .environmentObject(notificationCenter)
                .environmentObject(communityStore)
                .environmentObject(trainingStore)
        }
        .sheet(isPresented: $showingNutritionPremium, onDismiss: restoreTodayAfterDismissedNutritionPaywall) {
            PremiumPaywallView(requestedArea: .nutrition)
        }
        .sheet(isPresented: $showingLoginFromDeepLink) {
            LoginView()
                .environmentObject(authManager)
        }
        .sheet(item: $sharedWorkout) { workout in
            NavigationStack {
                FriendWorkoutDetailView(
                    social: sharedWorkoutSocial,
                    store: trainingStore,
                    workout: workout
                )
            }
        }
        .sheet(item: $sharedRecipe) { recipe in
            NavigationStack { SharedRecipeDetailView(recipe: recipe) }
        }
        .sheet(item: $sharedRoutine) { routine in
            NavigationStack { SharedRoutineDetailView(routine: routine) }
                .environmentObject(trainingStore)
                .environmentObject(premium)
        }
        .sheet(item: $phaseStartPrompt) { plan in
            ScheduledCaloriePhaseStartView(plan: plan, latestWeightKilograms: phasePromptWeightKilograms) { bodyFat, enteredWeight in
                completePlannedCaloriePhaseStart(planID: plan.id, bodyFatPercentage: bodyFat, enteredWeightKilograms: enteredWeight)
            }
            .environmentObject(language)
        }
        .sheet(isPresented: $showingAccountCreationAfterTour) {
            LoginView(startsInRegistration: true)
                .environmentObject(authManager)
        }
        .preferredColorScheme(userSettings.appTheme.colorScheme)
        .hyseAlert(isPresented: Binding(
            get: { foodTrackingRestrictionMessage != nil },
            set: {
                guard !$0 else { return }
                acknowledgeFoodTrackingRestriction()
                foodTrackingRestrictionMessage = nil
            }
        ), title: t("food_tracking.locked_home_title"), message: foodTrackingRestrictionMessage ?? "", icon: "fork.knife.circle.fill", tint: HyseColor.warning, buttonTitle: t("food_tracking.locked_acknowledge"))
    }

    var body: some View {
        appLifecycleContent
    }

    private var appLifecycleContent: some View {
        appSetupContent
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
            foodAccessClock = now
            activatePlannedCaloriePhase(now: now)
            if waterStore.refreshFromSharedStorage() {
                healthKitManager.syncWaterIntake(totalMilliliters: waterStore.amount(for: now), date: now)
            }
            guard premium.hasNutrition else { return }
            dailyFoodStore.reconcileToday(calorieStore: calorieStore, categories: categoryStore.categories, now: now)
            scheduleMicronutrientRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hyseExternalWaterChanged)) { _ in
            let now = Date()
            if waterStore.refreshFromSharedStorage() {
                healthKitManager.syncWaterIntake(totalMilliliters: waterStore.amount(for: now), date: now)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onChange(of: foodStore.foods) { _, _ in
            if foodStore.micronutrientScopeID == calorieStore.micronutrientScopeID {
                calorieStore.refreshMicronutrients(from: foodStore.availableFoods)
            }
            scheduleMicronutrientRefresh()
        }
        .onChange(of: foodStore.globalFoods) { _, _ in
            if foodStore.micronutrientScopeID == calorieStore.micronutrientScopeID {
                calorieStore.refreshMicronutrients(from: foodStore.availableFoods)
            }
            scheduleMicronutrientRefresh()
        }
        .onReceive(calorieStore.$entries) { _ in scheduleMicronutrientRefresh() }
        .onChange(of: trainingStore.bodyMeasurements) { _, _ in activatePlannedCaloriePhase() }
        .onChange(of: healthKitManager.bodyWeights) { _, _ in activatePlannedCaloriePhase() }
        .onChange(of: healthKitManager.dietaryPermissionRevision) { _, _ in
            healthKitManager.backfillDietaryMicronutrients(entries: calorieStore.entries, scopeID: calorieStore.micronutrientScopeID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hyseFoodEntriesAdded)) { notification in
            guard let added = notification.object as? [CalorieEntry] else { return }
            scheduleAutomaticMicronutrients(for: added)
        }
        .onOpenURL(perform: handleDeepLink)
        .onChange(of: trainingStore.hasResolvedPersistenceScope) { _, ready in
            guard ready, let url = pendingShortcutURL else { return }
            pendingShortcutURL = nil
            handleDeepLink(url)
        }
        .onChange(of: accountData.hasCompletedOnboarding) { _, completed in
            if !completed {
                tourStep = .nutrition
                configureTour(for: .nutrition)
            } else {
                firstActionCompletedScope = firstActionScope
            }
        }
        .onAppear {
            if accountData.hasCompletedOnboarding { firstActionCompletedScope = firstActionScope }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            foodAccessClock = Date()
            activatePlannedCaloriePhase()
            if waterStore.refreshFromSharedStorage() {
                healthKitManager.syncWaterIntake(totalMilliliters: waterStore.amount(for: Date()), date: Date())
            }
            communityStore.activate(auth: authManager)
            Task {
                await premium.updateAccount(authManager)
                await premium.refresh()
            }
            Task { await accountData.refreshAccountState(settingsStore: userSettings, language: language) }
            scheduleMicronutrientRefresh()
            scheduleAutomaticMicronutrients(for: calorieStore.entries(for: Date()))
            dailyFoodStore.syncPendingSchedules()
            streakRewards.syncPendingState()
            showFoodTrackingRestrictionIfNeeded()
        }
    }

    private var appSetupContent: some View {
        appSetupStateContent
        .onChange(of: accountData.cloudSyncConsent) { _, _ in
            applyAccountMode()
        }
        .onChange(of: userSettings.profileAgeYears) { _, _ in
            applyAccountMode()
        }
        .onChange(of: accountData.serverStreakDays) { _, days in
            calorieStore.applyServerStreakDays(days)
            refreshStreakRewards()
        }
        .onChange(of: calorieStore.streakActivityDayKeys) { _, _ in refreshStreakRewards() }
        .onChange(of: trainingStore.completedWorkouts.map(\.id)) { _, _ in refreshStreakRewards() }
        .onChange(of: trainingStore.completedWorkouts) { _, _ in
            refreshTodayWidgetGoals()
            Task { await notificationCenter.load(auth: authManager, trainingStore: trainingStore) }
        }
        .onChange(of: trainingStore.activeWorkout?.id) { _, _ in refreshTodayWidgetGoals() }
        .onChange(of: healthKitManager.energy(for: Date())?.active) { _, _ in refreshTodayWidgetGoals() }
        .onChange(of: streakRewards.nutritionFrozenDayKeys) { _, days in calorieStore.applyStreakFreezeDays(days) }
        .onChange(of: streakRewards.trainingFrozenWeekKeys) { _, weeks in trainingStore.applyStreakFreezeWeeks(weeks) }
        .onChange(of: fastingStore.isFasting) { _, isFasting in
            if !isFasting { applyDailyFoodSchedules() }
        }
    }

    private var appSetupStateContent: some View {
        appSetupBaseContent
        .onChange(of: authManager.isLoggedIn) { _, _ in
            applyAccountMode()
            Task {
                await premium.updateAccount(authManager)
                await premium.refresh()
            }
        }
        .onChange(of: premium.hasTraining) { _, unlocked in
            trainingStore.premiumTrainingUnlocked = unlocked
        }
        .onChange(of: premium.hasNutrition) { _, unlocked in
            userSettings.setDayTypeCalorieAdjustmentsEnabled(unlocked)
            userSettings.setAdvancedMacroGoalsEnabled(unlocked)
            if unlocked {
                applyDailyFoodSchedules()
                scheduleMicronutrientRefresh()
                scheduleAutomaticMicronutrients(for: calorieStore.entries(for: Date()))
            }
        }
        .onChange(of: selectedDate) { _, date in
            handleSelectedNutritionDateChange(date)
        }
    }

    private var appSetupBaseContent: some View {
        presentedContent
        .onAppear {
            accountData.attach(authManager)
            accountData.attachCategoryStore(categoryStore, settingsStore: userSettings, language: language)
            caloriePlanActivationReady = true
            activatePlannedCaloriePhase()
            calorieStore.userSettings = userSettings
            calorieStore.fastingStore = fastingStore
            calorieStore.trainingStore = trainingStore
            frequencyStore.attach(authManager)
            trainingStore.attach(authManager)
            trainingStore.premiumTrainingUnlocked = premium.hasTraining
            userSettings.setDayTypeCalorieAdjustmentsEnabled(premium.hasNutrition)
            userSettings.setAdvancedMacroGoalsEnabled(premium.hasNutrition)
            recipeStore.attach(authManager)
            calorieStore.attachCategoryStore(categoryStore)
            PhoneWatchConnectivityService.shared.configure(
                calorieStore: calorieStore,
                categoryStore: categoryStore,
                trainingStore: trainingStore,
                settingsStore: userSettings
            )
            calorieStore.healthKitManager = healthKitManager
            calorieStore.authManager = authManager
            foodStore.authManager = authManager
            if healthOnboardingStatus.isEmpty {
                healthOnboardingStatus = accountData.hasRequiredConsent ? "completed_existing_install" : "pending"
            }
            applyAccountMode()
            scheduleMicronutrientRefresh()
            scheduleAutomaticMicronutrients(for: calorieStore.entries(for: Date()))
            showFoodTrackingRestrictionIfNeeded()
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { if availableTabIDs.contains($0) { selectedTab = $0 } }
        )
    }

    private func ensureSelectedTabIsAvailable() {
        guard !availableTabIDs.contains(selectedTab) else { return }
        if nutritionHiddenBySchedule {
            selectedTab = showsTrainingTab ? 1 : 3
            return
        }
        if showsTrainingTab {
            selectedTab = 1
        } else if showsNutritionTab {
            selectedTab = 0
        } else {
            selectedTab = 3
        }
    }

    private func handleDeepLink(_ url: URL) {
        if url.scheme == "hyseapp", url.host == "login" {
            if !authManager.isLoggedIn { showingLoginFromDeepLink = true }
            return
        }
        if url.scheme == "hyseapp", ["food", "training"].contains(url.host ?? ""),
           !trainingStore.hasResolvedPersistenceScope {
            pendingShortcutURL = url
            return
        }
        if url.scheme == "hyseapp", url.host == "food" {
            guard showsNutritionTab, !nutritionHiddenBySchedule else { return }
            selectedTab = 0
            selectedDate = Calendar.current.startOfDay(for: Date())
            presentAddEntry()
            return
        }
        if let recipeID = RecipeShareLink.recipeID(from: url) {
            guard !nutritionHiddenBySchedule else { return }
            if showsNutritionTab { selectedTab = 0 }
            Task {
                if let recipe = try? await RecipeShareService.shared.fetch(id: recipeID) {
                    sharedRecipe = recipe
                }
            }
            return
        }
        if let routineID = RoutineShareLink.routineID(from: url) {
            if showsTrainingTab { selectedTab = 1 }
            Task {
                if let routine = try? await RoutineShareService.shared.fetch(id: routineID) {
                    sharedRoutine = routine
                }
            }
            return
        }
        if let workoutID = WorkoutShareLink.workoutID(from: url) {
            selectedTrainingSection = .friends
            if showsTrainingTab { selectedTab = 1 }
            Task {
                if let workout = await sharedWorkoutSocial.loadDetail(id: workoutID, auth: authManager, force: true) {
                    sharedWorkout = workout
                }
            }
            return
        }
        guard url.scheme == "hyseapp", url.host == "training" else { return }
        guard showsTrainingTab else { return }
        selectedTab = 1
        selectedTrainingSection = .training
        if url.path == "/start" {
            let requestedRoutine = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "routine" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if requestedRoutine.isEmpty {
                _ = trainingStore.startEmptyWorkout()
            } else if let routine = trainingStore.routines.first(where: {
                $0.name.compare(requestedRoutine, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                _ = trainingStore.start(routine: routine)
            } else {
                shortcutErrorMessage = t("shortcut.routine.not_found", requestedRoutine)
            }
        }
        if trainingStore.activeWorkout != nil {
            showingActiveWorkout = true
        }
    }

    private var mainContentTabs: some View {
        Group {
            if userSettings.trackingInterest == .both {
                // Keep the large page types out of TabView's generic tuple. On iOS 27
                // their combined type metadata overflows the stack during launch.
                TabView(selection: tabSelection) {
                if !nutritionHiddenBySchedule {
                AnyView(mainTabPage(homeView))
                    .tabItem { Label(t("app_tabs.nutrition"), systemImage: "fork.knife") }
                    .tag(0)
                }
                AnyView(TrainingRootView(
                    store: trainingStore,
                    selectedSection: $selectedTrainingSection,
                    isActive: selectedTab == 1,
                    showsActiveWorkoutBar: !keyboardVisible,
                    openSettings: nil
                ))
                    .tabItem { Label(t("training.title"), systemImage: "figure.strengthtraining.traditional") }
                    .tag(1)
                if !nutritionHiddenBySchedule {
                    AnyView(mainTabPage(HealthOverviewView(trainingStore: trainingStore, settings: userSettings, health: healthKitManager, isActive: selectedTab == 2)))
                        .tabItem { Label(t("health.overview.title"), systemImage: "heart.text.square.fill") }
                        .tag(2)
                }
                AnyView(mainTabPage(settingsPage))
                    .tabItem { Label(t("content.settings"), systemImage: "gearshape.fill") }
                    .tag(3)
                }
            } else if isSingleTrainingMode {
                AnyView(TrainingRootView(
                    store: trainingStore,
                    selectedSection: $selectedTrainingSection,
                    isActive: true,
                    showsActiveWorkoutBar: !keyboardVisible,
                    openSettings: { showingSettings = true }
                ))
            } else if nutritionHiddenBySchedule {
                AnyView(mainTabPage(settingsPage))
            } else {
                AnyView(mainTabPage(homeView))
            }
        }
        .tint(HyseColor.accent)
        .toolbar(userSettings.trackingInterest == .both ? .visible : .hidden, for: .tabBar)
        .modifier(OptimizedMainTabBarSurface())
        .overlay(alignment: .top) {
            if let reward = streakRewards.lastReward {
                HStack(spacing: HyseSpacing.small) {
                    Image(systemName: "snowflake")
                        .font(.headline.bold())
                    Text(t(reward.source == .nutrition ? "streak_rewards.earned_food" : "streak_rewards.earned_training", reward.amount))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, HyseSpacing.large)
                .frame(minHeight: 46)
                .hyseGlassSurface(radius: 18, tint: HyseColor.accent)
                .padding(.top, HyseSpacing.small)
                .onTapGesture { streakRewards.clearLastReward() }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .animation(.snappy(duration: 0.25), value: streakRewards.lastReward?.id)
    }

    private var mainContentPresented: some View {
        mainContentTabs
        .onAppear { ensureSelectedTabIsAvailable() }
        .onChange(of: userSettings.trackingInterest) { _, _ in ensureSelectedTabIsAvailable() }
        .onChange(of: nutritionHiddenBySchedule) { _, hidden in
            if hidden {
                addEntryCategory = nil
                showingHealthOverview = false
                showingCalorieDetails = false
                sharedRecipe = nil
            }
            ensureSelectedTabIsAvailable()
        }
        .fullScreenCover(isPresented: $showingActiveWorkout, onDismiss: { openedActiveWorkoutFromBar = false }) {
            ActiveWorkoutView(store: trainingStore, animateToLatestCompletedExercise: openedActiveWorkoutFromBar)
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            lastPhasePromptKey = nil
            activatePlannedCaloriePhase()
        }) { settingsPage }
        .sheet(isPresented: $showingHealthOverview) { healthOverviewPage }
        .sheet(item: $addEntryCategory) { category in
            AddEntryView(
                foodStore: foodStore,
                recipeStore: recipeStore,
                categoryStore: categoryStore,
                frequencyStore: frequencyStore,
                userSettings: userSettings,
                calorieStore: calorieStore,
                availableCalories: availableCalories,
                category: category,
                entryDate: selectedDate
            )
        }
        .hyseAlert(
            isPresented: Binding(get: { shortcutErrorMessage != nil }, set: { if !$0 { shortcutErrorMessage = nil } }),
            title: t("shortcut.routine.not_found_title"),
            message: shortcutErrorMessage ?? "",
            buttonTitle: t("common.ok")
        )
    }

    private var mainContentLifecycle: some View {
        mainContentPresented
        .onAppear {
            recordSelectedDayType()
            calorieStore.refreshWidget(immediately: true)
            refreshTodayWidgetGoals()
            guard !didActivateNotificationDefaults else { return }
            didActivateNotificationDefaults = true
            refreshNotificationSchedule()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hyseRemoteNotificationReceived)) { notification in
            handleRemoteNotification(notification)
        }
        .onChange(of: calorieStore.totalKcalToday) { _, _ in
            calorieStore.refreshWidget()
            refreshNotificationSchedule()
        }
    }

    private var mainContentEvents: some View {
        mainContentLifecycle
        .onChange(of: notificationDataSignature) { _, _ in refreshNotificationSchedule() }
        .onChange(of: availableCalories) { _, value in
            if isToday { userSettings.updateWidgetAvailableCalories(value) }
        }
        .onChange(of: userSettings.carbsPercentage) { _, _ in refreshWidgetMacroGoals() }
        .onChange(of: userSettings.proteinPercentage) { _, _ in refreshWidgetMacroGoals() }
        .onChange(of: userSettings.fatPercentage) { _, _ in refreshWidgetMacroGoals() }
        .onChange(of: userSettings.macroGoalPlan) { _, _ in refreshWidgetMacroGoals() }
        .onChange(of: userSettings.advancedMacroGoalsEnabled) { _, _ in refreshWidgetMacroGoals() }
        .onChange(of: selectedDate) { _, _ in recordSelectedDayType() }
        .onChange(of: isTrainingDay) { _, _ in recordSelectedDayType() }
        .onChange(of: userSettings.calorieDayTypes) { _, _ in recordSelectedDayType() }
        .onChange(of: userSettings.liveActivityEnabled) { _, _ in trainingStore.preferencesDidChange() }
        .onChange(of: userSettings.restNotificationEnabled) { _, enabled in
            if !enabled { RestTimerNotificationController.shared.cancel() }
            trainingStore.preferencesDidChange()
        }
        .onChange(of: userSettings.restSoundEnabled) { _, _ in trainingStore.preferencesDidChange() }
        .onChange(of: userSettings.trainingWeightUnit) { _, _ in trainingStore.preferencesDidChange() }
    }

    private func refreshWidgetMacroGoals() {
        refreshTodayWidgetGoals()
    }

    private func refreshTodayWidgetGoals() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let goal = userSettings.calorieTarget(
            for: today,
            previousDayEnergy: healthKitManager.energy(for: yesterday)
        ).targetKilocalories
        let activeEnergy = healthKitManager.energy(for: today)?.active ?? 0
        let hasWorkout = !trainingStore.workouts(on: today).isEmpty
        let plannedRoutine = !trainingStore.routines(plannedFor: today).isEmpty
        let trainingDay = hasWorkout || userSettings.trainingDayStatus(for: today, currentlyTraining: plannedRoutine)
        let available = userSettings.availableCalories(
            for: today,
            targetKilocalories: goal,
            activeEnergy: activeEnergy,
            isTrainingDay: trainingDay
        )
        userSettings.updateWidgetAvailableCalories(available)
    }

    private func handleRemoteNotification(_ notification: Notification) {
        guard authManager.isLoggedIn else { return }
        Task { await notificationCenter.load(auth: authManager, trainingStore: trainingStore, force: true) }
        if notification.userInfo?["hyse_open_notification_center"] as? Bool == true {
            if let userInfo = notification.userInfo {
                notificationCenter.requestOpen(userInfo: userInfo)
            }
            showingNotifications = true
        }
    }

    private var mainContent: some View {
        mainContentEvents
        .overlayPreferenceValue(HyseTourTargetPreferenceKey.self) { targets in
            GeometryReader { proxy in
                if !accountData.hasCompletedOnboarding {
                    HyseGuidedTourOverlay(
                        step: tourStep,
                        goBack: previousTourStep,
                        goForward: nextTourStep,
                        skip: { accountData.completeOnboarding(skipped: true) },
                        resolvedTarget: targets[tourStep].map { proxy[$0] }
                    )
                    .environmentObject(language)
                }
            }
            // TabView lays regular overlays out above the bottom safe area,
            // while its system tab bar extends into that area. Give the tour
            // one full-screen coordinate space so tab targets aren't clipped
            // or shifted upward.
            .ignoresSafeArea()
        }
        .onAppear {
            if !accountData.hasCompletedOnboarding { configureTour(for: tourStep) }
        }
    }

    private var settingsPage: some View {
        NavigationStack {
            SettingsView(
                settingsStore: userSettings,
                categoryStore: categoryStore,
                foodStore: foodStore,
                calorieStore: calorieStore,
                recipeStore: recipeStore,
                frequencyStore: frequencyStore,
                healthKitManager: healthKitManager
            )
        }
        .id(settingsNavigationResetID)
    }

    private var healthOverviewPage: some View {
        NavigationStack {
            HealthOverviewView(
                trainingStore: trainingStore,
                settings: userSettings,
                health: healthKitManager,
                isActive: true
            )
        }
    }

    private func nextTourStep() {
        guard let next = HyseTourStep(rawValue: tourStep.rawValue + 1) else {
            completeTourAndPresentAccountCreation()
            return
        }
        tourStep = next
        configureTour(for: next)
    }

    private func completeTourAndPresentAccountCreation() {
        accountData.completeOnboarding()
        guard !authManager.isLoggedIn else { return }

        // Wait for the overlay to leave the hierarchy before presenting the
        // registration sheet. This avoids competing modal transitions.
        DispatchQueue.main.async {
            showingAccountCreationAfterTour = true
        }
    }

    private func previousTourStep() {
        guard let previous = HyseTourStep(rawValue: tourStep.rawValue - 1) else { return }
        tourStep = previous
        configureTour(for: previous)
    }

    private func configureTour(for step: HyseTourStep) {
        addEntryCategory = nil
        switch step {
        case .nutrition, .meals:
            selectedTab = showsNutritionTab ? 0 : 1
        case .health:
            selectedTab = showsHealthTab ? 2 : (showsTrainingTab ? 1 : 3)
        case .trainingFriends:
            selectedTab = showsTrainingTab ? 1 : 0
            selectedTrainingSection = .friends
        case .trainingWorkouts:
            selectedTab = showsTrainingTab ? 1 : 0
            selectedTrainingSection = .training
        case .trainingProfile:
            selectedTab = showsTrainingTab ? 1 : 0
            selectedTrainingSection = .profile
        case .trainingStart:
            selectedTab = showsTrainingTab ? 1 : 0
            selectedTrainingSection = .training
        case .settings:
            selectedTab = 3
            // Settings uses nested SettingsView destinations. Recreate the
            // root stack so replaying the tutorial cannot leave it on a
            // previously opened privacy/legal detail page.
            settingsNavigationResetID = UUID()
        }
    }

    private func presentAddEntry() {
        guard !nutritionHiddenBySchedule else { return }
        guard addEntryCategory == nil, let category = categoryStore.categories.first else { return }
        if Calendar.current.startOfDay(for: selectedDate) > Calendar.current.startOfDay(for: Date()), !premium.hasNutrition {
            showingNutritionPremium = true
            return
        }
        if let restriction = calorieStore.trackingRestriction(for: selectedDate) {
            foodTrackingRestrictionMessage = restriction.message(using: language)
            return
        }
        addEntryCategory = category
    }

    private func showFoodTrackingRestrictionIfNeeded() {
        guard accountData.hasRequiredConsent, healthOnboardingStatus != "pending" else { return }
        guard let restriction = calorieStore.trackingRestriction(for: selectedDate) else {
            acknowledgedFoodTrackingRestriction = nil
            return
        }
        guard foodTrackingRestrictionMessage == nil else { return }
        let acknowledgement = FoodTrackingAcknowledgement(
            date: Calendar.current.startOfDay(for: selectedDate),
            restriction: restriction
        )
        guard acknowledgedFoodTrackingRestriction != acknowledgement else { return }
        foodTrackingRestrictionMessage = restriction.message(using: language)
    }

    private func acknowledgeFoodTrackingRestriction() {
        guard let restriction = calorieStore.trackingRestriction(for: selectedDate) else { return }
        acknowledgedFoodTrackingRestriction = FoodTrackingAcknowledgement(
            date: Calendar.current.startOfDay(for: selectedDate),
            restriction: restriction
        )
    }

    private func foodTrackingLockedBanner(_ restriction: FoodTrackingRestriction) -> some View {
        HyseCard(accent: HyseColor.warning) {
            HStack(alignment: .top, spacing: HyseSpacing.large) {
                ZStack {
                    Circle()
                        .fill(HyseColor.warning.opacity(0.16))
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(HyseColor.warning)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "lock.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(HyseColor.warning, in: Circle())
                                .offset(x: 6, y: 6)
                        }
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: HyseSpacing.small) {
                    Text(t("food_tracking.locked_home_title"))
                        .font(.title2.bold())
                        .foregroundStyle(HyseColor.warning)
                    Text(t("food_tracking.locked_home_subtitle"))
                        .font(.headline)
                    Text(restriction.message(using: language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, HyseSpacing.small)
            .accessibilityElement(children: .combine)
        }
    }

    private func applyAccountMode() {
        calorieStore.authManager = authManager
        foodStore.authManager = authManager
        dailyFoodStore.authManager = authManager
        streakRewards.authManager = authManager

        if authManager.isLoggedIn && accountData.hasRequiredConsent &&
            accountData.hasHealthSyncConsentForCurrentAccount && userSettings.profileAgeYears >= 16 {
            accountData.activateAccount(settingsStore: userSettings, language: language)
            frequencyStore.activateAccount()
            trainingStore.activateAccount()
            recipeStore.activateAccount()
            calorieStore.activateAccount()
            foodStore.activateAccount()
        } else {
            accountData.deactivateAccount()
            frequencyStore.deactivateAccount()
            trainingStore.deactivateAccount()
            recipeStore.deactivateAccount()
            calorieStore.deactivateAccount()
            foodStore.deactivateAccount()
        }
        streakRewards.activate(accountID: authManager.isLoggedIn && !authManager.accountID.isEmpty ? authManager.accountID : nil)
        if authManager.isLoggedIn {
            let pushEnabled = userSettings.communityNewsNotificationsEnabled
                || userSettings.workoutLikeNotificationsEnabled
                || userSettings.workoutCommentNotificationsEnabled
                || userSettings.friendActivityNotificationsEnabled
            CommunityPushNotificationManager.shared.syncIfEnabled(pushEnabled, auth: authManager)
            Task {
                await HyseNotificationService.shared.updatePreferences(settings: userSettings, token: authManager.token)
                await notificationCenter.load(auth: authManager, trainingStore: trainingStore, force: true)
            }
        } else {
            Task {
                await notificationCenter.load(auth: authManager, trainingStore: trainingStore, force: true)
            }
        }
        dailyFoodStore.activate(accountID: authManager.isLoggedIn && accountData.hasRequiredConsent && accountData.hasHealthSyncConsentForCurrentAccount && userSettings.profileAgeYears >= 16 ? authManager.accountID : nil)
        mealPlanStore.activate(accountID: authManager.isLoggedIn && accountData.hasRequiredConsent && accountData.hasHealthSyncConsentForCurrentAccount && userSettings.profileAgeYears >= 16 ? authManager.accountID : nil)
        if foodStore.micronutrientScopeID == calorieStore.micronutrientScopeID {
            calorieStore.refreshMicronutrients(from: foodStore.availableFoods)
        }
        if !healthKitManager.requestMissingMicronutrientAuthorization() {
            healthKitManager.backfillDietaryMicronutrients(entries: calorieStore.entries, scopeID: calorieStore.micronutrientScopeID)
        }
        applyDailyFoodSchedules()
        refreshStreakRewards()
    }

    private func activatePlannedCaloriePhase(now: Date = Date()) {
        guard caloriePlanActivationReady, let plan = userSettings.scheduledCaloriePhase else { return }
        let latestWeight = latestPlannedWeight(now: now)
        guard plan.isDue(now: now, latestWeightKilograms: latestWeight) else { return }
        if plan.goalMode == .dynamic && plan.dynamicMode == .deficit {
            let day = Calendar.current.startOfDay(for: now).timeIntervalSince1970
            let promptKey = "\(plan.id.uuidString)|\(day)"
            if lastPhasePromptKey != promptKey && phaseStartPrompt == nil {
                lastPhasePromptKey = promptKey
                phasePromptWeightKilograms = latestWeight
                phaseStartPrompt = plan
            }
            return
        }
        guard userSettings.activateScheduledCaloriePhaseIfDue(now: now, latestWeightKilograms: latestWeight) else { return }
        phaseStartPrompt = nil
        accountData.stageSettings(userSettings, language: language)
        accountData.syncSettings(userSettings, language: language)
        refreshTodayWidgetGoals()
    }

    private func latestPlannedWeight(now: Date) -> Double? {
        (trainingStore.bodyMeasurements + healthKitManager.bodyWeights)
            .filter { $0.date <= now && ($0.weightKilograms ?? 0) > 0 }
            .max { $0.date < $1.date }?.weightKilograms
    }

    private func completePlannedCaloriePhaseStart(planID: UUID, bodyFatPercentage: Double, enteredWeightKilograms: Double) {
        guard var plan = userSettings.scheduledCaloriePhase, plan.id == planID else { return }
        let now = Date()
        let latestWeight = latestPlannedWeight(now: now)
        guard plan.isDue(now: now, latestWeightKilograms: latestWeight) else { return }
        plan.bodyFatPercentage = bodyFatPercentage
        plan.weightSource = .manual
        plan.manualStartWeightKilograms = enteredWeightKilograms
        guard plan.isValid else { return }
        userSettings.setScheduledCaloriePhase(plan)
        guard userSettings.activateScheduledCaloriePhaseIfDue(now: now, latestWeightKilograms: latestWeight) else { return }
        phaseStartPrompt = nil
        accountData.stageSettings(userSettings, language: language)
        accountData.syncSettings(userSettings, language: language)
        refreshTodayWidgetGoals()
    }

    private func applyDailyFoodSchedules() {
        guard premium.hasNutrition else { return }
        dailyFoodStore.reconcileToday(calorieStore: calorieStore, categories: categoryStore.categories)
    }

    private func scheduleMicronutrientRefresh() {
        micronutrientRefresh.schedule(foods: foodStore, entries: calorieStore, enabled: premium.hasNutrition)
    }

    private func scheduleAutomaticMicronutrients(for entries: [CalorieEntry]) {
        automaticMicronutrientEstimation.schedule(entries: entries, foods: foodStore, diary: calorieStore, premium: premium)
    }

    private func refreshStreakRewards() {
        streakRewards.reconcile(
            nutritionActivityDays: calorieStore.streakActivityDayKeys,
            workoutDates: trainingStore.completedWorkouts.map { $0.completedAt ?? $0.startedAt }
        )
        calorieStore.applyStreakFreezeDays(streakRewards.nutritionFrozenDayKeys)
        trainingStore.applyStreakFreezeWeeks(streakRewards.trainingFrozenWeekKeys)
    }

    private func mainTabPage<Content: View>(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: HyseSpacing.small) { activeWorkoutInset }
    }

    @ViewBuilder private var activeWorkoutInset: some View {
        if trainingStore.hasResolvedPersistenceScope, !keyboardVisible, !mealBulkSelectionActive,
           let workout = trainingStore.activeWorkout {
            ActiveWorkoutBar(
                workout: workout,
                discard: { trainingStore.discardActiveWorkout() },
                open: {
                    openedActiveWorkoutFromBar = true
                    showingActiveWorkout = true
                }
            )
                .padding(.bottom, HyseSpacing.medium)
                .zIndex(20)
        }
    }

    private var homeView: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollViewReader { proxy in
                    ScrollView {
                        Color.clear.frame(height: 1).id(NutritionHomeScrollTarget.top)
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            LazyVStack(alignment: .leading, spacing: HyseSpacing.section) {
                                if let restriction = calorieStore.trackingRestriction(for: selectedDate, at: context.date) {
                                    foodTrackingLockedBanner(restriction)
                                }
                                nutritionHomeHeader
                                if userSettings.isDashboardSectionVisible(.fasting), fastingStore.isFasting {
                                    ActiveFastingBanner(store: fastingStore)
                                }
                                homeSyncStatus
                                mealLogSection
                                if userSettings.isDashboardSectionVisible(.water) {
                                    waterHomeSection
                                }
                                if userSettings.isDashboardSectionVisible(.steps) || userSettings.isDashboardSectionVisible(.fasting) {
                                    wellnessHomeSection
                                }
                                NavigationLink {
                                    WeeklyOverviewView(calorieStore: calorieStore, trainingStore: trainingStore, settings: userSettings, health: healthKitManager, selectedDate: selectedDate) { date in
                                        selectedDate = Calendar.current.startOfDay(for: date)
                                        nutritionHomeScrollRequestID = UUID()
                                    }
                                } label: {
                                    WeeklyOverviewHomeCard(calorieStore: calorieStore, trainingStore: trainingStore, selectedDate: selectedDate)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, HyseSpacing.page)
                            .padding(.top, HyseSpacing.medium)
                            .padding(.bottom, HyseSpacing.section)
                        }
                    }
                    .onChange(of: nutritionHomeScrollRequestID) { _, _ in
                        proxy.scrollTo(NutritionHomeScrollTarget.top, anchor: .top)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedMealCategory) { category in
                categoryDetailView(for: category)
            }
            .simultaneousGesture(daySwipeGesture)
            .sheet(isPresented: $showingCalendar, onDismiss: {
                guard showNutritionPremiumAfterCalendarDismiss else { return }
                showNutritionPremiumAfterCalendarDismiss = false
                showingNutritionPremium = true
            }) {
                homeCalendarSheet
            }
            .sheet(isPresented: $showingStreak) {
                StreakDetailView(calorieStore: calorieStore, trainingStore: trainingStore, rewards: streakRewards)
                    .environmentObject(language)
            }
            .sheet(isPresented: $showingCalorieDetails) { calorieDetails }
            .sheet(isPresented: Binding(
                get: { calorieStore.pendingGuestMergeCount > 0 || foodStore.pendingGuestFavoriteMergeCount > 0 || trainingStore.pendingGuestWorkoutCount > 0 || recipeStore.pendingGuestRecipeMergeCount > 0 || mealPlanStore.pendingGuestMergeCount > 0 },
                set: { _ in }
            )) {
                GuestMergeView(
                    entryCount: calorieStore.pendingGuestMergeCount,
                    favoriteCount: foodStore.pendingGuestFavoriteMergeCount,
                    workoutCount: trainingStore.pendingGuestWorkoutCount,
                    recipeCount: recipeStore.pendingGuestRecipeMergeCount,
                    mealPlanCount: mealPlanStore.pendingGuestMergeCount,
                    isMerging: calorieStore.isMergingGuestEntries || recipeStore.isMergingGuestRecipes,
                    importAction: {
                        calorieStore.resolveGuestMerge(shouldMerge: true)
                        foodStore.resolveGuestFavoriteMerge(shouldMerge: true)
                        trainingStore.resolveGuestMerge(shouldMerge: true)
                        recipeStore.resolveGuestMerge(shouldMerge: true)
                        mealPlanStore.resolveGuestMerge(shouldMerge: true)
                    },
                    keepSeparateAction: {
                        calorieStore.resolveGuestMerge(shouldMerge: false)
                        foodStore.resolveGuestFavoriteMerge(shouldMerge: false)
                        trainingStore.resolveGuestMerge(shouldMerge: false)
                        recipeStore.resolveGuestMerge(shouldMerge: false)
                        mealPlanStore.resolveGuestMerge(shouldMerge: false)
                    }
                )
                .environmentObject(language)
            }
            .onChange(of: scenePhase) { _, phase in
                // Nach Rückkehr in die App werden ggf. offline gespeicherte
                // Einträge erneut versucht, ohne die lokale Quelle zu verändern.
                if phase == .active {
                    Task { await authManager.refreshSession() }
                    calorieStore.syncPendingEntries()
                    foodStore.syncPendingFoods()
                    trainingStore.sync()
                    trainingStore.handleSceneBecameActive()
                    refreshNotificationSchedule()
                    recipeStore.syncPendingRecipes()
                    handleDayChangeIfNeeded()
                    applyDailyFoodSchedules()
                    refreshStreakRewards()
                    // Refresh the feed when returning to the foreground so a
                    // Community news post received while the app was away is
                    // reflected in the badge immediately.
                    Task { await notificationCenter.load(auth: authManager, trainingStore: trainingStore, force: true) }
                    // A manual value may have been added while Health was in
                    // the foreground. Bypass the short dashboard throttle once
                    // when Hyse becomes active so it is visible immediately.
                    healthKitManager.refreshEnergy(around: selectedDate, force: true)
                    healthKitManager.refreshSteps(around: selectedDate)
                    healthKitManager.backfillDietaryMicronutrients(entries: calorieStore.entries, scopeID: calorieStore.micronutrientScopeID)
                    calorieStore.refreshWidget(immediately: true)
                    refreshTodayWidgetGoals()
                } else {
                    // Flush the short in-memory training edit buffer before
                    // iOS suspends the app. Uploads resume on the next active
                    // phase, while local safety never depends on the network.
                    trainingStore.flushPendingChanges()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in handleDayChangeIfNeeded() }
        }
    }

    private var homeCalendarSheet: some View {
        NavigationStack {
            ZStack {
                HyseNutritionBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: HyseSpacing.section) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t("content.select_date"))
                                .font(.title2.bold())
                            Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(language.locale)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            .environment(\.locale, language.locale)
                            .tint(HyseColor.accent)
                            .padding(HyseSpacing.medium)
                            .hyseGlassSurface(radius: HyseRadius.card, tint: HyseColor.accent)

                        if !calendarActivityDays.isEmpty {
                            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                                HStack {
                                    Text(t("content.recent_activity").uppercased())
                                        .font(.caption.weight(.heavy))
                                        .tracking(1.1)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    HStack(spacing: HyseSpacing.medium) {
                                        calendarLegend("fork.knife", title: t("content.meals"), color: HyseColor.accent)
                                        calendarLegend("dumbbell.fill", title: t("training.title"), color: HyseColor.success)
                                    }
                                }

                                ForEach(calendarActivityDays.prefix(8), id: \.self) { day in
                                    Button {
                                        selectedDate = day
                                        showingCalendar = false
                                    } label: {
                                        calendarActivityRow(day)
                                    }
                                    .buttonStyle(HyseLiftButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(HyseSpacing.page)
                    .padding(.bottom, HyseSpacing.section)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("add_entry.done")) { showingCalendar = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func calendarLegend(_ icon: String, title: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel(title)
    }

    private func calendarActivityRow(_ day: Date) -> some View {
        let hasMeals = calorieStore.activeDays.contains { Calendar.current.isDate($0, inSameDayAs: day) }
        let hasWorkout = !trainingStore.workouts(on: day).isEmpty
        let selected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        return HStack(spacing: HyseSpacing.medium) {
            VStack(spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(language.locale)).uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.title3.bold())
                    .monospacedDigit()
            }
            .frame(width: 42, height: 44)
            .background(selected ? HyseColor.accent.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.wide).locale(language.locale)))
                    .font(.subheadline.weight(.semibold))
                Text(day.formatted(.dateTime.day().month(.wide).year().locale(language.locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if hasMeals { calendarActivityIcon("fork.knife", color: HyseColor.accent) }
            if hasWorkout { calendarActivityIcon("dumbbell.fill", color: HyseColor.success) }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(HyseSpacing.medium)
        .hyseGlassSurface(radius: HyseRadius.control, tint: selected ? HyseColor.accent : nil)
    }

    private func calendarActivityIcon(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.11), in: Circle())
    }

    @ViewBuilder private var homeSyncStatus: some View {
        if calorieStore.localDiaryUnreadable {
            HyseStatusBanner(title: t("content.local_diary_unreadable_title"), message: t("content.local_diary_unreadable_message"), style: .error)
        } else if authManager.isLoggedIn {
            switch calorieStore.syncState {
            case .syncing:
                HyseStatusBanner(title: t("sync.syncing"), message: t("content.entries_loading_from_account"), style: .information)
            case .offline:
                HyseStatusBanner(title: t("content.offline"), message: t("content.entries_remain_saved_locally_will_sync_later"), style: .offline)
            case .failed:
                HyseStatusBanner(title: t("content.sync_pending"), message: calorieStore.lastLocalSaveFailed ? t("content.local_diary_save_failed") : t("content.at_least_one_entry_has_not_yet"), style: .warning, actionTitle: t("content.retry"), action: calorieStore.syncPendingEntries)
            default:
                EmptyView()
            }
        }
    }

    private var mealLogSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            Text(t("content.food_log").uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: HyseSpacing.large) {
                ForEach(categoryStore.categories) { category in
                    Button {
                        guard !mealNavigationIsSuppressed else { return }
                        selectedMealCategory = category
                    } label: {
                        categoryRow(category)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(HyseSpacing.large)
                            .hyseGlassSurface(radius: HyseRadius.card)
                            .contentShape(Rectangle())
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .buttonStyle(HyseLiftButtonStyle())
                    // The parent day-swipe is simultaneous so scrolling stays
                    // responsive. Disable the row as soon as that gesture is
                    // clearly horizontal, otherwise its release can also navigate.
                    .allowsHitTesting(!mealNavigationIsSuppressed)
                    .disabled(mealNavigationIsSuppressed)
                }
            }
            .hyseTourTarget(.meals)
        }
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($horizontalDaySwipeIsActive) { value, isActive, _ in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                isActive = horizontal > 18 && horizontal > vertical * 1.35
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let wasHorizontalSwipe = abs(horizontal) > 18 && abs(horizontal) > abs(vertical) * 1.35
                if abs(horizontal) > 80, abs(horizontal) > abs(vertical) * 1.8 {
                    changeDay(by: horizontal < 0 ? 1 : -1)
                }

                // Keep suppression through the touch-up event. NavigationLink
                // resolves its action on release, after the drag has ended.
                if wasHorizontalSwipe {
                    suppressMealNavigationAfterDaySwipe = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        suppressMealNavigationAfterDaySwipe = false
                    }
                }
            }
    }

    private var mealNavigationIsSuppressed: Bool {
        horizontalDaySwipeIsActive || suppressMealNavigationAfterDaySwipe
    }

    private func categoryDetailView(for category: MealCategory) -> some View {
        CategoryDetailView(
            category: category,
            calorieStore: calorieStore,
            foodStore: foodStore,
            recipeStore: recipeStore,
            categoryStore: categoryStore,
            frequencyStore: frequencyStore,
            userSettings: userSettings,
            availableCalories: availableCalories,
            selectedDate: selectedDate,
            showsActiveWorkoutBar: trainingStore.activeWorkout != nil && !keyboardVisible && !mealBulkSelectionActive,
            onSelectionModeChanged: { mealBulkSelectionActive = $0 }
        )
    }

    private var waterHomeSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            Text(t("content.hydration").uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            HyseCard(accent: HyseColor.accent) {
                WaterTrackerView(waterStore: waterStore, settingsStore: userSettings, date: selectedDate, healthKitManager: healthKitManager)
            }
        }
    }

    private var wellnessHomeSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            if userSettings.isDashboardSectionVisible(.steps) {
                Text(t("wellness.activity").uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
                StepCounterCard(health: healthKitManager, date: selectedDate)
            }

            if userSettings.isDashboardSectionVisible(.fasting) {
                Text(t("fasting.title").uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
                    .padding(.top, userSettings.isDashboardSectionVisible(.steps) ? HyseSpacing.small : 0)
                FastingTrackerCard(store: fastingStore)
            }
        }
    }

    private var nutritionHomeHeader: some View {
        VStack(spacing: HyseSpacing.xLarge) {
            HStack(spacing: HyseSpacing.medium) {
                if authManager.isLoggedIn {
                    Button { showingNotifications = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: notificationCenter.unreadCount > 0 ? "bell.fill" : "bell")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(notificationCenter.unreadCount > 0 ? HyseColor.accent : Color.primary)
                                .frame(width: 42, height: 42)
                                .hyseGlassSurface(radius: 14, tint: notificationCenter.unreadCount > 0 ? HyseColor.accent : nil)
                            if notificationCenter.unreadCount > 0 {
                                Text("\(min(notificationCenter.unreadCount, 99))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 17, minHeight: 17)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .buttonStyle(HyseLiftButtonStyle())
                    .accessibilityLabel(t("notifications.title"))
                }
                Spacer(minLength: 0)
                Button { showingCalendar = true } label: {
                    VStack(spacing: 0) {
                        Text(selectedDate.formatted(.dateTime.month(.abbreviated).locale(language.locale)).uppercased())
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                        Text(selectedDate.formatted(.dateTime.day()).uppercased())
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(HyseColor.accent)
                    .frame(width: 42, height: 42)
                    .hyseGlassSurface(radius: 14)
                }
                .buttonStyle(HyseLiftButtonStyle())
                .accessibilityLabel(t("content.select_date"))
                Button { showingStreak = true } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill((calorieStore.hasStreakActivityToday ? HyseColor.streakFire : Color.secondary).opacity(0.12))
                            Image(systemName: "flame.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(calorieStore.hasStreakActivityToday ? HyseColor.streakFire : Color.secondary)
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: -1) {
                            Text("\(calorieStore.currentStreak)")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                            Text(t("app_tabs.days"))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                        Divider().frame(height: 23)
                        VStack(alignment: .leading, spacing: -1) {
                            Text("\(trainingStore.statistics.currentStreak)")
                                .font(.subheadline.bold())
                                .monospacedDigit()
                            Text(t("app_tabs.weeks"))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 42)
                    .hyseGlassSurface(radius: 16)
                }
                .buttonStyle(HyseLiftButtonStyle())
                .accessibilityLabel(
                    "\(t("content.current_streak_1_days", String(describing: calorieStore.currentStreak))), \(t("training.weekly_streak.accessibility", trainingStore.statistics.currentStreak))"
                )
                if isSingleNutritionMode {
                    Button { showingHealthOverview = true } label: {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(HyseColor.accent)
                            .frame(width: 42, height: 42)
                            .hyseGlassSurface(radius: 14, tint: HyseColor.accent)
                    }
                    .buttonStyle(HyseLiftButtonStyle())
                    .accessibilityLabel(t("health.overview.title"))
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .hyseGlassSurface(radius: 14)
                    }
                    .buttonStyle(HyseLiftButtonStyle())
                    .accessibilityLabel(t("content.settings"))
                }
            }

            HStack(spacing: HyseSpacing.medium) {
                Button { changeDay(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(HyseIconButtonStyle())
                    .accessibilityLabel(t("content.previous_day"))
                Spacer()
                Button { showingCalendar = true } label: {
                    Label(
                        dateHeaderTitle.uppercased(),
                        systemImage: "calendar"
                    )
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { changeDay(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(HyseIconButtonStyle())
                    .accessibilityLabel(t("content.next_day"))
            }

            VStack(spacing: HyseSpacing.small) {
                HyseCard(accent: HyseColor.accent) {
                    HStack(alignment: .center, spacing: HyseSpacing.large) {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            HStack(spacing: 4) {
                                Text(t("content.calorie_balance").uppercased())
                                    .font(.caption.weight(.heavy))
                                    .tracking(0.9)
                                    .foregroundStyle(.secondary)
                                HyseInfoButton(
                                    title: t("content.calorie_balance"),
                                    message: t("info.calorie_balance.body")
                                )
                            }
                            compactCalorieValue(t("content.eaten"), totalKcal)
                            compactCalorieValue(t("content.burned"), selectedDayEnergy.active)
                            Button(t("content.details")) { showingCalorieDetails = true }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(HyseColor.accent)
                        }
                        Spacer(minLength: 0)
                        calorieBalanceRing(size: 138, lineWidth: 10, prominent: true)
                    }
                }

                HyseCard {
                    VStack(spacing: HyseSpacing.medium) {
                        HStack(alignment: .top, spacing: HyseSpacing.medium) {
                            macroSummary(t("nutrition.metric.carbs"), calorieStore.totalCarbs(for: selectedDate), userSettings.targetCarbsGrams(availableCalories: availableCalories), color: HyseColor.accent)
                            Divider().frame(height: 54)
                            macroSummary(t("nutrition.metric.protein"), calorieStore.totalProtein(for: selectedDate), userSettings.targetProteinGrams(availableCalories: availableCalories), color: HyseColor.accent)
                            Divider().frame(height: 54)
                            macroSummary(t("nutrition.metric.fat"), calorieStore.totalFat(for: selectedDate), userSettings.targetFatGrams(availableCalories: availableCalories), color: HyseColor.accent)
                        }
                        if !visibleHomeAdditionalMetrics.isEmpty {
                            Divider()
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HyseSpacing.medium) {
                                ForEach(visibleHomeAdditionalMetrics) { metric in
                                    homeAdditionalMetricSummary(metric)
                                }
                            }
                        }
                        Divider()
                        MicronutrientDailyButton(entries: calorieStore.entries(for: selectedDate))
                    }
                }
            }
            .hyseTourTarget(.nutrition)
        }
        .padding(.vertical, HyseSpacing.small)
    }

    private var dateHeaderTitle: String {
        let date = selectedDate.formatted(.dateTime.day().month(.abbreviated).locale(language.locale))
        return isToday ? "\(t("content.today")), \(date)" : selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(language.locale))
    }

    private func homeIconAction(_ icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .hyseGlassSurface(radius: 20)
        }
        .buttonStyle(HyseLiftButtonStyle())
        .accessibilityLabel(label)
    }

    private func macroTile(_ title: String, _ amount: Double, _ target: Double, color: Color) -> some View {
        macroSummary(title, amount, target, color: color)
            .padding(.horizontal, HyseSpacing.small)
            .padding(.vertical, HyseSpacing.small)
            .frame(maxWidth: .infinity, minHeight: 68)
            .hyseGlassSurface(radius: HyseRadius.control)
    }

    @ViewBuilder
    private func dashboardSection(_ section: DashboardSection) -> some View {
        switch section {
        case .date:
            EmptyView()
        case .calories:
            EmptyView()
        case .training:
            EmptyView()
        case .water:
            Section(t("content.hydration")) {
                HyseCard(accent: HyseColor.accent) {
                    WaterTrackerView(waterStore: waterStore, settingsStore: userSettings, date: selectedDate, healthKitManager: healthKitManager)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
        case .nutrition:
            EmptyView()
        case .meals:
            Section(t("content.food_log")) {
                ForEach(categoryStore.categories) { category in
                    NavigationLink {
                        categoryDetailView(for: category)
                    } label: {
                        categoryRow(category)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HyseSpacing.medium)
                            .padding(.vertical, HyseSpacing.small)
                            .hyseGlassSurface(radius: HyseRadius.card)
                            .contentShape(Rectangle())
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                }
            }
        case .steps:
            StepCounterCard(health: healthKitManager, date: selectedDate)
        case .fasting:
            FastingTrackerCard(store: fastingStore)
        }
    }

    private var datePicker: some View {
        HStack(spacing: HyseSpacing.medium) {
            Button { changeDay(by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(HyseIconButtonStyle()).accessibilityLabel(t("content.previous_day"))
            Spacer()
            VStack {
                Text(isToday ? t("content.today") : selectedDate.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: language.language.localeIdentifier))))
                Text(selectedDate.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: language.language.localeIdentifier))))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button { changeDay(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .overlay(alignment: .topTrailing) {
                        if nextDayRequiresNutritionPremium {
                            PremiumFeatureIcon(area: .nutrition)
                                .offset(x: 9, y: -8)
                        }
                    }
            }
            .buttonStyle(HyseIconButtonStyle())
            .accessibilityLabel(t("content.next_day"))
        }
        .padding(HyseSpacing.medium)
        .hyseGlassSurface(radius: HyseRadius.card)
    }

    private func changeDay(by offset: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate
    }

    private var nextDayRequiresNutritionPremium: Bool {
        guard !premium.hasNutrition,
              let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return false }
        return Calendar.current.startOfDay(for: nextDay) > Calendar.current.startOfDay(for: Date())
    }

    private func handleSelectedNutritionDateChange(_ date: Date) {
        healthKitManager.refreshEnergy(around: date)
        guard !premium.hasNutrition,
              Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date()) else { return }
        if showingCalendar {
            showNutritionPremiumAfterCalendarDismiss = true
            showingCalendar = false
        } else {
            showingNutritionPremium = true
        }
    }

    private func restoreTodayAfterDismissedNutritionPaywall() {
        guard !premium.hasNutrition,
              Calendar.current.startOfDay(for: selectedDate) > Calendar.current.startOfDay(for: Date()) else { return }
        selectedDate = Calendar.current.startOfDay(for: Date())
    }

    private func handleDayChangeIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if Calendar.current.isDate(selectedDate, inSameDayAs: currentDay) { selectedDate = today }
        currentDay = today
        healthKitManager.refreshEnergy(around: today)
    }

    private var calorieSummary: some View {
        HyseCard(accent: availableCalories >= totalKcal ? HyseColor.accent : HyseColor.danger) {
        VStack(spacing: HyseSpacing.xLarge) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    Text(t("content.calorie_balance")).font(.headline)
                    Text("\(t("content.daily_goal")): \(Int(availableCalories)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("content.details")) { showingCalorieDetails = true }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(HyseColor.accent)
            }

            HStack(alignment: .center, spacing: HyseSpacing.medium) {
                calorieValue(t("content.eaten"), totalKcal)
                Spacer(minLength: 0)
                calorieBalanceRing()
                Spacer(minLength: 0)
                calorieValue(t("health.overview.activity"), selectedDayEnergy.active)
            }

            HStack(alignment: .top, spacing: HyseSpacing.medium) {
                macroSummary(
                    t("nutrition.metric.carbs"),
                    calorieStore.totalCarbs(for: selectedDate),
                    userSettings.targetCarbsGrams(availableCalories: availableCalories)
                )
                macroSummary(
                    t("nutrition.metric.protein"),
                    calorieStore.totalProtein(for: selectedDate),
                    userSettings.targetProteinGrams(availableCalories: availableCalories)
                )
                macroSummary(
                    t("nutrition.metric.fat"),
                    calorieStore.totalFat(for: selectedDate),
                    userSettings.targetFatGrams(availableCalories: availableCalories)
                )
            }

            MicronutrientDailyButton(entries: calorieStore.entries(for: selectedDate))

        }
        }
    }

    private var calorieDetails: some View {
        NavigationStack {
            List {
                Section {
                    HyseCard(accent: availableCalories >= totalKcal ? HyseColor.accent : HyseColor.danger) {
                        HStack(alignment: .center, spacing: HyseSpacing.medium) {
                            calorieValue(t("content.eaten"), totalKcal)
                            Spacer(minLength: 0)
                            calorieBalanceRing()
                            Spacer(minLength: 0)
                            calorieValue(t("health.overview.activity"), selectedDayEnergy.active)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }

                Section {
                    HyseCard(accent: HyseColor.accent) {
                        DashboardNutritionOverview(
                            carbs: calorieStore.totalCarbs(for: selectedDate), carbsTarget: userSettings.targetCarbsGrams(availableCalories: availableCalories),
                            protein: calorieStore.totalProtein(for: selectedDate), proteinTarget: userSettings.targetProteinGrams(availableCalories: availableCalories),
                            fat: calorieStore.totalFat(for: selectedDate), fatTarget: userSettings.targetFatGrams(availableCalories: availableCalories),
                            addedSugar: calorieStore.totalAddedSugar(for: selectedDate), addedSugarTarget: addedSugarTarget,
                            fruitSugar: calorieStore.totalFruitSugar(for: selectedDate), fruitSugarTarget: userSettings.fruitSugarGoalGrams,
                            salt: calorieStore.totalSalt(for: selectedDate), saltTarget: saltTarget,
                            fiber: calorieStore.totalFiber(for: selectedDate), fiberTarget: fiberTarget,
                            saturatedFat: calorieStore.totalSaturatedFat(for: selectedDate), saturatedFatTarget: saturatedFatTarget,
                            settingsStore: userSettings,
                            showsAllMetrics: true
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                } header: {
                    Text(t("content.nutrition_overview"))
                } footer: {
                    Text(t("content.progress_values_follow_targets_in_settings"))
                }

                Section(t("content.calculation")) {
                    HyseCard { dynamicTargetDetails }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
            .listStyle(.insetGrouped)
            .hyseForm()
            .navigationTitle(t("content.calorie_balance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("add_entry.done")) { showingCalorieDetails = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func calorieBalanceRing(size: CGFloat = 116, lineWidth: CGFloat = 11, prominent: Bool = false) -> some View {
        let remaining = availableCalories - totalKcal
        let progress = min(max(totalKcal / max(availableCalories, 1), 0), 1)
        let color = remaining >= 0 ? HyseColor.accent : HyseColor.danger
        return ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.08, to: 0.08 + 0.84 * progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(90))
            VStack(spacing: 1) {
                Text("\(Int(remaining))")
                    .font(prominent ? .system(size: size * 0.21, weight: .semibold, design: .rounded) : .title2.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(remaining >= 0 ? Color.primary : HyseColor.danger)
                Text(t("content.remaining"))
                    .font(prominent ? .caption : .caption2)
                    .foregroundStyle(.secondary)
                if prominent {
                    Text("\(t("content.daily_goal")) \(Int(availableCalories)) kcal")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }

    private func calorieValue(_ title: String, _ amount: Double) -> some View {
        VStack(spacing: HyseSpacing.xSmall) {
            Text("\(Int(amount))")
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func compactCalorieValue(_ title: String, _ amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HyseSpacing.small) {
            Text("\(Int(amount))")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func macroSummary(_ title: String, _ amount: Double, _ target: Double, color: Color = HyseColor.accent) -> some View {
        VStack(spacing: HyseSpacing.small) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            HyseProgressBar(
                value: amount,
                total: max(target, 1),
                colors: [amount > target ? HyseColor.danger : color]
            )
            Text("\(Int(amount)) / \(Int(target)) g")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var visibleHomeAdditionalMetrics: [NutritionMetric] {
        NutritionMetric.homeAdditionalOptions.filter(userSettings.isHomeAdditionalNutritionMetricVisible)
    }

    private func homeAdditionalMetricSummary(_ metric: NutritionMetric) -> some View {
        let values = homeAdditionalMetricValues(metric)
        return VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Text(t("nutrition.metric.\(metric.rawValue)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HyseProgressBar(
                value: values.amount,
                total: max(values.target, 1),
                colors: [metric != .fiber && values.amount > values.target ? HyseColor.danger : HyseColor.accent]
            )
            Text("\(values.amount.formatted(.number.precision(.fractionLength(0...1)))) / \(values.target.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func homeAdditionalMetricValues(_ metric: NutritionMetric) -> (amount: Double, target: Double) {
        switch metric {
        case .addedSugar: return (calorieStore.totalAddedSugar(for: selectedDate), addedSugarTarget)
        case .fruitSugar: return (calorieStore.totalFruitSugar(for: selectedDate), userSettings.fruitSugarGoalGrams)
        case .salt: return (calorieStore.totalSalt(for: selectedDate), saltTarget)
        case .fiber: return (calorieStore.totalFiber(for: selectedDate), fiberTarget)
        case .saturatedFat: return (calorieStore.totalSaturatedFat(for: selectedDate), saturatedFatTarget)
        case .carbs: return (calorieStore.totalCarbs(for: selectedDate), userSettings.targetCarbsGrams(availableCalories: availableCalories))
        case .protein: return (calorieStore.totalProtein(for: selectedDate), userSettings.targetProteinGrams(availableCalories: availableCalories))
        case .fat: return (calorieStore.totalFat(for: selectedDate), userSettings.targetFatGrams(availableCalories: availableCalories))
        }
    }

    @ViewBuilder private var dynamicTargetDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch calorieTarget.source {
            case .dynamic:
                if let surplus = calorieTarget.fixedSurplus {
                    Text(t(
                        "calorie_target.surplus_formula",
                        Int(calorieTarget.previousDayRestingEnergy ?? 0),
                        Int(surplus),
                        Int(calorieTarget.targetKilocalories)
                    ))
                } else {
                    Text(t(
                        "calorie_target.formula",
                        Int(calorieTarget.previousDayRestingEnergy ?? 0),
                        Int(calorieTarget.dynamicDeficit ?? 0),
                        Int(calorieTarget.targetKilocalories)
                    ))
                }
            case .fixedFallback(let reason):
                Text(t("calorie_target.fixed_fallback", Int(calorieTarget.targetKilocalories)))
                    .foregroundStyle(HyseColor.warning)
                Text(t(fallbackLocalizationKey(reason)))
            case .fixed:
                Text(t("calorie_target.fixed_formula", Int(calorieTarget.targetKilocalories)))
            }

            if userSettings.calorieGoalConfiguration(for: selectedDate).mode == .dynamic {
                Text(t("calorie_target.active_energy_formula", Int(selectedDayEnergy.active)))
            } else {
                Text(t("calorie_target.active_energy_fixed"))
            }

            Text(t(
                "calorie_target.day_type_formula",
                t(isTrainingDay ? "calorie_target.training_day" : "calorie_target.rest_day"),
                signedKcal(dayTypeAdjustment)
            ))
            Text(t("calorie_target.final_formula", Int(availableCalories)))

            if let phase = calorieTarget.phase {
                Text(t(
                    "calorie_target.phase_details",
                    phase.startedAt.formatted(.dateTime.day().month().year().locale(language.locale)),
                    calorieTarget.completedCalendarDays ?? 0,
                    phase.initialBodyFatFraction * 100,
                    phase.initialWeightKilograms
                ))
            }
            if let updated = calorieTarget.energyUpdatedAt {
                if (calorieTarget.energySourceCount ?? 0) > 1 {
                    Text(t(
                        "calorie_target.health_source_multiple",
                        calorieTarget.energySourceName ?? "Apple Health",
                        calorieTarget.energySourceCount ?? 0,
                        updated.formatted(.dateTime.day().month().hour().minute().locale(language.locale))
                    ))
                } else {
                    Text(t(
                        "calorie_target.health_source",
                        calorieTarget.energySourceName ?? "Apple Health",
                        updated.formatted(.dateTime.day().month().hour().minute().locale(language.locale))
                    ))
                }
            }
            if calorieTarget.rawTargetKilocalories < 0 {
                Text(t("calorie_target.existing_zero_floor", Int(calorieTarget.rawTargetKilocalories)))
            }
            if rawAvailableCalories < 0, calorieTarget.rawTargetKilocalories >= 0 {
                Text(t("calorie_target.available_zero_floor", Int(rawAvailableCalories)))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func signedKcal(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    private func fallbackLocalizationKey(_ reason: DynamicCalorieTargetBreakdown.FallbackReason) -> String {
        switch reason {
        case .phaseMissing: return "calorie_target.phase_missing"
        case .phaseNotStarted: return "calorie_target.phase_not_started"
        case .restingEnergyMissing: return "calorie_target.resting_missing"
        case .futureDate: return "calorie_target.future_date"
        }
    }

    private func categoryRow(_ category: MealCategory) -> some View {
        let current = calorieStore.totalKcal(for: selectedDate, categoryId: category.id)
        // Orientierungswert wird jetzt dynamisch auf Basis von Grundziel + Aktivitätskalorien berechnet.
        let target = category.target(for: availableCalories)
        let limit = category.limit(for: availableCalories)
        let ringDenominator = target ?? limit
        let progress = ringDenominator.map { $0 > 0 ? current / $0 : 0 } ?? 0
        let overLimit = (limit.map { category.enforceLimit && current > $0 }) ?? false

        return HStack(spacing: 14) {
            if let ringDenominator, ringDenominator > 0 {
                CategoryProgressRing(progress: progress, color: categoryTint(category), isOverLimit: overLimit)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(category.localizedName).font(.headline).foregroundStyle(.primary)
                Text(target.map { "\(Int(current)) / \(Int($0)) kcal" } ?? "\(Int(current)) kcal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let limit = limit, category.enforceLimit {
                    Text("\(t("content.limit")): \(Int(limit)) kcal").font(.caption).foregroundColor(current > limit ? HyseColor.danger : .secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 42)
        }.padding(.vertical, 4)
    }

    private func categoryTint(_ category: MealCategory) -> Color {
        HyseColor.accent
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
}

private struct ScheduledCaloriePhaseStartView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let plan: ScheduledCaloriePhase
    let latestWeightKilograms: Double?
    let onStart: (Double, Double) -> Void

    @State private var bodyFatText: String
    @State private var weightText: String

    init(plan: ScheduledCaloriePhase, latestWeightKilograms: Double?, onStart: @escaping (Double, Double) -> Void) {
        self.plan = plan
        self.latestWeightKilograms = latestWeightKilograms
        self.onStart = onStart
        _bodyFatText = State(initialValue: plan.bodyFatPercentage.map { String($0) } ?? "")
        let proposedWeight = latestWeightKilograms ?? plan.manualStartWeightKilograms
        _weightText = State(initialValue: proposedWeight.map { String($0) } ?? "")
    }

    private func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var bodyFat: Double? {
        guard let value = number(bodyFatText), value.isFinite, value > 0, value < 100 else { return nil }
        return value
    }

    private var enteredWeight: Double? {
        guard let value = number(weightText), value.isFinite, value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(language.text("calorie_plan.start_prompt_message"))
                    HStack {
                        Text(language.text("calorie_plan.body_fat"))
                        Spacer()
                        TextField("%", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("%").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(language.text("calorie_plan.start_weight"))
                        Spacer()
                        TextField("kg", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(language.text("calorie_plan.start_prompt_waiting"))
                }
            }
            .hyseForm()
            .navigationTitle(language.text("calorie_plan.start_prompt_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("calorie_plan.start_prompt_later")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("calorie_plan.start_prompt_confirm")) {
                        guard let bodyFat, let enteredWeight else { return }
                        onStart(bodyFat, enteredWeight)
                    }
                    .bold()
                    .disabled(bodyFat == nil || enteredWeight == nil)
                }
            }
        }
    }
}

private struct DashboardNutritionOverview: View {
    @EnvironmentObject private var language: LanguageStore
    let carbs, carbsTarget, protein, proteinTarget, fat, fatTarget: Double
    let addedSugar, addedSugarTarget, fruitSugar, fruitSugarTarget: Double
    let salt, saltTarget, fiber, fiberTarget, saturatedFat, saturatedFatTarget: Double
    @ObservedObject var settingsStore: UserSettingsStore
    var showsAllMetrics = false

    var body: some View {
        let visibleMetrics = showsAllMetrics ? metrics : metrics.filter { settingsStore.isNutritionMetricVisible($0.metric) }
        if visibleMetrics.isEmpty {
            Text("ui.choose_values_overview_in_settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 5)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(visibleMetrics) { metric in
                    cell(metric.title, metric.value, metric.target, metric.symbol, metric.color, isMinimum: metric.isMinimum)
                }
            }
            .padding(.vertical, 5)
        }
    }

    private var metrics: [NutritionDashboardMetric] {
        [
            NutritionDashboardMetric(metric: .carbs, title: language.text("nutrition.metric.carbs"), value: carbs, target: carbsTarget, symbol: "leaf", color: HyseColor.accent, isMinimum: true),
            NutritionDashboardMetric(metric: .protein, title: language.text("nutrition.metric.protein"), value: protein, target: proteinTarget, symbol: "figure.strengthtraining.traditional", color: HyseColor.accent, isMinimum: true),
            NutritionDashboardMetric(metric: .fat, title: language.text("nutrition.metric.fat"), value: fat, target: fatTarget, symbol: "drop.fill", color: HyseColor.accent, isMinimum: true),
            NutritionDashboardMetric(metric: .addedSugar, title: language.text("nutrition.metric.addedSugar"), value: addedSugar, target: addedSugarTarget, symbol: "cube", color: HyseColor.accent),
            NutritionDashboardMetric(metric: .salt, title: language.text("nutrition.metric.salt"), value: salt, target: saltTarget, symbol: "s.circle", color: HyseColor.accent),
            NutritionDashboardMetric(metric: .fiber, title: language.text("nutrition.metric.fiber"), value: fiber, target: fiberTarget, symbol: "leaf.fill", color: HyseColor.accent, isMinimum: true),
            NutritionDashboardMetric(metric: .saturatedFat, title: language.text("nutrition.metric.saturatedFat"), value: saturatedFat, target: saturatedFatTarget, symbol: "circle.fill", color: HyseColor.accent),
            NutritionDashboardMetric(metric: .fruitSugar, title: language.text("nutrition.metric.fruitSugar"), value: fruitSugar, target: fruitSugarTarget, symbol: "applelogo", color: HyseColor.accent)
        ]
    }

    private func cell(_ title: String, _ value: Double, _ target: Double, _ symbol: String, _ color: Color, isMinimum: Bool = false) -> some View {
        let exceeded = !isMinimum && value > target
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                HyseInfoButton(
                    title: title,
                    message: language.text("info.nutrition_metric.general"),
                    tint: color
                )
                .scaleEffect(0.82)
                .frame(width: 26, height: 26)
            }
            Text(String(format: "%.1f / %.1f g", value, target)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(exceeded ? HyseColor.danger : .primary)
            HyseProgressBar(value: min(value, target), total: max(target, 1), colors: [exceeded ? HyseColor.danger : color])
        }
        .padding(9)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NutritionDashboardMetric: Identifiable {
    let metric: NutritionMetric
    let title: String
    let value: Double
    let target: Double
    let symbol: String
    let color: Color
    var isMinimum = false

    var id: String { metric.rawValue }
}

private struct WaterTrackerView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var waterStore: WaterStore
    @ObservedObject var settingsStore: UserSettingsStore
    let date: Date
    @ObservedObject var healthKitManager: HealthKitManager

    private var amount: Double { waterStore.amount(for: date) }
    private var goal: Double { settingsStore.dailyWaterGoalMilliliters }
    private var glassSize: Double { settingsStore.waterGlassSizeMilliliters }
    private var remaining: Double { max(0, goal - amount) }
    private var progress: Double { min(amount / max(goal, 1), 1) }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(t("content.water_today"), systemImage: "drop.fill").font(.headline).foregroundStyle(HyseColor.accent)
                Spacer()
                HyseInfoButton(
                    title: t("content.hydration"),
                    message: t("info.hydration.body")
                )
                Text("\(formatted(amount)) / \(formatted(goal))")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
            }

            HyseProgressBar(value: progress, total: 1, colors: [HyseColor.accent])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(t("content.hydration_progress"))
            .accessibilityValue(t("content.1_percent", String(describing: Int(progress * 100))))

            Text(remaining > 0 ? t("content.1_remaining_reach_daily_goal", String(describing: formatted(remaining))) : t("content.daily_goal_reached"))
                .font(.caption)
                .foregroundStyle(remaining > 0 ? Color.secondary : HyseColor.success)

            HStack(spacing: 10) {
                Button { setWaterAmount(amount + glassSize) } label: {
                    Label(t("content.1_glass"), systemImage: "plus")
                }
                .buttonStyle(HysePrimaryButtonStyle())

                Button { setWaterAmount(amount + glassSize / 2) } label: {
                    Text(t("content.glass"))
                }
                .buttonStyle(HyseSecondaryButtonStyle())

                Spacer()

                Button { setWaterAmount(amount - glassSize / 2) } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(HyseIconButtonStyle())
                .disabled(amount == 0)
                .accessibilityLabel(t("content.remove_half_glass"))
            }
        }
        .padding(.vertical, 4)
    }

    private func setWaterAmount(_ newAmount: Double) {
        let total = max(0, newAmount)
        waterStore.setAmount(total, for: date)
        healthKitManager.syncWaterIntake(totalMilliliters: total, date: date)
    }

    private func formatted(_ milliliters: Double) -> String {
        let unit = settingsStore.defaultLiquidUnit
        let value = FoodUnit.milliliter.converted(milliliters, to: unit) ?? milliliters
        return unit == .fluidOunce
            ? String(format: "%.1f fl oz", value)
            : "\(Int(value.rounded())) ml"
    }
}
