import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import CoreTransferable
import Charts
import Combine

struct TrainingHistoryView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    @State private var query = ""
    @State private var muscle: String?
    @State private var routineID: UUID?
    @State private var recentDays = 0

    private var filtered: [WorkoutLog] {
        let earliest = recentDays > 0 ? Calendar.current.date(byAdding: .day, value: -recentDays, to: Date()) : nil
        return store.completedWorkouts.filter { workout in
            (query.isEmpty || workout.name.localizedCaseInsensitiveContains(query))
                && (muscle == nil || workout.muscleGroups.contains(muscle!))
                && (routineID == nil || workout.routineID == routineID)
                && (earliest == nil || (workout.completedAt ?? workout.startedAt) >= earliest!)
        }
    }

    private var grouped: [(Date, [WorkoutLog])] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.completedAt ?? $0.startedAt) }
            .map { ($0.key, $0.value) }.sorted { $0.0 > $1.0 }
    }

    var body: some View {
        List {
            Section {
                HyseSearchField(placeholder: language.text("training.history.search"), text: $query)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Menu { Button(language.text("training.filter.all_muscles")) { muscle = nil }; ForEach(store.muscleDistribution.map(\.muscle), id: \.self) { value in Button(language.text("training.muscle.\(value)")) { muscle = value } } } label: { Label(muscle.map { language.text("training.muscle.\($0)") } ?? language.text("training.primary_muscle"), systemImage: "figure.arms.open") }.buttonStyle(.bordered)
                        Menu { Button(language.text("training.history.all_routines")) { routineID = nil }; ForEach(store.routines) { routine in Button(routine.name) { routineID = routine.id } } } label: { Label(store.routines.first(where: { $0.id == routineID })?.name ?? language.text("training.routines"), systemImage: "list.bullet.rectangle") }.buttonStyle(.bordered)
                        Menu { Button(language.text("training.history.all_time")) { recentDays = 0 }; Button(language.text("training.history.last_7_days")) { recentDays = 7 }; Button(language.text("training.history.last_30_days")) { recentDays = 30 } } label: { Label(recentDays == 0 ? language.text("training.history.all_time") : language.text("training.history.last_days", [recentDays]), systemImage: "calendar") }.buttonStyle(.bordered)
                    }
                }
                if muscle != nil || routineID != nil || recentDays > 0 { Button(language.text("training.filter.reset")) { muscle = nil; routineID = nil; recentDays = 0 }.font(.caption) }
            }
            if grouped.isEmpty {
                HyseEmptyState(icon: "clock.arrow.circlepath", title: language.text("training.history.empty.title"), message: language.text("training.history.empty.message"))
            } else {
                ForEach(grouped, id: \.0) { date, workouts in
                    Section(date.formatted(.dateTime.weekday(.wide).day().month().year().locale(language.locale))) {
                        ForEach(workouts) { workout in NavigationLink { WorkoutSummaryView(workout: workout, store: store) } label: { WorkoutHistoryRow(workout: workout) } }
                    }
                }
            }
        }.hyseForm().navigationTitle(language.text("training.history"))
    }
}

private struct WorkoutHistoryRow: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    let workout: WorkoutLog
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(workout.name).font(.headline)
                Spacer()
                Text((workout.completedAt ?? workout.startedAt).formatted(.dateTime.day().month().year().locale(language.locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(durationText(workout.duration), systemImage: "timer")
                Label(t("training.progress.sets_short", TrainingSetStatistics.formatted(TrainingSetStatistics.count(workout, halveUnilateral: halveUnilateral), locale: language.locale)), systemImage: "checkmark.circle")
                Label(String(format: "%.0f %@", weightUnit.display(workout.totalVolume), weightUnit.rawValue), systemImage: "scalemass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let gymName = workout.gymName, !gymName.isEmpty {
                Label([gymName, workout.gymAddress].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct WorkoutSummaryView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @AppStorage("trainingDistanceUnit_v1") private var trainingDistanceUnitRaw = TrainingDistanceUnit.kilometers.rawValue
    let workout: WorkoutLog
    @ObservedObject var store: TrainingStore
    @StateObject private var social = TrainingSocialStore()
    var username: String? = nil
    @State private var workoutForEditing: WorkoutLog?
    @State private var showingRepeatedWorkout = false
    @State private var showingDeleteConfirmation = false
    @State private var showingShareComposer = false
    @State private var isMuscleSplitExpanded = false
    @State private var commentWorkoutID: String?
    @State private var commentLoadError: String?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    private var distanceUnit: TrainingDistanceUnit { TrainingDistanceUnit(rawValue: trainingDistanceUnitRaw) ?? .kilometers }

    private var currentWorkout: WorkoutLog {
        store.completedWorkouts.first(where: { $0.id == workout.id }) ?? workout
    }

    private var personalRecordCount: Int {
        currentWorkout.completedSets.filter(\.hasPersonalRecord).count
    }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
                    workoutHeader
                    Divider()
                    workoutActions
                    if authManager.isLoggedIn {
                        Group {
                            if let commentWorkoutID {
                                WorkoutCommentsSection(social: social, store: store, workoutID: commentWorkoutID)
                            } else if let commentLoadError {
                                HyseStatusBanner(title: t("training.social.comments"), message: commentLoadError, style: .warning,
                                                 actionTitle: t("content.retry"), action: { Task { await loadComments() } })
                            } else {
                                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                                    Text(t("training.social.comments")).font(.title3.bold())
                                    ProgressView()
                                }
                            }
                        }
                        .task(id: currentWorkout.id) { await loadComments() }
                    }
                    Divider()

                    if !muscleSplit.isEmpty {
                        muscleSplitSection
                    }

                    if personalRecordCount > 0 {
                        personalRecordCard
                    }

                    HStack {
                        Text(t("training.feed.workout"))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(t("training.feed.edit")) {
                            workoutForEditing = currentWorkout
                        }
                        .font(.subheadline)
                        .foregroundStyle(HyseColor.accent)
                    }

                    ForEach(currentWorkout.exercises) { exercise in
                        workoutExerciseSection(exercise)
                    }

                    if !currentWorkout.notes.isEmpty {
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            Text(t("training.workout.notes"))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(currentWorkout.notes)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(HyseSpacing.page)
            }
        }
        .navigationTitle(t("training.social.workout_details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingShareComposer = true } label: {
                        Label(t("training.feed.share"), systemImage: "square.and.arrow.up")
                    }
                    Button { store.createRoutine(from: currentWorkout) } label: {
                        Label(t("training.feed.save_as_routine"), systemImage: "square.and.arrow.down")
                    }
                    Button { workoutForEditing = currentWorkout } label: {
                        Label(t("training.feed.edit"), systemImage: "pencil")
                    }
                    Button { repeatWorkout() } label: {
                        Label(t("training.repeat"), systemImage: "arrow.counterclockwise")
                    }
                    .disabled(store.activeWorkout != nil)
                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                        Label(t("training.feed.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 40, height: 40)
                }
            }
        }
        .sheet(item: $workoutForEditing) { value in
            NavigationStack {
                WorkoutCompletionEditor(
                    workout: value,
                    store: store,
                    onSave: { edited in
                        store.updateCompletedWorkout(edited)
                        workoutForEditing = nil
                    },
                    onDiscard: { workoutForEditing = nil }
                )
            }
        }
        .sheet(isPresented: $showingShareComposer) {
            WorkoutShareComposer(
                workout: currentWorkout,
                muscleCounts: WorkoutShareMuscles.counts(for: currentWorkout),
                store: store
            )
            .environmentObject(language)
        }
        .fullScreenCover(isPresented: $showingRepeatedWorkout) {
            ActiveWorkoutView(store: store, animateToLatestCompletedExercise: false)
        }
        .confirmationDialog(
            t("training.feed.delete_title"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("training.feed.delete"), role: .destructive) {
                store.deleteCompletedWorkout(currentWorkout.id)
                dismiss()
            }
            Button(t("app_tabs.cancel"), role: .cancel) {}
        } message: {
            Text(t("training.feed.delete_message"))
        }
    }

    private var workoutHeader: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(spacing: HyseSpacing.medium) {
                ProfileAvatarView(size: 52, editable: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayUsername)
                        .font(.headline)
                    Text((currentWorkout.completedAt ?? currentWorkout.startedAt).formatted(.dateTime.weekday(.wide).day().month().year().hour().minute().locale(language.locale)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: HyseSpacing.medium) {
                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                    Text(currentWorkout.name)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    if let gymName = currentWorkout.gymName, !gymName.isEmpty {
                        HStack(alignment: .top, spacing: HyseSpacing.small) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(HyseColor.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gymName)
                                    .font(.headline)
                                if let address = currentWorkout.gymAddress, !address.isEmpty {
                                    Text(address)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if currentWorkout.mediaLocalFilename != nil {
                    WorkoutMediaView(localFilename: currentWorkout.mediaLocalFilename, compact: true, compactSize: 88)
                }
            }

            HStack(spacing: 0) {
                metric(t("training.duration"), activeWorkoutDurationText(currentWorkout.duration))
                metric(t("training.total_volume"), formattedVolume(currentWorkout.totalVolume))
                metric(t("training.completed_sets"), TrainingSetStatistics.formatted(TrainingSetStatistics.count(currentWorkout, halveUnilateral: halveUnilateral), locale: language.locale))
            }
        }
    }

    private var workoutActions: some View {
        HStack(spacing: HyseSpacing.xLarge) {
            Button { repeatWorkout() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .disabled(store.activeWorkout != nil)
            Button { workoutForEditing = currentWorkout } label: {
                Image(systemName: "pencil")
            }
            Button { showingShareComposer = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(t("training.share.title"))
            Spacer()
        }
        .font(.title3)
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
    }

    private func loadComments() async {
        commentLoadError = nil
        let workoutID = currentWorkout.remoteID ?? currentWorkout.id.uuidString.lowercased()
        var value = await social.loadDetail(id: workoutID, auth: authManager, force: true)
        if value == nil, currentWorkout.remoteID == nil {
            await store.flushPendingSync()
            value = await social.loadDetail(id: workoutID, auth: authManager, force: true)
        }
        if let resolved = value, resolved.id != workoutID {
            value = await social.loadDetail(id: resolved.id, auth: authManager, force: true)
        }
        commentWorkoutID = value?.id
        if value == nil {
            commentLoadError = social.errorMessage ?? t("training.feed.details_unavailable")
        }
    }

    private var personalRecordCard: some View {
        let gold = Color(red: 0.88, green: 0.64, blue: 0.12)
        let goldInk = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1)
                : UIColor(red: 0.49, green: 0.32, blue: 0.02, alpha: 1)
        })
        return HStack(spacing: HyseSpacing.medium) {
            Image(systemName: "trophy.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(goldInk)
                .frame(width: 48, height: 48)
                .background(gold.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                Text(t(personalRecordCount == 1 ? "training.pr.title" : "training.pr.multiple_title"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(personalRecordCount == 1
                     ? t("training.pr.message")
                     : t("training.summary.personal_records", personalRecordCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: HyseSpacing.small)
            Text("\(personalRecordCount)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(goldInk)
        }
        .padding(HyseSpacing.page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                .fill(LinearGradient(colors: [gold.opacity(0.22), gold.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                .stroke(gold.opacity(0.42), lineWidth: 1)
        }
    }

    private var muscleSplitSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            Text(t("training.feed.muscle_split"))
                .font(.title3)
                .foregroundStyle(.secondary)
            ForEach(Array(muscleSplit.prefix(isMuscleSplitExpanded ? muscleSplit.count : 2)), id: \.muscle) { entry in
                VStack(alignment: .leading, spacing: HyseSpacing.small) {
                    Text(t("training.muscle.\(entry.muscle)"))
                        .font(.headline)
                    HStack(spacing: HyseSpacing.small) {
                        ProgressView(value: entry.fraction)
                            .tint(HyseColor.accent)
                            .scaleEffect(x: 1, y: 2.2, anchor: .center)
                        Text(entry.fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 48, alignment: .leading)
                    }
                }
            }
            if muscleSplit.count > 2 {
                Button {
                    withAnimation(HyseMotion.standard) { isMuscleSplitExpanded.toggle() }
                } label: {
                    Label(
                        isMuscleSplitExpanded
                            ? t("training.feed.fewer_muscles")
                            : t("training.feed.more_muscles", muscleSplit.count - 2),
                        systemImage: isMuscleSplitExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(HyseColor.accent)
            }
        }
    }

    private func workoutExerciseSection(_ exercise: WorkoutExerciseLog) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(spacing: HyseSpacing.medium) {
                ExerciseMovementVisual(exercise: exerciseForVisual(exercise), height: 52)
                Text(exerciseName(exercise))
                    .font(.title3.bold())
                    .foregroundStyle(HyseColor.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(t("training.feed.set"))
                    .frame(width: 52, alignment: .leading)
                Text(t("training.feed.result"))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(Array(exercise.sets.filter(\.completed).enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text("\(index + 1)")
                        .font(.headline)
                        .frame(width: 52, alignment: .leading)
                    Text(setDescription(set, type: exercise.exerciseTypeSnapshot))
                        .monospacedDigit()
                    Spacer()
                }
            }
        }
        .padding(.vertical, HyseSpacing.small)
    }

    private var muscleSplit: [(muscle: String, fraction: Double)] {
        var counts: [String: Double] = [:]
        for exercise in currentWorkout.exercises {
            let setCount = TrainingSetStatistics.count(exercise, halveUnilateral: halveUnilateral)
            guard setCount > 0 else { continue }
            for muscle in exercise.primaryMusclesSnapshot {
                counts[muscle, default: 0] += setCount
            }
        }
        let total = max(1, counts.values.reduce(0, +))
        return counts.map { ($0.key, $0.value / total) }
            .sorted { left, right in
                if left.fraction != right.fraction { return left.fraction > right.fraction }
                let leftName = t("training.muscle.\(left.muscle)")
                let rightName = t("training.muscle.\(right.muscle)")
                let order = leftName.compare(rightName, options: [.caseInsensitive, .diacriticInsensitive], locale: language.locale)
                return order == .orderedSame ? left.muscle < right.muscle : order == .orderedAscending
            }
    }

    private var displayUsername: String {
        guard let username, !username.isEmpty else { return t("training.feed.your_workout") }
        return "@\(username)"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedVolume(_ kilograms: Double) -> String {
        "\(weightUnit.display(kilograms).formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue)"
    }

    private func exerciseName(_ exercise: WorkoutExerciseLog) -> String {
        language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty
            ? exercise.exerciseGermanNameSnapshot
            : exercise.exerciseNameSnapshot
    }

    private func exerciseForVisual(_ log: WorkoutExerciseLog) -> TrainingExercise {
        store.exercises.first(where: { $0.id == log.exerciseID }) ?? TrainingExercise(
            id: log.exerciseID,
            nameKey: "custom",
            englishName: log.exerciseNameSnapshot,
            germanName: log.exerciseGermanNameSnapshot,
            descriptionKey: "",
            techniqueKey: "",
            type: log.exerciseTypeSnapshot,
            equipment: log.equipmentSnapshot,
            primaryMuscles: log.primaryMusclesSnapshot,
            secondaryMuscles: log.secondaryMusclesSnapshot,
            isCustom: true,
            isFavorite: false,
            updatedAt: Date()
        )
    }

    private func repeatWorkout() {
        guard store.activeWorkout == nil else { return }
        store.repeatWorkout(currentWorkout)
        showingRepeatedWorkout = true
    }

    private func setDescription(_ set: TrainingSetLog, type: TrainingExerciseType) -> String {
        switch type {
        case .weightReps: return "\(weightUnit.display(set.weightKilograms).formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue) × \(set.reps)"
        case .bodyweight: return t("training.summary.bodyweight_set", set.reps, weightUnit.display(set.weightKilograms).formatted(.number.precision(.fractionLength(0...1))), weightUnit.rawValue)
        case .duration: return durationText(set.durationSeconds)
        case .distanceDuration: return "\(distanceUnit.display(set.distanceMeters).formatted(.number.precision(.fractionLength(0...2)))) \(distanceUnit.rawValue) · \(durationText(set.durationSeconds)) · \(paceText(set))"
        case .repsOnly: return t("training.summary.reps", set.reps)
        }
    }
    private func paceText(_ set: TrainingSetLog) -> String {
        guard let seconds = distanceUnit.paceSeconds(durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters) else { return "–" }
        return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60)) /\(distanceUnit.rawValue)"
    }
}

struct TrainingStatisticsDashboardView: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @ObservedObject var store: TrainingStore
    @State private var exerciseSearchQuery = ""
    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    var body: some View {
        let stats = store.statistics(halveUnilateral: halveUnilateral)
        return ZStack {
            HyseBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                    HyseCard(accent: HyseColor.accent) {
                        VStack(alignment: .leading, spacing: HyseSpacing.large) {
                            HyseSectionHeading(
                                title: language.text("training.statistics"),
                                subtitle: language.text("training.statistics.subtitle"),
                                icon: "chart.line.uptrend.xyaxis",
                                infoTitle: language.text("training.statistics"),
                                infoMessage: language.text("info.training.statistics")
                            )
                            HStack(alignment: .firstTextBaseline, spacing: HyseSpacing.small) {
                                Text("\(stats.workoutCount)")
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text(language.text("training.statistics.workouts"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            HStack(spacing: 0) {
                                heroMetric(language.text("training.statistics.duration"), aggregateDurationText(stats.totalDuration), "timer")
                                Divider().frame(height: 42)
                                heroMetric(language.text("training.statistics.volume"), aggregateVolumeText(stats.totalVolume), "scalemass")
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HyseSpacing.medium) {
                        metric("training.statistics.this_week", "\(stats.workoutsThisWeek)", "calendar")
                        metric("training.statistics.sets_this_week", TrainingSetStatistics.formatted(stats.setsThisWeek, locale: language.locale), "checklist")
                        metric("training.statistics.personal_records", "\(stats.personalRecordCount)", "medal.fill")
                        metric("training.statistics.streak", "\(stats.currentStreak)", "flame.fill")
                    }

                    HyseCard {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            HyseSectionHeading(title: language.text("training.statistics.frequency"), icon: "waveform.path.ecg")
                            valueRow(language.text("training.statistics.average_per_week"), stats.averageWorkoutsPerWeek.formatted(.number.precision(.fractionLength(1))), "calendar.badge.clock")
                            Divider()
                            valueRow(language.text("training.statistics.longest_streak"), "\(stats.longestStreak)", "trophy")
                        }
                    }

                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        HyseSectionHeading(title: language.text("training.statistics.volume_comparisons"), subtitle: language.text("training.statistics.comparison_note"), icon: "shippingbox.fill")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: HyseSpacing.medium) {
                                comparison(language.text("training.statistics.tonnes"), comparisonValue(stats.totalVolume / 1_000), "scalemass")
                                comparison(language.text("training.statistics.elephants"), comparisonValue(stats.totalVolume / 6_000), "pawprint.fill")
                                comparison(language.text("training.statistics.trucks"), comparisonValue(stats.totalVolume / 40_000), "truck.box.fill")
                                comparison(language.text("training.statistics.freight_trains"), comparisonValue(stats.totalVolume / 2_000_000), "train.side.front.car")
                            }
                        }
                        .contentMargins(.horizontal, 1, for: .scrollContent)
                    }

                    TrainingStatisticsDetails(store: store, exerciseSearchQuery: $exerciseSearchQuery)
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.top, HyseSpacing.small)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle(language.text("training.statistics"))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
    private func metric(_ key: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            HyseIconBadge(icon: icon, size: 32)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(language.text(key)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(HyseSpacing.large)
        .hyseGlassSurface(radius: HyseRadius.card)
    }

    private func heroMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HyseSpacing.medium)
    }

    private func valueRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon).foregroundStyle(HyseColor.accent).frame(width: 24)
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private func comparison(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Image(systemName: icon).font(.title3).foregroundStyle(HyseColor.accent)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
        .padding(HyseSpacing.large)
        .hyseGlassSurface(radius: HyseRadius.card)
    }

    private func aggregateDurationText(_ interval: TimeInterval) -> String {
        let seconds = max(0, interval)
        guard seconds >= 60 else { return durationText(seconds) }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = language.locale
        formatter.calendar = calendar

        switch seconds {
        case 0..<3_600: formatter.allowedUnits = [.minute]
        case 3_600..<86_400: formatter.allowedUnits = [.hour, .minute]
        default: formatter.allowedUnits = [.day, .hour]
        }
        return formatter.string(from: seconds) ?? durationText(seconds)
    }

    private func aggregateVolumeText(_ kilograms: Double) -> String {
        let value = max(0, kilograms)
        if value >= 1_000 {
            let tonnes = String(format: "%.1f", locale: language.locale, value / 1_000)
            return "\(tonnes) t"
        }
        let displayed = String(format: "%.0f", locale: language.locale, weightUnit.display(value))
        return "\(displayed) \(weightUnit.rawValue)"
    }

    private func comparisonValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 0...2 : 0...1)).locale(language.locale))
    }
}

struct TrainingHomeCard: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    let start: () -> Void
    let openTraining: () -> Void
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    var body: some View {
        HyseCard {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack { Label(t("training.home.title"), systemImage: "figure.strengthtraining.traditional").font(.headline); Spacer(); Button(t("training.home.details"), action: openTraining).font(.caption) }
                if store.hasResolvedPersistenceScope, let active = store.activeWorkout {
                    Button(action: start) { HStack { VStack(alignment: .leading) { Text(active.name).font(.headline); Text(t("training.active.resume")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "play.fill") } }.buttonStyle(.plain)
                } else {
                    let planned = store.routine(plannedFor: Date())
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(planned?.name ?? store.lastWorkout?.name ?? t("training.home.first_workout")).font(.headline)
                            Text(planned != nil ? t("training.home.planned_today") : store.lastWorkout == nil ? t("training.home.first_workout_message") : t("training.home.week_count", store.statistics.workoutsThisWeek)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { if let planned { _ = store.start(routine: planned) } else { _ = store.startEmptyWorkout() }; start() } label: { Label(t("training.start"), systemImage: "play.fill") }.buttonStyle(.borderedProminent)
                    }
                }
                HStack {
                    Label(t("training.home.streak", store.statistics.currentStreak), systemImage: store.statistics.trainedThisWeek ? "flame.fill" : "flame")
                        .foregroundStyle(store.statistics.trainedThisWeek ? HyseColor.streakFire : .secondary)
                    Spacer()
                    Text(store.recentMuscles.map { t("training.muscle.\($0)") }.joined(separator: " · ")).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let last = store.lastWorkout { Text(t("training.home.last_completed", last.name)).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

struct HealthOverviewView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var trainingStore: TrainingStore
    @ObservedObject var settings: UserSettingsStore
    @ObservedObject var health: HealthKitManager
    let isActive: Bool
    @State private var showingWeightEntry = false
    @State private var showingWeightPremium = false
    @State private var weightRange = TrainingChartRange.threeMonths
    @State private var selectedWeightDate: Date?
    @State private var selectedStepsDate: Date?
    @State private var selectedWorkoutWeekDate: Date?
    @State private var cachedWeightMeasurements: [BodyMeasurement] = []
    @State private var weightChartDataByRange: [TrainingChartRange: WeightChartData] = [:]

    private struct WeightChartPoint: Identifiable {
        let id: String
        let date: Date
        let kilograms: Double
    }

    private struct WeightChartData {
        let points: [WeightChartPoint]
        let markers: [WeightChartPoint]
    }

    private struct ActivityDay: Identifiable {
        let date: Date
        let steps: Int
        var id: Date { date }
    }

    private struct WorkoutWeek: Identifiable {
        let date: Date
        let workouts: Int
        var id: Date { date }
    }

    private var activityDays: [ActivityDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-6...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return ActivityDay(date: day, steps: health.steps(for: day))
        }
    }

    private var workoutWeeks: [WorkoutWeek] {
        let calendar = Calendar.current
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (-3...0).compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeek.start),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let count = trainingStore.completedWorkouts.filter { workout in
                let completed = workout.completedAt ?? workout.startedAt
                return completed >= start && completed < end
            }.count
            return WorkoutWeek(date: start, workouts: count)
        }
    }

    private func selectedActivityDay(in days: [ActivityDay]) -> ActivityDay? {
        guard let selectedStepsDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedStepsDate) }
    }

    private func selectedWorkoutWeek(in weeks: [WorkoutWeek]) -> WorkoutWeek? {
        guard let selectedWorkoutWeekDate else { return nil }
        return weeks.first { Calendar.current.isDate($0.date, equalTo: selectedWorkoutWeekDate, toGranularity: .weekOfYear) }
    }

    private func refreshActivityDays() {
        guard isActive else { return }
        for day in activityDays { health.refreshSteps(for: day.date) }
    }

    private func mergedWeightMeasurements() -> [BodyMeasurement] {
        var measurementsByID: [UUID: BodyMeasurement] = [:]
        for measurement in health.bodyWeights where measurement.weightKilograms != nil {
            measurementsByID[measurement.id] = measurement
        }
        for measurement in trainingStore.bodyMeasurements where measurement.weightKilograms != nil {
            measurementsByID[measurement.id] = measurement
        }
        return measurementsByID.values.sorted { $0.date < $1.date }
    }
    private var selectedWeightPoint: WeightChartPoint? {
        guard let selectedWeightDate else { return nil }
        return weightChartPoints.min {
            abs($0.date.timeIntervalSince(selectedWeightDate)) < abs($1.date.timeIntervalSince(selectedWeightDate))
        }
    }
    private var weightChartPoints: [WeightChartPoint] {
        weightChartDataByRange[weightRange]?.points ?? []
    }
    private var weightMarkerPoints: [WeightChartPoint] {
        weightChartDataByRange[weightRange]?.markers ?? []
    }
    private func nearestChartDate(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, dates: [Date]) -> Date? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        let x = location.x - frame.minX
        guard x >= 0, x <= frame.width,
              let selected = proxy.value(atX: x, as: Date.self) else { return nil }
        return dates.min { abs($0.timeIntervalSince(selected)) < abs($1.timeIntervalSince(selected)) }
    }
    private var weightChartDomain: ClosedRange<Double> {
        let values = weightChartPoints.map(\.kilograms).filter { $0.isFinite && $0 > 0 }
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let lowerKilograms = max(0, minimum - 5)
        let upperKilograms = max(lowerKilograms + 1, maximum + 5)
        return settings.trainingWeightUnit.display(lowerKilograms)...settings.trainingWeightUnit.display(upperKilograms)
    }

    private var hasWeightChartPremium: Bool {
        premium.hasNutrition || premium.hasTraining
    }

    private var weightRangeSelection: Binding<TrainingChartRange> {
        Binding(
            get: { weightRange },
            set: { value in
                if (value == .oneYear || value == .allTime) && !hasWeightChartPremium {
                    showingWeightPremium = true
                } else {
                    weightRange = value
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                        healthConnectionCard

                        HyseCard(accent: HyseColor.accent) {
                            VStack(alignment: .leading, spacing: HyseSpacing.large) {
                                HyseSectionHeading(
                                    title: language.text("health.weight.title"),
                                    subtitle: cachedWeightMeasurements.last.flatMap(\.weightKilograms).map { formattedWeight($0) },
                                    icon: "scalemass.fill",
                                    infoTitle: language.text("health.weight.title"),
                                    infoMessage: language.text("info.health.weight")
                                )

                    HyseSegmentedControl(
                        items: TrainingWeightUnit.allCases,
                        selection: $settings.trainingWeightUnit,
                        title: { language.text($0.localizationKey) },
                        symbol: { _ in "scalemass" }
                    )
                    HyseSegmentedControl(
                        items: TrainingChartRange.allCases,
                        selection: weightRangeSelection,
                        title: { language.text($0.localizationKey) },
                        symbol: {
                            ($0 == .oneYear || $0 == .allTime) && !hasWeightChartPremium
                                ? "crown.fill"
                                : rangeSymbol($0)
                        }
                    )
                    if weightChartPoints.isEmpty {
                        HyseEmptyState(icon: "chart.xyaxis.line", title: language.text("health.weight.empty_title"), message: language.text("health.weight.empty_message"))
                    } else {
                        Chart {
                            ForEach(weightChartPoints) { point in
                                LineMark(
                                    x: .value(language.text("health.weight.date"), point.date),
                                    y: .value(language.text("health.weight.title"), settings.trainingWeightUnit.display(point.kilograms))
                                )
                                .foregroundStyle(HyseColor.accent)
                                .interpolationMethod(.linear)
                            }
                            ForEach(weightMarkerPoints) { point in
                                PointMark(
                                    x: .value(language.text("health.weight.date"), point.date),
                                    y: .value(language.text("health.weight.title"), settings.trainingWeightUnit.display(point.kilograms))
                                )
                                .foregroundStyle(HyseColor.accent)
                            }
                            if let selectedWeightPoint {
                                RuleMark(x: .value(language.text("health.weight.date"), selectedWeightPoint.date))
                                    .foregroundStyle(.secondary.opacity(0.55))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                PointMark(
                                    x: .value(language.text("health.weight.date"), selectedWeightPoint.date),
                                    y: .value(language.text("health.weight.title"), settings.trainingWeightUnit.display(selectedWeightPoint.kilograms))
                                )
                                .foregroundStyle(HyseColor.accent)
                                .symbolSize(70)
                                .annotation(position: .top) {
                                    weightSelectionLabel(selectedWeightPoint)
                                }
                            }
                        }
                        .frame(height: 190)
                        .chartYScale(domain: weightChartDomain)
                        .transaction { $0.animation = nil }
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle().fill(.clear).contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                                        if let date = nearestChartDate(at: gesture.location, proxy: proxy, geometry: geometry,
                                                                       dates: weightChartPoints.map(\.date)) {
                                            selectedWeightDate = date
                                        }
                                    })
                            }
                        }
                        .accessibilityLabel(language.text("health.weight.chart_accessibility"))
                    }
                    Button { showingWeightEntry = true } label: {
                        Label(language.text("health.weight.add"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(HysePrimaryButtonStyle())
                    if let message = health.lastWeightSyncMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                            }
                        }

                        healthActivityCard
                        if settings.trackingInterest.includesTraining {
                            healthTrainingCard
                        }
                    }
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.top, HyseSpacing.small)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle(language.text("health.overview.title"))
                .onAppear {
                    refreshWeightData()
                    if isActive {
                        health.refreshBodyWeights()
                        refreshActivityDays()
                    }
                }
                .onChange(of: isActive) { _, active in
                    if active {
                        health.refreshBodyWeights()
                        refreshActivityDays()
                    }
                }
                .onChange(of: weightRange) { _, _ in
                    selectedWeightDate = nil
                }
                .onChange(of: settings.trainingWeightUnit) { _, _ in selectedWeightDate = nil }
                .onReceive(health.$bodyWeights) { _ in refreshWeightData() }
                .onReceive(trainingStore.$bodyMeasurements) { _ in refreshWeightData() }
                .sheet(isPresented: $showingWeightEntry) {
                    WeightEntryView(store: trainingStore, settings: settings, health: health)
                }
                .sheet(isPresented: $showingWeightPremium) {
                    PremiumPaywallView()
                }
        }
    }

    private var healthConnectionCard: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(spacing: HyseSpacing.large) {
                    HyseIconBadge(icon: "heart.text.clipboard.fill", size: 50)
                    VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                        Text(language.text("settings.apple_health"))
                            .font(.headline)
                        Text(health.isAuthorized ? language.text("settings.apple_health_connected") : language.text("settings.apple_health_connect"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    HyseInfoButton(
                        title: language.text("settings.apple_health"),
                        message: language.text("info.health.connection")
                    )
                    Image(systemName: health.isAuthorized ? "checkmark.circle.fill" : "heart")
                        .foregroundStyle(health.isAuthorized ? HyseColor.success : HyseColor.accent)
                }
                if !health.isAuthorized {
                    Button(language.text("settings.apple_health_connect")) {
                        health.requestAuthorization()
                    }
                    .buttonStyle(HyseSecondaryButtonStyle())
                }
            }
        }
        .hyseTourTarget(.health)
    }

    private var healthActivityCard: some View {
        let days = activityDays
        let selectedDay = selectedActivityDay(in: days)
        let recordedDays = days.filter { $0.steps > 0 }
        let average = recordedDays.isEmpty ? 0 : recordedDays.reduce(0) { $0 + $1.steps } / recordedDays.count
        return HyseCard {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HyseSectionHeading(
                    title: language.text("health.overview.steps_title"),
                    subtitle: language.text("health.overview.last_seven_days"),
                    icon: "figure.walk",
                    infoTitle: language.text("health.overview.steps_title"),
                    infoMessage: language.text("info.health.steps")
                )
                if recordedDays.isEmpty {
                    HyseEmptyState(
                        icon: "figure.walk",
                        title: language.text("health.overview.steps_empty_title"),
                        message: language.text(health.isAuthorized ? "health.overview.steps_empty_connected" : "health.overview.steps_empty_disconnected")
                    )
                } else {
                    Chart {
                        ForEach(days) { day in
                            BarMark(x: .value(language.text("health.weight.date"), day.date, unit: .day),
                                    y: .value(language.text("health.overview.steps_title"), Double(day.steps)))
                                .foregroundStyle(selectedDay == nil || selectedDay?.id == day.id ? HyseColor.accent : HyseColor.accent.opacity(0.35))
                                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                    if selectedDay?.id == day.id {
                                        chartSelectionLabel(
                                            value: "\(day.steps.formatted(.number.locale(language.locale))) \(language.text("health.overview.steps_title"))",
                                            date: day.date.formatted(.dateTime.day().month().year().locale(language.locale))
                                        )
                                    }
                                }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: days.map(\.date)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        }
                    }
                    .frame(height: 150)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                                    selectedStepsDate = ChartBarSelection.date(
                                        at: gesture.location, proxy: proxy, geometry: geometry,
                                        bars: days.map { ($0.date, Double($0.steps)) }, unit: .day
                                    )
                                })
                        }
                    }
                    .accessibilityLabel(language.text("health.overview.steps_chart_accessibility"))
                    metric(language.text("health.overview.steps_average"), average.formatted(.number.locale(language.locale)), "figure.walk")
                }
            }
        }
    }

    private var healthTrainingCard: some View {
        let weeks = workoutWeeks
        let selectedWeek = selectedWorkoutWeek(in: weeks)
        let total = weeks.reduce(0) { $0 + $1.workouts }
        let firstWeek = weeks.first?.date ?? Date()
        let trainingDays = Set(trainingStore.completedWorkouts.compactMap { workout -> Date? in
            let completed = workout.completedAt ?? workout.startedAt
            guard completed >= firstWeek && completed <= Date() else { return nil }
            return Calendar.current.startOfDay(for: completed)
        }).count
        return HyseCard {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HyseSectionHeading(
                    title: language.text("health.overview.training"),
                    subtitle: language.text("health.overview.last_four_weeks"),
                    icon: "figure.strengthtraining.traditional",
                    infoTitle: language.text("health.overview.training"),
                    infoMessage: language.text("info.health.training")
                )
                if total == 0 {
                    HyseEmptyState(icon: "figure.strengthtraining.traditional", title: language.text("health.overview.training_empty_title"), message: language.text("health.overview.training_empty_message"))
                } else {
                    Chart {
                        ForEach(weeks) { week in
                            BarMark(x: .value(language.text("health.overview.week"), week.date, unit: .weekOfYear),
                                    y: .value(language.text("training.statistics.workouts"), Double(week.workouts)))
                                .foregroundStyle(selectedWeek == nil || selectedWeek?.id == week.id ? HyseColor.accent : HyseColor.accent.opacity(0.35))
                                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                    if selectedWeek?.id == week.id {
                                        chartSelectionLabel(
                                            value: "\(week.workouts.formatted(.number.locale(language.locale))) \(language.text("training.statistics.workouts"))",
                                            date: workoutWeekLabel(week.date)
                                        )
                                    }
                                }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: weeks.map(\.date)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        }
                    }
                    .frame(height: 150)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                                    selectedWorkoutWeekDate = ChartBarSelection.date(
                                        at: gesture.location, proxy: proxy, geometry: geometry,
                                        bars: weeks.map { ($0.date, Double($0.workouts)) }, unit: .weekOfYear
                                    )
                                })
                        }
                    }
                    .accessibilityLabel(language.text("health.overview.training_chart_accessibility"))
                    metric(language.text("training.statistics.workouts"), "\(total)", "calendar")
                    metric(language.text("health.overview.training_days"), "\(trainingDays)", "checkmark.circle")
                }
                NavigationLink { TrainingStatisticsView(store: trainingStore) } label: {
                    HStack(spacing: HyseSpacing.medium) {
                        HyseIconBadge(icon: "chart.line.uptrend.xyaxis", size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.text("health.overview.open_training_progress"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(language.text("training.statistics.subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(HyseColor.accent)
                    }
                    .padding(HyseSpacing.medium)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hyseGlassSurface(radius: HyseRadius.control, tint: HyseColor.accent)
            }
        }
    }
    private func formattedWeight(_ kilograms: Double) -> String {
        "\(settings.trainingWeightUnit.display(kilograms).formatted(.number.precision(.fractionLength(0...1)))) \(settings.trainingWeightUnit.rawValue)"
    }
    private func rangeSymbol(_ range: TrainingChartRange) -> String {
        switch range {
        case .oneMonth: "calendar"
        case .threeMonths: "calendar.badge.clock"
        case .oneYear: "calendar.circle"
        case .allTime: "infinity"
        }
    }
    private func weightSelectionLabel(_ point: WeightChartPoint) -> some View {
        VStack(spacing: 2) {
            Text(formattedWeight(point.kilograms)).font(.caption.weight(.bold)).monospacedDigit()
            Text(weightPeriodLabel(point)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .hyseGlassSurface(radius: HyseRadius.small)
    }
    private func chartSelectionLabel(value: String, date: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.bold)).monospacedDigit()
            Text(date).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .hyseGlassSurface(radius: HyseRadius.small)
    }
    private func workoutWeekLabel(_ start: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let startText = start.formatted(.dateTime.day().month(.abbreviated).locale(language.locale))
        let endText = end.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale))
        return "\(startText) – \(endText)"
    }
    private func weightPeriodLabel(_ point: WeightChartPoint) -> String {
        point.date.formatted(.dateTime.day().month().year().locale(language.locale))
    }
    private func refreshWeightData() {
        let measurements = mergedWeightMeasurements()
        cachedWeightMeasurements = measurements
        weightChartDataByRange = Self.makeWeightChartData(from: measurements)
        selectedWeightDate = nil
    }
    private static func makeWeightChartData(from measurements: [BodyMeasurement], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> [TrainingChartRange: WeightChartData] {
        let allPoints = measurements.compactMap { measurement -> WeightChartPoint? in
            guard let kilograms = measurement.weightKilograms else { return nil }
            return WeightChartPoint(id: measurement.id.uuidString, date: measurement.date, kilograms: kilograms)
        }
        return TrainingChartRange.allCases.reduce(into: [:]) { data, range in
            let start: Date?
            switch range {
            case .oneMonth: start = calendar.date(byAdding: .month, value: -1, to: now)
            case .threeMonths: start = calendar.date(byAdding: .month, value: -3, to: now)
            case .oneYear: start = calendar.date(byAdding: .year, value: -1, to: now)
            case .allTime: start = nil
            }
            let points = start.map { cutoff in
                allPoints.filter { $0.date >= cutoff && $0.date <= now }
            } ?? allPoints
            let markers: [WeightChartPoint]
            if range == .oneMonth {
                markers = points
            } else {
                let component: Calendar.Component = range == .threeMonths ? .weekOfYear : .month
                let groups = Dictionary(grouping: points) { point in
                    calendar.dateInterval(of: component, for: point.date)?.start ?? calendar.startOfDay(for: point.date)
                }
                let markerIDs = Set(groups.values.compactMap { group in
                    group.max(by: { $0.date < $1.date })?.id
                })
                markers = points.filter { markerIDs.contains($0.id) }
            }
            data[range] = WeightChartData(points: points, markers: markers)
        }
    }
    private func metric(_ name: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HyseColor.accent)
                .frame(width: 24)
            Text(name)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct WeightEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    @ObservedObject var settings: UserSettingsStore
    @ObservedObject var health: HealthKitManager
    @State private var weightText = ""
    @State private var date = Date()

    private var enteredWeight: Double? {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(language.text("health.weight.value"), text: $weightText).keyboardType(.decimalPad)
                        Text(settings.trainingWeightUnit.rawValue).foregroundStyle(.secondary)
                    }
                    DatePicker(language.text("health.weight.date"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text(health.isAuthorized ? language.text("health.weight.health_connected_note") : language.text("health.weight.health_pending_note"))
                        .font(.caption)
                }
            }
            .hyseForm()
            .navigationTitle(language.text("health.weight.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("app_tabs.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("add_entry.done")) {
                        guard let displayed = enteredWeight else { return }
                        let measurement = store.addBodyWeight(kilograms: settings.trainingWeightUnit.kilograms(displayed), date: date)
                        health.saveBodyWeight(id: measurement.id, kilograms: measurement.weightKilograms ?? 0, date: measurement.date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(enteredWeight == nil)
                }
            }
        }
        .presentationDetents([.height(300), .large])
    }
}

struct ContentReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    let target: ContentReportTarget
    @State private var reason: ContentReportReason = .illegal
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var submitted = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(target.displayName, systemImage: "flag")
                    Picker(t("content_reports.reason_title"), selection: $reason) {
                        ForEach(ContentReportReason.allCases) { value in
                            Text(t(value.localizationKey)).tag(value)
                        }
                    }
                } header: {
                    Text(t("content_reports.report_title"))
                }
                Section {
                    TextEditor(text: $details)
                        .frame(minHeight: 130)
                    HStack {
                        Text(t("content_reports.details_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(details.count)/2000")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(HyseColor.warning) }
                }
                if submitted {
                    Section {
                        Label(t("content_reports.received"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(HyseColor.success)
                        Text(t("content_reports.received_detail"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(t("content_reports.good_faith"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .hyseForm()
            .navigationTitle(t("content_reports.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitted {
                        Button(t("common.ok")) { dismiss() }
                    } else {
                        Button(t("content_reports.submit")) { submit() }
                            .disabled(isSubmitting || details.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true; errorMessage = nil
        Task {
            do {
                _ = try await ContentReportService.shared.submit(target: target, reason: reason, details: details.trimmingCharacters(in: .whitespacesAndNewlines), token: auth.token)
                submitted = true
            } catch {
                errorMessage = error.localizedDescription == "content_reports.error" ? t("content_reports.error") : error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

struct ContentReportsView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    @State private var reports: [ContentReport] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var appealReport: ContentReport?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ZStack {
            HyseBackdrop()
            if isLoading && reports.isEmpty { ProgressView() }
            else if reports.isEmpty {
                HyseEmptyState(icon: "flag", title: t("content_reports.empty"), message: t("content_reports.empty_message"))
                    .padding(HyseSpacing.page)
            } else {
                List(reports) { report in
                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        HStack {
                            Text(report.targetLabel.isEmpty ? t("content_reports.reported_item") : report.targetLabel).font(.headline)
                            Spacer()
                            Text(t("content_reports.status.\(report.status)"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(report.status == "no_action" ? .secondary : HyseColor.accent)
                        }
                        Text(t(report.reason.localizationKey)).font(.caption).foregroundStyle(.secondary)
                        if !report.decisionReason.isEmpty {
                            Text(report.decisionReason).font(.caption).foregroundStyle(.secondary)
                        }
                        if ["action_taken", "no_action", "closed"].contains(report.status) {
                            Button(t("content_reports.appeal")) { appealReport = report }
                                .font(.caption.weight(.semibold))
                                .disabled(report.status == "closed")
                        }
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(t("content_reports.my_reports"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $appealReport) { report in
            ContentReportAppealSheet(report: report) { updated in
                reports = reports.map { $0.id == updated.id ? updated : $0 }
                appealReport = nil
            }
        }
        .alert(t("settings.error"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(t("common.ok")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        guard auth.isLoggedIn, !auth.token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do { reports = try await ContentReportService.shared.list(token: auth.token) }
        catch { errorMessage = error.localizedDescription == "content_reports.error" ? t("content_reports.error") : error.localizedDescription }
    }
}

private struct ContentReportAppealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    let report: ContentReport
    let onCompleted: (ContentReport) -> Void
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(t("content_reports.appeal_explanation")) .font(.subheadline) }
                Section {
                    TextEditor(text: $details).frame(minHeight: 150)
                    Text("\(details.count)/2000").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(HyseColor.warning) } }
            }
            .hyseForm()
            .navigationTitle(t("content_reports.appeal"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("app_tabs.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("content_reports.submit")) { submit() }
                        .disabled(isSubmitting || details.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                }
            }
        }
    }

    private func submit() {
        isSubmitting = true; errorMessage = nil
        Task {
            do {
                let updated = try await ContentReportService.shared.appeal(reportID: report.id, details: details.trimmingCharacters(in: .whitespacesAndNewlines), token: auth.token)
                onCompleted(updated); dismiss()
            } catch {
                errorMessage = error.localizedDescription == "content_reports.error" ? t("content_reports.error") : error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

nonisolated func durationText(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    if seconds >= 3_600 {
        return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

nonisolated func activeWorkoutDurationText(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    guard seconds >= 3_600 else { return String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
}
