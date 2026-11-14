import Foundation

@main
struct TrainingInitialsTests {
    private static func exercise(_ englishName: String, germanName: String = "") -> TrainingExercise {
        TrainingExercise(
            id: UUID(),
            remoteID: nil,
            nameKey: englishName.lowercased().replacingOccurrences(of: " ", with: "_"),
            englishName: englishName,
            germanName: germanName,
            descriptionKey: "",
            techniqueKey: "",
            type: .weightReps,
            equipment: .other,
            primaryMuscles: [],
            secondaryMuscles: [],
            isCustom: false,
            isFavorite: false,
            updatedAt: Date()
        )
    }

    static func main() {
        let cases: [(String, String)] = [
            ("Barbell Bench Press", "BBP"),
            ("Incline Dumbbell Press", "IDP"),
            ("Cable Glute Kickback", "CGK"),
            ("Romanian Deadlift", "RD"),
            ("Pull-Up", "PU"),
            ("Plank", "PL"),
            ("Schulterdrücken", "SD")
        ]

        for (name, expected) in cases {
            let actual = exercise(name).initials(isGerman: false)
            precondition(actual == expected, "\(name): expected \(expected), got \(actual)")
        }

        let localized = exercise("Incline Dumbbell Press", germanName: "Schrägbankdrücken mit Kurzhanteln")
        precondition(localized.initials(isGerman: true) == "SKD")

        let germanOnly = exercise("Schulterdrücken")
        precondition(germanOnly.initials(isGerman: false) == "SD")

        for builtIn in TrainingExercise.builtIns {
            let english = builtIn.initials(isGerman: false)
            let german = builtIn.initials(isGerman: true)
            precondition((2...3).contains(english.count), "Unexpected abbreviation for \(builtIn.englishName): \(english)")
            precondition((2...3).contains(german.count), "Unexpected German abbreviation for \(builtIn.germanName): \(german)")
        }

        let germanExamples = Dictionary(uniqueKeysWithValues: TrainingExercise.builtIns.map { ($0.nameKey, $0.initials(isGerman: true)) })
        precondition(germanExamples["overhead_press"] == "SD")
        precondition(germanExamples["pull_up"] == "KZ")
        precondition(germanExamples["lat_pulldown"] == "LZ")
        precondition(germanExamples["push_up"] == "LS")

        print("Training initials tests passed")
    }
}
