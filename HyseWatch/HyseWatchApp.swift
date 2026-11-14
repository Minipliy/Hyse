import SwiftUI
import WatchKit
import HealthKit

final class HyseWatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchWorkoutHealthManager.shared.start(configuration: workoutConfiguration)
        }
    }

    func handleActiveWorkoutRecovery() {
        Task { @MainActor in WatchWorkoutHealthManager.shared.recoverActiveSession() }
    }
}

@main
struct HyseWatchApp: App {
    @WKApplicationDelegateAdaptor(HyseWatchAppDelegate.self) private var appDelegate
    @StateObject private var connectivity = WatchConnectivityStore()
    @StateObject private var workoutHealth = WatchWorkoutHealthManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(connectivity)
                .environmentObject(workoutHealth)
        }
    }
}
