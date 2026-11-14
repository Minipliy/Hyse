import Foundation

@main
struct TrainingCoreTests {
    static func main() throws {
        let ids = TrainingExercise.builtIns.map(\.id)
        precondition(ids.count == Set(ids).count, "Built-in exercise IDs must be stable and unique")
        precondition(TrainingExercise.builtIns.allSatisfy { !$0.englishName.isEmpty && !$0.primaryMuscles.isEmpty })

        let pounds = TrainingWeightUnit.pounds.display(100)
        precondition(abs(pounds - 220.46226218) < 0.0001)
        precondition(abs(TrainingWeightUnit.pounds.kilograms(pounds) - 100) < 0.0001)
        precondition(abs(TrainingDistanceUnit.miles.display(1_609.344) - 1) < 0.0001)
        precondition(abs(TrainingDistanceUnit.miles.meters(1) - 1_609.344) < 0.0001)
        let run = TrainingSetLog(durationSeconds: 1_500, distanceMeters: 5_000, completed: true)
        precondition(abs((run.paceSecondsPerKilometer ?? 0) - 300) < 0.001, "A 25-minute 5K must have a 5:00/km pace")

        let timerStart = Date(timeIntervalSince1970: 1_000)
        var timedSet = TrainingSetLog(durationSeconds: 30)
        timedSet.startDurationTimer(at: timerStart)
        let restoredTimer = try JSONDecoder().decode(TrainingSetLog.self, from: JSONEncoder().encode(timedSet))
        precondition(restoredTimer.durationTimerRunning, "A running timer must survive app restart")
        precondition(abs(restoredTimer.currentDuration(at: timerStart.addingTimeInterval(90)) - 120) < 0.001, "Background time must count")
        timedSet.stopDurationTimer(at: timerStart.addingTimeInterval(90))
        precondition(!timedSet.durationTimerRunning && abs(timedSet.durationSeconds - 120) < 0.001, "Pausing must save elapsed time")

        var completed = TrainingSetLog(weightKilograms: 80, reps: 5, completed: true)
        let incomplete = TrainingSetLog(weightKilograms: 200, reps: 10, completed: false)
        precondition(completed.volume == 400)
        precondition(abs(completed.estimatedOneRepMaximum - 93.333_333) < 0.001)
        precondition(incomplete.volume == 0, "Incomplete sets must not contribute to volume")
        precondition(incomplete.estimatedOneRepMaximum == 0, "Incomplete sets must not contribute to estimated 1RM")
        completed.personalRecordFlags = ["weight", "estimated_1rm"]

        let exercise = TrainingExercise.builtIns[0]
        let log = WorkoutExerciseLog(
            exerciseID: exercise.id,
            exerciseNameSnapshot: exercise.englishName,
            exerciseGermanNameSnapshot: exercise.germanName,
            exerciseTypeSnapshot: exercise.type,
            equipmentSnapshot: exercise.equipment,
            primaryMusclesSnapshot: exercise.primaryMuscles,
            secondaryMusclesSnapshot: exercise.secondaryMuscles,
            sets: [completed, incomplete]
        )
        var repeatedPlacement = log
        repeatedPlacement.id = UUID()
        repeatedPlacement.sets = repeatedPlacement.sets.map { value in var copy = value; copy.id = UUID(); return copy }
        precondition(repeatedPlacement.exerciseID == log.exerciseID)
        precondition(repeatedPlacement.id != log.id, "The same exercise must have independent placement IDs")
        precondition(Set([log.id, repeatedPlacement.id]).count == 2)

        let workout = WorkoutLog(name: "Snapshot test", status: .completed, completedAt: Date(), exercises: [log, repeatedPlacement])
        precondition(workout.completedSets.count == 2)
        precondition(workout.totalVolume == 800)
        precondition(workout.totalReps == 10)

        let data = try JSONEncoder().encode(workout)
        let restored = try JSONDecoder().decode(WorkoutLog.self, from: data)
        precondition(restored == workout, "Workout snapshots must survive offline persistence")
        precondition(restored.exercises[0].exerciseNameSnapshot == exercise.englishName)

        let now = Date()
        let paused = WorkoutLog(name: "Paused", status: .paused, startedAt: now.addingTimeInterval(-100), pausedAt: now.addingTimeInterval(-20), accumulatedPausedSeconds: 10)
        precondition(abs(paused.duration - 70) < 0.1, "Paused time must not increase workout duration")
        let pausedData = try JSONEncoder().encode(paused)
        let restoredPaused = try JSONDecoder().decode(WorkoutLog.self, from: pausedData)
        precondition(restoredPaused == paused)

        let routine = WorkoutRoutine(name: "Independent routine", exercises: [RoutineExercise(exercise: exercise, sets: [completed])])
        var copiedSet = routine.exercises[0].sets[0]
        copiedSet.id = UUID(); copiedSet.completed = false; copiedSet.completedAt = nil
        precondition(copiedSet.id != routine.exercises[0].sets[0].id)
        precondition(routine.exercises[0].sets[0].completed, "Starting a workout must not mutate its routine")

        let point = ExerciseProgressPoint(id: UUID(), date: Date(), bestWeightKilograms: 80, bestRepetitions: 5, bestSetVolume: 400, estimatedOneRepMaximum: completed.estimatedOneRepMaximum, distanceMeters: 0, durationSeconds: 0, paceSecondsPerKilometer: nil)
        let progress = ExerciseProgressSummary(exerciseID: exercise.id, workoutCount: 1, completedSetCount: 1, bestWeightKilograms: 80, bestRepetitions: 5, bestSetVolume: 400, estimatedOneRepMaximum: point.estimatedOneRepMaximum, totalDistanceMeters: 0, totalDurationSeconds: 0, bestPaceSecondsPerKilometer: nil, points: [point])
        precondition(progress.points.count == 1 && progress.bestSetVolume == 400)

        print("Training core tests passed (including pause persistence).")
    }
}
