import Foundation
@preconcurrency import UserNotifications

nonisolated enum MotivationNotificationFrequency: String, CaseIterable, Identifiable, Sendable {
    case daily, weekdays, threePerWeek = "three_per_week", weekly
    var id: String { rawValue }
    var localizationKey: String { "settings.notification_frequency.\(rawValue)" }
}

nonisolated struct MotivationNotificationConfiguration: Sendable {
    let enabled: Bool
    let frequency: MotivationNotificationFrequency
    let motivationalMessages: Bool
    let foodLogReminder: Bool
    let waterReminder: Bool
    let plannedTrainingReminder: Bool
    let missingDailyDataReminder: Bool
}

nonisolated struct PlannedTrainingNotification: Sendable {
    let date: Date
    let title: String
}

nonisolated struct MotivationNotificationContext: Sendable {
    let hasFoodToday: Bool
    let waterAmountMilliliters: Double
    let waterGoalMilliliters: Double
    let plannedTrainings: [PlannedTrainingNotification]

    static let empty = MotivationNotificationContext(
        hasFoodToday: false,
        waterAmountMilliliters: 0,
        waterGoalMilliliters: 0,
        plannedTrainings: []
    )
}

@MainActor
final class MotivationNotificationManager {
    static let shared = MotivationNotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let motivationPrefix = "hyse.motivation."
    private let foodLogPrefix = "hyse.food-log."
    private let waterPrefix = "hyse.water."
    private let plannedTrainingPrefix = "hyse.planned-training."
    private let missingDataPrefix = "hyse.missing-data."
    private let notificationScheduleDays = 14
    private let foodLogReminderHours = [14, 19]
    private let waterReminderHours = [10, 14, 18]
    private let missingDataReminderHour = 20
    private let plannedTrainingReminderHour = 17
    private let foodLoggedDayKey = "hyse.food-log.logged-day"
    private var notificationScheduleRevision: UInt = 0
    private init() {}

    func setEnabled(_ configuration: MotivationNotificationConfiguration, language: AppLanguage, hasFoodToday: Bool) async -> Bool {
        await setEnabled(
            configuration,
            language: language,
            context: MotivationNotificationContext(
                hasFoodToday: hasFoodToday,
                waterAmountMilliliters: 0,
                waterGoalMilliliters: 0,
                plannedTrainings: []
            )
        )
    }

    func setEnabled(_ configuration: MotivationNotificationConfiguration, language: AppLanguage, context: MotivationNotificationContext) async -> Bool {
        if context.hasFoodToday { markFoodLogged(for: Date()) }
        guard configuration.enabled else { removeScheduledNotifications(); return false }
        let currentSettings = await center.notificationSettings()
        let isAllowed: Bool
        switch currentSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: isAllowed = true
        case .notDetermined: isAllowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied: isAllowed = false
        @unknown default: isAllowed = false
        }
        if isAllowed { await schedule(configuration, language: language, context: context) }
        else { removeScheduledNotifications() }
        return isAllowed
    }

    func applyStoredPreference(_ configuration: MotivationNotificationConfiguration, language: AppLanguage, hasFoodToday: Bool = false) {
        if hasFoodToday { markFoodLogged(for: Date()) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard configuration.enabled else { self.removeScheduledNotifications(); return }
            let settings = await self.center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: await self.schedule(configuration, language: language, context: .empty)
            case .notDetermined, .denied: self.removeScheduledNotifications()
            @unknown default: self.removeScheduledNotifications()
            }
        }
    }

    func cancelFoodLogReminder(for date: Date = Date()) {
        markFoodLogged(for: date)
        notificationScheduleRevision &+= 1
        let calendar = Calendar.autoupdatingCurrent
        let legacyMotivationIdentifier = motivationPrefix + "\(calendar.component(.weekday, from: date))"
        let identifiers = foodLogReminderHours.map { foodLogIdentifier(date, hour: $0) }
            + [motivationIdentifier(date), legacyMotivationIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func restoreTodayFoodLogReminderIfNeeded(language: AppLanguage) {
        let today = Date()
        clearFoodLogged(for: today)
        notificationScheduleRevision &+= 1
        let defaults = UserDefaults.standard
        let notificationsEnabled = defaults.object(forKey: "motivationNotificationsEnabled_v1") as? Bool ?? true
        let foodLogReminderEnabled = defaults.object(forKey: "foodLogReminderEnabled_v1") as? Bool ?? true
        let motivationalMessagesEnabled = defaults.object(forKey: "motivationalMessagesEnabled_v1") as? Bool ?? false
        let frequency = MotivationNotificationFrequency(
            rawValue: defaults.string(forKey: "motivationNotificationFrequency_v1") ?? ""
        ) ?? .daily
        let configuration = MotivationNotificationConfiguration(
            enabled: notificationsEnabled,
            frequency: frequency,
            motivationalMessages: motivationalMessagesEnabled,
            foodLogReminder: foodLogReminderEnabled,
            waterReminder: defaults.object(forKey: "waterReminderEnabled_v1") as? Bool ?? false,
            plannedTrainingReminder: defaults.object(forKey: "plannedTrainingReminderEnabled_v1") as? Bool ?? false,
            missingDailyDataReminder: defaults.object(forKey: "missingDailyDataReminderEnabled_v1") as? Bool ?? false
        )
        guard configuration.enabled else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let settings = await self.center.notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            await self.schedule(configuration, language: language, context: .empty)
        }
    }

    private func schedule(_ configuration: MotivationNotificationConfiguration, language: AppLanguage, context: MotivationNotificationContext) async {
        notificationScheduleRevision &+= 1
        await removeScheduledNotificationsBeforeRescheduling()
        if configuration.motivationalMessages {
            await scheduleMotivationalMessages(
                frequency: configuration.frequency,
                language: language,
                skipToday: context.hasFoodToday || hasLoggedFood(on: Date())
            )
        }
        if configuration.foodLogReminder {
            await scheduleFoodLogReminders(
                language: language,
                skipToday: context.hasFoodToday || hasLoggedFood(on: Date())
            )
        }
        if configuration.waterReminder {
            await scheduleWaterReminders(language: language, context: context)
        }
        if configuration.plannedTrainingReminder {
            await schedulePlannedTrainingReminders(language: language, trainings: context.plannedTrainings)
        }
        if configuration.missingDailyDataReminder {
            await scheduleMissingDailyDataReminders(language: language, context: context)
        }
    }

    private func scheduleMotivationalMessages(
        frequency: MotivationNotificationFrequency,
        language: AppLanguage,
        skipToday: Bool
    ) async {
        let calendar = Calendar.autoupdatingCurrent
        let weekdays = Set(scheduledWeekdays(for: frequency))
        let revision = notificationScheduleRevision
        for offset in 0..<notificationScheduleDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()),
                  weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            if offset == 0 && (skipToday || hasLoggedFood(on: day)) { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = 18
            guard let fireDate = calendar.date(from: components), fireDate > Date() else { continue }
            let identifier = motivationIdentifier(day)
            try? await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: motivationNotificationContent(language: language, day: day),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            )
            if offset == 0 && (revision != notificationScheduleRevision || hasLoggedFood(on: day)) {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
            }
        }
    }

    private func scheduleFoodLogReminders(language: AppLanguage, skipToday: Bool) async {
        let calendar = Calendar.autoupdatingCurrent
        let revision = notificationScheduleRevision
        for offset in 0..<notificationScheduleDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            if offset == 0 && (skipToday || hasLoggedFood(on: day)) { continue }
            for hour in foodLogReminderHours {
                guard revision == notificationScheduleRevision || offset > 0 else { continue }
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = hour
                guard let fireDate = calendar.date(from: components), fireDate > Date() else { continue }
                let identifier = foodLogIdentifier(day, hour: hour)
                try? await center.add(
                    UNNotificationRequest(
                        identifier: identifier,
                        content: foodLogNotificationContent(language: language),
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    )
                )
                if offset == 0 && (revision != notificationScheduleRevision || hasLoggedFood(on: day)) {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                }
            }
        }
    }

    private func scheduleWaterReminders(language: AppLanguage, context: MotivationNotificationContext) async {
        let calendar = Calendar.autoupdatingCurrent
        let goal = max(0, context.waterGoalMilliliters)
        let todayNeedsWater = goal <= 0 || context.waterAmountMilliliters < goal
        for offset in 0..<notificationScheduleDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            if offset == 0 && !todayNeedsWater { continue }
            for hour in waterReminderHours {
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = hour
                guard let fireDate = calendar.date(from: components), fireDate > Date() else { continue }
                try? await center.add(
                    UNNotificationRequest(
                        identifier: waterIdentifier(day, hour: hour),
                        content: waterNotificationContent(language: language),
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    )
                )
            }
        }
    }

    private func schedulePlannedTrainingReminders(language: AppLanguage, trainings: [PlannedTrainingNotification]) async {
        let calendar = Calendar.autoupdatingCurrent
        for training in trainings.prefix(40) {
            var components = calendar.dateComponents([.year, .month, .day], from: training.date)
            components.hour = plannedTrainingReminderHour
            guard let fireDate = calendar.date(from: components), fireDate > Date() else { continue }
            try? await center.add(
                UNNotificationRequest(
                    identifier: plannedTrainingIdentifier(training.date, title: training.title),
                    content: plannedTrainingNotificationContent(language: language, title: training.title),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            )
        }
    }

    private func scheduleMissingDailyDataReminders(language: AppLanguage, context: MotivationNotificationContext) async {
        let calendar = Calendar.autoupdatingCurrent
        let todayComplete = context.hasFoodToday && (
            context.waterGoalMilliliters <= 0 || context.waterAmountMilliliters >= context.waterGoalMilliliters
        )
        for offset in 0..<notificationScheduleDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            if offset == 0 && todayComplete { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = missingDataReminderHour
            guard let fireDate = calendar.date(from: components), fireDate > Date() else { continue }
            try? await center.add(
                UNNotificationRequest(
                    identifier: missingDataIdentifier(day),
                    content: missingDataNotificationContent(language: language),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            )
        }
    }

    private func scheduledWeekdays(for frequency: MotivationNotificationFrequency) -> [Int] {
        switch frequency {
        case .daily: Array(1...7)
        case .weekdays: Array(2...6)
        case .threePerWeek: [2, 4, 7]
        case .weekly: [2]
        }
    }

    private func motivationNotificationContent(language: AppLanguage, day: Date) -> UNMutableNotificationContent {
        let bodies = [
            "motivation.notification.body.consistency",
            "motivation.notification.body.progress",
            "motivation.notification.body.weekend"
        ]
        let weekday = Calendar.autoupdatingCurrent.component(.weekday, from: day)
        let content = UNMutableNotificationContent()
        content.title = LanguageStore.localizedString("motivation.notification.title", language: language)
        content.body = LanguageStore.localizedString(bodies[(weekday - 1) % bodies.count], language: language)
        content.sound = .default
        return content
    }

    private func foodLogNotificationContent(language: AppLanguage) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = LanguageStore.localizedString("food_log.notification.title", language: language)
        content.body = LanguageStore.localizedString("food_log.notification.body", language: language)
        content.sound = .default
        return content
    }

    private func waterNotificationContent(language: AppLanguage) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = LanguageStore.localizedString("water_reminder.notification.title", language: language)
        content.body = LanguageStore.localizedString("water_reminder.notification.body", language: language)
        content.sound = .default
        return content
    }

    private func plannedTrainingNotificationContent(language: AppLanguage, title: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = LanguageStore.localizedString("planned_training.notification.title", language: language)
        let format = LanguageStore.localizedString("planned_training.notification.body", language: language)
        content.body = String(format: format, title)
        content.sound = .default
        return content
    }

    private func missingDataNotificationContent(language: AppLanguage) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = LanguageStore.localizedString("missing_data.notification.title", language: language)
        content.body = LanguageStore.localizedString("missing_data.notification.body", language: language)
        content.sound = .default
        return content
    }

    private func foodLogIdentifier(_ date: Date, hour: Int) -> String {
        foodLogPrefix + notificationIdentifierDay(for: date) + ".\(hour)"
    }

    private func motivationIdentifier(_ date: Date) -> String {
        motivationPrefix + notificationIdentifierDay(for: date) + ".18"
    }

    private func waterIdentifier(_ date: Date, hour: Int) -> String {
        waterPrefix + notificationIdentifierDay(for: date) + ".\(hour)"
    }

    private func plannedTrainingIdentifier(_ date: Date, title: String) -> String {
        let safeTitle = String(title.filter { $0.isLetter || $0.isNumber }.prefix(24))
        return plannedTrainingPrefix + notificationIdentifierDay(for: date) + ".\(safeTitle)"
    }

    private func missingDataIdentifier(_ date: Date) -> String {
        missingDataPrefix + notificationIdentifierDay(for: date) + ".\(missingDataReminderHour)"
    }

    private func notificationIdentifierDay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .init(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func markFoodLogged(for date: Date) {
        UserDefaults.standard.set(notificationDayKey(for: date), forKey: foodLoggedDayKey)
    }

    private func clearFoodLogged(for date: Date) {
        guard hasLoggedFood(on: date) else { return }
        UserDefaults.standard.removeObject(forKey: foodLoggedDayKey)
    }

    private func hasLoggedFood(on date: Date) -> Bool {
        UserDefaults.standard.string(forKey: foodLoggedDayKey) == notificationDayKey(for: date)
    }

    private func notificationDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func removeScheduledNotifications() {
        let prefixes = [motivationPrefix, foodLogPrefix, waterPrefix, plannedTrainingPrefix, missingDataPrefix]
        center.getPendingNotificationRequests { [center, prefixes] requests in
            let ids = requests.map(\.identifier).filter { identifier in prefixes.contains { identifier.hasPrefix($0) } }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func removeScheduledNotificationsBeforeRescheduling() async {
        let prefixes = [motivationPrefix, foodLogPrefix, waterPrefix, plannedTrainingPrefix, missingDataPrefix]
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { [center, prefixes] requests in
                let ids = requests.map(\.identifier).filter { identifier in prefixes.contains { identifier.hasPrefix($0) } }
                center.removePendingNotificationRequests(withIdentifiers: ids)
                continuation.resume()
            }
        }
    }
}
