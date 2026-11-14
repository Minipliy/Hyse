import Foundation

@main
struct StreakTrackerTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!

        let todayActivity = StreakTracker.recordingActivity(for: now, now: now, existing: [], calendar: calendar)
        expect(todayActivity.count == 1, "today should create one activity day")
        expect(StreakTracker.currentStreak(activityDays: todayActivity, now: now, calendar: calendar) == 1, "today should start the streak")

        let yesterdayOnly = StreakTracker.recordingActivity(for: yesterday, now: now, existing: [], calendar: calendar)
        expect(yesterdayOnly.isEmpty, "backdated entry must not create activity")
        let tomorrowOnly = StreakTracker.recordingActivity(for: tomorrow, now: now, existing: [], calendar: calendar)
        expect(tomorrowOnly.isEmpty, "future entry must not create activity")

        let repeatedToday = StreakTracker.recordingActivity(for: now, now: now, existing: todayActivity, calendar: calendar)
        expect(repeatedToday == todayActivity, "multiple entries today must remain one activity day")
        let editedToday = StreakTracker.recordingActivity(for: now, now: now, existing: repeatedToday, calendar: calendar)
        expect(editedToday == todayActivity, "editing must not increment the streak twice")

        let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 23, minute: 59))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 0, minute: 1))!
        let firstDay = StreakTracker.recordingActivity(for: beforeMidnight, now: beforeMidnight, existing: [], calendar: calendar)
        expect(StreakTracker.currentStreak(activityDays: firstDay, now: afterMidnight, calendar: calendar) == 1, "streak must remain visible until the current local day ends")
        expect(!StreakTracker.hasActivityToday(activityDays: firstDay, now: afterMidnight, calendar: calendar), "a carried streak must remain visually inactive until today's activity")
        let secondDay = StreakTracker.recordingActivity(for: afterMidnight, now: afterMidnight, existing: firstDay, calendar: calendar)
        expect(StreakTracker.currentStreak(activityDays: secondDay, now: afterMidnight, calendar: calendar) == 2, "consecutive local calendar days should form a streak")
        expect(StreakTracker.hasActivityToday(activityDays: secondDay, now: afterMidnight, calendar: calendar), "today's activity must activate the streak styling")

        let restoredAfterRestart = Set(Array(secondDay))
        expect(StreakTracker.currentStreak(activityDays: restoredAfterRestart, now: afterMidnight, calendar: calendar) == 2, "persisted activity days must survive a restart")

        let dayBeforeGap = calendar.date(byAdding: .day, value: -2, to: afterMidnight)!
        let withMissingDay: Set<String> = [
            StreakTracker.dayKey(for: dayBeforeGap, calendar: calendar),
            StreakTracker.dayKey(for: afterMidnight, calendar: calendar)
        ]
        expect(StreakTracker.currentStreak(activityDays: withMissingDay, now: afterMidnight, calendar: calendar) == 1, "a missing calendar day must break the current streak")

        let dayAfterGap = calendar.date(byAdding: .day, value: 1, to: afterMidnight)!
        expect(StreakTracker.currentStreak(activityDays: firstDay, now: dayAfterGap, calendar: calendar) == 0, "a complete missed local day must reset the streak")

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        expect(StreakTracker.currentStreak(activityDays: firstDay, now: afterMidnight, calendar: losAngeles) == 1, "timezone changes must evaluate the user's current local calendar day")

        print("StreakTracker tests passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
