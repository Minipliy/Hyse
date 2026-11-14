import Foundation

@main
enum TrainingPersonalRecordsTests {
    static func main() {
        let baseline = TrainingSetLog(weightKilograms: 40, reps: 8, completed: true)
        let equal = TrainingSetLog(weightKilograms: 40, reps: 8, completed: true)
        let improved = TrainingSetLog(weightKilograms: 45, reps: 9, completed: true)
        let empty = TrainingSetLog(completed: true)

        expect(TrainingPersonalRecords.flags(for: baseline, comparedWith: []).isEmpty,
               "the first performance establishes a baseline")
        expect(TrainingPersonalRecords.flags(for: baseline, comparedWith: [empty]).isEmpty,
               "an empty set does not establish a baseline")
        expect(TrainingPersonalRecords.flags(for: equal, comparedWith: [baseline]).isEmpty,
               "matching the baseline is not a record")
        var unfinished = improved
        unfinished.completed = false
        expect(TrainingPersonalRecords.flags(for: unfinished, comparedWith: [baseline]).isEmpty,
               "an unfinished set is not a record")
        expect(Set(TrainingPersonalRecords.flags(for: improved, comparedWith: [baseline])) ==
               ["weight", "reps", "set_volume", "estimated_1rm"],
               "a later improvement is a record")

        var best = TrainingPersonalRecordBest()
        best.include(baseline)
        best.include(TrainingSetLog(weightKilograms: 35, reps: 15, completed: true))
        best.include(TrainingSetLog(weightKilograms: 100, reps: 20, completed: false))
        let fasterSet = TrainingSetLog(weightKilograms: 45, reps: 10, completed: true)
        expect(best.flags(for: fasterSet) == ["weight", "estimated_1rm"],
               "cached best values must preserve independent record categories and ignore unfinished sets")

        var legacy = baseline
        legacy.personalRecordFlags = ["first_performance"]
        expect(!legacy.hasPersonalRecord, "legacy first-performance flags are not counted")

        let exerciseID = UUID()
        let firstExercise = WorkoutExerciseLog(
            exerciseID: exerciseID,
            exerciseNameSnapshot: "Press",
            exerciseGermanNameSnapshot: "Drücken",
            exerciseTypeSnapshot: .weightReps,
            equipmentSnapshot: .barbell,
            primaryMusclesSnapshot: [],
            secondaryMusclesSnapshot: [],
            sets: [baseline]
        )
        let firstWorkout = WorkoutLog(name: "First", status: .completed, completedAt: Date(), exercises: [firstExercise])
        expect(MonthlyPersonalRecordHistory.recordsByMonth(workouts: [firstWorkout], calendar: .current).isEmpty,
               "a monthly report with only the first performance has no records")

        let exercise = WorkoutExerciseLog(
            exerciseID: exerciseID,
            exerciseNameSnapshot: "Press",
            exerciseGermanNameSnapshot: "Drücken",
            exerciseTypeSnapshot: .weightReps,
            equipmentSnapshot: .barbell,
            primaryMusclesSnapshot: [],
            secondaryMusclesSnapshot: [],
            sets: [baseline, improved]
        )
        let workout = WorkoutLog(name: "Test", status: .completed, completedAt: Date(), exercises: [exercise])
        let monthly = MonthlyPersonalRecordHistory.recordsByMonth(workouts: [workout], calendar: .current)
        let flags = monthly.values.flatMap { $0.map(\.flag) }
        expect(!flags.contains("first_performance"), "monthly reports exclude the baseline")
        expect(!flags.isEmpty, "monthly reports still include later improvements")
        print("Training personal record tests passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
