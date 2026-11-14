import Foundation

@main
struct TrainingExerciseSearchTests {
    static func main() {
        let exercises = TrainingExercise.builtIns
        let muscleNames = [
            "chest": "Brust",
            "back": "Rücken",
            "core": "Rumpf",
            "glutes": "Gesäß",
            "lats": "Latissimus",
            "upper_back": "Oberer Rücken"
        ]
        func score(_ key: String, _ query: String) -> Int? {
            guard let exercise = exercises.first(where: { $0.nameKey == key }) else {
                preconditionFailure("Missing exercise \(key)")
            }
            return TrainingExerciseSearch.score(
                exercise,
                query: query,
                isGerman: true,
                muscleName: { muscleNames[$0] ?? $0 }
            )
        }

        precondition(score("barbell_bench_press", "bankdruken") != nil)
        precondition(score("barbell_bench_press", "brsut") != nil)
        precondition(score("seated_cable_row", "kabel rudrn") != nil)
        precondition(score("pull_up", "Rükken") != nil)
        precondition(score("plank", "Bauch") != nil)
        precondition(score("hip_thrust", "po") != nil)
        precondition(score("biceps_curl", "Kurzhantel Bizeps") != nil)
        precondition(score("barbell_bench_press", "Bankdrücken")! < score("barbell_bench_press", "Brust")!)
        precondition(score("barbell_bench_press", "Brust")! < score("supported_chest_row", "Brust")!)
        precondition(score("barbell_bench_press", "Waden") == nil)
        print("Exercise search tests passed.")
    }
}
