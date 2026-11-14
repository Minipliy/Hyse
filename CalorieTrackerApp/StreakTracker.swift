import Foundation

/// Calendar-day based streak rules. Only an action performed for the user's
/// current local day creates activity; backdated or future entries never do.
enum StreakTracker {
    static func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func date(forDayKey key: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func recordingActivity(
        for entryDate: Date,
        now: Date = Date(),
        existing: Set<String>,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<String> {
        guard calendar.isDate(entryDate, inSameDayAs: now) else { return existing }
        var updated = existing
        updated.insert(dayKey(for: now, calendar: calendar))
        return updated
    }

    static func currentStreak(
        activityDays: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        var cursor = calendar.startOfDay(for: now)
        // A streak remains current throughout the following day so it does not
        // visually drop to zero before the user has had a chance to log today.
        // Once an entire local calendar day is missed, the streak is broken.
        if !hasActivityToday(activityDays: activityDays, now: now, calendar: calendar) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  activityDays.contains(dayKey(for: yesterday, calendar: calendar)) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while activityDays.contains(dayKey(for: cursor, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func hasActivityToday(
        activityDays: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        activityDays.contains(dayKey(for: now, calendar: calendar))
    }

    static func longestStreak(activityDays: Set<String>, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let days = activityDays.compactMap { date(forDayKey: $0, calendar: calendar) }.sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for index in 1..<days.count {
            if calendar.dateComponents([.day], from: days[index - 1], to: days[index]).day == 1 {
                current += 1
                best = max(best, current)
            } else if !calendar.isDate(days[index - 1], inSameDayAs: days[index]) {
                current = 1
            }
        }
        return best
    }
}
