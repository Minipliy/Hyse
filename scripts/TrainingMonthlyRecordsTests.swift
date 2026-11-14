import Foundation

struct TrainingSetLog: Codable {
    let id: UUID
    let weightKilograms: Double
    let reps: Int
    let durationSeconds: Double
    let distanceMeters: Double
    let completed: Bool
    var volume: Double { completed ? weightKilograms * Double(reps) : 0 }
    var estimatedOneRepMaximum: Double { completed && weightKilograms > 0 && reps > 0 ? weightKilograms * (1 + Double(reps) / 30) : 0 }
}

struct WorkoutExerciseLog: Codable {
    let exerciseID: UUID
    let sets: [TrainingSetLog]
}

struct WorkoutLog: Codable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let exercises: [WorkoutExerciseLog]
}

@main
struct TrainingMonthlyRecordsTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        func date(_ value: String) -> Date { formatter.date(from: value)! }
        func set(_ weight: Double, _ reps: Int, completed: Bool = true) -> TrainingSetLog {
            TrainingSetLog(id: UUID(), weightKilograms: weight, reps: reps, durationSeconds: 0, distanceMeters: 0, completed: completed)
        }
        let exerciseID = UUID()
        func workout(_ day: String, _ sets: [TrainingSetLog]) -> WorkoutLog {
            let timestamp = date(day)
            return WorkoutLog(id: UUID(), startedAt: timestamp, completedAt: timestamp, exercises: [WorkoutExerciseLog(exerciseID: exerciseID, sets: sets)])
        }
        let august = workout("2026-08-10T12:00:00Z", [set(60, 8), set(60, 8), set(200, 20, completed: false)])
        let september = workout("2026-09-10T12:00:00Z", [set(70, 8), set(70, 10)])
        let saved = try JSONDecoder().decode([WorkoutLog].self, from: JSONEncoder().encode([september, august]))
        let result = MonthlyPersonalRecordHistory.recordsByMonth(workouts: saved, calendar: calendar)
        let augustMonth = calendar.dateInterval(of: .month, for: august.completedAt!)!.start
        let septemberMonth = calendar.dateInterval(of: .month, for: september.completedAt!)!.start
        precondition(result[augustMonth]?.map(\.flag) == ["first_performance"])
        precondition(result[septemberMonth]?.map(\.flag) == ["weight", "set_volume", "estimated_1rm", "reps", "set_volume", "estimated_1rm"])
        precondition(Set((result[augustMonth] ?? []).map(\.id)).count == result[augustMonth]?.count)
        print("Monthly personal record history tests passed.")
    }
}
