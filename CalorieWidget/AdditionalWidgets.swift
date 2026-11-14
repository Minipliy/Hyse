import WidgetKit
import SwiftUI
import AppIntents

private let widgetAccent = Color(red: 0.055, green: 0.549, blue: 0.549)

struct RemainingCaloriesWidget: Widget {
    let kind = "RemainingCaloriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieWidgetProvider()) { entry in
            RemainingCaloriesWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetLocalization.text("widget.remaining.name"))
        .description(WidgetLocalization.text("widget.remaining.description"))
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct RemainingCaloriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalorieWidgetEntry

    private var remaining: Int { entry.goalKcal - entry.eatenKcal }
    private var progress: Double { min(1, max(0, Double(entry.eatenKcal) / Double(max(1, entry.goalKcal)))) }

    var body: some View {
        Group {
            if family == .accessoryCircular {
                Gauge(value: progress) {
                    Image(systemName: "flame")
                } currentValueLabel: {
                    Text("\(abs(remaining))")
                        .font(.caption2.bold().monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .containerBackground(.clear, for: .widget)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(widgetAccent)
                    Spacer(minLength: 0)
                    Text("\(abs(remaining))")
                        .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(WidgetLocalization.text(remaining < 0 ? "widget.remaining.over" : "widget.remaining.left"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .tint(widgetAccent)
                }
                .padding(14)
                .containerBackground(for: .widget) { Color(.systemBackground) }
            }
        }
        .widgetURL(URL(string: "hyseapp://food"))
    }
}

struct MacroGoalsWidget: Widget {
    let kind = "MacroGoalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieWidgetProvider()) { entry in
            MacroGoalsWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetLocalization.text("widget.macros.name"))
        .description(WidgetLocalization.text("widget.macros.description"))
        .supportedFamilies([.systemMedium])
    }
}

private struct MacroGoalsWidgetView: View {
    let entry: CalorieWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(WidgetLocalization.text("widget.macros.name"))
                .font(.subheadline.weight(.semibold))
            macroRow("widget.macros.protein", value: entry.proteinGrams, goal: entry.proteinGoalGrams)
            macroRow("widget.macros.carbs", value: entry.carbsGrams, goal: entry.carbsGoalGrams)
            macroRow("widget.macros.fat", value: entry.fatGrams, goal: entry.fatGoalGrams)
        }
        .padding(12)
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "hyseapp://food"))
    }

    private func macroRow(_ titleKey: String, value: Int, goal: Int) -> some View {
        HStack(spacing: 9) {
            Text(WidgetLocalization.text(titleKey))
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
            ProgressView(value: min(1, Double(value) / Double(max(1, goal))))
                .tint(widgetAccent)
            Text(entry.macroGoalsAvailable ? "\(value)/\(goal) g" : "\(value) g")
                .monospacedDigit()
                .frame(minWidth: 78, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.caption)
    }
}

struct WaterProgressWidget: Widget {
    let kind = "WaterProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieWidgetProvider()) { entry in
            WaterProgressWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetLocalization.text("widget.water.name"))
        .description(WidgetLocalization.text("widget.water.description"))
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct WaterProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalorieWidgetEntry

    private var progress: Double {
        min(1, Double(entry.waterMilliliters) / Double(max(1, entry.waterGoalMilliliters)))
    }

    var body: some View {
        Group {
            if family == .accessoryCircular {
                Gauge(value: progress) {
                    Image(systemName: "drop.fill")
                } currentValueLabel: {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption2.bold().monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .containerBackground(.clear, for: .widget)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Label(WidgetLocalization.text("widget.water"), systemImage: "drop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(widgetAccent)
                    Text("\(entry.waterMilliliters) / \(entry.waterGoalMilliliters) ml")
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    ProgressView(value: progress)
                        .tint(widgetAccent)
                    Button(intent: WidgetLogWaterIntent()) {
                        Label(WidgetLocalization.text("widget.add_water"), systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(widgetAccent)
                    .font(.caption.weight(.semibold))
                }
                .padding(12)
                .containerBackground(for: .widget) { Color(.systemBackground) }
            }
        }
    }
}

struct TrainingWeekWidget: Widget {
    let kind = "TrainingWeekWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieWidgetProvider()) { entry in
            TrainingWeekWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetLocalization.text("widget.training_week.name"))
        .description(WidgetLocalization.text("widget.training_week.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TrainingWeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalorieWidgetEntry

    private var hoursText: String {
        let hours = entry.workoutMinutesThisWeek / 60
        let minutes = entry.workoutMinutesThisWeek % 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(WidgetLocalization.text("widget.training_week.name"), systemImage: "figure.strengthtraining.traditional")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if family == .systemSmall {
                Spacer(minLength: 0)
                Text("\(entry.workoutsThisWeek)")
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                Text(WidgetLocalization.text("widget.training_week.workouts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(hoursText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(widgetAccent)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(entry.workoutsThisWeek)")
                            .font(.title.bold().monospacedDigit())
                        Text(WidgetLocalization.text("widget.training_week.workouts"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hoursText)
                            .font(.title3.bold().monospacedDigit())
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                        Text(WidgetLocalization.text("widget.training_week.duration"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    ForEach(0..<7, id: \.self) { day in
                        Circle()
                            .fill(entry.workoutDailyCounts.indices.contains(day) && entry.workoutDailyCounts[day] > 0 ? widgetAccent : Color.secondary.opacity(0.22))
                            .frame(maxWidth: .infinity)
                            .frame(height: 8)
                    }
                }
                .accessibilityLabel(WidgetLocalization.text("widget.training_week.days"))
            }
        }
        .padding(12)
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "hyseapp://training"))
    }
}
