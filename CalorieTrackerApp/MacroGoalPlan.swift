import Foundation

nonisolated enum MacroGoalMode: String, Codable {
    case percentages
    case flexible
}

nonisolated struct MacroGramTargets: Equatable, Sendable {
    let carbs: Double
    let protein: Double
    let fat: Double
}

/// Fixed grams are reserved first. Every variable macro receives a share of
/// the calories left after the fixed targets have been subtracted. All three
/// macros may also be fixed; any remaining calories then stay unallocated.
nonisolated struct MacroGoalPlan: Codable, Equatable, Sendable {
    var mode: MacroGoalMode = .percentages
    var carbsFixedGrams: Double? = nil
    var proteinFixedGrams: Double? = nil
    var fatFixedGrams: Double? = nil
    var carbsRemainingPercent = 50
    var proteinRemainingPercent = 20
    var fatRemainingPercent = 30

    var variableCount: Int { [carbsFixedGrams, proteinFixedGrams, fatFixedGrams].filter { $0 == nil }.count }
    var isValid: Bool {
        let fixed = [carbsFixedGrams, proteinFixedGrams, fatFixedGrams].compactMap { $0 }
        guard fixed.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        if variableCount == 0 { return true }
        let shares = [
            carbsFixedGrams == nil ? carbsRemainingPercent : 0,
            proteinFixedGrams == nil ? proteinRemainingPercent : 0,
            fatFixedGrams == nil ? fatRemainingPercent : 0
        ]
        return shares.allSatisfy { $0 >= 0 && $0 <= 100 }
            && (variableCount == 1 || shares.reduce(0, +) == 100)
    }

    func targets(calories: Double) -> MacroGramTargets? {
        guard isValid, calories.isFinite else { return nil }
        let fixedCalories = (carbsFixedGrams ?? 0) * 4 + (proteinFixedGrams ?? 0) * 4 + (fatFixedGrams ?? 0) * 9
        let remaining = max(0, calories - fixedCalories)
        func amount(_ fixed: Double?, _ percent: Int, factor: Double) -> Double {
            if let fixed { return fixed }
            return remaining * Double(variableCount == 1 ? 100 : percent) / 100 / factor
        }
        return MacroGramTargets(
            carbs: amount(carbsFixedGrams, carbsRemainingPercent, factor: 4),
            protein: amount(proteinFixedGrams, proteinRemainingPercent, factor: 4),
            fat: amount(fatFixedGrams, fatRemainingPercent, factor: 9)
        )
    }

    var fixedCalories: Double {
        (carbsFixedGrams ?? 0) * 4 + (proteinFixedGrams ?? 0) * 4 + (fatFixedGrams ?? 0) * 9
    }
}

/// Optional macro settings applied together with a scheduled calorie phase.
/// Percentage targets live outside MacroGoalPlan in the current settings as
/// well, so the three values are captured here when a phase is prepared.
nonisolated struct ScheduledMacroGoals: Codable, Equatable, Sendable {
    var carbsPercentage: Int
    var proteinPercentage: Int
    var fatPercentage: Int
    var plan: MacroGoalPlan

    var isValid: Bool {
        switch plan.mode {
        case .percentages:
            return [carbsPercentage, proteinPercentage, fatPercentage].allSatisfy { (0...100).contains($0) }
                && carbsPercentage + proteinPercentage + fatPercentage == 100
        case .flexible:
            return plan.isValid
        }
    }
}
