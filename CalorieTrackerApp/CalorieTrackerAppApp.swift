import SwiftUI

@main
struct CalorieTrackerAppApp: App {
    @UIApplicationDelegateAdaptor(HyseAppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager()
    @StateObject private var languageStore = LanguageStore()
    @StateObject private var accountData = AccountDataStore()
    @StateObject private var premiumAccess = PremiumAccessStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(languageStore)
                .environmentObject(accountData)
                .environmentObject(premiumAccess)
                .environment(\.locale, Locale(identifier: languageStore.language.localeIdentifier))
                .hyseScreen()
        }
    }
}
