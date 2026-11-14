import Foundation

@MainActor
final class LanguageStore {
    var isGerman = false

    func text(_ key: String, _ arguments: CVarArg...) -> String { key }
}

@main
struct EdgeCasePersistenceTests {
    static func main() throws {
        let categoryID = UUID()
        let entry = CalorieEntry(
            id: UUID(),
            name: "Test food",
            grams: 100,
            categoryId: categoryID,
            categoryName: "ui.snacks",
            portionName: "Serving",
            portionCount: 1,
            kcalPer100g: 250,
            carbsPer100g: 20,
            proteinPer100g: 10,
            fatPer100g: 8,
            date: Date(timeIntervalSince1970: 1_750_000_000)
        )
        expectClose(entry.kcal, 250, "100 g nutrition amount")

        var changedAmount = entry
        changedAmount.grams = 250
        changedAmount.portionCount = 2.5
        expectClose(changedAmount.kcal, 625, "edited nutrition amount")
        expectClose(changedAmount.carbs, 50, "edited carbohydrate amount")

        let entryData = try JSONEncoder().encode(changedAmount)
        let restoredEntry = try JSONDecoder().decode(CalorieEntry.self, from: entryData)
        expectClose(restoredEntry.grams, 250, "amount survives restart")
        expectClose(restoredEntry.portionCount ?? 0, 2.5, "portion count survives restart")
        expect(restoredEntry.categoryId == categoryID, "entry category survives restart")

        let exercises = Array(TrainingExercise.builtIns.prefix(2))
        let routine = WorkoutRoutine(
            name: "Future training",
            plannedWeekday: 5,
            exercises: exercises.map { RoutineExercise(exercise: $0) }
        )
        let routineData = try JSONEncoder().encode(routine)
        let restoredRoutine = try JSONDecoder().decode(WorkoutRoutine.self, from: routineData)
        expect(restoredRoutine.plannedWeekday == 5, "planned weekday survives restart")
        expect(restoredRoutine.exercises.map(\.exercise.id) == exercises.map(\.id), "exercise order survives restart")

        var unilateralRoutine = WorkoutRoutine(name: "Different sides", exercises: [
            RoutineExercise(exercise: exercises[0]), RoutineExercise(exercise: exercises[0])
        ])
        unilateralRoutine.exercises[0].exercise.isUnilateral = true
        unilateralRoutine.exercises[1].exercise.isUnilateral = false
        unilateralRoutine.exercises[0].sets[0].type = .warmup
        let restoredUnilateralRoutine = try JSONDecoder().decode(
            WorkoutRoutine.self, from: JSONEncoder().encode(unilateralRoutine)
        )
        expect(restoredUnilateralRoutine.exercises[0].exercise.isUnilateral == true
               && restoredUnilateralRoutine.exercises[1].exercise.isUnilateral == false,
               "unilateral choice stays separate for duplicate placements")
        expect(restoredUnilateralRoutine.exercises[0].sets[0].type == .warmup,
               "planned set type survives restart")
        expect(TrainingSetStatistics.isUnilateral(restoredUnilateralRoutine.exercises[0].exercise)
               && !TrainingSetStatistics.isUnilateral(restoredUnilateralRoutine.exercises[1].exercise),
               "unilateral setting overrides the exercise catalog per placement")

        let repeatedExercise = exercises[0]
        var repeatedRoutine = WorkoutRoutine(name: "Two rows", exercises: [
            RoutineExercise(exercise: repeatedExercise),
            RoutineExercise(exercise: exercises[1]),
            RoutineExercise(exercise: repeatedExercise)
        ])
        repeatedRoutine.updatedAt = Date(timeIntervalSince1970: 100)
        func loggedExercise(_ exercise: TrainingExercise, note: String) -> WorkoutExerciseLog {
            WorkoutExerciseLog(
                exerciseID: exercise.id,
                exerciseNameSnapshot: exercise.englishName,
                exerciseGermanNameSnapshot: exercise.germanName,
                exerciseTypeSnapshot: exercise.type,
                equipmentSnapshot: exercise.equipment,
                primaryMusclesSnapshot: exercise.primaryMuscles,
                secondaryMusclesSnapshot: exercise.secondaryMuscles,
                notes: note
            )
        }
        let completed = WorkoutLog(
            routineID: repeatedRoutine.id,
            name: repeatedRoutine.name,
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 200),
            completedAt: Date(timeIntervalSince1970: 300),
            exercises: [
                loggedExercise(repeatedExercise, note: "Hallo"),
                loggedExercise(exercises[1], note: "Middle"),
                loggedExercise(repeatedExercise, note: "Tschüss")
            ]
        )
        let savedCompleted = try JSONDecoder().decode(WorkoutLog.self, from: JSONEncoder().encode(completed))
        let firstNote = TrainingExerciseNoteHistory.notes(for: repeatedRoutine.exercises[0], occurrence: 0,
            in: repeatedRoutine, completedWorkouts: [savedCompleted], useRecentNotes: true)
        let secondNote = TrainingExerciseNoteHistory.notes(for: repeatedRoutine.exercises[2], occurrence: 1,
            in: repeatedRoutine, completedWorkouts: [savedCompleted], useRecentNotes: true)
        expect(firstNote == "Hallo" && secondNote == "Tschüss", "repeated exercise placements restore separate notes")

        var firstOnly = savedCompleted
        firstOnly.exercises.removeLast()
        let missingSecond = TrainingExerciseNoteHistory.notes(for: repeatedRoutine.exercises[2], occurrence: 1,
            in: repeatedRoutine, completedWorkouts: [firstOnly], useRecentNotes: true)
        expect(missingSecond.isEmpty, "a missing second placement does not copy the first note")

        // Unrelated routine changes (reorder, weekday, sync, repairs) bump
        // updatedAt but must keep the notes written in the last workout.
        repeatedRoutine.updatedAt = Date(timeIntervalSince1970: 400)
        expect(TrainingExerciseNoteHistory.notes(for: repeatedRoutine.exercises[0], occurrence: 0,
            in: repeatedRoutine, completedWorkouts: [savedCompleted], useRecentNotes: true) == "Hallo",
            "an unrelated routine change keeps the last workout note")

        repeatedRoutine.exercises[0].notes = "Edited first"
        repeatedRoutine.exercises[0].notesUpdatedAt = Date(timeIntervalSince1970: 400)
        repeatedRoutine.exercises[2].notes = ""
        repeatedRoutine.exercises[2].notesUpdatedAt = Date(timeIntervalSince1970: 400)
        expect(TrainingExerciseNoteHistory.notes(for: repeatedRoutine.exercises[0], occurrence: 0,
            in: repeatedRoutine, completedWorkouts: [savedCompleted], useRecentNotes: true) == "Edited first",
            "a later edit to the first routine placement wins")
        expect(TrainingExerciseNoteHistory.notes(for: repeatedRoutine.exercises[2], occurrence: 1,
            in: repeatedRoutine, completedWorkouts: [savedCompleted], useRecentNotes: true).isEmpty,
            "clearing one routine placement does not affect another")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_750_000_000))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        expect(calendar.startOfDay(for: tomorrow) > today, "future day remains distinct from today")

        print("Edge case persistence tests passed (amounts, future day and routine restart state).")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAILED: \(message)") }
    }

    private static func expectClose(_ actual: Double, _ expected: Double, _ message: String) {
        expect(abs(actual - expected) < 0.000_001, "\(message): expected \(expected), got \(actual)")
    }
}
