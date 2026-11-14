import Foundation

@main
struct MacroGoalPlanTests {
    static func main() throws {
        var twoFixed = MacroGoalPlan()
        twoFixed.mode = .flexible
        twoFixed.fatFixedGrams = 20
        twoFixed.proteinFixedGrams = 200
        assert(twoFixed.isValid)
        let remainder = twoFixed.targets(calories: 2_000)!
        assert(remainder.fat == 20 && remainder.protein == 200 && remainder.carbs == 255)

        var split = MacroGoalPlan()
        split.mode = .flexible
        split.fatFixedGrams = 20
        split.carbsRemainingPercent = 40
        split.proteinRemainingPercent = 60
        assert(split.isValid)
        let targets = split.targets(calories: 2_000)!
        assert(targets.fat == 20 && targets.carbs == 182 && targets.protein == 273)

        split.proteinRemainingPercent = 50
        assert(!split.isValid && split.targets(calories: 2_000) == nil)

        let reduced = twoFixed.targets(calories: 500)!
        assert(reduced.fat == 20 && reduced.protein == 200 && reduced.carbs == 0)
        var allFixed = twoFixed
        allFixed.carbsFixedGrams = 160
        assert(allFixed.isValid && allFixed.targets(calories: 2_000) == MacroGramTargets(carbs: 160, protein: 200, fat: 20))
        let scheduledPercentages = ScheduledMacroGoals(carbsPercentage: 45, proteinPercentage: 35, fatPercentage: 20, plan: MacroGoalPlan())
        assert(scheduledPercentages.isValid)
        let scheduledFlexible = ScheduledMacroGoals(carbsPercentage: 0, proteinPercentage: 0, fatPercentage: 0, plan: twoFixed)
        assert(scheduledFlexible.isValid)
        let decoded = try JSONDecoder().decode(MacroGoalPlan.self, from: JSONEncoder().encode(twoFixed))
        assert(decoded == twoFixed)
        print("MacroGoalPlanTests: all checks passed")
    }
}
