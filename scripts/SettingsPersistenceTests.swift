import Foundation

@main
struct SettingsPersistenceTests {
    static func main() {
        let defaults = UserDefaults.standard
        let keys = [
            "baseCalorieGoal",
            "trainingDayCalorieAdjustment_v1",
            "restDayCalorieAdjustment_v1",
            "calorieLimitBufferKilocalories_v1",
            "dynamicDeficitPhaseStartDate_v1",
            "dynamicDeficitInitialBodyFatFraction_v1",
            "dynamicDeficitInitialWeightKilograms_v1",
            "dynamicCalorieTargetMode_v1",
            "fixedCalorieSurplus_v1",
            "blockFoodTrackingWhileFastingEnabled_v1",
            "foodTrackingWindowEnabled_v1",
            "foodTrackingWindowStartMinutes_v1",
            "foodTrackingWindowEndMinutes_v1",
            "lowRemainingTrackingLockEnabled_v1",
            "lowRemainingTrackingLockStartMinutes_v1",
            "lowRemainingTrackingCaloriesThreshold_v1",
            "lowCalorieEntryWarningEnabled_v1",
            "lowCalorieEntryWarningThreshold_v1",
            "carbsPercentage",
            "proteinPercentage",
            "fatPercentage",
            "dailyWaterGoalMilliliters",
            "waterGlassSizeMilliliters",
            "nutritionTargets_v1",
            "restSoundEnabled_v1",
            "restHapticsEnabled_v1",
            "restSoundVariant_v1",
            "restSoundVolume_v1",
            "liveActivityEnabled_v1",
            "automaticallyStartAppleWatchWorkout_v1",
            "motivationNotificationsEnabled_v1",
            "dashboardSectionOrder_v1",
            "dashboardSectionIDs_v1"
        ]
        keys.forEach(defaults.removeObject(forKey:))

        let settings = UserSettingsStore()
        settings.baseCalorieGoal = 2_175
        settings.trainingDayCalorieAdjustment = 300
        settings.restDayCalorieAdjustment = -150
        settings.calorieLimitBufferKilocalories = 150
        precondition(settings.startDynamicDeficitPhase(bodyFatPercentage: 20, weightKilograms: 80))
        precondition(settings.setFixedCalorieSurplus(350))
        settings.blockFoodTrackingWhileFastingEnabled = true
        settings.foodTrackingWindowEnabled = true
        settings.foodTrackingWindowStartMinutes = 6 * 60
        settings.foodTrackingWindowEndMinutes = 18 * 60
        settings.lowRemainingTrackingLockEnabled = true
        settings.lowRemainingTrackingLockStartMinutes = 18 * 60
        settings.lowRemainingTrackingCaloriesThreshold = 200
        settings.lowCalorieEntryWarningEnabled = false
        settings.lowCalorieEntryWarningThreshold = 575
        precondition(settings.updateMacros(carbs: 45, protein: 30, fat: 25))
        settings.dailyWaterGoalMilliliters = 2_400
        settings.waterGlassSizeMilliliters = 300
        settings.addedSugarGoalGrams = 42
        settings.fruitSugarGoalGrams = 24
        settings.saltGoalGrams = 7.5
        settings.fiberGoalGrams = 31
        settings.saturatedFatGoalGrams = 19
        settings.restSoundEnabled = false
        settings.restHapticsEnabled = false
        settings.restSoundVariant = .soft
        settings.restSoundVolume = 0.45
        settings.liveActivityEnabled = false
        settings.automaticallyStartAppleWatchWorkout = false
        settings.motivationNotificationsEnabled = true
        settings.setDashboardSection(.training, isVisible: false)
        _ = defaults.synchronize()

        let reloaded = UserSettingsStore()
        precondition(reloaded.baseCalorieGoal == 2_175)
        precondition(reloaded.trainingDayCalorieAdjustment == 300)
        precondition(reloaded.restDayCalorieAdjustment == -150)
        precondition(reloaded.calorieLimitBufferKilocalories == 150)
        precondition(reloaded.maximumAllowedCalories(2_175) == 2_325)
        precondition(reloaded.dynamicDeficitPhase?.initialBodyFatFraction == 0.2)
        precondition(reloaded.dynamicDeficitPhase?.initialWeightKilograms == 80)
        precondition(reloaded.dynamicCalorieTargetMode == .surplus)
        precondition(reloaded.fixedCalorieSurplus == 350)
        precondition(reloaded.blockFoodTrackingWhileFastingEnabled)
        precondition(reloaded.foodTrackingWindowEnabled)
        precondition(reloaded.foodTrackingWindowStartMinutes == 6 * 60)
        precondition(reloaded.foodTrackingWindowEndMinutes == 18 * 60)
        precondition(reloaded.lowRemainingTrackingLockEnabled)
        precondition(reloaded.lowRemainingTrackingLockStartMinutes == 18 * 60)
        precondition(reloaded.lowRemainingTrackingCaloriesThreshold == 200)
        precondition(!reloaded.lowCalorieEntryWarningEnabled)
        precondition(reloaded.lowCalorieEntryWarningThreshold == 575)
        precondition(reloaded.carbsPercentage == 45)
        precondition(reloaded.proteinPercentage == 30)
        precondition(reloaded.fatPercentage == 25)
        precondition(reloaded.dailyWaterGoalMilliliters == 2_400)
        precondition(reloaded.waterGlassSizeMilliliters == 300)
        precondition(reloaded.addedSugarGoalGrams == 42)
        precondition(reloaded.fruitSugarGoalGrams == 24)
        precondition(reloaded.saltGoalGrams == 7.5)
        precondition(reloaded.fiberGoalGrams == 31)
        precondition(reloaded.saturatedFatGoalGrams == 19)
        precondition(!reloaded.restSoundEnabled)
        precondition(!reloaded.restHapticsEnabled)
        precondition(reloaded.restSoundVariant == .soft)
        precondition(reloaded.restSoundVolume == 0.45)
        precondition(!reloaded.liveActivityEnabled)
        precondition(!reloaded.automaticallyStartAppleWatchWorkout)
        precondition(reloaded.motivationNotificationsEnabled)
        precondition(!reloaded.isDashboardSectionVisible(.training))

        print("Settings persistence tests passed.")
    }
}
