import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchConnectivityStore: NSObject, ObservableObject, WCSessionDelegate {
    enum DeliveryState: Equatable {
        case idle
        case sending
        case saved
        case queued
        case failed
    }

    @Published private(set) var workout: WatchWorkout?
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var deliveryState: DeliveryState = .idle

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if !session.receivedApplicationContext.isEmpty {
            apply(session.receivedApplicationContext)
        }
        session.activate()
    }

    func requestLatestState() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        isPhoneReachable = session.isReachable
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["kind": "requestState"], replyHandler: nil, errorHandler: nil)
    }

    func addQuickNutrition(calories: Double, carbs: Double, protein: Double, fat: Double) {
        send([
            "kind": "quickNutrition",
            "calories": max(0, calories),
            "carbs": max(0, carbs),
            "protein": max(0, protein),
            "fat": max(0, fat)
        ])
    }

    func updateSet(workoutID: UUID, exerciseID: UUID, set: WatchSet) {
        send([
            "kind": "updateSet",
            "workoutID": workoutID.uuidString,
            "exerciseID": exerciseID.uuidString,
            "setID": set.id.uuidString,
            "weight": set.weight,
            "reps": set.reps,
            "duration": set.durationSeconds,
            "distance": set.distanceMeters,
            "completed": set.completed
        ])
    }

    private func send(_ values: [String: Any]) {
        guard WCSession.isSupported() else {
            deliveryState = .failed
            return
        }
        var message = values
        message["requestID"] = UUID().uuidString
        let session = WCSession.default
        isPhoneReachable = session.isReachable
        if session.activationState == .activated, session.isReachable {
            deliveryState = .sending
            session.sendMessage(message) { [weak self] response in
                Task { @MainActor in
                    self?.deliveryState = response["ok"] as? Bool == true ? .saved : .failed
                    self?.clearDeliveryStateLater()
                }
            } errorHandler: { [weak self] _ in
                session.transferUserInfo(message)
                Task { @MainActor in
                    self?.deliveryState = .queued
                    self?.clearDeliveryStateLater()
                }
            }
        } else {
            session.transferUserInfo(message)
            deliveryState = .queued
            clearDeliveryStateLater()
        }
    }

    private func clearDeliveryStateLater() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.deliveryState = .idle
        }
    }

    private func apply(_ payload: [String: Any]) {
        let kind = payload["kind"] as? String
        if kind == "workoutControl" {
            let endedWorkoutID = (payload["workoutID"] as? String).flatMap(UUID.init(uuidString:))
            if let endedWorkoutID, let workout, workout.id != endedWorkoutID { return }
            let shouldSave = payload["action"] as? String != "discard"
            WatchWorkoutHealthManager.shared.end(save: shouldSave, workoutID: endedWorkoutID)
            workout = nil
            return
        }
        guard kind == "state" else { return }
        if payload["hasWorkout"] as? Bool == true,
           let dictionary = payload["workout"] as? [String: Any] {
            let receivedWorkout = WatchWorkout(dictionary)
            workout = receivedWorkout
            let shouldAutomaticallyRecord = payload["automaticallyStartHealthWorkout"] as? Bool ?? true
            if let receivedWorkout,
               shouldAutomaticallyRecord || WatchWorkoutHealthManager.shared.isRecording {
                Task {
                    await WatchWorkoutHealthManager.shared.reconcile(
                        workoutID: receivedWorkout.id,
                        paused: receivedWorkout.paused
                    )
                }
            }
        } else {
            if let action = payload["workoutEndAction"] as? String {
                let endedWorkoutID = (payload["workoutEndID"] as? String).flatMap(UUID.init(uuidString:))
                if let endedWorkoutID, let workout, workout.id != endedWorkoutID { return }
                WatchWorkoutHealthManager.shared.end(save: action != "discard", workoutID: endedWorkoutID)
            }
            workout = nil
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            if activationState == .activated { self.requestLatestState() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            if session.isReachable { self.requestLatestState() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.apply(userInfo) }
    }
}
