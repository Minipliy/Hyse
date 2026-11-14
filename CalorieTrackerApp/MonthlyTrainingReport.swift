import Charts
import Combine
import CoreTransferable
import Foundation
import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

@MainActor
final class MonthlyTrainingReportNotificationManager {
    static let shared = MonthlyTrainingReportNotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let identifier = "hyse.training.monthly-report"

    private init() {}

    func setEnabled(_ enabled: Bool, language: AppLanguage) async -> Bool {
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return false
        }
        let settings = await center.notificationSettings()
        let allowed: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: allowed = true
        case .notDetermined: allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied: allowed = false
        @unknown default: allowed = false
        }
        if allowed { await schedule(language: language) }
        return allowed
    }

    func applyStoredPreference(_ enabled: Bool, language: AppLanguage) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard enabled else {
                self.center.removePendingNotificationRequests(withIdentifiers: [self.identifier])
                return
            }
            let settings = await self.center.notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            await self.schedule(language: language)
        }
    }

    private func schedule(language: AppLanguage) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = LanguageStore.localizedString("training.monthly_report.notification_title", language: language)
        content.body = LanguageStore.localizedString("training.monthly_report.notification_body", language: language)
        content.sound = .default
        content.userInfo = ["destination": "training-monthly-report"]
        var components = DateComponents()
        components.calendar = .current
        components.day = 1
        components.hour = 10
        try? await center.add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
        )
    }
}

private enum MonthlyReportMetric: String, CaseIterable, Identifiable {
    case workouts, duration, volume, sets
    var id: String { rawValue }
    var titleKey: String { "training.monthly_report.metric.\(rawValue)" }
}

private struct TrainingMonthSummary: Identifiable {
    let month: Date
    let workouts: Int
    let duration: TimeInterval
    let volume: Double
    let sets: Double
    let personalRecords: Int
    var id: Date { month }

    func value(for metric: MonthlyReportMetric, weightUnit: TrainingWeightUnit) -> Double {
        switch metric {
        case .workouts: Double(workouts)
        case .duration: duration / 3_600
        case .volume: weightUnit.display(volume)
        case .sets: sets
        }
    }
}

@MainActor
private final class MonthlyTrainingReportCache: ObservableObject {
    @Published private(set) var summaries: [TrainingMonthSummary] = []
    private(set) var summariesByMonth: [Date: TrainingMonthSummary] = [:]
    private(set) var workoutsByMonth: [Date: [WorkoutLog]] = [:]
    private(set) var recordsByMonth: [Date: [MonthlyRecordItem]] = [:]

    func rebuild(workouts: [WorkoutLog], endingAt end: Date, calendar: Calendar, halveUnilateral: Bool) {
        var grouped: [Date: [WorkoutLog]] = [:]
        for workout in workouts {
            let date = workout.completedAt ?? workout.startedAt
            let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
            grouped[start, default: []].append(workout)
        }

        let visibleMonths = (0..<12).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: end)
                .flatMap { calendar.dateInterval(of: .month, for: $0)?.start }
        }
        let previousBoundary = calendar.date(byAdding: .month, value: -12, to: end)
            .flatMap { calendar.dateInterval(of: .month, for: $0)?.start }
        let cachedMonths = previousBoundary.map { [$0] + visibleMonths } ?? visibleMonths
        let records = MonthlyPersonalRecordHistory.recordsByMonth(workouts: workouts, calendar: calendar)

        var summaryLookup: [Date: TrainingMonthSummary] = [:]
        for month in cachedMonths {
            let monthWorkouts = grouped[month] ?? []
            summaryLookup[month] = TrainingMonthSummary(
                month: month,
                workouts: monthWorkouts.count,
                duration: monthWorkouts.reduce(0) { $0 + $1.duration },
                volume: monthWorkouts.reduce(0) { $0 + $1.totalVolume },
                sets: TrainingSetStatistics.count(monthWorkouts, halveUnilateral: halveUnilateral),
                personalRecords: records[month]?.count ?? 0
            )
        }

        workoutsByMonth = grouped
        recordsByMonth = records
        summariesByMonth = summaryLookup
        summaries = visibleMonths.compactMap { summaryLookup[$0] }
    }
}

private struct MonthlyExerciseFrequency: Identifiable {
    let exercise: WorkoutExerciseLog
    let count: Int
    var id: UUID { exercise.exerciseID }
}

private struct MonthlyReportShareImage: Transferable {
    let pngData: Data
    let message: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            image.pngData
        }
    }
}

private struct MonthlyReportShareMuscle: Identifiable {
    let name: String
    let value: String
    let fraction: Double
    var id: String { name }
}

struct TrainingMonthlyReportView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    let month: Date
    @State private var metric = MonthlyReportMetric.workouts
    @State private var selectedMonth: Date?
    @State private var showsAllRecords = false
    @State private var renderedShareImage: MonthlyReportShareImage?
    @State private var isPreparingShareImage = false
    @State private var isShareSheetPresented = false
    @StateObject private var reportCache = MonthlyTrainingReportCache()
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false

    private var calendar: Calendar { .autoupdatingCurrent }
    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    private var reportMonth: Date { monthStart(selectedMonth ?? month) }
    private var summaries: [TrainingMonthSummary] {
        reportCache.summaries.isEmpty
            ? monthlySummaries(endingAt: latestAvailableMonth, count: 12)
            : reportCache.summaries
    }
    private var current: TrainingMonthSummary {
        reportCache.summariesByMonth[reportMonth] ?? summary(for: reportMonth)
    }
    private var previous: TrainingMonthSummary {
        let month = calendar.date(byAdding: .month, value: -1, to: reportMonth) ?? reportMonth
        return reportCache.summariesByMonth[monthStart(month)] ?? summary(for: month)
    }
    private var monthWorkouts: [WorkoutLog] {
        reportCache.workoutsByMonth[reportMonth] ?? workouts(in: reportMonth)
    }
    private var previousMonthWorkouts: [WorkoutLog] {
        let month = calendar.date(byAdding: .month, value: -1, to: reportMonth) ?? reportMonth
        return reportCache.workoutsByMonth[monthStart(month)] ?? workouts(in: month)
    }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                    reportHeader
                    chartSection
                    Divider()
                    Text(t("training.monthly_report.summary"))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HyseSpacing.medium) {
                        summaryCard(title: t("training.monthly_report.metric.workouts"), value: "\(current.workouts)", delta: Double(current.workouts - previous.workouts), deltaText: signed(current.workouts - previous.workouts))
                        summaryCard(title: t("training.monthly_report.metric.duration"), value: durationText(current.duration), delta: current.duration - previous.duration, deltaText: signedDuration(current.duration - previous.duration))
                        summaryCard(title: t("training.monthly_report.metric.volume"), value: compactWeight(current.volume), delta: current.volume - previous.volume, deltaText: signedWeight(current.volume - previous.volume))
                        summaryCard(title: t("training.monthly_report.metric.sets"), value: setCount(current.sets), delta: current.sets - previous.sets, deltaText: signedSets(current.sets - previous.sets))
                    }
                    Divider()
                    personalRecordsSection
                    Divider()
                    trainingDiarySection
                    Divider()
                    muscleComparisonSection
                    Divider()
                    primaryMusclesSection
                    Divider()
                    topExercisesSection
                    Divider()
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        Text(t("training.monthly_report.congratulations"))
                            .font(.title2.bold())
                        Text(t("training.monthly_report.congratulations_message"))
                            .foregroundStyle(.secondary)
                    }
                    Button(action: prepareAndPresentShareImage) {
                        HStack(spacing: HyseSpacing.small) {
                            if isPreparingShareImage {
                                ProgressView()
                            }
                            Label(
                                t(isPreparingShareImage ? "training.monthly_report.preparing_share_image" : "training.monthly_report.share"),
                                systemImage: "photo.on.rectangle.angled"
                            )
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HyseSpacing.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HyseColor.accent)
                    .disabled(isPreparingShareImage)
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.vertical, HyseSpacing.medium)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(t("training.monthly_report.navigation_title", monthName))
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(store.$completedWorkouts) { workouts in
            reportCache.rebuild(workouts: workouts, endingAt: latestAvailableMonth, calendar: calendar, halveUnilateral: halveUnilateral)
        }
        .onChange(of: halveUnilateral) { _, value in
            reportCache.rebuild(workouts: store.completedWorkouts, endingAt: latestAvailableMonth, calendar: calendar, halveUnilateral: value)
        }
        .sheet(isPresented: $isShareSheetPresented, onDismiss: {
            renderedShareImage = nil
        }) {
            if let renderedShareImage {
                MonthlyReportShareSheet(item: renderedShareImage)
            }
        }
    }

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Text(reportMonth.formatted(.dateTime.month(.wide).year().locale(language.locale)))
                .font(.largeTitle.bold())
            HStack(alignment: .firstTextBaseline, spacing: HyseSpacing.small) {
                Text(metricValue(current, for: metric)).font(.title.bold()).monospacedDigit()
                deltaLabel(value: metricDelta, text: metricDeltaText)
            }
        }
    }

    private var chartSection: some View {
        VStack(spacing: HyseSpacing.medium) {
            Chart(summaries) { summary in
                BarMark(
                    x: .value("Month", summary.month, unit: .month),
                    y: .value("Value", summary.value(for: metric, weightUnit: weightUnit))
                )
                .foregroundStyle(calendar.isDate(summary.month, equalTo: reportMonth, toGranularity: .month) ? HyseColor.accent : Color.secondary.opacity(0.35))
                .cornerRadius(4)
                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                    if summary.value(for: metric, weightUnit: weightUnit) > 0,
                       calendar.isDate(summary.month, equalTo: reportMonth, toGranularity: .month) {
                        Text(metricValue(summary, for: metric))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.small))
                    }
                }
            }
            .frame(height: 220)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                guard let month = ChartBarSelection.date(
                                    at: value.location, proxy: proxy, geometry: geometry,
                                    bars: summaries.map { ($0.month, $0.value(for: metric, weightUnit: weightUnit)) },
                                    unit: .month
                                ) else { return }
                                selectMonth(month)
                            }
                        )
                }
            }
            .chartYAxisLabel(metricUnit, position: .topLeading)
            Picker(t("training.monthly_report.metric_picker"), selection: $metric) {
                ForEach(MonthlyReportMetric.allCases) { value in Text(metricTitle(value)).tag(value) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            let visibleRecords = displayedRecordItems
            Text(t("training.monthly_report.personal_records"))
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(spacing: HyseSpacing.medium) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(HyseColor.warning)
                Text(t("training.monthly_report.new_records", current.personalRecords))
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity)

            ForEach(visibleRecords) { item in
                NavigationLink { exerciseDestination(item.exercise) } label: {
                    HStack(spacing: HyseSpacing.large) {
                        ExerciseMovementVisual(exercise: exerciseVisual(item.exercise), height: 54)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exerciseName(item.exercise)).font(.headline).foregroundStyle(.primary)
                            Label(recordDescription(item), systemImage: "medal.fill")
                                .font(.subheadline)
                                .foregroundStyle(HyseColor.warning)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                if item.id != visibleRecords.last?.id { Divider() }
            }
            if recordItems.count > 4 {
                Button(showsAllRecords ? t("training.monthly_report.show_fewer_records") : t("training.monthly_report.show_all_records", recordItems.count)) {
                    showsAllRecords.toggle()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var trainingDiarySection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            Text(t("training.monthly_report.training_diary"))
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(spacing: HyseSpacing.small) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(HyseColor.streakFire)
                Text(t("training.monthly_report.week_streak", longestWeeklyStreak))
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity)
            monthCalendar
        }
    }

    private var monthCalendar: some View {
        VStack(spacing: HyseSpacing.small) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: HyseSpacing.small) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(0..<(monthLeadingBlankCount + numberOfDaysInMonth), id: \.self) { index in
                    if index < monthLeadingBlankCount {
                        Color.clear.frame(height: 38)
                    } else {
                        let day = index - monthLeadingBlankCount + 1
                        let trained = trainedDayNumbers.contains(day)
                        Text("\(day)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(trained ? .white : .primary)
                            .frame(width: 38, height: 38)
                            .background(trained ? HyseColor.accent : Color.clear, in: Circle())
                    }
                }
            }
        }
    }

    private var muscleComparisonSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            Text(t("training.monthly_report.muscle_distribution"))
                .font(.title2)
                .foregroundStyle(.secondary)
            MonthlyMuscleRadarChart(
                current: broadMuscleValues(for: monthWorkouts),
                previous: broadMuscleValues(for: previousMonthWorkouts),
                labels: [
                    t("training.monthly_report.muscle.back"),
                    t("training.monthly_report.muscle.chest"),
                    t("training.monthly_report.muscle.core"),
                    t("training.monthly_report.muscle.shoulders"),
                    t("training.monthly_report.muscle.arms"),
                    t("training.monthly_report.muscle.legs")
                ]
            )
            .frame(height: 330)
            HStack(spacing: HyseSpacing.large) {
                Label(previousMonthName, systemImage: "circle.fill").foregroundStyle(.secondary)
                Label(monthName, systemImage: "circle.fill").foregroundStyle(HyseColor.accent)
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
    }

    private var primaryMusclesSection: some View {
        let muscles = Array(weightedMuscleCounts(for: monthWorkouts).sorted { $0.value > $1.value }.prefix(6))
        let maximum = max(1, muscles.map(\.value).max() ?? 1)
        return VStack(alignment: .leading, spacing: HyseSpacing.large) {
            Text(t("training.monthly_report.primary_muscles"))
                .font(.title2)
                .foregroundStyle(.secondary)
            HStack {
                Text(t("training.monthly_report.muscle")); Spacer(); Text(t("training.monthly_report.sets"))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            ForEach(muscles, id: \.key) { muscle, count in
                HStack(spacing: HyseSpacing.medium) {
                    Text(t("training.muscle.\(muscle)"))
                        .frame(width: 105, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    ProgressView(value: count, total: maximum)
                        .tint(HyseColor.accent)
                        .scaleEffect(x: 1, y: 2.2, anchor: .center)
                    Text(formatSetCount(count))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    private var topExercisesSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            Text(t("training.monthly_report.top_exercises"))
                .font(.title2)
                .foregroundStyle(.secondary)
            ForEach(Array(topExercises.prefix(5))) { item in
                NavigationLink { exerciseDestination(item.exercise) } label: {
                    HStack(spacing: HyseSpacing.large) {
                        ExerciseMovementVisual(exercise: exerciseVisual(item.exercise), height: 58)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exerciseName(item.exercise)).font(.headline).foregroundStyle(.primary)
                            Text(t("training.monthly_report.times", item.count)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                if item.id != topExercises.prefix(5).last?.id { Divider() }
            }
        }
    }

    private func summaryCard(title: String, value: String, delta: Double, deltaText: String) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Text(title).font(.subheadline)
            Text(value).font(.title2.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            deltaLabel(value: delta, text: deltaText)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(HyseSpacing.medium)
        .background(HyseColor.elevatedSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
    }

    private func deltaLabel(value: Double, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: value > 0 ? "arrow.up" : value < 0 ? "arrow.down" : "minus")
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(value > 0 ? HyseColor.success : value < 0 ? Color.red : Color.secondary)
    }

    private func summary(for month: Date, recordsByMonth: [Date: [MonthlyRecordItem]]? = nil) -> TrainingMonthSummary {
        let start = monthStart(month)
        let workouts = workouts(in: start)
        let records = recordsByMonth ?? MonthlyPersonalRecordHistory.recordsByMonth(workouts: store.completedWorkouts, calendar: calendar)
        return TrainingMonthSummary(
            month: start,
            workouts: workouts.count,
            duration: workouts.reduce(0) { $0 + $1.duration },
            volume: workouts.reduce(0) { $0 + $1.totalVolume },
            sets: TrainingSetStatistics.count(workouts, halveUnilateral: halveUnilateral),
            personalRecords: records[start]?.count ?? 0
        )
    }

    private func monthlySummaries(endingAt end: Date, count: Int) -> [TrainingMonthSummary] {
        let records = MonthlyPersonalRecordHistory.recordsByMonth(workouts: store.completedWorkouts, calendar: calendar)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: end).map { summary(for: $0, recordsByMonth: records) }
        }
    }

    private func workouts(in value: Date) -> [WorkoutLog] {
        let start = monthStart(value)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return store.completedWorkouts.filter {
            let date = $0.completedAt ?? $0.startedAt
            return date >= start && date < end
        }
    }

    private func monthStart(_ value: Date) -> Date {
        calendar.dateInterval(of: .month, for: value)?.start ?? value
    }

    private var latestAvailableMonth: Date {
        let previous = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return monthStart(previous)
    }

    private func selectMonth(_ value: Date) {
        let candidate = monthStart(value)
        guard summaries.contains(where: { calendar.isDate($0.month, equalTo: candidate, toGranularity: .month) }) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { selectedMonth = candidate }
    }

    private var numberOfDaysInMonth: Int {
        calendar.range(of: .day, in: .month, for: reportMonth)?.count ?? 30
    }

    private var monthLeadingBlankCount: Int {
        let weekday = calendar.component(.weekday, from: reportMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let split = max(0, min(symbols.count, calendar.firstWeekday - 1))
        return Array(symbols[split...]) + Array(symbols[..<split])
    }

    private var trainedDayNumbers: Set<Int> {
        Set(monthWorkouts.map { calendar.component(.day, from: $0.completedAt ?? $0.startedAt) })
    }

    private var longestWeeklyStreak: Int {
        let weeks = Set(monthWorkouts.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.completedAt ?? $0.startedAt)?.start }).sorted()
        guard !weeks.isEmpty else { return 0 }
        var longest = 1
        var currentRun = 1
        for index in 1..<weeks.count {
            let expected = calendar.date(byAdding: .weekOfYear, value: 1, to: weeks[index - 1])
            if expected.map({ calendar.isDate($0, inSameDayAs: weeks[index]) }) == true {
                currentRun += 1
                longest = max(longest, currentRun)
            } else {
                currentRun = 1
            }
        }
        return longest
    }

    private func weightedMuscleCounts(for workouts: [WorkoutLog]) -> [String: Double] {
        var result: [String: Double] = [:]
        for workout in workouts {
            for exercise in workout.exercises {
                let sets = TrainingSetStatistics.count(exercise, halveUnilateral: halveUnilateral)
                guard sets > 0 else { continue }
                let muscles = resolvedMuscles(for: exercise)
                for muscle in muscles.primary { result[muscle, default: 0] += sets }
                for muscle in muscles.secondary { result[muscle, default: 0] += sets * 0.5 }
            }
        }
        return result
    }

    private func resolvedMuscles(for log: WorkoutExerciseLog) -> (primary: [String], secondary: [String]) {
        if let corrected = TrainingExercise.repairedMuscleAssignment(
            exerciseID: log.exerciseID,
            englishName: log.exerciseNameSnapshot,
            germanName: log.exerciseGermanNameSnapshot,
            type: log.exerciseTypeSnapshot,
            equipment: log.equipmentSnapshot,
            primary: log.primaryMusclesSnapshot,
            secondary: log.secondaryMusclesSnapshot
        ) {
            return corrected
        }
        if !log.primaryMusclesSnapshot.isEmpty || !log.secondaryMusclesSnapshot.isEmpty {
            return (log.primaryMusclesSnapshot, log.secondaryMusclesSnapshot)
        }
        if let catalogExercise = store.exercises.first(where: { $0.id == log.exerciseID }) {
            return (catalogExercise.primaryMuscles, catalogExercise.secondaryMuscles)
        }
        let restored = TrainingExercise(
            id: log.exerciseID,
            nameKey: "hevy_import",
            englishName: log.exerciseNameSnapshot,
            germanName: log.exerciseGermanNameSnapshot,
            descriptionKey: "",
            techniqueKey: "",
            type: log.exerciseTypeSnapshot,
            equipment: log.equipmentSnapshot,
            primaryMuscles: [],
            secondaryMuscles: [],
            isCustom: true,
            isFavorite: false,
            updatedAt: .distantPast
        ).normalizedImportedCatalogEntry()
        if !restored.primaryMuscles.isEmpty || !restored.secondaryMuscles.isEmpty {
            return (restored.primaryMuscles, restored.secondaryMuscles)
        }

        let importedNames = [log.exerciseNameSnapshot, log.exerciseGermanNameSnapshot]
            .map(exerciseNameFingerprint)
            .filter { !$0.isEmpty }
        if let catalogExercise = store.exercises.first(where: { candidate in
            guard log.equipmentSnapshot == .other || candidate.equipment == log.equipmentSnapshot else { return false }
            let candidateNames = [candidate.englishName, candidate.germanName].map(exerciseNameFingerprint)
            return importedNames.contains { imported in
                candidateNames.contains { candidateName in
                    imported == candidateName || imported.isSubset(of: candidateName) || candidateName.isSubset(of: imported)
                }
            }
        }) {
            return (catalogExercise.primaryMuscles, catalogExercise.secondaryMuscles)
        }
        return ([], [])
    }

    private func exerciseNameFingerprint(_ value: String) -> Set<String> {
        let ignored = Set([
            "a", "am", "an", "at", "der", "dem", "die", "im", "in", "mit", "the", "von", "with",
            "barbell", "cable", "dumbbell", "kabel", "kabelzug", "kurzhantel", "langhantel", "machine", "maschine"
        ])
        return Set(
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !ignored.contains($0) }
                .map { word in word.count > 4 && word.hasSuffix("s") ? String(word.dropLast()) : word }
        )
    }

    private func broadMuscleValues(for workouts: [WorkoutLog]) -> [Double] {
        let counts = weightedMuscleCounts(for: workouts)
        let groups = [
            ["back", "upper_back", "lats"], ["chest"], ["abs", "core"],
            ["front_shoulders", "side_shoulders", "rear_shoulders", "shoulders"],
            ["biceps", "triceps", "forearms"],
            ["quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]
        ]
        return groups.map { group in group.reduce(0) { $0 + counts[$1, default: 0] } }
    }

    private var topExercises: [MonthlyExerciseFrequency] {
        var values: [UUID: (WorkoutExerciseLog, Int)] = [:]
        for workout in monthWorkouts {
            for exercise in workout.exercises where exercise.completedSetCount > 0 {
                let previous = values[exercise.exerciseID]
                values[exercise.exerciseID] = (previous?.0 ?? exercise, (previous?.1 ?? 0) + 1)
            }
        }
        return values.values
            .map { MonthlyExerciseFrequency(exercise: $0.0, count: $0.1) }
            .sorted { $0.count > $1.count }
    }

    private var recordItems: [MonthlyRecordItem] {
        if !reportCache.summariesByMonth.isEmpty {
            return reportCache.recordsByMonth[reportMonth] ?? []
        }
        return MonthlyPersonalRecordHistory.recordsByMonth(workouts: store.completedWorkouts, calendar: calendar)[reportMonth] ?? []
    }

    private var displayedRecordItems: [MonthlyRecordItem] {
        let newestFirst = Array(recordItems.reversed())
        return showsAllRecords ? newestFirst : Array(newestFirst.prefix(4))
    }

    private func recordDescription(_ item: MonthlyRecordItem) -> String {
        let title = t("training.pr.\(item.flag).title")
        let set = item.set
        switch item.flag {
        case "weight": return "\(title) · \(compactWeight(set.weightKilograms))"
        case "reps": return "\(title) · \(set.reps) \(t("training.reps"))"
        case "set_volume": return "\(title) · \(compactWeight(set.volume))"
        case "estimated_1rm": return "\(title) · \(compactWeight(set.estimatedOneRepMaximum))"
        default: return title
        }
    }

    private func exerciseName(_ exercise: WorkoutExerciseLog) -> String {
        language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty ? exercise.exerciseGermanNameSnapshot : exercise.exerciseNameSnapshot
    }

    private func exerciseVisual(_ log: WorkoutExerciseLog) -> TrainingExercise {
        store.exercises.first(where: { $0.id == log.exerciseID }) ?? TrainingExercise(
            id: log.exerciseID, nameKey: "custom", englishName: log.exerciseNameSnapshot,
            germanName: log.exerciseGermanNameSnapshot, descriptionKey: "", techniqueKey: "",
            type: log.exerciseTypeSnapshot, equipment: log.equipmentSnapshot,
            primaryMuscles: log.primaryMusclesSnapshot, secondaryMuscles: log.secondaryMusclesSnapshot,
            isCustom: true, isFavorite: false, updatedAt: Date()
        )
    }

    @ViewBuilder private func exerciseDestination(_ log: WorkoutExerciseLog) -> some View {
        if let exercise = store.exercises.first(where: { $0.id == log.exerciseID }) {
            ExerciseProgressView(exercise: exercise, store: store)
        } else {
            Text(exerciseName(log)).navigationTitle(exerciseName(log))
        }
    }

    private func formatSetCount(_ value: Double) -> String {
        TrainingSetStatistics.formatted(value, locale: language.locale)
    }

    private func metricTitle(_ value: MonthlyReportMetric) -> String {
        switch value {
        case .duration: "\(t(value.titleKey)) (h)"
        case .volume: "\(t(value.titleKey)) (\(weightUnit.rawValue))"
        default: t(value.titleKey)
        }
    }

    private var metricUnit: String {
        switch metric {
        case .duration: "h"
        case .volume: weightUnit.rawValue
        default: ""
        }
    }

    private func metricValue(_ summary: TrainingMonthSummary, for value: MonthlyReportMetric) -> String {
        switch value {
        case .workouts: "\(summary.workouts)"
        case .duration: durationText(summary.duration)
        case .volume: compactWeight(summary.volume)
        case .sets: setCount(summary.sets)
        }
    }

    private var metricDelta: Double {
        switch metric {
        case .workouts: Double(current.workouts - previous.workouts)
        case .duration: current.duration - previous.duration
        case .volume: current.volume - previous.volume
        case .sets: current.sets - previous.sets
        }
    }

    private var metricDeltaText: String {
        switch metric {
        case .workouts: signed(current.workouts - previous.workouts)
        case .duration: signedDuration(current.duration - previous.duration)
        case .volume: signedWeight(current.volume - previous.volume)
        case .sets: signedSets(current.sets - previous.sets)
        }
    }

    private var monthName: String { reportMonth.formatted(.dateTime.month(.wide).locale(language.locale)) }
    private var previousMonthName: String {
        (calendar.date(byAdding: .month, value: -1, to: reportMonth) ?? reportMonth)
            .formatted(.dateTime.month(.wide).year().locale(language.locale))
    }
    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
    private func setCount(_ value: Double) -> String { TrainingSetStatistics.formatted(value, locale: language.locale) }
    private func signedSets(_ value: Double) -> String { value > 0 ? "+\(setCount(value))" : setCount(value) }
    private func signedDuration(_ value: TimeInterval) -> String {
        let prefix = value > 0 ? "+" : value < 0 ? "−" : ""
        return prefix + durationText(abs(value))
    }
    private func signedWeight(_ kilograms: Double) -> String {
        let prefix = kilograms > 0 ? "+" : kilograms < 0 ? "−" : ""
        return prefix + compactWeight(abs(kilograms))
    }
    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
    private func compactWeight(_ kilograms: Double) -> String {
        let displayed = weightUnit.display(kilograms)
        return displayed >= 100_000
            ? "\((displayed / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(language.locale)))k \(weightUnit.rawValue)"
            : "\(displayed.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) \(weightUnit.rawValue)"
    }
    private var shareTopMuscles: [MonthlyReportShareMuscle] {
        let values = weightedMuscleCounts(for: monthWorkouts).sorted { $0.value > $1.value }
        let maximum = max(1, values.first?.value ?? 1)
        return values.prefix(3).map { muscle, value in
            MonthlyReportShareMuscle(
                name: t("training.muscle.\(muscle)"),
                value: formatSetCount(value),
                fraction: value / maximum
            )
        }
    }

    private func prepareAndPresentShareImage() {
        guard !isPreparingShareImage else { return }
        isPreparingShareImage = true
        Task { @MainActor in
            await Task.yield()
            renderedShareImage = renderShareImage()
            isPreparingShareImage = false
            isShareSheetPresented = renderedShareImage != nil
        }
    }

    private func renderShareImage() -> MonthlyReportShareImage? {
        let card = MonthlyReportShareCard(
            eyebrow: t("training.monthly_report.share_card_title"),
            month: reportMonth.formatted(.dateTime.month(.wide).year().locale(language.locale)),
            workoutsTitle: t("training.monthly_report.metric.workouts"),
            workoutsValue: "\(current.workouts)",
            workoutsDelta: signed(current.workouts - previous.workouts),
            workoutsDeltaValue: Double(current.workouts - previous.workouts),
            durationTitle: t("training.monthly_report.metric.duration"),
            durationValue: durationText(current.duration),
            durationDelta: signedDuration(current.duration - previous.duration),
            durationDeltaValue: current.duration - previous.duration,
            volumeTitle: t("training.monthly_report.metric.volume"),
            volumeValue: compactWeight(current.volume),
            volumeDelta: signedWeight(current.volume - previous.volume),
            volumeDeltaValue: current.volume - previous.volume,
            setsTitle: t("training.monthly_report.metric.sets"),
            setsValue: setCount(current.sets),
            setsDelta: signedSets(current.sets - previous.sets),
            setsDeltaValue: current.sets - previous.sets,
            recordsTitle: t("training.monthly_report.personal_records"),
            recordsValue: "\(current.personalRecords)",
            streakTitle: t("training.monthly_report.share_card_streak"),
            streakValue: "\(longestWeeklyStreak)",
            daysTitle: t("training.monthly_report.share_card_training_days"),
            daysValue: "\(trainedDayNumbers.count)",
            musclesTitle: t("training.monthly_report.share_card_top_muscles"),
            setsAbbreviation: t("training.monthly_report.metric.sets"),
            muscles: shareTopMuscles,
            footer: t("training.monthly_report.share_card_created_with")
        )
        .environment(\.locale, language.locale)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.pngData() else { return nil }
        return MonthlyReportShareImage(
            pngData: data,
            message: t("training.monthly_report.share_message")
        )
    }
}

private struct MonthlyReportShareSheet: UIViewControllerRepresentable {
    let item: MonthlyReportShareImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        guard let image = UIImage(data: item.pngData) else {
            return UIActivityViewController(activityItems: [item.message], applicationActivities: nil)
        }
        let reportItem = MonthlyReportShareActivityItem(image: image, message: item.message)
        return UIActivityViewController(activityItems: [reportItem, item.message], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class MonthlyReportShareActivityItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let message: String

    init(image: UIImage, message: String) {
        self.image = image
        self.message = message
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        message
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = message
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

private struct MonthlyReportShareCard: View {
    let eyebrow: String
    let month: String
    let workoutsTitle: String
    let workoutsValue: String
    let workoutsDelta: String
    let workoutsDeltaValue: Double
    let durationTitle: String
    let durationValue: String
    let durationDelta: String
    let durationDeltaValue: Double
    let volumeTitle: String
    let volumeValue: String
    let volumeDelta: String
    let volumeDeltaValue: Double
    let setsTitle: String
    let setsValue: String
    let setsDelta: String
    let setsDeltaValue: Double
    let recordsTitle: String
    let recordsValue: String
    let streakTitle: String
    let streakValue: String
    let daysTitle: String
    let daysValue: String
    let musclesTitle: String
    let setsAbbreviation: String
    let muscles: [MonthlyReportShareMuscle]
    let footer: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.035, blue: 0.07), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(HyseColor.accent.opacity(0.20))
                .frame(width: 360, height: 360)
                .blur(radius: 75)
                .offset(x: 235, y: -295)
            Circle()
                .fill(Color.cyan.opacity(0.09))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -260, y: 320)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(HyseColor.accent)
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)
                    Text("HYSE")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .tracking(2.2)
                    Spacer()
                    Text(month)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(HyseColor.accent)
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text(workoutsValue)
                            .font(.system(size: 72, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Text(workoutsTitle)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                        Spacer()
                        changePill(workoutsDelta, value: workoutsDeltaValue)
                    }
                }

                HStack(spacing: 12) {
                    metricCard(title: durationTitle, value: durationValue, delta: durationDelta, deltaValue: durationDeltaValue, icon: "clock.fill")
                    metricCard(title: volumeTitle, value: volumeValue, delta: volumeDelta, deltaValue: volumeDeltaValue, icon: "scalemass.fill")
                    metricCard(title: setsTitle, value: setsValue, delta: setsDelta, deltaValue: setsDeltaValue, icon: "checkmark.circle.fill")
                }

                HStack(spacing: 10) {
                    highlight(title: recordsTitle, value: recordsValue, icon: "medal.fill", tint: Color.yellow)
                    highlight(title: streakTitle, value: streakValue, icon: "flame.fill", tint: Color.orange)
                    highlight(title: daysTitle, value: daysValue, icon: "calendar", tint: HyseColor.accent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(musclesTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if muscles.isEmpty {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.08))
                            .frame(height: 9)
                    } else {
                        ForEach(muscles) { muscle in
                            HStack(spacing: 10) {
                                Text(muscle.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .frame(width: 104, alignment: .leading)
                                    .lineLimit(1)
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(.white.opacity(0.09))
                                        Capsule().fill(HyseColor.accent)
                                            .frame(width: geometry.size.width * max(0.04, muscle.fraction))
                                    }
                                }
                                .frame(height: 10)
                                Text("\(muscle.value) \(setsAbbreviation)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 66, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(17)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08)))

                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(footer)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.56))
                        Text(HyseConfiguration.serverURL)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(HyseColor.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HyseShareQRCode()
                }
            }
            .padding(34)
        }
        .foregroundStyle(.white)
        .frame(width: 540, height: 750)
        .clipped()
    }

    private func metricCard(title: String, value: String, delta: String, deltaValue: Double, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HyseColor.accent)
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(delta)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(comparisonColor(deltaValue))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08)))
    }

    private func highlight(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.system(size: 24, weight: .black, design: .rounded)).monospacedDigit()
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func changePill(_ text: String, value: Double) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(comparisonColor(value))
            .background(.white.opacity(0.08), in: Capsule())
    }

    private func comparisonColor(_ value: Double) -> Color {
        value > 0 ? HyseColor.success : value < 0 ? Color.red : Color.white.opacity(0.56)
    }
}

private struct MonthlyMuscleRadarChart: View {
    let current: [Double]
    let previous: [Double]
    let labels: [String]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36
            let maximum = max(1, (current + previous).max() ?? 1)
            for level in 1...5 {
                context.stroke(polygon(center: center, radius: radius * Double(level) / 5, values: Array(repeating: 1, count: 6)), with: .color(.secondary.opacity(0.22)), lineWidth: 1)
            }
            for index in 0..<6 {
                var axis = Path(); axis.move(to: center); axis.addLine(to: point(index, center, radius))
                context.stroke(axis, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                context.draw(Text(labels[index]).font(.caption).foregroundStyle(.secondary), at: point(index, center, radius + 24))
            }
            let previousPath = polygon(center: center, radius: radius, values: previous.map { $0 / maximum })
            context.fill(previousPath, with: .color(.secondary.opacity(0.17)))
            context.stroke(previousPath, with: .color(.secondary.opacity(0.75)), lineWidth: 2)
            let currentPath = polygon(center: center, radius: radius, values: current.map { $0 / maximum })
            context.fill(currentPath, with: .color(HyseColor.accent.opacity(0.28)))
            context.stroke(currentPath, with: .color(HyseColor.accent), lineWidth: 3)
        }
    }

    private func polygon(center: CGPoint, radius: Double, values: [Double]) -> Path {
        var path = Path()
        for index in 0..<6 {
            let value = values.indices.contains(index) ? min(max(values[index], 0), 1) : 0
            let target = point(index, center, radius * value)
            index == 0 ? path.move(to: target) : path.addLine(to: target)
        }
        path.closeSubpath()
        return path
    }

    private func point(_ index: Int, _ center: CGPoint, _ radius: Double) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) * Double.pi * 2 / 6
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}
