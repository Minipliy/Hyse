import Foundation

@main
struct TrainingExerciseMuscleAssignmentTests {
    static func main() {
        expect(TrainingExercise.builtIns.allSatisfy { !$0.primaryMuscles.isEmpty }, "every built-in exercise has a primary muscle group")
        let knownMuscles: Set<String> = [
            "chest", "core", "obliques", "front_shoulders", "shoulders", "rear_shoulders",
            "biceps", "triceps", "forearms", "lats", "upper_back", "back", "neck", "traps",
            "glutes", "quadriceps", "adductors", "abductors", "hip_flexors", "hamstrings",
            "calves", "tibialis", "arms", "legs", "cardio", "mobility"
        ]
        expect(TrainingExercise.builtIns.allSatisfy { exercise in
            let primary = Set(exercise.primaryMuscles)
            let secondary = Set(exercise.secondaryMuscles)
            return primary.isSubset(of: knownMuscles) && secondary.isSubset(of: knownMuscles) && primary.isDisjoint(with: secondary)
        }, "every built-in exercise has valid, distinct primary and secondary muscle groups")
        expect(TrainingExercise.builtIns.allSatisfy { !$0.primaryMuscles.contains("other") }, "no known exercise is filed under Other")
        let adductor = TrainingExercise.builtIns.first { $0.germanName == "Adduktorenmaschine" }
        expect(adductor?.primaryMuscles == ["adductors"], "the adductor machine uses adductors")
        let importedLegCurl = imported("Standing Leg Curl", equipment: .machine)
        expect(importedLegCurl.normalizedImportedCatalogEntry().primaryMuscles == ["hamstrings"], "imported leg curls receive hamstrings")
        let importedCurl = imported("Preacher Curl", equipment: .machine)
        expect(importedCurl.normalizedImportedCatalogEntry().primaryMuscles == ["biceps"], "imported curls receive biceps")
        let importedCardio = imported("Rowing Ergometer", equipment: .cardio)
        expect(importedCardio.normalizedImportedCatalogEntry().primaryMuscles.contains("cardio"), "cardio equipment does not get classified as a back row")
        var importedAdductor = imported("Adduktoren (Maschine)", equipment: .machine)
        importedAdductor.primaryMuscles = ["other"]
        expect(importedAdductor.normalizedImportedCatalogEntry().primaryMuscles == ["adductors"], "old adductor imports are reclassified")
        let unknownExercise = imported("Unrecognized Movement", equipment: .other)
        expect(unknownExercise.normalizedImportedCatalogEntry().primaryMuscles == ["other"], "unrecognized imports still show a muscle category")
        var manuallyClassified = unknownExercise
        manuallyClassified.primaryMuscles = ["chest"]
        expect(manuallyClassified.normalizedImportedCatalogEntry().primaryMuscles == ["chest"], "existing manual muscle groups are preserved")
        let repairedSnapshot = TrainingExercise.repairedMuscleAssignment(
            exerciseID: UUID(), englishName: "Preacher Curl", germanName: "Preacher Curl",
            type: .weightReps, equipment: .machine, primary: [], secondary: []
        )
        expect(repairedSnapshot?.primary == ["biceps"], "old workout snapshots receive missing muscle groups")
        let adductorSnapshot = TrainingExercise.repairedMuscleAssignment(
            exerciseID: UUID(), englishName: "Adduktoren (Maschine)", germanName: "Adduktoren (Maschine)",
            type: .weightReps, equipment: .machine, primary: ["other"], secondary: []
        )
        expect(adductorSnapshot?.primary == ["adductors"], "old workout snapshots replace an incorrect Other category")

        let legPress = TrainingExercise.repairedMuscleAssignment(
            exerciseID: UUID(),
            englishName: "Leg Press",
            germanName: "Beinpresse",
            type: .weightReps,
            equipment: .machine,
            primary: ["hamstrings"],
            secondary: []
        )
        expect(
            legPress?.primary == ["quadriceps", "glutes"],
            "leg press repairs stale hamstring-only metadata"
        )

        let seatedMachineRowID = UUID(uuidString: "f30d98f7-c98b-56a2-affd-4802670b9da4")!
        let seatedMachineRow = TrainingExercise.repairedMuscleAssignment(
            exerciseID: seatedMachineRowID,
            englishName: "Rudern sitzend (Maschine)",
            germanName: "Rudern sitzend an der Maschine",
            type: .weightReps,
            equipment: .machine,
            primary: ["lats"],
            secondary: []
        )
        expect(
            seatedMachineRow?.primary == ["upper_back", "lats"],
            "seated machine rows repair stale imports to include upper back"
        )

        let machinePulldownID = UUID(uuidString: "d353fcab-fb06-5622-ba17-5349e8475354")!
        let machinePulldown = TrainingExercise.repairedMuscleAssignment(
            exerciseID: machinePulldownID,
            englishName: "Machine Lat Pulldown",
            germanName: "Latzug an der Maschine",
            type: .weightReps,
            equipment: .machine,
            primary: ["biceps"],
            secondary: []
        )
        expect(
            machinePulldown?.primary == ["lats", "back"],
            "machine lat pulldowns repair stale imports to include the lats"
        )

        let standingHamstringCurl = TrainingExercise.repairedMuscleAssignment(
            exerciseID: UUID(),
            englishName: "Beinbeuger stehend",
            germanName: "Beinbeuger stehend",
            type: .weightReps,
            equipment: .machine,
            primary: [],
            secondary: []
        )
        expect(
            standingHamstringCurl?.primary == ["hamstrings"],
            "standing leg curls receive the hamstrings muscle group"
        )

        let stretchingID = UUID(uuidString: "807cd1ba-1cde-587e-8b95-3b4fd6e80c58")!
        let stretching = TrainingExercise(
            id: stretchingID,
            nameKey: "imported",
            englishName: "Stretching",
            germanName: "Dehnen",
            descriptionKey: "",
            techniqueKey: "",
            type: .weightReps,
            equipment: .other,
            primaryMuscles: [],
            secondaryMuscles: [],
            isCustom: true,
            isFavorite: false,
            updatedAt: .distantPast
        ).normalizedImportedCatalogEntry()
        expect(stretching.type == .duration, "stretching is tracked by duration")

        var timeSet = TrainingSetLog(weightKilograms: 20, reps: 10, durationSeconds: 45)
        timeSet = timeSet.normalized(for: .duration)
        expect(timeSet.weightKilograms == 0 && timeSet.reps == 0 && timeSet.durationSeconds == 45, "duration sets do not retain weight or reps")

        print("TrainingExerciseMuscleAssignmentTests: all checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAILED: \(message)") }
    }

    private static func imported(_ name: String, equipment: TrainingEquipment) -> TrainingExercise {
        TrainingExercise(
            id: UUID(), nameKey: "hevy_import", englishName: name, germanName: name,
            descriptionKey: "", techniqueKey: "", type: .weightReps, equipment: equipment,
            primaryMuscles: [], secondaryMuscles: [], isCustom: true, isFavorite: false, updatedAt: .distantPast
        )
    }
}
