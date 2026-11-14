import Foundation
@preconcurrency import UserNotifications

/// iOS owns delivery when the app is suspended or the phone is locked.
@MainActor
final class RestTimerNotificationController {
    static let shared = RestTimerNotificationController()
    static let identifierPrefix = "hyse.rest-timer."

    private let center = UNUserNotificationCenter.current()
    private let pendingIdentifierKey = "hyse.pendingRestTimerNotificationID_v1"
    private var revision = 0

    private var pendingIdentifier: String? {
        UserDefaults.standard.string(forKey: pendingIdentifierKey)
    }

    func schedule(timerID: UUID, end: Date) {
        revision += 1
        let expectedRevision = revision
        if let previous = pendingIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [previous])
            center.removeDeliveredNotifications(withIdentifiers: [previous])
        }
        UserDefaults.standard.removeObject(forKey: pendingIdentifierKey)
        guard UserDefaults.standard.object(forKey: "restNotificationEnabled_v1") as? Bool ?? true else { return }
        let identifier = Self.identifierPrefix + timerID.uuidString + "." + UUID().uuidString
        UserDefaults.standard.set(identifier, forKey: pendingIdentifierKey)
        Task {
            let settings = await center.notificationSettings()
            let allowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: allowed = true
            case .notDetermined:
                allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            case .denied: allowed = false
            @unknown default: allowed = false
            }
            guard allowed, expectedRevision == revision, pendingIdentifier == identifier else { return }
            let interval = end.timeIntervalSinceNow
            guard interval > 0 else { return }
            let content = UNMutableNotificationContent()
            content.title = LanguageStore.localizedString("training.rest_notification.title")
            content.body = LanguageStore.localizedString("training.rest_notification.body")
            if UserDefaults.standard.object(forKey: "restSoundEnabled_v1") as? Bool ?? true {
                let variant = RestSoundVariant(rawValue: UserDefaults.standard.string(forKey: "restSoundVariant_v1") ?? "") ?? .alert
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(variant.assetName).caf"))
            }
            content.userInfo = ["hyse_rest_timer_id": timerID.uuidString]
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            )
            try? await center.add(request)
            if expectedRevision != revision || pendingIdentifier != identifier {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
            }
        }
    }

    func cancel(removeDelivered: Bool = true) {
        revision += 1
        if let identifier = pendingIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            if removeDelivered {
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
            }
        }
        UserDefaults.standard.removeObject(forKey: pendingIdentifierKey)
    }
}
