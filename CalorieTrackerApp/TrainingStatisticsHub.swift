import SwiftUI

struct TrainingStatisticsView: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var store: TrainingStore
    @State private var showingTrainingPremium = false

    private var recentDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private var recentWorkouts: [WorkoutLog] {
        TrainingStatisticsData.workouts(store.completedWorkouts, range: .sevenDays)
    }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                    VStack(alignment: .leading, spacing: HyseSpacing.large) {
                        HStack {
                            Text(language.text("training.statistics.last_seven_days"))
                                .font(.title3.bold())
                            Spacer()
                            HyseInfoButton(
                                title: language.text("training.statistics.last_seven_days"),
                                message: language.text("training.statistics.last_seven_days_info")
                            )
                        }
                        TrainingStatisticsDayPicker(
                            days: recentDays,
                            selectedDay: nil,
                            trainedDays: Set(store.completedWorkouts.map { Calendar.current.startOfDay(for: $0.completedAt ?? $0.startedAt) })
                        )
                        HyseCard(accent: HyseColor.accent) {
                            TrainingMuscleBodyGraphic(counts: TrainingStatisticsData.muscleCounts(in: recentWorkouts, catalog: store.exercises, halveUnilateral: halveUnilateral))
                                .frame(height: 310)
                        }
                    }

                    HyseSectionHeading(title: language.text("training.statistics.advanced"), icon: "chart.xyaxis.line")

                    VStack(spacing: 0) {
                        Group {
                            if premium.hasTraining {
                                NavigationLink { MuscleSetsStatisticsView(store: store) } label: {
                                    statisticsRow("training.statistics.sets_by_muscle", "training.statistics.sets_by_muscle_subtitle", "chart.bar.xaxis")
                                }
                            } else {
                                Button { showingTrainingPremium = true } label: {
                                    statisticsRow("training.statistics.sets_by_muscle", "training.statistics.sets_by_muscle_subtitle", "chart.bar.xaxis", locked: true)
                                }
                            }
                        }
                        Divider().padding(.leading, 58)
                        NavigationLink {
                            MuscleRadarStatisticsView(store: store)
                        } label: {
                            statisticsRow("training.statistics.muscle_chart", "training.statistics.muscle_chart_subtitle", "pentagon")
                        }
                        Divider().padding(.leading, 58)
                        NavigationLink {
                            MuscleBodyStatisticsView(store: store)
                        } label: {
                            statisticsRow("training.statistics.muscle_body", "training.statistics.muscle_body_subtitle", "figure.arms.open")
                        }
                        Divider().padding(.leading, 58)
                        NavigationLink {
                            TopExercisesStatisticsView(store: store)
                        } label: {
                            statisticsRow("training.statistics.top_exercises", "training.statistics.top_exercises_subtitle", "figure.strengthtraining.traditional")
                        }
                        Divider().padding(.leading, 58)
                        NavigationLink {
                            RecordExercisesStatisticsView(store: store)
                        } label: {
                            statisticsRow("training.statistics.record_exercises", "training.statistics.record_exercises_subtitle", "trophy")
                        }
                        Divider().padding(.leading, 58)
                        NavigationLink {
                            TrainingMonthlyReportView(store: store, month: previousMonth)
                        } label: {
                            statisticsRow("training.statistics.monthly_report", "training.statistics.monthly_report_subtitle", "doc.text.bar.chart")
                        }
                    }
                    .buttonStyle(.plain)
                    .hyseGlassSurface(radius: HyseRadius.card)
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.top, HyseSpacing.small)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle(language.text("training.statistics"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
    }

    private var previousMonth: Date {
        let calendar = Calendar.current
        let previous = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return calendar.date(from: calendar.dateComponents([.year, .month], from: previous)) ?? previous
    }

    private func statisticsRow(_ titleKey: String, _ subtitleKey: String, _ icon: String, locked: Bool = false) -> some View {
        HStack(spacing: HyseSpacing.large) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(HyseColor.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(titleKey))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(language.text(subtitleKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: locked ? "crown.fill" : "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(locked ? HyseColor.accent : Color.secondary)
        }
        .padding(.horizontal, HyseSpacing.large)
        .padding(.vertical, HyseSpacing.medium)
        .contentShape(Rectangle())
    }
}

private struct TrainingStatisticsDayPicker: View {
    @EnvironmentObject private var language: LanguageStore
    let days: [Date]
    let selectedDay: Binding<Date>?
    let trainedDays: Set<Date>

    var body: some View {
        HStack(spacing: HyseSpacing.small) {
            ForEach(days, id: \.self) { day in
                let selected = selectedDay.map { Calendar.current.isDate(day, inSameDayAs: $0.wrappedValue) } ?? false
                let trained = trainedDays.contains(Calendar.current.startOfDay(for: day))
                Button {
                    guard let selectedDay else { return }
                    withAnimation(HyseMotion.quick) { selectedDay.wrappedValue = day }
                } label: {
                    VStack(spacing: 7) {
                        Text(day.formatted(.dateTime.weekday(.narrow).locale(language.locale)).uppercased())
                            .font(.caption2.weight(.semibold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(trained || selected ? .white : .secondary)
                            .frame(width: 34, height: 34)
                            .background(trained ? HyseColor.accent : selected ? HyseColor.accent.opacity(0.32) : Color.clear, in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .allowsHitTesting(selectedDay != nil)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month().locale(language.locale)))
            }
        }
    }
}

private struct TrainingMuscleBodyGraphic: View {
    let counts: [String: Double]

    var body: some View {
        DetailedTrainingMuscleBody(counts: counts)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Muscle activity")
    }
}

private nonisolated enum TrainingStatisticsRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays, thirtyDays, ninetyDays, allTime
    var id: String { rawValue }
    var days: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .allTime: nil
        }
    }
    var localizationKey: String { "training.statistics.range.\(rawValue)" }
}

private nonisolated enum TrainingStatisticsData {
    static func workouts(_ all: [WorkoutLog], range: TrainingStatisticsRange, end: Date = Date()) -> [WorkoutLog] {
        guard let days = range.days else { return all }
        let calendar = Calendar.autoupdatingCurrent
        let endDay = calendar.startOfDay(for: end)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: endDay),
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else { return all }
        return all.filter {
            let date = $0.completedAt ?? $0.startedAt
            return date >= start && date < endExclusive
        }
    }

    static func muscleCounts(in workouts: [WorkoutLog], catalog: [TrainingExercise] = [], halveUnilateral: Bool = false) -> [String: Double] {
        var values: [String: Double] = [:]
        let catalogByID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for workout in workouts {
            guard !Task.isCancelled else { return [:] }
            for exercise in workout.exercises {
                let count = TrainingSetStatistics.count(exercise, halveUnilateral: halveUnilateral)
                guard count > 0 else { continue }
                let muscles = resolvedMuscles(for: exercise, catalog: catalog, catalogByID: catalogByID)
                let weightedRegions = TrainingMuscleRegionMap.weightedRegions(
                    primary: muscles.primary,
                    secondary: muscles.secondary
                )
                for (muscle, weight) in weightedRegions where !muscle.isEmpty {
                    values[muscle, default: 0] += count * weight
                }
            }
        }
        return values
    }

    private static func resolvedMuscles(for log: WorkoutExerciseLog, catalog: [TrainingExercise], catalogByID: [UUID: TrainingExercise]) -> (primary: [String], secondary: [String]) {
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
        if let exercise = catalogByID[log.exerciseID] {
            return (exercise.primaryMuscles, exercise.secondaryMuscles)
        }
        if !log.primaryMusclesSnapshot.isEmpty || !log.secondaryMusclesSnapshot.isEmpty {
            return (log.primaryMusclesSnapshot, log.secondaryMusclesSnapshot)
        }
        let restored = TrainingExercise(
            id: log.exerciseID,
            nameKey: "statistics_restore",
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
            .map(nameFingerprint)
            .filter { !$0.isEmpty }
        if let exercise = catalog.first(where: { candidate in
            let candidateNames = [candidate.englishName, candidate.germanName].map(nameFingerprint)
            return importedNames.contains { imported in
                candidateNames.contains { name in
                    imported == name || imported.isSubset(of: name) || name.isSubset(of: imported)
                }
            }
        }) {
            return (exercise.primaryMuscles, exercise.secondaryMuscles)
        }
        return ([], [])
    }

    private static func nameFingerprint(_ value: String) -> Set<String> {
        let ignored = Set(["a", "am", "an", "at", "der", "dem", "die", "im", "in", "mit", "the", "von", "with", "barbell", "cable", "dumbbell", "kabel", "kabelzug", "kurzhantel", "langhantel", "machine", "maschine"])
        return Set(value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !ignored.contains($0) })
    }

    static func exerciseCounts(in workouts: [WorkoutLog]) -> [(exercise: WorkoutExerciseLog, count: Int)] {
        var values: [UUID: (WorkoutExerciseLog, Int)] = [:]
        for workout in workouts {
            guard !Task.isCancelled else { return [] }
            for exercise in workout.exercises where exercise.completedSetCount > 0 {
                let current = values[exercise.exerciseID]
                values[exercise.exerciseID] = (current?.0 ?? exercise, (current?.1 ?? 0) + 1)
            }
        }
        return values.values.sorted { $0.1 > $1.1 }.map { ($0.0, $0.1) }
    }
}

private struct StatisticsLoadingIndicator: View {
    @EnvironmentObject private var language: LanguageStore

    var body: some View {
        HStack(spacing: HyseSpacing.small) {
            ProgressView()
            Text(language.text("training.statistics.calculating"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HyseSpacing.xLarge)
        .accessibilityElement(children: .combine)
    }
}

private struct StatisticsRangePicker: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @Binding var range: TrainingStatisticsRange
    @State private var showingTrainingPremium = false
    var body: some View {
        Menu {
            ForEach(TrainingStatisticsRange.allCases) { value in
                Button {
                    if (value == .ninetyDays || value == .allTime) && !premium.hasTraining {
                        showingTrainingPremium = true
                    } else {
                        range = value
                    }
                } label: {
                    Label(language.text(value.localizationKey), systemImage: (value == .ninetyDays || value == .allTime) && !premium.hasTraining ? "crown.fill" : "calendar")
                }
            }
        } label: {
            HStack {
                Text(language.text(range.localizationKey)).font(.headline)
                Spacer()
                Image(systemName: "chevron.down")
            }
            .foregroundStyle(.primary)
            .padding(HyseSpacing.large)
            .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
    }
}

private struct MuscleSetsStatisticsView: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @ObservedObject var store: TrainingStore
    @State private var range = TrainingStatisticsRange.thirtyDays
    @State private var counts: [(String, Double)] = []
    @State private var isLoading = true
    private var maximum: Double { max(1, counts.map(\.1).max() ?? 1) }
    var body: some View {
        statisticsPage(title: language.text("training.statistics.sets_by_muscle")) {
            StatisticsRangePicker(range: $range)
            if isLoading {
                StatisticsLoadingIndicator()
            } else {
                ForEach(counts, id: \.0) { muscle, count in
                    HyseCard {
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            HStack { Text(language.text("training.muscle.\(muscle)")).font(.headline); Spacer(); Text(formatSetCount(count)).monospacedDigit() }
                            HyseProgressBar(value: count, total: maximum, colors: [HyseColor.accent])
                        }
                    }
                }
            }
        }
        .task(id: "\(range)-\(halveUnilateral)") {
            isLoading = true
            let workouts = store.completedWorkouts
            let catalog = store.exercises
            let selectedRange = range
            let countAsHalf = halveUnilateral
            let calculation = Task.detached(priority: .userInitiated) {
                TrainingStatisticsData.muscleCounts(
                    in: TrainingStatisticsData.workouts(workouts, range: selectedRange),
                    catalog: catalog,
                    halveUnilateral: countAsHalf
                ).sorted { $0.value > $1.value }
            }
            let result = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: {
                calculation.cancel()
            }
            guard !Task.isCancelled else { return }
            counts = result
            isLoading = false
        }
    }

    private func formatSetCount(_ value: Double) -> String {
        TrainingSetStatistics.formatted(value, locale: language.locale)
    }
}

private struct MuscleRadarStatisticsView: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @ObservedObject var store: TrainingStore
    @State private var range = TrainingStatisticsRange.thirtyDays
    @State private var current = Array(repeating: 0.0, count: 6)
    @State private var previous = Array(repeating: 0.0, count: 6)
    @State private var summaryWorkouts: [WorkoutLog] = []
    @State private var isLoading = true
    var body: some View {
        statisticsPage(title: language.text("training.statistics.muscle_chart")) {
            StatisticsRangePicker(range: $range)
            if isLoading {
                StatisticsLoadingIndicator()
            } else {
                HyseCard {
                    TrainingMuscleRadarChart(current: current, previous: previous)
                        .frame(height: 330)
                }
                TrainingStatisticsSummaryGrid(workouts: summaryWorkouts)
            }
        }
        .task(id: "\(range)-\(halveUnilateral)") {
            isLoading = true
            let allWorkouts = store.completedWorkouts
            let catalog = store.exercises
            let selectedRange = range
            let countAsHalf = halveUnilateral
            let now = Date()
            let calculation = Task.detached(priority: .userInitiated) { () -> ([Double], [Double], [WorkoutLog]) in
                let visibleWorkouts = TrainingStatisticsData.workouts(allWorkouts, range: selectedRange, end: now)
                let current = TrainingMuscleRadarChart.grouped(
                    TrainingStatisticsData.muscleCounts(in: visibleWorkouts, catalog: catalog, halveUnilateral: countAsHalf)
                )
                guard let days = selectedRange.days else {
                    return (current, Array(repeating: 0, count: 6), visibleWorkouts)
                }
                let end = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
                let previousWorkouts = TrainingStatisticsData.workouts(allWorkouts, range: selectedRange, end: end)
                let previous = TrainingMuscleRadarChart.grouped(
                    TrainingStatisticsData.muscleCounts(in: previousWorkouts, catalog: catalog, halveUnilateral: countAsHalf)
                )
                return (current, previous, visibleWorkouts)
            }
            let result = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: {
                calculation.cancel()
            }
            guard !Task.isCancelled else { return }
            current = result.0
            previous = result.1
            summaryWorkouts = result.2
            isLoading = false
        }
    }
}

private struct MuscleBodyStatisticsView: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @ObservedObject var store: TrainingStore
    @State private var weekOffset = 0
    private var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date())?.start ?? Date()
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var workouts: [WorkoutLog] { store.completedWorkouts.filter { workout in weekDays.contains { Calendar.current.isDate($0, inSameDayAs: workout.completedAt ?? workout.startedAt) } } }
    private var counts: [(String, Double)] { TrainingStatisticsData.muscleCounts(in: workouts, catalog: store.exercises, halveUnilateral: halveUnilateral).sorted { $0.value > $1.value } }
    var body: some View {
        statisticsPage(title: language.text("training.statistics.muscle_body")) {
            HStack {
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(weekLabel).font(.headline)
                Spacer()
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }.disabled(weekOffset >= 0)
            }
            TrainingStatisticsDayPicker(days: weekDays, selectedDay: nil, trainedDays: Set(workouts.map { Calendar.current.startOfDay(for: $0.completedAt ?? $0.startedAt) }))
                .allowsHitTesting(false)
            HyseCard(accent: HyseColor.accent) {
                TrainingMuscleBodyGraphic(counts: Dictionary(uniqueKeysWithValues: counts)).frame(height: 310)
            }
            HStack {
                Text(language.text("training.statistics.muscles")).font(.title3).foregroundStyle(.secondary)
                Spacer()
                Text(language.text("training.completed_sets")).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(counts, id: \.0) { muscle, count in
                HStack { Text(language.text("training.muscle.\(muscle)")); Spacer(); Text(formatSetCount(count)).monospacedDigit() }
                    .padding(.vertical, HyseSpacing.small)
                Divider()
            }
        }
    }
    private var weekLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return "\(first.formatted(.dateTime.day().month(.abbreviated).locale(language.locale))) – \(last.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale)))"
    }
    private func formatSetCount(_ value: Double) -> String {
        TrainingSetStatistics.formatted(value, locale: language.locale)
    }
}

private struct TopExercisesStatisticsView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    @State private var range = TrainingStatisticsRange.thirtyDays
    @State private var exercises: [(exercise: WorkoutExerciseLog, count: Int)] = []
    @State private var isLoading = true
    var body: some View {
        statisticsPage(title: language.text("training.statistics.top_exercises")) {
            StatisticsRangePicker(range: $range)
            if isLoading {
                StatisticsLoadingIndicator()
            } else {
                ForEach(exercises, id: \.exercise.exerciseID) { item in
                    NavigationLink { exerciseDestination(item.exercise) } label: {
                        StatisticsExerciseRow(exercise: item.exercise, detail: language.text("training.statistics.times", [item.count]), store: store)
                    }.buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .task(id: range) {
            isLoading = true
            let workouts = store.completedWorkouts
            let selectedRange = range
            let calculation = Task.detached(priority: .userInitiated) {
                TrainingStatisticsData.exerciseCounts(
                    in: TrainingStatisticsData.workouts(workouts, range: selectedRange)
                )
            }
            let result = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: {
                calculation.cancel()
            }
            guard !Task.isCancelled else { return }
            exercises = result
            isLoading = false
        }
    }
    @ViewBuilder private func exerciseDestination(_ log: WorkoutExerciseLog) -> some View {
        if let exercise = store.exercises.first(where: { $0.id == log.exerciseID }) { ExerciseProgressView(exercise: exercise, store: store) }
        else { Text(log.exerciseNameSnapshot) }
    }
}

private struct RecordExercisesStatisticsView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    private var exercises: [(exercise: WorkoutExerciseLog, count: Int)] {
        var records: [UUID: (WorkoutExerciseLog, Int)] = [:]
        for workout in store.completedWorkouts {
            for exercise in workout.exercises {
                let count = exercise.sets.filter { $0.completed && $0.hasPersonalRecord }.count
                guard count > 0 else { continue }
                let old = records[exercise.exerciseID]
                records[exercise.exerciseID] = (old?.0 ?? exercise, (old?.1 ?? 0) + count)
            }
        }
        return records.values.sorted { $0.1 > $1.1 }.map { ($0.0, $0.1) }
    }
    var body: some View {
        statisticsPage(title: language.text("training.statistics.record_exercises")) {
            if exercises.isEmpty {
                HyseCard { HyseEmptyState(icon: "trophy", title: language.text("training.statistics.no_records"), message: language.text("training.statistics.no_records_subtitle")) }
            } else {
                ForEach(exercises, id: \.exercise.exerciseID) { item in
                    StatisticsExerciseRow(exercise: item.exercise, detail: language.text("training.statistics.records", [item.count]), store: store)
                    Divider()
                }
            }
        }
    }
}

private struct StatisticsExerciseRow: View {
    @EnvironmentObject private var language: LanguageStore
    let exercise: WorkoutExerciseLog
    let detail: String
    @ObservedObject var store: TrainingStore
    var body: some View {
        HStack(spacing: HyseSpacing.large) {
            ExerciseMovementVisual(exercise: visual, height: 58).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty ? exercise.exerciseGermanNameSnapshot : exercise.exerciseNameSnapshot).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .padding(.vertical, HyseSpacing.small)
        .contentShape(Rectangle())
    }
    private var visual: TrainingExercise {
        store.exercises.first(where: { $0.id == exercise.exerciseID }) ?? TrainingExercise(id: exercise.exerciseID, nameKey: "custom", englishName: exercise.exerciseNameSnapshot, germanName: exercise.exerciseGermanNameSnapshot, descriptionKey: "", techniqueKey: "", type: exercise.exerciseTypeSnapshot, equipment: exercise.equipmentSnapshot, primaryMuscles: exercise.primaryMusclesSnapshot, secondaryMuscles: exercise.secondaryMusclesSnapshot, isCustom: true, isFavorite: false, updatedAt: Date())
    }
}

private struct TrainingMuscleRadarChart: View {
    @EnvironmentObject private var language: LanguageStore
    let current: [Double]
    let previous: [Double]
    private var labels: [String] {
        ["back", "chest", "core", "shoulders", "arms", "legs"].map { language.text("training.muscle.\($0)") }
    }
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36
            let maximum = max(1, (current + previous).max() ?? 1)
            for level in 1...5 {
                context.stroke(polygon(center: center, radius: radius * Double(level) / 5, values: Array(repeating: 1, count: 6)), with: .color(.secondary.opacity(0.22)), lineWidth: 1)
            }
            for index in 0..<6 {
                var axis = Path(); axis.move(to: center); axis.addLine(to: point(index: index, center: center, radius: radius))
                context.stroke(axis, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                let labelPoint = point(index: index, center: center, radius: radius + 24)
                context.draw(Text(labels[index]).font(.caption).foregroundStyle(.secondary), at: labelPoint)
            }
            let previousPath = polygon(center: center, radius: radius, values: previous.map { $0 / maximum })
            context.fill(previousPath, with: .color(.secondary.opacity(0.18)))
            context.stroke(previousPath, with: .color(.secondary.opacity(0.7)), lineWidth: 2)
            let currentPath = polygon(center: center, radius: radius, values: current.map { $0 / maximum })
            context.fill(currentPath, with: .color(HyseColor.accent.opacity(0.25)))
            context.stroke(currentPath, with: .color(HyseColor.accent), lineWidth: 3)
        }
    }
    private func polygon(center: CGPoint, radius: Double, values: [Double]) -> Path {
        var path = Path()
        for index in 0..<6 {
            let point = point(index: index, center: center, radius: radius * min(max(values.indices.contains(index) ? values[index] : 0, 0), 1))
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath(); return path
    }
    private func point(index: Int, center: CGPoint, radius: Double) -> CGPoint {
        let angle = -Double.pi / 2 + Double(index) * Double.pi * 2 / 6
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
    nonisolated static func grouped(_ counts: [String: Double]) -> [Double] {
        let groups = [["back", "upper_back", "lats"], ["chest"], ["abs", "core"], ["front_shoulders", "side_shoulders", "rear_shoulders", "shoulders"], ["biceps", "triceps", "forearms"], ["quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]]
        return groups.map { group in group.reduce(0) { $0 + counts[$1, default: 0] } }
    }
}

private struct TrainingStatisticsSummaryGrid: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    let workouts: [WorkoutLog]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HyseSpacing.medium) {
            card("training.statistics.workouts", "\(workouts.count)")
            card("training.statistics.duration", formattedDuration(workouts.reduce(0) { $0 + $1.duration }))
            card("training.statistics.volume", "\(Int(workouts.reduce(0) { $0 + $1.totalVolume })) kg")
            card("training.completed_sets", TrainingSetStatistics.formatted(TrainingSetStatistics.count(workouts, halveUnilateral: halveUnilateral), locale: language.locale))
        }
    }
    private func card(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(language.text(key)).foregroundStyle(.secondary); Text(value).font(.title2.bold()).monospacedDigit() }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading).padding(HyseSpacing.large).hyseGlassSurface(radius: HyseRadius.card)
    }
    private func formattedDuration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

@ViewBuilder private func statisticsPage<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    ZStack {
        HyseBackdrop()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HyseSpacing.large) { content() }
                .padding(HyseSpacing.page)
                .padding(.bottom, 28)
        }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
}
