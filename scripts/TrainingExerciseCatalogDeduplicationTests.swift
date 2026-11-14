import Foundation

@main
struct TrainingExerciseCatalogDeduplicationTests {
    static func main() {
        let builtIns = TrainingExercise.builtIns
        let keys = Set(builtIns.map(\.nameKey))
        precondition(keys.count == builtIns.count)
        precondition(!keys.contains("sl_188") && !keys.contains("sl_214") && !keys.contains("sl_236"))

        let adduction = TrainingExercise.matchingBuiltIn(named: "Adduktoren (Maschine)")
        let abduction = TrainingExercise.matchingBuiltIn(named: "Abduktoren (Maschine)")
        precondition(adduction?.nameKey == "hip_adduction_machine")
        precondition(abduction?.nameKey == "hip_abduction_machine")
        precondition(TrainingExercise.matchingBuiltIn(named: "Hüftadduktion am Kabelzug")?.nameKey == "sl_149")
        precondition(TrainingExercise.matchingBuiltIn(named: "Einbeinige Beinpresse")?.nameKey == "uni_001_single_leg_press")

        func custom(_ name: String, equipment: TrainingEquipment = .machine) -> TrainingExercise {
            TrainingExercise(
                id: UUID(), nameKey: "custom", englishName: name, germanName: name,
                descriptionKey: "", techniqueKey: "", type: .weightReps,
                equipment: equipment, primaryMuscles: ["adductors"], secondaryMuscles: [],
                isCustom: true, isFavorite: false, updatedAt: .distantPast
            )
        }
        let duplicate = custom("Adduktoren (Maschine)")
        precondition(TrainingExercise.isRetiredImported(duplicate))
        precondition(TrainingExercise.catalogDeduplicated(builtIns + [duplicate]).count == builtIns.count)

        let first = custom("Neue Übung", equipment: .cable)
        let repeated = custom("NEUE UEBUNG", equipment: .cable)
        let exactRepeated = custom("neue übung", equipment: .cable)
        let otherEquipment = custom("Neue Übung", equipment: .dumbbell)
        let unique = TrainingExercise.catalogDeduplicated(builtIns + [first, repeated, exactRepeated, otherEquipment])
        precondition(unique.contains(where: { $0.id == first.id }))
        precondition(!unique.contains(where: { $0.id == repeated.id }))
        precondition(!unique.contains(where: { $0.id == exactRepeated.id }))
        precondition(unique.contains(where: { $0.id == otherEquipment.id }))
        precondition(TrainingExercise.matchingCatalogExercise(named: "Adduktoren (Maschine)", equipment: .machine, in: builtIns)?.id == adduction?.id)

        let csv = "title,start_time,end_time,exercise_title,set_type,weight_kg,reps\nLegs,2026-09-20 10:00:00,2026-09-20 11:00:00,Adduktoren (Maschine),normal,35,12\n"
        let imported = try! HevyImportService.parse([
            HevyImportFile(name: "workouts.csv", data: Data(csv.utf8))
        ])
        precondition(imported.customExercises.isEmpty)
        precondition(imported.workouts.first?.exercises.first?.exerciseID == adduction?.id)
        print("Exercise catalog deduplication checks passed")
    }
}
