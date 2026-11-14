import Foundation

struct WatchWorkout: Identifiable, Equatable {
    let id: UUID
    let name: String
    let startedAt: Date
    let elapsedSeconds: TimeInterval
    let snapshotAt: Date
    let paused: Bool
    let exercises: [WatchExercise]

    nonisolated init?(_ dictionary: [String: Any]) {
        guard let idString = dictionary["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = dictionary["name"] as? String,
              let startedAt = WatchNumber.double(dictionary["startedAt"]) else { return nil }
        self.id = id
        self.name = name
        self.startedAt = Date(timeIntervalSince1970: startedAt)
        self.elapsedSeconds = max(0, WatchNumber.double(dictionary["elapsedSeconds"]) ?? 0)
        self.snapshotAt = Date(timeIntervalSince1970: WatchNumber.double(dictionary["snapshotAt"]) ?? Date().timeIntervalSince1970)
        self.paused = dictionary["paused"] as? Bool ?? false
        self.exercises = (dictionary["exercises"] as? [[String: Any]] ?? []).compactMap(WatchExercise.init)
    }
}

struct WatchExercise: Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: String
    let sets: [WatchSet]

    nonisolated init?(_ dictionary: [String: Any]) {
        guard let idString = dictionary["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = dictionary["name"] as? String else { return nil }
        self.id = id
        self.name = name
        self.type = dictionary["type"] as? String ?? "weightReps"
        self.sets = (dictionary["sets"] as? [[String: Any]] ?? []).compactMap(WatchSet.init)
    }
}

struct WatchSet: Identifiable, Equatable {
    let id: UUID
    var weight: Double
    var reps: Int
    var durationSeconds: Double
    var distanceMeters: Double
    var completed: Bool

    nonisolated init?(_ dictionary: [String: Any]) {
        guard let idString = dictionary["id"] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        self.id = id
        self.weight = max(0, WatchNumber.double(dictionary["weight"]) ?? 0)
        self.reps = max(0, Int((WatchNumber.double(dictionary["reps"]) ?? 0).rounded()))
        self.durationSeconds = max(0, WatchNumber.double(dictionary["duration"]) ?? 0)
        self.distanceMeters = max(0, WatchNumber.double(dictionary["distance"]) ?? 0)
        self.completed = dictionary["completed"] as? Bool ?? false
    }
}

enum WatchNumber {
    nonisolated static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}
