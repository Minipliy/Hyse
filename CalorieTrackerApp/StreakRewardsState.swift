import Foundation

nonisolated struct StreakRewardsState: Codable, Equatable, Sendable {
    static let nutritionReward = 10
    static let trainingReward = 20
    static let nutritionFreezeCost = 60
    static let trainingFreezeCost = 100
    static let maximumFreezeCount = 2

    var iceCrystals = 0
    var nutritionFreezeCount = 0
    var trainingFreezeCount = 0
    var rewardedNutritionDayKeys: Set<String> = []
    var rewardedTrainingDayKeys: Set<String> = []
    var nutritionFrozenDayKeys: Set<String> = []
    var trainingFrozenWeekKeys: Set<String> = []

    /// On a device with no account snapshot, actions can be recorded while the
    /// first cloud fetch is pending. Add only receipts absent from the cloud;
    /// the local balance also records any freezes bought in that interval.
    func mergingFirstLocalActions(into cloud: Self) -> Self {
        var merged = cloud
        let newNutritionDays = rewardedNutritionDayKeys.subtracting(cloud.rewardedNutritionDayKeys)
        let newTrainingDays = rewardedTrainingDayKeys.subtracting(cloud.rewardedTrainingDayKeys)
        let localCredits = rewardedNutritionDayKeys.count * Self.nutritionReward
            + rewardedTrainingDayKeys.count * Self.trainingReward
        let localSpending = max(0, localCredits - iceCrystals)
        let newCredits = newNutritionDays.count * Self.nutritionReward
            + newTrainingDays.count * Self.trainingReward
        let extraNutritionFreezes = max(0, cloud.nutritionFreezeCount + nutritionFreezeCount - Self.maximumFreezeCount)
        let extraTrainingFreezes = max(0, cloud.trainingFreezeCount + trainingFreezeCount - Self.maximumFreezeCount)
        let refund = extraNutritionFreezes * Self.nutritionFreezeCost
            + extraTrainingFreezes * Self.trainingFreezeCost

        merged.iceCrystals = max(0, cloud.iceCrystals + newCredits - localSpending + refund)
        merged.rewardedNutritionDayKeys.formUnion(rewardedNutritionDayKeys)
        merged.rewardedTrainingDayKeys.formUnion(rewardedTrainingDayKeys)
        merged.nutritionFrozenDayKeys.formUnion(nutritionFrozenDayKeys)
        merged.trainingFrozenWeekKeys.formUnion(trainingFrozenWeekKeys)
        merged.nutritionFreezeCount = min(Self.maximumFreezeCount, cloud.nutritionFreezeCount + nutritionFreezeCount)
        merged.trainingFreezeCount = min(Self.maximumFreezeCount, cloud.trainingFreezeCount + trainingFreezeCount)
        return merged
    }
}
