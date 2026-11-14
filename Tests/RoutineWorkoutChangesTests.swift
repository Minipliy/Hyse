import Foundation

@main
struct RoutineWorkoutChangesTests {
    static func main() {
        let press = exercise("Press")
        let row = exercise("Row")
        let routine = WorkoutRoutine(name: "Upper", exercises: [
            RoutineExercise(exercise: press, sets: [TrainingSetLog(weightKilograms: 40, reps: 8), TrainingSetLog(weightKilograms: 40, reps: 8)]),
            RoutineExercise(exercise: row, sets: [TrainingSetLog(weightKilograms: 30, reps: 10)])
        ])
        var workout = WorkoutLog(routineID: routine.id, name: routine.name, exercises: routine.exercises.map { source in
            WorkoutExerciseLog(
                exerciseID: source.exercise.id,
                exerciseNameSnapshot: source.exercise.englishName,
                exerciseGermanNameSnapshot: source.exercise.germanName,
                exerciseTypeSnapshot: source.exercise.type,
                equipmentSnapshot: source.exercise.equipment,
                primaryMusclesSnapshot: [],
                secondaryMusclesSnapshot: [],
                sets: source.sets.map { var set = $0; set.id = UUID(); return set }
            )
        })

        expect(!RoutineWorkoutChanges(routine: routine, workout: workout).hasChanges, "new workout set IDs do not count as changes")
        workout.exercises[0].sets[0].completed = true
        expect(!RoutineWorkoutChanges(routine: routine, workout: workout).hasChanges, "set completion does not change routine structure")

        workout.exercises[0].sets.removeLast()
        workout.exercises.removeLast()
        let removed = RoutineWorkoutChanges(routine: routine, workout: workout)
        expect(removed.removedExercises == 1 && removed.removedSets == 1, "removed exercise and set are counted separately")
        expect(removed.changedSets == 0, "set removal is not misreported as a changed value")

        workout.exercises = Array(workout.exercises.prefix(1))
        workout.exercises[0].sets.append(TrainingSetLog())
        workout.exercises.append(WorkoutExerciseLog(
            exerciseID: UUID(), exerciseNameSnapshot: "New", exerciseGermanNameSnapshot: "Neu",
            exerciseTypeSnapshot: .weightReps, equipmentSnapshot: .barbell,
            primaryMusclesSnapshot: [], secondaryMusclesSnapshot: []
        ))
        let added = RoutineWorkoutChanges(routine: routine, workout: workout)
        expect(added.addedExercises == 1 && added.removedExercises == 1, "added and removed exercises are both reported")

        var valuesWorkout = WorkoutLog(routineID: routine.id, name: routine.name, exercises: routine.exercises.map { source in
            WorkoutExerciseLog(
                exerciseID: source.exercise.id, exerciseNameSnapshot: source.exercise.englishName,
                exerciseGermanNameSnapshot: source.exercise.germanName, exerciseTypeSnapshot: source.exercise.type,
                equipmentSnapshot: source.exercise.equipment, primaryMusclesSnapshot: [], secondaryMusclesSnapshot: [],
                sets: source.sets
            )
        })
        valuesWorkout.exercises[0].sets[0].reps = 9
        valuesWorkout.exercises[1].restSeconds = 60
        let changed = RoutineWorkoutChanges(routine: routine, workout: valuesWorkout)
        expect(changed.changedSets == 1 && changed.changedExerciseSettings == 1, "set values and exercise settings are reported")
        valuesWorkout.exercises.swapAt(0, 1)
        expect(RoutineWorkoutChanges(routine: routine, workout: valuesWorkout).exercisesReordered, "exercise order is reported")
        print("RoutineWorkoutChangesTests: all checks passed")
    }

    private static func exercise(_ name: String) -> TrainingExercise {
        TrainingExercise(
            id: UUID(), nameKey: "custom", englishName: name, germanName: name,
            descriptionKey: "", techniqueKey: "", type: .weightReps, equipment: .barbell,
            primaryMuscles: [], secondaryMuscles: [], isCustom: true, isFavorite: false, updatedAt: Date()
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAILED: \(message)") }
    }
}
