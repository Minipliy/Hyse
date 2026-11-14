import Foundation
import Combine
import HealthKit

@MainActor
final class WatchWorkoutHealthManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutHealthManager()

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var heartRate = 0.0
    @Published private(set) var activeCalories = 0.0
    @Published private(set) var errorMessage: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var workoutID: UUID?
    private var isEnding = false
    private var isStarting = false
    private var requestedWorkoutID: UUID?
    private var requestedPausedState = false

    private var heartRateType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .heartRate)
    }
    private var activeEnergyType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
    }

    func reconcile(workoutID: UUID, paused: Bool) async {
        requestedWorkoutID = workoutID
        requestedPausedState = paused
        if session == nil {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            await start(configuration: configuration, workoutID: workoutID)
        } else {
            self.workoutID = workoutID
            setPaused(paused)
        }
    }

    func start(configuration: HKWorkoutConfiguration, workoutID: UUID? = nil) async {
        if let workoutID { requestedWorkoutID = workoutID }
        if session != nil {
            if let requestedWorkoutID { self.workoutID = requestedWorkoutID }
            return
        }
        // The system workout launch and WatchConnectivity application context
        // often arrive together. Health authorization suspends this method, so
        // guard against creating two competing HKWorkoutSession instances.
        guard !isStarting else { return }
        isStarting = true
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = String(localized: "Health-Daten sind auf dieser Apple Watch nicht verfügbar.")
            isStarting = false
            return
        }
        do {
            try await requestAuthorization()
            guard session == nil else {
                isStarting = false
                return
            }
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            newSession.delegate = self
            newBuilder.delegate = self
            session = newSession
            builder = newBuilder
            self.workoutID = requestedWorkoutID ?? workoutID
            isEnding = false
            errorMessage = nil
            heartRate = 0
            activeCalories = 0

            let startDate = Date()
            newSession.startActivity(with: startDate)
            try await newBuilder.beginCollection(at: startDate)
            isRecording = true
            isPaused = false
            isStarting = false
            if requestedPausedState { setPaused(true) }
        } catch {
            isStarting = false
            resetSession()
            errorMessage = error.localizedDescription
        }
    }

    func recoverActiveSession() {
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let recovered else {
                    if let error { self.errorMessage = error.localizedDescription }
                    return
                }
                self.session = recovered
                self.builder = recovered.associatedWorkoutBuilder()
                self.session?.delegate = self
                self.builder?.delegate = self
                self.isRecording = true
                self.isPaused = recovered.state == .paused
                self.updateLiveMetrics()
            }
        }
    }

    func setPaused(_ paused: Bool) {
        guard let session, isRecording, !isEnding, paused != isPaused else { return }
        if paused { session.pause() } else { session.resume() }
        isPaused = paused
    }

    func end(save: Bool, workoutID expectedWorkoutID: UUID? = nil) {
        if let expectedWorkoutID, let workoutID, workoutID != expectedWorkoutID { return }
        guard let session, let builder, !isEnding else { return }
        isEnding = true
        let endDate = Date()
        session.end()
        builder.endCollection(withEnd: endDate) { [weak self] success, error in
            guard success, error == nil, save else {
                builder.discardWorkout()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error { self.errorMessage = error.localizedDescription }
                    self.resetSession()
                }
                return
            }
            builder.finishWorkout { [weak self] _, finishError in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let finishError { self.errorMessage = finishError.localizedDescription }
                    self.resetSession()
                }
            }
        }
    }

    private func requestAuthorization() async throws {
        var read = Set<HKObjectType>()
        if let heartRateType { read.insert(heartRateType) }
        if let activeEnergyType { read.insert(activeEnergyType) }
        try await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
    }

    private func updateLiveMetrics() {
        guard let builder else { return }
        if let heartRateType,
           let quantity = builder.statistics(for: heartRateType)?.mostRecentQuantity() {
            heartRate = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if let activeEnergyType,
           let quantity = builder.statistics(for: activeEnergyType)?.sumQuantity() {
            activeCalories = quantity.doubleValue(for: .kilocalorie())
        }
    }

    private func resetSession() {
        session = nil
        builder = nil
        workoutID = nil
        isRecording = false
        isPaused = false
        isEnding = false
        isStarting = false
        requestedWorkoutID = nil
        requestedPausedState = false
    }
}

extension WatchWorkoutHealthManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.isRecording = toState == .running || toState == .paused
            self.isPaused = toState == .paused
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
            self.resetSession()
        }
    }
}

extension WatchWorkoutHealthManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in self.updateLiveMetrics() }
    }
}
