import Foundation

// Minimal app-domain fixtures let this test compile the production calculator
// directly without duplicating its implementation.
enum CalorieGoalMode: String, Codable { case fixed, dynamic }

struct DailyEnergy: Equatable {
    var date: Date
    var resting: Double
    var active: Double
    var updatedAt: Date? = nil
    var sourceName: String? = nil
    var sourceCount: Int? = nil
    var sourceSelectionStrategy: String? = nil
}

@main
struct CalorieTargetCalculatorTests {
    static func main() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = berlin.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12))!
        let phase = DynamicDeficitPhase(startedAt: start, initialBodyFatFraction: 0.20, initialWeightKilograms: 100)

        expect(CalorieTargetCalculator.completedCalendarDays(from: start, through: start, calendar: berlin) == 0, "start day must be n=0")
        let afterDST = berlin.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12))!
        expect(CalorieTargetCalculator.completedCalendarDays(from: start, through: afterDST, calendar: berlin) == 2, "DST must still count local calendar days")

        let dayZero = CalorieTargetCalculator.dynamicDeficit(phase: phase, targetDate: start, calendar: berlin)!
        expectClose(dayZero.kilocalories, 0.20 * 100 * 69.13, "day-zero formula")
        let dayOne = berlin.date(byAdding: .day, value: 1, to: start)!
        let decayed = CalorieTargetCalculator.dynamicDeficit(phase: phase, targetDate: dayOne, calendar: berlin)!
        expectClose(decayed.kilocalories, dayZero.kilocalories * 0.9902, "daily decay")

        let energy = DailyEnergy(date: start, resting: 2_000, active: 400, updatedAt: start, sourceName: "Apple Health", sourceCount: 1, sourceSelectionStrategy: "singleSource")
        expectClose(
            CalorieTargetCalculator.availableCalories(mode: .fixed, targetKilocalories: 2_400, activeEnergy: 400),
            2_400,
            "fixed goal must ignore active energy"
        )
        expectClose(
            CalorieTargetCalculator.availableCalories(mode: .dynamic, targetKilocalories: 2_400, activeEnergy: 400),
            2_800,
            "dynamic goal must include active energy"
        )
        expectClose(
            CalorieTargetCalculator.availableCalories(mode: .fixed, targetKilocalories: 2_400, activeEnergy: 400, dayAdjustment: 300),
            2_700,
            "training-day adjustment must be added to a fixed goal"
        )
        expectClose(
            CalorieTargetCalculator.availableCalories(mode: .dynamic, targetKilocalories: 2_400, activeEnergy: 400, dayAdjustment: -150),
            2_650,
            "rest-day adjustment must be added after active energy"
        )
        let target = CalorieTargetCalculator.target(mode: .dynamic, fixedGoal: 2_400, phase: phase, targetDate: start, previousDayEnergy: energy, calendar: berlin, referenceDate: start)
        expectClose(target.targetKilocalories, 2_000 - dayZero.kilocalories, "resting energy minus deficit")
        expect(target.completedCalendarDays == 0, "breakdown must expose n")

        let surplusTarget = CalorieTargetCalculator.target(
            mode: .dynamic,
            fixedGoal: 2_400,
            dynamicMode: .surplus,
            fixedSurplus: 350,
            phase: nil,
            targetDate: start,
            previousDayEnergy: energy,
            calendar: berlin,
            referenceDate: start
        )
        expectClose(surplusTarget.targetKilocalories, 2_350, "resting energy plus fixed surplus")
        expect(surplusTarget.fixedSurplus == 350, "breakdown must expose fixed surplus")
        expect(surplusTarget.dynamicDeficit == nil && surplusTarget.phase == nil, "surplus must not require a deficit phase")

        let fixedDeficitTarget = CalorieTargetCalculator.target(
            mode: .dynamic, fixedGoal: 2_400, dynamicMode: .fixedDeficit,
            fixedDeficit: 300, phase: nil, targetDate: start,
            previousDayEnergy: energy, calendar: berlin, referenceDate: start
        )
        expectClose(fixedDeficitTarget.targetKilocalories, 1_700, "fixed deficit must subtract from resting energy")
        expect(fixedDeficitTarget.dynamicDeficit == 300 && fixedDeficitTarget.phase == nil,
               "fixed deficit must be independent of a body-fat phase")
        let fixedDeficitFallback = CalorieTargetCalculator.target(
            mode: .dynamic, fixedGoal: 2_400, dynamicMode: .fixedDeficit,
            fixedDeficit: 300, phase: nil, targetDate: start,
            previousDayEnergy: nil, calendar: berlin, referenceDate: start
        )
        expect(fixedDeficitFallback.source == .fixedFallback(.restingEnergyMissing),
               "fixed deficit without Health energy must use the fallback goal")

        let tomorrowTarget = CalorieTargetCalculator.target(mode: .dynamic, fixedGoal: 2_400, phase: phase, targetDate: dayOne, previousDayEnergy: energy, calendar: berlin, referenceDate: start)
        expect(tomorrowTarget.source == .fixedFallback(.futureDate), "tomorrow must use the fallback instead of today's incomplete resting energy")
        expectClose(tomorrowTarget.targetKilocalories, 2_400, "tomorrow fallback value")

        let missingHealth = CalorieTargetCalculator.target(mode: .dynamic, fixedGoal: 2_400, phase: phase, targetDate: start, previousDayEnergy: nil, calendar: berlin)
        expect(missingHealth.source == .fixedFallback(.restingEnergyMissing), "missing Health data must use explicit existing fallback")
        expectClose(missingHealth.targetKilocalories, 2_400, "fixed fallback value")

        let missingPhase = CalorieTargetCalculator.target(mode: .dynamic, fixedGoal: 2_400, phase: nil, targetDate: start, previousDayEnergy: energy, calendar: berlin)
        expect(missingPhase.source == .fixedFallback(.phaseMissing), "missing baseline must never be invented")

        let beforeStart = berlin.date(byAdding: .day, value: -1, to: start)!
        let historical = CalorieTargetCalculator.target(mode: .dynamic, fixedGoal: 2_400, phase: phase, targetDate: beforeStart, previousDayEnergy: energy, calendar: berlin)
        expect(historical.source == .fixedFallback(.phaseNotStarted), "dates before the phase need an explicit fallback")

        let secondStart = berlin.date(byAdding: .day, value: 30, to: start)!
        let secondPhase = DynamicDeficitPhase(startedAt: secondStart, initialBodyFatFraction: 0.16, initialWeightKilograms: 92)
        let oldPhaseDay = berlin.date(byAdding: .day, value: 20, to: start)!
        expect(
            CalorieTargetCalculator.activePhase(in: [phase, secondPhase], for: oldPhaseDay, calendar: berlin) == phase,
            "a historical day must keep using the old phase after a new phase starts"
        )
        expect(
            CalorieTargetCalculator.activePhase(in: [phase, secondPhase], for: secondStart, calendar: berlin) == secondPhase,
            "the new phase must take over on its start day"
        )

        let originalGoal = CalorieGoalConfiguration(
            startedAt: .distantPast, fixedGoal: 2_800, mode: .fixed, dynamicMode: .deficit,
            fixedSurplus: 300, trainingDayAdjustment: 400, restDayAdjustment: -100,
            dayTypeAdjustmentsEnabled: true
        )
        let changedGoal = CalorieGoalConfiguration(
            startedAt: secondStart, fixedGoal: 2_200, mode: .fixed, dynamicMode: .deficit,
            fixedSurplus: 300, trainingDayAdjustment: 200, restDayAdjustment: 0,
            dayTypeAdjustmentsEnabled: true
        )
        let history = CalorieGoalHistory.recording(changedGoal, in: [originalGoal], on: secondStart, calendar: berlin)
        let oldConfiguration = CalorieGoalHistory.active(in: history, for: oldPhaseDay, calendar: berlin)!
        let newConfiguration = CalorieGoalHistory.active(in: history, for: secondStart, calendar: berlin)!
        expectClose(oldConfiguration.fixedGoal, 2_800, "older fixed goal must remain unchanged")
        expectClose(oldConfiguration.trainingDayAdjustment, 400, "older training-day adjustment must remain unchanged")
        expectClose(oldConfiguration.restDayAdjustment, -100, "older rest-day adjustment must remain unchanged")
        expectClose(newConfiguration.fixedGoal, 2_200, "new fixed goal starts on the change day")
        expectClose(
            CalorieTargetCalculator.availableCalories(mode: oldConfiguration.mode, targetKilocalories: oldConfiguration.fixedGoal, activeEnergy: 0, dayAdjustment: oldConfiguration.trainingDayAdjustment),
            3_200, "historical training-day allowance"
        )
        let sameDayEdit = CalorieGoalHistory.recording(
            CalorieGoalConfiguration(startedAt: secondStart, fixedGoal: 2_300, mode: .fixed, dynamicMode: .deficit, fixedSurplus: 300, trainingDayAdjustment: 200, restDayAdjustment: 0, dayTypeAdjustmentsEnabled: true),
            in: history, on: secondStart.addingTimeInterval(3_600), calendar: berlin
        )
        expect(sameDayEdit.count == 2 && sameDayEdit.last?.fixedGoal == 2_300, "edits on one day replace its configuration")
        let dynamicBeforeSwitch = CalorieGoalConfiguration(
            startedAt: .distantPast, fixedGoal: 2_400, mode: .dynamic, dynamicMode: .deficit,
            fixedSurplus: 300, trainingDayAdjustment: 100, restDayAdjustment: -50,
            dayTypeAdjustmentsEnabled: true
        )
        let switched = CalorieGoalHistory.recording(changedGoal, in: [dynamicBeforeSwitch], on: secondStart, calendar: berlin)
        expect(CalorieGoalHistory.active(in: switched, for: oldPhaseDay, calendar: berlin)?.mode == .dynamic, "switching to fixed must preserve older dynamic days")
        expect(CalorieGoalHistory.active(in: switched, for: secondStart, calendar: berlin)?.mode == .fixed, "the new mode starts on the change day")
        let decodedHistory = try! JSONDecoder().decode([CalorieGoalConfiguration].self, from: JSONEncoder().encode(history))
        expect(decodedHistory == history, "calorie goal history must survive storage and sync encoding")

        let zeroFloor = CalorieTargetCalculator.target(mode: .dynamic, fixedGoal: 2_400, phase: phase, targetDate: start, previousDayEnergy: DailyEnergy(date: start, resting: 500, active: 0), calendar: berlin)
        expect(zeroFloor.rawTargetKilocalories < 0 && zeroFloor.targetKilocalories == 0, "existing zero floor must remain")

        let plannedDate = start.addingTimeInterval(3_600)
        let scheduled = ScheduledCaloriePhase(
            createdAt: start, kind: .cut, trigger: .date, startDate: plannedDate,
            triggerWeightKilograms: nil, goalMode: .dynamic, fixedGoal: 2_100,
            dynamicMode: .deficit, fixedDeficit: 300, fixedSurplus: 250,
            weightSource: .latestMeasurement, manualStartWeightKilograms: nil,
            bodyFatPercentage: 20
        )
        expect(scheduled.isValid, "scheduled dynamic cut must have valid inputs")
        expect(!scheduled.isDue(now: start, latestWeightKilograms: 90), "date plan must wait until its time")
        expect(scheduled.isDue(now: plannedDate, latestWeightKilograms: 90), "date plan must start at its time")
        var weightPlan = scheduled
        weightPlan.trigger = .weight
        weightPlan.startDate = nil
        weightPlan.triggerWeightKilograms = 100
        expect(!weightPlan.isDue(now: plannedDate, latestWeightKilograms: 99), "cut weight plan must wait below its threshold")
        expect(weightPlan.isDue(now: plannedDate, latestWeightKilograms: 100), "cut weight plan must start at its threshold")
        weightPlan.kind = .bulk
        weightPlan.dynamicMode = .surplus
        expect(!weightPlan.isDue(now: plannedDate, latestWeightKilograms: 101), "bulk weight plan must wait above its threshold")
        expect(weightPlan.isDue(now: plannedDate, latestWeightKilograms: 100), "bulk weight plan must start at its threshold")
        weightPlan.triggerWeightKilograms = nil
        expect(!weightPlan.isValid, "weight plan needs a threshold")
        var firstReached = scheduled
        firstReached.trigger = .whicheverFirst
        firstReached.triggerWeightKilograms = 100
        firstReached.bodyFatPercentage = nil
        expect(firstReached.isValid, "a combined plan may collect body fat when it starts")
        expect(!firstReached.isDue(now: start, latestWeightKilograms: 99), "combined plan waits while neither condition is met")
        expect(firstReached.isDue(now: start, latestWeightKilograms: 100), "combined cut starts when weight is reached first")
        expect(firstReached.isDue(now: plannedDate, latestWeightKilograms: 99), "combined cut starts when date is reached first")
        expect(firstReached.isDue(now: plannedDate, latestWeightKilograms: nil), "the date does not require a weight measurement")
        firstReached.startDate = nil
        expect(!firstReached.isValid, "combined plan needs its date")
        firstReached.startDate = plannedDate
        firstReached.triggerWeightKilograms = nil
        expect(!firstReached.isValid, "combined plan needs its weight threshold")
        firstReached.triggerWeightKilograms = 100
        firstReached.kind = .bulk
        firstReached.dynamicMode = .surplus
        expect(firstReached.isDue(now: start, latestWeightKilograms: 100), "combined bulk starts at or below its threshold")
        expect(!firstReached.isDue(now: start, latestWeightKilograms: 101), "combined bulk waits above its threshold")
        expect(try! JSONDecoder().decode(ScheduledCaloriePhase.self, from: JSONEncoder().encode(firstReached)) == firstReached,
               "combined plan survives storage and account encoding")
        expect(try! JSONDecoder().decode(ScheduledCaloriePhase.self, from: JSONEncoder().encode(scheduled)) == scheduled,
               "scheduled plan must survive local and account encoding")

        var macroPlan = scheduled
        var flexible = MacroGoalPlan()
        flexible.mode = .flexible
        flexible.proteinFixedGrams = 180
        flexible.fatFixedGrams = 30
        macroPlan.macroGoals = ScheduledMacroGoals(carbsPercentage: 50, proteinPercentage: 20, fatPercentage: 30, plan: flexible)
        expect(macroPlan.isValid, "scheduled cut accepts fixed protein and fat with remaining carbohydrates")
        expect(macroPlan.macroGoals?.plan.targets(calories: 2_100) == MacroGramTargets(carbs: 277.5, protein: 180, fat: 30),
               "remaining carbohydrates use the phase calorie goal")
        expect(try! JSONDecoder().decode(ScheduledCaloriePhase.self, from: JSONEncoder().encode(macroPlan)) == macroPlan,
               "scheduled macros survive local and account encoding")
        macroPlan.macroGoals?.plan.fatFixedGrams = 200
        macroPlan.goalMode = .fixed
        expect(!macroPlan.isValid, "fixed macro calories must not exceed a fixed calorie goal")
        var legacyObject = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(scheduled)) as! [String: Any]
        legacyObject.removeValue(forKey: "macroGoals")
        let legacyData = try! JSONSerialization.data(withJSONObject: legacyObject)
        expect(try! JSONDecoder().decode(ScheduledCaloriePhase.self, from: legacyData).macroGoals == nil,
               "older plans without macro settings remain readable")

        print("CalorieTargetCalculatorTests: all checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAILED: \(message)") }
    }

    private static func expectClose(_ actual: Double, _ expected: Double, _ message: String) {
        expect(abs(actual - expected) < 0.000_001, "\(message): expected \(expected), got \(actual)")
    }
}
