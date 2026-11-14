import AVFAudio
import AudioToolbox
import Foundation
import OSLog
import UIKit

@MainActor
final class RestFeedbackController: NSObject, AVAudioPlayerDelegate {
    static let shared = RestFeedbackController()

    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "RestFeedback")
    private var player: AVAudioPlayer?
    private var completedTimerIDs: Set<UUID> = []
    private var previewID: UUID?

    func playTimerCompletion(timerID: UUID) {
        guard !completedTimerIDs.contains(timerID) else { return }
        completedTimerIDs.insert(timerID)

        if UIApplication.shared.applicationState == .active,
           UserDefaults.standard.object(forKey: "restHapticsEnabled_v1") as? Bool ?? true {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        guard UserDefaults.standard.object(forKey: "restSoundEnabled_v1") as? Bool ?? true else { return }
        play(variant: storedVariant, volume: storedVolume)
    }

    func playPersonalRecord() {
        guard UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey: "restSoundEnabled_v1") as? Bool ?? true else { return }
        play(variant: .bright, volume: max(storedVolume, 0.7))
    }

    func playSetCompletion() {
        guard UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey: "restSoundEnabled_v1") as? Bool ?? true else { return }
        play(assetName: "hyse-set-complete", volume: min(storedVolume, 0.65))
    }

    func preview(variant: RestSoundVariant, volume: Double, haptics: Bool) {
        previewID = UUID()
        if haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.75) }
        play(variant: variant, volume: volume)
    }

    func cancelPlayback() {
        guard let player else { return }
        player.stop()
        self.player = nil
        deactivateAudioSession()
    }

    private var storedVariant: RestSoundVariant {
        RestSoundVariant(rawValue: UserDefaults.standard.string(forKey: "restSoundVariant_v1") ?? "") ?? .alert
    }

    private var storedVolume: Double {
        let stored = UserDefaults.standard.object(forKey: "restSoundVolume_v1") as? Double ?? 0.8
        return min(max(stored, 0.1), 1)
    }

    private func play(variant: RestSoundVariant, volume: Double) {
        play(assetName: variant.assetName, volume: volume)
    }

    private func play(assetName: String, volume: Double) {
        guard let url = Bundle.main.url(forResource: assetName, withExtension: "caf") else {
            logger.error("Feedback sound asset is missing: \(assetName, privacy: .public)")
            AudioServicesPlaySystemSound(1007)
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // Keep the short timer cue audible while still mixing with music or podcasts.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self
            next.volume = Float(min(max(volume, 0.1), 1))
            next.numberOfLoops = 0
            next.prepareToPlay()
            player?.stop()
            player = next
            next.play()
        } catch {
            logger.error("Rest sound playback failed: \(error.localizedDescription, privacy: .public)")
            deactivateAudioSession()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.player = nil }
            self.deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
