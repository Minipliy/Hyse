import Foundation

@main
enum TrainingSetStatisticsTests {
    static func main() {
        let completed = TrainingSetLog(weightKilograms: 20, reps: 10, completed: true)
        let open = TrainingSetLog(weightKilograms: 20, reps: 10, completed: false)
        let unilateral = TrainingExercise.builtIns.first { $0.nameKey == "uni_023_single_arm_dumbbell_row" }!
        let oneLeggedExtension = TrainingExercise.builtIns.first { $0.nameKey == "sl_178" }!
        let bilateral = TrainingExercise.builtIns.first { $0.nameKey == "barbell_bench_press" }!

        func log(_ exercise: TrainingExercise, sets: [TrainingSetLog]) -> WorkoutExerciseLog {
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

        let oneSided = log(unilateral, sets: [completed, completed, open])
        let twoSided = log(bilateral, sets: [completed, open])
        let workout = WorkoutLog(name: "Test", exercises: [oneSided, twoSided])

        expect(TrainingSetStatistics.isUnilateral(oneSided), "cataloged single-arm exercise is unilateral")
        expect(!TrainingSetStatistics.isUnilateral(twoSided), "bench press is bilateral")
        expect(TrainingSetStatistics.count(workout, halveUnilateral: false) == 3, "default counts every completed set")
        expect(TrainingSetStatistics.count(workout, halveUnilateral: true) == 2, "two unilateral sets count as one")
        expect(TrainingSetStatistics.count(log(unilateral, sets: [completed]), halveUnilateral: true) == 0.5,
               "a single unilateral set counts as half")
        let warmup = TrainingSetLog(type: .warmup, weightKilograms: 10, reps: 10, completed: true)
        let withWarmup = log(bilateral, sets: [warmup, warmup, completed, open])
        expect(TrainingSetStatistics.count(withWarmup, halveUnilateral: false) == 1,
               "completed warm-up sets do not count towards set statistics")
        expect(withWarmup.completedSetCount == 3, "warm-up sets still count as completed for workout progress")
        expect(TrainingSetStatistics.count(log(unilateral, sets: [warmup, completed]), halveUnilateral: true) == 0.5,
               "warm-up sets are excluded before halving unilateral sets")
        let oneOfEach = WorkoutLog(name: "Progress", exercises: [
            log(unilateral, sets: [completed]),
            log(bilateral, sets: [open])
        ])
        expect(abs(TrainingSetStatistics.progress(oneOfEach) - 1.0 / 3.0) < 0.000_001,
               "a unilateral completion fills half as much of the bar as a bilateral completion")
        var changedLaterality = oneOfEach
        changedLaterality.exercises[0].isUnilateralSnapshot = false
        expect(TrainingSetStatistics.progress(changedLaterality) == 0.5,
               "the bar recalculates when the unilateral switch is turned off")
        changedLaterality.exercises[1].sets[0].completed = true
        expect(TrainingSetStatistics.progress(changedLaterality) == 1,
               "completing every planned set fills the bar")
        expect(TrainingSetStatistics.progress(WorkoutLog(name: "Empty")) == 0,
               "an empty workout has no progress")
        let legExtension = log(oneLeggedExtension, sets: [completed])
        expect(TrainingSetStatistics.isUnilateral(legExtension), "one-legged leg extension is unilateral")
        expect(TrainingSetStatistics.count(legExtension, halveUnilateral: true) == 0.5,
               "one completed one-legged extension counts as half")
        expect(TrainingSetStatistics.count(legExtension, halveUnilateral: false) == 1,
               "disabled half-counting keeps the physical set count")

        var custom = oneSided
        custom.exerciseID = UUID()
        custom.exerciseNameSnapshot = "One-Arm Cable Row"
        expect(TrainingSetStatistics.isUnilateral(custom), "custom unilateral names are recognized")
        custom.exerciseNameSnapshot = "Straight-Arm Pulldown"
        custom.exerciseGermanNameSnapshot = "Latziehen mit beiden Armen"
        expect(!TrainingSetStatistics.isUnilateral(custom), "arm alone does not imply unilateral")
        custom.isUnilateralSnapshot = true
        expect(TrainingSetStatistics.count(custom, halveUnilateral: true) == 1, "explicit unilateral choice halves two completed sets")
        custom.isUnilateralSnapshot = false
        expect(!TrainingSetStatistics.isUnilateral(custom), "explicit bilateral choice overrides name inference")

        var overridden = oneSided
        overridden.isUnilateralSnapshot = false
        let persisted = try! JSONDecoder().decode(WorkoutExerciseLog.self, from: JSONEncoder().encode(overridden))
        expect(!TrainingSetStatistics.isUnilateral(persisted), "a manual bilateral override survives a workout snapshot round trip")
        let routine = WorkoutRoutine(name: "Test", exercises: [RoutineExercise(exercise: unilateral)])
        let changedWorkout = WorkoutLog(name: "Test", exercises: [overridden])
        expect(RoutineWorkoutChanges(routine: routine, workout: changedWorkout).changedExerciseSettings == 1,
               "a changed unilateral choice is offered when updating the routine")

        let start = Date(timeIntervalSince1970: 1_000)
        var timed = TrainingSetLog(durationSeconds: 45)
        timed.startDurationTimer(at: start)
        expect(timed.currentDuration(at: start) == 0, "first timer start ignores the previous suggested duration")
        timed.stopDurationTimer(at: start.addingTimeInterval(12))
        timed.startDurationTimer(at: start.addingTimeInterval(20))
        expect(timed.currentDuration(at: start.addingTimeInterval(20)) == 12, "timer restart resumes the current set")

        expect(TrainingSetStatistics.formatted(0.5, locale: Locale(identifier: "de_DE")) == "0,5", "German fractions use a comma")
        expect(TrainingSetStatistics.formatted(0.25, locale: Locale(identifier: "de_DE")) == "0,25", "weighted muscle fractions stay precise")
        print("Training set statistics tests passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
