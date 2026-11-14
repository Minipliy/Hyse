import Foundation

@main
enum HevyImportTests {
    static func main() throws {
        try testRoutineExtraction()
        try testCustomExercisesUsedByImportedRoutines()
        if CommandLine.arguments.count == 1 {
            print("Hevy routine extraction tests passed")
            return
        }
        guard CommandLine.arguments.count == 3 else {
            throw TestError(message: "Usage: HevyImportTests workout_data.csv measurement_data.csv")
        }
        let files = try CommandLine.arguments.dropFirst().map { path in
            HevyImportFile(name: URL(fileURLWithPath: path).lastPathComponent, data: try Data(contentsOf: URL(fileURLWithPath: path)))
        }
        let referenceDate = Date()
        let parsed = try HevyImportService.parse(files, referenceDate: referenceDate)
        try expect(parsed.workouts.count == 478, "Expected 478 workouts, got \(parsed.workouts.count); ignored \(parsed.ignoredRows) rows")
        try expect(parsed.workouts.flatMap(\.completedSets).count == 9_839, "Expected 9839 completed sets")
        try expect(parsed.measurements.count == 496, "Expected 496 measurements, got \(parsed.measurements.count)")
        try expect(parsed.workouts.allSatisfy { $0.status == .completed && $0.completedAt != nil }, "Imported workouts must be completed")
        try expect(parsed.workouts.flatMap(\.completedSets).contains { $0.distanceMeters > 0 }, "Distance values were not imported")
        try expect(parsed.workouts.flatMap(\.completedSets).contains { $0.durationSeconds > 0 }, "Duration values were not imported")
        try expect(parsed.workouts.flatMap(\.completedSets).contains { $0.type == .warmup }, "Warm-up sets were not imported")
        try expect(Set(parsed.routines.map { $0.name.lowercased() }).count == parsed.routines.count, "Workout names should produce one routine each")
        let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: referenceDate)!
        try expect(parsed.routines.allSatisfy { $0.updatedAt >= cutoff && $0.updatedAt <= referenceDate }, "Only last month's workouts should produce routines")
        try expect(parsed.routines.flatMap(\.exercises).flatMap(\.sets).allSatisfy { !$0.completed && $0.completedAt == nil }, "Routine sets must be ready for a new workout")
        let secondPass = try HevyImportService.parse(files, referenceDate: referenceDate)
        try expect(Set(parsed.workouts.map(\.id)) == Set(secondPass.workouts.map(\.id)), "Workout IDs are not stable")
        try expect(Set(parsed.routines.map(\.id)) == Set(secondPass.routines.map(\.id)), "Routine IDs are not stable")
        try expect(Set(parsed.measurements.map(\.id)) == Set(secondPass.measurements.map(\.id)), "Measurement IDs are not stable")
        print("Hevy import tests passed: \(parsed.workouts.count) workouts, \(parsed.workouts.flatMap(\.completedSets).count) sets, \(parsed.measurements.count) measurements, \(parsed.customExercises.count) custom exercises")
    }

    private static func testRoutineExtraction() throws {
        let sample = "title,start_time,end_time,exercise_title,set_type,weight_kg,reps\nUpper,2025-01-20 10:00:00,2025-01-20 11:00:00,Bench Press,normal,40,8\nUpper,2025-02-01 10:00:00,2025-02-01 11:00:00,Bench Press,normal,60,6\nOld Split,2025-01-01 10:00:00,2025-01-01 11:00:00,Bench Press,normal,70,5\nFuture,2025-03-01 10:00:00,2025-03-01 11:00:00,Bench Press,normal,80,4\n"
        let file = HevyImportFile(name: "workout_data.csv", data: Data(sample.utf8))
        let referenceDate = Calendar.current.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 12))!
        let parsed = try HevyImportService.parse([file], referenceDate: referenceDate)
        try expect(parsed.workouts.count == 4, "Full workout history should still import")
        try expect(parsed.routines.count == 1, "Repeated workout names should make one template")
        try expect(parsed.routines.first?.name == "Upper", "Old and future workouts should not make templates")
        try expect(parsed.routines.first?.exercises.first?.sets.first?.weightKilograms == 60, "Template should use the newest workout's values")
        try expect(parsed.routines.first?.exercises.first?.sets.first?.completed == false, "Template sets should be incomplete")
        let secondPass = try HevyImportService.parse([file], referenceDate: referenceDate)
        try expect(parsed.routines.map(\.id) == secondPass.routines.map(\.id), "Reimport should use stable routine IDs")
    }

    private static func testCustomExercisesUsedByImportedRoutines() throws {
        let sample = "title,start_time,end_time,exercise_title,set_type,weight_kg,reps\nCustom Day,2025-02-10 10:00:00,2025-02-10 11:00:00,Dragon Cable Press 987,normal,35,8\n"
        let file = HevyImportFile(name: "workout_data.csv", data: Data(sample.utf8))
        let referenceDate = Calendar.current.date(from: DateComponents(year: 2025, month: 2, day: 15, hour: 12))!
        let parsed = try HevyImportService.parse([file], referenceDate: referenceDate)
        let imported = try require(parsed.customExercises.first, "Missing custom Hevy exercise")

        let fresh = HevyImportService.resolvingExercises(parsed, against: TrainingExercise.builtIns)
        try expect(fresh.customExercises.map(\.id) == [imported.id], "New Hevy exercise must be added to Hyse")
        try expect(fresh.routines.first?.exercises.first?.exercise.id == imported.id, "Routine must use the new catalog exercise")
        let repeated = HevyImportService.resolvingExercises(parsed, against: TrainingExercise.builtIns + fresh.customExercises)
        try expect(repeated.customExercises.isEmpty, "Reimport should not duplicate a Hevy exercise")
        try expect(repeated.routines.first?.exercises.first?.exercise.id == imported.id, "Reimport must keep the routine exercise ID")

        var existing = imported
        existing.id = UUID()
        let merged = HevyImportService.resolvingExercises(parsed, against: TrainingExercise.builtIns + [existing])
        try expect(merged.customExercises.isEmpty, "An existing Hyse exercise should not be duplicated")
        try expect(merged.routines.first?.exercises.first?.exercise.id == existing.id, "Routine must use the existing Hyse exercise")
        try expect(merged.workouts.first?.exercises.first?.exerciseID == existing.id, "Workout history must use the same exercise ID")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestError(message: message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestError(message: message) }
    }

    private struct TestError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
