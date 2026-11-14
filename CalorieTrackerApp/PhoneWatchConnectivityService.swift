import Foundation
import Combine
import WatchConnectivity
import HealthKit
import OSLog

@MainActor
final class PhoneWatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchConnectivityService()

    private weak var calorieStore: CalorieStore?
    private weak var categoryStore: CategoryStore?
    private weak var trainingStore: TrainingStore?
    private weak var settingsStore: UserSettingsStore?
    private var trainingObservation: AnyCancellable?
    private var settingsObservation: AnyCancellable?
    private var snapshotTask: Task<Void, Never>?
    private var processedRequestIDs = Set<String>()
    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "AppleWatchWorkout")
    private var launchedWatchWorkoutID: UUID?
    private var launchingWatchWorkoutID: UUID?
    private var watchLaunchTask: Task<Void, Never>?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func configure(calorieStore: CalorieStore, categoryStore: CategoryStore, trainingStore: TrainingStore, settingsStore: UserSettingsStore) {
        self.calorieStore = calorieStore
        self.categoryStore = categoryStore
        self.trainingStore = trainingStore
        self.settingsStore = settingsStore
        trainingObservation = trainingStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.scheduleSnapshot() }
        }
        settingsObservation = settingsStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleSnapshot(delay: .milliseconds(60))
                // objectWillChange fires before the new value is visible.
                // Re-evaluate on the next MainActor turn so enabling the switch
                // while a workout is active also wakes the Watch immediately.
                await Task.yield()
                guard settingsStore.automaticallyStartAppleWatchWorkout else {
                    self.cancelPendingWatchLaunch()
                    return
                }
                if let workout = trainingStore.activeWorkout {
                    self.startWatchWorkout(for: workout)
                }
            }
        }
        scheduleSnapshot(delay: .milliseconds(120))
        if let workout = trainingStore.activeWorkout {
            startWatchWorkout(for: workout)
        }
    }

    func startWatchWorkout(for workout: WorkoutLog) {
        guard settingsStore?.automaticallyStartAppleWatchWorkout ?? true,
              launchedWatchWorkoutID != workout.id,
              launchingWatchWorkoutID != workout.id,
              HKHealthStore.isHealthDataAvailable() else { return }

        launchingWatchWorkoutID = workout.id
        // Publish the Hyse workout identity before waking the Watch. Its app
        // delegate and connectivity context can then converge on the same
        // HealthKit session without waiting for the launch callback.
        pushSnapshot()
        queueWorkoutSnapshotForWatch()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.exercises.contains(where: { $0.exerciseTypeSnapshot == .distanceDuration })
            ? .mixedCardio
            : .traditionalStrengthTraining
        configuration.locationType = .indoor
        let workoutID = workout.id

        watchLaunchTask?.cancel()
        watchLaunchTask = Task { [weak self] in
            guard let self else { return }
            var lastError: Error?
            for attempt in 0..<2 {
                guard !Task.isCancelled,
                      self.trainingStore?.activeWorkout?.id == workoutID,
                      self.settingsStore?.automaticallyStartAppleWatchWorkout ?? true else {
                    if self.launchingWatchWorkoutID == workoutID {
                        self.launchingWatchWorkoutID = nil
                    }
                    return
                }
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(1.25))
                    guard !Task.isCancelled else { return }
                    self.queueWorkoutSnapshotForWatch()
                }
                do {
                    try await self.healthStore.startWatchApp(toHandle: configuration)
                    guard self.trainingStore?.activeWorkout?.id == workoutID else { return }
                    self.launchedWatchWorkoutID = workoutID
                    self.launchingWatchWorkoutID = nil
                    self.logger.info("Apple Watch workout launch accepted for \(workoutID.uuidString, privacy: .public)")
                    self.scheduleSnapshot(delay: .zero)
                    return
                } catch {
                    lastError = error
                    self.logger.error("Apple Watch workout launch attempt \(attempt + 1) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if self.launchingWatchWorkoutID == workoutID { self.launchingWatchWorkoutID = nil }
            if let lastError {
                self.logger.error("Apple Watch workout could not be started: \(lastError.localizedDescription, privacy: .public)")
            }
        }
    }

    private func cancelPendingWatchLaunch() {
        watchLaunchTask?.cancel()
        watchLaunchTask = nil
        launchingWatchWorkoutID = nil
    }

    func endWatchWorkout(save: Bool) {
        let endedWorkoutID = launchedWatchWorkoutID ?? launchingWatchWorkoutID
        watchLaunchTask?.cancel()
        watchLaunchTask = nil
        launchedWatchWorkoutID = nil
        launchingWatchWorkoutID = nil
        let action = save ? "finish" : "discard"
        var control: [String: Any] = ["kind": "workoutControl", "action": action, "requestID": UUID().uuidString]
        if let endedWorkoutID {
            control["workoutID"] = endedWorkoutID.uuidString
        }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }

        var state = workoutPayload()
        state["workoutEndAction"] = action
        if let endedWorkoutID {
            state["workoutEndID"] = endedWorkoutID.uuidString
        }
        try? WCSession.default.updateApplicationContext(state)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(control, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(control)
            }
        } else {
            WCSession.default.transferUserInfo(control)
        }
    }

    private func scheduleSnapshot(delay: Duration = .milliseconds(220)) {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pushSnapshot()
        }
    }

    private func pushSnapshot() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload = workoutPayload()
        try? WCSession.default.updateApplicationContext(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    /// Application context keeps only the newest state, while user info is
    /// queued until watchOS can deliver it. Using both closes the timing gap
    /// between HealthKit waking the Watch and WatchConnectivity activating.
    private func queueWorkoutSnapshotForWatch() {
        guard WCSession.isSupported() else { return }
        let payload = workoutPayload()
        let session = WCSession.default
        if session.activationState == .activated {
            try? session.updateApplicationContext(payload)
        }
        session.transferUserInfo(payload)
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func workoutPayload() -> [String: Any] {
        guard let workout = trainingStore?.activeWorkout else {
            return ["kind": "state", "version": 1, "hasWorkout": false]
        }
        return [
            "kind": "state",
            "version": 1,
            "hasWorkout": true,
            "automaticallyStartHealthWorkout": settingsStore?.automaticallyStartAppleWatchWorkout ?? true,
            "workout": [
                "id": workout.id.uuidString,
                "name": workout.name,
                "startedAt": workout.startedAt.timeIntervalSince1970,
                "elapsedSeconds": workout.duration,
                "snapshotAt": Date().timeIntervalSince1970,
                "paused": workout.status == .paused,
                "exercises": workout.exercises.map { exercise in
                    [
                        "id": exercise.id.uuidString,
                        "name": exercise.exerciseGermanNameSnapshot.isEmpty ? exercise.exerciseNameSnapshot : exercise.exerciseGermanNameSnapshot,
                        "type": exercise.exerciseTypeSnapshot.rawValue,
                        "sets": exercise.sets.map { set in
                            [
                                "id": set.id.uuidString,
                                "weight": set.weightKilograms,
                                "reps": set.reps,
                                "duration": set.durationSeconds,
                                "distance": set.distanceMeters,
                                "completed": set.completed
                            ] as [String: Any]
                        }
                    ] as [String: Any]
                }
            ] as [String: Any]
        ]
    }

    private func handle(_ message: [String: Any]) -> [String: Any] {
        guard let kind = message["kind"] as? String else { return ["ok": false] }
        if kind == "requestState" {
            scheduleSnapshot(delay: .zero)
            return ["ok": true]
        }
        guard let requestID = message["requestID"] as? String else { return ["ok": false] }
        if processedRequestIDs.contains(requestID) { return ["ok": true, "duplicate": true] }

        let handled: Bool
        switch kind {
        case "quickNutrition": handled = addQuickNutrition(message)
        case "updateSet": handled = updateTrainingSet(message)
        default: handled = false
        }
        guard handled else { return ["ok": false] }
        processedRequestIDs.insert(requestID)
        if processedRequestIDs.count > 200 {
            processedRequestIDs = Set(processedRequestIDs.prefix(150))
        }
        scheduleSnapshot(delay: .milliseconds(60))
        return ["ok": true]
    }

    private func addQuickNutrition(_ message: [String: Any]) -> Bool {
        guard let calorieStore, let categoryStore,
              let calories = number(message["calories"]), calories > 0 else { return false }
        let category = categoryStore.categories.first { $0.storageKey == "snacks" } ?? categoryStore.categories.first
        guard let category else { return false }
        let carbs = max(0, number(message["carbs"]) ?? 0)
        let protein = max(0, number(message["protein"]) ?? 0)
        let fat = max(0, number(message["fat"]) ?? 0)
        return calorieStore.addEntry(CalorieEntry(
            name: "Apple Watch Schnell-Eintrag",
            grams: 100,
            categoryId: category.id,
            categoryName: category.storageKey,
            kcalPer100g: calories,
            carbsPer100g: carbs,
            proteinPer100g: protein,
            fatPer100g: fat
        ))
    }

    private func updateTrainingSet(_ message: [String: Any]) -> Bool {
        guard let trainingStore,
              let workoutID = uuid(message["workoutID"]), trainingStore.activeWorkout?.id == workoutID,
              let exerciseID = uuid(message["exerciseID"]),
              let setID = uuid(message["setID"]),
              let exercise = trainingStore.activeWorkout?.exercises.first(where: { $0.id == exerciseID }),
              var set = exercise.sets.first(where: { $0.id == setID }) else { return false }
        switch exercise.exerciseTypeSnapshot {
        case .weightReps, .bodyweight:
            if let weight = number(message["weight"]) { set.weightKilograms = max(0, weight) }
            if let reps = number(message["reps"]) { set.reps = max(0, Int(reps.rounded())) }
        case .duration:
            if let duration = number(message["duration"]) { set.durationSeconds = max(0, duration) }
        case .distanceDuration:
            if let distance = number(message["distance"]) { set.distanceMeters = max(0, distance) }
            if let duration = number(message["duration"]) { set.durationSeconds = max(0, duration) }
        case .repsOnly:
            if let reps = number(message["reps"]) { set.reps = max(0, Int(reps.rounded())) }
        }
        trainingStore.updateSet(exerciseID: exerciseID, set: set)
        if let completed = message["completed"] as? Bool, completed != set.completed {
            trainingStore.toggleSet(exerciseID: exerciseID, setID: setID)
        }
        trainingStore.flushPendingChanges()
        return true
    }

    private func uuid(_ value: Any?) -> UUID? { (value as? String).flatMap(UUID.init(uuidString:)) }
    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.scheduleSnapshot(delay: .zero)
            if let workout = self.trainingStore?.activeWorkout {
                self.startWatchWorkout(for: workout)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.handle(message)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in _ = self.handle(userInfo) }
    }
}
