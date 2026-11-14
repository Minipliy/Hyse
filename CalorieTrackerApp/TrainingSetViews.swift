import SwiftUI
import UIKit
import Combine

@MainActor
private enum SetCompletionFeedback {
    private static let generator = UIImpactFeedbackGenerator(style: .heavy)

    static func completed() {
        generator.impactOccurred(intensity: 1)
        generator.prepare()
    }
}

struct WorkoutReorderSession {
    let exerciseID: UUID
    let initialIndex: Int
    let sourceCenterY: CGFloat
    var fingerStartY: CGFloat
    var fingerY: CGFloat
    var orderedIDs: [UUID]
    var scrollOffset: CGFloat = 0

    var draggedCenterY: CGFloat { sourceCenterY + fingerY - fingerStartY }
}

/// The cards stay in their original order until release. This fixed-height
/// surface only moves neighboring rows, so neither persistence nor a scrollTo
/// call can pull the selected exercise away from the finger.
struct WorkoutExerciseReorderList: View {
    @EnvironmentObject private var language: LanguageStore
    let exercises: [WorkoutExerciseLog]
    let visuals: [TrainingExercise]
    @Binding var session: WorkoutReorderSession?

    private let rowHeight: CGFloat = 68
    private var byID: [UUID: WorkoutExerciseLog] {
        Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    }

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let entries = byID
            ZStack(alignment: .topLeading) {
                HyseColor.background.opacity(0.98)

                if let current = session {
                    ForEach(Array(current.orderedIDs.enumerated()), id: \.element) { index, id in
                        if let exercise = entries[id] {
                            if id == current.exerciseID {
                                RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                                    .fill(HyseColor.accent.opacity(0.10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                                            .strokeBorder(HyseColor.accent.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                    }
                                    .frame(width: max(0, geometry.size.width - HyseSpacing.page * 2), height: rowHeight - 4)
                                    .position(x: geometry.size.width / 2, y: centerY(for: index, session: current, frame: frame))
                            } else {
                                row(exercise)
                                    .position(x: geometry.size.width / 2, y: centerY(for: index, session: current, frame: frame))
                            }
                        }
                    }
                    if let dragged = entries[current.exerciseID] {
                        row(dragged, lifted: true)
                            .position(x: geometry.size.width / 2, y: current.draggedCenterY - frame.minY)
                            .zIndex(1)
                            .animation(nil, value: current.fingerY)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onChange(of: session?.fingerY) { _, _ in updateTarget(in: frame) }
            .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
                autoScroll(in: frame)
            }
        }
        .accessibilityHidden(true)
    }

    private func centerY(for index: Int, session: WorkoutReorderSession, frame: CGRect) -> CGFloat {
        session.sourceCenterY - frame.minY
            + CGFloat(index - session.initialIndex) * rowHeight
            - session.scrollOffset
    }

    private func updateTarget(in frame: CGRect) {
        guard var current = session, current.orderedIDs.count > 1 else { return }
        let origin = current.sourceCenterY - CGFloat(current.initialIndex) * rowHeight
        let rawIndex = (current.draggedCenterY - origin + current.scrollOffset) / rowHeight
        let firstCenter = origin
        let minimumScrollOffset = min(0, firstCenter - frame.minY - rowHeight / 2)
        let atTop = current.scrollOffset <= minimumScrollOffset + 1
        let target = atTop && current.fingerY <= frame.minY + 110
            ? 0
            : min(max(Int(round(rawIndex)), 0), current.orderedIDs.count - 1)
        guard let source = current.orderedIDs.firstIndex(of: current.exerciseID), source != target else { return }
        // Keep a small dead zone around each boundary so a trembling finger
        // cannot bounce two neighbors back and forth.
        if target > source, rawIndex < CGFloat(source) + 0.62 { return }
        if target < source, target != 0, rawIndex > CGFloat(source) - 0.62 { return }
        current.orderedIDs.remove(at: source)
        current.orderedIDs.insert(current.exerciseID, at: target)
        withAnimation(.easeOut(duration: 0.16)) { session = current }
        ExerciseReorderFeedback.moved()
    }

    private func autoScroll(in frame: CGRect) {
        guard var current = session, current.orderedIDs.count > 1 else { return }
        let edge: CGFloat = 110
        let top = frame.minY + edge
        let bottom = frame.maxY - edge
        let speed: CGFloat
        if current.fingerY < top {
            speed = -min(48, (top - current.fingerY) * 0.48)
        } else if current.fingerY > bottom {
            speed = min(48, (current.fingerY - bottom) * 0.48)
        } else {
            return
        }
        let firstCenter = current.sourceCenterY - CGFloat(current.initialIndex) * rowHeight
        let lastCenter = firstCenter + CGFloat(current.orderedIDs.count - 1) * rowHeight
        let minimum = min(0, firstCenter - frame.minY - rowHeight / 2)
        let maximum = max(0, lastCenter - frame.maxY + rowHeight / 2)
        let next = min(max(current.scrollOffset + speed, minimum), maximum)
        guard next != current.scrollOffset else { return }
        current.scrollOffset = next
        session = current
        updateTarget(in: frame)
    }

    private func row(_ exercise: WorkoutExerciseLog, lifted: Bool = false) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            ExerciseMovementVisual(exercise: visual(for: exercise), height: 34)
                .frame(width: 42, height: 42)
                .background(HyseColor.accent.opacity(0.12), in: Circle())
                .clipShape(Circle())
            Text(language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty
                 ? exercise.exerciseGermanNameSnapshot : exercise.exerciseNameSnapshot)
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(lifted ? HyseColor.accent : Color.secondary)
        }
        .padding(.horizontal, HyseSpacing.medium)
        .frame(width: nil, height: rowHeight - 4)
        .frame(maxWidth: .infinity)
        .background(lifted ? HyseColor.elevatedSurface : HyseColor.surface,
                    in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                .strokeBorder(lifted ? HyseColor.accent.opacity(0.55) : HyseColor.border.opacity(0.55))
        }
        .shadow(color: .black.opacity(lifted ? 0.19 : 0), radius: lifted ? 13 : 0, y: lifted ? 7 : 0)
        .scaleEffect(lifted ? 1.025 : 1)
        .padding(.horizontal, HyseSpacing.page)
    }

    private func visual(for exercise: WorkoutExerciseLog) -> TrainingExercise {
        visuals.first(where: { $0.id == exercise.exerciseID })
            ?? TrainingExercise(
                id: exercise.exerciseID,
                nameKey: exercise.exerciseNameSnapshot.lowercased().replacingOccurrences(of: " ", with: "_"),
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
    }
}

@MainActor
enum ExerciseReorderFeedback {
    static func pickedUp() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.9)
    }

    static func moved() {
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
    }

    static func dropped() {
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.impactOccurred(intensity: 0.65)
    }
}

struct ExerciseReorderDragPreview: View {
    let title: String

    var body: some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HyseColor.accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, HyseSpacing.medium)
        .frame(height: 46)
        .background(HyseColor.elevatedSurface, in: Capsule())
        .overlay(Capsule().stroke(HyseColor.accent.opacity(0.35)))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
    }
}

private struct WorkoutExerciseReorderTouchView: UIViewRepresentable {
    let onTap: () -> Void
    let onBegan: (CGFloat) -> Void
    let onMoved: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePress(_:)))
        press.minimumPressDuration = 0.3
        press.allowableMovement = 10
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.require(toFail: press)
        view.addGestureRecognizer(press)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: WorkoutExerciseReorderTouchView
        private var pickedUp = false

        init(_ parent: WorkoutExerciseReorderTouchView) { self.parent = parent }

        @objc func handleTap() { parent.onTap() }

        @objc func handlePress(_ press: UILongPressGestureRecognizer) {
            let fingerY = press.location(in: press.view).y
            switch press.state {
            case .began:
                pickedUp = true
                parent.onBegan(fingerY)
            case .changed:
                if pickedUp { parent.onMoved(fingerY) }
            case .ended, .cancelled, .failed:
                guard pickedUp else { return }
                pickedUp = false
                parent.onEnded()
            default:
                break
            }
        }
    }
}

/// Keeps the progress bar tied to the actual touch, including movement outside
/// the control. Completion is only accepted after a full displayed hold.
private struct WorkoutAddSetHoldTouchView: UIViewRepresentable {
    let onProgress: (CGFloat) -> Void
    let onPreview: () -> Void
    let onComplete: () -> Void

    func makeUIView(context: Context) -> HoldView {
        let view = HoldView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: HoldView, context: Context) {
        view.onProgress = onProgress
        view.onPreview = onPreview
        view.onComplete = onComplete
    }

    final class HoldView: UIView {
        var onProgress: ((CGFloat) -> Void)?
        var onPreview: (() -> Void)?
        var onComplete: (() -> Void)?

        private let holdDuration: TimeInterval = 0.4
        private weak var activeTouch: UITouch?
        private var startedAt: TimeInterval = 0
        private var displayLink: CADisplayLink?
        private var reachedFullProgress = false
        private var fullProgressWasPresented = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeTouch == nil,
                  let touch = touches.first,
                  bounds.contains(touch.location(in: self)) else { return }
            activeTouch = touch
            startedAt = ProcessInfo.processInfo.systemUptime
            reachedFullProgress = false
            fullProgressWasPresented = false
            onProgress?(0)
            let link = CADisplayLink(target: self, selector: #selector(updateProgress))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch, touches.contains(activeTouch) else { return }
            if !bounds.contains(activeTouch.location(in: self)) { cancelHold() }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch, touches.contains(activeTouch) else { return }
            let endedInside = bounds.contains(activeTouch.location(in: self))
            let shouldAdd = fullProgressWasPresented && endedInside
            cancelHold()
            if shouldAdd { onComplete?() }
            else if endedInside { onPreview?() }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            cancelHold()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { cancelHold() }
        }

        @objc private func updateProgress() {
            guard let activeTouch, bounds.contains(activeTouch.location(in: self)) else {
                cancelHold()
                return
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let progress = min(1, max(0, elapsed / holdDuration))
            onProgress?(CGFloat(progress))
            if progress >= 1 {
                if reachedFullProgress {
                    fullProgressWasPresented = true
                    displayLink?.invalidate()
                    displayLink = nil
                } else {
                    // Let SwiftUI present the full bar for a frame before release can add a set.
                    reachedFullProgress = true
                }
            }
        }

        private func cancelHold() {
            displayLink?.invalidate()
            displayLink = nil
            activeTouch = nil
            reachedFullProgress = false
            fullProgressWasPresented = false
            onProgress?(0)
        }

        deinit { displayLink?.invalidate() }
    }
}

struct WorkoutExerciseCard: View {
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.scenePhase) private var scenePhase
    let exercise: WorkoutExerciseLog
    let store: TrainingStore
    let highlighted: Bool
    let onReorderBegan: (CGFloat) -> Void
    let onReorderChanged: (CGFloat) -> Void
    let onReorderEnded: () -> Void
    @State private var showingExerciseDetails = false
    @State private var showingExerciseActions = false
    @State private var showingProgressGoal = false
    @State private var openProgressGoalAfterActionsDismiss = false
    @State private var undoableAddedSet: TrainingSetLog?
    @State private var notesDraft: String
    @State private var addSetHoldProgress: CGFloat = 0
    @State private var showAddSetHoldHint = false
    @FocusState private var notesFocused: Bool
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var displayName: String { language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty ? exercise.exerciseGermanNameSnapshot : exercise.exerciseNameSnapshot }
    private var progress: Double { exercise.sets.isEmpty ? 0 : Double(exercise.completedSetCount) / Double(exercise.sets.count) }
    private var supportsProgressGoal: Bool { [.weightReps, .bodyweight, .repsOnly].contains(exercise.exerciseTypeSnapshot) }
    private var progressGoal: ExerciseProgressGoal? { store.progressGoals[exercise.exerciseID] }
    private var canUndoAddedSet: Bool {
        guard let undoableAddedSet, let lastSet = exercise.sets.last else { return false }
        return lastSet == undoableAddedSet
    }
    private var progressSuggestion: String? {
        guard let goal = progressGoal else { return nil }
        guard let previous = store.latestCompletedSet(exerciseID: exercise.exerciseID) else {
            return t("training.progress.log_first")
        }
        let reps: Int
        let weight: Double
        if previous.reps >= goal.maximumRepetitions,
           (previous.rpe ?? 0) <= 9,
           previous.weightKilograms > 0,
           goal.weightIncrementKilograms > 0 {
            reps = goal.minimumRepetitions
            weight = previous.weightKilograms + goal.weightIncrementKilograms
        } else {
            reps = min(goal.maximumRepetitions, max(goal.minimumRepetitions, previous.reps + 1))
            weight = previous.weightKilograms
        }
        if weight > 0 {
            let displayed = storeWeightUnit.display(weight).formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))
            return t("training.progress.next_weight", displayed, storeWeightUnit.rawValue, reps)
        }
        return t("training.progress.next_reps", reps)
    }
    private var storeWeightUnit: TrainingWeightUnit { trainingExerciseWeightUnit }
    @EnvironmentObject private var userSettings: UserSettingsStore
    private var trainingExerciseWeightUnit: TrainingWeightUnit { userSettings.trainingWeightUnit }
    init(exercise: WorkoutExerciseLog, store: TrainingStore, highlighted: Bool,
         onReorderBegan: @escaping (CGFloat) -> Void,
         onReorderChanged: @escaping (CGFloat) -> Void, onReorderEnded: @escaping () -> Void) {
        self.exercise = exercise
        self.store = store
        self.highlighted = highlighted
        self.onReorderBegan = onReorderBegan
        self.onReorderChanged = onReorderChanged
        self.onReorderEnded = onReorderEnded
        _notesDraft = State(initialValue: store.exerciseNotesDraft(for: exercise.id) ?? exercise.notes)
    }
    private var trainingExercise: TrainingExercise {
        store.exercises.first(where: { $0.id == exercise.exerciseID })
            ?? TrainingExercise(
                id: exercise.exerciseID,
                nameKey: exercise.exerciseNameSnapshot.lowercased().replacingOccurrences(of: " ", with: "_"),
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
    }
    private var canMoveUp: Bool {
        guard let exercises = store.activeWorkout?.exercises,
              let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return false }
        return index > 0
    }
    private var canMoveDown: Bool {
        guard let exercises = store.activeWorkout?.exercises,
              let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return false }
        return index < exercises.count - 1
    }
    var body: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            HStack(spacing: HyseSpacing.medium) {
                Button { showingExerciseDetails = true } label: {
                    ExerciseMovementVisual(exercise: trainingExercise, height: 38)
                        .frame(width: 46, height: 46)
                        .background(HyseColor.accent.opacity(0.12), in: Circle())
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(HyseColor.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.primaryMusclesSnapshot.map { t("training.muscle.\($0)") }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if supportsProgressGoal, let progressGoal {
                        Label(t("training.progress.range", progressGoal.minimumRepetitions, progressGoal.maximumRepetitions), systemImage: "target")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(HyseColor.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .contentShape(Rectangle())
                .overlay {
                    GeometryReader { geometry in
                        WorkoutExerciseReorderTouchView(
                            onTap: { showingExerciseDetails = true },
                            onBegan: { localY in onReorderBegan(geometry.frame(in: .global).minY + localY) },
                            onMoved: { localY in onReorderChanged(geometry.frame(in: .global).minY + localY) },
                            onEnded: onReorderEnded
                        )
                    }
                }
                .accessibilityHint(t("training.exercise.reorder_hint"))
                Spacer(minLength: 0)
                Button { showingExerciseActions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(HyseColor.elevatedSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayName)
            }

            TextField(t("training.exercise.notes"), text: Binding(
                get: { notesDraft },
                set: { value in
                    notesDraft = value
                    store.stageExerciseNotes(value, for: exercise.id)
                }
            ), axis: .vertical)
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline)
                .focused($notesFocused)
                .task(id: notesDraft) {
                    guard notesDraft != exercise.notes else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    store.updateExerciseDetails(exercise.id, notes: notesDraft)
                }
                .onChange(of: exercise.notes) { _, value in
                    if !notesFocused && notesDraft != value { notesDraft = value }
                }
                .onChange(of: notesFocused) { _, focused in
                    if !focused { flushNotesDraft() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { flushNotesDraft() }
                }
                // Scrolling a lazy row away cancels the debounce task above
                // without necessarily ending focus; keep the typed text.
                .onDisappear { flushNotesDraft() }

            restControl

            let previousSets = store.previousPerformances(workoutExerciseID: exercise.id, count: exercise.sets.count)
            VStack(spacing: HyseSpacing.small) {
                TrainingSetColumnHeader(exerciseType: exercise.exerciseTypeSnapshot)
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    TrainingSetRow(number: index + 1, exerciseType: exercise.exerciseTypeSnapshot, set: set, previousSet: previousSets[index], update: { store.updateSet(exerciseID: exercise.id, set: $0) }, toggle: { store.toggleSet(exerciseID: exercise.id, setID: set.id) }, complete: { store.completeSet(exerciseID: exercise.id, set: $0) }, duplicate: { store.duplicateSet(exerciseID: exercise.id, setID: set.id) }, delete: { store.deleteSet(exerciseID: exercise.id, setID: set.id) })
                        .equatable()
                        .id(set.id)
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                }
            }
            VStack(spacing: HyseSpacing.small) {
                Label(t(showAddSetHoldHint ? "training.set.hold_to_add" : "training.set.add"),
                      systemImage: showAddSetHoldHint ? "hand.point.up.left.fill" : "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .task(id: showAddSetHoldHint) {
                        guard showAddSetHoldHint else { return }
                        try? await Task.sleep(for: .milliseconds(900))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            addSetHoldProgress = 0
                            showAddSetHoldHint = false
                        }
                    }
                    .background {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                HyseColor.elevatedSurface
                                HyseColor.accent
                                    .frame(width: geometry.size.width * addSetHoldProgress)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
                    .contentShape(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    .overlay {
                        WorkoutAddSetHoldTouchView(
                            onProgress: { progress in
                                showAddSetHoldHint = false
                                addSetHoldProgress = progress
                            },
                            onPreview: {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    addSetHoldProgress = 0.22
                                    showAddSetHoldHint = true
                                }
                            },
                            onComplete: {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                undoableAddedSet = store.addSet(to: exercise.id)
                            }
                        )
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(t("training.set.add_hold_hint"))
                    .accessibilityAction { undoableAddedSet = store.addSet(to: exercise.id) }
                if canUndoAddedSet, let undoableAddedSet {
                    Button {
                        store.deleteSet(exerciseID: exercise.id, setID: undoableAddedSet.id)
                        self.undoableAddedSet = nil
                    } label: {
                        Label(t("training.undo"), systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HyseColor.accent)
                    .accessibilityLabel(t("training.set.undo_add"))
                }
            }
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.vertical, HyseSpacing.medium)
        .background(highlighted ? HyseColor.success.opacity(0.06) : Color.clear)
        .overlay(alignment: .bottom) { Divider() }
        .animation(.easeInOut(duration: 0.22), value: highlighted)
        .task(id: undoableAddedSet?.id) {
            guard undoableAddedSet != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            undoableAddedSet = nil
        }
        .onDisappear {
            showAddSetHoldHint = false
            addSetHoldProgress = 0
            flushNotesDraft()
        }
        .sheet(isPresented: $showingExerciseDetails) {
            NavigationStack { ExerciseProgressView(exercise: trainingExercise, store: store) }
        }
        .sheet(isPresented: $showingProgressGoal) {
            ExerciseProgressGoalEditor(
                goal: progressGoal,
                weightUnit: userSettings.trainingWeightUnit,
                usesWeight: exercise.exerciseTypeSnapshot != .repsOnly,
                save: { store.setProgressGoal($0, for: exercise.exerciseID) },
                remove: { store.setProgressGoal(nil, for: exercise.exerciseID) }
            )
        }
        .sheet(isPresented: $showingExerciseActions, onDismiss: {
            guard openProgressGoalAfterActionsDismiss else { return }
            openProgressGoalAfterActionsDismiss = false
            showingProgressGoal = true
        }) {
            WorkoutExerciseActionsSheet(
                exerciseName: displayName,
                isUnilateral: Binding(
                    get: {
                        guard let current = store.activeWorkout?.exercises.first(where: { $0.id == exercise.id }) else { return false }
                        return TrainingSetStatistics.isUnilateral(current)
                    },
                    set: { store.setExerciseUnilateral($0, for: exercise.id) }
                ),
                supportsProgressGoal: supportsProgressGoal,
                progressGoal: progressGoal,
                progressSuggestion: progressSuggestion,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                editProgressGoal: { openProgressGoalAfterActionsDismiss = true },
                moveUp: { store.moveExercise(exercise.id, by: -1) },
                moveDown: { store.moveExercise(exercise.id, by: 1) },
                duplicate: { store.duplicateExercise(exercise.id) },
                remove: { store.removeExercise(exercise.id) }
            )
            .environmentObject(language)
            .presentationDetents([.height(supportsProgressGoal ? 455 : 385)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(HyseColor.background)
            .presentationCornerRadius(28)
        }
    }

    private func flushNotesDraft() {
        guard notesDraft != exercise.notes else { return }
        store.updateExerciseDetails(exercise.id, notes: notesDraft)
    }

    private var restControl: some View {
        Menu {
            ForEach([0, 30, 60, 90, 120, 180, 240, 300], id: \.self) { seconds in
                Button(t("training.exercise.rest_seconds", seconds)) { store.updateExerciseDetails(exercise.id, restSeconds: seconds) }
            }
        } label: {
            Label(t("training.exercise.rest_seconds", exercise.restSeconds), systemImage: "stopwatch")
                .font(.subheadline.weight(.medium))
            .foregroundStyle(HyseColor.accent)
        }
    }
}

struct WorkoutExerciseActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let exerciseName: String
    @Binding var isUnilateral: Bool
    let supportsProgressGoal: Bool
    let progressGoal: ExerciseProgressGoal?
    let progressSuggestion: String?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let editProgressGoal: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let duplicate: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(spacing: HyseSpacing.medium) {
            Capsule()
                .fill(HyseColor.border)
                .frame(width: 38, height: 5)
                .padding(.top, HyseSpacing.small)

            Text(exerciseName)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: HyseSpacing.small) {
                Toggle(language.text("training.exercise.unilateral"), isOn: $isUnilateral)
                .tint(HyseColor.accent)
                .padding(.horizontal, HyseSpacing.medium)
                .frame(minHeight: 50)
                .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                if supportsProgressGoal {
                    action(
                        progressGoal.map { language.text("training.progress.range", [$0.minimumRepetitions, $0.maximumRepetitions]) }
                            ?? language.text("training.progress.set_goal"),
                        icon: "target",
                        subtitle: progressSuggestion,
                        action: editProgressGoal
                    )
                }
                action(language.text("training.exercise.move_up"), icon: "arrow.up", disabled: !canMoveUp, action: moveUp)
                action(language.text("training.exercise.move_down"), icon: "arrow.down", disabled: !canMoveDown, action: moveDown)
                action(language.text("training.exercise.duplicate"), icon: "plus.square.on.square", action: duplicate)
                action(language.text("training.exercise.remove"), icon: "trash", destructive: true, action: remove)
            }
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.bottom, HyseSpacing.large)
    }

    private func action(_ title: String, icon: String, subtitle: String? = nil, destructive: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer()
                if !destructive {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(destructive ? HyseColor.danger : HyseColor.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, HyseSpacing.medium)
            .background(
                destructive ? HyseColor.danger.opacity(0.10) : HyseColor.elevatedSurface,
                in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

private struct TrainingSetColumnHeader: View {
    @EnvironmentObject private var language: LanguageStore
    let exerciseType: TrainingExerciseType
    private func t(_ key: String) -> String { language.text(key) }

    var body: some View {
        HStack(spacing: 6) {
            Text(t("training.routine.set_column"))
                .frame(width: 42)
            Text(t("training.active.previous_column"))
                .frame(width: 82)
            inputLabels
            Image(systemName: "checkmark")
                .frame(width: 42)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
    }

    @ViewBuilder private var inputLabels: some View {
        switch exerciseType {
        case .weightReps:
            label(t("training.weight")); label(t("training.reps"))
        case .bodyweight:
            label(t("training.reps")); label(t("training.added_weight")); label(t("training.assistance"))
        case .duration:
            label(t("training.duration"))
        case .distanceDuration:
            label(t("training.distance")); label(t("training.duration"))
        case .repsOnly:
            label(t("training.reps"))
        }
    }

    private func label(_ value: String) -> some View {
        Text(value).lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity)
    }
}

/// A rolling duration input. Digits are entered from right to left as minutes
/// and seconds; values of at least one hour are displayed as H:MM:SS.
struct DurationInputField: UIViewRepresentable {
    @Binding var seconds: Double
    let label: String
    let disabled: Bool
    var placeholder: String? = nil
    var onFocusChanged: (Bool) -> Void = { _ in }
    var showsDismissAccessory = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.textAlignment = .center
        field.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        field.textColor = UIColor.label
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 11
        field.accessibilityLabel = label
        field.placeholder = placeholder
        field.text = displayText
        if showsDismissAccessory {
            let accessory = UIToolbar()
            accessory.sizeToFit()
            let dismissButton = UIBarButtonItem(
                image: UIImage(systemName: "keyboard.chevron.compact.down"),
                style: .plain,
                target: context.coordinator,
                action: #selector(Coordinator.dismissKeyboard)
            )
            dismissButton.accessibilityLabel = LanguageStore.localizedString("training.keyboard.dismiss")
            accessory.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), dismissButton]
            field.inputAccessoryView = accessory
        }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = !disabled
        field.accessibilityLabel = label
        field.placeholder = placeholder
        if field.text != displayText {
            field.text = displayText
        }
    }

    private var displayText: String {
        seconds > 0 ? Self.formatted(seconds) : ""
    }

    static func formatted(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3_600 {
            return String(format: "%d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func digits(from text: String?) -> String {
        text?.filter(\.isNumber) ?? ""
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DurationInputField
        private var startsFresh = false
        private var inputDigits = ""

        init(_ parent: DurationInputField) {
            self.parent = parent
        }

        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            startsFresh = true
            inputDigits = ""
            parent.onFocusChanged(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChanged(false)
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let selectedText = textField.selectedTextRange.flatMap { textField.text(in: $0) }
            var digits = startsFresh || selectedText == textField.text ? "" : inputDigits
            startsFresh = false

            let replacement = DurationInputField.digits(from: string)
            if replacement.isEmpty {
                if !digits.isEmpty { digits.removeLast() }
            } else {
                digits.append(contentsOf: replacement)
            }

            inputDigits = digits
            let secondsPart = Int(String(digits.suffix(2))) ?? 0
            let minuteDigits = String(digits.dropLast(min(2, digits.count)))
            let minutes = Int(minuteDigits) ?? 0
            parent.seconds = Double(minutes * 60 + secondsPart)
            textField.text = DurationInputField.formatted(parent.seconds)
            textField.selectedTextRange = textField.textRange(from: textField.endOfDocument, to: textField.endOfDocument)
            return false
        }

        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            startsFresh = false
            inputDigits = ""
            parent.seconds = 0
            textField.text = ""
            return false
        }
    }
}

/// Keeps the editable SwiftUI row stable while swiping, then gives a confirmed
/// deletion a short, contained exit before its data is removed. Publishing
/// SwiftUI state only after that exit avoids rebuilding focused text fields in
/// the middle of a horizontal pan.
struct SetDeleteInteraction<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let rowHeight: CGFloat
    let deleteLabel: String
    let deleteActionTitle: String
    let reduceMotion: Bool
    let deletionRequested: Bool
    let onDelete: () -> Void

    func makeUIViewController(context: Context) -> SetDeleteInteractionController {
        SetDeleteInteractionController(content: AnyView(content), rowHeight: rowHeight, deleteLabel: deleteLabel, deleteActionTitle: deleteActionTitle, reduceMotion: reduceMotion, onDelete: onDelete)
    }

    func updateUIViewController(_ controller: SetDeleteInteractionController, context: Context) {
        controller.update(content: AnyView(content), rowHeight: rowHeight, deleteLabel: deleteLabel, deleteActionTitle: deleteActionTitle, reduceMotion: reduceMotion, deletionRequested: deletionRequested, onDelete: onDelete)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: SetDeleteInteractionController, context: Context) -> CGSize? {
        // `UIHostingController.sizeThatFits` can keep an outdated, expanded
        // height after its parent LazyVStack is reordered. That turns an
        // ordinary 48-point set row into a large gap. The row content has a
        // deliberately known height, so report it directly instead.
        CGSize(width: proposal.width ?? 320, height: rowHeight)
    }
}

final class SetDeleteInteractionController: UIViewController, UIGestureRecognizerDelegate {
    private let actionWidth: CGFloat = 92
    private let deleteButton = UIButton(type: .system)
    private let hostedController: UIHostingController<AnyView>
    private var deleteAction: () -> Void
    private var reduceMotion: Bool
    private var restingOffset: CGFloat = 0
    private var startingOffset: CGFloat = 0
    private var isDeleting = false
    private var panGesture: UIPanGestureRecognizer?
    private var hostedHeightConstraint: NSLayoutConstraint?
    private var rowHeight: CGFloat

    init(content: AnyView, rowHeight: CGFloat, deleteLabel: String, deleteActionTitle: String, reduceMotion: Bool, onDelete: @escaping () -> Void) {
        hostedController = UIHostingController(rootView: content)
        self.rowHeight = rowHeight
        self.reduceMotion = reduceMotion
        deleteAction = onDelete
        super.init(nibName: nil, bundle: nil)
        configureDeleteButton(label: deleteLabel, title: deleteActionTitle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .clear
        root.clipsToBounds = true
        view = root

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.addTarget(self, action: #selector(deleteButtonPressed), for: .touchUpInside)
        deleteButton.layer.cornerRadius = HyseRadius.control
        deleteButton.layer.cornerCurve = .continuous
        deleteButton.layer.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMinYCorner,
            .layerMaxXMaxYCorner
        ]
        deleteButton.clipsToBounds = true
        // UIKit buttons start fully opaque. The action should only appear
        // as the hosted row is moved left by the pan gesture.
        deleteButton.alpha = 0
        root.addSubview(deleteButton)
        NSLayoutConstraint.activate([
            // Keep the action next to the set even if SwiftUI temporarily
            // gives this container the scroll view's height during removal.
            deleteButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 3),
            deleteButton.heightAnchor.constraint(equalToConstant: 42),
            deleteButton.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: actionWidth)
        ])

        addChild(hostedController)
        let hostedView = hostedController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        root.addSubview(hostedView)
        let heightConstraint = hostedView.heightAnchor.constraint(equalToConstant: rowHeight)
        hostedHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: root.topAnchor),
            heightConstraint
        ])
        hostedController.didMove(toParent: self)
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = true
        root.addGestureRecognizer(panGesture)
        self.panGesture = panGesture
    }

    func update(content: AnyView, rowHeight: CGFloat, deleteLabel: String, deleteActionTitle: String, reduceMotion: Bool, deletionRequested: Bool, onDelete: @escaping () -> Void) {
        hostedController.rootView = content
        self.rowHeight = rowHeight
        hostedHeightConstraint?.constant = rowHeight
        self.reduceMotion = reduceMotion
        deleteAction = onDelete
        configureDeleteButton(label: deleteLabel, title: deleteActionTitle)
        if deletionRequested { animateDeletion() }
    }

    func sizeThatFits(_ proposal: CGSize) -> CGSize {
        hostedController.sizeThatFits(in: proposal)
    }

    private func configureDeleteButton(label: String, title: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(
            systemName: "trash.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        configuration.imagePlacement = .top
        configuration.imagePadding = 3
        // Deleting a single set is reversible in the current interaction,
        // so use a neutral action treatment rather than an error signal.
        configuration.baseForegroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .white
                : UIColor(red: 0.14, green: 0.15, blue: 0.16, alpha: 1)
        }
        configuration.baseBackgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.155, green: 0.163, blue: 0.170, alpha: 1)
                : UIColor(red: 0.940, green: 0.940, blue: 0.940, alpha: 1)
        }
        configuration.background.cornerRadius = HyseRadius.control
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 2, bottom: 5, trailing: 2)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var styled = attributes
            styled.font = .systemFont(ofSize: 10, weight: .semibold)
            return styled
        }
        deleteButton.configuration = configuration
        deleteButton.accessibilityLabel = label
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = panGesture.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func handlePan(_ panGesture: UIPanGestureRecognizer) {
        let translation = panGesture.translation(in: view).x
        switch panGesture.state {
        case .began:
            startingOffset = restingOffset
        case .changed:
            applyOffset(clampedOffset(startingOffset + translation))
        case .ended:
            let finalOffset = clampedOffset(startingOffset + translation)
            let velocity = panGesture.velocity(in: view).x
            let predictedOffset = clampedOffset(finalOffset + velocity * 0.15)
            // A left swipe only reveals the explicit delete control. Even
            // a fast, full swipe must never delete a set on its own.
            settle(at: predictedOffset <= -(actionWidth * 0.5) ? -actionWidth : 0)
        case .cancelled, .failed:
            settle(at: restingOffset)
        default:
            break
        }
    }

    @objc private func deleteButtonPressed() { animateDeletion() }

    private func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(0, max(-actionWidth, offset))
    }

    private func applyOffset(_ offset: CGFloat) {
        hostedController.view.transform = CGAffineTransform(translationX: offset, y: 0)
        deleteButton.alpha = min(1, max(0, -offset / actionWidth))
        let progress = min(1, max(0, -offset / actionWidth))
        deleteButton.transform = CGAffineTransform(scaleX: 0.88 + (0.12 * progress), y: 0.94 + (0.06 * progress))
    }

    private func settle(at offset: CGFloat) {
        restingOffset = offset
        guard !reduceMotion else { applyOffset(offset); return }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.45,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) { self.applyOffset(offset) }
    }

    private func animateDeletion() {
        guard !isDeleting else { return }
        isDeleting = true
        panGesture?.isEnabled = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard !reduceMotion else {
            performDelete()
            return
        }
        // Confirm the tap, then let the row gently contract in place. A
        // long sideways flight made the action feel abrupt and pulled the
        // user's gaze away from the remaining sets.
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.hostedController.view.transform = CGAffineTransform(translationX: -18, y: 0)
                .scaledBy(x: 0.985, y: 0.985)
            self.hostedController.view.alpha = 0.72
            self.deleteButton.alpha = 1
            self.deleteButton.transform = CGAffineTransform(scaleX: 1.04, y: 1.02)
        } completion: { _ in
            UIView.animate(
                withDuration: 0.20,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                self.hostedController.view.transform = CGAffineTransform(translationX: -28, y: 0)
                    .scaledBy(x: 0.96, y: 0.18)
                self.hostedController.view.alpha = 0
                self.deleteButton.alpha = 0
            } completion: { _ in
                self.performDelete()
            }
        }
    }

    private func performDelete() {
        deleteAction()
    }
}

private struct TrainingSetRow: View, Equatable {
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @AppStorage("trainingDistanceUnit_v1") private var trainingDistanceUnitRaw = TrainingDistanceUnit.kilometers.rawValue
    let number: Int
    let exerciseType: TrainingExerciseType
    let set: TrainingSetLog
    let previousSet: TrainingSetLog?
    let update: (TrainingSetLog) -> Void
    let toggle: () -> Void
    let complete: (TrainingSetLog) -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @State private var validationFailed = false
    @State private var showingSetTypePicker = false
    @State private var deletionRequested = false
    @State private var draftSet: TrainingSetLog
    @State private var completionOverride: Bool?
    @FocusState private var inputFocused: Bool
    private var displayedCompleted: Bool { completionOverride ?? set.completed }
    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    private var distanceUnit: TrainingDistanceUnit { TrainingDistanceUnit(rawValue: trainingDistanceUnitRaw) ?? .kilometers }
    private var displayedWeight: Binding<Double> { Binding(get: { weightUnit.display(draftSet.weightKilograms) }, set: { draftSet.weightKilograms = weightUnit.kilograms($0) }) }
    private var displayedDistance: Binding<Double> { Binding(get: { distanceUnit.display(draftSet.distanceMeters) }, set: { draftSet.distanceMeters = distanceUnit.meters($0) }) }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    static func == (lhs: TrainingSetRow, rhs: TrainingSetRow) -> Bool {
        lhs.number == rhs.number && lhs.exerciseType == rhs.exerciseType
            && lhs.set == rhs.set && lhs.previousSet == rhs.previousSet
    }

    init(number: Int, exerciseType: TrainingExerciseType, set: TrainingSetLog, previousSet: TrainingSetLog?, update: @escaping (TrainingSetLog) -> Void, toggle: @escaping () -> Void, complete: @escaping (TrainingSetLog) -> Void, duplicate: @escaping () -> Void, delete: @escaping () -> Void) {
        self.number = number
        self.exerciseType = exerciseType
        self.set = set
        self.previousSet = previousSet
        self.update = update
        self.toggle = toggle
        self.complete = complete
        self.duplicate = duplicate
        self.delete = delete
        _draftSet = State(initialValue: set)
    }

    var body: some View {
        SetDeleteInteraction(
            content: rowContent.environmentObject(language),
            rowHeight: validationFailed ? 72 : 48,
            deleteLabel: t("training.set.delete"),
            deleteActionTitle: t("settings.delete"),
            reduceMotion: reduceMotion,
            deletionRequested: deletionRequested,
            onDelete: delete
        )
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { showingSetTypePicker = true } label: {
                    Text(draftSet.type.badge(number: number))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(draftSet.type.tint)
                        .frame(width: 42, height: 42)
                        .background(draftSet.type.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("training.set_type.change", t(draftSet.type.localizationKey)))
                Button(action: applyPreviousSet) {
                    Text(previousSet.map(previousText) ?? "–")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(previousSet == nil ? .tertiary : .secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(width: 82)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(previousSet == nil)
                .accessibilityLabel(t("training.active.previous_column"))
                .accessibilityHint(t("training.set.copy_previous_hint"))
                inputFields
                Button {
                    if displayedCompleted {
                        completionOverride = false
                        toggle()
                    } else {
                        completeSet()
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline.bold())
                        .foregroundStyle(displayedCompleted ? .white : .secondary)
                        .frame(width: 42, height: 42)
                        .background(displayedCompleted ? HyseColor.success : HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t(displayedCompleted ? "training.set.completed" : "training.set.mark_complete"))
            }
            if validationFailed { Label(t("training.set.invalid_values"), systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(HyseColor.danger) }
        }
        .padding(.vertical, 3)
        .background(displayedCompleted ? HyseColor.success.opacity(0.16) : validationFailed ? HyseColor.danger.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                .stroke(displayedCompleted ? HyseColor.success.opacity(0.42) : Color.clear, lineWidth: 1)
        }
        .onChange(of: set.completed) { _, _ in completionOverride = nil }
        .onChange(of: inputFocused) { wasFocused, focused in if wasFocused && !focused { commitDraft() } }
        .onChange(of: set) { _, value in
            guard !inputFocused else { return }
            draftSet = value
        }
        .onDisappear {
            commitDraft()
        }
        .task(id: draftSet.durationTimerStartedAt) {
            guard draftSet.durationTimerRunning, isTimedExercise, !set.completed else { return }
            refreshDurationTimer()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard draftSet.durationTimerRunning, !set.completed else { return }
                refreshDurationTimer()
            }
        }
        .sheet(isPresented: $showingSetTypePicker) {
            TrainingSetTypePicker(
                number: number,
                selection: draftSet.type,
                onSelect: { type in
                    draftSet.type = type
                    commitDraft()
                },
                onDuplicate: duplicate,
                onDelete: requestDeletionAfterSheetDismissal
            )
            .presentationDetents([.height(560), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(HyseColor.background)
        }
    }

    private func requestDeletionAfterSheetDismissal() {
        // Let the action sheet finish leaving before the row starts its exit;
        // otherwise the feedback happens behind the sheet and is easy to miss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            deletionRequested = true
        }
    }

    private func applyPreviousSet() {
        guard let previousSet else { return }
        draftSet.stopDurationTimer()
        switch exerciseType {
        case .weightReps:
            draftSet.weightKilograms = previousSet.weightKilograms
            draftSet.reps = previousSet.reps
        case .bodyweight:
            draftSet.reps = previousSet.reps
            draftSet.weightKilograms = previousSet.weightKilograms
            draftSet.assistedKilograms = previousSet.assistedKilograms
        case .duration:
            draftSet.durationSeconds = previousSet.durationSeconds
        case .distanceDuration:
            draftSet.distanceMeters = previousSet.distanceMeters
            draftSet.durationSeconds = previousSet.durationSeconds
        case .repsOnly:
            draftSet.reps = previousSet.reps
        }
        validationFailed = false
        commitDraft()
    }

    @ViewBuilder private var inputFields: some View {
        switch exerciseType {
        case .weightReps:
            numberField(t("training.weight"), value: displayedWeight, suffix: weightUnit.rawValue, placeholder: previousWeight) { draftSet.weightKilograms = set.weightKilograms }
            intField(t("training.reps"), value: binding(\.reps), placeholder: previousReps) { draftSet.reps = set.reps }
        case .bodyweight:
            intField(t("training.reps"), value: binding(\.reps), placeholder: previousReps) { draftSet.reps = set.reps }
            numberField(t("training.added_weight"), value: displayedWeight, suffix: weightUnit.rawValue, placeholder: previousWeight) { draftSet.weightKilograms = set.weightKilograms }
            numberField(t("training.assistance"), value: displayedAssistance, suffix: weightUnit.rawValue, placeholder: previousAssistance) { draftSet.assistedKilograms = set.assistedKilograms }
        case .duration:
            durationField
        case .distanceDuration:
            numberField(t("training.distance"), value: displayedDistance, suffix: distanceUnit.rawValue, placeholder: previousDistance) { draftSet.distanceMeters = set.distanceMeters }
            durationField
        case .repsOnly:
            intField(t("training.reps"), value: binding(\.reps), placeholder: previousReps) { draftSet.reps = set.reps }
        }
    }

    private var durationField: some View {
        HStack(spacing: 4) {
            DurationInputField(
                seconds: durationBinding,
                label: t("training.duration"),
                disabled: false,
                placeholder: previousDuration,
                onFocusChanged: { inputFocused = $0 },
                showsDismissAccessory: false
            )
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(HyseColor.border))
            Button(action: toggleDurationTimer) {
                Image(systemName: draftSet.durationTimerRunning ? "pause.fill" : "play.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(draftSet.durationTimerRunning ? HyseColor.warning : HyseColor.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(set.completed)
            .accessibilityLabel(t(draftSet.durationTimerRunning ? "training.duration_timer.pause" : "training.duration_timer.start"))
        }
    }

    private var isTimedExercise: Bool { exerciseType == .duration || exerciseType == .distanceDuration }
    private func toggleDurationTimer() {
        guard isTimedExercise, !set.completed else { return }
        if draftSet.durationTimerRunning {
            draftSet.stopDurationTimer()
        } else {
            draftSet.startDurationTimer()
        }
        commitDraft()
    }

    private var durationBinding: Binding<Double> {
        Binding(get: { draftSet.durationSeconds }, set: { value in
            draftSet.durationSeconds = value
            if draftSet.durationTimerRunning {
                draftSet.durationTimerBaseSeconds = value
                draftSet.durationTimerStartedAt = Date()
                commitDraft()
            }
        })
    }

    private func refreshDurationTimer() {
        draftSet.durationSeconds = draftSet.currentDuration()
    }

    private func isValid(_ value: TrainingSetLog) -> Bool {
        switch exerciseType {
        case .weightReps, .bodyweight, .repsOnly: value.reps > 0
        case .duration: value.durationSeconds > 0
        case .distanceDuration: value.distanceMeters > 0 && value.durationSeconds > 0
        }
    }

    private func completeSet() {
        var value = draftWithPreviousValues()
        value.stopDurationTimer()
        guard isValid(value) else {
            validationFailed = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        validationFailed = false
        draftSet = value
        completionOverride = true
        SetCompletionFeedback.completed()
        complete(value)
    }

    private func draftWithPreviousValues() -> TrainingSetLog {
        var value = draftValue()
        guard let previousSet else { return value }
        switch exerciseType {
        case .weightReps:
            if value.weightKilograms == 0, previousSet.weightKilograms > 0 { value.weightKilograms = previousSet.weightKilograms }
            if value.reps == 0, previousSet.reps > 0 { value.reps = previousSet.reps }
        case .bodyweight:
            if value.reps == 0, previousSet.reps > 0 { value.reps = previousSet.reps }
            if value.weightKilograms == 0, previousSet.weightKilograms > 0 { value.weightKilograms = previousSet.weightKilograms }
            if value.assistedKilograms == 0, previousSet.assistedKilograms > 0 { value.assistedKilograms = previousSet.assistedKilograms }
        case .duration:
            if value.durationSeconds == 0, previousSet.durationSeconds > 0 { value.durationSeconds = previousSet.durationSeconds }
        case .distanceDuration:
            if value.distanceMeters == 0, previousSet.distanceMeters > 0 { value.distanceMeters = previousSet.distanceMeters }
            if value.durationSeconds == 0, previousSet.durationSeconds > 0 { value.durationSeconds = previousSet.durationSeconds }
        case .repsOnly:
            if value.reps == 0, previousSet.reps > 0 { value.reps = previousSet.reps }
        }
        return value
    }

    private func commitDraft() {
        let copy = draftValue()
        guard copy.type != set.type || copy.weightKilograms != set.weightKilograms || copy.reps != set.reps || copy.durationSeconds != set.durationSeconds || copy.distanceMeters != set.distanceMeters || copy.assistedKilograms != set.assistedKilograms || copy.durationTimerStartedAt != set.durationTimerStartedAt || copy.durationTimerBaseSeconds != set.durationTimerBaseSeconds || copy.durationTimerEverStarted != set.durationTimerEverStarted else { return }
        update(copy)
    }
    private func draftValue() -> TrainingSetLog {
        var copy = set
        copy.type = draftSet.type
        copy.weightKilograms = draftSet.weightKilograms
        copy.reps = draftSet.reps
        copy.durationSeconds = draftSet.durationSeconds
        copy.durationTimerStartedAt = draftSet.durationTimerStartedAt
        copy.durationTimerBaseSeconds = draftSet.durationTimerBaseSeconds
        copy.durationTimerEverStarted = draftSet.durationTimerEverStarted
        copy.distanceMeters = draftSet.distanceMeters
        copy.assistedKilograms = draftSet.assistedKilograms
        return copy
    }
    private func binding<Value>(_ keyPath: WritableKeyPath<TrainingSetLog, Value>) -> Binding<Value> { Binding(get: { draftSet[keyPath: keyPath] }, set: { draftSet[keyPath: keyPath] = $0 }) }
    private var displayedAssistance: Binding<Double> { Binding(get: { weightUnit.display(draftSet.assistedKilograms) }, set: { draftSet.assistedKilograms = weightUnit.kilograms($0) }) }
    private func previousText(_ value: TrainingSetLog) -> String { switch exerciseType { case .weightReps, .bodyweight: return "\(weightUnit.display(value.weightKilograms).formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue) × \(value.reps)"; case .duration: return durationText(value.durationSeconds); case .distanceDuration: return "\(distanceUnit.display(value.distanceMeters).formatted(.number.precision(.fractionLength(0...2)))) \(distanceUnit.rawValue) · \(paceText(value))"; case .repsOnly: return "\(value.reps)" } }

    private func paceText(_ value: TrainingSetLog) -> String {
        guard let seconds = distanceUnit.paceSeconds(durationSeconds: value.durationSeconds, distanceMeters: value.distanceMeters) else { return "–" }
        return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60)) /\(distanceUnit.rawValue)"
    }

    private var previousWeight: String? {
        guard let previousSet, previousSet.weightKilograms > 0 else { return nil }
        return weightUnit.display(previousSet.weightKilograms).formatted(.number.precision(.fractionLength(0...2)))
    }

    private var previousReps: String? {
        guard let previousSet, previousSet.reps > 0 else { return nil }
        return "\(previousSet.reps)"
    }

    private var previousAssistance: String? {
        guard let previousSet, previousSet.assistedKilograms > 0 else { return nil }
        return weightUnit.display(previousSet.assistedKilograms).formatted(.number.precision(.fractionLength(0...2)))
    }

    private var previousDistance: String? {
        guard let previousSet, previousSet.distanceMeters > 0 else { return nil }
        return distanceUnit.display(previousSet.distanceMeters).formatted(.number.precision(.fractionLength(0...2)))
    }

    private var previousDuration: String? {
        guard let previousSet, previousSet.durationSeconds > 0 else { return nil }
        return durationText(previousSet.durationSeconds)
    }

    private func numberField(_ label: String, value: Binding<Double>, suffix: String, placeholder: String? = nil, restoreSavedValue: @escaping () -> Void) -> some View {
        ZStack {
            TrainingSetNumericField(value: value, allowsDecimals: true, showsZero: set.completed, onFocusChanged: { inputFocused = $0 }) { wasEmpty in
                if wasEmpty && set.completed { restoreSavedValue() }
                commitDraft()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            if value.wrappedValue == 0, !set.completed, !inputFocused, let placeholder {
                Text(placeholder)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 42)
        .overlay(alignment: .trailing) {
            Text(suffix)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.trailing, 5)
                .allowsHitTesting(false)
        }
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(HyseColor.border))
        .accessibilityLabel(label)
    }
    private func intField(_ label: String, value: Binding<Int>, placeholder: String? = nil, restoreSavedValue: @escaping () -> Void) -> some View {
        ZStack {
            TrainingSetNumericField(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                allowsDecimals: false,
                showsZero: set.completed,
                onFocusChanged: { inputFocused = $0 }
            ) { wasEmpty in
                if wasEmpty && set.completed { restoreSavedValue() }
                commitDraft()
            }
            if value.wrappedValue == 0, !set.completed, !inputFocused, let placeholder {
                Text(placeholder)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(HyseColor.border))
        .accessibilityLabel(label)
    }
}

private struct TrainingSetNumericField: UIViewRepresentable {
    @Binding var value: Double
    let allowsDecimals: Bool
    let showsZero: Bool
    let onFocusChanged: (Bool) -> Void
    let onEditingEnded: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = allowsDecimals ? .decimalPad : .numberPad
        field.textAlignment = .center
        field.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        field.textColor = .label
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 11
        field.text = Self.displayText(value, allowsDecimals: allowsDecimals, showsZero: showsZero)
        field.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.keyboardType = allowsDecimals ? .decimalPad : .numberPad
        field.textAlignment = .center
        let currentText = field.text ?? ""
        let enteredValue = currentText.isEmpty || currentText == "." || currentText == ","
            ? 0 : Self.parsedValue(currentText)
        if !field.isFirstResponder || enteredValue != value {
            let display = Self.displayText(value, allowsDecimals: allowsDecimals, showsZero: showsZero)
            if field.text != display { field.text = display }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TrainingSetNumericField

        init(_ parent: TrainingSetNumericField) { self.parent = parent }

        @objc func valueChanged(_ textField: UITextField) {
            let text = textField.text ?? ""
            if text.isEmpty {
                parent.value = 0
            } else if let parsed = TrainingSetNumericField.parsedValue(text) {
                parent.value = parsed
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChanged(true)
            DispatchQueue.main.async { [weak textField] in
                guard textField?.isFirstResponder == true else { return }
                textField?.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let text = textField.text ?? ""
            if let parsed = TrainingSetNumericField.parsedValue(text), parsed.isFinite {
                parent.value = parsed
            }
            parent.onEditingEnded(text.isEmpty || text == "." || text == ",")
            textField.text = TrainingSetNumericField.displayText(parent.value, allowsDecimals: parent.allowsDecimals, showsZero: parent.showsZero)
            parent.onFocusChanged(false)
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let textRange = Range(range, in: current) else { return false }
            let next = current.replacingCharacters(in: textRange, with: string)
            if next.isEmpty || (parent.allowsDecimals && (next == "." || next == ",")) { return true }
            guard let parsed = TrainingSetNumericField.parsedValue(next), parsed.isFinite, parsed >= 0,
                  parent.allowsDecimals || (parsed < Double(Int.max) && parsed.rounded(.towardZero) == parsed) else { return false }
            return true
        }
    }

    private static func parsedValue(_ text: String) -> Double? {
        var normalized = text.replacingOccurrences(of: ",", with: ".")
        if normalized.hasSuffix(".") { normalized.removeLast() }
        return Double(normalized)
    }

    private static func displayText(_ value: Double, allowsDecimals: Bool, showsZero: Bool) -> String {
        guard value != 0 else { return showsZero ? "0" : "" }
        return allowsDecimals
            ? value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            : Int(value).formatted(.number.grouping(.never))
    }
}

private extension TrainingSetType {
    var tint: Color {
        switch self {
        case .normal: .primary
        case .warmup: HyseColor.warning
        case .dropSet: HyseColor.information
        case .failure: HyseColor.danger
        case .superset: HyseColor.accent
        }
    }

    var detailLocalizationKey: String { "training.set_type.\(rawValue).description" }

    func badge(number: Int) -> String {
        switch self {
        case .normal: "\(number)"
        case .warmup: "W"
        case .dropSet: "D"
        case .failure: "F"
        case .superset: "S"
        }
    }
}

struct TrainingSetTypePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let number: Int
    let selection: TrainingSetType
    let onSelect: (TrainingSetType) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var explainedType: TrainingSetType?

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        VStack(spacing: 14) {
            Text(t("training.set_type.choose"))
                .font(.headline)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(TrainingSetType.allCases) { type in
                        HStack(spacing: 12) {
                            Button {
                                onSelect(type)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Text(type.badge(number: number))
                                        .font(.title3.bold().monospacedDigit())
                                        .foregroundStyle(type.tint)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t(type.localizationKey))
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if selection == type {
                                            Text(t("training.set_type.selected"))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(type.tint)
                                        }
                                    }
                                    Spacer()
                                    if selection == type {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(type.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button { explainedType = type } label: {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t("training.set_type.explain", t(type.localizationKey)))
                        }
                        .frame(minHeight: 62)
                        .padding(.horizontal, 14)

                        if type != TrainingSetType.allCases.last { Divider().padding(.leading, 60) }
                    }
                }
                .hyseGlassSurface(radius: HyseRadius.card)

                VStack(spacing: 0) {
                    actionRow(t("training.set.duplicate"), symbol: "plus.square.on.square", color: HyseColor.accent) {
                        dismiss()
                        onDuplicate()
                    }
                    Divider().padding(.leading, 54)
                    actionRow(t("training.set.delete"), symbol: "xmark", color: HyseColor.danger) {
                        dismiss()
                        onDelete()
                    }
                }
                .hyseGlassSurface(radius: HyseRadius.card)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .alert(item: $explainedType) { type in
            Alert(
                title: Text(t(type.localizationKey)),
                message: Text(t(type.detailLocalizationKey)),
                dismissButton: .default(Text(t("common.ok")))
            )
        }
    }

    private func actionRow(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .frame(width: 28)
                Text(title).font(.body.weight(.medium))
                Spacer()
            }
            .foregroundStyle(color)
            .frame(minHeight: 58)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
