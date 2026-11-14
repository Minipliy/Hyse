import Foundation

@main
enum StreakRewardsStateTests {
    static func main() {
        let today = "2026-10-01"
        let yesterday = "2026-09-30"

        var cloud = StreakRewardsState()
        cloud.iceCrystals = 40
        cloud.rewardedNutritionDayKeys = [yesterday]
        cloud.rewardedTrainingDayKeys = [yesterday]

        var local = StreakRewardsState()
        local.iceCrystals = 30
        local.rewardedNutritionDayKeys = [today]
        local.rewardedTrainingDayKeys = [today]
        let merged = local.mergingFirstLocalActions(into: cloud)
        expect(merged.iceCrystals == 70, "both first actions add 30 crystals to the cloud balance")
        expect(merged.rewardedNutritionDayKeys == [today, yesterday], "nutrition receipts survive")
        expect(merged.rewardedTrainingDayKeys == [today, yesterday], "training receipts survive")

        cloud.rewardedNutritionDayKeys.insert(today)
        cloud.iceCrystals = 50
        expect(local.mergingFirstLocalActions(into: cloud).iceCrystals == 70, "an already rewarded food day is not paid twice")

        var spent = StreakRewardsState()
        spent.rewardedNutritionDayKeys = ["2026-09-26", "2026-09-27", "2026-09-28", "2026-09-29", yesterday, today]
        spent.iceCrystals = 0
        spent.nutritionFreezeCount = 1
        let afterPurchase = spent.mergingFirstLocalActions(into: StreakRewardsState())
        expect(afterPurchase.iceCrystals == 0, "local spending is retained")
        expect(afterPurchase.nutritionFreezeCount == 1, "local freeze inventory is retained")

        var fullCloud = StreakRewardsState()
        fullCloud.iceCrystals = 80
        fullCloud.nutritionFreezeCount = 2
        let capped = spent.mergingFirstLocalActions(into: fullCloud)
        expect(capped.nutritionFreezeCount == 2, "freeze inventory stays capped")
        expect(capped.iceCrystals == 140, "an excess local freeze purchase is refunded")

        expect(StreakRewardsState().mergingFirstLocalActions(into: cloud) == cloud, "no local actions keep the cloud snapshot")
        print("Streak reward state tests passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
