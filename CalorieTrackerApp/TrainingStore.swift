import Foundation
import Combine
import OSLog
import UIKit
import WidgetKit

@MainActor
final class TrainingPersonalRecordPresentation: ObservableObject {
    @Published var feedback: TrainingPersonalRecordFeedback?
}

@MainActor
final class TrainingStore: ObservableObject {
    static let freeRoutineLimit = 5
    /// Legacy limits retained for older UI code; routine and exercise creation is unrestricted.
    static let freeCustomExerciseLimit = 4
    var premiumTrainingUnlocked = true
    @Published private(set) var exercises: [TrainingExercise] = TrainingExercise.builtIns
    @Published private(set) var routines: [WorkoutRoutine] = []
    @Published private(set) var workouts: [WorkoutLog] = []
    @Published private(set) var completedWorkouts: [WorkoutLog] = []
    @Published private(set) var bodyMeasurements: [BodyMeasurement] = []
    @Published private(set) var progressGoals: [UUID: ExerciseProgressGoal] = [:]
    @Published private(set) var syncState: TrainingSyncState = .local
    @Published private(set) var pendingGuestWorkoutCount = 0
    @Published private(set) var serverStreak: TrainingServerStreak?
    @Published private(set) var streakFrozenWeekKeys: Set<String> = []
    @Published var restTimerEnd: Date?
    private(set) var latestPersonalRecordFlags: [String] = []
    let personalRecordPresentation = TrainingPersonalRecordPresentation()
    private(set) var latestPersonalRecordFeedback: TrainingPersonalRecordFeedback? {
        get { personalRecordPresentation.feedback }
        set { personalRecordPresentation.feedback = newValue }
    }
    @Published private(set) var restTimerFinished = false
    @Published private(set) var exerciseRemovalUndoID: UUID?
    /// The store is constructed before ContentView knows whether the guest or
    /// account cache belongs to the current session. UI must not expose the
    /// provisional guest snapshot during that short handover.
    @Published private(set) var hasResolvedPersistenceScope = false

    weak var authManager: AuthManager?
    private var accountID: String?
    private var pendingGuestWorkouts: [WorkoutLog] = []
    private var pendingGuestRoutines: [WorkoutRoutine] = []
    private var pendingGuestExercises: [TrainingExercise] = []
    private var pendingGuestMeasurements: [BodyMeasurement] = []
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "Training")
    private var restTimerTask: Task<Void, Never>?
    private var deferredSyncTask: Task<Void, Never>?
    private var deferredActiveSaveTask: Task<Void, Never>?
    private var deferredActiveJournalTask: Task<Void, Never>?
    private var deferredLiveActivityTask: Task<Void, Never>?
    private var deferredSetFeedbackTask: Task<Void, Never>?
    private var routineShareRevocationTask: Task<Void, Never>?
    private var pendingSetFeedbackHasRecord = false
    private var pendingActiveWorkoutID: UUID?
    /// Text fields keep their draft local for smooth typing. Retain the newest
    /// value so finishing cannot capture an older debounced workout snapshot.
    private var pendingExerciseNotes: [UUID: String] = [:]
    private var restTimerID: UUID?
    private var syncTask: Task<Void, Never>?
    private var syncGeneration = 0
    private var syncIsRunning = false
    private var syncRequestedWhileRunning = false
    private var lastSuccessfulSyncAt: Date?
    private var lastAttemptedSyncAt: Date?
    private var removedExerciseUndo: (workoutID: UUID, index: Int, exercise: WorkoutExerciseLog)?
    private var exerciseRemovalUndoTask: Task<Void, Never>?
    var removedExerciseForUndo: WorkoutExerciseLog? { removedExerciseUndo?.exercise }
    /// Reordering can cross several rows in one drag. Keep those visual
    /// updates in memory and persist exactly once when the drop completes.
    private var activeExerciseReorderNeedsSaving = false
    /// Keep the last completed run of this workout stable while sets are edited.
    private var previousPerformanceCache: [UUID: [TrainingSetLog?]]?
    private var previousPerformanceCacheWorkoutID: UUID?
    private var previousPerformanceCacheWorkoutName: String?
    private var previousPerformanceCachePlacementIDs: [UUID] = []
    private var previousRecordBestCache: [UUID: TrainingPersonalRecordBest] = [:]

    private struct State: Codable {
        var exercises: [TrainingExercise] = []
        var routines: [WorkoutRoutine] = []
        var workouts: [WorkoutLog] = []
        var bodyMeasurements: [BodyMeasurement]?
        var progressGoals: [UUID: ExerciseProgressGoal]?
        var restTimerEnd: Date?
        var restTimerID: UUID?
    }

    init() { load(scope: "guest"); monitorRestTimer() }

    var activeWorkout: WorkoutLog? { workouts.first { $0.status == .active || $0.status == .paused } }
    func attach(_ authManager: AuthManager) { self.authManager = authManager }

    func activateAccount() {
        guard let authManager, authManager.isLoggedIn, !authManager.accountID.isEmpty else { return }
        let id = authManager.accountID
        // Re-entering a tab must not turn account activation into another
        // PocketBase round-trip. Scene activation and dirty-data scheduling
        // already provide the intentional synchronization points.
        guard accountID != id else {
            hasResolvedPersistenceScope = true
            return
        }
        hasResolvedPersistenceScope = false
        flushPendingChanges()
        deferredSyncTask?.cancel()
        deferredSyncTask = nil
        let guest = state(scope: "guest")
        accountID = id
        load(scope: "account_\(id)")
        hasResolvedPersistenceScope = true
        lastSuccessfulSyncAt = UserDefaults.standard.object(forKey: lastSuccessfulSyncKey(id)) as? Date
        if let lastSuccessfulSyncAt { syncState = .synced(lastSuccessfulSyncAt) }
        monitorRestTimer()
        refreshLiveActivity()
        let handled = Set(UserDefaults.standard.stringArray(forKey: "training_guest_handled_\(id)_v1") ?? [])
        let guestDeletedWorkouts = discardedWorkoutIDs(scope: "guest")
        pendingGuestWorkouts = guest.workouts.filter {
            !guestDeletedWorkouts.contains($0.id) && !handled.contains("workout:\($0.id.uuidString)") && !handled.contains($0.id.uuidString)
        }
        pendingGuestRoutines = guest.routines.filter { !handled.contains("routine:\($0.id.uuidString)") }
        pendingGuestExercises = guest.exercises.filter {
            $0.isCustom && !TrainingExercise.isRetiredImported($0) && !handled.contains("exercise:\($0.id.uuidString)")
        }.map { $0.normalizedImportedCatalogEntry() }
        pendingGuestMeasurements = (guest.bodyMeasurements ?? []).filter { !handled.contains("measurement:\($0.id.uuidString)") }
        pendingGuestWorkoutCount = pendingGuestWorkouts.count + pendingGuestRoutines.count + pendingGuestExercises.count + pendingGuestMeasurements.count
        retryRoutineShareRevocations()
        sync()
    }

    func deactivateAccount() {
        hasResolvedPersistenceScope = false
        flushPendingChanges()
        deferredSyncTask?.cancel()
        deferredSyncTask = nil
        accountID = nil
        lastSuccessfulSyncAt = nil
        pendingGuestWorkouts = []
        pendingGuestRoutines = []
        pendingGuestExercises = []
        pendingGuestMeasurements = []
        pendingGuestWorkoutCount = 0
        serverStreak = nil
        syncTask?.cancel()
        routineShareRevocationTask?.cancel()
        routineShareRevocationTask = nil
        syncIsRunning = false
        syncRequestedWhileRunning = false
        syncState = .local
        load(scope: "guest")
        hasResolvedPersistenceScope = true
        monitorRestTimer()
        refreshLiveActivity()
    }

    func resolveGuestMerge(shouldMerge: Bool) {
        guard let accountID else { return }
        let handled = pendingGuestWorkouts.map { "workout:\($0.id.uuidString)" }
            + pendingGuestRoutines.map { "routine:\($0.id.uuidString)" }
            + pendingGuestExercises.map { "exercise:\($0.id.uuidString)" }
            + pendingGuestMeasurements.map { "measurement:\($0.id.uuidString)" }
        if shouldMerge {
            let existing = Set(workouts.map(\.id))
            workouts.append(contentsOf: pendingGuestWorkouts.filter { !existing.contains($0.id) })
            let existingRoutines = Set(routines.map(\.id))
            routines.append(contentsOf: pendingGuestRoutines.filter { !existingRoutines.contains($0.id) })
            let existingExercises = Set(exercises.map(\.id))
            exercises.append(contentsOf: pendingGuestExercises.filter { !existingExercises.contains($0.id) })
            exercises = TrainingExercise.catalogDeduplicated(exercises)
            let existingMeasurements = Set(bodyMeasurements.map(\.id))
            bodyMeasurements.append(contentsOf: pendingGuestMeasurements.filter { !existingMeasurements.contains($0.id) })
            for (exerciseID, goal) in state(scope: "guest").progressGoals ?? [:] where progressGoals[exerciseID] == nil {
                progressGoals[exerciseID] = goal
            }
            _ = repairSavedRoutineExerciseTypes()
            _ = repairSavedWorkoutMuscleAssignments()
            markAllDirty()
            rebuildCompletedWorkouts()
            save()
        }
        UserDefaults.standard.set(handled, forKey: "training_guest_handled_\(accountID)_v1")
        pendingGuestWorkouts = []
        pendingGuestRoutines = []
        pendingGuestExercises = []
        pendingGuestMeasurements = []
        pendingGuestWorkoutCount = 0
        if shouldMerge { sync(force: true) }
    }

    func applyHevyImport(_ parsed: ParsedHevyImport) -> HevyImportSummary {
        let resolved = HevyImportService.resolvingExercises(parsed, against: exercises)
        let existingWorkoutIDs = Set(workouts.map(\.id))
        let newWorkouts = resolved.workouts.filter { !existingWorkoutIDs.contains($0.id) }
        let existingExerciseIDs = Set(exercises.map(\.id))
        let exerciseCandidates = resolved.customExercises.filter { !existingExerciseIDs.contains($0.id) }
        let acceptedExerciseIDs = Set(TrainingExercise.catalogDeduplicated(exercises + exerciseCandidates).map(\.id))
        let newExercises = exerciseCandidates.filter { acceptedExerciseIDs.contains($0.id) }
        let existingRoutineIDs = Set(routines.map(\.id))
        let existingRoutineNames = Set(routines.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines) })
        let newRoutines = resolved.routines.filter {
            !existingRoutineIDs.contains($0.id) &&
            !existingRoutineNames.contains($0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let existingMeasurementIDs = Set(bodyMeasurements.map(\.id))
        let newMeasurements = parsed.measurements.filter { !existingMeasurementIDs.contains($0.id) }

        // Re-importing an earlier Hevy export must also repair routines and
        // history that still point at a duplicate exercise ID. Keep any edits
        // to the user's sets and notes; only replace the exercise identity.
        let importedWorkoutsByID = Dictionary(uniqueKeysWithValues: resolved.workouts.map { ($0.id, $0) })
        var repairedWorkoutIDs = Set<UUID>()
        for workoutIndex in workouts.indices {
            guard let imported = importedWorkoutsByID[workouts[workoutIndex].id] else { continue }
            let importedLogsByID = Dictionary(uniqueKeysWithValues: imported.exercises.map { ($0.id, $0) })
            for exerciseIndex in workouts[workoutIndex].exercises.indices {
                let logID = workouts[workoutIndex].exercises[exerciseIndex].id
                guard let replacement = importedLogsByID[logID],
                      workouts[workoutIndex].exercises[exerciseIndex].exerciseID != replacement.exerciseID else { continue }
                workouts[workoutIndex].exercises[exerciseIndex].exerciseID = replacement.exerciseID
                workouts[workoutIndex].exercises[exerciseIndex].exerciseNameSnapshot = replacement.exerciseNameSnapshot
                workouts[workoutIndex].exercises[exerciseIndex].exerciseGermanNameSnapshot = replacement.exerciseGermanNameSnapshot
                workouts[workoutIndex].exercises[exerciseIndex].exerciseTypeSnapshot = replacement.exerciseTypeSnapshot
                workouts[workoutIndex].exercises[exerciseIndex].equipmentSnapshot = replacement.equipmentSnapshot
                workouts[workoutIndex].exercises[exerciseIndex].primaryMusclesSnapshot = replacement.primaryMusclesSnapshot
                workouts[workoutIndex].exercises[exerciseIndex].secondaryMusclesSnapshot = replacement.secondaryMusclesSnapshot
                repairedWorkoutIDs.insert(workouts[workoutIndex].id)
            }
            if repairedWorkoutIDs.contains(workouts[workoutIndex].id) { workouts[workoutIndex].updatedAt = Date() }
        }

        let importedRoutinesByID = Dictionary(uniqueKeysWithValues: resolved.routines.map { ($0.id, $0) })
        var repairedRoutineIDs = Set<UUID>()
        for routineIndex in routines.indices {
            guard let imported = importedRoutinesByID[routines[routineIndex].id] else { continue }
            let importedExercisesByID = Dictionary(uniqueKeysWithValues: imported.exercises.map { ($0.id, $0.exercise) })
            for exerciseIndex in routines[routineIndex].exercises.indices {
                let placementID = routines[routineIndex].exercises[exerciseIndex].id
                guard let replacement = importedExercisesByID[placementID],
                      routines[routineIndex].exercises[exerciseIndex].exercise.id != replacement.id else { continue }
                routines[routineIndex].exercises[exerciseIndex].exercise = replacement
                routines[routineIndex].exercises[exerciseIndex].sets = routines[routineIndex].exercises[exerciseIndex].sets.map { $0.normalized(for: replacement.type) }
                repairedRoutineIDs.insert(routines[routineIndex].id)
            }
            if repairedRoutineIDs.contains(routines[routineIndex].id) { routines[routineIndex].updatedAt = Date() }
        }

        workouts.append(contentsOf: newWorkouts)
        rebuildCompletedWorkouts()
        exercises.append(contentsOf: newExercises)
        routines.append(contentsOf: newRoutines)
        for routine in newRoutines { markRoutineDirty(routine.id) }
        for id in repairedRoutineIDs { markRoutineDirty(id) }
        bodyMeasurements.append(contentsOf: newMeasurements)
        bodyMeasurements.sort { $0.date > $1.date }
        if let accountID {
            var dirty = dirtyIDs(accountID)
            dirty.formUnion(newWorkouts.map(\.id))
            dirty.formUnion(repairedWorkoutIDs)
            store(dirty, key: dirtyKey(accountID))
            var dirtyExercises = ids(key: dirtyExerciseKey(accountID))
            dirtyExercises.formUnion(newExercises.map(\.id))
            store(dirtyExercises, key: dirtyExerciseKey(accountID))
        }
        save()
        if !newWorkouts.isEmpty || !newExercises.isEmpty || !newRoutines.isEmpty || !repairedWorkoutIDs.isEmpty || !repairedRoutineIDs.isEmpty { scheduleDeferredSync() }

        return HevyImportSummary(
            importedWorkouts: newWorkouts.count,
            skippedWorkouts: parsed.workouts.count - newWorkouts.count,
            importedRoutines: newRoutines.count,
            skippedRoutines: parsed.routines.count - newRoutines.count,
            importedExercises: newExercises.count,
            importedMeasurements: newMeasurements.count,
            skippedMeasurements: parsed.measurements.count - newMeasurements.count,
            ignoredRows: parsed.ignoredRows
        )
    }

    @discardableResult
    func addBodyWeight(kilograms: Double, date: Date) -> BodyMeasurement {
        let measurement = BodyMeasurement(
            id: UUID(), date: date, weightKilograms: kilograms,
            bodyFatPercentage: nil, centimeters: [:], source: "Hyse", updatedAt: Date()
        )
        bodyMeasurements.append(measurement)
        bodyMeasurements.sort { $0.date > $1.date }
        save()
        return measurement
    }

    @discardableResult
    func startEmptyWorkout(name: String? = nil) -> WorkoutLog {
        if let activeWorkout { return activeWorkout }
        clearExerciseRemovalUndo()
        let workout = WorkoutLog(name: name ?? LanguageStore.localizedString("training.workout.default_name"))
        workouts.append(workout)
        markDirty(workout.id)
        save()
        refreshLiveActivity()
        PhoneWatchConnectivityService.shared.startWatchWorkout(for: workout)
        scheduleDeferredSync()
        return workout
    }

    @discardableResult
    func start(routine: WorkoutRoutine, useRecentExerciseNotes: Bool = true) -> WorkoutLog {
        if let activeWorkout { return activeWorkout }
        clearExerciseRemovalUndo()
        var occurrences: [UUID: Int] = [:]
        let exercises = routine.exercises.map { item in
            let occurrence = occurrences[item.exercise.id, default: 0]
            occurrences[item.exercise.id] = occurrence + 1
            let notes = TrainingExerciseNoteHistory.notes(
                for: item,
                occurrence: occurrence,
                in: routine,
                completedWorkouts: completedWorkouts,
                useRecentNotes: useRecentExerciseNotes
            )
            return WorkoutExerciseLog(exerciseID: item.exercise.id, exerciseNameSnapshot: item.exercise.englishName, exerciseGermanNameSnapshot: item.exercise.germanName, exerciseTypeSnapshot: item.exercise.type, equipmentSnapshot: item.exercise.equipment, primaryMusclesSnapshot: item.exercise.primaryMuscles, secondaryMusclesSnapshot: item.exercise.secondaryMuscles, notes: notes, restSeconds: item.restSeconds, supersetGroup: item.supersetGroup, sets: item.sets.map { source in var value = source.normalized(for: item.exercise.type); value.id = UUID(); value.completed = false; value.completedAt = nil; value.personalRecordFlags = []; value.durationTimerEverStarted = nil; return value }, isUnilateralSnapshot: item.exercise.isUnilateral)
        }
        let workout = WorkoutLog(routineID: routine.id, name: routine.name, exercises: exercises)
        workouts.append(workout)
        markDirty(workout.id); save(); refreshLiveActivity()
        PhoneWatchConnectivityService.shared.startWatchWorkout(for: workout)
        scheduleDeferredSync()
        return workout
    }

    func repeatWorkout(_ source: WorkoutLog) {
        var routine = WorkoutRoutine(name: source.name, exercises: source.exercises.map { log in
            var exercise = exercises.first(where: { $0.id == log.exerciseID }) ?? TrainingExercise(id: log.exerciseID, nameKey: "custom", englishName: log.exerciseNameSnapshot, germanName: log.exerciseGermanNameSnapshot, descriptionKey: "", techniqueKey: "", type: log.exerciseTypeSnapshot, equipment: log.equipmentSnapshot, primaryMuscles: log.primaryMusclesSnapshot, secondaryMuscles: log.secondaryMusclesSnapshot, isCustom: true, isFavorite: false, updatedAt: Date())
            exercise.isUnilateral = log.isUnilateralSnapshot ?? exercise.isUnilateral
            // Repeating a workout keeps its structure and set types, while
            // previous performance is shown as a gray suggestion in the new
            // workout rather than being copied into editable fields.
            return RoutineExercise(exercise: exercise, notes: log.notes, restSeconds: log.restSeconds, supersetGroup: log.supersetGroup, sets: log.sets.map { set in
                var value = TrainingSetLog(type: set.type).normalized(for: exercise.type)
                value.id = UUID()
                return value
            })
        })
        if let sourceRoutineID = source.routineID { routine.id = sourceRoutineID }
        _ = start(routine: routine, useRecentExerciseNotes: false)
    }

    private func latestExerciseNotes(exerciseID: UUID, routine: WorkoutRoutine? = nil) -> String? {
        TrainingExerciseNoteHistory.latest(exerciseID: exerciseID, routine: routine, in: completedWorkouts)?.notes
    }

    @discardableResult
    func addExercise(_ exercise: TrainingExercise) -> UUID? {
        guard var workout = activeWorkout, let workoutIndex = workouts.firstIndex(where: { $0.id == workout.id }) else { return nil }
        // Previous performance stays a visual suggestion in the entry row.
        // Starting with an empty set lets the user type immediately instead
        // of having to clear last workout's values first.
        let placement = WorkoutExerciseLog(exerciseID: exercise.id, exerciseNameSnapshot: exercise.englishName, exerciseGermanNameSnapshot: exercise.germanName, exerciseTypeSnapshot: exercise.type, equipmentSnapshot: exercise.equipment, primaryMusclesSnapshot: exercise.primaryMuscles, secondaryMusclesSnapshot: exercise.secondaryMuscles, notes: latestExerciseNotes(exerciseID: exercise.id) ?? "", sets: [TrainingSetLog()], isUnilateralSnapshot: exercise.isUnilateral)
        workout.exercises.append(placement)
        workout.updatedAt = Date(); workouts[workoutIndex] = workout
        changed(workout.id)
        return placement.id
    }

    func removeExercise(_ exerciseID: UUID) {
        guard let workout = activeWorkout, let index = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let removed = workout.exercises[index]
        updateActive { $0.exercises.removeAll { $0.id == exerciseID } }
        removedExerciseUndo = (workout.id, index, removed)
        let undoID = UUID()
        exerciseRemovalUndoID = undoID
        exerciseRemovalUndoTask?.cancel()
        exerciseRemovalUndoTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.expireExerciseRemovalUndo(undoID)
        }
    }

    func undoLastExerciseRemoval() {
        guard let removed = removedExerciseUndo, activeWorkout?.id == removed.workoutID else { return }
        updateActive { $0.exercises.insert(removed.exercise, at: min(removed.index, $0.exercises.count)) }
        clearExerciseRemovalUndo()
    }

    func expireExerciseRemovalUndo(_ id: UUID) {
        guard exerciseRemovalUndoID == id else { return }
        clearExerciseRemovalUndo()
    }

    private func clearExerciseRemovalUndo() {
        exerciseRemovalUndoTask?.cancel()
        exerciseRemovalUndoTask = nil
        removedExerciseUndo = nil
        exerciseRemovalUndoID = nil
    }

    func duplicateExercise(_ exerciseID: UUID, includingSets: Bool = true) {
        updateActive { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            var copy = workout.exercises[index]; copy.id = UUID()
            copy.sets = (includingSets ? copy.sets : [TrainingSetLog()]).map { source in
                var set = source; set.stopDurationTimer(); set.durationTimerEverStarted = nil; set.id = UUID(); set.completed = false; set.completedAt = nil; set.personalRecordFlags = []; set.updatedAt = Date(); return set
            }
            workout.exercises.insert(copy, at: index + 1)
        }
    }

    func moveExercise(_ exerciseID: UUID, by offset: Int) {
        updateActive { workout in
            guard let source = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            let destination = max(0, min(workout.exercises.count - 1, source + offset))
            guard source != destination else { return }
            let value = workout.exercises.remove(at: source); workout.exercises.insert(value, at: destination)
        }
    }

    /// Persists the drag-and-drop order from the active-workout exercise
    /// overview. `IndexSet` also keeps the method correct if list editing is
    /// expanded to support moving several selected exercises later on.
    func moveExercises(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else { return }
        updateActive { workout in
            let orderedSource = source.sorted()
            let moving = orderedSource.map { workout.exercises[$0] }
            for index in orderedSource.reversed() {
                workout.exercises.remove(at: index)
            }
            let removedBeforeDestination = orderedSource.filter { $0 < destination }.count
            let insertionIndex = max(0, min(workout.exercises.count, destination - removedBeforeDestination))
            workout.exercises.insert(contentsOf: moving, at: insertionIndex)
        }
    }

    /// Updates the visible order while a drag is in progress. This deliberately
    /// avoids `updateActive`: serializing a full workout and refreshing the
    /// Live Activity for every hovered row makes long reorders stutter.
    func previewActiveExerciseReorder(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty,
              var workout = activeWorkout,
              let workoutIndex = workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        let orderedSource = source.sorted()
        guard orderedSource.allSatisfy({ workout.exercises.indices.contains($0) }) else { return }
        let moving = orderedSource.map { workout.exercises[$0] }
        for index in orderedSource.reversed() {
            workout.exercises.remove(at: index)
        }
        let removedBeforeDestination = orderedSource.filter { $0 < destination }.count
        let insertionIndex = max(0, min(workout.exercises.count, destination - removedBeforeDestination))
        workout.exercises.insert(contentsOf: moving, at: insertionIndex)
        workouts[workoutIndex] = workout
        activeExerciseReorderNeedsSaving = true
    }

    /// Commits the final drag position in one local write and schedules the
    /// normal account sync. Calling this more than once is intentionally safe.
    func commitActiveExerciseReorder() {
        guard activeExerciseReorderNeedsSaving,
              var workout = activeWorkout,
              let workoutIndex = workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        activeExerciseReorderNeedsSaving = false
        workout.updatedAt = Date()
        workouts[workoutIndex] = workout
        markDirty(workout.id)
        save()
        scheduleDeferredSync()
    }

    func updateExerciseDetails(_ exerciseID: UUID, notes: String? = nil, restSeconds: Int? = nil) {
        updateActive(journalImmediately: notes == nil) { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            if let notes { workout.exercises[index].notes = notes }
            if let restSeconds { workout.exercises[index].restSeconds = max(0, restSeconds) }
        }
        if let notes, pendingExerciseNotes[exerciseID] == notes {
            pendingExerciseNotes.removeValue(forKey: exerciseID)
        }
    }

    func setExerciseUnilateral(_ isUnilateral: Bool, for exerciseID: UUID) {
        updateActive { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            workout.exercises[index].isUnilateralSnapshot = isUnilateral
        }
    }

    func stageExerciseNotes(_ notes: String, for exerciseID: UUID) {
        guard activeWorkout?.exercises.contains(where: { $0.id == exerciseID }) == true else { return }
        pendingExerciseNotes[exerciseID] = notes
    }

    /// A recreated exercise row (lazy scrolling, reordering) must show the
    /// newest typed text instead of the older stored note.
    func exerciseNotesDraft(for exerciseID: UUID) -> String? { pendingExerciseNotes[exerciseID] }

    /// Writes typed but not yet debounced exercise notes into the active
    /// workout. Lifecycle flushes call this first, so closing the app right
    /// after typing cannot lose the note regardless of view update order.
    private func applyPendingExerciseNotes() {
        guard !pendingExerciseNotes.isEmpty else { return }
        let drafts = pendingExerciseNotes
        pendingExerciseNotes.removeAll()
        updateActive { workout in
            for index in workout.exercises.indices {
                if let draft = drafts[workout.exercises[index].id] { workout.exercises[index].notes = draft }
            }
        }
    }

    @discardableResult
    func addSet(to workoutExerciseID: UUID) -> TrainingSetLog? {
        var addedSet: TrainingSetLog?
        updateActive { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == workoutExerciseID }) else { return }
            let exerciseType = workout.exercises[index].exerciseTypeSnapshot
            let currentLastSet = workout.exercises[index].sets.last
            // Only duplicate values the user entered in this workout. Values
            // from an older workout are intentionally left as placeholders.
            let previous = currentLastSet.flatMap { hasEnteredValues($0) ? $0 : nil }
                ?? TrainingSetLog(type: currentLastSet?.type ?? .normal)
            var next = previous.normalized(for: exerciseType); next.stopDurationTimer(); next.durationTimerEverStarted = nil; next.id = UUID(); next.completed = false; next.completedAt = nil; next.personalRecordFlags = []; next.updatedAt = Date()
            workout.exercises[index].sets.append(next)
            addedSet = next
        }
        return addedSet
    }

    func duplicateSet(exerciseID: UUID, setID: UUID) {
        updateActive { workout in
            guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }), let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
            var copy = workout.exercises[exerciseIndex].sets[setIndex].normalized(for: workout.exercises[exerciseIndex].exerciseTypeSnapshot)
            copy.stopDurationTimer()
            copy.id = UUID(); copy.completed = false; copy.completedAt = nil; copy.personalRecordFlags = []; copy.durationTimerEverStarted = nil; copy.updatedAt = Date()
            workout.exercises[exerciseIndex].sets.insert(copy, at: setIndex + 1)
        }
    }

    func updateSet(exerciseID: UUID, set: TrainingSetLog) {
        updateActive { workout in
            guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }), let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id }) else { return }
            let exerciseType = workout.exercises[exerciseIndex].exerciseTypeSnapshot
            var changedSet = set.normalized(for: exerciseType); changedSet.updatedAt = Date()
            workout.exercises[exerciseIndex].sets[setIndex] = changedSet
        }
    }

    func toggleSet(exerciseID: UUID, setID: UUID) {
        updateSetCompletion(exerciseID: exerciseID, setID: setID)
    }

    /// Completes a set and applies its current draft values in one local update.
    /// This keeps the checkmark action from saving the same set twice.
    func completeSet(exerciseID: UUID, set: TrainingSetLog) {
        updateSetCompletion(exerciseID: exerciseID, setID: set.id, updatedSet: set)
    }

    private func updateSetCompletion(exerciseID: UUID, setID: UUID, updatedSet: TrainingSetLog? = nil) {
        var rest = 0
        var recordFlags: [String] = []
        var didComplete = false
        updateActive(journalImmediately: false) { workout in
            guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }), let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
            let exerciseType = workout.exercises[exerciseIndex].exerciseTypeSnapshot
            var changedSet = (updatedSet ?? workout.exercises[exerciseIndex].sets[setIndex]).normalized(for: exerciseType)
            if updatedSet == nil {
                changedSet.completed.toggle()
            } else {
                changedSet.id = setID
                changedSet.completed = true
            }
            let isCompleted = changedSet.completed
            if isCompleted { changedSet.stopDurationTimer() }
            didComplete = isCompleted
            changedSet.completedAt = isCompleted ? Date() : nil
            changedSet.personalRecordFlags = isCompleted
                ? personalRecordFlags(for: changedSet, exerciseID: workout.exercises[exerciseIndex].exerciseID, in: workout)
                : []
            recordFlags = changedSet.personalRecordFlags
            changedSet.updatedAt = Date()
            workout.exercises[exerciseIndex].sets[setIndex] = changedSet
            rest = workout.exercises[exerciseIndex].restSeconds
        }
        if rest > 0, activeWorkout?.exercises.first(where: { $0.id == exerciseID })?.sets.first(where: { $0.id == setID })?.completed == true {
            startRestTimer(seconds: rest)
        }
        if didComplete {
            scheduleSetFeedback(hasRecord: !recordFlags.isEmpty)
        }
        latestPersonalRecordFlags = recordFlags
        if didComplete, !recordFlags.isEmpty,
           let exercise = activeWorkout?.exercises.first(where: { $0.id == exerciseID }),
           let completedSet = exercise.sets.first(where: { $0.id == setID }) {
            latestPersonalRecordFeedback = TrainingPersonalRecordFeedback(
                flags: recordFlags,
                exerciseName: exercise.exerciseNameSnapshot,
                exerciseGermanName: exercise.exerciseGermanNameSnapshot,
                weightKilograms: completedSet.weightKilograms,
                repetitions: completedSet.reps,
                setVolume: completedSet.volume,
                estimatedOneRepMaximum: completedSet.estimatedOneRepMaximum
            )
        }
        // The checkmark is published before the coalesced journal and snapshot
        // writes. ContentView flushes them if the app leaves the foreground.
    }

    private func scheduleSetFeedback(hasRecord: Bool) {
        pendingSetFeedbackHasRecord = pendingSetFeedbackHasRecord || hasRecord
        deferredSetFeedbackTask?.cancel()
        deferredSetFeedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self else { return }
            let playRecordSound = self.pendingSetFeedbackHasRecord
            self.pendingSetFeedbackHasRecord = false
            self.deferredSetFeedbackTask = nil
            if playRecordSound {
                RestFeedbackController.shared.playPersonalRecord()
            } else {
                RestFeedbackController.shared.playSetCompletion()
            }
        }
    }

    func clearPersonalRecordFeedback() {
        latestPersonalRecordFlags = []
        latestPersonalRecordFeedback = nil
    }

    func toggleSuperset(_ workoutExerciseID: UUID) {
        updateActive { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == workoutExerciseID }) else { return }
            if let group = workout.exercises[index].supersetGroup, !group.isEmpty {
                for itemIndex in workout.exercises.indices where workout.exercises[itemIndex].supersetGroup == group {
                    workout.exercises[itemIndex].supersetGroup = nil
                }
            } else if workout.exercises.count > 1 {
                let partnerIndex = index == 0 ? 1 : index - 1
                let group = "superset-\(UUID().uuidString.lowercased())"
                workout.exercises[partnerIndex].supersetGroup = group
                workout.exercises[index].supersetGroup = group
            }
        }
    }

    func startRestTimer(seconds: Int) {
        guard seconds > 0 else { return }
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        restTimerTask?.cancel()
        RestFeedbackController.shared.cancelPlayback()
        restTimerID = UUID()
        restTimerEnd = end
        scheduleLocalSave()
        restTimerFinished = false
        monitorRestTimer()
        scheduleLiveActivityRefresh()
    }

    func adjustRestTimer(by seconds: Int) {
        guard let current = restTimerEnd else { return }
        let adjusted = max(Date(), current.addingTimeInterval(TimeInterval(seconds)))
        let remaining = Int(adjusted.timeIntervalSinceNow.rounded(.up))
        if remaining <= 0 { skipRestTimer() }
        else { restTimerEnd = adjusted; save(); monitorRestTimer(); refreshLiveActivity() }
    }

    func skipRestTimer() {
        restTimerTask?.cancel(); restTimerTask = nil
        RestTimerNotificationController.shared.cancel()
        restTimerEnd = nil
        restTimerID = nil
        restTimerFinished = false
        save()
        RestFeedbackController.shared.cancelPlayback()
        refreshLiveActivity()
    }

    func clearRestTimerFinished() { restTimerFinished = false; refreshLiveActivity() }

    func preferencesDidChange() {
        if restTimerEnd != nil { monitorRestTimer() }
        refreshLiveActivity()
    }
    func handleSceneBecameActive() { monitorRestTimer(); refreshLiveActivity() }

    func flushPendingChanges() {
        // Active-workout edits are coalesced while the user is typing or
        // swiping. Lifecycle changes flush them before iOS suspends the app.
        commitActiveExerciseReorder()
        applyPendingExerciseNotes()
        deferredActiveJournalTask?.cancel()
        deferredActiveJournalTask = nil
        deferredActiveSaveTask?.cancel()
        deferredActiveSaveTask = nil
        persistPendingActiveChanges()
        save()
    }

    func toggleWorkoutPause() {
        updateActive { workout in
            if workout.status == .paused {
                if let pausedAt = workout.pausedAt {
                    workout.accumulatedPausedSeconds = (workout.accumulatedPausedSeconds ?? 0) + Date().timeIntervalSince(pausedAt)
                }
                workout.pausedAt = nil
                workout.status = .active
            } else {
                workout.pausedAt = Date()
                workout.status = .paused
            }
        }
    }

    func deleteSet(exerciseID: UUID, setID: UUID) {
        updateActive { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            workout.exercises[index].sets.removeAll { $0.id == setID }
        }
    }

    func renameActiveWorkout(_ name: String) { updateActive(journalImmediately: false) { $0.name = name } }
    func updateActiveNotes(_ notes: String) { updateActive(journalImmediately: false) { $0.notes = notes } }

    func updateCompletedWorkout(_ edited: WorkoutLog) {
        guard edited.status == .completed,
              let index = workouts.firstIndex(where: { $0.id == edited.id }) else { return }
        var value = edited
        value.updatedAt = Date()
        workouts[index] = value
        rebuildCompletedWorkouts()
        persistWorkoutCompletionReceipt(value)
        persistCompletedWorkoutCheckpoint(value)
        changed(value.id)
        flushPendingChanges()
        UserDefaults.standard.synchronize()
        sync(force: true)
    }

    func deleteCompletedWorkout(_ id: UUID) {
        guard workouts.contains(where: { $0.id == id && $0.status == .completed }) else { return }
        recordWorkoutDeletion(id)
        workouts.removeAll { $0.id == id }
        rebuildCompletedWorkouts()
        save()
        UserDefaults.standard.synchronize()
        // A deleted workout must disappear from the social feed promptly; a
        // deferred sync would let the server return it during the next refresh.
        sync(force: true)
    }

    func saveWorkoutMedia(_ data: Data, workoutID: UUID, fileExtension: String) -> String? {
        guard !data.isEmpty,
              let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = applicationSupport.appendingPathComponent("HyseWorkoutMedia", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeExtension = fileExtension.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
            let filename = "\(workoutID.uuidString.lowercased()).\(safeExtension.isEmpty ? "media" : safeExtension)"
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            logger.error("Could not save local workout media: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func finishActiveWorkout() -> WorkoutLog? {
        commitActiveExerciseReorder()
        guard var workout = activeWorkout, workout.completedSets.count > 0, let index = workouts.firstIndex(where: { $0.id == workout.id }) else { return nil }
        clearExerciseRemovalUndo()
        for exerciseIndex in workout.exercises.indices {
            let id = workout.exercises[exerciseIndex].id
            if let draft = pendingExerciseNotes[id] { workout.exercises[exerciseIndex].notes = draft }
        }
        pendingExerciseNotes.removeAll()
        if let pausedAt = workout.pausedAt {
            workout.accumulatedPausedSeconds = (workout.accumulatedPausedSeconds ?? 0) + Date().timeIntervalSince(pausedAt)
            workout.pausedAt = nil
        }
        let completedAt = Date()
        workout.status = .completed; workout.completedAt = completedAt; workout.updatedAt = completedAt; workout.syncError = false
        for exerciseIndex in workout.exercises.indices {
            for setIndex in workout.exercises[exerciseIndex].sets.indices {
                workout.exercises[exerciseIndex].sets[setIndex].stopDurationTimer(at: completedAt)
            }
        }
        // A completed checkpoint survives an interrupted full-state write and
        // cannot be mistaken for the older active-workout journal on relaunch.
        persistWorkoutCompletionReceipt(workout)
        persistCompletedWorkoutCheckpoint(workout)
        workouts[index] = workout; rebuildCompletedWorkouts(); skipRestTimer(); changed(workout.id)
        flushPendingChanges()
        UserDefaults.standard.synchronize()
        sync(force: true)
        TrainingLiveActivityController.shared.finish(workout: workout, weightUnit: trainingWeightUnit)
        PhoneWatchConnectivityService.shared.endWatchWorkout(save: true)
        return workout
    }

    func discardActiveWorkout() {
        activeExerciseReorderNeedsSaving = false
        guard let workout = activeWorkout else { return }
        clearExerciseRemovalUndo()
        pendingExerciseNotes.removeAll()
        deferredActiveSaveTask?.cancel()
        deferredActiveSaveTask = nil
        pendingActiveWorkoutID = nil
        recordWorkoutDeletion(workout.id)
        workouts.removeAll { $0.id == workout.id }
        skipRestTimer()
        Task { await TrainingLiveActivityController.shared.endAll() }
        save()
        UserDefaults.standard.synchronize()
        PhoneWatchConnectivityService.shared.endWatchWorkout(save: false)
        sync(force: true)
    }

    func createRoutine(name: String, details: String = "", folder: String = "", plannedWeekday: Int? = nil, exercises selected: [TrainingExercise]) {
        let routine = WorkoutRoutine(
            name: name,
            details: details,
            folder: folder,
            plannedWeekday: plannedWeekday,
            exercises: selected.map { RoutineExercise(exercise: $0) }
        )
        routines.append(routine)
        markRoutineDirty(routine.id)
        save(); scheduleDeferredSync()
    }

    @discardableResult
    func saveRoutine(_ routine: WorkoutRoutine) -> Bool {
        var value = routine
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.details = value.details.trimmingCharacters(in: .whitespacesAndNewlines)
        value.folder = value.folder.trimmingCharacters(in: .whitespacesAndNewlines)
        value.updatedAt = Date()
        guard !value.name.isEmpty, !value.exercises.isEmpty else { return false }
        let previousExercises = Dictionary(
            (routines.first(where: { $0.id == value.id })?.exercises ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for index in value.exercises.indices {
            let placement = value.exercises[index]
            if let previous = previousExercises[placement.id] {
                if previous.notes != placement.notes { value.exercises[index].notesUpdatedAt = value.updatedAt }
            } else if !placement.notes.isEmpty && placement.notesUpdatedAt == nil {
                value.exercises[index].notesUpdatedAt = value.updatedAt
            }
        }
        if let index = routines.firstIndex(where: { $0.id == value.id }) { routines[index] = value }
        else { routines.append(value) }
        markRoutineDirty(value.id)
        save(); scheduleDeferredSync()
        return true
    }

    @discardableResult
    func addSuggestedProgram(_ program: SuggestedRoutineProgram) -> Int {
        let existingNames = Set(routines.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var added = 0
        for source in program.routines where !existingNames.contains(source.name.lowercased()) {
            var routine = source
            routine.id = UUID(); routine.remoteID = nil; routine.updatedAt = Date()
            routine.exercises = routine.exercises.map { item in
                var value = item; value.id = UUID()
                value.sets = value.sets.map { set in var copy = set; copy.id = UUID(); return copy }
                return value
            }
            routines.append(routine)
            markRoutineDirty(routine.id)
            added += 1
        }
        if added > 0 { save(); scheduleDeferredSync() }
        return added
    }

    @discardableResult
    func ensureRoutine(from workout: WorkoutLog) -> UUID {
        if let routineID = workout.routineID,
           routines.contains(where: { $0.id == routineID }) {
            return routineID
        }
        if let existing = routines.first(where: {
            $0.name == workout.name && $0.exercises.map(\.exercise.id) == workout.exercises.map(\.exerciseID)
        }) {
            return existing.id
        }
        let routine = WorkoutRoutine(name: workout.name, exercises: routineExercises(from: workout))
        routines.append(routine)
        markRoutineDirty(routine.id)
        save()
        scheduleDeferredSync()
        return routine.id
    }

    func createRoutine(from workout: WorkoutLog) {
        _ = ensureRoutine(from: workout)
    }

    func updateRoutineValues(_ routineID: UUID, from workout: WorkoutLog) {
        guard let index = routines.firstIndex(where: { $0.id == routineID }) else { return }
        routines[index].exercises = routineExercises(from: workout)
        routines[index].updatedAt = Date()
        markRoutineDirty(routineID)
        save()
        scheduleDeferredSync()
    }

    private func routineExercises(from workout: WorkoutLog) -> [RoutineExercise] {
        workout.exercises.map { log -> RoutineExercise in
            var exercise = exercises.first(where: { $0.id == log.exerciseID }) ?? TrainingExercise(
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
            exercise.isUnilateral = log.isUnilateralSnapshot ?? exercise.isUnilateral
            return RoutineExercise(exercise: exercise, notes: log.notes, restSeconds: log.restSeconds, supersetGroup: log.supersetGroup, sets: log.sets.map { set in var value = set; value.id = UUID(); value.completed = false; value.completedAt = nil; return value })
        }
    }

    @discardableResult
    func duplicateRoutine(_ routine: WorkoutRoutine) -> Bool {
        var copy = routine; copy.id = UUID(); copy.remoteID = nil; copy.shareRecordID = nil; copy.name += " \(LanguageStore.localizedString("training.routine.copy_suffix"))"; copy.updatedAt = Date()
        copy.exercises = copy.exercises.map { item in var value = item; value.id = UUID(); value.sets = value.sets.map { var set = $0; set.id = UUID(); return set }; return value }
        routines.append(copy); markAllDirty(); save(); scheduleDeferredSync()
        return true
    }

    func deleteRoutine(_ id: UUID) {
        if let shareID = routines.first(where: { $0.id == id })?.shareRecordID, let accountID {
            let key = "routine_share_revocations_\(accountID)_v1"
            var pending = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
            pending.insert(shareID)
            UserDefaults.standard.set(Array(pending), forKey: key)
        }
        routines.removeAll { $0.id == id }
        if let accountID {
            var deleted = ids(key: deletedRoutineKey(accountID)); deleted.insert(id)
            store(deleted, key: deletedRoutineKey(accountID))
        }
        save(); scheduleDeferredSync(); retryRoutineShareRevocations()
    }

    func moveRoutine(_ sourceID: UUID, to targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = routines.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = routines.firstIndex(where: { $0.id == targetID }) else { return }
        let routine = routines.remove(at: sourceIndex)
        routines.insert(routine, at: targetIndex)
        let now = Date()
        for index in routines.indices where routines[index].sortOrder != index {
            routines[index].sortOrder = index
            routines[index].updatedAt = now
            markRoutineDirty(routines[index].id)
        }
        save()
        scheduleDeferredSync()
    }

    func setRoutineOrder(_ orderedIDs: [UUID]) {
        guard orderedIDs.count == routines.count,
              Set(orderedIDs) == Set(routines.map(\.id)),
              orderedIDs != routines.map(\.id) else { return }
        let byID = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
        routines = orderedIDs.compactMap { byID[$0] }
        let now = Date()
        for index in routines.indices where routines[index].sortOrder != index {
            routines[index].sortOrder = index
            routines[index].updatedAt = now
            markRoutineDirty(routines[index].id)
        }
        save()
        scheduleDeferredSync()
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        exercises[index].isFavorite.toggle(); exercises[index].updatedAt = Date()
        if let accountID {
            var overrides = favoriteOverrides(accountID)
            overrides[id] = exercises[index].isFavorite
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.uuidString.lowercased(), $0.value) }), forKey: favoriteOverrideKey(accountID))
        }
        save(); scheduleDeferredSync()
    }

    @discardableResult
    func addCustomExercise(
        name: String,
        type: TrainingExerciseType,
        equipment: TrainingEquipment,
        primaryMuscle: String,
        isUnilateral: Bool = false,
        imageData: Data? = nil
    ) -> Bool {
        let customName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customName.isEmpty else { return false }
        let value = TrainingExercise(
            id: UUID(),
            nameKey: "custom",
            englishName: customName,
            germanName: customName,
            descriptionKey: "",
            techniqueKey: "",
            type: type,
            equipment: equipment,
            primaryMuscles: [primaryMuscle],
            secondaryMuscles: [],
            isCustom: true,
            isFavorite: false,
            updatedAt: Date(),
            customImageData: imageData,
            isUnilateral: isUnilateral
        )
        guard TrainingExercise.catalogDeduplicated(exercises + [value]).contains(where: { $0.id == value.id }) else {
            return true
        }
        if let accountID {
            var dirty = ids(key: dirtyExerciseKey(accountID)); dirty.insert(value.id)
            store(dirty, key: dirtyExerciseKey(accountID))
        }
        exercises.append(value); save(); scheduleDeferredSync()
        return true
    }

    func workouts(on date: Date) -> [WorkoutLog] { completedWorkouts.filter { Calendar.current.isDate($0.completedAt ?? $0.startedAt, inSameDayAs: date) } }

    func routines(plannedFor date: Date) -> [WorkoutRoutine] {
        let weekday = Calendar.current.component(.weekday, from: date)
        return routines
            .filter { $0.plannedWeekday == weekday }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func routine(plannedFor date: Date) -> WorkoutRoutine? {
        routines(plannedFor: date).first
    }

    var routineFolders: [String] {
        Array(Set(routines.map(\.folder).filter { !$0.isEmpty })).sorted()
    }

    var recentlyUsedExerciseIDs: [UUID] {
        var result: [UUID] = []
        for exercise in completedWorkouts.prefix(12).flatMap(\.exercises) where !result.contains(exercise.exerciseID) {
            result.append(exercise.exerciseID)
        }
        return result
    }

    var statistics: TrainingStatistics {
        statistics(halveUnilateral: UserDefaults.standard.bool(forKey: TrainingSetStatistics.settingKey))
    }

    func statistics(halveUnilateral: Bool) -> TrainingStatistics {
        let calendar = Calendar.current
        let completed = completedWorkouts
        let workoutDates = completed.map { $0.completedAt ?? $0.startedAt }
        let workoutWeeks = Set(workoutDates.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        let frozenWeeks = Set(streakFrozenWeekKeys.compactMap { StreakTracker.date(forDayKey: $0, calendar: calendar) })
        let weeks = workoutWeeks.union(frozenWeeks)
        let streak = Self.weeklyStreak(weeks: weeks, calendar: calendar)
        let longest = Self.longestWeeklyStreak(weeks: weeks, calendar: calendar)
        let week = calendar.dateInterval(of: .weekOfYear, for: Date())
        let thisWeek = completed.filter { week?.contains($0.completedAt ?? $0.startedAt) == true }
        let firstDate = completed.last.map { $0.completedAt ?? $0.startedAt }
        let activeWeekCount = max(1, (firstDate.map { calendar.dateComponents([.weekOfYear], from: $0, to: Date()).weekOfYear ?? 0 } ?? 0) + 1)
        return TrainingStatistics(
            workoutCount: completed.count,
            totalDuration: completed.reduce(0) { $0 + $1.duration },
            totalVolume: completed.reduce(0) { $0 + $1.totalVolume },
            currentStreak: streak,
            longestStreak: longest,
            trainedThisWeek: !thisWeek.isEmpty,
            workoutsThisWeek: thisWeek.count,
            setsThisWeek: TrainingSetStatistics.count(thisWeek, halveUnilateral: halveUnilateral),
            personalRecordCount: completed.flatMap(\.completedSets).filter(\.hasPersonalRecord).count,
            averageWorkoutsPerWeek: Double(completed.count) / Double(activeWeekCount)
        )
    }

    var lastWorkout: WorkoutLog? { completedWorkouts.first }
    var recentMuscles: [String] { Array(completedWorkouts.prefix(3).flatMap(\.muscleGroups).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(4)) }

    func applyStreakFreezeWeeks(_ weeks: Set<String>) {
        streakFrozenWeekKeys = weeks
    }

    /// Returns the heaviest completed working set from the latest workout with
    /// this exercise. A light drop set at the end should not lower the next goal.
    func latestCompletedSet(exerciseID: UUID) -> TrainingSetLog? {
        var fallback: TrainingSetLog?
        for workout in completedWorkouts {
            let matchingSets = workout.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
            let workingSets = matchingSets.filter { $0.completed && $0.type == .normal }
            if let set = workingSets.max(by: {
                $0.weightKilograms == $1.weightKilograms
                    ? $0.reps < $1.reps
                    : $0.weightKilograms < $1.weightKilograms
            }) { return set }
            if fallback == nil { fallback = matchingSets.last(where: \.completed) }
        }
        return fallback
    }

    func previousPerformance(workoutExerciseID: UUID, setPosition: Int) -> TrainingSetLog? {
        guard setPosition >= 0 else { return nil }
        return previousPerformances(workoutExerciseID: workoutExerciseID, count: setPosition + 1)[setPosition]
    }

    func setProgressGoal(_ goal: ExerciseProgressGoal?, for exerciseID: UUID) {
        progressGoals[exerciseID] = goal
        save()
    }

    func previousPerformances(workoutExerciseID: UUID, count: Int) -> [TrainingSetLog?] {
        guard count > 0 else { return [] }
        guard let activeWorkout else { return Array(repeating: nil, count: count) }
        let placementIDs = activeWorkout.exercises.map(\.id)
        if previousPerformanceCacheWorkoutID != activeWorkout.id
            || previousPerformanceCacheWorkoutName != activeWorkout.name
            || previousPerformanceCachePlacementIDs != placementIDs
            || previousPerformanceCache == nil {
            previousPerformanceCache = TrainingPreviousPerformance.setsByPlacement(
                for: activeWorkout,
                in: completedWorkouts
            )
            previousPerformanceCacheWorkoutID = activeWorkout.id
            previousPerformanceCacheWorkoutName = activeWorkout.name
            previousPerformanceCachePlacementIDs = placementIDs
        }
        let result = previousPerformanceCache?[workoutExerciseID] ?? []
        return (0..<count).map { $0 < result.count ? result[$0] : nil }
    }

    func exerciseProgress(exerciseID: UUID) -> ExerciseProgressSummary {
        let sessions: [(WorkoutLog, [TrainingSetLog])] = completedWorkouts.compactMap { workout in
            let sets = workout.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter(\.completed)
            return sets.isEmpty ? nil : (workout, sets)
        }
        let allSets = sessions.flatMap { $0.1 }
        let points = sessions.map { workout, sets in
            let cardioSets = sets.filter { $0.distanceMeters > 0 && $0.durationSeconds > 0 }
            return ExerciseProgressPoint(
                id: workout.id,
                date: workout.completedAt ?? workout.startedAt,
                bestWeightKilograms: sets.map(\.weightKilograms).max() ?? 0,
                bestRepetitions: sets.map(\.reps).max() ?? 0,
                bestSetVolume: sets.map(\.volume).max() ?? 0,
                estimatedOneRepMaximum: sets.map(\.estimatedOneRepMaximum).max() ?? 0,
                distanceMeters: sets.reduce(0) { $0 + max(0, $1.distanceMeters) },
                durationSeconds: sets.reduce(0) { $0 + max(0, $1.durationSeconds) },
                paceSecondsPerKilometer: cardioSets.compactMap(\.paceSecondsPerKilometer).min()
            )
        }.sorted { $0.date < $1.date }
        return ExerciseProgressSummary(
            exerciseID: exerciseID,
            workoutCount: sessions.count,
            completedSetCount: allSets.filter { $0.type != .warmup }.count,
            bestWeightKilograms: allSets.map(\.weightKilograms).max() ?? 0,
            bestRepetitions: allSets.map(\.reps).max() ?? 0,
            bestSetVolume: allSets.map(\.volume).max() ?? 0,
            estimatedOneRepMaximum: allSets.map(\.estimatedOneRepMaximum).max() ?? 0,
            totalDistanceMeters: allSets.reduce(0) { $0 + max(0, $1.distanceMeters) },
            totalDurationSeconds: allSets.reduce(0) { $0 + max(0, $1.durationSeconds) },
            bestPaceSecondsPerKilometer: allSets.compactMap(\.paceSecondsPerKilometer).min(),
            points: points
        )
    }

    var muscleDistribution: [MuscleTrainingVolume] {
        var setsByMuscle: [String: Double] = [:]
        var volumeByMuscle: [String: Double] = [:]
        let halveUnilateral = UserDefaults.standard.bool(forKey: TrainingSetStatistics.settingKey)
        for workout in completedWorkouts {
            for exercise in workout.exercises {
                let sets = exercise.sets.filter(\.completed)
                guard !sets.isEmpty else { continue }
                let corrected = TrainingExercise.repairedMuscleAssignment(
                    exerciseID: exercise.exerciseID,
                    englishName: exercise.exerciseNameSnapshot,
                    germanName: exercise.exerciseGermanNameSnapshot,
                    type: exercise.exerciseTypeSnapshot,
                    equipment: exercise.equipmentSnapshot,
                    primary: exercise.primaryMusclesSnapshot,
                    secondary: exercise.secondaryMusclesSnapshot
                )
                for muscle in corrected?.primary ?? exercise.primaryMusclesSnapshot {
                    setsByMuscle[muscle, default: 0] += TrainingSetStatistics.count(exercise, halveUnilateral: halveUnilateral)
                    volumeByMuscle[muscle, default: 0] += sets.reduce(0) { $0 + $1.volume }
                }
            }
        }
        return setsByMuscle.map { muscle, sets in
            MuscleTrainingVolume(muscle: muscle, completedSets: sets, volume: volumeByMuscle[muscle, default: 0])
        }.sorted { $0.completedSets > $1.completedSets }
    }

    private func personalRecordFlags(for candidate: TrainingSetLog, exerciseID: UUID, in workout: WorkoutLog) -> [String] {
        if previousRecordBestCache[exerciseID] == nil {
            var best = TrainingPersonalRecordBest()
            for completedWorkout in completedWorkouts {
                for placement in completedWorkout.exercises where placement.exerciseID == exerciseID {
                    for set in placement.sets {
                        best.include(set)
                    }
                }
            }
            previousRecordBestCache[exerciseID] = best
        }
        var best = previousRecordBestCache[exerciseID] ?? TrainingPersonalRecordBest()
        for placement in workout.exercises where placement.exerciseID == exerciseID {
            for set in placement.sets where set.id != candidate.id {
                best.include(set)
            }
        }
        return best.flags(for: candidate)
    }

    private func hasEnteredValues(_ set: TrainingSetLog) -> Bool {
        set.weightKilograms != 0 || set.reps != 0 || set.durationSeconds != 0 || set.distanceMeters != 0 || set.assistedKilograms != 0
    }

    private func monitorRestTimer() {
        restTimerTask?.cancel()
        guard let end = restTimerEnd, let timerID = restTimerID else {
            RestTimerNotificationController.shared.cancel(removeDelivered: false)
            return
        }
        guard end > Date() else {
            finishRestTimer(timerID: timerID, deadline: end, allowFeedback: false)
            return
        }
        RestTimerNotificationController.shared.schedule(timerID: timerID, end: end)
        restTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.restTimerEnd == end, self.restTimerID == timerID else { return }
            guard UIApplication.shared.applicationState == .active else { return }
            self.finishRestTimer(timerID: timerID, deadline: end, allowFeedback: Date().timeIntervalSince(end) < 1.5)
        }
    }

    private func finishRestTimer(timerID: UUID, deadline: Date, allowFeedback: Bool) {
        guard restTimerID == timerID, restTimerEnd == deadline else { return }
        restTimerEnd = nil
        restTimerID = nil
        restTimerFinished = true
        RestTimerNotificationController.shared.cancel(removeDelivered: false)
        save()
        refreshLiveActivity()
        if allowFeedback { RestFeedbackController.shared.playTimerCompletion(timerID: timerID) }
    }

    private func updateActive(journalImmediately: Bool = true, _ changes: (inout WorkoutLog) -> Void) {
        guard var workout = activeWorkout, let index = workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        let previous = workout
        changes(&workout)
        guard workout != previous else { return }
        workout.updatedAt = Date()
        workouts[index] = workout
        if journalImmediately {
            deferredActiveJournalTask?.cancel()
            deferredActiveJournalTask = nil
            persistActiveJournal(workout)
        } else {
            scheduleActiveJournal()
        }
        // Marking dirty writes to UserDefaults. Keep that work out of the
        // interaction frame and persist it together with the coalesced state.
        pendingActiveWorkoutID = workout.id
        scheduleLocalSave()
        scheduleLiveActivityRefresh()
    }

    private func scheduleActiveJournal() {
        deferredActiveJournalTask?.cancel()
        deferredActiveJournalTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let workout = self.activeWorkout else { return }
            self.deferredActiveJournalTask = nil
            self.persistActiveJournal(workout)
        }
    }

    /// Serializing the full training state for every keystroke or every drag
    /// frame causes visible hitching on long workouts. Keep the in-memory UI
    /// synchronous and write one consolidated snapshot once interaction has
    /// been quiet briefly.
    private func scheduleLocalSave() {
        deferredActiveSaveTask?.cancel()
        deferredActiveSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self else { return }
            self.deferredActiveSaveTask = nil
            self.persistPendingActiveChanges()
            self.save()
            self.scheduleDeferredSync()
        }
    }

    private func persistPendingActiveChanges() {
        guard let workoutID = pendingActiveWorkoutID else { return }
        pendingActiveWorkoutID = nil
        markDirty(workoutID)
    }

    private func changed(_ id: UUID) {
        markDirty(id)
        // The local snapshot and its dirty marker must exist before any
        // network work starts. Sync is deliberately scheduled separately.
        save()
        scheduleDeferredSync()
    }
    private var scope: String { accountID.map { "account_\($0)" } ?? "guest" }
    private func storageKey(_ scope: String) -> String { "training_state_\(scope)_v1" }
    private func activeJournalKey(_ scope: String) -> String { "training_active_journal_\(scope)_v1" }
    private func completedCheckpointKey(_ scope: String) -> String { "training_completed_checkpoint_\(scope)_v1" }
    private func completionReceiptsKey(_ scope: String) -> String { "training_completion_receipts_\(scope)_v1" }
    private func discardedWorkoutKey(_ scope: String) -> String { "training_discarded_workouts_\(scope)_v1" }
    private func dirtyKey(_ id: String) -> String { "training_dirty_\(id)_v1" }
    private func deletedKey(_ id: String) -> String { "training_deleted_\(id)_v1" }
    private func dirtyRoutineKey(_ id: String) -> String { "training_dirty_routines_\(id)_v1" }
    private func deletedRoutineKey(_ id: String) -> String { "training_deleted_routines_\(id)_v1" }
    private func dirtyExerciseKey(_ id: String) -> String { "training_dirty_exercises_\(id)_v1" }
    private func childRepairKey(_ id: String) -> String { "training_children_verified_\(id)_v3" }
    private func favoriteOverrideKey(_ id: String) -> String { "training_favorite_overrides_\(id)_v1" }
    private func lastSuccessfulSyncKey(_ id: String) -> String { "training_last_successful_sync_\(id)_v1" }

    private func state(scope: String) -> State {
        guard let data = UserDefaults.standard.data(forKey: storageKey(scope)), let value = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return value
    }

    private func orderedRoutines(_ values: [WorkoutRoutine]) -> [WorkoutRoutine] {
        values.enumerated().sorted { left, right in
            let leftOrder = left.element.sortOrder ?? Int.max
            let rightOrder = right.element.sortOrder ?? Int.max
            return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
        }.map(\.element)
    }

    private func load(scope: String) {
        activeExerciseReorderNeedsSaving = false
        clearExerciseRemovalUndo()
        let value = state(scope: scope)
        progressGoals = value.progressGoals ?? [:]
        let storedByID = Dictionary(uniqueKeysWithValues: value.exercises.map { ($0.id, $0) })
        exercises = TrainingExercise.catalogDeduplicated(TrainingExercise.builtIns.map { builtIn in
            guard let stored = storedByID[builtIn.id] else { return builtIn }
            var merged = builtIn; merged.isFavorite = stored.isFavorite; merged.remoteID = stored.remoteID; return merged
        } + value.exercises
            .filter { $0.isCustom && !TrainingExercise.isRetiredImported($0) }
            .map { $0.normalizedImportedCatalogEntry() })
        let repairedCustomMuscles = repairMissingCustomExerciseMuscles(from: value.exercises)
        routines = orderedRoutines(value.routines)
        let repairedRoutineExerciseTypes = repairSavedRoutineExerciseTypes()
        let enrichedSuggestedRoutines = enrichSavedHyseRoutineNotes()
        let journal = activeJournal(scope: scope)
        let completedCheckpoint = completedWorkoutCheckpoint(scope: scope)
        let completionReceipts = workoutCompletionReceipts(scope: scope)
        let checkpointNeedsRecovery = completedCheckpoint.map { checkpoint in
            guard let stored = value.workouts.first(where: { $0.id == checkpoint.id }) else { return true }
            return stored.status != .completed || stored.updatedAt < checkpoint.updatedAt
        } ?? false
        let discarded = discardedWorkoutIDs(scope: scope)
        workouts = TrainingWorkoutRecovery.restoredWorkouts(from: value.workouts, journal: journal, completedCheckpoint: completedCheckpoint, completionReceipts: completionReceipts)
            .filter { !discarded.contains($0.id) }
        let receiptRecoveredIDs = workouts.compactMap { workout -> UUID? in
            guard completionReceipts[workout.id] != nil,
                  value.workouts.first(where: { $0.id == workout.id })?.status != .completed else { return nil }
            return workout.id
        }
        for id in receiptRecoveredIDs { markDirty(id) }
        let repairedWorkoutMuscles = repairSavedWorkoutMuscleAssignments()
        rebuildCompletedWorkouts(); bodyMeasurements = (value.bodyMeasurements ?? []).sorted { $0.date > $1.date }; restTimerEnd = value.restTimerEnd; restTimerID = value.restTimerID
        if restTimerEnd != nil && restTimerID == nil { restTimerID = UUID() }
        if repairedCustomMuscles || repairedRoutineExerciseTypes || enrichedSuggestedRoutines || repairedWorkoutMuscles || journal != nil || checkpointNeedsRecovery || !receiptRecoveredIDs.isEmpty {
            save()
            if checkpointNeedsRecovery { UserDefaults.standard.synchronize() }
        }
    }

    @discardableResult
    private func repairMissingCustomExerciseMuscles(from source: [TrainingExercise]) -> Bool {
        let sourceByID = Dictionary(uniqueKeysWithValues: source.filter(\.isCustom).map { ($0.id, $0) })
        var changed = false
        for index in exercises.indices where exercises[index].isCustom {
            guard let previous = sourceByID[exercises[index].id],
                  previous.primaryMuscles != exercises[index].primaryMuscles ||
                    previous.secondaryMuscles != exercises[index].secondaryMuscles else { continue }
            exercises[index].updatedAt = Date()
            markCustomExerciseDirty(exercises[index].id)
            changed = true
        }
        return changed
    }

    /// Refreshes embedded exercise metadata in saved routines after a catalog
    /// correction, including the input shape of their target sets.
    @discardableResult
    private func repairSavedRoutineExerciseTypes() -> Bool {
        var changed = false
        for routineIndex in routines.indices {
            var routineChanged = false
            for exerciseIndex in routines[routineIndex].exercises.indices {
                let current = routines[routineIndex].exercises[exerciseIndex].exercise
                if let catalog = exercises.first(where: { $0.id == current.id }), current.type != catalog.type {
                    routines[routineIndex].exercises[exerciseIndex].exercise.type = catalog.type
                    changed = true
                    routineChanged = true
                }
                if let repaired = TrainingExercise.repairedMuscleAssignment(
                       exerciseID: current.id,
                       englishName: current.englishName,
                       germanName: current.germanName,
                       type: current.type,
                       equipment: current.equipment,
                       primary: current.primaryMuscles,
                       secondary: current.secondaryMuscles
                   ) {
                    routines[routineIndex].exercises[exerciseIndex].exercise.primaryMuscles = repaired.primary
                    routines[routineIndex].exercises[exerciseIndex].exercise.secondaryMuscles = repaired.secondary
                    changed = true
                    routineChanged = true
                }
                let type = routines[routineIndex].exercises[exerciseIndex].exercise.type
                let normalizedSets = routines[routineIndex].exercises[exerciseIndex].sets.map { $0.normalized(for: type) }
                if normalizedSets != routines[routineIndex].exercises[exerciseIndex].sets {
                    routines[routineIndex].exercises[exerciseIndex].sets = normalizedSets
                    changed = true
                    routineChanged = true
                }
            }
            if routineChanged {
                routines[routineIndex].updatedAt = Date()
                markRoutineDirty(routines[routineIndex].id)
            }
        }
        return changed
    }

    @discardableResult
    private func repairSavedWorkoutMuscleAssignments() -> Bool {
        var changed = false
        for workoutIndex in workouts.indices {
            var workoutChanged = false
            for exerciseIndex in workouts[workoutIndex].exercises.indices {
                let exercise = workouts[workoutIndex].exercises[exerciseIndex]
                guard let repaired = TrainingExercise.repairedMuscleAssignment(
                          exerciseID: exercise.exerciseID,
                          englishName: exercise.exerciseNameSnapshot,
                          germanName: exercise.exerciseGermanNameSnapshot,
                          type: exercise.exerciseTypeSnapshot,
                          equipment: exercise.equipmentSnapshot,
                          primary: exercise.primaryMusclesSnapshot,
                          secondary: exercise.secondaryMusclesSnapshot
                      ) else { continue }
                workouts[workoutIndex].exercises[exerciseIndex].primaryMusclesSnapshot = repaired.primary
                workouts[workoutIndex].exercises[exerciseIndex].secondaryMusclesSnapshot = repaired.secondary
                workoutChanged = true
            }
            if workoutChanged {
                workouts[workoutIndex].updatedAt = Date()
                markDirty(workouts[workoutIndex].id)
                changed = true
            }
        }
        return changed
    }

    /// Adds newly curated coaching notes to already saved Hyse templates while
    /// preserving every note the user has written or edited themselves.
    @discardableResult
    private func enrichSavedHyseRoutineNotes() -> Bool {
        let templates = SuggestedRoutineProgram.library(isGerman: true).flatMap(\.routines)
            + SuggestedRoutineProgram.library(isGerman: false).flatMap(\.routines)
        var changed = false
        for routineIndex in routines.indices {
            let folder = routines[routineIndex].folder
            guard folder == "Hyse Vorschläge" || folder == "Hyse Suggestions",
                  let template = templates.first(where: { $0.folder == folder && $0.name == routines[routineIndex].name }) else { continue }
            var routineChanged = false
            for exerciseIndex in routines[routineIndex].exercises.indices {
                guard routines[routineIndex].exercises[exerciseIndex].notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let exerciseID = routines[routineIndex].exercises[exerciseIndex].exercise.id
                guard let note = template.exercises.first(where: { $0.exercise.id == exerciseID })?.notes,
                      !note.isEmpty else { continue }
                routines[routineIndex].exercises[exerciseIndex].notes = note
                routineChanged = true
            }
            if routineChanged {
                routines[routineIndex].updatedAt = Date()
                markRoutineDirty(routines[routineIndex].id)
                changed = true
            }
        }
        return changed
    }

    private func save() {
        let value = State(exercises: exercises, routines: routines, workouts: workouts, bodyMeasurements: bodyMeasurements, progressGoals: progressGoals, restTimerEnd: restTimerEnd, restTimerID: restTimerID)
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(scope))
        // The full state now contains the active workout, so its compact
        // crash-safety journal can be discarded.
        UserDefaults.standard.removeObject(forKey: activeJournalKey(scope))
    }

    /// Full history serialization is intentionally debounced while the user
    /// trains. The active-workout journal is written immediately for actions
    /// and shortly after typing stops for text fields. It is merged on launch
    /// if iOS interrupts the full save.
    private func persistActiveJournal(_ workout: WorkoutLog) {
        guard let data = try? JSONEncoder().encode(workout) else { return }
        UserDefaults.standard.set(data, forKey: activeJournalKey(scope))
    }

    private func activeJournal(scope: String) -> WorkoutLog? {
        guard let data = UserDefaults.standard.data(forKey: activeJournalKey(scope)) else { return nil }
        return try? JSONDecoder().decode(WorkoutLog.self, from: data)
    }

    private func workoutCompletionReceipts(scope: String) -> [UUID: Date] {
        let values = UserDefaults.standard.dictionary(forKey: completionReceiptsKey(scope)) as? [String: TimeInterval] ?? [:]
        return values.reduce(into: [UUID: Date]()) { result, entry in
            if let id = UUID(uuidString: entry.key) {
                result[id] = Date(timeIntervalSince1970: entry.value)
            }
        }
    }

    private func persistWorkoutCompletionReceipt(_ workout: WorkoutLog) {
        guard let completedAt = workout.completedAt else { return }
        var values = UserDefaults.standard.dictionary(forKey: completionReceiptsKey(scope)) as? [String: TimeInterval] ?? [:]
        values[workout.id.uuidString] = completedAt.timeIntervalSince1970
        UserDefaults.standard.set(values, forKey: completionReceiptsKey(scope))
        UserDefaults.standard.synchronize()
    }

    private func persistCompletedWorkoutCheckpoint(_ workout: WorkoutLog) {
        guard workout.status == .completed, let data = try? JSONEncoder().encode(workout) else { return }
        UserDefaults.standard.set(data, forKey: completedCheckpointKey(scope))
        // Finishing must be durable before the confirmation sheet disappears.
        UserDefaults.standard.synchronize()
    }

    private func completedWorkoutCheckpoint(scope: String) -> WorkoutLog? {
        guard let data = UserDefaults.standard.data(forKey: completedCheckpointKey(scope)) else { return nil }
        return try? JSONDecoder().decode(WorkoutLog.self, from: data)
    }

    private func discardedWorkoutIDs(scope: String) -> Set<UUID> { ids(key: discardedWorkoutKey(scope)) }

    private func recordWorkoutDeletion(_ id: UUID) {
        var discarded = discardedWorkoutIDs(scope: scope)
        discarded.insert(id)
        store(discarded, key: discardedWorkoutKey(scope))
        var completionReceipts = UserDefaults.standard.dictionary(forKey: completionReceiptsKey(scope)) as? [String: TimeInterval] ?? [:]
        completionReceipts.removeValue(forKey: id.uuidString)
        UserDefaults.standard.set(completionReceipts, forKey: completionReceiptsKey(scope))
        if let accountID {
            var deleted = deletedIDs(accountID)
            deleted.insert(id)
            store(deleted, key: deletedKey(accountID))
        }
        // The marker must reach disk before the UI leaves the workout screen.
        // It protects against an older full snapshot or active journal on relaunch.
        UserDefaults.standard.synchronize()
    }

    private func rebuildCompletedWorkouts() {
        completedWorkouts = workouts
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
        publishTrainingWeekWidget()
        previousPerformanceCache = nil
        previousPerformanceCacheWorkoutID = nil
        previousPerformanceCacheWorkoutName = nil
        previousPerformanceCachePlacementIDs = []
        previousRecordBestCache.removeAll()
    }

    private func publishTrainingWeekWidget() {
        let calendar = Calendar.autoupdatingCurrent
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()),
              let defaults = UserDefaults(suiteName: HyseConfiguration.appGroup) else { return }
        let completedThisWeek = completedWorkouts.filter { week.contains($0.completedAt ?? $0.startedAt) }
        var dailyCounts = Array(repeating: 0, count: 7)
        for workout in completedThisWeek {
            let day = calendar.startOfDay(for: workout.completedAt ?? workout.startedAt)
            let index = calendar.dateComponents([.day], from: week.start, to: day).day ?? -1
            if dailyCounts.indices.contains(index) { dailyCounts[index] += 1 }
        }
        defaults.set(week.start.timeIntervalSince1970, forKey: "widgetTrainingWeekStart")
        defaults.set(completedThisWeek.count, forKey: "widgetWorkoutsThisWeek")
        defaults.set(Int((completedThisWeek.reduce(0) { $0 + $1.duration } / 60).rounded()),
                     forKey: "widgetWorkoutMinutesThisWeek")
        defaults.set(dailyCounts, forKey: "widgetWorkoutDailyCounts")
        defaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "TrainingWeekWidget")
    }

    private func scheduleLiveActivityRefresh() {
        deferredLiveActivityTask?.cancel()
        deferredLiveActivityTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.deferredLiveActivityTask = nil
            self.refreshLiveActivity()
        }
    }

    private func scheduleDeferredSync() {
        guard accountID != nil else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = Task { [weak self] in
            // Keep edits local while the user is working. A quiet period batches
            // routine and completed-workout changes into one server round-trip.
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled, let self else { return }
            self.deferredSyncTask = nil
            self.sync()
        }
    }

    private func markDirty(_ id: UUID) {
        guard let accountID else { return }
        var ids = dirtyIDs(accountID)
        if ids.insert(id).inserted { store(ids, key: dirtyKey(accountID)) }
    }
    private func markRoutineDirty(_ id: UUID) {
        guard let accountID else { return }
        var ids = self.ids(key: dirtyRoutineKey(accountID))
        if ids.insert(id).inserted { store(ids, key: dirtyRoutineKey(accountID)) }
    }
    private func markCustomExerciseDirty(_ id: UUID) {
        guard let accountID else { return }
        var ids = self.ids(key: dirtyExerciseKey(accountID))
        if ids.insert(id).inserted { store(ids, key: dirtyExerciseKey(accountID)) }
    }
    private func markAllDirty() {
        guard let accountID else { return }
        store(Set(workouts.map(\.id)), key: dirtyKey(accountID))
        store(Set(routines.map(\.id)), key: dirtyRoutineKey(accountID))
        store(Set(exercises.lazy.filter(\.isCustom).map(\.id)), key: dirtyExerciseKey(accountID))
    }
    private func dirtyIDs(_ id: String) -> Set<UUID> { ids(key: dirtyKey(id)) }
    private func deletedIDs(_ id: String) -> Set<UUID> { ids(key: deletedKey(id)) }
    private func favoriteOverrides(_ id: String) -> [UUID: Bool] {
        let stored = UserDefaults.standard.dictionary(forKey: favoriteOverrideKey(id)) as? [String: Bool] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }
    private func ids(key: String) -> Set<UUID> { Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))) }
    private func store(_ ids: Set<UUID>, key: String) { UserDefaults.standard.set(ids.map(\.uuidString), forKey: key) }

    private var trainingWeightUnit: TrainingWeightUnit {
        TrainingWeightUnit(rawValue: UserDefaults.standard.string(forKey: "trainingWeightUnit_v1") ?? "") ?? .kilograms
    }

    private func refreshLiveActivity() {
        guard hasResolvedPersistenceScope else { return }
        TrainingLiveActivityController.shared.reconcile(with: activeWorkout, restTimerEnd: restTimerEnd, finished: restTimerFinished, weightUnit: trainingWeightUnit)
    }

    private func retryRoutineShareRevocations() {
        guard routineShareRevocationTask == nil, let accountID,
              let authManager, authManager.accountID == accountID, !authManager.token.isEmpty else { return }
        let key = "routine_share_revocations_\(accountID)_v1"
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !ids.isEmpty else { return }
        let token = authManager.token
        routineShareRevocationTask = Task {
            for id in ids where !Task.isCancelled {
                guard (try? await RoutineShareService.shared.revoke(id: id, token: token)) != nil,
                      self.accountID == accountID else { continue }
                var pending = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
                pending.remove(id)
                UserDefaults.standard.set(Array(pending), forKey: key)
            }
            routineShareRevocationTask = nil
        }
    }

    func sync(force: Bool = false) {
        retryRoutineShareRevocations()
        deferredSyncTask?.cancel()
        deferredSyncTask = nil
        guard let accountID, let authManager, authManager.isLoggedIn, authManager.accountID == accountID, !authManager.token.isEmpty else {
            syncTask?.cancel()
            syncState = .local
            return
        }
        let allDirtyWorkoutIDs = dirtyIDs(accountID)
        let completedWorkoutIDs = Set(workouts.lazy.filter { $0.status == .completed }.map(\.id))
        let syncableWorkoutIDs = allDirtyWorkoutIDs.intersection(completedWorkoutIDs)
        let hasPendingChanges = !syncableWorkoutIDs.isEmpty
            || !ids(key: dirtyRoutineKey(accountID)).isEmpty
            || !deletedIDs(accountID).isEmpty
            || !ids(key: deletedRoutineKey(accountID)).isEmpty
            || !favoriteOverrides(accountID).isEmpty
            || !ids(key: dirtyExerciseKey(accountID)).isEmpty
        if !force, !hasPendingChanges, let lastAttemptedSyncAt,
           Date().timeIntervalSince(lastAttemptedSyncAt) < 300 { return }
        if !force, !hasPendingChanges, case .synced = syncState,
           let lastSuccessfulSyncAt, Date().timeIntervalSince(lastSuccessfulSyncAt) < 3_600 { return }
        if syncIsRunning {
            syncRequestedWhileRunning = true
            return
        }
        syncGeneration += 1
        let generation = syncGeneration
        syncTask?.cancel()
        syncState = .syncing
        lastAttemptedSyncAt = Date()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self,
                  self.syncGeneration == generation,
                  self.accountID == accountID,
                  self.authManager?.accountID == accountID,
                  let token = self.authManager?.token,
                  !token.isEmpty else { return }
            self.syncIsRunning = true
            defer {
                self.syncIsRunning = false
                if self.syncRequestedWhileRunning {
                    self.syncRequestedWhileRunning = false
                    self.sync()
                }
            }
            let local = self.workouts
            let routines = self.routines
            let custom = self.exercises
                .filter { $0.isCustom && !TrainingExercise.isRetiredImported($0) }
                .map { $0.normalizedImportedCatalogEntry() }
            let favoriteOverrides = self.favoriteOverrides(accountID)
            let uploadedWorkoutSnapshots = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
            let uploadedRoutineSnapshots = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
            let uploadedExerciseSnapshots = Dictionary(uniqueKeysWithValues: custom.map { ($0.id, $0) })
            let uploadedFavoriteOverrides = favoriteOverrides
            let dirtyExerciseIDs = self.ids(key: self.dirtyExerciseKey(accountID))
            let needsChildRepair = !UserDefaults.standard.bool(forKey: self.childRepairKey(accountID))
            let repairableWorkoutIDs = Set(local.lazy.filter { $0.status == .completed }.map(\.id))
            let dirtyWorkouts = needsChildRepair ? repairableWorkoutIDs : syncableWorkoutIDs
            let dirtyRoutines = needsChildRepair ? Set(routines.map(\.id)) : self.ids(key: self.dirtyRoutineKey(accountID))
            let deletedWorkouts = self.deletedIDs(accountID)
            let deletedRoutines = self.ids(key: self.deletedRoutineKey(accountID))
            let result = await TrainingSyncService.shared.sync(
                workouts: local,
                routines: routines,
                customExercises: custom,
                favoriteOverrides: favoriteOverrides,
                dirtyWorkoutIDs: dirtyWorkouts,
                dirtyRoutineIDs: dirtyRoutines,
                deletedWorkoutIDs: deletedWorkouts,
                deletedRoutineIDs: deletedRoutines,
                userID: accountID,
                token: token
            )
            guard !Task.isCancelled,
                  self.syncGeneration == generation,
                  self.accountID == accountID,
                  self.authManager?.accountID == accountID else { return }
            guard result.didFetch else {
                self.workouts = self.workouts.map { value in var copy = value; copy.syncError = true; return copy }
                self.rebuildCompletedWorkouts()
                self.save(); self.syncState = .offline; return
            }
            guard result.didPush else {
                self.workouts = self.workouts.map { value in var copy = value; copy.syncError = true; return copy }
                self.rebuildCompletedWorkouts()
                self.save(); self.syncState = .offline; return
            }
            let currentDeletedWorkouts = self.deletedIDs(accountID)
            let currentDeletedRoutines = self.ids(key: self.deletedRoutineKey(accountID))
            let localByID = Dictionary(uniqueKeysWithValues: self.workouts.map { ($0.id, $0) })
            let completionReceipts = self.workoutCompletionReceipts(scope: self.scope)
            let discardedWorkouts = self.discardedWorkoutIDs(scope: self.scope)
            let staleRemoteIDs = Set(result.workouts.compactMap { workout -> UUID? in
                completionReceipts[workout.id] != nil && workout.status != .completed
                    && !currentDeletedWorkouts.contains(workout.id)
                    && !discardedWorkouts.contains(workout.id) ? workout.id : nil
            })
            var merged = Dictionary(uniqueKeysWithValues: result.workouts.map { workout in
                let protected = TrainingWorkoutRecovery.applyingCompletionReceipt(
                    to: workout, completedAt: completionReceipts[workout.id]
                )
                return (protected.id, protected)
            })
            for (id, value) in localByID where TrainingWorkoutRecovery.shouldKeepCurrent(
                value, over: merged[id], incomingWasActive: staleRemoteIDs.contains(id)
            ) {
                merged[id] = value
            }
            merged = merged.filter { !currentDeletedWorkouts.contains($0.key) && !discardedWorkouts.contains($0.key) }
            self.workouts = Array(merged.values).map { value in var copy = value; copy.syncError = false; return copy }
            for id in staleRemoteIDs { self.markDirty(id) }
            let repairedWorkoutMuscles = self.repairSavedWorkoutMuscleAssignments()
            self.rebuildCompletedWorkouts()
            var repairedRoutineMetadata = false
            if !result.routines.isEmpty {
                let localRoutines = Dictionary(uniqueKeysWithValues: self.routines.map { ($0.id, $0) })
                var mergedRoutines = Dictionary(uniqueKeysWithValues: result.routines.map { ($0.id, $0) })
                for (id, value) in localRoutines where value.updatedAt > (mergedRoutines[id]?.updatedAt ?? .distantPast) {
                    mergedRoutines[id] = value
                }
                // The server does not store note edit times. Keep the local
                // marker while the synced note text is unchanged.
                for (id, local) in localRoutines {
                    guard var remote = mergedRoutines[id] else { continue }
                    let localByID = Dictionary(local.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    var carried = false
                    for index in remote.exercises.indices where remote.exercises[index].notesUpdatedAt == nil {
                        guard let match = localByID[remote.exercises[index].id],
                              let edited = match.notesUpdatedAt,
                              match.notes == remote.exercises[index].notes else { continue }
                        remote.exercises[index].notesUpdatedAt = edited
                        carried = true
                    }
                    if carried { mergedRoutines[id] = remote }
                }
                self.routines = self.orderedRoutines(Array(mergedRoutines.filter { !currentDeletedRoutines.contains($0.key) }.values))
                repairedRoutineMetadata = self.repairSavedRoutineExerciseTypes()
            }
            self.serverStreak = result.serverStreak
            let localCustomByID = Dictionary(uniqueKeysWithValues: self.exercises
                .filter { $0.isCustom && !TrainingExercise.isRetiredImported($0) }
                .map { $0.normalizedImportedCatalogEntry() }
                .map { ($0.id, $0) })
            var customByID = Dictionary(uniqueKeysWithValues: result.customExercises
                .filter { !TrainingExercise.isRetiredImported($0) }
                .map { $0.normalizedImportedCatalogEntry() }
                .map { ($0.id, $0) })
            for (id, value) in localCustomByID where value.updatedAt > (customByID[id]?.updatedAt ?? .distantPast) {
                customByID[id] = value
            }
            let currentFavoriteOverrides = self.favoriteOverrides(accountID)
            var favoriteExerciseIDs = result.favoriteExerciseIDs
            for (id, isFavorite) in currentFavoriteOverrides {
                if isFavorite { favoriteExerciseIDs.insert(id) } else { favoriteExerciseIDs.remove(id) }
            }
            self.exercises = TrainingExercise.catalogDeduplicated(TrainingExercise.builtIns.map { base in var value = base; value.isFavorite = favoriteExerciseIDs.contains(base.id); return value } + customByID.values.map { value in var copy = value; copy.isFavorite = favoriteExerciseIDs.contains(value.id); return copy })
            let repairedCustomMuscles = self.repairMissingCustomExerciseMuscles(from: result.customExercises)
            // Only clear a marker when the exact snapshot sent to the server
            // is still the current local value. Edits made while the request
            // was in flight remain pending for the next retry/startup.
            let currentWorkouts = Dictionary(uniqueKeysWithValues: self.workouts.map { ($0.id, $0) })
            let confirmedWorkoutIDs = dirtyWorkouts.filter { id in
                currentWorkouts[id]?.updatedAt == uploadedWorkoutSnapshots[id]?.updatedAt
            }
            let currentRoutines = Dictionary(uniqueKeysWithValues: self.routines.map { ($0.id, $0) })
            let confirmedRoutineIDs = dirtyRoutines.filter { id in
                currentRoutines[id]?.updatedAt == uploadedRoutineSnapshots[id]?.updatedAt
            }
            let currentCustom = Dictionary(uniqueKeysWithValues: self.exercises
                .filter { $0.isCustom && !TrainingExercise.isRetiredImported($0) }
                .map { $0.normalizedImportedCatalogEntry() }
                .map { ($0.id, $0) })
            let confirmedExerciseIDs = dirtyExerciseIDs.filter { id in
                currentCustom[id]?.updatedAt == uploadedExerciseSnapshots[id]?.updatedAt
            }
            let remainingDirtyWorkouts = self.dirtyIDs(accountID).subtracting(confirmedWorkoutIDs)
            let remainingDirtyRoutines = self.ids(key: self.dirtyRoutineKey(accountID)).subtracting(confirmedRoutineIDs)
            let remainingDirtyExercises = dirtyExerciseIDs.subtracting(confirmedExerciseIDs)
            let remainingDeletedWorkouts = currentDeletedWorkouts.subtracting(deletedWorkouts)
            let remainingDeletedRoutines = currentDeletedRoutines.subtracting(deletedRoutines)
            self.store(remainingDirtyWorkouts, key: self.dirtyKey(accountID))
            self.store(remainingDirtyRoutines, key: self.dirtyRoutineKey(accountID))
            self.store(remainingDirtyExercises, key: self.dirtyExerciseKey(accountID))
            self.store(remainingDeletedWorkouts, key: self.deletedKey(accountID))
            self.store(remainingDeletedRoutines, key: self.deletedRoutineKey(accountID))
            UserDefaults.standard.set(true, forKey: self.childRepairKey(accountID))

            var remainingFavoriteOverrides = currentFavoriteOverrides
            for (id, value) in uploadedFavoriteOverrides where remainingFavoriteOverrides[id] == value {
                remainingFavoriteOverrides.removeValue(forKey: id)
            }
            if remainingFavoriteOverrides.isEmpty {
                UserDefaults.standard.removeObject(forKey: self.favoriteOverrideKey(accountID))
            } else {
                UserDefaults.standard.set(
                    Dictionary(uniqueKeysWithValues: remainingFavoriteOverrides.map { ($0.key.uuidString.lowercased(), $0.value) }),
                    forKey: self.favoriteOverrideKey(accountID)
                )
            }
            self.save()
            if repairedWorkoutMuscles || repairedRoutineMetadata || repairedCustomMuscles || !staleRemoteIDs.isEmpty { self.scheduleDeferredSync() }
            let now = Date()
            self.lastSuccessfulSyncAt = now
            UserDefaults.standard.set(now, forKey: self.lastSuccessfulSyncKey(accountID))
            self.syncState = .synced(now)
        }
    }

    func flushPendingSync() async {
        flushPendingChanges()
        sync(force: true)
        for _ in 0..<3 {
            let generation = syncGeneration
            await syncTask?.value
            if syncGeneration == generation { break }
        }
    }

    private static func weeklyStreak(weeks: Set<Date>, calendar: Calendar) -> Int {
        guard !weeks.isEmpty,
              var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        // A still-open week must not erase the series before the user has had
        // a chance to train. The visual state separately indicates whether
        // this calendar week has already been completed.
        if !weeks.contains(cursor) {
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        var count = 0
        while weeks.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    private static func longestWeeklyStreak(weeks: Set<Date>, calendar: Calendar) -> Int {
        let ascending = weeks.sorted(); guard var previous = ascending.first else { return 0 }
        var best = 1, current = 1
        for week in ascending.dropFirst() {
            let expected = calendar.date(byAdding: .weekOfYear, value: 1, to: previous)
            if expected == week { current += 1 } else { current = 1 }
            best = max(best, current)
            previous = week
        }
        return best
    }
}
