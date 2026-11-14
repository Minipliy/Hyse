import Foundation

@MainActor
final class LanguageStore {
    var isGerman = false
    func text(_ key: String, _ arguments: CVarArg...) -> String { key }
}

@main
enum TrainingPreviousPerformanceTests {
    static func main() {
        let exercise = TrainingExercise.builtIns.first { $0.nameKey == "barbell_bench_press" }!
        let routine = UUID()
        let otherRoutine = UUID()

        func set(_ weight: Double) -> TrainingSetLog {
            TrainingSetLog(weightKilograms: weight, reps: 8, completed: true)
        }

        func placement(_ sets: [TrainingSetLog]) -> WorkoutExerciseLog {
            WorkoutExerciseLog(
                exerciseID: exercise.id,
                exerciseNameSnapshot: exercise.englishName,
                exerciseGermanNameSnapshot: exercise.germanName,
                exerciseTypeSnapshot: exercise.type,
                equipmentSnapshot: exercise.equipment,
                primaryMusclesSnapshot: exercise.primaryMuscles,
                secondaryMusclesSnapshot: exercise.secondaryMuscles,
                sets: sets
            )
        }

        func workout(_ name: String, routineID: UUID?, day: Double, sets: [TrainingSetLog]) -> WorkoutLog {
            WorkoutLog(
                routineID: routineID,
                name: name,
                status: .completed,
                completedAt: Date(timeIntervalSince1970: day * 86_400),
                exercises: sets.isEmpty ? [] : [placement(sets)]
            )
        }

        let older = workout("Push", routineID: routine, day: 1, sets: [set(60), set(65)])
        let latestSameRoutine = workout("Push", routineID: routine, day: 3, sets: [set(70)])
        let other = workout("Pull", routineID: otherRoutine, day: 4, sets: [set(90)])
        let active = WorkoutLog(routineID: routine, name: "Push", exercises: [placement([TrainingSetLog()])])
        let previous = TrainingPreviousPerformance.setsByPlacement(for: active, in: [other, older, latestSameRoutine])
        expect(previous[active.exercises[0].id]?[0]?.weightKilograms == 70, "use the last completed run of this routine")
        expect(previous[active.exercises[0].id]?.count == 1, "do not fill missing positions from older workouts")

        let latestWithoutExercise = workout("Push", routineID: routine, day: 5, sets: [])
        let absent = TrainingPreviousPerformance.setsByPlacement(for: active, in: [older, latestWithoutExercise])
        expect(absent[active.exercises[0].id] == nil, "an absent exercise stays blank instead of using an older run")

        let legacy = workout("Push", routineID: nil, day: 2, sets: [set(55)])
        let fallback = TrainingPreviousPerformance.setsByPlacement(for: active, in: [legacy, other])
        expect(fallback[active.exercises[0].id]?[0]?.weightKilograms == 55, "legacy name-only history remains usable")

        let duplicateName = workout("Push", routineID: otherRoutine, day: 6, sets: [set(100)])
        let isolated = TrainingPreviousPerformance.setsByPlacement(for: active, in: [duplicateName])
        expect(isolated[active.exercises[0].id] == nil, "a different routine with the same name is not this workout")

        let previousDuplicates = WorkoutLog(
            routineID: routine,
            name: "Push",
            status: .completed,
            completedAt: Date(timeIntervalSince1970: 7 * 86_400),
            exercises: [placement([set(80), set(85)]), placement([set(25), set(30)])]
        )
        let first = placement([TrainingSetLog(), TrainingSetLog()])
        let second = placement([TrainingSetLog(), TrainingSetLog()])
        let third = placement([TrainingSetLog()])
        let activeDuplicates = WorkoutLog(routineID: routine, name: "Push", exercises: [first, second, third])
        let separate = TrainingPreviousPerformance.setsByPlacement(for: activeDuplicates, in: [previousDuplicates])
        expect(separate[first.id]?.map { $0?.weightKilograms } == [80, 85], "first placement keeps its own sets")
        expect(separate[second.id]?.map { $0?.weightKilograms } == [25, 30], "second placement keeps its own sets")
        expect(separate[third.id] == nil, "an extra placement has no previous values")

        print("Previous workout performance tests passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
