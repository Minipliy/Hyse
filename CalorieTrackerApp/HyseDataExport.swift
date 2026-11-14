import Foundation
import SwiftUI
import UIKit

nonisolated private struct HyseExportArchive: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let foodEntries: [CalorieEntry]
    let foods: [FoodItem]
    let recipes: [Recipe]
    let plannedRecipes: [PlannedRecipe]
    let mealCategories: [MealCategory]
    let workouts: [WorkoutLog]
    let routines: [WorkoutRoutine]
    let customExercises: [TrainingExercise]
    let exerciseProgressGoals: [String: ExerciseProgressGoal]
    let bodyMeasurements: [BodyMeasurement]
    let waterMillilitersByDay: [String: Double]
    let baseCalorieGoal: Double
    let dailyWaterGoalMilliliters: Double
    let calorieLimitEnforced: Bool
}

enum HyseDataExport {
    @MainActor
    static func create(calories: CalorieStore, training: TrainingStore, health: HealthKitManager,
                       foods: FoodStore, recipes: RecipeStore, categories: CategoryStore,
                       mealPlan: MealPlanStore, water: WaterStore, settings: UserSettingsStore) async throws -> [URL] {
        _ = water.refreshFromSharedStorage()
        let measurements = mergedMeasurements(training.bodyMeasurements, health.bodyWeights)
        let archive = HyseExportArchive(
            schemaVersion: 3,
            exportedAt: Date(),
            foodEntries: calories.entries,
            foods: foods.foods,
            recipes: recipes.recipes,
            plannedRecipes: mealPlan.items,
            mealCategories: categories.categories,
            workouts: training.workouts,
            routines: training.routines,
            customExercises: training.exercises.filter(\.isCustom),
            exerciseProgressGoals: Dictionary(uniqueKeysWithValues: training.progressGoals.map { ($0.key.uuidString, $0.value) }),
            bodyMeasurements: measurements,
            waterMillilitersByDay: water.allAmounts,
            baseCalorieGoal: settings.baseCalorieGoal,
            dailyWaterGoalMilliliters: settings.dailyWaterGoalMilliliters,
            calorieLimitEnforced: settings.enforceCalorieLimit
        )
        return try await Task.detached(priority: .userInitiated) { try write(archive) }.value
    }

    nonisolated private static func write(_ archive: HyseExportArchive) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Hyse-Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            return try writeFiles(archive, in: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    nonisolated private static func writeFiles(_ archive: HyseExportArchive, in directory: URL) throws -> [URL] {
        let json = JSONEncoder()
        json.outputFormatting = [.prettyPrinted, .sortedKeys]
        json.dateEncodingStrategy = .iso8601
        let archiveURL = directory.appendingPathComponent("hyse-data.json")
        try json.encode(archive).write(to: archiveURL, options: .atomic)

        let foodsURL = directory.appendingPathComponent("food-entries.csv")
        let foodRows = archive.foodEntries.sorted { $0.date < $1.date }.map { entry in
            [entry.id.uuidString, timestamp(entry.date), entry.categoryName, entry.name,
             number(entry.grams), entry.unit.rawValue, number(entry.kcal), number(entry.carbs),
             number(entry.protein), number(entry.fat)]
        }
        try csv(["id", "date", "meal", "name", "amount", "unit", "kcal", "carbs_g", "protein_g", "fat_g"], foodRows)
            .write(to: foodsURL, atomically: true, encoding: .utf8)

        let mealPlanURL = directory.appendingPathComponent("meal-plan.csv")
        let mealPlanRows = archive.plannedRecipes.sorted { $0.date < $1.date }.map { item in
            [item.id.uuidString, timestamp(item.date), item.categoryName, item.recipe.name,
             number(item.servings), item.loggedEntryID?.uuidString ?? ""]
        }
        try csv(["id", "date", "meal", "recipe", "servings", "logged_entry_id"], mealPlanRows)
            .write(to: mealPlanURL, atomically: true, encoding: .utf8)

        let workoutsURL = directory.appendingPathComponent("workouts.csv")
        let workoutRows = archive.workouts.sorted { $0.startedAt < $1.startedAt }.map { workout in
            [workout.id.uuidString, workout.name, timestamp(workout.startedAt),
             workout.completedAt.map(timestamp) ?? "", workout.status.rawValue,
             workout.notes, "\(workout.exercises.count)"]
        }
        try csv(["id", "name", "started_at", "completed_at", "status", "notes", "exercise_count"], workoutRows)
            .write(to: workoutsURL, atomically: true, encoding: .utf8)

        let setsURL = directory.appendingPathComponent("workout-sets.csv")
        let setRows = archive.workouts.flatMap { workout in
            workout.exercises.flatMap { exercise in
                exercise.sets.enumerated().map { index, set in
                    [workout.id.uuidString, exercise.exerciseID.uuidString, exercise.exerciseNameSnapshot,
                     "\(index + 1)", set.type.rawValue, set.completed ? "true" : "false",
                     number(set.weightKilograms), "\(set.reps)", set.rpe.map(number) ?? "",
                     number(set.distanceMeters), number(set.durationSeconds)]
                }
            }
        }
        try csv(["workout_id", "exercise_id", "exercise", "set_number", "type", "completed", "weight_kg", "reps", "rpe", "distance_m", "duration_s"], setRows)
            .write(to: setsURL, atomically: true, encoding: .utf8)

        let weightsURL = directory.appendingPathComponent("body-weight.csv")
        let weightRows = archive.bodyMeasurements.sorted { $0.date < $1.date }.map { value in
            [value.id.uuidString, timestamp(value.date), value.weightKilograms.map(number) ?? "",
             value.bodyFatPercentage.map(number) ?? "", value.source]
        }
        try csv(["id", "date", "weight_kg", "body_fat_percent", "source"], weightRows)
            .write(to: weightsURL, atomically: true, encoding: .utf8)
        let waterURL = directory.appendingPathComponent("water.csv")
        let waterRows = archive.waterMillilitersByDay.sorted { $0.key < $1.key }.map { [$0.key, number($0.value)] }
        try csv(["day", "milliliters"], waterRows).write(to: waterURL, atomically: true, encoding: .utf8)

        let goalsURL = directory.appendingPathComponent("exercise-progress-goals.csv")
        let goalRows = archive.exerciseProgressGoals.sorted { $0.key < $1.key }.map { id, goal in
            [id, "\(goal.minimumRepetitions)", "\(goal.maximumRepetitions)", number(goal.weightIncrementKilograms)]
        }
        try csv(["exercise_id", "min_reps", "max_reps", "weight_increment_kg"], goalRows)
            .write(to: goalsURL, atomically: true, encoding: .utf8)
        return [archiveURL, foodsURL, mealPlanURL, workoutsURL, setsURL, weightsURL, waterURL, goalsURL]
    }

    nonisolated private static func mergedMeasurements(_ training: [BodyMeasurement], _ health: [BodyMeasurement]) -> [BodyMeasurement] {
        var byID: [UUID: BodyMeasurement] = [:]
        for value in health + training { byID[value.id] = value }
        return Array(byID.values)
    }
    nonisolated private static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    nonisolated private static func number(_ value: Double) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
    nonisolated private static func csv(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map { row in
            row.map { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let needsFormulaEscape = trimmed.first.map { "=+-@".contains($0) } == true && Double(trimmed) == nil
                let safeValue = needsFormulaEscape ? "'\(value)" : value
                return "\"\(safeValue.replacingOccurrences(of: "\"", with: "\"\""))\""
            }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }
}

struct HyseExportShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
