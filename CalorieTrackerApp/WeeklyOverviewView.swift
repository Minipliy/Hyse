import SwiftUI

private func weeklyDecimal(_ value: Double, locale: Locale) -> String {
    String(Int(value.rounded()))
}

private struct WeeklyHomeDay: Identifiable {
    let date: Date
    let calories: Double
    let hasFoodLog: Bool
    let isFuture: Bool
    var id: Date { date }
}

private struct WeeklyHomeSummary {
    let days: [WeeklyHomeDay]
    let loggedDays: Int
    let elapsedDays: Int
    let averageCalories: Double?
    let workouts: Int
    let start: Date
    let end: Date
}

struct WeeklyOverviewHomeCard: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var trainingStore: TrainingStore
    let selectedDate: Date

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    private func summary() -> WeeklyHomeSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let referenceDay = min(calendar.startOfDay(for: selectedDate), today)
        let start = calendar.dateInterval(of: .weekOfYear, for: referenceDay)?.start ?? referenceDay
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let days = (0..<7).compactMap { offset -> WeeklyHomeDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let totals = weeklyNutritionTotals(for: date, store: calorieStore)
            return WeeklyHomeDay(
                date: date,
                calories: totals.calories,
                hasFoodLog: totals.entries > 0,
                isFuture: date > today
            )
        }
        let workouts = trainingStore.completedWorkouts.filter {
            let completed = $0.completedAt ?? $0.startedAt
            return completed >= start && completed < end && completed < (calendar.date(byAdding: .day, value: 1, to: today) ?? end)
        }.count
        let elapsedDays = days.filter { $0.date <= today }
        let loggedDays = elapsedDays.filter(\.hasFoodLog)
        return WeeklyHomeSummary(
            days: days,
            loggedDays: loggedDays.count,
            elapsedDays: elapsedDays.count,
            averageCalories: loggedDays.isEmpty ? nil : loggedDays.reduce(0) { $0 + $1.calories } / Double(loggedDays.count),
            workouts: workouts,
            start: start,
            end: calendar.date(byAdding: .day, value: 6, to: start) ?? start
        )
    }

    var body: some View {
        let week = summary()
        let chartMaximum = max(1, week.days.map(\.calories).max() ?? 0)
        return HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(spacing: HyseSpacing.medium) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HyseColor.accent)
                        .frame(width: 42, height: 42)
                        .background(HyseColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("weekly.overview.title")).font(.headline)
                        Text("\(week.start.formatted(.dateTime.day().month(.abbreviated).locale(language.locale))) – \(week.end.formatted(.dateTime.day().month(.abbreviated).locale(language.locale)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Label(homeMotivation(for: week), systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HyseSpacing.medium)
                    .background(HyseColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: HyseRadius.small))

                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(week.days) { day in
                        VStack(spacing: 5) {
                            GeometryReader { geometry in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(HyseColor.accent.opacity(0.08))
                                    if day.hasFoodLog {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(HyseColor.accent.opacity(day.isFuture ? 0.35 : 1))
                                            .frame(height: max(4, geometry.size.height * CGFloat(day.calories / chartMaximum)))
                                    }
                                }
                            }
                            .frame(height: 68)
                            Text(day.date.formatted(.dateTime.weekday(.narrow).locale(language.locale)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).locale(language.locale)))
                        .accessibilityValue(day.hasFoodLog
                            ? (day.isFuture
                                ? t("weekly.overview.planned_value", weeklyDecimal(day.calories, locale: language.locale))
                                : t("weekly.overview.chart_accessibility_no_goal", weeklyDecimal(day.calories, locale: language.locale)))
                            : t("weekly.overview.no_food_log"))
                    }
                }

                HStack(alignment: .top, spacing: HyseSpacing.small) {
                    metric("\(week.loggedDays)/\(week.elapsedDays)", t("weekly.overview.logged_days"))
                    metric(week.averageCalories.map { "\(weeklyDecimal($0, locale: language.locale)) kcal" } ?? "–", t("weekly.overview.average_calories"))
                    metric("\(week.workouts)", t("weekly.overview.workouts"))
                }
                if week.loggedDays == 0 {
                    Text(t("weekly.overview.no_food_log"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.subheadline.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func homeMotivation(for week: WeeklyHomeSummary) -> String {
        if week.workouts > 0 { return t("weekly.overview.motivation_workouts", week.workouts) }
        if week.loggedDays > 0 { return t("weekly.overview.motivation_logged") }
        return t("weekly.overview.motivation_start")
    }
}

private struct WeeklyOverviewDay: Identifiable {
    let date: Date
    let calories: Double
    let protein: Double
    let calorieGoal: Double
    let proteinGoal: Double
    let workouts: Int
    let hasFoodLog: Bool
    let isFuture: Bool
    var id: Date { date }
    var proteinGoalReached: Bool { hasFoodLog && !isFuture && proteinGoal > 0 && protein >= proteinGoal }
}

private struct WeeklyNutritionTotals {
    var calories = 0.0
    var protein = 0.0
    var entries = 0
}

// Use the same local-day selection as the nutrition diary. In particular,
// entries near midnight must appear on the same day in both screens.
private func weeklyNutritionTotals(for date: Date, store: CalorieStore) -> WeeklyNutritionTotals {
    let entries = store.entries(for: date)
    return WeeklyNutritionTotals(
        calories: entries.reduce(0) { $0 + $1.kcal },
        protein: entries.reduce(0) { $0 + $1.protein },
        entries: entries.count
    )
}

private struct WeeklyOverviewSnapshot {
    let days: [WeeklyOverviewDay]
    let loggedDays: [WeeklyOverviewDay]
    let elapsedDays: Int
    let workoutCount: Int
    let averageCalories: Double
    let averageProtein: Double
    let proteinGoalDays: Int
    let proteinGoalEligibleDays: Int
    let calorieGoalDays: Int
    let calorieGoalEligibleDays: Int
    let chartMaximum: Double
    let previousWeekAverageCalories: Double?
    let weightChange: Double?
}

struct WeeklyOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var trainingStore: TrainingStore
    @ObservedObject var settings: UserSettingsStore
    @ObservedObject var health: HealthKitManager
    @State private var weekStart: Date
    @State private var goalsExpanded = false
    @State private var selectedChartDay: Date?
    private let selectedDate: Date
    private let onOpenDay: (Date) -> Void

    init(calorieStore: CalorieStore, trainingStore: TrainingStore, settings: UserSettingsStore, health: HealthKitManager, selectedDate: Date, onOpenDay: @escaping (Date) -> Void) {
        self.calorieStore = calorieStore
        self.trainingStore = trainingStore
        self.settings = settings
        self.health = health
        self.selectedDate = selectedDate
        self.onOpenDay = onOpenDay
        let calendar = Calendar.current
        let referenceDay = min(calendar.startOfDay(for: selectedDate), calendar.startOfDay(for: Date()))
        _weekStart = State(initialValue: calendar.dateInterval(of: .weekOfYear, for: referenceDay)?.start ?? referenceDay)
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private func makeSnapshot() -> WeeklyOverviewSnapshot {
        let calendar = Calendar.current
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
        let today = calendar.startOfDay(for: Date())
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? weekEnd
        var workoutsByDay: [Date: Int] = [:]
        for workout in trainingStore.completedWorkouts {
            let completed = workout.completedAt ?? workout.startedAt
            guard completed >= weekStart && completed < weekEnd && completed < endOfToday else { continue }
            workoutsByDay[calendar.startOfDay(for: completed), default: 0] += 1
        }

        let days: [WeeklyOverviewDay] = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let totals = weeklyNutritionTotals(for: date, store: calorieStore)
            let allowance = calorieStore.calorieAllowance(for: date) ?? 0
            return WeeklyOverviewDay(
                date: date,
                calories: totals.calories,
                protein: totals.protein,
                calorieGoal: allowance,
                proteinGoal: settings.targetProteinGrams(availableCalories: allowance),
                workouts: workoutsByDay[date, default: 0],
                hasFoodLog: totals.entries > 0,
                isFuture: date > today
            )
        }
        let loggedDays = days.filter { $0.date <= today && $0.hasFoodLog }
        let previousTotals = (0..<7).compactMap { offset -> WeeklyNutritionTotals? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: previousStart) else { return nil }
            let totals = weeklyNutritionTotals(for: date, store: calorieStore)
            return totals.entries > 0 ? totals : nil
        }
        let previousAverage = previousTotals.count >= 3 && loggedDays.count >= 3
            ? previousTotals.reduce(0) { $0 + $1.calories } / Double(previousTotals.count)
            : nil
        return WeeklyOverviewSnapshot(
            days: days,
            loggedDays: loggedDays,
            elapsedDays: days.filter { $0.date <= today }.count,
            workoutCount: days.reduce(0) { $0 + $1.workouts },
            averageCalories: loggedDays.isEmpty ? 0 : loggedDays.reduce(0) { $0 + $1.calories } / Double(loggedDays.count),
            averageProtein: loggedDays.isEmpty ? 0 : loggedDays.reduce(0) { $0 + $1.protein } / Double(loggedDays.count),
            proteinGoalDays: loggedDays.filter(\.proteinGoalReached).count,
            proteinGoalEligibleDays: loggedDays.filter { $0.proteinGoal > 0 }.count,
            calorieGoalDays: loggedDays.filter { $0.calorieGoal > 0 && $0.calories <= $0.calorieGoal }.count,
            calorieGoalEligibleDays: loggedDays.filter { $0.calorieGoal > 0 }.count,
            chartMaximum: max(1, days.map { max($0.calories, $0.calorieGoal) }.max() ?? 1),
            previousWeekAverageCalories: previousAverage,
            weightChange: weightChange(before: min(weekEnd, endOfToday))
        )
    }
    private func weightChange(before end: Date) -> Double? {
        var measurementsByID: [UUID: BodyMeasurement] = [:]
        for value in health.bodyWeights + trainingStore.bodyMeasurements { measurementsByID[value.id] = value }
        var first: (Date, Double)?
        var last: (Date, Double)?
        for value in measurementsByID.values {
            guard value.date >= weekStart, value.date < end, let weight = value.weightKilograms else { continue }
            if first.map({ value.date < $0.0 }) ?? true { first = (value.date, weight) }
            if last.map({ value.date > $0.0 }) ?? true { last = (value.date, weight) }
        }
        guard let first, let last, first.0 != last.0 else { return nil }
        return last.1 - first.1
    }
    private var canGoForward: Bool {
        let currentStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return weekStart < currentStart
    }

    var body: some View {
        let snapshot = makeSnapshot()
        return ScrollView {
            VStack(alignment: .leading, spacing: HyseSpacing.section) {
                weekPicker
                HyseCard(accent: HyseColor.accent) {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        HStack(alignment: .top, spacing: HyseSpacing.medium) {
                            VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                Text(t("weekly.overview.motivation"))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text(motivationText(for: snapshot))
                                    .font(.title2.weight(.bold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: motivationIcon(for: snapshot))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(HyseColor.accent)
                                .frame(width: 52, height: 52)
                                .background(HyseColor.accent.opacity(0.12), in: Circle())
                                .accessibilityHidden(true)
                        }
                        if let nextStepText = nextStepText(for: snapshot) {
                            Divider()
                            Text(nextStepText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if snapshot.days.contains(where: \.hasFoodLog) {
                    calorieChart(days: snapshot.days, chartMaximum: snapshot.chartMaximum)
                }
                HyseCard(accent: HyseColor.accent) {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        Text(t("weekly.overview.summary")).font(.headline)
                        HStack {
                            metric(t("weekly.overview.logged_days"), "\(snapshot.loggedDays.count)/\(snapshot.elapsedDays)", "fork.knife")
                            metric(t("weekly.overview.workouts"), "\(snapshot.workoutCount)", "figure.strengthtraining.traditional")
                        }
                        if !snapshot.loggedDays.isEmpty {
                            HStack {
                                metric(t("weekly.overview.average_calories"), "\(weeklyDecimal(snapshot.averageCalories, locale: language.locale)) kcal", "flame")
                                metric(t("weekly.overview.average_protein"), "\(weeklyDecimal(snapshot.averageProtein, locale: language.locale)) g", "circle.grid.2x2")
                            }
                            Text(t("weekly.overview.logged_days_note"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let weightChange = snapshot.weightChange {
                            Text(t("weekly.overview.weight_change", settings.trainingWeightUnit.display(weightChange).formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))), settings.trainingWeightUnit.rawValue))
                                .font(.subheadline)
                        }
                        if let previousWeekAverageCalories = snapshot.previousWeekAverageCalories {
                            let difference = snapshot.averageCalories - previousWeekAverageCalories
                            Text(t("weekly.overview.previous_week_delta", weeklyDecimal(difference, locale: language.locale)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HyseCard {
                    DisclosureGroup(t("weekly.overview.insight"), isExpanded: $goalsExpanded) {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            if !snapshot.loggedDays.isEmpty {
                                HStack(spacing: HyseSpacing.medium) {
                                    if snapshot.proteinGoalEligibleDays > 0 {
                                        metric(t("weekly.overview.protein_goal_days"),
                                               "\(snapshot.proteinGoalDays)/\(snapshot.proteinGoalEligibleDays)", "circle.grid.2x2")
                                    }
                                    if snapshot.calorieGoalEligibleDays > 0 {
                                        metric(t("weekly.overview.calorie_goal_days"),
                                               "\(snapshot.calorieGoalDays)/\(snapshot.calorieGoalEligibleDays)", "flame")
                                    }
                                }
                            }
                            Text(insightText(for: snapshot))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, HyseSpacing.small)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                HyseCard {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        Text(t("weekly.overview.daily")).font(.headline)
                        ForEach(snapshot.days) { day in
                            HStack {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().locale(language.locale)))
                                    .frame(width: 62, alignment: .leading)
                                if day.hasFoodLog {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t(day.isFuture ? "weekly.overview.planned_value" : "weekly.overview.eaten_value", weeklyDecimal(day.calories, locale: language.locale)))
                                            .font(.subheadline)
                                        if day.calorieGoal > 0 {
                                            Text(t("weekly.overview.goal_value", weeklyDecimal(day.calorieGoal, locale: language.locale)))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack(spacing: 4) {
                                            Text(day.proteinGoal > 0
                                                 ? t("weekly.overview.protein_daily", weeklyDecimal(day.protein, locale: language.locale), weeklyDecimal(day.proteinGoal, locale: language.locale))
                                                 : t("weekly.overview.protein_without_goal", weeklyDecimal(day.protein, locale: language.locale)))
                                            if day.proteinGoalReached {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(HyseColor.accent)
                                                    .accessibilityLabel(t("weekly.overview.protein_reached"))
                                            }
                                        }
                                        .font(.caption).foregroundStyle(.secondary)
                                    }
                                } else if day.date > Calendar.current.startOfDay(for: Date()) {
                                    Text(t("weekly.overview.upcoming"))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                } else {
                                    Text(t("weekly.overview.no_food_log"))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if day.workouts > 0 {
                                    Label("\(day.workouts)", systemImage: "figure.strengthtraining.traditional")
                                        .font(.caption).foregroundStyle(HyseColor.accent)
                                }
                            }
                            Button {
                                onOpenDay(day.date)
                                dismiss()
                            } label: {
                                Label(t("weekly.overview.open_day"), systemImage: "calendar")
                            }
                            .accessibilityLabel(t("weekly.overview.open_day") + ", " + day.date.formatted(.dateTime.weekday(.wide).day().month().locale(language.locale)))
                            if day.id != snapshot.days.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(HyseSpacing.page)
        }
        .background(HyseBackdrop())
        .navigationTitle(t("weekly.overview.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedDate) { _, date in
            let calendar = Calendar.current
            let referenceDay = min(calendar.startOfDay(for: date), calendar.startOfDay(for: Date()))
            weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDay)?.start ?? referenceDay
            selectedChartDay = nil
        }
    }

    private var weekPicker: some View {
        HStack {
            Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(t("weekly.overview.previous"))
            Spacer()
            Text(weekLabel).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                .disabled(!canGoForward)
                .accessibilityLabel(t("weekly.overview.next"))
        }
        .buttonStyle(HyseIconButtonStyle())
    }

    private var weekLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.day().month(.abbreviated).locale(language.locale))) – \(end.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale)))"
    }
    private func calorieChart(days: [WeeklyOverviewDay], chartMaximum: Double) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        let selectedDay = days.first { $0.date == selectedChartDay }
            ?? days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            ?? days.last { $0.date <= today }
        return HyseCard {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                Text(t("weekly.overview.chart_title")).font(.headline)
                if let selectedDay {
                    HStack(alignment: .firstTextBaseline, spacing: HyseSpacing.small) {
                        Text(selectedDay.date.formatted(.dateTime.weekday(.wide).day().month().locale(language.locale)))
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(selectedDay.hasFoodLog
                                 ? t(selectedDay.isFuture ? "weekly.overview.planned_value" : "weekly.overview.eaten_value", weeklyDecimal(selectedDay.calories, locale: language.locale))
                                 : t("weekly.overview.no_food_log"))
                                .font(.subheadline.weight(.semibold))
                            if selectedDay.calorieGoal > 0 {
                                Text(t("weekly.overview.goal_value", weeklyDecimal(selectedDay.calorieGoal, locale: language.locale)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(HyseSpacing.medium)
                    .background(HyseColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: HyseRadius.small))
                }
                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    HStack(spacing: HyseSpacing.medium) {
                        Label(t("weekly.overview.chart_within_goal"), systemImage: "square.fill")
                            .foregroundStyle(HyseColor.accent)
                        Label(t("weekly.overview.chart_above_goal"), systemImage: "square.fill")
                            .foregroundStyle(HyseColor.warning)
                    }
                    Label(t("weekly.overview.chart_goal"), systemImage: "minus")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(days) { day in
                        Button { selectedChartDay = day.date } label: {
                            VStack(spacing: 6) {
                                GeometryReader { geometry in
                                    let height = geometry.size.height
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(HyseColor.accent.opacity(0.08))
                                        if day.hasFoodLog {
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill((day.calorieGoal > 0 && day.calories > day.calorieGoal ? HyseColor.warning : HyseColor.accent).opacity(day.isFuture ? 0.35 : 1))
                                                .frame(height: max(3, height * CGFloat(day.calories / chartMaximum)))
                                        }
                                        if day.calorieGoal > 0 {
                                            Capsule()
                                                .fill(.primary.opacity(0.65))
                                                .frame(height: 2)
                                                .offset(y: -min(height - 2, height * CGFloat(day.calorieGoal / chartMaximum)))
                                        }
                                    }
                                    .overlay {
                                        if selectedDay?.date == day.date {
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(HyseColor.accent, lineWidth: 2)
                                        }
                                    }
                                }
                                .frame(height: 86)
                                Text(day.date.formatted(.dateTime.weekday(.narrow).locale(language.locale)))
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month().locale(language.locale)))
                        .accessibilityValue(day.hasFoodLog
                            ? (day.isFuture
                                ? t("weekly.overview.planned_value", weeklyDecimal(day.calories, locale: language.locale))
                                : day.calorieGoal > 0
                                ? t(day.calories > day.calorieGoal
                                    ? "weekly.overview.chart_accessibility_above_goal"
                                    : "weekly.overview.chart_accessibility_within_goal",
                                    weeklyDecimal(day.calories, locale: language.locale),
                                    weeklyDecimal(day.calorieGoal, locale: language.locale))
                                : t("weekly.overview.chart_accessibility_no_goal", weeklyDecimal(day.calories, locale: language.locale)))
                            : t("weekly.overview.no_food_log"))
                    }
                }
            }
        }
    }
    private func insightText(for snapshot: WeeklyOverviewSnapshot) -> String {
        if snapshot.loggedDays.isEmpty { return t("weekly.overview.insight_empty") }
        if snapshot.loggedDays.count < 3 { return t("weekly.overview.insight_sparse", snapshot.loggedDays.count) }
        if snapshot.proteinGoalEligibleDays == 0 && snapshot.calorieGoalEligibleDays == 0 {
            return t("weekly.overview.insight_no_goals")
        }
        return t("weekly.overview.insight_summary")
    }
    private func motivationText(for snapshot: WeeklyOverviewSnapshot) -> String {
        if snapshot.proteinGoalDays > 0 {
            return t("weekly.overview.motivation_protein", snapshot.proteinGoalDays)
        }
        if snapshot.workoutCount > 0 {
            return t("weekly.overview.motivation_workouts", snapshot.workoutCount)
        }
        if !snapshot.loggedDays.isEmpty { return t("weekly.overview.motivation_logged") }
        return t("weekly.overview.motivation_start")
    }
    private func motivationIcon(for snapshot: WeeklyOverviewSnapshot) -> String {
        if snapshot.proteinGoalDays > 0 { return "checkmark.seal.fill" }
        if snapshot.workoutCount > 0 { return "figure.strengthtraining.traditional" }
        if !snapshot.loggedDays.isEmpty { return "fork.knife" }
        return "sparkles"
    }
    private func nextStepText(for snapshot: WeeklyOverviewSnapshot) -> String? {
        let today = Calendar.current.startOfDay(for: Date())
        let currentWeek = Calendar.current.dateInterval(of: .weekOfYear, for: today)?.start
        guard currentWeek == weekStart else { return nil }
        if let plannedDay = snapshot.days.first(where: {
            $0.date >= today && $0.workouts == 0 && !trainingStore.routines(plannedFor: $0.date).isEmpty
        }), let routine = trainingStore.routine(plannedFor: plannedDay.date) {
            return t("weekly.overview.next_workout", routine.name, plannedDay.date.formatted(.dateTime.weekday(.wide).locale(language.locale)))
        }
        if snapshot.loggedDays.count < 3 {
            return t("weekly.overview.next_log")
        }
        if snapshot.proteinGoalEligibleDays >= 2 && snapshot.proteinGoalDays * 2 < snapshot.proteinGoalEligibleDays {
            return t("weekly.overview.next_protein")
        }
        return t("weekly.overview.next_continue")
    }
    private func shiftWeek(_ amount: Int) {
        guard let next = Calendar.current.date(byAdding: .weekOfYear, value: amount, to: weekStart) else { return }
        weekStart = next
        selectedChartDay = nil
    }
    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
