import SwiftUI
import UIKit
import CoreLocation
import LocalAuthentication
import Combine

private enum HyseLegalLinks {
    static let privacyEnglish = URL(string: "\(HyseConfiguration.serverURL)/en/privacy")!
    static let privacyGerman = URL(string: "\(HyseConfiguration.serverURL)/de/datenschutz")!
    static let termsEnglish = URL(string: "\(HyseConfiguration.serverURL)/en/terms")!
    static let termsGerman = URL(string: "\(HyseConfiguration.serverURL)/de/agb")!
    static let legalNoticeEnglish = URL(string: "\(HyseConfiguration.serverURL)/privacy#content")!
    static let legalNoticeGerman = URL(string: "\(HyseConfiguration.serverURL)/datenschutz#verantwortlicher")!
    static let instagram = URL(string: "https://www.instagram.com/hyseapp")!
    static let tiktok = URL(string: "https://www.tiktok.com/@hyseapp")!
    static let youtube = URL(string: "https://www.youtube.com/@hyseapp")!
    static let openFoodFacts = URL(string: "https://world.openfoodfacts.org")!
    static let openDatabaseLicense = URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!
    static let supportEnglish = URL(string: "\(HyseConfiguration.serverURL)/en/support")!
    static let supportGerman = URL(string: "\(HyseConfiguration.serverURL)/de/support")!
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case account, interests, goals, appearance, health, notifications, training, privacy, about

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .account: "settings.account"
        case .interests: "settings.tracking_interests"
        case .goals: "content.nutrition_overview"
        case .appearance: "settings.appearance_units"
        case .health: "settings.apple_health"
        case .notifications: "settings.notifications"
        case .training: "training.feedback.settings_title"
        case .privacy: "settings.privacy_legal"
        case .about: "settings.about_hyse"
        }
    }

    var icon: String {
        switch self {
        case .account: "person.crop.circle"
        case .interests: "square.grid.2x2"
        case .goals: "target"
        case .appearance: "paintbrush"
        case .health: "heart.fill"
        case .notifications: "bell.badge"
        case .training: "figure.strengthtraining.traditional"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }

    var subtitleKey: String { "settings.category.\(rawValue).subtitle" }
    var infoKey: String { "info.settings.\(rawValue)" }

    var color: Color {
        HyseColor.accent
    }
}

private struct SettingsOverviewGroup: Identifiable {
    let id: String
    let titleKey: String
    let categories: [SettingsCategory]
}

private enum NutritionCodePrompt: Identifiable {
    case setup
    case manage
    case unlock(NutritionSettingsLockScope)
    case change
    case reset

    var id: String {
        switch self {
        case .setup: "setup"
        case .manage: "manage"
        case .unlock(let scope): "unlock-\(scope.rawValue)"
        case .change: "change"
        case .reset: "reset"
        }
    }

    var needsConfirmation: Bool {
        switch self {
        case .setup, .change, .reset: true
        case .manage, .unlock: false
        }
    }

    var allowsReset: Bool {
        switch self {
        case .manage, .unlock: true
        case .setup, .change, .reset: false
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var accountData: AccountDataStore
    @EnvironmentObject private var dailyFoodStore: DailyFoodScheduleStore
    @EnvironmentObject private var mealPlanStore: MealPlanStore
    @EnvironmentObject private var streakRewards: StreakRewardsStore
    @EnvironmentObject private var trainingStore: TrainingStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var settingsStore: UserSettingsStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var frequencyStore: FrequencyStore
    @ObservedObject var healthKitManager: HealthKitManager

    @State private var baseGoalText: String = ""
    @State private var trackingWindowClock = Date()
    @State private var trainingDayCalorieAdjustmentText: String = ""
    @State private var restDayCalorieAdjustmentText: String = ""
    @State private var trainingDayAddsCalories = true
    @State private var restDayAddsCalories = true
    @State private var fixedSurplusText: String = ""
    @State private var fixedDeficitText: String = ""
    @State private var calorieLimitBufferText: String = ""
    @State private var lowRemainingTrackingThresholdText: String = ""
    @State private var phaseBodyFatText: String = ""
    @State private var phaseWeightText: String = ""
    @State private var carbsPctText: String = ""
    @State private var proteinPctText: String = ""
    @State private var fatPctText: String = ""
    @State private var waterGoalText: String = ""
    @State private var waterGlassSizeText: String = ""
    @State private var addedSugarGoalText: String = ""
    @State private var fruitSugarGoalText: String = ""
    @State private var saltGoalText: String = ""
    @State private var fiberGoalText: String = ""
    @State private var saturatedFatGoalText: String = ""

    @State private var newCategoryName: String = ""
    @State private var editingCategory: MealCategory?
    @State private var editCategoryName: String = ""
    @State private var alertMessage: String?
    @State private var showingDoenerClicker = false
    @State private var showingProfileSetup = false
    @State private var showingAccount = false
    @State private var showingEmailChange = false
    @State private var showingPasswordManagement = false
    @State private var showingContentReports = false
    @State private var showingPublicContentReport = false
    @State private var showingDeleteConfirmation = false
    @State private var showingLogoutConfirmation = false
    @State private var showingPhaseResetConfirmation = false
    @State private var showingPhaseEditor = false
    @State private var showingScheduledPhaseEditor = false
    @State private var showingDefaultGymPicker = false
    @State private var isSigningOut = false
    @State private var isSavingSettings = false
    @State private var settingsSavedMessage: String?
    @State private var automaticSaveTask: Task<Void, Never>?
    @State private var deferredSettingsSyncTask: Task<Void, Never>?
    @State private var categoryDeletionMessage: String?
    @State private var selectedSettingsCategory: SettingsCategory?
    @State private var hasNutritionSettingsCode = NutritionSettingsLockStore.hasPasscode
    @State private var nutritionProtectedScopes = NutritionSettingsLockStore.enabledScopes
    @State private var unlockedNutritionScopes: Set<NutritionSettingsLockScope> = []
    @State private var nutritionLockManagementUnlocked = false
    @State private var nutritionCodePrompt: NutritionCodePrompt?
    @State private var nutritionCode = ""
    @State private var nutritionCodeConfirmation = ""
    @State private var nutritionCodeError: String?
    @State private var isResettingNutritionCode = false
    @State private var showingRemoveNutritionCodeConfirmation = false
    @State private var exportURLs: [URL] = []
    @State private var showingExportShare = false
    @State private var isExporting = false
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    private func plannedMacroValue(_ macros: ScheduledMacroGoals, fixed: Double?, share: Int, percentage: Int) -> String {
        if macros.plan.mode == .percentages { return "\(percentage) %" }
        if let fixed {
            return "\(fixed.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) g"
        }
        return macros.plan.variableCount == 1
            ? t("calorie_plan.macro_rest")
            : "\(share) % \(t("calorie_plan.macro_of_remainder"))"
    }

    private var latestPlannedWeight: Double? {
        (trainingStore.bodyMeasurements + healthKitManager.bodyWeights)
            .filter { $0.date <= Date() && ($0.weightKilograms ?? 0) > 0 }
            .max { $0.date < $1.date }?.weightKilograms
    }


    private var settingsOverviewGroups: [SettingsOverviewGroup] {
        var groups: [SettingsOverviewGroup] = []
        if settingsStore.trackingInterest.includesNutrition {
            groups.append(.init(id: "nutrition", titleKey: "tracking_interest.nutrition", categories: [.goals]))
        }
        if settingsStore.trackingInterest.includesTraining {
            groups.append(.init(id: "training", titleKey: "tracking_interest.training", categories: [.training]))
        }
        groups.append(.init(id: "shared", titleKey: "settings.group.shared", categories: [.interests, .appearance, .health, .notifications, .about]))
        groups.append(.init(id: "legal", titleKey: "settings.group.legal", categories: [.privacy]))
        return groups
    }

    private var visibleSettingsCategories: [SettingsCategory] {
        settingsOverviewGroups.flatMap(\.categories)
    }

    private var privacyReceiptVersion: String {
        accountData.marketingConsentPrivacyVersion.replacingOccurrences(of: "-gemini", with: "")
    }

    init(settingsStore: UserSettingsStore, categoryStore: CategoryStore, foodStore: FoodStore, calorieStore: CalorieStore, recipeStore: RecipeStore, frequencyStore: FrequencyStore, healthKitManager: HealthKitManager, initialCategory: SettingsCategory? = nil) {
        self.settingsStore = settingsStore
        self.categoryStore = categoryStore
        self.foodStore = foodStore
        self.calorieStore = calorieStore
        self.recipeStore = recipeStore
        self.frequencyStore = frequencyStore
        self.healthKitManager = healthKitManager
        _selectedSettingsCategory = State(initialValue: initialCategory)
        _baseGoalText = State(initialValue: String(format: "%.0f", settingsStore.baseCalorieGoal))
        _trainingDayCalorieAdjustmentText = State(initialValue: String(format: "%.0f", abs(settingsStore.trainingDayCalorieAdjustment)))
        _restDayCalorieAdjustmentText = State(initialValue: String(format: "%.0f", abs(settingsStore.restDayCalorieAdjustment)))
        _trainingDayAddsCalories = State(initialValue: settingsStore.trainingDayCalorieAdjustment >= 0)
        _restDayAddsCalories = State(initialValue: settingsStore.restDayCalorieAdjustment >= 0)
        _fixedSurplusText = State(initialValue: String(format: "%.0f", settingsStore.fixedCalorieSurplus))
        _fixedDeficitText = State(initialValue: String(format: "%.0f", settingsStore.fixedCalorieDeficit))
        _calorieLimitBufferText = State(initialValue: String(format: "%.0f", settingsStore.calorieLimitBufferKilocalories))
        _lowRemainingTrackingThresholdText = State(initialValue: String(format: "%.0f", settingsStore.lowRemainingTrackingCaloriesThreshold))
        _phaseBodyFatText = State(initialValue: settingsStore.dynamicDeficitPhase.map { String(format: "%.1f", $0.initialBodyFatFraction * 100) } ?? "")
        _phaseWeightText = State(initialValue: settingsStore.dynamicDeficitPhase.map { String(format: "%.1f", $0.initialWeightKilograms) } ?? "")
        _carbsPctText = State(initialValue: String(settingsStore.carbsPercentage))
        _proteinPctText = State(initialValue: String(settingsStore.proteinPercentage))
        _fatPctText = State(initialValue: String(settingsStore.fatPercentage))
        _waterGoalText = State(initialValue: Self.volumeText(settingsStore.dailyWaterGoalMilliliters, unit: settingsStore.defaultLiquidUnit))
        _waterGlassSizeText = State(initialValue: Self.volumeText(settingsStore.waterGlassSizeMilliliters, unit: settingsStore.defaultLiquidUnit))
        _addedSugarGoalText = State(initialValue: String(format: "%.0f", settingsStore.addedSugarGoalGrams))
        _fruitSugarGoalText = State(initialValue: String(format: "%.0f", settingsStore.fruitSugarGoalGrams))
        _saltGoalText = State(initialValue: String(format: "%.1f", settingsStore.saltGoalGrams))
        _fiberGoalText = State(initialValue: String(format: "%.0f", settingsStore.fiberGoalGrams))
        _saturatedFatGoalText = State(initialValue: String(format: "%.0f", settingsStore.saturatedFatGoalGrams))
    }

    var body: some View {
        ZStack {
            HyseBackdrop()
            if selectedSettingsCategory == nil {
                settingsOverview
            } else {
                Form(content: {
                Group {
                if let selectedSettingsCategory {
                    Section {
                        settingsDetailHeader(selectedSettingsCategory)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                    }
                }
                if selectedSettingsCategory == .account {
                    Section(header: Text(language.text("settings.account")), footer: Text(authManager.isLoggedIn ? language.text("settings.local_entries_sync_account_when_connection_available") : language.text("settings.you_can_use_hyse_without_account_local"))) {
                    if authManager.isLoggedIn {
                        HStack(spacing: HyseSpacing.medium) {
                            ProfileAvatarView(size: 54, editable: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(authManager.accountName).font(.headline)
                                Text(t("profile.tap_avatar_to_change")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent(t("settings.signed_in_as"), value: authManager.accountName)
                        LabeledContent(t("login.email_address"), value: authManager.accountEmail)
                        Button { showingEmailChange = true } label: {
                            Label(t("app_tabs.change_email_address"), systemImage: "envelope.badge")
                        }
                        Button { showingPasswordManagement = true } label: {
                            Label(t("app_tabs.password_security"), systemImage: "lock.shield")
                        }
                        Button(role: .destructive) { showingLogoutConfirmation = true } label: {
                            if isSigningOut { HStack { ProgressView(); Text(t("settings.signing_out")) } }
                            else { Label(t("settings.sign_out"), systemImage: "rectangle.portrait.and.arrow.right") }
                        }
                        .disabled(isSigningOut)
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            if authManager.isDeletingAccount {
                                ProgressView()
                            } else {
                                Label(t("settings.delete_account_permanently"), systemImage: "trash")
                            }
                        }
                        .disabled(authManager.isDeletingAccount)
                    } else {
                        Button { showingAccount = true } label: {
                            Label(t("settings.sign_in_create_account"), systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    }
                }
                if selectedSettingsCategory == .interests {
                    Section(
                        header: Text(t("settings.tracking_interests")),
                        footer: Text(t("settings.tracking_interests_explanation"))
                    ) {
                        Picker(t("settings.tracking_interests"), selection: $settingsStore.trackingInterest) {
                            ForEach(TrackingInterest.allCases) { value in
                                Label(t(value.localizationKey), systemImage: value.iconName)
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
                if selectedSettingsCategory == .appearance {
                    Section(language.text("settings.language")) {
                    Picker(language.text("settings.app_language"), selection: $language.preference) {
                        ForEach(LanguagePreference.allCases) { item in
                            Text(language.text(item.displayNameKey)).tag(item)
                        }
                    }
                    Text(language.text("settings.language_preference_explanation"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Section(t("settings.appearance_units")) {
                    Picker(t("settings.theme"), selection: $settingsStore.appTheme) {
                        Text(t("settings.theme_system")).tag(AppTheme.system)
                        Text(t("settings.theme_light")).tag(AppTheme.light)
                        Text(t("settings.theme_dark")).tag(AppTheme.dark)
                    }
                    if settingsStore.trackingInterest.includesNutrition {
                        Picker(t("settings.default_food_weight_unit"), selection: $settingsStore.defaultFoodUnit) {
                            ForEach(FoodUnit.weightUnits, id: \.self) { value in
                                Text(t(value.localizationKey)).tag(value)
                            }
                        }
                        Picker(t("settings.default_liquid_unit"), selection: $settingsStore.defaultLiquidUnit) {
                            ForEach(FoodUnit.volumeUnits, id: \.self) { value in
                                Text(t(value.localizationKey)).tag(value)
                            }
                        }
                    }
                    if settingsStore.trackingInterest.includesTraining {
                        Picker(t("settings.training_weight_unit"), selection: $settingsStore.trainingWeightUnit) {
                            ForEach(TrainingWeightUnit.allCases) { unit in
                                Text(t(unit.localizationKey)).tag(unit)
                            }
                        }
                        Picker(t("settings.training_distance_unit"), selection: $settingsStore.trainingDistanceUnit) {
                            ForEach(TrainingDistanceUnit.allCases) { unit in
                                Text(t(unit.localizationKey)).tag(unit)
                            }
                        }
                    }
                    }
                }
                if selectedSettingsCategory == .health {
                    Section(header: Text(t("settings.apple_health")), footer: Text(t("settings.apple_health_explanation"))) {
                    Button {
                        if healthKitManager.isAuthorized {
                            openHealthPermissions()
                        } else {
                            healthKitManager.requestAuthorization()
                        }
                    } label: {
                        HStack(spacing: HyseSpacing.medium) {
                            HyseIconBadge(icon: "heart.fill", size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(healthKitManager.isAuthorized ? t("settings.apple_health_connected") : t("settings.apple_health_connect"))
                                    .foregroundStyle(.primary)
                                Text(healthKitManager.isAuthorized ? t("settings.apple_health_manage") : t("settings.apple_health_permissions"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: healthKitManager.isAuthorized ? "arrow.up.forward.app.fill" : "chevron.right")
                                .foregroundStyle(healthKitManager.isAuthorized ? HyseColor.success : .secondary)
                        }
                    }
                    if let error = healthKitManager.authorizationError {
                        Text(error).font(.caption).foregroundStyle(HyseColor.warning)
                    }
                    }
                }
                if selectedSettingsCategory == .training {
                    Section(
                        header: Text(t("settings.unilateral_sets_title")),
                        footer: Text(t("settings.unilateral_sets_explanation"))
                    ) {
                        Toggle(t("settings.unilateral_sets_half"), isOn: $settingsStore.countUnilateralSetsAsHalf)
                    }
                    Section(
                        header: Text(t("settings.training_defaults")),
                        footer: Text(t("settings.training_defaults_explanation"))
                    ) {
                        HStack(alignment: .top, spacing: HyseSpacing.medium) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(HyseColor.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("settings.default_gym"))
                                    .foregroundStyle(.primary)
                                TextField(t("settings.default_gym_placeholder"), text: defaultWorkoutGymNameBinding)
                                    .textInputAutocapitalization(.words)
                                    .foregroundStyle(.primary)
                                if let address = settingsStore.defaultWorkoutGymAddress, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        Button {
                            showingDefaultGymPicker = true
                        } label: {
                            Label(t("settings.default_gym_search"), systemImage: "location.magnifyingglass")
                        }
                        if settingsStore.defaultWorkoutGymName != nil {
                            Button(t("settings.default_gym_remove"), role: .destructive) {
                                clearDefaultWorkoutGym()
                            }
                        }
                        Picker(t("settings.default_workout_visibility"), selection: $settingsStore.defaultWorkoutVisibility) {
                            Text(t("training.completion.visibility.private")).tag("private")
                            Text(t("training.completion.visibility.everyone")).tag("public")
                        }
                    }
                    Section(
                        header: Text(t("settings.apple_watch_training")),
                        footer: Text(t("settings.apple_watch_training_explanation"))
                    ) {
                        Toggle(t("settings.apple_watch_training_automatic_start"), isOn: $settingsStore.automaticallyStartAppleWatchWorkout)
                    }
                    Section(t("training.feedback.settings_title")) {
                    Toggle(t("training.feedback.sound"), isOn: $settingsStore.restSoundEnabled)
                    Toggle(t("training.feedback.notification"), isOn: $settingsStore.restNotificationEnabled)
                    Toggle(t("training.feedback.haptics"), isOn: $settingsStore.restHapticsEnabled)
                    Toggle(t("training.feedback.live_activity"), isOn: $settingsStore.liveActivityEnabled)
                    if settingsStore.restSoundEnabled {
                        Picker(t("training.feedback.variant"), selection: $settingsStore.restSoundVariant) {
                            ForEach(RestSoundVariant.allCases) { variant in Text(t(variant.localizationKey)).tag(variant) }
                        }
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            HStack {
                                Label(t("training.feedback.volume"), systemImage: "speaker.wave.2")
                                Spacer()
                                Text(settingsStore.restSoundVolume, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary)
                            }
                            Slider(value: $settingsStore.restSoundVolume, in: 0.1...1)
                                .accessibilityLabel(t("training.feedback.volume"))
                        }
                        Button {
                            RestFeedbackController.shared.preview(variant: settingsStore.restSoundVariant, volume: settingsStore.restSoundVolume, haptics: settingsStore.restHapticsEnabled)
                        } label: {
                            Label(t("training.feedback.preview"), systemImage: "play.circle")
                        }
                    }
                    Text(t("training.feedback.background_explanation")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if selectedSettingsCategory == .notifications {
                    Section {
                        Toggle(isOn: Binding(
                            get: { settingsStore.motivationNotificationsEnabled },
                            set: { enabled in
                                Task {
                                    var configuration = settingsStore.motivationNotificationConfiguration
                                    configuration = MotivationNotificationConfiguration(
                                        enabled: enabled, frequency: configuration.frequency,
                                        motivationalMessages: configuration.motivationalMessages,
                                        foodLogReminder: configuration.foodLogReminder,
                                        waterReminder: configuration.waterReminder,
                                        plannedTrainingReminder: configuration.plannedTrainingReminder,
                                        missingDailyDataReminder: configuration.missingDailyDataReminder
                                    )
                                    let allowed = await MotivationNotificationManager.shared.setEnabled(
                                        configuration, language: language.language,
                                        hasFoodToday: !calorieStore.entriesForToday().isEmpty
                                    )
                                    settingsStore.motivationNotificationsEnabled = enabled && allowed
                                    if enabled && !allowed {
                                        alertMessage = t("settings.notifications_permission_denied")
                                    }
                                }
                            }
                        )) {
                            Label(t("settings.notifications_enable"), systemImage: "bell.badge")
                        }
                        if settingsStore.motivationNotificationsEnabled {
                            Toggle(t("settings.pure_motivation"), isOn: $settingsStore.motivationalMessagesEnabled)
                            if settingsStore.motivationalMessagesEnabled {
                                Picker(t("settings.notification_frequency"), selection: $settingsStore.motivationNotificationFrequency) {
                                    ForEach(MotivationNotificationFrequency.allCases) { frequency in
                                        Text(t(frequency.localizationKey)).tag(frequency)
                                    }
                                }
                            }
                            if settingsStore.trackingInterest.includesNutrition {
                                Toggle(t("settings.food_log_reminder"), isOn: $settingsStore.foodLogReminderEnabled)
                                if settingsStore.foodLogReminderEnabled {
                                    Text(t("settings.food_log_reminder_explanation")).font(.caption).foregroundStyle(.secondary)
                                }
                                Toggle(t("settings.water_reminder"), isOn: $settingsStore.waterReminderEnabled)
                                Toggle(t("settings.missing_daily_data_reminder"), isOn: $settingsStore.missingDailyDataReminderEnabled)
                            }
                            if settingsStore.trackingInterest.includesTraining {
                                Toggle(t("settings.planned_training_reminder"), isOn: $settingsStore.plannedTrainingReminderEnabled)
                                Toggle(isOn: Binding(
                                    get: { settingsStore.monthlyTrainingReportNotificationsEnabled },
                                    set: { enabled in
                                        Task {
                                            let allowed = await MonthlyTrainingReportNotificationManager.shared.setEnabled(enabled, language: language.language)
                                            settingsStore.monthlyTrainingReportNotificationsEnabled = enabled && allowed
                                            if enabled && !allowed { alertMessage = t("settings.notifications_permission_denied") }
                                        }
                                    }
                                )) {
                                    Label(t("training.monthly_report.notifications"), systemImage: "calendar.badge.clock")
                                }
                                Text(t("training.monthly_report.notifications_explanation"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if settingsStore.trackingInterest == .both {
                                Text(t("settings.additional_reminders_explanation"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if authManager.isLoggedIn {
                            NavigationLink { HyseNotificationCenterView() } label: {
                                Label(t("notifications.open_center"), systemImage: "tray.full")
                            }
                            if settingsStore.trackingInterest.includesTraining {
                                Toggle(t("notifications.settings.community_news"), isOn: pushPreferenceBinding(\.communityNewsNotificationsEnabled))
                                Toggle(t("notifications.settings.workout_likes"), isOn: pushPreferenceBinding(\.workoutLikeNotificationsEnabled))
                                Toggle(t("notifications.settings.workout_comments"), isOn: pushPreferenceBinding(\.workoutCommentNotificationsEnabled))
                                Toggle(t("notifications.settings.friend_activity"), isOn: pushPreferenceBinding(\.friendActivityNotificationsEnabled))
                                Text(t("notifications.settings.explanation")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text(t("settings.motivation_notifications_explanation"))
                    }
                    Section(t("training.feedback.settings_title")) {
                        Toggle(t("training.feedback.notification"), isOn: $settingsStore.restNotificationEnabled)
                    }
                }
                if selectedSettingsCategory == .privacy {
                    Section(t("settings.privacy_legal")) {
                    Label(t("privacy_data.essential_active"), systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                    Link(destination: language.isGerman ? HyseLegalLinks.termsGerman : HyseLegalLinks.termsEnglish) {
                        Label(t("settings.terms_use"), systemImage: "doc.text")
                    }
                    Link(destination: language.isGerman ? HyseLegalLinks.privacyGerman : HyseLegalLinks.privacyEnglish) {
                        Label(t("settings.privacy_policy"), systemImage: "hand.raised")
                    }
                    Button { showingPublicContentReport = true } label: {
                        Label(t("content_reports.title"), systemImage: "flag")
                    }
                    if authManager.isLoggedIn {
                        Button { showingContentReports = true } label: {
                            Label(t("content_reports.my_reports"), systemImage: "flag")
                        }
                    }
                    Label(t("legal_consent.cloud_sync"), systemImage: "heart.text.clipboard")
                    Text(t("legal_consent.cloud_sync_purpose")).font(.caption).foregroundStyle(.secondary)
                    Toggle(t("legal_consent.marketing"), isOn: Binding(
                        get: { accountData.marketingConsent },
                        set: { accountData.updateMarketingConsent($0, language: language.language) }
                    ))
                    Text(t("legal_consent.marketing_purpose")).font(.caption).foregroundStyle(.secondary)
                    Text(t("privacy_data.no_analytics_ads")).font(.caption).foregroundStyle(.secondary)
                    if let updated = accountData.marketingConsentUpdatedAt {
                        LabeledContent(t("legal_consent.last_changed"), value: updated.formatted(.dateTime.day().month().year().hour().minute().locale(language.locale)))
                            .font(.caption)
                        Text(t("legal_consent.preference_receipt", privacyReceiptVersion, accountData.marketingConsentLanguage.uppercased()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Button { accountData.resetOnboardingForReplay() } label: {
                        Label(t("settings.replay_tutorial"), systemImage: "sparkles.rectangle.stack")
                    }
                    Button {
                        exportPersonalData()
                    } label: {
                        if isExporting {
                            HStack { ProgressView(); Text(t("privacy_data.export_preparing")) }
                        } else {
                            Label(t("privacy_data.export_now"), systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)
                    Text(t("privacy_data.export_local_note")).font(.caption).foregroundStyle(.secondary)
                    if authManager.isLoggedIn {
                        Link(destination: URL(string: "mailto:\(HyseConfiguration.contactEmail)?subject=Hyse%20data%20export%20request")!) {
                            Label(t("privacy_data.request_server_export"), systemImage: "envelope")
                        }
                    }
                    if accountData.isSyncing { HStack { ProgressView(); Text(t("settings.syncing_account_settings")) } }
                    if let syncError = accountData.syncError { Text(syncError).font(.caption).foregroundStyle(HyseColor.warning) }
                    }
                }

                if selectedSettingsCategory == .about {
                    Section {
                        Text(t("settings.hyse_helps_you_track_meals_nutrition_clearly"))
                            .foregroundStyle(.secondary)
                        Text(t("settings.hyse_training_tracker_description"))
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(t("settings.about_hyse"))
                    }

                    Section {
                        Text(t("settings.support_explanation"))
                            .foregroundStyle(.secondary)
                        externalLink(
                            t("settings.open_support"),
                            icon: "questionmark.circle.fill",
                            url: language.isGerman ? HyseLegalLinks.supportGerman : HyseLegalLinks.supportEnglish
                        )
                    } header: {
                        Text(t("settings.support"))
                    }

                    Section {
                        Text(t("settings.data_sources.open_food_facts_attribution"))
                            .foregroundStyle(.secondary)
                        externalLink(
                            t("settings.data_sources.open_food_facts_link"),
                            icon: "leaf.fill",
                            url: HyseLegalLinks.openFoodFacts
                        )
                        externalLink(
                            t("settings.data_sources.odbl_link"),
                            icon: "doc.text.fill",
                            url: HyseLegalLinks.openDatabaseLicense
                        )
                    } header: {
                        Text(t("settings.data_sources"))
                    }

                    Section {
                        externalLink("Instagram", icon: "camera.fill", url: HyseLegalLinks.instagram)
                        externalLink("TikTok", icon: "music.note", url: HyseLegalLinks.tiktok)
                        externalLink("YouTube", icon: "play.rectangle.fill", url: HyseLegalLinks.youtube)
                    } header: {
                        Text(t("settings.social_media"))
                    } footer: {
                        Text(t("settings.social_media_explanation"))
                    }

                    Section(t("settings.legal")) {
                        externalLink(t("settings.privacy_policy"), icon: "hand.raised.fill", url: language.isGerman ? HyseLegalLinks.privacyGerman : HyseLegalLinks.privacyEnglish)
                        externalLink(t("settings.terms_use"), icon: "doc.text.fill", url: language.isGerman ? HyseLegalLinks.termsGerman : HyseLegalLinks.termsEnglish)
                        externalLink(t("settings.legal_notice"), icon: "building.2.fill", url: language.isGerman ? HyseLegalLinks.legalNoticeGerman : HyseLegalLinks.legalNoticeEnglish)
                    }

                    Section(t("settings.easter_egg")) {
                        Button { showingDoenerClicker = true } label: {
                            Label(t("settings.open_kebab_clicker"), systemImage: "gamecontroller")
                        }
                    }
                }

                if selectedSettingsCategory == .goals {
                    Section {
                        Button { showingProfileSetup = true } label: {
                            Label(t("first_action.setup_goals"), systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                    GoalsSettingsCategoryView(
                        settingsStore: settingsStore,
                        trackingWindowClock: trackingWindowClock,
                        categoryStore: categoryStore,
                        foodStore: foodStore,
                        calorieStore: calorieStore,
                        recipeStore: recipeStore,
                        frequencyStore: frequencyStore,
                        baseGoalText: $baseGoalText,
                        trainingDayCalorieAdjustmentText: $trainingDayCalorieAdjustmentText,
                        restDayCalorieAdjustmentText: $restDayCalorieAdjustmentText,
                        trainingDayAddsCalories: $trainingDayAddsCalories,
                        restDayAddsCalories: $restDayAddsCalories,
                        fixedSurplusText: $fixedSurplusText,
                        fixedDeficitText: $fixedDeficitText,
                        calorieLimitBufferText: $calorieLimitBufferText,
                        lowRemainingTrackingThresholdText: $lowRemainingTrackingThresholdText,
                        carbsPctText: $carbsPctText,
                        proteinPctText: $proteinPctText,
                        fatPctText: $fatPctText,
                        waterGoalText: $waterGoalText,
                        waterGlassSizeText: $waterGlassSizeText,
                        addedSugarGoalText: $addedSugarGoalText,
                        fruitSugarGoalText: $fruitSugarGoalText,
                        saltGoalText: $saltGoalText,
                        fiberGoalText: $fiberGoalText,
                        saturatedFatGoalText: $saturatedFatGoalText,
                        hasNutritionSettingsCode: $hasNutritionSettingsCode,
                        nutritionProtectedScopes: $nutritionProtectedScopes,
                        unlockedNutritionScopes: $unlockedNutritionScopes,
                        nutritionLockManagementUnlocked: $nutritionLockManagementUnlocked,
                        showingRemoveNutritionCodeConfirmation: $showingRemoveNutritionCodeConfirmation,
                        settingsSavedMessage: $settingsSavedMessage,
                        presentNutritionCodePrompt: { presentNutritionCodePrompt($0) },
                        preparePhaseEditor: { preparePhaseEditor() },
                        saveMacroSettings: {
                            accountData.stageSettings(settingsStore, language: language)
                            scheduleDeferredSettingsSync()
                        }
                    )
                    Section {
                        if let plan = settingsStore.scheduledCaloriePhase {
                            LabeledContent(t("calorie_plan.phase"), value: t(plan.kind == .cut ? "calorie_plan.cut" : "calorie_plan.bulk"))
                            if plan.trigger != .weight, let date = plan.startDate {
                                LabeledContent(t("calorie_plan.date"), value: date.formatted(date: .abbreviated, time: .shortened))
                            }
                            if plan.trigger != .date, let weight = plan.triggerWeightKilograms {
                                LabeledContent(t("calorie_plan.weight"), value: "\(plan.kind == .cut ? "≥" : "≤") \(weight.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) kg")
                            }
                            if plan.trigger == .whicheverFirst {
                                Text(t("calorie_plan.whichever_first_explanation"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let macros = plan.macroGoals {
                                LabeledContent(t("calorie_plan.macros"), value: t(macros.plan.mode == .percentages
                                    ? "calorie_plan.macro_percentages" : "calorie_plan.macro_flexible"))
                                LabeledContent(t("quick_entry.carbohydrates"), value: plannedMacroValue(macros,
                                    fixed: macros.plan.carbsFixedGrams, share: macros.plan.carbsRemainingPercent,
                                    percentage: macros.carbsPercentage))
                                LabeledContent(t("settings.protein"), value: plannedMacroValue(macros,
                                    fixed: macros.plan.proteinFixedGrams, share: macros.plan.proteinRemainingPercent,
                                    percentage: macros.proteinPercentage))
                                LabeledContent(t("quick_entry.fat"), value: plannedMacroValue(macros,
                                    fixed: macros.plan.fatFixedGrams, share: macros.plan.fatRemainingPercent,
                                    percentage: macros.fatPercentage))
                            }
                            Button(t("calorie_plan.edit")) { showingScheduledPhaseEditor = true }
                            Button(t("calorie_plan.cancel"), role: .destructive) {
                                settingsStore.setScheduledCaloriePhase(nil)
                                accountData.syncSettings(settingsStore, language: language)
                            }
                        } else {
                            Button { showingScheduledPhaseEditor = true } label: {
                                Label(t("calorie_plan.create"), systemImage: "calendar.badge.clock")
                            }
                        }
                    } header: {
                        Text(t("calorie_plan.title"))
                    } footer: {
                        Text(t("calorie_plan.explanation"))
                    }
                }

                if selectedSettingsCategory == .goals {
                    Section(language.text("settings.home_content")) {
                        NavigationLink {
                            DashboardLayoutView(settingsStore: settingsStore)
                        } label: {
                            HStack(spacing: HyseSpacing.medium) {
                                HyseIconBadge(icon: "rectangle.3.group", size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("settings.customise_home_screen"))
                                        .foregroundStyle(.primary)
                                    Text(t("settings.home_layout_explanation"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if selectedSettingsCategory == .goals {
                    Section(t("content.meals")) {
                    ForEach(categoryStore.categories) { cat in
                        Button { editingCategory = cat } label: { HStack { Text(cat.localizedName).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if calorieStore.entries.contains(where: { $0.categoryId == cat.id }) {
                                    categoryDeletionMessage = t("settings.meal_still_contains_entries_delete_move_them")
                                } else if categoryStore.categories.count <= 1 {
                                    categoryDeletionMessage = t("settings.at_least_one_meal_must_remain")
                                } else {
                                    categoryStore.deleteCategory(id: cat.id)
                                }
                            } label: { Label(t("settings.delete"), systemImage: "trash") }
                        }
                    }

                    HStack {
                        TextField(t("settings.new_meal"), text: $newCategoryName)
                        Button(t("settings.add")) {
                            addCategory()
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Button(t("settings.restore_default_meal_targets")) {
                        categoryStore.resetStandardTargets()
                    }
                    .font(.footnote.weight(.medium))
                    }
                }
                }
                .hyseGlassListRows(accent: selectedSettingsCategory?.color)
                })
                .hyseForm()
            }
        }
            .navigationTitle(selectedSettingsCategory.map { t($0.titleKey) } ?? t("content.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if selectedSettingsCategory != nil {
                        Group {
                            if isSavingSettings {
                                ProgressView()
                                    .accessibilityLabel(t("settings.saving"))
                            } else if settingsSavedMessage != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(HyseColor.success)
                                    .accessibilityLabel(t("settings.saved"))
                            }
                        }
                    }
                }
            }
            .sheet(item: $editingCategory) { cat in
                CategoryEditView(categoryStore: categoryStore, category: cat)
            }
            .sheet(isPresented: $showingDoenerClicker) {
                NavigationStack {
                    DoenerClickerView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("add_entry.done")) { showingDoenerClicker = false } } }
                }
            }
            .sheet(isPresented: $showingProfileSetup) {
                ProfileSetupOnboardingView(settings: settingsStore, trainingStore: trainingStore, allowsExistingProfileUpdate: true) {
                    showingProfileSetup = false
                }
            }
            .sheet(isPresented: $showingAccount) {
                LoginView()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showingExportShare) {
                HyseExportShareSheet(urls: exportURLs)
            }
            .sheet(isPresented: $showingEmailChange) {
                EmailChangeView()
                    .environmentObject(authManager)
                    .environmentObject(language)
            }
            .sheet(isPresented: $showingPasswordManagement) {
                PasswordManagementView().environmentObject(authManager).environmentObject(language)
            }
            .sheet(isPresented: $showingContentReports) {
                NavigationStack { ContentReportsView() }
                    .environmentObject(authManager)
                    .environmentObject(language)
            }
            .sheet(isPresented: $showingPublicContentReport) {
                PublicContentReportView()
                    .environmentObject(authManager)
                    .environmentObject(language)
            }
            .sheet(isPresented: $showingPhaseEditor) {
                phaseEditorSheet
            }
            .sheet(isPresented: $showingScheduledPhaseEditor) {
                ScheduledCaloriePhaseEditor(settingsStore: settingsStore,
                                            latestWeightKilograms: latestPlannedWeight) { plan in
                    settingsStore.setScheduledCaloriePhase(plan)
                    if plan.goalMode != .dynamic || plan.dynamicMode != .deficit {
                        _ = settingsStore.activateScheduledCaloriePhaseIfDue(latestWeightKilograms: latestPlannedWeight)
                    }
                    refreshCalorieGoalDraftValues()
                    accountData.syncSettings(settingsStore, language: language)
                    showingScheduledPhaseEditor = false
                }
                .environmentObject(language)
            }
            .sheet(isPresented: $showingDefaultGymPicker) {
                NavigationStack {
                    NearbyGymPickerView(selectedGymID: defaultWorkoutGymSelectionID) { gym in
                        settingsStore.defaultWorkoutGymName = gym.name
                        settingsStore.defaultWorkoutGymAddress = gym.address.isEmpty ? nil : gym.address
                        settingsStore.defaultWorkoutGymLatitude = gym.coordinate.latitude
                        settingsStore.defaultWorkoutGymLongitude = gym.coordinate.longitude
                    }
                }
                .environmentObject(language)
            }
            .sheet(item: $nutritionCodePrompt) { prompt in
                nutritionCodeSheet(prompt)
            }
            .sheet(isPresented: $showingLogoutConfirmation) {
                LogoutConfirmationView(
                    foodStore: foodStore,
                    calorieStore: calorieStore,
                    dailyFoodStore: dailyFoodStore,
                    isSigningOut: $isSigningOut
                ) {
                    if !flushPendingSettings() {
                        accountData.syncSettings(settingsStore, language: language)
                    }
                    await accountData.waitForPendingSettingsSync()
                    await streakRewards.flushPendingState()
                    await trainingStore.flushPendingSync()
                    authManager.logout()
                    showingLogoutConfirmation = false
                }
                .environmentObject(language)
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(isSigningOut)
            }
            .alert(t("settings.error"), isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
                Button(t("common.ok")) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .alert(t("settings.meal_cannot_deleted"), isPresented: Binding(get: { categoryDeletionMessage != nil }, set: { if !$0 { categoryDeletionMessage = nil } })) {
                Button(t("common.ok")) { categoryDeletionMessage = nil }
            } message: { Text(categoryDeletionMessage ?? "") }
            .confirmationDialog(
                t("nutrition_lock.remove_code"),
                isPresented: $showingRemoveNutritionCodeConfirmation,
                titleVisibility: .visible
            ) {
                Button(t("nutrition_lock.remove_code"), role: .destructive) {
                    NutritionSettingsLockStore.removePasscode()
                    hasNutritionSettingsCode = false
                    nutritionProtectedScopes.removeAll()
                    unlockedNutritionScopes.removeAll()
                    nutritionLockManagementUnlocked = false
                }
                Button(t("app_tabs.cancel"), role: .cancel) {}
            } message: {
                Text(t("nutrition_lock.remove_explanation"))
            }
            .confirmationDialog(
                t("settings.permanently_delete_account"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(t("settings.delete_account_synced_data"), role: .destructive) {
                    Task {
                        do {
                            try await authManager.deleteAccount()
                        } catch {
                            alertMessage = error.localizedDescription
                        }
                    }
                }
                Button(t("app_tabs.cancel"), role: .cancel) {}
            } message: {
                Text(t("settings.delete_account_explanation"))
            }
            .onChange(of: settingsStore.selectedNutritionProfileIDs) { _, _ in
                refreshDraftValues()
            }
            .onChange(of: settingsStore.scheduledCaloriePhase) { oldPlan, newPlan in
                if oldPlan != nil && newPlan == nil { refreshCalorieGoalDraftValues() }
            }
            .onChange(of: scenePhase) { _, phase in
                trackingWindowClock = Date()
                guard phase != .active else { return }
                unlockedNutritionScopes.removeAll()
                nutritionLockManagementUnlocked = false
                nutritionCodePrompt = nil
            }
            .onChange(of: settingsStore.defaultLiquidUnit) { oldUnit, newUnit in
                waterGoalText = convertedVolumeText(waterGoalText, from: oldUnit, to: newUnit)
                waterGlassSizeText = convertedVolumeText(waterGlassSizeText, from: oldUnit, to: newUnit)
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
                trackingWindowClock = now
            }
            .onChange(of: language.language) { _, _ in
                MotivationNotificationManager.shared.applyStoredPreference(
                    settingsStore.motivationNotificationConfiguration,
                    language: language.language,
                    hasFoodToday: !calorieStore.entriesForToday().isEmpty
                )
                MonthlyTrainingReportNotificationManager.shared.applyStoredPreference(
                    settingsStore.monthlyTrainingReportNotificationsEnabled,
                    language: language.language
                )
                accountData.stageSettings(settingsStore, language: language)
                scheduleDeferredSettingsSync()
            }
            .onChange(of: trainingPreferencesSignature) { _, _ in
                accountData.stageSettings(settingsStore, language: language)
                scheduleDeferredSettingsSync()
            }
            .onChange(of: settingsDraftSignature) { _, _ in
                settingsSavedMessage = nil
                scheduleAutomaticSave()
            }
            .onDisappear {
                flushPendingSettings()
                unlockedNutritionScopes.removeAll()
                nutritionLockManagementUnlocked = false
            }
    }

    private var trainingPreferencesSignature: String {
        [
            String(settingsStore.restSoundEnabled), String(settingsStore.restNotificationEnabled),
            String(settingsStore.restHapticsEnabled),
            settingsStore.restSoundVariant.rawValue, String(format: "%.2f", settingsStore.restSoundVolume),
            String(settingsStore.liveActivityEnabled), String(settingsStore.automaticallyStartAppleWatchWorkout),
            settingsStore.dashboardSectionIDs.joined(separator: ","),
            String(settingsStore.motivationNotificationsEnabled), settingsStore.motivationNotificationFrequency.rawValue,
            String(settingsStore.motivationalMessagesEnabled), String(settingsStore.foodLogReminderEnabled),
            String(settingsStore.waterReminderEnabled), String(settingsStore.plannedTrainingReminderEnabled),
            String(settingsStore.missingDailyDataReminderEnabled),
            String(settingsStore.communityNewsNotificationsEnabled),
            String(settingsStore.hyseUpdateNotificationsEnabled), String(settingsStore.workoutLikeNotificationsEnabled),
            String(settingsStore.workoutCommentNotificationsEnabled),
            String(settingsStore.friendActivityNotificationsEnabled),
            String(settingsStore.monthlyTrainingReportNotificationsEnabled),
            settingsStore.visibleDashboardSectionIDs.sorted().joined(separator: ","),
            settingsStore.visibleNutritionMetricIDs.sorted().joined(separator: ","),
            settingsStore.homeAdditionalNutritionMetricIDs.sorted().joined(separator: ","),
            settingsStore.selectedNutritionProfileIDs.sorted().joined(separator: ","),
            settingsStore.nutritionActivityLevel.rawValue,
            settingsStore.trackingInterest.rawValue,
            settingsStore.calorieGoalMode.rawValue, settingsStore.dynamicCalorieTargetMode.rawValue,
            String(settingsStore.enforceCalorieLimit),
            settingsStore.defaultFoodUnit.rawValue, settingsStore.defaultLiquidUnit.rawValue,
            settingsStore.trainingWeightUnit.rawValue, settingsStore.trainingDistanceUnit.rawValue,
            String(settingsStore.countUnilateralSetsAsHalf),
            settingsStore.appTheme.rawValue,
            settingsStore.defaultWorkoutGymName ?? "", settingsStore.defaultWorkoutGymAddress ?? "",
            String(settingsStore.defaultWorkoutGymLatitude ?? 0), String(settingsStore.defaultWorkoutGymLongitude ?? 0),
            settingsStore.defaultWorkoutVisibility
        ].joined(separator: "|")
    }

    private var defaultWorkoutGymSelectionID: String? {
        guard let name = settingsStore.defaultWorkoutGymName,
              let latitude = settingsStore.defaultWorkoutGymLatitude,
              let longitude = settingsStore.defaultWorkoutGymLongitude else { return nil }
        return "\(name)|\(latitude)|\(longitude)"
    }

    private var defaultWorkoutGymNameBinding: Binding<String> {
        Binding(
            get: { settingsStore.defaultWorkoutGymName ?? "" },
            set: { value in
                guard value != settingsStore.defaultWorkoutGymName else { return }
                settingsStore.defaultWorkoutGymName = value.isEmpty ? nil : value
                settingsStore.defaultWorkoutGymAddress = nil
                settingsStore.defaultWorkoutGymLatitude = nil
                settingsStore.defaultWorkoutGymLongitude = nil
            }
        )
    }

    private func exportPersonalData() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                let urls = try await HyseDataExport.create(
                    calories: calorieStore, training: trainingStore, health: healthKitManager,
                    foods: foodStore, recipes: recipeStore, categories: categoryStore,
                    mealPlan: mealPlanStore, water: WaterStore(), settings: settingsStore
                )
                if let previous = exportURLs.first?.deletingLastPathComponent() {
                    try? FileManager.default.removeItem(at: previous)
                }
                exportURLs = urls
                showingExportShare = true
            } catch {
                alertMessage = t("privacy_data.export_failed")
            }
            isExporting = false
        }
    }

    private func clearDefaultWorkoutGym() {
        settingsStore.defaultWorkoutGymName = nil
        settingsStore.defaultWorkoutGymAddress = nil
        settingsStore.defaultWorkoutGymLatitude = nil
        settingsStore.defaultWorkoutGymLongitude = nil
    }

    private func pushPreferenceBinding(_ keyPath: ReferenceWritableKeyPath<UserSettingsStore, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore[keyPath: keyPath] },
            set: { enabled in
                Task {
                    if enabled {
                        let allowed = await CommunityPushNotificationManager.shared.requestAndRegister(auth: authManager)
                        settingsStore[keyPath: keyPath] = allowed
                        if !allowed { alertMessage = t("training.community.notifications_denied") }
                    } else {
                        settingsStore[keyPath: keyPath] = false
                        let anyEnabled = settingsStore.communityNewsNotificationsEnabled
                            || settingsStore.workoutLikeNotificationsEnabled
                            || settingsStore.workoutCommentNotificationsEnabled
                            || settingsStore.friendActivityNotificationsEnabled
                        if !anyEnabled { await CommunityPushNotificationManager.shared.disable(auth: authManager) }
                    }
                    await HyseNotificationService.shared.updatePreferences(settings: settingsStore, token: authManager.token)
                }
            }
        )
    }

    private func presentNutritionCodePrompt(_ prompt: NutritionCodePrompt) {
        nutritionCode = ""
        nutritionCodeConfirmation = ""
        nutritionCodeError = nil
        nutritionCodePrompt = prompt
    }

    private func openHealthPermissions() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                Task { @MainActor in
                    alertMessage = t("settings.apple_health_open_failed")
                }
            }
        }
    }

    private func nutritionCodeSheet(_ prompt: NutritionCodePrompt) -> some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(t("nutrition_lock.code"), text: $nutritionCode)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                    if prompt.needsConfirmation {
                        SecureField(t("nutrition_lock.confirm_code"), text: $nutritionCodeConfirmation)
                            .keyboardType(.numberPad)
                            .textContentType(.password)
                    }
                    if let nutritionCodeError {
                        Text(nutritionCodeError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(prompt.needsConfirmation ? t("nutrition_lock.code_requirements") : t("nutrition_lock.unlock_explanation"))
                }
                if prompt.allowsReset {
                    Section {
                        Button {
                            resetForgottenNutritionCode()
                        } label: {
                            if isResettingNutritionCode {
                                ProgressView()
                            } else {
                                Text(t("nutrition_lock.forgot_code"))
                            }
                        }
                        .disabled(isResettingNutritionCode)
                    } footer: {
                        Text(t("nutrition_lock.reset_explanation"))
                    }
                }
            }
            .navigationTitle(nutritionCodePromptTitle(prompt))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { nutritionCodePrompt = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(prompt.needsConfirmation ? t("recipe_editor.save") : t("nutrition_lock.unlock")) {
                        submitNutritionCode(prompt)
                    }
                    .disabled(!NutritionSettingsLockStore.isValid(nutritionCode))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func nutritionCodePromptTitle(_ prompt: NutritionCodePrompt) -> String {
        switch prompt {
        case .setup: t("nutrition_lock.setup")
        case .manage: t("nutrition_lock.manage")
        case .unlock: t("nutrition_lock.unlock")
        case .change: t("nutrition_lock.change_code")
        case .reset: t("nutrition_lock.reset_code")
        }
    }

    private func resetForgottenNutritionCode() {
        guard !isResettingNutritionCode, NutritionSettingsLockStore.hasPasscode else { return }
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            nutritionCodeError = t("nutrition_lock.reset_unavailable")
            return
        }
        isResettingNutritionCode = true
        nutritionCodeError = nil
        Task { @MainActor in
            defer { isResettingNutritionCode = false }
            do {
                guard try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: t("nutrition_lock.reset_auth_reason")
                ) else { return }
                guard NutritionSettingsLockStore.hasPasscode,
                      nutritionCodePrompt?.allowsReset == true else { return }
                presentNutritionCodePrompt(.reset)
            } catch {
                let code = (error as? LAError)?.code
                if code != .userCancel && code != .systemCancel && code != .appCancel {
                    nutritionCodeError = t("nutrition_lock.reset_failed")
                }
            }
        }
    }

    private func submitNutritionCode(_ prompt: NutritionCodePrompt) {
        nutritionCodeError = nil
        switch prompt {
        case .setup, .change, .reset:
            guard nutritionCode == nutritionCodeConfirmation else {
                nutritionCodeError = t("nutrition_lock.codes_do_not_match")
                return
            }
            do {
                try NutritionSettingsLockStore.setPasscode(nutritionCode)
                hasNutritionSettingsCode = true
                nutritionLockManagementUnlocked = true
                nutritionCodePrompt = nil
            } catch {
                nutritionCodeError = t("nutrition_lock.save_failed")
            }
        case .manage:
            guard NutritionSettingsLockStore.verify(nutritionCode) else {
                nutritionCodeError = t("nutrition_lock.wrong_code")
                return
            }
            nutritionLockManagementUnlocked = true
            nutritionCodePrompt = nil
        case .unlock(let scope):
            guard NutritionSettingsLockStore.verify(nutritionCode) else {
                nutritionCodeError = t("nutrition_lock.wrong_code")
                return
            }
            unlockedNutritionScopes.insert(scope)
            nutritionCodePrompt = nil
        }
    }

    private var settingsDraftSignature: String {
        [
            baseGoalText, settingsStore.calorieGoalMode.rawValue, settingsStore.dynamicCalorieTargetMode.rawValue,
            trainingDayCalorieAdjustmentText, restDayCalorieAdjustmentText, String(trainingDayAddsCalories), String(restDayAddsCalories), fixedSurplusText, fixedDeficitText, calorieLimitBufferText, lowRemainingTrackingThresholdText, phaseBodyFatText, phaseWeightText,
            String(settingsStore.blockFoodTrackingWhileFastingEnabled),
            String(settingsStore.foodTrackingWindowEnabled),
            String(settingsStore.foodTrackingWindowStartMinutes),
            String(settingsStore.foodTrackingWindowEndMinutes),
            String(settingsStore.hideNutritionOutsideTrackingWindow),
            String(settingsStore.lockTrackingWindowSettingsOutsideHours),
            String(settingsStore.lowRemainingTrackingLockEnabled),
            String(settingsStore.lowRemainingTrackingLockStartMinutes),
            carbsPctText, proteinPctText, fatPctText,
            waterGoalText, waterGlassSizeText,
            addedSugarGoalText, fruitSugarGoalText, saltGoalText,
            fiberGoalText, saturatedFatGoalText
        ].joined(separator: "|")
    }

    private var settingsOverview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                settingsOverviewHero
                ForEach(settingsOverviewGroups) { group in
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        settingsGroupHeader(group.titleKey)
                        ForEach(group.categories) { category in
                            settingsCategoryTile(
                                category,
                                index: visibleSettingsCategories.firstIndex(of: category) ?? 0
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, HyseSpacing.page)
            .padding(.top, HyseSpacing.medium)
            .padding(.bottom, 36)
        }
    }

    private func settingsGroupHeader(_ titleKey: String) -> some View {
        HStack {
            Text(t(titleKey).uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Spacer()
            Rectangle()
                .fill(HyseColor.accent)
                .frame(width: 38, height: 3)
        }
        .padding(.horizontal, 2)
    }

    private var settingsOverviewHero: some View {
        NavigationLink {
            settingsDestination(.account)
        } label: {
            HyseCard(accent: HyseColor.accent) {
                HStack(spacing: HyseSpacing.large) {
                    ProfileAvatarView(size: 58, editable: false)
                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        Text(authManager.isLoggedIn ? authManager.accountName : t("settings.sign_in_create_account"))
                            .font(.title2.bold()).foregroundStyle(.primary)
                        Text(authManager.isLoggedIn ? authManager.accountEmail : t("settings.you_can_use_hyse_without_account_local"))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(HyseColor.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .hyseTourTarget(.settings)
    }

    private func settingsCategoryTile(_ category: SettingsCategory, index: Int) -> some View {
        NavigationLink { settingsDestination(category) } label: {
            HyseCard(accent: category.color) {
                HStack(alignment: .center, spacing: HyseSpacing.large) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(.title2, design: .monospaced, weight: .light))
                        .foregroundStyle(category.color)
                        .frame(width: 34, alignment: .leading)
                    HyseIconBadge(icon: category.icon, color: category.color, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t(category.titleKey))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(t(category.subtitleKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(category.color)
                }
            }
        }
        .buttonStyle(HyseLiftButtonStyle())
        .accessibilityHint(t(category.subtitleKey))
    }

    private func settingsDestination(_ category: SettingsCategory) -> some View {
        SettingsView(
            settingsStore: settingsStore, categoryStore: categoryStore, foodStore: foodStore,
            calorieStore: calorieStore, recipeStore: recipeStore, frequencyStore: frequencyStore,
            healthKitManager: healthKitManager, initialCategory: category
        )
    }

    private func settingsDetailHeader(_ category: SettingsCategory) -> some View {
        HyseCard(accent: category.color) {
            HStack(spacing: HyseSpacing.large) {
                HyseIconBadge(icon: category.icon, color: category.color, size: 50)
                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    Text(t(category.titleKey))
                        .font(.title3.bold())
                    Text(t(category.subtitleKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HyseInfoButton(
                    title: t(category.titleKey),
                    message: t(category.infoKey),
                    tint: category.color
                )
            }
        }
    }

    private func externalLink(_ title: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityHint(t("settings.opens_website_in_browser"))
    }

    private func addCategory() {
        categoryStore.addCategory(name: newCategoryName)
        newCategoryName = ""
    }

    private var phaseEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HyseSectionHeading(
                        title: t(settingsStore.dynamicDeficitPhase == nil ? "calorie_target.start_phase" : "calorie_target.start_new_phase"),
                        subtitle: t("calorie_target.phase_editor_subtitle"),
                        icon: "chart.line.downtrend.xyaxis",
                        infoTitle: t("calorie_target.new_phase_confirmation_title"),
                        infoMessage: t("calorie_target.settings_explanation")
                    )
                }
                .listRowBackground(Color.clear)

                Section {
                    HStack {
                        Label(t("calorie_target.body_fat_input"), systemImage: "percent")
                        Spacer()
                        TextField(t("calorie_target.body_fat_placeholder"), text: $phaseBodyFatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text("%").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label(t("calorie_target.weight_input"), systemImage: "scalemass")
                        Spacer()
                        TextField(t("calorie_target.weight_placeholder"), text: $phaseWeightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text(t("unit.kg_short")).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(t("calorie_target.new_start_values"))
                } footer: {
                    Text(t("calorie_target.phase_values_editable_hint"))
                }

                if let bodyFat = localizedDouble(phaseBodyFatText),
                   let weight = localizedDouble(phaseWeightText),
                   bodyFat > 0, bodyFat < 100, weight > 0 {
                    Section(t("calorie_target.preview")) {
                        LabeledContent(t("calorie_target.initial_body_fat"), value: bodyFat.formatted(.number.precision(.fractionLength(0...1))) + " %")
                        LabeledContent(t("calorie_target.initial_weight"), value: weight.formatted(.number.precision(.fractionLength(0...1))) + " " + t("unit.kg_short"))
                    }
                }
            }
            .hyseForm()
            .navigationTitle(t(settingsStore.dynamicDeficitPhase == nil ? "calorie_target.start_phase" : "calorie_target.start_new_phase"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { showingPhaseEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("calorie_target.use_start_values")) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        if settingsStore.dynamicDeficitPhase == nil {
                            startDynamicPhase()
                        } else {
                            showingPhaseResetConfirmation = true
                        }
                    }
                    .bold()
                    .disabled(!phaseDraftIsValid)
                }
            }
            .confirmationDialog(
                t("calorie_target.new_phase_confirmation_title"),
                isPresented: $showingPhaseResetConfirmation,
                titleVisibility: .visible
            ) {
                Button(t("calorie_target.start_new_phase"), role: .destructive) { startDynamicPhase() }
                Button(t("app_tabs.cancel"), role: .cancel) {}
            } message: {
                Text(t("calorie_target.new_phase_confirmation_message"))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(showingPhaseResetConfirmation)
    }

    private var phaseDraftIsValid: Bool {
        guard let bodyFat = localizedDouble(phaseBodyFatText),
              let weight = localizedDouble(phaseWeightText) else { return false }
        return bodyFat > 0 && bodyFat < 100 && weight > 0
    }

    private func preparePhaseEditor() {
        if let phase = settingsStore.dynamicDeficitPhase {
            phaseBodyFatText = (phase.initialBodyFatFraction * 100)
                .formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))
            phaseWeightText = phase.initialWeightKilograms
                .formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))
        }
        showingPhaseResetConfirmation = false
        showingPhaseEditor = true
    }

    private func refreshDraftValues() {
        carbsPctText = String(settingsStore.carbsPercentage)
        proteinPctText = String(settingsStore.proteinPercentage)
        fatPctText = String(settingsStore.fatPercentage)
        calorieLimitBufferText = String(format: "%.0f", settingsStore.calorieLimitBufferKilocalories)
        fixedDeficitText = String(format: "%.0f", settingsStore.fixedCalorieDeficit)
        trainingDayCalorieAdjustmentText = String(format: "%.0f", abs(settingsStore.trainingDayCalorieAdjustment))
        restDayCalorieAdjustmentText = String(format: "%.0f", abs(settingsStore.restDayCalorieAdjustment))
        trainingDayAddsCalories = settingsStore.trainingDayCalorieAdjustment >= 0
        restDayAddsCalories = settingsStore.restDayCalorieAdjustment >= 0
        waterGoalText = Self.volumeText(settingsStore.dailyWaterGoalMilliliters, unit: settingsStore.defaultLiquidUnit)
        waterGlassSizeText = Self.volumeText(settingsStore.waterGlassSizeMilliliters, unit: settingsStore.defaultLiquidUnit)
        addedSugarGoalText = String(format: "%.0f", settingsStore.addedSugarGoalGrams)
        fruitSugarGoalText = String(format: "%.0f", settingsStore.fruitSugarGoalGrams)
        saltGoalText = String(format: "%.1f", settingsStore.saltGoalGrams)
        fiberGoalText = String(format: "%.0f", settingsStore.fiberGoalGrams)
        saturatedFatGoalText = String(format: "%.0f", settingsStore.saturatedFatGoalGrams)
    }

    private func refreshCalorieGoalDraftValues() {
        baseGoalText = String(format: "%.0f", settingsStore.baseCalorieGoal)
        fixedDeficitText = String(format: "%.0f", settingsStore.fixedCalorieDeficit)
        fixedSurplusText = String(format: "%.0f", settingsStore.fixedCalorieSurplus)
    }

    @discardableResult
    private func applySettingsDraft(showValidationErrors: Bool) -> Bool {
        guard let goal = localizedDouble(baseGoalText), goal > 0 else {
            if showValidationErrors { alertMessage = t("settings.please_enter_valid_daily_calorie_goal") }
            return false
        }
        let surplus: Double?
        if settingsStore.calorieGoalMode == .dynamic, settingsStore.dynamicCalorieTargetMode == .surplus {
            guard let value = localizedDouble(fixedSurplusText), value > 0 else {
                if showValidationErrors { alertMessage = t("calorie_target.invalid_surplus") }
                return false
            }
            surplus = value
        } else {
            surplus = nil
        }
        let deficit: Double?
        if settingsStore.calorieGoalMode == .dynamic, settingsStore.dynamicCalorieTargetMode == .fixedDeficit {
            guard let value = localizedDouble(fixedDeficitText), value.isFinite, value > 0 else {
                if showValidationErrors { alertMessage = language.isGerman ? "Bitte ein gültiges festes Defizit eingeben." : "Enter a valid fixed deficit." }
                return false
            }
            deficit = value
        } else {
            deficit = nil
        }
        guard let trainingDayMagnitude = localizedDouble(trainingDayCalorieAdjustmentText),
              trainingDayMagnitude.isFinite, trainingDayMagnitude >= 0, trainingDayMagnitude <= 10_000,
              let restDayMagnitude = localizedDouble(restDayCalorieAdjustmentText),
              restDayMagnitude.isFinite, restDayMagnitude >= 0, restDayMagnitude <= 10_000 else {
            if showValidationErrors { alertMessage = t("settings.invalid_day_calorie_adjustment") }
            return false
        }
        let trainingDayAdjustment = trainingDayAddsCalories ? trainingDayMagnitude : -trainingDayMagnitude
        let restDayAdjustment = restDayAddsCalories ? restDayMagnitude : -restDayMagnitude
        let trackingThreshold: Double?
        if settingsStore.lowRemainingTrackingLockEnabled {
            guard let value = localizedDouble(lowRemainingTrackingThresholdText), value > 0 else {
                if showValidationErrors { alertMessage = t("food_tracking.invalid_threshold") }
                return false
            }
            trackingThreshold = value
        } else {
            trackingThreshold = nil
        }
        let calorieLimitBuffer: Double?
        if settingsStore.enforceCalorieLimit {
            guard let value = localizedDouble(calorieLimitBufferText), value >= 0 else {
                if showValidationErrors { alertMessage = t("settings.invalid_calorie_limit_buffer") }
                return false
            }
            calorieLimitBuffer = value
        } else {
            calorieLimitBuffer = nil
        }
        guard let displayedWaterGoal = localizedDouble(waterGoalText), displayedWaterGoal > 0,
              let displayedGlassSize = localizedDouble(waterGlassSizeText), displayedGlassSize > 0,
              let waterGoal = settingsStore.defaultLiquidUnit.converted(displayedWaterGoal, to: .milliliter),
              let glassSize = settingsStore.defaultLiquidUnit.converted(displayedGlassSize, to: .milliliter) else {
            if showValidationErrors { alertMessage = t("settings.water_values_greater_zero") }
            return false
        }

        guard let addedSugar = localizedDouble(addedSugarGoalText), addedSugar > 0,
              let fruitSugar = localizedDouble(fruitSugarGoalText), fruitSugar > 0,
              let salt = localizedDouble(saltGoalText), salt > 0,
              let fiber = localizedDouble(fiberGoalText), fiber > 0,
              let saturatedFat = localizedDouble(saturatedFatGoalText), saturatedFat > 0 else {
            if showValidationErrors { alertMessage = t("settings.guidance_values_greater_zero") }
            return false
        }

        let c = Int(carbsPctText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let p = Int(proteinPctText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let f = Int(fatPctText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        guard c >= 0, p >= 0, f >= 0, c + p + f == 100 else {
            if showValidationErrors { alertMessage = t("settings.macro_percentages_total", c + p + f) }
            return false
        }

        settingsStore.baseCalorieGoal = goal
        settingsStore.trainingDayCalorieAdjustment = trainingDayAdjustment
        settingsStore.restDayCalorieAdjustment = restDayAdjustment
        if let surplus { settingsStore.fixedCalorieSurplus = surplus }
        if let deficit { settingsStore.fixedCalorieDeficit = deficit }
        if let calorieLimitBuffer { settingsStore.calorieLimitBufferKilocalories = calorieLimitBuffer }
        if let trackingThreshold { settingsStore.lowRemainingTrackingCaloriesThreshold = trackingThreshold }
        let percentagesChanged = c != settingsStore.carbsPercentage || p != settingsStore.proteinPercentage || f != settingsStore.fatPercentage
        _ = settingsStore.updateMacros(carbs: c, protein: p, fat: f)
        if percentagesChanged, settingsStore.macroGoalPlan.mode == .flexible {
            var plan = settingsStore.macroGoalPlan
            plan.mode = .percentages
            _ = settingsStore.updateMacroGoalPlan(plan)
        }
        settingsStore.dailyWaterGoalMilliliters = waterGoal
        settingsStore.waterGlassSizeMilliliters = glassSize
        settingsStore.addedSugarGoalGrams = addedSugar
        settingsStore.fruitSugarGoalGrams = fruitSugar
        settingsStore.saltGoalGrams = salt
        settingsStore.fiberGoalGrams = fiber
        settingsStore.saturatedFatGoalGrams = saturatedFat
        accountData.stageSettings(settingsStore, language: language)
        return true
    }

    private func scheduleAutomaticSave() {
        automaticSaveTask?.cancel()
        isSavingSettings = true
        automaticSaveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(650)) }
            catch { return }
            automaticSaveTask = nil
            guard applySettingsDraft(showValidationErrors: false) else {
                isSavingSettings = false
                return
            }
            isSavingSettings = false
            settingsSavedMessage = t("settings.saved")
            scheduleDeferredSettingsSync()
        }
    }

    private func scheduleDeferredSettingsSync() {
        deferredSettingsSyncTask?.cancel()
        deferredSettingsSyncTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(900)) }
            catch { return }
            deferredSettingsSyncTask = nil
            syncSettingsNow()
        }
    }

    private func syncSettingsNow() {
        accountData.syncSettings(settingsStore, language: language)
        if authManager.isLoggedIn {
            Task {
                await HyseNotificationService.shared.updatePreferences(
                    settings: settingsStore,
                    token: authManager.token
                )
            }
        }
    }

    @discardableResult
    private func flushPendingSettings() -> Bool {
        let shouldApplyDraft = automaticSaveTask != nil
        let shouldSync = shouldApplyDraft || deferredSettingsSyncTask != nil
        automaticSaveTask?.cancel()
        automaticSaveTask = nil
        deferredSettingsSyncTask?.cancel()
        deferredSettingsSyncTask = nil
        isSavingSettings = false
        if shouldApplyDraft, applySettingsDraft(showValidationErrors: false) {
            settingsSavedMessage = t("settings.saved")
        }
        if shouldSync { syncSettingsNow() }
        return shouldSync
    }

    private func localizedDouble(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private static func volumeText(_ milliliters: Double, unit: FoodUnit) -> String {
        let value = FoodUnit.milliliter.converted(milliliters, to: unit) ?? milliliters
        return unit == .fluidOunce ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    private func convertedVolumeText(_ text: String, from oldUnit: FoodUnit, to newUnit: FoodUnit) -> String {
        guard let value = localizedDouble(text),
              let milliliters = oldUnit.converted(value, to: .milliliter) else { return text }
        return Self.volumeText(milliliters, unit: newUnit)
    }

    private func startDynamicPhase() {
        guard let bodyFat = localizedDouble(phaseBodyFatText), bodyFat > 0, bodyFat < 100,
              let weight = localizedDouble(phaseWeightText), weight > 0 else {
            alertMessage = t("calorie_target.invalid_phase_values")
            return
        }
        guard settingsStore.startDynamicDeficitPhase(bodyFatPercentage: bodyFat, weightKilograms: weight) else { return }
        accountData.syncSettings(settingsStore, language: language)
        settingsSavedMessage = t("calorie_target.phase_started")
        showingPhaseResetConfirmation = false
        showingPhaseEditor = false
    }
}

private struct ScheduledCaloriePhaseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var settingsStore: UserSettingsStore
    let latestWeightKilograms: Double?
    let onSave: (ScheduledCaloriePhase) -> Void

    @State private var kind: PlannedCaloriePhaseKind
    @State private var trigger: PlannedCaloriePhaseTrigger
    @State private var startDate: Date
    @State private var thresholdText: String
    @State private var goalMode: CalorieGoalMode
    @State private var fixedGoalText: String
    @State private var dynamicMode: DynamicCalorieTargetMode
    @State private var deficitText: String
    @State private var surplusText: String
    @State private var weightSource: PlannedCalorieWeightSource
    @State private var manualWeightText: String
    @State private var bodyFatText: String
    @State private var configureMacros: Bool
    @State private var plannedMacroPlan: MacroGoalPlan
    @State private var macroPercentTexts: [String: String]
    @State private var macroFieldTexts: [String: String]

    init(settingsStore: UserSettingsStore, latestWeightKilograms: Double?, onSave: @escaping (ScheduledCaloriePhase) -> Void) {
        self.settingsStore = settingsStore
        self.latestWeightKilograms = latestWeightKilograms
        self.onSave = onSave
        let plan = settingsStore.scheduledCaloriePhase
        _kind = State(initialValue: plan?.kind ?? .cut)
        _trigger = State(initialValue: plan?.trigger ?? .date)
        _startDate = State(initialValue: plan?.startDate ?? Date().addingTimeInterval(86_400))
        _thresholdText = State(initialValue: plan?.triggerWeightKilograms.map { String($0) } ?? "")
        _goalMode = State(initialValue: plan?.goalMode ?? .fixed)
        _fixedGoalText = State(initialValue: String(plan?.fixedGoal ?? settingsStore.baseCalorieGoal))
        _dynamicMode = State(initialValue: plan?.dynamicMode ?? .fixedDeficit)
        _deficitText = State(initialValue: String(plan?.fixedDeficit ?? settingsStore.fixedCalorieDeficit))
        _surplusText = State(initialValue: String(plan?.fixedSurplus ?? settingsStore.fixedCalorieSurplus))
        _weightSource = State(initialValue: plan?.weightSource ?? .latestMeasurement)
        _manualWeightText = State(initialValue: plan?.manualStartWeightKilograms.map { String($0) } ?? "")
        _bodyFatText = State(initialValue: plan?.bodyFatPercentage.map { String($0) } ?? "")
        let macroGoals = plan?.macroGoals
        let macroPlan = macroGoals?.plan ?? settingsStore.macroGoalPlan
        _configureMacros = State(initialValue: macroGoals != nil)
        _plannedMacroPlan = State(initialValue: macroPlan)
        _macroPercentTexts = State(initialValue: [
            "carbs": String(macroGoals?.carbsPercentage ?? settingsStore.carbsPercentage),
            "protein": String(macroGoals?.proteinPercentage ?? settingsStore.proteinPercentage),
            "fat": String(macroGoals?.fatPercentage ?? settingsStore.fatPercentage)
        ])
        _macroFieldTexts = State(initialValue: [
            "carbsFixed": String(macroPlan.carbsFixedGrams ?? 0), "carbsShare": String(macroPlan.carbsRemainingPercent),
            "proteinFixed": String(macroPlan.proteinFixedGrams ?? 0), "proteinShare": String(macroPlan.proteinRemainingPercent),
            "fatFixed": String(macroPlan.fatFixedGrams ?? 0), "fatShare": String(macroPlan.fatRemainingPercent)
        ])
    }

    private func t(_ key: String) -> String { language.text(key) }
    private func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var scheduledMacros: ScheduledMacroGoals {
        ScheduledMacroGoals(
            carbsPercentage: Int(macroPercentTexts["carbs"] ?? "") ?? -1,
            proteinPercentage: Int(macroPercentTexts["protein"] ?? "") ?? -1,
            fatPercentage: Int(macroPercentTexts["fat"] ?? "") ?? -1,
            plan: plannedMacroPlan
        )
    }

    private var macroPreview: MacroGramTargets? {
        guard let calories = number(fixedGoalText), calories > 0, scheduledMacros.isValid else { return nil }
        if plannedMacroPlan.mode == .flexible { return plannedMacroPlan.targets(calories: calories) }
        return MacroGramTargets(
            carbs: calories * Double(scheduledMacros.carbsPercentage) / 100 / 4,
            protein: calories * Double(scheduledMacros.proteinPercentage) / 100 / 4,
            fat: calories * Double(scheduledMacros.fatPercentage) / 100 / 9
        )
    }

    private func macroGrams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))
    }

    private var currentWeightDescription: String? {
        guard let latestWeightKilograms else { return nil }
        return "\(t("calorie_plan.current_weight")): \(macroGrams(latestWeightKilograms)) kg"
    }

    private func macroPreviewTitle(calories: Double) -> String {
        let key = goalMode == .dynamic ? "calorie_plan.macro_preview_fallback" : "calorie_plan.macro_preview"
        return language.text(key, [macroGrams(calories)])
    }

    private var draft: ScheduledCaloriePhase {
        ScheduledCaloriePhase(
            id: settingsStore.scheduledCaloriePhase?.id ?? UUID(),
            createdAt: settingsStore.scheduledCaloriePhase?.createdAt ?? Date(),
            kind: kind, trigger: trigger,
            startDate: trigger == .weight ? nil : startDate,
            triggerWeightKilograms: trigger == .date ? nil : number(thresholdText),
            goalMode: goalMode, fixedGoal: number(fixedGoalText) ?? 0,
            dynamicMode: kind == .bulk ? .surplus : dynamicMode,
            fixedDeficit: number(deficitText) ?? settingsStore.fixedCalorieDeficit,
            fixedSurplus: number(surplusText) ?? settingsStore.fixedCalorieSurplus,
            weightSource: weightSource,
            manualStartWeightKilograms: number(manualWeightText),
            bodyFatPercentage: bodyFatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : number(bodyFatText),
            macroGoals: configureMacros ? scheduledMacros : nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(t("calorie_plan.phase")) {
                    Picker(t("calorie_plan.phase"), selection: $kind) {
                        Text(t("calorie_plan.cut")).tag(PlannedCaloriePhaseKind.cut)
                        Text(t("calorie_plan.bulk")).tag(PlannedCaloriePhaseKind.bulk)
                    }.pickerStyle(.segmented)
                    .onChange(of: kind) { _, selected in
                        if selected == .cut && dynamicMode == .surplus { dynamicMode = .fixedDeficit }
                    }
                }
                Section(t("calorie_plan.start")) {
                    Picker(t("calorie_plan.trigger"), selection: $trigger) {
                        Text(t("calorie_plan.date")).tag(PlannedCaloriePhaseTrigger.date)
                        Text(t("calorie_plan.weight")).tag(PlannedCaloriePhaseTrigger.weight)
                        Text(t("calorie_plan.whichever_first")).tag(PlannedCaloriePhaseTrigger.whicheverFirst)
                    }.pickerStyle(.menu)
                    if trigger != .weight {
                        DatePicker(t("calorie_plan.date"), selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    }
                    if trigger != .date {
                        HStack {
                            Text(t(kind == .cut ? "calorie_plan.cut_weight" : "calorie_plan.bulk_weight"))
                            Spacer()
                            TextField("kg", text: $thresholdText)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                            Text("kg").foregroundStyle(.secondary)
                        }
                        if let currentWeightDescription {
                            Text(currentWeightDescription)
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(t("calorie_plan.no_weight"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if trigger == .whicheverFirst {
                        Text(t("calorie_plan.whichever_first_explanation"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(t("calorie_plan.target")) {
                    Picker(t("calorie_plan.target"), selection: $goalMode) {
                        Text(t("settings.fixed_calorie_goal")).tag(CalorieGoalMode.fixed)
                        Text(t("settings.dynamic_calorie_goal")).tag(CalorieGoalMode.dynamic)
                    }.pickerStyle(.segmented)
                    HStack {
                        Text(t(goalMode == .fixed ? "settings.daily_goal" : "settings.fixed_fallback_goal"))
                        Spacer()
                        TextField("kcal", text: $fixedGoalText)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        Text("kcal")
                    }
                    if goalMode == .dynamic {
                        if kind == .cut {
                            Picker(t("calorie_plan.deficit_type"), selection: $dynamicMode) {
                                Text(t("calorie_plan.fixed_deficit")).tag(DynamicCalorieTargetMode.fixedDeficit)
                                Text(t("calorie_plan.dynamic_deficit")).tag(DynamicCalorieTargetMode.deficit)
                            }
                            if dynamicMode == .fixedDeficit {
                                calorieInput(t("calorie_plan.deficit"), text: $deficitText)
                            } else {
                                HStack {
                                    Text(t("calorie_plan.body_fat"))
                                    Spacer()
                                    TextField("%", text: $bodyFatText)
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                    Text("%")
                                }
                                Text(t("calorie_plan.body_fat_start_prompt"))
                                    .font(.caption).foregroundStyle(.secondary)
                                Picker(t("calorie_plan.start_weight"), selection: $weightSource) {
                                    Text(t("calorie_plan.latest_weight")).tag(PlannedCalorieWeightSource.latestMeasurement)
                                    Text(t("calorie_plan.enter_weight")).tag(PlannedCalorieWeightSource.manual)
                                }
                                if weightSource == .manual {
                                    HStack {
                                        Text(t("calorie_plan.start_weight"))
                                        Spacer()
                                        TextField("kg", text: $manualWeightText)
                                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                        Text("kg")
                                    }
                                } else if latestWeightKilograms == nil {
                                    Text(t("calorie_plan.wait_for_weight"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            calorieInput(t("calorie_plan.surplus"), text: $surplusText)
                        }
                        Text(t("calorie_plan.dynamic_explanation"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(t("calorie_plan.macros")) {
                    Toggle(t("calorie_plan.configure_macros"), isOn: $configureMacros)
                    if configureMacros {
                        Picker(t("calorie_plan.macros"), selection: $plannedMacroPlan.mode) {
                            Text(t("calorie_plan.macro_percentages")).tag(MacroGoalMode.percentages)
                            Text(t("calorie_plan.macro_flexible")).tag(MacroGoalMode.flexible)
                        }
                        .pickerStyle(.segmented)
                        if plannedMacroPlan.mode == .percentages {
                            macroPercentageRow(t("quick_entry.carbohydrates"), key: "carbs")
                            macroPercentageRow(t("settings.protein"), key: "protein")
                            macroPercentageRow(t("quick_entry.fat"), key: "fat")
                            let total = scheduledMacros.carbsPercentage + scheduledMacros.proteinPercentage + scheduledMacros.fatPercentage
                            LabeledContent(t("settings.total"), value: "\(total) %")
                            if !scheduledMacros.isValid {
                                Text(t("calorie_plan.macro_invalid_percentages"))
                                    .font(.caption).foregroundStyle(HyseColor.warning)
                            }
                        } else {
                            Text(t("calorie_plan.macro_remaining_note"))
                                .font(.caption).foregroundStyle(.secondary)
                            plannedMacroRow(t("quick_entry.carbohydrates"), key: "carbs", fixed: \.carbsFixedGrams, share: \.carbsRemainingPercent)
                            plannedMacroRow(t("settings.protein"), key: "protein", fixed: \.proteinFixedGrams, share: \.proteinRemainingPercent)
                            plannedMacroRow(t("quick_entry.fat"), key: "fat", fixed: \.fatFixedGrams, share: \.fatRemainingPercent)
                            if plannedMacroPlan.variableCount == 0 {
                                Text(t("calorie_plan.macro_all_fixed_note"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if goalMode == .fixed, let calories = number(fixedGoalText), plannedMacroPlan.fixedCalories > calories {
                                Text(t("calorie_plan.macro_over_fixed_goal"))
                                    .font(.caption).foregroundStyle(HyseColor.warning)
                            }
                            if !plannedMacroPlan.isValid {
                                Text(t("calorie_plan.macro_invalid_remaining"))
                                    .font(.caption).foregroundStyle(HyseColor.warning)
                            }
                        }
                        if goalMode == .dynamic {
                            Text(t("calorie_plan.macro_dynamic_note"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let preview = macroPreview, let calories = number(fixedGoalText) {
                            VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                                Text(macroPreviewTitle(calories: calories))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(macroGrams(preview.carbs)) g \(t("quick_entry.carbohydrates")) · \(macroGrams(preview.protein)) g \(t("settings.protein")) · \(macroGrams(preview.fat)) g \(t("quick_entry.fat"))")
                                    .font(.subheadline)
                            }
                        }
                    } else {
                        Text(t("calorie_plan.macros_unchanged"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .hyseForm()
            .navigationTitle(t("calorie_plan.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("calorie_plan.save")) { onSave(draft) }
                        .bold().disabled(!draft.isValid)
                }
            }
        }
    }

    private func macroPercentageRow(_ title: String, key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("%", text: Binding(
                get: { macroPercentTexts[key] ?? "" },
                set: { macroPercentTexts[key] = $0 }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 60)
            Text("%")
        }
    }

    private func plannedMacroRow(
        _ title: String,
        key: String,
        fixed: WritableKeyPath<MacroGoalPlan, Double?>,
        share: WritableKeyPath<MacroGoalPlan, Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(title, selection: Binding(
                get: { plannedMacroPlan[keyPath: fixed] != nil },
                set: { isFixed in
                    if isFixed {
                        plannedMacroPlan[keyPath: fixed] = number(macroFieldTexts["\(key)Fixed"] ?? "0") ?? .nan
                    } else {
                        plannedMacroPlan[keyPath: fixed] = nil
                    }
                }
            )) {
                Text(t("calorie_plan.macro_fixed")).tag(true)
                Text(t("calorie_plan.macro_variable")).tag(false)
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                if plannedMacroPlan[keyPath: fixed] != nil {
                    TextField("0", text: Binding(
                        get: { macroFieldTexts["\(key)Fixed"] ?? "0" },
                        set: { text in
                            macroFieldTexts["\(key)Fixed"] = text
                            plannedMacroPlan[keyPath: fixed] = number(text) ?? .nan
                        }
                    ))
                    .keyboardType(.decimalPad)
                    Text("g")
                } else {
                    TextField("%", text: Binding(
                        get: { plannedMacroPlan.variableCount == 1 ? "100" : (macroFieldTexts["\(key)Share"] ?? "0") },
                        set: { text in
                            macroFieldTexts["\(key)Share"] = text
                            plannedMacroPlan[keyPath: share] = Int(text) ?? -1
                        }
                    ))
                    .keyboardType(.numberPad)
                    .disabled(plannedMacroPlan.variableCount == 1)
                    Text("%")
                }
            }
            .multilineTextAlignment(.trailing)
        }
    }

    private func calorieInput(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("kcal", text: text)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text("kcal")
        }
    }
}

private struct GoalsSettingsCategoryView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var dailyFoodStore: DailyFoodScheduleStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var settingsStore: UserSettingsStore
    let trackingWindowClock: Date
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var frequencyStore: FrequencyStore

    @Binding var baseGoalText: String
    @Binding var trainingDayCalorieAdjustmentText: String
    @Binding var restDayCalorieAdjustmentText: String
    @Binding var trainingDayAddsCalories: Bool
    @Binding var restDayAddsCalories: Bool
    @Binding var fixedSurplusText: String
    @Binding var fixedDeficitText: String
    @Binding var calorieLimitBufferText: String
    @Binding var lowRemainingTrackingThresholdText: String
    @Binding var carbsPctText: String
    @Binding var proteinPctText: String
    @Binding var fatPctText: String
    @Binding var waterGoalText: String
    @Binding var waterGlassSizeText: String
    @Binding var addedSugarGoalText: String
    @Binding var fruitSugarGoalText: String
    @Binding var saltGoalText: String
    @Binding var fiberGoalText: String
    @Binding var saturatedFatGoalText: String

    @Binding var hasNutritionSettingsCode: Bool
    @Binding var nutritionProtectedScopes: Set<NutritionSettingsLockScope>
    @Binding var unlockedNutritionScopes: Set<NutritionSettingsLockScope>
    @Binding var nutritionLockManagementUnlocked: Bool
    @Binding var showingRemoveNutritionCodeConfirmation: Bool
    @Binding var settingsSavedMessage: String?

    let presentNutritionCodePrompt: (NutritionCodePrompt) -> Void
    let preparePhaseEditor: () -> Void
    let saveMacroSettings: () -> Void
    @State private var showingNutritionPremium = false
    @State private var showingMacroEditor = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    private var macroPreviewCalories: Double {
        max(0, calorieStore.calorieAllowance(for: Date()) ?? settingsStore.baseCalorieGoal)
    }

    private func macroTargetText(_ grams: Double) -> String {
        "\(grams.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(language.locale))) g"
    }

    var body: some View {
        Group {
            Section {
                Picker(t("settings.activity_level"), selection: activityLevelBinding) {
                    ForEach(NutritionActivityLevel.allCases) { level in
                        Text(t(level.localizationKey)).tag(level)
                    }
                }
                .pickerStyle(.menu)
                Text(t(settingsStore.nutritionActivityLevel.descriptionKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(t("settings.activity_pal"), value: settingsStore.nutritionActivityLevel.pal.formatted(.number.precision(.fractionLength(1))))
                LabeledContent(t("settings.activity_calorie_target"), value: "\(Int(settingsStore.baseCalorieGoal)) kcal")
                LabeledContent(t("settings.activity_salt_target"), value: "\(settingsStore.saltGoalGrams.formatted(.number.precision(.fractionLength(0...1)))) g")
            } header: {
                Text(t("settings.activity_section"))
            } footer: {
                Text(t("settings.activity_explanation"))
            }

            Section {
                if hasNutritionSettingsCode {
                    if nutritionLockManagementUnlocked {
                        ForEach(NutritionSettingsLockScope.allCases) { scope in
                            Toggle(t(scope.titleKey), isOn: nutritionProtectionBinding(scope))
                        }
                        Button(t("nutrition_lock.change_code")) {
                            presentNutritionCodePrompt(.change)
                        }
                        Button(t("nutrition_lock.remove_code"), role: .destructive) {
                            showingRemoveNutritionCodeConfirmation = true
                        }
                    } else {
                        Button {
                            presentNutritionCodePrompt(.manage)
                        } label: {
                            Label(t("nutrition_lock.manage"), systemImage: "lock.shield")
                        }
                        Text(t("nutrition_lock.protected_count", nutritionProtectedScopes.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        presentNutritionCodePrompt(.setup)
                    } label: {
                        Label(t("nutrition_lock.setup"), systemImage: "lock.badge.plus")
                    }
                }
            } header: {
                Text(t("nutrition_lock.section"))
            } footer: {
                Text(t("nutrition_lock.explanation"))
            }

            Section(t("quick_entry.calories")) {
                if isNutritionSettingLocked(.dailyCalorieGoal) {
                    nutritionLockedRow(.dailyCalorieGoal)
                } else {
                    Picker(t("settings.calorie_goal"), selection: calorieGoalModeBinding) {
                        Text(t("settings.fixed_calorie_goal")).tag(CalorieGoalMode.fixed)
                        Text(t("settings.dynamic_calorie_goal")).tag(CalorieGoalMode.dynamic)
                    }
                    .pickerStyle(.segmented)
                    if !premium.hasNutrition {
                        Button { showingNutritionPremium = true } label: {
                            HStack {
                                PremiumLockedLabel(area: .nutrition)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Text(settingsStore.calorieGoalMode == .fixed ? t("settings.daily_goal") : t("settings.fixed_fallback_goal"))
                        Spacer()
                        TextField("kcal", text: $baseGoalText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kcal")
                    }
                }

                if settingsStore.calorieGoalMode == .dynamic {
                    if !premium.hasNutrition {
                        Text(t("settings.dynamic_calorie_goal_premium"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isNutritionSettingLocked(.calorieBalance) {
                        nutritionLockedRow(.calorieBalance)
                    } else {
                        Picker(t("calorie_target.dynamic_mode"), selection: $settingsStore.dynamicCalorieTargetMode) {
                            Text(language.isGerman ? "Dynamisches Defizit" : "Dynamic deficit").tag(DynamicCalorieTargetMode.deficit)
                            Text(language.isGerman ? "Festes Defizit" : "Fixed deficit").tag(DynamicCalorieTargetMode.fixedDeficit)
                            Text(t("calorie_target.surplus")).tag(DynamicCalorieTargetMode.surplus)
                        }
                        .pickerStyle(.menu)

                        if settingsStore.dynamicCalorieTargetMode == .deficit {
                            if let phase = settingsStore.dynamicDeficitPhase {
                                LabeledContent(t("calorie_target.phase_start"), value: phase.startedAt.formatted(.dateTime.day().month().year().locale(language.locale)))
                                LabeledContent(t("calorie_target.initial_body_fat"), value: String(format: "%.1f %%", phase.initialBodyFatFraction * 100))
                                LabeledContent(t("calorie_target.initial_weight"), value: String(format: "%.1f %@", phase.initialWeightKilograms, t("unit.kg_short")))
                            }
                            Button(settingsStore.dynamicDeficitPhase == nil ? t("calorie_target.start_phase") : t("calorie_target.start_new_phase")) {
                                preparePhaseEditor()
                            }
                            .buttonStyle(.borderedProminent)
                            Text(t("calorie_target.settings_explanation"))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(t("calorie_target.study_context"))
                                .font(.caption).foregroundStyle(.secondary)
                            if let studyURL = URL(string: "https://pubmed.ncbi.nlm.nih.gov/15615615/") {
                                Link(destination: studyURL) {
                                    Label(t("calorie_target.study_source"), systemImage: "book.closed")
                                        .font(.caption)
                                }
                                .accessibilityHint(t("settings.opens_website_in_browser"))
                            }
                            HyseStatusBanner(
                                title: nil,
                                message: t("calorie_target.safety_disclaimer"),
                                style: .warning
                            )
                        } else if settingsStore.dynamicCalorieTargetMode == .fixedDeficit {
                            HStack {
                                Text(language.isGerman ? "Festes Defizit" : "Fixed deficit")
                                Spacer()
                                TextField("kcal", text: $fixedDeficitText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                Text("kcal")
                            }
                            Text(language.isGerman
                                 ? "Wird täglich vom Ruheenergieverbrauch des Vortags abgezogen. Ohne Health-Daten gilt dein Ersatzziel."
                                 : "Subtracted from the previous day's resting energy. Without Health data, your fallback goal applies.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Text(t("calorie_target.fixed_surplus"))
                                Spacer()
                                TextField("kcal", text: $fixedSurplusText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                Text("kcal")
                            }
                            Text(t("calorie_target.surplus_explanation"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if isNutritionSettingLocked(.calorieLimitBuffer) {
                    nutritionLockedRow(.calorieLimitBuffer)
                } else {
                    Toggle(t("settings.enforce_calorie_limit"), isOn: $settingsStore.enforceCalorieLimit)
                    if settingsStore.enforceCalorieLimit {
                        HStack {
                            Text(t("settings.calorie_limit_buffer"))
                            Spacer()
                            TextField("0", text: $calorieLimitBufferText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("kcal")
                        }
                        Text(t("settings.calorie_limit_buffer_explanation"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if premium.hasNutrition {
                    dayTypeCalorieRow(
                        title: t("settings.training_day_calorie_adjustment"),
                        text: $trainingDayCalorieAdjustmentText,
                        addsCalories: $trainingDayAddsCalories
                    )

                    dayTypeCalorieRow(
                        title: t("settings.rest_day_calorie_adjustment"),
                        text: $restDayCalorieAdjustmentText,
                        addsCalories: $restDayAddsCalories
                    )
                } else {
                    Button { showingNutritionPremium = true } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t("settings.day_type_calories_premium_title"))
                                    .foregroundStyle(.primary)
                                Text(t("settings.day_type_calories_premium_subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                PremiumLockedLabel(area: .nutrition)
                            }
                        } icon: {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .foregroundStyle(HyseColor.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(t("settings.day_type_calories"))
            } footer: {
                    Text(premium.hasNutrition
                     ? t("settings.day_type_calories_explanation")
                     : t("settings.day_type_calories_premium_explanation"))
            }
            .sheet(isPresented: $showingNutritionPremium) {
                PremiumPaywallView(requestedArea: .nutrition)
            }

            Section {
                if isNutritionSettingLocked(.fastingBlock) {
                    nutritionLockedRow(.fastingBlock)
                } else {
                    Toggle(t("food_tracking.block_while_fasting"), isOn: $settingsStore.blockFoodTrackingWhileFastingEnabled)
                }
                if isNutritionSettingLocked(.trackingWindow) {
                    nutritionLockedRow(.trackingWindow)
                } else {
                    Group {
                        Toggle(t("food_tracking.window_enabled"), isOn: $settingsStore.foodTrackingWindowEnabled)
                        if settingsStore.foodTrackingWindowEnabled {
                            LabeledContent(t("food_tracking.allowed_from")) {
                                DatePicker(
                                    "",
                                    selection: trackingTimeBinding(\.foodTrackingWindowStartMinutes),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            LabeledContent(t("food_tracking.allowed_until")) {
                                DatePicker(
                                    "",
                                    selection: trackingTimeBinding(\.foodTrackingWindowEndMinutes),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            Toggle(t("food_tracking.hide_nutrition_outside_window"), isOn: $settingsStore.hideNutritionOutsideTrackingWindow)
                            Toggle(t("food_tracking.lock_window_changes_outside_hours"), isOn: $settingsStore.lockTrackingWindowSettingsOutsideHours)
                        }
                    }
                    .disabled(settingsStore.areTrackingWindowSettingsLocked(at: trackingWindowClock))
                    if settingsStore.areTrackingWindowSettingsLocked(at: trackingWindowClock) {
                        Text(t("food_tracking.window_settings_locked"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isNutritionSettingLocked(.eveningRule) {
                    nutritionLockedRow(.eveningRule)
                } else {
                    Toggle(t("food_tracking.low_remaining_enabled"), isOn: $settingsStore.lowRemainingTrackingLockEnabled)
                    if settingsStore.lowRemainingTrackingLockEnabled {
                        LabeledContent(t("food_tracking.lock_from")) {
                            DatePicker(
                                "",
                                selection: trackingTimeBinding(\.lowRemainingTrackingLockStartMinutes),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }
                        HStack {
                            Text(t("food_tracking.minimum_remaining"))
                            Spacer()
                            TextField("200", text: $lowRemainingTrackingThresholdText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("kcal")
                        }
                    }
                }
            } header: {
                Text(t("food_tracking.section"))
            } footer: {
                Text(t("food_tracking.explanation"))
            }

            Section {
                if premium.hasNutrition {
                    NavigationLink {
                        DailyFoodAutomationView(
                            store: dailyFoodStore, foodStore: foodStore, categoryStore: categoryStore,
                            calorieStore: calorieStore, frequencyStore: frequencyStore,
                            recipeStore: recipeStore, userSettings: settingsStore
                        )
                    } label: { dailyFoodSettingsLabel }
                } else {
                    Button { showingNutritionPremium = true } label: { dailyFoodSettingsLabel }
                }
            } header: {
                Text(t("daily_food.section"))
            } footer: {
                Text(t("daily_food.settings_footer"))
            }
            .sheet(isPresented: $showingNutritionPremium) {
                PremiumPaywallView(requestedArea: .nutrition)
            }

            Section(header: Text(language.text("settings.nutrition_presets")), footer: Text(language.text("settings.preset_immediately_applies_matching_macro_nutrient_targets"))) {
                Picker(language.text("settings.preset"), selection: selectedProfileBinding) {
                    ForEach(NutritionProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                Text(profileSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text(t("settings.macronutrients")), footer: Text(
                settingsStore.macroGoalPlan.mode == .flexible && premium.hasNutrition
                    ? (language.isGerman ? "Feste Grammwerte werden zuerst abgezogen; der Rest wird prozentual verteilt." : "Fixed grams are reserved first; the remaining calories are split by percentage.")
                    : t("settings.sum_all_three_macronutrients_must_exactly_100")
            )) {
                if settingsStore.macroGoalPlan.mode == .flexible && premium.hasNutrition {
                    LabeledContent(t("quick_entry.carbohydrates"), value: macroTargetText(settingsStore.targetCarbsGrams(availableCalories: macroPreviewCalories)))
                    LabeledContent(t("settings.protein"), value: macroTargetText(settingsStore.targetProteinGrams(availableCalories: macroPreviewCalories)))
                    LabeledContent(t("quick_entry.fat"), value: macroTargetText(settingsStore.targetFatGrams(availableCalories: macroPreviewCalories)))
                    if settingsStore.macroGoalPlan.fixedCalories > macroPreviewCalories {
                        Text(language.isGerman ? "Die festen Makros überschreiten das heutige Kalorienziel." : "Fixed macros exceed today's calorie goal.")
                            .font(.caption).foregroundStyle(HyseColor.warning)
                    }
                    Button(language.isGerman ? "Flexible Makroziele bearbeiten" : "Edit flexible macro targets") {
                        showingMacroEditor = true
                    }
                    Button(language.isGerman ? "Prozentziele verwenden" : "Use percentage targets") {
                        var plan = settingsStore.macroGoalPlan
                        plan.mode = .percentages
                        _ = settingsStore.updateMacroGoalPlan(plan)
                        saveMacroSettings()
                    }
                } else {
                HStack {
                    Text(t("quick_entry.carbohydrates"))
                    Spacer()
                    TextField("%", text: $carbsPctText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("%")
                    Text(macroTargetText(macroPreviewCalories * Double(Int(carbsPctText) ?? 0) / 100 / 4))
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Text(t("settings.protein"))
                    Spacer()
                    TextField("%", text: $proteinPctText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("%")
                    Text(macroTargetText(macroPreviewCalories * Double(Int(proteinPctText) ?? 0) / 100 / 4))
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Text(t("quick_entry.fat"))
                    Spacer()
                    TextField("%", text: $fatPctText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("%")
                    Text(macroTargetText(macroPreviewCalories * Double(Int(fatPctText) ?? 0) / 100 / 9))
                        .font(.caption).foregroundStyle(.secondary)
                }

                let sum = (Int(carbsPctText) ?? 0) + (Int(proteinPctText) ?? 0) + (Int(fatPctText) ?? 0)
                HStack {
                    Text(t("settings.total"))
                        .bold()
                    Spacer()
                    Text("\(sum) %")
                        .bold()
                        .foregroundColor(sum == 100 ? .green : .red)
                }
                if premium.hasNutrition {
                    Button(language.isGerman ? "Flexible Makroziele festlegen" : "Set flexible macro targets") {
                        showingMacroEditor = true
                    }
                } else {
                    Button { showingNutritionPremium = true } label: {
                        Label(language.isGerman ? "Flexible Makroziele" : "Flexible macro targets", systemImage: "lock.fill")
                    }
                }
                }
            }
            .sheet(isPresented: $showingMacroEditor) {
                FlexibleMacroGoalEditor(settingsStore: settingsStore, calorieGoal: macroPreviewCalories) {
                    saveMacroSettings()
                }
            }

            Section(header: Text(language.text("settings.health_hydration")), footer: Text(language.text("settings.water_intake_automatically_transferred_when_health_access"))) {
                settingField(title: t("content.daily_goal"), placeholder: t("settings.e_g_2000"), text: $waterGoalText, unit: settingsStore.defaultLiquidUnit.rawValue)
                settingField(title: t("settings.glass_size"), placeholder: t("settings.e_g_250"), text: $waterGlassSizeText, unit: settingsStore.defaultLiquidUnit.rawValue)
            }

            Section(header: Text(t("settings.targets")), footer: Text(t("settings.these_values_set_progress_bars_in_nutrition"))) {
                settingField(title: t("settings.added_sugar"), placeholder: "30", text: $addedSugarGoalText, unit: "g")
                settingField(title: t("settings.fruit_sugar"), placeholder: "50", text: $fruitSugarGoalText, unit: "g")
                settingField(title: t("settings.salt_electrolytes"), placeholder: "5", text: $saltGoalText, unit: "g")
                settingField(title: t("quick_entry.fibre"), placeholder: "30", text: $fiberGoalText, unit: "g")
                settingField(title: t("settings.saturated_fat"), placeholder: t("settings.e_g_27"), text: $saturatedFatGoalText, unit: "g")
            }

            Section {
                ForEach(NutritionMetric.homeAdditionalOptions) { metric in
                    Toggle(t("nutrition.metric.\(metric.rawValue)"), isOn: Binding(
                        get: { settingsStore.isHomeAdditionalNutritionMetricVisible(metric) },
                        set: { settingsStore.setHomeAdditionalNutritionMetric(metric, isVisible: $0) }
                    ))
                }
            } header: {
                Text(t("settings.home_additional_nutrients"))
            } footer: {
                Text(t("settings.home_additional_nutrients_footer"))
            }
        }
    }

    private var dailyFoodSettingsLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(t("daily_food.title"))
                Text(t("daily_food.settings_subtitle", dailyFoodStore.schedules.filter(\.isEnabled).count))
                    .font(.caption).foregroundStyle(.secondary)
                if !premium.hasNutrition { PremiumLockedLabel(area: .nutrition) }
            }
        } icon: {
            Image(systemName: "calendar.badge.checkmark")
        }
    }

    private var activityLevelBinding: Binding<NutritionActivityLevel> {
        Binding(
            get: { settingsStore.nutritionActivityLevel },
            set: { level in
                guard level != settingsStore.nutritionActivityLevel else { return }
                let target = settingsStore.applyActivityLevel(level)
                baseGoalText = String(format: "%.0f", target.calories)
                saltGoalText = String(format: "%.1f", target.saltGrams)
                settingsSavedMessage = nil
            }
        )
    }

    private var calorieGoalModeBinding: Binding<CalorieGoalMode> {
        Binding(
            get: { settingsStore.calorieGoalMode },
            set: { mode in
                guard mode != .dynamic else {
                    guard premium.hasNutrition else {
                        showingNutritionPremium = true
                        return
                    }
                    settingsStore.calorieGoalMode = .dynamic
                    return
                }
                settingsStore.calorieGoalMode = .fixed
            }
        )
    }

    private var selectedProfileBinding: Binding<NutritionProfile> {
        Binding(
            get: { NutritionProfile.allCases.first { settingsStore.isNutritionProfileSelected($0) } ?? .standard },
            set: { profile in
                settingsStore.setNutritionProfile(profile, isSelected: true)
                carbsPctText = String(settingsStore.carbsPercentage)
                proteinPctText = String(settingsStore.proteinPercentage)
                fatPctText = String(settingsStore.fatPercentage)
                saveMacroSettings()
            }
        )
    }

    private var profileSummary: String {
        let macros: String
        if premium.hasNutrition, settingsStore.macroGoalPlan.mode == .flexible {
            macros = "\(t("quick_entry.carbohydrates")) \(macroTargetText(settingsStore.targetCarbsGrams(availableCalories: macroPreviewCalories))) · \(t("settings.protein")) \(macroTargetText(settingsStore.targetProteinGrams(availableCalories: macroPreviewCalories))) · \(t("quick_entry.fat")) \(macroTargetText(settingsStore.targetFatGrams(availableCalories: macroPreviewCalories)))"
        } else {
            macros = "\(t("quick_entry.carbohydrates")) \(settingsStore.carbsPercentage) % · \(t("settings.protein")) \(settingsStore.proteinPercentage) % · \(t("quick_entry.fat")) \(settingsStore.fatPercentage) %"
        }
        let guidance = "\(t("settings.added_sugar")) ≤ \(Int(settingsStore.addedSugarGoalGrams)) g · \(t("quick_entry.fibre")) ≥ \(Int(settingsStore.fiberGoalGrams)) g · \(t("settings.saturated_fat")) ≤ \(Int(settingsStore.saturatedFatGoalGrams)) g · \(t("settings.salt_electrolytes")) ≤ \(settingsStore.saltGoalGrams.formatted(.number.precision(.fractionLength(0...1)))) g"
        return macros + "\n" + guidance
    }

    private func isNutritionSettingLocked(_ scope: NutritionSettingsLockScope) -> Bool {
        hasNutritionSettingsCode
            && nutritionProtectedScopes.contains(scope)
            && !unlockedNutritionScopes.contains(scope)
    }

    private func nutritionProtectionBinding(_ scope: NutritionSettingsLockScope) -> Binding<Bool> {
        Binding(
            get: { nutritionProtectedScopes.contains(scope) },
            set: { enabled in
                NutritionSettingsLockStore.setEnabled(enabled, for: scope)
                if enabled {
                    nutritionProtectedScopes.insert(scope)
                    unlockedNutritionScopes.insert(scope)
                } else {
                    nutritionProtectedScopes.remove(scope)
                    unlockedNutritionScopes.remove(scope)
                }
            }
        )
    }

    private func nutritionLockedRow(_ scope: NutritionSettingsLockScope) -> some View {
        Button {
            presentNutritionCodePrompt(.unlock(scope))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(HyseColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(scope.titleKey))
                        .foregroundStyle(.primary)
                    Text(t("nutrition_lock.tap_to_unlock"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func trackingTimeBinding(_ keyPath: ReferenceWritableKeyPath<UserSettingsStore, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = FoodTrackingPolicy.normalizedMinutes(settingsStore[keyPath: keyPath])
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settingsStore[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func settingField(title: String, placeholder: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func dayTypeCalorieRow(
        title: String,
        text: Binding<String>,
        addsCalories: Binding<Bool>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(t("settings.calorie_direction"), selection: addsCalories) {
                Text("+").tag(true)
                Text("−").tag(false)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel(t("settings.calorie_direction"))

            HStack(spacing: HyseSpacing.xSmall) {
                TextField("0", text: text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .accessibilityLabel(t("settings.calorie_amount"))
                    .onChange(of: text.wrappedValue) { _, newValue in
                        let digits = newValue.filter { $0.isASCII && $0.isNumber }
                        if digits != newValue { text.wrappedValue = digits }
                    }
                Text("kcal").foregroundStyle(.secondary)
            }
        }
    }
}

private struct FlexibleMacroGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var settingsStore: UserSettingsStore
    let calorieGoal: Double
    let onSave: () -> Void
    @State private var draft: MacroGoalPlan
    @State private var fieldTexts: [String: String]

    init(settingsStore: UserSettingsStore, calorieGoal: Double, onSave: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.calorieGoal = calorieGoal
        self.onSave = onSave
        _draft = State(initialValue: settingsStore.macroGoalPlan)
        let plan = settingsStore.macroGoalPlan
        _fieldTexts = State(initialValue: [
            "carbsFixed": String(plan.carbsFixedGrams ?? 0), "carbsShare": String(plan.carbsRemainingPercent),
            "proteinFixed": String(plan.proteinFixedGrams ?? 0), "proteinShare": String(plan.proteinRemainingPercent),
            "fatFixed": String(plan.fatFixedGrams ?? 0), "fatShare": String(plan.fatRemainingPercent)
        ])
    }

    private var targets: MacroGramTargets? { draft.targets(calories: calorieGoal) }
    private var canSave: Bool { draft.isValid && draft.fixedCalories <= calorieGoal }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(language.isGerman ? "Kalorienziel heute" : "Today's calorie goal",
                                   value: "\(calorieGoal.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))) kcal")
                    Text(language.isGerman
                         ? "Feste Grammwerte haben Vorrang. Alle anderen Makros teilen sich die verbleibenden Kalorien."
                         : "Fixed gram targets come first. The other macros split the remaining calories.")
                        .font(.caption).foregroundStyle(.secondary)
                    if draft.variableCount == 0 {
                        Text(language.text("calorie_plan.macro_all_fixed_note"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                macroRow(title: language.text("quick_entry.carbohydrates"), key: "carbs", fixed: \.carbsFixedGrams,
                         share: \.carbsRemainingPercent, target: targets?.carbs)
                macroRow(title: language.text("settings.protein"), key: "protein", fixed: \.proteinFixedGrams,
                         share: \.proteinRemainingPercent, target: targets?.protein)
                macroRow(title: language.text("quick_entry.fat"), key: "fat", fixed: \.fatFixedGrams,
                         share: \.fatRemainingPercent, target: targets?.fat)

                Section {
                    LabeledContent(language.isGerman ? "Für Prozentanteile übrig" : "Left for percentage shares",
                                   value: "\(max(0, calorieGoal - draft.fixedCalories).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))) kcal")
                    if !canSave {
                        Text(draft.fixedCalories > calorieGoal
                             ? (language.isGerman ? "Die festen Grammwerte überschreiten das heutige Kalorienziel." : "Fixed gram targets exceed today's calorie goal.")
                             : (language.isGerman ? "Die Anteile der übrigen Makros müssen zusammen 100 % ergeben." : "The remaining macro shares must add up to 100%."))
                            .foregroundStyle(HyseColor.warning)
                    }
                }
            }
            .hyseForm()
            .navigationTitle(language.isGerman ? "Flexible Makroziele" : "Flexible macro targets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("app_tabs.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("daily_food.save")) {
                        var value = draft
                        value.mode = .flexible
                        guard settingsStore.updateMacroGoalPlan(value) else { return }
                        onSave()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func macroRow(
        title: String,
        key: String,
        fixed: WritableKeyPath<MacroGoalPlan, Double?>,
        share: WritableKeyPath<MacroGoalPlan, Int>,
        target: Double?
    ) -> some View {
        Section(title) {
            Picker(title, selection: Binding(
                get: { draft[keyPath: fixed] != nil },
                set: { isFixed in
                    if isFixed {
                        let text = fieldTexts["\(key)Fixed"] ?? "0"
                        draft[keyPath: fixed] = Double(text.replacingOccurrences(of: ",", with: ".")) ?? .nan
                    } else {
                        draft[keyPath: fixed] = nil
                    }
                }
            )) {
                Text(language.isGerman ? "Fixe Gramm" : "Fixed grams").tag(true)
                Text(language.isGerman ? "% vom Rest" : "% of remainder").tag(false)
            }
            .pickerStyle(.segmented)

            HStack {
                Text(draft[keyPath: fixed] != nil ? "g" : "%")
                Spacer()
                if draft[keyPath: fixed] != nil {
                    TextField("0", text: Binding(
                        get: { fieldTexts["\(key)Fixed"] ?? "0" },
                        set: { text in
                            fieldTexts["\(key)Fixed"] = text
                            draft[keyPath: fixed] = Double(text.replacingOccurrences(of: ",", with: ".")) ?? .nan
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                } else {
                    TextField("%", text: Binding(
                        get: { draft.variableCount == 1 ? "100" : (fieldTexts["\(key)Share"] ?? "0") },
                        set: { text in
                            fieldTexts["\(key)Share"] = text
                            draft[keyPath: share] = Int(text) ?? -1
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .disabled(draft.variableCount == 1)
                }
            }
            if let target {
                LabeledContent(language.isGerman ? "Ziel" : "Target",
                               value: "\(target.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(language.locale))) g")
            }
        }
    }
}

struct EmailChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    @State private var newEmail = ""
    @State private var currentPassword = ""
    @State private var selectedMethod = "password"
    @State private var submittedEmail: String?
    @State private var message: String?
    @State private var isError = false
    @State private var isSubmitting = false
    @State private var isLoadingMethods = true

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var methods: AccountSignInMethods { authManager.accountSignInMethods }
    private var availableMethods: [String] { methods.availableMethods }
    private var usesOAuth: Bool { selectedMethod != "password" }
    private var canSubmit: Bool {
        let value = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let validEmail = value.contains("@") && value.contains(".") && value.lowercased() != authManager.accountEmail.lowercased()
        return validEmail && !isSubmitting && !isLoadingMethods && !availableMethods.isEmpty && (usesOAuth || !currentPassword.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(t("settings.current_address"), value: authManager.accountEmail)
                    TextField(t("settings.new_email_address"), text: $newEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .disabled(isSubmitting)
                } footer: {
                    Text(t("settings.new_address_becomes_active_only_after_you"))
                }

                Section(t("settings.confirm_identity")) {
                    if isLoadingMethods {
                        HStack { ProgressView(); Text(t("settings.loading_sign_in_methods")).foregroundStyle(.secondary) }
                    } else if let loadError = authManager.accountMethodsLoadError {
                        HyseStatusBanner(
                            title: t("settings.sign_in_methods_unavailable"),
                            message: loadError,
                            style: .error,
                            actionTitle: t("saved_foods.try_again"),
                            action: { Task { await loadMethods() } }
                        )
                    } else {
                        if availableMethods.count > 1 {
                            Picker(t("settings.confirm"), selection: $selectedMethod) {
                                ForEach(availableMethods, id: \.self) { method in
                                    Text(methodLabel(method)).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        if usesOAuth {
                            Label(
                                t("settings.you_will_confirm_change_by_securely_signing", String(describing: methodLabel(selectedMethod))),
                                systemImage: selectedMethod == "apple" ? "apple.logo" : "g.circle"
                            )
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else if methods.hasPassword {
                            SecureField(t("password_management.current_password"), text: $currentPassword)
                                .textContentType(.password)
                                .disabled(isSubmitting)
                        } else {
                            HyseStatusBanner(title: nil, message: t("settings.no_available_sign_in_method_was_found"), style: .error)
                        }
                    }
                }

                if let message {
                    Section { HyseStatusBanner(title: nil, message: message, style: isError ? .error : .success) }
                }

                Section {
                    Button { submit() } label: {
                        HStack {
                            Text(submittedEmail == nil ? t("settings.request_change") : t("settings.resend_confirmation_email"))
                            Spacer()
                            if isSubmitting { ProgressView() }
                        }
                    }
                    .disabled(!canSubmit)

                    if submittedEmail != nil {
                        Button(t("settings.refresh_account_details")) { Task { await authManager.refreshSession(force: true) } }
                            .disabled(authManager.isRefreshingSession)
                    }
                }
            }
            .hyseForm()
            .navigationTitle(t("app_tabs.change_email_address"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("add_entry.done")) { dismiss() } } }
            .task {
                await loadMethods()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await authManager.refreshSession() } }
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        let address = newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let proof: EmailChangeProof
        if selectedMethod == "password" {
            proof = .password(currentPassword)
        } else if let provider = OAuthProvider(rawValue: selectedMethod) {
            proof = .oauth(provider)
        } else {
            return
        }
        isSubmitting = true
        message = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await authManager.requestEmailChange(newEmail: address, proof: proof)
                submittedEmail = address
                currentPassword = ""
                isError = false
                message = t("settings.we_sent_confirmation_link_new_email_address")
            } catch is CancellationError {
                isError = false
                message = t("settings.confirmation_was_cancelled")
            } catch {
                isError = true
                if case AuthError.network = error {
                    message = t("settings.could_not_reach_server_please_try_again")
                } else {
                    message = emailChangeError(error)
                }
            }
        }
    }

    private func methodLabel(_ method: String) -> String {
        switch method {
        case "google": return "Google"
        case "apple": return "Apple"
        default: return t("login.password")
        }
    }

    @MainActor
    private func loadMethods() async {
        isLoadingMethods = true
        await authManager.loadAccountSignInMethods()
        selectedMethod = authManager.accountSignInMethods.availableMethods.first ?? ""
        isLoadingMethods = false
    }

    private func emailChangeError(_ error: Error) -> String {
        let value = error.localizedDescription.lowercased()
        if value.contains("already in use") || value.contains("bereits verwendet") {
            return t("settings.email_address_already_in_use")
        }
        if value.contains("recent authentication") || value.contains("confirm your identity") {
            return t("settings.security_confirmation_expired_please_confirm_identity_again")
        }
        if value.contains("valid, different") || value.contains("invalid") {
            return t("settings.enter_valid_different_email_address")
        }
        return error.localizedDescription
    }
}

private struct LogoutConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var dailyFoodStore: DailyFoodScheduleStore
    @Binding var isSigningOut: Bool
    let onLogout: () async -> Void

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        VStack(spacing: HyseSpacing.large) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(HyseColor.danger)
                .frame(width: 58, height: 58)
                .background(HyseColor.danger.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: HyseSpacing.small) {
                Text(t("settings.really_sign_out"))
                    .font(.title3.bold())
                Text(t("settings.do_you_really_want_sign_out_account"))
                    .multilineTextAlignment(.center)
                Text(t("settings.unsynced_changes_remain_safely_on_device_will"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(role: .destructive) { signOut() } label: {
                HStack {
                    if isSigningOut { ProgressView().tint(.white) }
                    Text(isSigningOut ? t("settings.signing_out") : t("settings.sign_out"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(HysePrimaryButtonStyle())
            .disabled(isSigningOut)
            Button(t("app_tabs.cancel")) { dismiss() }
                .disabled(isSigningOut)
                .frame(minHeight: 44)
        }
        .padding(HyseSpacing.xLarge)
        .background(HyseColor.background.ignoresSafeArea())
    }

    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        foodStore.syncPendingFoods()
        calorieStore.syncPendingEntries()
        Task { @MainActor in
            await dailyFoodStore.flushPendingSchedules()
            for _ in 0..<8 {
                let foodBusy = foodStore.syncState == .syncing
                let entryBusy = calorieStore.syncState == .syncing
                if !foodBusy && !entryBusy { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            await onLogout()
            isSigningOut = false
        }
    }
}

private struct DashboardLayoutView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var settingsStore: UserSettingsStore
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private let fixedSections: [DashboardSection] = [.date, .calories, .nutrition, .meals]

    var body: some View {
        ZStack {
            HyseBackdrop()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                    HyseCard(accent: HyseColor.accent) {
                        HyseSectionHeading(
                            title: t("settings.customise_home_screen"),
                            subtitle: t("settings.home_layout_explanation"),
                            icon: "rectangle.3.group"
                        )
                    }

                    HyseCard {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            HyseSectionHeading(
                                title: t("settings.home_essentials"),
                                subtitle: t("settings.home_essentials_explanation"),
                                icon: "lock.fill"
                            )

                            ForEach(Array(fixedSections.enumerated()), id: \.element.id) { index, section in
                                fixedSectionRow(section)
                                if index < fixedSections.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }

                    HyseCard(accent: HyseColor.accent) {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            HyseSectionHeading(
                                title: t("settings.optional_sections"),
                                subtitle: t("settings.optional_sections_explanation"),
                                icon: "switch.2"
                            )

                            ForEach(Array([DashboardSection.water, .steps, .fasting].enumerated()), id: \.element.id) { index, section in
                                Toggle(isOn: Binding(
                                    get: { settingsStore.isDashboardSectionVisible(section) },
                                    set: { settingsStore.setDashboardSection(section, isVisible: $0) }
                                )) {
                                    Label(section.title, systemImage: icon(for: section))
                                        .font(.body.weight(.medium))
                                }
                                .tint(HyseColor.accent)

                                if index < 2 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.top, HyseSpacing.medium)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle(t("settings.customise_home_screen"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fixedSectionRow(_ section: DashboardSection) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon(for: section))
                .foregroundStyle(HyseColor.accent)
                .frame(width: 26)
            Text(section.title)
                .font(.body.weight(.medium))
            Spacer()
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, HyseSpacing.xSmall)
    }

    private func icon(for section: DashboardSection) -> String {
        switch section {
        case .date: "calendar"
        case .calories: "flame.fill"
        case .training: "figure.strengthtraining.traditional"
        case .water: "drop.fill"
        case .nutrition: "chart.bar.fill"
        case .meals: "fork.knife"
        case .steps: "figure.walk"
        case .fasting: "timer"
        }
    }
}
