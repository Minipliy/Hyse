import Foundation

struct MonthlyRecordItem: Identifiable {
    let id: String
    let exercise: WorkoutExerciseLog
    let flag: String
    let set: TrainingSetLog
}

enum MonthlyPersonalRecordHistory {
    private struct Best {
        var weight = 0.0
        var reps = 0
        var volume = 0.0
        var estimatedOneRepMaximum = 0.0
        var hasPerformance = false
    }

    static func recordsByMonth(workouts: [WorkoutLog], calendar: Calendar) -> [Date: [MonthlyRecordItem]] {
        var bestByExercise: [UUID: Best] = [:]
        var records: [Date: [MonthlyRecordItem]] = [:]
        let orderedWorkouts = workouts.sorted {
            let left = $0.completedAt ?? $0.startedAt
            let right = $1.completedAt ?? $1.startedAt
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
        for workout in orderedWorkouts {
            let date = workout.completedAt ?? workout.startedAt
            let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
            for exercise in workout.exercises {
                for set in exercise.sets where set.completed {
                    let weight = max(0, set.weightKilograms)
                    let reps = max(0, set.reps)
                    let volume = set.volume
                    let estimate = set.estimatedOneRepMaximum
                    guard set.hasRecordablePerformance else { continue }
                    var best = bestByExercise[exercise.exerciseID] ?? Best()
                    var flags: [String] = []
                    if best.hasPerformance {
                        if weight > best.weight { flags.append("weight") }
                        if reps > best.reps { flags.append("reps") }
                        if volume > best.volume { flags.append("set_volume") }
                        if estimate > best.estimatedOneRepMaximum { flags.append("estimated_1rm") }
                    }
                    best.weight = max(best.weight, weight)
                    best.reps = max(best.reps, reps)
                    best.volume = max(best.volume, volume)
                    best.estimatedOneRepMaximum = max(best.estimatedOneRepMaximum, estimate)
                    best.hasPerformance = true
                    bestByExercise[exercise.exerciseID] = best
                    for flag in flags {
                        records[month, default: []].append(MonthlyRecordItem(
                            id: "\(workout.id.uuidString)|\(set.id.uuidString)|\(flag)",
                            exercise: exercise, flag: flag, set: set
                        ))
                    }
                }
            }
        }
        return records
    }
}
