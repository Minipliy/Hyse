import Foundation

nonisolated struct FoodTrackingRules: Equatable {
    var blockWhileFastingEnabled: Bool
    var windowEnabled: Bool
    var windowStartMinutes: Int
    var windowEndMinutes: Int
    var lowRemainingLockEnabled: Bool
    var lowRemainingLockStartMinutes: Int
    var lowRemainingCaloriesThreshold: Double
}

nonisolated enum FoodTrackingRestriction: Equatable {
    case activeFast
    case outsideAllowedWindow(startMinutes: Int, endMinutes: Int)
    case lowRemainingCalories(startMinutes: Int, threshold: Double, remaining: Double)
    case calorieLimitExceeded

    @MainActor
    func message(using language: LanguageStore) -> String {
        switch self {
        case .activeFast:
            return language.text("food_tracking.active_fast_block")
        case .outsideAllowedWindow(let start, let end):
            return language.text(
                "food_tracking.outside_window",
                [
                    Self.formattedTime(start, locale: language.locale),
                    Self.formattedTime(end, locale: language.locale)
                ]
            )
        case .lowRemainingCalories(let start, let threshold, let remaining):
            return language.text(
                "food_tracking.low_remaining_block",
                [
                    Self.formattedTime(start, locale: language.locale),
                    Int(threshold.rounded()),
                    Int(remaining.rounded())
                ]
            )
        case .calorieLimitExceeded:
            return language.text("add_entry.daily_limit_exceeded")
        }
    }

    private static func formattedTime(_ minutes: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let normalized = FoodTrackingPolicy.normalizedMinutes(minutes)
        let date = calendar.date(from: DateComponents(hour: normalized / 60, minute: normalized % 60)) ?? Date()
        return date.formatted(.dateTime.hour().minute().locale(locale))
    }
}

nonisolated enum FoodTrackingPolicy {
    static func isWithinAllowedWindow(
        at date: Date,
        startMinutes: Int,
        endMinutes: Int,
        calendar: Calendar = .current
    ) -> Bool {
        let start = normalizedMinutes(startMinutes)
        let end = normalizedMinutes(endMinutes)
        // Identical endpoints mean no restriction, rather than an accidental
        // permanent lock that cannot be changed until tomorrow.
        guard start != end else { return true }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let current = normalizedMinutes((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return start < end
            ? current >= start && current < end
            : current >= start || current < end
    }

    static func restriction(
        rules: FoodTrackingRules,
        at date: Date,
        remainingCalories: Double,
        isFasting: Bool = false,
        calendar: Calendar = .current
    ) -> FoodTrackingRestriction? {
        if rules.blockWhileFastingEnabled, isFasting {
            return .activeFast
        }
        let start = normalizedMinutes(rules.windowStartMinutes)
        let end = normalizedMinutes(rules.windowEndMinutes)

        if rules.windowEnabled,
           !isWithinAllowedWindow(at: date, startMinutes: start, endMinutes: end, calendar: calendar) {
            return .outsideAllowedWindow(startMinutes: start, endMinutes: end)
        }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let current = normalizedMinutes((components.hour ?? 0) * 60 + (components.minute ?? 0))
        let lockStart = normalizedMinutes(rules.lowRemainingLockStartMinutes)
        if rules.lowRemainingLockEnabled,
           current >= lockStart,
           remainingCalories < max(0, rules.lowRemainingCaloriesThreshold) {
            return .lowRemainingCalories(
                startMinutes: lockStart,
                threshold: max(0, rules.lowRemainingCaloriesThreshold),
                remaining: remainingCalories
            )
        }
        return nil
    }

    static func normalizedMinutes(_ value: Int) -> Int {
        let remainder = value % (24 * 60)
        return remainder >= 0 ? remainder : remainder + 24 * 60
    }
}
