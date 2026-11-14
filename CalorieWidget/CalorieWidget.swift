import WidgetKit
import SwiftUI
import AppIntents

struct WidgetLogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.add_water_intent"
    static var description = IntentDescription("widget.add_water_intent_description")

    func perform() async throws -> some IntentResult {
        guard let defaults = UserDefaults(suiteName: WidgetLocalization.appGroupID) else {
            throw NSError(domain: "HyseWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: WidgetLocalization.text("widget.water_save_failed")])
        }
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: Date())
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        // Each tap has its own key, so a simultaneous in-app edit cannot overwrite it.
        defaults.set(250.0, forKey: "water_external_add_v1_\(day)_\(UUID().uuidString)")
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

enum WidgetLocalization {
    static let storageKey = "app_language_v1"
    static let appGroupID = HyseConfiguration.appGroup

    static var languageCode: String {
        UserDefaults(suiteName: appGroupID)?.string(forKey: storageKey) == "de" ? "de" : "en"
    }

    static func text(_ key: String) -> String {
        let english = value(key, languageCode: "en")
        guard languageCode != "en" else { return english == key ? key : english }
        let translated = value(key, languageCode: languageCode)
        return translated == key ? english : translated
    }

    private static func value(_ key: String, languageCode: String) -> String {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)

        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

// MARK: - Timeline Entry
struct CalorieWidgetEntry: TimelineEntry {
    let date: Date
    let eatenKcal: Int
    let goalKcal: Int
    let waterMilliliters: Int
    let waterGoalMilliliters: Int
    let carbsGrams: Int
    let proteinGrams: Int
    let fatGrams: Int
    let carbsGoalGrams: Int
    let proteinGoalGrams: Int
    let fatGoalGrams: Int
    let macroGoalsAvailable: Bool
    let workoutsThisWeek: Int
    let workoutMinutesThisWeek: Int
    let workoutDailyCounts: [Int]
}

// MARK: - Timeline Provider
struct CalorieWidgetProvider: TimelineProvider {
    private let appGroupID = HyseConfiguration.appGroup

    func placeholder(in context: Context) -> CalorieWidgetEntry {
        CalorieWidgetEntry(date: Date(), eatenKcal: 1450, goalKcal: 2000, waterMilliliters: 500, waterGoalMilliliters: 2000,
                           carbsGrams: 120, proteinGrams: 90, fatGrams: 45, carbsGoalGrams: 250,
                           proteinGoalGrams: 150, fatGoalGrams: 65, macroGoalsAvailable: true,
                           workoutsThisWeek: 3, workoutMinutesThisWeek: 165,
                           workoutDailyCounts: [1, 0, 1, 0, 1, 0, 0])
    }

    func getSnapshot(in context: Context, completion: @escaping (CalorieWidgetEntry) -> Void) {
        completion(loadData(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalorieWidgetEntry>) -> Void) {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(24 * 60 * 60)

        // WidgetKit can render this entry at midnight without waiting for the
        // main app to launch. `loadData` recognizes that the persisted calories
        // belong to yesterday and returns a clean zero for the new day.
        let entries = [
            loadData(for: now),
            loadData(for: startOfTomorrow)
        ]
        let nextUpdate = calendar.date(byAdding: .minute, value: 5, to: startOfTomorrow)
            ?? startOfTomorrow.addingTimeInterval(5 * 60)
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadData(for date: Date) -> CalorieWidgetEntry {
        let userDefaults = UserDefaults(suiteName: appGroupID)
        userDefaults?.synchronize()
        let calendar = Calendar.autoupdatingCurrent
        let storedDayTimestamp = userDefaults?.object(forKey: "todayEatenDate") as? TimeInterval
        let legacyUpdateTimestamp = userDefaults?.object(forKey: "widgetDataUpdatedAt") as? TimeInterval
        let storedDay = (storedDayTimestamp ?? legacyUpdateTimestamp).map(Date.init(timeIntervalSince1970:))
        let belongsToRequestedDay = storedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let eaten = belongsToRequestedDay ? (userDefaults?.integer(forKey: "todayEatenKcal") ?? 0) : 0
        let storedGoal = userDefaults?.integer(forKey: "todayGoalKcal") ?? 0
        let fallbackGoal = userDefaults?.integer(forKey: "widgetFallbackGoalKcal") ?? 0
        let storedGoalTimestamp = userDefaults?.object(forKey: "todayGoalDate") as? TimeInterval
        let storedGoalDay = storedGoalTimestamp.map(Date.init(timeIntervalSince1970:))
        let goalBelongsToRequestedDay = storedGoalDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let goal = goalBelongsToRequestedDay
            ? storedGoal
            : (fallbackGoal > 0 ? fallbackGoal : storedGoal)
        let waterData = userDefaults?.data(forKey: "daily_water_amounts_v1")
        let waterAmounts = waterData.flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let waterDay = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let pending = userDefaults?.dictionaryRepresentation().reduce(0.0) { total, item in
            guard item.key.hasPrefix("water_external_add_v1_\(waterDay)_"), let amount = item.value as? Double else { return total }
            return total + amount
        } ?? 0
        let storedWaterGoal = userDefaults?.double(forKey: "widgetWaterGoalMilliliters") ?? 0
        let waterGoal = storedWaterGoal.isFinite && (1...100_000).contains(storedWaterGoal)
            ? Int(storedWaterGoal) : 2000
        let waterAmount = max(0, waterAmounts[waterDay, default: 0] + pending)
        let macroDayTimestamp = userDefaults?.object(forKey: "widgetMacroDate") as? TimeInterval
        let macrosBelongToDay = macroDayTimestamp.map { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: date) } ?? false
        let macroGoalDayTimestamp = userDefaults?.object(forKey: "widgetMacroGoalDate") as? TimeInterval
        let macroGoalsBelongToDay = macroGoalDayTimestamp.map { calendar.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: date) } ?? false
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start.timeIntervalSince1970
        let storedWeekStart = userDefaults?.object(forKey: "widgetTrainingWeekStart") as? TimeInterval
        let isStoredWeek = weekStart == storedWeekStart
        func grams(_ key: String, when belongsToDay: Bool) -> Int {
            guard belongsToDay else { return 0 }
            let value = userDefaults?.double(forKey: key) ?? 0
            return value.isFinite ? Int(max(0, min(value.rounded(), 1_000_000))) : 0
        }
        return CalorieWidgetEntry(date: date, eatenKcal: eaten, goalKcal: max(goal, 1),
                                  waterMilliliters: waterAmount.isFinite ? Int(min(waterAmount, 1_000_000)) : 0,
                                  waterGoalMilliliters: waterGoal,
                                  carbsGrams: grams("widgetCarbsGrams", when: macrosBelongToDay),
                                  proteinGrams: grams("widgetProteinGrams", when: macrosBelongToDay),
                                  fatGrams: grams("widgetFatGrams", when: macrosBelongToDay),
                                  carbsGoalGrams: grams("widgetCarbsGoalGrams", when: macroGoalsBelongToDay),
                                  proteinGoalGrams: grams("widgetProteinGoalGrams", when: macroGoalsBelongToDay),
                                  fatGoalGrams: grams("widgetFatGoalGrams", when: macroGoalsBelongToDay),
                                  macroGoalsAvailable: macroGoalsBelongToDay,
                                  workoutsThisWeek: isStoredWeek ? max(0, userDefaults?.integer(forKey: "widgetWorkoutsThisWeek") ?? 0) : 0,
                                  workoutMinutesThisWeek: isStoredWeek ? max(0, userDefaults?.integer(forKey: "widgetWorkoutMinutesThisWeek") ?? 0) : 0,
                                  workoutDailyCounts: isStoredWeek ? (userDefaults?.array(forKey: "widgetWorkoutDailyCounts") as? [Int] ?? Array(repeating: 0, count: 7)) : Array(repeating: 0, count: 7))
    }
}

// MARK: - Main Widget Entry View
struct CalorieWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: CalorieWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            LockScreenCircularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        case .systemMedium:
            HomeScreenMediumView(entry: entry)
        default:
            // Hier KEIN .containerBackground aufrufen, das macht HomeScreenSmallView selbst!
            HomeScreenSmallView(entry: entry)
        }
    }
}

struct HomeScreenMediumView: View {
    let entry: CalorieWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(WidgetLocalization.text("widget.kcal_eaten"), systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                Text("\(entry.eatenKcal) / \(entry.goalKcal)")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                ProgressView(value: min(Double(entry.eatenKcal) / Double(max(entry.goalKcal, 1)), 1))
                    .tint(Color(hex: "0E8C8C"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Label(WidgetLocalization.text("widget.water"), systemImage: "drop.fill")
                    .font(.subheadline.weight(.semibold))
                Text("\(entry.waterMilliliters) / \(entry.waterGoalMilliliters) ml")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                ProgressView(value: min(Double(entry.waterMilliliters) / Double(max(entry.waterGoalMilliliters, 1)), 1))
                    .tint(Color(hex: "0E8C8C"))
                Button(intent: WidgetLogWaterIntent()) {
                    Label(WidgetLocalization.text("widget.add_water"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "0E8C8C"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

// MARK: - HOME SCREEN WIDGET VIEW
struct HomeScreenSmallView: View {
    var entry: CalorieWidgetEntry

    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.colorScheme) var colorScheme // Erkennt Light/Dark Mode vom System

    private var progress: Double {
        min(max(Double(entry.eatenKcal) / Double(entry.goalKcal), 0.0), 1.0)
    }

    private var percentageText: String {
        let percent = Int((Double(entry.eatenKcal) / Double(entry.goalKcal)) * 100)
        return "\(percent)%"
    }

    private let progressColor = Color(hex: "0E8C8C")

    var body: some View {
        ZStack {
            // 1. Fortschrittskreis
            ZStack {
                Circle()
                    .trim(from: 0.13, to: 0.87)
                    .stroke(
                        Color.primary.opacity(renderingMode == .accented ? 0.2 : 0.12),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))

                Circle()
                    .trim(from: 0.13, to: 0.13 + (0.74 * progress))
                    .stroke(
                        progressColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .widgetAccentable()
            }
            .padding(4)

            // 2. Textblock
            VStack(spacing: 1) {
                Spacer()

                Text(percentageText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)

                Text("\(entry.eatenKcal)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, 8)

                Text(WidgetLocalization.text("widget.kcal_eaten"))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .offset(y: 4)
        }
        // Saubere ViewBuilder-Syntax für den Hintergrund:
        .containerBackground(for: .widget) {
            if colorScheme == .dark {
                Color(hex: "1C1C1E")
            } else {
                Color.white
            }
        }
    }
}
// MARK: - Lock Screen Widget View
struct LockScreenCircularView: View {
    var entry: CalorieWidgetEntry

    private var progress: Double {
        min(max(Double(entry.eatenKcal) / Double(entry.goalKcal), 0.0), 1.0)
    }

    var body: some View {
        Gauge(value: progress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(entry.eatenKcal)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - Widget Configuration
struct CalorieWidget: Widget {
    let kind: String = "CalorieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieWidgetProvider()) { entry in
            CalorieWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(WidgetLocalization.text("widget.display_name"))
        .description(WidgetLocalization.text("widget.description"))
        // Ergänze .systemMedium in der Liste:
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
