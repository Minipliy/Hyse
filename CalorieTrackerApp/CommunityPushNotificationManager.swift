import Foundation
import UIKit
@preconcurrency import UserNotifications

extension Notification.Name {
    static let hyseRemoteNotificationReceived = Notification.Name("hyse.remoteNotificationReceived")
}

@MainActor
final class CommunityPushNotificationManager {
    static let shared = CommunityPushNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let baseURL = HyseConfiguration.serverURL
    private let storedTokenKey = "communityPushDeviceToken_v1"
    private var pendingAuthToken = ""
    private var pendingAccountID = ""

    private init() {}

    func requestAndRegister(auth: AuthManager) async -> Bool {
        guard auth.isLoggedIn, !auth.token.isEmpty else { return false }
        let settings = await center.notificationSettings()
        let allowed: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            allowed = true
        case .notDetermined:
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            allowed = false
        @unknown default:
            allowed = false
        }
        guard allowed else { return false }
        pendingAuthToken = auth.token
        pendingAccountID = auth.accountID
        UIApplication.shared.registerForRemoteNotifications()
        if let token = UserDefaults.standard.string(forKey: storedTokenKey), !token.isEmpty {
            await register(token: token, authToken: auth.token)
        }
        return true
    }

    func syncIfEnabled(_ enabled: Bool, auth: AuthManager) {
        guard enabled, auth.isLoggedIn, !auth.token.isEmpty else { return }
        Task { _ = await requestAndRegister(auth: auth) }
    }

    func disable(auth: AuthManager) async {
        guard auth.isLoggedIn, !auth.token.isEmpty else { return }
        let token = UserDefaults.standard.string(forKey: storedTokenKey) ?? ""
        await updateDevice(token: token, enabled: false, authToken: auth.token)
    }

    func received(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: storedTokenKey)
        guard !pendingAuthToken.isEmpty, !pendingAccountID.isEmpty else { return }
        let authToken = pendingAuthToken
        Task { await register(token: token, authToken: authToken) }
    }

    private func register(token: String, authToken: String) async {
        await updateDevice(token: token, enabled: true, authToken: authToken)
    }

    private func updateDevice(token: String, enabled: Bool, authToken: String) async {
        guard let url = URL(string: baseURL + "/api/hyse/push-devices") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
#if DEBUG
        let environment = "sandbox"
#else
        let environment = "production"
#endif
        request.httpBody = try? JSONEncoder().encode([
            "device_token": token,
            "environment": environment,
            "enabled": enabled ? "true" : "false"
        ])
        _ = try? await URLSession.shared.data(for: request)
    }
}

final class HyseAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in CommunityPushNotificationManager.shared.received(deviceToken: deviceToken) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix(RestTimerNotificationController.identifierPrefix) {
            // The active workout plays its own cue. A second system sound here
            // would duplicate it while the app is in the foreground.
            completionHandler([])
            return
        }
        publish(notification, openCenter: false)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        publish(response.notification, openCenter: true)
        completionHandler()
    }

    private func publish(_ notification: UNNotification, openCenter: Bool) {
        var userInfo = notification.request.content.userInfo
        // Remote pushes and local reminders use the same in-app notification
        // center. Local reminders simply have no destination to open.
        userInfo["hyse_open_notification_center"] = openCenter
        NotificationCenter.default.post(
            name: .hyseRemoteNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
    }
}
