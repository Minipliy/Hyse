import ActivityKit
import Foundation

nonisolated struct TrainingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var workoutName: String
        var currentExercise: String
        var setNumber: Int
        var totalSets: Int
        var completedSets: Int
        var weightText: String
        var repetitionsText: String
        var durationStartDate: Date
        var pausedDurationSeconds: TimeInterval
        var restTimerEnd: Date?
        var timerStatus: String
        var workoutPaused: Bool
        var completed: Bool
    }

    var workoutID: String
}
