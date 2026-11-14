import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import CoreTransferable
import Charts
import Combine

struct ActiveWorkoutBar: View {
    @EnvironmentObject private var language: LanguageStore
    let workout: WorkoutLog
    let discard: () -> Void
    let open: () -> Void
    @State private var showingDiscardConfirmation = false
    private var currentExercise: String {
        guard let exercise = workout.exercises.first(where: { $0.sets.contains(where: { !$0.completed }) })
            ?? workout.exercises.last else {
            return language.text("training.exercise.add")
        }
        return language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty
            ? exercise.exerciseGermanNameSnapshot : exercise.exerciseNameSnapshot
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                Image(systemName: "chevron.up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(HyseColor.elevatedSurface, in: Circle())
                    .frame(width: 64, height: 68)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("training.active.resume"))

            Button(action: open) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(workout.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(activeWorkoutDurationText(workout.duration))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text(currentExercise)
                                .lineLimit(1)
                            if workout.status == .paused {
                                Image(systemName: "pause.fill")
                                Text(language.text("training.paused"))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(workout.name), \(currentExercise)")
            .accessibilityHint(language.text("training.active.open_hint"))

            Button {
                showingDiscardConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HyseColor.danger)
                    .frame(width: 48, height: 48)
                    .background(HyseColor.elevatedSurface, in: Circle())
                    .frame(width: 64, height: 68)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("training.discard"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .hyseGlassSurface(radius: HyseRadius.card)
        .padding(.horizontal, HyseSpacing.medium)
        .zIndex(1)
        .alert(language.text("training.discard.confirm_title"), isPresented: $showingDiscardConfirmation) {
            Button(language.text("training.continue"), role: .cancel) {}
            Button(language.text("training.discard"), role: .destructive, action: discard)
        } message: {
            Text(language.text("training.discard.confirm_message"))
        }
    }
}

struct ExerciseNamePositionPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct WorkoutKeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> DismissView {
        let view = DismissView()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: DismissView, context: Context) {}
    static func dismantleUIView(_ view: DismissView, coordinator: ()) { view.detach() }

    final class DismissView: UIView, UIGestureRecognizerDelegate {
        private weak var observedWindow: UIWindow?
        private lazy var tapRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard observedWindow !== window else { return }
            detach()
            observedWindow = window
            window?.addGestureRecognizer(tapRecognizer)
        }

        func detach() {
            observedWindow?.removeGestureRecognizer(tapRecognizer)
            observedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touchedView: UIView? = touch.view
            while let view = touchedView {
                if view is UITextField || view is UITextView { return false }
                touchedView = view.superview
            }
            return true
        }

        @objc private func dismissKeyboard() { observedWindow?.endEditing(true) }
    }
}

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @ObservedObject var store: TrainingStore
    let animateToLatestCompletedExercise: Bool
    @State private var showingExercises = false
    @State private var showingMuscleDistribution = false
    @State private var showingFinish = false
    @State private var showingDiscard = false
    @State private var reorderSession: WorkoutReorderSession?
    @State private var showingReorderOverlay = false
    @State private var exerciseCardLayoutID = UUID()
    @State private var completionDraft: WorkoutLog?
    @State private var completedSummary: WorkoutLog?
    @State private var highlightedExerciseID: UUID?
    @State private var addedExerciseNotice: WorkoutExerciseAdditionNotice?
    @State private var restTimerExpanded = false
    @State private var keyboardVisible = false
    @Namespace private var restTimerAnimation
    private let reorderTransitionDuration = 0.24
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var removedExerciseName: String? {
        guard let exercise = store.removedExerciseForUndo else { return nil }
        return language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty
            ? exercise.exerciseGermanNameSnapshot : exercise.exerciseNameSnapshot
    }

    private func finishExerciseReorder() {
        guard let session = reorderSession else { return }
        if let destination = session.orderedIDs.firstIndex(of: session.exerciseID),
           destination != session.initialIndex {
            store.moveExercises(
                from: IndexSet(integer: session.initialIndex),
                to: destination > session.initialIndex ? destination + 1 : destination
            )
            exerciseCardLayoutID = UUID()
        }
        ExerciseReorderFeedback.dropped()
        withAnimation(.easeInOut(duration: reorderTransitionDuration)) {
            showingReorderOverlay = false
        }
        let finishedID = session.exerciseID
        DispatchQueue.main.asyncAfter(deadline: .now() + reorderTransitionDuration) {
            guard !showingReorderOverlay, reorderSession?.exerciseID == finishedID else { return }
            reorderSession = nil
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let completionDraft {
                    WorkoutCompletionEditor(
                        workout: completionDraft,
                        store: store,
                        appliesDefaultPreferences: true,
                        onSave: { saved in
                            store.updateCompletedWorkout(saved)
                            self.completionDraft = nil
                            completedSummary = saved
                        },
                        onDiscard: {
                            store.deleteCompletedWorkout(completionDraft.id)
                            self.completionDraft = nil
                            dismiss()
                        }
                    )
                } else if let completedSummary {
                    WorkoutCelebrationView(
                        workout: completedSummary,
                        workoutNumber: max(1, store.completedWorkouts.count),
                        recentWorkouts: store.completedWorkouts,
                        store: store,
                        onDone: { dismiss() }
                    )
                } else if let workout = store.activeWorkout {
                    VStack(spacing: 0) {
                        workoutHeader(workout)
                        ZStack {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(spacing: HyseSpacing.large) {
                                        ForEach(workout.exercises) { exercise in
                                            WorkoutExerciseCard(
                                                exercise: exercise,
                                                store: store,
                                                highlighted: highlightedExerciseID == exercise.id,
                                                onReorderBegan: { fingerY in
                                                    if reorderSession == nil,
                                                       let index = workout.exercises.firstIndex(where: { $0.id == exercise.id }) {
                                                        reorderSession = WorkoutReorderSession(
                                                            exerciseID: exercise.id,
                                                            initialIndex: index,
                                                            sourceCenterY: fingerY,
                                                            fingerStartY: fingerY,
                                                            fingerY: fingerY,
                                                            orderedIDs: workout.exercises.map(\.id)
                                                        )
                                                        ExerciseReorderFeedback.pickedUp()
                                                        withAnimation(.easeInOut(duration: reorderTransitionDuration)) {
                                                            showingReorderOverlay = true
                                                        }
                                                    }
                                                },
                                                onReorderChanged: { fingerY in
                                                    guard reorderSession?.exerciseID == exercise.id else { return }
                                                    reorderSession?.fingerY = fingerY
                                                },
                                                onReorderEnded: finishExerciseReorder
                                            )
                                                .id(exercise.id)
                                        }
                                        workoutActions(workout)
                                    }
                                    .padding(.vertical, HyseSpacing.large)
                                    .id(exerciseCardLayoutID)
                                }
                                .scrollDismissesKeyboard(.interactively)
                                .task(id: workout.id) {
                                    guard let target = latestCompletedSet(in: workout) else { return }
                                    await Task.yield()
                                    guard !Task.isCancelled else { return }
                                    if animateToLatestCompletedExercise {
                                        if let firstExercise = workout.exercises.first {
                                            proxy.scrollTo(firstExercise.id, anchor: .top)
                                        }
                                        try? await Task.sleep(for: .milliseconds(400))
                                        guard !Task.isCancelled else { return }
                                        withAnimation(.easeInOut(duration: 0.6)) {
                                            proxy.scrollTo(target.exerciseID, anchor: .top)
                                        }
                                        return
                                    }
                                    // Materialize the lazy exercise card before targeting its set row.
                                    proxy.scrollTo(target.exerciseID, anchor: .top)
                                    try? await Task.sleep(for: .milliseconds(120))
                                    guard !Task.isCancelled else { return }
                                    proxy.scrollTo(target.setID, anchor: .center)
                                }
                                .onChange(of: highlightedExerciseID) { _, value in guard let value else { return }; withAnimation { proxy.scrollTo(value, anchor: .center) }; Task { try? await Task.sleep(for: .seconds(1.2)); highlightedExerciseID = nil } }
                            }
                            .animation(nil, value: workout.exercises.map(\.id))
                            .opacity(showingReorderOverlay ? 0 : 1)

                            if reorderSession != nil {
                                WorkoutExerciseReorderList(
                                    exercises: workout.exercises,
                                    visuals: store.exercises,
                                    session: $reorderSession
                                )
                                .opacity(showingReorderOverlay ? 1 : 0)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                            }
                            PersonalRecordBannerOverlay(
                                presentation: store.personalRecordPresentation,
                                onDismiss: store.clearPersonalRecordFeedback
                            )
                            .zIndex(2)
                            if let addedExerciseNotice {
                                WorkoutExerciseAddedToast(text: addedExerciseNotice.text)
                                    .padding(.horizontal, HyseSpacing.page)
                                    .padding(.top, HyseSpacing.small)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                    .allowsHitTesting(false)
                                    .zIndex(3)
                            }
                        }
                    }
                    .background(HyseBackdrop())
                    .background(WorkoutKeyboardDismissInstaller())
                } else { HyseEmptyState(icon: "checkmark.circle", title: t("training.no_active.title"), message: t("training.no_active.message"), actionTitle: t("add_entry.done"), action: { dismiss() }) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if completionDraft == nil && completedSummary == nil && !showingReorderOverlay {
                VStack(spacing: 0) {
                    if store.exerciseRemovalUndoID != nil {
                        HyseUndoNotice(
                            title: t("training.exercise.removed"),
                            detail: removedExerciseName,
                            actionTitle: t("training.undo"),
                            action: store.undoLastExerciseRemoval
                        )
                        .padding(.vertical, HyseSpacing.medium)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if store.restTimerEnd != nil {
                        bottomRestTimer
                    } else if keyboardVisible {
                        HStack {
                            Spacer(minLength: 0)
                            keyboardDismissButton
                        }
                        .padding(.trailing, 10)
                        .padding(.vertical, HyseSpacing.small)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
            .toolbar(completionDraft == nil && completedSummary == nil ? .hidden : .visible, for: .navigationBar)
        }
        .animation(HyseMotion.quick, value: store.exerciseRemovalUndoID)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
            restTimerExpanded = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onChange(of: store.restTimerEnd) { oldEnd, newEnd in
            // Every newly started timer opens in the compact layout. Changing
            // the duration while it is already running keeps the user's view.
            if (oldEnd == nil) != (newEnd == nil) {
                restTimerExpanded = false
            }
        }
        .sheet(isPresented: $showingExercises) {
            ExerciseLibraryView(store: store, selectionMode: true, onAdded: { id, name, count in
                highlightedExerciseID = id
                let text = count == 1
                    ? t("training.exercise.added", name)
                    : t("training.completion.changes.exercise_added.many", count)
                withAnimation(.easeOut(duration: 0.18)) {
                    addedExerciseNotice = WorkoutExerciseAdditionNotice(text: text)
                }
            })
        }
        .task(id: addedExerciseNotice?.id) {
            guard addedExerciseNotice != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { addedExerciseNotice = nil }
        }
        .sheet(isPresented: $showingMuscleDistribution) {
            ActiveWorkoutMuscleDistributionView(counts: activeWorkoutMuscleCounts)
                .environmentObject(language)
        }
        .sheet(isPresented: $showingFinish) {
            if let workout = store.activeWorkout {
                WorkoutFinishConfirmationView(
                    workout: workout,
                    onCancel: { showingFinish = false },
                    onConfirm: {
                        showingFinish = false
                        completionDraft = store.finishActiveWorkout()
                    }
                )
                .environmentObject(language)
                .presentationDetents([.height(workout.completedSets.isEmpty ? 500 : 430)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
        .alert(t("training.discard.confirm_title"), isPresented: $showingDiscard) {
            Button(t("training.continue"), role: .cancel) {}
            Button(t("training.discard"), role: .destructive) { store.discardActiveWorkout(); dismiss() }
        } message: { Text(t("training.discard.confirm_message")) }
        .dynamicTypeSize(.small)
    }

    private func latestCompletedSet(in workout: WorkoutLog) -> (exerciseID: UUID, setID: UUID)? {
        let completed = workout.exercises.flatMap { exercise in
            exercise.sets.filter(\.completed).map { set in
                (exerciseID: exercise.id, setID: set.id, completedAt: set.completedAt ?? .distantPast)
            }
        }
        guard let latest = completed.enumerated().max(by: { lhs, rhs in
            lhs.element.completedAt == rhs.element.completedAt
                ? lhs.offset < rhs.offset
                : lhs.element.completedAt < rhs.element.completedAt
        })?.element else { return nil }
        return (latest.exerciseID, latest.setID)
    }

    private func workoutHeader(_ workout: WorkoutLog) -> some View {
        let progress = TrainingSetStatistics.progress(workout)
        let muscleCounts = completedMuscleCounts(in: workout)
        return VStack(spacing: HyseSpacing.medium) {
            HStack(spacing: HyseSpacing.medium) {
                Button { store.flushPendingChanges(); dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(HyseColor.elevatedSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("training.close"))

                TextField(t("training.workout.name"), text: Binding(get: { workout.name }, set: store.renameActiveWorkout))
                    .font(.headline.weight(.bold))
                    .textFieldStyle(.plain)
                    .lineLimit(1)

                Button { store.toggleWorkoutPause() } label: {
                    Image(systemName: workout.status == .paused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(HyseColor.elevatedSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t(workout.status == .paused ? "training.resume" : "training.pause"))

                Button(t("training.finish")) { showingFinish = true }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(HyseColor.accent, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(workout.completedSets.isEmpty)
                    .opacity(workout.completedSets.isEmpty ? 0.45 : 1)
            }

            ProgressView(value: progress)
                .tint(HyseColor.accent)

            HStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    workoutMetric(t("training.duration"), activeWorkoutDurationText(workout.duration))
                }
                workoutMetric(t("training.total_volume"), compactWeight(workout.totalVolume))
                workoutMetric(t("training.completed_sets"), TrainingSetStatistics.formatted(TrainingSetStatistics.count(workout, halveUnilateral: halveUnilateral), locale: language.locale))
                Button { showingMuscleDistribution = true } label: {
                    DetailedTrainingMuscleBody(counts: muscleCounts)
                        .frame(width: 78, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("training.active.trained_muscles"))
            }
            .frame(maxWidth: .infinity)

            if workout.syncError { Label(t("training.sync.pending"), systemImage: "icloud.slash").font(.caption).foregroundStyle(HyseColor.warning) }
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.small)
        .padding(.bottom, HyseSpacing.large)
        .background(HyseColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(HyseColor.border).frame(height: 1) }
    }

    private func workoutMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(HyseColor.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeWorkoutMuscleCounts: [String: Double] {
        store.activeWorkout.map { completedMuscleCounts(in: $0) } ?? [:]
    }

    private func completedMuscleCounts(in workout: WorkoutLog) -> [String: Double] {
        workout.exercises.reduce(into: [String: Double]()) { result, exercise in
            let completedSets = TrainingSetStatistics.count(exercise, halveUnilateral: halveUnilateral)
            guard completedSets > 0 else { return }
            let catalogExercise = store.exercises.first { $0.id == exercise.exerciseID }
            let source = catalogExercise ?? TrainingExercise(
                id: exercise.exerciseID,
                nameKey: "workout_snapshot",
                englishName: exercise.exerciseNameSnapshot,
                germanName: exercise.exerciseGermanNameSnapshot,
                descriptionKey: "",
                techniqueKey: "",
                type: exercise.exerciseTypeSnapshot,
                equipment: exercise.equipmentSnapshot,
                primaryMuscles: exercise.primaryMusclesSnapshot,
                secondaryMuscles: exercise.secondaryMusclesSnapshot,
                isCustom: true,
                isFavorite: false,
                updatedAt: .distantPast
            )
            let corrected = TrainingExercise.repairedMuscleAssignment(
                exerciseID: source.id,
                englishName: source.englishName,
                germanName: source.germanName,
                type: source.type,
                equipment: source.equipment,
                primary: source.primaryMuscles,
                secondary: source.secondaryMuscles
            )
            let primaryMuscles = corrected?.primary ?? source.primaryMuscles
            let secondaryMuscles = corrected?.secondary ?? source.secondaryMuscles
            let weightedRegions = TrainingMuscleRegionMap.weightedRegions(
                primary: primaryMuscles,
                secondary: secondaryMuscles
            )
            for (muscle, weight) in weightedRegions {
                result[muscle, default: 0] += completedSets * weight
            }
        }
    }

    private func compactWeight(_ kilograms: Double) -> String {
        guard kilograms.isFinite else { return "— kg" }
        // The live header has only one third of the available width. Keep the
        // exact kg reading for normal workouts, then use tonnes once a long
        // grouped number would be truncated or scaled down into illegibility.
        if abs(kilograms) >= 10_000 {
            return "\((kilograms / 1_000).formatted(.number.precision(.fractionLength(0...1)))) t"
        }
        let value = kilograms.formatted(.number.precision(.fractionLength(0...1)))
        return "\(value) kg"
    }

    private func workoutActions(_ workout: WorkoutLog) -> some View {
        VStack(spacing: HyseSpacing.medium) {
            Button { showingExercises = true } label: {
                Label(t("training.exercise.add"), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HysePrimaryButtonStyle())
            HStack(spacing: HyseSpacing.medium) {
                Button { store.toggleWorkoutPause() } label: {
                    Label(t(workout.status == .paused ? "training.resume" : "training.pause"), systemImage: workout.status == .paused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HyseSecondaryButtonStyle())
                Button(role: .destructive) { showingDiscard = true } label: {
                    Label(t("training.discard"), systemImage: "trash")
                        .foregroundStyle(HyseColor.danger)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HyseSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.bottom, 96)
    }

    @ViewBuilder private var bottomRestTimer: some View {
        if let end = store.restTimerEnd {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(uiColor: .systemBlue))
                    .frame(height: 3)
                Group {
                    if restTimerExpanded && !keyboardVisible {
                        VStack(spacing: HyseSpacing.large) {
                            restTimerValue(end, fontSize: 54)
                            HStack(spacing: HyseSpacing.large) {
                                restAdjustmentButton("−15") { store.adjustRestTimer(by: -15) }
                                    .accessibilityLabel("-15 s")
                                restAdjustmentButton("+15") { store.adjustRestTimer(by: 15) }
                                    .accessibilityLabel("+15 s")
                                restSkipButton
                            }
                        }
                        .padding(.horizontal, HyseSpacing.large)
                        .padding(.vertical, HyseSpacing.large)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        compactRestTimer(end)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .animation(.easeInOut(duration: 0.32), value: restTimerExpanded)
            }
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background(HyseColor.surface)
        }
    }

    private func compactRestTimer(_ end: Date) -> some View {
        HStack(spacing: keyboardVisible ? 6 : HyseSpacing.large) {
            restAdjustmentButton("−15") { store.adjustRestTimer(by: -15) }
                .frame(width: keyboardVisible ? 48 : nil)
                .accessibilityLabel("-15 s")
            restTimerValue(end, fontSize: keyboardVisible ? 28 : 30)
            restAdjustmentButton("+15") { store.adjustRestTimer(by: 15) }
                .frame(width: keyboardVisible ? 48 : nil)
                .accessibilityLabel("+15 s")
            restSkipButton
                .frame(width: keyboardVisible ? 56 : nil)
            if keyboardVisible {
                keyboardDismissButton
            }
        }
        .padding(.horizontal, keyboardVisible ? 10 : HyseSpacing.large)
        .padding(.vertical, HyseSpacing.medium)
    }

    private var keyboardDismissButton: some View {
        Button {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.title3)
                .foregroundStyle(.black)
                .frame(width: 44, height: 48)
                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("training.keyboard.dismiss"))
    }

    private func restTimerValue(_ end: Date, fontSize: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(end.timeIntervalSince(context.date)))
            Button {
                guard !keyboardVisible else { return }
                withAnimation(.easeInOut(duration: 0.2)) { restTimerExpanded.toggle() }
            } label: {
                Text(durationText(TimeInterval(remaining)))
                    .font(.system(size: fontSize, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .matchedGeometryEffect(id: "rest-timer-value", in: restTimerAnimation)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(durationText(TimeInterval(remaining)))
            .accessibilityHint(restTimerExpanded ? "Tap to use compact timer" : "Tap to expand timer")
        }
    }

    private var restSkipButton: some View {
        Button { store.skipRestTimer() } label: {
            Text("Skip")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color(uiColor: .systemBlue), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Skip")
    }

    private func restAdjustmentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(HyseColor.controlSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ActiveWorkoutMuscleDistributionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let counts: [String: Double]

    private var sortedCounts: [(muscle: String, sets: Double)] {
        counts.map { (muscle: $0.key, sets: $0.value) }
            .sorted {
                if $0.sets == $1.sets {
                    return language.text("training.muscle.\($0.muscle)") < language.text("training.muscle.\($1.muscle)")
                }
                return $0.sets > $1.sets
            }
    }

    private var maximum: Double { max(1, sortedCounts.first?.sets ?? 1) }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    VStack(spacing: HyseSpacing.xLarge) {
                        DetailedTrainingMuscleBody(counts: counts)
                            .frame(maxWidth: 620)
                            .padding(.horizontal, HyseSpacing.medium)

                        if sortedCounts.isEmpty {
                            Text(language.text("training.active.no_trained_muscles"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, HyseSpacing.xLarge)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text(language.text("training.statistics.muscles"))
                                    Spacer()
                                    Text(language.text("training.completed_sets"))
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, HyseSpacing.large)
                                .padding(.vertical, HyseSpacing.medium)

                                ForEach(sortedCounts, id: \.muscle) { item in
                                    VStack(spacing: HyseSpacing.small) {
                                        HStack {
                                            Text(language.text("training.muscle.\(item.muscle)"))
                                                .lineLimit(1)
                                            Spacer()
                                            Text(formatted(item.sets))
                                                .monospacedDigit()
                                        }
                                        ProgressView(value: item.sets, total: maximum)
                                            .tint(HyseColor.accent)
                                            .scaleEffect(x: 1, y: 1.8, anchor: .center)
                                    }
                                    .padding(.horizontal, HyseSpacing.large)
                                    .padding(.vertical, HyseSpacing.medium)
                                    if item.muscle != sortedCounts.last?.muscle {
                                        Divider().padding(.leading, HyseSpacing.large)
                                    }
                                }
                            }
                            .hyseGlassSurface(radius: HyseRadius.card)
                            .padding(.horizontal, HyseSpacing.page)
                        }
                    }
                    .padding(.vertical, HyseSpacing.large)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(language.text("training.active.trained_muscles"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("add_entry.done")) { dismiss() }
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(value.rounded() == value ? 0 : 1))
                .locale(language.locale)
        )
    }
}

private struct WorkoutFinishConfirmationView: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    let workout: WorkoutLog
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(HyseColor.accent)
                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    Text(t("training.finish.confirm_title"))
                        .font(.title2.weight(.bold))
                    Text(t("training.finish.confirm_message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: HyseSpacing.small) {
                finishMetric(t("training.duration"), durationText(workout.duration))
                finishMetric(t("training.total_volume"), formattedVolume(workout.totalVolume))
                finishMetric(t("training.completed_sets"), TrainingSetStatistics.formatted(TrainingSetStatistics.count(workout, halveUnilateral: halveUnilateral), locale: language.locale))
            }
            .padding(.horizontal, HyseSpacing.medium)
            .padding(.vertical, HyseSpacing.large)
            .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))

            // Finishing stores only completed sets. Without one the store keeps
            // the workout active, so say so instead of silently closing.
            if workout.completedSets.isEmpty {
                Label(t("training.finish.no_completed_sets"), systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: HyseSpacing.medium) {
                Button(t("training.continue"), action: onCancel)
                    .buttonStyle(HyseSecondaryButtonStyle())
                Button(t("training.finish"), action: onConfirm)
                    .buttonStyle(HysePrimaryButtonStyle())
                    .disabled(workout.completedSets.isEmpty)
                    .opacity(workout.completedSets.isEmpty ? 0.45 : 1)
            }
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.large)
        .padding(.bottom, HyseSpacing.medium)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HyseColor.surface)
    }

    private func finishMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedVolume(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) kg"
    }
}

struct WorkoutMediaView: View {
    @EnvironmentObject private var language: LanguageStore
    var localFilename: String? = nil
    var remoteURL: String? = nil
    var compact = false
    var compactSize: CGFloat = 96
    @State private var showingFullImage = false

    private var localImage: UIImage? {
        guard let localFilename,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = support.appendingPathComponent("HyseWorkoutMedia", isDirectory: true)
            .appendingPathComponent((localFilename as NSString).lastPathComponent)
        return UIImage(contentsOfFile: url.path)
    }

    private var resolvedRemoteURL: URL? {
        guard let remoteURL, !remoteURL.isEmpty,
              let base = URL(string: HyseConfiguration.serverURL) else { return nil }
        return URL(string: remoteURL, relativeTo: base)?.absoluteURL
    }

    private var isVideo: Bool {
        let source = localFilename ?? resolvedRemoteURL?.path ?? ""
        return ["mp4", "mov"].contains((source as NSString).pathExtension.lowercased())
    }

    var body: some View {
        if isVideo {
            if compact {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: compactSize, height: compactSize)
                    .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
            } else {
                Label("Video", systemImage: "play.rectangle.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
            }
        } else if compact, localImage != nil || resolvedRemoteURL != nil {
            Button { showingFullImage = true } label: { thumbnail }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("training.feed.open_photo"))
                .fullScreenCover(isPresented: $showingFullImage) { expandedImage }
        } else if let localImage {
            GeometryReader { geometry in
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .aspectRatio(localImage.size.width >= localImage.size.height ? 4.0 / 3.0 : 3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        } else if let resolvedRemoteURL {
            AsyncImage(url: resolvedRemoteURL) { image in
                GeometryReader { geometry in
                    image.resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .aspectRatio(1, contentMode: .fit)
                .background(HyseColor.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
            } placeholder: {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let localImage {
                Image(uiImage: localImage).resizable().scaledToFill()
            } else if let resolvedRemoteURL {
                AsyncImage(url: resolvedRemoteURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: compactSize, height: compactSize)
        .background(HyseColor.elevatedSurface)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
    }

    private var expandedImage: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let localImage {
                    Image(uiImage: localImage).resizable().scaledToFit()
                } else if let resolvedRemoteURL {
                    AsyncImage(url: resolvedRemoteURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { showingFullImage = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding(HyseSpacing.page)
            }
            .accessibilityLabel(language.text("training.close"))
        }
    }
}

struct WorkoutCompletionEditor: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var settings: UserSettingsStore
    @State private var draft: WorkoutLog
    @State private var mediaItem: PhotosPickerItem?
    @State private var mediaPreview: UIImage?
    @State private var isLoadingMedia = false
    @State private var showingMediaSourcePicker = false
    @State private var showingCamera = false
    @State private var cameraAlert: CameraAlert?
    @State private var showingDiscardConfirmation = false
    @State private var showingNearbyGymPicker = false
    @State private var showingVisibility = false
    @State private var hasAppliedDefaultPreferences = false
    @State private var tracksRoutine: Bool
    @State private var updatesRoutineValues: Bool
    private let originalRoutineID: UUID?
    private let appliesDefaultPreferences: Bool
    @ObservedObject var store: TrainingStore
    let onSave: (WorkoutLog) -> Void
    let onDiscard: () -> Void

    init(
        workout: WorkoutLog,
        store: TrainingStore,
        appliesDefaultPreferences: Bool = false,
        onSave: @escaping (WorkoutLog) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        let linkedRoutineID = workout.routineID.flatMap { candidate in
            store.routines.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        _draft = State(initialValue: workout)
        _tracksRoutine = State(initialValue: linkedRoutineID != nil)
        _updatesRoutineValues = State(initialValue: linkedRoutineID != nil)
        originalRoutineID = linkedRoutineID
        self.appliesDefaultPreferences = appliesDefaultPreferences
        self.store = store
        self.onSave = onSave
        self.onDiscard = onDiscard
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                    TextField(t("training.workout.name"), text: $draft.name)
                        .font(.largeTitle.bold())
                        .textFieldStyle(.plain)

                    HStack(spacing: 0) {
                        completionMetric(t("training.duration"), durationText(draft.duration))
                        completionMetric(t("training.total_volume"), "\(draft.totalVolume.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) kg")
                        completionMetric(t("training.completed_sets"), TrainingSetStatistics.formatted(TrainingSetStatistics.count(draft, halveUnilateral: settings.countUnilateralSetsAsHalf), locale: language.locale))
                    }

                    Button { showingMediaSourcePicker = true } label: {
                        Group {
                            if let mediaPreview {
                                GeometryReader { geometry in
                                    Image(uiImage: mediaPreview)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .clipped()
                                }
                                .aspectRatio(mediaPreview.size.width >= mediaPreview.size.height ? 4.0 / 3.0 : 3.0 / 4.0, contentMode: .fit)
                            } else {
                                VStack(spacing: HyseSpacing.small) {
                                    Image(systemName: draft.mediaLocalFilename == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                                        .font(.title2)
                                    Text(t(draft.mediaLocalFilename == nil ? "training.completion.add_media" : "training.completion.media_added"))
                                        .font(.headline)
                                }
                                .foregroundStyle(draft.mediaLocalFilename == nil ? Color.primary : HyseColor.success)
                                .frame(maxWidth: .infinity)
                                .frame(height: 132)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background(HyseColor.elevatedSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                                .stroke(HyseColor.border, style: StrokeStyle(lineWidth: 1.2, dash: [6]))
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        Text(t("training.completion.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(t("training.completion.description_placeholder"), text: $draft.notes, axis: .vertical)
                            .lineLimit(3...7)
                            .textFieldStyle(.plain)
                            .padding(.bottom, HyseSpacing.small)
                        Divider()
                    }

                    completionRow(icon: "calendar", title: t("training.completion.date")) {
                        DatePicker("", selection: completedDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    completionGymRow
                    Button { showingVisibility = true } label: {
                        completionNavigationRow(
                            icon: "eye",
                            title: t("training.completion.visibility"),
                            value: visibilityTitle
                        )
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        RoutineTrackingSettingsView(
                            workoutName: routineDisplayName,
                            tracksRoutine: $tracksRoutine,
                            updatesRoutineValues: $updatesRoutineValues,
                            showsRoutineUpdateSetting: !appliesDefaultPreferences
                        )
                    } label: {
                        completionNavigationRow(
                            icon: "list.clipboard",
                            title: t("training.completion.routine_settings"),
                            value: t(tracksRoutine ? "training.completion.routine_tracking.on" : "training.completion.routine_tracking.off")
                        )
                    }
                    .buttonStyle(.plain)

                    Button(t("training.completion.discard"), role: .destructive) {
                        showingDiscardConfirmation = true
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HyseSpacing.large)
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(t("training.completion.save_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(t("training.completion.save")) { saveWorkout() }
                    .fontWeight(.semibold)
                    .disabled(isLoadingMedia || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: mediaItem) { _, item in loadMedia(item) }
        .onAppear {
            applyDefaultPreferencesIfNeeded()
            if let filename = draft.mediaLocalFilename,
               let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let url = support.appendingPathComponent("HyseWorkoutMedia", isDirectory: true)
                    .appendingPathComponent((filename as NSString).lastPathComponent)
                mediaPreview = UIImage(contentsOfFile: url.path)
            }
        }
        .sheet(isPresented: $showingMediaSourcePicker) {
            VStack(alignment: .leading, spacing: HyseSpacing.large) {
                HStack(alignment: .top, spacing: HyseSpacing.medium) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(HyseColor.accent)
                        .frame(width: 48, height: 48)
                        .background(HyseColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("training.completion.media_source_title"))
                            .font(.title3.bold())
                        Text(t("training.completion.media_source_subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { showingMediaSourcePicker = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(HyseColor.elevatedSurface, in: Circle())
                    }
                    .accessibilityLabel(t("training.close"))
                }
                .padding(.bottom, HyseSpacing.small)
                PhotosPicker(selection: $mediaItem, matching: .any(of: [.images, .videos])) {
                    mediaSourceOption(
                        icon: "photo.on.rectangle.angled",
                        title: t("training.completion.choose_library"),
                        subtitle: t("training.completion.library_hint")
                    )
                }
                .buttonStyle(.plain)
                Button {
                    openCamera()
                } label: {
                    mediaSourceOption(
                        icon: "camera.fill",
                        title: t("training.completion.take_photo"),
                        subtitle: t("training.completion.camera_hint")
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(HyseSpacing.page)
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(HyseColor.background)
            .sheet(isPresented: $showingCamera) {
                WorkoutCameraPicker { image in
                    saveCameraPhoto(image)
                    showingCamera = false
                    showingMediaSourcePicker = false
                } onCancel: {
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
        }
        .alert(item: $cameraAlert) { alert in
            switch alert {
            case .unavailable:
                Alert(title: Text(t("training.completion.camera_unavailable")))
            case .denied:
                Alert(
                    title: Text(t("training.completion.camera_denied")),
                    message: Text(t("training.completion.camera_denied_message")),
                    primaryButton: .default(Text(t("training.completion.open_settings"))) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .sheet(isPresented: $showingNearbyGymPicker) {
            NavigationStack {
                NearbyGymPickerView(selectedGymID: draft.gymSelectionID) { gym in
                    draft.gymName = gym.name
                    draft.gymAddress = gym.address.isEmpty ? nil : gym.address
                    draft.gymLatitude = gym.coordinate.latitude
                    draft.gymLongitude = gym.coordinate.longitude
                }
            }
            .environmentObject(language)
        }
        .sheet(isPresented: $showingVisibility) {
            WorkoutVisibilitySheet(selection: visibility)
                .environmentObject(language)
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
        }
        .alert(t("training.completion.discard_confirm_title"), isPresented: $showingDiscardConfirmation) {
            Button(t("app_tabs.cancel"), role: .cancel) {}
            Button(t("training.completion.discard"), role: .destructive, action: onDiscard)
        } message: {
            Text(t("training.completion.discard_confirm_message"))
        }
    }

    private func mediaSourceOption(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(HyseColor.accent)
                .frame(width: 48, height: 48)
                .background(HyseColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: HyseSpacing.small)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(HyseSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                .stroke(HyseColor.border, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
    }

    private var completedDate: Binding<Date> {
        Binding(get: { draft.completedAt ?? Date() }, set: { draft.completedAt = $0 })
    }

    private var gymName: Binding<String> {
        Binding(
            get: { draft.gymName ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed != draft.gymName {
                    draft.gymAddress = nil
                    draft.gymLatitude = nil
                    draft.gymLongitude = nil
                }
                draft.gymName = trimmed.isEmpty ? nil : value
            }
        )
    }

    private var visibility: Binding<String> {
        Binding(get: { draft.visibility ?? "private" }, set: { draft.visibility = $0 })
    }

    private var visibilityTitle: String {
        t((draft.visibility ?? "private") == "public"
          ? "training.completion.visibility.everyone"
          : "training.completion.visibility.private")
    }

    private func applyDefaultPreferencesIfNeeded() {
        guard appliesDefaultPreferences, !hasAppliedDefaultPreferences else { return }
        hasAppliedDefaultPreferences = true
        if draft.gymName == nil, let gymName = settings.defaultWorkoutGymName {
            draft.gymName = gymName
            draft.gymAddress = settings.defaultWorkoutGymAddress
            draft.gymLatitude = settings.defaultWorkoutGymLatitude
            draft.gymLongitude = settings.defaultWorkoutGymLongitude
        }
        if draft.visibility == nil {
            draft.visibility = settings.defaultWorkoutVisibility == "public" ? "public" : "private"
        }
    }

    private var routineDisplayName: String {
        originalRoutineID.flatMap { id in store.routines.first(where: { $0.id == id })?.name } ?? draft.name
    }

    private func saveWorkout() {
        commitWorkout(updateRoutine: appliesDefaultPreferences ? tracksRoutine : updatesRoutineValues)
    }

    private func commitWorkout(updateRoutine: Bool) {
        var completedWorkout = draft
        if tracksRoutine {
            let routineID: UUID
            if let originalRoutineID {
                routineID = originalRoutineID
            } else {
                routineID = store.ensureRoutine(from: completedWorkout)
            }
            completedWorkout.routineID = routineID
            if updateRoutine {
                store.updateRoutineValues(routineID, from: completedWorkout)
            }
        } else {
            completedWorkout.routineID = nil
        }
        onSave(completedWorkout)
    }

    private func completionMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completionGymRow: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(HyseColor.accent)
                Text(t("training.completion.gym"))
                    .font(.body.weight(.medium))
                Spacer(minLength: HyseSpacing.small)
                Button {
                    showingNearbyGymPicker = true
                } label: {
                    Label(t("training.completion.gym_nearby"), systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(HyseColor.accent.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(HyseColor.accent)
            }

            TextField(t("training.completion.select"), text: gymName)
                .font(.headline)
                .padding(.leading, 44)

            if let address = draft.gymAddress, !address.isEmpty {
                Label(address, systemImage: "mappin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, HyseSpacing.small)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func completionRow<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(HyseColor.accent)
            Text(title).font(.body.weight(.medium))
            Spacer(minLength: HyseSpacing.small)
            content()
        }
        .padding(.vertical, HyseSpacing.small)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func completionNavigationRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(HyseColor.accent)
            Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
            Spacer(minLength: HyseSpacing.small)
            Text(value).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, HyseSpacing.medium)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func loadMedia(_ item: PhotosPickerItem?) {
        guard let item else { return }
        showingMediaSourcePicker = false
        isLoadingMedia = true
        Task {
            defer { isLoadingMedia = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first
            let image = UIImage(data: data)
            let mediaData: Data
            let ext: String
            if let image {
                guard let jpeg = compressedWorkoutPhoto(image) else { return }
                mediaData = jpeg
                ext = "jpg"
            } else {
                mediaData = data
                ext = type?.preferredFilenameExtension ?? "media"
            }
            guard let filename = store.saveWorkoutMedia(mediaData, workoutID: draft.id, fileExtension: ext) else { return }
            draft.mediaLocalFilename = filename
            mediaPreview = ext == "jpg" ? UIImage(data: mediaData) : nil
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlert = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showingCamera = true }
                    else { cameraAlert = .denied }
                }
            }
        case .denied, .restricted:
            cameraAlert = .denied
        @unknown default:
            cameraAlert = .denied
        }
    }

    private func saveCameraPhoto(_ image: UIImage) {
        guard let data = compressedWorkoutPhoto(image),
              let filename = store.saveWorkoutMedia(data, workoutID: draft.id, fileExtension: "jpg") else { return }
        draft.mediaLocalFilename = filename
        mediaPreview = UIImage(data: data)
    }

    private func compressedWorkoutPhoto(_ image: UIImage) -> Data? {
        let maxBytes = 1_200_000
        for maxDimension in [CGFloat(1_600), 1_200, 900, 720, 540, 360] {
            if let data = image.hyseCompressedJPEG(maxDimension: maxDimension, maxBytes: maxBytes),
               data.count <= maxBytes {
                return data
            }
        }
        return nil
    }

    private enum CameraAlert: Identifiable {
        case unavailable, denied
        var id: Int { self == .unavailable ? 0 : 1 }
    }
}

private struct WorkoutCameraPicker: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPhoto: onPhoto, onCancel: onCancel) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPhoto: (UIImage) -> Void
        let onCancel: () -> Void

        init(onPhoto: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPhoto = onPhoto
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onPhoto(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}

private struct RoutineTrackingSettingsView: View {
    @EnvironmentObject private var language: LanguageStore
    let workoutName: String
    @Binding var tracksRoutine: Bool
    @Binding var updatesRoutineValues: Bool
    let showsRoutineUpdateSetting: Bool

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                VStack(spacing: 0) {
                    settingRow(
                        title: t("training.completion.routine_tracking.title", workoutName),
                        message: t("training.completion.routine_tracking.explanation"),
                        isOn: $tracksRoutine
                    )
                    if showsRoutineUpdateSetting {
                        Divider()
                        settingRow(
                            title: t("training.completion.routine_update.title"),
                            message: t("training.completion.routine_update.explanation"),
                            isOn: $updatesRoutineValues
                        )
                        .disabled(!tracksRoutine)
                        .opacity(tracksRoutine ? 1 : 0.48)
                    }
                    Divider()
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.top, HyseSpacing.large)
            }
        }
        .navigationTitle(t("training.completion.routine_settings_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: tracksRoutine) { _, enabled in
            if !enabled { updatesRoutineValues = false }
        }
    }

    private func settingRow(title: String, message: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Toggle(title, isOn: isOn)
                .font(.headline)
                .tint(HyseColor.accent)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, HyseSpacing.large)
    }
}

private struct WorkoutVisibilitySheet: View {
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    private func t(_ key: String) -> String { language.text(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            Text(t("training.completion.visibility"))
                .font(.title2.bold())
                .frame(maxWidth: .infinity)

            Text(t("training.completion.visibility.section"))
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                visibilityOption(
                    value: "private",
                    title: t("training.completion.visibility.private"),
                    message: t("training.completion.visibility.private_explanation")
                )
                Divider()
                visibilityOption(
                    value: "public",
                    title: t("training.completion.visibility.everyone"),
                    message: t("training.completion.visibility.everyone_explanation")
                )
            }
            .background(HyseColor.elevatedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
            Spacer(minLength: 0)
        }
        .padding(HyseSpacing.page)
        .background(HyseBackdrop())
    }

    private func visibilityOption(value: String, title: String, message: String) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack(spacing: HyseSpacing.medium) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: HyseSpacing.small)
                if selection == value {
                    Image(systemName: "checkmark")
                        .font(.title3.bold())
                        .foregroundStyle(HyseColor.accent)
                }
            }
            .padding(HyseSpacing.large)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutCelebrationView: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    let workout: WorkoutLog
    let workoutNumber: Int
    let recentWorkouts: [WorkoutLog]
    @ObservedObject var store: TrainingStore
    let onDone: () -> Void
    @State private var animateConfetti = false
    @State private var showingShareComposer = false
    @State private var isClosing = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                VStack(spacing: HyseSpacing.xLarge) {
                    VStack(spacing: HyseSpacing.small) {
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(HyseColor.accent)
                        Text(t("training.celebration.title"))
                            .font(.largeTitle.bold())
                        Text(t("training.celebration.workout_number", workoutNumber))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, HyseSpacing.large)

                    VStack(spacing: HyseSpacing.large) {
                        DetailedTrainingMuscleBody(counts: muscleCounts)
                            .frame(maxWidth: 420)
                            .accessibilityLabel(t("training.active.trained_muscles"))
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            Text(t("training.statistics.muscles"))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: HyseSpacing.small), GridItem(.flexible(), spacing: HyseSpacing.small)],
                                alignment: .leading,
                                spacing: HyseSpacing.small
                            ) {
                                ForEach(highlightedMuscles, id: \.muscle) { item in
                                    Text(t("training.muscle.\(item.muscle)"))
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, HyseSpacing.medium)
                                        .frame(height: 34)
                                        .background(HyseColor.surface, in: Capsule())
                                }
                                if additionalMuscleCount > 0 {
                                    Text("+\(additionalMuscleCount)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, HyseSpacing.medium)
                                        .frame(height: 34)
                                        .background(HyseColor.surface, in: Capsule())
                                }
                            }
                        }
                        weekStrip
                        Text(t("training.celebration.last_seven_days", activeDays.count))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 0) {
                            celebrationMetric(t("training.duration"), durationText(workout.duration))
                            celebrationMetric(t("training.total_volume"), "\(workout.totalVolume.formatted(.number.precision(.fractionLength(0...1)))) kg")
                            celebrationMetric(t("training.completed_sets"), TrainingSetStatistics.formatted(TrainingSetStatistics.count(workout, halveUnilateral: halveUnilateral), locale: language.locale))
                        }
                    }
                    .padding(HyseSpacing.large)
                    .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                            .stroke(HyseColor.border, lineWidth: 1)
                    }

                    Text(t("training.celebration.share"))
                        .font(.headline)
                    Button { showingShareComposer = true } label: {
                        Label(t("training.celebration.share_button"), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(HyseSecondaryButtonStyle())
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.bottom, 110)
            }
            WorkoutConfettiView(active: animateConfetti)
                .allowsHitTesting(false)
        }
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom) {
            Button {
                guard !isClosing else { return }
                isClosing = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                DispatchQueue.main.async { onDone() }
            } label: {
                Text(t("add_entry.done"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    .background(HyseColor.accent, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
            }
                .buttonStyle(.plain)
                .disabled(isClosing)
                .opacity(isClosing ? 0.72 : 1)
                .padding(.horizontal, HyseSpacing.page)
                .padding(.vertical, HyseSpacing.small)
                .background(HyseColor.elevatedSurface)
                .zIndex(100)
        }
        .onAppear { withAnimation(.linear(duration: 2.8)) { animateConfetti = true } }
        .sheet(isPresented: $showingShareComposer) {
            WorkoutShareComposer(workout: workout, muscleCounts: muscleCounts, store: store)
                .environmentObject(language)
        }
    }

    private var muscleCounts: [String: Double] {
        WorkoutShareMuscles.counts(for: workout)
    }

    private var highlightedMuscles: [(muscle: String, sets: Double)] {
        muscleCounts
            .map { (muscle: $0.key, sets: $0.value) }
            .sorted {
                if $0.sets == $1.sets {
                    return t("training.muscle.\($0.muscle)") < t("training.muscle.\($1.muscle)")
                }
                return $0.sets > $1.sets
            }
            .prefix(5)
            .map { $0 }
    }
    private var additionalMuscleCount: Int {
        max(0, muscleCounts.count - highlightedMuscles.count)
    }

    private var activeDays: Set<Date> {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        return Set(recentWorkouts.compactMap { value in
            let date = calendar.startOfDay(for: value.completedAt ?? value.startedAt)
            return date >= start ? date : nil
        })
    }

    private var weekStrip: some View {
        let calendar = Calendar.autoupdatingCurrent
        return HStack(spacing: HyseSpacing.small) {
            ForEach(0..<7, id: \.self) { offset in
                let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset - 6, to: Date()) ?? Date())
                VStack(spacing: 6) {
                    Text(date.formatted(.dateTime.weekday(.narrow).locale(language.locale)))
                        .font(.caption2.weight(.semibold))
                    Image(systemName: activeDays.contains(date) ? "checkmark.circle.fill" : "circle.fill")
                        .font(.title2)
                        .foregroundStyle(activeDays.contains(date) ? HyseColor.accent : Color.secondary.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func celebrationMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WorkoutConfettiView: View {
    let active: Bool
    private let colors: [Color] = [HyseColor.accent, HyseColor.success, HyseColor.warning, HyseColor.danger, .blue]

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<24, id: \.self) { index in
                let horizontalFraction = CGFloat((index * 37) % 100) / 100
                let startOffset = CGFloat((index * 41) % 180)
                let endY = geometry.size.height + 30
                let startY = -30 - startOffset
                WorkoutConfettiPiece(color: colors[index % colors.count], active: active, index: index)
                    .position(
                        x: geometry.size.width * horizontalFraction,
                        y: active ? endY : startY
                    )
            }
        }
    }
}

private struct WorkoutConfettiPiece: View {
    let color: Color
    let active: Bool
    let index: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 8, height: 14)
            .rotationEffect(.degrees(rotation))
            .animation(animation, value: active)
    }

    private var rotation: Double {
        active ? Double(index * 73 + 240) : Double(index * 19)
    }

    private var animation: Animation {
        .linear(duration: 2.2 + Double(index % 5) * 0.16)
            .delay(Double(index % 8) * 0.05)
    }
}

private struct PersonalRecordBannerOverlay: View {
    @ObservedObject var presentation: TrainingPersonalRecordPresentation
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if let feedback = presentation.feedback {
                PersonalRecordBanner(feedback: feedback)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(HyseMotion.quick, value: presentation.feedback?.id)
        .task(id: presentation.feedback?.id) {
            guard presentation.feedback != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}

private struct PersonalRecordBanner: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("trainingWeightUnit_v1") private var weightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    let feedback: TrainingPersonalRecordFeedback

    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: weightUnitRaw) ?? .kilograms }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var orderedFlags: [String] {
        let order = ["estimated_1rm", "set_volume", "weight", "reps", "first_performance"]
        return order.filter(feedback.flags.contains)
    }

    var body: some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: "medal.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(HyseColor.warning)
                .frame(width: 48, height: 48)
                .background(HyseColor.warning.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(t(orderedFlags.count > 1 ? "training.pr.multiple_title" : "training.pr.title"))
                    .font(.headline.bold())
                Text(feedback.exerciseDisplayName(isGerman: language.isGerman))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(orderedFlags.map { "\(t("training.pr.\($0).title")): \(value(for: $0))" }.joined(separator: " · "))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HyseSpacing.medium)
        .padding(.vertical, HyseSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hyseGlassSurface(radius: HyseRadius.card, tint: HyseColor.warning)
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                .stroke(HyseColor.warning.opacity(0.34), lineWidth: 1)
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.xSmall)
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }

    private func value(for flag: String) -> String {
        switch flag {
        case "estimated_1rm": formatWeight(feedback.estimatedOneRepMaximum)
        case "set_volume": formatWeight(feedback.setVolume)
        case "weight": formatWeight(feedback.weightKilograms)
        case "reps": t("training.pr.repetitions_value", feedback.repetitions)
        default: t("training.pr.first_performance_value", formatWeight(feedback.weightKilograms), feedback.repetitions)
        }
    }

    private func formatWeight(_ kilograms: Double) -> String {
        let displayed = weightUnit.display(kilograms)
        return "\(displayed.formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue)"
    }
}
