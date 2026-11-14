import Foundation

/// Immutable inputs for one dynamic-deficit phase. A new phase must be
/// created explicitly instead of silently changing the baseline mid-phase.
struct DynamicDeficitPhase: Codable, Equatable {
    let startedAt: Date
    let initialBodyFatFraction: Double
    let initialWeightKilograms: Double
}

nonisolated enum PlannedCaloriePhaseKind: String, Codable, CaseIterable, Identifiable {
    case cut, bulk
    var id: String { rawValue }
}

nonisolated enum PlannedCaloriePhaseTrigger: String, Codable, CaseIterable, Identifiable {
    case date, weight, whicheverFirst
    var id: String { rawValue }
}

nonisolated enum PlannedCalorieWeightSource: String, Codable, CaseIterable, Identifiable {
    case latestMeasurement, manual
    var id: String { rawValue }
}

/// One pending change of calorie goal. Values are stored in kilograms so
/// switching the display unit cannot silently change a weight threshold.
nonisolated struct ScheduledCaloriePhase: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var kind: PlannedCaloriePhaseKind
    var trigger: PlannedCaloriePhaseTrigger
    var startDate: Date?
    var triggerWeightKilograms: Double?
    var goalMode: CalorieGoalMode
    var fixedGoal: Double
    var dynamicMode: DynamicCalorieTargetMode
    var fixedDeficit: Double
    var fixedSurplus: Double
    var weightSource: PlannedCalorieWeightSource
    var manualStartWeightKilograms: Double?
    var bodyFatPercentage: Double?
    var macroGoals: ScheduledMacroGoals? = nil

    var isValid: Bool {
        guard fixedGoal.isFinite, fixedGoal > 0,
              fixedDeficit.isFinite, fixedDeficit >= 0,
              fixedSurplus.isFinite, fixedSurplus >= 0 else { return false }
        if goalMode == .dynamic {
            guard (kind == .bulk && dynamicMode == .surplus) ||
                  (kind == .cut && dynamicMode != .surplus) else { return false }
            if dynamicMode == .fixedDeficit && fixedDeficit <= 0 { return false }
            if dynamicMode == .surplus && fixedSurplus <= 0 { return false }
        }
        switch trigger {
        case .date: guard startDate != nil else { return false }
        case .weight:
            guard let threshold = triggerWeightKilograms, threshold.isFinite, threshold > 0 else { return false }
        case .whicheverFirst:
            guard startDate != nil,
                  let threshold = triggerWeightKilograms, threshold.isFinite, threshold > 0 else { return false }
        }
        if goalMode == .dynamic && dynamicMode == .deficit {
            // A missing value is collected when the start condition is met.
            if let bodyFatPercentage,
               (!bodyFatPercentage.isFinite || bodyFatPercentage <= 0 || bodyFatPercentage >= 100) { return false }
            if weightSource == .manual {
                guard let weight = manualStartWeightKilograms, weight.isFinite, weight > 0 else { return false }
            }
        }
        if let macroGoals {
            guard macroGoals.isValid else { return false }
            if goalMode == .fixed && macroGoals.plan.mode == .flexible && macroGoals.plan.fixedCalories > fixedGoal {
                return false
            }
        }
        return true
    }

    func isDue(now: Date, latestWeightKilograms: Double?) -> Bool {
        guard isValid else { return false }
        let dateReached = startDate.map { now >= $0 } ?? false
        let weightReached: Bool
        if let threshold = triggerWeightKilograms,
           let weight = latestWeightKilograms, weight.isFinite, weight > 0 {
            weightReached = kind == .cut ? weight >= threshold : weight <= threshold
        } else {
            weightReached = false
        }
        switch trigger {
        case .date: return dateReached
        case .weight: return weightReached
        case .whicheverFirst: return dateReached || weightReached
        }
    }
}

/// The settings that were in effect from one calendar day onward.
struct CalorieGoalConfiguration: Codable, Equatable {
    var startedAt: Date
    var fixedGoal: Double
    var mode: CalorieGoalMode
    var dynamicMode: DynamicCalorieTargetMode
    var fixedSurplus: Double
    var fixedDeficit: Double? = nil
    var trainingDayAdjustment: Double
    var restDayAdjustment: Double
    var dayTypeAdjustmentsEnabled: Bool

    func hasSameValues(as other: Self) -> Bool {
        fixedGoal == other.fixedGoal && mode == other.mode && dynamicMode == other.dynamicMode &&
        fixedSurplus == other.fixedSurplus && fixedDeficit == other.fixedDeficit && trainingDayAdjustment == other.trainingDayAdjustment &&
        restDayAdjustment == other.restDayAdjustment && dayTypeAdjustmentsEnabled == other.dayTypeAdjustmentsEnabled
    }
}

struct CalorieDayTypeRecord: Codable, Equatable {
    let day: Date
    let isTrainingDay: Bool
}

enum CalorieGoalHistory {
    static func active(in history: [CalorieGoalConfiguration], for date: Date, calendar: Calendar = .current) -> CalorieGoalConfiguration? {
        let day = calendar.startOfDay(for: date)
        return history.last { $0.startedAt <= day } ?? history.first
    }

    static func recording(
        _ configuration: CalorieGoalConfiguration,
        in history: [CalorieGoalConfiguration],
        on date: Date,
        calendar: Calendar = .current
    ) -> [CalorieGoalConfiguration] {
        let day = calendar.startOfDay(for: date)
        guard let last = history.last else {
            var baseline = configuration
            baseline.startedAt = .distantPast
            return [baseline]
        }
        guard !last.hasSameValues(as: configuration) else { return history }
        var result = history
        var updated = configuration
        updated.startedAt = day
        if calendar.isDate(last.startedAt, inSameDayAs: day) {
            result[result.count - 1] = updated
        } else {
            result.append(updated)
        }
        return result
    }
}

nonisolated enum DynamicCalorieTargetMode: String, Codable, CaseIterable, Identifiable {
    case deficit
    case fixedDeficit
    case surplus

    var id: String { rawValue }
}

struct DynamicCalorieTargetBreakdown: Equatable {
    enum Source: Equatable {
        case fixed
        case dynamic
        case fixedFallback(FallbackReason)
    }

    enum FallbackReason: Equatable {
        case phaseMissing
        case phaseNotStarted
        case restingEnergyMissing
        case futureDate
    }

    let source: Source
    let targetKilocalories: Double
    let rawTargetKilocalories: Double
    let previousDayRestingEnergy: Double?
    let dynamicDeficit: Double?
    let fixedSurplus: Double?
    let phase: DynamicDeficitPhase?
    let completedCalendarDays: Int?
    let energyUpdatedAt: Date?
    let energySourceName: String?
    let energySourceCount: Int?
    let energySourceSelectionStrategy: String?
}

enum CalorieTargetCalculator {
    static let dailyDecayFactor = 0.9902
    static let energyFactor = 69.13

    /// Resolves the calories available for the day. Active energy expands a
    /// dynamic target, while a user-selected fixed target stays fixed.
    static func availableCalories(
        mode: CalorieGoalMode,
        targetKilocalories: Double,
        activeEnergy: Double,
        dayAdjustment: Double = 0
    ) -> Double {
        max(0, targetKilocalories + (mode == .dynamic ? activeEnergy : 0) + dayAdjustment)
    }

    static func completedCalendarDays(
        from startDate: Date,
        through targetDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    static func dynamicDeficit(
        phase: DynamicDeficitPhase,
        targetDate: Date,
        calendar: Calendar = .current
    ) -> (kilocalories: Double, completedDays: Int)? {
        let days = completedCalendarDays(from: phase.startedAt, through: targetDate, calendar: calendar)
        guard days >= 0 else { return nil }
        let deficit = phase.initialBodyFatFraction
            * phase.initialWeightKilograms
            * energyFactor
            * pow(dailyDecayFactor, Double(days))
        return (deficit, days)
    }

    /// Returns the phase that was active on a historical calendar day. The
    /// following phase implicitly ends the previous one, so selecting the
    /// latest start not after the target keeps old targets reproducible.
    static func activePhase(
        in phases: [DynamicDeficitPhase],
        for targetDate: Date,
        calendar: Calendar = .current
    ) -> DynamicDeficitPhase? {
        let targetDay = calendar.startOfDay(for: targetDate)
        return phases
            .filter { calendar.startOfDay(for: $0.startedAt) <= targetDay }
            .max { calendar.startOfDay(for: $0.startedAt) < calendar.startOfDay(for: $1.startedAt) }
    }

    /// Central source of truth for the daily base target. Active energy never
    /// enters this formula and is applied separately according to the goal mode.
    static func target(
        mode: CalorieGoalMode,
        fixedGoal: Double,
        dynamicMode: DynamicCalorieTargetMode = .deficit,
        fixedSurplus: Double = 0,
        fixedDeficit: Double = 0,
        phase: DynamicDeficitPhase?,
        targetDate: Date,
        previousDayEnergy: DailyEnergy?,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> DynamicCalorieTargetBreakdown {
        guard mode == .dynamic else {
            return fixed(fixedGoal, source: .fixed)
        }
        let targetDay = calendar.startOfDay(for: targetDate)
        let today = calendar.startOfDay(for: referenceDate)
        guard targetDay <= today else {
            // A future day's previous-day input would be today's still
            // incomplete Health value. Never project that partial value into
            // tomorrow (or later); use the user's normal fallback goal.
            return fixed(
                fixedGoal,
                source: .fixedFallback(.futureDate),
                phase: dynamicMode == .deficit ? phase : nil,
                deficit: dynamicMode == .fixedDeficit ? max(0, fixedDeficit) : nil,
                surplus: dynamicMode == .surplus ? max(0, fixedSurplus) : nil
            )
        }
        if dynamicMode == .surplus {
            guard let energy = previousDayEnergy, energy.resting > 0 else {
                return fixed(
                    fixedGoal,
                    source: .fixedFallback(.restingEnergyMissing),
                    surplus: max(0, fixedSurplus),
                    energy: previousDayEnergy
                )
            }
            let surplus = max(0, fixedSurplus)
            let rawTarget = energy.resting + surplus
            return DynamicCalorieTargetBreakdown(
                source: .dynamic,
                targetKilocalories: rawTarget,
                rawTargetKilocalories: rawTarget,
                previousDayRestingEnergy: energy.resting,
                dynamicDeficit: nil,
                fixedSurplus: surplus,
                phase: nil,
                completedCalendarDays: nil,
                energyUpdatedAt: energy.updatedAt,
                energySourceName: energy.sourceName,
                energySourceCount: energy.sourceCount,
                energySourceSelectionStrategy: energy.sourceSelectionStrategy
            )
        }
        if dynamicMode == .fixedDeficit {
            let deficit = max(0, fixedDeficit)
            guard let energy = previousDayEnergy, energy.resting > 0 else {
                return fixed(fixedGoal, source: .fixedFallback(.restingEnergyMissing), deficit: deficit, energy: previousDayEnergy)
            }
            let rawTarget = energy.resting - deficit
            return DynamicCalorieTargetBreakdown(
                source: .dynamic,
                targetKilocalories: max(0, rawTarget),
                rawTargetKilocalories: rawTarget,
                previousDayRestingEnergy: energy.resting,
                dynamicDeficit: deficit,
                fixedSurplus: nil,
                phase: nil,
                completedCalendarDays: nil,
                energyUpdatedAt: energy.updatedAt,
                energySourceName: energy.sourceName,
                energySourceCount: energy.sourceCount,
                energySourceSelectionStrategy: energy.sourceSelectionStrategy
            )
        }
        guard let phase else {
            return fixed(fixedGoal, source: .fixedFallback(.phaseMissing))
        }
        guard let calculated = dynamicDeficit(phase: phase, targetDate: targetDate, calendar: calendar) else {
            return fixed(fixedGoal, source: .fixedFallback(.phaseNotStarted), phase: phase)
        }
        guard let energy = previousDayEnergy, energy.resting > 0 else {
            return fixed(
                fixedGoal,
                source: .fixedFallback(.restingEnergyMissing),
                phase: phase,
                deficit: calculated.kilocalories,
                completedDays: calculated.completedDays,
                energy: previousDayEnergy
            )
        }

        let rawTarget = energy.resting - calculated.kilocalories
        // Hyse already prevented negative calorie targets before this feature.
        // Keep that existing floor; no additional arbitrary limit is introduced.
        let target = max(0, rawTarget)
        return DynamicCalorieTargetBreakdown(
            source: .dynamic,
            targetKilocalories: target,
            rawTargetKilocalories: rawTarget,
            previousDayRestingEnergy: energy.resting,
            dynamicDeficit: calculated.kilocalories,
            fixedSurplus: nil,
            phase: phase,
            completedCalendarDays: calculated.completedDays,
            energyUpdatedAt: energy.updatedAt,
            energySourceName: energy.sourceName,
            energySourceCount: energy.sourceCount,
            energySourceSelectionStrategy: energy.sourceSelectionStrategy
        )
    }

    private static func fixed(
        _ goal: Double,
        source: DynamicCalorieTargetBreakdown.Source,
        phase: DynamicDeficitPhase? = nil,
        deficit: Double? = nil,
        surplus: Double? = nil,
        completedDays: Int? = nil,
        energy: DailyEnergy? = nil
    ) -> DynamicCalorieTargetBreakdown {
        DynamicCalorieTargetBreakdown(
            source: source,
            targetKilocalories: goal,
            rawTargetKilocalories: goal,
            previousDayRestingEnergy: energy?.resting,
            dynamicDeficit: deficit,
            fixedSurplus: surplus,
            phase: phase,
            completedCalendarDays: completedDays,
            energyUpdatedAt: energy?.updatedAt,
            energySourceName: energy?.sourceName,
            energySourceCount: energy?.sourceCount,
            energySourceSelectionStrategy: energy?.sourceSelectionStrategy
        )
    }
}
