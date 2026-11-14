import Foundation

@MainActor
final class AuthManager {
    var isLoggedIn = false
    var accountID = ""
    var token = ""
}

@main
@MainActor
enum StreakRewardsStoreTests {
    static func main() {
        let accountID = "rewards-test-\(UUID().uuidString)"
        let scope = "account_\(accountID)"
        defer {
            for prefix in ["streak_rewards_", "streak_rewards_updated_", "streak_rewards_pending_"] {
                UserDefaults.standard.removeObject(forKey: "\(prefix)\(scope)_v1")
            }
        }

        let store = StreakRewardsStore()
        store.activate(accountID: accountID) // First account launch has no local or cloud snapshot.
        let now = Date()
        let today = StreakTracker.dayKey(for: now)

        store.reconcile(nutritionActivityDays: [today], workoutDates: [], now: now)
        expect(store.iceCrystals == 10, "first food entry is rewarded before cloud hydration")
        store.reconcile(nutritionActivityDays: [today], workoutDates: [], now: now)
        expect(store.iceCrystals == 10, "second food entry does not award again")

        store.reconcile(nutritionActivityDays: [today], workoutDates: [now], now: now)
        expect(store.iceCrystals == 30, "first completed workout adds 20 crystals")
        store.reconcile(nutritionActivityDays: [today], workoutDates: [now, now], now: now)
        expect(store.iceCrystals == 30, "second workout does not award again")

        let restored = StreakRewardsStore()
        restored.activate(accountID: accountID)
        restored.reconcile(nutritionActivityDays: [today], workoutDates: [now], now: now)
        expect(restored.iceCrystals == 30, "receipts and balance survive a new store instance")
        print("Streak reward store tests passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
