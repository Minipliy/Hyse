// UserSettingsStore.swift
import Foundation
import Combine
import SwiftUI
import WidgetKit // 1. WICHTIG: WidgetKit importieren

extension Double {
    /// Sichere Int-Konvertierung für die Anzeige. NaN oder unendliche Werte
    /// (z. B. aus einem beschädigten Server-Sync oder einer alten Migration)
    /// würden bei einem direkten `Int(self)` sofort zum Absturz führen.
    var safeIntValue: Int {
        guard isFinite else { return 0 }
        let clamped = min(max(self, -1_000_000_000), 1_000_000_000)
        return Int(clamped.rounded())
    }

    /// Ersetzt NaN/unendliche Werte durch einen Fallback, bevor sie
    /// gespeichert oder weiterverarbeitet werden. Für Werte, die per
    /// Definition > 0 sein müssen (Ziel-Grammwerte etc.).
    func sanitizedNutritionValue(default fallback: Double) -> Double {
        isFinite && self > 0 ? self : fallback
    }

    /// Ersetzt NaN/unendliche Werte durch einen Fallback, ohne eine
    /// zusätzliche Vorzeichen-/Nullbedingung zu erzwingen.
    func sanitizedOrDefault(_ fallback: Double) -> Double {
        isFinite ? self : fallback
    }
}

nonisolated enum CalorieGoalMode: String, Codable, CaseIterable, Identifiable {
    case fixed
    case dynamic

    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
}

enum TrackingInterest: String, CaseIterable, Identifiable, Codable {
    case nutrition
    case training
    case both

    var id: String { rawValue }
    var localizationKey: String { "tracking_interest.\(rawValue)" }
    var descriptionKey: String { "tracking_interest.\(rawValue).description" }
    var iconName: String {
        switch self {
        case .nutrition: "fork.knife"
        case .training: "figure.strengthtraining.traditional"
        case .both: "square.grid.2x2"
        }
    }

    var includesNutrition: Bool { self == .nutrition || self == .both }
    var includesTraining: Bool { self == .training || self == .both }
}

enum NutritionMetric: String, CaseIterable, Identifiable {
    case carbs, protein, fat, addedSugar, salt, fiber, saturatedFat, fruitSugar

    static let homeAdditionalOptions: [NutritionMetric] = [.addedSugar, .fruitSugar, .salt, .fiber, .saturatedFat]

    var id: String { rawValue }

    var title: String {
        LanguageStore.localizedString("nutrition.metric.\(rawValue)")
    }
}

enum NutritionProfile: String, CaseIterable, Identifiable {
    case standard, sport, lowSugar, highProtein, lowCarb, plantBased
    var id: String { rawValue }
    var title: String {
        LanguageStore.localizedString("nutrition.profile.\(rawValue)")
    }
}

enum NutritionActivityLevel: String, CaseIterable, Identifiable, Codable {
    case low, everyday, sporty, veryActive

    var id: String { rawValue }
    var localizationKey: String { "nutrition.activity.\(rawValue)" }
    var descriptionKey: String { "nutrition.activity.\(rawValue).description" }

    /// DGE physical activity level used to scale the user's existing personal target.
    var pal: Double {
        switch self {
        case .low: 1.4
        case .everyday: 1.6
        case .sporty: 1.9
        case .veryActive: 2.2
        }
    }

    /// Conservative orientation target. Even very active profiles stay within
    /// the DGE orientation value of at most 6 g salt per day.
    var saltGoalGrams: Double {
        switch self {
        case .low, .everyday: 5
        case .sporty: 5.5
        case .veryActive: 6
        }
    }
}

enum OnboardingGoal: String, CaseIterable, Identifiable, Codable {
    case loseWeight, maintainWeight, gainWeight, buildMuscle

    var id: String { rawValue }
    var localizationKey: String { "onboarding.profile.goal.\(rawValue)" }
    var descriptionKey: String { "onboarding.profile.goal.\(rawValue).description" }

    var iconName: String {
        switch self {
        case .loseWeight: "arrow.down.right"
        case .maintainWeight: "equal.circle"
        case .gainWeight: "arrow.up.right"
        case .buildMuscle: "dumbbell.fill"
        }
    }
}

enum OnboardingSex: String, CaseIterable, Identifiable, Codable {
    case female, male, unspecified

    var id: String { rawValue }
    var localizationKey: String { "onboarding.profile.sex.\(rawValue)" }

    var calorieFormulaAdjustment: Double {
        switch self {
        case .female: -161
        case .male: 5
        case .unspecified: -78
        }
    }
}

struct OnboardingStartValues: Equatable {
    let calories: Double
    let waterMilliliters: Double
    let carbsPercentage: Int
    let proteinPercentage: Int
    let fatPercentage: Int
}

enum OnboardingCalculator {
    static func calculate(
        goal: OnboardingGoal,
        sex: OnboardingSex,
        ageYears: Int,
        heightCentimeters: Double,
        weightKilograms: Double,
        activityLevel: NutritionActivityLevel
    ) -> OnboardingStartValues {
        let restingEnergy = 10 * weightKilograms
            + 6.25 * heightCentimeters
            - 5 * Double(ageYears)
            + sex.calorieFormulaAdjustment
        let maintenance = max(1_000, restingEnergy * activityLevel.pal)
        let goalAdjustment: Double = switch goal {
        case .loseWeight: -300
        case .maintainWeight: 0
        case .gainWeight: 250
        case .buildMuscle: 200
        }
        let calories = min(5_000, max(1_200, ((maintenance + goalAdjustment) / 50).rounded() * 50))
        let water = min(4_000, max(1_500, (weightKilograms * 35 / 50).rounded() * 50))
        let macros: (Int, Int, Int) = switch goal {
        case .loseWeight: (40, 30, 30)
        case .maintainWeight: (50, 20, 30)
        case .gainWeight: (50, 25, 25)
        case .buildMuscle: (45, 35, 20)
        }
        return OnboardingStartValues(
            calories: calories,
            waterMilliliters: water,
            carbsPercentage: macros.0,
            proteinPercentage: macros.1,
            fatPercentage: macros.2
        )
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case date, calories, training, water, nutrition, meals, steps, fasting
    var id: String { rawValue }
    var title: String {
        LanguageStore.localizedString("dashboard.section.\(rawValue)")
    }
}

enum RestSoundVariant: String, CaseIterable, Identifiable, Codable {
    case alert, signature, soft, bright
    var id: String { rawValue }
    var assetName: String { "hyse-rest-\(rawValue)" }
    var localizationKey: String { "training.feedback.variant.\(rawValue)" }
}

final class UserSettingsStore: ObservableObject {
    /// This value is supplied by the current Premium entitlement. Day-type
    /// adjustments remain stored so they are available again after an upgrade,
    /// but only affect calorie targets while Nutrition Premium is active.
    @Published private(set) var dayTypeCalorieAdjustmentsEnabled = false
    @Published private(set) var advancedMacroGoalsEnabled = false
    @Published private(set) var calorieGoalHistory: [CalorieGoalConfiguration] = [] {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(calorieGoalHistory), forKey: "calorieGoalHistory_v1")
        }
    }
    @Published private(set) var scheduledCaloriePhase: ScheduledCaloriePhase? {
        didSet {
            if let scheduledCaloriePhase {
                UserDefaults.standard.set(try? JSONEncoder().encode(scheduledCaloriePhase), forKey: "scheduledCaloriePhase_v1")
            } else {
                UserDefaults.standard.removeObject(forKey: "scheduledCaloriePhase_v1")
            }
        }
    }
    @Published private(set) var calorieDayTypes: [CalorieDayTypeRecord] = [] {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(calorieDayTypes), forKey: "calorieDayTypes_v1")
        }
    }
    @Published var appTheme: AppTheme {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: "appTheme_v1") }
    }
    @Published var defaultFoodUnit: FoodUnit {
        didSet { UserDefaults.standard.set(defaultFoodUnit.rawValue, forKey: "defaultFoodUnit_v1") }
    }
    @Published var defaultLiquidUnit: FoodUnit {
        didSet { UserDefaults.standard.set(defaultLiquidUnit.rawValue, forKey: "defaultLiquidUnit_v1") }
    }
    @Published var trainingWeightUnit: TrainingWeightUnit {
        didSet { UserDefaults.standard.set(trainingWeightUnit.rawValue, forKey: "trainingWeightUnit_v1") }
    }
    @Published var trainingDistanceUnit: TrainingDistanceUnit {
        didSet { UserDefaults.standard.set(trainingDistanceUnit.rawValue, forKey: "trainingDistanceUnit_v1") }
    }
    @Published var countUnilateralSetsAsHalf: Bool {
        didSet { UserDefaults.standard.set(countUnilateralSetsAsHalf, forKey: TrainingSetStatistics.settingKey) }
    }
    @Published var onboardingGoal: OnboardingGoal {
        didSet { UserDefaults.standard.set(onboardingGoal.rawValue, forKey: "onboardingGoal_v1") }
    }
    @Published var trackingInterest: TrackingInterest {
        didSet { UserDefaults.standard.set(trackingInterest.rawValue, forKey: "trackingInterest_v1") }
    }
    @Published var onboardingSex: OnboardingSex {
        didSet { UserDefaults.standard.set(onboardingSex.rawValue, forKey: "onboardingSex_v1") }
    }
    @Published var profileAgeYears: Int {
        didSet { UserDefaults.standard.set(profileAgeYears, forKey: "profileAgeYears_v1") }
    }
    @Published var profileHeightCentimeters: Double {
        didSet { UserDefaults.standard.set(profileHeightCentimeters, forKey: "profileHeightCentimeters_v1") }
    }
    @Published var profileWeightKilograms: Double {
        didSet { UserDefaults.standard.set(profileWeightKilograms, forKey: "profileWeightKilograms_v1") }
    }
    @Published var defaultWorkoutGymName: String? {
        didSet { UserDefaults.standard.set(defaultWorkoutGymName, forKey: "defaultWorkoutGymName_v1") }
    }
    @Published var defaultWorkoutGymAddress: String? {
        didSet { UserDefaults.standard.set(defaultWorkoutGymAddress, forKey: "defaultWorkoutGymAddress_v1") }
    }
    @Published var defaultWorkoutGymLatitude: Double? {
        didSet { UserDefaults.standard.set(defaultWorkoutGymLatitude, forKey: "defaultWorkoutGymLatitude_v1") }
    }
    @Published var defaultWorkoutGymLongitude: Double? {
        didSet { UserDefaults.standard.set(defaultWorkoutGymLongitude, forKey: "defaultWorkoutGymLongitude_v1") }
    }
    @Published var defaultWorkoutVisibility: String {
        didSet {
            let validValue = defaultWorkoutVisibility == "public" ? "public" : "private"
            UserDefaults.standard.set(validValue, forKey: "defaultWorkoutVisibility_v1")
        }
    }
    @Published var automaticallyStartAppleWatchWorkout: Bool {
        didSet { UserDefaults.standard.set(automaticallyStartAppleWatchWorkout, forKey: "automaticallyStartAppleWatchWorkout_v1") }
    }
    @Published var restSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(restSoundEnabled, forKey: "restSoundEnabled_v1") }
    }
    @Published var restNotificationEnabled: Bool {
        didSet { UserDefaults.standard.set(restNotificationEnabled, forKey: "restNotificationEnabled_v1") }
    }
    @Published var restHapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(restHapticsEnabled, forKey: "restHapticsEnabled_v1") }
    }
    @Published var restSoundVariant: RestSoundVariant {
        didSet { UserDefaults.standard.set(restSoundVariant.rawValue, forKey: "restSoundVariant_v1") }
    }
    @Published var restSoundVolume: Double {
        didSet { UserDefaults.standard.set(min(max(restSoundVolume, 0.1), 1), forKey: "restSoundVolume_v1") }
    }
    @Published var liveActivityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(liveActivityEnabled, forKey: "liveActivityEnabled_v1")
            if !liveActivityEnabled { Task { await TrainingLiveActivityController.shared.endAll() } }
        }
    }
    @Published var motivationNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(motivationNotificationsEnabled, forKey: "motivationNotificationsEnabled_v1")
            MotivationNotificationManager.shared.applyStoredPreference(motivationNotificationConfiguration, language: .persisted)
        }
    }
    @Published var motivationNotificationFrequency: MotivationNotificationFrequency {
        didSet {
            UserDefaults.standard.set(motivationNotificationFrequency.rawValue, forKey: "motivationNotificationFrequency_v1")
            MotivationNotificationManager.shared.applyStoredPreference(motivationNotificationConfiguration, language: .persisted)
        }
    }
    @Published var motivationalMessagesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(motivationalMessagesEnabled, forKey: "motivationalMessagesEnabled_v1")
            MotivationNotificationManager.shared.applyStoredPreference(motivationNotificationConfiguration, language: .persisted)
        }
    }
    @Published var foodLogReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(foodLogReminderEnabled, forKey: "foodLogReminderEnabled_v1")
            MotivationNotificationManager.shared.applyStoredPreference(motivationNotificationConfiguration, language: .persisted)
        }
    }
    @Published var waterReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(waterReminderEnabled, forKey: "waterReminderEnabled_v1") }
    }
    @Published var plannedTrainingReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(plannedTrainingReminderEnabled, forKey: "plannedTrainingReminderEnabled_v1") }
    }
    @Published var missingDailyDataReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(missingDailyDataReminderEnabled, forKey: "missingDailyDataReminderEnabled_v1") }
    }
    @Published var communityNewsNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(communityNewsNotificationsEnabled, forKey: "communityNewsNotificationsEnabled_v1") }
    }
    @Published var hyseUpdateNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(hyseUpdateNotificationsEnabled, forKey: "hyseUpdateNotificationsEnabled_v1") }
    }
    @Published var workoutLikeNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(workoutLikeNotificationsEnabled, forKey: "workoutLikeNotificationsEnabled_v1") }
    }
    @Published var workoutCommentNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(workoutCommentNotificationsEnabled, forKey: "workoutCommentNotificationsEnabled_v1") }
    }
    @Published var friendActivityNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(friendActivityNotificationsEnabled, forKey: "friendActivityNotificationsEnabled_v1") }
    }
    @Published var monthlyTrainingReportNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(monthlyTrainingReportNotificationsEnabled, forKey: "monthlyTrainingReportNotificationsEnabled_v1")
            MonthlyTrainingReportNotificationManager.shared.applyStoredPreference(monthlyTrainingReportNotificationsEnabled, language: .persisted)
        }
    }
    @Published var baseCalorieGoal: Double {
        didSet {
            UserDefaults.standard.set(baseCalorieGoal, forKey: "baseCalorieGoal")
            publishWidgetFallbackGoal()
            recordCurrentCalorieGoalConfiguration()
            // The widget goal is written by ContentView after the effective
            // target and today's active energy have both been resolved. Never
            // overwrite that real daily allowance with this fallback value.
        }
    }

    /// Signed calorie adjustments applied after the regular daily target.
    /// Positive values allow more calories; negative values allow fewer.
    @Published var trainingDayCalorieAdjustment: Double {
        didSet {
            UserDefaults.standard.set(
                trainingDayCalorieAdjustment.sanitizedOrDefault(0),
                forKey: "trainingDayCalorieAdjustment_v1"
            )
            recordCurrentCalorieGoalConfiguration()
        }
    }

    @Published var restDayCalorieAdjustment: Double {
        didSet {
            UserDefaults.standard.set(
                restDayCalorieAdjustment.sanitizedOrDefault(0),
                forKey: "restDayCalorieAdjustment_v1"
            )
            publishWidgetFallbackGoal()
            recordCurrentCalorieGoalConfiguration()
        }
    }

    @Published var enforceCalorieLimit: Bool {
        didSet { UserDefaults.standard.set(enforceCalorieLimit, forKey: "enforceCalorieLimit") }
    }

    @Published var calorieLimitBufferKilocalories: Double {
        didSet {
            UserDefaults.standard.set(
                max(0, calorieLimitBufferKilocalories.sanitizedOrDefault(0)),
                forKey: "calorieLimitBufferKilocalories_v1"
            )
        }
    }

    @Published var foodTrackingWindowEnabled: Bool {
        didSet { UserDefaults.standard.set(foodTrackingWindowEnabled, forKey: "foodTrackingWindowEnabled_v1") }
    }
    @Published var hideNutritionOutsideTrackingWindow: Bool {
        didSet { UserDefaults.standard.set(hideNutritionOutsideTrackingWindow, forKey: "hideNutritionOutsideTrackingWindow_v1") }
    }
    @Published var lockTrackingWindowSettingsOutsideHours: Bool {
        didSet { UserDefaults.standard.set(lockTrackingWindowSettingsOutsideHours, forKey: "lockTrackingWindowSettingsOutsideHours_v1") }
    }
    @Published var blockFoodTrackingWhileFastingEnabled: Bool {
        didSet { UserDefaults.standard.set(blockFoodTrackingWhileFastingEnabled, forKey: "blockFoodTrackingWhileFastingEnabled_v1") }
    }
    @Published var foodTrackingWindowStartMinutes: Int {
        didSet { UserDefaults.standard.set(FoodTrackingPolicy.normalizedMinutes(foodTrackingWindowStartMinutes), forKey: "foodTrackingWindowStartMinutes_v1") }
    }
    @Published var foodTrackingWindowEndMinutes: Int {
        didSet { UserDefaults.standard.set(FoodTrackingPolicy.normalizedMinutes(foodTrackingWindowEndMinutes), forKey: "foodTrackingWindowEndMinutes_v1") }
    }
    @Published var lowRemainingTrackingLockEnabled: Bool {
        didSet { UserDefaults.standard.set(lowRemainingTrackingLockEnabled, forKey: "lowRemainingTrackingLockEnabled_v1") }
    }
    @Published var lowRemainingTrackingLockStartMinutes: Int {
        didSet { UserDefaults.standard.set(FoodTrackingPolicy.normalizedMinutes(lowRemainingTrackingLockStartMinutes), forKey: "lowRemainingTrackingLockStartMinutes_v1") }
    }
    @Published var lowRemainingTrackingCaloriesThreshold: Double {
        didSet { UserDefaults.standard.set(max(0, lowRemainingTrackingCaloriesThreshold.sanitizedOrDefault(200)), forKey: "lowRemainingTrackingCaloriesThreshold_v1") }
    }
    @Published var lowCalorieEntryWarningEnabled: Bool {
        didSet { UserDefaults.standard.set(lowCalorieEntryWarningEnabled, forKey: "lowCalorieEntryWarningEnabled_v1") }
    }
    @Published var lowCalorieEntryWarningThreshold: Double {
        didSet { UserDefaults.standard.set(max(0, lowCalorieEntryWarningThreshold.sanitizedOrDefault(600)), forKey: "lowCalorieEntryWarningThreshold_v1") }
    }

    @Published var calorieGoalMode: CalorieGoalMode {
        didSet {
            UserDefaults.standard.set(calorieGoalMode.rawValue, forKey: "calorieGoalMode_v1")
            recordCurrentCalorieGoalConfiguration()
        }
    }

    @Published var dynamicCalorieTargetMode: DynamicCalorieTargetMode {
        didSet {
            UserDefaults.standard.set(dynamicCalorieTargetMode.rawValue, forKey: "dynamicCalorieTargetMode_v1")
            recordCurrentCalorieGoalConfiguration()
        }
    }

    @Published var fixedCalorieSurplus: Double {
        didSet {
            UserDefaults.standard.set(max(0, fixedCalorieSurplus.sanitizedOrDefault(300)), forKey: "fixedCalorieSurplus_v1")
            recordCurrentCalorieGoalConfiguration()
        }
    }

    @Published var fixedCalorieDeficit: Double {
        didSet {
            UserDefaults.standard.set(max(0, fixedCalorieDeficit.sanitizedOrDefault(300)), forKey: "fixedCalorieDeficit_v1")
            recordCurrentCalorieGoalConfiguration()
        }
    }

    @Published private(set) var dynamicDeficitPhaseStartDate: Date? {
        didSet { UserDefaults.standard.set(dynamicDeficitPhaseStartDate, forKey: "dynamicDeficitPhaseStartDate_v1") }
    }

    @Published private(set) var dynamicDeficitInitialBodyFatFraction: Double? {
        didSet { UserDefaults.standard.set(dynamicDeficitInitialBodyFatFraction, forKey: "dynamicDeficitInitialBodyFatFraction_v1") }
    }

    @Published private(set) var dynamicDeficitInitialWeightKilograms: Double? {
        didSet { UserDefaults.standard.set(dynamicDeficitInitialWeightKilograms, forKey: "dynamicDeficitInitialWeightKilograms_v1") }
    }

    @Published private(set) var dynamicDeficitPhases: [DynamicDeficitPhase] {
        didSet {
            UserDefaults.standard.set(
                try? JSONEncoder().encode(dynamicDeficitPhases),
                forKey: "dynamicDeficitPhases_v2"
            )
        }
    }

    @Published var carbsPercentage: Int {
        didSet { UserDefaults.standard.set(carbsPercentage, forKey: "carbsPercentage") }
    }

    @Published var proteinPercentage: Int {
        didSet { UserDefaults.standard.set(proteinPercentage, forKey: "proteinPercentage") }
    }

    @Published var fatPercentage: Int {
        didSet { UserDefaults.standard.set(fatPercentage, forKey: "fatPercentage") }
    }

    @Published private(set) var macroGoalPlan: MacroGoalPlan {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(macroGoalPlan), forKey: "macroGoalPlan_v1") }
    }

    @Published var nutritionActivityLevel: NutritionActivityLevel {
        didSet { UserDefaults.standard.set(nutritionActivityLevel.rawValue, forKey: "nutritionActivityLevel_v1") }
    }

    @Published var visibleNutritionMetricIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(visibleNutritionMetricIDs), forKey: "visibleNutritionMetricIDs") }
    }

    @Published var homeAdditionalNutritionMetricIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(homeAdditionalNutritionMetricIDs), forKey: "homeAdditionalNutritionMetricIDs_v1") }
    }

    @Published var dailyWaterGoalMilliliters: Double {
        didSet {
            UserDefaults.standard.set(dailyWaterGoalMilliliters, forKey: "dailyWaterGoalMilliliters")
            publishWidgetWaterGoal()
        }
    }

    @Published var waterGlassSizeMilliliters: Double {
        didSet { UserDefaults.standard.set(waterGlassSizeMilliliters, forKey: "waterGlassSizeMilliliters") }
    }
    @Published var addedSugarGoalGrams: Double { didSet { saveNutritionTargets() } }
    @Published var fruitSugarGoalGrams: Double { didSet { saveNutritionTargets() } }
    @Published var saltGoalGrams: Double { didSet { saveNutritionTargets() } }
    @Published var fiberGoalGrams: Double { didSet { saveNutritionTargets() } }
    @Published var saturatedFatGoalGrams: Double { didSet { saveNutritionTargets() } }
    @Published var selectedNutritionProfileIDs: Set<String> { didSet { UserDefaults.standard.set(Array(selectedNutritionProfileIDs), forKey: "nutritionProfiles_v1") } }
    /// Reihenfolge und Sichtbarkeit werden getrennt gespeichert, damit ein
    /// ausgeblendeter Bereich beim erneuten Anzeigen an seine alte Position zurückkehrt.
    @Published var dashboardSectionIDs: [String] { didSet { UserDefaults.standard.set(dashboardSectionIDs, forKey: "dashboardSectionOrder_v1") } }
    @Published var visibleDashboardSectionIDs: Set<String> { didSet { UserDefaults.standard.set(Array(visibleDashboardSectionIDs), forKey: "dashboardSectionIDs_v1") } }

    init() {
        self.appTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme_v1") ?? "") ?? .system
        let legacyFoodUnit = FoodUnit(rawValue: UserDefaults.standard.string(forKey: "defaultFoodUnit_v1") ?? "") ?? .gram
        self.defaultFoodUnit = legacyFoodUnit.isVolume ? .gram : legacyFoodUnit
        let savedLiquidUnit = FoodUnit(rawValue: UserDefaults.standard.string(forKey: "defaultLiquidUnit_v1") ?? "")
        self.defaultLiquidUnit = savedLiquidUnit.flatMap { $0.isVolume ? $0 : nil }
            ?? (legacyFoodUnit.isVolume ? legacyFoodUnit : .milliliter)
        self.trainingWeightUnit = TrainingWeightUnit(rawValue: UserDefaults.standard.string(forKey: "trainingWeightUnit_v1") ?? "") ?? .kilograms
        self.trainingDistanceUnit = TrainingDistanceUnit(rawValue: UserDefaults.standard.string(forKey: "trainingDistanceUnit_v1") ?? "") ?? .kilometers
        self.countUnilateralSetsAsHalf = UserDefaults.standard.bool(forKey: TrainingSetStatistics.settingKey)
        self.onboardingGoal = OnboardingGoal(rawValue: UserDefaults.standard.string(forKey: "onboardingGoal_v1") ?? "") ?? .maintainWeight
        self.trackingInterest = TrackingInterest(rawValue: UserDefaults.standard.string(forKey: "trackingInterest_v1") ?? "") ?? .both
        self.onboardingSex = OnboardingSex(rawValue: UserDefaults.standard.string(forKey: "onboardingSex_v1") ?? "") ?? .unspecified
        self.profileAgeYears = max(13, UserDefaults.standard.object(forKey: "profileAgeYears_v1") as? Int ?? 30)
        self.profileHeightCentimeters = max(120, UserDefaults.standard.object(forKey: "profileHeightCentimeters_v1") as? Double ?? 170)
        self.profileWeightKilograms = max(35, UserDefaults.standard.object(forKey: "profileWeightKilograms_v1") as? Double ?? 70)
        self.defaultWorkoutGymName = UserDefaults.standard.string(forKey: "defaultWorkoutGymName_v1")
        self.defaultWorkoutGymAddress = UserDefaults.standard.string(forKey: "defaultWorkoutGymAddress_v1")
        self.defaultWorkoutGymLatitude = UserDefaults.standard.object(forKey: "defaultWorkoutGymLatitude_v1") as? Double
        self.defaultWorkoutGymLongitude = UserDefaults.standard.object(forKey: "defaultWorkoutGymLongitude_v1") as? Double
        self.defaultWorkoutVisibility = UserDefaults.standard.string(forKey: "defaultWorkoutVisibility_v1") == "public" ? "public" : "private"
        self.automaticallyStartAppleWatchWorkout = UserDefaults.standard.object(forKey: "automaticallyStartAppleWatchWorkout_v1") as? Bool ?? true
        self.restSoundEnabled = UserDefaults.standard.object(forKey: "restSoundEnabled_v1") as? Bool ?? true
        self.restNotificationEnabled = UserDefaults.standard.object(forKey: "restNotificationEnabled_v1") as? Bool ?? true
        self.restHapticsEnabled = UserDefaults.standard.object(forKey: "restHapticsEnabled_v1") as? Bool ?? true
        if !UserDefaults.standard.bool(forKey: "restSoundAlertUpgrade_v2") {
            UserDefaults.standard.set(RestSoundVariant.alert.rawValue, forKey: "restSoundVariant_v1")
            UserDefaults.standard.set(true, forKey: "restSoundAlertUpgrade_v2")
        }
        self.restSoundVariant = RestSoundVariant(rawValue: UserDefaults.standard.string(forKey: "restSoundVariant_v1") ?? "") ?? .alert
        self.restSoundVolume = UserDefaults.standard.object(forKey: "restSoundVolume_v1") as? Double ?? 0.8
        self.liveActivityEnabled = UserDefaults.standard.object(forKey: "liveActivityEnabled_v1") as? Bool ?? true
        self.motivationNotificationsEnabled = UserDefaults.standard.object(forKey: "motivationNotificationsEnabled_v1") as? Bool ?? true
        self.motivationNotificationFrequency = MotivationNotificationFrequency(rawValue: UserDefaults.standard.string(forKey: "motivationNotificationFrequency_v1") ?? "") ?? .daily
        self.motivationalMessagesEnabled = UserDefaults.standard.object(forKey: "motivationalMessagesEnabled_v1") as? Bool ?? false
        self.foodLogReminderEnabled = UserDefaults.standard.object(forKey: "foodLogReminderEnabled_v1") as? Bool ?? true
        self.waterReminderEnabled = UserDefaults.standard.object(forKey: "waterReminderEnabled_v1") as? Bool ?? false
        self.plannedTrainingReminderEnabled = UserDefaults.standard.object(forKey: "plannedTrainingReminderEnabled_v1") as? Bool ?? false
        self.missingDailyDataReminderEnabled = UserDefaults.standard.object(forKey: "missingDailyDataReminderEnabled_v1") as? Bool ?? false
        self.communityNewsNotificationsEnabled = UserDefaults.standard.object(forKey: "communityNewsNotificationsEnabled_v1") as? Bool ?? false
        self.hyseUpdateNotificationsEnabled = UserDefaults.standard.object(forKey: "hyseUpdateNotificationsEnabled_v1") as? Bool ?? false
        self.workoutLikeNotificationsEnabled = UserDefaults.standard.object(forKey: "workoutLikeNotificationsEnabled_v1") as? Bool ?? false
        self.workoutCommentNotificationsEnabled = UserDefaults.standard.object(forKey: "workoutCommentNotificationsEnabled_v1") as? Bool ?? false
        self.friendActivityNotificationsEnabled = UserDefaults.standard.object(forKey: "friendActivityNotificationsEnabled_v1") as? Bool ?? false
        self.monthlyTrainingReportNotificationsEnabled = UserDefaults.standard.object(forKey: "monthlyTrainingReportNotificationsEnabled_v1") as? Bool ?? true
        let savedGoal = UserDefaults.standard.double(forKey: "baseCalorieGoal")
        self.baseCalorieGoal = (savedGoal.isFinite && savedGoal > 0) ? savedGoal : 2400.0
        let storedTrainingDayAdjustment = UserDefaults.standard.object(forKey: "trainingDayCalorieAdjustment_v1") as? Double
        let storedRestDayAdjustment = UserDefaults.standard.object(forKey: "restDayCalorieAdjustment_v1") as? Double
        self.trainingDayCalorieAdjustment = (storedTrainingDayAdjustment ?? 0).sanitizedOrDefault(0)
        self.restDayCalorieAdjustment = (storedRestDayAdjustment ?? 0).sanitizedOrDefault(0)

        self.enforceCalorieLimit = UserDefaults.standard.object(forKey: "enforceCalorieLimit") as? Bool ?? false
        let storedCalorieLimitBuffer = UserDefaults.standard.object(forKey: "calorieLimitBufferKilocalories_v1") as? Double
        self.calorieLimitBufferKilocalories = max(0, (storedCalorieLimitBuffer ?? 0).sanitizedOrDefault(0))
        self.blockFoodTrackingWhileFastingEnabled = UserDefaults.standard.object(forKey: "blockFoodTrackingWhileFastingEnabled_v1") as? Bool ?? false
        self.foodTrackingWindowEnabled = UserDefaults.standard.object(forKey: "foodTrackingWindowEnabled_v1") as? Bool ?? false
        self.hideNutritionOutsideTrackingWindow = UserDefaults.standard.object(forKey: "hideNutritionOutsideTrackingWindow_v1") as? Bool ?? false
        self.lockTrackingWindowSettingsOutsideHours = UserDefaults.standard.object(forKey: "lockTrackingWindowSettingsOutsideHours_v1") as? Bool ?? false
        self.foodTrackingWindowStartMinutes = FoodTrackingPolicy.normalizedMinutes(UserDefaults.standard.object(forKey: "foodTrackingWindowStartMinutes_v1") as? Int ?? 6 * 60)
        self.foodTrackingWindowEndMinutes = FoodTrackingPolicy.normalizedMinutes(UserDefaults.standard.object(forKey: "foodTrackingWindowEndMinutes_v1") as? Int ?? 18 * 60)
        self.lowRemainingTrackingLockEnabled = UserDefaults.standard.object(forKey: "lowRemainingTrackingLockEnabled_v1") as? Bool ?? false
        self.lowRemainingTrackingLockStartMinutes = FoodTrackingPolicy.normalizedMinutes(UserDefaults.standard.object(forKey: "lowRemainingTrackingLockStartMinutes_v1") as? Int ?? 18 * 60)
        let storedTrackingThreshold = UserDefaults.standard.object(forKey: "lowRemainingTrackingCaloriesThreshold_v1") as? Double
        self.lowRemainingTrackingCaloriesThreshold = max(0, (storedTrackingThreshold ?? 200).sanitizedOrDefault(200))
        self.lowCalorieEntryWarningEnabled = UserDefaults.standard.object(forKey: "lowCalorieEntryWarningEnabled_v1") as? Bool ?? true
        let storedWarningThreshold = UserDefaults.standard.object(forKey: "lowCalorieEntryWarningThreshold_v1") as? Double
        self.lowCalorieEntryWarningThreshold = max(0, (storedWarningThreshold ?? 600).sanitizedOrDefault(600))
        self.calorieGoalMode = CalorieGoalMode(rawValue: UserDefaults.standard.string(forKey: "calorieGoalMode_v1") ?? "") ?? .fixed
        self.dynamicCalorieTargetMode = DynamicCalorieTargetMode(rawValue: UserDefaults.standard.string(forKey: "dynamicCalorieTargetMode_v1") ?? "") ?? .deficit
        let storedSurplus = UserDefaults.standard.object(forKey: "fixedCalorieSurplus_v1") as? Double
        self.fixedCalorieSurplus = max(0, (storedSurplus ?? 300).sanitizedOrDefault(300))
        let storedDeficit = UserDefaults.standard.object(forKey: "fixedCalorieDeficit_v1") as? Double
        self.fixedCalorieDeficit = max(0, (storedDeficit ?? 300).sanitizedOrDefault(300))
        let storedSchedule = UserDefaults.standard.data(forKey: "scheduledCaloriePhase_v1")
            .flatMap { try? JSONDecoder().decode(ScheduledCaloriePhase.self, from: $0) }
        self.scheduledCaloriePhase = storedSchedule?.isValid == true ? storedSchedule : nil
        let storedPhaseStartDate = UserDefaults.standard.object(forKey: "dynamicDeficitPhaseStartDate_v1") as? Date
        let storedInitialBodyFatFraction = UserDefaults.standard.object(forKey: "dynamicDeficitInitialBodyFatFraction_v1") as? Double
        let storedInitialWeightKilograms = UserDefaults.standard.object(forKey: "dynamicDeficitInitialWeightKilograms_v1") as? Double
        self.dynamicDeficitPhaseStartDate = storedPhaseStartDate
        self.dynamicDeficitInitialBodyFatFraction = storedInitialBodyFatFraction
        self.dynamicDeficitInitialWeightKilograms = storedInitialWeightKilograms
        let storedPhaseHistory = UserDefaults.standard.data(forKey: "dynamicDeficitPhases_v2")
            .flatMap { try? JSONDecoder().decode([DynamicDeficitPhase].self, from: $0) } ?? []
        if !storedPhaseHistory.isEmpty {
            self.dynamicDeficitPhases = storedPhaseHistory.sorted { $0.startedAt < $1.startedAt }
        } else if let startedAt = storedPhaseStartDate,
                  let bodyFat = storedInitialBodyFatFraction,
                  let weight = storedInitialWeightKilograms,
                  bodyFat.isFinite, weight.isFinite,
                  bodyFat > 0, weight > 0 {
            // One-time local migration from the previous single-phase model.
            self.dynamicDeficitPhases = [DynamicDeficitPhase(
                startedAt: Calendar.current.startOfDay(for: startedAt),
                initialBodyFatFraction: bodyFat,
                initialWeightKilograms: weight
            )]
        } else {
            self.dynamicDeficitPhases = []
        }

        let savedCarbs = UserDefaults.standard.integer(forKey: "carbsPercentage")
        let savedProtein = UserDefaults.standard.integer(forKey: "proteinPercentage")
        let savedFat = UserDefaults.standard.integer(forKey: "fatPercentage")

        if savedCarbs + savedProtein + savedFat == 100 {
            self.carbsPercentage = savedCarbs
            self.proteinPercentage = savedProtein
            self.fatPercentage = savedFat
        } else {
            self.carbsPercentage = 50
            self.proteinPercentage = 20
            self.fatPercentage = 30
        }
        self.macroGoalPlan = UserDefaults.standard.data(forKey: "macroGoalPlan_v1")
            .flatMap { try? JSONDecoder().decode(MacroGoalPlan.self, from: $0) } ?? MacroGoalPlan()
        self.nutritionActivityLevel = NutritionActivityLevel(rawValue: UserDefaults.standard.string(forKey: "nutritionActivityLevel_v1") ?? "") ?? .everyday

        let allMetricIDs = Set(NutritionMetric.allCases.map(\.rawValue))
        let savedMetricIDs = UserDefaults.standard.stringArray(forKey: "visibleNutritionMetricIDs")
        let validMetricIDs = Set(savedMetricIDs ?? []).intersection(allMetricIDs)
        let defaultMetrics = Set([NutritionMetric.carbs, .protein, .fat, .fiber].map(\.rawValue))
        self.visibleNutritionMetricIDs = validMetricIDs.isEmpty ? defaultMetrics : validMetricIDs
        let homeMetricIDs = Set(NutritionMetric.homeAdditionalOptions.map(\.rawValue))
        self.homeAdditionalNutritionMetricIDs = Set(UserDefaults.standard.stringArray(forKey: "homeAdditionalNutritionMetricIDs_v1") ?? [])
            .intersection(homeMetricIDs)

        let savedWaterGoal = UserDefaults.standard.double(forKey: "dailyWaterGoalMilliliters")
        self.dailyWaterGoalMilliliters = (savedWaterGoal.isFinite && savedWaterGoal > 0) ? savedWaterGoal : 2_000
        let savedGlassSize = UserDefaults.standard.double(forKey: "waterGlassSizeMilliliters")
        self.waterGlassSizeMilliliters = (savedGlassSize.isFinite && savedGlassSize > 0) ? savedGlassSize : 250

        // Ältere oder fehlerhaft synchronisierte Werte können NaN/unendlich
        // sein. `targets["x"] ?? default` fängt das nicht ab, da der Wert ja
        // nicht nil ist – daher zusätzlich auf Endlichkeit prüfen.
        let targets = UserDefaults.standard.dictionary(forKey: "nutritionTargets_v1") as? [String: Double] ?? [:]
        self.addedSugarGoalGrams = (targets["addedSugar"] ?? 30).sanitizedNutritionValue(default: 30)
        self.fruitSugarGoalGrams = (targets["fruitSugar"] ?? 50).sanitizedNutritionValue(default: 50)
        self.saltGoalGrams = (targets["salt"] ?? 5).sanitizedNutritionValue(default: 5)
        self.fiberGoalGrams = (targets["fiber"] ?? 30).sanitizedNutritionValue(default: 30)
        self.saturatedFatGoalGrams = (targets["saturatedFat"] ?? 27).sanitizedNutritionValue(default: 27)
        let savedProfiles = Set(UserDefaults.standard.stringArray(forKey: "nutritionProfiles_v1") ?? [NutritionProfile.standard.rawValue])
        self.selectedNutritionProfileIDs = savedProfiles.isEmpty ? [NutritionProfile.standard.rawValue] : savedProfiles
        let defaultDashboard: [String] = [
            DashboardSection.date.rawValue,
            DashboardSection.calories.rawValue,
            DashboardSection.water.rawValue,
            DashboardSection.nutrition.rawValue,
            DashboardSection.meals.rawValue,
            DashboardSection.steps.rawValue,
            DashboardSection.fasting.rawValue
        ]
        let legacyDashboard = UserDefaults.standard.stringArray(forKey: "dashboardSectionIDs_v1")
        let savedOrder = UserDefaults.standard.stringArray(forKey: "dashboardSectionOrder_v1")
        let validDashboard = (savedOrder ?? legacyDashboard ?? defaultDashboard).filter {
            DashboardSection(rawValue: $0) != nil && $0 != DashboardSection.training.rawValue
        }
        // Mahlzeiten bleiben als zentraler Navigationsbereich immer erreichbar.
        var completeOrder = validDashboard
        for id in defaultDashboard where !completeOrder.contains(id) {
            completeOrder.append(id)
        }
        self.dashboardSectionIDs = completeOrder
        var visibleDashboardIDs = Set((legacyDashboard ?? defaultDashboard).filter {
            DashboardSection(rawValue: $0) != nil && $0 != DashboardSection.training.rawValue
        } + [DashboardSection.meals.rawValue])
        // Enable the wellness cards once for both new and existing installs.
        // A versioned marker lets later launches respect deliberate switches.
        if !UserDefaults.standard.bool(forKey: "wellnessDashboardVisibilityMigrated_v2") {
            visibleDashboardIDs.formUnion([DashboardSection.steps.rawValue, DashboardSection.fasting.rawValue])
            UserDefaults.standard.set(true, forKey: "wellnessDashboardVisibilityMigrated_v2")
        }
        self.visibleDashboardSectionIDs = visibleDashboardIDs

        let storedGoalHistory = UserDefaults.standard.data(forKey: "calorieGoalHistory_v1")
            .flatMap { try? JSONDecoder().decode([CalorieGoalConfiguration].self, from: $0) } ?? []
        restoreCalorieGoalHistory(storedGoalHistory)
        calorieDayTypes = UserDefaults.standard.data(forKey: "calorieDayTypes_v1")
            .flatMap { try? JSONDecoder().decode([CalorieDayTypeRecord].self, from: $0) } ?? []
        publishWidgetFallbackGoal()
        publishWidgetWaterGoal()
        MotivationNotificationManager.shared.applyStoredPreference(motivationNotificationConfiguration, language: .persisted)
        MonthlyTrainingReportNotificationManager.shared.applyStoredPreference(monthlyTrainingReportNotificationsEnabled, language: .persisted)
    }

    var motivationNotificationConfiguration: MotivationNotificationConfiguration {
        MotivationNotificationConfiguration(
            enabled: motivationNotificationsEnabled,
            frequency: motivationNotificationFrequency,
            motivationalMessages: motivationalMessagesEnabled,
            foodLogReminder: foodLogReminderEnabled,
            waterReminder: waterReminderEnabled,
            plannedTrainingReminder: plannedTrainingReminderEnabled,
            missingDailyDataReminder: missingDailyDataReminderEnabled
        )
    }

    func targetCarbsGrams(availableCalories: Double) -> Double {
        if let targets = flexibleMacroTargets(availableCalories: availableCalories) { return targets.carbs }
        return (availableCalories * (Double(carbsPercentage) / 100.0)) / 4.0
    }

    var dynamicDeficitPhase: DynamicDeficitPhase? {
        dynamicDeficitPhases.last
    }

    func setScheduledCaloriePhase(_ phase: ScheduledCaloriePhase?) {
        scheduledCaloriePhase = phase?.isValid == true ? phase : nil
    }

    /// Returns true exactly once when a pending plan becomes the active goal.
    @discardableResult
    func activateScheduledCaloriePhaseIfDue(now: Date = Date(), latestWeightKilograms: Double?) -> Bool {
        guard let plan = scheduledCaloriePhase,
              plan.isDue(now: now, latestWeightKilograms: latestWeightKilograms) else { return false }
        let startWeight: Double? = plan.weightSource == .manual
            ? plan.manualStartWeightKilograms : latestWeightKilograms
        let previousHistory = calorieGoalHistory
        if plan.goalMode == .dynamic && plan.dynamicMode == .deficit {
            guard let startWeight, startWeight.isFinite, startWeight > 0,
                  let bodyFat = plan.bodyFatPercentage,
                  startDynamicDeficitPhase(bodyFatPercentage: bodyFat, weightKilograms: startWeight, on: now)
            else { return false }
        }
        baseCalorieGoal = plan.fixedGoal
        fixedCalorieDeficit = plan.fixedDeficit
        fixedCalorieSurplus = plan.fixedSurplus
        dynamicCalorieTargetMode = plan.dynamicMode
        calorieGoalMode = plan.goalMode
        let startDay = Calendar.current.startOfDay(for: now)
        var configuration = currentCalorieGoalConfiguration(startedAt: startDay)
        configuration.startedAt = startDay
        calorieGoalHistory = previousHistory.filter { $0.startedAt < startDay } + [configuration]
        if let macros = plan.macroGoals {
            if macros.plan.mode == .percentages {
                _ = updateMacros(carbs: macros.carbsPercentage, protein: macros.proteinPercentage, fat: macros.fatPercentage)
            }
            _ = updateMacroGoalPlan(macros.plan)
        }
        scheduledCaloriePhase = nil
        return true
    }

    func startDynamicDeficitPhase(bodyFatPercentage: Double, weightKilograms: Double, on date: Date = Date()) -> Bool {
        guard bodyFatPercentage.isFinite, weightKilograms.isFinite,
              bodyFatPercentage > 0, weightKilograms > 0 else { return false }
        let start = Calendar.current.startOfDay(for: date)
        let phase = DynamicDeficitPhase(
            startedAt: start,
            initialBodyFatFraction: bodyFatPercentage / 100,
            initialWeightKilograms: weightKilograms
        )
        var phases = dynamicDeficitPhases.filter { !Calendar.current.isDate($0.startedAt, inSameDayAs: start) }
        phases.append(phase)
        dynamicDeficitPhases = phases.sorted { $0.startedAt < $1.startedAt }
        dynamicDeficitPhaseStartDate = start
        dynamicDeficitInitialBodyFatFraction = phase.initialBodyFatFraction
        dynamicDeficitInitialWeightKilograms = phase.initialWeightKilograms
        dynamicCalorieTargetMode = .deficit
        calorieGoalMode = .dynamic
        return true
    }

    func setFixedCalorieSurplus(_ kilocalories: Double) -> Bool {
        guard kilocalories.isFinite, kilocalories > 0 else { return false }
        fixedCalorieSurplus = kilocalories
        dynamicCalorieTargetMode = .surplus
        calorieGoalMode = .dynamic
        return true
    }

    func restoreDynamicDeficitPhase(_ phase: DynamicDeficitPhase) {
        var phases = dynamicDeficitPhases.filter { !Calendar.current.isDate($0.startedAt, inSameDayAs: phase.startedAt) }
        phases.append(phase)
        restoreDynamicDeficitPhases(phases)
    }

    func restoreDynamicDeficitPhases(_ phases: [DynamicDeficitPhase]) {
        let valid = phases.filter {
            $0.initialBodyFatFraction.isFinite && $0.initialWeightKilograms.isFinite &&
            $0.initialBodyFatFraction > 0 && $0.initialWeightKilograms > 0
        }
        var byDay: [Date: DynamicDeficitPhase] = [:]
        for phase in valid {
            let day = Calendar.current.startOfDay(for: phase.startedAt)
            byDay[day] = DynamicDeficitPhase(
                startedAt: day,
                initialBodyFatFraction: phase.initialBodyFatFraction,
                initialWeightKilograms: phase.initialWeightKilograms
            )
        }
        dynamicDeficitPhases = byDay.values.sorted { $0.startedAt < $1.startedAt }
        guard let current = dynamicDeficitPhases.last else { return }
        dynamicDeficitPhaseStartDate = current.startedAt
        dynamicDeficitInitialBodyFatFraction = current.initialBodyFatFraction
        dynamicDeficitInitialWeightKilograms = current.initialWeightKilograms
    }

    /// The only source of truth for the daily base target. Active energy is
    /// applied separately after this calculation according to the goal mode.
    func calorieTarget(for date: Date, previousDayEnergy: DailyEnergy?) -> DynamicCalorieTargetBreakdown {
        let configuration = calorieGoalConfiguration(for: date)
        return CalorieTargetCalculator.target(
            mode: configuration.mode,
            fixedGoal: configuration.fixedGoal,
            dynamicMode: configuration.dynamicMode,
            fixedSurplus: configuration.fixedSurplus,
            fixedDeficit: configuration.fixedDeficit ?? 300,
            phase: CalorieTargetCalculator.activePhase(in: dynamicDeficitPhases, for: date),
            targetDate: date,
            previousDayEnergy: previousDayEnergy
        )
    }

    func availableCalories(for date: Date, targetKilocalories: Double, activeEnergy: Double, isTrainingDay: Bool = false) -> Double {
        let configuration = calorieGoalConfiguration(for: date)
        return CalorieTargetCalculator.availableCalories(
            mode: configuration.mode,
            targetKilocalories: targetKilocalories,
            activeEnergy: activeEnergy,
            dayAdjustment: configuration.dayTypeAdjustmentsEnabled
                ? (isTrainingDay ? configuration.trainingDayAdjustment : configuration.restDayAdjustment)
                : 0
        )
    }

    func dayTypeAdjustment(for date: Date, isTrainingDay: Bool) -> Double {
        let configuration = calorieGoalConfiguration(for: date)
        guard configuration.dayTypeAdjustmentsEnabled else { return 0 }
        return isTrainingDay ? configuration.trainingDayAdjustment : configuration.restDayAdjustment
    }

    func trainingDayStatus(for date: Date, currentlyTraining: Bool) -> Bool {
        guard Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date()) else {
            return currentlyTraining
        }
        return calorieDayTypes.first { Calendar.current.isDate($0.day, inSameDayAs: date) }?.isTrainingDay ?? currentlyTraining
    }

    @discardableResult
    func recordTrainingDayStatus(for date: Date, isTrainingDay: Bool) -> Bool {
        guard Calendar.current.isDateInToday(date) else { return false }
        let day = Calendar.current.startOfDay(for: date)
        var values = calorieDayTypes
        if let index = values.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
            guard values[index].isTrainingDay != isTrainingDay else { return false }
            values[index] = CalorieDayTypeRecord(day: day, isTrainingDay: isTrainingDay)
        } else {
            values.append(CalorieDayTypeRecord(day: day, isTrainingDay: isTrainingDay))
        }
        calorieDayTypes = values
        return true
    }

    func restoreCalorieDayTypes(_ values: [CalorieDayTypeRecord]) {
        var byDay: [Date: CalorieDayTypeRecord] = [:]
        for value in values {
            let day = Calendar.current.startOfDay(for: value.day)
            byDay[day] = CalorieDayTypeRecord(day: day, isTrainingDay: value.isTrainingDay)
        }
        calorieDayTypes = byDay.values.sorted { $0.day < $1.day }
    }

    func calorieGoalConfiguration(for date: Date) -> CalorieGoalConfiguration {
        var configuration = Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: Date())
            ? currentCalorieGoalConfiguration()
            : (CalorieGoalHistory.active(in: calorieGoalHistory, for: date) ?? currentCalorieGoalConfiguration())
        // Keep the user's selected mode in storage and account sync. A missing
        // entitlement only changes the effective target until access returns.
        if !dayTypeCalorieAdjustmentsEnabled {
            configuration.mode = .fixed
            configuration.dayTypeAdjustmentsEnabled = false
        }
        return configuration
    }

    func restoreCalorieGoalHistory(_ history: [CalorieGoalConfiguration]) {
        let valid = history.filter {
            $0.fixedGoal.isFinite && $0.fixedGoal > 0 && $0.fixedSurplus.isFinite && $0.fixedSurplus >= 0 &&
            ($0.fixedDeficit.map { $0.isFinite && $0 >= 0 } ?? true) &&
            $0.trainingDayAdjustment.isFinite && $0.restDayAdjustment.isFinite
        }
        calorieGoalHistory = valid.isEmpty
            ? [currentCalorieGoalConfiguration(startedAt: .distantPast)]
            : valid.sorted { $0.startedAt < $1.startedAt }
    }

    private func currentCalorieGoalConfiguration(startedAt: Date = Date()) -> CalorieGoalConfiguration {
        CalorieGoalConfiguration(
            startedAt: startedAt,
            fixedGoal: baseCalorieGoal.isFinite && baseCalorieGoal > 0 ? baseCalorieGoal : 2400,
            mode: calorieGoalMode,
            dynamicMode: dynamicCalorieTargetMode,
            fixedSurplus: max(0, fixedCalorieSurplus.sanitizedOrDefault(300)),
            fixedDeficit: max(0, fixedCalorieDeficit.sanitizedOrDefault(300)),
            trainingDayAdjustment: trainingDayCalorieAdjustment.sanitizedOrDefault(0),
            restDayAdjustment: restDayCalorieAdjustment.sanitizedOrDefault(0),
            dayTypeAdjustmentsEnabled: dayTypeCalorieAdjustmentsEnabled
        )
    }

    private func recordCurrentCalorieGoalConfiguration() {
        guard !calorieGoalHistory.isEmpty else { return }
        let updated = CalorieGoalHistory.recording(
            currentCalorieGoalConfiguration(), in: calorieGoalHistory, on: Date()
        )
        if updated != calorieGoalHistory { calorieGoalHistory = updated }
    }

    func setDayTypeCalorieAdjustmentsEnabled(_ enabled: Bool) {
        guard dayTypeCalorieAdjustmentsEnabled != enabled else { return }
        dayTypeCalorieAdjustmentsEnabled = enabled
        publishWidgetFallbackGoal()
        recordCurrentCalorieGoalConfiguration()
    }

    func maximumAllowedCalories(_ availableCalories: Double) -> Double {
        availableCalories + max(0, calorieLimitBufferKilocalories)
    }

    var foodTrackingRules: FoodTrackingRules {
        FoodTrackingRules(
            blockWhileFastingEnabled: blockFoodTrackingWhileFastingEnabled,
            windowEnabled: foodTrackingWindowEnabled,
            windowStartMinutes: foodTrackingWindowStartMinutes,
            windowEndMinutes: foodTrackingWindowEndMinutes,
            lowRemainingLockEnabled: lowRemainingTrackingLockEnabled,
            lowRemainingLockStartMinutes: lowRemainingTrackingLockStartMinutes,
            lowRemainingCaloriesThreshold: lowRemainingTrackingCaloriesThreshold
        )
    }

    func isOutsideFoodTrackingWindow(at date: Date = Date()) -> Bool {
        foodTrackingWindowEnabled && !FoodTrackingPolicy.isWithinAllowedWindow(
            at: date,
            startMinutes: foodTrackingWindowStartMinutes,
            endMinutes: foodTrackingWindowEndMinutes
        )
    }

    func shouldHideNutrition(at date: Date = Date()) -> Bool {
        hideNutritionOutsideTrackingWindow && isOutsideFoodTrackingWindow(at: date)
    }

    func areTrackingWindowSettingsLocked(at date: Date = Date()) -> Bool {
        lockTrackingWindowSettingsOutsideHours && isOutsideFoodTrackingWindow(at: date)
    }

    func foodTrackingRestriction(
        at date: Date = Date(),
        remainingCalories: Double,
        isFasting: Bool = false
    ) -> FoodTrackingRestriction? {
        FoodTrackingPolicy.restriction(
            rules: foodTrackingRules,
            at: date,
            remainingCalories: remainingCalories,
            isFasting: isFasting
        )
    }

    func targetProteinGrams(availableCalories: Double) -> Double {
        if let targets = flexibleMacroTargets(availableCalories: availableCalories) { return targets.protein }
        return (availableCalories * (Double(proteinPercentage) / 100.0)) / 4.0
    }

    func targetFatGrams(availableCalories: Double) -> Double {
        if let targets = flexibleMacroTargets(availableCalories: availableCalories) { return targets.fat }
        return (availableCalories * (Double(fatPercentage) / 100.0)) / 9.0
    }

    private func flexibleMacroTargets(availableCalories: Double) -> MacroGramTargets? {
        guard advancedMacroGoalsEnabled, macroGoalPlan.mode == .flexible else { return nil }
        return macroGoalPlan.targets(calories: availableCalories)
    }

    func setAdvancedMacroGoalsEnabled(_ enabled: Bool) {
        advancedMacroGoalsEnabled = enabled
    }

    @discardableResult
    func updateMacroGoalPlan(_ plan: MacroGoalPlan) -> Bool {
        guard plan.mode == .percentages || plan.isValid else { return false }
        macroGoalPlan = plan
        return true
    }

    func updateMacros(carbs: Int, protein: Int, fat: Int) -> Bool {
        guard carbs + protein + fat == 100, carbs >= 0, protein >= 0, fat >= 0 else {
            return false
        }
        self.carbsPercentage = carbs
        self.proteinPercentage = protein
        self.fatPercentage = fat
        return true
    }

    @discardableResult
    func applyActivityLevel(_ level: NutritionActivityLevel) -> (calories: Double, saltGrams: Double) {
        let previousPAL = nutritionActivityLevel.pal
        let rawAdjusted = baseCalorieGoal * level.pal / previousPAL / 50
        let adjustedCalories = rawAdjusted.isFinite
            ? max(1_000, min(6_000, rawAdjusted.rounded() * 50))
            : baseCalorieGoal.sanitizedOrDefault(2400)
        nutritionActivityLevel = level
        baseCalorieGoal = adjustedCalories
        saltGoalGrams = level.saltGoalGrams
        return (adjustedCalories, level.saltGoalGrams)
    }

    @discardableResult
    func applyOnboarding(
        goal: OnboardingGoal,
        sex: OnboardingSex,
        ageYears: Int,
        heightCentimeters: Double,
        weightKilograms: Double,
        activityLevel: NutritionActivityLevel,
        foodUnit: FoodUnit,
        liquidUnit: FoodUnit,
        trainingWeightUnit: TrainingWeightUnit,
        distanceUnit: TrainingDistanceUnit
    ) -> OnboardingStartValues {
        let values = OnboardingCalculator.calculate(
            goal: goal,
            sex: sex,
            ageYears: ageYears,
            heightCentimeters: heightCentimeters,
            weightKilograms: weightKilograms,
            activityLevel: activityLevel
        )
        onboardingGoal = goal
        onboardingSex = sex
        profileAgeYears = ageYears
        profileHeightCentimeters = heightCentimeters
        profileWeightKilograms = weightKilograms
        nutritionActivityLevel = activityLevel
        defaultFoodUnit = foodUnit
        defaultLiquidUnit = liquidUnit
        self.trainingWeightUnit = trainingWeightUnit
        self.trainingDistanceUnit = distanceUnit
        calorieGoalMode = .fixed
        baseCalorieGoal = values.calories
        _ = updateMacros(carbs: values.carbsPercentage, protein: values.proteinPercentage, fat: values.fatPercentage)
        dailyWaterGoalMilliliters = values.waterMilliliters
        waterGlassSizeMilliliters = 250
        addedSugarGoalGrams = max(1, (values.calories * 0.05 / 4).rounded())
        fruitSugarGoalGrams = 50
        fiberGoalGrams = max(25, (values.calories / 1_000 * 14).rounded())
        saturatedFatGoalGrams = max(1, (values.calories * 0.10 / 9).rounded())
        saltGoalGrams = activityLevel.saltGoalGrams
        return values
    }

    func isNutritionMetricVisible(_ metric: NutritionMetric) -> Bool {
        visibleNutritionMetricIDs.contains(metric.rawValue)
    }

    func setNutritionMetric(_ metric: NutritionMetric, isVisible: Bool) {
        var updatedIDs = visibleNutritionMetricIDs
        if isVisible {
            updatedIDs.insert(metric.rawValue)
        } else {
            updatedIDs.remove(metric.rawValue)
        }
        visibleNutritionMetricIDs = updatedIDs
    }

    func isHomeAdditionalNutritionMetricVisible(_ metric: NutritionMetric) -> Bool {
        homeAdditionalNutritionMetricIDs.contains(metric.rawValue)
    }

    func setHomeAdditionalNutritionMetric(_ metric: NutritionMetric, isVisible: Bool) {
        guard NutritionMetric.homeAdditionalOptions.contains(metric) else { return }
        var updatedIDs = homeAdditionalNutritionMetricIDs
        if isVisible {
            updatedIDs.insert(metric.rawValue)
        } else {
            updatedIDs.remove(metric.rawValue)
        }
        homeAdditionalNutritionMetricIDs = updatedIDs
    }

    func setNutritionProfile(_ profile: NutritionProfile, isSelected: Bool) {
        selectedNutritionProfileIDs = isSelected ? [profile.rawValue] : [NutritionProfile.standard.rawValue]
        macroGoalPlan.mode = .percentages
        applyProfiles()
    }

    func isNutritionProfileSelected(_ profile: NutritionProfile) -> Bool { selectedNutritionProfileIDs.contains(profile.rawValue) }

    func isDashboardSectionVisible(_ section: DashboardSection) -> Bool {
        section != .training && visibleDashboardSectionIDs.contains(section.rawValue)
    }
    var dashboardSections: [DashboardSection] {
        dashboardSectionIDs.compactMap(DashboardSection.init(rawValue:)).filter {
            $0 != .training && visibleDashboardSectionIDs.contains($0.rawValue)
        }
    }
    func setDashboardSection(_ section: DashboardSection, isVisible: Bool) {
        guard section != .training else { return }
        if isVisible { visibleDashboardSectionIDs.insert(section.rawValue) }
        else if section != .meals { visibleDashboardSectionIDs.remove(section.rawValue) }
    }
    func moveDashboardSections(from source: IndexSet, to destination: Int) {
        var visible = dashboardSections.map(\.rawValue)
        visible.move(fromOffsets: source, toOffset: destination)
        let visibleSet = Set(visible)
        var iterator = visible.makeIterator()
        dashboardSectionIDs = dashboardSectionIDs.map { visibleSet.contains($0) ? (iterator.next() ?? $0) : $0 }
    }

    private func applyProfiles() {
        let selected = NutritionProfile.allCases.first { selectedNutritionProfileIDs.contains($0.rawValue) } ?? .standard
        let preferredAddedSugar = max(1, (baseCalorieGoal * 0.05 / 4).sanitizedOrDefault(1).rounded())
        let lowAddedSugar = max(1, (baseCalorieGoal * 0.03 / 4).sanitizedOrDefault(1).rounded())
        let saturatedFatLimit = max(1, (baseCalorieGoal * 0.10 / 9).sanitizedOrDefault(1).rounded())
        switch selected {
        case .standard:
            _ = updateMacros(carbs: 50, protein: 20, fat: 30)
            addedSugarGoalGrams = preferredAddedSugar; fruitSugarGoalGrams = 50; saltGoalGrams = 5; fiberGoalGrams = 30; saturatedFatGoalGrams = saturatedFatLimit
        case .sport:
            _ = updateMacros(carbs: 55, protein: 25, fat: 20)
            addedSugarGoalGrams = preferredAddedSugar; fruitSugarGoalGrams = 60; saltGoalGrams = 5; fiberGoalGrams = 30; saturatedFatGoalGrams = saturatedFatLimit
        case .lowSugar:
            _ = updateMacros(carbs: 45, protein: 25, fat: 30)
            addedSugarGoalGrams = lowAddedSugar; fruitSugarGoalGrams = 30; saltGoalGrams = 5; fiberGoalGrams = 30; saturatedFatGoalGrams = saturatedFatLimit
        case .highProtein:
            _ = updateMacros(carbs: 35, protein: 35, fat: 30)
            addedSugarGoalGrams = preferredAddedSugar; fruitSugarGoalGrams = 40; saltGoalGrams = 5; fiberGoalGrams = 30; saturatedFatGoalGrams = saturatedFatLimit
        case .lowCarb:
            _ = updateMacros(carbs: 25, protein: 30, fat: 45)
            addedSugarGoalGrams = preferredAddedSugar; fruitSugarGoalGrams = 35; saltGoalGrams = 5; fiberGoalGrams = 25; saturatedFatGoalGrams = saturatedFatLimit
        case .plantBased:
            _ = updateMacros(carbs: 55, protein: 20, fat: 25)
            addedSugarGoalGrams = preferredAddedSugar; fruitSugarGoalGrams = 60; saltGoalGrams = 5; fiberGoalGrams = 35; saturatedFatGoalGrams = saturatedFatLimit
        }
        saltGoalGrams = nutritionActivityLevel.saltGoalGrams
    }

    private func saveNutritionTargets() {
        UserDefaults.standard.set([
            "addedSugar": addedSugarGoalGrams.sanitizedNutritionValue(default: 30),
            "fruitSugar": fruitSugarGoalGrams.sanitizedNutritionValue(default: 50),
            "salt": saltGoalGrams.sanitizedNutritionValue(default: 5),
            "fiber": fiberGoalGrams.sanitizedNutritionValue(default: 30),
            "saturatedFat": saturatedFatGoalGrams.sanitizedNutritionValue(default: 27)
        ], forKey: "nutritionTargets_v1")
    }

    /// Publishes the allowance already resolved for today. `baseCalorieGoal`
    /// alone must never be used here because it is only the fallback in dynamic
    /// mode.
    func updateWidgetAvailableCalories(_ availableCalories: Double) {
        let appGroupID = HyseConfiguration.appGroup
        if let userDefaults = UserDefaults(suiteName: appGroupID) {
            let calories = max(availableCalories, 0).sanitizedOrDefault(0)
            userDefaults.set(Int(calories.rounded()), forKey: "todayGoalKcal")
            userDefaults.set(
                Calendar.current.startOfDay(for: Date()).timeIntervalSince1970,
                forKey: "todayGoalDate"
            )
            userDefaults.set(max(0, targetCarbsGrams(availableCalories: calories)).sanitizedOrDefault(0), forKey: "widgetCarbsGoalGrams")
            userDefaults.set(max(0, targetProteinGrams(availableCalories: calories)).sanitizedOrDefault(0), forKey: "widgetProteinGoalGrams")
            userDefaults.set(max(0, targetFatGrams(availableCalories: calories)).sanitizedOrDefault(0), forKey: "widgetFatGoalGrams")
            userDefaults.set(Date().timeIntervalSince1970, forKey: "widgetMacroGoalDate")
            userDefaults.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func publishWidgetFallbackGoal() {
        let appGroupID = HyseConfiguration.appGroup
        let userDefaults = UserDefaults(suiteName: appGroupID)
        let restDayAdjustment = dayTypeCalorieAdjustmentsEnabled ? restDayCalorieAdjustment : 0
        let fallback = max(0, baseCalorieGoal + restDayAdjustment)
        userDefaults?.set(Int(max(fallback, 1).sanitizedOrDefault(1).rounded()), forKey: "widgetFallbackGoalKcal")
        userDefaults?.synchronize()
    }

    private func publishWidgetWaterGoal() {
        let goal = dailyWaterGoalMilliliters.sanitizedNutritionValue(default: 2_000)
        let defaults = UserDefaults(suiteName: HyseConfiguration.appGroup)
        defaults?.set(goal, forKey: "widgetWaterGoalMilliliters")
        defaults?.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
