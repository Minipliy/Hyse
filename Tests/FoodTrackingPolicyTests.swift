import Foundation

final class LanguageStore {
    let locale = Locale(identifier: "de_DE")
    func text(_ key: String, _ arguments: [CVarArg] = []) -> String { key }
}

@main
struct FoodTrackingPolicyTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func time(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: hour, minute: minute))!
        }

        let daytime = FoodTrackingRules(
            blockWhileFastingEnabled: false,
            windowEnabled: true,
            windowStartMinutes: 6 * 60,
            windowEndMinutes: 18 * 60,
            lowRemainingLockEnabled: false,
            lowRemainingLockStartMinutes: 18 * 60,
            lowRemainingCaloriesThreshold: 200
        )
        expectBlocked(daytime, at: time(5, 59), remaining: 1_000, calendar: calendar)
        expectAllowed(daytime, at: time(6), remaining: 1_000, calendar: calendar)
        expectAllowed(daytime, at: time(17, 59), remaining: 1_000, calendar: calendar)
        expectBlocked(daytime, at: time(18), remaining: 1_000, calendar: calendar)
        precondition(!FoodTrackingPolicy.isWithinAllowedWindow(at: time(5, 59), startMinutes: 6 * 60, endMinutes: 18 * 60, calendar: calendar))
        precondition(FoodTrackingPolicy.isWithinAllowedWindow(at: time(6), startMinutes: 6 * 60, endMinutes: 18 * 60, calendar: calendar))
        precondition(!FoodTrackingPolicy.isWithinAllowedWindow(at: time(18), startMinutes: 6 * 60, endMinutes: 18 * 60, calendar: calendar))

        var overnight = daytime
        overnight.windowStartMinutes = 18 * 60
        overnight.windowEndMinutes = 6 * 60
        expectAllowed(overnight, at: time(23), remaining: 1_000, calendar: calendar)
        expectAllowed(overnight, at: time(5, 59), remaining: 1_000, calendar: calendar)
        expectBlocked(overnight, at: time(12), remaining: 1_000, calendar: calendar)
        precondition(FoodTrackingPolicy.isWithinAllowedWindow(at: time(23), startMinutes: 18 * 60, endMinutes: 6 * 60, calendar: calendar))
        precondition(!FoodTrackingPolicy.isWithinAllowedWindow(at: time(12), startMinutes: 18 * 60, endMinutes: 6 * 60, calendar: calendar))
        precondition(FoodTrackingPolicy.isWithinAllowedWindow(at: time(12), startMinutes: 8 * 60, endMinutes: 8 * 60, calendar: calendar))

        var evening = daytime
        evening.windowEnabled = false
        evening.lowRemainingLockEnabled = true
        expectAllowed(evening, at: time(17, 59), remaining: 199, calendar: calendar)
        expectBlocked(evening, at: time(18), remaining: 199, calendar: calendar)
        expectAllowed(evening, at: time(18), remaining: 200, calendar: calendar)

        var fasting = daytime
        fasting.windowEnabled = false
        fasting.blockWhileFastingEnabled = true
        precondition(FoodTrackingPolicy.restriction(rules: fasting, at: time(12), remainingCalories: 1_000, isFasting: true, calendar: calendar) == .activeFast)
        precondition(FoodTrackingPolicy.restriction(rules: fasting, at: time(12), remainingCalories: 1_000, isFasting: false, calendar: calendar) == nil)

        print("FoodTrackingPolicyTests: all checks passed")
    }

    private static func expectAllowed(_ rules: FoodTrackingRules, at date: Date, remaining: Double, calendar: Calendar) {
        precondition(FoodTrackingPolicy.restriction(rules: rules, at: date, remainingCalories: remaining, calendar: calendar) == nil)
    }

    private static func expectBlocked(_ rules: FoodTrackingRules, at date: Date, remaining: Double, calendar: Calendar) {
        precondition(FoodTrackingPolicy.restriction(rules: rules, at: date, remainingCalories: remaining, calendar: calendar) != nil)
    }
}
