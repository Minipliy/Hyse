import Foundation

@main
enum TrainingExerciseGuideTests {
    static func main() {
        let genericGerman = "Richte dich stabil ein und führe jede Wiederholung langsam über einen schmerzfreien Bewegungsumfang aus. Vermeide Schwung und stoppe, wenn die Technik nachlässt."
        let genericEnglish = "Set up in a stable position and perform each repetition slowly through a pain-free range. Avoid momentum and stop when your technique breaks down."
        let strengthLogGerman = "Nimm eine stabile Ausgangsposition ein, bewege den Widerstand kontrolliert durch den vorgesehenen Bewegungsumfang und führe ihn langsam zurück. Halte den Rumpf ruhig."
        let strengthLogEnglish = "Set a stable starting position, move the resistance through the intended range under control, and return it slowly. Keep your trunk steady."

        for exercise in TrainingExercise.builtIns {
            let german = exercise.executionGuide(isGerman: true)
            let english = exercise.executionGuide(isGerman: false)
            expect(!german.isEmpty && !english.isEmpty, "\(exercise.nameKey) has guides in both languages")
            expect(german != genericGerman && english != genericEnglish, "\(exercise.nameKey) has no generic fallback")
            expect(german != strengthLogGerman && english != strengthLogEnglish, "\(exercise.nameKey) has a movement guide")
            if exercise.nameKey.hasPrefix("uni_") {
                expect(UnilateralExerciseDirectory.guide(for: exercise, isGerman: true) != nil, "\(exercise.nameKey) has unilateral instructions")
                let lower = german.lowercased()
                expect(lower.contains("wechsle") || lower.contains("andere") || lower.contains("beide"), "\(exercise.nameKey) explains switching sides")
            }
        }

        let singleLegPress = guide("uni_001_single_leg_press")
        expect(singleLegPress.contains("einen Fuß") && singleLegPress.contains("Beuge"), "single-leg press describes setup and movement")
        let wristExtension = guide("uni_072_single_arm_dumbbell_wrist_extension")
        expect(wristExtension.contains("Handfläche nach unten"), "wrist extension specifies the correct grip")
        let reverseFly = guide("sl_082")
        expect(reverseFly.contains("seitlich nach hinten"), "reverse fly does not receive the chest-fly cue")

        print("TrainingExerciseGuideTests: \(TrainingExercise.builtIns.count) catalog exercises have concrete German and English guides")
    }

    private static func guide(_ key: String) -> String {
        guard let exercise = TrainingExercise.builtIns.first(where: { $0.nameKey == key }) else {
            fatalError("Missing exercise: \(key)")
        }
        return exercise.executionGuide(isGerman: true)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAILED: \(message)") }
    }
}
