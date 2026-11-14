import ActivityKit
import Foundation
import OSLog

@MainActor
final class TrainingLiveActivityController {
    static let shared = TrainingLiveActivityController()
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "TrainingLiveActivity")
    private enum PendingAction {
        case reconcile(workoutID: String, state: TrainingActivityAttributes.ContentState, staleDate: Date?)
        case finish(workoutID: String, state: TrainingActivityAttributes.ContentState)
        case endAll
    }
    private var pendingAction: PendingAction?
    private var processingTask: Task<Void, Never>?

    func reconcile(with workout: WorkoutLog?, restTimerEnd: Date?, finished: Bool, weightUnit: TrainingWeightUnit) {
        guard UserDefaults.standard.object(forKey: "liveActivityEnabled_v1") as? Bool ?? true,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            enqueue(.endAll)
            return
        }
        guard let workout else {
            enqueue(.endAll)
            return
        }
        let state = contentState(workout: workout, restTimerEnd: restTimerEnd, finished: finished, weightUnit: weightUnit)
        enqueue(.reconcile(workoutID: workout.id.uuidString, state: state, staleDate: restTimerEnd))
    }

    func finish(workout: WorkoutLog, weightUnit: TrainingWeightUnit) {
        let state = contentState(workout: workout, restTimerEnd: nil, finished: false, weightUnit: weightUnit, completed: true)
        enqueue(.finish(workoutID: workout.id.uuidString, state: state))
    }

    func endAll() async {
        enqueue(.endAll)
        await processingTask?.value
    }

    private func enqueue(_ action: PendingAction) {
        pendingAction = action
        guard processingTask == nil else { return }
        processingTask = Task { await processPendingActions() }
    }

    private func processPendingActions() async {
        while let action = pendingAction {
            pendingAction = nil
            switch action {
            case let .reconcile(workoutID, state, staleDate):
                do {
                    if let matching = Activity<TrainingActivityAttributes>.activities.first(where: { $0.attributes.workoutID == workoutID }) {
                        await matching.update(ActivityContent(state: state, staleDate: staleDate))
                    } else {
                        await endExistingActivities()
                        // A newer state may have arrived while the old activity ended.
                        if pendingAction != nil { continue }
                        _ = try Activity.request(
                            attributes: TrainingActivityAttributes(workoutID: workoutID),
                            content: ActivityContent(state: state, staleDate: staleDate),
                            pushType: nil
                        )
                    }
                } catch {
                    logger.error("Live Activity update failed: \(error.localizedDescription, privacy: .public)")
                }
            case let .finish(workoutID, state):
                for activity in Activity<TrainingActivityAttributes>.activities where activity.attributes.workoutID == workoutID {
                    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(20)))
                }
            case .endAll:
                await endExistingActivities()
            }
        }
        processingTask = nil
    }

    private func endExistingActivities() async {
        for activity in Activity<TrainingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func contentState(workout: WorkoutLog, restTimerEnd: Date?, finished: Bool, weightUnit: TrainingWeightUnit, completed: Bool = false) -> TrainingActivityAttributes.ContentState {
        let pending = workout.exercises.lazy.flatMap { exercise in exercise.sets.map { (exercise, $0) } }.first { !$0.1.completed }
        let isGerman = AppLanguage.persisted == .german
        let exerciseName = pending.map { isGerman && !$0.0.exerciseGermanNameSnapshot.isEmpty ? $0.0.exerciseGermanNameSnapshot : $0.0.exerciseNameSnapshot }
            ?? workout.exercises.last.map { isGerman && !$0.exerciseGermanNameSnapshot.isEmpty ? $0.exerciseGermanNameSnapshot : $0.exerciseNameSnapshot }
            ?? "Hyse"
        let setIndex = pending.flatMap { pair in pair.0.sets.firstIndex(where: { $0.id == pair.1.id }) }.map { $0 + 1 } ?? max(1, workout.completedSets.count)
        let set = pending?.1
        let weight = set.flatMap { $0.weightKilograms > 0 ? weightUnit.display($0.weightKilograms) : nil }
        let weightText = weight.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue)" } ?? ""
        let repetitionsText = (set?.reps ?? 0) > 0 ? "\(set?.reps ?? 0)" : ""
        let timerStatus = finished ? "finished" : restTimerEnd == nil ? "inactive" : "running"
        let duration = workout.duration
        return TrainingActivityAttributes.ContentState(
            workoutName: workout.name,
            currentExercise: exerciseName,
            setNumber: setIndex,
            totalSets: workout.exercises.flatMap(\.sets).count,
            completedSets: workout.completedSets.count,
            weightText: weightText,
            repetitionsText: repetitionsText,
            durationStartDate: Date().addingTimeInterval(-duration),
            pausedDurationSeconds: duration,
            restTimerEnd: restTimerEnd,
            timerStatus: timerStatus,
            workoutPaused: workout.status == .paused,
            completed: completed
        )
    }
}
